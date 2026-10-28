-- Columnas compartidas del HUD (ScreenGui "HudDock"): cada controlador mete su pieza en una
-- columna y la columna las apila sin solaparse (antes cada uno calculaba su posición a mano y
-- acababan encimadas). Las posiciones y la escala salen de HudLayout (cálculo puro probado).
-- - "Left": barra del menú (MenuBar), líneas de estado y, en táctil, el seguimiento de misiones.
-- - "Right": aviso de datos guardados, tutorial y, en escritorio, el seguimiento de misiones.
-- Changed avisa cuando cambia el diseño (tamaño de pantalla, entradas del menú, barra del jefe
-- o el tamaño de la interfaz elegido en ⚙️ Ajustes).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local HudLayout = require(script.Parent.HudLayout)
local UserScale = require(script.Parent.UserScale)

local HudDock = {}

local changed = Instance.new("BindableEvent")
HudDock.Changed = changed.Event

local screenGui: ScreenGui? = nil
local columns: { [string]: Frame } = {}
local listLayouts: { UIListLayout } = {}
local options = { MenuEntries = 5, StatusLines = 2, BossBar = false, Chips = false }
local current: any = nil

function HudDock.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function ensureGui(): ScreenGui
	if screenGui and screenGui.Parent then
		return screenGui
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("HudDock")
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "HudDock"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4 -- sobre el HUD de combate, por debajo de los paneles modales (5)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	for _, name in { "Left", "Right" } do
		local column = Instance.new("Frame")
		column.Name = name
		column.BackgroundTransparency = 1
		column.AutomaticSize = Enum.AutomaticSize.Y
		column.AnchorPoint = if name == "Right" then Vector2.new(1, 0) else Vector2.zero
		local list = Instance.new("UIListLayout")
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.HorizontalAlignment = if name == "Right" then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left
		list.Parent = column
		table.insert(listLayouts, list)
		column.Parent = gui
		columns[name] = column
	end
	gui.Parent = playerGui
	screenGui = gui
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		HudDock.relayout()
	end)
	return gui
end

function HudDock.relayout()
	local gui = ensureGui()
	local size = gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local layout = HudLayout.compute(size, HudDock.isTouch(), options)
	current = layout
	local gap = math.floor(HudLayout.Sizes.Gap * 0.67 * layout.Scale + 0.5)
	for _, list in listLayouts do
		list.Padding = UDim.new(0, gap)
	end
	local left, right = columns.Left, columns.Right
	left.Position = UDim2.fromOffset(layout.Left.X, layout.Left.Y)
	left.Size = UDim2.fromOffset(layout.Left.W, 0)
	-- En escritorio queda a la izquierda de los botones del menú de la derecha (Right.Inset).
	right.Position = UDim2.new(1, -(layout.Right.Inset or HudLayout.Sizes.Edge), 0, layout.Right.Y)
	right.Size = UDim2.fromOffset(layout.Right.W, 0)
	changed:Fire(layout)
end

-- Diseño actual (se calcula la primera vez que se pide).
function HudDock.layout(): any
	if not current then
		HudDock.relayout()
	end
	if not current then
		-- Pantalla aún sin tamaño: diseño de referencia para no devolver nil.
		current = HudLayout.compute(HudLayout.Reference, HudDock.isTouch(), options)
	end
	return current
end

function HudDock.scale(): number
	return HudDock.layout().Scale
end

-- Mete `item` en una columna ("Left" o "Right") con su orden (de arriba hacia abajo).
function HudDock.attach(columnName: string, item: GuiObject, order: number)
	ensureGui()
	local column = columns[columnName]
	assert(column, "Columna desconocida: " .. tostring(columnName))
	item.AnchorPoint = Vector2.zero
	item.Position = UDim2.new()
	item.LayoutOrder = order
	item.Parent = column
end

function HudDock.column(columnName: string): Frame
	ensureGui()
	return columns[columnName]
end

-- Borde inferior (Y absoluta) hasta el que puede crecer una columna.
function HudDock.bottom(columnName: string): number
	local layout = HudDock.layout()
	return if columnName == "Right" then layout.Right.Bottom else layout.Left.Bottom
end

-- Columna donde va el seguimiento de misiones según el dispositivo.
function HudDock.trackerColumn(): string
	return HudDock.layout().TrackerColumn
end

local function setOption(key: string, value: any)
	if options[key] == value then
		return
	end
	options[key] = value
	HudDock.relayout()
end

function HudDock.setMenuEntries(count: number)
	setOption("MenuEntries", count)
end

function HudDock.setStatusLines(count: number)
	setOption("StatusLines", count)
end

function HudDock.setBossBar(visible: boolean)
	setOption("BossBar", visible)
end

function HudDock.setChips(visible: boolean)
	setOption("Chips", visible)
end

-- ⚙️ Tamaño de la interfaz: HudLayout ya usa el nuevo; se recoloca todo.
UserScale.watch(function()
	if screenGui then
		HudDock.relayout()
	else
		current = nil
	end
end)

return HudDock
