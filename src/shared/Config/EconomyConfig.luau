-- Valores de la economía y mejoras. El servidor es la única fuente de verdad; el cliente
-- solo los lee para mostrar información.
-- Dos monedas (desde la economía 2, PetData.EconomyVersion; EconomyService convierte la de
-- antes):
-- - 💰 Dinero: la moneda principal. Lo sueltan los enemigos y lo dan las oleadas, los
--   cofres, el premio diario y las aventuras. Paga TODO menos las habilidades: armas,
--   guantes y bastones (WeaponConfig), sus mejoras, huevos (EggConfig), portales
--   (ZoneConfig) y las mejoras de la Armería (también la Resonancia).
-- - 💎 Diamantes: escasos. Los sueltan los enemigos (pocos), las oleadas, los jefes, las
--   misiones y la tienda. Solo pagan lo del puesto ⚡ Mejoras (habilidades de cada estilo,
--   StyleConfig Skills, y la Velocidad de Correr) y los núcleos de las habilidades
--   elementales (CoreConfig).
--   En el código (y en el guardado) los diamantes siguen llamándose Energy (profile.Energy,
--   atributo Energy, EnergyService.grant): era la moneda que soltaban los enemigos. La
--   energía guardada de antes se convierte en dinero una vez (EconomyService).
-- El daño de cada arma se mejora en la propia arma (WeaponLogic.upgrade).

local EconomyConfig = {
	-- Versión de la economía (PetData.EconomyVersion). Los registros de una versión anterior
	-- se convierten al cargar (SaveService): su ⚡ pasa a 💰 (· ConvertRate), los 💎 empiezan
	-- en 0 y las cuentas de "energía conseguida" (misiones, título y clasificaciones), también.
	Version = 2,
	ConvertRate = 5,

	StartingEnergy = 0,
	StartingMoney = 0,

	-- Producción base sin mejoras (energía por segundo).
	BaseProductionPerSecond = 1,

	-- Cada cuántos segundos el servidor suma energía.
	TickInterval = 1,

	-- Los 💎 salen SOLO de pelear (nada pasivo):
	-- - PassiveEnergy = false: el cristal y los núcleos ya no suman nada cada segundo ni
	--   mientras no juegas (EnergyService, PlayerDataService). Con true vuelve lo de antes.
	-- - Cada enemigo derrotado da 💎 = Reward del enemigo · KillEnergyShare · poder de
	--   diamantes (WaveLogic.diamondPower del "poder de energía" profile.ProductionPerSecond:
	--   Resonancia, núcleos, mascotas, renacimiento, amuletos y el pase ×2, que aquí suben
	--   poco a poco). Lo que no llega a un diamante entero es una probabilidad: con 0.03 un
	--   Espinillo (35) da 1 💎 casi siempre; un Bruto (140), unos 4.
	PassiveEnergy = false,
	KillEnergyShare = 0.03,

	-- Lo que antes se pagaba en ⚡ "minutos de producción" (cofres, premio diario, aventuras)
	-- ahora se paga en 💰: esa misma cantidad · RewardMoneyRate.
	RewardMoneyRate = 5,

	-- Coste del nivel N = floor(BaseCost * CostMultiplier ^ N), en energía salvo Currency.
	Upgrades = {
		GeneratorPower = {
			DisplayName = "Resonancia del Cristal",
			Description = "Más 💎 por cada enemigo que derrotas (y la cuenta para renacer).",
			Currency = "Money",
			BaseCost = 60,
			CostMultiplier = 1.45,
			ProductionPerLevel = 1,
			MaxLevel = 50,
		},
		WalkSpeed = {
			DisplayName = "Velocidad de Correr",
			Description = "Corres más rápido: +2.5 de velocidad por nivel.",
			Currency = "Energy", -- 💎 (en el puesto ⚡ Mejoras, SkillsController)
			BaseCost = 15,
			CostMultiplier = 1.3,
			ProductionPerLevel = 0,
			SpeedPerLevel = 2.5, -- PlayerDataService: 28 + nivel · esto (antes de amuleto y estilo)
			MaxLevel = 20,
		},
		PetPower = {
			DisplayName = "Poder de Mascotas",
			Description = "Aumenta un +25% el daño que hacen tus mascotas en cada golpe.",
			Currency = "Money",
			BaseCost = 40,
			CostMultiplier = 1.55,
			ProductionPerLevel = 0,
			MaxLevel = 30,
		},
		LaserSpeed = {
			DisplayName = "Cadencia",
			Description = "Todas tus armas disparan más rápido (-2.5 % de tiempo entre disparos por nivel).",
			Currency = "Money",
			BaseCost = 60,
			CostMultiplier = 1.65,
			ProductionPerLevel = 0,
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
