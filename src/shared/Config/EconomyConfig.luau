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

	-- Los 💎 salen SOLO de pelear: cada enemigo derrotado da 💎 = Reward del enemigo ·
	-- KillDiamondShare · multiplicador de 💎 (pase Diamantes ×2, Poción de Diamantes,
	-- amuletos y Bendición de Abundancia: PlayerDataService.diamondMultiplier). Lo que no
	-- llega a un diamante entero es una probabilidad: con 0.03 un Espinillo (35) da 1 💎
	-- casi siempre; un Bruto (140), unos 4.
	KillDiamondShare = 0.03,

	-- Coste del nivel N = floor(BaseCost * CostMultiplier ^ N), en 💰 o en 💎 (Currency).
	Upgrades = {
		WalkSpeed = {
			DisplayName = "Velocidad de Correr",
			Description = "Corres más rápido: +2.5 de velocidad por nivel.",
			Currency = "Diamonds", -- 💎 (en el puesto ⚡ Mejoras, SkillsController)
			BaseCost = 15,
			CostMultiplier = 1.3,
			SpeedPerLevel = 2.5, -- PlayerDataService: 28 + nivel · esto (antes de amuleto y estilo)
			MaxLevel = 20,
		},
		PetPower = {
			DisplayName = "Poder de Mascotas",
			Description = "Aumenta un +25% el daño que hacen tus mascotas en cada golpe.",
			Currency = "Money",
			BaseCost = 40,
			CostMultiplier = 1.55,
			MaxLevel = 30,
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
