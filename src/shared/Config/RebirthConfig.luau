-- Renacimiento (Rebirth). Al renacer se reinician el 💰, el nivel de las armas y la
-- Resonancia del Cristal; se conservan los 💎, mascotas, núcleos, zonas, misiones y los
-- huevos ya desbloqueados. A cambio:
-- - Multiplicador permanente del "poder" (el de los 💎 y los premios en 💰) y de daño,
--   que crece con cada renacimiento.
-- - Fichas de renacimiento para la tienda de ventajas permanentes (Shop).
-- La lógica pura está en RebirthLogic; el servidor (RebirthService) decide todo.
--
-- Ritmo: el primer renacimiento pide Resonancia nivel 15 y cada siguiente 5 niveles más,
-- hasta el nivel máximo de la mejora. Ajustado en la ronda 10 con una simulación del avance
-- (cristal + núcleos + mascotas, sin contar misiones, combate ni premios): con 15, el primer
-- renacimiento llega a la ~media hora de juego atento (con 20 tardaba ~1 h) y la Caldera
-- (3 renacimientos) hacia la hora y media o dos horas. Sigue siendo ajustable con datos reales.

local RebirthConfig = {
	-- Mejora que se reinicia y que marca el requisito (la Resonancia del Cristal).
	UpgradeId = "GeneratorPower",

	-- Nivel de Resonancia necesario para el renacimiento n + 1 (n = renacimientos hechos):
	--   min(nivel máximo de la mejora, BaseLevel + LevelStep · n)
	Requirement = { BaseLevel = 15, LevelStep = 5 },

	-- Premio permanente por renacimiento (se suman: 3 renacimientos = ×2.5 de energía).
	EnergyBonus = 0.5, -- +50 % de energía por renacimiento
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
			Description = "+25 % de energía al derrotar enemigos",
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
		HeadStart = {
			Order = 4,
			DisplayName = "Inicio rápido",
			Icon = "🚀",
			Description = "Cada renacimiento empieza con +4 niveles de Resonancia",
			PerLevel = 4,
			Costs = { 2, 4, 8 },
		},
		Dreams = {
			Order = 5,
			DisplayName = "Sueño profundo",
			Icon = "🌙",
			Description = "+1 h de producción mientras no juegas",
			PerLevel = 3600,
			Costs = { 1, 2, 3, 5 },
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
	MaxHaloGems = 12, -- gemas que orbitan el cristal (una por renacimiento, hasta este tope)
	Sounds = {
		Rebirth = "rbxassetid://9116394876",
		Burst = "rbxasset://sounds/impact_explosion_03.mp3",
		Shop = "rbxasset://sounds/electronicpingshort.wav",
	},
}

return RebirthConfig
