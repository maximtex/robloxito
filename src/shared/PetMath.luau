-- Cálculos de mascotas compartidos. El servidor los usa para la producción real;
-- el cliente solo para mostrar información.

local PetConfig = require(script.Parent.Config.PetConfig)

local PetMath = {}

function PetMath.getPetMultiplier(petId: string): number
	local pet = PetConfig.Pets[petId]
	if not pet then
		return 1
	end
	if type(pet.Multiplier) == "number" then
		return pet.Multiplier
	end
	local rarity = PetConfig.Rarities[pet.Rarity]
	return if rarity then rarity.Multiplier else 1
end

-- Las bonificaciones se suman: 1 + Σ(multiplicador - 1). Redondeado a 3 decimales.
function PetMath.getTotalMultiplier(petIds: { string }): number
	local total = 1
	for _, petId in petIds do
		total += PetMath.getPetMultiplier(petId) - 1
	end
	return math.floor(total * 1000 + 0.5) / 1000
end

function PetMath.getRarity(petId: string)
	local pet = PetConfig.Pets[petId]
	return if pet then PetConfig.Rarities[pet.Rarity] else nil
end

return PetMath
