-- Huevos. Para añadir uno: nueva entrada en Eggs con su coste, probabilidades,
-- requisito, aspecto y posición del santuario. El servidor valida al arrancar que las
-- probabilidades de cada huevo activo sumen exactamente 100 y que todas sus mascotas
-- existan en PetConfig. Un huevo con Enabled = false no se construye ni se vende
-- (para preparar huevos cuyas recompensas aún no existen).
--
-- Zone: zona donde está el santuario (StandOffset es relativo a su centro; por defecto el
-- bosque). RequiredZone: la zona debe estar desbloqueada para comprar (lo valida el servidor).
--
-- Precios, calibrados con las mejoras (coste del nivel N = 10 · 1.5^N; producción ≈ 1 + N):
-- - Bosque (100): ~ el precio de la mejora 5-6. Una Común (+10 %) a producción 6/s
--   se amortiza en ~3 min.
-- - Musgo (750, requiere nivel 6): ~ las mejoras 9-10. Valor medio +31 % por huevo.
-- - Ancestral (8 000, requiere nivel 16): ~ la mejora 16-17. Valor medio +65 % por huevo.
-- - Cristal (5 000, solo en el Valle Cristalino, que cuesta 2 500 desbloquear): ~6 min a
--   nivel 10-12. Valor medio +72 % por huevo y la primera Legendaria del juego.

local EggConfig = {
	-- Distancia máxima (studs) entre el jugador y el santuario para poder comprar.
	MaxPurchaseDistance = 18,
	-- Segundos mínimos entre aperturas (protección del servidor contra spam).
	PurchaseCooldown = 1.5,
	-- Mejora cuyo nivel desbloquea huevos (RequiredLevel).
	UnlockUpgradeId = "GeneratorPower",

	Eggs = {
		ForestEgg = {
			DisplayName = "Huevo del Bosque",
			Enabled = true,
			Order = 1,
			Cost = 100,
			RequiredLevel = 0,
			-- Probabilidades explícitas en porcentaje (enteros; deben sumar 100).
			Chances = {
				{ PetId = "Sproutling", Chance = 55 },
				{ PetId = "MushroomHopper", Chance = 35 },
				{ PetId = "EmberFox", Chance = 10 },
			},
			-- Posición del santuario relativa al cristal (X, Z). El spawn está en Z ≈ +25.
			StandOffset = Vector2.new(-20, 12),
			Look = {
				Style = "Speckled",
				Shell = Color3.fromRGB(240, 232, 200),
				Spots = Color3.fromRGB(110, 180, 96),
				Accent = Color3.fromRGB(156, 222, 112),
			},
		},

		MossEgg = {
			DisplayName = "Huevo de Musgo",
			Enabled = true,
			Order = 2,
			Cost = 750,
			RequiredLevel = 6, -- etapa Esmeralda del cristal
			Chances = {
				{ PetId = "MossFox", Chance = 75 },
				{ PetId = "MoonOwl", Chance = 25 },
			},
			StandOffset = Vector2.new(-28, 0),
			Look = {
				Style = "Mossy",
				Shell = Color3.fromRGB(104, 150, 78),
				Spots = Color3.fromRGB(70, 118, 56),
				Accent = Color3.fromRGB(120, 214, 120),
			},
		},

		AncientEgg = {
			DisplayName = "Huevo Ancestral",
			Enabled = true,
			Order = 3,
			Cost = 8000,
			RequiredLevel = 16, -- etapa Dorada del cristal
			Chances = {
				{ PetId = "MoonOwl", Chance = 70 },
				{ PetId = "EmeraldFawn", Chance = 30 },
			},
			StandOffset = Vector2.new(24, 10),
			Look = {
				Style = "Runic",
				Shell = Color3.fromRGB(92, 88, 104),
				Spots = Color3.fromRGB(244, 204, 110),
				Accent = Color3.fromRGB(244, 204, 110),
			},
		},

		CrystalEgg = {
			DisplayName = "Huevo de Cristal",
			Enabled = true,
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
			StandOffset = Vector2.new(18, 8), -- relativo al centro del Valle
			Look = {
				Style = "Crystalline",
				Shell = Color3.fromRGB(176, 214, 236),
				Spots = Color3.fromRGB(176, 120, 236),
				Accent = Color3.fromRGB(150, 196, 255),
			},
		},
	},
}

return EggConfig
