-- Lógica pura de las clases de cada estilo (ClassConfig): cuáles tienes y a qué nivel, cuál
-- llevas activa en cada estilo, comprarlas, subirlas y elegirlas con 💎 diamantes (en el
-- código, Energy) y sus pasivas ya juntas (mods) para los servicios. Sin servicios: la usan
-- StyleService (valida y cobra), SaveService (guardar), PlayerDataService (atributos, vida y
-- velocidad), PetCombatService (golpes), EnemyService (jefes) y el cliente (solo mostrar).
--
-- Datos (profile.PetData.Classes):
--   Owned: { [clase]: nivel }   las que tiene (1..ClassConfig.Levels.Max); la primera de
--                               cada estilo (la gratis) siempre, a nivel 1 como mínimo
--   Active: { [estilo]: clase } la activa de cada estilo (una suya que tenga)
-- Lo que ya no existe se conserva en Archived tal cual.

local ClassConfig = require(script.Parent.Config.ClassConfig)

local ClassLogic = {}

export type ClassData = {
	Owned: { [string]: number },
	Active: { [string]: string },
	Archived: { [string]: any }?,
}

-- Pasivas de la clase activa ya convertidas en multiplicadores y sumas (neutras sin clase).
export type Mods = {
	ClassId: string?,
	Level: number,
	Damage: number, -- × daño de tus golpes
	Cooldown: number, -- × tiempo entre golpes
	Range: number, -- × alcance
	CritChance: number, -- + probabilidad de crítico
	CritPower: number, -- + al multiplicador del crítico
	LifeSteal: number, -- + parte del daño que te cura
	MaxHealth: number, -- × vida máxima
	DamageTaken: number, -- × daño que recibes
	WalkSpeed: number, -- × velocidad al caminar
	SkillDamage: number, -- × daño de las habilidades
	SkillCooldown: number, -- × recarga de las habilidades
	DashCooldown: number, -- × recarga del dash
	SplashRadius: number, -- + studs de explosión
	SplashFraction: number, -- + parte del daño en la explosión
	Slow: number, -- frenan al enemigo esta parte (0 = no)
	BossDamage: number, -- × daño a jefes
	ComboEvery: number, -- golpes de menos para el combo
}

local MAX_ID = 40

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function maxLevel(): number
	return ClassConfig.Levels.Max
end

function ClassLogic.definition(classId: any): { [string]: any }?
	return if type(classId) == "string" then ClassConfig.Classes[classId] else nil
end

-- Estilo al que pertenece una clase (o nil)
function ClassLogic.styleOf(classId: any): string?
	local def = ClassLogic.definition(classId)
	return def and def.Style
end

-- Clases de un estilo en su orden (la primera es la gratis)
function ClassLogic.ordered(styleId: string): { string }
	return ClassConfig.Styles[styleId] or {}
end

-- La gratis de un estilo
function ClassLogic.starter(styleId: string): string?
	return ClassLogic.ordered(styleId)[1]
end

function ClassLogic.empty(): ClassData
	local data = { Owned = {}, Active = {} }
	for styleId, ids in ClassConfig.Styles do
		local first = ids[1]
		if first then
			data.Owned[first] = 1
			data.Active[styleId] = first
		end
	end
	return data
end

-- Datos guardados -> válidos. Lo desconocido se archiva; lo corrupto toma el valor inicial.
function ClassLogic.sanitize(raw: any): ClassData
	local data = ClassLogic.empty()
	if type(raw) ~= "table" then
		return data
	end
	local archived = {}
	if type(raw.Owned) == "table" then
		for classId, level in raw.Owned do
			if ClassLogic.definition(classId) then
				if finite(level) then
					data.Owned[classId] = math.clamp(math.floor(level), 1, maxLevel())
				end
			elseif type(classId) == "string" and #classId <= MAX_ID and finite(level) then
				archived[classId] = level
			end
		end
	end
	if type(raw.Archived) == "table" then
		for classId, value in raw.Archived do
			if type(classId) == "string" and #classId <= MAX_ID and not ClassLogic.definition(classId) then
				archived[classId] = value
			end
		end
	end
	if next(archived) ~= nil then
		data.Archived = archived
	end
	if type(raw.Active) == "table" then
		for styleId in ClassConfig.Styles do
			local classId = raw.Active[styleId]
			if data.Owned[classId] and ClassLogic.styleOf(classId) == styleId then
				data.Active[styleId] = classId
			end
		end
	end
	return data
end

function ClassLogic.serialize(data: ClassData): { [string]: any }
	local out: { [string]: any } = { Owned = table.clone(data.Owned), Active = table.clone(data.Active) }
	if data.Archived and next(data.Archived) ~= nil then
		out.Archived = table.clone(data.Archived)
	end
	return out
end

function ClassLogic.level(data: ClassData?, classId: string): number
	return (data and data.Owned[classId]) or 0
end

-- La activa del estilo (una suya que tenga; si no, la gratis)
function ClassLogic.active(data: ClassData?, styleId: string): string?
	local classId = data and data.Active[styleId]
	if classId and data and data.Owned[classId] and ClassLogic.styleOf(classId) == styleId then
		return classId
	end
	return ClassLogic.starter(styleId)
end

-- Valor de una pasiva de la clase a ese nivel (0 si no la tiene)
function ClassLogic.bonus(classId: string, key: string, level: number?): number
	local def = ClassLogic.definition(classId)
	local spec = def and def.Bonuses and def.Bonuses[key]
	if finite(spec) then
		return spec
	end
	if type(spec) ~= "table" or not finite(spec[1]) then
		return 0
	end
	local low, high = spec[1], if finite(spec[2]) then spec[2] else spec[1]
	local lvl = if finite(level) then math.clamp(math.floor(level :: number), 1, maxLevel()) else 1
	local t = if maxLevel() > 1 then (lvl - 1) / (maxLevel() - 1) else 1
	return low + (high - low) * t
end

-- Pasivas de una clase en el orden del panel: { { Key, Value } }
function ClassLogic.bonusList(classId: string, level: number?): { { Key: string, Value: number } }
	local def = ClassLogic.definition(classId)
	local list = {}
	for key in (def and def.Bonuses) or {} do
		table.insert(list, { Key = key, Value = ClassLogic.bonus(classId, key, level) })
	end
	table.sort(list, function(a, b)
		local ao = ClassConfig.Bonuses[a.Key] and ClassConfig.Bonuses[a.Key].Order or 99
		local bo = ClassConfig.Bonuses[b.Key] and ClassConfig.Bonuses[b.Key].Order or 99
		return ao < bo
	end)
	return list
end

-- Valor de una pasiva como se enseña ("20 %", "5", "1.5")
function ClassLogic.formatValue(key: string, value: number): string
	local spec = ClassConfig.Bonuses[key]
	if spec and spec.Percent then
		return ("%d %%"):format(math.floor(value * 100 + 0.5))
	elseif math.abs(value - math.floor(value + 0.5)) < 0.05 then
		return tostring(math.floor(value + 0.5))
	end
	return ("%.1f"):format(value)
end

-- Texto de una pasiva para el panel ("⚔️ +20 % de daño"); `nextValue` añade lo que tendrá al
-- siguiente nivel ("→ 23 %") en verde (RichText).
function ClassLogic.bonusText(key: string, value: number, nextValue: number?): string
	local spec = ClassConfig.Bonuses[key]
	if not spec then
		return key
	end
	local text = ("%s " .. spec.Text):format(spec.Icon, ClassLogic.formatValue(key, value))
	if nextValue and math.abs(nextValue - value) > 1e-6 then
		text ..= (" <font color=\"#96F096\">→ %s</font>"):format(ClassLogic.formatValue(key, nextValue))
	end
	return text
end

-- Pasivas juntas -------------------------------------------------------------------------

local NEUTRAL: Mods = {
	ClassId = nil,
	Level = 0,
	Damage = 1,
	Cooldown = 1,
	Range = 1,
	CritChance = 0,
	CritPower = 0,
	LifeSteal = 0,
	MaxHealth = 1,
	DamageTaken = 1,
	WalkSpeed = 1,
	SkillDamage = 1,
	SkillCooldown = 1,
	DashCooldown = 1,
	SplashRadius = 0,
	SplashFraction = 0,
	Slow = 0,
	BossDamage = 1,
	ComboEvery = 0,
}

function ClassLogic.neutral(): Mods
	return table.clone(NEUTRAL)
end

-- Las pasivas de la clase activa del estilo `styleId` con su nivel.
function ClassLogic.mods(data: ClassData?, styleId: any): Mods
	local mods = table.clone(NEUTRAL)
	if type(styleId) ~= "string" or not ClassConfig.Styles[styleId] then
		return mods
	end
	local classId = ClassLogic.active(data, styleId)
	if not classId then
		return mods
	end
	local level = math.max(1, ClassLogic.level(data, classId))
	local function b(key: string): number
		return ClassLogic.bonus(classId, key, level)
	end
	mods.ClassId = classId
	mods.Level = level
	mods.Damage = 1 + math.max(0, b("Damage"))
	mods.Cooldown = 1 / (1 + math.clamp(b("FireRate"), 0, 4))
	mods.Range = 1 + math.max(0, b("Range"))
	mods.CritChance = math.clamp(b("CritChance"), 0, 1)
	mods.CritPower = math.max(0, b("CritPower"))
	mods.LifeSteal = math.clamp(b("LifeSteal"), 0, 1)
	mods.MaxHealth = 1 + math.max(0, b("Health"))
	mods.DamageTaken = 1 - math.clamp(b("Defense"), 0, 0.8)
	mods.WalkSpeed = 1 + math.max(0, b("Speed"))
	mods.SkillDamage = 1 + math.max(0, b("SkillDamage"))
	mods.SkillCooldown = 1 - math.clamp(b("SkillHaste"), 0, 0.8)
	mods.DashCooldown = 1 - math.clamp(b("DashHaste"), 0, 0.8)
	mods.SplashRadius = math.max(0, b("SplashRadius"))
	mods.SplashFraction = math.clamp(b("SplashFraction"), 0, 1)
	mods.Slow = math.clamp(b("Slow"), 0, 0.9)
	mods.BossDamage = 1 + math.max(0, b("BossDamage"))
	mods.ComboEvery = math.max(0, math.floor(b("ComboEvery")))
	return mods
end

-- Efecto de cada golpe con la clase: explosión (más grande o nueva) y frenar.
function ClassLogic.applyEffect(effect: { [string]: any }, mods: Mods): { [string]: any }
	if mods.SplashRadius <= 0 and mods.SplashFraction <= 0 and mods.Slow <= 0 then
		return effect
	end
	local result = table.clone(effect)
	local splash = effect.Splash
	local radius = (if splash and finite(splash.Radius) then splash.Radius else 0) + mods.SplashRadius
	local fraction = (if splash and finite(splash.Fraction) then splash.Fraction else 0) + mods.SplashFraction
	if radius > 0 and fraction > 0 then
		result.Splash = { Radius = math.min(radius, 30), Fraction = math.min(fraction, 1) }
	end
	if mods.Slow > 0 then
		local slow = effect.Slow
		local factor = 1 - mods.Slow
		if not (slow and finite(slow.Factor) and slow.Factor <= factor) then
			result.Slow = { Factor = factor, Seconds = math.max(ClassConfig.SlowSeconds, if slow and finite(slow.Seconds) then slow.Seconds else 0) }
		end
	end
	return result
end

-- 💎 para subir del nivel `level` al siguiente (nil si ya está al máximo)
function ClassLogic.upgradeCost(classId: string, level: number): number?
	local def = ClassLogic.definition(classId)
	if not def or not finite(level) or level < 1 or level >= maxLevel() then
		return nil
	end
	local scale = if finite(def.UpgradeScale) then def.UpgradeScale else 1
	return math.floor(ClassConfig.Levels.UpgradeBase * scale * ClassConfig.Levels.UpgradeGrowth ^ (level - 1))
end

-- Acciones (devuelven el código y los 💎 cobrados; quien llama los resta) ---------------------

-- Comprar: "Success" (queda a nivel 1 y activa en su estilo), "InvalidRequest",
-- "AlreadyOwned" o "InsufficientEnergy" (faltan 💎), y el precio.
function ClassLogic.buy(data: ClassData, classId: any, diamonds: any): (string, number)
	local def = ClassLogic.definition(classId)
	if not def then
		return "InvalidRequest", 0
	end
	if data.Owned[classId] then
		return "AlreadyOwned", 0
	end
	local price = def.Price or 0
	if not (finite(diamonds) and diamonds >= price) then
		return "InsufficientEnergy", price
	end
	data.Owned[classId] = 1
	data.Active[def.Style] = classId
	return "Success", price
end

-- Subir un nivel: "Success", "InvalidRequest", "NotOwned", "MaxLevel" o "InsufficientEnergy".
function ClassLogic.upgrade(data: ClassData, classId: any, diamonds: any): (string, number)
	if not ClassLogic.definition(classId) then
		return "InvalidRequest", 0
	end
	local level = data.Owned[classId]
	if not level then
		return "NotOwned", 0
	end
	local cost = ClassLogic.upgradeCost(classId, level)
	if not cost then
		return "MaxLevel", 0
	end
	if not (finite(diamonds) and diamonds >= cost) then
		return "InsufficientEnergy", cost
	end
	data.Owned[classId] = level + 1
	return "Success", cost
end

-- Elegirla como la activa de su estilo: "Success", "InvalidRequest" o "NotOwned".
function ClassLogic.select(data: ClassData, classId: any): string
	local def = ClassLogic.definition(classId)
	if not def then
		return "InvalidRequest"
	end
	if not data.Owned[classId] then
		return "NotOwned"
	end
	data.Active[def.Style] = classId
	return "Success"
end

-- Para el cliente (atributos) ------------------------------------------------------------------

-- "Soldier:2,Sniper:1,Brawler:1"
function ClassLogic.ownedText(data: ClassData): string
	local parts = {}
	for _, styleId in { "Weapons", "Fists", "Magic" } do
		for _, classId in ClassLogic.ordered(styleId) do
			local level = data.Owned[classId]
			if level then
				table.insert(parts, classId .. ":" .. level)
			end
		end
	end
	return table.concat(parts, ",")
end

-- "Weapons=Sniper;Fists=Brawler;Magic=Apprentice"
function ClassLogic.activeText(data: ClassData): string
	local parts = {}
	for _, styleId in { "Weapons", "Fists", "Magic" } do
		table.insert(parts, ("%s=%s"):format(styleId, ClassLogic.active(data, styleId) or ""))
	end
	return table.concat(parts, ";")
end

-- Los dos textos de los atributos -> datos (para el cliente; los mismos números que el servidor)
function ClassLogic.parse(ownedText: any, activeText: any): ClassData
	local raw = { Owned = {}, Active = {} }
	if type(ownedText) == "string" then
		for classId, level in ownedText:gmatch("([%w_]+):(%d+)") do
			raw.Owned[classId] = tonumber(level)
		end
	end
	if type(activeText) == "string" then
		for styleId, classId in activeText:gmatch("([%w_]+)=([%w_]*)") do
			raw.Active[styleId] = classId
		end
	end
	return ClassLogic.sanitize(raw)
end

return ClassLogic
