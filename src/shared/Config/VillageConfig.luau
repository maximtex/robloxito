-- Pueblo del Renacimiento (VillageService): el "City" de REBIRTH CITY. Justo detrás del
-- spawn, una calle de adoquines con casitas de fantasía a los lados lleva a una plaza con
-- fuente, puestos de mercado y banderines, y termina en el portal al Valle Cristalino.
-- Edificios con uso: la Tienda (abre 💎 Tienda), la casita de Premios (abre 🎁 Premios) y
-- el tablón de misiones (abre 📜 Misiones), con un aviso de proximidad (tecla E).
--
-- Posiciones RELATIVAS al Cristal del Renacimiento (centro del bosque), en X/Z, como
-- WorldConfig: X positivo = derecha vista desde el spawn, Z positivo = hacia el spawn y
-- más allá. El paisaje (LandscapeLayout) y las flores (WorldService) dejan libre todo lo
-- que ocupa el pueblo (VillageConfig.footprints); los enemigos no entran (SafeZone).

local V2 = Vector2.new

local VillageConfig = {
	ModelName = "Village",
	Name = "Pueblo del Renacimiento",

	-- Calle principal: del arco de entrada al portal del Valle (ZoneConfig.Portals).
	Street = { From = V2(0, 44), To = V2(0, 117), Width = 7, Material = "Cobblestone" }, -- acaba bajo el escalón del portal
	-- Plaza con la fuente en el centro.
	Square = { Center = V2(0, 84), Radius = 13, Material = "Cobblestone" },
	Fountain = { Radius = 4.2, Height = 1.4 },
	-- Arco de bienvenida sobre la calle.
	Gate = { Z = 47, Width = 12, Height = 10 },

	-- Estilos de casa (diseño "Casas del Pueblo" de Santiago; VillageHouses los construye).
	-- Huella en el suelo con tejados, escalones y adornos: Width a lo largo de la fachada,
	-- Back hacia atrás y Front hacia la calle, desde Position.
	Styles = {
		Timber = { Width = 14, Back = 6, Front = 7 }, -- A · entramado de dos plantas
		Tower = { Width = 13.6, Back = 4.8, Front = 6.5 }, -- B · cabaña con torre
		Shop = { Width = 12, Back = 6.5, Front = 8 }, -- C · tienda con escaparate y balcón
	},

	-- Edificios. Facing: hacia dónde mira la puerta ("East" = +X, "West" = -X).
	-- Roof: color del tejado (Colors.Roofs). Los que tienen Panel abren ese panel de la
	-- interfaz con su aviso de proximidad (PanelManager: "Shop", "Rewards", "Quests").
	Buildings = {
		{ Id = "House1", Style = "Timber", Position = V2(-19, 56), Facing = "East", Roof = "Red" },
		{ Id = "Shop", Style = "Shop", Position = V2(-22, 73), Facing = "East", Roof = "Blue", Sign = "💎 Tienda", Panel = "Shop", Prompt = "Abrir tienda", Display = "Crystals" },
		{ Id = "Rewards", Style = "Shop", Position = V2(19.5, 60), Facing = "West", Roof = "Pink", Sign = "🎁 Premios", Panel = "Rewards", Prompt = "Ver premios", Display = "Gifts" },
		{ Id = "House2", Style = "Tower", Position = V2(21, 74), Facing = "West", Roof = "Green" },
		{ Id = "House3", Style = "Timber", Position = V2(-19, 99), Facing = "East", Roof = "Orange" },
		{ Id = "House4", Style = "Tower", Position = V2(-19, 114), Facing = "East", Roof = "Plum" },
		{ Id = "House5", Style = "Tower", Position = V2(-36, 86), Facing = "East", Roof = "Red" },
	},

	-- Puestos de mercado dentro de la plaza (ángulo en grados desde el centro: 0 = +X,
	-- 90 = +Z) con su toldo de rayas y mercancía.
	Stalls = {
		{ Angle = 45, Distance = 9.4, Colors = { "Red", "Cream" }, Goods = "Fruit" },
		{ Angle = 135, Distance = 9.4, Colors = { "Blue", "Cream" }, Goods = "Crystals" },
		{ Angle = 225, Distance = 9.4, Colors = { "Green", "Cream" }, Goods = "Flowers" },
		{ Angle = 315, Distance = 9.4, Colors = { "Orange", "Cream" }, Goods = "Bread" },
	},

	-- Tablón de misiones junto a la calle.
	Board = { Position = V2(-9, 63), Facing = "East", Panel = "Quests", Prompt = "Ver misiones" },

	-- Cofre «RECLAMAR» (VillageService), con su círculo de 12 studs: en el prado entre la plaza,
	-- la avenida y el pasillo del Jardín de los Huevos, mirando en diagonal a la esquina de la
	-- plaza. En coordenadas del mundo, como los puestos de la plaza.
	ClaimChest = { Position = V2(19, 35), FaceToward = V2(12, 28) },
	-- Máquina de Evolución (VillageService), Scale veces su tamaño y sin círculo (se usa con
	-- E): en el prado del otro lado de la avenida, en espejo con el cofre. Coordenadas del mundo.
	EvolutionMachine = { Position = V2(-20, 36), FaceToward = V2(-12, 28), Scale = 1.6 },

	-- Bancos alrededor de la plaza (ángulo en grados) y farolas a los lados de la calle.
	Benches = { 20, 160, 200, 340 },
	BenchDistance = 11.6,
	LampSides = 5.6, -- distancia de las farolas al centro de la calle
	LampsAt = { 54, 66, 102, 112 }, -- Z de cada pareja de farolas (las de la plaza aparte)
	SquareLamps = { 0, 180 }, -- ángulos de las farolas en el borde de la plaza (salidas este y oeste)

	-- Banderines: guirnaldas entre farolas que cruzan la calle (en zigzag) y alrededor de
	-- la plaza.
	Bunting = { Sag = 1.2, FlagSpacing = 1.4 },

	-- Zona protegida de los enemigos (EnemyConfig.SafeZones la incluye).
	Safe = { Center = V2(0, 84), Radius = 44 },

	Colors = {
		Plaster = Color3.fromRGB(242, 232, 212),
		Beam = Color3.fromRGB(96, 66, 44),
		Stone = Color3.fromRGB(168, 162, 148),
		DarkStone = Color3.fromRGB(120, 116, 108),
		Door = Color3.fromRGB(122, 80, 48),
		Window = Color3.fromRGB(255, 224, 160),
		Brick = Color3.fromRGB(168, 96, 74),
		Wood = Color3.fromRGB(150, 108, 70),
		Roofs = {
			Red = Color3.fromRGB(196, 84, 64),
			Blue = Color3.fromRGB(74, 116, 186),
			Pink = Color3.fromRGB(226, 120, 170),
			Orange = Color3.fromRGB(226, 140, 64),
			Green = Color3.fromRGB(86, 150, 90),
			Plum = Color3.fromRGB(140, 92, 170),
		},
		Awning = {
			Red = Color3.fromRGB(214, 74, 70),
			Blue = Color3.fromRGB(70, 130, 214),
			Green = Color3.fromRGB(80, 170, 96),
			Orange = Color3.fromRGB(240, 150, 60),
			Cream = Color3.fromRGB(250, 242, 222),
			Pink = Color3.fromRGB(240, 140, 190),
		},
		Flags = {
			Color3.fromRGB(240, 92, 92), Color3.fromRGB(255, 200, 80), Color3.fromRGB(110, 200, 120),
			Color3.fromRGB(90, 160, 240), Color3.fromRGB(200, 130, 240), Color3.fromRGB(255, 150, 190),
		},
		Water = Color3.fromRGB(104, 196, 230),
		Crystal = Color3.fromRGB(110, 236, 220),
		Lamp = Color3.fromRGB(255, 214, 150),
		Sign = Color3.fromRGB(70, 48, 32),
		SignText = Color3.fromRGB(255, 240, 210),
	},
}

local function facingSign(facing: string): number
	return if facing == "East" then 1 else -1
end
VillageConfig.facingSign = facingSign

-- Rectángulo que ocupa un edificio en el suelo (X, Z), con su centro.
function VillageConfig.buildingRect(building: any): { MinX: number, MaxX: number, MinZ: number, MaxZ: number, CenterX: number, CenterZ: number }
	local style = VillageConfig.Styles[building.Style] or VillageConfig.Styles.Timber
	local sign = facingSign(building.Facing)
	local x, z = building.Position.X, building.Position.Y
	local x1, x2 = x - sign * style.Back, x + sign * style.Front
	local rect = {
		MinX = math.min(x1, x2),
		MaxX = math.max(x1, x2),
		MinZ = z - style.Width / 2,
		MaxZ = z + style.Width / 2,
		CenterX = 0,
		CenterZ = 0,
	}
	rect.CenterX = (rect.MinX + rect.MaxX) / 2
	rect.CenterZ = (rect.MinZ + rect.MaxZ) / 2
	return rect
end

-- Distancia de (x, z) a un rectángulo (0 si está dentro).
function VillageConfig.distanceToRect(x: number, z: number, rect: any): number
	local dx = math.max(rect.MinX - x, 0, x - rect.MaxX)
	local dz = math.max(rect.MinZ - z, 0, z - rect.MaxZ)
	return math.sqrt(dx * dx + dz * dz)
end

-- Posición de un puesto de mercado.
function VillageConfig.stallPosition(stall: any): Vector2
	local angle = math.rad(stall.Angle)
	local center = VillageConfig.Square.Center
	return V2(center.X + math.cos(angle) * stall.Distance, center.Y + math.sin(angle) * stall.Distance)
end

-- Farolas: { X, Z } a ambos lados de la calle y en el borde de la plaza.
function VillageConfig.lamps(): { Vector2 }
	local list = {}
	for _, z in VillageConfig.LampsAt do
		table.insert(list, V2(-VillageConfig.LampSides, z))
		table.insert(list, V2(VillageConfig.LampSides, z))
	end
	local square = VillageConfig.Square
	for _, degrees in VillageConfig.SquareLamps do
		local angle = math.rad(degrees)
		table.insert(list, V2(square.Center.X + math.cos(angle) * (square.Radius + 1.2), square.Center.Y + math.sin(angle) * (square.Radius + 1.2)))
	end
	return list
end

-- Lo que ocupa el pueblo (círculos X, Z, radio, nombre): para que el paisaje, las flores
-- y la colocación de todo lo demás lo dejen libre.
function VillageConfig.footprints(): { { X: number, Z: number, R: number, Name: string } }
	local list = {}
	local function add(x: number, z: number, r: number, name: string)
		table.insert(list, { X = x, Z = z, R = r, Name = name })
	end
	local square = VillageConfig.Square
	add(square.Center.X, square.Center.Y, square.Radius + 1, "VillageSquare")
	for _, building in VillageConfig.Buildings do
		local rect = VillageConfig.buildingRect(building)
		local half = math.sqrt((rect.MaxX - rect.MinX) ^ 2 + (rect.MaxZ - rect.MinZ) ^ 2) / 2
		add(rect.CenterX, rect.CenterZ, half + 1, "Village_" .. building.Id)
	end
	for index, stall in VillageConfig.Stalls do
		local position = VillageConfig.stallPosition(stall)
		add(position.X, position.Y, 2.4, "VillageStall" .. index)
	end
	add(VillageConfig.Board.Position.X, VillageConfig.Board.Position.Y, 2, "VillageBoard")
	local gate = VillageConfig.Gate
	add(-gate.Width / 2, gate.Z, 1.6, "VillageGateWest")
	add(gate.Width / 2, gate.Z, 1.6, "VillageGateEast")
	for index, lamp in VillageConfig.lamps() do
		add(lamp.X, lamp.Y, 1, "VillageLamp" .. index)
	end
	for index, degrees in VillageConfig.Benches do
		local angle = math.rad(degrees)
		local distance = VillageConfig.BenchDistance
		add(square.Center.X + math.cos(angle) * distance, square.Center.Y + math.sin(angle) * distance, 1.6, "VillageBench" .. index)
	end
	return list
end

-- ¿Está (x, z) dentro de algo del pueblo o sobre su calle? (`margin` de holgura)
function VillageConfig.occupies(x: number, z: number, margin: number?): boolean
	local extra = margin or 0
	for _, item in VillageConfig.footprints() do
		if (x - item.X) ^ 2 + (z - item.Z) ^ 2 < (item.R + extra) ^ 2 then
			return true
		end
	end
	local street = VillageConfig.Street
	return math.abs(x - street.From.X) < street.Width / 2 + extra and z >= street.From.Y - extra and z <= street.To.Y + extra
end

return VillageConfig
