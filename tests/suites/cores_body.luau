-- Pruebas unitarias de CoreLogic (los ocho núcleos), con CoreConfig, Economy y
-- EconomyConfig reales de src/. Lógica pura: sin servicios ni DataStores.

CoreLogic.init(CoreConfig, Economy, EconomyConfig)

local failures = 0
local function check(name, ok)
	if not ok then failures += 1 end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local function info(text)
	print("INFO   " .. text)
end
local function deep(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in value do out[k] = deep(v) end
	return out
end
-- Igualdad ESTRICTA (sin excepciones para NaN: NaN ~= NaN también aquí).
local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in a do if not same(v, b[k]) then return false end end
	for k in b do if a[k] == nil then return false end end
	return true
end
local function finite(x) return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge end
-- Recorre una tabla y devuelve la ruta del primer número no finito (o nil si no hay).
local function nonFinitePath(value, path)
	if type(value) == "number" then return if finite(value) then nil else path end
	if type(value) ~= "table" then return nil end
	for k, v in value do
		if type(k) == "number" and not finite(k) then return path .. "[clave no finita]" end
		local found = nonFinitePath(v, path .. "." .. tostring(k))
		if found then return found end
	end
	return nil
end
local ORDER = { "Nature", "Water", "Fire", "Wind", "Lightning", "Ice", "Shadow", "Celestial" }
local NOW = 1760000000
local up = CoreConfig.Upgrade
local NAN, INF = 0 / 0, math.huge

print("-- 1. Los ocho elementos y su orden")
check("la configuración real es válida", (CoreLogic.validateConfig(CoreConfig, EconomyConfig)))
check("ocho elementos en el orden aprobado", #CoreConfig.Order == 8 and table.concat(CoreConfig.Order, ",") == table.concat(ORDER, ","))
local named = true
for _, id in ORDER do
	if type(CoreConfig.Elements[id]) ~= "table" or type(CoreConfig.Elements[id].DisplayName) ~= "string" then named = false end
end
check("cada elemento tiene su definición y nombre visible", named)
check("indexOf respeta el orden (Nature 1, Celestial 8; desconocidos y tipos raros nil)", CoreLogic.indexOf("Nature") == 1 and CoreLogic.indexOf("Celestial") == 8 and CoreLogic.indexOf("Poison") == nil and CoreLogic.indexOf(5) == nil and CoreLogic.indexOf(nil) == nil)

print("-- 2. Naturaleza desbloqueada por defecto y selección válida")
local data = CoreLogic.empty()
check("Naturaleza desbloqueada y seleccionada", CoreLogic.isUnlocked(data, "Nature") and data.Selected == "Nature")
local othersLocked = true
for index = 2, 8 do
	if CoreLogic.isUnlocked(data, ORDER[index]) then othersLocked = false end
end
check("los otros siete empiezan bloqueados", othersLocked)
check("Naturaleza NO guarda nivel propio (es UpgradeLevels.GeneratorPower)", data.Elements.Nature.Level == nil)
check("su nivel se lee de UpgradeLevels", CoreLogic.level(data, { GeneratorPower = 7 }, "Nature") == 7 and CoreLogic.level(data, nil, "Nature") == 0)

print("-- 3. Desbloqueo: costes crecientes y orden secuencial obligatorio")
local costs, increasing = {}, true
for index = 2, 8 do
	costs[index] = CoreLogic.unlockCost(ORDER[index])
	if index > 2 and not (costs[index] > costs[index - 1]) then increasing = false end
end
check(("costes estrictamente crecientes: %s"):format(table.concat(costs, ", ", 2, 8)), increasing and costs[2] > 0)
check("siguen la fórmula configurada (BaseCost · Growth^(k-2))", costs[2] == CoreConfig.Unlock.BaseCost and costs[8] == math.floor(CoreConfig.Unlock.BaseCost * CoreConfig.Unlock.Growth ^ 6))
check("Naturaleza y desconocidos no tienen coste de desbloqueo", CoreLogic.unlockCost("Nature") == nil and CoreLogic.unlockCost("Poison") == nil)
check("el desbloqueo secuencial está activado explícitamente en la configuración", CoreConfig.Unlock.Sequential == true)
-- Desde el inicio, ningún núcleo salvo Agua se puede desbloquear (aunque sobre energía).
local outOfOrder = true
for index = 3, 8 do
	local fresh = CoreLogic.empty()
	local code = CoreLogic.unlock(fresh, ORDER[index], 1e15, NOW)
	if code ~= "Locked" or CoreLogic.isUnlocked(fresh, ORDER[index]) then outOfOrder = false end
end
check("desde el inicio, Fuego..Celestial se rechazan (Locked) aunque sobre energía", outOfOrder)
-- Saltarse uno en mitad de la cadena
local chain = CoreLogic.empty()
CoreLogic.unlock(chain, "Water", 1e15, NOW)
check("con Agua: saltar a Viento (sin Fuego) -> Locked", CoreLogic.unlock(chain, "Wind", 1e15, NOW) == "Locked" and not CoreLogic.isUnlocked(chain, "Wind"))
-- Datos guardados incoherentes: un núcleo intermedio desbloqueado sin sus anteriores
local gap = CoreLogic.sanitize({ Elements = { Lightning = { Unlocked = true } } })
check("datos con un hueco (Rayo sin Agua/Fuego/Viento): Hielo exige TODOS los anteriores -> Locked", CoreLogic.unlock(gap, "Ice", 1e15, NOW) == "Locked" and CoreLogic.unlock(gap, "Fire", 1e15, NOW) == "Locked")
check("y el siguiente válido sigue siendo Agua", CoreLogic.unlock(gap, "Water", 1e15, NOW) == "Success")
-- En orden, los ocho
local all = CoreLogic.empty()
local spent, inOrder = 0, true
for index = 2, 8 do
	local code, cost = CoreLogic.unlock(all, ORDER[index], 1e15, NOW + index)
	spent += cost
	if code ~= "Success" or all.Elements[ORDER[index]].UnlockedAt ~= NOW + index then inOrder = false end
end
check(("en orden se desbloquean los ocho (coste total %d)"):format(spent), inOrder and spent == (function() local s = 0 for i = 2, 8 do s += costs[i] end return s end)())
check("desbloquear dos veces -> AlreadyUnlocked; Naturaleza también", CoreLogic.unlock(all, "Water", 1e15, NOW) == "AlreadyUnlocked" and CoreLogic.unlock(all, "Nature", 1e15, NOW) == "AlreadyUnlocked")

print("-- 4. Costes y producción por nivel (Naturaleza = Economy, sin cambios)")
local natureCostOK, natureProdOK = true, true
for level = 0, 50 do
	if CoreLogic.upgradeCost("Nature", level) ~= (if level < 50 then Economy.getUpgradeCost("GeneratorPower", level) else nil) then natureCostOK = false end
	local pd = CoreLogic.empty()
	if CoreLogic.coreProduction(pd, { GeneratorPower = level }, "Nature") ~= Economy.getProductionPerSecond({ GeneratorPower = level }) then natureProdOK = false end
end
check("coste de Naturaleza = Economy.getUpgradeCost en los niveles 0..49; nil en el 50", natureCostOK)
check("producción de Naturaleza = Economy.getProductionPerSecond en los niveles 0..50", natureProdOK)
check("coste de Fuego nivel 3 = BaseUpgradeCost · Tier² · Growth³", CoreLogic.upgradeCost("Fire", 3) == math.floor(up.BaseUpgradeCost * up.TierMultiplier ^ 2 * up.CostGrowth ^ 3))
local growing = true
for level = 1, up.MaxLevel - 1 do
	if not (CoreLogic.upgradeCost("Water", level) > CoreLogic.upgradeCost("Water", level - 1)) then growing = false end
end
check("el coste de mejora crece con el nivel y se detiene en MaxLevel", growing and CoreLogic.upgradeCost("Water", up.MaxLevel) == nil)
check("niveles no válidos (negativo, NaN, infinito, texto) no tienen coste", CoreLogic.upgradeCost("Water", -1) == nil and CoreLogic.upgradeCost("Water", NAN) == nil and CoreLogic.upgradeCost("Water", INF) == nil and CoreLogic.upgradeCost("Water", "3") == nil)
local pw = CoreLogic.empty()
pw.Elements.Water.Unlocked = true
pw.Elements.Water.Level = 4
check("producción de Agua nivel 4 = Base · Tier · (1 + 4)", CoreLogic.coreProduction(pw, {}, "Water") == up.BaseProduction * up.TierMultiplier * 5)

print("-- 5. Producción total solo de núcleos desbloqueados")
local td = CoreLogic.empty()
td.Elements.Fire.Level = 10 -- nivel en un núcleo BLOQUEADO
check("un núcleo bloqueado no produce aunque tenga nivel", CoreLogic.coreProduction(td, {}, "Fire") == 0)
local levels = { GeneratorPower = 3 }
check("solo Naturaleza: producción base = la actual (1 + 3 = 4)", CoreLogic.baseProduction(td, levels) == 4)
td.Elements.Water.Unlocked = true
td.Elements.Water.Level = 2
local expected = 4 + up.BaseProduction * up.TierMultiplier * 3
check(("Naturaleza + Agua: %s ⚡/s"):format(tostring(expected)), CoreLogic.baseProduction(td, levels) == expected)

print("-- 6. Multiplicador de mascotas aplicado exactamente una vez")
check("total = (Σ base) · mascotas", math.abs(CoreLogic.totalProduction(td, levels, 1.35) - expected * 1.35) < 1e-9)
check("no se multiplica por núcleo: con 2 núcleos sigue siendo ×1,35 y no ×1,35²", math.abs(CoreLogic.totalProduction(td, levels, 1.35) / CoreLogic.baseProduction(td, levels) - 1.35) < 1e-12)
check("compatibilidad: con solo Naturaleza = producción actual del juego (Economy · mascotas)", CoreLogic.totalProduction(CoreLogic.empty(), levels, 1.35) == Economy.getProductionPerSecond(levels) * 1.35)
check("multiplicador no válido (NaN, infinito, negativo, texto) -> 1", CoreLogic.totalProduction(td, levels, NAN) == expected and CoreLogic.totalProduction(td, levels, INF) == expected and CoreLogic.totalProduction(td, levels, -2) == expected and CoreLogic.totalProduction(td, levels, "x") == expected)

print("-- 7. Selección de elemento")
local sd = CoreLogic.empty()
local code, cost = CoreLogic.selectElement(sd, {}, "Fire", 1e9, NOW)
check("seleccionar un núcleo bloqueado -> Locked y no cambia nada", code == "Locked" and cost == 0 and sd.Selected == "Nature")
check("elemento inexistente o de otro tipo -> InvalidRequest", CoreLogic.selectElement(sd, {}, "Poison", 1e9, NOW) == "InvalidRequest" and CoreLogic.selectElement(sd, {}, {}, 1e9, NOW) == "InvalidRequest")
check("seleccionar el ya seleccionado -> AlreadySelected", CoreLogic.selectElement(sd, {}, "Nature", 1e9, NOW) == "AlreadySelected")
CoreLogic.unlock(sd, "Water", 1e9, NOW)
local switchCost = CoreLogic.switchCost(sd, { GeneratorPower = 10 })
local baseSD = CoreLogic.baseProduction(sd, { GeneratorPower = 10 })
check(("coste de cambio = max(%d, 60 s de producción base %s) = %d"):format(CoreConfig.Switch.MinCost, tostring(baseSD), switchCost), switchCost == math.max(CoreConfig.Switch.MinCost, math.floor(CoreConfig.Switch.ProductionSeconds * baseSD)))
check("tiempo no válido (NaN, 0, negativo) -> InvalidRequest", CoreLogic.selectElement(sd, {}, "Water", 1e9, NAN) == "InvalidRequest" and CoreLogic.selectElement(sd, {}, "Water", 1e9, 0) == "InvalidRequest" and CoreLogic.selectElement(sd, {}, "Water", 1e9, -5) == "InvalidRequest")
code, cost = CoreLogic.selectElement(sd, { GeneratorPower = 10 }, "Water", switchCost - 1, NOW)
check("sin energía suficiente -> InsufficientEnergy, sin cambiar", code == "InsufficientEnergy" and sd.Selected == "Nature")
check("energía infinita o NaN no cuenta como suficiente", CoreLogic.selectElement(sd, {}, "Water", INF, NOW) == "InsufficientEnergy" and CoreLogic.selectElement(sd, {}, "Water", NAN, NOW) == "InsufficientEnergy")
code, cost = CoreLogic.selectElement(sd, { GeneratorPower = 10 }, "Water", 1e9, NOW)
check("cambiar a un núcleo desbloqueado -> Success y devuelve el coste", code == "Success" and cost == switchCost and sd.Selected == "Water" and sd.LastSwitchAt == NOW)
check("otra vez antes del enfriamiento -> TooFast", CoreLogic.selectElement(sd, {}, "Nature", 1e9, NOW + CoreConfig.Switch.CooldownSeconds - 1) == "TooFast" and sd.Selected == "Water")
check("tras el enfriamiento se puede cambiar", CoreLogic.selectElement(sd, {}, "Nature", 1e9, NOW + CoreConfig.Switch.CooldownSeconds) == "Success")
local ud = CoreLogic.empty()
check("desbloquear con tiempo o energía no válidos -> rechazado sin cambios", CoreLogic.unlock(ud, "Water", 1e9, NAN) == "InvalidRequest" and CoreLogic.unlock(ud, "Water", INF, NOW) == "InsufficientEnergy" and CoreLogic.unlock(ud, "Water", -1, NOW) == "InsufficientEnergy" and CoreLogic.unlock(ud, "Water", "999999", NOW) == "InsufficientEnergy" and not CoreLogic.isUnlocked(ud, "Water"))

print("-- 8. sanitize: valores malformados, campos desconocidos y entrada intacta")
check("sin datos (partida antigua: nil) -> estructura por defecto", same(CoreLogic.sanitize(nil), CoreLogic.empty()))
check("tipos raros (número, texto, booleano) -> estructura por defecto", same(CoreLogic.sanitize(42), CoreLogic.empty()) and same(CoreLogic.sanitize("texto"), CoreLogic.empty()) and same(CoreLogic.sanitize(true), CoreLogic.empty()))
-- Matriz: cada valor malformado en cada campo numérico/booleano conocido
local BAD = { NAN, INF, -INF, -5, "5", true, {}, 1e308 }
local matrixOK, matrixFail = true, ""
for _, bad in BAD do
	local clean = CoreLogic.sanitize({
		Selected = bad,
		LastSwitchAt = bad,
		Elements = { Water = { Unlocked = bad, Level = bad, Mastery = bad, UnlockedAt = bad }, Nature = { Mastery = bad } },
	})
	local water = clean.Elements.Water
	local okLevel = water.Level == 0 or (bad == 1e308 and water.Level == up.MaxLevel)
	local okMastery = water.Mastery == 0 or (bad == 1e308 and water.Mastery == CoreConfig.MaxMastery)
	local ok = clean.Selected == "Nature" and clean.LastSwitchAt == 0 and water.Unlocked == (bad == true) and okLevel and okMastery
		and water.UnlockedAt == 0 and finite(clean.Elements.Nature.Mastery) and nonFinitePath(clean, "Cores") == nil
	if not ok then matrixOK = false matrixFail = matrixFail .. " " .. tostring(bad) end
end
check("NaN, ±infinito, negativo, texto, booleano, tabla y 1e308 en cada campo -> valores seguros" .. matrixFail, matrixOK)
-- Datos con mezcla de todo
local raw = {
	Selected = "Fire", -- seleccionado pero BLOQUEADO
	LastSwitchAt = -50,
	FutureField = { a = 1, b = "texto", bad = NAN, worse = INF, fn = print },
	BrokenField = NAN,
	Elements = {
		Nature = { Unlocked = false, Level = 99, Mastery = 12, Extra = "x", ExtraNaN = NAN },
		Water = { Unlocked = true, Level = 999, Mastery = -3, UnlockedAt = NAN, Skin = "azul" },
		Fire = { Unlocked = "sí", Level = 5 },
		Wind = "roto",
		Poison = { Unlocked = true, Level = 3, Bad = -INF },
	},
}
-- Copia ESTRICTA de la entrada sin NaN (los campos NaN se comprueban aparte, uno a uno).
local rawWithoutNaN = deep(raw)
rawWithoutNaN.FutureField.bad = nil
rawWithoutNaN.BrokenField = nil
rawWithoutNaN.Elements.Nature.ExtraNaN = nil
rawWithoutNaN.Elements.Water.UnlockedAt = nil
local tablesBefore = { raw.FutureField, raw.Elements, raw.Elements.Water, raw.Elements.Poison }
local clean = CoreLogic.sanitize(raw)
local rawCompare = deep(raw)
rawCompare.FutureField.bad = nil
rawCompare.BrokenField = nil
rawCompare.Elements.Nature.ExtraNaN = nil
rawCompare.Elements.Water.UnlockedAt = nil
check("la entrada no se modifica: igualdad estricta de todos sus campos no-NaN", same(rawCompare, rawWithoutNaN))
check("y sus campos NaN siguen siendo NaN (no se han escrito)", raw.FutureField.bad ~= raw.FutureField.bad and raw.BrokenField ~= raw.BrokenField and raw.Elements.Nature.ExtraNaN ~= raw.Elements.Nature.ExtraNaN and raw.Elements.Water.UnlockedAt ~= raw.Elements.Water.UnlockedAt)
check("las tablas de la entrada son las mismas (no se reemplazan)", raw.FutureField == tablesBefore[1] and raw.Elements == tablesBefore[2] and raw.Elements.Water == tablesBefore[3] and raw.Elements.Poison == tablesBefore[4])
check("la salida no comparte tablas con la entrada", clean.FutureField ~= raw.FutureField and clean.Elements ~= raw.Elements and clean.Elements.Poison ~= raw.Elements.Poison)
local path = nonFinitePath(clean, "Cores")
check("la salida no contiene NINGÚN número no finito" .. (if path then " (encontrado en " .. path .. ")" else ""), path == nil)
check("selección en un núcleo bloqueado -> vuelve a Naturaleza; tiempo negativo -> 0", clean.Selected == "Nature" and clean.LastSwitchAt == 0)
check("Naturaleza siempre desbloqueada; su 'Level' (99) se conserva como dato desconocido sin usarlo", clean.Elements.Nature.Unlocked == true and clean.Elements.Nature.Level == 99 and CoreLogic.level(clean, { GeneratorPower = 2 }, "Nature") == 2)
check("nivel 999 -> MaxLevel; maestría negativa -> 0; UnlockedAt NaN -> 0", clean.Elements.Water.Level == up.MaxLevel and clean.Elements.Water.Mastery == 0 and clean.Elements.Water.UnlockedAt == 0)
check("'Unlocked' que no es true -> bloqueado (conserva su nivel válido 5)", clean.Elements.Fire.Unlocked == false and clean.Elements.Fire.Level == 5)
check("elemento con datos rotos -> valores por defecto", type(clean.Elements.Wind) == "table" and clean.Elements.Wind.Unlocked == false and clean.Elements.Wind.Level == 0)
check("se conservan los campos desconocidos VÁLIDOS (texto, número, tabla)", clean.FutureField.a == 1 and clean.FutureField.b == "texto" and clean.Elements.Nature.Extra == "x" and clean.Elements.Water.Skin == "azul" and clean.Elements.Poison.Level == 3)
check("se descartan los desconocidos NO válidos (NaN, infinito, funciones)", clean.FutureField.bad == nil and clean.FutureField.worse == nil and clean.FutureField.fn == nil and clean.BrokenField == nil and clean.Elements.Nature.ExtraNaN == nil and clean.Elements.Poison.Bad == nil)
check("un elemento desconocido no produce ni se puede seleccionar", CoreLogic.coreProduction(clean, {}, "Poison") == 0 and not CoreLogic.isUnlocked(clean, "Poison"))
check("sanear dos veces da exactamente lo mismo (idempotente, igualdad estricta)", same(CoreLogic.sanitize(clean), clean))
local valid = CoreLogic.sanitize({ Selected = "Water", Elements = { Water = { Unlocked = true, Level = 3.7 } } })
check("una selección válida se respeta y los niveles se truncan a entero (3,7 -> 3)", valid.Selected == "Water" and valid.Elements.Water.Level == 3)
-- Datos SIN sanear que llegan a las funciones de cálculo (defensa en profundidad)
local rough = CoreLogic.empty()
rough.Elements.Water.Unlocked = true
rough.Elements.Water.Level = -7
check("nivel negativo sin sanear no produce energía negativa", CoreLogic.coreProduction(rough, {}, "Water") == up.BaseProduction * up.TierMultiplier)
local natureOK = true
for _, badLevel in { NAN, INF, -INF, -3, "7", 1e9 } do
	local value = CoreLogic.coreProduction(CoreLogic.empty(), { GeneratorPower = badLevel }, "Nature")
	-- Lo no válido cuenta como nivel 0; un nivel enorme pero válido se acota al máximo.
	local clamped = if badLevel == 1e9 then EconomyConfig.Upgrades.GeneratorPower.MaxLevel else 0
	if not finite(value) or value ~= Economy.getProductionPerSecond({ GeneratorPower = clamped }) then natureOK = false end
end
check("GeneratorPower mal formado (NaN, ±inf, negativo, texto, 1e9) -> producción finita y acotada", natureOK)
-- Errores encontrados en la revisión final (cada uno falló antes de corregirse):
local allUnlocked = CoreLogic.empty()
for index = 2, 8 do allUnlocked.Elements[ORDER[index]].Unlocked = true end
check("multiplicador de mascotas enorme pero finito (1e308) -> ×1, sin desbordar a infinito", CoreLogic.totalProduction(allUnlocked, { GeneratorPower = 50 }, 1e308) == CoreLogic.baseProduction(allUnlocked, { GeneratorPower = 50 }) and finite((CoreLogic.offlineReward(allUnlocked, { GeneratorPower = 50 }, 1e308, NOW - 600, NOW))))
check("multiplicador justo en el tope (MaxPetMultiplier) se respeta", CoreLogic.totalProduction(CoreLogic.empty(), {}, CoreConfig.MaxPetMultiplier) == CoreConfig.MaxPetMultiplier)
local roughSwitch = CoreLogic.empty()
roughSwitch.Elements.Water.Unlocked = true
roughSwitch.LastSwitchAt = "ayer"
local okSwitch, switchCode = pcall(CoreLogic.selectElement, roughSwitch, {}, "Water", 1e9, NOW)
check("selectElement con LastSwitchAt sin sanear (texto) -> sin error, se trata como 0", okSwitch and switchCode == "Success")
local noErrors = true
for _, bad in { {}, "texto", 42 } do
	for _, fn in {
		function() return CoreLogic.isUnlocked(bad, "Water") end,
		function() return CoreLogic.baseProduction(bad, {}) end,
		function() return CoreLogic.unlock(bad, "Water", 1e9, NOW) end,
		function() return CoreLogic.selectElement(bad, {}, "Water", 1e9, NOW) end,
		function() return CoreLogic.offlineReward(bad, {}, 1, NOW - 60, NOW) end,
	} do
		local ok, value = pcall(fn)
		if not ok or (type(value) == "number" and value ~= 0) then noErrors = false end
	end
end
check("datos sin tabla Elements o que no son tabla -> sin errores, nada desbloqueado y producción 0", noErrors)
local partial = { Elements = { Nature = { Unlocked = true } } } -- sin sanear: falta la entrada de Agua
local okPartial, partialCode = pcall(CoreLogic.unlock, partial, "Water", 1e9, NOW)
check("unlock con la entrada del núcleo ausente -> InvalidRequest, sin error ni cambios", okPartial and partialCode == "InvalidRequest" and partial.Elements.Water == nil)
-- Auditoría de robustez: unlock y selectElement con estructuras no válidas. Cada llamada
-- va en pcall; debe devolver un código de rechazo y dejar los datos exactamente igual.
local function rejects(fn, d, expectedCode)
	local before = deep(d)
	local ok, code, cost = pcall(fn, d)
	-- InsufficientEnergy informa del coste; los demás rechazos devuelven coste 0.
	local costOK = if expectedCode == "InsufficientEnergy" then type(cost) == "number" else cost == 0
	return ok and code == expectedCode and costOK and same(d, before), (if ok then tostring(code) else "ERROR: " .. tostring(code))
end
local STRUCTURES = {
	-- { nombre, constructor, código de unlock, código de selectElement }
	{ "nil", function() return nil end, "InvalidRequest", "InvalidRequest" },
	{ "{}", function() return {} end, "InvalidRequest", "InvalidRequest" },
	{ "{Elements = nil}", function() return { Selected = "Nature", Elements = nil } end, "InvalidRequest", "InvalidRequest" },
	{ "{Elements = 'roto'}", function() return { Elements = "roto" } end, "InvalidRequest", "InvalidRequest" },
	{ "{Elements = {}}", function() return { Elements = {} } end, "InvalidRequest", "Locked" },
	{ "sin la entrada pedida", function() return { Selected = "Nature", Elements = { Nature = { Unlocked = true }, Water = { Unlocked = true } } } end, "InvalidRequest", "Locked" },
	{ "entrada que no es tabla", function() return { Selected = "Nature", Elements = { Nature = { Unlocked = true }, Water = { Unlocked = true }, Fire = "roto" } } end, "InvalidRequest", "Locked" },
}
local structuresOK, structuresFail = true, ""
for _, case in STRUCTURES do
	local name, make, unlockCode, selectCode = case[1], case[2], case[3], case[4]
	-- "sin la entrada pedida" y "entrada que no es tabla" piden Fuego (su entrada falta o está rota).
	local targets = if name == "sin la entrada pedida" or name == "entrada que no es tabla" then { "Fire" } else { "Nature", "Water", "Fire" }
	for _, target in targets do
		local expectedUnlock = unlockCode
		local okU, gotU = rejects(function(d) return CoreLogic.unlock(d, target, 1e15, NOW) end, make(), expectedUnlock)
		local expectedSelect = if target == "Nature" and selectCode == "Locked" then "Locked" else selectCode
		local okS, gotS = rejects(function(d) return CoreLogic.selectElement(d, {}, target, 1e15, NOW) end, make(), expectedSelect)
		if not okU then structuresOK = false structuresFail ..= (" unlock(%s,%s)=%s"):format(name, target, gotU) end
		if not okS then structuresOK = false structuresFail ..= (" select(%s,%s)=%s"):format(name, target, gotS) end
	end
end
check("unlock/selectElement con nil, {}, Elements nil/texto/{} o entrada ausente -> rechazo coherente, sin error ni cambios" .. structuresFail, structuresOK)
-- Con el desbloqueo NO secuencial no hay comprobación de anteriores que pare antes: la
-- estructura debe validarse igualmente.
local looseConfig = deep(CoreConfig)
looseConfig.Unlock.Sequential = false
CoreLogic.init(looseConfig, Economy, EconomyConfig)
local looseOK = true
for _, case in STRUCTURES do
	-- Se pide Fuego: en todos los casos su entrada falta, está rota o no hay estructura.
	if not (rejects(function(d) return CoreLogic.unlock(d, "Fire", 1e15, NOW) end, case[2](), "InvalidRequest")) then looseOK = false end
end
CoreLogic.init(CoreConfig, Economy, EconomyConfig) -- se restaura la configuración real
check("con Sequential = false, las mismas estructuras no válidas se rechazan sin error", looseOK)
-- Entradas no válidas sobre datos VÁLIDOS: nunca cambios parciales.
local BAD_ENERGY = { NAN, INF, -INF, -1, "1e9", false, {} }
local BAD_TIME = { NAN, INF, -INF, 0, -5, "x", false, 1e11 }
local BAD_ELEMENT = { "Poison", "", 5, {}, false, NAN }
local base = CoreLogic.empty()
base.Elements.Water.Unlocked = true
base.Elements.Water.Level = 3
base.LastSwitchAt = NOW - 1000
local noPartial, partialFail = true, ""
local function expectReject(label, fn, expectedCode, source)
	local d = deep(source or base)
	if not rejects(fn, d, expectedCode) then noPartial = false partialFail ..= " " .. label end
end
for i, energy in BAD_ENERGY do
	expectReject("unlock-energía" .. i, function(d) return CoreLogic.unlock(d, "Fire", energy, NOW) end, "InsufficientEnergy")
	expectReject("select-energía" .. i, function(d) return CoreLogic.selectElement(d, { GeneratorPower = 5 }, "Water", energy, NOW) end, "InsufficientEnergy")
end
expectReject("unlock-energía-nil", function(d) return CoreLogic.unlock(d, "Fire", nil, NOW) end, "InsufficientEnergy")
expectReject("select-energía-nil", function(d) return CoreLogic.selectElement(d, {}, "Water", nil, NOW) end, "InsufficientEnergy")
for i, time in BAD_TIME do
	expectReject("unlock-tiempo" .. i, function(d) return CoreLogic.unlock(d, "Fire", 1e15, time) end, "InvalidRequest")
	expectReject("select-tiempo" .. i, function(d) return CoreLogic.selectElement(d, {}, "Water", 1e15, time) end, "InvalidRequest")
end
expectReject("unlock-tiempo-nil", function(d) return CoreLogic.unlock(d, "Fire", 1e15, nil) end, "InvalidRequest")
expectReject("select-tiempo-nil", function(d) return CoreLogic.selectElement(d, {}, "Water", 1e15, nil) end, "InvalidRequest")
for i, element in BAD_ELEMENT do
	expectReject("unlock-elemento" .. i, function(d) return CoreLogic.unlock(d, element, 1e15, NOW) end, "InvalidRequest")
	expectReject("select-elemento" .. i, function(d) return CoreLogic.selectElement(d, {}, element, 1e15, NOW) end, "InvalidRequest")
end
expectReject("unlock-elemento-nil", function(d) return CoreLogic.unlock(d, nil, 1e15, NOW) end, "InvalidRequest")
expectReject("select-elemento-nil", function(d) return CoreLogic.selectElement(d, {}, nil, 1e15, NOW) end, "InvalidRequest")
expectReject("unlock-Naturaleza", function(d) return CoreLogic.unlock(d, "Nature", 1e15, NOW) end, "AlreadyUnlocked")
expectReject("select-bloqueado", function(d) return CoreLogic.selectElement(d, {}, "Fire", 1e15, NOW) end, "Locked")
local recent = deep(base)
recent.LastSwitchAt = NOW - 1
expectReject("select-enfriamiento", function(d) return CoreLogic.selectElement(d, {}, "Water", 1e15, NOW) end, "TooFast", recent)
check("energía, tiempo o elemento no válidos sobre datos válidos -> rechazo sin cambios parciales" .. partialFail, noPartial)
-- Naturaleza sin desbloquear en datos sin sanear: no tiene coste de desbloqueo.
local okNature, natureCode = pcall(CoreLogic.unlock, { Elements = { Nature = { Unlocked = false } } }, "Nature", 1e15, NOW)
check("unlock de Naturaleza en datos sin sanear -> sin error (no tiene coste de desbloqueo)", okNature and natureCode == "InvalidRequest")
-- Un tiempo en (0, 1) se truncaría a 0, que en los datos significa "nunca": se saltaría
-- el enfriamiento y UnlockedAt quedaría a 0. Debe rechazarse como tiempo no válido.
local subSecondOK, subSecondFail = true, ""
for _, time in { 0.5, 0.999 } do
	local fresh = CoreLogic.empty()
	fresh.Elements.Water.Unlocked = true
	local okU, gotU = rejects(function(d) return CoreLogic.unlock(d, "Water", 1e15, time) end, CoreLogic.empty(), "InvalidRequest")
	local okS, gotS = rejects(function(d) return CoreLogic.selectElement(d, {}, "Water", 1e15, time) end, fresh, "InvalidRequest")
	local reward = CoreLogic.offlineReward(CoreLogic.empty(), {}, 1, time, NOW)
	if not okU then subSecondOK = false subSecondFail ..= (" unlock(%s)=%s"):format(tostring(time), gotU) end
	if not okS then subSecondOK = false subSecondFail ..= (" select(%s)=%s"):format(tostring(time), gotS) end
	if reward ~= 0 then subSecondOK = false subSecondFail ..= (" offline(lastSeen=%s)=%s"):format(tostring(time), tostring(reward)) end
end
check("tiempo en (0, 1) -> InvalidRequest sin cambios; lastSeen en (0, 1) -> sin recompensa offline" .. subSecondFail, subSecondOK)

-- corrections: qué valores conocidos corrigió sanitize (para archivarlos antes).
local function correctionsOf(raw) return CoreLogic.corrections(raw, CoreLogic.sanitize(raw)) end
check("corrections: partida sin Cores, datos vacíos o ya válidos -> nada que archivar", correctionsOf(nil) == nil and correctionsOf({}) == nil and correctionsOf(CoreLogic.empty()) == nil and correctionsOf(deep(all)) == nil)
local nanChanges = correctionsOf({ LastSwitchAt = NAN, Elements = { Water = { Level = INF, Mastery = 2.5 } } })
check("corrections: los valores no guardables se describen como texto; lo válido no aparece",
	nanChanges ~= nil and type(nanChanges.LastSwitchAt) == "string" and nanChanges.LastSwitchAt:find("number", 1, true) ~= nil
		and type(nanChanges["Elements.Water.Level"]) == "string" and nanChanges["Elements.Water.Mastery"] == nil)
check("corrections: Cores que no es una tabla se archiva entero", same(correctionsOf("roto"), { Cores = "roto" }))
-- Un Level en Naturaleza se conserva copiado (no se usa): aunque sea una tabla, no es una
-- corrección (si lo fuera, se archivaría otra vez en cada carga).
check("corrections: un valor conservado como copia (Naturaleza.Level tabla) no se anota", correctionsOf({ Elements = { Nature = { Unlocked = true, Level = { Old = 3 } } } }) == nil)

print("-- 9. Recompensa offline (cálculo puro: no concede ni guarda)")
local cap, eff = CoreConfig.Offline.CapSeconds, CoreConfig.Offline.Efficiency
check(("configuración aprobada: tope %d s (4 h), eficiencia %.0f %%, con mascotas"):format(cap, eff * 100), cap == 4 * 3600 and eff == 0.5 and CoreConfig.Offline.IncludePetMultiplier == true)
local od = CoreLogic.empty()
od.Elements.Water.Unlocked = true
od.Elements.Water.Level = 2
local oLevels = { GeneratorPower = 5 }
local oBase = CoreLogic.baseProduction(od, oLevels) -- (1 + 5) + 2 · 3 = 12
local before = deep(od)
local levelsBefore = deep(oLevels)
local reward, seconds = CoreLogic.offlineReward(od, oLevels, 2, NOW, NOW)
check("ausencia cero -> 0", reward == 0 and seconds == 0)
reward, seconds = CoreLogic.offlineReward(od, oLevels, 2, NOW + 100, NOW)
check("ausencia negativa (reloj atrasado) -> 0", reward == 0 and seconds == 0)
reward, seconds = CoreLogic.offlineReward(od, oLevels, 2, NOW - 600, NOW)
check(("10 min, base %d ⚡/s, mascotas ×2 -> %d (600 · %d · 2 · 0,5)"):format(oBase, reward, oBase), reward == math.floor(600 * oBase * 2 * eff) and seconds == 600)
reward, seconds = CoreLogic.offlineReward(od, oLevels, 2, NOW - cap, NOW)
check("exactamente 4 h -> 4 h completas", seconds == cap and reward == math.floor(cap * oBase * 2 * eff))
reward, seconds = CoreLogic.offlineReward(od, oLevels, 2, NOW - 3 * 86400, NOW)
check(("3 días -> limitado a 4 h: %d"):format(reward), seconds == cap and reward == math.floor(cap * oBase * 2 * eff))
check("mascotas aplicadas UNA vez: igual a min(ausencia, 4 h) · producción total · 0,5", reward == math.floor(cap * CoreLogic.totalProduction(od, oLevels, 2) * eff))
check("no modifica los datos ni los niveles (no concede nada)", same(od, before) and same(oLevels, levelsBefore))
check("sin LastSeen (partida antigua: nil o 0) -> 0, nada retroactivo", CoreLogic.offlineReward(od, oLevels, 2, nil, NOW) == 0 and CoreLogic.offlineReward(od, oLevels, 2, 0, NOW) == 0)
check("tiempos no válidos (NaN, infinito, texto, negativos) -> 0", CoreLogic.offlineReward(od, oLevels, 2, NAN, NOW) == 0 and CoreLogic.offlineReward(od, oLevels, 2, NOW - 60, INF) == 0 and CoreLogic.offlineReward(od, oLevels, 2, "x", NOW) == 0 and CoreLogic.offlineReward(od, oLevels, 2, -60, NOW) == 0)
check("mascotas no válidas -> ×1", CoreLogic.offlineReward(od, oLevels, NAN, NOW - 600, NOW) == math.floor(600 * oBase * eff))
check("con datos de núcleos mal formados -> resultado finito", finite((CoreLogic.offlineReward(CoreLogic.sanitize({ Elements = { Water = { Unlocked = true, Level = NAN } } }), { GeneratorPower = NAN }, INF, NOW - 600, NOW))))

print("-- 10. Configuración no válida")
local function broken(mutate)
	local copy = deep(CoreConfig)
	mutate(copy)
	local ok, errors = CoreLogic.validateConfig(copy, EconomyConfig)
	return not ok and #errors > 0
end
check("no es una tabla", not (CoreLogic.validateConfig(nil, EconomyConfig)))
check("siete elementos", broken(function(c) table.remove(c.Order) end))
check("elemento repetido", broken(function(c) c.Order[8] = "Nature" end))
check("elemento sin definición", broken(function(c) c.Elements.Ice = nil end))
check("definición sin estar en el orden", broken(function(c) c.Elements.Poison = { DisplayName = "Veneno" } end))
check("elemento por defecto que no es el primero", broken(function(c) c.DefaultElement = "Water" end))
check("Naturaleza sin UpgradeId o con uno inexistente", broken(function(c) c.Elements.Nature.UpgradeId = nil end) and broken(function(c) c.Elements.Nature.UpgradeId = "Nope" end))
check("costes de desbloqueo no crecientes (Growth <= 1), cero, NaN o infinitos", broken(function(c) c.Unlock.Growth = 1 end) and broken(function(c) c.Unlock.BaseCost = 0 end) and broken(function(c) c.Unlock.BaseCost = NAN end) and broken(function(c) c.Unlock.BaseCost = INF end))
check("Sequential no booleano", broken(function(c) c.Unlock.Sequential = "sí" end))
check("CostGrowth <= 1, MaxLevel no entero, producción base 0", broken(function(c) c.Upgrade.CostGrowth = 1 end) and broken(function(c) c.Upgrade.MaxLevel = 2.5 end) and broken(function(c) c.Upgrade.BaseProduction = 0 end))
check("MaxPetMultiplier no válido (< 1, NaN)", broken(function(c) c.MaxPetMultiplier = 0.5 end) and broken(function(c) c.MaxPetMultiplier = NAN end))
check("offline: tope 0, eficiencia > 1 o negativa, IncludePetMultiplier no booleano", broken(function(c) c.Offline.CapSeconds = 0 end) and broken(function(c) c.Offline.Efficiency = 1.5 end) and broken(function(c) c.Offline.Efficiency = -0.1 end) and broken(function(c) c.Offline.IncludePetMultiplier = "no" end))
check("coste de cambio negativo", broken(function(c) c.Switch.MinCost = -1 end))
check("valores finitos que producen costes infinitos o sin precisión entera (Tier 1e60, BaseCost 1e300)", broken(function(c) c.Upgrade.TierMultiplier = 1e60 end) and broken(function(c) c.Unlock.BaseCost = 1e300 end))
check("la configuración real queda muy por debajo del límite de precisión (2^53)", (function()
	local maxUpgrade = CoreLogic.upgradeCost("Celestial", up.MaxLevel - 1)
	return maxUpgrade < 2 ^ 53 and CoreLogic.unlockCost("Celestial") < 2 ^ 53
end)())
local okInit = pcall(CoreLogic.init, (function() local c = deep(CoreConfig) c.Unlock.Growth = 0.5 return c end)(), Economy, EconomyConfig)
check("init rechaza una configuración no válida con un error claro", okInit == false)
CoreLogic.init(CoreConfig, Economy, EconomyConfig) -- se restaura la configuración real

print("-- 11. Informe de balance [PROVISIONAL] (comparación con el cristal actual)")
local function fmt(n)
	if n >= 1e9 then return ("%.2fB"):format(n / 1e9) elseif n >= 1e6 then return ("%.2fM"):format(n / 1e6) elseif n >= 1e4 then return ("%.1fk"):format(n / 1e3) end
	return tostring(math.floor(n * 100 + 0.5) / 100)
end
local full = CoreLogic.empty()
for index = 2, 8 do full.Elements[ORDER[index]].Unlocked = true end
info("núcleo      desbloqueo  acumulado   prod n0  prod n10  prod n25  prod n50  mejora n0  mejora n10  mejora n25  total 0->50")
local cumulative, finiteReport, tierOK = 0, true, true
for index, id in ORDER do
	local unlock = CoreLogic.unlockCost(id) or 0
	cumulative += unlock
	local prods, upgradeSum = {}, 0
	for _, level in { 0, 10, 25, 50 } do
		local lv = if index == 1 then { GeneratorPower = level } else {}
		if index > 1 then full.Elements[id].Level = level end
		prods[level] = CoreLogic.coreProduction(full, lv, id)
	end
	for level = 0, 49 do upgradeSum += CoreLogic.upgradeCost(id, level) end
	local c0, c10, c25 = CoreLogic.upgradeCost(id, 0), CoreLogic.upgradeCost(id, 10), CoreLogic.upgradeCost(id, 25)
	for _, v in { unlock, prods[0], prods[50], c0, upgradeSum } do if not finite(v) then finiteReport = false end end
	if index > 1 then
		-- Amortización de la mejora 10 = coste / producción que añade un nivel. Debe ser
		-- igual en todos los escalones (coste y producción crecen con el mismo factor).
		local marginal = up.BaseProduction * up.TierMultiplier ^ (index - 1)
		local waterPayback = CoreLogic.upgradeCost("Water", 10) / (up.BaseProduction * up.TierMultiplier)
		if math.abs(c10 / marginal - waterPayback) / waterPayback > 0.01 then tierOK = false end
	end
	info(("%-10s %10s %10s %9s %9s %9s %9s %10s %11s %11s %12s"):format(
		CoreConfig.Elements[id].DisplayName, fmt(unlock), fmt(cumulative), fmt(prods[0]), fmt(prods[10]), fmt(prods[25]), fmt(prods[50]), fmt(c0), fmt(c10), fmt(c25), fmt(upgradeSum)))
end
for index = 2, 8 do full.Elements[ORDER[index]].Level = 0 end
local crystalMax = Economy.getProductionPerSecond({ GeneratorPower = 50 })
info(("cristal actual (Naturaleza): nivel 0 = %s ⚡/s, nivel 50 = %s ⚡/s; las 50 mejoras cuestan %s"):format(
	fmt(Economy.getProductionPerSecond({ GeneratorPower = 0 })), fmt(crystalMax), fmt((function() local s = 0 for l = 0, 49 do s += Economy.getUpgradeCost("GeneratorPower", l) end return s end)())))
info(("los ocho desbloqueados a nivel 0: %s ⚡/s base; desbloquearlos todos cuesta %s"):format(fmt(CoreLogic.baseProduction(full, { GeneratorPower = 0 })), fmt(cumulative)))
info(("OBSERVACIÓN: Celestial a nivel 0 produce %s ⚡/s, más que el cristal a nivel 50 (%s ⚡/s): revisar Tier/BaseProduction con el diseño final."):format(fmt(CoreLogic.coreProduction(full, {}, "Celestial")), fmt(crystalMax)))
check("todas las cifras del informe son finitas", finiteReport)
check("cada escalón mantiene la misma relación coste/producción (amortización igual)", tierOK)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
