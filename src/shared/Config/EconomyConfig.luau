-- Valores de la economía y mejoras. El servidor es la única fuente de verdad; el cliente
-- solo los lee para mostrar información.
-- Monedas (desde la economía 2, PetData.EconomyVersion; SaveService convierte la de antes):
-- - 💰 Dinero: la moneda principal. Lo sueltan los enemigos y lo dan las oleadas, los
--   cofres, el premio diario, los códigos y las aventuras. Paga TODO menos las
--   habilidades: armas, guantes y bastones (WeaponConfig), sus mejoras, huevos
--   (EggConfig), portales (ZoneConfig) y las mejoras de la Armería.
-- - 💎 Diamantes: escasos. Los sueltan los enemigos (pocos), las oleadas, los jefes, las
--   misiones, los logros y la tienda. Solo pagan lo del puesto ⚡ Mejoras (habilidades de
--   cada estilo, StyleConfig Skills, y la Velocidad de Correr) y los núcleos de las
--   habilidades elementales (CoreConfig).
--   En el código y en el guardado se llaman Diamonds (profile.Diamonds, atributo Diamonds,
--   DiamondService.grant; hasta el guardado v17, Energy). La ⚡ guardada de la economía 1 se
--   convierte en dinero una vez (SaveService).
-- - 🔄 Fichas de renacer: las da el renacimiento (RebirthConfig).
-- Ya no hay ⚡ energía ni Cristal del Renacimiento (Resonancia): nada se gana sin jugar.
-- El daño de cada arma se mejora en la propia arma (WeaponLogic.upgrade).

local EconomyConfig = {
	-- Versión de la economía (PetData.EconomyVersion). Los registros de una versión anterior
	-- se convierten al cargar (SaveService): su ⚡ pasa a 💰 (· ConvertRate), los 💎 empiezan
	-- en 0 y las cuentas de "energía conseguida" (misiones, título y clasificaciones), también.
	Version = 2,
	ConvertRate = 5,

	StartingDiamonds = 0,
	StartingMoney = 0,

	-- Cada cuántos segundos se avisa a las misiones de los 💎 conseguidos (DiamondService).
	TickInterval = 1,

	-- Los 💎 salen SOLO de pelear y son ESCASOS (pagan clases y habilidades: si sobran, se
	-- mejora todo en una tarde). Ya no dependen del 💰 del enemigo (antes, Reward · 3 %: en
	-- el Mundo 2 eran cientos por bicho). Cada enemigo derrotado da:
	--   💎 = KillDiamonds[su tipo] · DiamondTier[su zona] · (EliteDiamonds si es élite)
	--        · multiplicador de 💎 (pase Diamantes ×2, Poción de Diamantes, amuletos y
	--          Bendición de Abundancia: PlayerDataService.diamondMultiplier)
	-- Lo que no llega a un diamante entero es una probabilidad: en el Bosque, 1 de cada 40
	-- pequeños da 1 💎; un Bruto, 1 de cada 7. Los jefes dan lo suyo (DiamondReward en
	-- EnemyConfig, BossRewardService) y las oleadas, el premio de cada oleada y el de victoria
	-- (WaveConfig.ClearDiamonds / VictoryDiamonds, también por DiamondTier).
	-- Ritmo buscado (jugando oleadas, sin pases): ~140 💎/h en el Bosque, ~200 en el Valle,
	-- ~270 en la Caldera, ~380 en la Tundra y ~550 en el Mundo 2 (ver docs/REDISENO.md).
	KillDiamonds = { Normal = 0.025, Strong = 0.15, Boss = 0 },
	EliteDiamonds = 3, -- × para los élite
	-- Multiplicador de los 💎 de cada zona (enemigos, oleadas y victoria). Crece despacio a
	-- propósito: el 💰 de cada zona se multiplica por ~5, los 💎 no.
	DiamondTier = {
		Forest = 1,
		CrystalValley = 1.6,
		EmberCaldera = 2.5,
		FrozenTundra = 3.5,
		GoblinFortress = 4.5,
		World2 = 5,
		DividedLands = 5.5,
	},

	-- Coste del nivel N = floor(BaseCost * CostMultiplier ^ N), en 💰 o en 💎 (Currency).
	Upgrades = {
		WalkSpeed = {
			DisplayName = "Velocidad de Correr",
			Description = "Corres un poco más rápido: +1 de velocidad por nivel.",
			Currency = "Diamonds", -- 💎 (en el puesto ⚡ Mejoras, SkillsController)
			-- Antes +2.5 por nivel hasta el 20 (+50: casi el doble de rápido). Ahora un extra
			-- pequeño: como mucho +10 (28 -> 38). Los niveles guardados por encima de MaxLevel
			-- cuentan como MaxLevel (PlayerDataService.applyBody).
			BaseCost = 20,
			CostMultiplier = 1.35,
			SpeedPerLevel = 1, -- PlayerDataService: 28 + nivel · esto (antes de amuleto y estilo)
			MaxLevel = 10,
		},
		PetPower = {
			DisplayName = "Poder de Mascotas",
			Description = "Aumenta un +25% el daño que hacen tus mascotas en cada golpe.",
			Currency = "Money",
			BaseCost = 40,
			CostMultiplier = 1.55,
			MaxLevel = 30,
		},
		-- Defensa (pruebas con amigos: "faltan mejoras defensivas"). Con 💰, en el panel ⚡ Mejoras.
		-- Vitalidad: +HealthPerLevel de vida máxima por nivel (PlayerDataService.applyBody).
		Vitality = {
			DisplayName = "Vitalidad",
			Description = "Más vida máxima: +6 % por nivel.",
			Currency = "Money",
			BaseCost = 300,
			CostMultiplier = 1.7,
			HealthPerLevel = 0.06,
			MaxLevel = 10,
		},
		-- Armadura: -ReductionPerLevel del daño que recibes por nivel (StyleService, con el del
		-- estilo y la clase).
		Armor = {
			DisplayName = "Armadura",
			Description = "Recibes menos daño: -3 % por nivel.",
			Currency = "Money",
			BaseCost = 400,
			CostMultiplier = 1.7,
			ReductionPerLevel = 0.03,
			MaxLevel = 10,
		},
		LaserSpeed = {
			DisplayName = "Cadencia",
			Description = "Todas tus armas disparan más rápido (-2.5 % de tiempo entre disparos por nivel).",
			Currency = "Money",
			BaseCost = 60,
			CostMultiplier = 1.65,
			MaxLevel = 15,
		},
	},

	-- Protección contra solicitudes repetidas.
	PurchaseRateLimit = {
		Cooldown = 0.2,
		WindowSeconds = 2,
		MaxRequestsPerWindow = 10,
	},
}

return EconomyConfig
