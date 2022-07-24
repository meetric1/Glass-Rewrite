AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"

ENT.Category		= "World"
ENT.PrintName		= "Shard"
ENT.Author			= "Mee"
ENT.Purpose			= ""
ENT.Instructions	= ""
ENT.Spawnable		= true

local generateUV, generateNormals, simplify_vertices, split_convex, split_entity = include("world_functions.lua")

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "PhysModel")
    self:NetworkVar("Entity", 0, "ReferenceShard")
    self:NetworkVar("Entity", 1, "OriginalShard")
end

function ENT:BuildCollision(verts)
    //self.TRIANGLES = verts
    self:PhysicsDestroy()
    self:EnableCustomCollisions()
    local new_verts, offset = simplify_vertices(verts)
	self:PhysicsInitConvex(new_verts)

    // physics object isnt valid, remove cuz its probably weird
    if SERVER then
        local phys = self:GetPhysicsObject()
        if !phys:IsValid() then
            self:Remove()
            return
        else
            local bounding = self:BoundingRadius()
            if bounding < 40 then
                self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
                if bounding < 10 then 
                    // glass effect
                    local data = EffectData() data:SetOrigin(self:GetPos())
                    util.Effect("GlassImpact", data)
                    SafeRemoveEntity(self) 
                end
            end
            phys:SetMass(bounding)
            phys:SetMaterial("glass")
            phys:SetPos(self:LocalToWorld(offset))
            self.TRIANGLES = phys:GetMesh()
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
        if !physobj:IsValid() or self:GetPos() == physobj:GetPos() then 
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
        if self.RENDER_MESH then
            self.RENDER_MESH.Mesh:Destroy()
        end
    end
else
    function ENT:Split(pos, radius)
        local convexes = {}
        //local function randVec() return Vector(math.Rand(-1, 1), math.Rand(-1, 1), math.Rand(-1, 1)):GetNormalized() end
        local function randVec() return VectorRand():GetNormalized() end
        local function randPos() return pos + VectorRand():GetNormalized() * radius end
        split_entity({randVec, randPos}, self.TRIANGLES, convexes, 5)
        local pos = self:GetPos()
        local ang = self:GetAngles()
        local model = self:GetPhysModel()
        local material = self:GetMaterial()
        local color = self:GetColor()
        local rendermode = self:GetRenderMode()
        local vel = self:GetVelocity()
        local lastblock
        for k, physmesh in ipairs(convexes) do 
            local block = ents.Create("procedural_shard")
            block:SetPos(pos)
            block:SetAngles(ang)
            block:SetPhysModel(model)
            block:Spawn()
            block:BuildCollision(physmesh[1])   // first thing in table is the triangles
            block:SetReferenceShard(self)
            block:SetOriginalShard(self:GetOriginalShard():IsValid() and self:GetOriginalShard() or self)
            block:SetMaterial(material)
            block:SetColor(color)
            block:SetRenderMode(rendermode)
            local phys = block:GetPhysicsObject()
            if phys:IsValid() then
                phys:SetVelocity(vel)
            end

            block.PLANES = physmesh[2]         // second thing in table is the planes, in format local_pos, normal, local_pos, normal, etc

            // weld it to other shards
            if lastblock then
                constraint.Weld(block, lastblock, 0, 0, 3000, true)
            end
            lastblock = block
        end

        constraint.RemoveAll(self)
        self:GetPhysicsObject():EnableMotion(false)
        self:SetNotSolid(true)
        self:ForcePlayerDrop()

        // for constraints to update
        timer.Simple(0, function()
            self:SetPos(Vector())
            self:SetAngles(Angle())
            self:SetNoDraw(true)
        end)
        
    end

    function ENT:SpawnFunction(ply, tr, class)
        local block = ents.Create("procedural_shard")
        block:SetPos(tr.HitPos + tr.HitNormal * 100)
        block:SetPhysModel("models/hunter/blocks/cube2x2x2.mdl")
        block:Spawn()
        block:BuildCollision(util.GetModelMeshes(block:GetPhysModel())[1].triangles)
        return block
    end

    function ENT:OnTakeDamage(damage)
        if !self.CAN_BREAK then return end
        self:Split(self:WorldToLocal(damage:GetDamagePosition()), 0)
    end

    function ENT:PhysicsCollide(data)
    	if self:IsPlayerHolding() then return end	--unbreakable if held

    	if data.Speed > 300 and self.CAN_BREAK then
            local ho = data.HitObject
            if ho and ho:IsValid() and ho.GetClass and ho:GetClass() == "procedural_shard" and ho.CAN_BREAK then return end
            local limit = 0.25
            if ho.GetClass and ho:GetClass() == "procedural_shard" then limit = -0.25 end
            local dot = data.OurNewVelocity:GetNormalized():Dot(data.OurOldVelocity:GetNormalized())
            if dot > limit then return end
           
            self.CAN_BREAK = false
            local pos = data.HitPos
            timer.Simple(0, function() // NEVER change collision rules in physics feedback
                if !self or !self:IsValid() then return end
                self:Split(self:WorldToLocal(pos), 0)
            end)
    	end
	end	

    function ENT:OnRemove() 
        for k, v in ipairs(ents.GetAll()) do
            if v.GetOriginalShard and v:GetOriginalShard() == self then
                SafeRemoveEntity(v)
            end
        end
    end
end

function ENT:OnDuplicated()
    self:BuildCollision(util.GetModelMeshes(self:GetPhysModel())[1].triangles)
end

function ENT:Initialize()
    //self:SetModel("models/Combine_Helicopter/helicopter_bomb01.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:PhysWake()
    self:DrawShadow(false)
    self:SetCustomCollisionCheck(true)
    self.CAN_BREAK = false
    // remove fast & laggy interactions
    timer.Simple(0.1, function()
        if !self then return end
        self.CAN_BREAK = true
    end)

    if SERVER then return end

    self.RENDER_MESH = {Mesh = Mesh(), Material = Material("hunter/myplastic")}

    // tell server to start sending shard data
    net.Start("SHARD_NETWORK")
    net.WriteEntity(self)
    net.SendToServer()
end

// make sure clients can always see entity, reguardless if not in view
function ENT:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end



// networking
if SERVER then
    util.AddNetworkString("SHARD_NETWORK")

    // must be from client requesting data, send back shard data
    net.Receive("SHARD_NETWORK", function(len, ply)
        local shard = net.ReadEntity()
        if !shard:IsValid() then return end
        
        net.Start("SHARD_NETWORK")
        net.WriteUInt(shard:EntIndex(), 16)
        if shard.PLANES then
            for i = 1, #shard.PLANES, 2 do
                local plane_pos = shard.PLANES[i]
                local plane_dir = shard.PLANES[i + 1]
                net.WriteFloat(plane_pos[1])
                net.WriteFloat(plane_pos[2])
                net.WriteFloat(plane_pos[3])
                
                // plane dir indexes will never go over 1
                net.WriteFloat(plane_dir[1])
                net.WriteFloat(plane_dir[2])
                net.WriteFloat(plane_dir[3])
            end
        end
        net.Send(ply)
    end)

else
    net.Receive("SHARD_NETWORK", function(len)
        local shard = net.ReadUInt(16)
        local plane_data_len = (len - 16) / ((32 * 3) + (32 * 3))
        local plane_data = {}
        for i = 0, plane_data_len - 1 do
            // plane local pos
            local pos_x = net.ReadFloat()
            local pos_y = net.ReadFloat()
            local pos_z = net.ReadFloat()

            // plane normal
            local dir_x = net.ReadFloat()
            local dir_y = net.ReadFloat()
            local dir_z = net.ReadFloat()

            // insert plane data into table
            plane_data[i * 2 + 1] = Vector(pos_x, pos_y, pos_z)
            plane_data[i * 2 + 2] = Vector(dir_x, dir_y, dir_z)
        end

        // try and find shard on client within 10 seconds
        timer.Create("try_shard" .. shard, 0, 1000, function()
            local shard_entity = Entity(shard)
            if !shard_entity:IsValid() or !shard_entity.GetReferenceShard then return end

            // get model information
            local model_triangles
            if shard_entity:GetReferenceShard():IsValid() then
                model_triangles = shard_entity:GetReferenceShard().TRIANGLES
            else
                local model = util.GetModelMeshes(shard_entity:GetPhysModel())
                if !model then model = util.GetModelMeshes("models/error.mdl") end
                model_triangles = model[1].triangles
            end

            // slice mesh up using networked planes
            for i = 1, #plane_data, 2 do
                model_triangles = split_convex(model_triangles, plane_data[i], plane_data[i + 1])
            end
            if #plane_data > 0 then
                // assemble visual mesh
                for k, v in ipairs(model_triangles) do
                    model_triangles[k] = {pos = v}
                end
            end

            // create render mesh and build physics mesh
            //shard_entity.TRIANGLES = model_triangles
            shard_entity:BuildCollision(model_triangles)
            if shard_entity:GetPhysicsObject():IsValid() then
                shard_entity.TRIANGLES = shard_entity:GetPhysicsObject():GetMesh()
            else
                shard_entity.TRIANGLES = model_triangles
            end

            // generate missing normals and uvs
            generateUV(shard_entity.TRIANGLES, -1/50)
            generateNormals(shard_entity.TRIANGLES)

            shard_entity.RENDER_MESH.Mesh:BuildFromTriangles(shard_entity.TRIANGLES)

            timer.Remove("try_shard" .. shard)
        end)
    end)
end
