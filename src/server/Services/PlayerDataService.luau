-- Estado de cada jugador. Energía, mejoras, mascotas, zonas y misiones se cargan y
-- guardan con SaveService (un único DataStore).
-- Replica valores al cliente mediante atributos del Player, que el cliente
-- no puede modificar en el servidor.
--
-- Carga:
-- - Mientras carga ("Loading") se sigue produciendo energía y cobrando recompensas de
--   enemigos; al terminar se SUMA a la energía guardada (no se pierde ni se duplica).
--   Gastar no es posible durante la carga (mejoras, huevos y zonas exigen datos listos).
-- - Si la carga falla ("Failed") se juega con valores de sesión y NUNCA se guarda: los
--   datos buenos del DataStore no se pisan con valores por defecto.
-- Guardado:
-- - Se guarda si hay cambios marcados (Dirty) o si la energía/mejoras cambiaron desde el
--   último guardado correcto. Si falla, queda pendiente y se avisa al jugador (SaveError).
-- Modo prueba del tutorial (DevConfig.TutorialSandbox, SOLO en Studio):
-- - Perfil temporal nuevo en memoria; no se llama a SaveService.load ni a .save, así que
--   el perfil real no se lee, no se bloquea y no se escribe. Se marca con Sandbox = true
--   y, además de no estar "Loaded", saveProfile lo rechaza explícitamente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local Constants = require(Shared.Constants)
local Economy = require(Shared.Economy)
local PetMath = require(Shared.PetMath)
local SaveService = require(script.Parent.SaveService)
local DevConfig = require(script.Parent.Parent.DevConfig)

local AUTOSAVE_INTERVAL = 90

export type DataState = "Loading" | "Loaded" | "Unavailable" | "Failed"

export type Profile = {
	Energy: number,
	ProductionPerSecond: number,
	UpgradeLevels: { [string]: number },
	PetMultiplier: number,
	PetData: SaveService.PetData,
	DataState: DataState,
	Dirty: boolean,
	SavedEconomy: string?, -- firma de energía y mejoras del último guardado correcto
	SaveError: boolean, -- el último intento de guardado falló (se reintentará)
	Sandbox: boolean, -- perfil temporal del modo prueba: nunca se carga ni se guarda
}

local PlayerDataService = {}

local profiles: { [Player]: Profile } = {}
local readyListeners: { (Player) -> () } = {}

local function createProfile(): Profile
	local upgradeLevels = {}
	for upgradeId in EconomyConfig.Upgrades do
		upgradeLevels[upgradeId] = 0
	end

	return {
		Energy = EconomyConfig.StartingEnergy,
		ProductionPerSecond = Economy.getProductionPerSecond(upgradeLevels),
		UpgradeLevels = upgradeLevels,
		PetMultiplier = 1,
		PetData = SaveService.emptyData(),
		DataState = "Loading",
		Dirty = false,
		SavedEconomy = nil,
		SaveError = false,
		Sandbox = false,
	}
end

function PlayerDataService.get(player: Player): Profile?
	return profiles[player]
end

function PlayerDataService.getAll(): { [Player]: Profile }
	return profiles
end

-- Las mascotas solo se pueden comprar o equipar con los datos cargados (o en modo sin
-- guardado), para que una carga tardía no sobrescriba lo obtenido en la sesión.
function PlayerDataService.isPetDataReady(profile: Profile): boolean
	return profile.DataState == "Loaded" or profile.DataState == "Unavailable"
end

function PlayerDataService.getEquippedPetIds(profile: Profile): { string }
	local byUid: { [string]: string } = {}
	for _, entry in profile.PetData.Pets do
		byUid[entry.Uid] = entry.PetId
	end
	local petIds = {}
	for _, uid in profile.PetData.Equipped do
		local petId = byUid[uid]
		if petId then
			table.insert(petIds, petId)
		end
	end
	return petIds
end

function PlayerDataService.recalculateProduction(player: Player)
	local profile = profiles[player]
	if profile then
		profile.PetMultiplier = PetMath.getTotalMultiplier(PlayerDataService.getEquippedPetIds(profile))
		profile.ProductionPerSecond = Economy.getProductionPerSecond(profile.UpgradeLevels) * profile.PetMultiplier
	end
end

local function setIfChanged(player: Player, name: string, value: any)
	if player:GetAttribute(name) ~= value then
		player:SetAttribute(name, value)
	end
end

function PlayerDataService.replicate(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end

	local attributes = Constants.Attributes
	player:SetAttribute(attributes.Energy, math.floor(profile.Energy))
	setIfChanged(player, attributes.ProductionPerSecond, profile.ProductionPerSecond)
	for upgradeId, level in profile.UpgradeLevels do
		setIfChanged(player, attributes.UpgradeLevelPrefix .. upgradeId, level)
	end
	setIfChanged(player, attributes.PetMultiplier, profile.PetMultiplier)
	setIfChanged(player, attributes.EquippedPets, table.concat(PlayerDataService.getEquippedPetIds(profile), ","))
	setIfChanged(player, attributes.UnlockedZones, table.concat(profile.PetData.UnlockedZones, ","))
	setIfChanged(player, attributes.DataStatus, profile.DataState)
	setIfChanged(player, attributes.SaveError, profile.SaveError)
end

-- Firma de la economía (para saber si hay algo nuevo que guardar).
local function economySignature(profile: Profile): string
	local parts = { ("%.4f"):format(profile.Energy) }
	for upgradeId, level in profile.UpgradeLevels do
		table.insert(parts, upgradeId .. "=" .. level)
	end
	table.sort(parts)
	return table.concat(parts, "|")
end

function PlayerDataService.markDirty(player: Player)
	local profile = profiles[player]
	if profile then
		profile.Dirty = true
	end
end

-- Se llama cuando las mascotas de un jugador están listas (cargadas o sin guardado).
function PlayerDataService.onPetDataReady(callback: (Player) -> ())
	table.insert(readyListeners, callback)
end

local function notifyReady(player: Player)
	for _, callback in readyListeners do
		task.spawn(callback, player)
	end
end

-- Modo prueba: solo con el interruptor activado Y dentro de Roblox Studio.
local function sandboxActive(): boolean
	return DevConfig.TutorialSandbox == true and RunService:IsStudio()
end

local function sandboxEnergy(): number
	local energy = DevConfig.SandboxStartingEnergy
	if type(energy) == "number" and energy == energy and energy >= 0 and energy < 1e15 then
		return energy
	end
	return EconomyConfig.StartingEnergy
end

-- Perfil temporal: datos vacíos (sin mascotas, zonas ni misiones; tutorial activo) y la
-- energía inicial de prueba, que se suma directamente y NO cuenta como generada.
local function startSandbox(player: Player, profile: Profile)
	profile.Sandbox = true
	profile.DataState = "Unavailable" -- se juega con normalidad y nunca se guarda
	profile.PetData = SaveService.emptyData() -- pura: no toca el DataStore
	profile.Energy = sandboxEnergy()
	player:SetAttribute(Constants.Attributes.TestMode, true)
	print(("[PlayerDataService] 🧪 Perfil temporal de prueba creado para %s (UserId %d)."):format(player.Name, player.UserId))
	PlayerDataService.recalculateProduction(player)
	PlayerDataService.replicate(player)
	notifyReady(player)
end

local function loadPetData(player: Player, profile: Profile)
	if sandboxActive() then
		startSandbox(player, profile)
		return
	end
	local status, data = SaveService.load(player.UserId)

	if profiles[player] ~= profile then
		-- El jugador salió durante la carga: liberar el bloqueo sin cambiar nada.
		if status == "Loaded" and data then
			SaveService.save(player.UserId, data, true)
		end
		return
	end

	profile.DataState = status
	if status == "Loaded" and data then
		-- Lo ganado mientras cargaba (producción y enemigos) se suma a lo guardado. Durante la
		-- carga no se puede gastar, así que la diferencia nunca es negativa.
		local gainedWhileLoading = math.max(0, profile.Energy - EconomyConfig.StartingEnergy)
		profile.Energy = data.Energy + gainedWhileLoading
		local levels = {}
		for upgradeId in EconomyConfig.Upgrades do
			levels[upgradeId] = data.UpgradeLevels[upgradeId] or 0
		end
		profile.UpgradeLevels = levels
		profile.PetData = data
	elseif status == "Unavailable" then
		warn("[PlayerDataService] DataStore no disponible: las mascotas no se guardarán en esta sesión. "
			.. "En Studio activa Game Settings > Security > Enable Studio Access to API Services.")
	else
		warn("[PlayerDataService] No se pudieron cargar los datos de " .. player.Name .. "; no se guardará para proteger sus datos.")
	end

	PlayerDataService.recalculateProduction(player)
	PlayerDataService.replicate(player)
	if PlayerDataService.isPetDataReady(profile) then
		notifyReady(player)
	end
end

-- Guardados en curso; BindToClose espera a que terminen todos.
local activeSaves = 0

local function saveProfile(player: Player, profile: Profile, release: boolean)
	if profile.DataState ~= "Loaded" or profile.Sandbox then
		return -- sin datos cargados (o perfil de prueba) nunca se guarda
	end
	activeSaves += 1
	profile.Dirty = false
	-- La economía se copia ahora; lo que cambie durante la espera se guardará la próxima vez.
	local signature = economySignature(profile)
	profile.PetData.Energy = profile.Energy
	profile.PetData.UpgradeLevels = table.clone(profile.UpgradeLevels)
	local ok, saved = pcall(SaveService.save, player.UserId, profile.PetData, release)
	if ok and saved then
		profile.SavedEconomy = signature
		profile.SaveError = false
	else
		if not ok then
			warn("[PlayerDataService] Error al guardar los datos de " .. player.Name .. ": " .. tostring(saved))
		end
		profile.Dirty = true -- se reintenta en el próximo guardado
		profile.SaveError = true
	end
	if profiles[player] == profile then
		PlayerDataService.replicate(player)
	end
	activeSaves -= 1
end

local function needsSave(profile: Profile): boolean
	return profile.DataState == "Loaded" and not profile.Sandbox and (profile.Dirty or economySignature(profile) ~= profile.SavedEconomy)
end

-- Guarda ya (sin esperar al autoguardado) tras un cambio importante, como un desbloqueo.
-- Solo si los datos se cargaron bien; si falla, queda pendiente para el autoguardado.
function PlayerDataService.saveNow(player: Player)
	local profile = profiles[player]
	if profile and profile.DataState == "Loaded" and not profile.Sandbox then
		task.spawn(saveProfile, player, profile, false)
	end
end

local function onPlayerAdded(player: Player)
	if profiles[player] then
		return
	end
	local profile = createProfile()
	profiles[player] = profile
	PlayerDataService.replicate(player)
	task.spawn(loadPetData, player, profile)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	profiles[player] = nil
	if profile then
		saveProfile(player, profile, true)
	end
end

function PlayerDataService.start()
	if DevConfig.TutorialSandbox == true then
		if RunService:IsStudio() then
			warn("[PlayerDataService] 🧪 MODO PRUEBA DEL TUTORIAL activo (DevConfig.TutorialSandbox): perfiles temporales, no se carga ni se guarda nada.")
		else
			warn("[PlayerDataService] DevConfig.TutorialSandbox está en true pero esto no es Studio: se IGNORA y se usan los datos guardados con normalidad.")
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- Jugadores que entraron antes de conectar el evento.
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- Autoguardado periódico de los perfiles con cambios.
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, profile in profiles do
				if needsSave(profile) then
					task.spawn(saveProfile, player, profile, false)
				end
			end
		end
	end)

	-- Al cerrar el servidor, guardar a los que sigan conectados y esperar también a los
	-- guardados lanzados por PlayerRemoving (que suele dispararse antes que esto).
	game:BindToClose(function()
		for player, profile in profiles do
			task.spawn(saveProfile, player, profile, true)
		end
		local deadline = os.clock() + 25
		task.wait() -- deja arrancar los guardados recién lanzados
		while activeSaves > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

return PlayerDataService
