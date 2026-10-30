-- WaveService · Waves: fases de la partida: jefes (y el que se parte), empezar oleada, mejoras y pausa.
-- Parte de WaveService (ver WaveService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WaveConfig = require(Shared.Config.WaveConfig)
local WaveLogic = require(Shared.WaveLogic)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local EnemyService = require(script.Parent.Parent.EnemyService)
local Types = require(script.Parent.Types)
type Participant = Types.Participant
type Run = Types.Run

local ctx: any -- tabla de estado compartida (la crea WaveService/init.luau)
local CARD_BREAK: any
local INSIDE_SLACK: any
local runs: any

-- Funciones de las otras partes
local function broadcast(...) return ctx.broadcast(...) end
local function despawnAll(...) return ctx.despawnAll(...) end
local function enterChoice(...) return ctx.enterChoice(...) end
local function finish(...) return ctx.finish(...) end
local function fxTo(...) return ctx.fxTo(...) end
local function hint(...) return ctx.hint(...) end
local function insideCount(...) return ctx.insideCount(...) end
local function recordCleared(...) return ctx.recordCleared(...) end
local function waveCleared(...) return ctx.waveCleared(...) end
local function serverTime(...) return ctx.serverTime(...) end

-- Fases ---------------------------------------------------------------------------------

local enterBreak: (Run, number) -> ()

-- Cayó el último jefe: victoria (con modo infinito, se cobra y cada uno elige si sigue). Si
-- era el jefe que vuelve en el modo infinito, es una oleada superada más: la escolta se
-- retira y se sigue.
local function bossesDefeated(run: Run)
	if run.Endless then
		despawnAll(run)
		waveCleared(run)
		return
	end
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
		HealthMultiplier = WaveLogic.bossHealthMultiplier(run.Players) * WaveLogic.endlessBossHealth(run.ArenaId, run.Wave) * run.Effects.BossHealth,
		DamageMultiplier = run.Effects.Damage,
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
	if WaveLogic.isBossWave(run.ArenaId, wave) or (run.Endless and WaveLogic.isEndlessBossWave(run.ArenaId, wave)) then
		run.Phase = "Boss"
		run.Queue = {}
		run.Total = 1
		run.NextEscortAt = os.clock() + 4
		if not spawnBoss(run) then
			if run.Endless then
				-- Modo infinito: sin jefe esta vez, se sigue con la siguiente
				warn("[WaveService] No hay sitio en la reserva para el jefe " .. tostring(run.Arena.Boss) .. " del modo infinito: se salta.")
				waveCleared(run)
				return
			end
			warn("[WaveService] No hay sitio en la reserva para el jefe " .. tostring(run.Arena.Boss) .. ": la partida se da por ganada.")
			finish(run, true)
			return
		end
	else
		run.Phase = "Wave"
		run.Queue = WaveLogic.spawnList(run.ArenaId, wave, math.random, run.Effects.CountScale)
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
		local choices = WaveLogic.rollCards(participant.Levels, math.random, WaveConfig.CardChoices, { Style = participant.Style, RareBoost = run.Effects.RareBoost })
		participant.Choices = if #choices > 0 then choices else nil
		if participant.Choices then
			anyChoice = true
			local cards = {}
			for _, cardId in choices do
				local card = WaveConfig.Cards[cardId]
				table.insert(cards, { Id = cardId, Icon = card.Icon, Name = card.Name, Text = card.Text, Level = WaveLogic.levelOf(participant.Levels, cardId), MaxLevel = card.MaxLevel, Rarity = card.Rarity or "Common", Class = card.Style ~= nil })
			end
			ctx.eventRemote:FireClient(player, "Cards", { Cards = cards, EndsAt = serverTime(run.EndsAt), Wave = run.Wave })
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
	ctx.eventRemote:FireClient(participant.Player, "Picked", { Id = cardId, Levels = levels })
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

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.applyPick = applyPick
	context.enterBreak = enterBreak
	context.enterCards = enterCards
	context.everyonePicked = everyonePicked
	context.startWave = startWave
end

function Part.link(context: any)
	CARD_BREAK = context.CARD_BREAK
	INSIDE_SLACK = context.INSIDE_SLACK
	runs = context.runs
end

return Part
