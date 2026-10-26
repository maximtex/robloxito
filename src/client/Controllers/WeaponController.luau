-- Armería (panel "Armory") con el diseño «Armería Roblox»: cabecera naranja a rayas con
-- ARMERÍA (o GUANTES / BASTONES: cada estilo de pelea tiene su tienda y solo se ve la de tu
-- estilo, WeaponConfig.Category), los botones ⚡ MEJORAS (habilidades del estilo,
-- SkillsController) y 🎭 CLASES (ClassesController), el dinero y la X roja; debajo, una tarjeta por arma (cuatro a la vista; las
-- flechas pasan al resto) con su arte, su rareza, sus números y sus botones: comprar con
-- dinero o con Robux, equipar y mejorar. Se abre en el puesto del pueblo, con la tecla L o
-- con el botón "Armas" del menú. Solo muestra y pide: el servidor valida y cobra
-- (WeaponService; las compras con Robux, ShopService).
-- Datos de los atributos del jugador: Weapons ("Laser:3,PlasmaBlaster:0"), EquippedWeapon,
-- Money, UnlockedZones, PetMultiplier y UpgradeLevel_LaserSpeed (cadencia).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local WeaponLogic = require(Shared.WeaponLogic)
local StyleLogic = require(Shared.StyleLogic)
local GunLogic = require(Shared.GunLogic)
local MagicLogic = require(Shared.MagicLogic)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local Icons = require(script.Parent.Parent.UI.Icons)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local MenuBar = require(script.Parent.Parent.UI.MenuBar)
local Toasts = require(script.Parent.Parent.UI.Toasts)
local Juice = require(script.Parent.Parent.UI.Juice)

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

local WeaponController = {}

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

local function buildCard(row: ScrollingFrame, weaponId: string, def, order: number)
	local light, base, dark = def.CardColors[1], def.CardColors[2], def.CardColors[3]
	local card = UiKit.create("Frame", {
		Name = "Card_" .. weaponId,
		Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, row)
	border(card, 4)
	UiKit.corner(card, 18)

	-- Fondo: degradado del color del arma (claro hacia el 38 % del alto, oscuro abajo) y
	-- rayos blancos desde ese punto, recortados a la tarjeta (CanvasGroup).
	local background = UiKit.create("CanvasGroup", {
		Name = "Background",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, card)
	UiKit.corner(background, 18)
	-- El degradado va en su propio marco: en el CanvasGroup teñiría también los rayos
	local tint = UiKit.create("Frame", {
		Name = "Tint",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, background)
	UiKit.create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, base:Lerp(dark, 0.2)),
			ColorSequenceKeypoint.new(0.08, base),
			ColorSequenceKeypoint.new(0.38, light),
			ColorSequenceKeypoint.new(0.68, base),
			ColorSequenceKeypoint.new(1, base:Lerp(dark, 0.87)),
		}),
	}, tint)
	for index = 0, 11 do
		local ray = UiKit.create("Frame", {
			Name = "Ray",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.38),
			Size = UDim2.fromOffset(26, 1300),
			Rotation = index * 15 + 3.5,
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
		}, background)
		UiKit.create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.86),
				NumberSequenceKeypoint.new(0.42, 0.9),
				NumberSequenceKeypoint.new(0.5, 1),
				NumberSequenceKeypoint.new(0.58, 0.9),
				NumberSequenceKeypoint.new(1, 0.86),
			}),
		}, ray)
	end
	-- Anillo interior: blanco si está equipada, blanco suave si no
	local ring = UiKit.create("Frame", {
		Name = "Ring",
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(1, -6, 1, -6),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, card)
	UiKit.corner(ring, 15)
	local ringStroke = UiKit.create("UIStroke", { Color = WHITE, Thickness = 3, Transparency = 0.7 }, ring)

	outlinedText(card, "Name", {
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 30),
		Font = DISPLAY,
		TextSize = 25,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = def.DisplayName,
	}, 3, 3)
	outlinedText(card, "Rarity", {
		Position = UDim2.fromOffset(0, 35),
		Size = UDim2.new(1, 0, 0, 24),
		Font = DISPLAY,
		TextSize = 21,
		TextColor3 = WeaponConfig.Rarities[def.Rarity] or WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = def.Rarity or "",
	}, 3, 2)

	-- Arte del arma con su sombra; sin imagen, su icono en grande
	if def.Art then
		local art = UiKit.create("ImageLabel", {
			Name = "Art",
			Position = UDim2.fromOffset(12, 62),
			Size = UDim2.new(1, -24, 0, 172),
			BackgroundTransparency = 1,
			Image = def.Art,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 3,
		}, card)
		local shadow = art:Clone()
		shadow.Name = "ArtShadow"
		shadow.Position = art.Position + UDim2.fromOffset(0, 6)
		shadow.ImageColor3 = Color3.new(0, 0, 0)
		shadow.ImageTransparency = 0.75
		shadow.ZIndex = 2
		shadow.Parent = card
	else
		UiKit.text(card, "ArtIcon", {
			Position = UDim2.fromOffset(12, 62),
			Size = UDim2.new(1, -24, 0, 172),
			TextSize = 110,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = def.Icon,
			ZIndex = 3,
		})
	end

	-- Píldora: nivel si la tiene, su efecto si no
	local tag = UiKit.create("Frame", {
		Name = "Tag",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 237),
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.fromRGB(20, 24, 44),
		BackgroundTransparency = 0.45,
		ZIndex = 3,
	}, card)
	UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, tag)
	border(tag, 3)
	UiKit.create("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, tag)
	local tagText = outlinedText(tag, "Text", {
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = DISPLAY,
		TextSize = 18,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	}, 2)

	-- Números: daño por disparo, velocidad de ataque y alcance
	local stats = UiKit.create("Frame", {
		Name = "Stats",
		Position = UDim2.fromOffset(15, 278),
		Size = UDim2.new(1, -30, 0, 90),
		BackgroundColor3 = Color3.fromRGB(14, 22, 44),
		BackgroundTransparency = 0.38,
		ZIndex = 3,
	}, card)
	UiKit.corner(stats, 10)
	border(stats, 3)
	local statLabels = {}
	for index, spec in { { "💥", 16 }, { "⏱", 15 }, { "🎯", 16 } } do
		local y = 6 + (index - 1) * 27
		UiKit.text(stats, "Icon" .. index, {
			Position = UDim2.fromOffset(8, y),
			Size = UDim2.fromOffset(24, 24),
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = spec[1],
			ZIndex = 4,
		})
		statLabels[index] = UiKit.text(stats, "Stat" .. index, {
			Position = UDim2.fromOffset(42, y),
			Size = UDim2.new(1, -48, 0, 24),
			FontFace = BOLD,
			TextSize = spec[2],
			TextColor3 = WHITE,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 4,
		})
	end

	-- Botones: el principal (comprar, equipar o por qué no se puede) y, al lado, mejorar o
	-- comprar con Robux
	local buttonsY = CARD_SIZE.Y - 10 - BUTTON_HEIGHT - 3
	local primary = chunkyButton(card, "Primary", {
		Position = UDim2.fromOffset(15, buttonsY),
		Size = UDim2.new(1, -30, 0, BUTTON_HEIGHT),
	}, 6, 3)
	local primaryLabel = outlinedText(primary, "Label", {
		Size = UDim2.fromScale(1, 1),
		Font = DISPLAY,
		TextSize = 28,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	}, 3)
	local primarySub = outlinedText(primary, "Sub", {
		Position = UDim2.new(0, 0, 1, -21),
		Size = UDim2.new(1, 0, 0, 16),
		Font = DISPLAY,
		TextSize = 15,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	}, 2)
	local secondary = chunkyButton(card, "Secondary", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -15, 0, buttonsY),
		Size = UDim2.fromOffset(90, BUTTON_HEIGHT),
	}, 6, 3)
	local secondaryContent = UiKit.create("Frame", {
		Name = "Content",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, secondary)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, secondaryContent)
	local robuxIcon = UiKit.create("ImageLabel", {
		Name = "Robux",
		Size = UDim2.fromOffset(28, 28),
		BackgroundTransparency = 1,
		Image = WeaponConfig.ArmoryArt.Robux or "",
		ImageColor3 = WHITE,
		ScaleType = Enum.ScaleType.Fit,
		LayoutOrder = 1,
		ZIndex = 5,
	}, secondaryContent)
	local secondaryLabel = outlinedText(secondaryContent, "Label", {
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = DISPLAY,
		TextSize = 24,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		ZIndex = 5,
	}, 3)

	return {
		Frame = card,
		Def = def,
		RingStroke = ringStroke,
		TagText = tagText,
		Stats = statLabels,
		Primary = primary,
		PrimaryLabel = primaryLabel,
		PrimarySub = primarySub,
		Secondary = secondary,
		SecondaryLabel = secondaryLabel,
		RobuxIcon = robuxIcon,
	}
end

local function arrowButton(parent: Instance, name: string, text: string, side: number): TextButton
	local button = chunkyButton(parent, name, {
		AnchorPoint = Vector2.new(if side < 0 then 0 else 1, 0.5),
		Position = UDim2.new(if side < 0 then 0 else 1, -side * 6, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		ZIndex = 6,
	}, 20, 4)
	fill(button, { Color3.fromRGB(255, 200, 58), Color3.fromRGB(240, 170, 30) }, 40)
	outlinedText(button, "Label", {
		Size = UDim2.new(1, 0, 1, -4),
		Font = DISPLAY,
		TextSize = 30,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = text,
		ZIndex = 7,
	}, 2.5)
	return button
end

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

function WeaponController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local actionRemote = remotes:WaitForChild(Constants.Remotes.WeaponAction) :: RemoteEvent
	local weaponResult = remotes:WaitForChild(Constants.Remotes.WeaponResult) :: RemoteEvent

	local ui = buildGui()
	local pending = false
	local pendingToken = 0
	local toastToken = 0
	local actions: { [string]: { Primary: () -> (), Secondary: () -> () } } = {}

	local function say(text: string, ok: boolean)
		toastToken += 1
		local token = toastToken
		ui.Toast.Text = text
		ui.Toast.TextColor3 = if ok then OK_COLOR else ERROR_COLOR
		ui.Toast.Visible = true
		task.delay(TOAST_SECONDS, function()
			if toastToken == token then
				ui.Toast.Visible = false
			end
		end)
	end

	-- Una petición a la vez (se libera con la respuesta o a los PENDING_TIMEOUT segundos)
	local function request(action: string, weaponId: string)
		if pending then
			return
		end
		pending = true
		pendingToken += 1
		local token = pendingToken
		actionRemote:FireServer(action, weaponId)
		task.delay(PENDING_TIMEOUT, function()
			if pendingToken == token then
				pending = false
			end
		end)
	end

	local function buyWithRobux(weaponId: string)
		local product = MonetizationConfig.WeaponProducts[weaponId]
		if product and product.Id > 0 then
			MarketplaceService:PromptProductPurchase(player, product.Id)
		else
			say("Próximamente con Robux", false)
		end
	end

	local shownCategory = ""
	local function refresh()
		local money = numberAttribute(Constants.Attributes.Money)
		ui.Money.Text = "$" .. short(money)
		local owned = ownedWeapons()
		local equipped = player:GetAttribute(Constants.Attributes.EquippedWeapon)
		local zones = unlockedZones()
		local pets = numberAttribute(Constants.Attributes.PetMultiplier)
		local cadence = numberAttribute(Constants.Attributes.UpgradeLevelPrefix .. WeaponConfig.CadenceUpgradeId)
		local category = currentCategory()
		local info = WeaponConfig.Categories[category]
		local world = currentWorld()
		ui.Title.Text = if world == 2 then info.Title .. " 2" else info.Title
		ui.Title.TextSize = if world == 2 then 52 else 60
		local useImage = ui.HeaderImage ~= nil and category == "Weapons"
		if ui.HeaderImage then
			ui.HeaderImage.Visible = useImage
		end
		ui.HeaderEmoji.Visible = not useImage
		ui.HeaderEmoji.Text = info.Icon
		if category .. world ~= shownCategory then
			shownCategory = category .. world
			ui.Row.CanvasPosition = Vector2.zero -- otra tienda: a la primera página
		end

		for weaponId, card in ui.Cards do
			local def = card.Def
			card.Frame.Visible = WeaponLogic.category(weaponId) == category and WeaponLogic.world(weaponId) == world
			local level = owned[weaponId]
			local has = level ~= nil
			local isEquipped = equipped == weaponId
			card.RingStroke.Transparency = if isEquipped then 0 else 0.7
			card.TagText.Text = if has then ("Nv. %d/%d"):format(level, WeaponConfig.MaxLevel) else def.Tagline or ""
			-- Números con el ritmo y el alcance de su estilo (y de su tipo de arma); la tercera
			-- línea: el tipo y el cargador (armas), el elemento (bastones) o cuerpo a cuerpo
			local styled = StyleLogic.applyStats({
				Shot = WeaponLogic.shotDamage(weaponId, level or 0, pets),
				Cooldown = WeaponLogic.cooldown(weaponId, cadence),
				Range = def.Range,
			}, category, def.Cooldown)
			if category == "Weapons" then
				styled = GunLogic.applyStats(styled, weaponId)
			end
			card.Stats[1].Text = short(styled.Shot) .. " " .. info.Hit
			card.Stats[2].Text = ("Velocidad de ataque: %.2f s"):format(styled.Cooldown)
			if category == "Weapons" then
				local gun = GunLogic.spec(weaponId)
				card.Stats[3].Text = ("%s · %d balas · %d"):format(gun.Name or styled.Gun, styled.Magazine, styled.Range)
			elseif category == "Magic" then
				local element = MagicLogic.elementDef(MagicLogic.element(weaponId))
				card.Stats[3].Text = ("%s %s · %d de alcance"):format(element.Icon or "", element.Name or "", styled.Range)
			elseif category == "Warrior" then
				card.Stats[3].Text = "Espada · cuerpo a cuerpo"
			else
				card.Stats[3].Text = "Cuerpo a cuerpo"
			end

			-- Principal: texto grande, texto pequeño debajo, color y qué hace
			local label, sub, size, colors, onPrimary = "", "", 28, GREEN, function() end
			-- Al lado: mejorar (si la tiene) o comprar con Robux (si se vende así)
			local side: { Label: string, Colors: { Color3 }, Robux: boolean, Action: () -> () }? = nil
			local product = MonetizationConfig.WeaponProducts[weaponId]
			local robuxSide = if product
				then { Label = tostring(product.Robux), Colors = PURPLE, Robux = true, Action = function()
					buyWithRobux(weaponId)
				end }
				else nil
			if has then
				local cost = WeaponLogic.upgradeCost(weaponId, level)
				side = {
					Label = if cost then "$" .. short(cost) else "MÁX",
					Colors = if cost and money >= cost then GREEN else GRAY,
					Robux = false,
					Action = function()
						if cost then
							request("Upgrade", weaponId)
						else
							say("Nivel máximo alcanzado", false)
						end
					end,
				}
				if isEquipped then
					label, onPrimary = "Equipado", function()
						say("Ya la tienes equipada", true)
					end
				else
					label, onPrimary = "Equipar", function()
						request("Equip", weaponId)
					end
				end
			elseif def.BossDrop then
				local boss = EnemyConfig.Types[def.BossDrop]
				label, sub, size, colors = "💀 DERROTA AL JEFE", if boss then boss.DisplayName else "", 20, DARK
				onPrimary = function()
					say("Lo suelta ese jefe si lo derrotas con este estilo", false)
				end
			elseif not WeaponLogic.meetsRequirement(weaponId, zones) then
				local zone = ZoneConfig.Zones[def.Requires.Zone]
				label, sub, size, colors = "🔒 $" .. short(def.Price), if zone then zone.DisplayName else "", 24, GRAY
				onPrimary = function()
					say("Primero desbloquea su zona", false)
				end
				side = robuxSide
			else
				label, colors = "$" .. short(def.Price), if money >= def.Price then GREEN else GRAY
				onPrimary = function()
					request("Buy", weaponId)
				end
				side = robuxSide
			end

			fill(card.Primary, colors, BUTTON_HEIGHT)
			card.PrimaryLabel.Text = label
			card.PrimaryLabel.TextSize = size
			card.PrimaryLabel.Size = if sub ~= "" then UDim2.new(1, 0, 1, -18) else UDim2.fromScale(1, 1)
			card.PrimarySub.Text = sub
			card.PrimarySub.Visible = sub ~= ""
			card.Secondary.Visible = side ~= nil
			card.Primary.Size = if side then UDim2.new(1, -30 - 90 - 8, 0, BUTTON_HEIGHT) else UDim2.new(1, -30, 0, BUTTON_HEIGHT)
			if side then
				fill(card.Secondary, side.Colors, BUTTON_HEIGHT)
				card.SecondaryLabel.Text = side.Label
				card.RobuxIcon.Visible = side.Robux
			end
			actions[weaponId] = { Primary = onPrimary, Secondary = if side then side.Action else function() end }
		end
	end

	-- Al soltar después de arrastrar las tarjetas, el botón de debajo no se pulsa
	local suppressClickUntil = 0
	for weaponId, card in ui.Cards do
		card.Primary.Activated:Connect(function()
			local action = actions[weaponId]
			if action and os.clock() >= suppressClickUntil then
				action.Primary()
			end
		end)
		card.Secondary.Activated:Connect(function()
			local action = actions[weaponId]
			if action and os.clock() >= suppressClickUntil then
				action.Secondary()
			end
		end)
	end

	-- Flechas: pasan de página (cuatro tarjetas), siempre alineadas a una tarjeta.
	-- CanvasPosition va en píxeles de pantalla (ya escalados por el UIScale del panel).
	local function maxScroll(): number
		return math.max(0, ui.Row.AbsoluteCanvasSize.X - ui.Row.AbsoluteWindowSize.X)
	end
	local function step(): number
		return CARD_STEP * ui.Row.AbsoluteWindowSize.X / ROW_SIZE.X
	end
	local function refreshArrows()
		local x = ui.Row.CanvasPosition.X
		ui.Left.Visible = x > 2
		ui.Right.Visible = x < maxScroll() - 2
	end
	local function page(direction: number)
		local current = math.round(ui.Row.CanvasPosition.X / step())
		local target = math.clamp((current + direction * CARDS_PER_PAGE) * step(), 0, maxScroll())
		TweenService:Create(ui.Row, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CanvasPosition = Vector2.new(target, 0) }):Play()
	end
	ui.Left.Activated:Connect(function()
		page(-1)
	end)
	ui.Right.Activated:Connect(function()
		page(1)
	end)
	for _, property in { "CanvasPosition", "AbsoluteCanvasSize", "AbsoluteWindowSize" } do
		ui.Row:GetPropertyChangedSignal(property):Connect(refreshArrows)
	end
	refreshArrows()

	-- Centrado en la pantalla, sin pisar la columna de la izquierda, y lo más grande que quepa
	-- (hasta la escala del HUD). Se vuelve a centrar al abrir y al cambiar el tamaño de pantalla.
	local function layoutPanel()
		local size = ui.ScreenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local hudScale = UiKit.computeScale(size)
		local sideReserve = 16 + Theme.Layout.SideButtonWidth * hudScale + Theme.Layout.Gap
		local fit = math.min(hudScale, (size.Y - 2 * Theme.Layout.Margin) / PANEL_SIZE.Y, (size.X - 2 * sideReserve) / PANEL_SIZE.X)
		ui.FitScale.Scale = fit
		PanelManager.setBasePosition(PANEL_NAME, UDim2.new(0.5, 0, 0, (size.Y - PANEL_SIZE.Y * fit) / 2))
	end

	-- Arrastrar con el ratón (o el dedo): la cabecera mueve la ventana; las tarjetas pasan de
	-- arma en arma (con el dedo ya lo hace el ScrollingFrame) y, al soltar, quedan alineadas.
	local function inside(gui: GuiObject, position: Vector2): boolean
		local corner, extent = gui.AbsolutePosition, gui.AbsoluteSize
		return position.X >= corner.X and position.X <= corner.X + extent.X and position.Y >= corner.Y and position.Y <= corner.Y + extent.Y
	end
	local windowDrag: { Input: InputObject, Start: Vector2, From: UDim2 }? = nil
	local rowDrag: { Start: number, From: number, Moved: boolean }? = nil
	UserInputService.InputBegan:Connect(function(input)
		local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
		if not (isMouse or input.UserInputType == Enum.UserInputType.Touch) or not PanelManager.isOpen(PANEL_NAME) then
			return
		end
		local position = Vector2.new(input.Position.X, input.Position.Y)
		if inside(ui.Header, position) and not inside(ui.Close, position) and not inside(ui.Skills, position) then
			windowDrag = { Input = input, Start = position, From = ui.Panel.Position }
		elseif isMouse and inside(ui.Row, position) then
			rowDrag = { Start = position.X, From = ui.Row.CanvasPosition.X, Moved = false }
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local isMouse = input.UserInputType == Enum.UserInputType.MouseMovement
		if windowDrag and (isMouse or input == windowDrag.Input) then
			local size = ui.ScreenGui.AbsoluteSize
			local delta = Vector2.new(input.Position.X, input.Position.Y) - windowDrag.Start
			local from = windowDrag.From
			-- Que el centro de la ventana y su cabecera no salgan de la pantalla
			local x = math.clamp(from.X.Offset + delta.X, -size.X / 2, size.X / 2)
			local y = math.clamp(from.Y.Offset + delta.Y, 0, size.Y - HEADER_HEIGHT * ui.FitScale.Scale)
			ui.Panel.Position = UDim2.new(0.5, x, 0, y)
		elseif rowDrag and isMouse then
			local delta = input.Position.X - rowDrag.Start
			if math.abs(delta) > 6 then
				rowDrag.Moved = true
			end
			if rowDrag.Moved then
				ui.Row.CanvasPosition = Vector2.new(math.clamp(rowDrag.From - delta, 0, maxScroll()), 0)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if windowDrag and (input == windowDrag.Input or input.UserInputType == Enum.UserInputType.MouseButton1) then
			windowDrag = nil
			if PanelManager.isOpen(PANEL_NAME) then
				PanelManager.setBasePosition(PANEL_NAME, ui.Panel.Position) -- para que cierre desde ahí
			end
		elseif rowDrag and input.UserInputType == Enum.UserInputType.MouseButton1 then
			if rowDrag.Moved then
				suppressClickUntil = os.clock() + 0.2
				local target = math.clamp(math.round(ui.Row.CanvasPosition.X / step()) * step(), 0, maxScroll())
				TweenService:Create(ui.Row, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CanvasPosition = Vector2.new(target, 0) }):Play()
			end
			rowDrag = nil
		end
	end)

	weaponResult.OnClientEvent:Connect(function(success: boolean, code: string, action: string, weaponId: string)
		pending = false
		local def = WeaponConfig.Weapons[weaponId]
		if code == "BossDrop" and def then
			local info = WeaponConfig.Categories[WeaponLogic.category(weaponId)] or WeaponConfig.Categories.Weapons
			Toasts.show(("%s %s ya es tuyo. Equípalo en la tienda de tu estilo (L)."):format(def.Icon, def.DisplayName), { Title = ("🏆 ¡Nuevo: %s!"):format(info.Item), Color = Theme.Colors.Gold })
			Juice.sound(Juice.Sounds.Upgrade, 1.1)
		elseif code == "Robux" and def then
			say("¡Comprada con Robux y equipada!", true)
			if not PanelManager.isOpen(PANEL_NAME) then
				Toasts.show(("%s %s ya es tuya y está equipada."):format(def.Icon, def.DisplayName), { Title = "¡Arma comprada!", Color = Theme.Colors.Gold })
			end
			Juice.sound(Juice.Sounds.Upgrade, 1.1)
		elseif success then
			say(if action == "Buy" then "¡Comprado y equipado!" elseif action == "Upgrade" then "¡Mejorado!" else "Equipado", true)
			Juice.sound(Juice.Sounds.Upgrade, if action == "Upgrade" then 1.05 else 1)
		else
			say(MESSAGES[code] or tostring(code), false)
		end
		refresh()
	end)

	PanelManager.register(PANEL_NAME, ui.Panel, {
		OnOpen = function()
			refresh()
			layoutPanel()
			-- Aparece creciendo desde el centro con un pequeño rebote, como en el diseño, y
			-- siempre en la primera página
			ui.Row.CanvasPosition = Vector2.zero
			ui.PopScale.Scale = 0.05
			local pop = TweenService:Create(ui.PopScale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			pop.Completed:Once(function()
				ui.Row.CanvasPosition = Vector2.zero
			end)
			pop:Play()
		end,
	})
	ui.ScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutPanel)
	layoutPanel()
	ui.Close.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
	end)
	ui.Skills.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
		PanelManager.open("Skills")
	end)
	ui.Classes.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
		PanelManager.open("Classes")
	end)
	local menuEntry = MenuBar.add({
		Id = "Armory",
		Order = 0,
		Icon = "⚔️",
		Label = "Armas",
		Key = "L",
		Panels = { PANEL_NAME },
		OnActivate = function()
			PanelManager.toggle(PANEL_NAME)
		end,
	})
	-- El azulejo dice qué tienda abre (Armas, Espadas, Guantes o Bastones)
	local MENU_WORDS = { Weapons = "Armas", Warrior = "Espadas", Fists = "Guantes", Magic = "Bastones" }
	local function refreshMenuLabel()
		menuEntry.setLabel(MENU_WORDS[currentCategory()] or "Armas")
	end
	player:GetAttributeChangedSignal(Constants.Attributes.CombatStyle):Connect(refreshMenuLabel)
	refreshMenuLabel()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.L then
			PanelManager.toggle(PANEL_NAME)
		end
	end)

	for _, attribute in {
		Constants.Attributes.Money,
		Constants.Attributes.Weapons,
		Constants.Attributes.EquippedWeapon,
		Constants.Attributes.UnlockedZones,
		Constants.Attributes.PetMultiplier,
		Constants.Attributes.UpgradeLevelPrefix .. WeaponConfig.CadenceUpgradeId,
		Constants.Attributes.CombatStyle,
		Constants.Attributes.CurrentZone,
	} do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	refresh()
end

return WeaponController
