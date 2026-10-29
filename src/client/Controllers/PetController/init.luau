-- Interfaz de mascotas:
-- - Azulejo "Mascotas" en la barra del menú (o tecla P) que abre el inventario para equipar
--   y desequipar. Lleva un "!" si hay un hueco libre y mascotas sin equipar.
-- - Panel del huevo al usar un santuario: precio, requisito, probabilidades reales y
--   apertura en tres tiempos (incubación con temblor, brillo y grietas; destello;
--   revelación con el modelo de la mascota, su rareza y su bonificación).
-- Solo envía solicitudes; el servidor decide el resultado y manda el inventario real.
-- Inventario y huevo son paneles modales del PanelManager: uno a la vez, se cierran con
-- su botón o con Escape, y el huevo no se puede cerrar a mitad de una apertura.
-- Cada compra lleva un requestId: si no llega respuesta se reenvía UNA vez con el mismo
-- id, y el servidor devuelve el mismo resultado sin cobrar ni sortear de nuevo.

--
-- Dividido en partes (Fase 3 del rediseño; mismo comportamiento): Gui, InventoryAndEvo, EggPanel, HatchSequence.
-- Cada parte se registra en la tabla de estado (install) y luego toma lo de las demás
-- (link); sus funciones públicas se copian aquí, a PetController, con el mismo nombre.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared.Config.PetConfig)

local PetController = {}

local PARTS = {
	require(script.Gui),
	require(script.InventoryAndEvo),
	require(script.EggPanel),
	require(script.HatchSequence),
}

-- Estado compartido entre las partes (lo que antes eran variables de primer nivel).
local ctx: any = {
	Service = PetController,
	snapshot = { Ready = false, Pets = {}, Equipped = {}, MaxEquipped = PetConfig.MaxEquipped, MaxInventory = PetConfig.MaxInventory },
	currentEggId = nil,
	currentPromptPart = nil,
	phase = "idle",
	incubating = false, -- true solo durante "incubating" (impide cerrar por distancia)
	currentRequestId = nil,
	pendingResult = nil, -- resultado ya recibido; se revela al acabar la secuencia
	sequenceToken = 0,
	animationConnection = nil,
	lastCount = 1, -- huevos de la última apertura («Otro» repite lo mismo)
}

for _, part in PARTS do
	part.install(ctx)
end
for _, part in PARTS do
	part.link(ctx)
end
for _, part in PARTS do
	for name, fn in part.Api do
		assert(PetController[name] == nil, "función pública repetida: " .. name)
		PetController[name] = fn
	end
end

function PetController.start()
	for _, part in PARTS do
		if part.start then
			part.start()
		end
	end
end

return PetController
