-- Fase 2 de los núcleos: CoreLogic (afinidad y mejora) y el CoreService REAL con el
-- PlayerDataService y el SaveService reales sobre un DataStore en memoria.
-- Desbloquear, mejorar y elegir: validación, cobro en el mismo paso, producción,
-- atributos, guardado y estado al cliente. Y la producción offline al cargar.
QuestLogic.init(QuestConfig, EnemyConfig, Economy)
PlayerDataService.start()
UpgradeService.start()
QuestService.start()
CoreService.start()

local failures = 0
local function check(name, ok)
	if not ok then failures += 1 end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local function record(userId) return storeData["player_" .. userId] end
local function enter(name, userId)
	local player = newPlayer(name, userId)
	join(player)
	advance(0)
	return player, PlayerDataService.get(player)
end
local function exit(player)
	leave(player)
	advance(0)
end
local function act(player, action, elementId)
	advance(0.4) -- por encima del enfriamiento de compras (0.3 s)
	fireServer("CoreAction", player, action, elementId)
	advance(0)
	return lastResult("CoreResult", player)
end
local function near(a, b) return math.abs(a - b) < 1e-9 end

print("-- 1. CoreLogic: afinidad, producción a un nivel y mejora")
local data = CoreLogic.empty()
local levels = { GeneratorPower = 5 }
check("productionAt: Naturaleza = Economy; Agua nivel 0 = 2; Agua nivel 3 = 8; nivel fuera de rango acotado",
	CoreLogic.productionAt("Nature", 5) == Economy.getProductionPerSecond({ GeneratorPower = 5 })
		and CoreLogic.productionAt("Water", 0) == 2 and CoreLogic.productionAt("Water", 3) == 8
		and CoreLogic.productionAt("Water", 999) == CoreLogic.productionAt("Water", CoreConfig.Upgrade.MaxLevel)
		and CoreLogic.productionAt("Water", 0 / 0) == 2 and CoreLogic.productionAt("Plasma", 1) == 0)
check("solo Naturaleza: effectiveProduction = Economy · mascotas (la economía de siempre)",
	CoreLogic.effectiveProduction(data, levels, 1.35) == Economy.getProductionPerSecond(levels) * 1.35)
data.Elements.Water.Unlocked = true
data.Elements.Water.Level = 3
check("con Naturaleza seleccionada no hay afinidad", CoreLogic.affinityBonus(data, levels) == 0)
data.Selected = "Water"
local rate = CoreConfig.Affinity.Bonus
check(("afinidad: el núcleo activo produce +%d %%"):format(rate * 100), near(CoreLogic.affinityBonus(data, levels), 8 * rate))
check("effectiveProduction = (base + afinidad) · mascotas; totalProduction sigue sin afinidad",
	near(CoreLogic.effectiveProduction(data, levels, 2), (CoreLogic.baseProduction(data, levels) + 8 * rate) * 2)
		and CoreLogic.totalProduction(data, levels, 2) == CoreLogic.baseProduction(data, levels) * 2)
check("la producción offline no incluye la afinidad",
	CoreLogic.offlineReward(data, levels, 1, 1000, 1100) == math.floor(100 * CoreLogic.baseProduction(data, levels) * CoreConfig.Offline.Efficiency))
data.Selected = "Fire" -- bloqueado (datos sin sanear): sin afinidad ni errores
check("afinidad 0 con un seleccionado bloqueado o datos mal formados", CoreLogic.affinityBonus(data, levels) == 0 and CoreLogic.affinityBonus("x" :: any, levels) == 0)

local u = CoreLogic.empty()
local code, cost = CoreLogic.upgrade(u, "Water", 1e9)
check("mejorar un núcleo bloqueado -> Locked, sin cambios", code == "Locked" and cost == 0 and u.Elements.Water.Level == 0)
code = CoreLogic.upgrade(u, "Nature", 1e9)
local code2 = CoreLogic.upgrade(u, "Plasma", 1e9)
local code3 = CoreLogic.upgrade({} :: any, "Water", 1e9)
check("Naturaleza (se mejora con la Resonancia), desconocido o sin estructura -> InvalidRequest", code == "InvalidRequest" and code2 == "InvalidRequest" and code3 == "InvalidRequest")
u.Elements.Water.Unlocked = true
code, cost = CoreLogic.upgrade(u, "Water", 5)
check("sin energía -> InsufficientEnergy con el coste, sin cambios", code == "InsufficientEnergy" and cost == CoreLogic.upgradeCost("Water", 0) and u.Elements.Water.Level == 0)
code, cost = CoreLogic.upgrade(u, "Water", 1e9)
check("con energía -> Success, nivel 1 y devuelve el coste del nivel 0", code == "Success" and cost == CoreLogic.upgradeCost("Water", 0) and u.Elements.Water.Level == 1)
u.Elements.Water.Level = CoreConfig.Upgrade.MaxLevel
code, cost = CoreLogic.upgrade(u, "Water", 1e15)
check("al máximo -> MaxLevel", code == "MaxLevel" and cost == 0 and u.Elements.Water.Level == CoreConfig.Upgrade.MaxLevel)

local function withAffinity(value)
	local config = table.clone(CoreConfig)
	config.Affinity = value
	return CoreLogic.validateConfig(config, EconomyConfig)
end
check("Affinity es opcional y debe estar entre 0 y 10", withAffinity(nil) and withAffinity({ Bonus = 0 }) and not withAffinity({ Bonus = -1 }) and not withAffinity({ Bonus = 0 / 0 }) and not withAffinity("mucho"))

print("-- 2. Despertar núcleos")
storeData.player_31 = { Version = 3, Energy = 100000, UpgradeLevels = { GeneratorPower = 10 }, Pets = { { Uid = "1", PetId = "MossFox" } }, Equipped = { "1" }, NextPetUid = 2 }
local ana, p = enter("Ana", 31)
advance(1)
p.Energy = 100000 -- los logros ya cumplidos pueden haber sumado energía al entrar
local pets = PetMath.getTotalMultiplier({ "MossFox" })
local before = p.ProductionPerSecond
check("entra con solo Naturaleza: producción de siempre y atributos de núcleos", before == Economy.getProductionPerSecond({ GeneratorPower = 10 }) * pets and ana:GetAttribute("UnlockedCores") == "Nature" and ana:GetAttribute("SelectedCore") == "Nature")
local r = act(ana, "Unlock", "Fire")
check("Fuego antes que Agua -> Locked (desbloqueo secuencial), sin cobrar", r[1] == false and r[2] == "Locked" and p.Energy == 100000)
p.Energy = 4000
r = act(ana, "Unlock", "Water")
check("sin energía suficiente -> InsufficientEnergy con el coste (5 000), sin cambios", r[1] == false and r[2] == "InsufficientEnergy" and r[5] == 5000 and p.Energy == 4000 and not CoreLogic.isUnlocked(p.PetData.Cores, "Water"))
p.Energy = 100000
local writes = storeWrites
r = act(ana, "Unlock", "Water")
check("despertar Agua -> Success, cuesta 5 000", r[1] == true and r[2] == "Success" and r[3] == "Unlock" and r[4] == "Water" and r[5] == 5000 and p.Energy == 95000)
check("la producción sube con la de Agua (2/s · mascotas)", near(p.ProductionPerSecond, (Economy.getProductionPerSecond({ GeneratorPower = 10 }) + 2) * pets))
check("atributos y altar: UnlockedCores = Nature,Water", ana:GetAttribute("UnlockedCores") == "Nature,Water")
check("se guarda al momento (UnlockedAt registrado)", storeWrites > writes and record(31).Cores.Elements.Water.Unlocked == true and record(31).Cores.Elements.Water.UnlockedAt == os.time())
r = act(ana, "Unlock", "Water")
check("despertarlo otra vez -> AlreadyUnlocked, sin cobrar", r[2] == "AlreadyUnlocked" and p.Energy == 95000)

print("-- 3. Mejorar")
local upgradeCost = CoreLogic.upgradeCost("Water", 0)
advance(1)
r = act(ana, "Upgrade", "Water")
check(("mejorar Agua -> nivel 1, cuesta %d"):format(upgradeCost), r[1] == true and r[3] == "Upgrade" and r[5] == upgradeCost and p.PetData.Cores.Elements.Water.Level == 1 and p.Energy == 95000 - upgradeCost)
check("producción de Agua a nivel 1 = 4/s", near(p.ProductionPerSecond, (Economy.getProductionPerSecond({ GeneratorPower = 10 }) + 4) * pets))
advance(1)
r = act(ana, "Upgrade", "Nature")
check("Naturaleza por CoreAction -> InvalidRequest (se mejora con la Resonancia del Cristal)", r[2] == "InvalidRequest" and p.UpgradeLevels.GeneratorPower == 10)

print("-- 4. Elegir el elemento activo (afinidad)")
advance(1)
local base = CoreLogic.baseProduction(p.PetData.Cores, p.UpgradeLevels)
local switchCost = math.max(CoreConfig.Switch.MinCost, math.floor(CoreConfig.Switch.ProductionSeconds * base))
local energyBefore = p.Energy
r = act(ana, "Select", "Water")
check(("elegir Agua -> cuesta 1 min de producción base (%d)"):format(switchCost), r[1] == true and r[3] == "Select" and r[5] == switchCost and p.Energy == energyBefore - switchCost)
check("afinidad: Agua produce +25 % (base + 1 por mascotas)", near(p.ProductionPerSecond, (base + 4 * CoreConfig.Affinity.Bonus) * pets) and ana:GetAttribute("SelectedCore") == "Water")
r = act(ana, "Select", "Water")
check("elegir el que ya está activo -> AlreadySelected", r[2] == "AlreadySelected")
advance(2)
r = act(ana, "Select", "Nature")
check("volver a cambiar antes de 10 s -> TooFast, sin cobrar", r[2] == "TooFast" and ana:GetAttribute("SelectedCore") == "Water")
advance(CoreConfig.Switch.CooldownSeconds)
r = act(ana, "Select", "Nature")
check("pasado el enfriamiento se puede volver a Naturaleza (sin afinidad)", r[1] == true and near(p.ProductionPerSecond, base * pets))
check("sin secundario: atributo vacío", ana:GetAttribute("SecondaryCore") == "")
advance(CoreConfig.Switch.CooldownSeconds)
energyBefore = p.Energy
switchCost = CoreLogic.switchCost(p.PetData.Cores, p.UpgradeLevels)
r = act(ana, "Secondary", "Water")
check("elegir Agua como secundario (R): cobra lo mismo que cambiar y se replica", r[1] == true and r[3] == "Secondary" and p.Energy == energyBefore - switchCost and ana:GetAttribute("SecondaryCore") == "Water")
check("el secundario no da afinidad (solo el principal)", near(p.ProductionPerSecond, base * pets))

print("-- 5. Peticiones no válidas y estado al cliente")
advance(1)
energyBefore = p.Energy
local bad = {
	act(ana, 42, "Water"),
	act(ana, "Steal", "Water"),
	act(ana, "Unlock", 7),
	act(ana, "Unlock", string.rep("x", 200)),
	act(ana, "Unlock", "Plasma"),
}
local allInvalid = true
for _, result in bad do
	if result[1] ~= false then allInvalid = false end
end
check("acción o elemento no válidos -> rechazados, sin cobrar", allInvalid and p.Energy == energyBefore)
check("la respuesta no devuelve textos enormes del cliente", bad[4][4] == nil and bad[1][3] == nil)
fireServer("RequestCores", ana)
advance(0)
local state = lastResult("CoreState", ana)[1]
check("CoreState: 8 núcleos en orden, Agua nivel 1, Fuego disponible, Viento no",
	#state.Elements == 8 and state.Elements[2].Id == "Water" and state.Elements[2].Level == 1
		and state.Elements[3].Available == true and state.Elements[3].UnlockCost == 20000 and state.Elements[4].Available == false)
check("CoreState: producción total, base, afinidad y coste de cambio coherentes con el perfil",
	state.Total == p.ProductionPerSecond and near(state.BaseProduction, base) and state.AffinityProduction == 0
		and state.SwitchCost == CoreLogic.switchCost(p.PetData.Cores, p.UpgradeLevels) and state.Ready == true and state.Secondary == "Water")
check("CoreState: Naturaleza muestra el coste de la Resonancia del Cristal", state.Elements[1].UpgradeCost == Economy.getUpgradeCost("GeneratorPower", 10))

print("-- 6. Límite de frecuencia")
advance(5)
local firedBefore = 0
for _, item in fired do if item.Name == "CoreResult" and item.Player == ana then firedBefore += 1 end end
for _ = 1, 20 do fireServer("CoreAction", ana, "Upgrade", "Water") end
advance(0)
local firedAfter = 0
for _, item in fired do if item.Name == "CoreResult" and item.Player == ana then firedAfter += 1 end end
check(("20 peticiones seguidas: como mucho %d respuestas y una sola mejora"):format(EconomyConfig.PurchaseRateLimit.MaxRequestsPerWindow), firedAfter - firedBefore <= EconomyConfig.PurchaseRateLimit.MaxRequestsPerWindow and p.PetData.Cores.Elements.Water.Level == 2)
exit(ana)
check("al salir se guardan núcleos y energía", record(31).Cores.Elements.Water.Level == 2 and record(31).Cores.Selected == "Nature" and record(31).Cores.Secondary == "Water" and record(31).Energy == p.Energy)

print("-- 7. Datos cargando: no se gasta")
storeData.player_32 = { Version = 3, Energy = 50000, UpgradeLevels = { GeneratorPower = 1 } }
storeLatency = 3
local ben = newPlayer("Ben", 32)
join(ben)
advance(0)
fireServer("CoreAction", ben, "Unlock", "Water")
advance(0)
r = lastResult("CoreResult", ben)
check("mientras carga -> NotReady", r[1] == false and r[2] == "NotReady")
advance(4)
storeLatency = 0
check("al terminar la carga, nada se cobró", PlayerDataService.get(ben).Energy == 50000 and not CoreLogic.isUnlocked(PlayerDataService.get(ben).PetData.Cores, "Water"))
exit(ben)

print("-- 8. Producción offline al cargar")
local now = os.time()
local cores = CoreLogic.empty()
cores.Elements.Water.Unlocked = true
cores.Elements.Water.Level = 2
storeData.player_33 = { Version = 3, Energy = 10, UpgradeLevels = { GeneratorPower = 4 }, Cores = cores, LastSeen = now - 7200,
	Pets = { { Uid = "1", PetId = "MossFox" } }, Equipped = { "1" }, NextPetUid = 2 }
local cid, cp = enter("Cid", 33)
-- Como el servicio: CoreLogic.offlineReward (base de los núcleos · mascotas · 50 %, ya
-- redondeada) por los multiplicadores de renacimiento, amuletos y pases (aquí 1).
local expected = CoreLogic.offlineReward(cores, { GeneratorPower = 4 }, pets, now - 7200, now)
check(("2 h fuera: %d (base de todos los núcleos · mascotas · 50 %%); recibió %d"):format(expected, cp.Energy - 10), cp.Energy == 10 + expected)
check("aviso al cliente: OfflineReward = energía,segundos", cid:GetAttribute("OfflineReward") == ("%d,%d"):format(expected, 7200))
check("se guarda en seguida: LastSeen avanza (no se cobra dos veces)", record(33).LastSeen == os.time() and record(33).Energy == 10 + expected)
check("no cuenta como energía generada para las misiones", (cp.PetData.Quests.Stats.EnergyEarned or 0) == 0)
exit(cid)
cid, cp = enter("Cid", 33)
check("al volver en seguida: sin recompensa nueva", cp.Energy == 10 + expected and cid:GetAttribute("OfflineReward") == nil)
exit(cid)

storeData.player_34 = { Version = 3, Energy = 0, UpgradeLevels = { GeneratorPower = 0 }, LastSeen = now - 10 * 86400 }
local dee, dp = enter("Dee", 34)
-- Sin mascotas guardadas recibe la inicial (Brotecillo), que también cuenta offline
check("10 días fuera: como mucho 4 h", dp.Energy == math.floor(CoreConfig.Offline.CapSeconds * Economy.getProductionPerSecond({ GeneratorPower = 0 }) * PetMath.getTotalMultiplier({ "Sproutling" }) * CoreConfig.Offline.Efficiency))
exit(dee)

storeData.player_35 = { Version = 3, Energy = 5, UpgradeLevels = { GeneratorPower = 3 } }
local eve, ep = enter("Eve", 35)
check("sin LastSeen (partida antigua): nada retroactivo", ep.Energy == 5 and eve:GetAttribute("OfflineReward") == nil)
exit(eve)

storeData.player_36 = { Version = 3, Energy = 5, UpgradeLevels = { GeneratorPower = 3 }, LastSeen = now - 3600 }
storeFail = 99
local fay = newPlayer("Fay", 36)
join(fay)
advance(40)
storeFail = 0
check("carga fallida: sin recompensa (y sin guardar)", PlayerDataService.get(fay).DataState == "Failed" and fay:GetAttribute("OfflineReward") == nil and record(36).Energy == 5)
exit(fay)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
