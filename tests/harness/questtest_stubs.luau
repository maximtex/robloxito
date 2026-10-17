-- Entorno simulado para ejecutar QuestLogic, QuestService y SaveService REALES.
Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end, new = function(r, g, b) return { R = r, G = g, B = b } end }
Vector2 = { new = function(x, y) return { X = x, Y = y } end }
Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }

local clock = 0
local serverTime = 20000 * 86400 + 3600 -- día 20000, 01:00 UTC
local realOs = os
os = {
	clock = function() return clock end,
	time = function() return math.floor(serverTime) end,
}
task = {
	spawn = function(fn, ...) fn(...) end,
	wait = function() end,
	delay = function() end,
}
warn = function(...) end

local function signal()
	local listeners = {}
	return {
		Connect = function(_, fn) table.insert(listeners, fn) return { Disconnect = function() end } end,
		Fire = function(_, ...) for _, fn in listeners do fn(...) end end,
	}
end

-- DataStore en memoria (UpdateAsync con la misma semántica: devolver nil cancela).
local storeData = {}
local storeFailNext = 0
local DataStoreStub = {
	UpdateAsync = function(_, key, transform)
		if storeFailNext > 0 then
			storeFailNext -= 1
			error("simulated DataStore failure")
		end
		-- copia profunda simulada (como la serialización real)
		local function deep(value)
			if type(value) ~= "table" then return value end
			local out = {}
			for k, v in value do out[k] = deep(v) end
			return out
		end
		local result = transform(deep(storeData[key]))
		if result ~= nil then
			storeData[key] = deep(result)
		end
		return deep(storeData[key])
	end,
}
local services = {
	DataStoreService = { GetDataStore = function() return DataStoreStub end },
	Players = { PlayerRemoving = signal(), PlayerAdded = signal(), GetPlayers = function() return {} end },
}
game = { JobId = "job-test", GetService = function(_, name) return services[name] or {} end }
