-- WaveService · Flow: empezar o unirse a una partida, muertes de sus enemigos y el paso de cada partida.
-- Parte de WaveService (ver WaveService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WaveConfig = require(Shared.Config.WaveConfig)
local WaveLogic = require(Shared.WaveLogic)
local PlayerDataService = require(script.Parent.Parent.PlayerDataService)
local EnemyService = require(script.Parent.Parent.EnemyService)
local Types = require(script.Parent.Types)
type Place = Types.Place
type Run = Types.Run

local ctx: any -- tabla de estado compartida (la crea WaveService/init.luau)
local CARD_BREAK: any
local PRACTICE_DONE_HINT: any
local STATE_SECONDS: any
local TUTORIAL_MODE: any
local TUTORIAL_PLACE: any
local TUTORIAL_STEP: any
local lockedUntil: any
local places: any
local runOf: any
local runs: any
local onEnemyDeath: any -- (declarada aquí; antes, más arriba en el original)

-- Funciones de las otras partes
local function addParticipant(...) return ctx.addParticipant(...) end
local function applyPick(...) return ctx.applyPick(...) end
local function broadcast(...) return ctx.broadcast(...) end
local function enterBreak(...) return ctx.enterBreak(...) end
local function everyonePicked(...) return ctx.everyonePicked(...) end
local function finish(...) return ctx.finish(...) end
local function flatDistance(...) return ctx.flatDistance(...) end
local function fxTo(...) return ctx.fxTo(...) end
local function hint(...) return ctx.hint(...) end
local function isActive(...) return ctx.isActive(...) end
local function isInside(...) return ctx.isInside(...) end
local function joinableRun(...) return ctx.joinableRun(...) end
local function resolveChoice(...) return ctx.resolveChoice(...) end
local function rootOf(...) return ctx.rootOf(...) end
local function runCount(...) return ctx.runCount(...) end
local function spawnOne(...) return ctx.spawnOne(...) end
local function startWave(...) return ctx.startWave(...) end
local function updateSign(...) return ctx.updateSign(...) end
local function waveCleared(...) return ctx.waveCleared(...) end

-- ¿Le toca la partida de práctica del tutorial?
local function wantsTutorial(player: Player): boolean
	if not (TUTORIAL_STEP and TUTORIAL_MODE) then
		return false
	end
	local profile = PlayerDataService.get(player)
	if not (profile and PlayerDataService.isPetDataReady(profile)) then
		return false
	end
	local tutorial = profile.PetData.Tutorial
	return type(tutorial) == "table" and tutorial.Status == "Active" and type(tutorial.Step) == "number" and tutorial.Step < TUTORIAL_STEP
end

-- Empezar (o unirse a una cuenta atrás) en el círculo `placeId` (o en el que esté el
-- jugador). true si ahora juega una partida.
local function tryStart(player: Player, placeId: string?): boolean
	if runOf[player] or (lockedUntil[player] or 0) > os.clock() then
		return false
	end
	local root = rootOf(player)
	if not (root and PlayerDataService.get(player)) then
		return false
	end
	-- Hay que estar dentro del círculo (del que se pulsó, o de cualquiera)
	local place: Place? = nil
	for id, candidate in places do
		if (placeId == nil or id == placeId) and flatDistance(root.Position, candidate.Center) <= WaveConfig.Place.AreaRadius + 2 then
			place = candidate
		end
	end
	if not place then
		return false
	end
	local mode = place.ArenaId
	if place.Id == TUTORIAL_PLACE or place.Practice then
		if not (TUTORIAL_MODE and wantsTutorial(player)) then
			ctx.eventRemote:FireClient(player, "Hint", { Text = PRACTICE_DONE_HINT, Seconds = 7 })
			lockedUntil[player] = os.clock() + 2 -- sin repetir el aviso al dejar pulsado
			return false
		end
		mode = TUTORIAL_MODE :: string
	end
	-- Unirse a la cuenta atrás de otra partida del mismo modo (la práctica es solo suya)
	if not WaveConfig.Arenas[mode].Tutorial then
		local countdown = joinableRun(place.Id, mode)
		if countdown then
			addParticipant(countdown, player)
			return true
		end
	end
	if runCount() >= WaveConfig.MaxRuns then
		ctx.eventRemote:FireClient(player, "Hint", { Text = "Hay muchas partidas en marcha: prueba en unos segundos.", Seconds = 4 })
		return false
	end
	local arena = WaveConfig.Arenas[mode]
	-- Hueco libre (como mucho MaxRuns partidas a la vez)
	local used = {}
	for _, other in runs do
		used[other.Slot] = true
	end
	local slot = 1
	while used[slot] do
		slot += 1
	end
	ctx.nextRunId += 1
	local run: Run = {
		Id = ctx.nextRunId,
		ArenaId = mode,
		Arena = arena,
		PlaceId = place.Id,
		Slot = slot,
		ZoneId = arena.Zone,
		Center = place.Center,
		Phase = "Countdown",
		Endless = false,
		VictoryPaid = false,
		Wave = 0,
		Waves = WaveLogic.waveCount(mode),
		EndsAt = os.clock() + WaveConfig.StartCountdown,
		Queue = {},
		Alive = {},
		AliveCount = 0,
		Total = 0,
		Killed = 0,
		Players = 1,
		Participants = {},
		EmptySince = nil,
		NextSpawnAt = 0,
		NextEscortAt = 0,
		Bosses = {},
		LastBroadcast = 0,
	}
	runs[run.Id] = run
	addParticipant(run, player)
	hint(run, "Countdown")
	return true
end

function onEnemyDeath(run: Run, id: number)
	return function(enemy, killer: Player?, position: Vector3)
		if runs[id] ~= run or not isActive(run) then
			return
		end
		if run.Alive[enemy] then
			run.Alive[enemy] = nil
			run.AliveCount = math.max(0, run.AliveCount - 1)
			run.Killed += 1
		end
		local participant = if killer then run.Participants[killer] else nil
		if not (killer and participant) then
			return
		end
		local mods = participant.Mods
		-- Vampiro: vida por enemigo
		if mods.Heal > 0 then
			local _, humanoid = rootOf(killer)
			if humanoid then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + mods.Heal)
			end
		end
		-- Reacción en cadena: lo que matas explota y daña a los de alrededor (de su partida)
		local explode = mods.Explode
		local profile = PlayerDataService.get(killer)
		if explode and profile then
			local shot = PlayerDataService.combatStats(profile).Shot * mods.Damage
			local damage = shot * explode.ShotMultiplier
			fxTo(run, { Kind = "Explode", Position = position, Radius = explode.Radius })
			for _, other in EnemyService.findInRadius(position, explode.Radius, 8, killer) do
				if other ~= enemy and EnemyService.isAlive(other) then
					EnemyService.damage(other, killer, damage)
				end
			end
		end
	end
end

-- Bucle ---------------------------------------------------------------------------------

local function step(run: Run, now: number)
	if not isActive(run) then
		return
	end
	for player in run.Participants do
		if not player.Parent then
			run.Participants[player] = nil
			runOf[player] = nil
		end
	end
	if next(run.Participants) == nil then
		finish(run, false)
		return
	end

	-- ¿Queda alguien dentro y vivo?
	local anyone = false
	for player in run.Participants do
		if isInside(run, player) then
			anyone = true
			break
		end
	end
	if anyone then
		run.EmptySince = nil
	else
		run.EmptySince = run.EmptySince or now
		if now - run.EmptySince >= WaveConfig.LeaveGrace then
			finish(run, false)
			return
		end
	end

	if run.Phase == "Countdown" then
		if now >= run.EndsAt then
			startWave(run, 1)
			updateSign()
		end
	elseif run.Phase == "Wave" then
		if #run.Queue > 0 and now >= run.NextSpawnAt then
			run.NextSpawnAt = now + WaveConfig.SpawnInterval
			local spawned = 0
			local limit = WaveLogic.maxAlive(run.Wave)
			while spawned < WaveConfig.BatchSize and #run.Queue > 0 and run.AliveCount < limit do
				if not spawnOne(run, run.Queue[1], run.Wave, true) then
					break -- reserva llena: se espera a que mueran algunos
				end
				table.remove(run.Queue, 1)
				spawned += 1
			end
		end
		if #run.Queue == 0 and run.AliveCount == 0 then
			waveCleared(run)
			return
		end
	elseif run.Phase == "Break" then
		if now >= run.EndsAt then
			startWave(run, run.Wave + 1)
		end
	elseif run.Phase == "Choice" then
		-- Modo infinito: cuando todos han elegido o se acaba el tiempo
		local decided = true
		for _, participant in run.Participants do
			if participant.Continue == nil then
				decided = false
			end
		end
		if decided or now >= run.EndsAt then
			resolveChoice(run)
			return
		end
	elseif run.Phase == "Cards" then
		if everyonePicked(run) then
			enterBreak(run, CARD_BREAK)
		elseif now >= run.EndsAt then
			-- Quien no eligió se lleva una al azar
			for _, participant in run.Participants do
				local choices = participant.Choices
				if choices and #choices > 0 then
					applyPick(run, participant, choices[math.random(1, #choices)])
				end
				participant.Choices = nil
			end
			enterBreak(run, CARD_BREAK)
		end
	elseif run.Phase == "Boss" then
		-- Escolta del jefe, poco a poco mientras siga vivo
		if now >= run.NextEscortAt and run.AliveCount < WaveConfig.MaxAlive then
			run.NextEscortAt = now + WaveConfig.EscortInterval
			local escort = run.Arena.BossEscort or {}
			local typeIds = {}
			for typeId in escort do
				table.insert(typeIds, typeId)
			end
			table.sort(typeIds)
			for _, typeId in typeIds do
				for _ = 1, math.max(1, math.floor(escort[typeId] / 2)) do
					spawnOne(run, typeId, run.Wave)
				end
			end
		end
	end
	if isActive(run) and os.clock() - run.LastBroadcast >= STATE_SECONDS then
		broadcast(run)
	end
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.onEnemyDeath = onEnemyDeath
	context.step = step
	context.tryStart = tryStart
end

function Part.link(context: any)
	CARD_BREAK = context.CARD_BREAK
	PRACTICE_DONE_HINT = context.PRACTICE_DONE_HINT
	STATE_SECONDS = context.STATE_SECONDS
	TUTORIAL_MODE = context.TUTORIAL_MODE
	TUTORIAL_PLACE = context.TUTORIAL_PLACE
	TUTORIAL_STEP = context.TUTORIAL_STEP
	lockedUntil = context.lockedUntil
	places = context.places
	runOf = context.runOf
	runs = context.runs
end

return Part
