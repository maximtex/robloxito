-- Combate del jugador: daño, alcance y ritmo. El servidor calcula el daño real con
-- CombatMath; el cliente solo usa estos valores para la interfaz.
--
-- Fórmula del daño (CombatMath.playerDamage):
--   daño = (BaseDamage + DamagePerLevel · nivel de "Resonancia del Cristal")
--          · (1 + PetDamageShare · (multiplicador de mascotas - 1))
-- Las mejoras siguen siendo la vía principal: cada nivel suma daño además de producción.
-- Las mascotas aportan la mitad de su bonificación al daño (ej. ×1.35 -> +17.5 %).
-- Ejemplos: nivel 0 sin mascotas = 10; nivel 10 con ×1.35 = 35.25; nivel 16 con ×2 = 63.

local CombatConfig = {
	BaseDamage = 10,
	DamagePerLevel = 2,
	DamageUpgradeId = "GeneratorPower",
	PetDamageShare = 0.5,

	AttackCooldown = 0.5, -- segundos entre golpes
	AttackRange = 9, -- studs desde el jugador hasta el borde del enemigo
	AttackArcDot = -0.2, -- ~100° a cada lado del frente; muy cerca (<4) golpea en cualquier dirección
	MaxTargetsPerSwing = 3, -- un golpe puede alcanzar a varios enemigos, cada uno una sola vez

	-- Animación de ataque. Orden de preferencia:
	-- 1. AttackAnimationId: un rbxassetid://... propio (sin configurar).
	-- 2. UseAvatarSlashAnimation: reutiliza la animación "toolslash" que trae el script
	--    Animate del propio personaje (no se inventa ningún Id ni se cambia el avatar).
	-- 3. Sin animación: el ataque funciona igual, solo con el efecto del tajo.
	AttackAnimationId = nil :: string?,
	UseAvatarSlashAnimation = true,

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
