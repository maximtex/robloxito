-- Construye la Fortaleza Goblin (Zona 5, final del Mundo 1), pegada tras la Tundra Helada, con
-- el mismo estilo de bloques (StudWorld; distribución en StudFloor.Zones.GoblinFortress):
-- - Prado de musgo con los campamentos goblin (tiendas, hogueras, cajas, empalizadas y
--   estandartes) a los lados del camino.
-- - La muralla de piedra de borde a borde con almenas, torres y la puerta abierta con su rastrillo.
-- - El patio: la Sala del Trono (arena del Rey Goblin, EnemyConfig.Zones.GoblinFortress.Boss),
--   con columnas y antorchas, el trono detrás y, al fondo, la tarima del PORTAL GIGANTE al
--   Mundo 2 (el arco lo construye ZoneService con ZoneConfig.WorldPortals.World2Portal).
-- - Riscos oscuros con musgo alrededor que cierran el fondo. Solo decorativo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local StudFloor = require(Shared.Util.StudFloor)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local StudWorld = require(script.Parent.Parent.Util.StudWorld)
local StudProps = require(script.Parent.Parent.Util.StudProps)

local FortressService = {}

local MODEL_NAME = "GoblinFortress"
local CENTER_2D = ZoneConfig.Zones.GoblinFortress.Center
local ORIGIN = Vector3.new(GeneratorConfig.Position.X + CENTER_2D.X, 0, GeneratorConfig.Position.Z + CENTER_2D.Y)
local FORT = StudFloor.Zones.GoblinFortress
local RAMPART = FORT.Rampart
local ARENA = EnemyConfig.Zones.GoblinFortress.Boss.Arena
local PORTAL = ZoneConfig.WorldPortals.World2Portal
local RGB = Color3.fromRGB

local STONE = { RGB(116, 110, 100), RGB(98, 94, 86) }
local DARK_STONE = RGB(70, 66, 60)
local MOSS = RGB(92, 140, 56)
local WOOD = { RGB(132, 92, 56), RGB(104, 70, 42) }
local CLOTH = { RGB(110, 150, 60), RGB(150, 110, 60), RGB(120, 60, 50) }
local BANNER = RGB(70, 130, 40)
local GOLD = RGB(240, 196, 70)
local FIRE = RGB(255, 150, 60)
local GREEN_FIRE = RGB(120, 255, 110)

local TOP = StudWorld.FloorTop
local B = 8

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

local function addFire(part: BasePart, color: Color3, size: number)
	local fire = Instance.new("Fire")
	fire.Size = size
	fire.Heat = 7
	fire.Color = color
	fire.SecondaryColor = color:Lerp(Color3.new(1, 1, 0.6), 0.5)
	fire.Parent = part
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 18
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = part
end

local function billboardText(parent: Instance, position: Vector3, text: string, color: Color3, width: number, height: number, distance: number)
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
	stroke.Thickness = 3
	stroke.Color = RGB(24, 22, 18)
	stroke.Parent = label
	billboard.Parent = anchor
end

-- Tierra por debajo del suelo
local function buildFlatTerrain()
	StudWorld.fillTerrainBelow(-220, 220, FORT.MinZ, FORT.MaxZ + 48, Enum.Material.Ground)
end

-- Estandarte goblin: asta con una bandera verde y el dibujo de una calavera con colmillos
local function banner(parent: Instance, pos: Vector3, yawDeg: number, height: number)
	local m = Instance.new("Model")
	m.Name = "Estandarte"
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	studBlock(m, "Asta", Vector3.new(0.6, height, 0.6), cf * CFrame.new(0, height / 2, 0), WOOD[2], true)
	studBlock(m, "Travesano", Vector3.new(4.4, 0.4, 0.4), cf * CFrame.new(0, height - 0.6, 0), WOOD[2], false)
	local flag = PartFactory.part(m, "Bandera", {
		Size = Vector3.new(4, 5.6, 0.2),
		CFrame = cf * CFrame.new(0, height - 3.6, -0.35),
		Color = BANNER,
		Material = Enum.Material.Fabric,
		Solid = false,
	})
	flag.CastShadow = false
	-- Calavera: cabeza clara, dos ojos y dos colmillos (piezas planas encima de la tela)
	local face = flag.CFrame * CFrame.new(0, 0.4, -0.12)
	PartFactory.part(m, "Calavera", { Size = Vector3.new(2, 1.8, 0.05), CFrame = face, Color = RGB(236, 226, 196), Material = Enum.Material.SmoothPlastic, Solid = false })
	for side = -1, 1, 2 do
		PartFactory.part(m, "Ojo", { Size = Vector3.new(0.5, 0.5, 0.06), CFrame = face * CFrame.new(side * 0.45, 0.2, -0.02), Color = RGB(30, 24, 20), Material = Enum.Material.SmoothPlastic, Solid = false })
		PartFactory.part(m, "Colmillo", { Size = Vector3.new(0.25, 0.6, 0.06), CFrame = face * CFrame.new(side * 0.4, -1.1, -0.02), Color = RGB(236, 226, 196), Material = Enum.Material.SmoothPlastic, Solid = false })
	end
	m.Parent = parent
end

-- Tienda goblin: dos lonas inclinadas (en A), con la entrada oscura y un palo en la cumbrera
local function tent(parent: Instance, pos: Vector3, yawDeg: number, scale: number, color: Color3)
	local m = Instance.new("Model")
	m.Name = "TiendaGoblin"
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local w, h, d = 7 * scale, 5.5 * scale, 8 * scale
	for side = -1, 1, 2 do
		local wedge = Instance.new("WedgePart")
		wedge.Name = "Lona"
		wedge.Anchored = true
		wedge.Size = Vector3.new(d, h, w / 2)
		wedge.CFrame = cf * CFrame.new(side * w / 4, h / 2, 0) * CFrame.Angles(0, math.rad(side * 90), 0)
		wedge.Color = color
		wedge.Material = Enum.Material.Fabric
		wedge.TopSurface = Enum.SurfaceType.Smooth
		wedge.BottomSurface = Enum.SurfaceType.Smooth
		wedge.CanTouch = false
		wedge.Parent = m
	end
	PartFactory.part(m, "Entrada", {
		Size = Vector3.new(2.2 * scale, 3 * scale, 0.1),
		CFrame = cf * CFrame.new(0, 1.5 * scale, -d / 2 - 0.05),
		Color = RGB(36, 30, 24),
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	studBlock(m, "Palo", Vector3.new(0.5, 0.5, d + 1.4), cf * CFrame.new(0, h + 0.1, 0), WOOD[2], false)
	m.Parent = parent
end

-- Hoguera: troncos cruzados, piedras en anillo y fuego
local function campfire(parent: Instance, pos: Vector3)
	local m = Instance.new("Model")
	m.Name = "Hoguera"
	for index = 1, 6 do
		local a = index / 6 * math.pi * 2
		studBlock(m, "Piedra", Vector3.new(1.2, 0.8, 1.2), CFrame.new(pos + Vector3.new(math.cos(a) * 2.2, 0.4, math.sin(a) * 2.2)) * CFrame.Angles(0, a, 0), DARK_STONE, false)
	end
	for index = 1, 3 do
		local a = index / 3 * math.pi
		PartFactory.part(m, "Tronco", {
			Size = Vector3.new(0.7, 0.7, 3.6),
			CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, a, math.rad(10)),
			Color = WOOD[2],
			Material = Enum.Material.Wood,
			Solid = false,
		})
	end
	local core = PartFactory.part(m, "Brasas", {
		Size = Vector3.new(1.4, 0.6, 1.4),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.7, 0)),
		Color = FIRE,
		Material = Enum.Material.Neon,
		Solid = false,
	})
	addFire(core, FIRE, 5)
	m.Parent = parent
end

-- Caja de madera con studs (a veces dos apiladas)
local function crates(parent: Instance, pos: Vector3, yawDeg: number, count: number)
	local m = Instance.new("Model")
	m.Name = "Cajas"
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	for index = 1, count do
		local offset = if index == 1 then CFrame.new(0, 1.3, 0) elseif index == 2 then CFrame.new(2.7, 1.1, 0.4) * CFrame.Angles(0, 0.3, 0) else CFrame.new(0.9, 3.7, 0.1) * CFrame.Angles(0, -0.2, 0)
		local size = if index == 2 then Vector3.new(2.2, 2.2, 2.2) else Vector3.new(2.6, 2.6, 2.6)
		studBlock(m, "Caja", size, cf * offset, WOOD[index % 2 + 1], true)
	end
	m.Parent = parent
end

-- Empalizada: troncos afilados inclinados hacia fuera
local function palisade(parent: Instance, from: Vector3, to: Vector3)
	local m = Instance.new("Model")
	m.Name = "Empalizada"
	local dir = to - from
	local count = math.max(2, math.floor(dir.Magnitude / 1.6))
	local across = Vector3.new(-dir.Z, 0, dir.X).Unit
	for index = 0, count do
		local p = from + dir * (index / count)
		local height = 4 + (index % 3) * 0.6
		PartFactory.part(m, "Estaca", {
			Size = Vector3.new(0.9, height, 0.9),
			CFrame = CFrame.lookAt(p, p + across) * CFrame.new(0, height / 2, 0) * CFrame.Angles(math.rad(-14), 0, 0),
			Color = WOOD[(index % 2) + 1],
			Material = Enum.Material.Wood,
			Solid = true,
		})
	end
	m.Parent = parent
end

-- Roca con musgo
local function mossyRock(parent: Instance, pos: Vector3, yawDeg: number, scale: number)
	local m = Instance.new("Model")
	m.Name = "RocaMusgo"
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	studBlock(m, "Roca", Vector3.new(4, 2.6, 3.4) * scale, cf * CFrame.new(0, 1.3 * scale, 0), STONE[2], true)
	studBlock(m, "Musgo", Vector3.new(3.4, 0.5, 2.8) * scale, cf * CFrame.new(0.2, 2.85 * scale, 0), MOSS, false)
	studBlock(m, "Piedra", Vector3.new(1.8, 1.2, 1.6) * scale, cf * CFrame.new(2.6 * scale, 0.6 * scale, 1 * scale), STONE[1], false)
	m.Parent = parent
end

-- Antorcha: palo con fuego
local function torch(parent: Instance, pos: Vector3, color: Color3?)
	local m = Instance.new("Model")
	m.Name = "Antorcha"
	studBlock(m, "Palo", Vector3.new(0.7, 5, 0.7), CFrame.new(pos + Vector3.new(0, 2.5, 0)), WOOD[2], true)
	studBlock(m, "Cuenco", Vector3.new(1.5, 0.7, 1.5), CFrame.new(pos + Vector3.new(0, 5.2, 0)), DARK_STONE, false)
	local flame = PartFactory.part(m, "Llama", {
		Size = Vector3.new(0.9, 0.9, 0.9),
		CFrame = CFrame.new(pos + Vector3.new(0, 5.9, 0)) * CFrame.Angles(0, math.rad(45), 0),
		Color = color or FIRE,
		Material = Enum.Material.Neon,
		Solid = false,
	})
	addFire(flame, color or FIRE, 2.6)
	m.Parent = parent
end

-- Muralla: bloques de piedra en damero, almenas encima, torres y la puerta con su rastrillo
local function buildRampart(parent: Instance)
	local folder = PartFactory.folder(parent, "Muralla")
	local z0, z1 = RAMPART.Z0, RAMPART.Z1
	local zc = (z0 + z1) / 2
	local depth = z1 - z0
	local rows = 3
	local gate = RAMPART.GateHalf
	local edge = FORT.MaxX
	for _, side in { -1, 1 } do
		local cols = math.round((edge - gate) / B)
		for col = 1, cols do
			local x = side * (gate + (col - 0.5) * B)
			for row = 1, rows do
				local part = studBlock(folder, "Bloque", Vector3.new(B, B, depth), CFrame.new(x, TOP + (row - 0.5) * B, zc), STONE[(col + row) % 2 + 1], true)
				part.Name = ("Bloque_%d_%d"):format(row, col)
			end
			-- Almena cada dos bloques
			if col % 2 == 1 then
				studBlock(folder, "Almena", Vector3.new(B * 0.6, 3.4, depth), CFrame.new(x, TOP + rows * B + 1.7, zc), STONE[col % 2 + 1], true)
			end
		end
		-- Torres: junto a la puerta y en la esquina
		for _, tx in { gate + 6, edge - 8 } do
			local x = side * tx
			local towerH = rows * B + 10
			studBlock(folder, "Torre", Vector3.new(12, towerH, 12), CFrame.new(x, TOP + towerH / 2, zc), DARK_STONE, true)
			for corner = 1, 4 do
				local cx = x + (if corner <= 2 then -4.5 else 4.5)
				local cz = zc + (if corner % 2 == 0 then -4.5 else 4.5)
				studBlock(folder, "AlmenaTorre", Vector3.new(3, 3, 3), CFrame.new(cx, TOP + towerH + 1.5, cz), STONE[1], true)
			end
			banner(folder, Vector3.new(x, TOP + towerH, zc), 0, 10)
			-- Antorchas en la cara de fuera de las torres de la puerta
			if tx == gate + 6 then
				local flame = PartFactory.part(folder, "AntorchaTorre", {
					Size = Vector3.new(1, 1.2, 1),
					CFrame = CFrame.new(x, TOP + 13, z0 - 6.6),
					Color = FIRE,
					Material = Enum.Material.Neon,
					Solid = false,
				})
				addFire(flame, FIRE, 3)
			end
		end
	end
	-- Dintel sobre la puerta y el rastrillo levantado (solo asoman sus puntas)
	studBlock(folder, "Dintel", Vector3.new(gate * 2, B, depth), CFrame.new(0, TOP + (rows - 0.5) * B, zc), DARK_STONE, true)
	for index = 0, 7 do
		local x = -gate + 2 + index * ((gate * 2 - 4) / 7)
		PartFactory.part(folder, "Rastrillo", {
			Size = Vector3.new(0.6, 4, 0.6),
			CFrame = CFrame.new(x, TOP + (rows - 1) * B - 1.6, z0 + 1),
			Color = RGB(60, 46, 34),
			Material = Enum.Material.Wood,
			Solid = false,
		})
	end
	PartFactory.part(folder, "RastrilloBarra", {
		Size = Vector3.new(gate * 2 - 2, 0.6, 0.6),
		CFrame = CFrame.new(0, TOP + (rows - 1) * B + 0.2, z0 + 1),
		Color = RGB(60, 46, 34),
		Material = Enum.Material.Wood,
		Solid = false,
	})
	billboardText(folder, Vector3.new(0, TOP + rows * B + 6, z0 - 1), "🏰 FORTALEZA GOBLIN", RGB(190, 255, 120), 26, 4, 220)
end

-- Sala del Trono: columnas con antorchas alrededor de la arena (con huecos al norte y al sur),
-- runas verdes en el suelo y el trono del rey detrás
local function buildThroneRoom(parent: Instance)
	local folder = PartFactory.folder(parent, "SalaDelTrono")
	local center = world(ARENA.Center.X, 0, ARENA.Center.Y)
	local floorY = TOP + StudFloor.PathRaise
	local count = 12
	for index = 1, count do
		local angle = (index - 0.5) / count * math.pi * 2
		-- Sin columnas en el paso de entrada (norte, -Z) ni hacia el portal (sur, +Z)
		local facingZ = math.sin(angle)
		if math.abs(facingZ) > 0.9 then
			continue
		end
		local pos = center + Vector3.new(math.cos(angle), 0, facingZ) * (ARENA.Radius + 5)
		local height = 16
		studBlock(folder, "Columna", Vector3.new(3.4, height, 3.4), CFrame.new(pos.X, floorY + height / 2, pos.Z), STONE[index % 2 + 1], true)
		studBlock(folder, "Capitel", Vector3.new(4.4, 1.2, 4.4), CFrame.new(pos.X, floorY + height + 0.6, pos.Z), DARK_STONE, true)
		local flame = PartFactory.part(folder, "Fuego", {
			Size = Vector3.new(1.4, 1, 1.4),
			CFrame = CFrame.new(pos.X, floorY + height + 1.7, pos.Z),
			Color = GREEN_FIRE,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		addFire(flame, GREEN_FIRE, 4)
	end
	-- Runas del borde y sello del centro (planas, sin colisión)
	for index = 1, 16 do
		local angle = index / 16 * math.pi * 2
		local pos = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (ARENA.Radius - 1.5)
		local tile = PartFactory.part(folder, "Runa", {
			Size = Vector3.new(1, 0.1, 2.6),
			CFrame = CFrame.lookAt(Vector3.new(pos.X, floorY + 0.06, pos.Z), Vector3.new(center.X, floorY + 0.06, center.Z)),
			Color = GREEN_FIRE,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		tile.Transparency = 0.3
	end
	for index, diameter in { 12, 8 } do
		local seal = PartFactory.verticalCylinder(folder, "Sello", Vector3.new(center.X, floorY + 0.04 + index * 0.03, center.Z), 0.08, diameter, if index == 1 then DARK_STONE else GREEN_FIRE, if index == 1 then Enum.Material.Slate else Enum.Material.Neon, false)
		seal.Transparency = if index == 1 then 0 else 0.55
		seal.CastShadow = false
	end
	billboardText(folder, Vector3.new(center.X, floorY + 24, center.Z - ARENA.Radius - 5), "👑 " .. ARENA.Name .. "\n<font size=\"16\">El Rey Goblin abre el portal al Mundo 2</font>", RGB(255, 220, 110), 24, 5, 200)

	-- El trono: tarima de escalones, asiento, respaldo alto con su corona de oro y dos braseros
	local throne = center + Vector3.new(0, 0, ARENA.Radius + 12)
	local cf = CFrame.lookAt(Vector3.new(throne.X, floorY, throne.Z), Vector3.new(throne.X, floorY, throne.Z - 1))
	for step = 1, 3 do
		studBlock(folder, "Tarima", Vector3.new(18 - step * 3, 1, 12 - step * 2), cf * CFrame.new(0, (step - 0.5), 0), STONE[step % 2 + 1], true)
	end
	studBlock(folder, "Asiento", Vector3.new(8, 3, 6), cf * CFrame.new(0, 4.5, 0.5), RGB(150, 40, 60), true)
	studBlock(folder, "Respaldo", Vector3.new(9, 14, 2), cf * CFrame.new(0, 10, 3.6), GOLD, true)
	studBlock(folder, "Cojin", Vector3.new(7, 9, 0.6), cf * CFrame.new(0, 9.5, 2.4), RGB(150, 40, 60), false)
	for side = -1, 1, 2 do
		studBlock(folder, "Brazo", Vector3.new(1.4, 2, 6), cf * CFrame.new(side * 4.6, 7, 0.5), GOLD, true)
		studBlock(folder, "PuntaCorona", Vector3.new(1.6, 3, 1.6), cf * CFrame.new(side * 3.2, 18.4, 3.6), GOLD, false)
		local bowl = studBlock(folder, "Brasero", Vector3.new(2.6, 6, 2.6), cf * CFrame.new(side * 11, 3, 0), DARK_STONE, true)
		local flame = PartFactory.part(folder, "FuegoTrono", {
			Size = Vector3.new(1.8, 1, 1.8),
			CFrame = bowl.CFrame * CFrame.new(0, 3.5, 0),
			Color = GREEN_FIRE,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		addFire(flame, GREEN_FIRE, 5)
	end
	studBlock(folder, "PuntaCoronaCentro", Vector3.new(1.8, 4, 1.8), cf * CFrame.new(0, 19, 3.6), GOLD, false)
	local gem = PartFactory.ball(folder, "Joya", (cf * CFrame.new(0, 15.5, 2.5)).Position, 1.6, RGB(255, 70, 50), Enum.Material.Neon, false)
	gem.CastShadow = false
end

-- Tarima del portal gigante: braseros de fuego verde a los lados y dos estatuas de goblin
local function buildPortalYard(parent: Instance)
	local folder = PartFactory.folder(parent, "PatioDelPortal")
	local center = world(PORTAL.Offset.X, 0, PORTAL.Offset.Y)
	local floorY = TOP + StudFloor.PathRaise
	for _, side in { -1, 1 } do
		for _, dz in { -14, 10 } do
			local pos = center + Vector3.new(side * 30, 0, dz)
			local bowl = studBlock(folder, "Brasero", Vector3.new(3, 7, 3), CFrame.new(pos.X, floorY + 3.5, pos.Z), DARK_STONE, true)
			local flame = PartFactory.part(folder, "Fuego", {
				Size = Vector3.new(2, 1, 2),
				CFrame = bowl.CFrame * CFrame.new(0, 4, 0),
				Color = GREEN_FIRE,
				Material = Enum.Material.Neon,
				Solid = false,
			})
			addFire(flame, GREEN_FIRE, 6)
		end
		-- Estatua de un goblin con lanza
		local base = center + Vector3.new(side * 24, 0, -22)
		local cf = CFrame.lookAt(Vector3.new(base.X, floorY, base.Z), Vector3.new(base.X, floorY, base.Z - 1))
		studBlock(folder, "Peana", Vector3.new(6, 2, 6), cf * CFrame.new(0, 1, 0), STONE[1], true)
		studBlock(folder, "Cuerpo", Vector3.new(3.4, 4, 2.4), cf * CFrame.new(0, 4.4, 0), STONE[2], true)
		studBlock(folder, "Cabeza", Vector3.new(3, 2.6, 2.6), cf * CFrame.new(0, 7.8, -0.1), STONE[2], true)
		for ear = -1, 1, 2 do
			studBlock(folder, "Oreja", Vector3.new(2.2, 0.6, 0.8), cf * CFrame.new(ear * 2.4, 8.2, 0) * CFrame.Angles(0, 0, math.rad(ear * 20)), STONE[2], false)
		end
		studBlock(folder, "Lanza", Vector3.new(0.5, 13, 0.5), cf * CFrame.new(side * 2.4, 6.5, -0.8), WOOD[2], false)
		studBlock(folder, "Punta", Vector3.new(1, 2, 0.4), cf * CFrame.new(side * 2.4, 13.6, -0.8), GOLD, false)
	end
end

-- Los campamentos goblin del prado (delante de la muralla) y las rocas con musgo
local function buildCamps(parent: Instance)
	local folder = PartFactory.folder(parent, "Campamentos")
	local keepOut = {}
	-- Nada pegado a la muralla
	for x = FORT.MinX, FORT.MaxX, 10 do
		table.insert(keepOut, { x, (RAMPART.Z0 + RAMPART.Z1) / 2, 14 })
	end
	local arena = world(ARENA.Center.X, 0, ARENA.Center.Y)
	table.insert(keepOut, { arena.X, arena.Z, ARENA.Radius + 18 })
	local portal = world(PORTAL.Offset.X, 0, PORTAL.Offset.Y)
	table.insert(keepOut, { portal.X, portal.Z, 34 })
	local decor = StudWorld.newDecor(FORT, "GoblinFortress", keepOut)
	local rng = decor.Rng
	local fieldMaxZ = RAMPART.Z0 - 6
	local function inField(pos: Vector3): boolean
		return pos.Z < fieldMaxZ
	end

	-- Campamentos fijos a los dos lados del camino: tienda, hoguera, cajas y estandarte
	for _, spec in {
		{ X = -64, Z = -120, Yaw = 150 },
		{ X = 64, Z = -120, Yaw = 210 },
		{ X = -96, Z = -70, Yaw = 110 },
		{ X = 96, Z = -70, Yaw = 250 },
		{ X = -48, Z = -76, Yaw = 160 },
		{ X = 48, Z = -76, Yaw = 200 },
	} do
		local pos = world(spec.X, TOP, spec.Z)
		pos = Vector3.new(pos.X, TOP, pos.Z)
		tent(folder, pos, spec.Yaw, rng:NextNumber(0.9, 1.15), CLOTH[rng:NextInteger(1, #CLOTH)])
		local yaw = math.rad(spec.Yaw)
		local forward = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
		campfire(folder, pos + forward * 9)
		crates(folder, pos + Vector3.new(-forward.Z, 0, forward.X) * 7, spec.Yaw + 20, rng:NextInteger(1, 3))
		banner(folder, pos + Vector3.new(forward.Z, 0, -forward.X) * 6, spec.Yaw, 9)
	end
	-- Empalizadas a los lados del camino, antes de la puerta
	for _, side in { -1, 1 } do
		palisade(folder, Vector3.new(side * 18, TOP, RAMPART.Z0 - 30), Vector3.new(side * 18, TOP, RAMPART.Z0 - 10))
		palisade(folder, Vector3.new(side * 40, TOP, RAMPART.Z0 - 10), Vector3.new(side * 70, TOP, RAMPART.Z0 - 10))
	end
	decor.wallRow(18, 9, 10, function(pos, yaw)
		if inField(pos) then
			mossyRock(folder, pos, yaw, rng:NextNumber(0.9, 1.4))
		end
	end)
	decor.scatter(14, 4, math.huge, 8, function(pos, yaw)
		if inField(pos) then
			crates(folder, pos, yaw, rng:NextInteger(1, 3))
		end
	end)
	decor.scatter(10, 4, math.huge, 9, function(pos, yaw)
		mossyRock(folder, pos, yaw, rng:NextNumber(0.8, 1.2))
	end)
	-- Antorchas a los lados del camino de llegada
	for z = FORT.MinZ + 40, RAMPART.Z0 - 14, 22 do
		for _, side in { -1, 1 } do
			torch(folder, Vector3.new(side * 15, TOP, z))
		end
	end
	billboardText(folder, world(0, 12, -128), "🏰 FORTALEZA GOBLIN", RGB(190, 255, 120), 20, 3.6, 140)
end

-- El patio por dentro: barriles, cajas y estandartes junto a las paredes, antorchas
local function buildCourtyard(parent: Instance)
	local folder = PartFactory.folder(parent, "Patio")
	local floorY = TOP + StudFloor.PathRaise
	for _, side in { -1, 1 } do
		for index, z in { RAMPART.Z1 + 14, RAMPART.Z1 + 50, RAMPART.Z1 + 92, RAMPART.Z1 + 132 } do
			local x = side * 70
			if index % 2 == 1 then
				crates(folder, Vector3.new(x, floorY, z), side * 40, 3)
			else
				banner(folder, Vector3.new(x, floorY, z), if side < 0 then 90 else -90, 11)
			end
			torch(folder, Vector3.new(side * 46, floorY, z + 8), GREEN_FIRE)
		end
	end
end

-- Sobre los riscos: árboles de musgo abajo y picos de roca arriba
local MOSS_TREE = { Trunk = RGB(92, 66, 44), LeafLight = RGB(98, 150, 54), LeafDark = RGB(78, 126, 42) }
local function buildTerraceDecor(parent: Instance, tops: { { Position: Vector3, Ring: number } })
	local folder = PartFactory.folder(parent, "TerraceDecor")
	local rng = Random.new(FORT.DecorSeed + 7)
	for index, cell in tops do
		local p = cell.Position
		if cell.Ring <= 2 and index % 10 == 0 then
			StudWorld.buildBlockyTree(folder, p, rng:NextNumber(0, 360), rng:NextNumber(0.75, 1), MOSS_TREE)
		elseif cell.Ring >= 4 and index % 8 == 0 then
			studBlock(folder, "Pico", Vector3.new(4, rng:NextNumber(6, 12), 4), CFrame.new(p + Vector3.new(0, 3, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), math.rad(rng:NextNumber(-8, 8))), DARK_STONE, false)
		end
	end
end

function FortressService.start()
	PartFactory.removeExisting(workspace, MODEL_NAME)
	buildFlatTerrain()

	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	StudWorld.buildFloor(model, FORT)
	local tops = StudWorld.buildWalls(model, FORT)
	buildRampart(model)
	buildThroneRoom(model)
	buildPortalYard(model)
	buildCamps(model)
	buildCourtyard(model)
	if tops then
		buildTerraceDecor(model, tops)
	end
	-- Todo en estilo studs, como el spawn (menos lo que brilla)
	StudProps.studifyMap(model)
	model.Parent = workspace
end

return FortressService
