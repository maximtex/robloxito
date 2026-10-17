-- Valle Cristalino: entorno de la segunda zona. Solo decorativo.
-- Posiciones RELATIVAS al centro de la zona (ZoneConfig.Zones.CrystalValley.Center), en X/Z.
-- Referencias: llegada (0, 44) mirando a -Z, portal de vuelta (0, 58), santuario del
-- Huevo de Cristal (18, 8), estanque y cascada (-42, 22), gran geoda al fondo (0, -62).

local ValleyConfig = {
	ModelName = "CrystalValley",

	Terrain = {
		Size = 440,
		Thickness = 8,
		-- Materiales del Valle: distintos de los del bosque, para que sus colores no se mezclen.
		Ground = "LeafyGrass",
		Mountain = "Limestone",
		Cliff = "Slate",
		Path = "Pavement",
		MaterialColors = {
			Limestone = Color3.fromRGB(198, 192, 214),
			Slate = Color3.fromRGB(96, 102, 130),
			Pavement = Color3.fromRGB(176, 176, 188),
		},
		-- Montañas que rodean el valle. (ángulo en grados, distancia, radio)
		Mountains = {
			Vector3.new(0, 195, 70), Vector3.new(35, 185, 60), Vector3.new(70, 200, 75),
			Vector3.new(110, 190, 65), Vector3.new(145, 200, 70), Vector3.new(180, 190, 72),
			Vector3.new(215, 195, 66), Vector3.new(250, 185, 74), Vector3.new(290, 200, 68),
			Vector3.new(325, 190, 62),
		},
		-- Colinas suaves interiores. (X, Z, radio)
		Hills = {
			Vector3.new(-90, -60, 26), Vector3.new(95, -70, 30), Vector3.new(100, 60, 24), Vector3.new(-95, 80, 28),
		},
		-- Caminos de piedra. (X, Z inicio) -> (X, Z fin), anchura
		Paths = {
			{ From = Vector2.new(0, 60), To = Vector2.new(0, -40), Width = 6 }, -- portal -> geoda
			{ From = Vector2.new(0, 8), To = Vector2.new(16, 8), Width = 5 }, -- ramal al santuario
			{ From = Vector2.new(0, 18), To = Vector2.new(-26, 22), Width = 5 }, -- ramal al estanque
		},
	},

	Pond = {
		Center = Vector2.new(-42, 22),
		Radius = 13,
		-- Acantilado detrás del estanque, de donde cae la cascada.
		Cliff = { Center = Vector2.new(-42, 41), Size = Vector3.new(34, 26, 12) },
	},

	Colors = {
		Crystals = {
			Color3.fromRGB(110, 170, 255), -- azul
			Color3.fromRGB(176, 120, 236), -- violeta
			Color3.fromRGB(96, 220, 210), -- turquesa
		},
		Trunk = Color3.fromRGB(214, 206, 190),
		Leaves = {
			Color3.fromRGB(110, 190, 176),
			Color3.fromRGB(176, 160, 222),
			Color3.fromRGB(128, 200, 150),
		},
		Ruin = Color3.fromRGB(190, 186, 200),
		Moss = Color3.fromRGB(96, 150, 96),
		Water = Color3.fromRGB(150, 210, 240),
	},

	-- Gran geoda: silueta reconocible al fondo, vista desde la llegada.
	Geode = { Position = Vector2.new(0, -62), Height = 30 },

	-- Formaciones de cristal. (X, Z, escala)
	CrystalClusters = {
		Vector3.new(-30, -22, 1.0), Vector3.new(40, -32, 1.3), Vector3.new(-72, -40, 1.6),
		Vector3.new(72, 12, 1.2), Vector3.new(-66, 62, 1.4), Vector3.new(56, 56, 1.0),
		Vector3.new(28, -76, 1.5), Vector3.new(-44, -80, 1.8), Vector3.new(-14, 34, 0.6),
	},

	-- Árboles de corteza clara y follaje cristalino. (X, Z, escala)
	Trees = {
		Vector3.new(-20, 32, 1.0), Vector3.new(28, 32, 0.9), Vector3.new(-58, 4, 1.2),
		Vector3.new(50, -10, 1.1), Vector3.new(-36, -48, 1.2), Vector3.new(32, -52, 1.0),
		Vector3.new(64, 36, 1.1), Vector3.new(-64, -18, 1.0), Vector3.new(-30, 66, 1.0),
	},

	-- Columnas en ruinas junto al santuario. (X, Z, altura; 0 = caída)
	RuinColumns = {
		Vector3.new(32, -2, 7), Vector3.new(36, 14, 3.5), Vector3.new(30, 22, 0),
	},
	-- Arco sobre el camino principal que enmarca la geoda desde la llegada.
	Arch = { Z = 26, Width = 11, Height = 10 },

	-- Flores de cristal repartidas con semilla fija.
	Flowers = { Seed = 77, Clusters = 26, MinRadius = 14, MaxRadius = 90 },

	-- Zonas despejadas (sin flores): llegada, portal, santuario, estanque y caminos. (X, Z, radio)
	KeepClear = {
		Vector3.new(0, 44, 9), Vector3.new(0, 58, 12), Vector3.new(18, 8, 8),
		Vector3.new(-42, 22, 16), Vector3.new(-42, 41, 20), Vector3.new(0, -62, 22),
	},
}

return ValleyConfig
