-- 💎 (en el código, Diamonds) solo de matar: ya no hay producción pasiva ni offline.
-- servicios REALES (PlayerDataService, DiamondService, QuestService, TutorialService) sobre
-- la persistencia simulada.
PlayerDataService.start()
DiamondService.start()
UpgradeService.start()
QuestService.start()
TutorialService.start()

local failures = 0
local function check(name, ok)
	if not ok then failures += 1 end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local function enter(name, userId)
	local player = newPlayer(name, userId)
	join(player)
	advance(0)
	return player, PlayerDataService.get(player)
end

print("-- 1. Sin energía pasiva")
check("ya no existe la producción pasiva (ni su interruptor)", EconomyConfig.PassiveEnergy == nil and EconomyConfig.BaseProductionPerSecond == nil)
check("cada enemigo da una parte de su recompensa en ⚡", EconomyConfig.KillDiamondShare > 0 and EconomyConfig.KillDiamondShare < 1)
local ana, profile = enter("Ana", 1)
local before = profile.Diamonds
advance(5)
check("5 s sin pelear: la energía no sube", profile.Diamonds == before)
check("y no cuenta energía generada", profile.PetData.Quests.Stats.DiamondsEarned == 0)

print("-- 2. Energía de los enemigos (DiamondService.grant)")
local given = DiamondService.grant(ana, 12.7)
check("se suma al momento, redondeada hacia abajo", given == 12 and profile.Diamonds == before + 12)
check("el contador del cliente sube ya", ana:GetAttribute("Diamonds") == math.floor(profile.Diamonds))
check("todavía no cuenta como generada (los avisos van una vez por segundo)", profile.PetData.Quests.Stats.DiamondsEarned == 0)
advance(1)
check("en el siguiente ciclo cuenta como generada (misiones y clasificaciones)", profile.PetData.Quests.Stats.DiamondsEarned == 12)
DiamondService.grant(ana, 5)
DiamondService.grant(ana, 3)
advance(1)
check("varios enemigos en el mismo segundo se cuentan juntos, una sola vez", profile.PetData.Quests.Stats.DiamondsEarned == 20)
advance(3)
check("sin pelear no se vuelve a contar", profile.PetData.Quests.Stats.DiamondsEarned == 20)
local energyNow = profile.Diamonds
check("cantidades raras no suman nada", DiamondService.grant(ana, 0 / 0) == 0 and DiamondService.grant(ana, -5) == 0 and DiamondService.grant(ana, math.huge) == 0 and DiamondService.grant(ana, 0.4) == 0 and DiamondService.grant(ana, "9") == 0 and profile.Diamonds == energyNow)
check("sin perfil (no está en la partida), nada", DiamondService.grant(newPlayer("Nadie", 99), 50) == 0)
leave(ana)
advance(0)
check("lo ganado peleando se guarda", storeData.player_1 ~= nil and storeData.player_1.Diamonds == energyNow)

print("-- 3. Nada mientras no juegas")
local now = os.time()
storeData.player_2 = { Version = 3, Diamonds = 10, UpgradeLevels = { GeneratorPower = 8 }, LastSeen = now - 7200,
	Pets = { { Uid = "1", PetId = "MossFox" } }, Equipped = { "1" }, NextPetUid = 2 }
local bea, beaProfile = enter("Bea", 2)
advance(10)
check("2 h fuera: sin 💎 offline (la ⚡ guardada, 10, pasó a 💰 50, más la devolución de su Resonancia 8)", beaProfile.Diamonds == 0 and beaProfile.Money == 50 + resonanceRefund(8))
check("y sin aviso de energía offline", bea:GetAttribute("OfflineReward") == nil)
check("los 💎 de los enemigos no dependen de la Resonancia ni de las mascotas (×1 sin pase, poción ni aventuras)", PlayerDataService.diamondMultiplier(beaProfile) == 1)
leave(bea)
advance(0)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
