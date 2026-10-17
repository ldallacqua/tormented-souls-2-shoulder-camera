-- RE4-style aim walk: camera-relative directions, backpedal/side-shuffle animation rates,
-- and a swept move that slides on walls, climbs small steps and never drops off ledges.
local walk=dofile(SOURCE..'/aimwalk.lua')
local cfg={aimWalkSpeed=96,aimBackSpeed=0.8}
local function close(a,b,eps) return math.abs(a-b)<(eps or 1e-3) end

assert(walk.plan(cfg,0,0,0,false)==nil,'No stick, no walk')
local f=walk.plan(cfg,0,1,90,false)
assert(close(f.dx,0) and close(f.dy,1),'Stick up walks towards the camera direction')
assert(close(f.speed,96) and close(f.rate,1) and close(f.stick,1),'Full forward is the native aim-walk')
local b=walk.plan(cfg,0,-1,0,false)
assert(close(b.dx,-1) and b.rate<0,'Stick down backpedals with the cycle reversed')
assert(close(b.speed,96*0.8),'Backpedal is slower')
assert(walk.plan(cfg,0,-1,0,true).rate>0,'A shot/reload montage never plays backwards')
local r=walk.plan(cfg,1,0,0,false)
assert(close(r.dx,0) and close(r.dy,1),'Stick right steps to the camera right (+Y at yaw 0)')
assert(r.rate>0 and r.rate<0.6,'Side steps use a short shuffle')
local half=walk.plan(cfg,0,0.5,0,false)
assert(close(half.speed,48) and close(half.rate,0.5) and close(half.stick,0.5),'Partial tilt walks slower')
assert(walk.plan(cfg,0.02,0.02,0,false)==nil,'Tiny input is ignored')

-- Mock world: floor at z=0 (capsule centre at 90), wall at x>=100, ledge at y<=-50,
-- a 20 cm step at x>=50 for y>=100.
local pos
local function floorAt(x,y)
    if y<=-50 then return -500 end
    if x>=50 and y>=100 then return 20 end
    return 0
end
local function blockedAt(x,y,z)
    if x>=100 then return true end
    if z-90<floorAt(x,y)-0.01 then return true end
    return false
end
local pawn={}
function pawn:K2_GetActorLocation() return {X=pos.X,Y=pos.Y,Z=pos.Z} end
function pawn:K2_SetActorLocation(to,sweep,hit)
    if not sweep then pos={X=to.X,Y=to.Y,Z=to.Z};return true end
    -- March towards the target; stop before the first blocked sample.
    local steps=50
    local last={X=pos.X,Y=pos.Y,Z=pos.Z}
    for i=1,steps do
        local t=i/steps
        local c={X=pos.X+(to.X-pos.X)*t,Y=pos.Y+(to.Y-pos.Y)*t,Z=pos.Z+(to.Z-pos.Z)*t}
        if blockedAt(c.X,c.Y,c.Z) then
            if hit then hit.ImpactNormal=(c.X>=100) and {X=-1,Y=0,Z=0} or {X=0,Y=0,Z=1} end
            pos=last;return true
        end
        last=c
    end
    pos=last
    return true
end

pos={X=0,Y=0,Z=92}
local moved=walk.move(pawn,10,0)
assert(close(moved,10,0.5) and close(pos.Z,92,1.5),'Plain floor move keeps the floor gap')

pos={X=95,Y=0,Z=92}
walk.move(pawn,10,10)
assert(pos.X<100 and pos.Y>5,'Diagonal into a wall slides along it')

pos={X=0,Y=-40,Z=92}
moved=walk.move(pawn,0,-20)
assert(moved==0 and close(pos.Y,-40) and close(pos.Z,92,1.5),'Never walk off a ledge while aiming')

pos={X=45,Y=120,Z=92}
walk.move(pawn,10,0)
assert(pos.X>50 and close(pos.Z,112,1.5),'Climb a small step')
print('PASS: aim walk plan (directions, backpedal, shuffle, montage safety) and swept move')
