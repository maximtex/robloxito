Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end }
Vector2 = { new = function(x, y) return { X = x, Y = y } end, zero = { X = 0, Y = 0 } }
Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }
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

		-- Huevo de Cristal (Valle Cristalino) -----------------------------------------
		QuartzFox = {
			DisplayName = "Zorrito de Cuarzo",
			Rarity = "Rare",
			Multiplier = 1.5,
			Look = { Style = "Quartz", Prototype = true, Primary = Color3.fromRGB(246, 222, 232), Secondary = Color3.fromRGB(236, 150, 196) },
		},
		CrystalTurtle = {
			DisplayName = "Tortuga de Musgo Cristalino",
			Rarity = "Epic",
			Multiplier = 2,
			Look = { Style = "Turtle", Prototype = true, Primary = Color3.fromRGB(110, 150, 84), Secondary = Color3.fromRGB(110, 214, 220) },
		},
		AmethystDragon = {
			DisplayName = "Dragón Bebé de Amatista",
			Rarity = "Legendary",
			Multiplier = 3,
			Look = { Style = "Dragon", Prototype = true, Primary = Color3.fromRGB(150, 92, 214), Secondary = Color3.fromRGB(220, 170, 255) },
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
-- Zone: zona donde está el santuario (StandOffset es relativo a su centro; por defecto el
-- bosque). RequiredZone: la zona debe estar desbloqueada para comprar (lo valida el servidor).
--
-- Precios, calibrados con las mejoras (coste del nivel N = 10 · 1.5^N; producción ≈ 1 + N):
-- - Bosque (100): ~ el precio de la mejora 5-6. Una Común (+10 %) a producción 6/s
--   se amortiza en ~3 min.
-- - Musgo (750, requiere nivel 6): ~ las mejoras 9-10. Valor medio +31 % por huevo.
-- - Ancestral (8 000, requiere nivel 16): ~ la mejora 16-17. Valor medio +65 % por huevo.
-- - Cristal (5 000, solo en el Valle Cristalino, que cuesta 2 500 desbloquear): ~6 min a
--   nivel 10-12. Valor medio +72 % por huevo y la primera Legendaria del juego.

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

		CrystalEgg = {
			DisplayName = "Huevo de Cristal",
			Enabled = true,
			Order = 4,
			Cost = 5000,
			RequiredLevel = 0,
			Zone = "CrystalValley",
			RequiredZone = "CrystalValley",
			Chances = {
				{ PetId = "QuartzFox", Chance = 65 },
				{ PetId = "CrystalTurtle", Chance = 30 },
				{ PetId = "AmethystDragon", Chance = 5 },
			},
			StandOffset = Vector2.new(18, 8), -- relativo al centro del Valle
			Look = {
				Style = "Crystalline",
				Shell = Color3.fromRGB(176, 214, 236),
				Spots = Color3.fromRGB(176, 120, 236),
				Accent = Color3.fromRGB(150, 196, 255),
			},
		},
	},
}

return EggConfig
end)()
local ZoneConfig = (function()
-- Zonas del mundo y portales entre ellas. Configuración centralizada del precio de
-- desbloqueo, puntos de llegada y límites de cada zona.
--
-- Posiciones RELATIVAS al Cristal del Renacimiento (GeneratorConfig.Position), en X/Z.
-- Cada zona tiene un centro; sus puntos (llegada, portales) son relativos a ese centro.
--
-- Precio del Valle (2 500): con las fórmulas actuales (mejora N = 10·1.5^N, producción
-- 1 + N), un jugador llega al nivel 10 hacia el minuto 3 y reúne 2 500 en ~3 min más
-- (~13/s con dos mascotas comunes). Es un objetivo de progresión sin espera excesiva.

local ZoneConfig = {
	DefaultZone = "Forest",

	Zones = {
		Forest = {
			DisplayName = "Bosque Inicial",
			Center = Vector2.new(0, 0),
			UnlockCost = 0, -- siempre disponible
			-- Llegada al volver: junto al portal del bosque, mirando al cristal (-Z).
			Arrival = Vector3.new(0, 0, 44),
			ArrivalFacing = Vector3.new(0, 0, -1),
			Radius = 320, -- radio horizontal que ocupa la zona
		},
		CrystalValley = {
			DisplayName = "Valle Cristalino",
			-- Lejos del bosque (su terreno acaba en ±310) para que no se vean ni se solapen.
			Center = Vector2.new(1400, 0),
			UnlockCost = 2500,
			Arrival = Vector3.new(0, 0, 44),
			ArrivalFacing = Vector3.new(0, 0, -1),
			Radius = 260,
		},
	},

	-- Portales: dónde están (zona + desplazamiento) y a qué zona llevan.
	Portals = {
		ForestPortal = {
			Zone = "Forest",
			Offset = Vector2.new(0, 56), -- al final del camino, detrás del spawn
			Target = "CrystalValley",
			Style = "Ancient",
		},
		ValleyPortal = {
			Zone = "CrystalValley",
			Offset = Vector2.new(0, 58),
			Target = "Forest",
			Style = "Return",
		},
	},

	-- Distancia máxima (horizontal) a un portal para desbloquear o viajar.
	InteractDistance = 18,
	-- Segundos mínimos entre viajes y entre intentos de desbloqueo de un jugador.
	TravelCooldown = 2,
	UnlockCooldown = 1,
}

return ZoneConfig
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

		-- Cliente -> servidor: (zoneId: string) desbloquear una zona en su portal
		UnlockZone = "UnlockZone",
		-- Servidor -> cliente: (success, code, zoneId?, missingEnergy?)
		ZoneResult = "ZoneResult",
		-- Cliente -> servidor: (zoneId: string) viajar a una zona desde un portal
		TravelToZone = "TravelToZone",
		-- Servidor -> cliente: (success, code, zoneId?)
		TravelResult = "TravelResult",
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
		-- Zonas desbloqueadas separadas por comas (solo informativo para la interfaz).
		UnlockedZones = "UnlockedZones",
		-- Zona en la que está el jugador (la fija el servidor al viajar o reaparecer).
		CurrentZone = "CurrentZone",
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
		ZoneLocked = "ZoneLocked", -- la zona (o el huevo de esa zona) no está desbloqueada
		AlreadyUnlocked = "AlreadyUnlocked",
		Busy = "Busy", -- ya hay un viaje en curso
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
export type PetData = { Pets: { PetEntry }, Equipped: { string }, NextPetUid: number, UnlockedZones: { string }? }
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
	-- Huevo de una zona que se compra: la zona debe estar desbloqueada en los datos del
	-- servidor (nunca se confía en el cliente ni en dónde dice estar).
	if egg.RequiredZone then
		local unlocked = profile.PetData.UnlockedZones or {}
		if not table.find(unlocked, egg.RequiredZone) then
			return codes.ZoneLocked, nil
		end
	end
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
local ZoneLogic = (function()
-- Lógica pura de zonas (sin APIs de Roblox) para poder probarla fuera de Studio.
-- La usa ZoneService, que añade las comprobaciones del mundo (datos cargados,
-- distancia al portal) y el viaje.

local ZoneLogic = {}

export type ProfileLike = { Energy: number, PetData: { UnlockedZones: { string } } }
export type Codes = { [string]: string }

function ZoneLogic.isUnlocked(profile: ProfileLike, zoneConfig, zoneId: string): boolean
	local zone = zoneConfig.Zones[zoneId]
	if not zone then
		return false
	end
	if (zone.UnlockCost or 0) <= 0 then
		return true
	end
	return table.find(profile.PetData.UnlockedZones, zoneId) ~= nil
end

-- Desbloquea una zona cobrando su precio UNA vez. Si ya estaba desbloqueada no cobra
-- (AlreadyUnlocked), de modo que repetir la solicitud nunca cobra dos veces.
-- Devuelve el código y, si falta energía, cuánta falta.
function ZoneLogic.unlock(profile: ProfileLike, zoneConfig, zoneId: string, codes: Codes): (string, number?)
	local zone = zoneConfig.Zones[zoneId]
	if not zone then
		return codes.InvalidRequest, nil
	end
	if ZoneLogic.isUnlocked(profile, zoneConfig, zoneId) then
		return codes.AlreadyUnlocked, nil
	end
	local cost = zone.UnlockCost
	if profile.Energy < cost then
		return codes.InsufficientEnergy, math.ceil(cost - profile.Energy)
	end
	profile.Energy -= cost
	table.insert(profile.PetData.UnlockedZones, zoneId)
	return codes.Success, nil
end

return ZoneLogic
end)()
local STYLES = { "Sprout","Fox","Owl","Mushroom","Ember","Fawn","Quartz","Turtle","Dragon" }
local MOTIONS = { "Sprout","Mushroom","Fox","Ember","Fawn","Owl","Quartz","Turtle","Dragon" }
local MAX_STORED_PETS = 1000
local SaveService = {}
function SaveService.emptyData(): PetData
	return { Pets = {}, Archived = {}, Equipped = {}, NextPetUid = 1, UnlockedZones = {} }
end
local function sanitize(raw: any): PetData
	local result = SaveService.emptyData()
	if type(raw) ~= "table" then
		return result
	end

	local seen: { [string]: boolean } = {}
	if type(raw.Pets) == "table" then
		for _, entry in raw.Pets do
			if #result.Pets + #result.Archived >= MAX_STORED_PETS then
				break
			end
			if type(entry) == "table" and type(entry.Uid) == "string" and type(entry.PetId) == "string" and not seen[entry.Uid] then
				seen[entry.Uid] = true
				local clean = { Uid = entry.Uid, PetId = entry.PetId }
				if PetConfig.Pets[entry.PetId] then
					table.insert(result.Pets, clean)
				else
					table.insert(result.Archived, clean)
				end
			end
		end
	end

	local valid: { [string]: boolean } = {}
	for _, entry in result.Pets do
		valid[entry.Uid] = true
	end
	if type(raw.Equipped) == "table" then
		for _, uid in raw.Equipped do
			if type(uid) == "string" and valid[uid] and not table.find(result.Equipped, uid) and #result.Equipped < PetConfig.MaxEquipped then
				table.insert(result.Equipped, uid)
			end
		end
	end

	local nextUid = if type(raw.NextPetUid) == "number" and raw.NextPetUid >= 1 then math.floor(raw.NextPetUid) else 1
	-- Garantiza que nunca se reutiliza un Uid existente.
	for uid in seen do
		local number = tonumber(uid)
		if number and number >= nextUid then
			nextUid = math.floor(number) + 1
		end
	end
	result.NextPetUid = nextUid

	-- Zonas desbloqueadas: textos únicos. Las partidas antiguas no tienen este campo.
	if type(raw.UnlockedZones) == "table" then
		for _, zoneId in raw.UnlockedZones do
			if type(zoneId) == "string" and #zoneId <= 64 and not table.find(result.UnlockedZones, zoneId) and #result.UnlockedZones < 100 then
				table.insert(result.UnlockedZones, zoneId)
			end
		end
	end

	return result
end
local Codes = Constants.PurchaseCodes
local failures = 0
local function check(name, ok) if not ok then failures += 1 end print((ok and "OK   " or "FALLO") .. "  " .. name) end
local function newProfile(energy) return { Energy = energy, UpgradeLevels = { GeneratorPower = 0 }, PetData = SaveService.emptyData() } end

print("-- Desbloqueo del Valle")
local valleyCost = ZoneConfig.Zones.CrystalValley.UnlockCost
check("precio centralizado en ZoneConfig = 2500", valleyCost == 2500)
local p = newProfile(1000)
local code, missing = ZoneLogic.unlock(p, ZoneConfig, "CrystalValley", Codes)
check("sin saldo -> InsufficientEnergy, faltan 1500 (" .. tostring(missing) .. ")", code == Codes.InsufficientEnergy and missing == 1500)
check("sin saldo no cobra ni desbloquea", p.Energy == 1000 and #p.PetData.UnlockedZones == 0)
p.Energy = 3000
code = ZoneLogic.unlock(p, ZoneConfig, "CrystalValley", Codes)
check("con saldo -> Success, 3000 -> 500", code == Codes.Success and p.Energy == 500)
check("queda registrado en los datos", ZoneLogic.isUnlocked(p, ZoneConfig, "CrystalValley"))
for i = 1, 3 do code = ZoneLogic.unlock(p, ZoneConfig, "CrystalValley", Codes) end
check("3 solicitudes repetidas -> AlreadyUnlocked sin cobrar (sigue 500)", code == Codes.AlreadyUnlocked and p.Energy == 500 and #p.PetData.UnlockedZones == 1)
check("el bosque siempre está abierto", ZoneLogic.isUnlocked(newProfile(0), ZoneConfig, "Forest"))
check("zona inexistente -> InvalidRequest", ZoneLogic.unlock(newProfile(1e9), ZoneConfig, "Atlantis", Codes) == Codes.InvalidRequest)

print("-- Huevo de Cristal")
check("configuración de huevos válida (incluye el de Cristal)", EggLogic.validate(PetConfig, EggConfig) == nil)
local egg = EggConfig.Eggs.CrystalEgg
local total = 0
for _, e in egg.Chances do
	total += e.Chance
	check("recompensa anunciada existe: " .. e.PetId, PetConfig.Pets[e.PetId] ~= nil)
end
check("probabilidades suman exactamente 100 (" .. total .. ")", total == 100)
local limits = { MaxInventory = PetConfig.MaxInventory, MaxEquipped = PetConfig.MaxEquipped, UnlockUpgradeId = EggConfig.UnlockUpgradeId }
local locked = newProfile(100000)
code = EggLogic.purchase(locked, egg, 10, limits, Codes)
check("sin desbloquear el Valle -> ZoneLocked, sin cobrar", code == Codes.ZoneLocked and locked.Energy == 100000 and #locked.PetData.Pets == 0)
ZoneLogic.unlock(locked, ZoneConfig, "CrystalValley", Codes)
check("desbloqueo cobra 2500", locked.Energy == 100000 - 2500)
local grant
code, grant = EggLogic.purchase(locked, egg, 10, limits, Codes)
check("tras desbloquear -> Success, cobra 5000 una vez", code == Codes.Success and locked.Energy == 100000 - 2500 - 5000)
check("tirada 10 -> Zorrito de Cuarzo", grant.PetId == "QuartzFox")
math.randomseed(99)
local counts, N = {}, 300000
for _ = 1, N do local id = EggLogic.roll(egg, math.random() * 100); counts[id] = (counts[id] or 0) + 1 end
for _, e in egg.Chances do
	local observed = (counts[e.PetId] or 0) / N * 100
	check(("%-15s %6.2f%% (config %d%%)"):format(e.PetId, observed, e.Chance), math.abs(observed - e.Chance) < 0.5)
end
check("los huevos del bosque no exigen zona (siguen funcionando)", EggConfig.Eggs.ForestEgg.RequiredZone == nil and EggLogic.purchase(newProfile(500), EggConfig.Eggs.ForestEgg, 10, limits, Codes) == Codes.Success)

print("-- Mascotas nuevas")
local owner = {}
for petId, pet in PetConfig.Pets do
	local style = pet.Look.Style
	local own = table.find(STYLES, style) ~= nil and table.find(MOTIONS, style) ~= nil and owner[style] == nil
	owner[style] = petId
	if petId == "QuartzFox" or petId == "CrystalTurtle" or petId == "AmethystDragon" then
		check(("%s (%s, %s): modelo y movimiento propios"):format(petId, pet.Rarity, style), own and pet.Look.Prototype == true)
	end
end
check("se conservan las 9 mascotas (6 anteriores + 3 nuevas)", (function() local n = 0 for _ in PetConfig.Pets do n += 1 end return n end)() == 9)

print("-- Guardado")
local old = sanitize({ Pets = { { Uid = "1", PetId = "Sproutling" } }, Equipped = { "1" }, NextPetUid = 2 })
check("partida antigua sin zonas -> lista vacía, mascotas intactas", #old.UnlockedZones == 0 and #old.Pets == 1 and #old.Equipped == 1)
local saved = sanitize({ Pets = {}, UnlockedZones = { "CrystalValley", "CrystalValley", 7, "ZonaFutura" } })
check("zonas: sin duplicados ni basura, se conservan las desconocidas", #saved.UnlockedZones == 2 and saved.UnlockedZones[1] == "CrystalValley" and saved.UnlockedZones[2] == "ZonaFutura")
local withValleyPets = sanitize({ Pets = { { Uid = "1", PetId = "AmethystDragon" } }, Equipped = { "1" }, UnlockedZones = { "CrystalValley" } })
check("mascota del Valle guardada se carga y equipa", #withValleyPets.Pets == 1 and #withValleyPets.Equipped == 1 and #withValleyPets.Archived == 0)
print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
