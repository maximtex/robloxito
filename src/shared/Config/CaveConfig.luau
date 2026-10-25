-- Mazmorras (cuevas): una en cada zona, con la MISMA forma (tres salas unidas por pasillos,
-- lejos del mapa) y cada vez más difíciles:
--   Bosque: Cueva de los Espinillos. La boca está en la colina oeste, al final del camino de
--           piedra que sale de la plaza (StudFloor.Zones.Forest.Cave).
--   Valle:  Cueva de Amatista. La boca es un montículo de roca a la derecha de la llegada.
--   Caldera: Forja de Magma. Igual, a la derecha de la llegada.
--   Tundra: Gruta Glacial. Igual (con carámbanos que caen del techo).
-- Al cruzar la boca, la pantalla se funde a negro y apareces dentro:
--   1. Sala de los pequeños. Aquí llegas.
--   2. Sala de los medianos (en el Valle y la Caldera, con un MINI-JEFE que guarda la puerta).
--   3. Sala del altar de las oleadas de la zona (WaveConfig.Places.<zona>): salen pequeños y
--      medianos y, en la última oleada, el jefe de la zona. Al ganar, un cofre (WaveConfig).
-- Cada pasillo empieza con una puerta de roca (Gates): se abre al derrotar los bichos que pide
-- en la sala de antes (o al mini-jefe: MiniBoss), solo para ti y para siempre (se guarda:
-- PetData.Cave, un número por puerta de TODAS las cuevas). Los bichos de cada cueva son más
-- duros que los de fuera (Strength), y en el Valle y la Caldera además:
--   - Trampas (Traps): pinchos de cristal / chorros de lava que salen del suelo junto a ti
--     (avisan con un círculo antes). Las lanza CaveService; las dibuja CaveTraps.
--   - Mini-jefe (MiniBoss) en la sala 2: abre la puerta del altar.
--   - Bichos élite (EliteChance; EnemyConfig.Elite): más grandes, brillan, con más vida y botín.
-- En la sala 1 (junto a donde llegas) y en la 3 hay un portal de salida que te devuelve a la
-- boca de esa cueva. Los bichos de las salas son los de su zona (EnemyConfig.Zones.<zona>).
-- Las cuevas están fuera de los cuadrados de las zonas: ZoneService las cuenta como su zona.
-- Todo en coordenadas del mundo y en bordes de bloque (8k ± 4); las alturas, desde la cara
-- de arriba del suelo. Las del Valle y la Caldera son la del Bosque movida en Z (Shift: lo
-- mismo que se separan los centros de las zonas, así sus bichos y círculos tienen los mismos
-- Offset relativos a su zona). Lo construye Server.Util.CaveDungeon (la boca del Bosque,
-- ForestCave); el viaje y las trampas, CaveService; el fundido, los carteles de cada sala y el
-- ambiente, el cliente (CaveController). Lógica pura (en qué cueva y sala estás) en
-- Shared.CaveLogic.
-- Listas planas (Rooms, Corridors, Gates, Exits): las de todas las cuevas seguidas, cada una
-- con su Cave; los índices (Room, Corridor, From, To) son de esas listas. Las del Bosque van
-- primero (sus índices no cambian: 1..3 salas, 1..2 puertas).

local RGB = Color3.fromRGB

-- Bosque: Cueva de los Espinillos ---------------------------------------------------------------

local FOREST = {
	Name = "Cueva de los Espinillos",
	Icon = "🦇",
	Zone = "Forest",
	Subtitle = "Tres salas: los pequeños, los medianos y el altar del Guardián",

	-- Boca de la cueva (en el mapa del Bosque): al entrar en Trigger (el fondo del túnel,
	-- detrás de la bruma oscura) te lleva dentro; al salir de la cueva apareces en Exit,
	-- en el camino, mirando a la pradera. Guide: a dónde apunta la guía del tutorial.
	Entrance = {
		Trigger = { MinX = -140, MaxX = -132, MinZ = 12, MaxZ = 28, Height = 24 },
		Exit = { Position = Vector3.new(-110, 0, 20), Facing = Vector3.new(1, 0, 0) },
		Guide = Vector3.new(-126, 8, 20),
	},

	-- Dónde apareces dentro (sala 1, junto al portal de salida), mirando a la cueva.
	Arrival = { Position = Vector3.new(-928, 0, 4), Facing = Vector3.new(-1, 0, 0) },

	-- Salas en orden. Rect: suelo de la sala (las paredes van por dentro); Height: alto del
	-- techo; Skylights: huecos del techo (rectángulos en bordes de bloque) por los que entra
	-- un haz de luz. Crystal / Mushroom: colores de lo que brilla.
	Rooms = {
		{
			Id = "Nest",
			Name = "El Nido",
			Label = "SALA 1 · EL NIDO",
			Text = "Espinillos pequeños",
			Rect = { MinX = -1004, MaxX = -908, MinZ = -36, MaxZ = 44 },
			Height = 40,
			Skylights = { { MinX = -972, MaxX = -964, MinZ = 12, MaxZ = 20 }, { MinX = -996, MaxX = -988, MinZ = -20, MaxZ = -12 } },
			Crystal = { RGB(96, 224, 255), RGB(120, 255, 200) },
			Mushroom = { RGB(110, 236, 255), RGB(255, 140, 220) },
		},
		{
			Id = "Gallery",
			Name = "La Galería",
			Label = "SALA 2 · LA GALERÍA",
			Text = "Brutos de Corteza",
			Rect = { MinX = -1132, MaxX = -1036, MinZ = -36, MaxZ = 60 },
			Height = 40,
			Skylights = { { MinX = -1076, MaxX = -1068, MinZ = 36, MaxZ = 44 }, { MinX = -1100, MaxX = -1092, MinZ = -20, MaxZ = -12 } },
			Crystal = { RGB(196, 128, 255), RGB(150, 110, 240) },
			Mushroom = { RGB(196, 128, 255), RGB(110, 236, 255) },
		},
		{
			Id = "Altar",
			Name = "El Altar",
			Label = "SALA 3 · EL ALTAR",
			Text = "Oleadas del Guardián",
			Rect = { MinX = -1276, MaxX = -1164, MinZ = -76, MaxZ = 36 },
			Height = 48,
			-- Encima del altar: un hueco grande por el que sale su columna de luz
			Skylights = { { MinX = -1236, MaxX = -1204, MinZ = -36, MaxZ = -4 } },
			Crystal = { RGB(255, 120, 40), RGB(255, 170, 60) },
			Mushroom = { RGB(255, 120, 40), RGB(140, 255, 58) },
			Altar = true, -- aquí está el altar de las oleadas (WaveConfig.Places de su zona)
		},
	},

	-- Puertas: una al principio de cada pasillo (Corridor), que se abre al derrotar Kills bichos
	-- de la sala Room (cuentan los que derrotas tú o en los que has hecho daño). Position:
	-- centro de la puerta en el suelo; Facing: hacia la sala de la que se viene (allí se ve
	-- cuántos llevas); Back: a dónde vuelve quien aparezca detrás con la puerta cerrada.
	-- MiniBoss = true: solo cuenta el mini-jefe de la sala (Kills = 1); Ask: lo que pide.
	Gates = {
		{
			Corridor = 1,
			Room = 1,
			Kills = 15,
			Opens = "la Galería",
			Enemies = "Espinillos",
			Position = Vector3.new(-1008, 0, 28),
			Facing = Vector3.new(1, 0, 0),
			Back = Vector3.new(-992, 0, 28),
		},
		{
			Corridor = 2,
			Room = 2,
			Kills = 6,
			Opens = "el Altar",
			Enemies = "Brutos",
			Position = Vector3.new(-1136, 0, -20),
			Facing = Vector3.new(1, 0, 0),
			Back = Vector3.new(-1120, 0, -20),
		},
	},

	-- Los bichos de la cueva (los del mundo, no los de las oleadas) tienen más vida, pegan
	-- más fuerte y dan más botín que los de fuera.
	Strength = { Health = 1.6, Damage = 1.5, Reward = 1.3 },

	-- Pasillos entre salas (From -> To), de 2 bloques de ancho y Height de alto.
	Corridors = {
		{ From = 1, To = 2, Rect = { MinX = -1036, MaxX = -1004, MinZ = 20, MaxZ = 36 }, Height = 24 },
		{ From = 2, To = 3, Rect = { MinX = -1164, MaxX = -1132, MinZ = -28, MaxZ = -12 }, Height = 24 },
	},

	-- Portales de salida: en el suelo junto a una pared, mirando hacia Facing.
	Exits = {
		{ Room = 1, Position = Vector3.new(-913, 0, 4), Facing = Vector3.new(-1, 0, 0) },
		{ Room = 3, Position = Vector3.new(-1271, 0, -20), Facing = Vector3.new(1, 0, 0) },
	},

	-- Colores de la piedra (suelo, paredes y techo, rocas), del haz de luz de las claraboyas,
	-- de los portales y de la bruma de la boca, y el tinte de dentro (cliente).
	Theme = {
		Stone = { RGB(92, 98, 128), RGB(78, 84, 112) },
		Rock = { RGB(104, 108, 140), RGB(86, 90, 120) },
		Dark = { RGB(70, 74, 100), RGB(58, 62, 86) },
		Shaft = RGB(255, 244, 205),
		Portal = RGB(150, 90, 255),
		Mist = RGB(150, 90, 255),
		Tint = { Brightness = -0.02, Contrast = 0.06, Saturation = 0, TintColor = RGB(240, 244, 255) },
	},
}

-- ¿Es un Vector3? (también los de mentira de las pruebas: una tabla con X, Y y Z)
local function isVector3(value: any): boolean
	if typeof(value) == "Vector3" then
		return true
	end
	return type(value) == "table" and type(value.X) == "number" and type(value.Y) == "number" and type(value.Z) == "number" and value.MinX == nil
end

-- Copia de una cueva movida `dz` en Z (posiciones y rectángulos; las direcciones no).
local function shifted(value: any, dz: number, key: any?): any
	if isVector3(value) then
		return if key == "Facing" then value else Vector3.new(value.X, value.Y, value.Z + dz)
	elseif type(value) == "table" then
		local copy = {}
		for k, v in value do
			copy[k] = shifted(v, dz, k)
		end
		if type(copy.MinZ) == "number" and type(copy.MaxZ) == "number" then
			copy.MinZ += dz
			copy.MaxZ += dz
		end
		return copy
	end
	return value
end

-- Boca de las cuevas del Valle y la Caldera: un montículo de roca de 4 × 3 bloques con el
-- túnel en medio, a la derecha de la llegada desde el portal (Offset (44, -124) de su zona,
-- donde estaba el círculo de las oleadas). `centerZ`: Z del mundo del centro de la zona.
local function mound(centerZ: number)
	local z = centerZ - 124
	return {
		Trigger = { MinX = 52, MaxX = 60, MinZ = z - 8, MaxZ = z + 8, Height = 16 },
		Exit = { Position = Vector3.new(32, 0, z), Facing = Vector3.new(-1, 0, 0) },
		Guide = Vector3.new(40, 8, z),
		-- Para CaveDungeon: frente del túnel (X = 44) mirando al oeste (-X), 2 bloques de ancho
		-- y de alto, y el montículo 3 bloques de fondo y 4 de ancho.
		Mound = { Front = Vector3.new(44, 0, z), Facing = Vector3.new(-1, 0, 0), Width = 16, Height = 16, Depth = 24, Span = 32 },
	}
end

-- Valle Morado: Cueva de Amatista -------------------------------------------------------------

local VALLEY = shifted(FOREST, 320)
VALLEY.Name = "Cueva de Amatista"
VALLEY.Icon = "💎"
VALLEY.Zone = "CrystalValley"
VALLEY.Subtitle = "Pinchos de cristal, un Gólem Guardián y el trono del Coloso"
VALLEY.Entrance = mound(295)
VALLEY.Rooms[1].Name, VALLEY.Rooms[1].Label, VALLEY.Rooms[1].Text = "La Cantera", "SALA 1 · LA CANTERA", "Fragmentos · ¡cuidado con los pinchos!"
VALLEY.Rooms[2].Name, VALLEY.Rooms[2].Label, VALLEY.Rooms[2].Text = "La Geoda", "SALA 2 · LA GEODA", "El Gólem Guardián"
VALLEY.Rooms[3].Name, VALLEY.Rooms[3].Label, VALLEY.Rooms[3].Text = "El Trono", "SALA 3 · EL TRONO", "Oleadas del Coloso"
VALLEY.Rooms[1].Crystal, VALLEY.Rooms[1].Mushroom = { RGB(200, 140, 255), RGB(140, 220, 255) }, { RGB(220, 160, 255), RGB(140, 220, 255) }
VALLEY.Rooms[2].Crystal, VALLEY.Rooms[2].Mushroom = { RGB(170, 110, 255), RGB(120, 200, 255) }, { RGB(170, 110, 255), RGB(255, 170, 240) }
VALLEY.Rooms[3].Crystal, VALLEY.Rooms[3].Mushroom = { RGB(190, 120, 255), RGB(230, 190, 255) }, { RGB(190, 120, 255), RGB(140, 220, 255) }
VALLEY.Gates[1].Kills, VALLEY.Gates[1].Opens, VALLEY.Gates[1].Enemies = 20, "la Geoda", "Fragmentos"
VALLEY.Gates[2].Kills, VALLEY.Gates[2].Opens, VALLEY.Gates[2].Enemies = 1, "el Trono", "Gólem Guardián"
VALLEY.Gates[2].MiniBoss = true
VALLEY.Gates[2].Ask = "Derrota al Gólem Guardián"
VALLEY.Strength = { Health = 2.2, Damage = 1.8, Reward = 1.6 }
-- Mini-jefe de la sala 2 (EnemyService lo crea): un bicho de la zona más grande, con más
-- vida (×Health además de la de la cueva: unos 3 500 aquí y 12 000 en la Caldera, por debajo
-- del jefe), que pega más y da más botín. Position: dónde vive.
VALLEY.MiniBoss = { Type = "GeodeGolem", Name = "👑 Gólem Guardián", Position = Vector3.new(-1084, 0, 332), Health = 2.5, Damage = 1.4, Reward = 6, Scale = 1.7 }
-- Parte de los pequeños de las salas que son élite (uno de cada round(1 / EliteChance),
-- siempre los mismos)
VALLEY.EliteChance = 0.25
-- Trampas: cada Interval (mín., máx.) segundos sale una junto a cada jugador de la cueva (a
-- Spread studs como mucho); avisa Warning segundos con un círculo de Radius y luego quita
-- Damage de la vida máxima a quien siga dentro.
VALLEY.Traps = { Kind = "Crystal", Name = "Pinchos de cristal", Interval = { 5, 8 }, Warning = 1.3, Radius = 6, Spread = 4, Damage = 0.15, Color = RGB(200, 140, 255) }
VALLEY.Theme = {
	Stone = { RGB(108, 94, 150), RGB(90, 78, 130) },
	Rock = { RGB(124, 110, 172), RGB(104, 92, 150) },
	Dark = { RGB(78, 66, 114), RGB(64, 54, 96) },
	Shaft = RGB(226, 206, 255),
	Portal = RGB(110, 200, 255),
	Mist = RGB(170, 110, 255),
	Tint = { Brightness = -0.02, Contrast = 0.07, Saturation = 0.05, TintColor = RGB(240, 232, 255) },
}

-- Caldera de Brasas: Forja de Magma ---------------------------------------------------------

local CALDERA = shifted(FOREST, 640)
CALDERA.Name = "Forja de Magma"
CALDERA.Icon = "🔥"
CALDERA.Zone = "EmberCaldera"
CALDERA.Subtitle = "Chorros de lava, el Gólem del Horno y el corazón del Titán"
CALDERA.Entrance = mound(615)
CALDERA.Rooms[1].Name, CALDERA.Rooms[1].Label, CALDERA.Rooms[1].Text = "La Fragua", "SALA 1 · LA FRAGUA", "Chispas · ¡cuidado con la lava!"
CALDERA.Rooms[2].Name, CALDERA.Rooms[2].Label, CALDERA.Rooms[2].Text = "El Horno", "SALA 2 · EL HORNO", "El Gólem del Horno"
CALDERA.Rooms[3].Name, CALDERA.Rooms[3].Label, CALDERA.Rooms[3].Text = "El Corazón", "SALA 3 · EL CORAZÓN", "Oleadas del Titán"
CALDERA.Rooms[1].Crystal, CALDERA.Rooms[1].Mushroom = { RGB(255, 130, 40), RGB(255, 200, 70) }, { RGB(255, 120, 40), RGB(255, 220, 90) }
CALDERA.Rooms[2].Crystal, CALDERA.Rooms[2].Mushroom = { RGB(255, 90, 30), RGB(255, 170, 50) }, { RGB(255, 90, 30), RGB(255, 200, 80) }
CALDERA.Rooms[3].Crystal, CALDERA.Rooms[3].Mushroom = { RGB(255, 70, 20), RGB(255, 190, 60) }, { RGB(255, 70, 20), RGB(255, 230, 120) }
CALDERA.Gates[1].Kills, CALDERA.Gates[1].Opens, CALDERA.Gates[1].Enemies = 25, "el Horno", "Chispas"
CALDERA.Gates[2].Kills, CALDERA.Gates[2].Opens, CALDERA.Gates[2].Enemies = 1, "el Corazón", "Gólem del Horno"
CALDERA.Gates[2].MiniBoss = true
CALDERA.Gates[2].Ask = "Derrota al Gólem del Horno"
CALDERA.Strength = { Health = 2.8, Damage = 2.2, Reward = 2 }
CALDERA.MiniBoss = { Type = "MagmaGolem", Name = "👑 Gólem del Horno", Position = Vector3.new(-1084, 0, 652), Health = 2, Damage = 1.5, Reward = 6, Scale = 1.8 }
CALDERA.EliteChance = 0.35
CALDERA.Traps = { Kind = "Lava", Name = "Chorro de lava", Interval = { 4, 6.5 }, Warning = 1.1, Radius = 7, Spread = 4, Damage = 0.22, Color = RGB(255, 110, 30) }
CALDERA.Theme = {
	Stone = { RGB(76, 58, 54), RGB(62, 46, 44) },
	Rock = { RGB(98, 68, 60), RGB(82, 56, 50) },
	Dark = { RGB(56, 40, 38), RGB(44, 32, 30) },
	Shaft = RGB(255, 196, 130),
	Portal = RGB(255, 130, 40),
	Mist = RGB(255, 110, 30),
	Tint = { Brightness = -0.01, Contrast = 0.08, Saturation = 0.06, TintColor = RGB(255, 236, 222) },
}

-- Tundra Helada: Gruta Glacial --------------------------------------------------------------

local TUNDRA = shifted(FOREST, 960)
TUNDRA.Name = "Gruta Glacial"
TUNDRA.Icon = "❄️"
TUNDRA.Zone = "FrozenTundra"
TUNDRA.Subtitle = "Carámbanos que caen, el Yeti Ancestral y el trono del Gólem de Hielo"
TUNDRA.Entrance = mound(935)
TUNDRA.Rooms[1].Name, TUNDRA.Rooms[1].Label, TUNDRA.Rooms[1].Text = "La Escarcha", "SALA 1 · LA ESCARCHA", "Lobos · ¡cuidado con los carámbanos!"
TUNDRA.Rooms[2].Name, TUNDRA.Rooms[2].Label, TUNDRA.Rooms[2].Text = "El Glaciar", "SALA 2 · EL GLACIAR", "El Yeti Ancestral"
TUNDRA.Rooms[3].Name, TUNDRA.Rooms[3].Label, TUNDRA.Rooms[3].Text = "El Trono Helado", "SALA 3 · EL TRONO HELADO", "Oleadas del Gólem de Hielo"
TUNDRA.Rooms[1].Crystal, TUNDRA.Rooms[1].Mushroom = { RGB(150, 220, 255), RGB(220, 245, 255) }, { RGB(170, 230, 255), RGB(255, 255, 255) }
TUNDRA.Rooms[2].Crystal, TUNDRA.Rooms[2].Mushroom = { RGB(110, 200, 255), RGB(190, 235, 255) }, { RGB(120, 210, 255), RGB(220, 240, 255) }
TUNDRA.Rooms[3].Crystal, TUNDRA.Rooms[3].Mushroom = { RGB(90, 180, 255), RGB(200, 240, 255) }, { RGB(100, 190, 255), RGB(180, 230, 255) }
TUNDRA.Gates[1].Kills, TUNDRA.Gates[1].Opens, TUNDRA.Gates[1].Enemies = 28, "el Glaciar", "Lobos"
TUNDRA.Gates[2].Kills, TUNDRA.Gates[2].Opens, TUNDRA.Gates[2].Enemies = 1, "el Trono Helado", "Yeti Ancestral"
TUNDRA.Gates[2].MiniBoss = true
TUNDRA.Gates[2].Ask = "Derrota al Yeti Ancestral"
TUNDRA.Strength = { Health = 3.2, Damage = 2.5, Reward = 2.4 }
TUNDRA.MiniBoss = { Type = "Yeti", Name = "👑 Yeti Ancestral", Position = Vector3.new(-1084, 0, 972), Health = 1.8, Damage = 1.5, Reward = 6, Scale = 1.8 }
TUNDRA.EliteChance = 0.4
-- Carámbanos: caen del techo donde avisa el círculo
TUNDRA.Traps = { Kind = "Ice", Name = "Carámbanos", Interval = { 4, 6 }, Warning = 1.1, Radius = 6.5, Spread = 4, Damage = 0.25, Color = RGB(150, 220, 255) }
TUNDRA.Theme = {
	Stone = { RGB(150, 170, 200), RGB(130, 150, 182) },
	Rock = { RGB(176, 196, 224), RGB(156, 176, 206) },
	Dark = { RGB(100, 118, 150), RGB(84, 100, 130) },
	Shaft = RGB(220, 240, 255),
	Portal = RGB(120, 210, 255),
	Mist = RGB(170, 220, 255),
	Tint = { Brightness = 0, Contrast = 0.06, Saturation = -0.05, TintColor = RGB(232, 244, 255) },
}

-- Todas -------------------------------------------------------------------------------------

local CaveConfig = {
	Order = { "Forest", "CrystalValley", "EmberCaldera", "FrozenTundra" },
	Caves = { Forest = FOREST, CrystalValley = VALLEY, EmberCaldera = CALDERA, FrozenTundra = TUNDRA },
	-- Distancia en Z entre las cuevas (la de los centros de las zonas)
	Shift = 320,

	-- Listas planas (se rellenan abajo)
	Rooms = {},
	Corridors = {},
	Gates = {},
	Exits = {},

	-- Portales de salida: lo cerca que hay que pasar para usarlos.
	ExitRadius = 4.5,

	-- Viaje: fundido a negro antes de moverte, espera mínima entre dos viajes.
	Travel = { FadeSeconds = 0.35, Cooldown = 2.5, CheckInterval = 0.15 },

	-- Ambiente dentro (cliente): sonidos al cruzar y al entrar en cada sala.
	Sounds = {
		Enter = { Id = "rbxassetid://9126229267", Volume = 0.5, Pitch = 0.7 }, -- ráfaga al cruzar
		Room = { Id = "rbxassetid://9116394876", Volume = 0.35, Pitch = 1.2 }, -- campanillas al entrar en una sala
		Count = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.3, Pitch = 1.3 }, -- uno más para la puerta
		GateOpen = { Id = "rbxassetid://9114630316", Volume = 0.55, Pitch = 0.7 }, -- gong grave al abrirse
		GateRumble = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.45, Pitch = 0.5 }, -- la roca bajando
		TrapWarn = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.35, Pitch = 0.6 }, -- aviso de trampa
		Crystal = { Id = "rbxassetid://9116394876", Volume = 0.55, Pitch = 0.5 }, -- pinchos de cristal
		Lava = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.5, Pitch = 0.8 }, -- chorro de lava
		Ice = { Id = "rbxassetid://9116394876", Volume = 0.6, Pitch = 1.5 }, -- carámbano que se rompe
	},
}

-- Cada cueva con sus salas, pasillos, puertas y salidas en las listas planas (índices
-- globales). Rooms[i].Cave, .Local (1..3); Gates[i].Cave, .Local; FirstRoom / FirstGate: dónde
-- empiezan las suyas.
for _, caveId in CaveConfig.Order do
	local cave = CaveConfig.Caves[caveId]
	cave.Id = caveId
	local roomBase, corridorBase, gateBase = #CaveConfig.Rooms, #CaveConfig.Corridors, #CaveConfig.Gates
	cave.FirstRoom, cave.FirstCorridor, cave.FirstGate = roomBase + 1, corridorBase + 1, gateBase + 1
	for index, room in cave.Rooms do
		room.Cave = caveId
		room.Local = index
		table.insert(CaveConfig.Rooms, room)
	end
	for _, corridor in cave.Corridors do
		local flat = table.clone(corridor)
		flat.Cave = caveId
		flat.From += roomBase
		flat.To += roomBase
		table.insert(CaveConfig.Corridors, flat)
	end
	for index, gate in cave.Gates do
		local flat = table.clone(gate)
		flat.Cave = caveId
		flat.Local = index
		flat.Room += roomBase
		flat.Corridor += corridorBase
		table.insert(CaveConfig.Gates, flat)
	end
	for _, exit in cave.Exits do
		local flat = table.clone(exit)
		flat.Cave = caveId
		flat.Room += roomBase
		table.insert(CaveConfig.Exits, flat)
	end
end

-- La del Bosque, como antes (tutorial, carteles): CaveConfig.Name, Zone, Entrance...
CaveConfig.Name = FOREST.Name
CaveConfig.Zone = FOREST.Zone
CaveConfig.Entrance = FOREST.Entrance
CaveConfig.Arrival = FOREST.Arrival
CaveConfig.Strength = FOREST.Strength
CaveConfig.Tint = FOREST.Theme.Tint

return CaveConfig
