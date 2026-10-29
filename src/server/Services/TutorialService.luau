-- Tutorial inicial (lógica en TutorialLogic, pasos en TutorialConfig).
-- - Los pasos los marca SOLO el servidor con los datos del perfil (los mismos que las
--   misiones: QuestService.contextOf y las estadísticas guardadas).
-- - Sin bucle propio: se actualiza con el aviso de 💎 de cada segundo y al
--   terminar de cargar los datos.
-- - El cliente solo puede pedir omitirlo (SkipTutorial, con límite de frecuencia).
-- - Estado en el perfil guardado (PetData.Tutorial) y replicado con atributos
--   (TutorialStatus, TutorialStep). Si los datos no se cargan, no hay tutorial.
-- - Premios (TutorialConfig.Steps[i].Reward): lo justo para el paso siguiente (💰 y
--   pociones), al cumplir cada paso; omitir o completarlo por veterano no da nada. Se avisa
--   al cliente con TutorialReward.
-- - Después del tutorial publica el siguiente objetivo (atributo TutorialNext).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local TutorialConfig = require(Shared.Config.TutorialConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local DiamondService = require(script.Parent.DiamondService)
local QuestService = require(script.Parent.QuestService)
local ItemLogic = require(Shared.ItemLogic)
local TutorialLogic = require(script.Parent.Parent.Util.TutorialLogic)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local Attributes = Constants.Attributes

local TutorialService = {}

local skipLimiter = RateLimiter.new(TutorialConfig.SkipRateLimit.Cooldown, TutorialConfig.SkipRateLimit.WindowSeconds, TutorialConfig.SkipRateLimit.MaxPerWindow)

local function readyProfile(player: Player): PlayerDataService.Profile?
	local profile = PlayerDataService.get(player)
	if profile and PlayerDataService.isPetDataReady(profile) then
		return profile
	end
	return nil
end

local function publish(player: Player, data: TutorialLogic.TutorialData, next: string?)
	if player:GetAttribute(Attributes.TutorialStatus) ~= data.Status then
		player:SetAttribute(Attributes.TutorialStatus, data.Status)
	end
	if player:GetAttribute(Attributes.TutorialStep) ~= data.Step then
		player:SetAttribute(Attributes.TutorialStep, data.Step)
	end
	if player:GetAttribute(Attributes.TutorialNext) ~= (next or "") then
		player:SetAttribute(Attributes.TutorialNext, next or "")
	end
end

-- Premio de un paso recién cumplido: 💰 y pociones. Devuelve lo dado (para el aviso) o nil.
local function grant(player: Player, profile: any, index: number): any?
	local reward = TutorialLogic.reward(index)
	if type(reward) ~= "table" then
		return nil
	end
	local given: any = { Step = index }
	local money = reward.Money
	if type(money) == "number" and money == money and money > 0 and money < math.huge then
		profile.Money += math.floor(money)
		given.Money = math.floor(money)
	end
	local items = ItemLogic.ofProfile(profile)
	if type(reward.Potions) == "table" and items then
		for potionId, count in reward.Potions do
			local added = if type(count) == "number" then ItemLogic.addPotion(items, potionId, math.floor(count)) else 0
			if added > 0 then
				given.Potions = given.Potions or {}
				given.Potions[potionId] = added
			end
		end
		if given.Potions then
			GameEvents.fire("ItemsChanged", player) -- el inventario y el botón ❤️ se refrescan
		end
	end
	return if given.Money or given.Potions then given else nil
end

local function update(player: Player)
	local profile = readyProfile(player)
	if not profile then
		return
	end
	local data = profile.PetData.Tutorial
	local ctx = QuestService.contextOf(profile)
	local stats = profile.PetData.Quests.Stats
	local changed, done = TutorialLogic.update(data, ctx, stats)
	if changed then
		local rewarded = false
		for _, index in done do
			local given = grant(player, profile, index)
			if given then
				rewarded = true
				RemoteService.get(Constants.Remotes.TutorialReward):FireClient(player, given)
			end
		end
		PlayerDataService.markDirty(player)
		if rewarded then
			PlayerDataService.replicate(player)
			PlayerDataService.saveNow(player) -- lo regalado no se pierde con una caída
		end
	end
	publish(player, data, TutorialLogic.nextGoal(data, ctx, stats))
end

function TutorialService.start()
	local skipRemote = RemoteService.get(Constants.Remotes.SkipTutorial)

	PlayerDataService.onPetDataReady(update)
	-- Cada segundo (aviso de DiamondService): pasos cumplidos desde el último ciclo.
	DiamondService.onProduced(function(player)
		update(player)
	end)

	skipRemote.OnServerEvent:Connect(function(player: Player)
		if skipLimiter:check(player) ~= "ok" then
			return
		end
		local profile = readyProfile(player)
		if not profile then
			return
		end
		if TutorialLogic.skip(profile.PetData.Tutorial) then
			PlayerDataService.markDirty(player)
		end
		local data = profile.PetData.Tutorial
		publish(player, data, TutorialLogic.nextGoal(data, QuestService.contextOf(profile), profile.PetData.Quests.Stats))
	end)

	Players.PlayerRemoving:Connect(function(player)
		skipLimiter:remove(player)
	end)
end

return TutorialService
