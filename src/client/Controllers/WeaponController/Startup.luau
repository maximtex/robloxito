-- WeaponController · Startup: arranque (start): refresco de tarjetas, compra/mejora/equipado, paginación, arrastre y atajo L.
-- Parte de WeaponController (ver WeaponController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local WeaponLogic = require(Shared.WeaponLogic)
local StyleLogic = require(Shared.StyleLogic)
local GunLogic = require(Shared.GunLogic)
local MagicLogic = require(Shared.MagicLogic)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.Parent.UI.PanelManager)
local MenuBar = require(script.Parent.Parent.Parent.UI.MenuBar)
local Toasts = require(script.Parent.Parent.Parent.UI.Toasts)
local Juice = require(script.Parent.Parent.Parent.UI.Juice)

local ctx: any -- tabla de estado compartida (la crea WeaponController/init.luau)
local Api = {} -- funciones públicas de esta parte (init.luau las copia a WeaponController)
local BUTTON_HEIGHT: any
local CARDS_PER_PAGE: any
local CARD_STEP: any
local DARK: any
local ERROR_COLOR: any
local GRAY: any
local GREEN: any
local HEADER_HEIGHT: any
local MESSAGES: any
local OK_COLOR: any
local PANEL_NAME: any
local PANEL_SIZE: any
local PENDING_TIMEOUT: any
local PURPLE: any
local ROW_SIZE: any
local TOAST_SECONDS: any
local player: any

-- Funciones de las otras partes
local function buildGui(...) return ctx.buildGui(...) end
local function currentCategory(...) return ctx.currentCategory(...) end
local function currentWorld(...) return ctx.currentWorld(...) end
local function fill(...) return ctx.fill(...) end
local function numberAttribute(...) return ctx.numberAttribute(...) end
local function ownedWeapons(...) return ctx.ownedWeapons(...) end
local function short(...) return ctx.short(...) end
local function unlockedZones(...) return ctx.unlockedZones(...) end

function Api.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local actionRemote = remotes:WaitForChild(Constants.Remotes.WeaponAction) :: RemoteEvent
	local weaponResult = remotes:WaitForChild(Constants.Remotes.WeaponResult) :: RemoteEvent

	local ui = buildGui()
	local pending = false
	local pendingToken = 0
	local toastToken = 0
	local actions: { [string]: { Primary: () -> (), Secondary: () -> () } } = {}

	local function say(text: string, ok: boolean)
		toastToken += 1
		local token = toastToken
		ui.Toast.Text = text
		ui.Toast.TextColor3 = if ok then OK_COLOR else ERROR_COLOR
		ui.Toast.Visible = true
		task.delay(TOAST_SECONDS, function()
			if toastToken == token then
				ui.Toast.Visible = false
			end
		end)
	end

	-- Una petición a la vez (se libera con la respuesta o a los PENDING_TIMEOUT segundos)
	local function request(action: string, weaponId: string)
		if pending then
			return
		end
		pending = true
		pendingToken += 1
		local token = pendingToken
		actionRemote:FireServer(action, weaponId)
		task.delay(PENDING_TIMEOUT, function()
			if pendingToken == token then
				pending = false
			end
		end)
	end

	local function buyWithRobux(weaponId: string)
		local product = MonetizationConfig.WeaponProducts[weaponId]
		if product and product.Id > 0 then
			MarketplaceService:PromptProductPurchase(player, product.Id)
		else
			say("Próximamente con Robux", false)
		end
	end

	local shownCategory = ""
	local function refresh()
		local money = numberAttribute(Constants.Attributes.Money)
		ui.Money.Text = "$" .. short(money)
		local owned = ownedWeapons()
		local equipped = player:GetAttribute(Constants.Attributes.EquippedWeapon)
		local zones = unlockedZones()
		local pets = numberAttribute(Constants.Attributes.PetMultiplier)
		local cadence = numberAttribute(Constants.Attributes.UpgradeLevelPrefix .. WeaponConfig.CadenceUpgradeId)
		local category = currentCategory()
		local info = WeaponConfig.Categories[category]
		local world = currentWorld()
		ui.Title.Text = if world == 2 then info.Title .. " 2" else info.Title
		ui.Title.TextSize = if world == 2 then 52 else 60
		local useImage = ui.HeaderImage ~= nil and category == "Weapons"
		if ui.HeaderImage then
			ui.HeaderImage.Visible = useImage
		end
		ui.HeaderEmoji.Visible = not useImage
		ui.HeaderEmoji.Text = info.Icon
		if category .. world ~= shownCategory then
			shownCategory = category .. world
			ui.Row.CanvasPosition = Vector2.zero -- otra tienda: a la primera página
		end

		for weaponId, card in ui.Cards do
			local def = card.Def
			card.Frame.Visible = WeaponLogic.category(weaponId) == category and WeaponLogic.world(weaponId) == world
			local level = owned[weaponId]
			local has = level ~= nil
			local isEquipped = equipped == weaponId
			card.RingStroke.Transparency = if isEquipped then 0 else 0.7
			card.TagText.Text = if has then ("Nv. %d/%d"):format(level, WeaponConfig.MaxLevel) else def.Tagline or ""
			-- Números con el ritmo y el alcance de su estilo (y de su tipo de arma); la tercera
			-- línea: el tipo y el cargador (armas), el elemento (bastones) o cuerpo a cuerpo
			local styled = StyleLogic.applyStats({
				Shot = WeaponLogic.shotDamage(weaponId, level or 0, pets),
				Cooldown = WeaponLogic.cooldown(weaponId, cadence),
				Range = def.Range,
			}, category, def.Cooldown)
			if category == "Weapons" then
				styled = GunLogic.applyStats(styled, weaponId)
			end
			card.Stats[1].Text = short(styled.Shot) .. " " .. info.Hit
			card.Stats[2].Text = ("Velocidad de ataque: %.2f s"):format(styled.Cooldown)
			if category == "Weapons" then
				local gun = GunLogic.spec(weaponId)
				card.Stats[3].Text = ("%s · %d flechas · %d"):format(gun.Name or styled.Gun, styled.Magazine, styled.Range)
			elseif category == "Magic" then
				local element = MagicLogic.elementDef(MagicLogic.element(weaponId))
				card.Stats[3].Text = ("%s %s · %d de alcance"):format(element.Icon or "", element.Name or "", styled.Range)
			elseif category == "Warrior" then
				card.Stats[3].Text = "Espada · cuerpo a cuerpo"
			else
				card.Stats[3].Text = "Cuerpo a cuerpo"
			end

			-- Principal: texto grande, texto pequeño debajo, color y qué hace
			local label, sub, size, colors, onPrimary = "", "", 28, GREEN, function() end
			-- Al lado: mejorar (si la tiene) o comprar con Robux (si se vende así)
			local side: { Label: string, Colors: { Color3 }, Robux: boolean, Action: () -> () }? = nil
			local product = MonetizationConfig.WeaponProducts[weaponId]
			local robuxSide = if product
				then { Label = tostring(product.Robux), Colors = PURPLE, Robux = true, Action = function()
					buyWithRobux(weaponId)
				end }
				else nil
			if has then
				local cost = WeaponLogic.upgradeCost(weaponId, level)
				side = {
					Label = if cost then "$" .. short(cost) else "MÁX",
					Colors = if cost and money >= cost then GREEN else GRAY,
					Robux = false,
					Action = function()
						if cost then
							request("Upgrade", weaponId)
						else
							say("Nivel máximo alcanzado", false)
						end
					end,
				}
				if isEquipped then
					label, onPrimary = "Equipado", function()
						say("Ya la tienes equipada", true)
					end
				else
					label, onPrimary = "Equipar", function()
						request("Equip", weaponId)
					end
				end
			elseif def.BossDrop then
				local boss = EnemyConfig.Types[def.BossDrop]
				label, sub, size, colors = "💀 DERROTA AL JEFE", if boss then boss.DisplayName else "", 20, DARK
				onPrimary = function()
					say("Lo suelta ese jefe si lo derrotas con este estilo", false)
				end
			elseif not WeaponLogic.meetsRequirement(weaponId, zones) then
				local zone = ZoneConfig.Zones[def.Requires.Zone]
				label, sub, size, colors = "🔒 $" .. short(def.Price), if zone then zone.DisplayName else "", 24, GRAY
				onPrimary = function()
					say("Primero desbloquea su zona", false)
				end
				side = robuxSide
			else
				label, colors = "$" .. short(def.Price), if money >= def.Price then GREEN else GRAY
				onPrimary = function()
					request("Buy", weaponId)
				end
				side = robuxSide
			end

			fill(card.Primary, colors, BUTTON_HEIGHT)
			card.PrimaryLabel.Text = label
			card.PrimaryLabel.TextSize = size
			card.PrimaryLabel.Size = if sub ~= "" then UDim2.new(1, 0, 1, -18) else UDim2.fromScale(1, 1)
			card.PrimarySub.Text = sub
			card.PrimarySub.Visible = sub ~= ""
			card.Secondary.Visible = side ~= nil
			card.Primary.Size = if side then UDim2.new(1, -30 - 90 - 8, 0, BUTTON_HEIGHT) else UDim2.new(1, -30, 0, BUTTON_HEIGHT)
			if side then
				fill(card.Secondary, side.Colors, BUTTON_HEIGHT)
				card.SecondaryLabel.Text = side.Label
				card.RobuxIcon.Visible = side.Robux
			end
			actions[weaponId] = { Primary = onPrimary, Secondary = if side then side.Action else function() end }
		end
	end

	-- Al soltar después de arrastrar las tarjetas, el botón de debajo no se pulsa
	local suppressClickUntil = 0
	for weaponId, card in ui.Cards do
		card.Primary.Activated:Connect(function()
			local action = actions[weaponId]
			if action and os.clock() >= suppressClickUntil then
				action.Primary()
			end
		end)
		card.Secondary.Activated:Connect(function()
			local action = actions[weaponId]
			if action and os.clock() >= suppressClickUntil then
				action.Secondary()
			end
		end)
	end

	-- Flechas: pasan de página (cuatro tarjetas), siempre alineadas a una tarjeta.
	-- CanvasPosition va en píxeles de pantalla (ya escalados por el UIScale del panel).
	local function maxScroll(): number
		return math.max(0, ui.Row.AbsoluteCanvasSize.X - ui.Row.AbsoluteWindowSize.X)
	end
	local function step(): number
		return CARD_STEP * ui.Row.AbsoluteWindowSize.X / ROW_SIZE.X
	end
	local function refreshArrows()
		local x = ui.Row.CanvasPosition.X
		ui.Left.Visible = x > 2
		ui.Right.Visible = x < maxScroll() - 2
	end
	local function page(direction: number)
		local current = math.round(ui.Row.CanvasPosition.X / step())
		local target = math.clamp((current + direction * CARDS_PER_PAGE) * step(), 0, maxScroll())
		TweenService:Create(ui.Row, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CanvasPosition = Vector2.new(target, 0) }):Play()
	end
	ui.Left.Activated:Connect(function()
		page(-1)
	end)
	ui.Right.Activated:Connect(function()
		page(1)
	end)
	for _, property in { "CanvasPosition", "AbsoluteCanvasSize", "AbsoluteWindowSize" } do
		ui.Row:GetPropertyChangedSignal(property):Connect(refreshArrows)
	end
	refreshArrows()

	-- Centrado en la pantalla, sin pisar la columna de la izquierda, y lo más grande que quepa
	-- (hasta la escala del HUD). Se vuelve a centrar al abrir y al cambiar el tamaño de pantalla.
	local function layoutPanel()
		local size = ui.ScreenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local hudScale = UiKit.computeScale(size)
		local sideReserve = 16 + Theme.Layout.SideButtonWidth * hudScale + Theme.Layout.Gap
		local fit = math.min(hudScale, (size.Y - 2 * Theme.Layout.Margin) / PANEL_SIZE.Y, (size.X - 2 * sideReserve) / PANEL_SIZE.X)
		ui.FitScale.Scale = fit
		PanelManager.setBasePosition(PANEL_NAME, UDim2.new(0.5, 0, 0, (size.Y - PANEL_SIZE.Y * fit) / 2))
	end

	-- Arrastrar con el ratón (o el dedo): la cabecera mueve la ventana; las tarjetas pasan de
	-- arma en arma (con el dedo ya lo hace el ScrollingFrame) y, al soltar, quedan alineadas.
	local function inside(gui: GuiObject, position: Vector2): boolean
		local corner, extent = gui.AbsolutePosition, gui.AbsoluteSize
		return position.X >= corner.X and position.X <= corner.X + extent.X and position.Y >= corner.Y and position.Y <= corner.Y + extent.Y
	end
	local windowDrag: { Input: InputObject, Start: Vector2, From: UDim2 }? = nil
	local rowDrag: { Start: number, From: number, Moved: boolean }? = nil
	UserInputService.InputBegan:Connect(function(input)
		local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
		if not (isMouse or input.UserInputType == Enum.UserInputType.Touch) or not PanelManager.isOpen(PANEL_NAME) then
			return
		end
		local position = Vector2.new(input.Position.X, input.Position.Y)
		if inside(ui.Header, position) and not inside(ui.Close, position) and not inside(ui.Skills, position) then
			windowDrag = { Input = input, Start = position, From = ui.Panel.Position }
		elseif isMouse and inside(ui.Row, position) then
			rowDrag = { Start = position.X, From = ui.Row.CanvasPosition.X, Moved = false }
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local isMouse = input.UserInputType == Enum.UserInputType.MouseMovement
		if windowDrag and (isMouse or input == windowDrag.Input) then
			local size = ui.ScreenGui.AbsoluteSize
			local delta = Vector2.new(input.Position.X, input.Position.Y) - windowDrag.Start
			local from = windowDrag.From
			-- Que el centro de la ventana y su cabecera no salgan de la pantalla
			local x = math.clamp(from.X.Offset + delta.X, -size.X / 2, size.X / 2)
			local y = math.clamp(from.Y.Offset + delta.Y, 0, size.Y - HEADER_HEIGHT * ui.FitScale.Scale)
			ui.Panel.Position = UDim2.new(0.5, x, 0, y)
		elseif rowDrag and isMouse then
			local delta = input.Position.X - rowDrag.Start
			if math.abs(delta) > 6 then
				rowDrag.Moved = true
			end
			if rowDrag.Moved then
				ui.Row.CanvasPosition = Vector2.new(math.clamp(rowDrag.From - delta, 0, maxScroll()), 0)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if windowDrag and (input == windowDrag.Input or input.UserInputType == Enum.UserInputType.MouseButton1) then
			windowDrag = nil
			if PanelManager.isOpen(PANEL_NAME) then
				PanelManager.setBasePosition(PANEL_NAME, ui.Panel.Position) -- para que cierre desde ahí
			end
		elseif rowDrag and input.UserInputType == Enum.UserInputType.MouseButton1 then
			if rowDrag.Moved then
				suppressClickUntil = os.clock() + 0.2
				local target = math.clamp(math.round(ui.Row.CanvasPosition.X / step()) * step(), 0, maxScroll())
				TweenService:Create(ui.Row, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CanvasPosition = Vector2.new(target, 0) }):Play()
			end
			rowDrag = nil
		end
	end)

	weaponResult.OnClientEvent:Connect(function(success: boolean, code: string, action: string, weaponId: string)
		pending = false
		local def = WeaponConfig.Weapons[weaponId]
		if code == "BossDrop" and def then
			local info = WeaponConfig.Categories[WeaponLogic.category(weaponId)] or WeaponConfig.Categories.Weapons
			Toasts.show(("%s %s ya es tuyo. Equípalo en la tienda de tu estilo (L)."):format(def.Icon, def.DisplayName), { Title = ("🏆 ¡Nuevo: %s!"):format(info.Item), Color = Theme.Colors.Gold })
			Juice.sound(Juice.Sounds.Upgrade, 1.1)
		elseif code == "Robux" and def then
			say("¡Comprada con Robux y equipada!", true)
			if not PanelManager.isOpen(PANEL_NAME) then
				Toasts.show(("%s %s ya es tuya y está equipada."):format(def.Icon, def.DisplayName), { Title = "¡Arma comprada!", Color = Theme.Colors.Gold })
			end
			Juice.sound(Juice.Sounds.Upgrade, 1.1)
		elseif success then
			say(if action == "Buy" then "¡Comprado y equipado!" elseif action == "Upgrade" then "¡Mejorado!" else "Equipado", true)
			Juice.sound(Juice.Sounds.Upgrade, if action == "Upgrade" then 1.05 else 1)
		else
			say(MESSAGES[code] or tostring(code), false)
		end
		refresh()
	end)

	PanelManager.register(PANEL_NAME, ui.Panel, {
		OnOpen = function()
			refresh()
			layoutPanel()
			-- Aparece creciendo desde el centro con un pequeño rebote, como en el diseño, y
			-- siempre en la primera página
			ui.Row.CanvasPosition = Vector2.zero
			ui.PopScale.Scale = 0.05
			local pop = TweenService:Create(ui.PopScale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			pop.Completed:Once(function()
				ui.Row.CanvasPosition = Vector2.zero
			end)
			pop:Play()
		end,
	})
	ui.ScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutPanel)
	UiKit.onScaleChanged(layoutPanel) -- ⚙️ tamaño de la interfaz
	layoutPanel()
	ui.Close.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
	end)
	ui.Skills.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
		PanelManager.open("Skills")
	end)
	ui.Classes.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
		PanelManager.open("Classes")
	end)
	local menuEntry = MenuBar.add({
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
	-- El azulejo dice qué tienda abre (Armas, Espadas, Guantes o Bastones)
	local MENU_WORDS = { Weapons = "Armas", Warrior = "Espadas", Fists = "Guantes", Magic = "Bastones" }
	local function refreshMenuLabel()
		menuEntry.setLabel(MENU_WORDS[currentCategory()] or "Armas")
	end
	player:GetAttributeChangedSignal(Constants.Attributes.CombatStyle):Connect(refreshMenuLabel)
	refreshMenuLabel()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.L then
			PanelManager.toggle(PANEL_NAME)
		end
	end)

	for _, attribute in {
		Constants.Attributes.Money,
		Constants.Attributes.Weapons,
		Constants.Attributes.EquippedWeapon,
		Constants.Attributes.UnlockedZones,
		Constants.Attributes.PetMultiplier,
		Constants.Attributes.UpgradeLevelPrefix .. WeaponConfig.CadenceUpgradeId,
		Constants.Attributes.CombatStyle,
		Constants.Attributes.CurrentZone,
	} do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	refresh()
end

local Part = { Api = Api }

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	BUTTON_HEIGHT = context.BUTTON_HEIGHT
	CARDS_PER_PAGE = context.CARDS_PER_PAGE
	CARD_STEP = context.CARD_STEP
	DARK = context.DARK
	ERROR_COLOR = context.ERROR_COLOR
	GRAY = context.GRAY
	GREEN = context.GREEN
	HEADER_HEIGHT = context.HEADER_HEIGHT
	MESSAGES = context.MESSAGES
	OK_COLOR = context.OK_COLOR
	PANEL_NAME = context.PANEL_NAME
	PANEL_SIZE = context.PANEL_SIZE
	PENDING_TIMEOUT = context.PENDING_TIMEOUT
	PURPLE = context.PURPLE
	ROW_SIZE = context.ROW_SIZE
	TOAST_SECONDS = context.TOAST_SECONDS
	player = context.player
end

return Part
