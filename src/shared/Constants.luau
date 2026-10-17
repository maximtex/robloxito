-- Nombres compartidos entre servidor y cliente.

local Constants = {
	RemotesFolderName = "Remotes",

	Remotes = {
		-- Cliente -> servidor: (upgradeId: string)
		PurchaseUpgrade = "PurchaseUpgrade",
		-- Servidor -> cliente: (success: boolean, code: string, upgradeId: string?)
		PurchaseResult = "PurchaseResult",

		-- Cliente -> servidor: (eggId: string, requestId: string)
		-- requestId identifica la compra: si se reenvía, el servidor devuelve el mismo
		-- resultado sin volver a cobrar ni a sortear.
		PurchaseEgg = "PurchaseEgg",
		-- Servidor -> cliente: (success, code, eggId?, petId?, petUid?, autoEquipped?, requestId?)
		EggResult = "EggResult",
		-- Cliente -> servidor: (petUid: string, equip: boolean)
		EquipPet = "EquipPet",
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

		-- Cliente -> servidor: () solo pide atacar. El servidor decide objetivos y daño.
		Attack = "Attack",
		-- Servidor -> cliente: (hits: { { Position, Damage, Killed, Kind } }) para efectos
		AttackResult = "AttackResult",
		-- Servidor -> cliente: (amount, enemyName, isBoss) energía ganada al derrotar
		CombatReward = "CombatReward",
		-- Servidor -> cliente: (event) acción de mascota YA confirmada, solo para efectos.
		-- No existe la dirección contraria: el cliente no puede pedir habilidades.
		PetAbility = "PetAbility",

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
	},

	-- Atributos que el servidor escribe en el Player (solo lectura para el cliente).
	Attributes = {
		Energy = "Energy",
		ProductionPerSecond = "ProductionPerSecond",
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
	},

	PurchaseCodes = {
		Success = "Success",
		InvalidRequest = "InvalidRequest",
		NotReady = "NotReady",
		MaxLevel = "MaxLevel",
		InsufficientEnergy = "InsufficientEnergy",
		TooFast = "TooFast",
		-- Mascotas y huevos
		InventoryFull = "InventoryFull",
		TooFar = "TooFar",
		NotOwned = "NotOwned",
		EquipLimit = "EquipLimit",
		Unavailable = "Unavailable",
		Locked = "Locked", -- el huevo requiere más nivel de mejora
		ZoneLocked = "ZoneLocked", -- la zona (o el huevo de esa zona) no está desbloqueada
		AlreadyUnlocked = "AlreadyUnlocked",
		Busy = "Busy", -- ya hay un viaje en curso
		-- Misiones
		NotComplete = "NotComplete",
		AlreadyClaimed = "AlreadyClaimed",
	},
}

return Constants
