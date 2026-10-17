-- Construye el Valle Cristalino, la segunda zona:
-- - Terrain: pradera, anillo de montañas, colinas, caminos de piedra y un estanque con
--   acantilado y cascada.
-- - Piezas ancladas: gran geoda, formaciones de cristal azules/violetas/turquesas,
--   árboles de follaje cristalino, ruinas, arco y flores de cristal.
-- Es solo decorativo. Una única luz (en la geoda); el resto brilla con neón.
-- Se reconstruye limpio en cada arranque (sin duplicados).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ValleyConfig = require(Shared.Config.ValleyConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)

local Colors = ValleyConfig.Colors
local TerrainConfig = ValleyConfig.Terrain
local Neon = Enum.Material.Neon

local ValleyService = {}

local CENTER_2D = ZoneConfig.Zones.CrystalValley.Center
local ORIGIN = Vector3.new(GeneratorConfig.Position.X + CENTER_2D.X, 0, GeneratorConfig.Position.Z + CENTER_2D.Y)
local GROUND = GeneratorConfig.Position.Y

local function world(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

local function material(name: string): Enum.Material
	return (Enum.Material :: any)[name]
end

-- Terreno ---------------------------------------------------------------------

local function buildTerrain()
	local terrain = workspace.Terrain
	for materialName, color in TerrainConfig.MaterialColors do
		terrain:SetMaterialColor(material(materialName), color)
	end

	local size = TerrainConfig.Size
	local thickness = TerrainConfig.Thickness
	terrain:FillBlock(CFrame.new(world(0, GROUND - thickness / 2, 0)), Vector3.new(size, thickness, size), material(TerrainConfig.Ground))

	for _, mountain in TerrainConfig.Mountains do
		local angle = math.rad(mountain.X)
		local distance, radius = mountain.Y, mountain.Z
		local center = world(math.cos(angle) * distance, GROUND - radius * 0.45, math.sin(angle) * distance)
		terrain:FillBall(center, radius, material(TerrainConfig.Mountain))
		-- Vetas de pizarra en la ladera interior
		terrain:FillBall(center - Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * 0.55 + Vector3.new(0, radius * 0.2, 0), radius * 0.35, material(TerrainConfig.Cliff))
	end
	for _, hill in TerrainConfig.Hills do
		terrain:FillBall(world(hill.X, GROUND - hill.Z * 0.6, hill.Y), hill.Z, material(TerrainConfig.Ground))
	end

	-- Caminos de piedra (se pinta la capa superficial, a la misma altura)
	local paintDepth = 4
	for _, path in TerrainConfig.Paths do
		local from = Vector3.new(path.From.X, 0, path.From.Y)
		local to = Vector3.new(path.To.X, 0, path.To.Y)
		local length = (to - from).Magnitude
		local middle = (from + to) / 2
		terrain:FillBlock(
			CFrame.lookAt(world(middle.X, GROUND - paintDepth / 2, middle.Z), world(to.X, GROUND - paintDepth / 2, to.Z)),
			Vector3.new(path.Width, paintDepth, length + path.Width),
			material(TerrainConfig.Path)
		)
	end

	-- Estanque: se excava y se rellena de agua un poco por debajo del suelo.
	local pond = ValleyConfig.Pond
	local pondCenter = world(pond.Center.X, 0, pond.Center.Y)
	terrain:FillCylinder(CFrame.new(pondCenter + Vector3.new(0, GROUND - 3, 0)), 7, pond.Radius, Enum.Material.Air)
	terrain:FillCylinder(CFrame.new(pondCenter + Vector3.new(0, GROUND - 3.6, 0)), 5, pond.Radius, Enum.Material.Water)
	-- Acantilado de pizarra detrás del estanque
	local cliff = pond.Cliff
	terrain:FillBlock(CFrame.new(world(cliff.Center.X, GROUND + cliff.Size.Y / 2 - 3, cliff.Center.Y)), cliff.Size, material(TerrainConfig.Cliff))
end

-- Cristales ---------------------------------------------------------------------

-- Prisma de cristal inclinado que nace del suelo.
local function crystal(parent: Instance, name: string, base: Vector3, height: number, width: number, tilt: Vector3, color: Color3, glow: boolean)
	local cframe = CFrame.new(base)
		* CFrame.Angles(tilt.X, tilt.Y, tilt.Z)
		* CFrame.new(0, height / 2 - 0.4, 0)
		* CFrame.Angles(0, math.rad(45), 0)
	local part = PartFactory.part(parent, name, {
		Size = Vector3.new(width, height, width),
		CFrame = cframe,
		Color = color,
		Material = if glow then Neon else Enum.Material.Glass,
		Solid = height > 4, -- los grandes se pueden tocar; los pequeños no estorban
	})
	if not glow then
		part.Transparency = 0.15
	end
	return part
end

local function buildCrystalCluster(parent: Instance, name: string, x: number, z: number, scale: number, random: Random)
	local model = Instance.new("Model")
	model.Name = name
	local count = random:NextInteger(3, 5)
	for index = 1, count do
		local color = Colors.Crystals[random:NextInteger(1, #Colors.Crystals)]
		local offset = if index == 1 then Vector3.zero else Vector3.new(random:NextNumber(-2, 2), 0, random:NextNumber(-2, 2)) * scale
		local height = (if index == 1 then random:NextNumber(5, 8) else random:NextNumber(2, 5)) * scale
		local tilt = Vector3.new(random:NextNumber(-0.35, 0.35), random:NextNumber(0, math.pi), random:NextNumber(-0.35, 0.35))
		crystal(model, "Crystal" .. index, world(x, GROUND, z) + offset, height, math.max(0.6, height * 0.22), tilt, color, index == 2)
	end
	model.Parent = parent
end

local function buildGeode(parent: Instance)
	local geode = ValleyConfig.Geode
	local model = Instance.new("Model")
	model.Name = "GreatGeode"
	local base = world(geode.Position.X, GROUND, geode.Position.Y)

	-- Roca madre partida, de la que brotan los cristales
	PartFactory.ellipsoid(model, "Rock", CFrame.new(base + Vector3.new(0, 2, 0)), Vector3.new(26, 10, 20), Color3.fromRGB(96, 92, 110), Enum.Material.Slate)
	local spires = {
		{ Angle = 0, Height = 1.0, Tilt = 0.05 },
		{ Angle = 50, Height = 0.75, Tilt = 0.3 },
		{ Angle = 110, Height = 0.6, Tilt = 0.4 },
		{ Angle = 170, Height = 0.8, Tilt = 0.3 },
		{ Angle = 230, Height = 0.55, Tilt = 0.45 },
		{ Angle = 300, Height = 0.7, Tilt = 0.35 },
	}
	for index, spire in spires do
		local radians = math.rad(spire.Angle)
		local offset = if index == 1 then Vector3.zero else Vector3.new(math.cos(radians), 0, math.sin(radians)) * 4.5
		local height = geode.Height * spire.Height
		local tilt = Vector3.new(math.sin(radians) * spire.Tilt, radians, -math.cos(radians) * spire.Tilt)
		crystal(model, "Spire" .. index, base + offset + Vector3.new(0, 3, 0), height, height * 0.2, tilt, Colors.Crystals[(index - 1) % #Colors.Crystals + 1], index == 1)
	end
	local light = Instance.new("PointLight")
	light.Color = Colors.Crystals[2]
	light.Range = 30
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = model:FindFirstChild("Spire1")

	model.Parent = parent
end

-- Árboles, ruinas y flores ---------------------------------------------------------

local function buildTree(parent: Instance, name: string, x: number, z: number, scale: number, random: Random)
	local model = Instance.new("Model")
	model.Name = name
	local base = world(x, GROUND - 0.5, z)
	local height = 10 * scale
	local lean = Vector3.new(random:NextNumber(-0.6, 0.6), 0, random:NextNumber(-0.6, 0.6)) * scale
	local top = base + Vector3.new(0, height, 0) + lean
	PartFactory.segment(model, "Trunk", base, top, 1.3 * scale, Colors.Trunk, Enum.Material.Wood)
	PartFactory.segment(model, "Branch", base + Vector3.new(0, height * 0.6, 0) + lean * 0.6, top + Vector3.new(2.5, -1, 1) * scale, 0.5 * scale, Colors.Trunk, Enum.Material.Wood)

	local leaves = Colors.Leaves[random:NextInteger(1, #Colors.Leaves)]
	for index, blob in { { Vector3.new(0, 1.2, 0), 7 }, { Vector3.new(2.2, 0, 1), 5 }, { Vector3.new(-2, 0.5, -1.2), 5.4 } } do
		local foliage = PartFactory.ball(model, "Leaves" .. index, top + blob[1] * scale, blob[2] * scale, leaves, Enum.Material.LeafyGrass, false)
		foliage.CastShadow = true
	end
	-- Pequeños cristales colgando de la copa
	for index = 1, 2 do
		local hang = top + Vector3.new(random:NextNumber(-2, 2), -2.2, random:NextNumber(-2, 2)) * scale
		PartFactory.part(model, "Hanging" .. index, {
			Size = Vector3.new(0.3, 0.9, 0.3) * scale,
			CFrame = CFrame.new(hang) * CFrame.Angles(0, math.rad(45), 0),
			Color = Colors.Crystals[index],
			Material = Neon,
			Solid = false,
		})
	end
	model.Parent = parent
end

local function buildColumn(parent: Instance, name: string, x: number, z: number, height: number, random: Random)
	local model = Instance.new("Model")
	model.Name = name
	if height > 0 then
		local base = world(x, GROUND, z)
		PartFactory.part(model, "Plinth", {
			Size = Vector3.new(2.8, 0.6, 2.8),
			CFrame = CFrame.new(base + Vector3.new(0, 0.3, 0)),
			Color = Colors.Ruin,
			Material = Enum.Material.Limestone,
		})
		PartFactory.verticalCylinder(model, "Shaft", base + Vector3.new(0, 0.6 + height / 2, 0), height, 2, Colors.Ruin, Enum.Material.Limestone, true)
		PartFactory.verticalCylinder(model, "Moss", base + Vector3.new(0, 0.6 + height + 0.1, 0), 0.25, 2.15, Colors.Moss, Enum.Material.LeafyGrass, false)
	else
		PartFactory.part(model, "Fallen", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(6, 2, 2),
			CFrame = CFrame.new(world(x, GROUND + 0.7, z)) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0),
			Color = Colors.Ruin,
			Material = Enum.Material.Limestone,
		})
	end
	model.Parent = parent
end

local function buildArch(parent: Instance)
	local arch = ValleyConfig.Arch
	local model = Instance.new("Model")
	model.Name = "ValleyArch"
	for index, side in { -1, 1 } do
		PartFactory.part(model, "Pillar" .. index, {
			Size = Vector3.new(1.8, arch.Height, 1.8),
			CFrame = CFrame.new(world(side * arch.Width / 2, GROUND + arch.Height / 2, arch.Z)),
			Color = Colors.Ruin,
			Material = Enum.Material.Limestone,
		})
		crystal(model, "PillarCrystal" .. index, world(side * (arch.Width / 2 + 1.2), GROUND, arch.Z), 3, 0.8, Vector3.new(0, 0, side * 0.3), Colors.Crystals[index + 1], false)
	end
	PartFactory.part(model, "Lintel", {
		Size = Vector3.new(arch.Width + 3, 1.5, 2.2),
		CFrame = CFrame.new(world(0, GROUND + arch.Height + 0.75, arch.Z)) * CFrame.Angles(0, 0, math.rad(-2)),
		Color = Colors.Ruin,
		Material = Enum.Material.Limestone,
	})
	PartFactory.part(model, "Rune", {
		Size = Vector3.new(3, 0.5, 0.1),
		CFrame = CFrame.new(world(0, GROUND + arch.Height + 0.75, arch.Z + 1.12)),
		Color = Colors.Crystals[3],
		Material = Neon,
		Solid = false,
	})
	model.Parent = parent
end

local function isClear(x: number, z: number): boolean
	for _, zone in ValleyConfig.KeepClear do
		if (Vector2.new(x, z) - Vector2.new(zone.X, zone.Y)).Magnitude < zone.Z then
			return false
		end
	end
	for _, path in TerrainConfig.Paths do
		-- Distancia del punto al segmento del camino
		local a, b, p = path.From, path.To, Vector2.new(x, z)
		local ab = b - a
		local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
		if (p - (a + ab * t)).Magnitude < path.Width / 2 + 1.5 then
			return false
		end
	end
	return true
end

local function buildFlowers(parent: Instance)
	local settings = ValleyConfig.Flowers
	local random = Random.new(settings.Seed)
	local folder = PartFactory.folder(parent, "CrystalFlowers")
	local placed, attempts = 0, 0
	while placed < settings.Clusters and attempts < settings.Clusters * 12 do
		attempts += 1
		local angle = random:NextNumber(0, math.pi * 2)
		local radius = random:NextNumber(settings.MinRadius, settings.MaxRadius)
		local x, z = math.cos(angle) * radius, math.sin(angle) * radius
		if isClear(x, z) then
			placed += 1
			local color = Colors.Crystals[random:NextInteger(1, #Colors.Crystals)]
			for index = 1, 3 do
				local position = world(x + random:NextNumber(-1, 1), GROUND + 0.35, z + random:NextNumber(-1, 1))
				PartFactory.part(folder, "Flower" .. placed .. "_" .. index, {
					Size = Vector3.new(0.35, 0.7, 0.35),
					CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(45), random:NextNumber(-0.3, 0.3)),
					Color = color,
					Material = if index == 1 then Neon else Enum.Material.Glass,
					Solid = false,
				})
			end
		end
	end
end

local function buildWaterfall(parent: Instance)
	local pond = ValleyConfig.Pond
	local cliff = pond.Cliff
	local model = Instance.new("Model")
	model.Name = "Waterfall"
	local frontZ = cliff.Center.Y - cliff.Size.Z / 2 - 0.3
	local topY = GROUND + cliff.Size.Y - 3
	local bottomY = GROUND - 1.2
	local water = PartFactory.part(model, "Fall", {
		Size = Vector3.new(7, topY - bottomY, 0.5),
		CFrame = CFrame.new(world(cliff.Center.X, (topY + bottomY) / 2, frontZ)),
		Color = Colors.Water,
		Material = Enum.Material.Glass,
		Solid = false,
	})
	water.Transparency = 0.35
	-- Espuma al caer: pocas partículas y solo en la base
	local foam = PartFactory.part(model, "Foam", {
		Size = Vector3.new(7, 0.2, 2),
		CFrame = CFrame.new(world(cliff.Center.X, bottomY + 0.3, frontZ - 1)),
		Color = Colors.Water,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	foam.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 12
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(1, 2.5)
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Size = NumberSequence.new(0.6, 1.6)
	emitter.Transparency = NumberSequence.new(0.5, 1)
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1))
	emitter.Parent = foam
	-- Rocas alrededor del estanque
	for index = 1, 7 do
		local angle = (index / 7) * math.pi * 2
		local position = world(pond.Center.X + math.cos(angle) * (pond.Radius + 0.5), GROUND - 0.2, pond.Center.Y + math.sin(angle) * (pond.Radius + 0.5))
		PartFactory.ellipsoid(model, "Rock" .. index, CFrame.new(position), Vector3.new(3.4, 1.8, 2.6), Color3.fromRGB(120, 124, 140), Enum.Material.Slate)
	end
	model.Parent = parent
end

function ValleyService.start()
	PartFactory.removeExisting(workspace, ValleyConfig.ModelName)
	buildTerrain()

	local random = Random.new(11) -- semilla fija: el valle es igual en cada partida
	local model = Instance.new("Model")
	model.Name = ValleyConfig.ModelName

	local crystals = PartFactory.folder(model, "Crystals")
	buildGeode(crystals)
	for index, cluster in ValleyConfig.CrystalClusters do
		buildCrystalCluster(crystals, "Cluster" .. index, cluster.X, cluster.Y, cluster.Z, random)
	end

	local trees = PartFactory.folder(model, "Trees")
	for index, tree in ValleyConfig.Trees do
		buildTree(trees, "Tree" .. index, tree.X, tree.Y, tree.Z, random)
	end

	local ruins = PartFactory.folder(model, "Ruins")
	buildArch(ruins)
	for index, column in ValleyConfig.RuinColumns do
		buildColumn(ruins, "Column" .. index, column.X, column.Y, column.Z, random)
	end

	buildWaterfall(model)
	buildFlowers(model)

	model.Parent = workspace
end

return ValleyService
