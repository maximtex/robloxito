-- Interfaz de los núcleos elementales (solo presentación; el servidor decide todo):
-- - Azulejo "Núcleos" en la barra del menú (o tecla N) y aviso en cada altar del
--   Círculo Elemental ("Ver núcleo") que abre el panel con ese núcleo resaltado.
-- - Panel (PanelManager) con los ocho núcleos: despertar, mejorar y elegir el elemento
--   activo (afinidad), con costes, producción y nivel que envía el servidor (CoreState).
--   Naturaleza es el cristal: su "Mejorar" es la Resonancia del Cristal (PurchaseUpgrade).
--   Dos huecos: ★ Q (principal, con afinidad) y ◆ R (secundario). Cada fila muestra la
--   habilidad del elemento con sus números reales y los combos en los que participa.
-- - Aviso de bienvenida (pila común de avisos) con la producción offline concedida al
--   entrar (atributo OfflineReward, una vez por sesión).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local CoreConfig = require(Shared.Config.CoreConfig)
local CoreShrineConfig = require(Shared.Config.CoreShrineConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local formatNumber = require(Shared.Util.FormatNumber)
local AbilityLogic = require(Shared.AbilityLogic)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local MenuBar = require(script.Parent.Parent.UI.MenuBar)
local Toasts = require(script.Parent.Parent.UI.Toasts)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local Codes = Constants.PurchaseCodes

local PANEL_NAME = "Cores"
local PANEL_SIZE = Vector2.new(660, 520)
local ROW_HEIGHT = 110 -- nombre, detalle, habilidad del elemento y sus combos
local TOAST_SECONDS = 9
local NATURE_UPGRADE_ID = CoreConfig.Elements[CoreConfig.DefaultElement].UpgradeId

local MESSAGES = {
	[Codes.InsufficientEnergy] = "Te falta energía.",
	[Codes.Locked] = "Despierta antes los núcleos anteriores.",
	[Codes.AlreadyUnlocked] = "Ese núcleo ya está despierto.",
	[Codes.AlreadySelected] = "Ese elemento ya está en ese hueco.",
	[Codes.TooFast] = "Espera un momento antes de volver a cambiar.",
	[Codes.NotReady] = "Tus datos aún se están cargando.",
	[Codes.MaxLevel] = "Ese núcleo ya está al nivel máximo.",
	[Codes.InvalidRequest] = "Esa acción no está disponible.",
}

local CoreController = {}

local player = Players.LocalPlayer

local function elementName(elementId: string): string
	local element = CoreConfig.Elements[elementId]
	return if element then element.DisplayName else elementId
end

local function elementColor(elementId: string): Color3
	if elementId == CoreConfig.DefaultElement then
		return GeneratorConfig.Colors.Turquoise
	end
	local look = CoreShrineConfig.Elements[elementId]
	return if look then look.Color else THEME.Accent
end

local function formatDuration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	if hours > 0 then
		return ("%d h %d min"):format(hours, minutes)
	elseif minutes > 0 then
		return ("%d min"):format(minutes)
	end
	return ("%d s"):format(seconds)
end

local function energy(): number
	local value = player:GetAttribute(Constants.Attributes.Energy)
	return if typeof(value) == "number" then value else 0
end

-- Construcción --------------------------------------------------------------------------

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("CoresHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "CoresHud",
		ResetOnSpawn = false,
		DisplayOrder = 5, -- como los demás paneles modales
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)

	-- Panel ----------------------------------------------------------------------------
	local panel, panelScale = UiKit.panel(screenGui, "CorePanel", PANEL_SIZE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.2))
	UiKit.text(panel, "Title", {
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -90, 0, 32),
		Font = FONTS.Display,
		TextSize = 28,
		Text = "Núcleos elementales",
	})
	local subtitle = UiKit.text(panel, "Subtitle", {
		Position = UDim2.fromOffset(22, 48),
		Size = UDim2.new(1, -90, 0, 20),
		Font = FONTS.Light,
		TextSize = 15,
		TextColor3 = THEME.Muted,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local close = UiKit.button(panel, "Close", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = THEME.Inset,
		Text = "×",
	})
	local hint = UiKit.text(panel, "Hint", {
		Position = UDim2.fromOffset(22, 72),
		Size = UDim2.new(1, -44, 0, 34),
		Font = FONTS.Light,
		TextSize = 14,
		TextColor3 = THEME.Gold,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
	})
	local list = UiKit.create("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(22, 112),
		Size = UDim2.new(1, -44, 1, -152),
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
	UiKit.create("UIPadding", { PaddingRight = UDim.new(0, 10) }, list)
	local feedback = UiKit.text(panel, "Feedback", {
		Position = UDim2.new(0, 22, 1, -34),
		Size = UDim2.new(1, -44, 0, 24),
		Font = FONTS.Body,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	screenGui.Parent = playerGui
	return {
		ScreenGui = screenGui,
		Panel = panel,
		PanelScale = panelScale,
		Subtitle = subtitle,
		Hint = hint,
		Close = close,
		List = list,
		Feedback = feedback,
	}
end

-- Controlador ---------------------------------------------------------------------------

type RowButton = { Button: TextButton, Cost: number?, Enabled: boolean, Shimmer: (boolean) -> () }

function CoreController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local requestRemote = remotes:WaitForChild(Constants.Remotes.RequestCores) :: RemoteEvent
	local stateRemote = remotes:WaitForChild(Constants.Remotes.CoreState) :: RemoteEvent
	local actionRemote = remotes:WaitForChild(Constants.Remotes.CoreAction) :: RemoteEvent
	local resultRemote = remotes:WaitForChild(Constants.Remotes.CoreResult) :: RemoteEvent
	local purchaseRemote = remotes:WaitForChild(Constants.Remotes.PurchaseUpgrade) :: RemoteEvent
	local purchaseResult = remotes:WaitForChild(Constants.Remotes.PurchaseResult) :: RemoteEvent

	local ui = buildGui()
	local state: any = nil
	local highlight: string? = nil
	local rowButtons: { RowButton } = {}
	local rowFrames: { [string]: Frame } = {}
	local pendingNature = false
	local feedbackToken = 0

	MenuBar.add({
		Id = "Cores",
		Order = 3,
		Icon = "✨",
		Label = "Núcleos",
		Key = "N",
		Color = GeneratorConfig.Colors.Turquoise,
		Panels = { PANEL_NAME },
		OnActivate = function()
			PanelManager.toggle(PANEL_NAME)
		end,
	})

	local function setFeedback(text: string, color: Color3)
		feedbackToken += 1
		local token = feedbackToken
		ui.Feedback.Text = text
		ui.Feedback.TextColor3 = color
		task.delay(4, function()
			if feedbackToken == token then
				ui.Feedback.Text = ""
			end
		end)
	end

	-- Botones según la energía actual (sin reconstruir las filas cada segundo).
	local function refreshAffordability()
		local current = energy()
		for _, entry in rowButtons do
			local affordable = entry.Enabled and (entry.Cost == nil or current >= entry.Cost)
			entry.Button.BackgroundColor3 = if affordable then THEME.Buy else THEME.Disabled
			entry.Button.TextColor3 = if affordable then THEME.Text else THEME.Muted
			UiKit.setDisabled(entry.Button, not affordable)
			entry.Shimmer(affordable)
		end
	end

	local function addButton(parent: Instance, name: string, text: string, width: number, cost: number?, enabled: boolean, onClick: () -> ()): TextButton
		local button = UiKit.button(parent, name, {
			Size = UDim2.fromOffset(width, 34),
			TextSize = 15,
			Text = text,
			LayoutOrder = #parent:GetChildren(),
		})
		local entry: RowButton = { Button = button, Cost = cost, Enabled = enabled, Shimmer = UiKit.shimmer(button, 10) }
		table.insert(rowButtons, entry)
		button.Activated:Connect(function()
			if button:GetAttribute("Disabled") == true then
				if entry.Enabled and entry.Cost and energy() < entry.Cost then
					setFeedback(("Te falta energía: necesitas ⚡ %s."):format(formatNumber(entry.Cost)), THEME.Error)
				end
				return
			end
			onClick()
		end)
		return button
	end

	local function badge(parent: Instance, text: string, color: Color3, width: number)
		local frame = UiKit.create("Frame", {
			Name = "Badge",
			Size = UDim2.fromOffset(width, 34),
			BackgroundColor3 = THEME.Panel,
			LayoutOrder = #parent:GetChildren(),
		}, parent)
		UiKit.corner(frame, 10)
		UiKit.stroke(frame, color, 1.5, 0.1)
		UiKit.text(frame, "Text", {
			Size = UDim2.fromScale(1, 1),
			Font = FONTS.Display,
			TextSize = 15,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = text,
		})
	end

	local function buildRow(order: number, element: any, previous: any?)
		local id = element.Id
		local isDefault = id == CoreConfig.DefaultElement
		local selected = state.Selected == id
		local color = elementColor(id)

		local row = UiKit.create("Frame", {
			Name = id,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			BackgroundColor3 = THEME.Inset,
			LayoutOrder = order,
		}, ui.List)
		UiKit.corner(row, 12)
		local rowStroke = UiKit.stroke(row, if selected then THEME.Gold else color, if selected then 2 else 1, if selected then 0 elseif element.Unlocked then 0.6 else 0.9)
		rowFrames[id] = row
		if highlight == id then
			rowStroke.Color = THEME.Gold
			rowStroke.Thickness = 3
			rowStroke.Transparency = 0
			TweenService:Create(rowStroke, TweenInfo.new(1.6), {
				Thickness = if selected then 2 else 1,
				Transparency = if selected then 0 elseif element.Unlocked then 0.6 else 0.9,
				Color = if selected then THEME.Gold else color,
			}):Play()
		end

		-- Orbe del elemento
		local orb = UiKit.create("Frame", {
			Name = "Orb",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 14, 0.5, 0),
			Size = UDim2.fromOffset(44, 44),
			BackgroundColor3 = if element.Unlocked then color else Color3.fromRGB(110, 112, 118),
		}, row)
		UiKit.corner(orb, 22)
		UiKit.shade(orb, 0.6)
		UiKit.stroke(orb, if element.Unlocked then color:Lerp(Color3.new(1, 1, 1), 0.5) else THEME.Disabled, 2, 0.2)
		UiKit.text(orb, "Mark", {
			Size = UDim2.fromScale(1, 1),
			Font = FONTS.Display,
			TextSize = 20,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.5,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = if element.Unlocked then (if selected then "★" else "") else "🔒",
		})

		-- Nombre y detalle
		UiKit.text(row, "Name", {
			Position = UDim2.fromOffset(70, 9),
			Size = UDim2.new(1, -340, 0, 24),
			Font = FONTS.Display,
			TextSize = 19,
			TextColor3 = if element.Unlocked then THEME.Text else THEME.Muted,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = elementName(id) .. (if isDefault then "  · el cristal" else ""),
		})
		local detail
		if element.Unlocked then
			detail = ("Nv. %d/%d  ·  %s ⚡/s"):format(element.Level, element.MaxLevel, formatNumber(element.Production, 1))
			if selected and not isDefault and state.AffinityProduction > 0 then
				detail ..= ("  ·  ★ +%s afinidad"):format(formatNumber(state.AffinityProduction, 1))
			end
		elseif element.Available then
			detail = ("Dormido  ·  al despertarlo: %s ⚡/s"):format(formatNumber(element.Production, 1))
		else
			detail = ("Requiere despertar %s"):format(if previous then elementName(previous.Id) else "el anterior")
		end
		UiKit.text(row, "Detail", {
			Position = UDim2.fromOffset(70, 34),
			Size = UDim2.new(1, -340, 0, 20),
			Font = FONTS.Light,
			TextSize = 14,
			TextColor3 = THEME.Muted,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = detail,
		})
		-- Habilidad del elemento (números reales del servidor) y sus combos.
		local isSecondary = state.Secondary == id
		local ability = element.Ability
		if typeof(ability) == "table" and typeof(ability.Name) == "string" then
			UiKit.text(row, "Ability", {
				Position = UDim2.fromOffset(14, 62),
				Size = UDim2.new(1, -28, 0, 20),
				Font = FONTS.Light,
				TextSize = 14,
				TextColor3 = if selected or isSecondary then THEME.Gold elseif element.Unlocked then THEME.Text else THEME.Muted,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = ("%s %s%s  ·  %s  ·  recarga %s s"):format(
					tostring(ability.Icon or ""),
					ability.Name,
					if selected then " (Q)" elseif isSecondary then " (R)" else "",
					tostring(ability.Summary or ""),
					tostring(ability.Cooldown or "?")
				),
			})
		end
		local combos = AbilityLogic.partnersText(id)
		if combos ~= "" then
			UiKit.text(row, "Combos", {
				Position = UDim2.fromOffset(14, 84),
				Size = UDim2.new(1, -28, 0, 18),
				Font = FONTS.Light,
				TextSize = 13,
				TextColor3 = THEME.Muted,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = "Combos con:  " .. combos,
			})
		end

		-- Acciones (a la derecha, a la altura del nombre)
		local actions = UiKit.create("Frame", {
			Name = "Actions",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0, 31),
			Size = UDim2.fromOffset(270, 34),
			BackgroundTransparency = 1,
		}, row)
		UiKit.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, actions)

		if not element.Unlocked then
			if element.Available then
				addButton(actions, "Unlock", "DESPERTAR · ⚡ " .. formatNumber(element.UnlockCost or 0), 200, element.UnlockCost, state.Ready, function()
					actionRemote:FireServer("Unlock", id)
					setFeedback("Despertando…", THEME.Muted)
				end)
			end
			return
		end

		if element.UpgradeCost then
			local label = ("MEJORAR · ⚡ %s"):format(formatNumber(element.UpgradeCost))
			addButton(actions, "Upgrade", label, 150, element.UpgradeCost, state.Ready, function()
				if isDefault then
					pendingNature = true
					purchaseRemote:FireServer(NATURE_UPGRADE_ID)
				else
					actionRemote:FireServer("Upgrade", id)
				end
			end)
		else
			badge(actions, "MÁX", THEME.Gold, 70)
		end

		-- Huecos: ★ Q (principal) y ◆ R (secundario). El coste de cambiar va en la cabecera.
		local waiting = math.ceil((state.SwitchReadyAt or 0) - Workspace:GetServerTimeNow())
		local function slotButton(slotName: string, key: string, action: string)
			if waiting > 0 then
				local button = addButton(actions, slotName .. "Waiting", ("%ds"):format(waiting), 50, nil, false, function() end)
				button.TextSize = 14
				return
			end
			addButton(actions, slotName, key, 50, state.SwitchCost, state.Ready, function()
				actionRemote:FireServer(action, id)
			end)
		end
		if selected then
			badge(actions, "★ Q", THEME.Gold, 50)
		else
			slotButton("Select", "Q", "Select")
		end
		if isSecondary then
			badge(actions, "◆ R", color:Lerp(Color3.new(1, 1, 1), 0.35), 50)
		elseif selected and state.Secondary == nil then
			-- El principal solo puede ir a la R si ya hay otro en la R (se intercambian).
			badge(actions, "R", THEME.Disabled, 50)
		else
			slotButton("Secondary", "R", "Secondary")
		end
	end

	local function render()
		for _, child in ui.List:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		table.clear(rowButtons)
		table.clear(rowFrames)
		if not state then
			ui.Subtitle.Text = "Cargando tus núcleos…"
			return
		end
		local affinity = if state.AffinityProduction > 0 then (" + afinidad %s"):format(formatNumber(state.AffinityProduction, 1)) else ""
		ui.Subtitle.Text = ("Base %s ⚡/s%s  ·  mascotas ×%s  =  %s ⚡/s"):format(
			formatNumber(state.BaseProduction, 1),
			affinity,
			formatNumber(state.PetMultiplier, 2),
			formatNumber(state.Total, 1)
		)
		if not state.Ready then
			ui.Subtitle.Text = "Tus datos aún se están cargando…"
		end
		local waitingSwitch = math.ceil((state.SwitchReadyAt or 0) - Workspace:GetServerTimeNow())
		ui.Hint.Text = ("★ Q: principal (+%d %% de energía)   ◆ R: secundario   ·   cambiar: ⚡ %s%s\nUsa dos elementos que combinen: la marca de uno + la habilidad del otro = ¡combo!"):format(
			math.floor((CoreConfig.Affinity and CoreConfig.Affinity.Bonus or 0) * 100 + 0.5),
			formatNumber(state.SwitchCost or 0),
			if waitingSwitch > 0 then ("  (espera %d s)"):format(waitingSwitch) else ""
		)
		local previous = nil
		for order, element in state.Elements do
			buildRow(order, element, previous)
			previous = element
		end
		refreshAffordability()
		-- Llevar a la vista el núcleo resaltado (desde su altar).
		local target = highlight and rowFrames[highlight]
		if target then
			task.defer(function()
				local y = target.AbsolutePosition.Y - ui.List.AbsolutePosition.Y + ui.List.CanvasPosition.Y
				ui.List.CanvasPosition = Vector2.new(0, math.max(0, y - 10))
			end)
		end
		highlight = nil
	end

	-- Navegación ---------------------------------------------------------------------------
	local openToken = 0
	PanelManager.register(PANEL_NAME, ui.Panel, {
		OnOpen = function()
			requestRemote:FireServer()
			render()
			-- Mientras está abierto: refrescar la cuenta atrás del cambio de elemento.
			openToken += 1
			local token = openToken
			task.spawn(function()
				while openToken == token do
					task.wait(1)
					if openToken == token and state and (state.SwitchReadyAt or 0) > Workspace:GetServerTimeNow() - 1 then
						render()
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

	local function openAt(elementId: string?)
		highlight = elementId
		if PanelManager.isOpen(PANEL_NAME) then
			render()
		else
			PanelManager.open(PANEL_NAME)
		end
	end
	CoreController.open = openAt

	ui.Close.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.N then
			PanelManager.toggle(PANEL_NAME)
		end
	end)

	-- Servidor ---------------------------------------------------------------------------
	stateRemote.OnClientEvent:Connect(function(snapshot)
		if typeof(snapshot) ~= "table" or typeof(snapshot.Elements) ~= "table" then
			return
		end
		state = snapshot
		if PanelManager.isOpen(PANEL_NAME) then
			render()
		end
	end)

	resultRemote.OnClientEvent:Connect(function(success: boolean, code: string, action: string?, elementId: string?, cost: number?)
		local name = if typeof(elementId) == "string" then elementName(elementId) else "el núcleo"
		if success then
			if action == "Unlock" then
				setFeedback(("✨ ¡Núcleo de %s despierto! Ya produce energía."):format(name), THEME.BuyHighlight)
			elseif action == "Upgrade" then
				setFeedback(("Núcleo de %s mejorado."):format(name), THEME.BuyHighlight)
			elseif action == "Select" then
				setFeedback(("★ %s en la Q (afinidad activada)."):format(name), THEME.Gold)
			elseif action == "Secondary" then
				setFeedback(("◆ %s en la R."):format(name), THEME.Gold)
			end
		else
			local message = MESSAGES[code] or tostring(code)
			if code == Codes.InsufficientEnergy and typeof(cost) == "number" and cost > 0 then
				message = ("Te falta energía: necesitas ⚡ %s."):format(formatNumber(cost))
			end
			setFeedback(message, THEME.Error)
		end
	end)

	-- Mejora de Naturaleza (la Resonancia del Cristal, del HUD de energía).
	purchaseResult.OnClientEvent:Connect(function(success: boolean, code: string)
		if not pendingNature then
			return
		end
		pendingNature = false
		if PanelManager.isOpen(PANEL_NAME) then
			if success then
				setFeedback("Cristal (Naturaleza) mejorado.", THEME.BuyHighlight)
			else
				setFeedback(MESSAGES[code] or tostring(code), THEME.Error)
			end
		end
	end)

	-- Lo que cambia los números del panel: pedir el estado nuevo si está abierto.
	local function refreshIfOpen()
		if PanelManager.isOpen(PANEL_NAME) then
			requestRemote:FireServer()
		end
	end
	player:GetAttributeChangedSignal(Constants.Attributes.UpgradeLevelPrefix .. NATURE_UPGRADE_ID):Connect(refreshIfOpen)
	player:GetAttributeChangedSignal(Constants.Attributes.PetMultiplier):Connect(refreshIfOpen)
	player:GetAttributeChangedSignal(Constants.Attributes.DataStatus):Connect(refreshIfOpen)
	player:GetAttributeChangedSignal(Constants.Attributes.Energy):Connect(function()
		if PanelManager.isOpen(PANEL_NAME) then
			refreshAffordability()
		end
	end)

	-- Avisos "Ver núcleo" en los altares del Círculo Elemental ------------------------------
	local function addPrompts(root: Instance)
		for _, altar in root:GetChildren() do
			local elementId = altar:GetAttribute("Element")
			local cap = altar:FindFirstChild("ColumnCap")
			if typeof(elementId) == "string" and cap and cap:IsA("BasePart") and not cap:FindFirstChild("CorePrompt") then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "CorePrompt"
				prompt.ActionText = "Ver núcleo"
				prompt.ObjectText = elementName(elementId)
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.HoldDuration = 0
				prompt.MaxActivationDistance = 10
				prompt.RequiresLineOfSight = false
				prompt:SetAttribute("CoreId", elementId)
				prompt.Parent = cap
			end
		end
	end
	task.spawn(function()
		while true do
			local root = Workspace:FindFirstChild(CoreShrineConfig.ModelName)
			if root then
				addPrompts(root)
			end
			task.wait(if root and #root:GetChildren() >= #CoreConfig.Order - 1 then 10 else 1)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local elementId = prompt:GetAttribute("CoreId")
		if typeof(elementId) == "string" then
			openAt(elementId)
		end
	end)

	-- Aviso de producción offline ------------------------------------------------------------
	local toastShown = false
	local function showOfflineToast()
		local value = player:GetAttribute(Constants.Attributes.OfflineReward)
		if toastShown or typeof(value) ~= "string" then
			return
		end
		local amount, seconds = value:match("^(%d+),(%d+)$")
		if not amount then
			return
		end
		toastShown = true
		local body = ("Tus núcleos produjeron ⚡ %s mientras no estabas (%s, al %d %%)."):format(
			formatNumber(tonumber(amount) or 0),
			formatDuration(tonumber(seconds) or 0),
			math.floor(CoreConfig.Offline.Efficiency * 100 + 0.5)
		)
		-- Se cierra sola o al pulsarla.
		Toasts.show(body, { Title = "🌙 ¡Bienvenido de vuelta!", Color = THEME.Gold, Duration = TOAST_SECONDS, OnClick = function() end })
	end
	player:GetAttributeChangedSignal(Constants.Attributes.OfflineReward):Connect(showOfflineToast)
	showOfflineToast()
end

return CoreController
