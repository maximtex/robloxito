-- Lógica pura de los ocho núcleos elementales (sin APIs de Roblox), para probarla fuera
-- de Studio. La usan SaveService (guardado), PlayerDataService (atributos), CoreService
-- (desbloquear, mejorar y elegir) y AbilityService (maestría de las habilidades Q/R).
-- Los núcleos ya no producen nada: solo dan sus habilidades elementales.
--
-- Datos de un jugador (futuro campo "Cores" del registro guardado):
--   {
--     Selected = "Nature",          -- elemento activo (siempre uno desbloqueado)
--     Secondary = "Water",          -- elemento secundario (tecla R), opcional: nil si no
--                                   -- hay; siempre desbloqueado y distinto de Selected
--     LastSwitchAt = 0,             -- os.time() del servidor del último cambio
--     Elements = {
--       Nature = { Unlocked = true, Mastery = 0 },                     -- SIN Level
--       Water  = { Unlocked = false, Level = 0, Mastery = 0, UnlockedAt = 0 },
--       ...
--     },
--   }
-- - Naturaleza viene desbloqueada y no tiene nivel (antes era la Resonancia del Cristal).
-- - sanitize conserva los campos y elementos que no conoce (copiados, no compartidos), y
--   corrections dice qué valores conocidos corrigió (para archivarlos antes).
-- - unlock, upgrade y selectElement modifican los datos y DEVUELVEN el coste: quien los
--   llame (CoreService) debe restar esos 💎 en el mismo paso, sin pausas.
-- - Cualquier número no válido (NaN, infinito, negativo, texto) se normaliza a un valor
--   seguro; los campos desconocidos solo se conservan si son datos válidos y guardables.

local CoreLogic = {}

local Config: any

export type ElementData = { Unlocked: boolean, Level: number?, Mastery: number, UnlockedAt: number? }
export type CoreData = { Selected: string, Secondary: string?, LastSwitchAt: number, Elements: { [string]: any } }

-- Campos que sanitize interpreta; cualquier otro se conserva tal cual.
local KNOWN_TOP = { Selected = true, Secondary = true, LastSwitchAt = true, Elements = true }
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
function CoreLogic.validateConfig(config: any): (boolean, { string })
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
	positive(config.Upgrade, "BaseUpgradeCost", 0, true)
	positive(config.Upgrade, "CostGrowth", 1, true)
	positive(config.Upgrade, "TierMultiplier", 1, false)
	local maxLevel = type(config.Upgrade) == "table" and config.Upgrade.MaxLevel
	if not (isFiniteNumber(maxLevel) and maxLevel >= 1 and maxLevel == math.floor(maxLevel)) then
		fail("Upgrade.MaxLevel debe ser un entero >= 1")
	end
	positive(config.Switch, "MinCost", 0, false)
	positive(config.Switch, "CooldownSeconds", 0, false)
	positive(config, "MaxMastery", 0, true)

	-- Los valores extremos que produce la configuración deben ser enteros exactos
	-- (< 2^53): ni infinitos ni tan grandes que pierdan precisión al restar 💎.
	if #errors == 0 then
		local count = #order
		local unlock, upgrade = config.Unlock, config.Upgrade
		local extremes = {
			{ "coste de desbloqueo máximo", unlock.BaseCost * unlock.Growth ^ (count - 2) },
			{ "coste de mejora máximo", upgrade.BaseUpgradeCost * upgrade.TierMultiplier ^ (count - 1) * upgrade.CostGrowth ^ (upgrade.MaxLevel - 1) },
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
function CoreLogic.init(coreConfig: any)
	local ok, errors = CoreLogic.validateConfig(coreConfig)
	if not ok then
		error("[CoreLogic] Configuración de núcleos no válida: " .. table.concat(errors, "; "))
	end
	Config = coreConfig
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
				-- Naturaleza siempre desbloqueada y sin nivel; un "Level" aquí se trata
				-- como campo desconocido (se conserva, no se usa).
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
	-- El secundario (si hay) también: desbloqueado y distinto del principal.
	local secondary = raw.Secondary
	if CoreLogic.isUnlocked(data, secondary) and secondary ~= data.Selected then
		data.Secondary = secondary
	end
	return data
end

-- Copia profunda con solo datos válidos y guardables (la misma que usa sanitize).
CoreLogic.storableCopy = deepCopy

-- Un valor original tal cual si es guardable; si no (NaN, infinito, función...), su
-- descripción en texto, para que el archivo conserve qué había.
local function describe(value: any): any
	local copy = deepCopy(value)
	if copy == nil then
		return ("<%s: %s>"):format(typeof(value), tostring(value))
	end
	return copy
end

-- Valores conocidos que sanitize ha corregido: { [ruta] = valor original }, o nil si no
-- corrigió nada. Sirve para archivarlos ANTES de normalizar. Un campo ausente (partidas
-- antiguas) no es una corrección. Los campos y elementos desconocidos no aparecen: los
-- conserva sanitize.
function CoreLogic.corrections(raw: any, clean: CoreData): { [string]: any }?
	if raw == nil then
		return nil
	end
	local changes = {}
	local found = false
	local function note(path: string, original: any, fixed: any)
		-- NaN ~= NaN: también se anota. Un valor corregido nunca es una tabla: si `fixed` lo
		-- es, sanitize conservó una copia (Level de Naturaleza) y no se perdió nada.
		if original ~= nil and original ~= fixed and type(fixed) ~= "table" then
			changes[path] = describe(original)
			found = true
		end
	end
	if type(raw) ~= "table" then
		note("Cores", raw, nil)
		return changes
	end
	note("Selected", raw.Selected, clean.Selected)
	note("Secondary", raw.Secondary, clean.Secondary)
	note("LastSwitchAt", raw.LastSwitchAt, clean.LastSwitchAt)
	local elements = raw.Elements
	if type(elements) ~= "table" then
		note("Elements", elements, nil)
	else
		for _, id in Config.Order do
			local entry = elements[id]
			if type(entry) ~= "table" then
				note("Elements." .. id, entry, nil)
			else
				local fixed = clean.Elements[id]
				for field in KNOWN_ELEMENT do
					note(("Elements.%s.%s"):format(id, field), entry[field], fixed[field])
				end
			end
		end
	end
	return if found then changes else nil
end

function CoreLogic.isUnlocked(data: CoreData, elementId: any): boolean
	if not CoreLogic.indexOf(elementId) or type(data) ~= "table" or type(data.Elements) ~= "table" then
		return false -- datos sin sanear o mal formados: nada desbloqueado (sin errores)
	end
	local entry = data.Elements[elementId]
	return type(entry) == "table" and entry.Unlocked == true
end

-- Elemento secundario válido (desbloqueado y distinto del principal) o nil.
function CoreLogic.secondaryOf(data: CoreData): string?
	if type(data) ~= "table" then
		return nil
	end
	local secondary = data.Secondary
	if CoreLogic.isUnlocked(data, secondary) and secondary ~= data.Selected then
		return secondary
	end
	return nil
end

-- Nivel de un núcleo, SIEMPRE un entero en [0, nivel máximo] aunque los datos estén mal
-- formados (NaN, infinito, negativo, texto -> 0; por encima del máximo -> máximo).
-- Naturaleza y los elementos desconocidos no tienen nivel: siempre 0.
function CoreLogic.level(data: CoreData, elementId: string): number
	if not CoreLogic.indexOf(elementId) or CoreLogic.isDefault(elementId) then
		return 0
	end
	local entry = if type(data) == "table" and type(data.Elements) == "table" then data.Elements[elementId] else nil
	local value = if type(entry) == "table" then entry.Level else nil
	if not isFiniteNumber(value) or value <= 0 then
		return 0
	end
	return math.min(math.floor(value), Config.Upgrade.MaxLevel)
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

-- Coste de subir el núcleo de su nivel actual al siguiente (nil para Naturaleza, que no
-- tiene nivel, si está al máximo o si el nivel no es válido).
function CoreLogic.upgradeCost(elementId: any, currentLevel: number): number?
	local index = CoreLogic.indexOf(elementId)
	if not index or index == 1 or not isFiniteNumber(currentLevel) or currentLevel < 0 then
		return nil
	end
	local level = math.floor(currentLevel)
	if level >= Config.Upgrade.MaxLevel then
		return nil
	end
	local upgrade = Config.Upgrade
	return math.floor(upgrade.BaseUpgradeCost * upgrade.TierMultiplier ^ (index - 1) * upgrade.CostGrowth ^ level)
end

-- Acciones (modifican los datos y devuelven el coste; el llamador resta los 💎) --------

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
-- InsufficientDiamonds. Cualquier rechazo deja los datos sin tocar.
function CoreLogic.unlock(data: CoreData, elementId: any, diamonds: number, now: number): (string, number)
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
	if not isFiniteNumber(diamonds) or diamonds < cost then
		return "InsufficientDiamonds", cost
	end
	entry.Unlocked = true
	entry.UnlockedAt = math.floor(now)
	return "Success", cost
end

-- Devuelve (código, coste). Sube un nivel un núcleo distinto de Naturaleza (que no tiene
-- nivel). Códigos: Success,
-- InvalidRequest (elemento desconocido, Naturaleza o datos sin estructura), Locked
-- (bloqueado), MaxLevel, InsufficientDiamonds. Cualquier rechazo deja los datos sin tocar.
function CoreLogic.upgrade(data: CoreData, elementId: any, diamonds: number): (string, number)
	local index = CoreLogic.indexOf(elementId)
	if not index or index == 1 or not validStructure(data) then
		return "InvalidRequest", 0
	end
	local entry = data.Elements[elementId]
	if type(entry) ~= "table" or not CoreLogic.isUnlocked(data, elementId) then
		return "Locked", 0
	end
	local level = CoreLogic.level(data, elementId)
	local cost = CoreLogic.upgradeCost(elementId, level)
	if not cost then
		return "MaxLevel", 0
	end
	if not isFiniteNumber(diamonds) or diamonds < cost then
		return "InsufficientDiamonds", cost
	end
	entry.Level = level + 1
	return "Success", cost
end

-- Coste en 💎 de cambiar de elemento (CoreConfig.Switch.MinCost).
function CoreLogic.switchCost(): number
	return Config.Switch.MinCost
end

-- Devuelve (código, coste). Códigos: Success, InvalidRequest (elemento, tiempo o
-- estructura de datos no válidos), Locked, AlreadySelected, TooFast (enfriamiento),
-- InsufficientDiamonds. Cualquier rechazo deja los datos sin tocar.
function CoreLogic.selectElement(data: CoreData, elementId: any, diamonds: number, now: number): (string, number)
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
	local cost = CoreLogic.switchCost()
	if not isFiniteNumber(diamonds) or diamonds < cost then
		return "InsufficientDiamonds", cost
	end
	-- Si era el secundario, se intercambian (el principal anterior pasa a la R).
	if data.Secondary == elementId then
		data.Secondary = data.Selected
	end
	data.Selected = elementId
	data.LastSwitchAt = clock
	return "Success", cost
end

-- Elemento secundario (tecla R). Mismo coste y enfriamiento que cambiar el principal
-- (comparten LastSwitchAt). Elegir el principal actual como secundario los intercambia
-- (solo si ya había secundario; si no, el principal se quedaría vacío: AlreadySelected).
-- Devuelve (código, coste). Códigos: Success, InvalidRequest, Locked, AlreadySelected,
-- TooFast, InsufficientDiamonds. Cualquier rechazo deja los datos sin tocar.
function CoreLogic.selectSecondary(data: CoreData, elementId: any, diamonds: number, now: number): (string, number)
	if not CoreLogic.indexOf(elementId) or not validNow(now) or not validStructure(data) then
		return "InvalidRequest", 0
	end
	if not CoreLogic.isUnlocked(data, elementId) then
		return "Locked", 0
	end
	local current = if CoreLogic.isUnlocked(data, data.Secondary) and data.Secondary ~= data.Selected then data.Secondary else nil
	if current == elementId or (data.Selected == elementId and current == nil) then
		return "AlreadySelected", 0
	end
	local clock = math.floor(now)
	local lastSwitch = cleanTime(data.LastSwitchAt)
	if lastSwitch > 0 and clock - lastSwitch < Config.Switch.CooldownSeconds then
		return "TooFast", 0
	end
	local cost = CoreLogic.switchCost()
	if not isFiniteNumber(diamonds) or diamonds < cost then
		return "InsufficientDiamonds", cost
	end
	if data.Selected == elementId then
		data.Selected = current :: string -- intercambio
	end
	data.Secondary = elementId
	data.LastSwitchAt = clock
	return "Success", cost
end

-- En Roblox se inicializa solo; las pruebas llaman a init con sus propias tablas.
if typeof(script) == "Instance" then
	local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	CoreLogic.init(require(Shared.Config.CoreConfig))
end

return CoreLogic
