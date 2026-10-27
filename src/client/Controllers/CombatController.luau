-- Combate en el cliente (solo presentación y entrada; el servidor decide todo):
-- - Disparar apuntando (AimPoint): un clic dispara hacia el cursor (mantener pulsado sigue
--   disparando y el personaje mira hacia donde apuntas); F, hacia el ratón; un toque corto
--   en el mundo, hacia el dedo; X (mando), el botón táctil ⚔ o "Disparar", hacia donde mira
--   el personaje. El servidor decide a quién da (lo que haya en el camino) y si falla, con la
--   cadencia del arma (PetCombatService). Con el pase "Disparo automático" el arma dispara
--   sola hacia donde apuntas cuando va a dar a alguien; la insignia (AUTO / OFF, o V) lo
--   enciende o apaga, y sin el pase (🔒 AUTO) abre la tienda. Sobre el botón, el arma
--   equipada y su daño por segundo. En PC el cursor es una mira.
-- - Cada disparo confirmado (PetAbility "PlayerShot") se dibuja según el proyectil del arma
--   (WeaponConfig): rayo, bola de plasma, espina, rayo de cristal que salta entre enemigos
--   o esfera que explota; luego los impactos (destello, chispas, número de daño, sonido).
--   Con el estilo Puños es un puñetazo (el personaje lanza el puño, alternando brazos, y el
--   golpe estalla en el enemigo) y con Magia un orbe que se carga en la mano (brazos al
--   frente) y viaja girando hasta explotar con un círculo de runas; con Armas el personaje
--   apunta con el brazo (CharacterPose). Los críticos (Armas) sacan el número dorado y más
--   grande. El botón dice
--   Disparar / Golpear / Lanzar y la línea de encima, el estilo y su daño por segundo.
-- - Botín: monedas (💰) y diamantes (💎) que saltan del enemigo y vuelan hacia ti al
--   cobrar, el ORBE DORADO (botín ×10) con su destello, un aviso al derrotarlo (uno solo
--   que se actualiza, para que las hordas no llenen la pila) y anuncio al derrotar a un jefe.
-- - Barra de vida grande del jefe al acercarse a su arena.
-- - Mascotas de combate: rayo del Zorrito, nova del Dragón (con aviso y recarga visible)
--   y escudo de la Tortuga, solo para acciones ya confirmadas por el servidor.
-- Interfaz con DisplayOrder 3: queda por debajo del inventario y los paneles.

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local CharacterPose = require(script.Parent.CharacterPose)
local AimPoint = require(script.Parent.AimPoint)
local AimCamera = require(script.Parent.AimCamera)
local CombatHud = require(script.Parent.CombatHud)
local StyleAnimations = require(script.Parent.StyleAnimations)
local MagicLogic = require(Shared.MagicLogic)
local GunLogic = require(Shared.GunLogic)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local LAYOUT = Theme.Layout
local ATTACK_ACTION = "RebirthAttack"
local AUTO_ACTION = "RebirthAutoFire"
local REPEAT_SECONDS = 0.12 -- mantener pulsado (o el automático) repite el aviso al servidor
local TAP_SECONDS = 0.3 -- un toque en el mundo más corto que esto (y casi sin moverse) dispara
local TAP_MOVE = 14 -- píxeles: si el dedo se mueve más, era para girar la cámara
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
-- Cómo se siente cada tipo de arma al disparar: retroceso del brazo, fogonazo, salto de la
-- mira (CombatHud.kick) y grosor del trazo de la bala
local GUN_FEEL = {
	Pistol = { Recoil = 0.7, Flash = 1, Kick = 0.7, Tracer = 0.12 },
	Rifle = { Recoil = 0.45, Flash = 0.8, Kick = 0.4, Tracer = 0.1 },
	Shotgun = { Recoil = 1.4, Flash = 1.6, Kick = 1.5, Tracer = 0.07 },
	Sniper = { Recoil = 1.6, Flash = 1.4, Kick = 1.9, Tracer = 0.22 },
	Launcher = { Recoil = 1.8, Flash = 1.8, Kick = 2, Tracer = 0.2 },
}
-- Puños: al pegar te echas encima del enemigo (hasta PUNCH_LUNGE_MAX studs, a esta velocidad)
-- y te quedas a PUNCH_REACH del punto donde el puño lo toca (el largo del brazo)
local PUNCH_REACH = 2.1
local PUNCH_LUNGE_MAX = 7
local PUNCH_LUNGE_SPEED = 80
local PUNCH_CROWD_RADIUS = 3.5 -- con otro bicho así de cerca, no te lanzas
local PUNCH_MAX_SPEED = 45 -- tras lanzarte, más rápido que esto es que algo te ha empujado
local PUNCH_MAX_RISE = 60
local SELECT_RANGE = 75 -- el automático solo apunta si hay enemigos a esta distancia
local AUTO_ON = Color3.fromRGB(96, 214, 96)
local AUTO_OFF = Color3.fromRGB(120, 120, 128)
local COIN_COLOR = Color3.fromRGB(255, 200, 40)
local COIN_SIZE = Vector3.new(0.22, 1.1, 1.1) -- moneda de canto (el cilindro va en X)
local COINS_KILL = 6 -- monedas que suelta un enemigo al morir
local COINS_BOSS = 18
local ORB_COLOR = Color3.fromRGB(110, 210, 255) -- diamantes (azul claro)
local ORB_SIZE = 0.75
local GEM_TILT = CFrame.Angles(math.rad(45), 0, math.rad(45)) -- el cubo de canto parece una gema
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

-- Sonido de StyleConfig.Sounds: el tuyo sin posición; el de otros, en su sitio (se oye cerca)
local styleSounds: { [string]: Sound } = {}
local function playStyleSound(key: string, at: Vector3?, pitch: number?)
	local spec = StyleConfig.Sounds[key]
	if not spec then
		return
	end
	if at then
		local holder = Instance.new("Attachment")
		holder.WorldPosition = at
		holder.Parent = Workspace.Terrain
		local sound = Instance.new("Sound")
		sound.SoundId = spec.Id
		sound.Volume = spec.Volume * 0.8
		sound.PlaybackSpeed = (spec.Pitch or 1) * (pitch or 1)
		sound.RollOffMaxDistance = 110
		sound.Parent = holder
		sound:Play()
		Debris:AddItem(holder, 4)
		return
	end
	local sound = styleSounds[key]
	if not sound then
		sound = Instance.new("Sound")
		sound.SoundId = spec.Id
		sound.Volume = spec.Volume
		sound.Parent = SoundService
		styleSounds[key] = sound
	end
	playVaried(sound, (spec.Pitch or 1) * (pitch or 1), 0.05)
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

-- Destello redondo que crece y se apaga (golpes de puño y explosiones de magia)
local function flashBall(center: Vector3, color: Color3, from: number, to: number, seconds: number)
	local ball = fxPart(Vector3.one * from, CFrame.new(center), color)
	ball.Shape = Enum.PartType.Ball
	ball.Transparency = 0.25
	TweenService:Create(ball, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * to, Transparency = 1 }):Play()
	Debris:AddItem(ball, seconds + 0.05)
end

-- Nombre de un combo de golpes (¡Gancho!, ¡Gran orbe!, ¡Tiro cargado!) sobre el enemigo
local function comboLabel(position: Vector3, text: string, color: Color3)
	local anchor = fxPart(Vector3.one * 0.2, CFrame.new(position + Vector3.new(0, 3.5, 0)), color)
	anchor.Transparency = 1
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(50, 16)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 90
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = FONTS.Display
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(43, 29, 63)
	label.TextStrokeTransparency = 0
	label.Text = text
	label.Parent = billboard
	billboard.Parent = anchor
	TweenService:Create(billboard, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(170, 46) }):Play()
	TweenService:Create(billboard, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 2, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 0.9)
end

-- Dónde toca el puño a un enemigo: el borde de su cuerpo que da hacia `from` (a la altura del
-- pecho, sin salirse del bicho). Devuelve el punto, la dirección del golpe (plana) y cuánto
-- falta desde `from` hasta ese borde.
local function punchContact(from: Vector3, fallback: Vector3, model: any): (Vector3, Vector3, number)
	local center, radius, bottom, top = fallback, 1.5, fallback.Y - 1.5, fallback.Y + 1.5
	if typeof(model) == "Instance" and model:IsA("Model") and model.Parent then
		local ok, cframe, size = pcall(function()
			return (model :: Model):GetBoundingBox()
		end)
		if ok then
			center = cframe.Position
			radius = math.clamp(math.min(size.X, size.Z) * 0.42, 0.8, 6)
			bottom = center.Y - size.Y / 2
			top = center.Y + size.Y / 2
		end
	end
	local flat = Vector3.new(center.X - from.X, 0, center.Z - from.Z)
	local distance = flat.Magnitude
	local direction = if distance > 0.05 then flat / distance else Vector3.new(0, 0, -1)
	local low, high = bottom + 0.8, top - 0.5
	if low > high then
		low = (bottom + top) / 2
		high = low
	end
	local reach = math.max(0, distance - radius)
	return Vector3.new(from.X, math.clamp(from.Y, low, high), from.Z) + direction * reach, direction, reach
end

-- Puñetazo: el golpe estalla donde el puño toca al enemigo (de la mano no sale nada):
-- destello, un disco de choque que se abre hacia delante y rayas de impacto alrededor. El
-- gancho del combo, más grande y hacia arriba (lo levanta).
local function punchFx(contact: Vector3, direction: Vector3, color: Color3, big: boolean?)
	local forward = if direction.Magnitude > 0.01 then direction.Unit else Vector3.new(0, 0, -1)
	local white = Color3.new(1, 1, 1)
	flashBall(contact, white, 0.5, if big then 4.2 else 2.3, if big then 0.15 else 0.09)
	if big then
		flashBall(contact, color, 1, 6.5, 0.28)
	end
	-- Disco de choque mirando hacia donde va el golpe (los cilindros van a lo largo de X)
	local facing = CFrame.lookAt(contact, contact + forward) * CFrame.Angles(0, math.rad(90), 0)
	local wave = fxPart(Vector3.new(0.12, 0.7, 0.7), facing, white:Lerp(color, 0.35))
	wave.Shape = Enum.PartType.Cylinder
	wave.Transparency = 0.1
	local waveSize = if big then 7 else 3.8
	TweenService:Create(wave, TweenInfo.new(if big then 0.22 else 0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.04, waveSize, waveSize),
		CFrame = facing * CFrame.new(if big then 1.4 else 0.8, 0, 0),
		Transparency = 1,
	}):Play()
	Debris:AddItem(wave, 0.26)
	-- Rayas de impacto: salen alrededor del golpe (un poco hacia ti, para que se vean)
	local side = forward:Cross(Vector3.yAxis)
	side = if side.Magnitude > 0.01 then side.Unit else Vector3.xAxis
	local up = side:Cross(forward).Unit
	local count = if big then 10 else 7
	local length = if big then 1.8 else 1.1
	for index = 1, count do
		local angle = (index + math.random() * 0.4) / count * math.pi * 2
		local radial = side * math.cos(angle) + up * math.sin(angle)
		local lift = if big then Vector3.new(0, 0.45, 0) else Vector3.zero
		local line = (radial - forward * 0.25 + lift).Unit
		local start = CFrame.lookAt(contact, contact + line)
		local spike = fxPart(Vector3.new(0.13, 0.13, length), start * CFrame.new(0, 0, -length / 2 - 0.3), if index % 2 == 0 then white else color)
		TweenService:Create(spike, TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = start * CFrame.new(0, 0, -length / 2 - (if big then 2.6 else 1.6)),
			Size = Vector3.new(0.04, 0.04, length * 0.5),
			Transparency = 1,
		}):Play()
		Debris:AddItem(spike, 0.16)
	end
	-- Gancho: una estela que sube (el enemigo sale volando hacia arriba)
	if big then
		local rise = fxPart(Vector3.new(0.5, 0.5, 4), CFrame.lookAt(contact, contact + Vector3.yAxis) * CFrame.new(0, 0, -2), white:Lerp(color, 0.5))
		rise.Transparency = 0.2
		TweenService:Create(rise, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.05, 0.05, 6),
			CFrame = CFrame.lookAt(contact, contact + Vector3.yAxis) * CFrame.new(0, 0, -4),
			Transparency = 1,
		}):Play()
		Debris:AddItem(rise, 0.3)
	end
end

-- Sacudida y zoom de la cámara de AbilityController (se pide al usarla: AbilityController
-- también requiere este módulo). Respetan "Reducir movimiento".
local cameraFx: any = nil
local function shakeCamera(amount: number, fov: number?)
	if cameraFx == nil then
		local ok, module = pcall(require, script.Parent.AbilityController)
		cameraFx = if ok then module else false
	end
	if cameraFx then
		if cameraFx.shake then
			cameraFx.shake(amount)
		end
		if fov and cameraFx.kickFov then
			cameraFx.kickFov(fov)
		end
	end
end

-- ¿Hay otro bicho pegado a ti (aparte del que golpeas)? Entonces no te lanzas: empujarte
-- entre varios cuerpos te mandaría volando.
local function crowded(root: BasePart, target: any): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent :: Instance, fxFolder }
	for _, part in Workspace:GetPartBoundsInRadius(root.Position, PUNCH_CROWD_RADIUS, params) do
		local node: Instance? = part.Parent
		while node and node ~= Workspace do
			if node:IsA("Model") and node:GetAttribute("EnemyType") ~= nil then
				if node ~= target then
					return true
				end
				break
			end
			node = node.Parent
		end
	end
	return false
end

-- Tras cada puñetazo, un momento sin salir disparado: si algún choque con los bichos te lanza
-- más rápido de lo normal, se frena (andar, saltar y el dash no llegan a esas velocidades)
local steadyUntil = 0
local steadyRoot: BasePart? = nil
local steadyConnection: RBXScriptConnection? = nil
local function keepSteady(root: BasePart, seconds: number)
	steadyUntil = math.max(steadyUntil, os.clock() + seconds)
	steadyRoot = root
	if steadyConnection then
		return
	end
	steadyConnection = RunService.Heartbeat:Connect(function()
		local current = steadyRoot
		if os.clock() > steadyUntil or not (current and current.Parent) then
			if steadyConnection then
				steadyConnection:Disconnect()
				steadyConnection = nil
			end
			return
		end
		if current:FindFirstChild("PunchLunge") then
			return -- la embestida misma sí va rápida
		end
		local velocity = current.AssemblyLinearVelocity
		local flat = Vector3.new(velocity.X, 0, velocity.Z)
		if flat.Magnitude > PUNCH_MAX_SPEED or velocity.Y > PUNCH_MAX_RISE then
			current.AssemblyLinearVelocity = Vector3.new(0, math.min(velocity.Y, 0), 0)
			current.AssemblyAngularVelocity = Vector3.zero
		end
	end)
end

-- Tu personaje se echa hacia delante `distance` studs para que el puño llegue de verdad: sin
-- cruzar paredes ni meterse en otros bichos, y sin lanzarse si tienes varios encima.
-- Devuelve cuánto dura la embestida (0 si no hace falta).
local lungeMover: LinearVelocity? = nil
local function lunge(root: BasePart, direction: Vector3, distance: number, target: any): number
	distance = math.min(distance, PUNCH_LUNGE_MAX)
	if distance < 0.6 or crowded(root, target) then
		return 0
	end
	-- Un cuerpo del ancho del tuyo a lo largo del camino: se para antes de lo primero que toque
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent :: Instance, fxFolder }
	local blocked = Workspace:Spherecast(root.Position, 1.2, direction * (distance + 1), params)
	if blocked then
		distance = math.min(distance, blocked.Distance - 0.5)
	end
	if distance < 0.6 then
		return 0
	end
	local seconds = math.clamp(distance / PUNCH_LUNGE_SPEED, 0.05, 0.1)
	if lungeMover then
		lungeMover:Destroy()
	end
	local attachment = root:FindFirstChild("PunchLungeAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "PunchLungeAttachment"
		attachment.Parent = root
	end
	local velocity = direction * (distance / seconds)
	local mover = Instance.new("LinearVelocity")
	mover.Name = "PunchLunge"
	mover.Attachment0 = attachment :: Attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	-- Fuerza justa para tu peso: si choca con algo, se queda ahí en vez de atravesarlo
	mover.MaxForce = math.max(root.AssemblyMass, 1) * 2500
	mover.Parent = root
	lungeMover = mover
	root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
	keepSteady(root, seconds + 0.6)
	task.delay(seconds, function()
		if lungeMover == mover then
			lungeMover = nil
			mover:Destroy()
			-- Sin pasarse de largo
			if root.Parent then
				root.AssemblyLinearVelocity = Vector3.new(0, math.min(root.AssemblyLinearVelocity.Y, 0), 0)
			end
		end
	end)
	return seconds
end

-- Orbe mágico: se carga en la mano (crece) y luego viaja girando, con chispas, hasta el
-- objetivo; al llegar llama a `onArrive`. `scale`: más grande (el gran orbe del combo).
local function magicOrb(hand: Vector3, target: Vector3, color: Color3, onArrive: () -> (), scale: number?)
	local charge = 0.14
	local orb = fxPart(Vector3.one * 0.3, CFrame.new(hand), color)
	orb.Shape = Enum.PartType.Ball
	orb.Transparency = 0.1
	local core = fxPart(Vector3.one * 0.15, CFrame.new(hand), Color3.new(1, 1, 1))
	core.Shape = Enum.PartType.Ball
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = 10
	glow.Brightness = 2
	glow.Parent = orb
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new(0.3, 0)
	sparkles.Transparency = NumberSequence.new(0.1, 1)
	sparkles.Lifetime = NumberRange.new(0.25, 0.45)
	sparkles.Speed = NumberRange.new(1, 3)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Rate = 70
	sparkles.Parent = orb
	TweenService:Create(orb, TweenInfo.new(charge, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.one * 1.8 * (scale or 1) }):Play()
	TweenService:Create(core, TweenInfo.new(charge), { Size = Vector3.one * 0.8 * (scale or 1) }):Play()
	task.delay(charge, function()
		if not orb.Parent then
			return
		end
		local start = orb.Position
		local travel = math.clamp((target - start).Magnitude / 48, 0.12, 0.6)
		local began = os.clock()
		local side = (target - start):Cross(Vector3.yAxis)
		side = if side.Magnitude > 0.01 then side.Unit else Vector3.xAxis
		local connection
		connection = game:GetService("RunService").RenderStepped:Connect(function()
			local t = math.clamp((os.clock() - began) / travel, 0, 1)
			-- Recorrido con un pequeño arco y un giro en espiral
			local position = start:Lerp(target, t) + Vector3.new(0, math.sin(t * math.pi) * 1.4, 0) + side * math.sin(t * math.pi * 3) * 0.6 * (1 - t)
			orb.CFrame = CFrame.new(position)
			core.CFrame = CFrame.new(position)
			if t >= 1 then
				connection:Disconnect()
				orb:Destroy()
				core:Destroy()
				onArrive()
			end
		end)
	end)
	Debris:AddItem(orb, 2)
	Debris:AddItem(core, 2)
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

-- Fogonazo en la boca del arma (y una luz breve)
local function muzzleFlash(at: Vector3, color: Color3, size: number)
	local flash = fxPart(Vector3.one * 0.4 * size, CFrame.new(at), Color3.fromRGB(255, 240, 190))
	flash.Shape = Enum.PartType.Ball
	flash.Transparency = 0.05
	local light = Instance.new("PointLight")
	light.Color = color:Lerp(Color3.fromRGB(255, 220, 150), 0.5)
	light.Range = 9 * size
	light.Brightness = 3
	light.Parent = flash
	TweenService:Create(flash, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 1.2 * size, Transparency = 1 }):Play()
	Debris:AddItem(flash, 0.1)
	emitAt("Spark", at, color, math.floor(3 * size + 0.5))
end

-- Trazo de una bala: línea fina y brillante que se apaga enseguida
local function tracer(from: Vector3, to: Vector3, color: Color3, thickness: number)
	local dist = (to - from).Magnitude
	if dist < 0.3 then
		return
	end
	local line = fxPart(Vector3.new(dist, thickness, thickness), CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0), color:Lerp(Color3.new(1, 1, 1), 0.45))
	line.Shape = Enum.PartType.Cylinder
	line.Transparency = 0.1
	TweenService:Create(line, TweenInfo.new(0.09, Enum.EasingStyle.Linear), { Transparency = 1, Size = Vector3.new(dist, thickness * 0.3, thickness * 0.3) }):Play()
	Debris:AddItem(line, 0.12)
end

-- Cohete de la bazuca: viaja de `from` a `to` en `seconds` dejando humo (la explosión la
-- dibuja el aviso "ShotImpact")
local function rocketFx(from: Vector3, to: Vector3, color: Color3, seconds: number)
	local rocket = fxPart(Vector3.new(0.5, 0.5, 1.4), CFrame.lookAt(from, to), color)
	rocket.Material = Enum.Material.Neon
	local tail = Instance.new("Attachment")
	tail.Position = Vector3.new(0, 0, 0.7)
	tail.Parent = rocket
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(255, 200, 120), Color3.fromRGB(90, 90, 96))
	smoke.Size = NumberSequence.new(0.5, 1.6)
	smoke.Transparency = NumberSequence.new(0.2, 1)
	smoke.Lifetime = NumberRange.new(0.3, 0.6)
	smoke.Speed = NumberRange.new(0.5, 1.5)
	smoke.Rate = 90
	smoke.LightEmission = 0.4
	smoke.Parent = tail
	local tween = TweenService:Create(rocket, TweenInfo.new(math.max(0.05, seconds), Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(to, to + (to - from).Unit) })
	tween.Completed:Once(function()
		rocket:Destroy()
	end)
	tween:Play()
	Debris:AddItem(rocket, seconds + 0.5)
end

-- Tajo de espada: un arco brillante que barre delante del personaje (`step` 1 de derecha a
-- izquierda, 2 al revés) o una rueda completa (el giro). Las piezas aparecen una tras otra.
local function slashArc(center: Vector3, direction: Vector3, radius: number, color: Color3, step: number, big: boolean?)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	flat = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)
	local base = CFrame.lookAt(center, center + flat)
	local full = step == 3
	local segments = if full then 18 else 9
	local spread = if full then 360 else 150
	local sweep = if step == 2 then -1 else 1
	local distance = math.max(2.5, radius * 0.7)
	local chord = 2 * distance * math.sin(math.rad(spread / segments) / 2) + 0.4
	local glow = color:Lerp(Color3.new(1, 1, 1), 0.35)
	for index = 1, segments do
		local t = (index - 0.5) / segments
		local angle = math.rad((-spread / 2 + spread * t) * sweep)
		local outward = base:VectorToWorldSpace(Vector3.new(math.sin(angle), 0, -math.cos(angle)))
		local position = center + outward * distance + Vector3.new(0, 0.2, 0)
		task.delay((index - 1) * (if full then 0.012 else 0.016), function()
			local piece = fxPart(Vector3.new(0.14, if big then 1.3 else 0.8, chord), CFrame.lookAt(position, position + outward:Cross(Vector3.yAxis)), glow)
			piece.Transparency = 0.15
			TweenService:Create(piece, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1, Size = Vector3.new(0.05, 0.2, chord) }):Play()
			Debris:AddItem(piece, 0.22)
		end)
	end
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
				local size = (boost or 1) * (if hit.Reaction or hit.Combo then 1.35 else 1)
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
CombatController.beam = function(from: Vector3, to: Vector3, color: Color3, thickness: number)
	if fxFolder then
		beamEffect(from, to, color, thickness)
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
	-- Barras de jefe: una a lo ancho o, con dos jefes a la vez (Ignis y Glacius), una al lado
	-- de la otra en el mismo sitio. La primera se llama "BossBar" (WaveController la busca).
	local function makeBossBar(name: string)
		local bossBar, _ = UiKit.panel(top, name, Vector2.new(440, 54), Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0))
		bossBar.Visible = false
		local bossName = UiKit.text(bossBar, "Name", {
			Position = UDim2.fromOffset(16, 6),
			Size = UDim2.new(1, -32, 0, 20),
			Font = FONTS.Display,
			TextSize = 18,
			TextScaled = true,
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
		-- Marca de dónde se parte (el Coloso del Equilibrio: EnemyConfig.Types.*.Split)
		local splitMark = UiKit.create("Frame", {
			Name = "SplitMark",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 3, 1, 8),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 3,
		}, bossTrack)
		return { Bar = bossBar, Name = bossName, Fill = bossFill, Trail = bossTrail, EnrageMark = enrageMark, SplitMark = splitMark, TrailTarget = 1 }
	end
	local bossBars = { makeBossBar("BossBar"), makeBossBar("BossBar2") }
	local bossBar = bossBars[1].Bar

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
		BossBars = bossBars,
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
	local hold: { By: any }? = nil
	local function startHold(by: any, aimFn: () -> Vector3?, turn: boolean)
		local current = { By = by }
		hold = current
		local aim = aimFn()
		if turn then
			AimPoint.faceToward(aim)
			setTurning(aimFn)
		else
			setTurning(nil)
		end
		if send(aim, "Shot") and animationTrack and isMelee(styleNow()) then
			animationTrack:Play()
		end
		task.spawn(function()
			while true do
				task.wait(REPEAT_SECONDS)
				if hold ~= current then
					return
				end
				send(aimFn(), "Hold")
			end
		end)
	end
	local function stopHold(by: any)
		if hold and hold.By == by then
			hold = nil
			setTurning(nil)
			signal("Release")
		end
	end

	-- Magia: clic corto = bola; mantener = cargar un orbe que crece en el bastón (al soltar sale)
	local magicSpec = StyleConfig.Styles.Magic
	local magicPress: { By: any, Charging: boolean, Aim: () -> Vector3? }? = nil
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
		magicPress = press
		task.delay(magicSpec.Charge.MinHold, function()
			if magicPress == press then
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
		local press = magicPress
		if not (press and press.By == by) then
			return
		end
		magicPress = nil
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
		hold = nil
		magicPress = nil
		stopChargeOrb()
		setTurning(nil)
	end)

	-- Clic derecho (o L2, o el botón 🛡️): apuntar con Armas, bloquear con Guerrero; con Magia,
	-- un clic derecho corto es el teletransporte (mantenerlo sigue girando la cámara).
	local altHeld: string? = nil
	local function blink(aim: Vector3?)
		styleActionRemote:FireServer("Blink", aim or facingAim())
	end
	local function altDown(fromPad: boolean)
		local style = styleNow()
		if altHeld then
			return
		end
		if style == "Weapons" then
			altHeld = "Ads"
			AimCamera.setAds(true)
			signal("AdsOn")
		elseif style == "Warrior" then
			altHeld = "Block"
			AimCamera.setSlow(StyleConfig.Styles.Warrior.Block.WalkSpeed)
			signal("BlockOn")
		elseif style == "Magic" and fromPad then
			blink(facingAim())
		end
	end
	local function altUp()
		if altHeld == "Ads" then
			AimCamera.setAds(false)
			signal("AdsOff")
		elseif altHeld == "Block" then
			AimCamera.setSlow(1)
			signal("BlockOff")
		end
		altHeld = nil
	end
	player:GetAttributeChangedSignal(Constants.Attributes.CombatStyle):Connect(function()
		altUp()
		magicPress = nil
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
			if altHeld then
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

	-- R: recargar (Armas) si al cargador le faltan balas; si está lleno, la R sigue siendo la
	-- habilidad secundaria del núcleo
	local function canReload(): boolean
		local ammo = player:GetAttribute(Constants.Attributes.Ammo)
		local magazine = player:GetAttribute(Constants.Attributes.AmmoMax)
		local reloadEnd = player:GetAttribute(Constants.Attributes.ReloadEnd)
		return styleNow() == "Weapons" and type(ammo) == "number" and type(magazine) == "number" and ammo < magazine and not (type(reloadEnd) == "number" and reloadEnd > Workspace:GetServerTimeNow())
	end
	ContextActionService:BindActionAtPriority("RebirthReload", function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if canReload() then
			signal("Reload")
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.R)
	CombatHud.start(ui.ButtonFrame)
	CombatHud.onResourceTapped(function()
		if canReload() then
			signal("Reload")
		end
	end)
	-- Sonido de recarga (también la automática al vaciar el cargador)
	player:GetAttributeChangedSignal(Constants.Attributes.ReloadEnd):Connect(function()
		local reloadEnd = player:GetAttribute(Constants.Attributes.ReloadEnd)
		if type(reloadEnd) == "number" and reloadEnd > 0 then
			playStyleSound("Reload", nil)
			StyleAnimations.reload(reloadEnd - Workspace:GetServerTimeNow())
		end
	end)

	-- Insignia AUTO o V: enciende o apaga el disparo automático; sin el pase, a la tienda
	local function hasAutoPass(): boolean
		return MonetizationLogic.autoFire(MonetizationLogic.parsePasses(player:GetAttribute(Constants.Attributes.Passes)))
	end
	local function refreshAutoFire()
		local owned = hasAutoPass()
		local on = owned and player:GetAttribute(Constants.Attributes.AutoFire) == true
		ui.AutoBadge.Text = if not owned then "🔒 AUTO" elseif on then "AUTO" else "OFF"
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

	-- Automático (con el pase y encendido): mientras haya enemigos cerca manda hacia dónde
	-- apuntas (el ratón; con mando o táctil, delante del personaje) y el servidor dispara solo
	-- cuando el disparo va a dar a alguien. Mientras mantienes pulsado no hace falta.
	task.spawn(function()
		local lastSent: Vector3? = nil
		local lastAt = 0
		while true do
			task.wait(REPEAT_SECONDS)
			if hold ~= nil or magicPress ~= nil or altHeld == "Block" or player:GetAttribute(Constants.Attributes.AutoFire) ~= true or not hasAutoPass() then
				continue
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not (root and root:IsA("BasePart")) or #enemiesInRange(root.Position) == 0 then
				continue
			end
			local last = UserInputService:GetLastInputType()
			local pointer = UserInputService.MouseEnabled and last ~= Enum.UserInputType.Touch and not string.find(last.Name, "Gamepad", 1, true)
			local aim = if isMelee(styleNow()) then meleeAim() elseif pointer then AimPoint.mouse() else AimPoint.facing()
			local now = os.clock()
			if aim and (lastSent == nil or (aim - lastSent).Magnitude > 0.5 or now - lastAt > 0.3) then
				send(aim, "Aim")
				lastSent = aim
				lastAt = now
			end
		end
	end)

	-- Arma equipada (o el estilo, si no es Armas) y su daño por segundo sobre el botón
	local ATTACK_WORDS = { Weapons = "Disparar", Warrior = "Atacar", Fists = "Golpear", Magic = "Lanzar" }
	local function refreshWeaponPill()
		local def = WeaponConfig.Weapons[player:GetAttribute(Constants.Attributes.EquippedWeapon)] or WeaponConfig.Weapons[WeaponConfig.StarterWeapon]
		local dps = player:GetAttribute(Constants.Attributes.DamagePerSecond)
		local styleId = player:GetAttribute(Constants.Attributes.CombatStyle)
		local style = if typeof(styleId) == "string" and styleId ~= "Weapons" then StyleConfig.Styles[styleId] else nil
		local dpsText = formatNumber(if typeof(dps) == "number" then dps else 0)
		if style and def.Category == styleId then
			-- Puños / Magia: sus guantes o su bastón
			ui.WeaponPill.Text = ("%s %s · %s/s"):format(def.Icon, def.DisplayName, dpsText)
			ui.WeaponPill.TextColor3 = def.Color
		elseif style then
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

	-- Orbes que están cargando otros magos (aviso "Charging"); se quitan al lanzarlo
	local othersCharging: { [Player]: Part } = {}
	Players.PlayerRemoving:Connect(function(leaving)
		local orb = othersCharging[leaving]
		if orb then
			orb:Destroy()
			othersCharging[leaving] = nil
		end
	end)

	petAbilityRemote.OnClientEvent:Connect(function(event)
		if typeof(event) ~= "table" or typeof(event.Owner) ~= "Instance" then
			return
		end
		local owner = event.Owner :: Player
		local isOwner = owner == player

		if event.Kind == "PlayerShot" and typeof(event.Target) == "Vector3" then
			local def = WeaponConfig.Weapons[event.WeaponId] or WeaponConfig.Weapons[WeaponConfig.StarterWeapon]
			local style = if typeof(event.Style) == "string" and StyleConfig.Styles[event.Style] then event.Style else "Weapons"
			-- El color del arma, o el de los guantes / la espada (si no, el del estilo); la
			-- magia, el de su elemento
			local gearOfStyle = style == "Weapons" or def.Category == style
			local color = if gearOfStyle then def.Color else StyleConfig.Styles[style].Color
			local elementSpec = if style == "Magic" and typeof(event.Element) == "string" then StyleConfig.Styles.Magic.Elements[event.Element] else nil
			if elementSpec and elementSpec.Color then
				color = elementSpec.Color
			end
			-- Rayos que saltan de enemigo en enemigo (cristal, rayo)
			local function chainFx(from: Vector3)
				if typeof(event.Chain) ~= "table" then
					return
				end
				local previous = from
				for _, point in event.Chain do
					if typeof(point) == "Vector3" then
						beamEffect(previous, point, color, 0.25)
						emitAt("Glint", point, color, 3)
						previous = point
					end
				end
			end
			local crit = event.Crit == true
			local combo = if typeof(event.Combo) == "string" then event.Combo else nil
			local character = owner.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local target = event.Target :: Vector3
			-- Tu personaje mira hacia donde va el disparo (el automático, F con el mando) si
			-- está quieto y no estás manteniendo pulsado (entonces ya mira al cursor)
			if isOwner and hold == nil and not AimCamera.isAds() then
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.MoveDirection.Magnitude < 0.1 then
					AimPoint.faceToward(target)
				end
			end
			local from = if root and root:IsA("BasePart") then root.Position + Vector3.new(0, 1.2, 0) else target
			local hand = CharacterPose.handPosition(character) or from
			local soundAt = if isOwner then nil else from
			-- Números, chispas y sonido de acierto (y la ✕ de la mira si es tuyo).
			-- `styleSound`: el sonido del golpe de este estilo en vez del genérico
			local function impact(styleSound: string?)
				emitAt("Glint", target, color, if crit then 10 else 4)
				if typeof(event.Splash) == "number" then
					impactRing(target, event.Splash, color)
				end
				-- Crítico: número dorado y más grande
				showHits(event.Hits, if crit then THEME.Gold else color, isOwner, 0.8, if crit then 1.6 else nil)
				if typeof(event.Hits) == "table" and #event.Hits > 0 then
					local killed = false
					for _, hit in event.Hits do
						killed = killed or (typeof(hit) == "table" and hit.Killed == true)
					end
					if styleSound then
						playStyleSound(styleSound, soundAt)
					end
					if isOwner then
						CombatHud.hitMarker(killed)
						if killed then
							playVaried(killSound, 0.9, 0.05)
						elseif not styleSound then
							playVaried(hitSound, if style == "Fists" then 0.95 elseif crit then 1.6 else 1.35, 0.07)
						end
					end
				end
			end
			if style == "Fists" then
				-- Puñetazo: el personaje lanza el puño, se echa encima del enemigo (el tuyo; los
				-- demás lo ven por Roblox) y el golpe estalla justo donde el puño lo toca, con un
				-- frenazo de la animación y la cámara que tiembla. El gancho (el 3.º seguido) es
				-- más grande y lo levanta por los aires.
				local big = combo ~= nil
				if not StyleAnimations.enabled("Fists") then
					CharacterPose.punch(character)
				elseif isOwner then
					StyleAnimations.punch(big)
				end
				playStyleSound("PunchSwing", soundAt, if big then 0.8 else 1)
				local first = if typeof(event.Hits) == "table" then event.Hits[1] else nil
				local hitModel = if typeof(first) == "table" then first.Model else nil
				if event.Miss == true or hitModel == nil then
					-- Al aire: solo el soplo delante del puño
					local flat = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
					local ahead = if flat.Magnitude > 0.05 then flat.Unit * math.min(flat.Magnitude, 2.5) else Vector3.zero
					emitAt("Miss", from + ahead, Color3.new(1, 1, 1), 4)
					impact()
				else
					local _, direction, reach = punchContact(from, target, hitModel)
					local lungeSeconds = 0
					if isOwner and root and root:IsA("BasePart") then
						keepSteady(root, 0.6)
						lungeSeconds = lunge(root, direction, reach - PUNCH_REACH, hitModel)
					end
					-- El golpe llega cuando el brazo está estirado (y la embestida ha terminado)
					task.delay(math.max(lungeSeconds, if big then 0.12 else 0.06), function()
						local now = if root and root:IsA("BasePart") and root.Parent then root.Position + Vector3.new(0, 1.2, 0) else from
						local contact, towards = punchContact(now, target, hitModel)
						punchFx(contact, towards, color, big)
						emitAt("Spark", contact, color, if big then 20 else 9)
						if big then
							impactRing(target, 5, color)
							comboLabel(target, combo :: string, color)
						end
						chainFx(contact)
						if isOwner then
							shakeCamera(if big then 0.62 else 0.34, if big then 5 else 1.5)
							StyleAnimations.hitstop(if big then 0.09 else 0.045)
						end
						impact(if big then "PunchHook" else "PunchHit")
					end)
				end
			elseif style == "Warrior" then
				-- Tajo de espada: el brazo barre y un arco de luz pasa delante (el 3.º, una
				-- rueda alrededor); el contraataque tras una parada sale dorado y más grande
				local step = math.clamp(math.floor(tonumber(event.Step) or 1), 1, 3)
				local counter = event.Counter == true
				local center = if root and root:IsA("BasePart") then root.Position else target
				local direction = if typeof(event.Direction) == "Vector3" then event.Direction else target - center
				local radius = tonumber(event.Radius) or 10
				local arcColor = if counter then THEME.Gold else color
				-- La animación de la espada la pone tu cliente en tu personaje (los demás la ven
				-- por Roblox); sin animaciones, el movimiento a mano en cada cliente
				if not StyleAnimations.enabled("Warrior") then
					CharacterPose.slash(character, step)
				elseif isOwner then
					StyleAnimations.slash(step)
				end
				slashArc(center, direction, radius, arcColor, step, counter or step == 3)
				if step == 3 then
					impactRing(center, radius * 0.9, arcColor)
				end
				playStyleSound(if step == 3 then "SwordSpin" else "SwordSwing", soundAt, if counter then 0.85 else 1)
				local slashes = StyleConfig.Styles.Warrior.Slashes
				local hitSomeone = typeof(event.Hits) == "table" and #event.Hits > 0
				if hitSomeone then
					emitAt("Spark", target, arcColor, if step == 3 or counter then 18 else 9)
					if counter then
						comboLabel(target, "¡Contraataque!", THEME.Gold)
						flashBall(target, Color3.new(1, 1, 1), 0.8, 6, 0.22)
					elseif step == 3 and slashes and slashes[3] and slashes[3].Name then
						comboLabel(target, slashes[3].Name, color)
					end
				end
				chainFx(target)
				impact("SwordHit")
			elseif style == "Magic" then
				-- Bola de energía desde la esfera del bastón, del color de su elemento: chispa
				-- pequeña sin maná, orbe enorme si la cargaste
				local charge = tonumber(event.Charge)
				local spark = event.Spark == true
				local scale = if charge then 1.3 + charge * 1.3 elseif spark then 0.5 else 1
				local others = othersCharging[owner]
				if others then
					others:Destroy()
					othersCharging[owner] = nil
				end
				if not StyleAnimations.enabled("Magic") then
					CharacterPose.cast(character, 0.12)
				elseif isOwner then
					StyleAnimations.cast()
				end
				local orbAt = CharacterPose.gearPoint(character, "Orb") or hand
				playStyleSound("MagicBolt", soundAt, if charge then 0.6 elseif spark then 1.35 else 1)
				magicOrb(orbAt, target, color, function()
					local big = charge ~= nil and charge >= 0.5
					flashBall(target, color, 1, if charge then 5 + charge * 9 elseif spark then 2.5 else 5, if big then 0.34 else 0.2)
					impactRing(target, if charge then 3 + charge * 5 elseif spark then 1.6 else 3, Color3.new(1, 1, 1))
					if big then
						playStyleSound("Explosion", soundAt, 1.25)
						emitAt("Glint", target, color, 14)
					end
					chainFx(target)
					if charge and charge >= 0.99 then
						comboLabel(target, "¡Orbe cargado!", color)
					end
					impact()
				end, scale)
			else
				-- Armas: fogonazo en la boca del arma, retroceso, trazo de cada bala (los
				-- perdigones de la escopeta, la bala que atraviesa del francotirador), flecha con
				-- el arco y un cohete con la bazuca (su explosión llega luego en "ShotImpact")
				local gun = if typeof(event.Gun) == "string" then event.Gun else GunLogic.kind(event.WeaponId)
				local feel = GUN_FEEL[gun] or GUN_FEEL.Pistol
				local isBow = def.Model == "Bow"
				local muzzle = CharacterPose.gearPoint(character, "Muzzle") or hand
				if not StyleAnimations.enabled("Weapons") then
					CharacterPose.recoil(character, feel.Recoil)
				elseif isOwner then
					StyleAnimations.shot()
				end
				if not isBow then
					muzzleFlash(muzzle, color, feel.Flash)
				end
				playStyleSound(if isBow then "GunBow" else "Gun" .. gun, soundAt)
				if isOwner then
					CombatHud.kick(feel.Kick)
				end
				if typeof(event.Delay) == "number" then
					rocketFx(muzzle, target, color, event.Delay)
				else
					local tracers = if typeof(event.Tracers) == "table" then event.Tracers else { { To = target, Hit = event.Miss ~= true } }
					local first = true
					for _, line in tracers do
						if typeof(line) == "table" and typeof(line.To) == "Vector3" then
							local to = line.To :: Vector3
							if isBow and first then
								travelBall(muzzle, to, color, 0.5, 140, function()
									emitAt("Glint", to, color, 4)
								end)
							else
								tracer(muzzle, to, color, feel.Tracer)
							end
							if line.Hit == true then
								emitAt("Spark", to, color, if gun == "Shotgun" then 2 else 5)
							else
								emitAt("Miss", to, Color3.fromRGB(200, 200, 200), 2)
							end
							first = false
						end
					end
					if combo then
						comboLabel(target, combo, color)
						flashBall(target, Color3.new(1, 1, 1), 0.6, 4, 0.18)
					end
					chainFx(target)
					impact()
				end
			end
		elseif event.Kind == "ShotImpact" and typeof(event.Position) == "Vector3" then
			-- Explosión del cohete de la bazuca
			local def = WeaponConfig.Weapons[event.WeaponId] or WeaponConfig.Weapons[WeaponConfig.StarterWeapon]
			local center = event.Position :: Vector3
			local radius = tonumber(event.Radius) or 8
			local crit = event.Crit == true
			flashBall(center, Color3.fromRGB(255, 220, 140), 1.5, radius * 1.5, 0.3)
			flashBall(center, def.Color, 1, radius * 1.9, 0.42)
			impactRing(center, radius, def.Color)
			emitAt("Spark", center, Color3.fromRGB(255, 190, 90), 24)
			emitAt("Miss", center, Color3.fromRGB(110, 110, 116), 8)
			playStyleSound("Explosion", if isOwner then nil else center)
			showHits(event.Hits, if crit then THEME.Gold else def.Color, isOwner, 1, if crit then 1.6 else nil)
			if isOwner and typeof(event.Hits) == "table" and #event.Hits > 0 then
				local killed = false
				for _, hit in event.Hits do
					killed = killed or (typeof(hit) == "table" and hit.Killed == true)
				end
				CombatHud.hitMarker(killed)
				if killed then
					playVaried(killSound, 0.9, 0.05)
				end
			end
		elseif event.Kind == "Blocked" and typeof(event.Position) == "Vector3" then
			-- Golpe bloqueado con la espada (sin parada): chispas y choque de metal
			local at = event.Position :: Vector3
			flashBall(at, Color3.new(1, 1, 1), 0.5, 2.6, 0.12)
			emitAt("Spark", at, Color3.fromRGB(210, 225, 255), 10)
			playStyleSound("SwordHit", if isOwner then nil else at, 0.7)
		elseif event.Kind == "Parry" and typeof(event.Position) == "Vector3" then
			-- Parada perfecta del Guerrero: destello blanco, chispas doradas
			local at = event.Position :: Vector3
			flashBall(at, Color3.new(1, 1, 1), 1, 7, 0.25)
			emitAt("Spark", at, THEME.Gold, 22)
			impactRing(at, 5, THEME.Gold)
			comboLabel(at, "¡Parada perfecta!", THEME.Gold)
			playStyleSound("Parry", if isOwner then nil else at)
		elseif event.Kind == "Charging" then
			-- Otro mago cargando un orbe: crece en su bastón (el tuyo lo dibuja tu cliente)
			if isOwner then
				return
			end
			local previous = othersCharging[owner]
			if previous then
				previous:Destroy()
			end
			local elementSpec = if typeof(event.Element) == "string" then StyleConfig.Styles.Magic.Elements[event.Element] else nil
			local color = if elementSpec and elementSpec.Color then elementSpec.Color else StyleConfig.Styles.Magic.Color
			local orb = fxPart(Vector3.one * 0.6, CFrame.new(), color)
			orb.Shape = Enum.PartType.Ball
			orb.Transparency = 0.2
			othersCharging[owner] = orb
			local began = os.clock()
			local full = StyleConfig.Styles.Magic.Charge.Full
			local connection
			connection = RunService.RenderStepped:Connect(function()
				local character = owner.Character
				local at = CharacterPose.gearPoint(character, "Orb") or CharacterPose.handPosition(character)
				local elapsed = os.clock() - began
				if not orb.Parent or othersCharging[owner] ~= orb or elapsed > full + 2.5 or not at then
					connection:Disconnect()
					if orb.Parent then
						orb:Destroy()
					end
					if othersCharging[owner] == orb then
						othersCharging[owner] = nil
					end
					return
				end
				local fraction = math.clamp(elapsed / full, 0, 1)
				orb.Size = Vector3.one * (0.6 + 2.8 * fraction)
				orb.CFrame = CFrame.new(at)
			end)
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

	-- Diamantes: brotan del enemigo, flotan un instante y vuelan hasta el jugador (uno por 💎,
	-- hasta ORBS_KILL).
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
			orb.Name = if isGolden then "GoldenOrb" else "DiamondDrop"
			orb.Shape = if isGolden then Enum.PartType.Ball else Enum.PartType.Block
			local tilt = if isGolden then CFrame.identity else GEM_TILT
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
			orb.CFrame = CFrame.new(from) * tilt
			if isGolden then
				local light = Instance.new("PointLight")
				light.Color = GOLDEN_COLOR
				light.Range = 12
				light.Brightness = 3
				light.Shadows = false
				light.Parent = orb
			end
			orb.Parent = fxFolder
			TweenService:Create(orb, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = CFrame.new(peak) * tilt * CFrame.Angles(0, math.pi, 0) }):Play()
			local hold = if isGolden then 0.6 else 0.3 + index * 0.04
			task.delay(0.35 + hold, function()
				if not orb.Parent then
					return
				end
				local goal = if root.Parent then root.Position else peak
				TweenService:Create(orb, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = CFrame.new(goal) * tilt,
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
				dropOrbs(at, math.clamp(energy, 1, if isBoss then ORBS_BOSS else ORBS_KILL), golden)
			end
		end
		if not (isKill or isBoss) then
			return -- golpe suelto: solo la moneda y el salto del contador
		end
		local loot = ("+%s 💰"):format(formatNumber(amount)) .. (if energy > 0 then ("  +%s 💎"):format(formatNumber(energy)) else "")
		if golden then
			Toasts.show(("🌟 ¡BOTÍN DORADO!  ×10  ·  %s"):format(loot), { Color = GOLDEN_COLOR, Key = "GoldenOrb" })
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

	-- Barras de jefe: se muestran al acercarse a una arena con su jefe vivo. Con dos jefes a
	-- la vez (las mitades del Coloso del Equilibrio), una al lado de la otra.
	local enragedAnnounced: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local barOwner: { [number]: Model? } = {}
	local bossBarShown = false
	local function fillBar(bar, model: Model, health: number, maxHealth: number, compact: boolean)
		local enraged = model:GetAttribute("Enraged") == true
		-- La IA del jefe publica a quién persigue (TargetUserId)
		local chasing = model:GetAttribute("TargetUserId") == player.UserId
		local name = tostring(model:GetAttribute("DisplayName"))
		local status = if compact then "" else (if chasing then "  ·  ¡Te persigue!" else "") .. (if enraged then "  ·  ¡Furioso!" else "")
		bar.Name.Text = name .. status .. ("   %s / %s"):format(formatNumber(health), formatNumber(maxHealth))
		bar.Name.TextColor3 = if enraged then BOSS_ENRAGED_COLOR elseif chasing then BOSS_CHASE_COLOR else THEME.Text
		local def = EnemyConfig.Types[model:GetAttribute("EnemyType")]
		local tint = def and def.Look and def.Look.Secondary
		bar.Fill.BackgroundColor3 = if enraged then BOSS_ENRAGED_COLOR elseif compact and typeof(tint) == "Color3" then tint else BOSS_BAR_COLOR
		local fraction = math.clamp(health / maxHealth, 0, 1)
		bar.Fill.Size = UDim2.fromScale(fraction, 1)
		-- El tramo claro alcanza a la vida real con un pequeño retraso.
		if fraction < bar.TrailTarget then
			TweenService:Create(bar.Trail, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.25), { Size = UDim2.fromScale(fraction, 1) }):Play()
		else
			bar.Trail.Size = UDim2.fromScale(fraction, 1)
		end
		bar.TrailTarget = fraction
		local enrageAt = def and def.Enrage and def.Enrage.HealthFraction
		bar.EnrageMark.Visible = enrageAt ~= nil and not enraged
		if enrageAt then
			bar.EnrageMark.Position = UDim2.fromScale(enrageAt, 0.5)
		end
		local splitAt = def and def.Split and def.Split.HealthFraction
		bar.SplitMark.Visible = splitAt ~= nil
		if splitAt then
			bar.SplitMark.Position = UDim2.fromScale(splitAt, 0.5)
		end
		-- Anunciar la entrada en furia una vez por vida del jefe
		if enraged and not enragedAnnounced[model] then
			enragedAnnounced[model] = true
			showBanner(("¡%s entra en furia!"):format(name), BOSS_ENRAGED_COLOR)
		elseif not enraged then
			enragedAnnounced[model] = nil
		end
	end
	task.spawn(function()
		while true do
			task.wait(0.25)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local enemiesFolder = Workspace:FindFirstChild("Enemies")
			local found = {}
			if root and root:IsA("BasePart") and enemiesFolder then
				for _, zoneFolder in enemiesFolder:GetChildren() do
					for _, model in zoneFolder:GetChildren() do
						if model:IsA("Model") and model:GetAttribute("Kind") == "Boss" and WaveVisibility.isVisible(model) then
							local center = model:GetAttribute("ArenaCenter")
							local radius = model:GetAttribute("ArenaRadius")
							local health = model:GetAttribute("Health")
							local maxHealth = model:GetAttribute("MaxHealth")
							if typeof(center) == "Vector3" and typeof(radius) == "number" and typeof(health) == "number" and typeof(maxHealth) == "number" and health > 0 and maxHealth > 0 then
								local offset = root.Position - center
								if Vector2.new(offset.X, offset.Z).Magnitude <= radius + BOSS_BAR_RANGE then
									table.insert(found, { Model = model, Health = health, MaxHealth = maxHealth })
								end
							end
						end
					end
				end
			end
			-- Siempre en el mismo orden (fuego a la izquierda: por tipo)
			table.sort(found, function(a, b)
				return tostring(a.Model:GetAttribute("EnemyType")) > tostring(b.Model:GetAttribute("EnemyType"))
			end)
			local count = math.min(#found, #ui.BossBars)
			local compact = count > 1
			for index, bar in ui.BossBars do
				local entry = found[index]
				local visible = entry ~= nil and index <= count
				if visible then
					if barOwner[index] ~= entry.Model then
						barOwner[index] = entry.Model
						bar.TrailTarget = 1
					end
					fillBar(bar, entry.Model, entry.Health, entry.MaxHealth, compact)
					-- Dos a la vez: mitad de ancho cada una, una a cada lado del centro
					bar.Bar.Size = UDim2.fromOffset(if compact then 216 else 440, 54)
					bar.Bar.AnchorPoint = Vector2.new(if compact then (if index == 1 then 1 else 0) else 0.5, 0)
					bar.Bar.Position = UDim2.new(0.5, if compact then (if index == 1 then -4 else 4) else 0, 0, 0)
				else
					barOwner[index] = nil
				end
				if bar.Bar.Visible ~= visible then
					bar.Bar.Visible = visible
				end
			end
			local shown = count > 0
			if bossBarShown ~= shown then
				bossBarShown = shown
				HudDock.setBossBar(shown)
			end
		end
	end)
end

return CombatController
