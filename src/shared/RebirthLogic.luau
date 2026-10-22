-- Lógica pura del renacimiento (sin APIs de Roblox). La usan el servidor (RebirthService,
-- SaveService, PlayerDataService y los servicios de combate y mascotas) para decidir y el
-- cliente (RebirthController) solo para mostrar. Números en RebirthConfig.
--
-- Datos de un jugador (campo "Rebirth" del registro guardado):
--   {
--     Count = 2,                       -- renacimientos hechos
--     Tokens = 1,                      -- fichas sin gastar
--     Shop = { Loot = 1, Strike = 2 }, -- nivel de cada ventaja de la tienda
--     BestLevel = 25,                  -- mayor nivel de Resonancia con el que se renació
--                                      -- (los huevos que desbloqueó siguen abiertos)
--     LastAt = 1760000000,             -- os.time() del último renacimiento (0 = nunca)
--   }
-- - Cualquier dato ausente o no válido (partidas antiguas, NaN, negativos, texto) se
--   normaliza a un valor seguro. Las ventajas de la tienda que ya no existan se conservan
--   tal cual (para no perderlas si vuelven).
-- - rebirth y buy modifican los datos y devuelven el resultado; quien los llame reinicia
--   la energía y la Resonancia en el mismo paso, sin pausas.

local RebirthConfig = require(script.Parent.Config.RebirthConfig)
local EconomyConfig = require(script.Parent.Config.EconomyConfig)

local RebirthLogic = {}

export type RebirthData = { Count: number, Tokens: number, Shop: { [string]: number }, BestLevel: number, LastAt: number }

local MAX_TOKENS = 1e9
local MAX_TIME = 1e10
local MAX_SHOP_ENTRIES = 50

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function cleanInteger(value: any, maxValue: number): number
	if not isFiniteNumber(value) or value <= 0 then
		return 0
	end
	return math.min(math.floor(value), maxValue)
end

local function maxUpgradeLevel(): number
	local definition = EconomyConfig.Upgrades[RebirthConfig.UpgradeId]
	return if definition then definition.MaxLevel else 0
end

function RebirthLogic.empty(): RebirthData
	return { Count = 0, Tokens = 0, Shop = {}, BestLevel = 0, LastAt = 0 }
end

-- Copia válida de unos datos guardados (o vacía si no hay o no son una tabla).
function RebirthLogic.sanitize(raw: any): RebirthData
	local data = RebirthLogic.empty()
	if type(raw) ~= "table" then
		return data
	end
	data.Count = cleanInteger(raw.Count, RebirthConfig.MaxRebirths)
	data.Tokens = cleanInteger(raw.Tokens, MAX_TOKENS)
	data.BestLevel = cleanInteger(raw.BestLevel, maxUpgradeLevel())
	data.LastAt = cleanInteger(raw.LastAt, MAX_TIME)
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

-- Nivel de Resonancia que pide el siguiente renacimiento tras `count` renacimientos.
function RebirthLogic.requiredLevel(count: any): number
	local done = cleanInteger(count, RebirthConfig.MaxRebirths)
	local requirement = RebirthConfig.Requirement
	return math.min(maxUpgradeLevel(), requirement.BaseLevel + requirement.LevelStep * done)
end

-- Fichas que da el renacimiento que viene después de `count` renacimientos.
function RebirthLogic.tokensFor(count: any): number
	local done = cleanInteger(count, RebirthConfig.MaxRebirths)
	return RebirthConfig.Tokens.Base + RebirthConfig.Tokens.PerRebirth * done
end

-- Multiplicador de energía (producción, offline y botín) con `count` renacimientos.
function RebirthLogic.energyMultiplierAt(count: any): number
	return 1 + RebirthConfig.EnergyBonus * cleanInteger(count, RebirthConfig.MaxRebirths)
end

function RebirthLogic.energyMultiplier(data: any): number
	return RebirthLogic.energyMultiplierAt(RebirthLogic.count(data))
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

-- Botín de enemigos: multiplicador de energía · "Botín abundante".
function RebirthLogic.lootMultiplier(data: any): number
	local loot = RebirthConfig.Shop.Loot
	local perLevel = if loot then loot.PerLevel else 0
	return RebirthLogic.energyMultiplier(data) * (1 + perLevel * RebirthLogic.shopLevel(data, "Loot"))
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

-- Segundos extra de producción offline ("Sueño profundo").
function RebirthLogic.offlineBonusSeconds(data: any): number
	local dreams = RebirthConfig.Shop.Dreams
	return if dreams then dreams.PerLevel * RebirthLogic.shopLevel(data, "Dreams") else 0
end

-- Nivel de Resonancia con el que empieza cada renacimiento ("Inicio rápido"); nunca
-- llega al requisito del siguiente.
function RebirthLogic.headStartLevel(data: any, nextRequired: number?): number
	local head = RebirthConfig.Shop.HeadStart
	local level = if head then head.PerLevel * RebirthLogic.shopLevel(data, "HeadStart") else 0
	local cap = (nextRequired or RebirthLogic.requiredLevel(RebirthLogic.count(data))) - 1
	return math.clamp(level, 0, math.max(0, cap))
end

-- Nivel que cuenta para desbloquear huevos: el actual o el mejor con el que se renació.
function RebirthLogic.unlockLevel(data: any, currentLevel: any): number
	local best = if type(data) == "table" then cleanInteger(data.BestLevel, maxUpgradeLevel()) else 0
	return math.max(cleanInteger(currentLevel, maxUpgradeLevel()), best)
end

function RebirthLogic.canRebirth(data: any, currentLevel: any): boolean
	local count = RebirthLogic.count(data)
	return count < RebirthConfig.MaxRebirths and cleanInteger(currentLevel, maxUpgradeLevel()) >= RebirthLogic.requiredLevel(count)
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

-- Renacer. Devuelve (código, resultado). Códigos: Success, InvalidRequest (datos no
-- válidos), MaxLevel (tope de renacimientos), LevelTooLow. Con Success, el resultado es
-- { Count, Tokens (ganadas), Level (nivel de Resonancia con el que se empieza) } y quien
-- llama debe poner la energía a cero y la Resonancia a Level en el mismo paso.
function RebirthLogic.rebirth(data: any, currentLevel: any, now: any): (string, any)
	if type(data) ~= "table" then
		return "InvalidRequest", nil
	end
	local count = RebirthLogic.count(data)
	if count >= RebirthConfig.MaxRebirths then
		return "MaxLevel", nil
	end
	local level = cleanInteger(currentLevel, maxUpgradeLevel())
	if level < RebirthLogic.requiredLevel(count) then
		return "LevelTooLow", nil
	end
	local tokens = RebirthLogic.tokensFor(count)
	data.Count = count + 1
	data.Tokens = math.min(MAX_TOKENS, cleanInteger(data.Tokens, MAX_TOKENS) + tokens)
	data.BestLevel = math.max(cleanInteger(data.BestLevel, maxUpgradeLevel()), level)
	data.LastAt = cleanInteger(now, MAX_TIME)
	if type(data.Shop) ~= "table" then
		data.Shop = {}
	end
	local startLevel = RebirthLogic.headStartLevel(data, RebirthLogic.requiredLevel(data.Count))
	return "Success", { Count = data.Count, Tokens = tokens, Level = startLevel }
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
	if not EconomyConfig.Upgrades[RebirthConfig.UpgradeId] then
		table.insert(problems, "UpgradeId no existe en EconomyConfig.Upgrades")
	end
	local requirement = RebirthConfig.Requirement
	if not (isFiniteNumber(requirement.BaseLevel) and requirement.BaseLevel >= 1 and isFiniteNumber(requirement.LevelStep) and requirement.LevelStep >= 0) then
		table.insert(problems, "Requirement no válido")
	end
	if not (isFiniteNumber(RebirthConfig.EnergyBonus) and RebirthConfig.EnergyBonus > 0) then
		table.insert(problems, "EnergyBonus debe ser > 0")
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
