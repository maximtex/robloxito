-- Configuración de los Huevos del juego (cada uno con sus mascotas). Se pagan con 💰
-- (Cost; economía 2: EconomyConfig):
-- 1. Huevo del Bosque (💰 250): Brotecillo, Seta Saltarina, Zorrito de Brasa
-- 2. Huevo de Musgo (💰 2,500): Zorro de Musgo, Zorrito de Cuarzo, Búho Lunar
-- 3. Huevo Ancestral (💰 20,000): Tortuga Cristalina, Cervatillo Esmeralda, Dragón de Amatista
-- 4. Huevo Clásico (💰 7,500): Perrito, Conejito, Osito y Dragoncito (modelos 3D de
--    mascotas-clasico.glb). Va en el pedestal rosa del Arcoíris (Gardens.Forest.RainbowOffset).
-- Tundra Helada (en la plaza de los Huevos de Hielo; hay que tener la zona):
-- 5. Huevo de Escarcha (💰 150,000) y 6. Huevo Glaciar (💰 600,000).
-- Mundo 2 (Jardín Celestial, junto a la plaza del pueblo; hay que haber llegado al Mundo 2):
-- 7. Huevo Estelar (💰 2.5 M), 8. Huevo Celestial (💰 9 M) y 9. Huevo Cósmico (💰 30 M).
-- FaceToward: hacia dónde mira el pedestal (relativo al centro de su zona); sin él, al altar
-- del Jardín de los Huevos del Bosque.

local EggConfig = {
	MaxPurchaseDistance = 20,
	-- Mallas y textura de los huevos, subidas a Roblox (importadas de huevos.glb) para que las
	-- vean todos los jugadores (EggStandService). Shell: el cascarón; RainbowTexture: bandas
	-- del huevo arcoíris; Cracks: sus grietas moradas, cada pieza con su posición respecto al
	-- centro del huevo en unidades de la malla (el huevo mide 1.3 de alto antes de escalar).
	Art = {
		Shell = "rbxassetid://137975395551328",
		RainbowTexture = "rbxassetid://132510171058905",
		Cracks = {
			{ Mesh = "rbxassetid://108756340800454", Offset = Vector3.new(-0.0021, 0.0749, -0.0013) }, -- anillo
			{ Mesh = "rbxassetid://126169809605389", Offset = Vector3.new(-0.2614, 0.2427, -0.2961) },
			{ Mesh = "rbxassetid://76814741328146", Offset = Vector3.new(0.3593, 0.2913, -0.1261) },
			{ Mesh = "rbxassetid://71307952398101", Offset = Vector3.new(-0.0270, 0.2614, 0.3871) },
			{ Mesh = "rbxassetid://129048991274127", Offset = Vector3.new(-0.0182, -0.1935, -0.4487) },
			{ Mesh = "rbxassetid://131958612478455", Offset = Vector3.new(0.3495, -0.2148, 0.3091) },
			{ Mesh = "rbxassetid://124734021851336", Offset = Vector3.new(-0.4048, -0.1412, 0.1993) },
		},
	},
	PurchaseCooldown = 1.2,
	UnlockUpgradeId = "GeneratorPower",

	Gardens = {
		Forest = {
			Zone = "Forest",
			Name = "Jardín de los Huevos",
			-- Patio gris abierto a la avenida del portal, al sureste de la plaza del pueblo
			-- (mundo X = 38, Z = 60). Los huevos forman un arco abierto hacia la avenida y el
			-- spawn (-X), como en la referencia: Común delante a la izquierda, No común detrás,
			-- el altar al fondo en el centro, Raro detrás a la derecha y el del Arcoíris delante
			-- a la derecha (vistos desde la avenida). Más abiertos hacia los lados que el arco de
			-- radio 12 para no apretarse: No común y Raro 4 studs, Común y Arcoíris 5 (hasta el
			-- borde del suelo rosa, que va de Z = 38 a 83 en el mundo). Los tres huevos usan
			-- StandOffset; el altar y el del Arcoíris (EggStandService), AltarOffset y RainbowOffset.
			Center = Vector2.new(38, 85),
			Radius = 17,
			Entrance = 180,
			AltarOffset = Vector2.new(50, 85),
			RainbowOffset = Vector2.new(35.9, 101.8),
			-- Mascota exclusiva que se vende por Robux en el altar (PetId de PetConfig, con su
			-- producto en MonetizationConfig.PetProducts). Su modelo es el de
			-- ReplicatedStorage.PetModels (guardado en el place, no está en Rojo), agrandado
			-- FeaturedPetScale veces y girado FeaturedPetYaw grados. Sin él, el altar pone su guardián.
			FeaturedPet = "Haxigator",
			FeaturedPetScale = 2.5,
			FeaturedPetYaw = 0,
			Style = "Terrace",
		},
		CrystalValley = {
			Zone = "CrystalValley",
			Name = "Nido de Cristal",
			Center = Vector2.new(18, 8),
			Radius = 7.5,
			Entrance = 180,
			Style = "Crystal",
		},
		EmberCaldera = {
			Zone = "EmberCaldera",
			Name = "Forja de Huevos",
			Center = Vector2.new(24, 10),
			Radius = 7.5,
			Entrance = 180,
			Style = "Ember",
		},
	},

	Eggs = {
		-- Tundra Helada ----------------------------------------------------------------------
		FrostEgg = {
			DisplayName = "Huevo de Escarcha",
			RarityTitle = "ESCARCHA",
			TitleColor = Color3.fromRGB(150, 220, 255),
			Enabled = true,
			Order = 6,
			Cost = 150000,
			RequiredLevel = 0,
			Zone = "FrozenTundra",
			RequiredZone = "FrozenTundra",
			Chances = {
				{ PetId = "FrostFox", Chance = 55 },
				{ PetId = "SnowOwl", Chance = 33 },
				{ PetId = "IceTurtle", Chance = 12 },
			},
			StandOffset = Vector2.new(30, -1),
			FaceToward = Vector2.new(0, -1),
			Pedestal = "Raro",
			Look = {
				Style = "Lightning",
				Shell = Color3.fromRGB(205, 238, 255),
				Spots = Color3.fromRGB(255, 255, 255),
				Accent = Color3.fromRGB(120, 210, 255),
				BaseColor = Color3.fromRGB(42, 86, 148),
			},
		},
		GlacierEgg = {
			DisplayName = "Huevo Glaciar",
			RarityTitle = "GLACIAR",
			TitleColor = Color3.fromRGB(110, 180, 255),
			Enabled = true,
			Order = 7,
			Cost = 600000,
			RequiredLevel = 0,
			Zone = "FrozenTundra",
			RequiredZone = "FrozenTundra",
			Chances = {
				{ PetId = "PolarFawn", Chance = 55 },
				{ PetId = "AuroraFox", Chance = 33 },
				{ PetId = "FrostDragon", Chance = 12 },
			},
			StandOffset = Vector2.new(30, 19),
			FaceToward = Vector2.new(0, 19),
			Pedestal = "Raro",
			Look = {
				Style = "Lightning",
				Shell = Color3.fromRGB(90, 160, 240),
				Spots = Color3.fromRGB(200, 240, 255),
				Accent = Color3.fromRGB(170, 230, 255),
				BaseColor = Color3.fromRGB(42, 86, 148),
			},
		},

		-- Mundo 2 ---------------------------------------------------------------------------
		StarEgg = {
			DisplayName = "Huevo Estelar",
			RarityTitle = "ESTELAR",
			TitleColor = Color3.fromRGB(255, 226, 90),
			Enabled = true,
			Order = 8,
			Cost = 2500000,
			RequiredLevel = 0,
			Zone = "World2",
			RequiredZone = "World2",
			Chances = {
				{ PetId = "StarFox", Chance = 55 },
				{ PetId = "MoonMushroom", Chance = 33 },
				{ PetId = "CometOwl", Chance = 12 },
			},
			StandOffset = Vector2.new(-22, -62),
			FaceToward = Vector2.new(0, -20),
			Pedestal = "Raro",
			Look = {
				Style = "Lightning",
				Shell = Color3.fromRGB(70, 70, 150),
				Spots = Color3.fromRGB(255, 226, 90),
				Accent = Color3.fromRGB(255, 226, 90),
				BaseColor = Color3.fromRGB(42, 86, 148),
			},
		},
		CelestialEgg = {
			DisplayName = "Huevo Celestial",
			RarityTitle = "CELESTIAL",
			TitleColor = Color3.fromRGB(255, 240, 190),
			Enabled = true,
			Order = 9,
			Cost = 9000000,
			RequiredLevel = 0,
			Zone = "World2",
			RequiredZone = "World2",
			Chances = {
				{ PetId = "CelestialFawn", Chance = 55 },
				{ PetId = "SunTurtle", Chance = 33 },
				{ PetId = "CelestialDragon", Chance = 12 },
			},
			StandOffset = Vector2.new(0, -74),
			FaceToward = Vector2.new(0, -20),
			Pedestal = "Arcoiris",
			Look = {
				Style = "Lightning",
				Shell = Color3.fromRGB(255, 248, 228),
				Spots = Color3.fromRGB(255, 210, 90),
				Accent = Color3.fromRGB(255, 210, 90),
				BaseColor = Color3.fromRGB(242, 48, 128),
			},
		},
		CosmicEgg = {
			DisplayName = "Huevo Cósmico",
			RarityTitle = "CÓSMICO",
			TitleColor = Color3.fromRGB(220, 130, 255),
			Enabled = true,
			Order = 10,
			Cost = 30000000,
			RequiredLevel = 0,
			Zone = "World2",
			RequiredZone = "World2",
			Chances = {
				{ PetId = "GalaxyFox", Chance = 55 },
				{ PetId = "CosmicSprout", Chance = 33 },
				{ PetId = "CosmicDragon", Chance = 12 },
			},
			StandOffset = Vector2.new(22, -62),
			FaceToward = Vector2.new(0, -20),
			Pedestal = "Arcoiris",
			Look = {
				Style = "Rainbow",
				Shell = Color3.fromRGB(150, 90, 230),
				Spots = Color3.fromRGB(255, 120, 230),
				Accent = Color3.fromRGB(220, 130, 255),
				BaseColor = Color3.fromRGB(242, 48, 128),
			},
		},

		ForestEgg = {
			DisplayName = "COMÚN",
			RarityTitle = "COMÚN",
			TitleColor = Color3.fromRGB(235, 242, 255),
			Enabled = true,
			Order = 1,
			Cost = 250,
			RequiredLevel = 0,
			Chances = {
				{ PetId = "Sproutling", Chance = 55 },
				{ PetId = "MushroomHopper", Chance = 35 },
				{ PetId = "EmberFox", Chance = 10 },
			},
			StandOffset = Vector2.new(35.9, 68.2),
			Pedestal = "Comun", -- pedestal de pedestales-huevos.glb (EggGardenData)
			Look = {
				Style = "Clean",
				Shell = Color3.fromRGB(238, 236, 242),
				Spots = Color3.fromRGB(220, 220, 230),
				Accent = Color3.fromRGB(45, 215, 255),
				BaseColor = Color3.fromRGB(42, 86, 148),
			},
		},

		MossEgg = {
			DisplayName = "NO COMÚN",
			RarityTitle = "NO COMÚN",
			TitleColor = Color3.fromRGB(85, 248, 42),
			Enabled = true,
			Order = 2,
			Cost = 2500,
			RequiredLevel = 0,
			Chances = {
				{ PetId = "MossFox", Chance = 55 },
				{ PetId = "QuartzFox", Chance = 33 },
				{ PetId = "MoonOwl", Chance = 12 },
			},
			StandOffset = Vector2.new(45.7, 71.8),
			Pedestal = "NoComun",
			Look = {
				Style = "Clean",
				Shell = Color3.fromRGB(52, 235, 28),
				Spots = Color3.fromRGB(95, 255, 70),
				Accent = Color3.fromRGB(45, 215, 255),
				BaseColor = Color3.fromRGB(42, 86, 148),
			},
		},

		AncientEgg = {
			DisplayName = "RARO",
			RarityTitle = "RARO",
			TitleColor = Color3.fromRGB(48, 214, 255),
			Enabled = true,
			Order = 3,
			Cost = 20000,
			RequiredLevel = 0,
			Chances = {
				{ PetId = "CrystalTurtle", Chance = 55 },
				{ PetId = "EmeraldFawn", Chance = 33 },
				{ PetId = "AmethystDragon", Chance = 12 },
			},
			StandOffset = Vector2.new(45.7, 98.2),
			Pedestal = "Raro",
			Look = {
				Style = "Lightning",
				Shell = Color3.fromRGB(36, 198, 255),
				Spots = Color3.fromRGB(165, 240, 255),
				Accent = Color3.fromRGB(45, 215, 255),
				BaseColor = Color3.fromRGB(42, 86, 148),
			},
		},

		-- Huevo Clásico: en el pedestal rosa del Arcoíris (antes decorativo), con la cáscara arcoíris.
		ClassicEgg = {
			DisplayName = "CLÁSICO",
			RarityTitle = "CLÁSICO",
			TitleColor = Color3.fromRGB(255, 105, 235),
			Enabled = true,
			Order = 4,
			Cost = 7500,
			RequiredLevel = 0,
			Chances = {
				{ PetId = "ClassicDog", Chance = 50 },
				{ PetId = "ClassicBunny", Chance = 30 },
				{ PetId = "ClassicBear", Chance = 15 },
				{ PetId = "ClassicDragon", Chance = 5 },
			},
			StandOffset = Vector2.new(35.9, 101.8),
			Pedestal = "Arcoiris",
			Look = {
				Style = "Rainbow",
				Shell = Color3.fromRGB(255, 230, 50),
				Spots = Color3.fromRGB(255, 150, 230),
				Accent = Color3.fromRGB(255, 105, 235),
				BaseColor = Color3.fromRGB(242, 48, 128),
			},
		},

		CrystalEgg = {
			DisplayName = "Huevo de Cristal",
			Enabled = false,
			Order = 4,
			Cost = 25000,
			RequiredLevel = 0,
			Zone = "CrystalValley",
			RequiredZone = "CrystalValley",
			Chances = {
				{ PetId = "QuartzFox", Chance = 65 },
				{ PetId = "CrystalTurtle", Chance = 30 },
				{ PetId = "AmethystDragon", Chance = 5 },
			},
			StandOffset = Vector2.new(18, 8),
			Look = {
				Style = "Crystalline",
				Shell = Color3.fromRGB(176, 214, 236),
				Spots = Color3.fromRGB(176, 120, 236),
				Accent = Color3.fromRGB(150, 196, 255),
			},
		},

		MagmaEgg = {
			DisplayName = "Huevo de Magma",
			Enabled = false,
			Order = 5,
			Cost = 300000,
			RequiredLevel = 0,
			Zone = "EmberCaldera",
			RequiredZone = "EmberCaldera",
			Chances = {
				{ PetId = "AshFox", Chance = 62 },
				{ PetId = "ObsidianTurtle", Chance = 30 },
				{ PetId = "MagmaDragon", Chance = 8 },
			},
			StandOffset = Vector2.new(24, 10),
			Look = {
				Style = "Runic",
				Shell = Color3.fromRGB(62, 50, 50),
				Spots = Color3.fromRGB(255, 132, 50),
				Accent = Color3.fromRGB(255, 170, 70),
			},
		},
	},
}

return EggConfig
