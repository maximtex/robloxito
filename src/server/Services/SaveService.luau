-- Persistencia de la energía y los niveles de mejora, de las mascotas (obtenidas y
-- equipadas), de las zonas desbloqueadas y del progreso de misiones y logros (campo
-- Quests), con un único DataStore.
--
-- Campos del registro (los nombres coinciden con los del perfil en PlayerDataService):
--   Energy: number                      energía actual (>= 0)
--   Money: number                       dinero actual (>= 0; lo sueltan los enemigos)
--   UpgradeLevels: { [id]: number }     niveles de mejora (enteros en [0, MaxLevel])
--   Tutorial: { Status, Step }          estado del tutorial inicial
--   Pets, Equipped, NextPetUid, UnlockedZones, Quests, Session, Version
--   Cores: { Selected, LastSwitchAt, Elements }  los ocho núcleos (CoreLogic): producen
--                                       energía y los gestiona CoreService.
--   CoresArchive: { entrada }           valores de Cores corregidos al sanear, guardados
--                                       ANTES de normalizar. Nunca se borra ni se reescribe.
--   LastSeen: number                    os.time() del último guardado correcto: base de la
--                                       recompensa offline (PlayerDataService).
--   Rebirth: { Count, Tokens, Shop, BestLevel, LastAt }  renacimientos, fichas y ventajas
--                                       de la tienda (RebirthLogic; los gestiona RebirthService).
--   Adventure: { Npcs, Amulets, Equipped, Blessings, Active }  historias de los personajes,
--                                       amuletos y bendiciones (AdventureLogic; los gestiona
--                                       AdventureService).
--   Rewards: { Streak, LastDay, Claims, Codes }  premio diario y códigos canjeados
--                                       (RewardLogic; RewardService).
--   Shop: { Receipts, AutoUpgrade }     compras sueltas ya concedidas y el interruptor de la
--                                       mejora automática (MonetizationLogic; ShopService).
--   Weekly: { Week, Energy }            energía generada esta semana (LeaderboardLogic;
--                                       clasificación semanal).
--   Weapons: { Owned, Levels, Equipped }  armas compradas o regaladas, su nivel y la
--                                       equipada (WeaponLogic; WeaponService).
--   Bosses: { [tipo]: número }          veces que ha derrotado a cada jefe (BossRewardService:
--                                       premio de la primera vez y acceso a la zona siguiente).
--   Items: { Potions, Eggs, Boosts, Titles, Title, TitleSet, PotionsUsed }  pociones, huevos
--                                       guardados y títulos (ItemLogic; ItemService). Las
--                                       pociones activas se guardan con los segundos que les quedan.
-- Los registros antiguos sin Energy/UpgradeLevels cargan con los valores iniciales, los
-- que no tienen Cores (v2) empiezan con Naturaleza desbloqueada y seleccionada, y los que
-- no tienen Rebirth (v3) empiezan sin renacimientos, los que no tienen Adventure (v4)
-- empiezan sin historias, amuletos ni bendiciones y los que no tienen Rewards/Shop/Weekly
-- (v5) empiezan sin racha, sin compras y con la semana a cero.
--
-- Seguridad de datos:
-- - Siempre UpdateAsync (nunca SetAsync a ciegas).
-- - Bloqueo de sesión: mientras un servidor tiene los datos de un jugador, otro no los
--   sobrescribe. Un bloqueo abandonado caduca a los LOCK_TIMEOUT segundos.
-- - Si la carga falla, el perfil NO se guarda, para no pisar datos buenos con datos vacíos.
-- - Al cargar se sanean los datos; las mascotas de especies que ya no existen en
--   PetConfig se conservan archivadas en lugar de borrarse.
-- - Al guardar se escribe sobre el registro existente: los campos que este código no
--   conoce se conservan (así, volver a la versión anterior no borra Cores ni LastSeen).
--
-- En Studio hace falta activar Game Settings > Security > "Enable Studio Access to
-- API Services". Si no está activado, el juego funciona pero sin guardar.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.PetConfig)
local EconomyConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.EconomyConfig)
local QuestLogic = require(script.Parent.Parent.Util.QuestLogic)
local TutorialLogic = require(script.Parent.Parent.Util.TutorialLogic)
local CoreLogic = require(script.Parent.Parent.Util.CoreLogic)
local RebirthLogic = require(ReplicatedStorage:WaitForChild("Shared").RebirthLogic)
local AdventureLogic = require(ReplicatedStorage:WaitForChild("Shared").AdventureLogic)
local MonetizationLogic = require(ReplicatedStorage:WaitForChild("Shared").MonetizationLogic)
local RewardLogic = require(script.Parent.Parent.Util.RewardLogic)
local LeaderboardLogic = require(script.Parent.Parent.Util.LeaderboardLogic)
local WeaponLogic = require(ReplicatedStorage:WaitForChild("Shared").WeaponLogic)
local WeaponConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.WeaponConfig)
local ItemLogic = require(ReplicatedStorage:WaitForChild("Shared").ItemLogic)

local STORE_NAME = "RebirthCity_PlayerData_v1"
-- 2: añade Energy y UpgradeLevels. 3: añade Cores, CoresArchive y LastSeen. 4: añade Rebirth.
-- 5: añade Adventure. 6: añade Rewards, Shop y Weekly. 7: añade Money. 8: añade Weapons y
-- Bosses. Los registros v1 a v7 siguen cargando (sin Money empiezan con el dinero inicial;
-- sin Weapons, con el láser al nivel de la antigua mejora "LaserPower"; sin Bosses, sin jefes).
-- 9: añade Items (pociones, huevos guardados y títulos; sin el campo, vacío).
local SCHEMA_VERSION = 9
local LOCK_TIMEOUT = 30 * 60
local LOAD_ATTEMPTS = 5
local LOAD_RETRY_DELAY = 5
local SAVE_ATTEMPTS = 3
local SAVE_RETRY_DELAY = 2
local MAX_STORED_PETS = 1000 -- tope de seguridad contra datos corruptos
local MAX_ENERGY = 1e15 -- tope de seguridad (muy por encima de cualquier partida real)
local MAX_ARCHIVED_UPGRADES = 50
local MAX_CORES_ARCHIVE = 20 -- entradas nuevas como máximo (las existentes nunca se borran)

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
	Money: number,
	UpgradeLevels: { [string]: number },
	ArchivedUpgrades: { [string]: number }, -- mejoras que ya no existen: se conservan tal cual
	Tutorial: TutorialLogic.TutorialData, -- tutorial inicial (activo en partidas antiguas)
	Cores: CoreLogic.CoreData, -- núcleos (producen energía; ver CoreService)
	CoresArchive: { any }, -- valores de núcleos corregidos al sanear (ver sanitizeCores)
	-- os.time() del último guardado correcto (0 si no hay: partidas antiguas o nuevas).
	-- Solo se lee al cargar (recompensa offline); al guardar se escribe la hora actual.
	LastSeen: number,
	Rebirth: RebirthLogic.RebirthData, -- renacimientos, fichas y tienda (ver RebirthService)
	Adventure: AdventureLogic.AdventureData, -- historias, amuletos y bendiciones (AdventureService)
	Rewards: RewardLogic.RewardData, -- premio diario y códigos (RewardService)
	Shop: MonetizationLogic.ShopData, -- compras sueltas concedidas y mejora automática (ShopService)
	Weekly: LeaderboardLogic.Weekly, -- energía generada esta semana (clasificación semanal)
	Weapons: WeaponLogic.WeaponData, -- armas, niveles y la equipada (WeaponService)
	Bosses: { [string]: number }, -- jefes derrotados (BossRewardService)
	Items: ItemLogic.ItemData, -- pociones, huevos guardados y títulos (ItemService)
}

-- "Loaded": datos cargados y bloqueados para esta sesión.
-- "Unavailable": DataStore no accesible (p. ej. Studio sin acceso a API): jugar sin guardar.
-- "Failed": error real; no se debe guardar este perfil.
export type LoadStatus = "Loaded" | "Unavailable" | "Failed"

local SaveService = {}

local store: DataStore? = nil

local function isUnavailableError(message: string): boolean
	return message:find("StudioAccessToApisNotAllowed", 1, true) ~= nil
		or message:find("Studio access to APIs is not allowed", 1, true) ~= nil
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
		Pets = { { Uid = "p1", PetId = "Sproutling" } },
		Archived = {},
		Equipped = { "p1" },
		NextPetUid = 2,
		UnlockedZones = {},
		Quests = QuestLogic.empty(),
		Energy = EconomyConfig.StartingEnergy,
		Money = EconomyConfig.StartingMoney,
		UpgradeLevels = startingUpgrades(),
		ArchivedUpgrades = {},
		Tutorial = TutorialLogic.empty(),
		Cores = CoreLogic.empty(),
		CoresArchive = {},
		LastSeen = 0,
		Rebirth = RebirthLogic.empty(),
		Adventure = AdventureLogic.empty(),
		Rewards = RewardLogic.empty(),
		Shop = MonetizationLogic.empty(),
		Weekly = LeaderboardLogic.emptyWeekly(),
		Weapons = WeaponLogic.empty(),
		Bosses = {},
		Items = ItemLogic.empty(),
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

	local money = raw.Money
	if money == nil then
		result.Money = EconomyConfig.StartingMoney
	elseif isFiniteNumber(money) and money >= 0 then
		result.Money = math.min(money, MAX_ENERGY)
	else
		warn("[SaveService] Dinero guardado no válido (" .. tostring(money) .. "); se usa el valor inicial.")
		result.Money = EconomyConfig.StartingMoney
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

-- Núcleos guardados -> estructura válida. Antes de normalizar, los valores conocidos que
-- haya que corregir se añaden a CoresArchive con su valor original (y se escriben en el
-- mismo guardado que la corrección). El archivo existente se conserva entero; si no es
-- una lista, se conserva dentro de una entrada nueva.
local function sanitizeCores(raw: { [string]: any }, result: PetData)
	local rawArchive = raw.CoresArchive
	local copy = CoreLogic.storableCopy(rawArchive)
	local isList = type(copy) == "table"
	if isList then
		local count = 0
		for _ in copy do
			count += 1
		end
		isList = count == #copy
	end
	local archive = if isList then copy else {}
	local function append(changes: { [string]: any })
		if #archive >= MAX_CORES_ARCHIVE then
			warn("[SaveService] CoresArchive lleno: no se archivan más correcciones (se conservan las existentes).")
			return
		end
		table.insert(archive, {
			At = os.time(),
			Version = if isFiniteNumber(raw.Version) then raw.Version else nil,
			Changes = changes,
		})
	end
	if rawArchive ~= nil and not isList then
		append({ CoresArchive = if copy ~= nil then copy else tostring(rawArchive) })
	end

	result.Cores = CoreLogic.sanitize(raw.Cores)
	local changes = CoreLogic.corrections(raw.Cores, result.Cores)
	if changes then
		warn("[SaveService] Datos de núcleos no válidos: se corrigen y los originales se guardan en CoresArchive.")
		append(changes)
	end
	result.CoresArchive = archive
end

local function sanitize(raw: any): PetData
	local result = SaveService.emptyData()
	if type(raw) ~= "table" then
		return result
	end
	-- Las mascotas son solo las guardadas: la inicial de los datos vacíos no se añade aquí
	-- (si no tiene ninguna, PlayerDataService le da la inicial al cargar).
	result.Pets = {}
	result.Equipped = {}
	result.NextPetUid = 1

	-- Renacimiento primero: sus ventajas deciden cuántas mascotas puede haber equipadas. El
	-- pase «Más mascotas» aún no se conoce al cargar (lo consulta ShopService a Roblox): se
	-- conservan hasta las que permitiría y ShopService quita las de más si no lo tiene.
	result.Rebirth = RebirthLogic.sanitize(raw.Rebirth)
	local maxEquipped = RebirthLogic.maxEquipped(result.Rebirth, PetConfig.MaxEquipped) + MonetizationLogic.petSlotBonus({ PetSpace = true })

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
			if type(uid) == "string" and valid[uid] and not table.find(result.Equipped, uid) and #result.Equipped < maxEquipped then
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
	-- Núcleos: las partidas v2 no los tienen y empiezan solo con Naturaleza.
	sanitizeCores(raw, result)
	-- Último guardado (base de la producción offline). Sin él (o no válido): 0, nada
	-- retroactivo.
	local lastSeen = raw.LastSeen
	result.LastSeen = if isFiniteNumber(lastSeen) and lastSeen > 0 and lastSeen <= 1e10 then math.floor(lastSeen) else 0
	-- Aventuras: las partidas v4 (o anteriores) no las tienen y empiezan vacías.
	result.Adventure = AdventureLogic.sanitize(raw.Adventure)
	-- Premios, tienda y semana: las partidas v5 (o anteriores) no los tienen.
	result.Rewards = RewardLogic.sanitize(raw.Rewards)
	result.Shop = MonetizationLogic.sanitize(raw.Shop)
	result.Weekly = LeaderboardLogic.sanitizeWeekly(raw.Weekly)
	-- Armas: sin el campo (v7 o anteriores) empieza con el láser, al nivel de la antigua
	-- mejora "Potencia del Láser" (UpgradeLevels.LaserPower) si la tenía.
	result.Weapons = WeaponLogic.sanitize(raw.Weapons)
	if raw.Weapons == nil and type(raw.UpgradeLevels) == "table" and isFiniteNumber(raw.UpgradeLevels.LaserPower) then
		result.Weapons.Levels[WeaponConfig.StarterWeapon] = math.clamp(math.floor(raw.UpgradeLevels.LaserPower), 0, WeaponConfig.MaxLevel)
	end
	-- Jefes derrotados: tipo -> veces (enteros >= 0)
	if type(raw.Bosses) == "table" then
		local count = 0
		for typeId, kills in raw.Bosses do
			if type(typeId) == "string" and #typeId <= 64 and isFiniteNumber(kills) and kills >= 0 and count < 50 then
				result.Bosses[typeId] = math.min(math.floor(kills), 1e9)
				count += 1
			end
		end
	end
	-- Artículos: sin el campo (v8 o anteriores) empiezan vacíos. Las pociones activas siguen
	-- con el tiempo que les quedaba.
	result.Items = ItemLogic.sanitize(raw.Items, os.time())

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
	local money = if isFiniteNumber(data.Money) and data.Money >= 0 then math.min(data.Money, MAX_ENERGY) else nil
	local upgradeLevels = table.clone(data.ArchivedUpgrades)
	for upgradeId, level in data.UpgradeLevels do
		upgradeLevels[upgradeId] = level
	end
	local cores = CoreLogic.sanitize(data.Cores) -- copia nueva (y siempre válida)
	local coresArchive = CoreLogic.storableCopy(data.CoresArchive) or {}
	local rebirth = RebirthLogic.serialize(data.Rebirth)
	local adventure = AdventureLogic.serialize(data.Adventure)
	local rewards = RewardLogic.serialize(data.Rewards)
	local shop = MonetizationLogic.serialize(data.Shop)
	local weekly = LeaderboardLogic.serializeWeekly(data.Weekly)
	local weapons = WeaponLogic.serialize(data.Weapons)
	local bosses = table.clone(data.Bosses)
	local items = ItemLogic.serialize(data.Items or ItemLogic.empty(), os.time())
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
				if money ~= nil then
					stored.Money = money
				end
				stored.UpgradeLevels = upgradeLevels
				stored.Cores = cores
				if next(coresArchive) ~= nil then
					stored.CoresArchive = coresArchive
				end
				stored.LastSeen = os.time()
				stored.Rebirth = rebirth
				stored.Adventure = adventure
				stored.Rewards = rewards
				stored.Shop = shop
				stored.Weekly = weekly
				stored.Weapons = weapons
				stored.Bosses = bosses
				stored.Items = items
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
