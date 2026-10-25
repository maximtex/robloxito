-- Clases de los estilos (ClassLogic, pura): configuración, comprar, subir, elegir, guardado
-- y las pasivas ya juntas (mods), más cómo suman a las del estilo (StyleLogic).

local failures = 0
local function check(name, ok)
	if not ok then
		failures += 1
	end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local function near(a, b, eps)
	return math.abs(a - b) < (eps or 1e-9)
end

print("-- Configuración")
local configOk = true
local seen = {}
for _, styleId in StyleConfig.Order do
	local ids = ClassConfig.Styles[styleId]
	configOk = configOk and ids ~= nil and #ids == 5
	local lastPrice = -1
	for index, classId in ids or {} do
		local def = ClassConfig.Classes[classId]
		configOk = configOk and def ~= nil and def.Style == styleId and not seen[classId]
			and type(def.Name) == "string" and type(def.Icon) == "string" and type(def.Text) == "string"
			and type(def.Price) == "number" and def.Price > lastPrice and type(def.Bonuses) == "table"
		seen[classId] = true
		if index == 1 then
			configOk = configOk and def.Price == 0
		end
		lastPrice = def.Price
		for key, spec in def.Bonuses do
			configOk = configOk and ClassConfig.Bonuses[key] ~= nil and (type(spec) == "number" or (type(spec) == "table" and spec[1] <= spec[2]))
		end
	end
end
local total = 0
for _ in ClassConfig.Classes do
	total += 1
end
check("5 clases por estilo (15), la primera gratis y cada vez más caras, con pasivas conocidas", configOk and total == 15)
local lastOk = true
for _, styleId in StyleConfig.Order do
	local ids = ClassConfig.Styles[styleId]
	local count = 0
	for _ in ClassConfig.Classes[ids[5]].Bonuses do
		count += 1
	end
	lastOk = lastOk and count == 3
end
check("la última de cada estilo (la definitiva) junta tres pasivas", lastOk)

print("-- Datos y acciones")
local data = ClassLogic.empty()
check("al empezar: la gratis de cada estilo a nivel 1 y activa", data.Owned.Soldier == 1 and data.Owned.Brawler == 1 and data.Owned.Apprentice == 1
	and ClassLogic.active(data, "Weapons") == "Soldier" and ClassLogic.active(data, "Fists") == "Brawler" and ClassLogic.active(data, "Magic") == "Apprentice"
	and data.Owned.Sniper == nil)
local code, cost = ClassLogic.buy(data, "Sniper", 199)
check("comprar sin 💎 suficientes no cambia nada", code == "InsufficientEnergy" and cost == 200 and data.Owned.Sniper == nil)
code, cost = ClassLogic.buy(data, "Sniper", 200)
check("comprar: queda a nivel 1 y activa en su estilo", code == "Success" and cost == 200 and data.Owned.Sniper == 1 and ClassLogic.active(data, "Weapons") == "Sniper")
check("comprarla otra vez: ya la tienes", (ClassLogic.buy(data, "Sniper", 9999)) == "AlreadyOwned")
check("comprar algo que no existe", (ClassLogic.buy(data, "Nope", 9999)) == "InvalidRequest" and (ClassLogic.buy(data, 5, 9999)) == "InvalidRequest")
check("elegir: una que no tienes no se pone", ClassLogic.select(data, "Gunner") == "NotOwned" and ClassLogic.active(data, "Weapons") == "Sniper")
check("elegir otra que tienes: gratis y solo cambia su estilo", ClassLogic.select(data, "Soldier") == "Success" and ClassLogic.active(data, "Weapons") == "Soldier" and ClassLogic.active(data, "Fists") == "Brawler")
local c1 = ClassLogic.upgradeCost("Sniper", 1)
local c2 = ClassLogic.upgradeCost("Sniper", 2)
check("subir cuesta cada vez más; al máximo no se puede", c1 == math.floor(ClassConfig.Levels.UpgradeBase * 1) and c2 > c1 and ClassLogic.upgradeCost("Sniper", ClassConfig.Levels.Max) == nil)
check("la gratis se sube más barata que las de 💎", ClassLogic.upgradeCost("Soldier", 1) < ClassLogic.upgradeCost("Sniper", 1) and ClassLogic.upgradeCost("Commando", 1) > ClassLogic.upgradeCost("Demolisher", 1))
code, cost = ClassLogic.upgrade(data, "Sniper", c1 - 1)
check("subir sin 💎 suficientes", code == "InsufficientEnergy" and cost == c1 and data.Owned.Sniper == 1)
code, cost = ClassLogic.upgrade(data, "Sniper", c1)
check("subir un nivel", code == "Success" and cost == c1 and data.Owned.Sniper == 2)
check("subir una que no tienes", (ClassLogic.upgrade(data, "Gunner", 1e9)) == "NotOwned")
for _ = 1, 10 do
	ClassLogic.upgrade(data, "Sniper", 1e9)
end
check("hasta el nivel máximo y no más", data.Owned.Sniper == ClassConfig.Levels.Max and (ClassLogic.upgrade(data, "Sniper", 1e9)) == "MaxLevel")

print("-- Guardado y atributos")
local saved = ClassLogic.serialize(data)
local loaded = ClassLogic.sanitize(saved)
check("guardar y cargar: igual", loaded.Owned.Sniper == ClassConfig.Levels.Max and loaded.Owned.Soldier == 1 and ClassLogic.active(loaded, "Weapons") == "Soldier")
local messy = ClassLogic.sanitize({
	Owned = { Sniper = 99, Gunner = 0 / 0, Tank = 2.7, OldClass = 3 },
	Active = { Weapons = "Gunner", Fists = "Tank", Magic = "Sniper" },
	Archived = { Older = 1 },
})
check("datos sucios: nivel al tope, lo roto fuera, la activa debe ser suya y de su estilo, lo viejo archivado",
	messy.Owned.Sniper == ClassConfig.Levels.Max and messy.Owned.Gunner == nil and messy.Owned.Tank == 2 and messy.Owned.Soldier == 1
		and ClassLogic.active(messy, "Weapons") == "Soldier" and ClassLogic.active(messy, "Fists") == "Tank" and ClassLogic.active(messy, "Magic") == "Apprentice"
		and messy.Archived.OldClass == 3 and messy.Archived.Older == 1)
check("sin datos (partidas viejas): la gratis de cada estilo", ClassLogic.sanitize(nil).Owned.Brawler == 1 and ClassLogic.active(ClassLogic.sanitize("x"), "Magic") == "Apprentice")
local parsed = ClassLogic.parse(ClassLogic.ownedText(data), ClassLogic.activeText(data))
check("atributos para el cliente: ida y vuelta", parsed.Owned.Sniper == data.Owned.Sniper and ClassLogic.active(parsed, "Weapons") == "Soldier" and ClassLogic.active(parsed, "Fists") == "Brawler")

print("-- Pasivas")
check("valor a nivel 1 y al máximo; en medio en línea recta", near(ClassLogic.bonus("Sniper", "Range", 1), 0.2) and near(ClassLogic.bonus("Sniper", "Range", ClassConfig.Levels.Max), 0.5)
	and near(ClassLogic.bonus("Sniper", "Range", 3), 0.35) and ClassLogic.bonus("Sniper", "Damage", 3) == 0 and ClassLogic.bonus("Champion", "ComboEvery", 4) == 1)
local neutral = ClassLogic.mods(nil, "Nope")
check("sin estilo válido: neutras", neutral.Damage == 1 and neutral.Cooldown == 1 and neutral.ClassId == nil)
local soldier = ClassLogic.mods(ClassLogic.empty(), "Weapons")
check("Soldado nivel 1: +8 % de daño y ataque un 5 % más rápido", soldier.ClassId == "Soldier" and near(soldier.Damage, 1.08) and near(soldier.Cooldown, 1 / 1.05) and soldier.Range == 1)
local tankData = ClassLogic.empty()
ClassLogic.buy(tankData, "Tank", 1e9)
local tank = ClassLogic.mods(tankData, "Fists")
check("Tanque: más vida y menos daño recibido (solo jugando Puños)", near(tank.MaxHealth, 1.25) and near(tank.DamageTaken, 0.9) and ClassLogic.mods(tankData, "Weapons").ClassId == "Soldier")
local champData = ClassLogic.empty()
ClassLogic.buy(champData, "Champion", 1e9)
local champ = ClassLogic.mods(champData, "Fists")
check("Campeón: combo un golpe antes, más daño de habilidades y vida", champ.ComboEvery == 1 and near(champ.SkillDamage, 1.2) and near(champ.MaxHealth, 1.15))
local archData = ClassLogic.empty()
ClassLogic.buy(archData, "Archmage", 1e9)
local arch = ClassLogic.mods(archData, "Magic")
check("Archimago: las habilidades recargan antes", near(arch.SkillCooldown, 0.85) and near(arch.SkillDamage, 1.15))

print("-- Efecto de los golpes")
local demoData = ClassLogic.empty()
ClassLogic.buy(demoData, "Demolisher", 1e9)
local demo = ClassLogic.mods(demoData, "Weapons")
local boom = ClassLogic.applyEffect({}, demo)
check("Demoledor: un arma sin explosión explota (radio 5, 30 %)", boom.Splash and near(boom.Splash.Radius, 5) and near(boom.Splash.Fraction, 0.3))
local bigger = ClassLogic.applyEffect({ Splash = { Radius = 12, Fraction = 0.6 } }, demo)
check("Demoledor con un arma que ya explota: más grande y más fuerte", near(bigger.Splash.Radius, 17) and near(bigger.Splash.Fraction, 0.9))
local pyroData = ClassLogic.empty()
ClassLogic.buy(pyroData, "Pyromancer", 1e9)
local pyro = ClassLogic.applyEffect(StyleLogic.effect("Magic", nil), ClassLogic.mods(pyroData, "Magic"))
check("Piromante: el orbe de Magia (7, 50 %) explota más grande", near(pyro.Splash.Radius, 10) and near(pyro.Splash.Fraction, 0.6))
local cryoData = ClassLogic.empty()
ClassLogic.buy(cryoData, "Cryomancer", 1e9)
local cryo = ClassLogic.mods(cryoData, "Magic")
local frozen = ClassLogic.applyEffect({}, cryo)
check("Criomante: los golpes frenan (×0.75 durante SlowSeconds)", frozen.Slow and near(frozen.Slow.Factor, 0.75) and frozen.Slow.Seconds == ClassConfig.SlowSeconds)
local stronger = ClassLogic.applyEffect({ Slow = { Factor = 0.6, Seconds = 1.5 } }, cryo)
check("Criomante con un arma que ya frena más: se queda la del arma", near(stronger.Slow.Factor, 0.6))
local plain = { Splash = { Radius = 3, Fraction = 0.2 } }
check("sin pasivas de efecto: el mismo efecto", ClassLogic.applyEffect(plain, soldier) == plain)

print("-- Con las pasivas del estilo")
check("crítico: el de Armas más el de la clase (Francotirador)", StyleLogic.critMultiplier("Weapons", 0.25, 0.1) == 2 and StyleLogic.critMultiplier("Weapons", 0.35, 0.1) == 1
	and StyleLogic.critMultiplier("Weapons", 0.1) == 2 and StyleLogic.critMultiplier("Weapons", 0.1, 0, 0.5) == 2.5)
check("crítico: otros estilos solo con la clase", StyleLogic.critMultiplier("Fists", 0.05) == 1 and StyleLogic.critMultiplier("Fists", 0.05, 0.1) == 2)
local state = { Count = 0, Last = 0 }
local first = StyleLogic.countHit("Fists", state, 1, 1)
local second = StyleLogic.countHit("Fists", state, 1.1, 1)
check("combo de Puños un golpe antes con el Campeón (cada 2)", first == nil and second ~= nil)
local fast = { Count = 0, Last = 0 }
local fired = 0
for i = 1, 6 do
	if StyleLogic.countHit("Fists", fast, i * 0.1, 99) then
		fired += 1
	end
end
check("el combo sale como mucho cada 2 golpes", fired == 3)
check("robo de vida: Puños con la clase (Berserker) se cura, con tope por golpe", near(StyleLogic.lifeSteal("Fists", 100, 1000, 0.05), 5) and near(StyleLogic.lifeSteal("Fists", 10000, 100, 0.05), 3)
	and StyleLogic.lifeSteal("Fists", 100, 1000) == 0)
check("robo de vida: la Magia suma la de la clase", near(StyleLogic.lifeSteal("Magic", 100, 10000, 0.05), 10))

print("-- Textos")
check("textos de las pasivas", ClassLogic.bonusText("Damage", 0.2) == "⚔️ +20 % de daño" and ClassLogic.bonusText("SplashRadius", 5) == "💥 Explosión de +5 studs"
	and ClassLogic.bonusText("Damage", 0.08, 0.11):find("→ 11 %", 1, true) ~= nil and ClassLogic.bonusText("Damage", 0.2, 0.2):find("→", 1, true) == nil)
local list = ClassLogic.bonusList("Commando", 1)
check("lista de pasivas en orden (daño, crítico, jefes)", #list == 3 and list[1].Key == "Damage" and list[2].Key == "CritPower" and list[3].Key == "BossDamage")

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
