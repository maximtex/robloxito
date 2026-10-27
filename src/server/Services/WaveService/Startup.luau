-- WaveService · Startup: arranque (start), remotes, bucle y runOf.
-- Parte de WaveService (ver WaveService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local WaveConfig = require(Shared.Config.WaveConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local RemoteService = require(script.Parent.Parent.RemoteService)
local EnemyService = require(script.Parent.Parent.EnemyService)
local PetCombatService = require(script.Parent.Parent.PetCombatService)
local PartFactory = require(script.Parent.Parent.Parent.Util.PartFactory)
local Types = require(script.Parent.Types)
type Place = Types.Place

local ctx: any -- tabla de estado compartida (la crea WaveService/init.luau)
local Api = {} -- funciones públicas de esta parte (init.luau las copia a WaveService)
local FOLDER_NAME: any
local TICK_SECONDS: any
local actionLimiter: any
local lockedUntil: any
local places: any
local runOf: any
local runs: any

-- Funciones de las otras partes
local function activeParticipant(...) return ctx.activeParticipant(...) end
local function applyPick(...) return ctx.applyPick(...) end
local function buildPlace(...) return ctx.buildPlace(...) end
local function floorAt(...) return ctx.floorAt(...) end
local function isActive(...) return ctx.isActive(...) end
local function step(...) return ctx.step(...) end
local function tryStart(...) return ctx.tryStart(...) end
local function updateSign(...) return ctx.updateSign(...) end

-- Arranque ------------------------------------------------------------------------------

local function buildPlaceInfo(placeId: string, settings): Place?
	local zone = ZoneConfig.Zones[settings.Zone]
	if not (zone and WaveConfig.Arenas[settings.Arena]) then
		warn(("[WaveService] El círculo %s no tiene zona o modo válidos"):format(placeId))
		return nil
	end
	local base = GeneratorConfig.Position
	local x = base.X + zone.Center.X + settings.Offset.X
	local z = base.Z + zone.Center.Y + settings.Offset.Y
	return {
		Id = placeId,
		ArenaId = settings.Arena,
		Practice = settings.Practice == true,
		ZoneId = settings.Zone,
		Center = Vector3.new(x, floorAt(x, z), z), -- cara de arriba del suelo
		SpawnPoints = settings.SpawnPoints,
		SpawnJitter = settings.SpawnJitter or 0,
		LeashRadius = settings.LeashRadius,
		InsideRadius = settings.InsideRadius,
		StatusLabel = nil,
		InfoLabel = nil,
	}
end

function Api.start()
	ctx.eventRemote = RemoteService.get(Constants.Remotes.WaveEvent)
	PartFactory.removeExisting(Workspace, FOLDER_NAME)
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace

	for placeId, settings in WaveConfig.Places do
		local info = buildPlaceInfo(placeId, settings)
		if info then
			places[placeId] = info
			buildPlace(info, folder)
		end
	end
	for _, arena in WaveConfig.Arenas do
		if arena.BossOnlyInWaves and arena.Boss then
			EnemyService.setBossWaveControlled(arena.Zone, true)
		end
	end

	-- Dentro de una partida el arma lleva las mejoras elegidas
	PetCombatService.setShotModifier(function(player: Player)
		local _, participant = activeParticipant(player)
		return if participant then participant.Mods else nil
	end)
	EnemyService.setKillModifier(function(player: Player)
		local _, participant = activeParticipant(player)
		if participant then
			return participant.Mods.Loot, participant.Mods.StreakSeconds
		end
		return 1, 0
	end)
	-- Lo ganado durante la partida (para el resumen final)
	EnemyService.onDefeated(function(player: Player, info)
		local _, participant = activeParticipant(player)
		if participant then
			participant.Kills += 1
			participant.Money += if type(info.Reward) == "number" then info.Reward else 0
			participant.Diamonds += if type(info.Diamonds) == "number" then info.Diamonds else 0
			if info.Golden then
				participant.Golden += 1
			end
			if type(info.Streak) == "number" and info.Streak > participant.BestStreak then
				participant.BestStreak = info.Streak
			end
		end
	end)

	RemoteService.get(Constants.Remotes.WaveAction).OnServerEvent:Connect(function(player: Player, action: any, value: any)
		if type(action) ~= "string" or actionLimiter:check(player) ~= "ok" then
			return
		end
		if action == "Start" then
			tryStart(player)
		elseif action == "Pick" then
			if type(value) ~= "string" then
				return
			end
			local run, participant = activeParticipant(player)
			if run and participant and run.Phase == "Cards" then
				applyPick(run, participant, value)
			end
		elseif action == "Endless" then
			-- Tras ganarle al jefe: true = seguir en el modo infinito, false = terminar
			if type(value) ~= "boolean" then
				return
			end
			local run, participant = activeParticipant(player)
			if run and participant and run.Phase == "Choice" then
				participant.Continue = value
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		actionLimiter:remove(player)
		lockedUntil[player] = nil
		local run = runOf[player]
		runOf[player] = nil
		if run then
			run.Participants[player] = nil
		end
	end)

	task.spawn(function()
		local lastSign = 0
		while true do
			task.wait(TICK_SECONDS)
			local now = os.clock()
			for id, run in runs do
				local ok, err = pcall(step, run, now)
				if not ok then
					warn("[WaveService] Error en la partida " .. id .. ": " .. tostring(err))
				end
			end
			if now - lastSign >= 0.5 then
				lastSign = now
				updateSign()
			end
		end
	end)
	updateSign()
end

-- Partida de un jugador (nil si no juega ninguna). Para otros servicios y pruebas.
function Api.runOf(player: Player): number?
	local run = runOf[player]
	return if run and isActive(run) then run.Id else nil
end

local Part = { Api = Api }

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	FOLDER_NAME = context.FOLDER_NAME
	TICK_SECONDS = context.TICK_SECONDS
	actionLimiter = context.actionLimiter
	lockedUntil = context.lockedUntil
	places = context.places
	runOf = context.runOf
	runs = context.runs
end

return Part
