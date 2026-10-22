-- Avisos entre servicios del servidor sin que dependan unos de otros: quien hace algo lo
-- anuncia (fire) y quien quiera reaccionar se suscribe (on). Lo usan las misiones diarias
-- para contar las mejoras compradas (UpgradePurchased).
-- Puro (sin APIs de Roblox): las pruebas lo cargan tal cual.

local GameEvents = {}

local listeners: { [string]: { (...any) -> () } } = {}

function GameEvents.on(name: string, listener: (...any) -> ())
	local list = listeners[name]
	if not list then
		list = {}
		listeners[name] = list
	end
	table.insert(list, listener)
end

-- Llama a cada oyente en orden; un error en uno no impide avisar a los demás.
function GameEvents.fire(name: string, ...: any)
	for _, listener in listeners[name] or {} do
		local ok, err = pcall(listener, ...)
		if not ok then
			print(("[GameEvents] Error en un oyente de %s: %s"):format(name, tostring(err)))
		end
	end
end

return GameEvents
