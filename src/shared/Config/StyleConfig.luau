-- Estilos de pelea: cómo usa el jugador el poder de su arma equipada. Se elige en cualquier
-- momento (botón ⇄ junto a la habilidad del estilo o tecla C) y se guarda (PetData.Style).
-- Todos salen del daño por segundo (DPS) de tu arma (nivel, cadencia, mascotas, renacimiento
-- y aventuras), así que mejorar o comprar armas sirve con cualquier estilo:
-- - Armas: disparas tu arma tal cual, con su alcance y su efecto (área, salto, ralentiza).
-- - Puños: cuerpo a cuerpo, poco alcance pero DpsScale veces más daño y golpes rapidísimos.
-- - Magia: orbes que explotan en un área pequeña, a media distancia.
-- Cada estilo tiene una PASIVA (siempre activa) y una HABILIDAD (tecla Z, R1 del mando o su
-- botón) con su recarga. Las habilidades hacen daño en múltiplos del DPS del estilo.
-- Lógica pura en StyleLogic; servidor en StyleService y PetCombatService (el disparo);
-- cliente en StyleController (elegir, botón y efectos) y CombatController (cada golpe).
--
-- [PROVISIONAL] Primer balance: Armas ≈ ×1.2 con críticos, Puños ×1.5 pero hay que
-- acercarse (y aguantan más), Magia ×1 con área y curación.

local RGB = Color3.fromRGB

local StyleConfig = {
	Default = "Weapons",
	Order = { "Weapons", "Fists", "Magic" },
	SwitchCooldown = 1.5, -- segundos entre dos cambios de estilo

	-- Sonidos de las habilidades (solo cliente; bibliotecas con licencia de Roblox).
	Sounds = {
		Burst = { Id = "rbxassetid://9125807267", Volume = 0.6, Pitch = 1.1 }, -- ráfaga que sube
		Quake = { Id = "rbxassetid://1846902656", Volume = 0.7, Pitch = 0.8 }, -- golpe grave
		QuakeRumble = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.5, Pitch = 0.6 },
		MeteorFall = { Id = "rbxassetid://9126229267", Volume = 0.45, Pitch = 0.8 }, -- silbido al caer
		MeteorHit = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.45, Pitch = 1 },
		Switch = { Id = "rbxassetid://9116394876", Volume = 0.45, Pitch = 1.5 }, -- campanillas
		Ready = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.3, Pitch = 1.4 },
	},

	Styles = {
		Weapons = {
			DisplayName = "Armas",
			Icon = "🔫",
			Color = RGB(90, 200, 255),
			Attack = "Disparas tu arma: mucho alcance y su efecto (área, salto o ralentiza).",
			Passive = {
				Name = "Puntería",
				Icon = "🎯",
				Text = "Un 20 % de tus disparos son críticos: ×2 de daño.",
				CritChance = 0.2,
				CritMultiplier = 2,
			},
			Ability = {
				Name = "Ráfaga",
				Icon = "💨",
				Text = "Durante 4 s disparas el doble de rápido.",
				Cooldown = 16,
				Duration = 4,
				CooldownScale = 0.5, -- tiempo entre disparos mientras dura
			},
		},
		Fists = {
			DisplayName = "Puños",
			Icon = "👊",
			Color = RGB(255, 150, 70),
			Attack = "Golpes cuerpo a cuerpo muy rápidos: hay que acercarse, pero pegan mucho más.",
			Range = 9, -- hasta el borde del enemigo
			Cooldown = 0.35, -- entre golpes (la mejora "Cadencia" también lo acorta)
			DpsScale = 1.5,
			Passive = {
				Name = "Piel dura",
				Icon = "🛡️",
				Text = "Recibes un 30 % menos de daño.",
				DamageTaken = 0.7,
			},
			Ability = {
				Name = "Terremoto",
				Icon = "🌋",
				Text = "Golpe al suelo: daña a todos a tu alrededor, los aturde y los empuja.",
				Cooldown = 12,
				Radius = 14,
				DamageRatio = 2.5, -- × DPS del estilo a cada enemigo
				Stun = 1.5, -- segundos (los jefes, menos: AbilityConfig.BossControl)
				Knockback = 35,
				MaxTargets = 12,
			},
		},
		Magic = {
			DisplayName = "Magia",
			Icon = "✨",
			Color = RGB(190, 120, 255),
			Attack = "Lanzas orbes mágicos que explotan y dañan a los que estén cerca.",
			Range = 45,
			Cooldown = 0.6,
			DpsScale = 1,
			Splash = { Radius = 7, Fraction = 0.5 },
			Passive = {
				Name = "Robo de vida",
				Icon = "💜",
				Text = "Te curas un 5 % del daño que haces.",
				LifeSteal = 0.05,
				MaxHealPerShot = 0.03, -- como mucho esta parte de tu vida máxima por golpe
			},
			Ability = {
				Name = "Meteoros",
				Icon = "☄️",
				Text = "Caen 6 meteoros sobre tu objetivo y los de alrededor.",
				Cooldown = 15,
				Range = 45, -- objetivo: el tuyo o el enemigo más cercano a esta distancia
				Count = 6,
				Spread = 9, -- cada meteoro cae a esta distancia como mucho del objetivo
				Radius = 7,
				DamageRatio = 1.5, -- × DPS del estilo a cada enemigo de cada meteoro
				Delay = 0.6, -- lo que tarda en caer el primero (se ve el aviso)
				Interval = 0.22, -- entre meteoros
				MaxTargets = 8,
			},
		},
	},
}

return StyleConfig
