-- EnemyService · Life: barra de vida, ojos, velocidad, control, efectos y reaparición.
-- Parte de EnemyService (ver EnemyService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local StudFloor = require(Shared.Util.StudFloor)
local EnemyLogic = require(script.Parent.Parent.Parent.Util.EnemyLogic)
local Types = require(script.Parent.Types)
type Enemy = Types.Enemy

local ctx: any -- tabla de estado compartida (la crea EnemyService/init.luau)
local BAR_DISTANCE: any
local BAR_HEALTHY: any
local BAR_SIZES: any
local BAR_TRACK: any
local ENRAGED_EYES: any
local KIND_NAME_COLORS: any
local STATUS_ATTRIBUTES: any

-- Funciones de las otras partes
local function healthColor(...) return ctx.healthColor(...) end
local function resetBrain(...) return ctx.resetBrain(...) end
local function tagRun(...) return ctx.tagRun(...) end

local function buildHealthBar(enemy: Enemy, barHeight: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Size = BAR_SIZES[enemy.Kind] or BAR_SIZES.Normal
	billboard.StudsOffset = Vector3.new(0, barHeight - enemy.RootHeight, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = BAR_DISTANCE[enemy.Kind] or BAR_DISTANCE.Normal
	billboard.Adornee = enemy.Root

	local name = Instance.new("TextLabel")
	name.Name = "EnemyName"
	name.Size = UDim2.new(1, 0, 0.58, 0)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextScaled = true
	name.TextColor3 = KIND_NAME_COLORS[enemy.Kind] or KIND_NAME_COLORS.Normal
	name.TextStrokeColor3 = Color3.new(0, 0, 0)
	name.TextStrokeTransparency = 0.35
	name.Text = enemy.Def.DisplayName
	name.Parent = billboard

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.new(0.5, 0, 0.66, 0)
	track.Size = UDim2.new(0.86, 0, 0.26, 0)
	track.BackgroundColor3 = BAR_TRACK
	track.BackgroundTransparency = 0.25
	track.BorderSizePixel = 0
	track.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = track
	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = Color3.new(0, 0, 0)
	trackStroke.Transparency = 0.4
	trackStroke.Thickness = 1
	trackStroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = BAR_HEALTHY
	fill.BorderSizePixel = 0
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = fill

	billboard.Enabled = false
	billboard.Parent = enemy.Root
	enemy.Bar = fill
	enemy.Billboard = billboard
end

-- Estado visible ------------------------------------------------------------------

local function syncHealth(enemy: Enemy)
	local status = enemy.Status
	enemy.Model:SetAttribute("Health", math.ceil(status.Health))
	enemy.Model:SetAttribute("MaxHealth", status.MaxHealth)
	local fraction = math.clamp(status.Health / status.MaxHealth, 0, 1)
	enemy.Bar.Size = UDim2.fromScale(fraction, 1)
	enemy.Bar.BackgroundColor3 = healthColor(fraction)
end

local function setEyes(enemy: Enemy, color: Color3)
	for _, part in enemy.Eyes do
		part.Color = color
	end
end

-- Color de los ojos cuando no está preparando un golpe.
local function restingEyes(enemy: Enemy): Color3
	return if enemy.Enraged then ENRAGED_EYES else enemy.EyeColor
end

-- Velocidad al andar: la base (con furia) y los estados de control. Solo escribe si cambia.
local function refreshSpeed(enemy: Enemy, now: number)
	local base = enemy.Def.WalkSpeed
	if enemy.Enraged and enemy.Def.Enrage then
		base *= enemy.Def.Enrage.SpeedMultiplier
	end
	-- Jefes persiguiendo a quien huye (EnemyConfig.Pursuit; BossAttacks.updateBoss)
	base *= enemy.SpeedBoost or 1
	local speed = EnemyLogic.speed(base, enemy.Control, now)
	if enemy.Humanoid.WalkSpeed ~= speed then
		enemy.Humanoid.WalkSpeed = speed
	end
end

-- Quita todos los estados (al reaparecer, morir o volver a casa).
local function clearControl(enemy: Enemy)
	EnemyLogic.clearControl(enemy.Control)
	for _, attribute in STATUS_ATTRIBUTES do
		enemy.Model:SetAttribute(attribute, nil)
	end
	enemy.Model:SetAttribute("Aura", nil)
	enemy.Model:SetAttribute("AuraUntil", nil)
end

local function setEnraged(enemy: Enemy, enraged: boolean)
	enemy.Enraged = enraged
	enemy.Model:SetAttribute("Enraged", enraged)
	if enemy.Aura then
		enemy.Aura.Enabled = enraged
	end
	if enemy.Glow then
		enemy.Glow.Enabled = enraged
	end
	setEyes(enemy, restingEyes(enemy))
	refreshSpeed(enemy, os.clock())
end

local function burst(position: Vector3, color: Color3, amount: number, rising: boolean?, run: number?)
	local part = Instance.new("Part")
	tagRun(part, run)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.CFrame = CFrame.new(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.LightEmission = 1
	emitter.Color = ColorSequence.new(color)
	emitter.Parent = part
	if rising then
		-- Motas de luz que ascienden: la criatura se disuelve en energía.
		local wisps = Instance.new("ParticleEmitter")
		wisps.Rate = 0
		wisps.Lifetime = NumberRange.new(1, 1.6)
		wisps.Speed = NumberRange.new(2, 4)
		wisps.Acceleration = Vector3.new(0, 8, 0)
		wisps.SpreadAngle = Vector2.new(60, 60)
		wisps.Size = NumberSequence.new(0.6, 0)
		wisps.Transparency = NumberSequence.new(0.1, 1)
		wisps.LightEmission = 1
		wisps.Color = ColorSequence.new(Color3.fromRGB(255, 246, 220), color)
		wisps.Parent = part
		part.Parent = ctx.fxFolder
		wisps:Emit(math.floor(amount / 2))
	end
	part.Parent = ctx.fxFolder
	emitter:Emit(amount)
	Debris:AddItem(part, 2.5)
end

-- Colocación y ciclo de vida ---------------------------------------------------------

local function place(enemy: Enemy)
	local home = enemy.Home
	local position = home + Vector3.new(0, enemy.RootHeight + 0.5 + StudFloor.raiseAt(home.X, home.Z), 0)
	enemy.Model:PivotTo(CFrame.lookAt(position, position + Vector3.new(0, 0, -1)))
	enemy.Root.AssemblyLinearVelocity = Vector3.zero
end

-- La IA de jefe (más abajo, updateBoss) reinicia su estado al reaparecer

local function respawn(enemy: Enemy)
	EnemyLogic.reset(enemy.Status)
	enemy.Target = nil
	clearControl(enemy)
	setEnraged(enemy, false) -- también restablece la velocidad
	enemy.StuckSince = nil
	enemy.LastHomeDistance = math.huge
	local now = os.clock()
	enemy.NextAttack = now + 1
	enemy.WindupUntil = nil
	enemy.NextSlam = now + (if enemy.Def.Slam then enemy.Def.Slam.Interval else math.huge)
	if enemy.Brain then
		resetBrain(enemy, now)
	end
	syncHealth(enemy)
	place(enemy)
	-- La barra de vida permanece oculta hasta que el jugador/mascotas ataquen a este enemigo.
	enemy.Billboard.Enabled = false
	enemy.Model:SetAttribute("AttackAt", nil)
	enemy.Model:SetAttribute("AttackTarget", nil)
	enemy.Model:SetAttribute("SlamAt", nil)
	enemy.Model:SetAttribute("DiedAt", nil)
	enemy.Model:SetAttribute("SpawnedAt", Workspace:GetServerTimeNow())
	enemy.Model.Parent = ctx.folder:FindFirstChild(enemy.ZoneId)
	pcall(function()
		enemy.Root:SetNetworkOwner(nil) -- el servidor controla el movimiento, no los clientes
	end)
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.buildHealthBar = buildHealthBar
	context.burst = burst
	context.clearControl = clearControl
	context.place = place
	context.refreshSpeed = refreshSpeed
	context.respawn = respawn
	context.restingEyes = restingEyes
	context.setEnraged = setEnraged
	context.setEyes = setEyes
	context.syncHealth = syncHealth
end

function Part.link(context: any)
	BAR_DISTANCE = context.BAR_DISTANCE
	BAR_HEALTHY = context.BAR_HEALTHY
	BAR_SIZES = context.BAR_SIZES
	BAR_TRACK = context.BAR_TRACK
	ENRAGED_EYES = context.ENRAGED_EYES
	KIND_NAME_COLORS = context.KIND_NAME_COLORS
	STATUS_ATTRIBUTES = context.STATUS_ATTRIBUTES
end

return Part
