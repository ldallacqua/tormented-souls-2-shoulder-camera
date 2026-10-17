-- Procedural camera motion: breathing sway and a slight lean into camera turns.
-- The rotation goes on FollowCamera, relative to the spring-arm socket that collision.lua
-- places, and stays within about a degree. No footstep bob: the walking oscillation caused
-- motion sickness in testing. Aiming keeps a slow, small sway; the crosshair is the screen
-- centre, so the aim point follows it.
local M={}
local lean,time=0,0
function M.reset() lean,time=0,0 end
local function ease(current,target,speed,dt) return current+(target-current)*(1-math.exp(-speed*dt)) end
-- yawRate: camera turn rate (deg/s).
function M.update(cfg,dt,yawRate,aiming)
    local sway=cfg.sway==false and 0 or (cfg.swayAmount or 1)
    time=(time+dt)%1000
    -- Lean slightly into camera turns.
    lean=ease(lean,math.max(-1.6,math.min(1.6,yawRate*0.008))*sway,5,dt)
    -- Breathing: two slow, incommensurate waves so it never looks like a loop.
    local breath=sway*(aiming and 1.4 or 1)
    local p=breath*(0.12*math.sin(time*1.38)+0.05*math.sin(time*3.33))
    local yw=breath*(0.10*math.sin(time*1.07+1.3)+0.04*math.sin(time*2.71))
    return {X=0,Y=0,Z=0},{pitch=p,Yaw=yw,Roll=lean}
end
return M
