-- Oleadas: la mecánica principal del rediseño "solo disparar".
-- En cada zona hay un círculo con un altar y una columna de luz (Places): en el Bosque, en la
-- sala 3 de la Cueva de los Espinillos (CaveConfig: se entra por la boca de la colina oeste
-- y se cruzan las salas de los pequeños y de los medianos); en el Valle y la Caldera, a la
-- derecha de la llegada. Pulsas E y empieza TU partida, con los enemigos y el jefe de esa
-- zona. En la pradera oeste del Bosque queda el altar de la práctica del tutorial.
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
-- Studio. Se ajustan jugando.

local WaveConfig = {
	-- Medidas de todos los círculos.
	Place = {
		-- Dentro de este radio se cuenta como dentro de la partida (con un margen al salir).
		AreaRadius = 18,
		-- Los enemigos salen en un anillo alrededor del altar (que está en el centro), no
		-- pegados a ti: da un segundo para verlos venir.
		SpawnRadius = { Min = 11, Max = 16 },
		-- Para pulsar E en el altar.
		PromptDistance = 12,
	},

	-- Los círculos (uno por zona; varias partidas a la vez en cada uno) y el modo que se juega
	-- en cada uno. Offset relativo al centro de su zona, como el resto del mapa. Cada círculo
	-- es zona segura para los enemigos del mundo (EnemyConfig.Zones.*.SafeZones) y ninguno
	-- sale dentro ni cerca (prueba "waves").
	-- Cave: el círculo está en la sala del altar de la cueva (CaveConfig; la columna de luz
	-- sale por el hueco del techo de encima).
	-- Practice: solo para la práctica del tutorial (quien ya la hizo recibe un aviso de que
	-- las oleadas de verdad están en la cueva).
	Places = {
		-- Sala 3 de la Cueva de los Espinillos (CaveConfig.Rooms[3], centro (-1220, -20) del
		-- mundo; aquí relativo al centro del Bosque).
		Forest = { Zone = "Forest", Offset = Vector2.new(-1220, 5), Arena = "Forest", Cave = true },
		-- Pradera oeste, a unos 90 studs a la izquierda del spawn (que está en (0, 43)), con el
		-- borde del mapa a 15 studs del círculo: la práctica del tutorial.
		Practice = { Zone = "Forest", Offset = Vector2.new(-69, 98), Arena = "Tutorial", Practice = true },
		-- A la derecha de la llegada desde el portal ((0, -132) en las dos zonas).
		CrystalValley = { Zone = "CrystalValley", Offset = Vector2.new(36, -124), Arena = "CrystalValley" },
		EmberCaldera = { Zone = "EmberCaldera", Offset = Vector2.new(36, -124), Arena = "EmberCaldera" },
	},

	-- Modos de partida. Cada altar juega el de su círculo (Places.*.Arena); el de la práctica
	-- ("Tutorial"), solo con quien está en ese paso del tutorial (TutorialConfig, "Waves").
	-- RewardScale multiplica los premios de limpiar oleadas y de victoria (zonas más altas,
	-- más premio); VictoryScale, solo el de victoria.
	Arenas = {
		Forest = {
			Place = "Forest",
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
				-- Las 4 primeras se pueden con el arma inicial; desde la 5 hacen falta mejoras.
				{ StarterThornling = 8 },
				{ StarterThornling = 10, Thornling = 1 },
				{ StarterThornling = 10, Thornling = 4 },
				{ StarterThornling = 8, Thornling = 8 },
				{ Thornling = 12, Barkbrute = 1 },
				{ StarterThornling = 12, Thornling = 10, Barkbrute = 2 },
				{ Thornling = 16, Barkbrute = 2 },
				{ StarterThornling = 14, Thornling = 12, Barkbrute = 3 },
				{ Thornling = 20, Barkbrute = 4 },
			},
			BossEscort = { StarterThornling = 6, Thornling = 2 },
		},
		-- Valle Morado: Fragmentos y Gólems de Geoda; el Coloso de Amatista solo sale aquí.
		CrystalValley = {
			Place = "CrystalValley",
			Zone = "CrystalValley",
			DisplayName = "Oleadas del Coloso",
			Boss = "AmethystColossus",
			BossOnlyInWaves = true,
			Pool = { Shardling = 80, GeodeGolem = 30, AmethystColossus = 6 },
			Waves = {
				{ Shardling = 8 },
				{ Shardling = 10 },
				{ Shardling = 10, GeodeGolem = 1 },
				{ Shardling = 10, GeodeGolem = 2 },
				{ Shardling = 12, GeodeGolem = 2 },
				{ Shardling = 12, GeodeGolem = 3 },
				{ Shardling = 14, GeodeGolem = 3 },
				{ Shardling = 14, GeodeGolem = 4 },
				{ Shardling = 16, GeodeGolem = 5 },
			},
			BossEscort = { Shardling = 6, GeodeGolem = 2 },
			RewardScale = 3,
		},
		-- Caldera de Brasas: Chispas y Gólems de Magma; el Titán de la Caldera solo sale aquí.
		EmberCaldera = {
			Place = "EmberCaldera",
			Zone = "EmberCaldera",
			DisplayName = "Oleadas del Titán",
			Boss = "CalderaTitan",
			BossOnlyInWaves = true,
			Pool = { Cinderling = 80, MagmaGolem = 30, CalderaTitan = 6 },
			Waves = {
				{ Cinderling = 8 },
				{ Cinderling = 10 },
				{ Cinderling = 10, MagmaGolem = 1 },
				{ Cinderling = 10, MagmaGolem = 2 },
				{ Cinderling = 12, MagmaGolem = 2 },
				{ Cinderling = 12, MagmaGolem = 3 },
				{ Cinderling = 14, MagmaGolem = 3 },
				{ Cinderling = 14, MagmaGolem = 4 },
				{ Cinderling = 16, MagmaGolem = 5 },
			},
			BossEscort = { Cinderling = 6, MagmaGolem = 2 },
			RewardScale = 8,
		},
		-- Paso del tutorial: una partida corta y fácil con consejos en pantalla, en el altar de
		-- la pradera (Places.Practice).
		Tutorial = {
			Place = "Practice",
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
	StartCountdown = 3, -- durante la cuenta atrás, quien pulse E se une
	BreakSeconds = 0.6, -- entre oleadas (casi seguidas)
	CardSeconds = 8, -- para elegir mejora (luego se elige una al azar)
	LeaveGrace = 6, -- sin nadie dentro (o todos caídos) durante esto: se pierde
	-- Aparición: de BatchSize en BatchSize cada SpawnInterval, sin pasar de los vivos a la
	-- vez de la oleada: AliveStart en la 1.ª y AliveGrowth más en cada una, hasta MaxAlive
	-- (las primeras no te rodean de golpe).
	SpawnInterval = 0.4,
	BatchSize = 5,
	AliveStart = 8,
	AliveGrowth = 2,
	MaxAlive = 20,
	-- Al limpiar cada oleada recuperas esta parte de tu vida máxima.
	ClearHeal = 0.35,
	-- Daño que hacen los enemigos de la oleada w (el jefe, el suyo):
	--   DamageStart + DamageGrowth · (w - 1), hasta DamageMax
	-- Las primeras pegan flojo (se aprenden con el arma inicial); desde la 6 más que en el mundo.
	DamageStart = 0.5,
	DamageGrowth = 0.1,
	DamageMax = 1.3,
	-- La escolta del jefe sale poco a poco mientras el jefe siga vivo.
	EscortInterval = 6,

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
	MoneyMultiplier = 0.3,

	-- Premio al limpiar cada oleada (para cada jugador de la partida), por el número de la
	-- oleada:  ⚡ = ClearEnergy · w · poder de energía     💰 = ClearMoney · w
	ClearEnergy = 6,
	ClearMoney = 15,
	-- Premio de victoria (además del botín del jefe y su arma la primera vez):
	VictoryEnergy = 150, -- · poder de energía
	VictoryMoney = 600,

	-- Modo infinito (los modos con jefe; Endless = false en un modo lo quita): al caer el
	-- jefe se cobra la victoria y cada jugador tiene ChoiceSeconds para elegir si sigue. Las
	-- oleadas siguen sin fin con los enemigos de la última de hordas, CountGrowth más por cada
	-- oleada tras el jefe (y con más vida: HealthGrowth), y cada StrongEvery el doble de
	-- fuertes. Las mejoras siguen cada CardEvery. Se acaba cuando caen todos (sin perder nada).
	Endless = { ChoiceSeconds = 10, CountGrowth = 0.12, StrongEvery = 5 },

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

	-- Sonidos de la partida (solo cliente, WaveFx). Todos son de las bibliotecas con licencia
	-- de Roblox (Pro Sound Effects y APM Music): sirven en cualquier experiencia y se
	-- comprobó en Studio que cargan. Volume 0..1; Pitch cambia tono y velocidad.
	Sounds = {
		Tick = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.35, Pitch = 1.2 }, -- cuenta atrás y racha
		Whoosh = { Id = "rbxassetid://9126229267", Volume = 0.5, Pitch = 1 }, -- PSE: ráfaga rápida (0,6 s)
		WaveHit = { Id = "rbxassetid://1846902656", Volume = 0.55, Pitch = 1 }, -- APM: golpe grave de orquesta (empieza la oleada)
		Cleared = { Id = "rbxassetid://1839997962", Volume = 0.45, Pitch = 1 }, -- APM: "respuesta correcta" con brillos
		CardsOpen = { Id = "rbxassetid://9126228629", Volume = 0.4, Pitch = 1.1 }, -- PSE: zoom de cámara
		Chime = { Id = "rbxassetid://9116394876", Volume = 0.45, Pitch = 1.4 }, -- campanillas (las de las mejoras del juego)
		Pick = { Id = "rbxassetid://9116394876", Volume = 0.55, Pitch = 1.75 },
		BossGong = { Id = "rbxassetid://9114630316", Volume = 0.6, Pitch = 0.9 }, -- PSE: gong con cola larga
		BossRoar = { Id = "rbxassetid://9113980319", Volume = 0.5, Pitch = 0.8 }, -- PSE: rugido de bestia gigante
		Victory = { Id = "rbxassetid://1840091929", Volume = 0.6, Pitch = 1 }, -- APM: fanfarria de metales y percusión
		Record = { Id = "rbxassetid://1839997693", Volume = 0.55, Pitch = 1 }, -- APM: metales y coro épico
		Endless = { Id = "rbxassetid://9125807267", Volume = 0.6, Pitch = 0.9 }, -- PSE: ráfaga que sube
		EndlessEnd = { Id = "rbxassetid://1839997745", Volume = 0.5, Pitch = 1 }, -- APM: final orgulloso con cuerdas y coro
		Defeat = { Id = "rbxassetid://1839997989", Volume = 0.55, Pitch = 1 }, -- APM: melodía grave que baja
	},
}

return WaveConfig
