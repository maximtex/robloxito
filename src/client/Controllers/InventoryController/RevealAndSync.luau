-- InventoryController · RevealAndSync: presentación 3D al abrir un huevo, sincronización con el servidor, avisos de botín y cuenta atrás de pociones.
-- Parte de InventoryController (ver InventoryController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ItemConfig = require(Shared.Config.ItemConfig)
local PetConfig = require(Shared.Config.PetConfig)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.Parent.UI.PanelManager)
local Toasts = require(script.Parent.Parent.Parent.UI.Toasts)
local Juice = require(script.Parent.Parent.Parent.UI.Juice)
local PetModelBuilder = require(script.Parent.Parent.Parent.Pets.PetModelBuilder)

local ctx: any -- tabla de estado compartida (la crea InventoryController/init.luau)
local MESSAGES: any
local PANEL_NAME: any
local PANEL_SIZE: any
local THEME: any
local player: any

-- Funciones de las otras partes
local function clockText(...) return ctx.clockText(...) end
local function eggLook(...) return ctx.eggLook(...) end
local function markNew(...) return ctx.markNew(...) end
local function rarityOf(...) return ctx.rarityOf(...) end
local function selectTab(...) return ctx.selectTab(...) end

local Part = { Api = {} }

function Part.start()
	local entry = ctx.entry
	local requestRemote = ctx.requestRemote
	local resultRemote = ctx.resultRemote
	local stateRemote = ctx.stateRemote
	local ui = ctx.ui

	-- Presentación de la mascota ------------------------------------------------------------
	local spinConnection: RBXScriptConnection? = nil
	local function closeReveal()
		ui.Reveal.Visible = false
		if spinConnection then
			spinConnection:Disconnect()
			spinConnection = nil
		end
		for _, child in ui.Viewport:GetChildren() do
			if not child:IsA("Camera") then
				child:Destroy()
			end
		end
	end
	local function showReveal(detail: any)
		closeReveal()
		local petId = detail.PetId
		local pet = PetConfig.Pets[petId]
		local rarity = rarityOf(petId)
		ui.Glow.BackgroundColor3 = rarity.Color
		ui.RevealName.Text = if pet then pet.DisplayName else tostring(petId)
		ui.RevealName.TextColor3 = rarity.Color
		ui.RevealInfo.Text = rarity.DisplayName .. "  ·  " .. (if detail.AutoEquipped then "✓ Equipada automáticamente" else "Guardada en tus mascotas")
		local model = PetModelBuilder.build(petId)
		if model then
			model.Parent = ui.Viewport
			local size = model:GetExtentsSize()
			local distance = math.max(size.X, size.Y, size.Z) * 1.7 + 2.5
			local startedAt = os.clock()
			spinConnection = RunService.RenderStepped:Connect(function()
				local angle = (os.clock() - startedAt) * 0.9
				ui.Camera.CFrame = CFrame.lookAt(Vector3.new(math.sin(angle) * distance, size.Y * 0.25, -math.cos(angle) * distance), Vector3.new(0, size.Y * 0.1, 0))
			end)
		end
		ui.Reveal.Visible = true
		local scale = ui.RevealCard:FindFirstChildOfClass("UIScale") or UiKit.create("UIScale", {}, ui.RevealCard)
		scale.Scale = 0.6
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		local order = rarity.Order or 1
		Juice.burst(ui.Viewport, rarity.Color, 8 + order * 5, 130 + order * 20)
		Juice.sound(Juice.Sounds.Hatch)
		if order >= 4 then
			Juice.sound(Juice.Sounds.HatchEpic)
		elseif order >= 3 then
			Juice.sound(Juice.Sounds.HatchRare)
		end
	end
	ui.RevealOk.Activated:Connect(closeReveal)
	ui.Reveal.Activated:Connect(closeReveal)

	-- Estado del servidor --------------------------------------------------------------------
	stateRemote.OnClientEvent:Connect(function(newState: any)
		if typeof(newState) ~= "table" then
			return
		end
		ctx.state = {
			Ready = newState.Ready == true,
			Potions = if typeof(newState.Potions) == "table" then newState.Potions else {},
			Eggs = if typeof(newState.Eggs) == "table" then newState.Eggs else {},
			Boosts = if typeof(newState.Boosts) == "table" then newState.Boosts else {},
			Titles = if typeof(newState.Titles) == "table" then newState.Titles else {},
			Title = if typeof(newState.Title) == "string" then newState.Title else "",
			Progress = if typeof(newState.Progress) == "table" then newState.Progress else {},
		}
		ctx.boostEnds = {}
		local now = os.clock()
		for potionId, seconds in ctx.state.Boosts do
			if typeof(seconds) == "number" and seconds > 0 and ItemConfig.Potions[potionId] then
				ctx.boostEnds[potionId] = now + seconds
			end
		end
		if PanelManager.isOpen(PANEL_NAME) then
			ctx.render()
		end
	end)

	resultRemote.OnClientEvent:Connect(function(success: boolean, code: string, action: string, detail: any)
		if action == "Drop" and typeof(detail) == "table" then
			-- Solo Pociones de Vida (salen a menudo): un aviso pequeño, sin el cartel de botín
			local onlyHeal = detail.Egg == nil and #(detail.Potions or {}) > 0
			for _, potionId in detail.Potions or {} do
				local def = ItemConfig.Potions[potionId]
				if not (def and def.Heal) then
					onlyHeal = false
				end
			end
			if onlyHeal then
				local def = ItemConfig.Potions[detail.Potions[1]]
				Toasts.show(("%s +%d %s"):format(def.Icon, #detail.Potions, def.DisplayName), { Color = def.Color, Style = "Line", Key = "HealDrop" })
				return
			end
			local names = {}
			local potionCount = 0
			for _, potionId in detail.Potions or {} do
				local def = ItemConfig.Potions[potionId]
				if def then
					table.insert(names, def.Icon .. " " .. def.DisplayName)
					potionCount += 1
				end
			end
			if detail.Egg then
				local name = eggLook(detail.Egg)
				table.insert(names, "🥚 " .. name)
				markNew("Eggs", 1)
			end
			if potionCount > 0 then
				markNew("Potions", potionCount)
			end
			Toasts.show(table.concat(names, "  ·  "), { Title = "🎁 ¡Botín de " .. tostring(detail.Boss) .. "!", Color = THEME.Gold, Duration = 4.5, OnClick = function()
				PanelManager.open(PANEL_NAME)
				selectTab(if detail.Egg then "Eggs" else "Potions")
			end })
			Juice.sound(Juice.Sounds.HatchRare)
			Juice.pop(entry.Tile)
		elseif action == "Title" and typeof(detail) == "string" then
			local def = ItemConfig.Titles[detail]
			if def then
				markNew("Titles", 1)
				Toasts.show(("«%s» · %s"):format(def.DisplayName, def.Description), { Title = "🏅 ¡Nuevo título!", Color = def.Color, Duration = 4.5, OnClick = function()
					PanelManager.open(PANEL_NAME)
					selectTab("Titles")
				end })
				Juice.sound(Juice.Sounds.HatchEpic)
			end
		elseif action == "BoostEnded" and typeof(detail) == "string" then
			local def = ItemConfig.Potions[detail]
			if def then
				Toasts.show(("Se acabó tu %s %s"):format(def.Icon, def.DisplayName), { Color = def.Color, Style = "Line" })
			end
		elseif action == "UsePotion" then
			if success and typeof(detail) == "table" then
				local def = ItemConfig.Potions[detail.PotionId]
				if def and def.Heal then
					Toasts.show(("%s +%d de vida"):format(def.Icon, tonumber(detail.Healed) or 0), { Color = def.Color, Style = "Line", Key = "HealPotion" })
					Juice.sound(Juice.Sounds.Upgrade, 1.4)
				elseif def then
					Toasts.show(("%s %s activa: %s"):format(def.Icon, def.Short, clockText(detail.Seconds or 0)), { Color = def.Color })
					Juice.sound(Juice.Sounds.Upgrade, 1.2)
				end
			else
				Toasts.show(MESSAGES[code] or "No se pudo usar.", { Color = THEME.Error, Style = "Line" })
			end
		elseif action == "OpenEgg" then
			if success and typeof(detail) == "table" then
				showReveal(detail)
			else
				Toasts.show(MESSAGES[code] or "No se pudo abrir el huevo.", { Color = THEME.Error, Style = "Line" })
			end
		elseif action == "EquipTitle" then
			if success and typeof(detail) == "table" then
				local def = ItemConfig.Titles[detail.TitleId]
				Toasts.show(if def then ("Ahora llevas «%s»"):format(def.DisplayName) else "Título quitado", { Color = if def then def.Color else THEME.Muted, Style = "Line" })
			elseif not success then
				Toasts.show(MESSAGES[code] or "No se pudo cambiar el título.", { Color = THEME.Error, Style = "Line" })
			end
		end
	end)

	-- Armas: se repinta al cambiar las que tiene o la equipada.
	for _, attribute in { Constants.Attributes.Weapons, Constants.Attributes.EquippedWeapon } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if PanelManager.isOpen(PANEL_NAME) and ctx.currentTab == "Weapons" then
				ctx.render()
			end
		end)
	end

	-- Cuenta atrás de las pociones (HUD y panel), dos veces por segundo.
	task.spawn(function()
		while true do
			local now = os.clock()
			for potionId, chip in ui.Chips do
				local endsAt = ctx.boostEnds[potionId]
				local left = if endsAt then endsAt - now else 0
				chip.Frame.Visible = left > 0
				if left > 0 then
					chip.Time.Text = clockText(left)
				end
			end
			if PanelManager.isOpen(PANEL_NAME) and ctx.currentTab == "Potions" then
				for _, child in ui.List:GetChildren() do
					local timer = child:FindFirstChild("Active")
					if timer and timer:IsA("TextLabel") then
						local potionId = timer:GetAttribute("Potion")
						local endsAt = typeof(potionId) == "string" and ctx.boostEnds[potionId]
						local left = if endsAt then endsAt - now else 0
						timer.Visible = left > 0
						timer.Text = if left > 0 then "⏱ " .. clockText(left) else ""
					end
				end
			end
			task.wait(0.5)
		end
	end)

	PanelManager.register(PANEL_NAME, ui.Panel, {
		OnOpen = function()
			requestRemote:FireServer()
			selectTab(ctx.currentTab)
		end,
		OnClose = closeReveal,
	})
	UiKit.bindModalLayout(ui.ScreenGui, ui.PanelScale, PANEL_SIZE, function(position)
		PanelManager.setBasePosition(PANEL_NAME, position)
	end)
	UiKit.bindScale(ui.BoostsGui, { ui.BoostScale })
	ui.Close.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.I then
			PanelManager.toggle(PANEL_NAME)
		end
	end)

	requestRemote:FireServer()
end

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	MESSAGES = context.MESSAGES
	PANEL_NAME = context.PANEL_NAME
	PANEL_SIZE = context.PANEL_SIZE
	THEME = context.THEME
	player = context.player
end

return Part
