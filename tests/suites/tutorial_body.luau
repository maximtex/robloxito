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
local function record(userId) return storeData["player_" .. userId] end
-- Historial de TutorialStatus que ha visto el cliente
local function track(player)
	local history = {}
	local set = player.SetAttribute
	function player.SetAttribute(self, k, v)
		if k == "TutorialStatus" then table.insert(history, v) end
		set(self, k, v)
	end
	return history
end
local function status(p) return p:GetAttribute("TutorialStatus") end
local function step(p) return p:GetAttribute("TutorialStep") end
local function give(profile, petId)
	-- Lo que hace PetService al vender una mascota (aquí sin pasar por el pedestal).
	local uid = tostring(profile.PetData.NextPetUid)
	profile.PetData.NextPetUid += 1
	table.insert(profile.PetData.Pets, { Uid = uid, PetId = petId })
	return uid
end

print("-- 1. Jugador nuevo: recorrido completo")
local alice = newPlayer("Alice", 1)
local aliceHistory = track(alice)
join(alice)
advance(0)
local profile = PlayerDataService.get(alice)
check("al entrar: tutorial activo, 0 pasos hechos", status(alice) == "Active" and step(alice) == 0)
defeat(alice, "StarterThornling")
defeat(alice, "Thornling")
defeat(alice, "Thornling")
advance(1)
check("derrotar enemigos sueltos no cuenta: sigue en el paso 1 (oleadas)", step(alice) == 0)
GameEvents.fire("WaveWon", alice, "Tutorial") -- lo que hace WaveService al ganar la práctica
advance(1)
check("al ganar la oleada de práctica: paso 1 hecho", step(alice) == 1 and profile.PetData.Quests.Stats.WaveWins == 1)
profile.PetData.Weapons.Levels.Laser = 1 -- lo que hace WeaponService al mejorar el arma
advance(1)
check("tras mejorar su arma: paso 2 hecho", step(alice) == 2)
give(profile, "MushroomHopper")
advance(1)
check("con una mascota además de la inicial: paso 3 hecho", step(alice) == 3)
defeat(alice, "ForestWarden", "Boss")
advance(1)
check("al derrotar al Guardián del Bosque: paso 4 hecho", step(alice) == 4)
local energyBefore = profile.Energy
table.insert(profile.PetData.UnlockedZones, "CrystalValley")
advance(1)
check("al desbloquear el Valle: tutorial completado", status(alice) == "Completed" and step(alice) == 5)
-- Sin producción pasiva: ese segundo no da nada.
check(("no concede 💎 (+%s)"):format(tostring(profile.Energy - energyBefore)), profile.Energy == energyBefore)
leave(alice)
advance(0)
check("se guarda como completado", record(1).Tutorial.Status == "Completed" and record(1).Tutorial.Step == 5)
alice = newPlayer("Alice", 1)
aliceHistory = track(alice)
join(alice)
advance(3)
check("al volver: completado y nunca se muestra como activo", status(alice) == "Completed" and not table.find(aliceHistory, "Active"))

print("-- 2. Veterano con mascotas y el Valle (registro sin campo Tutorial)")
storeData.player_2 = { Version = 2, Energy = 9000, UpgradeLevels = { GeneratorPower = 12 }, Pets = { { Uid = "1", PetId = "MossFox" }, { Uid = "2", PetId = "QuartzFox" } }, Equipped = { "1" }, NextPetUid = 3, UnlockedZones = { "CrystalValley" }, Quests = { Stats = { Kills = 300, EnergyEarned = 50000 } } }
local bob = newPlayer("Bob", 2)
local bobHistory = track(bob)
join(bob)
advance(0)
check("se completa solo al cargar y el cliente nunca lo ve activo", status(bob) == "Completed" and not table.find(bobHistory, "Active"))
-- La energía extra de Bob viene de sus LOGROS (Fase 5, al cargar), no del tutorial:
local achievementEnergy = 0
for _, f in fired do
	if f.Name == "QuestState" and f.Player == bob and type(f.Args[1].Notices) == "table" then
		for _, n in f.Args[1].Notices do
			if n.Type == "Achievement" then achievementEnergy += n.Reward or 0 end
		end
	end
end
print(("  (logros concedidos al cargar: +%d 💎)"):format(achievementEnergy))
check("el tutorial no cambia su dinero (su ⚡ 9000 pasó a 💰 45000, más la devolución de su Resonancia 12) ni sus 💎 (solo los logros) ni sus mascotas", PlayerDataService.get(bob).Money == 45000 + resonanceRefund(12) and PlayerDataService.get(bob).Energy == achievementEnergy and #PlayerDataService.get(bob).PetData.Pets == 2)

print("-- 3. Veterano a medias: tiene mascota pero no la equipó")
storeData.player_3 = { Version = 2, Energy = 40, UpgradeLevels = { GeneratorPower = 0 }, Pets = { { Uid = "1", PetId = "Sproutling" }, { Uid = "2", PetId = "MossFox" } }, Equipped = { "1" }, NextPetUid = 3, Quests = { Stats = { Kills = 12 } } }
local cara = newPlayer("Cara", 3)
join(cara)
advance(0)
check("no repite lo que ya cumple: con 2 mascotas empieza en 'Derrota al Guardián' (3 hechos)", status(cara) == "Active" and step(cara) == 3)
table.remove(PlayerDataService.get(cara).PetData.Pets)
advance(1)
check("lo hecho no se deshace (sigue en 3)", step(cara) == 3)

print("-- 4. Omitir")
fireServer("SkipTutorial", cara)
check("omitir lo marca como Skipped", status(cara) == "Skipped")
leave(cara)
advance(0)
check("se guarda omitido", record(3).Tutorial.Status == "Skipped")
cara = newPlayer("Cara", 3)
local caraHistory = track(cara)
join(cara)
advance(2)
check("al volver sigue omitido y no se muestra", status(cara) == "Skipped" and not table.find(caraHistory, "Active"))
defeat(cara, "ForestWarden", "Boss")
advance(2)
check("cumplir pasos después de omitir no lo reactiva", status(cara) == "Skipped")

print("-- 5. El cliente no puede declarar pasos")
local dan = newPlayer("Dan", 4)
join(dan)
advance(0.5)
fireServer("SkipTutorial", dan, { Status = "Completed", Step = 5 })
check("argumentos extra se ignoran: solo puede omitir (Skipped, no Completed)", status(dan) == "Skipped" and step(dan) == 0)
fireServer("SkipTutorial", alice)
advance(1)
check("omitir un tutorial ya completado no lo cambia", status(alice) == "Completed")
local before = #fired
for _ = 1, 20 do fireServer("SkipTutorial", dan) end
check("ráfaga de solicitudes limitada sin errores", status(dan) == "Skipped" and #fired == before)

print("-- 6. Datos guardados corruptos")
storeData.player_5 = { Version = 2, Tutorial = { Status = "Hacked", Step = 99 } }
local eve = newPlayer("Eve", 5)
join(eve)
advance(0)
check("estado inválido -> activo; paso fuera de rango recortado (y completado)", status(eve) == "Completed" and step(eve) == 5)
storeData.player_6 = { Version = 2, Tutorial = { Status = "Active", Step = -4 } }
local fay = newPlayer("Fay", 6)
join(fay)
advance(0)
check("paso negativo -> 0", status(fay) == "Active" and step(fay) == 0)

print("-- 7. Carga fallida")
storeData.player_7 = { Version = 2, Energy = 777, Tutorial = { Status = "Active", Step = 2 } }
local snapshot7 = deep(storeData.player_7)
storeFail = 5
local gus = newPlayer("Gus", 7)
join(gus)
advance(40)
check("sin datos no hay tutorial (sin atributos) y el estado es Failed", status(gus) == nil and gus:GetAttribute("DataStatus") == "Failed")
fireServer("SkipTutorial", gus)
leave(gus)
advance(0)
local same = record(7).Tutorial.Step == snapshot7.Tutorial.Step and record(7).Tutorial.Status == "Active" and record(7).Energy == 777
check("omitir sin datos no hace nada y el registro no cambia", same)

print("-- 8. Dos jugadores a la vez")
local h1, h2 = newPlayer("Hana", 8), newPlayer("Ivo", 9)
join(h1)
join(h2)
advance(1)
GameEvents.fire("WaveWon", h1, "Tutorial")
GameEvents.fire("WaveWon", h2, "Tutorial")
advance(1)
check("los dos avanzan con sus propias partidas (paso 1 cada uno)", step(h1) == 1 and step(h2) == 1)
advance(0.5)
PlayerDataService.get(h1).PetData.Weapons.Levels.Laser = 1
fireServer("SkipTutorial", h2)
advance(1)
check("mejorar el arma de uno no avanza al otro, y omitir de uno no afecta al otro", step(h1) == 2 and status(h1) == "Active" and status(h2) == "Skipped" and step(h2) == 1)
leave(h1)
leave(h2)
advance(0)
check("cada uno guarda su propio estado", record(8).Tutorial.Status == "Active" and record(8).Tutorial.Step == 2 and record(9).Tutorial.Status == "Skipped")

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
