-- Interfaz de los portales entre zonas:
-- - Panel del portal (PanelManager): si la zona está bloqueada, muestra el coste, la
--   energía disponible y la que falta, con el botón Desbloquear; si está desbloqueada
--   (o es el bosque), el botón Viajar.
-- - Viaje con un fundido breve que siempre se retira (respuesta, error o tiempo límite).
-- - Tinte de color local mientras el jugador está en el Valle Cristalino.
-- Solo envía solicitudes: el servidor valida el desbloqueo, el cobro y el viaje.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local Codes = Constants.PurchaseCodes

local PANEL_SIZE = Vector2.new(440, 300)
local CLOSE_DISTANCE = 22
local FADE_SECONDS = 0.25
local TRAVEL_TIMEOUT = 8 -- el fundido nunca se queda puesto más que esto

local MESSAGES = {
	[Codes.InsufficientEnergy] = "Energía insuficiente",
	[Codes.TooFar] = "Acércate al portal",
	[Codes.TooFast] = "Espera un momento",
	[Codes.NotReady] = "Cargando tus datos, inténtalo de nuevo",
	[Codes.ZoneLocked] = "Esta zona aún está bloqueada",
	[Codes.Busy] = "Ya estás viajando",
	[Codes.InvalidRequest] = "Solicitud no válida",
}

-- Tinte local del Valle (solo afecta a la pantalla de este jugador).
local ZONE_TINTS = {
	CrystalValley = { TintColor = Color3.fromRGB(236, 232, 255), Saturation = 0.08, Contrast = 0.04 },
}
local NEUTRAL_TINT = { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0 }

local PortalController = {}

local player = Players.LocalPlayer

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("PortalHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "PortalHud",
		ResetOnSpawn = false,
		DisplayOrder = 6,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)

	local panel, panelScale = UiKit.panel(screenGui, "PortalPanel", PANEL_SIZE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.2))
	local title = UiKit.text(panel, "Title", {
		Position = UDim2.fromOffset(22, 16),
		Size = UDim2.new(1, -90, 0, 32),
		Font = FONTS.Display,
		TextSize = 26,
	})
	local subtitle = UiKit.text(panel, "Subtitle", {
		Position = UDim2.fromOffset(22, 50),
		Size = UDim2.new(1, -44, 0, 20),
		Font = FONTS.Light,
		TextSize = 15,
		TextColor3 = THEME.Muted,
	})
	local close = UiKit.button(panel, "Close", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = THEME.Inset,
		Text = "✕",
	})
	local status = UiKit.text(panel, "Status", {
		Position = UDim2.fromOffset(22, 90),
		Size = UDim2.new(1, -44, 0, 26),
		Font = FONTS.Display,
		TextSize = 22,
	})
	local costLine = UiKit.text(panel, "Cost", {
		Position = UDim2.fromOffset(22, 122),
		Size = UDim2.new(1, -44, 0, 22),
		TextSize = 17,
		TextColor3 = THEME.Gold,
	})
	local missingLine = UiKit.text(panel, "Missing", {
		Position = UDim2.fromOffset(22, 148),
		Size = UDim2.new(1, -44, 0, 22),
		Font = FONTS.Light,
		TextSize = 16,
	})
	local action = UiKit.button(panel, "Action", {
		Position = UDim2.new(0, 22, 1, -96),
		Size = UDim2.new(1, -44, 0, 54),
		TextSize = 22,
	})
	local feedback = UiKit.text(panel, "Feedback", {
		Position = UDim2.new(0, 22, 1, -34),
		Size = UDim2.new(1, -44, 0, 22),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	-- Fundido del viaje (encima de todo; nunca bloquea más de TRAVEL_TIMEOUT).
	local fade = UiKit.create("Frame", {
		Name = "TravelFade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = THEME.Overlay,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 50,
	}, screenGui)
	local fadeLabel = UiKit.text(fade, "Label", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(500, 40),
		Font = FONTS.Display,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		ZIndex = 51,
	})
	-- Aviso breve cuando el panel ya está cerrado (p. ej. error al viajar).
	local toast = UiKit.text(screenGui, "Toast", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.fromOffset(520, 28),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		ZIndex = 40,
	})

	screenGui.Parent = playerGui
	return {
		ScreenGui = screenGui,
		Panel = panel,
		PanelScale = panelScale,
		Title = title,
		Subtitle = subtitle,
		Close = close,
		Status = status,
		CostLine = costLine,
		MissingLine = missingLine,
		Action = action,
		Feedback = feedback,
		Fade = fade,
		FadeLabel = fadeLabel,
		Toast = toast,
	}
end

function PortalController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local unlockRemote = remotes:WaitForChild(Constants.Remotes.UnlockZone) :: RemoteEvent
	local zoneResultRemote = remotes:WaitForChild(Constants.Remotes.ZoneResult) :: RemoteEvent
	local travelRemote = remotes:WaitForChild(Constants.Remotes.TravelToZone) :: RemoteEvent
	local travelResultRemote = remotes:WaitForChild(Constants.Remotes.TravelResult) :: RemoteEvent

	local ui = buildGui()
	local currentPortalId: string? = nil
	local currentPortalPart: BasePart? = nil
	local unlockPending = false
	local travelToken = 0
	local feedbackToken = 0

	local function showMessage(label: TextLabel, text: string, color: Color3)
		feedbackToken += 1
		local token = feedbackToken
		label.Text = text
		label.TextColor3 = color
		task.delay(3, function()
			if feedbackToken == token then
				label.Text = ""
			end
		end)
	end

	local function isUnlocked(zoneId: string): boolean
		local zone = ZoneConfig.Zones[zoneId]
		if zone and (zone.UnlockCost or 0) <= 0 then
			return true
		end
		local value = player:GetAttribute(Constants.Attributes.UnlockedZones)
		return typeof(value) == "string" and table.find(string.split(value, ","), zoneId) ~= nil
	end

	local function energy(): number
		local value = player:GetAttribute(Constants.Attributes.Energy)
		return if typeof(value) == "number" then value else 0
	end

	-- Pinta el panel según el estado actual (bloqueado / desbloqueado / volver).
	local function render()
		local portal = currentPortalId and ZoneConfig.Portals[currentPortalId]
		if not portal then
			return
		end
		local target = ZoneConfig.Zones[portal.Target]
		local cost = target.UnlockCost or 0
		ui.Title.Text = "Portal · " .. target.DisplayName
		ui.Subtitle.Text = if cost > 0 then "Un antiguo arco cubierto de cristales que late con energía." else "El camino de vuelta al bosque inicial."

		if isUnlocked(portal.Target) then
			ui.Status.Text = if cost > 0 then "✓ Desbloqueado" else "Siempre abierto"
			ui.Status.TextColor3 = THEME.Accent
			ui.CostLine.Text = ""
			ui.MissingLine.Text = ""
			ui.Action.Text = "Viajar a " .. target.DisplayName
			ui.Action.BackgroundColor3 = THEME.Buy
			ui.Action.TextColor3 = THEME.Text
			UiKit.setDisabled(ui.Action, false)
		else
			local have = energy()
			local missing = math.max(0, cost - have)
			ui.Status.Text = "🔒 Bloqueado"
			ui.Status.TextColor3 = THEME.Gold
			ui.CostLine.Text = ("Coste: ⚡ %s   ·   Tienes: ⚡ %s"):format(formatNumber(cost), formatNumber(have))
			ui.MissingLine.Text = if missing > 0 then ("Te faltan ⚡ %s"):format(formatNumber(math.ceil(missing))) else "¡Tienes suficiente energía!"
			ui.MissingLine.TextColor3 = if missing > 0 then THEME.Error else THEME.BuyHighlight
			ui.Action.Text = "Desbloquear  ·  ⚡ " .. formatNumber(cost)
			local enabled = missing <= 0
			ui.Action.BackgroundColor3 = if enabled then THEME.Buy else THEME.Disabled
			ui.Action.TextColor3 = if enabled then THEME.Text else THEME.Muted
			UiKit.setDisabled(ui.Action, not enabled)
		end
	end

	PanelManager.register("Portal", ui.Panel, {
		OnClose = function()
			currentPortalId = nil
			currentPortalPart = nil
		end,
	})
	UiKit.bindModalLayout(ui.ScreenGui, ui.PanelScale, PANEL_SIZE, function(position)
		PanelManager.setBasePosition("Portal", position)
	end)

	local function openPortal(portalId: string, part: BasePart?)
		if not ZoneConfig.Portals[portalId] then
			return
		end
		currentPortalId = portalId
		currentPortalPart = part
		ui.Feedback.Text = ""
		render()
		PanelManager.open("Portal")
	end

	-- Fundido: entrar, y salir siempre (resultado, error o tiempo límite).
	local function fadeIn(text: string)
		ui.Fade.Visible = true
		ui.FadeLabel.Text = text
		TweenService:Create(ui.Fade, TweenInfo.new(FADE_SECONDS), { BackgroundTransparency = 0 }):Play()
		TweenService:Create(ui.FadeLabel, TweenInfo.new(FADE_SECONDS), { TextTransparency = 0 }):Play()
	end
	local function fadeOut()
		local tween = TweenService:Create(ui.Fade, TweenInfo.new(FADE_SECONDS * 1.6), { BackgroundTransparency = 1 })
		TweenService:Create(ui.FadeLabel, TweenInfo.new(FADE_SECONDS), { TextTransparency = 1 }):Play()
		tween.Completed:Once(function()
			if ui.Fade.BackgroundTransparency >= 0.99 then
				ui.Fade.Visible = false
			end
		end)
		tween:Play()
	end

	ui.Action.Activated:Connect(function()
		local portal = currentPortalId and ZoneConfig.Portals[currentPortalId]
		if not portal then
			return
		end
		local zoneId = portal.Target
		if isUnlocked(zoneId) then
			-- Viajar: cerrar el panel, fundido y pedir el viaje al servidor.
			PanelManager.close("Portal")
			travelToken += 1
			local token = travelToken
			fadeIn("Viajando a " .. ZoneConfig.Zones[zoneId].DisplayName .. "…")
			travelRemote:FireServer(zoneId)
			task.delay(TRAVEL_TIMEOUT, function()
				if travelToken == token then
					travelToken += 1
					fadeOut()
				end
			end)
		else
			if unlockPending then
				return
			end
			if ui.Action:GetAttribute("Disabled") then
				showMessage(ui.Feedback, MESSAGES[Codes.InsufficientEnergy], THEME.Error)
				return
			end
			unlockPending = true
			unlockRemote:FireServer(zoneId)
			task.delay(4, function()
				unlockPending = false
			end)
		end
	end)
	ui.Close.Activated:Connect(function()
		PanelManager.close("Portal")
	end)

	zoneResultRemote.OnClientEvent:Connect(function(success: boolean, code: string, zoneId: string?, missing: number?)
		unlockPending = false
		if success then
			local zone = zoneId and ZoneConfig.Zones[zoneId]
			showMessage(ui.Feedback, "¡" .. (if zone then zone.DisplayName else "Zona") .. " desbloqueado!", THEME.BuyHighlight)
		elseif code == Codes.InsufficientEnergy and typeof(missing) == "number" then
			showMessage(ui.Feedback, ("Te faltan ⚡ %s"):format(formatNumber(missing)), THEME.Error)
		else
			showMessage(ui.Feedback, MESSAGES[code] or tostring(code), THEME.Error)
		end
		render()
	end)

	travelResultRemote.OnClientEvent:Connect(function(success: boolean, code: string)
		travelToken += 1 -- anula el tiempo límite
		task.delay(if success then 0.2 else 0, fadeOut)
		if not success then
			showMessage(ui.Toast, MESSAGES[code] or tostring(code), THEME.Error)
		end
	end)

	-- Actualizar el panel si cambian la energía o las zonas desbloqueadas.
	player:GetAttributeChangedSignal(Constants.Attributes.Energy):Connect(function()
		if PanelManager.isOpen("Portal") then
			render()
		end
	end)
	player:GetAttributeChangedSignal(Constants.Attributes.UnlockedZones):Connect(function()
		if PanelManager.isOpen("Portal") then
			render()
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local portalId = prompt:GetAttribute("PortalId")
		if typeof(portalId) == "string" then
			local parent = prompt.Parent
			openPortal(portalId, if parent and parent:IsA("BasePart") then parent else nil)
		end
	end)

	-- Cerrar el panel al alejarse del portal.
	task.spawn(function()
		while true do
			task.wait(0.5)
			if PanelManager.isOpen("Portal") and currentPortalPart then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and (root.Position - currentPortalPart.Position).Magnitude > CLOSE_DISTANCE then
					PanelManager.close("Portal")
				end
			end
		end
	end)

	-- Tinte local de la zona actual (atributo que fija el servidor).
	local tint = Lighting:FindFirstChild("ZoneTint")
	if not (tint and tint:IsA("ColorCorrectionEffect")) then
		tint = Instance.new("ColorCorrectionEffect")
		tint.Name = "ZoneTint"
		tint.Parent = Lighting
	end
	local function applyZoneTint()
		local zoneId = player:GetAttribute(Constants.Attributes.CurrentZone)
		local target = (typeof(zoneId) == "string" and ZONE_TINTS[zoneId]) or NEUTRAL_TINT
		TweenService:Create(tint :: ColorCorrectionEffect, TweenInfo.new(1.2), target):Play()
	end
	player:GetAttributeChangedSignal(Constants.Attributes.CurrentZone):Connect(applyZoneTint)
	applyZoneTint()
end

return PortalController
