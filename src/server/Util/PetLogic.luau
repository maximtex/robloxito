-- Lógica pura de las mascotas (sin APIs de Roblox) para poder probarla fuera de Studio:
-- validar la configuración, comprar la mascota de un pedestal del jardín (EggConfig.Stands,
-- con dinero) y conceder mascotas. La usa PetService, que añade lo que depende del mundo
-- (datos cargados, distancia al pedestal) y la comunicación con el cliente.

local PetLogic = {}

export type PetEntry = { Uid: string, PetId: string }
export type PetData = { Pets: { PetEntry }, Equipped: { string }, NextPetUid: number }
export type ProfileLike = { Money: number, PetData: PetData }
export type Limits = { MaxInventory: number, MaxEquipped: number }
export type Offer = { PetId: string, Price: number }
export type Grant = { PetId: string, Uid: string, AutoEquipped: boolean }
export type Codes = { [string]: string }

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function checkOffer(petConfig, name: string, offer): string?
	if not petConfig.Pets[offer.PetId] then
		return name .. " vende una mascota inexistente: " .. tostring(offer.PetId)
	end
	if not isFinite(offer.Price) or offer.Price <= 0 then
		return name .. " tiene un precio no válido"
	end
	return nil
end

-- Valida la configuración (rarezas, mascotas y lo que vende el jardín). Mensaje o nil.
function PetLogic.validate(petConfig, eggConfig): string?
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
	for standId, stand in eggConfig.Stands do
		if stand.Enabled ~= false then
			local problem = checkOffer(petConfig, "El pedestal " .. standId, stand)
			if problem then
				return problem
			end
		end
	end
	local rainbow = eggConfig.Gardens.Forest and eggConfig.Gardens.Forest.RainbowPet
	return if rainbow then checkOffer(petConfig, "El pedestal arcoíris", rainbow) else nil
end

-- Concede una mascota (sin cobrar: quien llama ya comprobó todo). Si hay hueco, se equipa.
function PetLogic.grant(petData: PetData, petId: string, maxEquipped: number): Grant
	local uid = tostring(petData.NextPetUid)
	petData.NextPetUid += 1
	table.insert(petData.Pets, { Uid = uid, PetId = petId })
	local autoEquipped = #petData.Equipped < maxEquipped
	if autoEquipped then
		table.insert(petData.Equipped, uid)
	end
	return { PetId = petId, Uid = uid, AutoEquipped = autoEquipped }
end

-- Compra directa: hace falta sitio en el inventario y dinero; cobra UNA vez. No cambia nada
-- si devuelve un código distinto de Success.
function PetLogic.buy(profile: ProfileLike, offer: Offer, limits: Limits, codes: Codes): (string, Grant?)
	if #profile.PetData.Pets >= limits.MaxInventory then
		return codes.InventoryFull, nil
	end
	if not (isFinite(profile.Money) and profile.Money >= offer.Price) then
		return codes.InsufficientMoney, nil
	end
	profile.Money -= offer.Price
	return codes.Success, PetLogic.grant(profile.PetData, offer.PetId, limits.MaxEquipped)
end

-- Mascota de regalo (jefes, premio diario, códigos): sin cobrar y respetando el espacio
-- del inventario.
function PetLogic.grantFree(profile: ProfileLike, petId: string, limits: Limits, codes: Codes): (string, Grant?)
	if #profile.PetData.Pets >= limits.MaxInventory then
		return codes.InventoryFull, nil
	end
	return codes.Success, PetLogic.grant(profile.PetData, petId, limits.MaxEquipped)
end

return PetLogic
