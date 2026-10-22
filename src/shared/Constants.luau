-- Nombres compartidos entre servidor y cliente.

local Constants = {
	RemotesFolderName = "Remotes",

	Remotes = {
		-- Cliente -> servidor: (upgradeId: string)
		PurchaseUpgrade = "PurchaseUpgrade",
		-- Servidor -> cliente: (success: boolean, code: string, upgradeId: string?)
		PurchaseResult = "PurchaseResult",

		-- Jardín de mascotas. Cliente -> servidor: (standId: string) compra la mascota de ese
		-- pedestal con dinero (EggConfig.Stands o "Rainbow").
		BuyPet = "BuyPet",
		-- Servidor -> cliente: (success, code, standId?, petId?, petUid?, autoEquipped?)
		PetShopResult = "PetShopResult",
		-- Cliente -> servidor: (petUid: string, equip: boolean)
		EquipPet = "EquipPet",
		-- Cliente -> servidor: (petId: string) fusiona 3 mascotas iguales en su versión ★ Evo
		EvolvePet = "EvolvePet",
		-- Servidor -> cliente: (success, code, petUid?, equip?)
		PetActionResult = "PetActionResult",
		-- Cliente -> servidor: () pide el inventario actual
		RequestPetInventory = "RequestPetInventory",
		-- Servidor -> cliente: (snapshot) inventario completo del propio jugador
		PetInventory = "PetInventory",

		-- Cliente -> servidor: (zoneId: string) desbloquear una zona en su portal
		UnlockZone = "UnlockZone",
		-- Servidor -> cliente: (success, code, zoneId?, missingEnergy?)
		ZoneResult = "ZoneResult",
		-- Cliente -> servidor: (zoneId: string) viajar a una zona desde un portal
		TravelToZone = "TravelToZone",
		-- Servidor -> cliente: (success, code, zoneId?)
		TravelResult = "TravelResult",

		-- Armería. Cliente -> servidor: (action: "Buy" | "Equip" | "Upgrade", weaponId: string)
		WeaponAction = "WeaponAction",
		-- Servidor -> cliente: (success, code, action, weaponId, cost?) también "BossDrop"
		-- cuando un jefe regala su arma.
		WeaponResult = "WeaponResult",

		-- Cliente -> servidor: (enemyModel: Model) elige el objetivo de su arma con un clic. El
		-- servidor comprueba que exista y esté vivo; el disparo y el daño los decide él.
		Attack = "Attack",
		-- Cliente -> servidor: (enabled: boolean) enciende o apaga el disparo automático.
		SetAutoFire = "SetAutoFire",
		-- Servidor -> cliente: (amount, enemyName, isBoss, position, isKill) dinero ganado
		CombatReward = "CombatReward",
		-- Servidor -> cliente: (event) acción de mascota YA confirmada, solo para efectos.
		-- No existe la dirección contraria: el cliente no puede pedir habilidades.
		PetAbility = "PetAbility",
		-- Habilidad elemental (AbilityService). Cliente -> servidor: (slot: "Primary" | "Secondary")
		-- solo pide usar la del hueco; el servidor decide elemento, objetivos, daño, curación,
		-- combos y recarga.
		UseAbility = "UseAbility",
		-- Servidor -> cliente (solo al que la usó): (success, code, elementId?, readyAt?, slot)
		-- readyAt = hora del servidor (Workspace:GetServerTimeNow) en que vuelve a estar lista.
		AbilityResult = "AbilityResult",
		-- Servidor -> clientes cercanos: (event) efecto YA resuelto, solo para dibujarlo.
		AbilityEvent = "AbilityEvent",

		-- Misiones y logros (los mismos 4 remotes para todas las misiones):
		-- Cliente -> servidor: () pide el estado actual de sus misiones
		RequestQuests = "RequestQuests",
		-- Servidor -> cliente: (state) misiones, diarias y logros + avisos nuevos (Notices)
		QuestState = "QuestState",
		-- Cliente -> servidor: (questId: string) reclamar. El servidor decide si procede y cuánto.
		ClaimQuest = "ClaimQuest",
		-- Servidor -> cliente: (success, code, questId?, amount?)
		QuestResult = "QuestResult",

		-- Cliente -> servidor: () omitir el tutorial inicial (lo único que el cliente decide).
		SkipTutorial = "SkipTutorial",

		-- Núcleos elementales (CoreService):
		-- Cliente -> servidor: () pide el estado de sus núcleos
		RequestCores = "RequestCores",
		-- Servidor -> cliente: (state) núcleos, niveles, costes y producción (solo para mostrar)
		CoreState = "CoreState",
		-- Cliente -> servidor: (action: "Unlock" | "Upgrade" | "Select", elementId: string)
		-- El servidor decide si procede y cuánto cuesta.
		CoreAction = "CoreAction",
		-- Servidor -> cliente: (success, code, action?, elementId?, cost?)
		CoreResult = "CoreResult",

		-- Renacimiento (RebirthService). El estado viaja en atributos del Player.
		-- Cliente -> servidor: () renacer (el cliente ya pidió confirmación al jugador).
		Rebirth = "Rebirth",
		-- Cliente -> servidor: (itemId: string) comprar el siguiente nivel de una ventaja.
		RebirthShop = "RebirthShop",
		-- Servidor -> cliente: (success, code, action: "Rebirth" | "Shop", detail?)
		-- detail: Rebirth -> { Count, Tokens, Level }; Shop -> { ItemId, Level, Cost }.
		RebirthResult = "RebirthResult",
		-- Servidor -> todos: (userId, displayName, count) alguien acaba de renacer (aviso).
		RebirthEvent = "RebirthEvent",

		-- Aventuras (AdventureService): personajes, misiones opcionales, amuletos y bendiciones.
		-- Cliente -> servidor: () pide el estado actual.
		RequestAdventure = "RequestAdventure",
		-- Servidor -> cliente: (state) historias, amuletos, bendiciones + avisos (Notices).
		AdventureState = "AdventureState",
		-- Servidor -> cliente: (npcId, deliveredFor?) abrir la conversación con un personaje
		-- (tras pulsar su aviso de proximidad). deliveredFor: personaje cuyo encargo se acaba
		-- de entregar a este.
		AdventureDialog = "AdventureDialog",
		-- Cliente -> servidor: (action, arg1?, arg2?) "Accept" | "TurnIn" (npcId),
		-- "Equip" (amuletId, slot?), "Unequip" (slot), "UseBlessing" (blessingId).
		AdventureAction = "AdventureAction",
		-- Servidor -> cliente: (success, code, action, detail?)
		AdventureResult = "AdventureResult",

		-- Premio diario y códigos (RewardService).
		-- Cliente -> servidor: () pide el estado de la racha.
		RequestRewards = "RequestRewards",
		-- Servidor -> cliente: (state) racha, premio de hoy y cuenta atrás.
		RewardState = "RewardState",
		-- Cliente -> servidor: (action: "Claim") o ("Redeem", texto del código).
		RewardAction = "RewardAction",
		-- Servidor -> cliente: (success, code, action, detail?) detail = premio concedido
		-- { Energy?, Blessings?, PetId? } o lo que falta (renacimientos del código).
		RewardResult = "RewardResult",

		-- Tienda (ShopService). Las compras las abre el cliente con MarketplaceService; el
		-- servidor las concede al confirmarlas Roblox.
		-- Cliente -> servidor: ("SetAuto", on: boolean) interruptor de la mejora automática.
		ShopAction = "ShopAction",
		-- Servidor -> cliente: (kind: "Pass" | "Product" | "Auto", key?, detail?) compra
		-- concedida (Product: detail = energía) o interruptor cambiado.
		ShopResult = "ShopResult",

		-- Cofres escondidos (ChestService). Se abren con su aviso de proximidad (lo valida
		-- el servidor); el cliente solo pide el estado.
		-- Cliente -> servidor: () pide las esperas de los cofres.
		RequestChests = "RequestChests",
		-- Servidor -> cliente: (state: { [chestId] = readyAt }, serverNow) cofres cerrados.
		ChestState = "ChestState",
		-- Servidor -> cliente: (success, code, chestId, detail?) detail = { Energy?,
		-- Blessings?, ReadyAt, Opened (cofres abiertos ahora), Total }.
		ChestResult = "ChestResult",
	},

	-- Atributos que el servidor escribe en el Player (solo lectura para el cliente).
	Attributes = {
		Energy = "Energy",
		-- Dinero que sueltan los enemigos; paga las armas y las mejoras de la Armería.
		Money = "Money",
		-- Armas: la equipada y las que tiene con su nivel ("Laser:3,PlasmaBlaster:0").
		EquippedWeapon = "EquippedWeapon",
		Weapons = "Weapons",
		-- true si su arma dispara sola al enemigo más cercano (PetCombatService).
		AutoFire = "AutoFire",
		ProductionPerSecond = "ProductionPerSecond",
		PlayerDamage = "PlayerDamage",
		DamagePerSecond = "DamagePerSecond",
		UpgradeLevelPrefix = "UpgradeLevel_",
		-- Multiplicador total de las mascotas equipadas (1 = sin bonificación).
		PetMultiplier = "PetMultiplier",
		-- PetIds equipados separados por comas; lo usan todos los clientes para dibujar mascotas.
		EquippedPets = "EquippedPets",
		-- Zonas desbloqueadas separadas por comas (solo informativo para la interfaz).
		UnlockedZones = "UnlockedZones",
		-- Zona en la que está el jugador (la fija el servidor al viajar o reaparecer).
		CurrentZone = "CurrentZone",
		-- Estado de sus datos guardados: "Loading" | "Loaded" | "Unavailable" | "Failed".
		DataStatus = "DataStatus",
		-- true si el último guardado falló (se reintenta solo).
		SaveError = "SaveError",
		-- Tutorial: "Active" | "Completed" | "Skipped" (sin atributo = datos no listos).
		TutorialStatus = "TutorialStatus",
		-- Pasos ya hechos (0..número de pasos); el paso actual es TutorialStep + 1.
		TutorialStep = "TutorialStep",
		-- true solo en el modo prueba del tutorial (Studio): nada se carga ni se guarda.
		TestMode = "TestMode",
		-- Núcleos elementales: desbloqueados separados por comas ("Nature,Water") y elemento
		-- seleccionado. Solo para la interfaz (CoreShrineController pinta los altares).
		UnlockedCores = "UnlockedCores",
		SelectedCore = "SelectedCore",
		-- Elemento secundario (habilidad en la R); "" si no hay.
		SecondaryCore = "SecondaryCore",
		-- Producción offline concedida al entrar: "energía,segundos" (una vez por sesión).
		OfflineReward = "OfflineReward",
		-- Renacimiento: renacimientos hechos, fichas sin gastar, niveles de la tienda
		-- ("Loot=1,Strike=2"), mejor nivel de Resonancia con el que se renació (los huevos
		-- que abrió siguen abiertos) y mascotas que se pueden equipar a la vez.
		Rebirths = "Rebirths",
		RebirthTokens = "RebirthTokens",
		RebirthShop = "RebirthShop",
		RebirthBestLevel = "RebirthBestLevel",
		MaxEquipped = "MaxEquipped",
		-- Tienda: pases que tiene ("DoubleEnergy,TripleHatch"), espacio de inventario y si la
		-- mejora automática está funcionando (tiene el pase y el interruptor encendido).
		Passes = "Passes",
		MaxInventory = "MaxInventory",
		AutoUpgrade = "AutoUpgrade",
		-- Premio diario: true si hoy hay premio sin reclamar (para la insignia del menú).
		DailyReady = "DailyReady",
		-- Energía generada en total (no baja al gastar ni al renacer): clasificaciones.
		TotalEnergy = "TotalEnergy",
	},

	PurchaseCodes = {
		Success = "Success",
		InvalidRequest = "InvalidRequest",
		NotReady = "NotReady",
		MaxLevel = "MaxLevel",
		InsufficientEnergy = "InsufficientEnergy",
		InsufficientMoney = "InsufficientMoney", -- armas y mejoras de la Armería
		AlreadyOwned = "AlreadyOwned", -- ya tiene esa arma
		NotForSale = "NotForSale", -- arma que solo suelta un jefe
		TooFast = "TooFast",
		-- Mascotas y huevos
		InventoryFull = "InventoryFull",
		TooFar = "TooFar",
		NotOwned = "NotOwned",
		EquipLimit = "EquipLimit",
		Unavailable = "Unavailable",
		Locked = "Locked", -- el huevo requiere más nivel de mejora
		ZoneLocked = "ZoneLocked", -- la zona (o el huevo de esa zona) no está desbloqueada
		RebirthLocked = "RebirthLocked", -- la zona pide más renacimientos
		AlreadyUnlocked = "AlreadyUnlocked",
		Busy = "Busy", -- ya hay un viaje en curso
		-- Misiones
		NotComplete = "NotComplete",
		AlreadyClaimed = "AlreadyClaimed",
		-- Núcleos
		AlreadySelected = "AlreadySelected",
		-- Habilidades elementales
		Cooldown = "Cooldown", -- aún recargando
		NoTarget = "NoTarget", -- habilidad con objetivo sin ningún enemigo delante (no se gasta)
		-- Renacimiento
		LevelTooLow = "LevelTooLow", -- falta Resonancia para renacer
		InsufficientTokens = "InsufficientTokens", -- faltan fichas para la ventaja
		-- Aventuras
		AlreadyAccepted = "AlreadyAccepted", -- esa misión ya está en curso
		-- Códigos
		InvalidCode = "InvalidCode", -- no existe
		Expired = "Expired", -- caducado
		AlreadyRedeemed = "AlreadyRedeemed", -- ya canjeado por este jugador
		Full = "Full", -- demasiados códigos guardados
		-- Tienda
		NotOwnedPass = "NotOwnedPass", -- hace falta el pase
		-- Cofres
		ChestCooldown = "ChestCooldown", -- ya abierto: hay que esperar
	},
}

return Constants
