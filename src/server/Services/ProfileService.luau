-- Personajes (⚙️ Ajustes → Personajes; pruebas con amigos: "cambiar de clase a mitad de
-- partida no tiene gracia"). Cada cuenta tiene hasta 3 personajes, cada uno con su clase fija
-- y su progreso (ProfileLogic; SaveService guarda cada uno en su entrada).
--
-- ProfileAction (cliente -> servidor):
--   ("Create", styleId)  crea un personaje con esa clase y entra con él
--   ("Select", hueco)    entra con otro de sus personajes
-- En los dos casos se guarda la cuenta (con quién entrar) y la partida, y el jugador vuelve a
-- entrar en el juego (TeleportService al mismo lugar; si no se puede, p. ej. en Studio, se le
-- saca con un mensaje para que vuelva a entrar). PlayerDataService carga al entrar el
-- personaje elegido. Respuesta: ProfileResult(success, code, action).
--
-- Lo comprado con Robux en pases es de la cuenta (Roblox lo dice en cada servidor); el resto
-- (💰, 💎, armas, mascotas, zonas, renacimientos) es de cada personaje.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ProfileLogic = require(Shared.ProfileLogic)
local StyleConfig = require(Shared.Config.StyleConfig)
local RemoteService = require(script.Parent.RemoteService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local Codes = Constants.PurchaseCodes

local ProfileService = {}

local REJOIN_MESSAGE = "Vuelve a entrar para jugar con tu otro personaje 🙂"

-- Cambiar de personaje guarda y saca del servidor: una vez cada 3 s como mucho.
local limiter = RateLimiter.new(3, 10, 4)
local busy: { [Player]: boolean } = {}

local function reply(player: Player, success: boolean, code: string, action: string)
	RemoteService.get(Constants.Remotes.ProfileResult):FireClient(player, success, code, action)
end

-- Vuelve a entrar en el juego (otro servidor o el mismo) con el personaje ya elegido.
local function rejoin(player: Player)
	local ok = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player })
	end)
	if not ok and player.Parent then
		player:Kick(REJOIN_MESSAGE)
	end
end

-- Hace el cambio (la cuenta ya dice con quién entrar) y devuelve el código.
local function switch(player: Player, profile: any, undo: () -> ()): string
	profile.Switching = true
	if not PlayerDataService.saveAccount(player) then
		profile.Switching = nil
		undo()
		return Codes.Unavailable
	end
	-- La partida de este personaje (al salir se vuelve a guardar y se suelta el bloqueo)
	PlayerDataService.saveAndWait(player)
	return Codes.Success
end

local function handle(player: Player, action: any, value: any): (string, string)
	local actionName = if action == "Create" or action == "Select" then action else "Unknown"
	local profile = PlayerDataService.get(player)
	if not profile or profile.DataState == "Loading" then
		return Codes.NotReady, actionName
	end
	local account = profile.Account
	if actionName == "Unknown" then
		return Codes.InvalidRequest, actionName
	end
	if profile.DataState ~= "Loaded" or profile.Sandbox or not account then
		return Codes.Unavailable, actionName -- sin datos guardados no hay personajes
	end
	local previousLast = account.Last
	if actionName == "Create" then
		local code, slot = ProfileLogic.create(account, value, os.time(), StyleConfig.Styles)
		if code ~= "Success" or not slot then
			return Codes[code] or code, actionName
		end
		return switch(player, profile, function()
			account.Slots[slot] = nil
			account.Last = previousLast
		end), actionName
	end
	if tonumber(value) == profile.Slot then
		return Codes.AlreadySelected, actionName
	end
	local code = ProfileLogic.select(account, value)
	if code ~= "Success" then
		return Codes[code] or code, actionName
	end
	return switch(player, profile, function()
		account.Last = previousLast
	end), actionName
end

function ProfileService.start()
	RemoteService.get(Constants.Remotes.ProfileAction).OnServerEvent:Connect(function(player: Player, action: any, value: any)
		local rate = limiter:check(player)
		if rate == "flood" then
			return
		elseif rate == "cooldown" or busy[player] then
			reply(player, false, Codes.TooFast, if type(action) == "string" then action else "")
			return
		end
		busy[player] = true
		local ok, code, actionName = pcall(handle, player, action, value)
		if not ok then
			warn("[ProfileService]", code)
			code, actionName = Codes.Unavailable, ""
		end
		reply(player, code == Codes.Success, code, actionName)
		if code == Codes.Success then
			task.wait(0.5) -- que le llegue el aviso de "cambiando de personaje"
			rejoin(player)
		else
			busy[player] = nil
		end
	end)
	-- Si el viaje falla después de empezar, también se le saca para que vuelva a entrar
	TeleportService.TeleportInitFailed:Connect(function(player: Player)
		local profile = PlayerDataService.get(player)
		if profile and (profile :: any).Switching and player.Parent then
			player:Kick(REJOIN_MESSAGE)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		limiter:remove(player)
		busy[player] = nil
	end)
end

return ProfileService
