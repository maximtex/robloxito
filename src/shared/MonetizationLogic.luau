-- Lógica pura de la tienda (sin APIs de Roblox), compartida: el servidor la usa para
-- conceder y aplicar los pases y las compras; el cliente, para mostrarlos.
--
-- Pases que tiene un jugador: tabla { [PassKey] = true } (la rellena ShopService al
-- entrar, consultando a Roblox; no se guarda: Roblox es la fuente de verdad). En los
-- atributos viaja como texto "DoubleEnergy,TripleHatch".
--
-- Datos guardados (campo Shop del registro):
--   Receipts: { PurchaseId } últimas compras sueltas ya concedidas (no se conceden dos veces).
--   AutoUpgrade: boolean, el interruptor de la mejora automática (encendido por defecto).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local RebirthLogic = require(Shared.RebirthLogic)

local MonetizationLogic = {}

export type Passes = { [string]: boolean }
export type ShopData = { Receipts: { string }, AutoUpgrade: boolean }

local function ordered(map: { [string]: any }): { string }
	local list = {}
	for key in map do
		table.insert(list, key)
	end
	table.sort(list, function(a, b)
		return (map[a].Order or 0) < (map[b].Order or 0)
	end)
	return list
end

local PASS_ORDER = ordered(MonetizationConfig.GamePasses)
local PRODUCT_ORDER = ordered(MonetizationConfig.Products)

function MonetizationLogic.passOrder(): { string }
	return PASS_ORDER
end

function MonetizationLogic.productOrder(): { string }
	return PRODUCT_ORDER
end

local function owns(passes: Passes?, key: string): boolean
	return type(passes) == "table" and passes[key] == true
end
MonetizationLogic.owns = owns

-- Texto de atributo <-> tabla de pases (solo pases que existen).
function MonetizationLogic.passesText(passes: Passes?): string
	local list = {}
	for _, key in PASS_ORDER do
		if owns(passes, key) then
			table.insert(list, key)
		end
	end
	return table.concat(list, ",")
end

function MonetizationLogic.parsePasses(text: any): Passes
	local passes = {}
	if type(text) == "string" then
		for _, key in string.split(text, ",") do
			if MonetizationConfig.GamePasses[key] then
				passes[key] = true
			end
		end
	end
	return passes
end

-- Efectos -------------------------------------------------------------------------------------

function MonetizationLogic.energyMultiplier(passes: Passes?): number
	return if owns(passes, "DoubleEnergy") then MonetizationConfig.EnergyMultiplier else 1
end

function MonetizationLogic.petSlotBonus(passes: Passes?): number
	return if owns(passes, "PetSpace") then MonetizationConfig.PetSlotBonus else 0
end

function MonetizationLogic.inventoryBonus(passes: Passes?): number
	return if owns(passes, "PetSpace") then MonetizationConfig.InventoryBonus else 0
end

-- Sin el pase, el arma solo dispara cuando el jugador lo pide (clic, F o "Disparar").
function MonetizationLogic.autoFire(passes: Passes?): boolean
	return owns(passes, "AutoFire")
end

-- Mascotas equipadas a la vez: base + renacimiento ("Espacio de mascota") + pase.
function MonetizationLogic.maxEquipped(rebirth: any, passes: Passes?, base: number): number
	return RebirthLogic.maxEquipped(rebirth, base) + MonetizationLogic.petSlotBonus(passes)
end

-- Tope absoluto (para guardar lo equipado antes de saber si tiene el pase, y para dibujar
-- las mascotas de los demás).
function MonetizationLogic.maxEquippedCap(base: number): number
	return RebirthLogic.maxEquippedCap(base) + MonetizationConfig.PetSlotBonus
end

function MonetizationLogic.maxInventory(passes: Passes?, base: number): number
	return base + MonetizationLogic.inventoryBonus(passes)
end

function MonetizationLogic.hatchCount(passes: Passes?, requested: any): number
	if requested == MonetizationConfig.TripleCount and owns(passes, "TripleHatch") then
		return MonetizationConfig.TripleCount
	end
	return 1
end

-- Ids de Roblox -> artículo ------------------------------------------------------------------

function MonetizationLogic.passById(assetId: any): string?
	if type(assetId) ~= "number" or assetId <= 0 then
		return nil
	end
	for key, def in MonetizationConfig.GamePasses do
		if def.Id == assetId then
			return key
		end
	end
	return nil
end

function MonetizationLogic.productById(productId: any): (string?, any)
	if type(productId) ~= "number" or productId <= 0 then
		return nil, nil
	end
	for key, def in MonetizationConfig.Products do
		if def.Id == productId then
			return key, def
		end
	end
	return nil, nil
end

-- Mascota exclusiva de un producto: su PetId y su definición.
function MonetizationLogic.petProductById(productId: any): (string?, any)
	if type(productId) ~= "number" or productId <= 0 then
		return nil, nil
	end
	for petId, def in MonetizationConfig.PetProducts do
		if def.Id == productId then
			return petId, def
		end
	end
	return nil, nil
end

-- Arma de un producto: su id de WeaponConfig y su definición.
function MonetizationLogic.weaponProductById(productId: any): (string?, any)
	if type(productId) ~= "number" or productId <= 0 then
		return nil, nil
	end
	for weaponId, def in MonetizationConfig.WeaponProducts do
		if def.Id == productId then
			return weaponId, def
		end
	end
	return nil, nil
end

-- Energía de una compra suelta con la producción actual (por segundo).
function MonetizationLogic.productEnergy(def: any, production: number): number
	local rate = if type(production) == "number" and production == production and production > 0 and production < math.huge then production else 0
	return math.floor(math.max(def.Min or 0, rate * (def.Minutes or 0) * 60))
end

-- Datos guardados ------------------------------------------------------------------------------

function MonetizationLogic.empty(): ShopData
	return { Receipts = {}, AutoUpgrade = true }
end

function MonetizationLogic.sanitize(raw: any): ShopData
	local data = MonetizationLogic.empty()
	if type(raw) ~= "table" then
		return data
	end
	if type(raw.Receipts) == "table" then
		for _, id in raw.Receipts do
			if type(id) == "string" and #id > 0 and #id <= 100 and not table.find(data.Receipts, id) then
				table.insert(data.Receipts, id)
			end
		end
		while #data.Receipts > MonetizationConfig.MaxReceipts do
			table.remove(data.Receipts, 1)
		end
	end
	if type(raw.AutoUpgrade) == "boolean" then
		data.AutoUpgrade = raw.AutoUpgrade
	end
	return data
end

function MonetizationLogic.serialize(data: ShopData): any
	return { Receipts = table.clone(data.Receipts), AutoUpgrade = data.AutoUpgrade }
end

function MonetizationLogic.hasReceipt(data: ShopData, purchaseId: string): boolean
	return table.find(data.Receipts, purchaseId) ~= nil
end

function MonetizationLogic.addReceipt(data: ShopData, purchaseId: string)
	if not table.find(data.Receipts, purchaseId) then
		table.insert(data.Receipts, purchaseId)
		while #data.Receipts > MonetizationConfig.MaxReceipts do
			table.remove(data.Receipts, 1)
		end
	end
end

return MonetizationLogic
