-- Estado de cada jugador. 💎 (Diamonds en el código), dinero, mejoras, mascotas, zonas,
-- misiones y núcleos se cargan y guardan con SaveService (un único DataStore).
-- Nada se gana sin jugar: no hay producción por segundo ni recompensa offline.
-- refreshStats recalcula el multiplicador de mascotas (daño y 💰); diamondMultiplier da el
-- de los 💎 (pase Diamantes ×2, poción y aventuras).
-- Pases de la tienda: profile.Passes, los rellena ShopService al consultar a Roblox.
-- Replica valores al cliente mediante atributos del Player, que el cliente
-- no puede modificar en el servidor.
--
-- Carga:
-- - Mientras carga ("Loading") se siguen cobrando recompensas de enemigos (💎 y 💰); al
--   terminar se SUMAN a lo guardado (no se pierde ni se duplica).
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
local ZoneConfig = require(Shared.Config.ZoneConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local WeaponLogic = require(Shared.WeaponLogic)
local Constants = require(Shared.Constants)
local PetMath = require(Shared.PetMath)
local RebirthLogic = require(Shared.RebirthLogic)
local AdventureLogic = require(Shared.AdventureLogic)
local MonetizationLogic = require(Shared.MonetizationLogic)
local PetConfig = require(Shared.Config.PetConfig)
local ItemLogic = require(Shared.ItemLogic)
local StyleLogic = require(Shared.StyleLogic)
local SkillLogic = require(Shared.SkillLogic)
local ClassLogic = require(Shared.ClassLogic)
local SaveService = require(script.Parent.SaveService)
local CoreLogic = require(script.Parent.Parent.Util.CoreLogic)
local DevConfig = require(script.Parent.Parent.DevConfig)

local AUTOSAVE_INTERVAL = 90

export type DataState = "Loading" | "Loaded" | "Unavailable" | "Failed"

export type Profile = {
	Diamonds: number,
	Money: number, -- lo sueltan los enemigos (EnemyService); paga la Tienda de Láser
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

local function createProfile(): Profile
	local upgradeLevels = {}
	for upgradeId in EconomyConfig.Upgrades do
		upgradeLevels[upgradeId] = 0
	end

	return {
		Diamonds = EconomyConfig.StartingDiamonds,
		Money = EconomyConfig.StartingMoney,
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

-- Multiplicador de las mascotas equipadas (daño y 💰). Se llama al cambiar mascotas,
-- mejoras, renacimientos o datos cargados.
function PlayerDataService.refreshStats(player: Player)
	local profile = profiles[player]
	if profile then
		profile.PetMultiplier = PetMath.getTotalMultiplier(PlayerDataService.getEquippedPetIds(profile))
	end
end

-- Multiplicador de los 💎 que gana el jugador (enemigos y premios de las oleadas): pase
-- Diamantes ×2, Poción de Diamantes y aventuras (amuletos de Savia y Magma, Bendición de
-- Abundancia). EnemyService y WaveService lo aplican sobre la cantidad base.
function PlayerDataService.diamondMultiplier(profile: Profile): number
	local now = os.time()
	return MonetizationLogic.diamondMultiplier(profile.Passes)
		* ItemLogic.multiplier(ItemLogic.ofProfile(profile), "Diamonds", now)
		* AdventureLogic.diamondMultiplier(profile.PetData.Adventure, now)
end

-- Números de combate del jugador con su arma equipada (WeaponLogic): daño de un disparo,
-- segundos entre disparos, alcance, daño por segundo y "poder" (lo que escala con el arma:
-- habilidades y núcleos), con mascotas, renacimiento y aventuras. RawPower es el poder sin
-- mascotas ni bonificaciones (base del daño de las mascotas, que llevan su propio multiplicador).
export type CombatStats = { WeaponId: string, Level: number, Shot: number, Cooldown: number, Range: number, Dps: number, Power: number, RawPower: number, Bonus: number }
function PlayerDataService.combatStats(profile: Profile): CombatStats
	local weapons = profile.PetData.Weapons
	-- Lo equipado para el estilo actual: el arma, los guantes o el bastón
	local weaponId = WeaponLogic.equippedFor(weapons, StyleLogic.sanitize(profile.PetData.Style))
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

-- Velocidad al caminar (mejora, amuleto, estilo: Puños corren más y Magia camina más
-- lento, y clase) y vida máxima (Puños: +50 %, y clase) del personaje. Al cambiar la vida
-- máxima se conserva la parte de vida que tenía.
local BASE_HEALTH = 100
local function applyBody(humanoid: Humanoid, profile: Profile)
	local speedLevel = profile.UpgradeLevels.WalkSpeed or 0
	local speedDef = EconomyConfig.Upgrades.WalkSpeed
	local perLevel = if speedDef and type(speedDef.SpeedPerLevel) == "number" then speedDef.SpeedPerLevel else 2.5
	local amuletMult = AdventureLogic.walkSpeedMultiplier(profile.PetData.Adventure)
	local style = StyleLogic.sanitize(profile.PetData.Style)
	local class = ClassLogic.mods(profile.PetData.Classes, style)
	local baseSpeed = (28 + speedLevel * perLevel) * amuletMult * StyleLogic.walkSpeed(style) * class.WalkSpeed
	humanoid:SetAttribute("BaseWalkSpeed", baseSpeed)
	humanoid.WalkSpeed = baseSpeed
	local maxHealth = math.floor(BASE_HEALTH * StyleLogic.maxHealth(style) * class.MaxHealth + 0.5)
	local current = humanoid.MaxHealth
	if type(current) == "number" and type(humanoid.Health) == "number" and math.abs(current - maxHealth) > 0.01 then
		local fraction = if current > 0 then math.clamp(humanoid.Health / current, 0, 1) else 1
		humanoid.MaxHealth = maxHealth
		if humanoid.Health > 0 then
			humanoid.Health = maxHealth * fraction
		end
	end
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
	player:SetAttribute(attributes.Diamonds, math.floor(profile.Diamonds))
	setIfChanged(player, attributes.Money, math.floor(profile.Money))
	for upgradeId, level in profile.UpgradeLevels do
		setIfChanged(player, attributes.UpgradeLevelPrefix .. upgradeId, level)
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		applyBody(humanoid, profile)
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
	-- Habilidades de los estilos: las que tiene (con nivel), las puestas y si ya eligió estilo
	local skills = profile.PetData.Skills or SkillLogic.empty()
	setIfChanged(player, attributes.Skills, SkillLogic.ownedText(skills))
	setIfChanged(player, attributes.SkillSlots, SkillLogic.slotsText(skills))
	setIfChanged(player, attributes.StylePicked, skills.Picked == true)
	-- Clases: las que tiene (con nivel) y la activa de cada estilo
	local classes = profile.PetData.Classes or ClassLogic.empty()
	setIfChanged(player, attributes.Classes, ClassLogic.ownedText(classes))
	setIfChanged(player, attributes.ClassActive, ClassLogic.activeText(classes))
	-- DPS de tus golpes con la clase (daño y cadencia; las habilidades van aparte)
	local class = ClassLogic.mods(classes, style)
	setIfChanged(player, attributes.DamagePerSecond, StyleLogic.dps(stats.Dps, style) * damageBoost * class.Damage / class.Cooldown)

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
	setIfChanged(player, attributes.RebirthCycle, RebirthLogic.cycleText(rebirth))
	setIfChanged(player, attributes.MaxEquipped, MonetizationLogic.maxEquipped(rebirth, profile.Passes, PetConfig.MaxEquipped))
	-- Energía generada en total (clasificaciones; la cuenta QuestService).
	local quests = profile.PetData.Quests
	local earned = if type(quests) == "table" and type(quests.Stats) == "table" then quests.Stats.DiamondsEarned else 0
	setIfChanged(player, attributes.TotalDiamonds, math.floor(if type(earned) == "number" and earned == earned then earned else 0))
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
	local parts = { ("%.4f"):format(profile.Diamonds), ("money=%.4f"):format(profile.Money) }
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

local function sandboxMoney(): number
	local money = DevConfig.SandboxStartingMoney
	if type(money) == "number" and money == money and money >= 0 and money < 1e15 then
		return money
	end
	return EconomyConfig.StartingMoney
end

-- Perfil temporal: datos vacíos (sin mascotas, zonas ni misiones; tutorial activo) y el
-- 💰 inicial de prueba (los 💎 empiezan en 0, como un jugador nuevo).
local function startSandbox(player: Player, profile: Profile)
	profile.Sandbox = true
	profile.DataState = "Unavailable" -- se juega con normalidad y nunca se guarda
	profile.PetData = SaveService.emptyData() -- pura: no toca el DataStore
	profile.Money = sandboxMoney()
	player:SetAttribute(Constants.Attributes.TestMode, true)
	print(("[PlayerDataService] 🧪 Perfil temporal de prueba creado para %s (UserId %d)."):format(player.Name, player.UserId))
	PlayerDataService.refreshStats(player)
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
		-- Lo ganado mientras cargaba (enemigos) se suma a lo guardado. Durante la
		-- carga no se puede gastar, así que la diferencia nunca es negativa.
		local gainedWhileLoading = math.max(0, profile.Diamonds - EconomyConfig.StartingDiamonds)
		profile.Diamonds = data.Diamonds + gainedWhileLoading
		profile.Money = data.Money + math.max(0, profile.Money - EconomyConfig.StartingMoney)
		local levels = {}
		for upgradeId in EconomyConfig.Upgrades do
			levels[upgradeId] = data.UpgradeLevels[upgradeId] or 0
		end
		profile.UpgradeLevels = levels
		profile.PetData = data
		local converted = data.EconomyConverted
		if converted then
			data.EconomyConverted = nil
			profile.Dirty = true -- que la conversión quede guardada cuanto antes
			player:SetAttribute(Constants.Attributes.EconomyNotice, ("%d,%d"):format(converted.Energy, converted.Money))
		end
		local refund = data.RetiredRefund
		if refund then
			data.RetiredRefund = nil
			profile.Dirty = true -- que la devolución quede guardada cuanto antes
			player:SetAttribute(Constants.Attributes.RetiredRefund, ("%d,%d,%d"):format(refund.Level, refund.Money, refund.Tokens))
		end
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

	PlayerDataService.refreshStats(player)
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
	profile.PetData.Diamonds = profile.Diamonds
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
			applyBody(humanoid, currentProfile)
			if type(humanoid.MaxHealth) == "number" then
				humanoid.Health = humanoid.MaxHealth
			end
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

-- Solo en Studio: herramienta para probar desde la barra de comandos (o el asistente):
-- ServerStorage.DevTools:Invoke("Money", jugador, cantidad) le pone ese 💰 y
-- ServerStorage.DevTools:Invoke("Zone", jugador, "DividedLands") le abre esa zona (sin pagar
-- ni derrotar a su jefe, para ir directo a probarla). Es un
-- BindableFunction (el cliente no puede llamarlo) y en una partida publicada no existe.
-- En Studio sin acceso a la API el perfil no se guarda: dura lo que dura el Play.
local MAX_DEV_MONEY = 1e15
local function startDevTools()
	pcall(function()
		local ServerStorage = game:GetService("ServerStorage")
		local tools = ServerStorage:FindFirstChild("DevTools")
		if not (tools and tools:IsA("BindableFunction")) then
			tools = Instance.new("BindableFunction")
			tools.Name = "DevTools"
		end
		(tools :: BindableFunction).OnInvoke = function(action: any, player: any, value: any): any
			local profile = if typeof(player) == "Instance" then profiles[player] else nil
			if not profile then
				return nil
			end
			if action == "Money" and type(value) == "number" and value == value and value >= 0 and value < MAX_DEV_MONEY then
				profile.Money = math.floor(value)
				PlayerDataService.replicate(player)
				return profile.Money
			end
			if action == "Zone" and type(value) == "string" and ZoneConfig.Zones[value] ~= nil then
				local unlocked = profile.PetData.UnlockedZones
				if not table.find(unlocked, value) then
					table.insert(unlocked, value)
				end
				PlayerDataService.replicate(player)
				return true
			end
			return nil
		end
		tools.Parent = ServerStorage
	end)
end

function PlayerDataService.start()
	if RunService:IsStudio() then
		startDevTools()
	end
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
