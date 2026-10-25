-- Cueva de los Espinillos por dentro (Bosque). La boca está en la colina oeste, al final del
-- camino de piedra que sale de la plaza (StudFloor.Zones.Forest.Cave). Al cruzarla, la
-- pantalla se funde a negro y apareces en OTRO sitio, lejos del mapa: tres salas unidas por
-- pasillos, todas abiertas (se va andando de una a otra):
--   1. El Nido: los pequeños (Espinillos Bebé y Espinillos). Aquí llegas.
--   2. La Galería: los medianos (Brutos de Corteza).
--   3. El Altar: el altar de las Oleadas del Guardián (WaveConfig.Places.Forest): salen
--      pequeños y medianos y, en la última oleada, el Guardián del Bosque.
-- En la sala 1 (junto a donde llegas) y en la 3 hay un portal de salida que te devuelve a la
-- boca de la cueva. Los bichos de las salas son los del Bosque (EnemyConfig.Zones.Forest).
-- La cueva sigue siendo el Bosque: está fuera de los cuadrados de las zonas y ZoneService la
-- cuenta como su zona por defecto.
-- Todo en coordenadas del mundo y en bordes de bloque (8k ± 4); las alturas, desde la cara
-- de arriba del suelo. Lo construye Server.Util.CaveDungeon; el viaje, CaveService; el
-- fundido, los carteles de cada sala y el ambiente, el cliente (CaveController). Lógica pura
-- (en qué sala estás) en Shared.CaveLogic.

local RGB = Color3.fromRGB

local CaveConfig = {
	Name = "Cueva de los Espinillos",
	Zone = "Forest",

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
			Altar = true, -- aquí está el altar de las oleadas (WaveConfig.Places.Forest)
		},
	},

	-- Pasillos entre salas (From -> To), de 2 bloques de ancho y Height de alto.
	Corridors = {
		{ From = 1, To = 2, Rect = { MinX = -1036, MaxX = -1004, MinZ = 20, MaxZ = 36 }, Height = 24 },
		{ From = 2, To = 3, Rect = { MinX = -1164, MaxX = -1132, MinZ = -28, MaxZ = -12 }, Height = 24 },
	},

	-- Portales de salida: en el suelo junto a una pared, mirando hacia Facing. Radius: lo
	-- cerca que hay que pasar para usarlo.
	Exits = {
		{ Room = 1, Position = Vector3.new(-913, 0, 4), Facing = Vector3.new(-1, 0, 0) },
		{ Room = 3, Position = Vector3.new(-1271, 0, -20), Facing = Vector3.new(1, 0, 0) },
	},
	ExitRadius = 4.5,

	-- Viaje: fundido a negro antes de moverte, espera mínima entre dos viajes.
	Travel = { FadeSeconds = 0.35, Cooldown = 2.5, CheckInterval = 0.15 },

	-- Ambiente dentro (cliente): sonidos al cruzar y al entrar en cada sala y un tinte un
	-- poco frío (casi neutro: los fuegos y los cristales naranjas siguen siendo naranjas).
	Sounds = {
		Enter = { Id = "rbxassetid://9126229267", Volume = 0.5, Pitch = 0.7 }, -- ráfaga al cruzar
		Room = { Id = "rbxassetid://9116394876", Volume = 0.35, Pitch = 1.2 }, -- campanillas al entrar en una sala
	},
	Tint = { Brightness = -0.02, Contrast = 0.06, Saturation = 0, TintColor = RGB(240, 244, 255) },
}

return CaveConfig
