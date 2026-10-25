-- Barra superior del HUD (`HUD Rediseño (standalone).html`):
-- - Arriba en el centro: Pastilla amarilla compacta `.warn-pill` con icono `!` para avisos de
--   estado de datos ("Modo sin guardado · el progreso de esta sesión no se guardará", etc.).
-- - Arriba a la derecha: Cabecera de zona `.zone-card` ("Bosque" / "ZONA 1 · PLAZA DEL CRISTAL").
--   En la boca de la Cueva de los Espinillos dice "ZONA 1 · CUEVA DE LOS ESPINILLOS" y dentro,
--   la sala en la que estás ("CUEVA · SALA 2 · LA GALERÍA", CaveConfig). El eco de cueva y el
--   resto del ambiente los pone CaveController.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared").Constants)
local StudFloor = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("StudFloor"))
local CaveLogic = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CaveLogic"))
local CaveConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CaveConfig"))
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudLayout = require(script.Parent.Parent.UI.HudLayout)

local FONTS = Theme.Fonts
local INK = Color3.fromRGB(43, 29, 63) -- #2B1D3F
local WARN_YELLOW = Color3.fromRGB(255, 201, 60) -- #FFC93C
local CREAM = Color3.fromRGB(255, 246, 224) -- #FFF6E0
local GOLD_SUB = Color3.fromRGB(255, 231, 168) -- #FFE7A8
local SLOW_LOAD_SECONDS = 6

local MESSAGES = {
	TestMode = { Text = "Modo prueba del tutorial · el progreso no se guarda", Bg = WARN_YELLOW },
	Loading = { Text = "Cargando tus datos · tu progreso aparecerá en unos segundos…", Bg = WARN_YELLOW },
	Unavailable = { Text = "Modo sin guardado · el progreso de esta sesión no se guardará", Bg = WARN_YELLOW },
	Failed = { Text = "No se pudieron cargar tus datos · esta sesión no se guardará", Bg = Color3.fromRGB(255, 130, 130) },
	SaveError = { Text = "No se pudo guardar · reintentando automáticamente…", Bg = Color3.fromRGB(255, 130, 130) },
	Saved = { Text = "Progreso guardado ✓", Bg = Color3.fromRGB(156, 236, 140) },
}

local ZONE_HEADERS: { [string]: { Title: string, Sub: string } } = {
	Forest = { Title = "Bosque", Sub = "ZONA 1 · PLAZA DEL CRISTAL" },
	CrystalValley = { Title = "Valle Morado", Sub = "ZONA 2 · VALLE CRISTALINO" },
	EmberCaldera = { Title = "Caldera", Sub = "ZONA 3 · CALDERA DE BRASAS" },
	FrozenTundra = { Title = "Tundra", Sub = "ZONA 4 · TUNDRA HELADA" },
	GoblinFortress = { Title = "Fortaleza", Sub = "ZONA 5 · FORTALEZA GOBLIN" },
	World2 = { Title = "Mundo 2", Sub = "MUNDO 2 · PUEBLO CELESTIAL" },
}

local DataStatusController = {}

function DataStatusController.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("DataStatusHud")
	if existing then
		existing:Destroy()
	end

	local screenGui = UiKit.create("ScreenGui", {
		Name = "DataStatusHud",
		ResetOnSpawn = false,
		DisplayOrder = 4,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)

	-- Pastilla amarilla superior central (.warn-pill)
	local pill = UiKit.create("Frame", {
		Name = "WarnPill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 34),
		BackgroundColor3 = WARN_YELLOW,
		Visible = false,
	}, screenGui)
	local pillScale = UiKit.create("UIScale", {}, pill)
	UiKit.corner(pill, 17)
	UiKit.create("UIStroke", {
		Color = INK,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, pill)
	UiKit.create("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 12),
	}, pill)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, pill)

	local bangCircle = UiKit.create("Frame", {
		Name = "Bang",
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = INK,
		LayoutOrder = 1,
	}, pill)
	UiKit.corner(bangCircle, 10)
	local bangLabel = UiKit.text(bangCircle, "BangText", {
		Size = UDim2.fromScale(1, 1),
		Font = FONTS.Display,
		TextSize = 13,
		TextColor3 = WARN_YELLOW,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "!",
	})

	local title = UiKit.text(pill, "Title", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		Font = FONTS.Display,
		TextSize = 14,
		TextColor3 = INK,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
	})

	local close = UiKit.create("TextButton", {
		Name = "Close",
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.82,
		Font = FONTS.Display,
		TextSize = 14,
		TextColor3 = INK,
		Text = "×",
		LayoutOrder = 3,
	}, pill)
	UiKit.corner(close, 10)

	-- Cabecera de zona arriba a la derecha (.zone-card)
	local zoneCard = UiKit.create("Frame", {
		Name = "ZoneCard",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 10),
		Size = UDim2.fromOffset(240, 48),
		BackgroundTransparency = 1,
	}, screenGui)
	local zoneScale = UiKit.create("UIScale", {}, zoneCard)

	local zoneTitle = UiKit.text(zoneCard, "ZoneTitle", {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 28),
		Font = FONTS.Display,
		TextSize = 26,
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "Bosque",
	})
	UiKit.create("UIStroke", {
		Color = INK,
		Thickness = 3.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, zoneTitle)

	local zoneSub = UiKit.text(zoneCard, "ZoneSub", {
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 16),
		Font = FONTS.Display,
		TextSize = 12,
		TextColor3 = GOLD_SUB,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "ZONA 1 · PLAZA DEL CRISTAL",
	})
	UiKit.create("UIStroke", {
		Color = INK,
		Thickness = 2.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, zoneSub)

	screenGui.Parent = playerGui

	local function applyScale()
		local size = screenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		local s = HudLayout.scale(size, isTouch)
		pillScale.Scale = s
		zoneScale.Scale = s
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyScale)
	applyScale()

	-- "" fuera de la cueva; si no, lo que dice la cabecera en la boca o en cada sala
	local caveLabel = ""
	local function refreshZone()
		local z = player:GetAttribute(Constants.Attributes.CurrentZone)
		local info = (typeof(z) == "string" and ZONE_HEADERS[z]) or ZONE_HEADERS.Forest
		zoneTitle.Text = info.Title
		zoneSub.Text = if caveLabel ~= "" then caveLabel else info.Sub
	end
	player:GetAttributeChangedSignal(Constants.Attributes.CurrentZone):Connect(refreshZone)
	refreshZone()

	-- ¿Estás dentro de la cueva? (cada medio segundo)
	local caveCheck = 0
	RunService.Heartbeat:Connect(function(dt: number)
		caveCheck += dt
		if caveCheck < 0.5 then
			return
		end
		caveCheck = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local label = ""
		if root ~= nil and root:IsA("BasePart") then
			local x, z = root.Position.X, root.Position.Z
			local _, room = CaveLogic.roomAt(x, z)
			if room then
				label = "CUEVA · " .. room.Label
			elseif StudFloor.inCave(x, z) or CaveLogic.inside(x, z, 4) then
				label = "ZONA 1 · " .. string.upper(CaveConfig.Name)
			end
		end
		if label ~= caveLabel then
			caveLabel = label
			refreshZone()
		end
	end)

	local dismissed: { [string]: boolean } = {}
	local shownKey: string? = nil
	local loadingSince = os.clock()
	local hadSaveError = false
	local savedToken = 0

	local function show(key: string?)
		shownKey = key
		local message = key and MESSAGES[key]
		if not message or dismissed[key :: string] then
			pill.Visible = false
			return
		end
		title.Text = message.Text
		pill.BackgroundColor3 = message.Bg
		bangLabel.TextColor3 = message.Bg
		close.Visible = key ~= "Loading" and key ~= "TestMode"
		pill.Visible = true
	end

	local function refresh()
		if player:GetAttribute(Constants.Attributes.TestMode) == true then
			dismissed.TestMode = nil
			show("TestMode")
			return
		end
		local status = player:GetAttribute(Constants.Attributes.DataStatus)
		local saveError = player:GetAttribute(Constants.Attributes.SaveError) == true
		if saveError then
			hadSaveError = true
			dismissed.SaveError = nil
			show("SaveError")
		elseif hadSaveError and status == "Loaded" then
			hadSaveError = false
			savedToken += 1
			local token = savedToken
			show("Saved")
			task.delay(3, function()
				if savedToken == token and shownKey == "Saved" then
					show(nil)
				end
			end)
		elseif status == "Failed" or status == "Unavailable" then
			show(status)
		elseif (status == nil or status == "Loading") and os.clock() - loadingSince >= SLOW_LOAD_SECONDS then
			show("Loading")
		elseif shownKey ~= "Saved" then
			show(nil)
		end
	end

	close.Activated:Connect(function()
		if shownKey then
			dismissed[shownKey] = true
		end
		show(nil)
	end)
	player:GetAttributeChangedSignal(Constants.Attributes.DataStatus):Connect(refresh)
	player:GetAttributeChangedSignal(Constants.Attributes.SaveError):Connect(refresh)
	player:GetAttributeChangedSignal(Constants.Attributes.TestMode):Connect(refresh)
	task.delay(SLOW_LOAD_SECONDS, refresh)
	refresh()
end

return DataStatusController
