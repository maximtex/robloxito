-- PetCombatService · Hits: golpes compartidos: avisos al cliente, objetivo, mascotas, estados, curación, área, salto y combo.
-- Parte de PetCombatService (ver PetCombatService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local PetConfig = require(Shared.Config.PetConfig)
local PetCombatConfig = require(Shared.Config.PetCombatConfig)
local StyleLogic = require(Shared.StyleLogic)
local ClassLogic = require(Shared.ClassLogic)
local WarriorLogic = require(Shared.WarriorLogic)
local PlayerDataService = require(script.Parent.Parent.PlayerDataService)
local EnemyService = require(script.Parent.Parent.EnemyService)
local Types = require(script.Parent.Types)
type State = Types.State

local ctx: any -- tabla de estado compartida (la crea PetCombatService/init.luau)
local BOSS_CONTROL: any
local MAX_EFFECT_TARGETS: any
local hitCombos: any
local states: any

-- Funciones de las otras partes
local function hideBarIfUntargeted(...) return ctx.hideBarIfUntargeted(...) end
local function rootOf(...) return ctx.rootOf(...) end

local function broadcast(owner: Player, origin: Vector3, event: { [string]: any })
	event.Owner = owner
	for _, player in Players:GetPlayers() do
		local root = if player == owner then nil else rootOf(player)
		if player == owner or (root and (root.Position - origin).Magnitude <= PetCombatConfig.BroadcastRange) then
			ctx.abilityRemote:FireClient(player, event)
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
	clearTargetAttributes(player)
	if old then
		hideBarIfUntargeted(old)
	end
end

local function setTarget(state: State, enemy: any)
	local old = state.Target
	state.Target = enemy
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
		state.ChargeStart = nil
		state.PendingCharge = nil
		state.Ads = false
		WarriorLogic.stopBlock(state.Block)
		player:SetAttribute(Constants.Attributes.Blocking, false)
		clearTarget(player, state)
	else
		clearTargetAttributes(player)
	end
end

-- Estado (frenar, raíces, aturdir, debilitar) con menos tiempo en los jefes
local function control(enemy: any, kind: string, seconds: number, factor: number?)
	if not EnemyService.isAlive(enemy) then
		return
	end
	local duration = if enemy.Kind == "Boss" and kind ~= "Vulnerable" then seconds * BOSS_CONTROL else seconds
	EnemyService.applyControl(enemy, kind, duration, factor)
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

-- Cura al jugador, sin pasar de su vida máxima.
local function heal(player: Player, amount: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and amount > 0 then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	end
end

local function maxHealthOf(player: Player): number?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid then humanoid.MaxHealth else nil
end

-- Robo de vida (Magia y clases): una parte de todo el daño de este golpe, con tope
local function lifeSteal(player: Player, style: string, class: ClassLogic.Mods, hits: { any }, extra: number?)
	local rate = class.LifeSteal + (extra or 0)
	if not (style == "Magic" or rate > 0) or #hits == 0 then
		return
	end
	local dealt = 0
	for _, hit in hits do
		dealt += hit.Damage
	end
	local maxHealth = maxHealthOf(player)
	if maxHealth then
		heal(player, StyleLogic.lifeSteal(style, dealt, maxHealth, rate))
	end
end

-- Explosión alrededor de `point` (sin el objetivo principal) a una parte del daño
local function splashAround(player: Player, point: Vector3, radius: number, amount: number, slow, skip: any?, hits: { any })
	for _, other in EnemyService.findInRadius(point, radius, MAX_EFFECT_TARGETS, player) do
		if other ~= skip and EnemyService.canInteract(player, other) then
			hitWith(player, other, amount, slow, hits)
		end
	end
end

-- Salto a otros enemigos desde `from` (sin repetir `visited`): devuelve los puntos del salto
local function chainFrom(player: Player, from: Vector3, chain, amount: number, slow, visited: { [any]: boolean }, hits: { any }): { Vector3 }
	local points = {}
	local at = from
	for _ = 1, chain.Count do
		local nextEnemy = nil
		for _, candidate in EnemyService.findInRadius(at, chain.Range, MAX_EFFECT_TARGETS, player) do
			if not visited[candidate] and EnemyService.canInteract(player, candidate) then
				nextEnemy = candidate
				break
			end
		end
		if not nextEnemy then
			break
		end
		visited[nextEnemy] = true
		at = nextEnemy.Root.Position
		table.insert(points, at)
		hitWith(player, nextEnemy, amount, slow, hits)
	end
	return points
end

-- Combo de golpes (tiro cargado, gancho): cuenta el golpe y devuelve el combo si toca
local function countCombo(player: Player, style: string, class: ClassLogic.Mods)
	local comboState = hitCombos[player] or { Count = 0, Last = 0 }
	hitCombos[player] = comboState
	return StyleLogic.countHit(style, comboState, os.clock(), class.ComboEvery)
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.broadcast = broadcast
	context.chainFrom = chainFrom
	context.clearTarget = clearTarget
	context.clearTargetAttributes = clearTargetAttributes
	context.control = control
	context.countCombo = countCombo
	context.heal = heal
	context.hitInfo = hitInfo
	context.hitWith = hitWith
	context.lifeSteal = lifeSteal
	context.maxHealthOf = maxHealthOf
	context.reset = reset
	context.setTarget = setTarget
	context.singlePetDamage = singlePetDamage
	context.splashAround = splashAround
end

function Part.link(context: any)
	BOSS_CONTROL = context.BOSS_CONTROL
	MAX_EFFECT_TARGETS = context.MAX_EFFECT_TARGETS
	hitCombos = context.hitCombos
	states = context.states
end

return Part
