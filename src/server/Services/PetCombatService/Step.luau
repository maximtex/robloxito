-- PetCombatService · Step: el paso de cada ciclo: objetivo válido, cambio de estilo, números del ataque y step().
-- Parte de PetCombatService (ver PetCombatService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local MonetizationLogic = require(Shared.MonetizationLogic)
local StyleConfig = require(Shared.Config.StyleConfig)
local ClassLogic = require(Shared.ClassLogic)
local AimLogic = require(Shared.AimLogic)
local GunLogic = require(Shared.GunLogic)
local MagicLogic = require(Shared.MagicLogic)
local WarriorLogic = require(Shared.WarriorLogic)
local PlayerDataService = require(script.Parent.Parent.PlayerDataService)
local EnemyService = require(script.Parent.Parent.EnemyService)

local ctx: any -- tabla de estado compartida (la crea PetCombatService/init.luau)
local Api = {} -- funciones públicas de esta parte (init.luau las copia a PetCombatService)
local AIM_FRESH_SECONDS: any
local MAX_CHARGE_SECONDS: any
local MAX_ENGAGE_RANGE: any
local MAX_SHOTS_PER_STEP: any
local MAX_TWIN_SHOTS: any
local PET_HIT_INTERVAL: any
local SHOT_REQUEST_SECONDS: any
local STEP_SECONDS: any
local TARGET_MEMORY: any
local burstDamage: any
local burstScale: any
local states: any

-- Funciones de las otras partes
local function aimOf(...) return ctx.aimOf(...) end
local function ammoUpkeep(...) return ctx.ammoUpkeep(...) end
local function broadcast(...) return ctx.broadcast(...) end
local function clearTarget(...) return ctx.clearTarget(...) end
local function clearTargetAttributes(...) return ctx.clearTargetAttributes(...) end
local function directionTo(...) return ctx.directionTo(...) end
local function finite(...) return ctx.finite(...) end
local function fireGun(...) return ctx.fireGun(...) end
local function fireMagic(...) return ctx.fireMagic(...) end
local function firePunch(...) return ctx.firePunch(...) end
local function fireSlash(...) return ctx.fireSlash(...) end
local function flatDistance(...) return ctx.flatDistance(...) end
local function gather(...) return ctx.gather(...) end
local function hitInfo(...) return ctx.hitInfo(...) end
local function isBursting(...) return ctx.isBursting(...) end
local function magicLock(...) return ctx.magicLock(...) end
local function manaUpkeep(...) return ctx.manaUpkeep(...) end
local function modsOf(...) return ctx.modsOf(...) end
local function notifyAbility(...) return ctx.notifyAbility(...) end
local function publishAmmo(...) return ctx.publishAmmo(...) end
local function rootOf(...) return ctx.rootOf(...) end
local function setIfChanged(...) return ctx.setIfChanged(...) end
local function singlePetDamage(...) return ctx.singlePetDamage(...) end
local function startReload(...) return ctx.startReload(...) end
local function styleOf(...) return ctx.styleOf(...) end
local function styledStats(...) return ctx.styledStats(...) end

-- ¿Le daría el golpe a alguien? (el automático no ataca al aire)
local function wouldHit(player: Player, root: BasePart, aim: Vector3, stats, style: string): boolean
	local origin = root.Position
	if style == "Magic" then
		return magicLock(player, root, aim, stats.Range) ~= nil
	end
	local dx, dz = directionTo(root, aim)
	local candidates = gather(player, origin, stats.Range)
	if style == "Warrior" then
		local first = StyleConfig.Styles.Warrior.Slashes[1]
		return #AimLogic.arcAll(origin.X, origin.Z, dx, dz, candidates, stats.Range, first.Arc or 70, 1) > 0
	elseif style == "Fists" then
		return AimLogic.inArc(origin.X, origin.Z, dx, dz, candidates, stats.Range, AimLogic.FistArcDegrees) ~= nil
	end
	return #AimLogic.lineHits(origin.X, origin.Z, dx, dz, candidates, stats.Range, AimLogic.Tolerance.Weapons, 1) > 0
end

-- Mantiene al enemigo como objetivo (mascotas y barra de vida) mientras valga
local function validTarget(player: Player, state: State, root: BasePart, now: number): any?
	local target = state.Target
	if not target then
		return nil
	end
	local valid = EnemyService.isAlive(target)
		and EnemyService.canInteract(player, target) -- al entrar o salir de una oleada privada
		and flatDistance(root.Position, target.Root.Position) <= MAX_ENGAGE_RANGE
		and now - state.LastHitAt <= TARGET_MEMORY
	if not valid then
		clearTarget(player, state)
		return nil
	end
	return target
end

-- Al cambiar de estilo: nada a medias del anterior
local function switchStyle(player: Player, state: State, style: string)
	state.Style = style
	state.ChargeStart = nil
	state.PendingCharge = nil
	state.Ads = false
	state.Combo = WarriorLogic.newCombo()
	WarriorLogic.stopBlock(state.Block)
	state.CounterUntil = 0
	player:SetAttribute(Constants.Attributes.Blocking, false)
	if style ~= "Weapons" then
		setIfChanged(player, Constants.Attributes.ReloadEnd, 0)
	end
end

-- Números del ataque del jugador ahora (estilo, clase, partida y Ráfaga)
local function attackStats(player: Player, profile, state: State, style: string, now: number)
	local stats = PlayerDataService.combatStats(profile)
	-- Mejoras de la partida (oleadas): daño y cadencia
	local mods = modsOf(player)
	if mods then
		stats.Shot = stats.Shot * finite(mods.Damage, 1, 0.1, 20)
		stats.Cooldown = math.max(0.05, stats.Cooldown * finite(mods.Cooldown, 1, 0.2, 1))
	end
	-- Estilo de pelea (alcance, ritmo y daño de cada golpe) y el arma de fuego
	stats = styledStats(profile, stats)
	if style == "Weapons" then
		stats = GunLogic.applyStats(stats, stats.WeaponId, state.Ads)
	end
	-- Clase activa del estilo: daño, cadencia y alcance de tus golpes
	local class = ClassLogic.mods(profile.PetData.Classes, style)
	stats.Shot = stats.Shot * class.Damage
	stats.Cooldown = math.max(0.05, stats.Cooldown * class.Cooldown)
	stats.Range = stats.Range * class.Range
	if isBursting(player, now) then
		stats.Cooldown = math.max(0.05, stats.Cooldown * (burstScale[player] or 0.5))
		stats.Shot = stats.Shot * (burstDamage[player] or 1)
	end
	return stats, mods, class
end

function Api.step(now: number)
	for player, state in states do
		local root = rootOf(player)
		local profile = PlayerDataService.get(player)
		-- El maná se recupera siempre (también con otro estilo)
		manaUpkeep(player, state, now)
		if not (root and profile) then
			clearTarget(player, state)
			continue
		end
		local style = styleOf(profile)
		if state.Style ~= style then
			switchStyle(player, state, style)
		end
		local stats, mods, class = attackStats(player, profile, state, style, now)
		local auto = state.AutoFire and MonetizationLogic.autoFire(profile.Passes)
		if player:GetAttribute(Constants.Attributes.AutoFire) ~= auto then
			player:SetAttribute(Constants.Attributes.AutoFire, auto)
		end
		if style == "Weapons" then
			ammoUpkeep(player, state, stats, now)
		end

		-- 1) El ataque, hacia donde apunta: uno por clic, a la cadencia mientras mantiene
		--    pulsado y, con el automático, solo cuando va a dar a alguien
		if state.NextShotAt < now - stats.Cooldown then
			state.NextShotAt = now -- tras una pausa no se acumulan golpes
		end
		local requested = now - state.ShotRequestedAt <= math.max(SHOT_REQUEST_SECONDS, stats.Cooldown) + STEP_SECONDS
		local held = now <= state.HeldUntil
		local aiming = auto and state.AimPoint ~= nil and now - state.AimAt <= AIM_FRESH_SECONDS
		local maxShots = if held or aiming then MAX_SHOTS_PER_STEP elseif requested then 1 else 0
		local busy = (style == "Magic" and state.ChargeStart ~= nil) or (style == "Warrior" and state.Block.Blocking)

		if style == "Magic" and state.PendingCharge then
			-- Orbe cargado soltado: sale ya (y la siguiente bola espera su cadencia)
			local chargeSeconds = math.min(state.PendingCharge, MAX_CHARGE_SECONDS)
			state.PendingCharge = nil
			state.ShotRequestedAt = -math.huge
			local charge = MagicLogic.charged(stats.Shot / math.max(0.05, stats.Cooldown), chargeSeconds)
			-- Sin maná para todo, se carga hasta donde llegue
			local chargeSpec = StyleConfig.Styles.Magic.Charge
			if state.Mana < charge.Cost and state.Mana >= chargeSpec.Cost[1] then
				local fraction = (state.Mana - chargeSpec.Cost[1]) / math.max(1, chargeSpec.Cost[2] - chargeSpec.Cost[1])
				charge = MagicLogic.charged(stats.Shot / math.max(0.05, stats.Cooldown), fraction * chargeSpec.Full)
			end
			fireMagic(player, state, root, aimOf(state, root), stats, mods, class, now, charge)
			state.NextShotAt = math.max(state.NextShotAt, now) + stats.Cooldown
			maxShots = 0
		elseif busy then
			maxShots = 0
		end

		local shots = 0
		while shots < maxShots and now >= state.NextShotAt do
			if style == "Weapons" and (state.ReloadUntil > 0 or state.Ammo <= 0) then
				startReload(player, state, stats, now)
				break -- recargando: el clic no se pierde si termina a tiempo
			end
			local aim = aimOf(state, root)
			if not (requested or held) and not wouldHit(player, root, aim, stats, style) then
				break -- el automático no gasta golpes en el aire
			end
			shots += 1
			state.ShotRequestedAt = -math.huge
			requested = false
			local cooldown = stats.Cooldown
			if style == "Weapons" then
				if not isBursting(player, now) then
					state.Ammo -= 1
				end
				fireGun(player, state, root, aim, stats, mods, class)
				if state.Ammo <= 0 then
					startReload(player, state, stats, now)
				end
				publishAmmo(player, state, stats.Magazine)
			elseif style == "Magic" then
				fireMagic(player, state, root, aim, stats, mods, class, now, nil)
			elseif style == "Warrior" then
				local _, recovery = fireSlash(player, state, root, aim, stats, mods, class, now)
				cooldown = recovery
			else
				firePunch(player, state, root, aim, stats, mods, class)
			end
			state.NextShotAt += cooldown
			-- Disparo doble (mejora de la partida): uno más gratis, hacia el mismo sitio
			local twin = if mods then finite(mods.Twin, 0, 0, 1) else 0
			for _ = 1, MAX_TWIN_SHOTS do
				if twin <= 0 or math.random() >= twin then
					break
				end
				if style == "Weapons" then
					fireGun(player, state, root, aim, stats, mods, class)
				elseif style == "Magic" then
					fireMagic(player, state, root, aim, stats, mods, class, now, nil, true)
				elseif style == "Warrior" then
					fireSlash(player, state, root, aim, stats, mods, class, now)
				else
					firePunch(player, state, root, aim, stats, mods, class)
				end
			end
		end

		-- 2) Objetivo (el último al que le diste): las mascotas lo atacan y se ve su vida
		local target = validTarget(player, state, root, now)
		if not target then
			continue
		end
		if target.Billboard then
			target.Billboard.Enabled = true
		end
		local equipped = PlayerDataService.getEquippedPetIds(profile)
		-- Posición del objetivo para que PetFollower mueva las mascotas alrededor
		if #equipped > 0 then
			player:SetAttribute("PetTargetPos", target.Root.Position)
			player:SetAttribute("PetTargetRadius", target.Radius or 2)
		else
			clearTargetAttributes(player)
		end

		-- Cada mascota equipada golpea periódicamente al objetivo
		for index, petId in equipped do
			if not EnemyService.isAlive(target) then
				break
			end
			local nextAt = state.PetNextHit[index] or 0
			if now >= nextAt then
				state.PetNextHit[index] = now + PET_HIT_INTERVAL + (index - 1) * 0.12
				local damage = singlePetDamage(player, petId)
				local dealt, killed = EnemyService.damage(target, player, damage)
				if dealt > 0 then
					notifyAbility(player, "FoxBolt")
					broadcast(player, root.Position, {
						Kind = "FoxBolt",
						PetId = petId,
						Index = index,
						Target = target.Root.Position,
						Hits = { hitInfo(target, dealt, killed) },
					})
				end
				if killed then
					clearTarget(player, state)
					break
				end
			end
		end
	end
end

local Part = { Api = Api }

function Part.install(context: any)
	ctx = context
	context.attackStats = attackStats
end

function Part.link(context: any)
	AIM_FRESH_SECONDS = context.AIM_FRESH_SECONDS
	MAX_CHARGE_SECONDS = context.MAX_CHARGE_SECONDS
	MAX_ENGAGE_RANGE = context.MAX_ENGAGE_RANGE
	MAX_SHOTS_PER_STEP = context.MAX_SHOTS_PER_STEP
	MAX_TWIN_SHOTS = context.MAX_TWIN_SHOTS
	PET_HIT_INTERVAL = context.PET_HIT_INTERVAL
	SHOT_REQUEST_SECONDS = context.SHOT_REQUEST_SECONDS
	STEP_SECONDS = context.STEP_SECONDS
	TARGET_MEMORY = context.TARGET_MEMORY
	burstDamage = context.burstDamage
	burstScale = context.burstScale
	states = context.states
end

return Part
