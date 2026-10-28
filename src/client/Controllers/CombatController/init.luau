-- Combate en el cliente (solo presentación y entrada; el servidor decide todo):
-- - Disparar apuntando (AimPoint): un clic dispara hacia el cursor (mantener pulsado sigue
--   disparando y el personaje mira hacia donde apuntas); F, hacia el ratón; un toque corto
--   en el mundo, hacia el dedo; X (mando), el botón táctil ⚔ o "Disparar", hacia donde mira
--   el personaje. El servidor decide a quién da (lo que haya en el camino) y si falla, con la
--   cadencia del arma (PetCombatService). Con el pase "Disparo automático" el arma dispara
--   sola hacia donde apuntas cuando va a dar a alguien; la insignia (AUTO / OFF, o V) lo
--   enciende o apaga, y sin el pase (🔒 AUTO) abre la tienda. Sobre el botón, el arma
--   equipada y su daño por segundo. En PC el cursor es una mira.
-- - Cada disparo confirmado (PetAbility "PlayerShot") se dibuja según el proyectil del arma
--   (WeaponConfig): rayo, bola de plasma, espina, rayo de cristal que salta entre enemigos
--   o esfera que explota; luego los impactos (destello, chispas, número de daño, sonido).
--   Con el estilo Puños es un puñetazo (el personaje lanza el puño, alternando brazos, y el
--   golpe estalla en el enemigo) y con Magia un orbe que se carga en la mano (brazos al
--   frente) y viaja girando hasta explotar con un círculo de runas; con Armas el personaje
--   apunta con el brazo (CharacterPose). Los críticos (Armas) sacan el número dorado y más
--   grande. El botón dice
--   Disparar / Golpear / Lanzar y la línea de encima, el estilo y su daño por segundo.
-- - Botín: monedas (💰) y diamantes (💎) que saltan del enemigo y vuelan hacia ti al
--   cobrar, el ORBE DORADO (botín ×10) con su destello, un aviso al derrotarlo (uno solo
--   que se actualiza, para que las hordas no llenen la pila) y anuncio al derrotar a un jefe.
-- - Barra de vida grande del jefe al acercarse a su arena.
-- - Mascotas de combate: rayo del Zorrito, nova del Dragón (con aviso y recarga visible)
--   y escudo de la Tortuga, solo para acciones ya confirmadas por el servidor.
-- Interfaz con DisplayOrder 3: queda por debajo del inventario y los paneles.
--
-- Dividido en partes (Fase 3 del rediseño; mismo comportamiento): Effects, Projectiles, HitsAndGui, Input, HudAndPets, ShotEvents, RewardsAndBoss.
-- Cada parte se registra en la tabla de estado (install) y luego toma lo de las demás
-- (link); sus funciones públicas se copian aquí, a CombatController, con el mismo nombre.

local CombatController = {}

local PARTS = {
	require(script.Effects),
	require(script.Projectiles),
	require(script.HitsAndGui),
	require(script.Input),
	require(script.HudAndPets),
	require(script.ShotEvents),
	require(script.RewardsAndBoss),
}

-- Estado compartido entre las partes (lo que antes eran variables de primer nivel).
local ctx: any = {
	Service = CombatController,
	-- fxFolder: nil al empezar
	animationTrack = nil,
	hold = nil,
	magicPress = nil,
	altHeld = nil,
}

for _, part in PARTS do
	part.install(ctx)
end
for _, part in PARTS do
	part.link(ctx)
end
for _, part in PARTS do
	for name, fn in part.Api do
		assert(CombatController[name] == nil, "función pública repetida: " .. name)
		CombatController[name] = fn
	end
end

function CombatController.start()
	for _, part in PARTS do
		if part.start then
			part.start()
		end
	end
end

return CombatController
