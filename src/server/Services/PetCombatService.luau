-- Combate de mascotas. Todo en el servidor, con UN bucle para todos los jugadores:
-- - Solo cuentan las mascotas EQUIPADAS según el perfil (PlayerDataService), leídas en
--   cada ciclo: al desequipar, dejan de actuar en el siguiente ciclo.
-- - Actúan solo si el jugador golpeó a un enemigo hace menos de EngageWindow, ese enemigo
--   sigue vivo y está a su alcance (las mascotas siempre van pegadas al jugador, así
--   que las distancias se miden desde él).
-- - Zorrito de Cuarzo: rayo al objetivo del jugador cada Interval.
-- - Tortuga de Musgo Cristalino: reduce el daño de los enemigos (con tope). Se calcula en
--   cada golpe a partir de las tortugas equipadas: nunca se acumula.
-- - Dragón Bebé de Amatista: nova en área alrededor del objetivo tras un aviso; cada
--   enemigo recibe daño como mucho una vez por activación.
-- - El daño pasa por EnemyService.damage: mismas muertes y recompensas (una vez por vida).
-- - Al morir o cambiar de zona se anula todo lo pendiente; los cooldowns se conservan
--   para que morir o reequipar no los reinicie.
-- El cliente nunca envía nada a este servicio; solo recibe PetAbility para los efectos.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local CombatConfig = require(Shared.Config.CombatConfig)
local PetCombatConfig = require(Shared.Config.PetCombatConfig)
local CombatMath = require(Shared.CombatMath)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local EnemyService = require(script.Parent.EnemyService)
local CombatService = require(script.Parent.CombatService)

local Abilities = PetCombatConfig.Abilities

type State = {
	Target: any?, -- enemigo que el jugador está golpeando
	LastHitAt: number,
	FoxNext: { [number]: number }, -- por número de zorrito equipado
	DragonNext: { [number]: number },
	Generation: number, -- cambia al morir o cambiar de zona: anula novas pendientes
}

local PetCombatService = {}

local states: { [Player]: State } = {}
local abilityRemote: RemoteEvent
-- Avisos de habilidad que ha hecho daño real (los usa QuestService).
local abilityListeners: { (Player, string) -> () } = {}

function PetCombatService.onAbilityHit(listener: (Player, string) -> ())
	table.insert(abilityListeners, listener)
end

local function notifyAbility(player: Player, kind: string)
	for _, listener in abilityListeners do
		task.spawn(listener, player, kind)
	end
end

local function stateOf(player: Player): State
	local state = states[player]
	if not state then
		state = { Target = nil, LastHitAt = -math.huge, FoxNext = {}, DragonNext = {}, Generation = 0 }
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

-- Cuántas mascotas de cada especie de combate tiene equipadas (según el servidor).
local function equippedCounts(player: Player): { [string]: number }
	local counts = {}
	local profile = PlayerDataService.get(player)
	if not profile then
		return counts
	end
	for _, petId in PlayerDataService.getEquippedPetIds(profile) do
		if Abilities[petId] then
			counts[petId] = (counts[petId] or 0) + 1
		end
	end
	return counts
end

local function playerDamage(player: Player): number
	local profile = PlayerDataService.get(player)
	if not profile then
		return 0
	end
	return CombatMath.playerDamage(profile.UpgradeLevels[CombatConfig.DamageUpgradeId] or 0, profile.PetMultiplier)
end

-- Efectos: al dueño y a los jugadores cercanos (solo acciones ya resueltas).
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

-- Zorrito de Cuarzo ---------------------------------------------------------------

local function foxAttacks(player: Player, state: State, count: number, root: BasePart, now: number)
	local fox = Abilities.QuartzFox
	for index = 1, count do
		local target = state.Target
		if not (EnemyService.isAlive(target) and flatDistance(root.Position, target.Root.Position) <= fox.Range) then
			return
		end
		if now >= (state.FoxNext[index] or 0) then
			-- Desfase entre zorritos para que no disparen todos a la vez
			state.FoxNext[index] = now + fox.Interval + (index - 1) * 0.15
			local position = target.Root.Position
			local damage = CombatMath.petAbilityDamage(fox.DamageRatio, playerDamage(player))
			local dealt, killed = EnemyService.damage(target, player, damage)
			if dealt > 0 then
				notifyAbility(player, "FoxBolt")
				broadcast(player, root.Position, { Kind = "FoxBolt", PetId = "QuartzFox", Index = index, Target = position, Hits = { hitInfo(target, dealt, killed) } })
			end
			if killed then
				state.Target = nil
			end
		end
	end
end

-- Dragón Bebé de Amatista ---------------------------------------------------------

local function dragonNova(player: Player, state: State, count: number, root: BasePart, now: number)
	local dragon = Abilities.AmethystDragon
	local target = state.Target
	if not (EnemyService.isAlive(target) and flatDistance(root.Position, target.Root.Position) <= dragon.Range) then
		return
	end
	for index = 1, count do
		if now >= (state.DragonNext[index] or 0) then
			state.DragonNext[index] = now + dragon.Cooldown
			local center = target.Root.Position
			local generation = state.Generation
			local readyAt = Workspace:GetServerTimeNow() + dragon.Cooldown
			broadcast(player, center, { Kind = "DragonCast", PetId = "AmethystDragon", Index = index, Center = center, Radius = dragon.Radius, Telegraph = dragon.Telegraph, ReadyAt = readyAt })
			task.delay(dragon.Telegraph, function()
				-- Anulada si murió, cambió de zona, salió o desequipó el dragón durante el aviso.
				if states[player] ~= state or state.Generation ~= generation or not rootOf(player) then
					return
				end
				if (equippedCounts(player).AmethystDragon or 0) < index then
					return
				end
				local damage = CombatMath.petAbilityDamage(dragon.DamageRatio, playerDamage(player))
				local hits = {}
				-- Cada enemigo como mucho una vez por activación (findInRadius no repite).
				for _, enemy in EnemyService.findInRadius(center, dragon.Radius, dragon.MaxTargets) do
					local dealt, killed = EnemyService.damage(enemy, player, damage)
					if dealt > 0 then
						table.insert(hits, hitInfo(enemy, dealt, killed))
					end
				end
				if #hits > 0 then
					notifyAbility(player, "DragonNova")
				end
				broadcast(player, center, { Kind = "DragonImpact", PetId = "AmethystDragon", Index = index, Center = center, Radius = dragon.Radius, Hits = hits })
			end)
			return -- una nova por ciclo como mucho
		end
	end
end

-- Tortuga de Musgo Cristalino --------------------------------------------------------

local function guardIncoming(player: Player, amount: number): number
	local turtles = equippedCounts(player).CrystalTurtle or 0
	local reduction = CombatMath.guardReduction(turtles)
	if reduction <= 0 then
		return amount
	end
	local reduced = CombatMath.reduceIncoming(amount, reduction)
	local root = rootOf(player)
	if root then
		broadcast(player, root.Position, { Kind = "TurtleBlock", PetId = "CrystalTurtle", Blocked = amount - reduced, Reduction = reduction })
	end
	return reduced
end

-- Ciclo -------------------------------------------------------------------------------

local function reset(player: Player)
	local state = states[player]
	if state then
		state.Generation += 1
		state.Target = nil
	end
end

-- Un ciclo para todos los jugadores (público para poder probarlo fuera de Studio).
function PetCombatService.step(now: number)
	for player, state in states do
		if not state.Target then
			continue
		end
		local root = rootOf(player)
		-- Fuera de combate (objetivo muerto o sin golpear hace rato): nada que hacer.
		if not root or now - state.LastHitAt > PetCombatConfig.EngageWindow or not EnemyService.isAlive(state.Target) then
			state.Target = nil
			continue
		end
		local counts = equippedCounts(player)
		if counts.QuartzFox then
			foxAttacks(player, state, counts.QuartzFox, root, now)
		end
		if counts.AmethystDragon then
			dragonNova(player, state, counts.AmethystDragon, root, now)
		end
	end
end

function PetCombatService.start()
	abilityRemote = RemoteService.get(Constants.Remotes.PetAbility)

	CombatService.onPlayerHit(function(player, enemy)
		local state = stateOf(player)
		state.Target = enemy
		state.LastHitAt = os.clock()
	end)
	EnemyService.setIncomingDamageModifier(guardIncoming)

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
			task.wait(PetCombatConfig.TickSeconds)
			local ok, err = pcall(PetCombatService.step, os.clock())
			if not ok then
				warn("[PetCombatService] " .. tostring(err))
			end
		end
	end)
end

return PetCombatService
