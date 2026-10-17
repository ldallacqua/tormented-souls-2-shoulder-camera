-- Zone cameras (BP_RailCamera) with AutoNorthLocal rewrite the movement reference every tick.
-- The mod must switch that flag off while active, restore it, and register the Blueprint
-- hooks even when the script starts before those classes are loaded (main menu).
function FName(s) return {ToString=function() return s end} end
local function object(name,fields)
    local o=fields or {}
    o.IsValid=function() return true end
    o.GetAddress=function() return name end
    o.GetFName=function() return FName(name) end
    o.GetFullName=function() return name end
    return o
end
local invalid={IsValid=function() return false end}
local blueprintLoaded=false
function StaticFindObject(path)
    if path:find('^/Game/') and blueprintLoaded then return object(path) end
    return invalid
end
local hooks={}
function RegisterHook(path,callback) hooks[path]=callback;return 1,2 end
function UnregisterHook() end
package.loaded.UEHelpers={GetGameInstance=function() return nil end}

local realDofile=dofile
local stubs={
    ['input.lua']={update=function() end,restore=function() end},
    ['collision.lua']={clearance=220,reset=function() end,solve=function(_,_,_,distance,shoulder) return distance,shoulder end},
}
dofile=function(path) return stubs[path:match('[^/\\]+$')] or realDofile(path) end
local camera=realDofile(SOURCE..'/camera.lua')
dofile=realDofile

local function rotator(yaw) return {pitch=0,Yaw=yaw,Roll=0} end
local boom=object('Boom',{TargetArmLength=300,SocketOffset={X=0,Y=0,Z=0},TargetOffset={X=0,Y=0,Z=0},
    RelativeLocation={X=0,Y=0,Z=0},RelativeRotation=rotator(0),K2_SetWorldRotation=function() end})
local view=object('FollowCamera',{FieldOfView=90,RelativeLocation={X=0,Y=0,Z=0},RelativeRotation=rotator(0),
    bIsActive=true,SetFieldOfView=function() end,Activate=function() end})
local pawn=object('Caroline',{CameraBoom=boom,FollowCamera=view,Health=100,TankMode=false,AutoNorth=false,
    NorthCamera=rotator(0),RAfterCameraChange=rotator(0),['Last Camera Rotator']=rotator(0),['Current Camera Rotator']=rotator(0)})
pawn.IsA=function() return true end
pawn.K2_GetActorRotation=function() return rotator(30) end
local pc=object('Controller',{Pawn=pawn})
pc.GetInputAnalogKeyState=function() return 0 end
pc.SetControlRotation=function() end
pc.GetViewTarget=function() return pawn end
pc.SetViewTargetWithBlend=function() end

local railTick='/Game/Tools/RailCamera/BP_RailCamera.BP_RailCamera_C:ReceiveTick'
local characterTick='/Game/Characters/BP_TormentedSoulCharacter.BP_TormentedSoulCharacter_C:ReceiveTick'
camera.update(pc,0.016)
assert(not hooks[railTick],'Blueprint hooks need their class to be loaded')
blueprintLoaded=true
camera.update(pc,0.5)
camera.update(pc,0.6)
assert(hooks[railTick] and hooks[characterTick],'Blueprint hooks must register once the level loads')

local rail=object('BP_RailCamera_C_4',{AutoNorthLocal=true})
local context={get=function() return rail end}
pawn.NorthCamera=rotator(-178.7);pawn.AutoNorth=true;pawn.ChangeNorth=true
hooks[railTick](context)
assert(rail.AutoNorthLocal==false,'Active shoulder view must disable zone AutoNorthLocal')
assert(pawn.NorthCamera.Yaw==30 and pawn.RAfterCameraChange.Yaw==30,'Zone camera yaw must not become the movement reference')
assert(pawn.AutoNorth==false and pawn.ChangeNorth==false)

pawn.ChangeNorth=true
hooks[characterTick]({get=function() return pawn end})
assert(pawn.ChangeNorth==false,'Character tick must leave the shoulder reference in place')

camera.action('toggle')
camera.update(pc,0.016)
assert(rail.AutoNorthLocal==true,'F6 must restore the zone camera')
hooks[railTick](context)
assert(rail.AutoNorthLocal==true,'Disabled mod must not touch zone cameras')
print('PASS: zone camera direction reference, late Blueprint hooks and F6 restoration')
