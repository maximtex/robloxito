-- Conserva cualquier carpeta `Npcs` existente en Studio y registra sus posiciones para AdventureService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AdventureService = require(script.Parent.AdventureService)

local FOLDER_NAME = "Npcs"
local WORLD_NAME = "AdventureWorld"

local NpcService = {}

function NpcService.start()
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = Workspace
	end

	local existing = ReplicatedStorage:FindFirstChild(WORLD_NAME)
	if existing then
		existing:Destroy()
	end
	local worldInfo = Instance.new("Folder")
	worldInfo.Name = WORLD_NAME
	worldInfo.Parent = ReplicatedStorage

	AdventureService.setWorld({
		npcPosition = function(npcId: string): Vector3?
			local model = folder:FindFirstChild(npcId)
			if model and model:IsA("Model") then
				return model:GetPivot().Position
			end
			return nil
		end,
		itemPosition = function(_itemId: string): Vector3?
			return nil
		end,
	})
end

return NpcService
