-- Oleadas: la mecánica principal (WaveConfig). Partidas PRIVADAS en el círculo de la plaza,
-- delante del spawn:
-- 1. Se empieza con E en el altar del centro (ProximityPrompt) o con WaveAction ("Start").
--    Cada jugador juega SU partida; quien pulse E durante la cuenta atrás de otra (del mismo
--    modo) se une a ella, para jugar con amigos. Varias partidas pueden ir a la vez.
-- 2. Mientras juegas, el resto de enemigos desaparece para ti y no te ataca: solo ves y
--    golpeas los de tu partida (atributo WaveRun en el jugador y en los enemigos;
--    EnemyService filtra y el cliente oculta, WaveVisibility).
-- 3. Oleadas de hordas (WaveLogic.spawnList): los enemigos salen de la reserva de
--    EnemyService (spawnPooled) de pocos en pocos, con más vida cuanto más avanzada la
--    oleada y cuantos más jugadores. Al limpiar una oleada, premio para todos.
-- 4. Cada pocas oleadas, cada jugador elige 1 de 3 mejoras (WaveLogic.rollCards) que duran
--    la partida: el arma (PetCombatService.setShotModifier), el botín y la racha
--    (EnemyService.setKillModifier), y explosiones y curación al matar (aquí).
-- 5. La última oleada trae un jefe (uno para cada partida) con escolta. Si cae: victoria y
--    premio (WaveLogic.victoryReward), además de su botín de siempre (BossRewardService:
--    cuenta para abrir la zona siguiente y su arma la primera vez). Los modos sin jefe (la
--    práctica del tutorial) se ganan al limpiar la última oleada.
-- 6. Si no queda nadie de la partida dentro y vivo durante LeaveGrace segundos, se pierde:
--    los enemigos se retiran sin botín (lo ganado hasta ahí se queda).
-- Modos: "Tutorial" para quien está en ese paso del tutorial (partida corta con consejos en
-- pantalla, "Hint"); el resto juega "Forest". Ganar suma WaveWins (GameEvents "WaveWon").
-- Dentro del círculo el arma dispara sola (PetCombatService.setFreeAutoFire).
-- Todo lo decide el servidor; el cliente (WaveController) solo dibuja lo que se le manda.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local WaveConfig = require(Shared.Config.WaveConfig)
local WaveLogic = require(Shared.WaveLogic)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local TutorialConfig = require(Shared.Config.TutorialConfig)
local ItemLogic = require(Shared.ItemLogic)
local StudFloor = require(Shared.Util.StudFloor)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local EnemyService = require(script.Parent.EnemyService)
local EnergyService = require(script.Parent.EnergyService)
local PetCombatService = require(script.Parent.PetCombatService)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)

local FOLDER_NAME = "WaveArenas"
local TICK_SECONDS = 0.2
local STATE_SECONDS = 0.5 -- cada cuánto se reenvía el estado mientras hay partida
local INSIDE_SLACK = 6 -- margen para seguir contando como "dentro" (y disparar solo)
local GROUND = GeneratorConfig.Position.Y
local CARD_BREAK = 1.5 -- pausa tras elegir mejoras
local RESTART_LOCK = 3 -- tras terminar, segundos sin poder empezar otra (no repetir sin querer)
local HINT_SECONDS = 7
local NORMAL_MODE = "Forest"

-- Paso del tutorial que se juega con la partida de práctica.
local TUTORIAL_STEP: number? = nil
for index, step in TutorialConfig.Steps do
	if step.Id == "Waves" then
		TUTORIAL_STEP = index
	end
end
local TUTORIAL_MODE: string? = nil
for arenaId, arena in WaveConfig.Arenas do
	if arena.Tutorial then
		TUTORIAL_MODE = arenaId
	end
end

type Participant = {
	Player: Player,
	Levels: WaveLogic.Levels,
	Mods: WaveLogic.Mods,
	Choices: { string }?, -- mejoras para elegir ahora (nil si no toca)
	Kills: number,
	Energy: number,
	Money: number,
	Golden: number,
	BestStreak: number,
}

type Run = {
	Id: number,
	ArenaId: string, -- modo (WaveConfig.Arenas)
	Arena: any,
	ZoneId: string,
	Center: Vector3,
	Phase: string, -- "Countdown" | "Wave" | "Break" | "Cards" | "Boss" | "Done"
	Wave: number,
	Waves: number,
	EndsAt: number, -- os.clock() en que acaba la fase (cuenta atrás, pausa, mejoras)
	Queue: { string }, -- enemigos que faltan por salir en esta oleada
	Alive: { [any]: boolean },
	AliveCount: number,
	Total: number,
	Killed: number,
	Players: number, -- jugadores dentro al empezar la oleada (vida de los enemigos)
	Participants: { [Player]: Participant },
	EmptySince: number?,
	NextSpawnAt: number,
	NextEscortAt: number,
	Boss: any?,
	LastBroadcast: number,
}

type Place = {
	ZoneId: string,
	Center: Vector3,
	StatusLabel: TextLabel?,
	InfoLabel: TextLabel?,
}

local WaveService = {}

local place: Place? = nil
local runs: { [number]: Run } = {}
local runOf: { [Player]: Run } = {}
local lockedUntil: { [Player]: number } = {}
local nextRunId = 0
local best = 0 -- mejor oleada superada en este servidor (modo normal)
local eventRemote: RemoteEvent
local actionLimiter = RateLimiter.new(WaveConfig.ActionCooldown, 3, 12)

local function serverTime(fromClock: number): number
	return Workspace:GetServerTimeNow() + (fromClock - os.clock())
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function rootOf(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil, nil
end

local function isActive(run: Run): boolean
	return run.Phase ~= "Done"
end

-- Dentro del círculo (con un margen al salir, para no salir y entrar a cada paso).
local function isInside(run: Run, player: Player): boolean
	local root = rootOf(player)
	return root ~= nil and flatDistance(root.Position, run.Center) <= WaveConfig.Place.AreaRadius + INSIDE_SLACK
end

local function newParticipant(player: Player): Participant
	return { Player = player, Levels = {}, Mods = WaveLogic.modifiers({}), Choices = nil, Kills = 0, Energy = 0, Money = 0, Golden = 0, BestStreak = 0 }
end

-- Partida (activa) en la que juega un jugador, con su ficha.
local function activeParticipant(player: Player): (Run?, Participant?)
	local run = runOf[player]
	if run and isActive(run) then
		return run, run.Participants[player]
	end
	return nil, nil
end

local function participantCount(run: Run): number
	local count = 0
	for _ in run.Participants do
		count += 1
	end
	return count
end

local function runCount(): number
	local count = 0
	for _ in runs do
		count += 1
	end
	return count
end

-- Envíos ---------------------------------------------------------------------------------

local function stateOf(run: Run)
	local remaining = #run.Queue + run.AliveCount
	return {
		Run = run.Id,
		Arena = run.ArenaId,
		Name = run.Arena.DisplayName,
		Tutorial = run.Arena.Tutorial == true,
		Phase = run.Phase,
		Wave = run.Wave,
		Waves = run.Waves,
		Remaining = remaining,
		Total = math.max(run.Total, remaining),
		EndsAt = if run.EndsAt > 0 then serverTime(run.EndsAt) else 0,
		Players = participantCount(run),
		Center = run.Center,
		Radius = WaveConfig.Place.AreaRadius,
		Best = best,
		Boss = if run.Phase == "Boss" and run.Arena.Boss then (EnemyConfig.Types[run.Arena.Boss] or {}).DisplayName else nil,
	}
end

-- Cartel del altar (lo ven todos): cómo jugar, partidas en marcha y récord.
local function updateSign()
	if not place then
		return
	end
	local countdown: Run? = nil
	for _, run in runs do
		if run.Phase == "Countdown" and run.ArenaId == NORMAL_MODE and participantCount(run) < WaveConfig.MaxPlayersPerRun then
			countdown = run
		end
	end
	if place.StatusLabel then
		place.StatusLabel.Text = if countdown then ("¡Pulsa E para unirte! (%d)"):format(math.max(1, math.ceil(countdown.EndsAt - os.clock()))) else "Pulsa E para jugar"
	end
	if place.InfoLabel then
		local playing = runCount()
		local parts = {}
		if playing > 0 then
			table.insert(parts, if playing == 1 then "1 partida en marcha" else ("%d partidas en marcha"):format(playing))
		end
		if best > 0 then
			table.insert(parts, ("Récord: oleada %d"):format(best))
		end
		place.InfoLabel.Text = if #parts > 0 then table.concat(parts, "  ·  ") else "Hordas, mejoras y un jefe al final"
	end
end

local function broadcast(run: Run)
	run.LastBroadcast = os.clock()
	local state = stateOf(run)
	for player in run.Participants do
		if player.Parent then
			eventRemote:FireClient(player, "State", state)
		end
	end
end

local function setPlayerRun(player: Player, run: Run?)
	if not player.Parent then
		return
	end
	local attributes = Constants.Attributes
	local runId = if run then run.Id else nil
	local arenaId = if run then run.ArenaId else nil
	if player:GetAttribute(attributes.WaveRun) ~= runId then
		player:SetAttribute(attributes.WaveRun, runId)
	end
	if player:GetAttribute(attributes.WaveArena) ~= arenaId then
		player:SetAttribute(attributes.WaveArena, arenaId)
	end
end

-- Efectos solo para los jugadores de la partida.
local function fxTo(run: Run, data)
	for player in run.Participants do
		if player.Parent then
			eventRemote:FireClient(player, "Fx", data)
		end
	end
end

-- Consejo del modo (tutorial) para todos los de la partida.
local function hint(run: Run, key: any)
	local text = WaveLogic.hint(run.ArenaId, key)
	if not text then
		return
	end
	for player in run.Participants do
		if player.Parent then
			eventRemote:FireClient(player, "Hint", { Text = text, Seconds = HINT_SECONDS })
		end
	end
end

-- Premios -------------------------------------------------------------------------------

local function pay(participant: Participant, energy: number, money: number): (number, number)
	local profile = PlayerDataService.get(participant.Player)
	if not profile then
		return 0, 0
	end
	-- Poción de Energía (inventario): también dobla la ⚡ de los premios de las oleadas.
	local potion = ItemLogic.multiplier(ItemLogic.ofProfile(profile), "Energy", os.time())
	local given = EnergyService.grant(participant.Player, energy * potion)
	local coins = math.max(0, math.floor(money))
	if coins > 0 then
		profile.Money += coins
		PlayerDataService.replicate(participant.Player)
	end
	participant.Energy += given
	participant.Money += coins
	return given, coins
end

-- Enemigos de la partida -----------------------------------------------------------------

local onEnemyDeath: (Run, number) -> ((any, Player?, Vector3) -> ())

local function spawnPoint(run: Run): Vector3
	local radius = WaveConfig.Place.SpawnRadius
	local angle = math.random() * math.pi * 2
	local distance = radius.Min + math.random() * (radius.Max - radius.Min)
	return run.Center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

local function spawnOne(run: Run, typeId: string, wave: number): boolean
	local area = WaveConfig.Place.AreaRadius
	local enemy = EnemyService.spawnPooled(run.ZoneId, typeId, spawnPoint(run), {
		LeashCenter = run.Center,
		LeashRadius = area + INSIDE_SLACK + 2,
		DetectRange = area * 2.5,
		HealthMultiplier = WaveLogic.healthMultiplier(wave, run.Players),
		RewardMultiplier = WaveLogic.rewardMultiplier(wave),
		PoolLimit = (run.Arena.Pool and run.Arena.Pool[typeId]) or 12,
		OnDeath = onEnemyDeath(run, run.Id),
		Run = run.Id,
		MoneyMultiplier = WaveConfig.MoneyMultiplier,
	})
	if not enemy then
		return false
	end
	run.Alive[enemy] = true
	run.AliveCount += 1
	return true
end

local function despawnAll(run: Run)
	for enemy in run.Alive do
		EnemyService.despawn(enemy)
	end
	table.clear(run.Alive)
	run.AliveCount = 0
	table.clear(run.Queue)
	if run.Boss and EnemyService.isAlive(run.Boss) then
		EnemyService.despawn(run.Boss)
	end
	run.Boss = nil
end

local function insideCount(run: Run): number
	local count = 0
	for player in run.Participants do
		if isInside(run, player) then
			count += 1
		end
	end
	return math.max(1, count)
end

-- Fases ---------------------------------------------------------------------------------

local enterBreak: (Run, number) -> ()
local finish: (Run, boolean) -> ()

-- El jefe de la partida (de la reserva: uno para cada partida), frente al altar.
local function spawnBoss(run: Run): boolean
	local arena = run.Arena
	local area = WaveConfig.Place.AreaRadius
	local id = run.Id
	local boss = EnemyService.spawnPooled(run.ZoneId, arena.Boss, run.Center + Vector3.new(0, 0, -area * 0.55), {
		LeashCenter = run.Center,
		LeashRadius = area + INSIDE_SLACK + 2,
		HealthMultiplier = WaveLogic.bossHealthMultiplier(run.Players),
		RewardMultiplier = 1,
		PoolLimit = (arena.Pool and arena.Pool[arena.Boss]) or 4,
		Run = id,
		MoneyMultiplier = WaveConfig.MoneyMultiplier,
		Arena = { Center = run.Center, Radius = area, Name = arena.DisplayName },
		Territory = area + 4,
		OnDeath = function()
			if runs[id] == run and run.Phase == "Boss" then
				finish(run, true)
			end
		end,
	})
	run.Boss = boss
	return boss ~= nil
end

local function startWave(run: Run, wave: number)
	run.Wave = wave
	run.Players = insideCount(run)
	run.Killed = 0
	run.NextSpawnAt = os.clock()
	if WaveLogic.isBossWave(run.ArenaId, wave) then
		run.Phase = "Boss"
		run.Queue = {}
		run.Total = 1
		run.NextEscortAt = os.clock() + 4
		if not spawnBoss(run) then
			warn("[WaveService] No hay sitio en la reserva para el jefe " .. tostring(run.Arena.Boss) .. ": la partida se da por ganada.")
			finish(run, true)
			return
		end
	else
		run.Phase = "Wave"
		run.Queue = WaveLogic.spawnList(run.ArenaId, wave, math.random)
		run.Total = #run.Queue
	end
	run.EndsAt = 0
	broadcast(run)
	hint(run, wave)
end

local function enterCards(run: Run)
	run.Phase = "Cards"
	run.EndsAt = os.clock() + WaveConfig.CardSeconds
	local anyChoice = false
	for player, participant in run.Participants do
		local choices = WaveLogic.rollCards(participant.Levels, math.random, WaveConfig.CardChoices)
		participant.Choices = if #choices > 0 then choices else nil
		if participant.Choices then
			anyChoice = true
			local cards = {}
			for _, cardId in choices do
				local card = WaveConfig.Cards[cardId]
				table.insert(cards, { Id = cardId, Icon = card.Icon, Name = card.Name, Text = card.Text, Level = WaveLogic.levelOf(participant.Levels, cardId), MaxLevel = card.MaxLevel })
			end
			eventRemote:FireClient(player, "Cards", { Cards = cards, EndsAt = serverTime(run.EndsAt), Wave = run.Wave })
		end
	end
	if not anyChoice then
		enterBreak(run, CARD_BREAK)
		return
	end
	broadcast(run)
end

local function applyPick(run: Run, participant: Participant, cardId: string): boolean
	local choices = participant.Choices
	if not (choices and table.find(choices, cardId)) then
		return false
	end
	if not WaveLogic.pick(participant.Levels, cardId) then
		return false
	end
	participant.Choices = nil
	participant.Mods = WaveLogic.modifiers(participant.Levels)
	local levels = {}
	for id, level in participant.Levels do
		levels[id] = level
	end
	eventRemote:FireClient(participant.Player, "Picked", { Id = cardId, Levels = levels })
	return true
end

local function everyonePicked(run: Run): boolean
	for _, participant in run.Participants do
		if participant.Choices then
			return false
		end
	end
	return true
end

function enterBreak(run: Run, seconds: number)
	run.Phase = "Break"
	run.EndsAt = os.clock() + seconds
	broadcast(run)
end

local function waveCleared(run: Run)
	local wave = run.Wave
	if run.ArenaId == NORMAL_MODE then
		best = math.max(best, wave)
	end
	for _, participant in run.Participants do
		local profile = PlayerDataService.get(participant.Player)
		if profile then
			local energy, money = WaveLogic.clearReward(wave, profile.ProductionPerSecond)
			local given, coins = pay(participant, energy, money)
			eventRemote:FireClient(participant.Player, "Cleared", { Wave = wave, Energy = given, Money = coins })
		end
	end
	if wave >= run.Waves then
		finish(run, true) -- modo sin jefe: ganada al limpiar la última
	elseif WaveLogic.isCardWave(run.ArenaId, wave) then
		enterCards(run)
	else
		enterBreak(run, WaveConfig.BreakSeconds)
	end
end

-- Fin de la partida: premios, resumen y cada uno vuelve al mundo normal.
function finish(run: Run, victory: boolean)
	if run.Phase == "Done" then
		return
	end
	local reached = run.Wave
	if victory and run.ArenaId == NORMAL_MODE then
		best = math.max(best, run.Waves)
	end
	-- Lo que quede se retira sin botín (el jefe derrotado ya se fue solo).
	run.Boss = if victory then nil else run.Boss
	despawnAll(run)
	run.Phase = "Done"
	run.EndsAt = 0
	if victory then
		hint(run, "Victory")
	end
	local now = os.clock()
	for player, participant in run.Participants do
		local energy, money = 0, 0
		if victory then
			local profile = PlayerDataService.get(player)
			if profile then
				energy, money = pay(participant, WaveLogic.victoryReward(profile.ProductionPerSecond, run.ArenaId))
			end
			GameEvents.fire("WaveWon", player, run.ArenaId)
		end
		if player.Parent then
			eventRemote:FireClient(player, "Result", {
				Run = run.Id,
				Victory = victory,
				Tutorial = run.Arena.Tutorial == true,
				Wave = reached,
				Waves = run.Waves,
				Kills = participant.Kills,
				Energy = participant.Energy,
				Money = participant.Money,
				Golden = participant.Golden,
				BestStreak = participant.BestStreak,
				VictoryEnergy = energy,
				VictoryMoney = money,
				Best = best,
			})
		end
		if runOf[player] == run then
			runOf[player] = nil
			setPlayerRun(player, nil)
		end
		lockedUntil[player] = now + RESTART_LOCK
	end
	runs[run.Id] = nil
	updateSign()
end

local function addParticipant(run: Run, player: Player)
	run.Participants[player] = newParticipant(player)
	runOf[player] = run
	setPlayerRun(player, run)
	broadcast(run)
	updateSign()
end

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

-- Empezar (o unirse a una cuenta atrás). true si ahora juega una partida.
local function tryStart(player: Player): boolean
	if not place or runOf[player] or (lockedUntil[player] or 0) > os.clock() then
		return false
	end
	local root = rootOf(player)
	if not (root and PlayerDataService.get(player)) then
		return false
	end
	if flatDistance(root.Position, place.Center) > WaveConfig.Place.AreaRadius + 2 then
		return false
	end
	local mode = if wantsTutorial(player) then TUTORIAL_MODE :: string else NORMAL_MODE
	-- Unirse a la cuenta atrás de otra partida del mismo modo (la práctica es solo suya)
	if not WaveConfig.Arenas[mode].Tutorial then
		for _, run in runs do
			if run.Phase == "Countdown" and run.ArenaId == mode and participantCount(run) < WaveConfig.MaxPlayersPerRun then
				addParticipant(run, player)
				return true
			end
		end
	end
	if runCount() >= WaveConfig.MaxRuns then
		eventRemote:FireClient(player, "Hint", { Text = "Hay muchas partidas en marcha: prueba en unos segundos.", Seconds = 4 })
		return false
	end
	local arena = WaveConfig.Arenas[mode]
	nextRunId += 1
	local run: Run = {
		Id = nextRunId,
		ArenaId = mode,
		Arena = arena,
		ZoneId = arena.Zone,
		Center = place.Center,
		Phase = "Countdown",
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
		Boss = nil,
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
			while spawned < WaveConfig.BatchSize and #run.Queue > 0 and run.AliveCount < WaveConfig.MaxAlive do
				if not spawnOne(run, run.Queue[1], run.Wave) then
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

-- Altar y círculo -----------------------------------------------------------------------

local function label(parent: Instance, position: UDim2, size: UDim2, color: Color3, text: string, stroke: number): TextLabel
	local textLabel = Instance.new("TextLabel")
	textLabel.Position = position
	textLabel.Size = size
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.FredokaOne
	textLabel.TextScaled = true
	textLabel.TextColor3 = color
	textLabel.Text = text
	textLabel.Parent = parent
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.fromRGB(43, 29, 63)
	outline.Thickness = stroke
	outline.Parent = textLabel
	return textLabel
end

local function buildPlace(info: Place, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "WavePedestal"
	local center = info.Center
	local ground = center.Y
	local stone = Color3.fromRGB(110, 112, 100)
	local rune = Color3.fromRGB(255, 140, 70)
	local area = WaveConfig.Place.AreaRadius

	-- Altar en el centro (base baja: los enemigos y los jugadores pasan por encima sin tropezar)
	PartFactory.verticalCylinder(model, "Base", Vector3.new(center.X, ground + 0.2, center.Z), 0.4, 11, stone, Enum.Material.Slate)
	local ring = PartFactory.verticalCylinder(model, "Ring", Vector3.new(center.X, ground + 0.45, center.Z), 0.1, 10, rune, Enum.Material.Neon, false)
	ring.Transparency = 0.2
	local column = PartFactory.part(model, "Column", {
		Size = Vector3.new(2.6, 5, 2.6),
		CFrame = CFrame.new(center.X, ground + 2.9, center.Z),
		Color = stone,
		Material = Enum.Material.Slate,
	})
	local crystal = PartFactory.part(model, "Crystal", {
		Size = Vector3.new(2.4, 3.6, 2.4),
		CFrame = CFrame.new(center.X, ground + 7.4, center.Z) * CFrame.Angles(0, math.rad(45), math.rad(12)),
		Color = rune,
		Material = Enum.Material.Neon,
		Solid = false,
	})
	local light = Instance.new("PointLight")
	light.Color = rune
	light.Range = 24
	light.Brightness = 2
	light.Shadows = false
	light.Parent = crystal
	-- Columna de luz: se ve desde todo el pueblo (y desde el punto de aparición)
	local beam = PartFactory.verticalCylinder(model, "LightBeam", Vector3.new(center.X, ground + 39, center.Z), 62, 2.6, rune, Enum.Material.Neon, false)
	beam.Transparency = 0.45
	beam.CastShadow = false

	-- Borde del círculo en el suelo: aquí dentro se juega
	local tiles = 32
	for index = 1, tiles do
		local angle = (index / tiles) * math.pi * 2
		local position = Vector3.new(center.X + math.cos(angle) * area, ground, center.Z + math.sin(angle) * area)
		local tile = PartFactory.part(model, "EdgeRune" .. index, {
			Size = Vector3.new(1.4, 0.2, 3),
			CFrame = CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)) * CFrame.new(0, 0.12, 0),
			Color = rune,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		tile.Transparency = 0.15
		tile.CastShadow = false
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WavePrompt"
	prompt.ActionText = "Jugar oleadas"
	prompt.ObjectText = "⚔ Oleadas"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = WaveConfig.Place.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = column
	prompt.Triggered:Connect(function(player: Player)
		tryStart(player)
	end)

	-- Cartel flotante: qué es, cómo empezar y lo que pasa
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "WaveSign"
	billboard.Size = UDim2.fromOffset(360, 112)
	billboard.StudsOffset = Vector3.new(0, 5.5, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 260
	billboard.Adornee = crystal
	label(billboard, UDim2.fromScale(0, 0), UDim2.new(1, 0, 0.46, 0), Color3.fromRGB(255, 214, 120), "⚔ OLEADAS", 3)
	info.StatusLabel = label(billboard, UDim2.fromScale(0, 0.48), UDim2.new(1, 0, 0.3, 0), Color3.new(1, 1, 1), "Pulsa E para jugar", 2)
	info.InfoLabel = label(billboard, UDim2.fromScale(0.05, 0.8), UDim2.new(0.9, 0, 0.2, 0), Color3.fromRGB(255, 236, 200), "", 1.5)
	billboard.Parent = crystal

	model.Parent = parent
end

-- Arranque ------------------------------------------------------------------------------

local function buildPlaceInfo(): Place?
	local settings = WaveConfig.Place
	local zone = ZoneConfig.Zones[settings.Zone]
	if not zone then
		warn("[WaveService] La zona de las oleadas no existe: " .. tostring(settings.Zone))
		return nil
	end
	local base = GeneratorConfig.Position
	local x = base.X + zone.Center.X + settings.Offset.X
	local z = base.Z + zone.Center.Y + settings.Offset.Y
	return {
		ZoneId = settings.Zone,
		Center = Vector3.new(x, GROUND + StudFloor.BaseTop + StudFloor.raiseAt(x, z), z), -- cara de arriba del suelo
		StatusLabel = nil,
		InfoLabel = nil,
	}
end

function WaveService.start()
	eventRemote = RemoteService.get(Constants.Remotes.WaveEvent)
	PartFactory.removeExisting(Workspace, FOLDER_NAME)
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace

	place = buildPlaceInfo()
	if place then
		buildPlace(place, folder)
	end
	for _, arena in WaveConfig.Arenas do
		if arena.BossOnlyInWaves and arena.Boss then
			EnemyService.setBossWaveControlled(arena.Zone, true)
		end
	end

	-- Dentro de una partida (y del círculo) el arma dispara sola y lleva las mejoras elegidas
	PetCombatService.setFreeAutoFire(function(player: Player): boolean
		local run = activeParticipant(player)
		return run ~= nil and isInside(run, player)
	end)
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
			participant.Energy += if type(info.Energy) == "number" then info.Energy else 0
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
function WaveService.runOf(player: Player): number?
	local run = runOf[player]
	return if run and isActive(run) then run.Id else nil
end

return WaveService
