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
	configOk = configOk and def ~= nil and type(def.DisplayName) == "string" and def.Passive ~= nil and def.Ability ~= nil and def.Ability2 ~= nil
		and type(def.Ability.Cooldown) == "number" and def.Ability.Cooldown > 0 and type(def.Ability2.Cooldown) == "number" and def.Ability2.Cooldown > 0
		and type(def.Pros) == "string" and type(def.Cons) == "string" and def.Ability.Name ~= def.Ability2.Name
end
check("tres estilos (Armas, Puños, Magia) con pasiva, ventaja, desventaja y dos habilidades con recarga", configOk)
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
check("efecto: Armas el del arma, Puños ninguno, Magia su explosión (7, 50 %)", StyleLogic.effect("Weapons", weaponEffect) == weaponEffect and next(StyleLogic.effect("Fists", weaponEffect)) == nil
	and StyleLogic.effect("Magic", weaponEffect).Splash.Radius == 7 and StyleLogic.effect("Magic", nil).Splash.Fraction == 0.5)

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
