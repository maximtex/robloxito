-- Tienda (solo presentación). Las compras las abre Roblox (MarketplaceService) y las concede
-- el servidor (ShopService); aquí solo se muestran los artículos y se pide comprar.
-- - Azulejo «💎 Tienda» en el menú (tecla K).
-- - Pases (MonetizationConfig.GamePasses): icono, qué hace y precio en Robux (lo da Roblox),
--   «✓ Tuyo» si ya lo tiene o «Próximamente» si aún no tiene Id. La mejora automática
--   tiene su interruptor.
-- - Diamantes (MonetizationConfig.Products): cuántos 💎 da y su precio.
-- - Mascotas exclusivas (MonetizationConfig.PetProducts): se compran en el mundo, con la
--   interacción que lleva el atributo PetProduct (el altar del Jardín de los Huevos).
-- - Al confirmarse una compra, aviso en la pila común y la tienda al día.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local MonetizationLogic = require(Shared.MonetizationLogic)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local MenuBar = require(script.Parent.Parent.UI.MenuBar)
local Toasts = require(script.Parent.Parent.UI.Toasts)
local Juice = require(script.Parent.Parent.UI.Juice)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local PANEL_NAME = "Shop"
local PANEL_SIZE = Vector2.new(660, 470)
local SHOP_COLOR = Color3.fromRGB(120, 200, 255)
local ROBUX = "R$ "

local ShopController = {}

local player = Players.LocalPlayer
local prices: { [string]: number | false } = {} -- "Pass:123" -> Robux (false = no se pudo leer)

local function priceOf(kind: string, id: number): number?
	local key = kind .. ":" .. id
	local cached = prices[key]
	if cached ~= nil then
		return if cached == false then nil else cached :: number
	end
	prices[key] = false
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, if kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product)
		if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
			prices[key] = info.PriceInRobux
		end
	end)
	return nil
end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("ShopHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "ShopHud",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local panel, panelScale = UiKit.panel(screenGui, "ShopPanel", PANEL_SIZE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.2))
	UiKit.text(panel, "Title", {
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -90, 0, 32),
		Font = FONTS.Display,
		TextSize = 28,
		Text = "💎 Tienda",
	})
	UiKit.text(panel, "Subtitle", {
		Position = UDim2.fromOffset(22, 48),
		Size = UDim2.new(1, -90, 0, 20),
		Font = FONTS.Light,
		TextSize = 16,
		TextColor3 = THEME.Muted,
		Text = "Apoya el juego y avanza más rápido. ¡Gracias!",
	})
	local close = UiKit.button(panel, "Close", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = THEME.Inset,
		Text = "×",
	})
	local list = UiKit.create("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(16, 78),
		Size = UDim2.new(1, -32, 1, -90),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = THEME.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, panel)
	UiKit.create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	UiKit.create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 8) }, list)

	local function section(name: string, order: number, text: string)
		UiKit.text(list, name, {
			Size = UDim2.new(1, 0, 0, 24),
			Font = FONTS.Display,
			TextSize = 20,
			TextColor3 = THEME.Gold,
			Text = text,
			LayoutOrder = order,
		})
	end
	section("PassesTitle", 1, "Pases (para siempre)")
	local passGrid = UiKit.create("Frame", {
		Name = "Passes",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
	}, list)
	UiKit.create("UIGridLayout", {
		CellSize = UDim2.new(0.5, -5, 0, 132),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, passGrid)
	section("ProductsTitle", 3, "Energía al instante")
	local productRow = UiKit.create("Frame", {
		Name = "Products",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 4,
	}, list)
	UiKit.create("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -7, 0, 150),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, productRow)
	UiKit.text(list, "Note", {
		Size = UDim2.new(1, 0, 0, 34),
		Font = FONTS.Light,
		TextSize = 14,
		TextWrapped = true,
		TextColor3 = THEME.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "Los 💎 compran habilidades nuevas y sus mejoras (botón Mejoras de tu estilo).",
		LayoutOrder = 5,
	})

	-- Tarjetas
	local passCards = {}
	for order, key in MonetizationLogic.passOrder() do
		local def = MonetizationConfig.GamePasses[key]
		local card = UiKit.create("Frame", { Name = key, BackgroundColor3 = THEME.Inset, LayoutOrder = order }, passGrid)
		UiKit.corner(card, 12)
		local stroke = UiKit.stroke(card, def.Color or THEME.Stroke, 1.5, 0.5)
		UiKit.text(card, "Icon", {
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.fromOffset(44, 44),
			Font = FONTS.Display,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = def.Icon,
		})
		UiKit.text(card, "Name", {
			Position = UDim2.fromOffset(62, 10),
			Size = UDim2.new(1, -72, 0, 24),
			Font = FONTS.Display,
			TextSize = 19,
			TextColor3 = def.Color or THEME.Text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = def.Name,
		})
		UiKit.text(card, "Description", {
			Position = UDim2.fromOffset(62, 36),
			Size = UDim2.new(1, -72, 0, 46),
			Font = FONTS.Light,
			TextSize = 13,
			TextWrapped = true,
			TextColor3 = THEME.Muted,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = def.Description,
		})
		local buy = UiKit.button(card, "Buy", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -10, 1, -10),
			Size = UDim2.fromOffset(130, 36),
			TextSize = 17,
		})
		local toggle = nil
		if key == "AutoUpgrade" then
			toggle = UiKit.button(card, "Toggle", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 10, 1, -10),
				Size = UDim2.fromOffset(150, 36),
				TextSize = 15,
				BackgroundColor3 = THEME.Secondary,
				Visible = false,
			})
		end
		passCards[key] = { Frame = card, Stroke = stroke, Buy = buy, Toggle = toggle }
	end
	local productCards = {}
	for order, key in MonetizationLogic.productOrder() do
		local def = MonetizationConfig.Products[key]
		local card = UiKit.create("Frame", { Name = key, BackgroundColor3 = THEME.Inset, LayoutOrder = order }, productRow)
		UiKit.corner(card, 12)
		UiKit.stroke(card, THEME.Gold, 1.5, 0.55)
		UiKit.text(card, "Icon", {
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 36),
			Font = FONTS.Display,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = def.Icon,
		})
		UiKit.text(card, "Name", {
			Position = UDim2.fromOffset(6, 48),
			Size = UDim2.new(1, -12, 0, 20),
			Font = FONTS.Body,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = def.Name,
		})
		local amount = UiKit.text(card, "Amount", {
			Position = UDim2.fromOffset(6, 70),
			Size = UDim2.new(1, -12, 0, 24),
			Font = FONTS.Display,
			TextSize = 20,
			TextColor3 = THEME.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local buy = UiKit.button(card, "Buy", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -24, 0, 36),
			TextSize = 17,
		})
		productCards[key] = { Frame = card, Amount = amount, Buy = buy }
	end

	screenGui.Parent = playerGui
	return { ScreenGui = screenGui, Panel = panel, PanelScale = panelScale, Close = close, PassCards = passCards, ProductCards = productCards }
end

function ShopController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local actionRemote = remotes:WaitForChild(Constants.Remotes.ShopAction) :: RemoteEvent
	local resultRemote = remotes:WaitForChild(Constants.Remotes.ShopResult) :: RemoteEvent
	local ui = buildGui()

	MenuBar.add({
		Id = "Shop",
		Order = 7,
		Icon = "💎",
		Label = "Tienda",
		Key = "K",
		Color = SHOP_COLOR,
		Panels = { PANEL_NAME },
		OnActivate = function()
			PanelManager.toggle(PANEL_NAME)
		end,
	})

	local function owned(): MonetizationLogic.Passes
		return MonetizationLogic.parsePasses(player:GetAttribute(Constants.Attributes.Passes))
	end

	local function render()
		local passes = owned()
		for key, card in ui.PassCards do
			local def = MonetizationConfig.GamePasses[key]
			local has = passes[key] == true
			local available = typeof(def.Id) == "number" and def.Id > 0
			if has then
				card.Buy.Text = "✓ Tuyo"
				card.Buy.BackgroundColor3 = THEME.Secondary
				UiKit.setDisabled(card.Buy, true)
			elseif not available then
				card.Buy.Text = "Próximamente"
				card.Buy.BackgroundColor3 = THEME.Disabled
				UiKit.setDisabled(card.Buy, true)
			else
				local price = priceOf("Pass", def.Id)
				card.Buy.Text = if price then ROBUX .. formatNumber(price) else "Comprar"
				card.Buy.BackgroundColor3 = THEME.Buy
				UiKit.setDisabled(card.Buy, false)
			end
			card.Stroke.Transparency = if has then 0.1 else 0.5
			if card.Toggle then
				card.Toggle.Visible = has
				local on = player:GetAttribute(Constants.Attributes.AutoUpgrade) == true
				card.Toggle.Text = if on then "Automática: SÍ" else "Automática: NO"
				card.Toggle.BackgroundColor3 = if on then THEME.Buy else THEME.Secondary
			end
		end
		for key, card in ui.ProductCards do
			local def = MonetizationConfig.Products[key]
			card.Amount.Text = "+" .. formatNumber(MonetizationLogic.productEnergy(def)) .. " 💎"
			local available = typeof(def.Id) == "number" and def.Id > 0
			if available then
				local price = priceOf("Product", def.Id)
				card.Buy.Text = if price then ROBUX .. formatNumber(price) else "Comprar"
				card.Buy.BackgroundColor3 = THEME.Buy
			else
				card.Buy.Text = "Próximamente"
				card.Buy.BackgroundColor3 = THEME.Disabled
			end
			UiKit.setDisabled(card.Buy, not available)
		end
	end

	for key, card in ui.PassCards do
		card.Buy.Activated:Connect(function()
			local def = MonetizationConfig.GamePasses[key]
			if owned()[key] or not (typeof(def.Id) == "number" and def.Id > 0) then
				return
			end
			MarketplaceService:PromptGamePassPurchase(player, def.Id)
		end)
		if card.Toggle then
			card.Toggle.Activated:Connect(function()
				actionRemote:FireServer("SetAuto", player:GetAttribute(Constants.Attributes.AutoUpgrade) ~= true)
			end)
		end
	end
	for key, card in ui.ProductCards do
		card.Buy.Activated:Connect(function()
			local def = MonetizationConfig.Products[key]
			if typeof(def.Id) == "number" and def.Id > 0 then
				MarketplaceService:PromptProductPurchase(player, def.Id)
			end
		end)
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local petId = prompt:GetAttribute("PetProduct")
		local def = typeof(petId) == "string" and MonetizationConfig.PetProducts[petId]
		if not def then
			return
		end
		if typeof(def.Id) == "number" and def.Id > 0 then
			MarketplaceService:PromptProductPurchase(player, def.Id)
		else
			Toasts.show(("%s %s: ¡próximamente a la venta!"):format(def.Icon or "", def.Name or petId), { Color = SHOP_COLOR })
		end
	end)

	resultRemote.OnClientEvent:Connect(function(kind: string, key: string?, detail: any)
		if kind == "Pass" and typeof(key) == "string" then
			local def = MonetizationConfig.GamePasses[key]
			Toasts.show(("¡Gracias! Ya tienes %s %s"):format(def and def.Icon or "", def and def.Name or key), { Color = SHOP_COLOR, Duration = 5 })
			Juice.sound(Juice.Sounds.HatchEpic)
		elseif kind == "Pet" and typeof(key) == "string" then
			local def = MonetizationConfig.PetProducts[key]
			Toasts.show(("¡Gracias! %s %s ya es tuyo"):format(def and def.Icon or "", def and def.Name or key), { Color = SHOP_COLOR, Duration = 5 })
			Juice.sound(Juice.Sounds.HatchEpic)
		elseif kind == "Product" and typeof(detail) == "number" then
			Toasts.show(("+%s 💎  ¡Gracias por tu compra!"):format(formatNumber(detail)), { Color = THEME.Gold, Duration = 5 })
			Juice.sound(Juice.Sounds.HatchRare)
		end
		if PanelManager.isOpen(PANEL_NAME) then
			render()
		end
	end)

	-- Los precios llegan poco después de abrir: se repinta un par de veces.
	local openToken = 0
	PanelManager.register(PANEL_NAME, ui.Panel, {
		OnOpen = function()
			render()
			openToken += 1
			local token = openToken
			task.spawn(function()
				for _ = 1, 3 do
					task.wait(1)
					if openToken ~= token then
						return
					end
					render()
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
	ui.Close.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.K then
			PanelManager.toggle(PANEL_NAME)
		end
	end)
	for _, attribute in { Constants.Attributes.Passes, Constants.Attributes.AutoUpgrade } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if PanelManager.isOpen(PANEL_NAME) then
				render()
			end
		end)
	end
end

return ShopController
