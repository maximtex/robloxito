-- Lógica pura del premio diario y de los códigos (sin APIs de Roblox), para probarla fuera
-- de Studio. La usan RewardService (acciones) y SaveService (sanear y guardar el campo
-- Rewards del registro).
--
-- Datos guardados (campo Rewards):
--   Streak: número de días seguidos reclamados (1 = el primer día).
--   LastDay: día (os.time() // DaySeconds) del último premio reclamado; 0 = nunca.
--   Claims: premios diarios reclamados en total.
--   Codes: { [CÓDIGO] = true } códigos ya canjeados.
--   Chests: { [IdDelCofre] = hora del servidor en que se puede volver a abrir } (cofres
--   escondidos del Bosque, ChestConfig).
--
-- Garantías:
-- - Como mucho un premio por día: reclamar marca el día antes de devolver el premio.
-- - Si el reloj de un servidor va atrasado (LastDay en el futuro) no se reclama nada.
-- - Un código se canjea una vez por jugador; los intentos no válidos no cambian nada.
-- - Un cofre no se abre otra vez hasta que pasa su espera (se marca antes del premio).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RewardConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.RewardConfig)

local RewardLogic = {}

export type RewardData = {
	Streak: number,
	LastDay: number,
	Claims: number,
	Codes: { [string]: boolean },
	Chests: { [string]: number },
}

local MAX_COUNT = 1e9
local MAX_CHESTS = 64
local MAX_CHEST_ID = 32

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function cleanCount(value: any): number
	if isFiniteNumber(value) and value >= 0 then
		return math.min(math.floor(value), MAX_COUNT)
	end
	return 0
end

function RewardLogic.empty(): RewardData
	return { Streak = 0, LastDay = 0, Claims = 0, Codes = {}, Chests = {} }
end

function RewardLogic.sanitize(raw: any): RewardData
	local data = RewardLogic.empty()
	if type(raw) ~= "table" then
		return data
	end
	data.Streak = cleanCount(raw.Streak)
	data.LastDay = cleanCount(raw.LastDay)
	data.Claims = cleanCount(raw.Claims)
	if type(raw.Codes) == "table" then
		local count = 0
		for code, value in raw.Codes do
			if type(code) == "string" and #code > 0 and #code <= RewardConfig.Codes.MaxLength and value == true and count < RewardConfig.Codes.MaxStored then
				data.Codes[code] = true
				count += 1
			end
		end
	end
	if type(raw.Chests) == "table" then
		local count = 0
		for id, readyAt in raw.Chests do
			if type(id) == "string" and #id > 0 and #id <= MAX_CHEST_ID and isFiniteNumber(readyAt) and readyAt > 0 and count < MAX_CHESTS then
				data.Chests[id] = math.min(math.floor(readyAt), 4e9)
				count += 1
			end
		end
	end
	return data
end

function RewardLogic.serialize(data: RewardData): any
	return { Streak = data.Streak, LastDay = data.LastDay, Claims = data.Claims, Codes = table.clone(data.Codes), Chests = table.clone(data.Chests) }
end

function RewardLogic.ofProfile(profile: any): RewardData?
	local petData = type(profile) == "table" and profile.PetData
	local data = type(petData) == "table" and petData.Rewards
	return if type(data) == "table" then data else nil
end

-- Día (entero) de una hora del servidor.
function RewardLogic.dayOf(serverTime: number): number
	return math.floor(serverTime / RewardConfig.DaySeconds)
end

-- Hora del servidor en que empieza el día siguiente (para la cuenta atrás).
function RewardLogic.nextDayAt(serverTime: number): number
	return (RewardLogic.dayOf(serverTime) + 1) * RewardConfig.DaySeconds
end

function RewardLogic.cycleLength(): number
	return #RewardConfig.Streak
end

-- Posición (1..7) en la vuelta de un número de racha.
function RewardLogic.cycleDay(streak: number): number
	if streak <= 0 then
		return 1
	end
	return ((streak - 1) % RewardLogic.cycleLength()) + 1
end

-- Estado de la racha para un día:
--   CanClaim: hay premio por reclamar hoy.
--   NextStreak: racha que quedará al reclamar hoy (o mañana, si hoy ya se reclamó).
--   Day: casilla (1..7) del premio que toca reclamar (o la que se reclamó hoy).
--   ClaimedToday: hoy ya se reclamó.
--   Broken: la racha anterior se perdió (pasó más de un día sin reclamar).
function RewardLogic.status(data: RewardData, today: number): any
	local claimedToday = data.LastDay >= today and data.LastDay > 0
	if claimedToday then
		return { CanClaim = false, ClaimedToday = true, NextStreak = data.Streak + 1, Day = RewardLogic.cycleDay(data.Streak), Broken = false, Streak = data.Streak }
	end
	local continues = data.LastDay > 0 and data.LastDay == today - 1
	local nextStreak = if continues then data.Streak + 1 else 1
	return {
		CanClaim = true,
		ClaimedToday = false,
		NextStreak = nextStreak,
		Day = RewardLogic.cycleDay(nextStreak),
		Broken = data.Streak > 0 and not continues,
		Streak = if continues then data.Streak else 0,
	}
end

-- Reclama el premio de hoy. Devuelve el código y la casilla (1..7) reclamada.
function RewardLogic.claim(data: RewardData, today: number): (string, number?)
	local status = RewardLogic.status(data, today)
	if not status.CanClaim then
		return "AlreadyClaimed", nil
	end
	data.Streak = status.NextStreak
	data.LastDay = today
	data.Claims += 1
	return "Success", status.Day
end

-- Premio de una casilla de la racha.
function RewardLogic.streakReward(day: number): any
	return RewardConfig.Streak[day]
end

-- Energía de un premio de energía con la producción actual (por segundo).
function RewardLogic.energyAmount(spec: any, production: number): number
	if type(spec) ~= "table" then
		return 0
	end
	local minutes = if isFiniteNumber(spec.Minutes) and spec.Minutes > 0 then spec.Minutes else 0
	local floor = if isFiniteNumber(spec.Min) and spec.Min > 0 then spec.Min else 0
	local rate = if isFiniteNumber(production) and production > 0 then production else 0
	return math.floor(math.max(floor, rate * minutes * 60))
end

-- Códigos ---------------------------------------------------------------------------------

-- Texto escrito por el jugador -> código normalizado (MAYÚSCULAS, solo A-Z y 0-9), o nil si
-- no puede ser un código.
function RewardLogic.normalizeCode(text: any): string?
	if type(text) ~= "string" or #text == 0 or #text > 64 then
		return nil
	end
	local code = string.upper(text):gsub("[^%w]", "")
	if #code == 0 or #code > RewardConfig.Codes.MaxLength or code:find("[^A-Z0-9]") then
		return nil
	end
	return code
end

-- ¿Sigue vigente? `untilDate` = { Year, Month, Day } (último día, hora UTC).
function RewardLogic.isExpired(def: any, now: number): boolean
	local untilDate = def.Until
	if type(untilDate) ~= "table" then
		return false
	end
	-- Días desde 1970 de una fecha (calendario gregoriano), sin depender de la zona horaria.
	local y, m, d = untilDate.Year, untilDate.Month, untilDate.Day
	if not (isFiniteNumber(y) and isFiniteNumber(m) and isFiniteNumber(d)) then
		return true
	end
	y -= if m <= 2 then 1 else 0
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	local days = era * 146097 + doe - 719468
	local endsAt = (days + 1) * 86400 -- final de ese día (UTC)
	return now >= endsAt
end

-- Canjea un código. `codes` = lista del servidor (CodesConfig). Devuelve:
-- "Success" (y la definición), "InvalidCode", "Expired", "AlreadyRedeemed",
-- "RebirthLocked" (y los renacimientos que pide) o "Full".
function RewardLogic.redeem(data: RewardData, codes: any, text: any, now: number, rebirths: number): (string, any, string?)
	local code = RewardLogic.normalizeCode(text)
	local def = code and codes[code]
	if not code or type(def) ~= "table" then
		return "InvalidCode", nil, code
	end
	if data.Codes[code] then
		return "AlreadyRedeemed", nil, code
	end
	if RewardLogic.isExpired(def, now) then
		return "Expired", nil, code
	end
	if isFiniteNumber(def.MinRebirths) and (rebirths or 0) < def.MinRebirths then
		return "RebirthLocked", def.MinRebirths, code
	end
	local stored = 0
	for _ in data.Codes do
		stored += 1
	end
	if stored >= RewardConfig.Codes.MaxStored then
		return "Full", nil, code
	end
	data.Codes[code] = true
	return "Success", def, code
end

-- Cofres escondidos --------------------------------------------------------------------------

-- Hora del servidor en que el cofre se puede volver a abrir (0 = nunca abierto).
function RewardLogic.chestReadyAt(data: RewardData, chestId: string): number
	return data.Chests[chestId] or 0
end

function RewardLogic.canOpenChest(data: RewardData, chestId: string, now: number, cooldown: number): boolean
	local readyAt = RewardLogic.chestReadyAt(data, chestId)
	return now >= readyAt or readyAt - now > cooldown
end

-- Abre un cofre: marca la espera antes de devolver nada. Devuelve el código y la hora en
-- que se podrá abrir otra vez. Una marca imposible (reloj de otro servidor muy adelantado:
-- más allá de una espera completa) no bloquea el cofre para siempre.
function RewardLogic.openChest(data: RewardData, chestId: string, now: number, cooldown: number): (string, number)
	if not RewardLogic.canOpenChest(data, chestId, now, cooldown) then
		return "ChestCooldown", RewardLogic.chestReadyAt(data, chestId)
	end
	local nextAt = math.floor(now + cooldown)
	data.Chests[chestId] = nextAt
	return "Success", nextAt
end

-- Esperas pendientes de los cofres conocidos (para el cliente): { [Id] = ReadyAt }.
function RewardLogic.chestState(data: RewardData, chestIds: { string }, now: number, cooldown: number): { [string]: number }
	local state = {}
	for _, id in chestIds do
		local readyAt = RewardLogic.chestReadyAt(data, id)
		if not RewardLogic.canOpenChest(data, id, now, cooldown) then
			state[id] = readyAt
		end
	end
	return state
end

-- Lista de premios de la racha para mostrar (el cliente calcula la energía con su
-- producción; aquí van los datos tal cual).
function RewardLogic.snapshot(data: RewardData, serverTime: number, production: number): any
	local today = RewardLogic.dayOf(serverTime)
	local status = RewardLogic.status(data, today)
	local days = {}
	for index, reward in RewardConfig.Streak do
		days[index] = {
			Energy = if reward.Energy then RewardLogic.energyAmount(reward.Energy, production) else nil,
			Blessings = reward.Blessings,
			Pet = if type(reward.Pet) == "string" then reward.Pet else nil,
		}
	end
	return {
		Ready = true,
		CanClaim = status.CanClaim,
		ClaimedToday = status.ClaimedToday,
		Day = status.Day,
		Streak = status.Streak,
		Broken = status.Broken,
		Claims = data.Claims,
		NextDayAt = RewardLogic.nextDayAt(serverTime),
		Days = days,
	}
end

return RewardLogic
