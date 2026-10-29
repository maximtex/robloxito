-- WeaponController · WindowGui: construcción de la ventana de la Armería (buildGui): cabecera a rayas, botones de mejoras/clases y fila de tarjetas.
-- Parte de WeaponController (ver WeaponController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.Config.WeaponConfig)
local WeaponLogic = require(Shared.WeaponLogic)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)
local Icons = require(script.Parent.Parent.Parent.UI.Icons)

local ctx: any -- tabla de estado compartida (la crea WeaponController/init.luau)
local CARD_GAP: any
local DISPLAY: any
local HEADER_HEIGHT: any
local INK: any
local ORANGE: any
local PANEL_BG: any
local PANEL_SIZE: any
local PURPLE: any
local RED: any
local ROW_SIZE: any
local STRIPE_A: any
local STRIPE_B: any
local WHITE: any
local WINDOW_SIZE: any
local player: any

-- Funciones de las otras partes
local function arrowButton(...) return ctx.arrowButton(...) end
local function border(...) return ctx.border(...) end
local function buildCard(...) return ctx.buildCard(...) end
local function chunkyButton(...) return ctx.chunkyButton(...) end
local function fill(...) return ctx.fill(...) end
local function outlinedText(...) return ctx.outlinedText(...) end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("ArmoryHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "ArmoryHud",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)

	-- Marco del panel (lo coloca PanelManager y lo escala bindModalLayout) y, dentro, la
	-- ventana con su propia escala para la animación de apertura.
	local panel = UiKit.create("Frame", {
		Name = "ArmoryPanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.12),
		Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y),
		BackgroundTransparency = 1,
		Visible = false,
	}, screenGui)
	local fitScale = UiKit.create("UIScale", {}, panel)
	local holder = UiKit.create("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, panel)
	local popScale = UiKit.create("UIScale", { Name = "Pop" }, holder)

	local shadow = UiKit.create("Frame", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 12),
		Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.65,
	}, holder)
	UiKit.corner(shadow, 24)
	local window = UiKit.create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WINDOW_SIZE.X, WINDOW_SIZE.Y),
		BackgroundColor3 = PANEL_BG,
	}, holder)
	UiKit.corner(window, 20)
	border(window, 5)

	-- Cabecera: rayas naranjas inclinadas (recortadas con CanvasGroup), brillo arriba y raya
	-- oscura abajo
	local stripes = UiKit.create("CanvasGroup", {
		Name = "Stripes",
		Size = UDim2.new(1, 0, 0, HEADER_HEIGHT + 30),
		BackgroundColor3 = STRIPE_A,
		BorderSizePixel = 0,
	}, window)
	UiKit.corner(stripes, 20)
	local spacing = 72 / math.cos(math.rad(25))
	for index = -2, math.ceil(WINDOW_SIZE.X / spacing) + 2 do
		UiKit.create("Frame", {
			Name = "Stripe",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(index * spacing, (HEADER_HEIGHT + 30) / 2),
			Size = UDim2.fromOffset(36, 260),
			Rotation = 25,
			BackgroundColor3 = STRIPE_B,
			BorderSizePixel = 0,
		}, stripes)
	end
	UiKit.create("Frame", {
		Name = "Shine",
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
	}, stripes)
	local body = UiKit.create("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, HEADER_HEIGHT),
		Size = UDim2.new(1, 0, 1, -HEADER_HEIGHT),
		BackgroundColor3 = PANEL_BG,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, window)
	UiKit.corner(body, 20)
	UiKit.create("Frame", {
		Name = "TopSquare", -- solo las esquinas de abajo son redondas
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = PANEL_BG,
		BorderSizePixel = 0,
	}, body)
	UiKit.create("Frame", {
		Name = "HeaderLine",
		Position = UDim2.fromOffset(0, HEADER_HEIGHT - 5),
		Size = UDim2.new(1, 0, 0, 5),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, window)

	local header = UiKit.create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, HEADER_HEIGHT - 5),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, window)
	-- Icono de la cabecera: el dibujo de la Armería (armas) o el emoji de la tienda (🥊, ✨)
	local headerArt = WeaponConfig.ArmoryArt.Header
	local headerImage = nil
	if headerArt then
		headerImage = UiKit.create("ImageLabel", {
			Name = "Icon",
			Position = UDim2.fromOffset(12, -5),
			Size = UDim2.fromOffset(102, 96),
			BackgroundTransparency = 1,
			Image = headerArt,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 3,
		}, header)
	end
	local headerEmoji = UiKit.text(header, "IconEmoji", {
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.fromOffset(102, HEADER_HEIGHT - 5),
		TextSize = 64,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "⚔️",
		Visible = headerImage == nil,
		ZIndex = 3,
	})
	local title = outlinedText(header, "Title", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 126, 0.5, -3),
		Size = UDim2.fromOffset(380, 70),
		Font = DISPLAY,
		TextSize = 60,
		TextColor3 = WHITE,
		Text = "ARMERÍA",
	}, 5, 5)

	-- ⚡ MEJORAS: las habilidades de tu estilo (comprar con 💎, subir de nivel y equipar)
	local skills = chunkyButton(header, "Skills", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 520, 0.5, 0),
		Size = UDim2.fromOffset(190, 58),
		ZIndex = 4,
	}, 12, 4)
	fill(skills, PURPLE, 58)
	outlinedText(skills, "Label", {
		Size = UDim2.fromScale(1, 1),
		Font = DISPLAY,
		TextSize = 28,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "⚡ MEJORAS",
		ZIndex = 5,
	}, 3.5)
	-- 🎭 CLASES: la pasiva de tu estilo (comprar, subir y elegir con 💎)
	local classes = chunkyButton(header, "Classes", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 720, 0.5, 0),
		Size = UDim2.fromOffset(170, 58),
		ZIndex = 4,
	}, 12, 4)
	fill(classes, ORANGE, 58)
	outlinedText(classes, "Label", {
		Size = UDim2.fromScale(1, 1),
		Font = DISPLAY,
		TextSize = 28,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "🎭 CLASES",
		ZIndex = 5,
	}, 3.5)

	local close = chunkyButton(header, "Close", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.5, 0),
		Size = UDim2.fromOffset(58, 58),
		ZIndex = 4,
	}, 10, 4)
	fill(close, RED, 58)
	outlinedText(close, "Label", {
		Size = UDim2.fromScale(1, 1),
		Font = DISPLAY,
		TextSize = 44,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "X",
		ZIndex = 5,
	}, 3.5)

	local moneyPill = UiKit.create("Frame", {
		Name = "Money",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -95, 0.5, 0),
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.3,
		ZIndex = 3,
	}, header)
	UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, moneyPill)
	border(moneyPill, 3)
	UiKit.create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 18) }, moneyPill)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, moneyPill)
	local moneyIcon = Icons.make(moneyPill, "money", {
		Name = "Icon",
		Size = UDim2.fromOffset(38, 38),
		ZIndex = 4,
	})
	moneyIcon.LayoutOrder = 1
	local moneyLabel = outlinedText(moneyPill, "Amount", {
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = DISPLAY,
		TextSize = 28,
		TextColor3 = WHITE,
		LayoutOrder = 2,
		ZIndex = 4,
	}, 3)

	-- Fila de tarjetas con desplazamiento horizontal
	local row = UiKit.create("ScrollingFrame", {
		Name = "Cards",
		Position = UDim2.fromOffset(16, 14),
		Size = UDim2.fromOffset(ROW_SIZE.X, ROW_SIZE.Y),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ElasticBehavior = Enum.ElasticBehavior.Never,
		ZIndex = 3,
	}, body)
	UiKit.create("UIPadding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		PaddingTop = UDim.new(0, 4),
	}, row)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, CARD_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	local cards = {}
	for order, weaponId in WeaponLogic.ordered() do
		cards[weaponId] = buildCard(row, weaponId, WeaponConfig.Weapons[weaponId], order)
	end
	local left = arrowButton(body, "Left", "‹", -1)
	local right = arrowButton(body, "Right", "›", 1)

	local toast = UiKit.create("TextLabel", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -7),
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = INK,
		Font = DISPLAY,
		TextSize = 20,
		Text = "",
		Visible = false,
		ZIndex = 8,
	}, body)
	UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, toast)
	border(toast, 3, WHITE)
	UiKit.create("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22) }, toast)

	screenGui.Parent = playerGui
	return {
		ScreenGui = screenGui,
		Panel = panel,
		FitScale = fitScale,
		PopScale = popScale,
		Header = header,
		HeaderImage = headerImage,
		HeaderEmoji = headerEmoji,
		Title = title,
		Skills = skills,
		Classes = classes,
		Close = close,
		Money = moneyLabel,
		Row = row,
		Cards = cards,
		Left = left,
		Right = right,
		Toast = toast,
	}
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.buildGui = buildGui
end

function Part.link(context: any)
	CARD_GAP = context.CARD_GAP
	DISPLAY = context.DISPLAY
	HEADER_HEIGHT = context.HEADER_HEIGHT
	INK = context.INK
	ORANGE = context.ORANGE
	PANEL_BG = context.PANEL_BG
	PANEL_SIZE = context.PANEL_SIZE
	PURPLE = context.PURPLE
	RED = context.RED
	ROW_SIZE = context.ROW_SIZE
	STRIPE_A = context.STRIPE_A
	STRIPE_B = context.STRIPE_B
	WHITE = context.WHITE
	WINDOW_SIZE = context.WINDOW_SIZE
	player = context.player
end

return Part
