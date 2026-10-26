-- Clases de cada estilo de pelea: una PASIVA que mejora cómo juegas ese estilo. Cada estilo
-- (Armas, Guerrero, Puños y Magia) tiene cinco: la primera es gratis y las otras cuatro se compran con 💎 diamantes (cada vez
-- más caras; la última es la definitiva). Llevas una activa por estilo (se cambia gratis
-- cuando quieras) y solo cuenta mientras juegas ese estilo. Cada clase sube de nivel con 💎
-- (del 1 al Levels.Max) y su pasiva se hace más fuerte.
-- Se compran, se suben y se eligen en el puesto 🎭 Clases de la plaza (ClassesController;
-- tecla H). Lógica en ClassLogic; el servidor (StyleService) valida y cobra, y las pasivas
-- las aplican PetCombatService (tus golpes), StyleService (habilidades, dash y daño que
-- recibes), PlayerDataService (vida y velocidad) y EnemyService (daño a jefes).
--
-- Bonuses: cada pasiva con su valor a nivel 1 y a nivel Max (en medio, en línea recta); un
-- número suelto es fijo a cualquier nivel. Qué hace cada una (todas se SUMAN a lo del estilo):
--   Damage          +x de daño de tus golpes (no de las habilidades)
--   FireRate        +x de velocidad de ataque (el tiempo entre golpes se divide por 1 + x)
--   Range           +x de alcance
--   CritChance      +x de probabilidad de crítico
--   CritPower       +x al multiplicador del crítico (×2 -> ×2.5 con 0.5)
--   LifeSteal       te curas x del daño de tus golpes (con el tope por golpe del estilo)
--   Health          +x de vida máxima
--   Defense         -x del daño que recibes
--   Speed           +x de velocidad al caminar
--   SkillDamage     +x de daño de tus habilidades (Z y X)
--   SkillHaste      -x de recarga de tus habilidades
--   DashHaste       -x de recarga del dash (Puños)
--   SplashRadius    +x studs de explosión en cada golpe (sin explosión, la crea)
--   SplashFraction  +x del daño del golpe que hace la explosión a los de alrededor
--   Slow            tus golpes frenan al enemigo un x (SlowSeconds segundos)
--   BossDamage      +x de daño a los jefes (todo tu daño)
--   ComboEvery      el combo de golpes sale x golpes antes (fijo, como mínimo cada 2)
--
-- [PROVISIONAL] Primer balance: la gratis ≈ +10-25 %, las de 💎 se especializan y la última
-- junta tres pasivas fuertes.

local ClassConfig = {
	Levels = {
		Max = 5,
		-- Subir del nivel n al n+1: UpgradeBase · UpgradeScale de la clase · UpgradeGrowth^(n-1) 💎
		UpgradeBase = 60,
		UpgradeGrowth = 1.6,
	},
	SlowSeconds = 1.5,

	-- Cómo se enseña cada pasiva en el panel (%s = el valor ya formateado)
	Bonuses = {
		Damage = { Order = 1, Icon = "⚔️", Text = "+%s de daño", Percent = true },
		FireRate = { Order = 2, Icon = "⏩", Text = "+%s de velocidad de ataque", Percent = true },
		Range = { Order = 3, Icon = "📏", Text = "+%s de alcance", Percent = true },
		CritChance = { Order = 4, Icon = "🎯", Text = "+%s de críticos", Percent = true },
		CritPower = { Order = 5, Icon = "💢", Text = "Críticos más fuertes (+×%s)" },
		LifeSteal = { Order = 6, Icon = "💜", Text = "Te curas el %s del daño", Percent = true },
		Health = { Order = 7, Icon = "❤️", Text = "+%s de vida", Percent = true },
		Defense = { Order = 8, Icon = "🛡️", Text = "-%s de daño recibido", Percent = true },
		Speed = { Order = 9, Icon = "🏃", Text = "+%s de velocidad", Percent = true },
		SkillDamage = { Order = 10, Icon = "✨", Text = "+%s de daño de habilidades", Percent = true },
		SkillHaste = { Order = 11, Icon = "⏱️", Text = "-%s de recarga de habilidades", Percent = true },
		DashHaste = { Order = 12, Icon = "💨", Text = "-%s de recarga del dash", Percent = true },
		SplashRadius = { Order = 13, Icon = "💥", Text = "Explosión de +%s studs" },
		SplashFraction = { Order = 14, Icon = "🔥", Text = "+%s de daño en área", Percent = true },
		Slow = { Order = 15, Icon = "❄️", Text = "Tus golpes frenan un %s", Percent = true },
		BossDamage = { Order = 16, Icon = "👑", Text = "+%s de daño a jefes", Percent = true },
		ComboEvery = { Order = 17, Icon = "🥊", Text = "Combo %s golpe antes" },
	},

	-- Orden de los estilos (como StyleConfig.Order) y de las clases de cada uno (la primera, la gratis)
	Order = { "Weapons", "Warrior", "Fists", "Magic" },
	Styles = {
		Weapons = { "Soldier", "Sniper", "Gunner", "Demolisher", "Commando" },
		Warrior = { "Squire", "Duelist", "Paladin", "Blademaster", "Warlord" },
		Fists = { "Brawler", "Monk", "Tank", "Berserker", "Champion" },
		Magic = { "Apprentice", "Pyromancer", "Cryomancer", "Archmage", "Sorcerer" },
	},

	Classes = {
		-- 🔫 Armas -------------------------------------------------------------------------
		Soldier = {
			Style = "Weapons",
			Name = "Soldado",
			Icon = "🎖️",
			Text = "Equilibrado: más daño y disparas un poco más rápido.",
			Price = 0,
			UpgradeScale = 0.5,
			Bonuses = { Damage = { 0.08, 0.2 }, FireRate = { 0.05, 0.12 } },
		},
		Sniper = {
			Style = "Weapons",
			Name = "Francotirador",
			Icon = "🎯",
			Text = "Pegas desde mucho más lejos y con muchos más críticos.",
			Price = 200,
			UpgradeScale = 1,
			Bonuses = { Range = { 0.2, 0.5 }, CritChance = { 0.1, 0.22 } },
		},
		Gunner = {
			Style = "Weapons",
			Name = "Ametrallador",
			Icon = "🔥",
			Text = "Disparas muchísimo más rápido y te mueves más.",
			Price = 500,
			UpgradeScale = 1.3,
			Bonuses = { FireRate = { 0.15, 0.4 }, Speed = { 0.05, 0.12 } },
		},
		Demolisher = {
			Style = "Weapons",
			Name = "Demoledor",
			Icon = "💥",
			Text = "Tus disparos explotan y dañan a los de alrededor; tus habilidades pegan más.",
			Price = 1200,
			UpgradeScale = 1.7,
			Bonuses = { SplashRadius = { 5, 9 }, SplashFraction = { 0.3, 0.5 }, SkillDamage = { 0.1, 0.3 } },
		},
		Commando = {
			Style = "Weapons",
			Name = "Comando Élite",
			Icon = "👑",
			Text = "La definitiva: más daño, críticos brutales y destrozas a los jefes.",
			Price = 3000,
			UpgradeScale = 2.5,
			Bonuses = { Damage = { 0.15, 0.35 }, CritPower = { 0.5, 1.5 }, BossDamage = { 0.25, 0.6 } },
		},

		-- 🗡️ Guerrero ------------------------------------------------------------------------
		Squire = {
			Style = "Warrior",
			Name = "Escudero",
			Icon = "🛡️",
			Text = "Equilibrado: tajos más fuertes y recibes algo menos de daño.",
			Price = 0,
			UpgradeScale = 0.5,
			Bonuses = { Damage = { 0.08, 0.2 }, Defense = { 0.05, 0.12 } },
		},
		Duelist = {
			Style = "Warrior",
			Name = "Duelista",
			Icon = "🤺",
			Text = "Tajos más rápidos y muchos críticos.",
			Price = 200,
			UpgradeScale = 1,
			Bonuses = { FireRate = { 0.08, 0.22 }, CritChance = { 0.1, 0.25 } },
		},
		Paladin = {
			Style = "Warrior",
			Name = "Paladín",
			Icon = "⚜️",
			Text = "Mucha más vida y te curas con cada tajo.",
			Price = 500,
			UpgradeScale = 1.3,
			Bonuses = { Health = { 0.2, 0.5 }, LifeSteal = { 0.02, 0.05 } },
		},
		Blademaster = {
			Style = "Warrior",
			Name = "Maestro de espadas",
			Icon = "⚔️",
			Text = "Tu espada llega más lejos y pega mucho más fuerte.",
			Price = 1200,
			UpgradeScale = 1.7,
			Bonuses = { Range = { 0.15, 0.35 }, Damage = { 0.15, 0.35 } },
		},
		Warlord = {
			Style = "Warrior",
			Name = "Señor de la guerra",
			Icon = "👑",
			Text = "La definitiva: más daño, habilidades brutales y destrozas a los jefes.",
			Price = 3000,
			UpgradeScale = 2.5,
			Bonuses = { Damage = { 0.2, 0.4 }, SkillDamage = { 0.2, 0.5 }, BossDamage = { 0.25, 0.6 } },
		},

		-- 👊 Puños ---------------------------------------------------------------------------
		Brawler = {
			Style = "Fists",
			Name = "Peleador",
			Icon = "🥊",
			Text = "Equilibrado: pegas más fuerte y aguantas un poco más.",
			Price = 0,
			UpgradeScale = 0.5,
			Bonuses = { Damage = { 0.08, 0.2 }, Health = { 0.05, 0.15 } },
		},
		Monk = {
			Style = "Fists",
			Name = "Monje",
			Icon = "☯️",
			Text = "Golpes rapidísimos y el dash recarga mucho antes.",
			Price = 200,
			UpgradeScale = 1,
			Bonuses = { FireRate = { 0.12, 0.3 }, DashHaste = { 0.2, 0.45 } },
		},
		Tank = {
			Style = "Fists",
			Name = "Tanque",
			Icon = "🛡️",
			Text = "Aguantas muchísimo: mucha más vida y recibes menos daño.",
			Price = 500,
			UpgradeScale = 1.3,
			Bonuses = { Health = { 0.25, 0.6 }, Defense = { 0.1, 0.25 } },
		},
		Berserker = {
			Style = "Fists",
			Name = "Berserker",
			Icon = "😡",
			Text = "Pegas brutal y te curas con cada golpe.",
			Price = 1200,
			UpgradeScale = 1.7,
			Bonuses = { Damage = { 0.2, 0.45 }, LifeSteal = { 0.03, 0.07 } },
		},
		Champion = {
			Style = "Fists",
			Name = "Campeón",
			Icon = "🏆",
			Text = "La definitiva: combo cada 2 golpes, habilidades brutales y más vida.",
			Price = 3000,
			UpgradeScale = 2.5,
			Bonuses = { ComboEvery = 1, SkillDamage = { 0.2, 0.5 }, Health = { 0.15, 0.35 } },
		},

		-- ✨ Magia ---------------------------------------------------------------------------
		Apprentice = {
			Style = "Magic",
			Name = "Aprendiz",
			Icon = "📘",
			Text = "Equilibrado: tus orbes y tus hechizos pegan un poco más.",
			Price = 0,
			UpgradeScale = 0.5,
			Bonuses = { Damage = { 0.08, 0.2 }, SkillDamage = { 0.05, 0.15 } },
		},
		Pyromancer = {
			Style = "Magic",
			Name = "Piromante",
			Icon = "🔥",
			Text = "Tus orbes explotan mucho más grande y más fuerte.",
			Price = 200,
			UpgradeScale = 1,
			Bonuses = { SplashRadius = { 3, 7 }, SplashFraction = { 0.1, 0.3 } },
		},
		Cryomancer = {
			Style = "Magic",
			Name = "Criomante",
			Icon = "❄️",
			Text = "Tus orbes congelan un poco (frenan) y recibes menos daño.",
			Price = 500,
			UpgradeScale = 1.3,
			Bonuses = { Slow = { 0.25, 0.45 }, Defense = { 0.08, 0.2 } },
		},
		Archmage = {
			Style = "Magic",
			Name = "Archimago",
			Icon = "🔮",
			Text = "Tus hechizos recargan mucho antes y pegan más.",
			Price = 1200,
			UpgradeScale = 1.7,
			Bonuses = { SkillHaste = { 0.15, 0.35 }, SkillDamage = { 0.15, 0.35 } },
		},
		Sorcerer = {
			Style = "Magic",
			Name = "Hechicero Supremo",
			Icon = "🌌",
			Text = "La definitiva: robo de vida enorme, mucho más daño y caminas más rápido.",
			Price = 3000,
			UpgradeScale = 2.5,
			Bonuses = { LifeSteal = { 0.05, 0.12 }, Damage = { 0.2, 0.4 }, Speed = { 0.1, 0.2 } },
		},
	},
}

return ClassConfig
