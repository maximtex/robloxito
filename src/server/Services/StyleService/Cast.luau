-- StyleService · Cast: lo que comparten las habilidades: combos, golpes, efectos, objetivos, puntería, empujes y embestida.
-- Parte de StyleService (ver StyleService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local AbilityLogic = require(Shared.AbilityLogic)
local CaveLogic = require(Shared.CaveLogic)
local EnemyService = require(script.Parent.Parent.EnemyService)
local CombatService = require(script.Parent.Parent.CombatService)
local PetCombatService = require(script.Parent.Parent.PetCombatService)
local Types = require(script.Parent.Types)
type Cast = Types.Cast

local ctx: any -- tabla de estado compartida (la crea StyleService/init.luau)
local COMBO: any
local DASH_STEP: any
local DASH_WALL_GAP: any

-- Funciones de las otras partes
local function broadcast(...) return ctx.broadcast(...) end

-- Multiplicador de los combos para un golpe de la habilidad a `enemy` (y su nombre).
local function comboFor(cast: Cast, enemy: any, ignoreStun: boolean?): (number, string?)
	local multiplier, name = 1, nil
	if not ignoreStun and EnemyService.isStunned(enemy) then
		multiplier *= COMBO.Stunned
		name = COMBO.Names.Stunned[cast.Style]
	end
	if cast.Buffed then
		multiplier *= COMBO.Buffed
		name = name or COMBO.Names.Buffed[cast.Style]
	end
	if cast.Element then
		-- Habilidades de Magia: su elemento deja marca o dispara el combo de la pareja
		multiplier *= PetCombatService.elementHit(cast.Player, enemy, cast.Element, cast.Damage)
	else
		local aura = EnemyService.auraOf(enemy)
		if aura then
			multiplier *= COMBO.Element
			name = COMBO.Names.Element
			EnemyService.setAura(enemy, nil) -- se gasta
		end
	end
	return math.min(multiplier, COMBO.Max), name
end

-- Un golpe de la habilidad a un enemigo (cuenta como golpe del jugador para su objetivo).
-- `scale`: parte del daño base (los golpes de cada momento del agujero negro).
local function hit(cast: Cast, enemy: any, hits: { any }, scale: number?, ignoreStun: boolean?): boolean
	local multiplier, name = comboFor(cast, enemy, ignoreStun)
	local dealt, killed = EnemyService.damage(enemy, cast.Player, cast.Damage * (scale or 1) * multiplier)
	if dealt > 0 then
		table.insert(hits, { Position = enemy.Root.Position, Damage = dealt, Killed = killed, Kind = enemy.Kind, Combo = name })
		if name and not cast.Combo then
			cast.Combo = name
			cast.ComboAt = enemy.Root.Position
		end
		if not killed then
			CombatService.reportHit(cast.Player, enemy)
		end
	end
	return killed
end

-- Aviso del combo (una vez por habilidad)
local function announceCombo(cast: Cast)
	if cast.Combo and cast.ComboAt then
		broadcast(cast.Player, cast.ComboAt, { Kind = "Combo", Name = cast.Combo, Position = cast.ComboAt, Style = cast.Style })
		cast.ComboAt = nil
	end
end

-- El color de los efectos de la habilidad va en cada aviso al cliente (si tiene uno propio)
local function fx(cast: Cast, event: { [string]: any }): { [string]: any }
	if cast.Color then
		event.Color = cast.Color
	end
	return event
end

-- Enemigos válidos alrededor de `center` para el jugador
local function targetsAround(player: Player, center: Vector3, radius: number, maxTargets: number): { any }
	local list = {}
	for _, enemy in EnemyService.findInRadius(center, radius, maxTargets, player) do
		if EnemyService.canInteract(player, enemy) then
			table.insert(list, enemy)
		end
	end
	return list
end

local function nearestTarget(player: Player, center: Vector3, range: number): any?
	return targetsAround(player, center, range, 1)[1]
end

-- Punto apuntado para la habilidad, sin pasar de `range` desde el personaje (nil si no apuntó).
-- A la altura del suelo apuntado si está cerca de la tuya; si no, a la tuya.
local function aimedPoint(cast: Cast, root: BasePart, range: number): Vector3?
	local aim = cast.Aim
	if not aim then
		return nil
	end
	local origin = root.Position
	local flat = Vector3.new(aim.X - origin.X, 0, aim.Z - origin.Z)
	if flat.Magnitude > range then
		flat = flat.Unit * range
	end
	local y = if math.abs(aim.Y - origin.Y) <= 12 then aim.Y + 1 else origin.Y
	return Vector3.new(origin.X + flat.X, y, origin.Z + flat.Z)
end

-- Dirección (en plano) hacia el punto apuntado; nil si no apuntó o está encima
local function aimedDirection(cast: Cast, root: BasePart): Vector3?
	local aim = cast.Aim
	if not aim then
		return nil
	end
	local flat = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
	return if flat.Magnitude > 0.5 then flat.Unit else nil
end

-- Atrae a `enemy` hacia `center` (el retroceso de EnemyService, hacia dentro)
local function pull(enemy: any, center: Vector3, force: number)
	local position = enemy.Root.Position
	local away = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
	if away.Magnitude < 1.5 then
		return
	end
	EnemyService.knockback(enemy, position + away.Unit * 2, force)
end

-- Hasta dónde se puede ir desde `origin` hacia `direction`: sin atravesar paredes, sin
-- salirse del suelo y sin cruzar una puerta cerrada de la cueva.
local function dashReach(player: Player, origin: Vector3, direction: Vector3, distance: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local ignore = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	local enemies = Workspace:FindFirstChild("Enemies")
	if enemies then
		table.insert(ignore, enemies)
	end
	params.FilterDescendantsInstances = ignore
	local limit = distance
	-- A la altura del cuerpo y a la de las rodillas (rocas bajas)
	for _, height in { 0, -1.6 } do
		local start = origin + Vector3.new(0, height, 0)
		local wall = Workspace:Raycast(start, direction * distance, params)
		if wall then
			limit = math.min(limit, math.max(0, (wall.Position - start).Magnitude - DASH_WALL_GAP))
		end
	end
	local progress = CaveLogic.parseProgress(player:GetAttribute(Constants.Attributes.CaveGates))
	local reach = 0
	local step = DASH_STEP
	while step <= limit + 1e-6 do
		local point = origin + direction * step
		local ahead = origin + direction * (step + 2) -- el cuerpo no se mete en la puerta
		local blocked = CaveLogic.inside(ahead.X, ahead.Z) and CaveLogic.blockedAt(ahead.X, ahead.Z, progress) ~= nil
		local ground = Workspace:Raycast(point, Vector3.new(0, -10, 0), params)
		if blocked or not ground then
			break
		end
		reach = step
		step += DASH_STEP
	end
	return reach
end

-- Hacia donde se mueve el personaje (o hacia donde mira si está quieto), en plano
local function moveDirection(player: Player, root: BasePart): Vector3
	local character = player.Character :: Model
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	local move = humanoid.MoveDirection
	local look = root.CFrame.LookVector
	local direction = if move.Magnitude > 0.1 then Vector3.new(move.X, 0, move.Z) else Vector3.new(look.X, 0, look.Z)
	return if direction.Magnitude > 0.05 then direction.Unit else Vector3.new(0, 0, -1)
end

local function stun(enemy: any, seconds: number)
	if EnemyService.isAlive(enemy) then
		EnemyService.applyControl(enemy, "Stun", (AbilityLogic.control("Stun", seconds, nil, enemy.Kind == "Boss")))
	end
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.aimedDirection = aimedDirection
	context.aimedPoint = aimedPoint
	context.announceCombo = announceCombo
	context.dashReach = dashReach
	context.fx = fx
	context.hit = hit
	context.moveDirection = moveDirection
	context.nearestTarget = nearestTarget
	context.pull = pull
	context.stun = stun
	context.targetsAround = targetsAround
end

function Part.link(context: any)
	COMBO = context.COMBO
	DASH_STEP = context.DASH_STEP
	DASH_WALL_GAP = context.DASH_WALL_GAP
end

return Part
