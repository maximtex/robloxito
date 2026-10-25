-- Lógica pura de las armas (WeaponConfig): datos guardados, comprar, mejorar, equipar y los
-- números de combate. El servidor la usa para validar (WeaponService, PetCombatService) y
-- el cliente solo para mostrar.
--
-- Datos (profile.PetData.Weapons):
--   Owned: { [id]: true }    armas, guantes y bastones que tiene (los iniciales siempre)
--   Levels: { [id]: number } nivel de mejora de cada uno (0..MaxLevel)
--   Equipped: string         arma con la que dispara el estilo Armas (siempre una que tiene)
--   Slots: { Fists, Magic }  guantes y bastón equipados de los otros dos estilos
-- Lo que ya no existe en WeaponConfig se conserva en Archived tal cual.
-- Cada objeto es de una categoría (WeaponConfig, Category: "Weapons", "Fists" o "Magic"):
-- la de cada estilo, con su tienda, su equipado y sus niveles aparte.

local WeaponConfig = require(script.Parent.Config.WeaponConfig)
local CombatConfig = require(script.Parent.Config.CombatConfig)

local WeaponLogic = {}

export type WeaponData = {
	Owned: { [string]: boolean },
	Levels: { [string]: number },
	Equipped: string,
	Slots: { [string]: string },
	Archived: { [string]: any }?,
}

local OTHER_CATEGORIES = { "Fists", "Magic" }

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function round2(value: number): number
	return math.floor(value * 100 + 0.5) / 100
end

function WeaponLogic.definition(weaponId: any)
	return if type(weaponId) == "string" then WeaponConfig.Weapons[weaponId] else nil
end

-- Categoría de un objeto ("Weapons" si no dice otra)
function WeaponLogic.category(weaponId: any): string
	local def = WeaponLogic.definition(weaponId)
	return if def and type(def.Category) == "string" then def.Category else "Weapons"
end

-- Mundo de un objeto (World; 1 si no lo dice): cada Armería enseña los de su mundo
function WeaponLogic.world(weaponId: any): number
	local def = WeaponLogic.definition(weaponId)
	return if def and type(def.World) == "number" then def.World else 1
end

-- Objeto inicial de una categoría
function WeaponLogic.starter(category: string): string
	local starters = WeaponConfig.Starters
	return (starters and starters[category]) or WeaponConfig.StarterWeapon
end

function WeaponLogic.empty(): WeaponData
	local starter = WeaponConfig.StarterWeapon
	local data = { Owned = { [starter] = true }, Levels = { [starter] = 0 }, Equipped = starter, Slots = {} }
	for _, category in OTHER_CATEGORIES do
		local id = WeaponLogic.starter(category)
		if WeaponLogic.definition(id) then
			data.Owned[id] = true
			data.Levels[id] = 0
			data.Slots[category] = id
		end
	end
	return data
end

-- Datos guardados -> válidos. Lo desconocido se archiva; lo corrupto toma el valor inicial.
function WeaponLogic.sanitize(raw: any): WeaponData
	local data = WeaponLogic.empty()
	if type(raw) ~= "table" then
		return data
	end
	local archived = {}
	if type(raw.Owned) == "table" then
		for _, weaponId in raw.Owned do
			if WeaponLogic.definition(weaponId) then
				data.Owned[weaponId] = true
			elseif type(weaponId) == "string" and #weaponId <= 64 then
				archived[weaponId] = true
			end
		end
	end
	if type(raw.Levels) == "table" then
		for weaponId, level in raw.Levels do
			if WeaponLogic.definition(weaponId) and data.Owned[weaponId] and isFinite(level) then
				data.Levels[weaponId] = math.clamp(math.floor(level), 0, WeaponConfig.MaxLevel)
			end
		end
	end
	if type(raw.Archived) == "table" then
		for weaponId, value in raw.Archived do
			if type(weaponId) == "string" and #weaponId <= 64 and not WeaponLogic.definition(weaponId) then
				archived[weaponId] = value
			end
		end
	end
	if next(archived) ~= nil then
		data.Archived = archived
	end
	if data.Owned[raw.Equipped] and WeaponLogic.category(raw.Equipped) == "Weapons" then
		data.Equipped = raw.Equipped
	end
	if type(raw.Slots) == "table" then
		for _, category in OTHER_CATEGORIES do
			local id = raw.Slots[category]
			if data.Owned[id] and WeaponLogic.category(id) == category then
				data.Slots[category] = id
			end
		end
	end
	return data
end

-- Copia para guardar (listas en vez de diccionarios de booleanos)
function WeaponLogic.serialize(data: WeaponData): { [string]: any }
	local owned = {}
	for weaponId in data.Owned do
		table.insert(owned, weaponId)
	end
	table.sort(owned)
	local out: { [string]: any } = { Owned = owned, Levels = table.clone(data.Levels), Equipped = data.Equipped, Slots = table.clone(data.Slots or {}) }
	if data.Archived and next(data.Archived) ~= nil then
		out.Archived = table.clone(data.Archived)
	end
	return out
end

function WeaponLogic.owns(data: WeaponData, weaponId: string): boolean
	return data.Owned[weaponId] == true
end

function WeaponLogic.level(data: WeaponData, weaponId: string): number
	return data.Levels[weaponId] or 0
end

-- Armas en el orden de la Armería (solo las de `category` si se pide una)
function WeaponLogic.ordered(category: string?): { string }
	local ids = {}
	for weaponId in WeaponConfig.Weapons do
		if category == nil or WeaponLogic.category(weaponId) == category then
			table.insert(ids, weaponId)
		end
	end
	table.sort(ids, function(a, b)
		return WeaponConfig.Weapons[a].Order < WeaponConfig.Weapons[b].Order
	end)
	return ids
end

-- ¿Cumple lo que pide el arma para venderse? (zonas desbloqueadas: lista de ids)
function WeaponLogic.meetsRequirement(weaponId: string, unlockedZones: { string }?): boolean
	local def = WeaponLogic.definition(weaponId)
	if not def then
		return false
	end
	local requires = def.Requires
	if requires and requires.Zone then
		return unlockedZones ~= nil and table.find(unlockedZones, requires.Zone) ~= nil
	end
	return true
end

-- Comprar: "Success" (y queda en Owned, nivel 0), "InvalidRequest", "AlreadyOwned",
-- "NotForSale" (se consigue de un jefe), "Locked" (falta la zona) o "InsufficientMoney".
-- Devuelve también el precio.
function WeaponLogic.buy(data: WeaponData, weaponId: any, unlockedZones: { string }?, money: any): (string, number)
	local def = WeaponLogic.definition(weaponId)
	if not def then
		return "InvalidRequest", 0
	end
	if data.Owned[weaponId] then
		return "AlreadyOwned", 0
	end
	local price = def.Price
	if price == nil then
		return "NotForSale", 0
	end
	if not WeaponLogic.meetsRequirement(weaponId, unlockedZones) then
		return "Locked", price
	end
	if not (isFinite(money) and money >= price) then
		return "InsufficientMoney", price
	end
	data.Owned[weaponId] = true
	data.Levels[weaponId] = 0
	return "Success", price
end

-- Regalar un arma (jefes). true si es nueva.
function WeaponLogic.grant(data: WeaponData, weaponId: string): boolean
	if not WeaponLogic.definition(weaponId) or data.Owned[weaponId] then
		return false
	end
	data.Owned[weaponId] = true
	data.Levels[weaponId] = 0
	return true
end

function WeaponLogic.equip(data: WeaponData, weaponId: any): string
	if not WeaponLogic.definition(weaponId) then
		return "InvalidRequest"
	end
	if not data.Owned[weaponId] then
		return "NotOwned"
	end
	local category = WeaponLogic.category(weaponId)
	if category == "Weapons" then
		data.Equipped = weaponId
	else
		data.Slots = data.Slots or {}
		data.Slots[category] = weaponId
	end
	return "Success"
end

-- Lo que lleva equipado el estilo `styleId` (Armas: el arma; Puños: los guantes; Magia: el
-- bastón). Siempre algo que tiene (si no, el inicial de su categoría).
function WeaponLogic.equippedFor(data: WeaponData, styleId: any): string
	if styleId == "Fists" or styleId == "Magic" then
		local id = data.Slots and data.Slots[styleId]
		if id and data.Owned[id] and WeaponLogic.category(id) == styleId then
			return id
		end
		local starter = WeaponLogic.starter(styleId)
		if WeaponLogic.definition(starter) then
			return starter
		end
	end
	return data.Equipped
end

-- Coste de subir del nivel `level` al siguiente (nil si ya está al máximo o no existe)
function WeaponLogic.upgradeCost(weaponId: string, level: number): number?
	local def = WeaponLogic.definition(weaponId)
	if not def or level >= WeaponConfig.MaxLevel then
		return nil
	end
	return math.floor(def.UpgradeCost * WeaponConfig.UpgradeGrowth ^ math.max(0, level))
end

-- Mejorar: "Success", "InvalidRequest", "NotOwned", "MaxLevel" o "InsufficientMoney", y el coste.
function WeaponLogic.upgrade(data: WeaponData, weaponId: any, money: any): (string, number)
	if not WeaponLogic.definition(weaponId) then
		return "InvalidRequest", 0
	end
	if not data.Owned[weaponId] then
		return "NotOwned", 0
	end
	local level = WeaponLogic.level(data, weaponId)
	local cost = WeaponLogic.upgradeCost(weaponId, level)
	if not cost then
		return "MaxLevel", 0
	end
	if not (isFinite(money) and money >= cost) then
		return "InsufficientMoney", cost
	end
	data.Levels[weaponId] = level + 1
	return "Success", cost
end

-- Combate -----------------------------------------------------------------------------

-- Segundos entre disparos con la mejora global de cadencia
function WeaponLogic.cooldown(weaponId: string, cadenceLevel: number?): number
	local def = WeaponLogic.definition(weaponId) or WeaponConfig.Weapons[WeaponConfig.StarterWeapon]
	local level = if isFinite(cadenceLevel) then math.max(0, cadenceLevel :: number) else 0
	local factor = math.max(WeaponConfig.MinCadenceFactor, 1 - WeaponConfig.CadencePerLevel * level)
	return def.Cooldown * factor
end

-- Daño de un disparo: base del arma · nivel · mascotas (CombatConfig.PetDamageShare de su
-- bonificación) · `bonus` (renacimiento y aventuras; uno no válido no cuenta).
function WeaponLogic.shotDamage(weaponId: string, level: number?, petMultiplier: number?, bonus: number?): number
	local def = WeaponLogic.definition(weaponId) or WeaponConfig.Weapons[WeaponConfig.StarterWeapon]
	local lvl = if isFinite(level) then math.clamp(math.floor(level :: number), 0, WeaponConfig.MaxLevel) else 0
	local pets = if isFinite(petMultiplier) then math.max(0, (petMultiplier :: number) - 1) * CombatConfig.PetDamageShare else 0
	local extra = if isFinite(bonus) and (bonus :: number) >= 0 then bonus :: number else 1
	return round2(def.Damage * (1 + WeaponConfig.LevelDamageBonus * lvl) * (1 + pets) * extra)
end

function WeaponLogic.dps(weaponId: string, level: number?, cadenceLevel: number?, petMultiplier: number?, bonus: number?): number
	return round2(WeaponLogic.shotDamage(weaponId, level, petMultiplier, bonus) / WeaponLogic.cooldown(weaponId, cadenceLevel))
end

-- "Poder" del jugador para lo que escala con su arma (habilidades, mascotas, núcleos): la
-- mitad de su daño por segundo (con el láser inicial, 10, como el antiguo golpe).
function WeaponLogic.power(weaponId: string, level: number?, cadenceLevel: number?, petMultiplier: number?, bonus: number?): number
	return round2(WeaponLogic.dps(weaponId, level, cadenceLevel, petMultiplier, bonus) * 0.5)
end

return WeaponLogic
