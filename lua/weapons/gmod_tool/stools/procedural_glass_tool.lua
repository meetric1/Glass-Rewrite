TOOL.Category = "Glass Rewrite"
TOOL.Name = "#Tool.procedural_glass_tool.name"

if CLIENT then
	language.Add("Tool.procedural_glass_tool.name", "Glass tool")
	language.Add("Tool.procedural_glass_tool.desc", "Turn props into glass (will giftwrap mesh)")
	
	TOOL.Information = {{name = "left"}}

	language.Add("Tool.procedural_glass_tool.left", "Left click on a prop to turn it into destructable glass")

	function TOOL.BuildCPanel(panel)
		panel:AddControl("label", {
			text = "Turns props into glass upon left click",
		})
	end
end

function TOOL:LeftClick(tr)
	local ent = tr.Entity
	local owner = self:GetOwner()

	if CPPI and ent.CPPICanTool and !ent:CPPICanTool(owner, "remover") then return end

	if ent:GetClass() != "prop_physics" then return end
	if !ent:GetPhysicsObject():IsValid() then return end
	if IsUselessModel(ent:GetModel()) then owner:ChatPrint("Invalid Model") end

	if SERVER then
		local block = ents.Create("procedural_shard")
        block:SetPos(ent:GetPos())
        block:SetAngles(ent:GetAngles())
        block:SetPhysModel(ent:GetModel())
        block:Spawn()
        block:BuildCollision(util.GetModelMeshes(block:GetPhysModel())[1].triangles)

        local phys = block:GetPhysicsObject()
        if phys then 
			phys:EnableMotion(false) 
		else 
			owner:ChatPrint("Unable to generate physics object") 
		end

		undo.Create("Glass")
			undo.AddEntity(block)
			undo.SetPlayer(owner)
		undo.Finish()

		 // prop protection support
		if CPPI then
			local owner = ent:CPPIGetOwner()
			if owner and owner:IsValid() then
				block:CPPISetOwner(owner)
			end
		end

		// remove original entity because we just turned it to glass
		SafeRemoveEntity(ent)
	end

	return true
end

