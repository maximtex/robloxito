-- StyleService · Abilities: las habilidades de cada estilo (tabla HANDLERS: se registran todas juntas al cargar).
-- Parte de StyleService (ver StyleService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local StyleLogic = require(Shared.StyleLogic)
local SkillLogic = require(Shared.SkillLogic)
local AbilityLogic = require(Shared.AbilityLogic)
local EnemyService = require(script.Parent.Parent.EnemyService)
local PetCombatService = require(script.Parent.Parent.PetCombatService)
local Types = require(script.Parent.Types)
type Cast = Types.Cast

local ctx: any -- tabla de estado compartida (la crea StyleService/init.luau)
local Api = {} -- funciones públicas de esta parte (init.luau las copia a StyleService)
local CHAIN_AIM: any
local buffUntil: any
local generation: any
local rageTaken: any
local rageUntil: any

-- Funciones de las otras partes
local function aimedDirection(...) return ctx.aimedDirection(...) end
local function aimedPoint(...) return ctx.aimedPoint(...) end
local function announceCombo(...) return ctx.announceCombo(...) end
local function broadcast(...) return ctx.broadcast(...) end
local function dashReach(...) return ctx.dashReach(...) end
local function fx(...) return ctx.fx(...) end
local function hit(...) return ctx.hit(...) end
local function moveDirection(...) return ctx.moveDirection(...) end
local function nearestTarget(...) return ctx.nearestTarget(...) end
local function pull(...) return ctx.pull(...) end
local function rootOf(...) return ctx.rootOf(...) end
local function serverNow(...) return ctx.serverNow(...) end
local function stun(...) return ctx.stun(...) end
local function targetsAround(...) return ctx.targetsAround(...) end

-- Habilidades ----------------------------------------------------------------------------
-- Cada una: (cast, ability, root, level) -> true si se ha usado (false: sin objetivo).

local HANDLERS = {}

-- Armas: Ráfaga
function HANDLERS.Burst(cast: Cast, ability: any, root: BasePart, level: number): boolean
	local player = cast.Player
	local duration = SkillLogic.duration(ability, level)
	PetCombatService.setBurst(player, os.clock() + duration, ability.CooldownScale)
	buffUntil[player] = os.clock() + duration
	player:SetAttribute(Constants.Attributes.StyleBurstUntil, serverNow() + duration)
	broadcast(player, root.Position, fx(cast, { Kind = "Burst", Duration = duration }))
	return true
end

-- Armas: Granada (vuela hasta donde apuntas y explota al llegar). Count (Bombardeo): la
-- primera donde apuntas y las demás en corro alrededor, una detrás de otra. Sin punto
-- (clientes antiguos), a los enemigos más cercanos.
function HANDLERS.Grenade(cast: Cast, ability: any, root: BasePart): boolean
	local player = cast.Player
	local count = math.max(1, math.floor(ability.Count or 1))
	local landings = {}
	local aimed = aimedPoint(cast, root, ability.Range)
	if aimed then
		table.insert(landings, aimed)
		local ring = ability.Radius * 1.2
		for index = 2, count do
			local angle = (index - 2) / math.max(1, count - 1) * math.pi * 2
			table.insert(landings, aimed + Vector3.new(math.cos(angle) * ring, 0, math.sin(angle) * ring))
		end
	else
		for _, target in targetsAround(player, root.Position, ability.Range, count) do
			table.insert(landings, target.Root.Position)
		end
	end
	if #landings == 0 then
		return false
	end
	local token = generation[player] or 0
	for index, landing in landings do
		local delay = ability.Delay + (index - 1) * 0.1
		broadcast(player, root.Position, fx(cast, {
			Kind = "Grenade",
			From = root.Position + Vector3.new(0, 1.5, 0),
			To = landing,
			Delay = delay,
			Radius = ability.Radius,
		}))
		task.delay(delay, function()
			if not player.Parent or (generation[player] or 0) ~= token then
				return
			end
			local hits = {}
			for _, enemy in targetsAround(player, landing, ability.Radius, ability.MaxTargets) do
				local killed = hit(cast, enemy, hits)
				if not killed and EnemyService.isAlive(enemy) then
					EnemyService.knockback(enemy, landing, ability.Knockback)
				end
			end
			broadcast(player, landing, fx(cast, { Kind = "GrenadeHit", Position = landing, Radius = ability.Radius, Hits = hits }))
			announceCombo(cast)
		end)
	end
	return true
end

-- Armas: Rayo perforante (franja recta hacia donde apuntas; sin punto, hacia el más cercano)
function HANDLERS.Pierce(cast: Cast, ability: any, root: BasePart): boolean
	local player = cast.Player
	local origin = root.Position
	local aim = aimedDirection(cast, root)
	if not aim then
		local target = nearestTarget(player, origin, ability.Length)
		if not target then
			return false
		end
		local toward = target.Root.Position - origin
		local flat = Vector3.new(toward.X, 0, toward.Z)
		aim = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)
	end
	assert(aim, "dirección del rayo")
	-- Beams (Rayo triple): varios rayos en abanico, Spread grados entre uno y otro; cada
	-- enemigo recibe como mucho un rayo
	local beams = math.max(1, math.floor(ability.Beams or 1))
	local struck = {}
	for beam = 1, beams do
		local angle = math.rad((beam - (beams + 1) / 2) * (ability.Spread or 0))
		local direction = (CFrame.Angles(0, angle, 0) * aim).Unit
		local finish = origin + direction * ability.Length
		local hits = {}
		local middle = (origin + finish) / 2
		for _, enemy in targetsAround(player, middle, ability.Length / 2 + ability.Width, ability.MaxTargets * 2) do
			if #hits >= ability.MaxTargets then
				break
			end
			local p = enemy.Root.Position
			if not struck[enemy] and StyleLogic.inStrip(origin.X, origin.Z, finish.X, finish.Z, ability.Width / 2, p.X, p.Z, enemy.Radius) then
				struck[enemy] = true
				hit(cast, enemy, hits)
			end
		end
		broadcast(player, origin, fx(cast, { Kind = ability.Visual or "Pierce", From = origin + Vector3.new(0, 1.2, 0), To = finish + Vector3.new(0, 1.2, 0), Width = ability.Width, Hits = hits }))
	end
	announceCombo(cast)
	return true
end

-- Armas: Torreta (dispara sola al más cercano mientras dura)
function HANDLERS.Turret(cast: Cast, ability: any, root: BasePart, level: number): boolean
	local player = cast.Player
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local base = root.Position + (if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)) * 3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model }
	local floor = Workspace:Raycast(base + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), params)
	local spot = if floor then floor.Position else base - Vector3.new(0, 2.5, 0)
	local duration = SkillLogic.duration(ability, level)
	local token = generation[player] or 0
	local gun = spot + Vector3.new(0, 2.6, 0)
	broadcast(player, spot, fx(cast, { Kind = "Turret", Position = spot, Duration = duration }))
	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			task.wait(ability.Interval)
			elapsed += ability.Interval
			if not player.Parent or (generation[player] or 0) ~= token then
				break
			end
			local target = nearestTarget(player, gun, ability.Range)
			if target then
				local hits = {}
				hit(cast, target, hits)
				broadcast(player, gun, fx(cast, { Kind = "TurretShot", From = gun, To = target.Root.Position, Hits = hits }))
				announceCombo(cast)
			end
		end
		broadcast(player, spot, fx(cast, { Kind = "TurretEnd", Position = spot }))
	end)
	return true
end

-- Puños: Terremoto. Waves (Terremoto titán): varios golpes seguidos donde lo usaste, cada uno
-- un 35 % más grande.
local function quakeWave(cast: Cast, ability: any, center: Vector3, radius: number)
	local hits = {}
	for _, enemy in targetsAround(cast.Player, center, radius, ability.MaxTargets) do
		local killed = hit(cast, enemy, hits)
		if not killed and EnemyService.isAlive(enemy) then
			stun(enemy, ability.Stun)
			EnemyService.knockback(enemy, center, ability.Knockback)
		end
	end
	broadcast(cast.Player, center, fx(cast, { Kind = "Quake", Position = center, Radius = radius, Hits = hits }))
	announceCombo(cast)
end

function HANDLERS.Quake(cast: Cast, ability: any, root: BasePart): boolean
	local player = cast.Player
	local center = root.Position
	quakeWave(cast, ability, center, ability.Radius)
	local waves = math.max(1, math.floor(ability.Waves or 1))
	if waves > 1 then
		local token = generation[player] or 0
		task.spawn(function()
			local radius = ability.Radius
			for _ = 2, waves do
				task.wait(ability.WaveInterval or 0.35)
				if not player.Parent or (generation[player] or 0) ~= token then
					return
				end
				radius *= 1.35
				quakeWave(cast, ability, center, radius)
			end
		end)
	end
	return true
end

-- Puños: Embestida
function HANDLERS.Dash(cast: Cast, ability: any, root: BasePart): boolean
	local player = cast.Player
	local character = player.Character :: Model
	local direction = moveDirection(player, root)
	local origin = root.Position
	local reach = dashReach(player, origin, direction, ability.Distance)
	local finish = origin + direction * reach
	local hits = {}
	local middle = (origin + finish) / 2
	for _, enemy in targetsAround(player, middle, reach / 2 + ability.Width, ability.MaxTargets * 2) do
		if #hits >= ability.MaxTargets then
			break
		end
		local p = enemy.Root.Position
		if StyleLogic.inStrip(origin.X, origin.Z, finish.X, finish.Z, ability.Width / 2, p.X, p.Z, enemy.Radius) then
			local killed = hit(cast, enemy, hits)
			if not killed and EnemyService.isAlive(enemy) then
				stun(enemy, ability.Stun)
				-- Se apartan a los lados de tu camino
				local along = math.clamp((p - origin):Dot(direction), 0, reach)
				EnemyService.knockback(enemy, origin + direction * along, ability.Knockback)
			end
		end
	end
	if reach > 0 then
		character:PivotTo(CFrame.lookAt(finish, finish + direction))
		root.AssemblyLinearVelocity = Vector3.zero
	end
	broadcast(player, origin, fx(cast, { Kind = "Dash", From = origin, To = finish, Hits = hits }))
	-- EndRadius (Cometa): al llegar, explota alrededor (EndRatio × DPS)
	if ability.EndRadius then
		local blast = {}
		local scale = (ability.EndRatio or ability.DamageRatio) / math.max(0.01, ability.DamageRatio)
		for _, enemy in targetsAround(player, finish, ability.EndRadius, ability.MaxTargets) do
			local killed = hit(cast, enemy, blast, scale)
			if not killed and EnemyService.isAlive(enemy) then
				EnemyService.knockback(enemy, finish, ability.Knockback)
			end
		end
		broadcast(player, finish, fx(cast, { Kind = "Quake", Position = finish, Radius = ability.EndRadius, Hits = blast }))
	end
	announceCombo(cast)
	return true
end

-- Guerrero: Salto aplastante (saltas hacia donde apuntas y caes con un golpe en área). El
-- cliente del jugador hace el salto (StyleController); al caer, si no llegó, se le pone allí.
function HANDLERS.Leap(cast: Cast, ability: any, root: BasePart): boolean
	local player = cast.Player
	local origin = root.Position
	local direction = aimedDirection(cast, root) or moveDirection(player, root)
	local wanted = ability.Distance
	if cast.Aim then
		local flat = Vector3.new(cast.Aim.X - origin.X, 0, cast.Aim.Z - origin.Z)
		wanted = math.clamp(flat.Magnitude, 4, ability.Distance)
	end
	local reach = dashReach(player, origin, direction, wanted)
	local landing = origin + direction * reach
	local delay = ability.Delay or 0.55
	local token = generation[player] or 0
	broadcast(player, origin, fx(cast, { Kind = "Leap", From = origin, To = landing, Delay = delay, Radius = ability.Radius }))
	task.delay(delay, function()
		if not player.Parent or (generation[player] or 0) ~= token then
			return
		end
		local here = rootOf(player)
		if not here then
			return
		end
		if (here.Position - landing).Magnitude > 8 then
			(player.Character :: Model):PivotTo(CFrame.lookAt(landing, landing + direction))
		end
		local hits = {}
		for _, enemy in targetsAround(player, landing, ability.Radius, ability.MaxTargets) do
			local killed = hit(cast, enemy, hits)
			if not killed and EnemyService.isAlive(enemy) then
				stun(enemy, ability.Stun)
				EnemyService.knockback(enemy, landing, ability.Knockback)
			end
		end
		broadcast(player, landing, fx(cast, { Kind = "Quake", Position = landing, Radius = ability.Radius, Hits = hits }))
		announceCombo(cast)
	end)
	return true
end

-- Puños: Furia (pegas más rápido y recibes la mitad de daño)
function HANDLERS.Rage(cast: Cast, ability: any, root: BasePart, level: number): boolean
	local player = cast.Player
	local duration = SkillLogic.duration(ability, level)
	local untilClock = os.clock() + duration
	PetCombatService.setBurst(player, untilClock, ability.CooldownScale, ability.DamageBoost)
	buffUntil[player] = untilClock
	rageUntil[player] = untilClock
	rageTaken[player] = ability.DamageTaken or 0.5
	player:SetAttribute(Constants.Attributes.StyleRageUntil, serverNow() + duration)
	broadcast(player, root.Position, fx(cast, { Kind = "Rage", Duration = duration }))
	return true
end

-- Puños: Torbellino (varios golpes alrededor que atraen hacia ti)
function HANDLERS.Whirlwind(cast: Cast, ability: any, root: BasePart): boolean
	local player = cast.Player
	local token = generation[player] or 0
	broadcast(player, root.Position, fx(cast, { Kind = "Whirl", Radius = ability.Radius, Pulses = ability.Pulses, Interval = ability.Interval }))
	task.spawn(function()
		for pulse = 1, ability.Pulses do
			if pulse > 1 then
				task.wait(ability.Interval)
			end
			local here = rootOf(player)
			if not here or (generation[player] or 0) ~= token then
				return
			end
			local hits = {}
			for _, enemy in targetsAround(player, here.Position, ability.Radius, ability.MaxTargets) do
				local killed = hit(cast, enemy, hits)
				if not killed and EnemyService.isAlive(enemy) and pulse < ability.Pulses then
					pull(enemy, here.Position, ability.Pull)
				end
			end
			broadcast(player, here.Position, fx(cast, { Kind = "WhirlHit", Position = here.Position, Radius = ability.Radius, Hits = hits }))
			announceCombo(cast)
		end
	end)
	return true
end

-- Magia: Meteoros (caen donde apuntas; sin punto, sobre el más cercano)
function HANDLERS.Meteors(cast: Cast, ability: any, root: BasePart): boolean
	local player = cast.Player
	local center = aimedPoint(cast, root, ability.Range)
	if not center then
		local target = nearestTarget(player, root.Position, ability.Range)
		if not target then
			return false -- sin nadie a tiro no se gasta
		end
		center = target.Root.Position
	end
	assert(center, "centro de los meteoros")
	local points = {}
	for _, offset in StyleLogic.meteorOffsets(ability.Count, ability.Spread) do
		table.insert(points, center + Vector3.new(offset.X, 0, offset.Y))
	end
	local token = generation[player] or 0
	broadcast(player, root.Position, fx(cast, {
		Kind = "Meteor",
		Points = points,
		Delay = ability.Delay,
		Interval = ability.Interval,
		Radius = ability.Radius,
		StartAt = serverNow(),
	}))
	for index, point in points do
		task.delay(ability.Delay + (index - 1) * ability.Interval, function()
			if not player.Parent or (generation[player] or 0) ~= token then
				return
			end
			local hits = {}
			for _, enemy in targetsAround(player, point, ability.Radius, ability.MaxTargets) do
				hit(cast, enemy, hits)
			end
			broadcast(player, point, fx(cast, { Kind = "MeteorHit", Position = point, Radius = ability.Radius, Hits = hits }))
			announceCombo(cast)
		end)
	end
	return true
end

-- Magia: Nova de hielo (daña y congela alrededor)
function HANDLERS.Nova(cast: Cast, ability: any, root: BasePart): boolean
	local player = cast.Player
	local hits, frozen = {}, {}
	for _, enemy in targetsAround(player, root.Position, ability.Radius, ability.MaxTargets) do
		local killed = hit(cast, enemy, hits)
		if not killed and EnemyService.isAlive(enemy) then
			local seconds = AbilityLogic.control("Stun", ability.Freeze, nil, enemy.Kind == "Boss")
			if EnemyService.applyControl(enemy, "Stun", seconds) then
				table.insert(frozen, { Model = enemy.Model, Seconds = seconds })
			end
		end
	end
	broadcast(player, root.Position, fx(cast, { Kind = "Nova", Position = root.Position, Radius = ability.Radius, Hits = hits, Frozen = frozen }))
	announceCombo(cast)
	return true
end

-- Magia: Cadena de rayos: empieza en el enemigo más cercano a donde apuntas (a CHAIN_AIM
-- studs o menos de ese punto, y a tu alcance) y salta al siguiente más cercano que aún no ha
-- tocado. Sin punto, empieza en el más cercano a ti.
function HANDLERS.ChainLightning(cast: Cast, ability: any, root: BasePart): boolean
	local player = cast.Player
	local current = nil
	local aimed = aimedPoint(cast, root, ability.Range)
	if aimed then
		for _, candidate in targetsAround(player, aimed, CHAIN_AIM, 6) do
			if (candidate.Root.Position - root.Position).Magnitude - (candidate.Radius or 0) <= ability.Range then
				current = candidate
				break
			end
		end
	else
		current = nearestTarget(player, root.Position, ability.Range)
	end
	if not current then
		return false
	end
	local points = { root.Position + Vector3.new(0, 1.5, 0) }
	local touched = {}
	local hits = {}
	for _ = 1, ability.Jumps do
		touched[current] = true
		table.insert(points, current.Root.Position)
		-- Primero el daño (el combo mira si ya estaba aturdido) y luego aturde
		local killed = hit(cast, current, hits)
		if not killed then
			stun(current, ability.Stun)
		end
		local nextEnemy = nil
		local best = math.huge
		for _, candidate in targetsAround(player, current.Root.Position, ability.JumpRange, 12) do
			if not touched[candidate] then
				local distance = (candidate.Root.Position - current.Root.Position).Magnitude
				if distance < best then
					best = distance
					nextEnemy = candidate
				end
			end
		end
		if not nextEnemy then
			break
		end
		current = nextEnemy
	end
	broadcast(player, root.Position, fx(cast, { Kind = "Lightning", Points = points, Hits = hits }))
	announceCombo(cast)
	return true
end

-- Magia: Agujero negro (atrae y daña un rato y luego explota)
function HANDLERS.BlackHole(cast: Cast, ability: any, root: BasePart, level: number): boolean
	local player = cast.Player
	local center = aimedPoint(cast, root, ability.Range)
	if not center then
		local target = nearestTarget(player, root.Position, ability.Range)
		if not target then
			return false
		end
		center = target.Root.Position
	end
	assert(center, "centro del agujero negro")
	local duration = SkillLogic.duration(ability, level)
	local token = generation[player] or 0
	local tickScale = (ability.TickRatio or 0.5) / math.max(0.01, ability.DamageRatio)
	broadcast(player, center, fx(cast, { Kind = "BlackHole", Position = center, Radius = ability.Radius, Duration = duration }))
	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			task.wait(ability.Interval)
			elapsed += ability.Interval
			if not player.Parent or (generation[player] or 0) ~= token then
				return
			end
			local hits = {}
			for _, enemy in targetsAround(player, center, ability.Radius, ability.MaxTargets) do
				local killed = hit(cast, enemy, hits, tickScale, true)
				if not killed and EnemyService.isAlive(enemy) then
					pull(enemy, center, ability.Pull)
				end
			end
			if #hits > 0 then
				broadcast(player, center, fx(cast, { Kind = "BlackHoleTick", Position = center, Hits = hits }))
			end
		end
		local hits = {}
		for _, enemy in targetsAround(player, center, ability.Radius, ability.MaxTargets) do
			hit(cast, enemy, hits)
		end
		broadcast(player, center, fx(cast, { Kind = "BlackHoleBlast", Position = center, Radius = ability.Radius, Hits = hits }))
		announceCombo(cast)
	end)
	return true
end

Api.Handlers = HANDLERS

local Part = { Api = Api }

function Part.install(context: any)
	ctx = context
	context.HANDLERS = HANDLERS
end

function Part.link(context: any)
	CHAIN_AIM = context.CHAIN_AIM
	buffUntil = context.buffUntil
	generation = context.generation
	rageTaken = context.rageTaken
	rageUntil = context.rageUntil
end

return Part
