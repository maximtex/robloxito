-- AbilityController · AbilityFx: efectos visuales de cada habilidad elemental (tabla EFFECTS).
-- Parte de AbilityController (ver AbilityController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityConfig = require(Shared.Config.AbilityConfig)
local CombatController = require(script.Parent.Parent.CombatController)

local ctx: any -- tabla de estado compartida (la crea AbilityController/init.luau)
local HEAL_COLOR: any
local HIT_BOOST: any

-- Funciones de las otras partes
local function abilityColor(...) return ctx.abilityColor(...) end
local function addShake(...) return ctx.addShake(...) end
local function burst(...) return ctx.burst(...) end
local function flashLight(...) return ctx.flashLight(...) end
local function flatRing(...) return ctx.flatRing(...) end
local function fxPart(...) return ctx.fxPart(...) end
local function groundAt(...) return ctx.groundAt(...) end
local function rootOf(...) return ctx.rootOf(...) end

-- Efectos de cada habilidad ----------------------------------------------------------------

local EFFECTS: { [string]: (any, boolean) -> () } = {}

-- Raíces: anillo verde y enredaderas que brotan alrededor de cada enemigo atrapado.
local function vines(position: Vector3, seconds: number, color: Color3)
	local ground = groundAt(position)
	for index = 1, 5 do
		local angle = (index / 5) * math.pi * 2 + math.random() * 0.5
		local base = Vector3.new(position.X + math.cos(angle) * 1.9, ground, position.Z + math.sin(angle) * 1.9)
		local tilt = CFrame.lookAt(base, Vector3.new(position.X, ground, position.Z)) * CFrame.Angles(math.rad(-25), 0, 0)
		local height = 3 + math.random() * 1.5
		local vine = fxPart(Vector3.new(0.5, 0.1, 0.5), tilt * CFrame.new(0, 0.05, 0), Color3.fromRGB(104, 176, 70), Enum.Material.Grass, 0)
		TweenService:Create(vine, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(0.45, height, 0.45), CFrame = tilt * CFrame.new(0, height / 2, 0) }):Play()
		task.delay(math.max(0.2, seconds), function()
			if vine.Parent then
				TweenService:Create(vine, TweenInfo.new(0.25), { Size = Vector3.new(0.3, 0.1, 0.3), CFrame = tilt * CFrame.new(0, 0.05, 0), Transparency = 1 }):Play()
			end
		end)
		Debris:AddItem(vine, seconds + 0.6)
	end
	burst(position, "Leaf", color, 10)
end

function EFFECTS.Roots(event, isOwner)
	local color = abilityColor("Nature")
	flatRing(event.Center, event.Radius * 2, color, 0.45, Enum.Material.Neon, 0.3)
	burst(event.Center, "Leaf", color, 18)
	local seconds = if typeof(event.Seconds) == "number" then event.Seconds else 1.5
	if typeof(event.Hits) == "table" then
		for _, hit in event.Hits do
			if typeof(hit) == "table" and typeof(hit.Position) == "Vector3" and hit.Killed ~= true then
				vines(hit.Position, if hit.Kind == "Boss" then seconds * AbilityConfig.BossControl else seconds, color)
			end
		end
	end
	CombatController.showHits(event.Hits, color, isOwner, 0.8, HIT_BOOST)
end

local function healNumbers(healed: any, color: Color3)
	if typeof(healed) ~= "table" then
		return
	end
	for _, entry in healed do
		local root = typeof(entry) == "table" and rootOf(entry.Player)
		if root then
			burst(root.Position, "Bubble", HEAL_COLOR, 12)
			flashLight(root.Position, color, 12, 0.5)
			if typeof(entry.Amount) == "number" and entry.Amount > 0 then
				CombatController.floatingNumber(root.Position + Vector3.new(0, 1, 0), entry.Amount, HEAL_COLOR, 1.2)
			end
		end
	end
end

function EFFECTS.Heal(event, isOwner)
	local color = abilityColor("Water")
	flatRing(event.Center, event.Radius * 2, color, 0.55, Enum.Material.Glass, 0.25)
	flatRing(event.Center, event.Radius * 1.3, Color3.fromRGB(200, 240, 255), 0.4, Enum.Material.Neon, 0.5)
	burst(event.Center, "Bubble", color, 24)
	healNumbers(event.Healed, color)
	CombatController.showHits(event.Hits, color, isOwner, 0.9, HIT_BOOST)
end

function EFFECTS.Burn(event, isOwner)
	local color = abilityColor("Fire")
	local look = if typeof(event.Look) == "Vector3" then event.Look else Vector3.new(0, 0, -1)
	local origin = event.Origin + Vector3.new(0, 0.5, 0) + look * 1.5
	burst(origin, "Flame", color, 70, look)
	burst(origin, "Flame", Color3.fromRGB(255, 220, 120), 30, look)
	flashLight(origin + look * 4, color, 18, 0.45)
	CombatController.showHits(event.Hits, color, isOwner, 0.8, HIT_BOOST)
end

function EFFECTS.BurnTick(event, isOwner)
	if isOwner then
		CombatController.showHits(event.Hits, Color3.fromRGB(255, 170, 90), true, 0.25)
	end
end

-- Velocidad del Vendaval: estela de viento en el personaje mientras dura.
local function hasteTrail(target: Player, seconds: number, color: Color3)
	local root = rootOf(target)
	if not root then
		return
	end
	local existing = root:FindFirstChild("AbilityHaste")
	if existing then
		existing:Destroy()
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "AbilityHaste"
	local streaks = Instance.new("ParticleEmitter")
	streaks.Rate = 22
	streaks.Lifetime = NumberRange.new(0.3, 0.5)
	streaks.Speed = NumberRange.new(1, 3)
	streaks.SpreadAngle = Vector2.new(180, 180)
	streaks.Size = NumberSequence.new(0.22, 0)
	streaks.Transparency = NumberSequence.new(0.2, 1)
	streaks.LightEmission = 0.8
	streaks.Color = ColorSequence.new(color)
	streaks.Parent = attachment
	attachment.Parent = root
	Debris:AddItem(attachment, seconds)
end

local function windRings(origin: Vector3, look: Vector3, color: Color3)
	for index = 1, 3 do
		local distance = 2 + index * 3
		local position = origin + look * distance
		local frame = CFrame.lookAt(position, position + look) * CFrame.Angles(0, math.rad(90), 0)
		local ring = fxPart(Vector3.new(0.12, 2, 2), frame, color, Enum.Material.Neon, 1, Enum.PartType.Cylinder)
		local delay = (index - 1) * 0.06
		TweenService:Create(ring, TweenInfo.new(0.05, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, delay), { Transparency = 0.45 }):Play()
		TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay + 0.05), { Size = Vector3.new(0.04, 3 + index * 2.5, 3 + index * 2.5), Transparency = 1, CFrame = frame + look * 2 }):Play()
		Debris:AddItem(ring, delay + 0.5)
	end
end

function EFFECTS.Gust(event, isOwner)
	local color = abilityColor("Wind")
	local look = if typeof(event.Look) == "Vector3" then event.Look else Vector3.new(0, 0, -1)
	local origin = event.Origin + Vector3.new(0, 0.3, 0)
	burst(origin + look * 1.5, "Wind", color, 50, look)
	windRings(origin, look, color)
	if typeof(event.HasteSeconds) == "number" and typeof(event.Owner) == "Instance" then
		hasteTrail(event.Owner, event.HasteSeconds, color)
	end
	CombatController.showHits(event.Hits, color, isOwner, 1, HIT_BOOST)
end

-- Rayo en zigzag entre dos puntos.
local function bolt(from: Vector3, to: Vector3, color: Color3, delay: number)
	task.delay(delay, function()
		local segments = 6
		local direction = to - from
		if direction.Magnitude < 0.1 then
			return
		end
		local side = direction:Cross(Vector3.new(0, 1, 0))
		side = if side.Magnitude > 0.01 then side.Unit else Vector3.new(1, 0, 0)
		local up = Vector3.new(0, 1, 0)
		local previous = from
		for index = 1, segments do
			local t = index / segments
			local point = from + direction * t
			if index < segments then
				point += side * (math.random() * 1.6 - 0.8) + up * (math.random() * 1.2 - 0.6)
			end
			local length = (point - previous).Magnitude
			local piece = fxPart(Vector3.new(0.2, 0.2, length), CFrame.lookAt((previous + point) / 2, point), Color3.new(1, 1, 1):Lerp(color, 0.4), Enum.Material.Neon, 0)
			TweenService:Create(piece, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = Vector3.new(0.05, 0.05, length) }):Play()
			Debris:AddItem(piece, 0.35)
			previous = point
		end
		burst(to, "Spark", color, 10)
		flashLight(to, color, 10, 0.25)
	end)
end

function EFFECTS.Chain(event, isOwner)
	local color = abilityColor("Lightning")
	if typeof(event.Points) == "table" then
		for index = 1, #event.Points - 1 do
			local from, to = event.Points[index], event.Points[index + 1]
			if typeof(from) == "Vector3" and typeof(to) == "Vector3" then
				bolt(from, to, color, (index - 1) * 0.05)
			end
		end
	end
	task.delay(0.05, function()
		CombatController.showHits(event.Hits, color, isOwner, 0.9, HIT_BOOST)
	end)
end

local function iceShards(center: Vector3, radius: number, count: number, scale: number)
	local ground = groundAt(center)
	for index = 1, count do
		local angle = (index / count) * math.pi * 2
		local distance = radius * (0.55 + math.random() * 0.4)
		local base = Vector3.new(center.X + math.cos(angle) * distance, ground, center.Z + math.sin(angle) * distance)
		local height = (1.6 + math.random() * 1.4) * scale
		local frame = CFrame.new(base) * CFrame.Angles(math.rad(math.random(-20, 20)), angle, math.rad(math.random(-20, 20)))
		local shard = fxPart(Vector3.new(0.6 * scale, 0.1, 0.6 * scale), frame, Color3.fromRGB(190, 236, 255), Enum.Material.Ice, 0.15)
		TweenService:Create(shard, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(0.6 * scale, height, 0.6 * scale), CFrame = frame * CFrame.new(0, height / 2, 0) }):Play()
		TweenService:Create(shard, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6), { Transparency = 1 }):Play()
		Debris:AddItem(shard, 1.1)
	end
end

function EFFECTS.Frost(event, isOwner)
	local color = abilityColor("Ice")
	flatRing(event.Center, event.Radius * 2, color, 0.5, Enum.Material.Ice, 0.2)
	flatRing(event.Center, event.Radius * 1.4, Color3.new(1, 1, 1), 0.35, Enum.Material.Neon, 0.55)
	burst(event.Center, "Snow", color, 34)
	iceShards(event.Center, event.Radius, 10, 1)
	CombatController.showHits(event.Hits, color, isOwner, 0.8, HIT_BOOST)
end

local function projectile(from: Vector3, to: Vector3, color: Color3, tail: Color3, onArrive: () -> ())
	local orb = fxPart(Vector3.one * 0.9, CFrame.new(from), color, Enum.Material.Neon, 0.1, Enum.PartType.Ball)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.3, 0)
	a0.Parent = orb
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.3, 0)
	a1.Parent = orb
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.2
	trail.LightEmission = 0.6
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(color, tail)
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Parent = orb
	local travel = math.clamp((to - from).Magnitude / 60, 0.12, 0.3)
	local tween = TweenService:Create(orb, TweenInfo.new(travel, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { CFrame = CFrame.new(to) })
	tween.Completed:Once(function()
		orb:Destroy()
		onArrive()
	end)
	tween:Play()
	Debris:AddItem(orb, travel + 0.3)
end

function EFFECTS.Curse(event, isOwner)
	local color = abilityColor("Shadow")
	if typeof(event.Origin) ~= "Vector3" or typeof(event.Target) ~= "Vector3" then
		return
	end
	projectile(event.Origin + Vector3.new(0, 1, 0), event.Target, color, Color3.fromRGB(40, 20, 70), function()
		flatRing(event.Target, 6, color, 0.4, Enum.Material.Neon, 0.35)
		burst(event.Target, "Smoke", color, 16)
		if typeof(event.Marked) == "table" then
			for _, position in event.Marked do
				if typeof(position) == "Vector3" then
					burst(position, "Smoke", Color3.fromRGB(110, 60, 180), 8)
				end
			end
		end
		CombatController.showHits(event.Hits, color, isOwner, 0.8, HIT_BOOST)
	end)
end

function EFFECTS.StarfallCast(event, _isOwner)
	local color = abilityColor("Celestial")
	if typeof(event.Center) ~= "Vector3" or typeof(event.Radius) ~= "number" then
		return
	end
	local telegraph = if typeof(event.Telegraph) == "number" then event.Telegraph else 0.7
	local waves = if typeof(event.Waves) == "number" then event.Waves else 3
	local interval = if typeof(event.WaveInterval) == "number" then event.WaveInterval else 0.45
	local total = telegraph + (waves - 1) * interval + 0.3
	local y = groundAt(event.Center) + 0.22
	local diameter = event.Radius * 2
	local frame = CFrame.new(event.Center.X, y, event.Center.Z) * CFrame.Angles(0, 0, math.rad(90))
	local ring = fxPart(Vector3.new(0.1, diameter, diameter), frame, color, Enum.Material.Neon, 0.65, Enum.PartType.Cylinder)
	local fill = fxPart(Vector3.new(0.12, 0.5, 0.5), frame + Vector3.new(0, 0.03, 0), color, Enum.Material.Neon, 0.6, Enum.PartType.Cylinder)
	TweenService:Create(fill, TweenInfo.new(telegraph, Enum.EasingStyle.Linear), { Size = Vector3.new(0.12, diameter, diameter) }):Play()
	TweenService:Create(ring, TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, total - 0.3), { Transparency = 1 }):Play()
	TweenService:Create(fill, TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, total - 0.3), { Transparency = 1 }):Play()
	Debris:AddItem(ring, total + 0.1)
	Debris:AddItem(fill, total + 0.1)
	burst(event.Center + Vector3.new(0, 1, 0), "Star", color, 12)
end

function EFFECTS.StarfallWave(event, isOwner)
	local color = abilityColor("Celestial")
	if typeof(event.Center) ~= "Vector3" or typeof(event.Radius) ~= "number" then
		return
	end
	local ground = groundAt(event.Center)
	for index = 1, 6 do
		local angle = math.random() * math.pi * 2
		local distance = math.sqrt(math.random()) * event.Radius * 0.9
		local target = Vector3.new(event.Center.X + math.cos(angle) * distance, ground + 0.5, event.Center.Z + math.sin(angle) * distance)
		local start = target + Vector3.new(math.random(-6, 6), 34, math.random(-6, 6))
		local star = fxPart(Vector3.one * 1.1, CFrame.new(start), Color3.fromRGB(255, 246, 210), Enum.Material.Neon, 0, Enum.PartType.Ball)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.4, 0)
		a0.Parent = star
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.4, 0)
		a1.Parent = star
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.25
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		trail.Transparency = NumberSequence.new(0, 1)
		trail.Parent = star
		local fall = 0.22 + index * 0.02
		local tween = TweenService:Create(star, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(target) })
		tween.Completed:Once(function()
			star:Destroy()
			burst(target, "Star", color, 8)
		end)
		tween:Play()
		Debris:AddItem(star, fall + 0.3)
	end
	task.delay(0.24, function()
		flashLight(event.Center + Vector3.new(0, 2, 0), color, 22, 0.35)
		CombatController.showHits(event.Hits, color, isOwner, 0.8, HIT_BOOST)
		if isOwner then
			addShake(0.22)
		end
	end)
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.EFFECTS = EFFECTS
	context.bolt = bolt
	context.healNumbers = healNumbers
	context.iceShards = iceShards
	context.vines = vines
end

function Part.link(context: any)
	HEAL_COLOR = context.HEAL_COLOR
	HIT_BOOST = context.HIT_BOOST
end

return Part
