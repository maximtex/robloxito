-- Oleadas en el cliente (solo presentación; WaveService decide todo):
-- - Panel arriba al centro (en el hueco de la barra del jefe, bajo el tutorial) mientras
--   juegas una partida: oleada, enemigos que quedan y cuenta atrás. En la del jefe se
--   esconde y se ve la barra del jefe.
-- - Anuncios grandes en el centro: cuenta atrás, "OLEADA 4", "¡JEFE!".
-- - Mejoras: tres tarjetas para elegir (clic o teclas 1, 2, 3) con su tiempo.
-- - Resumen al terminar (victoria o caída): enemigos, ⚡, 💰, orbes dorados y mejor racha.
-- - Racha: contador "x12" sobre tu cabeza mientras matas sin parar (atributos Streak y
--   StreakUntil de EnemyService), con el multiplicador de botín que da.
-- - Explosiones de la mejora "Reacción en cadena".

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
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

local HudDock = require(script.Parent.Parent.UI.HudDock)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local LAYOUT = Theme.Layout
local INK = Color3.fromRGB(43, 29, 63)
local ORANGE = Color3.fromRGB(255, 150, 60)
local BOSS_RED = Color3.fromRGB(240, 80, 96)
local CARD_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }
local CARD_ACTION = "RebirthWaveCards"
local STREAK_MIN = 3 -- la racha se ve a partir de aquí
local STREAK_COLORS = {
	{ Min = 0, Color = Color3.fromRGB(255, 255, 255) },
	{ Min = 10, Color = Color3.fromRGB(255, 226, 92) },
	{ Min = 25, Color = Color3.fromRGB(255, 150, 60) },
	{ Min = 50, Color = Color3.fromRGB(255, 92, 120) },
	{ Min = 100, Color = Color3.fromRGB(196, 120, 255) },
}
local SOUNDS = {
	Tick = "rbxasset://sounds/electronicpingshort.wav",
	Wave = "rbxasset://sounds/impact_explosion_03.mp3",
	Pick = "rbxasset://sounds/electronicpingshort.wav",
}

local WaveController = {}

local player = Players.LocalPlayer

local function makeSound(id: string, volume: number, speed: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.Parent = SoundService
	return sound
end

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

	hud.Parent = playerGui
	UiKit.bindScale(hud, { panelScale })
	-- Mismo sitio que la barra del jefe (CombatController): bajo la tarjeta de energía.
	local function placePanel()
		local scale = UiKit.computeScale(hud.AbsoluteSize)
		panel.Position = UDim2.new(0.5, 0, 0, LAYOUT.Margin + LAYOUT.EnergyCardSize.Y * scale + 8)
	end
	hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(placePanel)
	placePanel()

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

	modal.Parent = playerGui
	UiKit.bindScale(modal, { cardScale, resultScale })

	return {
		Panel = panel,
		Title = title,
		Subtitle = subtitle,
		Track = track,
		Fill = fill,
		Announce = announce,
		AnnounceStroke = announceStroke,
		AnnounceScale = announceScale,
		CardPanel = cardPanel,
		CardTimerFill = cardTimerFill,
		Cards = cardButtons,
		ResultPanel = resultPanel,
		ResultTitle = resultTitle,
		ResultBody = resultBody,
		ResultClose = resultClose,
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
	local tickSound = makeSound(SOUNDS.Tick, 0.35, 1.2)
	local waveSound = makeSound(SOUNDS.Wave, 0.3, 0.7)
	local pickSound = makeSound(SOUNDS.Pick, 0.45, 1.6)

	local fxFolder = Workspace:FindFirstChild("ClientWaveFX")
	if fxFolder then
		fxFolder:Destroy()
	end
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ClientWaveFX"
	fxFolder.Parent = Workspace

	local states: { [string]: any } = {}
	local lastPhase: { [string]: string } = {}
	local lastWave: { [string]: number } = {}
	local cardData: any = nil
	local resultToken = 0

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

	-- Partida que me toca: en la que participo o, si hay una en marcha, la de la arena en
	-- la que estoy.
	local function myState(): any?
		local arenaId = player:GetAttribute(Constants.Attributes.WaveArena)
		if type(arenaId) == "string" and states[arenaId] then
			return states[arenaId]
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		for _, state in states do
			local active = state.Phase ~= "Idle" and state.Phase ~= "Result"
			if active and root and root:IsA("BasePart") and typeof(state.Center) == "Vector3" then
				local offset = root.Position - state.Center
				if Vector2.new(offset.X, offset.Z).Magnitude <= (state.Radius or 0) then
					return state
				end
			end
		end
		return nil
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
		local shown = state ~= nil and state.Phase ~= "Idle" and state.Phase ~= "Result" and state.Phase ~= "Boss"
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
			ui.Title.Text = ("⚔ OLEADA %d / %d"):format(state.Wave, state.Waves)
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
		pickSound:Play()
		for _, other in ui.Cards do
			other.Stroke.Color = if other == card then THEME.BuyHighlight else THEME.Disabled
		end
	end

	local function openCards(data: any)
		if type(data) ~= "table" or type(data.Cards) ~= "table" then
			return
		end
		cardData = data
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
		if data.Victory then
			ui.ResultTitle.Text = "🏆 ¡VICTORIA!"
			ui.ResultTitle.TextColor3 = THEME.Gold
			announce("🏆 ¡VICTORIA!", THEME.Gold, 2)
		else
			ui.ResultTitle.Text = ("💀 Caíste en la oleada %d"):format(tonumber(data.Wave) or 0)
			ui.ResultTitle.TextColor3 = THEME.Error
		end
		local lines = {
			("⚔ Enemigos: <b>%s</b>"):format(formatNumber(tonumber(data.Kills) or 0)),
			("⚡ Energía: <b>%s</b>     💰 Dinero: <b>%s</b>"):format(formatNumber(tonumber(data.Energy) or 0), formatNumber(tonumber(data.Money) or 0)),
			("🔥 Mejor racha: <b>x%d</b>     🌟 Orbes dorados: <b>%d</b>"):format(tonumber(data.BestStreak) or 0, tonumber(data.Golden) or 0),
		}
		if data.Victory and (tonumber(data.VictoryEnergy) or 0) > 0 then
			table.insert(lines, ("🎁 Premio de victoria: +%s ⚡  +%s 💰"):format(formatNumber(data.VictoryEnergy), formatNumber(tonumber(data.VictoryMoney) or 0)))
		end
		table.insert(lines, ("Récord del servidor: oleada %d"):format(tonumber(data.Best) or 0))
		ui.ResultBody.Text = table.concat(lines, "\n")
		ui.ResultPanel.Visible = true
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
		if type(state) ~= "table" or type(state.Arena) ~= "string" then
			return
		end
		states[state.Arena] = state
		local mine = myState() == state
		local previous = lastPhase[state.Arena]
		local previousWave = lastWave[state.Arena] or 0
		lastPhase[state.Arena] = state.Phase
		lastWave[state.Arena] = state.Wave or 0
		if mine then
			if state.Phase == "Countdown" and previous ~= "Countdown" then
				announce("⚔ ¡PREPÁRATE!", THEME.Gold, 1)
			elseif state.Phase == "Wave" and (previous ~= "Wave" or (state.Wave or 0) ~= previousWave) then
				announce(("OLEADA %d"):format(state.Wave), Color3.new(1, 1, 1), 1.3)
				waveSound:Play()
			elseif state.Phase == "Boss" and previous ~= "Boss" then
				announce("💀 ¡JEFE FINAL!", BOSS_RED, 1.8)
				waveSound:Play()
			end
		end
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
				Toasts.show(("✅ Oleada %d superada  +%s ⚡  +%s 💰"):format(tonumber(data.Wave) or 0, formatNumber(tonumber(data.Energy) or 0), formatNumber(tonumber(data.Money) or 0)), { Color = THEME.BuyHighlight, Key = "WaveCleared" })
			end
		elseif kind == "Result" then
			showResult(data)
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
				tickSound:Play()
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
				tickSound:Play()
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
	player:GetAttributeChangedSignal(Constants.Attributes.WaveArena):Connect(refreshPanel)
end

return WaveController
