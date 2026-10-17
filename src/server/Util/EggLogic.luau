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
