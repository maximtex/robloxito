-- Habilidades elementales en el cliente (solo presentación y entrada; el servidor decide todo):
-- - Dos botones redondos junto al de ataque: ★ Q (elemento principal) y ◆ R (secundario,
--   cuando lo hay). Cada uno con el icono y el nombre de su habilidad y la recarga de SU
--   elemento que confirma el servidor (AbilityResult). Mando: Y (principal) y B (secundario).
-- - Efectos de cada habilidad y de cada combo SOLO para acciones ya resueltas (AbilityEvent).
--   Los números de daño y destellos reutilizan los del combate (CombatController).
-- - Sensación para quien la lanza: sacudida de cámara, pequeño golpe de zoom, destello de
--   pantalla del color del elemento y gesto del avatar (animaciones de su script Animate).
--   Con "Reducir movimiento" activado en los ajustes de Roblox no hay sacudida ni zoom.
-- - Sonidos por elemento y por combo (AbilityConfig.Sounds), en 3D donde ocurre.
-- - Estados sobre los enemigos (quemado, ralentizado, inmovilizado, aturdido, marcado) y su
--   marca elemental para los combos (icono sobre la barra de vida), a partir de los
--   atributos que publica el servidor.
-- El elemento de cada hueco replica la regla del servidor: principal = el seleccionado si
-- está despierto (si no, Naturaleza); secundario = SecondaryCore si es válido.

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local CoreConfig = require(Shared.Config.CoreConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local CombatController = require(script.Parent.CombatController)
local CoreController = require(script.Parent.CoreController)

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

local AbilityController = {}

local player = Players.LocalPlayer
local fxFolder: Folder

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
	part.Parent = fxFolder
	return part
end

-- Altura del suelo bajo un punto (sin contar personajes, enemigos ni efectos).
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function groundAt(position: Vector3): number
	local ignore = { fxFolder }
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
local flashFrame: Frame? = nil

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
AbilityController.shake = addShake
AbilityController.kickFov = kickFov

local function screenFlash(color: Color3, strength: number?)
	local frame = flashFrame
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

-- Efectos de cada habilidad ----------------------------------------------------------------

local EFFECTS: { [string]: (any, boolean) -> () } = {}

-- Raíces: anillo verde y enredaderas que brotan alrededor de cada enemigo atrapado.
local function vines(position: Vector3, seconds: number, color: Color3)
	local ground = groundAt(position)
	for index = 1, 5 do
		local angle = (index / 5) * math.pi * 2 + math.random() * 0.5
		local base = Vector3.new(position.X + math.cos(angle) * 1.9, ground, position.Z + math.sin(angle) * 1.9)
		local tilt = CFrame.lookAt(base, Vector3.new(position.X, ground, position.Z)) * CFrame.Angles(math.rad(-25), 0, 0)
		local height = 3 + math.random() * 1.5
		local vine = fxPart(Vector3.new(0.5, 0.1, 0.5), tilt * CFrame.new(0, 0.05, 0), Color3.fromRGB(104, 176, 70), Enum.Material.Grass, 0)
		TweenService:Create(vine, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(0.45, height, 0.45), CFrame = tilt * CFrame.new(0, height / 2, 0) }):Play()
		task.delay(math.max(0.2, seconds), function()
			if vine.Parent then
				TweenService:Create(vine, TweenInfo.new(0.25), { Size = Vector3.new(0.3, 0.1, 0.3), CFrame = tilt * CFrame.new(0, 0.05, 0), Transparency = 1 }):Play()
			end
		end)
		Debris:AddItem(vine, seconds + 0.6)
	end
	burst(position, "Leaf", color, 10)
end

function EFFECTS.Roots(event, isOwner)
	local color = abilityColor("Nature")
	flatRing(event.Center, event.Radius * 2, color, 0.45, Enum.Material.Neon, 0.3)
	burst(event.Center, "Leaf", color, 18)
	local seconds = if typeof(event.Seconds) == "number" then event.Seconds else 1.5
	if typeof(event.Hits) == "table" then
		for _, hit in event.Hits do
			if typeof(hit) == "table" and typeof(hit.Position) == "Vector3" and hit.Killed ~= true then
				vines(hit.Position, if hit.Kind == "Boss" then seconds * AbilityConfig.BossControl else seconds, color)
			end
		end
	end
	CombatController.showHits(event.Hits, color, isOwner, 0.8, HIT_BOOST)
end

local function healNumbers(healed: any, color: Color3)
	if typeof(healed) ~= "table" then
		return
	end
	for _, entry in healed do
		local root = typeof(entry) == "table" and rootOf(entry.Player)
		if root then
			burst(root.Position, "Bubble", HEAL_COLOR, 12)
			flashLight(root.Position, color, 12, 0.5)
			if typeof(entry.Amount) == "number" and entry.Amount > 0 then
				CombatController.floatingNumber(root.Position + Vector3.new(0, 1, 0), entry.Amount, HEAL_COLOR, 1.2)
			end
		end
	end
end

function EFFECTS.Heal(event, isOwner)
	local color = abilityColor("Water")
	flatRing(event.Center, event.Radius * 2, color, 0.55, Enum.Material.Glass, 0.25)
	flatRing(event.Center, event.Radius * 1.3, Color3.fromRGB(200, 240, 255), 0.4, Enum.Material.Neon, 0.5)
	burst(event.Center, "Bubble", color, 24)
	healNumbers(event.Healed, color)
	CombatController.showHits(event.Hits, color, isOwner, 0.9, HIT_BOOST)
end

function EFFECTS.Burn(event, isOwner)
	local color = abilityColor("Fire")
	local look = if typeof(event.Look) == "Vector3" then event.Look else Vector3.new(0, 0, -1)
	local origin = event.Origin + Vector3.new(0, 0.5, 0) + look * 1.5
	burst(origin, "Flame", color, 70, look)
	burst(origin, "Flame", Color3.fromRGB(255, 220, 120), 30, look)
	flashLight(origin + look * 4, color, 18, 0.45)
	CombatController.showHits(event.Hits, color, isOwner, 0.8, HIT_BOOST)
end

function EFFECTS.BurnTick(event, isOwner)
	if isOwner then
		CombatController.showHits(event.Hits, Color3.fromRGB(255, 170, 90), true, 0.25)
	end
end

-- Velocidad del Vendaval: estela de viento en el personaje mientras dura.
local function hasteTrail(target: Player, seconds: number, color: Color3)
	local root = rootOf(target)
	if not root then
		return
	end
	local existing = root:FindFirstChild("AbilityHaste")
	if existing then
		existing:Destroy()
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "AbilityHaste"
	local streaks = Instance.new("ParticleEmitter")
	streaks.Rate = 22
	streaks.Lifetime = NumberRange.new(0.3, 0.5)
	streaks.Speed = NumberRange.new(1, 3)
	streaks.SpreadAngle = Vector2.new(180, 180)
	streaks.Size = NumberSequence.new(0.22, 0)
	streaks.Transparency = NumberSequence.new(0.2, 1)
	streaks.LightEmission = 0.8
	streaks.Color = ColorSequence.new(color)
	streaks.Parent = attachment
	attachment.Parent = root
	Debris:AddItem(attachment, seconds)
end

local function windRings(origin: Vector3, look: Vector3, color: Color3)
	for index = 1, 3 do
		local distance = 2 + index * 3
		local position = origin + look * distance
		local frame = CFrame.lookAt(position, position + look) * CFrame.Angles(0, math.rad(90), 0)
		local ring = fxPart(Vector3.new(0.12, 2, 2), frame, color, Enum.Material.Neon, 1, Enum.PartType.Cylinder)
		local delay = (index - 1) * 0.06
		TweenService:Create(ring, TweenInfo.new(0.05, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, delay), { Transparency = 0.45 }):Play()
		TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay + 0.05), { Size = Vector3.new(0.04, 3 + index * 2.5, 3 + index * 2.5), Transparency = 1, CFrame = frame + look * 2 }):Play()
		Debris:AddItem(ring, delay + 0.5)
	end
end

function EFFECTS.Gust(event, isOwner)
	local color = abilityColor("Wind")
	local look = if typeof(event.Look) == "Vector3" then event.Look else Vector3.new(0, 0, -1)
	local origin = event.Origin + Vector3.new(0, 0.3, 0)
	burst(origin + look * 1.5, "Wind", color, 50, look)
	windRings(origin, look, color)
	if typeof(event.HasteSeconds) == "number" and typeof(event.Owner) == "Instance" then
		hasteTrail(event.Owner, event.HasteSeconds, color)
	end
	CombatController.showHits(event.Hits, color, isOwner, 1, HIT_BOOST)
end

-- Rayo en zigzag entre dos puntos.
local function bolt(from: Vector3, to: Vector3, color: Color3, delay: number)
	task.delay(delay, function()
		local segments = 6
		local direction = to - from
		if direction.Magnitude < 0.1 then
			return
		end
		local side = direction:Cross(Vector3.new(0, 1, 0))
		side = if side.Magnitude > 0.01 then side.Unit else Vector3.new(1, 0, 0)
		local up = Vector3.new(0, 1, 0)
		local previous = from
		for index = 1, segments do
			local t = index / segments
			local point = from + direction * t
			if index < segments then
				point += side * (math.random() * 1.6 - 0.8) + up * (math.random() * 1.2 - 0.6)
			end
			local length = (point - previous).Magnitude
			local piece = fxPart(Vector3.new(0.2, 0.2, length), CFrame.lookAt((previous + point) / 2, point), Color3.new(1, 1, 1):Lerp(color, 0.4), Enum.Material.Neon, 0)
			TweenService:Create(piece, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = Vector3.new(0.05, 0.05, length) }):Play()
			Debris:AddItem(piece, 0.35)
			previous = point
		end
		burst(to, "Spark", color, 10)
		flashLight(to, color, 10, 0.25)
	end)
end

function EFFECTS.Chain(event, isOwner)
	local color = abilityColor("Lightning")
	if typeof(event.Points) == "table" then
		for index = 1, #event.Points - 1 do
			local from, to = event.Points[index], event.Points[index + 1]
			if typeof(from) == "Vector3" and typeof(to) == "Vector3" then
				bolt(from, to, color, (index - 1) * 0.05)
			end
		end
	end
	task.delay(0.05, function()
		CombatController.showHits(event.Hits, color, isOwner, 0.9, HIT_BOOST)
	end)
end

local function iceShards(center: Vector3, radius: number, count: number, scale: number)
	local ground = groundAt(center)
	for index = 1, count do
		local angle = (index / count) * math.pi * 2
		local distance = radius * (0.55 + math.random() * 0.4)
		local base = Vector3.new(center.X + math.cos(angle) * distance, ground, center.Z + math.sin(angle) * distance)
		local height = (1.6 + math.random() * 1.4) * scale
		local frame = CFrame.new(base) * CFrame.Angles(math.rad(math.random(-20, 20)), angle, math.rad(math.random(-20, 20)))
		local shard = fxPart(Vector3.new(0.6 * scale, 0.1, 0.6 * scale), frame, Color3.fromRGB(190, 236, 255), Enum.Material.Ice, 0.15)
		TweenService:Create(shard, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(0.6 * scale, height, 0.6 * scale), CFrame = frame * CFrame.new(0, height / 2, 0) }):Play()
		TweenService:Create(shard, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6), { Transparency = 1 }):Play()
		Debris:AddItem(shard, 1.1)
	end
end

function EFFECTS.Frost(event, isOwner)
	local color = abilityColor("Ice")
	flatRing(event.Center, event.Radius * 2, color, 0.5, Enum.Material.Ice, 0.2)
	flatRing(event.Center, event.Radius * 1.4, Color3.new(1, 1, 1), 0.35, Enum.Material.Neon, 0.55)
	burst(event.Center, "Snow", color, 34)
	iceShards(event.Center, event.Radius, 10, 1)
	CombatController.showHits(event.Hits, color, isOwner, 0.8, HIT_BOOST)
end

local function projectile(from: Vector3, to: Vector3, color: Color3, tail: Color3, onArrive: () -> ())
	local orb = fxPart(Vector3.one * 0.9, CFrame.new(from), color, Enum.Material.Neon, 0.1, Enum.PartType.Ball)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.3, 0)
	a0.Parent = orb
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.3, 0)
	a1.Parent = orb
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.2
	trail.LightEmission = 0.6
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(color, tail)
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Parent = orb
	local travel = math.clamp((to - from).Magnitude / 60, 0.12, 0.3)
	local tween = TweenService:Create(orb, TweenInfo.new(travel, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { CFrame = CFrame.new(to) })
	tween.Completed:Once(function()
		orb:Destroy()
		onArrive()
	end)
	tween:Play()
	Debris:AddItem(orb, travel + 0.3)
end

function EFFECTS.Curse(event, isOwner)
	local color = abilityColor("Shadow")
	if typeof(event.Origin) ~= "Vector3" or typeof(event.Target) ~= "Vector3" then
		return
	end
	projectile(event.Origin + Vector3.new(0, 1, 0), event.Target, color, Color3.fromRGB(40, 20, 70), function()
		flatRing(event.Target, 6, color, 0.4, Enum.Material.Neon, 0.35)
		burst(event.Target, "Smoke", color, 16)
		if typeof(event.Marked) == "table" then
			for _, position in event.Marked do
				if typeof(position) == "Vector3" then
					burst(position, "Smoke", Color3.fromRGB(110, 60, 180), 8)
				end
			end
		end
		CombatController.showHits(event.Hits, color, isOwner, 0.8, HIT_BOOST)
	end)
end

function EFFECTS.StarfallCast(event, _isOwner)
	local color = abilityColor("Celestial")
	if typeof(event.Center) ~= "Vector3" or typeof(event.Radius) ~= "number" then
		return
	end
	local telegraph = if typeof(event.Telegraph) == "number" then event.Telegraph else 0.7
	local waves = if typeof(event.Waves) == "number" then event.Waves else 3
	local interval = if typeof(event.WaveInterval) == "number" then event.WaveInterval else 0.45
	local total = telegraph + (waves - 1) * interval + 0.3
	local y = groundAt(event.Center) + 0.22
	local diameter = event.Radius * 2
	local frame = CFrame.new(event.Center.X, y, event.Center.Z) * CFrame.Angles(0, 0, math.rad(90))
	local ring = fxPart(Vector3.new(0.1, diameter, diameter), frame, color, Enum.Material.Neon, 0.65, Enum.PartType.Cylinder)
	local fill = fxPart(Vector3.new(0.12, 0.5, 0.5), frame + Vector3.new(0, 0.03, 0), color, Enum.Material.Neon, 0.6, Enum.PartType.Cylinder)
	TweenService:Create(fill, TweenInfo.new(telegraph, Enum.EasingStyle.Linear), { Size = Vector3.new(0.12, diameter, diameter) }):Play()
	TweenService:Create(ring, TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, total - 0.3), { Transparency = 1 }):Play()
	TweenService:Create(fill, TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, total - 0.3), { Transparency = 1 }):Play()
	Debris:AddItem(ring, total + 0.1)
	Debris:AddItem(fill, total + 0.1)
	burst(event.Center + Vector3.new(0, 1, 0), "Star", color, 12)
end

function EFFECTS.StarfallWave(event, isOwner)
	local color = abilityColor("Celestial")
	if typeof(event.Center) ~= "Vector3" or typeof(event.Radius) ~= "number" then
		return
	end
	local ground = groundAt(event.Center)
	for index = 1, 6 do
		local angle = math.random() * math.pi * 2
		local distance = math.sqrt(math.random()) * event.Radius * 0.9
		local target = Vector3.new(event.Center.X + math.cos(angle) * distance, ground + 0.5, event.Center.Z + math.sin(angle) * distance)
		local start = target + Vector3.new(math.random(-6, 6), 34, math.random(-6, 6))
		local star = fxPart(Vector3.one * 1.1, CFrame.new(start), Color3.fromRGB(255, 246, 210), Enum.Material.Neon, 0, Enum.PartType.Ball)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.4, 0)
		a0.Parent = star
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.4, 0)
		a1.Parent = star
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.25
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		trail.Transparency = NumberSequence.new(0, 1)
		trail.Parent = star
		local fall = 0.22 + index * 0.02
		local tween = TweenService:Create(star, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(target) })
		tween.Completed:Once(function()
			star:Destroy()
			burst(target, "Star", color, 8)
		end)
		tween:Play()
		Debris:AddItem(star, fall + 0.3)
	end
	task.delay(0.24, function()
		flashLight(event.Center + Vector3.new(0, 2, 0), color, 22, 0.35)
		CombatController.showHits(event.Hits, color, isOwner, 0.8, HIT_BOOST)
		if isOwner then
			addShake(0.22)
		end
	end)
end

-- Combos -----------------------------------------------------------------------------------

local REACTION_FX: { [string]: (any, Color3) -> () } = {}

function REACTION_FX.Electrocuted(event, color)
	if typeof(event.Hits) == "table" then
		for index, hit in event.Hits do
			if typeof(hit) == "table" and typeof(hit.Position) == "Vector3" then
				bolt(event.Center + Vector3.new(0, 3, 0), hit.Position, color, (index - 1) * 0.04)
			end
		end
	end
	burst(event.Center, "Spark", Color3.fromRGB(255, 250, 200), 30)
end

function REACTION_FX.Steam(event, color)
	burst(event.Center, "Steam", color, 40)
	flatRing(event.Center, (event.Radius or 8) * 2.2, Color3.new(1, 1, 1), 0.5, Enum.Material.Neon, 0.4)
end

function REACTION_FX.Frozen(event, color)
	-- Bloque de hielo alrededor del enemigo mientras dura la congelación.
	local seconds = AbilityConfig.Reactions.Frozen.StunSeconds
	local block = fxPart(Vector3.one, CFrame.new(event.Center) * CFrame.Angles(0, math.rad(math.random(0, 90)), 0), Color3.fromRGB(190, 236, 255), Enum.Material.Ice, 0.45)
	TweenService:Create(block, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(5, 6, 5) }):Play()
	TweenService:Create(block, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, seconds), { Transparency = 1 }):Play()
	Debris:AddItem(block, seconds + 0.4)
	iceShards(event.Center, 3, 8, 0.8)
	burst(event.Center, "Snow", color, 30)
end

function REACTION_FX.Wildfire(event, color)
	burst(event.Center, "Flame", color, 50, Vector3.new(0, 1, 0))
	flatRing(event.Center, (event.Radius or 10) * 2, color, 0.5, Enum.Material.Neon, 0.3)
end

function REACTION_FX.Melt(event, color)
	burst(event.Center, "Steam", Color3.fromRGB(255, 200, 160), 20)
	burst(event.Center, "Flame", color, 30, Vector3.new(0, 1, 0))
end

function REACTION_FX.Superconduct(event, color)
	flatRing(event.Center, (event.Radius or 8) * 2, color, 0.55, Enum.Material.Neon, 0.25)
	burst(event.Center, "Spark", color, 24)
end

function REACTION_FX.Bloom(event, color)
	burst(event.Center, "Leaf", color, 30)
	vines(event.Center, AbilityConfig.Reactions.Bloom.RootSeconds or 3, color)
end

function REACTION_FX.Eclipse(event, color)
	local sphere = fxPart(Vector3.one * 2, CFrame.new(event.Center + Vector3.new(0, 2, 0)), Color3.fromRGB(30, 16, 50), Enum.Material.Neon, 0.1, Enum.PartType.Ball)
	TweenService:Create(sphere, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * (event.Radius or 10) * 1.2, Color = color, Transparency = 1 }):Play()
	Debris:AddItem(sphere, 0.35)
	burst(event.Center, "Star", color, 40)
	flatRing(event.Center, (event.Radius or 10) * 2.2, color, 0.6, Enum.Material.Neon, 0.25)
end

function REACTION_FX.Swirl(event, color)
	local auraColor = abilityColor(event.Aura)
	local center = event.Center
	for index = 1, 3 do
		task.delay((index - 1) * 0.07, function()
			flatRing(center + Vector3.new(0, index * 0.6, 0), (event.Radius or 10) * (0.8 + index * 0.4), if index == 2 then auraColor else color, 0.45, Enum.Material.Neon, 0.35)
		end)
	end
	burst(center, "Wind", auraColor, 30, Vector3.new(0, 1, 0))
end

local function showReaction(event: any, isOwner: boolean)
	local reaction = typeof(event.Reaction) == "string" and AbilityConfig.Reactions[event.Reaction] or nil
	if not (reaction and typeof(event.Center) == "Vector3") then
		return
	end
	local color = reaction.Color
	floatingText(event.Center, reaction.Name, color)
	flashLight(event.Center + Vector3.new(0, 2, 0), color, 20, 0.45)
	local flavor = REACTION_FX[event.Reaction]
	if flavor then
		flavor(event, color)
	end
	soundAt(event.Center, AbilityConfig.Sounds.Reactions[event.Reaction] or AbilityConfig.Sounds.Reactions.Default)
	healNumbers(event.Healed, color)
	CombatController.showHits(event.Hits, color, isOwner, 1, 1.3)
	if isOwner then
		addShake(AbilityConfig.ReactionShake or 0.55)
		kickFov(4)
		screenFlash(color, 1)
	end
end

-- Estados y marcas sobre los enemigos --------------------------------------------------------

local STATUS_LOOKS: { [string]: { Color: Color3, Setup: (ParticleEmitter) -> () } } = {
	BurnUntil = {
		Color = Color3.fromRGB(255, 130, 50),
		Setup = function(e)
			e.Rate = 16
			e.Lifetime = NumberRange.new(0.4, 0.7)
			e.Speed = NumberRange.new(2, 4)
			e.Acceleration = Vector3.new(0, 6, 0)
			e.SpreadAngle = Vector2.new(40, 40)
			e.Size = NumberSequence.new(0.8, 0)
			e.Transparency = NumberSequence.new(0.2, 1)
			e.LightEmission = 1
		end,
	},
	SlowUntil = {
		Color = Color3.fromRGB(170, 230, 255),
		Setup = function(e)
			e.Rate = 10
			e.Lifetime = NumberRange.new(0.8, 1.2)
			e.Speed = NumberRange.new(0.5, 1.5)
			e.Acceleration = Vector3.new(0, -2, 0)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new(0.3, 0)
			e.Rotation = NumberRange.new(0, 360)
			e.LightEmission = 0.7
		end,
	},
	RootUntil = {
		Color = Color3.fromRGB(120, 214, 96),
		Setup = function(e)
			e.Rate = 8
			e.Lifetime = NumberRange.new(0.6, 1)
			e.Speed = NumberRange.new(1, 2)
			e.SpreadAngle = Vector2.new(180, 20)
			e.Size = NumberSequence.new(0.3, 0.05)
			e.Rotation = NumberRange.new(0, 360)
			e.RotSpeed = NumberRange.new(-120, 120)
			e.LightEmission = 0.2
		end,
	},
	StunUntil = {
		Color = Color3.fromRGB(255, 240, 120),
		Setup = function(e)
			e.Rate = 20
			e.Lifetime = NumberRange.new(0.15, 0.3)
			e.Speed = NumberRange.new(4, 8)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new(0.25, 0)
			e.LightEmission = 1
		end,
	},
	CurseUntil = {
		Color = Color3.fromRGB(150, 90, 230),
		Setup = function(e)
			e.Rate = 9
			e.Lifetime = NumberRange.new(0.8, 1.2)
			e.Speed = NumberRange.new(0.5, 1.5)
			e.Acceleration = Vector3.new(0, 3, 0)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new(0.7, 1.2)
			e.Transparency = NumberSequence.new(0.4, 1)
			e.LightEmission = 0.3
		end,
	},
}

-- Icono de la marca elemental sobre la barra de vida del enemigo.
local function refreshAura(model: Model, root: BasePart, now: number)
	local element = model:GetAttribute("Aura")
	local untilTime = model:GetAttribute("AuraUntil")
	local ability = typeof(element) == "string" and AbilityConfig.Abilities[element] or nil
	local active = ability ~= nil and typeof(untilTime) == "number" and untilTime > now
	local icon = root:FindFirstChild("AuraIcon") :: BillboardGui?
	if not active then
		if icon then
			icon:Destroy()
		end
		return
	end
	if not icon then
		local bar = root:FindFirstChild("HealthBar")
		local offset = if bar and bar:IsA("BillboardGui") then bar.StudsOffset else Vector3.new(0, 3, 0)
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "AuraIcon"
		billboard.Size = UDim2.fromOffset(30, 30)
		billboard.StudsOffset = offset + Vector3.new(0, 1.7, 0)
		billboard.LightInfluence = 0
		billboard.MaxDistance = 80
		local circle = Instance.new("Frame")
		circle.Name = "Circle"
		circle.Size = UDim2.fromScale(1, 1)
		circle.BackgroundColor3 = THEME.Panel
		circle.BackgroundTransparency = 0.15
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = circle
		local stroke = Instance.new("UIStroke")
		stroke.Name = "Ring"
		stroke.Thickness = 2
		stroke.Parent = circle
		local label = Instance.new("TextLabel")
		label.Name = "Icon"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = FONTS.Display
		label.TextScaled = true
		label.Parent = circle
		circle.Parent = billboard
		billboard.Parent = root
		icon = billboard
	end
	local circle = (icon :: BillboardGui):FindFirstChild("Circle") :: Frame
	local label = circle:FindFirstChild("Icon") :: TextLabel
	local ring = circle:FindFirstChild("Ring") :: UIStroke
	if label.Text ~= ability.Icon then
		label.Text = ability.Icon
		ring.Color = ability.Color
	end
	-- Parpadea cuando está a punto de acabarse.
	local remaining = untilTime - now
	circle.BackgroundTransparency = if remaining < 1.2 and math.floor(now * 6) % 2 == 0 then 0.6 else 0.15
end

local function refreshStatuses()
	local enemies = Workspace:FindFirstChild("Enemies")
	if not enemies then
		return
	end
	local now = Workspace:GetServerTimeNow()
	for _, zoneFolder in enemies:GetChildren() do
		for _, model in zoneFolder:GetChildren() do
			local root = model:IsA("Model") and model:FindFirstChild("HumanoidRootPart")
			if not (root and root:IsA("BasePart")) then
				continue
			end
			for attribute, look in STATUS_LOOKS do
				local untilTime = model:GetAttribute(attribute)
				local active = typeof(untilTime) == "number" and untilTime > now
				local name = "Status_" .. attribute
				local existing = root:FindFirstChild(name)
				if active and not existing then
					local attachment = Instance.new("Attachment")
					attachment.Name = name
					local emitter = Instance.new("ParticleEmitter")
					look.Setup(emitter)
					emitter.Color = ColorSequence.new(look.Color:Lerp(Color3.new(1, 1, 1), 0.3), look.Color)
					emitter.Parent = attachment
					attachment.Parent = root
				elseif not active and existing then
					existing:Destroy()
				end
			end
			refreshAura(model :: Model, root, now)
		end
	end
end

-- Interfaz -------------------------------------------------------------------------------

local function unlockedList(): { string }
	local value = player:GetAttribute(Constants.Attributes.UnlockedCores)
	local list = {}
	if typeof(value) == "string" then
		for _, id in string.split(value, ",") do
			if id ~= "" then
				table.insert(list, id)
			end
		end
	end
	return list
end

-- Elemento de cada hueco (misma regla que el servidor).
local function slotElement(slot: string): string?
	local unlocked = {}
	for _, id in unlockedList() do
		unlocked[id] = true
	end
	local selected = player:GetAttribute(Constants.Attributes.SelectedCore)
	if slot == "Secondary" then
		local secondary = player:GetAttribute(Constants.Attributes.SecondaryCore)
		if typeof(secondary) == "string" and unlocked[secondary] and secondary ~= selected and AbilityConfig.Abilities[secondary] then
			return secondary
		end
		return nil
	end
	if typeof(selected) == "string" and unlocked[selected] and AbilityConfig.Abilities[selected] then
		return selected
	end
	return CoreConfig.DefaultElement
end

type SlotUi = {
	Frame: Frame,
	Gradient: UIGradient,
	Stroke: UIStroke,
	Button: TextButton,
	Cooldown: Frame,
	Count: TextLabel,
	Name: TextLabel,
	ReadyStroke: UIStroke,
}

local INK = Color3.fromRGB(43, 29, 63)
local CREAM = Color3.fromRGB(255, 246, 224)

local function buildSlot(screenGui: ScreenGui, name: string, key: string): (SlotUi, UIScale)
	local frame, scale = UiKit.panel(screenGui, name, Vector2.new(BUTTON_SIZE, BUTTON_SIZE), Vector2.new(1, 1), UDim2.new(1, -112, 1, -22))
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 0
	frame:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0)
	local shine = frame:FindFirstChild("Shine")
	if shine then
		shine:Destroy()
	end
	local oldGrad = frame:FindFirstChildOfClass("UIGradient")
	if oldGrad then
		oldGrad:Destroy()
	end
	local grad = UiKit.create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 247, 168)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(95, 203, 82)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(47, 154, 58)),
		}),
	}, frame)
	local stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Color = INK
	stroke.Thickness = 4
	stroke.Transparency = 0
	local cooldown = UiKit.create("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.35,
		ZIndex = 2,
	}, frame)
	UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, cooldown)
	local button = UiKit.create("TextButton", {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = FONTS.Display,
		TextSize = 36,
		TextColor3 = THEME.Text,
		Text = "",
		ZIndex = 3,
	}, frame)
	UiKit.addStates(button)
	local hover = button:FindFirstChild("Highlight")
	local hoverCorner = hover and hover:FindFirstChildOfClass("UICorner")
	if hoverCorner then
		hoverCorner.CornerRadius = UDim.new(0.5, 0)
	end
	local count = UiKit.text(frame, "Count", {
		Size = UDim2.fromScale(1, 1),
		Font = FONTS.Display,
		TextSize = 30,
		TextColor3 = THEME.Text,
		TextStrokeColor3 = THEME.Outline,
		TextStrokeTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 4,
	})
	local keyBadge = UiKit.create("Frame", {
		Name = "KeyBadge",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 2, 1, 2),
		Size = UDim2.fromOffset(25, 25),
		BackgroundColor3 = INK,
		ZIndex = 5,
	}, frame)
	UiKit.corner(keyBadge, 8)
	UiKit.create("UIStroke", {
		Color = Color3.new(1, 1, 1),
		Thickness = 1.5,
		Transparency = 0.72,
	}, keyBadge)
	UiKit.text(keyBadge, "Hint", {
		Size = UDim2.fromScale(1, 1),
		Font = FONTS.Display,
		TextSize = 13,
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = key,
		ZIndex = 6,
	})
	local label = UiKit.text(frame, "AbilityName", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 5),
		Size = UDim2.fromOffset(80, 18),
		Font = FONTS.Display,
		TextSize = 13,
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 4,
	})
	UiKit.create("UIStroke", {
		Color = INK,
		Thickness = 2.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, label)
	local readyRing = UiKit.create("Frame", {
		Name = "ReadyRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
	}, frame)
	UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, readyRing)
	local readyStroke = UiKit.stroke(readyRing, THEME.Gold, 3, 1)
	return {
		Frame = frame,
		Gradient = grad,
		Stroke = stroke,
		Button = button,
		Cooldown = cooldown,
		Count = count,
		Name = label,
		ReadyStroke = readyStroke,
	}, scale
end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("AbilityHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "AbilityHud",
		ResetOnSpawn = false,
		DisplayOrder = 3,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)

	local primary, primaryScale = buildSlot(screenGui, "AbilityButton", "Q")
	local secondary, secondaryScale = buildSlot(screenGui, "SecondaryButton", "R")
	local notice = UiKit.text(primary.Frame, "Notice", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -8),
		Size = UDim2.fromOffset(260, 18),
		Font = FONTS.Body,
		TextSize = 14,
		TextColor3 = THEME.Error,
		TextStrokeColor3 = THEME.Outline,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		ZIndex = 5,
	})
	local flash = UiKit.create("Frame", {
		Name = "AbilityFlash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 20,
	}, screenGui)
	flashFrame = flash

	screenGui.Parent = playerGui
	UiKit.bindScale(screenGui, { primaryScale, secondaryScale })

	local function place()
		local uiScale = UiKit.computeScale(screenGui.AbsoluteSize)
		local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		if touchOnly then
			primary.Frame.Position = UDim2.new(1, -EDGE, 0.5, -76 * uiScale)
			secondary.Frame.Position = UDim2.new(1, -EDGE, 0.5, -(76 + BUTTON_SIZE + 26) * uiScale)
		else
			primary.Frame.Position = UDim2.new(1, -(EDGE + (ATTACK_BUTTON + GAP) * uiScale), 1, -34)
			secondary.Frame.Position = UDim2.new(1, -(EDGE + (ATTACK_BUTTON + GAP + BUTTON_SIZE + GAP) * uiScale), 1, -34)
		end
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	UserInputService.LastInputTypeChanged:Connect(place)
	place()

	return { Primary = primary, Secondary = secondary, Notice = notice }
end

function AbilityController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local useRemote = remotes:WaitForChild(Constants.Remotes.UseAbility) :: RemoteEvent
	local resultRemote = remotes:WaitForChild(Constants.Remotes.AbilityResult) :: RemoteEvent
	local eventRemote = remotes:WaitForChild(Constants.Remotes.AbilityEvent) :: RemoteEvent

	local existingFx = Workspace:FindFirstChild("ClientAbilityFX")
	if existingFx then
		existingFx:Destroy()
	end
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ClientAbilityFX"
	fxFolder.Parent = Workspace

	local ui = buildGui()
	local slots: { [string]: SlotUi } = { Primary = ui.Primary, Secondary = ui.Secondary }
	local readyAtByElement: { [string]: number } = {}
	local wasCooling: { [string]: boolean } = {}
	local pendingAt: { [string]: number } = { Primary = -math.huge, Secondary = -math.huge }

	local function applyElements()
		for _, slot in SLOT_ORDER do
			local slotUi = slots[slot]
			local elementId = slotElement(slot)
			local ability = elementId and AbilityConfig.Abilities[elementId]
			if ability then
				slotUi.Frame.Visible = true
				slotUi.Button.Text = ability.Icon
				slotUi.Button.TextTransparency = 0
				slotUi.Name.Text = if #ability.Name > 9 then (ability.Name:match("^%S+") or ability.Name) else ability.Name
				slotUi.Frame.BackgroundColor3 = Color3.new(1, 1, 1)
				local c = ability.Color
				slotUi.Gradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, c:Lerp(Color3.new(1, 1, 1), 0.55)),
					ColorSequenceKeypoint.new(0.55, c),
					ColorSequenceKeypoint.new(1, c:Lerp(Color3.new(0, 0, 0), 0.28)),
				})
				slotUi.Stroke.Color = INK
				slotUi.Stroke.Transparency = 0
			elseif slot == "Secondary" and #unlockedList() >= 2 then
				slotUi.Frame.Visible = true
				slotUi.Button.Text = "+"
				slotUi.Button.TextTransparency = 0.3
				slotUi.Name.Text = "Elige tu R (N)"
				slotUi.Frame.BackgroundColor3 = THEME.Panel
				slotUi.Stroke.Color = INK
				slotUi.Stroke.Transparency = 0.2
			else
				slotUi.Frame.Visible = false
			end
		end
	end
	for _, attribute in { Constants.Attributes.SelectedCore, Constants.Attributes.SecondaryCore, Constants.Attributes.UnlockedCores } do
		player:GetAttributeChangedSignal(attribute):Connect(applyElements)
	end
	applyElements()

	local noticeToken = 0
	local function notice(text: string)
		noticeToken += 1
		local token = noticeToken
		ui.Notice.Text = text
		ui.Notice.TextTransparency = 0
		ui.Notice.TextStrokeTransparency = 0.3
		task.delay(1.6, function()
			if noticeToken == token then
				TweenService:Create(ui.Notice, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end)
	end

	local function readyPulse(slotUi: SlotUi)
		slotUi.ReadyStroke.Transparency = 0
		slotUi.ReadyStroke.Thickness = 3
		local ring = slotUi.ReadyStroke.Parent :: Frame
		ring.Size = UDim2.fromScale(1, 1)
		TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1.35, 1.35) }):Play()
		TweenService:Create(slotUi.ReadyStroke, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1, Thickness = 1 }):Play()
	end

	-- Recargas: un bucle ligero para los dos botones.
	task.spawn(function()
		while true do
			local now = Workspace:GetServerTimeNow()
			for _, slot in SLOT_ORDER do
				local slotUi = slots[slot]
				local elementId = slotElement(slot)
				local ability = elementId and AbilityConfig.Abilities[elementId]
				local remaining = if elementId then (readyAtByElement[elementId] or 0) - now else 0
				if ability and remaining > 0 then
					slotUi.Cooldown.Size = UDim2.fromScale(1, math.clamp(remaining / ability.Cooldown, 0, 1))
					slotUi.Count.Visible = true
					slotUi.Count.Text = tostring(math.ceil(remaining))
					wasCooling[slot] = true
				else
					slotUi.Cooldown.Size = UDim2.fromScale(1, 0)
					slotUi.Count.Visible = false
					if wasCooling[slot] then
						wasCooling[slot] = false
						readyPulse(slotUi)
					end
				end
			end
			task.wait(0.1)
		end
	end)

	local function shake(slotUi: SlotUi)
		local tween = TweenService:Create(slotUi.Frame, TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true), { Rotation = 6 })
		tween.Completed:Once(function()
			slotUi.Frame.Rotation = 0
		end)
		tween:Play()
	end

	local function tryUse(slot: string)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (humanoid and humanoid.Health > 0) then
			return
		end
		local elementId = slotElement(slot)
		if not elementId then
			if slot == "Secondary" and #unlockedList() >= 2 and CoreController.open then
				CoreController.open(nil) -- elegir el secundario en el panel
			end
			return
		end
		if (readyAtByElement[elementId] or 0) - Workspace:GetServerTimeNow() > 0.05 then
			shake(slots[slot]) -- aún recargando
			return
		end
		if os.clock() - pendingAt[slot] < 0.8 then
			return -- esperando la respuesta del servidor
		end
		pendingAt[slot] = os.clock()
		useRemote:FireServer(slot) -- sin objetivo: lo decide el servidor
	end

	ContextActionService:BindAction("RebirthAbility", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			tryUse("Primary")
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
	ContextActionService:BindAction("RebirthAbilitySecondary", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			tryUse("Secondary")
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.R, Enum.KeyCode.ButtonB)
	ui.Primary.Button.Activated:Connect(function()
		tryUse("Primary")
	end)
	ui.Secondary.Button.Activated:Connect(function()
		tryUse("Secondary")
	end)

	resultRemote.OnClientEvent:Connect(function(success: any, code: any, elementId: any, serverReadyAt: any, slot: any)
		local slotName = if slot == "Secondary" then "Secondary" else "Primary"
		pendingAt[slotName] = -math.huge
		local ability = typeof(elementId) == "string" and AbilityConfig.Abilities[elementId] or nil
		if typeof(serverReadyAt) == "number" and ability and (success == true or code == Codes.Cooldown) then
			readyAtByElement[elementId] = serverReadyAt
		end
		local slotUi = slots[slotName]
		if success == true and ability then
			-- Sensación al lanzarla: gesto, sacudida, zoom y destello del color del elemento.
			playGesture(ability.Gesture)
			addShake(ability.Shake or 0.3)
			kickFov(2.5)
			screenFlash(ability.Color, 0.6)
			slotUi.Frame.Size = UDim2.fromOffset(BUTTON_SIZE * 1.12, BUTTON_SIZE * 1.12)
			TweenService:Create(slotUi.Frame, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE) }):Play()
		elseif code == Codes.NoTarget then
			notice("No hay ningún enemigo delante")
			shake(slotUi)
		elseif code == Codes.Cooldown then
			shake(slotUi)
		end
	end)

	eventRemote.OnClientEvent:Connect(function(event: any)
		if typeof(event) ~= "table" or typeof(event.Kind) ~= "string" then
			return
		end
		local isOwner = event.Owner == player
		local ok, err = pcall(function()
			if event.Kind == "Reaction" then
				showReaction(event, isOwner)
				return
			end
			local effect = EFFECTS[event.Kind]
			if not effect then
				return
			end
			-- Sonido de lanzamiento en el punto de la habilidad (lo oyen los cercanos).
			if ABILITY_KINDS[event.Kind] then
				local origin = if typeof(event.Origin) == "Vector3" then event.Origin elseif typeof(event.Center) == "Vector3" then event.Center else nil
				if origin then
					soundAt(origin, AbilityConfig.Sounds.Cast[event.Element])
				end
			end
			effect(event, isOwner)
		end)
		if not ok then
			warn("[AbilityController] " .. tostring(event.Kind) .. ": " .. tostring(err))
		end
	end)

	-- Limpiar efectos temporales al morir o cambiar de zona.
	local function clear()
		fxFolder:ClearAllChildren()
	end
	player.CharacterRemoving:Connect(clear)
	player:GetAttributeChangedSignal(Constants.Attributes.CurrentZone):Connect(clear)

	RunService:BindToRenderStep("RebirthAbilityCamera", Enum.RenderPriority.Camera.Value + 1, cameraStep)

	-- Estados y marcas de los enemigos (atributos del servidor): un único bucle ligero.
	task.spawn(function()
		while true do
			task.wait(0.15)
			local ok, err = pcall(refreshStatuses)
			if not ok then
				warn("[AbilityController] estados: " .. tostring(err))
			end
		end
	end)
end

return AbilityController
