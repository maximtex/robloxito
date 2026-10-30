-- Oleadas: la mecánica principal del rediseño "solo disparar".
-- En cada zona hay un círculo con un altar y una columna de luz (Places), en la sala 3 de su
-- mazmorra (CaveConfig: Cueva de los Espinillos, Cueva de Amatista y Forja de Magma; se
-- entra por su boca y se cruzan las salas de los pequeños y de los medianos). Pulsas E y
-- empieza TU partida, con los enemigos y el jefe de esa zona; al ganar sale un cofre con 💰
-- y a veces una poción (Arenas.*.Chest). En la pradera oeste del Bosque queda el altar de la
-- práctica del tutorial.
-- Las partidas son PRIVADAS: mientras juegas, los enemigos normales desaparecen para ti (y
-- no te atacan) y solo ves y golpeas los de tu partida; otros jugadores pueden jugar la suya
-- en el mismo círculo a la vez sin verse los enemigos. Quien pulse E durante la cuenta atrás
-- de otra partida se une a ella (para jugar con amigos).
-- Cada enemigo revienta en 💎 y 💰 (EnemyService), matar sin parar sube la racha,
-- cada CardEvery oleadas eliges 1 de 3 mejoras que duran esa partida y en la última oleada
-- sale el jefe (uno para cada partida).
-- Lógica pura en WaveLogic; servidor en WaveService; cliente en WaveController y
-- WaveVisibility (quién ve qué).
--
-- [PROVISIONAL] Todos los números son un primer balance para probar la sensación en
-- Studio. Se ajustan jugando.

-- Por dónde salen los bichos de las oleadas en la sala del altar de las mazmorras (relativo
-- al altar: el pasillo de la sala 2, las paredes norte y sur y junto a las esquinas). Las tres
-- cuevas tienen la misma forma.
local CAVE_SPAWN_POINTS = {
	Vector2.new(48, 0),
	Vector2.new(0, -48),
	Vector2.new(0, 48),
	Vector2.new(30, -46),
	Vector2.new(-30, -46),
	Vector2.new(30, 46),
	Vector2.new(-30, 46),
}

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
		-- En la cueva los bichos salen por varios sitios de la sala (SpawnPoints, relativos al
		-- altar: el pasillo de la Galería, las paredes norte y sur y junto a las esquinas) y
		-- van a por ti desde allí (LeashRadius: hasta dónde te siguen, toda la sala).
		Forest = {
			Zone = "Forest",
			Offset = Vector2.new(-1220, 5),
			Arena = "Forest",
			Cave = true,
			SpawnPoints = CAVE_SPAWN_POINTS,
			SpawnJitter = 2.5,
			LeashRadius = 72,
			-- Dentro de la partida se cuenta toda la sala (no solo el círculo): para ir a por
			-- los que salen de las paredes sin perder la partida.
			InsideRadius = 64,
		},
		-- La práctica del tutorial: en el Bosque de Espinas (Zona 1), a la izquierda nada más
		-- llegar desde el pueblo (la llegada está en (0, -132)), en la pradera de los pequeños
		-- (Santiago la quitó del spawn: el pueblo se queda para tiendas, huevos y portales).
		Practice = { Zone = "ThornWoods", Offset = Vector2.new(-62, -109), Arena = "Tutorial", Practice = true },
		-- Sala 3 de la Cueva de Amatista y de la Forja de Magma (CaveConfig.Caves: la misma cueva
		-- movida a cada zona, así que el mismo Offset relativo a su zona).
		CrystalValley = {
			Zone = "CrystalValley",
			Offset = Vector2.new(-1220, 5),
			Arena = "CrystalValley",
			Cave = true,
			SpawnPoints = CAVE_SPAWN_POINTS,
			SpawnJitter = 2.5,
			LeashRadius = 72,
			InsideRadius = 64,
		},
		EmberCaldera = {
			Zone = "EmberCaldera",
			Offset = Vector2.new(-1220, 5),
			Arena = "EmberCaldera",
			Cave = true,
			SpawnPoints = CAVE_SPAWN_POINTS,
			SpawnJitter = 2.5,
			LeashRadius = 72,
			InsideRadius = 64,
		},
		-- Sala 3 de la Gruta Glacial (Tundra Helada)
		FrozenTundra = {
			Zone = "FrozenTundra",
			Offset = Vector2.new(-1220, 5),
			Arena = "FrozenTundra",
			Cave = true,
			SpawnPoints = CAVE_SPAWN_POINTS,
			SpawnJitter = 2.5,
			LeashRadius = 72,
			InsideRadius = 64,
		},
		-- Mundo 2 · Tierras Divididas: el Altar del Equilibrio, al aire libre en el centro del
		-- mapa (donde se juntan el volcán y el glaciar). Al final, el Coloso del Equilibrio, que
		-- se parte en dos (EnemyConfig.Types.EquilibriumColossus.Split).
		DividedLands = {
			Zone = "DividedLands",
			Offset = Vector2.new(0, -4),
			Arena = "DividedLands",
		},
		-- Y la sala 3 de su mazmorra, la Grieta Elemental (CaveConfig.Caves.DividedLands; la cueva
		-- del Bosque movida a esta zona: X - 2000, Y - 1): las Oleadas Gemelas.
		DividedLandsCave = {
			Zone = "DividedLands",
			Offset = Vector2.new(-3220, 4),
			Arena = "DividedLandsCave",
			Cave = true,
			SpawnPoints = CAVE_SPAWN_POINTS,
			SpawnJitter = 2.5,
			LeashRadius = 72,
			InsideRadius = 64,
		},
	},

	-- Modos de partida. Cada altar juega el de su círculo (Places.*.Arena); el de la práctica
	-- ("Tutorial"), solo con quien está en ese paso del tutorial (TutorialConfig, "Waves").
	-- RewardScale multiplica el 💰 de limpiar oleadas y de victoria (zonas más altas, más
	-- premio); los 💎 van por EconomyConfig.DiamondTier de la zona del modo (crecen mucho
	-- menos). VictoryScale escala solo el premio de victoria.
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
			Pool = { StarterThornling = 70, ThornCaster = 30, Thornling = 80, Barkbrute = 20, ForestWarden = 6 },
			-- Oleadas 1..9: cuántos de cada tipo. La última (10) es el jefe con escolta.
			Waves = {
				-- Las 4 primeras se pueden con el arma inicial; desde la 5 hacen falta mejoras.
				{ StarterThornling = 8 },
				{ StarterThornling = 10, Thornling = 1 },
				{ StarterThornling = 10, Thornling = 3, ThornCaster = 1 },
				{ StarterThornling = 8, Thornling = 6, ThornCaster = 2 },
				{ Thornling = 9, ThornCaster = 3, Barkbrute = 1 },
				{ StarterThornling = 12, Thornling = 8, ThornCaster = 2, Barkbrute = 2 },
				{ Thornling = 12, ThornCaster = 4, Barkbrute = 2 },
				{ StarterThornling = 14, Thornling = 9, ThornCaster = 3, Barkbrute = 3 },
				{ Thornling = 15, ThornCaster = 5, Barkbrute = 4 },
			},
			BossEscort = { StarterThornling = 6, Thornling = 2, ThornCaster = 2 },
			-- Cofre al ganar (para cada jugador): 💰 Money y, con PotionChance, una poción al azar
			-- (ItemConfig.Potions) para el inventario.
			Chest = { Money = 1500, PotionChance = 0.3 },
		},
		-- Valle Morado: Fragmentos y Gólems de Geoda; el Coloso de Amatista solo sale aquí.
		CrystalValley = {
			Place = "CrystalValley",
			Zone = "CrystalValley",
			DisplayName = "Oleadas del Coloso",
			Boss = "AmethystColossus",
			BossOnlyInWaves = true,
			Pool = { Shardling = 80, CrystalCaster = 30, GeodeGolem = 30, AmethystColossus = 6 },
			-- Oleadas 1..11 y la 12, el jefe (más que en el Bosque)
			Waves = {
				{ Shardling = 8 },
				{ Shardling = 10 },
				{ Shardling = 8, CrystalCaster = 2, GeodeGolem = 1 },
				{ Shardling = 8, CrystalCaster = 2, GeodeGolem = 2 },
				{ Shardling = 9, CrystalCaster = 3, GeodeGolem = 2 },
				{ Shardling = 9, CrystalCaster = 3, GeodeGolem = 3 },
				{ Shardling = 11, CrystalCaster = 3, GeodeGolem = 3 },
				{ Shardling = 11, CrystalCaster = 3, GeodeGolem = 4 },
				{ Shardling = 12, CrystalCaster = 4, GeodeGolem = 5 },
				{ Shardling = 14, CrystalCaster = 4, GeodeGolem = 5 },
				{ Shardling = 15, CrystalCaster = 5, GeodeGolem = 6 },
			},
			BossEscort = { Shardling = 6, GeodeGolem = 2, CrystalCaster = 2 },
			RewardScale = 3,
			-- Parte de los bichos de las oleadas que salen élite (EnemyConfig.Elite), como mucho
			-- EliteMax a la vez en cada tipo
			EliteChance = 0.08,
			EliteMax = 6,
			Chest = { Money = 6000, PotionChance = 0.4 },
		},
		-- Caldera de Brasas: Chispas y Gólems de Magma; el Titán de la Caldera solo sale aquí.
		EmberCaldera = {
			Place = "EmberCaldera",
			Zone = "EmberCaldera",
			DisplayName = "Oleadas del Titán",
			Boss = "CalderaTitan",
			BossOnlyInWaves = true,
			Pool = { Cinderling = 80, EmberCaster = 30, MagmaGolem = 30, CalderaTitan = 6 },
			-- Oleadas 1..14 y la 15, el jefe
			Waves = {
				{ Cinderling = 8 },
				{ Cinderling = 10 },
				{ Cinderling = 8, EmberCaster = 2, MagmaGolem = 1 },
				{ Cinderling = 8, EmberCaster = 2, MagmaGolem = 2 },
				{ Cinderling = 9, EmberCaster = 3, MagmaGolem = 2 },
				{ Cinderling = 9, EmberCaster = 3, MagmaGolem = 3 },
				{ Cinderling = 11, EmberCaster = 3, MagmaGolem = 3 },
				{ Cinderling = 11, EmberCaster = 3, MagmaGolem = 4 },
				{ Cinderling = 12, EmberCaster = 4, MagmaGolem = 5 },
				{ Cinderling = 14, EmberCaster = 4, MagmaGolem = 5 },
				{ Cinderling = 14, EmberCaster = 4, MagmaGolem = 6 },
				{ Cinderling = 15, EmberCaster = 5, MagmaGolem = 6 },
				{ Cinderling = 15, EmberCaster = 5, MagmaGolem = 7 },
				{ Cinderling = 17, EmberCaster = 5, MagmaGolem = 8 },
			},
			BossEscort = { Cinderling = 6, MagmaGolem = 2, EmberCaster = 2 },
			RewardScale = 8,
			EliteChance = 0.12,
			EliteMax = 8,
			Chest = { Money = 20000, PotionChance = 0.5 },
		},
		-- Tundra Helada: Lobos de Escarcha y Yetis; el Gólem de Hielo solo sale aquí.
		FrozenTundra = {
			Place = "FrozenTundra",
			Zone = "FrozenTundra",
			DisplayName = "Oleadas del Gólem de Hielo",
			Boss = "IceGolem",
			BossOnlyInWaves = true,
			Pool = { FrostWolf = 90, FrostCaster = 30, Yeti = 34, IceGolem = 6 },
			-- Oleadas 1..17 y la 18, el jefe
			Waves = {
				{ FrostWolf = 8 },
				{ FrostWolf = 10 },
				{ FrostWolf = 8, FrostCaster = 2, Yeti = 1 },
				{ FrostWolf = 9, FrostCaster = 3, Yeti = 1 },
				{ FrostWolf = 9, FrostCaster = 3, Yeti = 2 },
				{ FrostWolf = 9, FrostCaster = 3, Yeti = 3 },
				{ FrostWolf = 11, FrostCaster = 3, Yeti = 3 },
				{ FrostWolf = 11, FrostCaster = 3, Yeti = 4 },
				{ FrostWolf = 12, FrostCaster = 4, Yeti = 4 },
				{ FrostWolf = 12, FrostCaster = 4, Yeti = 5 },
				{ FrostWolf = 14, FrostCaster = 4, Yeti = 5 },
				{ FrostWolf = 14, FrostCaster = 4, Yeti = 6 },
				{ FrostWolf = 15, FrostCaster = 5, Yeti = 6 },
				{ FrostWolf = 15, FrostCaster = 5, Yeti = 7 },
				{ FrostWolf = 17, FrostCaster = 5, Yeti = 7 },
				{ FrostWolf = 17, FrostCaster = 5, Yeti = 8 },
				{ FrostWolf = 18, FrostCaster = 6, Yeti = 9 },
			},
			BossEscort = { FrostWolf = 8, Yeti = 3, FrostCaster = 2 },
			RewardScale = 20,
			EliteChance = 0.15,
			EliteMax = 10,
			Chest = { Money = 70000, PotionChance = 0.6 },
		},
		-- Mundo 2: bichos de fuego y de hielo a la vez y, en la última, el Coloso del Equilibrio
		-- (mitad fuego, mitad hielo): a la mitad de su vida se parte en Ignis y Glacius; se gana
		-- al derrotar a los dos.
		DividedLands = {
			Place = "DividedLands",
			Zone = "DividedLands",
			DisplayName = "Oleadas del Equilibrio",
			Boss = "EquilibriumColossus",
			BossOnlyInWaves = true,
			Pool = { EmberWisp = 60, FrostWisp = 60, LavaBrute = 18, FrostBrute = 18, EquilibriumColossus = 6, IgnisColossus = 6, GlaciusColossus = 6 },
			-- Oleadas 1..11 y la 12, el Coloso
			Waves = {
				{ EmberWisp = 5, FrostWisp = 5 },
				{ EmberWisp = 6, FrostWisp = 6 },
				{ EmberWisp = 6, FrostWisp = 6, LavaBrute = 1 },
				{ EmberWisp = 7, FrostWisp = 7, FrostBrute = 1 },
				{ EmberWisp = 7, FrostWisp = 7, LavaBrute = 1, FrostBrute = 1 },
				{ EmberWisp = 8, FrostWisp = 8, LavaBrute = 2, FrostBrute = 1 },
				{ EmberWisp = 8, FrostWisp = 8, LavaBrute = 1, FrostBrute = 2 },
				{ EmberWisp = 9, FrostWisp = 9, LavaBrute = 2, FrostBrute = 2 },
				{ EmberWisp = 10, FrostWisp = 10, LavaBrute = 3, FrostBrute = 2 },
				{ EmberWisp = 10, FrostWisp = 10, LavaBrute = 2, FrostBrute = 3 },
				{ EmberWisp = 11, FrostWisp = 11, LavaBrute = 3, FrostBrute = 3 },
			},
			BossEscort = { EmberWisp = 4, FrostWisp = 4 },
			RewardScale = 40,
			EliteChance = 0.15,
			EliteMax = 10,
			Chest = { Money = 300000, PotionChance = 0.7 },
		},
		-- La Grieta Elemental (sala 3 de su mazmorra): más oleadas, más élites y, al final, Ignis
		-- y Glacius juntos desde el principio (SplitAtStart: el Coloso ya llega partido).
		DividedLandsCave = {
			Place = "DividedLandsCave",
			Zone = "DividedLands",
			DisplayName = "Oleadas Gemelas",
			Boss = "EquilibriumColossus",
			SplitAtStart = true,
			Pool = { EmberWisp = 70, FrostWisp = 70, LavaBrute = 24, FrostBrute = 24, EquilibriumColossus = 6, IgnisColossus = 6, GlaciusColossus = 6 },
			-- Oleadas 1..14 y la 15, los gemelos
			Waves = {
				{ EmberWisp = 8 },
				{ FrostWisp = 8 },
				{ EmberWisp = 6, FrostWisp = 6, LavaBrute = 1 },
				{ EmberWisp = 6, FrostWisp = 6, FrostBrute = 1 },
				{ EmberWisp = 8, FrostWisp = 8, LavaBrute = 1, FrostBrute = 1 },
				{ EmberWisp = 12, LavaBrute = 3 },
				{ FrostWisp = 12, FrostBrute = 3 },
				{ EmberWisp = 9, FrostWisp = 9, LavaBrute = 2, FrostBrute = 2 },
				{ EmberWisp = 10, FrostWisp = 10, LavaBrute = 3, FrostBrute = 2 },
				{ EmberWisp = 10, FrostWisp = 10, LavaBrute = 2, FrostBrute = 3 },
				{ EmberWisp = 11, FrostWisp = 11, LavaBrute = 3, FrostBrute = 3 },
				{ EmberWisp = 12, FrostWisp = 12, LavaBrute = 4, FrostBrute = 3 },
				{ EmberWisp = 12, FrostWisp = 12, LavaBrute = 3, FrostBrute = 4 },
				{ EmberWisp = 14, FrostWisp = 14, LavaBrute = 4, FrostBrute = 4 },
			},
			BossEscort = { EmberWisp = 5, FrostWisp = 5, LavaBrute = 1, FrostBrute = 1 },
			RewardScale = 60,
			EliteChance = 0.25,
			EliteMax = 14,
			Chest = { Money = 600000, PotionChance = 0.8 },
		},
		-- Paso del tutorial: una partida corta y fácil con consejos en pantalla, en el altar del
		-- Bosque de Espinas junto a la llegada (Places.Practice).
		Tutorial = {
			Place = "Practice",
			Zone = "ThornWoods",
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
				Countdown = "¡Los enemigos van a salir a tu alrededor! Apunta con el ratón y haz clic para atacar.",
				[1] = "⚔️ Apunta y haz clic (o mantén pulsado). Muévete (WASD) para que no te alcancen.",
				[2] = "Cada enemigo suelta 💰 y 💎. ¡Mata sin parar para subir la 🔥 RACHA!",
				[3] = "¡Última oleada! Si un enemigo va a pegarte (¡!), Shift para esquivarlo con el dash.",
				Victory = "🏆 ¡Bien hecho! Las oleadas son la mejor forma de ganar 💎: vuelve cuando quieras.",
			},
		},
	},

	-- Partidas a la vez en el servidor y jugadores por partida.
	MaxRuns = 8,
	MaxPlayersPerRun = 4,

	-- Ritmo de la partida (segundos)
	StartCountdown = 3, -- durante la cuenta atrás, quien pulse E se une
	BreakSeconds = 0.6, -- entre oleadas (casi seguidas)
	CardSeconds = 10, -- para elegir mejora (luego se elige una al azar); las cartas tardan ~1,3 s en voltearse
	LeaveGrace = 6, -- sin nadie dentro (o todos caídos) durante esto: se pierde
	-- Aparición: de BatchSize en BatchSize cada SpawnInterval, sin pasar de los vivos a la
	-- vez de la oleada: AliveStart en la 1.ª y AliveGrowth más en cada una, hasta MaxAlive
	-- (las primeras no te rodean de golpe).
	SpawnInterval = 0.4,
	BatchSize = 5,
	AliveStart = 8,
	AliveGrowth = 2,
	MaxAlive = 20,
	-- Al limpiar cada oleada recuperas esta parte de tu vida máxima (antes 0.35: con eso y la
	-- regeneración de Roblox la vida casi no importaba; ahora hay que cuidarla).
	ClearHeal = 0.2,
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
	-- oleadas tienen sus premios por oleada y de victoria, el 💰 de cada bicho baja.
	MoneyMultiplier = 0.3,

	-- Premio al limpiar cada oleada (para cada jugador de la partida), por el número de la
	-- oleada:
	--   💎 = ClearDiamonds · w · DiamondTier de la zona · multiplicador de 💎
	--   💰 = ClearMoney · w · RewardScale
	-- (los "Diamonds" de aquí son 💎: EconomyConfig; el multiplicador es el del pase, la poción
	-- y las aventuras: PlayerDataService.diamondMultiplier). Los 💎 con decimales se redondean
	-- al azar (0.3 = un 30 % de las veces 1). Antes 1 · w · RewardScale: una partida de la
	-- Caldera daba ~900 💎 solo de oleadas.
	ClearDiamonds = 0.06,
	ClearMoney = 15,
	-- Premio de victoria (además del botín del jefe y su arma la primera vez):
	VictoryDiamonds = 2, -- 💎 · DiamondTier · multiplicador de 💎 (antes 40 · RewardScale)
	VictoryMoney = 600,

	-- Modo infinito (los modos con jefe; Endless = false en un modo lo quita): al caer el
	-- jefe se cobra la victoria y cada jugador tiene ChoiceSeconds para elegir si sigue. Las
	-- oleadas siguen sin fin con los enemigos de la última de hordas, CountGrowth más por cada
	-- oleada tras el jefe (y con más vida: HealthGrowth), y cada StrongEvery el doble de
	-- fuertes. Las mejoras siguen cada CardEvery. Se acaba cuando caen todos (sin perder nada).
	-- Cada BossEvery oleadas tras el jefe vuelve el jefe del modo (con su escolta), con
	-- BossHealthGrowth más de vida cada vez (pruebas con amigos: "el infinito no tiene jefes").
	Endless = { ChoiceSeconds = 10, CountGrowth = 0.12, StrongEvery = 5, BossEvery = 5, BossHealthGrowth = 0.4 },

	-- Mejoras cada CardEvery oleadas (tras la 3, la 6 y la 9), 1 de CardChoices. Cada modo
	-- puede cambiar CardEvery.
	CardEvery = 3,
	CardChoices = 3,

	-- Racha (en TODO el juego, no solo en las oleadas): cada enemigo que derrotas en menos
	-- de Window segundos desde el anterior la sube. Multiplica el botín (💎 y 💰):
	--   ×(1 + min(floor(racha / Step) · StepBonus, MaxBonus))   (x10 = ×1.1 … x100 = ×2)
	Streak = { Window = 2.5, Step = 10, StepBonus = 0.1, MaxBonus = 1 },

	-- Gema dorada: a veces un enemigo (nunca un jefe) suelta el botín multiplicado.
	GoldenOrb = { Chance = 0.03, Multiplier = 10 },

	-- Mejoras de la partida. MaxLevel = veces que se puede coger. Efectos (por nivel):
	--   Damage (+fracción de daño del arma), Cooldown (·factor del tiempo entre disparos),
	--   Chain (+saltos a otros enemigos), Splash (los disparos explotan: radio y fracción),
	--   Twin (probabilidad de un disparo extra), Explode (al matar, explosión: radio y
	--   veces el daño del disparo), Loot (+fracción de 💎 y 💰), Heal (vida por enemigo),
	--   StreakSeconds (+segundos de ventana de la racha).
	Cards = {
		Fury = { Order = 1, Icon = "🔥", Name = "Furia", Text = "+25 % de daño", MaxLevel = 3, Damage = 0.25 },
		Trigger = { Order = 2, Icon = "⚡", Name = "Gatillo fácil", Text = "Disparas un 15 % más rápido", MaxLevel = 3, Cooldown = 0.85 },
		Bounce = { Order = 3, Icon = "🔗", Name = "Rebote", Text = "El disparo salta a 1 enemigo más", MaxLevel = 3, Chain = 1 },
		Blast = { Order = 4, Icon = "💥", Name = "Estallido", Text = "Tus disparos explotan en área", MaxLevel = 3, Splash = { Radius = 5, RadiusPerLevel = 2, Fraction = 0.4 } },
		Twin = { Order = 5, Icon = "🎯", Name = "Doble disparo", Text = "25 % de disparar dos veces", MaxLevel = 3, Twin = 0.25 },
		Detonate = { Order = 6, Icon = "☄️", Name = "Reacción en cadena", Text = "Lo que matas explota", MaxLevel = 2, Explode = { Radius = 8, ShotMultiplier = 2 } },
		Greed = { Order = 7, Icon = "💰", Name = "Codicia", Text = "+30 % de 💎 y 💰 en esta partida", MaxLevel = 3, Loot = 0.3 },
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
