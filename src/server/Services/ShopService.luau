-- Tienda: pases (game passes) y compras sueltas de 💎 (developer products). Lo cobra
-- Roblox y lo concede este servicio; el cliente solo abre la ventana de compra de Roblox.
-- - Pases: al entrar se consulta a Roblox cuáles tiene (UserOwnsGamePassAsync) y se guardan
--   en el perfil (profile.Passes, no en el DataStore: Roblox es la fuente de verdad). Al
--   comprar uno en la partida (PromptGamePassPurchaseFinished) se aplica en el acto.
--   Efectos: Energía ×2 (PlayerDataService), Más mascotas y Abrir ×3 (PetService) y la
--   mejora automática (bucle de este servicio, con su interruptor guardado en Shop).
-- - Compras sueltas (ProcessReceipt): se conceden los 💎 o la mascota exclusiva
--   (PetProducts) UNA vez por compra (el PurchaseId se recuerda en el registro) y solo se
--   confirma a Roblox cuando la compra quedó guardada; si no se puede guardar, Roblox lo
--   reintenta más tarde.
-- - En Studio, DevConfig.StudioPasses = true da todos los pases (para probar).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local MonetizationLogic = require(Shared.MonetizationLogic)
local QuestConfig = require(Shared.Config.QuestConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local UpgradeService = require(script.Parent.UpgradeService)
local PetService = require(script.Parent.PetService)
local WeaponService = require(script.Parent.WeaponService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local DevConfig = require(script.Parent.Parent.DevConfig)

local Codes = Constants.PurchaseCodes
local CHECK_ATTEMPTS = 3
local PROFILE_WAIT = 30 -- segundos esperando al perfil del jugador (debería existir ya)
local AUTO_UPGRADE_ID = "GeneratorPower" -- la Resonancia del Cristal

local ShopService = {}

local actionLimiter = RateLimiter.new(0.5, 5, 10)
local resultRemote: any

local function studioPasses(): boolean
	return DevConfig.StudioPasses == true and RunService:IsStudio()
end

local function notify(player: Player, kind: string, key: string?, detail: any)
	if resultRemote and player.Parent then
		resultRemote:FireClient(player, kind, key, detail)
	end
end

-- Aplica los pases: producción, espacios de mascotas, inventario y atributos.
local function apply(player: Player)
	local profile = PlayerDataService.get(player)
	if not profile then
		return
	end
	PlayerDataService.recalculateProduction(player)
	PlayerDataService.replicate(player)
	if PlayerDataService.isPetDataReady(profile) then
		PetService.enforceEquipLimit(player)
		PetService.pushInventory(player)
	end
end
ShopService.apply = apply

local function ownsOnRoblox(player: Player, passId: number): boolean
	for attempt = 1, CHECK_ATTEMPTS do
		local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
		if ok then
			return result == true
		end
		if attempt < CHECK_ATTEMPTS then
			task.wait(1)
		end
	end
	warn(("[ShopService] No se pudo comprobar el pase %d de %s; se volverá a mirar si lo compra."):format(passId, player.Name))
	return false
end

-- Consulta los pases del jugador y los aplica.
local function checkPasses(player: Player)
	local owned: MonetizationLogic.Passes = {}
	for key, def in MonetizationConfig.GamePasses do
		if studioPasses() then
			owned[key] = true
		elseif type(def.Id) == "number" and def.Id > 0 then
			owned[key] = ownsOnRoblox(player, def.Id) or nil
		end
	end
	local deadline = os.clock() + PROFILE_WAIT
	local profile = PlayerDataService.get(player)
	while not profile and player.Parent and os.clock() < deadline do
		task.wait(0.25)
		profile = PlayerDataService.get(player)
	end
	if not profile then
		return
	end
	-- Lo comprado durante la consulta (PromptGamePassPurchaseFinished) se conserva.
	for key in profile.Passes do
		owned[key] = true
	end
	profile.Passes = owned
	profile.PassesChecked = true
	apply(player)
end

-- Compras sueltas -----------------------------------------------------------------------------

-- Concede una compra suelta (💎, una mascota exclusiva o un arma). Devuelve la
-- decisión para Roblox.
function ShopService.processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local productKey, def = MonetizationLogic.productById(receipt.ProductId)
	local petId = MonetizationLogic.petProductById(receipt.ProductId)
	local weaponId = MonetizationLogic.weaponProductById(receipt.ProductId)
	if not def and not petId and not weaponId then
		warn("[ShopService] Compra de un producto que no está en MonetizationConfig: " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local profile = player and PlayerDataService.get(player)
	if not player or not profile or not PlayerDataService.isPetDataReady(profile) then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox lo reintenta al volver
	end
	local purchaseId = tostring(receipt.PurchaseId)
	local shop = profile.PetData.Shop
	if MonetizationLogic.hasReceipt(shop, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- ya concedida
	end
	if petId then
		if PetService.grantPet(player, petId) ~= Codes.Success then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		MonetizationLogic.addReceipt(shop, purchaseId)
		notify(player, "Pet", petId, nil)
	elseif weaponId then
		if not WeaponService.grantPurchased(player, weaponId) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		MonetizationLogic.addReceipt(shop, purchaseId)
	else
		local amount = MonetizationLogic.productEnergy(def, profile.ProductionPerSecond)
		profile.Energy += amount
		MonetizationLogic.addReceipt(shop, purchaseId)
		PlayerDataService.replicate(player)
		notify(player, "Product", productKey, amount)
	end
	PlayerDataService.markDirty(player)
	if profile.DataState ~= "Loaded" then
		-- Sin DataStore (Studio): no hay dónde guardar; se concede igualmente.
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- Solo se confirma con la compra guardada. Si falla, Roblox la reintenta y el PurchaseId
	-- (ya en memoria) evita concederla dos veces en esta sesión.
	if PlayerDataService.saveAndWait(player) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Mejora automática ---------------------------------------------------------------------------

local function autoUpgradeTick()
	for _, player in Players:GetPlayers() do
		local profile = PlayerDataService.get(player)
		if profile and MonetizationLogic.owns(profile.Passes, "AutoUpgrade") and profile.DataState ~= "Loading" then
			local shop = profile.PetData.Shop
			if type(shop) == "table" and shop.AutoUpgrade then
				for _ = 1, MonetizationConfig.AutoUpgradeMaxPerTick do
					if UpgradeService.purchase(player, AUTO_UPGRADE_ID) ~= Codes.Success then
						break
					end
				end
			end
		end
	end
end

-- Arranque ------------------------------------------------------------------------------------

function ShopService.start()
	resultRemote = RemoteService.get(Constants.Remotes.ShopResult)
	local actionRemote = RemoteService.get(Constants.Remotes.ShopAction)
	PlayerDataService.expectPasses()

	-- Interruptor de la mejora automática.
	actionRemote.OnServerEvent:Connect(function(player: Player, action: any, value: any)
		if actionLimiter:check(player) ~= "ok" then
			return
		end
		if action == "SetAuto" and typeof(value) == "boolean" then
			local profile = PlayerDataService.get(player)
			if not profile or not PlayerDataService.isPetDataReady(profile) then
				return
			end
			profile.PetData.Shop.AutoUpgrade = value
			PlayerDataService.markDirty(player)
			PlayerDataService.replicate(player)
			notify(player, "Auto", nil, value)
		end
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		if not purchased then
			return
		end
		local key = MonetizationLogic.passById(passId)
		local profile = PlayerDataService.get(player)
		if key and profile then
			profile.Passes[key] = true
			apply(player)
			notify(player, "Pass", key, nil)
		end
	end)

	MarketplaceService.ProcessReceipt = ShopService.processReceipt

	-- Al cargar los datos, se quitan las mascotas equipadas de más (si ya se saben los pases).
	PlayerDataService.onPetDataReady(function(player: Player)
		local profile = PlayerDataService.get(player)
		if profile and profile.PassesChecked then
			apply(player)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(checkPasses, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(checkPasses, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		actionLimiter:remove(player)
	end)

	task.spawn(function()
		while true do
			task.wait(MonetizationConfig.AutoUpgradeInterval)
			autoUpgradeTick()
		end
	end)
end

return ShopService
