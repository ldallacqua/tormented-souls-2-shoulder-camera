-- Inventory, pause and short puzzle interactions keep the shoulder view frozen instead of
-- cutting to the room camera and back. A real close-up requested by the game is shown,
-- and its return to the room camera goes straight back to the shoulder view.
function FName(s) return {ToString=function() return s end} end
local function object(name,fields,classes)
    local o=fields or {}
    o.IsValid=function() return true end
    o.GetAddress=function() return name end
    o.GetFName=function() return FName(name) end
    o.GetFullName=function() return name end
    o.IsA=function(_,path) return classes==true or (classes and classes[path]) or false end
    return o
end
function StaticFindObject(path) return object(path) end
local hooks={}
function RegisterHook(path,callback) hooks[path]=callback;return 1,2 end
function UnregisterHook() end
local gameInstance=object('GameInstance',{CurrentCamera=nil})
package.loaded.UEHelpers={GetGameInstance=function() return gameInstance end}
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

local function rotator(yaw) return {pitch=0,Yaw=yaw,Roll=0} end
local boom=object('Boom',{TargetArmLength=300,SocketOffset={X=0,Y=0,Z=0},TargetOffset={X=0,Y=0,Z=0},
    RelativeLocation={X=0,Y=0,Z=0},RelativeRotation=rotator(0),K2_SetWorldRotation=function() end})
local view=object('FollowCamera',{FieldOfView=90,RelativeLocation={X=0,Y=0,Z=0},RelativeRotation=rotator(0),
    bIsActive=true,SetFieldOfView=function() end,Activate=function() end})
local pawn=object('Caroline',{CameraBoom=boom,FollowCamera=view,Health=100,TankMode=false,AutoNorth=false,
    NorthCamera=rotator(0),RAfterCameraChange=rotator(0),['Last Camera Rotator']=rotator(0),['Current Camera Rotator']=rotator(0)},true)
pawn.K2_GetActorRotation=function() return rotator(0) end
local cameraActor={['/Script/Engine.CameraActor']=true}
local room=object('CameraActor_3',{},cameraActor)
local closeUp=object('CameraActor_Puzzle',{},cameraActor)

local viewHook='/Script/Engine.PlayerController:SetViewTargetWithBlend'
local current=room
local pc=object('Controller',{Pawn=pawn})
pc.GetInputAnalogKeyState=function() return 0 end
pc.IsInputKeyDown=function() return false end
pc.SetControlRotation=function() end
pc.GetViewTarget=function() return current end
-- Mimics the game: the native pre-hook may replace the requested target.
pc.SetViewTargetWithBlend=function(self,target,blend)
    local requested=target
    hooks[viewHook]({get=function() return self end},
        {get=function() return requested end,set=function(_,v) requested=v end},
        {get=function() return blend end,set=function() end})
    current=requested
end
local function frame() camera.update(pc,0.016) end
local function isShoulder() return current:GetAddress()=='Caroline' end

frame()
assert(current==room,'Activation configures the spring arm one frame before taking the view')
frame()
assert(isShoulder(),'The shoulder view must take over on the next frame')

-- The game walks into a fixed-camera trigger: redirected as before.
pc:SetViewTargetWithBlend(room,0.5)
assert(isShoulder(),'Room cameras are redirected during gameplay')

-- Inventory: frozen shoulder view, closing it never exposes the room camera.
camera.mode_changed('inventory')
frame()
assert(isShoulder(),'Opening the inventory must not move the camera')
pc:SetViewTargetWithBlend(room,0.0)
camera.mode_changed('gameplay')
assert(isShoulder(),'Closing the inventory must not flash the room camera')
frame()
assert(isShoulder())

-- Short item/puzzle interaction without a close-up: no cut to the room camera and back.
camera.mode_changed('puzzle')
frame()
assert(isShoulder(),'Short interactions keep the frozen shoulder view')
camera.mode_changed('inventory');frame()
camera.mode_changed('puzzle');frame()
pc:SetViewTargetWithBlend(room,0.3)
camera.mode_changed('gameplay')
pawn.isInteractingWithPuzzleComp=true
frame()
assert(isShoulder(),'The lingering puzzle flag must not flash the room camera')
pawn.isInteractingWithPuzzleComp=false
frame()
assert(isShoulder())

-- A puzzle with its own close-up camera: shown natively, then straight back to the shoulder.
camera.mode_changed('puzzle')
pc:SetViewTargetWithBlend(closeUp,1.0)
assert(current==closeUp,'The game close-up must be shown during puzzles')
frame()
assert(current==closeUp,'The frozen update must not steal the close-up')
pc:SetViewTargetWithBlend(room,1.0)
assert(isShoulder(),'Leaving the close-up returns to the shoulder view, not the room camera')
camera.mode_changed('gameplay')
frame()
assert(isShoulder())

-- Close-up requested just before the puzzle flag is raised (redirected as a room camera).
pc:SetViewTargetWithBlend(closeUp,0.5)
assert(isShoulder())
pawn.isSolvingPuzzle=true
frame()
assert(current==closeUp,'A close-up redirected right before the puzzle must be restored')
pc:SetViewTargetWithBlend(room,0.5)
assert(isShoulder(),'The room camera from before the close-up is still recognised')
pawn.isSolvingPuzzle=false
frame()
assert(isShoulder())

-- Close-up recorded only as the game's current camera.
camera.mode_changed('puzzle')
gameInstance.CurrentCamera=closeUp
frame()
assert(current==closeUp,'The current game camera is shown when it is not the room camera')
gameInstance.CurrentCamera=room
camera.mode_changed('gameplay')
frame()
assert(isShoulder(),'After the hold the shoulder view is reclaimed')

-- Modes that need the native camera still restore it.
camera.mode_changed('cinematic')
assert(current==room,'Cinematics restore the native camera')
camera.mode_changed('gameplay')
frame()
assert(current==room,'Returning from a full restore warms up for one frame')
frame()
assert(isShoulder())
print('PASS: inventory/puzzle hold, native close-ups and warm-up after full restore')
