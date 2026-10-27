-- PetCombatService · Gun: estilo Armas: cargador, recarga, cohetes y disparo (fireGun).
-- Parte de PetCombatService (ver PetCombatService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local WeaponLogic = require(Shared.WeaponLogic)
local StyleLogic = require(Shared.StyleLogic)
local ClassLogic = require(Shared.ClassLogic)
local AimLogic = require(Shared.AimLogic)
local GunLogic = require(Shared.GunLogic)
local EnemyService = require(script.Parent.Parent.EnemyService)
local Types = require(script.Parent.Types)
type State = Types.State

local ctx: any -- tabla de estado compartida (la crea PetCombatService/init.luau)
local PetCombatService: any -- la tabla pública del servicio
local MAX_EFFECT_TARGETS: any
local PELLET_TOLERANCE: any
local SLACK_MAX_SPREAD: any
local burstUntil: any
local states: any

-- Funciones de las otras partes
local function broadcast(...) return ctx.broadcast(...) end
local function chainFrom(...) return ctx.chainFrom(...) end
local function countCombo(...) return ctx.countCombo(...) end
local function directionTo(...) return ctx.directionTo(...) end
local function effectWith(...) return ctx.effectWith(...) end
local function flatDistance(...) return ctx.flatDistance(...) end
local function gather(...) return ctx.gather(...) end
local function hitWith(...) return ctx.hitWith(...) end
local function lifeSteal(...) return ctx.lifeSteal(...) end
local function serverTime(...) return ctx.serverTime(...) end
local function setIfChanged(...) return ctx.setIfChanged(...) end
local function setTarget(...) return ctx.setTarget(...) end
local function splashAround(...) return ctx.splashAround(...) end

-- Armas ----------------------------------------------------------------------------------

local function publishAmmo(player: Player, state: State, magazine: number)
	setIfChanged(player, Constants.Attributes.Ammo, state.Ammo)
	setIfChanged(player, Constants.Attributes.AmmoMax, magazine)
	setIfChanged(player, Constants.Attributes.ReloadEnd, if state.ReloadUntil > 0 then state.ReloadEnd else 0)
end

-- Cargador del arma actual: lleno al cambiar de arma; termina la recarga si toca.
local function ammoUpkeep(player: Player, state: State, stats, now: number)
	if state.AmmoWeapon ~= stats.WeaponId then
		state.AmmoWeapon = stats.WeaponId
		state.Ammo = stats.Magazine
		state.ReloadUntil = 0
	end
	if state.ReloadUntil > 0 and now >= state.ReloadUntil then
		state.ReloadUntil = 0
		state.Ammo = stats.Magazine
	end
	state.Ammo = math.clamp(state.Ammo, 0, stats.Magazine)
	publishAmmo(player, state, stats.Magazine)
end

local function startReload(player: Player, state: State, stats, now: number)
	if state.ReloadUntil > 0 or state.Ammo >= stats.Magazine then
		return
	end
	state.ReloadUntil = now + stats.Reload
	state.ReloadEnd = serverTime(state.ReloadUntil)
	publishAmmo(player, state, stats.Magazine)
end

local function isBursting(player: Player, now: number): boolean
	return (burstUntil[player] or 0) > now
end

-- Cohete de la bazuca: llega a `impact` en `delay` segundos y explota
local function launchRocket(player: Player, state: State, impact: Vector3, target: any?, stats, effect, spec, crit: number, power: number, delay: number)
	local generation = state.Generation
	task.delay(delay, function()
		if states[player] ~= state or state.Generation ~= generation then
			return -- se fue, murió o cambió de zona
		end
		local hits = {}
		local blast = spec.Blast or { Radius = 8, Fraction = 0.8 }
		local radius = math.max(blast.Radius, if effect.Splash then effect.Splash.Radius else 0)
		local fraction = math.max(blast.Fraction, if effect.Splash then effect.Splash.Fraction else 0)
		local main = nil
		if target and EnemyService.isAlive(target) and flatDistance(target.Root.Position, impact) - (target.Radius or 1) <= radius then
			main = target
			local killed = hitWith(player, target, stats.Shot * crit * power, effect.Slow, hits)
			if not killed then
				setTarget(state, target)
				if spec.Knockback and EnemyService.isAlive(target) then
					EnemyService.knockback(target, impact, spec.Knockback)
				end
			end
		end
		for _, other in EnemyService.findInRadius(impact, radius, MAX_EFFECT_TARGETS, player) do
			if other ~= main and EnemyService.canInteract(player, other) then
				local killed = hitWith(player, other, stats.Shot * fraction * power, effect.Slow, hits)
				if spec.Knockback and not killed and EnemyService.isAlive(other) then
					EnemyService.knockback(other, impact, spec.Knockback * 0.6)
				end
			end
		end
		broadcast(player, impact, { Kind = "ShotImpact", WeaponId = stats.WeaponId, Position = impact, Radius = radius, Hits = hits, Crit = crit > 1 })
	end)
end

-- Un disparo del estilo Armas hacia `aim`: una bala (o los perdigones de la escopeta, o el
-- cohete) con su desvío. Devuelve si mató al primero que tocó.
local function fireGun(player: Player, state: State, root: BasePart, aim: Vector3, stats, mods: any?, class: ClassLogic.Mods): boolean
	local spec = GunLogic.specOf(stats.Gun)
	local def = WeaponLogic.definition(stats.WeaponId)
	local effect = ClassLogic.applyEffect(effectWith(StyleLogic.effect("Weapons", def and def.Effect), mods), class)
	local origin = root.Position
	local dx, dz = directionTo(root, aim)
	local candidates, byId = gather(player, origin, stats.Range)
	local directions = GunLogic.directions(dx, dz, spec, state.Ads, PetCombatService.random)
	local pellets = #directions
	local tolerance = if pellets > 1 then PELLET_TOLERANCE else AimLogic.Tolerance.Weapons
	local forgive = pellets == 1 and GunLogic.spread(spec, state.Ads) <= SLACK_MAX_SPREAD
	local adsChance, adsPower = GunLogic.adsCrit(spec, state.Ads)
	local crit = StyleLogic.critMultiplier("Weapons", PetCombatService.random(), class.CritChance + adsChance, class.CritPower + adsPower)

	-- A quién da cada bala (antes de dañar: el combo cuenta una vez por disparo que acierta)
	local plans = {}
	local anyHit = false
	for _, direction in directions do
		local ddx, ddz = direction[1], direction[2]
		local list = AimLogic.lineHits(origin.X, origin.Z, ddx, ddz, candidates, stats.Range, tolerance, GunLogic.maxHits(spec))
		if #list == 0 and forgive then
			local id = AimLogic.nearPoint(origin.X, origin.Z, aim.X, aim.Z, candidates, stats.Range, AimLogic.PointSlack)
			if id ~= nil then
				list = { { Id = id, Along = flatDistance(origin, byId[id].Root.Position) } }
			end
		end
		anyHit = anyHit or #list > 0
		table.insert(plans, { Direction = direction, List = list })
	end
	local combo = if anyHit then countCombo(player, "Weapons", class) else nil
	local power = if combo then combo.Multiplier or 2 else 1

	-- Bazuca: un cohete que llega al primero en su camino o a donde apuntabas y explota
	if spec.Speed then
		local plan = plans[1]
		local first = plan.List[1]
		local target = first and byId[first.Id]
		local impact
		if target then
			impact = target.Root.Position
		else
			local distance = math.clamp(flatDistance(origin, aim), 2, stats.Range)
			impact = Vector3.new(origin.X + plan.Direction[1] * distance, origin.Y, origin.Z + plan.Direction[2] * distance)
		end
		local delay = GunLogic.travelTime(spec, flatDistance(origin, impact))
		broadcast(player, origin, {
			Kind = "PlayerShot",
			WeaponId = stats.WeaponId,
			Style = "Weapons",
			Gun = stats.Gun,
			Crit = crit > 1,
			Target = impact,
			Delay = delay,
			Hits = {},
			Combo = combo and combo.Name,
			Ads = state.Ads,
		})
		launchRocket(player, state, impact, target, stats, effect, spec, crit, power, delay)
		return false
	end

	local hits = {}
	local tracers = {}
	local perBullet = stats.Shot / pellets
	local main = nil
	local killedMain = false
	for _, plan in plans do
		local endPoint = nil
		for index, entry in plan.List do
			local enemy = byId[entry.Id]
			if enemy and EnemyService.isAlive(enemy) then
				local amount = perBullet * GunLogic.pierceFactor(spec, index) * power * (if main == nil or enemy == main then crit else 1)
				local killed = hitWith(player, enemy, amount, effect.Slow, hits)
				if main == nil then
					main = enemy
					killedMain = killed
				end
				endPoint = enemy.Root.Position
			end
		end
		-- El francotirador sigue hasta el final; las demás balas acaban en el primero
		if endPoint == nil or (spec.Pierce or 0) > 0 then
			endPoint = Vector3.new(origin.X + plan.Direction[1] * stats.Range, origin.Y, origin.Z + plan.Direction[2] * stats.Range)
			if plan.List[1] and (spec.Pierce or 0) == 0 then
				endPoint = byId[plan.List[1].Id].Root.Position
			end
		end
		table.insert(tracers, { To = endPoint, Hit = #plan.List > 0 })
	end

	-- Efecto del arma (área, salto) una vez por disparo, en el primero al que dio
	local splashRadius, chain = nil, nil
	local target = main
	if target then
		local point = target.Root.Position
		if effect.Splash then
			splashRadius = effect.Splash.Radius
			splashAround(player, point, splashRadius, stats.Shot * effect.Splash.Fraction * power, effect.Slow, target, hits)
		end
		if effect.Chain then
			chain = chainFrom(player, point, effect.Chain, stats.Shot * effect.Chain.Fraction, effect.Slow, { [target] = true }, hits)
		end
		if not killedMain then
			setTarget(state, target)
		end
		if combo and combo.Knockback and not killedMain and EnemyService.isAlive(target) then
			EnemyService.knockback(target, origin, combo.Knockback)
		end
	end
	lifeSteal(player, "Weapons", class, hits)

	broadcast(player, origin, {
		Kind = "PlayerShot",
		WeaponId = stats.WeaponId,
		Style = "Weapons",
		Gun = stats.Gun,
		Crit = target ~= nil and crit > 1,
		Target = if target then target.Root.Position else tracers[1].To,
		Tracers = tracers,
		Hits = hits,
		Chain = chain,
		Splash = splashRadius,
		Combo = combo and combo.Name,
		Miss = if target then nil else true,
		Ads = state.Ads,
	})
	return killedMain
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.ammoUpkeep = ammoUpkeep
	context.fireGun = fireGun
	context.isBursting = isBursting
	context.publishAmmo = publishAmmo
	context.startReload = startReload
end

function Part.link(context: any)
	PetCombatService = context.Service
	MAX_EFFECT_TARGETS = context.MAX_EFFECT_TARGETS
	PELLET_TOLERANCE = context.PELLET_TOLERANCE
	SLACK_MAX_SPREAD = context.SLACK_MAX_SPREAD
	burstUntil = context.burstUntil
	states = context.states
end

return Part
