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
assert(trace and rotation and registrations==2,'The first aim registers the shot hooks')
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
assert(registrations==2 and #widgets==1,'Aiming again reuses hooks and widget')
aim.clear()
local expected={X=wall-muzzle.X,Y=40-muzzle.Y,Z=160-muzzle.Z}

local function shoot(world,direction)
    local finish=param({X=muzzle.X+direction.X*5000,Y=muzzle.Y+direction.Y*5000,Z=muzzle.Z+direction.Z*5000})
    trace(param(nil),param(world),param(muzzle),finish,param(2))
    local e=finish.value()
    return {X=e.X-muzzle.X,Y=e.Y-muzzle.Y,Z=e.Z-muzzle.Z}
end

-- Not aiming (a call still in flight after unregistering): nothing changes.
local out=shoot(ammo,{X=1,Y=0,Z=0})
assert(close(out.X,5000) and close(out.Y,0),'Disarmed free aim must not touch shots')

aim.update(pc,pawn)
out=shoot(ammo,{X=1,Y=0,Z=0})
assert(angle(out,expected)<0.01,'The shot must go to the point under the crosshair')
assert(close(math.sqrt(out.X^2+out.Y^2+out.Z^2),5000,1e-3),'Trace length is kept')

-- Pellet spread around the actor forward is kept.
out=shoot(ammo,m.fromRotator({pitch=0,Yaw=4}))
assert(close(angle(out,expected),4,0.01),'Pellet spread must survive the retarget')

-- Enemy traces (not player ammo) are left alone.
out=shoot(object('BP_EnemyProjectile',{},{}),{X=1,Y=0,Z=0})
assert(close(out.Y,0) and close(out.Z,0),'Only player ammo is retargeted')

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
