-- Caldera de Brasas: entorno de la tercera zona (se abre con renacimientos y energía).
-- Solo decorativo. Posiciones RELATIVAS al centro de la zona (ZoneConfig.Zones.EmberCaldera),
-- en X/Z, igual que ValleyConfig. Referencias: llegada (0, 44) mirando a -Z, portal de
-- vuelta (0, 62), Forja de Huevos (24, 10), lago de lava con cascada (-46, 8), Corazón de la
-- Caldera (arena del jefe, 0, -94) y el gran volcán al fondo, siempre a la vista.
--
-- Materiales del terreno propios (Basalt, CrackedLava, Salt, Brick): SetMaterialColor es
-- global y así no cambia el color del bosque ni del valle.

local CalderaConfig = {
	ModelName = "EmberCaldera",

	Terrain = {
		Size = 440,
		Thickness = 8,
		Ground = "Basalt",
		Mountain = "Basalt",
		Lava = "CrackedLava", -- grietas que brillan solas (vetas de las montañas y del volcán)
		Path = "Salt", -- piedra clara y cenicienta: se lee bien sobre el basalto
		MaterialColors = {
			Basalt = Color3.fromRGB(98, 78, 72),
			CrackedLava = Color3.fromRGB(70, 52, 50),
			Salt = Color3.fromRGB(176, 150, 132),
			Brick = Color3.fromRGB(132, 74, 58),
		},
		-- Montañas que cierran la caldera (ángulo en grados, distancia, radio). Sin montañas
		-- delante del volcán (270°, al fondo según se llega).
		Mountains = {
			Vector3.new(0, 200, 70), Vector3.new(35, 190, 62), Vector3.new(70, 205, 74),
			Vector3.new(110, 195, 66), Vector3.new(145, 205, 70), Vector3.new(180, 195, 72),
			Vector3.new(215, 200, 66), Vector3.new(325, 200, 64),
		},
		-- Colinas suaves interiores. (X, Z, radio)
		Hills = {
			Vector3.new(-96, -62, 24), Vector3.new(98, -66, 26), Vector3.new(104, 64, 22), Vector3.new(-98, 84, 26),
		},
		-- Caminos de piedra clara. (X, Z inicio) -> (X, Z fin), anchura
		Paths = {
			{ From = Vector2.new(0, 48), To = Vector2.new(0, -64), Width = 6 }, -- escalón del portal -> Corazón de la Caldera
			{ From = Vector2.new(0, 10), To = Vector2.new(16, 10), Width = 5 }, -- ramal a la Forja de Huevos
			{ From = Vector2.new(0, 20), To = Vector2.new(-28, 14), Width = 5 }, -- ramal al lago de lava
		},
	},

	-- Gran volcán al fondo (fuera del área de juego): cono de basalto con un cráter de lava
	-- que humea y ríos de lava por la ladera que mira a la caldera.
	Volcano = {
		Angle = 270, -- grados (270 = -Z, al fondo)
		Distance = 230,
		BaseRadius = 96,
		TopRadius = 24,
		Height = 120,
		CraterDepth = 16,
		Rivers = { -26, 0, 24 }, -- grados respecto a la dirección hacia el centro de la caldera
	},

	-- Lago de lava con una cascada de lava que cae de un acantilado de rocas.
	LavaLake = {
		Center = Vector2.new(-46, 8),
		Radius = 13,
		Cliff = {
			Center = Vector2.new(-46, -10), -- detrás del lago: la cascada mira a la llegada (+Z)
			FallHeight = 16,
			Rocks = {
				{ X = -9, Z = -6, Height = 26, Variant = 4, Yaw = 30 },
				{ X = 9, Z = -7, Height = 23, Variant = 4, Yaw = 160 },
				{ X = 19, Z = -1, Height = 15, Variant = 5, Yaw = 200 },
				{ X = -19, Z = -2, Height = 18, Variant = 9, Yaw = 20 },
				{ X = -23, Z = 5, Height = 5, Variant = 7, Yaw = 10 },
				{ X = 23, Z = 5, Height = 4, Variant = 1, Yaw = 80 },
			},
			-- Sin modelos de roca: un bloque de basalto del terreno.
			Size = Vector3.new(34, 24, 12),
		},
	},

	Colors = {
		-- El neón se ve más claro que su color: tonos algo oscuros para que la lava sea naranja.
		Lava = Color3.fromRGB(236, 88, 26),
		LavaBright = Color3.fromRGB(255, 150, 46),
		LavaDeep = Color3.fromRGB(200, 50, 24),
		-- Color de los modelos de roca (sin su textura clara, con material de basalto).
		RockTint = Color3.fromRGB(78, 64, 62),
		Obsidian = {
			Color3.fromRGB(46, 36, 56),
			Color3.fromRGB(64, 44, 70),
			Color3.fromRGB(38, 34, 44),
		},
		Rock = Color3.fromRGB(72, 60, 58),
		Smoke = Color3.fromRGB(70, 62, 62),
		Rune = Color3.fromRGB(255, 150, 60),
	},

	-- Partículas: ascuas que suben por toda la caldera, humo del volcán y de las fumarolas.
	Ambience = {
		Embers = { Size = Vector3.new(120, 12, 120), Height = 5, Rate = 16, Color = Color3.fromRGB(255, 150, 60), Second = Color3.fromRGB(255, 214, 110) },
		Crater = { Rate = 3, Color = Color3.fromRGB(86, 78, 76) },
		Vent = { Size = Vector3.new(3, 1, 3), Rate = 3, Color = Color3.fromRGB(110, 100, 98) },
	},

	-- Formaciones de obsidiana con vetas de lava. (X, Z, escala)
	ObsidianClusters = {
		Vector3.new(-28, -24, 1.0), Vector3.new(36, -22, 1.2), Vector3.new(-74, -56, 1.5),
		Vector3.new(78, 8, 1.2), Vector3.new(-62, 64, 1.3), Vector3.new(52, 62, 1.0),
		Vector3.new(24, -72, 1.4), Vector3.new(-48, -84, 1.6),
	},

	-- Fumarolas: montículos de lava agrietada que echan humo. (X, Z)
	Vents = {
		Vector2.new(-16, -54), Vector2.new(30, -6), Vector2.new(64, -72), Vector2.new(-82, 12), Vector2.new(40, 74),
	},

	-- Arco de basalto sobre el camino principal, con una runa de lava.
	Arch = { Z = 26, Width = 11, Height = 10 },

	-- Ascuas brillantes repartidas por el suelo con semilla fija.
	Embers = { Seed = 91, Clusters = 24, MinRadius = 14, MaxRadius = 92 },

	-- Zonas despejadas (sin ascuas): llegada, portal, forja, lago y cascada. (X, Z, radio)
	KeepClear = {
		Vector3.new(0, 44, 9), Vector3.new(0, 62, 16), Vector3.new(24, 10, 10),
		Vector3.new(-46, 8, 16), Vector3.new(-46, -10, 20),
	},
}

return CalderaConfig
