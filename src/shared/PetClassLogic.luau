-- Clases de mascota (PetConfig.Classes): Atacante, Tanque, Sanadora y Recolectora. Lógica pura:
-- la clase de cada mascota, lo que da y lo que dan las equipadas juntas. La usan
-- PlayerDataService (daño), StyleService (daño recibido), HealthService (curación),
-- EnemyService (💰) y el cliente (PetController: insignia y texto de cada mascota).

local PetConfig = require(script.Parent.Config.PetConfig)

local PetClassLogic = {}

export type Bonuses = {
	Damage: number, -- × daño del jugador
	DamageTaken: number, -- × daño que recibe
	Heal: number, -- parte de la vida máxima que cura por segundo
	Money: number, -- × 💰 de los enemigos
}

local function baseId(petId: string): string
	return (string.gsub(petId, "_Evo$", ""))
end

-- Clase de una mascota ("Attacker", "Tank", "Healer" o "Collector"); Atacante si no tiene.
function PetClassLogic.classOf(petId: any): string
	if type(petId) ~= "string" then
		return "Attacker"
	end
	local byId = PetConfig.ClassById and PetConfig.ClassById[baseId(petId)]
	if byId and PetConfig.Classes[byId] then
		return byId
	end
	local pet = PetConfig.Pets[petId]
	local style = pet and pet.Look and pet.Look.Style
	local byStyle = style and PetConfig.StyleClasses and PetConfig.StyleClasses[style]
	if byStyle and PetConfig.Classes[byStyle] then
		return byStyle
	end
	return "Attacker"
end

-- Lo que da una mascota sola: Base de su clase × ClassPower de su rareza.
function PetClassLogic.bonusOf(petId: any): (string, number)
	local classId = PetClassLogic.classOf(petId)
	local def = PetConfig.Classes[classId]
	local pet = type(petId) == "string" and PetConfig.Pets[petId] or nil
	local power = pet and PetConfig.ClassPower[pet.Rarity] or 1
	return classId, (def and def.Base or 0) * power
end

-- Lo que dan las equipadas juntas (cada clase con su tope).
function PetClassLogic.bonuses(petIds: { string }?): Bonuses
	local sums = { Attacker = 0, Tank = 0, Healer = 0, Collector = 0 }
	for _, petId in petIds or {} do
		if PetConfig.Pets[petId] then
			local classId, value = PetClassLogic.bonusOf(petId)
			sums[classId] = (sums[classId] or 0) + value
		end
	end
	local function capped(classId: string): number
		local def = PetConfig.Classes[classId]
		return math.clamp(sums[classId] or 0, 0, if def and def.Max then def.Max else math.huge)
	end
	return {
		Damage = 1 + capped("Attacker"),
		DamageTaken = 1 - capped("Tank"),
		Heal = capped("Healer"),
		Money = 1 + capped("Collector"),
	}
end

local function percentText(value: number): string
	local text = string.format("%.2f", value * 100)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

-- Lo que da una clase con `value`, corto: "+9 % daño", "-6 % daño recibido", "+0.3 % vida/s"
function PetClassLogic.amountText(classId: string, value: number): string
	if classId == "Healer" then
		return ("+%s %% vida/s"):format(percentText(value))
	elseif classId == "Tank" then
		return ("-%s %% daño recibido"):format(percentText(value))
	elseif classId == "Collector" then
		return ("+%s %% 💰"):format(percentText(value))
	end
	return ("+%s %% daño"):format(percentText(value))
end

-- "🛡️ Tanque: -9 % daño recibido" (para la interfaz)
function PetClassLogic.describe(petId: any): string
	local classId, value = PetClassLogic.bonusOf(petId)
	local def = PetConfig.Classes[classId]
	if not def then
		return ""
	end
	return ("%s %s: %s"):format(def.Icon, def.Name, PetClassLogic.amountText(classId, value))
end

-- Resumen de las equipadas: "⚔️ +9 % daño · 💚 +0.3 % vida/s" (solo lo que dan)
function PetClassLogic.summary(bonuses: Bonuses): string
	local parts = {}
	local values = {
		Attacker = bonuses.Damage - 1,
		Tank = 1 - bonuses.DamageTaken,
		Healer = bonuses.Heal,
		Collector = bonuses.Money - 1,
	}
	for _, classId in { "Attacker", "Tank", "Healer", "Collector" } do
		local value = values[classId]
		if value > 1e-6 then
			table.insert(parts, PetConfig.Classes[classId].Icon .. " " .. PetClassLogic.amountText(classId, value))
		end
	end
	return table.concat(parts, "  ·  ")
end

return PetClassLogic
