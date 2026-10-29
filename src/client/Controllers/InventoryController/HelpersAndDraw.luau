-- InventoryController · HelpersAndDraw: constantes, utilidades de formato/color y dibujo de azulejos, frascos de poción y huevos.
-- Parte de InventoryController (ver InventoryController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared.Config.ItemConfig)
local EggConfig = require(Shared.Config.EggConfig)
local PetConfig = require(Shared.Config.PetConfig)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)


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
	FullHealth = "Tienes la vida llena.",
	Cooldown = "Espera un momento para tomar otra.",
	TooFast = "Más despacio.",
}


local player = Players.LocalPlayer


-- Fin de cada poción activa en reloj local (os.clock), a partir de los segundos del servidor.

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

local Part = { Api = {} }

function Part.install(context: any)
	-- (esta parte no usa el estado compartido)
	context.CELL = CELL
	context.CONTENT_LEFT = CONTENT_LEFT
	context.FONTS = FONTS
	context.INK = INK
	context.INVENTORY_COLOR = INVENTORY_COLOR
	context.MESSAGES = MESSAGES
	context.PANEL_NAME = PANEL_NAME
	context.PANEL_SIZE = PANEL_SIZE
	context.SIDEBAR_WIDTH = SIDEBAR_WIDTH
	context.TABS = TABS
	context.TAB_ON = TAB_ON
	context.THEME = THEME
	context.TOP = TOP
	context.amount = amount
	context.clockText = clockText
	context.countLabel = countLabel
	context.darker = darker
	context.drawEgg = drawEgg
	context.drawPotion = drawPotion
	context.eggLook = eggLook
	context.label = label
	context.player = player
	context.rarityOf = rarityOf
	context.tileButton = tileButton
end

function Part.link(context: any)
	-- (nada que enlazar)
end

return Part
