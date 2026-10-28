-- CombatController · Effects: constantes, sonidos, reserva de emisores y efectos de golpe y puñetazo.
-- Parte de CombatController (ver CombatController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local StyleConfig = require(Shared.Config.StyleConfig)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)

local ctx: any -- tabla de estado compartida (la crea CombatController/init.luau)

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


local player = Players.LocalPlayer

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
	part.Parent = ctx.fxFolder
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
	if not (emitter and emitter.Parent and emitter.Parent.Parent == ctx.fxFolder) then
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

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.ATTACK_ACTION = ATTACK_ACTION
	context.AUTO_ACTION = AUTO_ACTION
	context.AUTO_OFF = AUTO_OFF
	context.AUTO_ON = AUTO_ON
	context.BOSS_BAR_COLOR = BOSS_BAR_COLOR
	context.BOSS_BAR_RANGE = BOSS_BAR_RANGE
	context.BOSS_CHASE_COLOR = BOSS_CHASE_COLOR
	context.BOSS_ENRAGED_COLOR = BOSS_ENRAGED_COLOR
	context.COINS_BOSS = COINS_BOSS
	context.COINS_KILL = COINS_KILL
	context.COIN_COLOR = COIN_COLOR
	context.COIN_SIZE = COIN_SIZE
	context.FONTS = FONTS
	context.GEM_TILT = GEM_TILT
	context.GOLDEN_COLOR = GOLDEN_COLOR
	context.GUN_FEEL = GUN_FEEL
	context.LAYOUT = LAYOUT
	context.MAX_DAMAGE_NUMBERS = MAX_DAMAGE_NUMBERS
	context.MAX_FLYING = MAX_FLYING
	context.ORBS_BOSS = ORBS_BOSS
	context.ORBS_KILL = ORBS_KILL
	context.ORB_COLOR = ORB_COLOR
	context.ORB_SIZE = ORB_SIZE
	context.POOL_PREFIX = POOL_PREFIX
	context.PUNCH_CROWD_RADIUS = PUNCH_CROWD_RADIUS
	context.PUNCH_LUNGE_MAX = PUNCH_LUNGE_MAX
	context.PUNCH_LUNGE_SPEED = PUNCH_LUNGE_SPEED
	context.PUNCH_MAX_RISE = PUNCH_MAX_RISE
	context.PUNCH_MAX_SPEED = PUNCH_MAX_SPEED
	context.PUNCH_REACH = PUNCH_REACH
	context.REPEAT_SECONDS = REPEAT_SECONDS
	context.SELECT_RANGE = SELECT_RANGE
	context.TAP_MOVE = TAP_MOVE
	context.TAP_SECONDS = TAP_SECONDS
	context.THEME = THEME
	context.beamEffect = beamEffect
	context.comboLabel = comboLabel
	context.emitAt = emitAt
	context.flashBall = flashBall
	context.fxPart = fxPart
	context.makeSound = makeSound
	context.playStyleSound = playStyleSound
	context.playVaried = playVaried
	context.player = player
	context.punchContact = punchContact
	context.punchFx = punchFx
end

function Part.link(context: any)
	-- (nada que enlazar)
end

return Part
