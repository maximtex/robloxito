-- Estilos de pelea: cómo usa el jugador el poder de su arma equipada. Se elige en cualquier
-- momento (botón ⇄ junto a las habilidades del estilo o tecla C) y se guarda (PetData.Style).
-- Todos salen del daño por segundo (DPS) de tu arma (nivel, cadencia, mascotas, renacimiento
-- y aventuras), así que mejorar o comprar armas sirve con cualquier estilo. Cada uno juega
-- distinto, con su ventaja y su desventaja (Pros / Cons, para el panel):
-- - Armas: disparas tu arma tal cual, de lejos y con críticos, pero recibes más daño.
-- - Puños: cuerpo a cuerpo y rapidísimos, corres más y aguantas más, pero hay que pegarse.
-- - Magia: orbes que explotan en área y te curan, pero caminas más lento y cada hechizo
--   tarda en cargar.
-- Combos (HitCombo): cada pocos golpes seguidos sale uno especial (tiro cargado, gancho,
-- gran orbe). Los de las habilidades entre sí y con las elementales: StyleService.
-- Cada estilo tiene una PASIVA (siempre activa) y CUATRO HABILIDADES (Skills): empieza con
-- dos (StartSkills) y las otras dos se compran con 💎 diamantes; lleva puestas dos, una en
-- la tecla Z (R1 del mando o su botón) y otra en la X (L1), cada una con su recarga. Cada
-- habilidad sube de nivel con 💎 (SkillLevels: más daño, menos recarga y más duración).
-- Se compran, se suben y se ponen en el panel ⚡ Mejoras (SkillsController; botón de la
-- tienda de tu estilo o tecla B). Lógica en SkillLogic. Las habilidades hacen daño en
-- múltiplos del DPS del estilo (DamageRatio).
-- Números de cada estilo: Range / Cooldown / DpsScale (su ataque), DamageTaken (daño que
-- recibes: ×1 normal) y WalkSpeed (velocidad al caminar: ×1 normal).
-- Lógica pura en StyleLogic; servidor en StyleService y PetCombatService (el disparo);
-- cliente en StyleController (elegir, botones y efectos), CombatController (cada golpe) y
-- CharacterPose (los movimientos del personaje).
--
-- [PROVISIONAL] Primer balance: Armas ≈ ×1.2 con críticos, Puños ×1.5 pero hay que
-- acercarse (y aguantan más), Magia ×1 con área y curación.

local RGB = Color3.fromRGB

local StyleConfig = {
	Default = "Weapons",
	Order = { "Weapons", "Fists", "Magic" },
	SwitchCooldown = 1.5, -- segundos entre dos cambios de estilo

	-- Niveles de las habilidades (SkillLogic): del 1 al Max. Cada nivel por encima del 1:
	-- +Damage de daño, -Cooldown de recarga (como mucho hasta MinCooldown) y +Duration de
	-- lo que dure. Subir del nivel n al n+1 cuesta UpgradeBase · UpgradeScale de la
	-- habilidad · UpgradeGrowth^(n-1) 💎.
	SkillLevels = {
		Max = 10,
		Damage = 0.15,
		Cooldown = 0.03,
		MinCooldown = 0.7,
		Duration = 0.05,
		UpgradeBase = 30,
		UpgradeGrowth = 1.4,
	},

	-- Sonidos de las habilidades (solo cliente; bibliotecas con licencia de Roblox).
	Sounds = {
		Burst = { Id = "rbxassetid://9125807267", Volume = 0.6, Pitch = 1.1 }, -- ráfaga que sube
		Quake = { Id = "rbxassetid://1846902656", Volume = 0.7, Pitch = 0.8 }, -- golpe grave
		QuakeRumble = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.5, Pitch = 0.6 },
		MeteorFall = { Id = "rbxassetid://9126229267", Volume = 0.45, Pitch = 0.8 }, -- silbido al caer
		MeteorHit = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.45, Pitch = 1 },
		Dash = { Id = "rbxassetid://9126229267", Volume = 0.6, Pitch = 0.75 }, -- ráfaga de aire
		DashHit = { Id = "rbxassetid://1846902656", Volume = 0.45, Pitch = 1.3 },
		Throw = { Id = "rbxassetid://9126229267", Volume = 0.4, Pitch = 1.5 }, -- silbido corto
		Grenade = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.6, Pitch = 0.8 },
		Nova = { Id = "rbxassetid://9116394876", Volume = 0.55, Pitch = 0.6 }, -- campanillas graves
		NovaBlast = { Id = "rbxassetid://9126228629", Volume = 0.5, Pitch = 0.7 },
		Charge = { Id = "rbxassetid://9116394876", Volume = 0.2, Pitch = 1.9 }, -- el orbe cargando
		Pierce = { Id = "rbxassetid://9125807267", Volume = 0.55, Pitch = 0.7 }, -- rayo largo
		Turret = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.35, Pitch = 0.8 },
		TurretShot = { Id = "rbxassetid://9125807267", Volume = 0.25, Pitch = 1.6 },
		Rage = { Id = "rbxassetid://1846902656", Volume = 0.6, Pitch = 0.6 },
		Whirl = { Id = "rbxassetid://9126229267", Volume = 0.5, Pitch = 1.1 },
		Lightning = { Id = "rbxassetid://9125807267", Volume = 0.5, Pitch = 1.3 },
		BlackHole = { Id = "rbxassetid://9116394876", Volume = 0.5, Pitch = 0.4 },
		Combo = { Id = "rbxassetid://9116394876", Volume = 0.5, Pitch = 1.2 },
		Switch = { Id = "rbxassetid://9116394876", Volume = 0.45, Pitch = 1.5 }, -- campanillas
		Ready = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.3, Pitch = 1.4 },
	},

	Styles = {
		Weapons = {
			DisplayName = "Armas",
			Icon = "🔫",
			Color = RGB(90, 200, 255),
			Attack = "Disparas tu arma: mucho alcance y su efecto (área, salto o ralentiza).",
			Pros = "Pegas de lejos y con críticos",
			Cons = "Recibes un 15 % más de daño",
			DamageTaken = 1.15,
			-- Combo de golpes: cada Every disparos seguidos (sin parar más de Window s), uno
			-- cargado que hace ×Multiplier (PetCombatService).
			HitCombo = { Every = 5, Window = 1.6, Multiplier = 2, Name = "¡Tiro cargado!" },
			Passive = {
				Name = "Puntería",
				Icon = "🎯",
				Text = "Un 20 % de tus disparos son críticos: ×2 de daño.",
				CritChance = 0.2,
				CritMultiplier = 2,
			},
			StartSkills = { "Burst", "Grenade" },
			Skills = {
				Burst = {
					Order = 1,
					Name = "Ráfaga",
					Icon = "💨",
					Text = "Durante 4 s disparas el doble de rápido.",
					Cooldown = 16,
					Duration = 4,
					CooldownScale = 0.5, -- tiempo entre disparos mientras dura
					Price = 0,
				},
				Grenade = {
					Order = 2,
					Name = "Granada",
					Icon = "💣",
					Text = "Lanzas una granada a tu objetivo: explota en área y los empuja.",
					Cooldown = 10,
					Range = 45, -- objetivo: el enemigo más cercano a esta distancia
					Delay = 0.7, -- lo que tarda en llegar y explotar
					Radius = 11,
					DamageRatio = 3, -- × DPS del estilo a cada enemigo
					Knockback = 30,
					MaxTargets = 12,
					Price = 0,
				},
				Pierce = {
					Order = 3,
					Name = "Rayo perforante",
					Icon = "🎯",
					Text = "Un rayo recto hacia tu objetivo que atraviesa a todos los que pilla.",
					Cooldown = 9,
					Length = 55, -- largo del rayo
					Width = 5,
					DamageRatio = 3.5,
					MaxTargets = 12,
					Price = 150,
					UpgradeScale = 1.5,
				},
				Turret = {
					Order = 4,
					Name = "Torreta",
					Icon = "🛰️",
					Text = "Pones una torreta que dispara sola al enemigo más cercano durante 8 s.",
					Cooldown = 24,
					Duration = 8,
					Interval = 0.5, -- entre disparos
					Range = 40,
					DamageRatio = 0.7, -- × DPS por disparo
					Price = 400,
					UpgradeScale = 2,
				},
			},
		},
		Fists = {
			DisplayName = "Puños",
			Icon = "👊",
			Color = RGB(255, 150, 70),
			Attack = "Golpes cuerpo a cuerpo muy rápidos: hay que acercarse, pero pegan mucho más.",
			Pros = "Corres más, +50 % de vida, recibes menos daño y tienes dash (Shift)",
			Cons = "Tienes que estar pegado al enemigo",
			Range = 9, -- hasta el borde del enemigo
			Cooldown = 0.35, -- entre golpes (la mejora "Cadencia" también lo acorta)
			DpsScale = 1.5,
			DamageTaken = 0.7,
			WalkSpeed = 1.2,
			MaxHealth = 1.5, -- × la vida normal
			-- Dash (tecla Shift, B del mando o su botón): un salto rápido hacia donde te
			-- mueves, sin daño, que no cruza paredes ni puertas cerradas de la cueva.
			Dash = { Distance = 16, Cooldown = 2.5 },
			HitCombo = { Every = 3, Window = 1.2, Multiplier = 2, Name = "¡Gancho!", Knockback = 22 },
			Passive = {
				Name = "Piel dura",
				Icon = "🛡️",
				Text = "Recibes un 30 % menos de daño, corres un 20 % más y tienes +50 % de vida.",
			},
			StartSkills = { "Quake", "Dash" },
			Skills = {
				Quake = {
					Order = 1,
					Name = "Terremoto",
					Icon = "🌋",
					Text = "Golpe al suelo: daña a todos a tu alrededor, los aturde y los empuja.",
					Cooldown = 12,
					Radius = 14,
					DamageRatio = 2.5, -- × DPS del estilo a cada enemigo
					Stun = 1.5, -- segundos (los jefes, menos: AbilityConfig.BossControl)
					Knockback = 35,
					MaxTargets = 12,
					Price = 0,
				},
				Dash = {
					Order = 2,
					Name = "Embestida",
					Icon = "🐗",
					Text = "Te lanzas hacia delante y golpeas a todos los que atraviesas.",
					Cooldown = 8,
					Distance = 24, -- como mucho (se para antes de una pared)
					Width = 8, -- ancho de la franja que golpea
					DamageRatio = 2,
					Stun = 0.6,
					Knockback = 30,
					MaxTargets = 10,
					Price = 0,
				},
				Rage = {
					Order = 3,
					Name = "Furia",
					Icon = "😤",
					Text = "Durante 6 s pegas mucho más rápido y recibes la mitad de daño.",
					Cooldown = 18,
					Duration = 6,
					CooldownScale = 0.6, -- tiempo entre golpes mientras dura
					DamageTaken = 0.5,
					Price = 150,
					UpgradeScale = 1.5,
				},
				Whirlwind = {
					Order = 4,
					Name = "Torbellino",
					Icon = "🌪️",
					Text = "Giras como un tornado: 4 golpes a todos a tu alrededor y los atraes hacia ti.",
					Cooldown = 16,
					Radius = 11,
					Pulses = 4,
					Interval = 0.3,
					DamageRatio = 1.1, -- × DPS en cada golpe
					Pull = 14, -- fuerza con la que los atrae
					MaxTargets = 12,
					Price = 400,
					UpgradeScale = 2,
				},
			},
		},
		Magic = {
			DisplayName = "Magia",
			Icon = "✨",
			Color = RGB(190, 120, 255),
			Attack = "Cargas orbes mágicos que explotan y dañan a los que estén cerca.",
			Pros = "Daño en área y te curas al pegar",
			Cons = "Caminas un 10 % más lento y cada hechizo tarda en cargar",
			Range = 45,
			Cooldown = 0.8, -- cada orbe carga (más lento que un disparo, pero pega más)
			DpsScale = 1,
			WalkSpeed = 0.9,
			Splash = { Radius = 7, Fraction = 0.5 },
			HitCombo = { Every = 4, Window = 2, Multiplier = 2.5, Name = "¡Gran orbe!", SplashScale = 1.6 },
			Passive = {
				Name = "Robo de vida",
				Icon = "💜",
				Text = "Te curas un 5 % del daño que haces.",
				LifeSteal = 0.05,
				MaxHealPerShot = 0.03, -- como mucho esta parte de tu vida máxima por golpe
			},
			StartSkills = { "Meteors", "Nova" },
			Skills = {
				Meteors = {
					Order = 1,
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
					Price = 0,
				},
				Nova = {
					Order = 2,
					Name = "Nova de hielo",
					Icon = "❄️",
					Text = "Una onda helada sale de ti: daña y congela a los que alcanza.",
					Cooldown = 14,
					Radius = 16,
					DamageRatio = 1.2,
					Freeze = 2, -- segundos congelados (los jefes, menos)
					MaxTargets = 14,
					Price = 0,
				},
				ChainLightning = {
					Order = 3,
					Name = "Cadena de rayos",
					Icon = "⚡",
					Text = "Un rayo mágico salta de enemigo en enemigo (hasta 6) y los aturde.",
					Cooldown = 10,
					Range = 40, -- primer objetivo
					Jumps = 6,
					JumpRange = 18,
					DamageRatio = 2.5,
					Stun = 0.5,
					Price = 150,
					UpgradeScale = 1.5,
				},
				BlackHole = {
					Order = 4,
					Name = "Agujero negro",
					Icon = "🌀",
					Text = "Abres un agujero negro en tu objetivo: atrae y daña 3 s y luego explota.",
					Cooldown = 22,
					Range = 45,
					Radius = 14,
					Duration = 3,
					Interval = 0.5,
					TickRatio = 0.5, -- × DPS cada Interval
					DamageRatio = 3, -- la explosión final
					Pull = 16,
					MaxTargets = 12,
					Price = 400,
					UpgradeScale = 2,
				},
			},
		},
	},
}

return StyleConfig
