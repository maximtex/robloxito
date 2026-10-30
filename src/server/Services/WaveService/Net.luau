-- WaveService · Net: envíos al cliente: estado de la partida, cartel del altar, avisos y consejos.
-- Parte de WaveService (ver WaveService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local WaveConfig = require(Shared.Config.WaveConfig)
local WaveLogic = require(Shared.WaveLogic)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local EnemyService = require(script.Parent.Parent.EnemyService)
local Types = require(script.Parent.Types)
type Run = Types.Run

local ctx: any -- tabla de estado compartida (la crea WaveService/init.luau)
local HINT_SECONDS: any
local best: any
local places: any
local runs: any

-- Funciones de las otras partes
local function participantCount(...) return ctx.participantCount(...) end
local function serverTime(...) return ctx.serverTime(...) end

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
			place.InfoLabel.Text = "Las del Guardián: en la 🦇 Cueva, al fondo junto a la puerta del Valle"
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
			ctx.eventRemote:FireClient(player, "State", state)
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
			ctx.eventRemote:FireClient(player, "Fx", data)
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
			ctx.eventRemote:FireClient(player, "Hint", { Text = text, Seconds = HINT_SECONDS })
		end
	end
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.broadcast = broadcast
	context.fxTo = fxTo
	context.hint = hint
	context.joinableRun = joinableRun
	context.setPlayerRun = setPlayerRun
	context.updateSign = updateSign
end

function Part.link(context: any)
	HINT_SECONDS = context.HINT_SECONDS
	best = context.best
	places = context.places
	runs = context.runs
end

return Part
