-- PetCombatService · Magic: estilo Magia: maná, efecto del elemento y orbes (fireMagic).
-- Parte de PetCombatService (ver PetCombatService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local WeaponLogic = require(Shared.WeaponLogic)
local StyleLogic = require(Shared.StyleLogic)
local ClassLogic = require(Shared.ClassLogic)
local AimLogic = require(Shared.AimLogic)
local MagicLogic = require(Shared.MagicLogic)
local EnemyService = require(script.Parent.Parent.EnemyService)

local ctx: any -- tabla de estado compartida (la crea PetCombatService/init.luau)
local PetCombatService: any -- la tabla pública del servicio

-- Funciones de las otras partes
local function broadcast(...) return ctx.broadcast(...) end
local function chainFrom(...) return ctx.chainFrom(...) end
local function control(...) return ctx.control(...) end
local function directionTo(...) return ctx.directionTo(...) end
local function effectWith(...) return ctx.effectWith(...) end
local function flatDistance(...) return ctx.flatDistance(...) end
local function heal(...) return ctx.heal(...) end
local function hitWith(...) return ctx.hitWith(...) end
local function lifeSteal(...) return ctx.lifeSteal(...) end
local function magicLock(...) return ctx.magicLock(...) end
local function maxHealthOf(...) return ctx.maxHealthOf(...) end
local function setIfChanged(...) return ctx.setIfChanged(...) end
local function setTarget(...) return ctx.setTarget(...) end
local function splashAround(...) return ctx.splashAround(...) end

-- Magia ----------------------------------------------------------------------------------

local function publishMana(player: Player, state: State)
	setIfChanged(player, Constants.Attributes.Mana, math.floor(state.Mana))
	setIfChanged(player, Constants.Attributes.ManaMax, MagicLogic.maxMana())
end

local function manaUpkeep(player: Player, state: State, now: number)
	local dt = now - state.ManaAt
	state.ManaAt = now
	state.Mana = MagicLogic.regen(state.Mana, dt, now - state.ManaSpentAt)
	publishMana(player, state)
end

local function spendMana(player: Player, state: State, cost: number, now: number): boolean
	if cost <= 0 then
		return true
	end
	if state.Mana < cost then
		return false
	end
	state.Mana -= cost
	state.ManaSpentAt = now
	publishMana(player, state)
	return true
end

-- Efecto del elemento del bastón en el bicho principal (además de la marca y los combos)
local function elementEffect(player: Player, enemy: any, element: string, charged: boolean)
	local spec = MagicLogic.elementDef(element)
	if not EnemyService.isAlive(enemy) then
		return
	end
	if spec.Slow then
		control(enemy, "Slow", spec.SlowSeconds or 1.5, spec.Slow)
	end
	if spec.Vulnerable then
		control(enemy, "Vulnerable", spec.VulnerableSeconds or 3, spec.Vulnerable)
	end
	if spec.RootSeconds and charged then
		control(enemy, "Root", spec.RootSeconds)
	end
end

-- Una bola (o el orbe cargado, con `charge`) hacia `aim`: persigue al bicho más cercano al
-- punto apuntado; si no hay, explota donde apuntabas.
local function fireMagic(player: Player, state: State, root: BasePart, aim: Vector3, stats, mods: any?, class: ClassLogic.Mods, now: number, charge: { [string]: number }?, free: boolean?): boolean
	local def = WeaponLogic.definition(stats.WeaponId)
	local element = MagicLogic.element(stats.WeaponId)
	local elementSpec = MagicLogic.elementDef(element)
	local origin = root.Position
	local target = magicLock(player, root, aim, stats.Range)

	-- Maná: la bola o el orbe; sin maná, chispa (el orbe se carga hasta donde llegue)
	local spark = false
	local damage = stats.Shot
	local splashSpec = nil
	local chargeAmount = nil
	if charge then
		chargeAmount = charge
		if not free and not spendMana(player, state, charge.Cost, now) then
			spark = true
		end
	elseif not free and not spendMana(player, state, MagicLogic.boltCost(), now) then
		spark = true
	end
	if spark then
		damage = MagicLogic.spark(stats.Shot)
		chargeAmount = nil
	elseif chargeAmount then
		damage = chargeAmount.Damage
	end

	local effect = ClassLogic.applyEffect(effectWith(StyleLogic.effect("Magic", def and def.Effect), mods), class)
	if chargeAmount then
		splashSpec = { Radius = math.max(chargeAmount.Radius, if effect.Splash then effect.Splash.Radius else 0), Fraction = chargeAmount.Fraction }
	elseif not spark then
		splashSpec = effect.Splash
	end

	local point
	if target then
		point = target.Root.Position
	else
		local dx, dz = directionTo(root, aim)
		local distance = AimLogic.missDistance("Magic", flatDistance(origin, aim), stats.Range)
		point = Vector3.new(origin.X + dx * distance, origin.Y, origin.Z + dz * distance)
	end

	local hits = {}
	local crit = 1
	local killed = false
	local chain = nil
	if target then
		crit = StyleLogic.critMultiplier("Magic", PetCombatService.random(), class.CritChance, class.CritPower)
		local amount = damage * crit
		if not spark and ctx.elementHook then
			-- Fuego: además quema (una parte del golpe cada segundo)
			local burn = if elementSpec.Burn then { Tick = amount * elementSpec.Burn, Seconds = elementSpec.BurnSeconds or 3 } else nil
			local ok, multiplier = pcall(ctx.elementHook, player, target, element, amount, burn)
			if ok and type(multiplier) == "number" and multiplier == multiplier then
				amount *= math.clamp(multiplier, 0, 4)
			end
		end
		killed = hitWith(player, target, amount, effect.Slow, hits)
		if not killed then
			setTarget(state, target)
			if not spark then
				elementEffect(player, target, element, chargeAmount ~= nil)
			end
		end
	end
	if splashSpec then
		splashAround(player, point, splashSpec.Radius, damage * splashSpec.Fraction, effect.Slow, target, hits)
	end
	if target and not spark then
		local chainSpec = effect.Chain
		if elementSpec.Chain and not (chainSpec and chainSpec.Count >= elementSpec.Chain.Count) then
			chainSpec = elementSpec.Chain
		end
		if chainSpec then
			chain = chainFrom(player, point, chainSpec, damage * chainSpec.Fraction, effect.Slow, { [target] = true }, hits)
		end
	end
	-- Robo de vida de la Magia (y Naturaleza: más) y curación Celestial
	if not spark then
		lifeSteal(player, "Magic", class, hits, elementSpec.LifeSteal)
		if elementSpec.Heal and #hits > 0 then
			local maxHealth = maxHealthOf(player)
			if maxHealth then
				heal(player, maxHealth * elementSpec.Heal)
			end
		end
	end

	broadcast(player, origin, {
		Kind = "PlayerShot",
		WeaponId = stats.WeaponId,
		Style = "Magic",
		Element = element,
		Spark = spark or nil,
		Charge = if chargeAmount then chargeAmount.Charge else nil,
		Crit = crit > 1,
		Target = point,
		Hits = hits,
		Chain = chain,
		Splash = if splashSpec then splashSpec.Radius else nil,
		Miss = if target then nil else true,
	})
	return killed
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.fireMagic = fireMagic
	context.manaUpkeep = manaUpkeep
	context.spendMana = spendMana
end

function Part.link(context: any)
	PetCombatService = context.Service
end

return Part
