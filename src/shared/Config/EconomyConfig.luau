-- Valores de la economía y mejoras. El servidor es la única fuente de verdad; el cliente
-- solo los lee para mostrar información.
-- Dos monedas: la energía (el cristal y los núcleos la producen; paga la Resonancia del
-- Cristal, huevos, zonas y núcleos) y el dinero (lo sueltan los enemigos; paga las mejoras
-- con Currency = "Money", las de la Tienda de Láser del pueblo).

local EconomyConfig = {
	StartingEnergy = 0,
	StartingMoney = 0,

	-- Producción base sin mejoras (energía por segundo).
	BaseProductionPerSecond = 1,

	-- Cada cuántos segundos el servidor suma energía.
	TickInterval = 1,

	-- Coste del nivel N = floor(BaseCost * CostMultiplier ^ N), en energía salvo Currency.
	Upgrades = {
		GeneratorPower = {
			DisplayName = "Resonancia del Cristal",
			Description = "Aumenta la energía que produce el cristal.",
			BaseCost = 10,
			CostMultiplier = 1.45,
			ProductionPerLevel = 1,
			MaxLevel = 50,
		},
		LaserPower = {
			DisplayName = "Potencia del Láser",
			Description = "Aumenta el daño del rayo láser de tu personaje y su color.",
			Currency = "Money",
			BaseCost = 10,
			CostMultiplier = 1.45,
			ProductionPerLevel = 0,
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
			DisplayName = "Cadencia del Láser",
			Description = "Hace que el láser de tu personaje dispare mucho más rápido.",
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
