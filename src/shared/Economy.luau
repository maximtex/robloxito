-- Fórmulas puras de la economía. Las usa el servidor para validar
-- y el cliente solo para mostrar costes.

local EconomyConfig = require(script.Parent.Config.EconomyConfig)

local Economy = {}

function Economy.getUpgradeDefinition(upgradeId: string)
	return EconomyConfig.Upgrades[upgradeId]
end

-- Moneda con la que se paga una mejora: "Money" (💰) o "Energy" (💎)
function Economy.getUpgradeCurrency(upgradeId: string): string
	local definition = EconomyConfig.Upgrades[upgradeId]
	return if definition and definition.Currency == "Money" then "Money" else "Energy"
end

function Economy.getUpgradeCost(upgradeId: string, currentLevel: number): number?
	local definition = EconomyConfig.Upgrades[upgradeId]
	if not definition then
		return nil
	end
	return math.floor(definition.BaseCost * definition.CostMultiplier ^ currentLevel)
end

return Economy
