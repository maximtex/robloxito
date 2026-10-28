-- Fórmulas puras de la economía. Las usa el servidor para validar
-- y el cliente solo para mostrar costes.

local EconomyConfig = require(script.Parent.Config.EconomyConfig)

local Economy = {}

function Economy.getUpgradeDefinition(upgradeId: string)
	return EconomyConfig.Upgrades[upgradeId]
end

-- Moneda con la que se paga una mejora: "Money" (💰) o "Diamonds" (💎)
function Economy.getUpgradeCurrency(upgradeId: string): string
	local definition = EconomyConfig.Upgrades[upgradeId]
	return if definition and definition.Currency == "Money" then "Money" else "Diamonds"
end

function Economy.getUpgradeCost(upgradeId: string, currentLevel: number): number?
	local definition = EconomyConfig.Upgrades[upgradeId]
	if not definition then
		return nil
	end
	return math.floor(definition.BaseCost * definition.CostMultiplier ^ currentLevel)
end

-- Nivel de una mejora sin pasar de su máximo (los guardados por encima cuentan como el máximo).
function Economy.cappedLevel(upgradeId: string, level: any): number
	local definition = EconomyConfig.Upgrades[upgradeId]
	local value = if type(level) == "number" and level == level then math.max(0, math.floor(level)) else 0
	if definition and type(definition.MaxLevel) == "number" then
		value = math.min(value, definition.MaxLevel)
	end
	return value
end

-- × vida máxima por la Vitalidad (1 sin mejora).
function Economy.vitalityMultiplier(level: any): number
	local definition = EconomyConfig.Upgrades.Vitality
	if not definition then
		return 1
	end
	return 1 + (definition.HealthPerLevel or 0) * Economy.cappedLevel("Vitality", level)
end

-- × daño recibido por la Armadura (1 sin mejora; nunca menos de 0.5).
function Economy.armorMultiplier(level: any): number
	local definition = EconomyConfig.Upgrades.Armor
	if not definition then
		return 1
	end
	return math.max(0.5, 1 - (definition.ReductionPerLevel or 0) * Economy.cappedLevel("Armor", level))
end

return Economy
