-- WeaponController · CardGui: construcción de cada tarjeta de arma (buildCard) y botones de flecha del carrusel (arrowButton).
-- Parte de WeaponController (ver WeaponController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.Config.WeaponConfig)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)

local ctx: any -- tabla de estado compartida (la crea WeaponController/init.luau)
local BOLD: any
local BUTTON_HEIGHT: any
local CARD_SIZE: any
local DISPLAY: any
local WHITE: any

-- Funciones de las otras partes
local function border(...) return ctx.border(...) end
local function chunkyButton(...) return ctx.chunkyButton(...) end
local function fill(...) return ctx.fill(...) end
local function outlinedText(...) return ctx.outlinedText(...) end

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
		-- Sin imagen: el objeto de su categoría en grande (🗡️, 🥊, 🔱, 🏹) y su elemento de
		-- insignia en la esquina, para que se vea qué es (antes solo el elemento: 🔮 parecía
		-- un orbe aunque fuera una espada).
		local category = WeaponConfig.Categories[def.Category or "Weapons"]
		local itemIcon = (category and category.ItemIcon) or def.Icon
		UiKit.text(card, "ArtIcon", {
			Position = UDim2.fromOffset(12, 62),
			Size = UDim2.new(1, -24, 0, 172),
			TextSize = 110,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = itemIcon,
			ZIndex = 3,
		})
		if def.Icon and def.Icon ~= itemIcon then
			local badge = UiKit.create("Frame", {
				Name = "ElementBadge",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -18, 0, 70),
				Size = UDim2.fromOffset(52, 52),
				BackgroundColor3 = Color3.fromRGB(30, 20, 45),
				BackgroundTransparency = 0.15,
				ZIndex = 4,
			}, card)
			UiKit.corner(badge, 26)
			UiKit.stroke(badge, WeaponConfig.Rarities[def.Rarity] or WHITE, 2, 0)
			UiKit.text(badge, "Icon", {
				Size = UDim2.fromScale(1, 1),
				TextSize = 32,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = def.Icon,
				ZIndex = 5,
			})
		end
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

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.arrowButton = arrowButton
	context.buildCard = buildCard
end

function Part.link(context: any)
	BOLD = context.BOLD
	BUTTON_HEIGHT = context.BUTTON_HEIGHT
	CARD_SIZE = context.CARD_SIZE
	DISPLAY = context.DISPLAY
	WHITE = context.WHITE
end

return Part
