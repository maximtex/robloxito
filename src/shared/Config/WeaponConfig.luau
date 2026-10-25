-- Armas del jugador: la principal forma de ganar poder de combate. Disparan solas al
-- enemigo elegido (WeaponLogic / PetCombatService); el servidor calcula todo el daño.
--
-- Cada arma:
--   Damage      daño de un disparo a nivel 0 (antes de mascotas, renacimiento y aventuras)
--   Cooldown    segundos entre disparos (la mejora global "Cadencia" lo reduce)
--   Range       alcance en studs hasta el borde del enemigo
--   Projectile  cómo se dibuja: "Beam" (rayo fino), "Bolt" (bola de plasma que viaja),
--               "Prism" (rayo de cristal que salta), "Thorn" (espina verde), "Orb" (esfera
--               que explota). Color = color del disparo.
--   Effect      opcional: Splash = { Radius, Fraction } (daño en área alrededor del
--               objetivo), Chain = { Count, Range, Fraction } (salta a otros enemigos),
--               Slow = { Factor, Seconds } (ralentiza al objetivo)
--   Price       dinero para comprarla (0 = se tiene desde el principio; nil = no se vende)
--   Requires    para poder comprarla: { Zone = "<zona desbloqueada>" }
--   BossDrop    jefe (tipo de EnemyConfig) que la regala la primera vez que se le derrota
--   UpgradeCost coste del nivel 0 → 1; cada nivel cuesta UpgradeGrowth veces el anterior
--   Order       posición en la Armería
--   Rarity      rareza que se ve en su tarjeta (color en Rarities)
--   CardColors  fondo de su tarjeta en la Armería: { claro (centro), base, oscuro (borde) }
--   Tagline     su efecto en pocas palabras (tarjeta de un arma que aún no tiene)
--   Art         imagen del arma (rbxassetid://…); sin ella la tarjeta muestra su Icon
--
-- Precios calculados con lo que gana un jugador activo (EnemyConfig: cada enemigo paga
-- su Reward al morir más ~0.75·Reward en golpes): unos 700 💰/min en el Bosque con el
-- láser inicial, ~2 500/min en el Valle y ~7 000/min en la Caldera. Una compra normal
-- cuesta unos minutos de su zona; las de zonas nuevas, algo más.
-- DPS a nivel 0: Láser 20 · Plasma 32 (+área) · Arco 37 (+ralentiza) · Cristal 89
-- (+salta a 2) · Prisma 127 (+salta a 4) · Vacío 200 (+área grande) · Magma 347 (+área).

local WeaponConfig = {
	StarterWeapon = "Laser",
	MaxLevel = 25,
	LevelDamageBonus = 0.15, -- +15 % de daño por nivel del arma
	UpgradeGrowth = 1.32,

	Weapons = {
		Laser = {
			DisplayName = "Láser básico",
			Description = "Rayo rápido y preciso. Tu primera arma.",
			Icon = "🔫",
			Damage = 5,
			Cooldown = 0.25,
			Range = 60,
			Projectile = "Beam",
			Color = Color3.fromRGB(80, 230, 255),
			Price = 0,
			UpgradeCost = 25,
			Order = 1,
			Rarity = "Común",
			CardColors = { Color3.fromRGB(166, 236, 255), Color3.fromRGB(47, 166, 242), Color3.fromRGB(19, 94, 196) },
			Tagline = "⚡ Rayo rápido",
			Art = "rbxassetid://115189526493315",
		},
		PlasmaBlaster = {
			DisplayName = "Bláster de plasma",
			Description = "Bolas de plasma lentas que explotan y dañan a los que estén cerca.",
			Icon = "💥",
			Damage = 16,
			Cooldown = 0.5,
			Range = 55,
			Projectile = "Bolt",
			Color = Color3.fromRGB(255, 96, 200),
			Effect = { Splash = { Radius = 6, Fraction = 0.5 } },
			Price = 4000,
			UpgradeCost = 120,
			Order = 2,
			Rarity = "Raro",
			CardColors = { Color3.fromRGB(255, 220, 106), Color3.fromRGB(247, 128, 31), Color3.fromRGB(207, 51, 15) },
			Tagline = "💥 Explota en área",
			Art = "rbxassetid://89889778592812",
		},
		ThornBow = {
			DisplayName = "Arco de espinas",
			Description = "Espinas que ralentizan al enemigo. Lo suelta el Guardián del Bosque.",
			Icon = "🌿",
			Damage = 11,
			Cooldown = 0.3,
			Range = 70,
			Projectile = "Thorn",
			Color = Color3.fromRGB(120, 230, 90),
			Effect = { Slow = { Factor = 0.6, Seconds = 1.5 } },
			BossDrop = "ForestWarden",
			UpgradeCost = 150,
			Order = 3,
			Rarity = "Épico",
			CardColors = { Color3.fromRGB(196, 255, 106), Color3.fromRGB(65, 194, 40), Color3.fromRGB(22, 127, 24) },
			Tagline = "🧊 Ralentiza 40%",
			Art = "rbxassetid://107410496738801",
		},
		CrystalCannon = {
			DisplayName = "Cañón cristalino",
			Description = "Rayo de cristal que salta a dos enemigos más.",
			Icon = "💎",
			Damage = 40,
			Cooldown = 0.45,
			Range = 70,
			Projectile = "Prism",
			Color = Color3.fromRGB(150, 200, 255),
			Effect = { Chain = { Count = 2, Range = 14, Fraction = 0.5 } },
			Price = 25000,
			Requires = { Zone = "CrystalValley" },
			UpgradeCost = 750,
			Order = 4,
			Rarity = "Legendario",
			CardColors = { Color3.fromRGB(158, 239, 255), Color3.fromRGB(63, 134, 242), Color3.fromRGB(58, 47, 184) },
			Tagline = "⚡ Salta a 2 más",
			Art = "rbxassetid://131638372208866",
		},
		AmethystPrism = {
			DisplayName = "Prisma de amatista",
			Description = "Rayo que salta a cuatro enemigos. Lo suelta el Coloso de Amatista.",
			Icon = "🔮",
			Damage = 70,
			Cooldown = 0.55,
			Range = 75,
			Projectile = "Prism",
			Color = Color3.fromRGB(200, 120, 255),
			Effect = { Chain = { Count = 4, Range = 16, Fraction = 0.6 } },
			BossDrop = "AmethystColossus",
			UpgradeCost = 1500,
			Order = 5,
			Rarity = "Legendario",
			CardColors = { Color3.fromRGB(236, 184, 255), Color3.fromRGB(163, 82, 240), Color3.fromRGB(85, 24, 158) },
			Tagline = "⚡ Salta a 4 más",
			Art = "rbxassetid://94787144945196",
		},
		VoidCannon = {
			DisplayName = "Cañón del vacío",
			Description = "Esferas de vacío que explotan en un área grande.",
			Icon = "🌑",
			Damage = 160,
			Cooldown = 0.8,
			Range = 75,
			Projectile = "Orb",
			Color = Color3.fromRGB(130, 70, 230),
			Effect = { Splash = { Radius = 10, Fraction = 0.7 } },
			Price = 120000,
			Requires = { Zone = "EmberCaldera" },
			UpgradeCost = 3600,
			Order = 6,
			Rarity = "Mítica",
			CardColors = { Color3.fromRGB(185, 166, 255), Color3.fromRGB(91, 63, 210), Color3.fromRGB(34, 18, 98) },
			Tagline = "💥 Área grande",
			Art = "rbxassetid://79163263488986",
		},
		MagmaHeart = {
			DisplayName = "Corazón de magma",
			Description = "Bolas de magma que explotan y frenan a los enemigos. Lo suelta el Titán de la Caldera.",
			Icon = "🔥",
			Damage = 260,
			Cooldown = 0.75,
			Range = 80,
			Projectile = "Orb",
			Color = Color3.fromRGB(255, 120, 40),
			Effect = { Splash = { Radius = 12, Fraction = 0.6 }, Slow = { Factor = 0.7, Seconds = 1.2 } },
			BossDrop = "CalderaTitan",
			UpgradeCost = 6000,
			Order = 7,
			Rarity = "Mítica",
			CardColors = { Color3.fromRGB(255, 195, 90), Color3.fromRGB(240, 80, 42), Color3.fromRGB(156, 18, 12) },
			Tagline = "💥 Área + 🧊 frena",
			Art = "rbxassetid://122488165200469",
		},
	},

	-- Color del texto de cada rareza en la Armería
	Rarities = {
		["Común"] = Color3.fromRGB(228, 228, 228),
		Raro = Color3.fromRGB(79, 180, 255),
		["Épico"] = Color3.fromRGB(208, 112, 255),
		Legendario = Color3.fromRGB(255, 210, 30),
		["Mítica"] = Color3.fromRGB(255, 79, 106),
	},

	-- Imágenes del panel de la Armería (rbxassetid://…): el icono de la cabecera (subido
	-- desde el diseño, con su borde difuminado) y el de Robux. Sin icono se ve ⚔️.
	ArmoryArt = {
		Header = "rbxassetid://73640158617132",
		Robux = "rbxasset://textures/ui/common/robux@3x.png",
	},

	-- Mejora global de la Armería que acelera todas las armas (EconomyConfig.Upgrades.LaserSpeed)
	CadenceUpgradeId = "LaserSpeed",
	CadencePerLevel = 0.025, -- -2.5 % de tiempo entre disparos por nivel
	MinCadenceFactor = 0.6,
}

return WeaponConfig
