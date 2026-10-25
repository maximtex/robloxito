-- Efectos de las oleadas en el cliente (solo presentación; solo los ve este jugador). Los
-- usa WaveController según lo que pasa en tu partida:
-- - sound(nombre, tono?, retraso?): sonidos de WaveConfig.Sounds (precargados al empezar).
-- - flash(color, fuerza): destello de toda la pantalla.
-- - pulse(color, fuerza, segundos): viñeta de color en los bordes que se apaga sola.
-- - setDanger(on): viñeta roja que late mientras dura el jefe.
-- - tint(ajustes, espera, vuelta): color de la imagen (ColorCorrection en la cámara) que
--   vuelve a la normalidad; p. ej. gris al caer.
-- - confetti(cantidad) / confettiBurst(punto, cantidad) / confettiFrom(elemento, cantidad):
--   lluvia de confeti o estallido desde un punto o un elemento de la pantalla.
-- - ring(...) / sparkle(...): onda en el suelo y chispas que suben, en el mundo.
-- - shake / kick: sacudida y zoom de AbilityController (respetan "Reducir movimiento").
-- Todo se crea al vuelo y se borra solo; las capas de pantalla no bloquean clics.

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local WaveConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("WaveConfig"))
local AbilityController = require(script.Parent.AbilityController)

local WaveFx = {}

local player = Players.LocalPlayer

local DANGER_COLOR = Color3.fromRGB(220, 30, 50)
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 206, 84),
	Color3.fromRGB(255, 120, 160),
	Color3.fromRGB(110, 210, 255),
	Color3.fromRGB(150, 236, 120),
	Color3.fromRGB(196, 140, 255),
	Color3.fromRGB(255, 255, 255),
}
local MAX_CONFETTI = 160 -- tope de piezas a la vez (por si se juntan varias celebraciones)

local sounds: { [string]: Sound } = {}
local backGui: ScreenGui? = nil -- destello y viñeta: por debajo del HUD
local frontGui: ScreenGui? = nil -- confeti: por encima de las ventanas
local flashFrame: Frame? = nil
local edges: { Frame } = {}
local worldFolder: Folder? = nil
local confettiCount = 0

-- Viñeta: un pulso que decae y el latido del jefe; se ve el más fuerte de los dos.
local pulseLevel = 0
local pulseDecay = 1
local pulseColor = DANGER_COLOR
local dangerOn = false
local vignetteShown = false

local tintEffect: ColorCorrectionEffect? = nil
local tintToken = 0

-- Sonidos ------------------------------------------------------------------------------

local function soundFor(name: string): Sound?
	local existing = sounds[name]
	if existing and existing.Parent then
		return existing
	end
	local spec = WaveConfig.Sounds[name]
	if not spec then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "Wave" .. name
	sound.SoundId = spec.Id
	sound.Volume = spec.Volume or 0.5
	sound.PlaybackSpeed = spec.Pitch or 1
	sound.Parent = SoundService
	sounds[name] = sound
	return sound
end

function WaveFx.sound(name: string, pitchScale: number?, delay: number?)
	local function play()
		local sound = soundFor(name)
		if not sound then
			return
		end
		local spec = WaveConfig.Sounds[name]
		sound.PlaybackSpeed = (spec.Pitch or 1) * (pitchScale or 1)
		sound.TimePosition = 0
		sound:Play()
	end
	if delay and delay > 0 then
		task.delay(delay, play)
	else
		play()
	end
end

-- Cámara (la de las habilidades: misma sensación en todo el juego) -------------------------

function WaveFx.shake(amount: number)
	if AbilityController.shake then
		AbilityController.shake(amount)
	end
end

function WaveFx.kick(degrees: number)
	if AbilityController.kickFov then
		AbilityController.kickFov(degrees)
	end
end

-- Pantalla -----------------------------------------------------------------------------

function WaveFx.flash(color: Color3, strength: number?)
	local frame = flashFrame
	if not frame then
		return
	end
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 1 - 0.6 * math.clamp(strength or 0.5, 0, 1)
	TweenService:Create(frame, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

function WaveFx.pulse(color: Color3, strength: number, seconds: number)
	pulseColor = color
	pulseLevel = math.max(pulseLevel, math.clamp(strength, 0, 1))
	pulseDecay = pulseLevel / math.max(0.1, seconds)
end

function WaveFx.setDanger(on: boolean)
	dangerOn = on
end

local function stepVignette(dt: number)
	local danger = if dangerOn then 0.25 + 0.1 * math.sin(os.clock() * 4.2) else 0
	pulseLevel = math.max(0, pulseLevel - dt * pulseDecay)
	local level = math.max(pulseLevel, danger)
	if level <= 0.002 then
		if vignetteShown then
			vignetteShown = false
			for _, frame in edges do
				frame.BackgroundTransparency = 1
			end
		end
		return
	end
	vignetteShown = true
	local color = if pulseLevel >= danger then pulseColor else DANGER_COLOR
	for _, frame in edges do
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = 1 - level
	end
end

-- ColorCorrection propio en la cámara: se pone ya y vuelve a la normalidad con calma.
function WaveFx.tint(target: { TintColor: Color3?, Saturation: number?, Contrast: number?, Brightness: number? }, hold: number, back: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local effect = tintEffect
	if not (effect and effect.Parent == camera) then
		if effect then
			effect:Destroy()
		end
		effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "WaveTint"
		effect.Parent = camera
		tintEffect = effect
	end
	local current = effect :: ColorCorrectionEffect
	tintToken += 1
	local token = tintToken
	current.TintColor = target.TintColor or Color3.new(1, 1, 1)
	current.Saturation = target.Saturation or 0
	current.Contrast = target.Contrast or 0
	current.Brightness = target.Brightness or 0
	current.Enabled = true
	task.delay(hold, function()
		if tintToken ~= token or not current.Parent then
			return
		end
		TweenService:Create(current, TweenInfo.new(back, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TintColor = Color3.new(1, 1, 1),
			Saturation = 0,
			Contrast = 0,
			Brightness = 0,
		}):Play()
	end)
end

-- Confeti ------------------------------------------------------------------------------

local function confettiPiece(gui: ScreenGui, color: Color3): Frame
	local piece = Instance.new("Frame")
	piece.Name = "Confetti"
	piece.BorderSizePixel = 0
	piece.AnchorPoint = Vector2.new(0.5, 0.5)
	piece.Size = UDim2.fromOffset(math.random(7, 11), math.random(12, 19))
	piece.BackgroundColor3 = color
	piece.Rotation = math.random(0, 360)
	piece.Active = false
	piece.Parent = gui
	confettiCount += 1
	piece.Destroying:Once(function()
		confettiCount -= 1
	end)
	return piece
end

-- Cae desde arriba por toda la pantalla.
function WaveFx.confetti(count: number)
	local gui = frontGui
	if not gui then
		return
	end
	local size = gui.AbsoluteSize
	if size.X < 10 or size.Y < 10 then
		return
	end
	local total = math.min(count, MAX_CONFETTI - confettiCount)
	for _ = 1, total do
		local piece = confettiPiece(gui, CONFETTI_COLORS[math.random(#CONFETTI_COLORS)])
		local startX = math.random() * size.X
		piece.Position = UDim2.fromOffset(startX, -20 - math.random() * size.Y * 0.35)
		local fall = 1.8 + math.random() * 1.4
		TweenService:Create(piece, TweenInfo.new(fall, Enum.EasingStyle.Linear), {
			Position = UDim2.fromOffset(startX + (math.random() - 0.5) * 240, size.Y + 30),
			Rotation = piece.Rotation + math.random(-600, 600),
		}):Play()
		Debris:AddItem(piece, fall + 0.1)
	end
end

-- Estalla desde un punto de la pantalla (en píxeles) y luego cae.
function WaveFx.confettiBurst(origin: Vector2, count: number)
	local gui = frontGui
	if not gui then
		return
	end
	local size = gui.AbsoluteSize
	local total = math.min(count, MAX_CONFETTI - confettiCount)
	for _ = 1, total do
		local piece = confettiPiece(gui, CONFETTI_COLORS[math.random(#CONFETTI_COLORS)])
		piece.Position = UDim2.fromOffset(origin.X, origin.Y)
		local angle = math.random() * math.pi * 2
		local reach = 90 + math.random() * 200
		local peak = origin + Vector2.new(math.cos(angle) * reach, math.sin(angle) * reach * 0.6 - 70)
		local up = TweenService:Create(piece, TweenInfo.new(0.35 + math.random() * 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(peak.X, peak.Y),
			Rotation = piece.Rotation + math.random(-200, 200),
		})
		local fall = 1.3 + math.random() * 0.9
		up.Completed:Once(function()
			if piece.Parent then
				TweenService:Create(piece, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.fromOffset(peak.X + (math.random() - 0.5) * 120, size.Y + 30),
					Rotation = piece.Rotation + math.random(-500, 500),
				}):Play()
			end
		end)
		up:Play()
		Debris:AddItem(piece, 0.55 + fall + 0.1)
	end
end

-- Estallido desde el centro de un elemento de la interfaz (de cualquier ScreenGui).
function WaveFx.confettiFrom(target: GuiObject, count: number)
	local center = target.AbsolutePosition + target.AbsoluteSize / 2
	local screen = target:FindFirstAncestorWhichIsA("ScreenGui")
	if screen and not screen.IgnoreGuiInset then
		local inset = GuiService:GetGuiInset()
		center += inset
	end
	WaveFx.confettiBurst(center, count)
end

-- Mundo --------------------------------------------------------------------------------

local function folder(): Folder
	local existing = worldFolder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "ClientWaveFxWorld"
	created.Parent = Workspace
	worldFolder = created
	return created
end

-- Onda en el suelo: un aro (no un disco: no pinta el suelo entero) hecho de tramos que se
-- abren a la vez y se apagan. Cada tramo mira hacia fuera: X = a lo largo del aro, Z = grosor.
local RING_SEGMENTS = 32

function WaveFx.ring(position: Vector3, color: Color3, fromDiameter: number, toDiameter: number, seconds: number, transparency: number?)
	local parent = folder()
	local fromRadius = math.max(0.5, fromDiameter / 2)
	local toRadius = math.max(fromRadius, toDiameter / 2)
	local thickness = math.clamp(toRadius * 0.07, 0.4, 1.4)
	local center = position + Vector3.new(0, 0.2, 0)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function arc(radius: number): number
		return 2 * math.pi * radius / RING_SEGMENTS * 1.1 -- un poco más largo: sin huecos entre tramos
	end
	for index = 1, RING_SEGMENTS do
		local angle = index / RING_SEGMENTS * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local segment = Instance.new("Part")
		segment.Name = "WaveRing"
		segment.Anchored = true
		segment.CanCollide = false
		segment.CanQuery = false
		segment.CanTouch = false
		segment.CastShadow = false
		segment.Material = Enum.Material.Neon
		segment.Color = color
		segment.Transparency = transparency or 0.2
		segment.Size = Vector3.new(arc(fromRadius), 0.3, thickness)
		segment.CFrame = CFrame.lookAt(center + direction * fromRadius, center + direction * (fromRadius + 1))
		segment.Parent = parent
		TweenService:Create(segment, info, {
			Size = Vector3.new(arc(toRadius), 0.12, thickness * 0.5),
			CFrame = CFrame.lookAt(center + direction * toRadius, center + direction * (toRadius + 1)),
			Transparency = 1,
		}):Play()
		Debris:AddItem(segment, seconds + 0.1)
	end
end

-- Chispas que suben (pocas partículas, de un solo uso).
function WaveFx.sparkle(position: Vector3, color: Color3, amount: number)
	local holder = Instance.new("Part")
	holder.Name = "WaveSparkle"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.CFrame = CFrame.new(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(2, 6)
	emitter.Acceleration = Vector3.new(0, 7, 0)
	emitter.Drag = 1.5
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Parent = holder
	holder.Parent = folder()
	emitter:Emit(amount)
	Debris:AddItem(holder, 1.6)
end

-- Pies del personaje (para efectos alrededor de ti).
function WaveFx.feet(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	local hip = if humanoid then humanoid.HipHeight else 2
	return root.Position - Vector3.new(0, root.Size.Y / 2 + hip, 0)
end

-- Arranque ------------------------------------------------------------------------------

local function edge(parent: ScreenGui, name: string, size: UDim2, position: UDim2, anchor: Vector2, rotation: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = DANGER_COLOR
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = anchor
	frame.Position = position
	frame.Size = size
	frame.Active = false
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation -- el lado opaco (0) mira al borde de la pantalla
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.55, 0.72),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = frame
	frame.Parent = parent
	return frame
end

function WaveFx.init()
	local playerGui = player:WaitForChild("PlayerGui")
	for _, name in { "WaveFxBack", "WaveFxFront" } do
		local existing = playerGui:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end

	local back = Instance.new("ScreenGui")
	back.Name = "WaveFxBack"
	back.ResetOnSpawn = false
	back.IgnoreGuiInset = true
	back.DisplayOrder = 2 -- por debajo de todo el HUD (3 en adelante)
	back.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	edges = {
		edge(back, "Top", UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 0), Vector2.new(0, 0), 90),
		edge(back, "Bottom", UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 1), Vector2.new(0, 1), -90),
		edge(back, "Left", UDim2.fromScale(0.22, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0), 0),
		edge(back, "Right", UDim2.fromScale(0.22, 1), UDim2.fromScale(1, 0), Vector2.new(1, 0), 180),
	}
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.Active = false
	flash.ZIndex = 2
	flash.Parent = back
	flashFrame = flash
	back.Parent = playerGui
	backGui = back

	local front = Instance.new("ScreenGui")
	front.Name = "WaveFxFront"
	front.ResetOnSpawn = false
	front.IgnoreGuiInset = true
	front.DisplayOrder = 9 -- sobre las ventanas de las oleadas (8)
	front.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	front.Parent = playerGui
	frontGui = front

	RunService.RenderStepped:Connect(stepVignette)

	-- Precarga: que el primer golpe suene a tiempo.
	task.spawn(function()
		local list = {}
		for name in WaveConfig.Sounds do
			local sound = soundFor(name)
			if sound then
				table.insert(list, sound)
			end
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
end

return WaveFx
