-- WeaponController · Helpers: constantes de diseño, lectura de atributos de armas y primitivas visuales (bordes, textos, degradados y botones).
-- Parte de WeaponController (ver WeaponController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)


local PANEL_NAME = "Armory"
-- Medidas del diseño (1280 × 720). Los contornos de Roblox (UIStroke) van por fuera del
-- marco, así que cada marco mide su borde menos que en el diseño.
local PANEL_SIZE = Vector2.new(1200, 676)
local WINDOW_SIZE = Vector2.new(1190, 666) -- + borde de 5
local HEADER_HEIGHT = 92 -- con su raya inferior de 5
local ROW_SIZE = Vector2.new(1158, 546) -- fila de tarjetas (márgenes de 16 y 14)
local CARD_SIZE = Vector2.new(271, 538) -- + borde de 4
local CARD_GAP = 22 -- 14 entre bordes
local CARD_STEP = CARD_SIZE.X + CARD_GAP
local CARDS_PER_PAGE = 4
local BUTTON_HEIGHT = 52 -- + borde de 3
local TOAST_SECONDS = 2.5
local PENDING_TIMEOUT = 2

local INK = Color3.fromRGB(43, 29, 63)
local WHITE = Color3.new(1, 1, 1)
local PANEL_BG = Color3.fromRGB(27, 42, 60)
local STRIPE_A = Color3.fromRGB(255, 174, 26)
local STRIPE_B = Color3.fromRGB(255, 200, 58)
local OK_COLOR = Color3.fromRGB(156, 236, 140)
local ERROR_COLOR = Color3.fromRGB(255, 136, 120)
-- Botones: color de arriba y de abajo del degradado
local GREEN = { Color3.fromRGB(180, 255, 74), Color3.fromRGB(70, 209, 30) }
local GRAY = { Color3.fromRGB(138, 148, 143), Color3.fromRGB(92, 102, 96) }
local DARK = { Color3.fromRGB(58, 70, 86), Color3.fromRGB(35, 44, 56) }
local PURPLE = { Color3.fromRGB(240, 138, 255), Color3.fromRGB(168, 48, 232) }
local RED = { Color3.fromRGB(255, 90, 78), Color3.fromRGB(216, 30, 30) }
local ORANGE = { Color3.fromRGB(255, 186, 92), Color3.fromRGB(232, 104, 32) }

local DISPLAY = Theme.Fonts.Display -- Fredoka One
local BOLD = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold)
local Codes = Constants.PurchaseCodes

local MESSAGES = {
	[Codes.InsufficientMoney] = "Te falta 💰 dinero: derrota enemigos",
	[Codes.AlreadyOwned] = "Ya lo tienes",
	[Codes.NotForSale] = "Eso lo suelta un jefe",
	[Codes.Locked] = "Primero desbloquea su zona",
	[Codes.NotOwned] = "Aún no lo tienes",
	[Codes.MaxLevel] = "Nivel máximo alcanzado",
	[Codes.TooFast] = "Demasiado rápido, espera un momento",
	[Codes.NotReady] = "Cargando datos, inténtalo de nuevo",
	[Codes.InvalidRequest] = "Solicitud no válida",
}


local player = Players.LocalPlayer

-- "Laser:3,PlasmaBlaster:0" -> { Laser = 3, PlasmaBlaster = 0 }
local function ownedWeapons(): { [string]: number }
	local owned = {}
	local text = player:GetAttribute(Constants.Attributes.Weapons)
	if typeof(text) == "string" then
		for weaponId, level in text:gmatch("([%w_]+):(%d+)") do
			owned[weaponId] = tonumber(level) or 0
		end
	end
	if next(owned) == nil then
		for _, starter in WeaponConfig.Starters or { Weapons = WeaponConfig.StarterWeapon } do
			owned[starter] = 0
		end
	end
	return owned
end

-- Mundo en el que está el jugador (el de su zona actual): la Armería del Mundo 2 solo enseña
-- lo del Mundo 2 (WeaponConfig.Weapons.*.World) y la del Mundo 1, lo suyo
local function currentWorld(): number
	local zoneId = player:GetAttribute(Constants.Attributes.CurrentZone)
	local zone = typeof(zoneId) == "string" and ZoneConfig.Zones[zoneId]
	return if zone and zone.World then zone.World else 1
end

-- Tienda que se ve: la del estilo de pelea (Armas, Puños o Magia)
local function currentCategory(): string
	local styleId = player:GetAttribute(Constants.Attributes.CombatStyle)
	return if typeof(styleId) == "string" and WeaponConfig.Categories[styleId] then styleId else "Weapons"
end

local function unlockedZones(): { string }
	local zones = {}
	local text = player:GetAttribute(Constants.Attributes.UnlockedZones)
	if typeof(text) == "string" then
		for zoneId in text:gmatch("[^,]+") do
			table.insert(zones, zoneId)
		end
	end
	return zones
end

local function numberAttribute(name: string): number
	local value = player:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

-- 5240 -> "5.2K", como en el diseño (un decimal hacia abajo; sin decimal desde 100)
local function short(n: number): string
	if n < 1000 then
		return tostring(math.round(n))
	end
	local units = { "K", "M", "B", "T", "Qa", "Qi" }
	local index, value = 0, n
	while value >= 1000 and index < #units do
		value /= 1000
		index += 1
	end
	local shown = if value >= 100 then math.floor(value) else math.floor(value * 10) / 10
	local text = if shown == math.floor(shown) then tostring(math.floor(shown)) else ("%.1f"):format(shown)
	return text .. units[index]
end

-- Contorno oscuro (el borde de 3 a 5 px del diseño)
local function border(guiObject: GuiObject, thickness: number, color: Color3?)
	UiKit.create("UIStroke", {
		Color = color or INK,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, guiObject)
end

-- Texto con contorno oscuro y, si se pide, sombra dura debajo (una copia oscura desplazada
-- `shadow` píxeles que sigue al texto).
local function outlinedText(parent: Instance, name: string, props: { [string]: any }, stroke: number, shadow: number?): TextLabel
	local label = UiKit.text(parent, name, props)
	if label.ZIndex < 3 then
		label.ZIndex = 3
	end
	UiKit.create("UIStroke", {
		Color = INK,
		Thickness = stroke,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, label)
	if shadow then
		local copy = label:Clone()
		copy.Name = name .. "Shadow"
		copy.TextColor3 = INK
		copy.Position = label.Position + UDim2.fromOffset(0, shadow)
		copy.ZIndex = label.ZIndex - 1
		copy.Parent = parent
		label:GetPropertyChangedSignal("Text"):Connect(function()
			copy.Text = label.Text
		end)
		label:GetPropertyChangedSignal("Visible"):Connect(function()
			copy.Visible = label.Visible
		end)
	end
	return label
end

-- Relleno de botón: degradado de arriba abajo con el brillo blanco de arriba (3 px) y la
-- sombra de abajo (5 px) del diseño, según el alto del botón.
local function fill(guiObject: GuiObject, colors: { Color3 }, height: number)
	local gradient = guiObject:FindFirstChild("Fill") :: UIGradient?
	if not gradient then
		gradient = UiKit.create("UIGradient", { Name = "Fill", Rotation = 90 }, guiObject)
	end
	local fillGradient = gradient :: UIGradient
	local top, bottom = colors[1], colors[2]
	local shine, shade = 3 / height, 1 - 5 / height
	local function at(t: number): Color3
		return top:Lerp(bottom, t)
	end
	guiObject.BackgroundColor3 = WHITE
	fillGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, at(0):Lerp(WHITE, 0.35)),
		ColorSequenceKeypoint.new(shine, at(shine):Lerp(WHITE, 0.35)),
		ColorSequenceKeypoint.new(shine + 0.001, at(shine)),
		ColorSequenceKeypoint.new(shade - 0.001, at(shade)),
		ColorSequenceKeypoint.new(shade, at(shade):Lerp(Color3.new(0, 0, 0), 0.2)),
		ColorSequenceKeypoint.new(1, bottom:Lerp(Color3.new(0, 0, 0), 0.2)),
	})
end

-- Botón grueso del diseño: marco con degradado, borde oscuro y esquinas de `radius`
local function chunkyButton(parent: Instance, name: string, props: { [string]: any }, radius: number, strokeWidth: number): TextButton
	local button = UiKit.create("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, nil)
	for key, value in props do
		(button :: any)[key] = value
	end
	UiKit.corner(button, radius)
	border(button, strokeWidth)
	UiKit.addStates(button)
	button.Parent = parent
	return button
end

local Part = { Api = {} }

function Part.install(context: any)
	-- (esta parte no usa el estado compartido)
	context.BOLD = BOLD
	context.BUTTON_HEIGHT = BUTTON_HEIGHT
	context.CARDS_PER_PAGE = CARDS_PER_PAGE
	context.CARD_GAP = CARD_GAP
	context.CARD_SIZE = CARD_SIZE
	context.CARD_STEP = CARD_STEP
	context.DARK = DARK
	context.DISPLAY = DISPLAY
	context.ERROR_COLOR = ERROR_COLOR
	context.GRAY = GRAY
	context.GREEN = GREEN
	context.HEADER_HEIGHT = HEADER_HEIGHT
	context.INK = INK
	context.MESSAGES = MESSAGES
	context.OK_COLOR = OK_COLOR
	context.ORANGE = ORANGE
	context.PANEL_BG = PANEL_BG
	context.PANEL_NAME = PANEL_NAME
	context.PANEL_SIZE = PANEL_SIZE
	context.PENDING_TIMEOUT = PENDING_TIMEOUT
	context.PURPLE = PURPLE
	context.RED = RED
	context.ROW_SIZE = ROW_SIZE
	context.STRIPE_A = STRIPE_A
	context.STRIPE_B = STRIPE_B
	context.TOAST_SECONDS = TOAST_SECONDS
	context.WHITE = WHITE
	context.WINDOW_SIZE = WINDOW_SIZE
	context.border = border
	context.chunkyButton = chunkyButton
	context.currentCategory = currentCategory
	context.currentWorld = currentWorld
	context.fill = fill
	context.numberAttribute = numberAttribute
	context.outlinedText = outlinedText
	context.ownedWeapons = ownedWeapons
	context.player = player
	context.short = short
	context.unlockedZones = unlockedZones
end

function Part.link(context: any)
	-- (nada que enlazar)
end

return Part
