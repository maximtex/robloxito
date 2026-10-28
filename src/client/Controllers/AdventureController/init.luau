-- Aventuras (solo presentación; el servidor decide todo):
-- - Sobre cada personaje: nombre, oficio y su aviso: "!" dorado (tiene una misión para ti),
--   "?" verde (vuelve a entregarla) o "…" (en curso). Se giran hacia el jugador cercano.
-- - Conversación (abajo, al pulsar E junto al personaje): texto con efecto de máquina de
--   escribir, objetivo con progreso, recompensa y botones Aceptar / Entregar / Ahora no.
--   Si el jugador traía un encargo para ese personaje, primero se ve la entrega.
-- - Seguimiento de las misiones en curso (columna derecha en escritorio, bajo el menú en
--   táctil) con tantas filas como quepan; avisos breves en la pila común (Toasts).
-- - Objetos perdidos: solo los ve quien tiene esa misión; brillan, flotan y tienen un haz
--   de luz para encontrarlos de lejos. El servidor los recoge al pasar cerca.
-- - Azulejo "Amuletos" en la barra del menú (tecla G): ranuras, amuletos, bendiciones e
--   historias. Bajo el menú, las bendiciones activas con su tiempo. Al conseguir un amuleto,
--   tarjeta de celebración.
--
-- Dividido en partes (Fase 3 del rediseño; mismo comportamiento): Gui, World, Dialog, Amulets, TrackerAndSync.
-- Cada parte se registra en la tabla de estado (install) y luego toma lo de las demás
-- (link); sus funciones públicas se copian aquí, a AdventureController, con el mismo nombre.

local AdventureController = {}

local PARTS = {
	require(script.Gui),
	require(script.World),
	require(script.Dialog),
	require(script.Amulets),
	require(script.TrackerAndSync),
}

-- Estado compartido entre las partes (lo que antes eran variables de primer nivel).
local ctx: any = {
	Service = AdventureController,
	state = { Ready = false },
	itemsFolder = nil,
	-- renderTracker: nil al empezar
	dialogNpc = nil,
	pending = false,
}

for _, part in PARTS do
	part.install(ctx)
end
for _, part in PARTS do
	part.link(ctx)
end
for _, part in PARTS do
	for name, fn in part.Api do
		assert(AdventureController[name] == nil, "función pública repetida: " .. name)
		AdventureController[name] = fn
	end
end

function AdventureController.start()
	for _, part in PARTS do
		if part.start then
			part.start()
		end
	end
end

return AdventureController
