-- Combate automático (el único camino de disparo del jugador) y golpes de sus mascotas:
-- - Cada jugador tiene un objetivo. Con el disparo automático encendido (por defecto; F o
--   el botón "Disparar" lo apagan), si no tiene uno, toma el enemigo vivo más cercano a
--   tiro de su arma (con comprobación de altura). Lo mantiene hasta que muere, se sale de
--   su alcance (con RANGE_SLACK de margen para no cambiar a cada paso) o el jugador elige
--   otro con un clic (CombatService); uno elegido con clic se persigue hasta
--   MAX_ENGAGE_RANGE y se dispara en cuanto entra en el alcance.
-- - Dispara con el arma equipada (PlayerDataService.combatStats: daño, cadencia y alcance)
--   y aplica su efecto (WeaponConfig): área alrededor del objetivo, salto a otros enemigos
--   o ralentizar. Todo se calcula aquí; el cliente solo dibuja (PetAbility "PlayerShot").
-- - Cada mascota equipada golpea al mismo objetivo cada PET_HIT_INTERVAL.
-- - La barra de vida del enemigo solo se muestra mientras alguien lo tiene de objetivo.
-- Un único bucle para todos los jugadores (STEP_SECONDS); varios disparos por paso si la
-- cadencia es más rápida que el bucle.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local PetConfig = require(Shared.Config.PetConfig)
local PetCombatConfig = require(Shared.Config.PetCombatConfig)
local WeaponLogic = require(Shared.WeaponLogic)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local EnemyService = require(script.Parent.EnemyService)
local CombatService = require(script.Parent.CombatService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local STEP_SECONDS = 0.1
local MAX_ENGAGE_RANGE = 75 -- un objetivo elegido con clic se deja más lejos que esto
local RANGE_SLACK = 4
local MAX_SHOTS_PER_STEP = 3
local MAX_EFFECT_TARGETS = 8
local PET_HIT_INTERVAL = 0.65

type State = {
	Target: any?,
	Manual: boolean, -- elegido con clic (o con una habilidad)
	AutoFire: boolean,
	LastHitAt: number,
	NextShotAt: number,
	PetNextHit: { [number]: number },
	Generation: number,
}

local PetCombatService = {}

local states: { [Player]: State } = {}
local abilityRemote: RemoteEvent
local abilityListeners: { (Player, string) -> () } = {}
local autoLimiter = RateLimiter.new(0.2, 2, 6)

function PetCombatService.onAbilityHit(listener: (Player, string) -> ())
	table.insert(abilityListeners, listener)
end

local function notifyAbility(player: Player, kind: string)
	for _, listener in abilityListeners do
		task.spawn(listener, player, kind)
	end
end

local function isTargetedByAnyone(enemy: any): boolean
	for _, state in states do
		if state.Target == enemy then
			return true
		end
	end
	return false
end

local function hideBarIfUntargeted(enemy: any)
	if enemy and enemy.Billboard and not isTargetedByAnyone(enemy) then
		enemy.Billboard.Enabled = false
	end
end

local function stateOf(player: Player): State
	local state = states[player]
	if not state then
		state = { Target = nil, Manual = false, AutoFire = true, LastHitAt = -math.huge, NextShotAt = 0, PetNextHit = {}, Generation = 0 }
		states[player] = state
		player:SetAttribute(Constants.Attributes.AutoFire, true)
	end
	return state
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root
	end
	return nil
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

-- ¿A tiro? Distancia al borde del enemigo y sin disparar a través de suelos
local function inReach(root: BasePart, enemy: any, range: number): boolean
	local position = enemy.Root.Position
	return flatDistance(root.Position, position) - enemy.Radius <= range and math.abs(position.Y - root.Position.Y) <= 10 + enemy.RootHeight
end

local function broadcast(owner: Player, origin: Vector3, event: { [string]: any })
	event.Owner = owner
	for _, player in Players:GetPlayers() do
		local root = if player == owner then nil else rootOf(player)
		if player == owner or (root and (root.Position - origin).Magnitude <= PetCombatConfig.BroadcastRange) then
			abilityRemote:FireClient(player, event)
		end
	end
end

local function hitInfo(enemy, dealt: number, killed: boolean)
	return { Position = enemy.Root.Position, Damage = dealt, Killed = killed, Kind = enemy.Kind, Model = enemy.Model }
end

local function singlePetDamage(player: Player, petId: string): number
	local profile = PlayerDataService.get(player)
	if not profile then
		return 5
	end
	local petDef = PetConfig.Pets[petId]
	local rarityDef = petDef and PetConfig.Rarities[petDef.Rarity]
	local mult = (petDef and petDef.Multiplier) or (rarityDef and rarityDef.Multiplier) or 1.1
	-- Base: el 60 % del poder del arma equipada (sin mascotas ni bonificaciones; con el láser
	-- inicial, 6 como antes) por su propio multiplicador y la mejora "Poder de Mascotas"
	local stats = PlayerDataService.combatStats(profile)
	local petPowerLevel = profile.UpgradeLevels.PetPower or 0
	local base = stats.RawPower * 0.6 * mult * (1 + petPowerLevel * 0.25)
	return math.max(1, math.floor(base * stats.Bonus))
end

local function clearTargetAttributes(player: Player)
	if player:GetAttribute("PetTargetPos") ~= nil then
		player:SetAttribute("PetTargetPos", nil)
		player:SetAttribute("PetTargetRadius", nil)
	end
end

local function clearTarget(player: Player, state: State)
	local old = state.Target
	state.Target = nil
	state.Manual = false
	clearTargetAttributes(player)
	if old then
		hideBarIfUntargeted(old)
	end
end

local function setTarget(state: State, enemy: any, manual: boolean)
	local old = state.Target
	state.Target = enemy
	state.Manual = manual
	state.LastHitAt = os.clock()
	if old and old ~= enemy then
		hideBarIfUntargeted(old)
	end
	if enemy.Billboard then
		enemy.Billboard.Enabled = true
	end
end

local function reset(player: Player)
	local state = states[player]
	if state then
		state.Generation += 1
		clearTarget(player, state)
	else
		clearTargetAttributes(player)
	end
end

-- Daña a `enemy` (con la ralentización del arma, si tiene) y apunta el golpe en `hits`
local function hitWith(player: Player, enemy: any, damage: number, slow, hits: { any }): boolean
	local dealt, killed = EnemyService.damage(enemy, player, damage)
	if dealt > 0 then
		table.insert(hits, hitInfo(enemy, dealt, killed))
	end
	if slow and dealt > 0 and not killed then
		EnemyService.applyControl(enemy, "Slow", slow.Seconds, slow.Factor)
	end
	return killed
end

-- Un disparo del arma equipada a `target`, con su efecto. true si el objetivo ha muerto.
local function fire(player: Player, root: BasePart, target: any, stats): boolean
	local def = WeaponLogic.definition(stats.WeaponId)
	local effect = def and def.Effect or {}
	local targetPosition = target.Root.Position
	local hits = {}
	local killed = hitWith(player, target, stats.Shot, effect.Slow, hits)

	local splashRadius = nil
	if effect.Splash then
		splashRadius = effect.Splash.Radius
		for _, other in EnemyService.findInRadius(targetPosition, effect.Splash.Radius, MAX_EFFECT_TARGETS) do
			if other ~= target then
				hitWith(player, other, stats.Shot * effect.Splash.Fraction, effect.Slow, hits)
			end
		end
	end
	local chain = nil
	if effect.Chain then
		chain = {}
		local visited = { [target] = true }
		local from = targetPosition
		for _ = 1, effect.Chain.Count do
			local nextEnemy = nil
			for _, candidate in EnemyService.findInRadius(from, effect.Chain.Range, MAX_EFFECT_TARGETS) do
				if not visited[candidate] then
					nextEnemy = candidate
					break
				end
			end
			if not nextEnemy then
				break
			end
			visited[nextEnemy] = true
			from = nextEnemy.Root.Position
			table.insert(chain, from)
			hitWith(player, nextEnemy, stats.Shot * effect.Chain.Fraction, effect.Slow, hits)
		end
	end

	broadcast(player, root.Position, {
		Kind = "PlayerShot",
		WeaponId = stats.WeaponId,
		Target = targetPosition,
		Hits = hits,
		Chain = chain,
		Splash = splashRadius,
	})
	return killed
end

function PetCombatService.step(now: number)
	for player, state in states do
		local root = rootOf(player)
		local profile = PlayerDataService.get(player)
		if not (root and profile) then
			clearTarget(player, state)
			continue
		end
		local stats = PlayerDataService.combatStats(profile)

		-- Objetivo: el elegido mientras valga; si no, el más cercano a tiro (automático)
		local target = state.Target
		if target then
			local valid = EnemyService.isAlive(target)
				and (if state.Manual then flatDistance(root.Position, target.Root.Position) <= MAX_ENGAGE_RANGE else inReach(root, target, stats.Range + RANGE_SLACK))
			if not valid then
				clearTarget(player, state)
				target = nil
			end
		end
		if not target and state.AutoFire then
			target = EnemyService.findInRadius(root.Position, stats.Range, 1)[1]
			if target then
				setTarget(state, target, false)
			end
		end
		if not target then
			continue
		end
		if target.Billboard then
			target.Billboard.Enabled = true
		end

		local equipped = PlayerDataService.getEquippedPetIds(profile)
		-- Posición del objetivo para que PetFollower mueva las mascotas alrededor
		if #equipped > 0 then
			player:SetAttribute("PetTargetPos", target.Root.Position)
			player:SetAttribute("PetTargetRadius", target.Radius or 2)
		else
			clearTargetAttributes(player)
		end

		-- 1) El arma: a la cadencia del arma mientras esté a tiro
		if state.NextShotAt < now - stats.Cooldown then
			state.NextShotAt = now -- tras una pausa no se acumulan disparos
		end
		local shots = 0
		while shots < MAX_SHOTS_PER_STEP and now >= state.NextShotAt and EnemyService.isAlive(target) and inReach(root, target, stats.Range) do
			shots += 1
			state.NextShotAt += stats.Cooldown
			if fire(player, root, target, stats) then
				break
			end
		end
		if not EnemyService.isAlive(target) then
			clearTarget(player, state)
			continue
		end

		-- 2) Cada mascota equipada golpea periódicamente al mismo objetivo
		for index, petId in equipped do
			if not EnemyService.isAlive(target) then
				break
			end
			local nextAt = state.PetNextHit[index] or 0
			if now >= nextAt then
				state.PetNextHit[index] = now + PET_HIT_INTERVAL + (index - 1) * 0.12
				local damage = singlePetDamage(player, petId)
				local dealt, killed = EnemyService.damage(target, player, damage)
				if dealt > 0 then
					notifyAbility(player, "FoxBolt")
					broadcast(player, root.Position, {
						Kind = "FoxBolt",
						PetId = petId,
						Index = index,
						Target = target.Root.Position,
						Hits = { hitInfo(target, dealt, killed) },
					})
				end
				if killed then
					clearTarget(player, state)
					break
				end
			end
		end
	end
end

function PetCombatService.start()
	abilityRemote = RemoteService.get(Constants.Remotes.PetAbility)

	-- Clic en un enemigo (CombatService) o golpe de una habilidad: pasa a ser el objetivo
	CombatService.onPlayerHit(function(player: Player, enemy: any)
		if EnemyService.isAlive(enemy) then
			setTarget(stateOf(player), enemy, true)
		end
	end)
	EnemyService.onClicked(function(player: Player, enemy: any)
		setTarget(stateOf(player), enemy, true)
	end)
	-- F o el botón "Disparar": enciende o apaga el disparo automático
	RemoteService.get(Constants.Remotes.SetAutoFire).OnServerEvent:Connect(function(player: Player, enabled: any)
		if typeof(enabled) ~= "boolean" or autoLimiter:check(player) ~= "ok" then
			return
		end
		local state = stateOf(player)
		state.AutoFire = enabled
		player:SetAttribute(Constants.Attributes.AutoFire, enabled)
		if not enabled and not state.Manual then
			clearTarget(player, state)
		end
	end)

	local function watch(player: Player)
		stateOf(player)
		player.CharacterRemoving:Connect(function()
			reset(player)
		end)
		player:GetAttributeChangedSignal(Constants.Attributes.CurrentZone):Connect(function()
			reset(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		reset(player)
		states[player] = nil
		autoLimiter:remove(player)
	end)

	task.spawn(function()
		while true do
			task.wait(STEP_SECONDS)
			local ok, err = pcall(PetCombatService.step, os.clock())
			if not ok then
				warn("[PetCombatService] " .. tostring(err))
			end
		end
	end)
end

return PetCombatService
