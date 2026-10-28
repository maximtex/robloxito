-- ⚙️ Ajustes: por ahora, el tamaño de la interfaz (pruebas con amigos: el HUD tapaba
-- demasiado y no se podía achicar). Botón pequeño de engranaje (abajo a la izquierda en
-- escritorio; arriba en la columna izquierda en táctil, donde abajo está el joystick) y un
-- panel con − / + que cambia el tamaño al momento. Se guarda con la partida (UserScale →
-- SetSetting → SettingsService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsLogic = require(ReplicatedStorage:WaitForChild("Shared").SettingsLogic)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudDock = require(script.Parent.Parent.UI.HudDock)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local UserScale = require(script.Parent.Parent.UI.UserScale)

local THEME = Theme.Colors
local FONTS = Theme.Fonts

local SettingsController = {}

local PANEL_NAME = "Settings"
local PANEL_SIZE = Vector2.new(400, 250)
local GEAR = 44 -- lado del botón a escala 1
local GEAR_EDGE = 16

local player = Players.LocalPlayer

local function buildPanel(playerGui: Instance)
	local existing = playerGui:FindFirstChild("SettingsHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "SettingsHud",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local panel, panelScale = UiKit.panel(screenGui, "SettingsPanel", PANEL_SIZE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.2))
	UiKit.text(panel, "Title", {
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -90, 0, 32),
		Font = FONTS.Display,
		TextSize = 28,
		Text = "⚙️ Ajustes",
	})
	local close = UiKit.button(panel, "Close", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = THEME.Inset,
		Text = "×",
	})

	-- Tamaño de la interfaz: [−]  90 %  [+]
	local row = UiKit.create("Frame", {
		Name = "HudScaleRow",
		Position = UDim2.fromOffset(22, 84),
		Size = UDim2.new(1, -44, 0, 60),
		BackgroundColor3 = THEME.Inset,
	}, panel)
	UiKit.corner(row, 10)
	UiKit.text(row, "Label", {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -190, 1, 0),
		Font = FONTS.Display,
		TextSize = 19,
		TextWrapped = true,
		Text = "Tamaño de la interfaz",
	})
	local minus = UiKit.button(row, "Smaller", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -124, 0.5, 0),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = THEME.Secondary,
		TextSize = 26,
		Text = "−",
	})
	local value = UiKit.text(row, "Value", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -60, 0.5, 0),
		Size = UDim2.fromOffset(62, 40),
		Font = FONTS.Display,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "100 %",
	})
	local plus = UiKit.button(row, "Bigger", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = THEME.Secondary,
		TextSize = 26,
		Text = "+",
	})
	UiKit.text(panel, "Hint", {
		Position = UDim2.fromOffset(22, 152),
		Size = UDim2.new(1, -44, 0, 40),
		Font = FONTS.Light,
		TextSize = 15,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = THEME.Muted,
		Text = "Más pequeño = ves más del juego. Se guarda con tu partida.",
	})
	local reset = UiKit.button(panel, "Reset", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(180, 38),
		BackgroundColor3 = THEME.Secondary,
		TextSize = 17,
		Text = "Normal (100 %)",
	})
	screenGui.Parent = playerGui
	return {
		ScreenGui = screenGui,
		Panel = panel,
		PanelScale = panelScale,
		Close = close,
		Minus = minus,
		Plus = plus,
		Value = value,
		Reset = reset,
	}
end

-- Engranaje: azulejo gris oscuro con contorno negro, como los del menú pero pequeño.
local function buildGear(playerGui: Instance): (TextButton, ScreenGui)
	local existing = playerGui:FindFirstChild("SettingsButtonHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "SettingsButtonHud",
		ResetOnSpawn = false,
		DisplayOrder = 4,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local gear = UiKit.create("TextButton", {
		Name = "SettingsButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, GEAR_EDGE, 1, -GEAR_EDGE),
		Size = UDim2.fromOffset(GEAR, GEAR),
		BackgroundColor3 = Color3.fromRGB(58, 61, 69),
		AutoButtonColor = true,
		Font = FONTS.Display,
		TextSize = 24,
		TextColor3 = THEME.Text,
		Text = "⚙️",
	}, screenGui)
	UiKit.corner(gear, 12)
	UiKit.shade(gear, Theme.Finish.ButtonShade)
	UiKit.stroke(gear, THEME.Outline, 3, 0)
	local scale = UiKit.create("UIScale", {}, gear)
	UiKit.bindScale(screenGui, { scale })
	screenGui.Parent = playerGui
	return gear, screenGui
end

function SettingsController.start()
	local playerGui = player:WaitForChild("PlayerGui")
	local ui = buildPanel(playerGui)
	local gear, gearGui = buildGear(playerGui)

	local function render()
		local current = UserScale.get()
		ui.Value.Text = SettingsLogic.hudScaleLabel(current)
		local list = SettingsLogic.HudScales
		UiKit.setDisabled(ui.Minus, current <= list[1])
		UiKit.setDisabled(ui.Plus, current >= list[#list])
		UiKit.setDisabled(ui.Reset, current == SettingsLogic.DefaultHudScale)
	end
	local function change(steps: number)
		local nextScale = SettingsLogic.stepHudScale(UserScale.get(), steps)
		if nextScale ~= UserScale.get() then
			UserScale.set(nextScale)
		end
	end
	ui.Minus.Activated:Connect(function()
		change(-1)
	end)
	ui.Plus.Activated:Connect(function()
		change(1)
	end)
	ui.Reset.Activated:Connect(function()
		UserScale.set(SettingsLogic.DefaultHudScale)
	end)
	UserScale.watch(render)
	render()

	PanelManager.register(PANEL_NAME, ui.Panel, { OnOpen = render })
	UiKit.bindModalLayout(ui.ScreenGui, ui.PanelScale, PANEL_SIZE, function(position)
		PanelManager.setBasePosition(PANEL_NAME, position)
	end)
	ui.Close.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
	end)
	gear.Activated:Connect(function()
		PanelManager.toggle(PANEL_NAME)
	end)

	-- Escritorio: esquina de abajo a la izquierda (libre). Táctil: ahí descansa el pulgar,
	-- así que va arriba en la columna izquierda del HUD (encima del seguimiento de misiones).
	local function place()
		local touch = HudDock.layout().Touch == true
		if touch then
			if gear.Parent ~= HudDock.column("Left") then
				HudDock.attach("Left", gear, 1)
			end
		elseif gear.Parent ~= gearGui then
			gear.Parent = gearGui
			gear.AnchorPoint = Vector2.new(0, 1)
			gear.Position = UDim2.new(0, GEAR_EDGE, 1, -GEAR_EDGE)
		end
	end
	HudDock.Changed:Connect(place)
	place()
end

return SettingsController
