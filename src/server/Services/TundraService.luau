-- Construye la Tundra Helada (Zona 4), pegada tras la Caldera de Brasas, con el mismo estilo de
-- bloques que el resto del mapa (StudWorld; la distribución está en StudFloor.Zones.FrozenTundra):
-- - Suelo de nieve en damero suave con caminos de hielo con studs y su borde azul.
-- - Montañas nevadas en escalones alrededor (con pinos nevados abajo y picos de hielo arriba)
--   y el muro sur con el paso del portal a la Fortaleza Goblin.
-- - Lago helado al oeste, la plaza de los Huevos de Hielo (EggConfig), el Mirador del Gólem al
--   fondo (una estatua de hielo del Gólem: él despierta en las oleadas de la Gruta Glacial),
--   pinos nevados, cristales de hielo, montones de nieve, iglús, farolillos de hielo y nieve
--   que cae. Solo decorativo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local StudFloor = require(Shared.Util.StudFloor)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local StudWorld = require(script.Parent.Parent.Util.StudWorld)

local TundraService = {}

local MODEL_NAME = "FrozenTundra"
local CENTER_2D = ZoneConfig.Zones.FrozenTundra.Center
local ORIGIN = Vector3.new(GeneratorConfig.Position.X + CENTER_2D.X, 0, GeneratorConfig.Position.Z + CENTER_2D.Y)
local TUNDRA = StudFloor.Zones.FrozenTundra
local RGB = Color3.fromRGB

local SNOW = RGB(244, 248, 255)
local SNOW_SHADE = RGB(222, 232, 246)
local ICE = { RGB(150, 210, 245), RGB(190, 232, 255), RGB(120, 186, 236) }
local ROCK = RGB(116, 128, 150)
local PINE = { Trunk = RGB(112, 78, 54), Light = RGB(74, 146, 100), Dark = RGB(54, 120, 84) }
local LANTERN = RGB(140, 220, 255)

-- Relativo al centro de la zona (como el resto de configuraciones)
local LAKE = { Center = Vector2.new(-46, 8), Size = 30 }
local STATUE = Vector2.new(0, 95) -- Mirador del Gólem (EnemyConfig.Zones.FrozenTundra.Boss.Arena)

local function world(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
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

-- Nieve por debajo del suelo, desde el muro sur de la Caldera hasta el fondo de la Tundra
local function buildFlatTerrain()
	StudWorld.fillTerrainBelow(-220, 220, TUNDRA.MinZ, ORIGIN.Z + 200, Enum.Material.Snow)
end

-- Pino nevado de bloques: tronco y tres pisos de copa, cada uno con su capa de nieve encima
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

-- Cristales de hielo: tres o cuatro prismas translúcidos inclinados
local function iceCluster(parent: Instance, pos: Vector3, yawDeg: number, scale: number)
	local m = Instance.new("Model")
	m.Name = "CristalesDeHielo"
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	for index, spec in {
		{ Offset = Vector3.new(0, 3.4, 0), Size = Vector3.new(2.2, 6.8, 2.2), Tilt = CFrame.Angles(math.rad(5), 0, math.rad(-6)) },
		{ Offset = Vector3.new(-1.8, 2.1, 1.0), Size = Vector3.new(1.6, 4.2, 1.6), Tilt = CFrame.Angles(math.rad(-14), 0, math.rad(22)) },
		{ Offset = Vector3.new(1.7, 2.3, -0.9), Size = Vector3.new(1.7, 4.6, 1.7), Tilt = CFrame.Angles(math.rad(16), 0, math.rad(-20)) },
		{ Offset = Vector3.new(0.4, 1.2, 1.8), Size = Vector3.new(1.1, 2.4, 1.1), Tilt = CFrame.Angles(math.rad(-24), 0, math.rad(-8)) },
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

-- Montón de nieve de bloques con studs
local function snowMound(parent: Instance, pos: Vector3, yawDeg: number, scale: number)
	local m = Instance.new("Model")
	m.Name = "MontonDeNieve"
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	studBlock(m, "Base", Vector3.new(5, 1.4, 4) * scale, cf * CFrame.new(0, 0.7 * scale, 0), SNOW_SHADE, false)
	studBlock(m, "Medio", Vector3.new(3.4, 1.2, 2.8) * scale, cf * CFrame.new(0.4 * scale, 2 * scale, -0.2 * scale), SNOW, false)
	studBlock(m, "Arriba", Vector3.new(1.8, 0.9, 1.6) * scale, cf * CFrame.new(0.2 * scale, 3 * scale, 0), SNOW, false)
	m.Parent = parent
end

-- Iglú: cúpula de nieve con su túnel de entrada y la puerta oscura
local function igloo(parent: Instance, pos: Vector3, yawDeg: number)
	local m = Instance.new("Model")
	m.Name = "Iglu"
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local dome = PartFactory.ellipsoid(m, "Cupula", cf * CFrame.new(0, 0, 0), Vector3.new(11, 10, 11), SNOW, Enum.Material.SmoothPlastic)
	dome.CastShadow = true
	-- Lo que choca: un cilindro por dentro de la cúpula (la malla de esfera choca como una caja)
	local inner = PartFactory.verticalCylinder(m, "Choque", (cf * CFrame.new(0, 2, 0)).Position, 4, 8.6, SNOW, Enum.Material.SmoothPlastic, true)
	inner.Transparency = 1
	inner.CastShadow = false
	-- Juntas de los bloques de hielo: aros finos alrededor de la cúpula
	for ring = 1, 2 do
		local y = ring * 1.6
		local r = math.sqrt(math.max(0, 1 - (y / 5) ^ 2)) * 5.5 + 0.03
		local seam = PartFactory.verticalCylinder(m, "Junta", (cf * CFrame.new(0, y, 0)).Position, 0.12, r * 2, SNOW_SHADE, Enum.Material.SmoothPlastic, false)
		seam.CastShadow = false
	end
	studBlock(m, "Tunel", Vector3.new(4, 3.6, 4), cf * CFrame.new(0, 1.8, -5.2), SNOW, true)
	PartFactory.part(m, "Puerta", {
		Size = Vector3.new(2.2, 2.6, 0.2),
		CFrame = cf * CFrame.new(0, 1.3, -7.25),
		Color = RGB(44, 56, 80),
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	m.Parent = parent
end

-- Farolillo de hielo: poste de madera con un cubo de hielo que brilla
local function iceLantern(parent: Instance, pos: Vector3)
	local m = Instance.new("Model")
	m.Name = "FarolDeHielo"
	studBlock(m, "Poste", Vector3.new(0.8, 5, 0.8), CFrame.new(pos + Vector3.new(0, 2.5, 0)), PINE.Trunk, true)
	studBlock(m, "Tejadillo", Vector3.new(1.8, 0.4, 1.8), CFrame.new(pos + Vector3.new(0, 6.7, 0)), SNOW, false)
	local glow = PartFactory.part(m, "Luz", {
		Size = Vector3.new(1.3, 1.3, 1.3),
		CFrame = CFrame.new(pos + Vector3.new(0, 5.8, 0)) * CFrame.Angles(0, math.rad(45), 0),
		Color = LANTERN,
		Material = Enum.Material.Neon,
		Solid = false,
	})
	local light = Instance.new("PointLight")
	light.Color = LANTERN
	light.Range = 14
	light.Brightness = 1.1
	light.Shadows = false
	light.Parent = glow
	m.Parent = parent
end

-- Lago helado: una losa de hielo (se puede andar encima) con su borde y rocas nevadas
local function buildFrozenLake(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "LagoHelado"
	local center = world(LAKE.Center.X, 0, LAKE.Center.Y)
	local top = StudWorld.FloorTop
	local size = LAKE.Size
	local border = StudFloor.BorderWidth
	local ice = PartFactory.part(m, "Hielo", {
		Size = Vector3.new(size - 2 * border, 0.3, size - 2 * border),
		CFrame = CFrame.new(center.X, top - 0.02, center.Z),
		Color = RGB(176, 222, 250),
		Material = Enum.Material.Glass,
		Solid = true,
	})
	ice.Transparency = 0.15
	ice.Reflectance = 0.15
	-- Grietas del hielo
	for index = 1, 6 do
		local a = index / 6 * math.pi * 2
		PartFactory.part(m, "Grieta", {
			Size = Vector3.new(0.25, 0.05, 6 + (index % 3) * 2),
			CFrame = CFrame.new(center.X + math.cos(a) * 5, top + 0.15, center.Z + math.sin(a) * 5) * CFrame.Angles(0, a + 0.4, 0),
			Color = RGB(236, 248, 255),
			Material = Enum.Material.SmoothPlastic,
			Solid = false,
		})
	end
	for _, side in { -1, 1 } do
		PartFactory.part(m, "Borde", {
			Size = Vector3.new(size, 0.3, border),
			CFrame = CFrame.new(center.X, top - 0.02, center.Z + side * (size - border) / 2),
			Color = TUNDRA.Colors.Border,
			Material = Enum.Material.Plastic,
			Solid = true,
		})
		PartFactory.part(m, "Borde", {
			Size = Vector3.new(border, 0.3, size - 2 * border),
			CFrame = CFrame.new(center.X + side * (size - border) / 2, top - 0.02, center.Z),
			Color = TUNDRA.Colors.Border,
			Material = Enum.Material.Plastic,
			Solid = true,
		})
	end
	-- Rocas con nieve en las esquinas y un agujero de pesca con su caña
	for index, spec in { { X = -1, Z = -1, H = 4 }, { X = 1, Z = -1, H = 2.6 }, { X = -1, Z = 1, H = 3 }, { X = 1, Z = 1, H = 4.6 } } do
		local pos = center + Vector3.new(spec.X * (size / 2 + 1.5), 0, spec.Z * (size / 2 + 1.5))
		local cf = CFrame.new(pos.X, top + spec.H / 2, pos.Z) * CFrame.Angles(0, math.rad(index * 23), 0)
		studBlock(m, "Roca" .. index, Vector3.new(5, spec.H, 5), cf, ROCK, true)
		studBlock(m, "NieveRoca" .. index, Vector3.new(4.4, 0.6, 4.4), cf * CFrame.new(0, spec.H / 2 + 0.3, 0), SNOW, false)
	end
	local hole = PartFactory.verticalCylinder(m, "Agujero", Vector3.new(center.X + 6, top + 0.16, center.Z - 4), 0.05, 3, RGB(40, 90, 150), Enum.Material.SmoothPlastic, false)
	hole.CastShadow = false
	PartFactory.segment(m, "Cana", Vector3.new(center.X + 8, top + 0.2, center.Z - 3), Vector3.new(center.X + 6.2, top + 4.5, center.Z - 4), 0.18, PINE.Trunk, Enum.Material.Wood, false)
	m.Parent = parent
end

-- Estatua de hielo del Gólem en el Mirador: un coloso congelado sobre su pedestal, con el cartel
local function buildGolemStatue(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "EstatuaDelGolem"
	local base = world(STATUE.X, StudWorld.FloorTop + StudFloor.PathRaise, STATUE.Y)
	local cf = CFrame.lookAt(base, base + Vector3.new(0, 0, -1))
	studBlock(m, "Pedestal", Vector3.new(14, 2.4, 14), cf * CFrame.new(0, 1.2, 0), ROCK, true)
	studBlock(m, "Pedestal2", Vector3.new(11, 1.4, 11), cf * CFrame.new(0, 3.1, 0), SNOW_SHADE, true)
	local function ice(name: string, size: Vector3, offset: CFrame, color: Color3)
		local p = PartFactory.part(m, name, {
			Size = size,
			CFrame = cf * CFrame.new(0, 3.8, 0) * offset,
			Color = color,
			Material = Enum.Material.Glass,
			Solid = true,
		})
		p.Transparency = 0.2
		return p
	end
	ice("Torso", Vector3.new(7, 8, 5), CFrame.new(0, 8, 0), ICE[1])
	ice("Cabeza", Vector3.new(3, 2.4, 2.6), CFrame.new(0, 13.2, -0.4), ICE[2])
	for side = -1, 1, 2 do
		ice("Pierna" .. side, Vector3.new(2.2, 3.8, 2.2), CFrame.new(side * 1.6, 1.9, 0), ICE[3])
		ice("Hombro" .. side, Vector3.new(3, 3, 3), CFrame.new(side * 4.6, 10.5, 0), ICE[2])
		-- Brazos en alto, como si rugiera
		ice("Brazo" .. side, Vector3.new(2, 6.5, 2), CFrame.new(side * 5.4, 13.6, -0.6) * CFrame.Angles(math.rad(-12), 0, math.rad(side * -18)), ICE[1])
		ice("Puno" .. side, Vector3.new(3, 3, 3), CFrame.new(side * 6.4, 17, -1.2), ICE[3])
		local eye = PartFactory.part(m, "Ojo" .. side, {
			Size = Vector3.new(0.6, 0.6, 0.2),
			CFrame = cf * CFrame.new(side * 0.8, 3.8 + 13.4, -1.75),
			Color = RGB(230, 250, 255),
			Material = Enum.Material.Neon,
			Solid = false,
		})
		eye.CastShadow = false
	end
	for index = 1, 5 do
		local a = index / 5 * math.pi - math.pi / 2
		local spike = PartFactory.part(m, "Corona" .. index, {
			Size = Vector3.new(0.9, 2.6, 0.9),
			CFrame = cf * CFrame.new(math.sin(a) * 1.3, 3.8 + 15.4, -0.4) * CFrame.Angles(0, 0, -math.sin(a) * 0.4) * CFrame.Angles(0, math.rad(45), 0),
			Color = RGB(120, 230, 255),
			Material = Enum.Material.Neon,
			Solid = false,
		})
		spike.Transparency = 0.2
	end
	local core = PartFactory.ball(m, "Nucleo", (cf * CFrame.new(0, 3.8 + 8.5, -2.6)).Position, 1.8, RGB(120, 230, 255), Enum.Material.Neon, false)
	local light = Instance.new("PointLight")
	light.Color = RGB(140, 220, 255)
	light.Range = 26
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = core

	-- Cartel delante del pedestal
	local anchor = PartFactory.part(m, "Cartel", {
		Size = Vector3.one * 0.2,
		CFrame = cf * CFrame.new(0, 26, 0),
		Color = SNOW,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	anchor.Transparency = 1
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(22, 4.4)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 160
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.RichText = true
	label.TextColor3 = RGB(200, 240, 255)
	label.Text = "❄️ Gólem de Hielo\n<font size=\"16\">Despierta en las oleadas de la Gruta Glacial</font>"
	label.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = RGB(20, 34, 60)
	stroke.Parent = label
	billboard.Parent = anchor
	m.Parent = parent
end

-- Nieve que cae sobre toda la zona (un emisor grande en el cielo)
local function buildSnowfall(parent: Instance)
	local sky = PartFactory.part(parent, "Nevada", {
		Size = Vector3.new(TUNDRA.MaxX - TUNDRA.MinX + 40, 1, TUNDRA.MaxZ - TUNDRA.MinZ + 20),
		CFrame = CFrame.new(ORIGIN.X, 55, (TUNDRA.MinZ + TUNDRA.MaxZ) / 2),
		Color = SNOW,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	sky.Transparency = 1
	sky.CastShadow = false
	local snow = Instance.new("ParticleEmitter")
	snow.Name = "Copos"
	snow.Color = ColorSequence.new(Color3.new(1, 1, 1))
	snow.LightEmission = 0.3
	snow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.25) })
	snow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.85, 0.3), NumberSequenceKeypoint.new(1, 1) })
	snow.Lifetime = NumberRange.new(9, 12)
	snow.Rate = 160
	snow.Speed = NumberRange.new(4, 6)
	snow.EmissionDirection = Enum.NormalId.Bottom
	snow.SpreadAngle = Vector2.new(15, 15)
	snow.Acceleration = Vector3.new(0.8, 0, 0.4)
	snow.RotSpeed = NumberRange.new(-40, 40)
	snow.Parent = sky
end

-- Sobre los escalones: pinos nevados abajo (1 y 2) y picos de hielo arriba (4 y 5)
local function buildTerraceDecor(parent: Instance, tops: { { Position: Vector3, Ring: number } })
	local folder = PartFactory.folder(parent, "TerraceDecor")
	local rng = Random.new(TUNDRA.DecorSeed + 7)
	for index, cell in tops do
		local p = cell.Position
		if cell.Ring <= 2 and index % 9 == 0 then
			snowyPine(folder, p, rng:NextNumber(0, 360), rng:NextNumber(0.8, 1.05))
		elseif cell.Ring >= 4 and index % 6 == 0 then
			iceCluster(folder, p, rng:NextNumber(0, 360), rng:NextNumber(1.2, 1.9))
		end
	end
end

local function buildDecor(parent: Instance)
	local folder = PartFactory.folder(parent, "MapDetails")
	local lakeCenter = world(LAKE.Center.X, 0, LAKE.Center.Y)
	local statue = world(STATUE.X, 0, STATUE.Y)
	local keepOut = {
		{ lakeCenter.X, lakeCenter.Z, LAKE.Size / 2 + 8 },
		{ statue.X, statue.Z, 16 },
	}
	-- La boca de la Gruta Glacial (montículo) y la plaza de los huevos
	table.insert(keepOut, { 52, ORIGIN.Z - 124, 22 })
	table.insert(keepOut, { 30, ORIGIN.Z + 9, 22 })
	local decor = StudWorld.newDecor(TUNDRA, "FrozenTundra", keepOut)
	local rng = decor.Rng

	buildFrozenLake(folder)
	buildGolemStatue(folder)
	decor.wallRow(20, 9, 12, function(pos, yaw)
		snowyPine(folder, pos, yaw, rng:NextNumber(1.0, 1.3))
	end)
	decor.scatter(14, 4, math.huge, 10, function(pos, yaw)
		iceCluster(folder, pos, yaw, rng:NextNumber(0.8, 1.3))
	end)
	decor.scatter(16, 3, math.huge, 6, function(pos, yaw)
		snowMound(folder, pos, yaw, rng:NextNumber(0.8, 1.2))
	end)
	decor.scatter(3, 8, 30, 12, function(pos, yaw)
		igloo(folder, pos, yaw)
	end)
	-- Farolillos de hielo a los dos lados de la avenida
	for z = TUNDRA.MinZ + 44, TUNDRA.MaxZ - 52, 28 do
		for _, side in { -1, 1 } do
			local x = side * 16
			if not StudWorld.onPath(TUNDRA, x, z) then
				iceLantern(folder, Vector3.new(x, StudWorld.FloorTop, z))
			end
		end
	end
	-- Transición hacia la Fortaleza Goblin junto al portal sur: estacas y estandartes goblins con nieve
	for _, side in { -1, 1 } do
		local gatePos = world(side * 15, StudWorld.FloorTop, 145)
		studBlock(folder, "FortressTransitionPost", Vector3.new(1.2, 5.6, 1.2), CFrame.new(gatePos + Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(-side * 8)), PINE.Trunk, true)
		studBlock(folder, "FortressTransitionBanner", Vector3.new(2.2, 3.2, 0.3), CFrame.new(gatePos + Vector3.new(-side * 1.1, 3.6, 0)), RGB(150, 42, 48), false)
		studBlock(folder, "FortressTransitionSnow", Vector3.new(2.8, 0.7, 2.8), CFrame.new(gatePos + Vector3.new(0, 0.35, 0)), SNOW, false)
	end
	-- Cartel de bienvenida en la llegada
	local sign = PartFactory.part(folder, "CartelLlegada", {
		Size = Vector3.one * 0.2,
		CFrame = CFrame.new(world(0, 12, -128)),
		Color = SNOW,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	sign.Transparency = 1
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(20, 3.6)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 140
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = RGB(200, 236, 255)
	label.Text = "❄️ TUNDRA HELADA"
	label.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = RGB(20, 34, 60)
	stroke.Parent = label
	billboard.Parent = sign
end

function TundraService.start()
	PartFactory.removeExisting(workspace, MODEL_NAME)
	buildFlatTerrain()

	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	StudWorld.buildFloor(model, TUNDRA)
	local tops = StudWorld.buildWalls(model, TUNDRA)
	buildDecor(model)
	if tops then
		buildTerraceDecor(model, tops)
	end
	buildSnowfall(model)
	model.Parent = workspace
end

-- Para las pruebas: dónde están las cosas (relativo al centro de la zona)
TundraService.Lake = LAKE
TundraService.Statue = STATUE
TundraService.EnemyZone = EnemyConfig.Zones.FrozenTundra

return TundraService
