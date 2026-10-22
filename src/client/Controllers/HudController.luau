-- HUD de Monedas estilo `HUD Rediseño (standalone).html` + Panel de la Tienda de Mejoras y Láser:
-- - A la izquierda: pila vertical limpia con:
--     1. Icono 3D de Rayo + cantidad de Energía en crema con borde oscuro + botón cuadrado verde `+`.
--     2. Pastilla naranja `×1.1` + texto `"Multiplicador"`.
--     3. Icono 3D de Cristal / Tokens de Renacimiento + cantidad en lavanda con borde oscuro,
--        y a su lado 💰 Dinero (lo sueltan los enemigos) en dorado.
-- - Panel "LaserShop" (abierto en el puesto Mejorar Láser del pueblo): sus mejoras se pagan
--   con dinero.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local Constants = require(Shared.Constants)
local Economy = require(Shared.Economy)
local CombatMath = require(Shared.CombatMath)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local Icons = require(script.Parent.Parent.UI.Icons)
local RevealGate = require(script.Parent.Parent.Pets.RevealGate)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local HudLayout = require(script.Parent.Parent.UI.HudLayout)
local Juice = require(script.Parent.Parent.UI.Juice)

local PENDING_TIMEOUT = 2
local FEEDBACK_SECONDS = 2.5
local LASER_PANEL_SIZE = Vector2.new(540, 430)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local INK = Color3.fromRGB(43, 29, 63) -- #2B1D3F
local CREAM = Color3.fromRGB(255, 246, 224) -- #FFF6E0
local MULT_GOLD = Color3.fromRGB(255, 231, 168) -- #FFE7A8
local TOKENS_LAVENDER = Color3.fromRGB(231, 216, 255) -- #E7D8FF
local MONEY_GOLD = Color3.fromRGB(255, 218, 92)

local RESULT_MESSAGES = {
	[Constants.PurchaseCodes.Success] = "¡Mejora comprada!",
	[Constants.PurchaseCodes.InsufficientEnergy] = "Energía insuficiente",
	[Constants.PurchaseCodes.InsufficientMoney] = "Dinero insuficiente: derrota enemigos",
	[Constants.PurchaseCodes.MaxLevel] = "Nivel máximo alcanzado",
	[Constants.PurchaseCodes.TooFast] = "Demasiado rápido, espera un momento",
	[Constants.PurchaseCodes.NotReady] = "Cargando datos, inténtalo de nuevo",
	[Constants.PurchaseCodes.InvalidRequest] = "Solicitud no válida",
}

local SHOP_UPGRADES = {
	{
		Id = "LaserPower",
		Icon = "⚡",
		Title = "Potencia del Láser",
		Color = Color3.fromRGB(70, 235, 255),
		Describe = function(level: number): string
			return ("Daño del láser: 💥 %s → %s"):format(formatNumber(CombatMath.playerDamage(level, 1)), formatNumber(CombatMath.playerDamage(level + 1, 1)))
		end,
	},
	{
		Id = "WalkSpeed",
		Icon = "👟",
		Title = "Velocidad de Correr",
		Color = Color3.fromRGB(110, 245, 130),
		Describe = function(level: number): string
			local curSpd = 28 + level * 2.5
			local nextSpd = 28 + (level + 1) * 2.5
			return ("Velocidad al correr: 🏃 %.1f → %.1f"):format(curSpd, nextSpd)
		end,
	},
	{
		Id = "PetPower",
		Icon = "🐾",
		Title = "Poder de Mascotas",
		Color = Color3.fromRGB(255, 205, 75),
		Describe = function(level: number): string
			local curPct = 100 + level * 25
			local nextPct = 100 + (level + 1) * 25
			return ("Daño de tus mascotas: 🐾 %d%% → %d%%"):format(curPct, nextPct)
		end,
	},
	{
		Id = "LaserSpeed",
		Icon = "🔋",
		Title = "Cadencia del Láser",
		Color = Color3.fromRGB(205, 115, 255),
		Describe = function(level: number): string
			local curInt = math.max(0.2, 0.55 - level * 0.022)
			local nextInt = math.max(0.2, 0.55 - (level + 1) * 0.022)
			return ("Velocidad de disparo: ⚡ %.2fs → %.2fs"):format(curInt, nextInt)
		end,
	},
}

local HudController = {}

export type Callbacks = {
	onPurchaseSuccess: (() -> ())?,
}

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
	local existing = playerGui:FindFirstChild("EnergyHud")
	if existing then
		existing:Destroy()
	end

	local screenGui = create("ScreenGui", {
		Name = "EnergyHud",
		ResetOnSpawn = false,
		DisplayOrder = 4,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)

	-- Pila izquierda de monedas (Energía + Multiplicador + Tokens de Renacimiento y Dinero)
	local energyCard = create("Frame", {
		Name = "EnergyCard",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 18, 0.30, 0),
		Size = UDim2.fromOffset(290, 154),
		BackgroundTransparency = 1,
	}, screenGui)
	local energyScale = create("UIScale", {}, energyCard)

	-- Fila 1: Icono de Rayo + Número de Energía + Botón `+` verde
	local energyRow = create("Frame", {
		Name = "EnergyRow",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(290, 62),
		BackgroundTransparency = 1,
	}, energyCard)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	}, energyRow)

	local boltHolder = Icons.make(energyRow, "energy", {
		Name = "EnergyIcon",
		Size = UDim2.fromOffset(60, 60),
		Rotation = -8,
		ZIndex = 3,
	})
	boltHolder.LayoutOrder = 1

	local energyValue = createText(energyRow, "Value", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 56),
		TextSize = 44,
		TextColor3 = CREAM,
		Text = "0",
		LayoutOrder = 2,
		ZIndex = 3,
	})
	addStroke(energyValue, 4, Enum.ApplyStrokeMode.Contextual)
	local energyPop = create("UIScale", { Name = "Pop" }, energyValue)

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
	}, energyRow)
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
	}, energyCard)
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
	}, energyCard)
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

	-- 💰 Dinero (lo sueltan los enemigos) en dorado, en la misma fila que los tokens: debajo
	-- empieza la columna de avisos y misiones (HudLayout cuenta con una tarjeta baja).
	local moneyGap = create("Frame", {
		Name = "MoneyGap",
		Size = UDim2.fromOffset(6, 10),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
	}, tokensRow)
	local _ = moneyGap
	local moneyIcon = Icons.make(tokensRow, "money", {
		Name = "MoneyIcon",
		Size = UDim2.fromOffset(42, 42),
		Rotation = -6,
		ZIndex = 3,
	})
	moneyIcon.LayoutOrder = 4

	local moneyValue = createText(tokensRow, "Money", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 48),
		TextSize = 36,
		TextColor3 = MONEY_GOLD,
		Text = "0",
		LayoutOrder = 5,
		ZIndex = 3,
	})
	addStroke(moneyValue, 3.6, Enum.ApplyStrokeMode.Contextual)
	local moneyPop = create("UIScale", { Name = "Pop" }, moneyValue)

	-- Panel de la Tienda de Láser y Mejoras (abierto desde el puesto ⚡ MEJORAR LÁSER) -------
	local laserPanel, laserScale = UiKit.panel(screenGui, "LaserShopPanel", LASER_PANEL_SIZE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.18))
	UiKit.text(laserPanel, "Title", {
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -90, 0, 32),
		Font = FONTS.Display,
		TextSize = 26,
		Text = "⚡ Tienda de Láser y Mejoras",
	})
	UiKit.text(laserPanel, "Subtitle", {
		Position = UDim2.fromOffset(22, 48),
		Size = UDim2.new(1, -44, 0, 20),
		Font = FONTS.Light,
		TextSize = 15,
		TextColor3 = THEME.Muted,
		Text = "Se paga con el 💰 dinero que sueltan los enemigos.",
	})
	local laserClose = UiKit.button(laserPanel, "Close", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = THEME.Inset,
		Text = "×",
	})

	local list = UiKit.create("ScrollingFrame", {
		Name = "UpgradeList",
		Position = UDim2.fromOffset(22, 78),
		Size = UDim2.new(1, -44, 1, -120),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = THEME.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, laserPanel)
	UiKit.create("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)

	local rows = {}
	for order, spec in SHOP_UPGRADES do
		local row = UiKit.create("Frame", {
			Name = "Row_" .. spec.Id,
			Size = UDim2.new(1, -8, 0, 68),
			BackgroundColor3 = THEME.Inset,
			LayoutOrder = order,
		}, list)
		UiKit.corner(row, 12)
		UiKit.stroke(row, spec.Color, 1.4, 0.25)

		local titleLabel = UiKit.text(row, "Title", {
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -200, 0, 24),
			Font = FONTS.Display,
			TextSize = 19,
			TextColor3 = spec.Color,
			Text = spec.Icon .. "  " .. spec.Title,
		})
		local descLabel = UiKit.text(row, "Desc", {
			Position = UDim2.fromOffset(14, 34),
			Size = UDim2.new(1, -200, 0, 22),
			Font = FONTS.Light,
			TextSize = 14,
			TextColor3 = THEME.Text,
		})
		local buyBtn = UiKit.button(row, "BuyButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(170, 44),
			TextSize = 16,
		})
		rows[spec.Id] = {
			Spec = spec,
			Title = titleLabel,
			Desc = descLabel,
			Button = buyBtn,
		}
	end

	local laserFeedback = UiKit.text(laserPanel, "Feedback", {
		Position = UDim2.new(0, 22, 1, -34),
		Size = UDim2.new(1, -44, 0, 22),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	screenGui.Parent = playerGui

	return {
		ScreenGui = screenGui,
		Scales = { energyScale },
		EnergyCard = energyCard,
		EnergyValue = energyValue,
		EnergyPop = energyPop,
		MultValue = multValue,
		TokensValue = tokensValue,
		MoneyValue = moneyValue,
		MoneyPop = moneyPop,
		LaserPanel = laserPanel,
		LaserScale = laserScale,
		LaserClose = laserClose,
		Rows = rows,
		LaserFeedback = laserFeedback,
	}
end

function HudController.start(callbacks: Callbacks?)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local purchaseRemote = remotes:WaitForChild(Constants.Remotes.PurchaseUpgrade) :: RemoteEvent
	local resultRemote = remotes:WaitForChild(Constants.Remotes.PurchaseResult) :: RemoteEvent

	local ui = buildGui(playerGui)

	local pendingToken = 0
	local pending = false
	local feedbackToken = 0

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
	applyScale()

	local lastEnergy: number? = nil
	local function popEnergy(energy: number, production: number)
		local previous = lastEnergy
		lastEnergy = energy
		if previous and energy - previous > math.max(production * 2, 1) then
			ui.EnergyPop.Scale = 1.12
			TweenService:Create(ui.EnergyPop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
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
		local energy = player:GetAttribute(Constants.Attributes.Energy)
		local production = player:GetAttribute(Constants.Attributes.ProductionPerSecond)
		local tokens = player:GetAttribute(Constants.Attributes.RebirthTokens)
		local tokenCount = if typeof(tokens) == "number" and tokens > 0 then tokens else 0
		ui.TokensValue.Text = formatNumber(tokenCount)
		local rawMoney = player:GetAttribute(Constants.Attributes.Money)
		local money = if typeof(rawMoney) == "number" then rawMoney else 0
		ui.MoneyValue.Text = formatNumber(money)
		popMoney(money)

		if typeof(energy) ~= "number" or typeof(production) ~= "number" then
			ui.EnergyValue.Text = "0"
			return
		end

		ui.EnergyValue.Text = formatNumber(energy)
		local petMult = player:GetAttribute(Constants.Attributes.PetMultiplier)
		local multVal = if typeof(petMult) == "number" and petMult > 0 then petMult else 1
		ui.MultValue.Text = ("×%s"):format(formatNumber(multVal, 1))
		popEnergy(energy, production)

		for upgradeId, row in ui.Rows do
			local def = EconomyConfig.Upgrades[upgradeId]
			local attr = Constants.Attributes.UpgradeLevelPrefix .. upgradeId
			local level = player:GetAttribute(attr)
			local lvl = if typeof(level) == "number" then level else 0
			local maxLvl = if def then def.MaxLevel else 50
			row.Title.Text = ("%s  %s  (Nv. %d/%d)"):format(row.Spec.Icon, row.Spec.Title, lvl, maxLvl)
			row.Desc.Text = row.Spec.Describe(lvl)

			if lvl >= maxLvl then
				row.Button.Text = "MÁXIMO"
				row.Button.BackgroundColor3 = THEME.Max
				row.Button.TextColor3 = THEME.Text
				UiKit.setDisabled(row.Button, true)
			else
				local cost = Economy.getUpgradeCost(upgradeId, lvl) or 0
				local affordable = (if Economy.getUpgradeCurrency(upgradeId) == "Money" then money else energy) >= cost
				row.Button.Text = ("Mejorar · $%s"):format(formatNumber(cost))
				row.Button.BackgroundColor3 = if affordable then THEME.Buy else THEME.Disabled
				row.Button.TextColor3 = if affordable then THEME.Text else THEME.Muted
				UiKit.setDisabled(row.Button, not affordable)
			end
		end
	end

	PanelManager.register("LaserShop", ui.LaserPanel, { OnOpen = refresh })
	UiKit.bindModalLayout(ui.ScreenGui, ui.LaserScale, LASER_PANEL_SIZE, function(position)
		PanelManager.setBasePosition("LaserShop", position)
	end)
	ui.LaserClose.Activated:Connect(function()
		PanelManager.close("LaserShop")
	end)

	local function showFeedback(text: string, color: Color3)
		feedbackToken += 1
		local token = feedbackToken
		ui.LaserFeedback.Text = text
		ui.LaserFeedback.TextColor3 = color
		task.delay(FEEDBACK_SECONDS, function()
			if feedbackToken == token then
				ui.LaserFeedback.Text = ""
			end
		end)
	end

	local combo, lastPurchaseAt = 0, 0
	local function playSuccessEffects()
		local now = os.clock()
		combo = if now - lastPurchaseAt < 1.2 then math.min(combo + 1, 10) else 0
		lastPurchaseAt = now
		Juice.sound(Juice.Sounds.Upgrade, 1 + combo * 0.05)

		if callbacks and callbacks.onPurchaseSuccess then
			pcall(callbacks.onPurchaseSuccess)
		end
	end

	for upgradeId, row in ui.Rows do
		row.Button.Activated:Connect(function()
			if pending then
				return
			end
			pending = true
			pendingToken += 1
			local token = pendingToken
			purchaseRemote:FireServer(upgradeId)

			task.delay(PENDING_TIMEOUT, function()
				if pendingToken == token then
					pending = false
				end
			end)
		end)
	end

	resultRemote.OnClientEvent:Connect(function(success: boolean, code: string)
		pending = false
		local message = RESULT_MESSAGES[code] or tostring(code)
		if success then
			showFeedback(message, THEME.BuyHighlight)
			playSuccessEffects()
		else
			showFeedback(message, THEME.Error)
		end
		refresh()
	end)

	player:GetAttributeChangedSignal(Constants.Attributes.Energy):Connect(refresh)
	player:GetAttributeChangedSignal(Constants.Attributes.ProductionPerSecond):Connect(refresh)
	for upgradeId in EconomyConfig.Upgrades do
		player:GetAttributeChangedSignal(Constants.Attributes.UpgradeLevelPrefix .. upgradeId):Connect(refresh)
	end
	player:GetAttributeChangedSignal(Constants.Attributes.AutoUpgrade):Connect(refresh)
	player:GetAttributeChangedSignal(Constants.Attributes.RebirthTokens):Connect(refresh)
	player:GetAttributeChangedSignal(Constants.Attributes.PetMultiplier):Connect(refresh)
	player:GetAttributeChangedSignal(Constants.Attributes.Money):Connect(refresh)
	RevealGate.Released:Connect(refresh)

	refresh()
end

return HudController
