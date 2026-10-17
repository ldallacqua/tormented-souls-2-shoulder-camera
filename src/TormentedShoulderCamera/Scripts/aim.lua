-- Free aim and crosshair while aiming in the shoulder view.
-- Player ammo (BP_BaseAmmo) turns towards the game's target, or forward, with
-- K2_SetActorRotation and fires LineTraceMulti from the muzzle. Both native calls are
-- adjusted so the shot goes to the point under the crosshair. Spread relative to the
-- game's own direction is kept. Nothing changes unless camera.lua arms it each frame.
-- It also bends Caroline's torso towards the crosshair and marks where shots land.
local UEHelpers=require('UEHelpers')
local directory=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])')
local crosshair=dofile(directory..'crosshair.lua')
local impact=dofile(directory..'impact.lua')
local M={}
local cfg,log
local armed=false
local pawn=nil
local point,dir=nil,nil -- Point under the crosshair and camera forward, refreshed per frame.
local ray=nil -- Camera ray through the crosshair, level with Caroline: where hitscan shots start.
local onEnemy=false
local channel=0 -- ETraceTypeQuery of the last player shot; Visibility until the first shot.
local adjusted=0
local failed=false
-- Native hooks fire for every actor in the game, so they are registered on the first aim
-- and gated by `armed`. They stay registered: UE4SS only removes a native hook after its
-- next call, and a pending removal still runs its pre-callback once.
local shotHooks={}
local shotHandlers={}
local probes={} -- Diagnostic: classes seen while aiming (once each), to learn each weapon's shot path.
local probeCount=0
local ammoClass='/Game/GameplaySystems/WeaponSystem/Ammo/BP_BaseAmmo.BP_BaseAmmo_C'
local noColor={R=0,G=0,B=0,A=0}
local SPREAD=math.cos(math.rad(20)) -- Wider deviations are not spread: the shot ignored the base direction.
local RANGE=6000
-- Torso pitch (probed): the character's RotationToAim.pitch drives four ModifyBone nodes on
-- spine_02 in her anim blueprint, 1:1, clamped there to -30..+40 degrees. It is how the game
-- bends her towards a target on the floor; free aim writes it from the crosshair point.
M.TORSO_MIN,M.TORSO_MAX=-30,40
local TORSO_PIVOT=40 -- Height of her hands above the actor origin when aiming level.
-- Steeper shots are raised to this pitch so they cannot land at her feet.
M.SHOT_MIN_PITCH=-50
local torso=nil -- Current eased torso pitch while free aim owns RotationToAim.
local torsoPawn=nil
local function valid(o) return o and o:IsValid() end
local function vec(v) return {X=v.X,Y=v.Y,Z=v.Z} end
local function add(a,b) return {X=a.X+b.X,Y=a.Y+b.Y,Z=a.Z+b.Z} end
local function sub(a,b) return {X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z} end
local function scale(a,s) return {X=a.X*s,Y=a.Y*s,Z=a.Z*s} end
local function dot(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
local function cross(a,b) return {X=a.Y*b.Z-a.Z*b.Y,Y=a.Z*b.X-a.X*b.Z,Z=a.X*b.Y-a.Y*b.X} end
local function len(a) return math.sqrt(dot(a,a)) end
local function norm(a) local l=len(a);if l<1e-6 then return nil end return scale(a,1/l) end
-- Rotates v by the rotation taking unit vector a onto unit vector b (Rodrigues).
local function rotateOnto(v,a,b)
    local k=cross(a,b);local s=len(k);local c=dot(a,b)
    if s<1e-6 then return c>0 and v or scale(v,-1) end
    k=scale(k,1/s)
    return add(add(scale(v,c),scale(cross(k,v),s)),scale(k,dot(k,v)*(1-c)))
end
-- This build exposes the rotator pitch as lowercase `pitch`.
local function fromRotator(r)
    local p,y=math.rad(r.pitch or 0),math.rad(r.Yaw)
    return {X=math.cos(p)*math.cos(y),Y=math.cos(p)*math.sin(y),Z=math.sin(p)}
end
local function toRotator(d,roll)
    return {pitch=math.deg(math.asin(math.max(-1,math.min(1,d.Z)))),Yaw=math.deg(math.atan(d.Y,d.X)),Roll=roll or 0}
end
M._math={rotateOnto=rotateOnto,fromRotator=fromRotator,toRotator=toRotator}

-- Torso pitch from her hands (origin) to the aim point, within the anim blueprint's range.
function M.torsoPitch(origin,target)
    local d=sub(target,origin)
    local h=math.sqrt(d.X*d.X+d.Y*d.Y)
    if h<1 then return 0 end
    return math.max(M.TORSO_MIN,math.min(M.TORSO_MAX,math.deg(math.atan(d.Z,h))))
end
-- Raises a unit direction that points down more steeply than SHOT_MIN_PITCH.
function M.limitShot(a)
    local minZ=math.sin(math.rad(M.SHOT_MIN_PITCH))
    if a.Z>=minZ then return a end
    local h=math.sqrt(a.X*a.X+a.Y*a.Y)
    if h<1e-6 then return nil end
    local c=math.cos(math.rad(M.SHOT_MIN_PITCH))
    return {X=a.X/h*c,Y=a.Y/h*c,Z=minZ}
end

local function hitActor(hit)
    local ok,c=pcall(function() return hit.Component:Get() end)
    if ok and valid(c) then return c:GetOwner() end
    return nil
end
-- Ray from the screen centre. It starts level with Caroline so nothing between the
-- camera and her (railings, the wall the camera backs against) can catch it.
local function trace(pc,p)
    local cm=pc.PlayerCameraManager
    if not valid(cm) then return nil end
    local loc=vec(cm:GetCameraLocation())
    local fwd=fromRotator(cm:GetCameraRotation())
    local skip=math.max(0,dot(sub(vec(p:K2_GetActorLocation()),loc),fwd))
    local start,finish=add(loc,scale(fwd,skip)),add(loc,scale(fwd,skip+RANGE))
    local hit={}
    local blocked=UEHelpers.GetKismetSystemLibrary():LineTraceSingle(p,start,finish,channel,false,{p},0,hit,true,noColor,noColor,0)
    if blocked then return vec(hit.ImpactPoint),fwd,hitActor(hit),start end
    return finish,fwd,nil,start
end

local function register(list,path,fn)
    local ok,a,b=pcall(RegisterHook,path,fn)
    if ok then list[#list+1]={path,a,b} else log('Hook unavailable: '..path..' '..tostring(a)) end
end
local function unregister(list)
    for _,h in ipairs(list) do pcall(UnregisterHook,h[1],h[2],h[3]) end
    return {}
end
local function probe(kind,object)
    if probeCount>=24 or not valid(object) or (valid(pawn) and object:GetAddress()==pawn:GetAddress()) then return end
    local ok,class=pcall(function() return object:GetClass():GetFName():ToString() end)
    class=ok and class or object:GetFullName()
    if probes[kind..class] then return end
    probes[kind..class]=true;probeCount=probeCount+1
    log('Aim probe '..kind..': '..class)
end
local function bendTorso(p,dt)
    local r=p.RotationToAim
    if not r then return end -- Another playable character without the spine bend.
    local want=M.torsoPitch(add(vec(p:K2_GetActorLocation()),{X=0,Y=0,Z=TORSO_PIVOT}),point)
    torso=torso or r.pitch or 0
    torso=torso+(want-torso)*math.min(1,12*dt)
    p.RotationToAim={pitch=torso,Yaw=r.Yaw,Roll=r.Roll}
    torsoPawn=p
end
local function straightenTorso()
    local p=torsoPawn
    torso=nil;torsoPawn=nil
    if not valid(p) then return end
    pcall(function() local r=p.RotationToAim;p.RotationToAim={pitch=0,Yaw=r.Yaw,Roll=r.Roll} end)
end
function M.update(pc,p,dt)
    pawn=p;armed=true
    if cfg.freeAim and #shotHooks==0 then
        for _,h in ipairs(shotHandlers) do register(shotHooks,h[1],h[2]) end
    end
    local ok,pt,fwd,actor,origin=pcall(trace,pc,p)
    if not ok then
        if not failed then failed=true;log('Aim trace unavailable: '..tostring(pt)) end
        point=nil;crosshair.update(pc,cfg.crosshair,false)
        return
    end
    point,dir,ray=pt,fwd,origin
    onEnemy=valid(actor) and actor:GetAddress()~=p:GetAddress() and actor:IsA('/Script/Engine.Pawn') or false
    crosshair.update(pc,cfg.crosshair,onEnemy)
    if cfg.freeAim and cfg.torsoAim~=false then
        local okBend,err=pcall(bendTorso,p,math.min(dt or 0.016,0.05))
        if not okBend then cfg.torsoAim=false;straightenTorso();log('Torso aim disabled after error: '..tostring(err)) end
    end
    if cfg.impactMarks then
        local okMarks,err=pcall(impact.flush,cfg,p,channel,log)
        if not okMarks then cfg.impactMarks=false;impact.clear();log('Impact marks disabled after error: '..tostring(err)) end
    end
end
function M.clear()
    if armed then crosshair.update(nil,false) end
    if torsoPawn then straightenTorso() end
    impact.clear()
    armed=false;onEnemy=false;point=nil;ray=nil
end

-- Direction from a muzzle to the crosshair point. A wall right in front of the muzzle
-- would bend the shot sideways, so fall back to the camera direction.
local function aimFrom(origin)
    local a=norm(sub(point,origin))
    if not a or dot(a,dir)<0.5 then a=dir end
    return M.limitShot(a) or a
end
local function ammoOf(kind,object)
    if not armed or not cfg.freeAim or not point or not valid(pawn) then return nil end
    probe(kind,object)
    if not valid(object) or not object:IsA(ammoClass) then return nil end
    return object
end
-- A failing hook switches its feature off for the session instead of erroring every call.
local function guard(feature,fn)
    return function(...)
        local ok,err=pcall(fn,...)
        if not ok then cfg[feature]=false;log(feature..' disabled after error: '..tostring(err)) end
    end
end
local function report(kind,from,to)
    adjusted=adjusted+1
    if adjusted<=6 or adjusted%200==0 then
        log(string.format('Free aim %s #%d: %.1f deg',kind,adjusted,math.deg(math.acos(math.max(-1,math.min(1,dot(from,to)))))))
    end
end

function M.init(config,logger)
    cfg,log=config,logger
    -- Projectile orientation: also covers ammo that flies instead of tracing.
    shotHandlers[#shotHandlers+1]={'/Script/Engine.Actor:K2_SetActorRotation',guard('freeAim',function(context,newRotation)
        local ammo=ammoOf('rotation',context:get())
        if not ammo then return end
        local r=newRotation:get()
        local requested=fromRotator(r)
        -- Without a locked target the game aims along Caroline's facing; keep pellet spread
        -- around it. With a target, the requested direction is the base itself.
        local base=requested
        local target=nil
        pcall(function() target=pawn.CurrentTarget end)
        if not valid(target) then
            local f=fromRotator({pitch=0,Yaw=pawn:K2_GetActorRotation().Yaw})
            if dot(requested,f)>SPREAD then base=f end
        end
        local a=aimFrom(vec(ammo:K2_GetActorLocation()))
        local shot=rotateOnto(requested,base,a)
        newRotation:set(toRotator(shot,r.Roll))
        if cfg.impactMarks then impact.queue(vec(ammo:K2_GetActorLocation()),shot,RANGE,ammo:GetAddress(),'flight') end
        report('rotation',requested,shot)
    end)}
    -- Hitscan, third-person style: the game's damage trace is moved onto the camera ray through
    -- the crosshair (starting level with Caroline), so whatever is under the crosshair is hit.
    -- Aiming from the muzzle missed: it sits beside the camera ray, and surfaces or enemy capsules
    -- that ignore the crosshair trace's channel bent the muzzle line away (tested in game).
    -- The game's range is kept from the muzzle; pellet spread is kept around the crosshair.
    shotHandlers[#shotHandlers+1]={'/Script/Engine.KismetSystemLibrary:LineTraceMulti',guard('freeAim',function(_,world,start,finish,traceChannel)
        local ammo=ammoOf('trace',world:get())
        if not ammo then return end
        channel=traceChannel:get()
        local s,e=vec(start:get()),vec(finish:get())
        local d=sub(e,s);local length=len(d)
        if length<1 then return end
        d=scale(d,1/length)
        local forward=norm(vec(ammo:GetActorForwardVector()))
        -- After the rotation hook the actor already faces the crosshair: keep its spread.
        local base=(forward and dot(d,forward)>SPREAD) and forward or d
        local origin,aim=s,aimFrom(s)
        if ray then origin,aim=ray,M.limitShot(dir) or dir end
        local shot=rotateOnto(d,base,aim)
        length=length+math.max(0,dot(sub(s,origin),aim))
        start:set(origin)
        finish:set(add(origin,scale(shot,length)))
        if cfg.impactMarks then impact.queue(origin,shot,length,ammo:GetAddress(),'trace') end
        report('trace',d,shot)
    end)}
    crosshair.init(logger)
end
function M.shutdown()
    M.clear()
    shotHooks=unregister(shotHooks)
    crosshair.shutdown()
end
return M
