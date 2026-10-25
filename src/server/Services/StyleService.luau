-- Estilos de pelea (StyleConfig): elegir estilo, sus pasivas fuera del disparo y sus dos
-- habilidades. El disparo de cada estilo (alcance, ritmo, daño, crítico, robo de vida) lo
-- hace PetCombatService; aquí:
-- - StyleAction("Set", styleId): cambia el estilo (con una espera corta entre cambios), se
--   guarda en PetData.Style y se replica (atributo CombatStyle; la velocidad al caminar la
--   pone PlayerDataService con StyleLogic.walkSpeed).
-- - StyleAction("Ability", slot): usa la habilidad 1 (Z) o 2 (X) del estilo si está lista.
--   Todo lo decide el servidor:
--     Armas:  Ráfaga (PetCombatService.setBurst) y Granada (cae en tu objetivo y explota).
--     Puños:  Terremoto (daño alrededor, aturde y empuja) y Embestida (te lanzas hacia
--             delante, sin cruzar paredes ni puertas cerradas de la cueva, y golpeas a todos
--             los de la franja).
--     Magia:  Meteoros (caen uno tras otro alrededor del objetivo) y Nova de hielo (daña y
--             congela a los de alrededor).
--   El daño son múltiplos del DPS del estilo y pasa por EnemyService.damage (mismas
--   recompensas y muertes). La recarga es por estilo y habilidad (cambiar de estilo no la
--   reinicia) y se replica en StyleReadyAt (1) y StyleReadyAt2 (2).
-- - Daño que recibe el jugador según el estilo (Puños menos, Armas más): EnemyService.
-- - StyleEvent: efectos ya resueltos a quien la usa y a los cercanos; "Result" solo a él.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local StyleConfig = require(Shared.Config.StyleConfig)
local StyleLogic = require(Shared.StyleLogic)
local AbilityLogic = require(Shared.AbilityLogic)
local CaveLogic = require(Shared.CaveLogic)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local EnemyService = require(script.Parent.EnemyService)
local CombatService = require(script.Parent.CombatService)
local PetCombatService = require(script.Parent.PetCombatService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local BROADCAST_RANGE = 150
local DASH_STEP = 2 -- la embestida se comprueba cada tantos studs (suelo y puertas)
local DASH_WALL_GAP = 2.5 -- se para a esta distancia de una pared
local SLOT_ATTRIBUTES = { Constants.Attributes.StyleReadyAt, Constants.Attributes.StyleReadyAt2 }

local StyleService = {}

local eventRemote: RemoteEvent
local limiter = RateLimiter.new(0.15, 3, 8)
local lastSwitch: { [Player]: number } = {}
local readyAt: { [Player]: { [string]: number } } = {}
local generation: { [Player]: number } = {} -- cambia al salir o morir: anula meteoros y granadas pendientes

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root
	end
	return nil
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function broadcast(owner: Player, origin: Vector3, event: { [string]: any })
	event.Owner = owner
	for _, player in Players:GetPlayers() do
		local root = if player == owner then nil else rootOf(player)
		if player == owner or (root and (root.Position - origin).Magnitude <= BROADCAST_RANGE) then
			eventRemote:FireClient(player, event)
		end
	end
end

local function result(player: Player, data: { [string]: any })
	data.Kind = "Result"
	data.Owner = player
	eventRemote:FireClient(player, data)
end

local function styleOf(player: Player): (string?, any)
	local profile = PlayerDataService.get(player)
	if not profile then
		return nil, nil
	end
	return StyleLogic.sanitize(profile.PetData.Style), profile
end

-- DPS del estilo (con el arma, la cadencia, mascotas y bonificaciones)
local function styleDps(profile, style: string): number
	local stats = PlayerDataService.combatStats(profile)
	return StyleLogic.dps(stats.Dps, style)
end

-- Daño a un enemigo con la habilidad (cuenta como golpe del jugador para su objetivo)
local function hit(player: Player, enemy: any, damage: number, hits: { any }): boolean
	local dealt, killed = EnemyService.damage(enemy, player, damage)
	if dealt > 0 then
		table.insert(hits, { Position = enemy.Root.Position, Damage = dealt, Killed = killed, Kind = enemy.Kind })
		if not killed then
			CombatService.reportHit(player, enemy)
		end
	end
	return killed
end

local function readyKey(style: string, slot: number): string
	return style .. ":" .. slot
end

-- Habilidades ----------------------------------------------------------------------------

-- Armas 1: Ráfaga
local function burst(player: Player, ability: any, root: BasePart): boolean
	PetCombatService.setBurst(player, os.clock() + ability.Duration)
	player:SetAttribute(Constants.Attributes.StyleBurstUntil, serverNow() + ability.Duration)
	broadcast(player, root.Position, { Kind = "Burst", Duration = ability.Duration })
	return true
end

-- Armas 2: Granada (vuela hasta tu objetivo y explota al llegar)
local function grenade(player: Player, ability: any, root: BasePart, profile, style: string): boolean
	local target = EnemyService.findInRadius(root.Position, ability.Range, 1, player)[1]
	if not target then
		return false
	end
	local landing = target.Root.Position
	local damage = StyleLogic.abilityDamage(style, styleDps(profile, style), 2)
	local token = generation[player] or 0
	broadcast(player, root.Position, {
		Kind = "Grenade",
		From = root.Position + Vector3.new(0, 1.5, 0),
		To = landing,
		Delay = ability.Delay,
		Radius = ability.Radius,
	})
	task.delay(ability.Delay, function()
		if not player.Parent or (generation[player] or 0) ~= token then
			return
		end
		local hits = {}
		for _, enemy in EnemyService.findInRadius(landing, ability.Radius, ability.MaxTargets, player) do
			if EnemyService.canInteract(player, enemy) then
				local killed = hit(player, enemy, damage, hits)
				if not killed and EnemyService.isAlive(enemy) then
					EnemyService.knockback(enemy, landing, ability.Knockback)
				end
			end
		end
		broadcast(player, landing, { Kind = "GrenadeHit", Position = landing, Radius = ability.Radius, Hits = hits })
	end)
	return true
end

-- Puños 1: Terremoto
local function quake(player: Player, ability: any, root: BasePart, profile, style: string): boolean
	local damage = StyleLogic.abilityDamage(style, styleDps(profile, style), 1)
	local hits = {}
	for _, enemy in EnemyService.findInRadius(root.Position, ability.Radius, ability.MaxTargets, player) do
		if EnemyService.canInteract(player, enemy) then
			local killed = hit(player, enemy, damage, hits)
			if not killed and EnemyService.isAlive(enemy) then
				local seconds = AbilityLogic.control("Stun", ability.Stun, nil, enemy.Kind == "Boss")
				EnemyService.applyControl(enemy, "Stun", seconds)
				EnemyService.knockback(enemy, root.Position, ability.Knockback)
			end
		end
	end
	broadcast(player, root.Position, { Kind = "Quake", Position = root.Position, Radius = ability.Radius, Hits = hits })
	return true
end

-- Hasta dónde llega la embestida desde `origin` hacia `direction`: sin atravesar paredes, sin
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

-- Puños 2: Embestida
local function dash(player: Player, ability: any, root: BasePart, profile, style: string): boolean
	local character = player.Character :: Model
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	-- Hacia donde te mueves (o hacia donde miras si estás quieto)
	local move = humanoid.MoveDirection
	local look = root.CFrame.LookVector
	local direction = if move.Magnitude > 0.1 then Vector3.new(move.X, 0, move.Z) else Vector3.new(look.X, 0, look.Z)
	direction = if direction.Magnitude > 0.05 then direction.Unit else Vector3.new(0, 0, -1)
	local origin = root.Position
	local reach = dashReach(player, origin, direction, ability.Distance)
	local finish = origin + direction * reach
	local damage = StyleLogic.abilityDamage(style, styleDps(profile, style), 2)
	local hits = {}
	local middle = (origin + finish) / 2
	local candidates = EnemyService.findInRadius(middle, reach / 2 + ability.Width, ability.MaxTargets * 2, player)
	for _, enemy in candidates do
		if #hits >= ability.MaxTargets then
			break
		end
		local p = enemy.Root.Position
		if EnemyService.canInteract(player, enemy) and StyleLogic.inStrip(origin.X, origin.Z, finish.X, finish.Z, ability.Width / 2, p.X, p.Z, enemy.Radius) then
			local killed = hit(player, enemy, damage, hits)
			if not killed and EnemyService.isAlive(enemy) then
				local seconds = AbilityLogic.control("Stun", ability.Stun, nil, enemy.Kind == "Boss")
				EnemyService.applyControl(enemy, "Stun", seconds)
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
	broadcast(player, origin, { Kind = "Dash", From = origin, To = finish, Hits = hits })
	return true
end

-- Magia 1: Meteoros
local function meteors(player: Player, ability: any, root: BasePart, profile, style: string): boolean
	local target = EnemyService.findInRadius(root.Position, ability.Range, 1, player)[1]
	if not target then
		return false -- sin nadie a tiro no se gasta
	end
	local center = target.Root.Position
	local points = {}
	for _, offset in StyleLogic.meteorOffsets(ability.Count, ability.Spread) do
		table.insert(points, center + Vector3.new(offset.X, 0, offset.Y))
	end
	local damage = StyleLogic.abilityDamage(style, styleDps(profile, style), 1)
	local token = generation[player] or 0
	broadcast(player, root.Position, {
		Kind = "Meteor",
		Points = points,
		Delay = ability.Delay,
		Interval = ability.Interval,
		Radius = ability.Radius,
		StartAt = serverNow(),
	})
	for index, point in points do
		task.delay(ability.Delay + (index - 1) * ability.Interval, function()
			if not player.Parent or (generation[player] or 0) ~= token then
				return
			end
			local hits = {}
			for _, enemy in EnemyService.findInRadius(point, ability.Radius, ability.MaxTargets, player) do
				if EnemyService.canInteract(player, enemy) then
					hit(player, enemy, damage, hits)
				end
			end
			broadcast(player, point, { Kind = "MeteorHit", Position = point, Radius = ability.Radius, Hits = hits })
		end)
	end
	return true
end

-- Magia 2: Nova de hielo (daña y congela alrededor)
local function nova(player: Player, ability: any, root: BasePart, profile, style: string): boolean
	local damage = StyleLogic.abilityDamage(style, styleDps(profile, style), 2)
	local hits, frozen = {}, {}
	for _, enemy in EnemyService.findInRadius(root.Position, ability.Radius, ability.MaxTargets, player) do
		if EnemyService.canInteract(player, enemy) then
			local killed = hit(player, enemy, damage, hits)
			if not killed and EnemyService.isAlive(enemy) then
				local seconds = AbilityLogic.control("Stun", ability.Freeze, nil, enemy.Kind == "Boss")
				if EnemyService.applyControl(enemy, "Stun", seconds) then
					table.insert(frozen, { Model = enemy.Model, Seconds = seconds })
				end
			end
		end
	end
	broadcast(player, root.Position, { Kind = "Nova", Position = root.Position, Radius = ability.Radius, Hits = hits, Frozen = frozen })
	return true
end

local HANDLERS = {
	Weapons = { burst, grenade },
	Fists = { quake, dash },
	Magic = { meteors, nova },
}

local function useAbility(player: Player, slot: number)
	local style, profile = styleOf(player)
	local root = rootOf(player)
	if not (style and profile and root) then
		return
	end
	local ability = StyleLogic.ability(style, slot)
	local handler = HANDLERS[style] and HANDLERS[style][slot]
	if not (ability and handler) then
		return
	end
	local now = os.clock()
	local own = readyAt[player] or {}
	readyAt[player] = own
	local key = readyKey(style, slot)
	if (own[key] or 0) > now then
		result(player, { Success = false, Code = "NotReady", Style = style, Slot = slot, ReadyAt = serverNow() + (own[key] - now) })
		return
	end
	if not handler(player, ability, root, profile, style) then
		result(player, { Success = false, Code = "NoTarget", Style = style, Slot = slot })
		return
	end
	own[key] = now + ability.Cooldown
	local ready = serverNow() + ability.Cooldown
	player:SetAttribute(SLOT_ATTRIBUTES[slot], ready)
	result(player, { Success = true, Code = "Success", Style = style, Slot = slot, ReadyAt = ready })
end

-- Recargas de las dos habilidades del estilo `style` en los atributos del jugador.
local function publishCooldowns(player: Player, style: string)
	local own = readyAt[player]
	local now = os.clock()
	for slot, attribute in SLOT_ATTRIBUTES do
		local at = own and own[readyKey(style, slot)]
		player:SetAttribute(attribute, serverNow() + (if at then math.max(0, at - now) else 0))
	end
end

local function setStyle(player: Player, styleId: any)
	local profile = PlayerDataService.get(player)
	if not (profile and type(styleId) == "string" and StyleLogic.definition(styleId)) then
		return
	end
	local now = os.clock()
	if profile.PetData.Style == styleId then
		return
	end
	if not StyleLogic.canSwitch(lastSwitch[player], now) then
		result(player, { Success = false, Code = "TooFast", Style = profile.PetData.Style })
		return
	end
	lastSwitch[player] = now
	profile.PetData.Style = styleId
	PlayerDataService.markDirty(player)
	PlayerDataService.replicate(player) -- también la velocidad al caminar del estilo
	publishCooldowns(player, styleId)
	result(player, { Success = true, Code = "Success", Action = "Set", Style = styleId })
end

function StyleService.start()
	eventRemote = RemoteService.get(Constants.Remotes.StyleEvent)

	RemoteService.get(Constants.Remotes.StyleAction).OnServerEvent:Connect(function(player: Player, action: any, value: any)
		if type(action) ~= "string" or limiter:check(player) ~= "ok" then
			return
		end
		if action == "Set" then
			setStyle(player, value)
		elseif action == "Ability" then
			useAbility(player, if value == 2 then 2 else 1)
		end
	end)

	-- Daño que recibe el jugador según su estilo (Puños menos, Armas más)
	EnemyService.setIncomingDamageModifier(function(player: Player, amount: number): number
		local style = styleOf(player)
		return if style then StyleLogic.damageTaken(style, amount) else amount
	end)

	local function watch(player: Player)
		player.CharacterRemoving:Connect(function()
			generation[player] = (generation[player] or 0) + 1
			PetCombatService.setBurst(player, 0)
			player:SetAttribute(Constants.Attributes.StyleBurstUntil, nil)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSwitch[player] = nil
		readyAt[player] = nil
		generation[player] = nil
		limiter:remove(player)
	end)
end

-- Para pruebas y otros servicios: el default por si un perfil no tiene estilo.
StyleService.DefaultStyle = StyleConfig.Default

return StyleService
