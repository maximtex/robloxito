-- Oleadas: la mecánica principal (WaveConfig). Partidas PRIVADAS en el círculo de cada zona
-- (WaveConfig.Places: Bosque (en la sala del altar de la Cueva de los Espinillos), Valle y
-- Caldera), con los enemigos y el jefe de esa zona:
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
--    práctica del tutorial) se ganan al limpiar la última oleada. En las mazmorras, además,
--    un COFRE para cada uno (Arenas.*.Chest: 💰 y a veces una poción; "Chest" al cliente,
--    que lo dibuja delante del altar y lo abre). En el Valle y la Caldera algunos bichos de
--    las hordas salen élite (Arenas.*.EliteChance; EnemyService, su propia reserva).
-- 6. Si no queda nadie de la partida dentro y vivo durante LeaveGrace segundos, se pierde:
--    los enemigos se retiran sin botín (lo ganado hasta ahí se queda).
-- Modos: "Tutorial" en el altar de la práctica (Places.Practice, en la pradera) para quien
-- está en ese paso del tutorial (partida corta con consejos en pantalla, "Hint"); a los demás
-- ese altar les dice que las oleadas están en la cueva. Ganar suma WaveWins (GameEvents
-- "WaveWon").
-- Dentro de la partida se apunta y se dispara igual que fuera (sin disparo automático gratis).
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
local DiamondService = require(script.Parent.DiamondService)
local PetCombatService = require(script.Parent.PetCombatService)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)
local ItemService = require(script.Parent.ItemService)

local FOLDER_NAME = "WaveArenas"
local TICK_SECONDS = 0.2
local STATE_SECONDS = 0.5 -- cada cuánto se reenvía el estado mientras hay partida
local INSIDE_SLACK = 6 -- margen para seguir contando como "dentro" (y disparar solo)
local GROUND = GeneratorConfig.Position.Y
local CARD_BREAK = 1.5 -- pausa tras elegir mejoras
local RESTART_LOCK = 3 -- tras terminar, segundos sin poder empezar otra (no repetir sin querer)
local HINT_SECONDS = 7

-- Paso del tutorial que se juega con la partida de práctica.
local TUTORIAL_STEP: number? = nil
for index, step in TutorialConfig.Steps do
	if step.Id == "Waves" then
		TUTORIAL_STEP = index
	end
end
local TUTORIAL_MODE: string? = WaveLogic.tutorialArena()
-- Círculo donde se juega la práctica (el de su modo).
local TUTORIAL_PLACE: string? = if TUTORIAL_MODE then WaveConfig.Arenas[TUTORIAL_MODE].Place else nil
-- Aviso para quien ya no está en la práctica y pulsa E en su altar.
local PRACTICE_DONE_HINT = "⚔ Las Oleadas del Guardián están en la 🦇 Cueva de los Espinillos: camino de piedra al oeste de la plaza."

type Participant = {
	Player: Player,
	Levels: WaveLogic.Levels,
	Mods: WaveLogic.Mods,
	Choices: { string }?, -- mejoras para elegir ahora (nil si no toca)
	Kills: number,
	Diamonds: number,
	Money: number,
	Golden: number,
	BestStreak: number,
	StartBest: number, -- su récord en este modo al empezar (WaveLogic.Records)
	NewBest: boolean, -- ha superado su récord en esta partida
	RecordShown: boolean, -- ya se le avisó del récord nuevo
	Continue: boolean?, -- modo infinito: true sigue, false se va, nil aún no ha elegido
	VictoryDiamonds: number, -- premio de victoria ya cobrado
	VictoryMoney: number,
}

type Run = {
	Id: number,
	ArenaId: string, -- modo (WaveConfig.Arenas)
	Arena: any,
	PlaceId: string, -- círculo (WaveConfig.Places)
	Slot: number, -- hueco 1..MaxRuns (grupo de colisión de sus enemigos)
	ZoneId: string,
	Center: Vector3,
	Phase: string, -- "Countdown" | "Wave" | "Break" | "Cards" | "Boss" | "Choice" | "Done"
	Endless: boolean, -- en el modo infinito (tras ganarle al jefe)
	VictoryPaid: boolean, -- el premio de victoria ya se cobró (al caer el jefe)
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
	-- Jefes vivos de la partida: uno, o los dos en que se parte el Coloso del Equilibrio
	-- (EnemyConfig.Types.*.Split). Se gana cuando cae el último.
	Bosses: { any },
	LastBroadcast: number,
}

type Place = {
	Id: string,
	ArenaId: string, -- modo que se juega aquí
	Practice: boolean, -- solo la práctica del tutorial (WaveConfig.Places.*.Practice)
	ZoneId: string,
	Center: Vector3,
	SpawnPoints: { Vector2 }?, -- por dónde salen los bichos (si no, el anillo del altar)
	SpawnJitter: number,
	LeashRadius: number?,
	InsideRadius: number?, -- hasta dónde se cuenta como dentro (si no, el círculo)
	StatusLabel: TextLabel?,
	InfoLabel: TextLabel?,
}

local WaveService = {}

local places: { [string]: Place } = {}
local runs: { [number]: Run } = {}
local runOf: { [Player]: Run } = {}
local lockedUntil: { [Player]: number } = {}
local nextRunId = 0
local best: { [string]: number } = {} -- mejor oleada superada en este servidor, por modo
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
	local place = places[run.PlaceId]
	local radius = (place and place.InsideRadius) or (WaveConfig.Place.AreaRadius + INSIDE_SLACK)
	return root ~= nil and flatDistance(root.Position, run.Center) <= radius
end

local function newParticipant(player: Player): Participant
	return {
		Player = player,
		Levels = {},
		Mods = WaveLogic.modifiers({}),
		Choices = nil,
		Kills = 0,
		Diamonds = 0,
		Money = 0,
		Golden = 0,
		BestStreak = 0,
		StartBest = 0,
		NewBest = false,
		RecordShown = false,
		Continue = nil,
		VictoryDiamonds = 0,
		VictoryMoney = 0,
	}
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

-- Nombre de los jefes de la partida en la fase del jefe ("Ignis y Glacius" tras partirse)
local function bossName(run: Run): string?
	if run.Phase ~= "Boss" then
		return nil
	end
	local names = {}
	for _, boss in run.Bosses do
		if EnemyService.isAlive(boss) then
			table.insert(names, boss.Def.DisplayName)
		end
	end
	if #names == 0 and run.Arena.Boss then
		return (EnemyConfig.Types[run.Arena.Boss] or {}).DisplayName
	end
	return table.concat(names, " y ")
end

local function stateOf(run: Run)
	local remaining = #run.Queue + run.AliveCount
	return {
		Run = run.Id,
		Arena = run.ArenaId,
		Name = run.Arena.DisplayName,
		Tutorial = run.Arena.Tutorial == true,
		Endless = run.Endless == true,
		Phase = run.Phase,
		Wave = run.Wave,
		Waves = run.Waves,
		Remaining = remaining,
		Total = math.max(run.Total, remaining),
		EndsAt = if run.EndsAt > 0 then serverTime(run.EndsAt) else 0,
		Players = participantCount(run),
		Center = run.Center,
		Radius = WaveConfig.Place.AreaRadius,
		Best = best[run.ArenaId] or 0,
		Boss = bossName(run),
	}
end

-- Cuenta atrás de una partida de este círculo a la que aún se puede unir alguien.
local function joinableRun(placeId: string, arenaId: string): Run?
	for _, run in runs do
		if run.PlaceId == placeId and run.ArenaId == arenaId and run.Phase == "Countdown" and participantCount(run) < WaveConfig.MaxPlayersPerRun then
			return run
		end
	end
	return nil
end

-- Carteles de los altares (los ven todos): cómo jugar, partidas en marcha y récord.
local function updateSign()
	for placeId, place in places do
		local countdown = joinableRun(placeId, place.ArenaId)
		if place.StatusLabel then
			place.StatusLabel.Text = if place.Practice then "Tu primera oleada (tutorial)"
				elseif countdown then ("¡Pulsa E para unirte! (%d)"):format(math.max(1, math.ceil(countdown.EndsAt - os.clock())))
				else "Pulsa E para jugar"
		end
		if place.Practice and place.InfoLabel then
			place.InfoLabel.Text = "Las del Guardián: en la 🦇 Cueva, al oeste"
		elseif place.InfoLabel then
			local playing = 0
			for _, run in runs do
				if run.PlaceId == placeId then
					playing += 1
				end
			end
			local parts = {}
			if playing > 0 then
				table.insert(parts, if playing == 1 then "1 partida en marcha" else ("%d partidas en marcha"):format(playing))
			end
			local record = best[place.ArenaId] or 0
			if record > 0 then
				table.insert(parts, ("Récord: oleada %d"):format(record))
			end
			place.InfoLabel.Text = if #parts > 0 then table.concat(parts, "  ·  ") else "Hordas, mejoras y un jefe al final"
		end
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

local function pay(participant: Participant, diamonds: number, money: number): (number, number)
	local profile = PlayerDataService.get(participant.Player)
	if not profile then
		return 0, 0
	end
	-- Pase Diamantes ×2, Poción de Diamantes y aventuras: también multiplican los 💎 de los
	-- premios de las oleadas.
	local given = DiamondService.grant(participant.Player, diamonds * PlayerDataService.diamondMultiplier(profile))
	local coins = math.max(0, math.floor(money))
	if coins > 0 then
		profile.Money += coins
		PlayerDataService.replicate(participant.Player)
	end
	participant.Diamonds += given
	participant.Money += coins
	return given, coins
end

-- Enemigos de la partida -----------------------------------------------------------------

local onEnemyDeath: (Run, number) -> ((any, Player?, Vector3) -> ())

local function spawnPoint(run: Run): Vector3
	-- La cueva: por uno de sus sitios de la sala, al azar
	local place = places[run.PlaceId]
	local points = place and place.SpawnPoints
	if points and #points > 0 then
		local point = points[math.random(1, #points)]
		local jitter = place.SpawnJitter
		local x = run.Center.X + point.X + (math.random() * 2 - 1) * jitter
		local z = run.Center.Z + point.Y + (math.random() * 2 - 1) * jitter
		return Vector3.new(x, run.Center.Y, z)
	end
	local radius = WaveConfig.Place.SpawnRadius
	local angle = math.random() * math.pi * 2
	local distance = radius.Min + math.random() * (radius.Max - radius.Min)
	return run.Center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

-- `allowElite`: las hordas pueden sacar élites (la escolta del jefe no).
local function spawnOne(run: Run, typeId: string, wave: number, allowElite: boolean?): boolean
	local area = WaveConfig.Place.AreaRadius
	local place = places[run.PlaceId]
	local leash = (place and place.LeashRadius) or (area + INSIDE_SLACK + 2)
	local options = {
		LeashCenter = run.Center,
		LeashRadius = leash,
		DetectRange = math.max(area * 2.5, leash * 1.6),
		HealthMultiplier = WaveLogic.healthMultiplier(wave, run.Players),
		RewardMultiplier = WaveLogic.rewardMultiplier(wave),
		PoolLimit = (run.Arena.Pool and run.Arena.Pool[typeId]) or 12,
		OnDeath = onEnemyDeath(run, run.Id),
		Run = run.Id,
		MoneyMultiplier = WaveConfig.MoneyMultiplier,
		DamageMultiplier = WaveLogic.damageMultiplier(wave),
		CollisionSlot = run.Slot,
	}
	local position = spawnPoint(run)
	local enemy = nil
	if allowElite and WaveLogic.isElite(run.ArenaId, math.random()) then
		local eliteOptions = table.clone(options)
		eliteOptions.Elite = true
		eliteOptions.PoolLimit = run.Arena.EliteMax or 4
		enemy = EnemyService.spawnPooled(run.ZoneId, typeId, position, eliteOptions)
	end
	enemy = enemy or EnemyService.spawnPooled(run.ZoneId, typeId, position, options)
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
	for _, boss in run.Bosses do
		if EnemyService.isAlive(boss) then
			EnemyService.despawn(boss)
		end
	end
	table.clear(run.Bosses)
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
local enterChoice: (Run) -> ()
local recordCleared: (Run, number) -> ()

-- Cayó el último jefe: victoria (con modo infinito, se cobra y cada uno elige si sigue)
local function bossesDefeated(run: Run)
	recordCleared(run, run.Wave)
	if WaveLogic.hasEndless(run.ArenaId) then
		enterChoice(run)
	else
		finish(run, true)
	end
end

-- Saca un jefe de la reserva (uno para cada partida) en `position`. Al morir sale de
-- run.Bosses y, si era el último, se gana. onSplit: el Coloso del Equilibrio (se parte).
local function spawnOneBoss(run: Run, typeId: string, position: Vector3, onSplit: ((any) -> ())?): any?
	local arena = run.Arena
	local area = WaveConfig.Place.AreaRadius
	local id = run.Id
	local def = EnemyConfig.Types[typeId]
	local split = def and def.Split
	local boss
	boss = EnemyService.spawnPooled(run.ZoneId, typeId, Vector3.new(position.X, run.Center.Y, position.Z), {
		LeashCenter = run.Center,
		LeashRadius = area + INSIDE_SLACK + 2,
		HealthMultiplier = WaveLogic.bossHealthMultiplier(run.Players),
		RewardMultiplier = 1,
		PoolLimit = (arena.Pool and arena.Pool[typeId]) or 4,
		Run = id,
		MoneyMultiplier = WaveConfig.MoneyMultiplier,
		CollisionSlot = run.Slot,
		Arena = { Center = run.Center, Radius = area, Name = arena.DisplayName },
		Territory = area + 4,
		OnSplit = onSplit,
		SplitAt = if onSplit and split then split.HealthFraction else nil,
		OnDeath = function()
			if runs[id] ~= run or run.Phase ~= "Boss" then
				return
			end
			local index = table.find(run.Bosses, boss)
			if index then
				table.remove(run.Bosses, index)
			end
			if #run.Bosses > 0 then
				broadcast(run) -- queda el otro
				return
			end
			bossesDefeated(run)
		end,
	})
	if boss then
		table.insert(run.Bosses, boss)
	end
	return boss
end

-- El Coloso del Equilibrio llega a la mitad de su vida: explota (efecto para la partida) y en
-- su sitio salen sus dos mitades (Split.Into), una a cada lado, con la vida entera.
local function splitBoss(run: Run, giant: any)
	if runs[run.Id] ~= run or run.Phase ~= "Boss" then
		return
	end
	local split = giant.Def.Split
	local index = table.find(run.Bosses, giant)
	if not (index and split and type(split.Into) == "table") then
		return
	end
	local position = giant.Root.Position
	local right = giant.Root.CFrame.RightVector
	right = Vector3.new(right.X, 0, right.Z)
	right = if right.Magnitude > 0.1 then right.Unit else Vector3.xAxis
	table.remove(run.Bosses, index)
	EnemyService.despawn(giant) -- sin botín: lo dan sus mitades
	local names = {}
	for _, typeId in split.Into do
		local half = EnemyConfig.Types[typeId]
		table.insert(names, if half then half.DisplayName else typeId)
	end
	fxTo(run, { Kind = "Split", Position = position, Names = names })
	local count = #split.Into
	for i, typeId in split.Into do
		local side = i - (count + 1) / 2
		spawnOneBoss(run, typeId, position + right * side * 2 * (split.Spread or 8))
	end
	if #run.Bosses == 0 then
		warn("[WaveService] No hay sitio en la reserva para las mitades de " .. tostring(giant.TypeId) .. ": la partida se da por ganada.")
		bossesDefeated(run)
		return
	end
	broadcast(run)
end

-- El jefe de la partida, frente al altar. Si se parte (Split), con su aviso; con
-- Arena.SplitAtStart salen directamente sus dos mitades (las Oleadas Gemelas de la Grieta).
local function spawnBoss(run: Run): boolean
	local arena = run.Arena
	local area = WaveConfig.Place.AreaRadius
	local front = run.Center + Vector3.new(0, 0, -area * 0.55)
	local def = EnemyConfig.Types[arena.Boss]
	local split = def and def.Split
	if split and arena.SplitAtStart then
		local count = #split.Into
		for i, typeId in split.Into do
			spawnOneBoss(run, typeId, front + Vector3.new((i - (count + 1) / 2) * 2 * (split.Spread or 8), 0, 0))
		end
		return #run.Bosses > 0
	end
	local onSplit = if split then function(enemy)
		splitBoss(run, enemy)
	end else nil
	return spawnOneBoss(run, arena.Boss, front, onSplit) ~= nil
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

-- Oleada `wave` superada: récord del servidor y de cada jugador (WaveLogic.recordWave), que
-- se guarda. Aviso "Record" la primera vez que alguien supera su récord anterior.
function recordCleared(run: Run, wave: number)
	if run.Arena.Tutorial then
		return
	end
	best[run.ArenaId] = math.max(best[run.ArenaId] or 0, wave)
	for player, participant in run.Participants do
		local profile = PlayerDataService.get(player)
		if not profile then
			continue
		end
		local records = profile.PetData.Waves
		if type(records) ~= "table" then
			records = WaveLogic.emptyRecords()
			profile.PetData.Waves = records
		end
		GameEvents.fire("WaveCleared", player, run.ArenaId, wave) -- requisito de renacer (RebirthService)
		if WaveLogic.recordWave(records, run.ArenaId, wave) then
			participant.NewBest = true
			if participant.StartBest > 0 and not participant.RecordShown and player.Parent then
				participant.RecordShown = true
				eventRemote:FireClient(player, "Record", { Wave = wave, Previous = participant.StartBest })
			end
		end
		PlayerDataService.markDirty(player)
		PlayerDataService.replicate(player)
	end
end

local function waveCleared(run: Run)
	local wave = run.Wave
	recordCleared(run, wave)
	for _, participant in run.Participants do
		local profile = PlayerDataService.get(participant.Player)
		if profile then
			local diamonds, money = WaveLogic.clearReward(wave, run.ArenaId)
			local given, coins = pay(participant, diamonds, money)
			-- Respiro: recupera parte de la vida (solo quien sigue en pie)
			local healed = false
			local _, humanoid = rootOf(participant.Player)
			if humanoid and humanoid.Health > 0 and WaveConfig.ClearHeal and WaveConfig.ClearHeal > 0 then
				local before = humanoid.Health
				humanoid.Health = math.min(humanoid.MaxHealth, before + humanoid.MaxHealth * WaveConfig.ClearHeal)
				healed = humanoid.Health > before
			end
			eventRemote:FireClient(participant.Player, "Cleared", { Wave = wave, Diamonds = given, Money = coins, Healed = healed })
		end
	end
	if not run.Endless and wave >= run.Waves then
		finish(run, true) -- modo sin jefe: ganada al limpiar la última
	elseif WaveLogic.isCardWave(run.ArenaId, wave) then
		enterCards(run)
	else
		enterBreak(run, WaveConfig.BreakSeconds)
	end
end

-- Cofre de las mazmorras para un jugador: 💰 y, a veces, una poción para el inventario. Se
-- cobra ya; el cliente lo dibuja delante del altar y lo abre ("Chest").
local function giveChest(run: Run, participant: Participant)
	local player = participant.Player
	local profile = PlayerDataService.get(player)
	local items = profile and ItemLogic.ofProfile(profile)
	local money, potion = WaveLogic.chestReward(run.ArenaId, math.random(), math.random(), ItemLogic.potionOrder())
	if money <= 0 and not potion then
		return
	end
	local _, coins = pay(participant, 0, money)
	if potion and not (items and ItemLogic.addPotion(items, potion, 1) > 0) then
		potion = nil
	end
	if potion then
		PlayerDataService.markDirty(player)
		pcall(ItemService.push, player)
	end
	if player.Parent then
		eventRemote:FireClient(player, "Chest", {
			Position = run.Center + Vector3.new(0, 0, WaveConfig.Place.AreaRadius * 0.45),
			Facing = Vector3.new(0, 0, -1),
			Money = coins,
			Potion = potion,
			Arena = run.Arena.DisplayName,
		})
	end
end

-- Premio de victoria para todos los de la partida (una sola vez).
local function payVictory(run: Run)
	if run.VictoryPaid then
		return
	end
	run.VictoryPaid = true
	hint(run, "Victory")
	for player, participant in run.Participants do
		local profile = PlayerDataService.get(player)
		if profile then
			participant.VictoryDiamonds, participant.VictoryMoney = pay(participant, WaveLogic.victoryReward(run.ArenaId))
			local ok, err = pcall(giveChest, run, participant)
			if not ok then
				warn("[WaveService] Cofre: " .. tostring(err))
			end
		end
		GameEvents.fire("WaveWon", player, run.ArenaId)
	end
end

-- Resumen para un jugador y vuelta al mundo normal.
local function sendResult(run: Run, player: Player, participant: Participant, victory: boolean)
	if player.Parent then
		local profile = PlayerDataService.get(player)
		eventRemote:FireClient(player, "Result", {
			Run = run.Id,
			Victory = victory,
			Tutorial = run.Arena.Tutorial == true,
			Endless = run.Endless == true,
			Arena = run.Arena.DisplayName,
			Wave = run.Wave,
			Waves = run.Waves,
			Kills = participant.Kills,
			Diamonds = participant.Diamonds,
			Money = participant.Money,
			Golden = participant.Golden,
			BestStreak = participant.BestStreak,
			VictoryDiamonds = participant.VictoryDiamonds,
			VictoryMoney = participant.VictoryMoney,
			Best = best[run.ArenaId] or 0,
			PersonalBest = if profile then WaveLogic.bestWave(profile.PetData.Waves, run.ArenaId) else 0,
			NewBest = participant.NewBest and participant.StartBest > 0,
		})
	end
	if runOf[player] == run then
		runOf[player] = nil
		setPlayerRun(player, nil)
	end
	lockedUntil[player] = os.clock() + RESTART_LOCK
end

-- Fin de la partida: premios, resumen y cada uno vuelve al mundo normal. En el modo infinito
-- la victoria ya se cobró al caer el jefe: el resumen la cuenta, pero no se paga otra vez.
function finish(run: Run, victory: boolean)
	if run.Phase == "Done" then
		return
	end
	-- Lo que quede se retira sin botín (los jefes derrotados ya se fueron solos).
	despawnAll(run)
	run.Phase = "Done"
	run.EndsAt = 0
	if victory then
		payVictory(run)
	end
	for player, participant in run.Participants do
		sendResult(run, player, participant, victory or run.VictoryPaid)
	end
	runs[run.Id] = nil
	updateSign()
end

-- Jefe derrotado en un modo con modo infinito: se cobra la victoria y cada jugador tiene
-- Endless.ChoiceSeconds para elegir si sigue ("Endless", true/false).
function enterChoice(run: Run)
	despawnAll(run) -- la escolta se retira (los jefes ya cayeron)
	payVictory(run)
	run.Phase = "Choice"
	run.EndsAt = os.clock() + WaveConfig.Endless.ChoiceSeconds
	for player, participant in run.Participants do
		participant.Continue = nil
		participant.Choices = nil
		if player.Parent then
			eventRemote:FireClient(player, "Choice", {
				EndsAt = serverTime(run.EndsAt),
				Wave = run.Wave,
				VictoryDiamonds = participant.VictoryDiamonds,
				VictoryMoney = participant.VictoryMoney,
			})
		end
	end
	broadcast(run)
	updateSign()
end

-- Fin de la elección: quien no sigue se lleva su resumen; con alguien que sigue, empieza el
-- modo infinito (tras una pausa corta).
local function resolveChoice(run: Run)
	for player, participant in run.Participants do
		if participant.Continue ~= true then
			run.Participants[player] = nil
			sendResult(run, player, participant, true)
		end
	end
	if next(run.Participants) == nil then
		run.Phase = "Done"
		runs[run.Id] = nil
		updateSign()
		return
	end
	run.Endless = true
	enterBreak(run, 2)
end

local function addParticipant(run: Run, player: Player)
	local participant = newParticipant(player)
	local profile = PlayerDataService.get(player)
	participant.StartBest = if profile then WaveLogic.bestWave(profile.PetData.Waves, run.ArenaId) else 0
	run.Participants[player] = participant
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
			eventRemote:FireClient(player, "Hint", { Text = PRACTICE_DONE_HINT, Seconds = 7 })
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
		eventRemote:FireClient(player, "Hint", { Text = "Hay muchas partidas en marcha: prueba en unos segundos.", Seconds = 4 })
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
	nextRunId += 1
	local run: Run = {
		Id = nextRunId,
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

-- Cara de arriba del suelo en (x, z) del mundo (los caminos sobresalen: StudFloor.raiseAt).
local function floorAt(x: number, z: number): number
	return GROUND + StudFloor.BaseTop + StudFloor.raiseAt(x, z)
end

local function buildPlace(info: Place, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "WavePedestal_" .. info.Id
	model:SetAttribute("Place", info.Id)
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

	-- Borde del círculo en el suelo: aquí dentro se juega (cada losa, a la altura del suelo
	-- que pisa: puede cruzar un camino)
	local tiles = 32
	for index = 1, tiles do
		local angle = (index / tiles) * math.pi * 2
		local tx, tz = center.X + math.cos(angle) * area, center.Z + math.sin(angle) * area
		local position = Vector3.new(tx, floorAt(tx, tz), tz)
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
	prompt.ObjectText = "⚔ " .. tostring((WaveConfig.Arenas[info.ArenaId] or {}).DisplayName or "Oleadas")
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = WaveConfig.Place.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = column
	prompt.Triggered:Connect(function(player: Player)
		tryStart(player, info.Id)
	end)

	-- Cartel flotante: qué es, cómo empezar y lo que pasa
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "WaveSign"
	billboard.Size = UDim2.fromOffset(360, 112)
	billboard.StudsOffset = Vector3.new(0, 5.5, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 260
	billboard.Adornee = crystal
	label(billboard, UDim2.fromScale(0, 0), UDim2.new(1, 0, 0.46, 0), Color3.fromRGB(255, 214, 120), if info.Practice then "⚔ PRÁCTICA" else "⚔ OLEADAS", 3)
	info.StatusLabel = label(billboard, UDim2.fromScale(0, 0.48), UDim2.new(1, 0, 0.3, 0), Color3.new(1, 1, 1), "Pulsa E para jugar", 2)
	info.InfoLabel = label(billboard, UDim2.fromScale(0.05, 0.8), UDim2.new(0.9, 0, 0.2, 0), Color3.fromRGB(255, 236, 200), "", 1.5)
	billboard.Parent = crystal

	model.Parent = parent
end

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

function WaveService.start()
	eventRemote = RemoteService.get(Constants.Remotes.WaveEvent)
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
function WaveService.runOf(player: Player): number?
	local run = runOf[player]
	return if run and isActive(run) then run.Id else nil
end

return WaveService
