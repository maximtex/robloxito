-- Punto de entrada del servidor. El orden importa:
-- los remotes deben existir antes de que UpgradeService y PetService conecten sus eventos.

local Services = script.Services

local RemoteService = require(Services.RemoteService)
local PlayerDataService = require(Services.PlayerDataService)
local EnergyService = require(Services.EnergyService)
local UpgradeService = require(Services.UpgradeService)
local PetService = require(Services.PetService)
local WorldService = require(Services.WorldService)
local GeneratorService = require(Services.GeneratorService)
local SpawnService = require(Services.SpawnService)
local EggStandService = require(Services.EggStandService)
local ValleyService = require(Services.ValleyService)
local ZoneService = require(Services.ZoneService)
local EnemyService = require(Services.EnemyService)
local CombatService = require(Services.CombatService)
local PetCombatService = require(Services.PetCombatService)
local QuestService = require(Services.QuestService)
local TutorialService = require(Services.TutorialService)

RemoteService.start()
PetService.start() -- registra su listener antes de que se carguen los primeros perfiles
PlayerDataService.start()
UpgradeService.start()
EnergyService.start()
WorldService.start()
ValleyService.start()
GeneratorService.start()
SpawnService.start()
EggStandService.start()
ZoneService.start() -- portales, desbloqueo y viaje entre zonas
EnemyService.start() -- enemigos, IA, arenas y recompensas
CombatService.start() -- ataque del jugador validado en el servidor
PetCombatService.start() -- habilidades de combate de las mascotas equipadas
QuestService.start() -- misiones, diarias y logros (escucha a los servicios anteriores)
TutorialService.start() -- tutorial inicial (después de QuestService: usa sus datos)

print("[REBIRTH CITY] Servidor iniciado")

-- Solo en Studio: lista (sin tocar) objetos de Workspace que el juego no crea.
local WorkspaceAudit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Util.WorkspaceAudit)
task.delay(8, WorkspaceAudit.run, "servidor")
