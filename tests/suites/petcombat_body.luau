-- Disparo: el PetCombatService REAL (el único camino de disparo), automático con el pase
-- y a mano sin él, con armas reales (WeaponLogic) y un EnemyService simulado sobre el
-- EnemyLogic real.

-- EnemyService simulado con el EnemyLogic REAL (vida y muerte única).
local enemyList = {}
local kills = {}
local slows = {}
local EnemyService = {}
local function newEnemy(id, x, z, health, y)
	local enemy = {
		Id = id,
		Kind = "Normal",
		Radius = 1.2,
		RootHeight = 1.6,
		Root = { Position = Vector3.new(x, y or 2, z) },
		Model = { Parent = true },
		Status = { State = "Idle", Health = health, MaxHealth = health, Contributions = {} },
	}
	table.insert(enemyList, enemy)
	return enemy
end
function EnemyService.isAlive(enemy)
	return enemy ~= nil and enemy.Model.Parent ~= nil and enemy.Status.State ~= "Dead"
end
function EnemyService.damage(enemy, player, amount)
	if enemy.Model.Parent == nil then
		return 0, false
	end
	local dealt, killed = EnemyLogic.applyDamage(enemy.Status, player.UserId, amount)
	if killed then
		kills[enemy.Id] = (kills[enemy.Id] or 0) + 1
		enemy.Model.Parent = nil
	end
	return dealt, killed
end
-- Oleadas privadas: en estas pruebas todos están en el mundo normal
function EnemyService.canInteract(player, enemy)
	return enemy ~= nil
end
function EnemyService.findInRadius(center, radius, maxTargets)
	local candidates, byId = {}, {}
	for _, enemy in enemyList do
		if EnemyService.isAlive(enemy) and math.abs(enemy.Root.Position.Y - center.Y) <= 10 + enemy.RootHeight then
			byId[enemy.Id] = enemy
			table.insert(candidates, { Id = enemy.Id, X = enemy.Root.Position.X, Z = enemy.Root.Position.Z, Radius = enemy.Radius, Alive = true })
		end
	end
	local result = {}
	for _, id in EnemyLogic.selectInRadius(center.X, center.Z, candidates, radius, maxTargets) do
		table.insert(result, byId[id])
	end
	return result
end
function EnemyService.applyControl(enemy, kind, seconds, factor)
	table.insert(slows, { Enemy = enemy, Kind = kind, Seconds = seconds, Factor = factor })
	return true
end
function EnemyService.onClicked() end

-- Números de combate del arma (PlayerDataService.combatStats) con el WeaponLogic real
PlayerDataService.combatStats = function(profile)
	local weapons = profile.PetData.Weapons
	local weaponId = weapons.Equipped
	local level = WeaponLogic.level(weapons, weaponId)
	return {
		WeaponId = weaponId,
		Level = level,
		Shot = WeaponLogic.shotDamage(weaponId, level, 1, 1),
		Cooldown = WeaponLogic.cooldown(weaponId, 0),
		Range = WeaponConfig.Weapons[weaponId].Range,
		RawPower = WeaponLogic.power(weaponId, level, 0, 1, 1),
		Bonus = 1,
	}
end

local PetCombatService = (function()
	PETCOMBAT_SOURCE_HERE
end)()

local failures = 0
local function check(name, ok)
	if not ok then
		failures += 1
	end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local function reset()
	for _, enemy in enemyList do
		enemy.Model.Parent = nil -- los de la prueba anterior ya no existen
	end
	table.clear(enemyList)
	table.clear(kills)
	table.clear(slows)
	table.clear(fired)
end
local function shots(player)
	local list = {}
	for _, entry in fired do
		if entry.Player == player and entry.Event.Kind == "PlayerShot" then
			table.insert(list, entry.Event)
		end
	end
	return list
end
local function run(fromTime, seconds)
	local t = fromTime
	while t < fromTime + seconds - 1e-9 do
		t += 0.1
		advance(t)
		PetCombatService.step(t)
	end
	return t
end
-- Por defecto con el pase "Disparo automático"; passes = {} para jugar sin él
local function profileWith(weaponId, equipped, passes)
	local weapons = WeaponLogic.empty()
	WeaponLogic.grant(weapons, weaponId)
	weapons.Equipped = weaponId
	return { PetData = { Weapons = weapons }, UpgradeLevels = {}, PetMultiplier = 1, Equipped = equipped or {}, Passes = passes or { AutoFire = true } }
end
local function petHitsIn(list)
	local count = 0
	for _, entry in list do
		if entry.Event.Kind == "FoxBolt" then
			count += 1
		end
	end
	return count
end

local ana = newPlayer("Ana", 1, Vector3.new(0, 3, 0))
profiles[ana] = profileWith("Laser")
PetCombatService.start()
playerAdded:Fire(ana)

print("-- 1. Con el pase: objetivo automático y cadencia del arma")
local near = newEnemy(1, 30, 0, 1000)
local far = newEnemy(2, 50, 0, 1000)
local outside = newEnemy(3, 100, 0, 1000)
local now = run(0, 1)
local list = shots(ana)
check("dispara solo al más cercano a tiro, sin clic", #list > 0 and list[1].Target.X == 30 and ana:GetAttribute("AutoFire") == true)
check(("con la cadencia del láser (0.25 s): %d disparos en 1 s"):format(#list), #list >= 3 and #list <= 5)
check("cada disparo hace el daño del arma (5)", near.Status.MaxHealth - near.Status.Health == 5 * #list)
check("ni el lejano ni el que está fuera de alcance reciben daño", far.Status.Health == 1000 and outside.Status.Health == 1000)
check("el disparo atribuye el arma para que el cliente lo dibuje", list[1].WeaponId == "Laser")

print("-- 2. Cambia de objetivo al matarlo y se detiene sin objetivos")
near.Status.Health = 5
table.clear(fired)
now = run(now, 0.6)
check("el cercano muere y sigue con el siguiente a tiro", kills[1] == 1 and far.Status.Health < 1000)
far.Model.Parent = nil
far.Status.State = "Dead"
table.clear(fired)
now = run(now, 0.6)
check("sin enemigos a tiro no dispara (el de 100 studs queda fuera)", #shots(ana) == 0 and outside.Status.Health == 1000)

print("-- 3. Altura: no dispara a través de suelos")
reset()
newEnemy(10, 20, 0, 100, 40)
now = run(now, 0.6)
check("un enemigo 37 studs más arriba no es objetivo", #shots(ana) == 0)

print("-- 4. Elegir con clic; con el automático apagado se dispara a mano")
reset()
local distant = newEnemy(20, 70, 0, 1000)
local nearby = newEnemy(21, 20, 0, 1000)
hitListener(ana, distant)
now = run(now, 0.6)
check("elegido con clic fuera de alcance (70 > 60): se mantiene pero aún no dispara", #shots(ana) == 0 and nearby.Status.Health == 1000)
ana.Root.Position = Vector3.new(30, 3, 0)
now = run(now, 0.6)
check("al acercarse dispara al elegido, no al más cercano", #shots(ana) > 0 and distant.Status.Health < 1000 and nearby.Status.Health == 1000)
ana.Root.Position = Vector3.new(0, 3, 0)

reset()
local clicked = newEnemy(22, 50, 0, 1000)
local auto = newEnemy(23, 20, 0, 1000)
remotes.SetAutoFire.OnServerEvent:Fire(ana, false)
now = run(now, 0.6)
check("con el automático apagado no dispara", #shots(ana) == 0 and ana:GetAttribute("AutoFire") == false)
hitListener(ana, clicked)
shotListener(ana, clicked)
now = run(now, 0.6)
check("apagado, un clic: un disparo al elegido, no al más cercano", #shots(ana) == 1 and clicked.Status.Health < 1000 and auto.Status.Health == 1000)
remotes.SetAutoFire.OnServerEvent:Fire(ana, true)
table.clear(fired)
now = run(now, 0.6)
check("al encenderlo sigue disparando solo, al elegido", #shots(ana) >= 2 and auto.Status.Health == 1000 and ana:GetAttribute("AutoFire") == true)

print("-- 5. Efectos de las armas")
reset()
profiles[ana] = profileWith("PlasmaBlaster")
local center = newEnemy(30, 20, 0, 10000)
local close = newEnemy(31, 23, 0, 10000)
local away = newEnemy(32, 40, 0, 10000)
now = run(now, 0.6)
local plasma = shots(ana)
check("plasma: daña al objetivo y al que está a menos de 6 studs (50 %)", #plasma > 0 and center.Status.MaxHealth - center.Status.Health == 16 * #plasma and close.Status.MaxHealth - close.Status.Health == 8 * #plasma)
check("plasma: el que está lejos no recibe nada y el disparo avisa del radio", away.Status.Health == 10000 and plasma[1].Splash == 6)

reset()
profiles[ana] = profileWith("CrystalCannon")
local first = newEnemy(40, 20, 0, 10000)
local hop1 = newEnemy(41, 30, 0, 10000)
local hop2 = newEnemy(42, 40, 0, 10000)
local hop3 = newEnemy(43, 50, 0, 10000)
now = run(now, 0.5)
local crystal = shots(ana)
check("cristal: salta a 2 enemigos más (50 %), en cadena", #crystal > 0 and hop1.Status.Health < 10000 and hop2.Status.Health < 10000 and hop3.Status.Health == 10000 and #crystal[1].Chain == 2)
check("cristal: el primero recibe el daño entero", first.Status.MaxHealth - first.Status.Health == 40 * #crystal)

reset()
profiles[ana] = profileWith("ThornBow")
newEnemy(50, 20, 0, 10000)
now = run(now, 0.4)
check("arco: ralentiza al objetivo (factor 0.6, 1.5 s)", #slows > 0 and slows[1].Kind == "Slow" and slows[1].Factor == 0.6 and slows[1].Seconds == 1.5)

print("-- 6. Mascotas: golpean al mismo objetivo")
reset()
profiles[ana] = profileWith("Laser", { "MossFox" })
local petTarget = newEnemy(60, 20, 0, 100000)
now = run(now, 1.4)
local petHits = petHitsIn(fired)
check(("la mascota equipada golpea al objetivo del arma (%d golpes en 1.4 s)"):format(petHits), petHits >= 2 and petTarget.Status.Health < 100000)

print("-- 7. Sin el pase: solo dispara cuando se pide")
reset()
profiles[ana] = profileWith("Laser", nil, {})
local manual = newEnemy(70, 20, 0, 1000)
local manualFar = newEnemy(71, 40, 0, 1000)
now = run(now, 0.6)
check("sin pedirlo no dispara ni elige objetivo, y AutoFire queda en false", #shots(ana) == 0 and manual.Status.Health == 1000 and ana:GetAttribute("AutoFire") == false)
remotes.SetAutoFire.OnServerEvent:Fire(ana, true)
now = run(now, 0.6)
check("encender el automático sin el pase no hace nada", #shots(ana) == 0 and ana:GetAttribute("AutoFire") == false)
shotListener(ana, nil)
now = run(now, 0.6)
local single = shots(ana)
check("F / Disparar: un disparo, al más cercano a tiro", #single == 1 and single[1].Target.X == 20 and manual.Status.MaxHealth - manual.Status.Health == 5)
table.clear(fired)
for _ = 1, 10 do
	shotListener(ana, nil)
	now = run(now, 0.1)
end
local held = shots(ana)
check(("mantener pulsado: dispara a la cadencia del arma, no más (%d en 1 s)"):format(#held), #held >= 3 and #held <= 5)
table.clear(fired)
hitListener(ana, manualFar)
shotListener(ana, manualFar)
now = run(now, 0.6)
local aimedShots = shots(ana)
check("clic en un enemigo: le dispara a él aunque haya otro más cerca", #aimedShots == 1 and aimedShots[1].Target.X == 40)
table.clear(fired)
local tooFar = newEnemy(72, 70, 0, 1000)
hitListener(ana, tooFar)
shotListener(ana, tooFar)
now = run(now, 0.6)
ana.Root.Position = Vector3.new(30, 3, 0)
now = run(now, 0.6)
check("la petición caduca: fuera de alcance no dispara, ni luego al acercarse", #shots(ana) == 0 and tooFar.Status.Health == 1000)
ana.Root.Position = Vector3.new(0, 3, 0)

reset()
shotListener(ana, nil)
now = run(now, 0.3)
check("sin enemigos a tiro, pedir un disparo no hace nada", #shots(ana) == 0)

reset()
profiles[ana] = profileWith("Laser", { "MossFox" }, {})
local chosen = newEnemy(80, 20, 0, 100000)
hitListener(ana, chosen)
shotListener(ana, chosen)
now = run(now, 1.4)
check(("las mascotas siguen golpeando al elegido (%d golpes) aunque el arma dispare una vez"):format(petHitsIn(fired)), #shots(ana) == 1 and petHitsIn(fired) >= 2)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
