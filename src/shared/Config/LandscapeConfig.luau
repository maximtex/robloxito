-- Paisaje de las zonas (LandscapeService): caminos de piedra, faroles, bancos, carteles,
-- vallas, bosque variado, estanque, arboleda de setas gigantes, puntos de referencia,
-- montañas que cierran el horizonte y un límite invisible. Solo decorativo.
--
-- Posiciones RELATIVAS al centro de cada zona (ZoneConfig), en X/Z, igual que WorldConfig
-- (Bosque: el cristal) y ValleyConfig. La colocación al azar usa una semilla fija y
-- respeta las zonas de juego (LandscapeLayout.obstacles): spawn, cristal, altares, jardines
-- de huevos, portales, arenas, zona de cada enemigo y lo que ya construyen
-- WorldService/ValleyService. Los jardines de huevos (EggConfig.Gardens) también se
-- decoran aquí (seto o cristales, arco, fuente, faroles, bancos y jardineras).

local V2 = Vector2.new

local LandscapeConfig = {
	ModelName = "Landscape",
	-- El mapa estilo simulador (StudFloor) solo usa el límite invisible de cada zona: con
	-- false, LandscapeService no construye árboles, caminos, montañas, jardines, pueblo ni
	-- naturaleza de LandscapeLayout (la prueba "landscape" omite sus comprobaciones).
	BuildsDecor = false,

	Colors = {
		Stone = Color3.fromRGB(152, 150, 138),
		DarkStone = Color3.fromRGB(104, 104, 98),
		Wood = Color3.fromRGB(128, 92, 60),
		DarkWood = Color3.fromRGB(92, 66, 44),
		Metal = Color3.fromRGB(56, 58, 62),
		LampGlow = Color3.fromRGB(255, 214, 140),
		SignText = Color3.fromRGB(58, 40, 24),
		Pine = { Color3.fromRGB(52, 108, 64), Color3.fromRGB(44, 96, 58), Color3.fromRGB(62, 120, 70) },
		Oak = { Color3.fromRGB(86, 152, 70), Color3.fromRGB(70, 132, 62), Color3.fromRGB(104, 170, 80) },
		Birch = { Color3.fromRGB(150, 196, 90), Color3.fromRGB(176, 206, 104) },
		BirchBark = Color3.fromRGB(232, 228, 216),
		Bush = { Color3.fromRGB(78, 140, 62), Color3.fromRGB(96, 156, 70), Color3.fromRGB(66, 124, 58) },
		Boulder = { Color3.fromRGB(122, 126, 112), Color3.fromRGB(136, 136, 124), Color3.fromRGB(110, 114, 104) },
		GiantCaps = { Color3.fromRGB(255, 150, 190), Color3.fromRGB(110, 226, 210), Color3.fromRGB(255, 204, 110), Color3.fromRGB(190, 150, 255) },
		Snow = Color3.fromRGB(240, 244, 250),
		Water = Color3.fromRGB(70, 150, 170),
		Lily = Color3.fromRGB(86, 150, 70),
		LilyFlower = Color3.fromRGB(255, 186, 214),
		Reed = Color3.fromRGB(120, 140, 70),
		Hedge = { Color3.fromRGB(58, 118, 54), Color3.fromRGB(66, 128, 58), Color3.fromRGB(52, 108, 50) },
		Marble = Color3.fromRGB(238, 234, 222),
		FountainStone = Color3.fromRGB(176, 172, 158),
		FountainWater = Color3.fromRGB(104, 186, 220),
		Gold = Color3.fromRGB(244, 204, 110),
		GardenGlow = Color3.fromRGB(255, 226, 170),
		-- Tinte de las copas de los modelos (MapAssets): verdes vivos y algún acento de
		-- color (cerezo, lila, dorado) como en los simuladores.
		TreeTints = {
			Color3.fromRGB(110, 170, 70), Color3.fromRGB(140, 200, 80), Color3.fromRGB(170, 215, 90), Color3.fromRGB(124, 186, 76),
		},
		BorderTints = { Color3.fromRGB(70, 130, 70), Color3.fromRGB(86, 146, 76), Color3.fromRGB(64, 118, 72) },
		AccentTints = { Color3.fromRGB(240, 150, 190), Color3.fromRGB(200, 160, 240), Color3.fromRGB(240, 200, 100) },
		AccentChance = 0.12,
		BushTints = { Color3.fromRGB(110, 175, 75), Color3.fromRGB(140, 200, 85), Color3.fromRGB(240, 160, 200) },
		ValleyTints = { Color3.fromRGB(190, 150, 250), Color3.fromRGB(140, 200, 250), Color3.fromRGB(240, 160, 230), Color3.fromRGB(150, 230, 220) },
		-- Caldera: copas de fuego (rojo, naranja y ámbar) con ascuas de neón entre las ramas.
		EmberTints = { Color3.fromRGB(214, 84, 44), Color3.fromRGB(240, 130, 50), Color3.fromRGB(196, 60, 52), Color3.fromRGB(250, 170, 70) },
		EmberGems = { Color3.fromRGB(255, 118, 36), Color3.fromRGB(255, 186, 70) },
		CharredBark = Color3.fromRGB(58, 46, 44),
		MagicTint = Color3.fromRGB(110, 214, 190), -- árbol ancestral
		LanternWood = Color3.fromRGB(122, 86, 56),
	},

	-- Tamaño de los modelos de la Creator Store (MapAssets) a escala 1 del paisaje.
	AssetHeights = { Tree = 20, BorderTree = 26, Bush = 4.2, Rock = 3.4, ValleyTree = 18, EmberTree = 17, AncientTree = 58, WorldTree = 19 },

	-- Jardines de huevos (EggConfig.Gardens): medidas por estilo. Ángulos en grados a cada
	-- lado de la entrada; radios relativos al del jardín (negativo = hacia dentro).
	Gardens = {
		-- Bosque: seto recortado con una entrada bajo un arco con el nombre, fuente con una
		-- estatua de huevo en el centro, faroles, bancos y jardineras entre los santuarios.
		Meadow = {
			Floor = "Cobblestone", FloorInset = 1.6,
			Ring = "Hedge", RingSegment = 3, RingHeight = 2.4, RingThickness = 1.6,
			GateHalfAngle = 15, GateHeight = 8,
			LampAngles = { 40 }, LampRadius = -1.8,
			BenchAngles = { 85 }, BenchRadius = -2.6,
			Planters = true, PlanterRadius = -2.2, PlanterSize = 2.2,
			Fountain = { Radius = 3.3 },
			Motes = { Rate = 5, Color = Color3.fromRGB(255, 214, 236), Second = Color3.fromRGB(255, 240, 180) },
		},
		-- Bosque (rediseño de Santiago, EggGardenTerrace): terraza de piedra con rosa de los
		-- vientos, muro bajo con seto, columnas con huevos de seto, puerta lunar y estanque con
		-- el Nido Mayor. Faroles a 24° y 90° de la entrada, bancos a 60° y macetas entre
		-- santuarios (LandscapeLayout las coloca; la terraza las construye a su estilo).
		Terrace = {
			Floor = "Cobblestone", FloorInset = 1.6,
			Ring = "Hedge", RingSegment = 2, RingHeight = 2.9, RingThickness = 1.6,
			GateHalfAngle = 20, GateHeight = 10,
			LampAngles = { 24, 90 }, LampRadius = -2.7,
			BenchAngles = { 60 }, BenchRadius = -3.4,
			Planters = true, PlanterRadius = -3, PlanterSize = 2.2,
			Fountain = { Radius = 4.4 },
			Motes = { Rate = 5, Color = Color3.fromRGB(255, 214, 236), Second = Color3.fromRGB(255, 240, 180) },
		},
		-- Valle: anillo de cristales luminosos con dos grandes a la entrada y faroles fuera.
		Crystal = {
			Floor = "Pavement", FloorInset = 0.5,
			Ring = "Crystals", RingSegment = 2.6, RingHeight = 3.2,
			GateHalfAngle = 28, GateHeight = 7,
			LampAngles = { 32 }, LampRadius = 2,
			BenchAngles = {}, BenchRadius = 0,
			Planters = false,
			Fountain = nil,
			Motes = { Rate = 4, Color = Color3.fromRGB(200, 170, 255), Second = Color3.fromRGB(150, 220, 255) },
		},
		-- Caldera: suelo de ladrillo y anillo de cristales de lava y obsidiana.
		Ember = {
			Floor = "Brick", FloorInset = 0.5,
			Ring = "Crystals", RingSegment = 2.6, RingHeight = 3.4,
			RingColors = { Color3.fromRGB(255, 118, 36), Color3.fromRGB(46, 36, 56), Color3.fromRGB(255, 186, 70) },
			Glow = Color3.fromRGB(255, 150, 70),
			Sign = { Icon = "🔥", Color = Color3.fromRGB(150, 60, 40), Text = Color3.fromRGB(255, 240, 220), Stroke = Color3.fromRGB(90, 30, 20) },
			PaintOver = { "Basalt" },
			GateHalfAngle = 28, GateHeight = 7,
			LampAngles = { 32 }, LampRadius = 2,
			BenchAngles = {}, BenchRadius = 0,
			Planters = false,
			Fountain = nil,
			Motes = { Rate = 5, Color = Color3.fromRGB(255, 150, 60), Second = Color3.fromRGB(255, 214, 110) },
		},
	},

	-- Límite invisible (paredes sin colisión de cámara) para no caer por el borde del mundo.
	Boundary = { Segments = 28, Height = 90, Thickness = 4 },

	Forest = {
		Zone = "Forest",
		BoundaryRadius = 170,

		-- Caminos (polilíneas X, Z). Material del terreno y anchura. Los faroles se reparten
		-- a lo largo de los que tienen Lamps.
		Paths = {
			{ Name = "WestTrail", Material = "Cobblestone", Width = 4.5, Lamps = true, Points = { V2(-4, 32), V2(-12, 24), V2(-26, 18), V2(-36, 8), V2(-50, 26), V2(-61.3, 40.9), V2(-71, 50.6) } },
			-- Del spawn a la entrada del Jardín de los Huevos (EggConfig.Gardens.Forest).
			{ Name = "EggTrail", Material = "Cobblestone", Width = 4.5, Lamps = true, Points = { V2(3, 30), V2(12, 30), V2(23, 30) } },
			-- De la plaza del pueblo (salida este) al embarcadero del estanque.
			{ Name = "PondTrail", Material = "Cobblestone", Width = 4, Lamps = true, Points = { V2(14, 84), V2(24, 85), V2(32, 88) } },
			-- Sale de la calle del pueblo y bordea el seto sur del jardín hasta la pradera.
			{ Name = "MeadowTrail", Material = "Cobblestone", Width = 4, Lamps = true, Points = { V2(4, 48), V2(24, 47), V2(40, 50), V2(52, 52), V2(55.7, 48.3) } },
			{ Name = "BruteTrailWest", Material = "Ground", Width = 3.5, Points = { V2(-36, 4), V2(-57.4, -21.8), V2(-74.7, -25.5) } },
			{ Name = "BruteTrailEast", Material = "Ground", Width = 3.5, Points = { V2(12, 4), V2(24, 8), V2(46, 10), V2(64.2, -3.9), V2(78.2, -14.5) } },
			-- Senderos del norte (WildsConfig): por el oeste del árbol ancestral hasta el río,
			-- el Puente del Norte y las Ruinas; ramales a la cascada y a la arboleda de setas, y
			-- del Bruto del este al campamento del lago.
			{ Name = "NorthTrail", Material = "Ground", Width = 4, Points = { V2(-57.4, -21.8), V2(-48.4, -43.6), V2(-38.3, -68.4), V2(-29.7, -87.5), V2(-12.1, -97.5), V2(0, -98.1), V2(0, -120.1), V2(2.3, -122.4) } },
			{ Name = "FallsTrail", Material = "Ground", Width = 3.5, Points = { V2(-12.1, -97.5), V2(-25.8, -97), V2(-40.9, -95.5), V2(-47.4, -88.9), V2(-53.4, -94.9) } },
			{ Name = "GroveTrail", Material = "Ground", Width = 3.5, Points = { V2(-38.3, -68.4), V2(-54.5, -72.1), V2(-67.4, -73.8) } },
			{ Name = "LakeTrail", Material = "Ground", Width = 3.5, Points = { V2(78.2, -14.5), V2(88.5, -36.4), V2(92.9, -57.4), V2(99, -62), V2(94, -66) } },
		},
		LampSpacing = 20,
		LampGap = 1.6, -- del borde del camino al farol

		-- Bancos (X, Z, giro en grados: 0 = mirando a -Z, 90 = mirando a -X).
		Benches = {
			Vector3.new(26, 92, -129), Vector3.new(44, 90, 141), Vector3.new(-30, 22, -45),
			Vector3.new(-58.4, 27.2, -132),
		},
		-- Jardineras de flores a los lados del arco del camino. (X, Z, tamaño)
		Planters = { Vector3.new(-10, 19, 2.6), Vector3.new(10, 19, 2.6) },
		-- Carteles: posición y flechas (texto y hacia qué punto apuntan).
		Signs = {
			{ Position = V2(-10, 33), Arrows = { { Text = "⚔ Guardián del Bosque", Toward = V2(-71, 50.6) }, { Text = "🪵 Bruto de Corteza", Toward = V2(-36, 8) } } },
			{ Position = V2(10, 34), Arrows = { { Text = "🥚 Jardín de los Huevos", Toward = V2(37, 30) }, { Text = "🌸 Pradera Este", Toward = V2(24, 47) } } },
			{ Position = V2(9, 41), Arrows = { { Text = "🏘 Pueblo y 🌀 Valle", Toward = V2(0, 84) }, { Text = "💧 Estanque", Toward = V2(36, 100) } } },
			{ Position = V2(-40, 14), Arrows = { { Text = "⚔ Círculo del Guardián", Toward = V2(-71, 50.6) }, { Text = "🪵 Bruto de Corteza", Toward = V2(-74.7, -25.5) }, { Text = "💧 Cascada y 🏛 Ruinas", Toward = V2(-57.4, -21.8) } } },
			{ Position = V2(-52, -24), Arrows = { { Text = "💧 Cascada y 🏛 Ruinas", Toward = V2(-48.4, -43.6) }, { Text = "🪵 Bruto de Corteza", Toward = V2(-74.7, -25.5) } } },
			{ Position = V2(-33.5, -65.2), Arrows = { { Text = "🍄 Arboleda de Setas", Toward = V2(-67.4, -73.8) }, { Text = "💧 Cascada y 🏛 Ruinas", Toward = V2(-29.7, -87.5) } } },
			{ Position = V2(-14, -91), Arrows = { { Text = "💧 Cascada del Eco", Toward = V2(-40.9, -95.5) }, { Text = "🏛 Ruinas Antiguas", Toward = V2(0, -120.1) } } },
			{ Position = V2(95.4, -42.6), Arrows = { { Text = "⛺ Campamento y Lago", Toward = V2(92.9, -57.4) } } },
		},
		-- Estanque con nenúfares, juncos y un pequeño embarcadero.
		Pond = { Center = V2(36, 100), Radius = 11, Depth = 4, Fence = true },
		-- Arboleda de setas gigantes (con luciérnagas).
		MushroomGrove = { Center = V2(-83.4, -81.8), Radius = 16, Count = 7 },
		-- Torre del vigía junto a la arena del Guardián.
		Watchtower = { Position = V2(-53.6, 81.3), Height = 22, Diameter = 7 },
		-- Pico de cristal en lo alto de la colina noreste: se ve desde todo el bosque.
		CrystalSpire = { Position = V2(116, 100), Height = 32 },

		-- Montañas que cierran el horizonte (ángulo en grados, distancia, radio). Nieve en la cima.
		Mountains = {
			Count = 26, Distance = 257, MinRadius = 68, MaxRadius = 90, Rise = 0.7, Snow = 0.36,
		},

		-- Bosque variado: arboledas en el anillo exterior (fuera de las zonas de juego), una
		-- franja densa de pinos delante del límite (lo esconde) y decoración sin colisión
		-- también cerca del centro (fuera de caminos y zonas clave). Clusters: arboledas.
		Scatter = {
			{ Kind = "Tree", Count = 100, MinRadius = 74.2, MaxRadius = 148.8, Clusters = 18, ClusterRadius = 17, Clearance = 3, Solid = true },
			{ Kind = "Tree", Count = 100, MinRadius = 149.5, MaxRadius = 161.5, Clearance = 1.5, Solid = true, Mix = { Pine = 0.75, Oak = 0.25 } },
			{ Kind = "Boulder", Count = 16, MinRadius = 67.1, MaxRadius = 159.4, Clearance = 3, Solid = true },
			{ Kind = "Log", Count = 4, MinRadius = 81.3, MaxRadius = 152.3, Clearance = 3, Solid = true },
			{ Kind = "Stump", Count = 6, MinRadius = 81.3, MaxRadius = 152.3, Clearance = 2.5, Solid = true },
			{ Kind = "Bush", Count = 105, MinRadius = 22, MaxRadius = 159.4, Clusters = 26, ClusterRadius = 12, Clearance = 1.5, Solid = false },
			{ Kind = "MushroomPatch", Count = 8, MinRadius = 60, MaxRadius = 152.3, Clearance = 2, Solid = false },
			{ Kind = "FlowerPatch", Count = 70, MinRadius = 40, MaxRadius = 109.7, Clusters = 12, ClusterRadius = 9, Clearance = 1.5, Solid = false },
		},
		TreeMix = { Oak = 0.5, Pine = 0.35, Birch = 0.15 },
		Seed = 9137,
	},

	Valley = {
		Zone = "CrystalValley",
		BoundaryRadius = 160,

		Paths = {
			{ Name = "ColossusTrail", Material = "Pavement", Width = 4.5, Lamps = true, Points = { V2(2, -10), V2(20, -13), V2(36, -17), V2(48, -22), V2(63, -12) } },
			{ Name = "ShardTrail", Material = "Pavement", Width = 4, Lamps = true, Points = { V2(-2, 2), V2(-26, -6), V2(-46, -22) } },
		},
		LampSpacing = 18,
		LampGap = 1.6,
		Benches = {},
		Planters = {},
		Signs = {
			{ Position = V2(6, -6), Arrows = { { Text = "⚔ Trono de Amatista", Toward = V2(63, -12) }, { Text = "💎 Gran Geoda", Toward = V2(0, -62) } } },
			{ Position = V2(14, 46), Arrows = { { Text = "🌋 Caldera de Brasas", Toward = V2(36, 46) } } },
		},
		-- Grandes agujas de cristal (puntos de referencia). (X, Z, escala)
		Spires = { Vector3.new(-108, 30, 1.6), Vector3.new(108, -62, 1.8), Vector3.new(70, 96, 1.5), Vector3.new(-60, -104, 1.7) },
		-- Arco de cristal sobre el camino del jefe.
		CrystalArch = { Position = V2(36, -17), Width = 10, Height = 9 },
		-- Cristales flotantes alrededor de la geoda.
		FloatingCrystals = { Center = V2(0, -62), Radius = 20, Count = 7, MinHeight = 9, MaxHeight = 16 },
		-- Lago de cristal: agua con piedras luminosas alrededor.
		CrystalPool = { Center = V2(40, 72), Radius = 8, Depth = 4 },
		Mountains = nil, -- el valle ya tiene las suyas (ValleyConfig)
		Scatter = {
			{ Kind = "CrystalTree", Count = 46, MinRadius = 70, MaxRadius = 148, Clusters = 11, ClusterRadius = 13, Clearance = 3, Solid = true },
			{ Kind = "Boulder", Count = 22, MinRadius = 60, MaxRadius = 148, Clearance = 3, Solid = true },
			{ Kind = "Shards", Count = 46, MinRadius = 20, MaxRadius = 148, Clearance = 2, Solid = false },
		},
		Seed = 6211,
	},

	Caldera = {
		Zone = "EmberCaldera",
		BoundaryRadius = 160,
		-- Material del suelo sobre el que se pintan caminos y jardín (por defecto, hierba).
		PaintOver = { "Basalt" },
		LampGlow = Color3.fromRGB(255, 150, 70),
		BoulderColors = { Color3.fromRGB(84, 68, 64), Color3.fromRGB(70, 58, 56), Color3.fromRGB(100, 82, 76) },
		RockTint = Color3.fromRGB(84, 70, 66), -- modelos de roca (MapAssets) en basalto oscuro
		ShardColors = { Color3.fromRGB(255, 118, 36), Color3.fromRGB(255, 186, 70), Color3.fromRGB(224, 64, 30) },
		-- Agujas de obsidiana (cuerpo oscuro) con cristales de lava a los lados.
		SpireColors = { Color3.fromRGB(46, 36, 56), Color3.fromRGB(255, 118, 36), Color3.fromRGB(64, 44, 70) },
		SpireGlow = false,
		FloatingColors = { Color3.fromRGB(255, 118, 36), Color3.fromRGB(255, 186, 70), Color3.fromRGB(224, 64, 30) },

		Paths = {
			{ Name = "GolemTrailWest", Material = "Salt", Width = 4, Lamps = true, Points = { V2(-2, -30), V2(-30, -40), V2(-60, -30), V2(-86, -16) } },
			{ Name = "GolemTrailEast", Material = "Salt", Width = 4, Lamps = true, Points = { V2(2, -44), V2(30, -50), V2(60, -44), V2(82, -34) } },
		},
		LampSpacing = 18,
		LampGap = 1.6,
		Benches = {},
		Planters = {},
		Signs = {
			{ Position = V2(6, -4), Arrows = { { Text = "⚔ Corazón de la Caldera", Toward = V2(0, -94) }, { Text = "🥚 Forja de Huevos", Toward = V2(24, 10) } } },
			{ Position = V2(-8, 8), Arrows = { { Text = "🌋 Lago de Lava", Toward = V2(-46, 8) }, { Text = "⚔ Gólems de Magma", Toward = V2(-96, -14) } } },
		},
		-- Agujas de obsidiana (puntos de referencia). (X, Z, escala)
		Spires = { Vector3.new(-112, -40, 1.5), Vector3.new(112, 24, 1.6), Vector3.new(72, -112, 1.4), Vector3.new(-84, 100, 1.5) },
		-- Ascuas flotando sobre la arena del Titán.
		FloatingCrystals = { Center = V2(0, -94), Radius = 27, Count = 9, MinHeight = 10, MaxHeight = 18 },
		Mountains = nil, -- la caldera ya tiene las suyas (CalderaConfig)
		Scatter = {
			{ Kind = "EmberTree", Count = 40, MinRadius = 70, MaxRadius = 148, Clusters = 10, ClusterRadius = 13, Clearance = 3, Solid = true },
			{ Kind = "Boulder", Count = 26, MinRadius = 50, MaxRadius = 148, Clearance = 3, Solid = true },
			{ Kind = "Shards", Count = 40, MinRadius = 20, MaxRadius = 148, Clearance = 2, Solid = false },
		},
		Seed = 7411,
	},
}

return LandscapeConfig
