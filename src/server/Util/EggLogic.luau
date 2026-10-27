-- Lógica pura de huevos (sin APIs de Roblox) para poder probarla fuera de Studio.
-- La usa PetService, que añade las comprobaciones que dependen del mundo
-- (datos cargados, distancia al santuario) y la comunicación con el cliente.

local EggLogic = {}

export type PetEntry = { Uid: string, PetId: string }
export type PetData = { Pets: { PetEntry }, Equipped: { string }, NextPetUid: number, UnlockedZones: { string }? }
export type ProfileLike = { Money: number, PetData: PetData }
export type Limits = { MaxInventory: number, MaxEquipped: number }
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

-- Requisitos del huevo (zona desbloqueada). nil si se cumplen; si no, el código.
local function requirementCode(profile: ProfileLike, egg, limits: Limits, codes: Codes): string?
	-- Huevo de una zona que se compra: la zona debe estar desbloqueada en los datos del
	-- servidor (nunca se confía en el cliente ni en dónde dice estar).
	if egg.RequiredZone then
		local unlocked = profile.PetData.UnlockedZones or {}
		if not table.find(unlocked, egg.RequiredZone) then
			return codes.ZoneLocked
		end
	end
	return nil
end

-- Concede una mascota ya sorteada (sin cobrar: quien llama ya comprobó todo).
local function grant(petData: PetData, petId: string, maxEquipped: number): Grant
	local uid = tostring(petData.NextPetUid)
	petData.NextPetUid += 1
	table.insert(petData.Pets, { Uid = uid, PetId = petId })
	-- Si hay hueco, la mascota nueva se equipa sola.
	local autoEquipped = #petData.Equipped < maxEquipped
	if autoEquipped then
		table.insert(petData.Equipped, uid)
	end
	return { PetId = petId, Uid = uid, AutoEquipped = autoEquipped }
end

-- Comprueba requisitos, cobra UNA vez, sortea y concede la mascota.
-- No modifica nada si devuelve un código distinto de Success.
function EggLogic.purchase(profile: ProfileLike, egg, rollValue: number, limits: Limits, codes: Codes): (string, Grant?)
	local code, grants = EggLogic.purchaseMany(profile, egg, { rollValue }, limits, codes)
	return code, if grants then grants[1] else nil
end

-- Abre varios huevos de una vez (pase «Abrir ×3»): todo o nada. Hace falta energía para
-- todos y sitio para todas las mascotas; si no, no cobra ni concede nada.
function EggLogic.purchaseMany(profile: ProfileLike, egg, rolls: { number }, limits: Limits, codes: Codes): (string, { Grant }?)
	local count = #rolls
	if count < 1 then
		return codes.InvalidRequest or "InvalidRequest", nil
	end
	local blocked = requirementCode(profile, egg, limits, codes)
	if blocked then
		return blocked, nil
	end
	local petData = profile.PetData
	if #petData.Pets + count > limits.MaxInventory then
		return codes.InventoryFull, nil
	end
	-- Los huevos se pagan con 💰 (economía 2: EconomyConfig)
	local total = egg.Cost * count
	if (profile.Money or 0) < total then
		return codes.InsufficientMoney, nil
	end

	profile.Money -= total
	local grants = {}
	for _, rollValue in rolls do
		table.insert(grants, grant(petData, EggLogic.roll(egg, rollValue), limits.MaxEquipped))
	end
	return codes.Success, grants
end

-- Mascota de regalo (premio diario, códigos): del huevo indicado, sin cobrar. Respeta los
-- requisitos del huevo y el espacio del inventario.
function EggLogic.grantFree(profile: ProfileLike, egg, rollValue: number, limits: Limits, codes: Codes): (string, Grant?)
	local blocked = requirementCode(profile, egg, limits, codes)
	if blocked then
		return blocked, nil
	end
	if #profile.PetData.Pets >= limits.MaxInventory then
		return codes.InventoryFull, nil
	end
	return codes.Success, grant(profile.PetData, EggLogic.roll(egg, rollValue), limits.MaxEquipped)
end

-- Mascota concreta ya pagada con Robux (MonetizationConfig.PetProducts): sin huevo ni sorteo
-- y aunque el inventario esté lleno, porque lo pagado se entrega siempre.
function EggLogic.grantPet(petData: PetData, petId: string, maxEquipped: number): Grant
	return grant(petData, petId, maxEquipped)
end

-- El mejor huevo (el más caro) que el jugador ya puede abrir, o nil.
function EggLogic.bestEgg(profile: ProfileLike, eggConfig, limits: Limits, codes: Codes): string?
	local bestId, bestCost = nil, -1
	for eggId, egg in eggConfig.Eggs do
		if egg.Enabled ~= false and type(egg.Cost) == "number" and not requirementCode(profile, egg, limits, codes) then
			if egg.Cost > bestCost or (egg.Cost == bestCost and bestId and eggId < bestId) then
				bestId, bestCost = eggId, egg.Cost
			end
		end
	end
	return bestId
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
