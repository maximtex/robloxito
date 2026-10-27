-- PetCombatService · Melee: estilos Guerrero (tajos) y Puños (puñetazos).
-- Parte de PetCombatService (ver PetCombatService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponLogic = require(Shared.WeaponLogic)
local StyleLogic = require(Shared.StyleLogic)
local StyleConfig = require(Shared.Config.StyleConfig)
local ClassLogic = require(Shared.ClassLogic)
local AimLogic = require(Shared.AimLogic)
local WarriorLogic = require(Shared.WarriorLogic)
local EnemyService = require(script.Parent.Parent.EnemyService)
local Types = require(script.Parent.Types)
type State = Types.State

local ctx: any -- tabla de estado compartida (la crea PetCombatService/init.luau)
local PetCombatService: any -- la tabla pública del servicio

-- Funciones de las otras partes
local function broadcast(...) return ctx.broadcast(...) end
local function chainFrom(...) return ctx.chainFrom(...) end
local function countCombo(...) return ctx.countCombo(...) end
local function directionTo(...) return ctx.directionTo(...) end
local function effectWith(...) return ctx.effectWith(...) end
local function gather(...) return ctx.gather(...) end
local function hitWith(...) return ctx.hitWith(...) end
local function lifeSteal(...) return ctx.lifeSteal(...) end
local function resolveShot(...) return ctx.resolveShot(...) end
local function setTarget(...) return ctx.setTarget(...) end
local function splashAround(...) return ctx.splashAround(...) end

-- Guerrero -------------------------------------------------------------------------------

-- Un tajo del combo hacia `aim`: a todos los del arco (el 3.º, alrededor). Devuelve si mató
-- al principal y lo que tarda el siguiente.
local function fireSlash(player: Player, state: State, root: BasePart, aim: Vector3, stats, mods: any?, class: ClassLogic.Mods, now: number): (boolean, number)
	local step, slash = WarriorLogic.nextSlash(state.Combo, now)
	local def = WeaponLogic.definition(stats.WeaponId)
	local effect = ClassLogic.applyEffect(effectWith(StyleLogic.effect("Warrior", def and def.Effect), mods), class)
	local origin = root.Position
	local dx, dz = directionTo(root, aim)
	local range = stats.Range * (slash.RangeScale or 1)
	local candidates, byId = gather(player, origin, range)
	local ids = AimLogic.arcAll(origin.X, origin.Z, dx, dz, candidates, range, slash.Arc or 70, slash.MaxTargets or 4)
	local counter = now <= state.CounterUntil and #ids > 0
	if counter then
		state.CounterUntil = 0
	end
	local crit = if #ids > 0 then StyleLogic.critMultiplier("Warrior", PetCombatService.random(), class.CritChance, class.CritPower) else 1
	local blockSpec = StyleConfig.Styles.Warrior.Block
	local power = (slash.Ratio or 1) * (if counter then blockSpec.CounterMultiplier else 1)
	local hits = {}
	local main = nil
	local killedMain = false
	for _, id in ids do
		local enemy = byId[id]
		if enemy and EnemyService.isAlive(enemy) then
			local killed = hitWith(player, enemy, stats.Shot * power * crit, effect.Slow, hits)
			if main == nil then
				main = enemy
				killedMain = killed
			end
			if slash.Knockback and not killed and EnemyService.isAlive(enemy) then
				EnemyService.knockback(enemy, origin, slash.Knockback)
			end
		end
	end
	local splashRadius, chain = nil, nil
	if main then
		local point = main.Root.Position
		if effect.Splash then
			splashRadius = effect.Splash.Radius
			splashAround(player, point, splashRadius, stats.Shot * effect.Splash.Fraction, effect.Slow, main, hits)
		end
		if effect.Chain then
			local visited = {}
			for _, id in ids do
				if byId[id] then
					visited[byId[id]] = true
				end
			end
			chain = chainFrom(player, point, effect.Chain, stats.Shot * effect.Chain.Fraction, effect.Slow, visited, hits)
		end
		if not killedMain then
			setTarget(state, main)
		end
	end
	lifeSteal(player, "Warrior", class, hits)
	local reach = math.min(range, 4)
	broadcast(player, origin, {
		Kind = "PlayerShot",
		WeaponId = stats.WeaponId,
		Style = "Warrior",
		Step = step,
		Counter = counter or nil,
		Crit = crit > 1,
		Target = if main then main.Root.Position else Vector3.new(origin.X + dx * reach, origin.Y, origin.Z + dz * reach),
		Direction = Vector3.new(dx, 0, dz),
		Radius = range,
		Hits = hits,
		Chain = chain,
		Splash = splashRadius,
		Miss = if main then nil else true,
	})
	return killedMain, WarriorLogic.recovery(slash, stats.Cooldown)
end

-- Puños ----------------------------------------------------------------------------------

-- Un puñetazo hacia `aim`: al más cercano del arco de enfrente, con su efecto.
local function firePunch(player: Player, state: State, root: BasePart, aim: Vector3, stats, mods: any?, class: ClassLogic.Mods): boolean
	local target, point = resolveShot(player, root, aim, stats.Range, "Fists")
	local def = WeaponLogic.definition(stats.WeaponId)
	local effect = ClassLogic.applyEffect(effectWith(StyleLogic.effect("Fists", def and def.Effect), mods), class)
	local hits = {}
	local crit, combo, killed = 1, nil, false
	if target then
		crit = StyleLogic.critMultiplier("Fists", PetCombatService.random(), class.CritChance, class.CritPower)
		combo = countCombo(player, "Fists", class)
	end
	local power = if combo then combo.Multiplier or 2 else 1
	if target then
		killed = hitWith(player, target, stats.Shot * crit * power, effect.Slow, hits)
		if combo and combo.Knockback and not killed and EnemyService.isAlive(target) then
			EnemyService.knockback(target, root.Position, combo.Knockback, combo.Lift)
		end
		if not killed then
			setTarget(state, target)
		end
	end
	local splashRadius, chain = nil, nil
	if target and effect.Splash then
		splashRadius = effect.Splash.Radius * (if combo and combo.SplashScale then combo.SplashScale else 1)
		splashAround(player, point, splashRadius, stats.Shot * effect.Splash.Fraction * power, effect.Slow, target, hits)
	end
	if target and effect.Chain then
		chain = chainFrom(player, point, effect.Chain, stats.Shot * effect.Chain.Fraction, effect.Slow, { [target] = true }, hits)
	end
	lifeSteal(player, "Fists", class, hits)
	broadcast(player, root.Position, {
		Kind = "PlayerShot",
		WeaponId = stats.WeaponId,
		Style = "Fists",
		Crit = crit > 1,
		Target = point,
		Hits = hits,
		Chain = chain,
		Splash = splashRadius,
		Combo = combo and combo.Name,
		Miss = if target then nil else true,
	})
	return killed
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.firePunch = firePunch
	context.fireSlash = fireSlash
end

function Part.link(context: any)
	PetCombatService = context.Service
end

return Part
