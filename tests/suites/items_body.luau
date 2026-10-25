local failures = 0
local function check(name, ok)
	if not ok then
		failures += 1
	end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end

-- Azar fijo: devuelve los valores de la lista en bucle.
local function sequence(values)
	local index = 0
	return function()
		index = index % #values + 1
		return values[index]
	end
end

local Codes = { Success = "Success", InvalidRequest = "InvalidRequest", NotOwned = "NotOwned", Full = "Full" }
local NOW = 1700000000
local SECONDS = ItemConfig.Potions.Energy.Seconds

print("-- 1. Configuración")
local potionsOk = true
for id, def in ItemConfig.Potions do
	if not (def.Seconds > 0 and def.Seconds <= ItemConfig.MaxBoostSeconds and def.Multiplier >= 1 and def.Icon and def.DisplayName) then
		potionsOk = false
		print("   ", id)
	end
end
check("cada poción dura menos que el máximo acumulado y multiplica", potionsOk)
local dropsOk = true
for id, drop in ItemConfig.BossDrops do
	if id ~= "Default" and not (EnemyConfig.Types[id] and EnemyConfig.Types[id].Kind == "Boss") then
		dropsOk = false
		print("   jefe", id)
	end
	if drop.Egg and not EggConfig.Eggs[drop.Egg] then
		dropsOk = false
		print("   huevo", drop.Egg)
	end
end
check("el botín es de jefes que existen y suelta huevos que existen", dropsOk)
local titlesOk = true
for id, def in ItemConfig.Titles do
	if def.Boss and not EnemyConfig.Types[def.Boss] then
		titlesOk = false
		print("   ", id)
	end
	if def.Stat and not (type(def.Goal) == "number" and def.Goal > 0) then
		titlesOk = false
		print("   ", id)
	end
end
check("los títulos piden jefes que existen o una meta", titlesOk)
check("orden de las pociones y los títulos", ItemLogic.potionOrder()[1] == "Energy" and #ItemLogic.potionOrder() == 4 and ItemLogic.titleOrder()[1] == "Novato")

print("-- 2. Datos guardados")
local fresh = ItemLogic.sanitize(nil, NOW)
check("sin datos (guardado v8 o anterior): inventario vacío", next(fresh.Potions) == nil and next(fresh.Eggs) == nil and next(fresh.Boosts) == nil and fresh.Title == "" and fresh.TitleSet == false and fresh.PotionsUsed == 0)
local dirty = ItemLogic.sanitize({
	Potions = { Energy = 3.7, Damage = -1, Money = 0 / 0, Luck = 5000, [5] = 2 },
	Eggs = { AncientEgg = 2, [""] = 4 },
	Boosts = { Energy = 300, Damage = -5, Nope = 100, Money = 99999999 },
	Titles = { Novato = true, Cazador = "sí" },
	Title = "Cazador",
	TitleSet = 1,
	PotionsUsed = 0 / 0,
}, NOW)
check("cantidades: enteras, positivas y con tope", dirty.Potions.Energy == 3 and dirty.Potions.Damage == nil and dirty.Potions.Money == nil and dirty.Potions.Luck == ItemConfig.MaxStack and dirty.Potions[5] == nil)
check("huevos sin id vacío", dirty.Eggs.AncientEgg == 2 and dirty.Eggs[""] == nil)
check("pociones activas: el tiempo que quedaba cuenta desde ahora (con tope)", dirty.Boosts.Energy == NOW + 300 and dirty.Boosts.Damage == nil and dirty.Boosts.Nope == nil and dirty.Boosts.Money == NOW + ItemConfig.MaxBoostSeconds)
check("títulos: solo los de verdad; el equipado tiene que ser suyo", dirty.Titles.Novato == true and dirty.Titles.Cazador == nil and dirty.Title == "" and dirty.TitleSet == false and dirty.PotionsUsed == 0)
local saved = ItemLogic.serialize(dirty, NOW + 100)
check("al guardar, las activas como segundos que quedan", saved.Boosts.Energy == 200 and saved.Potions.Energy == 3 and saved ~= dirty)
local later = ItemLogic.sanitize(saved, NOW + 86400)
check("sin jugar el tiempo no corre: al volver un día después le quedan 200 s", ItemLogic.remaining(later, "Energy", NOW + 86400) == 200)
check("las que ya se acabaron no se guardan", ItemLogic.serialize(dirty, NOW + 400).Boosts.Energy == nil)

print("-- 3. Pociones")
local data = ItemLogic.empty()
check("sin la poción: NotOwned", ItemLogic.usePotion(data, "Energy", NOW, Codes) == Codes.NotOwned)
check("poción inventada: InvalidRequest", ItemLogic.usePotion(data, "Nope", NOW, Codes) == Codes.InvalidRequest)
check("el botín no añade pociones inventadas", ItemLogic.addPotion(data, "Nope", 1) == 0 and data.Potions.Nope == nil)
check("suma pociones", ItemLogic.addPotion(data, "Energy", 2) == 2 and data.Potions.Energy == 2)
check("inactiva: multiplica por 1", ItemLogic.multiplier(data, "Energy", NOW) == 1 and ItemLogic.multiplier(nil, "Energy", NOW) == 1)
local code, total = ItemLogic.usePotion(data, "Energy", NOW, Codes)
check("tomarla: Success con su tiempo", code == Codes.Success and total == SECONDS and data.Potions.Energy == 1)
check("activa: ×2 Energía", ItemLogic.isActive(data, "Energy", NOW + 1) and ItemLogic.multiplier(data, "Energy", NOW + 1) == 2)
check("no toca las demás", ItemLogic.multiplier(data, "Damage", NOW + 1) == 1)
code, total = ItemLogic.usePotion(data, "Energy", NOW + 60, Codes)
check("otra igual suma su tiempo al que queda", code == Codes.Success and total == 2 * SECONDS - 60 and data.Potions.Energy == nil and data.PotionsUsed == 2)
data.Potions.Energy = 1
data.Boosts.Energy = NOW + ItemConfig.MaxBoostSeconds - 60
check("con el máximo acumulado: Full y no se gasta", ItemLogic.usePotion(data, "Energy", NOW, Codes) == Codes.Full and data.Potions.Energy == 1)
local ended = ItemLogic.expire(data, NOW + ItemConfig.MaxBoostSeconds)
check("al acabarse se quita y avisa", #ended == 1 and ended[1] == "Energy" and data.Boosts.Energy == nil and ItemLogic.multiplier(data, "Energy", NOW + ItemConfig.MaxBoostSeconds) == 1)
check("pociones con tope", ItemLogic.addPotion(data, "Luck", ItemConfig.MaxStack + 5) == ItemConfig.MaxStack and data.Potions.Luck == ItemConfig.MaxStack)

print("-- 4. Huevos guardados")
local eggs = ItemLogic.empty()
check("sin huevo no se abre", not ItemLogic.hasEgg(eggs, "AncientEgg") and not ItemLogic.takeEgg(eggs, "AncientEgg"))
ItemLogic.addEgg(eggs, "AncientEgg", 2)
check("dos huevos: se abren de uno en uno y desaparece al acabarse", ItemLogic.takeEgg(eggs, "AncientEgg") and eggs.Eggs.AncientEgg == 1 and ItemLogic.takeEgg(eggs, "AncientEgg") and eggs.Eggs.AncientEgg == nil)

print("-- 5. Botín de los jefes")
local first = ItemLogic.potionOrder()[1]
local drop = ItemLogic.rollBossDrop("ForestWarden", sequence({ 0, 0 }), EggConfig.Eggs)
check("Guardián: una poción y, con suerte, su huevo", #drop.Potions == 1 and drop.Potions[1] == first and drop.Egg == ItemConfig.BossDrops.ForestWarden.Egg)
drop = ItemLogic.rollBossDrop("ForestWarden", sequence({ 0.99, 0.99 }), EggConfig.Eggs)
check("sin suerte: solo la poción (la última del sorteo)", #drop.Potions == 1 and drop.Potions[1] == ItemLogic.potionOrder()[#ItemLogic.potionOrder()] and drop.Egg == nil)
check("si el huevo no existe no se suelta", ItemLogic.rollBossDrop("ForestWarden", sequence({ 0 }), {}).Egg == nil)
drop = ItemLogic.rollBossDrop("JefeNuevo", sequence({ 0 }), EggConfig.Eggs)
check("un jefe sin botín propio usa Default (sin huevo)", #drop.Potions == ItemConfig.BossDrops.Default.Potions and drop.Egg == nil)

print("-- 6. Títulos")
local titles = ItemLogic.empty()
local function stats(over)
	local s = { Kills = 0, Rebirths = 0, Pets = 0, PotionsUsed = 0, EnergyEarned = 0, Bosses = {} }
	for k, v in over or {} do
		s[k] = v
	end
	return s
end
local got = ItemLogic.grantTitles(titles, stats())
check("al empezar: Novato, y se pone solo", #got == 1 and got[1] == "Novato" and titles.Title == "Novato")
check("y no se concede dos veces", #ItemLogic.grantTitles(titles, stats()) == 0)
local value, goal = ItemLogic.titleProgress(ItemConfig.Titles.Cazador, stats({ Kills = 40 }))
check("progreso: 40 / 100 enemigos", value == 40 and goal == 100)
got = ItemLogic.grantTitles(titles, stats({ Kills = 150 }))
check("100 enemigos: Cazador, y se pone el nuevo", #got == 1 and got[1] == "Cazador" and titles.Title == "Cazador")
check("quitarlo a mano", ItemLogic.equipTitle(titles, "", Codes) == Codes.Success and titles.Title == "" and titles.TitleSet == true)
got = ItemLogic.grantTitles(titles, stats({ Kills = 1000, Bosses = { ForestWarden = 1 } }))
check("tras elegir a mano, los nuevos no se ponen solos", #got == 2 and titles.Title == "" and titles.Titles.Exterminador and titles.Titles.LeyendaBosque)
check("solo se pone uno conseguido", ItemLogic.equipTitle(titles, "Inmortal", Codes) == Codes.NotOwned and ItemLogic.equipTitle(titles, "Nope", Codes) == Codes.NotOwned)
check("ponerse uno conseguido", ItemLogic.equipTitle(titles, "LeyendaBosque", Codes) == Codes.Success and titles.Title == "LeyendaBosque")
value, goal = ItemLogic.titleProgress(ItemConfig.Titles.SenorMagma, stats())
check("los de jefe van de 0 a 1", value == 0 and goal == 1)

print("-- 7. Perfil")
check("artículos del perfil (o nil si aún no los tiene)", ItemLogic.ofProfile({ PetData = { Items = titles } }) == titles and ItemLogic.ofProfile({ PetData = {} }) == nil and ItemLogic.ofProfile(nil) == nil)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
