-- HUD de energía: tarjeta de saldo arriba, tarjeta de mejora abajo.
-- Solo envía solicitudes; el servidor decide si la compra es válida.
-- Mientras hay un panel modal abierto (PanelManager), la tarjeta de mejora se aparta
-- hacia abajo para no quedar tapada; la de energía siempre queda visible.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local Constants = require(Shared.Constants)
local Economy = require(Shared.Economy)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.UI.Theme)
local RevealGate = require(script.Parent.Parent.Pets.RevealGate)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)

local UPGRADE_ID = "GeneratorPower"
local PENDING_TIMEOUT = 2
local FEEDBACK_SECONDS = 2.5

-- El HUD se diseña para una ventana de 1280x720. ScreenGui.AbsoluteSize ya descuenta
-- la barra superior de Roblox (~58 px), así que la altura de referencia es 660:
-- a 1280x720 reales la escala es 1.
local REFERENCE_SIZE = Vector2.new(1280, 660)
-- En escritorio no se reduce por debajo de 0.9 aunque el visor de Studio sea pequeño.
-- En pantallas táctiles se permite más reducción para dejar sitio al joystick y al salto.
local MIN_SCALE_DESKTOP = 0.9
local MIN_SCALE_TOUCH = 0.6
local MAX_SCALE = 1.5

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local LAYOUT = Theme.Layout

local RESULT_MESSAGES = {
	[Constants.PurchaseCodes.Success] = "¡Mejora comprada!",
	[Constants.PurchaseCodes.InsufficientEnergy] = "Energía insuficiente",
	[Constants.PurchaseCodes.MaxLevel] = "Nivel máximo alcanzado",
	[Constants.PurchaseCodes.TooFast] = "Demasiado rápido, espera un momento",
	[Constants.PurchaseCodes.NotReady] = "Cargando datos, inténtalo de nuevo",
	[Constants.PurchaseCodes.InvalidRequest] = "Solicitud no válida",
}

local HudController = {}

export type Callbacks = {
	onPurchaseSuccess: (() -> ())?,
}

-- Utilidades de construcción ------------------------------------------------

local function create(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in properties do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function addCorner(parent: Instance, radius: number)
	create("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function createText(parent: Instance, name: string, properties: { [string]: any }): TextLabel
	local label = create("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Font = FONTS.Body,
		TextColor3 = THEME.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}, nil)
	for key, value in properties do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

-- Tarjeta base con el mismo estilo para todos los paneles.
local function createCard(parent: Instance, name: string, size: Vector2, anchor: Vector2, position: UDim2)
	local card = create("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = THEME.Panel,
		BackgroundTransparency = THEME.PanelTransparency,
	}, parent)
	addCorner(card, 14)
	local stroke = create("UIStroke", {
		Color = THEME.Stroke,
		Thickness = 1.5,
		Transparency = THEME.StrokeTransparency,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, card)
	local scale = create("UIScale", {}, card)
	return card, stroke, scale
end

local function buildGui(playerGui: PlayerGui)
	local existing = playerGui:FindFirstChild("EnergyHud")
	if existing then
		existing:Destroy()
	end

	local screenGui = create("ScreenGui", {
		Name = "EnergyHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)

	-- Tamaños en píxeles a escala 1 (ventana de 1280x720). UIScale los ajusta.

	-- Tarjeta de energía (arriba, centrada; el chat está arriba a la izquierda)
	local energyCard, _, energyScale = createCard(
		screenGui,
		"EnergyCard",
		LAYOUT.EnergyCardSize,
		Vector2.new(0.5, 0),
		UDim2.new(0.5, 0, 0, LAYOUT.Margin)
	)
	local accentBar = create("Frame", {
		Name = "AccentBar",
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(0, 5, 1, -36),
		BackgroundColor3 = THEME.Accent,
		BorderSizePixel = 0,
	}, energyCard)
	addCorner(accentBar, 3)

	createText(energyCard, "Caption", {
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -44, 0, 18),
		TextSize = 15,
		TextColor3 = THEME.Muted,
		Text = "ENERGÍA",
	})
	local energyValue = createText(energyCard, "Value", {
		Position = UDim2.fromOffset(22, 34),
		Size = UDim2.new(1, -44, 0, 48),
		Font = FONTS.Display,
		TextSize = 44,
		Text = "...",
	})
	local productionValue = createText(energyCard, "Production", {
		Position = UDim2.fromOffset(22, 88),
		Size = UDim2.new(1, -44, 0, 24),
		TextSize = 19,
		TextColor3 = THEME.Accent,
	})

	-- Tarjeta de mejora (abajo, centrada; entre el joystick y el botón de salto en móvil)
	local upgradeCard, upgradeStroke, upgradeScale = createCard(
		screenGui,
		"UpgradeCard",
		Vector2.new(420, 212),
		Vector2.new(0.5, 1),
		UDim2.new(0.5, 0, 1, -24)
	)

	local title = createText(upgradeCard, "Title", {
		Position = UDim2.fromOffset(20, 18),
		Size = UDim2.new(1, -136, 0, 28),
		TextSize = 20,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local levelBadge = create("Frame", {
		Name = "LevelBadge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 17),
		Size = UDim2.fromOffset(96, 30),
		BackgroundColor3 = THEME.Inset,
	}, upgradeCard)
	addCorner(levelBadge, 15)
	local levelText = createText(levelBadge, "Text", {
		Size = UDim2.fromScale(1, 1),
		TextSize = 17,
		TextColor3 = THEME.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local description = createText(upgradeCard, "Description", {
		Position = UDim2.fromOffset(20, 50),
		Size = UDim2.new(1, -40, 0, 22),
		Font = FONTS.Light,
		TextSize = 17,
		TextColor3 = THEME.Muted,
	})

	local progressTrack = create("Frame", {
		Name = "ProgressTrack",
		Position = UDim2.fromOffset(20, 86),
		Size = UDim2.new(1, -40, 0, 10),
		BackgroundColor3 = THEME.Inset,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, upgradeCard)
	addCorner(progressTrack, 5)
	local progressFill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = THEME.Accent,
		BorderSizePixel = 0,
	}, progressTrack)
	addCorner(progressFill, 5)

	local progressText = createText(upgradeCard, "ProgressText", {
		Position = UDim2.fromOffset(20, 100),
		Size = UDim2.new(1, -40, 0, 20),
		Font = FONTS.Light,
		TextSize = 15,
		TextColor3 = THEME.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	local button = create("TextButton", {
		Name = "UpgradeButton",
		Position = UDim2.new(0, 20, 1, -74),
		Size = UDim2.new(1, -40, 0, 56),
		BackgroundColor3 = THEME.Disabled,
		AutoButtonColor = false,
		Font = FONTS.Display,
		TextSize = 23,
		TextColor3 = THEME.Text,
		Text = "Cargando...",
	}, upgradeCard)
	addCorner(button, 12)
	local buttonScale = create("UIScale", {}, button)
	local buttonFlash = create("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, button)
	addCorner(buttonFlash, 12)

	-- Mensaje de resultado, flotando justo encima de la tarjeta de mejora.
	local feedback = createText(upgradeCard, "Feedback", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -10),
		Size = UDim2.new(1, 0, 0, 26),
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.35,
		TextStrokeColor3 = Color3.new(0, 0, 0),
	})

	screenGui.Parent = playerGui

	return {
		ScreenGui = screenGui,
		Scales = { energyScale, upgradeScale },
		EnergyCard = energyCard,
		EnergyValue = energyValue,
		ProductionValue = productionValue,
		UpgradeCard = upgradeCard,
		UpgradeStroke = upgradeStroke,
		Title = title,
		LevelText = levelText,
		Description = description,
		ProgressFill = progressFill,
		ProgressText = progressText,
		Button = button,
		ButtonScale = buttonScale,
		ButtonFlash = buttonFlash,
		Feedback = feedback,
	}
end

-- Controlador ---------------------------------------------------------------

function HudController.start(callbacks: Callbacks?)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local purchaseRemote = remotes:WaitForChild(Constants.Remotes.PurchaseUpgrade) :: RemoteEvent
	local resultRemote = remotes:WaitForChild(Constants.Remotes.PurchaseResult) :: RemoteEvent

	local ui = buildGui(playerGui)
	local definition = EconomyConfig.Upgrades[UPGRADE_ID]
	local levelAttribute = Constants.Attributes.UpgradeLevelPrefix .. UPGRADE_ID

	ui.Title.Text = definition.DisplayName
	ui.Description.Text = "+" .. formatNumber(definition.ProductionPerLevel) .. " energía/s por nivel"

	local pendingToken = 0
	local pending = false
	local feedbackToken = 0
	local hovered = false
	local lastProgress = -1

	local quickTween = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeTween = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- Escalado según el tamaño de pantalla disponible
	local function applyScale()
		local size = ui.ScreenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local isTouchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		local minScale = if isTouchOnly then MIN_SCALE_TOUCH else MIN_SCALE_DESKTOP
		local scale = math.clamp(math.min(size.X / REFERENCE_SIZE.X, size.Y / REFERENCE_SIZE.Y), minScale, MAX_SCALE)
		for _, uiScale in ui.Scales do
			uiScale.Scale = scale
		end
	end
	ui.ScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyScale)
	applyScale()

	local function setProgress(ratio: number)
		ratio = math.clamp(ratio, 0, 1)
		if math.abs(ratio - lastProgress) < 0.001 then
			return
		end
		lastProgress = ratio
		TweenService:Create(ui.ProgressFill, TweenInfo.new(0.25), { Size = UDim2.fromScale(ratio, 1) }):Play()
	end

	local function refresh()
		local energy = player:GetAttribute(Constants.Attributes.Energy)
		local production = player:GetAttribute(Constants.Attributes.ProductionPerSecond)
		local level = player:GetAttribute(levelAttribute)

		if typeof(energy) ~= "number" or typeof(production) ~= "number" or typeof(level) ~= "number" then
			ui.EnergyValue.Text = "..."
			ui.ProductionValue.Text = "Cargando..."
			ui.LevelText.Text = "Nv. -"
			ui.ProgressText.Text = ""
			ui.Button.Text = "Cargando..."
			ui.Button.BackgroundColor3 = THEME.Disabled
			ui.Button.TextColor3 = THEME.Muted
			setProgress(0)
			return
		end

		ui.EnergyValue.Text = "⚡ " .. formatNumber(energy)
		-- Mientras se incuba un huevo, la producción no se actualiza para no delatar la
		-- rareza de la mascota antes de la presentación (RevealGate).
		if not RevealGate.isHeld() then
			local productionText = "+" .. formatNumber(production, 2) .. " por segundo"
			local petMultiplier = player:GetAttribute(Constants.Attributes.PetMultiplier)
			if typeof(petMultiplier) == "number" and petMultiplier > 1 then
				productionText ..= "  ·  🐾 ×" .. formatNumber(petMultiplier, 2)
			end
			ui.ProductionValue.Text = productionText
		end

		if level >= definition.MaxLevel then
			ui.LevelText.Text = "MÁX"
			ui.LevelText.TextColor3 = THEME.Gold
			ui.ProgressText.Text = "Mejora completada"
			ui.Button.Text = "NIVEL MÁXIMO"
			ui.Button.BackgroundColor3 = THEME.Max
			ui.Button.TextColor3 = THEME.Text
			setProgress(1)
			return
		end

		-- Coste mostrado solo como referencia; el servidor lo recalcula.
		local cost = Economy.getUpgradeCost(UPGRADE_ID, level) or 0
		local affordable = energy >= cost

		ui.LevelText.Text = "Nv. " .. level
		ui.LevelText.TextColor3 = THEME.Accent
		ui.ProgressText.Text = formatNumber(math.min(energy, cost)) .. " / " .. formatNumber(cost)
		ui.Button.Text = "MEJORAR  ·  ⚡ " .. formatNumber(cost)
		ui.Button.BackgroundColor3 = if affordable then THEME.Buy else THEME.Disabled
		ui.Button.TextColor3 = if affordable then THEME.Text else THEME.Muted
		setProgress(if cost > 0 then energy / cost else 1)
	end

	local function showFeedback(text: string, color: Color3)
		feedbackToken += 1
		local token = feedbackToken
		ui.Feedback.Text = text
		ui.Feedback.TextColor3 = color
		ui.Feedback.TextTransparency = 0
		ui.Feedback.TextStrokeTransparency = 0.35
		task.delay(FEEDBACK_SECONDS, function()
			if feedbackToken == token then
				TweenService:Create(ui.Feedback, fadeTween, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end)
	end

	local function flashStroke(color: Color3)
		ui.UpgradeStroke.Color = color
		ui.UpgradeStroke.Thickness = 3
		ui.UpgradeStroke.Transparency = 0
		TweenService:Create(ui.UpgradeStroke, TweenInfo.new(0.6), {
			Color = THEME.Stroke,
			Thickness = 1.5,
			Transparency = THEME.StrokeTransparency,
		}):Play()
	end

	-- Texto "+X/s" que sube y se desvanece desde la tarjeta de energía.
	local function spawnFloatingGain()
		local floating = createText(ui.EnergyCard, "FloatingGain", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -22, 0, 88),
			Size = UDim2.fromOffset(140, 24),
			TextSize = 19,
			TextColor3 = THEME.BuyHighlight,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = "+" .. formatNumber(definition.ProductionPerLevel) .. "/s",
		})
		local tween = TweenService:Create(floating, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(1, -22, 0, 58),
			TextTransparency = 1,
		})
		tween.Completed:Once(function()
			floating:Destroy()
		end)
		tween:Play()
	end

	local function playSuccessEffects()
		ui.ButtonFlash.BackgroundTransparency = 0.4
		TweenService:Create(ui.ButtonFlash, fadeTween, { BackgroundTransparency = 1 }):Play()
		flashStroke(THEME.BuyHighlight)
		spawnFloatingGain()

		if callbacks and callbacks.onPurchaseSuccess then
			-- Un fallo en el efecto del mundo no debe romper el HUD.
			local ok, err = pcall(callbacks.onPurchaseSuccess)
			if not ok then
				warn("[HUD] Error en efecto de compra:", err)
			end
		end
	end

	-- Interacción del botón
	ui.Button.MouseEnter:Connect(function()
		hovered = true
		TweenService:Create(ui.ButtonScale, quickTween, { Scale = 1.03 }):Play()
	end)
	ui.Button.MouseLeave:Connect(function()
		hovered = false
		TweenService:Create(ui.ButtonScale, quickTween, { Scale = 1 }):Play()
	end)
	ui.Button.MouseButton1Down:Connect(function()
		TweenService:Create(ui.ButtonScale, quickTween, { Scale = 0.97 }):Play()
	end)
	ui.Button.MouseButton1Up:Connect(function()
		TweenService:Create(ui.ButtonScale, quickTween, { Scale = if hovered then 1.03 else 1 }):Play()
	end)

	ui.Button.Activated:Connect(function()
		-- Antirrebote local para no saturar la red; la protección real está en el servidor.
		if pending then
			return
		end
		pending = true
		pendingToken += 1
		local token = pendingToken
		purchaseRemote:FireServer(UPGRADE_ID)

		task.delay(PENDING_TIMEOUT, function()
			if pendingToken == token then
				pending = false
			end
		end)
	end)

	resultRemote.OnClientEvent:Connect(function(success: boolean, code: string)
		pending = false
		local message = RESULT_MESSAGES[code] or tostring(code)
		if success then
			showFeedback(message, THEME.BuyHighlight)
			playSuccessEffects()
		else
			showFeedback(message, THEME.Error)
			flashStroke(THEME.Error)
		end
	end)

	player:GetAttributeChangedSignal(Constants.Attributes.Energy):Connect(refresh)
	player:GetAttributeChangedSignal(Constants.Attributes.ProductionPerSecond):Connect(refresh)
	player:GetAttributeChangedSignal(levelAttribute):Connect(refresh)
	player:GetAttributeChangedSignal(Constants.Attributes.PetMultiplier):Connect(refresh)
	RevealGate.Released:Connect(refresh)

	-- Apartar la tarjeta de mejora mientras haya un panel modal abierto.
	local upgradeHome = ui.UpgradeCard.Position
	local upgradeAway = UDim2.new(0.5, 0, 1, 360) -- fuera de pantalla, por debajo
	local upgradeTween: Tween? = nil
	PanelManager.Changed:Connect(function(openPanel: string?)
		if upgradeTween then
			upgradeTween:Cancel()
		end
		local info = TweenInfo.new(LAYOUT.TransitionSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		if openPanel then
			local tween = TweenService:Create(ui.UpgradeCard, info, { Position = upgradeAway })
			tween.Completed:Once(function(state)
				if state == Enum.PlaybackState.Completed then
					ui.UpgradeCard.Visible = false
				end
			end)
			upgradeTween = tween
			tween:Play()
		else
			ui.UpgradeCard.Visible = true
			upgradeTween = TweenService:Create(ui.UpgradeCard, info, { Position = upgradeHome })
			upgradeTween:Play()
		end
	end)

	refresh()
end

return HudController
