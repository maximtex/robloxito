-- WaveController · Gui: constantes, construcción del HUD de oleadas, modales de mejoras/resumen y cartel de racha.
-- Parte de WaveController (ver WaveController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WaveConfig = require(Shared.Config.WaveConfig)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)


local THEME = Theme.Colors
local FONTS = Theme.Fonts
local LAYOUT = Theme.Layout
local INK = Color3.fromRGB(43, 29, 63)
local ORANGE = Color3.fromRGB(255, 150, 60)
local BOSS_RED = Color3.fromRGB(240, 80, 96)
local CARD_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }
local CARD_ACTION = "RebirthWaveCards"
local CHOICE_ACTION = "RebirthWaveEndless"
local STREAK_MIN = 3 -- la racha se ve a partir de aquí
local STREAK_COLORS = {
	{ Min = 0, Color = Color3.fromRGB(255, 255, 255) },
	{ Min = 10, Color = Color3.fromRGB(255, 226, 92) },
	{ Min = 25, Color = Color3.fromRGB(255, 150, 60) },
	{ Min = 50, Color = Color3.fromRGB(255, 92, 120) },
	{ Min = 100, Color = Color3.fromRGB(196, 120, 255) },
}
local CLEAR_GREEN = Color3.fromRGB(150, 236, 120)
local ENDLESS_PURPLE = Color3.fromRGB(176, 120, 255)
local HEAL_PINK = Color3.fromRGB(255, 120, 160)


local player = Players.LocalPlayer

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function secondsLeft(endsAt: any): number
	if typeof(endsAt) ~= "number" or endsAt <= 0 then
		return 0
	end
	return math.max(0, math.ceil(endsAt - serverNow()))
end

-- Texto con contorno oscuro; `Stroke` (grosor del contorno) no es una propiedad del texto.
local function textLabel(parent: Instance, name: string, properties: { [string]: any }): TextLabel
	local clean = table.clone(properties)
	local stroke = clean.Stroke
	clean.Stroke = nil
	local label = UiKit.text(parent, name, clean)
	UiKit.outline(label, if type(stroke) == "number" then stroke else 2.5, INK)
	return label
end

-- Interfaz ------------------------------------------------------------------------------

local function buildHud()
	local playerGui = player:WaitForChild("PlayerGui")
	for _, name in { "WaveHud", "WaveModal" } do
		local existing = playerGui:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end
	local hud = UiKit.create("ScreenGui", {
		Name = "WaveHud",
		ResetOnSpawn = false,
		DisplayOrder = 3,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)

	-- Panel de la partida: en el hueco de la barra del jefe (bajo el tutorial y los avisos de
	-- arriba), con su mismo tamaño; la pila de avisos baja como con la barra del jefe.
	local panel, panelScale = UiKit.panel(hud, "WavePanel", Vector2.new(440, 54), Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 148))
	panel.Visible = false
	local title = textLabel(panel, "WaveTitle", {
		Position = UDim2.fromOffset(16, 5),
		Size = UDim2.new(1, -32, 0, 22),
		Font = FONTS.Display,
		TextSize = 19,
		Stroke = 2.5,
	})
	local subtitle = textLabel(panel, "WaveSubtitle", {
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.new(1, -32, 0, 20),
		Font = FONTS.Body,
		TextSize = 15,
		TextColor3 = THEME.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Stroke = 1.5,
	})
	local track = UiKit.create("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(16, 31),
		Size = UDim2.new(1, -32, 0, 13),
		BackgroundColor3 = THEME.Inset,
	}, panel)
	UiKit.corner(track, 6)
	local fill = UiKit.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = ORANGE,
	}, track)
	UiKit.corner(fill, 6)

	-- Anuncio grande (cuenta atrás, "OLEADA 4", "¡JEFE!")
	local announce = UiKit.text(hud, "WaveAnnounce", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.34),
		Size = UDim2.fromOffset(700, 90),
		Font = FONTS.Display,
		TextSize = 64,
		TextColor3 = THEME.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
	})
	local announceStroke = UiKit.outline(announce, 4, INK)
	announceStroke.Transparency = 1
	local announceScale = UiKit.create("UIScale", {}, announce)

	-- Consejo (partida de práctica): cartel abajo, encima de la fila del menú (placeHint)
	local hintBox = UiKit.create("Frame", {
		Name = "WaveHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(560, 64),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.15,
		Visible = false,
	}, hud)
	UiKit.corner(hintBox, 14)
	UiKit.stroke(hintBox, THEME.Gold, 3, 0)
	local hintText = textLabel(hintBox, "Text", {
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.new(1, -32, 1, -12),
		Font = FONTS.Display,
		TextSize = 22,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = 2,
	})
	local hintScale = UiKit.create("UIScale", {}, hintBox)

	hud.Parent = playerGui
	UiKit.bindScale(hud, { panelScale, hintScale })
	-- Mismo sitio que la barra del jefe (CombatController): bajo la tarjeta de energía.
	local function placePanel()
		local scale = UiKit.computeScale(hud.AbsoluteSize)
		panel.Position = UDim2.new(0.5, 0, 0, LAYOUT.Margin + LAYOUT.DiamondCardSize.Y * scale + 8)
	end
	hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(placePanel)
	UiKit.onScaleChanged(placePanel) -- ⚙️ tamaño de la interfaz
	placePanel()
	-- El consejo se apoya sobre la fila de abajo del menú (MenuBar: "BottomDock"), con
	-- hueco para el porcentaje de Renacer que asoma por encima; si no está, a 150 px del borde.
	local watchedDock: GuiObject? = nil
	local function placeHint()
		local menuGui = playerGui:FindFirstChild("MenuDockHud")
		local dock = menuGui and menuGui:FindFirstChild("BottomDock", true)
		if menuGui and menuGui:IsA("ScreenGui") and dock and dock:IsA("GuiObject") then
			if watchedDock ~= dock then
				watchedDock = dock
				dock:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeHint)
			end
			-- Distancia al borde de abajo (igual en los dos ScreenGui aunque uno ignore la barra
			-- de arriba de Roblox)
			local scale = UiKit.computeScale(hud.AbsoluteSize)
			local bottom = menuGui.AbsoluteSize.Y - dock.AbsolutePosition.Y + 34 * scale
			hintBox.Position = UDim2.new(0.5, 0, 1, -math.floor(bottom))
		else
			hintBox.Position = UDim2.new(0.5, 0, 1, -150)
		end
	end
	hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeHint)
	UiKit.onScaleChanged(placeHint) -- ⚙️ tamaño de la interfaz
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "MenuDockHud" then
			task.defer(placeHint)
		end
	end)
	placeHint()

	-- Ventanas: mejoras y resumen (por encima del resto del HUD)
	local modal = UiKit.create("ScreenGui", {
		Name = "WaveModal",
		ResetOnSpawn = false,
		DisplayOrder = 8, -- por encima de la pila de avisos (7)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)

	local cardPanel, cardScale = UiKit.panel(modal, "CardPanel", Vector2.new(660, 344), Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.54))
	cardPanel.Visible = false
	UiKit.text(cardPanel, "Title", {
		Position = UDim2.fromOffset(20, 10),
		Size = UDim2.new(1, -40, 0, 34),
		Font = FONTS.Display,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "✨ Elige una mejora",
	})
	local cardHelp = UiKit.text(cardPanel, "Help", {
		Position = UDim2.fromOffset(20, 44),
		Size = UDim2.new(1, -40, 0, 22),
		Font = FONTS.Body,
		TextSize = 17,
		TextColor3 = THEME.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "Haz clic o pulsa 1, 2 o 3 · dura toda la partida",
	})
	local cardTimer = UiKit.create("Frame", {
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(1, -40, 0, 10),
		BackgroundColor3 = THEME.Inset,
	}, cardPanel)
	UiKit.corner(cardTimer, 5)
	local cardTimerFill = UiKit.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = THEME.Gold,
	}, cardTimer)
	UiKit.corner(cardTimerFill, 5)
	local cardButtons = {}
	for index = 1, WaveConfig.CardChoices do
		local button = UiKit.create("TextButton", {
			Name = "Card" .. index,
			Position = UDim2.fromOffset(20 + (index - 1) * 212, 72),
			Size = UDim2.fromOffset(196, 236),
			BackgroundColor3 = THEME.Inset,
			AutoButtonColor = true,
			Text = "",
		}, cardPanel)
		UiKit.corner(button, 12)
		local stroke = UiKit.stroke(button, THEME.Gold, 3, 0)
		UiKit.addStates(button)
		local icon = UiKit.text(button, "Icon", {
			Position = UDim2.fromOffset(0, 14),
			Size = UDim2.new(1, 0, 0, 60),
			Font = FONTS.Display,
			TextSize = 52,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local name = textLabel(button, "CardName", {
			Position = UDim2.fromOffset(10, 82),
			Size = UDim2.new(1, -20, 0, 28),
			Font = FONTS.Display,
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextScaled = false,
		})
		local body = UiKit.text(button, "CardText", {
			Position = UDim2.fromOffset(12, 114),
			Size = UDim2.new(1, -24, 0, 70),
			Font = FONTS.Body,
			TextSize = 16,
			TextWrapped = true,
			TextColor3 = THEME.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		local level = textLabel(button, "CardLevel", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 10, 1, -12),
			Size = UDim2.new(1, -20, 0, 22),
			Font = FONTS.Display,
			TextSize = 18,
			TextColor3 = THEME.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
			Stroke = 2,
		})
		local key = UiKit.create("Frame", {
			Name = "Key",
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = INK,
		}, button)
		UiKit.corner(key, 8)
		UiKit.text(key, "Hint", {
			Size = UDim2.fromScale(1, 1),
			Font = FONTS.Display,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = tostring(index),
		})
		-- Tapa de la carta: se ve boca abajo hasta que se voltea (openCards). Así nadie elige
		-- sin querer con el clic de atacar ni sin leer (pruebas con amigos).
		local cover = UiKit.create("Frame", {
			Name = "Cover",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = INK,
			ZIndex = 5,
			Visible = false,
		}, button)
		UiKit.corner(cover, 12)
		UiKit.stroke(cover, THEME.Gold, 3, 0.2)
		UiKit.text(cover, "Mark", {
			Size = UDim2.fromScale(1, 1),
			Font = FONTS.Display,
			TextSize = 64,
			TextColor3 = THEME.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "?",
			ZIndex = 6,
		})
		table.insert(cardButtons, { Button = button, Stroke = stroke, Icon = icon, Name = name, Body = body, Level = level, Cover = cover, Id = nil :: string? })
	end

	local resultPanel, resultScale = UiKit.panel(modal, "ResultPanel", Vector2.new(440, 320), Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5))
	resultPanel.Visible = false
	local resultTitle = UiKit.text(resultPanel, "Title", {
		Position = UDim2.fromOffset(20, 10),
		Size = UDim2.new(1, -40, 0, 34),
		Font = FONTS.Display,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local resultBody = textLabel(resultPanel, "Body", {
		Position = UDim2.fromOffset(24, 78),
		Size = UDim2.new(1, -48, 0, 160),
		Font = FONTS.Body,
		TextSize = 19,
		TextWrapped = true,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		Stroke = 1.5,
	})
	local resultClose = UiKit.button(resultPanel, "Continue", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(200, 46),
		TextSize = 22,
		Text = "Continuar",
	})

	-- Modo infinito: ¿seguir tras ganarle al jefe?
	local choicePanel, choiceScale = UiKit.panel(modal, "ChoicePanel", Vector2.new(480, 268), Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5))
	choicePanel.Visible = false
	UiKit.text(choicePanel, "Title", {
		Position = UDim2.fromOffset(20, 10),
		Size = UDim2.new(1, -40, 0, 34),
		Font = FONTS.Display,
		TextSize = 28,
		TextColor3 = THEME.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "🏆 ¡JEFE DERROTADO!",
	})
	local choiceBody = textLabel(choicePanel, "Body", {
		Position = UDim2.fromOffset(24, 52),
		Size = UDim2.new(1, -48, 0, 104),
		Font = FONTS.Body,
		TextSize = 18,
		TextWrapped = true,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		Stroke = 1.5,
	})
	local choiceGo = UiKit.button(choicePanel, "Go", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -8, 1, -34),
		Size = UDim2.fromOffset(200, 50),
		TextSize = 21,
		Text = "♾️ Seguir  [1]",
		BackgroundColor3 = THEME.BuyHighlight,
	})
	local choiceStop = UiKit.button(choicePanel, "Stop", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, 8, 1, -34),
		Size = UDim2.fromOffset(200, 50),
		TextSize = 21,
		Text = "🏁 Terminar  [2]",
		BackgroundColor3 = THEME.Inset,
	})
	local choiceTimer = UiKit.create("Frame", {
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(1, -40, 0, 10),
		BackgroundColor3 = THEME.Inset,
	}, choicePanel)
	UiKit.corner(choiceTimer, 5)
	local choiceTimerFill = UiKit.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = THEME.Gold,
	}, choiceTimer)
	UiKit.corner(choiceTimerFill, 5)

	modal.Parent = playerGui
	UiKit.bindScale(modal, { cardScale, resultScale, choiceScale })

	return {
		Panel = panel,
		Title = title,
		Subtitle = subtitle,
		Track = track,
		Fill = fill,
		Announce = announce,
		AnnounceStroke = announceStroke,
		AnnounceScale = announceScale,
		HintBox = hintBox,
		HintText = hintText,
		CardPanel = cardPanel,
		CardHelp = cardHelp,
		CardTimerFill = cardTimerFill,
		Cards = cardButtons,
		ResultPanel = resultPanel,
		ResultTitle = resultTitle,
		ResultBody = resultBody,
		ResultClose = resultClose,
		ChoicePanel = choicePanel,
		ChoiceBody = choiceBody,
		ChoiceGo = choiceGo,
		ChoiceStop = choiceStop,
		ChoiceTimerFill = choiceTimerFill,
	}
end

-- Racha sobre la cabeza (solo la ve este jugador).
local function buildStreak()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("StreakBillboard")
	if existing then
		existing:Destroy()
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StreakBillboard"
	billboard.Size = UDim2.fromOffset(170, 56)
	-- A la derecha del personaje (encima de la cabeza va el título del jugador).
	billboard.StudsOffset = Vector3.new(3.4, 1.2, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 120
	billboard.ResetOnSpawn = false
	billboard.Enabled = false
	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.Size = UDim2.new(1, 0, 0.66, 0)
	count.BackgroundTransparency = 1
	count.Font = FONTS.Display
	count.TextScaled = true
	count.TextColor3 = Color3.new(1, 1, 1)
	count.Parent = billboard
	local countStroke = Instance.new("UIStroke")
	countStroke.Color = INK
	countStroke.Thickness = 3
	countStroke.Parent = count
	local bonus = Instance.new("TextLabel")
	bonus.Name = "Bonus"
	bonus.Position = UDim2.fromScale(0, 0.64)
	bonus.Size = UDim2.new(1, 0, 0.36, 0)
	bonus.BackgroundTransparency = 1
	bonus.Font = FONTS.Display
	bonus.TextScaled = true
	bonus.TextColor3 = THEME.Gold
	bonus.Parent = billboard
	local bonusStroke = Instance.new("UIStroke")
	bonusStroke.Color = INK
	bonusStroke.Thickness = 2
	bonusStroke.Parent = bonus
	local scale = Instance.new("UIScale")
	scale.Parent = count
	billboard.Parent = playerGui
	return { Billboard = billboard, Count = count, Bonus = bonus, Scale = scale }
end

local function streakColor(count: number): Color3
	local color = STREAK_COLORS[1].Color
	for _, tier in STREAK_COLORS do
		if count >= tier.Min then
			color = tier.Color
		end
	end
	return color
end

-- Arranque ------------------------------------------------------------------------------

local Part = { Api = {} }

function Part.install(context: any)
	-- (esta parte no usa el estado compartido)
	context.BOSS_RED = BOSS_RED
	context.CARD_ACTION = CARD_ACTION
	context.CARD_KEYS = CARD_KEYS
	context.CHOICE_ACTION = CHOICE_ACTION
	context.CLEAR_GREEN = CLEAR_GREEN
	context.ENDLESS_PURPLE = ENDLESS_PURPLE
	context.HEAL_PINK = HEAL_PINK
	context.ORANGE = ORANGE
	context.STREAK_MIN = STREAK_MIN
	context.THEME = THEME
	context.buildHud = buildHud
	context.buildStreak = buildStreak
	context.player = player
	context.secondsLeft = secondsLeft
	context.serverNow = serverNow
	context.streakColor = streakColor
end

function Part.link(context: any)
	-- (nada que enlazar)
end

return Part
