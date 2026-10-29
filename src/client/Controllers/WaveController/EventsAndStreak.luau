-- WaveController · EventsAndStreak: recepción de eventos del servidor (WaveEvent), cartel de racha sobre la cabeza y bucle de tiempo.
-- Parte de WaveController (ver WaveController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local WaveConfig = require(Shared.Config.WaveConfig)
local WaveLogic = require(Shared.WaveLogic)
local formatNumber = require(Shared.Util.FormatNumber)
local Toasts = require(script.Parent.Parent.Parent.UI.Toasts)
local WaveFx = require(script.Parent.Parent.WaveFx)
local WaveChest = require(script.Parent.Parent.WaveChest)

local ctx: any -- tabla de estado compartida (la crea WaveController/init.luau)
local BOSS_RED: any
local STREAK_MIN: any
local THEME: any
local player: any

-- Funciones de las otras partes
local function announce(...) return ctx.announce(...) end
local function bossFx(...) return ctx.bossFx(...) end
local function clearedFx(...) return ctx.clearedFx(...) end
local function closeCards(...) return ctx.closeCards(...) end
local function closeChoice(...) return ctx.closeChoice(...) end
local function explosion(...) return ctx.explosion(...) end
local function myState(...) return ctx.myState(...) end
local function openCards(...) return ctx.openCards(...) end
local function openChoice(...) return ctx.openChoice(...) end
local function recordFx(...) return ctx.recordFx(...) end
local function refreshPanel(...) return ctx.refreshPanel(...) end
local function refreshPrompt(...) return ctx.refreshPrompt(...) end
local function secondsLeft(...) return ctx.secondsLeft(...) end
local function serverNow(...) return ctx.serverNow(...) end
local function showHint(...) return ctx.showHint(...) end
local function showResult(...) return ctx.showResult(...) end
local function splitFx(...) return ctx.splitFx(...) end
local function streakColor(...) return ctx.streakColor(...) end
local function waveStartFx(...) return ctx.waveStartFx(...) end

local Part = { Api = {} }

function Part.start()
	local eventRemote = ctx.eventRemote
	local streakUi = ctx.streakUi
	local ui = ctx.ui

	-- Eventos del servidor --------------------------------------------------------------
	local function onState(state: any)
		if type(state) ~= "table" or type(state.Run) ~= "number" then
			return
		end
		if not ctx.current or ctx.current.Run ~= state.Run then
			ctx.lastPhase = nil
			ctx.lastWave = 0
		end
		ctx.current = state
		local mine = myState() == state
		local previous = ctx.lastPhase
		local previousWave = ctx.lastWave
		ctx.lastPhase = state.Phase
		ctx.lastWave = state.Wave or 0
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
		if state.Phase ~= "Cards" and ctx.cardData then
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
			if not ctx.pickedHere then
				WaveFx.sound("Pick") -- se acabó el tiempo y la eligió el servidor
			end
			ctx.pickedHere = false
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
				-- Los 💎 de cada oleada son pocos (muchas veces 0): solo se enseñan si hay
				local diamonds = tonumber(data.Diamonds) or 0
				local gems = if diamonds > 0 then ("  +%s 💎"):format(formatNumber(diamonds)) else ""
				Toasts.show(("✅ Oleada %d superada%s  +%s 💰%s"):format(tonumber(data.Wave) or 0, gems, formatNumber(tonumber(data.Money) or 0), heal), { Color = THEME.BuyHighlight, Key = "WaveCleared" })
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
			ctx.current = nil
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
			elseif type(data) == "table" and data.Kind == "Split" and typeof(data.Position) == "Vector3" then
				splitFx(data.Position, data.Names)
			end
		elseif kind == "Chest" then
			WaveChest.show(data) -- cofre de victoria de las mazmorras
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
		if ctx.cardData and typeof(ctx.cardData.EndsAt) == "number" then
			local fraction = math.clamp((ctx.cardData.EndsAt - serverNow()) / WaveConfig.CardSeconds, 0, 1)
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

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	BOSS_RED = context.BOSS_RED
	STREAK_MIN = context.STREAK_MIN
	THEME = context.THEME
	player = context.player
end

return Part
