-- Animación y presentación de los enemigos en el cliente (solo visual; no decide nada):
-- - Los modelos del servidor unen sus piezas con Motor6D "Pose" (grupo Body/Arm/Leg y
--   su pivote). Aquí se escribe su Transform: respiración, paso según la velocidad real,
--   preparación y golpe, golpe en área del jefe y retroceso al recibir daño confirmado.
-- - Aparición (sube del suelo y se materializa) y muerte (se hunde y se disuelve en la
--   luz de su zona) a partir de los atributos SpawnedAt / DiedAt del servidor.
-- - Todo se calcula con el reloj compartido (GetServerTimeNow) y los atributos del
--   modelo, así que no hay estado que pueda desincronizarse.
-- - UNA conexión por fotograma para todos los enemigos, solo los cercanos a la cámara;
--   la lista se refresca cada 0,5 s. Los lejanos vuelven a su pose de reposo.

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local EnemyAnimator = {}

local ANIMATE_DISTANCE = 110 -- más lejos no se anima (y queda en reposo)
local REFRESH_SECONDS = 0.5
local APPEAR_SECONDS = 0.6
local DISSOLVE_SECONDS = { Normal = 0.7, Strong = 0.8, Boss = 1.4 } -- < tiempo que el servidor deja el cuerpo
local RECOIL_SECONDS = 0.22

type Motor = { Motor: Motor6D, Group: string, Side: number, Pivot: Vector3 }
type Entry = {
	Model: Model,
	Root: BasePart,
	Motors: { Motor },
	Parts: { BasePart },
	BodyPivot: Vector3,
	HasArms: boolean,
	Scale: number,
	Kind: string,
	Seed: number,
	Phase: number,
	Fade: number,
	Resting: boolean,
	RecoilAt: number,
	RecoilStrength: number,
	SpawnSeen: number?,
	DeathSeen: number?,
	AttackSeen: number?,
}

-- Se rehace en cada refresco con los modelos presentes: no retiene modelos retirados.
local entries: { [Model]: Entry } = {}
local active: { Entry } = {}
local fxFolder: Folder
local onBossSpawn: ((Model) -> ())? = nil
local spawnSound: Sound? = nil

local function entryFor(previous: { [Model]: Entry }, model: Model): Entry?
	local existing = previous[model]
	if existing and existing.Root.Parent == model then
		return existing
	end
	local root = model.PrimaryPart
	if not root then
		return nil
	end
	local motors: { Motor } = {}
	local parts: { BasePart } = {}
	local bodyPivot = root.Position
	local hasArms = false
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Name == "Pose" then
			local group = descendant:GetAttribute("Group")
			local pivot = descendant:GetAttribute("Pivot")
			if typeof(group) == "string" and typeof(pivot) == "Vector3" then
				table.insert(motors, { Motor = descendant, Group = group, Side = tonumber(descendant:GetAttribute("Side")) or 0, Pivot = pivot })
				if group == "Body" then
					bodyPivot = pivot
				elseif group == "Arm" then
					hasArms = true
				end
			end
		elseif descendant:IsA("BasePart") and descendant ~= root and descendant.Transparency < 1 then
			table.insert(parts, descendant)
		end
	end
	if #motors == 0 then
		return nil -- modelo sin articulaciones (versión antigua del servidor): no se anima
	end
	local kind = model:GetAttribute("Kind")
	local entry: Entry = {
		Model = model,
		Root = root,
		Motors = motors,
		Parts = parts,
		BodyPivot = bodyPivot,
		HasArms = hasArms,
		Scale = math.max(root.Size.Y / 2, 1),
		Kind = if typeof(kind) == "string" then kind else "Normal",
		Seed = math.random() * 10,
		Phase = 0,
		Fade = -1, -- fuerza a aplicar la transparencia la primera vez (el modelo puede volver disuelto)
		Resting = true,
		RecoilAt = -math.huge,
		RecoilStrength = 0,
		SpawnSeen = nil,
		DeathSeen = nil,
		AttackSeen = nil,
	}
	-- Lo que ya ocurrió antes de verlo (al entrar en la zona) no se reproduce.
	local spawnedAt = model:GetAttribute("SpawnedAt")
	if typeof(spawnedAt) == "number" and Workspace:GetServerTimeNow() - spawnedAt > 1.5 then
		entry.SpawnSeen = spawnedAt
	end
	return entry
end

local function refreshList()
	table.clear(active)
	local previous = entries
	entries = {}
	local enemies = Workspace:FindFirstChild("Enemies")
	if not enemies then
		return
	end
	for _, zoneFolder in enemies:GetChildren() do
		for _, model in zoneFolder:GetChildren() do
			if model:IsA("Model") and model:GetAttribute("EnemyType") ~= nil then
				local entry = entryFor(previous, model)
				if entry then
					entries[model] = entry
					table.insert(active, entry)
				end
			end
		end
	end
end

-- Efectos de suelo ---------------------------------------------------------------

local function groundRing(position: Vector3, color: Color3, fromDiameter: number, toDiameter: number, seconds: number, transparency: number)
	local ring = Instance.new("Part")
	ring.Name = "EnemyRing"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Shape = Enum.PartType.Cylinder
	ring.Color = color
	ring.Transparency = transparency
	ring.Size = Vector3.new(0.12, fromDiameter, fromDiameter)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = fxFolder
	TweenService:Create(ring, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.04, toDiameter, toDiameter), Transparency = 1 }):Play()
	Debris:AddItem(ring, seconds + 0.1)
end

-- Columna de luz vertical (aparición y derrota de jefes).
local function lightColumn(position: Vector3, color: Color3, height: number, diameter: number, seconds: number)
	local column = Instance.new("Part")
	column.Name = "EnemyColumn"
	column.Anchored = true
	column.CanCollide = false
	column.CanQuery = false
	column.CanTouch = false
	column.CastShadow = false
	column.Material = Enum.Material.Neon
	column.Shape = Enum.PartType.Cylinder
	column.Color = color
	column.Transparency = 0.35
	column.Size = Vector3.new(height, diameter, diameter)
	column.CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	column.Parent = fxFolder
	TweenService:Create(column, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(height, 0.2, 0.2), Transparency = 1 }):Play()
	Debris:AddItem(column, seconds + 0.1)
end

-- Polvo/motas de un solo uso (pocas partículas y se destruye solo).
local function puff(position: Vector3, color: Color3, amount: number, rising: boolean)
	local holder = Instance.new("Part")
	holder.Name = "EnemyPuff"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.CFrame = CFrame.new(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Color = ColorSequence.new(color)
	if rising then
		emitter.Lifetime = NumberRange.new(0.7, 1.2)
		emitter.Speed = NumberRange.new(1, 3)
		emitter.Acceleration = Vector3.new(0, 6, 0)
		emitter.SpreadAngle = Vector2.new(180, 30)
		emitter.Size = NumberSequence.new(0.4, 0)
		emitter.Transparency = NumberSequence.new(0.2, 1)
		emitter.LightEmission = 1
	else
		emitter.Lifetime = NumberRange.new(0.35, 0.6)
		emitter.Speed = NumberRange.new(4, 8)
		emitter.Drag = 4
		emitter.SpreadAngle = Vector2.new(80, 10)
		emitter.Size = NumberSequence.new(0.7, 1.4)
		emitter.Transparency = NumberSequence.new(0.45, 1)
		emitter.LightEmission = 0
	end
	emitter.Parent = holder
	holder.Parent = fxFolder
	emitter:Emit(amount)
	Debris:AddItem(holder, 1.4)
end

local function colorOf(entry: Entry): Color3
	local color = entry.Model:GetAttribute("FxColor")
	return if typeof(color) == "Color3" then color else Color3.fromRGB(200, 230, 210)
end

local function groundBelow(entry: Entry): Vector3
	-- La raíz está a "Hip + mitad de su altura" del suelo; el suelo es la base del modelo.
	local root = entry.Root
	local humanoid = entry.Model:FindFirstChildOfClass("Humanoid")
	local hip = if humanoid then humanoid.HipHeight else 0
	return root.Position - Vector3.new(0, root.Size.Y / 2 + hip - 0.15, 0)
end

local function playSpawnFx(entry: Entry)
	local ground = groundBelow(entry)
	local color = colorOf(entry)
	local radius = entry.Root.Size.X
	if entry.Kind == "Boss" then
		-- Entrada de jefe: columna de luz, doble onda y aviso en pantalla (si está cerca).
		lightColumn(ground, color, 26, radius * 1.6, 1.1)
		groundRing(ground + Vector3.new(0, 0.3, 0), color, radius, radius * 7, 0.9, 0.2)
		task.delay(0.25, groundRing, ground + Vector3.new(0, 0.32, 0), color, radius, radius * 5, 0.7, 0.35)
		puff(ground + Vector3.new(0, 1, 0), color, 26, true)
		if spawnSound then
			spawnSound:Play()
		end
		if onBossSpawn then
			task.spawn(onBossSpawn, entry.Model)
		end
	else
		groundRing(ground + Vector3.new(0, 0.3, 0), color, radius * 0.6, radius * 3.2, 0.55, 0.25)
		puff(ground + Vector3.new(0, 0.6, 0), color, 8, true)
	end
end

local function playDeathFx(entry: Entry)
	local ground = groundBelow(entry)
	local color = colorOf(entry)
	local radius = entry.Root.Size.X
	if entry.Kind == "Boss" then
		lightColumn(ground, color, 34, radius * 2, 1.6)
		groundRing(ground + Vector3.new(0, 0.3, 0), color, radius, radius * 9, 1.2, 0.15)
		puff(ground + Vector3.new(0, 2, 0), color, 40, true)
	else
		groundRing(ground + Vector3.new(0, 0.3, 0), color, radius * 2.4, radius * 0.4, 0.6, 0.3)
	end
end

-- Pose -----------------------------------------------------------------------------

local function setFade(entry: Entry, fade: number)
	-- Se omiten cambios mínimos, pero nunca el valor final (0 o 1): no queda a medias.
	if entry.Fade == fade or (math.abs(entry.Fade - fade) < 0.01 and fade > 0 and fade < 1) then
		return
	end
	entry.Fade = fade
	for _, part in entry.Parts do
		part.LocalTransparencyModifier = fade
	end
end

local function rest(entry: Entry)
	if entry.Resting then
		return
	end
	entry.Resting = true
	for _, motor in entry.Motors do
		motor.Motor.Transform = CFrame.identity
	end
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function easeOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

local function animate(entry: Entry, serverNow: number, clock: number, dt: number)
	local model = entry.Model
	local scale = entry.Scale
	local health = model:GetAttribute("Health")
	local diedAt = model:GetAttribute("DiedAt")
	local spawnedAt = model:GetAttribute("SpawnedAt")
	local dead = typeof(health) == "number" and health <= 0 and typeof(diedAt) == "number"

	-- Aparición / disolución
	local fade: number, sink: number = 0, 0
	if dead then
		if entry.DeathSeen ~= diedAt then
			entry.DeathSeen = diedAt
			if serverNow - diedAt < 0.5 then
				playDeathFx(entry)
			end
		end
		local k = math.clamp((serverNow - diedAt) / (DISSOLVE_SECONDS[entry.Kind] or 0.7), 0, 1)
		fade = k
		sink = k * k * 1.2 * scale
	elseif typeof(spawnedAt) == "number" then
		if entry.SpawnSeen ~= spawnedAt then
			entry.SpawnSeen = spawnedAt
			if serverNow - spawnedAt < 1 then
				playSpawnFx(entry)
			end
		end
		local k = math.clamp((serverNow - spawnedAt) / APPEAR_SECONDS, 0, 1)
		if k < 1 then
			fade = 1 - k
			sink = (1 - easeOut(k)) * 1.4 * scale
		end
	end
	setFade(entry, fade)

	-- Paso según la velocidad real del modelo (la mueve el servidor).
	local velocity = entry.Root.AssemblyLinearVelocity
	local speed = if dead then 0 else Vector2.new(velocity.X, velocity.Z).Magnitude
	local moving = math.clamp(speed / 9, 0, 1.2)
	entry.Phase += dt * (3 + speed * 0.55)
	local swing = math.sin(entry.Phase) * 0.5 * moving
	local breath = math.sin(clock * 2.2 + entry.Seed) * 0.04 * scale

	local pitch = -0.06 * moving -- inclinado hacia delante al correr
	local roll = math.sin(entry.Phase) * 0.05 * moving
	local lift = math.abs(math.sin(entry.Phase)) * 0.14 * scale * moving + breath - sink
	local lunge = 0
	local arms: { [number]: number } = { [1] = -swing * 0.6, [-1] = swing * 0.6 } -- balanceo contrario a las piernas

	if not dead then
		-- Golpe normal: preparación (brazo arriba / encogerse) y golpe.
		local attackAt = model:GetAttribute("AttackAt")
		local windup = model:GetAttribute("AttackWindup")
		if typeof(attackAt) == "number" and typeof(windup) == "number" and windup > 0 then
			local t = serverNow - attackAt
			local side = if math.floor(attackAt * 10) % 2 == 0 then 1 else -1
			local raise: number, bodyPitch: number, forward: number = 0, 0, 0
			if t >= -windup and t < 0 then
				local k = easeOut((t + windup) / windup)
				raise = 2.1 * k
				bodyPitch = 0.14 * k
				forward = -0.15 * k
			elseif t >= 0 and t < 0.12 then
				local k = t / 0.12
				raise = lerp(2.1, 0.4, k)
				bodyPitch = lerp(0.14, -0.22, k)
				forward = lerp(-0.15, 0.6, k)
			elseif t >= 0.12 and t < 0.45 then
				local k = easeOut((t - 0.12) / 0.33)
				raise = lerp(0.4, 0, k)
				bodyPitch = lerp(-0.22, 0, k)
				forward = lerp(0.6, 0, k)
			end
			if t >= 0 and t < 0.3 and entry.AttackSeen ~= attackAt then
				entry.AttackSeen = attackAt
				if entry.Kind ~= "Normal" then
					-- Polvo donde cae el golpe (es la animación, no una confirmación de daño).
					local root = entry.Root
					puff(groundBelow(entry) + root.CFrame.LookVector * (root.Size.Z / 2 + 1.5 * scale) + Vector3.new(0, 0.4, 0), Color3.fromRGB(196, 186, 160), if entry.Kind == "Boss" then 12 else 6, false)
				end
			end
			if entry.HasArms then
				arms[side] = (arms[side] or 0) + raise
				pitch += bodyPitch * 0.6
			else
				-- Sin brazos (Espinillo, Fragmento): se encoge y embiste con el cuerpo.
				pitch += bodyPitch * 1.6
				lift += math.min(0, forward) * 1.5 * scale
			end
			lunge += forward * (if entry.HasArms then 0.4 else 1) * scale
		end

		-- Golpe en área del jefe: ambos brazos arriba durante el aviso y golpe al suelo.
		local slamAt = model:GetAttribute("SlamAt")
		local telegraph = model:GetAttribute("SlamTelegraph")
		if typeof(slamAt) == "number" and typeof(telegraph) == "number" and telegraph > 0 then
			local t = serverNow - slamAt
			local raise: number, bodyPitch: number, rise: number = 0, 0, 0
			if t >= -telegraph and t < 0 then
				local k = easeOut((t + telegraph) / telegraph)
				raise = 2.7 * k
				bodyPitch = 0.2 * k
				rise = 0.12 * k
			elseif t >= 0 and t < 0.14 then
				local k = t / 0.14
				raise = lerp(2.7, 0.7, k)
				bodyPitch = lerp(0.2, -0.32, k)
				rise = lerp(0.12, -0.08, k)
			elseif t >= 0.14 and t < 0.7 then
				local k = easeOut((t - 0.14) / 0.56)
				raise = lerp(0.7, 0, k)
				bodyPitch = lerp(-0.32, 0, k)
				rise = lerp(-0.08, 0, k)
			end
			if raise > 0 or bodyPitch ~= 0 then
				arms[1] = math.max(arms[1] or 0, raise)
				arms[-1] = math.max(arms[-1] or 0, raise)
				pitch += bodyPitch
				lift += rise * scale
			end
		end

		-- Retroceso breve al recibir un golpe confirmado.
		local sinceHit = clock - entry.RecoilAt
		if sinceHit < RECOIL_SECONDS then
			local r = (1 - sinceHit / RECOIL_SECONDS) * entry.RecoilStrength
			pitch += 0.2 * r
			lunge -= 0.25 * scale * r
		end
	end

	-- Composición: el cuerpo gira sobre su pivote; brazos y cabeza lo acompañan, las
	-- piernas no (siguen apoyadas).
	local bodyPivot = entry.BodyPivot
	local body = CFrame.new(bodyPivot + Vector3.new(0, lift, -lunge)) * CFrame.Angles(pitch, 0, roll) * CFrame.new(-bodyPivot)
	for _, motor in entry.Motors do
		local group = motor.Group
		if group == "Body" then
			motor.Motor.Transform = CFrame.new(-motor.Pivot) * body * CFrame.new(motor.Pivot)
		elseif group == "Arm" then
			motor.Motor.Transform = CFrame.new(-motor.Pivot) * body * CFrame.new(motor.Pivot) * CFrame.Angles(arms[motor.Side] or 0, 0, 0)
		elseif group == "Leg" then
			motor.Motor.Transform = CFrame.new(0, -sink, 0) * CFrame.Angles(swing * motor.Side, 0, 0)
		end
	end
	entry.Resting = false
end

-- API ---------------------------------------------------------------------------------

-- Retroceso al recibir un golpe que el servidor ha confirmado (lo llama CombatController).
function EnemyAnimator.react(model: Model, strength: number)
	local entry = entries[model]
	if entry then
		entry.RecoilAt = os.clock()
		entry.RecoilStrength = if entry.Kind == "Boss" then strength * 0.35 else strength
	end
end

-- Limpia los efectos temporales (al morir o cambiar de zona).
function EnemyAnimator.clearEffects()
	if fxFolder then
		fxFolder:ClearAllChildren()
	end
end

-- options.OnBossSpawn: aviso en pantalla cuando aparece un jefe cerca.
-- options.SpawnSound: Id de sonido verificado para la entrada del jefe (o nil).
function EnemyAnimator.start(options: { OnBossSpawn: ((Model) -> ())?, SpawnSound: string? }?)
	onBossSpawn = options and options.OnBossSpawn
	local soundId = options and options.SpawnSound
	if soundId then
		local sound = Instance.new("Sound")
		sound.SoundId = soundId
		sound.Volume = 0.25
		sound.PlaybackSpeed = 0.7 -- más grave: retumbar, no explosión
		sound.Parent = SoundService
		spawnSound = sound
	end

	local existing = Workspace:FindFirstChild("ClientEnemyFX")
	if existing then
		existing:Destroy()
	end
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ClientEnemyFX"
	fxFolder.Parent = Workspace

	local nextRefresh = 0
	RunService.PreSimulation:Connect(function(dt: number)
		local clock = os.clock()
		if clock >= nextRefresh then
			nextRefresh = clock + REFRESH_SECONDS
			refreshList()
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local eye = camera.CFrame.Position
		local serverNow = Workspace:GetServerTimeNow()
		for _, entry in active do
			if entry.Model.Parent == nil or entry.Root.Parent == nil then
				continue
			end
			local distance = (entry.Root.Position - eye).Magnitude
			if distance <= ANIMATE_DISTANCE then
				animate(entry, serverNow, clock, dt)
			else
				rest(entry)
				local health = entry.Model:GetAttribute("Health")
				setFade(entry, if typeof(health) == "number" and health <= 0 then 1 else 0)
			end
		end
	end)
end

return EnemyAnimator
