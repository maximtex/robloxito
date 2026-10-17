-- Construye el claro mágico alrededor del cristal:
-- - Terrain: pradera, colinas, rocas, plaza de adoquines y camino de tierra.
-- - Piezas ancladas: árbol ancestral con raíces gigantes, árboles, arco y columnas
--   en ruinas, piedras del camino, setas luminosas, cristales y flores.
-- - Iluminación de tarde con atmósfera.
-- Es solo decorativo. No añade luces dinámicas: las setas y cristales usan neón.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldConfig = require(Shared.Config.WorldConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)

local Colors = WorldConfig.Colors
local TerrainConfig = WorldConfig.Terrain

local WorldService = {}

-- Origen: el cristal a nivel del suelo; GROUND es la altura de la superficie.
local ORIGIN = Vector3.new(GeneratorConfig.Position.X, 0, GeneratorConfig.Position.Z)
local GROUND = GeneratorConfig.Position.Y

local function world(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

local function segment(parent: Instance, name: string, from: Vector3, to: Vector3, diameter: number, color: Color3, material: Enum.Material)
	local direction = to - from
	return PartFactory.part(parent, name, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(direction.Magnitude, diameter, diameter),
		CFrame = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0),
		Color = color,
		Material = material,
	})
end

local function ball(parent: Instance, name: string, center: Vector3, diameter: number, color: Color3, material: Enum.Material, solid: boolean?)
	return PartFactory.part(parent, name, {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter,
		CFrame = CFrame.new(center),
		Color = color,
		Material = material,
		Solid = solid,
	})
end

-- Elipsoide nativo (SpecialMesh de tipo esfera, sin recursos externos).
local function ellipsoid(parent: Instance, name: string, cframe: CFrame, size: Vector3, color: Color3, material: Enum.Material)
	local part = PartFactory.part(parent, name, {
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material,
		Solid = false,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Terreno -------------------------------------------------------------------

local function buildTerrain()
	local terrain = workspace.Terrain
	for materialName, color in TerrainConfig.MaterialColors do
		terrain:SetMaterialColor((Enum.Material :: any)[materialName], color)
	end

	local size = TerrainConfig.Size
	local thickness = TerrainConfig.Thickness
	terrain:FillBlock(CFrame.new(world(0, GROUND - thickness / 2, 0)), Vector3.new(size, thickness, size), Enum.Material.Grass)

	for _, hill in TerrainConfig.Hills do
		local radius = hill.Z
		terrain:FillBall(world(hill.X, GROUND - radius * 0.6, hill.Y), radius, Enum.Material.Grass)
	end
	for _, rock in TerrainConfig.Rocks do
		local radius = rock.Z
		terrain:FillBall(world(rock.X, GROUND - radius * 0.45, rock.Y), radius, Enum.Material.Rock)
	end

	-- Plaza y camino: se pinta la capa superficial (misma altura que la pradera).
	local paintDepth = 4
	terrain:FillCylinder(CFrame.new(world(0, GROUND - paintDepth / 2, 0)), paintDepth, TerrainConfig.PlazaRadius, Enum.Material.Cobblestone)

	local pathStart = TerrainConfig.PlazaRadius - 1
	local pathLength = TerrainConfig.PathEndZ - pathStart
	terrain:FillBlock(
		CFrame.new(world(0, GROUND - paintDepth / 2, pathStart + pathLength / 2)),
		Vector3.new(TerrainConfig.PathWidth, paintDepth, pathLength),
		Enum.Material.Ground
	)
end

-- Árboles ---------------------------------------------------------------------

local function buildTree(parent: Instance, name: string, x: number, z: number, scale: number, random: Random)
	local model = Instance.new("Model")
	model.Name = name

	local base = world(x, GROUND - 0.5, z)
	local trunkHeight = 9 * scale
	local trunkDiameter = 1.6 * scale
	-- Tronco ligeramente inclinado en dos tramos
	local lean = Vector3.new(random:NextNumber(-0.8, 0.8), 0, random:NextNumber(-0.8, 0.8)) * scale
	local middle = base + Vector3.new(0, trunkHeight * 0.55, 0) + lean * 0.5
	local top = base + Vector3.new(0, trunkHeight, 0) + lean
	segment(model, "TrunkLower", base, middle, trunkDiameter, Colors.Bark, Enum.Material.Wood)
	segment(model, "TrunkUpper", middle, top, trunkDiameter * 0.8, Colors.Bark, Enum.Material.Wood)

	-- Copa: varias esferas de follaje
	local canopy = {
		{ Vector3.new(0, 1.5, 0), 8 },
		{ Vector3.new(2.6, 0.4, 1.2), 6 },
		{ Vector3.new(-2.4, 0.6, -1.4), 6.4 },
		{ Vector3.new(0.6, 3.6, -0.8), 5.4 },
	}
	for index, blob in canopy do
		local color = Colors.Leaves[random:NextInteger(1, #Colors.Leaves)]
		local foliage = ball(model, "Leaves" .. index, top + blob[1] * scale, blob[2] * scale, color, Enum.Material.LeafyGrass, false)
		foliage.CastShadow = true
	end

	model.Parent = parent
end

local function buildAncientTree(parent: Instance)
	local config = WorldConfig.AncientTree
	local model = Instance.new("Model")
	model.Name = "AncientTree"

	local base = world(config.Position.X, GROUND - 1, config.Position.Y)
	local diameter = config.TrunkDiameter
	local height = config.TrunkHeight

	-- Tronco en tres tramos que se estrechan
	local p1 = base + Vector3.new(0, height * 0.4, 0)
	local p2 = base + Vector3.new(1.2, height * 0.75, -0.6)
	local p3 = base + Vector3.new(0.4, height, -1.2)
	segment(model, "Trunk1", base, p1, diameter, Colors.DarkBark, Enum.Material.Wood)
	ball(model, "TrunkKnot1", p1, diameter * 0.92, Colors.DarkBark, Enum.Material.Wood)
	segment(model, "Trunk2", p1, p2, diameter * 0.85, Colors.DarkBark, Enum.Material.Wood)
	ball(model, "TrunkKnot2", p2, diameter * 0.78, Colors.DarkBark, Enum.Material.Wood)
	segment(model, "Trunk3", p2, p3, diameter * 0.7, Colors.DarkBark, Enum.Material.Wood)

	-- Ramas principales
	for index, branch in { Vector3.new(10, 5, -2), Vector3.new(-9, 6, 1), Vector3.new(2, 7, -9), Vector3.new(-3, 4, 8) } do
		segment(model, "Branch" .. index, p2, p2 + branch, diameter * 0.32, Colors.DarkBark, Enum.Material.Wood)
	end

	-- Copa amplia con follaje turquesa mágico mezclado
	local canopy = {
		{ Vector3.new(0, 4, 0), 22, Colors.Leaves[2] },
		{ Vector3.new(10, 1, -3), 15, Colors.Leaves[1] },
		{ Vector3.new(-10, 2, 2), 16, Colors.Leaves[3] },
		{ Vector3.new(2, 1, -10), 14, Colors.Leaves[1] },
		{ Vector3.new(-3, 0, 9), 13, Colors.MagicLeaves },
		{ Vector3.new(5, 9, 3), 12, Colors.MagicLeaves },
	}
	for index, blob in canopy do
		local foliage = ball(model, "Canopy" .. index, p3 + blob[1], blob[2], blob[3], Enum.Material.LeafyGrass, false)
		foliage.CastShadow = true
	end

	-- Raíces gigantes que se extienden por el suelo (arqueadas, se puede pasar por debajo de las altas)
	local roots = Instance.new("Model")
	roots.Name = "GiantRoots"
	roots.Parent = model
	for rootIndex = 1, config.RootCount do
		local angle = (rootIndex - 0.5) / config.RootCount * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local reach = config.RootReach * (if rootIndex % 2 == 0 then 1 else 0.75)
		local points = {
			base + direction * (diameter * 0.35) + Vector3.new(0, 4, 0),
			base + direction * (reach * 0.35) + Vector3.new(0, 3.2, 0),
			base + direction * (reach * 0.7) + Vector3.new(0, 1.4, 0),
			base + direction * reach + Vector3.new(0, -0.6, 0),
		}
		local thickness = { 3, 2.3, 1.5 }
		for step = 1, 3 do
			segment(roots, "Root" .. rootIndex .. "_" .. step, points[step], points[step + 1], thickness[step], Colors.DarkBark, Enum.Material.Wood)
			ball(roots, "Knot" .. rootIndex .. "_" .. step, points[step], thickness[step], Colors.DarkBark, Enum.Material.Wood)
		end
	end

	model.Parent = parent
end

-- Ruinas ----------------------------------------------------------------------

local function buildColumn(parent: Instance, name: string, x: number, z: number, height: number, random: Random)
	local model = Instance.new("Model")
	model.Name = name
	local diameter = 2

	if height > 0 then
		local base = world(x, GROUND, z)
		PartFactory.part(model, "Plinth", {
			Size = Vector3.new(2.8, 0.6, 2.8),
			CFrame = CFrame.new(base + Vector3.new(0, 0.3, 0)),
			Color = Colors.RuinStone,
			Material = Enum.Material.Cobblestone,
		})
		PartFactory.verticalCylinder(model, "Shaft", base + Vector3.new(0, 0.6 + height / 2, 0), height, diameter, Colors.RuinStone, Enum.Material.Slate, true)
		-- Musgo en la parte superior rota
		PartFactory.verticalCylinder(model, "Moss", base + Vector3.new(0, 0.6 + height + 0.1, 0), 0.25, diameter + 0.15, Colors.Moss, Enum.Material.LeafyGrass, false)
	else
		-- Columna caída, tumbada sobre la hierba
		local yaw = random:NextNumber(0, math.pi)
		PartFactory.part(model, "Fallen", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(6, diameter, diameter),
			CFrame = CFrame.new(world(x, GROUND + diameter / 2 - 0.3, z)) * CFrame.Angles(0, yaw, 0),
			Color = Colors.RuinStone,
			Material = Enum.Material.Slate,
		})
	end

	model.Parent = parent
end

local function buildArch(parent: Instance)
	local arch = WorldConfig.RuinArch
	local model = Instance.new("Model")
	model.Name = "RuinArch"

	local pillar = arch.PillarSize
	local halfWidth = arch.Width / 2
	for index, side in { -1, 1 } do
		local x = side * halfWidth
		PartFactory.part(model, "Pillar" .. index, {
			Size = Vector3.new(pillar, arch.Height, pillar),
			CFrame = CFrame.new(world(x, GROUND + arch.Height / 2, arch.Z)),
			Color = Colors.RuinStone,
			Material = Enum.Material.Cobblestone,
		})
		-- Hiedra colgando de la cara interior
		PartFactory.part(model, "Ivy" .. index, {
			Size = Vector3.new(0.2, arch.Height * 0.55, 1.2),
			CFrame = CFrame.new(world(x - side * (pillar / 2 + 0.05), GROUND + arch.Height * 0.68, arch.Z)),
			Color = Colors.Moss,
			Material = Enum.Material.LeafyGrass,
			Solid = false,
		})
	end
	PartFactory.part(model, "Lintel", {
		Size = Vector3.new(arch.Width + pillar + 1, 1.6, pillar + 0.4),
		CFrame = CFrame.new(world(0, GROUND + arch.Height + 0.8, arch.Z)) * CFrame.Angles(0, 0, math.rad(2)),
		Color = Colors.RuinStone,
		Material = Enum.Material.Slate,
	})
	PartFactory.part(model, "LintelMoss", {
		Size = Vector3.new(arch.Width * 0.6, 0.3, pillar + 0.5),
		CFrame = CFrame.new(world(-1.5, GROUND + arch.Height + 1.75, arch.Z)),
		Color = Colors.Moss,
		Material = Enum.Material.LeafyGrass,
		Solid = false,
	})

	model.Parent = parent
end

local function buildSteppingStones(parent: Instance)
	local folder = PartFactory.folder(parent, "SteppingStones")
	local plazaEdge = TerrainConfig.PlazaRadius
	local index = 0
	local z = plazaEdge + 1.5
	while z < TerrainConfig.PathEndZ - 1 do
		index += 1
		local offset = if index % 2 == 0 then 0.7 else -0.7
		PartFactory.verticalCylinder(folder, "Stone" .. index, world(offset, GROUND + 0.05, z), 0.3, 2.6 + (index % 3) * 0.3, Colors.StepStone, Enum.Material.Slate, false)
		z += 3.2
	end
end

-- Flora mágica -----------------------------------------------------------------

local function buildMushrooms(parent: Instance, random: Random)
	local folder = PartFactory.folder(parent, "GlowMushrooms")
	for clusterIndex, cluster in WorldConfig.MushroomClusters do
		local capColor = Colors.MushroomCaps[(clusterIndex - 1) % #Colors.MushroomCaps + 1]
		for index = 1, cluster.Z do
			local offset = Vector3.new(random:NextNumber(-1.4, 1.4), 0, random:NextNumber(-1.4, 1.4))
			local height = random:NextNumber(0.6, 1.5)
			local stemDiameter = height * 0.35
			local base = world(cluster.X, GROUND, cluster.Y) + offset
			local name = "Mushroom" .. clusterIndex .. "_" .. index
			PartFactory.verticalCylinder(folder, name .. "Stem", base + Vector3.new(0, height / 2, 0), height, stemDiameter, Colors.MushroomStem, Enum.Material.SmoothPlastic, false)
			local capWidth = stemDiameter * 3.2
			ellipsoid(folder, name .. "Cap", CFrame.new(base + Vector3.new(0, height, 0)), Vector3.new(capWidth, capWidth * 0.5, capWidth), capColor, Enum.Material.Neon)
		end
	end
end

local function buildCrystals(parent: Instance, random: Random)
	local folder = PartFactory.folder(parent, "SmallCrystals")
	for clusterIndex, cluster in WorldConfig.CrystalClusters do
		for index = 1, cluster.Z do
			local height = random:NextNumber(1.2, 2.6)
			local base = world(cluster.X, GROUND, cluster.Y) + Vector3.new(random:NextNumber(-0.8, 0.8), 0, random:NextNumber(-0.8, 0.8))
			local cframe = CFrame.new(base)
				* CFrame.Angles(random:NextNumber(-0.35, 0.35), random:NextNumber(0, math.pi), random:NextNumber(-0.35, 0.35))
				* CFrame.new(0, height / 2 - 0.2, 0)
			local shard = PartFactory.part(folder, "Crystal" .. clusterIndex .. "_" .. index, {
				Size = Vector3.new(0.55, height, 0.55),
				CFrame = cframe,
				Color = Colors.Crystal,
				-- Uno de cada racimo brilla; el resto es vidrio.
				Material = if index == 1 then Enum.Material.Neon else Enum.Material.Glass,
				Solid = false,
			})
			if index ~= 1 then
				shard.Transparency = 0.2
			end
		end
	end
end

local function isClear(x: number, z: number): boolean
	for _, zone in WorldConfig.KeepClear do
		if (Vector2.new(x, z) - Vector2.new(zone.X, zone.Y)).Magnitude < zone.Z then
			return false
		end
	end
	-- Camino de tierra
	if math.abs(x) < TerrainConfig.PathWidth / 2 + 1 and z > 0 and z < TerrainConfig.PathEndZ then
		return false
	end
	return true
end

local function buildFlowers(parent: Instance)
	local settings = WorldConfig.Flowers
	local random = Random.new(settings.Seed)
	local folder = PartFactory.folder(parent, "Flowers")

	local placed = 0
	local attempts = 0
	while placed < settings.Clusters and attempts < settings.Clusters * 10 do
		attempts += 1
		local angle = random:NextNumber(0, math.pi * 2)
		local radius = random:NextNumber(settings.MinRadius, settings.MaxRadius)
		local x, z = math.cos(angle) * radius, math.sin(angle) * radius
		if isClear(x, z) then
			placed += 1
			local magic = random:NextNumber() < settings.MagicChance
			local color = if magic then Colors.MagicFlower else Colors.Flowers[random:NextInteger(1, #Colors.Flowers)]
			for index = 1, 3 do
				local position = world(x + random:NextNumber(-1, 1), GROUND + 0.3, z + random:NextNumber(-1, 1))
				ball(folder, "Flower" .. placed .. "_" .. index, position, random:NextNumber(0.4, 0.6), color, if magic then Enum.Material.Neon else Enum.Material.SmoothPlastic, false)
			end
		end
	end
end

-- Iluminación ---------------------------------------------------------------

local function applyLighting()
	local settings = WorldConfig.Lighting
	if not settings.Enabled then
		return
	end

	Lighting.ClockTime = settings.ClockTime
	Lighting.Ambient = settings.Ambient
	Lighting.OutdoorAmbient = settings.OutdoorAmbient

	-- Respeta un Atmosphere que ya exista en el place; solo crea el nuestro si no hay ninguno.
	local atmosphereSettings = settings.Atmosphere
	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	if existing and existing.Name ~= atmosphereSettings.Name then
		return
	end
	local atmosphere = existing or Instance.new("Atmosphere")
	atmosphere.Name = atmosphereSettings.Name
	atmosphere.Density = atmosphereSettings.Density
	atmosphere.Offset = atmosphereSettings.Offset
	atmosphere.Color = atmosphereSettings.Color
	atmosphere.Decay = atmosphereSettings.Decay
	atmosphere.Glare = atmosphereSettings.Glare
	atmosphere.Haze = atmosphereSettings.Haze
	atmosphere.Parent = Lighting
end

function WorldService.start()
	PartFactory.removeExisting(workspace, WorldConfig.ModelName)

	buildTerrain()

	-- Semilla fija: el mundo es igual en cada partida.
	local random = Random.new(7)
	local model = Instance.new("Model")
	model.Name = WorldConfig.ModelName

	local trees = PartFactory.folder(model, "Trees")
	buildAncientTree(trees)
	for index, tree in WorldConfig.Trees do
		buildTree(trees, "Tree" .. index, tree.X, tree.Y, tree.Z, random)
	end

	local ruins = PartFactory.folder(model, "Ruins")
	buildArch(ruins)
	for index, column in WorldConfig.RuinColumns do
		buildColumn(ruins, "Column" .. index, column.X, column.Y, column.Z, random)
	end

	buildSteppingStones(model)

	local flora = PartFactory.folder(model, "Flora")
	buildMushrooms(flora, random)
	buildCrystals(flora, random)
	buildFlowers(flora)

	model.Parent = workspace
	applyLighting()
end

return WorldService
