-- Construye el pueblo del Mundo 2 (ZoneConfig.Zones.World2, lejos de todo: centro (2000, 0)),
-- como el spawn del Mundo 1 pero más bonito, con el estilo de bloques (StudWorld; distribución
-- en StudFloor.Zones.World2):
-- - Plaza con la Fuente de la Estrella en el centro y los cuatro puestos de siempre (Clases,
--   Mejoras, Tienda y Armería: VillageService.buildStall) y la Máquina de Evolución.
-- - Jardín Celestial al norte con los 3 huevos mejores (los pedestales los pone EggStandService:
--   EggConfig.Eggs.*.Zone = "World2").
-- - Avenida al sur, donde se llega (el círculo de aparición), y el portal de vuelta al Mundo 1
--   (ZoneService: ZoneConfig.WorldPortals.ReturnPortal).
-- - Árboles de colores, farolas doradas, setos con flores y terrazas de colores alrededor.
-- - Al norte del Jardín, el paso a la puerta de las Tierras Divididas (zona 1 del Mundo 2:
--   DividedLandsService), con un arco y un cartel en la plaza que lo indica. Solo decorativo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local SpawnConfig = require(Shared.Config.SpawnConfig)
local StudFloor = require(Shared.Util.StudFloor)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local StudWorld = require(script.Parent.Parent.Util.StudWorld)
local VillageService = require(script.Parent.VillageService)

local World2Service = {}

local MODEL_NAME = "World2"
local ZONE = ZoneConfig.Zones.World2
local ORIGIN = Vector3.new(GeneratorConfig.Position.X + ZONE.Center.X, 0, GeneratorConfig.Position.Z + ZONE.Center.Y)
local LAYOUT = StudFloor.Zones.World2
local RGB = Color3.fromRGB

local GOLD = RGB(255, 206, 84)
local MARBLE = { RGB(246, 242, 232), RGB(226, 220, 206) }
local WATER = RGB(110, 210, 240)
local TREE_COLORS = {
	{ Trunk = RGB(150, 104, 70), LeafLight = RGB(255, 170, 214), LeafDark = RGB(240, 140, 196) }, -- cerezo
	{ Trunk = RGB(150, 104, 70), LeafLight = RGB(130, 230, 214), LeafDark = RGB(100, 210, 196) }, -- turquesa
	{ Trunk = RGB(150, 104, 70), LeafLight = RGB(255, 220, 110), LeafDark = RGB(246, 196, 80) }, -- dorado
}
local FLOWERS = { RGB(255, 120, 160), RGB(255, 220, 90), RGB(160, 140, 255), RGB(255, 255, 255) }

local TOP = StudWorld.FloorTop

local function world(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

local function v2(x: number, z: number): Vector2
	return Vector2.new(ORIGIN.X + x, ORIGIN.Z + z)
end

local function studBlock(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, solid: boolean?): BasePart
	return StudWorld.allStuds(PartFactory.part(parent, name, {
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.Plastic,
		Solid = solid == true,
	}))
end

local function sign(parent: Instance, position: Vector3, text: string, color: Color3, width: number, height: number, distance: number)
	local anchor = PartFactory.part(parent, "Cartel", {
		Size = Vector3.one * 0.2,
		CFrame = CFrame.new(position),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	anchor.Transparency = 1
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(width, height)
	billboard.LightInfluence = 0
	billboard.MaxDistance = distance
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.RichText = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3.5
	stroke.Color = RGB(30, 24, 50)
	stroke.Parent = label
	billboard.Parent = anchor
end

local function buildFlatTerrain()
	StudWorld.fillTerrainBelow(LAYOUT.MinX - 60, LAYOUT.MaxX + 60, LAYOUT.MinZ - 60, LAYOUT.MaxZ + 60, Enum.Material.Grass)
end

-- Fuente de la Estrella: pilón redondo de mármol con agua, columna y una estrella dorada que
-- brilla encima
local function buildFountain(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "FuenteDeLaEstrella"
	local floorY = TOP + StudFloor.PathRaise
	local center = world(0, floorY, 0)
	PartFactory.verticalCylinder(m, "Pilon", center + Vector3.new(0, 1, 0), 2, 18, MARBLE[1], Enum.Material.Marble, true)
	PartFactory.verticalCylinder(m, "Agua", center + Vector3.new(0, 2.05, 0), 0.2, 16.4, WATER, Enum.Material.Glass, false).Transparency = 0.25
	PartFactory.verticalCylinder(m, "Borde", center + Vector3.new(0, 2.1, 0), 0.2, 18.4, GOLD, Enum.Material.Metal, false)
	PartFactory.verticalCylinder(m, "Columna", center + Vector3.new(0, 5, 0), 8, 3, MARBLE[2], Enum.Material.Marble, true)
	PartFactory.verticalCylinder(m, "Plato", center + Vector3.new(0, 9.2, 0), 0.8, 7, MARBLE[1], Enum.Material.Marble, false)
	-- Estrella de cinco puntas: un núcleo y cinco puntas en un plano vertical
	local starCenter = center + Vector3.new(0, 15, 0)
	local core = PartFactory.ball(m, "Estrella", starCenter, 3.2, GOLD, Enum.Material.Neon, false)
	for index = 1, 5 do
		local a = index / 5 * math.pi * 2
		PartFactory.part(m, "Punta", {
			Size = Vector3.new(1.4, 3.4, 1.0),
			CFrame = CFrame.new(starCenter) * CFrame.Angles(0, 0, a) * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, math.rad(45), 0),
			Color = GOLD,
			Material = Enum.Material.Neon,
			Solid = false,
		})
	end
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 30
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = core
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(GOLD, RGB(255, 255, 220))
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Lifetime = NumberRange.new(1.2, 2)
	sparkles.Rate = 14
	sparkles.Speed = NumberRange.new(1.5, 3)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Parent = core
	-- Chorritos de agua alrededor
	for index = 1, 6 do
		local a = index / 6 * math.pi * 2
		local jet = PartFactory.part(m, "Chorro", {
			Size = Vector3.new(0.5, 3, 0.5),
			CFrame = CFrame.new(center + Vector3.new(math.cos(a) * 3.2, 3.6, math.sin(a) * 3.2)) * CFrame.Angles(math.sin(a) * 0.4, 0, -math.cos(a) * 0.4),
			Color = WATER:Lerp(Color3.new(1, 1, 1), 0.4),
			Material = Enum.Material.Glass,
			Solid = false,
		})
		jet.Transparency = 0.35
	end
	m.Parent = parent
end

-- Círculo de aparición (decorado como los SpawnLocation del Mundo 1): aquí se llega
local function buildSpawnPad(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "CirculoDeLlegada"
	local arrival = ZONE.Arrival
	local floorY = TOP + StudFloor.PathRaise
	local center = world(arrival.X, floorY, arrival.Z)
	local pad = PartFactory.part(m, "Losa", {
		Size = Vector3.new(12, 0.6, 12),
		CFrame = CFrame.new(center + Vector3.new(0, 0.3, 0)),
		Color = SpawnConfig.PadColor,
		Material = SpawnConfig.PadMaterial,
		Solid = true,
	})
	for _, edge in {
		{ Vector3.new(0, 0.63, 5.6), Vector3.new(11.2, 0.06, 0.3) },
		{ Vector3.new(0, 0.63, -5.6), Vector3.new(11.2, 0.06, 0.3) },
		{ Vector3.new(5.6, 0.63, 0), Vector3.new(0.3, 0.06, 11.2) },
		{ Vector3.new(-5.6, 0.63, 0), Vector3.new(0.3, 0.06, 11.2) },
	} do
		PartFactory.part(m, "Runa", {
			Size = edge[2],
			CFrame = CFrame.new(center + edge[1]),
			Color = SpawnConfig.TrimColor,
			Material = Enum.Material.Neon,
			Solid = false,
		})
	end
	for _, side in { -1, 1 } do
		local base = center + Vector3.new(side * 8.5, 0, 0)
		studBlock(m, "Poste", Vector3.new(0.7, 4, 0.7), CFrame.new(base + Vector3.new(0, 2, 0)), RGB(104, 76, 52), true)
		local lantern = PartFactory.part(m, "Farol", {
			Size = Vector3.new(0.8, 0.9, 0.8),
			CFrame = CFrame.new(base + Vector3.new(-side * 0.9, 3.4, 0)),
			Color = SpawnConfig.LanternColor,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		local light = Instance.new("PointLight")
		light.Color = SpawnConfig.LightColor
		light.Range = 12
		light.Brightness = 1
		light.Shadows = false
		light.Parent = lantern
	end
	m.PrimaryPart = pad
	m.Parent = parent
end

-- Farola dorada
local function lamp(parent: Instance, pos: Vector3)
	local m = Instance.new("Model")
	m.Name = "Farola"
	studBlock(m, "Base", Vector3.new(1.6, 0.8, 1.6), CFrame.new(pos + Vector3.new(0, 0.4, 0)), MARBLE[2], true)
	studBlock(m, "Poste", Vector3.new(0.6, 7, 0.6), CFrame.new(pos + Vector3.new(0, 4.3, 0)), RGB(60, 60, 80), true)
	local glow = PartFactory.ball(m, "Luz", pos + Vector3.new(0, 8.4, 0), 1.6, RGB(255, 236, 170), Enum.Material.Neon, false)
	studBlock(m, "Tapa", Vector3.new(1.8, 0.4, 1.8), CFrame.new(pos + Vector3.new(0, 9.4, 0)), GOLD, false)
	local light = Instance.new("PointLight")
	light.Color = RGB(255, 226, 160)
	light.Range = 16
	light.Brightness = 1.1
	light.Shadows = false
	light.Parent = glow
	m.Parent = parent
end

-- Seto con flores (una fila de bloques verdes con flores encima)
local function hedge(parent: Instance, from: Vector3, to: Vector3, rng: Random)
	local m = Instance.new("Model")
	m.Name = "Seto"
	local dir = to - from
	local length = dir.Magnitude
	local cf = CFrame.lookAt((from + to) / 2, to)
	studBlock(m, "Seto", Vector3.new(2.4, 2.2, length), cf * CFrame.new(0, 1.1, 0), RGB(96, 176, 70), true)
	local count = math.floor(length / 2.2)
	for index = 1, count do
		local z = -length / 2 + (index - 0.5) * (length / count)
		local flower = PartFactory.part(m, "Flor", {
			Size = Vector3.new(0.8, 0.5, 0.8),
			CFrame = cf * CFrame.new(rng:NextNumber(-0.6, 0.6), 2.45, z),
			Color = FLOWERS[rng:NextInteger(1, #FLOWERS)],
			Material = Enum.Material.SmoothPlastic,
			Solid = false,
		})
		flower.CastShadow = false
	end
	m.Parent = parent
end

-- Arco de bienvenida dorado sobre un paso, con su cartel
local function arch(parent: Instance, center: Vector3, width: number, text: string)
	local m = Instance.new("Model")
	m.Name = "Arco"
	for _, side in { -1, 1 } do
		studBlock(m, "Pilar", Vector3.new(2.4, 12, 2.4), CFrame.new(center + Vector3.new(side * width / 2, 6, 0)), MARBLE[1], true)
		studBlock(m, "Remate", Vector3.new(3, 1, 3), CFrame.new(center + Vector3.new(side * width / 2, 12.5, 0)), GOLD, false)
	end
	studBlock(m, "Dintel", Vector3.new(width + 3, 2, 2.4), CFrame.new(center + Vector3.new(0, 13.6, 0)), GOLD, true)
	sign(m, center + Vector3.new(0, 17.5, 0), text, RGB(255, 236, 160), 24, 3.6, 180)
	m.Parent = parent
end

local function buildTown(parent: Instance)
	local folder = PartFactory.folder(parent, "Pueblo")
	buildFountain(folder)
	buildSpawnPad(folder)
	-- Los cuatro puestos, mirando al centro de la plaza (como en el Mundo 1)
	VillageService.buildStall(folder, "Rewards", v2(-36, -12), v2(0, -12), "Clases", "Classes", "🎭")
	VillageService.buildStall(folder, "Quests", v2(-36, 12), v2(0, 12), "Mejoras", "Skills", "⚡")
	VillageService.buildStall(folder, "Shop", v2(36, -12), v2(0, -12), "Tienda", "Shop", "🛒")
	VillageService.buildStall(folder, "LaserShop", v2(36, 12), v2(0, 12), "Armería", "Armory", "⚔️")
	VillageService.buildEvolutionMachine(folder, v2(-20, 38), v2(-12, 30), 1.6)
	-- Farolas en las esquinas de la plaza y a lo largo de la avenida
	for _, corner in { { -40, -24 }, { 40, -24 }, { -40, 24 }, { 40, 24 } } do
		lamp(folder, world(corner[1], TOP + StudFloor.PathRaise, corner[2]))
	end
	for z = 34, 70, 18 do
		for _, side in { -1, 1 } do
			lamp(folder, world(side * 16, TOP, z))
		end
	end
	arch(folder, world(0, TOP, 31), 28, "🌍 MUNDO 2 · PUEBLO CELESTIAL")
	arch(folder, world(0, TOP + StudFloor.PathRaise, -30), 34, "🌟 JARDÍN CELESTIAL")
	sign(folder, world(-50, 9, 0), "🔥❄️ Tierras Divididas\n<font size=\"18\">al norte, pasando el Jardín ⬆</font>", RGB(255, 210, 120), 16, 4, 120)
	arch(folder, world(0, TOP + StudFloor.PathRaise, -112), 30, "🔥 TIERRAS DIVIDIDAS ❄️")
end

-- Jardín Celestial: setos con flores alrededor de los huevos
local function buildGarden(parent: Instance, rng: Random)
	local folder = PartFactory.folder(parent, "Jardin")
	local y = TOP + StudFloor.PathRaise
	for _, side in { -1, 1 } do
		hedge(folder, world(side * 34, y, -88), world(side * 34, y, -40), rng)
	end
	-- El seto del fondo deja en medio el paso a las Tierras Divididas
	hedge(folder, world(-30, y, -90), world(-14, y, -90), rng)
	hedge(folder, world(14, y, -90), world(30, y, -90), rng)
	-- Macetas con flores entre los huevos
	for _, x in { -11, 11 } do
		local pos = world(x, y, -70)
		studBlock(folder, "Maceta", Vector3.new(3, 1.6, 3), CFrame.new(pos + Vector3.new(0, 0.8, 0)), RGB(196, 120, 80), true)
		for index = 1, 5 do
			local a = index / 5 * math.pi * 2
			PartFactory.part(folder, "Flor", {
				Size = Vector3.new(0.9, 0.6, 0.9),
				CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 0.8, 1.9, math.sin(a) * 0.8)),
				Color = FLOWERS[(index % #FLOWERS) + 1],
				Material = Enum.Material.SmoothPlastic,
				Solid = false,
			})
		end
	end
end

local function buildDecor(parent: Instance)
	local folder = PartFactory.folder(parent, "MapDetails")
	local keepOut = {
		{ ORIGIN.X, ORIGIN.Z + 96, 26 }, -- portal de vuelta
		{ ORIGIN.X - 20, ORIGIN.Z + 38, 8 }, -- Máquina de Evolución
	}
	local decor = StudWorld.newDecor(LAYOUT, "World2", keepOut)
	local rng = decor.Rng
	buildGarden(folder, rng)
	decor.wallRow(18, 9, 12, function(pos, yaw)
		StudWorld.buildBlockyTree(folder, pos, yaw, rng:NextNumber(0.95, 1.2), TREE_COLORS[rng:NextInteger(1, #TREE_COLORS)])
	end)
	decor.scatter(18, 6, math.huge, 10, function(pos, yaw)
		StudWorld.buildBlockyTree(folder, pos, yaw, rng:NextNumber(0.7, 0.95), TREE_COLORS[rng:NextInteger(1, #TREE_COLORS)])
	end)
	decor.scatter(30, 2, math.huge, 3, function(pos)
		local flower = PartFactory.part(folder, "Flor", {
			Size = Vector3.new(1, 0.7, 1),
			CFrame = CFrame.new(pos + Vector3.new(0, 0.35, 0)),
			Color = FLOWERS[rng:NextInteger(1, #FLOWERS)],
			Material = Enum.Material.SmoothPlastic,
			Solid = false,
		})
		flower.CastShadow = false
	end)
end

-- Sobre las terrazas: árboles de colores abajo y cristales arriba
local function buildTerraceDecor(parent: Instance, tops: { { Position: Vector3, Ring: number } })
	local folder = PartFactory.folder(parent, "TerraceDecor")
	local rng = Random.new(LAYOUT.DecorSeed + 7)
	for index, cell in tops do
		if cell.Ring <= 2 and index % 9 == 0 then
			StudWorld.buildBlockyTree(folder, cell.Position, rng:NextNumber(0, 360), rng:NextNumber(0.75, 1), TREE_COLORS[rng:NextInteger(1, #TREE_COLORS)])
		elseif cell.Ring >= 4 and index % 7 == 0 then
			local crystal = PartFactory.part(folder, "Cristal", {
				Size = Vector3.new(2.4, rng:NextNumber(5, 9), 2.4),
				CFrame = CFrame.new(cell.Position + Vector3.new(0, 3, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), math.rad(rng:NextNumber(-10, 10))),
				Color = if index % 2 == 0 then RGB(190, 140, 255) else RGB(120, 230, 255),
				Material = Enum.Material.Neon,
				Solid = false,
			})
			crystal.Transparency = 0.15
		end
	end
end

function World2Service.start()
	PartFactory.removeExisting(workspace, MODEL_NAME)
	buildFlatTerrain()

	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	StudWorld.buildFloor(model, LAYOUT)
	local tops = StudWorld.buildWalls(model, LAYOUT)
	buildTown(model)
	buildDecor(model)
	if tops then
		buildTerraceDecor(model, tops)
	end
	model.Parent = workspace
end

return World2Service
