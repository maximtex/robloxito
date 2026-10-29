-- WaveController · CardsAndSummary: elección de mejoras, ventana de modo infinito, resumen de partida y efectos de explosión/división.
-- Parte de WaveController (ver WaveController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WaveConfig = require(Shared.Config.WaveConfig)
local formatNumber = require(Shared.Util.FormatNumber)
local Juice = require(script.Parent.Parent.Parent.UI.Juice)
local WaveFx = require(script.Parent.Parent.WaveFx)

local ctx: any -- tabla de estado compartida (la crea WaveController/init.luau)
local CARD_ACTION: any
local CARD_KEYS: any
local CHOICE_ACTION: any
local ORANGE: any
local THEME: any

-- Funciones de las otras partes
local function announce(...) return ctx.announce(...) end
local function bounce(...) return ctx.bounce(...) end
local function celebrate(...) return ctx.celebrate(...) end
local function defeatFx(...) return ctx.defeatFx(...) end
local function endlessFx(...) return ctx.endlessFx(...) end
local function myState(...) return ctx.myState(...) end
local function serverNow(...) return ctx.serverNow(...) end

local Part = { Api = {} }

function Part.start()
	local actionRemote = ctx.actionRemote
	local fxFolder = ctx.fxFolder
	local ui = ctx.ui

	-- Mejoras -------------------------------------------------------------------------
	local function closeCards()
		ctx.cardData = nil
		ui.CardPanel.Visible = false
		ContextActionService:UnbindAction(CARD_ACTION)
	end

	-- Las cartas salen boca abajo y se voltean una a una: hasta que se ven todas no se puede
	-- elegir (antes se elegía sin querer con el clic de atacar o las teclas, sin leerlas).
	local CARD_REVEAL_START = 0.35 -- s hasta que se voltea la primera
	local CARD_REVEAL_STEP = 0.3 -- s entre una y la siguiente
	local CARD_READ = 0.35 -- s más tras la última antes de poder elegir
	local CARD_HELP = "Haz clic o pulsa 1, 2 o 3 · dura toda la partida"
	local cardsReadyAt = 0

	local function pick(index: number)
		local card = ui.Cards[index]
		if not (ctx.cardData and card and card.Id) then
			return
		end
		if os.clock() < cardsReadyAt then
			return -- aún se están volteando
		end
		actionRemote:FireServer("Pick", card.Id)
		ctx.pickedHere = true
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
		ctx.cardData = data
		-- Las tarjetas ya explican cómo elegir: fuera el consejo que hubiera debajo
		ctx.hintToken += 1
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
		ctx.pickedHere = false
		WaveFx.sound("CardsOpen")
		-- Boca abajo; se voltean una a una (la tapa se cierra hacia el centro) y luego se elige
		local shown = 0
		for _, card in ui.Cards do
			if card.Button.Visible then
				shown += 1
			end
			card.Cover.Visible = card.Button.Visible
			card.Cover.Size = UDim2.fromScale(1, 1)
			card.Button.AutoButtonColor = false
		end
		cardsReadyAt = os.clock() + CARD_REVEAL_START + CARD_REVEAL_STEP * math.max(0, shown - 1) + CARD_READ
		ui.CardHelp.Text = "👀 Mira bien tus opciones…"
		local order = 0
		for _, card in ui.Cards do
			if not card.Button.Visible then
				continue
			end
			order += 1
			task.delay(CARD_REVEAL_START + CARD_REVEAL_STEP * (order - 1), function()
				if ctx.cardData ~= data then
					return
				end
				TweenService:Create(card.Cover, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromScale(0, 1) }):Play()
				task.delay(0.18, function()
					card.Cover.Visible = false
				end)
				bounce(card.Button, 0.14)
				WaveFx.sound("Chime", 1 + order * 0.08, 0.15)
			end)
		end
		task.delay(cardsReadyAt - os.clock(), function()
			if ctx.cardData == data then
				ui.CardHelp.Text = CARD_HELP
				for _, card in ui.Cards do
					card.Button.AutoButtonColor = true
				end
			end
		end)
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
		ctx.hintToken += 1
		ui.HintBox.Visible = false
		choiceToken += 1
		local token = choiceToken
		local reward = ""
		if (tonumber(data.VictoryDiamonds) or 0) > 0 or (tonumber(data.VictoryMoney) or 0) > 0 then
			reward = ("🎁 Premio cobrado: <b>+%s 💎  +%s 💰</b>\n"):format(formatNumber(tonumber(data.VictoryDiamonds) or 0), formatNumber(tonumber(data.VictoryMoney) or 0))
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
		ctx.resultToken += 1
		ui.ResultPanel.Visible = false
	end
	ui.ResultClose.Activated:Connect(closeResult)

	local function showResult(data: any)
		if type(data) ~= "table" then
			return
		end
		closeCards()
		ctx.resultToken += 1
		local token = ctx.resultToken
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
			if ctx.celebratedRun == nil or ctx.celebratedRun ~= runId then
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
			("💎 Diamantes: <b>%s</b>     💰 Dinero: <b>%s</b>"):format(formatNumber(tonumber(data.Diamonds) or 0), formatNumber(tonumber(data.Money) or 0)),
			("🔥 Mejor racha: <b>x%d</b>     🌟 Orbes dorados: <b>%d</b>"):format(tonumber(data.BestStreak) or 0, tonumber(data.Golden) or 0),
		}
		if data.Victory and (tonumber(data.VictoryDiamonds) or 0) > 0 then
			table.insert(lines, ("🎁 Premio de victoria: +%s 💎  +%s 💰"):format(formatNumber(data.VictoryDiamonds), formatNumber(tonumber(data.VictoryMoney) or 0)))
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
			if ctx.resultToken == token then
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

	-- El Coloso del Equilibrio se parte en dos: estalla en una bola mitad fuego mitad hielo,
	-- dos ondas (naranja y azul), destello, temblor y el aviso con los nombres de las mitades
	local SPLIT_FIRE = Color3.fromRGB(255, 130, 40)
	local SPLIT_ICE = Color3.fromRGB(110, 210, 255)
	local function splitFx(position: Vector3, names: any)
		for index, color in { SPLIT_FIRE, SPLIT_ICE } do
			local ball = Instance.new("Part")
			ball.Shape = Enum.PartType.Ball
			ball.Anchored = true
			ball.CanCollide = false
			ball.CanQuery = false
			ball.CanTouch = false
			ball.CastShadow = false
			ball.Material = Enum.Material.Neon
			ball.Color = color
			ball.Transparency = 0.2
			ball.Size = Vector3.one * 4
			ball.CFrame = CFrame.new(position + Vector3.new((index - 1.5) * 6, 2, 0))
			ball.Parent = fxFolder
			TweenService:Create(ball, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.one * 34,
				Transparency = 1,
			}):Play()
			Debris:AddItem(ball, 0.8)
			WaveFx.ring(position, color, 6, 70, 1.2, 0.1)
		end
		WaveFx.sparkle(position + Vector3.new(0, 4, 0), SPLIT_FIRE, 30)
		WaveFx.sparkle(position + Vector3.new(0, 4, 0), SPLIT_ICE, 30)
		WaveFx.sound("BossGong")
		WaveFx.sound("BossRoar", 0.8, 0.2)
		WaveFx.flash(Color3.new(1, 1, 1), 0.8)
		WaveFx.shake(0.8)
		WaveFx.kick(9)
		local text = '<font size="44">💥 ¡EL COLOSO SE PARTE EN DOS!</font>'
		if type(names) == "table" and #names >= 2 then
			-- Solo el nombre corto ("Ignis, el Coloso de Fuego" -> "Ignis")
			local first = string.match(tostring(names[1]), "^[^,]+") or ""
			local second = string.match(tostring(names[2]), "^[^,]+") or ""
			text ..= ('\n<font size="34">🔥 %s  ·  ❄️ %s</font>'):format(first, second)
		end
		ui.Announce.RichText = true
		announce(text, THEME.Gold, 2.6)
	end

	ctx.closeCards = closeCards
	ctx.closeChoice = closeChoice
	ctx.explosion = explosion
	ctx.openCards = openCards
	ctx.openChoice = openChoice
	ctx.showResult = showResult
	ctx.splitFx = splitFx
end

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	CARD_ACTION = context.CARD_ACTION
	CARD_KEYS = context.CARD_KEYS
	CHOICE_ACTION = context.CHOICE_ACTION
	ORANGE = context.ORANGE
	THEME = context.THEME
end

return Part
