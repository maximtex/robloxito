-- Remotes y servicios de combate simulados alrededor de los servicios REALES.
local remotes = {}
local fired = {}
local RemoteService = {
	start = function() end,
	get = function(name)
		remotes[name] = remotes[name] or {
			OnServerEvent = signal(),
			FireClient = function(_, player, ...) table.insert(fired, { Name = name, Player = player, Args = { ... } }) end,
		}
		return remotes[name]
	end,
}
local function fireServer(name, player, ...)
	RemoteService.get(name).OnServerEvent:Fire(player, ...)
end
local function lastResult(name, player)
	for i = #fired, 1, -1 do
		if fired[i].Name == name and fired[i].Player == player then return fired[i].Args end
	end
	return nil
end
-- Enemigos simulados: las pruebas anuncian derrotas como lo haría EnemyService
local defeatListeners = {}
local EnemyService = { onDefeated = function(fn) table.insert(defeatListeners, fn) end }
local function defeat(player, typeId, kind)
	for _, fn in defeatListeners do
		fn(player, { TypeId = typeId, Kind = kind or "Normal", ZoneId = "Forest", Reward = 25 })
	end
end
local PetCombatService = { onAbilityHit = function() end }
