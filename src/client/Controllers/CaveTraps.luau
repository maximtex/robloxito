-- Trampas de las mazmorras en este cliente (CaveConfig.Caves.*.Traps; las lanza y las cobra
-- CaveService, que avisa con CaveEvent "Trap"):
-- - Aviso: un círculo de su color en el suelo que se va llenando hasta que salta (StrikeAt,
--   hora del servidor). Si estás dentro, ¡a moverse!
-- - Pinchos de cristal (Valle): pinchos que salen del suelo, brillan un momento y se hunden.
-- - Chorro de lava (Caldera): una columna de lava con fuego y chispas que sube y baja.
-- - Carámbanos (Tundra): caen del techo, se clavan y revientan en trozos de hielo y nieve.
-- Solo decorativo: el daño lo pone el servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CaveConfig = require(Shared.Config.CaveConfig)
local WaveFx = require(script.Parent.WaveFx)

local CaveTraps = {}

local player = Players.LocalPlayer
local RGB = Color3.fromRGB
local WARN = RGB(255, 70, 60)
local MAX_ACTIVE = 24

local active = 0
local fxFolder: Folder? = nil

local function folder(): Folder
	if fxFolder and fxFolder.Parent then
		return fxFolder
	end
	local f = Instance.new("Folder")
	f.Name = "CaveTrapsFx"
	f.Parent = Workspace
	fxFolder = f
	return f
end

local function sound(spec, at: Vector3?)
	if not spec then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = spec.Id
	s.Volume = spec.Volume or 0.5
	s.PlaybackSpeed = spec.Pitch or 1
	local holder: Instance = SoundService
	if at then
		local anchor = Instance.new("Attachment")
		anchor.WorldPosition = at
		anchor.Parent = Workspace.Terrain
		holder = anchor
		s.RollOffMaxDistance = 90
		task.delay(6, function()
			anchor:Destroy()
		end)
	end
	s.Parent = holder
	s:Play()
	task.delay(6, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Parent = parent
	return p
end

local function disc(name: string, center: Vector3, diameter: number, color: Color3, parent: Instance): Part
	local p = part(name, Vector3.new(0.12, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, parent)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- ¿Estoy dentro del círculo? (para avisar más fuerte)
local function inside(center: Vector3, radius: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	local dx, dz = root.Position.X - center.X, root.Position.Z - center.Z
	return dx * dx + dz * dz <= radius * radius
end

-- Pinchos de cristal: salen del suelo inclinados hacia fuera, brillan y se hunden.
local function crystalStrike(center: Vector3, radius: number, color: Color3, model: Model)
	local spikes = {}
	local count = 7
	for index = 1, count do
		local angle = index / count * math.pi * 2 + math.random() * 0.4
		local distance = if index == 1 then 0 else radius * (0.35 + math.random() * 0.45)
		local height = 4 + math.random() * 3.5
		local base = center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local tilt = CFrame.Angles(math.rad(math.cos(angle) * 18), 0, math.rad(-math.sin(angle) * 18))
		local spike = part("Pincho", Vector3.new(1.2, height, 1.2), CFrame.new(base - Vector3.new(0, height / 2, 0)) * tilt, if index % 2 == 0 then color else color:Lerp(Color3.new(1, 1, 1), 0.45), model)
		spike.Transparency = 0.1
		table.insert(spikes, { Part = spike, Base = base, Height = height, Tilt = tilt })
	end
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		-- sube en 0.12 s, se queda 0.45 s y se hunde en 0.35 s
		local up = if t < 0.12 then t / 0.12 elseif t < 0.57 then 1 else math.max(0, 1 - (t - 0.57) / 0.35)
		for _, spike in spikes do
			if spike.Part.Parent then
				spike.Part.CFrame = CFrame.new(spike.Base + Vector3.new(0, (up - 0.5) * spike.Height, 0)) * spike.Tilt
			end
		end
		if t > 0.95 then
			connection:Disconnect()
			model:Destroy()
		end
	end)
end

-- Chorro de lava: una columna que sube con fuego y chispas y luego baja.
local function lavaStrike(center: Vector3, radius: number, color: Color3, model: Model)
	local width = radius * 1.3
	local column = part("Chorro", Vector3.new(10, width, width), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, model)
	column.Shape = Enum.PartType.Cylinder
	column.Transparency = 0.15
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 22
	light.Brightness = 3
	light.Shadows = false
	light.Parent = column
	local fire = Instance.new("Fire")
	fire.Color = color
	fire.SecondaryColor = RGB(255, 220, 120)
	fire.Size = radius * 1.4
	fire.Heat = 18
	fire.Parent = column
	local embers = Instance.new("ParticleEmitter")
	embers.Color = ColorSequence.new(RGB(255, 200, 90), color)
	embers.LightEmission = 1
	embers.Size = NumberSequence.new(0.6, 0)
	embers.Lifetime = NumberRange.new(0.6, 1.2)
	embers.Speed = NumberRange.new(14, 26)
	embers.SpreadAngle = Vector2.new(25, 25)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Acceleration = Vector3.new(0, -30, 0)
	embers.Parent = column
	embers:Emit(40)
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		local height = if t < 0.15 then 12 * t / 0.15 elseif t < 0.65 then 12 else math.max(0.1, 12 * (1 - (t - 0.65) / 0.4))
		if column.Parent then
			column.Size = Vector3.new(height, width, width)
			column.CFrame = CFrame.new(center + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		end
		if t > 1.1 then
			connection:Disconnect()
			model:Destroy()
		end
	end)
end

-- Carámbanos: unos cuantos caen del techo a la vez, se clavan y revientan en trozos de hielo.
local function iceStrike(center: Vector3, radius: number, color: Color3, model: Model)
	local icicles = {}
	for index = 1, 5 do
		local angle = index / 5 * math.pi * 2 + math.random() * 0.5
		local distance = if index == 1 then 0 else radius * (0.3 + math.random() * 0.45)
		local length = 3.5 + math.random() * 2.5
		local base = center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local icicle = part("Carambano", Vector3.new(1.1, length, 1.1), CFrame.new(base + Vector3.new(0, 26, 0)), if index % 2 == 0 then color else color:Lerp(Color3.new(1, 1, 1), 0.5), model)
		icicle.Material = Enum.Material.Glass
		icicle.Transparency = 0.2
		table.insert(icicles, { Part = icicle, Base = base, Length = length, Delay = index * 0.03 })
	end
	local start = os.clock()
	local shattered = false
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		for _, icicle in icicles do
			local k = math.clamp((t - icicle.Delay) / 0.22, 0, 1)
			if icicle.Part.Parent then
				local y = 26 * (1 - k * k) + icicle.Length / 2 - 0.6
				icicle.Part.CFrame = CFrame.new(icicle.Base + Vector3.new(0, y, 0)) * CFrame.Angles(0, math.rad(45), 0)
			end
		end
		if t > 0.32 and not shattered then
			shattered = true
			local shards = Instance.new("ParticleEmitter")
			shards.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.4), color)
			shards.LightEmission = 0.5
			shards.Size = NumberSequence.new(0.5, 0)
			shards.Lifetime = NumberRange.new(0.4, 0.8)
			shards.Speed = NumberRange.new(10, 18)
			shards.SpreadAngle = Vector2.new(70, 70)
			shards.EmissionDirection = Enum.NormalId.Top
			shards.Acceleration = Vector3.new(0, -40, 0)
			shards.Rate = 0
			shards.Parent = icicles[1].Part
			shards:Emit(40)
		end
		if t > 0.9 then
			for _, icicle in icicles do
				if icicle.Part.Parent then
					icicle.Part.Transparency = math.min(1, icicle.Part.Transparency + 0.08)
				end
			end
		end
		if t > 1.4 then
			connection:Disconnect()
			model:Destroy()
		end
	end)
end

-- Una trampa: { Kind, Position (suelo), Radius, StrikeAt, Warning, Color }
function CaveTraps.show(data: any)
	if type(data) ~= "table" or typeof(data.Position) ~= "Vector3" or active >= MAX_ACTIVE then
		return
	end
	local radius = math.clamp(tonumber(data.Radius) or 6, 1, 20)
	local warning = math.clamp(tonumber(data.Warning) or 1.2, 0.2, 5)
	local strikeAt = tonumber(data.StrikeAt) or (Workspace:GetServerTimeNow() + warning)
	local color = if typeof(data.Color) == "Color3" then data.Color else RGB(255, 120, 40)
	local center = data.Position + Vector3.new(0, 0.08, 0)
	active += 1
	local model = Instance.new("Model")
	model.Name = "Trampa"
	model.Parent = folder()

	-- Aviso: borde y relleno que crece
	local edge = disc("Aviso", center, radius * 2, WARN, model)
	edge.Transparency = 0.55
	local fill = disc("Relleno", center + Vector3.new(0, 0.02, 0), 0.2, color, model)
	fill.Transparency = 0.35
	if inside(data.Position, radius + 1) then
		sound(CaveConfig.Sounds.TrapWarn)
	end
	local total = math.max(0.1, strikeAt - Workspace:GetServerTimeNow())
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / total, 0, 1)
		if fill.Parent then
			local d = math.max(0.2, radius * 2 * t)
			fill.Size = Vector3.new(0.12, d, d)
			edge.Transparency = 0.35 + 0.3 * math.abs(math.sin(os.clock() * 12))
		end
		if t >= 1 then
			connection:Disconnect()
			edge:Destroy()
			fill:Destroy()
			active -= 1
			local strikeModel = Instance.new("Model")
			strikeModel.Name = "Golpe"
			strikeModel.Parent = folder()
			model:Destroy()
			local hit = inside(data.Position, radius)
			if data.Kind == "Lava" then
				sound(CaveConfig.Sounds.Lava, data.Position)
				lavaStrike(center, radius, color, strikeModel)
			elseif data.Kind == "Ice" then
				sound(CaveConfig.Sounds.Ice or CaveConfig.Sounds.Crystal, data.Position)
				iceStrike(center, radius, color, strikeModel)
			else
				sound(CaveConfig.Sounds.Crystal, data.Position)
				crystalStrike(center, radius, color, strikeModel)
			end
			if hit then
				WaveFx.shake(0.35)
				WaveFx.flash(WARN, 0.25)
			end
		end
	end)
end

return CaveTraps
