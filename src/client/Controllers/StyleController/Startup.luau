-- StyleController · Startup: arranque (start): remotes, botones, teclas Z/X/Shift, recargas y recepción de StyleEvent.
-- Parte de StyleController (ver StyleController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local StyleConfig = require(Shared.Config.StyleConfig)
local StyleLogic = require(Shared.StyleLogic)
local SkillLogic = require(Shared.SkillLogic)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)
local Toasts = require(script.Parent.Parent.Parent.UI.Toasts)
local PanelManager = require(script.Parent.Parent.Parent.UI.PanelManager)
local CombatController = require(script.Parent.Parent.CombatController)
local AimPoint = require(script.Parent.Parent.AimPoint)

local ctx: any -- tabla de estado compartida (la crea StyleController/init.luau)
local Api = {} -- funciones públicas de esta parte (init.luau las copia a StyleController)
local ABILITY_ACTIONS: any
local ABILITY_FACING: any
local ABILITY_KEYS: any
local ATTACK_BUTTON: any
local BUTTON_SIZE: any
local DASH_ACTION: any
local EDGE: any
local GAP: any
local PANEL_ACTION: any
local PANEL_NAME: any
local PANEL_SIZE: any
local SKILLS_ACTION: any
local THEME: any
local player: any

-- Funciones de las otras partes
local function blackHoleBlastFx(...) return ctx.blackHoleBlastFx(...) end
local function blackHoleFx(...) return ctx.blackHoleFx(...) end
local function blinkFx(...) return ctx.blinkFx(...) end
local function bounce(...) return ctx.bounce(...) end
local function buildButtons(...) return ctx.buildButtons(...) end
local function buildPanel(...) return ctx.buildPanel(...) end
local function burstFx(...) return ctx.burstFx(...) end
local function classMods(...) return ctx.classMods(...) end
local function comboFx(...) return ctx.comboFx(...) end
local function dashFx(...) return ctx.dashFx(...) end
local function equippedSkill(...) return ctx.equippedSkill(...) end
local function grenadeFx(...) return ctx.grenadeFx(...) end
local function grenadeHitFx(...) return ctx.grenadeHitFx(...) end
local function leapFx(...) return ctx.leapFx(...) end
local function lightningFx(...) return ctx.lightningFx(...) end
local function meteorFx(...) return ctx.meteorFx(...) end
local function meteorHitFx(...) return ctx.meteorHitFx(...) end
local function novaFx(...) return ctx.novaFx(...) end
local function pierceFx(...) return ctx.pierceFx(...) end
local function playSound(...) return ctx.playSound(...) end
local function quakeFx(...) return ctx.quakeFx(...) end
local function quickDashFx(...) return ctx.quickDashFx(...) end
local function rageFx(...) return ctx.rageFx(...) end
local function removeTurret(...) return ctx.removeTurret(...) end
local function serverNow(...) return ctx.serverNow(...) end
local function slashWaveFx(...) return ctx.slashWaveFx(...) end
local function styleId(...) return ctx.styleId(...) end
local function turretFx(...) return ctx.turretFx(...) end
local function turretShotFx(...) return ctx.turretShotFx(...) end
local function whirlFx(...) return ctx.whirlFx(...) end
local function whirlHitFx(...) return ctx.whirlHitFx(...) end

-- Arranque ------------------------------------------------------------------------------

function Api.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local actionRemote = remotes:WaitForChild(Constants.Remotes.StyleAction) :: RemoteEvent
	local eventRemote = remotes:WaitForChild(Constants.Remotes.StyleEvent) :: RemoteEvent

	local existingFx = Workspace:FindFirstChild("ClientStyleFX")
	if existingFx then
		existingFx:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientStyleFX"
	folder.Parent = Workspace
	ctx.fxFolder = folder

	local panelUi = buildPanel()
	local hud, buttons, dashUi = buildButtons()
	local first = buttons[1]

	-- Panel
	PanelManager.register(PANEL_NAME, panelUi.Panel)
	UiKit.bindModalLayout(panelUi.ScreenGui, panelUi.PanelScale, PANEL_SIZE, function(position)
		PanelManager.setBasePosition(PANEL_NAME, position)
	end)
	panelUi.Close.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
	end)
	-- Personajes: con clase fija no se cambia de estilo (se crea otro personaje en ⚙️ Ajustes)
	local function fixedStyle(): string?
		local value = player:GetAttribute(Constants.Attributes.FixedStyle)
		return if type(value) == "string" and value ~= "" then value else nil
	end
	local function refreshCards()
		local current = styleId()
		local fixed = fixedStyle()
		for id, card in panelUi.Cards do
			local chosen = id == current
			card.Button.Text = if chosen then "✓ En uso" elseif fixed then "🔒 Otro personaje" else "Elegir"
			card.Button.BackgroundColor3 = if chosen then THEME.Inset else StyleConfig.Styles[id].Color
			card.Stroke.Thickness = if chosen then 5 else 3
			card.Stroke.Transparency = if chosen then 0 else 0.4
		end
	end
	for id, card in panelUi.Cards do
		card.Button.Activated:Connect(function()
			if id ~= styleId() then
				actionRemote:FireServer("Set", id)
			end
		end)
	end
	first.Switch.Activated:Connect(function()
		PanelManager.toggle(PANEL_NAME)
	end)
	local function refreshSwitch()
		local fixed = fixedStyle()
		first.Switch.Visible = fixed == nil
		if fixed and PanelManager.isOpen(PANEL_NAME) then
			PanelManager.close(PANEL_NAME)
		end
		refreshCards()
	end
	player:GetAttributeChangedSignal(Constants.Attributes.FixedStyle):Connect(refreshSwitch)
	refreshSwitch()
	buttons[2].Switch.Activated:Connect(function()
		PanelManager.toggle("Skills")
	end)

	-- Botones: icono, colores y nombre de cada habilidad del estilo actual
	local function refreshButtons()
		local style = styleId()
		local def = StyleConfig.Styles[style]
		local c = def.Color
		for slot, ui in buttons do
			local _, ability, level = equippedSkill(style, slot)
			ui.Button.Text = ability.Icon
			ui.Label.Text = if level > 1 then ("%s Nv.%d"):format(ability.Name, level) else ability.Name
			local tone = if slot == 2 then c:Lerp(Color3.new(0, 0, 0), 0.15) else c
			ui.Gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, tone:Lerp(Color3.new(1, 1, 1), 0.55)),
				ColorSequenceKeypoint.new(0.55, tone),
				ColorSequenceKeypoint.new(1, tone:Lerp(Color3.new(0, 0, 0), 0.35)),
			})
		end
		refreshCards()
		-- 💨 dash (todos) o ✨ teletransporte de Magia. También con teclado (con la tecla Shift
		-- encima), para que se sepa que existe
		dashUi.Frame.Visible = true
		dashUi.Key.Visible = UserInputService.KeyboardEnabled
		dashUi.Button.Text = if style == "Magic" then "✨" else "💨"
		dashUi.Frame.BackgroundColor3 = def.Color
	end
	local lastStyle = styleId()
	player:GetAttributeChangedSignal(Constants.Attributes.CombatStyle):Connect(function()
		refreshButtons()
		local now = styleId()
		if now ~= lastStyle then
			lastStyle = now
			local def = StyleConfig.Styles[now]
			Toasts.show(("%s Estilo: %s"):format(def.Icon, def.DisplayName), { Color = def.Color, Key = "StyleSwitch" })
			for _, ui in buttons do
				bounce(ui.Button, 0.15)
			end
			playSound("Switch")
		end
	end)
	refreshButtons()
	player:GetAttributeChangedSignal(Constants.Attributes.SkillSlots):Connect(refreshButtons)
	player:GetAttributeChangedSignal(Constants.Attributes.Skills):Connect(refreshButtons)

	-- Usar las habilidades (1: Z / R1, 2: X / L1) hacia donde apuntas: con la tecla, el
	-- ratón; con el mando o el botón de la pantalla, delante del personaje
	for slot, ui in buttons do
		local function use(aim: Vector3?)
			if aim then
				AimPoint.faceToward(aim)
			end
			actionRemote:FireServer("Ability", slot, aim)
		end
		ui.Button.Activated:Connect(function()
			use(AimPoint.facing(ABILITY_FACING))
		end)
		ContextActionService:BindAction(ABILITY_ACTIONS[slot], function(_, inputState, input)
			if inputState == Enum.UserInputState.Begin then
				local withMouse = input.UserInputType == Enum.UserInputType.Keyboard and UserInputService.MouseEnabled
				use(if withMouse then AimPoint.mouse() else AimPoint.facing(ABILITY_FACING))
			end
			return Enum.ContextActionResult.Pass
		end, false, table.unpack(ABILITY_KEYS[slot]))
	end
	ContextActionService:BindAction(PANEL_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			if fixedStyle() then
				Toasts.show("🔒 Este personaje tiene su clase. Crea otro en ⚙️ Ajustes → Personajes", { Color = THEME.Error, Key = "StyleNotice" })
			else
				PanelManager.toggle(PANEL_NAME)
			end
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.C)
	ContextActionService:BindAction(SKILLS_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			PanelManager.toggle("Skills")
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.B)
	-- Dash (todos; el de Puños es mejor) o teletransporte de Magia (Shift, el stick izquierdo
	-- pulsado del mando o el botón 💨 / ✨). El teletransporte va hacia donde andas; quieto,
	-- hacia el ratón.
	local function tryDash()
		local style = styleId()
		if StyleLogic.dashSpec(style) then
			actionRemote:FireServer("Dash")
		elseif style == "Magic" then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local moving = humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0.1
			local pointer = UserInputService.MouseEnabled and UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch
			actionRemote:FireServer("Blink", if not moving and pointer then AimPoint.mouse() else nil)
		end
	end
	ContextActionService:BindAction(DASH_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			tryDash()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	dashUi.Button.Activated:Connect(tryDash)

	-- Al lado de las habilidades elementales (Q y R, las que se vean: con solo Naturaleza no
	-- hay ninguna), o encima en táctil; la segunda a la izquierda de la primera
	local abilityHud = player:WaitForChild("PlayerGui"):WaitForChild("AbilityHud", 15)
	local primary = abilityHud and abilityHud:FindFirstChild("AbilityButton") :: GuiObject?
	local secondary = abilityHud and abilityHud:FindFirstChild("SecondaryButton") :: GuiObject?
	local function place()
		local uiScale = UiKit.computeScale(hud.AbsoluteSize)
		local slots = (if primary == nil or primary.Visible then 1 else 0) + (if secondary and secondary.Visible then 1 else 0)
		local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		-- Margen extra respecto al botón de ataque para no rozar su insignia "🔒 AUTO" (a -10 px)
		local attackSpan = ATTACK_BUTTON + GAP + (if slots == 0 then 14 else 0)
		for slot, ui in buttons do
			local shift = (slot - 1) * (BUTTON_SIZE + GAP)
			if touchOnly then
				ui.Frame.Position = UDim2.new(1, -(EDGE + shift * uiScale), 0.5, -(76 + slots * (BUTTON_SIZE + 26)) * uiScale)
			else
				ui.Frame.Position = UDim2.new(1, -(EDGE + (attackSpan + slots * (BUTTON_SIZE + GAP) + shift) * uiScale), 1, -34)
			end
		end
		-- 💨 a la izquierda de los dos botones del estilo
		local dashShift = 2 * (BUTTON_SIZE + GAP)
		if touchOnly then
			dashUi.Frame.Position = UDim2.new(1, -(EDGE + dashShift * uiScale), 0.5, -(76 + slots * (BUTTON_SIZE + 26) + 7) * uiScale)
		else
			dashUi.Frame.Position = UDim2.new(1, -(EDGE + (attackSpan + slots * (BUTTON_SIZE + GAP) + dashShift) * uiScale), 1, -41)
		end
	end
	hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	UiKit.onScaleChanged(place) -- ⚙️ tamaño de la interfaz
	UserInputService.LastInputTypeChanged:Connect(place)
	if secondary then
		secondary:GetPropertyChangedSignal("Visible"):Connect(place)
	end
	if primary then
		primary:GetPropertyChangedSignal("Visible"):Connect(place)
	end
	place()

	-- Recargas (hora del servidor en que vuelve a estar lista cada una)
	local READY_ATTRIBUTES = { Constants.Attributes.StyleReadyAt, Constants.Attributes.StyleReadyAt2 }
	RunService.Heartbeat:Connect(function()
		local style = styleId()
		for slot, ui in buttons do
			local _, ability, level = equippedSkill(style, slot)
			local total = SkillLogic.cooldown(ability, level) * classMods(style).SkillCooldown
			local readyAt = player:GetAttribute(READY_ATTRIBUTES[slot])
			local left = if typeof(readyAt) == "number" then readyAt - serverNow() else 0
			if left > 0 then
				ui.WasCooling = true
				ui.Cooldown.Size = UDim2.fromScale(1, math.clamp(left / total, 0, 1))
				ui.Count.Visible = true
				ui.Count.Text = tostring(math.ceil(left))
				ui.Button.TextTransparency = 0.5
			else
				ui.Cooldown.Size = UDim2.fromScale(1, 0)
				ui.Count.Visible = false
				ui.Button.TextTransparency = 0
				if ui.WasCooling then
					ui.WasCooling = false
					bounce(ui.Button, 0.12)
					playSound("Ready")
				end
			end
		end
		-- Recarga del dash
		if dashUi.Frame.Visible then
			local dashAt = player:GetAttribute(Constants.Attributes.DashReadyAt)
			local left = if typeof(dashAt) == "number" then dashAt - serverNow() else 0
			local style = styleId()
			local spec = StyleLogic.dashSpec(style)
			local total = if spec then spec.Cooldown * classMods(style).DashCooldown else StyleConfig.Styles.Magic.Blink.Cooldown
			dashUi.Cooldown.Size = UDim2.fromScale(1, if left > 0 then math.clamp(left / total, 0, 1) else 0)
		end
	end)

	-- Efectos y resultados
	eventRemote.OnClientEvent:Connect(function(event: any)
		if typeof(event) ~= "table" or typeof(event.Owner) ~= "Instance" then
			return
		end
		local owner = event.Owner :: Player
		ctx.tint = if typeof(event.Color) == "Color3" then event.Color else nil
		if event.Kind == "Result" then
			if owner ~= player then
				return
			end
			if typeof(event.Action) == "string" and string.find(event.Action, "Skill") then
				return -- comprar, subir y poner: SkillsController
			end
			local ui = buttons[if event.Slot == 2 then 2 else 1]
			if event.Success == false then
				if event.Code == "NoTarget" then
					Toasts.show("🎯 Apunta a un enemigo (a tu alcance)", { Color = THEME.Error, Key = "StyleNotice" })
				elseif event.Code == "NoMana" then
					Toasts.show("💧 Te falta maná", { Color = Color3.fromRGB(120, 150, 255), Key = "StyleNotice" })
					if event.Action ~= "Blink" then
						bounce(ui.Button, -0.08)
					end
				elseif event.Code == "NotReady" then
					bounce(ui.Button, -0.08)
				elseif event.Code == "Locked" then
					Toasts.show("🔒 Este personaje tiene su clase. Crea otro en ⚙️ Ajustes → Personajes", { Color = THEME.Error, Key = "StyleNotice" })
				end
			elseif event.Action ~= "Set" and event.Action ~= "Blink" then
				bounce(ui.Button, 0.18)
			end
		elseif event.Kind == "Burst" then
			burstFx(owner, tonumber(event.Duration) or 4)
		elseif event.Kind == "Grenade" and typeof(event.From) == "Vector3" and typeof(event.To) == "Vector3" then
			grenadeFx(owner, event.From, event.To, tonumber(event.Delay) or 0.7, tonumber(event.Radius) or 10)
		elseif event.Kind == "GrenadeHit" and typeof(event.Position) == "Vector3" then
			grenadeHitFx(owner, event.Position, tonumber(event.Radius) or 10, event.Hits)
		elseif event.Kind == "Quake" and typeof(event.Position) == "Vector3" then
			quakeFx(owner, event.Position, tonumber(event.Radius) or 14, event.Hits)
		elseif event.Kind == "Dash" and typeof(event.From) == "Vector3" and typeof(event.To) == "Vector3" then
			dashFx(owner, event.From, event.To, event.Hits)
		elseif event.Kind == "Meteor" then
			meteorFx(owner, event.Points, tonumber(event.Delay) or 0.6, tonumber(event.Interval) or 0.2, tonumber(event.Radius) or 7, tonumber(event.StartAt) or serverNow())
		elseif event.Kind == "MeteorHit" and typeof(event.Position) == "Vector3" then
			meteorHitFx(owner, event.Position, tonumber(event.Radius) or 7, event.Hits)
		elseif event.Kind == "Nova" and typeof(event.Position) == "Vector3" then
			novaFx(owner, event.Position, tonumber(event.Radius) or 16, event.Hits, event.Frozen)
		elseif event.Kind == "Pierce" and typeof(event.From) == "Vector3" and typeof(event.To) == "Vector3" then
			pierceFx(owner, event.From, event.To, tonumber(event.Width) or 5, event.Hits)
		elseif event.Kind == "Turret" and typeof(event.Position) == "Vector3" then
			turretFx(owner, event.Position, tonumber(event.Duration) or 8)
		elseif event.Kind == "TurretShot" and typeof(event.From) == "Vector3" and typeof(event.To) == "Vector3" then
			turretShotFx(owner, event.From, event.To, event.Hits)
		elseif event.Kind == "TurretEnd" then
			removeTurret(owner)
		elseif event.Kind == "Rage" then
			rageFx(owner, tonumber(event.Duration) or 6)
		elseif event.Kind == "Whirl" then
			whirlFx(owner, tonumber(event.Radius) or 11, tonumber(event.Pulses) or 4, tonumber(event.Interval) or 0.3)
		elseif event.Kind == "WhirlHit" and typeof(event.Position) == "Vector3" then
			whirlHitFx(owner, event.Position, tonumber(event.Radius) or 11, event.Hits)
		elseif event.Kind == "Lightning" then
			lightningFx(owner, event.Points, event.Hits)
		elseif event.Kind == "BlackHole" and typeof(event.Position) == "Vector3" then
			blackHoleFx(owner, event.Position, tonumber(event.Radius) or 14, tonumber(event.Duration) or 3)
		elseif event.Kind == "BlackHoleTick" then
			CombatController.showHits(event.Hits, ctx.tint or StyleConfig.Styles.Magic.Color, owner == player, 0.7)
		elseif event.Kind == "BlackHoleBlast" and typeof(event.Position) == "Vector3" then
			blackHoleBlastFx(owner, event.Position, tonumber(event.Radius) or 14, event.Hits)
		elseif event.Kind == "QuickDash" and typeof(event.From) == "Vector3" and typeof(event.To) == "Vector3" then
			quickDashFx(owner, event.From, event.To)
		elseif event.Kind == "Leap" and typeof(event.From) == "Vector3" and typeof(event.To) == "Vector3" then
			leapFx(owner, event.From, event.To, tonumber(event.Delay) or 0.55, tonumber(event.Radius) or 13)
		elseif event.Kind == "SlashWave" and typeof(event.From) == "Vector3" and typeof(event.To) == "Vector3" then
			slashWaveFx(owner, event.From, event.To, tonumber(event.Width) or 7, event.Hits)
		elseif event.Kind == "Blink" and typeof(event.From) == "Vector3" and typeof(event.To) == "Vector3" then
			blinkFx(owner, event.From, event.To)
		elseif event.Kind == "Combo" and typeof(event.Name) == "string" and typeof(event.Position) == "Vector3" then
			comboFx(owner, event.Name, event.Position, if typeof(event.Style) == "string" then event.Style else nil)
		end
		ctx.tint = nil
	end)
end

local Part = { Api = Api }

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	ABILITY_ACTIONS = context.ABILITY_ACTIONS
	ABILITY_FACING = context.ABILITY_FACING
	ABILITY_KEYS = context.ABILITY_KEYS
	ATTACK_BUTTON = context.ATTACK_BUTTON
	BUTTON_SIZE = context.BUTTON_SIZE
	DASH_ACTION = context.DASH_ACTION
	EDGE = context.EDGE
	GAP = context.GAP
	PANEL_ACTION = context.PANEL_ACTION
	PANEL_NAME = context.PANEL_NAME
	PANEL_SIZE = context.PANEL_SIZE
	SKILLS_ACTION = context.SKILLS_ACTION
	THEME = context.THEME
	player = context.player
end

return Part
