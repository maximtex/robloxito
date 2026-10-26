-- Lógica pura del estilo Magia (StyleConfig.Styles.Magic): maná (gastar y recuperar), la bola
-- rápida y la chispa sin maná, el orbe cargado (daño, explosión y coste según lo que hayas
-- mantenido), el elemento de cada bastón y el teletransporte. Sin servicios: la usan
-- PetCombatService, StyleService y el cliente (barra de maná, orbe que crece).

local StyleConfig = require(script.Parent.Config.StyleConfig)
local WeaponConfig = require(script.Parent.Config.WeaponConfig)

local MagicLogic = {}

local DEFAULT_ELEMENT = "Fire"

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function def()
	return StyleConfig.Styles.Magic
end
MagicLogic.definition = def

function MagicLogic.maxMana(): number
	return def().Mana.Max
end

-- Maná tras `dt` segundos llevando `idleFor` segundos sin gastar (sin pasar del máximo)
function MagicLogic.regen(mana: number, dt: number, idleFor: number?): number
	local spec = def().Mana
	local current = if finite(mana) then math.clamp(mana, 0, spec.Max) else spec.Max
	if not (finite(dt) and dt > 0) then
		return current
	end
	local rate = if finite(idleFor) and (idleFor :: number) >= spec.IdleSeconds then spec.IdleRegen else spec.Regen
	return math.min(spec.Max, current + rate * dt)
end

function MagicLogic.boltCost(): number
	return def().Mana.BoltCost
end

-- Daño de la chispa (sin maná) a partir del de la bola
function MagicLogic.spark(shot: number): number
	return (if finite(shot) then math.max(0, shot) else 0) * def().Mana.SparkScale
end

-- Parte cargada (0..1) tras mantener `held` segundos desde que empezó a cargar
function MagicLogic.chargeFraction(held: number): number
	local spec = def().Charge
	if not finite(held) then
		return 0
	end
	return math.clamp(held / spec.Full, 0, 1)
end

-- Orbe cargado con el `dps` del estilo tras cargar `held` segundos: { Damage, Radius,
-- Fraction, Cost, Charge (0..1) }. Cargar más de Full no da más.
function MagicLogic.charged(dps: number, held: number): { [string]: number }
	local spec = def().Charge
	local charge = MagicLogic.chargeFraction(held)
	local seconds = charge * spec.Full
	local power = if finite(dps) then math.max(0, dps) else 0
	return {
		Damage = power * (spec.BaseSeconds + seconds) * spec.Bonus,
		Radius = spec.Radius[1] + (spec.Radius[2] - spec.Radius[1]) * charge,
		Fraction = spec.Fraction,
		Cost = spec.Cost[1] + (spec.Cost[2] - spec.Cost[1]) * charge,
		Charge = charge,
	}
end

-- Elemento del bastón (WeaponConfig, Element; Fuego si no dice otro)
function MagicLogic.element(weaponId: any): string
	local item = if type(weaponId) == "string" then WeaponConfig.Weapons[weaponId] else nil
	local element = item and item.Element
	return if type(element) == "string" and def().Elements[element] then element else DEFAULT_ELEMENT
end

-- Efecto de un elemento en los golpes del bastón (StyleConfig.Styles.Magic.Elements)
function MagicLogic.elementDef(element: any): { [string]: any }
	return def().Elements[element] or def().Elements[DEFAULT_ELEMENT]
end

-- Maná que gasta una habilidad (0 si no gasta)
function MagicLogic.skillCost(ability: any): number
	return if type(ability) == "table" and finite(ability.ManaCost) then math.max(0, ability.ManaCost) else 0
end

return MagicLogic
