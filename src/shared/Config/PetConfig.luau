-- Mascotas y rarezas. Para añadir una mascota: añadir una entrada en Pets (con un ID
-- estable que no se renombre nunca: es lo que se guarda) y referenciarla desde un huevo
-- en EggConfig. El servidor valida esta tabla al arrancar.
--
-- Multiplicador: cada mascota equipada aporta (Multiplier - 1) de bonificación y las
-- bonificaciones se suman. Ej.: 1.10 + 1.25 equipadas = x1.35 de producción.
--
-- MODELOS: Look.Style elige un prototipo hecho con piezas nativas (PetModelBuilder).
-- Los marcados con Prototype = true deben sustituirse por arte definitivo: basta con
-- colocar un Model llamado igual que el ID en ReplicatedStorage.PetModels (con
-- PrimaryPart); PetModelBuilder lo usará automáticamente en lugar del prototipo.

local PetConfig = {
	MaxEquipped = 3,
	MaxInventory = 60,

	-- Multiplier: valor por defecto de las mascotas de esa rareza si no indican uno propio.
	Rarities = {
		Common = { DisplayName = "Común", Order = 1, Color = Color3.fromRGB(196, 204, 186), Multiplier = 1.1 },
		Uncommon = { DisplayName = "Poco común", Order = 2, Color = Color3.fromRGB(120, 214, 120), Multiplier = 1.25 },
		Rare = { DisplayName = "Rara", Order = 3, Color = Color3.fromRGB(96, 180, 255), Multiplier = 1.5 },
		Epic = { DisplayName = "Épica", Order = 4, Color = Color3.fromRGB(196, 120, 255), Multiplier = 2 },
		Legendary = { DisplayName = "Legendaria", Order = 5, Color = Color3.fromRGB(255, 200, 80), Multiplier = 3 },
	},

	Pets = {
		-- Huevo del Bosque ----------------------------------------------------------
		Sproutling = {
			DisplayName = "Brotecillo",
			Rarity = "Common",
			Multiplier = 1.1,
			Look = { Style = "Sprout", Prototype = true, Primary = Color3.fromRGB(156, 222, 112), Secondary = Color3.fromRGB(64, 150, 70) },
		},
		MushroomHopper = {
			DisplayName = "Seta Saltarina",
			Rarity = "Common",
			Multiplier = 1.1,
			Look = { Style = "Mushroom", Prototype = true, Primary = Color3.fromRGB(214, 70, 58), Secondary = Color3.fromRGB(244, 234, 214) },
		},
		EmberFox = {
			DisplayName = "Zorrito de Brasa",
			Rarity = "Uncommon",
			Multiplier = 1.25,
			Look = { Style = "Ember", Prototype = true, Primary = Color3.fromRGB(226, 96, 44), Secondary = Color3.fromRGB(255, 196, 70) },
		},

		-- Huevo de Musgo -----------------------------------------------------------
		MossFox = {
			DisplayName = "Zorro de Musgo",
			Rarity = "Uncommon",
			Multiplier = 1.25,
			Look = { Style = "Fox", Prototype = true, Primary = Color3.fromRGB(206, 124, 62), Secondary = Color3.fromRGB(112, 170, 82) },
		},

		-- Huevos de Musgo y Ancestral -------------------------------------------------
		MoonOwl = {
			DisplayName = "Búho Lunar",
			Rarity = "Rare",
			Multiplier = 1.5,
			Look = { Style = "Owl", Prototype = true, Primary = Color3.fromRGB(150, 160, 214), Secondary = Color3.fromRGB(110, 118, 176) },
		},

		-- Huevo Ancestral ------------------------------------------------------------
		EmeraldFawn = {
			DisplayName = "Cervatillo Esmeralda",
			Rarity = "Epic",
			Multiplier = 2,
			Look = { Style = "Fawn", Prototype = true, Primary = Color3.fromRGB(150, 112, 74), Secondary = Color3.fromRGB(70, 220, 130) },
		},

		-- Huevo de Cristal (Valle Cristalino) -----------------------------------------
		QuartzFox = {
			DisplayName = "Zorrito de Cuarzo",
			Rarity = "Rare",
			Multiplier = 1.5,
			Look = { Style = "Quartz", Prototype = true, Primary = Color3.fromRGB(246, 222, 232), Secondary = Color3.fromRGB(236, 150, 196) },
		},
		CrystalTurtle = {
			DisplayName = "Tortuga de Musgo Cristalino",
			Rarity = "Epic",
			Multiplier = 2,
			Look = { Style = "Turtle", Prototype = true, Primary = Color3.fromRGB(110, 150, 84), Secondary = Color3.fromRGB(110, 214, 220) },
		},
		AmethystDragon = {
			DisplayName = "Dragón Bebé de Amatista",
			Rarity = "Legendary",
			Multiplier = 3,
			Look = { Style = "Dragon", Prototype = true, Primary = Color3.fromRGB(150, 92, 214), Secondary = Color3.fromRGB(220, 170, 255) },
		},
	},
}

return PetConfig
