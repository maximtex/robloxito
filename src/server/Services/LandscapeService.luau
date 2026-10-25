-- En el mapa estilo simulador simple, LandscapeService solo construye los muros invisibles
-- de límite (MapBoundary) de cada zona para que nadie caiga fuera del mapa, sin árboles,
-- colinas, rocas ni estanques que recarguen la vista (LandscapeConfig.BuildsDecor = false).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LandscapeConfig = require(Shared.Config.LandscapeConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local StudFloor = require(Shared.Util.StudFloor)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local LandscapeLayout = require(script.Parent.Parent.Util.LandscapeLayout)

local GROUND = GeneratorConfig.Position.Y

local LandscapeService = {}

type Zone = { Origin: Vector3, Parent: Instance }

local function zoneOrigin(zoneId: string): Vector3
	local center = ZoneConfig.Zones[zoneId].Center
	return Vector3.new(GeneratorConfig.Position.X + center.X, 0, GeneratorConfig.Position.Z + center.Y)
end

local function at(zone: Zone, x: number, y: number, z: number): Vector3
	return zone.Origin + Vector3.new(x, y, z)
end

-- El anillo cruza el paso del muro de cada puerta de energía: ahí no se ponen sus segmentos
-- (los que quedan a menos de esto de la puerta) para poder pasar al desbloquear la zona. El
-- paso lo cierra la barrera de la puerta (ZoneService) mientras siga bloqueada.
local GATE_CLEARANCE = 30

local function nearPortal(position: Vector3): boolean
	for _, portal in ZoneConfig.Portals do
		local gate = zoneOrigin(portal.Zone) + Vector3.new(portal.Offset.X, 0, portal.Offset.Y)
		if (position - gate).Magnitude < GATE_CLEARANCE then
			return true
		end
	end
	return false
end

local function buildBoundary(zone: Zone, walls: { any })
	local folder = PartFactory.folder(zone.Parent, "MapBoundary")
	for index, wall in walls do
		local center = at(zone, wall.X, 0, wall.Z)
		-- Ni en el paso de una puerta ni dentro de la cueva del Bosque (sus paredes ya cierran)
		if nearPortal(center) or StudFloor.inCave(center.X, center.Z, wall.Width / 2 + 4) then
			continue
		end
		local part = Instance.new("Part")
		part.Name = "Wall" .. index
		part.Anchored = true
		part.CanCollide = true
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = Vector3.new(wall.Width, wall.Height, wall.Thickness)
		part.CFrame = CFrame.new(at(zone, wall.X, GROUND + wall.Height / 2 - 6, wall.Z)) * CFrame.Angles(0, wall.Yaw, 0)
		part.Parent = folder
	end
end

local function buildZone(root: Instance, key: string)
	local settings = LandscapeConfig[key]
	local model = Instance.new("Model")
	model.Name = key
	model.Parent = root
	local zone: Zone = { Origin = zoneOrigin(settings.Zone), Parent = model }
	local layout = LandscapeLayout.compute(key)
	buildBoundary(zone, layout.Boundary)
end

function LandscapeService.start()
	PartFactory.removeExisting(Workspace, LandscapeConfig.ModelName)
	local root = Instance.new("Model")
	root.Name = LandscapeConfig.ModelName
	root.Parent = Workspace
	for _, key in { "Forest", "Valley", "Caldera" } do
		local ok, err = pcall(buildZone, root, key)
		if not ok then
			warn("[LandscapeService] " .. key .. ": " .. tostring(err))
		end
	end
end

return LandscapeService
