local UEHelpers = require('UEHelpers')
local directory=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])')
local shortcuts=dofile(directory..'input.lua')
local collision=dofile(directory..'collision.lua')
local aim=dofile(directory..'aim.lua')
local motion=dofile(directory..'motion.lua')
local aimwalk=dofile(directory..'aimwalk.lua')
local M = { enabled=true, fault=false }
local cfg=dofile(directory..'config.lua')
M.enabled=cfg.enabled
assert(cfg.deadzone>=0 and cfg.deadzone<1,'deadzone must be >=0 and <1')
local pawn, controller, boom, camera, original, originalView
local yaw, pitch, side=0,-9,1
local active=false
-- True while a held reason let the game show its own close-up; the shoulder rig stays ready.
local handedOff=false
local lastReason=false
-- Last redirect, kept briefly: a puzzle may request its close-up just before the flag is set.
local recent=nil
local clock=0
local mode='gameplay'
local modeLog=''
local keys={}
local viewHookPre,viewHookPost
local extraHooks={}
local movementCorrections={}
-- Zone cameras whose AutoNorthLocal was switched off while the shoulder view owns movement.
local railPatched={}
local viewHookPath='/Script/Engine.PlayerController:SetViewTargetWithBlend'
local currentFov=cfg.fov
local function valid(o) return o and o:IsValid() end
local function log(s) print('[ShoulderCamera] '..s..'\n') end
aim.init(cfg,log)
-- Backpedal/side-step montages for the aim walk.
local walker=aimwalk.animator(cfg,log)
local function vec(v) return {X=v.X,Y=v.Y,Z=v.Z} end
local function rot(v) return {pitch=v.pitch or v.Pitch,Yaw=v.Yaw,Roll=v.Roll} end
local function key(name)
    if not keys[name] then keys[name]={KeyName=FName(name)} end
    return keys[name]
end
local function axis(pc,name,curve)
    local v=pc:GetInputAnalogKeyState(key(name))
    if math.abs(v)<cfg.deadzone then return 0 end
    local scaled=(math.abs(v)-cfg.deadzone)/(1-cfg.deadzone)
    return (v<0 and -1 or 1)*scaled^(curve or 1)
end
-- Rising edge of a gamepad button, polled once per frame.
local held={}
local function pressed(pc,name)
    local down=pc:IsInputKeyDown(key(name))
    local edge=down and not held[name]
    held[name]=down
    return edge
end
local function ease(current,target,speed,dt) return current+(target-current)*(1-math.exp(-speed*dt)) end
-- Blended framing: aiming and shoulder swaps glide instead of snapping.
local blend={distance=cfg.distance,shoulder=cfg.shoulder,height=cfg.height}
-- Quick turn: camera yaw still to rotate, and the movement yaw kept until the stick is released.
local turnLeft=0
local moveLatch=nil
local function moveYaw() return moveLatch or yaw end
local wasAiming=false
-- Aiming holds the game's movement input at zero; the left stick fine-aims instead.
local aimHold=false
local stickLogged=false
-- RE4-style aim walk (aimwalk.lua): the forward walk-cycle stick value we drive.
local walkStick=nil
local lastYaw=nil
-- Primitive components switched to OwnerNoSee while the camera is too close to the head.
local hiddenParts=nil
local primitiveClass=nil
local hideFailed=false
local function setCharacterHidden(p,hide)
    if hide==(hiddenParts~=nil) then return end
    if not hide then
        for _,c in ipairs(hiddenParts) do if valid(c) then c:SetOwnerNoSee(false) end end
        hiddenParts=nil
        return
    end
    if not valid(p) or hideFailed then return end
    primitiveClass=primitiveClass or StaticFindObject('/Script/Engine.PrimitiveComponent')
    hiddenParts={}
    -- Cosmetic only: a failure here must never disable the camera mod.
    local ok,err=pcall(function()
        local list=p:K2_GetComponentsByClass(primitiveClass)
        local function hide(c)
            -- Elements arrive wrapped (RemoteUnrealParam); unwrap when possible.
            local ok,inner=pcall(function() return c:get() end)
            if ok and inner then c=inner end
            -- Only primitives: attached lights (flashlight/lighter) must keep illuminating.
            if valid(c) and not c.bOwnerNoSee then hiddenParts[#hiddenParts+1]=c;c:SetOwnerNoSee(true) end
        end
        -- UE4SS returns TArray results as a plain Lua table; accept a TArray too.
        if type(list)=='table' then for _,c in ipairs(list) do hide(c) end
        elseif list and list.ForEach then list:ForEach(function(_,e) hide(e) end) end
    end)
    if not ok then
        hideFailed=true
        for _,c in ipairs(hiddenParts) do pcall(function() c:SetOwnerNoSee(false) end) end
        hiddenParts=nil
        log('Character hiding unavailable: '..tostring(err))
    end
end
local function restore()
    aim.clear()
    setCharacterHidden(pawn,false)
    local wasActive=active
    if railPatched then
        for _,rail in pairs(railPatched) do if valid(rail) then rail.AutoNorthLocal=true end end
    end
    railPatched={}
    if wasActive and valid(pawn) and original then
        pawn.TankMode=original.TankMode
        pawn.AutoNorth=original.AutoNorth
        pawn.bUseControllerRotationYaw=original.bUseControllerRotationYaw
        if valid(boom) then for k,v in pairs(original.boom) do boom[k]=v end end
        if valid(camera) then for k,v in pairs(original.camera) do camera[k]=v end end
        local gi=UEHelpers.GetGameInstance()
        local target=valid(gi) and gi.CurrentCamera or nil
        if not valid(target) then target=originalView end
        if valid(controller) and valid(target) and controller:GetViewTarget():GetAddress()==pawn:GetAddress() then
            controller:SetViewTargetWithBlend(target,0.0,0,0.0,false)
        end
    end
    if walkStick and valid(pawn) then walker:stop(pawn);pcall(function() pawn.StickX=0;pawn.StickY=0 end) end
    aimwalk.release(pawn)
    walkStick=nil
    active=false;handedOff=false;recent=nil;aimHold=false
    turnLeft=0;moveLatch=nil
end
function M.shutdown()
    restore()
    shortcuts.restore()
    if viewHookPre then UnregisterHook(viewHookPath,viewHookPre,viewHookPost);viewHookPre=nil end
    aim.shutdown()
    for _,h in ipairs(extraHooks) do UnregisterHook(h[1],h[2],h[3]) end
    extraHooks={}
end
-- Short interruptions keep the last shoulder view frozen instead of cutting to the fixed
-- room camera and back (the flash on return). The game can still take the view for its
-- own close-ups through SetViewTargetWithBlend; see the view hook. Long interactions where
-- Caroline moves (bIsCharacterInteracting, pushing) keep the native camera as before.
local holdReasons={pause=true,inventory=true,puzzle=true,preview=true,poi=true,text=true,
    isSolvingPuzzle=true,isInteractingWithPuzzleComp=true,isInteractingWithChildPuzzleComp=true,
    isInteractingWithPOI=true}
function M.mode_changed(value)
    mode=value
    if mode~='gameplay' and not holdReasons[mode] then restore() end
    log('Mode '..value)
end
function M.action(value)
    if value=='toggle' then M.enabled=not M.enabled; log('Enabled='..tostring(M.enabled)); if not M.enabled then restore() end end
    if value=='shoulder' then side=-side end
    if value=='recenter' and valid(pawn) then yaw=pawn:K2_GetActorRotation().Yaw;pitch=-9 end
end
local blockedFlags={'isInputDisabled','isSolvingPuzzle','isInteractingWithPuzzleComp','isInteractingWithChildPuzzleComp',
    'isInteractingWithPOI','bIsCharacterInteracting','bIsInsideInteraction','climbUp','climbDown','isFallen'}
local function blocked(pc,p)
    if mode~='gameplay' then return mode end
    if p.Health<=0 then return 'dead' end
    -- A flag that needs the native camera wins over one that only holds the view.
    local hold=nil
    for _,name in ipairs(blockedFlags) do
        if p[name] then
            if not holdReasons[name] then return name end
            hold=hold or name
        end
    end
    local ui=pc.UIManager
    if valid(ui) then
        if ui.bIsMainMenuOpen or ui.bIsSaveScreenMenuOpen then return 'menu' end
        if ui.bIsPauseMenuOpen or ui.bGameIsPaused then return hold or 'pause' end
    end
    return hold
end
local function syncMovement(source)
    if not M.enabled or M.fault or not active or not valid(pawn) or not valid(controller) then return end
    local desired=moveYaw()
    local function off(name) return math.abs((pawn[name].Yaw-desired+180)%360-180) end
    local delta=math.max(off('NorthCamera'),off('RAfterCameraChange'),off('Current Camera Rotator'),off('Last Camera Rotator'))
    -- Cheap exit first: rail cameras call this from every tick.
    if delta<=0.5 and not pawn.AutoNorth and not pawn.ChangeNorth then return end
    if blocked(controller,pawn) then return end
    -- ChangeNorth alone is set every frame by the game and is harmless once the yaw matches.
    if delta>1 or pawn.AutoNorth then
        movementCorrections[source]=(movementCorrections[source] or 0)+1
        local count=movementCorrections[source]
        if count<=3 or count%1000==0 then
            log(string.format('Movement reference correction #%d at %s: north=%.1f after=%.1f cur=%.1f desired=%.1f auto=%s change=%s',
                count,source,pawn.NorthCamera.Yaw,pawn.RAfterCameraChange.Yaw,pawn['Current Camera Rotator'].Yaw,desired,
                tostring(pawn.AutoNorth),tostring(pawn.ChangeNorth)))
        end
    end
    local r={pitch=0,Yaw=desired,Roll=0}
    pawn.NorthCamera=r;pawn['Last Camera Rotator']=r;pawn['Current Camera Rotator']=r;pawn.RAfterCameraChange=r
    pawn.AutoNorth=false;pawn.ChangeNorth=false
end
-- While aiming in the shoulder view the left stick aims instead of moving. The game would
-- otherwise turn Caroline towards the stick while the shoulder aim turns her back to the
-- camera every frame, which broke the aiming animation.
for _,name in ipairs({'SetStickXValue','SetStickYValue','SetStickXValueDPAD','SetStickYValueDPAD'}) do
    local path='/Script/TormentedSouls2.TormentedSouls2Character:'..name
    local ok,a,b=pcall(RegisterHook,path,function(context,value)
        if not valid(pawn) or context:get():GetAddress()~=pawn:GetAddress() then return end
        if aimHold and value then
            if not stickLogged and value:get()~=0 then stickLogged=true;log('Aiming: movement input held for the aim') end
            value:set(0.0)
        end
        syncMovement(name)
    end,function(context)
        -- The game just stored the zeroed input; the walk cycle reads these properties.
        if walkStick and valid(pawn) and context:get():GetAddress()==pawn:GetAddress() then
            pawn.StickX=0;pawn.StickY=walkStick
        end
    end)
    if ok then extraHooks[#extraHooks+1]={path,a,b} else log('Stick hook unavailable: '..name) end
end
local railLogged={}
local function railHook(source)
    return function(context)
        -- With AutoNorthLocal, the zone camera writes its own yaw into NorthCamera and sets
        -- AutoNorth/ChangeNorth every tick; the next stick change then flips movement ~180 deg.
        local rail=context:get()
        if active and M.enabled and not M.fault and rail.AutoNorthLocal then
            railPatched[rail:GetAddress()]=rail
            rail.AutoNorthLocal=false
            local name=rail:GetFName():ToString()
            if not railLogged[name] then railLogged[name]=true;log('Zone camera AutoNorthLocal off: '..name) end
        end
        syncMovement(source)
    end
end
local blueprintHooks={
    {path='/Game/Tools/RailCamera/BP_RailCamera.BP_RailCamera_C:ReceiveTick',fn=railHook('Rail ReceiveTick')},
    {path='/Game/Tools/RailCamera/BP_RailCamera.BP_RailCamera_C:Delegate_On_Trigger',fn=railHook('Rail Delegate_On_Trigger')},
    -- Blueprint hooks run after the Blueprint body: the last chance before native movement in Tick.
    {path='/Game/Characters/BP_TormentedSoulCharacter.BP_TormentedSoulCharacter_C:ReceiveTick',fn=function(context)
        if valid(pawn) and context:get():GetAddress()==pawn:GetAddress() then syncMovement('CharacterTick') end
    end},
}
local hookRetry=0
-- Blueprint classes load with the first level, after this script starts at the main menu.
local function registerBlueprintHooks(dt)
    hookRetry=hookRetry-dt
    if hookRetry>0 then return end
    hookRetry=1
    for _,h in ipairs(blueprintHooks) do
        local fn=StaticFindObject(h.path)
        if fn:IsValid() and fn:GetAddress()~=h.address then
            local a,b=RegisterHook(h.path,h.fn)
            extraHooks[#extraHooks+1]={h.path,a,b}
            h.address=fn:GetAddress()
        end
    end
end
viewHookPre,viewHookPost=RegisterHook(viewHookPath,function(context,newTarget,blendTime)
    if not active or not M.enabled or M.fault or not valid(pawn) then return end
    local pc=context:get()
    if not valid(controller) or pc:GetAddress()~=controller:GetAddress() then return end
    local reason=blocked(pc,pawn)
    if reason and not holdReasons[reason] then return end
    local target=newTarget:get()
    if not valid(target) or target:GetAddress()==pawn:GetAddress() then return end
    local fixed=not target:IsA('/Script/CinematicCamera.CineCameraActor') and
        (target:IsA('/Script/Engine.CameraActor') or target:IsA('/Script/TormentedSouls2.RailCamera'))
    -- Pause/inventory only ever bring back the room camera. During interactions, a camera
    -- other than the room camera we replaced is the game's close-up and must be shown.
    if fixed and reason and reason~='pause' and reason~='inventory' then
        fixed=valid(originalView) and target:GetAddress()==originalView:GetAddress()
    end
    if fixed then
        if not reason then recent={target=target,previous=originalView,time=clock} end
        originalView=target
        newTarget:set(pawn)
        blendTime:set(0.0)
        handedOff=false
        syncMovement('ViewTarget')
        log('Redirected fixed camera '..target:GetFName():ToString())
    elseif reason then
        -- The shoulder components stay configured, so the return needs no warm-up.
        if not handedOff then log('Native camera during '..reason..': '..target:GetFName():ToString()) end
        handedOff=true
        -- OwnerNoSee would also hide Caroline from the close-up.
        setCharacterHidden(pawn,false)
    end
end)
local function bind(pc,p)
    restore()
    controller=pc;pawn=p;boom=p.CameraBoom;camera=p.FollowCamera
    if not valid(boom) or not valid(camera) then error('Character camera components unavailable') end
    original={TankMode=p.TankMode,AutoNorth=p.AutoNorth,bUseControllerRotationYaw=p.bUseControllerRotationYaw,boom={},camera={}}
    local bp={'TargetArmLength','SocketOffset','TargetOffset','ProbeSize','ProbeChannel','bDoCollisionTest','bUsePawnControlRotation',
        'bInheritPitch','bInheritYaw','bInheritRoll','bEnableCameraLag','bEnableCameraRotationLag','CameraLagSpeed','CameraLagMaxDistance',
        'bAbsoluteRotation','RelativeRotation','RelativeLocation'}
    for _,name in ipairs(bp) do
        local value=boom[name]
        if name=='SocketOffset' or name=='TargetOffset' or name=='RelativeLocation' then value=vec(value) end
        if name=='RelativeRotation' then value=rot(value) end
        original.boom[name]=value
    end
    for _,name in ipairs({'FieldOfView','bUsePawnControlRotation','bConstrainAspectRatio','RelativeLocation','RelativeRotation','bIsActive'}) do
        local value=camera[name]
        if name=='RelativeLocation' then value=vec(value) end
        if name=='RelativeRotation' then value=rot(value) end
        original.camera[name]=value
    end
    originalView=pc:GetViewTarget()
    yaw=p:K2_GetActorRotation().Yaw; pitch=-9
    log('Bound '..p:GetFullName())
    log(string.format('Original camera: arm=%.1f cam-relative=%.1f,%.1f,%.1f tank=%s view=%s',
        boom.TargetArmLength,camera.RelativeLocation.X,camera.RelativeLocation.Y,camera.RelativeLocation.Z,
        tostring(p.TankMode),originalView:GetFullName()))
    pcall(function()
        local ds = p.BPC_DarknessSystem
        local mat = p.DarknessSystem_Mat
        if valid(mat) then
            camera:AddOrUpdateBlendable(mat, 1.0)
            log('Attached darkness post-process material to FollowCamera')
        end
        if valid(ds) then
            ds.CurrentCamera = camera
        end
    end)
end
-- During an interaction hold, show the game's close-up if it asked for one we redirected
-- or recorded it as the current camera. Without one, the frozen shoulder view stays.
local function handOffCloseUp(pc)
    local target=nil
    if recent and clock-recent.time<0.5 then
        target=recent.target;originalView=recent.previous
    else
        local gi=UEHelpers.GetGameInstance()
        target=valid(gi) and gi.CurrentCamera or nil
    end
    recent=nil
    if not valid(target) or target:GetAddress()==pawn:GetAddress() then return end
    -- The room camera we replaced is not a close-up; the hook would redirect it anyway.
    if valid(originalView) and target:GetAddress()==originalView:GetAddress() then return end
    handedOff=true
    log('Close-up camera restored: '..target:GetFName():ToString())
    pc:SetViewTargetWithBlend(target,0.0,0,0.0,false)
end
function M.update(pc,dt)
    if M.fault then return end
    clock=clock+math.max(dt or 0,0)
    registerBlueprintHooks(dt)
    shortcuts.update(M.enabled,dt)
    local p=pc.Pawn
    if not valid(p) or not p:IsA('/Script/TormentedSouls2.TormentedSouls2Character') then restore();pawn=nil;return end
    if not valid(pawn) or p:GetAddress()~=pawn:GetAddress() then bind(pc,p) end
    local reason=blocked(pc,p)
    local label=reason or (M.enabled and 'shoulder' or 'disabled')
    if label~=lastReason then lastReason=label;log('State '..label) end
    if reason or not M.enabled then
        aim.clear()
        if walkStick then walkStick=nil;walker:stop(p) end
        aimwalk.release(p)
    end
    -- Freeze the shoulder view (pause, inventory, interactions) so resuming never exposes a fixed view.
    if M.enabled and active and reason and holdReasons[reason] then
        if not handedOff and reason~='pause' and reason~='inventory' then handOffCloseUp(pc) end
        return
    end
    if not M.enabled or reason then restore();return end
    handedOff=false
    pcall(function() if valid(pc.MyHUD) and not pc.MyHUD.bShowHUD then pc.MyHUD.bShowHUD=true end end)
    dt=math.min(math.max(dt,0),0.05)
    -- After a full restore the spring arm still holds the native transform; switching the
    -- view in the same frame can render it once. Configure now, switch on the next frame.
    local warming=not active
    if warming then collision.reset();motion.reset();lastYaw=nil end
    active=true
    local curve=cfg.stickCurve or 1
    local x,y=axis(pc,'Gamepad_RightX',curve),axis(pc,'Gamepad_RightY',curve)
    local aiming=p.isAiming and true or false
    if aiming~=wasAiming then wasAiming=aiming;log(aiming and 'Aim start' or 'Aim end') end
    if cfg.shoulderSwapButton and pressed(pc,cfg.shoulderSwapButton) then side=-side end
    -- Quick turn: stick held back + run/dodge. The movement yaw stays latched until the
    -- stick is released, so holding back keeps running away instead of turning again.
    local lx,ly=axis(pc,'Gamepad_LeftX'),axis(pc,'Gamepad_LeftY')
    local runPressed=pressed(pc,'Gamepad_FaceButton_Left')
    if cfg.quickTurn and not aiming and turnLeft==0 and runPressed and ly<-0.7 and math.abs(lx)<0.5 then
        moveLatch=moveLatch or yaw;turnLeft=180
    end
    if turnLeft>0 then
        local step=math.min(turnLeft,900*dt)
        yaw=(yaw+step)%360;turnLeft=turnLeft-step
    elseif moveLatch and lx*lx+ly*ly<0.04 then moveLatch=nil end
    local stickMult=aiming and (cfg.aimSensitivity or 0.6) or 1.0
    aimHold=aiming and cfg.aimWalk~=true
    local aimMove=aimHold and cfg.aimMove~=false
    if aimHold and not aimMove then
        -- Stand-still aiming: the left stick fine-aims.
        x=x+lx*(cfg.aimLeftStick or 0.7);y=y-ly*(cfg.aimLeftStick or 0.7)*(cfg.invertY and 1 or -1)
        p.StickX=0;p.StickY=0
    end
    yaw=(yaw+x*cfg.yawSpeed*stickMult*dt)%360
    -- Aiming allows a steeper look up; leaving it eases back to the exploration limit.
    -- Looking down is limited while aiming so the crosshair never sits on her own feet.
    local maxPitch=aiming and 55 or 45
    local minPitch=aiming and (cfg.aimMinPitch or -35) or -55
    local wanted=pitch+y*cfg.pitchSpeed*stickMult*dt*(cfg.invertY and -1 or 1)
    if wanted<minPitch then wanted=pitch<minPitch and math.max(wanted,ease(pitch,minPitch,8,dt)) or minPitch end
    pitch=wanted
    if pitch>maxPitch then pitch=aiming and maxPitch or ease(pitch,maxPitch,8,dt) end
    if aiming then
        -- In RE4 style: character smoothly aligns body rotation with camera yaw
        local curYaw=p:K2_GetActorRotation().Yaw
        local delta=(yaw-curYaw+180)%360-180
        local newYaw=(curYaw+delta*math.min(1,dt*20))%360
        p:K2_SetActorRotation({pitch=0,Yaw=newYaw,Roll=0},false)
    end
    pc:SetControlRotation({pitch=pitch,Yaw=yaw,Roll=0})
    if aimMove then
        -- RE4-style: facing stays on the crosshair, the left stick walks relative to the camera.
        -- Forward uses the game's aim-walk cycle; backpedal and side steps play Caroline's own
        -- sequences as montages. No walking during a shot or reload, as in RE4.
        local busy=p.isAttacking or p.isReloading
        local plan=(not busy) and aimwalk.plan(cfg,lx,ly,yaw) or nil
        walker:update(p,plan and plan.anim or nil,plan and plan.rate or 1)
        local ok,err=pcall(aimwalk.drive,p,plan and plan.dx*plan.speed or 0,plan and plan.dy*plan.speed or 0,dt)
        if not ok then cfg.aimMove=false;aimwalk.release(p);log('Aim walk disabled after error: '..tostring(err)) end
        walkStick=plan and plan.stick or 0
        p.StickX=0;p.StickY=walkStick
    elseif walkStick then
        walkStick=nil;walker:stop(p);aimwalk.release(p)
        p.StickX=0;p.StickY=0
    end
    p.TankMode=false;p.AutoNorth=false
    local north={pitch=0,Yaw=moveYaw(),Roll=0}
    p.NorthCamera=north;p['Last Camera Rotator']=north;p['Current Camera Rotator']=north;p.RAfterCameraChange=north
    p.ChangeNorth=false
    p.bUseControllerRotationYaw=false
    boom.bUsePawnControlRotation=false;boom.bAbsoluteRotation=true
    boom.bInheritPitch=false;boom.bInheritYaw=false;boom.bInheritRoll=false
    -- collision.lua owns all camera collision (Visibility + Camera channels, two-stage).
    -- The native spring-arm sweep goes straight from the head to the camera and could
    -- collapse it back into the head, so it stays off while the shoulder view is active.
    boom.bDoCollisionTest=false;boom.ProbeSize=cfg.collisionRadius;boom.ProbeChannel=4
    -- Optional light positional lag (off by default: any walking motion can cause sickness).
    -- Capped well inside the collision margin; rotation never lags.
    boom.bEnableCameraLag=cfg.followLag==true;boom.bEnableCameraRotationLag=false
    boom.CameraLagSpeed=aiming and 30 or 14;boom.CameraLagMaxDistance=6
    local speed=cfg.transitionSpeed or 10
    if warming then blend.distance=cfg.distance;blend.shoulder=cfg.shoulder*side;blend.height=cfg.height end
    blend.distance=ease(blend.distance,aiming and cfg.aimDistance or cfg.distance,speed,dt)
    blend.shoulder=ease(blend.shoulder,cfg.shoulder*side,speed,dt)
    blend.height=ease(blend.height,aiming and (cfg.aimHeight or cfg.height) or cfg.height,speed,dt)
    local arm,offset=collision.solve(p,yaw,pitch,blend.distance,blend.shoulder,blend.height,cfg.collisionRadius,dt)
    boom.TargetArmLength=arm
    -- Never render the inside of the head: hide the character while the camera is too close.
    local hideBelow=cfg.hideCharacterBelow or 30
    if hiddenParts and collision.clearance>hideBelow+10 then
        setCharacterHidden(p,false)
    elseif not hiddenParts and not hideFailed and collision.clearance<hideBelow then
        setCharacterHidden(p,true)
        if hiddenParts then log(string.format('Camera close to head (%.0f cm, overlap=%s): character hidden. hit=%s',
            collision.clearance,tostring(collision.overlap),collision.lastHit)) end
    end
    boom.TargetOffset={X=0,Y=0,Z=blend.height}
    boom.SocketOffset={X=0,Y=offset,Z=0}
    boom.RelativeLocation={X=0,Y=0,Z=0}
    boom:K2_SetWorldRotation({pitch=pitch,Yaw=yaw,Roll=0},false,{},false)
    -- Breathing sway and turn lean (motion.lua) ride on the camera, relative to the socket.
    local yawRate=lastYaw and ((yaw-lastYaw+180)%360-180)/math.max(dt,1e-3) or 0
    lastYaw=yaw
    local still,tilt=motion.update(cfg,dt,yawRate,aiming)
    camera.RelativeLocation=still
    camera.RelativeRotation=tilt
    camera.bUsePawnControlRotation=false;camera.bConstrainAspectRatio=false
    local targetFov=aiming and (cfg.aimFov or 65) or (cfg.fov or 75)
    currentFov=ease(currentFov,targetFov,12,dt)
    camera:SetFieldOfView(currentFov)
    if not camera.bIsActive then camera:Activate(false) end
    if not warming and pc:GetViewTarget():GetAddress()~=p:GetAddress() then pc:SetViewTargetWithBlend(p,0.0,0,0.0,false) end
    if aiming and (cfg.freeAim or cfg.crosshair) then aim.update(pc,p,dt) else aim.clear() end
end
return M
