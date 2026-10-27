-- Renacimiento: RebirthLogic (pura) y el RebirthService REAL con PlayerDataService y
-- SaveService reales sobre un DataStore en memoria. Requisito (ganar las oleadas del modo
-- que toca desde el último renacimiento + 💰), bloqueo con Enabled = false, reinicio en el
-- mismo paso, fichas, tienda, multiplicadores (botín y daño), espacios de mascota, guardado
-- y lo social (leaderstats y aviso).
QuestLogic.init(QuestConfig, EnemyConfig)
PlayerDataService.start()
UpgradeService.start()
QuestService.start()
RebirthService.start()

local Codes = Constants.PurchaseCodes
local failures = 0
local function check(name, ok)
	if not ok then
		failures += 1
	end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local function near(a, b)
	return math.abs(a - b) < 1e-9
end
local function record(userId)
	return storeData["player_" .. userId]
end

print("-- 1. Configuración y fórmulas")
local okConfig, problems = RebirthLogic.validateConfig()
check("RebirthConfig válida" .. (if okConfig then "" else ": " .. table.concat(problems, "; ")), okConfig)
check("renacer está habilitado y ya no pide la Resonancia", RebirthConfig.Enabled == true and RebirthConfig.UpgradeId == nil)
local list = RebirthConfig.Requirement.Waves
local r1, r2, r5, r6, r8 = RebirthLogic.requirement(0), RebirthLogic.requirement(1), RebirthLogic.requirement(4), RebirthLogic.requirement(5), RebirthLogic.requirement(7)
check("requisito 1: ganar las oleadas del Bosque (10) y 💰 25 000", r1.ArenaId == "Forest" and r1.Wave == WaveLogic.waveCount("Forest") and r1.Wave == 10 and r1.Money == 25000)
check("requisito 2: las del Valle y 💰 75 000 (×3 cada vez)", r2.ArenaId == "CrystalValley" and r2.Wave == WaveLogic.waveCount("CrystalValley") and r2.Money == 75000)
check("requisito 5: el último modo de la lista", r5.ArenaId == list[#list] and r5.Wave == WaveLogic.waveCount(list[#list]))
check("después, el último modo en el infinito: +3 oleadas por renacimiento", r6.ArenaId == list[#list] and r6.Wave == WaveLogic.waveCount(list[#list]) + 3 and r8.Wave == WaveLogic.waveCount(list[#list]) + 9)
check("valores raros cuentan como 0 renacimientos", RebirthLogic.requirement(0 / 0).ArenaId == "Forest" and RebirthLogic.requirement(-4).Money == 25000)
check("fichas: el renacimiento k da k (1, 2, 5)", RebirthLogic.tokensFor(0) == 1 and RebirthLogic.tokensFor(1) == 2 and RebirthLogic.tokensFor(4) == 5)
check("botín: +50 % de 💰 por renacimiento (×1, ×1.5, ×3)",
	RebirthLogic.lootBonusAt(0) == 1 and near(RebirthLogic.lootBonusAt(1), 1.5) and near(RebirthLogic.lootBonusAt(4), 3))
check("daño: +10 % por renacimiento y +15 % por nivel de Golpe renacido, multiplicados",
	near(RebirthLogic.damageMultiplierAt(2, 0), 1.2) and near(RebirthLogic.damageMultiplierAt(2, 2), 1.2 * 1.3) and RebirthLogic.damageMultiplierAt(0, 0) == 1)
local shopData = { Count = 2, Tokens = 0, Shop = { Loot = 2, PetSlot = 1 }, LastAt = 0 }
check("botín: renacimientos · Botín abundante (×2 · 1.5 = ×3)", near(RebirthLogic.lootMultiplier(shopData), 3))
check("espacios: 3 + Espacio de mascota; tope 3 + 2", RebirthLogic.maxEquipped(shopData, 3) == 4 and RebirthLogic.maxEquippedCap(3) == 5 and RebirthLogic.maxEquipped(nil, 3) == 3)
check("ya no hay Inicio rápido (Resonancia) ni Sueño profundo (offline)", RebirthConfig.Shop.HeadStart == nil and RebirthConfig.Shop.Dreams == nil)
check("números romanos", RebirthLogic.numeral(1) == "I" and RebirthLogic.numeral(4) == "IV" and RebirthLogic.numeral(9) == "IX" and RebirthLogic.numeral(14) == "XIV" and RebirthLogic.numeral(40) == "XL" and RebirthLogic.numeral(2024) == "MMXXIV" and RebirthLogic.numeral(0) == "0")
local text = RebirthLogic.shopText(shopData)
local parsed = RebirthLogic.parseShop(text)
check("tienda en texto (atributo) y de vuelta: " .. text, text == "PetSlot=1,Loot=2" and parsed.PetSlot == 1 and parsed.Loot == 2 and parsed.Strike == nil)
check("texto de tienda manipulado: solo ventajas conocidas y sin pasar del máximo", RebirthLogic.parseShop("PetSlot=99,Hack=5,Loot=x").PetSlot == 2 and RebirthLogic.parseShop("PetSlot=99,Hack=5").Hack == nil)
check("CombatMath.withBonus: redondeo a centésimas y multiplicador no válido sin efecto",
	CombatMath.withBonus(10, 1.2) == 12 and CombatMath.withBonus(33.33, 1.1) == 36.66 and CombatMath.withBonus(10, 0 / 0) == 10 and CombatMath.withBonus(10, -1) == 10)

print("-- 2. Datos guardados: saneado")
local empty = RebirthLogic.sanitize(nil)
check("sin datos: vacío", empty.Count == 0 and empty.Tokens == 0 and next(empty.Shop) == nil and empty.LastAt == 0)
local dirty = RebirthLogic.sanitize({ Count = 0 / 0, Tokens = -5, BestLevel = 999, LastAt = "ayer", Shop = { Loot = 99, Strike = 2.7, Future = 3, [5] = 1, Bad = 0 / 0 } })
check("valores no válidos -> seguros; niveles acotados; ventajas futuras conservadas; BestLevel (Resonancia) fuera",
	dirty.Count == 0 and dirty.Tokens == 0 and dirty.BestLevel == nil and dirty.LastAt == 0
		and dirty.Shop.Loot == 4 and dirty.Shop.Strike == 2 and dirty.Shop.Future == 3 and dirty.Shop[5] == nil and dirty.Shop.Bad == nil)
check("tope de renacimientos", RebirthLogic.sanitize({ Count = 1e12 }).Count == RebirthConfig.MaxRebirths)
check("sanitize devuelve una copia (no comparte la tienda)", RebirthLogic.sanitize(shopData).Shop ~= shopData.Shop)

print("-- 3. Acciones puras: ciclo, renacer y comprar")
local d = RebirthLogic.empty()
check("ciclo vacío al empezar: nada superado", RebirthLogic.cycleWave(d, "Forest") == 0 and not RebirthLogic.canRebirth(d, 1e9))
check("anotar oleadas: solo sube el máximo y solo en modos que existen", RebirthLogic.recordWave(d, "Forest", 4) and not RebirthLogic.recordWave(d, "Forest", 3)
	and not RebirthLogic.recordWave(d, "Nada", 50) and not RebirthLogic.recordWave(d, "Forest", 0 / 0) and RebirthLogic.cycleWave(d, "Forest") == 4)
local code, result = RebirthLogic.rebirth(d, 1e9, 100)
check("oleada 4 de 10: WavesNotDone con el progreso, nada cambia", code == "WavesNotDone" and result.BestWave == 4 and result.Wave == 10 and d.Count == 0)
RebirthLogic.recordWave(d, "CrystalValley", 12)
check("ganar otro modo no cuenta para el Bosque", RebirthLogic.rebirth(d, 1e9, 100) == "WavesNotDone")
RebirthLogic.recordWave(d, "Forest", 10)
code, result = RebirthLogic.rebirth(d, 24999, 100)
check("oleadas ganadas pero 💰 24 999: InsufficientMoney, nada cambia", code == "InsufficientMoney" and result.Money == 25000 and result.Have == 24999 and d.Count == 0 and d.Cycle.Forest == 10)
check("canRebirth: con las dos cosas sí, con 💰 de menos no", RebirthLogic.canRebirth(d, 25000) and not RebirthLogic.canRebirth(d, 100))
code, result = RebirthLogic.rebirth(d, 25000, 100)
check("renace: 1 ficha, paga 💰 25 000 y el ciclo queda vacío", code == "Success" and result.Count == 1 and result.Tokens == 1 and result.Paid == 25000 and d.Count == 1 and d.Tokens == 1 and d.LastAt == 100 and next(d.Cycle) == nil)
check("el segundo pide el Valle: las oleadas del Valle de antes del renacimiento ya no cuentan", RebirthLogic.rebirth(d, 1e9, 200) == "WavesNotDone" and RebirthLogic.progress(d, 0).ArenaId == "CrystalValley")
check("el ciclo viaja en texto (atributo RebirthCycle) y de vuelta", (function()
	local c = RebirthLogic.empty()
	RebirthLogic.recordWave(c, "Forest", 10)
	RebirthLogic.recordWave(c, "EmberCaldera", 3)
	local text = RebirthLogic.cycleText(c)
	local back = RebirthLogic.parseCycle(text)
	return text == "EmberCaldera=3,Forest=10" and back.Forest == 10 and back.EmberCaldera == 3 and RebirthLogic.parseCycle("Hack=5,Forest=x").Hack == nil
end)())
check("ciclo guardado roto: se sanea (sin NaN, negativos ni claves raras)", (function()
	local clean = RebirthLogic.sanitize({ Count = 1, Cycle = { Forest = 9.7, Bad = -2, [3] = 4, Valley = "x" } })
	return clean.Cycle.Forest == 9 and clean.Cycle.Bad == nil and clean.Cycle[3] == nil and clean.Cycle.Valley == nil
end)())
code, result = RebirthLogic.buy(d, "PetSlot")
check("Espacio de mascota cuesta 3: con 1 ficha no llega y no cambia nada", code == "InsufficientTokens" and result == 3 and d.Tokens == 1 and d.Shop.PetSlot == nil)
code, result = RebirthLogic.buy(d, "Loot")
check("Botín abundante nivel 1 por 1 ficha", code == "Success" and result == 1 and d.Tokens == 0 and d.Shop.Loot == 1)
check("ventaja inexistente (también las quitadas) o datos no válidos: InvalidRequest", RebirthLogic.buy(d, "Hack") == "InvalidRequest" and RebirthLogic.buy(d, "HeadStart") == "InvalidRequest" and RebirthLogic.buy(nil, "Loot") == "InvalidRequest" and RebirthLogic.buy(d, 5) == "InvalidRequest")
d.Tokens = 100
for _ = 1, 2 do
	RebirthLogic.buy(d, "PetSlot")
end
check("al máximo: MaxLevel sin cobrar", RebirthLogic.buy(d, "PetSlot") == "MaxLevel" and d.Shop.PetSlot == 2 and d.Tokens == 100 - 3 - 10)
check("renacer con datos no válidos: InvalidRequest", RebirthLogic.rebirth(nil, 1e9, 1) == "InvalidRequest")
local maxed = { Count = RebirthConfig.MaxRebirths, Tokens = 0, Shop = {}, LastAt = 0, Cycle = {} }
check("tope de renacimientos: MaxLevel", RebirthLogic.rebirth(maxed, 1e15, 1) == "MaxLevel" and maxed.Count == RebirthConfig.MaxRebirths)
RebirthConfig.Enabled = false
local blocked = { Count = 0, Tokens = 0, Shop = {}, LastAt = 0, Cycle = { Forest = 10 } }
check("con Enabled = false: ComingSoon aunque cumpla el requisito", RebirthLogic.rebirth(blocked, 1e9, 1) == "ComingSoon" and blocked.Count == 0 and not RebirthLogic.canRebirth(blocked, 1e9))
RebirthConfig.Enabled = true

print("-- 4. RebirthService real: requisito")
local p1 = PetService.newPlayer("Ana", 1)
join(p1)
advance(0)
local profile = PlayerDataService.get(p1)
check("datos cargados: 0 renacimientos replicados y columna en la lista de jugadores",
	profile.DataState == "Loaded" and p1:GetAttribute("Rebirths") == 0 and p1:GetAttribute("MaxEquipped") == 3
		and p1:FindFirstChild("leaderstats") ~= nil and p1:FindFirstChild("leaderstats"):FindFirstChild("Renacimientos").Value == 0)
profile.Diamonds = 5000
profile.Money = 30000
fireServer("Rebirth", p1)
advance(0)
local args = lastResult("RebirthResult", p1)
check("sin las oleadas: WavesNotDone con el progreso (Bosque, 0 de 10)", args[1] == false and args[2] == Codes.WavesNotDone and args[3] == "Rebirth" and args[4].ArenaId == "Forest" and args[4].BestWave == 0)
check("y no se toca nada", profile.Diamonds == 5000 and profile.Money == 30000 and profile.PetData.Rebirth.Count == 0)
-- Lo que hace WaveService al superar oleadas (GameEvents "WaveCleared")
GameEvents.fire("WaveCleared", p1, "Forest", 9)
GameEvents.fire("WaveCleared", p1, "Forest", 10)
advance(0)
check("las oleadas superadas cuentan para el ciclo y se replican (RebirthCycle)", profile.PetData.Rebirth.Cycle.Forest == 10 and p1:GetAttribute("RebirthCycle") == "Forest=10")
profile.Money = 1000
advance(RebirthConfig.RebirthCooldown + 0.1)
fireServer("Rebirth", p1)
advance(0)
args = lastResult("RebirthResult", p1)
check("con las oleadas pero sin 💰: InsufficientMoney con lo que pide", args[1] == false and args[2] == Codes.InsufficientMoney and args[4].Money == 25000 and profile.PetData.Rebirth.Count == 0 and profile.Money == 1000)

print("-- 5. RebirthService real: renacer")
profile.Money = 30000
profile.PetData.Weapons.Levels[WeaponConfig.StarterWeapon] = 6
profile.PetMultiplier = 1.5
local pushedBefore = PetService.Pushed
local diamondsBefore = profile.Diamonds
advance(RebirthConfig.RebirthCooldown + 0.1)
fireServer("Rebirth", p1)
advance(0)
args = lastResult("RebirthResult", p1)
check("renace", args[1] == true and args[2] == Codes.Success and args[4].Count == 1 and args[4].Tokens == 1 and args[4].Paid == 25000)
check("en el mismo paso: 💰 al inicial, armas a nivel 0 y ciclo vacío; los 💎 se quedan", profile.Money == EconomyConfig.StartingMoney and profile.Diamonds == diamondsBefore and profile.PetData.Weapons.Levels[WeaponConfig.StarterWeapon] == 0 and next(profile.PetData.Rebirth.Cycle) == nil and p1:GetAttribute("RebirthCycle") == "")
check("1 renacimiento y 1 ficha (atributos para el cliente, sin los de la Resonancia)",
	p1:GetAttribute("Rebirths") == 1 and p1:GetAttribute("RebirthTokens") == 1 and p1:GetAttribute("RebirthBestLevel") == nil and p1:GetAttribute("UpgradeLevel_GeneratorPower") == nil)
check("la columna de la lista de jugadores marca 1", p1:FindFirstChild("leaderstats"):FindFirstChild("Renacimientos").Value == 1)
local broadcast = PetService.Broadcasts[#PetService.Broadcasts]
check("aviso a todos: quién y cuántos", broadcast and broadcast.Name == "RebirthEvent" and broadcast.Args[1] == 1 and broadcast.Args[2] == "Ana" and broadcast.Args[3] == 1)
check("inventario de mascotas reenviado (espacios al día)", PetService.Pushed == pushedBefore + 1)
advance(0)
local saved = record(1)
check("guardado en seguida: Version 17 y Rebirth (con su ciclo vacío) en el registro", saved and saved.Version == 17 and saved.Rebirth and saved.Rebirth.Count == 1 and saved.Rebirth.Tokens == 1 and next(saved.Rebirth.Cycle or {}) == nil)

fireServer("Rebirth", p1)
advance(0)
args = lastResult("RebirthResult", p1)
check("otra petición en seguida: TooFast (protección)", args[1] == false and args[2] == Codes.TooFast)
GameEvents.fire("WaveCleared", p1, "CrystalValley", 5)
advance(0)
exit = function(player)
	leave(player)
	advance(0)
end
leave(p1)
advance(0)
check("el ciclo se guarda (oleada 5 del Valle)", record(1).Rebirth.Cycle.CrystalValley == 5)
p1 = PetService.newPlayer("Ana", 1)
join(p1)
advance(0)
profile = PlayerDataService.get(p1)
check("y se carga al volver", profile.PetData.Rebirth.Cycle.CrystalValley == 5 and p1:GetAttribute("RebirthCycle") == "CrystalValley=5")

print("-- 6. Tienda")
advance(1)
fireServer("RebirthShop", p1, "PetSlot")
advance(0)
args = lastResult("RebirthResult", p1)
check("Espacio de mascota cuesta 3: con 1 ficha, InsufficientTokens con el coste", args[1] == false and args[2] == Codes.InsufficientTokens and args[4].Cost == 3 and profile.PetData.Rebirth.Tokens == 1)
advance(1)
fireServer("RebirthShop", p1, { "raro" })
advance(0)
args = lastResult("RebirthResult", p1)
check("argumento no válido: InvalidRequest", args[1] == false and args[2] == Codes.InvalidRequest)
advance(1)
fireServer("RebirthShop", p1, "Strike")
advance(0)
args = lastResult("RebirthResult", p1)
check("tienda de fichas: Golpe renacido nivel 1", args[1] == true and args[4].ItemId == "Strike" and args[4].Level == 1 and args[4].Cost == 1 and p1:GetAttribute("RebirthTokens") == 0 and p1:GetAttribute("RebirthShop") == "Strike=1")
profile.PetData.Rebirth.Tokens = 3
pushedBefore = PetService.Pushed
advance(1)
fireServer("RebirthShop", p1, "PetSlot")
advance(0)
check("Espacio de mascota: 4 equipadas y el inventario se reenvía", p1:GetAttribute("MaxEquipped") == 4 and PetService.Pushed == pushedBefore + 1)
check("daño del jugador: ×1.1 por el renacimiento y ×1.15 por Golpe renacido", near(RebirthLogic.damageMultiplier(profile.PetData.Rebirth), 1.1 * 1.15))

print("-- 7. Recarga: espacios y sin offline")
exit(p1)
storeData.player_2 = {
	Version = 4,
	Diamonds = 0,
	Pets = { { Uid = "1", PetId = "Sproutling" }, { Uid = "2", PetId = "Sproutling" }, { Uid = "3", PetId = "MossFox" }, { Uid = "4", PetId = "MossFox" }, { Uid = "5", PetId = "MoonOwl" } },
	Equipped = { "1", "2", "3", "4", "5" },
	NextPetUid = 6,
	LastSeen = os.time() - 6 * 3600,
	Rebirth = { Count = 2, Tokens = 4, Shop = { PetSlot = 2 }, LastAt = 1 },
}
local p2 = PetService.newPlayer("Bea", 2)
join(p2)
advance(0)
local profile2 = PlayerDataService.get(p2)
check("con 2 espacios extra se cargan las 5 equipadas", #profile2.PetData.Equipped == 5 and p2:GetAttribute("MaxEquipped") == 5)
check("6 h fuera con 2 renacimientos: sin 💎 offline", p2:GetAttribute("OfflineReward") == nil)
storeData.player_3 = { Version = 4, Pets = storeData.player_2.Pets, Equipped = { "1", "2", "3", "4", "5" }, NextPetUid = 6 }
local p3 = PetService.newPlayer("Caro", 3)
join(p3)
advance(0)
-- Sin espacios extra se pueden equipar 3; al cargar se conservan hasta 5 (las del pase «Más
-- mascotas» aún no se conocen) y ShopService quita las de más si no lo tiene (prueba shop).
check("sin espacios extra: puede equipar 3 (al cargar se conservan hasta 5 hasta saber sus pases)", #PlayerDataService.get(p3).PetData.Equipped == 5 and p3:GetAttribute("MaxEquipped") == 3)
check("un registro v3 sin Rebirth carga sin renacimientos", PlayerDataService.get(p3).PetData.Rebirth.Count == 0)
storeData.player_4 = { Version = 4, Diamonds = 10, Rebirth = { Count = 1, Tokens = 0, Shop = { Loot = 1, FutureThing = 2 }, LastAt = 5 } }
local p4 = PetService.newPlayer("Dani", 4)
join(p4)
advance(0)
exit(p4)
check("una ventaja futura desconocida se conserva al guardar", record(4).Rebirth.Shop.FutureThing == 2 and record(4).Rebirth.Shop.Loot == 1 and record(4).Rebirth.Count == 1)

print("-- 8. Logros de renacimiento")
local ctx = QuestService.contextOf(profile2)
check("el contexto de misiones cuenta los renacimientos", ctx.Rebirths == 2)
local found = 0
for _, def in QuestConfig.Achievements do
	if def.Goal.Source == "State" and def.Goal.Key == "Rebirths" then
		found += 1
	end
end
check("logros Renacido y Ciclo eterno", found == 2)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
