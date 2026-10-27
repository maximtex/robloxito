-- Huevos, inventario y evolución de mascotas:
-- - Comprar/abrir huevo (3 huevos, 3 mascotas por huevo).
-- - Equipar/desequipar mascotas.
-- - Evolucionar mascotas (EvolvePet): fusiona 3 mascotas iguales en su versión ★ Evo (doble multiplicador).
-- - Abrir los huevos guardados en el inventario (openStoredEgg; lo pide ItemService).
-- - Con la Poción de Suerte activa, el sorteo de los huevos se repite y se queda el mejor.

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
local EggLogic = require(script.Parent.Parent.Util.EggLogic)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)
local RebirthLogic = require(Shared.RebirthLogic)
local MonetizationLogic = require(Shared.MonetizationLogic)
local PetMath = require(Shared.PetMath)
local ItemConfig = require(Shared.Config.ItemConfig)
local ItemLogic = require(Shared.ItemLogic)

local Codes = Constants.PurchaseCodes
local MAX_ID_LENGTH = 64
local LEDGER_CAPACITY = 20

local PetService = {}

local disabledReason: string? = nil
local random = Random.new()

local eggLimiter = RateLimiter.new(EggConfig.PurchaseCooldown, 4, 6)
local equipLimiter = RateLimiter.new(0.15, 2, 12)
local syncLimiter = RateLimiter.new(1, 5, 4)
local ledgers: { [Player]: EggLogic.Ledger } = {}

-- Utilidades ------------------------------------------------------------------

function PetService.getStandPosition(eggId: string): Vector3?
	local egg = EggConfig.Eggs[eggId]
	if not egg then
		return nil
	end
	local zone = ZoneConfig.Zones[egg.Zone or ZoneConfig.DefaultZone]
	local center = if zone then zone.Center else Vector2.zero
	local base = GeneratorConfig.Position
	return Vector3.new(base.X + center.X + egg.StandOffset.X, base.Y, base.Z + center.Y + egg.StandOffset.Y)
end

local function isNearStand(player: Player, eggId: string): boolean
	local standPosition = PetService.getStandPosition(eggId)
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

local function limitsOf(profile: any): EggLogic.Limits
	return {
		MaxInventory = maxInventoryOf(profile),
		MaxEquipped = maxEquippedOf(profile),
	}
end

local function isValidId(value: any): boolean
	return typeof(value) == "string" and #value > 0 and #value <= MAX_ID_LENGTH
end

-- Número del sorteo de un huevo, en [0, 100). Con la Poción de Suerte se tira varias veces
-- (ItemConfig.LuckRolls) y se queda el más alto: en EggConfig.Chances las raras van al final.
local function rollFor(profile: any): number
	local value = random:NextNumber(0, 100)
	if ItemLogic.isActive(ItemLogic.ofProfile(profile), "Luck", os.time()) then
		for _ = 2, ItemConfig.LuckRolls do
			value = math.max(value, random:NextNumber(0, 100))
		end
	end
	return value
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
	PlayerDataService.refreshStats(player)
	PlayerDataService.replicate(player)
	PlayerDataService.markDirty(player)
	PetService.pushInventory(player)
end

-- Acciones --------------------------------------------------------------------

local function purchaseEgg(player: Player, eggId: any, requestedCount: any): (string, { EggLogic.Grant }?)
	if not isValidId(eggId) then
		return Codes.InvalidRequest, nil
	end
	local egg = EggConfig.Eggs[eggId]
	if not egg then
		return Codes.InvalidRequest, nil
	end
	if disabledReason or egg.Enabled == false then
		return Codes.Unavailable, nil
	end

	local profile = PlayerDataService.get(player)
	if not profile or not PlayerDataService.isPetDataReady(profile) then
		return Codes.NotReady, nil
	end
	if not isNearStand(player, eggId) then
		return Codes.TooFar, nil
	end

	local count = MonetizationLogic.hatchCount(profile.Passes, requestedCount)
	local rolls = {}
	for index = 1, count do
		rolls[index] = rollFor(profile)
	end
	local code, grants = EggLogic.purchaseMany(profile, egg, rolls, limitsOf(profile), Codes)
	if code == Codes.Success and grants then
		table.sort(grants, function(a, b)
			return PetMath.getPetMultiplier(a.PetId) > PetMath.getPetMultiplier(b.PetId)
		end)
		applyPetChange(player)
		for _ in grants do
			GameEvents.fire("EggOpened", player, eggId)
		end
	end
	return code, grants
end

function PetService.grantFreePet(player: Player): (string, EggLogic.Grant?, string?)
	local profile = PlayerDataService.get(player)
	if not profile or not PlayerDataService.isPetDataReady(profile) then
		return Codes.NotReady, nil, nil
	end
	local limits = limitsOf(profile)
	local eggId = EggLogic.bestEgg(profile, EggConfig, limits, Codes)
	local egg = eggId and EggConfig.Eggs[eggId]
	if not egg then
		return Codes.Unavailable, nil, nil
	end
	local code, grant = EggLogic.grantFree(profile, egg, rollFor(profile), limits, Codes)
	if code == Codes.Success then
		applyPetChange(player)
	end
	return code, grant, eggId
end

-- Mascota exclusiva comprada con Robux (la concede ShopService al procesar la compra).
function PetService.grantPet(player: Player, petId: string): (string, EggLogic.Grant?)
	local profile = PlayerDataService.get(player)
	if not profile or not PlayerDataService.isPetDataReady(profile) then
		return Codes.NotReady, nil
	end
	if not PetConfig.Pets[petId] then
		return Codes.InvalidRequest, nil
	end
	local grant = EggLogic.grantPet(profile.PetData, petId, maxEquippedOf(profile))
	applyPetChange(player)
	return Codes.Success, grant
end

-- Huevo guardado en el inventario (lo soltó un jefe; ItemService lo quita si sale bien): sin
-- coste ni requisitos de zona o nivel, pero con sitio en el inventario de mascotas.
function PetService.openStoredEgg(player: Player, eggId: string): (string, EggLogic.Grant?)
	local egg = EggConfig.Eggs[eggId]
	if not egg or disabledReason then
		return if egg then Codes.Unavailable else Codes.InvalidRequest, nil
	end
	local profile = PlayerDataService.get(player)
	if not profile or not PlayerDataService.isPetDataReady(profile) then
		return Codes.NotReady, nil
	end
	local limits = limitsOf(profile)
	if #profile.PetData.Pets >= limits.MaxInventory then
		return Codes.InventoryFull, nil
	end
	local grant = EggLogic.grantPet(profile.PetData, EggLogic.roll(egg, rollFor(profile)), limits.MaxEquipped)
	applyPetChange(player)
	GameEvents.fire("EggOpened", player, eggId)
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
	disabledReason = EggLogic.validate(PetConfig, EggConfig)
	if disabledReason then
		warn("[PetService] Configuración de mascotas no válida; huevos desactivados: " .. disabledReason)
	end

	local eggResult = RemoteService.get(Constants.Remotes.EggResult)
	local actionResult = RemoteService.get(Constants.Remotes.PetActionResult)

	RemoteService.get(Constants.Remotes.PurchaseEgg).OnServerEvent:Connect(function(player: Player, eggId: any, requestId: any, count: any)
		local rate = eggLimiter:check(player)
		if rate == "flood" then
			return
		end
		local safeEggId = if isValidId(eggId) then eggId else nil
		local safeRequestId = if isValidId(requestId) then requestId else nil

		local ledger = ledgers[player]
		if not ledger then
			ledger = EggLogic.newLedger(LEDGER_CAPACITY)
			ledgers[player] = ledger
		end
		local previous = if safeRequestId then ledger:get(safeRequestId) else nil
		if previous then
			eggResult:FireClient(player, table.unpack(previous, 1, 8))
			return
		end

		if rate == "cooldown" then
			eggResult:FireClient(player, false, Codes.TooFast, safeEggId, nil, nil, nil, safeRequestId)
			return
		end

		local code, grants = purchaseEgg(player, eggId, count)
		local grant = grants and grants[1]
		local extras = nil
		if grants and #grants > 1 then
			extras = {}
			for index = 2, #grants do
				table.insert(extras, { PetId = grants[index].PetId, Uid = grants[index].Uid, AutoEquipped = grants[index].AutoEquipped })
			end
		end
		local result = {
			code == Codes.Success,
			code,
			safeEggId,
			if grant then grant.PetId else nil,
			if grant then grant.Uid else nil,
			if grant then grant.AutoEquipped else nil,
			safeRequestId,
			extras,
		}
		if safeRequestId and code == Codes.Success then
			ledger:put(safeRequestId, result)
		end
		eggResult:FireClient(player, table.unpack(result, 1, 8))
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
		eggLimiter:remove(player)
		ledgers[player] = nil
		equipLimiter:remove(player)
		syncLimiter:remove(player)
	end)
end

return PetService
