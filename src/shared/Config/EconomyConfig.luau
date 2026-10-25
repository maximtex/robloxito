-- Valores de la economía y mejoras. El servidor es la única fuente de verdad; el cliente
-- solo los lee para mostrar información.
-- Dos monedas: la energía (la sueltan los enemigos según tu poder de energía; paga la Resonancia del
-- Cristal, zonas y núcleos) y el dinero (lo sueltan los enemigos; paga las armas
-- (WeaponConfig) y las mejoras con Currency = "Money", las de la Armería del pueblo).
-- El daño de cada arma se mejora en la propia arma (WeaponLogic.upgrade).

local EconomyConfig = {
	StartingEnergy = 0,
	StartingMoney = 0,

	-- Producción base sin mejoras (energía por segundo).
	BaseProductionPerSecond = 1,

	-- Cada cuántos segundos el servidor suma energía.
	TickInterval = 1,

	-- La energía sale SOLO de matar enemigos (rediseño "solo disparar"):
	-- - PassiveEnergy = false: el cristal y los núcleos ya no suman energía cada segundo ni
	--   mientras no juegas (EnergyService, PlayerDataService). Con true vuelve lo de antes.
	-- - Cada enemigo derrotado da ⚡ = Reward del enemigo · KillEnergyShare · "poder de
	--   energía" (profile.ProductionPerSecond: Resonancia, núcleos, mascotas, renacimiento,
	--   amuletos y el pase Energía ×2). Así las mejoras de siempre siguen subiendo la energía,
	--   pero solo se cobra peleando. Con 0.15 un Espinillo (35) da ~5 ⚡ al empezar.
	PassiveEnergy = false,
	KillEnergyShare = 0.15,

	-- Coste del nivel N = floor(BaseCost * CostMultiplier ^ N), en energía salvo Currency.
	Upgrades = {
		GeneratorPower = {
			DisplayName = "Resonancia del Cristal",
			Description = "Más ⚡ por cada enemigo que derrotas.",
			BaseCost = 10,
			CostMultiplier = 1.45,
			ProductionPerLevel = 1,
			MaxLevel = 50,
		},
		WalkSpeed = {
			DisplayName = "Velocidad de Correr",
			Description = "Aumenta la velocidad al correr de tu personaje por el mapa.",
			Currency = "Money",
			BaseCost = 25,
			CostMultiplier = 1.55,
			ProductionPerLevel = 0,
			SpeedPerLevel = 1.5,
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
