-- Interfaz de las puertas de energía entre zonas (se abren pagando 💰):
-- - Abre el panel de compra o permite desbloquear directamente la puerta.
-- - Cuando una zona está desbloqueada para el jugador local, su barrera de cristal
--   (`GateBarrier`) se vuelve invisible y sin colisión (`CanCollide = false`) para pasar caminando.
-- - Portales entre mundos (ZoneConfig.WorldPortals: el arco gigante de la Fortaleza Goblin al
--   Mundo 2 y el de vuelta): al cruzar su energía con el destino abierto, fundido y viaje
--   (TravelToZone). Cerrado, su energía se ve gris y avisa de qué jefe lo abre. El remolino de
--   los de tarima (Server.Util.PadPortal: el del spawn) gira aquí, solo en este cliente.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local DayNight = require(Shared.DayNight)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local Toasts = require(script.Parent.Parent.UI.Toasts)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local Codes = Constants.PurchaseCodes

local PANEL_SIZE = Vector2.new(440, 300)
local CLOSE_DISTANCE = 26
local FADE_SECONDS = 0.25
local TRAVEL_TIMEOUT = 8

local MESSAGES = {
	[Codes.InsufficientDiamonds] = "Diamantes insuficientes",
	[Codes.InsufficientMoney] = "Dinero insuficiente",
	[Codes.TooFar] = "Acércate a la puerta",
	[Codes.TooFast] = "Espera un momento",
	[Codes.NotReady] = "Cargando tus datos, inténtalo de nuevo",
	[Codes.ZoneLocked] = "Esta zona aún está bloqueada",
	[Codes.RebirthLocked] = "Necesitas más renacimientos",
	[Codes.BossLocked] = "Primero derrota al jefe de esta zona",
	[Codes.Busy] = "Ya estás viajando",
	[Codes.InvalidRequest] = "Solicitud no válida",
}

local ZONE_TINTS = {
	CrystalValley = { TintColor = Color3.fromRGB(236, 232, 255), Saturation = 0.08, Contrast = 0.04 },
	EmberCaldera = { TintColor = Color3.fromRGB(255, 232, 214), Saturation = 0.12, Contrast = 0.08 },
	FrozenTundra = { TintColor = Color3.fromRGB(232, 242, 255), Saturation = -0.08, Contrast = 0.05 },
	GoblinFortress = { TintColor = Color3.fromRGB(240, 255, 226), Saturation = 0.05, Contrast = 0.08 },
	World2 = { TintColor = Color3.fromRGB(255, 248, 236), Saturation = 0.14, Contrast = 0.04 },
}
local NEUTRAL_TINT = { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0 }
local ZONE_ATMOSPHERE = {
	EmberCaldera = { Color = Color3.fromRGB(214, 150, 120), Decay = Color3.fromRGB(120, 70, 60), Haze = 2, Density = 0.36 },
	FrozenTundra = { Color = Color3.fromRGB(220, 234, 250), Decay = Color3.fromRGB(150, 176, 214), Haze = 2.4, Density = 0.38 },
	GoblinFortress = { Color = Color3.fromRGB(190, 210, 160), Decay = Color3.fromRGB(90, 110, 70), Haze = 1.6, Density = 0.32 },
}
local ZONE_LIGHTING = {
	EmberCaldera = { ClockTime = 17.65, OutdoorAmbient = Color3.fromRGB(150, 112, 100), Ambient = Color3.fromRGB(90, 90, 100) },
}

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
		Text = "×",
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
	local currentPortalPosition: Vector3? = nil -- donde está la interacción de la puerta abierta
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

	-- Como ZoneLogic.isUnlocked: comprada, o sin precio (si pide un jefe, derrotado)
	local function isUnlocked(zoneId: string): boolean
		local zone = ZoneConfig.Zones[zoneId]
		local value = player:GetAttribute(Constants.Attributes.UnlockedZones)
		if typeof(value) == "string" and table.find(string.split(value, ","), zoneId) ~= nil then
			return true
		end
		if zone and (zone.UnlockCost or 0) <= 0 then
			if not zone.RequiredBoss then
				return true
			end
			local defeated = player:GetAttribute(Constants.Attributes.BossesDefeated)
			return typeof(defeated) == "string" and table.find(string.split(defeated, ","), zone.RequiredBoss) ~= nil
		end
		return false
	end

	local function money(): number
		local value = player:GetAttribute(Constants.Attributes.Money)
		return if typeof(value) == "number" then value else 0
	end

	local function rebirths(): number
		local value = player:GetAttribute(Constants.Attributes.Rebirths)
		return if typeof(value) == "number" then value else 0
	end

	-- Jefe que pide la zona y aún no ha derrotado (su definición), o nil
	local function missingBoss(zone)
		local bossId = zone.RequiredBoss
		if not bossId then
			return nil
		end
		local defeated = player:GetAttribute(Constants.Attributes.BossesDefeated)
		if typeof(defeated) == "string" and table.find(string.split(defeated, ","), bossId) then
			return nil
		end
		return EnemyConfig.Types[bossId]
	end

	-- Portales entre mundos: energía de su color si están abiertos; gris y con el aviso del
	-- jefe que los abre si no.
	local LOCKED_ENERGY = Color3.fromRGB(120, 120, 130)
	local function refreshWorldPortal(model: Instance, unlocked: boolean)
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") and (part.Name == "Energy" or part.Name == "EnergyArc" or part.Name == "EnergyGlow" or part.Name == "EnergyGlowArc") then
				local open = part:GetAttribute("OpenColor")
				if typeof(open) ~= "Color3" then
					part:SetAttribute("OpenColor", part.Color)
					open = part.Color
				end
				part.Color = if unlocked then open :: Color3 else LOCKED_ENERGY
			end
		end
		local sign = model:FindFirstChild("SignAnchor")
		local billboard = sign and sign:FindFirstChild("PortalSign")
		local lock = billboard and billboard:FindFirstChild("Lock")
		if lock and lock:IsA("TextLabel") then
			lock.Visible = not unlocked
		end
	end

	-- Actualiza las barreras físicas en el puente según las zonas desbloqueadas por el jugador.
	local function refreshGates()
		local folder = Workspace:FindFirstChild("ZonePortals")
		if not folder then
			return
		end
		for _, model in folder:GetChildren() do
			local worldPortalId = model:GetAttribute("WorldPortalId")
			local worldPortal = typeof(worldPortalId) == "string" and ZoneConfig.WorldPortals[worldPortalId]
			if worldPortal then
				refreshWorldPortal(model, isUnlocked(worldPortal.Target))
				continue
			end
			local portalId = model:GetAttribute("PortalId")
			local portal = typeof(portalId) == "string" and ZoneConfig.Portals[portalId]
			if not portal then
				continue
			end
			local unlocked = isUnlocked(portal.Target)
			local barrier = model:FindFirstChild("GateBarrier")
			if barrier and barrier:IsA("BasePart") then
				barrier.CanCollide = not unlocked
				local locked = barrier:GetAttribute("LockedTransparency")
				barrier.Transparency = if unlocked then 1 elseif typeof(locked) == "number" then locked else 0.6
				local prompt = barrier:FindFirstChild("PortalPrompt", true)
				if prompt and prompt:IsA("ProximityPrompt") then
					prompt.Enabled = not unlocked
				end
				local signGui = barrier:FindFirstChild("GateSign")
				if signGui and signGui:IsA("LayerCollector") then
					signGui.Enabled = not unlocked
				end
			end
		end
	end

	local function render()
		local portal = currentPortalId and ZoneConfig.Portals[currentPortalId]
		if not portal then
			return
		end
		local target = ZoneConfig.Zones[portal.Target]
		local cost = target.UnlockCost or 0
		ui.Title.Text = "Zona · " .. target.DisplayName
		ui.Subtitle.Text = "Desbloquea el puente con 💰 dinero para pasar a la siguiente zona."

		if isUnlocked(portal.Target) then
			ui.Status.Text = "✓ Puente Desbloqueado"
			ui.Status.TextColor3 = THEME.Accent
			ui.CostLine.Text = "¡Ya puedes cruzar caminando por el puente!"
			ui.MissingLine.Text = ""
			ui.Action.Text = "Cerrar"
			ui.Action.BackgroundColor3 = THEME.Buy
			ui.Action.TextColor3 = THEME.Text
			UiKit.setDisabled(ui.Action, false)
		else
			local have = money()
			local missing = math.max(0, cost - have)
			local needRebirths = target.RequiredRebirths or 0
			local haveRebirths = rebirths()
			ui.Status.Text = "🔒 Zona Bloqueada"
			ui.Status.TextColor3 = THEME.Gold
			local boss = missingBoss(target)
			if boss then
				ui.CostLine.Text = ("Requiere derrotar al 🏆 %s"):format(boss.DisplayName)
				ui.MissingLine.Text = ("Y además 💰 %s"):format(formatNumber(cost))
				ui.MissingLine.TextColor3 = THEME.Muted
				ui.Action.Text = "🔒 Derrota primero al jefe"
				ui.Action.BackgroundColor3 = THEME.Disabled
				ui.Action.TextColor3 = THEME.Muted
				UiKit.setDisabled(ui.Action, true)
				return
			end
			if needRebirths > haveRebirths then
				ui.CostLine.Text = ("Requiere 🔄 %d renacimientos   ·   Tienes 🔄 %d"):format(needRebirths, haveRebirths)
				ui.MissingLine.Text = ("Y además 💰 %s"):format(formatNumber(cost))
				ui.MissingLine.TextColor3 = THEME.Muted
				ui.Action.Text = ("🔒 Te faltan %d renacimientos"):format(needRebirths - haveRebirths)
				ui.Action.BackgroundColor3 = THEME.Disabled
				ui.Action.TextColor3 = THEME.Muted
				UiKit.setDisabled(ui.Action, true)
				return
			end
			ui.CostLine.Text = ("Coste: 💰 %s   ·   Tienes: 💰 %s"):format(formatNumber(cost), formatNumber(have))
			ui.MissingLine.Text = if missing > 0 then ("Te faltan 💰 %s"):format(formatNumber(math.ceil(missing))) else "¡Tienes suficiente dinero!"
			ui.MissingLine.TextColor3 = if missing > 0 then THEME.Error else THEME.BuyHighlight
			ui.Action.Text = "Desbloquear  ·  💰 " .. formatNumber(cost)
			local enabled = missing <= 0
			ui.Action.BackgroundColor3 = if enabled then THEME.Buy else THEME.Disabled
			ui.Action.TextColor3 = if enabled then THEME.Text else THEME.Muted
			UiKit.setDisabled(ui.Action, not enabled)
		end
	end

	PanelManager.register("Portal", ui.Panel, {
		OnClose = function()
			currentPortalId = nil
			currentPortalPosition = nil
		end,
	})
	UiKit.bindModalLayout(ui.ScreenGui, ui.PanelScale, PANEL_SIZE, function(position)
		PanelManager.setBasePosition("Portal", position)
	end)

	local function openPortal(portalId: string, at: Vector3?)
		if not ZoneConfig.Portals[portalId] then
			return
		end
		currentPortalId = portalId
		currentPortalPosition = at
		ui.Feedback.Text = ""
		render()
		PanelManager.open("Portal")
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
			PanelManager.close("Portal")
		else
			if unlockPending then
				return
			end
			if ui.Action:GetAttribute("Disabled") then
				local zone = ZoneConfig.Zones[zoneId]
				local code = if missingBoss(zone) then Codes.BossLocked elseif (zone.RequiredRebirths or 0) > rebirths() then Codes.RebirthLocked else Codes.InsufficientMoney
				showMessage(ui.Feedback, MESSAGES[code], THEME.Error)
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
		refreshGates()
		if success then
			local zone = zoneId and ZoneConfig.Zones[zoneId]
			Toasts.show("¡" .. (if zone then zone.DisplayName else "Zona") .. " desbloqueado!", { Color = THEME.BuyHighlight })
			PanelManager.close("Portal")
		elseif (code == Codes.InsufficientMoney or code == Codes.InsufficientDiamonds) and typeof(missing) == "number" then
			showMessage(ui.Feedback, ("Te faltan 💰 %s"):format(formatNumber(missing)), THEME.Error)
		elseif code == Codes.RebirthLocked and typeof(missing) == "number" then
			showMessage(ui.Feedback, ("Te faltan 🔄 %d renacimientos"):format(missing), THEME.Error)
		else
			showMessage(ui.Feedback, MESSAGES[code] or tostring(code), THEME.Error)
		end
		render()
	end)

	travelResultRemote.OnClientEvent:Connect(function(success: boolean, code: string)
		travelToken += 1
		task.delay(if success then 0.2 else 0, fadeOut)
		if not success then
			Toasts.show(MESSAGES[code] or tostring(code), { Color = THEME.Error })
		end
	end)

	player:GetAttributeChangedSignal(Constants.Attributes.Money):Connect(function()
		if PanelManager.isOpen("Portal") then
			render()
		end
	end)
	for _, attribute in { Constants.Attributes.UnlockedZones, Constants.Attributes.Rebirths, Constants.Attributes.BossesDefeated } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			refreshGates()
			if PanelManager.isOpen("Portal") then
				render()
			end
		end)
	end

	-- Cruzar un portal entre mundos: si su destino está abierto, fundido y viaje; si no, aviso.
	local WORLD_CHECK = 0.12
	local worldCooldownUntil = 0
	-- Portales que abren 🗺️ Viajar (OpensTravel: el del spawn) en los que ya estás dentro: el
	-- panel se abre al entrar, no cada vez que se revisa
	local insideHub: { [string]: boolean } = {}
	local lockedNoticeAt = 0
	local function fadeIn(text: string)
		ui.Fade.Visible = true
		ui.FadeLabel.Text = text
		TweenService:Create(ui.Fade, TweenInfo.new(FADE_SECONDS), { BackgroundTransparency = 0 }):Play()
		TweenService:Create(ui.FadeLabel, TweenInfo.new(FADE_SECONDS), { TextTransparency = 0 }):Play()
	end
	task.spawn(function()
		while true do
			task.wait(WORLD_CHECK)
			local folder = Workspace:FindFirstChild("ZonePortals")
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not (folder and root and root:IsA("BasePart")) or os.clock() < worldCooldownUntil then
				continue
			end
			for _, model in folder:GetChildren() do
				local portalId = model:GetAttribute("WorldPortalId")
				local portal = typeof(portalId) == "string" and ZoneConfig.WorldPortals[portalId]
				local energy = portal and model:FindFirstChild("Energy")
				if not (portal and energy and energy:IsA("BasePart")) then
					continue
				end
				local offset = root.Position - energy.Position
				local radius = portal.Radius or 8
				if Vector2.new(offset.X, offset.Z).Magnitude > radius or math.abs(offset.Y) > radius * 2 then
					insideHub[portalId] = nil
					continue
				end
				-- El portal del spawn no te lleva solo: abre 🗺️ Viajar para elegir la zona
				if portal.OpensTravel then
					if not insideHub[portalId] then
						insideHub[portalId] = true
						PanelManager.open("Travel")
					end
					break
				end
				local target = ZoneConfig.Zones[portal.Target]
				if isUnlocked(portal.Target) then
					worldCooldownUntil = os.clock() + TRAVEL_TIMEOUT
					travelToken += 1
					local token = travelToken
					fadeIn(("✨ Viajando a %s…"):format(if target then target.DisplayName else portal.Target))
					task.delay(FADE_SECONDS, function()
						travelRemote:FireServer(portal.Target)
					end)
					task.delay(TRAVEL_TIMEOUT, function()
						if travelToken == token then
							fadeOut()
						end
					end)
				elseif os.clock() - lockedNoticeAt > 4 then
					lockedNoticeAt = os.clock()
					local boss = target and target.RequiredBoss and EnemyConfig.Types[target.RequiredBoss]
					Toasts.show(if boss then ("🔒 El portal está cerrado: derrota al 👑 %s"):format(boss.DisplayName) else "🔒 El portal está cerrado", { Color = THEME.Error })
				end
				break
			end
		end
	end)
	-- Remolino de los portales de tarima (modelo "Swirl" con su SpinRate): gira mientras se ve
	local SPIN_DISTANCE = 220
	RunService.RenderStepped:Connect(function(dt)
		local folder = Workspace:FindFirstChild("ZonePortals")
		local camera = Workspace.CurrentCamera
		if not (folder and camera) then
			return
		end
		for _, model in folder:GetChildren() do
			local swirl = model:FindFirstChild("Swirl")
			if not (swirl and swirl:IsA("Model") and swirl.PrimaryPart) then
				continue
			end
			local pivot = swirl:GetPivot()
			if (pivot.Position - camera.CFrame.Position).Magnitude > SPIN_DISTANCE then
				continue
			end
			local rate = swirl:GetAttribute("SpinRate")
			swirl:PivotTo(pivot * CFrame.Angles(0, -(if typeof(rate) == "number" then rate else 1) * dt, 0))
		end
	end)
	travelResultRemote.OnClientEvent:Connect(function()
		worldCooldownUntil = os.clock() + 2.5
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local portalId = prompt:GetAttribute("PortalId")
		if typeof(portalId) == "string" then
			local parent = prompt.Parent
			openPortal(
				portalId,
				if parent and parent:IsA("Attachment") then parent.WorldPosition
					elseif parent and parent:IsA("BasePart") then parent.Position
					else nil
			)
		end
	end)

	task.spawn(function()
		while true do
			refreshGates()
			task.wait(1.0)
			if PanelManager.isOpen("Portal") and currentPortalPosition then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and (root.Position - currentPortalPosition).Magnitude > CLOSE_DISTANCE then
					PanelManager.close("Portal")
				end
			end
		end
	end)

	local tint = Lighting:FindFirstChild("ZoneTint")
	if not (tint and tint:IsA("ColorCorrectionEffect")) then
		tint = Instance.new("ColorCorrectionEffect")
		tint.Name = "ZoneTint"
		tint.Parent = Lighting
	end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local defaultAtmosphere = if atmosphere then { Color = atmosphere.Color, Decay = atmosphere.Decay, Haze = atmosphere.Haze, Density = atmosphere.Density } else nil
	local defaultLighting = { ClockTime = Lighting.ClockTime, OutdoorAmbient = Lighting.OutdoorAmbient }
	local function applyZoneTint()
		local zoneId = player:GetAttribute(Constants.Attributes.CurrentZone)
		local target = (typeof(zoneId) == "string" and ZONE_TINTS[zoneId]) or NEUTRAL_TINT
		TweenService:Create(tint :: ColorCorrectionEffect, TweenInfo.new(1.2), target):Play()
		if atmosphere and defaultAtmosphere then
			local air = (typeof(zoneId) == "string" and ZONE_ATMOSPHERE[zoneId]) or defaultAtmosphere
			TweenService:Create(atmosphere, TweenInfo.new(1.5), air):Play()
		end
		local light = typeof(zoneId) == "string" and ZONE_LIGHTING[zoneId]
		if light then
			TweenService:Create(Lighting, TweenInfo.new(1.5), light):Play()
		elseif not DayNight.enabled() then
			TweenService:Create(Lighting, TweenInfo.new(1.5), defaultLighting):Play()
		end
	end
	player:GetAttributeChangedSignal(Constants.Attributes.CurrentZone):Connect(applyZoneTint)
	applyZoneTint()
end

return PortalController
