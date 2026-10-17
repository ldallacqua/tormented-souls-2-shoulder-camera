-- Free aim retargets player ammo traces/rotations to the crosshair point, keeps pellet
-- spread, ignores everything else and switches itself off on errors.
local function object(name,fields,classes)
    local o=fields or {}
    o.IsValid=function() return true end
    o.GetAddress=function() return name end
    o.GetFullName=function() return name end
    o.IsA=function(_,path) return classes and classes[path] or false end
    return o
end
local hooks={}
local registrations=0
function RegisterHook(path,callback) hooks[path]=callback;registrations=registrations+1;return 1,2 end
function UnregisterHook() end
function FName(s) return {ToString=function() return s end} end
-- Minimal UMG for the crosshair widget.
local widgets,constructed,made={},0,{}
local function uobject(name,fields)
    local o=fields or {}
    o.IsValid=function() return true end
    o.GetFName=function() return FName(name) end
    return o
end
local hostClass=uobject('WBP_FPSShow_C')
local library=uobject('Default__WidgetBlueprintLibrary',{Create=function()
    local w=uobject('Host',{WidgetTree=uobject('Tree'),visibility=nil,inViewport=false})
    w.SetVisibility=function(self,v) self.visibility=v end
    w.AddToViewport=function(self) self.inViewport=true end
    w.IsInViewport=function(self) return self.inViewport end
    w.RemoveFromParent=function(self) self.inViewport=false end
    widgets[#widgets+1]=w
    return w
end})
local slotCalls=0
function StaticFindObject(path)
    if path:find('WBP_FPSShow') then return hostClass end
    if path:find('WidgetBlueprintLibrary') then return library end
    return uobject(path)
end
function StaticConstructObject(class)
    constructed=constructed+1
    local o=uobject('Widget'..constructed)
    o.AddChildToCanvas=function()
        slotCalls=slotCalls+1
        local s={}
        for _,n in ipairs({'SetAnchors','SetAlignment','SetPosition','SetSize'}) do s[n]=function() end end
        return s
    end
    o.SetColorAndOpacity=function(self,c) self.color=c end
    made[#made+1]=o
    return o
end
local wall=1000
local traceLibrary={LineTraceSingle=function(_,_,start,finish,_,_,_,_,hit)
    -- A wall at X=wall facing the camera.
    if finish.X<wall then return false end
    local t=(wall-start.X)/(finish.X-start.X)
    hit.ImpactPoint={X=wall,Y=start.Y+(finish.Y-start.Y)*t,Z=start.Z+(finish.Z-start.Z)*t}
    hit.Component={Get=function() return nil end}
    return true
end}
package.loaded.UEHelpers={GetKismetSystemLibrary=function() return traceLibrary end}
local aim=dofile(SOURCE..'/aim.lua')
local cfg={freeAim=true,crosshair=true}
local messages={}
aim.init(cfg,function(s) messages[#messages+1]=s end)
local m=aim._math

local function param(v) return {get=function() return v end,set=function(_,n) v=n end,value=function() return v end} end
local function close(a,b,eps) return math.abs(a-b)<(eps or 1e-6) end
local function unit(v) local l=math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) return {X=v.X/l,Y=v.Y/l,Z=v.Z/l} end
local function angle(a,b)
    a,b=unit(a),unit(b)
    return math.deg(math.acos(math.max(-1,math.min(1,a.X*b.X+a.Y*b.Y+a.Z*b.Z))))
end

-- Rotator <-> direction and Rodrigues rotation.
local d=m.fromRotator({pitch=30,Yaw=90})
assert(close(d.X,0) and close(d.Y,math.cos(math.rad(30))) and close(d.Z,0.5))
local r=m.toRotator(d)
assert(close(r.pitch,30) and close(r.Yaw,90),'toRotator must invert fromRotator')
local v=m.rotateOnto({X=1,Y=0,Z=0},{X=1,Y=0,Z=0},{X=0,Y=1,Z=0})
assert(close(v.X,0) and close(v.Y,1) and close(v.Z,0))
local spread=m.fromRotator({pitch=0,Yaw=5})
v=m.rotateOnto(spread,{X=1,Y=0,Z=0},m.fromRotator({pitch=10,Yaw=40}))
assert(close(angle(v,m.fromRotator({pitch=10,Yaw=40})),5,1e-4),'Rotation must keep the angular spread')

local pawn=object('Caroline',{CurrentTarget=nil},{['/Script/Engine.Pawn']=true})
pawn.K2_GetActorLocation=function() return {X=0,Y=0,Z=100} end
pawn.K2_GetActorRotation=function() return {pitch=0,Yaw=0,Roll=0} end
local manager=object('CameraManager')
manager.GetCameraLocation=function() return {X=-200,Y=40,Z=160} end
manager.GetCameraRotation=function() return {pitch=0,Yaw=0,Roll=0} end
local pc=object('Controller',{PlayerCameraManager=manager})
local ammoClass='/Game/GameplaySystems/WeaponSystem/Ammo/BP_BaseAmmo.BP_BaseAmmo_C'
local muzzle={X=0,Y=20,Z=140}
local ammo=object('BP_Nail',{},{[ammoClass]=true})
ammo.K2_GetActorLocation=function() return muzzle end
ammo.GetActorForwardVector=function() return {X=1,Y=0,Z=0} end
local tracePath,rotationPath='/Script/Engine.KismetSystemLibrary:LineTraceMulti','/Script/Engine.Actor:K2_SetActorRotation'
assert(not hooks[tracePath] and not hooks[rotationPath],'Shot hooks fire for every actor: none before the first aim')
assert(not hooks['/Script/Engine.HUD:ReceiveDrawHUD'],'ReceiveDrawHUD never fires in this game')
aim.update(pc,pawn)
local trace,rotation=hooks[tracePath],hooks[rotationPath]
local sphere=hooks['/Script/Engine.KismetSystemLibrary:SphereTraceMulti']
assert(trace and rotation and sphere and registrations==3,'The first aim registers the shot hooks')
-- Crosshair: one widget, five parts, visible while aiming.
assert(#widgets==1 and slotCalls==5,'The crosshair widget is built once with five parts')
local cross=widgets[1]
assert(cross.inViewport and cross.visibility==3,'The crosshair shows while aiming (hit-test invisible)')
local unregistered=0
function UnregisterHook() unregistered=unregistered+1 end
aim.clear()
assert(unregistered==0,'Pending native unregistration still runs once in UE4SS: keep the hooks, gate them instead')
assert(cross.visibility==2,'The crosshair hides when aiming ends')
aim.update(pc,pawn)
assert(registrations==3 and #widgets==1,'Aiming again reuses hooks and widget')
aim.clear()
local expected={X=wall-muzzle.X,Y=40-muzzle.Y,Z=160-muzzle.Z}

local shotStart=nil
local function shoot(world,direction)
    local finish=param({X=muzzle.X+direction.X*5000,Y=muzzle.Y+direction.Y*5000,Z=muzzle.Z+direction.Z*5000})
    local start=param(muzzle)
    trace(param(nil),param(world),start,finish,param(2))
    local e,s=finish.value(),start.value()
    shotStart=s
    return {X=e.X-s.X,Y=e.Y-s.Y,Z=e.Z-s.Z}
end
-- Hitscan shots run along the camera ray (camera at -200,40,160 looking +X), level with Caroline.
local cameraRay={X=1,Y=0,Z=0}
local rayStart={X=0,Y=40,Z=160}

-- Not aiming (a call still in flight after unregistering): nothing changes.
local out=shoot(ammo,{X=1,Y=0,Z=0})
assert(close(out.X,5000) and close(out.Y,0),'Disarmed free aim must not touch shots')

aim.update(pc,pawn)
out=shoot(ammo,{X=1,Y=0,Z=0})
assert(angle(out,cameraRay)<0.01,'The shot follows the camera ray through the crosshair')
assert(close(shotStart.X,rayStart.X) and close(shotStart.Y,rayStart.Y) and close(shotStart.Z,rayStart.Z),'The shot starts on the camera ray, level with Caroline')
assert(close(math.sqrt(out.X^2+out.Y^2+out.Z^2),5000,1e-3),'Trace length is kept (the muzzle is not ahead of the ray start here)')

-- Pellet spread around the actor forward is kept.
out=shoot(ammo,m.fromRotator({pitch=0,Yaw=4}))
assert(close(angle(out,cameraRay),4,0.01),'Pellet spread must survive the retarget')

-- Enemy traces (not player ammo) are left alone.
out=shoot(object('BP_EnemyProjectile',{},{}),{X=1,Y=0,Z=0})
assert(close(out.Y,0) and close(out.Z,0),'Only player ammo is retargeted')

-- Sphere sweeps fired with the shot follow the camera ray too (Radius sits before the channel).
do
    local start,finish=param(muzzle),param({X=muzzle.X+800,Y=muzzle.Y,Z=muzzle.Z})
    sphere(param(nil),param(ammo),start,finish,param(30),param(2))
    local s0,e0=start.value(),finish.value()
    assert(close(s0.Y,40) and close(s0.Z,160) and close(e0.Y,40) and close(e0.Z,160),'Sphere traces fired with the shot run along the camera ray')
end
-- A trace far from Caroline is a projectile in flight or its impact: left alone.
do
    local far={X=900,Y=300,Z=50}
    local start,finish=param(far),param({X=far.X+100,Y=far.Y,Z=far.Z})
    trace(param(nil),param(ammo),start,finish,param(2))
    assert(start.value()==far and close(finish.value().X,1000) and close(finish.value().Y,300),'In-flight/impact traces are not moved')
end

-- Projectile rotation follows the crosshair too.
local newRotation=param({pitch=0,Yaw=0,Roll=0})
rotation(param(ammo),newRotation)
assert(angle(m.fromRotator(newRotation.value()),expected)<0.01,'Projectiles must face the crosshair')

-- A wall right in front of the muzzle must not bend the shot sideways.
wall=5
aim.update(pc,pawn)
out=shoot(ammo,{X=1,Y=0,Z=0})
assert(angle(out,{X=1,Y=0,Z=0})<0.01,'Too-close aim points fall back to the camera direction')
wall=1000

aim.clear()
out=shoot(ammo,{X=1,Y=0,Z=0})
assert(close(out.Y,0),'Clearing disarms free aim')

-- Crosshair turns red over an enemy and is rebuilt after a level change.
local enemy=object('Enemy',{},{['/Script/Engine.Pawn']=true})
local realTrace=traceLibrary.LineTraceSingle
traceLibrary.LineTraceSingle=function(...)
    local args={...}
    local blocked=realTrace(...)
    if blocked then args[9].Component={Get=function() return {IsValid=function() return true end,GetOwner=function() return enemy end} end} end
    return blocked
end
aim.update(pc,pawn)
assert(made[#made].color.G<0.5 and made[#made].color.R==1,'The crosshair turns red over an enemy')
traceLibrary.LineTraceSingle=realTrace
aim.update(pc,pawn)
assert(made[#made].color.G==1,'And white again off target')
cross.inViewport=false
aim.update(pc,pawn)
assert(#widgets==2,'A crosshair dropped from the viewport is rebuilt')
aim.clear()

-- Errors switch the feature off instead of repeating every shot.
aim.update(pc,pawn)
ammo.GetActorForwardVector=function() error('boom') end
shoot(ammo,{X=1,Y=0,Z=0})
assert(cfg.freeAim==false and messages[#messages]:find('freeAim disabled'),'A failing hook must disable free aim')
print('PASS: free aim retarget, spread, filtering, wall fallback and error isolation')

-- Torso pitch follows the crosshair within the anim blueprint's -30..+40 range.
ammo.GetActorForwardVector=function() return {X=1,Y=0,Z=0} end
cfg.freeAim=true
assert(close(aim.torsoPitch({X=0,Y=0,Z=0},{X=100,Y=0,Z=100}),40),'Up is clamped to +40')
assert(close(aim.torsoPitch({X=0,Y=0,Z=0},{X=100,Y=0,Z=-20}),math.deg(math.atan(-20,100))),'Small angles bend 1:1')
assert(close(aim.torsoPitch({X=0,Y=0,Z=0},{X=10,Y=0,Z=-500}),-30),'Down is clamped to -30')
assert(aim.torsoPitch({X=0,Y=0,Z=0},{X=0,Y=0,Z=-500})==0,'A point straight below gives no bend')
-- Shots steeper than -50 degrees are raised (never into her feet); others are untouched.
local limited=aim.limitShot(unit({X=1,Y=0,Z=-3}))
assert(close(math.deg(math.asin(limited.Z)),-50,1e-6) and limited.X>0 and close(limited.Y,0),'Steep shots are raised')
local level=unit({X=1,Y=1,Z=-0.2})
assert(aim.limitShot(level)==level,'Shallow shots are untouched')

pawn.RotationToAim={pitch=0,Yaw=7,Roll=1}
aim.update(pc,pawn,0.016)
assert(pawn.RotationToAim.pitch>0 and pawn.RotationToAim.Yaw==7 and pawn.RotationToAim.Roll==1,'The torso eases towards the crosshair, keeping yaw/roll')
for _=1,120 do aim.update(pc,pawn,0.016) end
local want=math.deg(math.atan(160-140,wall))
assert(close(pawn.RotationToAim.pitch,want,0.05),'The torso settles on the crosshair elevation')
aim.clear()
assert(pawn.RotationToAim.pitch==0 and pawn.RotationToAim.Yaw==7,'Ending the aim straightens the torso')
cfg.torsoAim=false
aim.update(pc,pawn,0.016)
assert(pawn.RotationToAim.pitch==0,'torsoAim=false leaves the torso to the game')
aim.clear()
cfg.torsoAim=nil

-- Impact marks: queued by the shot hooks, traced next frame, enemies skipped, one per shot.
local decals={}
local midOk=true
local statics={SpawnDecalAtLocation=function(_,_,material,size,location,rotation,life)
    local d={material=material,size=size,location=location,rotation=rotation,life=life,textures={}}
    d.IsValid=function() return true end
    d.SetHiddenInGame=function(self,h) self.hidden=h end
    d.CreateDynamicMaterialInstance=function(self)
        if not midOk then return nil end
        return {IsValid=function() return true end,SetTextureParameterValue=function(_,name,t) self.textures[name:ToString()]=t end}
    end
    decals[#decals+1]=d
    return d
end}
package.loaded.UEHelpers.GetGameplayStatics=function() return statics end
realTrace=traceLibrary.LineTraceSingle
traceLibrary.LineTraceSingle=function(...)
    local args={...}
    local blocked=realTrace(...)
    if blocked then args[9].ImpactNormal={X=-1,Y=0,Z=0} end
    return blocked
end
cfg.impactMarks=true
aim.update(pc,pawn,0.016)
shoot(ammo,{X=1,Y=0,Z=0})
rotation(param(ammo),param({pitch=0,Yaw=0,Roll=0}))
assert(#decals==0,'Marks are never placed inside the native hook')
aim.update(pc,pawn,0.016)
assert(#decals==1,'One mark per shot even when trace and rotation hooks both report it')
local mark=decals[1]
assert(close(mark.location.X,wall) and close(mark.location.Y,40,1e-3) and close(mark.location.Z,160,1e-3),'The mark sits where the camera-ray shot hits: under the crosshair')
assert(close(mark.rotation.Yaw,0) and close(mark.rotation.pitch,0),'The decal projects into the surface')
assert(mark.life==30 and mark.size.Y==5 and mark.material,'Default life and size')
assert(mark.material:GetFName():ToString():find('Blood_Stain') and mark.textures.DRO and mark.textures.Albedo and mark.textures.Normal,
    'The Megascans decal gets the black albedo, flat normal and impact opacity textures')
assert(messages[#messages]:find('Impact marks use'),'The material choice is logged once')
-- A shot on an enemy leaves no mark.
traceLibrary.LineTraceSingle=function(...)
    local args={...}
    local blocked=realTrace(...)
    if blocked then
        args[9].ImpactNormal={X=-1,Y=0,Z=0}
        args[9].Component={Get=function() return {IsValid=function() return true end,GetOwner=function() return enemy end} end}
    end
    return blocked
end
shoot(ammo,{X=1,Y=0,Z=0})
aim.update(pc,pawn,0.016)
assert(#decals==1,'Enemies get no mark')
traceLibrary.LineTraceSingle=realTrace
-- Off: nothing is queued or placed.
cfg.impactMarks=false
shoot(ammo,{X=1,Y=0,Z=0})
aim.update(pc,pawn,0.016)
assert(#decals==1,'impactMarks=false places nothing')
-- Without a dynamic material the base blood stain is hidden, not left behind.
cfg.impactMarks=true;midOk=false
traceLibrary.LineTraceSingle=function(...)
    local args={...}
    local blocked=realTrace(...)
    if blocked then args[9].ImpactNormal={X=-1,Y=0,Z=0} end
    return blocked
end
shoot(ammo,{X=1,Y=0,Z=0})
aim.update(pc,pawn,0.016)
assert(#decals==2 and decals[2].hidden==true,'A decal without its impact material is hidden')
midOk=true
-- A failing spawn switches marks off once.
cfg.impactMarks=true
statics.SpawnDecalAtLocation=function() error('decal boom') end
traceLibrary.LineTraceSingle=function(...)
    local args={...}
    local blocked=realTrace(...)
    if blocked then args[9].ImpactNormal={X=-1,Y=0,Z=0} end
    return blocked
end
shoot(ammo,{X=1,Y=0,Z=0})
aim.update(pc,pawn,0.016)
assert(cfg.impactMarks==false and messages[#messages]:find('Impact marks disabled'),'A failing mark disables the feature')
traceLibrary.LineTraceSingle=realTrace
aim.clear()
print('PASS: torso pitch, shot floor limit and impact marks')
