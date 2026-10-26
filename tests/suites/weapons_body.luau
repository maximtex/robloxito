local failures = 0
local function check(name, ok)
	if not ok then
		failures += 1
	end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end

print("-- Configuración")
local starter = WeaponConfig.Weapons[WeaponConfig.StarterWeapon]
check("el arma inicial existe, es gratis y se vende", starter ~= nil and starter.Price == 0)
local configOK, orderOK, dropOK, zoneOK = true, true, true, true
local seenOrder = {}
for weaponId, def in WeaponConfig.Weapons do
	if not (def.Damage > 0 and def.Cooldown > 0 and def.Range > 0 and def.UpgradeCost > 0 and type(def.DisplayName) == "string") then
		configOK = false
	end
	if seenOrder[def.Order] then
		orderOK = false
	end
	seenOrder[def.Order] = true
	if def.BossDrop then
		local boss = EnemyConfig.Types[def.BossDrop]
		if not (boss and boss.Kind == "Boss" and def.Price == nil) then
			dropOK = false
		end
	elseif def.Price == nil then
		dropOK = false -- ni se vende ni lo suelta un jefe: no se podría conseguir
	end
	if def.Requires and def.Requires.Zone and not ZoneConfig.Zones[def.Requires.Zone] then
		zoneOK = false
	end
end
check("todas tienen daño, ritmo, alcance y coste de mejora", configOK)
check("cada una tiene su sitio en la Armería", orderOK)
check("cada arma se compra o la suelta un jefe que existe", dropOK)
check("las zonas que piden existen", zoneOK)

print("-- Progresión de poder")
local order = WeaponLogic.ordered("Weapons")
check("orden de la Armería: empieza por el láser (14: las de la Tundra, la Fortaleza y las 4 del Mundo 2 al final)", order[1] == WeaponConfig.StarterWeapon and #order == 14)
local growing = true
for index = 2, #order do
	if WeaponLogic.dps(order[index], 0) <= WeaponLogic.dps(order[index - 1], 0) then
		growing = false
	end
end
check("cada arma hace más daño por segundo que la anterior", growing)
check("sin categoría: todas (armas, espadas, guantes y bastones)", #WeaponLogic.ordered() == 56)
for _, category in { "Warrior", "Fists", "Magic" } do
	local list = WeaponLogic.ordered(category)
	local up, sameTiers = true, true
	for index = 2, #list do
		if WeaponLogic.dps(list[index], 0) <= WeaponLogic.dps(list[index - 1], 0) then
			up = false
		end
	end
	for index, id in list do
		-- el mismo DPS que el arma de su mismo puesto (la progresión de cada estilo va igual)
		if math.abs(WeaponLogic.dps(id, 0) / WeaponLogic.dps(order[index], 0) - 1) > 0.02 then
			sameTiers = false
		end
	end
	check(("%s: 14, empieza por %s (gratis), cada uno pega más y al ritmo de las armas"):format(category, WeaponConfig.Starters[category]),
		#list == 14 and list[1] == WeaponConfig.Starters[category] and WeaponConfig.Weapons[list[1]].Price == 0 and up and sameTiers)
end
local bossDrops = {}
for weaponId, def in WeaponConfig.Weapons do
	if def.BossDrop then
		bossDrops[def.BossDrop] = bossDrops[def.BossDrop] or {}
		bossDrops[def.BossDrop][WeaponLogic.category(weaponId)] = weaponId
	end
end
local dropsOk = true
for _, boss in { "ForestWarden", "AmethystColossus", "CalderaTitan", "IceGolem", "GoblinKing" } do
	local drops = bossDrops[boss]
	if not (drops and drops.Weapons and drops.Warrior and drops.Fists and drops.Magic) then
		dropsOk = false
	end
end
check("cada jefe suelta un arma, una espada, unos guantes y un bastón (el de tu estilo)", dropsOk)
-- Armería del Mundo 2: 4 de cada estilo, solo allí, se compran (con el Mundo 2 abierto) y
-- pegan más que todo lo del Mundo 1
local world2Ok = true
for _, category in { "Weapons", "Warrior", "Fists", "Magic" } do
	local count, strongest1, weakest2 = 0, 0, math.huge
	for _, id in WeaponLogic.ordered(category) do
		local def = WeaponConfig.Weapons[id]
		local dps = WeaponLogic.dps(id, 0)
		if WeaponLogic.world(id) == 2 then
			count += 1
			weakest2 = math.min(weakest2, dps)
			world2Ok = world2Ok and def.Price ~= nil and def.Requires ~= nil and def.Requires.Zone == "World2" and def.BossDrop == nil
		else
			strongest1 = math.max(strongest1, dps)
		end
	end
	world2Ok = world2Ok and count == 4 and weakest2 > strongest1
end
check("Mundo 2: 4 armas, 4 espadas, 4 guantes y 4 bastones solo de su Armería, más fuertes que todo lo del Mundo 1", world2Ok)

print("-- Armas de fuego (tipos) y elementos de los bastones")
local gunsOk, kinds = true, {}
for _, id in WeaponLogic.ordered("Weapons") do
	local def = WeaponConfig.Weapons[id]
	if not (def.Gun and WeaponConfig.Guns[def.Gun]) then
		gunsOk = false
	else
		kinds[def.Gun] = (kinds[def.Gun] or 0) + 1
	end
end
check("cada arma tiene su tipo de arma de fuego (pistola, rifle, escopeta, francotirador o bazuca)", gunsOk and kinds.Pistol and kinds.Rifle and kinds.Shotgun and kinds.Sniper and kinds.Launcher)
check("el láser es una pistola; el bláster, una escopeta; el arco, un francotirador; el cañón del vacío, una bazuca", GunLogic.kind("Laser") == "Pistol" and GunLogic.kind("PlasmaBlaster") == "Shotgun" and GunLogic.kind("ThornBow") == "Sniper" and GunLogic.kind("VoidCannon") == "Launcher" and GunLogic.kind("CrystalCannon") == "Rifle")
local balanced = true
for _, id in WeaponLogic.ordered("Weapons") do
	local ratio = GunLogic.sustainedRatio(GunLogic.spec(id), WeaponConfig.Weapons[id].Cooldown)
	if ratio < 0.95 or ratio > 1.35 then
		balanced = false
		print("   desequilibrada:", id, ratio)
	end
end
check("contando la recarga, cada arma hace entre ×0.95 y ×1.35 de su DPS (si entran todas)", balanced)
local laser = GunLogic.applyStats({ Shot = 8, Cooldown = 0.4, Range = 60, WeaponId = "Laser" }, "Laser")
check("pistola: 8 × 1.35 por disparo, cada 0.4 s, 12 balas", math.abs(laser.Shot - 10.8) < 1e-9 and laser.Cooldown == 0.4 and laser.Magazine == 12 and laser.Range == 60 and laser.Gun == "Pistol")
local aimed = GunLogic.applyStats({ Shot = 8, Cooldown = 0.4, Range = 60 }, "Laser", true)
check("apuntando: más alcance", math.abs(aimed.Range - 69) < 1e-9)
local pellets = GunLogic.directions(1, 0, GunLogic.spec("PlasmaBlaster"), false, function()
	return 0.5
end)
local spreadOk = #pellets == 8
for _, direction in pellets do
	local angle = math.deg(math.abs(math.atan2(direction[2], direction[1])))
	spreadOk = spreadOk and angle <= 10 + 1e-6 and math.abs(direction[1] ^ 2 + direction[2] ^ 2 - 1) < 1e-9
end
check("escopeta: 8 perdigones repartidos en ±10°", spreadOk)
local straight = GunLogic.directions(0, 1, GunLogic.spec("Laser"), true, function()
	return 0.99
end)
check("apuntando con la pistola la bala no se desvía", #straight == 1 and math.abs(straight[1][1]) < 1e-9 and math.abs(straight[1][2] - 1) < 1e-9)
check("francotirador: atraviesa a 2 más (×0.7, ×0.49)", GunLogic.maxHits(GunLogic.spec("ThornBow")) == 3 and math.abs(GunLogic.pierceFactor(GunLogic.spec("ThornBow"), 3) - 0.49) < 1e-9)
check("bazuca: el cohete tarda según la distancia", math.abs(GunLogic.travelTime(GunLogic.spec("VoidCannon"), 55) - 0.5) < 1e-9 and GunLogic.travelTime(GunLogic.spec("Laser"), 55) == 0)
local elementsOk = true
for _, id in WeaponLogic.ordered("Magic") do
	local element = WeaponConfig.Weapons[id].Element
	if not (element and StyleConfig.Styles.Magic.Elements[element] and MagicLogic.element(id) == element) then
		elementsOk = false
	end
end
check("cada bastón tiene su elemento (fuego, hielo, rayo, naturaleza, sombra o celestial)", elementsOk and MagicLogic.element("ApprenticeWand") == "Fire" and MagicLogic.element("FrostStaff") == "Ice")
check("los del Mundo 1 siguen en su Armería (mundo 1)", WeaponLogic.world("Laser") == 1 and WeaponLogic.world("GoblinCannon") == 1 and WeaponLogic.world("VoidAnnihilator") == 2)
check("láser nivel 0: 8 por disparo, 20/s y poder 10 (como el antiguo golpe)", WeaponLogic.shotDamage("Laser", 0) == 8 and WeaponLogic.dps("Laser", 0) == 20 and WeaponLogic.power("Laser", 0) == 10)
check("cada nivel suma un 15 %", WeaponLogic.shotDamage("Laser", 10) == 20)
check("mascotas ×1.5 → +25 % (la mitad de su bonificación)", WeaponLogic.shotDamage("Laser", 0, 1.5) == 10)
check("renacimiento ×2 duplica", WeaponLogic.shotDamage("Laser", 0, 1, 2) == 16)
check("valores no válidos no rompen ni bajan de la base", WeaponLogic.shotDamage("Laser", 0 / 0, 0 / 0, -1) == 8 and WeaponLogic.shotDamage("Nope", 0) == 8)
check("la cadencia acorta el tiempo entre disparos con un tope", WeaponLogic.cooldown("Laser", 4) == 0.4 * 0.9 and WeaponLogic.cooldown("Laser", 999) == 0.4 * WeaponConfig.MinCadenceFactor)
local plasma = WeaponConfig.Weapons.PlasmaBlaster
check("el plasma no es solo más daño: explota en área y dispara más lento", plasma.Effect.Splash ~= nil and plasma.Cooldown > starter.Cooldown)
check("el cristal salta entre enemigos", WeaponConfig.Weapons.CrystalCannon.Effect.Chain.Count >= 2)

print("-- Comprar, mejorar y equipar")
local data = WeaponLogic.empty()
check("datos nuevos: solo el láser, equipado", WeaponLogic.owns(data, "Laser") and not WeaponLogic.owns(data, "PlasmaBlaster") and data.Equipped == "Laser")
local code, price = WeaponLogic.buy(data, "PlasmaBlaster", {}, 3999)
check("sin dinero suficiente: InsufficientMoney con el precio", code == "InsufficientMoney" and price == 4000 and not WeaponLogic.owns(data, "PlasmaBlaster"))
code, price = WeaponLogic.buy(data, "PlasmaBlaster", {}, 4000)
check("con 4000: comprada", code == "Success" and price == 4000 and WeaponLogic.owns(data, "PlasmaBlaster") and WeaponLogic.level(data, "PlasmaBlaster") == 0)
check("no se compra dos veces", (WeaponLogic.buy(data, "PlasmaBlaster", {}, 1e9)) == "AlreadyOwned")
check("el cristal pide el Valle desbloqueado", (WeaponLogic.buy(data, "CrystalCannon", {}, 1e9)) == "Locked" and (WeaponLogic.buy(data, "CrystalCannon", { "CrystalValley" }, 1e9)) == "Success")
check("las de jefe no se venden", (WeaponLogic.buy(data, "ThornBow", { "CrystalValley", "EmberCaldera" }, 1e9)) == "NotForSale")
check("ids raros, dinero NaN o infinito: rechazado", (WeaponLogic.buy(data, "Nope", {}, 1e9)) == "InvalidRequest" and (WeaponLogic.buy(data, "VoidCannon", { "EmberCaldera" }, 0 / 0)) == "InsufficientMoney" and (WeaponLogic.buy(data, "VoidCannon", { "EmberCaldera" }, math.huge)) == "InsufficientMoney")
check("equipar una que no tiene: NotOwned", WeaponLogic.equip(data, "ThornBow") == "NotOwned" and data.Equipped == "Laser")
check("equipar el plasma", WeaponLogic.equip(data, "PlasmaBlaster") == "Success" and data.Equipped == "PlasmaBlaster")
check("un jefe regala su arma una vez", WeaponLogic.grant(data, "ThornBow") == true and WeaponLogic.grant(data, "ThornBow") == false and WeaponLogic.owns(data, "ThornBow"))
code, price = WeaponLogic.upgrade(data, "Laser", 24)
check("mejorar el láser cuesta 25 al principio", code == "InsufficientMoney" and price == 25)
code, price = WeaponLogic.upgrade(data, "Laser", 25)
check("con 25: nivel 1", code == "Success" and price == 25 and WeaponLogic.level(data, "Laser") == 1)
check("el siguiente nivel cuesta más", WeaponLogic.upgradeCost("Laser", 1) == math.floor(25 * WeaponConfig.UpgradeGrowth))
check("no se mejora un arma que no tiene", (WeaponLogic.upgrade(data, "MagmaHeart", 1e12)) == "NotOwned")
data.Levels.Laser = WeaponConfig.MaxLevel
check("al nivel máximo: MaxLevel y sin coste", (WeaponLogic.upgrade(data, "Laser", 1e12)) == "MaxLevel" and WeaponLogic.upgradeCost("Laser", WeaponConfig.MaxLevel) == nil)

print("-- Guantes y bastones (el progreso de cada estilo, aparte)")
local gear = WeaponLogic.empty()
check("datos nuevos: el láser, la espada de madera, los guantes de cuero y la varita, cada uno equipado en su estilo", WeaponLogic.owns(gear, "Laser") and WeaponLogic.owns(gear, "WoodenSword") and WeaponLogic.owns(gear, "LeatherGloves") and WeaponLogic.owns(gear, "ApprenticeWand")
	and WeaponLogic.equippedFor(gear, "Weapons") == "Laser" and WeaponLogic.equippedFor(gear, "Warrior") == "WoodenSword" and WeaponLogic.equippedFor(gear, "Fists") == "LeatherGloves" and WeaponLogic.equippedFor(gear, "Magic") == "ApprenticeWand")
check("las espadas se compran y se equipan aparte", (WeaponLogic.buy(gear, "IronSword", {}, 4000)) == "Success" and WeaponLogic.equip(gear, "IronSword") == "Success" and WeaponLogic.equippedFor(gear, "Warrior") == "IronSword" and gear.Equipped == "Laser")
check("los guantes se compran con 💰 como las armas", (WeaponLogic.buy(gear, "IronKnuckles", {}, 4000)) == "Success" and WeaponLogic.equip(gear, "IronKnuckles") == "Success")
check("equipar unos guantes no cambia el arma ni el bastón", gear.Equipped == "Laser" and WeaponLogic.equippedFor(gear, "Fists") == "IronKnuckles" and WeaponLogic.equippedFor(gear, "Magic") == "ApprenticeWand")
check("y cada uno tiene su nivel", (WeaponLogic.upgrade(gear, "IronKnuckles", 1e6)) == "Success" and WeaponLogic.level(gear, "IronKnuckles") == 1 and WeaponLogic.level(gear, "Laser") == 0)
local gearBack = WeaponLogic.sanitize(WeaponLogic.serialize(gear))
check("se guarda lo equipado de cada estilo", gearBack.Slots.Fists == "IronKnuckles" and gearBack.Slots.Magic == "ApprenticeWand" and gearBack.Equipped == "Laser" and gearBack.Levels.IronKnuckles == 1)
local oldSave = WeaponLogic.sanitize({ Owned = { "Laser", "PlasmaBlaster" }, Levels = { PlasmaBlaster = 2 }, Equipped = "PlasmaBlaster" })
check("partida de antes (sin guantes, espada ni bastón): recibe los iniciales y conserva su arma", oldSave.Equipped == "PlasmaBlaster" and WeaponLogic.owns(oldSave, "LeatherGloves") and WeaponLogic.equippedFor(oldSave, "Magic") == "ApprenticeWand" and WeaponLogic.equippedFor(oldSave, "Warrior") == "WoodenSword")
local mixed = WeaponLogic.sanitize({ Owned = { "Laser", "IronKnuckles" }, Equipped = "IronKnuckles", Slots = { Fists = "Laser", Magic = "VoidStaff" } })
check("datos cruzados (guantes como arma, un arma como guantes, un bastón que no tiene): cada uno a lo suyo", mixed.Equipped == "Laser" and mixed.Slots.Fists == "LeatherGloves" and mixed.Slots.Magic == "ApprenticeWand")

print("-- Guardado")
local saved = WeaponLogic.serialize(data)
local back = WeaponLogic.sanitize(saved)
check("guardar y cargar conserva armas, niveles y la equipada", back.Equipped == "PlasmaBlaster" and WeaponLogic.owns(back, "ThornBow") and WeaponLogic.owns(back, "CrystalCannon") and back.Levels.Laser == WeaponConfig.MaxLevel)
local messy = WeaponLogic.sanitize({ Owned = { "Laser", "OldGun", 5 }, Levels = { Laser = 999, OldGun = 3, PlasmaBlaster = 4 }, Equipped = "PlasmaBlaster" })
check("datos sucios: niveles al tope, sin armas que no tiene, la equipada vuelve al láser", messy.Levels.Laser == WeaponConfig.MaxLevel and messy.Levels.PlasmaBlaster == nil and messy.Equipped == "Laser")
check("las armas que ya no existen se archivan, no se borran", messy.Archived ~= nil and messy.Archived.OldGun == true and WeaponLogic.serialize(messy).Archived.OldGun == true)
check("nada guardado o basura: datos iniciales", WeaponLogic.sanitize(nil).Equipped == "Laser" and WeaponLogic.sanitize("x").Owned.Laser == true)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
