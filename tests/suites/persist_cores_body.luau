-- Esta batería prueba la producción pasiva y offline (cristal y núcleos), que sigue en el
-- código detrás de EconomyConfig.PassiveEnergy: se enciende para comprobarla.
EconomyConfig.PassiveEnergy = true
-- Persistencia v3 (Fase 2, etapa 1): Cores, CoresArchive y LastSeen con el SaveService y
-- el PlayerDataService REALES sobre un DataStore en memoria con datos controlados.
-- Desde la fase 2 los núcleos desbloqueados SÍ producen (y hay producción offline al
-- cargar): la sección 4 lo comprueba; el resto sigue validando solo la persistencia.
-- La vuelta atrás usa el SaveService v2 congelado (tests/fixtures/SaveService_v2.luau).
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
local function warnedWith(text, since)
	for i = since + 1, #warnings do
		if warnings[i]:find(text, 1, true) then return true end
	end
	return false
end
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

print("-- 1. Migración: perfil v2 sin Cores")
local V2 = {
	Version = 2, Energy = 1234, UpgradeLevels = { GeneratorPower = 7 },
	Pets = { { Uid = "1", PetId = "MossFox" } }, Equipped = { "1" }, NextPetUid = 2,
	UnlockedZones = { "CrystalValley" }, Quests = { Stats = { Kills = 3 } },
	Tutorial = { Status = "Completed", Step = 5 }, FutureField = { Keep = true },
}
storeData.player_11 = deep(V2)
local ana, p = enter("Ana", 11)
check("carga Loaded con los núcleos por defecto (Naturaleza desbloqueada y seleccionada, el resto bloqueado)", p.DataState == "Loaded" and same(p.PetData.Cores, CoreLogic.empty()))
check("Naturaleza sin Level propio: su nivel sigue siendo UpgradeLevels.GeneratorPower (7)", p.PetData.Cores.Elements.Nature.Level == nil and p.UpgradeLevels.GeneratorPower == 7)
check("una partida antigua no es una corrección: nada archivado ni avisado", #p.PetData.CoresArchive == 0)
local expectedProduction = Economy.getProductionPerSecond({ GeneratorPower = 7 }) * PetMath.getTotalMultiplier({ "MossFox" })
check(("sin efecto económico: energía 1234 y producción %s/s, como en v2"):format(tostring(expectedProduction)), p.Energy == 1234 and p.ProductionPerSecond == expectedProduction)
check("la carga solo toma el bloqueo: todavía no escribe Cores", record(11).Cores == nil and record(11).Version == 2 and record(11).Session ~= nil)

print("-- 2. Guardado en v3")
local savedAt = os.time()
exit(ana)
local r = record(11)
check("versión actual (11), Cores guardado y LastSeen = hora del guardado", r.Version == 11 and same(r.Cores, CoreLogic.empty()) and r.LastSeen == savedAt)
check("sin CoresArchive vacío en el registro", r.CoresArchive == nil)
check("energía, nivel, mascotas, zonas, misiones y tutorial intactos", r.Energy == 1234 and r.UpgradeLevels.GeneratorPower == 7 and same(r.Pets, V2.Pets) and same(r.Equipped, V2.Equipped) and same(r.UnlockedZones, V2.UnlockedZones) and r.Quests.Stats.Kills == 3 and r.Tutorial.Status == "Completed")
check("campo desconocido del nivel superior conservado y bloqueo liberado", same(r.FutureField, V2.FutureField) and r.Session == nil)

print("-- 3. Recarga y guardado automático")
ana, p = enter("Ana", 11)
check("al volver: los mismos núcleos y nada archivado", same(p.PetData.Cores, record(11).Cores) and #p.PetData.CoresArchive == 0)
advance(91)
check("el guardado automático actualiza LastSeen y mantiene el bloqueo", record(11).LastSeen > savedAt and record(11).LastSeen <= os.time() and record(11).Session ~= nil)
exit(ana)

print("-- 4. Registro v3 válido con datos desconocidos: ida y vuelta exacta")
local cores = CoreLogic.empty()
cores.Elements.Water = { Unlocked = true, Level = 4, Mastery = 12.5, UnlockedAt = 1700000000, Skin = "Azul" }
cores.Elements.Fire.Unlocked = true
cores.Elements.Fire.UnlockedAt = 1700000100
cores.Selected = "Fire"
cores.LastSwitchAt = 1700000200
cores.Elements.Nature.Level = 3 -- campo desconocido en Naturaleza: se conserva, no se usa
cores.Elements.Plasma = { Unlocked = true, Level = 9 } -- elemento de una versión futura
cores.Extra = { Notes = { "a", "b" } }
local V3 = { Version = 3, Energy = 50, UpgradeLevels = { GeneratorPower = 2 }, Cores = deep(cores), CoresArchive = { { At = 1, Changes = { Selected = "Ice" } } }, LastSeen = 1700000300 }
storeData.player_12 = deep(V3)
local ben
ben, p = enter("Ben", 12)
check("se carga tal cual, sin correcciones", same(p.PetData.Cores, V3.Cores) and same(p.PetData.CoresArchive, V3.CoresArchive))
-- Fase 2: Agua (nivel 4) y Fuego (seleccionado: afinidad) producen; y al cargar se concede
-- la producción offline desde LastSeen (máximo 4 h, al 50 %, sin afinidad).
local cleanCores = CoreLogic.sanitize(V3.Cores)
-- Sin mascotas guardadas recibe la inicial (Brotecillo): cuenta en la producción y offline
local expectedOffline = CoreLogic.offlineReward(cleanCores, { GeneratorPower = 2 }, p.PetMultiplier, V3.LastSeen, os.time())
check(("fase 2: producción de todos los núcleos + afinidad (%s/s) y offline %s al cargar"):format(tostring(p.ProductionPerSecond), tostring(expectedOffline)),
	p.ProductionPerSecond == CoreLogic.effectiveProduction(cleanCores, { GeneratorPower = 2 }, p.PetMultiplier)
		and p.ProductionPerSecond > Economy.getProductionPerSecond({ GeneratorPower = 2 })
		and expectedOffline > 0 and p.Energy == 50 + expectedOffline
		and ben:GetAttribute("OfflineReward") == ("%.0f,%.0f"):format(expectedOffline, CoreConfig.Offline.CapSeconds))
exit(ben)
check("al guardar: Cores y CoresArchive idénticos y LastSeen actualizado", same(record(12).Cores, V3.Cores) and same(record(12).CoresArchive, V3.CoresArchive) and record(12).LastSeen == os.time())

print("-- 5. Núcleos corruptos: los originales se archivan antes de normalizar")
local BAD = {
	Selected = "Shadow", -- bloqueado
	LastSwitchAt = "ayer",
	Elements = {
		Nature = { Unlocked = false, UnlockedAt = 5 },
		Water = { Unlocked = true, Level = "5", Mastery = -3 },
		Fire = { Unlocked = "sí", Level = 999 },
		Wind = "roto",
		Ice = { Unlocked = true, Mastery = 1e13, Aura = "fría" },
	},
	Note = "campo desconocido",
}
local OLD_ENTRY = { At = 1, Changes = { Selected = "Ice" } }
storeData.player_13 = { Version = 3, Energy = 10, Cores = deep(BAD), CoresArchive = { deep(OLD_ENTRY) } }
local warningsBefore = #warnings
local cid
cid, p = enter("Cid", 13)
local c = p.PetData.Cores
check("normalizado: selección válida, nivel y maestría acotados, texto -> valor seguro",
	c.Selected == "Nature" and c.LastSwitchAt == 0 and c.Elements.Nature.Unlocked == true and c.Elements.Nature.UnlockedAt == nil
		and c.Elements.Water.Level == 0 and c.Elements.Water.Mastery == 0 and c.Elements.Fire.Unlocked == false
		and c.Elements.Fire.Level == CoreConfig.Upgrade.MaxLevel and c.Elements.Wind.Unlocked == false and c.Elements.Ice.Mastery == CoreConfig.MaxMastery)
check("lo desconocido se conserva (Note, Ice.Aura)", c.Note == "campo desconocido" and c.Elements.Ice.Aura == "fría")
local EXPECTED_CHANGES = {
	Selected = "Shadow", LastSwitchAt = "ayer",
	["Elements.Nature.Unlocked"] = false, ["Elements.Nature.UnlockedAt"] = 5,
	["Elements.Water.Level"] = "5", ["Elements.Water.Mastery"] = -3,
	["Elements.Fire.Unlocked"] = "sí", ["Elements.Fire.Level"] = 999,
	["Elements.Wind"] = "roto", ["Elements.Ice.Mastery"] = 1e13,
}
local archive = p.PetData.CoresArchive
check("archivo: la entrada antigua intacta + una nueva con TODOS los valores originales corregidos",
	#archive == 2 and same(archive[1], OLD_ENTRY) and same(archive[2].Changes, EXPECTED_CHANGES) and archive[2].At == os.time() and archive[2].Version == 3)
check("aviso en la consola", warnedWith("núcleos no válidos", warningsBefore))
exit(cid)
check("corrección y archivo se escriben en el MISMO guardado", same(record(13).Cores, c) and same(record(13).CoresArchive, archive))
warningsBefore = #warnings
cid, p = enter("Cid", 13)
check("al volver a cargar: nada nuevo que corregir ni archivar", #p.PetData.CoresArchive == 2 and not warnedWith("núcleos no válidos", warningsBefore))
exit(cid)

print("-- 6. Cores o CoresArchive con un tipo inesperado")
storeData.player_14 = { Version = 3, Cores = "texto", CoresArchive = "x" }
local dee
dee, p = enter("Dee", 14)
archive = p.PetData.CoresArchive
check("Cores de texto -> núcleos por defecto, y el texto se archiva", same(p.PetData.Cores, CoreLogic.empty()) and #archive == 2 and archive[2].Changes.Cores == "texto")
check("un CoresArchive que no es lista se conserva dentro de una entrada", archive[1].Changes.CoresArchive == "x")
exit(dee)
check("se guarda todo", same(record(14).CoresArchive, archive))
storeData.player_15 = { Version = 3, CoresArchive = { Weird = { 1, 2 } } }
local status, data = SaveService.load(15)
check("un CoresArchive con claves (no lista) se conserva entero", status == "Loaded" and #data.CoresArchive == 1 and same(data.CoresArchive[1].Changes.CoresArchive, { Weird = { 1, 2 } }))

print("-- 7. Archivo lleno: lo archivado nunca se borra ni se sustituye")
local full = {}
for i = 1, 20 do full[i] = { At = i, Changes = { Selected = "Ice" } } end
storeData.player_16 = { Version = 3, Cores = { Selected = "Ice" }, CoresArchive = deep(full) }
warningsBefore = #warnings
status, data = SaveService.load(16)
check("las 20 entradas existentes intactas, sin añadir más, con aviso", status == "Loaded" and same(data.CoresArchive, full) and warnedWith("CoresArchive lleno", warningsBefore))
check("y los núcleos quedan normalizados igualmente", data.Cores.Selected == "Nature")

print("-- 8. Vuelta atrás a v2 y de nuevo a v3")
local snap = deep(record(12))
status, data = SaveServiceV2.load(12)
check("el SaveService v2 carga un registro v3 sin errores (ignora Cores)", status == "Loaded" and data.Cores == nil and data.Energy == snap.Energy)
data.Energy = 77
check("y guarda", SaveServiceV2.save(12, data, true))
r = record(12)
check("v2 conserva Cores, CoresArchive y LastSeen exactamente", same(r.Cores, snap.Cores) and same(r.CoresArchive, snap.CoresArchive) and r.LastSeen == snap.LastSeen)
check("v2 escribe Version = 2 y su energía (marca de que pasó por v2)", r.Version == 2 and r.Energy == 77)
ben, p = enter("Ben", 12)
check("v3 vuelve a leer los mismos núcleos, sin correcciones, con la energía de v2", same(p.PetData.Cores, snap.Cores) and same(p.PetData.CoresArchive, snap.CoresArchive) and p.Energy == 77)
exit(ben)
check("y al guardar vuelve a la versión actual (11) sin perder nada", record(12).Version == 11 and same(record(12).Cores, snap.Cores) and same(record(12).CoresArchive, snap.CoresArchive))

print("-- 9. Carga fallida y salida durante la carga")
storeData.player_17 ={ Version = 2, Energy = 900, UpgradeLevels = { GeneratorPower = 4 } }
local snapshot17 = deep(storeData.player_17)
storeFail = 5
local eli = newPlayer("Eli", 17)
join(eli)
advance(30)
check("carga fallida: estado Failed", PlayerDataService.get(eli).DataState == "Failed")
advance(200)
exit(eli)
check("el registro no cambia: ni Cores, ni LastSeen, ni Version", same(storeData.player_17, snapshot17))
storeData.player_18 = { Version = 2, Energy = 300, UpgradeLevels = { GeneratorPower = 1 } }
storeLatency = 2
local fin = newPlayer("Fin", 18)
join(fin)
leave(fin)
advance(5)
storeLatency = 0
r = record(18)
check("salir durante la carga: energía intacta, núcleos por defecto y bloqueo liberado", r.Energy == 300 and r.UpgradeLevels.GeneratorPower == 1 and same(r.Cores, CoreLogic.empty()) and r.Version == 11 and r.Session == nil)

print("-- 9b. Un dato conservado no se archiva una y otra vez")
storeData.player_20 = { Version = 3, Cores = { Elements = { Nature = { Unlocked = true, Level = { Old = 3 } } } } }
local hal
for _ = 1, 3 do
	hal, p = enter("Hal", 20)
	exit(hal)
end
check("tras 3 cargas y guardados: Level de Naturaleza conservado y CoresArchive sin entradas", same(record(20).Cores.Elements.Nature.Level, { Old = 3 }) and record(20).CoresArchive == nil)

print("-- 10. Instantánea coherente: lo que cambia mientras se espera al DataStore")
storeData.player_19 = { Version = 3, Energy = 1000, UpgradeLevels = { GeneratorPower = 1 } }
local gus
gus, p = enter("Gus", 19)
storeLatency = 2
PlayerDataService.saveNow(gus)
advance(0.5) -- el guardado está esperando al DataStore
-- Cambio durante la espera (como lo haría una compra futura): núcleos y energía a la vez.
p.PetData.Cores.Elements.Water.Unlocked = true
p.Energy -= 100
advance(3)
storeLatency = 0
r = record(19)
check("se guarda la instantánea tomada ANTES de esperar: núcleos y energía coherentes entre sí", r.Cores.Elements.Water.Unlocked == false and r.Energy == 1000)
exit(gus)
check("y el cambio se guarda en el siguiente guardado", record(19).Cores.Elements.Water.Unlocked == true and record(19).Energy == 900)

-- `sub` está contenido en `sup`: todo lo que había sigue ahí con el mismo valor (las
-- misiones pueden AÑADIR progreso durante la sesión, pero nunca quitar).
local function contains(sup, sub)
	if type(sub) ~= "table" then return sup == sub end
	if type(sup) ~= "table" then return false end
	for k, v in sub do if not contains(sup[k], v) then return false end end
	return true
end

print("-- 11. Migración v1 -> v3 (sin Energy, UpgradeLevels ni Cores)")
local V1 = { Version = 1, Pets = { { Uid = "1", PetId = "MossFox" } }, Equipped = { "1" }, NextPetUid = 2, UnlockedZones = { "CrystalValley" }, Quests = { Stats = { Kills = 7 } } }
storeData.player_21 = deep(V1)
local ivy
ivy, p = enter("Ivy", 21)
check("v1 carga: energía y mejora iniciales, núcleos por defecto, nada archivado", p.DataState == "Loaded" and p.Energy == EconomyConfig.StartingEnergy and p.UpgradeLevels.GeneratorPower == 0 and same(p.PetData.Cores, CoreLogic.empty()) and #p.PetData.CoresArchive == 0)
local energy21 = p.Energy
exit(ivy)
r = record(21)
check("v1 guardado en la versión actual: Cores, LastSeen y Version 11", r.Version == 11 and same(r.Cores, CoreLogic.empty()) and r.LastSeen == os.time() and r.Session == nil)
check("v1: mascotas, equipadas, NextPetUid, zonas y estadísticas intactas", same(r.Pets, V1.Pets) and same(r.Equipped, V1.Equipped) and r.NextPetUid == 2 and same(r.UnlockedZones, V1.UnlockedZones) and r.Quests.Stats.Kills == 7 and r.Energy == energy21 and r.UpgradeLevels.GeneratorPower == 0)

print("-- 12. Migración v2 completa: NextPetUid, Tutorial.Step, Quests y mejoras archivadas")
local today = QuestLogic.dayOf(os.time())
local V2FULL = {
	Version = 2, Energy = 4321, UpgradeLevels = { GeneratorPower = 9, OldBoost = 3 },
	Pets = { { Uid = "1", PetId = "MossFox" }, { Uid = "4", PetId = "Sproutling" }, { Uid = "6", PetId = "ExtinctPet" } },
	Equipped = { "4" }, NextPetUid = 9, UnlockedZones = { "CrystalValley" },
	Tutorial = { Status = "Active", Step = 2 },
	Quests = {
		Stats = { Kills = 40, StrongKills = 6, BossKills = 1, EnergyEarned = 98765, PetAbilities = 12, TypeKills = { Slime = 30 }, ZoneKills = { CrystalValley = 10 } },
		Done = { DefeatFive = true }, Claimed = { DefeatFive = true, BuyUpgrade = true }, Achievements = { Resonance10 = true },
		Daily = { Day = today, Ids = { "DailyEnergy" }, Progress = { DailyEnergy = 40 }, Claimed = {}, Notified = {} },
	},
}
storeData.player_22 = deep(V2FULL)
local jo
jo, p = enter("Jo", 22)
check("la mascota de una especie desconocida queda archivada, no borrada", #p.PetData.Pets == 2 and #p.PetData.Archived == 1 and p.PetData.Archived[1].Uid == "6")
check("NextPetUid 9 y Tutorial en el paso 2 (activo) se cargan tal cual", p.PetData.NextPetUid == 9 and p.PetData.Tutorial.Status == "Active" and p.PetData.Tutorial.Step == 2)
check("la mejora desconocida no entra en el perfil pero se conserva archivada", p.UpgradeLevels.OldBoost == nil and p.PetData.ArchivedUpgrades.OldBoost == 3 and p.UpgradeLevels.GeneratorPower == 9)
check("misiones: todo lo guardado está en el perfil (estadísticas, hechas, reclamadas, logros y diaria)", contains(p.PetData.Quests, V2FULL.Quests))
local sessionQuests = QuestLogic.serialize(p.PetData.Quests)
local energy22 = p.Energy
exit(jo)
r = record(22)
check("guardado en la versión actual con núcleos por defecto y LastSeen", r.Version == 11 and same(r.Cores, CoreLogic.empty()) and r.LastSeen == os.time())
check("energía, nivel, NextPetUid y tutorial (paso 2) guardados sin pérdidas", r.Energy == energy22 and energy22 >= V2FULL.Energy and r.UpgradeLevels.GeneratorPower == 9 and r.NextPetUid == 9 and r.Tutorial.Status == "Active" and r.Tutorial.Step == 2)
check("las tres mascotas (también la archivada) y la equipada guardadas", #r.Pets == 3 and contains(r.Pets, V2FULL.Pets) and same(r.Equipped, { "4" }))
check("mejora archivada OldBoost = 3 guardada junto a GeneratorPower", r.UpgradeLevels.OldBoost == 3)
check("misiones completas: lo guardado es la sesión, y contiene todo lo anterior", same(r.Quests, sessionQuests) and contains(r.Quests, V2FULL.Quests))

print("-- 13. Guardado sin poseer el bloqueo válido: no se pisa a la otra sesión")
storeData.player_23 = { Version = 3, Energy = 100, UpgradeLevels = { GeneratorPower = 1 } }
local kai
kai, p = enter("Kai", 23)
-- Otro servidor tomó el control (bloqueo vigente) y guardó sus propios datos.
local otherCores = CoreLogic.empty()
otherCores.Elements.Water.Unlocked = true
storeData.player_23 = { Version = 3, Energy = 555, UpgradeLevels = { GeneratorPower = 4 }, Cores = deep(otherCores), LastSeen = 1700000999, Session = { JobId = "otro-servidor", Time = os.time() } }
local other = deep(storeData.player_23)
p.PetData.Cores.Elements.Fire.Unlocked = true -- cambio local de esta sesión
p.Energy = 9999
warningsBefore = #warnings
PlayerDataService.saveNow(kai)
advance(0)
check("guardado rechazado: el registro de la otra sesión queda EXACTAMENTE igual (Cores, LastSeen, energía)", same(record(23), other) and warnedWith("Otra sesión", warningsBefore))
check("la sesión lo sabe (SaveError) y el cambio queda pendiente", kai:GetAttribute("SaveError") == true and p.Dirty == true)
exit(kai)
check("al salir tampoco se sobrescribe ni se libera el bloqueo ajeno", same(record(23), other))
-- Bloqueo ajeno CADUCADO (servidor caído hace más de 30 min): sí se guarda.
storeData.player_24 = { Version = 3, Energy = 100, UpgradeLevels = { GeneratorPower = 1 } }
local lee
lee, p = enter("Lee", 24)
storeData.player_24.Session = { JobId = "otro-servidor", Time = os.time() - 31 * 60 }
p.PetData.Cores.Elements.Water.Unlocked = true
exit(lee)
check("con el bloqueo ajeno caducado se guarda: Cores y LastSeen de esta sesión, bloqueo liberado", record(24).Cores.Elements.Water.Unlocked == true and record(24).LastSeen == os.time() and record(24).Session == nil)

print("-- 14. Cierre del servidor (BindToClose)")
storeData.player_25 = { Version = 3, Energy = 100, UpgradeLevels = { GeneratorPower = 1 }, LastSeen = 1700000000 }
storeData.player_26 = { Version = 2, Energy = 200, UpgradeLevels = { GeneratorPower = 2 } }
local mia, mp = enter("Mia", 25)
local ned, np = enter("Ned", 26)
mp.PetData.Cores.Elements.Water.Unlocked = true
mp.PetData.Cores.Elements.Water.UnlockedAt = 1700000500
local closedAt = os.time()
task.spawn(closeCallbacks[1])
advance(1)
check("BindToClose guarda los núcleos de la sesión y LastSeen, y libera el bloqueo", record(25).Cores.Elements.Water.Unlocked == true and record(25).Cores.Elements.Water.UnlockedAt == 1700000500 and record(25).LastSeen == closedAt and record(25).Session == nil)
check("BindToClose migra también un perfil v2 conectado (Version 11, núcleos por defecto, energía intacta)", record(26).Version == 11 and same(record(26).Cores, CoreLogic.empty()) and record(26).Energy == np.Energy and record(26).LastSeen == closedAt)
check("BindToClose no toca el registro con bloqueo ajeno (sección 13)", same(record(23), other))

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
