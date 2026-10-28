-- Enemigos PvE de todas las zonas (EnemyConfig):
-- - Modelos nativos provisionales por estilo, con Humanoid para moverse por el terreno
--   (MoveTo en línea recta; si se atascan al volver, reaparecen en su origen).
-- - UNA sola IA para todos (un bucle cada AiTickSeconds): Idle, Chase, Attack, Return, Dead.
--   Persiguen solo dentro de su radio, nunca entran en zonas protegidas (spawn, cristal,
--   portales, santuarios) y vuelven a casa si se alejan demasiado (curándose al llegar).
-- - Jefes: golpe normal + golpe en área anunciado en el suelo (un disco que se llena
--   marca el momento exacto y una onda expansiva el impacto) + furia bajo la mitad de vida
--   (aura y ojos encendidos). Los efectos son solo visuales y se limpian con Debris.
-- - Daño y muerte con EnemyLogic: la muerte se decide una sola vez por vida y la
--   recompensa en dinero se reparte por daño, sumándola a profile.Money (paga la Tienda de
--   Láser) y replicándola con PlayerDataService. Cada golpe suelta además un poco de dinero.
--   El cliente recibe dónde estaba el enemigo para dibujar las monedas que salen de él.
-- - Atacan a los jugadores que se acercan (DetectRange) o que les disparan dentro de su
--   radio; el daño respeta el escudo de aparición y la defensa de las tortugas. Cada golpe se
--   prepara quieto y avisado (AttackWindup; atributos AttackTarget, AttackDir, AttackReach y
--   AttackAt) y solo alcanza por delante: se puede esquivar, bloquear o parar (Guerrero).
-- - Al morir el modelo se retira (tras dejar que el cliente lo disuelva) y reaparece tras
--   RespawnSeconds, reutilizando el mismo modelo (sin crear ni filtrar instancias ni conexiones).
-- - Presentación: las piezas van unidas con Motor6D por grupos (cuerpo, brazos, piernas)
--   y el modelo publica atributos (SpawnedAt, AttackAt, SlamAt, DiedAt) que el cliente
--   usa para animarlo (EnemyAnimator). No cambian estadísticas, IA ni recompensas.
-- - Estados de las habilidades elementales (AbilityService): ralentizar, inmovilizar,
--   aturdir y marcar (más daño recibido), con EnemyLogic. Se borran al morir, reaparecer
--   o volver a casa. Publica <Estado>Until (hora del servidor) para los efectos del cliente.
-- - Marca elemental de los combos (Aura / AuraUntil) y retroceso breve al recibir una
--   habilidad fuerte (nunca los jefes).
-- - Cada enemigo derrotado da también 💎 (DiamondService.grant: EconomyConfig.KillDiamonds
--   de su tipo · DiamondTier de su zona · multiplicador de 💎 del jugador), sube la
--   RACHA del jugador (WaveLogic: multiplica el botín mientras mate sin parar; atributos
--   Streak y StreakUntil) y a veces suelta un ORBE DORADO (botín ×10, nunca un jefe).
--   setKillModifier deja que WaveService añada lo de las mejoras de la partida.
-- - Oleadas (WaveService): enemigos de una reserva (spawnPooled) que se crean una vez,
--   no reaparecen solos al morir y vuelven a la reserva; y jefes que solo salen en la
--   última oleada (setBossWaveControlled / wakeBoss). Al morir avisan a OnWaveDeath.
-- - Oleadas PRIVADAS: los enemigos de una partida llevan su número (Run, atributo WaveRun en
--   el modelo y en sus efectos) y los jugadores que la juegan, el atributo WaveRun. Solo se
--   persiguen, se golpean y se hacen daño los del mismo "mundo" (nil = el mundo normal);
--   el cliente oculta lo de los demás (WaveVisibility). Los de las partidas no chocan con
--   los jugadores ni entre ellos (grupo de colisión WaveEnemies) y no tienen zonas seguras.

--
-- Dividido en partes (Fase 3 del rediseño; mismo comportamiento): Core, Rigs, Life, Damage, Ai, BossBrain, BossAttacks, Spawning, Startup.
-- Cada parte se registra en la tabla de estado (install) y luego toma lo de las demás
-- (link); sus funciones públicas se copian aquí, a EnemyService, con el mismo nombre.

local Types = require(script.Types)
export type WaveSpawnOptions = Types.WaveSpawnOptions

local EnemyService = {}

local PARTS = {
	require(script.Core),
	require(script.Rigs),
	require(script.Life),
	require(script.Damage),
	require(script.Ai),
	require(script.BossBrain),
	require(script.BossAttacks),
	require(script.Spawning),
	require(script.Startup),
}

-- Estado compartido entre las partes (lo que antes eran variables de primer nivel).
local ctx: any = {
	Service = EnemyService,
	killModifier = nil,
	incomingModifier = nil,
	outgoingModifier = nil,
	-- folder: nil al empezar
	-- rewardRemote: nil al empezar
	waveSlots = 0, -- grupos de partida registrados
	-- fxFolder: nil al empezar
}

for _, part in PARTS do
	part.install(ctx)
end
for _, part in PARTS do
	part.link(ctx)
end
for _, part in PARTS do
	for name, fn in part.Api do
		assert(EnemyService[name] == nil, "función pública repetida: " .. name)
		EnemyService[name] = fn
	end
end

return EnemyService
