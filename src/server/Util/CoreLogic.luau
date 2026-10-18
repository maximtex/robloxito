-- Lógica pura de los ocho núcleos elementales (sin APIs de Roblox), para probarla fuera
-- de Studio. FASE 1: no está conectada a ningún servicio todavía.
--
-- Datos de un jugador (futuro campo "Cores" del registro guardado):
--   {
--     Selected = "Nature",          -- elemento activo (siempre uno desbloqueado)
--     LastSwitchAt = 0,             -- os.time() del servidor del último cambio
--     Elements = {
--       Nature = { Unlocked = true, Mastery = 0 },                     -- SIN Level
--       Water  = { Unlocked = false, Level = 0, Mastery = 0, UnlockedAt = 0 },
--       ...
--     },
--   }
-- - El nivel de Naturaleza es UpgradeLevels.GeneratorPower (no se duplica aquí); su
--   producción y su coste salen de Economy, igual que hoy.
-- - sanitize conserva los campos y elementos que no conoce (copiados, no compartidos).
-- - unlock y selectElement modifican los datos y DEVUELVEN el coste: quien los llame
--   (el servicio de una fase futura) debe restar esa energía en el mismo paso, sin pausas.
-- - offlineReward solo calcula: no concede nada.
-- - El multiplicador de mascotas se aplica UNA vez, sobre la suma de producciones base;
--   switchCost y offlineReward calculan la producción desde los datos (nunca la reciben).
-- - Cualquier número no válido (NaN, infinito, negativo, texto) se normaliza a un valor
--   seguro; los campos desconocidos solo se conservan si son datos válidos y guardables.

local CoreLogic = {}

local Config: any
local Economy: any
local EconomyConfig: any

export type ElementData = { Unlocked: boolean, Level: number?, Mastery: number, UnlockedAt: number? }
export type CoreData = { Selected: string, LastSwitchAt: number, Elements: { [string]: any } }

-- Campos que sanitize interpreta; cualquier otro se conserva tal cual.
local KNOWN_TOP = { Selected = true, LastSwitchAt = true, Elements = true }
local KNOWN_ELEMENT = { Unlocked = true, Level = true, Mastery = true, UnlockedAt = true }
local MAX_TIME = 1e10 -- os.time() razonable (año ~2286)
local MAX_EXACT = 2 ^ 53 -- mayor entero exacto en un número de Luau

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Copia profunda que solo conserva datos VÁLIDOS y guardables: textos, booleanos,
-- números finitos y tablas con claves válidas. Descarta NaN, infinitos, funciones,
-- instancias y anidamientos anómalos (devuelve nil para ellos).
local function deepCopy(value: any, depth: number?): any
	local kind = type(value)
	if kind == "string" or kind == "boolean" then
		return value
	elseif kind == "number" then
		return if isFiniteNumber(value) then value else nil
	elseif kind ~= "table" then
		return nil
	end
	local level = depth or 0
	if level > 20 then
		return nil -- datos anómalos muy anidados: no se copian
	end
	local out = {}
	for key, item in value do
		local cleanKey = if type(key) == "string" then key elseif isFiniteNumber(key) then key else nil
		local cleanItem = deepCopy(item, level + 1)
		if cleanKey ~= nil and cleanItem ~= nil then
			out[cleanKey] = cleanItem
		end
	end
	return out
end

-- Validación de la configuración -------------------------------------------------------

-- Devuelve (true, {}) o (false, { errores... }). No lanza errores.
function CoreLogic.validateConfig(config: any, economyConfig: any): (boolean, { string })
	local errors = {}
	local function fail(message: string)
		table.insert(errors, message)
	end
	if type(config) ~= "table" then
		return false, { "la configuración no es una tabla" }
	end
	local order = config.Order
	if type(order) ~= "table" or #order ~= 8 then
		fail("Order debe tener exactamente 8 elementos")
		order = {}
	end
	local seen = {}
	for index, id in order do
		if type(id) ~= "string" or id == "" then
			fail(("Order[%d] no es un identificador válido"):format(index))
		elseif seen[id] then
			fail("elemento repetido en Order: " .. id)
		else
			seen[id] = true
			if type(config.Elements) ~= "table" or type(config.Elements[id]) ~= "table" then
				fail("falta Elements." .. id)
			end
		end
	end
	if type(config.Elements) == "table" then
		for id in config.Elements do
			if not seen[id] then
				fail("Elements." .. tostring(id) .. " no está en Order")
			end
		end
	end
	if config.DefaultElement ~= order[1] then
		fail("DefaultElement debe ser el primer elemento de Order")
	end
	local default = type(config.Elements) == "table" and config.Elements[config.DefaultElement]
	local upgradeId = type(default) == "table" and default.UpgradeId
	if type(upgradeId) ~= "string" then
		fail("el elemento por defecto debe indicar su UpgradeId (el nivel existente)")
	elseif type(economyConfig) == "table" and not (type(economyConfig.Upgrades) == "table" and economyConfig.Upgrades[upgradeId]) then
		fail("UpgradeId no existe en EconomyConfig.Upgrades: " .. upgradeId)
	end

	local function positive(section: any, key: string, minimum: number, strict: boolean)
		local value = type(section) == "table" and section[key]
		if not isFiniteNumber(value) or (strict and value <= minimum) or (not strict and value < minimum) then
			fail(("%s debe ser un número %s %s"):format(key, if strict then ">" else ">=", tostring(minimum)))
		end
	end
	positive(config.Unlock, "BaseCost", 0, true)
	positive(config.Unlock, "Growth", 1, true) -- costes estrictamente crecientes
	if type(config.Unlock) == "table" and type(config.Unlock.Sequential) ~= "boolean" then
		fail("Unlock.Sequential debe ser booleano")
	end
	positive(config.Upgrade, "BaseProduction", 0, true)
	positive(config.Upgrade, "BaseUpgradeCost", 0, true)
	positive(config.Upgrade, "CostGrowth", 1, true)
	positive(config.Upgrade, "TierMultiplier", 1, false)
	local maxLevel = type(config.Upgrade) == "table" and config.Upgrade.MaxLevel
	if not (isFiniteNumber(maxLevel) and maxLevel >= 1 and maxLevel == math.floor(maxLevel)) then
		fail("Upgrade.MaxLevel debe ser un entero >= 1")
	end
	positive(config.Switch, "MinCost", 0, false)
	positive(config.Switch, "ProductionSeconds", 0, false)
	positive(config.Switch, "CooldownSeconds", 0, false)
	positive(config.Offline, "CapSeconds", 0, true)
	local efficiency = type(config.Offline) == "table" and config.Offline.Efficiency
	if not (isFiniteNumber(efficiency) and efficiency >= 0 and efficiency <= 1) then
		fail("Offline.Efficiency debe estar entre 0 y 1")
	end
	if type(config.Offline) == "table" and type(config.Offline.IncludePetMultiplier) ~= "boolean" then
		fail("Offline.IncludePetMultiplier debe ser booleano")
	end
	positive(config, "MaxMastery", 0, true)
	positive(config, "MaxPetMultiplier", 1, false)

	-- Los valores extremos que produce la configuración deben ser enteros exactos
	-- (< 2^53): ni infinitos ni tan grandes que pierdan precisión al sumar energía.
	if #errors == 0 then
		local count = #order
		local unlock, upgrade, offline = config.Unlock, config.Upgrade, config.Offline
		local naturePerLevel = type(economyConfig) == "table" and economyConfig.Upgrades[upgradeId] or nil
		local natureMax = if type(naturePerLevel) == "table" and type(economyConfig.BaseProductionPerSecond) == "number"
			then economyConfig.BaseProductionPerSecond + (naturePerLevel.ProductionPerLevel or 0) * (naturePerLevel.MaxLevel or 0)
			else 0
		local productionMax = natureMax
		for index = 2, count do
			productionMax += upgrade.BaseProduction * upgrade.TierMultiplier ^ (index - 1) * (1 + upgrade.MaxLevel)
		end
		local extremes = {
			{ "coste de desbloqueo máximo", unlock.BaseCost * unlock.Growth ^ (count - 2) },
			{ "coste de mejora máximo", upgrade.BaseUpgradeCost * upgrade.TierMultiplier ^ (count - 1) * upgrade.CostGrowth ^ (upgrade.MaxLevel - 1) },
			{ "producción máxima con mascotas", productionMax * config.MaxPetMultiplier },
			{ "recompensa offline máxima", offline.CapSeconds * productionMax * config.MaxPetMultiplier * offline.Efficiency },
		}
		for _, extreme in extremes do
			if not (isFiniteNumber(extreme[2]) and extreme[2] < MAX_EXACT) then
				fail(("%s demasiado grande (%s): la configuración produciría valores no representables"):format(extreme[1], tostring(extreme[2])))
			end
		end
	end
	return #errors == 0, errors
end

-- Dependencias (inyectadas para poder probarla fuera de Roblox). Una configuración no
-- válida detiene el arranque con un mensaje claro en lugar de producir valores raros.
function CoreLogic.init(coreConfig: any, economy: any, economyConfig: any)
	local ok, errors = CoreLogic.validateConfig(coreConfig, economyConfig)
	if not ok then
		error("[CoreLogic] Configuración de núcleos no válida: " .. table.concat(errors, "; "))
	end
	Config = coreConfig
	Economy = economy
	EconomyConfig = economyConfig
	CoreLogic.Order = coreConfig.Order
end

-- Consultas básicas --------------------------------------------------------------------

function CoreLogic.indexOf(elementId: any): number?
	if type(elementId) ~= "string" then
		return nil
	end
	return table.find(Config.Order, elementId)
end

function CoreLogic.isDefault(elementId: string): boolean
	return elementId == Config.DefaultElement
end

local function defaultUpgradeId(): string
	return Config.Elements[Config.DefaultElement].UpgradeId
end

-- Datos ---------------------------------------------------------------------------------

function CoreLogic.empty(): CoreData
	local elements = {}
	for _, id in Config.Order do
		if CoreLogic.isDefault(id) then
			elements[id] = { Unlocked = true, Mastery = 0 }
		else
			elements[id] = { Unlocked = false, Level = 0, Mastery = 0, UnlockedAt = 0 }
		end
	end
	return { Selected = Config.DefaultElement, LastSwitchAt = 0, Elements = elements }
end

local function cleanTime(value: any): number
	if isFiniteNumber(value) and value >= 0 and value <= MAX_TIME then
		return math.floor(value)
	end
	return 0
end

-- Datos guardados (o ausentes en partidas antiguas) -> estructura válida, conservando lo
-- desconocido. Nunca devuelve la misma tabla que recibe.
function CoreLogic.sanitize(raw: any): CoreData
	local data = CoreLogic.empty()
	if type(raw) ~= "table" then
		return data
	end
	-- Campos desconocidos del nivel superior
	for key, value in raw do
		if not KNOWN_TOP[key] then
			(data :: any)[key] = deepCopy(value)
		end
	end
	data.LastSwitchAt = cleanTime(raw.LastSwitchAt)

	local rawElements = if type(raw.Elements) == "table" then raw.Elements else {}
	for key, value in rawElements do
		if not CoreLogic.indexOf(key) then
			data.Elements[key] = deepCopy(value) -- elemento desconocido: se conserva sin usarlo
		end
	end
	for _, id in Config.Order do
		local entry = rawElements[id]
		local clean = data.Elements[id]
		if type(entry) == "table" then
			for key, value in entry do
				if not KNOWN_ELEMENT[key] then
					clean[key] = deepCopy(value)
				end
			end
			if isFiniteNumber(entry.Mastery) and entry.Mastery >= 0 then
				clean.Mastery = math.min(entry.Mastery, Config.MaxMastery)
			end
			if CoreLogic.isDefault(id) then
				-- Naturaleza siempre desbloqueada. Su nivel vive en UpgradeLevels; un
				-- "Level" aquí se trata como campo desconocido (se conserva, no se usa).
				clean.Unlocked = true
				if entry.Level ~= nil then
					clean.Level = deepCopy(entry.Level)
				end
			else
				clean.Unlocked = entry.Unlocked == true
				if isFiniteNumber(entry.Level) then
					clean.Level = math.clamp(math.floor(entry.Level), 0, Config.Upgrade.MaxLevel)
				end
				clean.UnlockedAt = cleanTime(entry.UnlockedAt)
			end
		end
	end

	-- La selección siempre apunta a un núcleo conocido y desbloqueado.
	local selected = raw.Selected
	if CoreLogic.isUnlocked(data, selected) then
		data.Selected = selected
	end
	return data
end

function CoreLogic.isUnlocked(data: CoreData, elementId: any): boolean
	if not CoreLogic.indexOf(elementId) or type(data) ~= "table" or type(data.Elements) ~= "table" then
		return false -- datos sin sanear o mal formados: nada desbloqueado (sin errores)
	end
	local entry = data.Elements[elementId]
	return type(entry) == "table" and entry.Unlocked == true
end

-- Nivel de un núcleo, SIEMPRE un entero en [0, nivel máximo] aunque los datos estén mal
-- formados (NaN, infinito, negativo, texto -> 0; por encima del máximo -> máximo).
-- Naturaleza lee el nivel existente de UpgradeLevels (no se duplica en los núcleos).
function CoreLogic.level(data: CoreData, upgradeLevels: { [string]: number }?, elementId: string): number
	local value: any, maxLevel: number
	if CoreLogic.isDefault(elementId) then
		value = if type(upgradeLevels) == "table" then upgradeLevels[defaultUpgradeId()] else nil
		maxLevel = EconomyConfig.Upgrades[defaultUpgradeId()].MaxLevel
	else
		local entry = if type(data) == "table" and type(data.Elements) == "table" then data.Elements[elementId] else nil
		value = if type(entry) == "table" then entry.Level else nil
		maxLevel = Config.Upgrade.MaxLevel
	end
	if not isFiniteNumber(value) or value <= 0 then
		return 0
	end
	return math.min(math.floor(value), maxLevel)
end

-- Costes ------------------------------------------------------------------------------

-- Coste de desbloqueo (nil para Naturaleza, que ya viene desbloqueada).
function CoreLogic.unlockCost(elementId: any): number?
	local index = CoreLogic.indexOf(elementId)
	if not index or index == 1 then
		return nil
	end
	return math.floor(Config.Unlock.BaseCost * Config.Unlock.Growth ^ (index - 2))
end

-- Coste de subir el núcleo de su nivel actual al siguiente (nil si está al máximo o el
-- nivel no es válido).
function CoreLogic.upgradeCost(elementId: any, currentLevel: number): number?
	local index = CoreLogic.indexOf(elementId)
	if not index or not isFiniteNumber(currentLevel) or currentLevel < 0 then
		return nil
	end
	local level = math.floor(currentLevel)
	if index == 1 then
		local upgradeId = defaultUpgradeId()
		if level >= EconomyConfig.Upgrades[upgradeId].MaxLevel then
			return nil
		end
		return Economy.getUpgradeCost(upgradeId, level) -- la fórmula actual, sin cambios
	end
	if level >= Config.Upgrade.MaxLevel then
		return nil
	end
	local upgrade = Config.Upgrade
	return math.floor(upgrade.BaseUpgradeCost * upgrade.TierMultiplier ^ (index - 1) * upgrade.CostGrowth ^ level)
end

-- Producción ----------------------------------------------------------------------------

-- Producción BASE (sin mascotas) de un núcleo desbloqueado; 0 si está bloqueado.
function CoreLogic.coreProduction(data: CoreData, upgradeLevels: { [string]: number }?, elementId: string): number
	if not CoreLogic.isUnlocked(data, elementId) then
		return 0
	end
	local level = CoreLogic.level(data, upgradeLevels, elementId)
	if CoreLogic.isDefault(elementId) then
		-- Naturaleza = la producción actual del cristal, con la fórmula de Economy sin
		-- cambios, pero con el nivel ya validado (Economy no recibe NaN ni negativos).
		return Economy.getProductionPerSecond({ [defaultUpgradeId()] = level })
	end
	local index = CoreLogic.indexOf(elementId) :: number
	local upgrade = Config.Upgrade
	return upgrade.BaseProduction * upgrade.TierMultiplier ^ (index - 1) * (1 + level)
end

-- Suma de producciones BASE de los núcleos desbloqueados (sin mascotas).
function CoreLogic.baseProduction(data: CoreData, upgradeLevels: { [string]: number }?): number
	local total = 0
	for _, id in Config.Order do
		total += CoreLogic.coreProduction(data, upgradeLevels, id)
	end
	return total
end

-- Multiplicador de mascotas válido (NaN, infinito, negativo, texto o por encima de
-- MaxPetMultiplier -> 1, sin efecto): la producción nunca puede desbordarse a infinito.
local function cleanMultiplier(value: any): number
	return if isFiniteNumber(value) and value >= 0 and value <= Config.MaxPetMultiplier then value else 1
end

-- Producción total: (Σ producción base) · multiplicador de mascotas, aplicado UNA vez.
function CoreLogic.totalProduction(data: CoreData, upgradeLevels: { [string]: number }?, petMultiplier: number?): number
	return CoreLogic.baseProduction(data, upgradeLevels) * cleanMultiplier(petMultiplier)
end

-- Acciones (modifican los datos y devuelven el coste; el llamador resta la energía) ----

-- Al menos 1: un tiempo en (0, 1) se truncaría a 0, que en los datos significa "nunca"
-- (se saltaría el enfriamiento y UnlockedAt quedaría a 0).
local function validNow(now: any): boolean
	return isFiniteNumber(now) and now >= 1 and now <= MAX_TIME
end

-- Estructura mínima para poder escribir en los datos (los datos sin sanear pueden no tenerla).
local function validStructure(data: any): boolean
	return type(data) == "table" and type(data.Elements) == "table"
end

-- Devuelve (código, coste). Códigos: Success, InvalidRequest (elemento, tiempo o
-- estructura de datos no válidos), AlreadyUnlocked, Locked (falta un núcleo anterior),
-- InsufficientEnergy. Cualquier rechazo deja los datos sin tocar.
function CoreLogic.unlock(data: CoreData, elementId: any, energy: number, now: number): (string, number)
	local index = CoreLogic.indexOf(elementId)
	if not index or not validNow(now) or not validStructure(data) then
		return "InvalidRequest", 0
	end
	if CoreLogic.isUnlocked(data, elementId) then
		return "AlreadyUnlocked", 0
	end
	-- Naturaleza no tiene coste de desbloqueo, y sin la entrada del núcleo no hay dónde
	-- escribir: ambos casos solo se dan con datos sin sanear.
	local entry = data.Elements[elementId]
	if index == 1 or type(entry) ~= "table" then
		return "InvalidRequest", 0
	end
	-- [PROVISIONAL] Desbloqueo secuencial: hacen falta TODOS los núcleos anteriores del
	-- orden (así, ni con datos guardados incoherentes se puede saltar ninguno).
	if Config.Unlock.Sequential then
		for previous = 1, index - 1 do
			if not CoreLogic.isUnlocked(data, Config.Order[previous]) then
				return "Locked", 0
			end
		end
	end
	local cost = CoreLogic.unlockCost(elementId) :: number
	if not isFiniteNumber(energy) or energy < cost then
		return "InsufficientEnergy", cost
	end
	entry.Unlocked = true
	entry.UnlockedAt = math.floor(now)
	return "Success", cost
end

-- Coste de cambiar de elemento, calculado con la producción BASE de los datos (sin
-- mascotas): quien llama no puede pasar una producción equivocada.
function CoreLogic.switchCost(data: CoreData, upgradeLevels: { [string]: number }?): number
	local production = CoreLogic.baseProduction(data, upgradeLevels)
	return math.max(Config.Switch.MinCost, math.floor(Config.Switch.ProductionSeconds * production))
end

-- Devuelve (código, coste). Códigos: Success, InvalidRequest (elemento, tiempo o
-- estructura de datos no válidos), Locked, AlreadySelected, TooFast (enfriamiento),
-- InsufficientEnergy. Cualquier rechazo deja los datos sin tocar.
function CoreLogic.selectElement(data: CoreData, upgradeLevels: { [string]: number }?, elementId: any, energy: number, now: number): (string, number)
	if not CoreLogic.indexOf(elementId) or not validNow(now) or not validStructure(data) then
		return "InvalidRequest", 0
	end
	if not CoreLogic.isUnlocked(data, elementId) then
		return "Locked", 0
	end
	if data.Selected == elementId then
		return "AlreadySelected", 0
	end
	local clock = math.floor(now)
	local lastSwitch = cleanTime(data.LastSwitchAt) -- datos sin sanear: tiempo no válido -> 0
	if lastSwitch > 0 and clock - lastSwitch < Config.Switch.CooldownSeconds then
		return "TooFast", 0
	end
	local cost = CoreLogic.switchCost(data, upgradeLevels)
	if not isFiniteNumber(energy) or energy < cost then
		return "InsufficientEnergy", cost
	end
	data.Selected = elementId
	data.LastSwitchAt = clock
	return "Success", cost
end

-- Producción offline (solo cálculo; NO concede energía ni escribe nada) ------------------

-- Devuelve (energía, segundos computados) para una ausencia de `now - lastSeen`:
--   floor(min(ausencia, CapSeconds) · producción base total · mascotas · Efficiency)
-- La producción se calcula aquí, desde los datos, con el multiplicador de mascotas
-- aplicado UNA sola vez. Sin `lastSeen` válido (> 0, partidas antiguas), con ausencia
-- cero o negativa, o con tiempos no válidos, devuelve 0. No modifica `data`.
function CoreLogic.offlineReward(data: CoreData, upgradeLevels: { [string]: number }?, petMultiplier: any, lastSeen: any, now: any): (number, number)
	if not (validNow(lastSeen) and validNow(now)) then
		return 0, 0
	end
	local elapsed = now - lastSeen
	if elapsed <= 0 then
		return 0, 0
	end
	local seconds = math.min(elapsed, Config.Offline.CapSeconds)
	local production = if Config.Offline.IncludePetMultiplier
		then CoreLogic.totalProduction(data, upgradeLevels, petMultiplier)
		else CoreLogic.baseProduction(data, upgradeLevels)
	return math.floor(seconds * production * Config.Offline.Efficiency), seconds
end

-- En Roblox se inicializa solo; las pruebas llaman a init con sus propias tablas.
if typeof(script) == "Instance" then
	local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	CoreLogic.init(require(Shared.Config.CoreConfig), require(Shared.Economy), require(Shared.Config.EconomyConfig))
end

return CoreLogic
