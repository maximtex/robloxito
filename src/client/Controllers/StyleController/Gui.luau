-- StyleController · Gui: constantes, sonidos, datos del estilo y construcción del panel y los botones (Z, X y dash).
-- Parte de StyleController (ver StyleController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local StyleConfig = require(Shared.Config.StyleConfig)
local SkillLogic = require(Shared.SkillLogic)
local ClassLogic = require(Shared.ClassLogic)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)

local ctx: any -- tabla de estado compartida (la crea StyleController/init.luau)

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


local player = Players.LocalPlayer

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
	if at and ctx.fxFolder then
		-- Las de otros jugadores suenan en su sitio (se apagan con la distancia)
		local holder = Instance.new("Part")
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.one * 0.2
		holder.CFrame = CFrame.new(at)
		holder.Parent = ctx.fxFolder
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
	-- 💨 Dash (todos; Magia: ✨ teletransporte). Con teclado, Shift
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
	-- Tecla debajo (solo con teclado)
	local dashKey = UiKit.text(dashFrame, "Key", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.fromOffset(64, 16),
		Font = FONTS.Display,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "Shift",
		ZIndex = 4,
	})
	UiKit.outline(dashKey, 1.5)
	dashFrame.Visible = false
	screenGui.Parent = playerGui
	UiKit.bindScale(screenGui, { buttons[1].Scale, buttons[2].Scale, dashScale })
	return screenGui, buttons, { Frame = dashFrame, Button = dashButton, Cooldown = dashCooldown, Key = dashKey }
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.ABILITY_ACTIONS = ABILITY_ACTIONS
	context.ABILITY_FACING = ABILITY_FACING
	context.ABILITY_KEYS = ABILITY_KEYS
	context.ATTACK_BUTTON = ATTACK_BUTTON
	context.BUTTON_SIZE = BUTTON_SIZE
	context.DASH_ACTION = DASH_ACTION
	context.EDGE = EDGE
	context.FONTS = FONTS
	context.GAP = GAP
	context.ICE = ICE
	context.INK = INK
	context.PANEL_ACTION = PANEL_ACTION
	context.PANEL_NAME = PANEL_NAME
	context.PANEL_SIZE = PANEL_SIZE
	context.SKILLS_ACTION = SKILLS_ACTION
	context.THEME = THEME
	context.buildButtons = buildButtons
	context.buildPanel = buildPanel
	context.classMods = classMods
	context.equippedSkill = equippedSkill
	context.playSound = playSound
	context.player = player
	context.serverNow = serverNow
	context.styleId = styleId
end

function Part.link(context: any)
	-- (nada que enlazar)
end

return Part
