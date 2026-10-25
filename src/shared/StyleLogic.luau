-- Lógica pura de los estilos de pelea (StyleConfig): qué estilo vale, cómo cambia el disparo
-- del arma (alcance, tiempo entre golpes, daño por golpe y efecto), las pasivas (crítico,
-- piel dura, robo de vida) y el daño de las habilidades. Sin servicios: la usan
-- PetCombatService, StyleService, PlayerDataService y el cliente (solo para mostrar).

local StyleConfig = require(script.Parent.Config.StyleConfig)

local StyleLogic = {}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function StyleLogic.definition(styleId: any)
	return if type(styleId) == "string" then StyleConfig.Styles[styleId] else nil
end

-- Estilo guardado -> uno que existe (si no, el de por defecto).
function StyleLogic.sanitize(styleId: any): string
	return if StyleLogic.definition(styleId) then styleId else StyleConfig.Default
end

-- ¿Se puede cambiar ya? (cambios muy seguidos se ignoran)
function StyleLogic.canSwitch(lastSwitchAt: number?, now: number): boolean
	return lastSwitchAt == nil or now - lastSwitchAt >= StyleConfig.SwitchCooldown
end

-- Daño por segundo que da el estilo con el `dps` del arma.
function StyleLogic.dps(dps: number, styleId: any): number
	local def = StyleLogic.definition(styleId)
	local scale = if def and finite(def.DpsScale) then def.DpsScale else 1
	return if finite(dps) then math.max(0, dps) * scale else 0
end

-- Disparo del arma (stats de PlayerDataService.combatStats, ya con las mejoras de la
-- partida) convertido al estilo: { Shot, Cooldown, Range } nuevos, el resto igual.
-- `baseCooldown`: el tiempo entre disparos del arma SIN la mejora de cadencia ni las de la
-- partida; lo que se haya acortado se aplica también al estilo.
function StyleLogic.applyStats(stats: { [string]: any }, styleId: any, baseCooldown: number?): { [string]: any }
	local result = table.clone(stats)
	local def = StyleLogic.definition(styleId)
	if not def or not finite(def.Cooldown) then
		return result -- Armas: el arma tal cual
	end
	local shot = if finite(stats.Shot) then math.max(0, stats.Shot) else 0
	local cooldown = if finite(stats.Cooldown) and stats.Cooldown > 0 then stats.Cooldown else 1
	local base = if finite(baseCooldown) and (baseCooldown :: number) > 0 then baseCooldown :: number else cooldown
	local speedFactor = math.clamp(cooldown / base, 0.1, 1) -- cadencia y mejoras: más rápido
	local dps = shot / cooldown
	result.Cooldown = def.Cooldown * speedFactor
	result.Shot = dps * (def.DpsScale or 1) * result.Cooldown
	result.Range = def.Range or stats.Range
	return result
end

-- Efecto de cada golpe: Armas usa el del arma; Puños ninguno; Magia su explosión.
function StyleLogic.effect(styleId: any, weaponEffect: { [string]: any }?): { [string]: any }
	local def = StyleLogic.definition(styleId)
	if styleId == "Weapons" or not def then
		return weaponEffect or {}
	elseif def.Splash then
		return { Splash = { Radius = def.Splash.Radius, Fraction = def.Splash.Fraction } }
	end
	return {}
end

-- Multiplicador de un golpe (crítico de Armas). `roll` en [0, 1).
function StyleLogic.critMultiplier(styleId: any, roll: number): number
	local def = StyleLogic.definition(styleId)
	local passive = def and def.Passive
	if passive and finite(passive.CritChance) and finite(roll) and roll < passive.CritChance then
		return passive.CritMultiplier or 2
	end
	return 1
end

-- Daño que recibe el jugador con este estilo (Puños: piel dura).
function StyleLogic.damageTaken(styleId: any, amount: number): number
	local def = StyleLogic.definition(styleId)
	local factor = def and def.Passive and def.Passive.DamageTaken
	if not finite(amount) then
		return 0
	end
	return if finite(factor) then math.max(0, amount) * math.clamp(factor, 0, 1) else math.max(0, amount)
end

-- Curación por un golpe que ha hecho `dealt` de daño (Magia), con su tope por golpe.
function StyleLogic.lifeSteal(styleId: any, dealt: number, maxHealth: number): number
	local def = StyleLogic.definition(styleId)
	local passive = def and def.Passive
	if not (passive and finite(passive.LifeSteal) and finite(dealt) and finite(maxHealth)) or dealt <= 0 or maxHealth <= 0 then
		return 0
	end
	local cap = if finite(passive.MaxHealPerShot) then passive.MaxHealPerShot * maxHealth else math.huge
	return math.min(dealt * passive.LifeSteal, cap)
end

-- Daño de la habilidad a cada enemigo alcanzado: DamageRatio × DPS del estilo.
function StyleLogic.abilityDamage(styleId: any, styleDps: number): number
	local def = StyleLogic.definition(styleId)
	local ability = def and def.Ability
	if not (ability and finite(ability.DamageRatio) and finite(styleDps)) then
		return 0
	end
	return math.max(0, styleDps) * ability.DamageRatio
end

-- Puntos de caída de los meteoros alrededor de `center` (x, z): `count` puntos en una
-- espiral (siempre los mismos, repartidos) a como mucho `spread`.
function StyleLogic.meteorOffsets(count: number, spread: number): { Vector2 }
	local points = {}
	local n = math.clamp(math.floor(if finite(count) then count else 0), 0, 20)
	for index = 1, n do
		local radius = if index == 1 then 0 else spread * math.sqrt((index - 1) / math.max(1, n - 1))
		local angle = index * 2.39996 -- ángulo áureo: sin amontonarse
		table.insert(points, Vector2.new(math.cos(angle) * radius, math.sin(angle) * radius))
	end
	return points
end

return StyleLogic
