-- Jardín de mascotas (el antiguo Jardín de los Huevos): mismo sitio y mismos pedestales,
-- pero cada pedestal vende una mascota concreta por dinero. Ya no hay huevos ni azar.
-- Las mascotas también se consiguen de los jefes (EnemyConfig, PetReward), del premio
-- diario y de los códigos (RewardConfig) y por Robux (el Haxigator del altar).

local EggConfig = {
	MaxPurchaseDistance = 20, -- studs del jugador al pedestal para comprar
	PurchaseCooldown = 1.2,

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
			-- Mascota a la venta en el pedestal arcoíris (RainbowOffset), la más cara del jardín
			RainbowPet = { PetId = "EmeraldFawn", Price = 150000 },
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

	-- Pedestales del jardín: cada uno vende UNA mascota fija por dinero (compra directa, sin
	-- azar ni incubar; PetService.buyPet). Se conservan los ids y StandOffset de los antiguos
	-- huevos: el jardín y lo que reserva sitio en el mapa (LandscapeLayout) no se mueven.
	-- Enabled = false: el pedestal no se construye (Valle y Caldera no tienen jardín).
	Stands = {
		ForestEgg = {
			Enabled = true,
			Order = 1,
			PetId = "MushroomHopper",
			Price = 1500,
			StandOffset = Vector2.new(35.9, 73.2),
			Pedestal = "Comun", -- pedestal de pedestales-huevos.glb (EggGardenData)
			Look = { Accent = Color3.fromRGB(45, 215, 255) },
		},
		MossEgg = {
			Enabled = true,
			Order = 2,
			PetId = "MossFox",
			Price = 6000,
			StandOffset = Vector2.new(45.7, 75.8),
			Pedestal = "NoComun",
			Look = { Accent = Color3.fromRGB(85, 248, 42) },
		},
		AncientEgg = {
			Enabled = true,
			Order = 3,
			PetId = "MoonOwl",
			Price = 30000,
			StandOffset = Vector2.new(45.7, 94.2),
			Pedestal = "Raro",
			Look = { Accent = Color3.fromRGB(48, 214, 255) },
		},
		CrystalEgg = {
			Enabled = false,
			Order = 4,
			Zone = "CrystalValley",
			StandOffset = Vector2.new(18, 8),
			Look = { Accent = Color3.fromRGB(150, 196, 255) },
		},
		MagmaEgg = {
			Enabled = false,
			Order = 5,
			Zone = "EmberCaldera",
			StandOffset = Vector2.new(24, 10),
			Look = { Accent = Color3.fromRGB(255, 170, 70) },
		},
	},
}

return EggConfig
