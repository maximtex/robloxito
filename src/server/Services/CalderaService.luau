-- Construye la Caldera de Brasas (Zona 3) pegada directamente tras el Valle Morado
-- (sin puente intermedio), con el mismo estilo de bloques que el Bosque (StudWorld):
-- - Suelo en damero volcánico naranja / terracota con los cuadritos del diseño, caminos de
--   ceniza con borde (StudFloor.Zones.EmberCaldera). Empieza donde acaba el muro sur del Valle.
-- - Muros perimetrales de damero volcánico con remate naranja (fin del corredor: sin paso).
-- - Lago de lava (CalderaConfig.LavaLake), árboles de brasas junto a los muros, formaciones de
--   obsidiana con vetas de lava, pozas de lava y piedras de brasa por el damero.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CalderaConfig = require(Shared.Config.CalderaConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local StudFloor = require(Shared.Util.StudFloor)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local StudWorld = require(script.Parent.Parent.Util.StudWorld)

local CalderaService = {}

local CENTER_2D = ZoneConfig.Zones.EmberCaldera.Center
local ORIGIN = Vector3.new(GeneratorConfig.Position.X + CENTER_2D.X, 0, GeneratorConfig.Position.Z + CENTER_2D.Y)
local CALDERA = StudFloor.Zones.EmberCaldera
local COLORS = CalderaConfig.Colors

-- Árboles de brasas: tronco carbonizado y copa naranja
local EMBER_TREE_COLORS = {
	Trunk = Color3.fromRGB(74, 52, 46),
	LeafLight = Color3.fromRGB(240, 128, 40),
	LeafDark = Color3.fromRGB(214, 84, 32),
}

local function world(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

-- Basalto por debajo del suelo, desde el muro sur del Valle hasta el fondo de la Caldera
local function buildFlatTerrain()
	local half = CalderaConfig.Terrain.Size / 2
	StudWorld.fillTerrainBelow(-half, half, CALDERA.MinZ, ORIGIN.Z + half, Enum.Material.Basalt)
end

-- Charco de lava cuadrado sobre el suelo con su borde de basalto (como el de los caminos)
local function buildLavaPool(parent: Instance, name: string, center: Vector3, size: number)
	local border = StudFloor.BorderWidth
	local top = StudWorld.FloorTop
	local m = Instance.new("Model")
	m.Name = name
	PartFactory.part(m, "Lava", {
		Size = Vector3.new(size - 2 * border, 0.2, size - 2 * border),
		CFrame = CFrame.new(center.X, top - 0.04, center.Z),
		Color = COLORS.Lava,
		Material = Enum.Material.Neon,
		Solid = false,
	})
	for _, side in { -1, 1 } do
		PartFactory.part(m, "Borde", {
			Size = Vector3.new(size, 0.2, border),
			CFrame = CFrame.new(center.X, top - 0.04, center.Z + side * (size - border) / 2),
			Color = CALDERA.Colors.Border,
			Material = Enum.Material.Plastic,
			Solid = false,
		})
		PartFactory.part(m, "Borde", {
			Size = Vector3.new(border, 0.2, size - 2 * border),
			CFrame = CFrame.new(center.X + side * (size - border) / 2, top - 0.04, center.Z),
			Color = CALDERA.Colors.Border,
			Material = Enum.Material.Plastic,
			Solid = false,
		})
	end
	m.Parent = parent
	return m
end

-- Lago de lava grande con rocas de basalto con studs alrededor
local function buildLavaLake(parent: Instance)
	local lake = CalderaConfig.LavaLake
	local center = world(lake.Center.X, 0, lake.Center.Y)
	local size = lake.Radius * 2 + 4
	local m = buildLavaPool(parent, "LavaLake", center, size)
	for index, spec in {
		{ X = -1, Z = -1, H = 4.5 },
		{ X = 1, Z = -1, H = 3 },
		{ X = -1, Z = 1, H = 2.5 },
		{ X = 1, Z = 1, H = 5 },
	} do
		local pos = center + Vector3.new(spec.X * (size / 2 + 1), 0, spec.Z * (size / 2 + 1))
		StudWorld.allStuds(PartFactory.part(m, "Roca" .. index, {
			Size = Vector3.new(5, spec.H, 5),
			CFrame = CFrame.new(pos.X, StudWorld.FloorTop + spec.H / 2, pos.Z) * CFrame.Angles(0, math.rad(index * 23), 0),
			Color = COLORS.Rock,
			Material = Enum.Material.Plastic,
			Solid = true,
		}))
	end
end

-- Formación de obsidiana: tres bloques oscuros inclinados con una veta de lava
local function buildObsidian(parent: Instance, pos: Vector3, yawDeg: number, scale: number)
	local m = Instance.new("Model")
	m.Name = "ObsidianCluster"
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	for index, spec in {
		{ Offset = Vector3.new(0, 3.2, 0), Size = Vector3.new(2.6, 6.4, 2.6), Tilt = CFrame.Angles(math.rad(6), 0, math.rad(-7)) },
		{ Offset = Vector3.new(-1.9, 2.0, 1.0), Size = Vector3.new(1.9, 4.0, 1.9), Tilt = CFrame.Angles(math.rad(-12), 0, math.rad(20)) },
		{ Offset = Vector3.new(1.8, 2.2, -0.9), Size = Vector3.new(2.0, 4.4, 2.0), Tilt = CFrame.Angles(math.rad(14), 0, math.rad(-18)) },
	} do
		PartFactory.part(m, "Obsidiana" .. index, {
			Size = spec.Size * scale,
			CFrame = cf * CFrame.new(spec.Offset * scale) * spec.Tilt * CFrame.Angles(0, math.rad(45), 0),
			Color = COLORS.Obsidian[index],
			Material = Enum.Material.SmoothPlastic,
			Solid = index == 1,
		})
	end
	PartFactory.part(m, "Veta", {
		Size = Vector3.new(0.5, 5.2, 0.5) * scale,
		CFrame = cf * CFrame.new(Vector3.new(0.9, 3.0, -0.9) * scale) * CFrame.Angles(math.rad(6), 0, math.rad(-7)),
		Color = COLORS.LavaBright,
		Material = Enum.Material.Neon,
		Solid = false,
	})
	m.Parent = parent
end

-- Piedra de brasa: bloque de basalto con studs y un brillo de lava encima
local function buildEmberRock(parent: Instance, pos: Vector3, yawDeg: number)
	local m = Instance.new("Model")
	m.Name = "EmberRock"
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	StudWorld.allStuds(PartFactory.part(m, "Roca", {
		Size = Vector3.new(2.6, 1.4, 2.2),
		CFrame = cf * CFrame.new(0, 0.7, 0),
		Color = COLORS.Rock,
		Material = Enum.Material.Plastic,
		Solid = false,
	}))
	PartFactory.part(m, "Brasa", {
		Size = Vector3.new(1.2, 0.5, 1.0),
		CFrame = cf * CFrame.new(0.3, 1.5, 0.1),
		Color = COLORS.LavaBright,
		Material = Enum.Material.Neon,
		Solid = false,
	})
	m.Parent = parent
end

-- Árboles de brasas junto a los muros, el lago de lava, obsidiana, pozas y brasas
local function buildDecor(parent: Instance)
	local folder = PartFactory.folder(parent, "MapDetails")
	local lake = CalderaConfig.LavaLake
	local lakeCenter = world(lake.Center.X, 0, lake.Center.Y)
	local decor = StudWorld.newDecor(CALDERA, "EmberCaldera", {
		{ lakeCenter.X, lakeCenter.Z, lake.Radius + 8 },
	})
	local rng = decor.Rng

	buildLavaLake(folder)
	decor.wallRow(22, 9, 12, function(pos, yaw)
		StudWorld.buildBlockyTree(folder, pos, yaw, rng:NextNumber(0.95, 1.2), EMBER_TREE_COLORS)
	end)
	decor.scatter(14, 4, math.huge, 10, function(pos, yaw)
		buildObsidian(folder, pos, yaw, rng:NextNumber(0.8, 1.3))
	end)
	decor.scatter(6, 6, math.huge, 10, function(pos)
		buildLavaPool(folder, "LavaPool", pos, 10)
	end)
	decor.scatter(28, 2, math.huge, 4, function(pos, yaw)
		buildEmberRock(folder, pos, yaw)
	end)
end

function CalderaService.start()
	PartFactory.removeExisting(workspace, CalderaConfig.ModelName)
	buildFlatTerrain()

	local model = Instance.new("Model")
	model.Name = CalderaConfig.ModelName
	StudWorld.buildFloor(model, CALDERA)
	StudWorld.buildWalls(model, CALDERA)
	buildDecor(model)
	model.Parent = workspace
end

return CalderaService
