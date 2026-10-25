-- Oleadas: la mecánica principal del rediseño "solo disparar".
-- Entras al círculo de una arena, pulsas E en el pedestal y te llegan hordas que te
-- rodean. Cada enemigo revienta en orbes de ⚡ y 💰 (EnemyService), matar sin parar sube
-- la racha, cada CardEvery oleadas eliges 1 de 3 mejoras que duran esa partida y en la
-- última oleada sale el jefe de la zona.
-- Lógica pura en WaveLogic; servidor en WaveService; cliente en WaveController.
--
-- [PROVISIONAL] Todos los números son un primer balance para probar la sensación en
-- Studio (enemigos y armas actuales del Bosque). Se ajustan jugando.

local WaveConfig = {
	-- Arenas de oleadas. La arena usa el círculo del jefe de su zona
	-- (EnemyConfig.Zones.<Zone>.Boss.Arena): mismo centro y el mismo jefe para la última.
	Arenas = {
		Forest = {
			Zone = "Forest",
			DisplayName = "Oleadas del Guardián",
			Boss = "ForestWarden",
			-- El jefe ya no está siempre en su arena: solo sale en la última oleada.
			BossOnlyInWaves = true,
			-- Radio (studs desde el centro de la arena) en el que se cuenta como dentro de la
			-- partida y hasta donde persiguen los enemigos de las oleadas.
			AreaRadius = 28,
			-- Los enemigos salen en un anillo dentro del círculo de runas (radio 16).
			SpawnRadius = { Min = 8, Max = 14 },
			-- Pedestal para empezar: en la entrada de la arena, a esta distancia del centro.
			PedestalDistance = 21,
			-- Enemigos que se crean una vez y se reutilizan (como mucho estos de cada tipo).
			Pool = { StarterThornling = 12, Thornling = 12, Barkbrute = 3 },
			-- Oleadas 1..9: cuántos de cada tipo. La última (10) es el jefe con escolta.
			Waves = {
				{ StarterThornling = 8 },
				{ StarterThornling = 11 },
				{ StarterThornling = 8, Thornling = 4 },
				{ StarterThornling = 6, Thornling = 8 },
				{ Thornling = 10, Barkbrute = 1 },
				{ StarterThornling = 10, Thornling = 8, Barkbrute = 1 },
				{ Thornling = 14, Barkbrute = 2 },
				{ StarterThornling = 12, Thornling = 10, Barkbrute = 2 },
				{ Thornling = 16, Barkbrute = 3 },
			},
			BossEscort = { StarterThornling = 6 },
		},
	},

	-- Ritmo de la partida (segundos)
	StartCountdown = 3,
	BreakSeconds = 3, -- entre oleadas
	CardSeconds = 12, -- para elegir mejora (luego se elige una al azar)
	ResultSeconds = 6, -- antes de poder empezar otra
	LeaveGrace = 6, -- sin nadie dentro (o todos caídos) durante esto: se pierde
	-- Aparición: de BatchSize en BatchSize cada SpawnInterval, sin pasar de MaxAlive vivos.
	SpawnInterval = 0.9,
	BatchSize = 3,
	MaxAlive = 14,
	-- La escolta del jefe sale poco a poco mientras el jefe siga vivo.
	EscortInterval = 9,

	-- Dificultad y premios por oleada (oleada w, n jugadores dentro):
	--   vida = base · (1 + HealthGrowth · (w - 1)) · (1 + PlayerHealth · (n - 1))
	--   botín = base · (1 + RewardGrowth · (w - 1))
	HealthGrowth = 0.12,
	PlayerHealth = 0.4,
	RewardGrowth = 0.1,
	-- Vida del jefe con varios jugadores (además de la de su configuración)
	BossPlayerHealth = 0.6,

	-- Premio al limpiar cada oleada (para cada jugador dentro), por el número de la oleada:
	--   ⚡ = ClearEnergy · w · poder de energía     💰 = ClearMoney · w
	ClearEnergy = 4,
	ClearMoney = 40,
	-- Premio de victoria (además del botín del jefe y su arma la primera vez):
	VictoryEnergy = 120, -- · poder de energía
	VictoryMoney = 1500,

	-- Mejoras cada CardEvery oleadas (tras la 3, la 6 y la 9), 1 de CardChoices.
	CardEvery = 3,
	CardChoices = 3,

	-- Racha (en TODO el juego, no solo en las oleadas): cada enemigo que derrotas en menos
	-- de Window segundos desde el anterior la sube. Multiplica el botín (⚡ y 💰):
	--   ×(1 + min(floor(racha / Step) · StepBonus, MaxBonus))   (x10 = ×1.1 … x100 = ×2)
	Streak = { Window = 2.5, Step = 10, StepBonus = 0.1, MaxBonus = 1 },

	-- Orbe dorado: a veces un enemigo (nunca un jefe) suelta el botín multiplicado.
	GoldenOrb = { Chance = 0.03, Multiplier = 10 },

	-- Mejoras de la partida. MaxLevel = veces que se puede coger. Efectos (por nivel):
	--   Damage (+fracción de daño del arma), Cooldown (·factor del tiempo entre disparos),
	--   Chain (+saltos a otros enemigos), Splash (los disparos explotan: radio y fracción),
	--   Twin (probabilidad de un disparo extra), Explode (al matar, explosión: radio y
	--   veces el daño del disparo), Loot (+fracción de ⚡ y 💰), Heal (vida por enemigo),
	--   StreakSeconds (+segundos de ventana de la racha).
	Cards = {
		Fury = { Order = 1, Icon = "🔥", Name = "Furia", Text = "+25 % de daño", MaxLevel = 3, Damage = 0.25 },
		Trigger = { Order = 2, Icon = "⚡", Name = "Gatillo fácil", Text = "Disparas un 15 % más rápido", MaxLevel = 3, Cooldown = 0.85 },
		Bounce = { Order = 3, Icon = "🔗", Name = "Rebote", Text = "El disparo salta a 1 enemigo más", MaxLevel = 3, Chain = 1 },
		Blast = { Order = 4, Icon = "💥", Name = "Estallido", Text = "Tus disparos explotan en área", MaxLevel = 3, Splash = { Radius = 5, RadiusPerLevel = 2, Fraction = 0.4 } },
		Twin = { Order = 5, Icon = "🎯", Name = "Doble disparo", Text = "25 % de disparar dos veces", MaxLevel = 3, Twin = 0.25 },
		Detonate = { Order = 6, Icon = "☄️", Name = "Reacción en cadena", Text = "Lo que matas explota", MaxLevel = 2, Explode = { Radius = 8, ShotMultiplier = 2 } },
		Greed = { Order = 7, Icon = "💰", Name = "Codicia", Text = "+30 % de ⚡ y 💰 en esta partida", MaxLevel = 3, Loot = 0.3 },
		Vampire = { Order = 8, Icon = "🩸", Name = "Vampiro", Text = "+3 de vida por enemigo", MaxLevel = 3, Heal = 3 },
		LongStreak = { Order = 9, Icon = "⏱️", Name = "Racha larga", Text = "La racha aguanta 1 s más", MaxLevel = 2, StreakSeconds = 1 },
	},

	-- Protección del servidor contra peticiones repetidas.
	ActionCooldown = 0.25,
}

return WaveConfig
