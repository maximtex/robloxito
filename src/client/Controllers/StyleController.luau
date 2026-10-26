-- Estilos de pelea en el cliente (StyleConfig; todo lo decide StyleService):
-- - Dos botones redondos con las habilidades puestas del estilo (atributo SkillSlots,
--   SkillLogic): la de la Z (R1 del mando o tocarlo) y la de la X (L1), junto a los de las
--   habilidades elementales, cada uno con su recarga (más corta con su nivel). La insignia ⇄
--   del primero (o la tecla C) abre el panel para elegir estilo: Armas, Guerrero, Puños o
--   Magia, cada uno con su ataque, su ventaja y su desventaja, su pasiva y sus cuatro
--   habilidades. La insignia ⚡ del segundo (o la tecla B) abre las ⚡ Mejoras
--   (SkillsController).
-- - Puños: dash con Shift (o el botón 💨 en pantallas táctiles), con su recarga. Magia: el
--   teletransporte con Shift (o el botón ✨; también el clic derecho corto, CombatController).
-- - Guerrero: Salto aplastante (tu cliente hace el salto: leapMove) y la onda cortante.
-- - Combos (StyleEvent "Combo"): el nombre grande sobre el enemigo y un aviso.
-- - Efectos de las habilidades ya resueltas (StyleEvent), con el movimiento del personaje
--   (CharacterPose): Ráfaga (apunta y chispas doradas mientras dura), Granada (la lanza por
--   encima del hombro, vuela en arco y explota), Terremoto (brazos arriba y golpe al suelo:
--   onda naranja, polvo y sacudida), Embestida (puños por delante, estela y huellas de
--   viento), Meteoros (lanza el hechizo; aviso en el suelo, caída y explosión) y Nova de
--   hielo (brazos abiertos: anillo helado, carámbanos y los enemigos congelados un momento
--   dentro de un bloque de hielo). Los números de daño los dibuja CombatController.

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
local SkillLogic = require(Shared.SkillLogic)
local ClassLogic = require(Shared.ClassLogic)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local Toasts = require(script.Parent.Parent.UI.Toasts)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local CombatController = require(script.Parent.CombatController)
local CharacterPose = require(script.Parent.CharacterPose)
local StyleAnimations = require(script.Parent.StyleAnimations)
local AimPoint = require(script.Parent.AimPoint)
local WaveFx = require(script.Parent.WaveFx)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local INK = Color3.fromRGB(43, 29, 63)
local CREAM = Color3.fromRGB(255, 246, 224)
local PANEL_NAME = "Style"
local PANEL_SIZE = Vector2.new(1030, 566) -- cuatro tarjetas de estilo
local ABILITY_ACTIONS = { "RebirthStyleAbility", "RebirthStyleAbility2" }
local ABILITY_KEYS = { { Enum.KeyCode.Z, Enum.KeyCode.ButtonR1 }, { Enum.KeyCode.X, Enum.KeyCode.ButtonL1 } }
local ABILITY_FACING = 22 -- sin ratón, las habilidades apuntan a esta distancia delante de ti
local KEY_LABELS = { "Z", "X" }
local PANEL_ACTION = "RebirthStylePanel"
local SKILLS_ACTION = "RebirthSkillsPanel"
local DASH_ACTION = "RebirthStyleDash"
local ICE = Color3.fromRGB(150, 230, 255)
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

-- Habilidad puesta en el hueco `slot` (1 = Z, 2 = X) del estilo y su nivel
local function equippedSkill(style: string, slot: number): (string, { [string]: any }, number)
	local slots = SkillLogic.parseSlots(player:GetAttribute(Constants.Attributes.SkillSlots))
	local mine = slots[style]
	local skillId = mine and mine[slot]
	local def = StyleConfig.Styles[style]
	if not (skillId and def.Skills[skillId]) then
		skillId = def.StartSkills[slot]
	end
	local owned = SkillLogic.parseOwned(player:GetAttribute(Constants.Attributes.Skills))
	return skillId, def.Skills[skillId], owned[skillId] or 1
end

-- Pasivas de la clase activa del estilo (para las recargas que se dibujan); se recalculan
-- solo si cambian los atributos.
local classCache: { Key: string, Mods: ClassLogic.Mods }? = nil
local function classMods(style: string): ClassLogic.Mods
	local owned = player:GetAttribute(Constants.Attributes.Classes)
	local active = player:GetAttribute(Constants.Attributes.ClassActive)
	local key = ("%s|%s|%s"):format(tostring(owned), tostring(active), style)
	if not (classCache and classCache.Key == key) then
		classCache = { Key = key, Mods = ClassLogic.mods(ClassLogic.parse(owned, active), style) }
	end
	return (classCache :: any).Mods
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
		Text = "Cada uno con su tienda, sus habilidades y su progreso. Cámbialo cuando quieras (C).",
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
	local function line(card: Instance, name: string, y: number, height: number, text: string, color: Color3?)
		UiKit.text(card, name, {
			Position = UDim2.fromOffset(12, y),
			Size = UDim2.new(1, -24, 0, height),
			Font = FONTS.Body,
			TextSize = 13,
			TextWrapped = true,
			RichText = true,
			TextColor3 = color or THEME.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = text,
		})
	end
	for order, id in StyleConfig.Order do
		local def = StyleConfig.Styles[id]
		local card = UiKit.create("Frame", {
			Name = id,
			Size = UDim2.fromOffset(236, 462),
			BackgroundColor3 = THEME.Inset,
			LayoutOrder = order,
		}, row)
		UiKit.corner(card, 14)
		local stroke = UiKit.stroke(card, def.Color, 3, 0)
		UiKit.text(card, "Icon", {
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 40),
			Font = FONTS.Display,
			TextSize = 36,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = def.Icon,
		})
		local name = UiKit.text(card, "Name", {
			Position = UDim2.fromOffset(0, 48),
			Size = UDim2.new(1, 0, 0, 28),
			Font = FONTS.Display,
			TextSize = 24,
			TextColor3 = def.Color,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = def.DisplayName,
		})
		UiKit.outline(name, 2, INK)
		UiKit.text(card, "Attack", {
			Position = UDim2.fromOffset(12, 78),
			Size = UDim2.new(1, -24, 0, 80),
			Font = FONTS.Body,
			TextSize = 13,
			TextWrapped = true,
			TextColor3 = THEME.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = def.Attack,
		})
		line(card, "Pros", 162, 34, "✅ " .. def.Pros, Color3.fromRGB(150, 240, 150))
		line(card, "Cons", 198, 34, "❌ " .. def.Cons, Color3.fromRGB(255, 150, 140))
		local passive = def.Passive
		line(card, "Passive", 236, 56, ("<b>%s Pasiva · %s</b>\n%s"):format(passive.Icon, passive.Name, passive.Text))
		-- Sus cuatro habilidades del Mundo 1 (las dos iniciales y las dos que se compran con 💎;
		-- las del Mundo 2 se ven en su puesto ⚡ Mejoras)
		local names = {}
		for _, skillId in SkillLogic.ordered(id, 1) do
			local skill = def.Skills[skillId]
			local price = if (skill.Price or 0) > 0 then (" <font color=\"#9AD8FF\">💎%d</font>"):format(skill.Price) else ""
			table.insert(names, ("%s %s%s"):format(skill.Icon, skill.Name, price))
		end
		line(card, "Skills", 296, 110, "<b>Habilidades</b>\n" .. table.concat(names, "\n") .. "\n<font color=\"#C4C4CE\">⚡ Mejoras (B): compra, sube y elige 2</font>")
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

local function makeButton(screenGui: ScreenGui, slot: number)
	local size = BUTTON_SIZE
	local frame, scale = UiKit.panel(screenGui, if slot == 1 then "StyleAbilityButton" else "StyleAbility2Button", Vector2.new(size, size), Vector2.new(1, 1), UDim2.new(1, -300, 1, -34))
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
		Text = KEY_LABELS[slot],
		ZIndex = 6,
	})
	-- ⇄ (solo en el primero): abre el panel para cambiar de estilo; ⚡ (en el segundo): Mejoras
	local switch = nil
	if slot == 2 then
		switch = UiKit.create("TextButton", {
			Name = "Skills",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 6, 0, -6),
			Size = UDim2.fromOffset(28, 28),
			BackgroundColor3 = Color3.fromRGB(168, 48, 232),
			Font = FONTS.Display,
			TextSize = 15,
			TextColor3 = CREAM,
			Text = "⚡",
			AutoButtonColor = true,
			ZIndex = 6,
		}, frame)
		UiKit.corner(switch, 14)
		UiKit.create("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5, Transparency = 0.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, switch)
	end
	if slot == 1 then
		switch = UiKit.create("TextButton", {
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
	end
	local label = UiKit.text(frame, "StyleName", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 5),
		Size = UDim2.fromOffset(BUTTON_SIZE + GAP - 4, 18), -- sin pisar el nombre de al lado
		Font = FONTS.Display,
		TextSize = 13,
		TextScaled = true, -- los nombres largos («Salto aplastante») se achican
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	})
	UiKit.create("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 8 }, label)
	UiKit.create("UIStroke", { Color = INK, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, label)
	return {
		Slot = slot,
		Frame = frame,
		Scale = scale,
		Gradient = gradient,
		Cooldown = cooldown,
		Button = button,
		Count = count,
		Switch = switch,
		Label = label,
		WasCooling = false,
	}
end

local function buildButtons()
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
	local buttons = { makeButton(screenGui, 1), makeButton(screenGui, 2) }
	-- 💨 Dash de Puños en pantallas táctiles (con teclado es Shift)
	local dashFrame, dashScale = UiKit.panel(screenGui, "StyleDashButton", Vector2.new(58, 58), Vector2.new(1, 1), UDim2.new(1, -300, 1, -34))
	dashFrame.BackgroundColor3 = StyleConfig.Styles.Fists.Color
	dashFrame.BackgroundTransparency = 0
	local dashCorner = dashFrame:FindFirstChildOfClass("UICorner")
	if dashCorner then
		dashCorner.CornerRadius = UDim.new(0.5, 0)
	end
	local dashCooldown = UiKit.create("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.35,
		ZIndex = 2,
	}, dashFrame)
	UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dashCooldown)
	local dashButton = UiKit.create("TextButton", {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = FONTS.Display,
		TextSize = 28,
		TextColor3 = THEME.Text,
		Text = "💨",
		ZIndex = 3,
	}, dashFrame)
	dashFrame.Visible = false
	screenGui.Parent = playerGui
	UiKit.bindScale(screenGui, { buttons[1].Scale, buttons[2].Scale, dashScale })
	return screenGui, buttons, { Frame = dashFrame, Button = dashButton, Cooldown = dashCooldown }
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

-- Color propio de la habilidad que se está dibujando (las del Mundo 2 traen el suyo: el
-- servidor lo manda en el aviso, Color); nil = el de siempre de su estilo
local tint: Color3? = nil

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
	local color = tint or StyleConfig.Styles.Weapons.Color
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
	CharacterPose.aim(character)
	WaveFx.ring(groundBelow(root.Position), color, 2, 14, 0.5, 0.15)
	playSound("Burst", if owner == player then nil else root.Position)
end

-- Terremoto: dos ondas naranjas, polvo y sacudida
local function quakeFx(owner: Player, position: Vector3, radius: number, hits: any)
	local ownerStyle = owner:GetAttribute(Constants.Attributes.CombatStyle)
	local color = tint or (if ownerStyle == "Warrior" then StyleConfig.Styles.Warrior.Color else StyleConfig.Styles.Fists.Color)
	local ground = groundBelow(position)
	CharacterPose.slam(owner.Character)
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
	local color = tint or StyleConfig.Styles.Magic.Color
	local elapsed = math.max(0, serverNow() - startAt)
	CharacterPose.cast(owner.Character, 0.3)
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
	local color = tint or StyleConfig.Styles.Magic.Color
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

-- Granada: el personaje la lanza por encima del hombro y vuela en arco hasta el objetivo
local function grenadeFx(owner: Player, from: Vector3, to: Vector3, delay: number, radius: number)
	CharacterPose.throw(owner.Character)
	playSound("Throw", if owner == player then nil else from)
	local ground = groundBelow(to)
	-- Aviso: círculo en el suelo hasta que explota
	local warning = fxPart(Vector3.new(0.1, radius * 2, radius * 2), CFrame.new(ground + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 120, 60))
	warning.Shape = Enum.PartType.Cylinder
	warning.Transparency = 0.85
	TweenService:Create(warning, TweenInfo.new(delay), { Transparency = 0.55 }):Play()
	Debris:AddItem(warning, delay + 0.05)
	local start = CharacterPose.handPosition(owner.Character) or from
	local bomb = fxPart(Vector3.one * 1.1, CFrame.new(start), Color3.fromRGB(46, 52, 60))
	bomb.Shape = Enum.PartType.Ball
	bomb.Material = Enum.Material.Metal
	local fuse = fxPart(Vector3.one * 0.4, CFrame.new(start), Color3.fromRGB(255, 200, 80))
	fuse.Shape = Enum.PartType.Ball
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 120, 40))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.25, 0)
	sparks.Lifetime = NumberRange.new(0.15, 0.3)
	sparks.Speed = NumberRange.new(2, 5)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 60
	sparks.Parent = fuse
	local began = os.clock()
	local height = math.clamp((to - start).Magnitude * 0.35, 4, 14)
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - began) / delay, 0, 1)
		local position = start:Lerp(ground + Vector3.new(0, 0.6, 0), t) + Vector3.new(0, math.sin(t * math.pi) * height, 0)
		bomb.CFrame = CFrame.new(position) * CFrame.Angles(t * 12, t * 7, 0)
		fuse.CFrame = bomb.CFrame * CFrame.new(0, 0.6, 0)
		if t >= 1 then
			connection:Disconnect()
			bomb:Destroy()
			fuse:Destroy()
		end
	end)
	Debris:AddItem(bomb, delay + 0.5)
	Debris:AddItem(fuse, delay + 0.5)
end

local function grenadeHitFx(owner: Player, position: Vector3, radius: number, hits: any)
	local ground = groundBelow(position)
	local fire = tint or Color3.fromRGB(255, 150, 60)
	-- Bola de fuego que crece y se apaga, onda en el suelo y humo
	local ball = fxPart(Vector3.one * 2, CFrame.new(ground + Vector3.new(0, 1.5, 0)), fire)
	ball.Shape = Enum.PartType.Ball
	ball.Transparency = 0.1
	TweenService:Create(ball, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * radius * 1.6, Transparency = 1, Color = Color3.fromRGB(255, 230, 150) }):Play()
	Debris:AddItem(ball, 0.4)
	WaveFx.ring(ground, fire, 2, radius * 2, 0.45, 0.1)
	WaveFx.sparkle(ground + Vector3.new(0, 1, 0), Color3.fromRGB(120, 110, 100), 20)
	CombatController.emitAt("Spark", ground + Vector3.new(0, 1, 0), fire, 18)
	CombatController.showHits(hits, StyleConfig.Styles.Weapons.Color, owner == player, 1.1)
	if owner == player then
		WaveFx.shake(0.35)
	end
	playSound("Grenade", if owner == player then nil else position)
end

-- Embestida: puños por delante, estela del recorrido e imágenes que se desvanecen
local function dashFx(owner: Player, from: Vector3, to: Vector3, hits: any)
	local color = tint or StyleConfig.Styles.Fists.Color
	CharacterPose.charge(owner.Character)
	local offset = to - from
	local distance = offset.Magnitude
	if distance > 0.5 then
		local trail = fxPart(Vector3.new(4.5, 0.2, distance), CFrame.lookAt(from:Lerp(to, 0.5), to) * CFrame.new(0, -1.5, 0), color)
		trail.Transparency = 0.4
		TweenService:Create(trail, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1, Size = Vector3.new(0.4, 0.1, distance) }):Play()
		Debris:AddItem(trail, 0.45)
		-- Huellas de viento: siluetas que se apagan a lo largo del camino
		local steps = math.clamp(math.floor(distance / 5), 1, 6)
		for index = 1, steps do
			local point = from:Lerp(to, index / (steps + 1))
			local ghost = fxPart(Vector3.new(2.2, 4.5, 1), CFrame.lookAt(point, point + offset.Unit), color)
			ghost.Transparency = 0.55 + index * 0.05
			TweenService:Create(ghost, TweenInfo.new(0.35 + index * 0.03), { Transparency = 1, Size = Vector3.new(0.4, 4, 0.4) }):Play()
			Debris:AddItem(ghost, 0.5)
		end
	end
	WaveFx.ring(groundBelow(to), color, 2, 10, 0.35, 0.2)
	CombatController.showHits(hits, color, owner == player, 1.1)
	if owner == player then
		WaveFx.kick(3)
		if typeof(hits) == "table" and #hits > 0 then
			WaveFx.shake(0.25)
		end
	end
	playSound("Dash", if owner == player then nil else from)
	if typeof(hits) == "table" and #hits > 0 then
		playSound("DashHit", if owner == player then nil else to)
	end
end

-- Nova de hielo: brazos abiertos, anillo helado, carámbanos y los congelados en hielo
local function novaFx(owner: Player, position: Vector3, radius: number, hits: any, frozen: any)
	local ice = tint or ICE
	local ground = groundBelow(position)
	CharacterPose.spread(owner.Character)
	WaveFx.ring(ground, ice, 2, radius * 2, 0.5, 0.05)
	task.delay(0.1, WaveFx.ring, ground, Color3.new(1, 1, 1), 2, radius * 1.6, 0.45, 0.4)
	-- Carámbanos que salen del suelo en círculo y se derriten
	for index = 1, 12 do
		local angle = index / 12 * math.pi * 2
		local distance = radius * (0.45 + (index % 3) * 0.18)
		local base = ground + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local spike = fxPart(Vector3.new(1, 0.2, 1), CFrame.new(base) * CFrame.Angles(math.rad((index % 2) * 12), angle, 0), ice)
		spike.Material = Enum.Material.Glass
		spike.Transparency = 0.2
		local tall = 2.5 + (index % 4)
		TweenService:Create(spike, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(1, tall, 1), CFrame = CFrame.new(base + Vector3.new(0, tall / 2, 0)) * CFrame.Angles(math.rad((index % 2) * 12), angle, 0) }):Play()
		task.delay(0.8, function()
			if spike.Parent then
				TweenService:Create(spike, TweenInfo.new(0.5), { Transparency = 1, Size = Vector3.new(0.3, 0.3, 0.3) }):Play()
			end
		end)
		Debris:AddItem(spike, 1.4)
	end
	-- Los congelados: un bloque de hielo alrededor mientras dura
	if typeof(frozen) == "table" then
		for _, entry in frozen do
			local model = typeof(entry) == "table" and entry.Model
			local seconds = typeof(entry) == "table" and tonumber(entry.Seconds) or 0
			if typeof(model) == "Instance" and model:IsA("Model") and seconds > 0 then
				local ok, cframe, size = pcall(function()
					return model:GetBoundingBox()
				end)
				if ok then
					local block = fxPart(size + Vector3.new(0.6, 0.6, 0.6), cframe, ice)
					block.Material = Enum.Material.Glass
					block.Transparency = 0.45
					TweenService:Create(block, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, math.max(0, seconds - 0.5)), { Transparency = 1 }):Play()
					Debris:AddItem(block, seconds + 0.1)
				end
			end
		end
	end
	WaveFx.sparkle(ground + Vector3.new(0, 1.5, 0), ice, 22)
	CombatController.showHits(hits, ice, owner == player, 1.1)
	if owner == player then
		WaveFx.flash(ice, 0.25)
	end
	playSound("Nova", if owner == player then nil else position)
	playSound("NovaBlast", if owner == player then nil else position)
end

-- Rayo perforante: un rayo grueso y recto con su núcleo blanco
local function pierceFx(owner: Player, from: Vector3, to: Vector3, width: number, hits: any)
	local color = tint or StyleConfig.Styles.Weapons.Color
	CharacterPose.aim(owner.Character)
	local distance = (to - from).Magnitude
	if distance > 0.5 then
		local center = CFrame.lookAt(from:Lerp(to, 0.5), to) * CFrame.Angles(0, math.rad(90), 0)
		local beam = fxPart(Vector3.new(distance, width * 0.5, width * 0.5), center, color)
		beam.Shape = Enum.PartType.Cylinder
		beam.Transparency = 0.25
		local core = fxPart(Vector3.new(distance, width * 0.18, width * 0.18), center, Color3.new(1, 1, 1))
		core.Shape = Enum.PartType.Cylinder
		for _, part in { beam, core } do
			TweenService:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1, Size = Vector3.new(distance, 0.1, 0.1) }):Play()
			Debris:AddItem(part, 0.4)
		end
	end
	CombatController.showHits(hits, color, owner == player, 1.1)
	if owner == player then
		WaveFx.kick(3)
	end
	playSound("Pierce", if owner == player then nil else from)
end

-- Torreta: base de metal, poste y cabeza que gira hacia cada objetivo
local turrets: { [Player]: { Model: Model, Head: BasePart, Gun: Vector3 } } = {}
local function removeTurret(owner: Player)
	local turret = turrets[owner]
	turrets[owner] = nil
	if turret and turret.Model.Parent then
		for _, part in turret.Model:GetChildren() do
			if part:IsA("BasePart") then
				TweenService:Create(part, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			end
		end
		Debris:AddItem(turret.Model, 0.35)
	end
end
local function turretFx(owner: Player, position: Vector3, duration: number)
	removeTurret(owner)
	local color = tint or StyleConfig.Styles.Weapons.Color
	local model = Instance.new("Model")
	model.Name = "StyleTurret"
	model.Parent = fxFolder
	local function piece(size: Vector3, cframe: CFrame, tone: Color3, material: Enum.Material): Part
		local part = fxPart(size, cframe, tone)
		part.Material = material
		part.Parent = model
		return part
	end
	local base = piece(Vector3.new(0.6, 2.6, 2.6), CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 78, 92), Enum.Material.Metal)
	base.Shape = Enum.PartType.Cylinder
	piece(Vector3.new(0.6, 1.8, 0.6), CFrame.new(position + Vector3.new(0, 1.4, 0)), Color3.fromRGB(110, 118, 130), Enum.Material.Metal)
	local head = piece(Vector3.new(1.4, 0.9, 1.8), CFrame.new(position + Vector3.new(0, 2.6, 0)), color, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = head
	turrets[owner] = { Model = model, Head = head, Gun = position + Vector3.new(0, 2.6, 0) }
	WaveFx.ring(position, color, 1, 8, 0.4, 0.2)
	playSound("Turret", if owner == player then nil else position)
	task.delay(duration + 0.6, function()
		if turrets[owner] and turrets[owner].Model == model then
			removeTurret(owner)
		end
	end)
end
local function turretShotFx(owner: Player, from: Vector3, to: Vector3, hits: any)
	local color = tint or StyleConfig.Styles.Weapons.Color
	local turret = turrets[owner]
	if turret and turret.Head.Parent then
		turret.Head.CFrame = CFrame.lookAt(turret.Gun, Vector3.new(to.X, turret.Gun.Y, to.Z))
	end
	CombatController.beam(from, to, color, 0.3)
	CombatController.emitAt("Glint", to, color, 4)
	CombatController.showHits(hits, color, owner == player, 0.7)
	if owner == player then
		playSound("TurretShot")
	end
end

-- Furia: aura roja alrededor del personaje mientras dura
local function rageFx(owner: Player, duration: number)
	local character = owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local color = tint or Color3.fromRGB(255, 70, 50)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "StyleRage"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 200, 120), color)
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Rate = 55
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.6, 0)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Parent = root
	Debris:AddItem(emitter, duration)
	local glow = Instance.new("PointLight")
	glow.Name = "StyleRageLight"
	glow.Color = color
	glow.Range = 12
	glow.Brightness = 2
	glow.Parent = root
	Debris:AddItem(glow, duration)
	CharacterPose.charge(character)
	WaveFx.ring(groundBelow(root.Position), color, 2, 16, 0.5, 0.1)
	if owner == player then
		WaveFx.flash(color, 0.2)
	end
	playSound("Rage", if owner == player then nil else root.Position)
end

-- Torbellino: el personaje gira con un anillo de viento a su alrededor
local function whirlFx(owner: Player, radius: number, pulses: number, interval: number)
	local character = owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local color = tint or StyleConfig.Styles.Fists.Color
	local blades = {}
	for index = 1, 6 do
		local blade = fxPart(Vector3.new(0.4, 3.2, radius * 0.45), root.CFrame, color)
		blade.Transparency = 0.45
		blades[index] = blade
	end
	local total = math.max(0.3, pulses * interval)
	local began = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - began
		if t >= total or not root.Parent then
			connection:Disconnect()
			for _, blade in blades do
				blade:Destroy()
			end
			return
		end
		for index, blade in blades do
			local angle = t * 14 + index / #blades * math.pi * 2
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * 0.6
			blade.CFrame = CFrame.lookAt(root.Position + offset, root.Position + offset + Vector3.new(-math.sin(angle), 0, math.cos(angle)))
		end
	end)
	for pulse = 0, pulses - 1 do
		task.delay(pulse * interval, CharacterPose.punch, character)
	end
	playSound("Whirl", if owner == player then nil else root.Position)
end
local function whirlHitFx(owner: Player, position: Vector3, radius: number, hits: any)
	local color = tint or StyleConfig.Styles.Fists.Color
	WaveFx.ring(groundBelow(position), color, 2, radius * 2, 0.3, 0.3)
	CombatController.showHits(hits, color, owner == player, 0.9)
	if owner == player and typeof(hits) == "table" and #hits > 0 then
		WaveFx.shake(0.12)
	end
end

-- Cadena de rayos: zigzag de un enemigo a otro
local LIGHTNING = Color3.fromRGB(255, 235, 120)
local function zigzag(from: Vector3, to: Vector3, color: Color3)
	local points = { from }
	local segments = math.clamp(math.floor((to - from).Magnitude / 4), 2, 7)
	for index = 1, segments - 1 do
		local base = from:Lerp(to, index / segments)
		table.insert(points, base + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2.2)
	end
	table.insert(points, to)
	for index = 1, #points - 1 do
		CombatController.beam(points[index], points[index + 1], color, 0.35)
	end
end
local function lightningFx(owner: Player, points: any, hits: any)
	if typeof(points) ~= "table" then
		return
	end
	local purple = StyleConfig.Styles.Magic.Color
	local bolt = tint or LIGHTNING
	CharacterPose.cast(owner.Character, 0.2)
	local start = CharacterPose.handPosition(owner.Character)
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			if index == 1 and start then
				a = start
			end
			task.delay((index - 1) * 0.05, function()
				zigzag(a, b, bolt)
				zigzag(a, b, purple)
				CombatController.emitAt("Spark", b, bolt, 8)
			end)
		end
	end
	CombatController.showHits(hits, bolt, owner == player, 1.05)
	if owner == player then
		WaveFx.flash(bolt, 0.12)
	end
	playSound("Lightning", if owner == player then nil else (if typeof(points[1]) == "Vector3" then points[1] else nil))
end

-- Agujero negro: esfera oscura que crece, anillo morado girando y, al final, la explosión
local function blackHoleFx(owner: Player, position: Vector3, radius: number, duration: number)
	local purple = tint or StyleConfig.Styles.Magic.Color
	local ground = groundBelow(position)
	local center = ground + Vector3.new(0, 2.5, 0)
	local core = fxPart(Vector3.one * 0.5, CFrame.new(center), Color3.fromRGB(12, 6, 24))
	core.Shape = Enum.PartType.Ball
	core.Material = Enum.Material.SmoothPlastic
	TweenService:Create(core, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.one * 4 }):Play()
	local halo = fxPart(Vector3.one * 5, CFrame.new(center), purple)
	halo.Shape = Enum.PartType.Ball
	halo.Transparency = 0.7
	local ring = fxPart(Vector3.new(0.2, radius * 1.6, radius * 1.6), CFrame.new(ground + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), purple)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.75
	local swirl = Instance.new("ParticleEmitter")
	swirl.Color = ColorSequence.new(purple, Color3.fromRGB(40, 10, 70))
	swirl.LightEmission = 0.6
	swirl.Lifetime = NumberRange.new(0.5, 0.8)
	swirl.Rate = 70
	swirl.Speed = NumberRange.new(-14, -10) -- hacia dentro
	swirl.SpreadAngle = Vector2.new(180, 180)
	swirl.Size = NumberSequence.new(0.5, 0.1)
	swirl.Parent = halo
	local light = Instance.new("PointLight")
	light.Color = purple
	light.Range = 16
	light.Brightness = 2
	light.Parent = halo
	local began = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - began
		if t >= duration or not ring.Parent then
			connection:Disconnect()
			return
		end
		ring.CFrame = CFrame.new(ground + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, t * 4, math.rad(90))
		halo.Size = Vector3.one * (5 + math.sin(t * 9) * 0.6)
	end)
	for _, part in { core, halo, ring } do
		Debris:AddItem(part, duration + 0.1)
	end
	playSound("BlackHole", if owner == player then nil else position)
end
local function blackHoleBlastFx(owner: Player, position: Vector3, radius: number, hits: any)
	local purple = tint or StyleConfig.Styles.Magic.Color
	local ground = groundBelow(position)
	local ball = fxPart(Vector3.one * 3, CFrame.new(ground + Vector3.new(0, 2.5, 0)), purple)
	ball.Shape = Enum.PartType.Ball
	ball.Transparency = 0.1
	TweenService:Create(ball, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * radius * 1.8, Transparency = 1, Color = Color3.new(1, 1, 1) }):Play()
	Debris:AddItem(ball, 0.45)
	WaveFx.ring(ground, purple, 2, radius * 2.2, 0.5, 0.05)
	WaveFx.sparkle(ground + Vector3.new(0, 1.5, 0), purple, 26)
	CombatController.showHits(hits, purple, owner == player, 1.25)
	if owner == player then
		WaveFx.shake(0.4)
		WaveFx.flash(purple, 0.2)
	end
	playSound("NovaBlast", if owner == player then nil else position)
end

-- Dash de Puños: estela corta
local function quickDashFx(owner: Player, from: Vector3, to: Vector3)
	local color = StyleConfig.Styles.Fists.Color
	local offset = to - from
	local distance = offset.Magnitude
	if distance > 0.5 then
		local trail = fxPart(Vector3.new(2.5, 0.15, distance), CFrame.lookAt(from:Lerp(to, 0.5), to) * CFrame.new(0, -1.8, 0), color)
		trail.Transparency = 0.5
		TweenService:Create(trail, TweenInfo.new(0.3), { Transparency = 1, Size = Vector3.new(0.3, 0.1, distance) }):Play()
		Debris:AddItem(trail, 0.35)
		local ghost = fxPart(Vector3.new(2, 4.5, 1), CFrame.lookAt(from:Lerp(to, 0.4), to), color)
		ghost.Transparency = 0.6
		TweenService:Create(ghost, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		Debris:AddItem(ghost, 0.35)
	end
	if owner == player then
		WaveFx.kick(2)
	end
	playSound("Dash", if owner == player then nil else from)
end

-- Guerrero: Salto aplastante. Tu cliente hace el salto (tu personaje es tuyo: el servidor
-- solo te pone en el sitio si no llegaste); todos ven la estela y el aviso donde caerá.
local function leapMove(from: Vector3, to: Vector3, delay: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid) then
		return
	end
	local flat = Vector3.new(to.X - root.Position.X, 0, to.Z - root.Position.Z)
	local seconds = math.max(0.2, delay)
	local horizontal = flat / seconds
	if flat.Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "LeapAttachment"
	attachment.Parent = root
	local mover = Instance.new("LinearVelocity")
	mover.Name = "LeapMover"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.PlaneVelocity = Vector2.new(horizontal.X, horizontal.Z)
	mover.MaxForce = math.huge
	mover.Parent = root
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	-- Sube y baja en el tiempo del salto (la gravedad hace el resto)
	root.AssemblyLinearVelocity = Vector3.new(horizontal.X, Workspace.Gravity * seconds / 2, horizontal.Z)
	task.delay(seconds, function()
		mover:Destroy()
		attachment:Destroy()
		if root.Parent then
			root.AssemblyLinearVelocity = Vector3.new(0, math.min(root.AssemblyLinearVelocity.Y, 0), 0)
		end
	end)
end

local function leapFx(owner: Player, from: Vector3, to: Vector3, delay: number, radius: number)
	local color = tint or StyleConfig.Styles.Warrior.Color
	local character = owner.Character
	CharacterPose.slam(character)
	if owner == player then
		leapMove(from, to, delay)
	end
	-- Aviso en el suelo donde vas a caer
	local ground = groundBelow(to)
	local mark = fxPart(Vector3.new(0.15, radius * 2, radius * 2), CFrame.new(ground + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), color)
	mark.Shape = Enum.PartType.Cylinder
	mark.Transparency = 0.75
	local inner = fxPart(Vector3.new(0.2, 0.5, 0.5), mark.CFrame, color)
	inner.Shape = Enum.PartType.Cylinder
	inner.Transparency = 0.4
	TweenService:Create(inner, TweenInfo.new(delay, Enum.EasingStyle.Linear), { Size = Vector3.new(0.2, radius * 2, radius * 2), Transparency = 0.6 }):Play()
	Debris:AddItem(mark, delay + 0.05)
	Debris:AddItem(inner, delay + 0.05)
	-- Estela del personaje en el aire
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(0, 1.2, 0)
		top.Parent = root
		local bottom = Instance.new("Attachment")
		bottom.Position = Vector3.new(0, -1.2, 0)
		bottom.Parent = root
		local trail = Instance.new("Trail")
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Lifetime = 0.25
		trail.LightEmission = 1
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		trail.Transparency = NumberSequence.new(0.3, 1)
		trail.Parent = root
		Debris:AddItem(trail, delay + 0.3)
		Debris:AddItem(top, delay + 0.3)
		Debris:AddItem(bottom, delay + 0.3)
	end
	playSound("Dash", if owner == player then nil else from)
end

-- Guerrero: Onda cortante (y Corte dimensional): una media luna que vuela de `from` a `to`
local function slashWaveFx(owner: Player, from: Vector3, to: Vector3, width: number, hits: any)
	local color = tint or StyleConfig.Styles.Warrior.Color
	if not StyleAnimations.enabled("Warrior") then
		CharacterPose.slash(owner.Character, 3)
	elseif owner == player then
		StyleAnimations.slash(1)
	end
	local offset = to - from
	local distance = offset.Magnitude
	if distance > 0.5 then
		local direction = offset.Unit
		local travel = math.clamp(distance / 90, 0.15, 0.6)
		local pieces = 9
		local arc = math.rad(130)
		local glow = color:Lerp(Color3.new(1, 1, 1), 0.3)
		for index = 1, pieces do
			local t = (index - 0.5) / pieces
			local angle = -arc / 2 + arc * t
			-- Media luna: las puntas van un poco por detrás del centro
			local local0 = Vector3.new(math.sin(angle) * width * 0.6, 0, -math.cos(angle) * width * 0.25)
			local base = CFrame.lookAt(from, from + direction)
			local start = base * CFrame.new(local0)
			local piece = fxPart(Vector3.new(0.2, 1.2 * (1 - math.abs(t - 0.5)) + 0.4, width * 0.6 * arc / pieces + 0.3), start * CFrame.Angles(0, angle + math.rad(90), 0), glow)
			piece.Transparency = 0.1
			local finish = CFrame.lookAt(to, to + direction) * CFrame.new(local0) * CFrame.Angles(0, angle + math.rad(90), 0)
			TweenService:Create(piece, TweenInfo.new(travel, Enum.EasingStyle.Linear), { CFrame = finish }):Play()
			TweenService:Create(piece, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, travel - 0.1), { Transparency = 1 }):Play()
			Debris:AddItem(piece, travel + 0.1)
		end
	end
	CombatController.showHits(hits, color, owner == player, 1.1)
	if owner == player then
		WaveFx.kick(3)
	end
	playSound("SwordSpin", if owner == player then nil else from)
end

-- Magia: Teletransporte. Destello donde estabas y donde apareces, y una estela entre ambos
local function blinkFx(owner: Player, from: Vector3, to: Vector3)
	local color = StyleConfig.Styles.Magic.Color
	for _, at in { from, to } do
		local ball = fxPart(Vector3.one * 1, CFrame.new(at), color)
		ball.Shape = Enum.PartType.Ball
		ball.Transparency = 0.2
		TweenService:Create(ball, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 6, Transparency = 1 }):Play()
		Debris:AddItem(ball, 0.35)
		WaveFx.sparkle(at, color, 14)
	end
	local distance = (to - from).Magnitude
	if distance > 0.5 then
		local streak = fxPart(Vector3.new(0.5, 0.5, distance), CFrame.lookAt(from:Lerp(to, 0.5), to), Color3.new(1, 1, 1))
		streak.Transparency = 0.4
		TweenService:Create(streak, TweenInfo.new(0.25), { Transparency = 1, Size = Vector3.new(0.05, 0.05, distance) }):Play()
		Debris:AddItem(streak, 0.3)
	end
	if owner == player then
		WaveFx.kick(2)
	end
	playSound("Blink", if owner == player then nil else from)
end

-- Combo: su nombre grande sobre el enemigo (y un aviso para quien lo hizo)
local COMBO_COLORS = { Weapons = Color3.fromRGB(120, 220, 255), Warrior = Color3.fromRGB(255, 120, 130), Fists = Color3.fromRGB(255, 170, 80), Magic = Color3.fromRGB(210, 150, 255) }
local function comboFx(owner: Player, name: string, position: Vector3, style: string?)
	local color = COMBO_COLORS[style or ""] or Color3.fromRGB(255, 220, 90)
	local anchor = fxPart(Vector3.one * 0.2, CFrame.new(position + Vector3.new(0, 4, 0)), color)
	anchor.Transparency = 1
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(60, 20)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 120
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = FONTS.Display
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeColor3 = INK
	label.TextStrokeTransparency = 0
	label.Text = "💥 " .. name
	label.Parent = billboard
	billboard.Parent = anchor
	TweenService:Create(billboard, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(240, 60) }):Play()
	TweenService:Create(billboard, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1.25)
	CombatController.emitAt("Glint", position, color, 14)
	if owner == player then
		Toasts.show(("💥 %s"):format(name), { Style = "Line", Color = color, Key = "StyleCombo" })
		playSound("Combo")
	end
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
	local hud, buttons, dashUi = buildButtons()
	local first = buttons[1]

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
	first.Switch.Activated:Connect(function()
		PanelManager.toggle(PANEL_NAME)
	end)
	buttons[2].Switch.Activated:Connect(function()
		PanelManager.toggle("Skills")
	end)

	-- Botones: icono, colores y nombre de cada habilidad del estilo actual
	local function refreshButtons()
		local style = styleId()
		local def = StyleConfig.Styles[style]
		local c = def.Color
		for slot, ui in buttons do
			local _, ability, level = equippedSkill(style, slot)
			ui.Button.Text = ability.Icon
			ui.Label.Text = if level > 1 then ("%s Nv.%d"):format(ability.Name, level) else ability.Name
			local tone = if slot == 2 then c:Lerp(Color3.new(0, 0, 0), 0.15) else c
			ui.Gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, tone:Lerp(Color3.new(1, 1, 1), 0.55)),
				ColorSequenceKeypoint.new(0.55, tone),
				ColorSequenceKeypoint.new(1, tone:Lerp(Color3.new(0, 0, 0), 0.35)),
			})
		end
		refreshCards()
		-- 💨 dash de Puños o ✨ teletransporte de Magia
		dashUi.Frame.Visible = (style == "Fists" or style == "Magic") and UserInputService.TouchEnabled
		dashUi.Button.Text = if style == "Magic" then "✨" else "💨"
		dashUi.Frame.BackgroundColor3 = def.Color
	end
	local lastStyle = styleId()
	player:GetAttributeChangedSignal(Constants.Attributes.CombatStyle):Connect(function()
		refreshButtons()
		local now = styleId()
		if now ~= lastStyle then
			lastStyle = now
			local def = StyleConfig.Styles[now]
			Toasts.show(("%s Estilo: %s"):format(def.Icon, def.DisplayName), { Color = def.Color, Key = "StyleSwitch" })
			for _, ui in buttons do
				bounce(ui.Button, 0.15)
			end
			playSound("Switch")
		end
	end)
	refreshButtons()
	player:GetAttributeChangedSignal(Constants.Attributes.SkillSlots):Connect(refreshButtons)
	player:GetAttributeChangedSignal(Constants.Attributes.Skills):Connect(refreshButtons)

	-- Usar las habilidades (1: Z / R1, 2: X / L1) hacia donde apuntas: con la tecla, el
	-- ratón; con el mando o el botón de la pantalla, delante del personaje
	for slot, ui in buttons do
		local function use(aim: Vector3?)
			if aim then
				AimPoint.faceToward(aim)
			end
			actionRemote:FireServer("Ability", slot, aim)
		end
		ui.Button.Activated:Connect(function()
			use(AimPoint.facing(ABILITY_FACING))
		end)
		ContextActionService:BindAction(ABILITY_ACTIONS[slot], function(_, inputState, input)
			if inputState == Enum.UserInputState.Begin then
				local withMouse = input.UserInputType == Enum.UserInputType.Keyboard and UserInputService.MouseEnabled
				use(if withMouse then AimPoint.mouse() else AimPoint.facing(ABILITY_FACING))
			end
			return Enum.ContextActionResult.Pass
		end, false, table.unpack(ABILITY_KEYS[slot]))
	end
	ContextActionService:BindAction(PANEL_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			PanelManager.toggle(PANEL_NAME)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.C)
	ContextActionService:BindAction(SKILLS_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			PanelManager.toggle("Skills")
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.B)
	-- Dash de Puños o teletransporte de Magia (Shift, el stick izquierdo pulsado del mando o
	-- el botón 💨 / ✨). El teletransporte va hacia donde andas; quieto, hacia el ratón.
	local function tryDash()
		local style = styleId()
		if style == "Fists" then
			actionRemote:FireServer("Dash")
		elseif style == "Magic" then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local moving = humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0.1
			local pointer = UserInputService.MouseEnabled and UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch
			actionRemote:FireServer("Blink", if not moving and pointer then AimPoint.mouse() else nil)
		end
	end
	ContextActionService:BindAction(DASH_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			tryDash()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	dashUi.Button.Activated:Connect(tryDash)

	-- Al lado de las habilidades elementales (Q, y R si se ve), o encima en táctil; la segunda
	-- a la izquierda de la primera
	local abilityHud = player:WaitForChild("PlayerGui"):WaitForChild("AbilityHud", 15)
	local secondary = abilityHud and abilityHud:FindFirstChild("SecondaryButton") :: GuiObject?
	local function place()
		local uiScale = UiKit.computeScale(hud.AbsoluteSize)
		local slots = if secondary and secondary.Visible then 2 else 1
		local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		for slot, ui in buttons do
			local shift = (slot - 1) * (BUTTON_SIZE + GAP)
			if touchOnly then
				ui.Frame.Position = UDim2.new(1, -(EDGE + shift * uiScale), 0.5, -(76 + slots * (BUTTON_SIZE + 26)) * uiScale)
			else
				ui.Frame.Position = UDim2.new(1, -(EDGE + (ATTACK_BUTTON + GAP + slots * (BUTTON_SIZE + GAP) + shift) * uiScale), 1, -34)
			end
		end
		-- 💨 a la izquierda de los dos botones del estilo
		local dashShift = 2 * (BUTTON_SIZE + GAP)
		if touchOnly then
			dashUi.Frame.Position = UDim2.new(1, -(EDGE + dashShift * uiScale), 0.5, -(76 + slots * (BUTTON_SIZE + 26) + 7) * uiScale)
		else
			dashUi.Frame.Position = UDim2.new(1, -(EDGE + (ATTACK_BUTTON + GAP + slots * (BUTTON_SIZE + GAP) + dashShift) * uiScale), 1, -41)
		end
	end
	hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	UserInputService.LastInputTypeChanged:Connect(place)
	if secondary then
		secondary:GetPropertyChangedSignal("Visible"):Connect(place)
	end
	place()

	-- Recargas (hora del servidor en que vuelve a estar lista cada una)
	local READY_ATTRIBUTES = { Constants.Attributes.StyleReadyAt, Constants.Attributes.StyleReadyAt2 }
	RunService.Heartbeat:Connect(function()
		local style = styleId()
		for slot, ui in buttons do
			local _, ability, level = equippedSkill(style, slot)
			local total = SkillLogic.cooldown(ability, level) * classMods(style).SkillCooldown
			local readyAt = player:GetAttribute(READY_ATTRIBUTES[slot])
			local left = if typeof(readyAt) == "number" then readyAt - serverNow() else 0
			if left > 0 then
				ui.WasCooling = true
				ui.Cooldown.Size = UDim2.fromScale(1, math.clamp(left / total, 0, 1))
				ui.Count.Visible = true
				ui.Count.Text = tostring(math.ceil(left))
				ui.Button.TextTransparency = 0.5
			else
				ui.Cooldown.Size = UDim2.fromScale(1, 0)
				ui.Count.Visible = false
				ui.Button.TextTransparency = 0
				if ui.WasCooling then
					ui.WasCooling = false
					bounce(ui.Button, 0.12)
					playSound("Ready")
				end
			end
		end
		-- Recarga del dash
		if dashUi.Frame.Visible then
			local dashAt = player:GetAttribute(Constants.Attributes.DashReadyAt)
			local left = if typeof(dashAt) == "number" then dashAt - serverNow() else 0
			local total = if styleId() == "Magic" then StyleConfig.Styles.Magic.Blink.Cooldown else StyleConfig.Styles.Fists.Dash.Cooldown * classMods("Fists").DashCooldown
			dashUi.Cooldown.Size = UDim2.fromScale(1, if left > 0 then math.clamp(left / total, 0, 1) else 0)
		end
	end)

	-- Efectos y resultados
	eventRemote.OnClientEvent:Connect(function(event: any)
		if typeof(event) ~= "table" or typeof(event.Owner) ~= "Instance" then
			return
		end
		local owner = event.Owner :: Player
		tint = if typeof(event.Color) == "Color3" then event.Color else nil
		if event.Kind == "Result" then
			if owner ~= player then
				return
			end
			if typeof(event.Action) == "string" and string.find(event.Action, "Skill") then
				return -- comprar, subir y poner: SkillsController
			end
			local ui = buttons[if event.Slot == 2 then 2 else 1]
			if event.Success == false then
				if event.Code == "NoTarget" then
					Toasts.show("🎯 Apunta a un enemigo (a tu alcance)", { Color = THEME.Error, Key = "StyleNotice" })
				elseif event.Code == "NoMana" then
					Toasts.show("💧 Te falta maná", { Color = Color3.fromRGB(120, 150, 255), Key = "StyleNotice" })
					if event.Action ~= "Blink" then
						bounce(ui.Button, -0.08)
					end
				elseif event.Code == "NotReady" then
					bounce(ui.Button, -0.08)
				end
			elseif event.Action ~= "Set" and event.Action ~= "Blink" then
				bounce(ui.Button, 0.18)
			end
		elseif event.Kind == "Burst" then
			burstFx(owner, tonumber(event.Duration) or 4)
		elseif event.Kind == "Grenade" and typeof(event.From) == "Vector3" and typeof(event.To) == "Vector3" then
			grenadeFx(owner, event.From, event.To, tonumber(event.Delay) or 0.7, tonumber(event.Radius) or 10)
		elseif event.Kind == "GrenadeHit" and typeof(event.Position) == "Vector3" then
			grenadeHitFx(owner, event.Position, tonumber(event.Radius) or 10, event.Hits)
		elseif event.Kind == "Quake" and typeof(event.Position) == "Vector3" then
			quakeFx(owner, event.Position, tonumber(event.Radius) or 14, event.Hits)
		elseif event.Kind == "Dash" and typeof(event.From) == "Vector3" and typeof(event.To) == "Vector3" then
			dashFx(owner, event.From, event.To, event.Hits)
		elseif event.Kind == "Meteor" then
			meteorFx(owner, event.Points, tonumber(event.Delay) or 0.6, tonumber(event.Interval) or 0.2, tonumber(event.Radius) or 7, tonumber(event.StartAt) or serverNow())
		elseif event.Kind == "MeteorHit" and typeof(event.Position) == "Vector3" then
			meteorHitFx(owner, event.Position, tonumber(event.Radius) or 7, event.Hits)
		elseif event.Kind == "Nova" and typeof(event.Position) == "Vector3" then
			novaFx(owner, event.Position, tonumber(event.Radius) or 16, event.Hits, event.Frozen)
		elseif event.Kind == "Pierce" and typeof(event.From) == "Vector3" and typeof(event.To) == "Vector3" then
			pierceFx(owner, event.From, event.To, tonumber(event.Width) or 5, event.Hits)
		elseif event.Kind == "Turret" and typeof(event.Position) == "Vector3" then
			turretFx(owner, event.Position, tonumber(event.Duration) or 8)
		elseif event.Kind == "TurretShot" and typeof(event.From) == "Vector3" and typeof(event.To) == "Vector3" then
			turretShotFx(owner, event.From, event.To, event.Hits)
		elseif event.Kind == "TurretEnd" then
			removeTurret(owner)
		elseif event.Kind == "Rage" then
			rageFx(owner, tonumber(event.Duration) or 6)
		elseif event.Kind == "Whirl" then
			whirlFx(owner, tonumber(event.Radius) or 11, tonumber(event.Pulses) or 4, tonumber(event.Interval) or 0.3)
		elseif event.Kind == "WhirlHit" and typeof(event.Position) == "Vector3" then
			whirlHitFx(owner, event.Position, tonumber(event.Radius) or 11, event.Hits)
		elseif event.Kind == "Lightning" then
			lightningFx(owner, event.Points, event.Hits)
		elseif event.Kind == "BlackHole" and typeof(event.Position) == "Vector3" then
			blackHoleFx(owner, event.Position, tonumber(event.Radius) or 14, tonumber(event.Duration) or 3)
		elseif event.Kind == "BlackHoleTick" then
			CombatController.showHits(event.Hits, tint or StyleConfig.Styles.Magic.Color, owner == player, 0.7)
		elseif event.Kind == "BlackHoleBlast" and typeof(event.Position) == "Vector3" then
			blackHoleBlastFx(owner, event.Position, tonumber(event.Radius) or 14, event.Hits)
		elseif event.Kind == "QuickDash" and typeof(event.From) == "Vector3" and typeof(event.To) == "Vector3" then
			quickDashFx(owner, event.From, event.To)
		elseif event.Kind == "Leap" and typeof(event.From) == "Vector3" and typeof(event.To) == "Vector3" then
			leapFx(owner, event.From, event.To, tonumber(event.Delay) or 0.55, tonumber(event.Radius) or 13)
		elseif event.Kind == "SlashWave" and typeof(event.From) == "Vector3" and typeof(event.To) == "Vector3" then
			slashWaveFx(owner, event.From, event.To, tonumber(event.Width) or 7, event.Hits)
		elseif event.Kind == "Blink" and typeof(event.From) == "Vector3" and typeof(event.To) == "Vector3" then
			blinkFx(owner, event.From, event.To)
		elseif event.Kind == "Combo" and typeof(event.Name) == "string" and typeof(event.Position) == "Vector3" then
			comboFx(owner, event.Name, event.Position, if typeof(event.Style) == "string" then event.Style else nil)
		end
		tint = nil
	end)
end

return StyleController
