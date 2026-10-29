-- HUD de Monedas estilo `HUD Rediseño (standalone).html`:
-- - A la izquierda: pila vertical limpia con:
--     1. Gema + cantidad de 💎 Diamantes (atributo Diamonds) en crema con borde oscuro + botón
--        cuadrado verde `+` (abre la 💎 Tienda).
--     2. Pastilla naranja `×1.1` + texto `"Multiplicador"`.
--     3. Icono 3D de Cristal / Tokens de Renacimiento + cantidad en lavanda con borde oscuro,
--        y a su lado el Dinero (lo sueltan los enemigos): fajo de billetes y "$" en verde.
-- Las mejoras que se pagan con dinero están en la Armería (WeaponController).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.UI.Theme)
local Icons = require(script.Parent.Parent.UI.Icons)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local HudLayout = require(script.Parent.Parent.UI.HudLayout)
local UserScale = require(script.Parent.Parent.UI.UserScale)

local FONTS = Theme.Fonts
local INK = Color3.fromRGB(43, 29, 63) -- #2B1D3F
local CREAM = Color3.fromRGB(255, 246, 224) -- #FFF6E0
local MULT_GOLD = Color3.fromRGB(255, 231, 168) -- #FFE7A8
local TOKENS_LAVENDER = Color3.fromRGB(231, 216, 255) -- #E7D8FF
local MONEY_GREEN = Color3.fromRGB(112, 226, 72)

local HudController = {}

local function create(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in properties do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function addCorner(parent: Instance, radius: number)
	create("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function createText(parent: Instance, name: string, properties: { [string]: any }): TextLabel
	local label = create("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Font = FONTS.Display,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}, nil)
	for key, value in properties do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

local function addStroke(parent: Instance, thickness: number, mode: Enum.ApplyStrokeMode?)
	return create("UIStroke", {
		Color = INK,
		Thickness = thickness,
		ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, parent)
end

local function buildGui(playerGui: PlayerGui)
	for _, oldName in { "DiamondHud", "EnergyHud", "MoneyHud", "TopBarHud" } do
		local existing = playerGui:FindFirstChild(oldName)
		if existing then
			existing:Destroy()
		end
	end

	local screenGui = create("ScreenGui", {
		Name = "DiamondHud",
		ResetOnSpawn = false,
		DisplayOrder = 4,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)

	-- Pila izquierda de monedas (Energía + Multiplicador + Tokens de Renacimiento y Dinero)
	local diamondCard = create("Frame", {
		Name = "DiamondCard",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 18, 0.30, 0),
		Size = UDim2.fromOffset(290, 154),
		BackgroundTransparency = 1,
	}, screenGui)
	local diamondScale = create("UIScale", {}, diamondCard)

	-- Fila 1: Icono de Rayo + Número de Energía + Botón `+` verde
	local diamondRow = create("Frame", {
		Name = "DiamondRow",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(290, 62),
		BackgroundTransparency = 1,
	}, diamondCard)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	}, diamondRow)

	-- 💎 Diamantes (Diamonds en el código)
	local boltHolder = Icons.make(diamondRow, "diamond", {
		Name = "DiamondIcon",
		Size = UDim2.fromOffset(60, 60),
		Rotation = -8,
		ZIndex = 3,
	})
	boltHolder.LayoutOrder = 1

	local diamondValue = createText(diamondRow, "Value", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 56),
		TextSize = 44,
		TextColor3 = CREAM,
		Text = "0",
		LayoutOrder = 2,
		ZIndex = 3,
	})
	addStroke(diamondValue, 4, Enum.ApplyStrokeMode.Contextual)
	local diamondPop = create("UIScale", { Name = "Pop" }, diamondValue)

	local plus = create("TextButton", {
		Name = "PlusButton",
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Font = FONTS.Display,
		TextSize = 26,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "+",
		LayoutOrder = 3,
		ZIndex = 4,
	}, diamondRow)
	addCorner(plus, 11)
	create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(182, 245, 166)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(96, 214, 96)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(63, 174, 69)),
		}),
	}, plus)
	addStroke(plus, 3, Enum.ApplyStrokeMode.Border)
	local plusTextStroke = create("UIStroke", {
		Color = INK,
		Thickness = 2.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, plus)
	local _ = plusTextStroke
	plus.Activated:Connect(function()
		PanelManager.open("Shop")
	end)

	-- Fila 2: Pastilla naranja `×1.1` + texto `"Multiplicador"`
	local multRow = create("Frame", {
		Name = "MultiplierRow",
		Position = UDim2.fromOffset(10, 64),
		Size = UDim2.fromOffset(250, 30),
		BackgroundTransparency = 1,
	}, diamondCard)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, multRow)

	local multPill = create("Frame", {
		Name = "MultPill",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(54, 26),
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = 1,
		ZIndex = 3,
	}, multRow)
	addCorner(multPill, 13)
	create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(255, 210, 122), Color3.fromRGB(242, 154, 58)),
	}, multPill)
	addStroke(multPill, 3, Enum.ApplyStrokeMode.Border)
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
	}, multPill)

	local multValue = createText(multPill, "MultValue", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextSize = 15,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "×1",
		ZIndex = 4,
	})
	addStroke(multValue, 2, Enum.ApplyStrokeMode.Contextual)

	local multLabel = createText(multRow, "MultLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		TextSize = 16,
		TextColor3 = MULT_GOLD,
		Text = "Multiplicador",
		LayoutOrder = 2,
		ZIndex = 3,
	})
	addStroke(multLabel, 2.5, Enum.ApplyStrokeMode.Contextual)

	-- Fila 3: Icono de Cristal (Tokens de Renacimiento) + Cantidad en lavanda
	local tokensRow = create("Frame", {
		Name = "TokensBar",
		Position = UDim2.fromOffset(4, 100),
		Size = UDim2.fromOffset(290, 52),
		BackgroundTransparency = 1,
	}, diamondCard)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, tokensRow)

	local tokensIcon = Icons.make(tokensRow, "tokens", {
		Name = "TokensIcon",
		Size = UDim2.fromOffset(48, 48),
		Rotation = 6,
		ZIndex = 3,
	})
	tokensIcon.LayoutOrder = 1

	local tokensValue = createText(tokensRow, "Tokens", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 48),
		TextSize = 36,
		TextColor3 = TOKENS_LAVENDER,
		Text = "0",
		LayoutOrder = 2,
		ZIndex = 3,
	})
	addStroke(tokensValue, 3.6, Enum.ApplyStrokeMode.Contextual)

	-- Dinero (lo sueltan los enemigos): fajo de billetes y cantidad en verde, en la misma fila
	-- que los tokens: debajo empieza la columna de avisos y misiones (HudLayout cuenta con
	-- una tarjeta baja).
	local moneyGap = create("Frame", {
		Name = "MoneyGap",
		Size = UDim2.fromOffset(6, 10),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
	}, tokensRow)
	local _ = moneyGap
	local moneyIcon = Icons.make(tokensRow, "money", {
		Name = "MoneyIcon",
		Size = UDim2.fromOffset(50, 50),
		ZIndex = 3,
	})
	moneyIcon.LayoutOrder = 4

	local moneyValue = createText(tokensRow, "Money", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 48),
		TextSize = 36,
		TextColor3 = MONEY_GREEN,
		Text = "0",
		LayoutOrder = 5,
		ZIndex = 3,
	})
	addStroke(moneyValue, 3.6, Enum.ApplyStrokeMode.Contextual)
	local moneyPop = create("UIScale", { Name = "Pop" }, moneyValue)

	screenGui.Parent = playerGui

	return {
		ScreenGui = screenGui,
		Scales = { diamondScale },
		DiamondCard = diamondCard,
		DiamondValue = diamondValue,
		DiamondPop = diamondPop,
		MultValue = multValue,
		TokensValue = tokensValue,
		MoneyValue = moneyValue,
		MoneyPop = moneyPop,
	}
end

function HudController.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local ui = buildGui(playerGui)

	local function applyScale()
		local size = ui.ScreenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local isTouchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		local scale = HudLayout.scale(size, isTouchOnly)
		for _, uiScale in ui.Scales do
			uiScale.Scale = scale
		end
	end
	ui.ScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyScale)
	UserScale.watch(applyScale) -- ⚙️ tamaño de la interfaz
	applyScale()

	local lastDiamonds: number? = nil
	-- Los 💎 saltan un poco cada vez que suben (enemigos, oleadas, misiones)
	local function popDiamonds(diamonds: number)
		local previous = lastDiamonds
		lastDiamonds = diamonds
		if previous and diamonds > previous then
			ui.DiamondPop.Scale = 1.12
			TweenService:Create(ui.DiamondPop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end

	-- El dinero salta un poco cada vez que sube (al cobrar de un enemigo)
	local lastMoney: number? = nil
	local function popMoney(money: number)
		local previous = lastMoney
		lastMoney = money
		if previous and money > previous then
			ui.MoneyPop.Scale = 1.15
			TweenService:Create(ui.MoneyPop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end

	local function refresh()
		local diamonds = player:GetAttribute(Constants.Attributes.Diamonds)
		local tokens = player:GetAttribute(Constants.Attributes.RebirthTokens)
		local tokenCount = if typeof(tokens) == "number" and tokens > 0 then tokens else 0
		ui.TokensValue.Text = formatNumber(tokenCount)
		local rawMoney = player:GetAttribute(Constants.Attributes.Money)
		local money = if typeof(rawMoney) == "number" then rawMoney else 0
		ui.MoneyValue.Text = "$" .. formatNumber(money)
		popMoney(money)

		if typeof(diamonds) ~= "number" then
			ui.DiamondValue.Text = "0"
			return
		end

		ui.DiamondValue.Text = formatNumber(diamonds)
		local petMult = player:GetAttribute(Constants.Attributes.PetMultiplier)
		local multVal = if typeof(petMult) == "number" and petMult > 0 then petMult else 1
		ui.MultValue.Text = ("×%s"):format(formatNumber(multVal, 1))
		popDiamonds(diamonds)
	end

	player:GetAttributeChangedSignal(Constants.Attributes.Diamonds):Connect(refresh)
	player:GetAttributeChangedSignal(Constants.Attributes.RebirthTokens):Connect(refresh)
	player:GetAttributeChangedSignal(Constants.Attributes.PetMultiplier):Connect(refresh)
	player:GetAttributeChangedSignal(Constants.Attributes.Money):Connect(refresh)

	refresh()
end

return HudController
