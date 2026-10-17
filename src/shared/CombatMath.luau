-- Fórmulas de combate (puras). El servidor calcula el daño real con ellas; el cliente
-- solo las usa para mostrar información.

local CombatConfig = require(script.Parent.Config.CombatConfig)
local PetCombatConfig = require(script.Parent.Config.PetCombatConfig)

local CombatMath = {}

-- Daño de un golpe del jugador según su nivel de mejora y su multiplicador de mascotas.
function CombatMath.playerDamage(upgradeLevel: number, petMultiplier: number): number
	local level = math.max(0, math.floor(upgradeLevel))
	local petBonus = math.max(0, petMultiplier - 1) * CombatConfig.PetDamageShare
	local damage = (CombatConfig.BaseDamage + CombatConfig.DamagePerLevel * level) * (1 + petBonus)
	return math.floor(damage * 100 + 0.5) / 100
end

-- Daño de una habilidad de mascota: fracción del daño actual del jugador.
function CombatMath.petAbilityDamage(ratio: number, playerDamage: number): number
	return math.floor(math.max(0, ratio) * math.max(0, playerDamage) * 100 + 0.5) / 100
end

-- Reducción defensiva de las Tortugas equipadas: se calcula a partir del NÚMERO actual
-- de tortugas (no se acumula con el tiempo) y tiene un tope.
function CombatMath.guardReduction(turtleCount: number): number
	local guard = PetCombatConfig.Abilities.CrystalTurtle
	if not guard or turtleCount <= 0 then
		return 0
	end
	return math.min(guard.MaxReduction, guard.ReductionPerPet * turtleCount)
end

-- Daño recibido tras la reducción (nunca negativo).
function CombatMath.reduceIncoming(amount: number, reduction: number): number
	return math.max(0, amount * (1 - math.clamp(reduction, 0, 1)))
end

return CombatMath
