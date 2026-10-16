local hitTime=nil
local complexTime=nil
local component={IsValid=function() return true end,GetFullName=function() return 'TestWall' end}
local library={SphereTraceSingle=function(self,pawn,start,finish,radius,channel,complex,ignore,debug,hit)
    assert(channel==0 and ignore[1]==pawn)
    local t=complex and complexTime or hitTime
    if t==nil then return false end
    hit.Time=t;hit.Distance=t*220
    hit.bStartPenetrating=true -- Reproduce the observed UE4SS packed-boolean read.
    hit.Component={Get=function() return component end}
    return true
end}
package.loaded.UEHelpers={GetKismetSystemLibrary=function() return library end}
local pawn={K2_GetActorLocation=function() return {X=0,Y=0,Z=0} end}
local collision=dofile(SOURCE..'/collision.lua')
local arm,shoulder=collision.solve(pawn,0,0,220,43,57,16,1/60)
assert(arm==220 and shoulder==43,'Clear space must preserve framing')
hitTime=0.6;complexTime=0.7
arm,shoulder=collision.solve(pawn,0,0,220,43,57,16,1/60)
assert(arm>125 and arm<132,'A wall 60% along the arm must not collapse the camera to the head')
assert(math.abs(shoulder/43-arm/220)<0.00001,'Shoulder offset must follow the same swept ray')
hitTime=0.2;complexTime=0.4
local closeArm=collision.solve(pawn,0,0,220,43,57,16,1/60)
assert(closeArm<44,'Approaching wall must retract immediately')
hitTime=nil;complexTime=nil
local released=collision.solve(pawn,0,0,220,43,57,16,1/60)
assert(released>closeArm and released<220,'Release from wall must be smoothed')
hitTime=0;complexTime=0
local initial=collision.solve(pawn,0,0,220,43,57,16,1/60)
assert(initial==0,'A real initial overlap must remain blocked')
print('PASS: collision distance, packed boolean regression, offset, retraction and release')
