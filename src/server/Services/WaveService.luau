-- Oleadas: la mecánica principal (WaveConfig). Una partida por arena, para todos los que
-- estén dentro:
-- 1. Se empieza con E en el pedestal de la entrada (ProximityPrompt) o con WaveAction
--    ("Start"). Cuenta atrás y entran en la partida los jugadores dentro del círculo
--    (AreaRadius); quien entre después también se suma.
-- 2. Oleadas de hordas (WaveLogic.spawnList): los enemigos salen de la reserva de
--    EnemyService (spawnPooled) de pocos en pocos, con más vida cuanto más avanzada la
--    oleada y cuantos más jugadores; persiguen a todo el que esté dentro. Al limpiar una
--    oleada, premio para todos (WaveLogic.clearReward).
-- 3. Tras la 3, la 6 y la 9, cada jugador elige 1 de 3 mejoras (WaveLogic.rollCards) que
--    duran la partida: el arma (PetCombatService.setShotModifier), el botín y la racha
--    (EnemyService.setKillModifier), y explosiones y curación al matar (aquí).
-- 4. La última oleada despierta al jefe de la zona (EnemyService.wakeBoss) con escolta. Si
--    cae: victoria y premio (WaveLogic.victoryReward), además de su botín de siempre
--    (BossRewardService: cuenta para abrir la zona siguiente y su arma la primera vez).
-- 5. Si no queda nadie dentro y vivo durante LeaveGrace segundos, se pierde: los enemigos
--    se retiran sin botín (lo ganado hasta ahí se queda).
-- Dentro de la partida el arma dispara sola para todos (PetCombatService.setFreeAutoFire).
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
local StudFloor = require(Shared.Util.StudFloor)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local EnemyService = require(script.Parent.EnemyService)
local EnergyService = require(script.Parent.EnergyService)
local PetCombatService = require(script.Parent.PetCombatService)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local FOLDER_NAME = "WaveArenas"
local TICK_SECONDS = 0.2
local STATE_SECONDS = 0.5 -- cada cuánto se reenvía el estado mientras hay partida
local INSIDE_SLACK = 6 -- margen para seguir contando como "dentro" (y disparar solo)
local START_DISTANCE = 16 -- desde el pedestal para poder empezar con WaveAction
local FX_RANGE = 160 -- jugadores que ven las explosiones de otro
local GROUND = GeneratorConfig.Position.Y
local CARD_BREAK = 1.5 -- pausa tras elegir mejoras

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
	ArenaId: string,
	Arena: any,
	ZoneId: string,
	Center: Vector3,
	Pedestal: Vector3,
	Phase: string, -- "Idle" | "Countdown" | "Wave" | "Break" | "Cards" | "Boss" | "Result"
	Wave: number,
	Waves: number,
	EndsAt: number, -- os.clock() en que acaba la fase (cuenta atrás, pausa, mejoras, resultado)
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
	Token: number, -- cambia en cada partida: invalida avisos de enemigos de otra
	Best: number, -- mejor oleada superada en este servidor
	LastBroadcast: number,
	StatusLabel: TextLabel?,
	Prompt: ProximityPrompt?,
}

local WaveService = {}

local runs: { [string]: Run } = {}
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
	return run.Phase ~= "Idle" and run.Phase ~= "Result"
end

-- Dentro de la partida (con un margen para no salir y entrar a cada paso). Para sumarse
-- hace falta entrar del todo (sin margen: joining = true).
local function isInside(run: Run, player: Player, joining: boolean?): boolean
	local root = rootOf(player)
	local radius = run.Arena.AreaRadius + (if joining then 0 else INSIDE_SLACK)
	return root ~= nil and flatDistance(root.Position, run.Center) <= radius
end

local function newParticipant(player: Player): Participant
	return { Player = player, Levels = {}, Mods = WaveLogic.modifiers({}), Choices = nil, Kills = 0, Energy = 0, Money = 0, Golden = 0, BestStreak = 0 }
end

-- Partida (activa) en la que juega un jugador, con su ficha.
local function activeParticipant(player: Player): (Run?, Participant?)
	for _, run in runs do
		local participant = run.Participants[player]
		if participant and isActive(run) then
			return run, participant
		end
	end
	return nil, nil
end

-- Envíos ---------------------------------------------------------------------------------

local function stateOf(run: Run)
	local participants = {}
	for player in run.Participants do
		table.insert(participants, player.UserId)
	end
	local remaining = #run.Queue + run.AliveCount
	return {
		Arena = run.ArenaId,
		Name = run.Arena.DisplayName,
		Phase = run.Phase,
		Wave = run.Wave,
		Waves = run.Waves,
		Remaining = remaining,
		Total = math.max(run.Total, remaining),
		EndsAt = if run.EndsAt > 0 then serverTime(run.EndsAt) else 0,
		Participants = participants,
		Center = run.Center,
		Radius = run.Arena.AreaRadius,
		Best = run.Best,
		Boss = if run.Phase == "Boss" then (EnemyConfig.Types[run.Arena.Boss] or {}).DisplayName else nil,
	}
end

local function statusText(run: Run): string
	if run.Phase == "Idle" then
		return if run.Best > 0 then ("Récord del servidor: oleada %d"):format(run.Best) else "Pulsa E para empezar"
	elseif run.Phase == "Countdown" then
		return "¡Prepárate!"
	elseif run.Phase == "Boss" then
		return "¡JEFE!"
	elseif run.Phase == "Result" then
		return "Terminada"
	end
	return ("Oleada %d / %d"):format(math.max(run.Wave, 1), run.Waves)
end

local function broadcast(run: Run)
	run.LastBroadcast = os.clock()
	local state = stateOf(run)
	eventRemote:FireAllClients("State", state)
	if run.StatusLabel then
		run.StatusLabel.Text = statusText(run)
	end
	if run.Prompt then
		run.Prompt.Enabled = run.Phase == "Idle"
	end
end

local function setArenaAttribute(player: Player, arenaId: string?)
	if player.Parent and player:GetAttribute(Constants.Attributes.WaveArena) ~= arenaId then
		player:SetAttribute(Constants.Attributes.WaveArena, arenaId)
	end
end

local function fxNear(position: Vector3, data)
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and (root.Position - position).Magnitude <= FX_RANGE then
			eventRemote:FireClient(player, "Fx", data)
		end
	end
end

-- Premios -------------------------------------------------------------------------------

local function pay(participant: Participant, energy: number, money: number): (number, number)
	local profile = PlayerDataService.get(participant.Player)
	if not profile then
		return 0, 0
	end
	local given = EnergyService.grant(participant.Player, energy)
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
	local radius = run.Arena.SpawnRadius
	local angle = math.random() * math.pi * 2
	local distance = radius.Min + math.random() * (radius.Max - radius.Min)
	return run.Center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

local function spawnOne(run: Run, typeId: string, wave: number): boolean
	local arena = run.Arena
	local enemy = EnemyService.spawnPooled(run.ZoneId, typeId, spawnPoint(run), {
		LeashCenter = run.Center,
		LeashRadius = arena.AreaRadius,
		DetectRange = arena.AreaRadius * 2,
		HealthMultiplier = WaveLogic.healthMultiplier(wave, run.Players),
		RewardMultiplier = WaveLogic.rewardMultiplier(wave),
		PoolLimit = (arena.Pool and arena.Pool[typeId]) or 12,
		OnDeath = onEnemyDeath(run, run.Token),
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
		local token = run.Token
		run.Boss = EnemyService.wakeBoss(run.ZoneId, WaveLogic.bossHealthMultiplier(run.Players), function()
			if run.Token == token and run.Phase == "Boss" then
				finish(run, true)
			end
		end)
		if not run.Boss then
			warn("[WaveService] La arena " .. run.ArenaId .. " no tiene jefe en su zona: se da por ganada.")
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
	run.Best = math.max(run.Best, wave)
	for _, participant in run.Participants do
		local profile = PlayerDataService.get(participant.Player)
		if profile then
			local energy, money = WaveLogic.clearReward(wave, profile.ProductionPerSecond)
			local given, coins = pay(participant, energy, money)
			eventRemote:FireClient(participant.Player, "Cleared", { Wave = wave, Energy = given, Money = coins })
		end
	end
	if WaveLogic.isCardWave(run.ArenaId, wave) then
		enterCards(run)
	else
		enterBreak(run, WaveConfig.BreakSeconds)
	end
end

function finish(run: Run, victory: boolean)
	if run.Phase == "Result" or run.Phase == "Idle" then
		return
	end
	local reached = run.Wave
	if victory then
		run.Best = math.max(run.Best, run.Waves)
	end
	-- Lo que quede de la oleada se retira sin botín (el jefe derrotado ya se fue solo).
	run.Boss = if victory then nil else run.Boss
	despawnAll(run)
	run.Phase = "Result"
	run.EndsAt = os.clock() + WaveConfig.ResultSeconds
	for player, participant in run.Participants do
		local energy, money = 0, 0
		if victory then
			local profile = PlayerDataService.get(player)
			if profile then
				energy, money = pay(participant, WaveLogic.victoryReward(profile.ProductionPerSecond))
			end
		end
		eventRemote:FireClient(player, "Result", {
			Victory = victory,
			Wave = reached,
			Waves = run.Waves,
			Kills = participant.Kills,
			Energy = participant.Energy,
			Money = participant.Money,
			Golden = participant.Golden,
			BestStreak = participant.BestStreak,
			VictoryEnergy = energy,
			VictoryMoney = money,
			Best = run.Best,
		})
	end
	broadcast(run)
end

local function reset(run: Run)
	despawnAll(run)
	for player in run.Participants do
		setArenaAttribute(player, nil)
	end
	table.clear(run.Participants)
	run.Phase = "Idle"
	run.Wave = 0
	run.Total = 0
	run.Killed = 0
	run.EndsAt = 0
	run.EmptySince = nil
	run.Token += 1
	broadcast(run)
end

local function start(run: Run, starter: Player): boolean
	if run.Phase ~= "Idle" then
		return false
	end
	local root = rootOf(starter)
	if not root then
		return false
	end
	if flatDistance(root.Position, run.Pedestal) > START_DISTANCE and flatDistance(root.Position, run.Center) > run.Arena.AreaRadius then
		return false
	end
	run.Token += 1
	table.clear(run.Participants)
	run.Participants[starter] = newParticipant(starter)
	setArenaAttribute(starter, run.ArenaId)
	run.Wave = 0
	run.Phase = "Countdown"
	run.EndsAt = os.clock() + WaveConfig.StartCountdown
	run.EmptySince = nil
	broadcast(run)
	return true
end

function onEnemyDeath(run: Run, token: number)
	return function(enemy, killer: Player?, position: Vector3)
		if run.Token ~= token then
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
		-- Reacción en cadena: lo que matas explota y daña a los de alrededor
		local explode = mods.Explode
		local profile = PlayerDataService.get(killer)
		if explode and profile then
			local shot = PlayerDataService.combatStats(profile).Shot * mods.Damage
			local damage = shot * explode.ShotMultiplier
			fxNear(position, { Kind = "Explode", Position = position, Radius = explode.Radius })
			for _, other in EnemyService.findInRadius(position, explode.Radius, 8) do
				if other ~= enemy and EnemyService.isAlive(other) then
					EnemyService.damage(other, killer, damage)
				end
			end
		end
	end
end

-- Bucle ---------------------------------------------------------------------------------

local function updateParticipants(run: Run)
	if not isActive(run) then
		return
	end
	-- Quien entra durante la partida se suma
	for _, player in Players:GetPlayers() do
		if not run.Participants[player] and isInside(run, player, true) and PlayerDataService.get(player) then
			run.Participants[player] = newParticipant(player)
			setArenaAttribute(player, run.ArenaId)
		end
	end
	for player in run.Participants do
		if not player.Parent then
			run.Participants[player] = nil
		end
	end
end

local function step(run: Run, now: number)
	if run.Phase == "Idle" then
		return
	end
	if run.Phase == "Result" then
		if now >= run.EndsAt then
			reset(run)
		end
		return
	end
	updateParticipants(run)

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
				for _ = 1, math.floor(escort[typeId] / 2) do
					spawnOne(run, typeId, run.Wave)
				end
			end
		end
	end
	if os.clock() - run.LastBroadcast >= STATE_SECONDS then
		broadcast(run)
	end
end

-- Pedestal ------------------------------------------------------------------------------

local function buildPedestal(run: Run, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "WavePedestal_" .. run.ArenaId
	local base = run.Pedestal
	local ground = base.Y
	local stone = Color3.fromRGB(110, 112, 100)
	local rune = Color3.fromRGB(255, 140, 70)
	PartFactory.verticalCylinder(model, "Base", Vector3.new(base.X, ground + 0.4, base.Z), 0.8, 7, stone, Enum.Material.Slate)
	local ring = PartFactory.verticalCylinder(model, "Ring", Vector3.new(base.X, ground + 0.85, base.Z), 0.1, 6.2, rune, Enum.Material.Neon, false)
	ring.Transparency = 0.35
	local column = PartFactory.part(model, "Column", {
		Size = Vector3.new(1.8, 3.4, 1.8),
		CFrame = CFrame.new(base.X, ground + 2.5, base.Z),
		Color = stone,
		Material = Enum.Material.Slate,
	})
	local crystal = PartFactory.part(model, "Crystal", {
		Size = Vector3.new(1.3, 2.2, 1.3),
		CFrame = CFrame.new(base.X, ground + 5.4, base.Z) * CFrame.Angles(0, math.rad(45), math.rad(12)),
		Color = rune,
		Material = Enum.Material.Neon,
		Solid = false,
	})
	local light = Instance.new("PointLight")
	light.Color = rune
	light.Range = 14
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = crystal

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WavePrompt"
	prompt.ActionText = "Empezar oleadas"
	prompt.ObjectText = "⚔ " .. run.Arena.DisplayName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = column
	prompt.Triggered:Connect(function(player: Player)
		start(run, player)
	end)
	run.Prompt = prompt

	-- Cartel flotante: nombre y estado de la partida
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(260, 70)
	billboard.StudsOffset = Vector3.new(0, 4.6, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 140
	billboard.Adornee = crystal
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.55, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 214, 120)
	title.Text = "⚔ OLEADAS"
	title.Parent = billboard
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(43, 29, 63)
	titleStroke.Thickness = 3
	titleStroke.Parent = title
	local status = Instance.new("TextLabel")
	status.Position = UDim2.fromScale(0, 0.58)
	status.Size = UDim2.new(1, 0, 0.42, 0)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.FredokaOne
	status.TextScaled = true
	status.TextColor3 = Color3.new(1, 1, 1)
	status.Text = statusText(run)
	status.Parent = billboard
	local statusStroke = Instance.new("UIStroke")
	statusStroke.Color = Color3.fromRGB(43, 29, 63)
	statusStroke.Thickness = 2
	statusStroke.Parent = status
	billboard.Parent = crystal
	run.StatusLabel = status

	model.Parent = parent
end

-- Arranque ------------------------------------------------------------------------------

local function buildRun(arenaId: string, arena: any): Run?
	local zone = ZoneConfig.Zones[arena.Zone]
	local zoneEnemies = EnemyConfig.Zones[arena.Zone]
	local bossArena = zoneEnemies and zoneEnemies.Boss and zoneEnemies.Boss.Arena
	if not (zone and bossArena) then
		warn("[WaveService] La arena " .. arenaId .. " no tiene zona o arena de jefe: no se crea.")
		return nil
	end
	local base = GeneratorConfig.Position
	local zoneCenter = Vector3.new(base.X + zone.Center.X, GROUND, base.Z + zone.Center.Y)
	local center = zoneCenter + Vector3.new(bossArena.Center.X, 0, bossArena.Center.Y)
	-- Pedestal en la entrada de la arena (mirando al centro de la zona, como el cartel)
	local toZone = zoneCenter - center
	local direction = if toZone.Magnitude > 0.1 then Vector3.new(toZone.X, 0, toZone.Z).Unit else Vector3.new(0, 0, 1)
	local spot = center + direction * arena.PedestalDistance
	local pedestal = Vector3.new(spot.X, GROUND + StudFloor.raiseAt(spot.X, spot.Z), spot.Z)
	return {
		ArenaId = arenaId,
		Arena = arena,
		ZoneId = arena.Zone,
		Center = center,
		Pedestal = pedestal,
		Phase = "Idle",
		Wave = 0,
		Waves = WaveLogic.waveCount(arenaId),
		EndsAt = 0,
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
		Token = 0,
		Best = 0,
		LastBroadcast = 0,
		StatusLabel = nil,
		Prompt = nil,
	}
end

function WaveService.start()
	eventRemote = RemoteService.get(Constants.Remotes.WaveEvent)
	PartFactory.removeExisting(Workspace, FOLDER_NAME)
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace

	for arenaId, arena in WaveConfig.Arenas do
		local run = buildRun(arenaId, arena)
		if run then
			runs[arenaId] = run
			buildPedestal(run, folder)
			if arena.BossOnlyInWaves then
				EnemyService.setBossWaveControlled(arena.Zone, true)
			end
		end
	end

	-- Dentro de una partida el arma dispara sola y lleva las mejoras elegidas
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
			local run = type(value) == "string" and runs[value]
			if run then
				start(run, player)
			end
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

	-- Al entrar, el estado de cada arena
	Players.PlayerAdded:Connect(function(player)
		for _, run in runs do
			eventRemote:FireClient(player, "State", stateOf(run))
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		actionLimiter:remove(player)
		for _, run in runs do
			run.Participants[player] = nil
		end
	end)

	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			local now = os.clock()
			for arenaId, run in runs do
				local ok, err = pcall(step, run, now)
				if not ok then
					warn("[WaveService] Error en la arena " .. arenaId .. ": " .. tostring(err))
				end
			end
		end
	end)
	for _, run in runs do
		broadcast(run)
	end
end

return WaveService
