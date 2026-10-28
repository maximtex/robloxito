-- Avisos breves de toda la interfaz en UNA sola pila (antes cada sistema ponía los suyos bajo
-- la energía y se encimaban entre sí): centrada bajo la tarjeta de energía (y bajo la barra
-- del jefe si se ve), con tantas filas como quepan antes de la tarjeta de mejora (HudLayout).
-- Si hay un panel abierto que ocupa esa zona, la pila baja al borde inferior de la pantalla,
-- o se pone al lado del panel si también tapa el borde inferior (HudLayout.toastSpot). Si no
-- hay hueco, la pila se oculta y las tarjetas esperan: al cerrarse el panel se ven completas.
-- Estilos:
-- - "Card" (por defecto): tarjeta con borde de color. Con Title, tarjeta de dos líneas.
-- - "Line": texto suelto con contorno, breve (la energía que da cada enemigo).
-- Con Key, un aviso que ya se ve (o espera) se actualiza en su sitio en vez de apilarse.
-- Las tarjetas que no caben esperan su turno; las líneas sobrantes ceden su sitio.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local HudDock = require(script.Parent.HudDock)
local HudLayout = require(script.Parent.HudLayout)
local PanelManager = require(script.Parent.PanelManager)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local SIZES = HudLayout.Sizes

local CARD_SECONDS = 2.2
local TITLED_SECONDS = 4.5 -- antes 7: los de título (botín, logro, arma nueva) tapaban mucho
local LINE_SECONDS = 1.4
local MAX_QUEUE = 4
local FADE = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

export type Options = {
	Color: Color3?,
	Key: string?,
	Style: string?, -- "Card" | "Line"
	Duration: number?,
	Title: string?,
	OnClick: (() -> ())?,
}

local Toasts = {}

type Item = {
	Frame: GuiObject,
	Text: TextLabel,
	Title: TextLabel?,
	Stroke: UIStroke?,
	Style: string,
	Key: string?,
	Token: number,
	Closing: boolean,
	Duration: number,
}

local screenGui: ScreenGui? = nil
local stack: Frame? = nil
local stackScale: UIScale? = nil
local listLayout: UIListLayout? = nil
local items: { Item } = {}
local queue: { { Text: string, Options: Options } } = {}
local order = 0
local held = false -- pila oculta por un panel: las tarjetas no caducan mientras tanto
local schedule: (item: Item, seconds: number) -> () -- más abajo

local function layout(): any
	return HudDock.layout()
end

-- Rectángulo en pantalla del panel abierto (si hay uno visible).
local function openPanelRect(): any?
	local name = PanelManager.current()
	local frame = name and PanelManager.frame(name)
	if not frame or not frame.Visible then
		return nil
	end
	return { X = frame.AbsolutePosition.X, Y = frame.AbsolutePosition.Y, W = frame.AbsoluteSize.X, H = frame.AbsoluteSize.Y }
end

local function place()
	if not stack or not stackScale or not listLayout then
		return
	end
	local current = layout()
	local s = current.Scale
	stackScale.Scale = s
	local spot = HudLayout.toastSpot(current, openPanelRect())
	local wasHeld = held
	held = spot.Mode == "Hidden"
	stack.Visible = not held
	if wasHeld and not held then
		-- Vuelven a verse: cada tarjeta recupera su tiempo entero.
		for _, item in items do
			if not item.Closing and item.Style ~= "Line" then
				schedule(item, item.Duration)
			end
		end
	end
	stack.Size = UDim2.fromOffset(spot.W / s, 0)
	if spot.Mode == "Bottom" then
		stack.AnchorPoint = Vector2.new(0.5, 1)
		stack.Position = UDim2.new(0.5, 0, 1, -SIZES.Margin)
		listLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	else
		stack.AnchorPoint = Vector2.new(0.5, 0)
		stack.Position = UDim2.fromOffset(spot.X, spot.Y)
		listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	end
end

local function ensure()
	if screenGui and screenGui.Parent then
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("ToastHud")
	if existing then
		existing:Destroy()
	end
	local gui = UiKit.create("ScreenGui", {
		Name = "ToastHud",
		ResetOnSpawn = false,
		DisplayOrder = 7, -- por encima de los paneles (5) y del portal (6)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local frame = UiKit.create("Frame", {
		Name = "Stack",
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, gui)
	stackScale = UiKit.create("UIScale", {}, frame)
	listLayout = UiKit.create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, SIZES.ToastGap),
	}, frame)
	gui.Parent = playerGui
	screenGui = gui
	stack = frame
	HudDock.Changed:Connect(place)
	PanelManager.Changed:Connect(function()
		-- El panel se coloca en el mismo cuadro: se espera a que tenga su posición.
		task.defer(place)
	end)
	place()
end

local function maxItems(): number
	return layout().Toasts.MaxItems
end

local showNext: () -> ()

local function close(item: Item)
	if item.Closing then
		return
	end
	item.Closing = true
	local frame = item.Frame
	if item.Style == "Line" then
		TweenService:Create(item.Text, FADE, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	else
		TweenService:Create(frame, FADE, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(item.Text, FADE, { TextTransparency = 1 }):Play()
		if item.Title then
			TweenService:Create(item.Title, FADE, { TextTransparency = 1 }):Play()
		end
		if item.Stroke then
			TweenService:Create(item.Stroke, FADE, { Transparency = 1 }):Play()
		end
	end
	task.delay(0.22, function()
		local index = table.find(items, item)
		if index then
			table.remove(items, index)
		end
		frame:Destroy()
		showNext()
	end)
end

schedule = function(item: Item, seconds: number)
	item.Token += 1
	item.Duration = seconds
	local token = item.Token
	task.delay(seconds, function()
		-- Con la pila oculta, las tarjetas esperan (place() las reprograma al volver).
		if item.Token == token and not (held and item.Style ~= "Line") then
			close(item)
		end
	end)
end

local function durationOf(options: Options, style: string): number
	if options.Duration then
		return options.Duration
	end
	if style == "Line" then
		return LINE_SECONDS
	end
	return if options.Title then TITLED_SECONDS else CARD_SECONDS
end

local function build(text: string, options: Options): Item
	local style = options.Style or "Card"
	local color = options.Color or THEME.Text
	order += 1
	if style == "Line" then
		local label = UiKit.text(stack :: Frame, "Line", {
			Size = UDim2.new(1, 0, 0, SIZES.ToastLine),
			Font = FONTS.Display,
			TextSize = 20,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeColor3 = Color3.new(0, 0, 0),
			TextStrokeTransparency = 0.35,
			TextTransparency = 1,
			Text = text,
			LayoutOrder = order,
		})
		TweenService:Create(label, FADE, { TextTransparency = 0 }):Play()
		return { Frame = label, Text = label, Style = style, Key = options.Key, Token = 0, Closing = false, Duration = LINE_SECONDS }
	end

	local titled = options.Title ~= nil and layout().Toasts.AllowTitled
	local body = text
	if options.Title and not titled then
		body = options.Title .. "  " .. text
	end
	local frame = UiKit.create("Frame", {
		Name = "Card",
		Size = UDim2.new(1, 0, 0, if titled then SIZES.ToastTitled else SIZES.Toast),
		BackgroundColor3 = THEME.Panel,
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, stack)
	UiKit.corner(frame, 12)
	UiKit.shade(frame, Theme.Finish.PanelShade)
	local stroke = UiKit.stroke(frame, color, 1.5, 1)
	local title: TextLabel? = nil
	if titled then
		title = UiKit.text(frame, "Title", {
			Position = UDim2.fromOffset(14, 6),
			Size = UDim2.new(1, -28, 0, 22),
			Font = FONTS.Display,
			TextSize = 17,
			TextColor3 = color,
			TextTransparency = 1,
			Text = options.Title,
		})
	end
	local label = UiKit.text(frame, "Text", {
		Position = if titled then UDim2.fromOffset(14, 29) else UDim2.fromOffset(12, 0),
		Size = if titled then UDim2.new(1, -28, 1, -33) else UDim2.new(1, -24, 1, 0),
		Font = if titled then FONTS.Light else FONTS.Display,
		TextSize = if titled then 14 else (if (utf8.len(body) or #body) > 40 then 15 else 17),
		TextColor3 = if titled then THEME.Text else color,
		TextXAlignment = if titled then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		TextYAlignment = if titled then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center,
		TextWrapped = true,
		TextTransparency = 1,
		Text = body,
	})
	local item: Item = { Frame = frame, Text = label, Title = title, Stroke = stroke, Style = style, Key = options.Key, Token = 0, Closing = false, Duration = CARD_SECONDS }
	if options.OnClick then
		local button = UiKit.create("TextButton", {
			Name = "Dismiss",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 5,
		}, frame)
		button.Activated:Connect(function()
			local callback = options.OnClick :: () -> ()
			callback()
			close(item)
		end)
	end
	TweenService:Create(frame, FADE, { BackgroundTransparency = THEME.PanelTransparency }):Play()
	TweenService:Create(label, FADE, { TextTransparency = 0 }):Play()
	TweenService:Create(stroke, FADE, { Transparency = 0.15 }):Play()
	if title then
		TweenService:Create(title, FADE, { TextTransparency = 0 }):Play()
	end
	return item
end

local function openCount(): number
	local count = 0
	for _, item in items do
		if not item.Closing then
			count += 1
		end
	end
	return count
end

local function present(text: string, options: Options)
	local style = options.Style or "Card"
	local item = build(text, options)
	table.insert(items, item)
	schedule(item, durationOf(options, style))
end

showNext = function()
	while #queue > 0 and openCount() < maxItems() do
		local nextItem = table.remove(queue, 1) :: any
		present(nextItem.Text, nextItem.Options)
	end
end

-- Muestra un aviso breve.
function Toasts.show(text: string, options: Options?)
	ensure()
	local opts: Options = options or {}
	local style = opts.Style or "Card"
	-- Mismo Key: se actualiza el que ya se ve (o el que espera) y se alarga su tiempo.
	if opts.Key then
		for _, item in items do
			if item.Key == opts.Key and not item.Closing then
				item.Text.Text = text
				if opts.Color then
					if item.Style == "Line" or not item.Title then
						item.Text.TextColor3 = opts.Color
					end
					if item.Stroke then
						item.Stroke.Color = opts.Color
					end
				end
				schedule(item, durationOf(opts, item.Style))
				return
			end
		end
		for _, queued in queue do
			if queued.Options.Key == opts.Key then
				queued.Text = text
				queued.Options = opts
				return
			end
		end
	end
	if openCount() >= maxItems() then
		if style == "Line" then
			-- Una línea nueva sustituye a la línea más antigua (si la hay); si no, se omite.
			for _, item in items do
				if item.Style == "Line" and not item.Closing then
					close(item)
					break
				end
			end
			if openCount() >= maxItems() then
				return
			end
		else
			if #queue >= MAX_QUEUE then
				table.remove(queue, 1)
			end
			table.insert(queue, { Text = text, Options = opts })
			-- Si hay líneas de combate ocupando sitio, ceden el suyo a la tarjeta.
			for _, item in items do
				if item.Style == "Line" and not item.Closing then
					close(item)
					break
				end
			end
			return
		end
	end
	present(text, opts)
end

return Toasts
