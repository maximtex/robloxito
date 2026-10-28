-- AbilityController · Helpers: constantes, piezas y emisores de efectos, sonidos, sacudida de cámara, destello y gestos.
-- Parte de AbilityController (ver AbilityController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)

local ctx: any -- tabla de estado compartida (la crea AbilityController/init.luau)
local Api = {} -- funciones públicas de esta parte (init.luau las copia a AbilityController)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local Codes = Constants.PurchaseCodes
local BUTTON_SIZE = 72
local ATTACK_BUTTON = 82 -- botón de ataque de CombatController (abajo a la derecha)
local GAP = 10
local EDGE = 20
local HEAL_COLOR = Color3.fromRGB(140, 255, 160)
local HIT_BOOST = 1.15 -- números de daño de las habilidades algo más grandes que los golpes
local SLOT_ORDER = { "Primary", "Secondary" }
local ABILITY_KINDS = { Roots = true, Heal = true, Burn = true, Gust = true, Chain = true, Frost = true, Curse = true, StarfallCast = true }


local player = Players.LocalPlayer

-- Utilidades de efectos ----------------------------------------------------------------

local function fxPart(size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, transparency: number?, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = material or Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency or 0
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.CFrame = cframe
	part.Parent = ctx.fxFolder
	return part
end

-- Altura del suelo bajo un punto (sin contar personajes, enemigos ni efectos).
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function groundAt(position: Vector3): number
	local ignore = { ctx.fxFolder }
	for _, name in { "Enemies", "ClientPets", "ClientCombatFX" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
	local result = Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0), rayParams)
	return if result then result.Position.Y else position.Y - 3
end

local function flatRing(center: Vector3, diameter: number, color: Color3, duration: number, material: Enum.Material?, transparency: number?)
	local y = groundAt(center) + 0.25
	local ring = fxPart(Vector3.new(0.18, diameter * 0.25, diameter * 0.25), CFrame.new(center.X, y, center.Z) * CFrame.Angles(0, 0, math.rad(90)), color, material, transparency or 0.35, Enum.PartType.Cylinder)
	TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.06, diameter, diameter), Transparency = 1 }):Play()
	Debris:AddItem(ring, duration + 0.1)
	return ring
end

-- Partículas: presets por estilo. Cada ráfaga usa una pieza temporal (se borra sola).
local PRESETS: { [string]: (ParticleEmitter) -> () } = {
	Leaf = function(e)
		e.Lifetime = NumberRange.new(0.6, 1.1)
		e.Speed = NumberRange.new(4, 9)
		e.Acceleration = Vector3.new(0, -6, 0)
		e.SpreadAngle = Vector2.new(70, 70)
		e.Size = NumberSequence.new(0.35, 0.1)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-200, 200)
		e.LightEmission = 0.2
	end,
	Bubble = function(e)
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Speed = NumberRange.new(2, 5)
		e.Acceleration = Vector3.new(0, 6, 0)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.3, 0.45), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new(0.2, 0.9)
		e.LightEmission = 0.6
	end,
	Flame = function(e)
		e.Lifetime = NumberRange.new(0.3, 0.55)
		e.Speed = NumberRange.new(24, 34)
		e.Drag = 3
		e.SpreadAngle = Vector2.new(24, 24)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.5, 1.6), NumberSequenceKeypoint.new(1, 0.2) })
		e.Transparency = NumberSequence.new(0.1, 1)
		e.LightEmission = 1
		e.EmissionDirection = Enum.NormalId.Front
	end,
	Wind = function(e)
		e.Lifetime = NumberRange.new(0.35, 0.6)
		e.Speed = NumberRange.new(28, 40)
		e.SpreadAngle = Vector2.new(18, 18)
		e.Size = NumberSequence.new(0.25, 0)
		e.Transparency = NumberSequence.new(0.2, 1)
		e.LightEmission = 0.8
		e.EmissionDirection = Enum.NormalId.Front
	end,
	Spark = function(e)
		e.Lifetime = NumberRange.new(0.15, 0.35)
		e.Speed = NumberRange.new(10, 18)
		e.Drag = 6
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new(0.3, 0)
		e.LightEmission = 1
	end,
	Snow = function(e)
		e.Lifetime = NumberRange.new(0.7, 1.2)
		e.Speed = NumberRange.new(6, 14)
		e.Drag = 4
		e.SpreadAngle = Vector2.new(180, 30)
		e.Size = NumberSequence.new(0.35, 0)
		e.Rotation = NumberRange.new(0, 360)
		e.LightEmission = 0.8
	end,
	Smoke = function(e)
		e.Lifetime = NumberRange.new(0.6, 1)
		e.Speed = NumberRange.new(2, 5)
		e.Acceleration = Vector3.new(0, 4, 0)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new(0.6, 1.4)
		e.Transparency = NumberSequence.new(0.35, 1)
		e.LightEmission = 0.3
	end,
	Steam = function(e)
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Speed = NumberRange.new(8, 16)
		e.Drag = 3
		e.Acceleration = Vector3.new(0, 5, 0)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3.5) })
		e.Transparency = NumberSequence.new(0.25, 1)
		e.LightEmission = 0.1
	end,
	Star = function(e)
		e.Lifetime = NumberRange.new(0.4, 0.8)
		e.Speed = NumberRange.new(6, 14)
		e.Drag = 3
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.7), NumberSequenceKeypoint.new(1, 0) })
		e.Rotation = NumberRange.new(0, 360)
		e.LightEmission = 1
	end,
}

local function burst(position: Vector3, preset: string, color: Color3, amount: number, facing: Vector3?)
	local cframe = if facing and facing.Magnitude > 0.01 then CFrame.lookAt(position, position + facing) else CFrame.new(position)
	local holder = fxPart(Vector3.one * 0.2, cframe, color, nil, 1)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	PRESETS[preset](emitter)
	emitter.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.35), color)
	emitter.Parent = holder
	emitter:Emit(amount)
	Debris:AddItem(holder, 2)
end

local function flashLight(position: Vector3, color: Color3, range: number, duration: number)
	local holder = fxPart(Vector3.one * 0.2, CFrame.new(position), color, nil, 1)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = 3
	light.Shadows = false
	light.Parent = holder
	TweenService:Create(light, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	Debris:AddItem(holder, duration + 0.1)
end

local function rootOf(target: Player?): BasePart?
	local character = target and target.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function abilityColor(elementId: any): Color3
	local ability = typeof(elementId) == "string" and AbilityConfig.Abilities[elementId] or nil
	return if ability then ability.Color else THEME.Accent
end

-- Sonido en 3D en un punto (se oye cerca; lejos se apaga). spec = { Id, Volume, Pitch }.
local function soundAt(position: Vector3, spec: any)
	if typeof(spec) ~= "table" or typeof(spec.Id) ~= "string" then
		return
	end
	local holder = fxPart(Vector3.one * 0.2, CFrame.new(position), Color3.new(1, 1, 1), nil, 1)
	local sound = Instance.new("Sound")
	sound.SoundId = spec.Id
	sound.Volume = spec.Volume or 0.5
	sound.PlaybackSpeed = (spec.Pitch or 1) * (1 + (math.random() * 2 - 1) * 0.04)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 12
	sound.RollOffMaxDistance = AbilityConfig.Sounds.RollOff or 90
	sound.Parent = holder
	sound:Play()
	Debris:AddItem(holder, 4)
end

-- Texto grande flotante (nombre del combo) sobre un punto.
local function floatingText(position: Vector3, text: string, color: Color3)
	local anchor = fxPart(Vector3.one * 0.1, CFrame.new(position + Vector3.new(0, 4.5, 0)), color, nil, 1)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(60, 20)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 140
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = FONTS.Display
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(20, 18, 30)
	label.TextStrokeTransparency = 0
	label.Text = string.upper(text)
	label.Parent = billboard
	billboard.Parent = anchor
	TweenService:Create(billboard, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(260, 62) }):Play()
	TweenService:Create(billboard, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 2.5, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.9), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1.4)
end

-- Sensación: cámara y destello -------------------------------------------------------------

local trauma = 0 -- 0..1: intensidad de la sacudida (decae sola)
local fovKick = 0 -- grados de zoom momentáneo
local fovApplied = 0

local function reducedMotion(): boolean
	local ok, value = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).ReducedMotion
	end)
	return ok and value == true
end

local function addShake(amount: number)
	trauma = math.clamp(trauma + amount, 0, 1)
end

local function kickFov(amount: number)
	fovKick = math.max(fovKick, amount)
end

-- Para otros controladores (p. ej. el renacimiento): misma sacudida y zoom, que respetan
-- "Reducir movimiento".
Api.shake = addShake
Api.kickFov = kickFov

local function screenFlash(color: Color3, strength: number?)
	local frame = ctx.flashFrame
	if not frame then
		return
	end
	local start = AbilityConfig.ScreenFlash or 0.82
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = start + (1 - start) * (1 - (strength or 1))
	TweenService:Create(frame, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

local function cameraStep(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	-- Zoom momentáneo: se quita el anterior y se pone el nuevo (respeta cambios ajenos).
	fovKick = math.max(0, fovKick - dt * 30)
	if fovApplied ~= 0 or fovKick > 0 then
		local offset = if reducedMotion() then 0 else fovKick
		camera.FieldOfView = math.clamp(camera.FieldOfView + fovApplied - offset, 1, 120)
		fovApplied = offset
	end
	if trauma <= 0 then
		return
	end
	trauma = math.max(0, trauma - dt * 1.8)
	if camera.CameraType == Enum.CameraType.Scriptable or reducedMotion() then
		return
	end
	local strength = trauma * trauma
	local t = os.clock() * 24
	local maxAngle = math.rad(2.2)
	camera.CFrame = camera.CFrame
		* CFrame.Angles(math.noise(t, 1.3) * maxAngle * strength, math.noise(t, 7.1) * maxAngle * strength, math.noise(t, 13.7) * maxAngle * 0.5 * strength)
end

-- Gesto del avatar con las animaciones de su propio script Animate (no se inventa ningún Id).
local gestureCache: { [string]: AnimationTrack } = {}
local gestureCharacter: Model? = nil
local function playGesture(name: any)
	if typeof(name) ~= "string" then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not (character and animator) then
		return
	end
	if gestureCharacter ~= character then
		gestureCharacter = character
		table.clear(gestureCache)
	end
	local track = gestureCache[name]
	if not track then
		local animate = character:FindFirstChild("Animate")
		local folder = animate and animate:FindFirstChild(name)
		local animation = folder and folder:FindFirstChildWhichIsA("Animation")
		if not (animation and animation.AnimationId ~= "") then
			return
		end
		local ok, loaded = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if not (ok and loaded) then
			return
		end
		loaded.Priority = Enum.AnimationPriority.Action
		loaded.Looped = false
		gestureCache[name] = loaded
		track = loaded
	end
	local current = track :: AnimationTrack
	current:Play(0.08, 1, 1.4)
	task.delay(0.55, function()
		if current.IsPlaying then
			current:Stop(0.25)
		end
	end)
end

local Part = { Api = Api }

function Part.install(context: any)
	ctx = context
	context.ABILITY_KINDS = ABILITY_KINDS
	context.ATTACK_BUTTON = ATTACK_BUTTON
	context.BUTTON_SIZE = BUTTON_SIZE
	context.Codes = Codes
	context.EDGE = EDGE
	context.FONTS = FONTS
	context.GAP = GAP
	context.HEAL_COLOR = HEAL_COLOR
	context.HIT_BOOST = HIT_BOOST
	context.SLOT_ORDER = SLOT_ORDER
	context.THEME = THEME
	context.abilityColor = abilityColor
	context.addShake = addShake
	context.burst = burst
	context.cameraStep = cameraStep
	context.flashLight = flashLight
	context.flatRing = flatRing
	context.floatingText = floatingText
	context.fxPart = fxPart
	context.groundAt = groundAt
	context.kickFov = kickFov
	context.playGesture = playGesture
	context.player = player
	context.rootOf = rootOf
	context.screenFlash = screenFlash
	context.soundAt = soundAt
end

function Part.link(context: any)
	-- (nada que enlazar)
end

return Part
