local UEHelpers=require('UEHelpers')
local M={lastHit='none',fraction=1}
local color={R=0,G=0,B=0,A=0}
local fraction=1
function M.reset() fraction=1 end
function M.solve(pawn,yaw,pitch,distance,shoulder,height,radius,dt)
    local p=pawn:K2_GetActorLocation()
    local start={X=p.X,Y=p.Y,Z=p.Z+height}
    local yr,pr=math.rad(yaw),math.rad(pitch)
    local dx=-math.cos(pr)*math.cos(yr)*distance-math.sin(yr)*shoulder
    local dy=-math.cos(pr)*math.sin(yr)*distance+math.cos(yr)*shoulder
    local dz=-math.sin(pr)*distance
    local finish={X=start.X+dx,Y=start.Y+dy,Z=start.Z+dz}
    local length=math.sqrt(dx*dx+dy*dy+dz*dz)
    local safe=1
    M.lastHit='none'
    -- TraceTypeQuery1 is Visibility. Query both simple collision and mesh geometry.
    -- Some set dressing ignores the Camera channel used by the native spring arm.
    for _,complex in ipairs({false,true}) do
        local hit={}
        local blocked=UEHelpers.GetKismetSystemLibrary():SphereTraceSingle(
            pawn,start,finish,radius,0,complex,{pawn},0,hit,true,color,color,0)
        if blocked then
            -- UE4SS reports the packed bStartPenetrating bit as true for ordinary
            -- blocking hits in this build. Time/Distance remain correct; a true
            -- initial overlap already has Time=0. Do not collapse every hit to 0.
            local t=math.max(0,math.min(1,hit.Time)-2/math.max(length,1))
            if t<safe then
                safe=t
                local component=hit.Component:Get()
                M.lastHit=component and component:IsValid() and component:GetFullName() or 'geometry'
            end
        end
    end
    -- Retract immediately to avoid clipping, ease out once the obstruction clears.
    if safe<fraction then fraction=safe else fraction=fraction+(safe-fraction)*(1-math.exp(-8*dt)) end
    M.fraction=fraction
    return distance*fraction,shoulder*fraction
end
return M
