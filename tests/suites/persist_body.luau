QuestLogic.init(QuestConfig, EnemyConfig, Economy)
PlayerDataService.start()
UpgradeService.start()
QuestService.start()

local failures = 0
local function check(name, ok)
	if not ok then failures += 1 end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local function record(userId) return storeData["player_" .. userId] end
local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in a do if not same(v, b[k]) then return false end end
	for k in b do if a[k] == nil then return false end end
	return true
end
local function buy(player)
	advance(0.5) -- respeta el límite de frecuencia de las compras
	fireServer("PurchaseUpgrade", player, "GeneratorPower")
	return lastResult("PurchaseResult", player)
end
local cost = function(level) return Economy.getUpgradeCost("GeneratorPower", level) end

print("-- 1. Perfil antiguo sin Energy ni UpgradeLevels")
storeData.player_1 = { Version = 1, Pets = { { Uid = "1", PetId = "MossFox" } }, Equipped = { "1" }, NextPetUid = 2, UnlockedZones = { "CrystalValley" }, Quests = { Stats = { Kills = 7 } } }
local alice = newPlayer("Alice", 1)
join(alice)
advance(0)
local profile = PlayerDataService.get(alice)
check("carga con energía inicial y mejora a 0", profile.DataState == "Loaded" and profile.Energy == 0 and profile.UpgradeLevels.GeneratorPower == 0)
check("mascotas, zonas y misiones antiguas intactas", #profile.PetData.Pets == 1 and profile.PetData.UnlockedZones[1] == "CrystalValley" and profile.PetData.Quests.Stats.Kills == 7)
check("el cliente ve DataStatus = Loaded y sin error de guardado", alice:GetAttribute("DataStatus") == "Loaded" and alice:GetAttribute("SaveError") == false)

print("-- 2. Guardar y cargar dinero, diamantes y mejoras")
profile.Money = 5000
profile.Energy = 40 -- 💎 (la Resonancia se paga con 💰)
for _ = 1, 3 do buy(alice) end
local expected = 5000 - cost(0) - cost(1) - cost(2)
check(("3 compras reales: nivel 3 y 💰 %d (los 💎 no se tocan)"):format(expected), profile.UpgradeLevels.GeneratorPower == 3 and profile.Money == expected and profile.Energy == 40)
leave(alice)
advance(0)
check("al salir se guardan Money, Energy (💎) y UpgradeLevels (y se libera el bloqueo)", record(1).Money == expected and record(1).Energy == 40 and record(1).UpgradeLevels.GeneratorPower == 3 and record(1).Session == nil and record(1).Version == 15 and record(1).EconomyVersion == 2)
check("y las clases (v14): la gratis de cada estilo, activa", record(1).Classes ~= nil and record(1).Classes.Owned.Soldier == 1 and record(1).Classes.Active.Fists == "Brawler" and record(1).Classes.Active.Magic == "Apprentice")
check("y el resto del registro sigue igual", #record(1).Pets == 1 and record(1).UnlockedZones[1] == "CrystalValley" and record(1).Quests.Stats.Kills == 7)
alice = newPlayer("Alice", 1)
join(alice)
advance(0)
profile = PlayerDataService.get(alice)
check(("al volver: 💰 %d, 💎 40, nivel 3"):format(profile.Money), profile.Money == expected and profile.Energy == 40 and profile.UpgradeLevels.GeneratorPower == 3)
check(("producción recalculada con la mejora y la mascota: %s/s"):format(tostring(profile.ProductionPerSecond)), math.abs(profile.ProductionPerSecond - 4 * PetMath.getTotalMultiplier({ "MossFox" })) < 1e-9)
check("el cliente recibe el dinero, los 💎 y el nivel guardados", alice:GetAttribute("Money") == math.floor(expected) and alice:GetAttribute("Energy") == 40 and alice:GetAttribute("UpgradeLevel_GeneratorPower") == 3)

print("-- 3. Compra de mejora y recompensa de misión simultáneas")
advance(1) -- la misión "comprar una mejora" queda marcada (estado del perfil)
fireServer("RequestQuests", alice)
local before = profile.Energy
local moneyBefore = profile.Money
local levelBefore = profile.UpgradeLevels.GeneratorPower
advance(1)
-- Las dos solicitudes en el mismo instante
fireServer("PurchaseUpgrade", alice, "GeneratorPower")
fireServer("ClaimQuest", alice, "BuyUpgrade")
local purchase = lastResult("PurchaseResult", alice)
local claim = lastResult("QuestResult", alice)
local reward = claim[4]
check(("compra OK (nivel %d -> %d) y reclamación OK (+%s)"):format(levelBefore, profile.UpgradeLevels.GeneratorPower, tostring(reward)), purchase[1] == true and claim[1] == true and profile.UpgradeLevels.GeneratorPower == levelBefore + 1)
local afterBoth = before + reward
local moneyAfter = moneyBefore - cost(levelBefore)
check(("exacto: 💰 %d - %d = %d y 💎 %d + %d = %d (sin pérdidas ni duplicados)"):format(moneyBefore, cost(levelBefore), moneyAfter, before, reward, afterBoth), profile.Energy == afterBoth and profile.Money == moneyAfter)
fireServer("ClaimQuest", alice, "BuyUpgrade")
advance(1)
fireServer("ClaimQuest", alice, "BuyUpgrade")
check("la recompensa no se repite", profile.Energy == afterBoth and lastResult("QuestResult", alice)[2] == "AlreadyClaimed")
leave(alice)
advance(0)
check("lo guardado coincide con la sesión (💎, 💰, nivel y misión reclamada)", record(1).Energy == afterBoth and record(1).Money == moneyAfter and record(1).UpgradeLevels.GeneratorPower == levelBefore + 1 and record(1).Quests.Claimed.BuyUpgrade == true)
alice = newPlayer("Alice", 1)
join(alice)
advance(1)
fireServer("ClaimQuest", alice, "BuyUpgrade")
check("tras volver a entrar tampoco se puede reclamar otra vez", lastResult("QuestResult", alice)[2] == "AlreadyClaimed" and PlayerDataService.get(alice).Energy == afterBoth)

print("-- 4. Carga fallida: no se sobrescribe el progreso anterior")
storeData.player_2 = { Version = 2, Energy = 999, UpgradeLevels = { GeneratorPower = 5 }, Pets = { { Uid = "1", PetId = "Sproutling" } }, Equipped = {}, NextPetUid = 2 }
local snapshot2 = deep(storeData.player_2)
storeFail = 5 -- todos los intentos de carga fallan
local bob = newPlayer("Bob", 2)
join(bob)
advance(30)
local bobProfile = PlayerDataService.get(bob)
check("tras 5 intentos: estado Failed y el cliente lo sabe", bobProfile.DataState == "Failed" and bob:GetAttribute("DataStatus") == "Failed")
check("se juega con valores de sesión (no con los guardados)", bobProfile.Energy == 0 and bobProfile.UpgradeLevels.GeneratorPower == 0)
bobProfile.Money = 100
local r = buy(bob)
check("puede seguir jugando en modo sesión (compra permitida)", r[1] == true and bobProfile.UpgradeLevels.GeneratorPower == 1)
advance(200) -- pasan guardados automáticos
leave(bob)
advance(0)
check("el registro guardado NO cambia (999 de energía, nivel 5, sin bloqueo nuevo)", same(storeData.player_2, snapshot2))

print("-- 5. Guardado fallido con tratamiento seguro")
profile = PlayerDataService.get(alice)
profile.Energy += 777
local stored = record(1).Energy
storeFail = 3 -- los 3 intentos del próximo guardado fallan
advance(91) -- guardado automático
check("guardado fallido: aviso al jugador (SaveError) y cambio pendiente", alice:GetAttribute("SaveError") == true and profile.Dirty == true)
check("el registro conserva el último valor bueno", record(1).Energy == stored)
advance(91) -- siguiente guardado automático, ya sin fallos
check("al reintentar se guarda y el aviso desaparece", record(1).Energy == profile.Energy and alice:GetAttribute("SaveError") == false)

print("-- 6. Diamantes ganados mientras carga (y la ⚡ de antes se vuelve 💰)")
storeData.player_3 = { Version = 2, Energy = 500, UpgradeLevels = { GeneratorPower = 2 } }
storeLatency = 2
local cara = newPlayer("Cara", 3)
join(cara)
local caraProfile = PlayerDataService.get(cara)
caraProfile.Energy += 25 -- recompensa de un enemigo durante la carga
advance(0.5)
fireServer("PurchaseUpgrade", cara, "GeneratorPower")
check("durante la carga no se puede comprar (NotReady)", lastResult("PurchaseResult", cara)[2] == "NotReady" and caraProfile.UpgradeLevels.GeneratorPower == 0)
advance(3)
storeLatency = 0
check(("al cargar: la ⚡ guardada (500) pasa a 💰 2500 y los 25 💎 ganados se quedan (%d), nivel 2"):format(caraProfile.Energy), caraProfile.Energy == 25 and caraProfile.Money == 2500 and caraProfile.UpgradeLevels.GeneratorPower == 2)
check("y se avisa al jugador una vez (EconomyNotice)", cara:GetAttribute("EconomyNotice") == "500,2500")

print("-- 7. Valores corruptos y mejoras desconocidas")
storeData.player_4 = { Version = 2, Energy = -50, UpgradeLevels = { GeneratorPower = 999, OldBoost = 3, Broken = "x" } }
local dan = newPlayer("Dan", 4)
join(dan)
advance(0)
local danProfile = PlayerDataService.get(dan)
storeData.player_7 = { Version = 2, Energy = -50 }
local warningsBefore = #warnings
local status7, loaded7 = SaveService.load(7)
check("energía negativa guardada -> valor inicial, con aviso en consola", status7 == "Loaded" and loaded7.Energy == 0 and #warnings > warningsBefore)
local resonanceReward = 0
for _, def in QuestConfig.Achievements do
	if def.Id == "Resonance10" then
		resonanceReward = QuestLogic.reward(def, 50)
	end
end
check(("nivel 999 recortado a 50 desbloquea su logro una vez (+%d 💎 con el logro Resonancia plena)"):format(danProfile.Energy), resonanceReward > 0 and danProfile.Energy == resonanceReward and danProfile.PetData.Quests.Achievements.Resonance10 == true)
check("nivel por encima del máximo -> 50", danProfile.UpgradeLevels.GeneratorPower == 50)
check("solo mejoras existentes en el perfil", danProfile.UpgradeLevels.OldBoost == nil)
leave(dan)
advance(0)
check("la mejora desconocida se conserva en el registro al guardar", record(4).UpgradeLevels.OldBoost == 3 and record(4).UpgradeLevels.GeneratorPower == 50)
storeData.player_6 = { Version = 2, Energy = 0 / 0, UpgradeLevels = { GeneratorPower = 0 / 0 } }
local fay = newPlayer("Fay", 6)
join(fay)
advance(0)
check("NaN -> 0 (energía y nivel)", PlayerDataService.get(fay).Energy == 0 and PlayerDataService.get(fay).UpgradeLevels.GeneratorPower == 0)

print("-- 8. Salir durante la carga")
storeData.player_5 = { Version = 2, Energy = 300, UpgradeLevels = { GeneratorPower = 1 } }
storeLatency = 2
local eve = newPlayer("Eve", 5)
join(eve)
leave(eve)
advance(5)
storeLatency = 0
check("el registro conserva lo suyo (su ⚡ ya convertida en 💰) y se libera el bloqueo", record(5).Money == 1500 and record(5).Energy == 0 and record(5).EconomyVersion == 2 and record(5).UpgradeLevels.GeneratorPower == 1 and record(5).Session == nil)

print("-- 9. Cierre del servidor")
profile = PlayerDataService.get(alice)
profile.Energy += 1
local target = profile.Energy
task.spawn(closeCallbacks[1])
advance(1)
check("BindToClose guarda la energía de los jugadores conectados", record(1).Energy == target)

print("-- 10. Dinero, armas y jefes derrotados (guardado v8)")
storeData.player_8 = { Version = 7, Energy = 10, Money = 777, UpgradeLevels = { GeneratorPower = 1, LaserPower = 7 } }
local gus = newPlayer("Gus", 8)
join(gus)
advance(0)
local gp = PlayerDataService.get(gus)
check("registro v7: conserva su dinero y su ⚡ (10) se suma como 💰 50", gp.Money == 827 and gp.Energy == 0)
check("sin armas guardadas: el láser con el nivel de la antigua Potencia del Láser (7)", gp.PetData.Weapons.Equipped == "Laser" and gp.PetData.Weapons.Levels.Laser == 7)
check("sin jefes guardados: ninguno derrotado", next(gp.PetData.Bosses) == nil)
check("sin récords de oleadas guardados (v9 o antes): a cero", gp.PetData.Waves.Cleared == 0 and next(gp.PetData.Waves.Best) == nil)
check("sin puertas de la cueva guardadas (v11 o antes): todas cerradas", gp.PetData.Cave[1] == 0 and gp.PetData.Cave[2] == 0)
WaveLogic.recordWave(gp.PetData.Waves, "Forest", 7)
gp.PetData.Cave = { 15, 4 }
gp.Money = 4321
WeaponLogic.grant(gp.PetData.Weapons, "PlasmaBlaster")
gp.PetData.Weapons.Levels.PlasmaBlaster = 3
WeaponLogic.equip(gp.PetData.Weapons, "PlasmaBlaster")
gp.PetData.Bosses.ForestWarden = 2
PlayerDataService.markDirty(gus)
leave(gus)
advance(0)
local r8 = record(8)
check("al salir se guardan dinero, armas, la equipada, sus niveles y los jefes", r8.Version == 15 and r8.EconomyVersion == 2 and r8.Money == 4321 and r8.Weapons.Equipped == "PlasmaBlaster" and r8.Weapons.Levels.PlasmaBlaster == 3 and table.find(r8.Weapons.Owned, "PlasmaBlaster") ~= nil and r8.Bosses.ForestWarden == 2)
check("y los récords de oleadas (v10)", r8.Waves.Cleared == 1 and r8.Waves.Best.Forest == 7)
check("y las puertas de las mazmorras (v12): una lista sin huecos, una por puerta de las cuatro cuevas", r8.Cave[1] == 15 and r8.Cave[2] == 4 and #r8.Cave == 8 and r8.Cave[3] == 0)
gus = newPlayer("Gus", 8)
join(gus)
advance(0)
gp = PlayerDataService.get(gus)
check("al volver: todo sigue igual (y el láser conserva su nivel 7)", gp.Money == 4321 and gp.PetData.Weapons.Equipped == "PlasmaBlaster" and gp.PetData.Weapons.Levels.PlasmaBlaster == 3 and gp.PetData.Weapons.Levels.Laser == 7 and gp.PetData.Bosses.ForestWarden == 2)
check("el cliente ve el arma equipada y las que tiene", gus:GetAttribute("EquippedWeapon") == "PlasmaBlaster" and gus:GetAttribute("Weapons") == "Laser:7,PlasmaBlaster:3,LeatherGloves:0,ApprenticeWand:0" and gus:GetAttribute("BossesDefeated") == "ForestWarden")
storeData.player_9 = { Version = 8, Money = 0 / 0, Weapons = { Owned = { "Laser", "Nope" }, Levels = { Laser = 999 }, Equipped = "Nope" }, Bosses = { ForestWarden = -3, Bad = 0 / 0 } }
local hal = newPlayer("Hal", 9)
join(hal)
advance(0)
local hp = PlayerDataService.get(hal)
check("valores corruptos: dinero 0, nivel al tope, equipada válida y jefes limpios", hp.Money == 0 and hp.PetData.Weapons.Levels.Laser == WeaponConfig.MaxLevel and hp.PetData.Weapons.Equipped == "Laser" and hp.PetData.Bosses.ForestWarden == nil and hp.PetData.Bosses.Bad == nil)

print("-- 11. Economía 2: conversión una sola vez")
storeData.player_10 = { Version = 12, Energy = 1234, Money = 6, UpgradeLevels = { GeneratorPower = 3 }, Pets = { { Uid = "1", PetId = "MossFox" } }, Equipped = { "1" }, NextPetUid = 2,
	Quests = { Stats = { Kills = 4, EnergyEarned = 999999 }, Daily = { Day = 5, Ids = { "DailyEnergy" }, Progress = { DailyEnergy = 2000, DailyHunt = 3 } } },
	Weekly = { Week = 3, Energy = 5000 } }
local ivy = newPlayer("Ivy", 10)
join(ivy)
advance(0)
local ip = PlayerDataService.get(ivy)
check("la ⚡ (1234) pasa a 💰 (6 + 6170) y los 💎 empiezan en 0", ip.Money == 6176 and ip.Energy == 0)
check("las cuentas de energía conseguida vuelven a 0 (misión y semana); el resto se queda", ip.PetData.Quests.Stats.EnergyEarned == 0 and ip.PetData.Quests.Stats.Kills == 4 and ip.PetData.Weekly.Energy == 0)
storeData.player_11 = { Version = 12, Energy = 5, Quests = { Daily = { Day = 5, Ids = { "DailyEnergy" }, Progress = { DailyEnergy = 2000, DailyHunt = 3 } } } }
local status11, loaded11 = SaveService.load(11)
check("y la diaria de energía de hoy (las otras diarias siguen)", status11 == "Loaded" and loaded11.Quests.Daily.Progress.DailyEnergy == nil and loaded11.Quests.Daily.Progress.DailyHunt == 3 and loaded11.EconomyConverted ~= nil and loaded11.EconomyConverted.Money == 25)
ip.Energy = 30
leave(ivy)
advance(0)
check("se guarda con EconomyVersion 2", record(10).EconomyVersion == 2 and record(10).Money == 6176 and record(10).Energy == 30)
ivy = newPlayer("Ivy", 10)
join(ivy)
advance(0)
ip = PlayerDataService.get(ivy)
check("al volver no se convierte otra vez (💎 30 se quedan) y no hay aviso", ip.Money == 6176 and ip.Energy == 30 and ivy:GetAttribute("EconomyNotice") == nil)

print("-- 12. Habilidades de los estilos (guardado v13)")
check("quien ya jugaba (con mascotas guardadas) no vuelve a elegir estilo", ip.PetData.Skills.Picked == true and ivy:GetAttribute("StylePicked") == true)
local _, fresh = SaveService.load(55)
check("un jugador nuevo sí elige (y empieza con las iniciales)", fresh.Skills.Picked == false and fresh.Skills.Owned.Burst == 1 and fresh.Skills.Owned.Pierce == nil)
ip.PetData.Skills.Owned.Pierce = 3
SkillLogic.equip(ip.PetData.Skills, "Pierce", 1)
PlayerDataService.markDirty(ivy)
leave(ivy)
advance(0)
check("se guardan las compradas, su nivel y las puestas", record(10).Skills.Owned.Pierce == 3 and record(10).Skills.Equipped.Weapons[1] == "Pierce" and record(10).Skills.Picked == true)
ivy = newPlayer("Ivy", 10)
join(ivy)
advance(0)
check("y el cliente las ve al volver", ivy:GetAttribute("Skills"):find("Pierce:3", 1, true) ~= nil and ivy:GetAttribute("SkillSlots"):find("Weapons=Pierce,Grenade", 1, true) ~= nil)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
