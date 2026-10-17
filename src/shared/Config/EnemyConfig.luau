-- Enemigos y su distribución por zonas. Para una zona nueva basta con añadir su entrada
-- en Zones (tipos y posiciones de aparición, jefe y arena, zonas protegidas y
-- multiplicador de recompensa); el requisito de acceso lo sigue definiendo ZoneConfig.
--
-- Posiciones RELATIVAS al centro de cada zona (ZoneConfig.Zones[...].Center), en X/Z.
--
-- Recompensas (energía), comparadas con las mejoras (mejora N = 10·1.5^N):
-- - Espinillo 25 / Bruto 120: ingresos extra al principio sin sustituir la producción.
-- - Guardián del Bosque 1 200 cada 3 min: ~ la mejora 12 (1 297).
-- - Coloso de Amatista 4 000 cada 4 min: ~ la mejora 15 (4 378). No permite saltarse
--   la progresión: hace falta nivel/mascotas para derrotarlo en un tiempo razonable.
-- Si varios jugadores dañan a un enemigo, la recompensa se REPARTE según el daño de
-- cada uno (el total nunca supera la recompensa del enemigo).

local EnemyConfig = {
	AiTickSeconds = 0.15, -- un único bucle de IA para todos los enemigos
	StuckSeconds = 6, -- si no avanza al volver a casa, reaparece en su punto de origen

	Types = {
		-- Bosque --------------------------------------------------------------------
		Thornling = {
			DisplayName = "Espinillo",
			Kind = "Normal",
			MaxHealth = 40,
			Damage = 8,
			AttackRange = 4.5,
			AttackCooldown = 1.6,
			AttackWindup = 0.35,
			WalkSpeed = 12,
			DetectRange = 26,
			LeashRange = 32,
			Reward = 25,
			RespawnSeconds = 8,
			Look = { Style = "Bramble", Primary = Color3.fromRGB(78, 104, 56), Secondary = Color3.fromRGB(120, 86, 56), Eyes = Color3.fromRGB(255, 170, 70) },
		},
		Barkbrute = {
			DisplayName = "Bruto de Corteza",
			Kind = "Strong",
			MaxHealth = 180,
			Damage = 18,
			AttackRange = 7, -- golpe largo con los brazos
			AttackCooldown = 2.6,
			AttackWindup = 0.7, -- lento pero contundente
			WalkSpeed = 9,
			DetectRange = 30,
			LeashRange = 36,
			Reward = 120,
			RespawnSeconds = 20,
			Look = { Style = "Brute", Primary = Color3.fromRGB(102, 74, 50), Secondary = Color3.fromRGB(92, 140, 64), Eyes = Color3.fromRGB(255, 200, 90) },
		},
		ForestWarden = {
			DisplayName = "Guardián del Bosque",
			Kind = "Boss",
			MaxHealth = 1500,
			Damage = 24,
			AttackRange = 9,
			AttackCooldown = 2.2,
			AttackWindup = 0.5,
			WalkSpeed = 10,
			DetectRange = 0, -- los jefes usan su arena (ver Zones.*.Boss.Arena)
			LeashRange = 0,
			Reward = 1200,
			RespawnSeconds = 180,
			-- Segundo ataque: golpe de raíces en área, anunciado con un círculo en el suelo.
			Slam = { Interval = 9, Telegraph = 1.2, Radius = 14, Damage = 30 },
			-- Furia por debajo de la mitad de vida: más rápido y golpes en área más seguidos.
			Enrage = { HealthFraction = 0.5, SpeedMultiplier = 1.3, SlamIntervalMultiplier = 0.65 },
			Look = { Style = "Treant", Primary = Color3.fromRGB(84, 62, 44), Secondary = Color3.fromRGB(78, 140, 62), Eyes = Color3.fromRGB(96, 224, 200) },
		},

		-- Valle Cristalino (variantes más poderosas) ----------------------------------
		Shardling = {
			DisplayName = "Fragmento Errante",
			Kind = "Normal",
			MaxHealth = 150,
			Damage = 14,
			AttackRange = 4.5,
			AttackCooldown = 1.4,
			AttackWindup = 0.3,
			WalkSpeed = 14,
			DetectRange = 28,
			LeashRange = 34,
			Reward = 90,
			RespawnSeconds = 10,
			Look = { Style = "Shard", Primary = Color3.fromRGB(150, 110, 220), Secondary = Color3.fromRGB(110, 170, 255), Eyes = Color3.fromRGB(255, 255, 255) },
		},
		GeodeGolem = {
			DisplayName = "Gólem de Geoda",
			Kind = "Strong",
			MaxHealth = 650,
			Damage = 28,
			AttackRange = 7.5,
			AttackCooldown = 2.8,
			AttackWindup = 0.8,
			WalkSpeed = 8,
			DetectRange = 30,
			LeashRange = 36,
			Reward = 400,
			RespawnSeconds = 25,
			Look = { Style = "Golem", Primary = Color3.fromRGB(98, 102, 126), Secondary = Color3.fromRGB(96, 220, 210), Eyes = Color3.fromRGB(110, 170, 255) },
		},
		AmethystColossus = {
			DisplayName = "Coloso de Amatista",
			Kind = "Boss",
			MaxHealth = 6000,
			Damage = 38,
			AttackRange = 10,
			AttackCooldown = 2.4,
			AttackWindup = 0.55,
			WalkSpeed = 9,
			DetectRange = 0,
			LeashRange = 0,
			Reward = 4000,
			RespawnSeconds = 240,
			Slam = { Interval = 8, Telegraph = 1.1, Radius = 16, Damage = 42 },
			Enrage = { HealthFraction = 0.5, SpeedMultiplier = 1.3, SlamIntervalMultiplier = 0.65 },
			Look = { Style = "Colossus", Primary = Color3.fromRGB(86, 84, 108), Secondary = Color3.fromRGB(176, 120, 236), Eyes = Color3.fromRGB(230, 180, 255) },
		},
	},

	Zones = {
		Forest = {
			RewardMultiplier = 1,
			-- Los enemigos nunca persiguen dentro de estas zonas ni aparecen en ellas:
			-- spawn, cristal, portal y santuarios de huevos.
			SafeZones = {
				{ Center = Vector2.new(0, 25), Radius = 16 },
				{ Center = Vector2.new(0, 0), Radius = 16 },
				{ Center = Vector2.new(0, 56), Radius = 14 },
				{ Center = Vector2.new(-20, 12), Radius = 9 },
				{ Center = Vector2.new(-28, 0), Radius = 9 },
				{ Center = Vector2.new(24, 10), Radius = 9 },
			},
			Spawns = {
				-- Prado oeste
				{ Type = "Thornling", Offset = Vector2.new(-55, 40) },
				{ Type = "Thornling", Offset = Vector2.new(-40, 76) },
				{ Type = "Thornling", Offset = Vector2.new(-46, 60) },
				-- Prado este
				{ Type = "Thornling", Offset = Vector2.new(60, 62) },
				{ Type = "Thornling", Offset = Vector2.new(72, 50) },
				-- Detrás del árbol ancestral
				{ Type = "Thornling", Offset = Vector2.new(42, -92) },
				{ Type = "Thornling", Offset = Vector2.new(56, -80) },
				-- Fuertes, en los lugares más alejados
				{ Type = "Barkbrute", Offset = Vector2.new(96, -22) },
				{ Type = "Barkbrute", Offset = Vector2.new(-96, -30) },
			},
			Boss = {
				Type = "ForestWarden",
				Arena = { Name = "Círculo del Guardián", Center = Vector2.new(-100, 72), Radius = 20 },
			},
		},

		CrystalValley = {
			RewardMultiplier = 1,
			SafeZones = {
				{ Center = Vector2.new(0, 44), Radius = 14 }, -- llegada
				{ Center = Vector2.new(0, 58), Radius = 14 }, -- portal de vuelta
				{ Center = Vector2.new(18, 8), Radius = 10 }, -- santuario del Huevo de Cristal
			},
			Spawns = {
				{ Type = "Shardling", Offset = Vector2.new(-60, -45) },
				{ Type = "Shardling", Offset = Vector2.new(-50, -56) },
				{ Type = "Shardling", Offset = Vector2.new(-20, -40) },
				{ Type = "Shardling", Offset = Vector2.new(45, 40) },
				{ Type = "GeodeGolem", Offset = Vector2.new(-80, 20) },
				{ Type = "GeodeGolem", Offset = Vector2.new(50, -60) },
			},
			Boss = {
				Type = "AmethystColossus",
				Arena = { Name = "Trono de Amatista", Center = Vector2.new(85, -15), Radius = 20 },
			},
		},
	},
}

return EnemyConfig
