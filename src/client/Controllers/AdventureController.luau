-- Aventuras (solo presentación; el servidor decide todo):
-- - Sobre cada personaje: nombre, oficio y su aviso: "!" dorado (tiene una misión para ti),
--   "?" verde (vuelve a entregarla) o "…" (en curso). Se giran hacia el jugador cercano.
-- - Conversación (abajo, al pulsar E junto al personaje): texto con efecto de máquina de
--   escribir, objetivo con progreso, recompensa y botones Aceptar / Entregar / Ahora no.
--   Si el jugador traía un encargo para ese personaje, primero se ve la entrega.
-- - Seguimiento de las misiones en curso (columna derecha en escritorio, bajo el menú en
--   táctil) con tantas filas como quepan; avisos breves en la pila común (Toasts).
-- - Objetos perdidos: solo los ve quien tiene esa misión; brillan, flotan y tienen un haz
--   de luz para encontrarlos de lejos. El servidor los recoge al pasar cerca.
-- - Azulejo "Amuletos" en la barra del menú (tecla G): ranuras, amuletos, bendiciones e
--   historias. Bajo el menú, las bendiciones activas con su tiempo. Al conseguir un amuleto,
--   tarjeta de celebración.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local AdventureConfig = require(Shared.Config.AdventureConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local AdventureLogic = require(Shared.AdventureLogic)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local MenuBar = require(script.Parent.Parent.UI.MenuBar)
local Toasts = require(script.Parent.Parent.UI.Toasts)
local HudDock = require(script.Parent.Parent.UI.HudDock)
local HudLayout = require(script.Parent.Parent.UI.HudLayout)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local Codes = Constants.PurchaseCodes
local COLORS = AdventureConfig.Colors

local DIALOG_PANEL = "AdventureDialog"
local AMULET_PANEL = "Amulets"
local DIALOG_SIZE = Vector2.new(620, 252)
local AMULET_PANEL_SIZE = Vector2.new(660, 560)
local TRACKER_WIDTH = HudLayout.Sizes.TrackerWidth
local TRACKER_ROW = HudLayout.Sizes.TrackerRow
local CLOSE_DISTANCE = 20 -- la conversación se cierra al alejarse
local FACE_DISTANCE = 18 -- los personajes miran al jugador cercano
local ANIMATE_DISTANCE = 90
local TYPE_SPEED = 70 -- letras por segundo
local ITEM_FLOAT = 1.6 -- altura del objeto sobre el suelo

local MESSAGES = {
	[Codes.TooFar] = "Acércate más para hablar.",
	[Codes.NotReady] = "Tus datos aún se están cargando.",
	[Codes.TooFast] = "Espera un momento.",
	[Codes.NotComplete] = "Todavía no has terminado esa misión.",
	[Codes.AlreadyAccepted] = "Esa misión ya está en curso.",
	[Codes.AlreadyClaimed] = "Ya entregaste esa misión.",
	[Codes.NotOwned] = "No tienes eso.",
	[Codes.Locked] = "Esa ranura se abre al terminar las historias del Bosque y del Valle.",
	[Codes.AlreadySelected] = "Ya lo llevas puesto.",
	[Codes.MaxLevel] = "Esa bendición ya está al máximo de tiempo.",
	[Codes.InvalidRequest] = "Esa acción no está disponible.",
}

local AdventureController = {}

local player = Players.LocalPlayer
local state: any = { Ready = false }

-- Utilidades --------------------------------------------------------------------------------

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function playSound(spec: any)
	if not spec then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = spec.Id
	sound.Volume = spec.Volume or 0.5
	sound.PlaybackSpeed = spec.Pitch or 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(6, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local function npcState(npcId: string): any
	return state.Ready and state.Npcs and state.Npcs[npcId] or AdventureLogic.state(nil, npcId)
end

local function fullName(npc: any): string
	return ("%s, %s"):format(npc.DisplayName, string.lower(npc.Title))
end

local function clockText(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

-- "Encuentra las flores de rocío (2/5)", "Derrota Espinillos (3/8)"...
local function objectiveText(npcId: string, st: any): string
	local step = AdventureLogic.stepOf(npcId, st.Step)
	if not step then
		return ""
	end
	local goal = step.Goal
	if goal.Type == "Talk" then
		return step.Objective
	end
	return ("%s (%d/%d)"):format(step.Objective, st.Progress, st.Target)
end

local function rewardText(npcId: string, st: any): string
	local step = AdventureLogic.stepOf(npcId, st.Step)
	if not step then
		return ""
	end
	local parts = {}
	if (st.Reward or 0) > 0 then
		table.insert(parts, ("⚡ %s"):format(formatNumber(st.Reward)))
	end
	local blessing = step.Reward.Blessing and AdventureConfig.Blessings[step.Reward.Blessing]
	if blessing then
		table.insert(parts, ("%s %s"):format(blessing.Icon, blessing.DisplayName))
	end
	local amulet = step.Reward.Amulet and AdventureConfig.Amulets[step.Reward.Amulet]
	if amulet then
		table.insert(parts, ("%s %s"):format(amulet.Icon, amulet.DisplayName))
	end
	return "Recompensa: " .. table.concat(parts, "  ·  ")
end

-- Construcción de la interfaz ------------------------------------------------------------------

local function buildDialog(screenGui: ScreenGui): any
	local panel, scale = UiKit.panel(screenGui, "AdventureDialog", DIALOG_SIZE, Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -24))
	-- Retrato: círculo con la inicial y el color del personaje
	local portrait = UiKit.create("Frame", {
		Name = "Portrait",
		Position = UDim2.fromOffset(20, -26),
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = THEME.Inset,
		ZIndex = 3,
	}, panel)
	UiKit.corner(portrait, 32)
	local portraitStroke = UiKit.stroke(portrait, THEME.Gold, 2.5, 0)
	local portraitText = UiKit.text(portrait, "Initial", {
		Size = UDim2.fromScale(1, 1),
		Font = FONTS.Display,
		TextSize = 32,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	})
	local name = UiKit.text(panel, "Name", {
		Position = UDim2.fromOffset(96, 8),
		Size = UDim2.new(1, -150, 0, 26),
		Font = FONTS.Display,
		TextSize = 22,
		TextColor3 = THEME.Gold,
	})
	local title = UiKit.text(panel, "Title", {
		Position = UDim2.fromOffset(96, 34),
		Size = UDim2.new(1, -150, 0, 18),
		Font = FONTS.Light,
		TextSize = 14,
		TextColor3 = THEME.Muted,
	})
	local close = UiKit.button(panel, "Close", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = THEME.Inset,
		TextSize = 16,
		Text = "×",
	})
	local body = UiKit.text(panel, "Body", {
		Position = UDim2.fromOffset(22, 62),
		Size = UDim2.new(1, -44, 0, 66),
		Font = FONTS.Body,
		TextSize = 17,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local skip = UiKit.create("TextButton", {
		Name = "Skip",
		Position = body.Position,
		Size = body.Size,
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 2,
	}, panel)
	local objective = UiKit.create("Frame", {
		Name = "Objective",
		Position = UDim2.fromOffset(22, 134),
		Size = UDim2.new(1, -44, 0, 52),
		BackgroundColor3 = THEME.Inset,
		BackgroundTransparency = 0.25,
	}, panel)
	UiKit.corner(objective, 10)
	local objectiveStroke = UiKit.stroke(objective, THEME.Stroke, 1, 0.5)
	local objectiveText = UiKit.text(objective, "Goal", {
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(1, -24, 0, 22),
		Font = FONTS.Body,
		TextSize = 15,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local reward = UiKit.text(objective, "Reward", {
		Position = UDim2.fromOffset(12, 26),
		Size = UDim2.new(1, -24, 0, 20),
		Font = FONTS.Light,
		TextSize = 14,
		TextColor3 = THEME.Gold,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local buttons = UiKit.create("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -22, 1, -14),
		Size = UDim2.new(1, -44, 0, 42),
		BackgroundTransparency = 1,
	}, panel)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, buttons)
	local primary = UiKit.button(buttons, "Primary", {
		Size = UDim2.fromOffset(190, 42),
		TextSize = 19,
		LayoutOrder = 2,
	})
	local primaryShimmer = UiKit.shimmer(primary, 10)
	local secondary = UiKit.button(buttons, "Secondary", {
		Size = UDim2.fromOffset(150, 42),
		BackgroundColor3 = THEME.Secondary,
		TextSize = 17,
		LayoutOrder = 1,
	})
	local feedback = UiKit.text(panel, "Feedback", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 22, 1, -22),
		Size = UDim2.new(1, -420, 0, 24),
		Font = FONTS.Body,
		TextSize = 14,
		TextColor3 = THEME.Error,
		TextWrapped = true,
	})
	return {
		Panel = panel,
		Scale = scale,
		Portrait = portrait,
		PortraitStroke = portraitStroke,
		PortraitText = portraitText,
		Name = name,
		Title = title,
		Close = close,
		Body = body,
		Skip = skip,
		Objective = objective,
		ObjectiveStroke = objectiveStroke,
		ObjectiveText = objectiveText,
		Reward = reward,
		Primary = primary,
		PrimaryShimmer = primaryShimmer,
		Secondary = secondary,
		Feedback = feedback,
	}
end

local function sectionTitle(parent: Instance, text: string, order: number): TextLabel
	return UiKit.text(parent, "Section" .. order, {
		Size = UDim2.new(1, 0, 0, 26),
		Font = FONTS.Display,
		TextSize = 19,
		TextColor3 = THEME.Gold,
		Text = text,
		LayoutOrder = order,
	})
end

local function rowFrame(parent: Instance, name: string, height: number, order: number): Frame
	local row = UiKit.create("Frame", {
		Name = name,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = THEME.Inset,
		BackgroundTransparency = 0.25,
		LayoutOrder = order,
	}, parent)
	UiKit.corner(row, 12)
	return row
end

local function buildAmuletPanel(screenGui: ScreenGui): any
	local panel, scale = UiKit.panel(screenGui, "AmuletPanel", AMULET_PANEL_SIZE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.2))
	UiKit.text(panel, "Heading", {
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -90, 0, 32),
		Font = FONTS.Display,
		TextSize = 28,
		Text = "🧿 Amuletos y bendiciones",
	})
	local subtitle = UiKit.text(panel, "Subtitle", {
		Position = UDim2.fromOffset(22, 48),
		Size = UDim2.new(1, -90, 0, 20),
		Font = FONTS.Light,
		TextSize = 15,
		TextColor3 = THEME.Muted,
		Text = "Ayuda a los personajes del mapa: sus historias dan bendiciones y amuletos.",
	})
	local close = UiKit.button(panel, "Close", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = THEME.Inset,
		Text = "×",
	})
	local list = UiKit.create("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(22, 80),
		Size = UDim2.new(1, -44, 1, -120),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = THEME.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, panel)
	UiKit.create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	UiKit.create("UIPadding", { PaddingRight = UDim.new(0, 10) }, list)
	local feedback = UiKit.text(panel, "Feedback", {
		Position = UDim2.new(0, 22, 1, -34),
		Size = UDim2.new(1, -44, 0, 24),
		Font = FONTS.Body,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	return { Panel = panel, Scale = scale, Subtitle = subtitle, Close = close, List = list, Feedback = feedback }
end

-- Seguimiento de misiones: una lista en la columna de HudDock que toque (derecha en
-- escritorio, bajo el menú en táctil).
local function buildTracker(): any
	local frame = UiKit.create("Frame", {
		Name = "AdventureTracker",
		Size = UDim2.fromOffset(TRACKER_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, nil)
	local scale = UiKit.create("UIScale", {}, frame)
	local list = UiKit.create("UIListLayout", { Padding = UDim.new(0, HudLayout.Sizes.TrackerGap), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right }, frame)
	HudDock.attach(HudDock.trackerColumn(), frame, 20)
	return { Frame = frame, Scale = scale, List = list, Rows = {} }
end

-- Tarjeta de celebración (amuleto nuevo).
local function buildCelebration(playerGui: PlayerGui): any
	local gui = UiKit.create("ScreenGui", {
		Name = "AdventureCelebration",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 30,
		Enabled = false,
	}, playerGui)
	local dim = UiKit.create("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = THEME.Overlay,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}, gui)
	local card, scale = UiKit.panel(gui, "Card", Vector2.new(440, 300), Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5))
	local cardStroke = card:FindFirstChildOfClass("UIStroke")
	local heading = UiKit.text(card, "Heading", {
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 30),
		Font = FONTS.Display,
		TextSize = 26,
		TextColor3 = THEME.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "¡Nuevo amuleto!",
	})
	local icon = UiKit.text(card, "Icon", {
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 80),
		Font = FONTS.Display,
		TextSize = 64,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local itemName = UiKit.text(card, "ItemName", {
		Position = UDim2.fromOffset(0, 140),
		Size = UDim2.new(1, 0, 0, 30),
		Font = FONTS.Display,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local description = UiKit.text(card, "Description", {
		Position = UDim2.fromOffset(24, 172),
		Size = UDim2.new(1, -48, 0, 44),
		Font = FONTS.Body,
		TextSize = 16,
		TextColor3 = THEME.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local equip = UiKit.button(card, "Equip", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, -84, 1, -20),
		Size = UDim2.fromOffset(160, 44),
		TextSize = 19,
		Text = "Ponérmelo",
	})
	local ok = UiKit.button(card, "Ok", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 84, 1, -20),
		Size = UDim2.fromOffset(160, 44),
		BackgroundColor3 = THEME.Secondary,
		TextSize = 19,
		Text = "¡Genial!",
	})
	return { Gui = gui, Dim = dim, Card = card, Scale = scale, Stroke = cardStroke, Heading = heading, Icon = icon, ItemName = itemName, Description = description, Equip = equip, Ok = ok }
end

-- Objetos perdidos (solo en este cliente) ---------------------------------------------------------

local itemsFolder: Folder? = nil
local itemVisuals: { [string]: { Model: Model, Base: Vector3, Phase: number } } = {}

local function itemWorldPosition(itemId: string): Vector3?
	local info = ReplicatedStorage:FindFirstChild("AdventureWorld")
	local value = info and info:GetAttribute("Item_" .. itemId)
	return if typeof(value) == "Vector3" then value else nil
end

local function localPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	if shape then
		part.Shape = shape
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- Forma de cada tipo de objeto, alrededor de `center` (todo anclado; se mueve con PivotTo).
local SHAPES = {}

function SHAPES.Dew(model: Model, center: CFrame, kind: any)
	-- Flor de cinco pétalos de cara al jugador, con tallo y hoja.
	local face = center * CFrame.Angles(math.rad(-70), 0, 0)
	for index = 1, 5 do
		local angle = math.rad(index * 72)
		localPart(model, "Petal" .. index, Vector3.new(0.62, 0.62, 0.62), face * CFrame.new(math.cos(angle) * 0.42, 0, math.sin(angle) * 0.42), kind.Color, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	localPart(model, "Center", Vector3.new(0.46, 0.46, 0.46), face * CFrame.new(0, 0.12, 0), Color3.fromRGB(255, 226, 110), Enum.Material.Neon, Enum.PartType.Ball)
	localPart(model, "Stem", Vector3.new(1.2, 0.12, 0.12), center * CFrame.new(0, -0.75, 0.15) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(90, 170, 80), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	localPart(model, "Leaf", Vector3.new(0.6, 0.08, 0.3), center * CFrame.new(0.25, -0.9, 0.15) * CFrame.Angles(0, 0, math.rad(25)), Color3.fromRGB(100, 190, 90), Enum.Material.SmoothPlastic)
end

function SHAPES.Arrow(model: Model, center: CFrame, kind: any)
	local tilt = center * CFrame.Angles(0, 0, math.rad(35))
	localPart(model, "Shaft", Vector3.new(2.4, 0.14, 0.14), tilt, Color3.fromRGB(150, 104, 62), Enum.Material.Wood, Enum.PartType.Cylinder)
	localPart(model, "Tip", Vector3.new(0.4, 0.3, 0.3), tilt * CFrame.new(1.3, 0, 0) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(200, 204, 214), Enum.Material.Metal)
	for side = -1, 1, 2 do
		localPart(model, "Fletch" .. side, Vector3.new(0.5, 0.06, 0.32), tilt * CFrame.new(-1.0, side * 0.1, 0) * CFrame.Angles(side * math.rad(30), 0, 0), kind.Color, Enum.Material.Neon)
	end
end

function SHAPES.Map(model: Model, center: CFrame, kind: any)
	localPart(model, "Paper", Vector3.new(1.3, 0.08, 1.0), center * CFrame.Angles(math.rad(-60), math.rad(15), 0), kind.Color, Enum.Material.SmoothPlastic)
	localPart(model, "Mark", Vector3.new(0.3, 0.1, 0.3), center * CFrame.Angles(math.rad(-60), math.rad(15), 0) * CFrame.new(0.2, 0.02, 0.1), Color3.fromRGB(214, 70, 60), Enum.Material.Neon)
end

function SHAPES.Ember(model: Model, center: CFrame, kind: any)
	-- Piedra oscura con grietas de lava y un corazón brillante.
	localPart(model, "Rock", Vector3.new(1.1, 0.9, 1.0), center * CFrame.Angles(0.4, 0.7, 0.2), Color3.fromRGB(64, 50, 50), Enum.Material.Basalt)
	localPart(model, "Core", Vector3.new(0.75, 0.75, 0.75), center * CFrame.new(0, 0.1, 0), kind.Color, Enum.Material.Neon, Enum.PartType.Ball)
	for index = 1, 3 do
		local angle = math.rad(index * 120)
		localPart(model, "Crack" .. index, Vector3.new(0.12, 0.7, 0.12), center * CFrame.Angles(0, angle, math.rad(35)) * CFrame.new(0, 0, -0.52), kind.Glow, Enum.Material.Neon)
	end
end

function SHAPES.Shard(model: Model, center: CFrame, kind: any)
	localPart(model, "Crystal", Vector3.new(0.6, 1.4, 0.6), center * CFrame.Angles(0, math.rad(45), math.rad(10)), kind.Color, Enum.Material.Neon)
	localPart(model, "Small", Vector3.new(0.35, 0.8, 0.35), center * CFrame.new(0.45, -0.3, 0.1) * CFrame.Angles(0, 0, math.rad(-30)), kind.Glow, Enum.Material.Neon)
end

local function makeItem(itemId: string, ground: Vector3): Model
	local item = AdventureConfig.Items[itemId]
	local kind = AdventureConfig.ItemKinds[item.Kind]
	local model = Instance.new("Model")
	model.Name = itemId
	local center = CFrame.new(ground + Vector3.new(0, ITEM_FLOAT, 0))
	local anchor = localPart(model, "Anchor", Vector3.new(0.2, 0.2, 0.2), center, kind.Glow, Enum.Material.SmoothPlastic)
	anchor.Transparency = 1
	model.PrimaryPart = anchor
	local shape = SHAPES[item.Kind] or SHAPES.Shard
	shape(model, center, kind)
	-- Haz de luz para verlo de lejos
	local beam = localPart(model, "Beam", Vector3.new(26, 0.35, 0.35), CFrame.new(ground + Vector3.new(0, 13, 0)) * CFrame.Angles(0, 0, math.rad(90)), kind.Glow, Enum.Material.Neon, Enum.PartType.Cylinder)
	beam.Transparency = 0.78
	local light = Instance.new("PointLight")
	light.Color = kind.Glow
	light.Range = 9
	light.Brightness = 1
	light.Shadows = false
	light.Parent = anchor
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Rate = 5
	sparkle.Lifetime = NumberRange.new(0.8, 1.4)
	sparkle.Speed = NumberRange.new(0.5, 1.2)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new(0.22, 0)
	sparkle.LightEmission = 1
	sparkle.Color = ColorSequence.new(kind.Glow)
	sparkle.Parent = anchor
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(44, 44)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.MaxDistance = 160
	billboard.LightInfluence = 0
	billboard.AlwaysOnTop = true
	billboard.Parent = anchor
	UiKit.text(billboard, "Icon", {
		Size = UDim2.fromScale(1, 1),
		Font = FONTS.Display,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = kind.Icon,
	})
	return model
end

local function burstAt(position: Vector3, color: Color3)
	local folder = itemsFolder
	if not folder then
		return
	end
	local part = localPart(folder, "Burst", Vector3.new(0.2, 0.2, 0.2), CFrame.new(position), color, Enum.Material.SmoothPlastic)
	part.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.LightEmission = 1
	emitter.Color = ColorSequence.new(color)
	emitter.Parent = part
	emitter:Emit(30)
	local ring = localPart(folder, "Ring", Vector3.new(0.2, 1, 1), CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon, Enum.PartType.Cylinder)
	ring.Transparency = 0.2
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.1, 8, 8), Transparency = 1 }):Play()
	task.delay(1.2, function()
		part:Destroy()
		ring:Destroy()
	end)
end

-- Muestra los objetos pendientes y quita (con estallido) los recogidos.
local function syncItems(pending: { string }, found: { [string]: boolean })
	local folder = itemsFolder
	if not folder then
		return
	end
	local wanted = {}
	for _, itemId in pending do
		wanted[itemId] = true
		if not itemVisuals[itemId] then
			local ground = itemWorldPosition(itemId)
			if ground then
				local model = makeItem(itemId, ground)
				model.Parent = folder
				itemVisuals[itemId] = { Model = model, Base = ground + Vector3.new(0, ITEM_FLOAT, 0), Phase = math.random() * math.pi * 2 }
			end
		end
	end
	for itemId, visual in itemVisuals do
		if not wanted[itemId] then
			if found[itemId] then
				local kind = AdventureConfig.ItemKinds[AdventureConfig.Items[itemId].Kind]
				burstAt(visual.Base, kind.Glow)
			end
			visual.Model:Destroy()
			itemVisuals[itemId] = nil
		end
	end
end

-- Personajes: nombre, aviso y giro hacia el jugador ------------------------------------------------

type NpcView = { Model: Model?, Billboard: BillboardGui, Indicator: TextLabel, Home: CFrame?, Yaw: number?, IndicatorTween: Tween? }

local npcViews: { [string]: NpcView } = {}

local function buildNpcBillboard(npcId: string, playerGui: PlayerGui): NpcView
	local npc = AdventureConfig.Npcs[npcId]
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Npc_" .. npcId
	billboard.Size = UDim2.fromOffset(220, 110)
	billboard.StudsOffset = Vector3.new(0, 2.9, 0)
	billboard.MaxDistance = 80
	billboard.LightInfluence = 0
	billboard.AlwaysOnTop = false
	billboard.ResetOnSpawn = false
	billboard.Enabled = false
	billboard.Parent = playerGui
	local indicator = UiKit.text(billboard, "Indicator", {
		Size = UDim2.new(1, 0, 0, 56),
		Font = FONTS.Display,
		TextSize = 54,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Color3.fromRGB(40, 28, 10),
	})
	UiKit.text(billboard, "Name", {
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 26),
		Font = FONTS.Display,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		Text = npc.DisplayName,
	})
	UiKit.text(billboard, "Title", {
		Position = UDim2.fromOffset(0, 86),
		Size = UDim2.new(1, 0, 0, 18),
		Font = FONTS.Body,
		TextSize = 15,
		TextColor3 = THEME.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		Text = npc.Title,
	})
	return { Model = nil, Billboard = billboard, Indicator = indicator, Home = nil, Yaw = nil, IndicatorTween = nil }
end

local function refreshIndicator(npcId: string)
	local view = npcViews[npcId]
	if not view then
		return
	end
	local st = npcState(npcId)
	local text, color = "", COLORS.Active
	if st.Status == "Offer" then
		text, color = "!", COLORS.Offer
	elseif st.Status == "Ready" then
		text, color = "?", COLORS.Ready
	elseif st.Status == "Active" then
		text, color = "…", COLORS.Active
	end
	view.Indicator.Text = text
	view.Indicator.TextColor3 = color
	view.Indicator.TextSize = if st.Status == "Active" then 40 else 54
	if view.IndicatorTween then
		view.IndicatorTween:Cancel()
		view.IndicatorTween = nil
	end
	view.Indicator.Position = UDim2.new()
	if st.Status == "Offer" or st.Status == "Ready" then
		local tween = TweenService:Create(view.Indicator, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromOffset(0, -8) })
		tween:Play()
		view.IndicatorTween = tween
	end
end

local function attachModel(npcId: string, model: Model)
	local view = npcViews[npcId]
	if not view then
		return
	end
	view.Model = model
	local root = model.PrimaryPart or model:FindFirstChild("Root")
	if root and root:IsA("BasePart") then
		view.Home = root.CFrame
		local _, yaw = root.CFrame:ToOrientation()
		view.Yaw = yaw
	end
	view.Billboard.Adornee = model:FindFirstChild("Head") or root
	view.Billboard.Enabled = true
end

local function detachModel(npcId: string)
	local view = npcViews[npcId]
	if view then
		view.Model = nil
		view.Billboard.Adornee = nil
		view.Billboard.Enabled = false
	end
end

local function watchNpcs(playerGui: PlayerGui)
	for _, npcId in AdventureLogic.npcOrder() do
		npcViews[npcId] = buildNpcBillboard(npcId, playerGui)
		refreshIndicator(npcId)
	end
	task.spawn(function()
		local folder = Workspace:WaitForChild("Npcs", 60)
		if not folder then
			return
		end
		local function added(child: Instance)
			if child:IsA("Model") and npcViews[child.Name] then
				-- Con streaming el modelo llega entero (Atomic); su raíz puede tardar un instante.
				if not child.PrimaryPart then
					child:WaitForChild("Root", 5)
				end
				attachModel(child.Name, child)
			end
		end
		for _, child in folder:GetChildren() do
			task.spawn(added, child)
		end
		folder.ChildAdded:Connect(added)
		folder.ChildRemoved:Connect(function(child)
			if npcViews[child.Name] and npcViews[child.Name].Model == child then
				detachModel(child.Name)
			end
		end)
	end)
end

local function angleLerp(from: number, to: number, alpha: number): number
	local delta = (to - from + math.pi) % (2 * math.pi) - math.pi
	return from + delta * alpha
end

local function animate(dt: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local me = if root and root:IsA("BasePart") then root.Position else nil
	local camera = Workspace.CurrentCamera
	local clock = os.clock()
	for _, view in npcViews do
		local model = view.Model
		if model and model.Parent and view.Home and view.Yaw then
			local home = view.Home
			if camera and (camera.CFrame.Position - home.Position).Magnitude < ANIMATE_DISTANCE then
				local _, homeYaw = home:ToOrientation()
				local target = homeYaw
				if me then
					local offset = Vector3.new(me.X - home.Position.X, 0, me.Z - home.Position.Z)
					if offset.Magnitude < FACE_DISTANCE and offset.Magnitude > 0.5 then
						target = math.atan2(-offset.X, -offset.Z)
					end
				end
				view.Yaw = angleLerp(view.Yaw, target, math.clamp(dt * 5, 0, 1))
				local bob = math.sin(clock * 2.2) * 0.05
				model:PivotTo(CFrame.new(home.Position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, view.Yaw, 0))
			end
		end
	end
	for _, visual in itemVisuals do
		local spin = CFrame.Angles(0, clock * 1.6 + visual.Phase, 0)
		visual.Model:PivotTo(CFrame.new(visual.Base + Vector3.new(0, math.sin(clock * 2 + visual.Phase) * 0.35, 0)) * spin)
	end
end

-- Controlador ------------------------------------------------------------------------------------

function AdventureController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local requestRemote = remotes:WaitForChild(Constants.Remotes.RequestAdventure) :: RemoteEvent
	local stateRemote = remotes:WaitForChild(Constants.Remotes.AdventureState) :: RemoteEvent
	local dialogRemote = remotes:WaitForChild(Constants.Remotes.AdventureDialog) :: RemoteEvent
	local actionRemote = remotes:WaitForChild(Constants.Remotes.AdventureAction) :: RemoteEvent
	local resultRemote = remotes:WaitForChild(Constants.Remotes.AdventureResult) :: RemoteEvent

	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	local existing = playerGui:FindFirstChild("AdventureHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "AdventureHud",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local dialog = buildDialog(screenGui)
	local amulets = buildAmuletPanel(screenGui)
	local tracker = buildTracker()
	screenGui.Parent = playerGui
	local celebration = buildCelebration(playerGui)

	local localFolder = Workspace:FindFirstChild("AdventureItemsLocal")
	if localFolder then
		localFolder:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "AdventureItemsLocal"
	folder.Parent = Workspace
	itemsFolder = folder

	watchNpcs(playerGui)

	-- Azulejo del menú y línea de estado con las bendiciones activas.
	local menuEntry = MenuBar.add({
		Id = "Amulets",
		Order = 4,
		Icon = "🧿",
		Label = "Amuletos",
		Key = "G",
		Color = Color3.fromRGB(190, 130, 255),
		Panels = { AMULET_PANEL },
		OnActivate = function()
			PanelManager.toggle(AMULET_PANEL)
		end,
	})
	local timersLine = MenuBar.status("Blessings", 2)
	timersLine.TextColor3 = THEME.Gold

	-- Diseño: el diálogo abajo al centro; el seguimiento en su columna de HudDock.
	local renderTracker: () -> ()
	local function place()
		local size = screenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local scale = UiKit.computeScale(size)
		dialog.Scale.Scale = math.min(scale, (size.X - 24) / DIALOG_SIZE.X)
		tracker.Scale.Scale = scale
		celebration.Scale.Scale = math.clamp(math.min(size.X / 1280, size.Y / 720) * 1.1, 0.6, 1.3)
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()
	-- Si cambia el diseño (o sube/baja lo que hay encima), cambian las filas que caben.
	local relayoutQueued = false
	local function queueTrackerRender()
		if relayoutQueued then
			return
		end
		relayoutQueued = true
		task.defer(function()
			relayoutQueued = false
			if renderTracker then
				renderTracker()
			end
		end)
	end
	HudDock.Changed:Connect(function()
		place()
		local column = HudDock.trackerColumn()
		if tracker.Frame.Parent ~= HudDock.column(column) then
			HudDock.attach(column, tracker.Frame, 20)
		end
		queueTrackerRender()
	end)
	local lastTop = -1
	tracker.Frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		local top = math.floor(tracker.Frame.AbsolutePosition.Y)
		if math.abs(top - lastTop) >= 4 then
			lastTop = top
			queueTrackerRender()
		end
	end)

	-- Avisos breves (pila común) -------------------------------------------------------------
	-- `key`: los avisos del mismo progreso se sustituyen en lugar de apilarse.
	local function notify(text: string, color: Color3?, key: string?)
		Toasts.show(text, { Color = color or THEME.Text, Key = key })
	end

	-- Conversación ----------------------------------------------------------------------------
	local dialogNpc: string? = nil
	local pages: { any } = {}
	local typingToken = 0
	local pending = false

	local function typeText(text: string)
		typingToken += 1
		local token = typingToken
		dialog.Body.Text = text
		dialog.Body.MaxVisibleGraphemes = 0
		local total = utf8.len(text) or #text
		task.spawn(function()
			local shown = 0
			while shown < total and typingToken == token do
				shown = math.min(total, shown + math.max(1, math.floor(TYPE_SPEED * RunService.RenderStepped:Wait())))
				dialog.Body.MaxVisibleGraphemes = shown
			end
			if typingToken == token then
				dialog.Body.MaxVisibleGraphemes = -1
			end
		end)
	end

	local function setButton(button: TextButton, text: string?, color: Color3?)
		button.Visible = text ~= nil
		if text then
			button.Text = text
			if color then
				button.BackgroundColor3 = color
			end
		end
	end

	local function renderDialog(retype: boolean)
		local npcId = dialogNpc
		if not npcId then
			return
		end
		local npc = AdventureConfig.Npcs[npcId]
		dialog.Name.Text = npc.DisplayName
		dialog.PortraitText.Text = string.sub(npc.DisplayName, 1, 1)
		dialog.Portrait.BackgroundColor3 = npc.Look.Primary
		dialog.PortraitStroke.Color = npc.Look.Accent
		local page = pages[1]
		dialog.Feedback.Text = ""
		dialog.PrimaryShimmer(false)
		if page and page.Kind == "Delivery" then
			local giver = AdventureConfig.Npcs[page.Giver]
			local step = AdventureLogic.stepOf(page.Giver, npcState(page.Giver).Step)
			dialog.Title.Text = ("Encargo de %s"):format(giver.DisplayName)
			if retype then
				typeText(page.Text)
			end
			dialog.Objective.Visible = true
			dialog.ObjectiveStroke.Color = COLORS.Ready
			dialog.ObjectiveText.Text = ("✓ Entregado: %s"):format(if step then step.Title else "encargo")
			dialog.ObjectiveText.TextColor3 = COLORS.Ready
			dialog.Reward.Text = ("Vuelve con %s para la recompensa."):format(giver.DisplayName)
			setButton(dialog.Primary, "Seguir", THEME.Buy)
			setButton(dialog.Secondary, nil)
			return
		end
		local st = npcState(npcId)
		local step = AdventureLogic.stepOf(npcId, st.Step)
		dialog.ObjectiveText.TextColor3 = THEME.Text
		dialog.ObjectiveStroke.Color = THEME.Stroke
		if st.Status == "Done" or not step then
			dialog.Title.Text = npc.Title .. " · historia completada ✓"
			if retype then
				typeText(npc.Greeting)
			end
			dialog.Objective.Visible = false
			setButton(dialog.Primary, "Adiós", THEME.Secondary)
			setButton(dialog.Secondary, nil)
			return
		end
		dialog.Title.Text = ("%s · misión %d de %d: %s"):format(npc.Title, st.Step, st.Steps, step.Title)
		dialog.Objective.Visible = true
		dialog.Reward.Text = rewardText(npcId, st)
		if st.Status == "Offer" then
			if retype then
				typeText(step.Offer)
			end
			dialog.ObjectiveText.Text = "🎯 " .. step.Objective .. (if step.Goal.Type ~= "Talk" then (" (%d)"):format(st.Target) else "")
			setButton(dialog.Primary, "Aceptar", THEME.Buy)
			setButton(dialog.Secondary, "Ahora no", THEME.Secondary)
			dialog.PrimaryShimmer(true)
		elseif st.Status == "Ready" then
			if retype then
				typeText(step.Ready)
			end
			dialog.ObjectiveText.Text = "✓ " .. objectiveText(npcId, st)
			dialog.ObjectiveText.TextColor3 = COLORS.Ready
			dialog.ObjectiveStroke.Color = COLORS.Ready
			setButton(dialog.Primary, "Entregar ✓", THEME.Buy)
			setButton(dialog.Secondary, nil)
			dialog.PrimaryShimmer(true)
		else
			if retype then
				typeText(step.Active)
			end
			dialog.ObjectiveText.Text = "🎯 " .. objectiveText(npcId, st)
			setButton(dialog.Primary, "¡Voy!", THEME.Secondary)
			setButton(dialog.Secondary, nil)
		end
	end

	local function openDialog(npcId: string, deliveredFor: string?)
		dialogNpc = npcId
		pages = {}
		if deliveredFor and AdventureConfig.Npcs[deliveredFor] then
			local giverState = npcState(deliveredFor)
			local step = AdventureLogic.stepOf(deliveredFor, giverState.Step)
			if step and step.Delivery then
				table.insert(pages, { Kind = "Delivery", Giver = deliveredFor, Text = step.Delivery })
			end
		end
		PanelManager.open(DIALOG_PANEL)
		renderDialog(true)
		playSound(AdventureConfig.Sounds.Talk)
	end

	local function closeDialog()
		PanelManager.close(DIALOG_PANEL)
	end

	PanelManager.register(DIALOG_PANEL, dialog.Panel, {
		OnClose = function()
			dialogNpc = nil
			typingToken += 1
		end,
	})

	dialog.Skip.Activated:Connect(function()
		typingToken += 1
		dialog.Body.MaxVisibleGraphemes = -1
	end)
	dialog.Close.Activated:Connect(closeDialog)
	dialog.Secondary.Activated:Connect(closeDialog)
	dialog.Primary.Activated:Connect(function()
		local npcId = dialogNpc
		if not npcId or pending then
			return
		end
		if pages[1] then
			table.remove(pages, 1)
			renderDialog(true)
			return
		end
		local st = npcState(npcId)
		local action = if st.Status == "Offer" then "Accept" elseif st.Status == "Ready" then "TurnIn" else nil
		if not action then
			closeDialog()
			return
		end
		pending = true
		actionRemote:FireServer(action, npcId)
		task.delay(3, function()
			pending = false -- sin respuesta (límite de frecuencia): se puede reintentar
		end)
	end)

	dialogRemote.OnClientEvent:Connect(function(npcId: any, deliveredFor: any)
		if typeof(npcId) == "string" and AdventureConfig.Npcs[npcId] then
			openDialog(npcId, if typeof(deliveredFor) == "string" then deliveredFor else nil)
		end
	end)

	-- Panel de amuletos -------------------------------------------------------------------------
	local function feedbackAmulets(text: string, color: Color3)
		amulets.Feedback.Text = text
		amulets.Feedback.TextColor3 = color
		task.delay(3, function()
			if amulets.Feedback.Text == text then
				amulets.Feedback.Text = ""
			end
		end)
	end

	local function clearList()
		for _, child in amulets.List:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function smallButton(parent: Instance, text: string, color: Color3, onClick: () -> ()): TextButton
		local button = UiKit.button(parent, "Action", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(112, 36),
			BackgroundColor3 = color,
			TextSize = 16,
			Text = text,
		})
		button.Activated:Connect(onClick)
		return button
	end

	local timerLabels: { [string]: TextLabel } = {}
	local function blessingText(blessingId: string, now: number): (string, boolean)
		local blessing = AdventureConfig.Blessings[blessingId]
		local expires = state.Active and state.Active[blessingId]
		if expires and expires > now then
			return ("%s · activa: %s"):format(blessing.Description, clockText(expires - now)), true
		end
		return ("%s durante %d min"):format(blessing.Description, blessing.Duration // 60), false
	end

	local function renderAmulets()
		clearList()
		timerLabels = {}
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		local equipped = state.Equipped or { "", "" }
		local slots = state.Slots or 1
		local owned = {}
		for _, amuletId in state.Amulets or {} do
			owned[amuletId] = true
		end
		local giverOf = {}
		for npcId, npc in AdventureConfig.Npcs do
			if npc.Amulet then
				giverOf[npc.Amulet] = npcId
			end
		end

		-- Ranuras
		sectionTitle(amulets.List, "Amuletos puestos", nextOrder())
		local slotRow = UiKit.create("Frame", { Name = "Slots", Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1, LayoutOrder = nextOrder() }, amulets.List)
		UiKit.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, slotRow)
		for slot = 1, AdventureConfig.MaxSlots do
			local card = UiKit.create("Frame", { Name = "Slot" .. slot, Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = THEME.Inset, BackgroundTransparency = 0.2, LayoutOrder = slot }, slotRow)
			UiKit.corner(card, 12)
			local amulet = AdventureConfig.Amulets[equipped[slot] or ""]
			local open = slot <= slots
			UiKit.stroke(card, if amulet then amulet.Color else THEME.Stroke, if amulet then 2 else 1, if amulet then 0 else 0.5)
			UiKit.text(card, "Label", {
				Position = UDim2.fromOffset(12, 6),
				Size = UDim2.new(1, -100, 0, 28),
				Font = FONTS.Display,
				TextSize = 18,
				TextColor3 = if open then THEME.Text else THEME.Muted,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = if amulet then ("%s %s"):format(amulet.Icon, amulet.DisplayName) elseif open then ("Ranura %d: vacía"):format(slot) else ("🔒 Ranura %d"):format(slot),
			})
			UiKit.text(card, "Hint", {
				Position = UDim2.fromOffset(12, 34),
				Size = UDim2.new(1, -100, 0, 20),
				Font = FONTS.Light,
				TextSize = 13,
				TextColor3 = THEME.Muted,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = if amulet then amulet.Description elseif open then "Elige un amuleto abajo" else "Termina las 4 historias",
			})
			if amulet then
				local remove = smallButton(card, "Quitar", THEME.Secondary, function()
					actionRemote:FireServer("Unequip", slot)
				end)
				remove.Size = UDim2.fromOffset(80, 32)
			end
		end

		-- Amuletos
		sectionTitle(amulets.List, "Colección", nextOrder())
		for _, amuletId in AdventureLogic.amuletOrder() do
			local amulet = AdventureConfig.Amulets[amuletId]
			local row = rowFrame(amulets.List, amuletId, 62, nextOrder())
			local has = owned[amuletId] == true
			local isOn = table.find(equipped, amuletId) ~= nil
			UiKit.stroke(row, if isOn then amulet.Color else THEME.Stroke, if isOn then 2 else 1, if isOn then 0 else 0.6)
			UiKit.text(row, "Icon", {
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.fromOffset(44, 62),
				Font = FONTS.Display,
				TextSize = 32,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTransparency = if has then 0 else 0.6,
				Text = amulet.Icon,
			})
			UiKit.text(row, "Name", {
				Position = UDim2.fromOffset(60, 8),
				Size = UDim2.new(1, -190, 0, 22),
				Font = FONTS.Display,
				TextSize = 18,
				TextColor3 = if has then amulet.Color else THEME.Muted,
				Text = amulet.DisplayName,
			})
			local giver = giverOf[amuletId] and AdventureConfig.Npcs[giverOf[amuletId]]
			UiKit.text(row, "Description", {
				Position = UDim2.fromOffset(60, 32),
				Size = UDim2.new(1, -190, 0, 20),
				Font = FONTS.Light,
				TextSize = 14,
				TextColor3 = THEME.Muted,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = if has then amulet.Description else ("🔒 Termina la historia de %s"):format(if giver then giver.DisplayName else "un personaje"),
			})
			if has then
				if isOn then
					local label = smallButton(row, "Puesto ✓", THEME.Inset, function() end)
					UiKit.setDisabled(label, true)
				else
					smallButton(row, "Ponerme", THEME.Buy, function()
						actionRemote:FireServer("Equip", amuletId)
					end)
				end
			end
		end

		-- Bendiciones
		sectionTitle(amulets.List, "Bendiciones", nextOrder())
		local now = serverNow()
		for _, blessingId in AdventureLogic.blessingOrder() do
			local blessing = AdventureConfig.Blessings[blessingId]
			local row = rowFrame(amulets.List, blessingId, 62, nextOrder())
			local count = state.Blessings and state.Blessings[blessingId] or 0
			local expires = state.Active and state.Active[blessingId]
			local active = expires and expires > now
			UiKit.stroke(row, if active then blessing.Color else THEME.Stroke, if active then 2 else 1, if active then 0 else 0.6)
			UiKit.text(row, "Icon", {
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.fromOffset(44, 62),
				Font = FONTS.Display,
				TextSize = 32,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTransparency = if count > 0 or active then 0 else 0.6,
				Text = blessing.Icon,
			})
			UiKit.text(row, "Name", {
				Position = UDim2.fromOffset(60, 8),
				Size = UDim2.new(1, -190, 0, 22),
				Font = FONTS.Display,
				TextSize = 18,
				TextColor3 = blessing.Color,
				Text = ("%s  ×%d"):format(blessing.DisplayName, count),
			})
			timerLabels[blessingId] = UiKit.text(row, "Description", {
				Position = UDim2.fromOffset(60, 32),
				Size = UDim2.new(1, -190, 0, 20),
				Font = FONTS.Light,
				TextSize = 14,
				TextColor3 = if active then THEME.BuyHighlight else THEME.Muted,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = (blessingText(blessingId, now)),
			})
			local use = smallButton(row, if active then "Alargar" else "Usar", if count > 0 then THEME.Buy else THEME.Disabled, function()
				actionRemote:FireServer("UseBlessing", blessingId)
			end)
			UiKit.setDisabled(use, count <= 0)
		end

		-- Historias
		sectionTitle(amulets.List, "Historias", nextOrder())
		for _, npcId in AdventureLogic.npcOrder() do
			local npc = AdventureConfig.Npcs[npcId]
			local st = npcState(npcId)
			local row = rowFrame(amulets.List, npcId, 58, nextOrder())
			local done = if st.Status == "Done" then st.Steps else st.Step - 1
			local dots = string.rep("●", done) .. string.rep("○", st.Steps - done)
			UiKit.text(row, "Name", {
				Position = UDim2.fromOffset(14, 6),
				Size = UDim2.new(1, -150, 0, 22),
				Font = FONTS.Display,
				TextSize = 17,
				Text = fullName(npc),
			})
			UiKit.text(row, "Where", {
				Position = UDim2.fromOffset(14, 30),
				Size = UDim2.new(1, -150, 0, 20),
				Font = FONTS.Light,
				TextSize = 13,
				TextColor3 = THEME.Muted,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = if st.Status == "Done" then "Historia completada ✓" elseif st.Status == "Offer" then "📍 " .. npc.Where else objectiveText(npcId, st),
			})
			UiKit.text(row, "Dots", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -14, 0.5, 0),
				Size = UDim2.fromOffset(120, 30),
				Font = FONTS.Display,
				TextSize = 20,
				TextColor3 = if st.Status == "Done" then COLORS.Ready else THEME.Gold,
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = dots,
			})
		end
	end

	PanelManager.register(AMULET_PANEL, amulets.Panel, {
		OnOpen = function()
			requestRemote:FireServer()
			renderAmulets()
		end,
	})
	UiKit.bindModalLayout(screenGui, amulets.Scale, AMULET_PANEL_SIZE, function(position)
		PanelManager.setBasePosition(AMULET_PANEL, position)
	end)
	amulets.Close.Activated:Connect(function()
		PanelManager.close(AMULET_PANEL)
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.G then
			PanelManager.toggle(AMULET_PANEL)
		end
	end)
	PanelManager.Changed:Connect(function(openPanel: string?)
		if openPanel == AMULET_PANEL then
			menuEntry.shimmer(false)
		end
	end)

	-- Celebración ---------------------------------------------------------------------------------
	local celebrationAmulet: string? = nil
	local function celebrate(amuletId: string)
		local amulet = AdventureConfig.Amulets[amuletId]
		if not amulet then
			return
		end
		celebrationAmulet = amuletId
		celebration.Icon.Text = amulet.Icon
		celebration.ItemName.Text = amulet.DisplayName
		celebration.ItemName.TextColor3 = amulet.Color
		celebration.Description.Text = amulet.Description
		if celebration.Stroke then
			celebration.Stroke.Color = amulet.Color
			celebration.Stroke.Transparency = 0
			celebration.Stroke.Thickness = 3
		end
		local isOn = table.find(state.Equipped or {}, amuletId) ~= nil
		celebration.Equip.Visible = not isOn
		celebration.Ok.Position = if isOn then UDim2.new(0.5, 0, 1, -20) else UDim2.new(0.5, 84, 1, -20)
		celebration.Gui.Enabled = true
		local scale = celebration.Card:FindFirstChildOfClass("UIScale")
		if scale then
			local target = scale.Scale
			scale.Scale = target * 0.6
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
		end
		playSound(AdventureConfig.Sounds.Reward)
	end
	celebration.Ok.Activated:Connect(function()
		celebration.Gui.Enabled = false
	end)
	celebration.Equip.Activated:Connect(function()
		celebration.Gui.Enabled = false
		if celebrationAmulet then
			actionRemote:FireServer("Equip", celebrationAmulet)
		end
	end)

	-- Seguimiento -----------------------------------------------------------------------------------
	renderTracker = function()
		for _, row in tracker.Rows do
			row:Destroy()
		end
		tracker.Rows = {}
		if not state.Ready then
			return
		end
		-- Primero las que ya se pueden entregar; luego las demás en curso.
		local entries = {}
		for index, npcId in AdventureLogic.npcOrder() do
			local st = npcState(npcId)
			if st.Status == "Ready" or st.Status == "Active" then
				table.insert(entries, { Id = npcId, State = st, Rank = (if st.Status == "Ready" then 0 else 100) + index })
			end
		end
		table.sort(entries, function(a, b)
			return a.Rank < b.Rank
		end)
		-- Filas que caben hasta el borde de la columna (encima del combate o del joystick).
		local column = HudDock.trackerColumn()
		local fit = HudLayout.trackerRows(tracker.Frame.AbsolutePosition.Y, HudDock.bottom(column), tracker.Scale.Scale, #entries)
		local shown = if fit < #entries then math.max(0, fit - 1) else #entries
		for order = 1, shown do
			local npcId = entries[order].Id
			local st = entries[order].State
			local npc = AdventureConfig.Npcs[npcId]
			local step = AdventureLogic.stepOf(npcId, st.Step)
			local ready = st.Status == "Ready"
			local row = UiKit.create("Frame", {
				Name = npcId,
				Size = UDim2.fromOffset(TRACKER_WIDTH, TRACKER_ROW),
				BackgroundColor3 = THEME.Panel,
				BackgroundTransparency = 0.25,
				LayoutOrder = order,
			}, tracker.Frame)
			UiKit.corner(row, 10)
			UiKit.stroke(row, if ready then COLORS.Ready else THEME.Stroke, if ready then 2 else 1, if ready then 0 else 0.5)
			UiKit.text(row, "Who", {
				Position = UDim2.fromOffset(10, 4),
				Size = UDim2.new(1, -20, 0, 20),
				Font = FONTS.Display,
				TextSize = 15,
				TextColor3 = if ready then COLORS.Ready else THEME.Gold,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = ("%s · %s"):format(npc.DisplayName, if step then step.Title else ""),
			})
			UiKit.text(row, "Goal", {
				Position = UDim2.fromOffset(10, 25),
				Size = UDim2.new(1, -20, 0, 20),
				Font = FONTS.Body,
				TextSize = 13,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = if ready then ("✓ ¡Lista! Vuelve con %s"):format(npc.DisplayName) else objectiveText(npcId, st),
			})
			table.insert(tracker.Rows, row)
		end
		-- Las que no caben se resumen en una línea (el panel de amuletos las lista todas).
		local hidden = #entries - shown
		if hidden > 0 and fit > 0 then
			local more = UiKit.text(tracker.Frame, "More", {
				Size = UDim2.fromOffset(TRACKER_WIDTH, 22),
				Font = FONTS.Body,
				TextSize = 14,
				TextColor3 = THEME.Muted,
				TextStrokeTransparency = 0.5,
				TextXAlignment = if column == "Right" then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
				Text = ("+%d %s en curso"):format(hidden, if hidden == 1 then "misión" else "misiones"),
				LayoutOrder = shown + 1,
			})
			table.insert(tracker.Rows, more)
		end
	end

	local function refreshSide()
		local unused = 0
		for _, count in state.Blessings or {} do
			unused += count
		end
		menuEntry.setBadge(if unused > 0 then tostring(unused) else nil)
	end

	-- Tiempos de las bendiciones activas (cada medio segundo).
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = serverNow()
			local parts = {}
			for _, blessingId in AdventureLogic.blessingOrder() do
				local expires = state.Active and state.Active[blessingId]
				if expires and expires > now then
					table.insert(parts, ("%s %s"):format(AdventureConfig.Blessings[blessingId].Icon, clockText(expires - now)))
				end
			end
			local text = table.concat(parts, "   ")
			if timersLine.Text ~= text then
				timersLine.Text = text
			end
			if PanelManager.isOpen(AMULET_PANEL) then
				for blessingId, label in timerLabels do
					if label.Parent then
						local text, active = blessingText(blessingId, now)
						label.Text = text
						label.TextColor3 = if active then THEME.BuyHighlight else THEME.Muted
					end
				end
			end
		end
	end)

	-- Estado del servidor ------------------------------------------------------------------------
	local function handleNotices(notices: { any })
		for _, notice in notices do
			if notice.Type == "Found" then
				local item = AdventureConfig.Items[notice.Item]
				local kind = item and AdventureConfig.ItemKinds[item.Kind]
				if kind then
					playSound(AdventureConfig.Sounds.Collect)
				end
			elseif notice.Type == "Progress" then
				local npc = AdventureConfig.Npcs[notice.Npc]
				local st = npcState(notice.Npc)
				local step = AdventureLogic.stepOf(notice.Npc, st.Step)
				if npc and step then
					if notice.Ready then
						notify(("✓ ¡%s lista! Vuelve con %s"):format(step.Title, npc.DisplayName), COLORS.Ready)
						playSound(AdventureConfig.Sounds.Accept)
					elseif step.Goal.Type == "Collect" then
						local kind = AdventureConfig.ItemKinds[AdventureConfig.Items[step.Goal.Items[1]].Kind]
						notify(("%s %s %d/%d"):format(kind.Icon, kind.DisplayName, notice.Progress, notice.Target), kind.Glow, "Progress_" .. notice.Npc)
					elseif step.Goal.Type == "Kill" then
						local enemy = EnemyConfig.Types[step.Goal.Enemies[1]]
						notify(("⚔ %s %d/%d"):format(if enemy then enemy.DisplayName else step.Title, notice.Progress, notice.Target), THEME.Text, "Progress_" .. notice.Npc)
					end
				end
			elseif notice.Type == "Reward" then
				local parts = {}
				if (notice.Energy or 0) > 0 then
					table.insert(parts, ("+%s ⚡"):format(formatNumber(notice.Energy)))
				end
				local blessing = notice.Blessing and AdventureConfig.Blessings[notice.Blessing]
				if blessing then
					table.insert(parts, ("+1 %s %s"):format(blessing.Icon, blessing.DisplayName))
				end
				notify("🎁 " .. table.concat(parts, "  ·  "), THEME.Gold)
				if blessing then
					menuEntry.shimmer(true)
				end
				if notice.Amulet then
					celebrate(notice.Amulet)
				end
				if notice.SlotOpened then
					task.delay(3, function()
						notify("🧿 ¡Historias del Bosque y del Valle completas! Se abrió la 2.ª ranura de amuleto", THEME.Gold)
					end)
				elseif notice.AllDone and notice.Finished then
					task.delay(3, function()
						notify("🏆 ¡Completaste todas las historias!", THEME.Gold)
					end)
				end
				playSound(AdventureConfig.Sounds.Reward)
			elseif notice.Type == "BlessingEnded" then
				notify("Una bendición terminó", THEME.Muted)
			end
		end
	end

	stateRemote.OnClientEvent:Connect(function(newState: any)
		if typeof(newState) ~= "table" then
			return
		end
		if not newState.Ready then
			state = { Ready = false }
			return
		end
		state = newState
		-- Un objeto que deja de estar pendiente por haberse encontrado estalla; si deja de
		-- estarlo por otro motivo, simplemente desaparece.
		local found = {}
		for _, st in state.Npcs or {} do
			for _, itemId in st.Found or {} do
				found[itemId] = true
			end
		end
		for _, notice in state.Notices or {} do
			if notice.Type == "Found" then
				found[notice.Item] = true
			end
		end
		syncItems(state.Pending or {}, found)
		for npcId in npcViews do
			refreshIndicator(npcId)
		end
		renderTracker()
		refreshSide()
		if dialogNpc then
			renderDialog(false)
		end
		if PanelManager.isOpen(AMULET_PANEL) then
			renderAmulets()
		end
		handleNotices(state.Notices or {})
	end)

	resultRemote.OnClientEvent:Connect(function(success: any, code: any, action: any, detail: any)
		pending = false
		if success then
			if action == "Accept" and typeof(detail) == "table" and dialogNpc == detail.Npc then
				local st = npcState(detail.Npc)
				local step = AdventureLogic.stepOf(detail.Npc, st.Step)
				playSound(AdventureConfig.Sounds.Accept)
				if step then
					notify(("📜 Misión aceptada: %s"):format(step.Title), THEME.Gold)
				end
				renderDialog(true)
			elseif action == "TurnIn" and typeof(detail) == "table" and dialogNpc == detail.Npc then
				renderDialog(true)
			elseif action == "Equip" then
				local amulet = typeof(detail) == "table" and AdventureConfig.Amulets[detail.Amulet]
				feedbackAmulets(if amulet then ("Llevas puesto: %s %s"):format(amulet.Icon, amulet.DisplayName) else "Amuleto puesto", THEME.BuyHighlight)
			elseif action == "UseBlessing" then
				local blessing = typeof(detail) == "table" and AdventureConfig.Blessings[detail.Blessing]
				if blessing then
					notify(("%s ¡%s activa!"):format(blessing.Icon, blessing.DisplayName), blessing.Color)
				end
				playSound(AdventureConfig.Sounds.Blessing)
			end
		else
			local message = MESSAGES[code] or "Esa acción no está disponible."
			if dialogNpc and (action == "Accept" or action == "TurnIn") then
				dialog.Feedback.Text = message
			elseif PanelManager.isOpen(AMULET_PANEL) then
				feedbackAmulets(message, THEME.Error)
			else
				notify(message, THEME.Error)
			end
		end
	end)

	-- Cerrar la conversación al alejarse; girar personajes y mover objetos.
	RunService.RenderStepped:Connect(function(dt)
		animate(dt)
		local npcId = dialogNpc
		if npcId then
			local view = npcViews[npcId]
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if view and view.Home and root and root:IsA("BasePart") and (root.Position - view.Home.Position).Magnitude > CLOSE_DISTANCE then
				closeDialog()
			end
		end
	end)

	-- Las posiciones de los objetos pueden llegar después que el estado.
	local info = ReplicatedStorage:WaitForChild("AdventureWorld", 30)
	if info then
		info.AttributeChanged:Connect(function()
			syncItems(state.Pending or {}, {})
		end)
	end
	requestRemote:FireServer()
	-- Por si el servidor aún cargaba los datos: un segundo intento.
	task.delay(6, function()
		if not state.Ready then
			requestRemote:FireServer()
		end
	end)
end

return AdventureController
