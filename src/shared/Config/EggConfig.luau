-- Configuración de los 3 Huevos del juego (cada uno con 3 tipos de mascotas):
-- 1. Huevo del Bosque (⚡ 100): Brotecillo, Seta Saltarina, Zorrito de Brasa
-- 2. Huevo de Musgo (⚡ 750): Zorro de Musgo, Zorrito de Cuarzo, Búho Lunar
-- 3. Huevo Ancestral (⚡ 4,000): Tortuga Cristalina, Cervatillo Esmeralda, Dragón de Amatista
-- 4. Huevo Clásico (⚡ 1,500): Perrito, Conejito, Osito y Dragoncito (modelos 3D de
--    mascotas-clasico.glb). Va en el pedestal rosa del Arcoíris (Gardens.Forest.RainbowOffset).

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
		ForestEgg = {
			DisplayName = "COMÚN",
			RarityTitle = "COMÚN",
			TitleColor = Color3.fromRGB(235, 242, 255),
			Enabled = true,
			Order = 1,
			Cost = 50,
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
			Cost = 500,
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
			Cost = 4000,
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
			Cost = 1500,
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
			Cost = 5000,
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
			Cost = 60000,
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
