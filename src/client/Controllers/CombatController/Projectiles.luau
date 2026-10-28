-- CombatController · Projectiles: sacudida de cámara, embestida de puños, orbes, flechas, cohetes y tajos.
-- Parte de CombatController (ver CombatController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local WaveVisibility = require(script.Parent.Parent.WaveVisibility)

local ctx: any -- tabla de estado compartida (la crea CombatController/init.luau)
local PUNCH_CROWD_RADIUS: any
local PUNCH_LUNGE_MAX: any
local PUNCH_LUNGE_SPEED: any
local PUNCH_MAX_RISE: any
local PUNCH_MAX_SPEED: any
local SELECT_RANGE: any

-- Funciones de las otras partes
local function fxPart(...) return ctx.fxPart(...) end

-- Sacudida y zoom de la cámara de AbilityController (se pide al usarla: AbilityController
-- también requiere este módulo). Respetan "Reducir movimiento".
local cameraFx: any = nil
local function shakeCamera(amount: number, fov: number?)
	if cameraFx == nil then
		local ok, module = pcall(require, script.Parent.Parent.AbilityController)
		cameraFx = if ok then module else false
	end
	if cameraFx then
		if cameraFx.shake then
			cameraFx.shake(amount)
		end
		if fov and cameraFx.kickFov then
			cameraFx.kickFov(fov)
		end
	end
end

-- ¿Hay otro bicho pegado a ti (aparte del que golpeas)? Entonces no te lanzas: empujarte
-- entre varios cuerpos te mandaría volando.
local function crowded(root: BasePart, target: any): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent :: Instance, ctx.fxFolder }
	for _, part in Workspace:GetPartBoundsInRadius(root.Position, PUNCH_CROWD_RADIUS, params) do
		local node: Instance? = part.Parent
		while node and node ~= Workspace do
			if node:IsA("Model") and node:GetAttribute("EnemyType") ~= nil then
				if node ~= target then
					return true
				end
				break
			end
			node = node.Parent
		end
	end
	return false
end

-- Tras cada puñetazo, un momento sin salir disparado: si algún choque con los bichos te lanza
-- más rápido de lo normal, se frena (andar, saltar y el dash no llegan a esas velocidades)
local steadyUntil = 0
local steadyRoot: BasePart? = nil
local steadyConnection: RBXScriptConnection? = nil
local function keepSteady(root: BasePart, seconds: number)
	steadyUntil = math.max(steadyUntil, os.clock() + seconds)
	steadyRoot = root
	if steadyConnection then
		return
	end
	steadyConnection = RunService.Heartbeat:Connect(function()
		local current = steadyRoot
		if os.clock() > steadyUntil or not (current and current.Parent) then
			if steadyConnection then
				steadyConnection:Disconnect()
				steadyConnection = nil
			end
			return
		end
		if current:FindFirstChild("PunchLunge") then
			return -- la embestida misma sí va rápida
		end
		local velocity = current.AssemblyLinearVelocity
		local flat = Vector3.new(velocity.X, 0, velocity.Z)
		if flat.Magnitude > PUNCH_MAX_SPEED or velocity.Y > PUNCH_MAX_RISE then
			current.AssemblyLinearVelocity = Vector3.new(0, math.min(velocity.Y, 0), 0)
			current.AssemblyAngularVelocity = Vector3.zero
		end
	end)
end

-- Tu personaje se echa hacia delante `distance` studs para que el puño llegue de verdad: sin
-- cruzar paredes ni meterse en otros bichos, y sin lanzarse si tienes varios encima.
-- Devuelve cuánto dura la embestida (0 si no hace falta).
local lungeMover: LinearVelocity? = nil
local function lunge(root: BasePart, direction: Vector3, distance: number, target: any): number
	distance = math.min(distance, PUNCH_LUNGE_MAX)
	if distance < 0.6 or crowded(root, target) then
		return 0
	end
	-- Un cuerpo del ancho del tuyo a lo largo del camino: se para antes de lo primero que toque
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent :: Instance, ctx.fxFolder }
	local blocked = Workspace:Spherecast(root.Position, 1.2, direction * (distance + 1), params)
	if blocked then
		distance = math.min(distance, blocked.Distance - 0.5)
	end
	if distance < 0.6 then
		return 0
	end
	local seconds = math.clamp(distance / PUNCH_LUNGE_SPEED, 0.05, 0.1)
	if lungeMover then
		lungeMover:Destroy()
	end
	local attachment = root:FindFirstChild("PunchLungeAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "PunchLungeAttachment"
		attachment.Parent = root
	end
	local velocity = direction * (distance / seconds)
	local mover = Instance.new("LinearVelocity")
	mover.Name = "PunchLunge"
	mover.Attachment0 = attachment :: Attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	-- Fuerza justa para tu peso: si choca con algo, se queda ahí en vez de atravesarlo
	mover.MaxForce = math.max(root.AssemblyMass, 1) * 2500
	mover.Parent = root
	lungeMover = mover
	root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
	keepSteady(root, seconds + 0.6)
	task.delay(seconds, function()
		if lungeMover == mover then
			lungeMover = nil
			mover:Destroy()
			-- Sin pasarse de largo
			if root.Parent then
				root.AssemblyLinearVelocity = Vector3.new(0, math.min(root.AssemblyLinearVelocity.Y, 0), 0)
			end
		end
	end)
	return seconds
end

-- Orbe mágico: se carga en la mano (crece) y luego viaja girando, con chispas, hasta el
-- objetivo; al llegar llama a `onArrive`. `scale`: más grande (el gran orbe del combo).
local function magicOrb(hand: Vector3, target: Vector3, color: Color3, onArrive: () -> (), scale: number?)
	local charge = 0.14
	local orb = fxPart(Vector3.one * 0.3, CFrame.new(hand), color)
	orb.Shape = Enum.PartType.Ball
	orb.Transparency = 0.1
	local core = fxPart(Vector3.one * 0.15, CFrame.new(hand), Color3.new(1, 1, 1))
	core.Shape = Enum.PartType.Ball
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = 10
	glow.Brightness = 2
	glow.Parent = orb
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new(0.3, 0)
	sparkles.Transparency = NumberSequence.new(0.1, 1)
	sparkles.Lifetime = NumberRange.new(0.25, 0.45)
	sparkles.Speed = NumberRange.new(1, 3)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Rate = 70
	sparkles.Parent = orb
	TweenService:Create(orb, TweenInfo.new(charge, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.one * 1.8 * (scale or 1) }):Play()
	TweenService:Create(core, TweenInfo.new(charge), { Size = Vector3.one * 0.8 * (scale or 1) }):Play()
	task.delay(charge, function()
		if not orb.Parent then
			return
		end
		local start = orb.Position
		local travel = math.clamp((target - start).Magnitude / 48, 0.12, 0.6)
		local began = os.clock()
		local side = (target - start):Cross(Vector3.yAxis)
		side = if side.Magnitude > 0.01 then side.Unit else Vector3.xAxis
		local connection
		connection = game:GetService("RunService").RenderStepped:Connect(function()
			local t = math.clamp((os.clock() - began) / travel, 0, 1)
			-- Recorrido con un pequeño arco y un giro en espiral
			local position = start:Lerp(target, t) + Vector3.new(0, math.sin(t * math.pi) * 1.4, 0) + side * math.sin(t * math.pi * 3) * 0.6 * (1 - t)
			orb.CFrame = CFrame.new(position)
			core.CFrame = CFrame.new(position)
			if t >= 1 then
				connection:Disconnect()
				orb:Destroy()
				core:Destroy()
				onArrive()
			end
		end)
	end)
	Debris:AddItem(orb, 2)
	Debris:AddItem(core, 2)
end

-- Onda de una explosión en el suelo, del radio del daño en área
local function impactRing(center: Vector3, radius: number, color: Color3)
	local diameter = radius * 2
	local wave = fxPart(Vector3.new(0.2, diameter * 0.4, diameter * 0.4), CFrame.new(center - Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color)
	wave.Shape = Enum.PartType.Cylinder
	wave.Transparency = 0.35
	TweenService:Create(wave, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, diameter, diameter), Transparency = 1 }):Play()
	Debris:AddItem(wave, 0.4)
end

-- Flecha o virote del Arquero (antes el trazo de una bala): asta de madera con la punta del
-- color del arma y una estela, que vuela de `from` a `to` muy rápido y se queda clavada un
-- momento. `scale`: tamaño (la arbalesta, más grande; los virotes de abanico, más pequeños).
local ARROW_SPEED = 230
local ARROW_WOOD = Color3.fromRGB(150, 108, 66)
local function arrowFx(from: Vector3, to: Vector3, color: Color3, scale: number?)
	local s = scale or 1
	local distance = (to - from).Magnitude
	if distance < 0.5 then
		return
	end
	local direction = (to - from).Unit
	local length = 1.8 * s
	local shaft = fxPart(Vector3.new(0.08 * s, 0.08 * s, length), CFrame.lookAt(from, from + direction), ARROW_WOOD)
	shaft.Material = Enum.Material.Wood
	local head = fxPart(Vector3.new(0.16, 0.16, 0.32) * s, CFrame.lookAt(from + direction * (length / 2), from + direction * (length / 2 + 1)), color)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.07 * s, length / 2)
	a0.Parent = shaft
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.07 * s, length / 2)
	a1.Parent = shaft
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.4))
	trail.Transparency = NumberSequence.new(0.35, 1)
	trail.Lifetime = 0.12
	trail.LightEmission = 0.8
	trail.FaceCamera = true
	trail.Parent = shaft
	local seconds = math.clamp(distance / ARROW_SPEED, 0.04, 0.5)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Linear)
	local stuckAt = to - direction * (length * 0.35)
	TweenService:Create(shaft, info, { CFrame = CFrame.lookAt(stuckAt, stuckAt + direction) }):Play()
	TweenService:Create(head, info, { CFrame = CFrame.lookAt(stuckAt + direction * (length / 2), stuckAt + direction * (length / 2 + 1)) }):Play()
	task.delay(seconds + 0.25, function()
		for _, part in { shaft, head } do
			if part.Parent then
				TweenService:Create(part, TweenInfo.new(0.2), { Transparency = 1 }):Play()
			end
		end
	end)
	Debris:AddItem(shaft, seconds + 0.5)
	Debris:AddItem(head, seconds + 0.5)
end

-- Virote con bomba de brea de la balista (antes el cohete de la bazuca): viaja de `from` a `to`
-- en `seconds` dejando humo (la explosión la dibuja el aviso "ShotImpact")
local function rocketFx(from: Vector3, to: Vector3, color: Color3, seconds: number)
	local rocket = fxPart(Vector3.new(0.45, 0.45, 2.2), CFrame.lookAt(from, to), color)
	rocket.Material = Enum.Material.Neon
	local tail = Instance.new("Attachment")
	tail.Position = Vector3.new(0, 0, 0.7)
	tail.Parent = rocket
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(255, 200, 120), Color3.fromRGB(90, 90, 96))
	smoke.Size = NumberSequence.new(0.5, 1.6)
	smoke.Transparency = NumberSequence.new(0.2, 1)
	smoke.Lifetime = NumberRange.new(0.3, 0.6)
	smoke.Speed = NumberRange.new(0.5, 1.5)
	smoke.Rate = 90
	smoke.LightEmission = 0.4
	smoke.Parent = tail
	local tween = TweenService:Create(rocket, TweenInfo.new(math.max(0.05, seconds), Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(to, to + (to - from).Unit) })
	tween.Completed:Once(function()
		rocket:Destroy()
	end)
	tween:Play()
	Debris:AddItem(rocket, seconds + 0.5)
end

-- Tajo de espada: un arco brillante que barre delante del personaje (`step` 1 de derecha a
-- izquierda, 2 al revés) o una rueda completa (el giro). Las piezas aparecen una tras otra.
local function slashArc(center: Vector3, direction: Vector3, radius: number, color: Color3, step: number, big: boolean?)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	flat = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)
	local base = CFrame.lookAt(center, center + flat)
	local full = step == 3
	local segments = if full then 18 else 9
	local spread = if full then 360 else 150
	local sweep = if step == 2 then -1 else 1
	local distance = math.max(2.5, radius * 0.7)
	local chord = 2 * distance * math.sin(math.rad(spread / segments) / 2) + 0.4
	local glow = color:Lerp(Color3.new(1, 1, 1), 0.35)
	for index = 1, segments do
		local t = (index - 0.5) / segments
		local angle = math.rad((-spread / 2 + spread * t) * sweep)
		local outward = base:VectorToWorldSpace(Vector3.new(math.sin(angle), 0, -math.cos(angle)))
		local position = center + outward * distance + Vector3.new(0, 0.2, 0)
		task.delay((index - 1) * (if full then 0.012 else 0.016), function()
			local piece = fxPart(Vector3.new(0.14, if big then 1.3 else 0.8, chord), CFrame.lookAt(position, position + outward:Cross(Vector3.yAxis)), glow)
			piece.Transparency = 0.15
			TweenService:Create(piece, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1, Size = Vector3.new(0.05, 0.2, chord) }):Play()
			Debris:AddItem(piece, 0.22)
		end)
	end
end

-- Enemigos vivos a tiro del personaje (Workspace.Enemies.<Zona>.<Modelo>)
local function enemiesInRange(origin: Vector3): { { Model: Model, Position: Vector3 } }
	local list = {}
	local enemiesFolder = Workspace:FindFirstChild("Enemies")
	if not enemiesFolder then
		return list
	end
	for _, zoneFolder in enemiesFolder:GetChildren() do
		for _, model in zoneFolder:GetChildren() do
			local enemyRoot = model:IsA("Model") and model:FindFirstChild("HumanoidRootPart")
			local health = model:GetAttribute("Health")
			-- Oleadas privadas: solo los de mi "mundo" (WaveVisibility)
			if enemyRoot and enemyRoot:IsA("BasePart") and (health == nil or health > 0) and model:GetAttribute("DiedAt") == nil and WaveVisibility.isVisible(model) then
				local offset = enemyRoot.Position - origin
				if Vector2.new(offset.X, offset.Z).Magnitude <= SELECT_RANGE then
					table.insert(list, { Model = model, Position = enemyRoot.Position })
				end
			end
		end
	end
	return list
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.arrowFx = arrowFx
	context.enemiesInRange = enemiesInRange
	context.impactRing = impactRing
	context.keepSteady = keepSteady
	context.lunge = lunge
	context.magicOrb = magicOrb
	context.rocketFx = rocketFx
	context.shakeCamera = shakeCamera
	context.slashArc = slashArc
end

function Part.link(context: any)
	PUNCH_CROWD_RADIUS = context.PUNCH_CROWD_RADIUS
	PUNCH_LUNGE_MAX = context.PUNCH_LUNGE_MAX
	PUNCH_LUNGE_SPEED = context.PUNCH_LUNGE_SPEED
	PUNCH_MAX_RISE = context.PUNCH_MAX_RISE
	PUNCH_MAX_SPEED = context.PUNCH_MAX_SPEED
	SELECT_RANGE = context.SELECT_RANGE
end

return Part
