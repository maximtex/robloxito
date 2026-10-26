-- Aviso de los golpes de los bichos (solo presentación; el golpe lo decide EnemyService.attack).
-- Cuando un bicho empieza a preparar un golpe contra TI (atributos AttackTarget = tu UserId,
-- AttackAt, AttackDir y AttackReach en su modelo):
-- - Un ! de neón encima de él que aparece de golpe y tiembla: rojo mientras se prepara y
--   dorado en el último momento (los últimos ParryWindow segundos: si bloqueas ahí con el
--   Guerrero, parada perfecta).
-- - Media luna roja en el suelo con su alcance, hacia donde va el golpe, que se llena hasta
--   el momento del golpe: si sales de ella (o te pones detrás), no te da.
-- - "¡Esquivado!" sobre ti si al soltarlo ya no estabas a su alcance.
-- Los golpes contra otros jugadores no se avisan aquí (ya se ven los ojos y la animación).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StyleConfig = require(Shared.Config.StyleConfig)
local Theme = require(script.Parent.Parent.UI.Theme)

local AttackWarning = {}

local player = Players.LocalPlayer
local FONTS = Theme.Fonts
local INK = Color3.fromRGB(43, 29, 63)
local RED = Color3.fromRGB(255, 60, 60)
local GOLD = Color3.fromRGB(255, 214, 70)
local DODGE_COLOR = Color3.fromRGB(140, 230, 255)
local PARRY_WINDOW = StyleConfig.Styles.Warrior.Block.ParryWindow
local FRONT_DOT = -0.1 -- como EnemyService: un poco más de medio círculo por delante
local MAX_WARNINGS = 10 -- en una horda, más avisos a la vez no se leen
local PIXELS_PER_STUD = 16

type Warning = {
	Model: Model,
	At: number, -- hora del golpe (servidor)
	Started: number,
	Reach: number,
	Direction: Vector3,
	Root: BasePart,
	Bar: Part, -- el ! (palo y punto), de neón
	Dot: Part,
	Size: number,
	Height: number, -- sobre la raíz del bicho
	Ground: Part,
	Fill: Frame,
	Outline: UIStroke,
	Back: Frame,
	Gold: boolean,
}

local fxFolder: Folder
local warnings: { [Model]: Warning } = {}
local watched: { [Model]: RBXScriptConnection } = {}
local count = 0
local dodgeSound: Sound? = nil

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function myRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function groundBelow(position: Vector3, model: Model): number
	local params = RaycastParams.new()
	local ignore: { Instance } = { model, fxFolder }
	local enemies = Workspace:FindFirstChild("Enemies")
	if enemies then
		table.insert(ignore, enemies)
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0), params)
	return if hit then hit.Position.Y else position.Y - 2.5
end

local function clear(model: Model)
	local warning = warnings[model]
	if not warning then
		return
	end
	warnings[model] = nil
	count -= 1
	warning.Bar:Destroy()
	warning.Dot:Destroy()
	warning.Ground:Destroy()
end

-- Media luna en el suelo (SurfaceGui sobre una pieza plana): el borde recto junto al bicho y
-- la parte redonda hacia donde va el golpe. Dentro, otra que crece hasta el golpe.
local function buildGround(origin: Vector3, direction: Vector3, reach: number, groundY: number): (Part, Frame, UIStroke, Frame)
	local center = Vector3.new(origin.X, groundY + 0.08, origin.Z) + direction * (reach / 2)
	local part = Instance.new("Part")
	part.Name = "AttackWarning"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(reach * 2, 0.05, reach)
	-- La cara de arriba de la pieza: el borde de arriba del SurfaceGui mira hacia -Z (LookVector)
	part.CFrame = CFrame.lookAt(center, center + direction)
	part.Parent = fxFolder
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.Brightness = 1.5
	gui.ZOffset = 1
	gui.Parent = part
	local clip = Instance.new("Frame")
	clip.Name = "Clip"
	clip.Size = UDim2.fromScale(1, 1)
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.Parent = gui
	-- El círculo entero mide el ancho; solo se ve su mitad de arriba
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.AnchorPoint = Vector2.new(0.5, 0.5)
	back.Position = UDim2.fromScale(0.5, 1)
	back.Size = UDim2.fromScale(1, 2)
	back.BackgroundColor3 = RED
	back.BackgroundTransparency = 0.82
	back.Parent = clip
	Instance.new("UICorner", back).CornerRadius = UDim.new(0.5, 0)
	local outline = Instance.new("UIStroke")
	outline.Color = RED
	outline.Thickness = 4
	outline.Transparency = 0.15
	outline.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0.5, 0.5)
	fill.Position = UDim2.fromScale(0.5, 1)
	fill.Size = UDim2.fromScale(0, 0)
	fill.BackgroundColor3 = RED
	fill.BackgroundTransparency = 0.45
	fill.Parent = clip
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0.5, 0)
	return part, fill, outline, back
end

local function neon(shape: Enum.PartType, color: Color3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Shape = shape
	part.Color = color
	part.Size = Vector3.one * 0.1
	part.Parent = fxFolder
	return part
end

-- El ! encima del bicho: un palo y un punto (se ven igual desde cualquier lado). Tamaño y
-- altura según lo grande que es el bicho.
local function buildMark(model: Model, root: BasePart): (Part, Part, number, number)
	local box, size = model:GetBoundingBox()
	local scale = math.clamp(size.Y / 5, 1, 2.2)
	local height = (box.Position.Y + size.Y / 2) - root.Position.Y + 0.5
	return neon(Enum.PartType.Cylinder, RED), neon(Enum.PartType.Ball, RED), scale, height
end

-- Coloca el ! (`pop` 0..1 al aparecer; `wobble` grados de temblor)
local function placeMark(warning: Warning, pop: number, wobble: number)
	local s = warning.Size * pop
	local base = warning.Root.Position + Vector3.new(0, warning.Height, 0)
	local tilt = CFrame.Angles(0, 0, math.rad(wobble))
	-- Cilindro: su eje es X; girado 90° queda de pie
	warning.Bar.Size = Vector3.new(1.3 * s, 0.5 * s, 0.5 * s)
	warning.Bar.CFrame = CFrame.new(base) * tilt * CFrame.new(0, 1.05 * s, 0) * CFrame.Angles(0, 0, math.rad(90))
	warning.Dot.Size = Vector3.one * 0.55 * s
	warning.Dot.CFrame = CFrame.new(base) * tilt * CFrame.new(0, 0.1 * s, 0)
end

-- "¡Esquivado!" sobre tu personaje
local function showDodge()
	local root = myRoot()
	if not root then
		return
	end
	local anchor = neon(Enum.PartType.Block, DODGE_COLOR)
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(root.Position)
	local billboard = Instance.new("BillboardGui")
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromOffset(150, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = FONTS.Display
	label.TextScaled = true
	label.Text = "¡Esquivado!"
	label.TextColor3 = DODGE_COLOR
	label.TextStrokeColor3 = INK
	label.TextStrokeTransparency = 0
	label.Parent = billboard
	billboard.Parent = anchor
	TweenService:Create(billboard, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffsetWorldSpace = Vector3.new(0, 6, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.45), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 0.8)
	if dodgeSound then
		dodgeSound.PlaybackSpeed = 1.5 + math.random() * 0.2
		dodgeSound:Play()
	end
end

-- ¿Al soltar el golpe estabas fuera de su alcance (con margen: lo decide el servidor)?
local function dodged(warning: Warning): boolean
	local root = myRoot()
	local enemyRoot = warning.Model.PrimaryPart
	if not (root and enemyRoot and warning.Model.Parent) then
		return false
	end
	local stunUntil = warning.Model:GetAttribute("StunUntil")
	if typeof(stunUntil) == "number" and stunUntil > warning.At then
		return false -- parado o aturdido: ese golpe no salió
	end
	local offset = Vector3.new(root.Position.X - enemyRoot.Position.X, 0, root.Position.Z - enemyRoot.Position.Z)
	local distance = offset.Magnitude
	if distance > warning.Reach + 1 then
		return true
	end
	return distance > 2 and offset.Unit:Dot(warning.Direction) < FRONT_DOT - 0.15
end

local function onAttack(model: Model)
	local at = model:GetAttribute("AttackAt")
	if typeof(at) ~= "number" then
		clear(model)
		return
	end
	if model:GetAttribute("AttackTarget") ~= player.UserId then
		clear(model) -- va a por otro
		return
	end
	local now = serverNow()
	local root = model.PrimaryPart
	if at <= now or not root then
		return
	end
	clear(model)
	if count >= MAX_WARNINGS then
		return
	end
	local direction = model:GetAttribute("AttackDir")
	direction = if typeof(direction) == "Vector3" and direction.Magnitude > 0.05 then Vector3.new(direction.X, 0, direction.Z).Unit else root.CFrame.LookVector
	local reach = model:GetAttribute("AttackReach")
	reach = if typeof(reach) == "number" and reach > 0 then reach else 6
	local bar, dot, size, height = buildMark(model, root)
	local ground, fill, outline, back = buildGround(root.Position, direction, reach, groundBelow(root.Position, model))
	local warning: Warning = {
		Model = model,
		At = at,
		Started = now,
		Reach = reach,
		Direction = direction,
		Root = root,
		Bar = bar,
		Dot = dot,
		Size = size,
		Height = height,
		Ground = ground,
		Fill = fill,
		Outline = outline,
		Back = back,
		Gold = false,
	}
	warnings[model] = warning
	placeMark(warning, 0.2, 0)
	count += 1
end

local function update()
	local now = serverNow()
	for model, warning in warnings do
		local diedAt = model:GetAttribute("DiedAt")
		if not model.Parent or typeof(diedAt) == "number" then
			clear(model)
			continue
		end
		if now >= warning.At then
			local wasDodged = dodged(warning)
			clear(model)
			if wasDodged then
				showDodge()
			end
			continue
		end
		local total = math.max(0.05, warning.At - warning.Started)
		local progress = math.clamp((now - warning.Started) / total, 0, 1)
		-- La media luna se llena; al final, todo dorado: ¡ahora! (bloquear o apartarse)
		warning.Fill.Size = UDim2.fromScale(progress, progress * 2)
		local gold = warning.At - now <= PARRY_WINDOW
		if gold ~= warning.Gold then
			warning.Gold = gold
			local color = if gold then GOLD else RED
			warning.Bar.Color = color
			warning.Dot.Color = color
			warning.Fill.BackgroundColor3 = color
			warning.Outline.Color = color
			warning.Back.BackgroundColor3 = color
		end
		-- Aparece de golpe (con rebote), tiembla mientras se prepara y en dorado late más grande
		local appear = math.clamp((now - warning.Started) / 0.14, 0, 1)
		local pop = if appear < 1 then 0.2 + 1.1 * appear else 1
		if gold then
			pop = 1.25 + math.abs(math.sin(now * 18)) * 0.15
		end
		placeMark(warning, pop, if gold then 0 else math.sin(now * 40) * 8)
	end
end

local function watch(model: Instance)
	if not model:IsA("Model") or watched[model] then
		return
	end
	watched[model] = model:GetAttributeChangedSignal("AttackAt"):Connect(function()
		onAttack(model)
	end)
	model.Destroying:Once(function()
		local connection = watched[model]
		if connection then
			connection:Disconnect()
		end
		watched[model] = nil
		clear(model)
	end)
end

-- Bichos: Workspace.Enemies.<Zona>.<Modelo> (se reutilizan: se vigila cada modelo una vez)
local function watchFolder(folder: Instance)
	if not folder:IsA("Folder") then
		return
	end
	folder.ChildAdded:Connect(watch)
	for _, child in folder:GetChildren() do
		watch(child)
	end
end

function AttackWarning.start()
	local existing = Workspace:FindFirstChild("ClientAttackWarnings")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientAttackWarnings"
	folder.Parent = Workspace
	fxFolder = folder

	local spec = StyleConfig.Sounds.Whirl
	if spec then
		local sound = Instance.new("Sound")
		sound.SoundId = spec.Id
		sound.Volume = spec.Volume * 0.7
		sound.Parent = SoundService
		dodgeSound = sound
	end

	task.spawn(function()
		local enemies = Workspace:WaitForChild("Enemies")
		enemies.ChildAdded:Connect(watchFolder)
		for _, child in enemies:GetChildren() do
			watchFolder(child)
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return AttackWarning
