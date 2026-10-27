-- Con la economía 1: la ⚡ de los registros antiguos de esta batería no se convierte en 💰
-- (su Diamonds cuenta directamente como 💎).
EconomyConfig.Version = 1
local UNLOCK = CoreConfig.Unlock.BaseCost -- despertar Agua
-- Núcleos: CoreLogic (mejora) y el CoreService REAL con el PlayerDataService y el
-- SaveService reales sobre un DataStore en memoria. Desbloquear, mejorar y elegir:
-- validación, cobro en el mismo paso, atributos, guardado y estado al cliente. Los núcleos
-- ya no producen nada (ni conectado ni offline): solo dan sus habilidades.
QuestLogic.init(QuestConfig, EnemyConfig)
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

print("-- 1. CoreLogic: mejora")
local u = CoreLogic.empty()
local code, cost = CoreLogic.upgrade(u, "Water", 1e9)
check("mejorar un núcleo bloqueado -> Locked, sin cambios", code == "Locked" and cost == 0 and u.Elements.Water.Level == 0)
code = CoreLogic.upgrade(u, "Nature", 1e9)
local code2 = CoreLogic.upgrade(u, "Plasma", 1e9)
local code3 = CoreLogic.upgrade({} :: any, "Water", 1e9)
check("Naturaleza (no tiene nivel), desconocido o sin estructura -> InvalidRequest", code == "InvalidRequest" and code2 == "InvalidRequest" and code3 == "InvalidRequest")
u.Elements.Water.Unlocked = true
code, cost = CoreLogic.upgrade(u, "Water", 5)
check("sin 💎 -> InsufficientDiamonds con el coste, sin cambios", code == "InsufficientDiamonds" and cost == CoreLogic.upgradeCost("Water", 0) and u.Elements.Water.Level == 0)
code, cost = CoreLogic.upgrade(u, "Water", 1e9)
check("con 💎 -> Success, nivel 1 y devuelve el coste del nivel 0", code == "Success" and cost == CoreLogic.upgradeCost("Water", 0) and u.Elements.Water.Level == 1)
u.Elements.Water.Level = CoreConfig.Upgrade.MaxLevel
code, cost = CoreLogic.upgrade(u, "Water", 1e15)
check("al máximo -> MaxLevel", code == "MaxLevel" and cost == 0 and u.Elements.Water.Level == CoreConfig.Upgrade.MaxLevel)

print("-- 2. Despertar núcleos")
storeData.player_31 = { Version = 3, Diamonds = 100000, UpgradeLevels = { GeneratorPower = 10 }, Pets = { { Uid = "1", PetId = "MossFox" } }, Equipped = { "1" }, NextPetUid = 2 }
local ana, p = enter("Ana", 31)
advance(1)
p.Diamonds = 100000 -- los logros ya cumplidos pueden haber sumado 💎 al entrar
check("entra con solo Naturaleza y los atributos de los núcleos (sin producción)", p.ProductionPerSecond == nil and ana:GetAttribute("ProductionPerSecond") == nil and ana:GetAttribute("UnlockedCores") == "Nature" and ana:GetAttribute("SelectedCore") == "Nature")
local r = act(ana, "Unlock", "Fire")
check("Fuego antes que Agua -> Locked (desbloqueo secuencial), sin cobrar", r[1] == false and r[2] == "Locked" and p.Diamonds == 100000)
p.Diamonds = UNLOCK - 1
r = act(ana, "Unlock", "Water")
check(("sin 💎 suficientes -> InsufficientDiamonds con el coste (%d), sin cambios"):format(UNLOCK), r[1] == false and r[2] == "InsufficientDiamonds" and r[5] == UNLOCK and p.Diamonds == UNLOCK - 1 and not CoreLogic.isUnlocked(p.PetData.Cores, "Water"))
p.Diamonds = 100000
local writes = storeWrites
r = act(ana, "Unlock", "Water")
check(("despertar Agua -> Success, cuesta %d"):format(UNLOCK), r[1] == true and r[2] == "Success" and r[3] == "Unlock" and r[4] == "Water" and r[5] == UNLOCK and p.Diamonds == 100000 - UNLOCK)
check("atributo UnlockedCores = Nature,Water", ana:GetAttribute("UnlockedCores") == "Nature,Water")
check("se guarda al momento (UnlockedAt registrado)", storeWrites > writes and record(31).Cores.Elements.Water.Unlocked == true and record(31).Cores.Elements.Water.UnlockedAt == os.time())
r = act(ana, "Unlock", "Water")
check("despertarlo otra vez -> AlreadyUnlocked, sin cobrar", r[2] == "AlreadyUnlocked" and p.Diamonds == 100000 - UNLOCK)

print("-- 3. Mejorar")
local upgradeCost = CoreLogic.upgradeCost("Water", 0)
advance(1)
r = act(ana, "Upgrade", "Water")
check(("mejorar Agua -> nivel 1, cuesta %d"):format(upgradeCost), r[1] == true and r[3] == "Upgrade" and r[5] == upgradeCost and p.PetData.Cores.Elements.Water.Level == 1 and p.Diamonds == 100000 - UNLOCK - upgradeCost)
advance(1)
r = act(ana, "Upgrade", "Nature")
check("Naturaleza por CoreAction -> InvalidRequest (no tiene nivel)", r[2] == "InvalidRequest")

print("-- 4. Elegir el elemento activo")
advance(1)
local switchCost = CoreLogic.switchCost()
local energyBefore = p.Diamonds
r = act(ana, "Select", "Water")
check(("elegir Agua -> cuesta Switch.MinCost (%d)"):format(switchCost), r[1] == true and r[3] == "Select" and r[5] == switchCost and p.Diamonds == energyBefore - switchCost and ana:GetAttribute("SelectedCore") == "Water")
r = act(ana, "Select", "Water")
check("elegir el que ya está activo -> AlreadySelected", r[2] == "AlreadySelected")
advance(2)
r = act(ana, "Select", "Nature")
check("volver a cambiar antes de 10 s -> TooFast, sin cobrar", r[2] == "TooFast" and ana:GetAttribute("SelectedCore") == "Water")
advance(CoreConfig.Switch.CooldownSeconds)
r = act(ana, "Select", "Nature")
check("pasado el enfriamiento se puede volver a Naturaleza", r[1] == true and ana:GetAttribute("SelectedCore") == "Nature")
check("sin secundario: atributo vacío", ana:GetAttribute("SecondaryCore") == "")
advance(CoreConfig.Switch.CooldownSeconds)
energyBefore = p.Diamonds
r = act(ana, "Secondary", "Water")
check("elegir Agua como secundario (R): cobra lo mismo que cambiar y se replica", r[1] == true and r[3] == "Secondary" and p.Diamonds == energyBefore - switchCost and ana:GetAttribute("SecondaryCore") == "Water")

print("-- 5. Peticiones no válidas y estado al cliente")
advance(1)
energyBefore = p.Diamonds
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
check("acción o elemento no válidos -> rechazados, sin cobrar", allInvalid and p.Diamonds == energyBefore)
check("la respuesta no devuelve textos enormes del cliente", bad[4][4] == nil and bad[1][3] == nil)
fireServer("RequestCores", ana)
advance(0)
local state = lastResult("CoreState", ana)[1]
check("CoreState: 8 núcleos en orden, Agua nivel 1, Fuego disponible, Viento no",
	#state.Elements == 8 and state.Elements[2].Id == "Water" and state.Elements[2].Level == 1
		and state.Elements[3].Available == true and state.Elements[3].UnlockCost == CoreLogic.unlockCost("Fire") and state.Elements[4].Available == false)
check("CoreState: coste de cambio, secundario y sin datos de producción",
	state.SwitchCost == CoreLogic.switchCost() and state.Ready == true and state.Secondary == "Water"
		and state.Total == nil and state.BaseProduction == nil and state.Elements[2].Production == nil)
check("CoreState: Naturaleza no tiene mejora (nivel 0 de 0)", state.Elements[1].UpgradeCost == nil and state.Elements[1].Level == 0 and state.Elements[1].MaxLevel == 0)

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
check("al salir se guardan núcleos y 💎", record(31).Cores.Elements.Water.Level == 2 and record(31).Cores.Selected == "Nature" and record(31).Cores.Secondary == "Water" and record(31).Diamonds == p.Diamonds)

print("-- 7. Datos cargando: no se gasta")
storeData.player_32 = { Version = 3, Diamonds = 50000, UpgradeLevels = { GeneratorPower = 1 } }
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
check("al terminar la carga, nada se cobró", PlayerDataService.get(ben).Diamonds == 50000 and not CoreLogic.isUnlocked(PlayerDataService.get(ben).PetData.Cores, "Water"))
exit(ben)

print("-- 8. Nada mientras no juegas")
local now = os.time()
local cores = CoreLogic.empty()
cores.Elements.Water.Unlocked = true
cores.Elements.Water.Level = 2
storeData.player_33 = { Version = 3, Diamonds = 10, UpgradeLevels = { GeneratorPower = 4 }, Cores = cores, LastSeen = now - 7200,
	Pets = { { Uid = "1", PetId = "MossFox" } }, Equipped = { "1" }, NextPetUid = 2 }
local cid, cp = enter("Cid", 33)
advance(2)
check("2 h fuera con núcleos despiertos: ni un 💎 offline ni aviso", cp.Diamonds == 10 and cid:GetAttribute("OfflineReward") == nil)
check("y sus núcleos siguen como estaban", CoreLogic.isUnlocked(cp.PetData.Cores, "Water") and CoreLogic.level(cp.PetData.Cores, "Water") == 2)
exit(cid)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
