-- Configuración de los 3 Huevos del juego (cada uno con 3 tipos de mascotas):
-- 1. Huevo del Bosque (⚡ 100): Brotecillo, Seta Saltarina, Zorrito de Brasa
-- 2. Huevo de Musgo (⚡ 750): Zorro de Musgo, Zorrito de Cuarzo, Búho Lunar
-- 3. Huevo Ancestral (⚡ 4,000): Tortuga Cristalina, Cervatillo Esmeralda, Dragón de Amatista

local EggConfig = {
	MaxPurchaseDistance = 20,
	PurchaseCooldown = 1.2,
	UnlockUpgradeId = "GeneratorPower",

	Gardens = {
		Forest = {
			Zone = "Forest",
			Name = "Jardín de los Huevos",
			-- Patio gris abierto a la avenida del portal, al sureste de la plaza del pueblo
			-- (mundo X = 38, Z = 60). Los huevos forman un arco de radio 12 abierto hacia la
			-- avenida y el spawn (-X), como en la referencia: Común delante a la izquierda, No
			-- común detrás, el altar al fondo en el centro, Raro detrás a la derecha y el del
			-- Arcoíris delante a la derecha (vistos desde la avenida). Los tres huevos usan
			-- StandOffset; el altar y el del Arcoíris (EggStandService), AltarOffset y RainbowOffset.
			Center = Vector2.new(38, 85),
			Radius = 17,
			Entrance = 180,
			AltarOffset = Vector2.new(50, 85),
			RainbowOffset = Vector2.new(35.9, 96.8),
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
			StandOffset = Vector2.new(35.9, 73.2),
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
			StandOffset = Vector2.new(45.7, 75.8),
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
			StandOffset = Vector2.new(45.7, 94.2),
			Pedestal = "Raro",
			Look = {
				Style = "Lightning",
				Shell = Color3.fromRGB(36, 198, 255),
				Spots = Color3.fromRGB(165, 240, 255),
				Accent = Color3.fromRGB(45, 215, 255),
				BaseColor = Color3.fromRGB(42, 86, 148),
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
