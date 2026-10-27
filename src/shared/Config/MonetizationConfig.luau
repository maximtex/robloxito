-- Tienda: pases (game passes, se compran una vez) y compras sueltas (developer products).
-- Lo cobra Roblox; lo concede el servidor (ShopService) y nunca se fía del cliente.
--
-- CÓMO ACTIVARLO:
-- 1. En el Creator Dashboard de tu juego crea cada pase (Monetización > Pases) y cada
--    compra suelta (Monetización > Productos para desarrolladores) con su precio en Robux.
-- 2. Copia el número de cada uno en `Id` aquí abajo y sincroniza con Rojo.
--    Las mascotas exclusivas (PetProducts) también son productos para desarrolladores.
-- Con Id = 0 el artículo sale en la tienda como «Próximamente» y no se puede comprar.
-- El precio que ve el jugador lo da Roblox (el que pongas en el Dashboard).
--
-- Para probar en Studio sin comprar nada: DevConfig.StudioPasses = true (solo Studio) da
-- todos los pases. Las compras sueltas de prueba de Studio son gratis.

local MonetizationConfig = {
	GamePasses = {
		DoubleEnergy = {
			Id = 0,
			Order = 1,
			Icon = "💎",
			Name = "Diamantes ×2",
			Description = "Ganas el doble de 💎 al derrotar enemigos y en las oleadas, para siempre.",
			Color = Color3.fromRGB(255, 214, 90),
		},
		AutoUpgrade = {
			Id = 0,
			Order = 2,
			Icon = "🤖",
			Name = "Mejora automática",
			Description = "Tu arma equipada (o tus guantes o tu bastón, según tu estilo) se mejora sola en cuanto te alcanza el 💰. Se puede apagar.",
			Color = Color3.fromRGB(110, 236, 220),
		},
		TripleHatch = {
			Id = 0,
			Order = 3,
			Icon = "🥚",
			Name = "Abrir ×3",
			Description = "Abre 3 huevos de una vez (pagas los 3 con 💰).",
			Color = Color3.fromRGB(255, 160, 200),
		},
		PetSpace = {
			Id = 0,
			Order = 4,
			Icon = "🐾",
			Name = "Más mascotas",
			Description = "+2 mascotas equipadas a la vez y +60 de espacio en el inventario.",
			Color = Color3.fromRGB(150, 220, 120),
		},
		AutoFire = {
			Id = 0,
			Order = 0,
			Icon = "🎯",
			Name = "Disparo automático",
			Description = "Tu arma dispara sola hacia donde apuntas en cuanto hay un enemigo en la mira, sin hacer clic. Se puede apagar.",
			Color = Color3.fromRGB(255, 130, 100),
		},
	},

	-- Compras sueltas de 💎 (en el código, Energy): Min diamantes.
	Products = {
		EnergySmall = { Id = 0, Order = 1, Icon = "💎", Name = "Bolsa de diamantes", Min = 150 },
		EnergyMedium = { Id = 0, Order = 2, Icon = "💠", Name = "Cofre de diamantes", Min = 700 },
		EnergyLarge = { Id = 0, Order = 3, Icon = "👑", Name = "Tesoro de diamantes", Min = 3000 },
	},

	-- Mascotas exclusivas (por su PetId de PetConfig): cada compra da una, aunque el
	-- inventario esté lleno. Se compran en el altar del Jardín de los Huevos (EggStandService,
	-- con EggConfig.Gardens.Forest.FeaturedPet).
	PetProducts = {
		Haxigator = { Id = 0, Icon = "🐊", Name = "Haxigator" },
	},

	-- Armas que también se compran con Robux (por su id de WeaponConfig), en su tarjeta de la
	-- Armería. Robux = precio que se ve en el botón (el de Roblox manda al pagar). Se
	-- entregan aunque su zona siga cerrada, y se equipan. Id 0 = aún sin crear ("Próximamente").
	WeaponProducts = {
		PlasmaBlaster = { Id = 0, Robux = 49 },
		CrystalCannon = { Id = 0, Robux = 149 },
		VoidCannon = { Id = 0, Robux = 399 },
	},

	-- Efecto de cada pase
	EnergyMultiplier = 2, -- DoubleEnergy (×2 de 💎)
	PetSlotBonus = 2, -- PetSpace: mascotas equipadas de más
	InventoryBonus = 60, -- PetSpace: espacio de inventario de más
	TripleCount = 3, -- TripleHatch: huevos por apertura
	AutoUpgradeInterval = 1, -- AutoUpgrade: cada cuántos segundos mira si puede mejorar
	AutoUpgradeMaxPerTick = 5, -- y cuántos niveles sube como mucho de una vez (arma del estilo actual)

	MaxReceipts = 50, -- compras recordadas por jugador (para no conceder dos veces)
}

return MonetizationConfig
