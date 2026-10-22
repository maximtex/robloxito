-- Inventario, tienda y evolución de mascotas (sin huevos):
-- - Comprar la mascota de un pedestal del jardín con dinero (BuyPet, EggConfig.Stands).
-- - Regalos: jefes, premio diario y códigos (grantFreePet) y Robux (grantPet).
-- - Equipar/desequipar mascotas.
-- - Evolucionar mascotas (EvolvePet): fusiona 3 mascotas iguales en su versión ★ Evo (doble multiplicador).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local PetConfig = require(Shared.Config.PetConfig)
local EggConfig = require(Shared.Config.EggConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local PetLogic = require(script.Parent.Parent.Util.PetLogic)
local RebirthLogic = require(Shared.RebirthLogic)
local MonetizationLogic = require(Shared.MonetizationLogic)

local Codes = Constants.PurchaseCodes
local MAX_ID_LENGTH = 64
local RAINBOW_STAND = "Rainbow" -- el pedestal arcoíris (EggConfig.Gardens.Forest.RainbowPet)

local PetService = {}

local disabledReason: string? = nil

local shopLimiter = RateLimiter.new(EggConfig.PurchaseCooldown, 4, 6)
local equipLimiter = RateLimiter.new(0.15, 2, 12)
local syncLimiter = RateLimiter.new(1, 5, 4)

-- Utilidades ------------------------------------------------------------------

-- Lo que vende un pedestal ({ PetId, Price }), o nil
local function offerOf(standId: string)
	if standId == RAINBOW_STAND then
		return EggConfig.Gardens.Forest.RainbowPet
	end
	local stand = EggConfig.Stands[standId]
	return if stand and stand.Enabled ~= false and stand.PetId then stand else nil
end

function PetService.getStandPosition(standId: string): Vector3?
	local base = GeneratorConfig.Position
	if standId == RAINBOW_STAND then
		local at = EggConfig.Gardens.Forest.RainbowOffset
		return Vector3.new(base.X + at.X, base.Y, base.Z + at.Y)
	end
	local stand = EggConfig.Stands[standId]
	if not stand then
		return nil
	end
	local zone = ZoneConfig.Zones[stand.Zone or ZoneConfig.DefaultZone]
	local center = if zone then zone.Center else Vector2.zero
	return Vector3.new(base.X + center.X + stand.StandOffset.X, base.Y, base.Z + center.Y + stand.StandOffset.Y)
end

local function isNearStand(player: Player, standId: string): boolean
	local standPosition = PetService.getStandPosition(standId)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (standPosition and root and root:IsA("BasePart")) then
		return false
	end
	local offset = root.Position - standPosition
	return Vector2.new(offset.X, offset.Z).Magnitude <= EggConfig.MaxPurchaseDistance
end

local function maxEquippedOf(profile: any): number
	return MonetizationLogic.maxEquipped(RebirthLogic.ofProfile(profile), profile.Passes, PetConfig.MaxEquipped)
end

local function maxInventoryOf(profile: any): number
	return MonetizationLogic.maxInventory(profile.Passes, PetConfig.MaxInventory)
end

local function limitsOf(profile: any): PetLogic.Limits
	return { MaxInventory = maxInventoryOf(profile), MaxEquipped = maxEquippedOf(profile) }
end

local function isValidId(value: any): boolean
	return typeof(value) == "string" and #value > 0 and #value <= MAX_ID_LENGTH
end

local function buildSnapshot(player: Player)
	local profile = PlayerDataService.get(player)
	if not profile then
		return { Ready = false, Pets = {}, Equipped = {}, MaxEquipped = PetConfig.MaxEquipped, MaxInventory = PetConfig.MaxInventory }
	end
	local pets = {}
	for _, entry in profile.PetData.Pets do
		table.insert(pets, { Uid = entry.Uid, PetId = entry.PetId })
	end
	return {
		Ready = PlayerDataService.isPetDataReady(profile),
		Saving = profile.DataState == "Loaded",
		Pets = pets,
		Equipped = table.clone(profile.PetData.Equipped),
		MaxEquipped = maxEquippedOf(profile),
		MaxInventory = maxInventoryOf(profile),
	}
end

function PetService.pushInventory(player: Player)
	if player.Parent then
		RemoteService.get(Constants.Remotes.PetInventory):FireClient(player, buildSnapshot(player))
	end
end

local function applyPetChange(player: Player)
	PlayerDataService.recalculateProduction(player)
	PlayerDataService.replicate(player)
	PlayerDataService.markDirty(player)
	PetService.pushInventory(player)
end

-- Acciones --------------------------------------------------------------------

-- Compra la mascota de un pedestal con dinero (junto al pedestal, con sitio en el inventario)
local function buyPet(player: Player, standId: any): (string, PetLogic.Grant?)
	if not isValidId(standId) then
		return Codes.InvalidRequest, nil
	end
	local offer = offerOf(standId)
	if not offer then
		return Codes.InvalidRequest, nil
	end
	if disabledReason then
		return Codes.Unavailable, nil
	end
	local profile = PlayerDataService.get(player)
	if not profile or not PlayerDataService.isPetDataReady(profile) then
		return Codes.NotReady, nil
	end
	if not isNearStand(player, standId) then
		return Codes.TooFar, nil
	end
	local code, grant = PetLogic.buy(profile, offer, limitsOf(profile), Codes)
	if code == Codes.Success then
		applyPetChange(player)
		PlayerDataService.saveNow(player) -- una compra no se pierde con una caída
	end
	return code, grant
end

-- Mascota de regalo (jefes, premio diario, códigos): sin cobrar, si cabe en el inventario.
function PetService.grantFreePet(player: Player, petId: string): (string, PetLogic.Grant?)
	local profile = PlayerDataService.get(player)
	if not profile or not PlayerDataService.isPetDataReady(profile) then
		return Codes.NotReady, nil
	end
	if not PetConfig.Pets[petId] then
		return Codes.InvalidRequest, nil
	end
	local code, grant = PetLogic.grantFree(profile, petId, limitsOf(profile), Codes)
	if code == Codes.Success then
		applyPetChange(player)
	end
	return code, grant
end

-- Mascota exclusiva comprada con Robux (la concede ShopService al procesar la compra):
-- aunque el inventario esté lleno, porque lo pagado se entrega siempre.
function PetService.grantPet(player: Player, petId: string): (string, PetLogic.Grant?)
	local profile = PlayerDataService.get(player)
	if not profile or not PlayerDataService.isPetDataReady(profile) then
		return Codes.NotReady, nil
	end
	if not PetConfig.Pets[petId] then
		return Codes.InvalidRequest, nil
	end
	local grant = PetLogic.grant(profile.PetData, petId, maxEquippedOf(profile))
	applyPetChange(player)
	return Codes.Success, grant
end

function PetService.enforceEquipLimit(player: Player)
	local profile = PlayerDataService.get(player)
	if not profile or not PlayerDataService.isPetDataReady(profile) then
		return
	end
	local equipped = profile.PetData.Equipped
	local limit = maxEquippedOf(profile)
	if #equipped <= limit then
		return
	end
	while #equipped > limit do
		table.remove(equipped)
	end
	applyPetChange(player)
end

local function setEquipped(player: Player, uid: any, equip: any): string
	if not isValidId(uid) or typeof(equip) ~= "boolean" then
		return Codes.InvalidRequest
	end
	local profile = PlayerDataService.get(player)
	if not profile or not PlayerDataService.isPetDataReady(profile) then
		return Codes.NotReady
	end

	local petData = profile.PetData
	local owned = false
	for _, entry in petData.Pets do
		if entry.Uid == uid then
			owned = true
			break
		end
	end
	if not owned then
		return Codes.NotOwned
	end

	local index = table.find(petData.Equipped, uid)
	if equip then
		if index then
			return Codes.Success
		end
		if #petData.Equipped >= maxEquippedOf(profile) then
			return Codes.EquipLimit
		end
		table.insert(petData.Equipped, uid)
	else
		if not index then
			return Codes.Success
		end
		table.remove(petData.Equipped, index)
	end

	applyPetChange(player)
	return Codes.Success
end

-- Evolucionar 3 mascotas iguales en 1 versión ★ Evo
local function evolvePet(player: Player, petId: any): (string, string?)
	if not isValidId(petId) then
		return Codes.InvalidRequest, nil
	end
	local baseDef = PetConfig.Pets[petId]
	local targetPetId = baseDef and baseDef.EvolvesInto
	if not (targetPetId and PetConfig.Pets[targetPetId]) then
		return Codes.InvalidRequest, nil
	end

	local profile = PlayerDataService.get(player)
	if not profile or not PlayerDataService.isPetDataReady(profile) then
		return Codes.NotReady, nil
	end

	local petData = profile.PetData
	local needed = PetConfig.EvolutionCopiesRequired or 3

	-- Priorizar copias NO equipadas primero, y luego equipadas si hace falta
	local equippedSet: { [string]: boolean } = {}
	for _, uid in petData.Equipped do
		equippedSet[uid] = true
	end

	local unequippedMatches = {}
	local equippedMatches = {}
	for _, entry in petData.Pets do
		if entry.PetId == petId then
			if equippedSet[entry.Uid] then
				table.insert(equippedMatches, entry.Uid)
			else
				table.insert(unequippedMatches, entry.Uid)
			end
		end
	end

	if #unequippedMatches + #equippedMatches < needed then
		return Codes.NotOwned, nil
	end

	local consumeSet: { [string]: boolean } = {}
	local picked = 0
	for _, uid in unequippedMatches do
		if picked < needed then
			consumeSet[uid] = true
			picked += 1
		end
	end
	for _, uid in equippedMatches do
		if picked < needed then
			consumeSet[uid] = true
			picked += 1
		end
	end

	-- Quitar las 3 mascotas consumidas del inventario y de equipadas
	local remainingPets = {}
	for _, entry in petData.Pets do
		if not consumeSet[entry.Uid] then
			table.insert(remainingPets, entry)
		end
	end
	petData.Pets = remainingPets

	local remainingEquipped = {}
	for _, uid in petData.Equipped do
		if not consumeSet[uid] then
			table.insert(remainingEquipped, uid)
		end
	end
	petData.Equipped = remainingEquipped

	-- Otorgar la mascota evolucionada ★ Evo y equiparla si hay hueco
	local newUid = tostring(petData.NextPetUid)
	petData.NextPetUid += 1
	table.insert(petData.Pets, { Uid = newUid, PetId = targetPetId })
	if #petData.Equipped < maxEquippedOf(profile) then
		table.insert(petData.Equipped, newUid)
	end

	applyPetChange(player)
	PlayerDataService.saveNow(player)
	return Codes.Success, targetPetId
end

function PetService.start()
	disabledReason = PetLogic.validate(PetConfig, EggConfig)
	if disabledReason then
		warn("[PetService] Configuración de mascotas no válida; tienda del jardín desactivada: " .. disabledReason)
	end

	local shopResult = RemoteService.get(Constants.Remotes.PetShopResult)
	local actionResult = RemoteService.get(Constants.Remotes.PetActionResult)

	RemoteService.get(Constants.Remotes.BuyPet).OnServerEvent:Connect(function(player: Player, standId: any)
		local rate = shopLimiter:check(player)
		if rate == "flood" then
			return
		end
		local safeStandId = if isValidId(standId) then standId else nil
		if rate == "cooldown" then
			shopResult:FireClient(player, false, Codes.TooFast, safeStandId)
			return
		end
		local code, grant = buyPet(player, standId)
		shopResult:FireClient(player, code == Codes.Success, code, safeStandId, if grant then grant.PetId else nil, if grant then grant.Uid else nil, if grant then grant.AutoEquipped else nil)
	end)

	RemoteService.get(Constants.Remotes.EquipPet).OnServerEvent:Connect(function(player: Player, uid: any, equip: any)
		local rate = equipLimiter:check(player)
		if rate == "flood" then
			return
		end
		local safeUid = if isValidId(uid) then uid else nil
		if rate == "cooldown" then
			actionResult:FireClient(player, false, Codes.TooFast, safeUid)
			return
		end

		local code = setEquipped(player, uid, equip)
		actionResult:FireClient(player, code == Codes.Success, code, safeUid, if typeof(equip) == "boolean" then equip else nil)
	end)

	RemoteService.get(Constants.Remotes.EvolvePet).OnServerEvent:Connect(function(player: Player, petId: any)
		local rate = equipLimiter:check(player)
		if rate == "flood" then
			return
		end
		local safePetId = if isValidId(petId) then petId else nil
		if rate == "cooldown" then
			actionResult:FireClient(player, false, Codes.TooFast, safePetId)
			return
		end
		local code, evolvedPetId = evolvePet(player, petId)
		actionResult:FireClient(player, code == Codes.Success, code, evolvedPetId or safePetId, "Evolve")
	end)

	RemoteService.get(Constants.Remotes.RequestPetInventory).OnServerEvent:Connect(function(player: Player)
		if syncLimiter:check(player) == "ok" then
			PetService.pushInventory(player)
		end
	end)

	PlayerDataService.onPetDataReady(PetService.pushInventory)

	Players.PlayerRemoving:Connect(function(player)
		shopLimiter:remove(player)
		equipLimiter:remove(player)
		syncLimiter:remove(player)
	end)
end

return PetService
