-- Fórmulas puras de la economía. Las usa el servidor para validar
-- y el cliente solo para mostrar costes.

local EconomyConfig = require(script.Parent.Config.EconomyConfig)

local Economy = {}

function Economy.getUpgradeDefinition(upgradeId: string)
	return EconomyConfig.Upgrades[upgradeId]
end

function Economy.getUpgradeCost(upgradeId: string, currentLevel: number): number?
	local definition = EconomyConfig.Upgrades[upgradeId]
	if not definition then
		return nil
	end
	return math.floor(definition.BaseCost * definition.CostMultiplier ^ currentLevel)
end

function Economy.getProductionPerSecond(upgradeLevels: { [string]: number }): number
	local total = EconomyConfig.BaseProductionPerSecond
	for upgradeId, level in upgradeLevels do
		local definition = EconomyConfig.Upgrades[upgradeId]
		if definition then
			total += definition.ProductionPerLevel * level
		end
	end
	return total
end

return Economy
