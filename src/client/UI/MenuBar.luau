-- Barra del menú (diseño "HUD Botones" de Santiago) + tarjeta de la misión diaria:
-- - Abajo en el centro: Armas, Amuletos y Mascotas, y Renacer destacado (mismo tamaño, con
--   anillo dorado y el porcentaje para renacer encima).
-- - A la derecha, en columna: Misiones, Premios y Tienda (posición en HudLayout.SideMenu,
--   para no pisar el cartel de la zona ni los botones de combate).
-- - En pantallas solo táctiles los siete van en la fila de abajo: a la derecha están las
--   habilidades.
-- Azulejos gris oscuro con contorno negro, icono grande, nombre con borde negro que asoma
-- por debajo, tecla arriba a la izquierda y aviso rojo inclinado arriba a la derecha. Al
-- pasar el ratón el azulejo sube; con su panel abierto lleva borde amarillo.
-- - A la izquierda (bajo las monedas): tarjeta estilo pergamino de la misión diaria, con
--   icono, título, contador verde (ej. 2/15) y barra de progreso.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local Icons = require(script.Parent.Icons)
local HudLayout = require(script.Parent.HudLayout)
local HudDock = require(script.Parent.HudDock)
local PanelManager = require(script.Parent.PanelManager)

local FONTS = Theme.Fonts
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(43, 29, 63) -- #2B1D3F (teclas y tarjeta de la misión diaria)
local CREAM = Color3.fromRGB(255, 246, 224) -- #FFF6E0
local GREEN_TEXT = Color3.fromRGB(63, 174, 69) -- #3FAE45

-- Colores de los azulejos (HUD Botones.dc.html)
local TILE = {
	Outline = Color3.fromRGB(14, 14, 18), -- #0e0e12
	Top = Color3.fromRGB(85, 89, 99), -- #555963
	Mid = Color3.fromRGB(58, 61, 69), -- #3a3d45
	Bottom = Color3.fromRGB(42, 44, 50), -- #2a2c32
	OpenTop = Color3.fromRGB(95, 99, 110), -- #5f636e (ratón encima o panel abierto)
	OpenMid = Color3.fromRGB(66, 69, 78), -- #42454e
	OpenBottom = Color3.fromRGB(47, 49, 56), -- #2f3138
	Open = Color3.fromRGB(255, 224, 102), -- #FFE066 borde con el panel abierto
	Featured = Color3.fromRGB(255, 201, 60), -- #FFC93C anillo de Renacer
	Badge = Color3.fromRGB(236, 56, 64), -- #EC3840
	Percent = Color3.fromRGB(255, 244, 191), -- #FFF4BF
}

-- Medidas a escala 1 (la columna derecha usa las de HudLayout: SideTile, SideGap)
local SIZE = {
	Tile = 76, -- todos iguales (Renacer también: Santiago lo quiso del mismo tamaño)
	Gap = 12, -- entre azulejos de la fila de abajo
	Bottom = 20, -- separación de la fila con el borde de abajo
	LabelDrop = 6, -- cuánto asoma el nombre por debajo del azulejo
	SideReserve = 360, -- ancho que la fila de abajo deja libre a los lados (combate, tarjeta)
}
local SIDE = HudLayout.Sizes

local MenuBar = {}

export type Spec = {
	Id: string,
	Order: number,
	Icon: string,
	Image: string?,
	Label: string,
	Key: string?,
	Color: Color3?,
	Panels: { string }?,
	OnActivate: () -> (),
}

export type Entry = {
	Id: string,
	Tile: Frame,
	Button: TextButton,
	setBadge: (text: string?) -> (),
	setAttention: (active: boolean, color: Color3?) -> (),
	setProgress: (ratio: number?) -> (),
	setLabel: (text: string, color: Color3?) -> (),
	shimmer: (active: boolean) -> (),
}

type StyleSpec = {
	Group: string, -- "Bottom" (fila de abajo) o "Side" (columna derecha)
	Order: number,
	Icon: string,
	Key: string,
	IconSize: number?, -- lado del icono (por defecto 60; los iconos 3D, 64)
	IconTop: number?, -- distancia del icono al borde de arriba (por defecto 2; 0 si mide 64)
	Featured: boolean?,
}

local DOCK_STYLES: { [string]: StyleSpec } = {
	Armory = { Group = "Bottom", Order = 10, Icon = "armory3d", Key = "L", IconSize = 64 },
	Amulets = { Group = "Bottom", Order = 20, Icon = "amulets3d", Key = "G", IconSize = 64 },
	Pets = { Group = "Bottom", Order = 30, Icon = "pets3d", Key = "P", IconSize = 64 },
	-- Núcleos ya no tiene azulejo (CoreController no lo añade); si vuelve, va aquí.
	Cores = { Group = "Bottom", Order = 35, Icon = "cores", Key = "N" },
	-- Inventario (InventoryController): mochila 3D.
	Inventory = { Group = "Bottom", Order = 40, Icon = "inventory3d", Key = "I", IconSize = 64 },
	-- Las flechas llenan todo el dibujo: más pequeñas y centradas para que no pisen el borde.
	Rebirth = { Group = "Bottom", Order = 50, Icon = "rebirth3d", Key = "T", IconSize = 54, IconTop = 5, Featured = true },
	Quests = { Group = "Side", Order = 60, Icon = "quests", Key = "M" },
	Rewards = { Group = "Side", Order = 70, Icon = "rewards3d", Key = "J", IconSize = 64 },
	Shop = { Group = "Side", Order = 80, Icon = "shop", Key = "K" },
}
local GROUP_GAP_ORDER = 40 -- hueco más ancho (24) entre el grupo y Renacer
local TOUCH_GAP_ORDER = 55 -- en táctil, el mismo hueco después de Renacer

local dockGui: ScreenGui? = nil
local bottomRow: Frame? = nil
local bottomScale: UIScale? = nil
local sideColumn: Frame? = nil
local sideScale: UIScale? = nil
local touchGap: Frame? = nil
local touchMode: boolean? = nil
local leftStack: Frame? = nil
local leftScale: UIScale? = nil
local dailyCard: Frame? = nil
local dailyTitle: TextLabel? = nil
local dailyProg: TextLabel? = nil
local dailyFill: Frame? = nil
local entries: { [string]: any } = {}
local statusLines: { [string]: TextLabel } = {}

local function addInkStroke(instance: Instance, thickness: number, mode: Enum.ApplyStrokeMode?, color: Color3?): UIStroke
	return UiKit.create("UIStroke", {
		Color = color or INK,
		Thickness = thickness,
		ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, instance)
end

-- Hueco invisible en la fila de abajo: con el espaciado de la lista (12 a cada lado) da 24.
local function gap(name: string, order: number, parent: Instance): Frame
	return UiKit.create("Frame", {
		Name = name,
		Size = UDim2.fromOffset(0, 1),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, parent)
end

local function parentFor(entry: any): Frame
	if entry.Group == "Side" and not touchMode then
		return sideColumn :: Frame
	end
	return bottomRow :: Frame
end

-- Ancho de la fila de abajo a escala 1 (azulejos visibles, huecos y espaciado).
local function rowWidth(): number
	local width, count = 0, 0
	for _, child in (bottomRow :: Frame):GetChildren() do
		if child:IsA("GuiObject") and child.Visible then
			width += child.Size.X.Offset
			count += 1
		end
	end
	return width + math.max(count - 1, 0) * SIZE.Gap
end

-- Coloca la fila de abajo y la columna derecha según el diseño del HUD (HudDock/HudLayout).
local function relayout()
	if not dockGui or not bottomRow or not sideColumn then
		return
	end
	local layout = HudDock.layout()
	local side = layout.SideMenu
	local touch = layout.Touch == true or side == nil
	if touch ~= touchMode then
		touchMode = touch
		for _, entry in entries do
			entry.Slot.Parent = parentFor(entry)
		end
		if touchGap then
			touchGap.Visible = touch
		end
	end

	local s = layout.MenuScale or layout.Scale -- escala del HUD con el aumento de los botones
	local screen = (dockGui :: ScreenGui).AbsoluteSize
	local fit = (screen.X - SIZE.SideReserve) / math.max(rowWidth(), 1)
	if bottomScale then
		bottomScale.Scale = math.clamp(math.min(s, fit), 0.5, HudLayout.MaxScale)
	end
	bottomRow.Position = UDim2.new(0.5, 0, 1, -SIZE.Bottom * s)

	sideColumn.Visible = side ~= nil
	if side then
		-- Anclada arriba a la derecha: la UIScale encoge hacia esa esquina.
		sideColumn.Position = UDim2.fromOffset(side.X + side.W, side.Y)
		if sideScale then
			sideScale.Scale = side.Scale
		end
	end
end

local function build()
	if dockGui and dockGui.Parent then
		return
	end
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local oldTopHud = playerGui:FindFirstChild("SimpleTopHud")
	if oldTopHud then
		oldTopHud:Destroy()
	end
	local existing = playerGui:FindFirstChild("MenuDockHud")
	if existing then
		existing:Destroy()
	end

	local screenGui = UiKit.create("ScreenGui", {
		Name = "MenuDockHud",
		ResetOnSpawn = false,
		DisplayOrder = 4,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	dockGui = screenGui

	-- Fila de abajo en el centro: Armas, Amuletos, Mascotas | Renacer
	local bottom = UiKit.create("Frame", {
		Name = "BottomDock",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -SIZE.Bottom),
		Size = UDim2.fromOffset(0, SIZE.Tile),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
	}, screenGui)
	bottomScale = UiKit.create("UIScale", {}, bottom)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, SIZE.Gap),
	}, bottom)
	gap("GroupGap", GROUP_GAP_ORDER, bottom)
	local secondGap = gap("TouchGap", TOUCH_GAP_ORDER, bottom)
	secondGap.Visible = false
	touchGap = secondGap
	bottomRow = bottom

	-- Columna derecha: Misiones, Premios, Tienda
	local side = UiKit.create("Frame", {
		Name = "SideDock",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(SIDE.SideTile, SIDE.SideCount * SIDE.SideTile + (SIDE.SideCount - 1) * SIDE.SideGap),
		BackgroundTransparency = 1,
		Visible = false,
	}, screenGui)
	sideScale = UiKit.create("UIScale", {}, side)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, SIDE.SideGap),
	}, side)
	sideColumn = side

	-- Contenedor izquierdo para la tarjeta de misión diaria (debajo de las monedas)
	local left = UiKit.create("Frame", {
		Name = "LeftStatusStack",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 20, 0.56, 0),
		Size = UDim2.fromOffset(244, 96),
		BackgroundTransparency = 1,
	}, screenGui)
	leftScale = UiKit.create("UIScale", {}, left)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, left)
	leftStack = left

	-- Tarjeta de Misión Diaria estilo pergamino (como en `HUD Rediseño (standalone).html`)
	local card = UiKit.create("Frame", {
		Name = "DailyMiniCard",
		Size = UDim2.fromOffset(238, 56),
		BackgroundColor3 = WHITE,
		LayoutOrder = 1,
		Visible = false,
	}, left)
	UiKit.corner(card, 16)
	UiKit.create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(255, 248, 230), Color3.fromRGB(244, 226, 184)),
	}, card)
	addInkStroke(card, 3.5, Enum.ApplyStrokeMode.Border)

	Icons.make(card, "quests", {
		Name = "QuestIcon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(38, 38),
		ZIndex = 2,
	})

	local dTitle = UiKit.text(card, "Title", {
		Position = UDim2.fromOffset(54, 8),
		Size = UDim2.new(1, -110, 0, 20),
		Font = FONTS.Display,
		TextSize = 15,
		TextColor3 = INK,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "Patrulla del día",
		ZIndex = 2,
	})
	local dProg = UiKit.text(card, "Progress", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 9),
		Size = UDim2.fromOffset(54, 18),
		Font = FONTS.Display,
		TextSize = 14,
		TextColor3 = GREEN_TEXT,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "0/15",
		ZIndex = 2,
	})

	local dTrack = UiKit.create("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(54, 33),
		Size = UDim2.new(1, -66, 0, 11),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, card)
	UiKit.corner(dTrack, 6)

	local dFill = UiKit.create("Frame", {
		Name = "Fill",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(0.15, -4, 1, -4),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, dTrack)
	UiKit.corner(dFill, 4)
	UiKit.create("UIGradient", {
		Rotation = 0,
		Color = ColorSequence.new(Color3.fromRGB(182, 245, 166), Color3.fromRGB(96, 214, 96)),
	}, dFill)

	local cardBtn = UiKit.create("TextButton", {
		Name = "OpenQuests",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 5,
	}, card)
	cardBtn.Activated:Connect(function()
		PanelManager.toggle("Quests")
	end)

	dailyCard = card
	dailyTitle = dTitle
	dailyProg = dProg
	dailyFill = dFill

	local function applyLeftScale()
		if leftScale then
			leftScale.Scale = HudDock.scale()
		end
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		relayout()
		applyLeftScale()
	end)
	HudDock.Changed:Connect(function()
		relayout()
		applyLeftScale()
	end)
	relayout()
	applyLeftScale()

	PanelManager.Changed:Connect(function(openPanel: string?)
		for _, entry in entries do
			local active = false
			for _, panelName in entry.Panels do
				if panelName == openPanel then
					active = true
				end
			end
			entry.setOpen(active)
		end
	end)
end

-- Tamaño del nombre según su largo (como en el diseño: 19, 18 o 17).
local function labelSize(text: string): number
	local length = utf8.len(text) or #text
	if length <= 6 then
		return 19
	elseif length == 7 then
		return 18
	end
	return 17
end

function MenuBar.add(spec: Spec): Entry
	build()

	local existing = entries[spec.Id]
	if existing then
		return existing
	end

	local style: StyleSpec = DOCK_STYLES[spec.Id] or {
		Group = "Bottom",
		Order = 100 + spec.Order,
		Icon = spec.Image or string.lower(spec.Id),
		Key = spec.Key or "",
	}
	local featured = style.Featured == true -- Renacer: anillo dorado y porcentaje encima
	local size = SIZE.Tile
	local border = 3
	local radius = 12

	local slot = UiKit.create("Frame", {
		Name = "Slot_" .. spec.Id,
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		LayoutOrder = style.Order,
	}, nil)

	-- Todo lo que sube al pasar el ratón (y lo que devuelve MenuBar.tile)
	local lift = UiKit.create("Frame", {
		Name = "Tile_" .. spec.Id,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, slot)

	-- Sin sombra debajo ni brillo arriba: asomaban fuera del contorno y se veía un segundo
	-- cuadro gris detrás (Santiago). El azulejo es solo la cara gris con su contorno negro.

	-- Anillo negro por fuera del borde amarillo (panel abierto)
	local ring = UiKit.create("Frame", {
		Name = "OpenRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 4, 1, 4),
		BackgroundColor3 = TILE.Outline,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
	}, lift)
	UiKit.corner(ring, radius + 2)

	-- Cara del azulejo: el contorno (UIStroke) va por fuera, así que mide lo que el diseño
	-- menos el contorno y el total queda igual que en el diseño.
	local tile = UiKit.create("Frame", {
		Name = "Face",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -2 * border, 1, -2 * border),
		BackgroundColor3 = WHITE, -- el color lo da el degradado
		BorderSizePixel = 0,
		ZIndex = 3,
	}, lift)
	UiKit.corner(tile, radius - border)
	local gradient = UiKit.create("UIGradient", { Name = "Tint", Rotation = 90 }, tile)
	local stroke = addInkStroke(tile, border, Enum.ApplyStrokeMode.Border, TILE.Outline)
	-- Filo claro por dentro del contorno (dorado en Renacer)
	local inner = UiKit.create("Frame", {
		Name = "Inner",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, tile)
	UiKit.corner(inner, math.max(radius - border - 2, 2))
	UiKit.create("UIStroke", {
		Color = if featured then TILE.Featured else WHITE,
		Thickness = 2,
		Transparency = if featured then 0 else 0.9,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, inner)
	-- Icono grande, pegado arriba (el nombre ocupa la parte de abajo)
	local iconSize = style.IconSize or 60
	local iconTop = style.IconTop or (if iconSize >= 64 then 0 else 2)
	local icon = Icons.make(lift, style.Icon, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, iconTop),
		Size = UDim2.fromOffset(iconSize, iconSize),
		ZIndex = 5,
	})
	local emoji = icon:FindFirstChild("Emoji")
	if emoji and emoji:IsA("TextLabel") and not Icons.has(style.Icon) then
		-- Emoji (Armas ⚔️): más grande y centrado en el hueco de encima del nombre
		emoji.Text = spec.Icon
		emoji.Size = UDim2.fromScale(0.82, 0.82)
		emoji.Position = UDim2.fromScale(0.5, 0.53)
	end
	-- Sombra del dibujo (drop-shadow 0 2px 0 rgba(0,0,0,.4))
	local image = icon:FindFirstChild("Image")
	if image and image:IsA("ImageLabel") then
		local imageShadow = image:Clone()
		imageShadow.Name = "ImageShadow"
		imageShadow.ImageColor3 = Color3.new(0, 0, 0)
		imageShadow.ImageTransparency = 0.6
		imageShadow.Position = UDim2.fromOffset(0, 2)
		imageShadow.ZIndex = image.ZIndex - 1
		imageShadow.Parent = icon
	end

	-- Nombre: asoma por debajo del azulejo, blanco con borde negro
	local textSize = labelSize(spec.Label)
	local label = UiKit.text(lift, "Label", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, SIZE.LabelDrop + 1),
		Size = UDim2.new(1, 28, 0, textSize + 2),
		Font = FONTS.Display,
		TextSize = textSize,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = spec.Label,
		ZIndex = 7,
	})
	addInkStroke(label, 2.5, Enum.ApplyStrokeMode.Contextual, TILE.Outline)

	-- Porcentaje para renacer, encima del azulejo destacado
	local percent: TextLabel? = nil
	if featured then
		local percentLabel = UiKit.text(lift, "Percent", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, -16),
			Size = UDim2.new(1, 28, 0, 22),
			Font = FONTS.Display,
			TextSize = 20,
			TextColor3 = TILE.Percent,
			TextXAlignment = Enum.TextXAlignment.Center,
			Visible = false,
			ZIndex = 7,
		})
		addInkStroke(percentLabel, 2.5, Enum.ApplyStrokeMode.Contextual, TILE.Outline)
		percent = percentLabel
	end

	-- Tecla (arriba a la izquierda)
	local keyStr = spec.Key or style.Key
	if keyStr and keyStr ~= "" then
		local keySize = 22
		local keyBadge = UiKit.create("Frame", {
			Name = "KeyBadge",
			Position = UDim2.fromOffset(-7, -7),
			Size = UDim2.fromOffset(keySize, keySize),
			BackgroundColor3 = INK,
			ZIndex = 8,
		}, lift)
		UiKit.corner(keyBadge, 7)
		UiKit.create("UIStroke", {
			Color = WHITE,
			Thickness = 1.5,
			Transparency = 0.7,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, keyBadge)
		UiKit.text(keyBadge, "KeyText", {
			Size = UDim2.fromScale(1, 1),
			Font = FONTS.Display,
			TextSize = 12,
			TextColor3 = CREAM,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = keyStr,
			ZIndex = 9,
		})
	end

	-- Aviso rojo inclinado (arriba a la derecha)
	local badge = UiKit.create("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 9, 0, -9),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = TILE.Badge,
		Rotation = 6,
		Visible = false,
		ZIndex = 8,
	}, lift)
	UiKit.corner(badge, 6)
	addInkStroke(badge, 2.5, Enum.ApplyStrokeMode.Border, TILE.Outline)
	local badgeText = UiKit.text(badge, "Count", {
		Size = UDim2.fromScale(1, 1),
		Font = FONTS.Display,
		TextSize = 15,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 9,
	})

	local button = UiKit.create("TextButton", {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 10,
	}, lift)

	-- Estados: ratón encima (sube 5), panel abierto (borde amarillo, sube 4), atención
	-- (borde del color que pida el controlador, p. ej. Premios listos).
	local hovered, open, attention = false, false, false
	local attentionColor: Color3? = nil
	local quick = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function refresh()
		local highlighted = open or attention
		stroke.Color = if open then TILE.Open elseif attention then (attentionColor or TILE.Open) else TILE.Outline
		ring.Visible = highlighted
		local lit = highlighted or hovered
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, if lit then TILE.OpenTop else TILE.Top),
			ColorSequenceKeypoint.new(0.55, if lit then TILE.OpenMid else TILE.Mid),
			ColorSequenceKeypoint.new(1, if lit then TILE.OpenBottom else TILE.Bottom),
		})
		local rise = if hovered then -5 elseif open then -4 else 0
		TweenService:Create(lift, quick, { Position = UDim2.fromOffset(0, rise) }):Play()
	end
	refresh()

	button.MouseEnter:Connect(function()
		hovered = true
		refresh()
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		refresh()
	end)
	button.Activated:Connect(spec.OnActivate)

	local entry: any = {
		Id = spec.Id,
		Group = style.Group,
		Slot = slot,
		Tile = lift,
		Button = button,
		Panels = spec.Panels or {},
	}
	function entry.setBadge(text: string?)
		local show = text ~= nil and text ~= ""
		badge.Visible = show
		badgeText.Text = text or ""
	end
	function entry.setAttention(active: boolean, color: Color3?)
		attention = active
		attentionColor = color
		refresh()
	end
	function entry.setOpen(active: boolean)
		open = active
		refresh()
	end
	-- Renacer: porcentaje encima del azulejo (nil lo oculta)
	function entry.setProgress(ratio: number?)
		if not percent then
			return
		end
		percent.Visible = ratio ~= nil
		percent.Text = if ratio then string.format("%d%%", math.floor(math.clamp(ratio, 0, 1) * 100)) else ""
	end
	function entry.setLabel(text: string, color: Color3?)
		label.Text = text
		label.TextColor3 = color or WHITE
	end
	entry.shimmer = UiKit.shimmer(tile, radius - border)
	entry.Icon = icon

	entries[spec.Id] = entry
	if touchMode == nil then
		relayout()
	end
	slot.Parent = parentFor(entry)
	relayout()
	return entry
end

function MenuBar.tile(id: string): GuiObject?
	local entry = entries[id]
	return entry and entry.Tile
end

function MenuBar.status(id: string, order: number): TextLabel
	build()
	local existing = statusLines[id]
	if existing then
		return existing
	end

	if id == "Quests" then
		-- Proxy TextLabel que sincroniza automáticamente la tarjeta estilo pergamino `DailyMiniCard`
		local proxy = Instance.new("TextLabel")
		proxy.Name = "Status_Quests_Proxy"
		proxy.Visible = false
		proxy:GetPropertyChangedSignal("Text"):Connect(function()
			local raw = proxy.Text
			if not dailyCard or not dailyTitle or not dailyProg or not dailyFill then
				return
			end
			if raw == "" then
				dailyCard.Visible = false
				return
			end
			dailyCard.Visible = true
			-- Limpia el emoji inicial "📜 " si viene incluido
			local clean = string.gsub(raw, "^📜%s*", "")
			local titlePart, curStr, maxStr = string.match(clean, "^(.-)%s+([%d%.,kKmM]+)/([%d%.,kKmM]+)$")
			if titlePart and curStr and maxStr then
				dailyTitle.Text = titlePart
				dailyProg.Text = curStr .. "/" .. maxStr
				local curNum = tonumber((string.gsub(curStr, "[^%d%.]", ""))) or 0
				local maxNum = tonumber((string.gsub(maxStr, "[^%d%.]", ""))) or 1
				local ratio = math.clamp(curNum / math.max(maxNum, 1), 0.06, 1)
				dailyFill.Size = UDim2.new(ratio, -4, 1, -4)
			else
				dailyTitle.Text = clean
				dailyProg.Text = "¡Lista!"
				dailyFill.Size = UDim2.new(1, -4, 1, -4)
			end
		end)
		statusLines[id] = proxy
		return proxy
	end

	local line = UiKit.text(leftStack :: Frame, "Status_" .. id, {
		Size = UDim2.fromOffset(238, 22),
		Font = FONTS.Display,
		TextSize = 15,
		TextColor3 = WHITE,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = order + 2,
		Visible = false,
	})
	addInkStroke(line, 2.5, Enum.ApplyStrokeMode.Contextual)
	line:GetPropertyChangedSignal("Text"):Connect(function()
		line.Visible = line.Text ~= ""
	end)
	statusLines[id] = line
	return line
end

return MenuBar
