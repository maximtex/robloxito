-- PetController · EggPanel: panel del santuario del huevo: probabilidades, estado de compra, grietas y reinicio.
-- Parte de PetController (ver PetController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local PetConfig = require(Shared.Config.PetConfig)
local EggConfig = require(Shared.Config.EggConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local PetMath = require(Shared.PetMath)
local PetClassLogic = require(Shared.PetClassLogic)
local MonetizationLogic = require(Shared.MonetizationLogic)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local formatNumber = require(Shared.Util.FormatNumber)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)
local RevealGate = require(script.Parent.Parent.Parent.Pets.RevealGate)
local PanelManager = require(script.Parent.Parent.Parent.UI.PanelManager)
local Juice = require(script.Parent.Parent.Parent.UI.Juice)

local ctx: any -- tabla de estado compartida (la crea PetController/init.luau)
local EGG_PANEL_SIZE: any
local EGG_SIZE: any
local FONTS: any
local THEME: any
local player: any

-- Funciones de las otras partes
local function bonusText(...) return ctx.bonusText(...) end
local function rarityOf(...) return ctx.rarityOf(...) end
local function showFeedback(...) return ctx.showFeedback(...) end

local Part = { Api = {} }

function Part.start()
	local ui = ctx.ui

	-- Huevo ----------------------------------------------------------------------
	-- "idle" (viendo probabilidades), "incubating" (animación / esperando) o "revealed".

	local function zoneUnlocked(zoneId: string): boolean
		local value = player:GetAttribute(Constants.Attributes.UnlockedZones)
		return typeof(value) == "string" and table.find(string.split(value, ","), zoneId) ~= nil
	end

	-- Comprobación previa en el cliente (solo para la interfaz; el servidor la repite).
	-- Devuelve: bloqueado, asequible y si el bloqueo es por zona (el único que hay).
	local function eggState(egg): (boolean, boolean, boolean)
		local money = player:GetAttribute(Constants.Attributes.Money) -- los huevos se pagan con 💰
		local zoneLocked = egg.RequiredZone ~= nil and not zoneUnlocked(egg.RequiredZone)
		local locked = zoneLocked
		local affordable = typeof(money) == "number" and money >= egg.Cost
		return locked, affordable, zoneLocked
	end

	-- Destello en los botones de compra mientras se pueden pagar.
	local shimmers: { [GuiObject]: (boolean) -> () } = {}
	local function setShimmer(button: GuiObject, active: boolean)
		local setter = shimmers[button]
		if not setter then
			setter = UiKit.shimmer(button, 10)
			shimmers[button] = setter
		end
		setter(active)
	end

	local function hasTriple(): boolean
		return MonetizationLogic.owns(MonetizationLogic.parsePasses(player:GetAttribute(Constants.Attributes.Passes)), "TripleHatch")
	end

	local function styleButton(button: TextButton, egg, label: string, count: number?)
		local amount = count or 1
		local locked, affordable, zoneLocked = eggState(egg)
		if amount > 1 then
			local money = player:GetAttribute(Constants.Attributes.Money)
			affordable = typeof(money) == "number" and money >= egg.Cost * amount
		end
		if zoneLocked then
			local zone = ZoneConfig.Zones[egg.RequiredZone]
			button.Text = "🔒 Requiere " .. (if zone then zone.DisplayName else egg.RequiredZone)
		else
			button.Text = label .. "  ·  💰 " .. formatNumber(egg.Cost * amount)
		end
		local enabled = not locked and affordable
		button.BackgroundColor3 = if enabled then THEME.Buy else THEME.Disabled
		button.TextColor3 = if enabled then THEME.Text else THEME.Muted
		UiKit.setDisabled(button, not enabled)
		setShimmer(button, enabled)
	end

	local function refreshEggButton()
		local egg = ctx.currentEggId and EggConfig.Eggs[ctx.currentEggId]
		if not egg then
			return
		end
		local triple = hasTriple()
		ui.TripleButton.Visible = triple
		ui.IncubateButton.Size = if triple then UDim2.new(0.5, -28, 0, 56) else UDim2.new(1, -44, 0, 56)
		styleButton(ui.IncubateButton, egg, if triple then "×1" else "INCUBAR")
		if triple then
			styleButton(ui.TripleButton, egg, "×" .. MonetizationConfig.TripleCount, MonetizationConfig.TripleCount)
		end
		if ctx.phase == "revealed" then
			local again = if triple then ctx.lastCount else 1
			styleButton(ui.AgainButton, egg, if again > 1 then "Otros ×" .. again else "Otro", again)
		end
	end

	local function renderOdds(egg)
		for _, child in ui.Odds:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		-- Solo lo que este huevo puede dar de verdad, con sus probabilidades reales.
		for order, entry in egg.Chances do
			local pet = PetConfig.Pets[entry.PetId]
			local rarity = rarityOf(entry.PetId)
			local row = UiKit.create("Frame", {
				Name = "Row" .. order,
				Size = UDim2.new(1, 0, 0, 48),
				BackgroundColor3 = THEME.Inset,
				LayoutOrder = order,
			}, ui.Odds)
			UiKit.corner(row, 10)
			UiKit.text(row, "Name", {
				Position = UDim2.fromOffset(12, 4),
				Size = UDim2.new(0.6, 0, 0, 22),
				Font = FONTS.Display,
				TextSize = 19,
				TextColor3 = rarity.Color,
				Text = if pet then pet.DisplayName else entry.PetId,
			})
			UiKit.text(row, "Detail", {
				Position = UDim2.fromOffset(12, 26),
				Size = UDim2.new(0.7, 0, 0, 18),
				Font = FONTS.Light,
				TextSize = 14,
				TextColor3 = THEME.Muted,
				Text = rarity.DisplayName .. "  ·  " .. PetConfig.Classes[PetClassLogic.classOf(entry.PetId)].Icon .. "  ·  " .. bonusText(PetMath.getPetMultiplier(entry.PetId)) .. " de poder",
			})
			UiKit.text(row, "Chance", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(90, 28),
				Font = FONTS.Display,
				TextSize = 22,
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = formatNumber(entry.Chance, 2) .. "%",
			})
		end
	end

	local function stopAnimation()
		if ctx.animationConnection then
			ctx.animationConnection:Disconnect()
			ctx.animationConnection = nil
		end
		ui.EggShape.Rotation = 0
		ui.EggShape.Size = UDim2.fromOffset(EGG_SIZE.X, EGG_SIZE.Y)
	end

	-- Cada grieta nueva suena (cada vez más aguda) mientras se incuba.
	local shownCracks = 0
	local function setCracks(count: number)
		if count > shownCracks then
			Juice.sound(Juice.Sounds.Crack, 1 + count * 0.12)
		end
		shownCracks = count
		for index, crack in ui.Cracks do
			crack.Visible = index <= count
		end
	end

	local function clearViewport()
		for _, child in ui.Viewport:GetChildren() do
			if child:IsA("Model") then
				child:Destroy()
			end
		end
	end

	local function resetHatch()
		ctx.sequenceToken += 1
		ctx.phase = "idle"
		ctx.incubating = false
		ctx.currentRequestId = nil
		ctx.pendingResult = nil
		stopAnimation()
		RevealGate.release()
		clearViewport()
		ui.Hatch.Visible = false
		ui.Viewport.Visible = false
		ui.AgainButton.Visible = false
		ui.BackButton.Visible = false
		ui.EggClose.Visible = true
		ui.HatchStatus.Text = ""
		ui.RevealName.Text = ""
		ui.RevealDetails.Text = ""
		ui.RevealEquip.Text = ""
		ui.EggShape.Visible = true
		ui.Flash.BackgroundTransparency = 1
		ui.Glow.BackgroundTransparency = 1
		ui.Glow.BackgroundColor3 = THEME.Gold
		ui.Glow.Size = UDim2.fromOffset(150, 150)
		setCracks(0)
	end

	-- Se ejecuta cuando el PanelManager cierra el panel del huevo.
	local function onEggPanelClosed()
		resetHatch()
		ctx.currentEggId = nil
		ctx.currentPromptPart = nil
	end

	local function closeEggPanel()
		PanelManager.close("Egg")
	end

	PanelManager.register("Egg", ui.EggPanel, {
		-- No se puede cerrar ni cambiar de panel a mitad de una apertura.
		CanClose = function()
			return not ctx.incubating
		end,
		OnClose = onEggPanelClosed,
	})
	UiKit.bindModalLayout(ui.ScreenGui, ui.EggScale, EGG_PANEL_SIZE, function(position)
		PanelManager.setBasePosition("Egg", position)
	end)

	local function openEggPanel(eggId: string, promptPart: BasePart?)
		local egg = EggConfig.Eggs[eggId]
		if not egg or egg.Enabled == false then
			return
		end
		if ctx.incubating then
			return -- no cambiar de huevo a mitad de una apertura
		end
		resetHatch()
		ctx.currentEggId = eggId
		ctx.currentPromptPart = promptPart
		ui.EggTitle.Text = egg.DisplayName
		ui.EggCost.Text = "💰 "
			.. formatNumber(egg.Cost)
			.. " por huevo"
		ui.EggShape.BackgroundColor3 = egg.Look.Shell
		for _, spot in ui.EggSpots do
			spot.BackgroundColor3 = egg.Look.Spots
		end
		renderOdds(egg)
		refreshEggButton()
		ui.EggFeedback.Text = ""
		PanelManager.open("Egg")
	end

	local function failIncubation(message: string)
		resetHatch()
		showFeedback(ui.EggFeedback, message, THEME.Error)
	end

	ctx.clearViewport = clearViewport
	ctx.closeEggPanel = closeEggPanel
	ctx.eggState = eggState
	ctx.failIncubation = failIncubation
	ctx.hasTriple = hasTriple
	ctx.openEggPanel = openEggPanel
	ctx.refreshEggButton = refreshEggButton
	ctx.resetHatch = resetHatch
	ctx.setCracks = setCracks
	ctx.stopAnimation = stopAnimation
end

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	EGG_PANEL_SIZE = context.EGG_PANEL_SIZE
	EGG_SIZE = context.EGG_SIZE
	FONTS = context.FONTS
	THEME = context.THEME
	player = context.player
end

return Part
