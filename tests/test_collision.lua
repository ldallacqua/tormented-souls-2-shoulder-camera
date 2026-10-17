-- Geometric mock: infinite planes swept by a sphere. Each wall blocks one side of an axis.
local walls={}
local function wall(name,axis,value,side,opts)
    opts=opts or {}
    local owner={IsValid=function() return true end,IsA=function(_,c) return opts.pawn and c=='/Script/Engine.Pawn' or false end}
    local component={IsValid=function() return true end,GetFullName=function() return name end,GetOwner=function() return owner end,
        IsA=function(_,c) return opts.widget and c=='/Script/UMG.WidgetComponent' or false end}
    walls[#walls+1]={axis=axis,value=value,side=side,component=component,owner=owner,complexOnly=opts.complexOnly}
end
local traces=0
local library={SphereTraceSingle=function(self,pawn,start,finish,radius,channel,complex,ignore,debug,hit)
    traces=traces+1
    assert(ignore[1]==pawn and (channel==0 or channel==1))
    local best=nil
    for _,w in ipairs(walls) do
        local skip=(w.complexOnly and not complex)
        for _,a in ipairs(ignore) do if a==w.owner then skip=true end end
        if not skip then
            local ds=w.side*(start[w.axis]-w.value)-radius
            local de=w.side*(finish[w.axis]-w.value)-radius
            local t=nil
            if ds<=0 then t=0 elseif de<0 then t=ds/(ds-de) end
            if t and (not best or t<best.t) then best={t=t,w=w} end
        end
    end
    if not best then return false end
    hit.Time=best.t
    hit.bStartPenetrating=true -- Reproduce the observed UE4SS packed-boolean read.
    hit.Component={Get=function() return best.w.component end}
    return true
end}
package.loaded.UEHelpers={GetKismetSystemLibrary=function() return library end}
local pawn={K2_GetActorLocation=function() return {X=0,Y=0,Z=0} end}
local collision=dofile(SOURCE..'/collision.lua')
local function solve(dt) return collision.solve(pawn,0,0,220,43,57,16,dt or 1/60) end
local function near(a,b,e) return math.abs(a-b)<(e or 0.5) end
-- yaw=0: camera looks along +X, so "behind" is -X and the right shoulder is +Y.

local arm,offset=solve()
assert(arm==220 and offset==43,'Clear space must preserve framing')

-- Regression: back against a wall 40 cm behind. The old diagonal sweep collapsed both
-- the arm and the shoulder offset, leaving the camera inside the head.
wall('BackWall','X',-40,1)
arm,offset=solve()
assert(near(offset,43),'A wall behind must not remove the shoulder offset')
assert(near(arm,22),'Arm stops at the wall minus probe radius and margin, got '..arm)
assert(collision.clearance>45,'Camera must stay beside the head, clearance='..collision.clearance)

-- Wall at 60% of the arm keeps a proportional distance.
walls={};collision.reset()
wall('FarWall','X',-148,1)
arm,offset=solve()
assert(near(arm,130),'Wall at 148 cm: arm should stop at ~130, got '..arm)

-- Side wall on the shoulder: lateral offset shrinks, back distance is untouched.
walls={};collision.reset()
wall('SideWall','Y',35,-1)
arm,offset=solve()
assert(near(offset,17),'Shoulder offset must stop at the side wall, got '..offset)
assert(arm==220,'Side wall must not shorten the arm')

-- Enemies and UI widgets in the way are ignored instead of collapsing the camera.
walls={};collision.reset()
wall('QuickTimeEvent_Widget','X',-20,1,{widget=true})
wall('Enemy','X',-30,1,{pawn=true})
arm=solve()
assert(arm==220,'Pawns/widgets must not block the camera, got '..arm)

-- Ornate trim thicker than the capsule: the 16 cm probe starts inside it at the head.
-- A thin retry keeps the camera at the shoulder instead of at the head pivot.
walls={};collision.reset()
wall('OrnateTrim','Y',-10,1,{complexOnly=true})
arm,offset=solve()
assert(collision.overlap,'Initial overlap must be reported')
assert(offset>40 and arm>200,'Initial overlap must not collapse the camera to the head')

-- Approaching a wall retracts immediately; releasing it eases out.
walls={};collision.reset()
wall('Close','X',-60,1)
local close=solve()
walls={}
local released=solve()
assert(released>close and released<220,'Release from wall must be smoothed')

-- Pinned in a corner: everything blocked -> camera.lua hides the character.
walls={};collision.reset()
wall('Back','X',-18,1);wall('Side','Y',18,-1)
solve()
assert(collision.clearance<30,'Corner case must report a small clearance')
print('PASS: two-stage collision (back wall, side wall, overlap retry, pawn/widget filter, smoothing)')
