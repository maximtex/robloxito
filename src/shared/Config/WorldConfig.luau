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

	Lighting = {
		Enabled = true,
		ClockTime = 15.5, -- tarde luminosa: colores cálidos y sombras suaves
		Ambient = Color3.fromRGB(78, 86, 74),
		OutdoorAmbient = Color3.fromRGB(132, 142, 122),
		-- Se crea solo si el place no tiene ya un Atmosphere propio.
		Atmosphere = {
			Name = "RebirthAtmosphere",
			Density = 0.3,
			Offset = 0.08,
			Color = Color3.fromRGB(200, 224, 214),
			Decay = Color3.fromRGB(112, 142, 120),
			Glare = 0.15,
			Haze = 1.2,
		},
	},

	Terrain = {
		Size = 620, -- lado del cuadrado de pradera
		Thickness = 8,
		PlazaRadius = 13, -- círculo de adoquines alrededor del cristal
		PathWidth = 6, -- camino de tierra desde el spawn
		PathEndZ = 52, -- pasa el spawn y llega al portal del Valle (ZoneConfig)
		MaterialColors = {
			Grass = Color3.fromRGB(96, 164, 72),
			Ground = Color3.fromRGB(128, 100, 68),
			Cobblestone = Color3.fromRGB(150, 148, 132),
			Rock = Color3.fromRGB(122, 126, 112),
			LeafyGrass = Color3.fromRGB(78, 140, 62),
		},
		-- Colinas que dan profundidad y cierran el horizonte. (X, Z, radio)
		Hills = {
			Vector3.new(-120, -150, 55),
			Vector3.new(-40, -190, 70),
			Vector3.new(70, -175, 60),
			Vector3.new(150, -100, 50),
			Vector3.new(170, 10, 55),
			Vector3.new(140, 120, 50),
			Vector3.new(30, 170, 55),
			Vector3.new(-80, 160, 60),
			Vector3.new(-170, 60, 55),
			Vector3.new(-165, -45, 50),
			Vector3.new(-230, -200, 70),
			Vector3.new(230, -220, 70),
		},
		-- Afloramientos de roca medio enterrados. (X, Z, radio)
		Rocks = {
			Vector3.new(-52, -8, 5),
			Vector3.new(48, -40, 6),
			Vector3.new(-30, 52, 4),
			Vector3.new(62, 38, 5),
			Vector3.new(-90, -70, 8),
			Vector3.new(95, -60, 7),
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
		Vector3.new(48, 30, 0.85),
		Vector3.new(-62, -48, 1.3),
		Vector3.new(60, -50, 1.2),
		Vector3.new(-22, 50, 0.9),
		Vector3.new(26, 54, 1.0),
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
		Vector3.new(-20, 12, 7), -- santuario del Huevo del Bosque
		Vector3.new(-28, 0, 7), -- santuario del Huevo de Musgo
		Vector3.new(24, 10, 7), -- santuario del Huevo Ancestral
		Vector3.new(0, 56, 12), -- portal al Valle Cristalino
		Vector3.new(0, 17, 8), -- arco
	},
}

return WorldConfig
