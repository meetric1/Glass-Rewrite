AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"

ENT.Category		= "Glass: Rewrite"
ENT.Author			= "Mee"
ENT.Purpose			= "Destructable Fun"
ENT.Instructions	= "Spawn and damage it"
ENT.Spawnable		= false

local generateUV, generateNormals, simplify_vertices, split_convex, split_entity = include("world_functions.lua")

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "PhysModel")
    self:NetworkVar("Vector", 0, "PhysScale")
    self:NetworkVar("Entity", 0, "ReferenceShard")
    self:NetworkVar("Entity", 1, "OriginalShard")
end

local use_expensive = CreateConVar("glass_lagfriendly", 0, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "", 0, 1)

function ENT:BuildCollision(verts, pointer)
    local new_verts, offset = simplify_vertices(verts, self:GetPhysScale())
    self:EnableCustomCollisions()
	self:PhysicsInitConvex(new_verts)

    // physics object isnt valid, remove cuz its probably weird
    if SERVER then
        local phys = self:GetPhysicsObject()
        if !phys:IsValid() then
            SafeRemoveEntity(self)
        else
            local bounding = self:BoundingRadius()
            if bounding < 40 and self:GetOriginalShard():IsValid() then
                self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
                if use_expensive then self:SetCollisionGroup(COLLISION_GROUP_WORLD) end
                if bounding < 20 then 
                    // glass effect
                    local data = EffectData() data:SetOrigin(self:GetPos())
                    util.Effect("GlassImpact", data)
                    SafeRemoveEntity(self)
                    return
                end
            end
            phys:SetMass(math.sqrt(phys:GetVolume()))
            phys:SetMaterial("glass")
            phys:SetPos(self:LocalToWorld(offset))
            self.TRIANGLES = phys:GetMesh()

            if pointer then pointer[1] = true end     // cant return true because of weird SENT issues, just use table pointer to indicate success
        end
    else
        self:SetRenderBounds(self:OBBMins(), self:OBBMaxs())
        local phys = self:GetPhysicsObject()
        if phys:IsValid() then
            phys:SetMaterial("glass")
        end
    end
end

if CLIENT then
    function ENT:Think()
        local physobj = self:GetPhysicsObject()
        if !physobj:IsValid() then 
            self:SetNextClientThink(CurTime())
            return true
        end

        if (self:GetPos() == physobj:GetPos() and !physobj:IsMotionEnabled()) then
            self:SetNextClientThink(CurTime() + 0.1)
            return true
        end

        physobj:EnableMotion(false)
        physobj:SetPos(self:GetPos())
        physobj:SetAngles(self:GetAngles())
        self:SetNextClientThink(CurTime())
    end

    function ENT:GetRenderMesh()
        if !self.RENDER_MESH then return end
        return self.RENDER_MESH
    end

    function ENT:OnRemove()
        if self.RENDER_MESH and self.RENDER_MESH.Mesh:IsValid() then
            self.RENDER_MESH.Mesh:Destroy()
        end
    end
else
    function ENT:Split(pos, explode, norm)
        local self = self
        if explode then pos = pos * 0.5 end  // if explosion, kind of "shrink" position closer to the center of the shard
        local function randPos() return pos end
        local convexes = {}
		if norm then
			local function randVec() return norm end
			split_entity({randVec, randPos}, self.TRIANGLES, convexes, 1)
		else
			local function randVec() return VectorRand():GetNormalized() end
			split_entity({randVec, randPos}, self.TRIANGLES, convexes, 5)
		end
        local pos = self:GetPos()
        local ang = self:GetAngles()
        local model = self:GetPhysModel()
        local material = self:GetMaterial()
        local color = self:GetColor()
        local rendermode = self:GetRenderMode()
        local vel = self:GetVelocity()
        local phys_scale = self:GetPhysScale()
        local original_shard = self:GetOriginalShard():IsValid() and self:GetOriginalShard() or self
        local lastblock
        local valid_entity = {false}      // table cuz i want pointers
        for k, physmesh in ipairs(convexes) do 
            local block = ents.Create("procedural_shard")
            block:SetPos(pos)
            block:SetAngles(ang)
            block:SetPhysModel(model)
            block:SetPhysScale(Vector(1, 1, 1))
            block:SetOriginalShard(original_shard)
            block:Spawn()
            block:SetReferenceShard(self)
            block:SetMaterial(material)
            block:SetColor(color)
            block:SetRenderMode(rendermode)
            block:BuildCollision(physmesh[1], valid_entity)   // first thing in table is the triangles
            block.IS_FUNNY_GLASS = self.IS_FUNNY_GLASS
            local phys = block:GetPhysicsObject()
            if phys:IsValid() then
                phys:SetVelocity(vel)
            end
            
            // prop protection support
            if CPPI then
                local owner = self:CPPIGetOwner()
                if owner and owner:IsValid() then
                    block:CPPISetOwner(owner)
                end
            end

            if k == 1 then block:EmitSound("Glass.Break") end

            block.PLANES = physmesh[2]         // second thing in table is the planes, in format local_pos, normal, local_pos, normal, etc
            if block.COMBINED_PLANES then
                table.Add(block.COMBINED_PLANES, physmesh[2])
            else
                block.COMBINED_PLANES = physmesh[2]
            end

            // weld it to other shards
            if lastblock then
                constraint.Weld(block, lastblock, 0, 0, 3000, true)
            end
            lastblock = block
        end

        // all shards have been removed because they are too small, remove the original
        if !valid_entity[1] then SafeRemoveEntity(self) return end

        constraint.RemoveAll(self)
        self:GetPhysicsObject():EnableMotion(false)
        self:SetNotSolid(true)
        self:ForcePlayerDrop()
        self.CAN_BREAK = false

        // this shard is now invalid, decriment the original shards count
        local orig_shard = self:GetOriginalShard()
        if orig_shard and orig_shard:IsValid() then 
            orig_shard.SHARD_COUNT = orig_shard.SHARD_COUNT - 1
        end

        // in case clientside receives sharded entity before this entity
        // give clients 5 seconds to try and find shard
        timer.Simple(5, function()
            if !self:IsValid() then return end
            self:SetPos(Vector())
            self:SetAngles(Angle())
            self:SetNoDraw(true)
        end)
        
    end

    function ENT:OnTakeDamage(damage)
        if !self.CAN_BREAK then return end
        local damagepos = damage:GetDamagePosition()
        if damagepos != Vector() then // some physents are broken and have no damage position, so just set the damage to the center of the object
            damagepos = self:WorldToLocal(damagepos)
        else
            damagepos = Vector()
        end
        self:Split(damagepos, damage:GetDamageType() == DMG_BLAST)
        self.CAN_BREAK = false
    end

    function ENT:PhysicsCollide(data)
    	if self:IsPlayerHolding() then return end	--unbreakable if held
        local speed_limit = self.IS_FUNNY_GLASS and -1 or 300
    	if data.Speed > speed_limit and self.CAN_BREAK then
            local ho = data.HitObject
            if ho and ho:IsValid() and ho.GetClass and ho:GetClass() == "procedural_shard" and ho.CAN_BREAK then return end

            // just some values that I thought looked nice
            local limit = 0.25
            if ho.GetClass and ho:GetClass() == "procedural_shard" then limit = -0.25 end   // less lag
            if self.IS_FUNNY_GLASS then limit = 2 end  // impossible to not break

            // if the glass is directly struck straightways, dont break since this can cause break loops
            local dot = data.OurNewVelocity:GetNormalized():Dot(data.OurOldVelocity:GetNormalized())
            if dot > limit then return end
           
            self.CAN_BREAK = false
            local pos = data.HitPos
            timer.Simple(0, function() // NEVER change collision rules in physics feedback
                if !self or !self:IsValid() then return end
                self:Split(self:WorldToLocal(pos))
            end)
    	end
	end	

    function ENT:OnRemove()
        local orig_shard = self:GetOriginalShard()
        if orig_shard and orig_shard:IsValid() then 
            orig_shard.SHARD_COUNT = orig_shard.SHARD_COUNT - 1
            if orig_shard.SHARD_COUNT < 1 then
                SafeRemoveEntity(orig_shard)
            end
        else    // must be original shard, remove parent shards
            for k, v in ipairs(ents.FindByClass("procedural_shard")) do
                if v.GetOriginalShard and v:GetOriginalShard() == self then
                    SafeRemoveEntity(v)
                end
            end
        end
    end
end

function ENT:OnDuplicated()
    self:BuildCollision(util.GetModelMeshes(self:GetPhysModel())[1].triangles)
end


local default_mat = Material("models/props_combine/health_charger_glass")
function ENT:Initialize(first)
    //self:SetModel("models/Combine_Helicopter/helicopter_bomb01.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:PhysWake()
    self:DrawShadow(false)

    if SERVER then 
        self.CAN_BREAK = false
        // if valid to completely remove
        local orig_shard = self:GetOriginalShard()
        if orig_shard and orig_shard:IsValid() then
            orig_shard.SHARD_COUNT = orig_shard.SHARD_COUNT + 1
        else
            self.SHARD_COUNT = 0    // it is the original shard
        end

        // remove fast & laggy interactions
        timer.Simple(0.25, function()
            if !self then return end
            self.CAN_BREAK = true
        end)

        return 
    end

    self.RENDER_MESH = {Mesh = Mesh(), Material = default_mat}
    
    if first then return end

    // tell server to start sending shard data
    net.Start("SHARD_NETWORK")
    net.WriteEntity(self)
    net.SendToServer()
end

// make sure clients can always see entity, reguardless if not in view
function ENT:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end

if CLIENT then 
    language.Add("procedural_shard", "Glass Shard")
    return 
end

// glass func_breakable_surf replacement
local function replaceGlass()
    for _, glass in ipairs(ents.FindByClass("func_breakable_surf")) do
        // func breakable surf is kinda cursed, its origin and angle are always 0,0,0
        // so we need to find out what they are

        // angle can be found by going through 3 of the 4 points defined on a surf entity and finding the angle by constructing a triangle
        local verts = glass:GetBrushSurfaces()[1]:GetVertices()
        local glass_angle = (verts[1] - verts[2]):Cross(verts[1] - verts[3]):Angle()

        // position can be found by getting the middle of the bounding box in the object
        local offset = (glass:OBBMaxs() + glass:OBBMins()) * 0.5

        // weird rotate issue fix
        local rotate_angle = glass_angle
        if glass_angle[1] >= 45 and glass_angle[2] >= 180 then
            rotate_angle = -rotate_angle
        end

        // our bounding box needs to be rotated to match the angle of the glass, the rotation is currently in local space, we need to convert to world
        verts[1] = verts[1] - offset
        verts[3] = verts[3] - offset
        verts[1]:Rotate(-rotate_angle)
        verts[3]:Rotate(-rotate_angle)

        // now we have the actual size of the glass, take the 2 points and subtract to find the size, then divide by 2
        local size = (verts[1] - verts[3]) * 0.5

        // create the shard
        local block = ents.Create("procedural_shard")
        block:SetPhysModel("models/hunter/blocks/cube025x025x025.mdl")
        block:SetPhysScale(Vector(1, size[2], size[3]) / 5.90625)  // 5.90625 is the size of the block model
        block:SetPos(offset)
        block:SetAngles(glass_angle)
        block:SetMaterial(glass:GetMaterials()[1])
        block:Spawn()
    
        block:BuildCollision(util.GetModelMeshes("models/hunter/blocks/cube025x025x025.mdl")[1].triangles)
        if block:GetPhysicsObject():IsValid() then block:GetPhysicsObject():EnableMotion(false) end

        // remove original func_ entity
        SafeRemoveEntity(glass)
    end
end

hook.Add("InitPostEntity", "glass_init", replaceGlass)
hook.Add("PostCleanupMap", "glass_init", replaceGlass)
