-- Huevos y mascotas. Todo se decide en el servidor:
-- - Comprar/abrir huevo: tipo de argumento, huevo existente y activo, datos listos,
--   distancia al santuario, nivel requerido, inventario con espacio, saldo y límite de
--   frecuencia. La mascota se sortea aquí con las probabilidades de EggConfig
--   (lógica pura en Util/EggLogic).
-- - Cada compra lleva un requestId: el resultado se decide UNA vez y se recuerda, de modo
--   que un reenvío devuelve lo mismo sin volver a cobrar ni a sortear.
-- - Equipar/desequipar: la mascota debe pertenecer al jugador y respetar MaxEquipped.
-- El cliente solo pide; nunca envía mascotas, rarezas ni multiplicadores.

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
	-- StandOffset es relativo al centro de la zona del huevo (por defecto, el bosque).
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
	-- Distancia en horizontal; la altura del personaje no cuenta.
	return Vector2.new(offset.X, offset.Z).Magnitude <= EggConfig.MaxPurchaseDistance
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
		MaxEquipped = PetConfig.MaxEquipped,
		MaxInventory = PetConfig.MaxInventory,
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

local function purchaseEgg(player: Player, eggId: any): (string, EggLogic.Grant?)
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

	local code, grant = EggLogic.purchase(profile, egg, random:NextNumber(0, 100), {
		MaxInventory = PetConfig.MaxInventory,
		MaxEquipped = PetConfig.MaxEquipped,
		UnlockUpgradeId = EggConfig.UnlockUpgradeId,
	}, Codes)
	if code == Codes.Success then
		applyPetChange(player)
	end
	return code, grant
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
		if #petData.Equipped >= PetConfig.MaxEquipped then
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

function PetService.start()
	disabledReason = EggLogic.validate(PetConfig, EggConfig)
	if disabledReason then
		warn("[PetService] Configuración de mascotas no válida; huevos desactivados: " .. disabledReason)
	end

	local eggResult = RemoteService.get(Constants.Remotes.EggResult)
	local actionResult = RemoteService.get(Constants.Remotes.PetActionResult)

	RemoteService.get(Constants.Remotes.PurchaseEgg).OnServerEvent:Connect(function(player: Player, eggId: any, requestId: any)
		local rate = eggLimiter:check(player)
		if rate == "flood" then
			return
		end
		local safeEggId = if isValidId(eggId) then eggId else nil
		local safeRequestId = if isValidId(requestId) then requestId else nil

		-- Reenvío de una compra ya resuelta: devolver el mismo resultado, sin cobrar.
		local ledger = ledgers[player]
		if not ledger then
			ledger = EggLogic.newLedger(LEDGER_CAPACITY)
			ledgers[player] = ledger
		end
		local previous = if safeRequestId then ledger:get(safeRequestId) else nil
		if previous then
			eggResult:FireClient(player, table.unpack(previous, 1, 7))
			return
		end

		if rate == "cooldown" then
			eggResult:FireClient(player, false, Codes.TooFast, safeEggId, nil, nil, nil, safeRequestId)
			return
		end

		local code, grant = purchaseEgg(player, eggId)
		local result = {
			code == Codes.Success,
			code,
			safeEggId,
			if grant then grant.PetId else nil,
			if grant then grant.Uid else nil,
			if grant then grant.AutoEquipped else nil,
			safeRequestId,
		}
		-- Solo se recuerdan las compras realizadas; un rechazo puede reintentarse.
		if safeRequestId and code == Codes.Success then
			ledger:put(safeRequestId, result)
		end
		eggResult:FireClient(player, table.unpack(result, 1, 7))
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
