-- Combate de mascotas y Láser del personaje estilo Pet Simulator:
-- - Las mascotas y el Láser del personaje SOLO atacan cuando el jugador presiona un enemigo.
-- - El nivel del Láser (`GeneratorPower`) aumenta el daño y cambia el color/potencia del rayo.
-- - La barra de vida del enemigo solo se muestra mientras está siendo atacado.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local PetConfig = require(Shared.Config.PetConfig)
local PetCombatConfig = require(Shared.Config.PetCombatConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local EnemyService = require(script.Parent.EnemyService)
local CombatService = require(script.Parent.CombatService)

local MAX_ENGAGE_RANGE = 75
local PET_HIT_INTERVAL = 0.65
local LASER_HIT_INTERVAL = 0.55

type State = {
	Target: any?,
	LastHitAt: number,
	NextLaserAt: number,
	PetNextHit: { [number]: number },
	Generation: number,
}

local PetCombatService = {}

local states: { [Player]: State } = {}
local abilityRemote: RemoteEvent
local abilityListeners: { (Player, string) -> () } = {}

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
		state = { Target = nil, LastHitAt = -math.huge, NextLaserAt = 0, PetNextHit = {}, Generation = 0 }
		states[player] = state
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

local function playerLaserDamage(player: Player): (number, number)
	local profile = PlayerDataService.get(player)
	if not profile then
		return 5, 0
	end
	local stats = PlayerDataService.combatStats(profile)
	return math.max(1, stats.Shot), stats.Level
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
	clearTargetAttributes(player)
	if old then
		hideBarIfUntargeted(old)
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

function PetCombatService.step(now: number)
	for player, state in states do
		local root = rootOf(player)
		if not root then
			clearTarget(player, state)
			continue
		end

		local target = state.Target
		if not (EnemyService.isAlive(target) and flatDistance(root.Position, target.Root.Position) <= MAX_ENGAGE_RANGE) then
			if target then
				clearTarget(player, state)
			end
			continue
		end

		if target.Billboard then
			target.Billboard.Enabled = true
		end

		local profile = PlayerDataService.get(player)
		local equipped = if profile then PlayerDataService.getEquippedPetIds(profile) else {}

		-- Publicar posición del objetivo para que PetFollower mueva las mascotas alrededor del "coso"
		if #equipped > 0 then
			player:SetAttribute("PetTargetPos", target.Root.Position)
			player:SetAttribute("PetTargetRadius", target.Radius or 2)
		else
			clearTargetAttributes(player)
		end

		-- 1) Láser del personaje (mejorable en la Tienda de Láser)
		if now >= state.NextLaserAt and EnemyService.isAlive(target) then
			local laserSpeedLevel = if profile then (profile.UpgradeLevels.LaserSpeed or 0) else 0
			state.NextLaserAt = now + math.max(0.2, LASER_HIT_INTERVAL - laserSpeedLevel * 0.022)
			local laserDmg, laserLevel = playerLaserDamage(player)
			local dealt, killed = EnemyService.damage(target, player, laserDmg)
			if dealt > 0 then
				broadcast(player, root.Position, {
					Kind = "PlayerLaser",
					LaserLevel = laserLevel,
					Target = target.Root.Position,
					Hits = { hitInfo(target, dealt, killed) },
				})
			end
			if killed then
				clearTarget(player, state)
				continue
			end
		end

		-- 2) Cada mascota equipada golpea periódicamente al objetivo seleccionado
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

	local function assignTarget(player: Player, enemy: any)
		local state = stateOf(player)
		local old = state.Target
		if old and old ~= enemy then
			state.Target = nil
			hideBarIfUntargeted(old)
		end
		state.Target = enemy
		state.LastHitAt = os.clock()
		if enemy and enemy.Billboard then
			enemy.Billboard.Enabled = true
		end
	end

	CombatService.onPlayerHit(assignTarget)
	EnemyService.onClicked(assignTarget)

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
	end)

	task.spawn(function()
		while true do
			task.wait(0.15)
			local ok, err = pcall(PetCombatService.step, os.clock())
			if not ok then
				warn("[PetCombatService] " .. tostring(err))
			end
		end
	end)
end

return PetCombatService
