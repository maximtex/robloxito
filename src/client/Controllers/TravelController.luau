-- 🗺️ Viajar: llegar rápido a cualquier zona abierta (pruebas con amigos: "un botón para
-- teletransportarse a las zonas"). Botón pequeño encima del ⚙️ (abajo a la izquierda en
-- escritorio; en la columna izquierda en táctil) y tecla O. El panel lista las zonas del Mundo 1
-- en orden (ZoneConfig.TravelOrder): las abiertas con "Ir", la tuya con 📍 y las cerradas con lo que
-- falta. El viaje lo decide el servidor (FastTravel -> ZoneService.fastTravel): solo a zonas
-- abiertas, fuera de una partida de oleadas y como mucho uno cada FastTravelCooldown s.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudDock = require(script.Parent.Parent.UI.HudDock)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local Toasts = require(script.Parent.Parent.UI.Toasts)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local Codes = Constants.PurchaseCodes

local TravelController = {}

local PANEL_NAME = "Travel"
local PANEL_SIZE = Vector2.new(460, 500)
local ROW_HEIGHT = 58
local SIZE = 44 -- lado del botón a escala 1 (como el ⚙️)
local EDGE = 16
local ACTION = "RebirthTravel"

local ICONS = { Forest = "🏡", ThornWoods = "🌲", CrystalValley = "💎", EmberCaldera = "🌋", FrozenTundra = "❄️", GoblinFortress = "🏰" }
local SUBTITLES = {
	Forest = "Pueblo · el spawn",
	ThornWoods = "Zona 1",
	CrystalValley = "Zona 2",
	EmberCaldera = "Zona 3",
	FrozenTundra = "Zona 4",
	GoblinFortress = "Zona 5",
}
local ERRORS = {
	[Codes.InWave] = "🌊 Termina la partida de oleadas primero",
	[Codes.TooFast] = "⏳ Espera un momento para volver a viajar",
	[Codes.ZoneLocked] = "🔒 Esa zona aún está cerrada",
	[Codes.BossLocked] = "🔒 Esa zona aún está cerrada",
	[Codes.NotReady] = "Cargando tus datos, inténtalo de nuevo",
	[Codes.Busy] = "Ya estás viajando",
}

local player = Players.LocalPlayer

-- Como ZoneLogic.isUnlocked: comprada, o sin precio (si pide un jefe, derrotado). En Studio con
-- DevConfig.StudioAllZones (atributo DevAllZones), todas.
local function isUnlocked(zoneId: string): boolean
	if player:GetAttribute(Constants.Attributes.DevAllZones) == true then
		return true
	end
	local zone = ZoneConfig.Zones[zoneId]
	local value = player:GetAttribute(Constants.Attributes.UnlockedZones)
	if typeof(value) == "string" and table.find(string.split(value, ","), zoneId) ~= nil then
		return true
	end
	if zone and (zone.UnlockCost or 0) <= 0 then
		if not zone.RequiredBoss then
			return true
		end
		local defeated = player:GetAttribute(Constants.Attributes.BossesDefeated)
		return typeof(defeated) == "string" and table.find(string.split(defeated, ","), zone.RequiredBoss) ~= nil
	end
	return false
end

-- Lo que falta para abrir una zona cerrada
local function lockedText(zoneId: string): string
	local zone = ZoneConfig.Zones[zoneId]
	local bossId = zone and zone.RequiredBoss
	local defeated = player:GetAttribute(Constants.Attributes.BossesDefeated)
	if bossId and not (typeof(defeated) == "string" and table.find(string.split(defeated, ","), bossId)) then
		local boss = EnemyConfig.Types[bossId]
		return "🔒 Derrota al " .. (if boss then boss.DisplayName else bossId)
	end
	if zone and (zone.UnlockCost or 0) > 0 then
		return ("🔒 Ábrela en su puerta (💰 %s)"):format(formatNumber(zone.UnlockCost))
	end
	return "🔒 Cerrada"
end

local function buildPanel(playerGui: Instance)
	local existing = playerGui:FindFirstChild("TravelHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "TravelHud",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local panel, panelScale = UiKit.panel(screenGui, "TravelPanel", PANEL_SIZE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.12))
	UiKit.text(panel, "Title", {
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -90, 0, 32),
		Font = FONTS.Display,
		TextSize = 28,
		Text = "🗺️ Viajar",
	})
	UiKit.text(panel, "Hint", {
		Position = UDim2.fromOffset(22, 48),
		Size = UDim2.new(1, -44, 0, 20),
		Font = FONTS.Light,
		TextSize = 14,
		TextColor3 = THEME.Muted,
		Text = "Ve al instante a cualquier zona del Mundo 1 que ya hayas abierto.",
	})
	local close = UiKit.button(panel, "Close", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = THEME.Inset,
		Text = "×",
	})
	local list = UiKit.create("ScrollingFrame", {
		Name = "Zones",
		Position = UDim2.fromOffset(18, 78),
		Size = UDim2.new(1, -36, 1, -92),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = THEME.Muted,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, panel)
	UiKit.create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, list)
	UiKit.create("UIPadding", { PaddingRight = UDim.new(0, 8) }, list)

	local rows = {}
	for order, zoneId in ZoneConfig.TravelOrder do
		local zone = ZoneConfig.Zones[zoneId]
		if not zone then
			continue
		end
		local row = UiKit.create("Frame", {
			Name = zoneId,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			BackgroundColor3 = THEME.Inset,
		}, list)
		UiKit.corner(row, 10)
		UiKit.text(row, "Icon", {
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.fromOffset(40, ROW_HEIGHT),
			Font = FONTS.Display,
			TextSize = 26,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = ICONS[zoneId] or "📍",
		})
		local name = UiKit.text(row, "Name", {
			Position = UDim2.fromOffset(54, 7),
			Size = UDim2.new(1, -180, 0, 22),
			Font = FONTS.Display,
			TextSize = 19,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = zone.DisplayName,
		})
		local sub = UiKit.text(row, "Sub", {
			Position = UDim2.fromOffset(54, 31),
			Size = UDim2.new(1, -180, 0, 18),
			Font = FONTS.Light,
			TextSize = 13,
			TextColor3 = THEME.Muted,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local go = UiKit.button(row, "Go", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(112, 40),
			TextSize = 17,
			Text = "Ir",
		})
		rows[zoneId] = { Frame = row, Name = name, Sub = sub, Go = go }
	end
	screenGui.Parent = playerGui
	return { ScreenGui = screenGui, Panel = panel, PanelScale = panelScale, Close = close, Rows = rows }
end

-- Botón 🗺️: azulejo gris oscuro con contorno, como el ⚙️
local function buildButton(playerGui: Instance): (TextButton, ScreenGui)
	local existing = playerGui:FindFirstChild("TravelButtonHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "TravelButtonHud",
		ResetOnSpawn = false,
		DisplayOrder = 4,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local button = UiKit.create("TextButton", {
		Name = "TravelButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, EDGE, 1, -(EDGE + SIZE + 10)),
		Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundColor3 = Color3.fromRGB(46, 112, 150),
		AutoButtonColor = true,
		Font = FONTS.Display,
		TextSize = 24,
		TextColor3 = THEME.Text,
		Text = "🗺️",
	}, screenGui)
	UiKit.corner(button, 12)
	UiKit.shade(button, Theme.Finish.ButtonShade)
	UiKit.stroke(button, THEME.Outline, 3, 0)
	local keyLabel = UiKit.text(button, "Key", {
		Position = UDim2.fromOffset(-2, -4),
		Size = UDim2.fromOffset(16, 16),
		Font = FONTS.Display,
		TextSize = 13,
		Text = "O",
		ZIndex = 3,
	})
	UiKit.outline(keyLabel, 1.5)
	local scale = UiKit.create("UIScale", {}, button)
	UiKit.bindScale(screenGui, { scale })
	screenGui.Parent = playerGui
	return button, screenGui
end

function TravelController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local travelRemote = remotes:WaitForChild(Constants.Remotes.FastTravel) :: RemoteEvent
	local resultRemote = remotes:WaitForChild(Constants.Remotes.TravelResult) :: RemoteEvent
	local playerGui = player:WaitForChild("PlayerGui")
	local ui = buildPanel(playerGui)
	local button, buttonGui = buildButton(playerGui)
	local pending = false

	local function setGo(go: TextButton, text: string, color: Color3, disabled: boolean)
		go.Text = text
		go.BackgroundColor3 = if disabled then THEME.Disabled else color
		UiKit.setDisabled(go, disabled)
	end

	local function render()
		local current = player:GetAttribute(Constants.Attributes.CurrentZone)
		for zoneId, row in ui.Rows do
			local open = isUnlocked(zoneId)
			-- Las cerradas también salen (con su candado y lo que falta), pero no se puede ir
			row.Frame.BackgroundTransparency = if open or current == zoneId then 0 else 0.45
			row.Name.TextColor3 = if open or current == zoneId then THEME.Text else THEME.Muted
			if current == zoneId then
				row.Sub.Text = (SUBTITLES[zoneId] or "") .. " · estás aquí"
				setGo(row.Go, "📍 Aquí", THEME.Inset, true)
			elseif open then
				row.Sub.Text = SUBTITLES[zoneId] or ""
				setGo(row.Go, if pending then "…" else "✨ Ir", THEME.Buy, pending)
			else
				row.Sub.Text = (SUBTITLES[zoneId] or "") .. " · " .. lockedText(zoneId)
				setGo(row.Go, "🔒 Cerrada", THEME.Disabled, true)
			end
		end
	end

	local function go(zoneId: string)
		if pending or not isUnlocked(zoneId) or player:GetAttribute(Constants.Attributes.CurrentZone) == zoneId then
			return
		end
		pending = true
		render()
		local zone = ZoneConfig.Zones[zoneId]
		Toasts.show(("✨ Viajando a %s…"):format(if zone then zone.DisplayName else zoneId), { Color = Color3.fromRGB(150, 220, 255), Key = "Travel" })
		travelRemote:FireServer(zoneId)
		task.delay(6, function() -- por si no llega la respuesta
			if pending then
				pending = false
				render()
			end
		end)
	end
	for zoneId, row in ui.Rows do
		row.Go.Activated:Connect(function()
			go(zoneId)
		end)
	end
	resultRemote.OnClientEvent:Connect(function(success: any, code: any, _zoneId: any, fast: any)
		if fast ~= true then
			return -- (los de los portales los atiende PortalController)
		end
		pending = false
		if success == true then
			PanelManager.close(PANEL_NAME)
		else
			Toasts.show(ERRORS[code] or "No se pudo viajar", { Color = THEME.Error, Key = "Travel" })
		end
		render()
	end)

	PanelManager.register(PANEL_NAME, ui.Panel, { OnOpen = render })
	UiKit.bindModalLayout(ui.ScreenGui, ui.PanelScale, PANEL_SIZE, function(position)
		PanelManager.setBasePosition(PANEL_NAME, position)
	end)
	ui.Close.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
	end)
	button.Activated:Connect(function()
		PanelManager.toggle(PANEL_NAME)
	end)
	ContextActionService:BindAction(ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			PanelManager.toggle(PANEL_NAME)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.O)
	for _, attribute in { Constants.Attributes.UnlockedZones, Constants.Attributes.BossesDefeated, Constants.Attributes.CurrentZone, Constants.Attributes.DevAllZones } do
		player:GetAttributeChangedSignal(attribute):Connect(render)
	end
	render()

	-- Escritorio: encima del ⚙️ (abajo a la izquierda). Táctil: en la columna izquierda.
	local function place()
		local keyLabel = button:FindFirstChild("Key")
		if keyLabel and keyLabel:IsA("GuiObject") then
			keyLabel.Visible = UserInputService.KeyboardEnabled
		end
		if HudDock.layout().Touch == true then
			if button.Parent ~= HudDock.column("Left") then
				HudDock.attach("Left", button, 3)
			end
		elseif button.Parent ~= buttonGui then
			button.Parent = buttonGui
			button.AnchorPoint = Vector2.new(0, 1)
			button.Position = UDim2.new(0, EDGE, 1, -(EDGE + SIZE + 10))
		end
	end
	HudDock.Changed:Connect(place)
	UserInputService.LastInputTypeChanged:Connect(place)
	place()
end

return TravelController
