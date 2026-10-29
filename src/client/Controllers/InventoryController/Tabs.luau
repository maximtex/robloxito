-- InventoryController · Tabs: arranque de remotes, insignias de novedades y renderizado de las cuatro pestañas (Armas, Huevos, Artículos y Títulos).
-- Parte de InventoryController (ver InventoryController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ItemConfig = require(Shared.Config.ItemConfig)
local EggConfig = require(Shared.Config.EggConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local ItemLogic = require(Shared.ItemLogic)
local formatNumber = require(Shared.Util.FormatNumber)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.Parent.UI.PanelManager)
local MenuBar = require(script.Parent.Parent.Parent.UI.MenuBar)
local Juice = require(script.Parent.Parent.Parent.UI.Juice)

local ctx: any -- tabla de estado compartida (la crea InventoryController/init.luau)
local CELL: any
local FONTS: any
local INK: any
local INVENTORY_COLOR: any
local PANEL_NAME: any
local TABS: any
local TAB_ON: any
local THEME: any
local player: any

-- Funciones de las otras partes
local function amount(...) return ctx.amount(...) end
local function buildGui(...) return ctx.buildGui(...) end
local function countLabel(...) return ctx.countLabel(...) end
local function darker(...) return ctx.darker(...) end
local function drawEgg(...) return ctx.drawEgg(...) end
local function drawPotion(...) return ctx.drawPotion(...) end
local function eggLook(...) return ctx.eggLook(...) end
local function label(...) return ctx.label(...) end
local function tileButton(...) return ctx.tileButton(...) end

local Part = { Api = {} }

function Part.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local actionRemote = remotes:WaitForChild(Constants.Remotes.ItemAction) :: RemoteEvent
	local resultRemote = remotes:WaitForChild(Constants.Remotes.ItemResult) :: RemoteEvent
	local stateRemote = remotes:WaitForChild(Constants.Remotes.ItemState) :: RemoteEvent
	local requestRemote = remotes:WaitForChild(Constants.Remotes.RequestItems) :: RemoteEvent
	local weaponRemote = remotes:WaitForChild(Constants.Remotes.WeaponAction) :: RemoteEvent
	local ui = buildGui()

	local unseen: { [string]: number } = {} -- cosas nuevas por pestaña (desde la última vez que se vio)

	local entry = MenuBar.add({
		Id = "Inventory",
		Order = 4,
		Icon = "🎒",
		Label = "Inventario",
		Key = "I",
		Color = INVENTORY_COLOR,
		Panels = { PANEL_NAME },
		OnActivate = function()
			PanelManager.toggle(PANEL_NAME)
		end,
	})

	local function refreshBadges()
		local total = 0
		for _, tab in TABS do
			local count = unseen[tab.Id] or 0
			ui.Tabs[tab.Id].New.Visible = count > 0
			total += count
		end
		entry.setBadge(if total > 0 then tostring(total) else nil)
	end

	local function markNew(tabId: string, count: number)
		if PanelManager.isOpen(PANEL_NAME) and ctx.currentTab == tabId then
			return
		end
		unseen[tabId] = (unseen[tabId] or 0) + count
		refreshBadges()
	end

	local function selectTab(tabId: string)
		ctx.currentTab = tabId
		unseen[tabId] = nil
		refreshBadges()
		for id, tab in ui.Tabs do
			local on = id == tabId
			tab.Button.BackgroundColor3 = if on then TAB_ON else THEME.Inset
			tab.Stroke.Color = if on then Color3.fromRGB(150, 220, 255) else INK
		end
		ctx.render()
	end

	local function clearList()
		for _, child in ui.List:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function showEmpty(text: string?)
		ui.Empty.Visible = text ~= nil
		ui.Empty.Text = text or ""
	end

	-- Armas: las que tiene ("Laser:3,PlasmaBlaster:0") en el orden de la Armería.
	local function ownedWeapons(): { { Id: string, Level: number } }
		local owned = {}
		local text = player:GetAttribute(Constants.Attributes.Weapons)
		if typeof(text) == "string" then
			for id, level in string.gmatch(text, "([%w_]+):(%d+)") do
				if WeaponConfig.Weapons[id] then
					table.insert(owned, { Id = id, Level = tonumber(level) or 0 })
				end
			end
		end
		table.sort(owned, function(a, b)
			return (WeaponConfig.Weapons[a.Id].Order or 0) < (WeaponConfig.Weapons[b.Id].Order or 0)
		end)
		return owned
	end

	local function renderWeapons()
		ui.Grid.CellSize = UDim2.fromOffset(CELL, CELL + 18)
		local owned = ownedWeapons()
		local equipped = player:GetAttribute(Constants.Attributes.EquippedWeapon)
		ui.Hint.Text = amount(#owned, "arma", "armas") .. " • Haz clic en un arma para equiparla"
		showEmpty(if #owned == 0 then "Aún no tienes armas." else nil)
		for order, weapon in owned do
			local def = WeaponConfig.Weapons[weapon.Id]
			local colors = def.CardColors or { THEME.Secondary, THEME.Secondary, THEME.Inset }
			local tile = tileButton(ui.List, weapon.Id, Color3.new(1, 1, 1), order)
			local gradient = tile:FindFirstChildOfClass("UIGradient")
			if gradient then
				gradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, colors[1]),
					ColorSequenceKeypoint.new(0.55, colors[2]),
					ColorSequenceKeypoint.new(1, colors[3]),
				})
			end
			if typeof(def.Art) == "string" and def.Art ~= "" then
				UiKit.create("ImageLabel", {
					Name = "Art",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.44),
					Size = UDim2.fromOffset(84, 84),
					BackgroundTransparency = 1,
					ScaleType = Enum.ScaleType.Fit,
					Image = def.Art,
					ZIndex = 2,
				}, tile)
			else
				label(tile, "Icon", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.42),
					Size = UDim2.fromOffset(58, 58),
					Font = FONTS.Display,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Center,
					Text = def.Icon or "⚔️",
					ZIndex = 2,
				})
			end
			label(tile, "Name", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -4),
				Size = UDim2.new(1, -10, 0, 20),
				Font = FONTS.Display,
				TextSize = 15,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = def.DisplayName,
				ZIndex = 3,
			}, 2)
			label(tile, "Level", {
				Position = UDim2.fromOffset(8, 5),
				Size = UDim2.fromOffset(60, 20),
				Font = FONTS.Display,
				TextSize = 16,
				Text = "Nv. " .. weapon.Level,
				ZIndex = 3,
			}, 2)
			if weapon.Id == equipped then
				local badge = UiKit.create("Frame", {
					Name = "Equipped",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 6, 0, -8),
					Size = UDim2.fromOffset(30, 30),
					BackgroundColor3 = THEME.Accent,
					ZIndex = 5,
				}, tile)
				UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, badge)
				UiKit.stroke(badge, INK, 2.5, 0)
				label(badge, "Check", {
					Size = UDim2.fromScale(1, 1),
					Font = FONTS.Display,
					TextSize = 20,
					TextXAlignment = Enum.TextXAlignment.Center,
					Text = "✓",
					ZIndex = 6,
				}, 2)
				local stroke = tile:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = THEME.Gold
				end
			end
			tile.Activated:Connect(function()
				if weapon.Id ~= player:GetAttribute(Constants.Attributes.EquippedWeapon) then
					weaponRemote:FireServer("Equip", weapon.Id)
					Juice.sound(Juice.Sounds.Upgrade)
				end
			end)
		end
	end

	local function renderEggs()
		ui.Grid.CellSize = UDim2.fromOffset(CELL, CELL + 18)
		local ids = {}
		local total = 0
		for eggId, count in ctx.state.Eggs do
			if EggConfig.Eggs[eggId] and count > 0 then
				table.insert(ids, eggId)
				total += count
			end
		end
		table.sort(ids, function(a, b)
			return (EggConfig.Eggs[a].Order or 0) < (EggConfig.Eggs[b].Order or 0)
		end)
		ui.Hint.Text = amount(total, "huevo", "huevos") .. " • Haz clic en un huevo para abrirlo"
		showEmpty(if #ids == 0 then "No tienes huevos guardados.\n¡Los jefes a veces sueltan uno!" else nil)
		for order, eggId in ids do
			local name, color = eggLook(eggId)
			local tile = tileButton(ui.List, eggId, darker(color, 0.55), order)
			drawEgg(tile, color, 54, 68, UDim2.fromScale(0.5, 0.42))
			label(tile, "Name", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -4),
				Size = UDim2.new(1, -10, 0, 20),
				Font = FONTS.Display,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = name,
				ZIndex = 3,
			}, 2)
			local count = UiKit.create("Frame", { Name = "CountHolder", Size = UDim2.new(1, 0, 1, -18), BackgroundTransparency = 1 }, tile)
			countLabel(count, ctx.state.Eggs[eggId])
			tile.Activated:Connect(function()
				actionRemote:FireServer("OpenEgg", eggId)
			end)
		end
	end

	local function renderPotions()
		ui.Grid.CellSize = UDim2.fromOffset(CELL, CELL)
		local ids = {}
		local total = 0
		for _, potionId in ItemLogic.potionOrder() do
			local count = ctx.state.Potions[potionId] or 0
			if count > 0 or ctx.boostEnds[potionId] then
				table.insert(ids, potionId)
				total += count
			end
		end
		ui.Hint.Text = amount(total, "poción", "pociones") .. " • Haz clic en una poción para usarla"
		showEmpty(if #ids == 0 then "No tienes pociones.\n¡Derrota jefes para conseguirlas!" else nil)
		for order, potionId in ids do
			local def = ItemConfig.Potions[potionId]
			local count = ctx.state.Potions[potionId] or 0
			local tile = tileButton(ui.List, potionId, darker(def.Color, 0.6), order)
			drawPotion(tile, def, 80)
			if count > 0 then
				countLabel(tile, count)
			else
				UiKit.setDisabled(tile, true)
				tile.BackgroundTransparency = 0.3
			end
			local timer = label(tile, "Active", {
				Position = UDim2.fromOffset(6, 4),
				Size = UDim2.new(1, -12, 0, 20),
				Font = FONTS.Display,
				TextSize = 16,
				TextColor3 = THEME.Gold,
				Visible = false,
				ZIndex = 4,
			}, 2)
			timer:SetAttribute("Potion", potionId)
			tile.Activated:Connect(function()
				if (ctx.state.Potions[potionId] or 0) > 0 then
					actionRemote:FireServer("UsePotion", potionId)
				end
			end)
			local tip = def.DisplayName .. ": " .. def.Description
			tile.MouseEnter:Connect(function()
				ui.Hint.Text = tip
			end)
			tile.MouseLeave:Connect(function()
				ui.Hint.Text = amount(total, "poción", "pociones") .. " • Haz clic en una poción para usarla"
			end)
		end
	end

	local function renderTitles()
		ui.Grid.CellSize = UDim2.new(1, 0, 0, 66)
		local ownedCount = 0
		for titleId in ctx.state.Titles do
			if ItemConfig.Titles[titleId] then
				ownedCount += 1
			end
		end
		ui.Hint.Text = amount(ownedCount, "título", "títulos") .. " • Haz clic en uno para llevarlo encima de tu cabeza"
		showEmpty(nil)
		for order, titleId in ItemLogic.titleOrder() do
			local def = ItemConfig.Titles[titleId]
			local owned = ctx.state.Titles[titleId] == true
			local equipped = ctx.state.Title == titleId
			local row = UiKit.create("TextButton", {
				Name = titleId,
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = if equipped then darker(def.Color, 0.45) else THEME.Panel,
				LayoutOrder = if owned then order else 100 + order,
			}, ui.List)
			UiKit.corner(row, 12)
			UiKit.stroke(row, if equipped then THEME.Gold else INK, if equipped then 3 else 2.5, 0)
			UiKit.addStates(row)
			UiKit.create("Frame", {
				Name = "Strip",
				Position = UDim2.fromOffset(8, 10),
				Size = UDim2.new(0, 8, 1, -20),
				BackgroundColor3 = if owned then def.Color else THEME.Disabled,
			}, row)
			label(row, "Name", {
				Position = UDim2.fromOffset(26, 8),
				Size = UDim2.new(1, -170, 0, 28),
				Font = FONTS.Display,
				TextSize = 22,
				TextColor3 = if owned then def.Color else THEME.Muted,
				Text = (if owned then "" else "🔒 ") .. def.DisplayName,
			}, 2)
			label(row, "Description", {
				Position = UDim2.fromOffset(26, 36),
				Size = UDim2.new(1, -170, 0, 20),
				Font = FONTS.Body,
				TextSize = 14,
				TextColor3 = THEME.Muted,
				Text = def.Description,
			})
			local status = label(row, "Status", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -14, 0.5, 0),
				Size = UDim2.fromOffset(140, 30),
				Font = FONTS.Display,
				TextSize = 18,
				TextXAlignment = Enum.TextXAlignment.Right,
			}, 2)
			if equipped then
				status.Text = "✓ PUESTO"
				status.TextColor3 = THEME.Gold
			elseif owned then
				status.Text = "Ponerlo"
				status.TextColor3 = THEME.BuyHighlight
			else
				local progress = ctx.state.Progress[titleId]
				local value, goal = if progress then progress[1] else 0, if progress then progress[2] else 1
				if goal > 1 then
					status.Text = formatNumber(math.min(value, goal)) .. " / " .. formatNumber(goal)
				else
					status.Text = "Pendiente"
				end
				status.TextColor3 = THEME.Muted
				UiKit.setDisabled(row, true)
				if goal > 1 then
					local bar = UiKit.create("Frame", {
						Name = "Bar",
						AnchorPoint = Vector2.new(1, 1),
						Position = UDim2.new(1, -14, 1, -8),
						Size = UDim2.fromOffset(130, 8),
						BackgroundColor3 = THEME.Inset,
					}, row)
					UiKit.corner(bar, 4)
					local fill = UiKit.create("Frame", {
						Name = "Fill",
						Size = UDim2.fromScale(math.clamp(value / goal, 0, 1), 1),
						BackgroundColor3 = def.Color,
					}, bar)
					UiKit.corner(fill, 4)
				end
			end
			row.Activated:Connect(function()
				if not owned then
					return
				end
				actionRemote:FireServer("EquipTitle", if equipped then "" else titleId)
			end)
		end
	end

	ctx.render = function()
		clearList()
		if not ctx.state.Ready and ctx.currentTab ~= "Weapons" then
			ui.Hint.Text = "Cargando…"
			showEmpty("Cargando tus datos…")
			return
		end
		if ctx.currentTab == "Weapons" then
			renderWeapons()
		elseif ctx.currentTab == "Eggs" then
			renderEggs()
		elseif ctx.currentTab == "Potions" then
			renderPotions()
		else
			renderTitles()
		end
	end

	for _, tab in TABS do
		ui.Tabs[tab.Id].Button.Activated:Connect(function()
			selectTab(tab.Id)
		end)
	end

	ctx.entry = entry
	ctx.markNew = markNew
	ctx.requestRemote = requestRemote
	ctx.resultRemote = resultRemote
	ctx.selectTab = selectTab
	ctx.stateRemote = stateRemote
	ctx.ui = ui
end

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	CELL = context.CELL
	FONTS = context.FONTS
	INK = context.INK
	INVENTORY_COLOR = context.INVENTORY_COLOR
	PANEL_NAME = context.PANEL_NAME
	TABS = context.TABS
	TAB_ON = context.TAB_ON
	THEME = context.THEME
	player = context.player
end

return Part
