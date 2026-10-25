-- Estilos de pelea en el cliente (StyleConfig; todo lo decide StyleService):
-- - Botón redondo de la habilidad del estilo (tecla Z, R1 del mando o tocarlo), junto a los
--   de las habilidades elementales, con su recarga. Su insignia ⇄ (o la tecla C) abre el
--   panel para elegir estilo: Armas, Puños o Magia, cada uno con su ataque, su pasiva y su
--   habilidad.
-- - Efectos de las habilidades ya resueltas (StyleEvent): Ráfaga (chispas doradas alrededor
--   mientras dura), Terremoto (onda naranja, polvo y sacudida) y Meteoros (aviso en el suelo,
--   caída y explosión). Los números de daño los dibuja CombatController.

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local StyleConfig = require(Shared.Config.StyleConfig)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local Toasts = require(script.Parent.Parent.UI.Toasts)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local CombatController = require(script.Parent.CombatController)
local WaveFx = require(script.Parent.WaveFx)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local INK = Color3.fromRGB(43, 29, 63)
local CREAM = Color3.fromRGB(255, 246, 224)
local PANEL_NAME = "Style"
local PANEL_SIZE = Vector2.new(740, 430)
local ABILITY_ACTION = "RebirthStyleAbility"
local PANEL_ACTION = "RebirthStylePanel"
-- Medidas de los botones de habilidad (AbilityController) para ponerse a su lado
local BUTTON_SIZE = 72
local ATTACK_BUTTON = 82
local GAP = 10
local EDGE = 20

local StyleController = {}

local player = Players.LocalPlayer
local fxFolder: Folder? = nil

local function styleId(): string
	local value = player:GetAttribute(Constants.Attributes.CombatStyle)
	return if typeof(value) == "string" and StyleConfig.Styles[value] then value else StyleConfig.Default
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function playSound(name: string, at: Vector3?)
	local spec = StyleConfig.Sounds[name]
	if not spec then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = spec.Id
	sound.Volume = spec.Volume or 0.5
	sound.PlaybackSpeed = spec.Pitch or 1
	if at and fxFolder then
		-- Las de otros jugadores suenan en su sitio (se apagan con la distancia)
		local holder = Instance.new("Part")
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.one * 0.2
		holder.CFrame = CFrame.new(at)
		holder.Parent = fxFolder
		sound.RollOffMaxDistance = 120
		sound.Parent = holder
		Debris:AddItem(holder, 6)
	else
		sound.Parent = SoundService
		Debris:AddItem(sound, 6)
	end
	sound:Play()
end

-- Panel para elegir estilo -------------------------------------------------------------

local function buildPanel()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("StylePanelHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "StylePanelHud",
		ResetOnSpawn = false,
		DisplayOrder = 5, -- como los demás paneles modales
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local panel, panelScale = UiKit.panel(screenGui, "StylePanel", PANEL_SIZE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.2))
	UiKit.text(panel, "Title", {
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -90, 0, 32),
		Font = FONTS.Display,
		TextSize = 28,
		Text = "⚔ Estilo de pelea",
	})
	UiKit.text(panel, "Subtitle", {
		Position = UDim2.fromOffset(22, 48),
		Size = UDim2.new(1, -90, 0, 20),
		Font = FONTS.Light,
		TextSize = 16,
		TextColor3 = THEME.Muted,
		Text = "Todos usan el poder de tu arma. Cámbialo cuando quieras (tecla C).",
	})
	local close = UiKit.button(panel, "Close", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = THEME.Inset,
		Text = "×",
	})
	local row = UiKit.create("Frame", {
		Name = "Cards",
		Position = UDim2.fromOffset(18, 82),
		Size = UDim2.new(1, -36, 1, -98),
		BackgroundTransparency = 1,
	}, panel)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)

	local cards = {}
	for order, id in StyleConfig.Order do
		local def = StyleConfig.Styles[id]
		local card = UiKit.create("Frame", {
			Name = id,
			Size = UDim2.fromOffset(222, 332),
			BackgroundColor3 = THEME.Inset,
			LayoutOrder = order,
		}, row)
		UiKit.corner(card, 14)
		local stroke = UiKit.stroke(card, def.Color, 3, 0)
		UiKit.text(card, "Icon", {
			Position = UDim2.fromOffset(0, 10),
			Size = UDim2.new(1, 0, 0, 46),
			Font = FONTS.Display,
			TextSize = 40,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = def.Icon,
		})
		local name = UiKit.text(card, "Name", {
			Position = UDim2.fromOffset(0, 58),
			Size = UDim2.new(1, 0, 0, 28),
			Font = FONTS.Display,
			TextSize = 24,
			TextColor3 = def.Color,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = def.DisplayName,
		})
		UiKit.outline(name, 2, INK)
		UiKit.text(card, "Attack", {
			Position = UDim2.fromOffset(12, 88),
			Size = UDim2.new(1, -24, 0, 50),
			Font = FONTS.Body,
			TextSize = 14,
			TextWrapped = true,
			TextColor3 = THEME.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = def.Attack,
		})
		local passive = def.Passive
		UiKit.text(card, "Passive", {
			Position = UDim2.fromOffset(12, 142),
			Size = UDim2.new(1, -24, 0, 62),
			Font = FONTS.Body,
			TextSize = 14,
			TextWrapped = true,
			RichText = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = ("<b>%s Pasiva · %s</b>\n%s"):format(passive.Icon, passive.Name, passive.Text),
		})
		local ability = def.Ability
		UiKit.text(card, "Ability", {
			Position = UDim2.fromOffset(12, 208),
			Size = UDim2.new(1, -24, 0, 70),
			Font = FONTS.Body,
			TextSize = 14,
			TextWrapped = true,
			RichText = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = ("<b>%s Habilidad (Z) · %s</b>\n%s <font color=\"#C4C4CE\">(%d s)</font>"):format(ability.Icon, ability.Name, ability.Text, ability.Cooldown),
		})
		local choose = UiKit.button(card, "Choose", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Size = UDim2.new(1, -28, 0, 38),
			BackgroundColor3 = def.Color,
			TextSize = 18,
			Text = "Elegir",
		})
		cards[id] = { Frame = card, Stroke = stroke, Button = choose }
	end

	screenGui.Parent = playerGui
	return { ScreenGui = screenGui, Panel = panel, PanelScale = panelScale, Close = close, Cards = cards }
end

-- Botón de la habilidad del estilo ---------------------------------------------------------

local function buildButton()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("StyleHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "StyleHud",
		ResetOnSpawn = false,
		DisplayOrder = 3,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local frame, scale = UiKit.panel(screenGui, "StyleAbilityButton", Vector2.new(BUTTON_SIZE, BUTTON_SIZE), Vector2.new(1, 1), UDim2.new(1, -300, 1, -34))
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 0
	local corner = frame:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0.5, 0)
	end
	local shine = frame:FindFirstChild("Shine")
	if shine then
		shine:Destroy()
	end
	local oldGrad = frame:FindFirstChildOfClass("UIGradient")
	if oldGrad then
		oldGrad:Destroy()
	end
	local gradient = UiKit.create("UIGradient", { Rotation = 90 }, frame)
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = INK
		stroke.Thickness = 4
		stroke.Transparency = 0
	end
	local cooldown = UiKit.create("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.35,
		ZIndex = 2,
	}, frame)
	UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, cooldown)
	local button = UiKit.create("TextButton", {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = FONTS.Display,
		TextSize = 34,
		TextColor3 = THEME.Text,
		Text = "",
		ZIndex = 3,
	}, frame)
	UiKit.addStates(button)
	local hover = button:FindFirstChild("Highlight")
	local hoverCorner = hover and hover:FindFirstChildOfClass("UICorner")
	if hoverCorner then
		hoverCorner.CornerRadius = UDim.new(0.5, 0)
	end
	local count = UiKit.text(frame, "Count", {
		Size = UDim2.fromScale(1, 1),
		Font = FONTS.Display,
		TextSize = 28,
		TextColor3 = THEME.Text,
		TextStrokeColor3 = THEME.Outline,
		TextStrokeTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 4,
	})
	local keyBadge = UiKit.create("Frame", {
		Name = "KeyBadge",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 2, 1, 2),
		Size = UDim2.fromOffset(25, 25),
		BackgroundColor3 = INK,
		ZIndex = 5,
	}, frame)
	UiKit.corner(keyBadge, 8)
	UiKit.text(keyBadge, "Hint", {
		Size = UDim2.fromScale(1, 1),
		Font = FONTS.Display,
		TextSize = 13,
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "Z",
		ZIndex = 6,
	})
	-- ⇄: abre el panel para cambiar de estilo
	local switch = UiKit.create("TextButton", {
		Name = "Switch",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(-6, -6),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = INK,
		Font = FONTS.Display,
		TextSize = 15,
		TextColor3 = CREAM,
		Text = "⇄",
		AutoButtonColor = true,
		ZIndex = 6,
	}, frame)
	UiKit.corner(switch, 14)
	UiKit.create("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5, Transparency = 0.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, switch)
	local label = UiKit.text(frame, "StyleName", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 5),
		Size = UDim2.fromOffset(96, 18),
		Font = FONTS.Display,
		TextSize = 13,
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 4,
	})
	UiKit.create("UIStroke", { Color = INK, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, label)

	screenGui.Parent = playerGui
	UiKit.bindScale(screenGui, { scale })
	return {
		ScreenGui = screenGui,
		Frame = frame,
		Gradient = gradient,
		Cooldown = cooldown,
		Button = button,
		Count = count,
		Switch = switch,
		Label = label,
	}
end

-- Efectos de las habilidades --------------------------------------------------------------

local function groundBelow(position: Vector3): Vector3
	local params = RaycastParams.new()
	local ignore = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	local enemies = Workspace:FindFirstChild("Enemies")
	if enemies then
		table.insert(ignore, enemies)
	end
	if fxFolder then
		table.insert(ignore, fxFolder)
	end
	params.FilterDescendantsInstances = ignore
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), params)
	return if hit then hit.Position else position - Vector3.new(0, 2.5, 0)
end

local function fxPart(size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	part.Parent = fxFolder
	return part
end

-- Ráfaga: chispas doradas alrededor del personaje mientras dura
local function burstFx(owner: Player, duration: number)
	local character = owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local color = StyleConfig.Styles.Weapons.Color
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "StyleBurst"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), color)
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.4, 0.7)
	emitter.Rate = 40
	emitter.Speed = NumberRange.new(4, 8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.35, 0)
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Parent = root
	Debris:AddItem(emitter, duration)
	WaveFx.ring(groundBelow(root.Position), color, 2, 14, 0.5, 0.15)
	playSound("Burst", if owner == player then nil else root.Position)
end

-- Terremoto: dos ondas naranjas, polvo y sacudida
local function quakeFx(owner: Player, position: Vector3, radius: number, hits: any)
	local color = StyleConfig.Styles.Fists.Color
	local ground = groundBelow(position)
	WaveFx.ring(ground, color, 2, radius * 2, 0.55, 0.1)
	task.delay(0.12, WaveFx.ring, ground, Color3.fromRGB(255, 230, 190), 1, radius * 1.5, 0.5, 0.35)
	WaveFx.sparkle(ground + Vector3.new(0, 1, 0), Color3.fromRGB(200, 160, 110), 24)
	CombatController.showHits(hits, color, owner == player, 1.2)
	if owner == player then
		WaveFx.shake(0.5)
		WaveFx.kick(4)
	end
	playSound("Quake", if owner == player then nil else position)
	playSound("QuakeRumble", if owner == player then nil else position)
end

-- Meteoros: un aviso en el suelo por punto y la bola cayendo justo al llegar su golpe
local function meteorFx(owner: Player, points: any, delay: number, interval: number, radius: number, startAt: number)
	if typeof(points) ~= "table" then
		return
	end
	local color = StyleConfig.Styles.Magic.Color
	local elapsed = math.max(0, serverNow() - startAt)
	for index, point in points do
		if typeof(point) ~= "Vector3" then
			continue
		end
		local impactIn = math.max(0.05, delay + (index - 1) * interval - elapsed)
		local ground = groundBelow(point)
		-- Aviso: disco morado que se hace visible hasta que cae
		local warning = fxPart(Vector3.new(0.1, radius * 2, radius * 2), CFrame.new(ground + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)), color)
		warning.Shape = Enum.PartType.Cylinder
		warning.Transparency = 0.9
		TweenService:Create(warning, TweenInfo.new(impactIn), { Transparency = 0.6 }):Play()
		Debris:AddItem(warning, impactIn + 0.1)
		-- Bola que cae en diagonal y llega al suelo en el momento del golpe
		local fall = math.min(0.55, impactIn)
		task.delay(impactIn - fall, function()
			local from = ground + Vector3.new(10, 46, -6)
			local meteor = fxPart(Vector3.one * 2.4, CFrame.new(from), color)
			meteor.Shape = Enum.PartType.Ball
			local tail = Instance.new("Attachment")
			tail.Position = Vector3.new(0, 0.9, 0)
			tail.Parent = meteor
			local head = Instance.new("Attachment")
			head.Position = Vector3.new(0, -0.9, 0)
			head.Parent = meteor
			local trail = Instance.new("Trail")
			trail.Attachment0 = tail
			trail.Attachment1 = head
			trail.Lifetime = 0.25
			trail.LightEmission = 1
			trail.FaceCamera = true
			trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
			trail.Transparency = NumberSequence.new(0, 1)
			trail.Parent = meteor
			local glow = Instance.new("PointLight")
			glow.Color = color
			glow.Range = 14
			glow.Brightness = 2
			glow.Parent = meteor
			TweenService:Create(meteor, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(ground + Vector3.new(0, 1, 0)) }):Play()
			Debris:AddItem(meteor, fall + 0.05)
			if index == 1 or index % 2 == 0 then
				playSound("MeteorFall", if owner == player then nil else ground)
			end
		end)
	end
end

local function meteorHitFx(owner: Player, position: Vector3, radius: number, hits: any)
	local color = StyleConfig.Styles.Magic.Color
	local ground = groundBelow(position)
	WaveFx.ring(ground, color, 2, radius * 2, 0.45, 0.1)
	CombatController.emitAt("Glint", ground + Vector3.new(0, 1.5, 0), color, 10)
	WaveFx.sparkle(ground + Vector3.new(0, 1, 0), color, 14)
	CombatController.showHits(hits, color, owner == player, 1)
	if owner == player then
		WaveFx.shake(0.18)
	end
	playSound("MeteorHit", if owner == player then nil else position)
end

-- Rebote del botón con su propia escala de pulsar (UiKit.addStates): no se apilan UIScale.
local function bounce(button: GuiObject, amount: number)
	local scale = button:FindFirstChild("PressScale")
	if scale and scale:IsA("UIScale") then
		scale.Scale = 1 + amount
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- Arranque ------------------------------------------------------------------------------

function StyleController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local actionRemote = remotes:WaitForChild(Constants.Remotes.StyleAction) :: RemoteEvent
	local eventRemote = remotes:WaitForChild(Constants.Remotes.StyleEvent) :: RemoteEvent

	local existingFx = Workspace:FindFirstChild("ClientStyleFX")
	if existingFx then
		existingFx:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientStyleFX"
	folder.Parent = Workspace
	fxFolder = folder

	local panelUi = buildPanel()
	local ui = buildButton()

	-- Panel
	PanelManager.register(PANEL_NAME, panelUi.Panel)
	UiKit.bindModalLayout(panelUi.ScreenGui, panelUi.PanelScale, PANEL_SIZE, function(position)
		PanelManager.setBasePosition(PANEL_NAME, position)
	end)
	panelUi.Close.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
	end)
	local function refreshCards()
		local current = styleId()
		for id, card in panelUi.Cards do
			local chosen = id == current
			card.Button.Text = if chosen then "✓ En uso" else "Elegir"
			card.Button.BackgroundColor3 = if chosen then THEME.Inset else StyleConfig.Styles[id].Color
			card.Stroke.Thickness = if chosen then 5 else 3
			card.Stroke.Transparency = if chosen then 0 else 0.4
		end
	end
	for id, card in panelUi.Cards do
		card.Button.Activated:Connect(function()
			if id ~= styleId() then
				actionRemote:FireServer("Set", id)
			end
		end)
	end
	ui.Switch.Activated:Connect(function()
		PanelManager.toggle(PANEL_NAME)
	end)

	-- Botón: icono, colores y nombre del estilo actual
	local function refreshButton()
		local def = StyleConfig.Styles[styleId()]
		ui.Button.Text = def.Ability.Icon
		ui.Label.Text = def.Ability.Name
		local c = def.Color
		ui.Gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, c:Lerp(Color3.new(1, 1, 1), 0.55)),
			ColorSequenceKeypoint.new(0.55, c),
			ColorSequenceKeypoint.new(1, c:Lerp(Color3.new(0, 0, 0), 0.35)),
		})
		refreshCards()
	end
	local lastStyle = styleId()
	player:GetAttributeChangedSignal(Constants.Attributes.CombatStyle):Connect(function()
		refreshButton()
		local now = styleId()
		if now ~= lastStyle then
			lastStyle = now
			local def = StyleConfig.Styles[now]
			Toasts.show(("%s Estilo: %s"):format(def.Icon, def.DisplayName), { Color = def.Color, Key = "StyleSwitch" })
			bounce(ui.Button, 0.15)
			playSound("Switch")
		end
	end)
	refreshButton()

	-- Usar la habilidad
	local function useAbility()
		actionRemote:FireServer("Ability")
	end
	ui.Button.Activated:Connect(useAbility)
	ContextActionService:BindAction(ABILITY_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			useAbility()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Z, Enum.KeyCode.ButtonR1)
	ContextActionService:BindAction(PANEL_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			PanelManager.toggle(PANEL_NAME)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.C)

	-- Al lado de las habilidades elementales (Q, y R si se ve), o encima en táctil
	local abilityHud = player:WaitForChild("PlayerGui"):WaitForChild("AbilityHud", 15)
	local secondary = abilityHud and abilityHud:FindFirstChild("SecondaryButton") :: GuiObject?
	local function place()
		local uiScale = UiKit.computeScale(ui.ScreenGui.AbsoluteSize)
		local slots = if secondary and secondary.Visible then 2 else 1
		local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		if touchOnly then
			ui.Frame.Position = UDim2.new(1, -EDGE, 0.5, -(76 + slots * (BUTTON_SIZE + 26)) * uiScale)
		else
			ui.Frame.Position = UDim2.new(1, -(EDGE + (ATTACK_BUTTON + GAP + slots * (BUTTON_SIZE + GAP)) * uiScale), 1, -34)
		end
	end
	ui.ScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	UserInputService.LastInputTypeChanged:Connect(place)
	if secondary then
		secondary:GetPropertyChangedSignal("Visible"):Connect(place)
	end
	place()

	-- Recarga (hora del servidor en que vuelve a estar lista)
	local wasCooling = false
	RunService.Heartbeat:Connect(function()
		local readyAt = player:GetAttribute(Constants.Attributes.StyleReadyAt)
		local def = StyleConfig.Styles[styleId()]
		local left = if typeof(readyAt) == "number" then readyAt - serverNow() else 0
		if left > 0 then
			wasCooling = true
			ui.Cooldown.Size = UDim2.fromScale(1, math.clamp(left / def.Ability.Cooldown, 0, 1))
			ui.Count.Visible = true
			ui.Count.Text = tostring(math.ceil(left))
			ui.Button.TextTransparency = 0.5
		else
			ui.Cooldown.Size = UDim2.fromScale(1, 0)
			ui.Count.Visible = false
			ui.Button.TextTransparency = 0
			if wasCooling then
				wasCooling = false
				bounce(ui.Button, 0.12)
				playSound("Ready")
			end
		end
	end)

	-- Efectos y resultados
	eventRemote.OnClientEvent:Connect(function(event: any)
		if typeof(event) ~= "table" or typeof(event.Owner) ~= "Instance" then
			return
		end
		local owner = event.Owner :: Player
		if event.Kind == "Result" then
			if owner ~= player then
				return
			end
			if event.Success == false then
				if event.Code == "NoTarget" then
					Toasts.show("☄️ No hay enemigos cerca", { Color = THEME.Error, Key = "StyleNotice" })
				elseif event.Code == "NotReady" then
					bounce(ui.Button, -0.08)
				end
			elseif event.Action ~= "Set" then
				bounce(ui.Button, 0.18)
			end
		elseif event.Kind == "Burst" then
			burstFx(owner, tonumber(event.Duration) or 4)
		elseif event.Kind == "Quake" and typeof(event.Position) == "Vector3" then
			quakeFx(owner, event.Position, tonumber(event.Radius) or 14, event.Hits)
		elseif event.Kind == "Meteor" then
			meteorFx(owner, event.Points, tonumber(event.Delay) or 0.6, tonumber(event.Interval) or 0.2, tonumber(event.Radius) or 7, tonumber(event.StartAt) or serverNow())
		elseif event.Kind == "MeteorHit" and typeof(event.Position) == "Vector3" then
			meteorHitFx(owner, event.Position, tonumber(event.Radius) or 7, event.Hits)
		end
	end)
end

return StyleController
