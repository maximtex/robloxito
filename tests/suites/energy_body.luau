-- Energía solo de matar (EconomyConfig.PassiveEnergy = false, el rediseño "solo disparar"):
-- servicios REALES (PlayerDataService, EnergyService, QuestService, TutorialService) sobre
-- la persistencia simulada.
PlayerDataService.start()
EnergyService.start()
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
check("el interruptor está apagado en el juego", EconomyConfig.PassiveEnergy == false)
check("cada enemigo da una parte de su recompensa en ⚡", EconomyConfig.KillEnergyShare > 0 and EconomyConfig.KillEnergyShare < 1)
local ana, profile = enter("Ana", 1)
local before = profile.Energy
advance(5)
check("5 s sin pelear: la energía no sube", profile.Energy == before)
check("y no cuenta energía generada", profile.PetData.Quests.Stats.EnergyEarned == 0)

print("-- 2. Energía de los enemigos (EnergyService.grant)")
local given = EnergyService.grant(ana, 12.7)
check("se suma al momento, redondeada hacia abajo", given == 12 and profile.Energy == before + 12)
check("el contador del cliente sube ya", ana:GetAttribute("Energy") == math.floor(profile.Energy))
check("todavía no cuenta como generada (los avisos van una vez por segundo)", profile.PetData.Quests.Stats.EnergyEarned == 0)
advance(1)
check("en el siguiente ciclo cuenta como generada (misiones y clasificaciones)", profile.PetData.Quests.Stats.EnergyEarned == 12)
EnergyService.grant(ana, 5)
EnergyService.grant(ana, 3)
advance(1)
check("varios enemigos en el mismo segundo se cuentan juntos, una sola vez", profile.PetData.Quests.Stats.EnergyEarned == 20)
advance(3)
check("sin pelear no se vuelve a contar", profile.PetData.Quests.Stats.EnergyEarned == 20)
local energyNow = profile.Energy
check("cantidades raras no suman nada", EnergyService.grant(ana, 0 / 0) == 0 and EnergyService.grant(ana, -5) == 0 and EnergyService.grant(ana, math.huge) == 0 and EnergyService.grant(ana, 0.4) == 0 and EnergyService.grant(ana, "9") == 0 and profile.Energy == energyNow)
check("sin perfil (no está en la partida), nada", EnergyService.grant(newPlayer("Nadie", 99), 50) == 0)
leave(ana)
advance(0)
check("lo ganado peleando se guarda", storeData.player_1 ~= nil and storeData.player_1.Energy == energyNow)

print("-- 3. Nada mientras no juegas")
local now = os.time()
storeData.player_2 = { Version = 3, Energy = 10, UpgradeLevels = { GeneratorPower = 8 }, LastSeen = now - 7200,
	Pets = { { Uid = "1", PetId = "MossFox" } }, Equipped = { "1" }, NextPetUid = 2 }
local bea, beaProfile = enter("Bea", 2)
advance(10)
check("2 h fuera: sin energía offline", beaProfile.Energy == 10)
check("y sin aviso de energía offline", bea:GetAttribute("OfflineReward") == nil)
check("el poder de energía (Resonancia y mascotas) sigue contando para los enemigos", beaProfile.ProductionPerSecond > 1)
leave(bea)
advance(0)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
