-- Nombres compartidos entre servidor y cliente.

local Constants = {
	RemotesFolderName = "Remotes",

	Remotes = {
		-- Cliente -> servidor: (upgradeId: string)
		PurchaseUpgrade = "PurchaseUpgrade",
		-- Servidor -> cliente: (success: boolean, code: string, upgradeId: string?)
		PurchaseResult = "PurchaseResult",

		-- Cliente -> servidor: (eggId: string, requestId: string, count: number?)
		-- requestId identifica la compra: si se reenvía, el servidor devuelve el mismo
		-- resultado sin volver a cobrar ni a sortear. count = 3 abre tres (pase «Abrir ×3»).
		PurchaseEgg = "PurchaseEgg",
		-- Servidor -> cliente: (success, code, eggId?, petId?, petUid?, autoEquipped?, requestId?, extras?)
		-- extras: { { PetId, Uid, AutoEquipped } } las otras mascotas de una apertura ×3
		-- (petId es siempre la más rara).
		EggResult = "EggResult",
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
		-- Servidor -> cliente: (success, code, zoneId?, missingDiamonds?)
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

		-- Cliente -> servidor: (enemyModel: Model?) pide un disparo: al enemigo del clic o, sin
		-- modelo (F o "Disparar"), al más cercano a tiro. El servidor comprueba que exista y
		-- esté vivo; el disparo, la cadencia y el daño los decide él.
		Attack = "Attack",
		-- Cliente -> servidor: (enabled: boolean) enciende o apaga el disparo automático
		-- (solo con el pase "Disparo automático"; sin él se ignora).
		SetAutoFire = "SetAutoFire",
		-- Cliente -> servidor: (key: "HudScale", value: number) cambia un ajuste del jugador
		-- (⚙️ Ajustes; SettingsService lo valida con SettingsLogic y lo guarda).
		SetSetting = "SetSetting",
		-- Personajes (ProfileService). Cliente -> servidor: ("Create", styleId) crea un personaje
		-- con esa clase o ("Select", hueco) elige otro; en los dos casos se guarda y el jugador
		-- vuelve a entrar con ese personaje. Servidor -> cliente: (success, code, action).
		ProfileAction = "ProfileAction",
		ProfileResult = "ProfileResult",
		-- Servidor -> cliente: (amount, enemyName, isBoss, position, isKill, extra?) dinero
		-- ganado; al derrotarlo extra = { Diamonds, Golden, Streak } (⚡, orbe dorado y racha).
		CombatReward = "CombatReward",
		-- Oleadas (WaveService). Cliente -> servidor: ("Start") empieza o se une a una partida
		-- (también con el ProximityPrompt del altar) o ("Pick", cardId) elige mejora.
		WaveAction = "WaveAction",
		-- Servidor -> cliente: (kind, data) "State" (estado de SU partida, solo a quien juega),
		-- "Cards" (mejoras para elegir), "Picked", "Cleared", "Hint" (consejo del tutorial),
		-- "Fx" y "Result" (fin de la partida).
		WaveEvent = "WaveEvent",
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
		-- Servidor -> cliente: ({ Step, Money?, Potions? }) premio de un paso del tutorial.
		TutorialReward = "TutorialReward",

		-- Núcleos elementales (CoreService):
		-- Cliente -> servidor: () pide el estado de sus núcleos
		RequestCores = "RequestCores",
		-- Servidor -> cliente: (state) núcleos, niveles, costes y habilidades (solo para mostrar)
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
		-- Oleada más alta superada en cada modo desde el último renacimiento ("Forest=10").
		RebirthCycle = "RebirthCycle",
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
		-- { Diamonds?, Blessings?, PetId? } o lo que falta (renacimientos del código).
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
		-- Servidor -> cliente: (success, code, chestId, detail?) detail = { Diamonds?,
		-- Blessings?, ReadyAt, Opened (cofres abiertos ahora), Total }.
		ChestResult = "ChestResult",

		-- Inventario (ItemService): pociones, huevos guardados y títulos.
		-- Cliente -> servidor: () pide el estado del inventario.
		RequestItems = "RequestItems",
		-- Servidor -> cliente: (state) { Ready, Potions, Eggs, Boosts (segundos que quedan),
		-- Titles, Title, Progress } (al pedirlo y cuando cambia algo).
		ItemState = "ItemState",
		-- Cliente -> servidor: (action: "UsePotion" | "OpenEgg" | "EquipTitle", id: string)
		ItemAction = "ItemAction",
		-- Servidor -> cliente: (success, code, action, detail?); también "Drop" (botín de un
		-- jefe), "Title" (título nuevo) y "BoostEnded" (se acabó una poción).
		ItemResult = "ItemResult",

		-- Estilos de pelea (StyleService; StyleConfig). Cliente -> servidor: ("Set", styleId)
		-- cambia de estilo o ("Ability") usa la habilidad del estilo; el servidor lo decide todo.
		StyleAction = "StyleAction",
		-- Servidor -> clientes cercanos: (event) efecto YA resuelto de una habilidad de estilo
		-- ("Burst", "Quake", "Meteor") o resultado para quien la pidió ("Result").
		StyleEvent = "StyleEvent",

		-- Cueva de los Espinillos (CaveService; CaveConfig). Servidor -> cliente que viaja:
		-- ("Fade", { Inside }) antes de moverlo (fundido a negro), ("Arrived", { Inside, Position,
		-- Facing }) al llegar y ("Blocked", { Index }) si estaba detrás de una puerta cerrada.
		CaveEvent = "CaveEvent",
	},

	-- Atributos que el servidor escribe en el Player (solo lectura para el cliente).
	Attributes = {
		Diamonds = "Diamonds",
		-- Dinero que sueltan los enemigos; paga las armas y las mejoras de la Armería.
		Money = "Money",
		-- Armas: la equipada y las que tiene con su nivel ("Laser:3,PlasmaBlaster:0").
		EquippedWeapon = "EquippedWeapon",
		Weapons = "Weapons",
		-- true si su arma dispara sola hacia donde apunta cuando va a dar a alguien (tiene el
		-- pase y lo tiene encendido; PetCombatService).
		AutoFire = "AutoFire",
		-- Jefes que ha derrotado alguna vez, separados por comas (portales y tutorial).
		BossesDefeated = "BossesDefeated",
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
		-- Tamaño de la interfaz elegido en ⚙️ Ajustes (uno de SettingsLogic.HudScales).
		HudScale = "HudScale",
		-- Personajes de la cuenta (ProfileLogic.encode), hueco con el que juega y su clase fija
		-- ("" = puede cambiar de estilo, el personaje de antes de los personajes).
		Profiles = "Profiles",
		ProfileSlot = "ProfileSlot",
		FixedStyle = "FixedStyle",
		-- Tutorial: "Active" | "Completed" | "Skipped" (sin atributo = datos no listos).
		TutorialStatus = "TutorialStatus",
		-- Pasos ya hechos (0..número de pasos); el paso actual es TutorialStep + 1.
		TutorialStep = "TutorialStep",
		-- Tras el tutorial: Id del siguiente objetivo (TutorialConfig.NextGoals) o "" si no hay.
		TutorialNext = "TutorialNext",
		-- true solo en el modo prueba del tutorial (Studio): nada se carga ni se guarda.
		TestMode = "TestMode",
		-- Núcleos elementales: desbloqueados separados por comas ("Nature,Water") y elemento
		-- seleccionado. Solo para la interfaz.
		UnlockedCores = "UnlockedCores",
		SelectedCore = "SelectedCore",
		-- Elemento secundario (habilidad en la R); "" si no hay.
		SecondaryCore = "SecondaryCore",
		-- Economía nueva: la ⚡ guardada se convirtió en 💰 al entrar: "energía,dinero" (una vez).
		EconomyNotice = "EconomyNotice",
		-- Guardado v16: la Resonancia y las ventajas de renacer quitadas se devolvieron al entrar:
		-- "nivel,dinero,fichas" (una vez).
		RetiredRefund = "RetiredRefund",
		-- Renacimiento: renacimientos hechos, fichas sin gastar, niveles de la tienda
		-- ("Loot=1,Strike=2") y mascotas que se pueden equipar a la vez.
		Rebirths = "Rebirths",
		RebirthTokens = "RebirthTokens",
		RebirthShop = "RebirthShop",
		-- Oleada más alta superada en cada modo desde el último renacimiento ("Forest=10").
		RebirthCycle = "RebirthCycle",
		MaxEquipped = "MaxEquipped",
		-- Tienda: pases que tiene ("DoubleEnergy,TripleHatch"), espacio de inventario y si la
		-- mejora automática está funcionando (tiene el pase y el interruptor encendido).
		Passes = "Passes",
		MaxInventory = "MaxInventory",
		AutoUpgrade = "AutoUpgrade",
		-- Premio diario: true si hoy hay premio sin reclamar (para la insignia del menú).
		DailyReady = "DailyReady",
		-- Energía generada en total (no baja al gastar ni al renacer): clasificaciones.
		TotalDiamonds = "TotalDiamonds",
		-- Oleadas superadas en total (clasificación "Oleadas superadas"; WaveLogic.Records).
		WavesCleared = "WavesCleared",
		-- Racha de enemigos derrotados sin parar (EnemyService): cuántos, hora del servidor a
		-- la que caduca y la mejor de la sesión.
		Streak = "Streak",
		StreakUntil = "StreakUntil",
		StreakBest = "StreakBest",
		-- Modo de oleadas en el que juega ahora (WaveConfig.Arenas; nil si ninguno; WaveService).
		WaveArena = "WaveArena",
		-- Partida de oleadas (número) del jugador y de cada enemigo de esa partida (en el
		-- modelo y en sus efectos). Las partidas son privadas: cada jugador solo ve, golpea y
		-- recibe golpes de los enemigos con su mismo valor (nil = el mundo normal).
		WaveRun = "WaveRun",
		-- Estilo de pelea elegido (StyleConfig: "Weapons" | "Warrior" | "Fists" | "Magic"), hora del
		-- servidor en que su habilidad vuelve a estar lista y hasta cuándo dura la Ráfaga.
		CombatStyle = "CombatStyle",
		StyleReadyAt = "StyleReadyAt",
		-- Hora del servidor en que vuelve a estar lista la segunda habilidad del estilo (X).
		StyleReadyAt2 = "StyleReadyAt2",
		StyleBurstUntil = "StyleBurstUntil",
		-- Puertas de la Cueva de los Espinillos: bichos derrotados para cada una ("15,3";
		-- CaveLogic.parseProgress). Sin atributo: datos aún no cargados.
		CaveGates = "CaveGates",
		-- Habilidades de los estilos (SkillLogic): las que tiene con su nivel
		-- ("Burst:1,Grenade:3") y las puestas de cada estilo ("Weapons=Burst,Grenade;…").
		Skills = "Skills",
		SkillSlots = "SkillSlots",
		-- Clases de los estilos (ClassLogic): las que tiene con su nivel ("Soldier:2,Sniper:1")
		-- y la activa de cada estilo ("Weapons=Sniper;Fists=Brawler;Magic=Apprentice").
		Classes = "Classes",
		ClassActive = "ClassActive",
		-- Ya eligió su estilo al empezar (si no, el cliente le enseña el selector).
		StylePicked = "StylePicked",
		-- Hasta cuándo dura la Furia de Puños (hora del servidor) y el dash (Shift).
		StyleRageUntil = "StyleRageUntil",
		DashReadyAt = "DashReadyAt",
		-- Armas (PetCombatService): balas en el cargador, su tamaño y hasta cuándo recarga
		-- (hora del servidor; 0 = no recarga).
		Ammo = "Ammo",
		AmmoMax = "AmmoMax",
		ReloadEnd = "ReloadEnd",
		-- Magia: maná que tiene (entero) y el máximo.
		Mana = "Mana",
		ManaMax = "ManaMax",
		-- Guerrero: está bloqueando (lo ven todos: pose de guardia).
		Blocking = "Blocking",
	},

	PurchaseCodes = {
		Success = "Success",
		InvalidRequest = "InvalidRequest",
		NotReady = "NotReady",
		MaxLevel = "MaxLevel",
		InsufficientDiamonds = "InsufficientDiamonds",
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
		BossLocked = "BossLocked", -- la zona pide derrotar antes al jefe de la anterior
		AlreadyUnlocked = "AlreadyUnlocked",
		Busy = "Busy", -- ya hay un viaje en curso
		-- Misiones
		NotComplete = "NotComplete",
		AlreadyClaimed = "AlreadyClaimed",
		-- Núcleos
		AlreadySelected = "AlreadySelected",
		-- Habilidades elementales
		Cooldown = "Cooldown", -- aún recargando
		FullHealth = "FullHealth", -- Poción de Vida con la vida llena
		NoTarget = "NoTarget", -- habilidad con objetivo sin ningún enemigo delante (no se gasta)
		-- Renacimiento
		ComingSoon = "ComingSoon", -- aún no disponible (renacer con RebirthConfig.Enabled = false)
		WavesNotDone = "WavesNotDone", -- para renacer faltan las oleadas del ciclo
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
