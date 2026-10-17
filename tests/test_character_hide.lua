-- The character is hidden (OwnerNoSee) while the camera is closer than hideCharacterBelow
-- to the head, shown again with hysteresis, and always restored by F6/blocked modes.
function FName(s) return {ToString=function() return s end} end
local function object(name,fields)
    local o=fields or {}
    o.IsValid=function() return true end
    o.GetAddress=function() return name end
    o.GetFName=function() return FName(name) end
    o.GetFullName=function() return name end
    return o
end
function StaticFindObject(path) return object(path) end
function RegisterHook() return 1,2 end
function UnregisterHook() end
package.loaded.UEHelpers={GetGameInstance=function() return nil end}
local stub={clearance=220,reset=function() end,solve=function(_,_,_,d,s) return d,s end}
local realDofile=dofile
dofile=function(path)
    local n=path:match('[^/\\]+$')
    if n=='collision.lua' then return stub end
    if n=='input.lua' then return {update=function() end,restore=function() end} end
    return realDofile(path)
end
local camera=realDofile(SOURCE..'/camera.lua')
dofile=realDofile

local function part(name,noSee)
    local c=object(name,{bOwnerNoSee=noSee})
    c.SetOwnerNoSee=function(self,v) self.bOwnerNoSee=v end
    return c
end
local body,hair,preHidden=part('Body',false),part('Hair',false),part('AlreadyHidden',true)
local parts={body,hair,preHidden}
local function rotator(yaw) return {pitch=0,Yaw=yaw,Roll=0} end
local boom=object('Boom',{TargetArmLength=300,SocketOffset={X=0,Y=0,Z=0},TargetOffset={X=0,Y=0,Z=0},
    RelativeLocation={X=0,Y=0,Z=0},RelativeRotation=rotator(0),K2_SetWorldRotation=function() end})
local view=object('FollowCamera',{FieldOfView=90,RelativeLocation={X=0,Y=0,Z=0},RelativeRotation=rotator(0),
    bIsActive=true,SetFieldOfView=function() end,Activate=function() end})
local pawn=object('Caroline',{CameraBoom=boom,FollowCamera=view,Health=100,TankMode=false,AutoNorth=false,
    NorthCamera=rotator(0),RAfterCameraChange=rotator(0),['Last Camera Rotator']=rotator(0),['Current Camera Rotator']=rotator(0)})
pawn.IsA=function() return true end
pawn.K2_GetActorRotation=function() return rotator(0) end
-- Observed in game: a plain Lua table (no ForEach) whose elements are wrapped (no IsValid).
pawn.K2_GetComponentsByClass=function() local list={} for i,c in ipairs(parts) do list[i]={get=function() return c end} end return list end
local pc=object('Controller',{Pawn=pawn})
pc.GetInputAnalogKeyState=function() return 0 end
pc.SetControlRotation=function() end
pc.GetViewTarget=function() return pawn end
pc.SetViewTargetWithBlend=function() end

camera.update(pc,0.016)
assert(boom.bDoCollisionTest==false,'Native spring-arm collision must be off while active')
assert(not body.bOwnerNoSee,'Far camera keeps the character visible')
stub.clearance=20;camera.update(pc,0.016)
assert(body.bOwnerNoSee and hair.bOwnerNoSee,'Camera near the head must hide the character')
stub.clearance=35;camera.update(pc,0.016)
assert(body.bOwnerNoSee,'Hysteresis: stay hidden just above the threshold')
stub.clearance=60;camera.update(pc,0.016)
assert(not body.bOwnerNoSee and not hair.bOwnerNoSee,'Character reappears once the camera moves away')
assert(preHidden.bOwnerNoSee,'Components hidden by the game must stay hidden')
stub.clearance=10;camera.update(pc,0.016)
assert(body.bOwnerNoSee)
camera.action('toggle');camera.update(pc,0.016)
assert(not body.bOwnerNoSee,'F6 must make the character visible again')
camera.action('toggle');stub.clearance=220;camera.update(pc,0.016)
-- A failing component query must not disable the camera (it used to set fault=true).
pawn.K2_GetComponentsByClass=function() error('boom') end
stub.clearance=10;camera.update(pc,0.016)
assert(not camera.fault and boom.TargetArmLength==220,'Hiding errors must be non-fatal')
camera.update(pc,0.016)
print('PASS: character hidden near the head, hysteresis, restoration and non-fatal failure')
