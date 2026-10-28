-- Punto de entrada del servidor. El orden importa:
-- los remotes deben existir antes de que UpgradeService y PetService conecten sus eventos.

local Services = script.Services

local RemoteService = require(Services.RemoteService)
local PlayerDataService = require(Services.PlayerDataService)
local DiamondService = require(Services.DiamondService)
local UpgradeService = require(Services.UpgradeService)
local CoreService = require(Services.CoreService)
local PetService = require(Services.PetService)
local WorldService = require(Services.WorldService)
local SpawnService = require(Services.SpawnService)
local EggStandService = require(Services.EggStandService)
local ValleyService = require(Services.ValleyService)
local CalderaService = require(Services.CalderaService)
local TundraService = require(Services.TundraService)
local FortressService = require(Services.FortressService)
local World2Service = require(Services.World2Service)
local DividedLandsService = require(Services.DividedLandsService)
local LeaderboardService = require(Services.LeaderboardService)
local VillageService = require(Services.VillageService)
local WildsService = require(Services.WildsService)
local ChestService = require(Services.ChestService)
local ZoneService = require(Services.ZoneService)
local EnemyService = require(Services.EnemyService)
local LandscapeService = require(Services.LandscapeService)
local CombatService = require(Services.CombatService)
local WeaponService = require(Services.WeaponService)
local BossRewardService = require(Services.BossRewardService)
local PetCombatService = require(Services.PetCombatService)
local WaveService = require(Services.WaveService)
local AbilityService = require(Services.AbilityService)
local StyleService = require(Services.StyleService)
local GearService = require(Services.GearService)
local CaveService = require(Services.CaveService)
local RebirthService = require(Services.RebirthService)
local AdventureService = require(Services.AdventureService)
local NpcService = require(Services.NpcService)
local QuestService = require(Services.QuestService)
local TutorialService = require(Services.TutorialService)
local ShopService = require(Services.ShopService)
local RewardService = require(Services.RewardService)
local ItemService = require(Services.ItemService)
local HealthService = require(Services.HealthService)
local SettingsService = require(Services.SettingsService)
local ProfileService = require(Services.ProfileService)

local function safeStart(name: string, service: any)
	local ok, err = pcall(service.start)
	if not ok then
		warn("[SERVER ERROR en " .. name .. "]:", err)
	else
		print("[SERVER OK] " .. name)
	end
end

safeStart("RemoteService", RemoteService)
safeStart("PetService", PetService)
safeStart("ItemService", ItemService) -- inventario: pociones, huevos de jefe y títulos
safeStart("ShopService", ShopService)
safeStart("PlayerDataService", PlayerDataService)
safeStart("HealthService", HealthService) -- regeneración de vida (sin la de Roblox)
safeStart("SettingsService", SettingsService) -- ⚙️ Ajustes: tamaño de la interfaz (se guarda)
safeStart("ProfileService", ProfileService) -- ⚙️ Ajustes → Personajes: crear y elegir
safeStart("UpgradeService", UpgradeService)
safeStart("CoreService", CoreService)
safeStart("DiamondService", DiamondService)
safeStart("WorldService", WorldService)
safeStart("ValleyService", ValleyService)
safeStart("CalderaService", CalderaService)
safeStart("TundraService", TundraService) -- zona 4
safeStart("FortressService", FortressService) -- zona 5 (el portal gigante lo pone ZoneService)
safeStart("VillageService", VillageService)
safeStart("World2Service", World2Service) -- pueblo del Mundo 2 (usa los puestos de VillageService)
safeStart("DividedLandsService", DividedLandsService) -- Mundo 2, zona 1: Tierras Divididas (fuego y hielo)
safeStart("WildsService", WildsService)
safeStart("SpawnService", SpawnService)
safeStart("EggStandService", EggStandService)
safeStart("LeaderboardService", LeaderboardService)
safeStart("ZoneService", ZoneService)
safeStart("EnemyService", EnemyService)
safeStart("LandscapeService", LandscapeService)
safeStart("CombatService", CombatService)
safeStart("WeaponService", WeaponService)
safeStart("BossRewardService", BossRewardService)
safeStart("PetCombatService", PetCombatService)
safeStart("WaveService", WaveService) -- oleadas: después de EnemyService y PetCombatService
safeStart("AbilityService", AbilityService)
safeStart("StyleService", StyleService) -- estilos de pelea: después de PetCombatService
safeStart("GearService", GearService) -- el arma, la espada o el bastón en la mano
-- Marca y combos elementales de los golpes del bastón y de las habilidades de Magia
PetCombatService.setElementHook(AbilityService.elementalHit)
safeStart("CaveService", CaveService) -- viaje a la Cueva de los Espinillos (la construye WorldService)
safeStart("RebirthService", RebirthService)
safeStart("AdventureService", AdventureService)
safeStart("RewardService", RewardService)
safeStart("ChestService", ChestService)
safeStart("NpcService", NpcService)
safeStart("QuestService", QuestService)
safeStart("TutorialService", TutorialService)

print("[REBIRTH CITY] Servidor iniciado completamente")

-- Solo en Studio: lista (sin tocar) objetos de Workspace que el juego no crea.
local WorkspaceAudit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Util.WorkspaceAudit)
task.delay(8, WorkspaceAudit.run, "servidor")
