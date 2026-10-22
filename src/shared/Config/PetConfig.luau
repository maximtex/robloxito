-- Mascotas, rarezas y evoluciones:
-- - 3 huevos principales con 3 mascotas cada uno (9 mascotas base + sus versiones evolucionadas ★ Evo).
-- - Cada mascota base tiene `EvolvesInto = "<PetId>_Evo"`: al juntar 3 iguales en la Máquina de
--   Evolución se fusionan en su versión ★ Evo con el doble de poder.
-- - Mascotas exclusivas (rareza Exclusive): no salen de huevos, se compran con Robux
--   (MonetizationConfig.PetProducts) y no evolucionan.

local PetConfig = {
	MaxEquipped = 3,
	MaxInventory = 60,
	EvolutionCopiesRequired = 3,

	Rarities = {
		Common = { DisplayName = "Común", Order = 1, Color = Color3.fromRGB(196, 204, 186), Multiplier = 1.1 },
		Uncommon = { DisplayName = "Poco común", Order = 2, Color = Color3.fromRGB(120, 214, 120), Multiplier = 1.25 },
		Rare = { DisplayName = "Rara", Order = 3, Color = Color3.fromRGB(96, 180, 255), Multiplier = 1.5 },
		Epic = { DisplayName = "Épica", Order = 4, Color = Color3.fromRGB(196, 120, 255), Multiplier = 2 },
		Legendary = { DisplayName = "Legendaria", Order = 5, Color = Color3.fromRGB(255, 200, 80), Multiplier = 3 },
		Exclusive = { DisplayName = "Exclusiva", Order = 6, Color = Color3.fromRGB(60, 255, 120), Multiplier = 6 },
	},

	Pets = {
		-- Huevo 1: Huevo del Bosque (3 tipos de mascotas) ---------------------------
		Sproutling = {
			DisplayName = "Brotecillo",
			Rarity = "Common",
			Multiplier = 1.1,
			EvolvesInto = "Sproutling_Evo",
			Look = { Style = "Sprout", Primary = Color3.fromRGB(156, 222, 112), Secondary = Color3.fromRGB(64, 150, 70) },
		},
		MushroomHopper = {
			DisplayName = "Seta Saltarina",
			Rarity = "Common",
			Multiplier = 1.2,
			EvolvesInto = "MushroomHopper_Evo",
			Look = { Style = "Mushroom", Primary = Color3.fromRGB(214, 70, 58), Secondary = Color3.fromRGB(244, 234, 214) },
		},
		EmberFox = {
			DisplayName = "Zorrito de Brasa",
			Rarity = "Uncommon",
			Multiplier = 1.35,
			EvolvesInto = "EmberFox_Evo",
			Look = { Style = "Ember", Primary = Color3.fromRGB(226, 96, 44), Secondary = Color3.fromRGB(255, 196, 70) },
		},

		-- Huevo 2: Huevo de Musgo (3 tipos de mascotas) -----------------------------
		MossFox = {
			DisplayName = "Zorro de Musgo",
			Rarity = "Uncommon",
			Multiplier = 1.4,
			EvolvesInto = "MossFox_Evo",
			Look = { Style = "Fox", Primary = Color3.fromRGB(206, 124, 62), Secondary = Color3.fromRGB(112, 170, 82) },
		},
		QuartzFox = {
			DisplayName = "Zorrito de Cuarzo",
			Rarity = "Rare",
			Multiplier = 1.65,
			EvolvesInto = "QuartzFox_Evo",
			Look = { Style = "Quartz", Primary = Color3.fromRGB(246, 222, 232), Secondary = Color3.fromRGB(236, 150, 196) },
		},
		MoonOwl = {
			DisplayName = "Búho Lunar",
			Rarity = "Rare",
			Multiplier = 1.9,
			EvolvesInto = "MoonOwl_Evo",
			Look = { Style = "Owl", Primary = Color3.fromRGB(150, 160, 214), Secondary = Color3.fromRGB(110, 118, 176) },
		},

		-- Huevo 3: Huevo Ancestral (3 tipos de mascotas) ----------------------------
		CrystalTurtle = {
			DisplayName = "Tortuga Cristalina",
			Rarity = "Epic",
			Multiplier = 2.2,
			EvolvesInto = "CrystalTurtle_Evo",
			Look = { Style = "Turtle", Primary = Color3.fromRGB(110, 150, 84), Secondary = Color3.fromRGB(110, 214, 220) },
		},
		EmeraldFawn = {
			DisplayName = "Cervatillo Esmeralda",
			Rarity = "Epic",
			Multiplier = 2.6,
			EvolvesInto = "EmeraldFawn_Evo",
			Look = { Style = "Fawn", Primary = Color3.fromRGB(150, 112, 74), Secondary = Color3.fromRGB(70, 220, 130) },
		},
		AmethystDragon = {
			DisplayName = "Dragón de Amatista",
			Rarity = "Legendary",
			Multiplier = 3.5,
			EvolvesInto = "AmethystDragon_Evo",
			Look = { Style = "Dragon", Primary = Color3.fromRGB(150, 92, 214), Secondary = Color3.fromRGB(220, 170, 255) },
		},

		-- Mascotas extra (compatibilidad con perfiles existentes) -------------------
		AshFox = {
			DisplayName = "Zorro de Ceniza",
			Rarity = "Rare",
			Multiplier = 1.75,
			EvolvesInto = "AshFox_Evo",
			Look = { Style = "Ember", Primary = Color3.fromRGB(84, 74, 76), Secondary = Color3.fromRGB(255, 140, 50) },
		},
		ObsidianTurtle = {
			DisplayName = "Tortuga de Obsidiana",
			Rarity = "Epic",
			Multiplier = 2.5,
			EvolvesInto = "ObsidianTurtle_Evo",
			Look = { Style = "Turtle", Primary = Color3.fromRGB(70, 58, 60), Secondary = Color3.fromRGB(255, 120, 40) },
		},
		MagmaDragon = {
			DisplayName = "Dragón de Magma",
			Rarity = "Legendary",
			Multiplier = 4,
			EvolvesInto = "MagmaDragon_Evo",
			Look = { Style = "Dragon", Primary = Color3.fromRGB(214, 70, 40), Secondary = Color3.fromRGB(255, 196, 80) },
		},

		-- Exclusivas de Robux (se compran en el altar del Jardín de los Huevos) -----
		-- El modelo es ReplicatedStorage.PetModels.Haxigator (guardado en el place); si
		-- falta, se dibuja como un dragón con sus colores.
		Haxigator = {
			DisplayName = "Haxigator",
			Rarity = "Exclusive",
			Multiplier = 6,
			Look = { Style = "Dragon", Primary = Color3.fromRGB(28, 34, 30), Secondary = Color3.fromRGB(60, 255, 120) },
		},

		-- Versiones Evolucionadas (★ Evo: doble multiplicador y aspecto radiante) ----
		Sproutling_Evo = {
			DisplayName = "★ Brotecillo Evo",
			Rarity = "Rare",
			Multiplier = 2.2,
			IsEvolved = true,
			Look = { Style = "Sprout", Primary = Color3.fromRGB(255, 215, 70), Secondary = Color3.fromRGB(110, 255, 140) },
		},
		MushroomHopper_Evo = {
			DisplayName = "★ Seta Saltarina Evo",
			Rarity = "Rare",
			Multiplier = 2.4,
			IsEvolved = true,
			Look = { Style = "Mushroom", Primary = Color3.fromRGB(255, 195, 55), Secondary = Color3.fromRGB(255, 90, 180) },
		},
		EmberFox_Evo = {
			DisplayName = "★ Zorrito de Brasa Evo",
			Rarity = "Epic",
			Multiplier = 2.7,
			IsEvolved = true,
			Look = { Style = "Ember", Primary = Color3.fromRGB(255, 210, 65), Secondary = Color3.fromRGB(255, 95, 40) },
		},
		MossFox_Evo = {
			DisplayName = "★ Zorro de Musgo Evo",
			Rarity = "Epic",
			Multiplier = 2.8,
			IsEvolved = true,
			Look = { Style = "Fox", Primary = Color3.fromRGB(255, 215, 75), Secondary = Color3.fromRGB(95, 245, 150) },
		},
		QuartzFox_Evo = {
			DisplayName = "★ Zorrito de Cuarzo Evo",
			Rarity = "Epic",
			Multiplier = 3.3,
			IsEvolved = true,
			Look = { Style = "Quartz", Primary = Color3.fromRGB(255, 220, 90), Secondary = Color3.fromRGB(190, 120, 255) },
		},
		MoonOwl_Evo = {
			DisplayName = "★ Búho Lunar Evo",
			Rarity = "Legendary",
			Multiplier = 3.8,
			IsEvolved = true,
			Look = { Style = "Owl", Primary = Color3.fromRGB(255, 220, 95), Secondary = Color3.fromRGB(120, 210, 255) },
		},
		CrystalTurtle_Evo = {
			DisplayName = "★ Tortuga Cristalina Evo",
			Rarity = "Legendary",
			Multiplier = 4.4,
			IsEvolved = true,
			Look = { Style = "Turtle", Primary = Color3.fromRGB(255, 215, 80), Secondary = Color3.fromRGB(90, 245, 255) },
		},
		EmeraldFawn_Evo = {
			DisplayName = "★ Cervatillo Esmeralda Evo",
			Rarity = "Legendary",
			Multiplier = 5.2,
			IsEvolved = true,
			Look = { Style = "Fawn", Primary = Color3.fromRGB(255, 220, 85), Secondary = Color3.fromRGB(70, 255, 155) },
		},
		AmethystDragon_Evo = {
			DisplayName = "★ Dragón de Amatista Evo",
			Rarity = "Legendary",
			Multiplier = 7.0,
			IsEvolved = true,
			Look = { Style = "Dragon", Primary = Color3.fromRGB(255, 215, 75), Secondary = Color3.fromRGB(215, 120, 255) },
		},
		AshFox_Evo = {
			DisplayName = "★ Zorro de Ceniza Evo",
			Rarity = "Epic",
			Multiplier = 3.5,
			IsEvolved = true,
			Look = { Style = "Ember", Primary = Color3.fromRGB(255, 210, 75), Secondary = Color3.fromRGB(255, 110, 40) },
		},
		ObsidianTurtle_Evo = {
			DisplayName = "★ Tortuga de Obsidiana Evo",
			Rarity = "Legendary",
			Multiplier = 5.0,
			IsEvolved = true,
			Look = { Style = "Turtle", Primary = Color3.fromRGB(255, 210, 75), Secondary = Color3.fromRGB(255, 95, 35) },
		},
		MagmaDragon_Evo = {
			DisplayName = "★ Dragón de Magma Evo",
			Rarity = "Legendary",
			Multiplier = 8.0,
			IsEvolved = true,
			Look = { Style = "Dragon", Primary = Color3.fromRGB(255, 225, 90), Secondary = Color3.fromRGB(255, 80, 30) },
		},
	},
}

return PetConfig
