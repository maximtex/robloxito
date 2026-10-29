-- InventoryController · Gui: construcción del panel del inventario, pestañas, vista 3D de revelación y HUD de pociones activas.
-- Parte de InventoryController (ver InventoryController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared.Config.ItemConfig)
local ItemLogic = require(Shared.ItemLogic)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.Parent.UI.PanelManager)

local ctx: any -- tabla de estado compartida (la crea InventoryController/init.luau)
local CELL: any
local CONTENT_LEFT: any
local FONTS: any
local INK: any
local PANEL_SIZE: any
local SIDEBAR_WIDTH: any
local TABS: any
local THEME: any
local TOP: any
local player: any

-- Funciones de las otras partes
local function darker(...) return ctx.darker(...) end
local function label(...) return ctx.label(...) end

-- Interfaz -----------------------------------------------------------------------------------

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("InventoryHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "InventoryHud",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local panel, panelScale = UiKit.panel(screenGui, "InventoryPanel", PANEL_SIZE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.2))
	UiKit.text(panel, "Title", {
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -90, 0, 32),
		Font = FONTS.Display,
		TextSize = 28,
		Text = "🎒 Inventario",
	})
	UiKit.text(panel, "Subtitle", {
		Position = UDim2.fromOffset(22, 48),
		Size = UDim2.new(1, -240, 0, 20),
		Font = FONTS.Light,
		TextSize = 16,
		TextColor3 = THEME.Muted,
		Text = "Tus armas, huevos, pociones, títulos y amuletos",
	})
	local amuletsBtn = UiKit.button(panel, "AmuletsShortcut", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -64, 0, 14),
		Size = UDim2.fromOffset(154, 40),
		BackgroundColor3 = Color3.fromRGB(116, 76, 178),
		TextSize = 17,
		Text = "🧿 Amuletos [G]",
	})
	amuletsBtn.Activated:Connect(function()
		PanelManager.open("Amulets")
	end)
	local close = UiKit.button(panel, "Close", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = THEME.Inset,
		Text = "×",
	})

	-- Pestañas a la izquierda
	local sidebar = UiKit.create("Frame", {
		Name = "Tabs",
		Position = UDim2.fromOffset(16, TOP),
		Size = UDim2.new(0, SIDEBAR_WIDTH, 1, -TOP - 16),
		BackgroundTransparency = 1,
	}, panel)
	UiKit.create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, sidebar)
	local tabButtons = {}
	for order, tab in TABS do
		local button = UiKit.create("TextButton", {
			Name = tab.Id,
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, 74),
			BackgroundColor3 = THEME.Inset,
			LayoutOrder = order,
		}, sidebar)
		UiKit.corner(button, 12)
		local stroke = UiKit.stroke(button, INK, 3, 0)
		UiKit.shade(button, 0.8)
		UiKit.addStates(button)
		label(button, "Icon", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(36, 34),
			Font = FONTS.Display,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = tab.Icon,
		})
		label(button, "Label", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -8, 0, 26),
			Font = FONTS.Display,
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = tab.Label,
		}, 2.5)
		local dot = UiKit.create("Frame", {
			Name = "New",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -8, 0, 8),
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = Theme.Cartoon.Badge,
			Visible = false,
			ZIndex = 5,
		}, button)
		UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dot)
		UiKit.stroke(dot, INK, 2, 0)
		label(dot, "Mark", {
			Size = UDim2.fromScale(1, 1),
			Font = FONTS.Display,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "!",
			ZIndex = 6,
		})
		tabButtons[tab.Id] = { Button = button, Stroke = stroke, New = dot }
	end

	-- Contenido a la derecha
	local hint = label(panel, "Hint", {
		Position = UDim2.fromOffset(CONTENT_LEFT, TOP - 4),
		Size = UDim2.new(1, -CONTENT_LEFT - 16, 0, 26),
		Font = FONTS.Display,
		TextSize = 19,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, 2)
	local box = UiKit.create("Frame", {
		Name = "Box",
		Position = UDim2.fromOffset(CONTENT_LEFT, TOP + 28),
		Size = UDim2.new(1, -CONTENT_LEFT - 16, 1, -TOP - 28 - 16),
		BackgroundColor3 = THEME.Inset,
	}, panel)
	UiKit.corner(box, 14)
	UiKit.stroke(box, INK, 3, 0)
	local list = UiKit.create("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = THEME.Muted,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, box)
	UiKit.create("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
	}, list)
	local grid = UiKit.create("UIGridLayout", {
		CellSize = UDim2.fromOffset(CELL, CELL),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)
	local empty = label(box, "Empty", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -60, 0, 80),
		Font = FONTS.Display,
		TextSize = 20,
		TextWrapped = true,
		TextColor3 = THEME.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	})

	-- Presentación de la mascota al abrir un huevo (encima del panel)
	local reveal = UiKit.create("TextButton", {
		Name = "Reveal",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = THEME.Overlay,
		BackgroundTransparency = 0.35,
		Visible = false,
		ZIndex = 20,
	}, panel)
	UiKit.corner(reveal, Theme.Finish.PanelCorner)
	local card = UiKit.create("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 400),
		BackgroundColor3 = THEME.Panel,
		ZIndex = 21,
	}, reveal)
	UiKit.corner(card, 16)
	UiKit.stroke(card, INK, 3, 0)
	local glow = UiKit.create("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.fromOffset(240, 240),
		BackgroundColor3 = THEME.Gold,
		BackgroundTransparency = 0.75,
		ZIndex = 21,
	}, card)
	UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, glow)
	local viewport = UiKit.create("ViewportFrame", {
		Name = "Viewport",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.fromOffset(250, 230),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 200, 200),
		LightColor = Color3.new(1, 1, 1),
		ZIndex = 22,
	}, card)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local revealTitle = label(card, "Hatched", {
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 30),
		Font = FONTS.Display,
		TextSize = 26,
		TextColor3 = THEME.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "¡Ha nacido!",
		ZIndex = 23,
	}, 2.5)
	local revealName = label(card, "PetName", {
		Position = UDim2.fromOffset(10, 270),
		Size = UDim2.new(1, -20, 0, 32),
		Font = FONTS.Display,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 23,
	}, 2.5)
	local revealInfo = label(card, "Info", {
		Position = UDim2.fromOffset(10, 304),
		Size = UDim2.new(1, -20, 0, 40),
		Font = FONTS.Body,
		TextSize = 15,
		TextWrapped = true,
		TextColor3 = THEME.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 23,
	})
	local revealOk = UiKit.button(card, "Ok", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(170, 44),
		TextSize = 22,
		Text = "¡Genial!",
		ZIndex = 23,
	})

	-- Pociones activas (abajo a la izquierda)
	local boostsGui = UiKit.create("ScreenGui", {
		Name = "BoostsHud",
		ResetOnSpawn = false,
		DisplayOrder = 3,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local boostStack = UiKit.create("Frame", {
		Name = "Boosts",
		AnchorPoint = if touchOnly then Vector2.new(0.5, 0) else Vector2.new(0, 1),
		Position = if touchOnly then UDim2.new(0.5, 0, 0, 150) else UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(190, 200),
		BackgroundTransparency = 1,
	}, boostsGui)
	UiKit.create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = if touchOnly then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = if touchOnly then Enum.HorizontalAlignment.Center else Enum.HorizontalAlignment.Left,
	}, boostStack)
	local boostScale = UiKit.create("UIScale", {}, boostStack)
	local chips = {}
	for order, potionId in ItemLogic.boostOrder() do
		local def = ItemConfig.Potions[potionId]
		local chip = UiKit.create("Frame", {
			Name = potionId,
			Size = UDim2.fromOffset(186, 36),
			BackgroundColor3 = darker(def.Color, 0.75),
			LayoutOrder = order,
			Visible = false,
		}, boostStack)
		UiKit.corner(chip, 18)
		UiKit.stroke(chip, INK, 2.5, 0)
		UiKit.shade(chip, 0.8)
		label(chip, "Icon", {
			Position = UDim2.fromOffset(8, 4),
			Size = UDim2.fromOffset(28, 28),
			Font = FONTS.Display,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = def.Icon,
		})
		label(chip, "Name", {
			Position = UDim2.fromOffset(40, 0),
			Size = UDim2.new(1, -100, 1, 0),
			Font = FONTS.Display,
			TextSize = 17,
			Text = def.Short,
		}, 2)
		local timer = label(chip, "Time", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.new(0, 60, 1, 0),
			Font = FONTS.Display,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Right,
		}, 2)
		chips[potionId] = { Frame = chip, Time = timer }
	end

	screenGui.Parent = playerGui
	boostsGui.Parent = playerGui
	return {
		ScreenGui = screenGui,
		Panel = panel,
		PanelScale = panelScale,
		Close = close,
		Tabs = tabButtons,
		Hint = hint,
		List = list,
		Grid = grid,
		Empty = empty,
		Reveal = reveal,
		RevealCard = card,
		Glow = glow,
		Viewport = viewport,
		Camera = camera,
		RevealTitle = revealTitle,
		RevealName = revealName,
		RevealInfo = revealInfo,
		RevealOk = revealOk,
		BoostsGui = boostsGui,
		BoostScale = boostScale,
		Chips = chips,
	}
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.buildGui = buildGui
end

function Part.link(context: any)
	CELL = context.CELL
	CONTENT_LEFT = context.CONTENT_LEFT
	FONTS = context.FONTS
	INK = context.INK
	PANEL_SIZE = context.PANEL_SIZE
	SIDEBAR_WIDTH = context.SIDEBAR_WIDTH
	TABS = context.TABS
	THEME = context.THEME
	TOP = context.TOP
	player = context.player
end

return Part
