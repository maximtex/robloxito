-- Tierras Divididas (Mundo 2, zona 1: ZoneConfig.Zones.DividedLands, distribución en
-- StudFloor.Zones.DividedLands), al norte del pueblo del Mundo 2. Un mapa partido en dos por
-- la línea X = Split.X:
-- - Oeste: volcán. Suelo y terrazas de la Caldera, árboles de brasas, obsidiana, pozas de lava,
--   piedras de brasa y chispas que suben.
-- - Este: glaciar. Suelo y terrazas de la Tundra, pinos nevados, cristales de hielo, montones
--   de nieve y nieve que cae.
-- - La Grieta: una raja que brilla naranja de un lado y azul del otro a lo largo de la línea.
-- - Llegada por el paso del sur con un arco mitad fuego y mitad hielo; a los lados, el Brasero
--   Eterno (oeste) y el Huevo del Equilibrio (este, lo pone EggStandService).
-- - En medio, la plaza del Altar del Equilibrio (el altar y su columna de luz los pone
--   WaveService: WaveConfig.Places.DividedLands) con dos obeliscos de fuego y dos de hielo.
-- - Al norte, la boca de la Grieta Elemental (la mazmorra: CaveConfig, CaveDungeon).
-- Los bichos de fuego viven en el oeste y los de hielo en el este (EnemyConfig). Solo decorativo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local WaveConfig = require(Shared.Config.WaveConfig)
local EggConfig = require(Shared.Config.EggConfig)
local CaveConfig = require(Shared.Config.CaveConfig)
local StudFloor = require(Shared.Util.StudFloor)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local StudWorld = require(script.Parent.Parent.Util.StudWorld)

local DividedLandsService = {}

local MODEL_NAME = "DividedLands"
local ZONE_ID = "DividedLands"
local CENTER_2D = ZoneConfig.Zones[ZONE_ID].Center
local ORIGIN = Vector3.new(GeneratorConfig.Position.X + CENTER_2D.X, 0, GeneratorConfig.Position.Z + CENTER_2D.Y)
local LAYOUT = StudFloor.Zones[ZONE_ID]
local SPLIT_X = LAYOUT.Split.X
local TOP = StudWorld.FloorTop
local RGB = Color3.fromRGB

-- Fuego
local LAVA = RGB(255, 110, 30)
local LAVA_BRIGHT = RGB(255, 190, 70)
local BASALT = RGB(62, 46, 44)
local OBSIDIAN = { RGB(40, 30, 38), RGB(58, 42, 50), RGB(30, 24, 30) }
local EMBER_TREE = { Trunk = RGB(74, 52, 46), LeafLight = RGB(240, 128, 40), LeafDark = RGB(214, 84, 32) }
-- Hielo
local SNOW = RGB(244, 248, 255)
local SNOW_SHADE = RGB(222, 232, 246)
local ICE = { RGB(150, 210, 245), RGB(190, 232, 255), RGB(120, 186, 236) }
local FROST = RGB(110, 210, 255)
local PINE = { Trunk = RGB(112, 78, 54), Light = RGB(74, 146, 100), Dark = RGB(54, 120, 84) }

local function world(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

local function isFire(x: number): boolean
	return x < SPLIT_X
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

local function glow(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, shape: Enum.PartType?): Part
	local part = PartFactory.part(parent, name, {
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.Neon,
		Shape = shape,
		Solid = false,
		CastShadow = false,
	})
	return part
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local point = Instance.new("PointLight")
	point.Color = color
	point.Range = range
	point.Brightness = brightness
	point.Shadows = false
	point.Parent = parent
end

local function flames(parent: Instance, color: Color3, size: number)
	local fire = Instance.new("Fire")
	fire.Size = size
	fire.Heat = size * 1.5
	fire.Color = color
	fire.SecondaryColor = Color3.new(1, 1, 1):Lerp(color, 0.4)
	fire.Parent = parent
end

local function sign(parent: Instance, position: Vector3, text: string, color: Color3, width: number, height: number)
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
	billboard.MaxDistance = 200
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.RichText = true
	label.TextColor3 = color
	label.TextStrokeColor3 = RGB(30, 18, 48)
	label.TextStrokeTransparency = 0
	label.Text = text
	label.Parent = billboard
	billboard.Parent = anchor
end

-- Terreno por debajo del suelo: basalto al oeste y nieve al este
local function buildFlatTerrain()
	local z0, z1 = LAYOUT.MinZ - 60, LAYOUT.MaxZ + 40
	StudWorld.fillTerrainBelow(LAYOUT.MinX - 60, SPLIT_X, z0, z1, Enum.Material.Basalt)
	StudWorld.fillTerrainBelow(SPLIT_X, LAYOUT.MaxX + 60, z0, z1, Enum.Material.Snow)
end

-- Fuego -------------------------------------------------------------------------------------

-- Obsidiana: tres bloques oscuros inclinados con una veta de lava
local function obsidian(parent: Instance, pos: Vector3, yawDeg: number, scale: number)
	local m = Instance.new("Model")
	m.Name = "Obsidiana"
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	for index, spec in {
		{ Offset = Vector3.new(0, 3.2, 0), Size = Vector3.new(2.6, 6.4, 2.6), Tilt = CFrame.Angles(math.rad(6), 0, math.rad(-7)) },
		{ Offset = Vector3.new(-1.9, 2.0, 1.0), Size = Vector3.new(1.9, 4.0, 1.9), Tilt = CFrame.Angles(math.rad(-12), 0, math.rad(20)) },
		{ Offset = Vector3.new(1.8, 2.2, -0.9), Size = Vector3.new(2.0, 4.4, 2.0), Tilt = CFrame.Angles(math.rad(14), 0, math.rad(-18)) },
	} do
		PartFactory.part(m, "Bloque" .. index, {
			Size = spec.Size * scale,
			CFrame = cf * CFrame.new(spec.Offset * scale) * spec.Tilt * CFrame.Angles(0, math.rad(45), 0),
			Color = OBSIDIAN[index],
			Material = Enum.Material.SmoothPlastic,
			Solid = index == 1,
		})
	end
	glow(m, "Veta", Vector3.new(0.5, 5.2, 0.5) * scale, cf * CFrame.new(Vector3.new(0.9, 3.0, -0.9) * scale) * CFrame.Angles(math.rad(6), 0, math.rad(-7)), LAVA_BRIGHT)
	m.Parent = parent
end

-- Poza de lava cuadrada con su borde de basalto
local function lavaPool(parent: Instance, center: Vector3, size: number)
	local m = Instance.new("Model")
	m.Name = "PozaDeLava"
	local lava = glow(m, "Lava", Vector3.new(size - 2, 0.2, size - 2), CFrame.new(center.X, TOP - 0.04, center.Z), LAVA)
	light(lava, LAVA, size + 6, 1)
	for _, side in { -1, 1 } do
		studBlock(m, "Borde", Vector3.new(size, 0.6, 1), CFrame.new(center.X, TOP + 0.1, center.Z + side * (size - 1) / 2), BASALT, false)
		studBlock(m, "Borde", Vector3.new(1, 0.6, size - 2), CFrame.new(center.X + side * (size - 1) / 2, TOP + 0.1, center.Z), BASALT, false)
	end
	m.Parent = parent
end

-- Piedra de brasa: bloque de basalto con un brillo de lava encima
local function emberRock(parent: Instance, pos: Vector3, yawDeg: number)
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	studBlock(parent, "PiedraDeBrasa", Vector3.new(2.6, 1.4, 2.2), cf * CFrame.new(0, 0.7, 0), BASALT, false)
	glow(parent, "Brasa", Vector3.new(1.2, 0.5, 1.0), cf * CFrame.new(0.3, 1.5, 0.1), LAVA_BRIGHT)
end

-- Hielo -------------------------------------------------------------------------------------

-- Pino nevado de bloques: tronco y tres pisos de copa con nieve encima
local function snowyPine(parent: Instance, pos: Vector3, yawDeg: number, scale: number)
	local tree = Instance.new("Model")
	tree.Name = "PinoNevado"
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local trunk = studBlock(tree, "Tronco", Vector3.new(1.6, 4, 1.6) * scale, cf * CFrame.new(0, 2 * scale, 0), PINE.Trunk, true)
	for tier = 1, 3 do
		local width = (8.4 - tier * 2) * scale
		local y = (3 + tier * 2.6) * scale
		studBlock(tree, "Copa" .. tier, Vector3.new(width, 2.6 * scale, width), cf * CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(tier * 15), 0), if tier % 2 == 1 then PINE.Dark else PINE.Light, false)
		studBlock(tree, "Nieve" .. tier, Vector3.new(width * 0.82, 0.6 * scale, width * 0.82), cf * CFrame.new(0, y + 1.6 * scale, 0) * CFrame.Angles(0, math.rad(tier * 15), 0), SNOW, false)
	end
	studBlock(tree, "Punta", Vector3.new(1.4, 1.6, 1.4) * scale, cf * CFrame.new(0, 12.4 * scale, 0), SNOW, false)
	tree.PrimaryPart = trunk
	tree.Parent = parent
end

-- Cristales de hielo: prismas translúcidos inclinados
local function iceCluster(parent: Instance, pos: Vector3, yawDeg: number, scale: number)
	local m = Instance.new("Model")
	m.Name = "CristalesDeHielo"
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	for index, spec in {
		{ Offset = Vector3.new(0, 3.4, 0), Size = Vector3.new(2.2, 6.8, 2.2), Tilt = CFrame.Angles(math.rad(5), 0, math.rad(-6)) },
		{ Offset = Vector3.new(-1.8, 2.1, 1.0), Size = Vector3.new(1.6, 4.2, 1.6), Tilt = CFrame.Angles(math.rad(-14), 0, math.rad(22)) },
		{ Offset = Vector3.new(1.7, 2.3, -0.9), Size = Vector3.new(1.7, 4.6, 1.7), Tilt = CFrame.Angles(math.rad(16), 0, math.rad(-20)) },
	} do
		local crystal = PartFactory.part(m, "Cristal" .. index, {
			Size = spec.Size * scale,
			CFrame = cf * CFrame.new(spec.Offset * scale) * spec.Tilt * CFrame.Angles(0, math.rad(45), 0),
			Color = ICE[(index - 1) % #ICE + 1],
			Material = Enum.Material.Glass,
			Solid = index == 1,
		})
		crystal.Transparency = 0.25
	end
	m.Parent = parent
end

-- Montón de nieve de bloques
local function snowMound(parent: Instance, pos: Vector3, yawDeg: number, scale: number)
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	studBlock(parent, "NieveBase", Vector3.new(5, 1.4, 4) * scale, cf * CFrame.new(0, 0.7 * scale, 0), SNOW_SHADE, false)
	studBlock(parent, "NieveMedio", Vector3.new(3.4, 1.2, 2.8) * scale, cf * CFrame.new(0.4 * scale, 2 * scale, -0.2 * scale), SNOW, false)
	studBlock(parent, "NieveArriba", Vector3.new(1.8, 0.9, 1.6) * scale, cf * CFrame.new(0.2 * scale, 3 * scale, 0), SNOW, false)
end

-- Lugares ---------------------------------------------------------------------------------

-- Arco de la llegada: pilar de basalto con lava al oeste, de hielo al este, y el nombre
local function buildEntranceArch(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "ArcoDeLlegada"
	local z = LAYOUT.MaxZ - 6
	local half = 22
	for _, side in { -1, 1 } do
		local fire = side < 0
		local x = ORIGIN.X + side * half
		local stone = if fire then BASALT else RGB(180, 214, 240)
		for row = 1, 5 do
			studBlock(m, "Pilar" .. row, Vector3.new(4, 3.2, 4), CFrame.new(x, TOP + (row - 0.5) * 3.2, z), if row % 2 == 0 then stone:Lerp(Color3.new(0, 0, 0), 0.12) else stone, true)
		end
		local band = glow(m, "Runa", Vector3.new(0.4, 13, 1.2), CFrame.new(x - side * 2.1, TOP + 8, z), if fire then LAVA else FROST)
		light(band, band.Color, 14, 1.2)
		local top = glow(m, "Llama", Vector3.one * 2.2, CFrame.new(x, TOP + 17.4, z), if fire then LAVA_BRIGHT else FROST, Enum.PartType.Ball)
		flames(top, if fire then LAVA else FROST, 6)
	end
	studBlock(m, "DintelFuego", Vector3.new(half + 2, 2.4, 4.4), CFrame.new(ORIGIN.X - half / 2, TOP + 17, z), BASALT, true)
	studBlock(m, "DintelHielo", Vector3.new(half + 2, 2.4, 4.4), CFrame.new(ORIGIN.X + half / 2, TOP + 17, z), RGB(180, 214, 240), true)
	sign(m, Vector3.new(ORIGIN.X, TOP + 21.5, z), '<font color="#FF9A3C">🔥 TIERRAS</font> <font color="#8FDBFF">DIVIDIDAS ❄️</font>', Color3.new(1, 1, 1), 30, 4.2)
	m.Parent = parent
end

-- Brasero Eterno (plazoleta oeste): cuenco de piedra enorme con lava y fuego
local function buildEternalBrazier(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "BraseroEterno"
	local center = Vector3.new(ORIGIN.X - 44, TOP + StudFloor.PathRaise, LAYOUT.MaxZ - 24)
	studBlock(m, "Base", Vector3.new(7, 2, 7), CFrame.new(center + Vector3.new(0, 1, 0)), BASALT, true)
	studBlock(m, "Pie", Vector3.new(3.6, 4, 3.6), CFrame.new(center + Vector3.new(0, 4, 0)), RGB(84, 62, 58), true)
	studBlock(m, "Cuenco", Vector3.new(8, 2.4, 8), CFrame.new(center + Vector3.new(0, 7.2, 0)), BASALT, true)
	local core = glow(m, "Lava", Vector3.new(6.4, 0.6, 6.4), CFrame.new(center + Vector3.new(0, 8.5, 0)), LAVA)
	flames(core, LAVA, 14)
	light(core, LAVA, 34, 2.5)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Chispas"
	sparks.Color = ColorSequence.new(LAVA_BRIGHT, LAVA)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.35, 0)
	sparks.Lifetime = NumberRange.new(1.2, 2.2)
	sparks.Rate = 18
	sparks.Speed = NumberRange.new(4, 9)
	sparks.SpreadAngle = Vector2.new(25, 25)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Parent = core
	sign(m, center + Vector3.new(0, 16, 0), "🔥 Brasero Eterno", LAVA_BRIGHT, 10, 2.2)
	m.Parent = parent
end

-- Plaza del altar: dos obeliscos de obsidiana con fuego al oeste y dos de hielo al este
local function buildAltarPlaza(parent: Instance)
	local folder = PartFactory.folder(parent, "PlazaDelAltar")
	local place = WaveConfig.Places[ZONE_ID]
	local center = if place then world(place.Offset.X, 0, place.Offset.Y) else ORIGIN
	for _, corner in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
		local fire = corner[1] < 0
		local base = Vector3.new(center.X + corner[1] * 30, TOP + StudFloor.PathRaise, center.Z + corner[2] * 30)
		local stone = if fire then OBSIDIAN[2] else RGB(170, 210, 240)
		local material = if fire then Enum.Material.SmoothPlastic else Enum.Material.Glass
		local pillar = PartFactory.part(folder, "Obelisco", {
			Size = Vector3.new(3.2, 12, 3.2),
			CFrame = CFrame.new(base + Vector3.new(0, 6, 0)) * CFrame.Angles(0, math.rad(45), 0),
			Color = stone,
			Material = material,
			Solid = true,
		})
		if not fire then
			pillar.Transparency = 0.15
		end
		local tip = glow(folder, "Punta", Vector3.new(2, 3, 2), CFrame.new(base + Vector3.new(0, 13.5, 0)) * CFrame.Angles(0, math.rad(45), 0), if fire then LAVA_BRIGHT else FROST)
		light(tip, tip.Color, 22, 1.6)
		if fire then
			flames(tip, LAVA, 5)
		end
		glow(folder, "Veta", Vector3.new(0.4, 9, 3.3), CFrame.new(base + Vector3.new(0, 6, 0)) * CFrame.Angles(0, math.rad(45), 0), if fire then LAVA else FROST)
	end
	sign(folder, center + Vector3.new(0, TOP + 24, -34), '<font color="#FF9A3C">⚖️ ALTAR</font> <font color="#8FDBFF">DEL EQUILIBRIO</font>', Color3.new(1, 1, 1), 26, 3.6)
end

-- La Grieta: una raja que brilla a lo largo de la línea que parte el mapa (naranja del lado del
-- fuego y azul del lado del hielo), de punta a punta: también cruza la avenida y la plaza
-- (encima de las losas). Tramos de 4 desde un borde de bloque: ninguno queda a caballo entre
-- el damero y un camino (que está más alto).
local function buildRift(parent: Instance)
	local folder = PartFactory.folder(parent, "Grieta")
	local rng = Random.new(LAYOUT.DecorSeed + 3)
	local step = 4
	local x = SPLIT_X
	for z = LAYOUT.MinZ + 4, LAYOUT.MaxZ + 32, step do -- (+32: el cuello de la entrada)
		local nextX = SPLIT_X + rng:NextNumber(-1.2, 1.2)
		local midZ = z + step / 2
		if StudFloor.onFloor(LAYOUT, SPLIT_X, midZ, 2) then
			local y = TOP + StudFloor.raiseAt(SPLIT_X, midZ) + 0.03
			local from = Vector3.new(x, y, z)
			local to = Vector3.new(nextX, y, z + step)
			local frame = CFrame.lookAt((from + to) / 2, to)
			local length = (to - from).Magnitude + 0.2
			glow(folder, "RajaFuego", Vector3.new(0.7, 0.08, length), frame * CFrame.new(-0.45, 0, 0), LAVA)
			glow(folder, "RajaHielo", Vector3.new(0.7, 0.08, length), frame * CFrame.new(0.45, 0, 0), FROST)
			local core = glow(folder, "RajaCentro", Vector3.new(0.35, 0.1, length), frame, Color3.new(1, 1, 1))
			if (z // step) % 6 == 0 then
				light(core, Color3.fromRGB(230, 200, 255), 10, 0.8)
			end
		end
		x = nextX
	end
end

-- Tiempo: chispas que suben sobre el volcán y nieve que cae sobre el glaciar
local function buildWeather(parent: Instance)
	local depth = LAYOUT.MaxZ - LAYOUT.MinZ + 20
	local midZ = (LAYOUT.MinZ + LAYOUT.MaxZ) / 2
	local width = SPLIT_X - LAYOUT.MinX + 20
	local embersAt = PartFactory.part(parent, "Ascuas", {
		Size = Vector3.new(width, 1, depth),
		CFrame = CFrame.new((LAYOUT.MinX - 20 + SPLIT_X) / 2, TOP + 1, midZ),
		Color = LAVA,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	embersAt.Transparency = 1
	embersAt.CastShadow = false
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Ascuas"
	embers.Color = ColorSequence.new(LAVA_BRIGHT, LAVA)
	embers.LightEmission = 1
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	embers.Lifetime = NumberRange.new(5, 8)
	embers.Rate = 70
	embers.Speed = NumberRange.new(2, 4)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.SpreadAngle = Vector2.new(20, 20)
	embers.Acceleration = Vector3.new(0.6, 0.4, 0)
	embers.Parent = embersAt

	local snowAt = PartFactory.part(parent, "Nevada", {
		Size = Vector3.new(LAYOUT.MaxX - SPLIT_X + 20, 1, depth),
		CFrame = CFrame.new((SPLIT_X + LAYOUT.MaxX + 20) / 2, 55, midZ),
		Color = SNOW,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	snowAt.Transparency = 1
	snowAt.CastShadow = false
	local snow = Instance.new("ParticleEmitter")
	snow.Name = "Copos"
	snow.Color = ColorSequence.new(Color3.new(1, 1, 1))
	snow.LightEmission = 0.3
	snow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.25) })
	snow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.85, 0.3), NumberSequenceKeypoint.new(1, 1) })
	snow.Lifetime = NumberRange.new(9, 12)
	snow.Rate = 90
	snow.Speed = NumberRange.new(4, 6)
	snow.EmissionDirection = Enum.NormalId.Bottom
	snow.SpreadAngle = Vector2.new(15, 15)
	snow.Acceleration = Vector3.new(0.8, 0, 0.4)
	snow.RotSpeed = NumberRange.new(-40, 40)
	snow.Parent = snowAt
end

-- Decoración repartida: lo de fuego en el oeste y lo de hielo en el este
local function buildDecor(parent: Instance)
	local folder = PartFactory.folder(parent, "MapDetails")
	local keepOut = {
		{ ORIGIN.X - 44, LAYOUT.MaxZ - 24, 12 }, -- Brasero Eterno
	}
	for _, egg in EggConfig.Eggs do
		if egg.Zone == ZONE_ID and egg.StandOffset then
			table.insert(keepOut, { ORIGIN.X + egg.StandOffset.X, ORIGIN.Z + egg.StandOffset.Y, 12 })
		end
	end
	-- La boca de la Grieta Elemental y su entrada monumental
	for _, cave in CaveConfig.Caves do
		local mound = cave.Zone == ZONE_ID and cave.Entrance.Mound
		if mound then
			table.insert(keepOut, { mound.Front.X + mound.Depth / 2, mound.Front.Z, 30 })
			table.insert(keepOut, { mound.Front.X - 24, mound.Front.Z, 16 })
		end
	end
	local decor = StudWorld.newDecor(LAYOUT, ZONE_ID, keepOut)
	local rng = decor.Rng
	decor.wallRow(20, 9, 12, function(pos, yaw)
		if isFire(pos.X) then
			StudWorld.buildBlockyTree(folder, pos, yaw, rng:NextNumber(0.95, 1.2), EMBER_TREE)
		else
			snowyPine(folder, pos, yaw, rng:NextNumber(0.9, 1.15))
		end
	end)
	decor.scatter(24, 4, math.huge, 9, function(pos, yaw)
		if isFire(pos.X) then
			obsidian(folder, pos, yaw, rng:NextNumber(0.8, 1.3))
		else
			iceCluster(folder, pos, yaw, rng:NextNumber(0.8, 1.3))
		end
	end)
	decor.scatter(8, 6, math.huge, 9, function(pos, yaw)
		if isFire(pos.X) then
			lavaPool(folder, pos, 9)
		else
			snowMound(folder, pos, yaw, rng:NextNumber(0.9, 1.3))
		end
	end)
	decor.scatter(30, 2, math.huge, 4, function(pos, yaw)
		if isFire(pos.X) then
			emberRock(folder, pos, yaw)
		else
			snowMound(folder, pos, yaw, rng:NextNumber(0.4, 0.6))
		end
	end)
end

-- Sobre las terrazas: árboles de brasas y obsidiana al oeste; pinos y cristales al este
local function buildTerraceDecor(parent: Instance, tops: { { Position: Vector3, Ring: number } })
	local folder = PartFactory.folder(parent, "TerraceDecor")
	local rng = Random.new(LAYOUT.DecorSeed + 7)
	for index, cell in tops do
		local p = cell.Position
		local fire = isFire(p.X)
		if cell.Ring <= 2 and index % 9 == 0 then
			if fire then
				StudWorld.buildBlockyTree(folder, p, rng:NextNumber(0, 360), rng:NextNumber(0.75, 0.95), EMBER_TREE)
			else
				snowyPine(folder, p, rng:NextNumber(0, 360), rng:NextNumber(0.8, 1.05))
			end
		elseif cell.Ring >= 4 and index % 6 == 0 then
			if fire then
				obsidian(folder, p, rng:NextNumber(0, 360), rng:NextNumber(1.0, 1.6))
			else
				iceCluster(folder, p, rng:NextNumber(0, 360), rng:NextNumber(1.2, 1.9))
			end
		end
	end
end

function DividedLandsService.start()
	PartFactory.removeExisting(workspace, MODEL_NAME)
	buildFlatTerrain()

	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	StudWorld.buildFloor(model, LAYOUT)
	local tops = StudWorld.buildWalls(model, LAYOUT)
	buildEntranceArch(model)
	buildEternalBrazier(model)
	buildAltarPlaza(model)
	buildRift(model)
	buildWeather(model)
	buildDecor(model)
	if tops then
		buildTerraceDecor(model, tops)
	end
	model.Parent = workspace
end

return DividedLandsService
