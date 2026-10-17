-- Persistencia de la energía y los niveles de mejora, de las mascotas (obtenidas y
-- equipadas), de las zonas desbloqueadas y del progreso de misiones y logros (campo
-- Quests), con un único DataStore.
--
-- Campos del registro (los nombres coinciden con los del perfil en PlayerDataService):
--   Energy: number                      energía actual (>= 0)
--   UpgradeLevels: { [id]: number }     niveles de mejora (enteros en [0, MaxLevel])
--   Tutorial: { Status, Step }          estado del tutorial inicial
--   Pets, Equipped, NextPetUid, UnlockedZones, Quests, Session, Version
-- Los registros antiguos sin Energy/UpgradeLevels cargan con los valores iniciales.
--
-- Seguridad de datos:
-- - Siempre UpdateAsync (nunca SetAsync a ciegas).
-- - Bloqueo de sesión: mientras un servidor tiene los datos de un jugador, otro no los
--   sobrescribe. Un bloqueo abandonado caduca a los LOCK_TIMEOUT segundos.
-- - Si la carga falla, el perfil NO se guarda, para no pisar datos buenos con datos vacíos.
-- - Al cargar se sanean los datos; las mascotas de especies que ya no existen en
--   PetConfig se conservan archivadas en lugar de borrarse.
--
-- En Studio hace falta activar Game Settings > Security > "Enable Studio Access to
-- API Services". Si no está activado, el juego funciona pero sin guardar.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.PetConfig)
local EconomyConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.EconomyConfig)
local QuestLogic = require(script.Parent.Parent.Util.QuestLogic)
local TutorialLogic = require(script.Parent.Parent.Util.TutorialLogic)

local STORE_NAME = "RebirthCity_PlayerData_v1"
local SCHEMA_VERSION = 2 -- 2: añade Energy y UpgradeLevels (los registros v1 siguen cargando)
local LOCK_TIMEOUT = 30 * 60
local LOAD_ATTEMPTS = 5
local LOAD_RETRY_DELAY = 5
local SAVE_ATTEMPTS = 3
local SAVE_RETRY_DELAY = 2
local MAX_STORED_PETS = 1000 -- tope de seguridad contra datos corruptos
local MAX_ENERGY = 1e15 -- tope de seguridad (muy por encima de cualquier partida real)
local MAX_ARCHIVED_UPGRADES = 50

export type PetEntry = { Uid: string, PetId: string }

export type PetData = {
	Pets: { PetEntry }, -- mascotas válidas
	Archived: { PetEntry }, -- especies desconocidas: se guardan tal cual
	Equipped: { string }, -- Uids equipados
	NextPetUid: number,
	UnlockedZones: { string }, -- zonas compradas (se conservan aunque dejen de existir)
	Quests: QuestLogic.QuestData, -- misiones, diarias y logros (vacío en partidas antiguas)
	-- Copia de la economía del perfil para guardar (PlayerDataService la rellena justo antes
	-- de guardar; durante la sesión manda profile.Energy / profile.UpgradeLevels).
	Energy: number,
	UpgradeLevels: { [string]: number },
	ArchivedUpgrades: { [string]: number }, -- mejoras que ya no existen: se conservan tal cual
	Tutorial: TutorialLogic.TutorialData, -- tutorial inicial (activo en partidas antiguas)
}

-- "Loaded": datos cargados y bloqueados para esta sesión.
-- "Unavailable": DataStore no accesible (p. ej. Studio sin acceso a API): jugar sin guardar.
-- "Failed": error real; no se debe guardar este perfil.
export type LoadStatus = "Loaded" | "Unavailable" | "Failed"

local SaveService = {}

local store: DataStore? = nil

local function isUnavailableError(message: string): boolean
	return message:find("StudioAccessToApisNotAllowed", 1, true) ~= nil
		or message:find("403", 1, true) ~= nil
		or message:find("publish", 1, true) ~= nil
end

local function getStore(): (DataStore?, string?)
	if store then
		return store, nil
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
		return result, nil
	end
	return nil, tostring(result)
end

local function keyFor(userId: number): string
	return "player_" .. userId
end

local function isLockedByOtherSession(data: { [string]: any }): boolean
	local session = data.Session
	return type(session) == "table"
		and session.JobId ~= game.JobId
		and type(session.Time) == "number"
		and os.time() - session.Time < LOCK_TIMEOUT
end

local function startingUpgrades(): { [string]: number }
	local levels = {}
	for upgradeId in EconomyConfig.Upgrades do
		levels[upgradeId] = 0
	end
	return levels
end

function SaveService.emptyData(): PetData
	return {
		Pets = {},
		Archived = {},
		Equipped = {},
		NextPetUid = 1,
		UnlockedZones = {},
		Quests = QuestLogic.empty(),
		Energy = EconomyConfig.StartingEnergy,
		UpgradeLevels = startingUpgrades(),
		ArchivedUpgrades = {},
		Tutorial = TutorialLogic.empty(),
	}
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Energía y mejoras guardadas -> valores válidos. Lo ausente (partidas antiguas) toma el
-- valor inicial; lo corrupto también, avisándolo en la consola.
local function sanitizeEconomy(raw: { [string]: any }, result: PetData)
	local energy = raw.Energy
	if energy == nil then
		result.Energy = EconomyConfig.StartingEnergy
	elseif isFiniteNumber(energy) and energy >= 0 then
		result.Energy = math.min(energy, MAX_ENERGY)
	else
		warn("[SaveService] Energía guardada no válida (" .. tostring(energy) .. "); se usa el valor inicial.")
		result.Energy = EconomyConfig.StartingEnergy
	end

	if type(raw.UpgradeLevels) ~= "table" then
		return
	end
	local archived = 0
	for upgradeId, level in raw.UpgradeLevels do
		local definition = type(upgradeId) == "string" and EconomyConfig.Upgrades[upgradeId]
		if definition then
			if isFiniteNumber(level) then
				result.UpgradeLevels[upgradeId] = math.clamp(math.floor(level), 0, definition.MaxLevel)
			else
				warn("[SaveService] Nivel de mejora no válido para " .. upgradeId .. "; se usa 0.")
			end
		elseif type(upgradeId) == "string" and #upgradeId <= 64 and isFiniteNumber(level) and archived < MAX_ARCHIVED_UPGRADES then
			result.ArchivedUpgrades[upgradeId] = level
			archived += 1
		end
	end
end

local function sanitize(raw: any): PetData
	local result = SaveService.emptyData()
	if type(raw) ~= "table" then
		return result
	end

	local seen: { [string]: boolean } = {}
	if type(raw.Pets) == "table" then
		for _, entry in raw.Pets do
			if #result.Pets + #result.Archived >= MAX_STORED_PETS then
				break
			end
			if type(entry) == "table" and type(entry.Uid) == "string" and type(entry.PetId) == "string" and not seen[entry.Uid] then
				seen[entry.Uid] = true
				local clean = { Uid = entry.Uid, PetId = entry.PetId }
				if PetConfig.Pets[entry.PetId] then
					table.insert(result.Pets, clean)
				else
					table.insert(result.Archived, clean)
				end
			end
		end
	end

	local valid: { [string]: boolean } = {}
	for _, entry in result.Pets do
		valid[entry.Uid] = true
	end
	if type(raw.Equipped) == "table" then
		for _, uid in raw.Equipped do
			if type(uid) == "string" and valid[uid] and not table.find(result.Equipped, uid) and #result.Equipped < PetConfig.MaxEquipped then
				table.insert(result.Equipped, uid)
			end
		end
	end

	local nextUid = if type(raw.NextPetUid) == "number" and raw.NextPetUid >= 1 then math.floor(raw.NextPetUid) else 1
	-- Garantiza que nunca se reutiliza un Uid existente.
	for uid in seen do
		local number = tonumber(uid)
		if number and number >= nextUid then
			nextUid = math.floor(number) + 1
		end
	end
	result.NextPetUid = nextUid

	-- Zonas desbloqueadas: textos únicos. Las partidas antiguas no tienen este campo.
	if type(raw.UnlockedZones) == "table" then
		for _, zoneId in raw.UnlockedZones do
			if type(zoneId) == "string" and #zoneId <= 64 and not table.find(result.UnlockedZones, zoneId) and #result.UnlockedZones < 100 then
				table.insert(result.UnlockedZones, zoneId)
			end
		end
	end

	-- Misiones: las partidas sin este campo empiezan vacías; nada existente se pierde.
	result.Quests = QuestLogic.sanitize(raw.Quests)
	-- Energía y mejoras (las partidas antiguas no las tienen).
	sanitizeEconomy(raw, result)
	-- Tutorial: sin el campo empieza activo; el servidor lo completa solo si ya se cumplió.
	result.Tutorial = TutorialLogic.sanitize(raw.Tutorial)

	return result
end

function SaveService.load(userId: number): (LoadStatus, PetData?)
	local dataStore, storeError = getStore()
	if not dataStore then
		if storeError and isUnavailableError(storeError) then
			return "Unavailable", nil
		end
		warn("[SaveService] No se pudo abrir el DataStore:", storeError)
		return "Failed", nil
	end

	local key = keyFor(userId)
	for attempt = 1, LOAD_ATTEMPTS do
		-- En el último intento se toma el bloqueo aunque otra sesión lo tenga
		-- (la otra sesión probablemente se cerró sin liberarlo).
		local forceLock = attempt == LOAD_ATTEMPTS
		local lockedElsewhere = false
		local loaded: any = nil

		local ok, result = pcall(function()
			return dataStore:UpdateAsync(key, function(old)
				local data = if type(old) == "table" then old else { Version = SCHEMA_VERSION }
				if not forceLock and isLockedByOtherSession(data) then
					lockedElsewhere = true
					return nil -- cancela la escritura
				end
				lockedElsewhere = false
				data.Session = { JobId = game.JobId, Time = os.time() }
				loaded = data
				return data
			end)
		end)

		if ok and not lockedElsewhere then
			return "Loaded", sanitize(loaded or result)
		elseif not ok then
			local message = tostring(result)
			if isUnavailableError(message) then
				return "Unavailable", nil
			end
			warn(("[SaveService] Error al cargar %s (intento %d/%d): %s"):format(key, attempt, LOAD_ATTEMPTS, message))
		end

		if attempt < LOAD_ATTEMPTS then
			task.wait(LOAD_RETRY_DELAY)
		end
	end

	return "Failed", nil
end

-- Guarda las mascotas. `release` libera el bloqueo de sesión (al salir el jugador).
function SaveService.save(userId: number, data: PetData, release: boolean): boolean
	local dataStore = getStore()
	if not dataStore then
		return false
	end

	local pets = table.clone(data.Pets)
	for _, entry in data.Archived do
		table.insert(pets, entry)
	end
	local equipped = table.clone(data.Equipped)
	local unlockedZones = table.clone(data.UnlockedZones)
	local quests = QuestLogic.serialize(data.Quests)
	local tutorial = TutorialLogic.serialize(data.Tutorial)
	-- Copias tomadas ANTES de esperar al DataStore: lo que cambie mientras tanto queda en el
	-- perfil y se guarda la próxima vez.
	local energy = if isFiniteNumber(data.Energy) and data.Energy >= 0 then math.min(data.Energy, MAX_ENERGY) else nil
	local upgradeLevels = table.clone(data.ArchivedUpgrades)
	for upgradeId, level in data.UpgradeLevels do
		upgradeLevels[upgradeId] = level
	end
	local key = keyFor(userId)

	for attempt = 1, SAVE_ATTEMPTS do
		local lostLock = false
		local ok, result = pcall(function()
			return dataStore:UpdateAsync(key, function(old)
				local stored = if type(old) == "table" then old else {}
				if isLockedByOtherSession(stored) then
					-- Otra sesión tomó el control: no sobrescribir sus datos.
					lostLock = true
					return nil
				end
				lostLock = false
				stored.Version = SCHEMA_VERSION
				stored.Pets = pets
				stored.Equipped = equipped
				stored.NextPetUid = data.NextPetUid
				stored.UnlockedZones = unlockedZones
				stored.Quests = quests
				stored.Tutorial = tutorial
				if energy ~= nil then
					stored.Energy = energy -- nunca se escribe un valor no válido
				end
				stored.UpgradeLevels = upgradeLevels
				stored.Session = if release then nil else { JobId = game.JobId, Time = os.time() }
				return stored
			end)
		end)

		if ok then
			if lostLock then
				warn("[SaveService] Otra sesión tiene los datos de " .. key .. "; no se sobrescriben.")
				return false
			end
			return true
		end
		warn(("[SaveService] Error al guardar %s (intento %d/%d): %s"):format(key, attempt, SAVE_ATTEMPTS, tostring(result)))
		if attempt < SAVE_ATTEMPTS then
			task.wait(SAVE_RETRY_DELAY)
		end
	end
	return false
end

return SaveService
