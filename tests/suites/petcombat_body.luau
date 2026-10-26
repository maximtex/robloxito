-- Disparo: el PetCombatService REAL (el único camino de disparo), apuntado (AimLogic real):
-- a mano (clic, mantener pulsado) y automático con el pase, con armas reales (WeaponLogic)
-- y un EnemyService simulado sobre el EnemyLogic real.

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
local knockbacks = 0
function EnemyService.knockback()
	knockbacks += 1
end

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

-- Las pruebas 1 a 8 miden el arma y el estilo SIN clase (la gratis también suma): pasivas
-- neutras hasta la sección 9, que usa las de verdad.
local realClassMods = ClassLogic.mods
ClassLogic.mods = function()
	return ClassLogic.neutral()
end

local failures = 0
local function check(name, ok)
	if not ok then
		failures += 1
	end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local ana
local function reset()
	for _, enemy in enemyList do
		enemy.Model.Parent = nil -- los de la prueba anterior ya no existen
	end
	table.clear(enemyList)
	table.clear(kills)
	table.clear(slows)
	table.clear(fired)
	if ana then
		PetCombatService.refill(ana) -- cargador y maná llenos
	end
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
-- Avanza el reloj de 0.1 en 0.1. `aim` (opcional): antes de cada paso el jugador apunta ahí
-- (`mode`: "Aim" por defecto, el del automático; "Hold" = mantiene pulsado).
local function run(fromTime, seconds, aim, mode, who)
	local t = fromTime
	while t < fromTime + seconds - 1e-9 do
		t += 0.1
		advance(t)
		if aim then
			shotListener(who or ana, aim, mode or "Aim")
		end
		PetCombatService.step(t)
	end
	return t
end
local function at(x, z)
	return Vector3.new(x, 2, z)
end
-- Suelta el botón (tras mantener pulsado)
local function release(who)
	shotListener(who or ana, at(0, 0), "Release")
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

local function eventsOf(kind)
	local list = {}
	for _, entry in fired do
		if entry.Player == ana and entry.Event.Kind == kind then
			table.insert(list, entry.Event)
		end
	end
	return list
end
local function damageOf(enemy)
	return enemy.Status.MaxHealth - enemy.Status.Health
end
local function near2(a, b)
	return math.abs(a - b) < 1e-6
end
local function combosIn(list)
	local count = 0
	for _, shot in list do
		if shot.Combo then
			count += 1
		end
	end
	return count
end

ana = newPlayer("Ana", 1, Vector3.new(0, 3, 0))
profiles[ana] = profileWith("Laser")
-- 0.5: sin crítico (Puntería: 20 %) y las balas sin desviarse; las pruebas lo cambian
local critRoll = 0.5
PetCombatService.random = function()
	return critRoll
end
PetCombatService.start()
playerAdded:Fire(ana)

-- Láser = pistola: 8 × 1.35 = 10.8 por disparo, cada 0.4 s, cargador de 12
local LASER = 10.8

print("-- 1. Con el pase: dispara solo hacia donde apuntas, si va a dar a alguien")
local near = newEnemy(1, 30, 0, 1000)
local far = newEnemy(2, 50, 0, 1000)
local outside = newEnemy(3, 100, 0, 1000)
local now = run(0, 1, at(30, 0))
local list = shots(ana)
check("apuntando al de 30 studs: le dispara a él, sin clic", #list > 0 and list[1].Target.X == 30 and list[1].Miss == nil and ana:GetAttribute("AutoFire") == true)
check(("con la cadencia del láser (0.4 s): %d disparos en 1 s"):format(#list), #list >= 2 and #list <= 4)
check(("cada disparo hace el daño de la pistola (%.1f)"):format(LASER), near2(damageOf(near), LASER * (#list + combosIn(list))))
check("ni el de detrás ni el que está fuera de alcance reciben daño", far.Status.Health == 1000 and outside.Status.Health == 1000)
check("el disparo atribuye el arma y su tipo (pistola) para que el cliente lo dibuje", list[1].WeaponId == "Laser" and list[1].Gun == "Pistol")
check("cada disparo gasta una bala del cargador", ana:GetAttribute("AmmoMax") == 12 and ana:GetAttribute("Ammo") == 12 - #list)
table.clear(fired)
now = run(now, 1, at(0, 30))
check("apuntando a donde no hay nadie, el automático no dispara al aire", #shots(ana) == 0)
table.clear(fired)
local before = damageOf(near)
now = run(now, 1)
check("sin apuntar no dispara solo (nada de buscar al más cercano)", #shots(ana) == 0 and damageOf(near) == before)

print("-- 2. Si cae el de delante, da al siguiente de la línea; sin nadie a tiro, nada")
reset()
local first2 = newEnemy(4, 30, 0, 5)
local second2 = newEnemy(5, 50, 0, 1000)
now = run(now, 0.8, at(30, 0))
check("el de delante muere y el disparo sigue al de detrás", kills[4] == 1 and second2.Status.Health < 1000)
second2.Model.Parent = nil
second2.Status.State = "Dead"
local tooFar2 = newEnemy(6, 100, 0, 1000)
table.clear(fired)
now = run(now, 0.6, at(100, 0))
check("el de 100 studs queda fuera de alcance: no dispara", #shots(ana) == 0 and tooFar2.Status.Health == 1000)

print("-- 3. Altura: no dispara a través de suelos")
reset()
local high = newEnemy(10, 20, 0, 100, 40)
now = run(now, 0.6, at(20, 0), "Hold")
release()
local highShots = shots(ana)
check("apuntando a uno 37 studs más arriba: el disparo falla", #highShots > 0 and highShots[1].Miss == true and high.Status.Health == 100)

print("-- 4. A mano: clic, mantener pulsado, fallos y lo que se cruza")
reset()
local clicked = newEnemy(22, 50, 0, 1000)
local aside = newEnemy(23, 20, 15, 1000)
remotes.SetAutoFire.OnServerEvent:Fire(ana, false)
now = run(now, 0.6, at(50, 0))
check("con el automático apagado, apuntar no dispara", #shots(ana) == 0 and ana:GetAttribute("AutoFire") == false)
shotListener(ana, at(50, 0), "Shot")
now = run(now, 0.6)
check("un clic: un disparo hacia el cursor, al de allí (no al más cercano)", #shots(ana) == 1 and clicked.Status.Health < 1000 and aside.Status.Health == 1000)
table.clear(fired)
before = clicked.Status.Health
shotListener(ana, at(0, -30), "Shot")
now = run(now, 0.6)
local missed = shots(ana)
check("un clic donde no hay nadie: el disparo sale y falla", #missed == 1 and missed[1].Miss == true and #missed[1].Hits == 0 and clicked.Status.Health == before and aside.Status.Health == 1000)
check("el disparo fallido llega al final del alcance (60)", math.abs(missed[1].Target.Z + 60) < 1e-6)
reset()
local heldTarget = newEnemy(24, 50, 0, 100000)
now = run(now, 1, at(50, 0), "Hold")
release()
local heldShots = shots(ana)
check(("mantener pulsado: a la cadencia del arma, no más (%d en 1 s)"):format(#heldShots), #heldShots >= 2 and #heldShots <= 4)
table.clear(fired)
now = run(now, 1, at(-30, 0), "Hold")
release()
local heldMiss = shots(ana)
check("mantener pulsado hacia la nada: dispara igual (y falla)", #heldMiss >= 2 and heldMiss[1].Miss == true)
table.clear(fired)
PetCombatService.refill(ana)
shotListener(ana, at(50, 0), "Hold")
now = run(now, 0.1)
release()
local afterRelease = #shots(ana)
now = run(now, 0.5)
check("al soltar deja de disparar (nada de disparos de más)", #shots(ana) == afterRelease)
remotes.SetAutoFire.OnServerEvent:Fire(ana, true)
table.clear(fired)
now = run(now, 0.6, at(50, 0))
check("al encenderlo vuelve a disparar solo hacia donde apuntas", #shots(ana) >= 1 and heldTarget.Status.Health < 100000 and ana:GetAttribute("AutoFire") == true)

reset()
local blocker = newEnemy(25, 20, 0, 1000)
local behind = newEnemy(26, 40, 0, 1000)
shotListener(ana, at(40, 0), "Shot")
now = run(now, 0.6)
check("el que se cruza en el camino se lleva el disparo", blocker.Status.Health < 1000 and behind.Status.Health == 1000)
reset()
local moved = newEnemy(27, 30, 3.5, 1000)
shotListener(ana, at(30, 0), "Shot")
now = run(now, 0.6)
check("el enemigo apuntado se movió un poco (3.5 studs): le da igual", moved.Status.Health < 1000)
reset()
local wide = newEnemy(28, 30, 7, 1000)
shotListener(ana, at(30, 0), "Shot")
now = run(now, 0.6)
check("pero si apuntas a 7 studs de él, falla", wide.Status.Health == 1000 and shots(ana)[1].Miss == true)

print("-- 5. Cargador y recarga")
reset()
local wall = newEnemy(29, 20, 0, 1e9)
remotes.SetAutoFire.OnServerEvent:Fire(ana, false)
for _ = 1, 12 do
	shotListener(ana, at(20, 0), "Shot")
	now = run(now, 0.4)
end
check("12 disparos vacían el cargador y empieza a recargar solo", ana:GetAttribute("Ammo") == 0 and (ana:GetAttribute("ReloadEnd") or 0) > 0 and #shots(ana) == 12)
table.clear(fired)
shotListener(ana, at(20, 0), "Shot")
now = run(now, 0.3)
check("recargando no dispara", #shots(ana) == 0)
now = run(now, 1.2)
check("tras 1.1 s el cargador vuelve a estar lleno", ana:GetAttribute("Ammo") == 12 and ana:GetAttribute("ReloadEnd") == 0)
shotListener(ana, at(20, 0), "Shot")
now = run(now, 0.4)
shotListener(ana, at(0, 0), "Reload")
now = run(now, 0.1)
check("R: recarga antes de vaciarlo", (ana:GetAttribute("ReloadEnd") or 0) > 0)
now = run(now, 1.2)
check("y vuelve a tener las 12", ana:GetAttribute("Ammo") == 12)
PetCombatService.setBurst(ana, now + 10)
table.clear(fired)
now = run(now, 1, at(20, 0), "Hold")
release()
check(("Ráfaga: dispara el doble de rápido (%d en 1 s) y sin gastar balas"):format(#shots(ana)), #shots(ana) >= 4 and ana:GetAttribute("Ammo") == 12)
PetCombatService.setBurst(ana, 0)
remotes.SetAutoFire.OnServerEvent:Fire(ana, true)

print("-- 6. Tipos de arma de fuego")
reset()
-- Escopeta (Bláster de plasma): 25.6 × 1.6 × 1.45 = 59.392 en 8 perdigones; alcance 27.5
profiles[ana] = profileWith("PlasmaBlaster")
local close6 = newEnemy(30, 10, 0, 100000)
local side6 = newEnemy(31, 10, 4, 100000)
shotListener(ana, at(10, 0), "Shot")
now = run(now, 0.3)
local blast = shots(ana)
check("escopeta: 8 perdigones; de cerca entran todos (59.4)", #blast == 1 and #blast[1].Tracers == 8 and near2(damageOf(close6), 59.392) and blast[1].Gun == "Shotgun")
check("escopeta: el plasma explota y daña al de al lado (50 %)", near2(damageOf(side6), 59.392 * 0.5))
reset()
local far6 = newEnemy(32, 25, 0, 100000)
shotListener(ana, at(25, 0), "Shot")
now = run(now, 1.4)
check("escopeta: de lejos entran menos perdigones (4 de 8)", near2(damageOf(far6), 59.392 / 2))
reset()
local out6 = newEnemy(33, 40, 0, 100000)
shotListener(ana, at(40, 0), "Shot")
now = run(now, 1.4)
check("escopeta: a 40 studs no llega (alcance 27.5)", out6.Status.Health == 100000)

reset()
-- Francotirador (Arco de espinas): 17.6 × 2.2 × 1.5 = 58.08, atraviesa a 2 más (×0.7 cada uno)
profiles[ana] = profileWith("ThornBow")
local s1 = newEnemy(40, 20, 0, 100000)
local s2 = newEnemy(41, 40, 0, 100000)
local s3 = newEnemy(42, 60, 0, 100000)
local s4 = newEnemy(43, 80, 0, 100000)
shotListener(ana, at(20, 0), "Shot")
now = run(now, 0.3)
check("francotirador: atraviesa a 3 en línea (58.1, 40.7, 28.5) y frena", near2(damageOf(s1), 58.08) and near2(damageOf(s2), 58.08 * 0.7) and near2(damageOf(s3), 58.08 * 0.49) and s4.Status.Health == 100000 and #slows >= 3)

reset()
-- Rifle (Cañón cristalino): 64 × 0.4 × 1.3 = 33.28 cada 0.288 s, cargador de 30
profiles[ana] = profileWith("CrystalCannon")
local r1 = newEnemy(44, 20, 0, 100000)
local hop = newEnemy(45, 30, 0, 100000)
now = run(now, 1, at(20, 0), "Hold")
release()
local burstShots = shots(ana)
check(("rifle: automático, %d balas en 1 s"):format(#burstShots), #burstShots >= 3 and #burstShots <= 5 and burstShots[1].Gun == "Rifle" and ana:GetAttribute("AmmoMax") == 30)
check("rifle: cada bala hace 33.28 y salta al siguiente (50 %)", near2(damageOf(r1), 33.28 * (#burstShots + combosIn(burstShots))) and hop.Status.Health < 100000)

reset()
-- Bazuca (Cañón del vacío): 256 × 2 × 1.4 = 716.8; cohete a 110 studs/s; explosión de 10 al 80 %
profiles[ana] = profileWith("VoidCannon")
local rocketTarget = newEnemy(46, 33, 0, 100000)
local rocketSide = newEnemy(47, 38, 0, 100000)
shotListener(ana, at(33, 0), "Shot")
advance(now + 0.1)
PetCombatService.step(now + 0.1)
now += 0.1
local launched = shots(ana)
check("bazuca: sale el cohete (tarda 0.3 s) y aún no hace daño", #launched == 1 and launched[1].Gun == "Launcher" and near2(launched[1].Delay, 0.3) and rocketTarget.Status.Health == 100000)
now = run(now, 0.4)
local impacts = eventsOf("ShotImpact")
check("bazuca: al llegar explota: 716.8 al apuntado y 573.4 al de al lado", #impacts == 1 and near2(damageOf(rocketTarget), 716.8) and near2(damageOf(rocketSide), 716.8 * 0.8) and impacts[1].Radius == 10)
reset()
local ground = newEnemy(48, 22, 5, 100000)
shotListener(ana, at(20, 0), "Shot")
now = run(now, 0.6)
check("bazuca: apuntando al suelo, explota allí y pilla al de al lado", near2(damageOf(ground), 716.8 * 0.8))

print("-- 7. Apuntar (clic derecho)")
reset()
profiles[ana] = profileWith("Laser")
local distant7 = newEnemy(50, 66, 0, 100000)
shotListener(ana, at(66, 0), "Shot")
now = run(now, 0.6)
check("sin apuntar, a 66 studs no llega (alcance 60)", distant7.Status.Health == 100000)
shotListener(ana, at(0, 0), "AdsOn")
shotListener(ana, at(66, 0), "Shot")
now = run(now, 0.6)
check("apuntando llega más lejos (+15 %: 69)", distant7.Status.Health < 100000)
reset()
critRoll = 0.25
local crit7 = newEnemy(51, 20, 0, 100000)
shotListener(ana, at(20, 0), "Shot")
now = run(now, 0.6)
check("apuntando hay más críticos (20 % + 10 %)", shots(ana)[1].Crit == true and near2(damageOf(crit7), LASER * 2 * #shots(ana)))
shotListener(ana, at(0, 0), "AdsOff")
table.clear(fired)
shotListener(ana, at(20, 0), "Shot")
now = run(now, 0.6)
check("sin apuntar, esa misma tirada no es crítico", shots(ana)[1].Crit == false)
critRoll = 0.5

print("-- 8. Mascotas: atacan al último al que le diste")
reset()
profiles[ana] = profileWith("Laser", { "MossFox" })
now = run(now, 1) -- lo último que apuntó ya no cuenta
local idle = newEnemy(59, 20, 0, 100000)
table.clear(fired)
now = run(now, 1.4)
check("sin darle a nadie, las mascotas no atacan solas", petHitsIn(fired) == 0 and idle.Status.Health == 100000)
reset()
local petTarget = newEnemy(60, 20, 0, 100000)
now = run(now, 1.4, at(20, 0))
local petHits = petHitsIn(fired)
check(("la mascota golpea al enemigo al que disparas (%d golpes en 1.4 s)"):format(petHits), petHits >= 2 and petTarget.Status.Health < 100000)
now = run(now, 5.5)
table.clear(fired)
now = run(now, 1)
check("si dejas de darle un rato, las mascotas lo dejan", petHitsIn(fired) == 0)

print("-- 9. Sin el pase: solo ataca cuando se pide")
reset()
profiles[ana] = profileWith("Laser", nil, {})
local manual = newEnemy(70, 20, 0, 1000)
local manualFar = newEnemy(71, 40, 10, 1000)
now = run(now, 0.6, at(20, 0))
check("apuntar sin pedir disparo no dispara, y AutoFire queda en false", #shots(ana) == 0 and manual.Status.Health == 1000 and ana:GetAttribute("AutoFire") == false)
remotes.SetAutoFire.OnServerEvent:Fire(ana, true)
now = run(now, 0.6, at(20, 0))
check("encender el automático sin el pase no hace nada", #shots(ana) == 0 and ana:GetAttribute("AutoFire") == false)
shotListener(ana, at(20, 0), "Shot")
now = run(now, 0.6)
local single = shots(ana)
check("clic: un disparo hacia el cursor", #single == 1 and single[1].Target.X == 20 and near2(damageOf(manual), LASER))
table.clear(fired)
shotListener(ana, at(40, 10), "Shot")
now = run(now, 0.6)
local aimedShots = shots(ana)
check("clic en otro enemigo: le dispara a él aunque haya otro más cerca", #aimedShots == 1 and aimedShots[1].Target.X == 40 and manualFar.Status.Health < 1000)
table.clear(fired)
local tooFar = newEnemy(72, 70, -20, 1000)
shotListener(ana, at(70, -20), "Shot")
now = run(now, 0.6)
check("fuera de alcance (73 > 60): el disparo falla", #shots(ana) == 1 and shots(ana)[1].Miss == true and tooFar.Status.Health == 1000)
reset()
profiles[ana] = profileWith("Laser", { "MossFox" }, {})
local chosen = newEnemy(80, 20, 0, 100000)
shotListener(ana, at(20, 0), "Shot")
now = run(now, 1.4)
check(("las mascotas siguen golpeando al que le diste (%d golpes) aunque el arma dispare una vez"):format(petHitsIn(fired)), #shots(ana) == 1 and petHitsIn(fired) >= 2)

print("-- 10. Puños")
reset()
local fists = profileWith("Laser")
fists.PetData.Style = "Fists"
profiles[ana] = fists
local farFist = newEnemy(91, 20, 0, 100000)
now = run(now, 0.6, at(20, 0))
check("Puños: a 20 studs no llega (alcance 9)", #shots(ana) == 0 and farFist.Status.Health == 100000)
local closeFist = newEnemy(92, 8, 0, 100000)
local behindFist = newEnemy(98, -6, 0, 100000)
table.clear(fired)
now = run(now, 1, at(8, 0))
local punches = shots(ana)
-- Láser: 20 DPS · 1.5 = 30 DPS en golpes de 0.35 s = 10.5 por golpe, sin crítico
local hooks = combosIn(punches)
check(("Puños: golpes rápidos de 10.5 (%d en 1 s, %d gancho ×2) y sin efecto del arma"):format(#punches, hooks), #punches >= 2 and #punches <= 4 and near2(damageOf(closeFist), 10.5 * (#punches + hooks)) and punches[1].Style == "Fists" and punches[1].Splash == nil)
check("combo de golpes: el 3.º puñetazo seguido es un gancho (y empuja)", #punches >= 3 and punches[1].Combo == nil and punches[2].Combo == nil and punches[3].Combo == "¡Gancho!" and knockbacks >= 1)
check("Puños: el de detrás de ti no recibe nada", behindFist.Status.Health == 100000)

print("-- 11. Magia")
reset()
local magic = profileWith("Laser")
magic.PetData.Style = "Magic"
profiles[ana] = magic
ana.Humanoid.MaxHealth = 100
ana.Humanoid.Health = 50
local orbTarget = newEnemy(93, 30, 0, 100000)
local orbClose = newEnemy(94, 33, 0, 100000)
local orbFar = newEnemy(95, 50, 0, 100000)
now = run(now, 0.3, at(30, 0))
local orbs = shots(ana)
-- Magia: 20 DPS × 1.05 en bolas cada 0.45 s = 9.45; explosión de 4 studs al 40 %
check(("Magia: bolas de 9.45 que explotan (3.78 al de al lado), %d bolas"):format(#orbs), #orbs >= 1 and near2(damageOf(orbTarget), 9.45 * #orbs) and near2(damageOf(orbClose), 3.78 * #orbs) and orbFar.Status.Health == 100000 and orbs[1].Splash == 4 and orbs[1].Element == "Fire")
-- Robo de vida: 5 % de 13.23 por bola = 0.6615
check("Magia · Robo de vida: se cura una parte del daño", near2(ana.Humanoid.Health, 50 + 0.6615 * #orbs))
check("cada bola gasta maná (8)", ana:GetAttribute("Mana") < 100 and ana:GetAttribute("ManaMax") == 100)
ana.Humanoid.Health = 100
reset()
local lockTarget = newEnemy(96, 30, 6, 100000)
shotListener(ana, at(30, 0), "Shot")
now = run(now, 0.3)
check("la bola persigue al bicho más cercano a donde apuntas (a 6 studs)", lockTarget.Status.Health < 100000 and shots(ana)[1].Miss == nil)
reset()
local nextTo = newEnemy(97, 20, 18, 100000)
shotListener(ana, at(0, 20), "Shot")
now = run(now, 0.5)
local missOrb = shots(ana)
check("sin bichos cerca del punto: explota donde apuntabas", #missOrb == 1 and missOrb[1].Miss == true and near2(missOrb[1].Target.Z, 20) and nextTo.Status.Health == 100000)
reset()
local chargeTarget = newEnemy(99, 30, 0, 100000)
local chargeSide = newEnemy(100, 38, 0, 100000)
shotListener(ana, at(30, 0), "Charge")
now = run(now, 1.3)
check("cargando no lanza bolas", #shots(ana) == 0)
shotListener(ana, at(30, 0), "Release")
now = run(now, 0.1)
local charged = shots(ana)
-- 21 DPS × (0.6 + 1.5) × 1.6 = 70.56; explosión de 14 studs al 70 %
check("orbe cargado al máximo: 70.56 y explota grande (14) al 70 %", #charged == 1 and charged[1].Charge == 1 and near2(damageOf(chargeTarget), 70.56) and near2(damageOf(chargeSide), 70.56 * 0.7) and charged[1].Splash == 14)
check("el orbe cargado gasta mucho maná (40)", ana:GetAttribute("Mana") <= 61)
reset()
PetCombatService.spendMana(ana, PetCombatService.mana(ana))
local sparkTarget = newEnemy(101, 20, 0, 100000)
shotListener(ana, at(20, 0), "Shot")
now = run(now, 0.1)
local sparks = shots(ana)
check("sin maná: chispa débil (35 %) sin explosión", #sparks == 1 and sparks[1].Spark == true and near2(damageOf(sparkTarget), 9.45 * 0.35) and sparks[1].Splash == nil)

print("-- 12. Guerrero")
reset()
remotes.SetAutoFire.OnServerEvent:Fire(ana, false) -- solo lo que se pide
local warrior = profileWith("Laser")
warrior.PetData.Style = "Warrior"
profiles[ana] = warrior
-- Láser: 20 DPS × 1.35 en tajos de 0.5 s = 13.5 por tajo; combo ×1, ×1.1 y ×1.8 (giro)
local front1 = newEnemy(110, 8, 0, 100000)
local front2 = newEnemy(111, 8, 4, 100000)
local back = newEnemy(112, -8, 0, 100000)
now = run(now, 1.1, at(8, 0), "Hold")
release()
local slashes = shots(ana)
check(("Guerrero: 3 tajos seguidos (%d) con su paso del combo"):format(#slashes), #slashes == 3 and slashes[1].Step == 1 and slashes[2].Step == 2 and slashes[3].Step == 3 and slashes[1].Style == "Warrior")
check("los dos tajos de delante pegan a los dos de enfrente (13.5 y 14.85)", near2(damageOf(front2), 13.5 + 14.85 + 24.3) and near2(damageOf(front1), 13.5 + 14.85 + 24.3))
check("el giro (3.º) pega también al de detrás (24.3) y empuja", near2(damageOf(back), 24.3) and knockbacks >= 3)
reset()
local parried = newEnemy(113, 6, 0, 100000)
shotListener(ana, at(6, 0), "BlockOn")
check("bloquear: lo ven todos", ana:GetAttribute("Blocking") == true)
local factor = PetCombatService.blockIncoming(ana, parried)
check("parada perfecta: no recibe daño, aturde al bicho y avisa", factor == 0 and #eventsOf("Parry") == 1 and slows[#slows].Kind == "Stun")
check("después de la parada, el bloqueo quita el 70 %", PetCombatService.blockIncoming(ana, parried) == 0.3)
shotListener(ana, at(6, 0), "Shot")
now = run(now, 0.3)
check("bloqueando no ataca", #shots(ana) == 0)
shotListener(ana, at(6, 0), "BlockOff")
check("sin bloquear recibe todo", PetCombatService.blockIncoming(ana, parried) == 1 and ana:GetAttribute("Blocking") == false)
shotListener(ana, at(6, 0), "Shot")
now = run(now, 0.3)
local counterSlash = shots(ana)
check("contraataque: el siguiente tajo hace ×2.5 (33.75)", #counterSlash == 1 and counterSlash[1].Counter == true and near2(damageOf(parried), 33.75))
shotListener(ana, at(6, 0), "BlockOn")
check("volver a bloquear enseguida no da otra parada perfecta", PetCombatService.blockIncoming(ana, parried) == 0.3)
shotListener(ana, at(6, 0), "BlockOff")
remotes.SetAutoFire.OnServerEvent:Fire(ana, true)

print("-- 13. Clases (pasiva de la clase activa del estilo)")
ClassLogic.mods = realClassMods
reset()
profiles[ana] = profileWith("Laser") -- sin datos de clases: la gratis (Soldado, nivel 1)
local soldierTarget = newEnemy(120, 20, 0, 100000)
now = run(now, 0.6, at(20, 0))
local soldierShots = shots(ana)
check(("Soldado (gratis): cada disparo hace 10.8 × 1.08 = 11.664 (%d disparos)"):format(#soldierShots), #soldierShots >= 1 and near2(damageOf(soldierTarget), 11.664 * (#soldierShots + combosIn(soldierShots))))

reset()
local demo = profileWith("Laser")
demo.PetData.Classes = ClassLogic.empty()
ClassLogic.buy(demo.PetData.Classes, "Demolisher", 1e9)
profiles[ana] = demo
local demoTarget = newEnemy(121, 20, 0, 100000)
local demoClose = newEnemy(122, 23, 0, 100000)
now = run(now, 0.6, at(20, 0))
local demoShots = shots(ana)
check(("Demoledor: la pistola explota y hace el 30 %% al de al lado (%d disparos)"):format(#demoShots), #demoShots >= 1 and near2(damageOf(demoTarget), LASER * (#demoShots + combosIn(demoShots))) and near2(damageOf(demoClose), LASER * 0.3 * (#demoShots + combosIn(demoShots))) and demoShots[1].Splash == 5)

reset()
local berserk = profileWith("Laser")
berserk.PetData.Style = "Fists"
berserk.PetData.Classes = ClassLogic.empty()
ClassLogic.buy(berserk.PetData.Classes, "Berserker", 1e9)
profiles[ana] = berserk
ana.Humanoid.MaxHealth = 100
ana.Humanoid.Health = 50
local berserkTarget = newEnemy(123, 8, 0, 100000)
now = run(now, 0.6, at(8, 0))
local berserkHits = shots(ana)
local berserkDealt = damageOf(berserkTarget)
-- Puños: 10.5 por golpe × 1.2 (Berserker) = 12.6, y se cura el 3 % de lo que pega
check(("Berserker: Puños pega ×1.2 y se cura el 3 %% del daño (%d golpes)"):format(#berserkHits), #berserkHits >= 1 and berserkDealt >= 12.6 * #berserkHits - 1e-6 and near2(ana.Humanoid.Health, 50 + berserkDealt * 0.03))
ana.Humanoid.Health = 100

reset()
local sniper = profileWith("Laser")
sniper.PetData.Classes = ClassLogic.empty()
ClassLogic.buy(sniper.PetData.Classes, "Sniper", 1e9)
profiles[ana] = sniper
local laserRange = WeaponLogic.definition("Laser").Range
local farTarget = newEnemy(124, laserRange + 4, 0, 100000)
now = run(now, 0.6, at(laserRange + 4, 0))
check("Francotirador: llega más lejos que la pistola normal (+20 %)", #shots(ana) >= 1 and farTarget.Status.Health < 100000)

reset()
local duelist = profileWith("Laser")
duelist.PetData.Style = "Warrior"
duelist.PetData.Classes = ClassLogic.empty()
ClassLogic.buy(duelist.PetData.Classes, "Duelist", 1e9)
profiles[ana] = duelist
critRoll = 0.05
local duelTarget = newEnemy(125, 8, 0, 100000)
shotListener(ana, at(8, 0), "Shot")
now = run(now, 0.3)
check("Duelista (Guerrero): sus tajos tienen críticos", shots(ana)[1].Crit == true)
critRoll = 0.5

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
