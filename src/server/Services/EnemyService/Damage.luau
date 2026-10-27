-- EnemyService · Damage: botín, racha, muerte, daño recibido, estados, retroceso y búsqueda de objetivos.
-- Parte de EnemyService (ver EnemyService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local RebirthLogic = require(Shared.RebirthLogic)
local AdventureLogic = require(Shared.AdventureLogic)
local CombatConfig = require(Shared.Config.CombatConfig)
local ItemLogic = require(Shared.ItemLogic)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local WaveLogic = require(Shared.WaveLogic)
local PlayerDataService = require(script.Parent.Parent.PlayerDataService)
local DiamondService = require(script.Parent.Parent.DiamondService)
local EnemyLogic = require(script.Parent.Parent.Parent.Util.EnemyLogic)
local Types = require(script.Parent.Types)
type Enemy = Types.Enemy

local ctx: any -- tabla de estado compartida (la crea EnemyService/init.luau)
local EnemyService: any -- la tabla pública del servicio
local Api = {} -- funciones públicas de esta parte (init.luau las copia a EnemyService)
local DISSOLVE_SECONDS: any
local ENRAGED_EYES: any
local KNOCKBACK_SECONDS: any
local MAX_CONTROL_SECONDS: any
local STATUS_ATTRIBUTES: any
local defeatListeners: any
local enemies: any
local pools: any
local streaks: any

-- Funciones de las otras partes
local function burst(...) return ctx.burst(...) end
local function clearControl(...) return ctx.clearControl(...) end
local function refreshSpeed(...) return ctx.refreshSpeed(...) end
local function respawn(...) return ctx.respawn(...) end
local function runOfPlayer(...) return ctx.runOfPlayer(...) end
local function sameWorld(...) return ctx.sameWorld(...) end
local function setEnraged(...) return ctx.setEnraged(...) end
local function syncHealth(...) return ctx.syncHealth(...) end

-- Multiplicador del dinero que cobra un jugador: renacimiento y "Botín abundante", amuletos
-- y bendiciones de las aventuras, sus mascotas (CombatConfig.PetMoneyShare de su
-- bonificación) y la Poción de Riqueza (inventario) mientras dura.
local function lootMultiplier(profile): number
	local pets = 1 + math.max(0, (profile.PetMultiplier or 1) - 1) * CombatConfig.PetMoneyShare
	return RebirthLogic.lootMultiplier(RebirthLogic.ofProfile(profile))
		* AdventureLogic.lootMultiplier(AdventureLogic.ofProfile(profile), os.time())
		* pets
		* ItemLogic.multiplier(ItemLogic.ofProfile(profile), "Money", os.time())
end

-- Racha del jugador: sube con este enemigo y se publica para el cliente (Streak y la hora
-- del servidor a la que caduca, StreakUntil).
local function streakOf(player: Player): WaveLogic.Streak
	local streak = streaks[player]
	if not streak then
		streak = WaveLogic.newStreak()
		streaks[player] = streak
	end
	return streak
end

local function publishStreak(player: Player, streak: WaveLogic.Streak, nowClock: number)
	local attributes = Constants.Attributes
	player:SetAttribute(attributes.Streak, streak.Count)
	player:SetAttribute(attributes.StreakUntil, Workspace:GetServerTimeNow() + math.max(0, streak.Until - nowClock))
	player:SetAttribute(attributes.StreakBest, streak.Best)
end

-- Extra de las mejoras de la partida (WaveService): multiplicador del botín y segundos
-- de más en la ventana de la racha. Valores raros se ignoran.
local function killExtras(player: Player, enemy: Enemy): (number, number)
	if not ctx.killModifier then
		return 1, 0
	end
	local ok, loot, seconds = pcall(ctx.killModifier, player, enemy)
	if not ok then
		return 1, 0
	end
	local cleanLoot = if type(loot) == "number" and loot == loot and loot > 0 and loot < 100 then loot else 1
	local cleanSeconds = if type(seconds) == "number" and seconds == seconds and seconds > 0 and seconds < 30 then seconds else 0
	return cleanLoot, cleanSeconds
end

-- Vuelve a la reserva de las oleadas (una sola vez).
local function release(enemy: Enemy)
	if not enemy.Pooled or enemy.InPool then
		return
	end
	enemy.InPool = true
	local key = enemy.ZoneId .. "/" .. enemy.TypeId .. (if enemy.Variant == "Elite" then "/Elite" else "")
	pools[key] = pools[key] or {}
	table.insert(pools[key], enemy)
end

local function onDeath(enemy: Enemy)
	enemy.Generation += 1
	local generation = enemy.Generation
	enemy.Target = nil
	clearControl(enemy)
	enemy.Humanoid:MoveTo(enemy.Root.Position)
	syncHealth(enemy)
	enemy.Billboard.Enabled = false
	enemy.Model:SetAttribute("DiedAt", Workspace:GetServerTimeNow())

	-- Recompensa: una sola vez por vida (solo llega aquí el golpe que lo mató).
	-- 💰 y 💎 para cada uno según su daño, por la racha, el botín dorado y las mejoras.
	local reward = math.floor(enemy.Def.Reward * enemy.RewardMultiplier)
	local isBoss = enemy.Kind == "Boss"
	local position = enemy.Root.Position
	local nowClock = os.clock()
	for userId, amount in EnemyLogic.splitReward(enemy.Status.Contributions, reward) do
		local player = Players:GetPlayerByUserId(userId)
		local profile = player and PlayerDataService.get(player)
		if player and profile and amount > 0 then
			local lootBonus, streakSeconds = killExtras(player, enemy)
			local streak = streakOf(player)
			local count = WaveLogic.streakKill(streak, nowClock, streakSeconds)
			local golden = WaveLogic.rollGolden(math.random, isBoss)
			local bonus = WaveLogic.streakMultiplier(count) * WaveLogic.goldenMultiplier(golden) * lootBonus
			local earned = math.floor(amount * lootMultiplier(profile) * bonus * enemy.MoneyMultiplier)
			profile.Money += earned
			-- 💎 (Diamonds en el código): pocos, por el pase Diamantes ×2, la Poción de Diamantes y
			-- las aventuras (PlayerDataService.diamondMultiplier); lo que no llega a uno entero es
			-- su probabilidad
			local rawDiamonds = WaveLogic.killDiamonds(amount, EconomyConfig.KillDiamondShare) * bonus * PlayerDataService.diamondMultiplier(profile)
			local diamonds = DiamondService.grant(player, WaveLogic.roundDiamonds(rawDiamonds, math.random()))
			if diamonds <= 0 then
				PlayerDataService.replicate(player) -- grant ya replica si ha sumado energía
			end
			publishStreak(player, streak, nowClock)
			ctx.rewardRemote:FireClient(player, earned, enemy.Def.DisplayName, isBoss, position, true, { Diamonds = diamonds, Golden = golden, Streak = count })
			-- Cuenta como derrota para quien recibe parte de la recompensa (daño real). Home: dónde
			-- vive (la cueva cuenta los de cada sala); Wave: era de una oleada.
			local info = {
				TypeId = enemy.TypeId,
				Kind = enemy.Kind,
				ZoneId = enemy.ZoneId,
				Reward = earned,
				Diamonds = diamonds,
				Golden = golden,
				Streak = count,
				Home = enemy.Home,
				Wave = enemy.Pooled or enemy.WaveControlled,
				Elite = enemy.Variant == "Elite",
				MiniBoss = enemy.Variant == "MiniBoss", -- abre la puerta de su sala (CaveService)
			}
			for _, listener in defeatListeners do
				task.spawn(listener, player, info)
			end
		end
	end

	burst(position, enemy.Def.Look.Secondary, if isBoss then 60 else 20, true, enemy.Run)
	local killer = enemy.LastHitBy
	enemy.LastHitBy = nil
	local dissolve = enemy.DeathSeconds or DISSOLVE_SECONDS[enemy.Kind] or 0.8
	-- Oleadas: ni reaparece solo ni se queda; los de la reserva vuelven a ella.
	if enemy.Pooled or enemy.WaveControlled then
		task.delay(dissolve, function()
			if enemy.Generation == generation then
				enemy.Model.Parent = nil
				release(enemy)
			end
		end)
		local callback = enemy.OnWaveDeath
		enemy.OnWaveDeath = nil
		if callback then
			task.spawn(callback, enemy, killer, position)
		end
		return
	end
	-- Los modelos con animación de muerte (ModelosZona1) se quedan lo que dura esa animación.
	task.delay(dissolve, function()
		if enemy.Generation == generation then
			enemy.Model.Parent = nil -- fuera del mundo hasta reaparecer
		end
	end)
	task.delay(enemy.Def.RespawnSeconds, function()
		if enemy.Generation == generation then
			enemy.Generation += 1
			respawn(enemy)
		end
	end)
end

-- Daño recibido de un jugador (lo llama CombatService tras validar el golpe).
-- Devuelve el daño aplicado, si este golpe lo ha matado y las monedas ganadas en el impacto.
function Api.damage(enemy: Enemy, player: Player, amount: number): (number, boolean, number)
	if enemy.Model.Parent == nil or not sameWorld(enemy, player) then
		return 0, false, 0 -- los de otra partida (o del mundo, si juegas una) no se golpean
	end
	-- Marcado por una maldición: recibe más daño (de todos los jugadores y mascotas).
	local profile = PlayerDataService.get(player)
	if type(amount) == "number" then
		amount = EnemyLogic.damageTaken(amount, enemy.Control, os.clock())
		-- Poción de Fuerza: todo el daño del jugador (disparos, habilidades y mascotas) x2.
		if profile then
			amount *= ItemLogic.multiplier(ItemLogic.ofProfile(profile), "Damage", os.time())
		end
		-- Clase (StyleService): p. ej. más daño a los jefes
		if ctx.outgoingModifier then
			local ok, result = pcall(ctx.outgoingModifier, player, enemy, amount)
			if ok and type(result) == "number" and result == result then
				amount = math.clamp(result, 0, amount * 3)
			end
		end
	end
	-- Jefe que se parte: ningún golpe lo baja de la vida del corte (ni lo mata de golpe)
	local splitFloor = if enemy.OnSplit and enemy.SplitAt then math.max(1, math.floor(enemy.Status.MaxHealth * enemy.SplitAt)) else nil
	if splitFloor and type(amount) == "number" then
		amount = math.clamp(amount, 0, math.max(0, enemy.Status.Health - splitFloor))
	end
	local dealt, killed = EnemyLogic.applyDamage(enemy.Status, player.UserId, amount)
	if dealt <= 0 then
		return 0, false, 0
	end
	-- Cada golpe al enemigo suelta un poco de dinero al instante
	local earnedHit = 0
	if profile then
		local baseHit = math.max(1, math.floor(enemy.Def.Reward * (dealt / math.max(1, enemy.Status.MaxHealth)) * 0.75))
		earnedHit = math.max(1, math.floor(baseHit * lootMultiplier(profile) * enemy.MoneyMultiplier))
		profile.Money += earnedHit
		PlayerDataService.replicate(player)
		ctx.rewardRemote:FireClient(player, earnedHit, enemy.Def.DisplayName, false, enemy.Root.Position, false)
	end
	burst(enemy.Root.Position, enemy.Def.Look.Secondary, 5, false, enemy.Run)
	if killed then
		enemy.LastHitBy = player
		onDeath(enemy)
		return dealt, true, earnedHit
	end
	enemy.Billboard.Enabled = true
	syncHealth(enemy)
	-- Llega al corte: se parte (WaveService lo retira y saca sus dos mitades)
	if splitFloor and enemy.Status.Health <= splitFloor then
		local onSplit = enemy.OnSplit
		enemy.OnSplit = nil
		enemy.SplitAt = nil
		if onSplit then
			task.spawn(onSplit, enemy)
		end
		return dealt, false, earnedHit
	end
	-- Furia del jefe
	local enrage = enemy.Def.Enrage
	if enrage and not enemy.Enraged and enemy.Status.Health <= enemy.Status.MaxHealth * enrage.HealthFraction then
		setEnraged(enemy, true) -- más rápido (refreshSpeed)
		burst(enemy.Root.Position, ENRAGED_EYES, 40, false, enemy.Run)
	end
	-- Quien le golpea se convierte en su objetivo si no tenía uno
	if enemy.Target == nil then
		enemy.Target = player
	end
	return dealt, false, earnedHit
end

function Api.isAlive(enemy: Enemy?): boolean
	return enemy ~= nil and enemy.Model.Parent ~= nil and enemy.Status.State ~= "Dead"
end

-- Estado de una habilidad: "Slow" (factor = velocidad), "Root", "Stun" o "Vulnerable"
-- (factor = daño extra). No afecta a enemigos muertos o volviendo a casa. Devuelve true
-- si se ha aplicado. Lo llama AbilityService (que ya ha ajustado los valores de los jefes).
function Api.applyControl(enemy: Enemy, kind: string, seconds: number, factor: number?): boolean
	if not EnemyService.isAlive(enemy) or enemy.Status.State == "Return" then
		return false
	end
	local now = os.clock()
	if not EnemyLogic.applyControl(enemy.Control, kind, now, seconds, factor, MAX_CONTROL_SECONDS) then
		return false
	end
	local control = enemy.Control
	local untilClock = if kind == "Slow" then control.SlowUntil elseif kind == "Root" then control.RootUntil elseif kind == "Stun" then control.StunUntil else control.VulnerableUntil
	enemy.Model:SetAttribute(STATUS_ATTRIBUTES[kind], Workspace:GetServerTimeNow() + (untilClock - now))
	refreshSpeed(enemy, now)
	if kind == "Root" or kind == "Stun" then
		enemy.Humanoid:MoveTo(enemy.Root.Position) -- se para en seco
	end
	return true
end

-- ¿Está aturdido o congelado ahora? (combos de las habilidades de los estilos)
function Api.isStunned(enemy: Enemy): boolean
	return EnemyService.isAlive(enemy) and EnemyLogic.isStunned(enemy.Control, os.clock())
end

-- Marca elemental para los combos (AbilityService). Devuelve la activa o nil.
function Api.auraOf(enemy: Enemy): string?
	return EnemyLogic.auraOf(enemy.Control, os.clock())
end

-- Pone la marca (o la quita con element = nil). No afecta a muertos o volviendo a casa.
function Api.setAura(enemy: Enemy, element: string?, seconds: number?)
	if not EnemyService.isAlive(enemy) or enemy.Status.State == "Return" then
		return
	end
	local now = os.clock()
	EnemyLogic.setAura(enemy.Control, element, now, seconds, MAX_CONTROL_SECONDS)
	local active = EnemyLogic.auraOf(enemy.Control, now)
	enemy.Model:SetAttribute("Aura", active)
	enemy.Model:SetAttribute("AuraUntil", if active then Workspace:GetServerTimeNow() + (enemy.Control.AuraUntil - now) else nil)
end

-- Retroceso breve lejos de `from` (solo enemigos normales y fuertes; los jefes no se
-- mueven). Un LinearVelocity de KNOCKBACK_SECONDS empuja (el Humanoid anularía una simple
-- velocidad) y el enemigo queda quieto un instante para que su IA no luche contra él.
-- `lift`: parte de la fuerza que va hacia arriba (0.2 si no se dice; el gancho de Puños lo
-- levanta más).
function Api.knockback(enemy: Enemy, from: Vector3, force: number, lift: number?)
	if enemy.Kind == "Boss" or not EnemyService.isAlive(enemy) or enemy.Status.State == "Return" then
		return
	end
	local offset = enemy.Root.Position - from
	local flatOffset = Vector3.new(offset.X, 0, offset.Z)
	local direction = if flatOffset.Magnitude > 0.05 then flatOffset.Unit else Vector3.new(0, 0, -1)
	local strength = math.clamp(force, 0, 60) * (if enemy.Kind == "Strong" then 0.6 else 1)
	if strength <= 0 then
		return
	end
	-- Quieto un instante (sin atributo: no es un estado que haya que dibujar).
	local now = os.clock()
	EnemyLogic.applyControl(enemy.Control, "Root", now, KNOCKBACK_SECONDS + 0.15, nil, MAX_CONTROL_SECONDS)
	refreshSpeed(enemy, now)
	local attachment = enemy.Root:FindFirstChild("KnockbackAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "KnockbackAttachment"
		attachment.Parent = enemy.Root
	end
	local previous = enemy.Root:FindFirstChild("Knockback")
	if previous then
		previous:Destroy()
	end
	local mover = Instance.new("LinearVelocity")
	mover.Name = "Knockback"
	mover.Attachment0 = attachment :: Attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.MaxForce = 1e7
	mover.VectorVelocity = direction * strength + Vector3.new(0, strength * math.clamp(lift or 0.2, 0, 1), 0)
	mover.Parent = enemy.Root
	Debris:AddItem(mover, KNOCKBACK_SECONDS)
end

-- Marca de presentación (p. ej. "Burn" mientras se quema): solo el atributo para el cliente.
function Api.markStatus(enemy: Enemy, name: string, seconds: number)
	local attribute = STATUS_ATTRIBUTES[name]
	if attribute and EnemyService.isAlive(enemy) and type(seconds) == "number" and seconds > 0 then
		enemy.Model:SetAttribute(attribute, Workspace:GetServerTimeNow() + math.min(seconds, MAX_CONTROL_SECONDS))
	end
end

-- Daño que recibe un jugador (estilo, clase, bloqueo del Guerrero): (jugador, daño, el
-- enemigo que le pega) -> daño final.
function Api.setIncomingDamageModifier(modifier: (Player, number, any?) -> number)
	ctx.incomingModifier = modifier
end

function Api.setOutgoingDamageModifier(modifier: (Player, any, number) -> number)
	ctx.outgoingModifier = modifier
end

local function damagePlayer(enemy: Enemy, player: Player, humanoid: Humanoid, amount: number)
	if not sameWorld(enemy, player) then
		return -- de otra partida (o del mundo normal mientras juegas una): no te alcanza
	end
	local final = amount * (enemy.DamageMultiplier or 1) -- oleadas: suave al principio, fuerte al final
	if ctx.incomingModifier then
		local ok, result = pcall(ctx.incomingModifier, player, final, enemy)
		if ok and type(result) == "number" and result == result then
			final = math.clamp(result, 0, final * 2) -- nunca curación ni más del doble (estilo Armas: algo más)
		end
	end
	humanoid:TakeDamage(final) -- respeta el escudo de aparición
end

-- Enemigos vivos dentro de un radio (borde incluido), sin repetidos y como mucho `maxTargets`.
-- Con `viewer`, solo los de su mismo "mundo" (oleadas privadas).
function Api.findInRadius(center: Vector3, radius: number, maxTargets: number, viewer: Player?): { Enemy }
	local candidates = {}
	local byId: { [number]: Enemy } = {}
	local viewerRun = if viewer then runOfPlayer(viewer) else nil
	for _, enemy in enemies do
		if EnemyService.isAlive(enemy) and (viewer == nil or enemy.Run == viewerRun) and math.abs(enemy.Root.Position.Y - center.Y) <= 10 + enemy.RootHeight then
			byId[enemy.Id] = enemy
			table.insert(candidates, { Id = enemy.Id, X = enemy.Root.Position.X, Z = enemy.Root.Position.Z, Radius = enemy.Radius, Alive = true })
		end
	end
	local result = {}
	for _, id in EnemyLogic.selectInRadius(center.X, center.Z, candidates, radius, maxTargets) do
		table.insert(result, byId[id])
	end
	return result
end

-- Objetivos de un golpe (la lógica de alcance y ángulo está en EnemyLogic).
function Api.findTargets(origin: Vector3, look: Vector3, range: number, arcDot: number, maxTargets: number, viewer: Player?): { Enemy }
	local candidates = {}
	local byId: { [number]: Enemy } = {}
	local viewerRun = if viewer then runOfPlayer(viewer) else nil
	for _, enemy in enemies do
		local alive = enemy.Model.Parent ~= nil and enemy.Status.State ~= "Dead" and (viewer == nil or enemy.Run == viewerRun)
		-- Sin golpes a través de suelos o desde muy arriba/abajo
		if alive and math.abs(enemy.Root.Position.Y - origin.Y) <= 10 + enemy.RootHeight then
			byId[enemy.Id] = enemy
			table.insert(candidates, { Id = enemy.Id, X = enemy.Root.Position.X, Z = enemy.Root.Position.Z, Radius = enemy.Radius, Alive = true })
		end
	end
	local result = {}
	for _, id in EnemyLogic.selectTargets(origin.X, origin.Z, look.X, look.Z, candidates, range, arcDot, maxTargets) do
		table.insert(result, byId[id])
	end
	return result
end

local Part = { Api = Api }

function Part.install(context: any)
	ctx = context
	context.damagePlayer = damagePlayer
	context.onDeath = onDeath
	context.release = release
end

function Part.link(context: any)
	EnemyService = context.Service
	DISSOLVE_SECONDS = context.DISSOLVE_SECONDS
	ENRAGED_EYES = context.ENRAGED_EYES
	KNOCKBACK_SECONDS = context.KNOCKBACK_SECONDS
	MAX_CONTROL_SECONDS = context.MAX_CONTROL_SECONDS
	STATUS_ATTRIBUTES = context.STATUS_ATTRIBUTES
	defeatListeners = context.defeatListeners
	enemies = context.enemies
	pools = context.pools
	streaks = context.streaks
end

return Part
