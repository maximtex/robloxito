-- Estilos de pelea: cómo usa el jugador el poder de su arma equipada. Se elige en cualquier
-- momento (botón ⇄ junto a las habilidades del estilo o tecla C) y se guarda (PetData.Style).
-- Todos salen del daño por segundo (DPS) de tu arma (nivel, cadencia, mascotas, renacimiento
-- y aventuras), así que mejorar o comprar armas sirve con cualquier estilo. Cada uno juega
-- distinto, con su ventaja y su desventaja (Pros / Cons, para el panel):
-- - Armas: disparas tu arma tal cual, de lejos y con críticos, pero recibes más daño.
-- - Puños: cuerpo a cuerpo y rapidísimos, corres más y aguantas más, pero hay que pegarse.
-- - Magia: orbes que explotan en área y te curan, pero caminas más lento y cada hechizo
--   tarda en cargar.
-- Cada estilo tiene una PASIVA (siempre activa) y DOS HABILIDADES: Ability (tecla Z, R1 del
-- mando o su botón) y Ability2 (tecla X, L1 o su botón), cada una con su recarga. Las
-- habilidades hacen daño en múltiplos del DPS del estilo.
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
			Ability2 = {
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
			},
		},
		Fists = {
			DisplayName = "Puños",
			Icon = "👊",
			Color = RGB(255, 150, 70),
			Attack = "Golpes cuerpo a cuerpo muy rápidos: hay que acercarse, pero pegan mucho más.",
			Pros = "Corres un 20 % más y recibes un 30 % menos",
			Cons = "Tienes que estar pegado al enemigo",
			Range = 9, -- hasta el borde del enemigo
			Cooldown = 0.35, -- entre golpes (la mejora "Cadencia" también lo acorta)
			DpsScale = 1.5,
			DamageTaken = 0.7,
			WalkSpeed = 1.2,
			Passive = {
				Name = "Piel dura",
				Icon = "🛡️",
				Text = "Recibes un 30 % menos de daño y corres un 20 % más.",
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
			Ability2 = {
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
			Ability2 = {
				Name = "Nova de hielo",
				Icon = "❄️",
				Text = "Una onda helada sale de ti: daña y congela a los que alcanza.",
				Cooldown = 14,
				Radius = 16,
				DamageRatio = 1.2,
				Freeze = 2, -- segundos congelados (los jefes, menos)
				MaxTargets = 14,
			},
		},
	},
}

return StyleConfig
