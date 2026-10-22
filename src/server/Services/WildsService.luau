-- En el modo de mapa plano y simple, no se excavan ríos, cascadas ni ruinas para mantener
-- el piso cuadriculado limpio. Conserva isBuilt() para que ChestService coloque los cofres
-- a nivel del suelo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WildsConfig = require(Shared.Config.WildsConfig)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)

local WildsService = {}

local built = false

function WildsService.isBuilt(): boolean
	return built
end

function WildsService.start()
	PartFactory.removeExisting(Workspace, WildsConfig.ModelName)
	local root = Instance.new("Model")
	root.Name = WildsConfig.ModelName
	root.Parent = Workspace
	built = true
end

return WildsService
