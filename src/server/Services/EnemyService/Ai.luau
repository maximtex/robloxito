-- EnemyService · Ai: IA de los enemigos normales (objetivo, zonas seguras, golpe y golpe en área).
-- Parte de EnemyService (ver EnemyService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnemyConfig = require(Shared.Config.EnemyConfig)
local PartFactory = require(script.Parent.Parent.Parent.Util.PartFactory)
local EnemyLogic = require(script.Parent.Parent.Parent.Util.EnemyLogic)
local Types = require(script.Parent.Types)
type Enemy = Types.Enemy
type SafeArea = Types.SafeArea

local ctx: any -- tabla de estado compartida (la crea EnemyService/init.luau)
local ENRAGED_EYES: any
local GROUND: any
local WINDUP_EYES: any

-- Funciones de las otras partes
local function burst(...) return ctx.burst(...) end
local function clearControl(...) return ctx.clearControl(...) end
local function damagePlayer(...) return ctx.damagePlayer(...) end
local function flat(...) return ctx.flat(...) end
local function place(...) return ctx.place(...) end
local function placeFx(...) return ctx.placeFx(...) end
local function refreshSpeed(...) return ctx.refreshSpeed(...) end
local function restingEyes(...) return ctx.restingEyes(...) end
local function sameWorld(...) return ctx.sameWorld(...) end
local function setEnraged(...) return ctx.setEnraged(...) end
local function setEyes(...) return ctx.setEyes(...) end
local function syncHealth(...) return ctx.syncHealth(...) end
local function zoneCenter(...) return ctx.zoneCenter(...) end

-- IA ------------------------------------------------------------------------------

local function characterOf(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil, nil
end

-- Zonas sin monstruos de una zona (EnemyConfig.Zones.*.SafeAreas), en el mundo
local function safeAreasOf(zoneId: string, zoneSettings): { SafeArea }
	local center = zoneCenter(zoneId)
	local areas = {}
	for _, area in zoneSettings.SafeAreas or {} do
		table.insert(areas, {
			Min = Vector2.new(center.X + area.Min.X, center.Z + area.Min.Y),
			Max = Vector2.new(center.X + area.Max.X, center.Z + area.Max.Y),
		})
	end
	return areas
end

local function inSafeArea(areas: { SafeArea }, position: Vector3): boolean
	for _, area in areas do
		if position.X >= area.Min.X and position.X <= area.Max.X and position.Z >= area.Min.Y and position.Z <= area.Max.Y then
			return true
		end
	end
	return false
end

local function inSafeZone(enemy: Enemy, position: Vector3): boolean
	for _, zone in enemy.SafeZones do
		if flat(position - zone.Center) <= zone.Radius then
			return true
		end
	end
	return inSafeArea(enemy.SafeAreas, position)
end

local function canTarget(enemy: Enemy, position: Vector3): boolean
	return flat(position - enemy.LeashCenter) <= enemy.LeashRadius and not inSafeZone(enemy, position)
end

local function acquireTarget(enemy: Enemy): Player?
	local best, bestDistance = nil, math.huge
	for _, player in Players:GetPlayers() do
		local root = characterOf(player)
		if root then
			local distance = flat(root.Position - enemy.Root.Position)
			local inRange = if enemy.Kind == "Boss" then flat(root.Position - enemy.LeashCenter) <= enemy.LeashRadius - 2 else distance <= enemy.DetectRange
			if inRange and distance < bestDistance and sameWorld(enemy, player) and canTarget(enemy, root.Position) then
				best, bestDistance = player, distance
			end
		end
	end
	return best
end

-- Golpe cuerpo a cuerpo avisado: el bicho se compromete (se queda quieto mirando a su
-- objetivo durante AttackWindup, con los ojos encendidos) y al final pega solo por delante y
-- a su alcance: apartarse o rodearlo lo esquiva; el Guerrero puede bloquearlo o pararlo.
-- Atributos para el cliente (AttackWarning y EnemyAnimator): AttackTarget (UserId de a quién
-- va), AttackDir (hacia dónde), AttackReach (alcance) y AttackAt (hora del golpe).
local HIT_SLACK = 1.5 -- studs de margen al validar el golpe
local FRONT_DOT = -0.1 -- un poco más de medio círculo por delante
local function attack(enemy: Enemy, target: Player)
	local generation = enemy.Generation
	local windup = enemy.Def.AttackWindup
	local origin = enemy.Root.Position
	local targetRoot = characterOf(target)
	local forward = if targetRoot then Vector3.new(targetRoot.Position.X - origin.X, 0, targetRoot.Position.Z - origin.Z) else Vector3.zero
	if forward.Magnitude > 0.05 then
		forward = forward.Unit
		enemy.Root.CFrame = CFrame.lookAt(origin, origin + forward)
	else
		local look = enemy.Root.CFrame.LookVector
		forward = Vector3.new(look.X, 0, look.Z)
		forward = if forward.Magnitude > 0.05 then forward.Unit else Vector3.new(0, 0, -1)
	end
	local reach = enemy.Def.AttackRange + enemy.Radius + HIT_SLACK
	enemy.WindupUntil = os.clock() + windup
	enemy.Humanoid:MoveTo(origin)
	setEyes(enemy, WINDUP_EYES) -- aviso del golpe
	enemy.Model:SetAttribute("AttackKind", nil) -- golpe (no disparo): media luna en el suelo
	enemy.Model:SetAttribute("AttackTarget", target.UserId)
	enemy.Model:SetAttribute("AttackDir", forward)
	enemy.Model:SetAttribute("AttackReach", reach)
	-- Momento del golpe para la animación y el aviso del cliente (preparación y golpe).
	enemy.Model:SetAttribute("AttackAt", Workspace:GetServerTimeNow() + windup)
	task.delay(windup, function()
		if enemy.Generation ~= generation or enemy.Status.State == "Dead" then
			return
		end
		enemy.WindupUntil = nil
		setEyes(enemy, restingEyes(enemy))
		if EnemyLogic.isStunned(enemy.Control, os.clock()) then
			return -- aturdido durante la preparación: el golpe se pierde
		end
		local root, humanoid = characterOf(target)
		if not (root and humanoid) then
			return
		end
		local offset = Vector3.new(root.Position.X - enemy.Root.Position.X, 0, root.Position.Z - enemy.Root.Position.Z)
		local distance = offset.Magnitude
		local inFront = distance < enemy.Radius + 1 or offset.Unit:Dot(forward) >= FRONT_DOT
		if distance <= reach and inFront then
			damagePlayer(enemy, target, humanoid, enemy.Def.Damage)
		end
	end)
end

-- Disparo de los bichos a distancia (Def.Ranged; pruebas con amigos: "todos son cuerpo a
-- cuerpo"). Se avisa igual que un golpe (ojos y ¡! sobre su objetivo, AttackKind = "Shot")
-- y al soltarlo sale una bola hacia donde estaba el jugador EN ESE MOMENTO: moverse durante
-- el vuelo la esquiva. Daña al primer jugador de su mundo que toque.
local SHOT_HEIGHT = 1.5 -- sobre la raíz

local function launchShot(enemy: Enemy, from: Vector3, aim: Vector3, settings)
	local direction = aim - from
	if direction.Magnitude < 0.5 then
		return
	end
	-- Sigue un poco más allá del punto (no se para justo donde estabas)
	local range = math.max(direction.Magnitude + 6, 8)
	local finish = from + direction.Unit * range
	local travel = range / math.max(settings.Speed or 36, 1)
	local color = settings.Color or enemy.Def.Look.Secondary
	local ball = PartFactory.ball(nil :: any, "EnemyShot", from, settings.Size or 1.2, color, Enum.Material.Neon, false)
	placeFx(ball, enemy.Run)
	local radius = settings.Radius or 2
	task.spawn(function()
		local began = os.clock()
		while ball.Parent do
			local t = (os.clock() - began) / travel
			if t >= 1 then
				break
			end
			local position = from:Lerp(finish, t)
			ball.Position = position
			for _, player in Players:GetPlayers() do
				local root, humanoid = characterOf(player)
				if root and humanoid and sameWorld(enemy, player) and (root.Position - position).Magnitude <= radius then
					damagePlayer(enemy, player, humanoid, settings.Damage)
					burst(position, color, 8, false, enemy.Run)
					ball:Destroy()
					return
				end
			end
			RunService.Heartbeat:Wait()
		end
		if ball.Parent then
			ball:Destroy()
		end
	end)
end

local function shoot(enemy: Enemy, target: Player)
	local settings = enemy.Def.Ranged
	local generation = enemy.Generation
	local origin = enemy.Root.Position
	local targetRoot = characterOf(target)
	if not targetRoot then
		return
	end
	local forward = Vector3.new(targetRoot.Position.X - origin.X, 0, targetRoot.Position.Z - origin.Z)
	forward = if forward.Magnitude > 0.05 then forward.Unit else Vector3.new(0, 0, -1)
	enemy.Root.CFrame = CFrame.lookAt(origin, origin + forward)
	local windup = settings.Windup or 0.7
	enemy.WindupUntil = os.clock() + windup
	enemy.Humanoid:MoveTo(origin)
	setEyes(enemy, WINDUP_EYES)
	enemy.Model:SetAttribute("AttackKind", "Shot")
	enemy.Model:SetAttribute("AttackTarget", target.UserId)
	enemy.Model:SetAttribute("AttackDir", forward)
	enemy.Model:SetAttribute("AttackReach", settings.Range)
	enemy.Model:SetAttribute("AttackAt", Workspace:GetServerTimeNow() + windup)
	task.delay(windup, function()
		if enemy.Generation ~= generation or enemy.Status.State == "Dead" then
			return
		end
		enemy.WindupUntil = nil
		setEyes(enemy, restingEyes(enemy))
		if EnemyLogic.isStunned(enemy.Control, os.clock()) then
			return
		end
		local root = characterOf(target)
		if not root then
			return
		end
		local from = enemy.Root.Position + Vector3.new(0, SHOT_HEIGHT, 0)
		launchShot(enemy, from, root.Position, settings)
	end)
end

-- ¿Ve a su objetivo? (sin paredes en medio; no cuentan enemigos ni personajes)
local function canSee(enemy: Enemy, point: Vector3): boolean
	local origin = enemy.Root.Position + Vector3.new(0, SHOT_HEIGHT, 0)
	local direction = point - origin
	if direction.Magnitude < 1 then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { ctx.folder, ctx.fxFolder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(origin, direction, params)
	return hit == nil or not hit.Instance.CanCollide
end

-- Atascos al perseguir (pruebas con amigos: "se quedan pegados al terreno"): si casi no se
-- mueve en STUCK_JUMP s salta; si sigue, rodea por un lado DETOUR_SECONDS; y si lleva
-- EnemyConfig.StuckSeconds atascado, vuelve a su sitio (place). true si está rodeando (el
-- que llama no le da otra orden de moverse).
local STUCK_MOVE = 0.6 -- studs que cuentan como moverse
local STUCK_JUMP = 0.9
local STUCK_DETOUR = 1.8
local DETOUR_SECONDS = 0.9

local function handleStuck(enemy: Enemy, now: number, goal: Vector3): boolean
	local position = enemy.Root.Position
	if enemy.DetourUntil and now < enemy.DetourUntil and enemy.DetourPoint then
		enemy.Humanoid:MoveTo(enemy.DetourPoint)
		return true
	end
	enemy.DetourUntil = nil
	local last = enemy.ChaseCheck
	if not last or flat(position - last) > STUCK_MOVE then
		enemy.ChaseCheck = position
		enemy.ChaseStillSince = now
		return false
	end
	local still = now - (enemy.ChaseStillSince or now)
	if still > EnemyConfig.StuckSeconds then
		place(enemy) -- de vuelta a su sitio (sigue persiguiendo desde allí)
		enemy.ChaseCheck = nil
		enemy.ChaseStillSince = nil
		return true
	end
	if still > STUCK_DETOUR then
		-- Rodeo: a un lado (al azar) de la línea hacia su objetivo
		local toward = Vector3.new(goal.X - position.X, 0, goal.Z - position.Z)
		toward = if toward.Magnitude > 0.05 then toward.Unit else Vector3.new(0, 0, -1)
		local side = Vector3.new(-toward.Z, 0, toward.X) * (if math.random() < 0.5 then -1 else 1)
		enemy.DetourPoint = position + side * 7 + toward * 2
		enemy.DetourUntil = now + DETOUR_SECONDS
		enemy.ChaseStillSince = now - STUCK_JUMP -- si el rodeo no sirve, vuelve a probar
		enemy.Humanoid.Jump = true
		enemy.Humanoid:MoveTo(enemy.DetourPoint)
		return true
	end
	if still > STUCK_JUMP then
		enemy.Humanoid.Jump = true
	end
	return false
end

-- Golpe en área del jefe: círculo de aviso en el suelo y daño al terminar.
local function slam(enemy: Enemy)
	local settings = enemy.Def.Slam
	local generation = enemy.Generation
	local center = Vector3.new(enemy.Root.Position.X, GROUND, enemy.Root.Position.Z)
	local diameter = settings.Radius * 2
	local warningColor = if enemy.Enraged then ENRAGED_EYES else enemy.Def.Look.Eyes
	enemy.Model:SetAttribute("SlamAt", Workspace:GetServerTimeNow() + settings.Telegraph)
	-- Borde del área (fijo) y disco interior que crece: cuando llena el borde, golpea.
	local ring = PartFactory.verticalCylinder(nil :: any, "SlamWarning", center + Vector3.new(0, 0.32, 0), 0.12, diameter, warningColor, Enum.Material.Neon, false)
	ring.Transparency = 0.55 -- borde bien visible: aquí acaba el área
	placeFx(ring, enemy.Run)
	local fill = PartFactory.verticalCylinder(nil :: any, "SlamFill", center + Vector3.new(0, 0.36, 0), 0.14, 1, warningColor, Enum.Material.Neon, false)
	fill.Transparency = 0.55
	placeFx(fill, enemy.Run)
	TweenService:Create(fill, TweenInfo.new(settings.Telegraph, Enum.EasingStyle.Linear), { Size = Vector3.new(0.14, diameter, diameter) }):Play()
	Debris:AddItem(ring, settings.Telegraph + 0.1)
	Debris:AddItem(fill, settings.Telegraph + 0.1)
	task.delay(settings.Telegraph, function()
		if enemy.Generation ~= generation or enemy.Status.State == "Dead" then
			return
		end
		if EnemyLogic.isStunned(enemy.Control, os.clock()) then
			return -- aturdido justo al golpear: el golpe en área se interrumpe
		end
		burst(center + Vector3.new(0, 1, 0), enemy.Def.Look.Secondary, 30, false, enemy.Run)
		-- Onda expansiva breve
		local wave = PartFactory.verticalCylinder(nil :: any, "SlamWave", center + Vector3.new(0, 0.4, 0), 0.3, diameter * 0.6, warningColor, Enum.Material.Neon, false)
		wave.Transparency = 0.3
		placeFx(wave, enemy.Run)
		TweenService:Create(wave, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, diameter * 1.15, diameter * 1.15), Transparency = 1 }):Play()
		Debris:AddItem(wave, 0.45)
		for _, player in Players:GetPlayers() do
			local root, humanoid = characterOf(player)
			if root and humanoid and flat(root.Position - center) <= settings.Radius and math.abs(root.Position.Y - center.Y) < 12 then
				damagePlayer(enemy, player, humanoid, settings.Damage)
			end
		end
	end)
end

local function updateEnemy(enemy: Enemy, now: number)
	local status = enemy.Status
	if status.State == "Dead" or enemy.Model.Parent == nil then
		return
	end
	local position = enemy.Root.Position
	local fromHome = flat(position - enemy.LeashCenter)
	refreshSpeed(enemy, now) -- los estados caducan solos: aquí se recupera la velocidad

	-- Volver a casa (invulnerable) y curarse al llegar; si se atasca, reaparece en su origen.
	if status.State == "Return" then
		if flat(position - enemy.Home) < 3 then
			EnemyLogic.reset(status)
			syncHealth(enemy)
			setEnraged(enemy, false) -- también restablece la velocidad
			return
		end
		enemy.Humanoid:MoveTo(enemy.Home)
		if fromHome >= enemy.LastHomeDistance - 0.3 then
			enemy.StuckSince = enemy.StuckSince or now
			if now - enemy.StuckSince > EnemyConfig.StuckSeconds then
				place(enemy)
				enemy.StuckSince = nil
			end
		else
			enemy.StuckSince = nil
		end
		enemy.LastHomeDistance = fromHome
		return
	end

	-- Demasiado lejos de su zona: volver.
	if fromHome > enemy.LeashRadius + 4 then
		status.State = "Return"
		enemy.Target = nil
		clearControl(enemy) -- vuelve sin estados (es invulnerable mientras vuelve)
		refreshSpeed(enemy, now)
		enemy.LastHomeDistance = math.huge
		setEyes(enemy, restingEyes(enemy))
		return
	end

	-- Validar u obtener objetivo
	local target = enemy.Target
	local targetRoot = if target and target.Parent then characterOf(target) else nil
	if not (targetRoot and sameWorld(enemy, target) and canTarget(enemy, targetRoot.Position) and flat(targetRoot.Position - enemy.LeashCenter) <= enemy.LeashRadius + 6) then
		enemy.Target = nil
		target = acquireTarget(enemy)
		enemy.Target = target
		targetRoot = if target then characterOf(target) else nil
	end

	if not (target and targetRoot) then
		status.State = "Idle"
		if now >= enemy.NextWander then
			enemy.NextWander = now + math.random(40, 80) / 10
			local angle = math.random() * math.pi * 2
			enemy.Humanoid:MoveTo(enemy.Home + Vector3.new(math.cos(angle), 0, math.sin(angle)) * math.random(2, 6))
		end
		return
	end

	-- Aturdido: ni golpea ni prepara golpes en área (se retrasan hasta que se recupere).
	local stunned = EnemyLogic.isStunned(enemy.Control, now)

	-- Jefe: golpe en área periódico (más seguido con furia)
	local slamSettings = enemy.Def.Slam
	if slamSettings and now >= enemy.NextSlam then
		if stunned then
			enemy.NextSlam = enemy.Control.StunUntil + 0.5
		else
			local interval = slamSettings.Interval * (if enemy.Enraged then enemy.Def.Enrage.SlamIntervalMultiplier else 1)
			enemy.NextSlam = now + interval
			slam(enemy)
		end
	end

	-- Preparando un golpe: se queda quieto hasta soltarlo (así se puede esquivar)
	if enemy.WindupUntil and now < enemy.WindupUntil then
		status.State = "Attack"
		enemy.Humanoid:MoveTo(position)
		return
	end

	local offset = targetRoot.Position - position
	local distance = flat(offset)
	-- A distancia (Def.Ranged): se para a tiro y dispara; si te acercas mientras recarga,
	-- retrocede un poco (sin salir de su zona). Pegado a él, golpea como los demás.
	local ranged = enemy.Def.Ranged
	if ranged and distance > enemy.Def.AttackRange + enemy.Radius and distance <= ranged.Range and canSee(enemy, targetRoot.Position) then
		status.State = "Attack"
		enemy.ChaseCheck = nil
		local flatOffset = Vector3.new(offset.X, 0, offset.Z)
		local away = if distance > 0.05 then -flatOffset.Unit else Vector3.zero
		local backTo = position + away * 6
		if distance < (ranged.Keep or 0) and now < enemy.NextAttack and flat(backTo - enemy.LeashCenter) <= enemy.LeashRadius - 2 then
			enemy.Humanoid:MoveTo(backTo)
		else
			enemy.Humanoid:MoveTo(if distance > 0.05 then position - away * 0.1 else position)
		end
		if now >= enemy.NextAttack and not stunned then
			enemy.NextAttack = now + EnemyLogic.attackCooldown(ranged.Cooldown or 2.5, enemy.Control, now)
			shoot(enemy, target)
		end
		return
	end
	if distance <= enemy.Def.AttackRange + enemy.Radius then
		status.State = "Attack"
		enemy.ChaseCheck = nil -- quieto a propósito: no cuenta como atasco
		-- Detenerse mirando al objetivo (si están superpuestos no hay dirección: solo parar)
		local flatOffset = Vector3.new(offset.X, 0, offset.Z)
		enemy.Humanoid:MoveTo(if distance > 0.05 then position + flatOffset.Unit * 0.1 else position)
		if now >= enemy.NextAttack and not stunned then
			-- Ralentizado: también ataca más despacio.
			enemy.NextAttack = now + EnemyLogic.attackCooldown(enemy.Def.AttackCooldown, enemy.Control, now)
			attack(enemy, target)
		end
	else
		status.State = "Chase"
		if not handleStuck(enemy, now, targetRoot.Position) then
			enemy.Humanoid:MoveTo(targetRoot.Position)
		end
	end
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.attack = attack
	context.characterOf = characterOf
	context.inSafeArea = inSafeArea
	context.inSafeZone = inSafeZone
	context.safeAreasOf = safeAreasOf
	context.launchShot = launchShot
	context.slam = slam
	context.updateEnemy = updateEnemy
end

function Part.link(context: any)
	ENRAGED_EYES = context.ENRAGED_EYES
	GROUND = context.GROUND
	WINDUP_EYES = context.WINDUP_EYES
end

return Part
