-- Habilidades elementales en el cliente (solo presentación y entrada; el servidor decide todo):
-- - Dos botones redondos junto al de ataque: ★ Q (elemento principal) y ◆ R (secundario,
--   cuando lo hay). Cada uno con el icono y el nombre de su habilidad y la recarga de SU
--   elemento que confirma el servidor (AbilityResult). Mando: Y (principal) y B (secundario).
-- - Efectos de cada habilidad y de cada combo SOLO para acciones ya resueltas (AbilityEvent).
--   Los números de daño y destellos reutilizan los del combate (CombatController).
-- - Sensación para quien la lanza: sacudida de cámara, pequeño golpe de zoom, destello de
--   pantalla del color del elemento y gesto del avatar (animaciones de su script Animate).
--   Con "Reducir movimiento" activado en los ajustes de Roblox no hay sacudida ni zoom.
-- - Sonidos por elemento y por combo (AbilityConfig.Sounds), en 3D donde ocurre.
-- - Estados sobre los enemigos (quemado, ralentizado, inmovilizado, aturdido, marcado) y su
--   marca elemental para los combos (icono sobre la barra de vida), a partir de los
--   atributos que publica el servidor.
-- El elemento de cada hueco replica la regla del servidor: principal = el seleccionado si
-- está despierto (si no, Naturaleza); secundario = SecondaryCore si es válido.
--
-- Dividido en partes (Fase 3 del rediseño; mismo comportamiento): Helpers, AbilityFx, ReactionsAndStatus, Gui, Startup.
-- Cada parte se registra en la tabla de estado (install) y luego toma lo de las demás
-- (link); sus funciones públicas se copian aquí, a AbilityController, con el mismo nombre.

local AbilityController = {}

local PARTS = {
	require(script.Helpers),
	require(script.AbilityFx),
	require(script.ReactionsAndStatus),
	require(script.Gui),
	require(script.Startup),
}

-- Estado compartido entre las partes (lo que antes eran variables de primer nivel).
local ctx: any = {
	Service = AbilityController,
	-- fxFolder: nil al empezar
	flashFrame = nil,
}

for _, part in PARTS do
	part.install(ctx)
end
for _, part in PARTS do
	part.link(ctx)
end
for _, part in PARTS do
	for name, fn in part.Api do
		assert(AbilityController[name] == nil, "función pública repetida: " .. name)
		AbilityController[name] = fn
	end
end

return AbilityController
