-- Entorno para RewardService y ShopService REALES sobre la persistencia real (persist_stubs +
-- persist_glue): MarketplaceService simulado (pases, ventana de compra y recibos),
-- Players:GetPlayerByUserId, Enum.ProductPurchaseDecision y un PetService simulado que usa
-- PetLogic real (mascotas de regalo y límite de equipadas con los pases).
-- Devuelve el PetService simulado (se inserta como módulo "PetService").

Enum = Enum or {}
Enum.ProductPurchaseDecision = { PurchaseGranted = "PurchaseGranted", NotProcessedYet = "NotProcessedYet" }

PlayersService.GetPlayerByUserId = function(_, userId)
	for _, player in playersList do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

-- Pases que tiene cada UserId en "Roblox" (Owned[userId][passId] = true) y llamadas que
-- fallan (Fail = N próximas).
local MarketplaceStub = {
	PromptGamePassPurchaseFinished = signal(),
	ProcessReceipt = nil,
	Owned = {},
	Fail = 0,
	Checks = 0,
}
function MarketplaceStub.UserOwnsGamePassAsync(self, userId, passId)
	self.Checks += 1
	if self.Fail > 0 then
		self.Fail -= 1
		error("simulated Marketplace failure")
	end
	local owned = self.Owned[userId]
	return owned ~= nil and owned[passId] == true
end
services.MarketplaceService = MarketplaceStub

local PetServiceStub = { Pushed = 0, Enforced = 0, Market = MarketplaceStub }
local function petLimits(profile)
	return {
		MaxInventory = MonetizationLogic.maxInventory(profile.Passes, PetConfig.MaxInventory),
		MaxEquipped = MonetizationLogic.maxEquipped(profile.PetData.Rebirth, profile.Passes, PetConfig.MaxEquipped),
	}
end
function PetServiceStub.pushInventory()
	PetServiceStub.Pushed += 1
end
function PetServiceStub.grantFreePet(player, petId)
	local profile = PlayerDataService.get(player)
	if not profile or not PlayerDataService.isPetDataReady(profile) then
		return Constants.PurchaseCodes.NotReady, nil
	end
	return PetLogic.grantFree(profile, petId, petLimits(profile), Constants.PurchaseCodes)
end
function PetServiceStub.enforceEquipLimit(player)
	local profile = PlayerDataService.get(player)
	if not profile then
		return
	end
	PetServiceStub.Enforced += 1
	local limit = petLimits(profile).MaxEquipped
	while #profile.PetData.Equipped > limit do
		table.remove(profile.PetData.Equipped)
	end
end

return PetServiceStub
