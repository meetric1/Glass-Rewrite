AddCSLuaFile()

// to shut up console
ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.Spawnable = false

local models = {
    "models/hunter/plates/plate1x1.mdl",
    "models/hunter/plates/plate2x2.mdl",
    "models/hunter/plates/plate4x4.mdl",
    "models/hunter/blocks/cube1x1x025.mdl",
    "models/hunter/blocks/cube2x2x025.mdl",
    "models/hunter/blocks/cube4x4x025.mdl",
    "models/hunter/blocks/cube1x1x1.mdl",
    "models/hunter/blocks/cube2x2x2.mdl",
    "models/hunter/blocks/cube4x4x4.mdl",
}

local names = {
    "Glass Thin 1",
    "Glass Thin 2",
    "Glass Thin 4",
    "Glass Thick 1",
    "Glass Thick 2",
    "Glass Thick 4",
    "Glass Block 1",
    "Glass Block 2",
    "Glass Block 4",
}

local use_expensive = CreateConVar("glass_expensive_material", 0, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Use nicer material", 0, 1)

for k, v in ipairs(models) do
    local ENT = scripted_ents.Get("procedural_shard")
    ENT.Spawnable = true
    ENT.PrintName =  names[k]
    function ENT:SpawnFunction(ply, tr, class)
        local block = ents.Create("procedural_shard")
        block:SetPos(tr.HitPos)
        block:SetAngles(Angle(90, ply:EyeAngles()[2], 0))
        block:SetPhysModel(v)
        block:Spawn()
        block:BuildCollision(util.GetModelMeshes(block:GetPhysModel())[1].triangles)
        if use_expensive:GetBool() then block:SetMaterial("glass_rewrite/glass_refract") end

        local phys = block:GetPhysicsObject()
        if phys then phys:EnableMotion(false) end

        return block
    end

    scripted_ents.Register(ENT, "procedural_shard_" .. k)
end

local ENT = scripted_ents.Get("procedural_shard")
ENT.Spawnable = true
ENT.PrintName =  "​100% Fragile"
ENT.AdminOnly = true
function ENT:SpawnFunction(ply, tr, class)
    local block = ents.Create("procedural_shard")
    block:SetPos(tr.HitPos)
    block:SetAngles(Angle(90, ply:EyeAngles()[2], 0))
    block:SetPhysModel("models/hunter/blocks/cube2x2x025.mdl")
    block:Spawn()
    block:SetMaterial("phoenix_storms/stripes")
    block:BuildCollision(util.GetModelMeshes(block:GetPhysModel())[1].triangles)
    block.IS_FUNNY_GLASS = true

    local phys = block:GetPhysicsObject()
    if phys then phys:EnableMotion(false) end

    return block
end

scripted_ents.Register(ENT, "procedural_shard_fragile")

