-- WaveController · HudAndFx: arranque, anuncios, efectos visuales/sonoros de oleada y jefe, consejos y panel superior.
-- Parte de WaveController (ver WaveController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local WaveConfig = require(Shared.Config.WaveConfig)
local Juice = require(script.Parent.Parent.Parent.UI.Juice)
local WaveFx = require(script.Parent.Parent.WaveFx)
local HudDock = require(script.Parent.Parent.Parent.UI.HudDock)

local ctx: any -- tabla de estado compartida (la crea WaveController/init.luau)
local BOSS_RED: any
local CLEAR_GREEN: any
local ENDLESS_PURPLE: any
local HEAL_PINK: any
local THEME: any
local player: any

-- Funciones de las otras partes
local function buildHud(...) return ctx.buildHud(...) end
local function buildStreak(...) return ctx.buildStreak(...) end
local function secondsLeft(...) return ctx.secondsLeft(...) end

local Part = { Api = {} }

function Part.start()
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
		if ctx.current and type(runId) == "number" and ctx.current.Run == runId then
			return ctx.current
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
		if runId ~= nil and ctx.celebratedRun == runId then
			return
		end
		ctx.celebratedRun = runId
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
	local function showHint(text: string, seconds: number)
		ctx.hintToken += 1
		local token = ctx.hintToken
		ui.HintText.Text = text
		-- Una línea más de alto por cada salto de línea (modificador y dificultad juntos)
		local _, breaks = string.gsub(text, "\n", "")
		ui.HintBox.Size = UDim2.fromOffset(560, 64 + 30 * math.min(breaks, 3))
		ui.HintBox.Visible = true
		ui.HintBox.BackgroundTransparency = 0.15
		ui.HintText.TextTransparency = 0
		task.delay(seconds, function()
			if ctx.hintToken == token then
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
		ui.Tags.Text = if type(state.Tags) == "string" then state.Tags else ""
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

	ctx.actionRemote = actionRemote
	ctx.announce = announce
	ctx.bossFx = bossFx
	ctx.bounce = bounce
	ctx.celebrate = celebrate
	ctx.clearedFx = clearedFx
	ctx.defeatFx = defeatFx
	ctx.endlessFx = endlessFx
	ctx.eventRemote = eventRemote
	ctx.fxFolder = fxFolder
	ctx.myState = myState
	ctx.recordFx = recordFx
	ctx.refreshPanel = refreshPanel
	ctx.refreshPrompt = refreshPrompt
	ctx.showHint = showHint
	ctx.streakUi = streakUi
	ctx.ui = ui
	ctx.waveStartFx = waveStartFx
end

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	BOSS_RED = context.BOSS_RED
	CLEAR_GREEN = context.CLEAR_GREEN
	ENDLESS_PURPLE = context.ENDLESS_PURPLE
	HEAL_PINK = context.HEAL_PINK
	THEME = context.THEME
	player = context.player
end

return Part
