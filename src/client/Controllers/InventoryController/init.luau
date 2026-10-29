-- 🎒 Inventario (tecla I): lo que tiene el jugador, en cuatro pestañas (solo presentación;
-- todo lo decide el servidor: ItemService y WeaponService).
-- - ⚔️ Armas: las que tiene, con su nivel. Clic = equiparla (WeaponAction "Equip").
-- - 🥚 Huevos: los que soltaron los jefes. Clic = abrirlo aquí mismo (ItemAction "OpenEgg"),
--   con su presentación de la mascota.
-- - 🧪 Artículos: pociones. Clic = tomarla (ItemAction "UsePotion"); la activa muestra su tiempo.
-- - 🏅 Títulos: los conseguidos (clic = ponerlo encima de tu cabeza o quitarlo) y los que
--   faltan, con lo que piden y cuánto llevas.
-- Además: las pociones activas abajo a la izquierda con su cuenta atrás, el aviso del botín
-- de los jefes y de los títulos nuevos, y el número de cosas nuevas en el azulejo del menú.

--
-- Dividido en partes (Fase 3 del rediseño; mismo comportamiento): HelpersAndDraw, Gui, Tabs, RevealAndSync.
-- Cada parte se registra en la tabla de estado (install) y luego toma lo de las demás
-- (link); sus funciones públicas se copian aquí, a InventoryController, con el mismo nombre.

local InventoryController = {}

local PARTS = {
	require(script.HelpersAndDraw),
	require(script.Gui),
	require(script.Tabs),
	require(script.RevealAndSync),
}

-- Estado compartido entre las partes (lo que antes eran variables de primer nivel).
local ctx: any = {
	Service = InventoryController,
	state = { Ready = false, Potions = {}, Eggs = {}, Boosts = {}, Titles = {}, Title = "", Progress = {} },
	boostEnds = {},
	currentTab = "Weapons",
	-- render: nil al empezar
}

for _, part in PARTS do
	part.install(ctx)
end
for _, part in PARTS do
	part.link(ctx)
end
for _, part in PARTS do
	for name, fn in part.Api do
		assert(InventoryController[name] == nil, "función pública repetida: " .. name)
		InventoryController[name] = fn
	end
end

function InventoryController.start()
	for _, part in PARTS do
		if part.start then
			part.start()
		end
	end
end

return InventoryController
