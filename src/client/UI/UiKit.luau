-- Utilidades para construir interfaz con el estilo del tema.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local HudLayout = require(script.Parent.HudLayout)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local LAYOUT = Theme.Layout
local FINISH = Theme.Finish
local CARTOON = Theme.Cartoon
local HEADER = Theme.Header
local GRID = Theme.Grid

local UiKit = {}

function UiKit.create(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in properties do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UiKit.corner(parent: Instance, radius: number)
	UiKit.create("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

function UiKit.stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	return UiKit.create("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

-- Borde grueso alrededor de las letras (texto blanco con contorno, estilo simulador).
function UiKit.outline(label: GuiObject, thickness: number?, color: Color3?): UIStroke
	return UiKit.create("UIStroke", {
		Name = "Outline",
		Color = color or CARTOON.Ink,
		Thickness = thickness or CARTOON.TextStroke,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, label)
end

-- Degradado vertical que oscurece la parte baja del fondo (multiplica el color, así que
-- cambiar BackgroundColor3 sigue funcionando).
function UiKit.shade(guiObject: GuiObject, bottom: number): UIGradient
	return UiKit.create("UIGradient", {
		Name = "Shade",
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(bottom, bottom, bottom)),
	}, guiObject)
end

-- Brillo blanco suave en la parte alta (queda por debajo del contenido del panel).
function UiKit.shine(guiObject: GuiObject, radius: number)
	local shine = UiKit.create("Frame", {
		Name = "Shine",
		Size = UDim2.new(1, 0, 0, FINISH.ShineHeight),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = FINISH.ShineTransparency,
		BorderSizePixel = 0,
		Active = false,
		Selectable = false,
	}, guiObject)
	UiKit.corner(shine, radius)
	UiKit.create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(0, 1),
	}, shine)
	return shine
end

-- Destello que recorre un botón de izquierda a derecha (para llamar la atención sobre
-- una acción disponible). Devuelve una función para activarlo o pararlo.
function UiKit.shimmer(button: GuiObject, radius: number): (boolean) -> ()
	local sweep = UiKit.create("Frame", {
		Name = "Shimmer",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Active = false,
		Visible = false,
		ZIndex = button.ZIndex + 1,
	}, button)
	UiKit.corner(sweep, radius)
	local gradient = UiKit.create("UIGradient", {
		Rotation = 20,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.55),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-1, 0),
	}, sweep)
	local running = false
	local token = 0
	return function(active: boolean)
		if active == running then
			return
		end
		running = active
		token += 1
		local myToken = token
		sweep.Visible = active
		if not active then
			return
		end
		task.spawn(function()
			while running and token == myToken and sweep.Parent do
				gradient.Offset = Vector2.new(-1, 0)
				local tween = TweenService:Create(gradient, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Offset = Vector2.new(1, 0) })
				tween:Play()
				task.wait(2.6)
			end
		end)
	end
end

-- Estados de botón: normal, hover (brillo), pulsado (se encoge) y deshabilitado
-- (atributo "Disabled": sin brillo ni efecto; el botón sigue recibiendo el clic para
-- poder explicar por qué no está disponible).
function UiKit.setDisabled(button: GuiButton, disabled: boolean)
	button:SetAttribute("Disabled", disabled)
	if disabled then
		local highlight = button:FindFirstChild("Highlight")
		if highlight and highlight:IsA("Frame") then
			highlight.BackgroundTransparency = 1
		end
	end
end

function UiKit.addStates(button: GuiButton)
	button.AutoButtonColor = false
	local highlight = UiKit.create("Frame", {
		Name = "Highlight",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = button.ZIndex,
		Active = false,
	}, button)
	UiKit.corner(highlight, 10)
	local scale = UiKit.create("UIScale", { Name = "PressScale" }, button)
	local quick = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local hovered = false

	local function isDisabled(): boolean
		return button:GetAttribute("Disabled") == true
	end
	local function refresh()
		local active = hovered and not isDisabled()
		TweenService:Create(highlight, quick, { BackgroundTransparency = if active then 0.88 else 1 }):Play()
	end

	button.MouseEnter:Connect(function()
		hovered = true
		refresh()
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		refresh()
		TweenService:Create(scale, quick, { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		if not isDisabled() then
			TweenService:Create(scale, quick, { Scale = 0.96 }):Play()
		end
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, quick, { Scale = 1 }):Play()
	end)
	button:GetAttributeChangedSignal("Disabled"):Connect(refresh)
end

function UiKit.text(parent: Instance, name: string, properties: { [string]: any }): TextLabel
	local label = UiKit.create("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Font = FONTS.Body,
		TextColor3 = THEME.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}, nil)
	for key, value in properties do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

function UiKit.button(parent: Instance, name: string, properties: { [string]: any }): TextButton
	local button = UiKit.create("TextButton", {
		Name = name,
		AutoButtonColor = true,
		BackgroundColor3 = THEME.Buy,
		Font = FONTS.Display,
		TextColor3 = THEME.Text,
		TextSize = 18,
		TextStrokeColor3 = THEME.Outline,
		TextStrokeTransparency = 1, -- el borde de las letras lo pone UiKit.outline
	}, nil)
	for key, value in properties do
		(button :: any)[key] = value
	end
	UiKit.corner(button, 10)
	UiKit.shade(button, FINISH.ButtonShade)
	UiKit.stroke(button, THEME.Outline, 2.5, 0)
	-- Letras blancas con contorno negro (más grueso cuanto más grande el texto)
	UiKit.outline(button, math.clamp(button.TextSize / 8, 1.5, 3), THEME.Outline)
	UiKit.addStates(button)
	button.Parent = parent
	return button
end

-- Textura de studs del cuerpo del panel (queda debajo de todo el contenido).
function UiKit.grid(panel: GuiObject, radius: number): ImageLabel
	local grid = UiKit.create("ImageLabel", {
		Name = "Grid",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = GRID.Image,
		ImageTransparency = GRID.Transparency,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(GRID.Tile, GRID.Tile),
		ZIndex = 0,
		Active = false,
	}, panel)
	UiKit.corner(grid, radius)
	return grid
end

-- Barra de título color arena. No hace falta llamarla: UiKit.panel la muestra sola cuando
-- el panel recibe su título arriba (un TextLabel "Title" o "Heading" a 24 px o menos del
-- borde) y la estira hasta cubrir los textos de la cabecera (título, subtítulo, coste...:
-- los TextLabel de hasta 34 px de alto que empiezan antes de 60 px). Esos textos pasan a
-- blanco con contorno negro y el botón "Close" de arriba a la derecha pasa a rojo.
local HEADER_TITLES = { Title = true, Heading = true }
local HEADER_TITLE_TOP = 24
local HEADER_TEXT_TOP = 60
local HEADER_TEXT_HEIGHT = 34
local HEADER_PADDING = 4
local HEADER_LIGHT_TEXT = Color3.fromRGB(255, 250, 236)

local function isHeaderText(child: Instance): boolean
	if not child:IsA("TextLabel") then
		return false
	end
	local position, size = child.Position, child.Size
	return position.Y.Scale == 0
		and size.Y.Scale == 0
		and position.Y.Offset < HEADER_TEXT_TOP
		and size.Y.Offset <= HEADER_TEXT_HEIGHT
end

function UiKit.titleBar(panel: Frame, radius: number, shine: Frame?)
	local header = UiKit.create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, HEADER.MinHeight),
		BackgroundColor3 = Color3.new(1, 1, 1), -- el color lo da el degradado
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 0,
		Active = false,
	}, panel)
	UiKit.corner(header, radius)
	local gradient = UiKit.create("UIGradient", { Rotation = 90 }, header)
	-- Las esquinas de abajo van rectas: un relleno del color de abajo tapa su redondeo.
	UiKit.create("Frame", {
		Name = "Fill",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, radius),
		BackgroundColor3 = HEADER.Bottom,
		BorderSizePixel = 0,
		ZIndex = 0,
		Active = false,
	}, header)
	local gloss = UiKit.create("Frame", {
		Name = "Gloss",
		Position = UDim2.fromOffset(radius, 4),
		Size = UDim2.new(1, -2 * radius, 0, 3),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = HEADER.GlossTransparency,
		BorderSizePixel = 0,
		ZIndex = 0,
		Active = false,
	}, header)
	UiKit.corner(gloss, 2)
	local line = UiKit.create("Frame", {
		Name = "HeaderLine",
		Position = UDim2.fromOffset(0, HEADER.MinHeight),
		Size = UDim2.new(1, 0, 0, HEADER.Line),
		BackgroundColor3 = THEME.Stroke,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 0,
		Active = false,
	}, panel)

	local texts: { TextLabel } = {}
	local titled = false

	local function refresh()
		local height = HEADER.MinHeight
		for _, label in texts do
			height = math.max(height, label.Position.Y.Offset + label.Size.Y.Offset + HEADER_PADDING)
		end
		header.Size = UDim2.new(1, 0, 0, height)
		line.Position = UDim2.fromOffset(0, height)
		-- Degradado de arena clara a tostada; el tramo redondeado de abajo, liso (como el relleno).
		local flat = math.clamp((height - radius) / height, 0.01, 0.99)
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, HEADER.Top),
			ColorSequenceKeypoint.new(flat, HEADER.Bottom),
			ColorSequenceKeypoint.new(1, HEADER.Bottom),
		})
		header.Visible = true
		line.Visible = true
		if shine then
			shine.Visible = false
		end
		for _, label in texts do
			if not label:FindFirstChild("Outline") then
				UiKit.outline(label, if HEADER_TITLES[label.Name] then CARTOON.TextStroke else 2, THEME.Outline)
			end
			if label.TextColor3 == THEME.Muted then
				label.TextColor3 = HEADER_LIGHT_TEXT
			end
		end
	end

	local function onChild(child: Instance)
		if child:IsA("TextButton") and child.Name == "Close" and child.Position.Y.Scale == 0 and child.Position.Y.Offset <= HEADER_TITLE_TOP then
			child.BackgroundColor3 = HEADER.Close
			child.Font = FONTS.Display
			child.TextSize = math.max(child.TextSize, 26)
			local outline = child:FindFirstChild("Outline")
			if outline and outline:IsA("UIStroke") then
				outline.Thickness = 2.5
			end
			return
		end
		if not isHeaderText(child) then
			return
		end
		local label = child :: TextLabel
		table.insert(texts, label)
		if HEADER_TITLES[label.Name] and label.Position.Y.Offset <= HEADER_TITLE_TOP then
			titled = true
		end
		if titled then
			refresh()
		end
	end

	for _, child in panel:GetChildren() do
		onChild(child)
	end
	panel.ChildAdded:Connect(onChild)
end

-- Panel con el estilo común (gris carbón con studs, contorno negro grueso, barra de título
-- color arena) y su UIScale.
function UiKit.panel(parent: Instance, name: string, size: Vector2, anchor: Vector2, position: UDim2): (Frame, UIScale)
	-- Studs y barra de título solo en paneles grandes (no en botones redondos, barras ni
	-- píldoras, que se hacen también con UiKit.panel).
	local big = size.X >= GRID.MinSize and size.Y >= GRID.MinSize
	local radius = if big then FINISH.PanelCorner else 16
	local panel = UiKit.create("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = THEME.Panel,
		BackgroundTransparency = THEME.PanelTransparency,
	}, parent)
	UiKit.corner(panel, radius)
	UiKit.stroke(panel, THEME.Stroke, CARTOON.Stroke, THEME.StrokeTransparency)
	UiKit.shade(panel, FINISH.PanelShade)
	if big then
		UiKit.grid(panel, radius)
	end
	local shine = UiKit.shine(panel, radius)
	if big then
		UiKit.titleBar(panel, radius, shine)
	end
	local scale = UiKit.create("UIScale", {}, panel)
	return panel, scale
end

-- Escala general del HUD para un tamaño de pantalla (la de HudLayout, igual para todo).
function UiKit.computeScale(size: Vector2): number
	local isTouchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	return HudLayout.scale(size, isTouchOnly)
end

-- Mantiene las UIScale ajustadas al tamaño de pantalla disponible.
function UiKit.bindScale(screenGui: ScreenGui, scales: { UIScale })
	local function apply()
		local size = screenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local scale = UiKit.computeScale(size)
		for _, uiScale in scales do
			uiScale.Scale = scale
		end
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
	apply()
end

-- Diseño de un panel modal (cálculo puro): centrado en horizontal, justo DEBAJO de la
-- tarjeta de energía (que nunca queda tapada), sin invadir la barra del menú de la
-- izquierda y encogido si no cabe. Devuelve la escala del panel y la Y de su borde superior.
-- En pantallas muy bajas (móvil en horizontal), si debajo de la energía el panel quedaría
-- ilegible, pasa a modo compacto: empieza arriba (tapando la energía solo mientras está
-- abierto) y siempre cabe entero.
local MIN_READABLE_SCALE = 0.55

function UiKit.computeModalLayout(screenSize: Vector2, baseSize: Vector2, hudScale: number): (number, number)
	local sideReserve = 16 + LAYOUT.SideButtonWidth * hudScale + LAYOUT.Gap
	local availableWidth = screenSize.X - 2 * sideReserve

	-- La tarjeta de energía tiene un margen fijo arriba y su altura escala con UIScale.
	local top = LAYOUT.Margin + LAYOUT.EnergyCardSize.Y * hudScale + LAYOUT.Gap
	local fit = math.min(hudScale, (screenSize.Y - top - LAYOUT.Margin) / baseSize.Y, availableWidth / baseSize.X)
	if fit < MIN_READABLE_SCALE then
		top = LAYOUT.Margin
		fit = math.min(hudScale, (screenSize.Y - 2 * LAYOUT.Margin) / baseSize.Y, availableWidth / baseSize.X)
	end
	return fit, top
end

-- Aplica computeModalLayout ahora y cada vez que cambia el tamaño de pantalla.
-- `onPosition` recibe la posición de reposo del panel (anclado arriba al centro).
function UiKit.bindModalLayout(screenGui: ScreenGui, uiScale: UIScale, baseSize: Vector2, onPosition: (UDim2) -> ())
	local function apply()
		local size = screenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local scale, top = UiKit.computeModalLayout(size, baseSize, UiKit.computeScale(size))
		uiScale.Scale = scale
		onPosition(UDim2.new(0.5, 0, 0, top))
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
	apply()
end

return UiKit
