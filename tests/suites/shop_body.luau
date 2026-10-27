-- Esta batería prueba la producción pasiva y offline (cristal y núcleos), que sigue en el
-- código detrás de EconomyConfig.PassiveEnergy: se enciende para comprobarla.
EconomyConfig.PassiveEnergy = true
-- Premios y tienda: RewardLogic, MonetizationLogic, EggLogic (abrir varios, regalo, mejor
-- huevo) y la semana de LeaderboardLogic (puras), y RewardService y ShopService REALES con
-- PlayerDataService y SaveService reales sobre un DataStore en memoria (pases simulados de
-- Roblox, recibos de compras sueltas y mejora automática).

local Codes = Constants.PurchaseCodes
local failures = 0
local function check(name, ok)
	if not ok then
		failures += 1
	end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local function record(userId)
	return storeData["player_" .. userId]
end
local function count(map)
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

print("-- 1. Racha diaria (pura)")
local r = RewardLogic.empty()
local D = 20500
local s = RewardLogic.status(r, D)
check("sin reclamar nunca: hay premio, día 1, sin racha rota", s.CanClaim and s.Day == 1 and s.NextStreak == 1 and not s.Broken)
local code, day = RewardLogic.claim(r, D)
check("reclamar: día 1, racha 1, LastDay = hoy", code == "Success" and day == 1 and r.Streak == 1 and r.LastDay == D and r.Claims == 1)
code = RewardLogic.claim(r, D)
check("dos veces el mismo día: AlreadyClaimed y nada cambia", code == "AlreadyClaimed" and r.Streak == 1 and r.Claims == 1)
code, day = RewardLogic.claim(r, D + 1)
check("al día siguiente: día 2", code == "Success" and day == 2 and r.Streak == 2)
s = RewardLogic.status(r, D + 3)
check("tras saltarse un día: vuelve al día 1 y avisa de la racha perdida", s.CanClaim and s.Day == 1 and s.Broken and s.Streak == 0)
for offset = 3, 9 do
	RewardLogic.claim(r, D + offset)
end
check("7 días seguidos: el 7.º es el gran premio y el 8.º vuelve a la casilla 1", r.Streak == 7 and RewardLogic.cycleDay(7) == 7 and RewardLogic.status(r, D + 10).Day == 1 and RewardLogic.status(r, D + 10).NextStreak == 8)
check("el día 7 da mascota y 💰", RewardLogic.streakReward(7).Pet == true and RewardLogic.streakReward(7).Money ~= nil)
local future = RewardLogic.empty()
future.Streak, future.LastDay = 3, D + 5
check("reloj atrasado (último premio «en el futuro»): no se reclama", RewardLogic.claim(future, D) == "AlreadyClaimed" and future.Streak == 3)
check("💰: N minutos del 💰/min de la mejor zona, nunca menos del mínimo", RewardLogic.moneyAmount({ Minutes = 10, Min = 500 }, 0) == 500 and RewardLogic.moneyAmount({ Minutes = 10, Min = 500 }, 700) == 7000 and RewardLogic.moneyAmount({ Minutes = 10, Min = 500 }, 0 / 0) == 500)
do
	local fake = { Money = 0, PetData = { UnlockedZones = {}, Bosses = {} } }
	local forestRate = ZoneLogic.bestMoneyPerMinute(fake, ZoneConfig)
	table.insert(fake.PetData.UnlockedZones, "EmberCaldera")
	local calderaRate = ZoneLogic.bestMoneyPerMinute(fake, ZoneConfig)
	check("💰/min: el del Bosque al empezar y el de la mejor zona abierta después", forestRate == ZoneConfig.Zones.Forest.MoneyPerMinute and calderaRate == ZoneConfig.Zones.EmberCaldera.MoneyPerMinute)
end
local dirty = RewardLogic.sanitize({ Streak = -4, LastDay = "ayer", Claims = 1 / 0, Codes = { OK = true, [5] = true, MAL = "sí", ["DEMASIADOLARGODEMASIADOLARGO"] = true } })
check("saneado: números raros a 0 y solo códigos válidos", dirty.Streak == 0 and dirty.LastDay == 0 and dirty.Claims == 0 and dirty.Codes.OK == true and count(dirty.Codes) == 1)

print("-- 2. Códigos (puros)")
check("normaliza: minúsculas, espacios y signos", RewardLogic.normalizeCode(" bien-venido! ") == "BIENVENIDO" and RewardLogic.normalizeCode("") == nil and RewardLogic.normalizeCode(42) == nil and RewardLogic.normalizeCode("ñ") == nil)
local testCodes = {
	HOLA = { Reward = { Money = { Minutes = 1, Min = 10 } } },
	VIEJO = { Reward = {}, Until = { Year = 2020, Month = 1, Day = 1 } },
	VIP = { Reward = {}, MinRebirths = 2 },
	FIN = { Reward = {}, Until = { Year = 2027, Month = 1, Day = 31 } },
}
local cd = RewardLogic.empty()
local c1, def1 = RewardLogic.redeem(cd, testCodes, "hola", 1801439000, 0)
local c2 = RewardLogic.redeem(cd, testCodes, "HOLA", 1801439000, 0)
check("canjear: Success y queda marcado; otra vez: AlreadyRedeemed", c1 == "Success" and def1 == testCodes.HOLA and cd.Codes.HOLA and c2 == "AlreadyRedeemed")
check("inventado: InvalidCode (sin marcar nada)", RewardLogic.redeem(cd, testCodes, "NOEXISTE", 0, 0) == "InvalidCode" and count(cd.Codes) == 1)
check("caducado: Expired", RewardLogic.redeem(cd, testCodes, "VIEJO", 1801439000, 0) == "Expired")
local cr, need = RewardLogic.redeem(cd, testCodes, "VIP", 0, 1)
check("pide renacimientos: RebirthLocked con los que pide", cr == "RebirthLocked" and need == 2 and not cd.Codes.VIP)
check("último día válido hasta las 23:59:59 UTC", not RewardLogic.isExpired(testCodes.FIN, 1801439999) and RewardLogic.isExpired(testCodes.FIN, 1801440000))
local realOk = true
for name, codeDef in CodesConfig do
	realOk = realOk and RewardLogic.normalizeCode(name) == name and type(codeDef.Reward) == "table"
	if codeDef.Reward.Blessings then
		for blessingId in codeDef.Reward.Blessings do
			realOk = realOk and AdventureConfig.Blessings[blessingId] ~= nil
		end
	end
end
for _, reward in RewardConfig.Streak do
	for blessingId in reward.Blessings or {} do
		realOk = realOk and AdventureConfig.Blessings[blessingId] ~= nil
	end
end
check("CodesConfig y la racha: nombres válidos y bendiciones que existen", realOk)

print("-- 3. Tienda (pura)")
local passes = MonetizationLogic.parsePasses("DoubleEnergy,Inventado,PetSpace")
check("pases desde el atributo (ignora los que no existen) y de vuelta en orden", passes.DoubleEnergy and passes.PetSpace and not passes.Inventado and MonetizationLogic.passesText(passes) == "DoubleEnergy,PetSpace")
check("Energía ×2", MonetizationLogic.energyMultiplier(passes) == 2 and MonetizationLogic.energyMultiplier({}) == 1 and MonetizationLogic.energyMultiplier(nil) == 1)
check("Más mascotas: +2 equipadas (con las del renacimiento) y +60 de inventario",
	MonetizationLogic.maxEquipped(nil, passes, 3) == 5 and MonetizationLogic.maxEquipped({ Shop = { PetSlot = 2 } }, passes, 3) == 7 and MonetizationLogic.maxInventory(passes, 60) == 120 and MonetizationLogic.maxInventory({}, 60) == 60)
check("tope de equipadas para dibujar: 3 + 2 del renacimiento + 2 del pase", MonetizationLogic.maxEquippedCap(3) == 7)
check("Abrir ×3 solo con el pase (pedir 3 sin él abre 1)", MonetizationLogic.hatchCount({ TripleHatch = true }, 3) == 3 and MonetizationLogic.hatchCount({}, 3) == 1 and MonetizationLogic.hatchCount({ TripleHatch = true }, 7) == 1)
check("Disparo automático solo con el pase", MonetizationLogic.autoFire({ AutoFire = true }) and not MonetizationLogic.autoFire({}) and not MonetizationLogic.autoFire(nil) and MonetizationConfig.GamePasses.AutoFire ~= nil)
local shopData = MonetizationLogic.sanitize({ Receipts = { "a", "a", 5, "b" }, AutoUpgrade = false })
check("saneado: recibos únicos y el interruptor guardado", #shopData.Receipts == 2 and shopData.AutoUpgrade == false and MonetizationLogic.sanitize(nil).AutoUpgrade == true)
for index = 1, MonetizationConfig.MaxReceipts + 5 do
	MonetizationLogic.addReceipt(shopData, "r" .. index)
end
check("recibos: se recuerdan los últimos " .. MonetizationConfig.MaxReceipts, #shopData.Receipts == MonetizationConfig.MaxReceipts and MonetizationLogic.hasReceipt(shopData, "r" .. (MonetizationConfig.MaxReceipts + 5)) and not MonetizationLogic.hasReceipt(shopData, "a"))
check("💎 de una bolsa: su Min (y 0 si no es válido)", MonetizationLogic.productEnergy(MonetizationConfig.Products.EnergySmall) == MonetizationConfig.Products.EnergySmall.Min and MonetizationLogic.productEnergy({ Min = 0 / 0 }) == 0)
local petProductsOk = true
for petId in MonetizationConfig.PetProducts do
	local pet = PetConfig.Pets[petId]
	petProductsOk = petProductsOk and pet ~= nil and pet.Rarity == "Exclusive" and pet.EvolvesInto == nil
end
for _, egg in EggConfig.Eggs do
	for _, chance in egg.Chances or {} do
		petProductsOk = petProductsOk and MonetizationConfig.PetProducts[chance.PetId] == nil
	end
end
check("mascotas exclusivas: existen, rareza Exclusiva, sin evolución y ningún huevo las da", petProductsOk and MonetizationConfig.PetProducts[EggConfig.Gardens.Forest.FeaturedPet] ~= nil)
local haxigatorId = MonetizationConfig.PetProducts.Haxigator.Id
MonetizationConfig.PetProducts.Haxigator.Id = 301
check("producto de mascota: da su PetId y no se confunde con la energía", MonetizationLogic.petProductById(301) == "Haxigator" and MonetizationLogic.productById(301) == nil and MonetizationLogic.petProductById(0) == nil and MonetizationLogic.petProductById(201) == nil)
MonetizationConfig.PetProducts.Haxigator.Id = haxigatorId

print("-- 4. Huevos: varios a la vez, regalo y mejor huevo (puros)")
local function eggProfile(energy, level, zones, pets)
	local list = {}
	for index = 1, pets or 0 do
		table.insert(list, { Uid = tostring(index), PetId = "Sproutling" })
	end
	return { Money = energy, Energy = 0, UpgradeLevels = { GeneratorPower = level }, PetData = { Pets = list, Equipped = {}, NextPetUid = (pets or 0) + 1, UnlockedZones = zones or {} } }
end
local limits = { MaxInventory = 60, MaxEquipped = 3, UnlockUpgradeId = "GeneratorPower" }
local forest = EggConfig.Eggs.ForestEgg
local poor = eggProfile(forest.Cost * 2, 0)
check("×3 sin 💰 para los tres: no cobra ni da nada", EggLogic.purchaseMany(poor, forest, { 1, 2, 3 }, limits, Codes) == Codes.InsufficientMoney and poor.Money == forest.Cost * 2 and #poor.PetData.Pets == 0)
local full = eggProfile(1e6, 0, nil, 58)
check("×3 sin sitio para las tres: InventoryFull", EggLogic.purchaseMany(full, forest, { 1, 2, 3 }, limits, Codes) == Codes.InventoryFull and #full.PetData.Pets == 58)
local rich = eggProfile(1e6, 0)
local mc, grants = EggLogic.purchaseMany(rich, forest, { 1, 50, 99 }, limits, Codes)
check("×3: cobra 3 veces, 3 mascotas, Uids distintos y se equipan las que caben", mc == Codes.Success and #grants == 3 and rich.Money == 1e6 - forest.Cost * 3 and #rich.PetData.Pets == 3 and #rich.PetData.Equipped == 3 and grants[1].Uid ~= grants[2].Uid and grants[2].Uid ~= grants[3].Uid)
local single = eggProfile(forest.Cost, 0)
check("abrir uno sigue igual (purchase)", select(1, EggLogic.purchase(single, forest, 10, limits, Codes)) == Codes.Success and single.Money == 0)
local gift = eggProfile(0, 0)
local gc, gg = EggLogic.grantFree(gift, forest, 10, limits, Codes)
check("regalo: sin cobrar", gc == Codes.Success and gg and gift.Money == 0 and #gift.PetData.Pets == 1)
check("regalo con el inventario lleno: InventoryFull", EggLogic.grantFree(eggProfile(0, 0, nil, 60), forest, 10, limits, Codes) == Codes.InventoryFull)
local paid = eggProfile(0, 0, nil, 60)
local paidGrant = EggLogic.grantPet(paid.PetData, "Haxigator", 3)
check("mascota pagada con Robux: se entrega aunque el inventario esté lleno, sin cobrar 💰", paidGrant.PetId == "Haxigator" and #paid.PetData.Pets == 61 and paid.Money == 0 and paidGrant.AutoEquipped)
-- Los huevos del bosque no piden nivel; los de las otras zonas están apagados (Enabled = false)
-- y, encendidos, piden su zona desbloqueada.
local eggsOn = { Eggs = table.clone(EggConfig.Eggs) }
for id, egg in eggsOn.Eggs do
	eggsOn.Eggs[id] = table.clone(egg)
	eggsOn.Eggs[id].Enabled = true
end
check("mejor huevo: el más caro que ya puede abrir", EggLogic.bestEgg(eggProfile(0, 0), EggConfig, limits, Codes) == "AncientEgg"
	and EggLogic.bestEgg(eggProfile(0, 0, { "CrystalValley", "EmberCaldera" }), EggConfig, limits, Codes) == "AncientEgg"
	and EggLogic.bestEgg(eggProfile(0, 0, { "CrystalValley" }), eggsOn, limits, Codes) == "CrystalEgg" and EggLogic.bestEgg(eggProfile(0, 0, { "CrystalValley", "EmberCaldera" }), eggsOn, limits, Codes) == "MagmaEgg")

print("-- 5. Semana (pura)")
local monday = 1792368000 -- lunes 19 de octubre de 2026, 00:00 UTC
local week = LeaderboardLogic.weekOf(monday)
check("la semana cambia el lunes a las 00:00 UTC", LeaderboardLogic.weekOf(monday - 1) == week - 1 and LeaderboardLogic.weekOf(monday + 6 * 86400 + 86399) == week and LeaderboardLogic.weekEndsAt(week) == monday + 7 * 86400)
local weekly = LeaderboardLogic.emptyWeekly()
LeaderboardLogic.addWeekly(weekly, week, 100)
LeaderboardLogic.addWeekly(weekly, week, 50)
LeaderboardLogic.addWeekly(weekly, week, -5)
LeaderboardLogic.addWeekly(weekly, week, 0 / 0)
check("suma la energía de la semana (ignora valores raros)", weekly.Week == week and weekly.Energy == 150 and LeaderboardLogic.weeklyValue(weekly, week) == 150)
LeaderboardLogic.addWeekly(weekly, week - 1, 30)
check("reloj atrasado: se suma a la semana guardada", weekly.Week == week and weekly.Energy == 180)
LeaderboardLogic.addWeekly(weekly, week + 1, 10)
check("semana nueva: empieza de cero", weekly.Week == week + 1 and weekly.Energy == 10 and LeaderboardLogic.weeklyValue(weekly, week) == 0)
check("valor para la clasificación global: entero >= 0", LeaderboardLogic.storeValue(12.7) == 12 and LeaderboardLogic.storeValue(-1) == nil and LeaderboardLogic.storeValue(0 / 0) == nil and LeaderboardLogic.storeValue(1e20) == 1e15)
check("saneado de la semana", LeaderboardLogic.sanitizeWeekly({ Week = "x" }).Week == 0 and LeaderboardLogic.sanitizeWeekly({ Week = 3, Energy = 5 }).Energy == 5)

-- Servicios reales ---------------------------------------------------------------------------
local Market = PetService.Market
MonetizationConfig.GamePasses.DoubleEnergy.Id = 101
MonetizationConfig.GamePasses.AutoUpgrade.Id = 102
MonetizationConfig.GamePasses.TripleHatch.Id = 103
MonetizationConfig.GamePasses.PetSpace.Id = 104
MonetizationConfig.Products.EnergySmall.Id = 201

QuestLogic.init(QuestConfig, EnemyConfig, Economy)
ShopService.start()
PlayerDataService.start()
UpgradeService.start()
QuestService.start()
AdventureService.start()
RewardService.start()
-- Jugadores con la señal CharacterAdded (la usa AdventureService).
local baseNewPlayer = newPlayer
newPlayer = function(name, userId)
	local player = baseNewPlayer(name, userId)
	player.CharacterAdded = signal()
	return player
end
local now = os.time()
RewardService.setClock(function()
	return now
end)

print("-- 6. RewardService real")
local p1 = newPlayer("Ana", 1)
join(p1)
advance(1)
check("al cargar: premio disponible (insignia DailyReady)", p1:GetAttribute("DailyReady") == true)
local state = lastResult("RewardState", p1)
local day1Money = RewardLogic.moneyAmount(RewardConfig.Streak[1].Money, ZoneLogic.bestMoneyPerMinute(PlayerDataService.get(p1), ZoneConfig))
check("estado al cliente: día 1 con el 💰 calculado", state and state[1].Ready and state[1].CanClaim and state[1].Day == 1 and state[1].Days[1].Money == day1Money and day1Money >= RewardConfig.Streak[1].Money.Min)
local before = PlayerDataService.get(p1).Money
fireServer("RewardAction", p1, "Claim")
advance(1)
local result = lastResult("RewardResult", p1)
check("reclamar: Success, el 💰 del día 1 y se guarda en seguida", result and result[1] == true and result[3] == "Claim" and result[4].Money == day1Money and PlayerDataService.get(p1).Money >= before + day1Money and record(1) and record(1).Rewards and record(1).Rewards.Streak == 1)
check("después: sin premio hasta mañana", p1:GetAttribute("DailyReady") == false)
fireServer("RewardAction", p1, "Claim")
advance(2)
result = lastResult("RewardResult", p1)
check("otra vez hoy: AlreadyClaimed", result and result[1] == false and result[2] == Codes.AlreadyClaimed)
now += 86400
fireServer("RewardAction", p1, "Claim")
advance(2)
now += 86400
fireServer("RewardAction", p1, "Claim")
advance(2)
result = lastResult("RewardResult", p1)
local adventure = PlayerDataService.get(p1).PetData.Adventure
check("día 3: Bendición de Abundancia guardada sin activar", result and result[1] == true and result[4].Day == 3 and result[4].Blessings and result[4].Blessings.Abundance == 1 and adventure.Blessings.Abundance == 1 and adventure.Active.Abundance == nil)
for _ = 4, 7 do
	now += 86400
	fireServer("RewardAction", p1, "Claim")
	advance(2)
end
result = lastResult("RewardResult", p1)
local p1Pets = PlayerDataService.get(p1).PetData.Pets
check("día 7: mascota del mejor huevo (además de la inicial) y 💰", result and result[1] == true and result[4].Day == 7 and type(result[4].PetId) == "string" and result[4].Money and #p1Pets == 2 and p1Pets[2].PetId == result[4].PetId)

print("-- 7. Códigos en el servidor")
fireServer("RewardAction", p1, "Redeem", "  bienvenido ")
advance(3)
result = lastResult("RewardResult", p1)
check("BIENVENIDO: 💰 y bendición", result and result[1] == true and result[3] == "Redeem" and result[4].Code == "BIENVENIDO" and result[4].Money and result[4].Blessings.Abundance == 1)
fireServer("RewardAction", p1, "Redeem", "BIENVENIDO")
advance(3)
result = lastResult("RewardResult", p1)
check("otra vez: AlreadyRedeemed", result and result[1] == false and result[2] == Codes.AlreadyRedeemed)
fireServer("RewardAction", p1, "Redeem", "CALDERA")
advance(3)
result = lastResult("RewardResult", p1)
check("CALDERA sin renacer: RebirthLocked (pide 1)", result and result[2] == Codes.RebirthLocked and result[4].Required == 1)
fireServer("RewardAction", p1, "Redeem", "NADA")
fireServer("RewardAction", p1, "Redeem", "NADA2")
advance(0.1)
result = lastResult("RewardResult", p1)
check("intentos muy seguidos: TooFast", result and result[2] == Codes.TooFast)
advance(3)
check("los códigos canjeados se guardan", record(1).Rewards.Codes.BIENVENIDO == true)

print("-- 8. Pases (ShopService real)")
Market.Owned[2] = { [101] = true, [104] = true }
local p2 = newPlayer("Beto", 2)
join(p2)
advance(2)
local profile2 = PlayerDataService.get(p2)
check("consulta a Roblox: tiene Energía ×2 y Más mascotas", profile2.PassesChecked and profile2.Passes.DoubleEnergy and profile2.Passes.PetSpace and not profile2.Passes.TripleHatch and p2:GetAttribute("Passes") == "DoubleEnergy,PetSpace")
check("💎 ×2 y 5 mascotas equipadas, 120 de inventario", PlayerDataService.diamondMultiplier(profile2) == 2 and p2:GetAttribute("MaxEquipped") == 5 and p2:GetAttribute("MaxInventory") == 120)
-- Sin el pase: las equipadas de más se quitan al saber sus pases.
storeData.player_3 = { Version = 5, Pets = { { Uid = "1", PetId = "Sproutling" }, { Uid = "2", PetId = "Sproutling" }, { Uid = "3", PetId = "Sproutling" }, { Uid = "4", PetId = "Sproutling" }, { Uid = "5", PetId = "Sproutling" } }, Equipped = { "1", "2", "3", "4", "5" }, NextPetUid = 6 }
local p3 = newPlayer("Caro", 3)
join(p3)
advance(2)
check("sin «Más mascotas»: quedan 3 equipadas (las demás siguen en el inventario)", #PlayerDataService.get(p3).PetData.Equipped == 3 and #PlayerDataService.get(p3).PetData.Pets == 5)
Market.Fail = 100
Market.Owned[4] = { [101] = true }
local p4 = newPlayer("Dani", 4)
join(p4)
advance(10)
check("si Roblox falla al comprobar: sin el pase (no se inventa) y se puede jugar", PlayerDataService.get(p4).PassesChecked and not PlayerDataService.get(p4).Passes.DoubleEnergy)
Market.Fail = 0
Market.PromptGamePassPurchaseFinished:Fire(p3, 103, true)
advance(0.1)
local shopResult = lastResult("ShopResult", p3)
check("comprar un pase en la partida: se aplica al momento y se avisa", PlayerDataService.get(p3).Passes.TripleHatch == true and p3:GetAttribute("Passes") == "TripleHatch" and shopResult and shopResult[1] == "Pass" and shopResult[2] == "TripleHatch")
Market.PromptGamePassPurchaseFinished:Fire(p3, 104, false)
advance(0.1)
check("ventana cerrada sin comprar: nada cambia", not PlayerDataService.get(p3).Passes.PetSpace)

print("-- 9. Compras sueltas (recibos)")
local energyBefore = PlayerDataService.get(p3).Energy
local receipt = { PlayerId = 3, ProductId = 201, PurchaseId = "compra-1" }
local decision = Market.ProcessReceipt(receipt)
local gained = PlayerDataService.get(p3).Energy - energyBefore
check("se concede la energía y se confirma con la compra guardada", decision == "PurchaseGranted" and gained == MonetizationConfig.Products.EnergySmall.Min and table.find(record(3).Shop.Receipts, "compra-1") ~= nil)
check("el mismo recibo otra vez: confirmado sin dar más", Market.ProcessReceipt(receipt) == "PurchaseGranted" and PlayerDataService.get(p3).Energy - energyBefore == gained)
check("jugador que no está: NotProcessedYet (Roblox reintenta)", Market.ProcessReceipt({ PlayerId = 99, ProductId = 201, PurchaseId = "x" }) == "NotProcessedYet")
check("producto que no existe: NotProcessedYet", Market.ProcessReceipt({ PlayerId = 3, ProductId = 999, PurchaseId = "y" }) == "NotProcessedYet")
-- Con fallos el guardado espera entre intentos: la compra se procesa en su propia tarea.
local function receiptAsync(data)
	local out = {}
	task.spawn(function()
		out.Decision = Market.ProcessReceipt(data)
	end)
	advance(10)
	return out.Decision
end
storeFail = 3
energyBefore = PlayerDataService.get(p3).Energy
local failed = receiptAsync({ PlayerId = 3, ProductId = 201, PurchaseId = "compra-2" })
check("si no se puede guardar: NotProcessedYet", failed == "NotProcessedYet")
storeFail = 0
local retried = receiptAsync({ PlayerId = 3, ProductId = 201, PurchaseId = "compra-2" })
check("al reintentar: confirmada sin conceder dos veces", retried == "PurchaseGranted" and PlayerDataService.get(p3).Energy - energyBefore == MonetizationConfig.Products.EnergySmall.Min)

-- Armas con Robux (botón morado de su tarjeta en la Armería)
WeaponService.start()
MonetizationConfig.WeaponProducts.CrystalCannon.Id = 401
local weapons3 = PlayerDataService.get(p3).PetData.Weapons
check("producto de arma: da su arma y no se confunde con los demás", MonetizationLogic.weaponProductById(401) == "CrystalCannon" and MonetizationLogic.productById(401) == nil and MonetizationLogic.petProductById(401) == nil and MonetizationLogic.weaponProductById(0) == nil)
local weaponDecision = Market.ProcessReceipt({ PlayerId = 3, ProductId = 401, PurchaseId = "arma-1" })
advance(0.1)
local weaponNotice = lastResult("WeaponResult", p3)
check("arma con Robux: llega con su zona cerrada, se equipa, se guarda y se avisa", weaponDecision == "PurchaseGranted" and weapons3.Owned.CrystalCannon == true and weapons3.Equipped == "CrystalCannon"
	and p3:GetAttribute("EquippedWeapon") == "CrystalCannon" and weaponNotice and weaponNotice[2] == "Robux" and table.find(record(3).Shop.Receipts, "arma-1") ~= nil)
weapons3.Equipped = "Laser"
check("el mismo recibo de arma otra vez: confirmado sin volver a darla", Market.ProcessReceipt({ PlayerId = 3, ProductId = 401, PurchaseId = "arma-1" }) == "PurchaseGranted" and weapons3.Equipped == "Laser")
MonetizationConfig.WeaponProducts.CrystalCannon.Id = 0

print("-- 10. Mejora automática")
Market.Owned[5] = { [102] = true }
local p5 = newPlayer("Eva", 5)
join(p5)
advance(2)
local profile5 = PlayerDataService.get(p5)
local weapons5 = profile5.PetData.Weapons
local gun5 = WeaponLogic.equippedFor(weapons5, "Weapons")
local function level(id) return WeaponLogic.level(weapons5, id) end
profile5.Money = 1e7
advance(1.5)
local level5 = level(gun5)
check("con el pase se mejora sola el arma equipada con 💰 (hasta 5 por tick)", level5 >= 5 and level5 <= 5 * 2 and profile5.Money < 1e7 and p5:GetAttribute("AutoUpgrade") == true and profile5.UpgradeLevels.GeneratorPower == 0)
profile5.PetData.Style = "Fists"
local gloves5 = WeaponLogic.equippedFor(weapons5, "Fists")
local gunBefore = level(gun5)
advance(1.5)
check("con Puños se mejoran los guantes, no el arma", level(gloves5) >= 1 and level(gun5) == gunBefore)
fireServer("ShopAction", p5, "SetAuto", false)
advance(0.1)
profile5.Money = 1e7
local glovesOff = level(gloves5)
advance(3)
check("apagada: no sube y el interruptor se guarda", level(gloves5) == glovesOff and profile5.PetData.Shop.AutoUpgrade == false and p5:GetAttribute("AutoUpgrade") == false)
fireServer("ShopAction", p5, "SetAuto", "sí")
advance(0.6)
check("interruptor con un valor raro: se ignora", profile5.PetData.Shop.AutoUpgrade == false)
local profile1 = PlayerDataService.get(p1)
local gun1 = WeaponLogic.equippedFor(profile1.PetData.Weapons, "Weapons")
local level1 = WeaponLogic.level(profile1.PetData.Weapons, gun1)
profile1.Money = 1e7
advance(2)
check("sin el pase: nunca sube sola", WeaponLogic.level(profile1.PetData.Weapons, gun1) == level1)

print("-- 11. Producción offline con Energía ×2")
Market.Owned[6] = { [101] = true }
storeData.player_6 = { Version = 5, LastSeen = os.time() - 2 * 3600, Energy = 0 }
local p6 = newPlayer("Fede", 6)
join(p6)
advance(10)
local profile6 = PlayerDataService.get(p6)
local base6 = CoreLogic.offlineReward(profile6.PetData.Cores, profile6.UpgradeLevels, profile6.PetMultiplier, os.time() - 2 * 3600 - 10, os.time() - 10, 0)
local offline = p6:GetAttribute("OfflineReward")
check("la offline espera a saber los pases y se dobla", offline ~= nil and tonumber(string.split(offline, ",")[1]) == math.floor(base6 * 2))

print("-- Cofres escondidos (ChestService real)")
ChestService.startRemotes()
ChestService.setClock(function()
	return now
end)
local chestDef = ChestConfig.get("Waterfall")
local chestProfile = PlayerDataService.get(p1)
local chestBefore = chestProfile.Money
local blessingsBefore = chestProfile.PetData.Adventure.Blessings.Abundance or 0
local chestCode, chestDetail = ChestService.open(p1, "Waterfall")
local chestEnergy = RewardLogic.moneyAmount(chestDef.Reward.Money, ZoneLogic.bestMoneyPerMinute(chestProfile, ZoneConfig))
check("cofre: se abre con su 💰 y su bendición", chestCode == Codes.Success and chestDetail.Money == chestEnergy and chestProfile.Money == chestBefore + chestEnergy and chestDetail.Blessings and chestDetail.Blessings.Abundance == 1 and chestProfile.PetData.Adventure.Blessings.Abundance == blessingsBefore + 1)
check("cofre: cuenta los abiertos (1 de todos)", chestDetail.Opened == 1 and chestDetail.Total == #ChestConfig.Chests and chestDetail.ReadyAt == now + ChestConfig.Cooldown)
advance(1)
check("cofre: la espera se guarda en seguida", record(1).Rewards.Chests and record(1).Rewards.Chests.Waterfall == now + ChestConfig.Cooldown)
local chestAgain = ChestService.open(p1, "Waterfall")
check("cofre: otra vez durante la espera -> ChestCooldown y nada más", chestAgain == Codes.ChestCooldown and chestProfile.Money == chestBefore + chestEnergy)
check("cofre: id que no existe -> InvalidRequest", ChestService.open(p1, "Tesoro") == Codes.InvalidRequest and ChestService.open(p1, 42) == Codes.InvalidRequest)
local chestStranger = newPlayer("Nadie", 77)
check("cofre: jugador sin datos cargados -> NotReady", ChestService.open(chestStranger, "Ruins") == Codes.NotReady)
fireServer("RequestChests", p1)
advance(1)
local chestState = lastResult("ChestState", p1)
check("cofre: el cliente recibe sus esperas", chestState and chestState[1].Waterfall == now + ChestConfig.Cooldown and chestState[1].Ruins == nil and chestState[2] == now)
now += ChestConfig.Cooldown
check("cofre: pasada la espera se vuelve a abrir", (ChestService.open(p1, "Waterfall")) == Codes.Success)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
