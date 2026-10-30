-- WaveService · Core: constantes, práctica del tutorial, partidas y participantes.
-- Parte de WaveService (ver WaveService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WaveConfig = require(Shared.Config.WaveConfig)
local WaveLogic = require(Shared.WaveLogic)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local TutorialConfig = require(Shared.Config.TutorialConfig)
local StyleLogic = require(Shared.StyleLogic)
local PlayerDataService = require(script.Parent.Parent.PlayerDataService)
local RateLimiter = require(script.Parent.Parent.Parent.Util.RateLimiter)
local Types = require(script.Parent.Types)
type Participant = Types.Participant
type Place = Types.Place
type Run = Types.Run


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
local PRACTICE_DONE_HINT = "⚔ Las Oleadas del Guardián están en la 🦇 Cueva de los Espinillos: al fondo del Bosque de Espinas, junto a la puerta del Valle."



local places: { [string]: Place } = {}
local runs: { [number]: Run } = {}
local runOf: { [Player]: Run } = {}
local lockedUntil: { [Player]: number } = {}
local best: { [string]: number } = {} -- mejor oleada superada en este servidor, por modo
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
	local profile = PlayerDataService.get(player)
	return {
		Player = player,
		Style = if profile then StyleLogic.sanitize(profile.PetData.Style) else nil,
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

local Part = { Api = {} }

function Part.install(context: any)
	context.CARD_BREAK = CARD_BREAK
	context.FOLDER_NAME = FOLDER_NAME
	context.GROUND = GROUND
	context.HINT_SECONDS = HINT_SECONDS
	context.INSIDE_SLACK = INSIDE_SLACK
	context.PRACTICE_DONE_HINT = PRACTICE_DONE_HINT
	context.RESTART_LOCK = RESTART_LOCK
	context.STATE_SECONDS = STATE_SECONDS
	context.TICK_SECONDS = TICK_SECONDS
	context.TUTORIAL_MODE = TUTORIAL_MODE
	context.TUTORIAL_PLACE = TUTORIAL_PLACE
	context.TUTORIAL_STEP = TUTORIAL_STEP
	context.actionLimiter = actionLimiter
	context.activeParticipant = activeParticipant
	context.best = best
	context.flatDistance = flatDistance
	context.isActive = isActive
	context.isInside = isInside
	context.lockedUntil = lockedUntil
	context.newParticipant = newParticipant
	context.participantCount = participantCount
	context.places = places
	context.rootOf = rootOf
	context.runCount = runCount
	context.runOf = runOf
	context.runs = runs
	context.serverTime = serverTime
end

function Part.link(context: any)
	-- (nada que enlazar)
end

return Part
