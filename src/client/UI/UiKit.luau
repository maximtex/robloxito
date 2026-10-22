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
		TextStrokeTransparency = 0.35,
	}, nil)
	for key, value in properties do
		(button :: any)[key] = value
	end
	UiKit.corner(button, 10)
	UiKit.shade(button, FINISH.ButtonShade)
	UiKit.stroke(button, THEME.Outline, 2.5, 0)
	UiKit.addStates(button)
	button.Parent = parent
	return button
end

-- Panel con el estilo común (fondo esmeralda, contorno oscuro grueso) y su UIScale.
function UiKit.panel(parent: Instance, name: string, size: Vector2, anchor: Vector2, position: UDim2): (Frame, UIScale)
	local panel = UiKit.create("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = THEME.Panel,
		BackgroundTransparency = THEME.PanelTransparency,
	}, parent)
	UiKit.corner(panel, 16)
	UiKit.stroke(panel, THEME.Stroke, CARTOON.Stroke, THEME.StrokeTransparency)
	UiKit.shade(panel, FINISH.PanelShade)
	UiKit.shine(panel, 16)
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
