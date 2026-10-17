-- Tutorial inicial en el cliente (solo presentación; el servidor marca los pasos):
-- - Lee TutorialStatus / TutorialStep (atributos del servidor). Sin atributos (datos no
--   cargados o carga fallida) no se muestra nada.
-- - Tarjeta compacta arriba a la derecha (lejos del chat, del combate y de los controles
--   táctiles): paso actual, explicación y progreso orientativo. Se puede plegar (–) y
--   omitir (dos pulsaciones: "Omitir" -> "¿Seguro?"), que es lo único que se envía.
-- - Guía: en el mundo, un rayo y una flecha hacia el cristal, el santuario o el portal
--   (desaparecen al llegar); en la interfaz, un marco que parpadea sobre el botón a usar.
-- - Al completarlo se felicita una vez y desaparece. Nunca da recompensas.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local TutorialConfig = require(Shared.Config.TutorialConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local EggConfig = require(Shared.Config.EggConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local Attributes = Constants.Attributes
local CARD_SIZE = Vector2.new(320, 128)
local GUIDE_COLOR = Color3.fromRGB(110, 236, 220)
local STEPS = TutorialConfig.Steps

local TutorialController = {}

local player = Players.LocalPlayer

-- Posiciones del mundo con las mismas fórmulas que el servidor (configuración compartida).
local function zoneCenter(zoneId: string): Vector3?
	local zone = ZoneConfig.Zones[zoneId]
	if not zone then
		return nil
	end
	local base = GeneratorConfig.Position
	return Vector3.new(base.X + zone.Center.X, base.Y, base.Z + zone.Center.Y)
end

local function guideTarget(guide: string): (Vector3?, string?)
	if guide == "Crystal" then
		-- Centro visual del cristal flotante del santuario.
		return GeneratorConfig.Position + Vector3.new(0, GeneratorConfig.CoreHeight, 0), ZoneConfig.DefaultZone or "Forest"
	end
	local kind, id = guide:match("^(%a+):(%w+)$")
	if kind == "Egg" then
		local egg = EggConfig.Eggs[id]
		local zoneId = egg and (egg.Zone or ZoneConfig.DefaultZone or "Forest")
		local center = zoneId and zoneCenter(zoneId)
		if egg and center then
			return center + Vector3.new(egg.StandOffset.X, 5, egg.StandOffset.Y), zoneId
		end
	elseif kind == "Portal" then
		local portal = ZoneConfig.Portals[id]
		local center = portal and zoneCenter(portal.Zone)
		if portal and center then
			return center + Vector3.new(portal.Offset.X, 8, portal.Offset.Y), portal.Zone
		end
	end
	return nil, nil
end

-- Botón de la interfaz que señala un paso (de otros controladores; solo se lee).
local function guideButton(guide: string): GuiObject?
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local hudName, buttonName = nil, nil
	if guide == "UpgradeButton" then
		hudName, buttonName = "EnergyHud", "UpgradeButton"
	elseif guide == "PetsButton" then
		hudName, buttonName = "PetsHud", "PetsButton"
	end
	local hud = hudName and playerGui:FindFirstChild(hudName)
	local button = hud and hud:FindFirstChild(buttonName :: string, true)
	return if button and button:IsA("GuiObject") then button else nil
end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("TutorialHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "TutorialHud",
		ResetOnSpawn = false,
		DisplayOrder = 4, -- sobre el HUD, por debajo de los paneles modales
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)

	local card, cardScale = UiKit.panel(screenGui, "Card", CARD_SIZE, Vector2.new(1, 0), UDim2.new(1, -16, 0, 12))
	card.Visible = false
	local header = UiKit.text(card, "Header", {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -110, 0, 18),
		Font = FONTS.Light,
		TextSize = 14,
		TextColor3 = GUIDE_COLOR,
	})
	local title = UiKit.text(card, "Title", {
		Position = UDim2.fromOffset(16, 28),
		Size = UDim2.new(1, -32, 0, 24),
		Font = FONTS.Display,
		TextSize = 20,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local body = UiKit.text(card, "Body", {
		Position = UDim2.fromOffset(16, 54),
		Size = UDim2.new(1, -32, 0, 36),
		Font = FONTS.Light,
		TextSize = 14,
		TextColor3 = THEME.Muted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local track = UiKit.create("Frame", {
		Name = "Track",
		Position = UDim2.new(0, 16, 1, -26),
		Size = UDim2.new(1, -110, 0, 10),
		BackgroundColor3 = THEME.Inset,
	}, card)
	UiKit.corner(track, 5)
	local fill = UiKit.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = GUIDE_COLOR,
	}, track)
	UiKit.corner(fill, 5)
	local progressText = UiKit.text(card, "Progress", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 1, -32),
		Size = UDim2.fromOffset(86, 20),
		Font = FONTS.Body,
		TextSize = 13,
		TextColor3 = THEME.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local skip = UiKit.button(card, "Skip", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -48, 0, 8),
		Size = UDim2.fromOffset(78, 26),
		BackgroundColor3 = THEME.Secondary,
		Font = FONTS.Body,
		TextSize = 13,
		Text = "Omitir",
	})
	local collapse = UiKit.button(card, "Collapse", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(32, 26),
		BackgroundColor3 = THEME.Inset,
		TextSize = 18,
		Text = "–",
	})

	-- Versión plegada: una píldora que vuelve a abrir la tarjeta.
	local pill, pillScale = UiKit.panel(screenGui, "Pill", Vector2.new(170, 40), Vector2.new(1, 0), UDim2.new(1, -16, 0, 12))
	pill.Visible = false
	local pillButton = UiKit.create("TextButton", {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = FONTS.Display,
		TextSize = 17,
		TextColor3 = THEME.Text,
	}, pill)
	UiKit.addStates(pillButton)

	-- Marco que señala un botón de la interfaz (no captura clics).
	local marker = UiKit.create("Frame", {
		Name = "ButtonMarker",
		BackgroundTransparency = 1,
		Active = false,
		Visible = false,
		ZIndex = 10,
	}, screenGui)
	UiKit.corner(marker, 14)
	local markerStroke = UiKit.stroke(marker, GUIDE_COLOR, 3, 0)
	TweenService:Create(markerStroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.75 }):Play()

	screenGui.Parent = playerGui
	UiKit.bindScale(screenGui, { cardScale, pillScale })
	return {
		ScreenGui = screenGui,
		Card = card,
		CardScale = cardScale,
		Header = header,
		Title = title,
		Body = body,
		Fill = fill,
		Progress = progressText,
		Skip = skip,
		Collapse = collapse,
		Pill = pill,
		PillButton = pillButton,
		Marker = marker,
	}
end

function TutorialController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local skipRemote = remotes:WaitForChild(Constants.Remotes.SkipTutorial) :: RemoteEvent
	local ui = buildGui()

	local collapsed = false
	local confirmSkip = false
	local wasActive = false
	local celebrating = false

	-- Guía en el mundo: un ancla invisible en el destino, una flecha flotante y un rayo
	-- desde el personaje. Solo existe mientras hay un paso con destino en el mundo.
	local guideFolder = Instance.new("Folder")
	guideFolder.Name = "ClientTutorialGuide"
	local anchor = Instance.new("Part")
	anchor.Name = "GuideAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Parent = guideFolder
	local targetAttachment = Instance.new("Attachment")
	targetAttachment.Parent = anchor
	local arrow = Instance.new("BillboardGui")
	arrow.Size = UDim2.fromOffset(46, 46)
	arrow.AlwaysOnTop = true
	arrow.LightInfluence = 0
	arrow.Parent = anchor
	UiKit.text(arrow, "Arrow", {
		Size = UDim2.fromScale(1, 1),
		Font = FONTS.Display,
		TextScaled = true,
		TextColor3 = GUIDE_COLOR,
		TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "▼",
	})
	TweenService:Create(arrow, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { StudsOffset = Vector3.new(0, 1.2, 0) }):Play()
	local beam = Instance.new("Beam")
	beam.Attachment1 = targetAttachment
	beam.Color = ColorSequence.new(GUIDE_COLOR)
	beam.Transparency = NumberSequence.new(0.35, 0.85)
	beam.Width0 = 0.3
	beam.Width1 = 0.3
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Segments = 1
	beam.Parent = anchor
	local sourceAttachment: Attachment? = nil

	local function currentStep(): (any, number)
		local status = player:GetAttribute(Attributes.TutorialStatus)
		local done = player:GetAttribute(Attributes.TutorialStep)
		if status ~= "Active" or typeof(done) ~= "number" then
			return nil, 0
		end
		local index = math.clamp(math.floor(done) + 1, 1, #STEPS)
		return STEPS[index], index
	end

	local function setWorldGuide(target: Vector3?)
		if not target then
			guideFolder.Parent = nil
			return
		end
		anchor.CFrame = CFrame.new(target)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and (not sourceAttachment or sourceAttachment.Parent ~= root) then
			if sourceAttachment then
				sourceAttachment:Destroy()
			end
			local attachment = Instance.new("Attachment")
			attachment.Name = "TutorialGuideSource"
			attachment.Parent = root
			sourceAttachment = attachment
		end
		beam.Attachment0 = sourceAttachment
		guideFolder.Parent = Workspace
	end

	local markerConnections: { RBXScriptConnection } = {}
	local markedButton: GuiObject? = nil
	local function setButtonGuide(button: GuiObject?)
		if button == markedButton and (button == nil or #markerConnections > 0) then
			return -- ya señalado: no se reconecta en cada repaso
		end
		markedButton = button
		for _, connection in markerConnections do
			connection:Disconnect()
		end
		table.clear(markerConnections)
		if not button then
			ui.Marker.Visible = false
			return
		end
		local function place()
			local padding = 6
			ui.Marker.Position = UDim2.fromOffset(button.AbsolutePosition.X - padding, button.AbsolutePosition.Y - padding)
			ui.Marker.Size = UDim2.fromOffset(button.AbsoluteSize.X + padding * 2, button.AbsoluteSize.Y + padding * 2)
			ui.Marker.Visible = button.Visible and button.AbsoluteSize.X > 0
		end
		table.insert(markerConnections, button:GetPropertyChangedSignal("AbsolutePosition"):Connect(place))
		table.insert(markerConnections, button:GetPropertyChangedSignal("AbsoluteSize"):Connect(place))
		place()
	end

	-- La tarjeta baja si el aviso de estado de datos ocupa la esquina.
	local function placeCard()
		local status = player:FindFirstChildOfClass("PlayerGui")
		local dataHud = status and status:FindFirstChild("DataStatusHud")
		local dataCard = dataHud and dataHud:FindFirstChild("Card")
		local offset = 12
		if dataCard and dataCard:IsA("GuiObject") and dataCard.Visible then
			offset = 12 + math.ceil(dataCard.AbsoluteSize.Y) + 8
		end
		ui.Card.Position = UDim2.new(1, -16, 0, offset)
		ui.Pill.Position = UDim2.new(1, -16, 0, offset)
	end

	-- Progreso orientativo con los datos que ya ve el cliente (no decide nada).
	local function progressFor(step): (number, string)
		local energy = player:GetAttribute(Attributes.Energy)
		energy = if typeof(energy) == "number" then energy else 0
		if step.Id == "Energy" then
			return math.clamp(energy / step.Target, 0, 1), ("%s/%s ⚡"):format(formatNumber(math.min(energy, step.Target)), formatNumber(step.Target))
		elseif step.Id == "Valley" then
			local zone = ZoneConfig.Zones[step.Goal.Zone]
			local cost = zone and zone.UnlockCost or 0
			if cost > 0 then
				return math.clamp(energy / cost, 0, 1), ("%s/%s ⚡"):format(formatNumber(math.min(energy, cost)), formatNumber(cost))
			end
		end
		return 0, ""
	end

	local function render()
		local step, index = currentStep()
		local status = player:GetAttribute(Attributes.TutorialStatus)
		if not step then
			-- Felicitación una sola vez si se completa durante la sesión.
			if wasActive and status == "Completed" and not celebrating then
				celebrating = true
				ui.Pill.Visible = false
				ui.Card.Visible = true
				ui.Header.Text = "Tutorial"
				ui.Title.Text = "¡Tutorial completado! ✦"
				ui.Body.Text = "Sigue avanzando con las 📜 Misiones (tecla M)."
				ui.Fill.Size = UDim2.fromScale(1, 1)
				ui.Progress.Text = ""
				ui.Skip.Visible = false
				ui.Collapse.Visible = false
				task.delay(5, function()
					ui.Card.Visible = false
				end)
			elseif not celebrating then
				ui.Card.Visible = false
				ui.Pill.Visible = false
			end
			wasActive = false
			setWorldGuide(nil)
			setButtonGuide(nil)
			return
		end
		wasActive = true
		placeCard()
		ui.Skip.Visible = true
		ui.Collapse.Visible = true
		ui.Header.Text = ("Tutorial · paso %d de %d"):format(index, #STEPS)
		ui.Title.Text = step.Title
		ui.Body.Text = step.Text
		local ratio, label = progressFor(step)
		ui.Fill.Size = UDim2.fromScale(ratio, 1)
		ui.Progress.Text = label
		ui.PillButton.Text = ("📖 Tutorial %d/%d"):format(index, #STEPS)
		ui.Card.Visible = not collapsed
		ui.Pill.Visible = collapsed
		ui.Skip.Text = if confirmSkip then "¿Seguro?" else "Omitir"

		-- Guía: botón de la interfaz o destino en el mundo (si está en esa zona y lejos).
		local target, zoneId = guideTarget(step.Guide)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local currentZone = player:GetAttribute(Attributes.CurrentZone)
		local sameZone = zoneId == nil or currentZone == nil or currentZone == zoneId
		local far = root and root:IsA("BasePart") and target and (root.Position - target).Magnitude > TutorialConfig.GuideHideDistance
		setWorldGuide(if target and sameZone and far and not collapsed then target else nil)
		setButtonGuide(if not collapsed then guideButton(step.Guide) else nil)
	end

	ui.Collapse.Activated:Connect(function()
		collapsed = true
		confirmSkip = false
		render()
	end)
	ui.PillButton.Activated:Connect(function()
		collapsed = false
		render()
	end)
	ui.Skip.Activated:Connect(function()
		if not confirmSkip then
			confirmSkip = true
			render()
			task.delay(4, function()
				if confirmSkip then
					confirmSkip = false
					render()
				end
			end)
			return
		end
		confirmSkip = false
		skipRemote:FireServer() -- el servidor decide; la tarjeta se oculta cuando lo confirma
	end)

	for _, attribute in { Attributes.TutorialStatus, Attributes.TutorialStep, Attributes.Energy, Attributes.CurrentZone } do
		player:GetAttributeChangedSignal(attribute):Connect(render)
	end
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 5)
		render()
	end)
	-- La distancia al destino cambia al moverse: se revisa cada medio segundo solo
	-- mientras hay un tutorial activo (no hay ningún bucle si no lo hay).
	local watching = false
	local function watchDistance()
		if watching then
			return
		end
		watching = true
		task.spawn(function()
			while currentStep() ~= nil do
				task.wait(0.5)
				render()
			end
			watching = false
		end)
	end
	player:GetAttributeChangedSignal(Attributes.TutorialStatus):Connect(watchDistance)
	render()
	watchDistance()
end

return TutorialController
