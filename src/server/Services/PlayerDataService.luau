-- Estado de cada jugador. Energía, dinero, mejoras, mascotas, zonas, misiones y núcleos se
-- cargan y guardan con SaveService (un único DataStore).
-- Producción: todos los núcleos desbloqueados (Naturaleza = el cristal) más la afinidad
-- del seleccionado, por el multiplicador de mascotas (CoreLogic.effectiveProduction) y por
-- el de renacimiento (RebirthLogic.energyMultiplier, aparte para no chocar con el tope de
-- mascotas) y por el de las aventuras (amuletos y bendiciones activas,
-- AdventureLogic.productionMultiplier). Al cargar se concede la producción offline desde
-- el último guardado (CoreLogic), también con el multiplicador de renacimiento, sus horas
-- extra y los amuletos (las bendiciones son solo para jugar).
-- Mientras dura, la Poción de Energía (ItemLogic, inventario) también la multiplica (no la
-- offline: el tiempo de las pociones solo corre jugando).
-- Pases de la tienda (profile.Passes, los rellena ShopService al consultar a Roblox): el
-- de «Energía ×2» multiplica la producción y la offline (para la offline se espera unos
-- segundos a saber qué pases tiene).
-- Replica valores al cliente mediante atributos del Player, que el cliente
-- no puede modificar en el servidor.
--
-- Carga:
-- - Mientras carga ("Loading") se sigue produciendo energía y cobrando recompensas de
--   enemigos; al terminar se SUMA a la energía guardada (no se pierde ni se duplica).
--   Gastar no es posible durante la carga (mejoras, armas, huevos y zonas exigen datos listos).
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
local WeaponConfig = require(Shared.Config.WeaponConfig)
local WeaponLogic = require(Shared.WeaponLogic)
local Constants = require(Shared.Constants)
local Economy = require(Shared.Economy)
local PetMath = require(Shared.PetMath)
local RebirthLogic = require(Shared.RebirthLogic)
local AdventureLogic = require(Shared.AdventureLogic)
local MonetizationLogic = require(Shared.MonetizationLogic)
local PetConfig = require(Shared.Config.PetConfig)
local ItemLogic = require(Shared.ItemLogic)
local StyleLogic = require(Shared.StyleLogic)
local SaveService = require(script.Parent.SaveService)
local CoreLogic = require(script.Parent.Parent.Util.CoreLogic)
local DevConfig = require(script.Parent.Parent.DevConfig)

local AUTOSAVE_INTERVAL = 90
local PASSES_WAIT = 8 -- segundos como mucho esperando a saber los pases (producción offline)

export type DataState = "Loading" | "Loaded" | "Unavailable" | "Failed"

export type Profile = {
	Energy: number,
	Money: number, -- lo sueltan los enemigos (EnemyService); paga la Tienda de Láser
	ProductionPerSecond: number,
	UpgradeLevels: { [string]: number },
	PetMultiplier: number,
	PetData: SaveService.PetData,
	DataState: DataState,
	Dirty: boolean,
	SavedEconomy: string?, -- firma de energía y mejoras del último guardado correcto
	SaveError: boolean, -- el último intento de guardado falló (se reintentará)
	Sandbox: boolean, -- perfil temporal del modo prueba: nunca se carga ni se guarda
	Passes: MonetizationLogic.Passes, -- pases de la tienda (ShopService; no se guardan)
	PassesChecked: boolean, -- ya se consultaron a Roblox
}

local PlayerDataService = {}

local profiles: { [Player]: Profile } = {}
local readyListeners: { (Player) -> () } = {}
local expectPasses = false -- hay una tienda que consulta los pases (ShopService.start)

-- La tienda avisa de que consultará los pases de cada jugador: la producción offline espera
-- (poco) a saber si tiene «Energía ×2».
function PlayerDataService.expectPasses()
	expectPasses = true
end

local function createProfile(): Profile
	local upgradeLevels = {}
	for upgradeId in EconomyConfig.Upgrades do
		upgradeLevels[upgradeId] = 0
	end

	return {
		Energy = EconomyConfig.StartingEnergy,
		Money = EconomyConfig.StartingMoney,
		ProductionPerSecond = Economy.getProductionPerSecond(upgradeLevels),
		UpgradeLevels = upgradeLevels,
		PetMultiplier = 1,
		PetData = SaveService.emptyData(),
		DataState = "Loading",
		Dirty = false,
		SavedEconomy = nil,
		SaveError = false,
		Sandbox = false,
		Passes = {},
		PassesChecked = false,
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
		-- Con solo Naturaleza y sin renacer es exactamente Economy · mascotas, como antes.
		local base = CoreLogic.effectiveProduction(profile.PetData.Cores, profile.UpgradeLevels, profile.PetMultiplier)
		profile.ProductionPerSecond = base
			* RebirthLogic.energyMultiplier(profile.PetData.Rebirth)
			* AdventureLogic.productionMultiplier(profile.PetData.Adventure, os.time())
			* MonetizationLogic.energyMultiplier(profile.Passes)
			* ItemLogic.multiplier(ItemLogic.ofProfile(profile), "Energy", os.time()) -- Poción de Energía
	end
end

-- Números de combate del jugador con su arma equipada (WeaponLogic): daño de un disparo,
-- segundos entre disparos, alcance, daño por segundo y "poder" (lo que escala con el arma:
-- habilidades y núcleos), con mascotas, renacimiento y aventuras. RawPower es el poder sin
-- mascotas ni bonificaciones (base del daño de las mascotas, que llevan su propio multiplicador).
export type CombatStats = { WeaponId: string, Level: number, Shot: number, Cooldown: number, Range: number, Dps: number, Power: number, RawPower: number, Bonus: number }
function PlayerDataService.combatStats(profile: Profile): CombatStats
	local weapons = profile.PetData.Weapons
	local weaponId = weapons.Equipped
	local level = WeaponLogic.level(weapons, weaponId)
	local cadence = profile.UpgradeLevels[WeaponConfig.CadenceUpgradeId] or 0
	local bonus = RebirthLogic.damageMultiplier(RebirthLogic.ofProfile(profile)) * AdventureLogic.damageMultiplier(AdventureLogic.ofProfile(profile), os.time())
	local definition = WeaponLogic.definition(weaponId) or WeaponConfig.Weapons[WeaponConfig.StarterWeapon]
	return {
		WeaponId = weaponId,
		Level = level,
		Shot = WeaponLogic.shotDamage(weaponId, level, profile.PetMultiplier, bonus),
		Cooldown = WeaponLogic.cooldown(weaponId, cadence),
		Range = definition.Range,
		Dps = WeaponLogic.dps(weaponId, level, cadence, profile.PetMultiplier, bonus),
		Power = WeaponLogic.power(weaponId, level, cadence, profile.PetMultiplier, bonus),
		RawPower = WeaponLogic.power(weaponId, level, cadence, 1, 1),
		Bonus = bonus,
	}
end

-- Armas que tiene con su nivel, para el cliente ("Laser:3,PlasmaBlaster:0")
local function weaponsText(weapons: WeaponLogic.WeaponData): string
	local parts = {}
	for _, weaponId in WeaponLogic.ordered() do
		if weapons.Owned[weaponId] then
			table.insert(parts, weaponId .. ":" .. WeaponLogic.level(weapons, weaponId))
		end
	end
	return table.concat(parts, ",")
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
	setIfChanged(player, attributes.Money, math.floor(profile.Money))
	setIfChanged(player, attributes.ProductionPerSecond, profile.ProductionPerSecond)
	for upgradeId, level in profile.UpgradeLevels do
		setIfChanged(player, attributes.UpgradeLevelPrefix .. upgradeId, level)
	end
	local speedLevel = profile.UpgradeLevels.WalkSpeed or 0
	local amuletMult = AdventureLogic.walkSpeedMultiplier(profile.PetData.Adventure)
	-- Estilo de pelea: Puños corren más y Magia camina más lento
	local baseSpeed = (28 + speedLevel * 2.5) * amuletMult * StyleLogic.walkSpeed(profile.PetData.Style)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:SetAttribute("BaseWalkSpeed", baseSpeed)
		humanoid.WalkSpeed = baseSpeed
	end
	setIfChanged(player, attributes.PetMultiplier, profile.PetMultiplier)

	-- Arma equipada, las que tiene y sus números (Armería, botón de disparo)
	local stats = PlayerDataService.combatStats(profile)
	setIfChanged(player, attributes.EquippedWeapon, stats.WeaponId)
	setIfChanged(player, attributes.Weapons, weaponsText(profile.PetData.Weapons))
	-- Con la Poción de Fuerza se muestra el daño doble (lo aplica EnemyService.damage).
	local damageBoost = ItemLogic.multiplier(ItemLogic.ofProfile(profile), "Damage", os.time())
	setIfChanged(player, attributes.PlayerDamage, stats.Shot * damageBoost)
	-- Estilo de pelea y el daño por segundo que da con el arma (Puños: más)
	local style = StyleLogic.sanitize(profile.PetData.Style)
	setIfChanged(player, attributes.CombatStyle, style)
	setIfChanged(player, attributes.DamagePerSecond, StyleLogic.dps(stats.Dps, style) * damageBoost)

	-- Dinero en la lista de jugadores
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		local folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
		leaderstats = folder
	end
	local moneyStat = leaderstats:FindFirstChild("Dinero")
	if not moneyStat then
		local stat = Instance.new("NumberValue")
		stat.Name = "Dinero"
		stat.Parent = leaderstats
		moneyStat = stat
	end
	local money = math.floor(profile.Money)
	if (moneyStat :: NumberValue).Value ~= money then
		(moneyStat :: NumberValue).Value = money
	end
	setIfChanged(player, attributes.EquippedPets, table.concat(PlayerDataService.getEquippedPetIds(profile), ","))
	setIfChanged(player, attributes.UnlockedZones, table.concat(profile.PetData.UnlockedZones, ","))
	local bosses = {}
	for typeId, kills in profile.PetData.Bosses do
		if kills > 0 then
			table.insert(bosses, typeId)
		end
	end
	table.sort(bosses)
	setIfChanged(player, attributes.BossesDefeated, table.concat(bosses, ","))
	setIfChanged(player, attributes.DataStatus, profile.DataState)
	setIfChanged(player, attributes.SaveError, profile.SaveError)
	-- Núcleos (para los altares y el panel): desbloqueados en el orden de CoreConfig.
	local cores = profile.PetData.Cores
	local unlocked = {}
	for _, elementId in CoreLogic.Order do
		if CoreLogic.isUnlocked(cores, elementId) then
			table.insert(unlocked, elementId)
		end
	end
	setIfChanged(player, attributes.UnlockedCores, table.concat(unlocked, ","))
	setIfChanged(player, attributes.SelectedCore, cores.Selected)
	-- Secundario (tecla R): "" si no hay.
	setIfChanged(player, attributes.SecondaryCore, CoreLogic.secondaryOf(cores) or "")
	-- Renacimiento (RebirthController y la tienda de fichas).
	local rebirth = profile.PetData.Rebirth
	setIfChanged(player, attributes.Rebirths, RebirthLogic.count(rebirth))
	setIfChanged(player, attributes.RebirthTokens, if type(rebirth) == "table" then rebirth.Tokens or 0 else 0)
	setIfChanged(player, attributes.RebirthShop, RebirthLogic.shopText(rebirth))
	setIfChanged(player, attributes.RebirthBestLevel, if type(rebirth) == "table" then rebirth.BestLevel or 0 else 0)
	setIfChanged(player, attributes.MaxEquipped, MonetizationLogic.maxEquipped(rebirth, profile.Passes, PetConfig.MaxEquipped))
	-- Energía generada en total (clasificaciones; la cuenta QuestService).
	local quests = profile.PetData.Quests
	local earned = if type(quests) == "table" and type(quests.Stats) == "table" then quests.Stats.EnergyEarned else 0
	setIfChanged(player, attributes.TotalEnergy, math.floor(if type(earned) == "number" and earned == earned then earned else 0))
	-- Oleadas superadas en total (clasificación de oleadas; las cuenta WaveService).
	local waves = profile.PetData.Waves
	setIfChanged(player, attributes.WavesCleared, if type(waves) == "table" and type(waves.Cleared) == "number" then waves.Cleared else 0)
	-- Tienda
	setIfChanged(player, attributes.Passes, MonetizationLogic.passesText(profile.Passes))
	setIfChanged(player, attributes.MaxInventory, MonetizationLogic.maxInventory(profile.Passes, PetConfig.MaxInventory))
	local shop = profile.PetData.Shop
	setIfChanged(player, attributes.AutoUpgrade, MonetizationLogic.owns(profile.Passes, "AutoUpgrade") and type(shop) == "table" and shop.AutoUpgrade == true)
end

-- Firma de la economía (para saber si hay algo nuevo que guardar).
local function economySignature(profile: Profile): string
	local parts = { ("%.4f"):format(profile.Energy), ("money=%.4f"):format(profile.Money) }
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

-- Producción offline desde el último guardado correcto (CoreLogic.offlineReward: base de
-- los núcleos · mascotas · 50 %, máximo 4 h más las del renacimiento) por el multiplicador
-- de renacimiento. Se suma directamente, sin pasar por
-- EnergyService, así que NO cuenta para las misiones de "generar energía". Se guarda en
-- seguida para que LastSeen avance y la misma ausencia no se pueda cobrar dos veces.
local function grantOfflineReward(player: Player, profile: Profile)
	-- Rediseño "solo disparar": sin energía pasiva tampoco hay energía mientras no juegas.
	if EconomyConfig.PassiveEnergy == false then
		return
	end
	-- El pase «Energía ×2» también vale offline: se espera (poco) a saber si lo tiene.
	local deadline = os.clock() + PASSES_WAIT
	while expectPasses and not profile.PassesChecked and os.clock() < deadline and profiles[player] == profile do
		task.wait(0.25)
	end
	if profiles[player] ~= profile then
		return
	end
	local data = profile.PetData
	local rawReward, seconds = CoreLogic.offlineReward(data.Cores, profile.UpgradeLevels, profile.PetMultiplier, data.LastSeen, os.time(), RebirthLogic.offlineBonusSeconds(data.Rebirth))
	local reward = math.floor(rawReward * RebirthLogic.energyMultiplier(data.Rebirth) * AdventureLogic.offlineMultiplier(data.Adventure) * MonetizationLogic.energyMultiplier(profile.Passes))
	if reward <= 0 then
		return
	end
	profile.Energy += reward
	data.LastSeen = os.time() -- ya cobrada (el próximo guardado escribe la hora real)
	player:SetAttribute(Constants.Attributes.OfflineReward, ("%.0f,%.0f"):format(reward, seconds))
	PlayerDataService.saveNow(player)
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
		profile.Money = data.Money + math.max(0, profile.Money - EconomyConfig.StartingMoney)
		local levels = {}
		for upgradeId in EconomyConfig.Upgrades do
			levels[upgradeId] = data.UpgradeLevels[upgradeId] or 0
		end
		profile.UpgradeLevels = levels
		profile.PetData = data
		if #profile.PetData.Pets == 0 then
			table.insert(profile.PetData.Pets, { Uid = "p1", PetId = "Sproutling" })
			table.insert(profile.PetData.Equipped, "p1")
			profile.PetData.NextPetUid = math.max(profile.PetData.NextPetUid or 1, 2)
		elseif #profile.PetData.Equipped == 0 then
			table.insert(profile.PetData.Equipped, profile.PetData.Pets[1].Uid)
		end
	elseif status == "Unavailable" then
		warn("[PlayerDataService] DataStore no disponible: las mascotas no se guardarán en esta sesión. "
			.. "En Studio activa Game Settings > Security > Enable Studio Access to API Services.")
	else
		warn("[PlayerDataService] No se pudieron cargar los datos de " .. player.Name .. "; no se guardará para proteger sus datos.")
	end

	PlayerDataService.recalculateProduction(player)
	if status == "Loaded" and data then
		-- En su propio hilo: si espera a saber los pases, los datos ya están listos mientras.
		task.spawn(grantOfflineReward, player, profile)
	end
	PlayerDataService.replicate(player)
	if PlayerDataService.isPetDataReady(profile) then
		notifyReady(player)
	end
end

-- Guardados en curso; BindToClose espera a que terminen todos.
local activeSaves = 0

local function saveProfile(player: Player, profile: Profile, release: boolean): boolean
	if profile.DataState ~= "Loaded" or profile.Sandbox then
		return false -- sin datos cargados (o perfil de prueba) nunca se guarda
	end
	activeSaves += 1
	profile.Dirty = false
	-- La economía se copia ahora; lo que cambie durante la espera se guardará la próxima vez.
	local signature = economySignature(profile)
	profile.PetData.Energy = profile.Energy
	profile.PetData.Money = profile.Money
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
	return ok and saved == true
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

-- Guarda ya y espera el resultado (compras de Robux: solo se confirman a Roblox cuando la
-- compra quedó guardada). true si se guardó.
function PlayerDataService.saveAndWait(player: Player): boolean
	local profile = profiles[player]
	if not profile or profile.DataState ~= "Loaded" or profile.Sandbox then
		return false
	end
	return saveProfile(player, profile, false)
end

local function onPlayerAdded(player: Player)
	if profiles[player] then
		return
	end
	local profile = createProfile()
	profiles[player] = profile
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
		local currentProfile = profiles[player]
		if humanoid and currentProfile then
			local speedLvl = currentProfile.UpgradeLevels.WalkSpeed or 0
			local amuletMult = AdventureLogic.walkSpeedMultiplier(currentProfile.PetData.Adventure)
			local baseSpeed = (28 + speedLvl * 2.5) * amuletMult * StyleLogic.walkSpeed(currentProfile.PetData.Style)
			humanoid:SetAttribute("BaseWalkSpeed", baseSpeed)
			humanoid.WalkSpeed = baseSpeed
		end
	end)
	PlayerDataService.replicate(player)
	task.spawn(loadPetData, player, profile)
end

-- Avisos de salida (antes de soltar el perfil): reciben el jugador y su perfil.
local leavingListeners: { (Player, Profile) -> () } = {}
function PlayerDataService.onLeaving(callback: (Player, Profile) -> ())
	table.insert(leavingListeners, callback)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	profiles[player] = nil
	if profile then
		for _, callback in leavingListeners do
			task.spawn(callback, player, profile)
		end
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
