-- Eventos del mapa (pruebas con amigos: "el juego se siente repetitivo"): cada pocos minutos
-- pasa algo en una de las zonas del Mundo 1 con bichos y se avisa a todo el servidor. Lo
-- monta MapEventService (servidor), lo enseña MapEventController (aviso, columna de luz y
-- botón para ir con 🗺️ Viajar). La lógica pura (elegir zona, tipo y premios) está en
-- MapEventLogic.
--
-- Kinds (Weight: lo a menudo que sale cada uno):
--   Invasion        una horda de bichos de la zona alrededor de un punto; si la derrotáis
--                   entre todos antes de Duration, premio para quien esté cerca o haya
--                   matado alguno.
--   TreasureGoblin  un goblin con un saco de oro que no ataca y corretea por la zona; si lo
--                   matáis antes de que se escape (Lifetime), premio para quien esté cerca.
--   DiamondRain     caen gemas por la zona: cada una que tocas da 💎 y 💰 (con un tope por
--                   jugador); recoger MinForDone cuenta como evento hecho.
-- Premios: Money = minutos de 💰 de esa zona (ZoneConfig.Zones.*.MoneyPerMinute) y Diamonds =
-- 💎 · EconomyConfig.DiamondTier de la zona (con decimales: lo que falta es su probabilidad;
-- y por el multiplicador de 💎 del jugador). Hacer uno cuenta para el reto semanal
-- "Aventurero" (GameEvents "MapEventDone").

local MapEventConfig = {
	FirstDelay = 150, -- s desde que arranca el servidor hasta el primero
	Interval = { Min = 420, Max = 660 }, -- s entre el final de uno y el siguiente
	RetryDelay = 60, -- s para volver a probar si no hay nadie que pueda ir
	-- Zonas donde puede pasar (las del Mundo 1 con bichos). Se prefieren las que tienen a
	-- alguien dentro; si no, una que alguien tenga abierta.
	Zones = { "ThornWoods", "CrystalValley", "EmberCaldera", "FrozenTundra", "GoblinFortress" },
	NearRadius = 50, -- studs del punto del evento para contar como "estabas ahí"
	Kinds = {
		Invasion = {
			Order = 1,
			Weight = 3,
			Icon = "⚔️",
			Name = "Invasión",
			Text = "¡Una horda ataca %s! Derrotadla entre todos.",
			Duration = 150,
			Count = 14, -- bichos de la horda
			StrongEvery = 4, -- uno fuerte de cada tantos (si la zona tiene)
			Health = 1.3, -- · vida
			Ring = { Min = 8, Max = 22 }, -- dónde salen, alrededor del punto
			Reward = { Money = 2, Diamonds = 3 },
		},
		TreasureGoblin = {
			Order = 2,
			Weight = 2,
			Icon = "💰",
			Name = "Goblin del tesoro",
			Text = "¡Un goblin con un saco de oro corretea por %s! Atrápalo antes de que se escape.",
			Duration = 60, -- se escapa a los 60 s
			TypeId = "TreasureGoblin",
			-- Su vida y su botín, según los bichos normales de la zona (la media): vida ·
			-- HealthFactor y botín · RewardFactor
			HealthFactor = 10,
			RewardFactor = 30,
			RoamRadius = 26, -- corretea alrededor del punto
			RoamEvery = 2.5,
			Reward = { Money = 3, Diamonds = 4 },
		},
		DiamondRain = {
			Order = 3,
			Weight = 2,
			Icon = "💎",
			Name = "Lluvia de diamantes",
			Text = "¡Llueven gemas en %s! Corre a recogerlas.",
			Duration = 45,
			Count = 40, -- gemas
			Radius = 32,
			MaxPerPlayer = 15,
			MinForDone = 5,
			Reward = { Money = 0.06, Diamonds = 0.35 }, -- por gema
		},
	},
}

return MapEventConfig
