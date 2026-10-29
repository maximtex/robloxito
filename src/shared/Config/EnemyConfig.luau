-- Enemigos ("cosos") y su distribución por zonas estilo Pet Simulator:
-- - Repartidos por todo el mapa del Bosque (lados izquierdo y derecho de las parcelas y campo norte),
--   pero NUNCA dentro de las parcelas, tiendas, huevos ni el camino central.
-- - Sueltan dinero (Reward) al recibir golpes y al morir.
-- - Atacan al jugador que se les acerca (DetectRange) y lo persiguen dentro de su radio
--   (LeashRange), sin entrar en las zonas seguras. El jugador tiene 100 de vida y se cura
--   poco a poco (1 por segundo): los normales casi no hacen daño solos (un Espinillo tarda
--   casi un minuto en matarte y muere en 2 s); en grupo, los fuertes y los jefes sí hay que
--   vigilarlos. Los jefes además lanzan un golpe de área anunciado en el suelo (Slam) que
--   se esquiva saliendo del círculo.
-- - Cada golpe se avisa (AttackWindup segundos): el bicho se queda quieto mirando a su
--   objetivo, se le encienden los ojos y a ese jugador le sale un ¡! encima (AttackWarning,
--   en el cliente). Da tiempo a apartarse (el golpe solo alcanza por delante) o a bloquear
--   con el Guerrero (justo al final, parada perfecta).

local EnemyConfig = {
	AiTickSeconds = 0.15,
	-- Todos los bichos (y jefes) tienen esta vez su MaxHealth: más duros de farmear
	HealthScale = 1.5,

	-- Bichos élite de las mazmorras del Valle y la Caldera (CaveConfig.Caves.*.EliteChance en
	-- las salas y WaveConfig.Arenas.*.EliteChance en las oleadas): más grandes (Scale), brillan
	-- (Color) y tienen más vida, pegan más y dan más botín. Su nombre lleva Prefix.
	Elite = { Health = 3, Damage = 1.3, Reward = 3, Scale = 1.3, Color = Color3.fromRGB(255, 214, 90), Prefix = "⭐ " },
	StuckSeconds = 6,
	-- Persecución de los jefes (anti "kiteo", pruebas con amigos; EnemyLogic.pursuitBoost): si su
	-- objetivo lleva Delay s a más de Gap studs de su alcance, acelera Ramp por segundo hasta Max ×
	-- su velocidad, sin pasar de CatchUp × la velocidad de su objetivo. Se le pasa al alcanzarlo.
	Pursuit = { Delay = 1.5, Ramp = 0.6, Max = 2.2, CatchUp = 0.95, Gap = 4 },

	Types = {
		-- Bosque --------------------------------------------------------------------
		StarterThornling = {
			DisplayName = "Espinillo Bebé",
			Kind = "Normal",
			MaxHealth = 20,
			Damage = 3,
			AttackRange = 4.5,
			AttackCooldown = 1.6,
			AttackWindup = 0.65,
			WalkSpeed = 11,
			DetectRange = 12,
			LeashRange = 18,
			Reward = 25,
			RespawnSeconds = 3,
			-- Modelo 3D: arbolito.glb, más pequeño (Server.Util.ModelosZona1). Eyes = color de sus ojos.
			Look = { Style = "ArbolitoBebe", Primary = Color3.fromRGB(110, 68, 38), Secondary = Color3.fromRGB(255, 235, 120), Eyes = Color3.fromRGB(255, 243, 160) },
		},
		Thornling = {
			DisplayName = "Espinillo",
			Kind = "Normal",
			MaxHealth = 40,
			Damage = 5,
			AttackRange = 4.5,
			AttackCooldown = 1.6,
			AttackWindup = 0.6,
			WalkSpeed = 13,
			DetectRange = 12,
			LeashRange = 18,
			Reward = 35,
			RespawnSeconds = 4,
			Trait = { Kind = "BrambleSlow", SlowFactor = 0.85, Duration = 1.0 },
			-- Modelo 3D: arbolito.glb (Server.Util.ModelosZona1)
			Look = { Style = "Arbolito", Primary = Color3.fromRGB(110, 68, 38), Secondary = Color3.fromRGB(127, 209, 59), Eyes = Color3.fromRGB(255, 243, 160) },
		},
		Barkbrute = {
			DisplayName = "Bruto de Corteza",
			Kind = "Strong",
			MaxHealth = 180,
			Damage = 12,
			AttackRange = 7,
			AttackCooldown = 2.6,
			AttackWindup = 0.95,
			WalkSpeed = 10,
			DetectRange = 14,
			LeashRange = 20,
			Reward = 140,
			RespawnSeconds = 6,
			Trait = { Kind = "BrambleSlow", SlowFactor = 0.78, Duration = 1.4 },
			-- Modelo 3D: arbol_guardian.glb (Server.Util.ModelosZona1)
			Look = { Style = "ArbolGuardian", Primary = Color3.fromRGB(110, 68, 38), Secondary = Color3.fromRGB(127, 209, 59), Eyes = Color3.fromRGB(255, 243, 160) },
		},
		-- Lanzador del Bosque (oleadas): lanza semillas de espinas
		ThornCaster = {
			DisplayName = "Brujo Espinoso",
			Kind = "Normal",
			MaxHealth = 30,
			Damage = 3,
			AttackRange = 4,
			AttackCooldown = 1.6,
			AttackWindup = 0.6,
			WalkSpeed = 11,
			DetectRange = 16,
			LeashRange = 22,
			Reward = 35,
			RespawnSeconds = 4,
			Trait = { Kind = "BrambleSlow", SlowFactor = 0.85, Duration = 1.0 },
			-- A distancia (EnemyService.Ai): se para a Range, dispara cada Cooldown (avisado Windup s)
			-- y si te acercas mientras recarga retrocede hasta Keep. La bola va a donde estabas.
			Ranged = { Range = 24, Keep = 12, Damage = 5, Cooldown = 2.8, Windup = 0.75, Speed = 32, Radius = 2, Size = 1.1 },
			Look = { Style = "Caster", Theme = "Forest", Primary = Color3.fromRGB(96, 70, 44), Secondary = Color3.fromRGB(150, 255, 80), Eyes = Color3.fromRGB(190, 255, 120) },
		},
		ForestWarden = {
			DisplayName = "Guardián del Bosque",
			Kind = "Boss",
			MaxHealth = 1200,
			Damage = 18,
			AttackRange = 9,
			AttackCooldown = 2.2,
			AttackWindup = 0.8,
			WalkSpeed = 10,
			DetectRange = 0, -- los jefes usan su arena (Zones.*.Boss.Arena)
			LeashRange = 18,
			Reward = 1200,
			DiamondReward = 3, -- 💎 extra para cada jugador que lo derrota (BossRewardService); antes 60
			RespawnSeconds = 12,
			-- IA de jefe (EnemyService.updateBoss): vigila su arena, persigue con rutas
			-- (PathfindingService) dentro de su territorio, avisa cada ataque y descansa tras él.
			Brain = { DetectRange = 22, Territory = 34, LockSeconds = 4, RecoverSeconds = 0.9 },
			-- Identidad: raíces que atrapan y ralentizan donde estás
			Roots = { Interval = 11, Telegraph = 1.2, Radius = 7, Range = 30, Damage = 8, SlowFactor = 0.5, SlowSeconds = 2.5 },
			-- Golpe de área anunciado con un círculo en el suelo
			Slam = { Interval = 9, Telegraph = 1.4, Radius = 10, Damage = 22 },
			-- Furia bajo la mitad de vida: más rápido y golpes de área más seguidos
			Enrage = { HealthFraction = 0.5, SpeedMultiplier = 1.3, SlamIntervalMultiplier = 0.65 },
			-- Peligro de su arena (BossAttacks): espinas que salen del suelo (y ralentizan), avisado en el suelo cerca de cada jugador
			Hazard = { Style = "Spikes", Interval = 8, Telegraph = 1.3, Radius = 5, Damage = 10, Count = 2, SlowFactor = 0.6, SlowSeconds = 1.5, Color = Color3.fromRGB(140, 255, 58) },
			-- Modelo 3D: gigante_del_bosque.glb (Server.Util.ModelosZona1)
			Look = { Style = "GiganteDelBosque", Primary = Color3.fromRGB(110, 68, 38), Secondary = Color3.fromRGB(140, 255, 58), Eyes = Color3.fromRGB(140, 255, 58) },
		},

		-- Valle Morado ---------------------------------------------------------------
		Shardling = {
			DisplayName = "Fragmento Errante",
			Kind = "Normal",
			MaxHealth = 150,
			Damage = 7,
			AttackRange = 4.5,
			AttackCooldown = 1.4,
			AttackWindup = 0.55,
			WalkSpeed = 14,
			DetectRange = 12,
			LeashRange = 18,
			Reward = 110,
			RespawnSeconds = 4,
			Trait = { Kind = "CrystalWard", ShieldReduction = 0.45 },
			Look = { Style = "Shard", Primary = Color3.fromRGB(150, 110, 240), Secondary = Color3.fromRGB(110, 226, 255), Eyes = Color3.fromRGB(34, 22, 48) },
		},
		GeodeGolem = {
			DisplayName = "Gólem de Geoda",
			Kind = "Strong",
			MaxHealth = 650,
			Damage = 16,
			AttackRange = 7.5,
			AttackCooldown = 2.8,
			AttackWindup = 1.0,
			WalkSpeed = 10,
			DetectRange = 14,
			LeashRange = 20,
			Reward = 450,
			RespawnSeconds = 6,
			Trait = { Kind = "CrystalWard", ShieldReduction = 0.50 },
			Look = { Style = "Golem", Primary = Color3.fromRGB(98, 102, 126), Secondary = Color3.fromRGB(96, 220, 210), Eyes = Color3.fromRGB(110, 170, 255) },
		},
		-- Lanzador del Valle (oleadas): dispara esquirlas de cristal
		CrystalCaster = {
			DisplayName = "Hechicero de Cristal",
			Kind = "Normal",
			MaxHealth = 110,
			Damage = 6,
			AttackRange = 4,
			AttackCooldown = 1.6,
			AttackWindup = 0.6,
			WalkSpeed = 12,
			DetectRange = 16,
			LeashRange = 22,
			Reward = 110,
			RespawnSeconds = 4,
			Trait = { Kind = "CrystalWard", ShieldReduction = 0.40 },
			-- A distancia (EnemyService.Ai): se para a Range, dispara cada Cooldown (avisado Windup s)
			-- y si te acercas mientras recarga retrocede hasta Keep. La bola va a donde estabas.
			Ranged = { Range = 26, Keep = 12, Damage = 9, Cooldown = 2.6, Windup = 0.7, Speed = 36, Radius = 2, Size = 1.1 },
			Look = { Style = "Caster", Theme = "Crystal", Primary = Color3.fromRGB(92, 62, 150), Secondary = Color3.fromRGB(110, 226, 255), Eyes = Color3.fromRGB(230, 200, 255) },
		},
		AmethystColossus = {
			DisplayName = "Coloso de Amatista",
			Kind = "Boss",
			MaxHealth = 4500,
			Damage = 24,
			AttackRange = 10,
			AttackCooldown = 2.4,
			AttackWindup = 0.8,
			WalkSpeed = 10,
			DetectRange = 0, -- los jefes usan su arena (Zones.*.Boss.Arena)
			LeashRange = 18,
			Reward = 4000,
			DiamondReward = 6, -- 💎 extra para cada jugador que lo derrota (BossRewardService); antes 150
			RespawnSeconds = 12,
			Brain = { DetectRange = 24, Territory = 40, LockSeconds = 4, RecoverSeconds = 0.8 },
			-- Identidad: embestidas en línea recta (se esquivan apartándose de la franja roja)
			Charge = { Interval = 8, Telegraph = 1.0, Distance = 26, Width = 6, Damage = 28, Speed = 42, MinRange = 8, MaxRange = 30 },
			-- Golpe de área anunciado con un círculo en el suelo
			Slam = { Interval = 8, Telegraph = 1.3, Radius = 12, Damage = 30 },
			-- Furia bajo la mitad de vida: más rápido y golpes de área más seguidos
			Enrage = { HealthFraction = 0.5, SpeedMultiplier = 1.3, SlamIntervalMultiplier = 0.65 },
			-- Peligro de su arena (BossAttacks): cristales que caen del techo, avisado en el suelo cerca de cada jugador
			Hazard = { Style = "Crystal", Interval = 7, Telegraph = 1.2, Radius = 5, Damage = 16, Count = 3, Color = Color3.fromRGB(200, 140, 255) },
			Look = { Style = "Colossus", Primary = Color3.fromRGB(86, 84, 108), Secondary = Color3.fromRGB(176, 120, 236), Eyes = Color3.fromRGB(230, 180, 255) },
		},

		-- Caldera de Brasas -----------------------------------------------------------
		Cinderling = {
			DisplayName = "Chispa Ígnea",
			Kind = "Normal",
			MaxHealth = 520,
			Damage = 8,
			AttackRange = 4.5,
			AttackCooldown = 1.3,
			AttackWindup = 0.55,
			WalkSpeed = 15,
			DetectRange = 12,
			LeashRange = 18,
			Reward = 320,
			RespawnSeconds = 4,
			Trait = { Kind = "EmberPool", Radius = 4.0, Duration = 2.4, TickDamage = 5 },
			Look = { Style = "FlameImp", Primary = Color3.fromRGB(214, 72, 32), Secondary = Color3.fromRGB(255, 210, 68), Eyes = Color3.fromRGB(44, 20, 20) },
		},
		MagmaGolem = {
			DisplayName = "Gólem de Magma",
			Kind = "Strong",
			MaxHealth = 2200,
			Damage = 20,
			AttackRange = 7.5,
			AttackCooldown = 2.8,
			AttackWindup = 1.0,
			WalkSpeed = 11,
			DetectRange = 14,
			LeashRange = 20,
			Reward = 1300,
			RespawnSeconds = 6,
			Trait = { Kind = "EmberPool", Radius = 5.4, Duration = 3.0, TickDamage = 9 },
			Look = { Style = "MagmaBrute", Material = "Basalt", Primary = Color3.fromRGB(74, 54, 48), Secondary = Color3.fromRGB(255, 118, 36), Eyes = Color3.fromRGB(255, 200, 90) },
		},
		-- Lanzador de la Caldera (oleadas): bolas de fuego
		EmberCaster = {
			DisplayName = "Piromante",
			Kind = "Normal",
			MaxHealth = 380,
			Damage = 8,
			AttackRange = 4,
			AttackCooldown = 1.6,
			AttackWindup = 0.6,
			WalkSpeed = 13,
			DetectRange = 16,
			LeashRange = 22,
			Reward = 320,
			RespawnSeconds = 4,
			Trait = { Kind = "EmberPool", Radius = 3.8, Duration = 2.2, TickDamage = 5 },
			-- A distancia (EnemyService.Ai): se para a Range, dispara cada Cooldown (avisado Windup s)
			-- y si te acercas mientras recarga retrocede hasta Keep. La bola va a donde estabas.
			Ranged = { Range = 26, Keep = 12, Damage = 12, Cooldown = 2.4, Windup = 0.65, Speed = 40, Radius = 2.2, Size = 1.3 },
			Look = { Style = "Caster", Theme = "Ember", Primary = Color3.fromRGB(120, 36, 28), Secondary = Color3.fromRGB(255, 150, 40), Eyes = Color3.fromRGB(255, 220, 120) },
		},
		CalderaTitan = {
			DisplayName = "Titán de la Caldera",
			Kind = "Boss",
			MaxHealth = 15000,
			Damage = 28,
			AttackRange = 10,
			AttackCooldown = 2.3,
			AttackWindup = 0.8,
			WalkSpeed = 11,
			DetectRange = 0, -- los jefes usan su arena (Zones.*.Boss.Arena)
			LeashRange = 18,
			Reward = 12000,
			DiamondReward = 12, -- 💎 extra para cada jugador que lo derrota (BossRewardService); antes 400
			RespawnSeconds = 15,
			Brain = { DetectRange = 26, Territory = 42, LockSeconds = 4, RecoverSeconds = 0.8 },
			-- Identidad: saltos que caen donde estabas y ráfagas de bolas de fuego
			Leap = { Interval = 10, Telegraph = 1.1, Radius = 9, Damage = 30, MinRange = 10, MaxRange = 32 },
			Volley = { Interval = 6, Count = 3, Damage = 14, Speed = 45, Telegraph = 0.6, Range = 40, Radius = 3 },
			-- Golpe de área anunciado con un círculo en el suelo
			Slam = { Interval = 8, Telegraph = 1.3, Radius = 13, Damage = 35 },
			-- Furia bajo la mitad de vida: más rápido y golpes de área más seguidos
			Enrage = { HealthFraction = 0.5, SpeedMultiplier = 1.3, SlamIntervalMultiplier = 0.65 },
			-- Peligro de su arena (BossAttacks): erupciones de lava, avisado en el suelo cerca de cada jugador
			Hazard = { Style = "Lava", Interval = 7, Telegraph = 1.3, Radius = 6, Damage = 20, Count = 3, Color = Color3.fromRGB(255, 110, 30) },
			Look = { Style = "VolcanoTitan", Material = "Basalt", Primary = Color3.fromRGB(64, 48, 46), Secondary = Color3.fromRGB(255, 118, 36), Eyes = Color3.fromRGB(255, 232, 150) },
		},

		-- Tundra Helada -------------------------------------------------------------------
		FrostWolf = {
			DisplayName = "Lobo de Escarcha",
			Kind = "Normal",
			MaxHealth = 1700,
			Damage = 10,
			AttackRange = 5,
			AttackCooldown = 1.2,
			AttackWindup = 0.5,
			WalkSpeed = 17, -- rápidos: llegan en manada
			DetectRange = 13,
			LeashRange = 20,
			Reward = 1000,
			RespawnSeconds = 4,
			Trait = { Kind = "FrostChill", SlowFactor = 0.78, Duration = 1.5 },
			Look = { Style = "Wolf", Primary = Color3.fromRGB(226, 236, 248), Secondary = Color3.fromRGB(120, 190, 255), Eyes = Color3.fromRGB(70, 200, 255) },
		},
		Yeti = {
			DisplayName = "Yeti",
			Kind = "Strong",
			MaxHealth = 7000,
			Damage = 24,
			AttackRange = 8,
			AttackCooldown = 2.6,
			AttackWindup = 0.95,
			WalkSpeed = 12,
			DetectRange = 14,
			LeashRange = 20,
			Reward = 4000,
			RespawnSeconds = 6,
			Trait = { Kind = "FrostChill", SlowFactor = 0.72, Duration = 1.8 },
			Look = { Style = "Yeti", Primary = Color3.fromRGB(240, 246, 255), Secondary = Color3.fromRGB(110, 150, 200), Eyes = Color3.fromRGB(70, 170, 255) },
		},
		-- Lanzador de la Tundra (oleadas): carámbanos
		FrostCaster = {
			DisplayName = "Chamán de Escarcha",
			Kind = "Normal",
			MaxHealth = 1200,
			Damage = 10,
			AttackRange = 4,
			AttackCooldown = 1.6,
			AttackWindup = 0.6,
			WalkSpeed = 14,
			DetectRange = 16,
			LeashRange = 22,
			Reward = 1000,
			RespawnSeconds = 4,
			Trait = { Kind = "FrostChill", SlowFactor = 0.78, Duration = 1.5 },
			-- A distancia (EnemyService.Ai): se para a Range, dispara cada Cooldown (avisado Windup s)
			-- y si te acercas mientras recarga retrocede hasta Keep. La bola va a donde estabas.
			Ranged = { Range = 28, Keep = 14, Damage = 14, Cooldown = 2.4, Windup = 0.65, Speed = 44, Radius = 2.2, Size = 1.3 },
			Look = { Style = "Caster", Theme = "Frost", Primary = Color3.fromRGB(70, 110, 170), Secondary = Color3.fromRGB(170, 235, 255), Eyes = Color3.fromRGB(200, 245, 255) },
		},
		IceGolem = {
			DisplayName = "Gólem de Hielo",
			Kind = "Boss",
			MaxHealth = 50000,
			Damage = 32,
			AttackRange = 10,
			AttackCooldown = 2.2,
			AttackWindup = 0.75,
			WalkSpeed = 12,
			DetectRange = 0, -- los jefes usan su arena (Zones.*.Boss.Arena)
			LeashRange = 18,
			Reward = 36000,
			DiamondReward = 20, -- 💎 extra para cada jugador que lo derrota (BossRewardService); antes 1000
			RespawnSeconds = 15,
			Brain = { DetectRange = 28, Territory = 44, LockSeconds = 4, RecoverSeconds = 0.7 },
			-- Identidad: embestidas sobre el hielo y ráfagas de carámbanos
			Charge = { Interval = 7, Telegraph = 0.9, Distance = 30, Width = 7, Damage = 32, Speed = 50, MinRange = 8, MaxRange = 32 },
			Volley = { Interval = 6, Count = 4, Damage = 15, Speed = 50, Telegraph = 0.55, Range = 42, Radius = 3 },
			-- Golpe de área anunciado con un círculo en el suelo
			Slam = { Interval = 7, Telegraph = 1.2, Radius = 14, Damage = 38 },
			Enrage = { HealthFraction = 0.5, SpeedMultiplier = 1.35, SlamIntervalMultiplier = 0.6 },
			-- Peligro de su arena (BossAttacks): carámbanos que congelan (ralentizan), avisado en el suelo cerca de cada jugador
			Hazard = { Style = "Ice", Interval = 7, Telegraph = 1.3, Radius = 6, Damage = 16, Count = 3, SlowFactor = 0.5, SlowSeconds = 2.5, Color = Color3.fromRGB(140, 220, 255) },
			Look = { Style = "Colossus", Material = "Glacier", Primary = Color3.fromRGB(170, 212, 240), Secondary = Color3.fromRGB(120, 230, 255), Eyes = Color3.fromRGB(230, 250, 255) },
		},

		-- Fortaleza Goblin -------------------------------------------------------------------
		Goblin = {
			DisplayName = "Goblin",
			Kind = "Normal",
			MaxHealth = 5500,
			Damage = 14,
			AttackRange = 4.5,
			AttackCooldown = 1.2,
			AttackWindup = 0.5,
			WalkSpeed = 18,
			DetectRange = 16, -- te salen al paso por el camino
			LeashRange = 24,
			Reward = 3200,
			RespawnSeconds = 4,
			Trait = { Kind = "BattleFrenzy", HealthFraction = 0.45, SpeedMultiplier = 1.25 },
			Look = { Style = "Goblin", Primary = Color3.fromRGB(116, 186, 72), Secondary = Color3.fromRGB(122, 86, 52), Eyes = Color3.fromRGB(255, 214, 60) },
		},
		GoblinBrute = {
			DisplayName = "Goblin Bruto",
			Kind = "Strong",
			MaxHealth = 22000,
			Damage = 32,
			AttackRange = 8,
			AttackCooldown = 2.4,
			AttackWindup = 0.9,
			WalkSpeed = 14,
			DetectRange = 16,
			LeashRange = 24,
			Reward = 12000,
			RespawnSeconds = 7,
			Trait = { Kind = "BattleFrenzy", HealthFraction = 0.50, SpeedMultiplier = 1.30 },
			Look = { Style = "GoblinBrute", Primary = Color3.fromRGB(96, 152, 62), Secondary = Color3.fromRGB(120, 124, 136), Eyes = Color3.fromRGB(255, 120, 60) },
		},
		-- Rey Goblin (jefe final del Mundo 1): enorme, SUPER rápido (corre más que tú) y duro.
		-- Embiste, salta sobre ti, lanza dagas y golpea el suelo sin apenas descansar. Abre el
		-- portal gigante al Mundo 2 (ZoneConfig.Zones.World2.RequiredBoss).
		GoblinKing = {
			DisplayName = "Rey Goblin",
			Kind = "Boss",
			MaxHealth = 160000,
			Damage = 34,
			AttackRange = 11,
			AttackCooldown = 1.1,
			AttackWindup = 0.65,
			WalkSpeed = 30,
			DetectRange = 0, -- usa su arena (Zones.*.Boss.Arena)
			LeashRange = 18,
			Reward = 120000,
			DiamondReward = 30, -- 💎 extra para cada jugador que lo derrota (BossRewardService); antes 3000
			RespawnSeconds = 30,
			Brain = { DetectRange = 36, Territory = 52, LockSeconds = 3, RecoverSeconds = 0.3 },
			Charge = { Interval = 5, Telegraph = 0.7, Distance = 36, Width = 8, Damage = 40, Speed = 85, MinRange = 8, MaxRange = 38 },
			Leap = { Interval = 7, Telegraph = 0.8, Radius = 11, Damage = 42, MinRange = 10, MaxRange = 38 },
			Volley = { Interval = 5, Count = 5, Damage = 14, Speed = 75, Telegraph = 0.4, Range = 46, Radius = 3 },
			Slam = { Interval = 6, Telegraph = 0.9, Radius = 15, Damage = 48 },
			-- Furia bajo la mitad de vida: todavía más rápido y ataques mucho más seguidos
			Enrage = { HealthFraction = 0.5, SpeedMultiplier = 1.35, SlamIntervalMultiplier = 0.55 },
			-- Peligro de su arena (BossAttacks): rocas que tiran desde las murallas, avisado en el suelo cerca de cada jugador
			Hazard = { Style = "Rock", Interval = 6.5, Telegraph = 1.1, Radius = 6, Damage = 26, Count = 3, Color = Color3.fromRGB(130, 110, 90) },
			Scale = 1.45, -- enorme: casi 30 studs de alto (EnemyService lo agranda al crearlo)
			Look = { Style = "GoblinKing", Primary = Color3.fromRGB(104, 172, 64), Secondary = Color3.fromRGB(150, 40, 60), Eyes = Color3.fromRGB(255, 70, 50) },
		},
		-- Tierras Divididas (Mundo 2) -----------------------------------------------------------
		-- Cada bicho tiene su gemelo del otro elemento: la misma forma con los colores opuestos.
		-- Los de fuego viven en la mitad del volcán (oeste) y los de hielo en la del glaciar (este).
		EmberWisp = {
			DisplayName = "Espíritu de Brasa",
			Kind = "Normal",
			MaxHealth = 15000,
			Damage = 18,
			AttackRange = 4.5,
			AttackCooldown = 1.2,
			AttackWindup = 0.5,
			WalkSpeed = 17,
			DetectRange = 15,
			LeashRange = 22,
			Reward = 8000,
			RespawnSeconds = 4,
			Trait = { Kind = "EmberPool", Radius = 4.5, Duration = 2.6, TickDamage = 12 },
			Look = { Style = "FlameImp", Primary = Color3.fromRGB(255, 112, 36), Secondary = Color3.fromRGB(255, 220, 90), Eyes = Color3.fromRGB(120, 20, 10) },
		},
		FrostWisp = {
			DisplayName = "Espíritu de Escarcha",
			Kind = "Normal",
			MaxHealth = 15000,
			Damage = 18,
			AttackRange = 4.5,
			AttackCooldown = 1.2,
			AttackWindup = 0.5,
			WalkSpeed = 17,
			DetectRange = 15,
			LeashRange = 22,
			Reward = 8000,
			RespawnSeconds = 4,
			Trait = { Kind = "FrostChill", SlowFactor = 0.76, Duration = 1.6 },
			-- Lanza esquirlas de hielo a distancia (EnemyService.Ai; los de fuego siguen cuerpo a cuerpo)
			Ranged = { Range = 26, Keep = 12, Damage = 20, Cooldown = 2.2, Windup = 0.6, Speed = 46, Radius = 2.2, Size = 1.3 },
			Look = { Style = "Shard", Primary = Color3.fromRGB(110, 200, 255), Secondary = Color3.fromRGB(235, 250, 255), Eyes = Color3.fromRGB(20, 60, 140) },
		},
		LavaBrute = {
			DisplayName = "Bruto de Lava",
			Kind = "Strong",
			MaxHealth = 60000,
			Damage = 38,
			AttackRange = 8,
			AttackCooldown = 2.4,
			AttackWindup = 0.9,
			WalkSpeed = 13,
			DetectRange = 15,
			LeashRange = 22,
			Reward = 26000,
			RespawnSeconds = 6,
			Trait = { Kind = "EmberPool", Radius = 5.8, Duration = 3.0, TickDamage = 16 },
			Look = { Style = "MagmaBrute", Material = "Basalt", Primary = Color3.fromRGB(78, 52, 46), Secondary = Color3.fromRGB(255, 120, 30), Eyes = Color3.fromRGB(255, 214, 90) },
		},
		FrostBrute = {
			DisplayName = "Bruto de Escarcha",
			Kind = "Strong",
			MaxHealth = 60000,
			Damage = 38,
			AttackRange = 8,
			AttackCooldown = 2.4,
			AttackWindup = 0.9,
			WalkSpeed = 13,
			DetectRange = 15,
			LeashRange = 22,
			Reward = 26000,
			RespawnSeconds = 6,
			Trait = { Kind = "FrostChill", SlowFactor = 0.72, Duration = 1.8 },
			Look = { Style = "Golem", Material = "Glacier", Primary = Color3.fromRGB(176, 214, 242), Secondary = Color3.fromRGB(90, 200, 255), Eyes = Color3.fromRGB(230, 250, 255) },
		},
		-- Coloso del Equilibrio (jefe de las Tierras Divididas): gigante mitad fuego y mitad hielo
		-- (Look.Split: su lado derecho lleva los colores del hielo). Sale en la última oleada del
		-- Altar del Equilibrio (WaveConfig) y, al bajarle la mitad de la vida (Split), explota y
		-- se parte en Ignis (fuego) y Glacius (hielo): hay que derrotar a los dos. Él no da
		-- botín (se retira al partirse); lo dan los dos gemelos.
		EquilibriumColossus = {
			DisplayName = "Coloso del Equilibrio",
			Kind = "Boss",
			MaxHealth = 400000,
			Damage = 40,
			AttackRange = 12,
			AttackCooldown = 2,
			AttackWindup = 0.8,
			WalkSpeed = 13,
			DetectRange = 0, -- usa su arena (Zones.*.Boss.Arena)
			LeashRange = 20,
			Reward = 100000,
			RespawnSeconds = 30,
			Brain = { DetectRange = 40, Territory = 56, LockSeconds = 4, RecoverSeconds = 0.6 },
			-- Embiste, lanza bolas mitad fuego mitad hielo y golpea el suelo
			Charge = { Interval = 7, Telegraph = 0.9, Distance = 34, Width = 9, Damage = 44, Speed = 60, MinRange = 10, MaxRange = 36 },
			Volley = { Interval = 6, Count = 6, Damage = 18, Speed = 55, Telegraph = 0.6, Range = 46, Radius = 3.4 },
			Slam = { Interval = 7, Telegraph = 1.2, Radius = 17, Damage = 50 },
			Enrage = { HealthFraction = 0.75, SpeedMultiplier = 1.2, SlamIntervalMultiplier = 0.8 },
			-- Peligro de su arena (BossAttacks): erupciones de lava, avisado en el suelo cerca de cada jugador
			Hazard = { Style = "Lava", Interval = 7, Telegraph = 1.2, Radius = 6, Damage = 22, Count = 3, Color = Color3.fromRGB(255, 150, 60) },
			-- Al llegar a esta parte de la vida se parte en estos dos, a Spread studs a cada lado
			Split = { HealthFraction = 0.5, Into = { "IgnisColossus", "GlaciusColossus" }, Spread = 10 },
			Scale = 1.7, -- enorme: más de 30 studs de alto
			Look = {
				Style = "Colossus",
				Material = "CrackedLava",
				Primary = Color3.fromRGB(150, 46, 26),
				Secondary = Color3.fromRGB(255, 140, 40),
				Eyes = Color3.fromRGB(255, 236, 160),
				Split = { Material = "Ice", Primary = Color3.fromRGB(196, 228, 255), Secondary = Color3.fromRGB(90, 200, 255), Eyes = Color3.fromRGB(225, 250, 255) },
			},
		},
		-- Las dos mitades del Coloso del Equilibrio. Ignis salta sobre ti y lanza fuego; Glacius
		-- embiste sobre el hielo y lanza carámbanos. Cada uno da su botín y sus 💎.
		IgnisColossus = {
			DisplayName = "Ignis, el Coloso de Fuego",
			Kind = "Boss",
			MaxHealth = 220000,
			Damage = 38,
			AttackRange = 10,
			AttackCooldown = 1.8,
			AttackWindup = 0.75,
			WalkSpeed = 15,
			DetectRange = 0,
			LeashRange = 20,
			Reward = 150000,
			DiamondReward = 25, -- 💎 extra para cada jugador que lo derrota (BossRewardService); antes 4000 (y son dos)
			RespawnSeconds = 30,
			Brain = { DetectRange = 40, Territory = 56, LockSeconds = 3, RecoverSeconds = 0.5 },
			Leap = { Interval = 7, Telegraph = 0.9, Radius = 11, Damage = 44, MinRange = 10, MaxRange = 36 },
			Volley = { Interval = 5, Count = 5, Damage = 18, Speed = 55, Telegraph = 0.5, Range = 44, Radius = 3 },
			Slam = { Interval = 7, Telegraph = 1.1, Radius = 14, Damage = 46 },
			Enrage = { HealthFraction = 0.5, SpeedMultiplier = 1.3, SlamIntervalMultiplier = 0.65 },
			-- Peligro de su arena (BossAttacks): erupciones de lava, avisado en el suelo cerca de cada jugador
			Hazard = { Style = "Lava", Interval = 7.5, Telegraph = 1.2, Radius = 6, Damage = 22, Count = 2, Color = Color3.fromRGB(255, 110, 30) },
			Scale = 1.2,
			Look = { Style = "VolcanoTitan", Material = "CrackedLava", Primary = Color3.fromRGB(150, 46, 26), Secondary = Color3.fromRGB(255, 140, 40), Eyes = Color3.fromRGB(255, 236, 160) },
		},
		GlaciusColossus = {
			DisplayName = "Glacius, el Coloso de Hielo",
			Kind = "Boss",
			MaxHealth = 220000,
			Damage = 38,
			AttackRange = 10,
			AttackCooldown = 1.8,
			AttackWindup = 0.75,
			WalkSpeed = 15,
			DetectRange = 0,
			LeashRange = 20,
			Reward = 150000,
			DiamondReward = 25, -- 💎 extra para cada jugador que lo derrota (BossRewardService); antes 4000 (y son dos)
			RespawnSeconds = 30,
			Brain = { DetectRange = 40, Territory = 56, LockSeconds = 3, RecoverSeconds = 0.5 },
			Charge = { Interval = 6, Telegraph = 0.85, Distance = 32, Width = 8, Damage = 44, Speed = 62, MinRange = 8, MaxRange = 34 },
			Volley = { Interval = 5, Count = 5, Damage = 18, Speed = 58, Telegraph = 0.5, Range = 44, Radius = 3 },
			Slam = { Interval = 7, Telegraph = 1.1, Radius = 14, Damage = 46 },
			Enrage = { HealthFraction = 0.5, SpeedMultiplier = 1.3, SlamIntervalMultiplier = 0.65 },
			-- Peligro de su arena (BossAttacks): carámbanos que congelan, avisado en el suelo cerca de cada jugador
			Hazard = { Style = "Ice", Interval = 7.5, Telegraph = 1.2, Radius = 6, Damage = 18, Count = 2, SlowFactor = 0.5, SlowSeconds = 2, Color = Color3.fromRGB(140, 220, 255) },
			Scale = 1.2,
			Look = { Style = "Colossus", Material = "Ice", Primary = Color3.fromRGB(196, 228, 255), Secondary = Color3.fromRGB(90, 200, 255), Eyes = Color3.fromRGB(225, 250, 255) },
		},
	},

	Zones = {
		Forest = {
			RewardMultiplier = 1,
			-- Centro del pueblo sin monstruos: la plaza, el Jardín de los Huevos, la avenida hasta
			-- el portal del Valle, el cofre, el evolucionador y las tablas de clasificación. Ahí
			-- no aparece ninguno (EnemyService no crea los que caigan dentro) y no atacan a quien
			-- esté dentro. Rectángulos { Min, Max } en X/Z relativos al centro de la zona.
			SafeAreas = {
				{ Min = Vector2.new(-46, -17), Max = Vector2.new(62, 165) },
			},
			SafeZones = {
				{ Center = Vector2.new(38, 85), Radius = 20 }, -- Jardín de los Huevos (EggConfig.Gardens.Forest)
				{ Center = Vector2.new(0, 160), Radius = 16 }, -- portal al Valle (ZoneConfig.Portals.ForestPortal)
				-- Círculo de la práctica de las oleadas (WaveConfig.Places.Practice, radio AreaRadius + 4):
				-- los del mundo no entran a por nadie ni atacan a quien espera junto al altar.
				{ Center = Vector2.new(-69, 98), Radius = 22 },
				-- Cueva de los Espinillos por dentro (CaveConfig, lejos del mapa; aquí relativo al centro
				-- del Bosque, Z + 25): donde llegas al entrar (sala 1, junto al portal de salida) y el
				-- círculo de las Oleadas del Guardián en la sala 3 (WaveConfig.Places.Forest).
				{ Center = Vector2.new(-928, 29), Radius = 12 },
				{ Center = Vector2.new(-1220, 5), Radius = 22 },
			},
			Spawns = {
				-- Zona de inicio: enemigos para golpear desde el principio, alrededor del centro del
				-- pueblo y justo fuera de la zona sin monstruos (al oeste, al este y al norte)
				{ Type = "StarterThornling", Offset = Vector2.new(-56, 26) },
				{ Type = "StarterThornling", Offset = Vector2.new(-54, 63) },
				{ Type = "StarterThornling", Offset = Vector2.new(-84, 62) },
				{ Type = "StarterThornling", Offset = Vector2.new(80, 20) },
				{ Type = "StarterThornling", Offset = Vector2.new(84, 62) },
				{ Type = "StarterThornling", Offset = Vector2.new(-20, -25) },
				{ Type = "StarterThornling", Offset = Vector2.new(20, -25) },
				{ Type = "Thornling", Offset = Vector2.new(-54, 140) },
				{ Type = "Thornling", Offset = Vector2.new(72, 125) },

				-- Pradera izquierda (al oeste de las parcelas y tiendas), a ambos lados del círculo
				-- de la práctica de las oleadas (WaveConfig.Places.Practice, en (-69, 98)), lejos de su
				-- zona segura.
				{ Type = "Thornling", Offset = Vector2.new(-60, 134) },
				{ Type = "Thornling", Offset = Vector2.new(-70, 136) },
				{ Type = "Thornling", Offset = Vector2.new(-62, 62) },
				{ Type = "Thornling", Offset = Vector2.new(-92, 62) },
				{ Type = "Thornling", Offset = Vector2.new(-96, 70) },
				{ Type = "Thornling", Offset = Vector2.new(-62, 12) },
				{ Type = "Barkbrute", Offset = Vector2.new(-68, 12) },

				-- Cueva de los Espinillos por dentro (CaveConfig; se entra por la boca de la colina
				-- oeste). Sala 1, el Nido: los pequeños, lejos de donde llegas.
				{ Type = "StarterThornling", Offset = Vector2.new(-950, 5) },
				{ Type = "StarterThornling", Offset = Vector2.new(-948, 51) },
				{ Type = "StarterThornling", Offset = Vector2.new(-966, 31) },
				{ Type = "StarterThornling", Offset = Vector2.new(-976, 3) },
				{ Type = "Thornling", Offset = Vector2.new(-986, 53) },
				{ Type = "Thornling", Offset = Vector2.new(-990, 29) },
				{ Type = "Thornling", Offset = Vector2.new(-994, 7) },
				{ Type = "Thornling", Offset = Vector2.new(-968, 57) },
				-- Sala 2, la Galería: los medianos (uno guarda el pasillo a la sala del altar).
				{ Type = "Barkbrute", Offset = Vector2.new(-1066, 29) },
				{ Type = "Barkbrute", Offset = Vector2.new(-1090, 63) },
				{ Type = "Barkbrute", Offset = Vector2.new(-1104, 31) },
				{ Type = "Barkbrute", Offset = Vector2.new(-1112, 5) },
				{ Type = "Barkbrute", Offset = Vector2.new(-1076, 3) },

				-- Pradera derecha (al este de las parcelas y los huevos)
				{ Type = "Thornling", Offset = Vector2.new(88, 105) },
				{ Type = "Thornling", Offset = Vector2.new(68, 118) },
				{ Type = "ThornCaster", Offset = Vector2.new(71, 118) }, -- lanzador (dispara de lejos)
				{ Type = "Thornling", Offset = Vector2.new(68, 115) },
				{ Type = "Thornling", Offset = Vector2.new(72, 96) }, -- (lejos del Jardín de los Huevos)
				{ Type = "Thornling", Offset = Vector2.new(76, 84) },
				{ Type = "Thornling", Offset = Vector2.new(68, 48) },
				{ Type = "ThornCaster", Offset = Vector2.new(71, 48) }, -- lanzador (dispara de lejos)
				{ Type = "Thornling", Offset = Vector2.new(68, 12) },

				-- Pradera norte (pasando el letrero de ZONA SEGURA)
				{ Type = "Thornling", Offset = Vector2.new(-68, -28) },
				{ Type = "Thornling", Offset = Vector2.new(-48, -28) },
				{ Type = "Thornling", Offset = Vector2.new(0, -30) },
				{ Type = "ThornCaster", Offset = Vector2.new(3, -30) }, -- lanzador (dispara de lejos)
				{ Type = "Thornling", Offset = Vector2.new(48, -28) },
				{ Type = "Thornling", Offset = Vector2.new(68, -28) },
				{ Type = "Thornling", Offset = Vector2.new(-68, -36) },
				{ Type = "Thornling", Offset = Vector2.new(-28, -36) },
				{ Type = "Thornling", Offset = Vector2.new(28, -36) },
				{ Type = "Barkbrute", Offset = Vector2.new(68, -36) },
			},
			Boss = {
				Type = "ForestWarden",
				Arena = { Name = "Círculo del Guardián", Center = Vector2.new(-58, -35), Radius = 16 },
			},
		},

		CrystalValley = {
			RewardMultiplier = 1,
			SafeZones = {
				{ Center = Vector2.new(18, 8), Radius = 11 },
				{ Center = Vector2.new(0, 160), Radius = 16 }, -- portal a la Caldera (ZoneConfig.Portals.CalderaPortal)
				-- Boca de la Cueva de Amatista (CaveConfig.Caves.CrystalValley.Entrance), donde
				-- estaba el círculo de las oleadas: nadie te espera al salir.
				{ Center = Vector2.new(36, -124), Radius = 22 },
				-- Cueva de Amatista por dentro (relativo al centro de la zona, como la del Bosque): donde
				-- llegas y el círculo de las oleadas en la sala 3 (WaveConfig.Places).
				{ Center = Vector2.new(-928, 29), Radius = 12 },
				{ Center = Vector2.new(-1220, 5), Radius = 22 },
			},
			Spawns = {
				-- Cueva de Amatista por dentro (CaveConfig.Caves; la boca está a la derecha de la llegada): la
				-- misma cueva que la del Bosque movida a esta zona, así que los mismos sitios.
				-- Sala 1, la Cantera: los pequeños, lejos de donde llegas.
				{ Type = "Shardling", Offset = Vector2.new(-950, 5) },
				{ Type = "Shardling", Offset = Vector2.new(-948, 51) },
				{ Type = "Shardling", Offset = Vector2.new(-966, 31) },
				{ Type = "Shardling", Offset = Vector2.new(-976, 3) },
				{ Type = "Shardling", Offset = Vector2.new(-986, 53) },
				{ Type = "Shardling", Offset = Vector2.new(-990, 29) },
				{ Type = "Shardling", Offset = Vector2.new(-994, 7) },
				{ Type = "Shardling", Offset = Vector2.new(-968, 57) },
				-- Sala 2, la Geoda: los medianos (y el mini-jefe, que crea EnemyService: CaveConfig).
				{ Type = "GeodeGolem", Offset = Vector2.new(-1066, 29) },
				{ Type = "GeodeGolem", Offset = Vector2.new(-1090, 63) },
				{ Type = "GeodeGolem", Offset = Vector2.new(-1104, 31) },
				{ Type = "GeodeGolem", Offset = Vector2.new(-1112, 5) },
				{ Type = "GeodeGolem", Offset = Vector2.new(-1076, 3) },

				{ Type = "Shardling", Offset = Vector2.new(-55, -85) },
				{ Type = "Shardling", Offset = Vector2.new(-35, -60) },
				{ Type = "CrystalCaster", Offset = Vector2.new(-32, -60) }, -- lanzador (dispara de lejos)
				{ Type = "Shardling", Offset = Vector2.new(-82, -48) },
				{ Type = "Shardling", Offset = Vector2.new(52, -82) },
				{ Type = "Shardling", Offset = Vector2.new(85, -48) },
				{ Type = "CrystalCaster", Offset = Vector2.new(88, -48) }, -- lanzador (dispara de lejos)
				{ Type = "Shardling", Offset = Vector2.new(-62, 24) },
				{ Type = "Shardling", Offset = Vector2.new(-92, 54) },
				{ Type = "Shardling", Offset = Vector2.new(-44, 82) },
				{ Type = "CrystalCaster", Offset = Vector2.new(-41, 82) }, -- lanzador (dispara de lejos)
				{ Type = "Shardling", Offset = Vector2.new(62, 54) },
				{ Type = "Shardling", Offset = Vector2.new(92, 74) },
				{ Type = "GeodeGolem", Offset = Vector2.new(-85, -5) },
				{ Type = "GeodeGolem", Offset = Vector2.new(90, -12) },
				{ Type = "GeodeGolem", Offset = Vector2.new(-55, 105) },
				{ Type = "GeodeGolem", Offset = Vector2.new(55, 105) },
			},
			Boss = {
				Type = "AmethystColossus",
				Arena = { Name = "Trono de Amatista", Center = Vector2.new(95, 35), Radius = 20 },
			},
		},

		EmberCaldera = {
			RewardMultiplier = 1,
			SafeZones = {
				{ Center = Vector2.new(24, 10), Radius = 11 },
				{ Center = Vector2.new(0, 160), Radius = 16 }, -- portal a la Tundra (ZoneConfig.Portals.TundraPortal)
				-- Boca de la Forja de Magma (CaveConfig.Caves.EmberCaldera.Entrance)
				{ Center = Vector2.new(36, -124), Radius = 22 },
				-- Forja de Magma por dentro (relativo al centro de la zona, como la del Bosque): donde
				-- llegas y el círculo de las oleadas en la sala 3 (WaveConfig.Places).
				{ Center = Vector2.new(-928, 29), Radius = 12 },
				{ Center = Vector2.new(-1220, 5), Radius = 22 },
			},
			Spawns = {
				-- Forja de Magma por dentro (CaveConfig.Caves; la boca está a la derecha de la llegada): la
				-- misma cueva que la del Bosque movida a esta zona, así que los mismos sitios.
				-- Sala 1, la Fragua: los pequeños, lejos de donde llegas.
				{ Type = "Cinderling", Offset = Vector2.new(-950, 5) },
				{ Type = "Cinderling", Offset = Vector2.new(-948, 51) },
				{ Type = "Cinderling", Offset = Vector2.new(-966, 31) },
				{ Type = "Cinderling", Offset = Vector2.new(-976, 3) },
				{ Type = "Cinderling", Offset = Vector2.new(-986, 53) },
				{ Type = "Cinderling", Offset = Vector2.new(-990, 29) },
				{ Type = "Cinderling", Offset = Vector2.new(-994, 7) },
				{ Type = "Cinderling", Offset = Vector2.new(-968, 57) },
				-- Sala 2, el Horno: los medianos (y el mini-jefe, que crea EnemyService: CaveConfig).
				{ Type = "MagmaGolem", Offset = Vector2.new(-1066, 29) },
				{ Type = "MagmaGolem", Offset = Vector2.new(-1090, 63) },
				{ Type = "MagmaGolem", Offset = Vector2.new(-1104, 31) },
				{ Type = "MagmaGolem", Offset = Vector2.new(-1112, 5) },
				{ Type = "MagmaGolem", Offset = Vector2.new(-1076, 3) },

				{ Type = "Cinderling", Offset = Vector2.new(-60, -72) },
				{ Type = "EmberCaster", Offset = Vector2.new(-57, -72) }, -- lanzador (dispara de lejos)
				{ Type = "Cinderling", Offset = Vector2.new(-36, -56) },
				{ Type = "Cinderling", Offset = Vector2.new(46, -60) },
				{ Type = "EmberCaster", Offset = Vector2.new(49, -60) }, -- lanzador (dispara de lejos)
				{ Type = "Cinderling", Offset = Vector2.new(82, -75) },
				{ Type = "Cinderling", Offset = Vector2.new(60, 34) },
				{ Type = "EmberCaster", Offset = Vector2.new(63, 34) }, -- lanzador (dispara de lejos)
				{ Type = "Cinderling", Offset = Vector2.new(92, 65) },
				{ Type = "Cinderling", Offset = Vector2.new(-74, 34) },
				{ Type = "Cinderling", Offset = Vector2.new(-95, 72) },
				{ Type = "MagmaGolem", Offset = Vector2.new(-96, -14) },
				{ Type = "MagmaGolem", Offset = Vector2.new(90, -30) },
				{ Type = "MagmaGolem", Offset = Vector2.new(-55, 95) },
				{ Type = "MagmaGolem", Offset = Vector2.new(55, 95) },
			},
			Boss = {
				Type = "CalderaTitan",
				Arena = { Name = "Corazón de la Caldera", Center = Vector2.new(0, 95), Radius = 22 },
			},
		},

		-- Tundra Helada: la misma forma que la Caldera, así que los mismos sitios (lejos del lago
		-- helado y de la plaza de los huevos).
		FrozenTundra = {
			RewardMultiplier = 1,
			SafeZones = {
				{ Center = Vector2.new(30, 9), Radius = 20 }, -- plaza de los Huevos de Hielo
				{ Center = Vector2.new(0, 160), Radius = 16 }, -- portal a la Fortaleza (ZoneConfig.Portals.FortressPortal)
				-- Boca de la Gruta Glacial (CaveConfig.Caves.FrozenTundra.Entrance)
				{ Center = Vector2.new(36, -124), Radius = 22 },
				-- Gruta Glacial por dentro: donde llegas y el círculo de las oleadas (WaveConfig.Places)
				{ Center = Vector2.new(-928, 29), Radius = 12 },
				{ Center = Vector2.new(-1220, 5), Radius = 22 },
			},
			Spawns = {
				-- Gruta Glacial por dentro (CaveConfig.Caves): sala 1, la Escarcha: los lobos.
				{ Type = "FrostWolf", Offset = Vector2.new(-950, 5) },
				{ Type = "FrostWolf", Offset = Vector2.new(-948, 51) },
				{ Type = "FrostWolf", Offset = Vector2.new(-966, 31) },
				{ Type = "FrostWolf", Offset = Vector2.new(-976, 3) },
				{ Type = "FrostWolf", Offset = Vector2.new(-986, 53) },
				{ Type = "FrostWolf", Offset = Vector2.new(-990, 29) },
				{ Type = "FrostWolf", Offset = Vector2.new(-994, 7) },
				{ Type = "FrostWolf", Offset = Vector2.new(-968, 57) },
				-- Sala 2, el Glaciar: los yetis (y el mini-jefe, que crea EnemyService: CaveConfig).
				{ Type = "Yeti", Offset = Vector2.new(-1066, 29) },
				{ Type = "Yeti", Offset = Vector2.new(-1090, 63) },
				{ Type = "Yeti", Offset = Vector2.new(-1104, 31) },
				{ Type = "Yeti", Offset = Vector2.new(-1112, 5) },
				{ Type = "Yeti", Offset = Vector2.new(-1076, 3) },

				{ Type = "FrostWolf", Offset = Vector2.new(-60, -72) },
				{ Type = "FrostWolf", Offset = Vector2.new(-36, -56) },
				{ Type = "FrostCaster", Offset = Vector2.new(-33, -56) }, -- lanzador (dispara de lejos)
				{ Type = "FrostWolf", Offset = Vector2.new(46, -60) },
				{ Type = "FrostWolf", Offset = Vector2.new(82, -75) },
				{ Type = "FrostWolf", Offset = Vector2.new(70, 40) },
				{ Type = "FrostCaster", Offset = Vector2.new(73, 40) }, -- lanzador (dispara de lejos)
				{ Type = "FrostWolf", Offset = Vector2.new(92, 65) },
				{ Type = "FrostWolf", Offset = Vector2.new(-80, 40) },
				{ Type = "FrostWolf", Offset = Vector2.new(-95, 72) },
				{ Type = "FrostCaster", Offset = Vector2.new(-92, 72) }, -- lanzador (dispara de lejos)
				{ Type = "FrostWolf", Offset = Vector2.new(-30, 60) },
				{ Type = "FrostWolf", Offset = Vector2.new(30, 60) },
				{ Type = "Yeti", Offset = Vector2.new(-96, -14) },
				{ Type = "Yeti", Offset = Vector2.new(90, -30) },
				{ Type = "Yeti", Offset = Vector2.new(-55, 95) },
				{ Type = "Yeti", Offset = Vector2.new(55, 95) },
			},
			Boss = {
				Type = "IceGolem",
				Arena = { Name = "Mirador del Gólem", Center = Vector2.new(0, 95), Radius = 22 },
			},
		},

		-- Fortaleza Goblin: goblins por el prado y junto al camino (te salen al paso), brutos en
		-- la puerta de la muralla y por el patio, y el Rey Goblin en la Sala del Trono. La tarima
		-- del portal gigante es zona segura.
		GoblinFortress = {
			RewardMultiplier = 1,
			SafeZones = {
				{ Center = Vector2.new(0, 124), Radius = 22 }, -- portal gigante al Mundo 2 (ZoneConfig.WorldPortals)
				{ Center = Vector2.new(0, -150), Radius = 14 }, -- llegada desde la Tundra
			},
			Spawns = {
				-- El prado de los campamentos
				{ Type = "Goblin", Offset = Vector2.new(-70, -118) },
				{ Type = "Goblin", Offset = Vector2.new(-42, -112) },
				{ Type = "Goblin", Offset = Vector2.new(42, -112) },
				{ Type = "Goblin", Offset = Vector2.new(70, -118) },
				{ Type = "Goblin", Offset = Vector2.new(-96, -82) },
				{ Type = "Goblin", Offset = Vector2.new(-62, -78) },
				{ Type = "Goblin", Offset = Vector2.new(62, -78) },
				{ Type = "Goblin", Offset = Vector2.new(96, -82) },
				-- Junto al camino a la muralla
				{ Type = "Goblin", Offset = Vector2.new(-24, -100) },
				{ Type = "Goblin", Offset = Vector2.new(24, -100) },
				{ Type = "Goblin", Offset = Vector2.new(-24, -76) },
				{ Type = "Goblin", Offset = Vector2.new(24, -76) },
				{ Type = "GoblinBrute", Offset = Vector2.new(-32, -66) },
				{ Type = "GoblinBrute", Offset = Vector2.new(32, -66) },
				-- El patio, a los lados de la Sala del Trono
				{ Type = "Goblin", Offset = Vector2.new(-56, -28) },
				{ Type = "Goblin", Offset = Vector2.new(56, -28) },
				{ Type = "Goblin", Offset = Vector2.new(-64, 8) },
				{ Type = "Goblin", Offset = Vector2.new(64, 8) },
				{ Type = "Goblin", Offset = Vector2.new(-64, 48) },
				{ Type = "Goblin", Offset = Vector2.new(64, 48) },
				{ Type = "Goblin", Offset = Vector2.new(-60, 86) },
				{ Type = "Goblin", Offset = Vector2.new(60, 86) },
				{ Type = "GoblinBrute", Offset = Vector2.new(-40, -32) },
				{ Type = "GoblinBrute", Offset = Vector2.new(40, -32) },
			},
			Boss = {
				Type = "GoblinKing",
				Arena = { Name = "Sala del Trono", Center = Vector2.new(0, 44), Radius = 30 },
			},
		},

		-- Tierras Divididas (Mundo 2, zona 1; centro (2000, -320)). Bichos de fuego en la mitad
		-- oeste (volcán) y de hielo en la este (glaciar), lejos de la llegada, del huevo, del Altar
		-- del Equilibrio (oleadas) y de la boca de la Grieta Elemental. El Coloso del Equilibrio
		-- solo sale en las oleadas (BossOnlyInWaves): su arena del mundo está vacía.
		DividedLands = {
			RewardMultiplier = 1,
			SafeZones = {
				{ Center = Vector2.new(0, 100), Radius = 22 }, -- llegada desde el pueblo del Mundo 2
				{ Center = Vector2.new(0, 144), Radius = 16 }, -- el paso y la puerta (ZoneConfig.Portals.DividedPortal)
				{ Center = Vector2.new(44, 92), Radius = 14 }, -- Huevo del Equilibrio (EggConfig)
				-- Altar del Equilibrio (WaveConfig.Places.DividedLands, radio AreaRadius + 8)
				{ Center = Vector2.new(0, -4), Radius = 26 },
				-- Boca de la Grieta Elemental (CaveConfig.Caves.DividedLands.Entrance): al salir
				{ Center = Vector2.new(24, -92), Radius = 22 },
				-- Grieta Elemental por dentro (la cueva del Bosque movida; relativo al centro de esta
				-- zona): donde llegas y el círculo de las Oleadas Gemelas en la sala 3
				{ Center = Vector2.new(-2928, 28), Radius = 12 },
				{ Center = Vector2.new(-3220, 4), Radius = 22 },
			},
			Spawns = {
				-- Volcán (oeste): espíritus de brasa y brutos de lava
				{ Type = "EmberWisp", Offset = Vector2.new(-48, 72) },
				{ Type = "EmberWisp", Offset = Vector2.new(-80, 60) },
				{ Type = "EmberWisp", Offset = Vector2.new(-100, 30) },
				{ Type = "EmberWisp", Offset = Vector2.new(-56, 34) },
				{ Type = "EmberWisp", Offset = Vector2.new(-92, -6) },
				{ Type = "EmberWisp", Offset = Vector2.new(-48, -52) },
				{ Type = "EmberWisp", Offset = Vector2.new(-60, -108) },
				{ Type = "LavaBrute", Offset = Vector2.new(-76, 92) },
				{ Type = "LavaBrute", Offset = Vector2.new(-72, -30) },
				-- Glaciar (este): espíritus de escarcha y brutos de escarcha
				{ Type = "FrostWisp", Offset = Vector2.new(64, 60) },
				{ Type = "FrostWisp", Offset = Vector2.new(100, 30) },
				{ Type = "FrostWisp", Offset = Vector2.new(56, 34) },
				{ Type = "FrostWisp", Offset = Vector2.new(92, -6) },
				{ Type = "FrostWisp", Offset = Vector2.new(48, -52) },
				{ Type = "FrostWisp", Offset = Vector2.new(96, -60) },
				{ Type = "FrostWisp", Offset = Vector2.new(100, 64) },
				{ Type = "FrostBrute", Offset = Vector2.new(76, 92) },
				{ Type = "FrostBrute", Offset = Vector2.new(72, -30) },

				-- Grieta Elemental por dentro (CaveConfig; la cueva del Bosque movida aquí: los mismos
				-- sitios con X - 2000 e Y - 1). Sala 1, la Fragua Partida: espíritus de brasa.
				{ Type = "EmberWisp", Offset = Vector2.new(-2950, 4) },
				{ Type = "EmberWisp", Offset = Vector2.new(-2948, 50) },
				{ Type = "EmberWisp", Offset = Vector2.new(-2966, 30) },
				{ Type = "EmberWisp", Offset = Vector2.new(-2976, 2) },
				{ Type = "EmberWisp", Offset = Vector2.new(-2986, 52) },
				{ Type = "EmberWisp", Offset = Vector2.new(-2990, 28) },
				{ Type = "EmberWisp", Offset = Vector2.new(-2994, 6) },
				{ Type = "EmberWisp", Offset = Vector2.new(-2968, 56) },
				-- Sala 2, el Glaciar Roto: brutos de escarcha (y el mini-jefe, que crea EnemyService).
				{ Type = "FrostBrute", Offset = Vector2.new(-3066, 28) },
				{ Type = "FrostBrute", Offset = Vector2.new(-3090, 62) },
				{ Type = "FrostBrute", Offset = Vector2.new(-3104, 30) },
				{ Type = "FrostBrute", Offset = Vector2.new(-3112, 4) },
				{ Type = "FrostBrute", Offset = Vector2.new(-3076, 2) },
			},
			Boss = {
				Type = "EquilibriumColossus",
				Arena = { Name = "Cráter del Equilibrio", Center = Vector2.new(-84, -70), Radius = 20 },
			},
		},
	},
}

return EnemyConfig
