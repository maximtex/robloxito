-- EnemyService · BossAttacks: ataques de los jefes (golpe, Slam, Roots, Charge, Leap, Volley) y su máquina de estados.
-- Parte de EnemyService (ver EnemyService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnemyConfig = require(Shared.Config.EnemyConfig)
local StudFloor = require(Shared.Util.StudFloor)
local PartFactory = require(script.Parent.Parent.Parent.Util.PartFactory)
local EnemyLogic = require(script.Parent.Parent.Parent.Util.EnemyLogic)
local Types = require(script.Parent.Types)
type Brain = Types.Brain
type Enemy = Types.Enemy

local ctx: any -- tabla de estado compartida (la crea EnemyService/init.luau)
local GROUND: any
local TELEGRAPH_RED: any
local WINDUP_EYES: any

-- Funciones de las otras partes
local function attack(...) return ctx.attack(...) end
local function bossAcquire(...) return ctx.bossAcquire(...) end
local function bossCanTarget(...) return ctx.bossCanTarget(...) end
local function bossMoveTo(...) return ctx.bossMoveTo(...) end
local function burst(...) return ctx.burst(...) end
local function busyThenRecover(...) return ctx.busyThenRecover(...) end
local function characterOf(...) return ctx.characterOf(...) end
local function clampToTerritory(...) return ctx.clampToTerritory(...) end
local function clearControl(...) return ctx.clearControl(...) end
local function damageInRadius(...) return ctx.damageInRadius(...) end
local function damagePlayer(...) return ctx.damagePlayer(...) end
local function faceTowards(...) return ctx.faceTowards(...) end
local function flat(...) return ctx.flat(...) end
local function intervalOf(...) return ctx.intervalOf(...) end
local function place(...) return ctx.place(...) end
local function placeFx(...) return ctx.placeFx(...) end
local function refreshSpeed(...) return ctx.refreshSpeed(...) end
local function restingEyes(...) return ctx.restingEyes(...) end
local function sameWorld(...) return ctx.sameWorld(...) end
local function setBossState(...) return ctx.setBossState(...) end
local function setEnraged(...) return ctx.setEnraged(...) end
local function setEyes(...) return ctx.setEyes(...) end
local function slam(...) return ctx.slam(...) end
local function slowPlayer(...) return ctx.slowPlayer(...) end
local function syncHealth(...) return ctx.syncHealth(...) end
local function telegraphDisc(...) return ctx.telegraphDisc(...) end
local function telegraphStrip(...) return ctx.telegraphStrip(...) end

-- Golpe cuerpo a cuerpo con aviso: un disco rojo delante y los ojos encendidos
local function bossStrike(enemy: Enemy, target: Player, targetRoot: BasePart)
	local reach = enemy.Def.AttackRange + enemy.Radius
	local forward = faceTowards(enemy, targetRoot.Position)
	telegraphDisc(enemy.Root.Position + forward * reach * 0.5, reach * 0.55, TELEGRAPH_RED, enemy.Def.AttackWindup, enemy.Run)
	attack(enemy, target) -- ojos, animación y daño validado al terminar la preparación
	busyThenRecover(enemy, enemy.Def.AttackWindup + 0.15)
end

local function bossSlam(enemy: Enemy)
	slam(enemy) -- círculo que se llena, onda y daño
	busyThenRecover(enemy, enemy.Def.Slam.Telegraph + 0.1)
end

local function bossRoots(enemy: Enemy, targetPosition: Vector3)
	local settings = enemy.Def.Roots
	local generation = enemy.Generation
	local center = Vector3.new(targetPosition.X, GROUND, targetPosition.Z)
	faceTowards(enemy, targetPosition)
	telegraphDisc(center, settings.Radius, enemy.Def.Look.Secondary, settings.Telegraph, enemy.Run)
	setEyes(enemy, WINDUP_EYES)
	task.delay(settings.Telegraph, function()
		if enemy.Generation ~= generation or enemy.Status.State == "Dead" then
			return
		end
		setEyes(enemy, restingEyes(enemy))
		burst(center + Vector3.new(0, 1, 0), enemy.Def.Look.Secondary, 25, false, enemy.Run)
		for index = 1, 6 do
			local angle = index / 6 * math.pi * 2
			local spike = PartFactory.part(nil :: any, "RootSpike", {
				Size = Vector3.new(0.8, 4, 0.8),
				CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * settings.Radius * 0.6, 1.5, math.sin(angle) * settings.Radius * 0.6)) * CFrame.Angles(math.rad(15), angle, 0),
				Color = enemy.Def.Look.Primary,
				Material = Enum.Material.Wood,
				Solid = false,
			})
			placeFx(spike, enemy.Run)
			Debris:AddItem(spike, 1.2)
		end
		damageInRadius(enemy, center, settings.Radius, settings.Damage, function(_player, humanoid)
			slowPlayer(humanoid, settings.SlowFactor, settings.SlowSeconds)
		end)
	end)
	busyThenRecover(enemy, 0.5) -- lanza las raíces y sigue
end

local function bossCharge(enemy: Enemy, targetPosition: Vector3)
	local settings = enemy.Def.Charge
	local brain = enemy.Brain :: Brain
	local generation = enemy.Generation
	local origin = enemy.Root.Position
	local direction = faceTowards(enemy, targetPosition)
	local finish = clampToTerritory(enemy, origin + direction * settings.Distance)
	telegraphStrip(origin, finish, settings.Width, TELEGRAPH_RED, settings.Telegraph, enemy.Run)
	setEyes(enemy, WINDUP_EYES)
	local dashSeconds = flat(finish - origin) / settings.Speed + 0.2
	busyThenRecover(enemy, settings.Telegraph + dashSeconds)
	task.delay(settings.Telegraph, function()
		if enemy.Generation ~= generation or enemy.Status.State == "Dead" or EnemyLogic.isStunned(enemy.Control, os.clock()) then
			return
		end
		setEyes(enemy, restingEyes(enemy))
		brain.Dash = { Hit = {}, Until = os.clock() + dashSeconds, Damage = settings.Damage, Width = settings.Width }
		enemy.Humanoid.WalkSpeed = settings.Speed
		enemy.Humanoid:MoveTo(finish)
	end)
end

-- Durante la embestida: cada jugador que toque la franja recibe el golpe una sola vez
local function updateDash(enemy: Enemy, now: number)
	local brain = enemy.Brain :: Brain
	local dash = brain.Dash
	if not dash then
		return
	end
	if now >= dash.Until then
		brain.Dash = nil
		refreshSpeed(enemy, now)
		return
	end
	for _, player in Players:GetPlayers() do
		local root, humanoid = characterOf(player)
		if root and humanoid and not dash.Hit[player] and flat(root.Position - enemy.Root.Position) <= dash.Width / 2 + enemy.Radius then
			dash.Hit[player] = true
			damagePlayer(enemy, player, humanoid, dash.Damage)
		end
	end
end

local function bossLeap(enemy: Enemy, targetPosition: Vector3)
	local settings = enemy.Def.Leap
	local generation = enemy.Generation
	local landing = clampToTerritory(enemy, Vector3.new(targetPosition.X, GROUND, targetPosition.Z))
	faceTowards(enemy, landing)
	telegraphDisc(landing, settings.Radius, TELEGRAPH_RED, settings.Telegraph + 0.5, enemy.Run)
	setEyes(enemy, WINDUP_EYES)
	busyThenRecover(enemy, settings.Telegraph + 0.7)
	task.delay(settings.Telegraph, function()
		if enemy.Generation ~= generation or enemy.Status.State == "Dead" or EnemyLogic.isStunned(enemy.Control, os.clock()) then
			return
		end
		-- Vuelo en arco (el cuerpo va anclado mientras salta)
		local start = enemy.Root.Position
		local finish = landing + Vector3.new(0, enemy.RootHeight + 0.5 + StudFloor.raiseAt(landing.X, landing.Z), 0)
		local heading = Vector3.new(finish.X - start.X, 0, finish.Z - start.Z)
		heading = if heading.Magnitude > 0.05 then heading.Unit else Vector3.new(0, 0, -1)
		local flight = 0.5
		local began = os.clock()
		enemy.Root.Anchored = true
		while os.clock() - began < flight do
			if enemy.Generation ~= generation then
				enemy.Root.Anchored = false
				return
			end
			local t = (os.clock() - began) / flight
			local point = start:Lerp(finish, t) + Vector3.new(0, math.sin(t * math.pi) * 12, 0)
			enemy.Model:PivotTo(CFrame.lookAt(point, point + heading))
			RunService.Heartbeat:Wait()
		end
		enemy.Model:PivotTo(CFrame.lookAt(finish, finish + heading))
		enemy.Root.Anchored = false
		pcall(function()
			enemy.Root:SetNetworkOwner(nil)
		end)
		setEyes(enemy, restingEyes(enemy))
		burst(landing + Vector3.new(0, 1, 0), enemy.Def.Look.Secondary, 35, false, enemy.Run)
		damageInRadius(enemy, landing + Vector3.new(0, enemy.RootHeight, 0), settings.Radius, settings.Damage)
	end)
end

local function bossVolley(enemy: Enemy, target: Player)
	local settings = enemy.Def.Volley
	local generation = enemy.Generation
	setEyes(enemy, WINDUP_EYES)
	busyThenRecover(enemy, settings.Telegraph + settings.Count * 0.3)
	task.delay(settings.Telegraph, function()
		for _ = 1, settings.Count do
			if enemy.Generation ~= generation or enemy.Status.State == "Dead" then
				return
			end
			local root = characterOf(target)
			if root then
				-- Va hacia donde estaba el jugador al lanzarla: moverse la esquiva
				local from = enemy.Root.Position + Vector3.new(0, 3, 0)
				local aim = root.Position
				faceTowards(enemy, aim)
				local travel = math.max(0.2, (aim - from).Magnitude / settings.Speed)
				local ball = PartFactory.ball(nil :: any, "BossFireball", from, 1.6, enemy.Def.Look.Secondary, Enum.Material.Neon, false)
				placeFx(ball, enemy.Run)
				task.spawn(function()
					local began = os.clock()
					local hit: { [Player]: boolean } = {}
					while os.clock() - began < travel and ball.Parent do
						local position = from:Lerp(aim, (os.clock() - began) / travel)
						ball.Position = position
						for _, player in Players:GetPlayers() do
							local playerRoot, humanoid = characterOf(player)
							if playerRoot and humanoid and not hit[player] and (playerRoot.Position - position).Magnitude <= settings.Radius then
								hit[player] = true
								damagePlayer(enemy, player, humanoid, settings.Damage)
							end
						end
						RunService.Heartbeat:Wait()
					end
					burst(aim, enemy.Def.Look.Secondary, 10, false, enemy.Run)
					ball:Destroy()
				end)
			end
			task.wait(0.3)
		end
		if enemy.Generation == generation then
			setEyes(enemy, restingEyes(enemy))
		end
	end)
end

-- Peligros de la arena (Def.Hazard) ----------------------------------------------------
-- Cada Interval (más seguido con furia) caen Count avisos en el suelo: uno donde está cada
-- jugador de la pelea (con un poco de azar, para que haya que moverse) y el resto por el
-- territorio. Tras Telegraph, el efecto de su Style y el daño (y ralentizar, si SlowFactor) a
-- quien siga dentro. No dependen de lo que haga el jefe: también caen mientras ataca.

local HAZARD_SPOKES = 5

local function hazardEffect(enemy: Enemy, center: Vector3, settings)
	local style = settings.Style
	local color = settings.Color or enemy.Def.Look.Secondary
	local radius = settings.Radius
	if style == "Crystal" or style == "Rock" then
		-- Cae desde arriba y se rompe al tocar el suelo
		local size = if style == "Rock" then Vector3.new(radius * 0.7, radius * 0.7, radius * 0.7) else Vector3.new(radius * 0.45, radius * 1.1, radius * 0.45)
		local shard = PartFactory.part(nil :: any, "HazardDrop", {
			Size = size,
			CFrame = CFrame.new(center + Vector3.new(0, 20, 0)) * CFrame.Angles(0, math.rad(math.random(0, 90)), math.rad(12)),
			Color = color,
			Material = if style == "Rock" then Enum.Material.Basalt else Enum.Material.Neon,
			Solid = false,
		})
		placeFx(shard, enemy.Run)
		TweenService:Create(shard, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(center + Vector3.new(0, size.Y / 2, 0)) }):Play()
		Debris:AddItem(shard, 0.9)
	elseif style == "Lava" then
		-- Columna de lava que sube y se apaga
		local column = PartFactory.verticalCylinder(nil :: any, "HazardColumn", center + Vector3.new(0, 4, 0), 8, radius * 1.4, color, Enum.Material.Neon, false)
		column.Transparency = 0.2
		placeFx(column, enemy.Run)
		TweenService:Create(column, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1, Size = Vector3.new(12, radius * 0.4, radius * 0.4) }):Play()
		Debris:AddItem(column, 0.7)
	else
		-- "Spikes" (espinas) e "Ice" (carámbanos): pinchos que salen del suelo en círculo
		local material = if style == "Ice" then Enum.Material.Glass else Enum.Material.Wood
		for index = 1, HAZARD_SPOKES do
			local angle = index / HAZARD_SPOKES * math.pi * 2
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * 0.55
			local spike = PartFactory.part(nil :: any, "HazardSpike", {
				Size = Vector3.new(0.9, 4.5, 0.9),
				CFrame = CFrame.new(center + offset + Vector3.new(0, 1.8, 0)) * CFrame.Angles(math.rad(14), angle, 0),
				Color = color,
				Material = material,
				Solid = false,
			})
			placeFx(spike, enemy.Run)
			Debris:AddItem(spike, 1.1)
		end
	end
	burst(center + Vector3.new(0, 1, 0), color, 18, false, enemy.Run)
end

local function dropHazard(enemy: Enemy, center: Vector3, settings)
	local generation = enemy.Generation
	telegraphDisc(center, settings.Radius, settings.Color or enemy.Def.Look.Secondary, settings.Telegraph, enemy.Run)
	task.delay(settings.Telegraph, function()
		if enemy.Generation ~= generation or enemy.Status.State == "Dead" then
			return
		end
		hazardEffect(enemy, center, settings)
		local slowFactor, slowSeconds = settings.SlowFactor, settings.SlowSeconds
		damageInRadius(enemy, center, settings.Radius, settings.Damage, if slowFactor and slowSeconds then function(_player, humanoid)
			slowPlayer(humanoid, slowFactor, slowSeconds)
		end else nil)
	end)
end

local function updateHazards(enemy: Enemy, now: number)
	local settings = enemy.Def.Hazard
	local brain = enemy.Brain :: Brain
	if not settings or not enemy.Target or enemy.Status.State == "Return" then
		return
	end
	if brain.NextHazard == nil then
		brain.NextHazard = now + (settings.Interval or 8) * 0.6
		return
	end
	if now < brain.NextHazard then
		return
	end
	brain.NextHazard = now + intervalOf(enemy, settings)
	local points = {}
	local spread = settings.Spread or settings.Radius
	for _, player in Players:GetPlayers() do
		local root = characterOf(player)
		if root and sameWorld(enemy, player) and bossCanTarget(enemy, root.Position) then
			local angle = math.random() * math.pi * 2
			local jitter = Vector3.new(math.cos(angle), 0, math.sin(angle)) * math.random() * spread * 0.4
			table.insert(points, clampToTerritory(enemy, Vector3.new(root.Position.X, GROUND, root.Position.Z) + jitter))
		end
	end
	local count = math.max(settings.Count or 1, #points)
	local territory = (enemy.Territory or enemy.Def.Brain.Territory) - settings.Radius
	while #points < count do
		local angle = math.random() * math.pi * 2
		local distance = math.sqrt(math.random()) * math.max(territory, 4)
		table.insert(points, Vector3.new(enemy.LeashCenter.X + math.cos(angle) * distance, GROUND, enemy.LeashCenter.Z + math.sin(angle) * distance))
	end
	for index, point in points do
		-- Escalonados un poco: no todos a la vez
		task.delay((index - 1) * 0.15, dropHazard, enemy, point, settings)
	end
end

-- Elige y lanza un ataque si hay alguno listo (true si ha atacado)
local function bossTryAttack(enemy: Enemy, target: Player, targetRoot: BasePart, now: number): boolean
	local brain = enemy.Brain :: Brain
	local def = enemy.Def
	local distance = flat(targetRoot.Position - enemy.Root.Position)
	local function ready(name: string): boolean
		return def[name] ~= nil and now >= (brain.NextSpecial[name] or 0)
	end
	local function used(name: string)
		brain.NextSpecial[name] = now + intervalOf(enemy, def[name])
	end
	if ready("Slam") and distance <= def.Slam.Radius + 2 then
		used("Slam")
		bossSlam(enemy)
		return true
	end
	if ready("Charge") and distance >= def.Charge.MinRange and distance <= def.Charge.MaxRange then
		used("Charge")
		bossCharge(enemy, targetRoot.Position)
		return true
	end
	if ready("Leap") and distance >= def.Leap.MinRange and distance <= def.Leap.MaxRange then
		used("Leap")
		bossLeap(enemy, targetRoot.Position)
		return true
	end
	if ready("Volley") and distance <= def.Volley.Range then
		used("Volley")
		bossVolley(enemy, target)
		return true
	end
	if ready("Roots") and distance <= def.Roots.Range then
		used("Roots")
		bossRoots(enemy, targetRoot.Position)
		return true
	end
	if now >= enemy.NextAttack and distance <= def.AttackRange + enemy.Radius then
		enemy.NextAttack = now + EnemyLogic.attackCooldown(def.AttackCooldown, enemy.Control, now)
		bossStrike(enemy, target, targetRoot)
		return true
	end
	return false
end

local function updateBoss(enemy: Enemy, now: number)
	local status = enemy.Status
	if status.State == "Dead" or enemy.Model.Parent == nil then
		return
	end
	local brain = enemy.Brain :: Brain
	local def = enemy.Def
	local position = enemy.Root.Position
	if (position - brain.LastPosition).Magnitude > 0.5 then
		brain.LastPosition = position
		brain.StillSince = now
	end
	updateDash(enemy, now)
	if not brain.Dash then
		refreshSpeed(enemy, now)
	end
	updateHazards(enemy, now)

	-- Vuelta a la arena (invulnerable) y curación al llegar
	if status.State == "Return" then
		setBossState(enemy, "Return")
		enemy.Model:SetAttribute("TargetUserId", nil)
		brain.FarSince = nil
		enemy.SpeedBoost = 1
		if flat(position - enemy.Home) < 4 then
			EnemyLogic.reset(status)
			syncHealth(enemy)
			setEnraged(enemy, false)
			status.State = "Idle"
			setBossState(enemy, "Patrol")
			return
		end
		bossMoveTo(enemy, enemy.Home, now)
		if now - brain.StillSince > EnemyConfig.StuckSeconds then
			place(enemy) -- atascado volviendo: reaparece en el centro
			brain.StillSince = now
		end
		return
	end

	-- Preparando o haciendo un ataque / descansando
	if brain.State == "Busy" then
		if now < brain.Until then
			return
		end
		setBossState(enemy, "Recover")
		brain.Until = now + def.Brain.RecoverSeconds
		enemy.Humanoid:MoveTo(position)
		return
	end
	if brain.State == "Recover" and now < brain.Until then
		return
	end

	-- Objetivo: se mantiene LockSeconds; si deja de valer, el más cercano que vea
	local previous = enemy.Target
	local target = previous
	local targetRoot = if target and target.Parent then characterOf(target) else nil
	if not (targetRoot and sameWorld(enemy, target) and bossCanTarget(enemy, targetRoot.Position)) then
		target, targetRoot = nil, nil
	elseif now >= brain.LockedUntil then
		local closer = bossAcquire(enemy)
		if closer and closer ~= target then
			target = closer
			targetRoot = characterOf(closer)
		end
	end
	if not target then
		target = bossAcquire(enemy)
		targetRoot = if target then characterOf(target) else nil
	end
	if target ~= previous then
		brain.LockedUntil = now + def.Brain.LockSeconds
		brain.Path = nil
	end
	enemy.Target = target
	enemy.Model:SetAttribute("TargetUserId", if target then target.UserId else nil)

	-- Persecución (anti "kiteo"): si su objetivo sigue fuera de su alcance, acelera poco a poco
	-- (EnemyConfig.Pursuit; EnemyLogic.pursuitBoost) hasta casi su velocidad.
	local pursuit = EnemyConfig.Pursuit
	if target and targetRoot and pursuit then
		local reach = def.AttackRange + enemy.Radius
		if flat(targetRoot.Position - position) > reach + (pursuit.Gap or 4) then
			brain.FarSince = brain.FarSince or now
		else
			brain.FarSince = nil
		end
		local base = def.WalkSpeed * (if enemy.Enraged and def.Enrage then def.Enrage.SpeedMultiplier else 1)
		local _, targetHumanoid = characterOf(target)
		enemy.SpeedBoost = if brain.FarSince then EnemyLogic.pursuitBoost(now - brain.FarSince, pursuit, base, if targetHumanoid then targetHumanoid.WalkSpeed else nil) else 1
	else
		brain.FarSince = nil
		enemy.SpeedBoost = 1
	end
	if not brain.Dash then
		refreshSpeed(enemy, now)
	end

	if not (target and targetRoot) then
		-- Sin nadie: si se alejó de la arena vuelve; si no, patrulla
		if flat(position - enemy.LeashCenter) > enemy.LeashRadius + 2 then
			status.State = "Return"
			clearControl(enemy)
			setEyes(enemy, restingEyes(enemy))
			return
		end
		status.State = "Idle"
		setBossState(enemy, "Patrol")
		if now >= enemy.NextWander then
			enemy.NextWander = now + math.random(40, 70) / 10
			local angle = math.random() * math.pi * 2
			enemy.Humanoid:MoveTo(enemy.Home + Vector3.new(math.cos(angle), 0, math.sin(angle)) * math.random(3, math.max(4, math.floor(enemy.LeashRadius * 0.6))))
		end
		return
	end

	-- Aturdido por una habilidad: ni se mueve ni ataca
	if EnemyLogic.isStunned(enemy.Control, now) then
		return
	end
	if bossTryAttack(enemy, target, targetRoot, now) then
		status.State = "Attack"
		return
	end
	status.State = "Chase"
	setBossState(enemy, "Chase")
	bossMoveTo(enemy, targetRoot.Position, now)
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.updateBoss = updateBoss
end

function Part.link(context: any)
	GROUND = context.GROUND
	TELEGRAPH_RED = context.TELEGRAPH_RED
	WINDUP_EYES = context.WINDUP_EYES
end

return Part
