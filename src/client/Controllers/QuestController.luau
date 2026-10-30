-- Interfaz de misiones y logros (solo presentación; el servidor decide todo):
-- - Azulejo "Misiones" en la barra del menú, con el número de recompensas listas.
-- - Bajo el menú, una línea de estado con la diaria más avanzada sin completar.
-- - Avisos (misión completada, logro, energía recibida) en la pila común (Toasts).
-- - Panel (PanelManager) con pestañas Diarias / Semanales / Misiones / Logros: progreso 3/5,
--   recompensa, botón "Reclamar" solo si el servidor la marca lista, "Completada" al
--   reclamar y logros bloqueados/desbloqueados.
-- - La energía solo se muestra como recibida cuando el servidor lo confirma (QuestResult
--   o un aviso de logro ya concedido).
-- - Tecla M para abrir y cerrar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local QuestConfig = require(Shared.Config.QuestConfig)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local MenuBar = require(script.Parent.Parent.UI.MenuBar)
local Toasts = require(script.Parent.Parent.UI.Toasts)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local PANEL_NAME = "Quests"
local PANEL_SIZE = Vector2.new(600, 440)
local TURQUOISE = Color3.fromRGB(110, 236, 220)
local VIOLET = Color3.fromRGB(190, 120, 255)

local MESSAGES = {
	NotComplete = "Aún no has completado este objetivo.",
	AlreadyClaimed = "Ya reclamaste esta recompensa.",
	Locked = "Necesitas desbloquear otra zona primero.",
	TooFast = "Espera un momento.",
	NotReady = "Tus datos aún se están cargando.",
	InvalidRequest = "Esta misión ya no está disponible.",
}

local definitions: { [string]: any } = {}
for _, list in { QuestConfig.Missions, QuestConfig.Daily, QuestConfig.Weekly or {}, QuestConfig.Achievements } do
	for _, def in list do
		definitions[def.Id] = def
	end
end
if QuestConfig.WeeklyChest then
	definitions[QuestConfig.WeeklyChest.Id] = QuestConfig.WeeklyChest -- el cofre de la semana
end

local QuestController = {}

local player = Players.LocalPlayer

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("QuestsHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "QuestsHud",
		ResetOnSpawn = false,
		DisplayOrder = 5, -- como los demás paneles modales
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)

	-- Panel ------------------------------------------------------------------------
	local panel, panelScale = UiKit.panel(screenGui, "QuestPanel", PANEL_SIZE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.2))
	UiKit.text(panel, "Title", {
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -90, 0, 32),
		Font = FONTS.Display,
		TextSize = 28,
		Text = "Misiones",
	})
	local subtitle = UiKit.text(panel, "Subtitle", {
		Position = UDim2.fromOffset(22, 48),
		Size = UDim2.new(1, -90, 0, 20),
		Font = FONTS.Light,
		TextSize = 16,
		TextColor3 = THEME.Muted,
	})
	local close = UiKit.button(panel, "Close", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = THEME.Inset,
		Text = "×",
	})
	local tabsRow = UiKit.create("Frame", {
		Name = "Tabs",
		Position = UDim2.fromOffset(22, 78),
		Size = UDim2.new(1, -44, 0, 36),
		BackgroundTransparency = 1,
	}, panel)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tabsRow)
	local tabs = {}
	for order, spec in { { "Daily", "Diarias" }, { "Weekly", "Semanales" }, { "Missions", "Misiones" }, { "Achievements", "Logros" } } do
		local tab = UiKit.button(tabsRow, spec[1], {
			Size = UDim2.fromOffset(130, 36),
			BackgroundColor3 = THEME.Inset,
			TextSize = 17,
			Text = spec[2],
			LayoutOrder = order,
		})
		tabs[spec[1]] = tab
	end
	local list = UiKit.create("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(22, 124),
		Size = UDim2.new(1, -44, 1, -164),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = THEME.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, panel)
	UiKit.create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)
	local feedback = UiKit.text(panel, "Feedback", {
		Position = UDim2.new(0, 22, 1, -34),
		Size = UDim2.new(1, -44, 0, 24),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	screenGui.Parent = playerGui
	return {
		ScreenGui = screenGui,
		Panel = panel,
		PanelScale = panelScale,
		Subtitle = subtitle,
		Close = close,
		Tabs = tabs,
		List = list,
		Feedback = feedback,
	}
end

-- Fila de una misión (o logro).
local function buildRow(parent: Instance, order: number, entry: any, isAchievement: boolean, onClaim: (string, TextButton) -> (), pending: { [string]: boolean })
	local def = definitions[entry.Id]
	if not def then
		return
	end
	local status = entry.Status
	local done = if isAchievement then entry.Unlocked else (status == "Ready" or status == "Claimed")
	local locked = status == "Locked"
	local accent = if isAchievement then VIOLET else TURQUOISE

	local row = UiKit.create("Frame", {
		Name = entry.Id,
		Size = UDim2.new(1, -10, 0, 78),
		BackgroundColor3 = THEME.Inset,
		BackgroundTransparency = if locked then 0.45 else 0.1,
		LayoutOrder = order,
	}, parent)
	UiKit.corner(row, 12)
	if done then
		UiKit.stroke(row, if isAchievement then VIOLET else THEME.Gold, 1.5, 0.35)
	end
	local icon = if isAchievement then (if done then "🏆" else "🔒") elseif locked then "🔒" elseif status == "Claimed" then "✓" else "★"
	UiKit.text(row, "Title", {
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -170, 0, 22),
		Font = FONTS.Display,
		TextSize = 18,
		TextColor3 = if locked then THEME.Muted else THEME.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = icon .. "  " .. def.Title,
	})
	UiKit.text(row, "Description", {
		Position = UDim2.fromOffset(14, 31),
		Size = UDim2.new(1, -170, 0, 18),
		Font = FONTS.Light,
		TextSize = 14,
		TextColor3 = THEME.Muted,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = if locked then "Desbloquea el Valle Cristalino para empezar." else def.Description,
	})
	-- Barra de progreso con "3/5"
	local track = UiKit.create("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(14, 55),
		Size = UDim2.new(1, -250, 0, 12),
		BackgroundColor3 = THEME.Overlay,
		BackgroundTransparency = 0.3,
	}, row)
	UiKit.corner(track, 6)
	local ratio = if entry.Target > 0 then math.clamp(entry.Progress / entry.Target, 0, 1) else 0
	local fill = UiKit.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(ratio, 1),
		BackgroundColor3 = if done then THEME.Gold else accent,
		Visible = ratio > 0,
	}, track)
	UiKit.corner(fill, 6)
	UiKit.text(row, "Count", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -164, 0, 51),
		Size = UDim2.fromOffset(80, 20),
		Font = FONTS.Body,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = formatNumber(math.floor(entry.Progress)) .. "/" .. formatNumber(entry.Target),
	})
	-- Recompensa y acción
	local rewardText = if entry.Reward and entry.Reward > 0 then "+" .. formatNumber(entry.Reward) .. " 💎" else "Insignia"
	UiKit.text(row, "Reward", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.fromOffset(140, 22),
		Font = FONTS.Display,
		TextSize = 17,
		TextColor3 = THEME.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = rewardText,
	})
	if isAchievement then
		UiKit.text(row, "State", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -12, 1, -10),
			Size = UDim2.fromOffset(140, 22),
			Font = FONTS.Body,
			TextSize = 15,
			TextColor3 = if done then VIOLET else THEME.Muted,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = if done then "Desbloqueado" else "Bloqueado",
		})
		return
	end
	if status == "Ready" then
		local claimButton = UiKit.button(row, "Claim", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -12, 1, -8),
			Size = UDim2.fromOffset(130, 34),
			BackgroundColor3 = THEME.Buy,
			TextSize = 17,
			Text = if pending[entry.Id] then "…" else "Reclamar",
		})
		UiKit.setDisabled(claimButton, pending[entry.Id] == true)
		UiKit.shimmer(claimButton, 10)(pending[entry.Id] ~= true)
		claimButton.Activated:Connect(function()
			onClaim(entry.Id, claimButton)
		end)
	else
		UiKit.text(row, "State", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -12, 1, -10),
			Size = UDim2.fromOffset(140, 22),
			Font = FONTS.Body,
			TextSize = 15,
			TextColor3 = if status == "Claimed" then THEME.Accent else THEME.Muted,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = if status == "Claimed" then "Completada" elseif locked then "Bloqueada" else "En curso",
		})
	end
end

function QuestController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local requestRemote = remotes:WaitForChild(Constants.Remotes.RequestQuests) :: RemoteEvent
	local stateRemote = remotes:WaitForChild(Constants.Remotes.QuestState) :: RemoteEvent
	local claimRemote = remotes:WaitForChild(Constants.Remotes.ClaimQuest) :: RemoteEvent
	local resultRemote = remotes:WaitForChild(Constants.Remotes.QuestResult) :: RemoteEvent

	local ui = buildGui()
	local state: any = { Ready = false, Missions = {}, Daily = {}, Weekly = {}, Achievements = {} }
	local tab = "Daily"
	local pending: { [string]: boolean } = {}

	local menuEntry = MenuBar.add({
		Id = "Quests",
		Order = 2,
		Icon = "📜",
		Label = "Misiones",
		Key = "M",
		Color = Color3.fromRGB(236, 200, 120),
		Panels = { PANEL_NAME },
		OnActivate = function()
			PanelManager.toggle(PANEL_NAME)
		end,
	})
	local statusLine = MenuBar.status("Quests", 1)
	local function notify(text: string, color: Color3)
		Toasts.show(text, { Color = color })
	end

	local feedbackToken = 0
	local function setFeedback(text: string, color: Color3)
		feedbackToken += 1
		local token = feedbackToken
		ui.Feedback.Text = text
		ui.Feedback.TextColor3 = color
		task.delay(3, function()
			if feedbackToken == token then
				ui.Feedback.Text = ""
			end
		end)
	end

	-- Render -----------------------------------------------------------------------
	local function claim(questId: string, button: TextButton)
		if pending[questId] then
			return
		end
		pending[questId] = true
		button.Text = "…"
		UiKit.setDisabled(button, true)
		claimRemote:FireServer(questId) -- solo el Id: la recompensa la decide el servidor
		-- Si no llega respuesta, se puede volver a intentar (el servidor nunca paga dos veces).
		task.delay(5, function()
			pending[questId] = nil
		end)
	end

	local function countdown(): string
		local remaining = math.max(0, (state.ResetAt or 0) - Workspace:GetServerTimeNow())
		local hours = math.floor(remaining / 3600)
		local minutes = math.floor((remaining % 3600) / 60)
		return ("Nuevas diarias en %d h %02d min"):format(hours, minutes)
	end
	local function weekCountdown(): string
		local remaining = math.max(0, (state.WeekResetAt or 0) - Workspace:GetServerTimeNow())
		local days = math.floor(remaining / 86400)
		local hours = math.floor((remaining % 86400) / 3600)
		return ("Retos de la semana · nuevos en %d d %d h · reclama los 3 y abre el 🎁 cofre"):format(days, hours)
	end

	local function renderList()
		for _, child in ui.List:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for name, button in ui.Tabs do
			button.BackgroundColor3 = if name == tab then THEME.Buy else THEME.Inset
		end
		if not state.Ready then
			local failed = player:GetAttribute(Constants.Attributes.DataStatus) == "Failed"
			ui.Subtitle.Text = if failed
				then "No se pudieron cargar tus misiones. Tus datos guardados están a salvo: vuelve a entrar más tarde."
				else "Cargando tus misiones…"
			return
		end
		if tab == "Daily" then
			ui.Subtitle.Text = countdown()
		elseif tab == "Weekly" then
			ui.Subtitle.Text = weekCountdown()
		elseif tab == "Missions" then
			ui.Subtitle.Text = "Objetivos permanentes: cada recompensa se reclama una vez"
		else
			local unlocked = 0
			for _, entry in state.Achievements do
				unlocked += if entry.Unlocked then 1 else 0
			end
			ui.Subtitle.Text = ("Logros desbloqueados: %d/%d"):format(unlocked, #state.Achievements)
		end
		local entries = state[tab] or {}
		for order, entry in entries do
			buildRow(ui.List, order, entry, tab == "Achievements", claim, pending)
		end
	end

	local function refreshHud()
		local ready = 0
		for _, list in { state.Missions or {}, state.Daily or {}, state.Weekly or {} } do
			for _, entry in list do
				if entry.Status == "Ready" then
					ready += 1
				end
			end
		end
		menuEntry.setBadge(if ready > 0 then tostring(ready) else nil)
		-- Diaria más avanzada aún en curso (o la siguiente misión) en una sola línea.
		local best, bestRatio = nil, -1
		for _, entry in state.Daily or {} do
			local ratio = entry.Progress / math.max(entry.Target, 1)
			if entry.Status == "Active" and ratio > bestRatio then
				best, bestRatio = entry, ratio
			end
		end
		if best and definitions[best.Id] then
			statusLine.Text = ("📜 %s  %s/%s"):format(definitions[best.Id].Title, formatNumber(math.floor(best.Progress)), formatNumber(best.Target))
			statusLine.TextColor3 = THEME.Text
		elseif ready > 0 then
			statusLine.Text = "📜 ¡Recompensas listas!"
			statusLine.TextColor3 = THEME.Gold
		else
			statusLine.Text = ""
		end
	end

	-- Estado del servidor -----------------------------------------------------------------
	stateRemote.OnClientEvent:Connect(function(data)
		if typeof(data) ~= "table" then
			return
		end
		if data.Ready ~= true then
			state = { Ready = false, Missions = {}, Daily = {}, Weekly = {}, Achievements = {} }
			refreshHud()
			if PanelManager.isOpen(PANEL_NAME) then
				renderList()
			end
			return
		end
		state = data
		-- Avisos de cosas ya hechas en el servidor (los logros con energía ya la sumaron).
		if typeof(data.Notices) == "table" then
			for _, notice in data.Notices do
				local def = typeof(notice) == "table" and definitions[notice.Id]
				if def then
					if notice.Type == "Achievement" then
						local reward = if typeof(notice.Reward) == "number" and notice.Reward > 0 then ("  +%s 💎"):format(formatNumber(notice.Reward)) else ""
						notify("🏆 Logro: " .. def.Title .. reward, VIOLET)
					elseif notice.Type == "Daily" then
						notify("★ Diaria completada: " .. def.Title .. " — ¡reclámala!", TURQUOISE)
					elseif notice.Type == "Weekly" then
						notify("🏅 Reto semanal completado: " .. def.Title .. " — ¡reclámalo!", THEME.Gold)
					else
						notify("★ Misión completada: " .. def.Title .. " — ¡reclámala!", TURQUOISE)
					end
				end
			end
		end
		refreshHud()
		if PanelManager.isOpen(PANEL_NAME) then
			renderList()
		end
	end)

	resultRemote.OnClientEvent:Connect(function(success: boolean, code: string, questId: string?, amount: number?)
		if typeof(questId) == "string" then
			pending[questId] = nil
		end
		if success then
			local def = typeof(questId) == "string" and definitions[questId]
			local text = ("+%s 💎"):format(formatNumber(if typeof(amount) == "number" then amount else 0))
			setFeedback(("¡Recompensa recibida! %s"):format(text), THEME.BuyHighlight)
			notify(("💎 %s  %s"):format(if def then def.Title else "Recompensa", text), THEME.Gold)
		else
			setFeedback(MESSAGES[code] or tostring(code), THEME.Error)
			if PanelManager.isOpen(PANEL_NAME) then
				renderList() -- quita el "…" del botón
			end
		end
	end)

	-- Navegación ---------------------------------------------------------------------
	-- Cuenta atrás de las diarias: solo mientras el panel está abierto (se corta al cerrar).
	local openToken = 0
	PanelManager.register(PANEL_NAME, ui.Panel, {
		OnOpen = function()
			requestRemote:FireServer()
			renderList()
			openToken += 1
			local token = openToken
			task.spawn(function()
				while openToken == token do
					task.wait(15)
					if openToken == token and tab == "Daily" and state.Ready then
						ui.Subtitle.Text = countdown()
					end
				end
			end)
		end,
		OnClose = function()
			openToken += 1
		end,
	})
	UiKit.bindModalLayout(ui.ScreenGui, ui.PanelScale, PANEL_SIZE, function(position)
		PanelManager.setBasePosition(PANEL_NAME, position)
	end)
	for name, button in ui.Tabs do
		button.Activated:Connect(function()
			tab = name
			renderList()
		end)
	end
	ui.Close.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.M then
			PanelManager.toggle(PANEL_NAME)
		end
	end)

	-- Al cambiar el estado de los datos (cargados o error), se actualiza lo que se ve.
	player:GetAttributeChangedSignal(Constants.Attributes.DataStatus):Connect(function()
		if PanelManager.isOpen(PANEL_NAME) then
			renderList()
		end
	end)

	requestRemote:FireServer()
end

return QuestController
