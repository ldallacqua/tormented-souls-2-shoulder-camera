local UEHelpers=require('UEHelpers')
-- Two-stage shoulder camera collision.
--   1. Lateral: sweep from the head pivot to the shoulder pivot.
--   2. Back: sweep from the (safe) shoulder pivot along the view direction.
-- Collapsing the whole arm towards the head pivot put the camera inside Caroline's head
-- whenever a wall was behind her. Keeping the shoulder offset leaves the camera beside
-- the head; camera.lua hides the character if the camera still ends up too close.
local M={lastHit='none',fraction=1,lateral=1,clearance=0,overlap=false}
local color={R=0,G=0,B=0,A=0}
local backFraction,lateralFraction=1,1
-- ETraceTypeQuery: TraceTypeQuery1=Visibility, TraceTypeQuery2=Camera. Visibility with
-- simple and complex geometry catches set dressing; Camera keeps the old spring-arm checks.
local queries={{channel=0,complex=false},{channel=0,complex=true},{channel=1,complex=false}}
local MARGIN=2 -- cm kept between the probe sphere and the obstacle.
local MAX_IGNORED=4
function M.reset() backFraction,lateralFraction=1,1 end

local function component(hit)
    local ok,c=pcall(function() return hit.Component:Get() end)
    if ok and c and c:IsValid() then return c end
    return nil
end
-- Pawns (enemies, NPCs) and UI widgets must not pull the camera into the head.
local function ignorable(c)
    if c:IsA('/Script/UMG.WidgetComponent') then return true end
    local owner=c:GetOwner()
    return owner and owner:IsValid() and owner:IsA('/Script/Engine.Pawn') or false
end

-- Returns the safe travel fraction [0,1] of a sphere sweep from start to finish.
local function sweep(pawn,start,finish,radius,length)
    if length<0.01 then return 1,nil,false end
    local best,bestName,overlap=1,nil,false
    local library=UEHelpers.GetKismetSystemLibrary()
    for _,q in ipairs(queries) do
        local ignore={pawn}
        for _=1,MAX_IGNORED do
            local hit={}
            local blocked=library:SphereTraceSingle(pawn,start,finish,radius,q.channel,q.complex,ignore,0,hit,true,color,color,0)
            if not blocked then break end
            local c=component(hit)
            if c and ignorable(c) then
                ignore[#ignore+1]=c:GetOwner()
            else
                -- UE4SS reports the packed bStartPenetrating bit as true for ordinary hits in
                -- this build; Time is reliable and a genuine initial overlap has Time=0.
                local time=math.max(0,math.min(1,hit.Time))
                if time<=0 then overlap=true end
                local t=math.max(0,time-MARGIN/length)
                if t<best then best=t;bestName=c and c:GetFullName() or 'geometry' end
                break
            end
        end
    end
    return best,bestName,overlap
end

-- Sweep with the requested radius; if the probe already overlaps geometry at its start
-- (ornate trims are often thicker than the character capsule), retry with a thin probe
-- instead of collapsing the camera to the start point.
local function safeSweep(pawn,start,finish,radius,length)
    local t,name,overlap=sweep(pawn,start,finish,radius,length)
    if overlap and t<=0 then
        local t2,name2=sweep(pawn,start,finish,math.max(4,radius*0.35),length)
        return t2,name2 or name,true
    end
    return t,name,overlap
end

local function ease(current,safe,dt)
    -- Retract immediately to avoid clipping, ease out once the obstruction clears.
    if safe<current then return safe end
    return current+(safe-current)*(1-math.exp(-8*dt))
end

function M.solve(pawn,yaw,pitch,distance,shoulder,height,radius,dt)
    local p=pawn:K2_GetActorLocation()
    local head={X=p.X,Y=p.Y,Z=p.Z+height}
    local yr,pr=math.rad(yaw),math.rad(pitch)
    -- Spring-arm basis (roll=0): right is yaw-only, forward includes pitch.
    local rx,ry=-math.sin(yr),math.cos(yr)
    local fx,fy,fz=math.cos(pr)*math.cos(yr),math.cos(pr)*math.sin(yr),math.sin(pr)

    local shoulderPoint={X=head.X+rx*shoulder,Y=head.Y+ry*shoulder,Z=head.Z}
    local lateralSafe,lateralHit,lateralOverlap=safeSweep(pawn,head,shoulderPoint,radius,math.abs(shoulder))
    lateralFraction=ease(lateralFraction,lateralSafe,dt)
    local offset=shoulder*lateralFraction
    local pivot={X=head.X+rx*offset,Y=head.Y+ry*offset,Z=head.Z}

    local finish={X=pivot.X-fx*distance,Y=pivot.Y-fy*distance,Z=pivot.Z-fz*distance}
    local backSafe,backHit,backOverlap=safeSweep(pawn,pivot,finish,radius,distance)
    backFraction=ease(backFraction,backSafe,dt)
    local arm=distance*backFraction

    M.lastHit=backHit or lateralHit or 'none'
    M.overlap=lateralOverlap or backOverlap
    M.fraction=backFraction;M.lateral=lateralFraction
    -- Back and right axes are orthogonal: distance from the head pivot to the camera.
    M.clearance=math.sqrt(arm*arm+offset*offset)
    return arm,offset
end
return M
