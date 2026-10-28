-- AdventureController · Amulets: panel de amuletos, historias, bendiciones y tarjeta de celebración.
-- Parte de AdventureController (ver AdventureController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AdventureConfig = require(Shared.Config.AdventureConfig)
local AdventureLogic = require(Shared.AdventureLogic)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.Parent.UI.PanelManager)

local ctx: any -- tabla de estado compartida (la crea AdventureController/init.luau)
local AMULET_PANEL: any
local AMULET_PANEL_SIZE: any
local COLORS: any
local FONTS: any
local THEME: any

-- Funciones de las otras partes
local function clockText(...) return ctx.clockText(...) end
local function fullName(...) return ctx.fullName(...) end
local function npcState(...) return ctx.npcState(...) end
local function objectiveText(...) return ctx.objectiveText(...) end
local function playSound(...) return ctx.playSound(...) end
local function rowFrame(...) return ctx.rowFrame(...) end
local function sectionTitle(...) return ctx.sectionTitle(...) end
local function serverNow(...) return ctx.serverNow(...) end

local Part = { Api = {} }

function Part.start()
	local actionRemote = ctx.actionRemote
	local amulets = ctx.amulets
	local celebration = ctx.celebration
	local menuEntry = ctx.menuEntry
	local requestRemote = ctx.requestRemote
	local screenGui = ctx.screenGui

	-- Panel de amuletos -------------------------------------------------------------------------
	local function feedbackAmulets(text: string, color: Color3)
		amulets.Feedback.Text = text
		amulets.Feedback.TextColor3 = color
		task.delay(3, function()
			if amulets.Feedback.Text == text then
				amulets.Feedback.Text = ""
			end
		end)
	end

	local function clearList()
		for _, child in amulets.List:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function smallButton(parent: Instance, text: string, color: Color3, onClick: () -> ()): TextButton
		local button = UiKit.button(parent, "Action", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(112, 36),
			BackgroundColor3 = color,
			TextSize = 16,
			Text = text,
		})
		button.Activated:Connect(onClick)
		return button
	end

	local timerLabels: { [string]: TextLabel } = {}
	local function blessingText(blessingId: string, now: number): (string, boolean)
		local blessing = AdventureConfig.Blessings[blessingId]
		local expires = ctx.state.Active and ctx.state.Active[blessingId]
		if expires and expires > now then
			return ("%s · activa: %s"):format(blessing.Description, clockText(expires - now)), true
		end
		return ("%s durante %d min"):format(blessing.Description, blessing.Duration // 60), false
	end

	local function renderAmulets()
		clearList()
		timerLabels = {}
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		local equipped = ctx.state.Equipped or { "", "" }
		local slots = ctx.state.Slots or 1
		local owned = {}
		for _, amuletId in ctx.state.Amulets or {} do
			owned[amuletId] = true
		end
		local giverOf = {}
		for npcId, npc in AdventureConfig.Npcs do
			if npc.Amulet then
				giverOf[npc.Amulet] = npcId
			end
		end

		-- Ranuras
		sectionTitle(amulets.List, "Amuletos puestos", nextOrder())
		local slotRow = UiKit.create("Frame", { Name = "Slots", Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1, LayoutOrder = nextOrder() }, amulets.List)
		UiKit.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, slotRow)
		for slot = 1, AdventureConfig.MaxSlots do
			local card = UiKit.create("Frame", { Name = "Slot" .. slot, Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = THEME.Inset, BackgroundTransparency = 0.2, LayoutOrder = slot }, slotRow)
			UiKit.corner(card, 12)
			local amulet = AdventureConfig.Amulets[equipped[slot] or ""]
			local open = slot <= slots
			UiKit.stroke(card, if amulet then amulet.Color else THEME.Stroke, if amulet then 2 else 1, if amulet then 0 else 0.5)
			UiKit.text(card, "Label", {
				Position = UDim2.fromOffset(12, 6),
				Size = UDim2.new(1, -100, 0, 28),
				Font = FONTS.Display,
				TextSize = 18,
				TextColor3 = if open then THEME.Text else THEME.Muted,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = if amulet then ("%s %s"):format(amulet.Icon, amulet.DisplayName) elseif open then ("Ranura %d: vacía"):format(slot) else ("🔒 Ranura %d"):format(slot),
			})
			UiKit.text(card, "Hint", {
				Position = UDim2.fromOffset(12, 34),
				Size = UDim2.new(1, -100, 0, 20),
				Font = FONTS.Light,
				TextSize = 13,
				TextColor3 = THEME.Muted,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = if amulet then amulet.Description elseif open then "Elige un amuleto abajo" else "Termina las 4 historias",
			})
			if amulet then
				local remove = smallButton(card, "Quitar", THEME.Secondary, function()
					actionRemote:FireServer("Unequip", slot)
				end)
				remove.Size = UDim2.fromOffset(80, 32)
			end
		end

		-- Amuletos
		sectionTitle(amulets.List, "Colección", nextOrder())
		for _, amuletId in AdventureLogic.amuletOrder() do
			local amulet = AdventureConfig.Amulets[amuletId]
			local row = rowFrame(amulets.List, amuletId, 62, nextOrder())
			local has = owned[amuletId] == true
			local isOn = table.find(equipped, amuletId) ~= nil
			UiKit.stroke(row, if isOn then amulet.Color else THEME.Stroke, if isOn then 2 else 1, if isOn then 0 else 0.6)
			UiKit.text(row, "Icon", {
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.fromOffset(44, 62),
				Font = FONTS.Display,
				TextSize = 32,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTransparency = if has then 0 else 0.6,
				Text = amulet.Icon,
			})
			UiKit.text(row, "Name", {
				Position = UDim2.fromOffset(60, 8),
				Size = UDim2.new(1, -190, 0, 22),
				Font = FONTS.Display,
				TextSize = 18,
				TextColor3 = if has then amulet.Color else THEME.Muted,
				Text = amulet.DisplayName,
			})
			local giver = giverOf[amuletId] and AdventureConfig.Npcs[giverOf[amuletId]]
			UiKit.text(row, "Description", {
				Position = UDim2.fromOffset(60, 32),
				Size = UDim2.new(1, -190, 0, 20),
				Font = FONTS.Light,
				TextSize = 14,
				TextColor3 = THEME.Muted,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = if has then amulet.Description else ("🔒 Termina la historia de %s"):format(if giver then giver.DisplayName else "un personaje"),
			})
			if has then
				if isOn then
					local label = smallButton(row, "Puesto ✓", THEME.Inset, function() end)
					UiKit.setDisabled(label, true)
				else
					smallButton(row, "Ponerme", THEME.Buy, function()
						actionRemote:FireServer("Equip", amuletId)
					end)
				end
			end
		end

		-- Bendiciones
		sectionTitle(amulets.List, "Bendiciones", nextOrder())
		local now = serverNow()
		for _, blessingId in AdventureLogic.blessingOrder() do
			local blessing = AdventureConfig.Blessings[blessingId]
			local row = rowFrame(amulets.List, blessingId, 62, nextOrder())
			local count = ctx.state.Blessings and ctx.state.Blessings[blessingId] or 0
			local expires = ctx.state.Active and ctx.state.Active[blessingId]
			local active = expires and expires > now
			UiKit.stroke(row, if active then blessing.Color else THEME.Stroke, if active then 2 else 1, if active then 0 else 0.6)
			UiKit.text(row, "Icon", {
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.fromOffset(44, 62),
				Font = FONTS.Display,
				TextSize = 32,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTransparency = if count > 0 or active then 0 else 0.6,
				Text = blessing.Icon,
			})
			UiKit.text(row, "Name", {
				Position = UDim2.fromOffset(60, 8),
				Size = UDim2.new(1, -190, 0, 22),
				Font = FONTS.Display,
				TextSize = 18,
				TextColor3 = blessing.Color,
				Text = ("%s  ×%d"):format(blessing.DisplayName, count),
			})
			timerLabels[blessingId] = UiKit.text(row, "Description", {
				Position = UDim2.fromOffset(60, 32),
				Size = UDim2.new(1, -190, 0, 20),
				Font = FONTS.Light,
				TextSize = 14,
				TextColor3 = if active then THEME.BuyHighlight else THEME.Muted,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = (blessingText(blessingId, now)),
			})
			local use = smallButton(row, if active then "Alargar" else "Usar", if count > 0 then THEME.Buy else THEME.Disabled, function()
				actionRemote:FireServer("UseBlessing", blessingId)
			end)
			UiKit.setDisabled(use, count <= 0)
		end

		-- Historias
		sectionTitle(amulets.List, "Historias", nextOrder())
		for _, npcId in AdventureLogic.npcOrder() do
			local npc = AdventureConfig.Npcs[npcId]
			local st = npcState(npcId)
			local row = rowFrame(amulets.List, npcId, 58, nextOrder())
			local done = if st.Status == "Done" then st.Steps else st.Step - 1
			local dots = string.rep("●", done) .. string.rep("○", st.Steps - done)
			UiKit.text(row, "Name", {
				Position = UDim2.fromOffset(14, 6),
				Size = UDim2.new(1, -150, 0, 22),
				Font = FONTS.Display,
				TextSize = 17,
				Text = fullName(npc),
			})
			UiKit.text(row, "Where", {
				Position = UDim2.fromOffset(14, 30),
				Size = UDim2.new(1, -150, 0, 20),
				Font = FONTS.Light,
				TextSize = 13,
				TextColor3 = THEME.Muted,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = if st.Status == "Done" then "Historia completada ✓" elseif st.Status == "Offer" then "📍 " .. npc.Where else objectiveText(npcId, st),
			})
			UiKit.text(row, "Dots", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -14, 0.5, 0),
				Size = UDim2.fromOffset(120, 30),
				Font = FONTS.Display,
				TextSize = 20,
				TextColor3 = if st.Status == "Done" then COLORS.Ready else THEME.Gold,
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = dots,
			})
		end
	end

	PanelManager.register(AMULET_PANEL, amulets.Panel, {
		OnOpen = function()
			requestRemote:FireServer()
			renderAmulets()
		end,
	})
	UiKit.bindModalLayout(screenGui, amulets.Scale, AMULET_PANEL_SIZE, function(position)
		PanelManager.setBasePosition(AMULET_PANEL, position)
	end)
	amulets.Close.Activated:Connect(function()
		PanelManager.close(AMULET_PANEL)
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.G then
			PanelManager.toggle(AMULET_PANEL)
		end
	end)
	PanelManager.Changed:Connect(function(openPanel: string?)
		if openPanel == AMULET_PANEL then
			menuEntry.shimmer(false)
		end
	end)

	-- Celebración ---------------------------------------------------------------------------------
	local celebrationAmulet: string? = nil
	local function celebrate(amuletId: string)
		local amulet = AdventureConfig.Amulets[amuletId]
		if not amulet then
			return
		end
		celebrationAmulet = amuletId
		celebration.Icon.Text = amulet.Icon
		celebration.ItemName.Text = amulet.DisplayName
		celebration.ItemName.TextColor3 = amulet.Color
		celebration.Description.Text = amulet.Description
		if celebration.Stroke then
			celebration.Stroke.Color = amulet.Color
			celebration.Stroke.Transparency = 0
			celebration.Stroke.Thickness = 3
		end
		local isOn = table.find(ctx.state.Equipped or {}, amuletId) ~= nil
		celebration.Equip.Visible = not isOn
		celebration.Ok.Position = if isOn then UDim2.new(0.5, 0, 1, -20) else UDim2.new(0.5, 84, 1, -20)
		celebration.Gui.Enabled = true
		local scale = celebration.Card:FindFirstChildOfClass("UIScale")
		if scale then
			local target = scale.Scale
			scale.Scale = target * 0.6
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
		end
		playSound(AdventureConfig.Sounds.Reward)
	end
	celebration.Ok.Activated:Connect(function()
		celebration.Gui.Enabled = false
	end)
	celebration.Equip.Activated:Connect(function()
		celebration.Gui.Enabled = false
		if celebrationAmulet then
			actionRemote:FireServer("Equip", celebrationAmulet)
		end
	end)

	ctx.blessingText = blessingText
	ctx.celebrate = celebrate
	ctx.feedbackAmulets = feedbackAmulets
	ctx.renderAmulets = renderAmulets
	ctx.timerLabels = timerLabels
end

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	AMULET_PANEL = context.AMULET_PANEL
	AMULET_PANEL_SIZE = context.AMULET_PANEL_SIZE
	COLORS = context.COLORS
	FONTS = context.FONTS
	THEME = context.THEME
end

return Part
