-- RE4-style walking while aiming.
-- Findings (probed in game, see docs/AI_CONTEXT.md):
--  * The only locomotion the game has while aiming is the forward aim-walk cycle; it
--    plays whenever the character's StickX/StickY properties are non-zero.
--  * Writing those properties animates the legs without moving Caroline; the game only
--    moves her through SetStick*Value, turning her towards the stick first.
--  * Played backwards (negative GlobalAnimRateScale) the cycle is a correct backpedal.
--  * While aiming, external movement input is ignored, but a swept SetActorLocation works.
-- So camera.lua holds the game's stick input at zero, keeps Caroline facing the crosshair,
-- and this module moves her itself and drives the walk cycle and its rate.
local M={}
local STEP_UP=30 -- cm; small steps and thresholds.
local STEP_DOWN=40 -- cm; the floor must be this close or the move is undone (no ledge drops).
local FLOOR_GAP=2

-- Pure plan from the left stick (lx right, ly forward, already dead-zoned) and camera yaw.
-- Returns the world direction, speed (cm/s), the stick value that animates the cycle and
-- the animation rate (negative = backpedal; small = side shuffle).
function M.plan(cfg,lx,ly,cameraYaw,busy)
    local magnitude=math.min(1,math.sqrt(lx*lx+ly*ly))
    if magnitude<0.05 then return nil end
    local y=math.rad(cameraYaw)
    local fx,fy=math.cos(y),math.sin(y)
    local rx,ry=-math.sin(y),math.cos(y)
    local dx,dy=fx*ly+rx*lx,fy*ly+ry*lx
    local length=math.sqrt(dx*dx+dy*dy)
    dx,dy=dx/length,dy/length
    local forward,side=ly/magnitude,lx/magnitude
    local base=cfg.aimWalkSpeed or 96
    -- Backpedalling and side steps are a little slower, as in RE4.
    local speed=base*magnitude*(forward<0 and (cfg.aimBackSpeed or 0.8) or 1)*(1-0.25*math.abs(side))
    -- The cycle covers ~77 cm/s of ground at rate 1 while the game walks at 96 cm/s.
    local stride=speed/base
    local rate=math.max(math.abs(forward)*stride,0.55*math.abs(side)*stride,0.25)
    -- Shot and reload montages must not play backwards: backpedal feet slide while busy.
    if forward<-0.2 and not busy then rate=-rate end
    return {dx=dx,dy=dy,speed=speed,stick=magnitude,rate=rate}
end

local function flat(a,b) return math.sqrt((b.X-a.X)^2+(b.Y-a.Y)^2) end
local function sweep(p,to)
    local hit={}
    p:K2_SetActorLocation(to,true,hit,false)
    return hit
end
local function normalOf(hit)
    local ok,n=pcall(function() return hit.ImpactNormal or hit.Normal end)
    if not ok or not n then return nil end
    local x,y=n.X or 0,n.Y or 0
    local l=math.sqrt(x*x+y*y)
    if l<0.1 then return nil end
    return x/l,y/l
end
-- Horizontal swept move with one slide along whatever blocked it.
local function slideMove(p,dx,dy)
    local a=p:K2_GetActorLocation()
    local hit=sweep(p,{X=a.X+dx,Y=a.Y+dy,Z=a.Z})
    local b=p:K2_GetActorLocation()
    local want=math.sqrt(dx*dx+dy*dy)
    local moved=flat(a,b)
    if moved<want*0.95 then
        local nx,ny=normalOf(hit)
        if nx then
            local left=(want-moved)/want
            local rx,ry=dx*left,dy*left
            local into=rx*nx+ry*ny
            rx,ry=rx-nx*into,ry-ny*into
            if rx*rx+ry*ry>0.01 then sweep(p,{X=b.X+rx,Y=b.Y+ry,Z=b.Z}) end
        end
    end
    return p:K2_GetActorLocation()
end
-- Moves Caroline by (dx,dy) cm: slide along walls, climb small steps, follow the floor
-- down and refuse to walk off ledges. Returns the horizontal distance covered.
function M.move(p,dx,dy)
    local start=p:K2_GetActorLocation()
    local want=math.sqrt(dx*dx+dy*dy)
    if want<0.01 then return 0 end
    local after=slideMove(p,dx,dy)
    if flat(start,after)<want*0.5 then
        -- Blocked low: try the same move from a step higher (stairs, door sills).
        local flatEnd=after
        sweep(p,{X=start.X,Y=start.Y,Z=start.Z+STEP_UP})
        local raised=slideMove(p,dx,dy)
        if flat(start,raised)>flat(start,flatEnd)+0.5 then after=raised
        else p:K2_SetActorLocation(flatEnd,false,{},false);after=flatEnd end
    end
    -- Settle on the floor.
    sweep(p,{X=after.X,Y=after.Y,Z=after.Z-STEP_UP-STEP_DOWN})
    local landed=p:K2_GetActorLocation()
    if after.Z-landed.Z>=STEP_UP+STEP_DOWN-0.5 then
        p:K2_SetActorLocation(start,false,{},false)
        return 0
    end
    -- Hover like CharacterMovement does, so the next sweep does not start touching the floor.
    p:K2_SetActorLocation({X=landed.X,Y=landed.Y,Z=landed.Z+FLOOR_GAP},false,{},false)
    return flat(start,landed)
end
return M
