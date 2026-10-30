-- Lógica pura de misiones y logros (sin APIs de Roblox), para poder probarla fuera de
-- Studio. La usa QuestService (eventos, reclamaciones) y SaveService (sanear al cargar).
--
-- Garantías:
-- - El progreso solo sale de eventos que crea el servidor (record) y del estado del
--   perfil (ctx). Nada viene del cliente.
-- - Una misión cumplida queda marcada (Done) aunque el estado baje después (p. ej. se
--   gasta energía): no se pierde lo conseguido.
-- - Reclamar marca la misión antes de devolver la recompensa, sin pausas entre la
--   comprobación y la marca: dos solicitudes seguidas no pueden cobrar dos veces.
-- - Las recompensas de misiones no se registran como progreso (no hay ciclos).
-- - Los logros se marcan una sola vez; su recompensa (si tienen) se devuelve solo en el
--   momento de marcarlos.

local QuestLogic = {}

local QuestConfig: any
local EnemyConfig: any

-- Dependencias (inyectadas para poder probarla fuera de Roblox).
function QuestLogic.init(questConfig: any, enemyConfig: any)
	QuestConfig = questConfig
	EnemyConfig = enemyConfig
	QuestLogic.Missions = {}
	QuestLogic.Daily = {}
	QuestLogic.Weekly = {}
	QuestLogic.Achievements = {}
	for _, def in questConfig.Missions do
		QuestLogic.Missions[def.Id] = def
	end
	for _, def in questConfig.Daily do
		QuestLogic.Daily[def.Id] = def
	end
	for _, def in questConfig.Weekly or {} do
		QuestLogic.Weekly[def.Id] = def
	end
	for _, def in questConfig.Achievements do
		QuestLogic.Achievements[def.Id] = def
	end
end

export type QuestData = {
	Stats: { [string]: any },
	Done: { [string]: boolean },
	Claimed: { [string]: boolean },
	Achievements: { [string]: boolean },
	Daily: { Day: number, Ids: { string }, Progress: { [string]: number }, Claimed: { [string]: boolean }, Notified: { [string]: boolean } },
	-- Retos de la semana (QuestConfig.Weekly) y si ya se abrió su cofre
	Weekly: { Week: number, Ids: { string }, Progress: { [string]: number }, Claimed: { [string]: boolean }, Notified: { [string]: boolean }, Chest: boolean },
}

-- Estado del perfil que usan las misiones de tipo "State".
export type Context = {
	WeaponLevel: number?, -- nivel del arma más mejorada (sin el campo cuenta como 0)
	PetsOwned: number,
	PetsEquipped: number,
	CombatPetsOwned: number,
	ZonesUnlocked: number,
	UnlockedZones: { [string]: boolean },
	Rebirths: number?, -- renacimientos hechos (sin el campo cuenta como 0)
	BodyUpgrades: number?, -- niveles de ⚡ Mejoras del cuerpo: Velocidad, Vitalidad y Armadura (tutorial)
}

-- WaveWins: partidas de oleadas ganadas (también la de práctica del tutorial).
local STAT_KEYS = { "Kills", "StrongKills", "BossKills", "DiamondsEarned", "PetAbilities", "WaveWins" }
local MAX_NUMBER = 1e15
local MAX_SET = 500
local MAX_MAP = 64

function QuestLogic.empty(): QuestData
	local stats: { [string]: any } = { TypeKills = {}, ZoneKills = {} }
	for _, key in STAT_KEYS do
		stats[key] = 0
	end
	return {
		Stats = stats,
		Done = {},
		Claimed = {},
		Achievements = {},
		Daily = { Day = 0, Ids = {}, Progress = {}, Claimed = {}, Notified = {} },
		Weekly = { Week = 0, Ids = {}, Progress = {}, Claimed = {}, Notified = {}, Chest = false },
	}
end

-- Saneamiento ---------------------------------------------------------------------------

local function cleanNumber(value: any): number
	if type(value) ~= "number" or value ~= value or value < 0 then
		return 0
	end
	return math.min(value, MAX_NUMBER)
end

local function cleanId(value: any): string?
	if type(value) == "string" and #value > 0 and #value <= 64 then
		return value
	end
	return nil
end

-- Acepta { id = true } o { "id", ... }. Conserva ids desconocidos (no borra progreso de
-- misiones retiradas de la configuración).
local function cleanSet(raw: any): { [string]: boolean }
	local result = {}
	local count = 0
	if type(raw) ~= "table" then
		return result
	end
	for key, value in raw do
		local id = if type(key) == "string" and value == true then cleanId(key) elseif type(key) == "number" then cleanId(value) else nil
		if id and not result[id] and count < MAX_SET then
			result[id] = true
			count += 1
		end
	end
	return result
end

local function cleanMap(raw: any): { [string]: number }
	local result = {}
	local count = 0
	if type(raw) ~= "table" then
		return result
	end
	for key, value in raw do
		local id = cleanId(key)
		if id and count < MAX_MAP then
			result[id] = cleanNumber(value)
			count += 1
		end
	end
	return result
end

-- Datos guardados (o ausentes en partidas antiguas) -> estructura válida.
-- Nombres de antes del guardado v17 (la ⚡ / los 💎 se llamaban Energy): se leen con el nuevo.
local LEGACY_STATS = { DiamondsEarned = "EnergyEarned" }
local LEGACY_IDS = { EarnEnergy = "EarnDiamonds", DailyEnergy = "DailyDiamonds" }

local function renameIds(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, item in value do
		local newKey = if type(key) == "string" then LEGACY_IDS[key] or key else key
		local newItem = if type(item) == "string" then LEGACY_IDS[item] or item else item
		if out[newKey] == nil then
			out[newKey] = newItem
		end
	end
	return out
end

function QuestLogic.sanitize(raw: any): QuestData
	local data = QuestLogic.empty()
	if type(raw) ~= "table" then
		return data
	end
	if type(raw.Stats) == "table" then
		for _, key in STAT_KEYS do
			local value = raw.Stats[key]
			if value == nil and LEGACY_STATS[key] then
				value = raw.Stats[LEGACY_STATS[key]]
			end
			data.Stats[key] = cleanNumber(value)
		end
		data.Stats.TypeKills = cleanMap(raw.Stats.TypeKills)
		data.Stats.ZoneKills = cleanMap(raw.Stats.ZoneKills)
	end
	data.Done = cleanSet(renameIds(raw.Done))
	data.Claimed = cleanSet(renameIds(raw.Claimed))
	data.Achievements = cleanSet(raw.Achievements)
	if type(raw.Daily) == "table" then
		local day = raw.Daily.Day
		data.Daily.Day = if type(day) == "number" and day == day and day >= 0 and day < 1e7 then math.floor(day) else 0
		if type(raw.Daily.Ids) == "table" then
			for _, id in raw.Daily.Ids do
				local clean = cleanId(if type(id) == "string" then LEGACY_IDS[id] or id else id)
				if clean and not table.find(data.Daily.Ids, clean) and #data.Daily.Ids < 10 then
					table.insert(data.Daily.Ids, clean)
				end
			end
		end
		data.Daily.Progress = cleanMap(renameIds(raw.Daily.Progress))
		data.Daily.Claimed = cleanSet(renameIds(raw.Daily.Claimed))
		data.Daily.Notified = cleanSet(renameIds(raw.Daily.Notified))
	end
	if type(raw.Weekly) == "table" then
		local week = raw.Weekly.Week
		data.Weekly.Week = if type(week) == "number" and week == week and week >= 0 and week < 1e7 then math.floor(week) else 0
		if type(raw.Weekly.Ids) == "table" then
			for _, id in raw.Weekly.Ids do
				local clean = cleanId(id)
				if clean and not table.find(data.Weekly.Ids, clean) and #data.Weekly.Ids < 10 then
					table.insert(data.Weekly.Ids, clean)
				end
			end
		end
		data.Weekly.Progress = cleanMap(raw.Weekly.Progress)
		data.Weekly.Claimed = cleanSet(raw.Weekly.Claimed)
		data.Weekly.Notified = cleanSet(raw.Weekly.Notified)
		data.Weekly.Chest = raw.Weekly.Chest == true
	end
	return data
end

-- Copia para guardar (tablas nuevas: lo guardado no cambia si el perfil sigue cambiando).
function QuestLogic.serialize(data: QuestData): any
	local stats = table.clone(data.Stats)
	stats.TypeKills = table.clone(data.Stats.TypeKills)
	stats.ZoneKills = table.clone(data.Stats.ZoneKills)
	return {
		Stats = stats,
		Done = table.clone(data.Done),
		Claimed = table.clone(data.Claimed),
		Achievements = table.clone(data.Achievements),
		Daily = {
			Day = data.Daily.Day,
			Ids = table.clone(data.Daily.Ids),
			Progress = table.clone(data.Daily.Progress),
			Claimed = table.clone(data.Daily.Claimed),
			Notified = table.clone(data.Daily.Notified),
		},
		Weekly = {
			Week = data.Weekly.Week,
			Ids = table.clone(data.Weekly.Ids),
			Progress = table.clone(data.Weekly.Progress),
			Claimed = table.clone(data.Weekly.Claimed),
			Notified = table.clone(data.Weekly.Notified),
			Chest = data.Weekly.Chest == true,
		},
	}
end

-- Recompensas -----------------------------------------------------------------------------

-- Factor de las recompensas: el más alto de QuestConfig.ZoneFactor entre las zonas abiertas
-- del contexto (1 si no hay ninguna).
function QuestLogic.rewardFactor(ctx: Context): number
	local best = 1
	for zoneId, factor in QuestConfig.ZoneFactor or {} do
		if ctx.UnlockedZones[zoneId] and type(factor) == "number" and factor == factor and factor < math.huge then
			best = math.max(best, factor)
		end
	end
	return best
end

-- 💎 de una misión con el factor de la mejor zona: min(Min · factor, Max) · RewardScale
-- (como mínimo 1 si la misión da algo).
function QuestLogic.reward(def: any, factor: number): number
	local settings = def.Reward
	if not settings then
		return 0
	end
	local f = if type(factor) == "number" and factor == factor and factor > 0 and factor < math.huge then factor else 1
	local scale = QuestConfig.RewardScale
	scale = if type(scale) == "number" and scale == scale and scale > 0 and scale < math.huge then scale else 1
	local base = math.clamp(settings.Min * f, settings.Min, settings.Max)
	if base <= 0 then
		return 0
	end
	return math.max(1, math.floor(base * scale))
end

-- Progreso -------------------------------------------------------------------------------

local function bossTypes(data: QuestData): number
	local count = 0
	for typeId, kills in data.Stats.TypeKills do
		local def = EnemyConfig.Types[typeId]
		if def and def.Kind == "Boss" and kills > 0 then
			count += 1
		end
	end
	return count
end

function QuestLogic.progress(def: any, data: QuestData, ctx: Context): number
	local goal = def.Goal
	local value = 0
	if goal.Source == "Stat" then
		value = data.Stats[goal.Key] or 0
	elseif goal.Source == "ZoneKills" then
		value = data.Stats.ZoneKills[goal.Zone] or 0
	elseif goal.Source == "BossTypes" then
		value = bossTypes(data)
	elseif goal.Source == "State" then
		value = (ctx :: any)[goal.Key] or 0
	elseif goal.Source == "Daily" then
		value = data.Daily.Progress[def.Id] or 0
	elseif goal.Source == "Weekly" then
		value = data.Weekly.Progress[def.Id] or 0
	end
	return math.min(value, def.Target)
end

local function isLocked(def: any, ctx: Context): boolean
	return def.RequiresZone ~= nil and not ctx.UnlockedZones[def.RequiresZone]
end

-- Diarias ---------------------------------------------------------------------------------

function QuestLogic.dayOf(serverTime: number): number
	return math.floor(serverTime / QuestConfig.DaySeconds)
end

local function eligibleDaily(def: any, ctx: Context): boolean
	if isLocked(def, ctx) then
		return false
	end
	if def.RequiresCombatPet and ctx.CombatPetsOwned <= 0 then
		return false
	end
	return true
end

-- Generador determinista (mismo día + mismo jugador = mismas diarias en cualquier servidor).
local function seeded(day: number, userId: number): () -> number
	local state = (day * 7919 + userId * 104729) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end

-- Cambia las diarias si ha empezado un día nuevo. Nunca retrocede: si el reloj de otro
-- servidor iba adelantado, se mantienen las guardadas hasta que llegue ese día.
-- Las diarias del día anterior sin reclamar se pierden (política del reinicio).
function QuestLogic.ensureDay(data: QuestData, day: number, userId: number, ctx: Context): boolean
	if data.Daily.Day > day or (data.Daily.Day == day and #data.Daily.Ids > 0) then
		return false
	end
	local ids = {}
	for _, id in QuestConfig.DailyAlways do
		local def = QuestLogic.Daily[id]
		if def and eligibleDaily(def, ctx) and #ids < QuestConfig.DailyCount then
			table.insert(ids, id)
		end
	end
	local pool = {}
	for _, def in QuestConfig.Daily do
		if not table.find(ids, def.Id) and eligibleDaily(def, ctx) then
			table.insert(pool, def.Id)
		end
	end
	local random = seeded(day, userId)
	while #ids < QuestConfig.DailyCount and #pool > 0 do
		local index = math.floor(random() * #pool) + 1
		table.insert(ids, table.remove(pool, index))
	end
	data.Daily = { Day = day, Ids = ids, Progress = {}, Claimed = {}, Notified = {} }
	return true
end

-- Semanas ----------------------------------------------------------------------------------

-- Semana de una hora del servidor (empiezan el lunes a las 00:00 UTC).
function QuestLogic.weekOf(serverTime: number): number
	return math.floor((serverTime + (QuestConfig.WeekOffset or 0)) / (QuestConfig.WeekSeconds or 604800))
end

-- Hora del servidor en que empieza la semana siguiente.
function QuestLogic.weekEndsAt(week: number): number
	return (week + 1) * (QuestConfig.WeekSeconds or 604800) - (QuestConfig.WeekOffset or 0)
end

-- Como ensureDay, para los retos de la semana: los mismos para el jugador en cualquier
-- servidor; nunca retrocede; los de la semana anterior sin reclamar se pierden.
function QuestLogic.ensureWeek(data: QuestData, week: number, userId: number, ctx: Context): boolean
	local weekly = data.Weekly
	if weekly.Week > week or (weekly.Week == week and #weekly.Ids > 0) then
		return false
	end
	local count = QuestConfig.WeeklyCount or 3
	local ids = {}
	for _, id in QuestConfig.WeeklyAlways or {} do
		local def = QuestLogic.Weekly[id]
		if def and not isLocked(def, ctx) and #ids < count then
			table.insert(ids, id)
		end
	end
	local pool = {}
	for _, def in QuestConfig.Weekly or {} do
		if not table.find(ids, def.Id) and not isLocked(def, ctx) then
			table.insert(pool, def.Id)
		end
	end
	local random = seeded(week * 31 + 17, userId)
	while #ids < count and #pool > 0 do
		local index = math.floor(random() * #pool) + 1
		table.insert(ids, table.remove(pool, index))
	end
	data.Weekly = { Week = week, Ids = ids, Progress = {}, Claimed = {}, Notified = {}, Chest = false }
	return true
end

-- ¿Cuenta este evento para el objetivo de un reto semanal?
local function weeklyMatches(goal: any, event: any, kind: string?, zoneId: string?): boolean
	if goal.Event ~= event.Type then
		return false
	end
	if goal.Kind ~= nil and goal.Kind ~= kind then
		return false
	end
	if goal.Zone ~= nil and goal.Zone ~= zoneId then
		return false
	end
	if goal.Elite == true and event.Elite ~= true then
		return false
	end
	if event.Type == "WaveWin" then
		if event.Tutorial == true then
			return false
		end
		if goal.MinDifficulty ~= nil then
			local ranks = QuestConfig.DifficultyRank or {}
			local need = ranks[goal.MinDifficulty] or math.huge
			local have = (type(event.Difficulty) == "string" and ranks[event.Difficulty]) or 1
			if have < need then
				return false
			end
		end
		if goal.AnyMutator == true and not (type(event.Mutator) == "string" and #event.Mutator > 0) then
			return false
		end
	end
	return true
end

-- Eventos del servidor ----------------------------------------------------------------------

-- event = { Type = "Kill", TypeId, ZoneId } | { Type = "Diamonds", Amount } | { Type = "PetAbility" }
--   | { Type = "Upgrade" } (mejora de arma, guante o bastón comprada) | { Type = "Egg" } (huevo abierto)
--   | { Type = "WaveWin" } (partida de oleadas ganada)
-- Devuelve true si el evento era válido y se registró.
function QuestLogic.record(data: QuestData, event: any): boolean
	if type(event) ~= "table" then
		return false
	end
	local stats = data.Stats
	local amount = 1
	local kind, zoneId = nil, nil
	if event.Type == "Kill" then
		local def = EnemyConfig.Types[event.TypeId]
		if not def or type(event.ZoneId) ~= "string" or not EnemyConfig.Zones[event.ZoneId] then
			return false
		end
		kind, zoneId = def.Kind, event.ZoneId
		stats.Kills += 1
		if kind == "Strong" then
			stats.StrongKills += 1
		elseif kind == "Boss" then
			stats.BossKills += 1
		end
		stats.TypeKills[event.TypeId] = (stats.TypeKills[event.TypeId] or 0) + 1
		stats.ZoneKills[zoneId] = (stats.ZoneKills[zoneId] or 0) + 1
	elseif event.Type == "Diamonds" then
		amount = event.Amount
		if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount > 1e9 then
			return false
		end
		stats.DiamondsEarned = math.min(stats.DiamondsEarned + amount, MAX_NUMBER)
	elseif event.Type == "PetAbility" then
		stats.PetAbilities += 1
	elseif event.Type == "WaveWin" then
		stats.WaveWins += 1
	elseif event.Type == "Upgrade" or event.Type == "Egg" or event.Type == "MapEvent" then
		-- Solo cuentan para las diarias y los retos (sin estadística permanente).
	elseif event.Type == "WaveCleared" then
		-- Solo para los retos semanales: la oleada más alta superada
		amount = event.Wave
		if type(amount) ~= "number" or amount ~= amount or amount < 1 or amount > 1e6 then
			return false
		end
	else
		return false
	end

	-- Diarias activas a las que cuenta este evento
	for _, id in data.Daily.Ids do
		local def = QuestLogic.Daily[id]
		local goal = def and def.Goal
		if goal and goal.Event == event.Type and (goal.Kind == nil or goal.Kind == kind) and (goal.Zone == nil or goal.Zone == zoneId) then
			data.Daily.Progress[id] = math.min((data.Daily.Progress[id] or 0) + amount, def.Target)
		end
	end
	-- Retos de la semana
	for _, id in data.Weekly.Ids do
		local def = QuestLogic.Weekly[id]
		local goal = def and def.Goal
		if goal and weeklyMatches(goal, event, kind, zoneId) then
			local current = data.Weekly.Progress[id] or 0
			local value = if goal.Max then math.max(current, amount) else current + amount
			data.Weekly.Progress[id] = math.min(value, def.Target)
		end
	end
	return true
end

-- Evaluación: marca misiones cumplidas y desbloquea logros. Devuelve los avisos nuevos
-- ({ Type = "Mission" | "Daily" | "Achievement", Id, Reward? }); los logros con
-- recompensa la incluyen y es la ÚNICA vez que se devuelve.
function QuestLogic.evaluate(data: QuestData, ctx: Context): { any }
	local notices = {}
	for _, def in QuestConfig.Missions do
		if not data.Done[def.Id] and not isLocked(def, ctx) and QuestLogic.progress(def, data, ctx) >= def.Target then
			data.Done[def.Id] = true
			if not data.Claimed[def.Id] then
				table.insert(notices, { Type = "Mission", Id = def.Id })
			end
		end
	end
	for _, id in data.Daily.Ids do
		local def = QuestLogic.Daily[id]
		if def and not data.Daily.Notified[id] and QuestLogic.progress(def, data, ctx) >= def.Target then
			data.Daily.Notified[id] = true -- aviso una sola vez por día
			table.insert(notices, { Type = "Daily", Id = id })
		end
	end
	for _, id in data.Weekly.Ids do
		local def = QuestLogic.Weekly[id]
		if def and not data.Weekly.Notified[id] and QuestLogic.progress(def, data, ctx) >= def.Target then
			data.Weekly.Notified[id] = true -- aviso una sola vez por semana
			table.insert(notices, { Type = "Weekly", Id = id })
		end
	end
	for _, def in QuestConfig.Achievements do
		if not data.Achievements[def.Id] and QuestLogic.progress(def, data, ctx) >= def.Target then
			data.Achievements[def.Id] = true
			table.insert(notices, { Type = "Achievement", Id = def.Id, Reward = QuestLogic.reward(def, QuestLogic.rewardFactor(ctx)) })
		end
	end
	return notices
end

-- Reclamar ---------------------------------------------------------------------------------

-- Devuelve (código, energía). Solo "Success" concede energía, y la misión queda marcada
-- antes de devolverla.
function QuestLogic.claim(data: QuestData, questId: any, ctx: Context): (string, number)
	if type(questId) ~= "string" or #questId == 0 or #questId > QuestConfig.MaxIdLength then
		return "InvalidRequest", 0
	end
	local mission = QuestLogic.Missions[questId]
	if mission then
		if data.Claimed[questId] then
			return "AlreadyClaimed", 0
		end
		if isLocked(mission, ctx) then
			return "Locked", 0
		end
		if not data.Done[questId] and QuestLogic.progress(mission, data, ctx) < mission.Target then
			return "NotComplete", 0
		end
		data.Done[questId] = true
		data.Claimed[questId] = true
		return "Success", QuestLogic.reward(mission, QuestLogic.rewardFactor(ctx))
	end
	local daily = QuestLogic.Daily[questId]
	if daily and table.find(data.Daily.Ids, questId) then
		if data.Daily.Claimed[questId] then
			return "AlreadyClaimed", 0
		end
		if QuestLogic.progress(daily, data, ctx) < daily.Target then
			return "NotComplete", 0
		end
		data.Daily.Claimed[questId] = true
		return "Success", QuestLogic.reward(daily, QuestLogic.rewardFactor(ctx))
	end
	local weekly = QuestLogic.Weekly[questId]
	if weekly and table.find(data.Weekly.Ids, questId) then
		if data.Weekly.Claimed[questId] then
			return "AlreadyClaimed", 0
		end
		if QuestLogic.progress(weekly, data, ctx) < weekly.Target then
			return "NotComplete", 0
		end
		data.Weekly.Claimed[questId] = true
		return "Success", QuestLogic.reward(weekly, QuestLogic.rewardFactor(ctx))
	end
	local chest = QuestConfig.WeeklyChest
	if chest and questId == chest.Id then
		if data.Weekly.Chest then
			return "AlreadyClaimed", 0
		end
		if QuestLogic.weeklyClaimed(data) < #data.Weekly.Ids or #data.Weekly.Ids == 0 then
			return "NotComplete", 0
		end
		data.Weekly.Chest = true
		return "Success", QuestLogic.reward(chest, QuestLogic.rewardFactor(ctx))
	end
	-- Diarias de otro día, retos de otra semana, logros (se conceden solos) o ids inventados.
	return "InvalidRequest", 0
end

-- Retos de la semana ya reclamados.
function QuestLogic.weeklyClaimed(data: QuestData): number
	local count = 0
	for _, id in data.Weekly.Ids do
		if data.Weekly.Claimed[id] then
			count += 1
		end
	end
	return count
end

-- Estado para la interfaz ---------------------------------------------------------------------

local function status(claimed: boolean, done: boolean, locked: boolean): string
	if claimed then
		return "Claimed"
	elseif locked then
		return "Locked"
	elseif done then
		return "Ready"
	end
	return "Active"
end

function QuestLogic.snapshot(data: QuestData, ctx: Context, day: number, week: number?): any
	local missions, daily, weekly, achievements = {}, {}, {}, {}
	for _, def in QuestConfig.Missions do
		local progress = QuestLogic.progress(def, data, ctx)
		local done = data.Done[def.Id] == true or progress >= def.Target
		table.insert(missions, {
			Id = def.Id,
			Progress = if done then def.Target else progress,
			Target = def.Target,
			Reward = QuestLogic.reward(def, QuestLogic.rewardFactor(ctx)),
			Status = status(data.Claimed[def.Id] == true, done, isLocked(def, ctx)),
		})
	end
	for _, id in data.Daily.Ids do
		local def = QuestLogic.Daily[id]
		if def then
			local progress = QuestLogic.progress(def, data, ctx)
			table.insert(daily, {
				Id = id,
				Progress = progress,
				Target = def.Target,
				Reward = QuestLogic.reward(def, QuestLogic.rewardFactor(ctx)),
				Status = status(data.Daily.Claimed[id] == true, progress >= def.Target, false),
			})
		end
	end
	for _, id in data.Weekly.Ids do
		local def = QuestLogic.Weekly[id]
		if def then
			local progress = QuestLogic.progress(def, data, ctx)
			table.insert(weekly, {
				Id = id,
				Progress = progress,
				Target = def.Target,
				Reward = QuestLogic.reward(def, QuestLogic.rewardFactor(ctx)),
				Status = status(data.Weekly.Claimed[id] == true, progress >= def.Target, false),
			})
		end
	end
	local chest = QuestConfig.WeeklyChest
	if chest and #data.Weekly.Ids > 0 then
		local claimed = QuestLogic.weeklyClaimed(data)
		table.insert(weekly, {
			Id = chest.Id,
			Progress = claimed,
			Target = #data.Weekly.Ids,
			Reward = QuestLogic.reward(chest, QuestLogic.rewardFactor(ctx)),
			Status = status(data.Weekly.Chest == true, claimed >= #data.Weekly.Ids, false),
		})
	end
	for _, def in QuestConfig.Achievements do
		local unlocked = data.Achievements[def.Id] == true
		table.insert(achievements, {
			Id = def.Id,
			Progress = if unlocked then def.Target else QuestLogic.progress(def, data, ctx),
			Target = def.Target,
			Reward = if def.Reward then QuestLogic.reward(def, QuestLogic.rewardFactor(ctx)) else 0,
			Unlocked = unlocked,
		})
	end
	return {
		Ready = true,
		Day = day,
		ResetAt = (day + 1) * QuestConfig.DaySeconds,
		Missions = missions,
		Daily = daily,
		Weekly = weekly,
		WeekResetAt = if week then QuestLogic.weekEndsAt(week) else nil,
		Achievements = achievements,
	}
end

-- En Roblox se inicializa solo; las pruebas llaman a init con sus propias tablas.
if typeof(script) == "Instance" then
	local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	QuestLogic.init(require(Shared.Config.QuestConfig), require(Shared.Config.EnemyConfig))
end

return QuestLogic
