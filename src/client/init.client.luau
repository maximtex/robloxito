-- Punto de entrada del cliente.
-- Los módulos que no esperan a nada arrancan primero; los que esperan a los remotes,
-- después. PetController va en su propio hilo para no retrasar el HUD.

local GeneratorAnimator = require(script.Controllers.GeneratorAnimator)
local CrystalAppearance = require(script.Controllers.CrystalAppearance)
local HudController = require(script.Controllers.HudController)
local PetFollower = require(script.Controllers.PetFollower)
local PetController = require(script.Controllers.PetController)
local PortalController = require(script.Controllers.PortalController)
local CombatController = require(script.Controllers.CombatController)
local QuestController = require(script.Controllers.QuestController)
local DataStatusController = require(script.Controllers.DataStatusController)
local TutorialController = require(script.Controllers.TutorialController)

GeneratorAnimator.start()
CrystalAppearance.start()
PetFollower.start()
task.spawn(PetController.start)
task.spawn(PortalController.start)
task.spawn(CombatController.start)
task.spawn(QuestController.start)
task.spawn(DataStatusController.start)
task.spawn(TutorialController.start)
-- Solo en Studio: lista (sin tocar) objetos de Workspace que el juego no crea.
local WorkspaceAudit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Util.WorkspaceAudit)
task.delay(10, WorkspaceAudit.run, "cliente")
HudController.start({
	onPurchaseSuccess = GeneratorAnimator.playPurchaseBurst,
})

-- Si este mensaje no aparece en la Salida, no hay ningún cliente conectado (p. ej. Studio
-- en modo Run/F8, o se está mirando la ventana del servidor).
print("[REBIRTH CITY] Cliente iniciado")
