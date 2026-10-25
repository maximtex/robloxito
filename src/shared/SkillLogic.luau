-- Lógica pura de las habilidades de cada estilo (StyleConfig.Styles[estilo].Skills): cuáles
-- tienes, su nivel, cuáles llevas puestas en la Z y la X, comprarlas y subirlas con 💎
-- diamantes (en el código, Energy) y sus números a cada nivel. Sin servicios: la usan
-- StyleService (valida y cobra), SaveService (guardar), PlayerDataService (atributos) y el
-- cliente (SkillsController y StyleController, solo para mostrar).
--
-- Datos (profile.PetData.Skills):
--   Owned: { [habilidad]: nivel }   las que tiene (1..StyleConfig.SkillLevels.Max); las
--                                   iniciales de cada estilo (StartSkills) siempre, a nivel 1
--   Equipped: { [estilo]: { a, b } } las dos puestas de cada estilo (1 = Z, 2 = X)
--   Picked: boolean                 ya eligió su estilo al empezar (StylePicker)
-- Lo que ya no existe se conserva en Archived tal cual.

local StyleConfig = require(script.Parent.Config.StyleConfig)

local SkillLogic = {}

export type SkillData = {
	Owned: { [string]: number },
	Equipped: { [string]: { string } },
	Picked: boolean,
	Archived: { [string]: any }?,
}

local MAX_ID = 40

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function levels()
	return StyleConfig.SkillLevels
end

-- Estilo al que pertenece una habilidad (y su definición), o nil.
local styleOfSkill: { [string]: string } = {}
for styleId, style in StyleConfig.Styles do
	for skillId in style.Skills or {} do
		styleOfSkill[skillId] = styleId
	end
end

function SkillLogic.styleOf(skillId: any): string?
	return if type(skillId) == "string" then styleOfSkill[skillId] else nil
end

function SkillLogic.definition(skillId: any): { [string]: any }?
	local styleId = SkillLogic.styleOf(skillId)
	return if styleId then StyleConfig.Styles[styleId].Skills[skillId] else nil
end

-- Habilidades de un estilo en su orden (Order)
function SkillLogic.ordered(styleId: string): { string }
	local style = StyleConfig.Styles[styleId]
	local ids = {}
	for skillId in (style and style.Skills) or {} do
		table.insert(ids, skillId)
	end
	table.sort(ids, function(a, b)
		return (style.Skills[a].Order or 0) < (style.Skills[b].Order or 0)
	end)
	return ids
end

local function starters(styleId: string): { string }
	local style = StyleConfig.Styles[styleId]
	return (style and style.StartSkills) or {}
end

function SkillLogic.empty(): SkillData
	local data = { Owned = {}, Equipped = {}, Picked = false }
	for styleId in StyleConfig.Styles do
		local start = starters(styleId)
		for _, skillId in start do
			data.Owned[skillId] = 1
		end
		data.Equipped[styleId] = { start[1], start[2] }
	end
	return data
end

-- Datos guardados -> válidos. Lo desconocido se archiva; lo corrupto toma el valor inicial.
function SkillLogic.sanitize(raw: any): SkillData
	local data = SkillLogic.empty()
	if type(raw) ~= "table" then
		return data
	end
	local archived = {}
	if type(raw.Owned) == "table" then
		for skillId, level in raw.Owned do
			if SkillLogic.definition(skillId) then
				if finite(level) then
					data.Owned[skillId] = math.clamp(math.floor(level), 1, levels().Max)
				end
			elseif type(skillId) == "string" and #skillId <= MAX_ID and finite(level) then
				archived[skillId] = level
			end
		end
	end
	if type(raw.Archived) == "table" then
		for skillId, value in raw.Archived do
			if type(skillId) == "string" and #skillId <= MAX_ID and not SkillLogic.definition(skillId) then
				archived[skillId] = value
			end
		end
	end
	if next(archived) ~= nil then
		data.Archived = archived
	end
	if type(raw.Equipped) == "table" then
		for styleId in StyleConfig.Styles do
			local slots = raw.Equipped[styleId]
			if type(slots) == "table" then
				local clean = {}
				for slot = 1, 2 do
					local skillId = slots[slot]
					if data.Owned[skillId] and SkillLogic.styleOf(skillId) == styleId and not table.find(clean, skillId) then
						clean[slot] = skillId
					end
				end
				-- Huecos vacíos: con las que tenga del estilo (primero las iniciales)
				for slot = 1, 2 do
					if not clean[slot] then
						for _, skillId in SkillLogic.ordered(styleId) do
							if data.Owned[skillId] and clean[1] ~= skillId and clean[2] ~= skillId then
								clean[slot] = skillId
								break
							end
						end
					end
				end
				data.Equipped[styleId] = { clean[1], clean[2] }
			end
		end
	end
	data.Picked = raw.Picked == true
	return data
end

function SkillLogic.serialize(data: SkillData): { [string]: any }
	local equipped = {}
	for styleId, slots in data.Equipped do
		equipped[styleId] = { slots[1], slots[2] }
	end
	local out: { [string]: any } = { Owned = table.clone(data.Owned), Equipped = equipped, Picked = data.Picked == true }
	if data.Archived and next(data.Archived) ~= nil then
		out.Archived = table.clone(data.Archived)
	end
	return out
end

function SkillLogic.level(data: SkillData, skillId: string): number
	return data.Owned[skillId] or 0
end

-- La habilidad puesta en el hueco `slot` (1 = Z, 2 = X) del estilo
function SkillLogic.equipped(data: SkillData?, styleId: string, slot: number): string?
	local slots = data and data.Equipped[styleId]
	local skillId = slots and slots[slot]
	if skillId and SkillLogic.styleOf(skillId) == styleId then
		return skillId
	end
	return starters(styleId)[slot]
end

-- Números a un nivel --------------------------------------------------------------------------

-- Multiplicador del daño (y del poder de lo que dure) a ese nivel: +Damage por nivel
function SkillLogic.power(level: number?): number
	local lvl = if finite(level) then math.clamp(math.floor(level :: number), 1, levels().Max) else 1
	return 1 + levels().Damage * (lvl - 1)
end

-- Recarga a ese nivel: -Cooldown por nivel, como mucho hasta MinCooldown de la base
function SkillLogic.cooldown(def: { [string]: any }, level: number?): number
	local lvl = if finite(level) then math.clamp(math.floor(level :: number), 1, levels().Max) else 1
	local factor = math.max(levels().MinCooldown, 1 - levels().Cooldown * (lvl - 1))
	return (def.Cooldown or 10) * factor
end

-- Duración de lo que dura (Ráfaga, Furia, Torreta, Agujero negro) a ese nivel
function SkillLogic.duration(def: { [string]: any }, level: number?): number
	local lvl = if finite(level) then math.clamp(math.floor(level :: number), 1, levels().Max) else 1
	return (def.Duration or 0) * (1 + levels().Duration * (lvl - 1))
end

-- 💎 para subir del nivel `level` al siguiente (nil si ya está al máximo)
function SkillLogic.upgradeCost(skillId: string, level: number): number?
	local def = SkillLogic.definition(skillId)
	if not def or not finite(level) or level < 1 or level >= levels().Max then
		return nil
	end
	local scale = if finite(def.UpgradeScale) then def.UpgradeScale else 1
	return math.floor(levels().UpgradeBase * scale * levels().UpgradeGrowth ^ (level - 1))
end

-- Acciones (devuelven el código y los 💎 cobrados; quien llama los resta) ---------------------

-- Comprar: "Success" (queda a nivel 1), "InvalidRequest", "AlreadyOwned" o
-- "InsufficientEnergy" (faltan 💎), y el precio.
function SkillLogic.buy(data: SkillData, skillId: any, diamonds: any): (string, number)
	local def = SkillLogic.definition(skillId)
	if not def then
		return "InvalidRequest", 0
	end
	if data.Owned[skillId] then
		return "AlreadyOwned", 0
	end
	local price = def.Price or 0
	if not (finite(diamonds) and diamonds >= price) then
		return "InsufficientEnergy", price
	end
	data.Owned[skillId] = 1
	return "Success", price
end

-- Subir un nivel: "Success", "InvalidRequest", "NotOwned", "MaxLevel" o "InsufficientEnergy".
function SkillLogic.upgrade(data: SkillData, skillId: any, diamonds: any): (string, number)
	if not SkillLogic.definition(skillId) then
		return "InvalidRequest", 0
	end
	local level = data.Owned[skillId]
	if not level then
		return "NotOwned", 0
	end
	local cost = SkillLogic.upgradeCost(skillId, level)
	if not cost then
		return "MaxLevel", 0
	end
	if not (finite(diamonds) and diamonds >= cost) then
		return "InsufficientEnergy", cost
	end
	data.Owned[skillId] = level + 1
	return "Success", cost
end

-- Ponerla en el hueco `slot` (1 = Z, 2 = X) de su estilo. Si ya estaba en el otro, se
-- intercambian. "Success", "InvalidRequest" o "NotOwned".
function SkillLogic.equip(data: SkillData, skillId: any, slot: any): string
	local styleId = SkillLogic.styleOf(skillId)
	if not styleId or (slot ~= 1 and slot ~= 2) then
		return "InvalidRequest"
	end
	if not data.Owned[skillId] then
		return "NotOwned"
	end
	local slots = data.Equipped[styleId] or { starters(styleId)[1], starters(styleId)[2] }
	local other = if slot == 1 then 2 else 1
	if slots[other] == skillId then
		slots[other] = slots[slot]
	end
	slots[slot] = skillId
	data.Equipped[styleId] = slots
	return "Success"
end

-- Para el cliente (atributos) ------------------------------------------------------------------

-- "Burst:1,Grenade:3,Pierce:1"
function SkillLogic.ownedText(data: SkillData): string
	local parts = {}
	for _, styleId in StyleConfig.Order do
		for _, skillId in SkillLogic.ordered(styleId) do
			local level = data.Owned[skillId]
			if level then
				table.insert(parts, skillId .. ":" .. level)
			end
		end
	end
	return table.concat(parts, ",")
end

function SkillLogic.parseOwned(text: any): { [string]: number }
	local owned = {}
	if type(text) == "string" then
		for skillId, level in text:gmatch("([%w_]+):(%d+)") do
			if SkillLogic.definition(skillId) then
				owned[skillId] = tonumber(level) or 1
			end
		end
	end
	return owned
end

-- "Weapons=Burst,Grenade;Fists=Quake,Dash;Magic=Meteors,Nova"
function SkillLogic.slotsText(data: SkillData): string
	local parts = {}
	for _, styleId in StyleConfig.Order do
		table.insert(parts, ("%s=%s,%s"):format(styleId, SkillLogic.equipped(data, styleId, 1) or "", SkillLogic.equipped(data, styleId, 2) or ""))
	end
	return table.concat(parts, ";")
end

function SkillLogic.parseSlots(text: any): { [string]: { string } }
	local slots = {}
	if type(text) == "string" then
		for styleId, first, second in text:gmatch("([%w_]+)=([%w_]*),([%w_]*)") do
			slots[styleId] = { first, second }
		end
	end
	return slots
end

return SkillLogic
