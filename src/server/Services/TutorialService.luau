-- Tutorial inicial (lógica en TutorialLogic, pasos en TutorialConfig).
-- - Los pasos los marca SOLO el servidor con los datos del perfil (los mismos que las
--   misiones: QuestService.contextOf y las estadísticas guardadas).
-- - Sin bucle propio: se actualiza con el aviso de 💎 de cada segundo y al
--   terminar de cargar los datos.
-- - El cliente solo puede pedir omitirlo (SkipTutorial, con límite de frecuencia).
-- - Estado en el perfil guardado (PetData.Tutorial) y replicado con atributos
--   (TutorialStatus, TutorialStep). Si los datos no se cargan, no hay tutorial.
-- - No concede energía ni objetos: esas acciones ya las premian las misiones.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local TutorialConfig = require(Shared.Config.TutorialConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local DiamondService = require(script.Parent.DiamondService)
local QuestService = require(script.Parent.QuestService)
local TutorialLogic = require(script.Parent.Parent.Util.TutorialLogic)
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

local function publish(player: Player, data: TutorialLogic.TutorialData)
	if player:GetAttribute(Attributes.TutorialStatus) ~= data.Status then
		player:SetAttribute(Attributes.TutorialStatus, data.Status)
	end
	if player:GetAttribute(Attributes.TutorialStep) ~= data.Step then
		player:SetAttribute(Attributes.TutorialStep, data.Step)
	end
end

local function update(player: Player)
	local profile = readyProfile(player)
	if not profile then
		return
	end
	local data = profile.PetData.Tutorial
	if TutorialLogic.update(data, QuestService.contextOf(profile), profile.PetData.Quests.Stats) then
		PlayerDataService.markDirty(player)
	end
	publish(player, data)
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
		publish(player, profile.PetData.Tutorial)
	end)

	Players.PlayerRemoving:Connect(function(player)
		skipLimiter:remove(player)
	end)
end

return TutorialService
