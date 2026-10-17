-- Valores de la economía. El servidor es la única fuente de verdad;
-- el cliente solo los lee para mostrar información.

local EconomyConfig = {
	StartingEnergy = 0,

	-- Producción base sin mejoras (energía por segundo).
	BaseProductionPerSecond = 1,

	-- Cada cuántos segundos el servidor suma energía.
	TickInterval = 1,

	Upgrades = {
		GeneratorPower = {
			DisplayName = "Resonancia del Cristal",
			BaseCost = 10,
			-- Coste del nivel N = floor(BaseCost * CostMultiplier ^ N)
			CostMultiplier = 1.5,
			ProductionPerLevel = 1,
			MaxLevel = 50,
		},
	},

	-- Protección contra solicitudes repetidas.
	PurchaseRateLimit = {
		Cooldown = 0.3, -- segundos mínimos entre compras
		WindowSeconds = 2,
		MaxRequestsPerWindow = 8, -- por encima de esto se ignoran sin responder
	},
}

return EconomyConfig
