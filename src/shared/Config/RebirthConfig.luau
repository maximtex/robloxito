-- Renacimiento (Rebirth). Al renacer se reinician el 💰 y el nivel de las armas; se
-- conservan los 💎, mascotas, núcleos, zonas y misiones. A cambio:
-- - Multiplicador permanente del botín en 💰 de los enemigos y del daño, que crece con
--   cada renacimiento.
-- - Fichas de renacimiento para la tienda de ventajas permanentes (Shop).
-- La lógica pura está en RebirthLogic; el servidor (RebirthService) decide todo.
--
-- Requisito (Requirement) del renacimiento n + 1 (n = renacimientos hechos), las dos cosas:
-- - Ganar las oleadas del modo Waves[n + 1] (derrotar a su jefe en la última oleada) DESDE
--   EL ÚLTIMO RENACIMIENTO (cuenta lo de PetData.Rebirth.Cycle, que se vacía al renacer).
--   Pasada la lista, el último modo en el modo infinito: EndlessExtraWaves oleadas más por
--   cada renacimiento de más.
-- - Tener 💰 MoneyBase, que se multiplica por MoneyGrowth en cada renacimiento hasta el
--   LateGrowthFrom (sin incluirlo) y por LateMoneyGrowth desde ese (se paga al renacer; el
--   resto del 💰 se reinicia): 25 k, 75 k, 225 k, 675 k, 2,025 M y luego ×1,5.
-- Enabled = false lo bloquea ("Próximamente").

local RebirthConfig = {
	Enabled = true,

	Requirement = {
		-- Modo de oleadas (WaveConfig.Arenas) que pide cada renacimiento, en orden.
		Waves = { "Forest", "CrystalValley", "EmberCaldera", "FrozenTundra", "DividedLands" },
		EndlessExtraWaves = 3,
		MoneyBase = 25000,
		MoneyGrowth = 3, -- renacimientos 2..5
		LateGrowthFrom = 6, -- desde el 6.º renacimiento crece con LateMoneyGrowth
		LateMoneyGrowth = 1.5,
	},

	-- Premio permanente por renacimiento (se suman: 3 renacimientos = ×2.5 de botín).
	LootBonus = 0.5, -- +50 % de 💰 de los enemigos por renacimiento
	DamageBonus = 0.1, -- +10 % de daño por renacimiento

	-- Fichas que da el renacimiento número k: Base + PerRebirth · (k - 1) (1, 2, 3...).
	Tokens = { Base = 1, PerRebirth = 1 },

	-- Tope de seguridad (muy por encima de cualquier partida real).
	MaxRebirths = 1000,

	-- Protección del servidor contra solicitudes repetidas (segundos).
	RebirthCooldown = 3,
	ShopCooldown = 0.4,

	-- Tienda de ventajas permanentes. Costs[n] = fichas del nivel n (el nivel máximo es
	-- #Costs). PerLevel: cuánto da cada nivel (su unidad depende de la ventaja).
	Shop = {
		PetSlot = {
			Order = 1,
			DisplayName = "Espacio de mascota",
			Icon = "🐾",
			Description = "+1 mascota equipada a la vez",
			PerLevel = 1,
			Costs = { 3, 10 },
		},
		Loot = {
			Order = 2,
			DisplayName = "Botín abundante",
			Icon = "💰",
			Description = "+25 % de 💰 al derrotar enemigos",
			PerLevel = 0.25,
			Costs = { 1, 2, 4, 6 },
		},
		Strike = {
			Order = 3,
			DisplayName = "Golpe renacido",
			Icon = "⚔",
			Description = "+15 % de daño (ataques, habilidades y mascotas)",
			PerLevel = 0.15,
			Costs = { 1, 2, 4, 6 },
		},
	},

	-- Presentación (cliente).
	Colors = {
		Glow = Color3.fromRGB(255, 214, 120),
		Halo = {
			Color3.fromRGB(255, 214, 120), -- 1-4: dorado
			Color3.fromRGB(150, 220, 255), -- 5-9: celeste
			Color3.fromRGB(214, 150, 255), -- 10-19: violeta
			Color3.fromRGB(255, 120, 150), -- 20+: rubí
		},
	},
	HaloTiers = { 1, 5, 10, 20 }, -- renacimientos a partir de los que cambia el color del aura
	Sounds = {
		Rebirth = "rbxassetid://9116394876",
		Burst = "rbxasset://sounds/impact_explosion_03.mp3",
		Shop = "rbxasset://sounds/electronicpingshort.wav",
	},
}

return RebirthConfig
