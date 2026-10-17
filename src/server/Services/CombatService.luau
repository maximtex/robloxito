-- Ataque del jugador. El cliente solo pide "atacar": el servidor comprueba el ritmo,
-- calcula el daño con CombatMath (nivel de mejora y mascotas del perfil del servidor) y
-- elige los objetivos desde la posición y orientación reales del personaje. Cada golpe
-- alcanza a cada enemigo como mucho una vez. Nunca acepta daño, objetivos ni
-- recompensas del cliente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local CombatConfig = require(Shared.Config.CombatConfig)
local CombatMath = require(Shared.CombatMath)
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

-- Pequeña tolerancia sobre el cooldown por la latencia; ráfagas abusivas se ignoran.
local attackLimiter = RateLimiter.new(CombatConfig.AttackCooldown * 0.85, 3, 10)

local function handleAttack(player: Player)
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
	local damage = CombatMath.playerDamage(level, profile.PetMultiplier)
	local targets = EnemyService.findTargets(root.Position, root.CFrame.LookVector, CombatConfig.AttackRange, CombatConfig.AttackArcDot, CombatConfig.MaxTargetsPerSwing)

	local hits = {}
	for _, enemy in targets do
		local position = enemy.Root.Position
		local dealt, killed = EnemyService.damage(enemy, player, damage)
		if dealt > 0 then
			-- Model solo sirve para el destello visual en el cliente; no se acepta de vuelta.
			table.insert(hits, { Position = position, Damage = dealt, Killed = killed, Kind = enemy.Kind, Model = enemy.Model })
		end
	end
	RemoteService.get(Constants.Remotes.AttackResult):FireClient(player, hits)
	-- El primer enemigo alcanzado pasa a ser el objetivo de sus mascotas.
	local first = targets[1]
	if first and #hits > 0 then
		for _, listener in hitListeners do
			task.spawn(listener, player, first)
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
