Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end }
Vector2 = { new = function(x, y) return { X = x, Y = y } end }
local PetConfig = (function()
-- Mascotas y rarezas. Para añadir una mascota: añadir una entrada en Pets (con un ID
-- estable que no se renombre nunca: es lo que se guarda) y referenciarla desde un huevo
-- en EggConfig. El servidor valida esta tabla al arrancar.
--
-- Multiplicador: cada mascota equipada aporta (Multiplier - 1) de bonificación y las
-- bonificaciones se suman. Ej.: 1.10 + 1.25 equipadas = x1.35 de producción.
--
-- MODELOS: Look.Style elige un prototipo hecho con piezas nativas (PetModelBuilder).
-- Los marcados con Prototype = true deben sustituirse por arte definitivo: basta con
-- colocar un Model llamado igual que el ID en ReplicatedStorage.PetModels (con
-- PrimaryPart); PetModelBuilder lo usará automáticamente en lugar del prototipo.

local PetConfig = {
	MaxEquipped = 3,
	MaxInventory = 60,

	-- Multiplier: valor por defecto de las mascotas de esa rareza si no indican uno propio.
	Rarities = {
		Common = { DisplayName = "Común", Order = 1, Color = Color3.fromRGB(196, 204, 186), Multiplier = 1.1 },
		Uncommon = { DisplayName = "Poco común", Order = 2, Color = Color3.fromRGB(120, 214, 120), Multiplier = 1.25 },
		Rare = { DisplayName = "Rara", Order = 3, Color = Color3.fromRGB(96, 180, 255), Multiplier = 1.5 },
		Epic = { DisplayName = "Épica", Order = 4, Color = Color3.fromRGB(196, 120, 255), Multiplier = 2 },
		Legendary = { DisplayName = "Legendaria", Order = 5, Color = Color3.fromRGB(255, 200, 80), Multiplier = 3 },
	},

	Pets = {
		-- Huevo del Bosque ----------------------------------------------------------
		Sproutling = {
			DisplayName = "Brotecillo",
			Rarity = "Common",
			Multiplier = 1.1,
			Look = { Style = "Sprout", Prototype = true, Primary = Color3.fromRGB(156, 222, 112), Secondary = Color3.fromRGB(64, 150, 70) },
		},
		MushroomHopper = {
			DisplayName = "Seta Saltarina",
			Rarity = "Common",
			Multiplier = 1.1,
			Look = { Style = "Mushroom", Prototype = true, Primary = Color3.fromRGB(214, 70, 58), Secondary = Color3.fromRGB(244, 234, 214) },
		},
		EmberFox = {
			DisplayName = "Zorrito de Brasa",
			Rarity = "Uncommon",
			Multiplier = 1.25,
			Look = { Style = "Ember", Prototype = true, Primary = Color3.fromRGB(226, 96, 44), Secondary = Color3.fromRGB(255, 196, 70) },
		},

		-- Huevo de Musgo -----------------------------------------------------------
		MossFox = {
			DisplayName = "Zorro de Musgo",
			Rarity = "Uncommon",
			Multiplier = 1.25,
			Look = { Style = "Fox", Prototype = true, Primary = Color3.fromRGB(206, 124, 62), Secondary = Color3.fromRGB(112, 170, 82) },
		},

		-- Huevos de Musgo y Ancestral -------------------------------------------------
		MoonOwl = {
			DisplayName = "Búho Lunar",
			Rarity = "Rare",
			Multiplier = 1.5,
			Look = { Style = "Owl", Prototype = true, Primary = Color3.fromRGB(150, 160, 214), Secondary = Color3.fromRGB(110, 118, 176) },
		},

		-- Huevo Ancestral ------------------------------------------------------------
		EmeraldFawn = {
			DisplayName = "Cervatillo Esmeralda",
			Rarity = "Epic",
			Multiplier = 2,
			Look = { Style = "Fawn", Prototype = true, Primary = Color3.fromRGB(150, 112, 74), Secondary = Color3.fromRGB(70, 220, 130) },
		},
	},
}

return PetConfig
end)()
local EggConfig = (function()
-- Huevos. Para añadir uno: nueva entrada en Eggs con su coste, probabilidades,
-- requisito, aspecto y posición del santuario. El servidor valida al arrancar que las
-- probabilidades de cada huevo activo sumen exactamente 100 y que todas sus mascotas
-- existan en PetConfig. Un huevo con Enabled = false no se construye ni se vende
-- (para preparar huevos cuyas recompensas aún no existen).
--
-- Precios, calibrados con las mejoras (coste del nivel N = 10 · 1.5^N; producción ≈ 1 + N):
-- - Bosque (100): ~ el precio de la mejora 5-6. Una Común (+10 %) a producción 6/s
--   se amortiza en ~3 min.
-- - Musgo (750, requiere nivel 6): ~ las mejoras 9-10. Valor medio +31 % por huevo.
-- - Ancestral (8 000, requiere nivel 16): ~ la mejora 16-17. Valor medio +65 % por huevo.

local EggConfig = {
	-- Distancia máxima (studs) entre el jugador y el santuario para poder comprar.
	MaxPurchaseDistance = 18,
	-- Segundos mínimos entre aperturas (protección del servidor contra spam).
	PurchaseCooldown = 1.5,
	-- Mejora cuyo nivel desbloquea huevos (RequiredLevel).
	UnlockUpgradeId = "GeneratorPower",

	Eggs = {
		ForestEgg = {
			DisplayName = "Huevo del Bosque",
			Enabled = true,
			Order = 1,
			Cost = 100,
			RequiredLevel = 0,
			-- Probabilidades explícitas en porcentaje (enteros; deben sumar 100).
			Chances = {
				{ PetId = "Sproutling", Chance = 55 },
				{ PetId = "MushroomHopper", Chance = 35 },
				{ PetId = "EmberFox", Chance = 10 },
			},
			-- Posición del santuario relativa al cristal (X, Z). El spawn está en Z ≈ +25.
			StandOffset = Vector2.new(-20, 12),
			Look = {
				Style = "Speckled",
				Shell = Color3.fromRGB(240, 232, 200),
				Spots = Color3.fromRGB(110, 180, 96),
				Accent = Color3.fromRGB(156, 222, 112),
			},
		},

		MossEgg = {
			DisplayName = "Huevo de Musgo",
			Enabled = true,
			Order = 2,
			Cost = 750,
			RequiredLevel = 6, -- etapa Esmeralda del cristal
			Chances = {
				{ PetId = "MossFox", Chance = 75 },
				{ PetId = "MoonOwl", Chance = 25 },
			},
			StandOffset = Vector2.new(-28, 0),
			Look = {
				Style = "Mossy",
				Shell = Color3.fromRGB(104, 150, 78),
				Spots = Color3.fromRGB(70, 118, 56),
				Accent = Color3.fromRGB(120, 214, 120),
			},
		},

		AncientEgg = {
			DisplayName = "Huevo Ancestral",
			Enabled = true,
			Order = 3,
			Cost = 8000,
			RequiredLevel = 16, -- etapa Dorada del cristal
			Chances = {
				{ PetId = "MoonOwl", Chance = 70 },
				{ PetId = "EmeraldFawn", Chance = 30 },
			},
			StandOffset = Vector2.new(24, 10),
			Look = {
				Style = "Runic",
				Shell = Color3.fromRGB(92, 88, 104),
				Spots = Color3.fromRGB(244, 204, 110),
				Accent = Color3.fromRGB(244, 204, 110),
			},
		},
	},
}

return EggConfig
end)()
local Constants = (function()
-- Nombres compartidos entre servidor y cliente.

local Constants = {
	RemotesFolderName = "Remotes",

	Remotes = {
		-- Cliente -> servidor: (upgradeId: string)
		PurchaseUpgrade = "PurchaseUpgrade",
		-- Servidor -> cliente: (success: boolean, code: string, upgradeId: string?)
		PurchaseResult = "PurchaseResult",

		-- Cliente -> servidor: (eggId: string, requestId: string)
		-- requestId identifica la compra: si se reenvía, el servidor devuelve el mismo
		-- resultado sin volver a cobrar ni a sortear.
		PurchaseEgg = "PurchaseEgg",
		-- Servidor -> cliente: (success, code, eggId?, petId?, petUid?, autoEquipped?, requestId?)
		EggResult = "EggResult",
		-- Cliente -> servidor: (petUid: string, equip: boolean)
		EquipPet = "EquipPet",
		-- Servidor -> cliente: (success, code, petUid?, equip?)
		PetActionResult = "PetActionResult",
		-- Cliente -> servidor: () pide el inventario actual
		RequestPetInventory = "RequestPetInventory",
		-- Servidor -> cliente: (snapshot) inventario completo del propio jugador
		PetInventory = "PetInventory",
	},

	-- Atributos que el servidor escribe en el Player (solo lectura para el cliente).
	Attributes = {
		Energy = "Energy",
		ProductionPerSecond = "ProductionPerSecond",
		UpgradeLevelPrefix = "UpgradeLevel_",
		-- Multiplicador total de las mascotas equipadas (1 = sin bonificación).
		PetMultiplier = "PetMultiplier",
		-- PetIds equipados separados por comas; lo usan todos los clientes para dibujar mascotas.
		EquippedPets = "EquippedPets",
	},

	PurchaseCodes = {
		Success = "Success",
		InvalidRequest = "InvalidRequest",
		NotReady = "NotReady",
		MaxLevel = "MaxLevel",
		InsufficientEnergy = "InsufficientEnergy",
		TooFast = "TooFast",
		-- Mascotas y huevos
		InventoryFull = "InventoryFull",
		TooFar = "TooFar",
		NotOwned = "NotOwned",
		EquipLimit = "EquipLimit",
		Unavailable = "Unavailable",
		Locked = "Locked", -- el huevo requiere más nivel de mejora
	},
}

return Constants
end)()
local EggLogic = (function()
-- Lógica pura de huevos (sin APIs de Roblox) para poder probarla fuera de Studio.
-- La usa PetService, que añade las comprobaciones que dependen del mundo
-- (datos cargados, distancia al santuario) y la comunicación con el cliente.

local EggLogic = {}

export type PetEntry = { Uid: string, PetId: string }
export type PetData = { Pets: { PetEntry }, Equipped: { string }, NextPetUid: number }
export type ProfileLike = { Energy: number, UpgradeLevels: { [string]: number }, PetData: PetData }
export type Limits = { MaxInventory: number, MaxEquipped: number, UnlockUpgradeId: string }
export type Grant = { PetId: string, Uid: string, AutoEquipped: boolean }
export type Codes = { [string]: string }

-- Valida la configuración. Devuelve un mensaje de error o nil.
function EggLogic.validate(petConfig, eggConfig): string?
	for rarityId, rarity in petConfig.Rarities do
		if type(rarity.Multiplier) ~= "number" or rarity.Multiplier < 1 then
			return "Rareza " .. rarityId .. " sin multiplicador válido"
		end
	end
	for petId, pet in petConfig.Pets do
		if not petConfig.Rarities[pet.Rarity] then
			return "La mascota " .. petId .. " usa una rareza inexistente: " .. tostring(pet.Rarity)
		end
		if pet.Multiplier ~= nil and (type(pet.Multiplier) ~= "number" or pet.Multiplier < 1) then
			return "La mascota " .. petId .. " tiene un multiplicador no válido"
		end
	end
	for eggId, egg in eggConfig.Eggs do
		if egg.Enabled == false then
			continue
		end
		if type(egg.Cost) ~= "number" or egg.Cost < 0 then
			return "El huevo " .. eggId .. " tiene un coste no válido"
		end
		if type(egg.Chances) ~= "table" or #egg.Chances == 0 then
			return "El huevo " .. eggId .. " no tiene probabilidades"
		end
		local total = 0
		local seen = {}
		for _, entry in egg.Chances do
			if not petConfig.Pets[entry.PetId] then
				return "El huevo " .. eggId .. " referencia una mascota inexistente: " .. tostring(entry.PetId)
			end
			if seen[entry.PetId] then
				return "El huevo " .. eggId .. " repite la mascota " .. entry.PetId
			end
			seen[entry.PetId] = true
			if type(entry.Chance) ~= "number" or entry.Chance <= 0 then
				return "El huevo " .. eggId .. " tiene una probabilidad no válida"
			end
			total += entry.Chance
		end
		if math.abs(total - 100) > 1e-9 then
			return ("Las probabilidades de %s suman %s en lugar de 100"):format(eggId, tostring(total))
		end
	end
	return nil
end

-- `roll` es un número en [0, 100). Devuelve la mascota cuyo tramo lo contiene.
function EggLogic.roll(egg, roll: number): string
	local cumulative = 0
	for _, entry in egg.Chances do
		cumulative += entry.Chance
		if roll < cumulative then
			return entry.PetId
		end
	end
	return egg.Chances[#egg.Chances].PetId
end

-- Comprueba requisitos, cobra UNA vez, sortea y concede la mascota.
-- No modifica nada si devuelve un código distinto de Success.
function EggLogic.purchase(profile: ProfileLike, egg, rollValue: number, limits: Limits, codes: Codes): (string, Grant?)
	local level = profile.UpgradeLevels[limits.UnlockUpgradeId] or 0
	if level < (egg.RequiredLevel or 0) then
		return codes.Locked, nil
	end
	local petData = profile.PetData
	if #petData.Pets >= limits.MaxInventory then
		return codes.InventoryFull, nil
	end
	if profile.Energy < egg.Cost then
		return codes.InsufficientEnergy, nil
	end

	profile.Energy -= egg.Cost
	local petId = EggLogic.roll(egg, rollValue)
	local uid = tostring(petData.NextPetUid)
	petData.NextPetUid += 1
	table.insert(petData.Pets, { Uid = uid, PetId = petId })

	-- Si hay hueco, la mascota nueva se equipa sola.
	local autoEquipped = #petData.Equipped < limits.MaxEquipped
	if autoEquipped then
		table.insert(petData.Equipped, uid)
	end

	return codes.Success, { PetId = petId, Uid = uid, AutoEquipped = autoEquipped }
end

-- Registro de compras ya resueltas por jugador, para que reenviar la misma solicitud
-- (reintento tras un corte, doble clic con lag, cliente manipulado) devuelva el mismo
-- resultado sin cobrar ni sortear otra vez. Guarda las últimas `capacity` solicitudes.
local Ledger = {}
Ledger.__index = Ledger

export type Ledger = typeof(setmetatable({} :: { Capacity: number, Order: { string }, Results: { [string]: any } }, Ledger))

function EggLogic.newLedger(capacity: number): Ledger
	return setmetatable({ Capacity = capacity, Order = {}, Results = {} }, Ledger)
end

function Ledger.get(self: Ledger, requestId: string): any
	return self.Results[requestId]
end

function Ledger.put(self: Ledger, requestId: string, result: any)
	if self.Results[requestId] == nil then
		table.insert(self.Order, requestId)
		if #self.Order > self.Capacity then
			local oldest = table.remove(self.Order, 1)
			self.Results[oldest] = nil
		end
	end
	self.Results[requestId] = result
end

return EggLogic
end)()
local PetMath = (function()
-- Cálculos de mascotas compartidos. El servidor los usa para la producción real;
-- el cliente solo para mostrar información.


local PetMath = {}

function PetMath.getPetMultiplier(petId: string): number
	local pet = PetConfig.Pets[petId]
	if not pet then
		return 1
	end
	if type(pet.Multiplier) == "number" then
		return pet.Multiplier
	end
	local rarity = PetConfig.Rarities[pet.Rarity]
	return if rarity then rarity.Multiplier else 1
end

-- Las bonificaciones se suman: 1 + Σ(multiplicador - 1). Redondeado a 3 decimales.
function PetMath.getTotalMultiplier(petIds: { string }): number
	local total = 1
	for _, petId in petIds do
		total += PetMath.getPetMultiplier(petId) - 1
	end
	return math.floor(total * 1000 + 0.5) / 1000
end

function PetMath.getRarity(petId: string)
	local pet = PetConfig.Pets[petId]
	return if pet then PetConfig.Rarities[pet.Rarity] else nil
end

return PetMath
end)()
local Codes = Constants.PurchaseCodes
local failures = 0
local function check(name, ok) if not ok then failures += 1 end print((ok and "OK   " or "FALLO") .. "  " .. name) end
local function deepcopy(t) if type(t) ~= "table" then return t end local c = {} for k, v in t do c[k] = deepcopy(v) end return c end

-- 1. Configuración
check("configuración real válida", EggLogic.validate(PetConfig, EggConfig) == nil)
for eggId, egg in EggConfig.Eggs do
	local total = 0
	for _, e in egg.Chances do
		total += e.Chance
		check(eggId .. " entrega solo mascotas implementadas: " .. e.PetId, PetConfig.Pets[e.PetId] ~= nil)
	end
	check(eggId .. " suma exactamente 100 (" .. total .. ")", total == 100)
end
local bad = deepcopy(EggConfig); bad.Eggs.ForestEgg.Chances[1].Chance = 54
check("detecta suma 99", EggLogic.validate(PetConfig, bad) ~= nil)
bad = deepcopy(EggConfig); bad.Eggs.MossEgg.Chances[1].PetId = "DragonInexistente"
check("detecta mascota inexistente", EggLogic.validate(PetConfig, bad) ~= nil)
bad = deepcopy(EggConfig); bad.Eggs.MossEgg.Enabled = false; bad.Eggs.MossEgg.Chances = {}
check("huevo desactivado sin recompensas no invalida la config", EggLogic.validate(PetConfig, bad) == nil)
local badPets = deepcopy(PetConfig); badPets.Pets.EmberFox.Rarity = "Mitica"
check("detecta rareza inexistente", EggLogic.validate(badPets, EggConfig) ~= nil)

-- 2. Sorteo
local N = 300000
for eggId, egg in EggConfig.Eggs do
	math.randomseed(2024)
	local counts = {}
	for _ = 1, N do local id = EggLogic.roll(egg, math.random() * 100); counts[id] = (counts[id] or 0) + 1 end
	for _, e in egg.Chances do
		local observed = (counts[e.PetId] or 0) / N * 100
		check(("%s %-14s %6.2f%% (config %d%%)"):format(eggId, e.PetId, observed, e.Chance), math.abs(observed - e.Chance) < 0.5)
	end
end
check("tirada en el límite 100 no falla", EggLogic.roll(EggConfig.Eggs.ForestEgg, 100) == "EmberFox")

-- 3. Compra: energía descontada exactamente una vez
local limits = { MaxInventory = PetConfig.MaxInventory, MaxEquipped = PetConfig.MaxEquipped, UnlockUpgradeId = EggConfig.UnlockUpgradeId }
local function newProfile(energy, level) return { Energy = energy, UpgradeLevels = { GeneratorPower = level }, PetData = { Pets = {}, Equipped = {}, NextPetUid = 1 } } end
local forest = EggConfig.Eggs.ForestEgg
local p = newProfile(250, 0)
local code, grant = EggLogic.purchase(p, forest, 10, limits, Codes)
check("compra correcta", code == Codes.Success and grant ~= nil)
check("energía 250 -> 150 (descuento único de 100)", p.Energy == 150)
check("1 mascota añadida con uid '1'", #p.PetData.Pets == 1 and p.PetData.Pets[1].Uid == "1")
check("auto-equipada al haber hueco", grant.AutoEquipped == true and #p.PetData.Equipped == 1)
check("tirada 10 en Bosque -> Brotecillo", grant.PetId == "Sproutling")

local before = deepcopy(p)
p.Energy = 50
code = EggLogic.purchase(p, forest, 10, limits, Codes)
check("sin saldo -> InsufficientEnergy", code == Codes.InsufficientEnergy)
check("sin saldo no cambia nada", p.Energy == 50 and #p.PetData.Pets == #before.PetData.Pets)

local locked = newProfile(100000, 5)
code = EggLogic.purchase(locked, EggConfig.Eggs.MossEgg, 10, limits, Codes)
check("Musgo con nivel 5 -> Locked", code == Codes.Locked)
check("bloqueado no cobra", locked.Energy == 100000 and #locked.PetData.Pets == 0)
locked.UpgradeLevels.GeneratorPower = 6
code = EggLogic.purchase(locked, EggConfig.Eggs.MossEgg, 10, limits, Codes)
check("Musgo con nivel 6 -> Success, cobra 750", code == Codes.Success and locked.Energy == 100000 - 750)

local full = newProfile(1000, 0)
for i = 1, PetConfig.MaxInventory do table.insert(full.PetData.Pets, { Uid = tostring(i), PetId = "Sproutling" }) end
full.PetData.NextPetUid = PetConfig.MaxInventory + 1
code = EggLogic.purchase(full, forest, 10, limits, Codes)
check("inventario lleno -> InventoryFull sin cobrar", code == Codes.InventoryFull and full.Energy == 1000)

local many = newProfile(1000, 0)
for i = 1, 5 do EggLogic.purchase(many, forest, 10, limits, Codes) end
check("5 compras: energía 1000 - 5x100 = 500", many.Energy == 500)
check("5 compras: 5 mascotas, uids únicos 1..5", #many.PetData.Pets == 5 and many.PetData.Pets[5].Uid == "5")
check("solo " .. PetConfig.MaxEquipped .. " equipadas automáticamente", #many.PetData.Equipped == PetConfig.MaxEquipped)

-- 4. Registro de solicitudes (flujo del manejador de PetService)
local ledger = EggLogic.newLedger(20)
local prof = newProfile(1000, 0)
local function handle(requestId)
	local previous = ledger:get(requestId)
	if previous then return previous end
	local c, g = EggLogic.purchase(prof, forest, 60, limits, Codes)
	local result = { c == Codes.Success, c, "ForestEgg", g and g.PetId, g and g.Uid, g and g.AutoEquipped, requestId }
	if c == Codes.Success then ledger:put(requestId, result) end
	return result
end
local r1 = handle("abc")
local r2 = handle("abc") -- reenvío (reintento del cliente)
local r3 = handle("abc")
check("reenvío devuelve el mismo resultado", r1 == r2 and r2 == r3 and r1[5] == "1")
check("3 envíos del mismo id cobran UNA vez (1000 -> 900)", prof.Energy == 900)
check("3 envíos del mismo id conceden UNA mascota", #prof.PetData.Pets == 1)
handle("otra")
check("una solicitud distinta sí es otra compra", prof.Energy == 800 and #prof.PetData.Pets == 2)
local small = EggLogic.newLedger(2)
small:put("a", 1); small:put("b", 2); small:put("c", 3)
check("el registro olvida las más antiguas (capacidad)", small:get("a") == nil and small:get("c") == 3)

-- 5. Multiplicadores: se calculan desde cero, nunca se acumulan
local ids = { "Sproutling", "EmberFox", "EmeraldFawn" }
local m1 = PetMath.getTotalMultiplier(ids)
local m2 = PetMath.getTotalMultiplier(ids)
check("Brotecillo+Brasa+Cervatillo = x2.35 (" .. m1 .. ")", m1 == 2.35)
check("recalcular no acumula (" .. m2 .. ")", m1 == m2)
print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
