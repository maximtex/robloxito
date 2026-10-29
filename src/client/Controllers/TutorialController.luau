-- Tutorial inicial en el cliente (solo presentación; el servidor marca los pasos):
-- - Lee TutorialStatus / TutorialStep (atributos del servidor). Sin atributos (datos no
--   cargados o carga fallida) no se muestra nada.
-- - Banner amarillo arriba en el centro: paso (1/4), qué hacer (una línea corta), progreso
--   orientativo y el premio del paso debajo. Se puede omitir tras la práctica (dos
--   pulsaciones: "Omitir" -> "¿Seguro?"), lo único que se envía.
-- - Premios: aviso al recibirlos (TutorialReward).
-- - Después (completado u omitido): el siguiente objetivo (atributo TutorialNext: la cueva y
--   luego el portal del Valle) en el mismo banner, con su flecha; × lo oculta esta sesión.
-- - Guía: en el mundo, un rayo y una flecha hacia el altar de las oleadas, el santuario o
--   el portal (desaparecen al llegar); en la interfaz, un marco que parpadea sobre el botón.
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
local EnemyConfig = require(Shared.Config.EnemyConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local WaveConfig = require(Shared.Config.WaveConfig)
local CaveConfig = require(Shared.Config.CaveConfig)
local CaveLogic = require(Shared.CaveLogic)
local formatNumber = require(Shared.Util.FormatNumber)
local ItemConfig = require(Shared.Config.ItemConfig)
local Toasts = require(script.Parent.Parent.UI.Toasts)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudDock = require(script.Parent.Parent.UI.HudDock)
local MenuBar = require(script.Parent.Parent.UI.MenuBar)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local Attributes = Constants.Attributes
local CARD_SIZE = Vector2.new(600, 92)
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

local function guideTarget(guide: string?): (Vector3?, string?)
	if not guide then
		return nil, nil
	elseif guide == "Waves" then
		-- Altar de la práctica de las oleadas, en el centro de su círculo (WaveConfig.Places).
		local settings
		for _, arena in WaveConfig.Arenas do
			if arena.Tutorial then
				settings = WaveConfig.Places[arena.Place]
			end
		end
		if not settings then
			return nil, nil
		end
		local center = zoneCenter(settings.Zone)
		if center then
			return center + Vector3.new(settings.Offset.X, 6, settings.Offset.Y), settings.Zone
		end
		return nil, nil
	elseif guide == "Cave" then
		-- Fuera: la boca de la cueva. Dentro: la primera puerta cerrada (delante de ella) o, con
		-- todas abiertas, el altar de las Oleadas del Guardián.
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local inside = root ~= nil and root:IsA("BasePart") and (CaveLogic.caveAt(root.Position.X, root.Position.Z, 4)) == CaveConfig.Zone
		if inside then
			local progress = CaveLogic.parseProgress(player:GetAttribute(Attributes.CaveGates))
			for index, gate in CaveConfig.Gates do
				if gate.Cave == CaveConfig.Zone and not CaveLogic.isOpen(progress, index) then
					local front = gate.Position + gate.Facing * 4
					return Vector3.new(front.X, GeneratorConfig.Position.Y + 6, front.Z), CaveConfig.Zone
				end
			end
			local altar = CaveLogic.altarCenter()
			if altar then
				return Vector3.new(altar.X, GeneratorConfig.Position.Y + 6, altar.Y), CaveConfig.Zone
			end
		end
		-- La boca está en el Bosque de Espinas (CaveConfig.EntranceZone), junto a la puerta del Valle
		local mouth = CaveConfig.Entrance.Guide
		return Vector3.new(mouth.X, GeneratorConfig.Position.Y + mouth.Y, mouth.Z), CaveConfig.EntranceZone or CaveConfig.Zone
	end
	local kind, id = guide:match("^(%a+):(%w+)$")
	if kind == "Egg" then
		local egg = EggConfig.Eggs[id]
		local zoneId = egg and (egg.Zone or ZoneConfig.DefaultZone or "Forest")
		local center = zoneId and zoneCenter(zoneId)
		if egg and center then
			return center + Vector3.new(egg.StandOffset.X, 5, egg.StandOffset.Y), zoneId
		end
	elseif kind == "Arena" then
		local zoneSettings = EnemyConfig.Zones[id]
		local arena = zoneSettings and zoneSettings.Boss and zoneSettings.Boss.Arena
		local center = arena and zoneCenter(id)
		if arena and center then
			return center + Vector3.new(arena.Center.X, 6, arena.Center.Y), id
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

-- Primer portal del camino de `from` a `to` (andando de zona en zona por ZoneConfig.Portals), o
-- nil si no hay camino.
local function portalToward(from: string, to: string): string?
	local firstStep: { [string]: string } = {}
	local queue = { from }
	local seen = { [from] = true }
	local head = 1
	while queue[head] do
		local zone = queue[head]
		head += 1
		for portalId, portal in ZoneConfig.Portals do
			local nextZone = if portal.Zone == zone then portal.Target elseif portal.Target == zone then portal.Zone else nil
			if nextZone and not seen[nextZone] then
				seen[nextZone] = true
				-- (hacia atrás es el mismo portal: está en la frontera entre las dos)
				firstStep[nextZone] = firstStep[zone] or portalId
				if nextZone == to then
					return firstStep[nextZone]
				end
				table.insert(queue, nextZone)
			end
		end
	end
	return nil
end

-- Botón de la interfaz que señala un paso (de otros controladores; solo se lee).
local function guideButton(guide: string?): GuiObject?
	if guide == "PetsButton" then
		return MenuBar.tile("Pets") -- azulejo "Mascotas" de la barra del menú
	elseif guide == "ArmoryButton" then
		return MenuBar.tile("Armory") -- azulejo "Armas" (la Armería)
	elseif guide == "SkillsButton" then
		-- el ⚡ del segundo botón de habilidad (StyleController), que abre ⚡ Mejoras
		local hud = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("StyleHud")
		local button = hud and hud:FindFirstChild("Skills", true)
		return if button and button:IsA("GuiObject") then button else nil
	end
	return nil
end

-- Texto del premio: "+250 💰 · ❤️ ×2"
local function rewardText(reward: any): string
	if type(reward) ~= "table" then
		return ""
	end
	local parts = {}
	if type(reward.Money) == "number" and reward.Money > 0 then
		table.insert(parts, ("+%s 💰"):format(formatNumber(reward.Money)))
	end
	if type(reward.Potions) == "table" then
		for potionId, count in reward.Potions do
			local def = ItemConfig.Potions[potionId]
			if def and type(count) == "number" and count > 0 then
				table.insert(parts, ("%s ×%d"):format(def.Icon or "🧪", count))
			end
		end
	end
	return table.concat(parts, " · ")
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

	-- Banner amarillo estilo simulador arriba en el centro (como en las capturas 1 y 2)
	local card = UiKit.create("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y),
		BackgroundColor3 = Color3.fromRGB(255, 204, 54),
		Visible = false,
	}, screenGui)
	local cardScale = UiKit.create("UIScale", {}, card)
	UiKit.corner(card, 10)
	UiKit.stroke(card, Color3.fromRGB(20, 20, 24), 3, 0)

	-- Patrón sutil de cuadros estilo studs dentro del banner amarillo
	local studsHolder = UiKit.create("Frame", {
		Name = "StudsPattern",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, card)
	for col = 0, math.ceil(CARD_SIZE.X / 35) do
		for row = 0, math.ceil(CARD_SIZE.Y / 25) do
			local stud = UiKit.create("Frame", {
				Position = UDim2.fromOffset(8 + col * 35, 6 + row * 25),
				Size = UDim2.fromOffset(26, 20),
				BackgroundColor3 = Color3.fromRGB(238, 182, 36),
				BackgroundTransparency = 0.55,
			}, studsHolder)
			UiKit.corner(stud, 4)
		end
	end

	local fill = UiKit.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(255, 224, 82),
		BackgroundTransparency = 0.55,
		ZIndex = 2,
	}, card)
	UiKit.corner(fill, 10)

	local header = UiKit.text(card, "Header", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, -2),
		Size = UDim2.fromOffset(260, 24),
		Font = FONTS.Display,
		TextSize = 20,
		TextColor3 = Color3.fromRGB(255, 226, 56),
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "Tutorial",
		ZIndex = 5,
	})
	UiKit.outline(header, 2.5)

	local title = UiKit.text(card, "Title", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(1, -150, 0, 32),
		Font = FONTS.Display,
		TextSize = 27,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	})
	UiKit.create("UITextSizeConstraint", { MaxTextSize = 27, MinTextSize = 16 }, title)
	UiKit.outline(title, 3)

	-- Qué hacer, en una o dos líneas cortas (antes no se veía: solo el título)
	local body = UiKit.text(card, "Body", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 46),
		Size = UDim2.new(1, -36, 0, 40),
		Font = FONTS.Body,
		TextSize = 16,
		TextWrapped = true,
		TextColor3 = Color3.fromRGB(58, 38, 4),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 4,
	})

	-- Premio del paso: una pestaña oscura colgando debajo del banner
	local rewardTab = UiKit.create("Frame", {
		Name = "Reward",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.fromOffset(230, 28),
		BackgroundColor3 = Color3.fromRGB(40, 44, 54),
		Visible = false,
		ZIndex = 3,
	}, card)
	UiKit.corner(rewardTab, 8)
	UiKit.stroke(rewardTab, Color3.fromRGB(20, 20, 24), 2, 0)
	local rewardLabel = UiKit.text(rewardTab, "Label", {
		Size = UDim2.fromScale(1, 1),
		Font = FONTS.Body,
		TextSize = 14,
		TextColor3 = Color3.fromRGB(255, 226, 120),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	})
	local progressText = UiKit.text(card, "Progress", {
		Visible = false,
		Size = UDim2.fromOffset(0, 0),
	})
	local skip = UiKit.button(card, "Skip", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(64, 26),
		BackgroundColor3 = Color3.fromRGB(40, 44, 54),
		Font = FONTS.Body,
		TextSize = 11,
		Text = "Omitir",
		ZIndex = 6,
	})
	local collapse = UiKit.button(card, "Collapse", {
		Visible = false,
		Size = UDim2.fromOffset(0, 0),
	})

	-- Versión plegada: una píldora que vuelve a abrir la tarjeta.
	local pill, pillScale = UiKit.panel(screenGui, "Pill", Vector2.new(170, 40), Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 12))
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
		RewardTab = rewardTab,
		RewardLabel = rewardLabel,
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
	local rewardRemote = remotes:WaitForChild(Constants.Remotes.TutorialReward) :: RemoteEvent
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
	beam.Color = ColorSequence.new(Color3.new(1, 1, 1))
	beam.Transparency = NumberSequence.new(1)
	beam.Width0 = 0.2
	beam.Width1 = 0.2
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Segments = 1
	beam.Parent = anchor
	local sourceAttachment: Attachment? = nil

	-- Flechas blancas con borde negro en el suelo (como en las capturas 1, 2 y 4)
	local MAX_CHEVRONS = 9
	local chevrons: { Part } = {}
	for i = 1, MAX_CHEVRONS do
		local p = Instance.new("Part")
		p.Name = "Chevron_" .. i
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Transparency = 1
		p.Size = Vector3.new(2.6, 0.1, 2.6)
		p.Parent = guideFolder

		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(2.4, 0, 2.4, 0)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.Adornee = p
		bb.Parent = p

		local lbl = UiKit.text(bb, "ArrowGlyph", {
			Size = UDim2.fromScale(1, 1),
			Font = FONTS.Display,
			TextScaled = true,
			TextColor3 = Color3.fromRGB(246, 250, 255),
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "➤",
		})
		UiKit.outline(lbl, 3)
		table.insert(chevrons, p)
	end

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
		if root and root:IsA("BasePart") then
			local startPos = Vector3.new(root.Position.X, GeneratorConfig.Position.Y + 0.85, root.Position.Z)
			local endPos = Vector3.new(target.X, GeneratorConfig.Position.Y + 0.85, target.Z)
			local diff = endPos - startPos
			local dist = diff.Magnitude
			local dir = if dist > 0.1 then diff.Unit else Vector3.new(0, 0, -1)
			for i, chev in chevrons do
				local stepDist = i * 3.1
				if stepDist < dist - 2 then
					chev.CFrame = CFrame.lookAt(startPos + dir * stepDist, endPos)
					local bb = chev:FindFirstChildOfClass("BillboardGui")
					if bb then
						bb.Enabled = true
					end
				else
					local bb = chev:FindFirstChildOfClass("BillboardGui")
					if bb then
						bb.Enabled = false
					end
				end
			end
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

	-- Siguiente objetivo tras el tutorial (atributo TutorialNext; × lo oculta esta sesión)
	local dismissed: { [string]: boolean } = {}
	local nextById: { [string]: any } = {}
	for _, goal in TutorialConfig.NextGoals or {} do
		nextById[goal.Id] = goal
	end
	local function currentNext(): any?
		local status = player:GetAttribute(Attributes.TutorialStatus)
		local id = player:GetAttribute(Attributes.TutorialNext)
		if (status ~= "Completed" and status ~= "Skipped") or typeof(id) ~= "string" or id == "" or dismissed[id] then
			return nil
		end
		return nextById[id]
	end

	-- Progreso orientativo con los datos que ya ve el cliente (no decide nada).
	local function progressFor(step): (number, string)
		if step.Id == "Valley" then
			-- el portal se paga con 💰
			local money = player:GetAttribute(Attributes.Money)
			money = if typeof(money) == "number" then money else 0
			local zone = ZoneConfig.Zones[step.Goal.Zone]
			local cost = zone and zone.UnlockCost or 0
			if cost > 0 then
				return math.clamp(money / cost, 0, 1), ("%s/%s 💰"):format(formatNumber(math.min(money, cost)), formatNumber(cost))
			end
		end
		return 0, ""
	end

	-- Guía: botón de la interfaz o destino en el mundo (si está en esa zona y lejos).
	local function applyGuide(guide: string?)
		local target, zoneId = guideTarget(guide)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local currentZone = player:GetAttribute(Attributes.CurrentZone)
		-- Destino en otra zona (la cueva, desde el pueblo): primero, el portal hacia allí
		if target and zoneId and typeof(currentZone) == "string" and currentZone ~= zoneId then
			local portalId = portalToward(currentZone, zoneId)
			if portalId then
				target = guideTarget("Portal:" .. portalId)
				zoneId = currentZone -- el portal está en la frontera: se ve desde los dos lados
			end
		end
		local sameZone = zoneId == nil or currentZone == nil or currentZone == zoneId
		local far = root and root:IsA("BasePart") and target and (root.Position - target).Magnitude > TutorialConfig.GuideHideDistance
		setWorldGuide(if target and sameZone and far and not collapsed then target else nil)
		setButtonGuide(if not collapsed then guideButton(guide) else nil)
	end

	-- Título, instrucción y progreso de un paso o de un objetivo
	local function show(entry: any, header: string)
		local ratio, label = progressFor(entry)
		local cleanProgress = label:gsub("%s*💰", "")
		ui.Header.Text = header
		ui.Title.Text = if cleanProgress ~= ""
			then string.upper(entry.Title) .. " (" .. cleanProgress .. ")"
			else string.upper(entry.Title)
		ui.Body.Text = entry.Text
		ui.Fill.Size = UDim2.fromScale(ratio, 1)
		ui.Progress.Text = label
		ui.Card.Visible = not collapsed
		ui.Pill.Visible = collapsed
		ui.Collapse.Visible = false
	end

	local mode: string? = nil -- "Step", "Next", "Done" o nil
	local function render()
		local step, index = currentStep()
		local status = player:GetAttribute(Attributes.TutorialStatus)
		if not step then
			-- Felicitación una sola vez si se completa durante la sesión (5 s; luego, el
			-- siguiente objetivo).
			if wasActive and status == "Completed" and not celebrating then
				celebrating = true
				wasActive = false
				mode = "Done"
				ui.Pill.Visible = false
				ui.Card.Visible = true
				ui.Header.Text = "Tutorial"
				ui.Title.Text = "¡TUTORIAL COMPLETADO! ★"
				ui.Body.Text = "Usa la ❤️ poción (Y) cuando te quede poca vida. Ahora, a por tu siguiente objetivo."
				ui.Fill.Size = UDim2.fromScale(1, 1)
				ui.Progress.Text = ""
				ui.RewardTab.Visible = false
				ui.Skip.Visible = false
				ui.Collapse.Visible = false
				setWorldGuide(nil)
				setButtonGuide(nil)
				task.delay(5, function()
					celebrating = false
					render()
				end)
				return
			end
			wasActive = false
			if celebrating then
				return
			end
			local goal = currentNext()
			if goal then
				mode = "Next"
				show(goal, "🎯 Siguiente objetivo")
				ui.RewardTab.Visible = false
				ui.Skip.Visible = true
				ui.Skip.Text = "×"
				applyGuide(goal.Guide)
				return
			end
			mode = nil
			ui.Card.Visible = false
			ui.Pill.Visible = false
			setWorldGuide(nil)
			setButtonGuide(nil)
			return
		end
		wasActive = true
		mode = "Step"
		show(step, ("Tutorial %d/%d"):format(index, #STEPS))
		ui.PillButton.Text = ("📖 Tutorial %d/%d"):format(index, #STEPS)
		-- Premio de este paso (lo justo para el siguiente)
		local prize = rewardText(step.Reward)
		ui.RewardTab.Visible = prize ~= "" and not collapsed
		ui.RewardLabel.Text = "🎁 Premio: " .. prize
		-- Omitir solo cuando ya hizo los primeros pasos (TutorialConfig.MinSkipStep)
		ui.Skip.Visible = index > (TutorialConfig.MinSkipStep or 0)
		ui.Skip.Text = if confirmSkip then "¿Seguro?" else "Omitir"
		applyGuide(step.Guide)
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
		if mode == "Next" then
			-- Ocultar el objetivo (vuelve al entrar otra vez o con el siguiente)
			local id = player:GetAttribute(Attributes.TutorialNext)
			if typeof(id) == "string" and id ~= "" then
				dismissed[id] = true
			end
			render()
			return
		end
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

	-- Premios de cada paso
	rewardRemote.OnClientEvent:Connect(function(given: any)
		local text = rewardText(given)
		if text ~= "" then
			Toasts.show("🎁 Premio del tutorial: " .. text, { Color = Color3.fromRGB(255, 214, 80), Key = "TutorialReward" })
		end
	end)

	for _, attribute in { Attributes.TutorialStatus, Attributes.TutorialStep, Attributes.TutorialNext, Attributes.Money, Attributes.CurrentZone } do
		player:GetAttributeChangedSignal(attribute):Connect(render)
	end
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 5)
		render()
	end)
	-- La distancia al destino cambia al moverse: se revisa cada medio segundo solo
	-- mientras hay un paso o un objetivo que enseñar (no hay ningún bucle si no lo hay).
	local watching = false
	local function watchDistance()
		if watching then
			return
		end
		watching = true
		task.spawn(function()
			while currentStep() ~= nil or currentNext() ~= nil do
				task.wait(0.5)
				render()
			end
			watching = false
		end)
	end
	player:GetAttributeChangedSignal(Attributes.TutorialStatus):Connect(watchDistance)
	player:GetAttributeChangedSignal(Attributes.TutorialNext):Connect(watchDistance)
	render()
	watchDistance()
end

return TutorialController
