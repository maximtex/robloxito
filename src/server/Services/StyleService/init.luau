-- Estilos de pelea (StyleConfig): elegir estilo, sus pasivas fuera del disparo, sus
-- habilidades (4 por estilo, 2 puestas: SkillLogic), los combos, el dash de Puños y el
-- teletransporte de Magia. El
-- disparo de cada estilo (alcance, ritmo, daño, crítico, robo de vida y los combos de golpes)
-- lo hace PetCombatService; aquí:
-- - StyleAction("Set", styleId): cambia el estilo (con una espera corta entre cambios), se
--   guarda en PetData.Style y se replica (atributo CombatStyle; la velocidad al caminar y la
--   vida las pone PlayerDataService con StyleLogic).
-- - StyleAction("Pick", styleId): la elección del estilo al empezar (StylePicker): lo pone y
--   marca PetData.Skills.Picked (ya no se vuelve a preguntar).
-- - StyleAction("Ability", slot, aimPoint): usa la habilidad puesta en la Z (1) o la X (2)
--   si está lista, hacia el punto al que apuntas (el ratón; con el botón, delante). Todo lo
--   decide el servidor:
--     Armas:  Ráfaga, Granada (cae donde apuntas), Rayo perforante (franja recta hacia donde
--             apuntas) y Torreta (dispara sola al más cercano un rato).
--     Guerrero: Giro de acero (tajos alrededor), Salto aplastante (HANDLERS.Leap: saltas
--             hacia donde apuntas y al caer golpeas, aturdes y empujas alrededor), Grito de
--             guerra (como la Furia, y pegas más fuerte) y Onda cortante (franja recta).
--     Puños:  Terremoto, Embestida, Furia (pegas más rápido y recibes la mitad) y Torbellino
--             (4 golpes alrededor que atraen).
--     Magia:  Meteoros (donde apuntas), Nova de hielo, Cadena de rayos (empieza en el enemigo
--             junto a donde apuntas, salta de enemigo en enemigo y aturde) y Agujero negro
--             (donde apuntas: atrae y daña, y al final explota).
--   Las de Magia gastan maná (ManaCost; sin maná: Result "NoMana"). Una habilidad con Base
--   usa el efecto de otra (también en cadena: la del Mundo 2 sobre la del Mundo 1).
--   El daño son múltiplos del DPS del estilo × el nivel de la habilidad (SkillLogic.power)
--   y pasa por EnemyService.damage (mismas recompensas y muertes). La recarga es por
--   habilidad (cambiar de estilo o de hueco no la reinicia; la acorta su nivel) y se replica
--   en StyleReadyAt (Z) y StyleReadyAt2 (X).
-- - StyleAction("BuySkill" | "UpgradeSkill", skillId) y ("EquipSkill", skillId, slot):
--   comprar y subir con 💎 (profile.Diamonds) y ponerla en la Z o la X (SkillLogic valida).
-- - StyleAction("Dash"): el dash de Puños (StyleConfig.Styles.Fists.Dash): un salto corto
--   hacia donde te mueves, sin cruzar paredes ni puertas cerradas; DashReadyAt.
-- - StyleAction("Blink", aimPoint): el teletransporte de Magia (StyleConfig.Styles.Magic.Blink)
--   hacia el punto (o hacia donde te mueves), gasta maná y comparte DashReadyAt.
-- - Combos de habilidades (COMBO): una habilidad que da a un enemigo aturdido o congelado
--   (Terremoto, Embestida, Nova, Cadena de rayos) hace ×1.5 («¡Remate!», «¡Hielo roto!»…);
--   con tu Ráfaga o tu Furia activas, las demás habilidades hacen ×1.4; y a un enemigo con
--   la marca de un elemento (las habilidades elementales Q/R, AbilityService) le hace ×1.5 y
--   gasta la marca («¡Combo elemental!»). Se multiplican, hasta ×COMBO.Max.
-- - Daño que recibe el jugador según el estilo (Puños y Guerrero menos, Armas más; la Furia,
--   la mitad; bloqueando con el Guerrero, PetCombatService.blockIncoming).
-- - Clases (ClassConfig, ClassLogic): StyleAction("BuyClass" | "UpgradeClass", classId) y
--   ("SelectClass", classId): comprar y subir con 💎 y elegir la activa de su estilo. Sus
--   pasivas, aquí: daño y recarga de las habilidades, recarga del dash, daño que recibes y
--   daño a los jefes (gancho de EnemyService); las demás en PetCombatService y PlayerDataService.
-- - StyleEvent: efectos ya resueltos a quien la usa y a los cercanos; "Result" solo a él.

--
-- Dividido en partes (Fase 3 del rediseño; mismo comportamiento): Core, Cast, Abilities, Actions, Startup.
-- Cada parte se registra en la tabla de estado (install) y luego toma lo de las demás
-- (link); sus funciones públicas se copian aquí, a StyleService, con el mismo nombre.

local StyleService = {}

local PARTS = {
	require(script.Core),
	require(script.Cast),
	require(script.Abilities),
	require(script.Actions),
	require(script.Startup),
}

-- Estado compartido entre las partes (lo que antes eran variables de primer nivel).
local ctx: any = {
	Service = StyleService,
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
		assert(StyleService[name] == nil, "función pública repetida: " .. name)
		StyleService[name] = fn
	end
end

return StyleService
