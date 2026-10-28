-- Estilos de pelea: cómo usa el jugador el poder de su arma equipada. Se elige en cualquier
-- momento (botón ⇄ junto a las habilidades del estilo o tecla C) y se guarda (PetData.Style).
-- Todos salen del daño por segundo (DPS) de tu arma (nivel, cadencia, mascotas, renacimiento
-- y aventuras), así que mejorar o comprar armas sirve con cualquier estilo. Cada uno juega
-- distinto, con su ventaja y su desventaja (Pros / Cons, para el panel):
-- - Armas: apuntas con la mira y disparas tu arma de fuego (pistola, rifle, escopeta,
--   francotirador o bazuca: WeaponConfig.Guns) con su cargador y su recarga; clic derecho
--   para apuntar. De lejos y con críticos, pero recibes más daño.
-- - Guerrero: espada. Combo de 3 tajos (el 3.º gira y pega a todos), bloquea con clic
--   derecho y, si bloquea justo a tiempo, para el golpe, aturde y contraataca (Block).
-- - Puños: cuerpo a cuerpo y rapidísimos, corres más y aguantas más, pero hay que pegarse.
-- - Magia: bolas que persiguen al bicho más cercano a tu cursor, orbe gigante si mantienes
--   (Charge), maná (Mana), el elemento de tu bastón (combos con las marcas elementales) y
--   teletransporte (Blink). Caminas más lento.
-- Combos (HitCombo): cada pocos golpes seguidos sale uno especial (tiro cargado, gancho).
-- Los de las habilidades entre sí y con las elementales: StyleService.
-- Cada estilo tiene una PASIVA (siempre activa) y CUATRO HABILIDADES del Mundo 1 (Skills): empieza con
-- dos (StartSkills) y las otras dos se compran con 💎 diamantes; lleva puestas dos, una en
-- la tecla Z (R1 del mando o su botón) y otra en la X (L1), cada una con su recarga. Cada
-- habilidad sube de nivel con 💎 (SkillLevels: más daño, menos recarga y más duración).
-- Se compran, se suben y se ponen en el panel ⚡ Mejoras (SkillsController; botón de la
-- tienda de tu estilo o tecla B). Lógica en SkillLogic. Las habilidades hacen daño en
-- múltiplos del DPS del estilo (DamageRatio).
-- Y otras CUATRO del Mundo 2 (World = 2), más fuertes: solo se ven, se compran y se suben en el
-- puesto ⚡ Mejoras del Mundo 2 (SkillsController enseña las del mundo en el que estás) y piden
-- haber llegado allí (Requires). Usan el efecto de una del Mundo 1 (Base), más grande, con su
-- propio color (Color) y algo más: Bombardeo (varias granadas: Count), Rayo triple (Beams),
-- Cometa (explota al llegar: EndRadius) y Terremoto titán (varios golpes: Waves). Las del
-- Guerrero también usan el efecto de otra (Base) con su aspecto (Color, Visual): Giro de acero
-- (Torbellino), Grito de guerra (Furia, con DamageBoost) y Onda cortante (Rayo perforante).
-- Las de Magia dejan su marca elemental (Element) y gastan maná (ManaCost).
-- Números de cada estilo: Range / Cooldown / DpsScale (su ataque), DamageTaken (daño que
-- recibes: ×1 normal) y WalkSpeed (velocidad al caminar: ×1 normal).
-- Lógica pura en StyleLogic (y GunLogic, MagicLogic y WarriorLogic); servidor en
-- StyleService, PetCombatService (cada golpe) y GearService (lo que llevas en la mano);
-- cliente en StyleController (elegir, botones y efectos), CombatController (cada golpe,
-- mira, balas, maná, apuntar y bloquear) y CharacterPose (los movimientos del personaje).
--
-- [PROVISIONAL] Primer balance: Armas ≈ ×1.1-1.25 sostenido (con la recarga) más críticos,
-- Guerrero ×1.35 a varios a la vez, Puños ×1.5 pero hay que acercarse (y aguantan más),
-- Magia ×1.05 con área, elementos, orbe cargado y curación.

local RGB = Color3.fromRGB

local StyleConfig = {
	Default = "Weapons",
	Order = { "Weapons", "Warrior", "Fists", "Magic" },
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
		-- Golpes de cada estilo (CombatController): disparo de cada tipo de arma, recarga,
		-- tajos de espada, parada perfecta, bola mágica y teletransporte
		GunPistol = { Id = "rbxassetid://132539859090895", Volume = 0.45, Pitch = 1 },
		GunRifle = { Id = "rbxassetid://86298841850357", Volume = 0.35, Pitch = 1 },
		GunShotgun = { Id = "rbxassetid://132255180302885", Volume = 0.5, Pitch = 1 },
		GunSniper = { Id = "rbxassetid://130570662564570", Volume = 0.5, Pitch = 1 },
		GunLauncher = { Id = "rbxassetid://2853035419", Volume = 0.5, Pitch = 1 },
		GunBow = { Id = "rbxassetid://9126229267", Volume = 0.45, Pitch = 1.6 },
		Explosion = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.55, Pitch = 0.9 },
		Reload = { Id = "rbxassetid://117963160131194", Volume = 0.45, Pitch = 1 },
		SwordSwing = { Id = "rbxassetid://134671877618939", Volume = 0.45, Pitch = 1 },
		SwordSpin = { Id = "rbxassetid://125914564702009", Volume = 0.5, Pitch = 1 },
		SwordHit = { Id = "rbxassetid://138293953015099", Volume = 0.4, Pitch = 1 },
		PunchSwing = { Id = "rbxassetid://137832890763917", Volume = 0.5, Pitch = 1 }, -- el puño cortando el aire
		PunchHit = { Id = "rbxassetid://140626490819228", Volume = 0.45, Pitch = 1 }, -- jab y directo
		PunchHook = { Id = "rbxassetid://140712924060867", Volume = 0.55, Pitch = 1 }, -- el gancho del combo
		Parry = { Id = "rbxassetid://5763723309", Volume = 0.6, Pitch = 1 },
		MagicBolt = { Id = "rbxassetid://9116394876", Volume = 0.25, Pitch = 2.2 },
		Blink = { Id = "rbxassetid://112075927683042", Volume = 0.5, Pitch = 1 },
	},

	Styles = {
		Weapons = {
			DisplayName = "Armas",
			Icon = "🔫",
			Color = RGB(90, 200, 255),
			Attack = "Apuntas con la mira y disparas: pistola, rifle, escopeta, francotirador o bazuca, cada una con su cargador. Clic derecho: apuntar.",
			Pros = "Pegas de lejos, con críticos y apuntando con clic derecho",
			Cons = "Recibes un 15 % más de daño y tienes que recargar (R)",
			DamageTaken = 1.15,
			-- Combo de golpes: cada Every disparos seguidos (sin parar más de Window s), uno
			-- cargado que hace ×Multiplier (PetCombatService).
			HitCombo = { Every = 5, Window = 1.6, Multiplier = 2, Name = "¡Tiro cargado!" },
			-- Animaciones (publicadas en Roblox; StyleAnimations las pone en tu personaje)
			Animations = {
				Guard = "rbxassetid://97145337559173", -- el arma medio levantada (se repite)
				Aim = "rbxassetid://88074758199655", -- las dos manos en el arma, al frente
				Shot = "rbxassetid://111940463532578", -- retroceso del disparo
				Reload = "rbxassetid://74064624724049", -- cambiar el cargador
			},
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
					Text = "Durante 4 s disparas el doble de rápido y sin gastar balas.",
					Cooldown = 16,
					Duration = 4,
					CooldownScale = 0.5, -- tiempo entre disparos mientras dura
					Price = 0,
				},
				Grenade = {
					Order = 2,
					Name = "Granada",
					Icon = "💣",
					Text = "Lanzas una granada donde apuntas: explota en área y los empuja.",
					Cooldown = 10,
					Range = 45, -- llega como mucho a esta distancia (donde apuntas)
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
					Text = "Un rayo recto hacia donde apuntas que atraviesa a todos los que pilla.",
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
				-- Mundo 2 (World = 2): se compran y se suben en el puesto ⚡ Mejoras del Mundo 2 (hay
				-- que haber llegado: Requires). Base: la habilidad del Mundo 1 cuyo efecto usan, más
				-- grande y fuerte; Color: el de sus efectos.
				Bombardment = {
					Order = 5,
					World = 2,
					Requires = "World2",
					Base = "Grenade",
					Color = RGB(255, 110, 60),
					Name = "Bombardeo",
					Icon = "🧨",
					Text = "Lanzas 4 granadas donde apuntas (una en el centro y tres alrededor): explotan en área grande.",
					Cooldown = 12,
					Count = 4, -- granadas (una donde apuntas y las demás alrededor)
					Range = 55,
					Delay = 0.8,
					Radius = 13,
					DamageRatio = 5,
					Knockback = 34,
					MaxTargets = 14,
					Price = 600, -- 💎 (antes 1 500)
					UpgradeScale = 3,
				},
				TriBeam = {
					Order = 6,
					World = 2,
					Requires = "World2",
					Base = "Pierce",
					Color = RGB(255, 214, 80),
					Name = "Rayo triple",
					Icon = "🔱",
					Text = "Tres rayos dorados en abanico hacia donde apuntas que atraviesan a todos.",
					Cooldown = 10,
					Beams = 3,
					Spread = 22, -- grados entre rayos
					Length = 70,
					Width = 7,
					DamageRatio = 5,
					MaxTargets = 16,
					Price = 1200, -- 💎 (antes 3 000)
					UpgradeScale = 4,
				},
				Overdrive = {
					Order = 7,
					World = 2,
					Requires = "World2",
					Base = "Burst",
					Color = RGB(255, 80, 80),
					Name = "Sobrecarga",
					Icon = "🔥",
					Text = "Durante 6 s disparas casi el triple de rápido y sin gastar balas.",
					Cooldown = 20,
					Duration = 6,
					CooldownScale = 0.35,
					Price = 2000, -- 💎 (antes 6 000)
					UpgradeScale = 5,
				},
				AssaultDrone = {
					Order = 8,
					World = 2,
					Requires = "World2",
					Base = "Turret",
					Color = RGB(110, 255, 150),
					Name = "Dron de asalto",
					Icon = "🤖",
					Text = "Un dron dispara solo y muy rápido al enemigo más cercano durante 12 s.",
					Cooldown = 26,
					Duration = 12,
					Interval = 0.3,
					Range = 55,
					DamageRatio = 1.2,
					Price = 3500, -- 💎 (antes 12 000)
					UpgradeScale = 6,
				},
			},
		},
		Warrior = {
			DisplayName = "Guerrero",
			Icon = "🗡️",
			Color = RGB(240, 80, 90),
			Attack = "Combo de 3 tajos con tu espada (el 3.º gira y pega a todos). Clic derecho: bloqueas; si bloqueas justo a tiempo, contraatacas.",
			Pros = "Pegas a varios a la vez, +25 % de vida y bloqueas los golpes",
			Cons = "Caminas más lento, haces -15 % de daño a los jefes y es cuerpo a cuerpo",
			Range = 11, -- hasta el borde del enemigo
			Cooldown = 0.5, -- entre tajos
			-- Rebalance (pruebas con amigos: "el Guerrero no tiene ninguna desventaja"): menos
			-- daño (1.35 -> 1.2), recibe algo más (0.85 -> 0.95), más lento (1.05 -> 0.95), algo
			-- menos de vida (1.3 -> 1.25), bloqueo menos fuerte (0.3 -> 0.45) y -15 % a jefes. Es
			-- el de las hordas; los jefes son cosa de los Puños.
			DpsScale = 1.2,
			DamageTaken = 0.95,
			WalkSpeed = 0.95,
			MaxHealth = 1.25,
			BossDamage = 0.85, -- × daño a los jefes (StyleLogic.bossDamage)
			-- Combo de tajos (WarriorLogic): cada tajo seguido (sin parar más de ComboWindow s) es el
			-- siguiente. Ratio: × el daño de un tajo; Arc: grados a cada lado (180 = alrededor);
			-- RangeScale: × alcance; Recovery: × lo que tarda el siguiente.
			ComboWindow = 1.1,
			Slashes = {
				{ Name = "Tajo", Ratio = 1, Arc = 70, MaxTargets = 4 },
				{ Name = "Revés", Ratio = 1.1, Arc = 70, MaxTargets = 4 },
				{ Name = "¡Giro!", Ratio = 1.8, Arc = 180, RangeScale = 1.2, MaxTargets = 8, Knockback = 24, Recovery = 1.4 },
			},
			-- Bloquear (mantener clic derecho, L2 o el botón 🛡️): recibes DamageTaken del daño y
			-- caminas más lento. Parada perfecta: si te pegan en los primeros ParryWindow s de un
			-- bloqueo (y no bloqueaste hace menos de ParryRearm s), no te hace nada, el bicho queda
			-- aturdido Stun s y tu siguiente tajo en CounterSeconds s hace ×CounterMultiplier.
			Block = { DamageTaken = 0.45, ParryWindow = 0.35, ParryRearm = 0.8, Stun = 1.5, CounterSeconds = 2, CounterMultiplier = 2.5, WalkSpeed = 0.5 },
			-- Animaciones de la espada (publicadas en Roblox; StyleAnimations las pone en tu
			-- personaje y Roblox las enseña a los demás). Sin ellas, los movimientos hechos a
			-- mano (CharacterPose).
			Animations = {
				Guard = "rbxassetid://139812042784083", -- espada en guardia (se repite)
				Slashes = {
					"rbxassetid://93691437653340", -- Tajo: de derecha a izquierda
					"rbxassetid://91310235080419", -- Revés: de izquierda a derecha
					"rbxassetid://77829434960786", -- ¡Giro! (vuelta completa)
				},
				Block = "rbxassetid://81075562399143", -- espada atravesada (se repite)
			},
			Passive = {
				Name = "Sed de batalla",
				Icon = "🩸",
				Text = "Cada enemigo que derrotas te cura un 5 % de tu vida.",
				KillHeal = 0.05,
			},
			StartSkills = { "Cleave", "Leap" },
			Skills = {
				Cleave = {
					Order = 1,
					Base = "Whirlwind", -- su efecto: golpes a tu alrededor
					Color = RGB(235, 235, 245),
					Name = "Giro de acero",
					Icon = "🌀",
					Text = "Giras con la espada: 3 tajos a todos los que tienes alrededor.",
					Cooldown = 10,
					Radius = 13,
					Pulses = 3,
					Interval = 0.25,
					DamageRatio = 1.3, -- × DPS en cada tajo
					Pull = 0,
					MaxTargets = 12,
					Price = 0,
				},
				Leap = {
					Order = 2,
					Name = "Salto aplastante",
					Icon = "🔨",
					Text = "Saltas hacia donde apuntas y caes con un golpe que aturde y empuja a todos alrededor.",
					Cooldown = 9,
					Distance = 28, -- como mucho
					Delay = 0.55, -- lo que tarda en caer
					Radius = 13,
					DamageRatio = 2.8,
					Stun = 1,
					Knockback = 30,
					MaxTargets = 12,
					Price = 0,
				},
				WarCry = {
					Order = 3,
					Base = "Rage",
					Color = RGB(255, 90, 70),
					Name = "Grito de guerra",
					Icon = "📣",
					Text = "Durante 6 s pegas más rápido, un 30 % más fuerte y recibes la mitad de daño.",
					Cooldown = 18,
					Duration = 6,
					CooldownScale = 0.7,
					DamageBoost = 1.3,
					DamageTaken = 0.5,
					Price = 150,
					UpgradeScale = 1.5,
				},
				SlashWave = {
					Order = 4,
					Base = "Pierce",
					Visual = "SlashWave", -- se ve como una onda de corte
					Color = RGB(255, 140, 150),
					Name = "Onda cortante",
					Icon = "🌙",
					Text = "Lanzas una onda de corte hacia donde apuntas que atraviesa a todos.",
					Cooldown = 9,
					Length = 40,
					Width = 7,
					DamageRatio = 3.2,
					MaxTargets = 12,
					Price = 400,
					UpgradeScale = 2,
				},
				-- Mundo 2
				BladeStorm = {
					Order = 5,
					World = 2,
					Requires = "World2",
					Base = "Cleave",
					Color = RGB(255, 220, 110),
					Name = "Tormenta de espadas",
					Icon = "⚔️",
					Text = "Una tormenta de espadas a tu alrededor: 6 tajos que atraen a todos hacia ti.",
					Cooldown = 14,
					Radius = 16,
					Pulses = 6,
					Interval = 0.22,
					DamageRatio = 1.6,
					Pull = 8,
					MaxTargets = 16,
					Price = 600, -- 💎 (antes 1 500)
					UpgradeScale = 3,
				},
				MeteorStrike = {
					Order = 6,
					World = 2,
					Requires = "World2",
					Base = "Leap",
					Color = RGB(255, 130, 60),
					Name = "Impacto meteoro",
					Icon = "☄️",
					Text = "Saltas muy lejos y caes como un meteoro: daño enorme y aturde a todos alrededor.",
					Cooldown = 12,
					Distance = 40,
					Delay = 0.65,
					Radius = 20,
					DamageRatio = 5,
					Stun = 1.6,
					Knockback = 40,
					MaxTargets = 16,
					Price = 1200, -- 💎 (antes 3 000)
					UpgradeScale = 4,
				},
				WarGod = {
					Order = 7,
					World = 2,
					Requires = "World2",
					Base = "WarCry",
					Color = RGB(255, 200, 60),
					Name = "Dios de la guerra",
					Icon = "👑",
					Text = "Durante 8 s pegas el doble de rápido, un 50 % más fuerte y recibes un 75 % menos de daño.",
					Cooldown = 22,
					Duration = 8,
					CooldownScale = 0.5,
					DamageBoost = 1.5,
					DamageTaken = 0.25,
					Price = 2000, -- 💎 (antes 6 000)
					UpgradeScale = 5,
				},
				RiftSlash = {
					Order = 8,
					World = 2,
					Requires = "World2",
					Base = "SlashWave",
					Visual = "SlashWave",
					Color = RGB(200, 110, 255),
					Name = "Corte dimensional",
					Icon = "🌌",
					Text = "Tres ondas de corte en abanico hacia donde apuntas que atraviesan a todos.",
					Cooldown = 11,
					Beams = 3,
					Spread = 20,
					Length = 60,
					Width = 8,
					DamageRatio = 4.5,
					MaxTargets = 16,
					Price = 3500, -- 💎 (antes 12 000)
					UpgradeScale = 6,
				},
			},
		},
		Fists = {
			DisplayName = "Puños",
			Icon = "👊",
			Color = RGB(255, 150, 70),
			Attack = "Golpes cuerpo a cuerpo muy rápidos: hay que acercarse, pero pegan mucho más.",
			Pros = "+35 % de daño a los jefes, corres más, +50 % de vida, recibes menos daño y tienes dash (Shift)",
			Cons = "Pegas a uno solo y tienes que estar pegado al enemigo",
			Range = 9, -- hasta el borde del enemigo
			Cooldown = 0.35, -- entre golpes (la mejora "Cadencia" también lo acorta)
			-- Rebalance: el que más daño hace a UN enemigo (1.5 -> 1.6) y a los jefes (+35 %);
			-- el Guerrero es el de las hordas.
			DpsScale = 1.6,
			BossDamage = 1.35, -- × daño a los jefes (StyleLogic.bossDamage)
			DamageTaken = 0.7,
			WalkSpeed = 1.2,
			MaxHealth = 1.5, -- × la vida normal
			-- Dash (tecla Shift, B del mando o su botón): un salto rápido hacia donde te
			-- mueves, sin daño, que no cruza paredes ni puertas cerradas de la cueva.
			Dash = { Distance = 16, Cooldown = 2.5 },
			-- El 3.º golpe seguido es un gancho: doble daño y lo lanza hacia atrás y hacia arriba
			-- (Lift: parte de la fuerza que va hacia arriba)
			HitCombo = { Every = 3, Window = 1.2, Multiplier = 2, Name = "¡Gancho!", Knockback = 30, Lift = 0.55 },
			-- Animaciones (publicadas en Roblox; StyleAnimations las pone en tu personaje)
			Animations = {
				Guard = "rbxassetid://72227312054591", -- puños en guardia (se repite)
				Punches = {
					"rbxassetid://123639911749294", -- jab (izquierda)
					"rbxassetid://82475920022600", -- directo (derecha)
				},
				Hook = "rbxassetid://116881478839232", -- el gancho del combo
			},
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
				-- Mundo 2
				Comet = {
					Order = 5,
					World = 2,
					Requires = "World2",
					Base = "Dash",
					Color = RGB(110, 220, 255),
					Name = "Cometa",
					Icon = "☄️",
					Text = "Te lanzas como un cometa, golpeas a todos los que atraviesas y al final explotas.",
					Cooldown = 9,
					Distance = 32,
					Width = 10,
					DamageRatio = 3.5,
					Stun = 1,
					Knockback = 40,
					MaxTargets = 14,
					EndRadius = 14, -- explosión al llegar
					EndRatio = 3,
					Price = 600, -- 💎 (antes 1 500)
					UpgradeScale = 3,
				},
				TitanQuake = {
					Order = 6,
					World = 2,
					Requires = "World2",
					Base = "Quake",
					Color = RGB(255, 200, 70),
					Name = "Terremoto titán",
					Icon = "⛰️",
					Text = "Tres golpes al suelo seguidos, cada uno más grande: aturden y empujan.",
					Cooldown = 14,
					Radius = 16,
					Waves = 3, -- golpes seguidos, cada uno un 35 % más grande
					WaveInterval = 0.35,
					DamageRatio = 3,
					Stun = 2,
					Knockback = 40,
					MaxTargets = 16,
					Price = 1200, -- 💎 (antes 3 000)
					UpgradeScale = 4,
				},
				TitanMode = {
					Order = 7,
					World = 2,
					Requires = "World2",
					Base = "Rage",
					Color = RGB(255, 170, 40),
					Name = "Modo titán",
					Icon = "🦾",
					Text = "Durante 8 s pegas el doble de rápido y recibes un 70 % menos de daño.",
					Cooldown = 22,
					Duration = 8,
					CooldownScale = 0.45,
					DamageTaken = 0.3,
					Price = 2000, -- 💎 (antes 6 000)
					UpgradeScale = 5,
				},
				Hurricane = {
					Order = 8,
					World = 2,
					Requires = "World2",
					Base = "Whirlwind",
					Color = RGB(80, 230, 200),
					Name = "Huracán",
					Icon = "🌀",
					Text = "Un huracán a tu alrededor: 7 golpes que atraen a todos hacia ti.",
					Cooldown = 18,
					Radius = 15,
					Pulses = 7,
					Interval = 0.25,
					DamageRatio = 1.4,
					Pull = 18,
					MaxTargets = 16,
					Price = 3500, -- 💎 (antes 12 000)
					UpgradeScale = 6,
				},
			},
		},
		Magic = {
			DisplayName = "Magia",
			Icon = "✨",
			Color = RGB(190, 120, 255),
			Attack = "Clic: bola que persigue al bicho más cercano a tu cursor. Mantén para cargar un orbe gigante. Gastas maná. Clic derecho o Shift: teletransporte.",
			Pros = "Hechizos que persiguen, área, el elemento de tu bastón y teletransporte",
			Cons = "Caminas un 10 % más lento, tienes un 20 % menos de vida y gastas maná",
			Range = 45,
			Cooldown = 0.45, -- entre bolas rápidas
			DpsScale = 1.05,
			WalkSpeed = 0.9,
			MaxHealth = 0.8, -- de lejos y con área, pero frágil
			Splash = { Radius = 4, Fraction = 0.4 }, -- la bola rápida (el orbe cargado, Charge)
			-- Las bolas persiguen al bicho más cercano al punto apuntado (a esta distancia de él y
			-- a tu alcance); si no hay, explotan donde apuntas.
			LockRadius = 12,
			-- Maná: cada bola gasta BoltCost y el orbe cargado Charge.Cost; se recupera Regen por
			-- segundo (IdleRegen si llevas IdleSeconds sin gastar). Sin maná lanzas chispas
			-- (SparkScale del daño, sin explosión ni elemento). Las habilidades gastan ManaCost.
			-- Rebalance: antes Regen 14 e IdleRegen 30 (casi nunca te quedabas sin maná).
			Mana = { Max = 100, Regen = 8, IdleRegen = 18, IdleSeconds = 1.5, BoltCost = 8, SparkScale = 0.35 },
			-- Orbe cargado: mantén el clic (desde MinHold s); a los Full s está al máximo. Daño =
			-- DPS · (BaseSeconds + segundos cargando) · Bonus; explosión de Radius[1] a Radius[2]
			-- y maná de Cost[1] a Cost[2] según lo cargado.
			Charge = { MinHold = 0.25, Full = 1.5, BaseSeconds = 0.6, Bonus = 1.6, Radius = { 6, 14 }, Fraction = 0.7, Cost = { 12, 40 } },
			-- Teletransporte (clic derecho corto, Shift o su botón): hacia donde apuntas.
			Blink = { Distance = 18, Cooldown = 3, Cost = 15 },
			-- Efecto de cada elemento en los golpes del bastón (además de su marca y sus combos)
			Elements = {
				Fire = { Name = "Fuego", Icon = "🔥", Color = RGB(255, 120, 50), Text = "Quema: un 12 % del golpe cada segundo, 3 s", Burn = 0.12, BurnSeconds = 3 },
				Ice = { Name = "Hielo", Icon = "❄️", Color = RGB(150, 220, 255), Text = "Frena un 35 % 1.5 s", Slow = 0.65, SlowSeconds = 1.5 },
				Lightning = { Name = "Rayo", Icon = "⚡", Color = RGB(255, 240, 110), Text = "Salta a 2 bichos más (45 %)", Chain = { Count = 2, Range = 14, Fraction = 0.45 } },
				Nature = { Name = "Naturaleza", Icon = "🌿", Color = RGB(120, 220, 100), Text = "El orbe cargado enraíza 1.5 s y te curas más", RootSeconds = 1.5, LifeSteal = 0.03 },
				Shadow = { Name = "Sombra", Icon = "🌑", Color = RGB(150, 90, 230), Text = "Debilita: reciben un 15 % más de daño 3 s", Vulnerable = 0.15, VulnerableSeconds = 3 },
				Celestial = { Name = "Celestial", Icon = "🌟", Color = RGB(255, 225, 120), Text = "Cada golpe te cura un 1 % de tu vida", Heal = 0.01 },
			},
			-- Animaciones (publicadas en Roblox; StyleAnimations las pone en tu personaje)
			Animations = {
				Guard = "rbxassetid://97687620779682", -- el bastón en la mano (se repite)
				Charge = "rbxassetid://103550823174900", -- bastón arriba cargando el orbe (se repite)
				Cast = "rbxassetid://118213005926250", -- lanzar: el bastón apunta al frente
			},
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
					Element = "Fire", -- su marca elemental (combos con tu bastón)
					ManaCost = 25,
					Order = 1,
					Name = "Meteoros",
					Icon = "☄️",
					Text = "Caen 6 meteoros donde apuntas y alrededor.",
					Cooldown = 15,
					Range = 45, -- caen donde apuntas, a esta distancia como mucho
					Count = 6,
					Spread = 9, -- cada meteoro cae a esta distancia como mucho del centro
					Radius = 7,
					DamageRatio = 1.5, -- × DPS del estilo a cada enemigo de cada meteoro
					Delay = 0.6, -- lo que tarda en caer el primero (se ve el aviso)
					Interval = 0.22, -- entre meteoros
					MaxTargets = 8,
					Price = 0,
				},
				Nova = {
					Element = "Ice", -- su marca elemental (combos con tu bastón)
					ManaCost = 25,
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
					Element = "Lightning", -- su marca elemental (combos con tu bastón)
					ManaCost = 30,
					Order = 3,
					Name = "Cadena de rayos",
					Icon = "⚡",
					Text = "Un rayo mágico sale hacia el enemigo al que apuntas, salta de uno en uno (hasta 6) y los aturde.",
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
					Element = "Shadow", -- su marca elemental (combos con tu bastón)
					ManaCost = 40,
					Order = 4,
					Name = "Agujero negro",
					Icon = "🌀",
					Text = "Abres un agujero negro donde apuntas: atrae y daña 3 s y luego explota.",
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
				-- Mundo 2
				StarRain = {
					Element = "Celestial", -- su marca elemental (combos con tu bastón)
					ManaCost = 35,
					Order = 5,
					World = 2,
					Requires = "World2",
					Base = "Meteors",
					Color = RGB(255, 220, 90),
					Name = "Lluvia de estrellas",
					Icon = "🌠",
					Text = "Caen 12 estrellas donde apuntas y sobre todo lo que hay alrededor.",
					Cooldown = 14,
					Range = 55,
					Count = 12,
					Spread = 13,
					Radius = 8,
					DamageRatio = 2.2,
					Delay = 0.5,
					Interval = 0.12,
					MaxTargets = 10,
					Price = 600, -- 💎 (antes 1 500)
					UpgradeScale = 3,
				},
				Supernova = {
					Element = "Ice", -- su marca elemental (combos con tu bastón)
					ManaCost = 35,
					Order = 6,
					World = 2,
					Requires = "World2",
					Base = "Nova",
					Color = RGB(255, 150, 230),
					Name = "Supernova",
					Icon = "💥",
					Text = "Explotas como una estrella: daña a todos a tu alrededor y los congela 3 s.",
					Cooldown = 15,
					Radius = 24,
					DamageRatio = 3,
					Freeze = 3,
					MaxTargets = 18,
					Price = 1200, -- 💎 (antes 3 000)
					UpgradeScale = 4,
				},
				Thunderstorm = {
					Element = "Lightning", -- su marca elemental (combos con tu bastón)
					ManaCost = 40,
					Order = 7,
					World = 2,
					Requires = "World2",
					Base = "ChainLightning",
					Color = RGB(120, 230, 255),
					Name = "Tormenta eléctrica",
					Icon = "🌩️",
					Text = "Un rayo enorme salta de enemigo en enemigo (hasta 12) y los aturde.",
					Cooldown = 9,
					Range = 50,
					Jumps = 12,
					JumpRange = 24,
					DamageRatio = 3.5,
					Stun = 0.8,
					Price = 2000, -- 💎 (antes 6 000)
					UpgradeScale = 5,
				},
				Singularity = {
					Element = "Shadow", -- su marca elemental (combos con tu bastón)
					ManaCost = 50,
					Order = 8,
					World = 2,
					Requires = "World2",
					Base = "BlackHole",
					Color = RGB(230, 90, 255),
					Name = "Singularidad",
					Icon = "🕳️",
					Text = "Un agujero negro gigante atrae y daña 4 s y luego explota con muchísima fuerza.",
					Cooldown = 24,
					Range = 55,
					Radius = 20,
					Duration = 4,
					Interval = 0.4,
					TickRatio = 0.9,
					DamageRatio = 6,
					Pull = 22,
					MaxTargets = 16,
					Price = 3500, -- 💎 (antes 12 000)
					UpgradeScale = 6,
				},
			},
		},
	},
}

return StyleConfig
