-- Disparo del jugador (uno por clic). El cliente solo pide "disparar" y, con clic o toque,
-- propone el modelo del enemigo al que apunta: el servidor comprueba el ritmo, que ese
-- enemigo exista, esté vivo y a tiro desde la posición real del personaje (si no, el disparo
-- se pierde; sin enemigo propuesto, con F o el botón, elige el más cercano a tiro) y calcula
-- el daño con CombatMath (nivel de mejora y mascotas del perfil del servidor). Nunca acepta
-- daño ni recompensas del cliente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local CombatConfig = require(Shared.Config.CombatConfig)
local CombatMath = require(Shared.CombatMath)
local RebirthLogic = require(Shared.RebirthLogic)
local AdventureLogic = require(Shared.AdventureLogic)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local EnemyService = require(script.Parent.EnemyService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local CombatService = {}

-- Avisos de "el jugador ha golpeado a este enemigo" (los usa PetCombatService para saber
-- a quién ayudar). Se registran una vez al arrancar.
local hitListeners: { (Player, any) -> () } = {}
function CombatService.onPlayerHit(listener: (Player, any) -> ())
	table.insert(hitListeners, listener)
end

-- Otro servicio del servidor (AbilityService) avisa de que el jugador ha dañado a este
-- enemigo con una habilidad: sus mascotas se unen igual que tras un golpe normal.
function CombatService.reportHit(player: Player, enemy: any)
	for _, listener in hitListeners do
		task.spawn(listener, player, enemy)
	end
end

-- Pequeña tolerancia sobre el cooldown por la latencia; ráfagas abusivas se ignoran.
local attackLimiter = RateLimiter.new(CombatConfig.AttackCooldown * 0.85, 3, 10)

local function inRange(root: BasePart, enemy: any): boolean
	local offset = enemy.Root.Position - root.Position
	return Vector2.new(offset.X, offset.Z).Magnitude - enemy.Radius <= CombatConfig.ShotRange
end

local function handleAttack(player: Player, aimed: any)
	local rate = attackLimiter:check(player)
	if rate ~= "ok" then
		return -- demasiado pronto o ráfaga: se ignora sin efectos
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
		return
	end
	local profile = PlayerDataService.get(player)
	if not profile then
		return
	end

	local level = profile.UpgradeLevels[CombatConfig.DamageUpgradeId] or 0
	local damage = CombatMath.withBonus(CombatMath.playerDamage(level, profile.PetMultiplier), RebirthLogic.damageMultiplier(RebirthLogic.ofProfile(profile)) * AdventureLogic.damageMultiplier(AdventureLogic.ofProfile(profile), os.time()))
		* CombatConfig.ShotDamageScale

	-- Con clic o toque llega el enemigo apuntado: solo él, si está vivo y a tiro (si no, el
	-- disparo se pierde; nunca va a otro). Sin apuntar (F, botón): el más cercano a tiro.
	local target = nil
	if aimed == nil then
		target = EnemyService.findNearest(root.Position, CombatConfig.ShotRange)
	elseif typeof(aimed) == "Instance" then
		local enemy = EnemyService.fromModel(aimed)
		if enemy and EnemyService.isAlive(enemy) and inRange(root, enemy) then
			target = enemy
		end
	end

	local hits = {}
	if target then
		local position = target.Root.Position
		local dealt, killed, earnedCoins = EnemyService.damage(target, player, damage)
		if dealt > 0 then
			-- Model solo sirve para el destello visual en el cliente; no se acepta de vuelta.
			table.insert(hits, { Position = position, Damage = dealt, Coins = earnedCoins or 0, Killed = killed, Kind = target.Kind, Model = target.Model })
		end
	end
	RemoteService.get(Constants.Remotes.AttackResult):FireClient(player, hits)
	-- El enemigo alcanzado pasa a ser el objetivo de sus mascotas.
	if target and #hits > 0 then
		for _, listener in hitListeners do
			task.spawn(listener, player, target)
		end
	end
end

function CombatService.start()
	RemoteService.get(Constants.Remotes.Attack).OnServerEvent:Connect(handleAttack)
	Players.PlayerRemoving:Connect(function(player)
		attackLimiter:remove(player)
	end)
end

return CombatService
