-- Lógica pura del renacimiento (sin APIs de Roblox). La usan el servidor (RebirthService,
-- SaveService, PlayerDataService y los servicios de combate y mascotas) para decidir y el
-- cliente (RebirthController) solo para mostrar. Números en RebirthConfig.
--
-- Datos de un jugador (campo "Rebirth" del registro guardado):
--   {
--     Count = 2,                       -- renacimientos hechos
--     Tokens = 1,                      -- fichas sin gastar
--     Shop = { Loot = 1, Strike = 2 }, -- nivel de cada ventaja de la tienda
--     LastAt = 1760000000,             -- os.time() del último renacimiento (0 = nunca)
--     Cycle = { Forest = 10 },         -- oleada más alta superada en cada modo DESDE el
--                                      -- último renacimiento (se vacía al renacer)
--   }
-- - Cualquier dato ausente o no válido (partidas antiguas, NaN, negativos, texto) se
--   normaliza a un valor seguro. Las ventajas de la tienda que ya no existan se conservan
--   tal cual (para no perderlas si vuelven).
-- - rebirth y buy modifican los datos y devuelven el resultado; quien los llame reinicia
--   el dinero y las armas en el mismo paso, sin pausas.

local RebirthConfig = require(script.Parent.Config.RebirthConfig)
local WaveConfig = require(script.Parent.Config.WaveConfig)

local RebirthLogic = {}

export type RebirthData = { Count: number, Tokens: number, Shop: { [string]: number }, LastAt: number, Cycle: { [string]: number } }
export type Requirement = { ArenaId: string, Wave: number, Money: number }
export type Progress = { ArenaId: string, Wave: number, BestWave: number, WavesDone: boolean, Money: number, Have: number, MoneyDone: boolean }

local MAX_TOKENS = 1e9
local MAX_TIME = 1e10
local MAX_SHOP_ENTRIES = 50
local MAX_CYCLE_ENTRIES = 20
local MAX_WAVE = 1e6

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function cleanInteger(value: any, maxValue: number): number
	if not isFiniteNumber(value) or value <= 0 then
		return 0
	end
	return math.min(math.floor(value), maxValue)
end

function RebirthLogic.empty(): RebirthData
	return { Count = 0, Tokens = 0, Shop = {}, LastAt = 0, Cycle = {} }
end

-- Copia válida de unos datos guardados (o vacía si no hay o no son una tabla).
function RebirthLogic.sanitize(raw: any): RebirthData
	local data = RebirthLogic.empty()
	if type(raw) ~= "table" then
		return data
	end
	data.Count = cleanInteger(raw.Count, RebirthConfig.MaxRebirths)
	data.Tokens = cleanInteger(raw.Tokens, MAX_TOKENS)
	data.LastAt = cleanInteger(raw.LastAt, MAX_TIME)
	if type(raw.Cycle) == "table" then
		local entries = 0
		for arenaId, wave in raw.Cycle do
			if type(arenaId) == "string" and #arenaId <= 64 and entries < MAX_CYCLE_ENTRIES then
				local clean = cleanInteger(wave, MAX_WAVE)
				if clean > 0 then
					data.Cycle[arenaId] = clean
					entries += 1
				end
			end
		end
	end
	if type(raw.Shop) == "table" then
		local entries = 0
		for itemId, level in raw.Shop do
			if type(itemId) == "string" and #itemId <= 64 and entries < MAX_SHOP_ENTRIES then
				local item = RebirthConfig.Shop[itemId]
				local clean = cleanInteger(level, if item then #item.Costs else 1000)
				if clean > 0 then
					data.Shop[itemId] = clean
					entries += 1
				end
			end
		end
	end
	return data
end

-- Copia para guardar (siempre válida).
function RebirthLogic.serialize(data: any): RebirthData
	return RebirthLogic.sanitize(data)
end

-- Datos de renacimiento de un perfil del servidor (o nil si no tiene).
function RebirthLogic.ofProfile(profile: any): RebirthData?
	local petData = if type(profile) == "table" then profile.PetData else nil
	local data = if type(petData) == "table" then petData.Rebirth else nil
	return if type(data) == "table" then data else nil
end

function RebirthLogic.count(data: any): number
	return if type(data) == "table" then cleanInteger(data.Count, RebirthConfig.MaxRebirths) else 0
end

function RebirthLogic.shopLevel(data: any, itemId: string): number
	local item = RebirthConfig.Shop[itemId]
	if not item or type(data) ~= "table" or type(data.Shop) ~= "table" then
		return 0
	end
	return cleanInteger(data.Shop[itemId], #item.Costs)
end

-- Requisito y premio ------------------------------------------------------------------------

-- Oleadas de un modo (las de hordas y la del jefe), como WaveLogic.waveCount.
local function waveCount(arenaId: string): number
	local arena = WaveConfig.Arenas[arenaId]
	if not arena then
		return 0
	end
	return #arena.Waves + (if arena.Boss then 1 else 0)
end

-- Lo que pide el renacimiento que viene tras `count` renacimientos: { ArenaId, Wave, Money }.
function RebirthLogic.requirement(count: any): Requirement
	local done = cleanInteger(count, RebirthConfig.MaxRebirths)
	local settings = RebirthConfig.Requirement
	local list = settings.Waves
	local index = done + 1
	local arenaId = list[math.min(index, #list)]
	local wave = waveCount(arenaId)
	if index > #list then
		wave += settings.EndlessExtraWaves * (index - #list)
	end
	local money = math.floor(settings.MoneyBase * settings.MoneyGrowth ^ done)
	return { ArenaId = arenaId, Wave = wave, Money = money }
end

-- Oleada más alta superada en un modo desde el último renacimiento.
function RebirthLogic.cycleWave(data: any, arenaId: string): number
	local cycle = if type(data) == "table" and type(data.Cycle) == "table" then data.Cycle else nil
	return if cycle then cleanInteger(cycle[arenaId], MAX_WAVE) else 0
end

-- Anota una oleada superada en `arenaId` (WaveService). true si sube el máximo del ciclo.
function RebirthLogic.recordWave(data: any, arenaId: any, wave: any): boolean
	if type(data) ~= "table" or type(arenaId) ~= "string" or not WaveConfig.Arenas[arenaId] then
		return false
	end
	local clean = cleanInteger(wave, MAX_WAVE)
	if clean <= RebirthLogic.cycleWave(data, arenaId) then
		return false
	end
	if type(data.Cycle) ~= "table" then
		data.Cycle = {}
	end
	data.Cycle[arenaId] = clean
	return true
end

-- Cómo va el requisito con `money` 💰.
function RebirthLogic.progress(data: any, money: any): Progress
	local need = RebirthLogic.requirement(RebirthLogic.count(data))
	local best = RebirthLogic.cycleWave(data, need.ArenaId)
	local have = if isFiniteNumber(money) and money > 0 then money else 0
	return {
		ArenaId = need.ArenaId,
		Wave = need.Wave,
		BestWave = best,
		WavesDone = best >= need.Wave,
		Money = need.Money,
		Have = have,
		MoneyDone = have >= need.Money,
	}
end

-- Texto para replicar el ciclo al cliente ("Forest=10,CrystalValley=3") y su lectura.
function RebirthLogic.cycleText(data: any): string
	local parts = {}
	local cycle = if type(data) == "table" and type(data.Cycle) == "table" then data.Cycle else {}
	for arenaId, wave in cycle do
		if type(arenaId) == "string" and WaveConfig.Arenas[arenaId] then
			table.insert(parts, arenaId .. "=" .. cleanInteger(wave, MAX_WAVE))
		end
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

function RebirthLogic.parseCycle(text: any): { [string]: number }
	local cycle = {}
	if type(text) ~= "string" then
		return cycle
	end
	for arenaId, wave in text:gmatch("(%w+)=(%d+)") do
		if WaveConfig.Arenas[arenaId] then
			cycle[arenaId] = math.min(tonumber(wave) or 0, MAX_WAVE)
		end
	end
	return cycle
end

-- Fichas que da el renacimiento que viene después de `count` renacimientos.
function RebirthLogic.tokensFor(count: any): number
	local done = cleanInteger(count, RebirthConfig.MaxRebirths)
	return RebirthConfig.Tokens.Base + RebirthConfig.Tokens.PerRebirth * done
end

-- Multiplicador del botín en 💰 por los renacimientos (`count`), sin la tienda.
function RebirthLogic.lootBonusAt(count: any): number
	return 1 + RebirthConfig.LootBonus * cleanInteger(count, RebirthConfig.MaxRebirths)
end

-- Daño: renacimientos y "Golpe renacido" (se multiplican entre sí).
function RebirthLogic.damageMultiplierAt(count: any, strikeLevel: any): number
	local strike = RebirthConfig.Shop.Strike
	local perLevel = if strike then strike.PerLevel else 0
	return (1 + RebirthConfig.DamageBonus * cleanInteger(count, RebirthConfig.MaxRebirths)) * (1 + perLevel * cleanInteger(strikeLevel, 1000))
end

function RebirthLogic.damageMultiplier(data: any): number
	return RebirthLogic.damageMultiplierAt(RebirthLogic.count(data), RebirthLogic.shopLevel(data, "Strike"))
end

-- Botín (💰) de los enemigos: renacimientos · "Botín abundante".
function RebirthLogic.lootMultiplier(data: any): number
	local loot = RebirthConfig.Shop.Loot
	local perLevel = if loot then loot.PerLevel else 0
	return RebirthLogic.lootBonusAt(RebirthLogic.count(data)) * (1 + perLevel * RebirthLogic.shopLevel(data, "Loot"))
end

-- Mascotas equipadas a la vez: las de base + "Espacio de mascota".
function RebirthLogic.maxEquipped(data: any, base: number): number
	local slot = RebirthConfig.Shop.PetSlot
	return base + (if slot then slot.PerLevel * RebirthLogic.shopLevel(data, "PetSlot") else 0)
end

-- Tope absoluto de mascotas equipadas (para el cliente al dibujar las de otros).
function RebirthLogic.maxEquippedCap(base: number): number
	local slot = RebirthConfig.Shop.PetSlot
	return base + (if slot then slot.PerLevel * #slot.Costs else 0)
end

-- ¿Se puede renacer con `money` 💰? Hacen falta las oleadas del ciclo y el 💰 (y que no
-- esté bloqueado: RebirthConfig.Enabled).
function RebirthLogic.canRebirth(data: any, money: any): boolean
	if RebirthConfig.Enabled ~= true or RebirthLogic.count(data) >= RebirthConfig.MaxRebirths then
		return false
	end
	local progress = RebirthLogic.progress(data, money)
	return progress.WavesDone and progress.MoneyDone
end

-- Tienda ------------------------------------------------------------------------------------

-- Coste en fichas del siguiente nivel de una ventaja (nil si no existe o está al máximo).
function RebirthLogic.shopCost(itemId: any, currentLevel: any): number?
	local item = if type(itemId) == "string" then RebirthConfig.Shop[itemId] else nil
	if not item then
		return nil
	end
	local level = cleanInteger(currentLevel, #item.Costs)
	return item.Costs[level + 1]
end

-- Ventajas en el orden de la tienda: { { Id, Item } }.
function RebirthLogic.shopOrder(): { { Id: string, Item: any } }
	local list = {}
	for id, item in RebirthConfig.Shop do
		table.insert(list, { Id = id, Item = item })
	end
	table.sort(list, function(a, b)
		return a.Item.Order < b.Item.Order
	end)
	return list
end

-- Acciones (modifican los datos) ---------------------------------------------------------------

-- Renacer con `money` 💰. Devuelve (código, resultado). Códigos: Success, InvalidRequest
-- (datos no válidos), ComingSoon (RebirthConfig.Enabled = false), MaxLevel (tope de
-- renacimientos), WavesNotDone (faltan las oleadas del ciclo; resultado = el progreso) e
-- InsufficientMoney (falta 💰; resultado = el progreso). Con Success, el resultado es
-- { Count, Tokens (ganadas), Paid (💰 del requisito) }, el ciclo queda vacío y quien llama
-- debe reiniciar el dinero y las armas en el mismo paso.
function RebirthLogic.rebirth(data: any, money: any, now: any): (string, any)
	if type(data) ~= "table" then
		return "InvalidRequest", nil
	end
	if RebirthConfig.Enabled ~= true then
		return "ComingSoon", nil
	end
	local count = RebirthLogic.count(data)
	if count >= RebirthConfig.MaxRebirths then
		return "MaxLevel", nil
	end
	local progress = RebirthLogic.progress(data, money)
	if not progress.WavesDone then
		return "WavesNotDone", progress
	end
	if not progress.MoneyDone then
		return "InsufficientMoney", progress
	end
	local tokens = RebirthLogic.tokensFor(count)
	data.Count = count + 1
	data.Cycle = {}
	data.Tokens = math.min(MAX_TOKENS, cleanInteger(data.Tokens, MAX_TOKENS) + tokens)
	data.LastAt = cleanInteger(now, MAX_TIME)
	if type(data.Shop) ~= "table" then
		data.Shop = {}
	end
	return "Success", { Count = data.Count, Tokens = tokens, Paid = progress.Money }
end

-- Comprar el siguiente nivel de una ventaja. Devuelve (código, coste). Códigos: Success,
-- InvalidRequest, MaxLevel, InsufficientTokens. Cualquier rechazo deja los datos igual.
function RebirthLogic.buy(data: any, itemId: any): (string, number)
	if type(data) ~= "table" or type(itemId) ~= "string" or not RebirthConfig.Shop[itemId] then
		return "InvalidRequest", 0
	end
	local level = RebirthLogic.shopLevel(data, itemId)
	local cost = RebirthLogic.shopCost(itemId, level)
	if not cost then
		return "MaxLevel", 0
	end
	local tokens = cleanInteger(data.Tokens, MAX_TOKENS)
	if tokens < cost then
		return "InsufficientTokens", cost
	end
	if type(data.Shop) ~= "table" then
		data.Shop = {}
	end
	data.Tokens = tokens - cost
	data.Shop[itemId] = level + 1
	return "Success", cost
end

-- Texto para replicar los niveles de la tienda al cliente ("Loot=1,Strike=2") y su lectura.
function RebirthLogic.shopText(data: any): string
	local parts = {}
	for _, entry in RebirthLogic.shopOrder() do
		local level = RebirthLogic.shopLevel(data, entry.Id)
		if level > 0 then
			table.insert(parts, entry.Id .. "=" .. level)
		end
	end
	return table.concat(parts, ",")
end

function RebirthLogic.parseShop(text: any): { [string]: number }
	local shop = {}
	if type(text) ~= "string" then
		return shop
	end
	for itemId, level in text:gmatch("(%w+)=(%d+)") do
		local item = RebirthConfig.Shop[itemId]
		if item then
			shop[itemId] = math.min(tonumber(level) or 0, #item.Costs)
		end
	end
	return shop
end

-- Presentación ------------------------------------------------------------------------------

local NUMERALS = { { 1000, "M" }, { 900, "CM" }, { 500, "D" }, { 400, "CD" }, { 100, "C" }, { 90, "XC" }, { 50, "L" }, { 40, "XL" }, { 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" } }

-- Número romano (1..3999); fuera de ese rango, el número tal cual.
function RebirthLogic.numeral(value: number): string
	local n = math.floor(value)
	if n < 1 or n > 3999 then
		return tostring(n)
	end
	local parts = {}
	for _, pair in NUMERALS do
		while n >= pair[1] do
			table.insert(parts, pair[2])
			n -= pair[1]
		end
	end
	return table.concat(parts)
end

-- Índice del color del aura (RebirthConfig.HaloTiers) para un número de renacimientos.
function RebirthLogic.haloTier(count: number): number
	local tier = 0
	for index, threshold in RebirthConfig.HaloTiers do
		if count >= threshold then
			tier = index
		end
	end
	return tier
end

-- Comprobación de la configuración (la llama el servidor al arrancar y las pruebas).
function RebirthLogic.validateConfig(): (boolean, { string })
	local problems = {}
	if not (isFiniteNumber(RebirthConfig.LootBonus) and RebirthConfig.LootBonus > 0) then
		table.insert(problems, "LootBonus debe ser > 0")
	end
	local requirement = RebirthConfig.Requirement
	if type(requirement) ~= "table" or type(requirement.Waves) ~= "table" or #requirement.Waves == 0 then
		table.insert(problems, "Requirement.Waves debe ser una lista de modos")
	else
		for index, arenaId in requirement.Waves do
			local arena = WaveConfig.Arenas[arenaId]
			if not arena or not arena.Boss or arena.Tutorial then
				table.insert(problems, ("Requirement.Waves[%d]: %s no es un modo con jefe"):format(index, tostring(arenaId)))
			end
		end
		if not (isFiniteNumber(requirement.EndlessExtraWaves) and requirement.EndlessExtraWaves >= 1) then
			table.insert(problems, "Requirement.EndlessExtraWaves debe ser >= 1")
		end
		if not (isFiniteNumber(requirement.MoneyBase) and requirement.MoneyBase >= 0 and isFiniteNumber(requirement.MoneyGrowth) and requirement.MoneyGrowth >= 1) then
			table.insert(problems, "Requirement: MoneyBase >= 0 y MoneyGrowth >= 1")
		end
	end
	local orders = {}
	for id, item in RebirthConfig.Shop do
		if type(item.Costs) ~= "table" or #item.Costs == 0 then
			table.insert(problems, id .. ": sin costes")
		else
			for index, cost in item.Costs do
				if not (isFiniteNumber(cost) and cost >= 1 and cost == math.floor(cost)) then
					table.insert(problems, ("%s: coste %d no válido"):format(id, index))
				end
			end
		end
		if orders[item.Order] then
			table.insert(problems, id .. ": orden repetido")
		end
		orders[item.Order] = true
	end
	return #problems == 0, problems
end

return RebirthLogic
