local UEHelpers = require('UEHelpers')
local directory=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])')
local shortcuts=dofile(directory..'input.lua')
local collision=dofile(directory..'collision.lua')
local M = { enabled=true, fault=false }
local cfg=dofile(directory..'config.lua')
M.enabled=cfg.enabled
assert(cfg.deadzone>=0 and cfg.deadzone<1,'deadzone must be >=0 and <1')
local pawn, controller, boom, camera, original, originalView
local yaw, pitch, side=0,-9,1
local active=false
local mode='gameplay'
local modeLog=''
local keys={}
local viewHookPre,viewHookPost
local extraHooks={}
local movementCorrections={}
-- Zone cameras whose AutoNorthLocal was switched off while the shoulder view owns movement.
local railPatched={}
local viewHookPath='/Script/Engine.PlayerController:SetViewTargetWithBlend'
local function valid(o) return o and o:IsValid() end
local function log(s) print('[ShoulderCamera] '..s..'\n') end
local function vec(v) return {X=v.X,Y=v.Y,Z=v.Z} end
local function rot(v) return {pitch=v.pitch or v.Pitch,Yaw=v.Yaw,Roll=v.Roll} end
local function key(name)
    if not keys[name] then keys[name]={KeyName=FName(name)} end
    return keys[name]
end
local function axis(pc,name)
    local v=pc:GetInputAnalogKeyState(key(name))
    if math.abs(v)<cfg.deadzone then return 0 end
    local scaled=(math.abs(v)-cfg.deadzone)/(1-cfg.deadzone)
    return (v<0 and -1 or 1)*scaled
end
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
    setCharacterHidden(pawn,false)
    local wasActive=active
    active=false
    for _,rail in pairs(railPatched) do if valid(rail) then rail.AutoNorthLocal=true end end
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
    active=false
end
function M.shutdown()
    restore()
    shortcuts.restore()
    if viewHookPre then UnregisterHook(viewHookPath,viewHookPre,viewHookPost);viewHookPre=nil end
    for _,h in ipairs(extraHooks) do UnregisterHook(h[1],h[2],h[3]) end
    extraHooks={}
end
function M.mode_changed(value)
    mode=value
    if mode~='gameplay' and mode~='pause' then restore() end
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
    for _,name in ipairs(blockedFlags) do if p[name] then return name end end
    local ui=pc.UIManager
    if valid(ui) then
        if ui.bIsMainMenuOpen or ui.bIsSaveScreenMenuOpen then return 'menu' end
        if ui.bIsPauseMenuOpen or ui.bGameIsPaused then return 'pause' end
    end
    return nil
end
local function syncMovement(source)
    if not M.enabled or M.fault or not active or not valid(pawn) or not valid(controller) then return end
    local function off(name) return math.abs((pawn[name].Yaw-yaw+180)%360-180) end
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
                count,source,pawn.NorthCamera.Yaw,pawn.RAfterCameraChange.Yaw,pawn['Current Camera Rotator'].Yaw,yaw,
                tostring(pawn.AutoNorth),tostring(pawn.ChangeNorth)))
        end
    end
    pawn.NorthCamera={pitch=0,Yaw=yaw,Roll=0}
    pawn['Last Camera Rotator']={pitch=0,Yaw=yaw,Roll=0}
    pawn['Current Camera Rotator']={pitch=0,Yaw=yaw,Roll=0}
    pawn.RAfterCameraChange={pitch=0,Yaw=yaw,Roll=0}
    pawn.AutoNorth=false;pawn.ChangeNorth=false
end
for _,name in ipairs({'SetStickXValue','SetStickYValue'}) do
    local path='/Script/TormentedSouls2.TormentedSouls2Character:'..name
    local a,b=RegisterHook(path,function(context)
        if valid(pawn) and context:get():GetAddress()==pawn:GetAddress() then syncMovement(name) end
    end)
    extraHooks[#extraHooks+1]={path,a,b}
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
    if reason and reason~='pause' then return end
    local target=newTarget:get()
    if not valid(target) or target:GetAddress()==pawn:GetAddress() then return end
    if target:IsA('/Script/CinematicCamera.CineCameraActor') then return end
    if target:IsA('/Script/Engine.CameraActor') or target:IsA('/Script/TormentedSouls2.RailCamera') then
        originalView=target
        newTarget:set(pawn)
        blendTime:set(0.0)
        syncMovement('ViewTarget')
        log('Redirected fixed camera '..target:GetFName():ToString())
    end
end)
local function bind(pc,p)
    restore()
    controller=pc;pawn=p;boom=p.CameraBoom;camera=p.FollowCamera
    if not valid(boom) or not valid(camera) then error('Character camera components unavailable') end
    original={TankMode=p.TankMode,AutoNorth=p.AutoNorth,bUseControllerRotationYaw=p.bUseControllerRotationYaw,boom={},camera={}}
    local bp={'TargetArmLength','SocketOffset','TargetOffset','ProbeSize','ProbeChannel','bDoCollisionTest','bUsePawnControlRotation',
        'bInheritPitch','bInheritYaw','bInheritRoll','bEnableCameraLag','bEnableCameraRotationLag','bAbsoluteRotation','RelativeRotation','RelativeLocation'}
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
end
function M.update(pc,dt)
    if M.fault then return end
    registerBlueprintHooks(dt)
    shortcuts.update(M.enabled,dt)
    local p=pc.Pawn
    if not valid(p) or not p:IsA('/Script/TormentedSouls2.TormentedSouls2Character') then restore();pawn=nil;return end
    if not valid(pawn) or p:GetAddress()~=pawn:GetAddress() then bind(pc,p) end
    local reason=blocked(pc,p)
    local label=reason or (M.enabled and 'shoulder' or 'disabled')
    if label~=modeLog then modeLog=label;log('State '..label) end
    -- Freeze the shoulder view during pause so resuming never exposes a fixed view.
    if M.enabled and active and reason=='pause' then return end
    if not M.enabled or reason then restore();return end
    dt=math.min(math.max(dt,0),0.05)
    if not active then collision.reset() end
    active=true
    local x,y=axis(pc,'Gamepad_RightX'),axis(pc,'Gamepad_RightY')
    yaw=(yaw+x*cfg.yawSpeed*dt)%360
    pitch=math.max(-55,math.min(45,pitch+y*cfg.pitchSpeed*dt*(cfg.invertY and -1 or 1)))
    local aiming=p.isAiming
    if aiming and math.abs(x)<0.01 then
        local target=p:K2_GetActorRotation().Yaw
        local delta=(target-yaw+180)%360-180
        yaw=(yaw+delta*math.min(1,dt*8))%360
    end
    pc:SetControlRotation({pitch=pitch,Yaw=yaw,Roll=0})
    p.TankMode=false;p.AutoNorth=false
    p.NorthCamera={pitch=0,Yaw=yaw,Roll=0}
    p['Last Camera Rotator']={pitch=0,Yaw=yaw,Roll=0}
    p['Current Camera Rotator']={pitch=0,Yaw=yaw,Roll=0}
    p.RAfterCameraChange={pitch=0,Yaw=yaw,Roll=0}
    p.ChangeNorth=false
    p.bUseControllerRotationYaw=false
    boom.bUsePawnControlRotation=false;boom.bAbsoluteRotation=true
    boom.bInheritPitch=false;boom.bInheritYaw=false;boom.bInheritRoll=false
    -- collision.lua owns all camera collision (Visibility + Camera channels, two-stage).
    -- The native spring-arm sweep goes straight from the head to the camera and could
    -- collapse it back into the head, so it stays off while the shoulder view is active.
    boom.bDoCollisionTest=false;boom.ProbeSize=cfg.collisionRadius;boom.ProbeChannel=4
    boom.bEnableCameraLag=false;boom.bEnableCameraRotationLag=false
    local arm,offset=collision.solve(p,yaw,pitch,aiming and cfg.aimDistance or cfg.distance,cfg.shoulder*side,cfg.height,cfg.collisionRadius,dt)
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
    boom.TargetOffset={X=0,Y=0,Z=cfg.height}
    boom.SocketOffset={X=0,Y=offset,Z=0}
    boom.RelativeLocation={X=0,Y=0,Z=0}
    boom:K2_SetWorldRotation({pitch=pitch,Yaw=yaw,Roll=0},false,{},false)
    camera.RelativeLocation={X=0,Y=0,Z=0}
    camera.RelativeRotation={pitch=0,Yaw=0,Roll=0}
    camera.bUsePawnControlRotation=false;camera.bConstrainAspectRatio=false
    camera:SetFieldOfView(aiming and cfg.aimFov or cfg.fov)
    if not camera.bIsActive then camera:Activate(false) end
    if pc:GetViewTarget():GetAddress()~=p:GetAddress() then pc:SetViewTargetWithBlend(p,0.0,0,0.0,false) end

end
return M
