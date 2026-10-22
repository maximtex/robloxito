-- Claro mágico alrededor del Cristal del Renacimiento. Solo decorativo.
--
-- Todas las posiciones son RELATIVAS al cristal (GeneratorConfig.Position, en X/Z):
-- X positivo = derecha vista desde el spawn, Z positivo = hacia el spawn (Z ≈ +25).
-- La superficie del terreno queda a la altura GeneratorConfig.Position.Y.
--
-- Zonas que se dejan libres a propósito (para futuras áreas y máquinas):
-- el claro este (X ≈ +25, Z ≈ 0..15) y la parte trasera entre las ruinas y el árbol ancestral.

local WorldConfig = {
	ModelName = "MeadowWorld",

	-- Estilo simulador colorido (como el juego de referencia): luz clara y pareja de primera
	-- hora de la tarde, ambiente neutro (no azul) para que los colores se vean pastel y tal
	-- cual son, sin saturación ni contraste extra, y poca bruma. WorldService la aplica al
	-- arrancar y DayNightController usa Ambient y OutdoorAmbient como luz de día.
	Lighting = {
		Enabled = true,
		ClockTime = 14,
		Brightness = 2,
		Ambient = Color3.fromRGB(128, 128, 136),
		OutdoorAmbient = Color3.fromRGB(150, 150, 158),
		-- Se crea (o ajusta el de la plantilla de Roblox) salvo que el place tenga uno propio.
		Atmosphere = {
			Name = "RebirthAtmosphere",
			Density = 0.2,
			Offset = 0.15,
			Color = Color3.fromRGB(214, 232, 255),
			Decay = Color3.fromRGB(176, 206, 240),
			Glare = 0,
			Haze = 0.4,
		},
		-- Reflejos del entorno (poco brillo: el plástico de los bloques no debe relucir).
		EnvironmentDiffuseScale = 1,
		EnvironmentSpecularScale = 0.2,
		-- Posprocesado y nubes dinámicas (sin recursos externos). Si el place ya tiene un
		-- efecto de esa clase con otro nombre, se respeta el suyo; los que vienen con la
		-- plantilla de Roblox (Bloom, SunRays...) se ajustan a estos valores.
		Effects = {
			Bloom = { Name = "RebirthBloom", Intensity = 0.35, Size = 24, Threshold = 1.7 },
			ColorCorrection = {
				Name = "RebirthColor",
				Brightness = 0.02,
				Contrast = 0,
				Saturation = 0,
				TintColor = Color3.fromRGB(255, 253, 250),
			},
			SunRays = { Name = "RebirthSunRays", Intensity = 0.045, Spread = 0.6 },
			Clouds = { Name = "RebirthClouds", Cover = 0.52, Density = 0.55, Color = Color3.fromRGB(255, 252, 246) },
		},
	},

	-- Ciclo de día y noche (lo aplica cada cliente: DayNightController, con DayNight). La
	-- hora sale de la del servidor, así que todos ven la misma. Día largo, atardecer y
	-- amanecer cortos y una noche suave (luz de luna azulada: se sigue viendo bien).
	-- Keys: { fracción del ciclo, hora de Roblox (ClockTime) } en orden; la última hora es la
	-- primera + 24 (vuelta completa). La Caldera tiene su atardecer fijo (PortalController).
	DayNight = {
		Enabled = true,
		CycleMinutes = 24,
		Keys = { { 0, 7 }, { 0.6, 17 }, { 0.7, 19.4 }, { 0.88, 28.6 }, { 1, 31 } },
		-- Luna suave: apenas azulada y clara, para que los colores no se vuelvan morados de noche.
		NightOutdoorAmbient = Color3.fromRGB(136, 140, 164),
		NightAmbient = Color3.fromRGB(110, 112, 132),
		NightExposure = 0.5, -- más exposición de noche (se ve sin forzar la vista)
		FixedZones = { EmberCaldera = true },
	},

	-- Partículas ambientales (Ambience): polvo mágico en el claro, luciérnagas en las
	-- setas luminosas y polvo turquesa que cae de la copa del árbol ancestral.
	Ambience = {
		Motes = { Size = Vector3.new(118, 12, 118), Height = 6, Rate = 14, Color = Color3.fromRGB(255, 244, 200), Second = Color3.fromRGB(190, 255, 230) },
		Fireflies = { Size = Vector3.new(7, 3, 7), Height = 1.8, Rate = 1.2, Color = Color3.fromRGB(214, 255, 150) },
		Canopy = { Size = Vector3.new(34, 4, 34), Height = 30, Rate = 4, Color = Color3.fromRGB(88, 186, 160), Second = Color3.fromRGB(210, 255, 240) },
	},

	Terrain = {
		Size = 620, -- lado del cuadrado de pradera
		Thickness = 8,
		PlazaRadius = 13, -- círculo de adoquines alrededor del cristal
		PathWidth = 6, -- camino de tierra desde el spawn
		PathEndZ = 46, -- pasa el spawn y llega al arco del pueblo (la calle sigue en VillageConfig)
		-- Suelo de la pradera: LeafyGrass (liso, sin las hojas altas que la decoración del
		-- terreno pone sobre Grass y que tapaban todo).
		GroundMaterial = "LeafyGrass",
		MaterialColors = {
			Grass = Color3.fromRGB(122, 198, 88),
			Ground = Color3.fromRGB(196, 162, 116),
			Cobblestone = Color3.fromRGB(204, 194, 172),
			Rock = Color3.fromRGB(150, 156, 172),
			LeafyGrass = Color3.fromRGB(122, 198, 88),
		},
		-- Agua del terreno (río, lago, poza y estanques): turquesa clara, transparente y con
		-- poco reflejo (de noche el reflejo del cielo la volvía negra).
		Water = { Color = Color3.fromRGB(64, 170, 196), Transparency = 0.55, Reflectance = 0.35, WaveSize = 0.12, WaveSpeed = 8 },
		-- Colinas que dan profundidad y cierran el horizonte. (X, Z, radio)
		Hills = {
			Vector3.new(-105.4, -121.9, 55),
			Vector3.new(-40.7, -169, 70),
			Vector3.new(62, -152, 48),
			Vector3.new(128, -86, 40),
			Vector3.new(138, 8, 45),
			Vector3.new(116, 100, 44),
			Vector3.new(36, 184, 55), -- detrás del portal del Valle, sin taparle la tarima
			Vector3.new(-80, 160, 60),
			Vector3.new(-150, 50, 44),
			Vector3.new(-134, -36.5, 41),
			Vector3.new(-196, -170, 60),
			Vector3.new(198, -189, 60),
			-- Lomas suaves en el interior (praderas y alrededores de la arboleda de setas).
			Vector3.new(66.9, 95.7, 26),
			Vector3.new(-123.4, -75.8, 28),
		},
		-- Afloramientos de roca medio enterrados. (X, Z, radio)
		Rocks = {
			Vector3.new(-52, -8, 5),
			Vector3.new(47.4, -39.5, 6),
			Vector3.new(-35, 47, 4), -- (movida para dejar sitio a la primera casa del pueblo)
			Vector3.new(58.9, 36.1, 5),
			Vector3.new(-74, -54, 8),
			Vector3.new(82.2, -51.9, 7),
		},
	},

	Colors = {
		Bark = Color3.fromRGB(104, 76, 52),
		DarkBark = Color3.fromRGB(78, 58, 42),
		Leaves = {
			Color3.fromRGB(86, 152, 70),
			Color3.fromRGB(70, 132, 62),
			Color3.fromRGB(104, 170, 80),
		},
		MagicLeaves = Color3.fromRGB(88, 186, 160), -- follaje turquesa del árbol ancestral
		RuinStone = Color3.fromRGB(176, 172, 152),
		Moss = Color3.fromRGB(92, 140, 64),
		StepStone = Color3.fromRGB(162, 160, 146),
		Crystal = Color3.fromRGB(110, 214, 200),
		MushroomStem = Color3.fromRGB(236, 226, 200),
		MushroomCaps = {
			Color3.fromRGB(96, 224, 200), -- turquesa
			Color3.fromRGB(255, 204, 110), -- dorado
		},
		Flowers = {
			Color3.fromRGB(255, 156, 200),
			Color3.fromRGB(255, 214, 96),
			Color3.fromRGB(196, 156, 255),
			Color3.fromRGB(248, 246, 236),
		},
		MagicFlower = Color3.fromRGB(130, 240, 214),
	},

	-- Árbol ancestral detrás del cristal: telón de fondo y raíces gigantes.
	AncientTree = {
		Position = Vector2.new(0, -52),
		TrunkDiameter = 8,
		TrunkHeight = 30,
		RootCount = 6,
		RootReach = 24,
	},

	-- Árboles normales. (X, Z, escala)
	Trees = {
		Vector3.new(-38, -20, 1.0),
		Vector3.new(-46, 8, 0.9),
		Vector3.new(-36, 34, 1.1),
		Vector3.new(38, -24, 1.0),
		Vector3.new(56, 18, 0.85),
		Vector3.new(-62, -48, 1.3),
		Vector3.new(60, -50, 1.2),
		Vector3.new(-72, 22, 1.2),
		Vector3.new(74, 4, 1.1),
		Vector3.new(-26, -64, 1.1),
		Vector3.new(30, -66, 1.0),
	},

	-- Arco de piedra antiguo sobre el camino: enmarca el cristal visto desde el spawn.
	RuinArch = {
		Z = 17,
		Width = 12,
		Height = 11,
		PillarSize = 1.8,
	},

	-- Columnas en ruinas. (X, Z, altura; altura 0 = columna caída)
	RuinColumns = {
		Vector3.new(26, -8, 7),
		Vector3.new(32, -14, 4.5),
		Vector3.new(30, -2, 0),
		Vector3.new(-26, -38, 6),
		Vector3.new(-33, -33, 3.5),
		Vector3.new(-31, -45, 0),
	},

	-- Setas luminosas. (X, Z, número de setas)
	MushroomClusters = {
		Vector3.new(-35, -16, 3),
		Vector3.new(36, -20, 2),
		Vector3.new(-6, -40, 3),
		Vector3.new(9, -42, 2),
		Vector3.new(28, -12, 2),
		Vector3.new(-24, -34, 3),
		Vector3.new(-43, 11, 2),
		Vector3.new(-16, 16, 2),
	},

	-- Pequeños cristales. (X, Z, número de fragmentos)
	CrystalClusters = {
		Vector3.new(-12, -9, 3),
		Vector3.new(12, -10, 3),
		Vector3.new(24, -4, 2),
		Vector3.new(-29, -30, 3),
		Vector3.new(-14, 20, 2),
	},

	-- Flores repartidas con una semilla fija (siempre el mismo resultado).
	Flowers = {
		Seed = 2024,
		Clusters = 34,
		MinRadius = 15,
		MaxRadius = 62,
		MagicChance = 0.2,
	},

	-- Zonas donde no se colocan flores. (X, Z, radio)
	KeepClear = {
		Vector3.new(0, 25, 9), -- spawn
		Vector3.new(38, 85, 18), -- Jardín de los Huevos (EggConfig.Gardens.Forest)
		Vector3.new(0, 131, 16), -- portal al Valle Cristalino (al final de la calle del pueblo)
		Vector3.new(0, 17, 8), -- arco
		Vector3.new(-15, -11, 9), -- tabla de clasificación (LeaderboardConfig)
		Vector3.new(15, -11, 9), -- tabla de clasificación
	},
}

return WorldConfig
