-- Clasificación pura (sin APIs de Roblox):
-- - rank: ordena las entradas de mayor a menor valor (con desempate opcional y, al final,
--   por nombre para que el orden sea estable) y devuelve las primeras `rows`.
--   Entradas: { Name, Value, Tie? }; se ignoran valores no numéricos o NaN.
-- - Semana: número de semana (empiezan el lunes a las 00:00 UTC) y la energía generada en
--   la semana, que se guarda en el campo Weekly del registro { Week, Energy } y se publica
--   en la clasificación semanal global.

local LeaderboardLogic = {}

local function valid(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function LeaderboardLogic.rank(entries: { any }, rows: number): { any }
	local list = {}
	for _, entry in entries do
		if type(entry) == "table" and type(entry.Name) == "string" and valid(entry.Value) then
			table.insert(list, { Name = entry.Name, Value = entry.Value, Tie = if valid(entry.Tie) then entry.Tie else 0 })
		end
	end
	table.sort(list, function(a, b)
		if a.Value ~= b.Value then
			return a.Value > b.Value
		end
		if a.Tie ~= b.Tie then
			return a.Tie > b.Tie
		end
		return a.Name < b.Name
	end)
	local top = {}
	for index = 1, math.min(rows, #list) do
		top[index] = list[index]
	end
	return top
end

-- Semana --------------------------------------------------------------------------------

local WEEK = 7 * 86400
local MONDAY_OFFSET = 3 * 86400 -- el 1 de enero de 1970 fue jueves

function LeaderboardLogic.weekOf(serverTime: number): number
	return math.floor((serverTime + MONDAY_OFFSET) / WEEK)
end

-- Hora del servidor en que termina una semana (empieza la siguiente).
function LeaderboardLogic.weekEndsAt(week: number): number
	return (week + 1) * WEEK - MONDAY_OFFSET
end

export type Weekly = { Week: number, Energy: number }

function LeaderboardLogic.emptyWeekly(): Weekly
	return { Week = 0, Energy = 0 }
end

function LeaderboardLogic.sanitizeWeekly(raw: any): Weekly
	local data = LeaderboardLogic.emptyWeekly()
	if type(raw) == "table" and valid(raw.Week) and valid(raw.Energy) and raw.Week >= 0 and raw.Energy >= 0 then
		data.Week = math.floor(raw.Week)
		data.Energy = math.min(raw.Energy, 1e15)
	end
	return data
end

function LeaderboardLogic.serializeWeekly(data: Weekly): any
	return { Week = data.Week, Energy = data.Energy }
end

-- Suma energía generada en la semana `week`. Una semana nueva empieza de cero; si el reloj
-- de este servidor va atrasado (semana guardada posterior), se suma a la guardada.
function LeaderboardLogic.addWeekly(data: Weekly, week: number, amount: number)
	if not valid(amount) or amount <= 0 then
		return
	end
	if week > data.Week then
		data.Week = week
		data.Energy = 0
	end
	data.Energy = math.min(data.Energy + amount, 1e15)
end

function LeaderboardLogic.weeklyValue(data: Weekly?, week: number): number
	if type(data) == "table" and data.Week == week and valid(data.Energy) then
		return data.Energy
	end
	return 0
end

-- Valor para una clasificación global (OrderedDataStore solo guarda enteros >= 0).
function LeaderboardLogic.storeValue(value: any): number?
	if not valid(value) or value < 0 then
		return nil
	end
	return math.floor(math.min(value, 1e15))
end

return LeaderboardLogic
