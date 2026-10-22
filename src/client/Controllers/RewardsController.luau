-- Premios (solo presentación; el servidor decide todo, RewardService):
-- - Azulejo «🎁 Premios» en el menú, con «!» y borde que late si hoy hay premio.
-- - Panel con pestañas Racha diaria / Códigos:
--   · Racha: los 7 días (ya reclamados, el de hoy resaltado y los que vienen), botón
--     «Reclamar» o cuenta atrás hasta el siguiente.
--   · Códigos: caja de texto y botón «Canjear» (el servidor dice si vale).
-- - Al entrar, si hay premio sin reclamar (y el tutorial ya terminó), el panel se abre solo
--   una vez.
-- - Tecla J para abrir y cerrar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local RewardConfig = require(Shared.Config.RewardConfig)
local AdventureConfig = require(Shared.Config.AdventureConfig)
local PetConfig = require(Shared.Config.PetConfig)
local ChestConfig = require(Shared.Config.ChestConfig)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local MenuBar = require(script.Parent.Parent.UI.MenuBar)
local Toasts = require(script.Parent.Parent.UI.Toasts)
local Juice = require(script.Parent.Parent.UI.Juice)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local PANEL_NAME = "Rewards"
local PANEL_SIZE = Vector2.new(640, 430)
local PINK = Color3.fromRGB(255, 150, 190)
local CARD_SIZE = Vector2.new(78, 150)
local CARD_GAP = 6

local MESSAGES = {
	AlreadyClaimed = "Ya reclamaste el premio de hoy.",
	NotReady = "Tus datos aún se están cargando.",
	TooFast = "Espera un momento.",
	InvalidCode = "Ese código no existe. Revisa que esté bien escrito.",
	Expired = "Ese código ya caducó.",
	AlreadyRedeemed = "Ya canjeaste ese código.",
	RebirthLocked = "Necesitas más renacimientos para ese código.",
	Full = "Ya canjeaste demasiados códigos.",
	InvalidRequest = "No se pudo hacer.",
}

local RewardsController = {}

local player = Players.LocalPlayer

local function blessingText(blessings: any): string
	local parts = {}
	if typeof(blessings) == "table" then
		for blessingId, count in blessings do
			local def = AdventureConfig.Blessings[blessingId]
			if def then
				table.insert(parts, (if typeof(count) == "number" and count > 1 then count .. "× " else "") .. def.Icon .. " " .. def.DisplayName)
			end
		end
	end
	table.sort(parts)
	return table.concat(parts, " + ")
end

-- Icono y texto corto de un premio de la racha.
local function rewardFace(day: any): (string, string)
	local icons, lines = {}, {}
	if typeof(day) ~= "table" then
		return "🎁", ""
	end
	if day.Pet then
		table.insert(icons, "🐾")
		table.insert(lines, "Mascota")
	end
	if typeof(day.Energy) == "number" then
		table.insert(icons, "⚡")
		table.insert(lines, "+" .. formatNumber(day.Energy))
	end
	if typeof(day.Blessings) == "table" then
		for blessingId in day.Blessings do
			local def = AdventureConfig.Blessings[blessingId]
			if def then
				table.insert(icons, def.Icon)
			end
		end
		if #lines == 0 then
			table.insert(lines, "Bendición")
		end
	end
	return table.concat(icons, ""), table.concat(lines, "\n")
end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("RewardsHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "RewardsHud",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local panel, panelScale = UiKit.panel(screenGui, "RewardsPanel", PANEL_SIZE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.2))
	UiKit.text(panel, "Title", {
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -90, 0, 32),
		Font = FONTS.Display,
		TextSize = 28,
		Text = "🎁 Premios",
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
	UiKit.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, tabsRow)
	local tabs = {}
	for order, spec in { { "Streak", "Racha diaria" }, { "Codes", "Códigos" }, { "Chests", "📦 Cofres" } } do
		tabs[spec[1]] = UiKit.button(tabsRow, spec[1], {
			Size = UDim2.fromOffset(170, 36),
			BackgroundColor3 = THEME.Inset,
			TextSize = 17,
			Text = spec[2],
			LayoutOrder = order,
		})
	end

	-- Racha -------------------------------------------------------------------------------
	local streakPage = UiKit.create("Frame", {
		Name = "StreakPage",
		Position = UDim2.fromOffset(22, 124),
		Size = UDim2.new(1, -44, 1, -134),
		BackgroundTransparency = 1,
	}, panel)
	local cardsRow = UiKit.create("Frame", {
		Name = "Days",
		Size = UDim2.new(1, 0, 0, CARD_SIZE.Y),
		BackgroundTransparency = 1,
	}, streakPage)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, CARD_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, cardsRow)
	local cards = {}
	for index = 1, #RewardConfig.Streak do
		local card = UiKit.create("Frame", {
			Name = "Day" .. index,
			Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y),
			BackgroundColor3 = THEME.Inset,
			LayoutOrder = index,
		}, cardsRow)
		UiKit.corner(card, 12)
		local stroke = UiKit.stroke(card, THEME.Stroke, 1.5, 0.6)
		local dayLabel = UiKit.text(card, "Day", {
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 18),
			Font = FONTS.Body,
			TextSize = 14,
			TextColor3 = THEME.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "Día " .. index,
		})
		local icon = UiKit.text(card, "Icon", {
			Position = UDim2.fromOffset(4, 30),
			Size = UDim2.new(1, -8, 0, 44),
			Font = FONTS.Display,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local amount = UiKit.text(card, "Amount", {
			Position = UDim2.fromOffset(4, 80),
			Size = UDim2.new(1, -8, 0, 36),
			Font = FONTS.Display,
			TextSize = 15,
			TextWrapped = true,
			TextColor3 = THEME.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		local state = UiKit.text(card, "State", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -6),
			Size = UDim2.new(1, 0, 0, 20),
			Font = FONTS.Display,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		table.insert(cards, { Frame = card, Stroke = stroke, Day = dayLabel, Icon = icon, Amount = amount, State = state })
	end
	local streakInfo = UiKit.text(streakPage, "Info", {
		Position = UDim2.fromOffset(0, CARD_SIZE.Y + 14),
		Size = UDim2.new(1, 0, 0, 22),
		Font = FONTS.Body,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local claimButton = UiKit.button(streakPage, "Claim", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, CARD_SIZE.Y + 44),
		Size = UDim2.fromOffset(300, 52),
		TextSize = 22,
		Text = "Reclamar",
	})
	local streakFeedback = UiKit.text(streakPage, "Feedback", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -4),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	-- Códigos -----------------------------------------------------------------------------
	local codesPage = UiKit.create("Frame", {
		Name = "CodesPage",
		Position = UDim2.fromOffset(22, 124),
		Size = UDim2.new(1, -44, 1, -134),
		BackgroundTransparency = 1,
		Visible = false,
	}, panel)
	UiKit.text(codesPage, "Help", {
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 44),
		Font = FONTS.Light,
		TextSize = 16,
		TextWrapped = true,
		TextColor3 = THEME.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "¿Tienes un código? Los publicamos en nuestras redes y en las actualizaciones. Cada código se canjea una vez.",
	})
	local box = UiKit.create("TextBox", {
		Name = "CodeBox",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 74),
		Size = UDim2.fromOffset(380, 52),
		BackgroundColor3 = THEME.Overlay,
		BackgroundTransparency = 0.2,
		ClearTextOnFocus = false,
		PlaceholderText = "Escribe el código",
		PlaceholderColor3 = THEME.Muted,
		Text = "",
		TextColor3 = THEME.Text,
		Font = FONTS.Display,
		TextSize = 24,
	}, codesPage)
	UiKit.corner(box, 10)
	UiKit.stroke(box, THEME.Stroke, 1.5, 0.4)
	local redeemButton = UiKit.button(codesPage, "Redeem", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 140),
		Size = UDim2.fromOffset(240, 50),
		TextSize = 21,
		Text = "Canjear",
	})
	local codeFeedback = UiKit.text(codesPage, "Feedback", {
		Position = UDim2.fromOffset(0, 204),
		Size = UDim2.new(1, 0, 0, 44),
		TextSize = 17,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	-- Cofres escondidos ----------------------------------------------------------------------
	local chestsPage = UiKit.create("Frame", {
		Name = "ChestsPage",
		Position = UDim2.fromOffset(22, 124),
		Size = UDim2.new(1, -44, 1, -134),
		BackgroundTransparency = 1,
		Visible = false,
	}, panel)
	local chestsInfo = UiKit.text(chestsPage, "Info", {
		Size = UDim2.new(1, 0, 0, 22),
		Font = FONTS.Body,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local grid = UiKit.create("Frame", {
		Name = "Grid",
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 1, -30),
		BackgroundTransparency = 1,
	}, chestsPage)
	UiKit.create("UIGridLayout", {
		CellSize = UDim2.new(0.25, -6, 0.5, -6),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	local chestCards = {}
	for index, chest in ChestConfig.Chests do
		local card = UiKit.create("Frame", {
			Name = chest.Id,
			BackgroundColor3 = THEME.Inset,
			LayoutOrder = index,
		}, grid)
		UiKit.corner(card, 12)
		local stroke = UiKit.stroke(card, THEME.Stroke, 1.5, 0.6)
		local icon = UiKit.text(card, "Icon", {
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.new(1, 0, 0, 30),
			Font = FONTS.Display,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "📦",
		})
		local name = UiKit.text(card, "Name", {
			Position = UDim2.fromOffset(6, 38),
			Size = UDim2.new(1, -12, 0, 32),
			Font = FONTS.Display,
			TextSize = 14,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = chest.Name,
		})
		local status = UiKit.text(card, "Status", {
			Position = UDim2.fromOffset(6, 72),
			Size = UDim2.new(1, -12, 1, -76),
			Font = FONTS.Light,
			TextSize = 12,
			TextWrapped = true,
			TextColor3 = THEME.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		chestCards[chest.Id] = { Frame = card, Stroke = stroke, Icon = icon, Name = name, Status = status }
	end

	screenGui.Parent = playerGui
	return {
		ChestsPage = chestsPage,
		ChestsInfo = chestsInfo,
		ChestCards = chestCards,
		ScreenGui = screenGui,
		Panel = panel,
		PanelScale = panelScale,
		Subtitle = subtitle,
		Close = close,
		Tabs = tabs,
		StreakPage = streakPage,
		Cards = cards,
		StreakInfo = streakInfo,
		ClaimButton = claimButton,
		StreakFeedback = streakFeedback,
		CodesPage = codesPage,
		CodeBox = box,
		RedeemButton = redeemButton,
		CodeFeedback = codeFeedback,
	}
end

function RewardsController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local requestRemote = remotes:WaitForChild(Constants.Remotes.RequestRewards) :: RemoteEvent
	local stateRemote = remotes:WaitForChild(Constants.Remotes.RewardState) :: RemoteEvent
	local actionRemote = remotes:WaitForChild(Constants.Remotes.RewardAction) :: RemoteEvent
	local resultRemote = remotes:WaitForChild(Constants.Remotes.RewardResult) :: RemoteEvent

	local ui = buildGui()
	local state: any = { Ready = false }
	local tab = "Streak"
	local claiming = false
	local redeeming = false
	local autoOpened = false
	local claimShimmer = UiKit.shimmer(ui.ClaimButton, 10)

	local menuEntry = MenuBar.add({
		Id = "Rewards",
		Order = 6,
		Icon = "🎁",
		Label = "Premios",
		Key = "J",
		Color = PINK,
		Panels = { PANEL_NAME },
		OnActivate = function()
			PanelManager.toggle(PANEL_NAME)
		end,
	})

	local function feedback(label: TextLabel, text: string, color: Color3)
		label.Text = text
		label.TextColor3 = color
		local token = (label:GetAttribute("Token") or 0) + 1
		label:SetAttribute("Token", token)
		task.delay(4, function()
			if label:GetAttribute("Token") == token then
				label.Text = ""
			end
		end)
	end

	local function countdown(): string
		local remaining = math.max(0, (state.NextDayAt or 0) - Workspace:GetServerTimeNow())
		local hours = math.floor(remaining / 3600)
		local minutes = math.floor((remaining % 3600) / 60)
		return ("%d h %02d min"):format(hours, minutes)
	end

	-- Esperas de los cofres (ChestService): os.clock() en que se vuelven a llenar.
	local chestDeadlines: { [string]: number } = {}
	local chestsKnown = false

	local function renderChests()
		ui.Subtitle.Text = "Cofres escondidos por el bosque: búscalos y ábrelos con E"
		local opened = 0
		for _, chest in ChestConfig.Chests do
			local card = ui.ChestCards[chest.Id]
			local remaining = math.max(0, (chestDeadlines[chest.Id] or 0) - os.clock())
			local waiting = remaining > 0
			if waiting then
				opened += 1
				local hours = math.floor(remaining / 3600)
				local minutes = math.floor((remaining % 3600) / 60)
				card.Icon.Text = "✅"
				card.Status.Text = ("Abierto · se llena en %d h %02d min"):format(hours, minutes)
				card.Status.TextColor3 = THEME.Accent
			else
				card.Icon.Text = "📦"
				card.Status.Text = "🔍 " .. (chest.Hint or "")
				card.Status.TextColor3 = THEME.Muted
			end
			card.Frame.BackgroundTransparency = if waiting then 0.45 else 0.05
			card.Stroke.Color = if waiting then THEME.Accent else THEME.Gold
			card.Stroke.Transparency = if waiting then 0.3 else 0.5
		end
		if not chestsKnown then
			ui.ChestsInfo.Text = "Buscando tus cofres…"
		else
			ui.ChestsInfo.Text = ("%d de %d abiertos ahora · cada cofre se vuelve a llenar a las %d h"):format(opened, #ChestConfig.Chests, ChestConfig.Cooldown // 3600)
		end
		ui.ChestsInfo.TextColor3 = THEME.Text
	end

	local function render()
		for name, button in ui.Tabs do
			button.BackgroundColor3 = if name == tab then THEME.Buy else THEME.Inset
		end
		ui.StreakPage.Visible = tab == "Streak"
		ui.CodesPage.Visible = tab == "Codes"
		ui.ChestsPage.Visible = tab == "Chests"
		if tab == "Codes" then
			ui.Subtitle.Text = "Canjea códigos para conseguir premios"
			return
		end
		if tab == "Chests" then
			renderChests()
			return
		end
		if not state.Ready then
			ui.Subtitle.Text = "Cargando tus premios…"
			ui.ClaimButton.Text = "…"
			UiKit.setDisabled(ui.ClaimButton, true)
			claimShimmer(false)
			return
		end
		ui.Subtitle.Text = "Entra cada día: los premios van subiendo hasta el día " .. #RewardConfig.Streak
		for index, card in ui.Cards do
			local day = state.Days and state.Days[index]
			local icon, text = rewardFace(day)
			card.Icon.Text = icon
			card.Amount.Text = text
			local claimed = index < state.Day or (index == state.Day and state.ClaimedToday)
			local today = index == state.Day and state.CanClaim
			card.Frame.BackgroundTransparency = if claimed then 0.5 else 0.05
			card.Frame.BackgroundColor3 = if today then Color3.fromRGB(70, 60, 30) elseif index == #ui.Cards then Color3.fromRGB(56, 50, 34) else THEME.Inset
			card.Stroke.Color = if today then THEME.Gold elseif claimed then THEME.Accent else THEME.Stroke
			card.Stroke.Transparency = if today then 0 elseif claimed then 0.3 else 0.6
			card.Stroke.Thickness = if today then 3 else 1.5
			card.State.Text = if claimed then "✓" elseif today then "¡Hoy!" else ""
			card.State.TextColor3 = if claimed then THEME.Accent else THEME.Gold
			card.Day.TextColor3 = if today then THEME.Gold else THEME.Muted
		end
		if state.CanClaim then
			ui.StreakInfo.Text = if state.Broken then "Se perdió tu racha: empiezas otra vez por el día 1." elseif state.Streak > 0 then ("🔥 Racha de %d %s. ¡No la pierdas!"):format(state.Streak, if state.Streak == 1 then "día" else "días") else "¡Tu primer premio te espera!"
			ui.StreakInfo.TextColor3 = if state.Broken then THEME.Error else THEME.Text
			ui.ClaimButton.Text = if claiming then "…" else ("Reclamar día %d"):format(state.Day)
			ui.ClaimButton.BackgroundColor3 = THEME.Buy
			UiKit.setDisabled(ui.ClaimButton, claiming)
			claimShimmer(not claiming)
		else
			ui.StreakInfo.Text = ("🔥 Racha de %d %s"):format(state.Streak, if state.Streak == 1 then "día" else "días")
			ui.StreakInfo.TextColor3 = THEME.Text
			ui.ClaimButton.Text = "Siguiente premio en " .. countdown()
			ui.ClaimButton.BackgroundColor3 = THEME.Disabled
			UiKit.setDisabled(ui.ClaimButton, true)
			claimShimmer(false)
		end
	end

	local function refreshMenu()
		local ready = player:GetAttribute(Constants.Attributes.DailyReady) == true
		menuEntry.setBadge(if ready then "!" else nil)
		menuEntry.setAttention(ready, PINK)
	end

	-- Abrir solo una vez al entrar si hay premio (sin interrumpir el tutorial ni otro panel).
	local function maybeAutoOpen()
		if autoOpened or not RewardConfig.AutoOpen or not state.Ready or not state.CanClaim then
			return
		end
		autoOpened = true
		task.delay(RewardConfig.AutoOpenDelay, function()
			local tutorial = player:GetAttribute(Constants.Attributes.TutorialStatus)
			if tutorial == "Active" or PanelManager.current() ~= nil then
				return
			end
			if state.CanClaim then
				tab = "Streak"
				PanelManager.open(PANEL_NAME)
			end
		end)
	end

	stateRemote.OnClientEvent:Connect(function(data)
		if typeof(data) ~= "table" then
			return
		end
		state = data
		claiming = false
		render()
		maybeAutoOpen()
	end)

	resultRemote.OnClientEvent:Connect(function(success: boolean, code: string, action: string, detail: any)
		if action == "Claim" then
			claiming = false
		elseif action == "Redeem" then
			redeeming = false
			ui.RedeemButton.Text = "Canjear"
			UiKit.setDisabled(ui.RedeemButton, false)
		end
		if not success then
			local message = MESSAGES[code] or tostring(code)
			if code == "RebirthLocked" and typeof(detail) == "table" and typeof(detail.Required) == "number" then
				message = ("Ese código pide 🔄 %d renacimientos."):format(detail.Required)
			end
			feedback(if action == "Redeem" then ui.CodeFeedback else ui.StreakFeedback, message, THEME.Error)
			render()
			return
		end
		-- Lo concedido (ya sumado en el servidor).
		local parts = {}
		if typeof(detail) == "table" then
			if typeof(detail.Energy) == "number" then
				table.insert(parts, "+" .. formatNumber(detail.Energy) .. " ⚡")
			end
			local blessings = blessingText(detail.Blessings)
			if blessings ~= "" then
				table.insert(parts, blessings)
			end
			if typeof(detail.PetId) == "string" then
				local pet = PetConfig.Pets[detail.PetId]
				table.insert(parts, "🐾 " .. (if pet then pet.DisplayName else detail.PetId))
			end
		end
		local summary = table.concat(parts, "  ·  ")
		local hint = if typeof(detail) == "table" and detail.Blessings then " (actívala en 🧿 Amuletos)" else ""
		if action == "Claim" then
			feedback(ui.StreakFeedback, "¡Premio recibido! " .. summary, THEME.BuyHighlight)
			Toasts.show(("🎁 Día %s: %s%s"):format(tostring(typeof(detail) == "table" and detail.Day or "?"), summary, hint), { Color = PINK, Duration = 5 })
			Juice.burst(ui.ClaimButton, THEME.Gold, 16, 160)
			Juice.sound(Juice.Sounds.HatchRare)
		else
			ui.CodeBox.Text = ""
			feedback(ui.CodeFeedback, "¡Código canjeado! " .. summary .. hint, THEME.BuyHighlight)
			Toasts.show("🎫 Código canjeado: " .. summary, { Color = PINK, Duration = 5 })
			Juice.burst(ui.RedeemButton, PINK, 14, 140)
			Juice.sound(Juice.Sounds.Upgrade)
		end
		if typeof(detail) == "table" and detail.InventoryFull then
			Toasts.show("Inventario lleno: la mascota del premio se cambió por energía.", { Color = THEME.Gold })
		end
		render()
	end)

	ui.ClaimButton.Activated:Connect(function()
		if claiming or not state.CanClaim then
			return
		end
		claiming = true
		render()
		actionRemote:FireServer("Claim")
		task.delay(6, function()
			if claiming then
				claiming = false
				render()
			end
		end)
	end)

	local function redeem()
		if redeeming then
			return
		end
		local text = ui.CodeBox.Text
		if text:gsub("%s", "") == "" then
			feedback(ui.CodeFeedback, "Escribe un código primero.", THEME.Error)
			return
		end
		redeeming = true
		ui.RedeemButton.Text = "…"
		UiKit.setDisabled(ui.RedeemButton, true)
		actionRemote:FireServer("Redeem", string.sub(text, 1, 64))
		task.delay(6, function()
			if redeeming then
				redeeming = false
				ui.RedeemButton.Text = "Canjear"
				UiKit.setDisabled(ui.RedeemButton, false)
			end
		end)
	end
	ui.RedeemButton.Activated:Connect(redeem)
	ui.CodeBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			redeem()
		end
	end)

	-- Cofres: el mismo estado que pinta ChestController en el mundo.
	local chestStateRemote = remotes:WaitForChild(Constants.Remotes.ChestState) :: RemoteEvent
	local chestRequestRemote = remotes:WaitForChild(Constants.Remotes.RequestChests) :: RemoteEvent
	chestStateRemote.OnClientEvent:Connect(function(chestState: any, serverNow: any)
		if typeof(chestState) ~= "table" or typeof(serverNow) ~= "number" then
			return
		end
		chestsKnown = true
		table.clear(chestDeadlines)
		for chestId, readyAt in chestState do
			if typeof(chestId) == "string" and typeof(readyAt) == "number" and readyAt > serverNow then
				chestDeadlines[chestId] = os.clock() + (readyAt - serverNow)
			end
		end
		if tab == "Chests" then
			render()
		end
	end)

	-- Navegación ---------------------------------------------------------------------------
	local openToken = 0
	PanelManager.register(PANEL_NAME, ui.Panel, {
		OnOpen = function()
			requestRemote:FireServer()
			chestRequestRemote:FireServer()
			render()
			openToken += 1
			local token = openToken
			task.spawn(function()
				while openToken == token do
					task.wait(20)
					if openToken == token and tab == "Streak" and state.Ready and not state.CanClaim then
						render()
					end
				end
			end)
			task.spawn(function()
				while openToken == token do
					task.wait(1)
					if openToken == token and tab == "Chests" then
						renderChests()
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
			render()
		end)
	end
	ui.Close.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.J then
			PanelManager.toggle(PANEL_NAME)
		end
	end)
	player:GetAttributeChangedSignal(Constants.Attributes.DailyReady):Connect(function()
		refreshMenu()
		if player:GetAttribute(Constants.Attributes.DailyReady) == true then
			requestRemote:FireServer() -- día nuevo: estado al día
		end
	end)
	refreshMenu()
	render()
	requestRemote:FireServer()
	-- El latido del azulejo no tapa el resto: se apaga mientras el panel está abierto.
	PanelManager.Changed:Connect(function(openPanel: string?)
		if openPanel == PANEL_NAME then
			menuEntry.setAttention(false)
		else
			refreshMenu()
		end
	end)
end

return RewardsController
