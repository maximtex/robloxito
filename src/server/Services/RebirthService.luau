-- Renacimiento (Rebirth). Todo se decide aquí; el cliente solo pide.
-- - Renacer (remote Rebirth): datos listos y RebirthLogic.canRebirth (mientras
--   RebirthConfig.Enabled sea false responde ComingSoon: el requisito nuevo llega en la fase
--   2 del rediseño). En el mismo paso: +1 renacimiento, fichas, dinero al inicial (los 💎 se
--   quedan) y las armas a nivel 0. Las armas (y la equipada), mascotas, núcleos, zonas, jefes
--   derrotados, mejoras de la Armería y misiones se quedan.
--   Se guarda en seguida (no se pierde un renacimiento por un cierre).
-- - Tienda (remote RebirthShop): sube una ventaja pagando fichas (RebirthLogic.buy).
-- - Estado al cliente por atributos (PlayerDataService.replicate): Rebirths,
--   RebirthTokens, RebirthShop y MaxEquipped.
-- - Social: columna "Renacimientos" en la lista de jugadores (leaderstats), etiqueta
--   "🔄 II" sobre la cabeza y aviso a todos cuando alguien renace (RebirthEvent).
-- Los multiplicadores (botín, daño, mascotas) los aplican EnemyService, CombatService,
-- AbilityService, PetCombatService y PetService con RebirthLogic.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local RebirthLogic = require(Shared.RebirthLogic)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local PetService = require(script.Parent.PetService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local Codes = Constants.PurchaseCodes
local Attributes = Constants.Attributes
local MAX_ID_LENGTH = 64
local LEADERSTAT_NAME = "Renacimientos"
local TAG_NAME = "RebirthTag"

local RebirthService = {}

local rebirthLimiter = RateLimiter.new(RebirthConfig.RebirthCooldown, 10, 4)
local shopLimiter = RateLimiter.new(RebirthConfig.ShopCooldown, 3, 10)
local rebirthListeners: { (Player, number) -> () } = {}

-- Avisos de renacimiento (para otros servicios). Se llaman después de aplicarlo.
function RebirthService.onRebirth(listener: (Player, number) -> ())
	table.insert(rebirthListeners, listener)
end

local function readyProfile(player: Player): PlayerDataService.Profile?
	local profile = PlayerDataService.get(player)
	if profile and PlayerDataService.isPetDataReady(profile) then
		return profile
	end
	return nil
end

-- Acciones -----------------------------------------------------------------------------------

function RebirthService.rebirth(player: Player): (string, any)
	local profile = readyProfile(player)
	if not profile then
		return Codes.NotReady, nil
	end
	local data = profile.PetData.Rebirth
	local code, result = RebirthLogic.rebirth(data, os.time())
	if code ~= "Success" then
		return Codes[code] or Codes.InvalidRequest, nil
	end
	-- Reinicio en el mismo paso (sin pausas: nadie gana ni gasta entre medias): dinero y el
	-- nivel de cada arma. Se conservan los 💎 (y las habilidades compradas), las armas (y la
	-- equipada), las mascotas, las zonas, los jefes derrotados, las mejoras de la Armería y
	-- los núcleos.
	profile.Money = EconomyConfig.StartingMoney
	for weaponId in profile.PetData.Weapons.Levels do
		profile.PetData.Weapons.Levels[weaponId] = 0
	end
	PlayerDataService.refreshStats(player)
	PlayerDataService.replicate(player)
	PlayerDataService.markDirty(player)
	PlayerDataService.saveNow(player)
	PetService.pushInventory(player) -- huevos desbloqueados y espacios al día en el panel
	for _, listener in rebirthListeners do
		task.spawn(listener, player, result.Count)
	end
	RemoteService.get(Constants.Remotes.RebirthEvent):FireAllClients(player.UserId, player.DisplayName, result.Count)
	return Codes.Success, result
end

function RebirthService.buy(player: Player, itemId: any): (string, any)
	if typeof(itemId) ~= "string" or #itemId == 0 or #itemId > MAX_ID_LENGTH then
		return Codes.InvalidRequest, nil
	end
	local profile = readyProfile(player)
	if not profile then
		return Codes.NotReady, nil
	end
	local code, cost = RebirthLogic.buy(profile.PetData.Rebirth, itemId)
	if code ~= "Success" then
		return Codes[code] or Codes.InvalidRequest, { ItemId = itemId, Cost = cost }
	end
	PlayerDataService.refreshStats(player)
	PlayerDataService.replicate(player)
	PlayerDataService.markDirty(player)
	PlayerDataService.saveNow(player)
	if itemId == "PetSlot" then
		PetService.pushInventory(player)
	end
	return Codes.Success, { ItemId = itemId, Level = RebirthLogic.shopLevel(profile.PetData.Rebirth, itemId), Cost = cost }
end

-- Social ------------------------------------------------------------------------------------

local function rebirthCount(player: Player): number
	local value = player:GetAttribute(Attributes.Rebirths)
	return if typeof(value) == "number" then value else 0
end

local function updateLeaderstat(player: Player)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	local value = stats:FindFirstChild(LEADERSTAT_NAME) :: IntValue?
	if not value then
		local created = Instance.new("IntValue")
		created.Name = LEADERSTAT_NAME
		created.Parent = stats
		value = created
	end
	(value :: IntValue).Value = rebirthCount(player)
end

-- Etiqueta "🔄 II" sobre la cabeza (solo con algún renacimiento), visible para todos.
local function updateTag(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local count = rebirthCount(player)
	local tag = head:FindFirstChild(TAG_NAME) :: BillboardGui?
	if count <= 0 then
		if tag then
			tag:Destroy()
		end
		return
	end
	if not tag then
		local gui = Instance.new("BillboardGui")
		gui.Name = TAG_NAME
		gui.Size = UDim2.fromOffset(110, 26)
		gui.StudsOffset = Vector3.new(0, 3.1, 0)
		gui.MaxDistance = 70
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextStrokeTransparency = 0.25
		label.TextStrokeColor3 = Color3.fromRGB(40, 28, 10)
		label.Parent = gui
		gui.Parent = head
		tag = gui
	end
	local tier = RebirthLogic.haloTier(count)
	local label = (tag :: BillboardGui):FindFirstChild("Label") :: TextLabel
	label.Text = "🔄 " .. RebirthLogic.numeral(count)
	label.TextColor3 = RebirthConfig.Colors.Halo[math.max(1, tier)]
end

local function watchPlayer(player: Player)
	updateLeaderstat(player)
	player:GetAttributeChangedSignal(Attributes.Rebirths):Connect(function()
		updateLeaderstat(player)
		updateTag(player)
	end)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 10)
		updateTag(player)
	end)
	if player.Character then
		task.spawn(updateTag, player)
	end
end

-- Arranque ----------------------------------------------------------------------------------

function RebirthService.start()
	local ok, problems = RebirthLogic.validateConfig()
	if not ok then
		warn("[RebirthService] RebirthConfig con problemas: " .. table.concat(problems, "; "))
	end

	local rebirthRemote = RemoteService.get(Constants.Remotes.Rebirth)
	local shopRemote = RemoteService.get(Constants.Remotes.RebirthShop)
	local resultRemote = RemoteService.get(Constants.Remotes.RebirthResult)
	RemoteService.get(Constants.Remotes.RebirthEvent) -- se crea ya para que el cliente lo encuentre

	rebirthRemote.OnServerEvent:Connect(function(player: Player)
		local rate = rebirthLimiter:check(player)
		if rate == "flood" then
			return
		elseif rate == "cooldown" then
			resultRemote:FireClient(player, false, Codes.TooFast, "Rebirth", nil)
			return
		end
		local code, detail = RebirthService.rebirth(player)
		resultRemote:FireClient(player, code == Codes.Success, code, "Rebirth", detail)
	end)

	shopRemote.OnServerEvent:Connect(function(player: Player, itemId: any)
		local rate = shopLimiter:check(player)
		if rate == "flood" then
			return
		elseif rate == "cooldown" then
			resultRemote:FireClient(player, false, Codes.TooFast, "Shop", nil)
			return
		end
		local code, detail = RebirthService.buy(player, itemId)
		resultRemote:FireClient(player, code == Codes.Success, code, "Shop", detail)
	end)

	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		rebirthLimiter:remove(player)
		shopLimiter:remove(player)
	end)
end

return RebirthService
