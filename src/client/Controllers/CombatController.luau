-- Combate en el cliente (solo presentación y entrada; el servidor decide todo):
-- - Disparar: un clic o toque en un enemigo le dispara a él; F, X (mando), el botón táctil
--   o el botón "Disparar", al más cercano a tiro. Mantener pulsado sigue disparando (el
--   servidor respeta la cadencia del arma: PetCombatService). Con el pase "Disparo
--   automático" el arma dispara sola; la insignia (AUTO / OFF, o V) lo enciende o apaga, y
--   sin el pase (🔒 AUTO) abre la tienda. Sobre el botón, el arma equipada y su daño por
--   segundo.
-- - Cada disparo confirmado (PetAbility "PlayerShot") se dibuja según el proyectil del arma
--   (WeaponConfig): rayo, bola de plasma, espina, rayo de cristal que salta entre enemigos
--   o esfera que explota; luego los impactos (destello, chispas, número de daño, sonido).
--   Con el estilo Puños es un puñetazo (estallido en el enemigo, sin proyectil) y con Magia
--   un orbe morado; los críticos (Armas) sacan el número dorado y más grande. El botón dice
--   Disparar / Golpear / Lanzar y la línea de encima, el estilo y su daño por segundo.
-- - Botín: monedas (💰) y orbes de energía (⚡) que saltan del enemigo y vuelan hacia ti al
--   cobrar, el ORBE DORADO (botín ×10) con su destello, un aviso al derrotarlo (uno solo
--   que se actualiza, para que las hordas no llenen la pila) y anuncio al derrotar a un jefe.
-- - Dentro de una partida de oleadas el arma dispara sola aunque no tengas el pase: la
--   insignia muestra "AUTO ⚔".
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
local WeaponConfig = require(Shared.Config.WeaponConfig)
local StyleConfig = require(Shared.Config.StyleConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local formatNumber = require(Shared.Util.FormatNumber)
local CombatMath = require(Shared.CombatMath)
local MonetizationLogic = require(Shared.MonetizationLogic)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local Toasts = require(script.Parent.Parent.UI.Toasts)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local HudDock = require(script.Parent.Parent.UI.HudDock)
local EnemyAnimator = require(script.Parent.EnemyAnimator)
local WaveVisibility = require(script.Parent.WaveVisibility)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local LAYOUT = Theme.Layout
local ATTACK_ACTION = "RebirthAttack"
local AUTO_ACTION = "RebirthAutoFire"
local REPEAT_SECONDS = 0.15 -- mantener pulsado repite la petición de disparo
local BOSS_BAR_RANGE = 30 -- distancia extra al borde de la arena para mostrar la barra
local KIND_COLORS = {
	Normal = Color3.fromRGB(255, 244, 214),
	Strong = Color3.fromRGB(255, 200, 110),
	Boss = Color3.fromRGB(255, 140, 140),
}

local BOSS_BAR_COLOR = Color3.fromRGB(230, 90, 100)
local BOSS_ENRAGED_COLOR = Color3.fromRGB(255, 140, 60)
local BOSS_CHASE_COLOR = Color3.fromRGB(255, 120, 120)
local MAX_DAMAGE_NUMBERS = 14 -- más números a la vez no se leen y cuestan rendimiento
local SOUND_GAP = 0.06 -- el mismo sonido no se repite antes de este intervalo
local AIM_DISTANCE = 300 -- largo de la línea del cursor (desde la cámara) para buscar al enemigo apuntado
local SELECT_RANGE = 75 -- studs del personaje al enemigo para poder elegirlo (CombatService)
local AUTO_ON = Color3.fromRGB(96, 214, 96)
local AUTO_OFF = Color3.fromRGB(120, 120, 128)
local COIN_COLOR = Color3.fromRGB(255, 200, 40)
local COIN_SIZE = Vector3.new(0.22, 1.1, 1.1) -- moneda de canto (el cilindro va en X)
local COINS_KILL = 6 -- monedas que suelta un enemigo al morir
local COINS_BOSS = 18
local ORB_COLOR = Color3.fromRGB(32, 229, 209) -- energía (turquesa del cristal)
local ORB_SIZE = 0.8
local ORBS_KILL = 3
local ORBS_BOSS = 12
local GOLDEN_COLOR = Color3.fromRGB(255, 214, 70)
local MAX_FLYING = 90 -- más monedas y orbes volando a la vez no se distinguen y cuestan rendimiento

local CombatController = {}

local player = Players.LocalPlayer
local fxFolder: Folder

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

-- Rayo de un disparo: un haz de luz de `from` a `to` que se estrecha y se apaga
local SLASH_TO = Color3.fromRGB(120, 236, 206)
local function beamEffect(from: Vector3, to: Vector3, color: Color3, thickness: number)
	local dist = (to - from).Magnitude
	if dist > 0.2 then
		local beam = fxPart(Vector3.new(dist, thickness, thickness), CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0), color)
		beam.Shape = Enum.PartType.Cylinder
		beam.Transparency = 0.05
		TweenService:Create(beam, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(dist, 0.04, 0.04),
		}):Play()
		Debris:AddItem(beam, 0.24)
	end
end

-- Bola de luz con estela que viaja de `from` a `to` y llama a `onArrive` al llegar
local function travelBall(from: Vector3, to: Vector3, color: Color3, size: number, speed: number, onArrive: () -> ())
	local travel = math.clamp((to - from).Magnitude / speed, 0.1, 0.45)
	local ball = fxPart(Vector3.one * size, CFrame.new(from), color)
	ball.Shape = Enum.PartType.Ball
	local tail = Instance.new("Attachment")
	tail.Position = Vector3.new(0, size * 0.35, 0)
	tail.Parent = ball
	local head = Instance.new("Attachment")
	head.Position = Vector3.new(0, -size * 0.35, 0)
	head.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = tail
	trail.Attachment1 = head
	trail.Lifetime = 0.16
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Parent = ball
	local tween = TweenService:Create(ball, TweenInfo.new(travel, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { CFrame = CFrame.new(to) })
	tween.Completed:Once(function()
		ball:Destroy()
		onArrive()
	end)
	tween:Play()
	Debris:AddItem(ball, travel + 0.3)
end

-- Onda de una explosión en el suelo, del radio del daño en área
local function impactRing(center: Vector3, radius: number, color: Color3)
	local diameter = radius * 2
	local wave = fxPart(Vector3.new(0.2, diameter * 0.4, diameter * 0.4), CFrame.new(center - Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color)
	wave.Shape = Enum.PartType.Cylinder
	wave.Transparency = 0.35
	TweenService:Create(wave, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, diameter, diameter), Transparency = 1 }):Play()
	Debris:AddItem(wave, 0.4)
end

-- Enemigos vivos a tiro del personaje (Workspace.Enemies.<Zona>.<Modelo>)
local function enemiesInRange(origin: Vector3): { { Model: Model, Position: Vector3 } }
	local list = {}
	local enemiesFolder = Workspace:FindFirstChild("Enemies")
	if not enemiesFolder then
		return list
	end
	for _, zoneFolder in enemiesFolder:GetChildren() do
		for _, model in zoneFolder:GetChildren() do
			local enemyRoot = model:IsA("Model") and model:FindFirstChild("HumanoidRootPart")
			local health = model:GetAttribute("Health")
			-- Oleadas privadas: solo los de mi "mundo" (WaveVisibility)
			if enemyRoot and enemyRoot:IsA("BasePart") and (health == nil or health > 0) and model:GetAttribute("DiedAt") == nil and WaveVisibility.isVisible(model) then
				local offset = enemyRoot.Position - origin
				if Vector2.new(offset.X, offset.Z).Magnitude <= SELECT_RANGE then
					table.insert(list, { Model = model, Position = enemyRoot.Position })
				end
			end
		end
	end
	return list
end

-- Modelo del enemigo (Workspace.Enemies.<Zona>.<Modelo>) al que pertenece una pieza
local function enemyModelOf(instance: Instance, enemiesFolder: Instance): Model?
	local current: Instance? = instance
	while current and current.Parent and current.Parent.Parent ~= enemiesFolder do
		current = current.Parent
	end
	if current and current:IsA("Model") and current.Parent and current.Parent.Parent == enemiesFolder then
		return current
	end
	return nil
end

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Include

-- Enemigo que toca la línea del cursor o del toque (su cuerpo, con un margen de AimRadius),
-- si está lo bastante cerca para elegirlo. Solo es una propuesta: el servidor comprueba que
-- exista, esté vivo y cerca.
local function pickTarget(root: BasePart, aimRay: Ray): (Model?, Vector3?)
	local enemiesFolder = Workspace:FindFirstChild("Enemies")
	if not enemiesFolder then
		return nil, nil
	end
	aimParams.FilterDescendantsInstances = { enemiesFolder }
	local hit = Workspace:Spherecast(aimRay.Origin, CombatConfig.AimRadius, aimRay.Direction.Unit * AIM_DISTANCE, aimParams)
	local model = hit and enemyModelOf(hit.Instance, enemiesFolder)
	for _, candidate in enemiesInRange(root.Position) do
		if candidate.Model == model then
			return candidate.Model, candidate.Position
		end
	end
	return nil, nil
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
		-- Si el enemigo ya tiene su contorno de caricatura, el destello usa ese mismo
		-- Highlight (dos por modelo gastarían el límite de Highlights visibles).
		local outline = model:FindFirstChild("Outline")
		if outline and outline:IsA("Highlight") then
			highlight = outline
		else
			highlight = Instance.new("Highlight")
			highlight.Name = "HitFlash"
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.OutlineTransparency = 1
			highlight.Enabled = false
			highlight.Parent = model
		end
		flashes[model] = highlight
	end
	local current = highlight :: Highlight
	local persistent = current.Name == "Outline"
	current.FillColor = color
	current.FillTransparency = 0.2
	current.Enabled = true
	local tween = TweenService:Create(current, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FillTransparency = 1 })
	tween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed and not persistent then
			current.Enabled = false -- apagado: no ocupa el límite de Highlights visibles
		end
	end)
	tween:Play()
end

-- Número de daño: aparece con un pequeño "pop", sube y se desvanece en 0.7 s.
-- Como mucho MAX_DAMAGE_NUMBERS a la vez: el más antiguo se retira antes de tiempo.
local liveNumbers: { BasePart } = {}
local function damageNumber(position: Vector3, amount: number, color: Color3, killed: boolean, big: boolean?, boost: number?)
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
	local size = (if killed then Vector2.new(150, 48) elseif big then Vector2.new(118, 40) else Vector2.new(96, 34)) * math.clamp(boost or 1, 0.5, 2)
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
	label.Text = (if killed then "★ " else "") .. formatNumber(amount, 1)
	label.Parent = billboard
	billboard.Parent = anchor
	TweenService:Create(billboard, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(size.X, size.Y) }):Play()
	TweenService:Create(billboard, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 2.2, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.35), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 0.8)
end

-- Monedas ganadas en cada golpe: flotan en dorado sobre el enemigo
local liveCoinNumbers: { BasePart } = {}
local function coinNumber(position: Vector3, amount: number)
	for index = #liveCoinNumbers, 1, -1 do
		if liveCoinNumbers[index].Parent == nil then
			table.remove(liveCoinNumbers, index)
		end
	end
	while #liveCoinNumbers >= 10 do
		table.remove(liveCoinNumbers, 1):Destroy()
	end
	local anchor = fxPart(Vector3.one * 0.1, CFrame.new(position + Vector3.new(math.random(-6, 6) / 10, 2.6, math.random(-6, 6) / 10)), Color3.fromRGB(255, 220, 50))
	anchor.Transparency = 1
	table.insert(liveCoinNumbers, anchor)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(130, 42)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 80

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = FONTS.Display
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 235, 60)
	label.TextStrokeColor3 = Color3.fromRGB(45, 30, 10)
	label.TextStrokeTransparency = 0.12
	label.Text = "+$" .. formatNumber(amount, 0)
	label.Parent = billboard
	billboard.Parent = anchor

	TweenService:Create(billboard, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(115, 36) }):Play()
	TweenService:Create(billboard, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0.6, 2.5, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.35), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 0.75)
end

-- Impactos ya confirmados por el servidor de otros sistemas (mascotas y habilidades
-- elementales): número de daño (solo para el dueño), chispas, destello y sacudida.
-- boost agranda los números (habilidades); los impactos que dispararon un combo (campo
-- Reaction) salen aún más grandes.
local function showHits(hits: any, color: Color3, isOwner: boolean, react: number?, boost: number?)
	if typeof(hits) ~= "table" or not fxFolder then
		return
	end
	for _, hit in hits do
		if typeof(hit) == "table" and typeof(hit.Position) == "Vector3" and typeof(hit.Damage) == "number" then
			local killed = hit.Killed == true
			if isOwner then
				local size = (boost or 1) * (if hit.Reaction then 1.35 else 1)
				damageNumber(hit.Position, hit.Damage, color, killed, hit.Kind == "Boss", size)
			end
			emitAt("Spark", hit.Position, color, if killed then 16 else 6)
			if killed then
				emitAt("Wisp", hit.Position, color, 12)
			end
			if typeof(hit.Model) == "Instance" and hit.Model:IsA("Model") then
				flashEnemy(hit.Model, color)
				if not killed then
					EnemyAnimator.react(hit.Model, react or 0.6)
				end
			end
		end
	end
end
CombatController.showHits = showHits
CombatController.emitAt = function(kind: string, position: Vector3, color: Color3, amount: number)
	if fxFolder then
		emitAt(kind, position, color, amount)
	end
end
CombatController.impactRing = function(center: Vector3, radius: number, color: Color3)
	if fxFolder then
		impactRing(center, radius, color)
	end
end

-- Número flotante (p. ej. la curación de la Marea Sanadora) con el mismo estilo.
function CombatController.floatingNumber(position: Vector3, amount: number, color: Color3, boost: number?)
	if fxFolder then
		damageNumber(position, amount, color, false, false, boost)
	end
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

	-- Botón de ataque estilo `HUD Rediseño (standalone).html` (circular coral con borde #2B1D3F)
	local INK = Color3.fromRGB(43, 29, 63)
	local CREAM = Color3.fromRGB(255, 246, 224)
	local buttonFrame, buttonScale = UiKit.panel(screenGui, "AttackButton", Vector2.new(82, 82), Vector2.new(1, 1), UDim2.new(1, -20, 1, -22))
	buttonFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	buttonFrame.BackgroundTransparency = 0
	buttonFrame:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0)
	local oldShine = buttonFrame:FindFirstChild("Shine")
	if oldShine then
		oldShine:Destroy()
	end
	local oldGrad = buttonFrame:FindFirstChildOfClass("UIGradient")
	if oldGrad then
		oldGrad:Destroy()
	end
	UiKit.create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 217, 196)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(240, 112, 92)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 64, 58)),
		}),
	}, buttonFrame)
	local atkStroke = buttonFrame:FindFirstChildOfClass("UIStroke")
	if atkStroke then
		atkStroke.Color = INK
		atkStroke.Thickness = 4
		atkStroke.Transparency = 0
	end
	local cooldown = UiKit.create("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.4,
		ZIndex = 2,
	}, buttonFrame)
	UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, cooldown)
	local button = UiKit.create("TextButton", {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = FONTS.Display,
		TextSize = 38,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "⚔️",
		ZIndex = 3,
	}, buttonFrame)
	UiKit.addStates(button)
	local keyBadge = UiKit.create("Frame", {
		Name = "KeyBadge",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 2, 1, 2),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = INK,
		ZIndex = 4,
	}, buttonFrame)
	UiKit.corner(keyBadge, 8)
	UiKit.create("UIStroke", {
		Color = Color3.new(1, 1, 1),
		Thickness = 1.5,
		Transparency = 0.72,
	}, keyBadge)
	UiKit.text(keyBadge, "Hint", {
		Size = UDim2.fromScale(1, 1),
		Font = FONTS.Display,
		TextSize = 14,
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "F",
		ZIndex = 5,
	})
	local atkLabel = UiKit.text(buttonFrame, "AttackLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 5),
		Size = UDim2.fromOffset(90, 18),
		Font = FONTS.Display,
		TextSize = 13,
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "Disparar",
		ZIndex = 4,
	})
	UiKit.create("UIStroke", {
		Color = INK,
		Thickness = 2.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, atkLabel)
	-- Disparo automático (pase): encendido (AUTO), apagado (OFF) o sin el pase (🔒 AUTO)
	local autoBadge = UiKit.create("TextButton", {
		Name = "AutoBadge",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(-10, -8),
		Size = UDim2.fromOffset(58, 20),
		AutoButtonColor = true,
		BackgroundColor3 = AUTO_OFF,
		Font = FONTS.Display,
		TextSize = 12,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "🔒 AUTO",
		ZIndex = 6,
	}, buttonFrame)
	UiKit.corner(autoBadge, 6)
	UiKit.create("UIStroke", { Color = INK, Thickness = 1.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, autoBadge)
	-- Arma equipada y su daño por segundo, sobre el botón
	local weaponPill = UiKit.text(buttonFrame, "WeaponPill", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 4, 0, -8),
		Size = UDim2.fromOffset(240, 22),
		Font = FONTS.Display,
		TextSize = 15,
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 4,
	})
	UiKit.create("UIStroke", { Color = INK, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, weaponPill)

	-- Barra del jefe: justo debajo de la tarjeta de energía (la energía de cada enemigo va a
	-- la pila común de avisos, que baja cuando la barra se ve).
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
		AutoBadge = autoBadge,
		WeaponPill = weaponPill,
		AttackLabel = atkLabel,
		BossBar = bossBar,
		BossName = bossName,
		BossFill = bossFill,
		BossTrail = bossTrail,
		EnrageMark = enrageMark,
		Banner = banner,
		ScreenFlash = screenFlash,
	}
end

function CombatController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local attackRemote = remotes:WaitForChild(Constants.Remotes.Attack) :: RemoteEvent
	local autoRemote = remotes:WaitForChild(Constants.Remotes.SetAutoFire) :: RemoteEvent
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

	-- Clic o toque sobre un enemigo: le pide un disparo (el servidor comprueba el enemigo y
	-- decide el disparo). true si apuntaba a uno.
	local function shootAt(aimRay: Ray): boolean
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return false
		end
		local aimed, at = pickTarget(root, aimRay)
		if aimed and at then
			attackRemote:FireServer(aimed)
			emitAt("Glint", at, SLASH_TO, 4)
			flashEnemy(aimed, SLASH_TO)
			return true
		end
		return false
	end
	-- F, X (mando), el botón táctil o "Disparar": al más cercano a tiro (lo elige el servidor)
	local function shootNearest(): boolean
		attackRemote:FireServer()
		return true
	end

	-- Mantener pulsado: repite la petición mientras no se suelte lo que la empezó (el botón
	-- del ratón, ese dedo o la acción de F). Solo una repetición a la vez.
	local hold: { By: any }? = nil
	local function startHold(by: any, fire: () -> boolean)
		local current = { By = by }
		hold = current
		if fire() and animationTrack then
			animationTrack:Play()
		end
		task.spawn(function()
			while true do
				task.wait(REPEAT_SECONDS)
				if hold ~= current then
					return
				end
				fire()
			end
		end)
	end
	local function stopHold(by: any)
		if hold and hold.By == by then
			hold = nil
		end
	end

	ContextActionService:BindAction(ATTACK_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			startHold(ATTACK_ACTION, shootNearest)
		else
			stopHold(ATTACK_ACTION)
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle(ATTACK_ACTION, "⚔")
	ContextActionService:SetPosition(ATTACK_ACTION, UDim2.new(1, -170, 1, -150))
	ui.Button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			startHold(Enum.UserInputType.MouseButton1, shootNearest)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			startHold(input, shootNearest)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			startHold(Enum.UserInputType.MouseButton1, function()
				local mouse = UserInputService:GetMouseLocation()
				return shootAt(Workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y))
			end)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			startHold(input, function()
				return shootAt(Workspace.CurrentCamera:ScreenPointToRay(input.Position.X, input.Position.Y))
			end)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			stopHold(Enum.UserInputType.MouseButton1)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			stopHold(input)
		end
	end)

	-- Insignia AUTO o V: enciende o apaga el disparo automático; sin el pase, a la tienda
	local function hasAutoPass(): boolean
		return MonetizationLogic.autoFire(MonetizationLogic.parsePasses(player:GetAttribute(Constants.Attributes.Passes)))
	end
	local function refreshAutoFire()
		local owned = hasAutoPass()
		local on = player:GetAttribute(Constants.Attributes.AutoFire) == true
		-- Sin el pase, "AUTO ⚔" = disparo automático gratis dentro de las oleadas.
		ui.AutoBadge.Text = if on and not owned then "AUTO ⚔" elseif not owned then "🔒 AUTO" elseif on then "AUTO" else "OFF"
		ui.AutoBadge.BackgroundColor3 = if on then AUTO_ON else AUTO_OFF
	end
	local function toggleAutoFire()
		if not hasAutoPass() then
			Toasts.show("🎯 Disparo automático: consíguelo en la 🛒 Tienda", { Color = THEME.Gold, Key = "AutoFirePass" })
			PanelManager.open("Shop")
			return
		end
		autoRemote:FireServer(player:GetAttribute(Constants.Attributes.AutoFire) ~= true)
		if swingSound then
			swingSound:Play()
		end
	end
	ContextActionService:BindAction(AUTO_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			toggleAutoFire()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.V)
	ui.AutoBadge.Activated:Connect(toggleAutoFire)
	player:GetAttributeChangedSignal(Constants.Attributes.AutoFire):Connect(refreshAutoFire)
	player:GetAttributeChangedSignal(Constants.Attributes.Passes):Connect(refreshAutoFire)
	refreshAutoFire()

	-- Arma equipada (o el estilo, si no es Armas) y su daño por segundo sobre el botón
	local ATTACK_WORDS = { Weapons = "Disparar", Fists = "Golpear", Magic = "Lanzar" }
	local function refreshWeaponPill()
		local def = WeaponConfig.Weapons[player:GetAttribute(Constants.Attributes.EquippedWeapon)] or WeaponConfig.Weapons[WeaponConfig.StarterWeapon]
		local dps = player:GetAttribute(Constants.Attributes.DamagePerSecond)
		local styleId = player:GetAttribute(Constants.Attributes.CombatStyle)
		local style = if typeof(styleId) == "string" and styleId ~= "Weapons" then StyleConfig.Styles[styleId] else nil
		local dpsText = formatNumber(if typeof(dps) == "number" then dps else 0)
		if style then
			ui.WeaponPill.Text = ("%s %s · %s/s"):format(style.Icon, style.DisplayName, dpsText)
			ui.WeaponPill.TextColor3 = style.Color
		else
			ui.WeaponPill.Text = ("%s %s · %s/s"):format(def.Icon, def.DisplayName, dpsText)
			ui.WeaponPill.TextColor3 = def.Color
		end
		ui.AttackLabel.Text = ATTACK_WORDS[if typeof(styleId) == "string" then styleId else "Weapons"] or "Disparar"
	end
	player:GetAttributeChangedSignal(Constants.Attributes.EquippedWeapon):Connect(refreshWeaponPill)
	player:GetAttributeChangedSignal(Constants.Attributes.DamagePerSecond):Connect(refreshWeaponPill)
	player:GetAttributeChangedSignal(Constants.Attributes.CombatStyle):Connect(refreshWeaponPill)
	refreshWeaponPill()

	-- En pantallas solo táctiles se usa el botón táctil de Roblox (junto al de saltar).
	local function refreshButtonVisibility()
		ui.ButtonFrame.Visible = not (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	end
	UserInputService.LastInputTypeChanged:Connect(refreshButtonVisibility)
	refreshButtonVisibility()

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
		showHits(hits, color, isOwner, 0.6)
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
		-- En móvil, a media altura a la derecha para no chocar con los botones táctiles; en
		-- escritorio, justo encima del botón de ataque (que crece con la escala del HUD).
		local hudScale = UiKit.computeScale((ui.ButtonFrame.Parent :: ScreenGui).AbsoluteSize)
		-- (por encima del arma equipada, que va justo sobre el botón)
		chips.Position = if touchOnly then UDim2.new(1, -20, 0.5, 0) else UDim2.new(1, -20, 1, -(24 + 96 * hudScale + 12 + 30 * hudScale))
		dragonChip.Visible = equippedCount("AmethystDragon") > 0
		local turtles = equippedCount("CrystalTurtle")
		turtleChip.Visible = turtles > 0
		turtleLabel.Text = "-" .. formatNumber(CombatMath.guardReduction(turtles) * 100, 0) .. " % daño"
		-- La columna derecha del HUD termina encima de los indicadores cuando se ven.
		-- (el arma equipada ocupa ese sitio aunque no haya indicadores)
		HudDock.setChips(true)
		refreshGuardAura()
	end
	player:GetAttributeChangedSignal(Constants.Attributes.EquippedPets):Connect(refreshPetChips)
	local hudGui = ui.ButtonFrame.Parent :: ScreenGui
	hudGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshPetChips)
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

		if event.Kind == "PlayerShot" and typeof(event.Target) == "Vector3" then
			local def = WeaponConfig.Weapons[event.WeaponId] or WeaponConfig.Weapons[WeaponConfig.StarterWeapon]
			local style = if typeof(event.Style) == "string" and StyleConfig.Styles[event.Style] then event.Style else "Weapons"
			local color = if style == "Weapons" then def.Color else StyleConfig.Styles[style].Color
			local crit = event.Crit == true
			local character = owner.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local target = event.Target :: Vector3
			local from = if root and root:IsA("BasePart") then root.Position + Vector3.new(0, 1.2, 0) else target
			local function impact()
				emitAt("Glint", target, color, if crit then 10 else 4)
				if typeof(event.Splash) == "number" then
					impactRing(target, event.Splash, color)
				end
				-- Crítico: número dorado y más grande
				showHits(event.Hits, if crit then THEME.Gold else color, isOwner, 0.8, if crit then 1.6 else nil)
				if isOwner and typeof(event.Hits) == "table" and #event.Hits > 0 then
					local killed = false
					for _, hit in event.Hits do
						killed = killed or (typeof(hit) == "table" and hit.Killed == true)
					end
					if killed then
						playVaried(killSound, 0.9, 0.05)
					else
						playVaried(hitSound, if style == "Fists" then 0.95 elseif crit then 1.6 else 1.35, 0.07)
					end
				end
			end
			if style == "Fists" then
				-- Puñetazo: sin proyectil, un estallido en el enemigo
				impactRing(target, 2.6, color)
				emitAt("Spark", target, color, 8)
				impact()
			elseif style == "Magic" then
				-- Orbe mágico que viaja y explota (el área la marca impact)
				travelBall(from, target, color, 1.3, 70, impact)
			elseif def.Projectile == "Bolt" or def.Projectile == "Orb" then
				travelBall(from, target, color, if def.Projectile == "Orb" then 1.5 else 0.9, if def.Projectile == "Orb" then 70 else 90, impact)
			else
				beamEffect(from, target, color, if def.Projectile == "Thorn" then 0.22 elseif def.Projectile == "Prism" then 0.45 else 0.3)
				if typeof(event.Chain) == "table" then
					-- El rayo de cristal salta de enemigo en enemigo
					local previous = target
					for _, point in event.Chain do
						if typeof(point) == "Vector3" then
							beamEffect(previous, point, color, 0.25)
							emitAt("Glint", point, color, 3)
							previous = point
						end
					end
				end
				impact()
			end
		elseif event.Kind == "FoxBolt" and typeof(event.Target) == "Vector3" then
			-- Rayo turquesa desde el zorrito hasta el objetivo (daño ya aplicado).
			-- Bola de luz con estela; tarda según la distancia para que se vea el recorrido.
			local from = petPosition(owner, tostring(event.PetId or "QuartzFox"), tonumber(event.Index) or 1) or event.Target
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
		if animationTrack then
			animationTrack:Stop(0)
			animationTrack = nil
		end
		clearTransientEffects()
	end)
	player:GetAttributeChangedSignal(Constants.Attributes.CurrentZone):Connect(function()
		clearTransientEffects()
	end)

	-- Dinero ganado al derrotar a un enemigo (línea breve en la pila común de avisos)
	local function toast(text: string, color: Color3)
		Toasts.show(text, { Style = "Line", Color = color })
	end

	-- Monedas: saltan del enemigo en abanico y vuelan girando hasta el jugador
	local flying = 0
	local function dropCoins(from: Vector3, count: number)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return
		end
		count = math.min(count, math.max(0, MAX_FLYING - flying))
		flying += count
		task.delay(0.7 + count * 0.025, function()
			flying = math.max(0, flying - count)
		end)
		for index = 1, count do
			local coin = Instance.new("Part")
			coin.Name = "Coin"
			coin.Shape = Enum.PartType.Cylinder
			coin.Size = COIN_SIZE
			coin.Color = COIN_COLOR
			coin.Material = Enum.Material.SmoothPlastic
			coin.Reflectance = 0.25
			coin.Anchored = true
			coin.CanCollide = false
			coin.CanQuery = false
			coin.CanTouch = false
			coin.CastShadow = false
			local angle = (index / count + math.random() * 0.15) * math.pi * 2
			local spread = if count > 1 then 2 + math.random() * 2.5 else 1
			local peak = from + Vector3.new(math.cos(angle) * spread, 2.5 + math.random() * 2, math.sin(angle) * spread)
			coin.CFrame = CFrame.new(from) * CFrame.Angles(0, angle, 0)
			coin.Parent = fxFolder
			local pop = TweenService:Create(coin, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(peak) * CFrame.Angles(0, angle + math.pi, 0) })
			pop:Play()
			task.delay(0.28 + index * 0.025, function()
				if not coin.Parent then
					return
				end
				local goal = if root.Parent then root.Position else peak
				TweenService:Create(coin, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = CFrame.new(goal) * CFrame.Angles(0, angle + math.pi * 3, 0),
					Size = COIN_SIZE * 0.4,
				}):Play()
				Debris:AddItem(coin, 0.32)
			end)
		end
	end

	-- Orbes de energía: brotan del enemigo, flotan un instante y vuelan hasta el jugador.
	-- El orbe dorado es uno grande que brilla (y suena) antes de volar.
	local function dropOrbs(from: Vector3, count: number, golden: boolean)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return
		end
		if golden then
			count += 1
		end
		count = math.min(count, math.max(0, MAX_FLYING - flying))
		flying += count
		task.delay(1 + count * 0.04, function()
			flying = math.max(0, flying - count)
		end)
		for index = 1, count do
			local isGolden = golden and index == count
			local size = if isGolden then ORB_SIZE * 2.4 else ORB_SIZE * (0.8 + math.random() * 0.4)
			local orb = Instance.new("Part")
			orb.Name = if isGolden then "GoldenOrb" else "EnergyOrb"
			orb.Shape = Enum.PartType.Ball
			orb.Size = Vector3.one * size
			orb.Color = if isGolden then GOLDEN_COLOR else ORB_COLOR
			orb.Material = Enum.Material.Neon
			orb.Anchored = true
			orb.CanCollide = false
			orb.CanQuery = false
			orb.CanTouch = false
			orb.CastShadow = false
			local angle = math.random() * math.pi * 2
			local spread = 1.5 + math.random() * 2.5
			local peak = from + Vector3.new(math.cos(angle) * spread, 3 + math.random() * 2.5, math.sin(angle) * spread)
			orb.CFrame = CFrame.new(from)
			if isGolden then
				local light = Instance.new("PointLight")
				light.Color = GOLDEN_COLOR
				light.Range = 12
				light.Brightness = 3
				light.Shadows = false
				light.Parent = orb
			end
			orb.Parent = fxFolder
			TweenService:Create(orb, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = CFrame.new(peak) }):Play()
			local hold = if isGolden then 0.6 else 0.3 + index * 0.04
			task.delay(0.35 + hold, function()
				if not orb.Parent then
					return
				end
				local goal = if root.Parent then root.Position else peak
				TweenService:Create(orb, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = CFrame.new(goal),
					Size = Vector3.one * size * 0.3,
				}):Play()
				Debris:AddItem(orb, 0.3)
				if isGolden then
					emitAt("Glint", goal, GOLDEN_COLOR, 24)
				end
			end)
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

	-- Cada golpe suelta una moneda; al derrotarlo, un puñado (más si es un jefe) y el aviso.
	rewardRemote.OnClientEvent:Connect(function(amount: number, enemyName: string, isBoss: boolean, at: Vector3?, isKill: boolean?, extra: any?)
		if typeof(amount) ~= "number" then
			return
		end
		local energy = if type(extra) == "table" and typeof(extra.Energy) == "number" then extra.Energy else 0
		local golden = type(extra) == "table" and extra.Golden == true
		if typeof(at) == "Vector3" then
			dropCoins(at, if isBoss then COINS_BOSS elseif isKill then COINS_KILL else 1)
			if isKill and (energy > 0 or golden) then
				dropOrbs(at, if isBoss then ORBS_BOSS else ORBS_KILL, golden)
			end
		end
		if not (isKill or isBoss) then
			return -- golpe suelto: solo la moneda y el salto del contador
		end
		local loot = ("+%s 💰"):format(formatNumber(amount)) .. (if energy > 0 then ("  +%s ⚡"):format(formatNumber(energy)) else "")
		if golden then
			Toasts.show(("🌟 ¡ORBE DORADO!  ×10  ·  %s"):format(loot), { Color = GOLDEN_COLOR, Key = "GoldenOrb" })
			playVaried(killSound, 1.6, 0.05)
		elseif isBoss then
			toast(("%s  ·  %s"):format(loot, tostring(enemyName)), THEME.Gold)
		else
			-- Uno solo que se actualiza: con hordas no se apilan decenas de avisos.
			Toasts.show(("%s  ·  %s"):format(loot, tostring(enemyName)), { Style = "Line", Color = THEME.BuyHighlight, Key = "KillLoot" })
		end
		if isBoss then
			showBanner(("¡%s derrotado!  +%s 💰"):format(tostring(enemyName), formatNumber(amount)), THEME.Gold)
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
		IsVisible = WaveVisibility.isVisible,
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
						if model:IsA("Model") and model:GetAttribute("Kind") == "Boss" and WaveVisibility.isVisible(model) then
							local center = model:GetAttribute("ArenaCenter")
							local radius = model:GetAttribute("ArenaRadius")
							local health = model:GetAttribute("Health")
							local maxHealth = model:GetAttribute("MaxHealth")
							if typeof(center) == "Vector3" and typeof(radius) == "number" and typeof(health) == "number" and typeof(maxHealth) == "number" and health > 0 then
								local offset = root.Position - center
								if Vector2.new(offset.X, offset.Z).Magnitude <= radius + BOSS_BAR_RANGE then
									shown = true
									local enraged = model:GetAttribute("Enraged") == true
									-- La IA del jefe publica a quién persigue (TargetUserId)
									local chasing = model:GetAttribute("TargetUserId") == player.UserId
									local name = tostring(model:GetAttribute("DisplayName"))
									local status = (if chasing then "  ·  ¡Te persigue!" else "") .. (if enraged then "  ·  ¡Furioso!" else "")
									ui.BossName.Text = name .. status .. ("   %s / %s"):format(formatNumber(health), formatNumber(maxHealth))
									ui.BossName.TextColor3 = if enraged then BOSS_ENRAGED_COLOR elseif chasing then BOSS_CHASE_COLOR else THEME.Text
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
			if ui.BossBar.Visible ~= shown then
				ui.BossBar.Visible = shown
				HudDock.setBossBar(shown)
			end
		end
	end)
end

return CombatController
