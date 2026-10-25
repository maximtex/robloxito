-- Habilidades elementales (AbilityConfig). Los núcleos elegidos dan su habilidad:
-- - El cliente solo pide "usar la habilidad" de un hueco (UseAbility("Primary" | "Secondary")).
--   El servidor comprueba el ritmo, que el personaje esté vivo, el elemento de ese hueco
--   (principal: el seleccionado si está despierto, si no Naturaleza; secundario: solo si
--   hay uno válido), su recarga y la recarga global entre habilidades.
-- - Objetivos desde la posición y orientación REALES del personaje (como el ataque), daño
--   con AbilityLogic sobre el poder del arma equipada y la maestría del núcleo, y todo pasa
--   por EnemyService.damage: mismas muertes y recompensas (una vez por vida).
-- - Estados sobre los enemigos con EnemyService.applyControl (los jefes resisten).
-- - Recarga por ELEMENTO (cambiarlo de hueco o morir no la reinicia) y recarga global
--   corta entre dos habilidades. Las habilidades con objetivo no se gastan si no hay
--   ningún enemigo delante.
-- - Combos: cada impacto mira la marca elemental del enemigo (EnemyService.auraOf); si la
--   pareja tiene reacción (AbilityLogic.reaction) se consume y se dispara el combo después
--   del impacto; si no, deja la marca de su elemento. Los daños de los combos no disparan
--   otros combos. Algunos impactos empujan (Knockback; nunca a los jefes).
-- - Quemaduras y oleadas pendientes en UN bucle del servidor; al morir o cambiar de zona
--   se anulan las oleadas pendientes de ese jugador.
-- - Efectos: AbilityEvent al jugador y a los cercanos (solo acciones ya resueltas) y
--   AbilityResult solo al que la usó (con la hora a la que vuelve a estar lista).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local CoreConfig = require(Shared.Config.CoreConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local AbilityLogic = require(Shared.AbilityLogic)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local EnemyService = require(script.Parent.EnemyService)
local CombatService = require(script.Parent.CombatService)
local CoreLogic = require(script.Parent.Parent.Util.CoreLogic)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local Codes = Constants.PurchaseCodes
local TICK_SECONDS = 0.1
local MAX_POOL = 24 -- enemigos que se consideran para los saltos del rayo
local MAX_REACTION_TARGETS = 8
local SLOTS = { Primary = true, Secondary = true }

type State = {
	ReadyAt: { [string]: number }, -- por elemento: os.clock() a partir del cual está lista
	LastCastAt: number, -- última habilidad (recarga global)
	Generation: number, -- cambia al morir o cambiar de zona: anula oleadas pendientes
	HasteToken: number, -- cada Vendaval nuevo invalida el final del anterior
}

type Burn = {
	Enemy: any,
	Player: Player,
	EnemyGeneration: number, -- si el enemigo muere o reaparece, la quemadura se acaba
	Damage: number,
	Interval: number,
	NextTick: number,
	TicksLeft: number,
}

-- Contexto de un uso: acumula impactos y avisa a las mascotas una sola vez.
type Context = {
	Player: Player,
	State: State,
	Ability: any,
	ElementId: string,
	Level: number,
	Base: number, -- daño del jugador en este momento
	Root: BasePart,
	Humanoid: Humanoid,
	Hits: { any },
	Engaged: boolean,
	Reactions: { any }, -- combos disparados en este uso (se resuelven después)
	NoReactions: boolean?, -- daño de un combo: no dispara más combos
}

local AbilityService = {}

local states: { [Player]: State } = {}
local burns: { Burn } = {}
local eventRemote: RemoteEvent
local resultRemote: RemoteEvent
local useLimiter = RateLimiter.new(0.2, 3, 10)

local function stateOf(player: Player): State
	local state = states[player]
	if not state then
		state = { ReadyAt = {}, LastCastAt = -math.huge, Generation = 0, HasteToken = 0 }
		states[player] = state
	end
	return state
end

local function characterOf(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil, nil
end

-- Hora del servidor equivalente a un instante de os.clock() (para la interfaz).
local function serverTime(clockTime: number): number
	return Workspace:GetServerTimeNow() + (clockTime - os.clock())
end

-- Elemento de un hueco. Principal: el seleccionado si está despierto; si no, Naturaleza.
-- Secundario: el elegido si es válido (desbloqueado y distinto del principal); si no, nil.
function AbilityService.elementOf(profile: any, slot: string?): string?
	local cores = profile.PetData and profile.PetData.Cores
	local ready = cores ~= nil and PlayerDataService.isPetDataReady(profile)
	if slot == "Secondary" then
		local secondary = if ready then CoreLogic.secondaryOf(cores) else nil
		return if secondary and AbilityLogic.get(secondary) then secondary else nil
	end
	if ready then
		local selected = cores.Selected
		if AbilityLogic.get(selected) and CoreLogic.isUnlocked(cores, selected) then
			return selected
		end
	end
	return CoreConfig.DefaultElement
end

-- Efectos: al dueño y a los jugadores cercanos.
local function broadcast(owner: Player, origin: Vector3, event: { [string]: any })
	event.Owner = owner
	for _, player in Players:GetPlayers() do
		local root = if player == owner then nil else characterOf(player)
		if player == owner or (root and (root.Position - origin).Magnitude <= AbilityConfig.BroadcastRange) then
			eventRemote:FireClient(player, event)
		end
	end
end

-- Efecto de un uso: lleva el elemento que lo lanza (el cliente elige sonido y colores).
local function emit(ctx: Context, origin: Vector3, event: { [string]: any })
	event.Element = ctx.ElementId
	broadcast(ctx.Player, origin, event)
end

local function damageOf(ctx: Context, ratio: number): number
	return AbilityLogic.damage(ctx.ElementId, ratio, ctx.Base, ctx.Level)
end

-- Daño a un enemigo. Antes mira su marca elemental: combo (se consume y se resuelve
-- después) o marca nueva. Guarda el impacto para los efectos, empuja si la habilidad lo
-- hace y, con el primero que sobrevive, avisa a CombatService para que las mascotas se unan.
local function hit(ctx: Context, enemy: any, amount: number, knockbackFrom: Vector3?, knockback: number?): (number, boolean)
	local position = enemy.Root.Position
	local reactionId = nil
	if not ctx.NoReactions then
		local aura = EnemyService.auraOf(enemy)
		reactionId = AbilityLogic.reaction(aura, ctx.ElementId)
		if reactionId then
			amount *= AbilityConfig.Reactions[reactionId].Multiplier or 1
			EnemyService.setAura(enemy, nil)
			table.insert(ctx.Reactions, { Id = reactionId, Enemy = enemy, Position = position, Aura = aura })
		elseif AbilityLogic.leavesAura(ctx.ElementId) then
			EnemyService.setAura(enemy, ctx.ElementId, AbilityConfig.Aura.Seconds)
		end
	end
	local dealt, killed = EnemyService.damage(enemy, ctx.Player, amount)
	if dealt > 0 then
		table.insert(ctx.Hits, { Position = position, Damage = dealt, Killed = killed, Kind = enemy.Kind, Model = enemy.Model, Reaction = reactionId })
		if not killed then
			local force = knockback or ctx.Ability.Knockback
			if force and force > 0 then
				EnemyService.knockback(enemy, knockbackFrom or ctx.Root.Position, force)
			end
			if not ctx.Engaged then
				ctx.Engaged = true
				CombatService.reportHit(ctx.Player, enemy)
			end
		end
	end
	return dealt, killed
end

-- Estado de control ajustado si el objetivo es un jefe.
local function control(enemy: any, kind: string, seconds: number, factor: number?): boolean
	local duration, strength = AbilityLogic.control(kind, seconds, factor, enemy.Kind == "Boss")
	return EnemyService.applyControl(enemy, kind, duration, if kind == "Slow" then strength else nil)
end

local function flatLook(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function addBurn(player: Player, enemy: any, damage: number, ability: any)
	local now = os.clock()
	local ticks = AbilityLogic.burnTicks(ability)
	for _, burn in burns do
		if burn.Enemy == enemy and burn.Player == player then
			-- Reaplicar renueva la quemadura (no se acumulan dos del mismo jugador).
			burn.EnemyGeneration = enemy.Generation
			burn.Damage = math.max(burn.Damage, damage)
			burn.TicksLeft = ticks
			return
		end
	end
	table.insert(burns, {
		Enemy = enemy,
		Player = player,
		EnemyGeneration = enemy.Generation,
		Damage = damage,
		Interval = ability.BurnTickSeconds,
		NextTick = now + ability.BurnTickSeconds,
		TicksLeft = ticks,
	})
end

-- Velocidad normal del personaje: la de StarterPlayer, o la que fija AdventureService
-- con la Pluma del Viento (atributo BaseWalkSpeed del Humanoid).
local function baseWalkSpeed(humanoid: Humanoid): number
	local value = humanoid:GetAttribute("BaseWalkSpeed")
	if typeof(value) == "number" and value == value and value > 0 and value < 100 then
		return value
	end
	return StarterPlayer.CharacterWalkSpeed
end

local function haste(player: Player, state: State, humanoid: Humanoid, bonus: number, seconds: number)
	local base = baseWalkSpeed(humanoid)
	humanoid.WalkSpeed = base * (1 + bonus)
	state.HasteToken += 1
	local token = state.HasteToken
	task.delay(seconds, function()
		if state.HasteToken == token and humanoid.Parent then
			humanoid.WalkSpeed = base
		end
	end)
end

local function healPlayer(target: Player, humanoid: Humanoid, fraction: number, healed: { any })
	local before = humanoid.Health
	humanoid.Health = math.min(humanoid.MaxHealth, before + humanoid.MaxHealth * fraction)
	table.insert(healed, { Player = target, Amount = math.floor(humanoid.Health - before + 0.5) })
end

-- Combos ---------------------------------------------------------------------------------

-- Efecto de la marca esparcida por el Remolino del Viento (la de su elemento original).
local function spreadAura(ctx: Context, enemy: any, aura: string)
	EnemyService.setAura(enemy, aura, AbilityConfig.Aura.Seconds)
	local source = AbilityConfig.Abilities[aura]
	if aura == "Fire" then
		addBurn(ctx.Player, enemy, damageOf(ctx, source.BurnRatioPerTick), source)
		EnemyService.markStatus(enemy, "Burn", source.BurnSeconds)
	elseif aura == "Ice" then
		control(enemy, "Slow", source.SlowSeconds, source.SlowFactor)
	elseif aura == "Lightning" then
		control(enemy, "Stun", source.StunSeconds)
	end
end

local function applyReaction(ctx: Context, entry: any)
	local reaction = AbilityConfig.Reactions[entry.Id]
	local enemy, center = entry.Enemy, entry.Position
	-- Los daños del combo no disparan más combos ni ponen marcas.
	local burst: Context = table.clone(ctx)
	burst.Hits = {}
	burst.Reactions = {}
	burst.NoReactions = true
	local radius = reaction.Radius or 0
	local around = if radius > 0 then EnemyService.findInRadius(center, radius, MAX_REACTION_TARGETS, ctx.Player) else {}
	if reaction.BurstRatio then
		local amount = damageOf(ctx, reaction.BurstRatio)
		for _, other in around do
			hit(burst, other, amount, center, reaction.Knockback or 0)
		end
	end
	if reaction.StunSeconds and EnemyService.isAlive(enemy) then
		control(enemy, "Stun", reaction.StunSeconds)
	end
	if reaction.RootSeconds and EnemyService.isAlive(enemy) then
		control(enemy, "Root", reaction.RootSeconds)
	end
	if reaction.VulnerableBonus then
		for _, other in (if #around > 0 then around else { enemy }) do
			EnemyService.applyControl(other, "Vulnerable", reaction.VulnerableSeconds, reaction.VulnerableBonus)
		end
	end
	if reaction.BurnMultiplier then
		local fire = AbilityConfig.Abilities.Fire
		local tick = damageOf(ctx, fire.BurnRatioPerTick * reaction.BurnMultiplier)
		for _, other in (if #around > 0 then around else { enemy }) do
			if EnemyService.isAlive(other) then
				addBurn(ctx.Player, other, tick, fire)
				EnemyService.markStatus(other, "Burn", fire.BurnSeconds)
			end
		end
	end
	if reaction.Trigger and type(entry.Aura) == "string" then
		for _, other in around do
			if EnemyService.isAlive(other) then
				spreadAura(ctx, other, entry.Aura)
			end
		end
	end
	local healed = {}
	if reaction.HealFraction then
		local root, humanoid = characterOf(ctx.Player)
		if root and humanoid then
			healPlayer(ctx.Player, humanoid, reaction.HealFraction, healed)
		end
	end
	emit(ctx, center, { Kind = "Reaction", Reaction = entry.Id, Center = center, Radius = radius, Aura = entry.Aura, Healed = healed, Hits = burst.Hits })
end

-- Resuelve los combos pendientes de un uso (después de todos sus impactos).
local function runReactions(ctx: Context)
	local pending = ctx.Reactions
	ctx.Reactions = {}
	for _, entry in pending do
		applyReaction(ctx, entry)
	end
end

-- Ejecutores por tipo. Devuelven false si no hay objetivo (no se gasta la recarga).
local EXECUTE: { [string]: (Context) -> boolean } = {}

function EXECUTE.Roots(ctx: Context): boolean
	local ability = ctx.Ability
	local center = ctx.Root.Position
	for _, enemy in EnemyService.findInRadius(center, ability.Radius, ability.MaxTargets, ctx.Player) do
		local _, killed = hit(ctx, enemy, damageOf(ctx, ability.DamageRatio))
		if not killed then
			control(enemy, "Root", ability.RootSeconds)
		end
	end
	emit(ctx, center, { Kind = "Roots", Center = center, Radius = ability.Radius, Seconds = ability.RootSeconds, Hits = ctx.Hits })
	return true
end

function EXECUTE.Heal(ctx: Context): boolean
	local ability = ctx.Ability
	local center = ctx.Root.Position
	local healed = {}
	healPlayer(ctx.Player, ctx.Humanoid, ability.HealFraction, healed)
	for _, other in Players:GetPlayers() do
		if other ~= ctx.Player then
			local root, humanoid = characterOf(other)
			if root and humanoid and (root.Position - center).Magnitude <= ability.AllyRadius then
				healPlayer(other, humanoid, ability.AllyHealFraction, healed)
			end
		end
	end
	for _, enemy in EnemyService.findInRadius(center, ability.Radius, ability.MaxTargets, ctx.Player) do
		hit(ctx, enemy, damageOf(ctx, ability.DamageRatio))
	end
	emit(ctx, center, { Kind = "Heal", Center = center, Radius = ability.Radius, AllyRadius = ability.AllyRadius, Healed = healed, Hits = ctx.Hits })
	return true
end

function EXECUTE.Burn(ctx: Context): boolean
	local ability = ctx.Ability
	local origin, look = ctx.Root.Position, flatLook(ctx.Root)
	local tick = damageOf(ctx, ability.BurnRatioPerTick)
	for _, enemy in EnemyService.findTargets(origin, look, ability.Range, ability.ArcDot, ability.MaxTargets, ctx.Player) do
		local _, killed = hit(ctx, enemy, damageOf(ctx, ability.DamageRatio))
		if not killed then
			addBurn(ctx.Player, enemy, tick, ability)
			EnemyService.markStatus(enemy, "Burn", ability.BurnSeconds)
		end
	end
	emit(ctx, origin, { Kind = "Burn", Origin = origin, Look = look, Range = ability.Range, Hits = ctx.Hits })
	return true
end

function EXECUTE.Gust(ctx: Context): boolean
	local ability = ctx.Ability
	local origin, look = ctx.Root.Position, flatLook(ctx.Root)
	for _, enemy in EnemyService.findTargets(origin, look, ability.Range, ability.ArcDot, ability.MaxTargets, ctx.Player) do
		hit(ctx, enemy, damageOf(ctx, ability.DamageRatio))
	end
	haste(ctx.Player, ctx.State, ctx.Humanoid, ability.HasteBonus, ability.HasteSeconds)
	emit(ctx, origin, { Kind = "Gust", Origin = origin, Look = look, Range = ability.Range, HasteSeconds = ability.HasteSeconds, Hits = ctx.Hits })
	return true
end

function EXECUTE.Chain(ctx: Context): boolean
	local ability = ctx.Ability
	local origin, look = ctx.Root.Position, flatLook(ctx.Root)
	local first = EnemyService.findTargets(origin, look, ability.Range, ability.ArcDot, 1, ctx.Player)[1]
	if not first then
		return false
	end
	-- Candidatos para los saltos: los vivos alrededor del primero.
	local byId = { [first.Id] = first }
	local candidates = { { Id = first.Id, X = first.Root.Position.X, Z = first.Root.Position.Z, Radius = first.Radius, Alive = true } }
	for _, enemy in EnemyService.findInRadius(first.Root.Position, ability.JumpRange * ability.Jumps, MAX_POOL, ctx.Player) do
		if not byId[enemy.Id] then
			byId[enemy.Id] = enemy
			table.insert(candidates, { Id = enemy.Id, X = enemy.Root.Position.X, Z = enemy.Root.Position.Z, Radius = enemy.Radius, Alive = true })
		end
	end
	local order = AbilityLogic.chainOrder(candidates, first.Id, ability.JumpRange, ability.Jumps)
	local damages = AbilityLogic.chainDamages(damageOf(ctx, ability.DamageRatio), ability.Jumps, ability.JumpFalloff)
	local points = { origin + Vector3.new(0, 1.5, 0) }
	for index, id in order do
		local enemy = byId[id]
		table.insert(points, enemy.Root.Position)
		local _, killed = hit(ctx, enemy, damages[index])
		if not killed then
			control(enemy, "Stun", ability.StunSeconds)
		end
	end
	emit(ctx, origin, { Kind = "Chain", Points = points, Hits = ctx.Hits })
	return true
end

function EXECUTE.Frost(ctx: Context): boolean
	local ability = ctx.Ability
	local center = ctx.Root.Position
	for _, enemy in EnemyService.findInRadius(center, ability.Radius, ability.MaxTargets, ctx.Player) do
		local _, killed = hit(ctx, enemy, damageOf(ctx, ability.DamageRatio))
		if not killed then
			control(enemy, "Slow", ability.SlowSeconds, ability.SlowFactor)
		end
	end
	emit(ctx, center, { Kind = "Frost", Center = center, Radius = ability.Radius, Seconds = ability.SlowSeconds, Hits = ctx.Hits })
	return true
end

function EXECUTE.Curse(ctx: Context): boolean
	local ability = ctx.Ability
	local origin, look = ctx.Root.Position, flatLook(ctx.Root)
	local primary = EnemyService.findTargets(origin, look, ability.Range, ability.ArcDot, 1, ctx.Player)[1]
	if not primary then
		return false
	end
	local center = primary.Root.Position
	-- Primero el golpe (sin el bonus de su propia marca) y después la marca.
	hit(ctx, primary, damageOf(ctx, ability.DamageRatio))
	local marked = {}
	for _, enemy in EnemyService.findInRadius(center, ability.SpreadRadius, ability.MaxTargets, ctx.Player) do
		if EnemyService.applyControl(enemy, "Vulnerable", ability.CurseSeconds, ability.VulnerableBonus) then
			table.insert(marked, enemy.Root.Position)
		end
	end
	emit(ctx, origin, { Kind = "Curse", Origin = origin, Target = center, Marked = marked, Seconds = ability.CurseSeconds, Hits = ctx.Hits })
	return true
end

function EXECUTE.Starfall(ctx: Context): boolean
	local ability = ctx.Ability
	local player, state = ctx.Player, ctx.State
	local center = ctx.Root.Position + flatLook(ctx.Root) * ability.Distance
	local generation = state.Generation
	emit(ctx, center, { Kind = "StarfallCast", Center = center, Radius = ability.Radius, Telegraph = ability.Telegraph, Waves = ability.Waves, WaveInterval = ability.WaveInterval })
	for wave = 1, ability.Waves do
		task.delay(ability.Telegraph + (wave - 1) * ability.WaveInterval, function()
			-- Anulada si murió, cambió de zona o salió durante el aviso.
			if states[player] ~= state or state.Generation ~= generation or not characterOf(player) then
				return
			end
			ctx.Hits = {}
			for _, enemy in EnemyService.findInRadius(center, ability.Radius, ability.MaxTargets, ctx.Player) do
				hit(ctx, enemy, damageOf(ctx, ability.DamageRatio), center)
			end
			emit(ctx, center, { Kind = "StarfallWave", Center = center, Radius = ability.Radius, Wave = wave, Hits = ctx.Hits })
			runReactions(ctx)
		end)
	end
	return true
end

-- Usa la habilidad de un hueco ("Primary" por defecto). Devuelve (código, elemento?,
-- hora del servidor en que ese elemento volverá a estar listo?).
function AbilityService.perform(player: Player, slot: any): (string, string?, number?)
	if slot ~= nil and not (typeof(slot) == "string" and SLOTS[slot]) then
		return Codes.InvalidRequest, nil, nil
	end
	local root, humanoid = characterOf(player)
	if not (root and humanoid) then
		return Codes.InvalidRequest, nil, nil
	end
	local profile = PlayerDataService.get(player)
	if not profile then
		return Codes.NotReady, nil, nil
	end
	local state = stateOf(player)
	local elementId = AbilityService.elementOf(profile, slot)
	if not elementId then
		return Codes.Locked, nil, nil -- sin elemento secundario
	end
	local now = os.clock()
	local readyAt = state.ReadyAt[elementId] or 0
	if now < readyAt then
		return Codes.Cooldown, elementId, serverTime(readyAt)
	end
	if now - state.LastCastAt < AbilityConfig.GlobalCooldown then
		return Codes.TooFast, elementId, serverTime(readyAt)
	end
	local ability = AbilityLogic.get(elementId :: string)
	local execute = ability and EXECUTE[ability.Type]
	if not execute then
		return Codes.InvalidRequest, elementId, nil
	end
	local ctx: Context = {
		Player = player,
		State = state,
		Ability = ability,
		ElementId = elementId :: string,
		Level = CoreLogic.level(profile.PetData.Cores, profile.UpgradeLevels, elementId :: string),
		Base = PlayerDataService.combatStats(profile).Power, -- escala con el arma equipada
		Root = root,
		Humanoid = humanoid,
		Hits = {},
		Engaged = false,
		Reactions = {},
	}
	if not execute(ctx) then
		return Codes.NoTarget, elementId, serverTime(readyAt)
	end
	state.ReadyAt[elementId :: string] = now + ability.Cooldown
	state.LastCastAt = now
	runReactions(ctx)
	return Codes.Success, elementId, serverTime(now + ability.Cooldown)
end

-- Quemaduras pendientes (público para poder probarlo fuera de Studio).
function AbilityService.step(now: number)
	local ticks: { [Player]: { any } } = {}
	local index = 1
	while index <= #burns do
		local burn = burns[index]
		local enemy = burn.Enemy
		if not states[burn.Player] or enemy.Generation ~= burn.EnemyGeneration or not EnemyService.isAlive(enemy) or burn.TicksLeft <= 0 then
			table.remove(burns, index)
			continue
		end
		if now >= burn.NextTick then
			burn.NextTick = now + burn.Interval
			burn.TicksLeft -= 1
			local position = enemy.Root.Position
			local dealt, killed = EnemyService.damage(enemy, burn.Player, burn.Damage)
			if dealt > 0 then
				ticks[burn.Player] = ticks[burn.Player] or {}
				table.insert(ticks[burn.Player], { Position = position, Damage = dealt, Killed = killed, Kind = enemy.Kind, Model = enemy.Model })
			end
		end
		index += 1
	end
	-- Un aviso por jugador y ciclo, solo a él (los demás ven las llamas por el atributo).
	for player, hits in ticks do
		if player.Parent ~= nil then
			eventRemote:FireClient(player, { Kind = "BurnTick", Owner = player, Hits = hits })
		end
	end
end

local function reset(player: Player)
	local state = states[player]
	if state then
		state.Generation += 1
		state.HasteToken += 1 -- el personaje nuevo empieza con la velocidad normal
	end
end

function AbilityService.start()
	eventRemote = RemoteService.get(Constants.Remotes.AbilityEvent)
	resultRemote = RemoteService.get(Constants.Remotes.AbilityResult)
	local useRemote = RemoteService.get(Constants.Remotes.UseAbility)

	useRemote.OnServerEvent:Connect(function(player: Player, slot: any)
		local rate = useLimiter:check(player)
		if rate == "flood" then
			return
		end
		local safeSlot = if typeof(slot) == "string" and SLOTS[slot] then slot else "Primary"
		if rate == "cooldown" then
			resultRemote:FireClient(player, false, Codes.TooFast, nil, nil, safeSlot)
			return
		end
		local code, elementId, readyAt = AbilityService.perform(player, slot)
		resultRemote:FireClient(player, code == Codes.Success, code, elementId, readyAt, safeSlot)
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
		useLimiter:remove(player)
	end)

	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			local ok, err = pcall(AbilityService.step, os.clock())
			if not ok then
				warn("[AbilityService] " .. tostring(err))
			end
		end
	end)
end

return AbilityService
