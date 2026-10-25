-- Artículos del inventario (🎒 Inventario, InventoryController). Todo lo decide el servidor:
-- - Botín de los jefes: a cada jugador que recibe parte de la recompensa de un jefe, sus
--   pociones y, a veces, un huevo (ItemConfig.BossDrops).
-- - Pociones: tomar una (ItemAction "UsePotion") y quitarla al acabarse. Mientras dura, la
--   aplican PlayerDataService (energía y daño mostrado), EnemyService (daño y dinero) y
--   PetService (suerte de los huevos), leyendo ItemLogic.
-- - Huevos guardados: abrirlos ("OpenEgg") con PetService.openStoredEgg.
-- - Títulos: se conceden al cumplir su logro (se comprueba cada pocos segundos) y el
--   equipado ("EquipTitle") se ve encima de la cabeza del jugador para todos.
-- El estado viaja al cliente con ItemState (al pedirlo y al cambiar algo).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ItemConfig = require(Shared.Config.ItemConfig)
local EggConfig = require(Shared.Config.EggConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local ItemLogic = require(Shared.ItemLogic)
local RebirthLogic = require(Shared.RebirthLogic)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local EnemyService = require(script.Parent.EnemyService)
local PetService = require(script.Parent.PetService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local Codes = Constants.PurchaseCodes
local MAX_ID_LENGTH = 64
local TICK_SECONDS = 1
local TITLE_CHECK_SECONDS = 5
local BILLBOARD_NAME = "TituloJugador"

local ItemService = {}

local random = Random.new()
local actionLimiter = RateLimiter.new(0.25, 3, 10)
local syncLimiter = RateLimiter.new(1, 5, 4)
local stateRemote: RemoteEvent
local resultRemote: RemoteEvent

local function isValidId(value: any): boolean
	return typeof(value) == "string" and #value <= MAX_ID_LENGTH
end

-- Artículos de un perfil con los datos listos (nil si aún cargan).
local function readyItems(player: Player): (any?, ItemLogic.ItemData?)
	local profile = PlayerDataService.get(player)
	if not profile or not PlayerDataService.isPetDataReady(profile) then
		return nil, nil
	end
	local data = profile.PetData
	if type(data.Items) ~= "table" then
		data.Items = ItemLogic.empty()
	end
	return profile, data.Items
end

-- Estadísticas para los títulos (ItemConfig.Titles: Stat).
function ItemService.statsOf(profile: any): ItemLogic.Stats
	local data = profile.PetData
	local quests = data.Quests
	local stats = if type(quests) == "table" and type(quests.Stats) == "table" then quests.Stats else {}
	local items = ItemLogic.ofProfile(profile)
	return {
		Kills = if type(stats.Kills) == "number" then stats.Kills else 0,
		EnergyEarned = if type(stats.EnergyEarned) == "number" then stats.EnergyEarned else 0,
		Rebirths = RebirthLogic.count(data.Rebirth),
		Pets = #data.Pets,
		PotionsUsed = if items then items.PotionsUsed else 0,
		Bosses = data.Bosses or {},
	}
end

local function buildState(player: Player): any
	local profile, items = readyItems(player)
	if not profile or not items then
		return { Ready = false }
	end
	local now = os.time()
	local boosts = {}
	for potionId in items.Boosts do
		local left = ItemLogic.remaining(items, potionId, now)
		if left > 0 then
			boosts[potionId] = left
		end
	end
	local stats = ItemService.statsOf(profile)
	local progress = {}
	for _, titleId in ItemLogic.titleOrder() do
		if not items.Titles[titleId] then
			local value, goal = ItemLogic.titleProgress(ItemConfig.Titles[titleId], stats)
			progress[titleId] = { math.floor(value), goal }
		end
	end
	return {
		Ready = true,
		Potions = table.clone(items.Potions),
		Eggs = table.clone(items.Eggs),
		Boosts = boosts,
		Titles = table.clone(items.Titles),
		Title = items.Title,
		Progress = progress,
	}
end

function ItemService.push(player: Player)
	if player.Parent then
		stateRemote:FireClient(player, buildState(player))
	end
end

-- Título encima de la cabeza ---------------------------------------------------------------

local function applyBillboard(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local existing = head:FindFirstChild(BILLBOARD_NAME)
	local profile = PlayerDataService.get(player)
	local items = profile and ItemLogic.ofProfile(profile)
	local def = items and items.Title ~= "" and ItemConfig.Titles[items.Title]
	if not def then
		if existing then
			existing:Destroy()
		end
		return
	end
	local billboard = existing :: BillboardGui?
	if not billboard then
		local gui = Instance.new("BillboardGui")
		gui.Name = BILLBOARD_NAME
		gui.Size = UDim2.fromOffset(220, 30)
		gui.StudsOffset = Vector3.new(0, 3.2, 0)
		gui.MaxDistance = 90
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		gui.ResetOnSpawn = false
		local label = Instance.new("TextLabel")
		label.Name = "Texto"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(16, 14, 18)
		stroke.Parent = label
		label.Parent = gui
		gui.Parent = head
		billboard = gui
	end
	local label = (billboard :: BillboardGui):FindFirstChild("Texto") :: TextLabel
	label.Text = "« " .. def.DisplayName .. " »"
	label.TextColor3 = def.Color
end

-- Títulos: concede los que ya se cumplen y avisa.
local function checkTitles(player: Player)
	local profile, items = readyItems(player)
	if not profile or not items then
		return
	end
	local before = items.Title
	local fresh = ItemLogic.grantTitles(items, ItemService.statsOf(profile))
	if #fresh == 0 then
		return
	end
	PlayerDataService.markDirty(player)
	if items.Title ~= before then
		applyBillboard(player)
	end
	for _, titleId in fresh do
		resultRemote:FireClient(player, true, Codes.Success, "Title", titleId)
	end
	ItemService.push(player)
end

-- Botín de los jefes ------------------------------------------------------------------------

local function onDefeated(player: Player, info: { TypeId: string, Kind: string })
	if info.Kind ~= "Boss" then
		return
	end
	local _, items = readyItems(player)
	if not items then
		return
	end
	local drop = ItemLogic.rollBossDrop(info.TypeId, function()
		return random:NextNumber()
	end, EggConfig.Eggs)
	local gotPotions = {}
	for _, potionId in drop.Potions do
		if ItemLogic.addPotion(items, potionId, 1) > 0 then
			table.insert(gotPotions, potionId)
		end
	end
	local gotEgg = if drop.Egg and ItemLogic.addEgg(items, drop.Egg, 1) > 0 then drop.Egg else nil
	if #gotPotions == 0 and not gotEgg then
		return
	end
	PlayerDataService.markDirty(player)
	local def = EnemyConfig.Types[info.TypeId]
	resultRemote:FireClient(player, true, Codes.Success, "Drop", {
		Boss = if def then def.DisplayName else info.TypeId,
		Potions = gotPotions,
		Egg = gotEgg,
	})
	ItemService.push(player)
	task.defer(checkTitles, player) -- el jefe puede dar su título
end

-- Acciones del jugador ----------------------------------------------------------------------

local function usePotion(player: Player, potionId: any): (string, any?)
	if not isValidId(potionId) then
		return Codes.InvalidRequest, nil
	end
	local profile, items = readyItems(player)
	if not profile or not items then
		return Codes.NotReady, nil
	end
	local code, seconds = ItemLogic.usePotion(items, potionId, os.time(), Codes)
	if code ~= Codes.Success then
		return code, nil
	end
	PlayerDataService.recalculateProduction(player) -- energía
	PlayerDataService.replicate(player) -- daño mostrado
	PlayerDataService.markDirty(player)
	return code, { PotionId = potionId, Seconds = seconds }
end

local function openEgg(player: Player, eggId: any): (string, any?)
	if not isValidId(eggId) or not EggConfig.Eggs[eggId] then
		return Codes.InvalidRequest, nil
	end
	local _, items = readyItems(player)
	if not items then
		return Codes.NotReady, nil
	end
	if not ItemLogic.hasEgg(items, eggId) then
		return Codes.NotOwned, nil
	end
	local code, grant = PetService.openStoredEgg(player, eggId)
	if code ~= Codes.Success or not grant then
		return code, nil
	end
	ItemLogic.takeEgg(items, eggId)
	PlayerDataService.markDirty(player)
	PlayerDataService.saveNow(player) -- mascota nueva: se guarda ya
	return code, { EggId = eggId, PetId = grant.PetId, Uid = grant.Uid, AutoEquipped = grant.AutoEquipped }
end

local function equipTitle(player: Player, titleId: any): (string, any?)
	if typeof(titleId) ~= "string" or #titleId > MAX_ID_LENGTH then
		return Codes.InvalidRequest, nil
	end
	local _, items = readyItems(player)
	if not items then
		return Codes.NotReady, nil
	end
	local code = ItemLogic.equipTitle(items, titleId, Codes)
	if code == Codes.Success then
		PlayerDataService.markDirty(player)
		applyBillboard(player)
	end
	return code, { TitleId = titleId }
end

local ACTIONS = {
	UsePotion = usePotion,
	OpenEgg = openEgg,
	EquipTitle = equipTitle,
}

-- Pociones que se acaban ----------------------------------------------------------------------

local function tick()
	local now = os.time()
	for player, profile in PlayerDataService.getAll() do
		local items = ItemLogic.ofProfile(profile)
		if items and next(items.Boosts) ~= nil then
			local ended = ItemLogic.expire(items, now)
			if #ended > 0 then
				PlayerDataService.recalculateProduction(player)
				PlayerDataService.replicate(player)
				for _, potionId in ended do
					resultRemote:FireClient(player, true, Codes.Success, "BoostEnded", potionId)
				end
				ItemService.push(player)
			end
		end
	end
end

function ItemService.start()
	stateRemote = RemoteService.get(Constants.Remotes.ItemState)
	resultRemote = RemoteService.get(Constants.Remotes.ItemResult)

	RemoteService.get(Constants.Remotes.ItemAction).OnServerEvent:Connect(function(player: Player, action: any, arg: any)
		local rate = actionLimiter:check(player)
		if rate == "flood" then
			return
		end
		local handler = typeof(action) == "string" and ACTIONS[action]
		if not handler then
			return
		end
		if rate == "cooldown" then
			resultRemote:FireClient(player, false, Codes.TooFast, action, nil)
			return
		end
		local code, detail = handler(player, arg)
		resultRemote:FireClient(player, code == Codes.Success, code, action, detail)
		ItemService.push(player)
	end)

	RemoteService.get(Constants.Remotes.RequestItems).OnServerEvent:Connect(function(player: Player)
		if syncLimiter:check(player) == "ok" then
			ItemService.push(player)
		end
	end)

	EnemyService.onDefeated(onDefeated)

	PlayerDataService.onPetDataReady(function(player: Player)
		checkTitles(player)
		applyBillboard(player)
		ItemService.push(player)
	end)

	local function watchCharacter(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Head", 10)
			applyBillboard(player)
		end)
		if player.Character then
			task.spawn(applyBillboard, player)
		end
	end
	Players.PlayerAdded:Connect(watchCharacter)
	for _, player in Players:GetPlayers() do
		watchCharacter(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		actionLimiter:remove(player)
		syncLimiter:remove(player)
	end)

	task.spawn(function()
		local sinceTitles = 0
		while true do
			task.wait(TICK_SECONDS)
			tick()
			sinceTitles += TICK_SECONDS
			if sinceTitles >= TITLE_CHECK_SECONDS then
				sinceTitles = 0
				for player in PlayerDataService.getAll() do
					task.spawn(checkTitles, player)
				end
			end
		end
	end)
end

return ItemService
