-- Ataque del jugador (el único camino de sus golpes básicos) y golpes de sus mascotas. El
-- cliente manda hacia dónde apunta y qué hace (CombatService.onShotRequest); aquí se decide
-- todo, según el estilo de pelea (PetData.Style; StyleLogic):
-- - Armas: disparo con el arma de fuego (GunLogic, WeaponConfig.Guns): pistola, rifle,
--   escopeta (perdigones en abanico), francotirador (atraviesa a varios) o bazuca (cohete que
--   tarda en llegar y explota). Cada bala va hacia el punto apuntado con su desvío (menos
--   apuntando: "AdsOn"/"AdsOff") y da a lo que haya en su camino (AimLogic). Cargador: cada
--   disparo gasta una bala; vacío, recarga solo ("Reload" recarga antes). La Ráfaga no gasta.
-- - Magia (MagicLogic): la bola persigue al bicho más cercano al punto apuntado (LockRadius);
--   gasta maná (sin maná, chispa débil). Mantener ("Charge" → "Release") carga un orbe
--   gigante. El elemento del bastón deja su marca y dispara combos (setElementHook,
--   AbilityService) y tiene su efecto (frena, debilita, cura, salta).
-- - Guerrero (WarriorLogic): combo de 3 tajos a todos los del arco de enfrente (el 3.º,
--   alrededor). Bloquear ("BlockOn"/"BlockOff"): menos daño; la parada perfecta (blockIncoming,
--   desde StyleService) aturde al bicho y el siguiente tajo es un contraataque.
-- - Puños: el más cercano en el arco de enfrente.
-- - Un clic ("Shot") es un golpe (espera a la cadencia si hace falta); mantener pulsado
--   ("Hold") sigue a la cadencia hasta "Release" o HOLD_SECONDS sin aviso.
-- - Con el pase "Disparo automático" y el automático encendido, el cliente manda hacia dónde
--   apunta ("Aim") y se ataca solo a la cadencia, pero solo cuando el golpe va a dar a alguien.
-- - El enemigo al que le das pasa a ser el objetivo: sus mascotas lo atacan y se ve su barra
--   de vida. Se olvida si muere, se aleja más de MAX_ENGAGE_RANGE o llevas TARGET_MEMORY sin
--   darle (ni con el arma ni con una habilidad).
-- - El daño sale del arma, la espada, los guantes o el bastón equipados
--   (PlayerDataService.combatStats) con su efecto (WeaponConfig: área, salto, frenar), la
--   clase activa del estilo (ClassLogic.mods) y las mejoras de la partida de oleadas
--   (setShotModifier, WaveLogic.Mods). Todo se calcula aquí; el cliente solo dibuja
--   (PetAbility "PlayerShot", "ShotImpact", "Parry", "Charging").
-- - Cada mascota equipada golpea al objetivo cada PET_HIT_INTERVAL.
-- Un único bucle para todos los jugadores (STEP_SECONDS); varios golpes por paso si la
-- cadencia es más rápida que el bucle.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local PetConfig = require(Shared.Config.PetConfig)
local PetCombatConfig = require(Shared.Config.PetCombatConfig)
local WeaponLogic = require(Shared.WeaponLogic)
local MonetizationLogic = require(Shared.MonetizationLogic)
local StyleLogic = require(Shared.StyleLogic)
local StyleConfig = require(Shared.Config.StyleConfig)
local ClassLogic = require(Shared.ClassLogic)
local AimLogic = require(Shared.AimLogic)
local GunLogic = require(Shared.GunLogic)
local MagicLogic = require(Shared.MagicLogic)
local WarriorLogic = require(Shared.WarriorLogic)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local EnemyService = require(script.Parent.EnemyService)
local CombatService = require(script.Parent.CombatService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local STEP_SECONDS = 0.1
local MAX_ENGAGE_RANGE = 75 -- el objetivo de las mascotas se deja más lejos que esto
local TARGET_MEMORY = 5 -- segundos sin darle al objetivo antes de olvidarlo
local MAX_SHOTS_PER_STEP = 3
local MAX_EFFECT_TARGETS = 8
local MAX_AIM_CANDIDATES = 24
local PET_HIT_INTERVAL = 0.65
local SHOT_REQUEST_SECONDS = 0.35 -- una petición de disparo caduca (o tras la recarga del arma)
local HOLD_SECONDS = 0.3 -- cada aviso de "mantengo pulsado" dispara durante esto
local AIM_FRESH_SECONDS = 0.6 -- el automático deja de disparar si el cliente deja de apuntar
local FACING_DISTANCE = 40 -- sin punto, se dispara hacia donde mira el personaje
local PELLET_TOLERANCE = 0.8 -- margen de cada perdigón (más fino que una bala)
local SLACK_MAX_SPREAD = 1.5 -- con más desvío no se perdona el fallo (AimLogic.PointSlack)
local BOSS_CONTROL = 0.4 -- los jefes sufren los estados (frenar, raíces, aturdir) menos tiempo
local MAX_CHARGE_SECONDS = 4 -- una carga más larga que esto se trata como la máxima

type State = {
	Target: any?,
	AutoFire: boolean, -- interruptor (solo cuenta con el pase)
	AimPoint: Vector3?, -- último punto al que apuntó
	AimAt: number, -- cuándo llegó
	ShotRequestedAt: number, -- última petición de un disparo sin usar
	HeldUntil: number, -- mantiene pulsado hasta
	LastHitAt: number,
	NextShotAt: number,
	PetNextHit: { [number]: number },
	Generation: number,
	Style: string?, -- estilo del último paso (al cambiar se reinicia lo de cada estilo)
	-- Armas
	Ammo: number,
	AmmoWeapon: string?, -- arma a la que corresponden las balas
	ReloadUntil: number, -- os.clock() del fin de la recarga (0 = no recarga)
	ReloadEnd: number, -- lo mismo en hora del servidor (para el cliente)
	Ads: boolean, -- apuntando (clic derecho)
	-- Magia
	Mana: number,
	ManaAt: number,
	ManaSpentAt: number,
	ChargeStart: number?, -- cargando un orbe desde
	PendingCharge: number?, -- segundos cargados de un orbe soltado (se lanza en el paso)
	-- Guerrero
	Combo: WarriorLogic.ComboState,
	Block: WarriorLogic.BlockState,
	CounterUntil: number, -- hasta cuándo el siguiente tajo es un contraataque
}

local PetCombatService = {}

local states: { [Player]: State } = {}
local abilityRemote: RemoteEvent
local abilityListeners: { (Player, string) -> () } = {}
local autoLimiter = RateLimiter.new(0.2, 2, 6)
-- Gancho de las oleadas (WaveService): mejoras de la partida.
local shotModifier: ((Player) -> any)? = nil
-- Gancho de los elementos (AbilityService): marca y combos de cada golpe del bastón.
local elementHook: ((Player, any, string, number, any?) -> number)? = nil
local CHAIN_DEFAULT = { Range = 14, Fraction = 0.5 } -- salto de la mejora "Rebote" sin arma que salte
local MAX_TWIN_SHOTS = 1
-- Ráfaga (Armas), Furia (Puños) o Grito de guerra (Guerrero): os.clock() hasta el que ataca
-- más rápido (y más fuerte).
local burstUntil: { [Player]: number } = {}
local burstScale: { [Player]: number } = {}
local burstDamage: { [Player]: number } = {}
-- Combo de golpes de cada jugador (StyleLogic.countHit)
local hitCombos: { [Player]: { Count: number, Last: number } } = {}
-- Azar de los críticos y del desvío (las pruebas lo sustituyen para que sea determinista).
PetCombatService.random = function(): number
	return math.random()
end

-- Ráfaga (Armas), Furia (Puños) o Grito de guerra (Guerrero): hasta `untilClock` el tiempo
-- entre golpes se multiplica por `scale` (0.5 = el doble de rápido) y el daño por `damage`.
function PetCombatService.setBurst(player: Player, untilClock: number, scale: number?, damage: number?)
	burstUntil[player] = untilClock
	burstScale[player] = if type(scale) == "number" and scale > 0 and scale <= 1 then scale else 0.5
	burstDamage[player] = if type(damage) == "number" and damage >= 1 and damage <= 3 then damage else 1
end

-- Estilo de pelea del perfil (uno válido siempre).
local function styleOf(profile): string
	return StyleLogic.sanitize(profile.PetData.Style)
end

-- Números del golpe con el estilo: Guerrero, Puños y Magia salen del DPS de lo equipado.
local function styledStats(profile, stats)
	local def = WeaponLogic.definition(stats.WeaponId)
	return StyleLogic.applyStats(stats, styleOf(profile), def and def.Cooldown)
end
PetCombatService.styledStats = styledStats

function PetCombatService.setShotModifier(modifier: (Player) -> any)
	shotModifier = modifier
end

-- Marca y combos elementales de un golpe del bastón: devuelve el multiplicador del daño.
function PetCombatService.setElementHook(hook: (Player, any, string, number, any?) -> number)
	elementHook = hook
end

local function finite(value: any, default: number, low: number, high: number): number
	if type(value) ~= "number" or value ~= value then
		return default
	end
	return math.clamp(value, low, high)
end

-- Mejoras de la partida de un jugador (nil si no tiene): valores ya limitados.
local function modsOf(player: Player): any?
	if not shotModifier then
		return nil
	end
	local ok, mods = pcall(shotModifier, player)
	if not ok or type(mods) ~= "table" then
		return nil
	end
	return mods
end

-- Efecto del arma con las mejoras de la partida encima (sin tocar WeaponConfig).
local function effectWith(effect, mods)
	if not mods then
		return effect
	end
	local result = table.clone(effect)
	local extraChain = math.floor(finite(mods.Chain, 0, 0, 6))
	if extraChain > 0 then
		local base = effect.Chain
		result.Chain = {
			Count = (if base then base.Count else 0) + extraChain,
			Range = if base then base.Range else CHAIN_DEFAULT.Range,
			Fraction = if base then base.Fraction else CHAIN_DEFAULT.Fraction,
		}
	end
	local splash = mods.Splash
	if type(splash) == "table" then
		local radius = finite(splash.Radius, 0, 0, 20)
		local fraction = finite(splash.Fraction, 0, 0, 1)
		if radius > 0 and fraction > 0 then
			local base = effect.Splash
			result.Splash = {
				Radius = math.max(radius, if base then base.Radius else 0),
				Fraction = math.max(fraction, if base then base.Fraction else 0),
			}
		end
	end
	return result
end

function PetCombatService.onAbilityHit(listener: (Player, string) -> ())
	table.insert(abilityListeners, listener)
end

local function notifyAbility(player: Player, kind: string)
	for _, listener in abilityListeners do
		task.spawn(listener, player, kind)
	end
end

local function isTargetedByAnyone(enemy: any): boolean
	for _, state in states do
		if state.Target == enemy then
			return true
		end
	end
	return false
end

local function hideBarIfUntargeted(enemy: any)
	if enemy and enemy.Billboard and not isTargetedByAnyone(enemy) then
		enemy.Billboard.Enabled = false
	end
end

local function stateOf(player: Player): State
	local state = states[player]
	if not state then
		state = {
			Target = nil,
			AutoFire = true,
			AimPoint = nil,
			AimAt = -math.huge,
			ShotRequestedAt = -math.huge,
			HeldUntil = -math.huge,
			LastHitAt = -math.huge,
			NextShotAt = 0,
			PetNextHit = {},
			Generation = 0,
			Style = nil,
			Ammo = 0,
			AmmoWeapon = nil,
			ReloadUntil = 0,
			ReloadEnd = 0,
			Ads = false,
			Mana = MagicLogic.maxMana(),
			ManaAt = os.clock(),
			ManaSpentAt = -math.huge,
			ChargeStart = nil,
			PendingCharge = nil,
			Combo = WarriorLogic.newCombo(),
			Block = WarriorLogic.newBlock(),
			CounterUntil = 0,
		}
		states[player] = state
		player:SetAttribute(Constants.Attributes.AutoFire, false)
	end
	return state
end

-- Lo que tarda en llegar un aviso del jugador (la mitad de su ping), como mucho 0.15 s
local function oneWayLatency(player: Player): number
	local ok, ping = pcall(function()
		return (player :: any):GetNetworkPing()
	end)
	if ok and type(ping) == "number" and ping == ping then
		return math.clamp(ping / 2, 0, 0.15)
	end
	return 0
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root
	end
	return nil
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function setIfChanged(player: Player, name: string, value: any)
	if player:GetAttribute(name) ~= value then
		player:SetAttribute(name, value)
	end
end

local function serverTime(clockTime: number): number
	return Workspace:GetServerTimeNow() + (clockTime - os.clock())
end

-- Hacia donde mira el personaje (en plano); hacia -Z si no se sabe
local function facingOf(root: BasePart): (number, number)
	local cframe = (root :: any).CFrame
	local look = cframe and cframe.LookVector
	if look then
		local length = math.sqrt(look.X * look.X + look.Z * look.Z)
		if length > 0.05 then
			return look.X / length, look.Z / length
		end
	end
	return 0, -1
end

-- Punto hacia el que ataca: el último que mandó el cliente o, sin él, delante de él
local function aimOf(state: State, root: BasePart): Vector3
	if state.AimPoint then
		return state.AimPoint
	end
	local dx, dz = facingOf(root)
	local origin = root.Position
	return Vector3.new(origin.X + dx * FACING_DISTANCE, origin.Y, origin.Z + dz * FACING_DISTANCE)
end

-- Dirección plana hacia el punto apuntado (o hacia donde mira si está encima)
local function directionTo(root: BasePart, aim: Vector3): (number, number)
	local origin = root.Position
	local dx, dz = AimLogic.direction(origin.X, origin.Z, aim.X, aim.Z)
	if dx and dz then
		return dx, dz
	end
	return facingOf(root)
end

-- Enemigos a tiro con los que puede pelear (sin atravesar suelos: findInRadius mira la
-- altura): la lista para AimLogic y cada uno por su Id.
local function gather(player: Player, origin: Vector3, range: number): ({ AimLogic.Candidate }, { [any]: any })
	local byId = {}
	local candidates = {}
	for _, enemy in EnemyService.findInRadius(origin, range, MAX_AIM_CANDIDATES, player) do
		if EnemyService.canInteract(player, enemy) then
			byId[enemy.Id] = enemy
			local position = enemy.Root.Position
			table.insert(candidates, { Id = enemy.Id, X = position.X, Z = position.Z, Radius = enemy.Radius or 1 })
		end
	end
	return candidates, byId
end

-- Puños: a quién da un golpe hacia `aim` (AimLogic) y dónde acaba: en el enemigo o, si
-- falla, un poco delante.
local function resolveShot(player: Player, root: BasePart, aim: Vector3, range: number, style: string): (any?, Vector3)
	local origin = root.Position
	local dx, dz = directionTo(root, aim)
	local candidates, byId = gather(player, origin, range)
	local id = AimLogic.pick(style, origin.X, origin.Z, dx, dz, aim.X, aim.Z, candidates, range)
	local enemy = if id ~= nil then byId[id] else nil
	if enemy then
		return enemy, enemy.Root.Position
	end
	local distance = AimLogic.missDistance(style, flatDistance(origin, aim), range)
	return nil, Vector3.new(origin.X + dx * distance, origin.Y, origin.Z + dz * distance)
end

-- Magia: el bicho al que persigue la bola (el más cercano al punto apuntado o, si no, el
-- primero en la línea), o nil.
local function magicLock(player: Player, root: BasePart, aim: Vector3, range: number): any?
	local origin = root.Position
	local dx, dz = directionTo(root, aim)
	local candidates, byId = gather(player, origin, range)
	local lockRadius = StyleConfig.Styles.Magic.LockRadius or 12
	local id = AimLogic.nearPoint(origin.X, origin.Z, aim.X, aim.Z, candidates, range, lockRadius)
	if id == nil then
		id = AimLogic.alongLine(origin.X, origin.Z, dx, dz, candidates, range, AimLogic.Tolerance.Magic)
	end
	return if id ~= nil then byId[id] else nil
end

local function broadcast(owner: Player, origin: Vector3, event: { [string]: any })
	event.Owner = owner
	for _, player in Players:GetPlayers() do
		local root = if player == owner then nil else rootOf(player)
		if player == owner or (root and (root.Position - origin).Magnitude <= PetCombatConfig.BroadcastRange) then
			abilityRemote:FireClient(player, event)
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
		if not spark and elementHook then
			-- Fuego: además quema (una parte del golpe cada segundo)
			local burn = if elementSpec.Burn then { Tick = amount * elementSpec.Burn, Seconds = elementSpec.BurnSeconds or 3 } else nil
			local ok, multiplier = pcall(elementHook, player, target, element, amount, burn)
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
			EnemyService.knockback(target, root.Position, combo.Knockback)
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

function PetCombatService.step(now: number)
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

-- Para StyleService ------------------------------------------------------------------------

-- Cargador y maná llenos y listo para atacar (pruebas y regalos)
function PetCombatService.refill(player: Player)
	local state = states[player]
	if state then
		state.AmmoWeapon = nil
		state.ReloadUntil = 0
		state.Mana = MagicLogic.maxMana()
		state.NextShotAt = 0
	end
end

-- Marca y combos elementales de un golpe (habilidades de Magia): el multiplicador del daño
function PetCombatService.elementHit(player: Player, enemy: any, element: string, amount: number): number
	if not elementHook then
		return 1
	end
	local ok, multiplier = pcall(elementHook, player, enemy, element, amount)
	return if ok and type(multiplier) == "number" and multiplier == multiplier then math.clamp(multiplier, 0, 4) else 1
end

-- Maná que tiene ahora el jugador
function PetCombatService.mana(player: Player): number
	local state = states[player]
	return if state then state.Mana else MagicLogic.maxMana()
end

-- Gasta maná (habilidades, teletransporte). false si no le llega.
function PetCombatService.spendMana(player: Player, cost: number): boolean
	return spendMana(player, stateOf(player), cost, os.clock())
end

-- Le pegan al jugador (EnemyService, por StyleService): la parte del daño que recibe al
-- bloquear con el Guerrero. Con una parada perfecta no recibe nada, aturde a `enemy` y su
-- siguiente tajo es un contraataque.
function PetCombatService.blockIncoming(player: Player, enemy: any?): number
	local state = states[player]
	if not (state and state.Style == "Warrior") then
		return 1
	end
	local now = os.clock()
	local factor, parried = WarriorLogic.incoming(state.Block, now)
	if factor < 1 and not parried then
		-- Bloqueado (sin parada): chispas en la espada
		local root = rootOf(player)
		if root then
			local at = root.Position
			if enemy and enemy.Root then
				-- Un poco hacia el bicho (donde choca la espada)
				local dx, dz = enemy.Root.Position.X - at.X, enemy.Root.Position.Z - at.Z
				local length = math.sqrt(dx * dx + dz * dz)
				if length > 0.1 then
					at = Vector3.new(at.X + dx / length * 1.5, at.Y, at.Z + dz / length * 1.5)
				end
			end
			broadcast(player, at, { Kind = "Blocked", Position = at })
		end
	end
	if parried then
		local spec = StyleConfig.Styles.Warrior.Block
		state.CounterUntil = now + spec.CounterSeconds
		local root = rootOf(player)
		if enemy and EnemyService.isAlive(enemy) then
			control(enemy, "Stun", spec.Stun)
		end
		local at = if enemy and enemy.Root then enemy.Root.Position elseif root then root.Position else nil
		if at then
			broadcast(player, at, { Kind = "Parry", Position = at })
		end
	end
	return factor
end

function PetCombatService.start()
	abilityRemote = RemoteService.get(Constants.Remotes.PetAbility)

	-- Golpe de una habilidad (CombatService.reportHit): pasa a ser el objetivo
	CombatService.onPlayerHit(function(player: Player, enemy: any)
		if EnemyService.isAlive(enemy) and EnemyService.canInteract(player, enemy) then
			setTarget(stateOf(player), enemy)
		end
	end)
	-- Hacia dónde apunta (punto ya validado por CombatService) y qué pide: "Shot" un golpe,
	-- "Hold" sigue mientras llegue, "Release" ha soltado (y suelta el orbe que cargaba), "Aim"
	-- solo apunta (para el automático), "Charge" empieza a cargar un orbe (Magia), "Reload"
	-- recarga (Armas), "AdsOn"/"AdsOff" apunta con el clic derecho (Armas) y
	-- "BlockOn"/"BlockOff" bloquea (Guerrero).
	CombatService.onShotRequest(function(player: Player, aim: Vector3, mode: string)
		local state = stateOf(player)
		local now = os.clock()
		local style = state.Style
		if mode == "Release" then
			state.HeldUntil = -math.huge
			if state.ChargeStart then
				state.PendingCharge = now - state.ChargeStart
				state.ChargeStart = nil
				state.AimPoint = aim
				state.AimAt = now
			end
			return
		elseif mode == "Reload" then
			local profile = PlayerDataService.get(player)
			if profile and style == "Weapons" then
				local stats = attackStats(player, profile, state, style, now)
				ammoUpkeep(player, state, stats, now)
				startReload(player, state, stats, now)
			end
			return
		elseif mode == "AdsOn" or mode == "AdsOff" then
			state.Ads = mode == "AdsOn" and style == "Weapons"
			return
		elseif mode == "BlockOn" then
			if style == "Warrior" then
				-- Cuenta desde que lo pulsó (sin el viaje del aviso): la parada es justa con lag
				WarriorLogic.startBlock(state.Block, now - oneWayLatency(player))
				state.HeldUntil = -math.huge
				player:SetAttribute(Constants.Attributes.Blocking, true)
			end
			return
		elseif mode == "BlockOff" then
			WarriorLogic.stopBlock(state.Block)
			player:SetAttribute(Constants.Attributes.Blocking, false)
			return
		end
		state.AimPoint = aim
		state.AimAt = now
		if mode == "Charge" then
			if style == "Magic" and not state.ChargeStart then
				local spec = StyleConfig.Styles.Magic.Charge
				state.ChargeStart = now - spec.MinHold
				state.HeldUntil = -math.huge
				local root = rootOf(player)
				if root then
					broadcast(player, root.Position, { Kind = "Charging", Element = MagicLogic.element(player:GetAttribute(Constants.Attributes.EquippedWeapon)) })
				end
			end
		elseif mode == "Hold" then
			state.HeldUntil = now + HOLD_SECONDS
		elseif mode ~= "Aim" then
			state.ShotRequestedAt = now
		end
	end)
	-- Clic en el cuerpo de un enemigo (ClickDetector): sus mascotas lo atacan
	EnemyService.onClicked(function(player: Player, enemy: any)
		if not EnemyService.canInteract(player, enemy) then
			return
		end
		setTarget(stateOf(player), enemy)
	end)
	-- Guerrero · Sed de batalla: cada bicho que derrota le cura
	if EnemyService.onDefeated then
		EnemyService.onDefeated(function(player: Player)
			local state = states[player]
			local passive = StyleConfig.Styles.Warrior.Passive
			if state and state.Style == "Warrior" and passive.KillHeal then
				local maxHealth = maxHealthOf(player)
				if maxHealth then
					heal(player, maxHealth * passive.KillHeal)
				end
			end
		end)
	end
	-- Insignia AUTO (o V): enciende o apaga el disparo automático, solo con el pase
	RemoteService.get(Constants.Remotes.SetAutoFire).OnServerEvent:Connect(function(player: Player, enabled: any)
		if typeof(enabled) ~= "boolean" or autoLimiter:check(player) ~= "ok" then
			return
		end
		local profile = PlayerDataService.get(player)
		if not (profile and MonetizationLogic.autoFire(profile.Passes)) then
			return
		end
		local state = stateOf(player)
		state.AutoFire = enabled
		player:SetAttribute(Constants.Attributes.AutoFire, enabled)
	end)

	local function watch(player: Player)
		stateOf(player)
		player.CharacterRemoving:Connect(function()
			reset(player)
		end)
		player:GetAttributeChangedSignal(Constants.Attributes.CurrentZone):Connect(function()
			reset(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		reset(player)
		states[player] = nil
		burstUntil[player] = nil
		burstScale[player] = nil
		burstDamage[player] = nil
		hitCombos[player] = nil
		autoLimiter:remove(player)
	end)

	task.spawn(function()
		while true do
			task.wait(STEP_SECONDS)
			local ok, err = pcall(PetCombatService.step, os.clock())
			if not ok then
				warn("[PetCombatService] " .. tostring(err))
			end
		end
	end)
end

return PetCombatService
