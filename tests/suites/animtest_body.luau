local EnemyAnimator = (function()
	ANIMATOR_SOURCE_HERE
end)()

-- Modelos falsos con la misma estructura que crea EnemyService (raíz + piezas + Motor6D "Pose").
local function newModel(typeId, kind, groups, attrs)
	local attributes = attrs
	attributes.EnemyType = typeId
	attributes.Kind = kind
	local model = { Name = typeId }
	local root = { Name = "HumanoidRootPart", Size = Vector3.new(3, 4, 2), Position = Vector3.new(0, 3, 0), AssemblyLinearVelocity = Vector3.new(0, 0, 0), Transparency = 1, CFrame = { LookVector = Vector3.new(0, 0, -1) } }
	root.Parent = model
	function root.IsA(_, c) return c == "BasePart" end
	local descendants = { root }
	local motors, parts = {}, {}
	for _, spec in groups do
		local part = { Name = spec[1], Transparency = 0, LocalTransparencyModifier = 0 }
		function part.IsA(_, c) return c == "BasePart" end
		local motor = { Name = "Pose", Transform = CFrame.identity, Attr = { Group = spec[2], Side = spec[3], Pivot = Vector3.new(spec[3], 2, 0) } }
		function motor.IsA(_, c) return c == "Motor6D" end
		function motor.GetAttribute(self, k) return self.Attr[k] end
		table.insert(descendants, part)
		table.insert(descendants, motor)
		table.insert(motors, motor)
		table.insert(parts, part)
	end
	model.PrimaryPart = root
	model.Parent = true
	function model.IsA(_, c) return c == "Model" end
	function model.GetAttribute(_, k) return attributes[k] end
	function model.SetAttribute(_, k, v) attributes[k] = v end
	function model.GetDescendants() return descendants end
	function model.FindFirstChildOfClass() return { HipHeight = 1.6 } end
	return model, motors, parts, root
end

local brute, bruteMotors, bruteParts, bruteRoot = newModel("Barkbrute", "Strong", { { "Torso", "Body", 0 }, { "Arm1", "Arm", 1 }, { "Arm-1", "Arm", -1 }, { "Leg1", "Leg", 1 }, { "Leg-1", "Leg", -1 } }, { Health = 180, MaxHealth = 180, AttackWindup = 0.7, FxColor = Color3.fromRGB(1, 2, 3) })
local thorn, thornMotors = newModel("Thornling", "Normal", { { "Body", "Body", 0 }, { "Foot1", "Leg", 1 }, { "Foot-1", "Leg", -1 } }, { Health = 40, MaxHealth = 40, AttackWindup = 0.35 })
local boss, bossMotors = newModel("ForestWarden", "Boss", { { "Trunk", "Body", 0 }, { "UpperArm1", "Arm", 1 }, { "UpperArm-1", "Arm", -1 } }, { Health = 1500, MaxHealth = 1500, AttackWindup = 0.5, SlamTelegraph = 1.2, ArenaCenter = Vector3.new(0, 0, 0), ArenaRadius = 20, DisplayName = "Guardián" })
local zoneModels = { brute, thorn, boss }
local zone = { GetChildren = function() return zoneModels end }
enemiesFolder = { GetChildren = function() return { zone } end }

local bossSpawns = 0
EnemyAnimator.start({ OnBossSpawn = function() bossSpawns += 1 end, SpawnSound = "rbxasset://sounds/impact_explosion_03.mp3" })

local failures = 0
local function check(name, ok)
	if not ok then failures += 1 end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local function step(to)
	while clock < to - 1e-9 do
		clock += 1 / 60
		local i = 1
		while i <= #delayed do
			if delayed[i].At <= clock then
				local d = table.remove(delayed, i)
				d.Fn(table.unpack(d.Args))
			else
				i += 1
			end
		end
		frame(1 / 60)
	end
end
local function rotated(motor) return motor.Transform.R end
local function countCreated(name)
	local n = 0
	for _, o in created do
		if o.Name == name then n += 1 end
	end
	return n
end

-- 1. Aparición: el servidor marca SpawnedAt; se materializa (transparencia 1 -> 0).
step(1)
brute:SetAttribute("SpawnedAt", clock)
boss:SetAttribute("SpawnedAt", clock)
step(1.1)
check("aparición: empieza casi transparente", bruteParts[1].LocalTransparencyModifier > 0.5)
step(2)
check("aparición: termina visible", bruteParts[1].LocalTransparencyModifier == 0)
check("aparición: anillo en el suelo", countCreated("EnemyRing") >= 2)
check("entrada de jefe: columna de luz y aviso (1 vez)", countCreated("EnemyColumn") == 1 and bossSpawns == 1)

-- 2. Reposo y paso
step(3)
check("en reposo respira (el cuerpo se mueve un poco)", bruteMotors[1].Transform.P.Y ~= 0)
bruteRoot.AssemblyLinearVelocity = Vector3.new(9, 0, 0)
step(3.5)
check("al caminar las piernas se balancean", rotated(bruteMotors[4]) > 0.01 or rotated(bruteMotors[5]) > 0.01)
bruteRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)

-- 3. Golpe normal: preparación (brazo levantado) y golpe
local attackAt = 5
brute:SetAttribute("AttackAt", attackAt)
step(attackAt - 0.05)
local raised = math.max(rotated(bruteMotors[2]), rotated(bruteMotors[3]))
check(("preparación: un brazo levantado (%.2f rad)"):format(raised), raised > 1.5)
local puffsBefore = countCreated("EnemyPuff")
step(attackAt + 0.05)
check("golpe: polvo donde cae (enemigo fuerte)", countCreated("EnemyPuff") == puffsBefore + 1)
step(attackAt + 1)
check("después del golpe vuelve al reposo", math.max(rotated(bruteMotors[2]), rotated(bruteMotors[3])) < 0.05)

-- Sin brazos: embiste con el cuerpo
thorn:SetAttribute("AttackAt", 7)
step(7.05)
check("enemigo sin brazos: embestida del cuerpo", thornMotors[1].Transform.P.Z ~= 0)

-- 4. Golpe en área del jefe: ambos brazos arriba durante el aviso
boss:SetAttribute("SlamAt", 10)
step(9.9)
check("aviso del golpe en área: ambos brazos arriba", rotated(bossMotors[2]) > 2 and rotated(bossMotors[3]) > 2)
step(11)
check("tras el golpe en área vuelve al reposo", rotated(bossMotors[2]) < 0.05)

-- 5. Retroceso al recibir un golpe confirmado
step(12)
local before = bruteMotors[1].Transform.R
EnemyAnimator.react(brute, 1)
step(12.05)
check("retroceso al recibir daño confirmado", bruteMotors[1].Transform.R > before + 0.05)
step(12.5)
check("el retroceso es breve", bruteMotors[1].Transform.R < 0.05)

-- 6. Muerte: se disuelve y se hunde
brute:SetAttribute("Health", 0)
brute:SetAttribute("DiedAt", clock)
step(clock + 0.35)
local mid = bruteParts[1].LocalTransparencyModifier
step(clock + 0.5)
check(("muerte: se disuelve (%.2f -> %.2f)"):format(mid, bruteParts[1].LocalTransparencyModifier), mid > 0.2 and mid < 1 and bruteParts[1].LocalTransparencyModifier == 1)
check("muerte: se hunde", bruteMotors[1].Transform.P.Y < -0.5)

-- 7. Reaparece el mismo modelo: vuelve a ser visible (no se queda disuelto)
brute:SetAttribute("Health", 180)
brute:SetAttribute("DiedAt", nil)
brute:SetAttribute("SpawnedAt", clock)
step(clock + 1)
check("al reaparecer vuelve a verse", bruteParts[1].LocalTransparencyModifier == 0)

-- 8. Lejos de la cámara: pose de reposo y sin animar
camera.CFrame.Position = Vector3.new(0, 5, 500)
brute:SetAttribute("AttackAt", clock + 0.5)
step(clock + 0.3)
check("lejos: no se anima (reposo)", rotated(bruteMotors[2]) == 0 and bruteMotors[1].Transform.P.Y == 0)

-- 9. Retirado del mundo (muerto): no da errores ni se queda en la lista
zoneModels = { thorn }
camera.CFrame.Position = Vector3.new(0, 5, 20)
step(clock + 1)
check("modelos retirados se olvidan sin errores", true)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
