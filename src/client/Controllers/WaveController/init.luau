-- Oleadas en el cliente (solo presentación; WaveService decide todo):
-- - Panel arriba al centro (en el hueco de la barra del jefe, bajo el tutorial) mientras
--   juegas una partida: oleada, enemigos que quedan y cuenta atrás. En la del jefe se
--   esconde y se ve la barra del jefe.
-- - Anuncios grandes en el centro: cuenta atrás, "OLEADA 4", "¡JEFE!".
-- - Consejos de la partida de práctica del tutorial ("Hint"), en un cartel abajo, justo
--   encima de la fila del menú: el centro queda libre para ver al personaje y los avisos.
-- - Las partidas son privadas: el servidor solo manda el estado de la tuya (y el altar
--   esconde su "Pulsa E" mientras juegas). Qué enemigos ves lo decide WaveVisibility.
-- - Mejoras: tres tarjetas para elegir (clic o teclas 1, 2, 3) con su tiempo.
-- - Resumen al terminar (victoria o caída): enemigos, 💎, 💰, orbes dorados, mejor racha y
--   tu récord en ese modo (aviso "Record" en cuanto lo superas).
-- - Modo infinito: al caer el jefe, ventana para elegir si sigues ("Endless", true/false);
--   después las oleadas se cuentan sin tope ("♾️ OLEADA 14").
-- - Racha: contador "x12" sobre tu cabeza mientras matas sin parar (atributos Streak y
--   StreakUntil de EnemyService), con el multiplicador de botín que da.
-- - Explosiones de la mejora "Reacción en cadena".
-- - Sonidos y efectos de cada momento (WaveFx): golpe y onda al empezar oleada, chispas al
--   superarla, gong y viñeta roja con el jefe, confeti en la victoria y el récord, pantalla
--   gris al caer.

--
-- Dividido en partes (Fase 3 del rediseño; mismo comportamiento): Gui, HudAndFx, CardsAndSummary, EventsAndStreak
-- y Difficulty (la ventana para elegir la dificultad de la mazmorra).
-- Cada parte se registra en la tabla de estado (install) y luego toma lo de las demás
-- (link); sus funciones públicas se copian aquí, a WaveController, con el mismo nombre.

local WaveController = {}

local PARTS = {
	require(script.Gui),
	require(script.HudAndFx),
	require(script.CardsAndSummary),
	require(script.EventsAndStreak),
	require(script.Difficulty),
}

-- Estado compartido entre las partes (lo que antes eran variables de primer nivel).
local ctx: any = {
	Service = WaveController,
	current = nil, -- estado de mi partida (solo llega el de la tuya)
	lastPhase = nil,
	lastWave = 0,
	cardData = nil,
	resultToken = 0,
	pickedHere = false, -- elegiste tú la mejora (si no, la eligió el servidor al acabarse el tiempo)
	celebratedRun = nil, -- partida cuya victoria ya se celebró (al caer el jefe)
	hintToken = 0,
}

for _, part in PARTS do
	part.install(ctx)
end
for _, part in PARTS do
	part.link(ctx)
end
for _, part in PARTS do
	for name, fn in part.Api do
		assert(WaveController[name] == nil, "función pública repetida: " .. name)
		WaveController[name] = fn
	end
end

function WaveController.start()
	for _, part in PARTS do
		if part.start then
			part.start()
		end
	end
end

return WaveController
