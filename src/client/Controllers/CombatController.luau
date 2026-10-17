-- Combate en el cliente (solo presentación y entrada; el servidor decide todo):
-- - Atacar con F, X (mando), el botón táctil o el botón de pantalla. Cooldown visual.
-- - Tajo mágico al atacar (es el golpe, no el impacto). Los impactos (destello en el
--   enemigo, chispas, número de daño, sonido) SOLO se muestran cuando el servidor los
--   confirma en AttackResult; si confirma que no hubo impacto, una nubecilla discreta.
-- - Animación: la propia del avatar ("toolslash" de su script Animate) o una configurada.
-- - Avisos de energía ganada bajo la tarjeta de energía y anuncio al derrotar a un jefe.
-- - Barra de vida grande del jefe al acercarse a su arena.
-- - Mascotas de combate: rayo del Zorrito, nova del Dragón (con aviso y recarga visible)
--   y escudo de la Tortuga, solo para acciones ya confirmadas por el servidor.
-- Interfaz con DisplayOrder 3: queda por debajo del inventario y los paneles.

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local CombatConfig = require(Shared.Config.CombatConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local formatNumber = require(Shared.Util.FormatNumber)
local CombatMath = require(Shared.CombatMath)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local EnemyAnimator = require(script.Parent.EnemyAnimator)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local LAYOUT = Theme.Layout
local ATTACK_ACTION = "RebirthAttack"
local BOSS_BAR_RANGE = 30 -- distancia extra al borde de la arena para mostrar la barra
local KIND_COLORS = {
	Normal = Color3.fromRGB(255, 244, 214),
	Strong = Color3.fromRGB(255, 200, 110),
	Boss = Color3.fromRGB(255, 140, 140),
}

local BOSS_BAR_COLOR = Color3.fromRGB(230, 90, 100)
local BOSS_ENRAGED_COLOR = Color3.fromRGB(255, 140, 60)
local MAX_DAMAGE_NUMBERS = 14 -- más números a la vez no se leen y cuestan rendimiento
local SOUND_GAP = 0.06 -- el mismo sonido no se repite antes de este intervalo

local CombatController = {}

local player = Players.LocalPlayer
local fxFolder: Folder
local nextAttackAt = 0
local pendingSwings: { { Tip: Vector3, Time: number } } = {}

local function makeSound(id: string?, volume: number): Sound?
	if not id then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Parent = SoundService
	return sound
end

-- Reproduce con una ligera variación de tono y sin solapar copias idénticas seguidas.
local lastPlayed: { [Sound]: number } = {}
local function playVaried(sound: Sound?, pitch: number, variation: number)
	if not sound then
		return
	end
	local now = os.clock()
	if now - (lastPlayed[sound] or 0) < SOUND_GAP then
		return
	end
	lastPlayed[sound] = now
	sound.PlaybackSpeed = pitch * (1 + (math.random() * 2 - 1) * variation)
	sound:Play()
end

local function fxPart(size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	part.Parent = fxFolder
	return part
end

-- Emisores reutilizables: UNA pieza invisible por tipo de efecto, que se mueve al punto
-- y emite una ráfaga. No se crean piezas ni conexiones por partícula ni por golpe.
local POOL_PREFIX = "Pool_"
local emitters: { [string]: ParticleEmitter } = {}

local EMITTER_SETUPS: { [string]: (ParticleEmitter) -> () } = {
	Spark = function(emitter)
		emitter.Lifetime = NumberRange.new(0.18, 0.35)
		emitter.Speed = NumberRange.new(9, 15)
		emitter.Drag = 5
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Size = NumberSequence.new(0.28, 0)
		emitter.LightEmission = 1
	end,
	Glint = function(emitter)
		emitter.Lifetime = NumberRange.new(0.35, 0.6)
		emitter.Speed = NumberRange.new(1.5, 3.5)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.25, 0.55), NumberSequenceKeypoint.new(1, 0) })
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.LightEmission = 1
	end,
	Miss = function(emitter)
		emitter.Lifetime = NumberRange.new(0.3, 0.5)
		emitter.Speed = NumberRange.new(1, 2.5)
		emitter.SpreadAngle = Vector2.new(60, 60)
		emitter.Size = NumberSequence.new(0.4, 1)
		emitter.Transparency = NumberSequence.new(0.65, 1)
		emitter.LightEmission = 0
	end,
	Wisp = function(emitter)
		emitter.Lifetime = NumberRange.new(0.8, 1.3)
		emitter.Speed = NumberRange.new(2, 5)
		emitter.Acceleration = Vector3.new(0, 7, 0)
		emitter.SpreadAngle = Vector2.new(70, 70)
		emitter.Size = NumberSequence.new(0.45, 0)
		emitter.Transparency = NumberSequence.new(0.1, 1)
		emitter.LightEmission = 1
	end,
}

local function emitAt(kind: string, position: Vector3, color: Color3, amount: number)
	local emitter = emitters[kind]
	if not (emitter and emitter.Parent and emitter.Parent.Parent == fxFolder) then
		local holder = fxPart(Vector3.one * 0.2, CFrame.new(position), Color3.new(1, 1, 1))
		holder.Name = POOL_PREFIX .. kind
		holder.Transparency = 1
		emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 0
		EMITTER_SETUPS[kind](emitter)
		emitter.Parent = holder
		emitters[kind] = emitter
	end
	local ready = emitter :: ParticleEmitter
	(ready.Parent :: BasePart).CFrame = CFrame.new(position)
	ready.Color = ColorSequence.new(color)
	ready:Emit(amount)
end

-- Tajo mágico: arco de hojas de luz que barre de derecha a izquierda (dorado -> turquesa)
-- y se desvanece. Sin tareas ni bucles: cada hoja tiene dos tweens con retardo.
-- Devuelve el punto central del arco (donde se marca un fallo si no hay impacto).
local SLASH_BLADES = 9
local SLASH_FROM = THEME.Gold
local SLASH_TO = Color3.fromRGB(120, 236, 206)
local function slashEffect(root: BasePart): Vector3
	local base = root.CFrame * CFrame.new(0, 0.5, 0)
	for index = 0, SLASH_BLADES - 1 do
		local t = index / (SLASH_BLADES - 1)
		local angle = 0.95 - 1.9 * t
		local height = 0.7 - 1.2 * t
		local position = (base * CFrame.Angles(0, angle, 0) * CFrame.new(0, height, -3.4)).Position
		local blade = fxPart(Vector3.new(1.05, 0.08, 0.22), CFrame.lookAt(position, base.Position + Vector3.new(0, height, 0)) * CFrame.Angles(0, math.rad(90), math.rad(-18)), SLASH_FROM:Lerp(SLASH_TO, t))
		blade.Transparency = 1
		TweenService:Create(blade, TweenInfo.new(0.04, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, index * 0.012), { Transparency = 0.05 }):Play()
		TweenService:Create(blade, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.06 + index * 0.012), { Transparency = 1, Size = Vector3.new(1.3, 0.03, 0.08) }):Play()
		Debris:AddItem(blade, 0.45)
	end
	return (base * CFrame.new(0, 0.1, -3.4)).Position
end

-- Reacción del enemigo al recibir daño: destello blanco breve con un Highlight local
-- reutilizado por modelo. No mueve sus piezas, así que no interfiere con su IA.
local flashes: { [Model]: Highlight } = setmetatable({}, { __mode = "k" }) :: any
local function flashEnemy(model: Model, color: Color3)
	if not model.Parent then
		return
	end
	local highlight = flashes[model]
	if not (highlight and highlight.Parent == model) then
		highlight = Instance.new("Highlight")
		highlight.Name = "HitFlash"
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.OutlineTransparency = 1
		highlight.Enabled = false
		highlight.Parent = model
		flashes[model] = highlight
	end
	local current = highlight :: Highlight
	current.FillColor = color
	current.FillTransparency = 0.2
	current.Enabled = true
	local tween = TweenService:Create(current, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FillTransparency = 1 })
	tween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			current.Enabled = false -- apagado: no ocupa el límite de Highlights visibles
		end
	end)
	tween:Play()
end

-- Número de daño: aparece con un pequeño "pop", sube y se desvanece en 0.7 s.
-- Como mucho MAX_DAMAGE_NUMBERS a la vez: el más antiguo se retira antes de tiempo.
local liveNumbers: { BasePart } = {}
local function damageNumber(position: Vector3, amount: number, color: Color3, killed: boolean, big: boolean?)
	for index = #liveNumbers, 1, -1 do
		if liveNumbers[index].Parent == nil then
			table.remove(liveNumbers, index)
		end
	end
	while #liveNumbers >= MAX_DAMAGE_NUMBERS do
		table.remove(liveNumbers, 1):Destroy()
	end
	local anchor = fxPart(Vector3.one * 0.1, CFrame.new(position + Vector3.new(math.random(-8, 8) / 10, 2.4, math.random(-8, 8) / 10)), color)
	anchor.Transparency = 1
	table.insert(liveNumbers, anchor)
	local size = if killed then Vector2.new(150, 48) elseif big then Vector2.new(118, 40) else Vector2.new(96, 34)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(size.X * 1.3, size.Y * 1.3)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = FONTS.Display
	label.TextScaled = true
	label.TextColor3 = if killed then THEME.Gold else color
	label.TextStrokeColor3 = Color3.fromRGB(20, 26, 22)
	label.TextStrokeTransparency = 0.15
	label.Text = (if killed then "✦ " else "") .. formatNumber(amount, 1)
	label.Parent = billboard
	billboard.Parent = anchor
	TweenService:Create(billboard, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(size.X, size.Y) }):Play()
	TweenService:Create(billboard, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 2.2, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.35), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 0.8)
end

-- Limpia los efectos temporales (al morir o cambiar de zona); conserva los emisores.
local function clearTransientEffects()
	for _, child in fxFolder:GetChildren() do
		if child.Name:sub(1, #POOL_PREFIX) ~= POOL_PREFIX then
			child:Destroy()
		end
	end
	table.clear(liveNumbers)
	EnemyAnimator.clearEffects()
end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("CombatHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "CombatHud",
		ResetOnSpawn = false,
		DisplayOrder = 3, -- por debajo de inventario (5) y portal (6)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)

	-- Botón de ataque (abajo a la derecha, lejos del panel de mejoras del centro)
	local buttonFrame, buttonScale = UiKit.panel(screenGui, "AttackButton", Vector2.new(96, 96), Vector2.new(1, 1), UDim2.new(1, -20, 1, -24))
	buttonFrame:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0)
	local cooldown = UiKit.create("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = THEME.Overlay,
		BackgroundTransparency = 0.35,
		ZIndex = 2,
	}, buttonFrame)
	UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, cooldown)
	local button = UiKit.create("TextButton", {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = FONTS.Display,
		TextSize = 40,
		TextColor3 = THEME.Text,
		Text = "⚔",
		ZIndex = 3,
	}, buttonFrame)
	UiKit.addStates(button)
	UiKit.text(buttonFrame, "Hint", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.fromOffset(60, 16),
		Font = FONTS.Light,
		TextSize = 13,
		TextColor3 = THEME.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "F",
		ZIndex = 3,
	})

	-- Barra del jefe y avisos: justo debajo de la tarjeta de energía.
	local top = UiKit.create("Frame", {
		Name = "TopArea",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 148),
		Size = UDim2.fromOffset(440, 160),
		BackgroundTransparency = 1,
	}, screenGui)
	local topScale = UiKit.create("UIScale", {}, top)
	local bossBar, _ = UiKit.panel(top, "BossBar", Vector2.new(440, 54), Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0))
	bossBar.Visible = false
	local bossName = UiKit.text(bossBar, "Name", {
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.new(1, -32, 0, 20),
		Font = FONTS.Display,
		TextSize = 18,
	})
	local bossTrack = UiKit.create("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(16, 30),
		Size = UDim2.new(1, -32, 0, 14),
		BackgroundColor3 = THEME.Inset,
	}, bossBar)
	UiKit.corner(bossTrack, 7)
	-- Tramo claro que se vacía con retraso: deja ver cuánto daño acaba de recibir.
	local bossTrail = UiKit.create("Frame", {
		Name = "Trail",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 236, 200),
		BackgroundTransparency = 0.25,
	}, bossTrack)
	UiKit.corner(bossTrail, 7)
	local bossFill = UiKit.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(230, 90, 100),
		ZIndex = 2,
	}, bossTrack)
	UiKit.corner(bossFill, 7)
	-- Marca de la furia (a la mitad de vida, como en EnemyConfig).
	local enrageMark = UiKit.create("Frame", {
		Name = "EnrageMark",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 2, 1, 6),
		BackgroundColor3 = BOSS_ENRAGED_COLOR,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, bossTrack)
	local toasts = UiKit.create("Frame", {
		Name = "Toasts",
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 0, 96),
		BackgroundTransparency = 1,
	}, top)
	UiKit.create("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	}, toasts)

	-- Anuncio de jefe derrotado
	local banner = UiKit.text(screenGui, "BossBanner", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(700, 60),
		Font = FONTS.Display,
		TextSize = 40,
		TextColor3 = THEME.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.2,
		TextTransparency = 1,
		TextStrokeColor3 = Color3.new(0, 0, 0),
	})

	-- Destello suave de pantalla al derrotar a un jefe
	local screenFlash = UiKit.create("Frame", {
		Name = "ScreenFlash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 246, 220),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Active = false,
	}, screenGui)

	screenGui.Parent = playerGui
	UiKit.bindScale(screenGui, { buttonScale, topScale })
	-- La zona superior sigue el borde inferior de la tarjeta de energía.
	local function placeTop()
		local scale = UiKit.computeScale(screenGui.AbsoluteSize)
		top.Position = UDim2.new(0.5, 0, 0, LAYOUT.Margin + LAYOUT.EnergyCardSize.Y * scale + 8)
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeTop)
	placeTop()

	return {
		ButtonFrame = buttonFrame,
		Button = button,
		Cooldown = cooldown,
		BossBar = bossBar,
		BossName = bossName,
		BossFill = bossFill,
		BossTrail = bossTrail,
		EnrageMark = enrageMark,
		Toasts = toasts,
		Banner = banner,
		ScreenFlash = screenFlash,
	}
end

function CombatController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local attackRemote = remotes:WaitForChild(Constants.Remotes.Attack) :: RemoteEvent
	local resultRemote = remotes:WaitForChild(Constants.Remotes.AttackResult) :: RemoteEvent
	local rewardRemote = remotes:WaitForChild(Constants.Remotes.CombatReward) :: RemoteEvent

	local existingFx = Workspace:FindFirstChild("ClientCombatFX")
	if existingFx then
		existingFx:Destroy()
	end
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ClientCombatFX"
	fxFolder.Parent = Workspace

	local ui = buildGui()
	local swingSound = makeSound(CombatConfig.Sounds.Swing, 0.4)
	local hitSound = makeSound(CombatConfig.Sounds.Hit, 0.35)
	local killSound = makeSound(CombatConfig.Sounds.Kill, 0.45)
	local novaSound = makeSound(CombatConfig.Sounds.PetNova, 0.18)
	local bossDefeatSound = makeSound(CombatConfig.Sounds.BossDefeat, 0.3)
	local animationTrack: AnimationTrack? = nil

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
		animationTrack = nil
		local humanoid = character:WaitForChild("Humanoid", 5)
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		local animation = findAttackAnimation(character)
		if animator and animation then
			local ok, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Action
				animationTrack = track
			end
		end
	end
	player.CharacterAdded:Connect(loadAnimation)
	if player.Character then
		task.spawn(loadAnimation, player.Character)
	end

	local function tryAttack()
		local now = os.clock()
		if now < nextAttackAt then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
			return
		end
		nextAttackAt = now + CombatConfig.AttackCooldown
		attackRemote:FireServer() -- sin objetivo ni daño: los decide el servidor
		local tip = slashEffect(root)
		-- Cada golpe enviado recibe un resultado; se emparejan en orden.
		table.insert(pendingSwings, { Tip = tip, Time = now })
		if #pendingSwings > 4 then
			table.remove(pendingSwings, 1)
		end
		if swingSound then
			swingSound:Play()
		end
		if animationTrack then
			animationTrack:Play()
		end
		-- Indicador de recarga del botón
		ui.Cooldown.Size = UDim2.fromScale(1, 1)
		TweenService:Create(ui.Cooldown, TweenInfo.new(CombatConfig.AttackCooldown, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 0) }):Play()
	end

	-- Teclado (F), mando (X) y botón táctil automático en móvil.
	ContextActionService:BindAction(ATTACK_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			tryAttack()
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle(ATTACK_ACTION, "⚔")
	ContextActionService:SetPosition(ATTACK_ACTION, UDim2.new(1, -170, 1, -150))
	ui.Button.Activated:Connect(tryAttack)
	-- En pantallas solo táctiles se usa el botón táctil de Roblox (junto al de saltar).
	local function refreshButtonVisibility()
		ui.ButtonFrame.Visible = not (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	end
	UserInputService.LastInputTypeChanged:Connect(refreshButtonVisibility)
	refreshButtonVisibility()

	-- Resultado CONFIRMADO del golpe: solo aquí se muestran impactos.
	resultRemote.OnClientEvent:Connect(function(hits)
		if typeof(hits) ~= "table" then
			return
		end
		local swing = table.remove(pendingSwings, 1)
		local landed, kills, bossHit = 0, 0, false
		for _, hit in hits do
			if typeof(hit) == "table" and typeof(hit.Position) == "Vector3" and typeof(hit.Damage) == "number" then
				landed += 1
				local killed = hit.Killed == true
				local isBoss = hit.Kind == "Boss"
				kills += if killed then 1 else 0
				bossHit = bossHit or isBoss
				local color = KIND_COLORS[hit.Kind] or KIND_COLORS.Normal
				damageNumber(hit.Position, hit.Damage, color, killed, isBoss)
				-- Golpe normal: chispas; jefe: más chispas y brillo; derrota: estallido y motas.
				emitAt("Spark", hit.Position, color, if killed then 22 elseif isBoss then 12 else 8)
				emitAt("Glint", hit.Position, SLASH_TO, if killed then 10 elseif isBoss then 6 else 3)
				if killed then
					emitAt("Wisp", hit.Position, SLASH_TO, 14) -- la criatura se disuelve en luz
				end
				if typeof(hit.Model) == "Instance" and hit.Model:IsA("Model") then
					flashEnemy(hit.Model, if killed then THEME.Gold else Color3.new(1, 1, 1))
					if not killed then
						EnemyAnimator.react(hit.Model, 1)
					end
				end
			end
		end
		if landed > 0 then
			if kills > 0 and killSound then
				playVaried(killSound, 0.9, 0.05)
			else
				playVaried(hitSound, if bossHit then 1.15 else 1.35, 0.07)
			end
		elseif swing and os.clock() - swing.Time < 1.5 then
			-- Fallo confirmado: una nubecilla discreta donde acabó el tajo, sin texto.
			emitAt("Miss", swing.Tip, Color3.fromRGB(200, 204, 190), 5)
		end
	end)

	-- Mascotas de combate -------------------------------------------------------------
	-- Solo se dibujan acciones que el servidor ya ha resuelto (PetAbility).
	local petAbilityRemote = remotes:WaitForChild(Constants.Remotes.PetAbility) :: RemoteEvent
	local FOX_COLOR = Color3.fromRGB(110, 236, 220)
	local DRAGON_COLOR = Color3.fromRGB(190, 120, 255)
	local GUARD_COLOR = Color3.fromRGB(150, 232, 214)

	-- Posición de la mascota dibujada por PetFollower ("<jugador>_<hueco>_<PetId>").
	local function petPosition(owner: Player, petId: string, index: number): Vector3?
		local pets = Workspace:FindFirstChild("ClientPets")
		if pets then
			local prefix = owner.Name .. "_"
			local matches = {}
			for _, model in pets:GetChildren() do
				if model:IsA("Model") and model.PrimaryPart and model.Name:sub(1, #prefix) == prefix and model.Name:sub(-#petId) == petId then
					table.insert(matches, model)
				end
			end
			table.sort(matches, function(a, b)
				return a.Name < b.Name
			end)
			local model = matches[index] or matches[1]
			if model and model.PrimaryPart then
				return model.PrimaryPart.Position
			end
		end
		local character = owner.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		return if root and root:IsA("BasePart") then root.Position + Vector3.new(0, 2, 0) else nil
	end

	local function showPetHits(hits: any, color: Color3, isOwner: boolean)
		if typeof(hits) ~= "table" then
			return
		end
		for _, hit in hits do
			if typeof(hit) == "table" and typeof(hit.Position) == "Vector3" and typeof(hit.Damage) == "number" then
				local killed = hit.Killed == true
				if isOwner then
					damageNumber(hit.Position, hit.Damage, color, killed)
				end
				emitAt("Spark", hit.Position, color, if killed then 16 else 6)
				if killed then
					emitAt("Wisp", hit.Position, color, 12)
				end
				if typeof(hit.Model) == "Instance" and hit.Model:IsA("Model") then
					flashEnemy(hit.Model, color)
					if not killed then
						EnemyAnimator.react(hit.Model, 0.6)
					end
				end
			end
		end
	end

	-- Indicadores sobre el botón de ataque: recarga del dragón y defensa de la tortuga.
	local chips = UiKit.create("Frame", {
		Name = "PetAbilities",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -130),
		Size = UDim2.fromOffset(140, 60),
		BackgroundTransparency = 1,
	}, ui.ButtonFrame.Parent)
	local chipsScale = UiKit.create("UIScale", {}, chips)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 8),
	}, chips)
	local function makeChip(name: string, icon: string)
		local chip, _ = UiKit.panel(chips, name, Vector2.new(56, 56), Vector2.zero, UDim2.new())
		chip:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0)
		local scale = chip:FindFirstChildOfClass("UIScale")
		if scale then
			scale:Destroy() -- la escala la lleva el contenedor
		end
		local overlay = UiKit.create("Frame", {
			Name = "Cooldown",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = THEME.Overlay,
			BackgroundTransparency = 0.35,
			ZIndex = 2,
		}, chip)
		UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, overlay)
		UiKit.text(chip, "Icon", {
			Size = UDim2.fromScale(1, 1),
			Font = FONTS.Display,
			TextSize = 26,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = icon,
			ZIndex = 3,
		})
		local label = UiKit.text(chip, "Label", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 2),
			Size = UDim2.fromOffset(70, 16),
			Font = FONTS.Light,
			TextSize = 13,
			TextColor3 = THEME.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.5,
			ZIndex = 3,
		})
		chip.Visible = false
		return chip, overlay, label
	end
	local dragonChip, dragonCooldown, dragonLabel = makeChip("DragonChip", "🐉")
	local turtleChip, _, turtleLabel = makeChip("TurtleChip", "🛡")
	dragonLabel.Text = "Nova lista"
	UiKit.bindScale(ui.ButtonFrame.Parent :: ScreenGui, { chipsScale })

	local function equippedCount(petId: string): number
		local value = player:GetAttribute(Constants.Attributes.EquippedPets)
		local count = 0
		if typeof(value) == "string" then
			for _, id in string.split(value, ",") do
				if id == petId then
					count += 1
				end
			end
		end
		return count
	end

	-- Aura discreta de la tortuga: partículas locales en el propio personaje (no cambia
	-- el avatar y desaparece con él).
	local function refreshGuardAura()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		local existing = root:FindFirstChild("GuardAura")
		local turtles = equippedCount("CrystalTurtle")
		if turtles <= 0 then
			if existing then
				existing:Destroy()
			end
			return
		end
		if existing then
			return
		end
		local attachment = Instance.new("Attachment")
		attachment.Name = "GuardAura"
		local motes = Instance.new("ParticleEmitter")
		motes.Rate = 3
		motes.Lifetime = NumberRange.new(1, 1.6)
		motes.Speed = NumberRange.new(0.3, 0.8)
		motes.SpreadAngle = Vector2.new(180, 180)
		motes.Size = NumberSequence.new(0.22, 0)
		motes.Transparency = NumberSequence.new(0.3, 1)
		motes.LightEmission = 1
		motes.Color = ColorSequence.new(GUARD_COLOR)
		motes.Parent = attachment
		attachment.Parent = root
	end

	local function refreshPetChips()
		local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		-- En móvil, a media altura a la derecha para no chocar con los botones táctiles.
		chips.Position = if touchOnly then UDim2.new(1, -20, 0.5, 0) else UDim2.new(1, -20, 1, -130)
		dragonChip.Visible = equippedCount("AmethystDragon") > 0
		local turtles = equippedCount("CrystalTurtle")
		turtleChip.Visible = turtles > 0
		turtleLabel.Text = "-" .. formatNumber(CombatMath.guardReduction(turtles) * 100, 0) .. " % daño"
		refreshGuardAura()
	end
	player:GetAttributeChangedSignal(Constants.Attributes.EquippedPets):Connect(refreshPetChips)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 5)
		refreshPetChips()
	end)
	refreshPetChips()

	local function startDragonCooldown(readyAt: number)
		local remaining = readyAt - Workspace:GetServerTimeNow()
		if remaining <= 0 then
			return
		end
		dragonLabel.Text = "¡Nova!"
		dragonLabel.TextColor3 = DRAGON_COLOR
		dragonCooldown.Size = UDim2.fromScale(1, 1)
		local tween = TweenService:Create(dragonCooldown, TweenInfo.new(remaining, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 0) })
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				dragonLabel.Text = "Nova lista"
				dragonLabel.TextColor3 = THEME.Muted
			end
		end)
		tween:Play()
	end

	petAbilityRemote.OnClientEvent:Connect(function(event)
		if typeof(event) ~= "table" or typeof(event.Owner) ~= "Instance" then
			return
		end
		local owner = event.Owner :: Player
		local isOwner = owner == player

		if event.Kind == "FoxBolt" and typeof(event.Target) == "Vector3" then
			-- Rayo turquesa desde el zorrito hasta el objetivo (daño ya aplicado).
			-- Bola de luz con estela; tarda según la distancia para que se vea el recorrido.
			local from = petPosition(owner, "QuartzFox", tonumber(event.Index) or 1) or event.Target
			local target = event.Target :: Vector3
			local travel = math.clamp((target - from).Magnitude / 70, 0.12, 0.3)
			local bolt = fxPart(Vector3.one * 0.6, CFrame.new(from), FOX_COLOR)
			bolt.Shape = Enum.PartType.Ball
			local tail = Instance.new("Attachment")
			tail.Position = Vector3.new(0, 0.22, 0)
			tail.Parent = bolt
			local head = Instance.new("Attachment")
			head.Position = Vector3.new(0, -0.22, 0)
			head.Parent = bolt
			local trail = Instance.new("Trail")
			trail.Attachment0 = tail
			trail.Attachment1 = head
			trail.Lifetime = 0.14
			trail.LightEmission = 1
			trail.FaceCamera = true
			trail.Color = ColorSequence.new(Color3.new(1, 1, 1), FOX_COLOR)
			trail.Transparency = NumberSequence.new(0.1, 1)
			trail.Parent = bolt
			emitAt("Glint", from, FOX_COLOR, 3)
			local tween = TweenService:Create(bolt, TweenInfo.new(travel, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { CFrame = CFrame.new(target) })
			tween.Completed:Once(function()
				bolt:Destroy()
				emitAt("Glint", target, FOX_COLOR, 4)
				showPetHits(event.Hits, FOX_COLOR, isOwner)
			end)
			tween:Play()
			Debris:AddItem(bolt, travel + 0.3)
		elseif event.Kind == "DragonCast" and typeof(event.Center) == "Vector3" and typeof(event.Radius) == "number" then
			-- Aviso previo: círculo violeta que se llena hasta el impacto.
			local telegraph = if typeof(event.Telegraph) == "number" then event.Telegraph else 0.8
			local center = Vector3.new(event.Center.X, event.Center.Y - 2.5, event.Center.Z)
			local diameter = event.Radius * 2
			local ring = fxPart(Vector3.new(0.1, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), DRAGON_COLOR)
			ring.Shape = Enum.PartType.Cylinder
			ring.Transparency = 0.7
			local fill = fxPart(Vector3.new(0.12, 0.5, 0.5), CFrame.new(center + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, 0, math.rad(90)), DRAGON_COLOR)
			fill.Shape = Enum.PartType.Cylinder
			fill.Transparency = 0.55
			TweenService:Create(fill, TweenInfo.new(telegraph, Enum.EasingStyle.Linear), { Size = Vector3.new(0.12, diameter, diameter) }):Play()
			Debris:AddItem(ring, telegraph + 0.1)
			Debris:AddItem(fill, telegraph + 0.1)
			local from = petPosition(owner, "AmethystDragon", tonumber(event.Index) or 1)
			if from then
				emitAt("Glint", from, DRAGON_COLOR, 8) -- el dragón carga la habilidad
			end
			if isOwner and typeof(event.ReadyAt) == "number" then
				startDragonCooldown(event.ReadyAt)
			end
		elseif event.Kind == "DragonImpact" and typeof(event.Center) == "Vector3" and typeof(event.Radius) == "number" then
			local center = Vector3.new(event.Center.X, event.Center.Y - 2.3, event.Center.Z)
			local diameter = event.Radius * 2
			local wave = fxPart(Vector3.new(0.2, diameter * 0.5, diameter * 0.5), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), DRAGON_COLOR)
			wave.Shape = Enum.PartType.Cylinder
			wave.Transparency = 0.3
			TweenService:Create(wave, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, diameter * 1.1, diameter * 1.1), Transparency = 1 }):Play()
			Debris:AddItem(wave, 0.45)
			emitAt("Glint", event.Center, DRAGON_COLOR, 14)
			showPetHits(event.Hits, DRAGON_COLOR, isOwner)
			if isOwner then
				playVaried(novaSound, 1.5, 0.05)
			end
		elseif event.Kind == "TurtleBlock" then
			-- Escudo de la tortuga: burbuja breve alrededor del jugador protegido.
			local character = owner.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local bubble = fxPart(Vector3.one * 6.5, root.CFrame, GUARD_COLOR)
				bubble.Shape = Enum.PartType.Ball
				bubble.Material = Enum.Material.ForceField
				bubble.Transparency = 0.2
				TweenService:Create(bubble, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1, Size = Vector3.one * 7.5 }):Play()
				Debris:AddItem(bubble, 0.45)
				if isOwner and typeof(event.Blocked) == "number" and event.Blocked >= 0.5 then
					damageNumber(root.Position + Vector3.new(0, 1, 0), event.Blocked, GUARD_COLOR, false)
				end
			end
		end
	end)

	-- Limpiar efectos temporales al morir o al cambiar de zona.
	player.CharacterRemoving:Connect(function()
		table.clear(pendingSwings)
		if animationTrack then
			animationTrack:Stop(0)
			animationTrack = nil
		end
		clearTransientEffects()
	end)
	player:GetAttributeChangedSignal(Constants.Attributes.CurrentZone):Connect(function()
		table.clear(pendingSwings)
		clearTransientEffects()
	end)

	-- Energía ganada
	local function toast(text: string, color: Color3)
		local label = UiKit.text(ui.Toasts, "Toast", {
			Size = UDim2.fromOffset(440, 26),
			Font = FONTS.Display,
			TextSize = 20,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.35,
			TextStrokeColor3 = Color3.new(0, 0, 0),
			LayoutOrder = math.floor(os.clock() * 100),
		})
		task.delay(1.4, function()
			local tween = TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 })
			tween.Completed:Once(function()
				label:Destroy()
			end)
			tween:Play()
		end)
		-- Nunca más de 3 avisos a la vez
		local labels = {}
		for _, child in ui.Toasts:GetChildren() do
			if child:IsA("TextLabel") then
				table.insert(labels, child)
			end
		end
		table.sort(labels, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for index = 1, #labels - 3 do
			labels[index]:Destroy()
		end
	end

	-- Anuncio grande y breve en el centro (jefe derrotado o en furia).
	local bannerToken = 0
	local function showBanner(text: string, color: Color3)
		bannerToken += 1
		local token = bannerToken
		ui.Banner.Text = text
		ui.Banner.TextColor3 = color
		ui.Banner.TextTransparency = 0
		ui.Banner.TextStrokeTransparency = 0.2
		task.delay(2.6, function()
			if bannerToken == token then
				TweenService:Create(ui.Banner, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end)
	end

	rewardRemote.OnClientEvent:Connect(function(amount: number, enemyName: string, isBoss: boolean)
		if typeof(amount) ~= "number" then
			return
		end
		toast(("+%s ⚡  ·  %s"):format(formatNumber(amount), tostring(enemyName)), if isBoss then THEME.Gold else THEME.BuyHighlight)
		if isBoss then
			showBanner(("¡%s derrotado!  +%s ⚡"):format(tostring(enemyName), formatNumber(amount)), THEME.Gold)
			ui.ScreenFlash.BackgroundTransparency = 0.55
			TweenService:Create(ui.ScreenFlash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
			if bossDefeatSound then
				bossDefeatSound:Play()
			end
		end
	end)

	-- Animación de enemigos y entrada de los jefes (aviso solo si estás cerca de su arena).
	EnemyAnimator.start({
		SpawnSound = CombatConfig.Sounds.BossSpawn,
		OnBossSpawn = function(model: Model)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local center = model:GetAttribute("ArenaCenter")
			local radius = model:GetAttribute("ArenaRadius")
			if root and root:IsA("BasePart") and typeof(center) == "Vector3" and typeof(radius) == "number" then
				local offset = root.Position - center
				if Vector2.new(offset.X, offset.Z).Magnitude <= radius + BOSS_BAR_RANGE * 2 then
					showBanner(("¡%s ha despertado!"):format(tostring(model:GetAttribute("DisplayName"))), BOSS_BAR_COLOR)
				end
			end
		end,
	})

	-- Barra del jefe: se muestra al acercarse a una arena con su jefe vivo.
	local enragedAnnounced: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local trailTarget = 1
	task.spawn(function()
		while true do
			task.wait(0.25)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local enemiesFolder = Workspace:FindFirstChild("Enemies")
			local shown = false
			if root and root:IsA("BasePart") and enemiesFolder then
				for _, zoneFolder in enemiesFolder:GetChildren() do
					for _, model in zoneFolder:GetChildren() do
						if model:IsA("Model") and model:GetAttribute("Kind") == "Boss" then
							local center = model:GetAttribute("ArenaCenter")
							local radius = model:GetAttribute("ArenaRadius")
							local health = model:GetAttribute("Health")
							local maxHealth = model:GetAttribute("MaxHealth")
							if typeof(center) == "Vector3" and typeof(radius) == "number" and typeof(health) == "number" and typeof(maxHealth) == "number" and health > 0 then
								local offset = root.Position - center
								if Vector2.new(offset.X, offset.Z).Magnitude <= radius + BOSS_BAR_RANGE then
									shown = true
									local enraged = model:GetAttribute("Enraged") == true
									local name = tostring(model:GetAttribute("DisplayName"))
									ui.BossName.Text = name .. (if enraged then "  ·  ¡Furioso!" else "") .. ("   %s / %s"):format(formatNumber(health), formatNumber(maxHealth))
									ui.BossName.TextColor3 = if enraged then BOSS_ENRAGED_COLOR else THEME.Text
									ui.BossFill.BackgroundColor3 = if enraged then BOSS_ENRAGED_COLOR else BOSS_BAR_COLOR
									local fraction = math.clamp(health / maxHealth, 0, 1)
									ui.BossFill.Size = UDim2.fromScale(fraction, 1)
									-- El tramo claro alcanza a la vida real con un pequeño retraso.
									if fraction < trailTarget then
										TweenService:Create(ui.BossTrail, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.25), { Size = UDim2.fromScale(fraction, 1) }):Play()
									else
										ui.BossTrail.Size = UDim2.fromScale(fraction, 1)
									end
									trailTarget = fraction
									local def = EnemyConfig.Types[model:GetAttribute("EnemyType")]
									local enrageAt = def and def.Enrage and def.Enrage.HealthFraction
									ui.EnrageMark.Visible = enrageAt ~= nil and not enraged
									if enrageAt then
										ui.EnrageMark.Position = UDim2.fromScale(enrageAt, 0.5)
									end
									-- Anunciar la entrada en furia una vez por vida del jefe
									if enraged and not enragedAnnounced[model] then
										enragedAnnounced[model] = true
										showBanner(("¡%s entra en furia!"):format(name), BOSS_ENRAGED_COLOR)
									elseif not enraged then
										enragedAnnounced[model] = nil
									end
								end
							end
						end
					end
				end
			end
			ui.BossBar.Visible = shown
		end
	end)
end

return CombatController
