-- RE4-style walking while aiming.
-- Findings (probed in game, see docs/AI_CONTEXT.md):
--  * The aim state machine only has the forward aim-walk cycle; it plays whenever the
--    character's StickX/StickY properties are non-zero, without moving Caroline.
--  * The game only moves her through SetStick*Value, turning her towards the stick first.
--  * The weapon's aim-walk sequence (Nailgun: Nailer_Walk_Aim, same hand pose as the native
--    cycle) played backwards as a slot montage is a clean backpedal with the weapon raised.
--    side_step_Left/Right play the same way. Caroline's back_pedal lowers the weapon and
--    turns her head, so it is only the fallback for weapons without a known aim walk.
--  * Negative GlobalAnimRateScale must not be used: it froze and stretched her spine.
--  * CharacterMovement keeps a velocity written from Lua while aiming once ground friction
--    and braking are zero. Moving that way is smooth (the engine follows floors and steps
--    in its own tick); teleporting the actor each frame made the camera judder.
-- So camera.lua holds the game's stick input at zero and keeps Caroline facing the
-- crosshair; this module picks the animation and drives the movement velocity.
local M={}
local C='/Game/Characters/Caroline/Animations/'
local BACK_PEDAL=C..'Animations_Rig/back_pedal.back_pedal'
M.sequences={
    left=C..'Animations_Rig/side_step_Left.side_step_Left',
    right=C..'Animations_Rig/side_step_Right.side_step_Right',
}
-- Aim-walk sequence per weapon ID keyword (checked in order), played reversed to backpedal.
-- These five are the only aim-walk sequences in the game files; IDs are matched loosely
-- because the game's own names vary (class BP_HandCanon, folder Ranged/Machinegun).
local AUTO=C..'5_Automatic_Nailer/Automatic_Nailer_Aim_Walk.Automatic_Nailer_Aim_Walk'
M.aimWalks={
    {{'auto','nail'},AUTO},
    {{'machine'},AUTO},
    {{'nail'},C..'Nailer/Nailer_Walk_Aim.Nailer_Walk_Aim'},
    {{'canon'},C..'HandCanon/New_Anims/HandCannon_Walk_aim.HandCannon_Walk_aim'},
    {{'cannon'},C..'HandCanon/New_Anims/HandCannon_Walk_aim.HandCannon_Walk_aim'},
    {{'hammer'},C..'4_Hammer/Hammer_Aim_Walk.Hammer_Aim_Walk'},
    {{'crowbar'},C..'Crowbar/NewAnim/Crowbar_Walk_Aim.Crowbar_Walk_Aim'},
}
-- Ground speed of each animation at play rate 1 (planted-foot measurement).
M.animSpeed={forward=96,back=92,left=104,right=104}

-- Returns the backpedal sequence path for a weapon ID and whether it plays reversed.
function M.backSequence(weaponId)
    local id=tostring(weaponId or ''):lower()
    for _,entry in ipairs(M.aimWalks) do
        local all=true
        for _,word in ipairs(entry[1]) do if not id:find(word,1,true) then all=false end end
        if all then return entry[2],true end
    end
    return BACK_PEDAL,false
end

-- Pure plan from the left stick (lx right, ly forward, already dead-zoned) and camera yaw.
-- Returns the world direction, the animation (forward/back/left/right), its play rate and
-- the ground speed (cm/s) that keeps the feet planted.
function M.plan(cfg,lx,ly,cameraYaw)
    local magnitude=math.min(1,math.sqrt(lx*lx+ly*ly))
    if magnitude<0.05 then return nil end
    local y=math.rad(cameraYaw)
    local fx,fy=math.cos(y),math.sin(y)
    local rx,ry=-math.sin(y),math.cos(y)
    local dx,dy=fx*ly+rx*lx,fy*ly+ry*lx
    local length=math.sqrt(dx*dx+dy*dy)
    dx,dy=dx/length,dy/length
    -- Angle from straight ahead: <=50 walks, >=130 backpedals, otherwise side steps.
    local angle=math.deg(math.atan(lx,ly))
    local anim
    if math.abs(angle)<=50 then anim='forward'
    elseif math.abs(angle)>=130 then anim='back'
    else anim=lx>0 and 'right' or 'left' end
    local scale=(anim=='forward' and 1) or (anim=='back' and (cfg.aimBackSpeed or 0.9)) or (cfg.aimSideSpeed or 0.85)
    local rate=math.max(0.45,magnitude)*scale
    local speed=M.animSpeed[anim]*rate
    if anim=='forward' then speed=(cfg.aimWalkSpeed or 96)*rate end
    return {dx=dx,dy=dy,anim=anim,rate=rate,speed=speed,stick=anim=='forward' and rate or 0}
end

-- Plays the backpedal/side-step sequences as looping dynamic montages on one slot.
-- Every engine argument is checked first: a nil object or name crashes UE4SS natively.
local Animator={}
Animator.__index=Animator
function M.animator(cfg,log)
    return setmetatable({cfg=cfg,log=log or function() end,assets={},current=nil,montage=nil,rate=nil,failed=false},Animator)
end
local function valid(o) return o~=nil and o.IsValid~=nil and o:IsValid() end
function Animator:asset(path)
    local a=self.assets[path]
    if a~=nil then return a or nil end
    local found=StaticFindObject(path)
    if not valid(found) and LoadAsset then pcall(function() found=LoadAsset(path) end) end
    if valid(found) then self.assets[path]=found else self.assets[path]=false;self.log('Aim walk animation missing: '..path) end
    return valid(found) and found or nil
end
function Animator:instance(p)
    local inst=p.Mesh:GetAnimInstance()
    return valid(inst) and inst or nil
end
function Animator:choose(p,anim)
    if anim~='back' then return M.sequences[anim],false end
    local id=''
    pcall(function() id=p.currentWeaponID:ToString() end)
    local path,reverse=M.backSequence(id)
    if id~=self.weapon then
        self.weapon=id
        self.log('Aim walk backpedal for '..(id~='' and id or 'unknown weapon')..': '..path:match('[^.]+$')..(reverse and ' (reversed)' or ''))
    end
    return path,reverse
end
-- anim: forward/back/left/right or nil (standing / busy). Returns true while a montage owns
-- the legs (the forward aim-walk cycle must then stay off).
function Animator:update(p,anim,rate)
    if self.failed then return false end
    local ok,res=pcall(function()
        local want=(anim=='back' or anim=='left' or anim=='right') and anim or nil
        local inst=self:instance(p)
        if not inst then self.current=nil;self.montage=nil;return false end
        local slot=FName(self.cfg.aimWalkSlot or 'DefaultSlot')
        if want~=self.current or (want and not (valid(self.montage) and inst:Montage_IsPlaying(self.montage))) then
            if self.current then inst:StopSlotAnimation(0.2,slot) end
            self.current=nil;self.montage=nil;self.rate=nil
            if want then
                local path,reverse=self:choose(p,want)
                local seq=self:asset(path)
                if not seq then return false end
                local length=seq:GetPlayLength()
                if not length or length<=0.1 then return false end
                local m
                if reverse then m=inst:PlaySlotAnimationAsDynamicMontage(seq,slot,0.2,0.2,-rate,1000,0.0,length*0.98)
                else m=inst:PlaySlotAnimationAsDynamicMontage(seq,slot,0.2,0.2,rate,1000,-1.0,0.0) end
                if not valid(m) then return false end
                self.current=want;self.montage=m;self.rate=rate;self.reverse=reverse;self.length=length
            end
        end
        if self.current then
            if math.abs((self.rate or 0)-rate)>0.02 then
                inst:Montage_SetPlayRate(self.montage,self.reverse and -rate or rate);self.rate=rate
            end
            -- A reversed montage does not loop by itself: wrap just before the start.
            if self.reverse then
                local pos=inst:Montage_GetPosition(self.montage)
                if pos<=0.04 then inst:Montage_SetPosition(self.montage,self.length-0.04+pos) end
            end
        end
        return self.current~=nil
    end)
    if not ok then self.failed=true;self.log('Aim walk animation disabled after error: '..tostring(res));return false end
    return res
end
function Animator:stop(p)
    if not self.current then return end
    self.current=nil;self.montage=nil;self.rate=nil
    pcall(function()
        local inst=self:instance(p)
        if inst then inst:StopSlotAnimation(0.2,FName(self.cfg.aimWalkSlot or 'DefaultSlot')) end
    end)
end

-- Movement through CharacterMovement: friction/braking off so a written velocity holds,
-- no walking off ledges. Originals are restored by M.release.
local saved=nil
local function ease(a,b,rate,dt) return a+(b-a)*math.min(1,rate*dt) end
function M.drive(p,vx,vy,dt)
    local m=p.CharacterMovement
    if not saved then
        saved={movement=m,friction=m.GroundFriction,braking=m.BrakingDecelerationWalking,ledges=m.bCanWalkOffLedges}
        m.GroundFriction=0;m.BrakingDecelerationWalking=0;m.bCanWalkOffLedges=false
    end
    local v=m.Velocity
    -- Short ease in/out so starts and stops are not instantaneous.
    m.Velocity={X=ease(v.X,vx,14,dt),Y=ease(v.Y,vy,14,dt),Z=v.Z}
end
function M.release(p)
    if not saved then return end
    local s=saved
    saved=nil
    pcall(function()
        local m=s.movement
        if not valid(m) then return end
        m.GroundFriction=s.friction;m.BrakingDecelerationWalking=s.braking;m.bCanWalkOffLedges=s.ledges
        local v=m.Velocity
        m.Velocity={X=0,Y=0,Z=v.Z}
    end)
end
function M.driving() return saved~=nil end
return M
