-- EnemyService · Core: constantes, estado de los enemigos, mundos de las oleadas privadas y búsquedas.
-- Parte de EnemyService (ver EnemyService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local WaveLogic = require(Shared.WaveLogic)
local Types = require(script.Parent.Types)
type Enemy = Types.Enemy

local ctx: any -- tabla de estado compartida (la crea EnemyService/init.luau)
local EnemyService: any -- la tabla pública del servicio
local Api = {} -- funciones públicas de esta parte (init.luau las copia a EnemyService)

local FOLDER_NAME = "Enemies"
local ARENAS_NAME = "BossArenas"
local GROUND = GeneratorConfig.Position.Y
local WINDUP_EYES = Color3.fromRGB(255, 70, 60)
local ENRAGED_EYES = Color3.fromRGB(255, 120, 40)
-- Tiempo que el cuerpo sigue en el mundo tras morir, para que el cliente lo disuelva
-- (ya está muerto: no recibe golpes ni ataca). Solo presentación.
local DISSOLVE_SECONDS = { Normal = 0.8, Strong = 0.9, Boss = 1.6 }
-- Tope de seguridad de cualquier estado (AbilityConfig.MaxControlSeconds).
local MAX_CONTROL_SECONDS = 10
local KNOCKBACK_SECONDS = 0.18 -- duración del empujón (distancia ≈ fuerza · duración)
-- Atributo de presentación de cada estado (hora del servidor a la que termina).
local STATUS_ATTRIBUTES = { Slow = "SlowUntil", Root = "RootUntil", Stun = "StunUntil", Vulnerable = "CurseUntil", Burn = "BurnUntil" }
-- Barra de vida como la de Roblox (la de los jugadores): nombre blanco con sombra y barra
-- verde que pasa a amarilla y a roja al bajar. El nombre de los fuertes y los jefes lleva un
-- toque de color para distinguirlos.
local BAR_HEALTHY = Color3.fromRGB(27, 252, 107)
local BAR_WARNING = Color3.fromRGB(250, 235, 0)
local BAR_CRITICAL = Color3.fromRGB(255, 28, 0)
local BAR_TRACK = Color3.fromRGB(28, 28, 28)
local KIND_NAME_COLORS = {
	Normal = Color3.fromRGB(255, 255, 255),
	Strong = Color3.fromRGB(255, 214, 140),
	Boss = Color3.fromRGB(255, 150, 150),
}
-- Contorno oscuro alrededor de cada enemigo (estilo caricatura).
local INK = Color3.fromRGB(43, 29, 63)
local BAR_SIZES = { Normal = UDim2.fromOffset(130, 32), Strong = UDim2.fromOffset(150, 34), Boss = UDim2.fromOffset(190, 38) }
local BAR_DISTANCE = { Normal = 120, Strong = 140, Boss = 180 }

-- Color de la barra según la vida que queda (0..1), como la de Roblox.
local function healthColor(fraction: number): Color3
	if fraction >= 0.5 then
		return BAR_HEALTHY
	elseif fraction >= 0.25 then
		return BAR_WARNING:Lerp(BAR_HEALTHY, (fraction - 0.25) / 0.25)
	end
	return BAR_CRITICAL:Lerp(BAR_WARNING, math.max(0, fraction) / 0.25)
end



local enemies: { Enemy } = {}
-- Reserva de enemigos de las oleadas: "<zona>/<tipo>" -> libres y cuántos se han creado.
local pools: { [string]: { Enemy } } = {}
-- Élites de las salas de las mazmorras: cuántos pequeños lleva cada cueva (uno de cada
-- round(1 / EliteChance) es élite: siempre los mismos)
local eliteCount: { [string]: number } = {}
local poolCreated: { [string]: number } = {}
-- Jefe de cada zona (para las oleadas).
local bossByZone: { [string]: Enemy } = {}
-- Racha de cada jugador (WaveLogic) y extra de las mejoras de la partida (WaveService).
local streaks: { [Player]: WaveLogic.Streak } = {}
-- Modificador del daño que los enemigos hacen a los jugadores (lo registra
-- PetCombatService para la Tortuga). Un único punto: nunca se aplica dos veces.
-- Daño que hace el jugador según su clase (StyleService: más a los jefes)
-- Avisos de "este jugador ha derrotado a este enemigo" (los usa QuestService). Solo
-- informan: no cambian la muerte ni la recompensa.
local defeatListeners: { (Player, { TypeId: string, Kind: string, ZoneId: string, Reward: number }) -> () } = {}
local clickListeners: { (Player, Enemy) -> () } = {}

-- Oleadas privadas (WaveService) ------------------------------------------------------------
local RUN_ATTRIBUTE = Constants.Attributes.WaveRun
local WAVE_GROUP = "WaveEnemies" -- grupo de colisión de los de la reserva (sin partida)
local CHARACTER_GROUP = "Characters" -- personajes de los jugadores
-- Un grupo por partida a la vez ("WaveRun1".."WaveRunN", N = WaveConfig.MaxRuns): los de la
-- misma partida chocan entre ellos (rodean al jugador en vez de amontonarse en un punto),
-- pero no con los de otras partidas ni con los personajes.
local WAVE_SLOT_PREFIX = "WaveRun"

-- Partida que juega un jugador (nil = el mundo normal).
local function runOfPlayer(player: Player): number?
	local value = player:GetAttribute(RUN_ATTRIBUTE)
	return if type(value) == "number" then value else nil
end

-- ¿El enemigo y el jugador están en el mismo "mundo"?
local function sameWorld(enemy: Enemy, player: Player): boolean
	return enemy.Run == runOfPlayer(player)
end

-- ¿Este jugador puede ver, apuntar y golpear a este enemigo?
function Api.canInteract(player: Player, enemy: any): boolean
	return enemy ~= nil and sameWorld(enemy, player)
end

-- Marca una pieza de efecto con la partida de su enemigo (el cliente oculta las ajenas).
local function tagRun(instance: Instance, run: number?)
	if run ~= nil then
		instance:SetAttribute(RUN_ATTRIBUTE, run)
	end
end

-- Pieza de efecto creada sin padre: se marca con su partida y LUEGO se pone en el mundo
-- (así llega ya marcada y los demás jugadores no la ven ni un instante).
local function placeFx(part: Instance, run: number?)
	tagRun(part, run)
	part.Parent = ctx.fxFolder
end

local function setCollisionGroup(model: Instance, group: string)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

function Api.onDefeated(listener: (Player, { TypeId: string, Kind: string, ZoneId: string, Reward: number }) -> ())
	table.insert(defeatListeners, listener)
end

function Api.onClicked(listener: (Player, Enemy) -> ())
	table.insert(clickListeners, listener)
end

function Api.findNearest(center: Vector3, maxRange: number): Enemy?
	local best: Enemy? = nil
	local bestDist = maxRange
	for _, enemy in enemies do
		if EnemyService.isAlive(enemy) then
			local d = Vector2.new(enemy.Root.Position.X - center.X, enemy.Root.Position.Z - center.Z).Magnitude
			if d <= bestDist then
				bestDist = d
				best = enemy
			end
		end
	end
	return best
end

-- El enemigo de un modelo (el cliente lo propone al apuntar; quien llama comprueba que
-- esté vivo y a su alcance).
function Api.fromModel(model: Instance): Enemy?
	for _, enemy in enemies do
		if enemy.Model == model then
			return enemy
		end
	end
	return nil
end

local function zoneCenter(zoneId: string): Vector3
	local zone = ZoneConfig.Zones[zoneId]
	local base = GeneratorConfig.Position
	return Vector3.new(base.X + zone.Center.X, GROUND, base.Z + zone.Center.Y)
end

local function flat(vector: Vector3): number
	return Vector2.new(vector.X, vector.Z).Magnitude
end

local Part = { Api = Api }

function Part.install(context: any)
	ctx = context
	context.ARENAS_NAME = ARENAS_NAME
	context.BAR_DISTANCE = BAR_DISTANCE
	context.BAR_HEALTHY = BAR_HEALTHY
	context.BAR_SIZES = BAR_SIZES
	context.BAR_TRACK = BAR_TRACK
	context.CHARACTER_GROUP = CHARACTER_GROUP
	context.DISSOLVE_SECONDS = DISSOLVE_SECONDS
	context.ENRAGED_EYES = ENRAGED_EYES
	context.FOLDER_NAME = FOLDER_NAME
	context.GROUND = GROUND
	context.INK = INK
	context.KIND_NAME_COLORS = KIND_NAME_COLORS
	context.KNOCKBACK_SECONDS = KNOCKBACK_SECONDS
	context.MAX_CONTROL_SECONDS = MAX_CONTROL_SECONDS
	context.RUN_ATTRIBUTE = RUN_ATTRIBUTE
	context.STATUS_ATTRIBUTES = STATUS_ATTRIBUTES
	context.WAVE_GROUP = WAVE_GROUP
	context.WAVE_SLOT_PREFIX = WAVE_SLOT_PREFIX
	context.WINDUP_EYES = WINDUP_EYES
	context.bossByZone = bossByZone
	context.clickListeners = clickListeners
	context.defeatListeners = defeatListeners
	context.eliteCount = eliteCount
	context.enemies = enemies
	context.flat = flat
	context.healthColor = healthColor
	context.placeFx = placeFx
	context.poolCreated = poolCreated
	context.pools = pools
	context.runOfPlayer = runOfPlayer
	context.sameWorld = sameWorld
	context.setCollisionGroup = setCollisionGroup
	context.streaks = streaks
	context.tagRun = tagRun
	context.zoneCenter = zoneCenter
end

function Part.link(context: any)
	EnemyService = context.Service
end

return Part
