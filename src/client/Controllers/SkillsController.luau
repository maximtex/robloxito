-- ⚡ Mejoras (panel "Skills"): las habilidades de cada estilo (StyleConfig.Styles[x].Skills,
-- SkillLogic) y la Velocidad de Correr (EconomyConfig.Upgrades.WalkSpeed), todo con 💎.
-- Solo muestra y pide; StyleService (habilidades) y UpgradeService (velocidad) validan y
-- cobran:
-- - Pestañas Armas / Puños / Magia (se abre en la de tu estilo).
-- - Una tarjeta por habilidad: icono, nombre, qué hace, nivel, daño y recarga a su nivel, y
--   sus botones: Comprar (💎), Mejorar (💎, hasta el nivel máximo) y ponerla en la Z o la X.
-- - Abajo, la Velocidad de Correr: su nivel, lo que suma y el botón para subirla.
-- - Se abre en el puesto ⚡ Mejoras del pueblo (pisando su círculo), con el botón ⚡ MEJORAS de
--   la tienda de tu estilo, la insignia ⚡ del botón de la X o la tecla B.
-- Datos de los atributos del jugador: Skills ("Burst:1,Pierce:2"), SkillSlots y Diamonds (💎).
-- Cada mundo tiene las suyas: en el Mundo 2 (CurrentZone del Mundo 2) se ven sus 4 habilidades
-- nuevas de cada estilo (StyleConfig: World = 2) y en el Mundo 1, las de siempre. Las puestas
-- en la Z y la X se quedan aunque cambies de mundo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local StyleConfig = require(Shared.Config.StyleConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local Economy = require(Shared.Economy)
local SkillLogic = require(Shared.SkillLogic)
local ZoneConfig = require(Shared.Config.ZoneConfig)
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
local PANEL_NAME = "Skills"
local PANEL_SIZE = Vector2.new(820, 616)
local SPEED_ID = "WalkSpeed"
local CARD_SIZE = Vector2.new(186, 404)
local Codes = Constants.PurchaseCodes

local MESSAGES = {
	[Codes.InsufficientDiamonds] = "Te faltan 💎: derrota enemigos, gana oleadas y haz misiones",
	[Codes.AlreadyOwned] = "Ya la tienes",
	[Codes.NotOwned] = "Primero cómprala",
	[Codes.MaxLevel] = "Ya está al nivel máximo",
	[Codes.TooFast] = "Demasiado rápido, espera un momento",
	[Codes.NotReady] = "Cargando datos, inténtalo de nuevo",
	[Codes.InvalidRequest] = "Solicitud no válida",
	[Codes.ZoneLocked] = "Primero llega al Mundo 2",
}

local SkillsController = {}

local player = Players.LocalPlayer

local function diamonds(): number
	local value = player:GetAttribute(Constants.Attributes.Diamonds)
	return if typeof(value) == "number" then value else 0
end

-- Mundo en el que está el jugador (el de su zona actual)
local function currentWorld(): number
	local zoneId = player:GetAttribute(Constants.Attributes.CurrentZone)
	local zone = typeof(zoneId) == "string" and ZoneConfig.Zones[zoneId]
	return if zone and zone.World then zone.World else 1
end

local function currentStyle(): string
	local value = player:GetAttribute(Constants.Attributes.CombatStyle)
	return if typeof(value) == "string" and StyleConfig.Styles[value] then value else StyleConfig.Default
end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("SkillsHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "SkillsHud",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local panel, panelScale = UiKit.panel(screenGui, "SkillsPanel", PANEL_SIZE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.15))
	local title = UiKit.text(panel, "Title", {
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -300, 0, 34),
		Font = FONTS.Display,
		TextSize = 30,
		Text = "⚡ Mejoras",
	})
	UiKit.outline(title, 2, INK)
	UiKit.text(panel, "Subtitle", {
		Position = UDim2.fromOffset(22, 50),
		Size = UDim2.new(1, -44, 0, 20),
		Font = FONTS.Light,
		TextSize = 15,
		TextColor3 = THEME.Muted,
		Text = "Con 💎: compra habilidades, súbelas (más daño) y pon dos (Z y X). Abajo, tu velocidad.",
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

	-- Tarjetas (cuatro, una por habilidad del estilo que se ve)
	local row = UiKit.create("Frame", {
		Name = "Cards",
		Position = UDim2.fromOffset(18, 126),
		Size = UDim2.new(1, -36, 0, CARD_SIZE.Y),
		BackgroundTransparency = 1,
	}, panel)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	local cards = {}
	for index = 1, 4 do
		local card = UiKit.create("Frame", {
			Name = "Card" .. index,
			Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y),
			BackgroundColor3 = THEME.Inset,
			LayoutOrder = index,
		}, row)
		UiKit.corner(card, 14)
		local stroke = UiKit.stroke(card, Color3.new(1, 1, 1), 3, 0.4)
		local icon = UiKit.text(card, "Icon", {
			Position = UDim2.fromOffset(0, 10),
			Size = UDim2.new(1, 0, 0, 50),
			Font = FONTS.Display,
			TextSize = 44,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local name = UiKit.text(card, "Name", {
			Position = UDim2.fromOffset(6, 62),
			Size = UDim2.new(1, -12, 0, 26),
			Font = FONTS.Display,
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextScaled = true,
		})
		UiKit.outline(name, 2, INK)
		local level = UiKit.text(card, "Level", {
			Position = UDim2.fromOffset(6, 90),
			Size = UDim2.new(1, -12, 0, 20),
			Font = FONTS.Display,
			TextSize = 16,
			TextColor3 = THEME.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local text = UiKit.text(card, "Text", {
			Position = UDim2.fromOffset(10, 114),
			Size = UDim2.new(1, -20, 0, 92),
			Font = FONTS.Body,
			TextSize = 14,
			TextWrapped = true,
			TextColor3 = THEME.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		local stats = UiKit.text(card, "Stats", {
			Position = UDim2.fromOffset(10, 210),
			Size = UDim2.new(1, -20, 0, 44),
			Font = FONTS.Body,
			TextSize = 14,
			RichText = true,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		local main = UiKit.button(card, "Main", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -62),
			Size = UDim2.new(1, -20, 0, 44),
			TextSize = 18,
		})
		local slotZ = UiKit.button(card, "SlotZ", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 10, 1, -12),
			Size = UDim2.new(0.5, -15, 0, 40),
			BackgroundColor3 = THEME.Secondary,
			TextSize = 17,
			Text = "Z",
		})
		local slotX = UiKit.button(card, "SlotX", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -10, 1, -12),
			Size = UDim2.new(0.5, -15, 0, 40),
			BackgroundColor3 = THEME.Secondary,
			TextSize = 17,
			Text = "X",
		})
		cards[index] = { Frame = card, Stroke = stroke, Icon = icon, Name = name, Level = level, Text = text, Stats = stats, Main = main, Slots = { slotZ, slotX } }
	end

	-- Velocidad de Correr (abajo, con 💎)
	local speedRow = UiKit.create("Frame", {
		Name = "Speed",
		Position = UDim2.fromOffset(18, 538),
		Size = UDim2.new(1, -36, 0, 48),
		BackgroundColor3 = THEME.Inset,
	}, panel)
	UiKit.corner(speedRow, 12)
	UiKit.stroke(speedRow, Color3.fromRGB(120, 230, 160), 2, 0.3)
	local speedText = UiKit.text(speedRow, "Text", {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -240, 1, 0),
		Font = FONTS.Display,
		TextSize = 18,
		RichText = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "🏃 Velocidad al correr",
	})
	local speedButton = UiKit.button(speedRow, "Upgrade", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(210, 38),
		TextSize = 17,
		Text = "⬆ Mejorar",
	})

	local feedback = UiKit.text(panel, "Feedback", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -40, 0, 22),
		Font = FONTS.Display,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "Los 💎 los sueltan los enemigos, las oleadas, los jefes y las misiones.",
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
		SpeedText = speedText,
		SpeedButton = speedButton,
		Feedback = feedback,
	}
end

function SkillsController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local actionRemote = remotes:WaitForChild(Constants.Remotes.StyleAction) :: RemoteEvent
	local purchaseRemote = remotes:WaitForChild(Constants.Remotes.PurchaseUpgrade) :: RemoteEvent
	local purchaseResult = remotes:WaitForChild(Constants.Remotes.PurchaseResult) :: RemoteEvent
	local eventRemote = remotes:WaitForChild(Constants.Remotes.StyleEvent) :: RemoteEvent
	local ui = buildGui()
	local shown = currentStyle()
	local actions: { [number]: { Main: () -> (), Z: () -> (), X: () -> () } } = {}
	local feedbackToken = 0

	local function say(text: string, ok: boolean)
		feedbackToken += 1
		local token = feedbackToken
		ui.Feedback.Text = text
		ui.Feedback.TextColor3 = if ok then THEME.BuyHighlight else THEME.Error
		task.delay(3, function()
			if feedbackToken == token then
				ui.Feedback.Text = "Los 💎 los sueltan los enemigos, las oleadas, los jefes y las misiones."
				ui.Feedback.TextColor3 = THEME.Muted
			end
		end)
	end

	local function renderSpeed(money: number)
		local def = EconomyConfig.Upgrades[SPEED_ID]
		local raw = player:GetAttribute(Constants.Attributes.UpgradeLevelPrefix .. SPEED_ID)
		-- (los niveles de antes por encima del máximo cuentan como el máximo)
		local level = math.min(if typeof(raw) == "number" then raw else 0, def.MaxLevel)
		local per = def.SpeedPerLevel or 1
		ui.SpeedText.Text = ("🏃 Velocidad al correr · <font color=\"#FFCE54\">Nivel %d/%d</font> · +%s"):format(level, def.MaxLevel, formatNumber(level * per, 1))
		if level >= def.MaxLevel then
			ui.SpeedButton.Text = "★ MÁX"
			ui.SpeedButton.BackgroundColor3 = THEME.Gold
		else
			local cost = Economy.getUpgradeCost(SPEED_ID, level) or 0
			ui.SpeedButton.Text = ("⬆ +%s  💎%s"):format(formatNumber(per, 1), formatNumber(cost))
			ui.SpeedButton.BackgroundColor3 = if money >= cost then THEME.Buy else THEME.Disabled
		end
	end

	local function render()
		local style = StyleConfig.Styles[shown]
		local money = diamonds()
		renderSpeed(money)
		ui.Diamonds.Text = "💎 " .. formatNumber(money)
		local world = currentWorld()
		ui.Title.Text = ("⚡ Mejoras%s · %s %s"):format(if world == 2 then " del Mundo 2" else "", style.Icon, style.DisplayName)
		for styleId, tab in ui.Tabs do
			local active = styleId == shown
			tab.BackgroundColor3 = if active then StyleConfig.Styles[styleId].Color else THEME.Inset
		end
		local owned = SkillLogic.parseOwned(player:GetAttribute(Constants.Attributes.Skills))
		local slots = SkillLogic.parseSlots(player:GetAttribute(Constants.Attributes.SkillSlots))[shown] or {}
		local list = SkillLogic.ordered(shown, world)
		for index, card in ui.Cards do
			card.Frame.Visible = list[index] ~= nil
		end
		for index, skillId in list do
			local card = ui.Cards[index]
			if not card then
				continue
			end
			local def = style.Skills[skillId]
			local level = owned[skillId]
			local has = level ~= nil
			card.Icon.Text = def.Icon
			card.Name.Text = def.Name
			card.Name.TextColor3 = if has then style.Color else THEME.Text
			card.Text.Text = def.Text
			card.Stroke.Color = if has then style.Color else Color3.new(1, 1, 1)
			card.Stroke.Transparency = if has then 0 else 0.6
			local shownLevel = level or 1
			local parts = {}
			if def.DamageRatio then
				table.insert(parts, ("Daño <b>×%s</b>"):format(formatNumber(def.DamageRatio * SkillLogic.power(shownLevel), 2)))
			end
			if def.Duration then
				table.insert(parts, ("Dura <b>%.1f s</b>"):format(SkillLogic.duration(def, shownLevel)))
			end
			table.insert(parts, ("Recarga <b>%.1f s</b>"):format(SkillLogic.cooldown(def, shownLevel)))
			card.Stats.Text = table.concat(parts, "  ·  ")
			card.Stats.TextColor3 = THEME.Text
			local action = { Main = function() end, Z = function() end, X = function() end }
			if has then
				card.Level.Text = ("Nivel %d/%d"):format(level, StyleConfig.SkillLevels.Max)
				local cost = SkillLogic.upgradeCost(skillId, level)
				if cost then
					card.Main.Text = ("⬆ Mejorar  💎%s"):format(formatNumber(cost))
					card.Main.BackgroundColor3 = if money >= cost then THEME.Buy else THEME.Disabled
					action.Main = function()
						actionRemote:FireServer("UpgradeSkill", skillId)
					end
				else
					card.Main.Text = "★ MÁX"
					card.Main.BackgroundColor3 = THEME.Gold
					action.Main = function()
						say("Ya está al nivel máximo", true)
					end
				end
				for slot, button in card.Slots do
					local equipped = slots[slot] == skillId
					button.Text = if equipped then ("✓ %s"):format(if slot == 1 then "Z" else "X") else (if slot == 1 then "Z" else "X")
					button.BackgroundColor3 = if equipped then style.Color else THEME.Secondary
					button.Visible = true
				end
				action.Z = function()
					actionRemote:FireServer("EquipSkill", skillId, 1)
				end
				action.X = function()
					actionRemote:FireServer("EquipSkill", skillId, 2)
				end
			else
				card.Level.Text = "🔒 Sin comprar"
				local price = def.Price or 0
				card.Main.Text = ("Comprar  💎%s"):format(formatNumber(price))
				card.Main.BackgroundColor3 = if money >= price then THEME.Buy else THEME.Disabled
				action.Main = function()
					actionRemote:FireServer("BuySkill", skillId)
				end
				for _, button in card.Slots do
					button.Visible = false
				end
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
		card.Slots[1].Activated:Connect(function()
			local action = actions[index]
			if action then
				action.Z()
			end
		end)
		card.Slots[2].Activated:Connect(function()
			local action = actions[index]
			if action then
				action.X()
			end
		end)
	end
	for styleId, tab in ui.Tabs do
		tab.Activated:Connect(function()
			shown = styleId
			render()
		end)
	end
	ui.SpeedButton.Activated:Connect(function()
		purchaseRemote:FireServer(SPEED_ID)
	end)
	purchaseResult.OnClientEvent:Connect(function(success: boolean, code: string, upgradeId: string?)
		if upgradeId ~= SPEED_ID then
			return
		end
		if success then
			say("🏃 ¡Corres más rápido!", true)
			Juice.sound(Juice.Sounds.Upgrade, 1.1)
		else
			say(MESSAGES[code] or tostring(code), false)
		end
		if PanelManager.isOpen(PANEL_NAME) then
			render()
		end
	end)

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

	eventRemote.OnClientEvent:Connect(function(event: any)
		if typeof(event) ~= "table" or event.Kind ~= "Result" or event.Owner ~= player then
			return
		end
		local action = event.Action
		if action ~= "BuySkill" and action ~= "UpgradeSkill" and action ~= "EquipSkill" then
			return
		end
		local def = SkillLogic.definition(event.Skill)
		local name = if def then ("%s %s"):format(def.Icon, def.Name) else "Habilidad"
		if event.Success then
			if action == "BuySkill" then
				say(("¡%s es tuya! Ponla en la Z o la X."):format(name), true)
				Juice.sound(Juice.Sounds.Upgrade, 1.1)
				if not PanelManager.isOpen(PANEL_NAME) then
					Toasts.show(("¡%s es tuya!"):format(name), { Color = DIAMOND })
				end
			elseif action == "UpgradeSkill" then
				say(("%s mejorada"):format(name), true)
				Juice.sound(Juice.Sounds.Upgrade, 1.05)
			else
				say(("%s puesta en la %s"):format(name, if event.Slot == 2 then "X" else "Z"), true)
			end
		else
			say(MESSAGES[event.Code] or tostring(event.Code), false)
		end
		if PanelManager.isOpen(PANEL_NAME) then
			render()
		end
	end)

	for _, attribute in { Constants.Attributes.Diamonds, Constants.Attributes.Skills, Constants.Attributes.SkillSlots, Constants.Attributes.CombatStyle, Constants.Attributes.CurrentZone, Constants.Attributes.UpgradeLevelPrefix .. SPEED_ID } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if PanelManager.isOpen(PANEL_NAME) then
				render()
			end
		end)
	end
end

return SkillsController
