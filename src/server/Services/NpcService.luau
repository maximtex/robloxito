-- NPCs desactivados a petición del usuario: limpia cualquier carpeta previa de NPCs
-- y deja el registro vacío para mantener compatibilidad con AdventureService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AdventureService = require(script.Parent.AdventureService)

local FOLDER_NAME = "Npcs"
local WORLD_NAME = "AdventureWorld"

local NpcService = {}

function NpcService.start()
	for _, child in Workspace:GetChildren() do
		if child.Name == FOLDER_NAME then
			child:Destroy()
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace

	local existing = ReplicatedStorage:FindFirstChild(WORLD_NAME)
	if existing then
		existing:Destroy()
	end
	local worldInfo = Instance.new("Folder")
	worldInfo.Name = WORLD_NAME
	worldInfo.Parent = ReplicatedStorage

	AdventureService.setWorld({
		npcPosition = function(_npcId: string): Vector3?
			return nil
		end,
		itemPosition = function(_itemId: string): Vector3?
			return nil
		end,
	})
end

return NpcService
