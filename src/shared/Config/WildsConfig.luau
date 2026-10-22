-- Naturaleza del Bosque (WildsService): el norte y los rincones que antes estaban vacíos.
-- - Río Cristalino: nace en una cascada al noroeste, cruza el norte del bosque por detrás
--   del árbol ancestral y desemboca en el Lago del Ocaso, al noreste.
-- - Cascada: acantilado de roca con una cortina de agua y una cornisa DETRÁS del agua (se
--   llega por unas piedras sobre la poza) donde se esconde un cofre.
-- - Puente del Norte (de madera, en arco) donde el Sendero del Norte cruza el río hacia las
--   Ruinas Antiguas; Campamento del Explorador junto al lago; praderas de hierba alta con
--   flores (y mariposas, que pone el cliente).
--
-- Posiciones RELATIVAS al Cristal del Renacimiento (centro del bosque), en X/Z, como
-- WorldConfig: X positivo = derecha vista desde el spawn, Z positivo = hacia el spawn.
-- Todo queda fuera de las zonas de juego (lo comprueban las pruebas del paisaje) y
-- LandscapeLayout lo deja libre al repartir árboles y rocas (WildsConfig.footprints).
-- Los caminos que llegan hasta aquí están en LandscapeConfig.Forest.Paths.

local V2 = Vector2.new

local WildsConfig = {
	ModelName = "Wilds",

	River = {
		Name = "Río Cristalino",
		-- Cauce (polilínea X, Z): de la poza de la cascada al lago.
		Points = {
			V2(-63.4, -112.9), V2(-49.8, -108.8), V2(-32.1, -104.7), V2(-11.9, -106.8), V2(5.1, -109.7),
			V2(23.4, -112.2), V2(41.7, -110), V2(59.9, -103.1), V2(73.8, -96.9),
		},
		Width = 9, -- ancho del agua
		Depth = 4,
		Bank = 2.5, -- orilla de arena a cada lado
		Step = 2, -- separación entre cortes del cauce (studs)
		SoundSpacing = 34, -- un emisor del murmullo del agua cada tantos studs
	},

	Waterfall = {
		Name = "Cascada del Eco",
		-- Centro de la cortina de agua (X) y plano de la cara del acantilado (Z).
		X = -63.4,
		FaceZ = -121.9,
		Height = 19, -- desde el suelo hasta el borde por donde cae el agua
		Width = 7,
		LedgeDepth = 3.5, -- cornisa entre la roca y el agua (detrás de la cascada)
		-- La poza llega hasta la roca: la cortina cae dentro del agua y la repisa queda encima.
		Pool = { Center = V2(-63.4, -112.9), Radius = 9.5, Depth = 5 },
		-- Rocas grandes que forman el acantilado (modelos de MapAssets; sin ellos, solo el
		-- bloque de roca del terreno). Relativas al centro de la cortina en la cara.
		Rocks = {
			{ X = -16, Z = -6, Height = 24, Variant = 4, Yaw = 30 },
			{ X = 16, Z = -6, Height = 22, Variant = 4, Yaw = 160 },
			{ X = -27, Z = 1, Height = 15, Variant = 9, Yaw = 200 },
			{ X = 27, Z = 0, Height = 12, Variant = 5, Yaw = 20 },
			{ X = 0, Z = -14, Height = 26, Variant = 4, Yaw = 95 },
		},
		-- Bloque de roca del terreno detrás de la cortina (ancho, alto, fondo).
		Block = Vector3.new(14, 24, 16),
		-- Piedras para cruzar la poza hasta la cornisa (desde el final del Sendero de la Cascada).
		Stones = { V2(-55.9, -100.4), V2(-57.4, -104.9), V2(-58.9, -109.4), V2(-60.4, -113.9), V2(-61.9, -117.9) },
	},

	Lake = { Name = "Lago del Ocaso", Center = V2(83.8, -96.9), Radius = 13, Depth = 5 },

	-- Puente donde el Sendero del Norte cruza el río (de From a To, recto).
	Bridges = {
		{ Name = "Puente del Norte", From = V2(0, -99.6), To = V2(0, -118.1), Width = 5, Arch = 1.6 },
	},

	Ruins = { Name = "Ruinas Antiguas", Center = V2(3.3, -132.4), Radius = 10 },

	Camp = { Name = "Campamento del Explorador", Center = V2(90, -72), Radius = 7 },

	-- Praderas: hierba alta (material Grass del terreno) y muchas flores.
	Meadows = {
		{ Name = "Pradera de las Mariposas", Center = V2(-116.4, 24.9), Radius = 16, Flowers = 70 },
		{ Name = "Prado del Estanque", Center = V2(66.9, 93.7), Radius = 15, Flowers = 60 },
		{ Name = "Ladera de las Flores", Center = V2(-51.1, 115.3), Radius = 14, Flowers = 55 },
	},

	Seed = 4411,

	Colors = {
		Sand = Color3.fromRGB(226, 208, 160),
		Water = Color3.fromRGB(120, 200, 230),
		Foam = Color3.fromRGB(236, 250, 255),
		Mist = Color3.fromRGB(220, 240, 255),
		Stone = Color3.fromRGB(150, 150, 140),
		RuinStone = Color3.fromRGB(196, 190, 170),
		DarkStone = Color3.fromRGB(110, 110, 104),
		Moss = Color3.fromRGB(92, 146, 70),
		Wood = Color3.fromRGB(140, 100, 64),
		DarkWood = Color3.fromRGB(96, 68, 44),
		Rope = Color3.fromRGB(196, 170, 120),
		Canvas = Color3.fromRGB(226, 196, 140),
		CanvasStripe = Color3.fromRGB(196, 96, 70),
		Fire = Color3.fromRGB(255, 150, 60),
		Crystal = Color3.fromRGB(110, 236, 220),
		Lily = Color3.fromRGB(86, 150, 70),
		LilyFlower = Color3.fromRGB(255, 186, 214),
		Reed = Color3.fromRGB(120, 140, 70),
		Flowers = {
			Color3.fromRGB(255, 156, 200), Color3.fromRGB(255, 214, 96), Color3.fromRGB(196, 156, 255),
			Color3.fromRGB(248, 246, 236), Color3.fromRGB(255, 120, 110), Color3.fromRGB(130, 200, 255),
		},
		Stem = Color3.fromRGB(86, 150, 64),
	},

	Sounds = {
		River = "rbxassetid://9120552550", -- Pro Sound Effects: corriente constante
		Waterfall = "rbxassetid://9120550536", -- Pro Sound Effects: cascada de cerca
	},
}

-- Distancia de (x, z) al cauce del río (al eje; negativa no existe).
function WildsConfig.distanceToRiver(x: number, z: number): number
	local points = WildsConfig.River.Points
	local best = math.huge
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		local dx, dz = b.X - a.X, b.Y - a.Y
		local lengthSquared = dx * dx + dz * dz
		local t = if lengthSquared > 0 then math.clamp(((x - a.X) * dx + (z - a.Y) * dz) / lengthSquared, 0, 1) else 0
		local px, pz = a.X + dx * t, a.Y + dz * t
		best = math.min(best, math.sqrt((x - px) ^ 2 + (z - pz) ^ 2))
	end
	return best
end

-- Puntos del cauce cada `step` studs (para tallarlo en el terreno y repartir sonidos).
function WildsConfig.riverSamples(step: number): { { X: number, Z: number, Distance: number } }
	local points = WildsConfig.River.Points
	local result = {}
	local travelled = 0
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		local dx, dz = b.X - a.X, b.Y - a.Y
		local length = math.sqrt(dx * dx + dz * dz)
		local count = math.max(1, math.ceil(length / step))
		for s = 0, count - 1 do
			local t = s / count
			table.insert(result, { X = a.X + dx * t, Z = a.Y + dz * t, Distance = travelled + length * t })
		end
		travelled += length
	end
	local last = points[#points]
	table.insert(result, { X = last.X, Z = last.Y, Distance = travelled })
	return result
end

-- Ancho del agua en un punto del cauce (varía un poco para que parezca natural).
function WildsConfig.riverWidthAt(distance: number): number
	local river = WildsConfig.River
	return river.Width + math.sin(distance / 23) * 1.2 + math.sin(distance / 9.5) * 0.5
end

-- Lo que ocupa (círculos X, Z, radio, nombre) para que el paisaje lo deje libre. El río va
-- aparte, como un camino ancho (LandscapeLayout).
function WildsConfig.footprints(): { { X: number, Z: number, R: number, Name: string } }
	local list = {}
	local function add(x: number, z: number, r: number, name: string)
		table.insert(list, { X = x, Z = z, R = r, Name = name })
	end
	local fall = WildsConfig.Waterfall
	add(fall.Pool.Center.X, fall.Pool.Center.Y, fall.Pool.Radius + 3, "WaterfallPool")
	add(fall.X, fall.FaceZ - 8, 18, "WaterfallCliff")
	local lake = WildsConfig.Lake
	add(lake.Center.X, lake.Center.Y, lake.Radius + 4, "Lake")
	add(WildsConfig.Ruins.Center.X, WildsConfig.Ruins.Center.Y, WildsConfig.Ruins.Radius + 2, "Ruins")
	add(WildsConfig.Camp.Center.X, WildsConfig.Camp.Center.Y, WildsConfig.Camp.Radius + 2, "Camp")
	for index, bridge in WildsConfig.Bridges do
		local length = math.sqrt((bridge.From.X - bridge.To.X) ^ 2 + (bridge.From.Y - bridge.To.Y) ^ 2)
		add((bridge.From.X + bridge.To.X) / 2, (bridge.From.Y + bridge.To.Y) / 2, length / 2 + 2, "Bridge" .. index)
	end
	return list
end

-- Ancho del río como obstáculo (agua, orillas y un margen).
function WildsConfig.riverClearance(): number
	local river = WildsConfig.River
	return river.Width + 1.2 * 2 + river.Bank * 2 + 2
end

return WildsConfig
