-- AdventureController · Gui: constantes, textos de misiones y construcción del diálogo, el panel de amuletos, el seguimiento y la celebración.
-- Parte de AdventureController (ver AdventureController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local AdventureConfig = require(Shared.Config.AdventureConfig)
local AdventureLogic = require(Shared.AdventureLogic)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)
local HudDock = require(script.Parent.Parent.Parent.UI.HudDock)
local HudLayout = require(script.Parent.Parent.Parent.UI.HudLayout)

local ctx: any -- tabla de estado compartida (la crea AdventureController/init.luau)

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


local player = Players.LocalPlayer

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
	return ctx.state.Ready and ctx.state.Npcs and ctx.state.Npcs[npcId] or AdventureLogic.state(nil, npcId)
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
		table.insert(parts, ("💰 %s"):format(formatNumber(st.Reward)))
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

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.AMULET_PANEL = AMULET_PANEL
	context.AMULET_PANEL_SIZE = AMULET_PANEL_SIZE
	context.ANIMATE_DISTANCE = ANIMATE_DISTANCE
	context.CLOSE_DISTANCE = CLOSE_DISTANCE
	context.COLORS = COLORS
	context.DIALOG_PANEL = DIALOG_PANEL
	context.DIALOG_SIZE = DIALOG_SIZE
	context.FACE_DISTANCE = FACE_DISTANCE
	context.FONTS = FONTS
	context.ITEM_FLOAT = ITEM_FLOAT
	context.MESSAGES = MESSAGES
	context.THEME = THEME
	context.TRACKER_ROW = TRACKER_ROW
	context.TRACKER_WIDTH = TRACKER_WIDTH
	context.TYPE_SPEED = TYPE_SPEED
	context.buildAmuletPanel = buildAmuletPanel
	context.buildCelebration = buildCelebration
	context.buildDialog = buildDialog
	context.buildTracker = buildTracker
	context.clockText = clockText
	context.fullName = fullName
	context.npcState = npcState
	context.objectiveText = objectiveText
	context.playSound = playSound
	context.player = player
	context.rewardText = rewardText
	context.rowFrame = rowFrame
	context.sectionTitle = sectionTitle
	context.serverNow = serverNow
end

function Part.link(context: any)
	-- (nada que enlazar)
end

return Part
