-- Camera motion has no footstep bob (it caused motion sickness): only a subtle breathing
-- sway and a capped lean into turns, both switchable.
local motion=dofile(SOURCE..'/motion.lua')
local cfg={sway=true,swayAmount=1}
local function run(seconds,yawRate,aiming,config)
    local maxPitch,maxYaw=0,0
    local loc,rot
    for _=1,math.floor(seconds/0.016) do
        loc,rot=motion.update(config or cfg,0.016,yawRate or 0,aiming)
        assert(loc.X==0 and loc.Y==0 and loc.Z==0,'The camera position never oscillates')
        maxPitch=math.max(maxPitch,math.abs(rot.pitch));maxYaw=math.max(maxYaw,math.abs(rot.Yaw))
    end
    return {pitch=maxPitch,yaw=maxYaw,rot=rot}
end

motion.reset()
local idle=run(6)
assert(idle.pitch>0.02 and idle.pitch<0.3 and idle.yaw<0.3,'Breathing sway is present but subtle')

motion.reset()
local turning=run(1.5,300)
assert(turning.rot.Roll>1 and turning.rot.Roll<=1.7,'Lean into a fast right turn, capped')
local back=run(2,0)
assert(math.abs(back.rot.Roll)<0.2,'Lean returns when the turn stops')

motion.reset()
local off=run(3,300,false,{sway=false})
assert(off.pitch==0 and off.yaw==0 and off.rot.Roll==0,'Sway can be switched off')
print('PASS: no camera bob, subtle breathing sway, capped turn lean and switch')
