-- Estilos de pelea en el cliente (StyleConfig; todo lo decide StyleService):
-- - Dos botones redondos con las habilidades puestas del estilo (atributo SkillSlots,
--   SkillLogic): la de la Z (R1 del mando o tocarlo) y la de la X (L1), junto a los de las
--   habilidades elementales, cada uno con su recarga (más corta con su nivel). La insignia ⇄
--   del primero (o la tecla C) abre el panel para elegir estilo: Armas, Guerrero, Puños o
--   Magia, cada uno con su ataque, su ventaja y su desventaja, su pasiva y sus cuatro
--   habilidades. La insignia ⚡ del segundo (o la tecla B) abre las ⚡ Mejoras
--   (SkillsController).
-- - Todos: dash con Shift (o el botón 💨), con su recarga (el de Puños, mejor). Magia: el
--   teletransporte con Shift (o el botón ✨; también el clic derecho corto, CombatController).
-- - Guerrero: Salto aplastante (tu cliente hace el salto: leapMove) y la onda cortante.
-- - Combos (StyleEvent "Combo"): el nombre grande sobre el enemigo y un aviso.
-- - Efectos de las habilidades ya resueltas (StyleEvent), con el movimiento del personaje
--   (CharacterPose): Ráfaga (apunta y chispas doradas mientras dura), Granada (la lanza por
--   encima del hombro, vuela en arco y explota), Terremoto (brazos arriba y golpe al suelo:
--   onda naranja, polvo y sacudida), Embestida (puños por delante, estela y huellas de
--   viento), Meteoros (lanza el hechizo; aviso en el suelo, caída y explosión) y Nova de
--   hielo (brazos abiertos: anillo helado, carámbanos y los enemigos congelados un momento
--   dentro de un bloque de hielo). Los números de daño los dibuja CombatController.
--
-- Dividido en partes (Fase 3 del rediseño; mismo comportamiento): Gui, PrimaryFx, SecondaryFx, Startup.
-- Cada parte se registra en la tabla de estado (install) y luego toma lo de las demás
-- (link); sus funciones públicas se copian aquí, a StyleController, con el mismo nombre.

local StyleController = {}

local PARTS = {
	require(script.Gui),
	require(script.PrimaryFx),
	require(script.SecondaryFx),
	require(script.Startup),
}

-- Estado compartido entre las partes (lo que antes eran variables de primer nivel).
local ctx: any = {
	Service = StyleController,
	fxFolder = nil,
	tint = nil,
}

for _, part in PARTS do
	part.install(ctx)
end
for _, part in PARTS do
	part.link(ctx)
end
for _, part in PARTS do
	for name, fn in part.Api do
		assert(StyleController[name] == nil, "función pública repetida: " .. name)
		StyleController[name] = fn
	end
end

return StyleController
