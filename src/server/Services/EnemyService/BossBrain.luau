-- EnemyService · BossBrain: IA de jefe: estado, territorio, rutas, avisos en el suelo y ayudas de sus ataques.
-- Parte de EnemyService (ver EnemyService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Debris = game:GetService("Debris")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local StudFloor = require(Shared.Util.StudFloor)
local PartFactory = require(script.Parent.Parent.Parent.Util.PartFactory)
local Types = require(script.Parent.Types)
type Brain = Types.Brain
type Enemy = Types.Enemy

local ctx: any -- tabla de estado compartida (la crea EnemyService/init.luau)
local GROUND: any
local resetBrain: any -- (declarada aquí; antes, más arriba en el original)

-- Funciones de las otras partes
local function characterOf(...) return ctx.characterOf(...) end
local function damagePlayer(...) return ctx.damagePlayer(...) end
local function flat(...) return ctx.flat(...) end
local function inSafeZone(...) return ctx.inSafeZone(...) end
local function placeFx(...) return ctx.placeFx(...) end
local function sameWorld(...) return ctx.sameWorld(...) end

-- IA de jefe ------------------------------------------------------------------------
-- Máquina de estados de cada jefe (enemy.Brain.State, Def.Brain):
-- - "Patrol": vigila su arena andando de un sitio a otro.
-- - "Chase": persigue a su objetivo (lo ve a DetectRange o le ha disparado). Si algo se
--   interpone usa una ruta de PathfindingService, que solo se recalcula cuando el objetivo
--   se ha movido bastante, cuando se atasca o cada PATH_REFRESH. Nunca sale de su
--   territorio (Territory studs desde el centro de la arena): si el objetivo se aleja más
--   de Territory + LOSE_MARGIN, muere o entra en una zona segura, lo deja.
-- - "Busy": prepara o hace un ataque. Cada ataque se anuncia (ojos rojos y una marca en
--   el suelo durante su Telegraph) y su daño se valida al final con la posición real.
-- - "Recover": descansa RecoverSeconds tras atacar (ventana para contraatacar).
-- - "Return": vuelve al centro de su arena (invulnerable, como todos) y se cura al llegar.
-- Un objetivo se mantiene LockSeconds aunque otro jugador esté más cerca.
-- Ataques: golpe cuerpo a cuerpo (Damage) y los especiales de su tipo: Slam (área a su
-- alrededor), Roots (atrapa y ralentiza donde estás), Charge (embestida en línea), Leap
-- (salta y cae donde estabas) y Volley (bolas de fuego que se pueden esquivar).
-- Además (pruebas con amigos: "se les hace kite fácil" y "las arenas no tienen nada"):
-- - Persecución (EnemyConfig.Pursuit): si su objetivo se le escapa, acelera poco a poco.
-- - Peligros de la arena (Def.Hazard): mientras pelea caen cosas avisadas en el suelo cerca
--   de los jugadores (espinas, cristales, lava, hielo...), cada jefe las suyas.

local PATH_REFRESH = 1.5 -- segundos mínimos entre rutas para el mismo objetivo quieto
local PATH_GOAL_MOVED = 6 -- studs que debe moverse el objetivo para recalcular la ruta
local WAYPOINT_REACHED = 3
local LOSE_MARGIN = 12
local STUCK_SECONDS = 1.2
local TELEGRAPH_RED = Color3.fromRGB(255, 70, 60)


local SPECIALS = { "Slam", "Roots", "Charge", "Leap", "Volley" }

local function newBrain(): Brain
	return {
		State = "Patrol",
		Until = 0,
		LockedUntil = 0,
		Path = nil,
		PathIndex = 1,
		PathGoal = nil,
		PathAt = -math.huge,
		Computing = false,
		NextSpecial = {},
		LastPosition = Vector3.zero,
		StillSince = 0,
		Dash = nil,
		FarSince = nil,
		NextHazard = nil,
	}
end

-- Al reaparecer: patrulla y los especiales escalonados (no todos a la vez al empezar)
function resetBrain(enemy: Enemy, now: number)
	local brain = enemy.Brain :: Brain
	brain.State = "Patrol"
	brain.Until = 0
	brain.LockedUntil = 0
	brain.Path = nil
	brain.PathGoal = nil
	brain.Dash = nil
	brain.FarSince = nil
	enemy.SpeedBoost = 1
	local hazard = enemy.Def.Hazard
	brain.NextHazard = if hazard then now + (hazard.Interval or 8) * 0.6 else nil
	for index, name in SPECIALS do
		local settings = enemy.Def[name]
		if settings then
			brain.NextSpecial[name] = now + settings.Interval * 0.5 + index
		end
	end
	enemy.Model:SetAttribute("TargetUserId", nil)
	enemy.Model:SetAttribute("BossState", "Patrol")
end

local function setBossState(enemy: Enemy, state: string)
	local brain = enemy.Brain :: Brain
	if brain.State ~= state then
		brain.State = state
		enemy.Model:SetAttribute("BossState", state)
	end
end

local function territoryOf(enemy: Enemy): number
	return enemy.Territory or enemy.Def.Brain.Territory
end

-- Punto dentro del territorio (el jefe nunca sale de él)
local function clampToTerritory(enemy: Enemy, point: Vector3): Vector3
	local offset = point - enemy.LeashCenter
	local flatOffset = Vector3.new(offset.X, 0, offset.Z)
	local limit = territoryOf(enemy) - 2
	if flatOffset.Magnitude > limit then
		flatOffset = flatOffset.Unit * limit
	end
	return Vector3.new(enemy.LeashCenter.X + flatOffset.X, point.Y, enemy.LeashCenter.Z + flatOffset.Z)
end

local function bossCanTarget(enemy: Enemy, position: Vector3): boolean
	return flat(position - enemy.LeashCenter) <= territoryOf(enemy) + LOSE_MARGIN and not inSafeZone(enemy, position)
end

local function bossAcquire(enemy: Enemy): Player?
	local best, bestDistance = nil, enemy.Def.Brain.DetectRange
	for _, player in Players:GetPlayers() do
		local root = characterOf(player)
		if root then
			local distance = flat(root.Position - enemy.Root.Position)
			if distance <= bestDistance and sameWorld(enemy, player) and flat(root.Position - enemy.LeashCenter) <= territoryOf(enemy) and bossCanTarget(enemy, root.Position) then
				best, bestDistance = player, distance
			end
		end
	end
	return best
end

-- ¿Hay algo entre el jefe y el punto? (sin contar enemigos ni personajes)
local function lineBlocked(enemy: Enemy, goal: Vector3): boolean
	local origin = enemy.Root.Position
	local direction = Vector3.new(goal.X - origin.X, 0, goal.Z - origin.Z)
	if direction.Magnitude < 1 then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { ctx.folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	-- A media altura del cuerpo: el suelo y las alfombras no cuentan como obstáculo
	local hit = Workspace:Raycast(origin + Vector3.new(0, 1, 0), direction, params)
	return hit ~= nil and hit.Instance.CanCollide
end

local function requestPath(enemy: Enemy, goal: Vector3)
	local brain = enemy.Brain :: Brain
	if brain.Computing then
		return
	end
	brain.Computing = true
	brain.PathAt = os.clock()
	brain.PathGoal = goal
	local generation = enemy.Generation
	local from = enemy.Root.Position
	task.spawn(function()
		local path = PathfindingService:CreatePath({ AgentRadius = math.max(2, enemy.Radius), AgentHeight = 6, AgentCanJump = false, WaypointSpacing = 5 })
		local ok = pcall(function()
			path:ComputeAsync(from, goal)
		end)
		brain.Computing = false
		if enemy.Generation ~= generation then
			return
		end
		if ok and path.Status == Enum.PathStatus.Success then
			local points = {}
			for _, waypoint in path:GetWaypoints() do
				table.insert(points, waypoint.Position)
			end
			brain.Path = points
			brain.PathIndex = math.min(2, #points)
		else
			brain.Path = nil -- sin ruta: va en línea recta (y si se atasca, lo deja)
		end
	end)
end

-- Andar hacia `goal` (dentro del territorio): recto si nada lo impide; si no, por la ruta.
local function bossMoveTo(enemy: Enemy, goal: Vector3, now: number)
	local brain = enemy.Brain :: Brain
	goal = clampToTerritory(enemy, goal)
	if not lineBlocked(enemy, goal) then
		brain.Path = nil
		enemy.Humanoid:MoveTo(goal)
		return
	end
	local stale = brain.PathGoal == nil or flat(goal - brain.PathGoal) > PATH_GOAL_MOVED or (now - brain.PathAt > PATH_REFRESH and now - brain.StillSince > STUCK_SECONDS)
	if (brain.Path == nil or stale) and now - brain.PathAt > 0.4 then
		requestPath(enemy, goal)
	end
	local path = brain.Path
	if path and path[brain.PathIndex] then
		local waypoint = path[brain.PathIndex]
		if flat(waypoint - enemy.Root.Position) < WAYPOINT_REACHED and brain.PathIndex < #path then
			brain.PathIndex += 1
			waypoint = path[brain.PathIndex]
		end
		enemy.Humanoid:MoveTo(waypoint)
	else
		enemy.Humanoid:MoveTo(goal)
	end
end

-- Marca de aviso en el suelo: borde fijo y un disco que crece hasta llenarlo cuando golpea
local function telegraphDisc(center: Vector3, radius: number, color: Color3, seconds: number, run: number?)
	local ground = Vector3.new(center.X, GROUND + StudFloor.raiseAt(center.X, center.Z), center.Z)
	local diameter = radius * 2
	local ring = PartFactory.verticalCylinder(nil :: any, "BossWarning", ground + Vector3.new(0, 0.32, 0), 0.12, diameter, color, Enum.Material.Neon, false)
	ring.Transparency = 0.55
	placeFx(ring, run)
	local fill = PartFactory.verticalCylinder(nil :: any, "BossWarningFill", ground + Vector3.new(0, 0.36, 0), 0.14, 1, color, Enum.Material.Neon, false)
	fill.Transparency = 0.55
	placeFx(fill, run)
	TweenService:Create(fill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = Vector3.new(0.14, diameter, diameter) }):Play()
	Debris:AddItem(ring, seconds + 0.1)
	Debris:AddItem(fill, seconds + 0.1)
end

-- Franja de aviso de la embestida, de `from` a `to`
local function telegraphStrip(from: Vector3, to: Vector3, width: number, color: Color3, seconds: number, run: number?)
	local a = Vector3.new(from.X, GROUND + 0.34 + StudFloor.raiseAt(from.X, from.Z), from.Z)
	local b = Vector3.new(to.X, a.Y, to.Z)
	local length = (b - a).Magnitude
	if length < 0.5 then
		return
	end
	local strip = PartFactory.part(nil :: any, "BossChargeWarning", {
		Size = Vector3.new(width, 0.12, length),
		CFrame = CFrame.lookAt((a + b) / 2, b),
		Color = color,
		Material = Enum.Material.Neon,
		Solid = false,
	})
	strip.Transparency = 0.5
	placeFx(strip, run)
	Debris:AddItem(strip, seconds + 0.1)
end

-- Ralentiza a un jugador un rato (deja su velocidad como estaba si nadie la ha cambiado)
local function slowPlayer(humanoid: Humanoid, factor: number, seconds: number)
	local before = humanoid.WalkSpeed
	local slowed = before * factor
	humanoid.WalkSpeed = slowed
	humanoid:SetAttribute("SlowedUntil", Workspace:GetServerTimeNow() + seconds)
	task.delay(seconds, function()
		if humanoid.Parent and math.abs(humanoid.WalkSpeed - slowed) < 0.01 then
			humanoid.WalkSpeed = before
		end
	end)
end

local function damageInRadius(enemy: Enemy, center: Vector3, radius: number, damage: number, onHit: ((Player, Humanoid) -> ())?)
	for _, player in Players:GetPlayers() do
		local root, humanoid = characterOf(player)
		if root and humanoid and sameWorld(enemy, player) and flat(root.Position - center) <= radius and math.abs(root.Position.Y - center.Y) < 12 then
			damagePlayer(enemy, player, humanoid, damage)
			if onHit then
				onHit(player, humanoid)
			end
		end
	end
end

-- Ocupado `seconds` (sin moverse ni elegir otro ataque) y después a descansar
local function busyThenRecover(enemy: Enemy, seconds: number)
	local brain = enemy.Brain :: Brain
	setBossState(enemy, "Busy")
	brain.Until = os.clock() + seconds
	enemy.Humanoid:MoveTo(enemy.Root.Position)
end

local function intervalOf(enemy: Enemy, settings): number
	if enemy.Enraged and enemy.Def.Enrage then
		return settings.Interval * enemy.Def.Enrage.SlamIntervalMultiplier
	end
	return settings.Interval
end

local function faceTowards(enemy: Enemy, point: Vector3): Vector3
	local origin = enemy.Root.Position
	local forward = Vector3.new(point.X - origin.X, 0, point.Z - origin.Z)
	forward = if forward.Magnitude > 0.05 then forward.Unit else Vector3.new(0, 0, -1)
	enemy.Root.CFrame = CFrame.lookAt(origin, origin + forward)
	return forward
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.TELEGRAPH_RED = TELEGRAPH_RED
	context.bossAcquire = bossAcquire
	context.bossCanTarget = bossCanTarget
	context.bossMoveTo = bossMoveTo
	context.busyThenRecover = busyThenRecover
	context.clampToTerritory = clampToTerritory
	context.damageInRadius = damageInRadius
	context.faceTowards = faceTowards
	context.intervalOf = intervalOf
	context.newBrain = newBrain
	context.resetBrain = resetBrain
	context.setBossState = setBossState
	context.slowPlayer = slowPlayer
	context.telegraphDisc = telegraphDisc
	context.telegraphStrip = telegraphStrip
end

function Part.link(context: any)
	GROUND = context.GROUND
end

return Part
