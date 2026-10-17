-- EnemyService simulado con el EnemyLogic REAL (vida, muerte única y reparto).
local enemyList = {}
local kills = {}
local payouts = {}
local incomingModifier
local EnemyService = {}
local function newEnemy(id, x, z, health)
	local enemy = {
		Id = id,
		Kind = "Normal",
		Radius = 1.2,
		RootHeight = 1.6,
		Reward = 100,
		Root = { Position = Vector3.new(x, 2, z) },
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
		for userId, value in EnemyLogic.splitReward(enemy.Status.Contributions, enemy.Reward) do
			payouts[userId] = (payouts[userId] or 0) + value
		end
	end
	return dealt, killed
end
function EnemyService.findInRadius(center, radius, maxTargets)
	local candidates, byId = {}, {}
	for _, enemy in enemyList do
		if EnemyService.isAlive(enemy) then
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
function EnemyService.setIncomingDamageModifier(fn)
	incomingModifier = fn
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
local function count(kind, player)
	local n = 0
	for _, f in fired do
		if f.Event.Kind == kind and (player == nil or f.Event.Owner == player) and f.Player == f.Event.Owner then
			n += 1
		end
	end
	return n
end
local function damageOf(enemy, userId)
	return enemy.Status.Contributions[userId] or 0
end

local alice = newPlayer("Alice", 1, Vector3.new(0, 3, 0))
profiles[alice] = { UpgradeLevels = { GeneratorPower = 10 }, PetMultiplier = 1.35, Equipped = {} }
PetCombatService.start()
playerAdded:Fire(alice)
local playerDamage = CombatMath.playerDamage(10, 1.35)
local foxDamage = CombatMath.petAbilityDamage(PetCombatConfig.Abilities.QuartzFox.DamageRatio, playerDamage)

print("-- Sin mascotas de combate")
local dummy = newEnemy(1, 0, -6, 10000)
advance(0)
hitListener(alice, dummy)
for t = 0.25, 3, 0.25 do
	advance(t)
	PetCombatService.step(t)
end
check("sin mascotas de combate no hay ningún ataque extra", #fired == 0 and damageOf(dummy, 1) == 0)
profiles[alice].Equipped = { "Sproutling", "MoonOwl" }
for t = 3.25, 5, 0.25 do
	advance(t)
	PetCombatService.step(t)
end
check("mascotas sin habilidad (Brotecillo, Búho) tampoco atacan", #fired == 0)

print("-- Zorrito de Cuarzo")
profiles[alice].Equipped = { "QuartzFox" }
hitListener(alice, dummy)
local times = {}
for t = 5, 9, 0.05 do
	advance(t)
	local before = count("FoxBolt", alice)
	PetCombatService.step(t)
	if count("FoxBolt", alice) > before then
		table.insert(times, t)
	end
end
local minGap = math.huge
for i = 2, #times do
	minGap = math.min(minGap, times[i] - times[i - 1])
end
check(("ataca respetando su intervalo (%d rayos en 4 s, separación mínima %.2f s >= %.2f)"):format(#times, minGap, PetCombatConfig.Abilities.QuartzFox.Interval), #times >= 3 and minGap >= PetCombatConfig.Abilities.QuartzFox.Interval - 1e-6)
check(("daño de cada rayo = %.2f (0.35 × %.2f del jugador)"):format(foxDamage, playerDamage), math.abs(damageOf(dummy, 1) - foxDamage * #times) < 1e-6)
local boltsBefore = count("FoxBolt", alice)
profiles[alice].Equipped = { "MossFox" } -- desequipa el zorrito
for t = 9.05, 12, 0.25 do
	advance(t)
	PetCombatService.step(t)
end
check("al desequiparlo deja de atacar de inmediato", count("FoxBolt", alice) == boltsBefore)
profiles[alice].Equipped = { "QuartzFox" }
for t = 12, 20, 0.25 do
	advance(t)
	PetCombatService.step(t)
end
check("fuera de combate (6 s sin golpear) no ataca", count("FoxBolt", alice) == boltsBefore)
local far = newEnemy(2, 0, -60, 1000)
hitListener(alice, far)
advance(20.25)
PetCombatService.step(20.25)
check("objetivo fuera de alcance: no ataca", count("FoxBolt", alice) == boltsBefore)

print("-- Dragón Bebé de Amatista")
local function engage(t, enemy)
	advance(t)
	hitListener(alice, enemy)
	PetCombatService.step(t)
end
profiles[alice].Equipped = { "AmethystDragon" }
local center = newEnemy(10, 0, -8, 5000)
local near1 = newEnemy(11, 4, -8, 5000)
local near2 = newEnemy(12, -5, -10, 5000)
local outside = newEnemy(13, 30, -8, 5000)
engage(30, center)
check("lanza la nova y avisa antes del impacto (DragonCast sin impacto aún)", count("DragonCast", alice) == 1 and count("DragonImpact", alice) == 0)
advance(30 + PetCombatConfig.Abilities.AmethystDragon.Telegraph)
local novaDamage = CombatMath.petAbilityDamage(PetCombatConfig.Abilities.AmethystDragon.DamageRatio, playerDamage)
check(("impacto: cada enemigo del área recibe %.2f UNA vez"):format(novaDamage), damageOf(center, 1) == novaDamage and damageOf(near1, 1) == novaDamage and damageOf(near2, 1) == novaDamage)
check("los enemigos fuera del radio no reciben daño", damageOf(outside, 1) == 0)
for t = 31, 39.75, 0.25 do
	engage(t, center) -- sigue en combate todo el rato
end
check("respeta su recarga de 10 s (una sola nova)", count("DragonCast", alice) == 1)
local crowd = {}
for i = 1, 10 do
	table.insert(crowd, newEnemy(100 + i, (i % 4) - 2, -8 + (i % 3), 5000))
end
engage(40, center)
advance(41)
local struck = 0
for _, enemy in { center, near1, near2, table.unpack(crowd) } do
	if damageOf(enemy, 1) > (if enemy == center or enemy == near1 or enemy == near2 then novaDamage else 0) then
		struck += 1
	end
end
check(("con 13 enemigos en el área golpea como mucho %d (golpeó %d)"):format(PetCombatConfig.Abilities.AmethystDragon.MaxTargets, struck), count("DragonImpact", alice) == 2 and struck >= 1 and struck <= PetCombatConfig.Abilities.AmethystDragon.MaxTargets)
-- Cancelaciones durante el aviso
local impacts = count("DragonImpact", alice)
engage(50, center)
local before = damageOf(center, 1)
alice.CharacterRemoving:Fire() -- muere durante el aviso
advance(51)
check("si el jugador muere durante el aviso, la nova se anula", count("DragonImpact", alice) == impacts and damageOf(center, 1) == before)
engage(60, center)
profiles[alice].Equipped = {} -- desequipa durante el aviso
advance(61)
check("si se desequipa durante el aviso, la nova se anula", count("DragonImpact", alice) == impacts)
profiles[alice].Equipped = { "AmethystDragon" }
engage(70, center)
alice.AttributeSignals.CurrentZone:Fire() -- viaja a otra zona durante el aviso
advance(71)
check("si cambia de zona durante el aviso, la nova se anula", count("DragonImpact", alice) == impacts)
alice.CharacterRemoving:Fire()
engage(71.5, center)
check(("morir no reinicia la recarga: %d novas en 30/40/50/60/70 s, ninguna extra"):format(count("DragonCast", alice)), count("DragonCast", alice) == 5)

print("-- Tortuga de Musgo Cristalino")
profiles[alice].Equipped = {}
check("sin tortuga el daño recibido no cambia (20 -> 20)", incomingModifier(alice, 20) == 20)
profiles[alice].Equipped = { "CrystalTurtle" }
local one = incomingModifier(alice, 20)
local again = incomingModifier(alice, 20)
check(("1 tortuga: 20 -> %.1f (-15 %%)"):format(one), math.abs(one - 17) < 1e-6)
check("repetir golpes, cambiar de zona o reaparecer no acumula la reducción", again == one)
alice.AttributeSignals.CurrentZone:Fire()
alice.CharacterRemoving:Fire()
check("tras cambiar de zona y reaparecer sigue siendo -15 %", math.abs(incomingModifier(alice, 20) - 17) < 1e-6)
profiles[alice].Equipped = { "CrystalTurtle", "CrystalTurtle", "CrystalTurtle" }
local capped = incomingModifier(alice, 20)
check(("3 tortugas: tope del %d %% (20 -> %.1f), nunca invulnerable"):format(PetCombatConfig.Abilities.CrystalTurtle.MaxReduction * 100, capped), math.abs(capped - 20 * (1 - PetCombatConfig.Abilities.CrystalTurtle.MaxReduction)) < 1e-6 and capped > 0)
check("muestra el bloqueo al dueño (TurtleBlock)", count("TurtleBlock", alice) >= 1)

print("-- Recompensa única con jugador, zorrito y dragón a la vez")
local bob = newPlayer("Bob", 2, Vector3.new(2, 3, 0))
profiles[bob] = { UpgradeLevels = { GeneratorPower = 0 }, PetMultiplier = 1, Equipped = { "QuartzFox" } }
playerAdded:Fire(bob)
profiles[alice].Equipped = { "QuartzFox", "AmethystDragon" }
alice.Humanoid.Health = 100
local target = newEnemy(500, 0, -6, 300)
target.Reward = 120
local t = 100
while EnemyService.isAlive(target) and t < 200 do
	EnemyService.damage(target, alice, playerDamage) -- golpe del jugador
	hitListener(alice, target)
	hitListener(bob, target)
	advance(t)
	PetCombatService.step(t)
	t += 0.25
end
advance(t + 2)
check("el enemigo muere exactamente una vez", kills[500] == 1)
local total = 0
for _, userId in { 1, 2 } do
	total += payouts[userId] or 0
end
check(("recompensa total repartida = 120 (%d)"):format(total), total == 120 and (payouts[2] or 0) > 0)
print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
