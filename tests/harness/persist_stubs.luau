-- Entorno simulado con planificador de corrutinas (task.spawn/wait/delay como en Roblox)
-- y DataStore en memoria con latencia y fallos controlables.
-- 💰 que se devuelve al cargar por una Resonancia del Cristal de nivel `level` (guardado
-- v16, SaveService.refundRetired): lo que costaba, floor(60 · 1,45^n) por nivel.
function resonanceRefund(level)
	local total = 0
	for n = 0, level - 1 do
		total += math.floor(60 * 1.45 ^ n)
	end
	return total
end
Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end, new = function(r, g, b) return { R = r, G = g, B = b } end }
Vector2 = { new = function(x, y) return { X = x, Y = y } end }
Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }

local clock = 0
local serverTime = 20000 * 86400 + 3600
os = {
	clock = function() return clock end,
	time = function() return math.floor(serverTime + clock) end,
}
local warnings = {}
warn = function(...)
	local parts = {}
	for _, v in { ... } do table.insert(parts, tostring(v)) end
	table.insert(warnings, table.concat(parts, " "))
end

local sleeping = {}
local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		error("error en una tarea: " .. tostring(err))
	end
end
task = {
	spawn = function(fn, ...)
		local co = coroutine.create(fn)
		resume(co, ...)
		return co
	end,
	wait = function(seconds)
		local co = coroutine.running()
		table.insert(sleeping, { Co = co, At = clock + (seconds or 0) })
		return coroutine.yield()
	end,
	delay = function(seconds, fn, ...)
		local args = { ... }
		table.insert(sleeping, { Fn = function() fn(table.unpack(args)) end, At = clock + (seconds or 0) })
	end,
}
-- Avanza el reloj y despierta lo que toque (en orden).
local function advance(seconds)
	local target = clock + seconds
	while true do
		local nextIndex, nextAt = nil, math.huge
		for i, s in sleeping do
			if s.At <= target and s.At < nextAt then
				nextIndex, nextAt = i, s.At
			end
		end
		if not nextIndex then break end
		local item = table.remove(sleeping, nextIndex)
		clock = math.max(clock, item.At)
		if item.Co then resume(item.Co) else task.spawn(item.Fn) end
	end
	clock = target
end

local function signal()
	local listeners = {}
	return {
		Connect = function(_, fn) table.insert(listeners, fn) return { Disconnect = function() end } end,
		Fire = function(_, ...) for _, fn in listeners do task.spawn(fn, ...) end end,
	}
end

-- DataStore en memoria: latencia (segundos) y fallos programables.
local storeData = {}
local storeLatency = 0
local storeFail = 0 -- las próximas N llamadas a UpdateAsync fallan
local storeWrites = 0
local function deep(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in value do out[k] = deep(v) end
	return out
end
local DataStoreStub = {
	UpdateAsync = function(_, key, transform)
		if storeLatency > 0 then task.wait(storeLatency) end
		if storeFail > 0 then
			storeFail -= 1
			error("simulated DataStore failure")
		end
		local result = transform(deep(storeData[key]))
		if result ~= nil then
			storeData[key] = deep(result)
			storeWrites += 1
		end
		return deep(storeData[key])
	end,
}

-- Instancias mínimas (la carpeta leaderstats): nombre, padre e hijos
local function findChild(self, childName)
	for _, child in self.Children do
		if child.Name == childName then
			return child
		end
	end
	return nil
end
local InstanceMeta = {
	__newindex = function(object, key, value)
		if key == "Parent" and type(value) == "table" and value.Children then
			table.insert(value.Children, object)
		end
		rawset(object, key, value)
	end,
}
Instance = {
	new = function(className)
		return setmetatable({ ClassName = className, Children = {}, FindFirstChild = findChild }, InstanceMeta)
	end,
}

-- Jugadores falsos con atributos (sin personaje: CharacterAdded no llega a dispararse)
local function newPlayer(name, userId)
	local attributes = {}
	local player = { Name = name, UserId = userId, Parent = true, Children = {}, FindFirstChild = findChild, CharacterAdded = signal() }
	function player.SetAttribute(_, k, v) attributes[k] = v end
	function player.GetAttribute(_, k) return attributes[k] end
	player.Attributes = attributes
	return player
end
local playersList = {}
local closeCallbacks = {}
local PlayersService = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return playersList end }
local services = {
	DataStoreService = { GetDataStore = function() return DataStoreStub end },
	Players = PlayersService,
	ReplicatedStorage = { WaitForChild = function() return {} end },
	-- Como un servidor publicado: el modo prueba (DevConfig) se ignora aunque esté en true.
	RunService = { IsStudio = function() return false end },
}
game = {
	JobId = "job-test",
	GetService = function(_, name) return services[name] or {} end,
	BindToClose = function(_, fn) table.insert(closeCallbacks, fn) end,
}
local function join(player)
	table.insert(playersList, player)
	PlayersService.PlayerAdded:Fire(player)
end
local function leave(player)
	table.remove(playersList, table.find(playersList, player))
	PlayersService.PlayerRemoving:Fire(player)
end
