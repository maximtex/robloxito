-- Lógica pura de los artículos (pociones, huevos guardados y títulos). La usa el servidor
-- (ItemService, PlayerDataService, EnemyService, PetService, SaveService) y el cliente solo
-- para mostrar. Números en ItemConfig.
--
-- Datos guardados (PetData.Items):
--   Potions: { [potionId]: número }   pociones sin usar
--   Eggs: { [eggId]: número }         huevos sin abrir
--   Boosts: { [potionId]: número }    en memoria: os.time() en que se acaba la poción activa.
--                                     Al guardar se guardan los SEGUNDOS que le quedan, así
--                                     que el tiempo no corre mientras no se juega.
--   Titles: { [titleId]: true }       títulos conseguidos
--   Title: string                     título equipado ("" = ninguno)
--   TitleSet: boolean                 el jugador ya eligió (o quitó) un título a mano: los
--                                     nuevos ya no se equipan solos
--   PotionsUsed: número               pociones tomadas en total (título Alquimista)

local ItemConfig = require(script.Parent.Config.ItemConfig)

export type ItemData = {
	Potions: { [string]: number },
	Eggs: { [string]: number },
	Boosts: { [string]: number },
	Titles: { [string]: boolean },
	Title: string,
	TitleSet: boolean,
	PotionsUsed: number,
}

local MAX_ID_LENGTH = 64
local MAX_ENTRIES = 64

local ItemLogic = {}

function ItemLogic.empty(): ItemData
	return { Potions = {}, Eggs = {}, Boosts = {}, Titles = {}, Title = "", TitleSet = false, PotionsUsed = 0 }
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function cleanCounts(raw: any): { [string]: number }
	local result = {}
	if type(raw) ~= "table" then
		return result
	end
	local count = 0
	for id, amount in raw do
		if type(id) == "string" and #id > 0 and #id <= MAX_ID_LENGTH and isFiniteNumber(amount) and amount >= 1 and count < MAX_ENTRIES then
			result[id] = math.min(math.floor(amount), ItemConfig.MaxStack)
			count += 1
		end
	end
	return result
end

-- Datos guardados (o ausentes en partidas antiguas) -> estructura válida. `now` = os.time():
-- el tiempo que le quedaba a cada poción empieza a contar desde ahora.
function ItemLogic.sanitize(raw: any, now: number): ItemData
	local data = ItemLogic.empty()
	if type(raw) ~= "table" then
		return data
	end
	-- Se conservan también las pociones y huevos que ya no existan en la configuración (no se
	-- ven ni se pueden usar, pero vuelven si se recuperan).
	data.Potions = cleanCounts(raw.Potions)
	data.Eggs = cleanCounts(raw.Eggs)
	if type(raw.Boosts) == "table" then
		for id, seconds in raw.Boosts do
			if type(id) == "string" and ItemConfig.Potions[id] and isFiniteNumber(seconds) and seconds > 0 then
				data.Boosts[id] = now + math.min(math.floor(seconds), ItemConfig.MaxBoostSeconds)
			end
		end
	end
	if type(raw.Titles) == "table" then
		local count = 0
		for id, owned in raw.Titles do
			if type(id) == "string" and #id <= MAX_ID_LENGTH and owned == true and count < MAX_ENTRIES then
				data.Titles[id] = true
				count += 1
			end
		end
	end
	if type(raw.Title) == "string" and data.Titles[raw.Title] then
		data.Title = raw.Title
	end
	data.TitleSet = raw.TitleSet == true
	data.PotionsUsed = if isFiniteNumber(raw.PotionsUsed) and raw.PotionsUsed >= 0 then math.min(math.floor(raw.PotionsUsed), 1e9) else 0
	return data
end

-- Copia para guardar: las pociones activas como segundos que les quedan.
function ItemLogic.serialize(data: ItemData, now: number): any
	local boosts = {}
	for id, endsAt in data.Boosts do
		local left = math.floor(endsAt - now)
		if left > 0 then
			boosts[id] = left
		end
	end
	return {
		Potions = table.clone(data.Potions),
		Eggs = table.clone(data.Eggs),
		Boosts = boosts,
		Titles = table.clone(data.Titles),
		Title = data.Title,
		TitleSet = data.TitleSet,
		PotionsUsed = data.PotionsUsed,
	}
end

-- Artículos del perfil (nil si el perfil aún no los tiene).
function ItemLogic.ofProfile(profile: any): ItemData?
	local petData = type(profile) == "table" and profile.PetData
	local items = type(petData) == "table" and petData.Items
	return if type(items) == "table" then items else nil
end

-- Pociones --------------------------------------------------------------------------------

function ItemLogic.remaining(data: ItemData?, potionId: string, now: number): number
	local endsAt = data and data.Boosts[potionId]
	return if endsAt then math.max(0, endsAt - now) else 0
end

function ItemLogic.isActive(data: ItemData?, potionId: string, now: number): boolean
	return ItemLogic.remaining(data, potionId, now) > 0
end

-- Lo que multiplica la poción ahora (1 si no está activa).
function ItemLogic.multiplier(data: ItemData?, potionId: string, now: number): number
	if not ItemLogic.isActive(data, potionId, now) then
		return 1
	end
	local def = ItemConfig.Potions[potionId]
	return if def then def.Multiplier or 1 else 1
end

-- Suma pociones (botín). Devuelve cuántas se añadieron (tope MaxStack).
function ItemLogic.addPotion(data: ItemData, potionId: string, count: number): number
	if not ItemConfig.Potions[potionId] then
		return 0
	end
	local before = data.Potions[potionId] or 0
	local after = math.min(before + count, ItemConfig.MaxStack)
	data.Potions[potionId] = after
	return after - before
end

-- Toma una poción: la gasta y suma su tiempo al que le quede. Devuelve el código y los
-- segundos que quedan ahora.
function ItemLogic.usePotion(data: ItemData, potionId: string, now: number, codes: any): (string, number?)
	local def = ItemConfig.Potions[potionId]
	if not def then
		return codes.InvalidRequest, nil
	end
	if (data.Potions[potionId] or 0) < 1 then
		return codes.NotOwned, nil
	end
	local left = ItemLogic.remaining(data, potionId, now)
	if left + def.Seconds > ItemConfig.MaxBoostSeconds + 1 then
		return codes.Full, nil -- ya tiene el máximo acumulado
	end
	data.Potions[potionId] -= 1
	if data.Potions[potionId] <= 0 then
		data.Potions[potionId] = nil
	end
	local total = left + def.Seconds
	data.Boosts[potionId] = now + total
	data.PotionsUsed += 1
	return codes.Success, total
end

-- Quita las pociones que ya se acabaron. Devuelve sus ids (para avisar al jugador).
function ItemLogic.expire(data: ItemData, now: number): { string }
	local ended = {}
	for id, endsAt in data.Boosts do
		if endsAt <= now then
			table.insert(ended, id)
		end
	end
	for _, id in ended do
		data.Boosts[id] = nil
	end
	return ended
end

-- Huevos ----------------------------------------------------------------------------------

function ItemLogic.addEgg(data: ItemData, eggId: string, count: number): number
	local before = data.Eggs[eggId] or 0
	local after = math.min(before + count, ItemConfig.MaxStack)
	data.Eggs[eggId] = after
	return after - before
end

function ItemLogic.hasEgg(data: ItemData, eggId: string): boolean
	return (data.Eggs[eggId] or 0) >= 1
end

function ItemLogic.takeEgg(data: ItemData, eggId: string): boolean
	if not ItemLogic.hasEgg(data, eggId) then
		return false
	end
	data.Eggs[eggId] -= 1
	if data.Eggs[eggId] <= 0 then
		data.Eggs[eggId] = nil
	end
	return true
end

-- Botín de un jefe. `random()` devuelve un número en [0, 1). Huevo solo si existe (eggs =
-- EggConfig.Eggs).
function ItemLogic.rollBossDrop(typeId: string, random: () -> number, eggs: { [string]: any }): { Potions: { string }, Egg: string? }
	local def = ItemConfig.BossDrops[typeId] or ItemConfig.BossDrops.Default
	local order = ItemLogic.potionOrder()
	local drop = { Potions = {}, Egg = nil }
	for _ = 1, def.Potions or 0 do
		local index = math.clamp(math.floor(random() * #order) + 1, 1, #order)
		table.insert(drop.Potions, order[index])
	end
	if def.Egg and eggs[def.Egg] and random() < (def.EggChance or 0) then
		drop.Egg = def.Egg
	end
	return drop
end

-- Títulos ---------------------------------------------------------------------------------

export type Stats = {
	Kills: number,
	Rebirths: number,
	Pets: number,
	PotionsUsed: number,
	EnergyEarned: number,
	Bosses: { [string]: number },
}

-- Progreso hacia un título: (actual, meta). Los de jefe van de 0 a 1.
function ItemLogic.titleProgress(def: any, stats: Stats): (number, number)
	if def.Boss then
		return if (stats.Bosses[def.Boss] or 0) > 0 then 1 else 0, 1
	end
	if def.Stat then
		local value = stats[def.Stat]
		return if type(value) == "number" then value else 0, def.Goal or 1
	end
	return 1, 1
end

function ItemLogic.titleReached(def: any, stats: Stats): boolean
	local value, goal = ItemLogic.titleProgress(def, stats)
	return value >= goal
end

-- Concede los títulos cuyo requisito ya se cumple. Devuelve los nuevos. Si el jugador no ha
-- elegido nunca un título, se equipa solo el último conseguido.
function ItemLogic.grantTitles(data: ItemData, stats: Stats): { string }
	local fresh = {}
	for _, titleId in ItemLogic.titleOrder() do
		if not data.Titles[titleId] and ItemLogic.titleReached(ItemConfig.Titles[titleId], stats) then
			data.Titles[titleId] = true
			table.insert(fresh, titleId)
		end
	end
	if #fresh > 0 and not data.TitleSet then
		data.Title = fresh[#fresh]
	end
	return fresh
end

-- Equipa un título conseguido ("" lo quita). Devuelve el código.
function ItemLogic.equipTitle(data: ItemData, titleId: string, codes: any): string
	if titleId ~= "" and not (ItemConfig.Titles[titleId] and data.Titles[titleId]) then
		return codes.NotOwned
	end
	data.Title = titleId
	data.TitleSet = true
	return codes.Success
end

-- Orden de presentación -------------------------------------------------------------------

local function ordered(map: { [string]: any }): { string }
	local ids = {}
	for id in map do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local oa, ob = map[a].Order or 0, map[b].Order or 0
		if oa ~= ob then
			return oa < ob
		end
		return a < b
	end)
	return ids
end

local potionOrder = ordered(ItemConfig.Potions)
local titleOrder = ordered(ItemConfig.Titles)

function ItemLogic.potionOrder(): { string }
	return potionOrder
end

function ItemLogic.titleOrder(): { string }
	return titleOrder
end

return ItemLogic
