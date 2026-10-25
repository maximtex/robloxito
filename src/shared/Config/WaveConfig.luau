-- Oleadas: la mecánica principal del rediseño "solo disparar".
-- Delante del spawn, en la plaza, hay un círculo con un altar: pulsas E y empieza TU partida.
-- Las partidas son PRIVADAS: mientras juegas, los enemigos normales desaparecen para ti (y
-- no te atacan) y solo ves y golpeas los de tu partida; otros jugadores pueden jugar la suya
-- en el mismo círculo a la vez sin verse los enemigos. Quien pulse E durante la cuenta atrás
-- de otra partida se une a ella (para jugar con amigos).
-- Cada enemigo revienta en orbes de ⚡ y 💰 (EnemyService), matar sin parar sube la racha,
-- cada CardEvery oleadas eliges 1 de 3 mejoras que duran esa partida y en la última oleada
-- sale el jefe (uno para cada partida).
-- Lógica pura en WaveLogic; servidor en WaveService; cliente en WaveController y
-- WaveVisibility (quién ve qué).
--
-- [PROVISIONAL] Todos los números son un primer balance para probar la sensación en
-- Studio (enemigos y armas actuales del Bosque). Se ajustan jugando.

local WaveConfig = {
	-- El círculo de las oleadas (uno para todas las partidas). Offset relativo al centro de
	-- su zona, como el resto del mapa: (0, 15) es la plaza del pueblo, delante del spawn
	-- (el spawn está en (0, 43) y mira hacia aquí).
	Place = {
		Zone = "Forest",
		Offset = Vector2.new(0, 15),
		-- Dentro de este radio se cuenta como dentro de la partida (con un margen al salir).
		AreaRadius = 18,
		-- Los enemigos salen en un anillo alrededor del altar (que está en el centro).
		SpawnRadius = { Min = 8, Max = 15 },
		-- Para pulsar E en el altar.
		PromptDistance = 12,
	},

	-- Modos de partida. El altar elige el modo: "Tutorial" para quien está en ese paso del
	-- tutorial (TutorialConfig, paso "Waves"); "Forest" para todos los demás.
	Arenas = {
		Forest = {
			Zone = "Forest", -- de qué zona son los enemigos
			DisplayName = "Oleadas del Guardián",
			Boss = "ForestWarden",
			-- El jefe ya no está siempre en su arena del Bosque: solo sale en la última oleada.
			BossOnlyInWaves = true,
			-- Enemigos que se crean una vez y se reutilizan (como mucho estos de cada tipo,
			-- para TODAS las partidas a la vez).
			Pool = { StarterThornling = 70, Thornling = 80, Barkbrute = 20, ForestWarden = 6 },
			-- Oleadas 1..9: cuántos de cada tipo. La última (10) es el jefe con escolta.
			Waves = {
				{ StarterThornling = 10 },
				{ StarterThornling = 12, Thornling = 2 },
				{ StarterThornling = 10, Thornling = 6 },
				{ StarterThornling = 8, Thornling = 10 },
				{ Thornling = 12, Barkbrute = 1 },
				{ StarterThornling = 12, Thornling = 10, Barkbrute = 2 },
				{ Thornling = 16, Barkbrute = 2 },
				{ StarterThornling = 14, Thornling = 12, Barkbrute = 3 },
				{ Thornling = 20, Barkbrute = 4 },
			},
			BossEscort = { StarterThornling = 6, Thornling = 2 },
		},
		-- Paso del tutorial: una partida corta y fácil con consejos en pantalla.
		Tutorial = {
			Zone = "Forest",
			DisplayName = "Oleada de práctica",
			Tutorial = true,
			Pool = { StarterThornling = 70, Thornling = 80 },
			Waves = {
				{ StarterThornling = 4 },
				{ StarterThornling = 6 },
				{ StarterThornling = 6, Thornling = 2 },
			},
			CardEvery = 2, -- una mejora tras la 2.ª, para aprender a elegir
			VictoryScale = 0.2, -- premio de victoria más pequeño (es una práctica)
			-- Consejos: al empezar (Countdown), al empezar cada oleada (su número) y al ganar
			-- (Victory). Cómo elegir mejora lo explica siempre la propia ventana de cartas.
			Hints = {
				Countdown = "¡Los enemigos van a salir a tu alrededor! Tu arma dispara SOLA.",
				[1] = "🔫 Tu arma dispara sola. Muévete (WASD) para que no te alcancen.",
				[2] = "Cada enemigo suelta ⚡ y 💰. ¡Mata sin parar para subir la 🔥 RACHA!",
				[3] = "¡Última oleada! Acaba con todos.",
				Victory = "🏆 ¡Bien hecho! Las oleadas son la mejor forma de ganar ⚡: vuelve cuando quieras.",
			},
		},
	},

	-- Partidas a la vez en el servidor y jugadores por partida.
	MaxRuns = 8,
	MaxPlayersPerRun = 4,

	-- Ritmo de la partida (segundos)
	StartCountdown = 4, -- durante la cuenta atrás, quien pulse E se une
	BreakSeconds = 1, -- entre oleadas
	CardSeconds = 10, -- para elegir mejora (luego se elige una al azar)
	LeaveGrace = 6, -- sin nadie dentro (o todos caídos) durante esto: se pierde
	-- Aparición: de BatchSize en BatchSize cada SpawnInterval, sin pasar de MaxAlive vivos.
	SpawnInterval = 0.6,
	BatchSize = 4,
	MaxAlive = 18,
	-- La escolta del jefe sale poco a poco mientras el jefe siga vivo.
	EscortInterval = 8,

	-- Dificultad y premios por oleada (oleada w, n jugadores dentro):
	--   vida = base · (1 + HealthGrowth · (w - 1)) · (1 + PlayerHealth · (n - 1))
	--   botín = base · (1 + RewardGrowth · (w - 1))
	HealthGrowth = 0.2,
	PlayerHealth = 0.4,
	RewardGrowth = 0.1,
	-- Vida del jefe con varios jugadores (además de la de su configuración)
	BossPlayerHealth = 0.6,
	-- Dinero de los enemigos de las oleadas (golpes y derrota) frente a los del mundo: las
	-- oleadas dan mucha ⚡ pero el 💰 se queda normal.
	MoneyMultiplier = 0.4,

	-- Premio al limpiar cada oleada (para cada jugador de la partida), por el número de la
	-- oleada:  ⚡ = ClearEnergy · w · poder de energía     💰 = ClearMoney · w
	ClearEnergy = 6,
	ClearMoney = 15,
	-- Premio de victoria (además del botín del jefe y su arma la primera vez):
	VictoryEnergy = 150, -- · poder de energía
	VictoryMoney = 600,

	-- Mejoras cada CardEvery oleadas (tras la 3, la 6 y la 9), 1 de CardChoices. Cada modo
	-- puede cambiar CardEvery.
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
