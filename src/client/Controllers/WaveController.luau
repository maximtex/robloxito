-- Oleadas en el cliente (solo presentación; WaveService decide todo):
-- - Panel arriba al centro (en el hueco de la barra del jefe, bajo el tutorial) mientras
--   juegas una partida: oleada, enemigos que quedan y cuenta atrás. En la del jefe se
--   esconde y se ve la barra del jefe.
-- - Anuncios grandes en el centro: cuenta atrás, "OLEADA 4", "¡JEFE!".
-- - Consejos de la partida de práctica del tutorial ("Hint"), en un cartel abajo, justo
--   encima de la fila del menú: el centro queda libre para ver al personaje y los avisos.
-- - Las partidas son privadas: el servidor solo manda el estado de la tuya (y el altar
--   esconde su "Pulsa E" mientras juegas). Qué enemigos ves lo decide WaveVisibility.
-- - Mejoras: tres tarjetas para elegir (clic o teclas 1, 2, 3) con su tiempo.
-- - Resumen al terminar (victoria o caída): enemigos, 💎, 💰, orbes dorados, mejor racha y
--   tu récord en ese modo (aviso "Record" en cuanto lo superas).
-- - Modo infinito: al caer el jefe, ventana para elegir si sigues ("Endless", true/false);
--   después las oleadas se cuentan sin tope ("♾️ OLEADA 14").
-- - Racha: contador "x12" sobre tu cabeza mientras matas sin parar (atributos Streak y
--   StreakUntil de EnemyService), con el multiplicador de botín que da.
-- - Explosiones de la mejora "Reacción en cadena".
-- - Sonidos y efectos de cada momento (WaveFx): golpe y onda al empezar oleada, chispas al
--   superarla, gong y viñeta roja con el jefe, confeti en la victoria y el récord, pantalla
--   gris al caer.

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local WaveConfig = require(Shared.Config.WaveConfig)
local WaveLogic = require(Shared.WaveLogic)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local Toasts = require(script.Parent.Parent.UI.Toasts)
local Juice = require(script.Parent.Parent.UI.Juice)
local WaveFx = require(script.Parent.WaveFx)

local HudDock = require(script.Parent.Parent.UI.HudDock)

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

local WaveController = {}

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
		panel.Position = UDim2.new(0.5, 0, 0, LAYOUT.Margin + LAYOUT.EnergyCardSize.Y * scale + 8)
	end
	hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(placePanel)
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
	UiKit.text(cardPanel, "Help", {
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
		table.insert(cardButtons, { Button = button, Stroke = stroke, Icon = icon, Name = name, Body = body, Level = level, Id = nil :: string? })
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

function WaveController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local eventRemote = remotes:WaitForChild(Constants.Remotes.WaveEvent) :: RemoteEvent
	local actionRemote = remotes:WaitForChild(Constants.Remotes.WaveAction) :: RemoteEvent

	local ui = buildHud()
	local streakUi = buildStreak()
	WaveFx.init()

	local fxFolder = Workspace:FindFirstChild("ClientWaveFX")
	if fxFolder then
		fxFolder:Destroy()
	end
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ClientWaveFX"
	fxFolder.Parent = Workspace

	local current: any = nil -- estado de mi partida (solo llega el de la tuya)
	local lastPhase: string? = nil
	local lastWave = 0
	local cardData: any = nil
	local resultToken = 0
	local pickedHere = false -- elegiste tú la mejora (si no, la eligió el servidor al acabarse el tiempo)
	local celebratedRun: number? = nil -- partida cuya victoria ya se celebró (al caer el jefe)

	-- Anuncio grande en el centro
	local announceToken = 0
	local function announce(text: string, color: Color3, seconds: number?)
		announceToken += 1
		local token = announceToken
		ui.Announce.Text = text
		ui.Announce.TextColor3 = color
		ui.Announce.TextTransparency = 0
		ui.AnnounceStroke.Transparency = 0
		ui.AnnounceScale.Scale = 1.35
		TweenService:Create(ui.AnnounceScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(seconds or 1.2, function()
			if announceToken == token then
				local fade = TweenInfo.new(0.35)
				TweenService:Create(ui.Announce, fade, { TextTransparency = 1 }):Play()
				TweenService:Create(ui.AnnounceStroke, fade, { Transparency = 1 }):Play()
			end
		end)
	end

	-- Mi partida: la del atributo WaveRun (el servidor solo manda la mía).
	local function myState(): any?
		local runId = player:GetAttribute(Constants.Attributes.WaveRun)
		if current and type(runId) == "number" and current.Run == runId then
			return current
		end
		return nil
	end

	-- Efectos de cada momento (WaveFx) -------------------------------------------------
	local function arenaSize(state: any): number
		return (tonumber(state and state.Radius) or WaveConfig.Place.AreaRadius) * 2
	end

	-- Empieza una oleada: golpe, onda desde el altar y un toque de cámara.
	local function waveStartFx(state: any)
		WaveFx.sound("Whoosh")
		WaveFx.sound("WaveHit", 1, 0.05)
		WaveFx.flash(Color3.new(1, 1, 1), 0.3)
		WaveFx.shake(0.22)
		WaveFx.kick(3)
		if typeof(state.Center) == "Vector3" then
			local size = arenaSize(state)
			WaveFx.ring(state.Center, if state.Endless then ENDLESS_PURPLE else THEME.Gold, 4, size * 1.1, 0.8, 0.15)
			task.delay(0.12, WaveFx.ring, state.Center, Color3.new(1, 1, 1), 2, size * 0.8, 0.7, 0.4)
		end
	end

	-- Sale el jefe: gong, rugido, imagen roja un momento y viñeta que late mientras viva.
	local function bossFx(state: any)
		WaveFx.sound("BossGong")
		WaveFx.sound("BossRoar", 1, 0.45)
		WaveFx.flash(BOSS_RED, 0.5)
		WaveFx.pulse(BOSS_RED, 0.6, 1.8)
		WaveFx.tint({ TintColor = Color3.fromRGB(255, 205, 205), Contrast = 0.12 }, 0.4, 1.6)
		WaveFx.shake(0.55)
		WaveFx.kick(7)
		if typeof(state.Center) == "Vector3" then
			local size = arenaSize(state)
			WaveFx.ring(state.Center, BOSS_RED, 4, size * 1.3, 1.1, 0.1)
			task.delay(0.25, WaveFx.ring, state.Center, BOSS_RED, 2, size, 0.9, 0.3)
		end
	end

	-- Oleada superada: sonido de acierto y chispas verdes a tus pies (rosas si te curó).
	local function clearedFx(data: any)
		WaveFx.sound("Cleared")
		announce("✅ ¡OLEADA SUPERADA!", CLEAR_GREEN, 1)
		WaveFx.flash(CLEAR_GREEN, 0.25)
		WaveFx.pulse(CLEAR_GREEN, 0.3, 0.9)
		local feet = WaveFx.feet()
		if feet then
			WaveFx.ring(feet, CLEAR_GREEN, 2, 14, 0.7, 0.2)
			WaveFx.sparkle(feet + Vector3.new(0, 1.5, 0), CLEAR_GREEN, 18)
			if data.Healed == true then
				WaveFx.sparkle(feet + Vector3.new(0, 2.5, 0), HEAL_PINK, 12)
			end
		end
	end

	-- Victoria (una vez por partida): fanfarria, destello dorado y lluvia de confeti.
	local function celebrate(runId: number?)
		if runId ~= nil and celebratedRun == runId then
			return
		end
		celebratedRun = runId
		WaveFx.setDanger(false)
		WaveFx.sound("Victory")
		WaveFx.flash(THEME.Gold, 0.45)
		WaveFx.pulse(THEME.Gold, 0.35, 1.5)
		WaveFx.shake(0.3)
		WaveFx.confetti(90)
		local feet = WaveFx.feet()
		if feet then
			WaveFx.sparkle(feet + Vector3.new(0, 2, 0), THEME.Gold, 30)
		end
	end

	-- Récord superado en plena partida: coro, estrellas y confeti desde el anuncio.
	local function recordFx()
		WaveFx.sound("Record")
		WaveFx.flash(THEME.Gold, 0.25)
		WaveFx.confettiFrom(ui.Announce, 45)
		Juice.burst(ui.Announce, THEME.Gold, 14, 160)
	end

	-- Entras al modo infinito: ráfaga que sube y golpe, todo morado.
	local function endlessFx()
		WaveFx.sound("Endless")
		WaveFx.sound("WaveHit", 0.85, 0.9)
		WaveFx.flash(ENDLESS_PURPLE, 0.4)
		WaveFx.pulse(ENDLESS_PURPLE, 0.45, 1.4)
		WaveFx.kick(5)
		local state = myState()
		if state and typeof(state.Center) == "Vector3" then
			WaveFx.ring(state.Center, ENDLESS_PURPLE, 4, arenaSize(state) * 1.2, 1, 0.15)
		end
	end

	-- Caíste: melodía que baja y la imagen pierde el color unos segundos.
	local function defeatFx()
		WaveFx.setDanger(false)
		WaveFx.sound("Defeat")
		WaveFx.tint({ Saturation = -0.85, Brightness = -0.04 }, 0.8, 2.2)
		WaveFx.pulse(Color3.fromRGB(40, 10, 20), 0.55, 2.2)
		WaveFx.shake(0.2)
	end

	-- Rebote de una tarjeta con su propia escala de pulsar (no se apilan dos UIScale).
	local function bounce(button: GuiObject, amount: number)
		local scale = button:FindFirstChild("PressScale")
		if scale and scale:IsA("UIScale") then
			scale.Scale = 1 + amount
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		else
			Juice.pop(button, amount)
		end
	end

	-- Consejo de la partida de práctica
	local hintToken = 0
	local function showHint(text: string, seconds: number)
		hintToken += 1
		local token = hintToken
		ui.HintText.Text = text
		ui.HintBox.Visible = true
		ui.HintBox.BackgroundTransparency = 0.15
		ui.HintText.TextTransparency = 0
		task.delay(seconds, function()
			if hintToken == token then
				ui.HintBox.Visible = false
			end
		end)
	end

	-- El "Pulsa E" de los altares no se ve mientras juegas (es local: los demás lo siguen viendo).
	local function refreshPrompt()
		local arenas = Workspace:FindFirstChild("WaveArenas")
		if not arenas then
			return
		end
		local free = player:GetAttribute(Constants.Attributes.WaveRun) == nil
		for _, prompt in arenas:GetDescendants() do
			if prompt.Name == "WavePrompt" and prompt:IsA("ProximityPrompt") then
				prompt.Enabled = free
			end
		end
	end

	-- El panel usa el hueco de la barra del jefe: mientras se ve, la pila de avisos baja
	-- (HudDock.setBossBar). En la oleada del jefe se esconde y la barra del jefe ocupa el sitio.
	local reserved = false
	local function reserveSlot(shown: boolean)
		if shown == reserved then
			return
		end
		reserved = shown
		local combatHud = player.PlayerGui:FindFirstChild("CombatHud")
		local bossBar = combatHud and combatHud:FindFirstChild("BossBar", true)
		local bossShown = bossBar ~= nil and (bossBar :: GuiObject).Visible
		if shown or not bossShown then
			HudDock.setBossBar(shown or bossShown)
		end
	end

	local function refreshPanel()
		local state = myState()
		local shown = state ~= nil and state.Phase ~= "Done" and state.Phase ~= "Boss"
		ui.Panel.Visible = shown
		reserveSlot(shown)
		if not shown then
			return
		end
		local phase = state.Phase
		local left = secondsLeft(state.EndsAt)
		ui.Track.Visible = phase == "Wave"
		ui.Title.TextColor3 = Color3.new(1, 1, 1)
		if phase == "Countdown" then
			ui.Title.Text = "⚔ ¡PREPÁRATE!"
			ui.Subtitle.Text = ("Empieza en %d…"):format(left)
		elseif phase == "Wave" then
			ui.Title.Text = if state.Endless then ("♾️ OLEADA %d"):format(state.Wave) else ("⚔ OLEADA %d / %d"):format(state.Wave, state.Waves)
			local total = math.max(1, state.Total or 1)
			local remaining = math.max(0, state.Remaining or 0)
			ui.Subtitle.Text = if remaining == 1 then "Queda 1 enemigo" else ("Quedan %d enemigos"):format(remaining)
			ui.Fill.Size = UDim2.fromScale(math.clamp(1 - remaining / total, 0, 1), 1)
		elseif phase == "Break" then
			ui.Title.Text = ("✅ OLEADA %d SUPERADA"):format(state.Wave)
			ui.Title.TextColor3 = THEME.BuyHighlight
			ui.Subtitle.Text = ("La siguiente en %d…"):format(left)
		elseif phase == "Cards" then
			ui.Title.Text = "✨ ELIGE UNA MEJORA"
			ui.Title.TextColor3 = THEME.Gold
			ui.Subtitle.Text = ("%d s"):format(left)
		elseif phase == "Boss" then
			ui.Title.Text = "💀 ¡JEFE FINAL!"
			ui.Title.TextColor3 = BOSS_RED
			ui.Subtitle.Text = tostring(state.Boss or "")
		elseif phase == "Choice" then
			ui.Title.Text = "♾️ ¿MODO INFINITO?"
			ui.Title.TextColor3 = THEME.Gold
			ui.Subtitle.Text = ("%d s"):format(left)
		end
	end

	-- Mejoras -------------------------------------------------------------------------
	local function closeCards()
		cardData = nil
		ui.CardPanel.Visible = false
		ContextActionService:UnbindAction(CARD_ACTION)
	end

	local function pick(index: number)
		local card = ui.Cards[index]
		if not (cardData and card and card.Id) then
			return
		end
		actionRemote:FireServer("Pick", card.Id)
		pickedHere = true
		WaveFx.sound("Pick")
		Juice.burst(card.Button, THEME.Gold, 12, 120)
		bounce(card.Button, 0.1)
		for _, other in ui.Cards do
			other.Stroke.Color = if other == card then THEME.BuyHighlight else THEME.Disabled
		end
	end

	local function openCards(data: any)
		if type(data) ~= "table" or type(data.Cards) ~= "table" then
			return
		end
		cardData = data
		-- Las tarjetas ya explican cómo elegir: fuera el consejo que hubiera debajo
		hintToken += 1
		ui.HintBox.Visible = false
		for index, card in ui.Cards do
			local info = data.Cards[index]
			card.Button.Visible = info ~= nil
			card.Id = if info then info.Id else nil
			if info then
				card.Icon.Text = tostring(info.Icon)
				card.Name.Text = tostring(info.Name)
				card.Body.Text = tostring(info.Text)
				local level = tonumber(info.Level) or 0
				card.Level.Text = if level > 0 then ("Nv. %d → %d"):format(level, level + 1) else "¡Nueva!"
				card.Stroke.Color = THEME.Gold
			end
		end
		ui.CardPanel.Visible = true
		pickedHere = false
		WaveFx.sound("CardsOpen")
		WaveFx.sound("Chime", 1, 0.15)
		for index, card in ui.Cards do
			if card.Button.Visible then
				task.delay((index - 1) * 0.07, bounce, card.Button, 0.14)
			end
		end
		ContextActionService:BindAction(CARD_ACTION, function(_, inputState, input)
			if inputState == Enum.UserInputState.Begin then
				local index = table.find(CARD_KEYS, input.KeyCode)
				if index then
					pick(index)
				end
			end
			return Enum.ContextActionResult.Pass
		end, false, table.unpack(CARD_KEYS))
	end

	for index, card in ui.Cards do
		card.Button.Activated:Connect(function()
			pick(index)
		end)
	end

	-- Modo infinito ---------------------------------------------------------------------
	local choiceToken = 0
	local function closeChoice()
		choiceToken += 1
		ui.ChoicePanel.Visible = false
		ContextActionService:UnbindAction(CHOICE_ACTION)
	end

	local function choose(keepGoing: boolean)
		if not ui.ChoicePanel.Visible then
			return
		end
		actionRemote:FireServer("Endless", keepGoing)
		closeChoice()
		if keepGoing then
			announce("♾️ ¡MODO INFINITO!", THEME.Gold, 2)
			endlessFx()
		end
	end

	local function openChoice(data: any)
		if type(data) ~= "table" then
			return
		end
		closeCards()
		hintToken += 1
		ui.HintBox.Visible = false
		choiceToken += 1
		local token = choiceToken
		local reward = ""
		if (tonumber(data.VictoryEnergy) or 0) > 0 or (tonumber(data.VictoryMoney) or 0) > 0 then
			reward = ("🎁 Premio cobrado: <b>+%s 💎  +%s 💰</b>\n"):format(formatNumber(tonumber(data.VictoryEnergy) or 0), formatNumber(tonumber(data.VictoryMoney) or 0))
		end
		ui.ChoiceBody.Text = reward .. "¿Sigues en el <b>modo infinito</b>? Oleadas sin fin, cada vez más duras y con más premio. Si caes, no pierdes nada."
		ui.ChoicePanel.Visible = true
		announce("🏆 ¡VICTORIA!", THEME.Gold, 2)
		local state = myState()
		celebrate(if state then state.Run else nil)
		local endsAt = tonumber(data.EndsAt) or (serverNow() + WaveConfig.Endless.ChoiceSeconds)
		local total = math.max(0.1, endsAt - serverNow())
		task.spawn(function()
			while choiceToken == token and ui.ChoicePanel.Visible do
				local left = math.max(0, endsAt - serverNow())
				ui.ChoiceTimerFill.Size = UDim2.fromScale(math.clamp(left / total, 0, 1), 1)
				if left <= 0 then
					closeChoice()
					break
				end
				task.wait(0.05)
			end
		end)
		ContextActionService:BindAction(CHOICE_ACTION, function(_, inputState, input)
			if inputState == Enum.UserInputState.Begin then
				if input.KeyCode == Enum.KeyCode.One then
					choose(true)
				elseif input.KeyCode == Enum.KeyCode.Two then
					choose(false)
				end
			end
			return Enum.ContextActionResult.Pass
		end, false, Enum.KeyCode.One, Enum.KeyCode.Two)
	end
	ui.ChoiceGo.Activated:Connect(function()
		choose(true)
	end)
	ui.ChoiceStop.Activated:Connect(function()
		choose(false)
	end)

	-- Resumen ---------------------------------------------------------------------------
	local function closeResult()
		resultToken += 1
		ui.ResultPanel.Visible = false
	end
	ui.ResultClose.Activated:Connect(closeResult)

	local function showResult(data: any)
		if type(data) ~= "table" then
			return
		end
		closeCards()
		resultToken += 1
		local token = resultToken
		local runId = tonumber(data.Run)
		if data.Endless then
			-- Modo infinito: el jefe ya cayó; se acaba al caer (sin perder nada)
			ui.ResultTitle.Text = ("♾️ Llegaste a la oleada %d"):format(tonumber(data.Wave) or 0)
			ui.ResultTitle.TextColor3 = THEME.Gold
			WaveFx.setDanger(false)
			WaveFx.sound("EndlessEnd")
			WaveFx.pulse(THEME.Gold, 0.3, 1.5)
			if data.NewBest then
				WaveFx.confetti(60)
			end
		elseif data.Victory then
			ui.ResultTitle.Text = if data.Tutorial then "🏆 ¡PRÁCTICA SUPERADA!" else "🏆 ¡VICTORIA!"
			ui.ResultTitle.TextColor3 = THEME.Gold
			if celebratedRun == nil or celebratedRun ~= runId then
				-- Sin modo infinito (la práctica): la victoria se celebra aquí
				announce("🏆 ¡VICTORIA!", THEME.Gold, 2)
				celebrate(runId)
			end
		else
			ui.ResultTitle.Text = ("💀 Caíste en la oleada %d"):format(tonumber(data.Wave) or 0)
			ui.ResultTitle.TextColor3 = THEME.Error
			defeatFx()
		end
		local lines = {
			("⚔ Enemigos: <b>%s</b>"):format(formatNumber(tonumber(data.Kills) or 0)),
			("💎 Diamantes: <b>%s</b>     💰 Dinero: <b>%s</b>"):format(formatNumber(tonumber(data.Energy) or 0), formatNumber(tonumber(data.Money) or 0)),
			("🔥 Mejor racha: <b>x%d</b>     🌟 Orbes dorados: <b>%d</b>"):format(tonumber(data.BestStreak) or 0, tonumber(data.Golden) or 0),
		}
		if data.Victory and (tonumber(data.VictoryEnergy) or 0) > 0 then
			table.insert(lines, ("🎁 Premio de victoria: +%s 💎  +%s 💰"):format(formatNumber(data.VictoryEnergy), formatNumber(tonumber(data.VictoryMoney) or 0)))
		end
		if not data.Tutorial then
			local personal = tonumber(data.PersonalBest) or 0
			if data.NewBest then
				table.insert(lines, ("🎉 <b>¡Nuevo récord!</b> Oleada %d"):format(personal))
			elseif personal > 0 then
				table.insert(lines, ("🏅 Tu récord aquí: oleada %d"):format(personal))
			end
			table.insert(lines, ("Récord del servidor: oleada %d"):format(tonumber(data.Best) or 0))
		end
		ui.ResultBody.Text = table.concat(lines, "\n")
		ui.ResultPanel.Visible = true
		if data.Victory or data.Endless or data.NewBest then
			task.defer(Juice.burst, ui.ResultTitle, THEME.Gold, 12, 150)
		end
		task.delay(10, function()
			if resultToken == token then
				closeResult()
			end
		end)
	end

	-- Explosión de "Reacción en cadena"
	local function explosion(position: Vector3, radius: number)
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanQuery = false
		ball.CanTouch = false
		ball.CastShadow = false
		ball.Material = Enum.Material.Neon
		ball.Color = ORANGE
		ball.Transparency = 0.25
		ball.Size = Vector3.one * 1
		ball.CFrame = CFrame.new(position + Vector3.new(0, 1, 0))
		ball.Parent = fxFolder
		TweenService:Create(ball, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.one * radius * 2,
			Transparency = 1,
		}):Play()
		Debris:AddItem(ball, 0.4)
	end

	-- Eventos del servidor --------------------------------------------------------------
	local function onState(state: any)
		if type(state) ~= "table" or type(state.Run) ~= "number" then
			return
		end
		if not current or current.Run ~= state.Run then
			lastPhase = nil
			lastWave = 0
		end
		current = state
		local mine = myState() == state
		local previous = lastPhase
		local previousWave = lastWave
		lastPhase = state.Phase
		lastWave = state.Wave or 0
		if mine then
			if state.Phase == "Countdown" and previous ~= "Countdown" then
				announce("⚔ ¡PREPÁRATE!", THEME.Gold, 1)
				WaveFx.sound("Whoosh", 0.9)
			elseif state.Phase == "Wave" and (previous ~= "Wave" or (state.Wave or 0) ~= previousWave) then
				announce(("OLEADA %d"):format(state.Wave), Color3.new(1, 1, 1), 1.3)
				waveStartFx(state)
			elseif state.Phase == "Boss" and previous ~= "Boss" then
				announce("💀 ¡JEFE FINAL!", BOSS_RED, 1.8)
				bossFx(state)
			end
		end
		-- La viñeta roja late solo mientras el jefe de tu partida sigue vivo
		WaveFx.setDanger(mine and state.Phase == "Boss")
		if state.Phase ~= "Cards" and cardData then
			closeCards()
		end
		refreshPanel()
	end

	eventRemote.OnClientEvent:Connect(function(kind: string, data: any)
		if kind == "State" then
			onState(data)
		elseif kind == "Cards" then
			openCards(data)
		elseif kind == "Picked" then
			if not pickedHere then
				WaveFx.sound("Pick") -- se acabó el tiempo y la eligió el servidor
			end
			pickedHere = false
			if type(data) == "table" and type(data.Id) == "string" then
				local card = WaveConfig.Cards[data.Id]
				local level = type(data.Levels) == "table" and tonumber(data.Levels[data.Id]) or 1
				if card then
					Toasts.show(("%s %s  ·  nivel %d"):format(card.Icon, card.Name, level), { Color = THEME.Gold, Key = "WaveCard" })
				end
			end
			task.delay(0.35, closeCards)
		elseif kind == "Cleared" then
			if type(data) == "table" then
				local heal = if data.Healed == true then "  +❤️" else ""
				Toasts.show(("✅ Oleada %d superada  +%s 💎  +%s 💰%s"):format(tonumber(data.Wave) or 0, formatNumber(tonumber(data.Energy) or 0), formatNumber(tonumber(data.Money) or 0), heal), { Color = THEME.BuyHighlight, Key = "WaveCleared" })
				clearedFx(data)
			end
		elseif kind == "Choice" then
			openChoice(data)
		elseif kind == "Record" then
			if type(data) == "table" then
				Toasts.show(("🏆 ¡Nuevo récord! Oleada %d (antes %d)"):format(tonumber(data.Wave) or 0, tonumber(data.Previous) or 0), { Color = THEME.Gold, Key = "WaveRecord" })
				announce("🏆 ¡NUEVO RÉCORD!", THEME.Gold, 1.5)
				recordFx()
			end
		elseif kind == "Result" then
			current = nil
			WaveFx.setDanger(false)
			closeChoice()
			showResult(data)
			refreshPanel()
		elseif kind == "Hint" then
			if type(data) == "table" and type(data.Text) == "string" then
				showHint(data.Text, math.clamp(tonumber(data.Seconds) or 6, 1, 20))
			end
		elseif kind == "Fx" then
			if type(data) == "table" and data.Kind == "Explode" and typeof(data.Position) == "Vector3" then
				explosion(data.Position, tonumber(data.Radius) or 6)
			end
		end
	end)

	-- Racha sobre la cabeza
	local function attachStreak()
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		streakUi.Billboard.Adornee = if head and head:IsA("BasePart") then head else nil
	end
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 5)
		attachStreak()
	end)
	attachStreak()

	local lastCount = 0
	local function refreshStreak()
		local count = player:GetAttribute(Constants.Attributes.Streak)
		local untilAt = player:GetAttribute(Constants.Attributes.StreakUntil)
		local active = typeof(count) == "number" and typeof(untilAt) == "number" and count >= STREAK_MIN and serverNow() <= untilAt
		streakUi.Billboard.Enabled = active and streakUi.Billboard.Adornee ~= nil
		if not active then
			lastCount = 0
			return
		end
		local value = count :: number
		if value ~= lastCount then
			lastCount = value
			streakUi.Count.Text = ("x%d 🔥"):format(value)
			streakUi.Count.TextColor3 = streakColor(value)
			local multiplier = WaveLogic.streakMultiplier(value)
			streakUi.Bonus.Text = if multiplier > 1 then ("botín ×%s"):format(formatNumber(multiplier, 1)) else "¡sigue así!"
			streakUi.Scale.Scale = 1.25
			TweenService:Create(streakUi.Scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			-- Cada salto de multiplicador, un aviso
			if value % WaveConfig.Streak.Step == 0 then
				WaveFx.sound("Tick", math.min(1.8, 1 + value / WaveConfig.Streak.Step * 0.08))
				local feet = WaveFx.feet()
				if feet then
					WaveFx.sparkle(feet + Vector3.new(0, 3, 0), streakColor(value), 10)
				end
			end
		end
		-- Se apaga al acabarse la ventana
		local remaining = (untilAt :: number) - serverNow()
		streakUi.Count.TextTransparency = if remaining < 0.6 then 0.5 else 0
	end

	-- Cuenta atrás y textos que dependen del tiempo
	local lastSecond = -1
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < 0.1 then
			return
		end
		elapsed = 0
		refreshStreak()
		refreshPanel()
		local state = myState()
		if state and state.Phase == "Countdown" then
			local left = secondsLeft(state.EndsAt)
			if left ~= lastSecond and left > 0 then
				lastSecond = left
				announce(tostring(left), Color3.new(1, 1, 1), 0.8)
				WaveFx.sound("Tick", 1 + math.max(0, WaveConfig.StartCountdown - left) * 0.1)
			end
		else
			lastSecond = -1
		end
		if cardData and typeof(cardData.EndsAt) == "number" then
			local fraction = math.clamp((cardData.EndsAt - serverNow()) / WaveConfig.CardSeconds, 0, 1)
			ui.CardTimerFill.Size = UDim2.fromScale(fraction, 1)
			if fraction <= 0 then
				closeCards()
			end
		end
	end)
	player:GetAttributeChangedSignal(Constants.Attributes.WaveRun):Connect(function()
		if player:GetAttribute(Constants.Attributes.WaveRun) == nil then
			WaveFx.setDanger(false)
		end
		refreshPanel()
		refreshPrompt()
	end)
	task.spawn(function()
		Workspace:WaitForChild("WaveArenas", 30)
		task.wait(1)
		refreshPrompt()
	end)
end

return WaveController
