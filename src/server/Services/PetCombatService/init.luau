-- Ataque del jugador (el único camino de sus golpes básicos) y golpes de sus mascotas. El
-- cliente manda hacia dónde apunta y qué hace (CombatService.onShotRequest); aquí se decide
-- todo, según el estilo de pelea (PetData.Style; StyleLogic):
-- - Armas: disparo con el arma de fuego (GunLogic, WeaponConfig.Guns): pistola, rifle,
--   escopeta (perdigones en abanico), francotirador (atraviesa a varios) o bazuca (cohete que
--   tarda en llegar y explota). Cada bala va hacia el punto apuntado con su desvío (menos
--   apuntando: "AdsOn"/"AdsOff") y da a lo que haya en su camino (AimLogic). Cargador: cada
--   disparo gasta una bala; vacío, recarga solo ("Reload" recarga antes). La Ráfaga no gasta.
-- - Magia (MagicLogic): la bola persigue al bicho más cercano al punto apuntado (LockRadius);
--   gasta maná (sin maná, chispa débil). Mantener ("Charge" → "Release") carga un orbe
--   gigante. El elemento del bastón deja su marca y dispara combos (setElementHook,
--   AbilityService) y tiene su efecto (frena, debilita, cura, salta).
-- - Guerrero (WarriorLogic): combo de 3 tajos a todos los del arco de enfrente (el 3.º,
--   alrededor). Bloquear ("BlockOn"/"BlockOff"): menos daño; la parada perfecta (blockIncoming,
--   desde StyleService) aturde al bicho y el siguiente tajo es un contraataque.
-- - Puños: el más cercano en el arco de enfrente.
-- - Un clic ("Shot") es un golpe (espera a la cadencia si hace falta); mantener pulsado
--   ("Hold") sigue a la cadencia hasta "Release" o HOLD_SECONDS sin aviso.
-- - Con el pase "Disparo automático" y el automático encendido, el cliente manda hacia dónde
--   apunta ("Aim") y se ataca solo a la cadencia, pero solo cuando el golpe va a dar a alguien.
-- - El enemigo al que le das pasa a ser el objetivo: sus mascotas lo atacan y se ve su barra
--   de vida. Se olvida si muere, se aleja más de MAX_ENGAGE_RANGE o llevas TARGET_MEMORY sin
--   darle (ni con el arma ni con una habilidad).
-- - El daño sale del arma, la espada, los guantes o el bastón equipados
--   (PlayerDataService.combatStats) con su efecto (WeaponConfig: área, salto, frenar), la
--   clase activa del estilo (ClassLogic.mods) y las mejoras de la partida de oleadas
--   (setShotModifier, WaveLogic.Mods). Todo se calcula aquí; el cliente solo dibuja
--   (PetAbility "PlayerShot", "ShotImpact", "Parry", "Charging").
-- - Cada mascota equipada golpea al objetivo cada PET_HIT_INTERVAL.
-- Un único bucle para todos los jugadores (STEP_SECONDS); varios golpes por paso si la
-- cadencia es más rápida que el bucle.

--
-- Dividido en partes (Fase 3 del rediseño; mismo comportamiento): Core, Hits, Gun, Magic, Melee, Step, StyleApi, Startup.
-- Cada parte se registra en la tabla de estado (install) y luego toma lo de las demás
-- (link); sus funciones públicas se copian aquí, a PetCombatService, con el mismo nombre.

local PetCombatService = {}

local PARTS = {
	require(script.Core),
	require(script.Hits),
	require(script.Gun),
	require(script.Magic),
	require(script.Melee),
	require(script.Step),
	require(script.StyleApi),
	require(script.Startup),
}

-- Estado compartido entre las partes (lo que antes eran variables de primer nivel).
local ctx: any = {
	Service = PetCombatService,
	-- abilityRemote: nil al empezar
	shotModifier = nil,
	elementHook = nil,
}

for _, part in PARTS do
	part.install(ctx)
end
for _, part in PARTS do
	part.link(ctx)
end
for _, part in PARTS do
	for name, fn in part.Api do
		assert(PetCombatService[name] == nil, "función pública repetida: " .. name)
		PetCombatService[name] = fn
	end
end

return PetCombatService
