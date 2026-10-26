-- Combate del jugador: daño, alcance y ritmo. El servidor calcula el daño real con
-- CombatMath; el cliente solo usa estos valores para la interfaz.
--
-- El daño de cada disparo lo pone el arma equipada (WeaponConfig, WeaponLogic.shotDamage).
-- Las mascotas aportan PetDamageShare de su bonificación al daño (ej. ×1.35 -> +17.5 %).
-- CombatMath.playerDamage (BaseDamage + DamagePerLevel · nivel) queda como fórmula de
-- referencia de las pruebas antiguas.

local CombatConfig = {
	BaseDamage = 10,
	DamagePerLevel = 2,
	PetDamageShare = 0.5,
	PetMoneyShare = 0.5, -- y la mitad de su bonificación al dinero de los enemigos

	-- Se apunta con el ratón o el toque (AimPoint): el disparo va hacia ese punto y da a quien
	-- esté en el camino (PetCombatService, AimLogic), con la cadencia y el alcance de WeaponConfig.
	AimRadius = 1, -- margen (studs) alrededor del cuerpo del enemigo para que el cursor lo apunte a él

	-- Animación de ataque. Orden de preferencia:
	-- 1. AttackAnimationId: un rbxassetid://... propio (sin configurar).
	-- 2. UseAvatarSlashAnimation: reutiliza la animación "toolslash" que trae el script
	--    Animate del propio personaje (no se inventa ningún Id ni se cambia el avatar).
	-- 3. Sin animación: el ataque funciona igual, solo con el efecto del disparo.
	-- El disparo no usa la de tajo: un mandoble por cada clic no casa con un rayo.
	AttackAnimationId = nil :: string?,
	UseAvatarSlashAnimation = false,

	-- Sonidos del contenido integrado de Roblox. Solo se usan archivos verificados en las
	-- instalaciones de Studio y Player (content/sounds). nil = sin sonido.
	-- Swing: no hay ningún sonido de tajo verificable, así que queda sin sonido.
	-- Los demás reutilizan esos dos archivos con otro tono y volumen (el cliente varía el
	-- tono ligeramente y nunca reproduce dos copias idénticas a la vez).
	Sounds = {
		Swing = nil :: string?,
		Hit = "rbxasset://sounds/action_jump_land.mp3" :: string?,
		Kill = "rbxasset://sounds/action_jump_land.mp3" :: string?, -- más grave y fuerte
		PetNova = "rbxasset://sounds/impact_explosion_03.mp3" :: string?, -- agudo y suave
		BossSpawn = "rbxasset://sounds/impact_explosion_03.mp3" :: string?, -- grave: retumbar
		BossDefeat = "rbxasset://sounds/impact_explosion_03.mp3" :: string?,
	},
}

return CombatConfig
