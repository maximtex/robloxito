-- CombatController · Input: arranque de remotes, sonidos, animaciones y controles de ataque, magia y bloqueo.
-- Parte de CombatController (ver CombatController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local CombatConfig = require(Shared.Config.CombatConfig)
local StyleConfig = require(Shared.Config.StyleConfig)
local CharacterPose = require(script.Parent.Parent.CharacterPose)
local AimPoint = require(script.Parent.Parent.AimPoint)
local AimCamera = require(script.Parent.Parent.AimCamera)
local StyleAnimations = require(script.Parent.Parent.StyleAnimations)
local MagicLogic = require(Shared.MagicLogic)

local ctx: any -- tabla de estado compartida (la crea CombatController/init.luau)
local ATTACK_ACTION: any
local REPEAT_SECONDS: any
local TAP_MOVE: any
local TAP_SECONDS: any
local player: any

-- Funciones de las otras partes
local function buildGui(...) return ctx.buildGui(...) end
local function fxPart(...) return ctx.fxPart(...) end
local function makeSound(...) return ctx.makeSound(...) end
local function playStyleSound(...) return ctx.playStyleSound(...) end

local Part = { Api = {} }

function Part.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local attackRemote = remotes:WaitForChild(Constants.Remotes.Attack) :: RemoteEvent
	local autoRemote = remotes:WaitForChild(Constants.Remotes.SetAutoFire) :: RemoteEvent
	local rewardRemote = remotes:WaitForChild(Constants.Remotes.CombatReward) :: RemoteEvent

	local existingFx = Workspace:FindFirstChild("ClientCombatFX")
	if existingFx then
		existingFx:Destroy()
	end
	ctx.fxFolder = Instance.new("Folder")
	ctx.fxFolder.Name = "ClientCombatFX"
	ctx.fxFolder.Parent = Workspace

	local ui = buildGui()
	local swingSound = makeSound(CombatConfig.Sounds.Swing, 0.4)
	local hitSound = makeSound(CombatConfig.Sounds.Hit, 0.35)
	local killSound = makeSound(CombatConfig.Sounds.Kill, 0.45)
	local novaSound = makeSound(CombatConfig.Sounds.PetNova, 0.18)
	local bossDefeatSound = makeSound(CombatConfig.Sounds.BossDefeat, 0.3)

	-- Animación de ataque: Id configurado o, si no, la "toolslash" del script Animate del
	-- propio personaje. No se crea ni se cambia nada del avatar; si no hay, no pasa nada.
	local function findAttackAnimation(character: Model): Animation?
		local id = CombatConfig.AttackAnimationId
		if id then
			local animation = Instance.new("Animation")
			animation.AnimationId = id
			return animation
		end
		if CombatConfig.UseAvatarSlashAnimation then
			local animate = character:WaitForChild("Animate", 5)
			local slash = animate and animate:FindFirstChild("toolslash")
			local animation = slash and slash:FindFirstChildWhichIsA("Animation")
			if animation and animation.AnimationId ~= "" then
				return animation
			end
		end
		return nil
	end

	local function loadAnimation(character: Model)
		ctx.animationTrack = nil
		local humanoid = character:WaitForChild("Humanoid", 5)
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		local animation = findAttackAnimation(character)
		if animator and animation then
			local ok, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Action
				ctx.animationTrack = track
			end
		end
	end
	player.CharacterAdded:Connect(loadAnimation)
	if player.Character then
		task.spawn(loadAnimation, player.Character)
	end

	local styleActionRemote = remotes:WaitForChild(Constants.Remotes.StyleAction) :: RemoteEvent

	-- Estilo de pelea ahora
	local function styleNow(): string
		local value = player:GetAttribute(Constants.Attributes.CombatStyle)
		return if typeof(value) == "string" and StyleConfig.Styles[value] then value else "Weapons"
	end
	local function isMelee(style: string): boolean
		return style == "Warrior" or style == "Fists"
	end

	-- Cada aviso lleva el punto al que apuntas (AimPoint) y qué haces: "Shot" (un golpe),
	-- "Hold" (sigues pulsando; "Release" al soltar), "Aim" (solo apuntas, para el automático) o
	-- "Charge" (cargas un orbe). Los cambios de estado (apuntar, bloquear, recargar) van sin
	-- punto (signal).
	local function send(aim: Vector3?, mode: string): boolean
		if not aim then
			return false
		end
		attackRemote:FireServer(aim, mode)
		return true
	end
	local function signal(mode: string)
		attackRemote:FireServer(nil, mode)
	end
	local function mouseAim(): Vector3?
		return AimPoint.mouse()
	end
	local function facingAim(): Vector3?
		return AimPoint.facing()
	end
	-- Cuerpo a cuerpo (Guerrero y Puños): al bicho más cercano a tu alcance (sin mira)
	local function meleeAim(): Vector3?
		local def = StyleConfig.Styles[styleNow()]
		return AimPoint.melee((def and def.Range) or 9)
	end
	local function styledAim(aimFn: () -> Vector3?): () -> Vector3?
		return function()
			if isMelee(styleNow()) then
				return meleeAim()
			end
			return aimFn()
		end
	end

	-- Mientras mantienes pulsado, el personaje mira hacia donde ataca (y camina de lado); al
	-- soltar vuelve a girar solo hacia donde anda.
	local turnConnection: RBXScriptConnection? = nil
	local turnAim: (() -> Vector3?)? = nil
	local function setTurning(aimFn: (() -> Vector3?)?)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		turnAim = aimFn
		if aimFn and not turnConnection then
			if humanoid then
				humanoid.AutoRotate = false
			end
			turnConnection = RunService.RenderStepped:Connect(function()
				if turnAim then
					AimPoint.faceToward(turnAim())
				end
			end)
		elseif not aimFn and turnConnection then
			turnConnection:Disconnect()
			turnConnection = nil
			if humanoid and not AimCamera.isAds() then
				humanoid.AutoRotate = true
			end
		end
	end

	-- Mantener pulsado: el primer aviso es un golpe y luego "Hold" mientras no se suelte lo que
	-- lo empezó (el botón del ratón o la acción de F / X / ⚔). Solo una repetición a la vez.
	local function startHold(by: any, aimFn: () -> Vector3?, turn: boolean)
		local current = { By = by }
		ctx.hold = current
		local aim = aimFn()
		if turn then
			AimPoint.faceToward(aim)
			setTurning(aimFn)
		else
			setTurning(nil)
		end
		if send(aim, "Shot") and ctx.animationTrack and isMelee(styleNow()) then
			ctx.animationTrack:Play()
		end
		task.spawn(function()
			while true do
				task.wait(REPEAT_SECONDS)
				if ctx.hold ~= current then
					return
				end
				send(aimFn(), "Hold")
			end
		end)
	end
	local function stopHold(by: any)
		if ctx.hold and ctx.hold.By == by then
			ctx.hold = nil
			setTurning(nil)
			signal("Release")
		end
	end

	-- Magia: clic corto = bola; mantener = cargar un orbe que crece en el bastón (al soltar sale)
	local magicSpec = StyleConfig.Styles.Magic
	local chargeOrb: Part? = nil
	local chargeStarted = 0
	local function stopChargeOrb()
		if chargeOrb then
			chargeOrb:Destroy()
			chargeOrb = nil
		end
		StyleAnimations.charging(false)
	end
	local function startChargeOrb()
		stopChargeOrb()
		local element = MagicLogic.elementDef(MagicLogic.element(player:GetAttribute(Constants.Attributes.EquippedWeapon)))
		local orb = fxPart(Vector3.one * 0.6, CFrame.new(), element.Color or Color3.new(1, 1, 1))
		orb.Shape = Enum.PartType.Ball
		orb.Transparency = 0.15
		local light = Instance.new("PointLight")
		light.Color = element.Color or Color3.new(1, 1, 1)
		light.Range = 10
		light.Brightness = 2
		light.Parent = orb
		chargeOrb = orb
		chargeStarted = os.clock() - magicSpec.Charge.MinHold
		playStyleSound("Charge", nil)
	end
	RunService.RenderStepped:Connect(function()
		if chargeOrb then
			local character = player.Character
			local at = CharacterPose.gearPoint(character, "Orb") or CharacterPose.handPosition(character)
			if at then
				local fraction = math.clamp((os.clock() - chargeStarted) / magicSpec.Charge.Full, 0, 1)
				chargeOrb.Size = Vector3.one * (0.6 + 2.8 * fraction)
				chargeOrb.CFrame = CFrame.new(at)
				chargeOrb.Transparency = if fraction >= 1 then 0.05 + math.abs(math.sin(os.clock() * 10)) * 0.25 else 0.15
			end
		end
	end)
	local function magicDown(by: any, aimFn: () -> Vector3?)
		local press = { By = by, Charging = false, Aim = aimFn }
		ctx.magicPress = press
		task.delay(magicSpec.Charge.MinHold, function()
			if ctx.magicPress == press then
				press.Charging = true
				send(aimFn() or facingAim(), "Charge")
				startChargeOrb()
				setTurning(aimFn)
				if StyleAnimations.enabled("Magic") then
					StyleAnimations.charging(true)
				else
					CharacterPose.cast(player.Character, magicSpec.Charge.Full)
				end
			end
		end)
	end
	local function magicUp(by: any)
		local press = ctx.magicPress
		if not (press and press.By == by) then
			return
		end
		ctx.magicPress = nil
		local aim = press.Aim() or facingAim()
		AimPoint.faceToward(aim)
		if press.Charging then
			stopChargeOrb()
			setTurning(nil)
			send(aim, "Release")
		else
			send(aim, "Shot")
		end
	end

	-- Atacar con lo que empieza el golpe (`by`) hacia `aimFn`, según el estilo
	local function attackDown(by: any, aimFn: () -> Vector3?, turn: boolean)
		local style = styleNow()
		if style == "Magic" then
			magicDown(by, aimFn)
			return
		end
		startHold(by, styledAim(aimFn), turn or isMelee(style))
	end
	local function attackUp(by: any)
		magicUp(by)
		stopHold(by)
	end
	player.CharacterAdded:Connect(function()
		ctx.hold = nil
		ctx.magicPress = nil
		stopChargeOrb()
		setTurning(nil)
	end)

	-- Clic derecho (o L2, o el botón 🛡️): apuntar con Armas, bloquear con Guerrero; con Magia,
	-- un clic derecho corto es el teletransporte (mantenerlo sigue girando la cámara).
	local function blink(aim: Vector3?)
		styleActionRemote:FireServer("Blink", aim or facingAim())
	end
	local function altDown(fromPad: boolean)
		local style = styleNow()
		if ctx.altHeld then
			return
		end
		if style == "Weapons" then
			ctx.altHeld = "Ads"
			AimCamera.setAds(true)
			signal("AdsOn")
		elseif style == "Warrior" then
			ctx.altHeld = "Block"
			AimCamera.setSlow(StyleConfig.Styles.Warrior.Block.WalkSpeed)
			signal("BlockOn")
		elseif style == "Magic" and fromPad then
			blink(facingAim())
		end
	end
	local function altUp()
		if ctx.altHeld == "Ads" then
			AimCamera.setAds(false)
			signal("AdsOff")
		elseif ctx.altHeld == "Block" then
			AimCamera.setSlow(1)
			signal("BlockOff")
		end
		ctx.altHeld = nil
	end
	player:GetAttributeChangedSignal(Constants.Attributes.CombatStyle):Connect(function()
		altUp()
		ctx.magicPress = nil
		stopChargeOrb()
	end)
	player.CharacterAdded:Connect(altUp)

	-- F con ratón: hacia el cursor. X del mando y el botón táctil ⚔: hacia donde mira.
	ContextActionService:BindAction(ATTACK_ACTION, function(_, inputState, input)
		if inputState == Enum.UserInputState.Begin then
			local withMouse = input.UserInputType == Enum.UserInputType.Keyboard and UserInputService.MouseEnabled
			attackDown(ATTACK_ACTION, if withMouse then mouseAim else facingAim, withMouse)
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			attackUp(ATTACK_ACTION)
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle(ATTACK_ACTION, "⚔")
	ContextActionService:SetPosition(ATTACK_ACTION, UDim2.new(1, -170, 1, -150))
	-- El botón "Disparar" de la pantalla: hacia donde mira el personaje (el cursor está encima
	-- del botón)
	ui.Button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			attackDown(Enum.UserInputType.MouseButton1, facingAim, false)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			attackDown(input, facingAim, false)
		end
	end)

	-- En el mundo: clic (hacia el cursor) o toque corto (hacia el dedo; arrastrar es para la
	-- cámara y no ataca); clic derecho y L2 (ver arriba)
	local taps: { [InputObject]: { At: number, Position: Vector3 } } = {}
	local rightPress: { At: number }? = nil
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.KeyCode == Enum.KeyCode.ButtonL2 then
			altDown(true)
			return
		end
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			attackDown(Enum.UserInputType.MouseButton1, mouseAim, true)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			rightPress = { At = os.clock() }
			altDown(false)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			taps[input] = { At = os.clock(), Position = input.Position }
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.ButtonL2 then
			altUp()
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			attackUp(Enum.UserInputType.MouseButton1)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			local press = rightPress
			rightPress = nil
			if ctx.altHeld then
				altUp()
			elseif press and styleNow() == "Magic" and os.clock() - press.At <= TAP_SECONDS then
				-- Clic derecho corto con Magia: teletransporte hacia el cursor
				blink(mouseAim())
			end
		elseif input.UserInputType == Enum.UserInputType.Touch then
			attackUp(input)
			local tap = taps[input]
			taps[input] = nil
			if tap and os.clock() - tap.At <= TAP_SECONDS and (input.Position - tap.Position).Magnitude <= TAP_MOVE then
				local aim = if isMelee(styleNow()) then meleeAim() else AimPoint.fromScreen(input.Position.X, input.Position.Y)
				AimPoint.faceToward(aim)
				send(aim, "Shot")
			end
		end
	end)

	-- Bloquear en pantallas táctiles (Guerrero): botón 🛡️ que se mantiene
	local BLOCK_ACTION = "RebirthBlock"
	local function refreshBlockButton()
		ContextActionService:UnbindAction(BLOCK_ACTION)
		if styleNow() == "Warrior" then
			ContextActionService:BindAction(BLOCK_ACTION, function(_, inputState)
				if inputState == Enum.UserInputState.Begin then
					altDown(true)
				elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
					altUp()
				end
				return Enum.ContextActionResult.Sink
			end, true)
			ContextActionService:SetTitle(BLOCK_ACTION, "🛡️")
			ContextActionService:SetPosition(BLOCK_ACTION, UDim2.new(1, -250, 1, -110))
		end
	end
	player:GetAttributeChangedSignal(Constants.Attributes.CombatStyle):Connect(refreshBlockButton)
	refreshBlockButton()

	ctx.autoRemote = autoRemote
	ctx.bossDefeatSound = bossDefeatSound
	ctx.hitSound = hitSound
	ctx.isMelee = isMelee
	ctx.killSound = killSound
	ctx.meleeAim = meleeAim
	ctx.novaSound = novaSound
	ctx.remotes = remotes
	ctx.rewardRemote = rewardRemote
	ctx.send = send
	ctx.signal = signal
	ctx.styleNow = styleNow
	ctx.swingSound = swingSound
	ctx.ui = ui
end

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	ATTACK_ACTION = context.ATTACK_ACTION
	REPEAT_SECONDS = context.REPEAT_SECONDS
	TAP_MOVE = context.TAP_MOVE
	TAP_SECONDS = context.TAP_SECONDS
	player = context.player
end

return Part
