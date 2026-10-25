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

local EnemyConfig = {
	AiTickSeconds = 0.15,
	StuckSeconds = 6,

	Types = {
		-- Bosque --------------------------------------------------------------------
		StarterThornling = {
			DisplayName = "Espinillo Bebé",
			Kind = "Normal",
			MaxHealth = 20,
			Damage = 3,
			AttackRange = 4.5,
			AttackCooldown = 1.6,
			AttackWindup = 0.35,
			WalkSpeed = 8,
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
			AttackWindup = 0.35,
			WalkSpeed = 10,
			DetectRange = 12,
			LeashRange = 18,
			Reward = 35,
			RespawnSeconds = 4,
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
			AttackWindup = 0.7,
			WalkSpeed = 8,
			DetectRange = 14,
			LeashRange = 20,
			Reward = 140,
			RespawnSeconds = 6,
			-- Modelo 3D: arbol_guardian.glb (Server.Util.ModelosZona1)
			Look = { Style = "ArbolGuardian", Primary = Color3.fromRGB(110, 68, 38), Secondary = Color3.fromRGB(127, 209, 59), Eyes = Color3.fromRGB(255, 243, 160) },
		},
		ForestWarden = {
			DisplayName = "Guardián del Bosque",
			Kind = "Boss",
			MaxHealth = 1200,
			Damage = 18,
			AttackRange = 9,
			AttackCooldown = 2.2,
			AttackWindup = 0.5,
			WalkSpeed = 8,
			DetectRange = 0, -- los jefes usan su arena (Zones.*.Boss.Arena)
			LeashRange = 18,
			Reward = 1200,
			EnergyReward = 1500, -- ⚡ extra para cada jugador que lo derrota (BossRewardService)
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
			AttackWindup = 0.3,
			WalkSpeed = 11,
			DetectRange = 12,
			LeashRange = 18,
			Reward = 110,
			RespawnSeconds = 4,
			Look = { Style = "Shard", Primary = Color3.fromRGB(150, 110, 240), Secondary = Color3.fromRGB(110, 226, 255), Eyes = Color3.fromRGB(34, 22, 48) },
		},
		GeodeGolem = {
			DisplayName = "Gólem de Geoda",
			Kind = "Strong",
			MaxHealth = 650,
			Damage = 16,
			AttackRange = 7.5,
			AttackCooldown = 2.8,
			AttackWindup = 0.8,
			WalkSpeed = 8,
			DetectRange = 14,
			LeashRange = 20,
			Reward = 450,
			RespawnSeconds = 6,
			Look = { Style = "Golem", Primary = Color3.fromRGB(98, 102, 126), Secondary = Color3.fromRGB(96, 220, 210), Eyes = Color3.fromRGB(110, 170, 255) },
		},
		AmethystColossus = {
			DisplayName = "Coloso de Amatista",
			Kind = "Boss",
			MaxHealth = 4500,
			Damage = 24,
			AttackRange = 10,
			AttackCooldown = 2.4,
			AttackWindup = 0.55,
			WalkSpeed = 8,
			DetectRange = 0, -- los jefes usan su arena (Zones.*.Boss.Arena)
			LeashRange = 18,
			Reward = 4000,
			EnergyReward = 6000, -- ⚡ extra para cada jugador que lo derrota (BossRewardService)
			RespawnSeconds = 12,
			Brain = { DetectRange = 24, Territory = 40, LockSeconds = 4, RecoverSeconds = 0.8 },
			-- Identidad: embestidas en línea recta (se esquivan apartándose de la franja roja)
			Charge = { Interval = 8, Telegraph = 1.0, Distance = 26, Width = 6, Damage = 28, Speed = 42, MinRange = 8, MaxRange = 30 },
			-- Golpe de área anunciado con un círculo en el suelo
			Slam = { Interval = 8, Telegraph = 1.3, Radius = 12, Damage = 30 },
			-- Furia bajo la mitad de vida: más rápido y golpes de área más seguidos
			Enrage = { HealthFraction = 0.5, SpeedMultiplier = 1.3, SlamIntervalMultiplier = 0.65 },
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
			AttackWindup = 0.3,
			WalkSpeed = 12,
			DetectRange = 12,
			LeashRange = 18,
			Reward = 320,
			RespawnSeconds = 4,
			Look = { Style = "Shard", Primary = Color3.fromRGB(255, 128, 44), Secondary = Color3.fromRGB(255, 230, 96), Eyes = Color3.fromRGB(44, 20, 20) },
		},
		MagmaGolem = {
			DisplayName = "Gólem de Magma",
			Kind = "Strong",
			MaxHealth = 2200,
			Damage = 20,
			AttackRange = 7.5,
			AttackCooldown = 2.8,
			AttackWindup = 0.8,
			WalkSpeed = 9,
			DetectRange = 14,
			LeashRange = 20,
			Reward = 1300,
			RespawnSeconds = 6,
			Look = { Style = "Golem", Primary = Color3.fromRGB(74, 60, 58), Secondary = Color3.fromRGB(255, 118, 36), Eyes = Color3.fromRGB(255, 200, 90) },
		},
		CalderaTitan = {
			DisplayName = "Titán de la Caldera",
			Kind = "Boss",
			MaxHealth = 15000,
			Damage = 28,
			AttackRange = 10,
			AttackCooldown = 2.3,
			AttackWindup = 0.55,
			WalkSpeed = 9,
			DetectRange = 0, -- los jefes usan su arena (Zones.*.Boss.Arena)
			LeashRange = 18,
			Reward = 12000,
			EnergyReward = 20000, -- ⚡ extra para cada jugador que lo derrota (BossRewardService)
			RespawnSeconds = 15,
			Brain = { DetectRange = 26, Territory = 42, LockSeconds = 4, RecoverSeconds = 0.8 },
			-- Identidad: saltos que caen donde estabas y ráfagas de bolas de fuego
			Leap = { Interval = 10, Telegraph = 1.1, Radius = 9, Damage = 30, MinRange = 10, MaxRange = 32 },
			Volley = { Interval = 6, Count = 3, Damage = 14, Speed = 45, Telegraph = 0.6, Range = 40, Radius = 3 },
			-- Golpe de área anunciado con un círculo en el suelo
			Slam = { Interval = 8, Telegraph = 1.3, Radius = 13, Damage = 35 },
			-- Furia bajo la mitad de vida: más rápido y golpes de área más seguidos
			Enrage = { HealthFraction = 0.5, SpeedMultiplier = 1.3, SlamIntervalMultiplier = 0.65 },
			Look = { Style = "Colossus", Primary = Color3.fromRGB(64, 52, 52), Secondary = Color3.fromRGB(255, 118, 36), Eyes = Color3.fromRGB(255, 232, 150) },
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
			},
			Spawns = {
				-- Zona de inicio: enemigos para golpear desde el principio, alrededor del centro del
				-- pueblo y justo fuera de la zona sin monstruos (al oeste, al este y al norte)
				{ Type = "StarterThornling", Offset = Vector2.new(-54, 36) },
				{ Type = "StarterThornling", Offset = Vector2.new(-54, 63) },
				{ Type = "StarterThornling", Offset = Vector2.new(-80, 100) },
				{ Type = "StarterThornling", Offset = Vector2.new(80, 20) },
				{ Type = "StarterThornling", Offset = Vector2.new(84, 62) },
				{ Type = "StarterThornling", Offset = Vector2.new(-20, -25) },
				{ Type = "StarterThornling", Offset = Vector2.new(20, -25) },
				{ Type = "Thornling", Offset = Vector2.new(-56, 125) },
				{ Type = "Thornling", Offset = Vector2.new(72, 125) },

				-- Pradera izquierda (al oeste de las parcelas y tiendas)
				{ Type = "Thornling", Offset = Vector2.new(-58, 115) },
				{ Type = "Thornling", Offset = Vector2.new(-68, 118) },
				{ Type = "Thornling", Offset = Vector2.new(-68, 115) },
				{ Type = "Thornling", Offset = Vector2.new(-62, 82) },
				{ Type = "Thornling", Offset = Vector2.new(-68, 82) },
				{ Type = "Thornling", Offset = Vector2.new(-60, 48) },
				{ Type = "Thornling", Offset = Vector2.new(-68, 48) },
				{ Type = "Thornling", Offset = Vector2.new(-62, 12) },
				{ Type = "Barkbrute", Offset = Vector2.new(-68, 12) },

				-- Pradera derecha (al este de las parcelas y los huevos)
				{ Type = "Thornling", Offset = Vector2.new(88, 105) },
				{ Type = "Thornling", Offset = Vector2.new(68, 118) },
				{ Type = "Thornling", Offset = Vector2.new(68, 115) },
				{ Type = "Thornling", Offset = Vector2.new(72, 96) }, -- (lejos del Jardín de los Huevos)
				{ Type = "Thornling", Offset = Vector2.new(76, 84) },
				{ Type = "Thornling", Offset = Vector2.new(68, 48) },
				{ Type = "Thornling", Offset = Vector2.new(68, 12) },

				-- Pradera norte (pasando el letrero de ZONA SEGURA)
				{ Type = "Thornling", Offset = Vector2.new(-68, -28) },
				{ Type = "Thornling", Offset = Vector2.new(-48, -28) },
				{ Type = "Thornling", Offset = Vector2.new(0, -30) },
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
			},
			Spawns = {
				{ Type = "Shardling", Offset = Vector2.new(-55, -85) },
				{ Type = "Shardling", Offset = Vector2.new(-35, -60) },
				{ Type = "Shardling", Offset = Vector2.new(-82, -48) },
				{ Type = "Shardling", Offset = Vector2.new(52, -82) },
				{ Type = "Shardling", Offset = Vector2.new(85, -48) },
				{ Type = "Shardling", Offset = Vector2.new(-62, 24) },
				{ Type = "Shardling", Offset = Vector2.new(-92, 54) },
				{ Type = "Shardling", Offset = Vector2.new(-44, 82) },
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
			},
			Spawns = {
				{ Type = "Cinderling", Offset = Vector2.new(-60, -72) },
				{ Type = "Cinderling", Offset = Vector2.new(-36, -56) },
				{ Type = "Cinderling", Offset = Vector2.new(46, -60) },
				{ Type = "Cinderling", Offset = Vector2.new(82, -75) },
				{ Type = "Cinderling", Offset = Vector2.new(60, 34) },
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
	},
}

return EnemyConfig
