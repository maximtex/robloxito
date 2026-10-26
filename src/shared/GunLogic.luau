-- Lógica pura de las armas de fuego del estilo Armas (WeaponConfig.Guns, campo Gun de cada
-- arma): cómo cambia el disparo según el tipo (pistola, rifle, escopeta, francotirador o
-- bazuca), hacia dónde sale cada bala o perdigón (desvío sin apuntar / apuntando), el
-- cargador y la recarga, los críticos al apuntar y lo que tarda un cohete. Sin servicios:
-- la usan PetCombatService (el disparo), GearService (el modelo de la mano) y el cliente
-- (solo para mostrar: mira, balas, Armería).

local WeaponConfig = require(script.Parent.Config.WeaponConfig)

local GunLogic = {}

local DEFAULT_KIND = "Pistol"

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Tipo de arma de fuego de un arma ("Pistol" si no dice otro o no existe)
function GunLogic.kind(weaponId: any): string
	local def = if type(weaponId) == "string" then WeaponConfig.Weapons[weaponId] else nil
	local kind = def and def.Gun
	return if type(kind) == "string" and WeaponConfig.Guns[kind] then kind else DEFAULT_KIND
end

-- Números del tipo de arma de fuego de un arma
function GunLogic.spec(weaponId: any): { [string]: any }
	return WeaponConfig.Guns[GunLogic.kind(weaponId)]
end

function GunLogic.specOf(kind: any): { [string]: any }
	return WeaponConfig.Guns[kind] or WeaponConfig.Guns[DEFAULT_KIND]
end

-- Disparo del arma (stats de PlayerDataService.combatStats, ya con mejoras) con su tipo:
-- Shot = daño de cada disparo (la escopeta lo reparte entre sus perdigones), Cooldown,
-- Range (más apuntando), Magazine, Reload, Pellets y Gun (el tipo).
function GunLogic.applyStats(stats: { [string]: any }, weaponId: any, ads: boolean?): { [string]: any }
	local result = table.clone(stats)
	local kind = GunLogic.kind(weaponId)
	local spec = WeaponConfig.Guns[kind]
	local shot = if finite(stats.Shot) then math.max(0, stats.Shot) else 0
	local cooldown = if finite(stats.Cooldown) and stats.Cooldown > 0 then stats.Cooldown else 1
	local range = if finite(stats.Range) then math.max(0, stats.Range) else 0
	result.Gun = kind
	result.Cooldown = cooldown * (spec.FireScale or 1)
	result.Shot = shot * (spec.FireScale or 1) * (spec.DamageScale or 1)
	result.Range = range * (spec.RangeScale or 1) * (if ads then WeaponConfig.Ads.RangeScale else 1)
	result.Magazine = math.max(1, math.floor(spec.Magazine or 1))
	result.Reload = math.max(0, spec.Reload or 0)
	result.Pellets = math.max(1, math.floor(spec.Pellets or 1))
	return result
end

-- Grados de desvío de cada bala (o medio abanico de la escopeta)
function GunLogic.spread(spec: { [string]: any }, ads: boolean?): number
	local value = if ads then spec.AdsSpread else spec.Spread
	return if finite(value) then math.max(0, value :: number) else 0
end

-- Gira la dirección plana (dx, dz) `degrees` grados alrededor del eje vertical
function GunLogic.rotate(dx: number, dz: number, degrees: number): (number, number)
	local a = math.rad(degrees)
	local c, s = math.cos(a), math.sin(a)
	return dx * c + dz * s, -dx * s + dz * c
end

-- Direcciones de un disparo hacia (dx, dz): una por bala o perdigón, cada una desviada al
-- azar (`random` da números en [0, 1)). Los perdigones se reparten por el abanico.
function GunLogic.directions(dx: number, dz: number, spec: { [string]: any }, ads: boolean?, random: () -> number): { { number } }
	local spread = GunLogic.spread(spec, ads)
	local pellets = math.max(1, math.floor(spec.Pellets or 1))
	local list = {}
	if pellets == 1 then
		local angle = if spread > 0 then (random() * 2 - 1) * spread else 0
		local x, z = GunLogic.rotate(dx, dz, angle)
		table.insert(list, { x, z })
		return list
	end
	local step = spread * 2 / pellets
	for index = 1, pellets do
		local angle = -spread + (index - 0.5) * step + (random() - 0.5) * step * 0.6
		local x, z = GunLogic.rotate(dx, dz, angle)
		table.insert(list, { x, z })
	end
	return list
end

-- Parte del daño que hace la bala al enemigo número `index` que atraviesa (1 = el primero)
function GunLogic.pierceFactor(spec: { [string]: any }, index: number): number
	local falloff = if finite(spec.PierceFalloff) then spec.PierceFalloff else 1
	return falloff ^ math.max(0, index - 1)
end

-- Enemigos que puede dañar una bala (1 + los que atraviesa)
function GunLogic.maxHits(spec: { [string]: any }): number
	return 1 + math.max(0, math.floor(spec.Pierce or 0))
end

-- Segundos que tarda en llegar un cohete a `distance` (0 si la bala es instantánea)
function GunLogic.travelTime(spec: { [string]: any }, distance: number): number
	if not (finite(spec.Speed) and spec.Speed > 0 and finite(distance)) then
		return 0
	end
	return math.max(0, distance) / spec.Speed
end

-- Críticos extra al apuntar: probabilidad y fuerza (+× al multiplicador)
function GunLogic.adsCrit(spec: { [string]: any }, ads: boolean?): (number, number)
	if not ads then
		return 0, 0
	end
	return (if finite(spec.AdsCrit) then spec.AdsCrit else 0), (if finite(spec.AdsCritPower) then spec.AdsCritPower else 0)
end

-- Daño sostenido (con la recarga) respecto al DPS del arma, si entran todas las balas: para
-- comprobar el equilibrio entre tipos.
function GunLogic.sustainedRatio(spec: { [string]: any }, cooldown: number): number
	local fire = (spec.FireScale or 1) * cooldown
	local magazine = math.max(1, spec.Magazine or 1)
	return (spec.DamageScale or 1) * magazine * fire / (magazine * fire + (spec.Reload or 0))
end

return GunLogic
