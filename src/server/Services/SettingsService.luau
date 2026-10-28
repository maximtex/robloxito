-- Ajustes del jugador (⚙️ Ajustes en el cliente). Por ahora solo el tamaño de la interfaz:
-- el cliente lo aplica al momento y lo manda aquí para que se guarde con la partida
-- (profile.PetData.Settings; SettingsLogic lo valida). PlayerDataService.replicate lo
-- devuelve en el atributo HudScale, así que al volver a entrar sale como lo dejaste.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local SettingsLogic = require(Shared.SettingsLogic)
local RemoteService = require(script.Parent.RemoteService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local SettingsService = {}

-- Pulsar − / + seguido es normal: hasta 10 cambios en 3 s.
local limiter = RateLimiter.new(0.1, 3, 10)

function SettingsService.start()
	RemoteService.get(Constants.Remotes.SetSetting).OnServerEvent:Connect(function(player: Player, key: any, value: any)
		if key ~= "HudScale" or limiter:check(player) ~= "ok" then
			return
		end
		local profile = PlayerDataService.get(player)
		-- Con los datos aún cargando se ignora (la carga lo pisaría); el cliente lo vuelve a
		-- aplicar con lo que diga el atributo.
		if not (profile and PlayerDataService.isPetDataReady(profile)) then
			return
		end
		local scale = SettingsLogic.sanitizeHudScale(value)
		local settings = SettingsLogic.sanitize(profile.PetData.Settings)
		if settings.HudScale ~= scale then
			settings.HudScale = scale
			profile.PetData.Settings = settings
			PlayerDataService.markDirty(player)
		end
		player:SetAttribute(Constants.Attributes.HudScale, scale)
	end)
	Players.PlayerRemoving:Connect(function(player)
		limiter:remove(player)
	end)
end

return SettingsService
