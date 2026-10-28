-- Armas del jugador: la principal forma de ganar poder de combate. Disparan hacia donde
-- apuntas (WeaponLogic, GunLogic / PetCombatService); el servidor calcula todo el daño.
--
-- Cada arma:
--   Damage      daño de un disparo a nivel 0 (antes de mascotas, renacimiento y aventuras)
--   Cooldown    segundos entre disparos (la mejora global "Cadencia" lo reduce)
--   Range       alcance en studs hasta el borde del enemigo
--   Projectile  cómo se dibuja: "Beam" (rayo fino), "Bolt" (bola de plasma que viaja),
--               "Prism" (rayo de cristal que salta), "Thorn" (espina verde), "Orb" (esfera
--               que explota), "Slash" (tajo de espada). Color = color del disparo (y del
--               arma, la espada o el bastón que se ve en la mano: GearModels).
--   Gun         estilo Armas: tipo de arma de fuego ("Pistol", "Rifle", "Shotgun", "Sniper"
--               o "Launcher"; ver Guns): cómo dispara, su cargador y el modelo de la mano.
--               Model = "Bow" lo dibuja como un arco.
--   Element     estilo Magia: elemento del bastón ("Fire", "Ice", "Lightning", "Nature",
--               "Shadow" o "Celestial"): su efecto en cada golpe y sus combos con las marcas
--               elementales (AbilityConfig.Reactions; MagicLogic).
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
--   World       2 = solo se ve en la Armería del Mundo 2 (sin él, en la del Mundo 1)
--   Category    para qué estilo es (StyleConfig): "Weapons" (armas, por defecto), "Warrior"
--               (espadas), "Fists" (guantes) o "Magic" (bastones). Cada estilo tiene su
--               propia tienda (la Armería enseña la de tu estilo), su equipado y sus niveles:
--               el progreso de cada estilo va aparte. Guerrero, Puños y Magia usan el daño
--               por segundo de su espada, sus guantes o su bastón (Damage / Cooldown) con su
--               propio ritmo y alcance (StyleConfig) y el efecto del objeto (frena, salta,
--               área) sobre el del estilo.
--
-- Precios calculados con lo que gana un jugador activo (EnemyConfig: cada enemigo paga
-- su Reward al morir más ~0.75·Reward en golpes): unos 700 💰/min en el Bosque con el
-- láser inicial, ~2 500/min en el Valle y ~7 000/min en la Caldera. Una compra normal
-- cuesta unos minutos de su zona; las de zonas nuevas, algo más.
-- Disparan más despacio y más fuerte (tiempo entre disparos y daño ×1.6 respecto al primer
-- diseño: mismo DPS, golpes más gordos); los estilos Puños y Magia salen de este mismo DPS.
-- DPS a nivel 0: Láser 20 · Plasma 32 (+área) · Arco 37 (+ralentiza) · Cristal 89
-- (+salta a 2) · Prisma 127 (+salta a 4) · Vacío 200 (+área grande) · Magma 347 (+área).

local WeaponConfig = {
	StarterWeapon = "Laser",
	-- Lo que tiene cada estilo desde el principio (y lo que se equipa si no hay otra cosa)
	Starters = { Weapons = "Laser", Warrior = "WoodenSword", Fists = "LeatherGloves", Magic = "ApprenticeWand" },
	-- Cada tienda: título de la cabecera, icono y cómo se llama un objeto suyo
	-- ItemIcon: el objeto de la categoría, en grande en la tarjeta de la tienda (sin Art); el
	-- Icon de cada arma (su elemento: 🔮, 🌑, 🔥…) va de insignia en la esquina. Antes solo se
	-- veía el Icon y una espada de amatista parecía un orbe (pruebas con amigos).
	Categories = {
		Weapons = { Title = "ARQUERÍA", Icon = "🏹", ItemIcon = "🏹", Item = "arma", Items = "armas", Hit = "por disparo" },
		Warrior = { Title = "ESPADAS", Icon = "🗡️", ItemIcon = "🗡️", Item = "espada", Items = "espadas", Hit = "por tajo" },
		Fists = { Title = "GUANTES", Icon = "🥊", ItemIcon = "🥊", Item = "guantes", Items = "guantes", Hit = "por golpe" },
		Magic = { Title = "BASTONES", Icon = "✨", ItemIcon = "🔱", Item = "bastón", Items = "bastones", Hit = "por hechizo" },
	},
	MaxLevel = 25,
	LevelDamageBonus = 0.15, -- +15 % de daño por nivel del arma

	-- Tipos de arma del Arquero (campo Gun de cada arma del estilo "Weapons"; GunLogic). Los ids
	-- son los de cuando eran armas de fuego (Pistol, Rifle...): solo cambian nombre y modelo. Sobre el
	-- daño y el tiempo entre disparos del arma:
	--   FireScale    × tiempo entre disparos (y × daño de cada disparo: mismo DPS)
	--   DamageScale  × daño de cada disparo (compensa la recarga; la escopeta, si entran todos)
	--   RangeScale   × alcance
	--   Magazine     balas del cargador; Reload: segundos que tarda en recargar
	--   Spread       grados de desvío de cada bala sin apuntar; AdsSpread apuntando (clic derecho)
	--   Pellets      perdigones por disparo (escopeta: cada uno hace su parte del daño)
	--   Pierce       enemigos extra que atraviesa la bala (francotirador), con PierceFalloff
	--   Speed        studs/s del cohete (bazuca: el daño llega al explotar) y Blast su explosión
	--   AdsCrit / AdsCritPower  críticos extra al apuntar
	Guns = {
		Pistol = {
			Name = "Ballesta de mano",
			Icon = "🏹",
			Text = "Precisa y rápida de recargar.",
			FireScale = 1,
			DamageScale = 1.35,
			RangeScale = 1,
			Magazine = 12,
			Reload = 1.1,
			Spread = 1.5,
			AdsSpread = 0,
			AdsCrit = 0.1,
		},
		Rifle = {
			Name = "Ballesta de repetición",
			Icon = "⚙️",
			Text = "Automática: mantén el clic y no para de soltar virotes.",
			FireScale = 0.4,
			DamageScale = 1.3,
			RangeScale = 1,
			Magazine = 30,
			Reload = 1.7,
			Spread = 3.5,
			AdsSpread = 1,
			AdsCrit = 0.1,
		},
		Shotgun = {
			Name = "Ballesta de abanico",
			Icon = "🪶",
			Text = "Varios virotes en abanico: brutal de cerca.",
			FireScale = 1.6,
			DamageScale = 1.45,
			RangeScale = 0.5,
			Magazine = 6,
			Reload = 1.8,
			Spread = 10,
			AdsSpread = 6,
			Pellets = 8,
			AdsCrit = 0.05,
		},
		Sniper = {
			Name = "Arbalesta",
			Icon = "🎯",
			Text = "Lenta y letal: atraviesa a 2 más y apuntando hace críticos enormes.",
			FireScale = 2.2,
			DamageScale = 1.5,
			RangeScale = 1.5,
			Magazine = 5,
			Reload = 2,
			Spread = 4,
			AdsSpread = 0,
			Pierce = 2,
			PierceFalloff = 0.7,
			AdsCrit = 0.35,
			AdsCritPower = 1,
		},
		Launcher = {
			Name = "Balista de mano",
			Icon = "🧨",
			Text = "Virotes con brea que explotan en un área grande.",
			FireScale = 2,
			DamageScale = 1.4,
			RangeScale = 1,
			Magazine = 3,
			Reload = 2.3,
			Spread = 2,
			AdsSpread = 0.5,
			Speed = 110,
			Blast = { Radius = 9, Fraction = 0.8 },
			Knockback = 18,
			AdsCrit = 0.1,
		},
	},
	-- Apuntar (clic derecho o L2 con el estilo Armas): zoom por encima del hombro, más
	-- alcance y precisión (AdsSpread) y más críticos (AdsCrit), pero caminas más lento.
	Ads = { RangeScale = 1.15, FieldOfView = 48, WalkSpeed = 0.6, CameraOffset = Vector3.new(1.8, 0.4, 0) },
	UpgradeGrowth = 1.32,

	-- Las armas de cada categoría (estilo) viven en su propio módulo: Weapons (armas de
	-- fuego), Gloves (guantes, Puños), Swords (espadas, Guerrero) y Staffs (bastones,
	-- Magia). Se juntan aquí abajo, en esta misma tabla.
	Weapons = {},

	-- Color del texto de cada rareza en la Armería
	Rarities = {
		["Común"] = Color3.fromRGB(228, 228, 228),
		Raro = Color3.fromRGB(79, 180, 255),
		["Épico"] = Color3.fromRGB(208, 112, 255),
		Legendario = Color3.fromRGB(255, 210, 30),
		["Mítica"] = Color3.fromRGB(255, 79, 106),
		Divina = Color3.fromRGB(110, 255, 230),
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

-- Las armas de las cuatro categorías, en WeaponConfig.Weapons (ningún id se repite).
for _, list in { require(script.Weapons), require(script.Gloves), require(script.Swords), require(script.Staffs) } do
	for weaponId, def in list do
		assert(WeaponConfig.Weapons[weaponId] == nil, "arma repetida: " .. weaponId)
		WeaponConfig.Weapons[weaponId] = def
	end
end

return WeaponConfig
