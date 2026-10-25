-- Puertas de las mazmorras en este cliente (CaveConfig.Gates, de todas las cuevas; el progreso
-- lo cuenta y lo guarda CaveService y llega en el atributo CaveGates):
-- - Cada puerta cerrada es una losa de roca con runas moradas al principio de su pasillo.
--   Solo existe en este cliente, así que solo te cierra el paso a ti (los que ya la abrieron
--   pasan). En su cara se ve qué pide y cuántos llevas ("7 / 15").
-- - Mientras estás en la sala de una puerta cerrada, arriba se ve el contador y cada bicho que
--   cuenta suena y late.
-- - Al llegar a la cifra, la puerta tiembla, se hunde en el suelo con polvo y un gong y sale
--   el aviso "Se abrió el paso". Las que ya estaban abiertas al entrar no se construyen.
-- Solo decorativo y de colisión local: CaveService devuelve delante a quien se cuele.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local CaveConfig = require(Shared.Config.CaveConfig)
local CaveLogic = require(Shared.CaveLogic)
local StudFloor = require(Shared.Util.StudFloor)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local Toasts = require(script.Parent.Parent.UI.Toasts)
local WaveFx = require(script.Parent.WaveFx)

local CaveGates = {}

local player = Players.LocalPlayer
local RGB = Color3.fromRGB
local FLOOR_TOP = GeneratorConfig.Position.Y + StudFloor.BaseTop
local ROCK = { RGB(104, 108, 140), RGB(86, 90, 120) }
local RUNE = RGB(170, 110, 255)
local OPEN_SECONDS = 1.6

type Door = {
	Index: number,
	Model: Model,
	Slab: Part,
	Runes: { BasePart },
	Count: TextLabel,
	Fill: Frame,
	Opening: boolean,
}

local doors: { [number]: Door } = {}
local progress: { number } = CaveLogic.sanitizeProgress(nil)
local loaded = false
local pill: Frame
local pillText: TextLabel
local pillFill: Frame

local function sound(spec)
	if not spec then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = spec.Id
	s.Volume = spec.Volume or 0.5
	s.PlaybackSpeed = spec.Pitch or 1
	s.Parent = SoundService
	s.Ended:Connect(function()
		s:Destroy()
	end)
	s:Play()
	task.delay(8, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, solid: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = solid
	p.CanQuery = solid
	p.CanTouch = false
	p.CastShadow = solid
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Plastic
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Parent = parent
	return p
end

local function label(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = position
	l.Size = size
	l.Font = font
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeColor3 = RGB(20, 12, 36)
	l.TextStrokeTransparency = 0
	l.Parent = parent
	return l
end

-- Puerta ----------------------------------------------------------------------------------

local function buildDoor(index: number): Door
	local gate = CaveConfig.Gates[index]
	local width, height = CaveLogic.gateSize(index)
	local facing = Vector3.new(gate.Facing.X, 0, gate.Facing.Z).Unit
	local base = Vector3.new(gate.Position.X, FLOOR_TOP, gate.Position.Z)
	local frame = CFrame.lookAt(base, base + facing) -- -Z local: hacia la sala de antes
	local model = Instance.new("Model")
	model.Name = "PuertaCueva" .. index

	-- Losa (un poco más ancha que el pasillo para no dejar rendijas) con studs por delante
	local slab = part(model, "Losa", Vector3.new(width + 0.4, height, 2), frame * CFrame.new(0, height / 2, 0), ROCK[1], true)
	local studs = Instance.new("Texture")
	studs.Name = "Studs"
	studs.Texture = StudFloor.StudTexture
	studs.Face = Enum.NormalId.Front
	studs.StudsPerTileU = 8
	studs.StudsPerTileV = 8
	studs.Parent = slab
	-- Marco más oscuro arriba y a los lados (sin tapar el cartel de la cara)
	part(model, "Marco", Vector3.new(width + 0.6, 1.6, 2.4), frame * CFrame.new(0, height - 0.8, 0), ROCK[2], false)
	-- Runas: dos tiras a los lados y un candado redondo encima de la cuenta
	local runes = {}
	for _, side in { -1, 1 } do
		local strip = part(model, "Runa", Vector3.new(0.6, height - 4, 0.2), frame * CFrame.new(side * (width / 2 - 1.6), height / 2, -1.1), RUNE, false)
		strip.Material = Enum.Material.Neon
		table.insert(runes, strip)
	end
	local lock = part(model, "Candado", Vector3.new(0.2, 4.6, 4.6), frame * CFrame.new(0, height * 0.6, -1.1) * CFrame.Angles(0, math.rad(90), 0), RUNE, false)
	lock.Shape = Enum.PartType.Cylinder
	lock.Material = Enum.Material.Neon
	lock.Transparency = 0.15
	table.insert(runes, lock)
	local glow = Instance.new("PointLight")
	glow.Color = RUNE
	glow.Range = 16
	glow.Brightness = 1.2
	glow.Shadows = false
	glow.Parent = lock

	-- Cartel en la cara: qué abre, qué pide y cuántos llevas
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Cartel"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = slab
	label(gui, "Titulo", UDim2.fromScale(0.08, 0.08), UDim2.fromScale(0.84, 0.12), RGB(255, 236, 170), Enum.Font.FredokaOne).Text = "🔒 " .. string.upper(gate.Opens)
	label(gui, "Pide", UDim2.fromScale(0.1, 0.2), UDim2.fromScale(0.8, 0.07), RGB(230, 220, 255), Enum.Font.GothamBold).Text = CaveLogic.gateAsk(gate)
	local count = label(gui, "Cuenta", UDim2.fromScale(0.2, 0.54), UDim2.fromScale(0.6, 0.16), Color3.new(1, 1, 1), Enum.Font.FredokaOne)
	local track = Instance.new("Frame")
	track.Name = "Barra"
	track.Position = UDim2.fromScale(0.15, 0.74)
	track.Size = UDim2.fromScale(0.7, 0.05)
	track.BackgroundColor3 = RGB(28, 22, 40)
	track.BorderSizePixel = 0
	track.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = track
	local fill = Instance.new("Frame")
	fill.Name = "Relleno"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = RUNE
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner:Clone().Parent = fill

	model.Parent = Workspace
	return { Index = index, Model = model, Slab = slab, Runes = runes, Count = count, Fill = fill, Opening = false }
end

local function refreshDoor(door: Door)
	local gate = CaveConfig.Gates[door.Index]
	local kills = progress[door.Index] or 0
	door.Count.Text = if loaded then ("%d / %d"):format(kills, gate.Kills) else "…"
	door.Fill.Size = UDim2.fromScale(math.clamp(kills / gate.Kills, 0, 1), 1)
end

-- Las runas brillan un momento (un bicho más)
local function pulseDoor(door: Door)
	for _, rune in door.Runes do
		rune.Color = Color3.new(1, 1, 1)
		TweenService:Create(rune, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Color = RUNE }):Play()
	end
end

-- Se abre: tiembla, se hunde en el suelo con polvo y se quita
local function openDoor(door: Door, celebrate: boolean)
	if door.Opening then
		return
	end
	door.Opening = true
	doors[door.Index] = nil
	local gate = CaveConfig.Gates[door.Index]
	if not celebrate then
		door.Model:Destroy()
		return
	end
	local _, height = CaveLogic.gateSize(door.Index)
	sound(CaveConfig.Sounds.GateOpen)
	sound(CaveConfig.Sounds.GateRumble)
	WaveFx.shake(0.45)
	for _, rune in door.Runes do
		rune.Color = Color3.new(1, 1, 1)
	end
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "Polvo"
	dust.Color = ColorSequence.new(RGB(180, 170, 200))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) })
	dust.Transparency = NumberSequence.new(0.4, 1)
	dust.Lifetime = NumberRange.new(0.8, 1.4)
	dust.Speed = NumberRange.new(3, 7)
	dust.SpreadAngle = Vector2.new(70, 20)
	dust.Rate = 60
	dust.Parent = door.Slab
	-- Temblor y bajada (todas las piezas a la vez)
	local start = os.clock()
	local origins = {}
	for _, piece in door.Model:GetDescendants() do
		if piece:IsA("BasePart") then
			origins[piece] = piece.CFrame
			piece.CanCollide = false
		end
	end
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / OPEN_SECONDS, 0, 1)
		local drop = (t ^ 1.6) * (height + 1)
		local shake = (1 - t) * 0.25
		local offset = Vector3.new(math.random() * shake - shake / 2, -drop, math.random() * shake - shake / 2)
		for piece, origin in origins do
			if piece.Parent then
				piece.CFrame = origin + offset
			end
		end
		if t >= 1 then
			connection:Disconnect()
			door.Model:Destroy()
		end
	end)
	Toasts.show(("🔓 ¡Se abrió el paso a %s!"):format(gate.Opens), { Color = RUNE, Key = "CaveGate" })
end

-- Contador de arriba -------------------------------------------------------------------------

local function buildPill()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CaveGatesHud"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 4
	screenGui.Parent = player:WaitForChild("PlayerGui")
	pill = Instance.new("Frame")
	pill.Name = "Contador"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, 132)
	pill.Size = UDim2.fromOffset(330, 46)
	pill.BackgroundColor3 = RGB(30, 22, 46)
	pill.BackgroundTransparency = 0.15
	pill.Visible = false
	pill.Parent = screenGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = pill
	local stroke = Instance.new("UIStroke")
	stroke.Color = RUNE
	stroke.Thickness = 2
	stroke.Parent = pill
	pillText = label(pill, "Texto", UDim2.fromOffset(12, 4), UDim2.new(1, -24, 0, 24), Color3.new(1, 1, 1), Enum.Font.FredokaOne)
	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 14, 1, -14)
	track.Size = UDim2.new(1, -28, 0, 7)
	track.BackgroundColor3 = RGB(60, 48, 84)
	track.BorderSizePixel = 0
	track.Parent = pill
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0.5, 0)
	trackCorner.Parent = track
	pillFill = Instance.new("Frame")
	pillFill.Size = UDim2.fromScale(0, 1)
	pillFill.BackgroundColor3 = RUNE
	pillFill.BorderSizePixel = 0
	pillFill.Parent = track
	trackCorner:Clone().Parent = pillFill
	local scale = Instance.new("UIScale")
	scale.Name = "Pulse"
	scale.Parent = pill
end

local function pulsePill()
	local scale = pill:FindFirstChild("Pulse") :: UIScale?
	if scale then
		scale.Scale = 1.12
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- Muestra el contador si estás en la sala de una puerta cerrada
local function refreshPill()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local index, gate = nil, nil
	if root and root:IsA("BasePart") and loaded then
		local roomIndex = CaveLogic.roomAt(root.Position.X, root.Position.Z)
		index, gate = CaveLogic.gateOfRoom(roomIndex)
		if index and CaveLogic.isOpen(progress, index) then
			index, gate = nil, nil
		end
	end
	pill.Visible = index ~= nil
	if index and gate then
		local kills = progress[index] or 0
		pillText.Text = if gate.MiniBoss then ("🔒 Abre %s: %s"):format(gate.Opens, (CaveLogic.gateAsk(gate):gsub("^D", "d"))) else ("🔒 Abre %s: %d/%d %s"):format(gate.Opens, kills, gate.Kills, gate.Enemies)
		pillFill.Size = UDim2.fromScale(math.clamp(kills / gate.Kills, 0, 1), 1)
	end
end

-- Arranque ------------------------------------------------------------------------------

local function applyProgress(text: any, celebrate: boolean)
	local previous = progress
	loaded = typeof(text) == "string"
	progress = CaveLogic.parseProgress(text)
	for index in CaveConfig.Gates do
		local open = loaded and CaveLogic.isOpen(progress, index)
		local door = doors[index]
		if open and door then
			openDoor(door, celebrate)
		elseif not open and not door then
			door = buildDoor(index)
			doors[index] = door
		end
		if door and doors[index] then
			refreshDoor(door)
			if celebrate and (progress[index] or 0) > (previous[index] or 0) then
				pulseDoor(door)
			end
		end
	end
	if celebrate then
		for index in CaveConfig.Gates do
			if (progress[index] or 0) > (previous[index] or 0) and not CaveLogic.isOpen(progress, index) then
				sound(CaveConfig.Sounds.Count)
				pulsePill()
			end
		end
	end
	refreshPill()
end

-- Aviso de CaveService: estabas detrás de una puerta cerrada
function CaveGates.blocked(index: number)
	local gate = CaveConfig.Gates[index]
	if gate then
		Toasts.show(("🔒 Puerta cerrada: %s para abrir %s"):format((CaveLogic.gateAsk(gate):gsub("^D", "d")), gate.Opens), { Color = RUNE, Key = "CaveGate" })
	end
end

function CaveGates.start()
	buildPill()
	applyProgress(player:GetAttribute(Constants.Attributes.CaveGates), false)
	player:GetAttributeChangedSignal(Constants.Attributes.CaveGates):Connect(function()
		-- Al cargar los datos (de nada a algo) no se celebra: las abiertas simplemente no están
		applyProgress(player:GetAttribute(Constants.Attributes.CaveGates), loaded)
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= 0.3 then
			elapsed = 0
			refreshPill()
		end
	end)
end

return CaveGates
