-- PetCombatService · Core: constantes, estado de cada jugador, mejoras y clase, puntería y búsqueda del objetivo.
-- Parte de PetCombatService (ver PetCombatService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local WeaponLogic = require(Shared.WeaponLogic)
local StyleLogic = require(Shared.StyleLogic)
local StyleConfig = require(Shared.Config.StyleConfig)
local AimLogic = require(Shared.AimLogic)
local MagicLogic = require(Shared.MagicLogic)
local WarriorLogic = require(Shared.WarriorLogic)
local EnemyService = require(script.Parent.Parent.EnemyService)
local RateLimiter = require(script.Parent.Parent.Parent.Util.RateLimiter)

local ctx: any -- tabla de estado compartida (la crea PetCombatService/init.luau)
local Api = {} -- funciones públicas de esta parte (init.luau las copia a PetCombatService)

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



local states: { [Player]: State } = {}
local abilityListeners: { (Player, string) -> () } = {}
local autoLimiter = RateLimiter.new(0.2, 2, 6)
-- Gancho de las oleadas (WaveService): mejoras de la partida.
-- Gancho de los elementos (AbilityService): marca y combos de cada golpe del bastón.
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
Api.random = function(): number
	return math.random()
end

-- Ráfaga (Armas), Furia (Puños) o Grito de guerra (Guerrero): hasta `untilClock` el tiempo
-- entre golpes se multiplica por `scale` (0.5 = el doble de rápido) y el daño por `damage`.
function Api.setBurst(player: Player, untilClock: number, scale: number?, damage: number?)
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
Api.styledStats = styledStats

function Api.setShotModifier(modifier: (Player) -> any)
	ctx.shotModifier = modifier
end

-- Marca y combos elementales de un golpe del bastón: devuelve el multiplicador del daño.
function Api.setElementHook(hook: (Player, any, string, number, any?) -> number)
	ctx.elementHook = hook
end

local function finite(value: any, default: number, low: number, high: number): number
	if type(value) ~= "number" or value ~= value then
		return default
	end
	return math.clamp(value, low, high)
end

-- Mejoras de la partida de un jugador (nil si no tiene): valores ya limitados.
local function modsOf(player: Player): any?
	if not ctx.shotModifier then
		return nil
	end
	local ok, mods = pcall(ctx.shotModifier, player)
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

function Api.onAbilityHit(listener: (Player, string) -> ())
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

local Part = { Api = Api }

function Part.install(context: any)
	ctx = context
	context.AIM_FRESH_SECONDS = AIM_FRESH_SECONDS
	context.BOSS_CONTROL = BOSS_CONTROL
	context.HOLD_SECONDS = HOLD_SECONDS
	context.MAX_CHARGE_SECONDS = MAX_CHARGE_SECONDS
	context.MAX_EFFECT_TARGETS = MAX_EFFECT_TARGETS
	context.MAX_ENGAGE_RANGE = MAX_ENGAGE_RANGE
	context.MAX_SHOTS_PER_STEP = MAX_SHOTS_PER_STEP
	context.MAX_TWIN_SHOTS = MAX_TWIN_SHOTS
	context.PELLET_TOLERANCE = PELLET_TOLERANCE
	context.PET_HIT_INTERVAL = PET_HIT_INTERVAL
	context.SHOT_REQUEST_SECONDS = SHOT_REQUEST_SECONDS
	context.SLACK_MAX_SPREAD = SLACK_MAX_SPREAD
	context.STEP_SECONDS = STEP_SECONDS
	context.TARGET_MEMORY = TARGET_MEMORY
	context.aimOf = aimOf
	context.autoLimiter = autoLimiter
	context.burstDamage = burstDamage
	context.burstScale = burstScale
	context.burstUntil = burstUntil
	context.directionTo = directionTo
	context.effectWith = effectWith
	context.finite = finite
	context.flatDistance = flatDistance
	context.gather = gather
	context.hideBarIfUntargeted = hideBarIfUntargeted
	context.hitCombos = hitCombos
	context.magicLock = magicLock
	context.modsOf = modsOf
	context.notifyAbility = notifyAbility
	context.oneWayLatency = oneWayLatency
	context.resolveShot = resolveShot
	context.rootOf = rootOf
	context.serverTime = serverTime
	context.setIfChanged = setIfChanged
	context.stateOf = stateOf
	context.states = states
	context.styleOf = styleOf
	context.styledStats = styledStats
end

function Part.link(context: any)
	-- (nada que enlazar)
end

return Part
