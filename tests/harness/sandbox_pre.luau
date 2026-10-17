-- Interruptor y "¿estamos en Studio?" controlables por la prueba.
local isStudio = false
services.RunService = { IsStudio = function() return isStudio end }
local DevConfig = { TutorialSandbox = true, SandboxStartingEnergy = 3000 }
-- Cuenta TODAS las operaciones de DataStore (lectura, bloqueo y escritura pasan por aquí).
local storeCalls = 0
local getStoreCalls = 0
do
	local update = DataStoreStub.UpdateAsync
	DataStoreStub.UpdateAsync = function(...)
		storeCalls += 1
		return update(...)
	end
	local getStore = services.DataStoreService.GetDataStore
	services.DataStoreService.GetDataStore = function(...)
		getStoreCalls += 1
		return getStore(...)
	end
	for _, name in { "GetAsync", "SetAsync", "RemoveAsync", "IncrementAsync" } do
		DataStoreStub[name] = function() storeCalls += 1 error("operación no esperada: " .. name) end
	end
end
