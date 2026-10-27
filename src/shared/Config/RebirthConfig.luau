-- Renacimiento (Rebirth). Al renacer se reinician el 💰 y el nivel de las armas; se
-- conservan los 💎, mascotas, núcleos, zonas y misiones. A cambio:
-- - Multiplicador permanente del botín en 💰 de los enemigos y del daño, que crece con
--   cada renacimiento.
-- - Fichas de renacimiento para la tienda de ventajas permanentes (Shop).
-- La lógica pura está en RebirthLogic; el servidor (RebirthService) decide todo.
--
-- Antes pedía un nivel de la Resonancia del Cristal, que ya no existe. Hasta que llegue el
-- requisito nuevo (fase 2 del rediseño), Enabled = false: no se puede renacer y el panel
-- dice "Próximamente". Se conserva lo ya conseguido (renacimientos, fichas y tienda).

local RebirthConfig = {
	Enabled = false,

	-- Premio permanente por renacimiento (se suman: 3 renacimientos = ×2.5 de botín).
	LootBonus = 0.5, -- +50 % de 💰 de los enemigos por renacimiento
	DamageBonus = 0.1, -- +10 % de daño por renacimiento

	-- Fichas que da el renacimiento número k: Base + PerRebirth · (k - 1) (1, 2, 3...).
	Tokens = { Base = 1, PerRebirth = 1 },

	-- Tope de seguridad (muy por encima de cualquier partida real).
	MaxRebirths = 1000,

	-- Protección del servidor contra solicitudes repetidas (segundos).
	RebirthCooldown = 3,
	ShopCooldown = 0.4,

	-- Tienda de ventajas permanentes. Costs[n] = fichas del nivel n (el nivel máximo es
	-- #Costs). PerLevel: cuánto da cada nivel (su unidad depende de la ventaja).
	Shop = {
		PetSlot = {
			Order = 1,
			DisplayName = "Espacio de mascota",
			Icon = "🐾",
			Description = "+1 mascota equipada a la vez",
			PerLevel = 1,
			Costs = { 3, 10 },
		},
		Loot = {
			Order = 2,
			DisplayName = "Botín abundante",
			Icon = "💰",
			Description = "+25 % de 💰 al derrotar enemigos",
			PerLevel = 0.25,
			Costs = { 1, 2, 4, 6 },
		},
		Strike = {
			Order = 3,
			DisplayName = "Golpe renacido",
			Icon = "⚔",
			Description = "+15 % de daño (ataques, habilidades y mascotas)",
			PerLevel = 0.15,
			Costs = { 1, 2, 4, 6 },
		},
	},

	-- Presentación (cliente).
	Colors = {
		Glow = Color3.fromRGB(255, 214, 120),
		Halo = {
			Color3.fromRGB(255, 214, 120), -- 1-4: dorado
			Color3.fromRGB(150, 220, 255), -- 5-9: celeste
			Color3.fromRGB(214, 150, 255), -- 10-19: violeta
			Color3.fromRGB(255, 120, 150), -- 20+: rubí
		},
	},
	HaloTiers = { 1, 5, 10, 20 }, -- renacimientos a partir de los que cambia el color del aura
	Sounds = {
		Rebirth = "rbxassetid://9116394876",
		Burst = "rbxasset://sounds/impact_explosion_03.mp3",
		Shop = "rbxasset://sounds/electronicpingshort.wav",
	},
}

return RebirthConfig
