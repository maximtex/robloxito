-- 🎭 Clases (panel "Classes"): las cinco clases de cada estilo (ClassConfig, ClassLogic), con
-- 💎. Solo muestra y pide; StyleService valida y cobra:
-- - Pestañas Armas / Puños / Magia (se abre en la de tu estilo).
-- - Una tarjeta por clase: icono, nombre, qué hace, nivel y sus pasivas a ese nivel (con lo
--   que da el siguiente en verde), y sus botones: Comprar (💎), Mejorar (💎, hasta el nivel
--   máximo) y Elegir (la activa de ese estilo; cambiarla es gratis).
-- - Se abre en el puesto 🎭 Clases de la plaza (pisando su círculo), con el botón 🎭 CLASES de
--   la tienda de tu estilo o la tecla H.
-- Datos de los atributos del jugador: Classes ("Soldier:2,Sniper:1"), ClassActive y Diamonds (💎).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local StyleConfig = require(Shared.Config.StyleConfig)
local ClassConfig = require(Shared.Config.ClassConfig)
local ClassLogic = require(Shared.ClassLogic)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local Toasts = require(script.Parent.Parent.UI.Toasts)
local Juice = require(script.Parent.Parent.UI.Juice)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local INK = Color3.fromRGB(43, 29, 63)
local DIAMOND = Color3.fromRGB(120, 210, 255)
local PANEL_NAME = "Classes"
local PANEL_ACTION = "RebirthCityClasses"
local CARD_COUNT = 5
local CARD_SIZE = Vector2.new(164, 424)
local PANEL_SIZE = Vector2.new(18 * 2 + CARD_COUNT * CARD_SIZE.X + (CARD_COUNT - 1) * 10, 610)
local HINT = "Una activa por estilo (cambiarla es gratis). Solo cuenta mientras juegas ese estilo."
local Codes = Constants.PurchaseCodes

local MESSAGES = {
	[Codes.InsufficientDiamonds] = "Te faltan 💎: derrota enemigos, gana oleadas y haz misiones",
	[Codes.AlreadyOwned] = "Ya la tienes",
	[Codes.NotOwned] = "Primero cómprala",
	[Codes.MaxLevel] = "Ya está al nivel máximo",
	[Codes.TooFast] = "Demasiado rápido, espera un momento",
	[Codes.NotReady] = "Cargando datos, inténtalo de nuevo",
	[Codes.InvalidRequest] = "Solicitud no válida",
}

local ClassesController = {}

local player = Players.LocalPlayer

local function diamonds(): number
	local value = player:GetAttribute(Constants.Attributes.Diamonds)
	return if typeof(value) == "number" then value else 0
end

local function currentStyle(): string
	local value = player:GetAttribute(Constants.Attributes.CombatStyle)
	return if typeof(value) == "string" and StyleConfig.Styles[value] then value else StyleConfig.Default
end

local function classData(): ClassLogic.ClassData
	return ClassLogic.parse(player:GetAttribute(Constants.Attributes.Classes), player:GetAttribute(Constants.Attributes.ClassActive))
end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("ClassesHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "ClassesHud",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local panel, panelScale = UiKit.panel(screenGui, "ClassesPanel", PANEL_SIZE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.15))
	local title = UiKit.text(panel, "Title", {
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -300, 0, 34),
		Font = FONTS.Display,
		TextSize = 30,
		Text = "🎭 Clases",
	})
	UiKit.outline(title, 2, INK)
	UiKit.text(panel, "Subtitle", {
		Position = UDim2.fromOffset(22, 50),
		Size = UDim2.new(1, -44, 0, 20),
		Font = FONTS.Light,
		TextSize = 15,
		TextColor3 = THEME.Muted,
		Text = "Cada clase da una pasiva a tu estilo. Cómpralas y súbelas con 💎 (más nivel, más fuerte).",
	})
	local pill = UiKit.create("Frame", {
		Name = "Diamonds",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -66, 0, 14),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = INK,
	}, panel)
	UiKit.corner(pill, 20)
	UiKit.create("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, pill)
	local diamondText = UiKit.text(pill, "Amount", {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = FONTS.Display,
		TextSize = 24,
		TextColor3 = DIAMOND,
		Text = "💎 0",
	})
	local close = UiKit.button(panel, "Close", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = THEME.Inset,
		Text = "×",
	})

	-- Pestañas de los estilos
	local tabsRow = UiKit.create("Frame", {
		Name = "Tabs",
		Position = UDim2.fromOffset(18, 78),
		Size = UDim2.new(1, -36, 0, 38),
		BackgroundTransparency = 1,
	}, panel)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tabsRow)
	local tabs = {}
	for order, styleId in StyleConfig.Order do
		local def = StyleConfig.Styles[styleId]
		tabs[styleId] = UiKit.button(tabsRow, styleId, {
			Size = UDim2.fromOffset(170, 38),
			BackgroundColor3 = THEME.Inset,
			TextSize = 18,
			Text = ("%s %s"):format(def.Icon, def.DisplayName),
			LayoutOrder = order,
		})
	end

	-- Tarjetas (cinco, una por clase del estilo que se ve)
	local row = UiKit.create("Frame", {
		Name = "Cards",
		Position = UDim2.fromOffset(18, 126),
		Size = UDim2.new(1, -36, 0, CARD_SIZE.Y),
		BackgroundTransparency = 1,
	}, panel)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	local cards = {}
	for index = 1, CARD_COUNT do
		local card = UiKit.create("Frame", {
			Name = "Card" .. index,
			Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y),
			BackgroundColor3 = THEME.Inset,
			LayoutOrder = index,
		}, row)
		UiKit.corner(card, 14)
		local stroke = UiKit.stroke(card, Color3.new(1, 1, 1), 3, 0.4)
		local badge = UiKit.text(card, "Badge", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, -10),
			Size = UDim2.fromOffset(96, 22),
			BackgroundTransparency = 0,
			BackgroundColor3 = THEME.Gold,
			Font = FONTS.Display,
			TextSize = 14,
			TextColor3 = INK,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "✓ ACTIVA",
			Visible = false,
			ZIndex = 3,
		})
		UiKit.corner(badge, 11)
		local icon = UiKit.text(card, "Icon", {
			Position = UDim2.fromOffset(0, 12),
			Size = UDim2.new(1, 0, 0, 50),
			Font = FONTS.Display,
			TextSize = 44,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local name = UiKit.text(card, "Name", {
			Position = UDim2.fromOffset(6, 64),
			Size = UDim2.new(1, -12, 0, 26),
			Font = FONTS.Display,
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextScaled = true,
		})
		UiKit.outline(name, 2, INK)
		local level = UiKit.text(card, "Level", {
			Position = UDim2.fromOffset(6, 92),
			Size = UDim2.new(1, -12, 0, 20),
			Font = FONTS.Display,
			TextSize = 16,
			TextColor3 = THEME.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local text = UiKit.text(card, "Text", {
			Position = UDim2.fromOffset(10, 116),
			Size = UDim2.new(1, -20, 0, 70),
			Font = FONTS.Body,
			TextSize = 15,
			TextWrapped = true,
			TextColor3 = THEME.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		local bonuses = UiKit.text(card, "Bonuses", {
			Position = UDim2.fromOffset(8, 190),
			Size = UDim2.new(1, -16, 0, 122),
			Font = FONTS.Body,
			TextSize = 16,
			RichText = true,
			TextWrapped = true,
			LineHeight = 1.05,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		local main = UiKit.button(card, "Main", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -60),
			Size = UDim2.new(1, -20, 0, 44),
			TextSize = 17,
		})
		local selectButton = UiKit.button(card, "Select", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -20, 0, 42),
			BackgroundColor3 = THEME.Secondary,
			TextSize = 17,
			Text = "Elegir",
		})
		cards[index] = { Frame = card, Stroke = stroke, Badge = badge, Icon = icon, Name = name, Level = level, Text = text, Bonuses = bonuses, Main = main, Select = selectButton }
	end

	local feedback = UiKit.text(panel, "Feedback", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -40, 0, 22),
		Font = FONTS.Display,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = HINT,
		TextColor3 = THEME.Muted,
	})

	screenGui.Parent = playerGui
	return {
		ScreenGui = screenGui,
		Panel = panel,
		PanelScale = panelScale,
		Title = title,
		Diamonds = diamondText,
		Close = close,
		Tabs = tabs,
		Cards = cards,
		Feedback = feedback,
	}
end

function ClassesController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local actionRemote = remotes:WaitForChild(Constants.Remotes.StyleAction) :: RemoteEvent
	local eventRemote = remotes:WaitForChild(Constants.Remotes.StyleEvent) :: RemoteEvent
	local ui = buildGui()
	local shown = currentStyle()
	local actions: { [number]: { Main: () -> (), Select: () -> () } } = {}
	local feedbackToken = 0

	local function say(text: string, ok: boolean)
		feedbackToken += 1
		local token = feedbackToken
		ui.Feedback.Text = text
		ui.Feedback.TextColor3 = if ok then THEME.BuyHighlight else THEME.Error
		task.delay(3, function()
			if feedbackToken == token then
				ui.Feedback.Text = HINT
				ui.Feedback.TextColor3 = THEME.Muted
			end
		end)
	end

	local function render()
		local style = StyleConfig.Styles[shown]
		local money = diamonds()
		ui.Diamonds.Text = "💎 " .. formatNumber(money)
		ui.Title.Text = ("🎭 Clases · %s %s"):format(style.Icon, style.DisplayName)
		for styleId, tab in ui.Tabs do
			tab.BackgroundColor3 = if styleId == shown then StyleConfig.Styles[styleId].Color else THEME.Inset
		end
		local data = classData()
		local active = ClassLogic.active(data, shown)
		for index, card in ui.Cards do
			local classId = ClassLogic.ordered(shown)[index]
			local def = classId and ClassLogic.definition(classId)
			card.Frame.Visible = def ~= nil
			if not (classId and def) then
				actions[index] = nil
				continue
			end
			local level = ClassLogic.level(data, classId)
			local has = level > 0
			local isActive = has and classId == active
			card.Icon.Text = def.Icon
			card.Name.Text = def.Name
			card.Name.TextColor3 = if has then style.Color else THEME.Text
			card.Text.Text = def.Text
			card.Stroke.Color = if isActive then THEME.Gold elseif has then style.Color else Color3.new(1, 1, 1)
			card.Stroke.Thickness = if isActive then 4 else 3
			card.Stroke.Transparency = if has then 0 else 0.6
			card.Badge.Visible = isActive
			local shownLevel = math.max(1, level)
			local nextLevel = if has and shownLevel < ClassConfig.Levels.Max then shownLevel + 1 else nil
			local lines = {}
			for _, bonus in ClassLogic.bonusList(classId, shownLevel) do
				local nextValue = if nextLevel then ClassLogic.bonus(classId, bonus.Key, nextLevel) else nil
				table.insert(lines, ClassLogic.bonusText(bonus.Key, bonus.Value, nextValue))
			end
			card.Bonuses.Text = table.concat(lines, "\n")
			local action = { Main = function() end, Select = function() end }
			if has then
				card.Level.Text = ("Nivel %d/%d"):format(level, ClassConfig.Levels.Max)
				local cost = ClassLogic.upgradeCost(classId, level)
				if cost then
					card.Main.Text = ("⬆ Mejorar  💎%s"):format(formatNumber(cost))
					card.Main.BackgroundColor3 = if money >= cost then THEME.Buy else THEME.Disabled
					action.Main = function()
						actionRemote:FireServer("UpgradeClass", classId)
					end
				else
					card.Main.Text = "★ MÁX"
					card.Main.BackgroundColor3 = THEME.Gold
					action.Main = function()
						say("Ya está al nivel máximo", true)
					end
				end
				card.Select.Visible = true
				card.Select.Text = if isActive then "✓ Activa" else "Elegir"
				card.Select.BackgroundColor3 = if isActive then style.Color else THEME.Secondary
				action.Select = function()
					if isActive then
						say(("%s %s ya es tu clase de %s"):format(def.Icon, def.Name, style.DisplayName), true)
					else
						actionRemote:FireServer("SelectClass", classId)
					end
				end
			else
				local price = def.Price or 0
				card.Level.Text = if price <= 0 then "Gratis" else "🔒 Sin comprar"
				card.Main.Text = ("Comprar  💎%s"):format(formatNumber(price))
				card.Main.BackgroundColor3 = if money >= price then THEME.Buy else THEME.Disabled
				action.Main = function()
					actionRemote:FireServer("BuyClass", classId)
				end
				card.Select.Visible = false
			end
			actions[index] = action
		end
	end

	for index, card in ui.Cards do
		card.Main.Activated:Connect(function()
			local action = actions[index]
			if action then
				action.Main()
			end
		end)
		card.Select.Activated:Connect(function()
			local action = actions[index]
			if action then
				action.Select()
			end
		end)
	end
	for styleId, tab in ui.Tabs do
		tab.Activated:Connect(function()
			shown = styleId
			render()
		end)
	end

	PanelManager.register(PANEL_NAME, ui.Panel, {
		OnOpen = function()
			shown = currentStyle()
			render()
		end,
	})
	UiKit.bindModalLayout(ui.ScreenGui, ui.PanelScale, PANEL_SIZE, function(position)
		PanelManager.setBasePosition(PANEL_NAME, position)
	end)
	ui.Close.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
	end)
	ContextActionService:BindAction(PANEL_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			PanelManager.toggle(PANEL_NAME)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.H)

	eventRemote.OnClientEvent:Connect(function(event: any)
		if typeof(event) ~= "table" or event.Kind ~= "Result" or event.Owner ~= player then
			return
		end
		local action = event.Action
		if action ~= "BuyClass" and action ~= "UpgradeClass" and action ~= "SelectClass" then
			return
		end
		local def = ClassLogic.definition(event.Class)
		local name = if def then ("%s %s"):format(def.Icon, def.Name) else "Clase"
		if event.Success then
			if action == "BuyClass" then
				say(("¡%s es tuya y ya está activa!"):format(name), true)
				Juice.sound(Juice.Sounds.Upgrade, 1.1)
				if not PanelManager.isOpen(PANEL_NAME) then
					Toasts.show(("¡%s es tuya!"):format(name), { Color = DIAMOND })
				end
			elseif action == "UpgradeClass" then
				say(("%s mejorada: su pasiva es más fuerte"):format(name), true)
				Juice.sound(Juice.Sounds.Upgrade, 1.05)
			else
				say(("Ahora eres %s"):format(name), true)
				Juice.sound(Juice.Sounds.Upgrade, 1.2)
			end
		else
			say(MESSAGES[event.Code] or tostring(event.Code), false)
		end
		if PanelManager.isOpen(PANEL_NAME) then
			render()
		end
	end)

	for _, attribute in { Constants.Attributes.Diamonds, Constants.Attributes.Classes, Constants.Attributes.ClassActive, Constants.Attributes.CombatStyle } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if PanelManager.isOpen(PANEL_NAME) then
				render()
			end
		end)
	end
end

return ClassesController
