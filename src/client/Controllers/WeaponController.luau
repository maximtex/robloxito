-- Armería (panel "Armory"): comprar, equipar y mejorar armas, y las mejoras globales que se
-- pagan con dinero (Velocidad de Correr, Poder de Mascotas, Cadencia). Se abre en el puesto
-- del pueblo, con la tecla L o con el botón "Armas" del menú. Solo muestra y pide: el
-- servidor (WeaponService, UpgradeService) valida y cobra.
-- Datos de los atributos del jugador: Weapons ("Laser:3,PlasmaBlaster:0"), EquippedWeapon,
-- Money, UnlockedZones, PetMultiplier y UpgradeLevel_<id>.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Economy = require(Shared.Economy)
local WeaponLogic = require(Shared.WeaponLogic)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local MenuBar = require(script.Parent.Parent.UI.MenuBar)
local Toasts = require(script.Parent.Parent.UI.Toasts)
local Juice = require(script.Parent.Parent.UI.Juice)

local PANEL_NAME = "Armory"
local PANEL_SIZE = Vector2.new(640, 560)
local FEEDBACK_SECONDS = 2.5
local PENDING_TIMEOUT = 2

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local Codes = Constants.PurchaseCodes

local MESSAGES = {
	[Codes.InsufficientMoney] = "Te falta 💰 dinero: derrota enemigos",
	[Codes.InsufficientEnergy] = "Energía insuficiente",
	[Codes.AlreadyOwned] = "Ya tienes esa arma",
	[Codes.NotForSale] = "Esa arma la suelta un jefe",
	[Codes.Locked] = "Primero desbloquea su zona",
	[Codes.NotOwned] = "Aún no tienes esa arma",
	[Codes.MaxLevel] = "Nivel máximo alcanzado",
	[Codes.TooFast] = "Demasiado rápido, espera un momento",
	[Codes.NotReady] = "Cargando datos, inténtalo de nuevo",
	[Codes.InvalidRequest] = "Solicitud no válida",
}

-- Mejoras globales de la Armería (EconomyConfig, Currency = "Money")
local UPGRADES = {
	{
		Id = "LaserSpeed",
		Icon = "⏱",
		Color = Color3.fromRGB(205, 115, 255),
		Describe = function(level: number): string
			local now = 1 - math.max(WeaponConfig.MinCadenceFactor, 1 - WeaponConfig.CadencePerLevel * level)
			local after = 1 - math.max(WeaponConfig.MinCadenceFactor, 1 - WeaponConfig.CadencePerLevel * (level + 1))
			return ("Todas tus armas: -%d%% → -%d%% de tiempo entre disparos"):format(math.round(now * 100), math.round(after * 100))
		end,
	},
	{
		Id = "PetPower",
		Icon = "🐾",
		Color = Color3.fromRGB(255, 205, 75),
		Describe = function(level: number): string
			return ("Daño de tus mascotas: %d%% → %d%%"):format(100 + level * 25, 100 + (level + 1) * 25)
		end,
	},
	{
		Id = "WalkSpeed",
		Icon = "👟",
		Color = Color3.fromRGB(110, 245, 130),
		Describe = function(level: number): string
			return ("Velocidad al correr: %.1f → %.1f"):format(28 + level * 2.5, 28 + (level + 1) * 2.5)
		end,
	},
}

local WeaponController = {}

local player = Players.LocalPlayer

-- "Laser:3,PlasmaBlaster:0" -> { Laser = 3, PlasmaBlaster = 0 }
local function ownedWeapons(): { [string]: number }
	local owned = {}
	local text = player:GetAttribute(Constants.Attributes.Weapons)
	if typeof(text) == "string" then
		for weaponId, level in text:gmatch("([%w_]+):(%d+)") do
			owned[weaponId] = tonumber(level) or 0
		end
	end
	if next(owned) == nil then
		owned[WeaponConfig.StarterWeapon] = 0
	end
	return owned
end

local function unlockedZones(): { string }
	local zones = {}
	local text = player:GetAttribute(Constants.Attributes.UnlockedZones)
	if typeof(text) == "string" then
		for zoneId in text:gmatch("[^,]+") do
			table.insert(zones, zoneId)
		end
	end
	return zones
end

local function numberAttribute(name: string): number
	local value = player:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

-- Efecto especial en una línea
local function effectText(def): string
	local effect = def.Effect
	if not effect then
		return def.Description
	end
	local parts = {}
	if effect.Splash then
		table.insert(parts, ("💥 explota en %d studs (%d%%)"):format(effect.Splash.Radius, math.round(effect.Splash.Fraction * 100)))
	end
	if effect.Chain then
		table.insert(parts, ("⚡ salta a %d enemigos más (%d%%)"):format(effect.Chain.Count, math.round(effect.Chain.Fraction * 100)))
	end
	if effect.Slow then
		table.insert(parts, ("🧊 ralentiza un %d%%"):format(math.round((1 - effect.Slow.Factor) * 100)))
	end
	return table.concat(parts, "  ·  ")
end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("ArmoryHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "ArmoryHud",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)

	local panel, scale = UiKit.panel(screenGui, "ArmoryPanel", PANEL_SIZE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.18))
	UiKit.text(panel, "Title", {
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -260, 0, 32),
		Font = FONTS.Display,
		TextSize = 26,
		Text = "⚔️ Armería",
	})
	UiKit.text(panel, "Subtitle", {
		Position = UDim2.fromOffset(22, 48),
		Size = UDim2.new(1, -44, 0, 20),
		Font = FONTS.Light,
		TextSize = 15,
		TextColor3 = THEME.Muted,
		Text = "Compra, equipa y mejora tus armas con el 💰 dinero de los enemigos.",
	})
	local moneyLabel = UiKit.text(panel, "Money", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -66, 0, 18),
		Size = UDim2.fromOffset(180, 28),
		Font = FONTS.Display,
		TextSize = 22,
		TextColor3 = THEME.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
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
		Position = UDim2.fromOffset(22, 78),
		Size = UDim2.new(1, -44, 1, -120),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = THEME.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, panel)
	UiKit.create("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)

	local order = 0
	local function header(text: string)
		order += 1
		UiKit.text(list, "Header", {
			Size = UDim2.new(1, -8, 0, 24),
			Font = FONTS.Display,
			TextSize = 19,
			TextColor3 = THEME.Gold,
			Text = text,
			LayoutOrder = order,
		})
	end

	header("Armas")
	local weaponRows = {}
	for _, weaponId in WeaponLogic.ordered() do
		local def = WeaponConfig.Weapons[weaponId]
		order += 1
		local row = UiKit.create("Frame", {
			Name = "Weapon_" .. weaponId,
			Size = UDim2.new(1, -8, 0, 96),
			BackgroundColor3 = THEME.Inset,
			LayoutOrder = order,
		}, list)
		UiKit.corner(row, 12)
		local rowStroke = UiKit.stroke(row, def.Color, 1.4, 0.25)
		local title = UiKit.text(row, "Title", {
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -210, 0, 24),
			Font = FONTS.Display,
			TextSize = 19,
			TextColor3 = def.Color,
		})
		local stats = UiKit.text(row, "Stats", {
			Position = UDim2.fromOffset(14, 36),
			Size = UDim2.new(1, -210, 0, 20),
			Font = FONTS.Body,
			TextSize = 14,
		})
		local detail = UiKit.text(row, "Detail", {
			Position = UDim2.fromOffset(14, 60),
			Size = UDim2.new(1, -210, 0, 28),
			Font = FONTS.Light,
			TextSize = 13,
			TextColor3 = THEME.Muted,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		local primary = UiKit.button(row, "Primary", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 10),
			Size = UDim2.fromOffset(180, 38),
			TextSize = 16,
		})
		local upgrade = UiKit.button(row, "Upgrade", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 54),
			Size = UDim2.fromOffset(180, 32),
			TextSize = 14,
		})
		weaponRows[weaponId] = { Def = def, Title = title, Stats = stats, Detail = detail, Primary = primary, Upgrade = upgrade, Stroke = rowStroke }
	end

	header("Mejoras de la Armería")
	local upgradeRows = {}
	for _, spec in UPGRADES do
		local def = EconomyConfig.Upgrades[spec.Id]
		order += 1
		local row = UiKit.create("Frame", {
			Name = "Upgrade_" .. spec.Id,
			Size = UDim2.new(1, -8, 0, 68),
			BackgroundColor3 = THEME.Inset,
			LayoutOrder = order,
		}, list)
		UiKit.corner(row, 12)
		UiKit.stroke(row, spec.Color, 1.4, 0.25)
		local title = UiKit.text(row, "Title", {
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -210, 0, 24),
			Font = FONTS.Display,
			TextSize = 19,
			TextColor3 = spec.Color,
		})
		local desc = UiKit.text(row, "Desc", {
			Position = UDim2.fromOffset(14, 36),
			Size = UDim2.new(1, -210, 0, 22),
			Font = FONTS.Light,
			TextSize = 14,
		})
		local button = UiKit.button(row, "BuyButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(180, 44),
			TextSize = 16,
		})
		upgradeRows[spec.Id] = { Spec = spec, Def = def, Title = title, Desc = desc, Button = button }
	end

	local feedback = UiKit.text(panel, "Feedback", {
		Position = UDim2.new(0, 22, 1, -34),
		Size = UDim2.new(1, -44, 0, 22),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	screenGui.Parent = playerGui
	return {
		ScreenGui = screenGui,
		Panel = panel,
		Scale = scale,
		Close = close,
		Money = moneyLabel,
		WeaponRows = weaponRows,
		UpgradeRows = upgradeRows,
		Feedback = feedback,
	}
end

local function style(button: TextButton, text: string, color: Color3, enabled: boolean)
	button.Text = text
	button.BackgroundColor3 = color
	button.TextColor3 = if enabled then THEME.Text else THEME.Muted
	UiKit.setDisabled(button, not enabled)
end

function WeaponController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local actionRemote = remotes:WaitForChild(Constants.Remotes.WeaponAction) :: RemoteEvent
	local weaponResult = remotes:WaitForChild(Constants.Remotes.WeaponResult) :: RemoteEvent
	local purchaseRemote = remotes:WaitForChild(Constants.Remotes.PurchaseUpgrade) :: RemoteEvent
	local purchaseResult = remotes:WaitForChild(Constants.Remotes.PurchaseResult) :: RemoteEvent

	local ui = buildGui()
	local pending = false
	local pendingToken = 0
	local feedbackToken = 0

	local function refresh()
		local money = numberAttribute(Constants.Attributes.Money)
		ui.Money.Text = "💰 " .. formatNumber(money)
		local owned = ownedWeapons()
		local equipped = player:GetAttribute(Constants.Attributes.EquippedWeapon)
		local zones = unlockedZones()
		local pets = numberAttribute(Constants.Attributes.PetMultiplier)
		local cadence = numberAttribute(Constants.Attributes.UpgradeLevelPrefix .. WeaponConfig.CadenceUpgradeId)

		for weaponId, row in ui.WeaponRows do
			local def = row.Def
			local level = owned[weaponId]
			local has = level ~= nil
			local shownLevel = level or 0
			row.Title.Text = ("%s  %s%s"):format(def.Icon, def.DisplayName, if has then ("   Nv. %d/%d"):format(shownLevel, WeaponConfig.MaxLevel) else "")
			row.Stats.Text = ("💥 %s por disparo  ·  ⏱ %.2fs  ·  🎯 %d  ·  %s/s"):format(
				formatNumber(WeaponLogic.shotDamage(weaponId, shownLevel, pets)),
				WeaponLogic.cooldown(weaponId, cadence),
				def.Range,
				formatNumber(WeaponLogic.dps(weaponId, shownLevel, cadence, pets))
			)
			row.Detail.Text = effectText(def)
			row.Stroke.Transparency = if equipped == weaponId then 0 else 0.25
			row.Stroke.Thickness = if equipped == weaponId then 3 else 1.4

			if equipped == weaponId then
				style(row.Primary, "✓ Equipada", THEME.Secondary, false)
			elseif has then
				style(row.Primary, "Equipar", THEME.Buy, true)
			elseif def.BossDrop then
				local boss = EnemyConfig.Types[def.BossDrop]
				style(row.Primary, "🏆 Jefe", THEME.Disabled, false)
				row.Detail.Text = ("Derrota al %s para conseguirla. %s"):format(boss and boss.DisplayName or "jefe", effectText(def))
			elseif not WeaponLogic.meetsRequirement(weaponId, zones) then
				local zone = ZoneConfig.Zones[def.Requires.Zone]
				style(row.Primary, "🔒 " .. formatNumber(def.Price), THEME.Disabled, false)
				row.Detail.Text = ("Desbloquea %s para comprarla. %s"):format(zone and zone.DisplayName or "su zona", effectText(def))
			else
				local affordable = money >= def.Price
				style(row.Primary, "Comprar · $" .. formatNumber(def.Price), if affordable then THEME.Buy else THEME.Disabled, affordable)
			end

			row.Upgrade.Visible = has
			if has then
				local cost = WeaponLogic.upgradeCost(weaponId, shownLevel)
				if cost then
					local affordable = money >= cost
					style(row.Upgrade, "Mejorar · $" .. formatNumber(cost), if affordable then THEME.Buy else THEME.Disabled, affordable)
				else
					style(row.Upgrade, "MÁXIMO", THEME.Max, false)
				end
			end
		end

		for upgradeId, row in ui.UpgradeRows do
			local level = numberAttribute(Constants.Attributes.UpgradeLevelPrefix .. upgradeId)
			local maxLevel = row.Def.MaxLevel
			row.Title.Text = ("%s  %s  (Nv. %d/%d)"):format(row.Spec.Icon, row.Def.DisplayName, level, maxLevel)
			row.Desc.Text = row.Spec.Describe(level)
			if level >= maxLevel then
				style(row.Button, "MÁXIMO", THEME.Max, false)
			else
				local cost = Economy.getUpgradeCost(upgradeId, level) or 0
				local affordable = money >= cost
				style(row.Button, "Mejorar · $" .. formatNumber(cost), if affordable then THEME.Buy else THEME.Disabled, affordable)
			end
		end
	end

	local function showFeedback(text: string, color: Color3)
		feedbackToken += 1
		local token = feedbackToken
		ui.Feedback.Text = text
		ui.Feedback.TextColor3 = color
		task.delay(FEEDBACK_SECONDS, function()
			if feedbackToken == token then
				ui.Feedback.Text = ""
			end
		end)
	end

	-- Una petición a la vez (se libera con la respuesta o a los PENDING_TIMEOUT segundos)
	local function request(send: () -> ())
		if pending then
			return
		end
		pending = true
		pendingToken += 1
		local token = pendingToken
		send()
		task.delay(PENDING_TIMEOUT, function()
			if pendingToken == token then
				pending = false
			end
		end)
	end

	for weaponId, row in ui.WeaponRows do
		row.Primary.Activated:Connect(function()
			local owned = ownedWeapons()
			request(function()
				actionRemote:FireServer(if owned[weaponId] then "Equip" else "Buy", weaponId)
			end)
		end)
		row.Upgrade.Activated:Connect(function()
			request(function()
				actionRemote:FireServer("Upgrade", weaponId)
			end)
		end)
	end
	for upgradeId, row in ui.UpgradeRows do
		row.Button.Activated:Connect(function()
			request(function()
				purchaseRemote:FireServer(upgradeId)
			end)
		end)
	end

	weaponResult.OnClientEvent:Connect(function(success: boolean, code: string, action: string, weaponId: string)
		pending = false
		local def = WeaponConfig.Weapons[weaponId]
		if code == "BossDrop" and def then
			Toasts.show(("%s %s ya es tuya. Equípala en la Armería (L)."):format(def.Icon, def.DisplayName), { Title = "🏆 ¡Nueva arma!", Color = THEME.Gold })
			Juice.sound(Juice.Sounds.Upgrade, 1.1)
		elseif success then
			local text = if action == "Buy" then "¡Comprada y equipada!" elseif action == "Upgrade" then "¡Arma mejorada!" else "Equipada"
			showFeedback(text, THEME.BuyHighlight)
			Juice.sound(Juice.Sounds.Upgrade, if action == "Upgrade" then 1.05 else 1)
		else
			showFeedback(MESSAGES[code] or tostring(code), THEME.Error)
		end
		refresh()
	end)
	purchaseResult.OnClientEvent:Connect(function(success: boolean, code: string)
		if not PanelManager.isOpen(PANEL_NAME) then
			return -- compras de otros paneles (la Resonancia del Cristal, en Núcleos)
		end
		pending = false
		if success then
			showFeedback("¡Mejora comprada!", THEME.BuyHighlight)
			Juice.sound(Juice.Sounds.Upgrade, 1)
		else
			showFeedback(MESSAGES[code] or tostring(code), THEME.Error)
		end
		refresh()
	end)

	PanelManager.register(PANEL_NAME, ui.Panel, { OnOpen = refresh })
	UiKit.bindModalLayout(ui.ScreenGui, ui.Scale, PANEL_SIZE, function(position)
		PanelManager.setBasePosition(PANEL_NAME, position)
	end)
	ui.Close.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
	end)
	MenuBar.add({
		Id = "Armory",
		Order = 0,
		Icon = "⚔️",
		Label = "Armas",
		Key = "L",
		Panels = { PANEL_NAME },
		OnActivate = function()
			PanelManager.toggle(PANEL_NAME)
		end,
	})
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.L then
			PanelManager.toggle(PANEL_NAME)
		end
	end)

	for _, attribute in { Constants.Attributes.Money, Constants.Attributes.Weapons, Constants.Attributes.EquippedWeapon, Constants.Attributes.UnlockedZones, Constants.Attributes.PetMultiplier } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	for _, spec in UPGRADES do
		player:GetAttributeChangedSignal(Constants.Attributes.UpgradeLevelPrefix .. spec.Id):Connect(refresh)
	end
	refresh()
end

return WeaponController
