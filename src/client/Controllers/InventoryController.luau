-- 🎒 Inventario (tecla I): lo que tiene el jugador, en cuatro pestañas (solo presentación;
-- todo lo decide el servidor: ItemService y WeaponService).
-- - ⚔️ Armas: las que tiene, con su nivel. Clic = equiparla (WeaponAction "Equip").
-- - 🥚 Huevos: los que soltaron los jefes. Clic = abrirlo aquí mismo (ItemAction "OpenEgg"),
--   con su presentación de la mascota.
-- - 🧪 Artículos: pociones. Clic = tomarla (ItemAction "UsePotion"); la activa muestra su tiempo.
-- - 🏅 Títulos: los conseguidos (clic = ponerlo encima de tu cabeza o quitarlo) y los que
--   faltan, con lo que piden y cuánto llevas.
-- Además: las pociones activas abajo a la izquierda con su cuenta atrás, el aviso del botín
-- de los jefes y de los títulos nuevos, y el número de cosas nuevas en el azulejo del menú.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ItemConfig = require(Shared.Config.ItemConfig)
local EggConfig = require(Shared.Config.EggConfig)
local PetConfig = require(Shared.Config.PetConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local ItemLogic = require(Shared.ItemLogic)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local MenuBar = require(script.Parent.Parent.UI.MenuBar)
local Toasts = require(script.Parent.Parent.UI.Toasts)
local Juice = require(script.Parent.Parent.UI.Juice)
local PetModelBuilder = require(script.Parent.Parent.Pets.PetModelBuilder)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local INK = Theme.Cartoon.Ink
local PANEL_NAME = "Inventory"
local PANEL_SIZE = Vector2.new(720, 480)
local SIDEBAR_WIDTH = 172
local CONTENT_LEFT = 16 + SIDEBAR_WIDTH + 14
local TOP = 86
local INVENTORY_COLOR = Color3.fromRGB(255, 176, 72)
local TAB_ON = Color3.fromRGB(64, 146, 204)
local CELL = 112

local TABS = {
	{ Id = "Weapons", Icon = "⚔️", Label = "Armas" },
	{ Id = "Eggs", Icon = "🥚", Label = "Huevos" },
	{ Id = "Potions", Icon = "🧪", Label = "Artículos" },
	{ Id = "Titles", Icon = "🏅", Label = "Títulos" },
}

local MESSAGES = {
	NotReady = "Tus datos aún se están cargando.",
	NotOwned = "Ya no lo tienes.",
	InventoryFull = "Tu inventario de mascotas está lleno.",
	Full = "Ya tienes el máximo de tiempo de esa poción (2 h).",
	TooFast = "Más despacio.",
}

local InventoryController = {}

local player = Players.LocalPlayer

type State = {
	Ready: boolean,
	Potions: { [string]: number },
	Eggs: { [string]: number },
	Boosts: { [string]: number },
	Titles: { [string]: boolean },
	Title: string,
	Progress: { [string]: { number } },
}

local state: State = { Ready = false, Potions = {}, Eggs = {}, Boosts = {}, Titles = {}, Title = "", Progress = {} }
-- Fin de cada poción activa en reloj local (os.clock), a partir de los segundos del servidor.
local boostEnds: { [string]: number } = {}

local function clockText(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	local secs = seconds % 60
	if hours > 0 then
		return ("%d:%02d:%02d"):format(hours, minutes, secs)
	end
	return ("%d:%02d"):format(minutes, secs)
end

-- "1 poción", "3 pociones"
local function amount(count: number, one: string, many: string): string
	return ("%d %s"):format(count, if count == 1 then one else many)
end

local function darker(color: Color3, factor: number): Color3
	return Color3.new(color.R * factor, color.G * factor, color.B * factor)
end

local function lighter(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

local function eggLook(eggId: string): (string, Color3)
	local look = ItemConfig.EggLooks[eggId]
	local egg = EggConfig.Eggs[eggId]
	local name = if look then look.Name elseif egg then egg.DisplayName else eggId
	local color = if look then look.Color elseif egg and egg.TitleColor then egg.TitleColor else Color3.fromRGB(230, 230, 230)
	return name, color
end

local function rarityOf(petId: string)
	local pet = PetConfig.Pets[petId]
	return (pet and PetConfig.Rarities[pet.Rarity]) or PetConfig.Rarities.Common
end

-- Piezas de dibujo -------------------------------------------------------------------------

local function label(parent: Instance, name: string, props: { [string]: any }, outline: number?): TextLabel
	local text = UiKit.text(parent, name, props)
	if outline then
		UiKit.outline(text, outline, INK)
	end
	return text
end

-- Azulejo cuadrado con contorno negro y degradado (botón).
local function tileButton(parent: Instance, name: string, color: Color3, order: number): TextButton
	local button = UiKit.create("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = color,
		LayoutOrder = order,
	}, parent)
	UiKit.corner(button, 12)
	UiKit.stroke(button, INK, 3, 0)
	UiKit.create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150)),
	}, button)
	UiKit.addStates(button)
	return button
end

-- Frasco de poción dibujado con marcos: cuerpo redondo del color de la poción, cuello,
-- corcho y el símbolo de lo que hace.
local function drawPotion(parent: Instance, def: any, size: number)
	local holder = UiKit.create("Frame", {
		Name = "Potion",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	}, parent)
	local body = UiKit.create("Frame", {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.78, 0.66),
		BackgroundColor3 = lighter(def.Color, 0.15),
	}, holder)
	UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, body)
	UiKit.stroke(body, INK, 2.5, 0)
	UiKit.create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(lighter(def.Color, 0.35), darker(def.Color, 0.8)),
	}, body)
	local shine = UiKit.create("Frame", {
		Name = "Shine",
		Position = UDim2.fromScale(0.18, 0.14),
		Size = UDim2.fromScale(0.22, 0.16),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.35,
		Rotation = -30,
	}, body)
	UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shine)
	local neck = UiKit.create("Frame", {
		Name = "Neck",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.36, 2),
		Size = UDim2.fromScale(0.3, 0.2),
		BackgroundColor3 = Color3.fromRGB(214, 236, 246),
		ZIndex = 0,
	}, holder)
	UiKit.corner(neck, 3)
	UiKit.stroke(neck, INK, 2, 0)
	local cork = UiKit.create("Frame", {
		Name = "Cork",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.2),
		Size = UDim2.fromScale(0.36, 0.14),
		BackgroundColor3 = Color3.fromRGB(176, 118, 64),
	}, holder)
	UiKit.corner(cork, 3)
	UiKit.stroke(cork, INK, 2, 0)
	label(body, "Symbol", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.62, 0.62),
		Font = FONTS.Display,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = def.Icon,
		ZIndex = 2,
	})
end

-- Huevo dibujado: óvalo del color del huevo con motas y brillo.
local function drawEgg(parent: Instance, color: Color3, width: number, height: number, center: UDim2?)
	local egg = UiKit.create("Frame", {
		Name = "Egg",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center or UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = color,
	}, parent)
	UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, egg)
	UiKit.stroke(egg, INK, 2.5, 0)
	UiKit.create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(lighter(color, 0.35), darker(color, 0.78)),
	}, egg)
	for index, spot in { { 0.62, 0.3, 0.2 }, { 0.3, 0.58, 0.16 }, { 0.66, 0.7, 0.13 } } do
		local dot = UiKit.create("Frame", {
			Name = "Spot" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spot[1], spot[2]),
			Size = UDim2.fromScale(spot[3], spot[3] * width / height),
			BackgroundColor3 = lighter(color, 0.55),
			BackgroundTransparency = 0.15,
		}, egg)
		UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dot)
	end
	local shine = UiKit.create("Frame", {
		Name = "Shine",
		Position = UDim2.fromScale(0.2, 0.14),
		Size = UDim2.fromScale(0.2, 0.18),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.3,
		Rotation = -25,
	}, egg)
	UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shine)
	return egg
end

local function countLabel(parent: Instance, count: number)
	label(parent, "Count", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 1, -4),
		Size = UDim2.fromOffset(60, 26),
		Font = FONTS.Display,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = THEME.BuyHighlight,
		Text = "x" .. formatNumber(count),
		ZIndex = 4,
	}, 2.5)
end

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
		Size = UDim2.new(1, -90, 0, 20),
		Font = FONTS.Light,
		TextSize = 16,
		TextColor3 = THEME.Muted,
		Text = "Tus armas, huevos, pociones y títulos",
	})
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
	for order, potionId in ItemLogic.potionOrder() do
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

function InventoryController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local actionRemote = remotes:WaitForChild(Constants.Remotes.ItemAction) :: RemoteEvent
	local resultRemote = remotes:WaitForChild(Constants.Remotes.ItemResult) :: RemoteEvent
	local stateRemote = remotes:WaitForChild(Constants.Remotes.ItemState) :: RemoteEvent
	local requestRemote = remotes:WaitForChild(Constants.Remotes.RequestItems) :: RemoteEvent
	local weaponRemote = remotes:WaitForChild(Constants.Remotes.WeaponAction) :: RemoteEvent
	local ui = buildGui()

	local currentTab = "Weapons"
	local unseen: { [string]: number } = {} -- cosas nuevas por pestaña (desde la última vez que se vio)
	local render: () -> ()

	local entry = MenuBar.add({
		Id = "Inventory",
		Order = 4,
		Icon = "🎒",
		Label = "Inventario",
		Key = "I",
		Color = INVENTORY_COLOR,
		Panels = { PANEL_NAME },
		OnActivate = function()
			PanelManager.toggle(PANEL_NAME)
		end,
	})

	local function refreshBadges()
		local total = 0
		for _, tab in TABS do
			local count = unseen[tab.Id] or 0
			ui.Tabs[tab.Id].New.Visible = count > 0
			total += count
		end
		entry.setBadge(if total > 0 then tostring(total) else nil)
	end

	local function markNew(tabId: string, count: number)
		if PanelManager.isOpen(PANEL_NAME) and currentTab == tabId then
			return
		end
		unseen[tabId] = (unseen[tabId] or 0) + count
		refreshBadges()
	end

	local function selectTab(tabId: string)
		currentTab = tabId
		unseen[tabId] = nil
		refreshBadges()
		for id, tab in ui.Tabs do
			local on = id == tabId
			tab.Button.BackgroundColor3 = if on then TAB_ON else THEME.Inset
			tab.Stroke.Color = if on then Color3.fromRGB(150, 220, 255) else INK
		end
		render()
	end

	local function clearList()
		for _, child in ui.List:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function showEmpty(text: string?)
		ui.Empty.Visible = text ~= nil
		ui.Empty.Text = text or ""
	end

	-- Armas: las que tiene ("Laser:3,PlasmaBlaster:0") en el orden de la Armería.
	local function ownedWeapons(): { { Id: string, Level: number } }
		local owned = {}
		local text = player:GetAttribute(Constants.Attributes.Weapons)
		if typeof(text) == "string" then
			for id, level in string.gmatch(text, "([%w_]+):(%d+)") do
				if WeaponConfig.Weapons[id] then
					table.insert(owned, { Id = id, Level = tonumber(level) or 0 })
				end
			end
		end
		table.sort(owned, function(a, b)
			return (WeaponConfig.Weapons[a.Id].Order or 0) < (WeaponConfig.Weapons[b.Id].Order or 0)
		end)
		return owned
	end

	local function renderWeapons()
		ui.Grid.CellSize = UDim2.fromOffset(CELL, CELL + 18)
		local owned = ownedWeapons()
		local equipped = player:GetAttribute(Constants.Attributes.EquippedWeapon)
		ui.Hint.Text = amount(#owned, "arma", "armas") .. " • Haz clic en un arma para equiparla"
		showEmpty(if #owned == 0 then "Aún no tienes armas." else nil)
		for order, weapon in owned do
			local def = WeaponConfig.Weapons[weapon.Id]
			local colors = def.CardColors or { THEME.Secondary, THEME.Secondary, THEME.Inset }
			local tile = tileButton(ui.List, weapon.Id, Color3.new(1, 1, 1), order)
			local gradient = tile:FindFirstChildOfClass("UIGradient")
			if gradient then
				gradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, colors[1]),
					ColorSequenceKeypoint.new(0.55, colors[2]),
					ColorSequenceKeypoint.new(1, colors[3]),
				})
			end
			if typeof(def.Art) == "string" and def.Art ~= "" then
				UiKit.create("ImageLabel", {
					Name = "Art",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.44),
					Size = UDim2.fromOffset(84, 84),
					BackgroundTransparency = 1,
					ScaleType = Enum.ScaleType.Fit,
					Image = def.Art,
					ZIndex = 2,
				}, tile)
			else
				label(tile, "Icon", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.42),
					Size = UDim2.fromOffset(58, 58),
					Font = FONTS.Display,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Center,
					Text = def.Icon or "⚔️",
					ZIndex = 2,
				})
			end
			label(tile, "Name", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -4),
				Size = UDim2.new(1, -10, 0, 20),
				Font = FONTS.Display,
				TextSize = 15,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = def.DisplayName,
				ZIndex = 3,
			}, 2)
			label(tile, "Level", {
				Position = UDim2.fromOffset(8, 5),
				Size = UDim2.fromOffset(60, 20),
				Font = FONTS.Display,
				TextSize = 16,
				Text = "Nv. " .. weapon.Level,
				ZIndex = 3,
			}, 2)
			if weapon.Id == equipped then
				local badge = UiKit.create("Frame", {
					Name = "Equipped",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 6, 0, -8),
					Size = UDim2.fromOffset(30, 30),
					BackgroundColor3 = THEME.Accent,
					ZIndex = 5,
				}, tile)
				UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, badge)
				UiKit.stroke(badge, INK, 2.5, 0)
				label(badge, "Check", {
					Size = UDim2.fromScale(1, 1),
					Font = FONTS.Display,
					TextSize = 20,
					TextXAlignment = Enum.TextXAlignment.Center,
					Text = "✓",
					ZIndex = 6,
				}, 2)
				local stroke = tile:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = THEME.Gold
				end
			end
			tile.Activated:Connect(function()
				if weapon.Id ~= player:GetAttribute(Constants.Attributes.EquippedWeapon) then
					weaponRemote:FireServer("Equip", weapon.Id)
					Juice.sound(Juice.Sounds.Upgrade)
				end
			end)
		end
	end

	local function renderEggs()
		ui.Grid.CellSize = UDim2.fromOffset(CELL, CELL + 18)
		local ids = {}
		local total = 0
		for eggId, count in state.Eggs do
			if EggConfig.Eggs[eggId] and count > 0 then
				table.insert(ids, eggId)
				total += count
			end
		end
		table.sort(ids, function(a, b)
			return (EggConfig.Eggs[a].Order or 0) < (EggConfig.Eggs[b].Order or 0)
		end)
		ui.Hint.Text = amount(total, "huevo", "huevos") .. " • Haz clic en un huevo para abrirlo"
		showEmpty(if #ids == 0 then "No tienes huevos guardados.\n¡Los jefes a veces sueltan uno!" else nil)
		for order, eggId in ids do
			local name, color = eggLook(eggId)
			local tile = tileButton(ui.List, eggId, darker(color, 0.55), order)
			drawEgg(tile, color, 54, 68, UDim2.fromScale(0.5, 0.42))
			label(tile, "Name", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -4),
				Size = UDim2.new(1, -10, 0, 20),
				Font = FONTS.Display,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = name,
				ZIndex = 3,
			}, 2)
			local count = UiKit.create("Frame", { Name = "CountHolder", Size = UDim2.new(1, 0, 1, -18), BackgroundTransparency = 1 }, tile)
			countLabel(count, state.Eggs[eggId])
			tile.Activated:Connect(function()
				actionRemote:FireServer("OpenEgg", eggId)
			end)
		end
	end

	local function renderPotions()
		ui.Grid.CellSize = UDim2.fromOffset(CELL, CELL)
		local ids = {}
		local total = 0
		for _, potionId in ItemLogic.potionOrder() do
			local count = state.Potions[potionId] or 0
			if count > 0 or boostEnds[potionId] then
				table.insert(ids, potionId)
				total += count
			end
		end
		ui.Hint.Text = amount(total, "poción", "pociones") .. " • Haz clic en una poción para usarla"
		showEmpty(if #ids == 0 then "No tienes pociones.\n¡Derrota jefes para conseguirlas!" else nil)
		for order, potionId in ids do
			local def = ItemConfig.Potions[potionId]
			local count = state.Potions[potionId] or 0
			local tile = tileButton(ui.List, potionId, darker(def.Color, 0.6), order)
			drawPotion(tile, def, 80)
			if count > 0 then
				countLabel(tile, count)
			else
				UiKit.setDisabled(tile, true)
				tile.BackgroundTransparency = 0.3
			end
			local timer = label(tile, "Active", {
				Position = UDim2.fromOffset(6, 4),
				Size = UDim2.new(1, -12, 0, 20),
				Font = FONTS.Display,
				TextSize = 16,
				TextColor3 = THEME.Gold,
				Visible = false,
				ZIndex = 4,
			}, 2)
			timer:SetAttribute("Potion", potionId)
			tile.Activated:Connect(function()
				if (state.Potions[potionId] or 0) > 0 then
					actionRemote:FireServer("UsePotion", potionId)
				end
			end)
			local tip = def.DisplayName .. ": " .. def.Description
			tile.MouseEnter:Connect(function()
				ui.Hint.Text = tip
			end)
			tile.MouseLeave:Connect(function()
				ui.Hint.Text = amount(total, "poción", "pociones") .. " • Haz clic en una poción para usarla"
			end)
		end
	end

	local function renderTitles()
		ui.Grid.CellSize = UDim2.new(1, 0, 0, 66)
		local ownedCount = 0
		for titleId in state.Titles do
			if ItemConfig.Titles[titleId] then
				ownedCount += 1
			end
		end
		ui.Hint.Text = amount(ownedCount, "título", "títulos") .. " • Haz clic en uno para llevarlo encima de tu cabeza"
		showEmpty(nil)
		for order, titleId in ItemLogic.titleOrder() do
			local def = ItemConfig.Titles[titleId]
			local owned = state.Titles[titleId] == true
			local equipped = state.Title == titleId
			local row = UiKit.create("TextButton", {
				Name = titleId,
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = if equipped then darker(def.Color, 0.45) else THEME.Panel,
				LayoutOrder = if owned then order else 100 + order,
			}, ui.List)
			UiKit.corner(row, 12)
			UiKit.stroke(row, if equipped then THEME.Gold else INK, if equipped then 3 else 2.5, 0)
			UiKit.addStates(row)
			UiKit.create("Frame", {
				Name = "Strip",
				Position = UDim2.fromOffset(8, 10),
				Size = UDim2.new(0, 8, 1, -20),
				BackgroundColor3 = if owned then def.Color else THEME.Disabled,
			}, row)
			label(row, "Name", {
				Position = UDim2.fromOffset(26, 8),
				Size = UDim2.new(1, -170, 0, 28),
				Font = FONTS.Display,
				TextSize = 22,
				TextColor3 = if owned then def.Color else THEME.Muted,
				Text = (if owned then "" else "🔒 ") .. def.DisplayName,
			}, 2)
			label(row, "Description", {
				Position = UDim2.fromOffset(26, 36),
				Size = UDim2.new(1, -170, 0, 20),
				Font = FONTS.Body,
				TextSize = 14,
				TextColor3 = THEME.Muted,
				Text = def.Description,
			})
			local status = label(row, "Status", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -14, 0.5, 0),
				Size = UDim2.fromOffset(140, 30),
				Font = FONTS.Display,
				TextSize = 18,
				TextXAlignment = Enum.TextXAlignment.Right,
			}, 2)
			if equipped then
				status.Text = "✓ PUESTO"
				status.TextColor3 = THEME.Gold
			elseif owned then
				status.Text = "Ponerlo"
				status.TextColor3 = THEME.BuyHighlight
			else
				local progress = state.Progress[titleId]
				local value, goal = if progress then progress[1] else 0, if progress then progress[2] else 1
				if goal > 1 then
					status.Text = formatNumber(math.min(value, goal)) .. " / " .. formatNumber(goal)
				else
					status.Text = "Pendiente"
				end
				status.TextColor3 = THEME.Muted
				UiKit.setDisabled(row, true)
				if goal > 1 then
					local bar = UiKit.create("Frame", {
						Name = "Bar",
						AnchorPoint = Vector2.new(1, 1),
						Position = UDim2.new(1, -14, 1, -8),
						Size = UDim2.fromOffset(130, 8),
						BackgroundColor3 = THEME.Inset,
					}, row)
					UiKit.corner(bar, 4)
					local fill = UiKit.create("Frame", {
						Name = "Fill",
						Size = UDim2.fromScale(math.clamp(value / goal, 0, 1), 1),
						BackgroundColor3 = def.Color,
					}, bar)
					UiKit.corner(fill, 4)
				end
			end
			row.Activated:Connect(function()
				if not owned then
					return
				end
				actionRemote:FireServer("EquipTitle", if equipped then "" else titleId)
			end)
		end
	end

	render = function()
		clearList()
		if not state.Ready and currentTab ~= "Weapons" then
			ui.Hint.Text = "Cargando…"
			showEmpty("Cargando tus datos…")
			return
		end
		if currentTab == "Weapons" then
			renderWeapons()
		elseif currentTab == "Eggs" then
			renderEggs()
		elseif currentTab == "Potions" then
			renderPotions()
		else
			renderTitles()
		end
	end

	for _, tab in TABS do
		ui.Tabs[tab.Id].Button.Activated:Connect(function()
			selectTab(tab.Id)
		end)
	end

	-- Presentación de la mascota ------------------------------------------------------------
	local spinConnection: RBXScriptConnection? = nil
	local function closeReveal()
		ui.Reveal.Visible = false
		if spinConnection then
			spinConnection:Disconnect()
			spinConnection = nil
		end
		for _, child in ui.Viewport:GetChildren() do
			if not child:IsA("Camera") then
				child:Destroy()
			end
		end
	end
	local function showReveal(detail: any)
		closeReveal()
		local petId = detail.PetId
		local pet = PetConfig.Pets[petId]
		local rarity = rarityOf(petId)
		ui.Glow.BackgroundColor3 = rarity.Color
		ui.RevealName.Text = if pet then pet.DisplayName else tostring(petId)
		ui.RevealName.TextColor3 = rarity.Color
		ui.RevealInfo.Text = rarity.DisplayName .. "  ·  " .. (if detail.AutoEquipped then "✓ Equipada automáticamente" else "Guardada en tus mascotas")
		local model = PetModelBuilder.build(petId)
		if model then
			model.Parent = ui.Viewport
			local size = model:GetExtentsSize()
			local distance = math.max(size.X, size.Y, size.Z) * 1.7 + 2.5
			local startedAt = os.clock()
			spinConnection = RunService.RenderStepped:Connect(function()
				local angle = (os.clock() - startedAt) * 0.9
				ui.Camera.CFrame = CFrame.lookAt(Vector3.new(math.sin(angle) * distance, size.Y * 0.25, -math.cos(angle) * distance), Vector3.new(0, size.Y * 0.1, 0))
			end)
		end
		ui.Reveal.Visible = true
		local scale = ui.RevealCard:FindFirstChildOfClass("UIScale") or UiKit.create("UIScale", {}, ui.RevealCard)
		scale.Scale = 0.6
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		local order = rarity.Order or 1
		Juice.burst(ui.Viewport, rarity.Color, 8 + order * 5, 130 + order * 20)
		Juice.sound(Juice.Sounds.Hatch)
		if order >= 4 then
			Juice.sound(Juice.Sounds.HatchEpic)
		elseif order >= 3 then
			Juice.sound(Juice.Sounds.HatchRare)
		end
	end
	ui.RevealOk.Activated:Connect(closeReveal)
	ui.Reveal.Activated:Connect(closeReveal)

	-- Estado del servidor --------------------------------------------------------------------
	stateRemote.OnClientEvent:Connect(function(newState: any)
		if typeof(newState) ~= "table" then
			return
		end
		state = {
			Ready = newState.Ready == true,
			Potions = if typeof(newState.Potions) == "table" then newState.Potions else {},
			Eggs = if typeof(newState.Eggs) == "table" then newState.Eggs else {},
			Boosts = if typeof(newState.Boosts) == "table" then newState.Boosts else {},
			Titles = if typeof(newState.Titles) == "table" then newState.Titles else {},
			Title = if typeof(newState.Title) == "string" then newState.Title else "",
			Progress = if typeof(newState.Progress) == "table" then newState.Progress else {},
		}
		boostEnds = {}
		local now = os.clock()
		for potionId, seconds in state.Boosts do
			if typeof(seconds) == "number" and seconds > 0 and ItemConfig.Potions[potionId] then
				boostEnds[potionId] = now + seconds
			end
		end
		if PanelManager.isOpen(PANEL_NAME) then
			render()
		end
	end)

	resultRemote.OnClientEvent:Connect(function(success: boolean, code: string, action: string, detail: any)
		if action == "Drop" and typeof(detail) == "table" then
			local names = {}
			local potionCount = 0
			for _, potionId in detail.Potions or {} do
				local def = ItemConfig.Potions[potionId]
				if def then
					table.insert(names, def.Icon .. " " .. def.DisplayName)
					potionCount += 1
				end
			end
			if detail.Egg then
				local name = eggLook(detail.Egg)
				table.insert(names, "🥚 " .. name)
				markNew("Eggs", 1)
			end
			if potionCount > 0 then
				markNew("Potions", potionCount)
			end
			Toasts.show(table.concat(names, "  ·  "), { Title = "🎁 ¡Botín de " .. tostring(detail.Boss) .. "!", Color = THEME.Gold, Duration = 6, OnClick = function()
				PanelManager.open(PANEL_NAME)
				selectTab(if detail.Egg then "Eggs" else "Potions")
			end })
			Juice.sound(Juice.Sounds.HatchRare)
			Juice.pop(entry.Tile)
		elseif action == "Title" and typeof(detail) == "string" then
			local def = ItemConfig.Titles[detail]
			if def then
				markNew("Titles", 1)
				Toasts.show(("«%s» · %s"):format(def.DisplayName, def.Description), { Title = "🏅 ¡Nuevo título!", Color = def.Color, Duration = 6, OnClick = function()
					PanelManager.open(PANEL_NAME)
					selectTab("Titles")
				end })
				Juice.sound(Juice.Sounds.HatchEpic)
			end
		elseif action == "BoostEnded" and typeof(detail) == "string" then
			local def = ItemConfig.Potions[detail]
			if def then
				Toasts.show(("Se acabó tu %s %s"):format(def.Icon, def.DisplayName), { Color = def.Color, Style = "Line" })
			end
		elseif action == "UsePotion" then
			if success and typeof(detail) == "table" then
				local def = ItemConfig.Potions[detail.PotionId]
				if def then
					Toasts.show(("%s %s activa: %s"):format(def.Icon, def.Short, clockText(detail.Seconds or 0)), { Color = def.Color })
					Juice.sound(Juice.Sounds.Upgrade, 1.2)
				end
			else
				Toasts.show(MESSAGES[code] or "No se pudo usar.", { Color = THEME.Error, Style = "Line" })
			end
		elseif action == "OpenEgg" then
			if success and typeof(detail) == "table" then
				showReveal(detail)
			else
				Toasts.show(MESSAGES[code] or "No se pudo abrir el huevo.", { Color = THEME.Error, Style = "Line" })
			end
		elseif action == "EquipTitle" then
			if success and typeof(detail) == "table" then
				local def = ItemConfig.Titles[detail.TitleId]
				Toasts.show(if def then ("Ahora llevas «%s»"):format(def.DisplayName) else "Título quitado", { Color = if def then def.Color else THEME.Muted, Style = "Line" })
			elseif not success then
				Toasts.show(MESSAGES[code] or "No se pudo cambiar el título.", { Color = THEME.Error, Style = "Line" })
			end
		end
	end)

	-- Armas: se repinta al cambiar las que tiene o la equipada.
	for _, attribute in { Constants.Attributes.Weapons, Constants.Attributes.EquippedWeapon } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if PanelManager.isOpen(PANEL_NAME) and currentTab == "Weapons" then
				render()
			end
		end)
	end

	-- Cuenta atrás de las pociones (HUD y panel), dos veces por segundo.
	task.spawn(function()
		while true do
			local now = os.clock()
			for potionId, chip in ui.Chips do
				local endsAt = boostEnds[potionId]
				local left = if endsAt then endsAt - now else 0
				chip.Frame.Visible = left > 0
				if left > 0 then
					chip.Time.Text = clockText(left)
				end
			end
			if PanelManager.isOpen(PANEL_NAME) and currentTab == "Potions" then
				for _, child in ui.List:GetChildren() do
					local timer = child:FindFirstChild("Active")
					if timer and timer:IsA("TextLabel") then
						local potionId = timer:GetAttribute("Potion")
						local endsAt = typeof(potionId) == "string" and boostEnds[potionId]
						local left = if endsAt then endsAt - now else 0
						timer.Visible = left > 0
						timer.Text = if left > 0 then "⏱ " .. clockText(left) else ""
					end
				end
			end
			task.wait(0.5)
		end
	end)

	PanelManager.register(PANEL_NAME, ui.Panel, {
		OnOpen = function()
			requestRemote:FireServer()
			selectTab(currentTab)
		end,
		OnClose = closeReveal,
	})
	UiKit.bindModalLayout(ui.ScreenGui, ui.PanelScale, PANEL_SIZE, function(position)
		PanelManager.setBasePosition(PANEL_NAME, position)
	end)
	UiKit.bindScale(ui.BoostsGui, { ui.BoostScale })
	ui.Close.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.I then
			PanelManager.toggle(PANEL_NAME)
		end
	end)

	requestRemote:FireServer()
end

return InventoryController
