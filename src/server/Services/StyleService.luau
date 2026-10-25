-- Estilos de pelea (StyleConfig): elegir estilo, sus pasivas fuera del disparo y su
-- habilidad. El disparo de cada estilo (alcance, ritmo, daño, crítico, robo de vida) lo
-- hace PetCombatService; aquí:
-- - StyleAction("Set", styleId): cambia el estilo (con una espera corta entre cambios), se
--   guarda en PetData.Style y se replica (atributo CombatStyle).
-- - StyleAction("Ability"): usa la habilidad del estilo si está lista. Todo lo decide el
--   servidor: Ráfaga (PetCombatService.setBurst), Terremoto (daño en área, aturde y empuja)
--   o Meteoros (caen uno tras otro alrededor del objetivo). El daño son múltiplos del DPS
--   del estilo y pasa por EnemyService.damage (mismas recompensas y muertes). La recarga es
--   por estilo (cambiar de estilo no la reinicia) y se replica en StyleReadyAt.
-- - Piel dura (Puños): reduce el daño que recibe el jugador (EnemyService).
-- - StyleEvent: efectos ya resueltos a quien la usa y a los cercanos; "Result" solo a él.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local StyleConfig = require(Shared.Config.StyleConfig)
local StyleLogic = require(Shared.StyleLogic)
local AbilityLogic = require(Shared.AbilityLogic)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local EnemyService = require(script.Parent.EnemyService)
local CombatService = require(script.Parent.CombatService)
local PetCombatService = require(script.Parent.PetCombatService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local BROADCAST_RANGE = 150

local StyleService = {}

local eventRemote: RemoteEvent
local limiter = RateLimiter.new(0.15, 3, 8)
local lastSwitch: { [Player]: number } = {}
local readyAt: { [Player]: { [string]: number } } = {}
local generation: { [Player]: number } = {} -- cambia al salir o morir: anula meteoros pendientes

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

-- Habilidades ----------------------------------------------------------------------------

local function burst(player: Player, ability: any, root: BasePart): boolean
	PetCombatService.setBurst(player, os.clock() + ability.Duration)
	player:SetAttribute(Constants.Attributes.StyleBurstUntil, serverNow() + ability.Duration)
	broadcast(player, root.Position, { Kind = "Burst", Duration = ability.Duration })
	return true
end

local function quake(player: Player, ability: any, root: BasePart, profile, style: string): boolean
	local damage = StyleLogic.abilityDamage(style, styleDps(profile, style))
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
	local damage = StyleLogic.abilityDamage(style, styleDps(profile, style))
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

local function useAbility(player: Player)
	local style, profile = styleOf(player)
	local root = rootOf(player)
	if not (style and profile and root) then
		return
	end
	local def = StyleLogic.definition(style)
	local ability = def and def.Ability
	if not ability then
		return
	end
	local now = os.clock()
	local own = readyAt[player] or {}
	readyAt[player] = own
	if (own[style] or 0) > now then
		result(player, { Success = false, Code = "NotReady", Style = style, ReadyAt = serverNow() + (own[style] - now) })
		return
	end
	local used
	if style == "Weapons" then
		used = burst(player, ability, root)
	elseif style == "Fists" then
		used = quake(player, ability, root, profile, style)
	else
		used = meteors(player, ability, root, profile, style)
	end
	if not used then
		result(player, { Success = false, Code = "NoTarget", Style = style })
		return
	end
	own[style] = now + ability.Cooldown
	local ready = serverNow() + ability.Cooldown
	player:SetAttribute(Constants.Attributes.StyleReadyAt, ready)
	result(player, { Success = true, Code = "Success", Style = style, ReadyAt = ready })
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
	PlayerDataService.replicate(player)
	-- La recarga de la habilidad del estilo nuevo (si la usó hace poco)
	local own = readyAt[player]
	local left = if own and own[styleId] then math.max(0, own[styleId] - now) else 0
	player:SetAttribute(Constants.Attributes.StyleReadyAt, serverNow() + left)
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
			useAbility(player)
		end
	end)

	-- Piel dura (Puños): menos daño de los enemigos
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
