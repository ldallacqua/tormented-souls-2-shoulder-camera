-- RE4-style aim walk: camera-relative directions, Caroline's own backpedal/side-step montages,
-- reversed aim walk for the backpedal, and movement through CharacterMovement.
local walk=dofile(SOURCE..'/aimwalk.lua')
local cfg={aimWalkSpeed=96,aimBackSpeed=0.9,aimSideSpeed=0.85}
local function close(a,b,eps) return math.abs(a-b)<(eps or 1e-3) end

assert(walk.plan(cfg,0,0,0)==nil,'No stick, no walk')
local f=walk.plan(cfg,0,1,90)
assert(close(f.dx,0) and close(f.dy,1),'Stick up walks towards the camera direction')
assert(f.anim=='forward' and close(f.speed,96) and close(f.rate,1) and close(f.stick,1),'Full forward is the native aim-walk')
local b=walk.plan(cfg,0,-1,0)
assert(close(b.dx,-1) and b.anim=='back' and b.stick==0,'Stick down backpedals with its own animation')
assert(b.rate>0,'Animations never play backwards (negative rates broke the spine)')
assert(close(b.speed,92*0.9),'Backpedal speed matches its animation')
local r=walk.plan(cfg,1,0,0)
assert(close(r.dx,0) and close(r.dy,1) and r.anim=='right','Stick right steps to the camera right (+Y at yaw 0)')
assert(walk.plan(cfg,-1,0,0).anim=='left','Stick left steps left')
assert(walk.plan(cfg,0.7,0.7,0).anim=='forward' and walk.plan(cfg,0.7,-0.7,0).anim=='back','Diagonals keep forward/back cycles')
local half=walk.plan(cfg,0,0.5,0)
assert(close(half.speed,48) and close(half.rate,0.5) and close(half.stick,0.5),'Partial tilt walks slower')
assert(walk.plan(cfg,0.02,0.02,0)==nil,'Tiny input is ignored')

-- Animator: plays/loops/stops one slot montage per direction; missing assets fail soft.
function FName(s) return {name=s} end
local seqs={}
function StaticFindObject(path) seqs[path]=seqs[path] or {path=path,IsValid=function() return true end,GetPlayLength=function() return 1.0 end};return seqs[path] end
local log={}
local playing,calls=nil,{}
local inst={IsValid=function() return true end}
function inst:PlaySlotAnimationAsDynamicMontage(seq,slot,bi,bo,rate,loops)
    assert(seq and slot and slot.name=='DefaultSlot' and rate>0,'Engine arguments are always set')
    playing={seq=seq.path,rate=rate,IsValid=function() return true end};calls[#calls+1]='play'
    return playing
end
function inst:Montage_IsPlaying(m) return playing==m end
function inst:Montage_SetPlayRate(m,r) m.rate=r end
function inst:StopSlotAnimation(t,slot) assert(slot.name=='DefaultSlot');playing=nil;calls[#calls+1]='stop' end
local pawnA={Mesh={GetAnimInstance=function() return inst end}}
local anim=walk.animator({aimWalkSlot='DefaultSlot'},function(s) log[#log+1]=s end)
assert(anim:update(pawnA,'forward',1)==false and #calls==0,'Forward uses the native cycle')
assert(anim:update(pawnA,'back',0.9)==true and playing.seq:find('back_pedal'),'Backpedal montage')
anim:update(pawnA,'back',0.6)
assert(#calls==1 and close(playing.rate,0.6),'Same direction only changes the rate')
playing=nil -- interrupted by the game (e.g. a hit reaction)
anim:update(pawnA,'back',0.6)
assert(calls[#calls]=='play','An interrupted montage restarts')
anim:update(pawnA,'right',0.85)
assert(calls[#calls-1]=='stop' and playing.seq:find('side_step_Right'),'Direction change swaps montage')
anim:update(pawnA,nil,1)
assert(playing==nil and calls[#calls]=='stop','Releasing the stick stops the montage')
function StaticFindObject() return {IsValid=function() return false end} end
log={}
local anim2=walk.animator({},function(s) log[#log+1]=s end)
assert(anim2:update(pawnA,'left',1)==false and #log==1,'Missing animation logs once and falls back')

-- Backpedal: the weapon's aim walk reversed; unknown weapons fall back to back_pedal.
local path,rev=walk.backSequence('Nailgun')
assert(path:find('Nailer_Walk_Aim',1,true) and rev,'Nailgun backpedals with its aim walk reversed')
assert(walk.backSequence('AutoNailgun'):find('Automatic_Nailer',1,true),'Automatic nailer has its own aim walk')
path,rev=walk.backSequence('Shotgun')
assert(path:find('back_pedal',1,true) and not rev,'Unknown aim walk falls back to back_pedal')
local revPlays={}
local inst2={IsValid=function() return true end}
local pos=0
function inst2:PlaySlotAnimationAsDynamicMontage(seq,slot,bi,bo,rate,loops,trigger,start)
    revPlays[#revPlays+1]={rate=rate,start=start};pos=start
    playing={IsValid=function() return true end,rate=rate};return playing
end
function inst2:Montage_IsPlaying(m) return playing==m end
function inst2:Montage_SetPlayRate(m,r) m.rate=r end
function inst2:Montage_GetPosition() return pos end
function inst2:Montage_SetPosition(m,p) pos=p end
function inst2:StopSlotAnimation() playing=nil end
function StaticFindObject(p) return {IsValid=function() return true end,GetPlayLength=function() return 1.0 end} end
local pawnB={Mesh={GetAnimInstance=function() return inst2 end},currentWeaponID={ToString=function() return 'Nailgun' end}}
local anim3=walk.animator({},function() end)
anim3:update(pawnB,'back',0.8)
assert(revPlays[1].rate<0 and revPlays[1].start>0.9,'Reversed montage starts at the end with a negative rate')
pos=0.02;anim3:update(pawnB,'back',0.8)
assert(pos>0.9,'Reversed montage wraps around instead of ending')
anim3:update(pawnB,'back',0.5)
assert(close(playing.rate,-0.5),'Rate changes keep the direction')

-- Movement goes through CharacterMovement with friction and braking off, restored after.
local cm={GroundFriction=8,BrakingDecelerationWalking=2048,bCanWalkOffLedges=true,Velocity={X=0,Y=0,Z=-3},IsValid=function() return true end}
local pawnM={CharacterMovement=cm}
for _=1,60 do walk.drive(pawnM,50,-20,0.016) end
assert(cm.GroundFriction==0 and cm.BrakingDecelerationWalking==0 and cm.bCanWalkOffLedges==false,'Friction/braking off, no ledge drops')
assert(close(cm.Velocity.X,50,0.5) and close(cm.Velocity.Y,-20,0.5) and cm.Velocity.Z==-3,'Velocity eases to the target, gravity untouched')
walk.drive(pawnM,0,0,0.016)
assert(cm.Velocity.X<50 and cm.Velocity.X>0,'Stopping eases out')
walk.release(pawnM)
assert(cm.GroundFriction==8 and cm.BrakingDecelerationWalking==2048 and cm.bCanWalkOffLedges==true,'Originals restored')
assert(cm.Velocity.X==0 and cm.Velocity.Y==0 and not walk.driving(),'Release stops her')
walk.release(pawnM)
-- Weapon IDs are matched loosely: both spellings of the cannon, the machine-gun folder name.
for id,want in pairs({HandCanon='HandCannon_Walk_aim',HandCannon='HandCannon_Walk_aim',Machinegun='Automatic_Nailer_Aim_Walk',
        AutomaticNailer='Automatic_Nailer_Aim_Walk',Nailgun='Nailer_Walk_Aim',Hammer='Hammer_Aim_Walk',Crowbar='Crowbar_Walk_Aim'}) do
    local path,reverse=walk.backSequence(id)
    assert(path:find(want,1,true) and reverse,'Aim walk for '..id)
end
local path,reverse=walk.backSequence('SomethingElse')
assert(path:find('back_pedal',1,true) and not reverse,'Unknown weapons fall back to back_pedal')
print('PASS: aim walk plan, own side-step and reversed aim-walk montages, CharacterMovement drive')
