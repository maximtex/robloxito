-- EnemyService · Spawning: arenas de jefe, creación de enemigos, variantes y élites, reserva de las oleadas y jefes de oleada.
-- Parte de EnemyService (ver EnemyService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnemyConfig = require(Shared.Config.EnemyConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local WaveLogic = require(Shared.WaveLogic)
local PartFactory = require(script.Parent.Parent.Parent.Util.PartFactory)
local EnemyLogic = require(script.Parent.Parent.Parent.Util.EnemyLogic)
local TerrainPaint = require(script.Parent.Parent.Parent.Util.TerrainPaint)
local Types = require(script.Parent.Types)
type Brain = Types.Brain
type Enemy = Types.Enemy

local ctx: any -- tabla de estado compartida (la crea EnemyService/init.luau)
local EnemyService: any -- la tabla pública del servicio
local Api = {} -- funciones públicas de esta parte (init.luau las copia a EnemyService)
local BAR_SIZES: any
local BUILDERS: any
local ENRAGED_EYES: any
local GROUND: any
local INK: any
local RUN_ATTRIBUTE: any
local SHAPES: any
local WAVE_GROUP: any
local WAVE_SLOT_PREFIX: any
local bossByZone: any
local clickListeners: any
local enemies: any
local poolCreated: any
local pools: any
local streaks: any

-- Funciones de las otras partes
local function addJoints(...) return ctx.addJoints(...) end
local function buildHealthBar(...) return ctx.buildHealthBar(...) end
local function burst(...) return ctx.burst(...) end
local function clearControl(...) return ctx.clearControl(...) end
local function newBrain(...) return ctx.newBrain(...) end
local function newRig(...) return ctx.newRig(...) end
local function release(...) return ctx.release(...) end
local function respawn(...) return ctx.respawn(...) end
local function safeAreasOf(...) return ctx.safeAreasOf(...) end
local function sameWorld(...) return ctx.sameWorld(...) end
local function setCollisionGroup(...) return ctx.setCollisionGroup(...) end
local function setEnraged(...) return ctx.setEnraged(...) end
local function syncHealth(...) return ctx.syncHealth(...) end
local function zoneCenter(...) return ctx.zoneCenter(...) end

-- Arenas de jefe ---------------------------------------------------------------------

local function buildArena(parent: Instance, zoneId: string, arena)
	local center = zoneCenter(zoneId) + Vector3.new(arena.Center.X, 0, arena.Center.Y)
	local isValley = zoneId == "CrystalValley"
	local floor = if isValley then Enum.Material.Pavement else Enum.Material.Cobblestone
	-- Suelo pintado a ras, sin montículo (TerrainPaint; un FillCylinder lo levantaría).
	TerrainPaint.circle(center.X, center.Z, arena.Radius, GROUND, { Enum.Material.Grass, Enum.Material.LeafyGrass, Enum.Material.Ground }, floor)

	local model = Instance.new("Model")
	model.Name = "Arena_" .. zoneId
	local stone = if isValley then Color3.fromRGB(120, 118, 144) else Color3.fromRGB(110, 112, 100)
	local rune = if isValley then Color3.fromRGB(176, 120, 236) else Color3.fromRGB(96, 224, 200)
	-- Entrada orientada hacia el centro de la zona
	local toZone = zoneCenter(zoneId) - center
	local entranceAngle = math.atan2(toZone.Z, toZone.X)
	local count = 10
	for index = 1, count do
		local angle = entranceAngle + (index - 0.5) / count * math.pi * 2
		-- Se salta el menhir que taparía la entrada
		if index ~= 1 and index ~= count then
			local position = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (arena.Radius + 1.5)
			local height = 5 + (index % 3) * 1.2
			local facing = CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z))
			PartFactory.part(model, "Stone" .. index, {
				Size = Vector3.new(2, height, 1.2),
				CFrame = facing * CFrame.new(0, height / 2 - 0.3, 0),
				Color = stone,
				Material = Enum.Material.Slate,
			})
			PartFactory.part(model, "Rune" .. index, {
				Size = Vector3.new(0.3, height * 0.4, 0.06),
				CFrame = facing * CFrame.new(0, height * 0.55, -0.63),
				Color = rune,
				Material = Enum.Material.Neon,
				Solid = false,
			})
		end
	end
	-- Cartel con el nombre del lugar, sobre la entrada
	local signPosition = center + Vector3.new(math.cos(entranceAngle), 0, math.sin(entranceAngle)) * (arena.Radius + 2)
	local anchor = PartFactory.part(model, "SignAnchor", {
		Size = Vector3.one * 0.2,
		CFrame = CFrame.new(signPosition + Vector3.new(0, 8, 0)),
		Color = stone,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	anchor.Transparency = 1
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(14, 0, 2, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 150
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 236, 200)
	label.TextStrokeTransparency = 0.3
	label.Text = "⚔ " .. arena.Name
	label.Parent = billboard
	billboard.Parent = anchor

	-- Círculo de runas en el suelo (marca el límite de la pelea) y sello central. Piezas
	-- planas sin colisión; ni luces ni partículas.
	local runeCount = 12
	for index = 1, runeCount do
		local angle = (index / runeCount) * math.pi * 2
		local position = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (arena.Radius - 1.5)
		local tile = PartFactory.part(model, "FloorRune" .. index, {
			Size = Vector3.new(0.9, 0.1, 2.2),
			CFrame = CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)) * CFrame.new(0, 0.2, 0),
			Color = rune,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		tile.Transparency = 0.35
	end
	for index, diameter in { 7, 4.2 } do
		local seal = PartFactory.verticalCylinder(model, "Seal" .. index, center + Vector3.new(0, 0.18 + index * 0.03, 0), 0.1, diameter, if index == 1 then stone else rune, if index == 1 then Enum.Material.Slate else Enum.Material.Neon, false)
		seal.Transparency = if index == 1 then 0 else 0.5
	end

	model.Parent = parent
end

-- Arranque --------------------------------------------------------------------------

-- Vida de un tipo con la escala global (EnemyConfig.HealthScale: todos aguantan más)
local function baseHealth(def): number
	local scale = EnemyConfig.HealthScale
	return math.max(1, math.floor(def.MaxHealth * (if type(scale) == "number" and scale > 0 then scale else 1)))
end

local function createEnemy(zoneId: string, typeId: string, home: Vector3, zoneSettings, leashCenter: Vector3?, leashRadius: number?, pooled: boolean?): Enemy?
	local def = EnemyConfig.Types[typeId]
	if not def then
		warn("[EnemyService] Tipo de enemigo desconocido: " .. tostring(typeId))
		return nil
	end
	local shape = SHAPES[def.Look.Style]
	local rig = newRig(typeId, shape.Root, shape.Hip, def.WalkSpeed)
	BUILDERS[def.Look.Style](rig, def.Look)
	addJoints(rig, shape.Pivots)
	-- Contorno de caricatura (el cliente lo reutiliza para el destello al recibir daño).
	local outline = Instance.new("Highlight")
	outline.Name = "Outline"
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.FillTransparency = 1
	outline.OutlineColor = INK
	outline.OutlineTransparency = 0
	outline.Parent = rig.Model
	rig.Model:SetAttribute("EnemyType", typeId)
	rig.Model:SetAttribute("Kind", def.Kind)
	rig.Model:SetAttribute("DisplayName", def.DisplayName)
	-- Datos de presentación para el cliente (copias de la configuración, no se leen de vuelta).
	rig.Model:SetAttribute("FxColor", def.Look.Secondary)
	rig.Model:SetAttribute("AttackWindup", def.AttackWindup)
	if def.Slam then
		rig.Model:SetAttribute("SlamTelegraph", def.Slam.Telegraph)
	end

	local safeZones = {}
	local center = zoneCenter(zoneId)
	for _, safe in zoneSettings.SafeZones or {} do
		table.insert(safeZones, { Center = center + Vector3.new(safe.Center.X, 0, safe.Center.Y), Radius = safe.Radius })
	end

	local enemy: Enemy = {
		Id = #enemies + 1,
		TypeId = typeId,
		Def = def,
		Kind = def.Kind,
		ZoneId = zoneId,
		Model = rig.Model,
		Root = rig.Root,
		Humanoid = rig.Humanoid,
		Eyes = rig.Eyes,
		EyeColor = def.Look.Eyes,
		Aura = nil,
		Glow = nil,
		Bar = nil :: any,
		Billboard = nil :: any,
		RootHeight = rig.RootHeight,
		Radius = shape.Radius,
		DeathSeconds = shape.DeathSeconds,
		Home = home,
		LeashCenter = leashCenter or home,
		LeashRadius = leashRadius or def.LeashRange,
		DetectRange = def.DetectRange,
		SafeZones = safeZones,
		SafeAreas = safeAreasOf(zoneId, zoneSettings),
		RewardMultiplier = zoneSettings.RewardMultiplier or 1,
		Status = { State = "Idle", Health = baseHealth(def), MaxHealth = baseHealth(def), Contributions = {} },
		Control = EnemyLogic.newControl(),
		Target = nil,
		NextAttack = 0,
		NextSlam = 0,
		NextWander = 0,
		Enraged = false,
		Generation = 0,
		StuckSince = nil,
		LastHomeDistance = math.huge,
		Brain = nil,
		Pooled = pooled == true,
		InPool = false,
		WaveControlled = false,
		OnWaveDeath = nil,
		LastHitBy = nil,
		Run = nil,
		MoneyMultiplier = 1,
		Territory = nil,
	}
	if pooled then
		-- De las oleadas: sin zonas seguras (el círculo está en la plaza) y sin chocar con
		-- los jugadores ni con los de otras partidas.
		enemy.SafeZones = {}
		enemy.SafeAreas = {}
		setCollisionGroup(rig.Model, WAVE_GROUP)
	end
	if def.Brain then
		enemy.Brain = newBrain()
	end
	buildHealthBar(enemy, shape.BarHeight)
	if def.Enrage then
		-- Aura de furia: se crea una vez y solo se enciende durante la furia.
		local aura = Instance.new("ParticleEmitter")
		aura.Name = "EnrageAura"
		aura.Enabled = false
		aura.Rate = 12
		aura.Lifetime = NumberRange.new(0.8, 1.2)
		aura.Speed = NumberRange.new(1, 2)
		aura.Acceleration = Vector3.new(0, 4, 0)
		aura.SpreadAngle = Vector2.new(180, 180)
		aura.Size = NumberSequence.new(0.9, 0)
		aura.Transparency = NumberSequence.new(0.3, 1)
		aura.LightEmission = 1
		aura.Color = ColorSequence.new(ENRAGED_EYES, def.Look.Secondary)
		aura.Parent = enemy.Root
		enemy.Aura = aura
		local glow = Instance.new("PointLight")
		glow.Name = "EnrageGlow"
		glow.Enabled = false
		glow.Color = ENRAGED_EYES
		glow.Range = 16
		glow.Brightness = 1.6
		glow.Shadows = false
		glow.Parent = enemy.Root
		enemy.Glow = glow
	end
	table.insert(enemies, enemy)
	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 75
	clickDetector.Parent = rig.Model
	clickDetector.MouseClick:Connect(function(player: Player)
		if EnemyService.isAlive(enemy) and sameWorld(enemy, player) then
			enemy.Billboard.Enabled = true
			for _, listener in clickListeners do
				task.spawn(listener, player, enemy)
			end
		end
	end)
	if enemy.Pooled then
		-- De la reserva: fuera del mundo hasta que una oleada lo saque (spawnPooled).
		enemy.Status.State = "Dead"
		syncHealth(enemy)
	else
		respawn(enemy)
	end
	return enemy
end

-- Mazmorras: élites y mini-jefes ------------------------------------------------------------

-- Lo visible de un élite o un mini-jefe (una sola vez, al crearlo): más grande (Scale), una
-- luz y chispas de su color alrededor y su nombre en la barra. Lo de más vida, daño y botín lo
-- pone quien lo crea.
-- Más grande (s veces): el modelo, su cadera, su radio de golpe y la barra encima
local function scaleEnemy(enemy: Enemy, s: number)
	if s == 1 then
		return
	end
	local model = enemy.Model
	local hip = enemy.Humanoid.HipHeight
	local offset = enemy.Billboard.StudsOffset
	local ok = pcall(function()
		model:ScaleTo(model:GetScale() * s)
	end)
	if ok then
		enemy.Humanoid.HipHeight = hip * s
		enemy.RootHeight *= s
		enemy.Radius *= s
		enemy.Billboard.StudsOffset = offset * s
	end
end

local function dressVariant(enemy: Enemy, variant: string, scale: number?, color: Color3, name: string)
	enemy.Variant = variant
	local model = enemy.Model
	local s = if type(scale) == "number" and scale > 0 then scale else 1
	scaleEnemy(enemy, s)
	local glow = Instance.new("PointLight")
	glow.Name = "VariantGlow"
	glow.Color = color
	glow.Range = 12 * s
	glow.Brightness = 1.6
	glow.Shadows = false
	glow.Parent = enemy.Root
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "VariantSparkles"
	sparkles.Color = ColorSequence.new(color)
	sparkles.LightEmission = 1
	sparkles.LightInfluence = 0
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.45 * s), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Transparency = NumberSequence.new(0.15)
	sparkles.Lifetime = NumberRange.new(0.8, 1.4)
	sparkles.Rate = if variant == "MiniBoss" then 22 else 12
	sparkles.Speed = NumberRange.new(1.5, 3)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Acceleration = Vector3.new(0, 3, 0)
	sparkles.Parent = enemy.Root
	local label = enemy.Billboard:FindFirstChild("EnemyName")
	if label and label:IsA("TextLabel") then
		label.Text = name
		label.TextColor3 = color
	end
	enemy.Billboard.Size = if variant == "MiniBoss" then BAR_SIZES.Boss else BAR_SIZES.Strong
	model:SetAttribute("DisplayName", name)
	model:SetAttribute("Variant", variant)
end

-- Más vida, daño y botín (×) de golpe, para los del mundo (los de las oleadas lo llevan en
-- spawnPooled).
local function strengthen(enemy: Enemy, health: number?, damage: number?, reward: number?)
	enemy.Status.MaxHealth = math.max(1, math.floor(enemy.Status.MaxHealth * (health or 1)))
	enemy.Status.Health = enemy.Status.MaxHealth
	enemy.DamageMultiplier = (enemy.DamageMultiplier or 1) * (damage or 1)
	enemy.RewardMultiplier *= reward or 1
	syncHealth(enemy)
end

local function makeElite(enemy: Enemy)
	local elite = EnemyConfig.Elite
	dressVariant(enemy, "Elite", elite.Scale, elite.Color, (elite.Prefix or "") .. enemy.Def.DisplayName)
end

-- Oleadas ------------------------------------------------------------------------------


local function finiteOr(value: any, default: number): number
	return if type(value) == "number" and value == value and value > 0 and value < 1e9 then value else default
end

-- Saca un enemigo de la reserva (o lo crea si aún caben) en `position`. nil si no hay sitio.
function Api.spawnPooled(zoneId: string, typeId: string, position: Vector3, options: WaveSpawnOptions?): Enemy?
	local opts: WaveSpawnOptions = options or {}
	local zoneSettings = EnemyConfig.Zones[zoneId]
	if not (zoneSettings and EnemyConfig.Types[typeId] and ZoneConfig.Zones[zoneId]) then
		return nil
	end
	local elite = opts.Elite == true
	local key = zoneId .. "/" .. typeId .. (if elite then "/Elite" else "")
	local free = pools[key]
	local enemy = if free then table.remove(free) else nil
	if not enemy then
		if (poolCreated[key] or 0) >= finiteOr(opts.PoolLimit, 20) then
			return nil
		end
		enemy = createEnemy(zoneId, typeId, position, zoneSettings, nil, nil, true)
		if not enemy then
			return nil
		end
		-- Tamaño propio (los jefes gigantes de las oleadas), una vez por instancia
		local scale = enemy.Def.Scale
		if type(scale) == "number" and scale > 0 and scale ~= 1 then
			scaleEnemy(enemy, scale)
		end
		if elite then
			makeElite(enemy)
		end
		poolCreated[key] = (poolCreated[key] or 0) + 1
	end
	local eliteSpec = if enemy.Variant == "Elite" then EnemyConfig.Elite else nil
	local def = enemy.Def
	enemy.InPool = false
	enemy.Home = position
	enemy.LeashCenter = opts.LeashCenter or position
	enemy.LeashRadius = finiteOr(opts.LeashRadius, def.LeashRange)
	enemy.DetectRange = finiteOr(opts.DetectRange, def.DetectRange)
	enemy.RewardMultiplier = finiteOr(opts.RewardMultiplier, 1) * (if eliteSpec then eliteSpec.Reward else 1)
	enemy.Status.MaxHealth = math.max(1, math.floor(baseHealth(def) * finiteOr(opts.HealthMultiplier, 1) * (if eliteSpec then eliteSpec.Health else 1)))
	enemy.OnWaveDeath = opts.OnDeath
	enemy.OnSplit = opts.OnSplit
	enemy.SplitAt = if opts.OnSplit then math.clamp(finiteOr(opts.SplitAt, 0.5), 0.05, 0.95) else nil
	enemy.LastHitBy = nil
	enemy.Run = opts.Run
	enemy.Model:SetAttribute(RUN_ATTRIBUTE, opts.Run)
	enemy.MoneyMultiplier = if opts.MoneyMultiplier ~= nil then math.clamp(finiteOr(opts.MoneyMultiplier, 1), 0, 10) else 1
	enemy.DamageMultiplier = if opts.DamageMultiplier ~= nil then math.clamp(finiteOr(opts.DamageMultiplier, 1), 0.1, 10) else nil
	if eliteSpec then
		enemy.DamageMultiplier = (enemy.DamageMultiplier or 1) * eliteSpec.Damage
	end
	local slot = opts.CollisionSlot
	setCollisionGroup(enemy.Model, if type(slot) == "number" and slot >= 1 and slot <= ctx.waveSlots then WAVE_SLOT_PREFIX .. math.floor(slot) else WAVE_GROUP)
	enemy.Territory = if opts.Territory ~= nil then finiteOr(opts.Territory, def.Brain and def.Brain.Territory or 20) else nil
	local arena = opts.Arena
	enemy.Model:SetAttribute("ArenaCenter", if arena then arena.Center else nil)
	enemy.Model:SetAttribute("ArenaRadius", if arena then arena.Radius else nil)
	enemy.Model:SetAttribute("ArenaName", if arena then arena.Name else nil)
	enemy.Generation += 1
	respawn(enemy)
	return enemy
end

-- Retira un enemigo de una oleada SIN recompensa (partida perdida o terminada). Los de la
-- reserva vuelven a ella; los jefes de las oleadas se quedan dormidos.
function Api.despawn(enemy: Enemy?)
	if not enemy then
		return
	end
	enemy.Generation += 1 -- anula reapariciones y disoluciones pendientes
	enemy.OnWaveDeath = nil
	enemy.OnSplit = nil
	enemy.SplitAt = nil
	enemy.LastHitBy = nil
	enemy.Target = nil
	clearControl(enemy)
	setEnraged(enemy, false)
	if enemy.Model.Parent ~= nil and enemy.Status.State ~= "Dead" then
		burst(enemy.Root.Position, enemy.Def.Look.Secondary, 12, true, enemy.Run)
	end
	enemy.Status.State = "Dead"
	enemy.Billboard.Enabled = false
	enemy.Model:SetAttribute("TargetUserId", nil)
	enemy.Model.Parent = nil
	release(enemy)
end

-- El jefe de una zona pasa a salir solo en las oleadas (controlled = true: se duerme ya)
-- o vuelve a estar siempre en su arena (false: reaparece ahora con su vida normal).
function Api.setBossWaveControlled(zoneId: string, controlled: boolean): Enemy?
	local boss = bossByZone[zoneId]
	if not boss then
		return nil
	end
	boss.WaveControlled = controlled
	if controlled then
		EnemyService.despawn(boss)
	else
		boss.Status.MaxHealth = baseHealth(boss.Def)
		boss.OnWaveDeath = nil
		boss.Generation += 1
		respawn(boss)
	end
	return boss
end

-- Despierta al jefe de una zona para la última oleada (con más vida si hay más jugadores).
function Api.wakeBoss(zoneId: string, healthMultiplier: number?, onDeath: ((any, Player?, Vector3) -> ())?): Enemy?
	local boss = bossByZone[zoneId]
	if not boss then
		return nil
	end
	boss.Status.MaxHealth = math.max(1, math.floor(baseHealth(boss.Def) * finiteOr(healthMultiplier, 1)))
	boss.OnWaveDeath = onDeath
	boss.LastHitBy = nil
	boss.Generation += 1
	respawn(boss)
	return boss
end

function Api.bossOf(zoneId: string): Enemy?
	return bossByZone[zoneId]
end

-- WaveService añade lo de las mejoras de la partida: (multiplicador del botín, segundos
-- extra de racha) para ese jugador y ese enemigo.
function Api.setKillModifier(modifier: (Player, Enemy) -> (number?, number?))
	ctx.killModifier = modifier
end

-- Racha vigente de un jugador (0 si caducó) y la mejor de la sesión.
function Api.streakOf(player: Player): (number, number)
	local streak = streaks[player]
	if not streak then
		return 0, 0
	end
	return WaveLogic.streakCount(streak, os.clock()), streak.Best
end

local Part = { Api = Api }

function Part.install(context: any)
	ctx = context
	context.createEnemy = createEnemy
	context.dressVariant = dressVariant
	context.makeElite = makeElite
	context.scaleEnemy = scaleEnemy
	context.strengthen = strengthen
end

function Part.link(context: any)
	EnemyService = context.Service
	BAR_SIZES = context.BAR_SIZES
	BUILDERS = context.BUILDERS
	ENRAGED_EYES = context.ENRAGED_EYES
	GROUND = context.GROUND
	INK = context.INK
	RUN_ATTRIBUTE = context.RUN_ATTRIBUTE
	SHAPES = context.SHAPES
	WAVE_GROUP = context.WAVE_GROUP
	WAVE_SLOT_PREFIX = context.WAVE_SLOT_PREFIX
	bossByZone = context.bossByZone
	clickListeners = context.clickListeners
	enemies = context.enemies
	poolCreated = context.poolCreated
	pools = context.pools
	streaks = context.streaks
end

return Part
