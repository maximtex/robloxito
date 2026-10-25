-- Punto de entrada del cliente.
-- Los módulos que no esperan a nada arrancan primero; los que esperan a los remotes,
-- después. PetController va en su propio hilo para no retrasar el HUD.

local GeneratorAnimator = require(script.Controllers.GeneratorAnimator)
local CrystalAppearance = require(script.Controllers.CrystalAppearance)
local CoreShrineController = require(script.Controllers.CoreShrineController)
local EggShrineAnimator = require(script.Controllers.EggShrineAnimator)
local HudController = require(script.Controllers.HudController)
local PetFollower = require(script.Controllers.PetFollower)
local PetController = require(script.Controllers.PetController)
local PortalController = require(script.Controllers.PortalController)
local CombatController = require(script.Controllers.CombatController)
local WaveVisibility = require(script.Controllers.WaveVisibility)
local WaveController = require(script.Controllers.WaveController)
local WeaponController = require(script.Controllers.WeaponController)
local AbilityController = require(script.Controllers.AbilityController)
local StyleController = require(script.Controllers.StyleController)
local SkillsController = require(script.Controllers.SkillsController)
local ClassesController = require(script.Controllers.ClassesController)
local StylePickerController = require(script.Controllers.StylePickerController)
local QuestController = require(script.Controllers.QuestController)
local CoreController = require(script.Controllers.CoreController)
local DataStatusController = require(script.Controllers.DataStatusController)
local TutorialController = require(script.Controllers.TutorialController)
local RebirthController = require(script.Controllers.RebirthController)
local AdventureController = require(script.Controllers.AdventureController)
local RewardsController = require(script.Controllers.RewardsController)
local ShopController = require(script.Controllers.ShopController)
local InventoryController = require(script.Controllers.InventoryController)
local WorldPromptController = require(script.Controllers.WorldPromptController)
local DayNightController = require(script.Controllers.DayNightController)
local AmbientController = require(script.Controllers.AmbientController)
local CaveController = require(script.Controllers.CaveController)
local ChestController = require(script.Controllers.ChestController)
local LeaderboardController = require(script.Controllers.LeaderboardController)

GeneratorAnimator.start()
CrystalAppearance.start()
CoreShrineController.start()
EggShrineAnimator.start() -- los huevos de los santuarios flotan y giran
PetFollower.start()
WaveVisibility.start() -- oleadas privadas: solo se ven los enemigos de tu partida (o del mundo)
task.spawn(PetController.start)
task.spawn(PortalController.start)
task.spawn(CombatController.start)
task.spawn(WaveController.start) -- oleadas: panel, mejoras, resumen y racha
task.spawn(WeaponController.start) -- Armería: comprar, equipar y mejorar armas (L)
task.spawn(AbilityController.start) -- habilidad elemental (Q), junto al botón de ataque
task.spawn(StyleController.start) -- estilo de pelea (C), sus habilidades (Z y X) y el dash de Puños
task.spawn(SkillsController.start) -- ⚡ Mejoras: comprar, subir y poner las habilidades (B)
task.spawn(ClassesController.start) -- 🎭 Clases: la pasiva de cada estilo, con 💎 (H)
task.spawn(StylePickerController.start) -- elegir estilo al empezar (jugador nuevo)
task.spawn(QuestController.start)
task.spawn(CoreController.start)
task.spawn(DataStatusController.start)
task.spawn(TutorialController.start)
task.spawn(RebirthController.start) -- renacer: panel, tienda de fichas y corona del cristal
task.spawn(AdventureController.start) -- personajes, misiones opcionales, amuletos y bendiciones
task.spawn(RewardsController.start) -- premio diario y códigos (🎁 Premios)
task.spawn(ShopController.start) -- pases y compras de energía (💎 Tienda)
task.spawn(InventoryController.start) -- 🎒 Inventario: armas, huevos, pociones y títulos (I)
WorldPromptController.start() -- avisos del pueblo que abren Tienda, Premios y Misiones
DayNightController.start() -- ciclo de día y noche (misma hora para todos)
AmbientController.start() -- pájaros, mariposas, luciérnagas y sonido del bosque
task.spawn(CaveController.start) -- Cueva de los Espinillos: fundido al entrar y salir, cartel de cada sala y eco
task.spawn(ChestController.start) -- cofres escondidos: abiertos o cerrados para este jugador
LeaderboardController.start() -- tu fila en las tablas de clasificación
-- Solo en Studio: lista (sin tocar) objetos de Workspace que el juego no crea.
local WorkspaceAudit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Util.WorkspaceAudit)
task.delay(10, WorkspaceAudit.run, "cliente")
HudController.start()

-- Si este mensaje no aparece en la Salida, no hay ningún cliente conectado (p. ej. Studio
-- en modo Run/F8, o se está mirando la ventana del servidor).
print("[REBIRTH CITY] Cliente iniciado")
