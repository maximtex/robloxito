-- Habilidades elementales: configuración, fórmulas puras (AbilityLogic), estados de
-- control (EnemyLogic) y el AbilityService REAL con enemigos y datos simulados.

local failures = 0
local function check(name, ok)
	if not ok then
		failures += 1
	end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local function near(a, b, eps)
	return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (eps or 1e-6)
end
local function events(kind, player)
	local list = {}
	for _, f in fired do
		if f.Remote == "AbilityEvent" and type(f.Event) == "table" and f.Event.Kind == kind and (player == nil or f.Player == player) then
			table.insert(list, f)
		end
	end
	return list
end
local function results()
	local list = {}
	for _, f in fired do
		if f.Remote == "AbilityResult" then
			table.insert(list, f.Args)
		end
	end
	return list
end
local function freshWorld()
	table.clear(enemyList)
	table.clear(fired)
	table.clear(engaged)
	table.clear(marks)
end
local function health(enemy)
	return enemy.Status.Health
end

-- Poder del arma equipada (PlayerDataService.combatStats): estas pruebas fijan la base con
-- la fórmula de referencia (nivel 10 y mascotas ×1.35 = 35.25) y el renacimiento y las
-- aventuras del perfil, como el servicio real.
PlayerDataService.combatStats = function(profile)
	local bonus = RebirthLogic.damageMultiplier(RebirthLogic.ofProfile(profile)) * AdventureLogic.damageMultiplier(AdventureLogic.ofProfile(profile), os.time())
	return { Power = CombatMath.withBonus(CombatMath.playerDamage(profile.UpgradeLevels.LaserPower or 0, profile.PetMultiplier), bonus) }
end
local D = CombatMath.playerDamage(10, 1.35) -- 35.25
local function r2(value)
	return math.floor(value * 100 + 0.5) / 100
end

-- 1. Configuración --------------------------------------------------------------------
local TYPES = { Roots = true, Heal = true, Burn = true, Gust = true, Chain = true, Frost = true, Curse = true, Starfall = true }
local seenTypes = {}
local allOk, summariesOk = true, true
for _, elementId in CoreConfig.Order do
	local ability = AbilityLogic.get(elementId)
	local ok = type(ability) == "table" and TYPES[ability.Type] == true and type(ability.Name) == "string" and #ability.Name > 0
		and type(ability.Icon) == "string" and #ability.Icon > 0 and type(ability.Color) == "table"
		and type(ability.Cooldown) == "number" and ability.Cooldown > 0
		and type(ability.DamageRatio) == "number" and ability.DamageRatio > 0
	if not ok then
		allOk = false
		print("  elemento sin habilidad válida: " .. elementId)
	else
		seenTypes[ability.Type] = (seenTypes[ability.Type] or 0) + 1
		local summary = AbilityLogic.summary(elementId, D, 10)
		if #summary < 10 or summary:find("nil") then
			summariesOk = false
			print("  resumen raro: " .. elementId .. " -> " .. summary)
		end
	end
end
check("los 8 elementos tienen su habilidad completa", allOk)
local distinct = 0
for _, n in seenTypes do
	distinct += if n == 1 then 1 else 0
end
check("cada elemento tiene un tipo de habilidad distinto", distinct == 8)
check("los resúmenes de la interfaz tienen números reales", summariesOk)
check("resumen de Fuego (nivel 10)", AbilityLogic.summary("Fire", D, 10) == "Llamarada de 55 y quemadura de 102 en 4 s")
check("elemento desconocido: sin habilidad ni resumen", AbilityLogic.get("Plasma") == nil and AbilityLogic.get(nil) == nil and AbilityLogic.summary("Plasma", D, 0) == "")

-- 2. Fórmulas -------------------------------------------------------------------------
check("Naturaleza no tiene maestría (ya sube con el cristal)", AbilityLogic.mastery("Nature", 30) == 1)
check("maestría: nivel 0 = ×1, nivel 10 = ×1.2", AbilityLogic.mastery("Water", 0) == 1 and near(AbilityLogic.mastery("Water", 10), 1.2))
check("maestría con tope en el nivel 50 (×2)", near(AbilityLogic.mastery("Water", 500), 2) and AbilityLogic.mastery("Water", -3) == 1 and AbilityLogic.mastery("Water", 0 / 0) == 1)
check("daño = fracción · daño del jugador · maestría", AbilityLogic.damage("Fire", 1.3, D, 10) == 54.99)
check("daño 0 con daño de jugador no válido", AbilityLogic.damage("Fire", 1.3, 0, 10) == 0 and AbilityLogic.damage("Fire", 1.3, 0 / 0, 10) == 0)
local chain = AbilityLogic.chainDamages(100, 4, 0.8)
check("daños de la cadena: cada salto el 80 %", #chain == 5 and chain[1] == 100 and chain[2] == 80 and chain[5] == 40.96)

local cands = {
	{ Id = "A", X = 0, Z = 0, Radius = 1, Alive = true },
	{ Id = "B", X = 5, Z = 0, Radius = 1, Alive = true },
	{ Id = "C", X = 10, Z = 0, Radius = 1, Alive = true },
	{ Id = "D", X = 30, Z = 0, Radius = 1, Alive = true },
	{ Id = "E", X = 3, Z = 1, Radius = 1, Alive = false },
}
local order = AbilityLogic.chainOrder(cands, "A", 6, 4)
check("cadena: salta al más cercano, sin repetir ni pasar del alcance", #order == 3 and order[1] == "A" and order[2] == "B" and order[3] == "C")
check("cadena: respeta el número de saltos", #AbilityLogic.chainOrder(cands, "A", 6, 1) == 2)
check("cadena: sin primer objetivo válido no hay cadena", #AbilityLogic.chainOrder(cands, "E", 6, 4) == 0 and #AbilityLogic.chainOrder(cands, "Z", 6, 4) == 0)

local rootSeconds = AbilityLogic.control("Root", 1.5, nil, false)
local bossRoot = AbilityLogic.control("Root", 1.5, nil, true)
local _, bossSlow = AbilityLogic.control("Slow", 4, 0.5, true)
local _, normalSlow = AbilityLogic.control("Slow", 4, 0.5, false)
check("jefes: inmovilizar dura un 40 %", rootSeconds == 1.5 and near(bossRoot, 0.6))
check("jefes: ralentizar a la mitad de fuerza", normalSlow == 0.5 and near(bossSlow, 0.75))
check("estados con tope de duración", AbilityLogic.control("Stun", 60, nil, false) == AbilityConfig.MaxControlSeconds)
check("quemadura de Fuego: 8 tics", AbilityLogic.burnTicks(AbilityConfig.Abilities.Fire) == 8)

-- 3. Estados de control (EnemyLogic) --------------------------------------------------
local c = EnemyLogic.newControl()
check("ralentizar se aplica", EnemyLogic.applyControl(c, "Slow", 0, 3, 0.5, 10) == true)
check("ralentizado: mitad de velocidad y ataques más espaciados", EnemyLogic.speed(10, c, 1) == 5 and EnemyLogic.attackCooldown(2, c, 1) == 4)
EnemyLogic.applyControl(c, "Slow", 1, 5, 0.8, 10)
check("una ralentización más débil no sustituye a la fuerte, pero alarga", c.SlowFactor == 0.5 and c.SlowUntil == 6)
check("la ralentización caduca sola", EnemyLogic.speed(10, c, 6.1) == 10 and EnemyLogic.attackCooldown(2, c, 6.1) == 2)
EnemyLogic.applyControl(c, "Slow", 7, 2, 0.8, 10)
check("tras caducar, la nueva ralentización vale tal cual", c.SlowFactor == 0.8)
EnemyLogic.applyControl(c, "Root", 10, 1, nil, 10)
check("inmovilizado: velocidad 0 (pero no aturdido)", EnemyLogic.speed(10, c, 10.5) == 0 and not EnemyLogic.isStunned(c, 10.5))
EnemyLogic.applyControl(c, "Stun", 20, 0.5, nil, 10)
check("aturdido: ni anda ni ataca", EnemyLogic.isStunned(c, 20.2) and EnemyLogic.speed(10, c, 20.2) == 0 and not EnemyLogic.isStunned(c, 20.6))
EnemyLogic.applyControl(c, "Vulnerable", 30, 6, 0.3, 10)
check("marcado: recibe un 30 % más de daño mientras dura", near(EnemyLogic.damageTaken(100, c, 31), 130) and EnemyLogic.damageTaken(100, c, 36.5) == 100)
check("estados no válidos se rechazan", not EnemyLogic.applyControl(c, "Slow", 40, 0 / 0, 0.5, 10) and not EnemyLogic.applyControl(c, "Root", 40, -1, nil, 10)
	and not EnemyLogic.applyControl(c, "Fly", 40, 1, nil, 10) and not EnemyLogic.applyControl(c, "Slow", 40, 1, nil, 10) and not EnemyLogic.applyControl(c, "Root", 40, math.huge, nil, 10))
EnemyLogic.applyControl(c, "Stun", 50, 100, nil, 10)
check("duración con tope", c.StunUntil == 60)
EnemyLogic.applyControl(c, "Slow", 50, 1, 0.01, 10)
check("ralentización con tope (nunca paralizado del todo)", c.SlowFactor == 0.1)
EnemyLogic.clearControl(c)
check("limpiar quita todos los estados", c.StunUntil == 0 and c.SlowFactor == 1 and c.VulnerableBonus == 0 and EnemyLogic.speed(10, c, 50.5) == 10)

-- 4. AbilityService -------------------------------------------------------------------
local alice = newPlayer("Alice", 1, Vector3.new(0, 3, 0))
local bob = newPlayer("Bob", 2, Vector3.new(10, 3, 0))
local carol = newPlayer("Carol", 3, Vector3.new(500, 3, 0))
local function newProfile()
	return { UpgradeLevels = { GeneratorPower = 10, LaserPower = 10 }, PetMultiplier = 1.35, PetData = { Cores = CoreLogic.empty() } }
end
profiles[alice] = newProfile()
profiles[bob] = newProfile()
profiles[carol] = newProfile()
local cores = profiles[alice].PetData.Cores
local function choose(elementId, level)
	local entry = cores.Elements[elementId]
	entry.Unlocked = true
	entry.Level = level
	cores.Selected = elementId
end
local function nextTurn()
	advance(clock + 20) -- todas las recargas terminadas
	freshWorld()
end

AbilityService.start()
local SERVER = 5000 -- desplazamiento del reloj del servidor simulado

-- Naturaleza (por defecto) ------------------------------------------------------------
cores.Selected = "Water" -- seleccionado pero NO despierto: se usa Naturaleza
check("elemento no despierto -> habilidad de Naturaleza", AbilityService.elementOf(profiles[alice]) == "Nature")
local e1 = newEnemy(1, 0, -6, 500)
local e2 = newEnemy(2, 8, 0, 500)
local boss = newEnemy(3, 0, 10, 5000, "Boss")
local e4 = newEnemy(4, 0, -40, 500)
local code, elementId, readyAt = AbilityService.perform(alice)
check("Raíces: se usa", code == "Success" and elementId == "Nature")
check("Raíces: recarga de 8 s en hora del servidor", near(readyAt, clock + SERVER + 8))
check("Raíces: daño en área (1.6 × daño)", near(500 - health(e1), r2(1.6 * D)) and near(500 - health(e2), r2(1.6 * D)) and near(5000 - health(boss), r2(1.6 * D)))
check("Raíces: no alcanza fuera del radio", health(e4) == 500)
check("Raíces: inmoviliza 1.5 s (jefe: 0.6 s)", near(e1.Control.RootUntil, clock + 1.5) and near(boss.Control.RootUntil, clock + 0.6))
check("Raíces: efecto para el dueño y el cercano, no para el lejano", #events("Roots", alice) == 1 and #events("Roots", bob) == 1 and #events("Roots", carol) == 0)
local rootsEvent = events("Roots", alice)[1]
check("Raíces: el efecto lleva los 3 impactos y su dueño", rootsEvent and #rootsEvent.Event.Hits == 3 and rootsEvent.Event.Owner == alice)
check("las mascotas se unen una sola vez por uso", #engaged == 1 and engaged[1].Player == alice)
code, _, readyAt = AbilityService.perform(alice)
check("recargando: no se usa otra vez", code == "Cooldown" and near(readyAt, clock + SERVER + 8) and near(500 - health(e1), r2(1.6 * D)))
advance(clock + 7.9)
check("recargando aún a los 7.9 s", (AbilityService.perform(alice)) == "Cooldown")
advance(clock + 0.1)
check("lista a los 8 s", (AbilityService.perform(alice)) == "Success")

-- Remote: ritmo y ráfagas ---------------------------------------------------------------
nextTurn()
local useRemote = remotes.UseAbility
useRemote.OnServerEvent:Fire(alice)
useRemote.OnServerEvent:Fire(alice)
local list = results()
check("remote: primera petición confirmada con elemento y hora", #list == 2 and list[1][1] == true and list[1][2] == "Success" and list[1][3] == "Nature" and near(list[1][4], clock + SERVER + 8))
check("remote: segunda petición inmediata -> demasiado pronto", list[2][1] == false and list[2][2] == "TooFast")
for _ = 1, 10 do
	useRemote.OnServerEvent:Fire(alice)
end
check("remote: las ráfagas abusivas se ignoran en silencio", #results() == 10)

-- Agua: cura ---------------------------------------------------------------------------
nextTurn()
choose("Water", 10)
alice.Humanoid.Health = 50
bob.Humanoid.Health = 60
carol.Humanoid.Health = 60
local w1 = newEnemy(5, 0, -5, 500)
code, elementId = AbilityService.perform(alice)
check("Marea: se usa la habilidad del elemento elegido", code == "Success" and elementId == "Water")
check("Marea: te cura un 35 %", alice.Humanoid.Health == 85)
check("Marea: cura un 20 % a los aliados cercanos, no a los lejanos", bob.Humanoid.Health == 80 and carol.Humanoid.Health == 60)
check("Marea: daño con maestría (1 × daño × 1.2)", near(500 - health(w1), r2(D * 1.2)))
local healEvent = events("Heal", alice)[1]
check("Marea: el efecto dice a quién ha curado y cuánto", healEvent and #healEvent.Event.Healed == 2 and healEvent.Event.Healed[1].Amount == 35)
alice.Humanoid.Health = 95
advance(clock + 12)
AbilityService.perform(alice)
check("Marea: nunca por encima de la vida máxima", alice.Humanoid.Health == 100)
alice.Humanoid.Health = 100

-- Fuego: quemadura ---------------------------------------------------------------------
nextTurn()
choose("Fire", 10)
local f1 = newEnemy(6, 0, -8, 1000)
local f2 = newEnemy(7, 3, -10, 1000)
local behind = newEnemy(8, 0, 8, 1000)
local weak = newEnemy(9, -2, -6, 60)
local castAt = clock
check("Llamarada: se usa", (AbilityService.perform(alice)) == "Success")
local tick = r2(0.3 * D * 1.2)
check("Llamarada: golpe inicial en el cono", near(1000 - health(f1), 54.99) and near(1000 - health(f2), 54.99) and near(60 - health(weak), 54.99))
check("Llamarada: no alcanza a los de detrás", health(behind) == 1000)
check("Llamarada: marca de quemadura para los efectos", marks[6] and marks[6].Name == "Burn" and marks[6].Seconds == 4)
for step = 1, 12 do
	advance(castAt + step * 0.5)
	AbilityService.step(clock)
end
check("Quemadura: 8 tics de 0.3 × daño × maestría", near(1000 - health(f1), 54.99 + 8 * tick, 1e-4) and near(1000 - health(f2), 54.99 + 8 * tick, 1e-4))
check("Quemadura: remata y la muerte cuenta una sola vez", weak.Status.State == "Dead" and kills[9] == 1 and (payouts[1] or 0) >= 100)
check("Quemadura: un aviso por ciclo solo al dueño", #events("BurnTick", alice) == 8 and #events("BurnTick", bob) == 0)

-- Viento: velocidad ----------------------------------------------------------------------
nextTurn()
choose("Wind", 0)
local g1 = newEnemy(10, 0, -10, 1000)
local gustAt = clock
AbilityService.perform(alice)
check("Vendaval: daño delante (1.8 × daño)", near(1000 - health(g1), r2(1.8 * D)))
check("Vendaval: +35 % de velocidad", near(alice.Humanoid.WalkSpeed, 16 * 1.35))
advance(gustAt + 4.9)
check("Vendaval: sigue rápido a los 4.9 s", near(alice.Humanoid.WalkSpeed, 16 * 1.35))
advance(gustAt + 5)
check("Vendaval: vuelve a la velocidad normal a los 5 s", alice.Humanoid.WalkSpeed == 16)

-- Rayo: cadena ---------------------------------------------------------------------------
nextTurn()
choose("Lightning", 10)
newEnemy(11, 0, 10, 1000) -- detrás: no cuenta
local before = clock
code, _, readyAt = AbilityService.perform(alice)
check("Rayo sin nadie delante: no se gasta", code == "NoTarget" and readyAt <= before + SERVER)
local c1 = newEnemy(12, 0, -10, 1000)
local c2 = newEnemy(13, 6, -12, 1000)
local c3 = newEnemy(14, 12, -12, 1000)
local c4 = newEnemy(15, 18, -14, 1000)
local c5 = newEnemy(16, 24, -14, 1000)
local c6 = newEnemy(17, 60, -14, 1000)
code = AbilityService.perform(alice)
local first = r2(2.2 * D * 1.2)
check("Rayo: se usa justo después del intento sin objetivo", code == "Success")
check("Rayo: golpea al de delante con todo el daño", near(1000 - health(c1), first))
check("Rayo: salta cuatro veces, cada vez más débil", near(1000 - health(c2), r2(first * 0.8)) and near(1000 - health(c5), r2(r2(r2(r2(first * 0.8) * 0.8) * 0.8) * 0.8)) and health(c6) == 1000)
check("Rayo: aturde un instante", near(c1.Control.StunUntil, clock + 0.5) and near(c5.Control.StunUntil, clock + 0.5))
local chainEvent = events("Chain", alice)[1]
check("Rayo: el efecto lleva el recorrido (jugador + 5 enemigos)", chainEvent and #chainEvent.Event.Points == 6)

-- Hielo: ralentiza -----------------------------------------------------------------------
nextTurn()
choose("Ice", 0)
local i1 = newEnemy(18, 0, -5, 1000)
local i2 = newEnemy(19, 5, 5, 5000, "Boss")
AbilityService.perform(alice)
check("Escarcha: daño a tu alrededor", near(1000 - health(i1), r2(1.3 * D)) and near(5000 - health(i2), r2(1.3 * D)))
check("Escarcha: ralentiza a la mitad 4 s", i1.Control.SlowFactor == 0.5 and near(i1.Control.SlowUntil, clock + 4))
check("Escarcha: al jefe, a la mitad de fuerza", near(i2.Control.SlowFactor, 0.75))

-- Sombra: maldición ----------------------------------------------------------------------
nextTurn()
choose("Shadow", 0)
check("Maldición sin nadie delante: no se gasta", (AbilityService.perform(alice)) == "NoTarget")
local s1 = newEnemy(20, 0, -8, 1000)
local s2 = newEnemy(21, 4, -10, 1000)
local s3 = newEnemy(22, 30, -30, 1000)
check("Maldición: se usa", (AbilityService.perform(alice)) == "Success")
check("Maldición: el golpe no cuenta su propia marca", near(1000 - health(s1), r2(2.2 * D)))
check("Maldición: marca al objetivo y a los cercanos", near(s1.Control.VulnerableUntil, clock + 6) and near(s2.Control.VulnerableUntil, clock + 6) and s3.Control.VulnerableUntil == 0)
local dealt = EnemyService.damage(s2, bob, 100)
check("Maldición: los marcados reciben +30 % de daño (de cualquiera)", near(dealt, 130))

-- Celestial: lluvia estelar ---------------------------------------------------------------
nextTurn()
choose("Celestial", 0)
local st1 = newEnemy(23, 0, -9, 1000)
local st2 = newEnemy(24, 0, -40, 1000)
local starAt = clock
AbilityService.perform(alice)
local cast = events("StarfallCast", alice)[1]
check("Lluvia: aviso delante del jugador antes del daño", cast and near(cast.Event.Center.Z, -9) and health(st1) == 1000)
advance(starAt + 0.7)
check("Lluvia: primera oleada tras el aviso", near(1000 - health(st1), r2(1.7 * D)))
advance(starAt + 0.7 + 0.9 + 0.05)
check("Lluvia: tres oleadas", near(1000 - health(st1), 3 * r2(1.7 * D), 1e-4) and #events("StarfallWave", alice) == 3 and health(st2) == 1000)
advance(starAt + 15)
local hpBefore = health(st1)
AbilityService.perform(alice)
alice.CharacterRemoving:Fire() -- muere durante el aviso
advance(clock + 2)
check("Lluvia: morir durante el aviso anula las oleadas", health(st1) == hpBefore)

-- Recarga por elemento, recarga global, personaje y datos -----------------------------------
nextTurn()
choose("Fire", 0)
check("Fuego: se usa", (AbilityService.perform(alice)) == "Success")
choose("Ice", 0)
check("recarga global: otra habilidad justo después no sale", (AbilityService.perform(alice)) == "TooFast")
advance(clock + 0.6)
code, elementId = AbilityService.perform(alice)
check("cada elemento tiene su recarga: Hielo sale aunque Fuego esté recargando", code == "Success" and elementId == "Ice")
choose("Fire", 0)
code, elementId, readyAt = AbilityService.perform(alice)
check("volver a Fuego no reinicia su recarga", code == "Cooldown" and elementId == "Fire" and readyAt > clock + SERVER + 7)
alice.Humanoid.Health = 0
check("personaje muerto: no se usa", (AbilityService.perform(alice)) == "InvalidRequest")
alice.Humanoid.Health = 100
local dave = newPlayer("Dave", 4, Vector3.new(0, 3, 0))
check("sin datos: no se usa", (AbilityService.perform(dave)) == "NotReady")
profiles[alice].Ready = false
check("datos sin cargar del todo: habilidad de Naturaleza", AbilityService.elementOf(profiles[alice]) == "Nature")
check("datos sin cargar del todo: sin secundario", AbilityService.elementOf(profiles[alice], "Secondary") == nil)
profiles[alice].Ready = nil
check("hueco no válido", (AbilityService.perform(alice, "Tertiary")) == "InvalidRequest" and (AbilityService.perform(alice, 7)) == "InvalidRequest")

-- 5. Segundo elemento (CoreLogic) ---------------------------------------------------------
local d = CoreLogic.empty()
local T0 = 1700000000
check("secundario: bloqueado", (CoreLogic.selectSecondary(d, "Water", 1e9, T0)) == "Locked")
check("secundario: sin secundario no se puede mover el principal", (CoreLogic.selectSecondary(d, "Nature", 1e9, T0)) == "AlreadySelected")
d.Elements.Water.Unlocked = true
d.Elements.Fire.Unlocked = true
local switchCost = CoreLogic.switchCost()
local scode, scost = CoreLogic.selectSecondary(d, "Water", switchCost - 1, T0)
check("secundario: cuesta lo mismo que cambiar el principal", scode == "InsufficientDiamonds" and scost == switchCost and d.Secondary == nil)
scode, scost = CoreLogic.selectSecondary(d, "Water", 1e9, T0)
check("secundario: se elige", scode == "Success" and scost == switchCost and d.Secondary == "Water" and d.Selected == "Nature" and CoreLogic.secondaryOf(d) == "Water")
check("secundario: mismo enfriamiento que cambiar", (CoreLogic.selectSecondary(d, "Fire", 1e9, T0 + 5)) == "TooFast")
check("secundario: ya elegido", (CoreLogic.selectSecondary(d, "Water", 1e9, T0 + 20)) == "AlreadySelected")
scode = CoreLogic.selectSecondary(d, "Nature", 1e9, T0 + 20)
check("secundario: elegir el principal los intercambia", scode == "Success" and d.Selected == "Water" and d.Secondary == "Nature")
scode = CoreLogic.selectElement(d, "Nature", 1e9, T0 + 40)
check("principal: elegir el secundario los intercambia", scode == "Success" and d.Selected == "Nature" and d.Secondary == "Water")
scode = CoreLogic.selectElement(d, "Fire", 1e9, T0 + 60)
check("principal: un tercero no toca el secundario", scode == "Success" and d.Selected == "Fire" and d.Secondary == "Water")
local cleanD = CoreLogic.sanitize(d)
check("guardado: el secundario válido se conserva", cleanD.Secondary == "Water" and cleanD ~= d)
local badD = CoreLogic.sanitize({ Selected = "Fire", Secondary = "Fire", Elements = d.Elements })
check("guardado: secundario igual al principal se descarta", badD.Secondary == nil and CoreLogic.corrections({ Selected = "Fire", Secondary = "Fire", Elements = d.Elements }, badD) ~= nil)
check("guardado: secundario bloqueado o raro se descarta", CoreLogic.sanitize({ Secondary = "Celestial" }).Secondary == nil and CoreLogic.sanitize({ Secondary = 42 }).Secondary == nil)
check("partidas antiguas: sin secundario", CoreLogic.sanitize({ Selected = "Nature" }).Secondary == nil and CoreLogic.corrections({ Selected = "Nature" }, CoreLogic.sanitize({ Selected = "Nature" })) == nil)

-- 6. Combos (fórmulas) -------------------------------------------------------------------
check("combo en cualquier orden", AbilityLogic.reaction("Water", "Lightning") == "Electrocuted" and AbilityLogic.reaction("Lightning", "Water") == "Electrocuted")
check("sin combo: mismo elemento, sin marca o pareja sin reacción", AbilityLogic.reaction("Fire", "Fire") == nil and AbilityLogic.reaction(nil, "Fire") == nil and AbilityLogic.reaction("Shadow", "Fire") == nil)
check("Remolino: Viento sobre Agua/Fuego/Hielo/Rayo", AbilityLogic.reaction("Fire", "Wind") == "Swirl" and AbilityLogic.reaction("Ice", "Wind") == "Swirl" and AbilityLogic.reaction("Wind", "Fire") == nil and AbilityLogic.reaction("Shadow", "Wind") == nil)
check("el Viento no deja marca", not AbilityLogic.leavesAura("Wind") and AbilityLogic.leavesAura("Water") and not AbilityLogic.leavesAura("Plasma"))
local pairsSeen, pairsOk = {}, true
for id, reaction in AbilityConfig.Reactions do
	if reaction.Pair then
		local key = if reaction.Pair[1] < reaction.Pair[2] then reaction.Pair[1] .. "+" .. reaction.Pair[2] else reaction.Pair[2] .. "+" .. reaction.Pair[1]
		pairsOk = pairsOk and not pairsSeen[key] and AbilityLogic.get(reaction.Pair[1]) ~= nil and AbilityLogic.get(reaction.Pair[2]) ~= nil and reaction.Pair[1] ~= reaction.Pair[2]
		pairsSeen[key] = true
	end
	pairsOk = pairsOk and type(reaction.Name) == "string" and type(reaction.Color) == "table"
end
check("combos: parejas únicas y de elementos reales", pairsOk)
local everyone = true
for _, elementId in CoreConfig.Order do
	everyone = everyone and #AbilityLogic.partners(elementId) > 0
end
check("todos los elementos tienen al menos un combo", everyone)
check("texto de combos para el panel", AbilityLogic.partnersText("Lightning"):find("Electrocutado") ~= nil and AbilityLogic.partnersText("Wind"):find("Remolino") ~= nil)
local ac = EnemyLogic.newControl()
EnemyLogic.setAura(ac, "Water", 10, 6, 10)
check("marca: dura lo configurado", EnemyLogic.auraOf(ac, 15.9) == "Water" and EnemyLogic.auraOf(ac, 16) == nil)
EnemyLogic.setAura(ac, "Fire", 20, 60, 10)
check("marca: con tope de duración", ac.AuraUntil == 30)
EnemyLogic.setAura(ac, nil, 21)
check("marca: se quita", EnemyLogic.auraOf(ac, 21) == nil)
EnemyLogic.setAura(ac, "Ice", 22, 6, 10)
EnemyLogic.clearControl(ac)
check("marca: limpiar estados la quita", EnemyLogic.auraOf(ac, 22) == nil)

-- 7. Combos (servicio) --------------------------------------------------------------------
local function eventOf(kind, reactionId)
	for _, f in fired do
		if f.Remote == "AbilityEvent" and f.Player == alice and f.Event.Kind == kind and (reactionId == nil or f.Event.Reaction == reactionId) then
			return f.Event
		end
	end
	return nil
end
local function combo(slotElements, setup, cast)
	nextTurn()
	table.clear(knocks)
	choose(slotElements[1], 0)
	local enemies = setup()
	cast()
	return enemies
end

-- Electrocutado con los dos huecos: Agua (Q) moja, Rayo (R) electrocuta.
nextTurn()
table.clear(knocks)
cores.Secondary = nil
choose("Water", 0)
check("sin secundario: la R no hace nada", (AbilityService.perform(alice, "Secondary")) == "Locked")
cores.Elements.Lightning.Unlocked = true
cores.Elements.Lightning.Level = 0
cores.Secondary = "Lightning"
check("secundario de los datos -> hueco R", AbilityService.elementOf(profiles[alice], "Secondary") == "Lightning")
local wet = newEnemy(30, 0, -6, 2000)
local wetBuddy = newEnemy(31, 4, -6, 2000)
code, elementId = AbilityService.perform(alice, "Primary")
check("Q: Agua", code == "Success" and elementId == "Water")
check("Agua deja la marca mojada", EnemyService.auraOf(wet) == "Water" and EnemyService.auraOf(wetBuddy) == "Water")
check("la ola aparta a los enemigos normales", knocks[30] == 22)
EnemyService.setAura(wetBuddy, nil) -- solo uno mojado: un único combo
local before1, before2 = health(wet), health(wetBuddy)
advance(clock + 0.6)
code, elementId = AbilityService.perform(alice, "Secondary")
check("R: Rayo", code == "Success" and elementId == "Lightning")
local first = r2(2.2 * D)
local burstE = r2(0.8 * D)
check("¡Electrocutado!: el rayo pega ×1.5 (más la descarga)", near(before1 - health(wet), first * 1.5 + burstE, 1e-3))
check("¡Electrocutado!: la descarga alcanza al de al lado (sin encadenar combos)", near(before2 - health(wetBuddy), r2(first * 0.8) + burstE, 1e-3) and EnemyService.auraOf(wetBuddy) == "Lightning")
check("¡Electrocutado!: aturde 1.2 s y consume la marca", near(wet.Control.StunUntil, clock + 1.2) and EnemyService.auraOf(wet) == nil)
local reactionEvent = eventOf("Reaction", "Electrocuted")
check("¡Electrocutado!: aviso del combo con sus impactos", reactionEvent ~= nil and #reactionEvent.Hits >= 2)
local chainEv = eventOf("Chain")
local tagged = false
for _, h in (chainEv and chainEv.Hits or {}) do
	tagged = tagged or h.Reaction == "Electrocuted"
end
check("los impactos del combo llevan su nombre para el cliente", tagged)

-- Vapor: Fuego marca, Agua explota (y aparta). La explosión no dispara más combos.
nextTurn()
table.clear(knocks)
cores.Secondary = nil
choose("Water", 0)
local v1 = newEnemy(32, 0, -5, 2000)
local v2 = newEnemy(33, 3, -5, 2000)
EnemyService.setAura(v1, "Fire", 6)
EnemyService.setAura(v2, "Ice", 6)
local hv1, hv2 = health(v1), health(v2)
AbilityService.perform(alice)
local wave = r2(D)
check("¡Vapor!: explosión de 2 × daño alrededor", near(hv1 - health(v1), wave + r2(2 * D), 1e-3))
check("¡Congelado! en el de al lado (Agua sobre Hielo) y la explosión no encadena", eventOf("Reaction", "Frozen") ~= nil and near(v2.Control.StunUntil, clock + 2.5))
check("Vapor aparta", knocks[32] ~= nil)

-- Derretir: Fuego sobre Hielo pega el doble.
nextTurn()
choose("Fire", 0)
local m1 = newEnemy(34, 0, -8, 3000)
EnemyService.setAura(m1, "Ice", 6)
AbilityService.perform(alice)
check("¡Derretir!: golpe de fuego ×2", near(3000 - health(m1), r2(1.3 * D) * 2, 1e-3))

-- Incendio: Fuego sobre Naturaleza esparce una quemadura doble.
nextTurn()
choose("Fire", 0)
local w1 = newEnemy(35, 0, -8, 3000)
local w2 = newEnemy(36, 6, -8, 3000)
EnemyService.setAura(w1, "Nature", 6)
local castW = clock
AbilityService.perform(alice)
local hw2 = health(w2)
for step = 1, 10 do
	advance(castW + step * 0.5)
	AbilityService.step(clock)
end
check("¡Incendio!: el de al lado arde con quemadura doble", near(hw2 - health(w2), 8 * r2(0.6 * D), 1e-3) and eventOf("Reaction", "Wildfire") ~= nil)

-- Superconductor: Rayo sobre Hielo rompe la defensa.
nextTurn()
choose("Lightning", 0)
local sc1 = newEnemy(37, 0, -8, 3000)
EnemyService.setAura(sc1, "Ice", 6)
AbilityService.perform(alice)
check("¡Superconductor!: +40 % de daño recibido 6 s", sc1.Control.VulnerableBonus == 0.4 and near(sc1.Control.VulnerableUntil, clock + 6))

-- Florecer: Agua sobre Naturaleza cura y enraíza.
nextTurn()
choose("Water", 0)
alice.Humanoid.Health = 30
local b1 = newEnemy(38, 0, -5, 3000)
EnemyService.setAura(b1, "Nature", 6)
AbilityService.perform(alice)
check("¡Florecer!: cura un 25 % extra", alice.Humanoid.Health == 30 + 35 + 25)
check("¡Florecer!: enraíza 3 s", near(b1.Control.RootUntil, clock + 3))
alice.Humanoid.Health = 100

-- Eclipse: Celestial sobre Sombra.
nextTurn()
choose("Celestial", 0)
local ec = newEnemy(39, 0, -9, 5000)
EnemyService.setAura(ec, "Shadow", 6)
local starAt2 = clock
AbilityService.perform(alice)
advance(starAt2 + 0.75)
check("¡Eclipse!: estalla con la primera oleada (3 × daño)", near(5000 - health(ec), r2(1.7 * D) + r2(3 * D), 1e-3) and eventOf("Reaction", "Eclipse") ~= nil)

-- Remolino: el Viento esparce el fuego a los de alrededor.
nextTurn()
table.clear(knocks)
choose("Wind", 0)
local sw1 = newEnemy(40, 0, -8, 3000)
local sw2 = newEnemy(41, 7, -12, 3000, "Boss")
EnemyService.setAura(sw1, "Fire", 6)
AbilityService.perform(alice)
check("¡Remolino!: esparce la marca de fuego y la quemadura", EnemyService.auraOf(sw2) == "Fire" and marks[41] and marks[41].Name == "Burn")
check("el Viento no deja su marca", EnemyService.auraOf(sw1) == nil or EnemyService.auraOf(sw1) == "Fire")
check("a los jefes no se les empuja", knocks[41] == nil)

-- Mismo elemento: renueva la marca sin combo.
nextTurn()
choose("Ice", 0)
local same = newEnemy(42, 0, -5, 3000)
EnemyService.setAura(same, "Ice", 1)
AbilityService.perform(alice)
check("mismo elemento: renueva la marca, sin combo", EnemyService.auraOf(same) == "Ice" and near(same.Control.AuraUntil, clock + 6) and eventOf("Reaction") == nil)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
