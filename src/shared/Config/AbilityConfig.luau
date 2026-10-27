-- Habilidades elementales: el núcleo SELECCIONADO da al jugador una habilidad de combate
-- propia (tecla Q, botón Y del mando o el botón de pantalla). Todo lo decide el servidor
-- (AbilityService): el cliente solo pide "usar la habilidad" y dibuja lo que se le confirma.
--
-- Daño de una habilidad (AbilityLogic.damage):
--   daño = DamageRatio · daño del jugador (CombatMath.playerDamage) · maestría
--   maestría = 1 + Mastery.PerLevel · min(nivel del núcleo, Mastery.MaxLevel)
-- Naturaleza NO tiene maestría: no tiene nivel (antes era el del Cristal del
-- Renacimiento, que ya no existe).
-- Así mejorar el núcleo que usas lo hace más fuerte (hasta ×2 al nivel 50).
-- Ejemplo: jugador de 35 de daño con Fuego al nivel 10 -> Llamarada 1.3 · 35 · 1.2 = 54.6.
--
-- Dos huecos: el elemento PRINCIPAL (tecla Q) y el SECUNDARIO (tecla R, cuando tienes
-- dos núcleos despiertos). Cada elemento tiene su recarga, que no se reinicia al
-- cambiarlo de hueco ni al morir; entre dos habilidades cualesquiera hay una pequeña
-- recarga global (GlobalCooldown). Las habilidades con objetivo (Rayo, Sombra) no se
-- gastan si no hay ningún enemigo delante.
--
-- Combos (Reactions): cada habilidad deja en el enemigo su MARCA elemental durante
-- Aura.Seconds (menos el Viento, que no marca: esparce). Si otra habilidad de un elemento
-- distinto le alcanza y la pareja tiene reacción, la marca se consume y se dispara el
-- combo. El daño de los combos sale del daño del jugador y la maestría del elemento que
-- lo dispara. Los combos no encadenan otros combos.
--
-- Control sobre los jefes: inmovilizar y aturdir duran BossControl veces lo normal y la
-- ralentización es más débil, para que un jefe no se pueda dejar quieto para siempre.
--
-- [PROVISIONAL] Todos los números son un primer balance razonado con la economía y los
-- enemigos actuales (vida del jugador 100; Espinillo 40, Bruto 180, Guardián 1 500).

local AbilityConfig = {
	Mastery = {
		PerLevel = 0.02,
		MaxLevel = 50,
	},
	BossControl = 0.4, -- inmovilizar/aturdir a un jefe dura un 40 % (ralentizar: la mitad de fuerte)
	BroadcastRange = 150, -- jugadores que ven los efectos de la habilidad de otro
	GlobalCooldown = 0.6, -- segundos mínimos entre dos habilidades (Q y R)
	Aura = {
		Seconds = 6, -- lo que dura la marca elemental en un enemigo
		NoAura = { Wind = true }, -- elementos que no dejan marca
	},
	MaxControlSeconds = 10, -- tope de seguridad de cualquier estado sobre un enemigo

	-- Presentación (solo cliente). Sonidos: efectos gratuitos de la Creator Store de Roblox
	-- (biblioteca de Pro Sound Effects, con licencia de Roblox para cualquier experiencia).
	-- Volume y Pitch (velocidad de reproducción) por sonido; nil = sin sonido.
	Sounds = {
		Cast = {
			Nature = { Id = "rbxassetid://9114518386", Volume = 0.7, Pitch = 1.1 }, -- follaje
			Water = { Id = "rbxassetid://9125703162", Volume = 0.6, Pitch = 0.85 }, -- chapoteo
			Fire = { Id = "rbxassetid://9114444008", Volume = 0.55, Pitch = 1 }, -- llamarada
			Wind = { Id = "rbxassetid://9125646252", Volume = 0.6, Pitch = 1.1 }, -- ráfaga mágica
			Lightning = { Id = "rbxassetid://9114277757", Volume = 0.5, Pitch = 1 }, -- chispazo
			Ice = { Id = "rbxassetid://9125611419", Volume = 0.55, Pitch = 1.15 }, -- hielo crujiendo
			Shadow = { Id = "rbxassetid://9125648149", Volume = 0.6, Pitch = 0.6 }, -- silbido grave
			Celestial = { Id = "rbxassetid://9116394876", Volume = 0.6, Pitch = 1 }, -- campanillas
		},
		Reactions = {
			Default = { Id = "rbxassetid://9125647922", Volume = 0.6, Pitch = 0.8 },
			Electrocuted = { Id = "rbxassetid://9114277402", Volume = 0.55, Pitch = 1.1 },
			Steam = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.35, Pitch = 1.3 },
			Frozen = { Id = "rbxassetid://9125611419", Volume = 0.6, Pitch = 0.8 },
			Eclipse = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.4, Pitch = 0.75 },
			Bloom = { Id = "rbxassetid://9116394876", Volume = 0.5, Pitch = 1.25 },
		},
		RollOff = 90, -- distancia a la que deja de oírse la habilidad de otro jugador
	},
	ReactionShake = 0.55, -- sacudida al disparar un combo
	ScreenFlash = 0.82, -- transparencia inicial del destello de pantalla (1 = sin destello)

	-- Combos entre elementos. Pair: los dos elementos (en cualquier orden: la marca de uno
	-- y la habilidad del otro). Remolino (Swirl) es especial: lo dispara el Viento sobre
	-- cualquiera de las marcas de Spreads y la esparce a los enemigos cercanos.
	Reactions = {
		Electrocuted = {
			Name = "¡Electrocutado!",
			Pair = { "Water", "Lightning" },
			Color = Color3.fromRGB(150, 210, 255),
			Multiplier = 1.5, -- el golpe que lo dispara
			StunSeconds = 1.2,
			Radius = 8, -- descarga alrededor
			BurstRatio = 0.8,
		},
		Steam = {
			Name = "¡Vapor!",
			Pair = { "Water", "Fire" },
			Color = Color3.fromRGB(235, 240, 245),
			Radius = 9,
			BurstRatio = 2, -- explosión de vapor
			Knockback = 30,
		},
		Frozen = {
			Name = "¡Congelado!",
			Pair = { "Water", "Ice" },
			Color = Color3.fromRGB(180, 240, 255),
			StunSeconds = 2.5, -- bloque de hielo: ni anda ni ataca
		},
		Wildfire = {
			Name = "¡Incendio!",
			Pair = { "Nature", "Fire" },
			Color = Color3.fromRGB(255, 120, 40),
			Radius = 10,
			BurnMultiplier = 2, -- quemadura doble que salta a los cercanos
		},
		Melt = {
			Name = "¡Derretir!",
			Pair = { "Ice", "Fire" },
			Color = Color3.fromRGB(255, 170, 110),
			Multiplier = 2,
		},
		Overload = {
			Name = "¡Sobrecarga!",
			Pair = { "Fire", "Lightning" },
			Color = Color3.fromRGB(255, 170, 70),
			Radius = 9,
			BurstRatio = 1.5, -- explosión alrededor
			Knockback = 24,
		},
		Superconduct = {
			Name = "¡Superconductor!",
			Pair = { "Ice", "Lightning" },
			Color = Color3.fromRGB(190, 160, 255),
			Radius = 8,
			VulnerableBonus = 0.4, -- rompe la defensa: +40 % de daño recibido
			VulnerableSeconds = 6,
		},
		Bloom = {
			Name = "¡Florecer!",
			Pair = { "Nature", "Water" },
			Color = Color3.fromRGB(140, 255, 150),
			HealFraction = 0.25, -- cura al jugador
			RootSeconds = 3,
		},
		Eclipse = {
			Name = "¡Eclipse!",
			Pair = { "Shadow", "Celestial" },
			Color = Color3.fromRGB(255, 200, 120),
			Radius = 10,
			BurstRatio = 3,
			HealFraction = 0.2,
			Knockback = 28,
		},
		Swirl = {
			Name = "¡Remolino!",
			Trigger = "Wind",
			Spreads = { Water = true, Fire = true, Ice = true, Lightning = true },
			Color = Color3.fromRGB(196, 255, 232),
			Radius = 10,
			BurstRatio = 1,
			Knockback = 18,
		},
	},

	Abilities = {
		-- Raíces que brotan a tu alrededor: daño en área e inmovilizan.
		Nature = {
			Name = "Raíces Atrapantes",
			Icon = "🌿",
			Color = Color3.fromRGB(120, 214, 96),
			Type = "Roots",
			Gesture = "toollunge", -- gesto del avatar al lanzarla (script Animate)
			Shake = 0.35, -- sacudida de cámara (0..1) para quien la lanza
			Cooldown = 8,
			Radius = 12,
			DamageRatio = 1.6,
			MaxTargets = 6,
			RootSeconds = 1.5,
		},
		-- Marea curativa: te cura (y a los aliados cercanos) y empapa a los enemigos.
		Water = {
			Name = "Marea Sanadora",
			Icon = "💧",
			Color = Color3.fromRGB(90, 180, 255),
			Type = "Heal",
			Gesture = "cheer", -- gesto del avatar al lanzarla (script Animate)
			Shake = 0.25, -- sacudida de cámara (0..1) para quien la lanza
			Cooldown = 12,
			HealFraction = 0.35, -- de la vida máxima del jugador
			AllyHealFraction = 0.2,
			AllyRadius = 18,
			Radius = 10,
			DamageRatio = 1,
			MaxTargets = 6,
			Knockback = 22, -- la ola los aparta (los jefes no se mueven)
		},
		-- Llamarada en cono: golpe inicial y quemadura que sigue haciendo daño.
		Fire = {
			Name = "Llamarada",
			Icon = "🔥",
			Color = Color3.fromRGB(255, 130, 50),
			Type = "Burn",
			Gesture = "point", -- gesto del avatar al lanzarla (script Animate)
			Shake = 0.4, -- sacudida de cámara (0..1) para quien la lanza
			Cooldown = 9,
			Range = 14,
			ArcDot = 0.45, -- ~63° a cada lado del frente
			DamageRatio = 1.3,
			MaxTargets = 5,
			BurnRatioPerTick = 0.3, -- por tic de quemadura
			BurnTickSeconds = 0.5,
			BurnSeconds = 4, -- 8 tics: 2.4 × daño más
		},
		-- Vendaval: ráfaga en cono y velocidad extra para el jugador.
		Wind = {
			Name = "Vendaval",
			Icon = "🌪",
			Color = Color3.fromRGB(196, 255, 232),
			Type = "Gust",
			Gesture = "toolslash", -- gesto del avatar al lanzarla (script Animate)
			Shake = 0.3, -- sacudida de cámara (0..1) para quien la lanza
			Cooldown = 10,
			Range = 16,
			ArcDot = 0.55,
			DamageRatio = 1.8,
			MaxTargets = 6,
			HasteBonus = 0.35, -- +35 % de velocidad al andar
			HasteSeconds = 5,
			Knockback = 34,
		},
		-- Cadena de rayos: alcanza al enemigo de delante y salta a los cercanos.
		Lightning = {
			Name = "Cadena de Rayos",
			Icon = "⚡",
			Color = Color3.fromRGB(255, 236, 110),
			Type = "Chain",
			Gesture = "point", -- gesto del avatar al lanzarla (script Animate)
			Shake = 0.45, -- sacudida de cámara (0..1) para quien la lanza
			Cooldown = 7,
			Range = 18,
			ArcDot = 0.2,
			DamageRatio = 2.2,
			Jumps = 4, -- enemigos adicionales
			JumpRange = 11, -- distancia máxima entre un salto y el siguiente
			JumpFalloff = 0.8, -- cada salto hace el 80 % del anterior
			StunSeconds = 0.5, -- breve aturdimiento: interrumpe su golpe
		},
		-- Escarcha: nova helada a tu alrededor que ralentiza (andar y atacar).
		Ice = {
			Name = "Escarcha",
			Icon = "❄",
			Color = Color3.fromRGB(150, 226, 255),
			Type = "Frost",
			Gesture = "toollunge", -- gesto del avatar al lanzarla (script Animate)
			Shake = 0.35, -- sacudida de cámara (0..1) para quien la lanza
			Cooldown = 10,
			Radius = 14,
			DamageRatio = 1.3,
			MaxTargets = 8,
			SlowFactor = 0.5, -- se mueven y atacan a la mitad de ritmo
			SlowSeconds = 4,
		},
		-- Maldición: golpe al enemigo de delante; él y los cercanos reciben más daño.
		Shadow = {
			Name = "Maldición Sombría",
			Icon = "🌑",
			Color = Color3.fromRGB(170, 110, 255),
			Type = "Curse",
			Gesture = "point", -- gesto del avatar al lanzarla (script Animate)
			Shake = 0.35, -- sacudida de cámara (0..1) para quien la lanza
			Cooldown = 11,
			Range = 16,
			ArcDot = 0.3,
			DamageRatio = 2.2,
			SpreadRadius = 9, -- alrededor del objetivo principal
			MaxTargets = 5,
			VulnerableBonus = 0.3, -- +30 % de daño recibido de todo (jugadores y mascotas)
			CurseSeconds = 6,
		},
		-- Lluvia estelar: aviso dorado delante del jugador y tres oleadas de estrellas.
		Celestial = {
			Name = "Lluvia Estelar",
			Icon = "🌟",
			Color = Color3.fromRGB(255, 220, 120),
			Type = "Starfall",
			Gesture = "cheer", -- gesto del avatar al lanzarla (script Animate)
			Shake = 0.3, -- sacudida de cámara (0..1) para quien la lanza
			Cooldown = 15,
			Distance = 9, -- centro del área, delante del jugador
			Radius = 14,
			Telegraph = 0.7,
			Waves = 3,
			WaveInterval = 0.45,
			DamageRatio = 1.7, -- por oleada (5.1 × daño en total)
			MaxTargets = 8,
		},
	},
}

return AbilityConfig
