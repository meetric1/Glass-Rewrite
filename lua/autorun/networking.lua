AddCSLuaFile()

local generateUV, generateNormals, simplify_vertices, split_convex, split_entity = include("world_functions.lua")

// networking
if SERVER then
    util.AddNetworkString("SHARD_NETWORK")

    // must be from client requesting data, send back shard data
    net.Receive("SHARD_NETWORK", function(len, ply)
		// client requests some shard data
        if len > 1 then
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
        else
			// client requests all shard data
			local ply_index = ply:EntIndex()
            local shards = ents.FindByClass("procedural_shard")
			if #shards < 1 then return end
			timer.Create("shards" .. ply_index, 0.05, #shards, function()
				local shard = shards[1]
				table.remove(shards, 1)
				if !shard:IsValid() then return end
				
				net.Start("SHARD_NETWORK")
				net.WriteUInt(shard:EntIndex(), 16)
				if shard.COMBINED_PLANES then
					for i = 1, #shard.COMBINED_PLANES, 2 do
						local plane_pos = shard.COMBINED_PLANES[i]
						local plane_dir = shard.COMBINED_PLANES[i + 1]
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
    	end
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
            if !shard_entity:IsValid() or !shard_entity.GetReferenceShard or !shard_entity.BuildCollision then return end

            // get model information
            local reference_shard = shard_entity:GetReferenceShard()    // the shard that was broken to create the current shard
            local model_triangles
            if reference_shard:IsValid() then
                model_triangles = reference_shard.TRIANGLES
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

            // destroy possibly corrupt memory!??!
            // not desroying this caused a vertex lock crash... wtf source?
			if shard_entity.RENDER_MESH.Mesh:IsValid() then
				shard_entity.RENDER_MESH.Mesh:Destroy()
				shard_entity.RENDER_MESH.Mesh = Mesh()
			else
				shard_entity.RENDER_MESH.Mesh = Mesh()
			end
            shard_entity.RENDER_MESH.Mesh:BuildFromTriangles(shard_entity.TRIANGLES)

            if reference_shard:IsValid() then
                reference_shard:SetNoDraw(true)
            end

            timer.Remove("try_shard" .. shard)
        end)
    end)
end	

if SERVER then return end

// client initialize
hook.Add("InitPostEntity", "glass_init", function()
	timer.Simple(1, function()	// let SENT functions initialize, unsure why they arent in this hook.
		for k, v in ipairs(ents.FindByClass("procedural_shard")) do
			v:Initialize(true)
		end

		// tell server to send ALL shard data
		net.Start("SHARD_NETWORK")
		net.SendToServer()
	end)
end)
