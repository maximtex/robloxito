-- StyleController · SecondaryFx: efectos de Furia, Torbellino, Rayos, Agujero negro, dash, Guerrero (Salto y Onda), Teletransporte y combos.
-- Parte de StyleController (ver StyleController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local StyleConfig = require(Shared.Config.StyleConfig)
local Toasts = require(script.Parent.Parent.Parent.UI.Toasts)
local CombatController = require(script.Parent.Parent.CombatController)
local CharacterPose = require(script.Parent.Parent.CharacterPose)
local StyleAnimations = require(script.Parent.Parent.StyleAnimations)
local WaveFx = require(script.Parent.Parent.WaveFx)

local ctx: any -- tabla de estado compartida (la crea StyleController/init.luau)
local FONTS: any
local INK: any
local player: any

-- Funciones de las otras partes
local function fxPart(...) return ctx.fxPart(...) end
local function groundBelow(...) return ctx.groundBelow(...) end
local function playSound(...) return ctx.playSound(...) end

-- Furia: aura roja alrededor del personaje mientras dura
local function rageFx(owner: Player, duration: number)
	local character = owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local color = ctx.tint or Color3.fromRGB(255, 70, 50)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "StyleRage"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 200, 120), color)
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Rate = 55
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.6, 0)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Parent = root
	Debris:AddItem(emitter, duration)
	local glow = Instance.new("PointLight")
	glow.Name = "StyleRageLight"
	glow.Color = color
	glow.Range = 12
	glow.Brightness = 2
	glow.Parent = root
	Debris:AddItem(glow, duration)
	CharacterPose.charge(character)
	WaveFx.ring(groundBelow(root.Position), color, 2, 16, 0.5, 0.1)
	if owner == player then
		WaveFx.flash(color, 0.2)
	end
	playSound("Rage", if owner == player then nil else root.Position)
end

-- Torbellino: el personaje gira con un anillo de viento a su alrededor
local function whirlFx(owner: Player, radius: number, pulses: number, interval: number)
	local character = owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local color = ctx.tint or StyleConfig.Styles.Fists.Color
	local blades = {}
	for index = 1, 6 do
		local blade = fxPart(Vector3.new(0.4, 3.2, radius * 0.45), root.CFrame, color)
		blade.Transparency = 0.45
		blades[index] = blade
	end
	local total = math.max(0.3, pulses * interval)
	local began = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - began
		if t >= total or not root.Parent then
			connection:Disconnect()
			for _, blade in blades do
				blade:Destroy()
			end
			return
		end
		for index, blade in blades do
			local angle = t * 14 + index / #blades * math.pi * 2
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * 0.6
			blade.CFrame = CFrame.lookAt(root.Position + offset, root.Position + offset + Vector3.new(-math.sin(angle), 0, math.cos(angle)))
		end
	end)
	for pulse = 0, pulses - 1 do
		task.delay(pulse * interval, CharacterPose.punch, character)
	end
	playSound("Whirl", if owner == player then nil else root.Position)
end
local function whirlHitFx(owner: Player, position: Vector3, radius: number, hits: any)
	local color = ctx.tint or StyleConfig.Styles.Fists.Color
	WaveFx.ring(groundBelow(position), color, 2, radius * 2, 0.3, 0.3)
	CombatController.showHits(hits, color, owner == player, 0.9)
	if owner == player and typeof(hits) == "table" and #hits > 0 then
		WaveFx.shake(0.12)
	end
end

-- Cadena de rayos: zigzag de un enemigo a otro
local LIGHTNING = Color3.fromRGB(255, 235, 120)
local function zigzag(from: Vector3, to: Vector3, color: Color3)
	local points = { from }
	local segments = math.clamp(math.floor((to - from).Magnitude / 4), 2, 7)
	for index = 1, segments - 1 do
		local base = from:Lerp(to, index / segments)
		table.insert(points, base + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2.2)
	end
	table.insert(points, to)
	for index = 1, #points - 1 do
		CombatController.beam(points[index], points[index + 1], color, 0.35)
	end
end
local function lightningFx(owner: Player, points: any, hits: any)
	if typeof(points) ~= "table" then
		return
	end
	local purple = StyleConfig.Styles.Magic.Color
	local bolt = ctx.tint or LIGHTNING
	CharacterPose.cast(owner.Character, 0.2)
	local start = CharacterPose.handPosition(owner.Character)
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			if index == 1 and start then
				a = start
			end
			task.delay((index - 1) * 0.05, function()
				zigzag(a, b, bolt)
				zigzag(a, b, purple)
				CombatController.emitAt("Spark", b, bolt, 8)
			end)
		end
	end
	CombatController.showHits(hits, bolt, owner == player, 1.05)
	if owner == player then
		WaveFx.flash(bolt, 0.12)
	end
	playSound("Lightning", if owner == player then nil else (if typeof(points[1]) == "Vector3" then points[1] else nil))
end

-- Agujero negro: esfera oscura que crece, anillo morado girando y, al final, la explosión
local function blackHoleFx(owner: Player, position: Vector3, radius: number, duration: number)
	local purple = ctx.tint or StyleConfig.Styles.Magic.Color
	local ground = groundBelow(position)
	local center = ground + Vector3.new(0, 2.5, 0)
	local core = fxPart(Vector3.one * 0.5, CFrame.new(center), Color3.fromRGB(12, 6, 24))
	core.Shape = Enum.PartType.Ball
	core.Material = Enum.Material.SmoothPlastic
	TweenService:Create(core, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.one * 4 }):Play()
	local halo = fxPart(Vector3.one * 5, CFrame.new(center), purple)
	halo.Shape = Enum.PartType.Ball
	halo.Transparency = 0.7
	local ring = fxPart(Vector3.new(0.2, radius * 1.6, radius * 1.6), CFrame.new(ground + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), purple)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.75
	local swirl = Instance.new("ParticleEmitter")
	swirl.Color = ColorSequence.new(purple, Color3.fromRGB(40, 10, 70))
	swirl.LightEmission = 0.6
	swirl.Lifetime = NumberRange.new(0.5, 0.8)
	swirl.Rate = 70
	swirl.Speed = NumberRange.new(-14, -10) -- hacia dentro
	swirl.SpreadAngle = Vector2.new(180, 180)
	swirl.Size = NumberSequence.new(0.5, 0.1)
	swirl.Parent = halo
	local light = Instance.new("PointLight")
	light.Color = purple
	light.Range = 16
	light.Brightness = 2
	light.Parent = halo
	local began = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - began
		if t >= duration or not ring.Parent then
			connection:Disconnect()
			return
		end
		ring.CFrame = CFrame.new(ground + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, t * 4, math.rad(90))
		halo.Size = Vector3.one * (5 + math.sin(t * 9) * 0.6)
	end)
	for _, part in { core, halo, ring } do
		Debris:AddItem(part, duration + 0.1)
	end
	playSound("BlackHole", if owner == player then nil else position)
end
local function blackHoleBlastFx(owner: Player, position: Vector3, radius: number, hits: any)
	local purple = ctx.tint or StyleConfig.Styles.Magic.Color
	local ground = groundBelow(position)
	local ball = fxPart(Vector3.one * 3, CFrame.new(ground + Vector3.new(0, 2.5, 0)), purple)
	ball.Shape = Enum.PartType.Ball
	ball.Transparency = 0.1
	TweenService:Create(ball, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * radius * 1.8, Transparency = 1, Color = Color3.new(1, 1, 1) }):Play()
	Debris:AddItem(ball, 0.45)
	WaveFx.ring(ground, purple, 2, radius * 2.2, 0.5, 0.05)
	WaveFx.sparkle(ground + Vector3.new(0, 1.5, 0), purple, 26)
	CombatController.showHits(hits, purple, owner == player, 1.25)
	if owner == player then
		WaveFx.shake(0.4)
		WaveFx.flash(purple, 0.2)
	end
	playSound("NovaBlast", if owner == player then nil else position)
end

-- Dash de Puños: estela corta
local function quickDashFx(owner: Player, from: Vector3, to: Vector3)
	local color = StyleConfig.Styles.Fists.Color
	local offset = to - from
	local distance = offset.Magnitude
	if distance > 0.5 then
		local trail = fxPart(Vector3.new(2.5, 0.15, distance), CFrame.lookAt(from:Lerp(to, 0.5), to) * CFrame.new(0, -1.8, 0), color)
		trail.Transparency = 0.5
		TweenService:Create(trail, TweenInfo.new(0.3), { Transparency = 1, Size = Vector3.new(0.3, 0.1, distance) }):Play()
		Debris:AddItem(trail, 0.35)
		local ghost = fxPart(Vector3.new(2, 4.5, 1), CFrame.lookAt(from:Lerp(to, 0.4), to), color)
		ghost.Transparency = 0.6
		TweenService:Create(ghost, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		Debris:AddItem(ghost, 0.35)
	end
	if owner == player then
		WaveFx.kick(2)
	end
	playSound("Dash", if owner == player then nil else from)
end

-- Guerrero: Salto aplastante. Tu cliente hace el salto (tu personaje es tuyo: el servidor
-- solo te pone en el sitio si no llegaste); todos ven la estela y el aviso donde caerá.
local function leapMove(from: Vector3, to: Vector3, delay: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid) then
		return
	end
	local flat = Vector3.new(to.X - root.Position.X, 0, to.Z - root.Position.Z)
	local seconds = math.max(0.2, delay)
	local horizontal = flat / seconds
	if flat.Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "LeapAttachment"
	attachment.Parent = root
	local mover = Instance.new("LinearVelocity")
	mover.Name = "LeapMover"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.PlaneVelocity = Vector2.new(horizontal.X, horizontal.Z)
	mover.MaxForce = math.huge
	mover.Parent = root
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	-- Sube y baja en el tiempo del salto (la gravedad hace el resto)
	root.AssemblyLinearVelocity = Vector3.new(horizontal.X, Workspace.Gravity * seconds / 2, horizontal.Z)
	task.delay(seconds, function()
		mover:Destroy()
		attachment:Destroy()
		if root.Parent then
			root.AssemblyLinearVelocity = Vector3.new(0, math.min(root.AssemblyLinearVelocity.Y, 0), 0)
		end
	end)
end

local function leapFx(owner: Player, from: Vector3, to: Vector3, delay: number, radius: number)
	local color = ctx.tint or StyleConfig.Styles.Warrior.Color
	local character = owner.Character
	CharacterPose.slam(character)
	if owner == player then
		leapMove(from, to, delay)
	end
	-- Aviso en el suelo donde vas a caer
	local ground = groundBelow(to)
	local mark = fxPart(Vector3.new(0.15, radius * 2, radius * 2), CFrame.new(ground + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), color)
	mark.Shape = Enum.PartType.Cylinder
	mark.Transparency = 0.75
	local inner = fxPart(Vector3.new(0.2, 0.5, 0.5), mark.CFrame, color)
	inner.Shape = Enum.PartType.Cylinder
	inner.Transparency = 0.4
	TweenService:Create(inner, TweenInfo.new(delay, Enum.EasingStyle.Linear), { Size = Vector3.new(0.2, radius * 2, radius * 2), Transparency = 0.6 }):Play()
	Debris:AddItem(mark, delay + 0.05)
	Debris:AddItem(inner, delay + 0.05)
	-- Estela del personaje en el aire
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(0, 1.2, 0)
		top.Parent = root
		local bottom = Instance.new("Attachment")
		bottom.Position = Vector3.new(0, -1.2, 0)
		bottom.Parent = root
		local trail = Instance.new("Trail")
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Lifetime = 0.25
		trail.LightEmission = 1
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		trail.Transparency = NumberSequence.new(0.3, 1)
		trail.Parent = root
		Debris:AddItem(trail, delay + 0.3)
		Debris:AddItem(top, delay + 0.3)
		Debris:AddItem(bottom, delay + 0.3)
	end
	playSound("Dash", if owner == player then nil else from)
end

-- Guerrero: Onda cortante (y Corte dimensional): una media luna que vuela de `from` a `to`
local function slashWaveFx(owner: Player, from: Vector3, to: Vector3, width: number, hits: any)
	local color = ctx.tint or StyleConfig.Styles.Warrior.Color
	if not StyleAnimations.enabled("Warrior") then
		CharacterPose.slash(owner.Character, 3)
	elseif owner == player then
		StyleAnimations.slash(1)
	end
	local offset = to - from
	local distance = offset.Magnitude
	if distance > 0.5 then
		local direction = offset.Unit
		local travel = math.clamp(distance / 90, 0.15, 0.6)
		local pieces = 9
		local arc = math.rad(130)
		local glow = color:Lerp(Color3.new(1, 1, 1), 0.3)
		for index = 1, pieces do
			local t = (index - 0.5) / pieces
			local angle = -arc / 2 + arc * t
			-- Media luna: las puntas van un poco por detrás del centro
			local local0 = Vector3.new(math.sin(angle) * width * 0.6, 0, -math.cos(angle) * width * 0.25)
			local base = CFrame.lookAt(from, from + direction)
			local start = base * CFrame.new(local0)
			local piece = fxPart(Vector3.new(0.2, 1.2 * (1 - math.abs(t - 0.5)) + 0.4, width * 0.6 * arc / pieces + 0.3), start * CFrame.Angles(0, angle + math.rad(90), 0), glow)
			piece.Transparency = 0.1
			local finish = CFrame.lookAt(to, to + direction) * CFrame.new(local0) * CFrame.Angles(0, angle + math.rad(90), 0)
			TweenService:Create(piece, TweenInfo.new(travel, Enum.EasingStyle.Linear), { CFrame = finish }):Play()
			TweenService:Create(piece, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, travel - 0.1), { Transparency = 1 }):Play()
			Debris:AddItem(piece, travel + 0.1)
		end
	end
	CombatController.showHits(hits, color, owner == player, 1.1)
	if owner == player then
		WaveFx.kick(3)
	end
	playSound("SwordSpin", if owner == player then nil else from)
end

-- Magia: Teletransporte. Destello donde estabas y donde apareces, y una estela entre ambos
local function blinkFx(owner: Player, from: Vector3, to: Vector3)
	local color = StyleConfig.Styles.Magic.Color
	for _, at in { from, to } do
		local ball = fxPart(Vector3.one * 1, CFrame.new(at), color)
		ball.Shape = Enum.PartType.Ball
		ball.Transparency = 0.2
		TweenService:Create(ball, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 6, Transparency = 1 }):Play()
		Debris:AddItem(ball, 0.35)
		WaveFx.sparkle(at, color, 14)
	end
	local distance = (to - from).Magnitude
	if distance > 0.5 then
		local streak = fxPart(Vector3.new(0.5, 0.5, distance), CFrame.lookAt(from:Lerp(to, 0.5), to), Color3.new(1, 1, 1))
		streak.Transparency = 0.4
		TweenService:Create(streak, TweenInfo.new(0.25), { Transparency = 1, Size = Vector3.new(0.05, 0.05, distance) }):Play()
		Debris:AddItem(streak, 0.3)
	end
	if owner == player then
		WaveFx.kick(2)
	end
	playSound("Blink", if owner == player then nil else from)
end

-- Combo: su nombre grande sobre el enemigo (y un aviso para quien lo hizo)
local COMBO_COLORS = { Weapons = Color3.fromRGB(120, 220, 255), Warrior = Color3.fromRGB(255, 120, 130), Fists = Color3.fromRGB(255, 170, 80), Magic = Color3.fromRGB(210, 150, 255) }
local function comboFx(owner: Player, name: string, position: Vector3, style: string?)
	local color = COMBO_COLORS[style or ""] or Color3.fromRGB(255, 220, 90)
	local anchor = fxPart(Vector3.one * 0.2, CFrame.new(position + Vector3.new(0, 4, 0)), color)
	anchor.Transparency = 1
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(60, 20)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 120
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = FONTS.Display
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeColor3 = INK
	label.TextStrokeTransparency = 0
	label.Text = "💥 " .. name
	label.Parent = billboard
	billboard.Parent = anchor
	TweenService:Create(billboard, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(240, 60) }):Play()
	TweenService:Create(billboard, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1.25)
	CombatController.emitAt("Glint", position, color, 14)
	if owner == player then
		Toasts.show(("💥 %s"):format(name), { Style = "Line", Color = color, Key = "StyleCombo" })
		playSound("Combo")
	end
end

-- Rebote del botón con su propia escala de pulsar (UiKit.addStates): no se apilan UIScale.
local function bounce(button: GuiObject, amount: number)
	local scale = button:FindFirstChild("PressScale")
	if scale and scale:IsA("UIScale") then
		scale.Scale = 1 + amount
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.blackHoleBlastFx = blackHoleBlastFx
	context.blackHoleFx = blackHoleFx
	context.blinkFx = blinkFx
	context.bounce = bounce
	context.comboFx = comboFx
	context.leapFx = leapFx
	context.lightningFx = lightningFx
	context.quickDashFx = quickDashFx
	context.rageFx = rageFx
	context.slashWaveFx = slashWaveFx
	context.whirlFx = whirlFx
	context.whirlHitFx = whirlHitFx
end

function Part.link(context: any)
	FONTS = context.FONTS
	INK = context.INK
	player = context.player
end

return Part
