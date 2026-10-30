-- Oleadas: la mecánica principal (WaveConfig). Partidas PRIVADAS en el círculo de cada zona
-- (WaveConfig.Places: Bosque (en la sala del altar de la Cueva de los Espinillos), Valle y
-- Caldera), con los enemigos y el jefe de esa zona:
-- 1. Se empieza con E en el altar del centro (ProximityPrompt) o con WaveAction ("Start").
--    Cada jugador juega SU partida; quien pulse E durante la cuenta atrás de otra (del mismo
--    modo) se une a ella, para jugar con amigos. Varias partidas pueden ir a la vez.
-- 2. Mientras juegas, el resto de enemigos desaparece para ti y no te ataca: solo ves y
--    golpeas los de tu partida (atributo WaveRun en el jugador y en los enemigos;
--    EnemyService filtra y el cliente oculta, WaveVisibility).
-- 3. Oleadas de hordas (WaveLogic.spawnList): los enemigos salen de la reserva de
--    EnemyService (spawnPooled) de pocos en pocos, con más vida cuanto más avanzada la
--    oleada y cuantos más jugadores. Al limpiar una oleada, premio para todos.
-- 4. Cada pocas oleadas, cada jugador elige 1 de 3 mejoras (WaveLogic.rollCards) que duran
--    la partida: el arma (PetCombatService.setShotModifier), el botín y la racha
--    (EnemyService.setKillModifier), y explosiones y curación al matar (aquí).
-- 5. La última oleada trae un jefe (uno para cada partida) con escolta. Si cae: victoria y
--    premio (WaveLogic.victoryReward), además de su botín de siempre (BossRewardService:
--    cuenta para abrir la zona siguiente y su arma la primera vez). Los modos sin jefe (la
--    práctica del tutorial) se ganan al limpiar la última oleada. En las mazmorras, además,
--    un COFRE para cada uno (Arenas.*.Chest: 💰 y a veces una poción; "Chest" al cliente,
--    que lo dibuja delante del altar y lo abre). En el Valle y la Caldera algunos bichos de
--    las hordas salen élite (Arenas.*.EliteChance; EnemyService, su propia reserva).
-- 6. Si no queda nadie de la partida dentro y vivo durante LeaveGrace segundos, se pierde:
--    los enemigos se retiran sin botín (lo ganado hasta ahí se queda).
-- Modos: "Tutorial" en el altar de la práctica (Places.Practice, en el Bosque de Espinas) para quien
-- está en ese paso del tutorial (partida corta con consejos en pantalla, "Hint"); a los demás
-- ese altar les dice que las oleadas están en la cueva. Ganar suma WaveWins (GameEvents
-- "WaveWon").
-- Dentro de la partida se apunta y se dispara igual que fuera (sin disparo automático gratis).
-- Todo lo decide el servidor; el cliente (WaveController) solo dibuja lo que se le manda.

--
-- Dividido en partes (Fase 3 del rediseño; mismo comportamiento): Core, Net, Spawns, Waves, Results, Flow, Altar, Startup.
-- Cada parte se registra en la tabla de estado (install) y luego toma lo de las demás
-- (link); sus funciones públicas se copian aquí, a WaveService, con el mismo nombre.

local WaveService = {}

local PARTS = {
	require(script.Core),
	require(script.Net),
	require(script.Spawns),
	require(script.Waves),
	require(script.Results),
	require(script.Flow),
	require(script.Altar),
	require(script.Startup),
}

-- Estado compartido entre las partes (lo que antes eran variables de primer nivel).
local ctx: any = {
	Service = WaveService,
	nextRunId = 0,
	-- eventRemote: nil al empezar
}

for _, part in PARTS do
	part.install(ctx)
end
for _, part in PARTS do
	part.link(ctx)
end
for _, part in PARTS do
	for name, fn in part.Api do
		assert(WaveService[name] == nil, "función pública repetida: " .. name)
		WaveService[name] = fn
	end
end

return WaveService
