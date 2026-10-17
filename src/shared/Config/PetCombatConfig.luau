-- Habilidades de combate de las mascotas. Solo actúan las especies con entrada en
-- Abilities; el resto conserva únicamente su bonificación de energía (PetMath).
-- Todo lo ejecuta el servidor (PetCombatService); el cliente solo dibuja los efectos.
--
-- El daño de las mascotas es una FRACCIÓN del daño del jugador (CombatMath.playerDamage),
-- así que crece con las mejoras y nunca las sustituye:
-- - Zorrito: 0.35 × daño cada 1.2 s ≈ +15 % del daño por segundo del jugador por zorrito.
-- - Dragón: 2 × daño en área (hasta 6 enemigos) cada 10 s.
-- Ejemplo a nivel 10 con ×1.35: jugador 35.25/golpe; zorrito 12.3; nova del dragón 70.5.

local PetCombatConfig = {
	TickSeconds = 0.25, -- un único bucle para todos los jugadores
	EngageWindow = 6, -- las mascotas ayudan hasta 6 s después del último golpe del jugador
	BroadcastRange = 150, -- jugadores que ven los efectos de las mascotas de otro

	Abilities = {
		QuartzFox = {
			Type = "Bolt", -- ataca al enemigo que el jugador está golpeando
			Interval = 1.2,
			DamageRatio = 0.35,
			Range = 22, -- distancia máxima jugador -> objetivo
		},
		CrystalTurtle = {
			Type = "Guard", -- reduce el daño recibido de los enemigos
			ReductionPerPet = 0.15,
			MaxReduction = 0.35, -- tope: nunca invulnerable
		},
		AmethystDragon = {
			Type = "Nova", -- área alrededor del objetivo, con aviso previo
			Cooldown = 10,
			Telegraph = 0.8,
			DamageRatio = 2,
			Radius = 10,
			Range = 24,
			MaxTargets = 6,
		},
	},
}

return PetCombatConfig
