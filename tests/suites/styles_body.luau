-- Estilos de pelea (StyleLogic, pura): elegir, cómo cambian el disparo del arma, las
-- pasivas y el daño de las habilidades.

local failures = 0
local function check(name, ok)
	if not ok then
		failures += 1
	end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local function near(a, b)
	return math.abs(a - b) < 1e-9
end

print("-- Configuración")
local configOk = #StyleConfig.Order == 3
for _, id in StyleConfig.Order do
	local def = StyleConfig.Styles[id]
	local count, free, priced = 0, 0, 0
	for _, skill in (def and def.Skills) or {} do
		if skill.World == 2 then
			continue -- las del Mundo 2, aparte
		end
		count += 1
		configOk = configOk and type(skill.Cooldown) == "number" and skill.Cooldown > 0 and type(skill.Name) == "string" and type(skill.Icon) == "string" and type(skill.Price) == "number"
		if skill.Price == 0 then
			free += 1
		else
			priced += 1
		end
	end
	configOk = configOk and def ~= nil and type(def.DisplayName) == "string" and def.Passive ~= nil and count == 4 and free == 2 and priced == 2
		and def.Skills[def.StartSkills[1]] ~= nil and def.Skills[def.StartSkills[2]] ~= nil and def.StartSkills[1] ~= def.StartSkills[2]
		and def.Skills[def.StartSkills[1]].Price == 0 and def.Skills[def.StartSkills[2]].Price == 0
		and type(def.Pros) == "string" and type(def.Cons) == "string"
end
check("tres estilos (Armas, Puños, Magia) con pasiva, ventaja, desventaja y 4 habilidades: 2 de inicio y 2 que se compran", configOk)
local handlersOk = true
for _, id in StyleConfig.Order do
	for skillId in StyleConfig.Styles[id].Skills do
		if SkillLogic.styleOf(skillId) ~= id then
			handlersOk = false
		end
	end
end
check("cada habilidad es de un solo estilo (ids únicos)", handlersOk)
-- Mundo 2: 4 más por estilo, que se compran (piden el Mundo 2) y usan el efecto de una del
-- Mundo 1 de su estilo (Base), más fuertes
local world2Ok = true
for _, id in StyleConfig.Order do
	local def = StyleConfig.Styles[id]
	local list = SkillLogic.ordered(id, 2)
	world2Ok = world2Ok and #list == 4 and #SkillLogic.ordered(id, 1) == 4 and #SkillLogic.ordered(id) == 8
	for _, skillId in list do
		local skill = def.Skills[skillId]
		local base = skill.Base and def.Skills[skill.Base]
		world2Ok = world2Ok and SkillLogic.world(skillId) == 2 and skill.Requires == "World2" and (skill.Price or 0) > 0
			and base ~= nil and (base.World or 1) == 1 and skill.Color ~= nil
			and ((skill.DamageRatio or 0) >= (base.DamageRatio or 0)) and type(skill.Name) == "string" and type(skill.Icon) == "string"
	end
end
check("Mundo 2: 4 habilidades más por estilo, con precio, el Mundo 2 de requisito y el efecto (más fuerte) de una del Mundo 1", world2Ok)
local w2 = SkillLogic.empty()
local code, price = SkillLogic.buy(w2, "Bombardment", 1e9, {})
check("sin haber llegado al Mundo 2 no se compran (ZoneLocked) y no se cobra", code == "ZoneLocked" and w2.Owned.Bombardment == nil and price == StyleConfig.Styles.Weapons.Skills.Bombardment.Price)
code = SkillLogic.buy(w2, "Bombardment", 1e9, { "World2" })
check("con el Mundo 2, sí (y se puede poner en la Z)", code == "Success" and w2.Owned.Bombardment == 1 and SkillLogic.equip(w2, "Bombardment", 1) == "Success" and SkillLogic.equipped(w2, "Weapons", 1) == "Bombardment")
check("las de siempre se siguen comprando sin requisito", SkillLogic.buy(w2, "Pierce", 1e9) == "Success")
local soundsOk = true
for name, spec in StyleConfig.Sounds do
	local id = spec.Id
	if not (type(id) == "string" and (string.match(id, "^rbxassetid://%d+$") or string.match(id, "^rbxasset://sounds/"))) then
		soundsOk = false
		print("   sonido mal: " .. name)
	end
end
check("sonidos con Id de Roblox", soundsOk)

print("-- Elegir")
check("sin estilo o uno raro: Armas", StyleLogic.sanitize(nil) == "Weapons" and StyleLogic.sanitize("Nope") == "Weapons" and StyleLogic.sanitize(5) == "Weapons")
check("los que existen se quedan", StyleLogic.sanitize("Fists") == "Fists" and StyleLogic.sanitize("Magic") == "Magic")
check("cambiar: la primera vez sí; muy seguido, no", StyleLogic.canSwitch(nil, 10) and not StyleLogic.canSwitch(10, 10 + StyleConfig.SwitchCooldown - 0.1) and StyleLogic.canSwitch(10, 10 + StyleConfig.SwitchCooldown))

print("-- El disparo según el estilo")
local laser = { WeaponId = "Laser", Shot = 8, Cooldown = 0.4, Range = 60, Dps = 20 }
local same = StyleLogic.applyStats(laser, "Weapons", 0.4)
check("Armas: el arma tal cual", same.Shot == 8 and same.Cooldown == 0.4 and same.Range == 60 and same ~= laser)
local fists = StyleLogic.applyStats(laser, "Fists", 0.4)
check("Puños: golpes de 10.5 cada 0.35 s (×1.5 de DPS), alcance 9", near(fists.Shot, 10.5) and near(fists.Cooldown, 0.35) and fists.Range == 9)
local fastFists = StyleLogic.applyStats({ Shot = 8, Cooldown = 0.36, Range = 60 }, "Fists", 0.4)
check("Puños con cadencia: también más rápidos (×0.9), mismo golpe", near(fastFists.Cooldown, 0.315) and near(fastFists.Shot, 10.5))
local magic = StyleLogic.applyStats(laser, "Magic", 0.4)
check("Magia: orbes que cargan, de 16 cada 0.8 s, alcance 45", near(magic.Shot, 16) and near(magic.Cooldown, 0.8) and magic.Range == 45)
check("DPS que se muestra: ×1.5 con Puños, igual con Armas y Magia", StyleLogic.dps(20, "Fists") == 30 and StyleLogic.dps(20, "Weapons") == 20 and StyleLogic.dps(20, "Magic") == 20 and StyleLogic.dps(0 / 0, "Fists") == 0)
local weaponEffect = { Splash = { Radius = 6, Fraction = 0.5 } }
local slowGloves = { Slow = { Factor = 0.6, Seconds = 1.5 } }
local bigStaff = { Splash = { Radius = 11, Fraction = 0.7 }, Chain = { Count = 1, Range = 14, Fraction = 0.6 } }
check("efecto: Armas el del arma; Puños el de sus guantes (sin guantes especiales, nada); Magia su explosión (7, 50 %)", StyleLogic.effect("Weapons", weaponEffect) == weaponEffect and next(StyleLogic.effect("Fists", nil)) == nil
	and StyleLogic.effect("Fists", slowGloves).Slow.Factor == 0.6 and StyleLogic.effect("Fists", slowGloves) ~= slowGloves
	and StyleLogic.effect("Magic", weaponEffect).Splash.Radius == 7 and StyleLogic.effect("Magic", nil).Splash.Fraction == 0.5)
check("Magia con un bastón especial: su área si es más grande y su rayo que salta", StyleLogic.effect("Magic", bigStaff).Splash.Radius == 11 and StyleLogic.effect("Magic", bigStaff).Chain.Count == 1
	and StyleLogic.effect("Magic", slowGloves).Slow ~= nil and StyleLogic.effect("Magic", slowGloves).Splash.Radius == 7)

print("-- Pasivas")
check("Puntería: críticos ×2 con un 20 %", StyleLogic.critMultiplier("Weapons", 0.1) == 2 and StyleLogic.critMultiplier("Weapons", 0.5) == 1 and StyleLogic.critMultiplier("Fists", 0) == 1 and StyleLogic.critMultiplier("Weapons", 0 / 0) == 1)
check("Piel dura: Puños reciben un 30 % menos", near(StyleLogic.damageTaken("Fists", 100), 70) and StyleLogic.damageTaken("Fists", 0 / 0) == 0)
check("Armas reciben un 15 % más y Magia lo normal", near(StyleLogic.damageTaken("Weapons", 100), 115) and StyleLogic.damageTaken("Magic", 100) == 100 and StyleLogic.damageTaken("Nope", 100) == 100)
check("velocidad: Puños ×1.2, Magia ×0.9, Armas ×1", near(StyleLogic.walkSpeed("Fists"), 1.2) and near(StyleLogic.walkSpeed("Magic"), 0.9) and StyleLogic.walkSpeed("Weapons") == 1 and StyleLogic.walkSpeed(nil) == 1)
-- Ventajas y desventajas: Puños pegan más pero de cerca; Armas de lejos; Magia en área
local fistsStats = StyleLogic.applyStats(laser, "Fists", 0.4)
local magicStats = StyleLogic.applyStats(laser, "Magic", 0.4)
check("Puños: más DPS y menos alcance que Armas; Magia: área y alcance medio", StyleLogic.dps(20, "Fists") > StyleLogic.dps(20, "Weapons") and fistsStats.Range < magicStats.Range and magicStats.Range < laser.Range
	and StyleLogic.effect("Magic", nil).Splash ~= nil)
check("Robo de vida: 5 % del daño, como mucho 3 % de la vida por golpe", near(StyleLogic.lifeSteal("Magic", 20, 100), 1) and near(StyleLogic.lifeSteal("Magic", 1000, 100), 3)
	and StyleLogic.lifeSteal("Weapons", 100, 100) == 0 and StyleLogic.lifeSteal("Magic", -5, 100) == 0)

print("-- Habilidades")
check("Terremoto: 2.5 × el DPS de Puños a cada uno", StyleLogic.abilityDamage("Fists", 30) == 75)
check("Meteoros: 1.5 × el DPS de Magia por meteoro", StyleLogic.abilityDamage("Magic", 20) == 30)
check("Ráfaga no hace daño por sí sola", StyleLogic.abilityDamage("Weapons", 20) == 0)
check("segunda habilidad (X): Granada 3×, Embestida 2× y Nova 1.2× el DPS", StyleLogic.abilityDamage("Weapons", 20, 2) == 60 and StyleLogic.abilityDamage("Fists", 30, 2) == 60 and near(StyleLogic.abilityDamage("Magic", 20, 2), 24))
check("habilidad por número: 1 = Z, 2 = X (y la 1 si es raro)", StyleLogic.ability("Fists", 1).Name == "Terremoto" and StyleLogic.ability("Fists", 2).Name == "Embestida" and StyleLogic.ability("Magic", 7).Name == "Meteoros" and StyleLogic.ability("Nope", 1) == nil)
check("Puños: +50 % de vida y dash; los demás, vida normal", StyleLogic.maxHealth("Fists") == 1.5 and StyleLogic.maxHealth("Magic") == 1 and StyleLogic.maxHealth(nil) == 1 and StyleConfig.Styles.Fists.Dash.Cooldown > 0)

print("-- Combos de golpes")
local counter = {}
local seq = {}
for index = 1, 6 do
	table.insert(seq, StyleLogic.countHit("Fists", counter, index * 0.4) ~= nil)
end
check("Puños: cada 3 golpes seguidos, un gancho", not seq[1] and not seq[2] and seq[3] and not seq[4] and not seq[5] and seq[6])
local magicCounter = {}
for index = 1, 3 do
	StyleLogic.countHit("Magic", magicCounter, index)
end
check("parar más de lo que dura el combo lo reinicia", StyleLogic.countHit("Magic", magicCounter, 100) == nil and magicCounter.Count == 1)
local mixed = {}
StyleLogic.countHit("Fists", mixed, 1)
StyleLogic.countHit("Fists", mixed, 1.2)
check("cambiar de estilo también lo reinicia", StyleLogic.countHit("Weapons", mixed, 1.4) == nil and mixed.Count == 1)
check("el gran orbe hace ×2.5 y agranda el área; el tiro cargado, cada 5", StyleConfig.Styles.Magic.HitCombo.Multiplier == 2.5 and StyleConfig.Styles.Magic.HitCombo.SplashScale > 1 and StyleConfig.Styles.Weapons.HitCombo.Every == 5)

print("-- Habilidades compradas y sus niveles (SkillLogic)")
local skills = SkillLogic.empty()
check("al empezar: las dos iniciales de cada estilo, a nivel 1 y puestas en Z y X", skills.Owned.Burst == 1 and skills.Owned.Quake == 1 and skills.Owned.Nova == 1 and skills.Owned.Pierce == nil
	and SkillLogic.equipped(skills, "Weapons", 1) == "Burst" and SkillLogic.equipped(skills, "Magic", 2) == "Nova" and skills.Picked == false)
local code, cost = SkillLogic.buy(skills, "ChainLightning", 149)
check("comprar sin 💎 suficientes: InsufficientEnergy con su precio", code == "InsufficientEnergy" and cost == 150 and skills.Owned.ChainLightning == nil)
code, cost = SkillLogic.buy(skills, "ChainLightning", 150)
check("con 150 💎: comprada a nivel 1", code == "Success" and cost == 150 and skills.Owned.ChainLightning == 1)
check("no se compra dos veces ni una que no existe", (SkillLogic.buy(skills, "ChainLightning", 1e9)) == "AlreadyOwned" and (SkillLogic.buy(skills, "Nope", 1e9)) == "InvalidRequest")
check("ponerla en la Z de Magia: Meteoros se queda fuera y Nova en la X", SkillLogic.equip(skills, "ChainLightning", 1) == "Success" and SkillLogic.equipped(skills, "Magic", 1) == "ChainLightning" and SkillLogic.equipped(skills, "Magic", 2) == "Nova")
check("ponerla en la X: se intercambian", SkillLogic.equip(skills, "ChainLightning", 2) == "Success" and SkillLogic.equipped(skills, "Magic", 1) == "Nova" and SkillLogic.equipped(skills, "Magic", 2) == "ChainLightning")
check("no se pone una que no tiene, ni en un hueco raro", SkillLogic.equip(skills, "BlackHole", 1) == "NotOwned" and SkillLogic.equip(skills, "Nova", 3) == "InvalidRequest")
local up = SkillLogic.upgradeCost("Quake", 1)
code, cost = SkillLogic.upgrade(skills, "Quake", up)
check(("subir el Terremoto: nivel 2 por %d 💎"):format(up), code == "Success" and cost == up and skills.Owned.Quake == 2 and SkillLogic.upgradeCost("Quake", 2) > up)
check("las compradas cuestan más de subir (UpgradeScale)", SkillLogic.upgradeCost("BlackHole", 1) > SkillLogic.upgradeCost("Quake", 1))
skills.Owned.Quake = StyleConfig.SkillLevels.Max
check("al máximo: MaxLevel", (SkillLogic.upgrade(skills, "Quake", 1e12)) == "MaxLevel" and SkillLogic.upgradeCost("Quake", StyleConfig.SkillLevels.Max) == nil)
check("nivel: +15 % de daño por nivel, menos recarga (con tope) y más duración", near(SkillLogic.power(1), 1) and near(SkillLogic.power(3), 1.3)
	and SkillLogic.cooldown({ Cooldown = 10 }, 1) == 10 and near(SkillLogic.cooldown({ Cooldown = 10 }, 3), 9.4) and SkillLogic.cooldown({ Cooldown = 10 }, 999) >= 10 * StyleConfig.SkillLevels.MinCooldown
	and SkillLogic.duration({ Duration = 4 }, 2) > 4)
check("el daño de una habilidad sube con su nivel", near(StyleLogic.abilityDamage("Fists", 30, 1, skills, 3), 75 * 1.3))
check("con los datos del jugador, la habilidad puesta", StyleLogic.ability("Magic", 2, skills).Name == "Cadena de rayos")
local back = SkillLogic.sanitize(SkillLogic.serialize(skills))
check("guardar y cargar: niveles y las puestas", back.Owned.ChainLightning == 1 and back.Owned.Quake == StyleConfig.SkillLevels.Max and SkillLogic.equipped(back, "Magic", 2) == "ChainLightning")
local messy = SkillLogic.sanitize({ Owned = { Quake = 99, Pierce = 0, OldSkill = 3 }, Equipped = { Weapons = { "Quake", "Pierce" }, Fists = { "Dash", "Dash" } }, Picked = true })
check("datos sucios: niveles al tope o a 1, una de otro estilo no se pone, huecos repetidos se rellenan y lo viejo se archiva",
	messy.Owned.Quake == StyleConfig.SkillLevels.Max and messy.Owned.Pierce == 1 and SkillLogic.equipped(messy, "Weapons", 1) == "Burst" and SkillLogic.equipped(messy, "Weapons", 2) == "Pierce"
		and SkillLogic.equipped(messy, "Fists", 1) == "Dash" and SkillLogic.equipped(messy, "Fists", 2) == "Quake" and messy.Archived.OldSkill == 3 and messy.Picked == true)
check("atributos para el cliente: ida y vuelta", SkillLogic.parseOwned(SkillLogic.ownedText(skills)).ChainLightning == 1 and SkillLogic.parseSlots(SkillLogic.slotsText(skills)).Magic[2] == "ChainLightning")
check("embestida: golpea a los de su franja (borde incluido) y no a los de fuera", StyleLogic.inStrip(0, 0, 20, 0, 4, 10, 3, 1) and StyleLogic.inStrip(0, 0, 20, 0, 4, 10, 4.9, 1) and not StyleLogic.inStrip(0, 0, 20, 0, 4, 10, 6, 1)
	and StyleLogic.inStrip(0, 0, 20, 0, 4, 21, 0, 1.5) and not StyleLogic.inStrip(0, 0, 20, 0, 4, 26, 0, 1) and StyleLogic.inStrip(0, 0, 0, 0, 4, 2, 0, 0) and not StyleLogic.inStrip(0, 0, 0 / 0, 0, 4, 1, 1))
local offsets = StyleLogic.meteorOffsets(6, 9)
local inside = #offsets == 6 and offsets[1].X == 0 and offsets[1].Y == 0
for _, offset in offsets do
	inside = inside and math.sqrt(offset.X ^ 2 + offset.Y ^ 2) <= 9 + 1e-9
end
check("meteoros: 6 puntos, el primero en el objetivo y todos a 9 o menos", inside)
check("meteoros: cantidades raras no rompen", #StyleLogic.meteorOffsets(0 / 0, 9) == 0 and #StyleLogic.meteorOffsets(99, 9) == 20)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
