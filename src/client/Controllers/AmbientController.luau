-- Vida del mundo en este cliente (solo decorativo, nada se replica):
-- - Sonido ambiente del bosque: pájaros de día y grillos de noche (se mezclan con el ciclo
--   de DayNightController); más bajo en el Valle y apagado en la Caldera.
-- - Bandadas de pájaros que vuelan en círculo sobre la zona (de día).
-- - Mariposas que revolotean en las praderas, el claro del cristal, la plaza del pueblo y
--   el estanque cuando el jugador está cerca (de día).
-- - Luciérnagas alrededor del jugador al caer la noche.
-- - Cristales marcados con el atributo "Floaty" (ruinas) giran y flotan despacio.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local WildsConfig = require(Shared.Config.WildsConfig)
local DayNightController = require(script.Parent.DayNightController)

local AmbientController = {}

local player = Players.LocalPlayer

-- Pro Sound Effects (gratis en la Creator Store).
local SOUNDS = {
	Day = { Id = "rbxassetid://9112806424", Volume = 0.22 }, -- amanecer en la selva: pájaros
	Night = { Id = "rbxassetid://9117114470", Volume = 0.2 }, -- noche: grillos e insectos
}
-- Volumen del ambiente por zona (1 = completo).
local ZONE_AMBIENCE = { Forest = 1, CrystalValley = 0.55, EmberCaldera = 0 }

-- Sitios con mariposas (relativos al centro de la zona del Bosque): praderas y otros.
local BUTTERFLY_SPOTS = {
	{ Center = Vector2.new(0, 8), Radius = 30 }, -- claro del cristal
	{ Center = Vector2.new(0, 84), Radius = 16 }, -- plaza del pueblo
	{ Center = Vector2.new(36, 100), Radius = 14 }, -- estanque
	{ Center = Vector2.new(37, 30), Radius = 14 }, -- jardín de los huevos
}
for _, meadow in WildsConfig.Meadows do
	table.insert(BUTTERFLY_SPOTS, { Center = meadow.Center, Radius = meadow.Radius })
end
local BUTTERFLIES_PER_SPOT = 4
local BUTTERFLY_RANGE = 80 -- distancia del jugador a la que se activan
local BUTTERFLY_COLORS = {
	Color3.fromRGB(255, 170, 70), Color3.fromRGB(120, 190, 255), Color3.fromRGB(255, 140, 200),
	Color3.fromRGB(255, 236, 120), Color3.fromRGB(190, 150, 255), Color3.fromRGB(255, 255, 255),
}

local FLOCKS = {
	{ Offset = Vector2.new(-40, -60), Radius = 90, Height = 46, Speed = 0.09, Count = 5 },
	{ Offset = Vector2.new(70, 40), Radius = 70, Height = 38, Speed = -0.11, Count = 4 },
	{ Offset = Vector2.new(-20, 120), Radius = 60, Height = 42, Speed = 0.12, Count = 3 },
}

local folder: Folder
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { Workspace.Terrain }

local function zoneOrigin(zoneId: string): Vector3?
	local zone = ZoneConfig.Zones[zoneId]
	if not zone then
		return nil
	end
	return Vector3.new(GeneratorConfig.Position.X + zone.Center.X, GeneratorConfig.Position.Y, GeneratorConfig.Position.Z + zone.Center.Y)
end

local function currentZone(): string
	local zoneId = player:GetAttribute(Constants.Attributes.CurrentZone)
	return if typeof(zoneId) == "string" then zoneId else ZoneConfig.DefaultZone
end

local function piece(name: string, size: Vector3, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = folder
	return part
end

local function rootPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- Sonido ambiente -----------------------------------------------------------------------------

local function startSounds()
	local sounds = {}
	for key, spec in SOUNDS do
		local sound = Instance.new("Sound")
		sound.Name = "Ambience" .. key
		sound.SoundId = spec.Id
		sound.Looped = true
		sound.Volume = 0
		sound.Parent = SoundService
		sound:Play()
		sounds[key] = sound
	end
	RunService.Heartbeat:Connect(function(dt: number)
		local night = DayNightController.night()
		local zoneFactor = ZONE_AMBIENCE[currentZone()] or 0.5
		local blend = math.clamp(dt * 1.5, 0, 1)
		local dayTarget = SOUNDS.Day.Volume * (1 - night) * zoneFactor
		local nightTarget = SOUNDS.Night.Volume * night * zoneFactor
		sounds.Day.Volume += (dayTarget - sounds.Day.Volume) * blend
		sounds.Night.Volume += (nightTarget - sounds.Night.Volume) * blend
	end)
end

-- Pájaros -------------------------------------------------------------------------------------

type Bird = { Body: Part, Left: Part, Right: Part, Phase: number, Slot: Vector3 }

local function makeBird(index: number): Bird
	local color = Color3.fromRGB(60, 56, 64)
	local body = piece("Bird", Vector3.new(0.45, 0.35, 1.3), color)
	local left = piece("Wing", Vector3.new(1.5, 0.08, 0.6), color)
	local right = piece("Wing", Vector3.new(1.5, 0.08, 0.6), color)
	local row = math.ceil((index - 1) / 2)
	local side = if index % 2 == 0 then 1 else -1
	return { Body = body, Left = left, Right = right, Phase = index * 0.7, Slot = Vector3.new(side * row * 2.6, row * 0.3, row * 2.4) }
end

local function startBirds(parts: { BasePart }, frames: { CFrame }, birds: { any })
	for flockIndex, flock in FLOCKS do
		local list = {}
		for index = 1, flock.Count do
			table.insert(list, makeBird(index))
		end
		table.insert(birds, { Flock = flock, Birds = list, Seed = flockIndex * 1.9 })
	end
end

local function updateBirds(now: number, origin: Vector3, visible: boolean, parts: { BasePart }, frames: { CFrame }, birds: { any })
	for _, entry in birds do
		local flock = entry.Flock
		local angle = now * flock.Speed + entry.Seed
		local center = origin + Vector3.new(flock.Offset.X, flock.Height + math.sin(now * 0.3 + entry.Seed) * 4, flock.Offset.Y)
		local position = center + Vector3.new(math.cos(angle) * flock.Radius, 0, math.sin(angle) * flock.Radius)
		local ahead = center + Vector3.new(math.cos(angle + 0.05 * math.sign(flock.Speed)) * flock.Radius, 0, math.sin(angle + 0.05 * math.sign(flock.Speed)) * flock.Radius)
		local leader = CFrame.lookAt(position, ahead)
		for _, bird in entry.Birds do
			local frame = if visible then leader * CFrame.new(bird.Slot) else CFrame.new(0, -500, 0)
			local flap = math.sin(now * 9 + bird.Phase) * 0.6
			table.insert(parts, bird.Body)
			table.insert(frames, frame)
			table.insert(parts, bird.Left)
			table.insert(frames, frame * CFrame.new(-0.2, 0, 0) * CFrame.Angles(0, 0, flap) * CFrame.new(-0.75, 0, 0))
			table.insert(parts, bird.Right)
			table.insert(frames, frame * CFrame.new(0.2, 0, 0) * CFrame.Angles(0, 0, -flap) * CFrame.new(0.75, 0, 0))
		end
	end
end

-- Mariposas -----------------------------------------------------------------------------------

type Butterfly = { Left: Part, Right: Part, Spot: any, Position: Vector3, Target: Vector3, Ground: number, Phase: number, Speed: number, NextTarget: number }

local function groundAt(position: Vector3): number
	local hit = Workspace:Raycast(position + Vector3.new(0, 40, 0), Vector3.new(0, -100, 0), rayParams)
	return if hit then hit.Position.Y else position.Y
end

local function pickTarget(butterfly: Butterfly, origin: Vector3, random: Random)
	local spot = butterfly.Spot
	local angle = random:NextNumber(0, math.pi * 2)
	local distance = spot.Radius * math.sqrt(random:NextNumber())
	local flat = origin + Vector3.new(spot.Center.X + math.cos(angle) * distance, 0, spot.Center.Y + math.sin(angle) * distance)
	local ground = groundAt(flat + Vector3.new(0, 20, 0))
	butterfly.Target = Vector3.new(flat.X, ground + random:NextNumber(1, 3.5), flat.Z)
	butterfly.NextTarget = os.clock() + random:NextNumber(2, 5)
end

local function makeButterflies(random: Random): { Butterfly }
	local list = {}
	for _, spot in BUTTERFLY_SPOTS do
		for index = 1, BUTTERFLIES_PER_SPOT do
			local color = BUTTERFLY_COLORS[random:NextInteger(1, #BUTTERFLY_COLORS)]
			local left = piece("ButterflyWing", Vector3.new(0.5, 0.05, 0.45), color, Enum.Material.Neon)
			local right = piece("ButterflyWing", Vector3.new(0.5, 0.05, 0.45), color, Enum.Material.Neon)
			left.Transparency = 0.1
			right.Transparency = 0.1
			table.insert(list, {
				Left = left,
				Right = right,
				Spot = spot,
				Position = Vector3.new(0, -500, 0),
				Target = Vector3.new(0, -500, 0),
				Ground = 0,
				Phase = index * 1.3,
				Speed = random:NextNumber(2.2, 3.4),
				NextTarget = 0,
			})
		end
	end
	return list
end

local function updateButterflies(now: number, dt: number, origin: Vector3?, rootPos: Vector3?, day: boolean, list: { Butterfly }, random: Random, parts: { BasePart }, frames: { CFrame })
	for _, butterfly in list do
		local spot = butterfly.Spot
		local active = false
		if origin and rootPos and day then
			local center = origin + Vector3.new(spot.Center.X, 0, spot.Center.Y)
			local flatDistance = Vector2.new(rootPos.X - center.X, rootPos.Z - center.Z).Magnitude
			active = flatDistance < spot.Radius + BUTTERFLY_RANGE
		end
		local frame
		if active and origin then
			if butterfly.Position.Y < -400 then
				pickTarget(butterfly, origin, random)
				butterfly.Position = butterfly.Target
			end
			if now >= butterfly.NextTarget or (butterfly.Target - butterfly.Position).Magnitude < 0.6 then
				pickTarget(butterfly, origin, random)
			end
			local toTarget = butterfly.Target - butterfly.Position
			local step = math.min(toTarget.Magnitude, butterfly.Speed * dt)
			local wobble = Vector3.new(math.sin(now * 3.1 + butterfly.Phase), math.sin(now * 4.3 + butterfly.Phase) * 0.8, math.cos(now * 2.7 + butterfly.Phase)) * dt * 1.2
			if toTarget.Magnitude > 0.01 then
				butterfly.Position += toTarget.Unit * step + wobble
			end
			local heading = if toTarget.Magnitude > 0.01 then toTarget.Unit else Vector3.zAxis
			frame = CFrame.lookAt(butterfly.Position, butterfly.Position + Vector3.new(heading.X, 0, heading.Z) + Vector3.new(0, 0, 0.001))
		else
			butterfly.Position = Vector3.new(0, -500, 0)
			frame = CFrame.new(0, -500, 0)
		end
		local flap = math.abs(math.sin(now * 14 + butterfly.Phase)) * 1.2
		table.insert(parts, butterfly.Left)
		table.insert(frames, frame * CFrame.Angles(0, 0, flap) * CFrame.new(-0.26, 0, 0))
		table.insert(parts, butterfly.Right)
		table.insert(frames, frame * CFrame.Angles(0, 0, -flap) * CFrame.new(0.26, 0, 0))
	end
end

-- Luciérnagas ---------------------------------------------------------------------------------

local function makeFireflies(): ParticleEmitter
	local holder = piece("Fireflies", Vector3.new(70, 6, 70), Color3.new(1, 1, 1))
	holder.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(3, 5)
	emitter.Speed = NumberRange.new(0.2, 0.7)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 0.1, 0)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.3), NumberSequenceKeypoint.new(0.7, 0.3), NumberSequenceKeypoint.new(1, 0) })
	emitter.Color = ColorSequence.new(Color3.fromRGB(214, 255, 140))
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Parent = holder
	return emitter
end

-- Arranque ------------------------------------------------------------------------------------

function AmbientController.start()
	folder = Instance.new("Folder")
	folder.Name = "ClientAmbience"
	folder.Parent = Workspace

	startSounds()

	local random = Random.new(os.time())
	local birds = {}
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	startBirds(parts, frames, birds)
	local butterflies = makeButterflies(random)
	local fireflies = makeFireflies()
	local fireflyHolder = fireflies.Parent :: BasePart

	-- Cristales que flotan (se buscan de vez en cuando: el mundo llega por partes).
	local floaty: { { Part: BasePart, Base: CFrame } } = {}
	local known: { [BasePart]: boolean } = {}
	task.spawn(function()
		while true do
			local wilds = Workspace:FindFirstChild("Wilds")
			if wilds then
				for _, item in wilds:GetDescendants() do
					if item:IsA("BasePart") and item:GetAttribute("Floaty") and not known[item] then
						known[item] = true
						table.insert(floaty, { Part = item, Base = item.CFrame })
					end
				end
			end
			for index = #floaty, 1, -1 do
				if not floaty[index].Part.Parent then
					known[floaty[index].Part] = nil
					table.remove(floaty, index)
				end
			end
			task.wait(5)
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		local now = os.clock()
		local zoneId = currentZone()
		local origin = zoneOrigin(zoneId)
		local night = DayNightController.night()
		local outdoors = zoneId ~= "EmberCaldera"
		table.clear(parts)
		table.clear(frames)
		if origin then
			updateBirds(now, origin, outdoors and night < 0.5, parts, frames, birds)
		end
		local rootPos = rootPosition()
		updateButterflies(now, dt, if zoneId == "Forest" then origin else nil, rootPos, night < 0.4, butterflies, random, parts, frames)
		for _, item in floaty do
			table.insert(parts, item.Part)
			table.insert(frames, item.Base * CFrame.new(0, math.sin(now * 1.2) * 0.35, 0) * CFrame.Angles(0, now * 0.8, 0))
		end
		if rootPos then
			table.insert(parts, fireflyHolder)
			table.insert(frames, CFrame.new(rootPos + Vector3.new(0, 1, 0)))
		end
		if #parts > 0 then
			Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end
		fireflies.Rate = if outdoors then 16 * night else 0
	end)
end

return AmbientController
