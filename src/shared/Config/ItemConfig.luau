-- Artículos del inventario (🎒 Inventario: InventoryController; los concede ItemService):
-- - Pociones (impulsos): duplican algo durante un rato. Tomar otra igual suma su tiempo al
--   que quede (hasta MaxBoostSeconds). El tiempo solo corre mientras se juega.
-- - Poción de Vida (Heal): cura al momento (pruebas con amigos: con la vida volviendo sola
--   las pociones no servían; ahora la vida casi no vuelve sola). Se toma con la tecla Y o su
--   botón ❤️ (QuickPotionController) o desde el inventario; HealCooldown entre dos. La sueltan
--   los enemigos más a menudo que las otras (HealthDrops).
-- - Huevos guardados: los sueltan los jefes y se abren desde el inventario, sin coste.
-- - Títulos: se ganan con logros y el equipado se ve encima de la cabeza (lo ven todos).
-- - Botín de los jefes (BossDrops): a cada jugador que recibe parte de la recompensa. Los
--   demás enemigos (también los de las oleadas) a veces sueltan una poción (EnemyDrops).

local ItemConfig = {
	-- Pociones. Multiplier: lo que multiplica mientras dura (ItemLogic.multiplier).
	--   Diamonds  💎 de los enemigos y de los premios de las oleadas
	--           (PlayerDataService.diamondMultiplier)
	--   Damage  todo el daño del jugador: disparos, habilidades y mascotas (EnemyService.damage)
	--   Money   dinero de los enemigos (EnemyService: lootMultiplier)
	--   Luck    sorteo de los huevos: se tira LuckRolls veces y se queda el mejor (PetService)
	Potions = {
		Health = {
			DisplayName = "Poción de Vida",
			Short = "Vida",
			Description = "Cura al momento la mitad de tu vida máxima (tecla Y).",
			Icon = "❤️",
			Color = Color3.fromRGB(236, 72, 104),
			Heal = 0.5, -- parte de la vida máxima (sin tiempo: no es un impulso)
			Order = 0,
		},
		Diamonds = {
			DisplayName = "Poción de Diamantes",
			Short = "x2 Diamantes",
			Description = "Duplica los 💎 que sueltan los enemigos y las oleadas.",
			Icon = "💎",
			Color = Color3.fromRGB(110, 200, 255),
			Multiplier = 2,
			Seconds = 10 * 60,
			Order = 1,
		},
		Damage = {
			DisplayName = "Poción de Fuerza",
			Short = "x2 Daño",
			Description = "Tus disparos, habilidades y mascotas hacen el doble de daño.",
			Icon = "⚔️",
			Color = Color3.fromRGB(240, 76, 64),
			Multiplier = 2,
			Seconds = 10 * 60,
			Order = 2,
		},
		Money = {
			DisplayName = "Poción de Riqueza",
			Short = "x2 Dinero",
			Description = "Los enemigos sueltan el doble de dinero.",
			Icon = "💰",
			Color = Color3.fromRGB(72, 200, 92),
			Multiplier = 2,
			Seconds = 10 * 60,
			Order = 3,
		},
		Luck = {
			DisplayName = "Poción de Suerte",
			Short = "Suerte",
			Description = "Más probabilidad de mascotas raras al abrir huevos.",
			Icon = "🍀",
			Color = Color3.fromRGB(140, 100, 255),
			Multiplier = 2,
			Seconds = 10 * 60,
			Order = 4,
		},
	},
	MaxBoostSeconds = 2 * 60 * 60, -- tiempo acumulado como máximo por poción
	HealCooldown = 6, -- segundos entre dos Pociones de Vida
	-- Poción de Vida al derrotar a un enemigo (probabilidad según su Kind; los jefes, siempre)
	HealthDrops = { Normal = 0.03, Strong = 0.12, Boss = 1 },
	MaxStack = 999, -- pociones o huevos de un mismo tipo como máximo
	-- Suerte: el sorteo del huevo se repite estas veces y se queda el número más alto (en
	-- EggConfig.Chances las mascotas raras van al final, así que salen más).
	LuckRolls = 2,

	-- Botín de los jefes (tipo de EnemyConfig). Potions: pociones al azar que suelta siempre.
	-- EggChance: probabilidad (0..1) de soltar además el huevo Egg (de EggConfig.Eggs).
	-- Los jefes que no están aquí usan Default.
	BossDrops = {
		Default = { Potions = 1, EggChance = 0 },
		ForestWarden = { Potions = 1, EggChance = 0.25, Egg = "AncientEgg" },
		AmethystColossus = { Potions = 1, EggChance = 0.25, Egg = "CrystalEgg" },
		CalderaTitan = { Potions = 1, EggChance = 0.25, Egg = "MagmaEgg" },
	},
	-- Los demás enemigos: probabilidad (0..1) de soltar una poción al azar, según su Kind
	-- (EnemyConfig). Más o menos 1 de cada 200 normales y 1 de cada 50 fuertes.
	EnemyDrops = { Normal = 0.005, Strong = 0.02 },

	-- Huevos guardados: nombre y color en el inventario (si el huevo no los tiene en EggConfig).
	EggLooks = {
		ForestEgg = { Name = "Huevo Común", Color = Color3.fromRGB(196, 204, 186) },
		MossEgg = { Name = "Huevo No Común", Color = Color3.fromRGB(96, 206, 80) },
		AncientEgg = { Name = "Huevo Raro", Color = Color3.fromRGB(48, 170, 255) },
		CrystalEgg = { Name = "Huevo de Cristal", Color = Color3.fromRGB(176, 110, 255) },
		MagmaEgg = { Name = "Huevo de Magma", Color = Color3.fromRGB(255, 110, 48) },
	},

	-- Títulos. Requisito (uno):
	--   Stat + Goal  llegar a Goal en una estadística (ItemService.statsOf):
	--                Kills (enemigos derrotados), Rebirths, Pets (mascotas que tiene),
	--                PotionsUsed, DiamondsEarned (💎 conseguidos en total)
	--   Boss         haber derrotado a ese jefe (tipo de EnemyConfig)
	--   sin nada     se tiene desde el principio
	Titles = {
		Novato = { DisplayName = "Novato", Description = "Empieza tu aventura.", Color = Color3.fromRGB(214, 220, 228), Order = 1 },
		Cazador = { DisplayName = "Cazador", Description = "Derrota 100 enemigos.", Stat = "Kills", Goal = 100, Color = Color3.fromRGB(120, 230, 110), Order = 2 },
		Exterminador = { DisplayName = "Exterminador", Description = "Derrota 1.000 enemigos.", Stat = "Kills", Goal = 1000, Color = Color3.fromRGB(255, 150, 60), Order = 3 },
		LeyendaBosque = { DisplayName = "Leyenda del Bosque", Description = "Derrota al Guardián del Bosque.", Boss = "ForestWarden", Color = Color3.fromRGB(140, 255, 58), Order = 4 },
		Rompecristales = { DisplayName = "Rompecristales", Description = "Derrota al Coloso de Amatista.", Boss = "AmethystColossus", Color = Color3.fromRGB(200, 130, 255), Order = 5 },
		SenorMagma = { DisplayName = "Señor del Magma", Description = "Derrota al Titán de la Caldera.", Boss = "CalderaTitan", Color = Color3.fromRGB(255, 92, 48), Order = 6 },
		Alquimista = { DisplayName = "Alquimista", Description = "Usa 10 pociones.", Stat = "PotionsUsed", Goal = 10, Color = Color3.fromRGB(170, 120, 255), Order = 7 },
		Coleccionista = { DisplayName = "Coleccionista", Description = "Ten 25 mascotas.", Stat = "Pets", Goal = 25, Color = Color3.fromRGB(96, 190, 255), Order = 8 },
		Generador = { DisplayName = "Minero de Diamantes", Description = "Consigue 25.000 💎 en total.", Stat = "DiamondsEarned", Goal = 25000, Color = Color3.fromRGB(110, 200, 255), Order = 9 },
		Renacido = { DisplayName = "Renacido", Description = "Renace 1 vez.", Stat = "Rebirths", Goal = 1, Color = Color3.fromRGB(255, 200, 80), Order = 10 },
		Inmortal = { DisplayName = "Inmortal", Description = "Renace 10 veces.", Stat = "Rebirths", Goal = 10, Color = Color3.fromRGB(255, 110, 200), Order = 11 },
	},
}

return ItemConfig
