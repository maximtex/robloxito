-- Construye el Valle Morado / Valle Cristalino (Zona 2) pegado directamente tras el Bosque Inicial
-- (sin puente intermedio), con el mismo estilo de bloques que el Bosque (StudWorld):
-- - Suelo morado en damero con los cuadritos del diseño, caminos y plazas con borde
--   (StudFloor.Zones.CrystalValley). Empieza justo donde acaba el muro sur del Bosque.
-- - Muros perimetrales de damero morado oscuro con remate lavanda y paso hacia la Caldera.
-- - Río cristalino de lado a lado con borde morado; la avenida central lo cruza como puente.
-- - Gran Geoda, Agujas, Ruinas y Árboles de cristal, más árboles de bloques junto a los muros
--   y cristales sueltos por el damero.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ValleyConfig = require(Shared.Config.ValleyConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local StudFloor = require(Shared.Util.StudFloor)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local StudWorld = require(script.Parent.Parent.Util.StudWorld)

local ValleyService = {}

local CENTER_2D = ZoneConfig.Zones.CrystalValley.Center
local ORIGIN = Vector3.new(GeneratorConfig.Position.X + CENTER_2D.X, 0, GeneratorConfig.Position.Z + CENTER_2D.Y)
local GROUND = GeneratorConfig.Position.Y
local VALLEY = StudFloor.Zones.CrystalValley

-- Paleta de mapas-del-mundo.mtl para el Valle Morado
local AGUA_VALLE = Color3.fromRGB(98, 184, 236)
local RUINA = Color3.fromRGB(162, 156, 180)
local PIZARRA = Color3.fromRGB(88, 78, 138)
local VIOLETA = Color3.fromRGB(178, 104, 255)
local AZUL = Color3.fromRGB(68, 138, 255)
local TRONCO = Color3.fromRGB(178, 164, 138)

local COPA_COLORS = {
	Color3.fromRGB(74, 144, 255), -- CopaValle0 (Azul)
	Color3.fromRGB(158, 88, 242), -- CopaValle1 (Violeta)
	Color3.fromRGB(54, 214, 192), -- CopaValle2 (Turquesa)
}

-- Árboles de bloques de los muros: tronco claro y copas de cristal
local BLOCKY_TREE_COLORS = {
	{ Trunk = TRONCO, LeafLight = Color3.fromRGB(158, 88, 242), LeafDark = Color3.fromRGB(122, 64, 206) },
	{ Trunk = TRONCO, LeafLight = Color3.fromRGB(54, 214, 192), LeafDark = Color3.fromRGB(36, 176, 160) },
	{ Trunk = TRONCO, LeafLight = Color3.fromRGB(74, 144, 255), LeafDark = Color3.fromRGB(52, 112, 222) },
}

local SCALE = 12

-- Los 22 árboles de cristal extraídos de mapas-del-mundo.obj
local TREES = {
	{ dX = 1.67, dZ = 5.00, trunkH = 1.17, crownW = 1.45, crownH = 2.18, colorIdx = 1 },
	{ dX = 10.21, dZ = -0.93, trunkH = 0.91, crownW = 1.07, crownH = 1.69, colorIdx = 2 },
	{ dX = 3.88, dZ = -2.19, trunkH = 0.72, crownW = 0.90, crownH = 1.35, colorIdx = 3 },
	{ dX = -2.44, dZ = -3.15, trunkH = 0.91, crownW = 1.12, crownH = 1.69, colorIdx = 1 },
	{ dX = -7.07, dZ = 0.11, trunkH = 0.83, crownW = 0.82, crownH = 1.54, colorIdx = 2 },
	{ dX = 1.33, dZ = -9.81, trunkH = 1.07, crownW = 0.96, crownH = 2.00, colorIdx = 3 },
	{ dX = -4.34, dZ = 0.49, trunkH = 0.92, crownW = 0.86, crownH = 1.71, colorIdx = 1 },
	{ dX = -3.55, dZ = -5.81, trunkH = 1.15, crownW = 1.03, crownH = 2.15, colorIdx = 2 },
	{ dX = -2.10, dZ = 6.63, trunkH = 1.02, crownW = 1.06, crownH = 1.90, colorIdx = 3 },
	{ dX = 2.42, dZ = 7.92, trunkH = 0.88, crownW = 1.00, crownH = 1.64, colorIdx = 1 },
	{ dX = -1.20, dZ = 4.57, trunkH = 0.94, crownW = 1.03, crownH = 1.76, colorIdx = 2 },
	{ dX = 4.28, dZ = -8.69, trunkH = 0.98, crownW = 0.91, crownH = 1.82, colorIdx = 3 },
	{ dX = 6.73, dZ = -4.27, trunkH = 1.02, crownW = 1.02, crownH = 1.90, colorIdx = 1 },
	{ dX = -1.55, dZ = -9.43, trunkH = 1.05, crownW = 1.01, crownH = 1.96, colorIdx = 2 },
	{ dX = 3.89, dZ = 0.92, trunkH = 1.10, crownW = 1.14, crownH = 2.05, colorIdx = 3 },
	{ dX = 0.27, dZ = 6.33, trunkH = 0.92, crownW = 1.01, crownH = 1.71, colorIdx = 1 },
	{ dX = 6.08, dZ = -0.23, trunkH = 1.15, crownW = 1.19, crownH = 2.15, colorIdx = 2 },
	{ dX = -3.99, dZ = -7.68, trunkH = 0.88, crownW = 1.09, crownH = 1.64, colorIdx = 3 },
	{ dX = -4.82, dZ = 3.65, trunkH = 0.87, crownW = 0.84, crownH = 1.63, colorIdx = 1 },
	{ dX = 5.61, dZ = 7.98, trunkH = 1.04, crownW = 0.96, crownH = 1.94, colorIdx = 2 },
	{ dX = 1.71, dZ = 3.13, trunkH = 1.15, crownW = 1.01, crownH = 2.15, colorIdx = 3 },
	{ dX = -6.11, dZ = -2.25, trunkH = 0.81, crownW = 0.98, crownH = 1.52, colorIdx = 1 },
}

-- Posiciones (en unidades de mapas-del-mundo.obj) de la geoda, las agujas y las ruinas
local GEODE = { dX = 1.5, dZ = -5.0 }
local NEEDLES = {
	{ dX = -6.0, dZ = -5.0, H = 26, W = 7.5 },
	{ dX = -7.5, dZ = -3.2, H = 19, W = 6.2 },
	{ dX = -4.6, dZ = -6.8, H = 16, W = 5.5 },
}
local RUINS = {
	{ dX = 5.0, dZ = 5.0, H = 9 },
	{ dX = 6.5, dZ = 4.2, H = 19 },
	{ dX = 7.4, dZ = 5.8, H = 9 },
	{ dX = 5.6, dZ = 6.8, H = 19 },
}

local function world(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

local function objToValley(dX: number, y: number, dZ: number): Vector3
	return world(-dZ * SCALE, y, dX * SCALE)
end

-- Pizarra por debajo del suelo, desde el muro sur del Bosque hasta el de la Caldera
local function buildFlatTerrain()
	StudWorld.fillTerrainBelow(-172, 172, VALLEY.MinZ, VALLEY.MaxZ + StudFloor.Wall.Thickness, Enum.Material.Slate)
end

-- Río cristalino de lado a lado sobre el suelo, con borde morado en las dos orillas; se corta
-- en la avenida central, que lo cruza como puente. Con terrazas sigue entre ellas hasta
-- Hill.Channel.Reach: allí cae una cascada (oeste) y entra en una cueva (este).
local function buildRiver(parent: Instance)
	local folder = PartFactory.folder(parent, "River")
	local river = VALLEY.River
	local border = StudFloor.BorderWidth
	local top = StudWorld.FloorTop
	local channel = VALLEY.Hill and VALLEY.Hill.Channel
	local reach = if channel then channel.Reach else VALLEY.MaxX
	for _, side in { { -reach, -river.BridgeHalf }, { river.BridgeHalf, reach } } do
		local x0, x1 = side[1], side[2]
		local cx, w = (x0 + x1) / 2, x1 - x0
		local water = PartFactory.part(folder, "AguaValle", {
			Size = Vector3.new(w, 0.2, river.MaxZ - river.MinZ - 2 * border),
			CFrame = CFrame.new(cx, top - 0.04, (river.MinZ + river.MaxZ) / 2),
			Color = AGUA_VALLE,
			Material = Enum.Material.Glass,
			Solid = false,
		})
		water.Transparency = 0.15
		for _, z in { river.MinZ + border / 2, river.MaxZ - border / 2 } do
			PartFactory.part(folder, "Orilla", {
				Size = Vector3.new(w, 0.2, border),
				CFrame = CFrame.new(cx, top - 0.04, z),
				Color = VALLEY.Colors.Border,
				Material = Enum.Material.Plastic,
				Solid = false,
			})
		end
	end
	if not channel then
		return
	end
	local width = river.MaxZ - river.MinZ - 2 * border
	local midZ = (river.MinZ + river.MaxZ) / 2
	local cliff = VALLEY.Hill.Terraces[#VALLEY.Hill.Terraces].Height
	-- Cascada: lámina de agua que cae del escalón más alto, espuma abajo y bruma
	local fall = PartFactory.part(folder, "Cascada", {
		Size = Vector3.new(1, cliff, width),
		CFrame = CFrame.new(-reach + 0.6, top + cliff / 2, midZ),
		Color = Color3.fromRGB(150, 225, 255),
		Material = Enum.Material.Neon,
		Solid = false,
	})
	fall.Transparency = 0.35
	local foam = PartFactory.part(folder, "Espuma", {
		Size = Vector3.new(6, 0.6, width),
		CFrame = CFrame.new(-reach + 3.5, top + 0.2, midZ),
		Color = Color3.fromRGB(235, 250, 255),
		Material = Enum.Material.Neon,
		Solid = false,
	})
	foam.Transparency = 0.2
	local mist = Instance.new("ParticleEmitter")
	mist.Name = "Bruma"
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(Color3.fromRGB(230, 248, 255))
	mist.Transparency = NumberSequence.new(0.55, 1)
	mist.Size = NumberSequence.new(3, 7)
	mist.Lifetime = NumberRange.new(1.2, 2)
	mist.Rate = 12
	mist.Speed = NumberRange.new(2, 4)
	mist.SpreadAngle = Vector2.new(60, 60)
	mist.Parent = foam
	-- Cueva: boca oscura en el escalón más alto con un marco de piedra
	local caveH = 22
	PartFactory.part(folder, "CuevaBoca", {
		Size = Vector3.new(1, caveH, width),
		CFrame = CFrame.new(reach - 0.6, top + caveH / 2, midZ),
		Color = Color3.fromRGB(18, 12, 34),
		Material = Enum.Material.SmoothPlastic,
		Solid = true,
	})
	for _, spec in {
		{ Size = Vector3.new(2, 4, width + 8), Offset = Vector3.new(0, caveH + 2, 0) },
		{ Size = Vector3.new(2, caveH + 4, 4), Offset = Vector3.new(0, (caveH + 4) / 2, -width / 2 - 2) },
		{ Size = Vector3.new(2, caveH + 4, 4), Offset = Vector3.new(0, (caveH + 4) / 2, width / 2 + 2) },
	} do
		StudWorld.allStuds(PartFactory.part(folder, "CuevaMarco", {
			Size = spec.Size,
			CFrame = CFrame.new(Vector3.new(reach - 1, top, midZ) + spec.Offset),
			Color = PIZARRA,
			Material = Enum.Material.Plastic,
			Solid = true,
		}))
	end
end

-- Zonas ocupadas por la geoda, las agujas y las ruinas: { x, z, radio } en el mundo
local function landmarkKeepOut(): { { number } }
	local list: { { number } } = {}
	local geodePos = objToValley(GEODE.dX, 0, GEODE.dZ)
	table.insert(list, { geodePos.X, geodePos.Z, 30 })
	for _, aSpec in NEEDLES do
		local pos = objToValley(aSpec.dX, 0, aSpec.dZ)
		table.insert(list, { pos.X, pos.Z, aSpec.W + 4 })
	end
	for _, rSpec in RUINS do
		local pos = objToValley(rSpec.dX, 0, rSpec.dZ)
		table.insert(list, { pos.X, pos.Z, 8 })
	end
	return list
end

-- Geoda gigante (GeodaRoca + GeodaCristal1..3), Agujas (Aguja1..3), Ruinas y Árboles de cristal
-- (los que caerían sobre un camino o el río no se ponen)
local function buildLandmarks(parent: Instance, decor)
	local landmarks = PartFactory.folder(parent, "Landmarks")
	local diamondRot = CFrame.Angles(math.rad(45), 0, math.rad(35.264))

	local geodePos = objToValley(GEODE.dX, GROUND, GEODE.dZ)
	PartFactory.part(landmarks, "GeodaRoca", {
		Size = Vector3.new(36, 20, 42),
		CFrame = CFrame.new(geodePos + Vector3.new(0, 10, 0)) * CFrame.Angles(0, math.rad(25), 0),
		Color = PIZARRA,
		Material = Enum.Material.Slate,
		Solid = true,
	})
	PartFactory.part(landmarks, "GeodaRocaTop", {
		Size = Vector3.new(26, 12, 30),
		CFrame = CFrame.new(geodePos + Vector3.new(0, 22, 0)) * CFrame.Angles(0, math.rad(55), 0),
		Color = PIZARRA,
		Material = Enum.Material.Slate,
		Solid = true,
	})
	for index, cSpec in {
		{ Offset = Vector3.new(0, 28, 0), Size = Vector3.new(7, 18, 7), Tilt = CFrame.Angles(math.rad(8), 0, math.rad(-6)) },
		{ Offset = Vector3.new(-7, 24, -6), Size = Vector3.new(5.5, 13, 5.5), Tilt = CFrame.Angles(math.rad(-14), 0, math.rad(16)) },
		{ Offset = Vector3.new(7, 25, 6), Size = Vector3.new(6, 14, 6), Tilt = CFrame.Angles(math.rad(12), 0, math.rad(-18)) },
	} do
		PartFactory.part(landmarks, "GeodaCristal" .. index, {
			Size = cSpec.Size,
			CFrame = CFrame.new(geodePos + cSpec.Offset) * cSpec.Tilt * CFrame.Angles(0, math.rad(45), 0),
			Color = VIOLETA,
			Material = Enum.Material.Neon,
			Solid = false,
		})
	end

	for index, aSpec in NEEDLES do
		local pos = objToValley(aSpec.dX, GROUND + aSpec.H / 2, aSpec.dZ)
		PartFactory.part(landmarks, "Aguja" .. index, {
			Size = Vector3.new(aSpec.W, aSpec.H, aSpec.W),
			CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(6), math.rad(index * 35), math.rad(-5)),
			Color = AZUL,
			Material = Enum.Material.Neon,
			Solid = true,
		})
	end

	for index, rSpec in RUINS do
		local pos = objToValley(rSpec.dX, GROUND + rSpec.H / 2, rSpec.dZ)
		PartFactory.verticalCylinder(landmarks, "RuinaColumna" .. index, pos, rSpec.H, 5.5, RUINA, Enum.Material.Slate, true)
	end

	local treesFolder = PartFactory.folder(landmarks, "CrystalTrees")
	for index, t in TREES do
		local safeDZ = if math.abs(t.dZ) < 1.35 then (if t.dZ >= 0 then 1.6 else -1.6) else t.dZ
		local base = objToValley(t.dX, GROUND, safeDZ)
		if decor.isFree(base.X, base.Z, 4, math.huge, 6) then
			decor.claim(base.X, base.Z, 6)
			local trunkH = t.trunkH * 7.5
			local crownSize = t.crownW * 7.5
			local crownColor = COPA_COLORS[t.colorIdx] or COPA_COLORS[1]

			PartFactory.verticalCylinder(
				treesFolder,
				"ValleArbol_" .. index .. "_Tronco",
				base + Vector3.new(0, trunkH / 2, 0),
				trunkH,
				2.2,
				TRONCO,
				Enum.Material.SmoothPlastic,
				true
			)
			PartFactory.part(treesFolder, "ValleArbol_" .. index .. "_Copa", {
				Size = Vector3.one * crownSize,
				CFrame = CFrame.new(base + Vector3.new(0, trunkH + crownSize * 0.55, 0)) * diamondRot,
				Color = crownColor,
				Material = Enum.Material.Neon,
				Solid = false,
			})
		end
	end
end

-- Cristales sueltos: tres puntas de neón inclinadas sobre una piedra de pizarra
local function buildCrystalCluster(parent: Instance, pos: Vector3, yawDeg: number, color: Color3)
	local m = Instance.new("Model")
	m.Name = "CrystalCluster"
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	StudWorld.allStuds(PartFactory.part(m, "Base", {
		Size = Vector3.new(3.4, 0.8, 3.4),
		CFrame = cf * CFrame.new(0, 0.4, 0),
		Color = PIZARRA,
		Material = Enum.Material.Plastic,
		Solid = false,
	}))
	for index, spec in {
		{ Offset = Vector3.new(0, 2.2, 0), Size = Vector3.new(1.3, 3.8, 1.3), Tilt = CFrame.Angles(math.rad(6), 0, math.rad(-8)) },
		{ Offset = Vector3.new(-1.0, 1.5, 0.6), Size = Vector3.new(0.9, 2.4, 0.9), Tilt = CFrame.Angles(math.rad(-12), 0, math.rad(24)) },
		{ Offset = Vector3.new(1.0, 1.6, -0.5), Size = Vector3.new(1.0, 2.6, 1.0), Tilt = CFrame.Angles(math.rad(14), 0, math.rad(-22)) },
	} do
		PartFactory.part(m, "Cristal" .. index, {
			Size = spec.Size,
			CFrame = cf * CFrame.new(spec.Offset) * spec.Tilt * CFrame.Angles(0, math.rad(45), 0),
			Color = color,
			Material = Enum.Material.Neon,
			Solid = false,
		})
	end
	m.Parent = parent
end

-- Árboles de bloques de cristal junto a los muros y cristales sueltos por el damero
local function buildDecor(parent: Instance, decor)
	local folder = PartFactory.folder(parent, "MapDetails")
	local rng = decor.Rng
	local crystals = ValleyConfig.Colors.Crystals
	decor.wallRow(22, 9, 12, function(pos, yaw)
		local colors = BLOCKY_TREE_COLORS[rng:NextInteger(1, #BLOCKY_TREE_COLORS)]
		StudWorld.buildBlockyTree(folder, pos, yaw, rng:NextNumber(0.95, 1.2), colors)
	end)
	decor.scatter(22, 2, math.huge, 6, function(pos, yaw)
		buildCrystalCluster(folder, pos, yaw, crystals[rng:NextInteger(1, #crystals)])
	end)
	-- Faroles de cristal en la avenida y transición volcánica junto al portal sur hacia la Caldera
	local top = StudWorld.FloorTop
	for _, zOff in { -110, -45, 45, 105 } do
		for _, side in { -1, 1 } do
			local p = world(side * 16, top, zOff)
			PartFactory.verticalCylinder(folder, "CrystalLanternPost", p + Vector3.new(0, 2.2, 0), 4.4, 0.9, PIZARRA, Enum.Material.Slate, true)
			PartFactory.part(folder, "CrystalLanternGem", {
				Size = Vector3.new(1.3, 2.2, 1.3),
				CFrame = CFrame.new(p + Vector3.new(0, 5.2, 0)) * CFrame.Angles(math.rad(12), math.rad(45), 0),
				Color = VIOLETA,
				Material = Enum.Material.Neon,
				Solid = false,
			})
		end
	end
	for _, side in { -1, 1 } do
		local gatePos = world(side * 15, top, 145)
		PartFactory.part(folder, "CalderaTransitionRock", {
			Size = Vector3.new(3.2, 4.4, 2.8),
			CFrame = CFrame.new(gatePos + Vector3.new(0, 2.2, 0)) * CFrame.Angles(math.rad(8), math.rad(side * 25), math.rad(-side * 10)),
			Color = Color3.fromRGB(64, 48, 44),
			Material = Enum.Material.Basalt,
			Solid = true,
		})
		PartFactory.part(folder, "CalderaTransitionVein", {
			Size = Vector3.new(0.7, 3.8, 0.7),
			CFrame = CFrame.new(gatePos + Vector3.new(-side * 0.8, 2.4, -0.6)) * CFrame.Angles(math.rad(8), 0, math.rad(-side * 10)),
			Color = Color3.fromRGB(255, 128, 36),
			Material = Enum.Material.Neon,
			Solid = false,
		})
	end
end

-- Sobre las terrazas: cristales en los escalones 3 y 4 y árboles de cristal en el 1 y el 2,
-- repartidos siempre igual (una de cada pocas casillas)
local function buildTerraceDecor(parent: Instance, tops: { { Position: Vector3, Ring: number } })
	local folder = PartFactory.folder(parent, "TerraceDecor")
	local crystals = ValleyConfig.Colors.Crystals
	local rng = Random.new(VALLEY.DecorSeed + 7)
	for index, cell in tops do
		if cell.Ring >= 3 and index % 6 == 0 then
			buildCrystalCluster(folder, cell.Position, rng:NextNumber(0, 360), crystals[rng:NextInteger(1, #crystals)])
		elseif cell.Ring <= 2 and index % 11 == 0 then
			local colors = BLOCKY_TREE_COLORS[rng:NextInteger(1, #BLOCKY_TREE_COLORS)]
			StudWorld.buildBlockyTree(folder, cell.Position, rng:NextNumber(0, 360), rng:NextNumber(0.75, 0.95), colors)
		end
	end
end

function ValleyService.start()
	PartFactory.removeExisting(workspace, ValleyConfig.ModelName)
	buildFlatTerrain()

	local model = Instance.new("Model")
	model.Name = ValleyConfig.ModelName
	StudWorld.buildFloor(model, VALLEY)
	local tops = StudWorld.buildWalls(model, VALLEY)
	buildRiver(model)
	local decor = StudWorld.newDecor(VALLEY, "CrystalValley", landmarkKeepOut())
	buildLandmarks(model, decor)
	buildDecor(model, decor)
	if tops then
		buildTerraceDecor(model, tops)
	end
	model.Parent = workspace
end

return ValleyService
