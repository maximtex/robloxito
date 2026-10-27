-- Renacimiento: RebirthLogic (pura) y el RebirthService REAL con PlayerDataService y
-- SaveService reales sobre un DataStore en memoria. Bloqueo "Próximamente" (sin la
-- Resonancia del Cristal no hay requisito hasta la fase 2), reinicio en el mismo paso,
-- fichas, tienda, multiplicadores (botín y daño), espacios de mascota, guardado y lo
-- social (leaderstats y aviso).
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
check("renacer está bloqueado (Próximamente) hasta su requisito nuevo", RebirthConfig.Enabled == false and RebirthConfig.UpgradeId == nil and RebirthConfig.Requirement == nil)
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

print("-- 3. Acciones puras: renacer y comprar")
local d = RebirthLogic.empty()
local code, result = RebirthLogic.rebirth(d, 100)
check("bloqueado: ComingSoon y nada cambia", code == "ComingSoon" and result == nil and d.Count == 0 and d.Tokens == 0 and not RebirthLogic.canRebirth(d))
check("renacer con datos no válidos: InvalidRequest", RebirthLogic.rebirth(nil, 1) == "InvalidRequest")
RebirthConfig.Enabled = true -- (fase 2: el requisito nuevo) se prueba el resto del camino
code, result = RebirthLogic.rebirth(d, 100)
check("habilitado: renace (1 ficha)", code == "Success" and result.Count == 1 and result.Tokens == 1 and d.Count == 1 and d.Tokens == 1 and d.LastAt == 100 and RebirthLogic.canRebirth(d))
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
code, result = RebirthLogic.rebirth(d, 300)
check("el segundo da 2 fichas", code == "Success" and result.Tokens == 2 and d.Count == 2)
local maxed = { Count = RebirthConfig.MaxRebirths, Tokens = 0, Shop = {}, LastAt = 0 }
check("tope de renacimientos: MaxLevel", RebirthLogic.rebirth(maxed, 1) == "MaxLevel" and maxed.Count == RebirthConfig.MaxRebirths)
RebirthConfig.Enabled = false

print("-- 4. RebirthService real: bloqueado")
local p1 = PetService.newPlayer("Ana", 1)
join(p1)
advance(0)
local profile = PlayerDataService.get(p1)
check("datos cargados: 0 renacimientos replicados y columna en la lista de jugadores",
	profile.DataState == "Loaded" and p1:GetAttribute("Rebirths") == 0 and p1:GetAttribute("MaxEquipped") == 3
		and p1:FindFirstChild("leaderstats") ~= nil and p1:FindFirstChild("leaderstats"):FindFirstChild("Renacimientos").Value == 0)
profile.Energy = 5000
profile.Money = 777
fireServer("Rebirth", p1)
advance(0)
local args = lastResult("RebirthResult", p1)
check("pedir renacer: ComingSoon", args[1] == false and args[2] == Codes.ComingSoon and args[3] == "Rebirth")
check("y no se toca nada", profile.Energy == 5000 and profile.Money == 777 and profile.PetData.Rebirth.Count == 0)

print("-- 5. RebirthService real: renacer (con Enabled, como en la fase 2)")
RebirthConfig.Enabled = true
profile.PetData.Weapons.Levels[WeaponConfig.StarterWeapon] = 6
profile.PetMultiplier = 1.5
local pushedBefore = PetService.Pushed
local diamondsBefore = profile.Energy
advance(RebirthConfig.RebirthCooldown + 0.1)
fireServer("Rebirth", p1)
advance(0)
args = lastResult("RebirthResult", p1)
check("renace", args[1] == true and args[2] == Codes.Success and args[4].Count == 1 and args[4].Tokens == 1)
check("en el mismo paso: 💰 al inicial y armas a nivel 0; los 💎 se quedan", profile.Money == EconomyConfig.StartingMoney and profile.Energy == diamondsBefore and profile.PetData.Weapons.Levels[WeaponConfig.StarterWeapon] == 0)
check("1 renacimiento y 1 ficha (atributos para el cliente, sin los de la Resonancia)",
	p1:GetAttribute("Rebirths") == 1 and p1:GetAttribute("RebirthTokens") == 1 and p1:GetAttribute("RebirthBestLevel") == nil and p1:GetAttribute("UpgradeLevel_GeneratorPower") == nil)
check("la columna de la lista de jugadores marca 1", p1:FindFirstChild("leaderstats"):FindFirstChild("Renacimientos").Value == 1)
local broadcast = PetService.Broadcasts[#PetService.Broadcasts]
check("aviso a todos: quién y cuántos", broadcast and broadcast.Name == "RebirthEvent" and broadcast.Args[1] == 1 and broadcast.Args[2] == "Ana" and broadcast.Args[3] == 1)
check("inventario de mascotas reenviado (espacios al día)", PetService.Pushed == pushedBefore + 1)
advance(0)
local saved = record(1)
check("guardado en seguida: Version 15 y Rebirth en el registro", saved and saved.Version == 15 and saved.Rebirth and saved.Rebirth.Count == 1 and saved.Rebirth.Tokens == 1)

fireServer("Rebirth", p1)
advance(0)
args = lastResult("RebirthResult", p1)
check("otra petición en seguida: TooFast (protección)", args[1] == false and args[2] == Codes.TooFast)
RebirthConfig.Enabled = false

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
check("la tienda funciona aunque renacer esté bloqueado: Golpe renacido nivel 1", args[1] == true and args[4].ItemId == "Strike" and args[4].Level == 1 and args[4].Cost == 1 and p1:GetAttribute("RebirthTokens") == 0 and p1:GetAttribute("RebirthShop") == "Strike=1")
profile.PetData.Rebirth.Tokens = 3
pushedBefore = PetService.Pushed
advance(1)
fireServer("RebirthShop", p1, "PetSlot")
advance(0)
check("Espacio de mascota: 4 equipadas y el inventario se reenvía", p1:GetAttribute("MaxEquipped") == 4 and PetService.Pushed == pushedBefore + 1)
check("daño del jugador: ×1.1 por el renacimiento y ×1.15 por Golpe renacido", near(RebirthLogic.damageMultiplier(profile.PetData.Rebirth), 1.1 * 1.15))

print("-- 7. Recarga: espacios y sin offline")
exit = function(player)
	leave(player)
	advance(0)
end
exit(p1)
storeData.player_2 = {
	Version = 4,
	Energy = 0,
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
storeData.player_4 = { Version = 4, Energy = 10, Rebirth = { Count = 1, Tokens = 0, Shop = { Loot = 1, FutureThing = 2 }, LastAt = 5 } }
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
