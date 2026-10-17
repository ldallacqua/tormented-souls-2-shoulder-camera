-- Controller polish: L3 shoulder swap glides, aiming blends distance, the stick curve
-- softens small inputs and the quick turn keeps running away until the stick is released.
function FName(s) return {ToString=function() return s end} end
local function object(name,fields)
    local o=fields or {}
    o.IsValid=function() return true end
    o.GetAddress=function() return name end
    o.GetFName=function() return FName(name) end
    o.GetFullName=function() return name end
    o.IsA=function() return true end
    return o
end
function StaticFindObject(path) return object(path) end
local hooks={}
function RegisterHook(path,callback) hooks[path]=callback;return 1,2 end
function UnregisterHook() end
package.loaded.UEHelpers={GetGameInstance=function() return nil end}
local solved={}
local stub={clearance=220,reset=function() end,solve=function(_,_,_,d,s,h) solved={distance=d,shoulder=s,height=h} return d,s end}
local realDofile=dofile
dofile=function(path)
    local n=path:match('[^/\\]+$')
    if n=='collision.lua' then return stub end
    if n=='input.lua' then return {update=function() end,restore=function() end} end
    if n=='aim.lua' then return {init=function() end,update=function() end,clear=function() end,shutdown=function() end} end
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
    NorthCamera=rotator(0),RAfterCameraChange=rotator(0),['Last Camera Rotator']=rotator(0),['Current Camera Rotator']=rotator(0)})
pawn.K2_GetActorRotation=function() return rotator(0) end
pawn.K2_SetActorRotation=function() end
pawn.Mesh={GlobalAnimRateScale=1}
-- Open floor with the capsule centre resting at z=90.
local pos={X=0,Y=0,Z=92}
pawn.K2_GetActorLocation=function() return {X=pos.X,Y=pos.Y,Z=pos.Z} end
pawn.K2_SetActorLocation=function(_,to,sweep) pos={X=to.X,Y=to.Y,Z=sweep and math.max(to.Z,90) or to.Z} return true end
local axes,buttons={},{}
local control=rotator(0)
local pc=object('Controller',{Pawn=pawn})
pc.GetInputAnalogKeyState=function(_,k) return axes[k.KeyName:ToString()] or 0 end
pc.IsInputKeyDown=function(_,k) return buttons[k.KeyName:ToString()] or false end
pc.SetControlRotation=function(_,r) control=r end
pc.GetViewTarget=function() return pawn end
pc.SetViewTargetWithBlend=function() end
local function frames(n) for _=1,n do camera.update(pc,0.016) end end
local function close(a,b,eps) return math.abs(a-b)<(eps or 0.5) end

frames(2)
assert(close(solved.shoulder,43) and close(solved.distance,220),'Default framing on activation')

-- L3: one press swaps once, and the offset glides to the other shoulder.
buttons.Gamepad_LeftThumbstick=true
frames(1)
assert(solved.shoulder>0 and solved.shoulder<43,'The swap must glide, not snap')
frames(3)
buttons.Gamepad_LeftThumbstick=false
frames(60)
assert(close(solved.shoulder,-43),'Holding L3 swaps only once')

-- Aiming blends to the aim distance.
pawn.isAiming=true
frames(1)
assert(solved.distance<220 and solved.distance>170,'Aim zoom must blend')
frames(60)
assert(close(solved.distance,170))
pawn.isAiming=false
frames(60)

-- Stick curve: half deflection turns slower than linear.
local before=control.Yaw
axes.Gamepad_RightX=0.6
frames(10)
axes.Gamepad_RightX=0
local turned=(control.Yaw-before)%360
local linear=(0.6-0.2)/0.8*135*0.16
assert(turned<linear*0.8 and turned>0,'The response curve must soften small inputs')

-- Quick turn: stick back + run/dodge turns the camera 180 degrees.
local startYaw=control.Yaw
axes.Gamepad_LeftY=-1
buttons.Gamepad_FaceButton_Left=true
frames(1)
buttons.Gamepad_FaceButton_Left=false
frames(30)
assert(close((control.Yaw-startYaw)%360,180,0.01),'Quick turn must rotate the camera 180 degrees')
assert(close(pawn.NorthCamera.Yaw,startYaw,0.01),'Movement keeps the old reference while the stick is held')
axes.Gamepad_LeftY=0
frames(1)
assert(close(pawn.NorthCamera.Yaw,control.Yaw,0.01),'Releasing the stick hands movement to the new view')

-- No quick turn without the stick held back, or while aiming.
startYaw=control.Yaw
buttons.Gamepad_FaceButton_Left=true;frames(1);buttons.Gamepad_FaceButton_Left=false;frames(20)
assert(close(control.Yaw,startYaw,0.01),'Run/dodge alone must not turn the camera')
pawn.isAiming=true;axes.Gamepad_LeftY=-1
buttons.Gamepad_FaceButton_Left=true;frames(1);buttons.Gamepad_FaceButton_Left=false;frames(20)
assert(close(control.Yaw,startYaw,0.01),'No quick turn while aiming')

-- Aiming: the game's movement input is held at zero; the left stick walks RE4-style.
local stickX='/Script/TormentedSouls2.TormentedSouls2Character:SetStickXValue'
local function feed(v)
    local value=v
    hooks[stickX]({get=function() return pawn end},{get=function() return value end,set=function(_,n) value=n end})
    return value
end
pawn.isAiming=true;axes.Gamepad_LeftY=0
frames(1)
assert(feed(0.8)==0,'Movement input is held while aiming')
startYaw=control.Yaw
local before={X=pos.X,Y=pos.Y}
axes.Gamepad_LeftY=-1
frames(30)
assert(close(control.Yaw,startYaw,0.01),'Walking while aiming does not turn the aim')
local backward=(pos.X-before.X)*math.cos(math.rad(startYaw))+(pos.Y-before.Y)*math.sin(math.rad(startYaw))
assert(backward<-20,'Stick down backpedals away from the crosshair')
assert(pawn.StickY>0 and pawn.Mesh.GlobalAnimRateScale<-0.5,'The walk cycle plays reversed for the backpedal')
axes.Gamepad_LeftY=0
frames(30)
assert(pawn.StickY==0 and pawn.Mesh.GlobalAnimRateScale>0.9,'Releasing the stick stops the cycle')
pawn.isAiming=false
frames(1)
assert(pawn.Mesh.GlobalAnimRateScale==1,'Leaving aim restores the animation rate')
assert(feed(0.8)==0.8,'Movement input is untouched when not aiming')
print('PASS: L3 shoulder swap, aim blend, stick curve, quick turn and aim stick hold')
