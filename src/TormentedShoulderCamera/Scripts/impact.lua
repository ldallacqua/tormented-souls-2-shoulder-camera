-- Marks where player shots land, to check free aim against the crosshair (cfg.impactMarks).
-- The free-aim hooks queue each adjusted shot; it is traced on the next frame (never inside
-- the native hook) and a decal is placed on the surface hit. Enemies get no mark: a decal
-- would hang in the air once they move.
-- Probed: the game's particle decal materials (MI_BurnDecal, MI_GroundCrackDecal) render as
-- plain squares outside Niagara. The Megascans decal master with a black albedo and the
-- game's Impact23 particle texture as its DRO (opacity) map gives a dark impact star.
local UEHelpers=require('UEHelpers')
local M={}
M.materials={
    '/Game/Megascans/Decals/Blood_Stain_sheadaac/MI_Blood_Stain_sheadaac_4K.MI_Blood_Stain_sheadaac_4K',
    '/Game/MSPresets/M_MS_Decal_Material/M_MS_Decal_Material.M_MS_Decal_Material',
}
M.textures={
    Albedo='/Engine/EngineResources/Black.Black',
    Normal='/Engine/EngineMaterials/FlatNormal.FlatNormal',
    DRO='/Game/Particles/Textures/Impact23.Impact23',
}
local MAX_PENDING=16
local pending={}
local material=nil -- false once the material or a texture failed to load.
local textures={}
local noColor={R=0,G=0,B=0,A=0}
local function valid(o) return o~=nil and o.IsValid~=nil and o:IsValid() end
local function vec(v) return {X=v.X,Y=v.Y,Z=v.Z} end

-- The trace and rotation hooks can both report one shot. A traced shot (kind 'trace') is what
-- hits; the flight direction of the same ammo (kind 'flight', same key) is then dropped.
function M.queue(start,dir,length,key,kind)
    for _,s in ipairs(pending) do
        local d,o=s.dir,s.start
        if d.X*dir.X+d.Y*dir.Y+d.Z*dir.Z>0.99995 and (o.X-start.X)^2+(o.Y-start.Y)^2+(o.Z-start.Z)^2<2500 then return end
    end
    if #pending<MAX_PENDING then pending[#pending+1]={start=vec(start),dir=vec(dir),length=length,key=key,kind=kind} end
end
function M.pending() return #pending end

local function load(path)
    local o=StaticFindObject(path)
    if not valid(o) and LoadAsset then pcall(function() o=LoadAsset(path) end) end
    return valid(o) and o or nil
end
-- Loaded once; reloaded if a level change dropped any of them.
local function find(log)
    if material==false then return nil end
    local ready=valid(material)
    for name in pairs(M.textures) do if not valid(textures[name]) then ready=false end end
    if ready then return material end
    material=nil
    for _,path in ipairs(M.materials) do material=material or load(path) end
    for name,path in pairs(M.textures) do textures[name]=load(path) end
    local missing=not material
    for name in pairs(M.textures) do if not textures[name] then missing=true end end
    if missing then material=false;log('Impact marks unavailable: decal material or texture not found');return nil end
    log('Impact marks use '..material:GetFName():ToString())
    return material
end

-- Traces the queued shots and marks the surfaces hit. Returns the number of marks placed.
function M.flush(cfg,p,channel,log)
    if #pending==0 then return 0 end
    local shots=pending
    pending={}
    local traced={}
    for _,s in ipairs(shots) do if s.kind=='trace' and s.key then traced[s.key]=true end end
    if not cfg.impactMarks or not valid(p) then return 0 end
    local decal=find(log)
    if not decal then return 0 end
    local size=cfg.impactMarkSize or 5
    local placed=0
    for _,s in ipairs(shots) do
        if not (s.kind=='flight' and traced[s.key]) then
            local finish={X=s.start.X+s.dir.X*s.length,Y=s.start.Y+s.dir.Y*s.length,Z=s.start.Z+s.dir.Z*s.length}
            local hit={}
            if UEHelpers.GetKismetSystemLibrary():LineTraceSingle(p,s.start,finish,channel,true,{p},0,hit,true,noColor,noColor,0) then
                local owner=nil
                pcall(function() local c=hit.Component:Get();if valid(c) then owner=c:GetOwner() end end)
                local n=hit.ImpactNormal
                if n and hit.ImpactPoint and not (valid(owner) and owner:IsA('/Script/Engine.Pawn')) then
                    -- The decal box projects along its X axis: point it into the surface.
                    local rotation={pitch=math.deg(math.asin(math.max(-1,math.min(1,-n.Z)))),Yaw=math.deg(math.atan(-n.Y,-n.X)),Roll=math.random()*360}
                    local d=UEHelpers.GetGameplayStatics():SpawnDecalAtLocation(p,decal,{X=4,Y=size,Z=size},vec(hit.ImpactPoint),rotation,cfg.impactMarkSeconds or 30)
                    local mid=valid(d) and d:CreateDynamicMaterialInstance() or nil
                    if valid(mid) then
                        for name,texture in pairs(textures) do mid:SetTextureParameterValue(FName(name),texture) end
                        placed=placed+1
                    elseif valid(d) then
                        d:SetHiddenInGame(true,false) -- Never leave the base blood stain behind.
                    end
                end
            end
        end
    end
    return placed
end
function M.clear() pending={} end
return M
