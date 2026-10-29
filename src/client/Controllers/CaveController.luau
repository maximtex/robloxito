-- Mazmorras en este cliente (CaveConfig: una cueva por zona; el viaje lo hace CaveService):
-- - Fundido a negro al cruzar la boca o un portal de salida ("Fade"), con el nombre de a
--   dónde vas, y vuelta a ver al llegar ("Arrived"; si no llegara, se quita solo). Al llegar
--   la cámara mira hacia donde apuntas (Facing): seguir andando te aleja de la boca o del
--   portal en vez de devolverte.
-- - Cartel grande al entrar en cada sala ("SALA 2 · LA GALERÍA" y lo que hay dentro).
-- - Dentro (y en la boca): eco de cueva y el tinte de cada cueva (Theme.Tint).
-- - Las puertas entre salas las lleva CaveGates (aquí se arranca y se le pasa el aviso
--   "Blocked") y las trampas, CaveTraps ("Trap").
-- Solo decorativo: nada se replica.

local Lighting = game:GetService("Lighting")
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
local ZoneConfig = require(Shared.Config.ZoneConfig)
local CaveGates = require(script.Parent.CaveGates)
local CaveTraps = require(script.Parent.CaveTraps)

local CaveController = {}

local player = Players.LocalPlayer
local RGB = Color3.fromRGB
local CHECK_SECONDS = 0.25
local FAILSAFE_SECONDS = 4

local gui: ScreenGui
local black: Frame
local title: TextLabel
local subtitle: TextLabel
local banner: Frame
local bannerTitle: TextLabel
local bannerText: TextLabel
local fadeToken = 0
local bannerToken = 0
local tint: ColorCorrectionEffect? = nil

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

local function text(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3, font: Enum.Font): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = size
	label.Position = position
	label.Font = font
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeColor3 = RGB(20, 12, 36)
	label.TextStrokeTransparency = 0.2
	label.Parent = parent
	return label
end

local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "CaveHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20 -- el fundido tapa todo el HUD
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	black = Instance.new("Frame")
	black.Name = "Fundido"
	black.Size = UDim2.fromScale(1, 1)
	black.BackgroundColor3 = RGB(4, 2, 10)
	black.BackgroundTransparency = 1
	black.BorderSizePixel = 0
	black.Visible = false
	black.Parent = gui
	title = text(black, "Titulo", UDim2.new(0.8, 0, 0.09, 0), UDim2.fromScale(0.5, 0.46), RGB(230, 210, 255), Enum.Font.FredokaOne)
	subtitle = text(black, "Subtitulo", UDim2.new(0.6, 0, 0.045, 0), UDim2.fromScale(0.5, 0.54), RGB(200, 190, 230), Enum.Font.GothamBold)

	-- Cartel de cada sala, en el centro por encima del personaje (debajo de la tarjeta del
	-- tutorial y del panel de las oleadas)
	banner = Instance.new("Frame")
	banner.Name = "CartelSala"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.fromScale(0.5, 0.36)
	banner.Size = UDim2.new(0.5, 0, 0.11, 0)
	banner.BackgroundTransparency = 1
	banner.Visible = false
	banner.Parent = gui
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(620, 120)
	constraint.Parent = banner
	bannerTitle = text(banner, "Titulo", UDim2.fromScale(1, 0.62), UDim2.fromScale(0.5, 0.31), RGB(255, 236, 170), Enum.Font.FredokaOne)
	bannerText = text(banner, "Texto", UDim2.fromScale(0.8, 0.32), UDim2.fromScale(0.5, 0.82), RGB(230, 220, 255), Enum.Font.GothamBold)

	gui.Parent = player:WaitForChild("PlayerGui")
end

local function setFade(shown: boolean, seconds: number)
	local goal = if shown then 0 else 1
	if shown then
		black.Visible = true
	end
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(black, info, { BackgroundTransparency = goal }):Play()
	TweenService:Create(title, info, { TextTransparency = goal, TextStrokeTransparency = if shown then 0.2 else 1 }):Play()
	TweenService:Create(subtitle, info, { TextTransparency = goal, TextStrokeTransparency = if shown then 0.2 else 1 }):Play()
	if not shown then
		local token = fadeToken
		task.delay(seconds, function()
			if token == fadeToken then
				black.Visible = false
			end
		end)
	end
end

local ZONE_ICONS = { Forest = "🏡", ThornWoods = "🌲", CrystalValley = "💎", EmberCaldera = "🌋", FrozenTundra = "❄️", GoblinFortress = "🏰", World2 = "🌍", DividedLands = "⚖️" }

local function onFade(data)
	fadeToken += 1
	local token = fadeToken
	local inside = type(data) == "table" and data.Inside == true
	local cave = (type(data) == "table" and CaveLogic.cave(data.Cave)) or CaveConfig.Caves[CaveConfig.Order[1]]
	-- Al salir apareces delante de la boca: en su zona (la del Bosque, en el Bosque de Espinas)
	local outsideZone = cave.EntranceZone or cave.Zone
	local zone = ZoneConfig.Zones[outsideZone]
	title.Text = if inside then ("%s %s"):format(cave.Icon or "🦇", string.upper(cave.Name)) else ("%s %s"):format(ZONE_ICONS[outsideZone] or "🌲", string.upper(zone and zone.DisplayName or "Bosque de Espinas"))
	subtitle.Text = if inside then (cave.Subtitle or "") else "Saliendo de la cueva…"
	title.TextTransparency, subtitle.TextTransparency = 1, 1
	sound(CaveConfig.Sounds.Enter)
	setFade(true, CaveConfig.Travel.FadeSeconds)
	-- Por si no llega "Arrived" (se cae la conexión un momento): se quita solo
	task.delay(FAILSAFE_SECONDS, function()
		if token == fadeToken and black.Visible then
			setFade(false, 0.6)
		end
	end)
end

-- Cámara detrás del personaje mirando hacia `facing` (con el mismo zoom que llevaba)
local function faceCamera(position: Vector3?, facing: Vector3?)
	local camera = Workspace.CurrentCamera
	if not (camera and typeof(position) == "Vector3" and typeof(facing) == "Vector3") then
		return
	end
	local flat = Vector3.new(facing.X, 0, facing.Z)
	if flat.Magnitude < 0.01 then
		return
	end
	flat = flat.Unit
	-- Espera a que el personaje esté ya allí (lo movió el servidor)
	local root
	for _ = 1, 30 do
		local character = player.Character
		root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - position).Magnitude < 12 then
			break
		end
		task.wait(0.05)
	end
	if not (root and root:IsA("BasePart")) or camera.CameraType ~= Enum.CameraType.Custom then
		return
	end
	local zoom = math.clamp((camera.CFrame.Position - camera.Focus.Position).Magnitude, 8, 30)
	local focus = root.Position + Vector3.new(0, 1.5, 0)
	camera.CFrame = CFrame.lookAt(focus - flat * zoom * 0.92 + Vector3.new(0, zoom * 0.4, 0), focus)
end

local function onArrived(data)
	local token = fadeToken
	if type(data) == "table" then
		task.spawn(faceCamera, data.Position, data.Facing)
	end
	task.delay(0.35, function()
		if token == fadeToken then
			setFade(false, 0.7)
		end
	end)
end

local function showBanner(room)
	bannerToken += 1
	local token = bannerToken
	bannerTitle.Text = room.Label
	bannerText.Text = room.Text
	banner.Visible = true
	banner.Position = UDim2.fromScale(0.5, 0.32)
	for _, label in { bannerTitle, bannerText } do
		label.TextTransparency = 1
		label.TextStrokeTransparency = 1
		TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 0, TextStrokeTransparency = 0.2 }):Play()
	end
	TweenService:Create(banner, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.36) }):Play()
	sound(CaveConfig.Sounds.Room)
	task.delay(3.2, function()
		if token ~= bannerToken then
			return
		end
		for _, label in { bannerTitle, bannerText } do
			TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
		task.delay(0.6, function()
			if token == bannerToken then
				banner.Visible = false
			end
		end)
	end)
end

-- Tinte dentro de la cueva (el de cada una; en Lighting, aparte del de las oleadas)
local function setTint(on: boolean, spec)
	if on and not tint then
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "CaveTint"
		effect.Brightness = 0
		effect.Contrast = 0
		effect.Saturation = 0
		effect.TintColor = Color3.new(1, 1, 1)
		effect.Parent = Lighting
		tint = effect
	end
	if tint then
		spec = spec or CaveConfig.Tint
		TweenService:Create(tint, TweenInfo.new(0.8), {
			Brightness = if on then spec.Brightness else 0,
			Contrast = if on then spec.Contrast else 0,
			Saturation = if on then spec.Saturation else 0,
			TintColor = if on then spec.TintColor else Color3.new(1, 1, 1),
		}):Play()
	end
end

function CaveController.start()
	buildGui()
	task.spawn(CaveGates.start)
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local eventRemote = remotes:WaitForChild(Constants.Remotes.CaveEvent) :: RemoteEvent
	eventRemote.OnClientEvent:Connect(function(kind: any, data: any)
		if kind == "Fade" then
			onFade(data)
		elseif kind == "Arrived" then
			onArrived(data)
		elseif kind == "Blocked" and type(data) == "table" and type(data.Index) == "number" then
			CaveGates.blocked(data.Index)
		elseif kind == "Trap" then
			CaveTraps.show(data)
		end
	end)

	-- Sala en la que estás y ambiente de cueva (cada poco)
	local lastRoom: number? = nil
	local reverbOn = false
	local tintOn: string? = nil
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < CHECK_SECONDS then
			return
		end
		elapsed = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return
		end
		local position = root.Position
		local roomIndex, room = CaveLogic.roomAt(position.X, position.Z)
		if roomIndex and roomIndex ~= lastRoom then
			showBanner(room)
		end
		lastRoom = roomIndex or (if CaveLogic.inside(position.X, position.Z) then lastRoom else nil)
		local caveId, cave = CaveLogic.caveAt(position.X, position.Z, 4)
		local inDungeon = caveId ~= nil
		local reverb = inDungeon or StudFloor.inCave(position.X, position.Z, 2)
		if reverb ~= reverbOn then
			reverbOn = reverb
			SoundService.AmbientReverb = if reverb then Enum.ReverbType.Cave else Enum.ReverbType.NoReverb
		end
		if caveId ~= tintOn then
			tintOn = caveId
			setTint(inDungeon, cave and cave.Theme and cave.Theme.Tint)
		end
	end)
end

-- ¿Está el jugador dentro de la cueva (salas o pasillos)? Para otros controladores.
function CaveController.isInside(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart") and CaveLogic.inside(root.Position.X, root.Position.Z, 4)
end

return CaveController
