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
			Icon = "⚡",
			Name = "Energía ×2",
			Description = "Produces el doble de energía para siempre, también mientras no juegas.",
			Color = Color3.fromRGB(255, 214, 90),
		},
		AutoUpgrade = {
			Id = 0,
			Order = 2,
			Icon = "🤖",
			Name = "Mejora automática",
			Description = "La Resonancia del Cristal sube sola en cuanto te alcanza la energía. Se puede apagar.",
			Color = Color3.fromRGB(110, 236, 220),
		},
		TripleHatch = {
			Id = 0,
			Order = 3,
			Icon = "🥚",
			Name = "Abrir ×3",
			Description = "Abre 3 huevos de una vez (pagas los 3 con energía).",
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
	},

	-- Compras sueltas de energía: N minutos de la producción actual del jugador (como los
	-- premios), nunca menos de Min.
	Products = {
		EnergySmall = { Id = 0, Order = 1, Icon = "⚡", Name = "Saco de energía", Minutes = 30, Min = 5000 },
		EnergyMedium = { Id = 0, Order = 2, Icon = "💰", Name = "Cofre de energía", Minutes = 120, Min = 25000 },
		EnergyLarge = { Id = 0, Order = 3, Icon = "👑", Name = "Tesoro de energía", Minutes = 480, Min = 100000 },
	},

	-- Mascotas exclusivas (por su PetId de PetConfig): cada compra da una, aunque el
	-- inventario esté lleno. Se compran en el altar del Jardín de los Huevos (EggStandService,
	-- con EggConfig.Gardens.Forest.FeaturedPet).
	PetProducts = {
		Haxigator = { Id = 0, Icon = "🐊", Name = "Haxigator" },
	},

	-- Efecto de cada pase
	EnergyMultiplier = 2, -- DoubleEnergy
	PetSlotBonus = 2, -- PetSpace: mascotas equipadas de más
	InventoryBonus = 60, -- PetSpace: espacio de inventario de más
	TripleCount = 3, -- TripleHatch: huevos por apertura
	AutoUpgradeInterval = 1, -- AutoUpgrade: cada cuántos segundos mira si puede mejorar
	AutoUpgradeMaxPerTick = 5, -- y cuántos niveles sube como mucho de una vez

	MaxReceipts = 50, -- compras recordadas por jugador (para no conceder dos veces)
}

return MonetizationConfig
