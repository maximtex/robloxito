-- Coordina los paneles modales (inventario, huevo, ...):
-- - Solo uno abierto a la vez: abrir uno cierra el anterior.
-- - Un panel puede negarse a cerrarse (CanClose), p. ej. el huevo durante la incubación.
-- - Escape (y B en mando) cierra el panel abierto mientras haya uno.
-- - Transición corta de apertura y cierre que no bloquea la interacción.
-- - Changed avisa a otros controladores (el HUD aparta la tarjeta de mejora).

local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local CLOSE_ACTION = "RebirthClosePanel"
local SLIDE_OFFSET = 14

type Options = {
	CanClose: (() -> boolean)?,
	OnOpen: (() -> ())?,
	OnClose: (() -> ())?,
}

type Panel = {
	Frame: GuiObject,
	Options: Options,
	BasePosition: UDim2,
	Tween: Tween?,
}

local PanelManager = {}

local panels: { [string]: Panel } = {}
local current: string? = nil
local changed = Instance.new("BindableEvent")

-- Se dispara con el nombre del panel abierto, o nil si no hay ninguno.
PanelManager.Changed = changed.Event

local function play(panel: Panel, position: UDim2, seconds: number, onDone: (() -> ())?)
	if panel.Tween then
		panel.Tween:Cancel()
	end
	local tween = TweenService:Create(panel.Frame, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = position })
	panel.Tween = tween
	if onDone then
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				onDone()
			end
		end)
	end
	tween:Play()
end

local function offset(position: UDim2): UDim2
	return position + UDim2.fromOffset(0, SLIDE_OFFSET)
end

local function setEscapeBound(bound: boolean)
	if bound then
		ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				PanelManager.close()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
	else
		ContextActionService:UnbindAction(CLOSE_ACTION)
	end
end

function PanelManager.register(name: string, frame: GuiObject, options: Options?)
	panels[name] = {
		Frame = frame,
		Options = options or {},
		BasePosition = frame.Position,
		Tween = nil,
	}
	frame.Visible = false
end

-- La posición de reposo cambia con el tamaño de pantalla (la calcula el diseño).
function PanelManager.setBasePosition(name: string, position: UDim2)
	local panel = panels[name]
	if not panel then
		return
	end
	panel.BasePosition = position
	if current == name then
		if panel.Tween then
			panel.Tween:Cancel()
			panel.Tween = nil
		end
		panel.Frame.Position = position
	end
end

function PanelManager.current(): string?
	return current
end

function PanelManager.isOpen(name: string): boolean
	return current == name
end

-- Marco de un panel registrado (para que otras piezas del HUD eviten taparlo).
function PanelManager.frame(name: string): GuiObject?
	local panel = panels[name]
	return panel and panel.Frame
end

local function hide(name: string)
	local panel = panels[name]
	play(panel, offset(panel.BasePosition), Theme.Layout.TransitionSeconds * 0.75, function()
		if current ~= name then
			panel.Frame.Visible = false
		end
	end)
	if panel.Options.OnClose then
		panel.Options.OnClose()
	end
end

-- Cierra el panel indicado (o el abierto). Devuelve false si el panel se niega.
function PanelManager.close(name: string?): boolean
	local target = name or current
	if target == nil or target ~= current then
		return true
	end
	local panel = panels[target]
	if panel.Options.CanClose and not panel.Options.CanClose() then
		return false
	end
	current = nil
	setEscapeBound(false)
	hide(target)
	changed:Fire(nil)
	return true
end

-- Abre un panel (cerrando el anterior). Devuelve false si el anterior no puede cerrarse.
function PanelManager.open(name: string): boolean
	local panel = panels[name]
	if not panel then
		return false
	end
	if current == name then
		return true
	end
	if current ~= nil then
		local previous = panels[current]
		if previous.Options.CanClose and not previous.Options.CanClose() then
			return false
		end
		local previousName = current :: string
		current = nil
		hide(previousName)
	end

	current = name
	panel.Frame.Position = offset(panel.BasePosition)
	panel.Frame.Visible = true
	play(panel, panel.BasePosition, Theme.Layout.TransitionSeconds, nil)
	setEscapeBound(true)
	if panel.Options.OnOpen then
		panel.Options.OnOpen()
	end
	changed:Fire(name)
	return true
end

function PanelManager.toggle(name: string)
	if current == name then
		PanelManager.close(name)
	else
		PanelManager.open(name)
	end
end

return PanelManager
