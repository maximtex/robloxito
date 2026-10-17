-- Servicios simulados alrededor del QuestService real.
local profiles = {}
local readyListener, defeatListener, producedListener, abilityListener
local saveCalls = 0
local PlayerDataService = {
	get = function(p) return profiles[p] end,
	isPetDataReady = function(profile) return profile.DataState == "Loaded" or profile.DataState == "Unavailable" end,
	markDirty = function(p) if profiles[p] then profiles[p].Dirty = true end end,
	replicate = function() end,
	onPetDataReady = function(fn) readyListener = fn end,
	saveNow = function() saveCalls += 1 end,
}
local remotes = {}
local fired = {}
local RemoteService = {
	get = function(name)
		remotes[name] = remotes[name] or {
			OnServerEvent = signal(),
			FireClient = function(_, player, ...) table.insert(fired, { Name = name, Player = player, Args = { ... } }) end,
		}
		return remotes[name]
	end,
}
local EnemyService = { onDefeated = function(fn) defeatListener = fn end }
local EnergyService = { onProduced = function(fn) producedListener = fn end }
local PetCombatService = { onAbilityHit = function(fn) abilityListener = fn end }
local function lastState(p)
	for i = #fired, 1, -1 do
		if fired[i].Name == "QuestState" and fired[i].Player == p then return fired[i].Args[1] end
	end
	return nil
end
local function results(p)
	local out = {}
	for _, f in fired do
		if f.Name == "QuestResult" and f.Player == p then table.insert(out, f.Args) end
	end
	return out
end
local function fireServer(name, p, ...)
	remotes[name].OnServerEvent:Fire(p, ...)
end
local tmpKey = 500
local function SaveServiceSanitize(raw)
	if raw == nil then return SaveService.emptyData() end
	tmpKey += 1
	storeData["player_" .. tmpKey] = raw
	local _, d = SaveService.load(tmpKey)
	return d
end
