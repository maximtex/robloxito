local failures = 0
local function check(name, ok)
	if not ok then
		failures += 1
	end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local function newEnemy(hp)
	return { State = "Idle", Health = hp, MaxHealth = hp, Contributions = {} }
end

print("-- Fórmula de daño")
check("nivel 0 sin mascotas = 10", CombatMath.playerDamage(0, 1) == 10)
check("nivel 10 con x1.35 = 35.25 (" .. CombatMath.playerDamage(10, 1.35) .. ")", CombatMath.playerDamage(10, 1.35) == 35.25)
check("nivel 16 con x2 = 63", CombatMath.playerDamage(16, 2) == 63)
check("cada nivel de mejora suma daño (nivel 5 > nivel 4)", CombatMath.playerDamage(5, 1) > CombatMath.playerDamage(4, 1))
check("multiplicador < 1 o nivel negativo no bajan de la base", CombatMath.playerDamage(-3, 0.5) == 10)

print("-- Dinero y Armería")
check("ya no hay una mejora de daño aparte: el daño es del arma (WeaponConfig)", EconomyConfig.Upgrades.LaserPower == nil and CombatConfig.DamageUpgradeId == nil)
local shopMoney = true
for _, upgradeId in { "PetPower", "LaserSpeed" } do
	local def = EconomyConfig.Upgrades[upgradeId]
	if not (def and def.Currency == "Money") then
		shopMoney = false
	end
end
check("las mejoras de la Armería cuestan dinero", shopMoney)
local speed = EconomyConfig.Upgrades.WalkSpeed
check("la Velocidad de Correr (puesto ⚡ Mejoras) se paga con 💎", speed.Currency == "Diamonds" and speed.SpeedPerLevel > 0)
check("ya no existe la Resonancia del Cristal (ni la producción de energía)", EconomyConfig.Upgrades.GeneratorPower == nil and EconomyConfig.BaseProductionPerSecond == nil and EconomyConfig.PassiveEnergy == nil)
local allHit = true
for _, def in EnemyConfig.Types do
	if not (def.Damage > 0 and def.Reward > 0) then
		allHit = false
	end
end
check("todos los enemigos hacen daño y sueltan dinero", allHit)

print("-- Daño y muerte")
local e = newEnemy(40)
local dealt, killed = EnemyLogic.applyDamage(e, 1, 25)
check("golpe de 25 a 40 de vida -> 25 aplicado, vivo", dealt == 25 and not killed and e.Health == 15)
dealt, killed = EnemyLogic.applyDamage(e, 1, 25)
check("el daño sobrante se recorta (15) y muere en ese golpe", dealt == 15 and killed and e.State == "Dead")
dealt, killed = EnemyLogic.applyDamage(e, 2, 999)
check("muerto: más golpes no aplican nada ni vuelven a matar", dealt == 0 and not killed)
local nan = 0 / 0
local badText: any = "9"
check("daño inválido (NaN, negativo, texto) se ignora", EnemyLogic.applyDamage(newEnemy(10), 1, nan) == 0 and EnemyLogic.applyDamage(newEnemy(10), 1, -5) == 0 and EnemyLogic.applyDamage(newEnemy(10), 1, badText) == 0)
local back = newEnemy(100)
back.State = "Return"
check("volviendo a casa es invulnerable", EnemyLogic.applyDamage(back, 1, 50) == 0 and back.Health == 100)

print("-- Jefe con golpes simultáneos de varios jugadores")
local boss = newEnemy(1500)
local kills = 0
for _ = 1, 200 do
	for userId = 1, 4 do
		local _, k = EnemyLogic.applyDamage(boss, userId, 4 + userId)
		if k then
			kills += 1
		end
	end
end
check(("800 golpes de 4 jugadores: exactamente 1 muerte (%d)"):format(kills), kills == 1)
local payouts = EnemyLogic.splitReward(boss.Contributions, 1200)
local sum, count = 0, 0
for _, amount in payouts do
	sum += amount
	count += 1
end
check(("recompensa repartida entre 4: suma exactamente 1200 (%d)"):format(sum), sum == 1200 and count == 4)
check("quien más daño hizo recibe más", payouts[4] > payouts[1])
local solo = EnemyLogic.splitReward({ [7] = 40 }, 25)
check("un solo jugador recibe la recompensa completa (25)", solo[7] == 25)
check("sin daño registrado no hay recompensa", next(EnemyLogic.splitReward({}, 500)) == nil)
EnemyLogic.reset(boss)
check("reaparecer: vida llena, Idle y contribuciones borradas", boss.Health == 1500 and boss.State == "Idle" and next(boss.Contributions) == nil)

print("-- Objetivos de un golpe")
local cands = {
	{ Id = "frente", X = 0, Z = -6, Radius = 1.2, Alive = true },
	{ Id = "lejos", X = 0, Z = -15, Radius = 1.2, Alive = true },
	{ Id = "detras", X = 0, Z = 8, Radius = 1.2, Alive = true },
	{ Id = "pegado_detras", X = 0, Z = 2.5, Radius = 1.2, Alive = true },
	{ Id = "muerto", X = 1, Z = -3, Radius = 1.2, Alive = false },
	{ Id = "frente", X = 0, Z = -6, Radius = 1.2, Alive = true },
	{ Id = "jefe", X = 0, Z = -12, Radius = 4.5, Alive = true },
}
-- Golpe en arco (lo usan las habilidades): alcance 9, ~100° a cada lado del frente
local ARC_RANGE, ARC_DOT, ARC_MAX_TARGETS = 9, -0.2, 3
local hits = EnemyLogic.selectTargets(0, 0, 0, -1, cands, ARC_RANGE, ARC_DOT, 10)
local set = {}
for _, id in hits do
	set[id] = (set[id] or 0) + 1
end
check("alcanza al de delante dentro del alcance", set.frente == 1)
check("no alcanza al que está fuera de alcance", set.lejos == nil)
check("no alcanza al que está detrás y lejos", set.detras == nil)
check("sí al que está pegado aunque esté detrás", set.pegado_detras == 1)
check("nunca a un enemigo muerto", set.muerto == nil)
check("cada enemigo como mucho una vez por golpe", set.frente == 1)
check("los enemigos grandes se miden hasta su borde", set.jefe == 1)
check("máximo de objetivos por golpe respetado", #EnemyLogic.selectTargets(0, 0, 0, -1, cands, 50, -1, ARC_MAX_TARGETS) == ARC_MAX_TARGETS)

print("-- Configuración de enemigos y zonas")
for typeId, def in EnemyConfig.Types do
	local ok = table.find(BUILDERS, def.Look.Style) ~= nil and table.find(SHAPES, def.Look.Style) ~= nil
	check(("%s (%s): modelo '%s', vida %d, daño %d, recompensa %d, reaparece %ds"):format(typeId, def.Kind, def.Look.Style, def.MaxHealth, def.Damage, def.Reward, def.RespawnSeconds), ok)
end
for zoneId, zone in EnemyConfig.Zones do
	local kinds = {}
	for _, spawn in zone.Spawns do
		local def = EnemyConfig.Types[spawn.Type]
		if def then
			kinds[def.Kind] = true
		else
			check(zoneId .. ": tipo inexistente " .. spawn.Type, false)
		end
		for _, safe in zone.SafeZones do
			local d = math.sqrt((spawn.Offset.X - safe.Center.X) ^ 2 + (spawn.Offset.Y - safe.Center.Y) ^ 2)
			if d < safe.Radius + 12 then
				check(("%s: %s en (%d,%d) demasiado cerca de una zona protegida"):format(zoneId, spawn.Type, spawn.Offset.X, spawn.Offset.Y), false)
			end
		end
		-- Fuera de las zonas sin monstruos y con margen para que al pasear no entren
		for _, area in zone.SafeAreas or {} do
			local dx = math.max(area.Min.X - spawn.Offset.X, 0, spawn.Offset.X - area.Max.X)
			local dz = math.max(area.Min.Y - spawn.Offset.Y, 0, spawn.Offset.Y - area.Max.Y)
			if math.sqrt(dx * dx + dz * dz) < 6 then
				check(("%s: %s en (%d,%d) dentro o al borde de una zona sin monstruos"):format(zoneId, spawn.Type, spawn.Offset.X, spawn.Offset.Y), false)
			end
		end
	end
	local bossDef = EnemyConfig.Types[zone.Boss.Type]
	kinds[bossDef.Kind] = true
	check(zoneId .. ": tiene Normal, Fuerte y Jefe", kinds.Normal and kinds.Strong and kinds.Boss)
	local a = zone.Boss.Arena
	for _, safe in zone.SafeZones do
		local d = math.sqrt((a.Center.X - safe.Center.X) ^ 2 + (a.Center.Y - safe.Center.Y) ^ 2)
		check(("%s: arena a %d studs de la zona protegida (%d,%d), sin solaparse"):format(zoneId, d, safe.Center.X, safe.Center.Y), d > a.Radius + 4 + safe.Radius)
	end
	check(zoneId .. ": arena dentro de la zona", math.sqrt(a.Center.X ^ 2 + a.Center.Y ^ 2) + a.Radius < ZoneConfig.Zones[zoneId].Radius)
	check(zoneId .. ": jefe con dos ataques (golpe + área) y furia", bossDef.Slam ~= nil and bossDef.Enrage ~= nil)
end
-- El centro del pueblo (spawn, plaza y Jardín de los Huevos) es zona sin monstruos
local function inForestArea(offset)
	for _, area in EnemyConfig.Zones.Forest.SafeAreas or {} do
		if offset.X >= area.Min.X and offset.X <= area.Max.X and offset.Y >= area.Min.Y and offset.Y <= area.Max.Y then
			return true
		end
	end
	return false
end
check("Bosque: el spawn, la plaza y el Jardín de los Huevos son zona sin monstruos",
	-- spawn (0, 43), centro de la plaza (0, 25) y Jardín de los Huevos (EggConfig.Gardens.Forest.Center)
	inForestArea(Vector2.new(0, 43)) and inForestArea(Vector2.new(0, 25)) and inForestArea(Vector2.new(38, 85)))
check("Valle más poderoso que el bosque", EnemyConfig.Types.Shardling.MaxHealth > EnemyConfig.Types.Thornling.MaxHealth and EnemyConfig.Types.GeodeGolem.Damage > EnemyConfig.Types.Barkbrute.Damage)
local function cost(n)
	return math.floor(10 * 1.5 ^ n)
end
check(("Guardián (1200) <= mejora 13 (%d): no se salta la progresión"):format(cost(13)), EnemyConfig.Types.ForestWarden.Reward <= cost(13))
check(("Coloso (4000) <= mejora 16 (%d)"):format(cost(16)), EnemyConfig.Types.AmethystColossus.Reward <= cost(16))

print("-- Persecución de los jefes (anti kiteo)")
local pursuit = EnemyConfig.Pursuit
check("hay persecución configurada", type(pursuit) == "table" and pursuit.Max > 1 and pursuit.Ramp > 0)
check("al principio no acelera (aún puede alcanzarte andando)", EnemyLogic.pursuitBoost(pursuit.Delay, pursuit, 10, 26) == 1 and EnemyLogic.pursuitBoost(0, pursuit, 10, 26) == 1)
local midBoost = EnemyLogic.pursuitBoost(pursuit.Delay + 1, pursuit, 10, 26)
check("si sigues huyendo, acelera poco a poco", midBoost > 1 and midBoost < EnemyLogic.pursuitBoost(pursuit.Delay + 2, pursuit, 10, 26))
check("como mucho Max × su velocidad", math.abs(EnemyLogic.pursuitBoost(60, pursuit, 10, 1000) - pursuit.Max) < 1e-9)
check("y nunca más rápido que CatchUp × tu velocidad", EnemyLogic.pursuitBoost(60, pursuit, 10, 16) * 10 <= 16 * pursuit.CatchUp + 1e-9)
check("si ya es más rápido que tú, no acelera", EnemyLogic.pursuitBoost(60, pursuit, 30, 16) == 1)
check("sin datos raros", EnemyLogic.pursuitBoost(0 / 0, pursuit, 10, 16) == 1 and EnemyLogic.pursuitBoost(5, nil, 10, 16) == 1)

print("-- Identidad visual y mecánicas por zona")
local types = EnemyConfig.Types
check("Caldera tiene modelos distintos a los del Valle (FlameImp, MagmaBrute, VolcanoTitan)",
	types.Cinderling.Look.Style ~= types.Shardling.Look.Style
	and types.MagmaGolem.Look.Style ~= types.GeodeGolem.Look.Style
	and types.CalderaTitan.Look.Style ~= types.AmethystColossus.Look.Style)
check("los lanzadores de cada zona tienen su propio tema visual",
	types.ThornCaster.Look.Theme == "Forest"
	and types.CrystalCaster.Look.Theme == "Crystal"
	and types.EmberCaster.Look.Theme == "Ember"
	and types.FrostCaster.Look.Theme == "Frost")
check("los enemigos de cada zona tienen mecánicas propias (Trait)",
	types.Barkbrute.Trait and types.Barkbrute.Trait.Kind == "BrambleSlow"
	and types.Shardling.Trait and types.Shardling.Trait.Kind == "CrystalWard"
	and types.Cinderling.Trait and types.Cinderling.Trait.Kind == "EmberPool"
	and types.FrostWolf.Trait and types.FrostWolf.Trait.Kind == "FrostChill"
	and types.Goblin.Trait and types.Goblin.Trait.Kind == "BattleFrenzy")
print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
