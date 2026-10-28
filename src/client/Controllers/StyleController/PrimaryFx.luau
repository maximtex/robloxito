-- StyleController · PrimaryFx: efectos de las habilidades iniciales y de Arquero (Ráfaga, Terremoto, Meteoros, Granada, Embestida, Nova, Flecha y Balista).
-- Parte de StyleController (ver StyleController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local StyleConfig = require(Shared.Config.StyleConfig)
local CombatController = require(script.Parent.Parent.CombatController)
local CharacterPose = require(script.Parent.Parent.CharacterPose)
local WaveFx = require(script.Parent.Parent.WaveFx)

local ctx: any -- tabla de estado compartida (la crea StyleController/init.luau)
local ICE: any
local player: any

-- Funciones de las otras partes
local function playSound(...) return ctx.playSound(...) end
local function serverNow(...) return ctx.serverNow(...) end

-- Efectos de las habilidades --------------------------------------------------------------

local function groundBelow(position: Vector3): Vector3
	local params = RaycastParams.new()
	local ignore = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	local enemies = Workspace:FindFirstChild("Enemies")
	if enemies then
		table.insert(ignore, enemies)
	end
	if ctx.fxFolder then
		table.insert(ignore, ctx.fxFolder)
	end
	params.FilterDescendantsInstances = ignore
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), params)
	return if hit then hit.Position else position - Vector3.new(0, 2.5, 0)
end

-- Color propio de la habilidad que se está dibujando (las del Mundo 2 traen el suyo: el
-- servidor lo manda en el aviso, Color); nil = el de siempre de su estilo

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

-- Ráfaga: chispas doradas alrededor del personaje mientras dura
local function burstFx(owner: Player, duration: number)
	local character = owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local color = ctx.tint or StyleConfig.Styles.Weapons.Color
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "StyleBurst"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), color)
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.4, 0.7)
	emitter.Rate = 40
	emitter.Speed = NumberRange.new(4, 8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.35, 0)
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Parent = root
	Debris:AddItem(emitter, duration)
	CharacterPose.aim(character)
	WaveFx.ring(groundBelow(root.Position), color, 2, 14, 0.5, 0.15)
	playSound("Burst", if owner == player then nil else root.Position)
end

-- Terremoto: dos ondas naranjas, polvo y sacudida
local function quakeFx(owner: Player, position: Vector3, radius: number, hits: any)
	local ownerStyle = owner:GetAttribute(Constants.Attributes.CombatStyle)
	local color = ctx.tint or (if ownerStyle == "Warrior" then StyleConfig.Styles.Warrior.Color else StyleConfig.Styles.Fists.Color)
	local ground = groundBelow(position)
	CharacterPose.slam(owner.Character)
	WaveFx.ring(ground, color, 2, radius * 2, 0.55, 0.1)
	task.delay(0.12, WaveFx.ring, ground, Color3.fromRGB(255, 230, 190), 1, radius * 1.5, 0.5, 0.35)
	WaveFx.sparkle(ground + Vector3.new(0, 1, 0), Color3.fromRGB(200, 160, 110), 24)
	CombatController.showHits(hits, color, owner == player, 1.2)
	if owner == player then
		WaveFx.shake(0.5)
		WaveFx.kick(4)
	end
	playSound("Quake", if owner == player then nil else position)
	playSound("QuakeRumble", if owner == player then nil else position)
end

-- Meteoros: un aviso en el suelo por punto y la bola cayendo justo al llegar su golpe
local function meteorFx(owner: Player, points: any, delay: number, interval: number, radius: number, startAt: number)
	if typeof(points) ~= "table" then
		return
	end
	local color = ctx.tint or StyleConfig.Styles.Magic.Color
	local elapsed = math.max(0, serverNow() - startAt)
	CharacterPose.cast(owner.Character, 0.3)
	for index, point in points do
		if typeof(point) ~= "Vector3" then
			continue
		end
		local impactIn = math.max(0.05, delay + (index - 1) * interval - elapsed)
		local ground = groundBelow(point)
		-- Aviso: disco morado que se hace visible hasta que cae
		local warning = fxPart(Vector3.new(0.1, radius * 2, radius * 2), CFrame.new(ground + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)), color)
		warning.Shape = Enum.PartType.Cylinder
		warning.Transparency = 0.9
		TweenService:Create(warning, TweenInfo.new(impactIn), { Transparency = 0.6 }):Play()
		Debris:AddItem(warning, impactIn + 0.1)
		-- Bola que cae en diagonal y llega al suelo en el momento del golpe
		local fall = math.min(0.55, impactIn)
		task.delay(impactIn - fall, function()
			local from = ground + Vector3.new(10, 46, -6)
			local meteor = fxPart(Vector3.one * 2.4, CFrame.new(from), color)
			meteor.Shape = Enum.PartType.Ball
			local tail = Instance.new("Attachment")
			tail.Position = Vector3.new(0, 0.9, 0)
			tail.Parent = meteor
			local head = Instance.new("Attachment")
			head.Position = Vector3.new(0, -0.9, 0)
			head.Parent = meteor
			local trail = Instance.new("Trail")
			trail.Attachment0 = tail
			trail.Attachment1 = head
			trail.Lifetime = 0.25
			trail.LightEmission = 1
			trail.FaceCamera = true
			trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
			trail.Transparency = NumberSequence.new(0, 1)
			trail.Parent = meteor
			local glow = Instance.new("PointLight")
			glow.Color = color
			glow.Range = 14
			glow.Brightness = 2
			glow.Parent = meteor
			TweenService:Create(meteor, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(ground + Vector3.new(0, 1, 0)) }):Play()
			Debris:AddItem(meteor, fall + 0.05)
			if index == 1 or index % 2 == 0 then
				playSound("MeteorFall", if owner == player then nil else ground)
			end
		end)
	end
end

local function meteorHitFx(owner: Player, position: Vector3, radius: number, hits: any)
	local color = ctx.tint or StyleConfig.Styles.Magic.Color
	local ground = groundBelow(position)
	WaveFx.ring(ground, color, 2, radius * 2, 0.45, 0.1)
	CombatController.emitAt("Glint", ground + Vector3.new(0, 1.5, 0), color, 10)
	WaveFx.sparkle(ground + Vector3.new(0, 1, 0), color, 14)
	CombatController.showHits(hits, color, owner == player, 1)
	if owner == player then
		WaveFx.shake(0.18)
	end
	playSound("MeteorHit", if owner == player then nil else position)
end

-- Granada: el personaje la lanza por encima del hombro y vuela en arco hasta el objetivo
local function grenadeFx(owner: Player, from: Vector3, to: Vector3, delay: number, radius: number)
	CharacterPose.throw(owner.Character)
	playSound("Throw", if owner == player then nil else from)
	local ground = groundBelow(to)
	-- Aviso: círculo en el suelo hasta que explota
	local warning = fxPart(Vector3.new(0.1, radius * 2, radius * 2), CFrame.new(ground + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 120, 60))
	warning.Shape = Enum.PartType.Cylinder
	warning.Transparency = 0.85
	TweenService:Create(warning, TweenInfo.new(delay), { Transparency = 0.55 }):Play()
	Debris:AddItem(warning, delay + 0.05)
	local start = CharacterPose.handPosition(owner.Character) or from
	-- Bomba de brea del Arquero: vasija de barro con la mecha encendida
	local bomb = fxPart(Vector3.one * 1.1, CFrame.new(start), Color3.fromRGB(150, 92, 56))
	bomb.Shape = Enum.PartType.Ball
	bomb.Material = Enum.Material.Slate
	local fuse = fxPart(Vector3.one * 0.4, CFrame.new(start), Color3.fromRGB(255, 200, 80))
	fuse.Shape = Enum.PartType.Ball
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 120, 40))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.25, 0)
	sparks.Lifetime = NumberRange.new(0.15, 0.3)
	sparks.Speed = NumberRange.new(2, 5)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 60
	sparks.Parent = fuse
	local began = os.clock()
	local height = math.clamp((to - start).Magnitude * 0.35, 4, 14)
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - began) / delay, 0, 1)
		local position = start:Lerp(ground + Vector3.new(0, 0.6, 0), t) + Vector3.new(0, math.sin(t * math.pi) * height, 0)
		bomb.CFrame = CFrame.new(position) * CFrame.Angles(t * 12, t * 7, 0)
		fuse.CFrame = bomb.CFrame * CFrame.new(0, 0.6, 0)
		if t >= 1 then
			connection:Disconnect()
			bomb:Destroy()
			fuse:Destroy()
		end
	end)
	Debris:AddItem(bomb, delay + 0.5)
	Debris:AddItem(fuse, delay + 0.5)
end

local function grenadeHitFx(owner: Player, position: Vector3, radius: number, hits: any)
	local ground = groundBelow(position)
	local fire = ctx.tint or Color3.fromRGB(255, 150, 60)
	-- Bola de fuego que crece y se apaga, onda en el suelo y humo
	local ball = fxPart(Vector3.one * 2, CFrame.new(ground + Vector3.new(0, 1.5, 0)), fire)
	ball.Shape = Enum.PartType.Ball
	ball.Transparency = 0.1
	TweenService:Create(ball, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * radius * 1.6, Transparency = 1, Color = Color3.fromRGB(255, 230, 150) }):Play()
	Debris:AddItem(ball, 0.4)
	WaveFx.ring(ground, fire, 2, radius * 2, 0.45, 0.1)
	WaveFx.sparkle(ground + Vector3.new(0, 1, 0), Color3.fromRGB(120, 110, 100), 20)
	CombatController.emitAt("Spark", ground + Vector3.new(0, 1, 0), fire, 18)
	CombatController.showHits(hits, StyleConfig.Styles.Weapons.Color, owner == player, 1.1)
	if owner == player then
		WaveFx.shake(0.35)
	end
	playSound("Grenade", if owner == player then nil else position)
end

-- Embestida: puños por delante, estela del recorrido e imágenes que se desvanecen
local function dashFx(owner: Player, from: Vector3, to: Vector3, hits: any)
	local color = ctx.tint or StyleConfig.Styles.Fists.Color
	CharacterPose.charge(owner.Character)
	local offset = to - from
	local distance = offset.Magnitude
	if distance > 0.5 then
		local trail = fxPart(Vector3.new(4.5, 0.2, distance), CFrame.lookAt(from:Lerp(to, 0.5), to) * CFrame.new(0, -1.5, 0), color)
		trail.Transparency = 0.4
		TweenService:Create(trail, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1, Size = Vector3.new(0.4, 0.1, distance) }):Play()
		Debris:AddItem(trail, 0.45)
		-- Huellas de viento: siluetas que se apagan a lo largo del camino
		local steps = math.clamp(math.floor(distance / 5), 1, 6)
		for index = 1, steps do
			local point = from:Lerp(to, index / (steps + 1))
			local ghost = fxPart(Vector3.new(2.2, 4.5, 1), CFrame.lookAt(point, point + offset.Unit), color)
			ghost.Transparency = 0.55 + index * 0.05
			TweenService:Create(ghost, TweenInfo.new(0.35 + index * 0.03), { Transparency = 1, Size = Vector3.new(0.4, 4, 0.4) }):Play()
			Debris:AddItem(ghost, 0.5)
		end
	end
	WaveFx.ring(groundBelow(to), color, 2, 10, 0.35, 0.2)
	CombatController.showHits(hits, color, owner == player, 1.1)
	if owner == player then
		WaveFx.kick(3)
		if typeof(hits) == "table" and #hits > 0 then
			WaveFx.shake(0.25)
		end
	end
	playSound("Dash", if owner == player then nil else from)
	if typeof(hits) == "table" and #hits > 0 then
		playSound("DashHit", if owner == player then nil else to)
	end
end

-- Nova de hielo: brazos abiertos, anillo helado, carámbanos y los congelados en hielo
local function novaFx(owner: Player, position: Vector3, radius: number, hits: any, frozen: any)
	local ice = ctx.tint or ICE
	local ground = groundBelow(position)
	CharacterPose.spread(owner.Character)
	WaveFx.ring(ground, ice, 2, radius * 2, 0.5, 0.05)
	task.delay(0.1, WaveFx.ring, ground, Color3.new(1, 1, 1), 2, radius * 1.6, 0.45, 0.4)
	-- Carámbanos que salen del suelo en círculo y se derriten
	for index = 1, 12 do
		local angle = index / 12 * math.pi * 2
		local distance = radius * (0.45 + (index % 3) * 0.18)
		local base = ground + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local spike = fxPart(Vector3.new(1, 0.2, 1), CFrame.new(base) * CFrame.Angles(math.rad((index % 2) * 12), angle, 0), ice)
		spike.Material = Enum.Material.Glass
		spike.Transparency = 0.2
		local tall = 2.5 + (index % 4)
		TweenService:Create(spike, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(1, tall, 1), CFrame = CFrame.new(base + Vector3.new(0, tall / 2, 0)) * CFrame.Angles(math.rad((index % 2) * 12), angle, 0) }):Play()
		task.delay(0.8, function()
			if spike.Parent then
				TweenService:Create(spike, TweenInfo.new(0.5), { Transparency = 1, Size = Vector3.new(0.3, 0.3, 0.3) }):Play()
			end
		end)
		Debris:AddItem(spike, 1.4)
	end
	-- Los congelados: un bloque de hielo alrededor mientras dura
	if typeof(frozen) == "table" then
		for _, entry in frozen do
			local model = typeof(entry) == "table" and entry.Model
			local seconds = typeof(entry) == "table" and tonumber(entry.Seconds) or 0
			if typeof(model) == "Instance" and model:IsA("Model") and seconds > 0 then
				local ok, cframe, size = pcall(function()
					return model:GetBoundingBox()
				end)
				if ok then
					local block = fxPart(size + Vector3.new(0.6, 0.6, 0.6), cframe, ice)
					block.Material = Enum.Material.Glass
					block.Transparency = 0.45
					TweenService:Create(block, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, math.max(0, seconds - 0.5)), { Transparency = 1 }):Play()
					Debris:AddItem(block, seconds + 0.1)
				end
			end
		end
	end
	WaveFx.sparkle(ground + Vector3.new(0, 1.5, 0), ice, 22)
	CombatController.showHits(hits, ice, owner == player, 1.1)
	if owner == player then
		WaveFx.flash(ice, 0.25)
	end
	playSound("Nova", if owner == player then nil else position)
	playSound("NovaBlast", if owner == player then nil else position)
end

-- Flecha perforante: una flecha enorme que cruza recta y deja una estela de su color
local function pierceFx(owner: Player, from: Vector3, to: Vector3, width: number, hits: any)
	local color = ctx.tint or StyleConfig.Styles.Weapons.Color
	CharacterPose.aim(owner.Character)
	local distance = (to - from).Magnitude
	if distance > 0.5 then
		local center = CFrame.lookAt(from:Lerp(to, 0.5), to) * CFrame.Angles(0, math.rad(90), 0)
		local streak = fxPart(Vector3.new(distance, width * 0.14, width * 0.14), center, color)
		streak.Shape = Enum.PartType.Cylinder
		streak.Transparency = 0.35
		TweenService:Create(streak, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1, Size = Vector3.new(distance, 0.05, 0.05) }):Play()
		Debris:AddItem(streak, 0.4)
		CombatController.arrow(from, to, color, math.clamp(width * 0.45, 1.5, 3.5))
	end
	CombatController.showHits(hits, color, owner == player, 1.1)
	if owner == player then
		WaveFx.kick(3)
	end
	playSound("Pierce", if owner == player then nil else from)
end

-- Balista (antes torreta): base y poste de madera y una ballesta grande que gira hacia cada
-- objetivo y le dispara flechas
local turrets: { [Player]: { Model: Model, Head: BasePart, Prod: BasePart, Gun: Vector3 } } = {}
local function removeTurret(owner: Player)
	local turret = turrets[owner]
	turrets[owner] = nil
	if turret and turret.Model.Parent then
		for _, part in turret.Model:GetChildren() do
			if part:IsA("BasePart") then
				TweenService:Create(part, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			end
		end
		Debris:AddItem(turret.Model, 0.35)
	end
end
local function turretFx(owner: Player, position: Vector3, duration: number)
	removeTurret(owner)
	local color = ctx.tint or StyleConfig.Styles.Weapons.Color
	local model = Instance.new("Model")
	model.Name = "StyleTurret"
	model.Parent = ctx.fxFolder
	local function piece(size: Vector3, cframe: CFrame, tone: Color3, material: Enum.Material): Part
		local part = fxPart(size, cframe, tone)
		part.Material = material
		part.Parent = model
		return part
	end
	local wood = Color3.fromRGB(120, 82, 48)
	local base = piece(Vector3.new(0.6, 2.6, 2.6), CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), wood:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Wood)
	base.Shape = Enum.PartType.Cylinder
	piece(Vector3.new(0.6, 1.8, 0.6), CFrame.new(position + Vector3.new(0, 1.4, 0)), wood, Enum.Material.Wood)
	local gun = position + Vector3.new(0, 2.6, 0)
	local head = piece(Vector3.new(0.6, 0.5, 2.6), CFrame.new(gun), wood, Enum.Material.Wood)
	local prod = piece(Vector3.new(3, 0.25, 0.3), head.CFrame * CFrame.new(0, 0, -1.1), color, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = prod
	turrets[owner] = { Model = model, Head = head, Prod = prod, Gun = gun }
	WaveFx.ring(position, color, 1, 8, 0.4, 0.2)
	playSound("Turret", if owner == player then nil else position)
	task.delay(duration + 0.6, function()
		if turrets[owner] and turrets[owner].Model == model then
			removeTurret(owner)
		end
	end)
end
local function turretShotFx(owner: Player, from: Vector3, to: Vector3, hits: any)
	local color = ctx.tint or StyleConfig.Styles.Weapons.Color
	local turret = turrets[owner]
	if turret and turret.Head.Parent then
		turret.Head.CFrame = CFrame.lookAt(turret.Gun, Vector3.new(to.X, turret.Gun.Y, to.Z))
		turret.Prod.CFrame = turret.Head.CFrame * CFrame.new(0, 0, -1.1)
	end
	CombatController.arrow(from, to, color, 1.3)
	CombatController.emitAt("Glint", to, color, 4)
	CombatController.showHits(hits, color, owner == player, 0.7)
	if owner == player then
		playSound("TurretShot")
	end
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.burstFx = burstFx
	context.dashFx = dashFx
	context.fxPart = fxPart
	context.grenadeFx = grenadeFx
	context.grenadeHitFx = grenadeHitFx
	context.groundBelow = groundBelow
	context.meteorFx = meteorFx
	context.meteorHitFx = meteorHitFx
	context.novaFx = novaFx
	context.pierceFx = pierceFx
	context.quakeFx = quakeFx
	context.removeTurret = removeTurret
	context.turretFx = turretFx
	context.turretShotFx = turretShotFx
end

function Part.link(context: any)
	ICE = context.ICE
	player = context.player
end

return Part
