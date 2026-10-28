-- AbilityController · Gui: selección de elemento por hueco y construcción de los botones Q y R (buildSlot, buildGui).
-- Parte de AbilityController (ver AbilityController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local CoreConfig = require(Shared.Config.CoreConfig)
local AbilityLogic = require(Shared.AbilityLogic)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)
local Types = require(script.Parent.Types)
type SlotUi = Types.SlotUi

local ctx: any -- tabla de estado compartida (la crea AbilityController/init.luau)
local ATTACK_BUTTON: any
local BUTTON_SIZE: any
local EDGE: any
local FONTS: any
local GAP: any
local THEME: any
local player: any

-- Interfaz -------------------------------------------------------------------------------

local function unlockedList(): { string }
	local value = player:GetAttribute(Constants.Attributes.UnlockedCores)
	local list = {}
	if typeof(value) == "string" then
		for _, id in string.split(value, ",") do
			if id ~= "" then
				table.insert(list, id)
			end
		end
	end
	return list
end

-- Elemento de cada hueco (misma regla que el servidor).
local function slotElement(slot: string): string?
	local unlocked = {}
	for _, id in unlockedList() do
		unlocked[id] = true
	end
	-- Como AbilityService.elementOf: Naturaleza ya no da habilidad (era Raíces; ahora todos
	-- tienen el dash), así que con ella de principal el secundario pasa a la Q.
	local selected = player:GetAttribute(Constants.Attributes.SelectedCore)
	local secondary = player:GetAttribute(Constants.Attributes.SecondaryCore)
	local primaryOk = typeof(selected) == "string" and unlocked[selected] and AbilityLogic.castable(selected) ~= nil
	local secondaryOk = typeof(secondary) == "string" and unlocked[secondary] and secondary ~= selected and AbilityLogic.castable(secondary) ~= nil
	if slot == "Secondary" then
		return if primaryOk and secondaryOk then secondary else nil
	end
	if primaryOk then
		return selected
	elseif secondaryOk then
		return secondary
	end
	return if AbilityLogic.castable(CoreConfig.DefaultElement) then CoreConfig.DefaultElement else nil
end

-- Núcleos despiertos que dan habilidad (Naturaleza no)
local function castableCount(): number
	local count = 0
	for _, id in unlockedList() do
		if AbilityLogic.castable(id) then
			count += 1
		end
	end
	return count
end


local INK = Color3.fromRGB(43, 29, 63)
local CREAM = Color3.fromRGB(255, 246, 224)

local function buildSlot(screenGui: ScreenGui, name: string, key: string): (SlotUi, UIScale)
	local frame, scale = UiKit.panel(screenGui, name, Vector2.new(BUTTON_SIZE, BUTTON_SIZE), Vector2.new(1, 1), UDim2.new(1, -112, 1, -22))
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 0
	frame:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0)
	local shine = frame:FindFirstChild("Shine")
	if shine then
		shine:Destroy()
	end
	local oldGrad = frame:FindFirstChildOfClass("UIGradient")
	if oldGrad then
		oldGrad:Destroy()
	end
	local grad = UiKit.create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 247, 168)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(95, 203, 82)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(47, 154, 58)),
		}),
	}, frame)
	local stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Color = INK
	stroke.Thickness = 4
	stroke.Transparency = 0
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
		TextSize = 36,
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
		TextSize = 30,
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
	UiKit.create("UIStroke", {
		Color = Color3.new(1, 1, 1),
		Thickness = 1.5,
		Transparency = 0.72,
	}, keyBadge)
	UiKit.text(keyBadge, "Hint", {
		Size = UDim2.fromScale(1, 1),
		Font = FONTS.Display,
		TextSize = 13,
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = key,
		ZIndex = 6,
	})
	local label = UiKit.text(frame, "AbilityName", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 5),
		Size = UDim2.fromOffset(80, 18),
		Font = FONTS.Display,
		TextSize = 13,
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 4,
	})
	UiKit.create("UIStroke", {
		Color = INK,
		Thickness = 2.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, label)
	local readyRing = UiKit.create("Frame", {
		Name = "ReadyRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
	}, frame)
	UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, readyRing)
	local readyStroke = UiKit.stroke(readyRing, THEME.Gold, 3, 1)
	return {
		Frame = frame,
		Gradient = grad,
		Stroke = stroke,
		Button = button,
		Cooldown = cooldown,
		Count = count,
		Name = label,
		ReadyStroke = readyStroke,
	}, scale
end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("AbilityHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "AbilityHud",
		ResetOnSpawn = false,
		DisplayOrder = 3,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)

	local primary, primaryScale = buildSlot(screenGui, "AbilityButton", "Q")
	local secondary, secondaryScale = buildSlot(screenGui, "SecondaryButton", "R")
	local notice = UiKit.text(primary.Frame, "Notice", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -8),
		Size = UDim2.fromOffset(260, 18),
		Font = FONTS.Body,
		TextSize = 14,
		TextColor3 = THEME.Error,
		TextStrokeColor3 = THEME.Outline,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		ZIndex = 5,
	})
	local flash = UiKit.create("Frame", {
		Name = "AbilityFlash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 20,
	}, screenGui)
	ctx.flashFrame = flash

	screenGui.Parent = playerGui
	UiKit.bindScale(screenGui, { primaryScale, secondaryScale })

	local function place()
		local uiScale = UiKit.computeScale(screenGui.AbsoluteSize)
		local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		if touchOnly then
			primary.Frame.Position = UDim2.new(1, -EDGE, 0.5, -76 * uiScale)
			secondary.Frame.Position = UDim2.new(1, -EDGE, 0.5, -(76 + BUTTON_SIZE + 26) * uiScale)
		else
			primary.Frame.Position = UDim2.new(1, -(EDGE + (ATTACK_BUTTON + GAP) * uiScale), 1, -34)
			secondary.Frame.Position = UDim2.new(1, -(EDGE + (ATTACK_BUTTON + GAP + BUTTON_SIZE + GAP) * uiScale), 1, -34)
		end
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	UiKit.onScaleChanged(place) -- ⚙️ tamaño de la interfaz
	UserInputService.LastInputTypeChanged:Connect(place)
	place()

	return { Primary = primary, Secondary = secondary, Notice = notice }
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.INK = INK
	context.buildGui = buildGui
	context.castableCount = castableCount
	context.slotElement = slotElement
end

function Part.link(context: any)
	ATTACK_BUTTON = context.ATTACK_BUTTON
	BUTTON_SIZE = context.BUTTON_SIZE
	EDGE = context.EDGE
	FONTS = context.FONTS
	GAP = context.GAP
	THEME = context.THEME
	player = context.player
end

return Part
