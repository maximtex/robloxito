-- Equipo visible (pruebas con amigos: "no se nota la clase ni lo que mejoras"). Además de lo
-- que llevas en la mano (GearService), cada clase lleva su pieza y la mejora de Armadura se ve
-- en el cuerpo. Lógica pura: qué se lleva; los modelos los hace GearModels.outfit.
--
-- Pieza de cada clase (StyleConfig.Styles):
--   Weapons (Arquero)  carcaj a la espalda con flechas y correa al pecho
--   Warrior (Guerrero) escudo redondo a la espalda
--   Fists   (Puños)    cinta en la frente y fajín
--   Magic   (Magia)    capa
-- Armadura (EconomyConfig.Upgrades.Armor, nivel 0..10): cada umbral de ArmorTiers añade o
-- mejora piezas (1 hombreras de cuero, 2 de hierro, 3 + peto, 4 todo dorado).

local OutfitLogic = {}

OutfitLogic.Pieces = {
	Weapons = "Quiver",
	Warrior = "Shield",
	Fists = "Headband",
	Magic = "Cape",
}

-- Nivel de Armadura desde el que se ve cada grado
OutfitLogic.ArmorTiers = { 1, 4, 7, 10 }

OutfitLogic.TierNames = { "Cuero", "Hierro", "Acero", "Oro" }

-- Grado de armadura (0 = sin armadura) para un nivel de Armadura
function OutfitLogic.armorTier(level: any): number
	local value = if type(level) == "number" and level == level then level else 0
	local tier = 0
	for index, minimum in OutfitLogic.ArmorTiers do
		if value >= minimum then
			tier = index
		end
	end
	return tier
end

-- Pieza de la clase (nil si el estilo no tiene)
function OutfitLogic.piece(styleId: any): string?
	return if type(styleId) == "string" then OutfitLogic.Pieces[styleId] else nil
end

-- Lo que lleva, como texto: si no cambia, no se rehace el modelo
function OutfitLogic.key(styleId: any, armorLevel: any): string
	return ("%s:%d"):format(OutfitLogic.piece(styleId) or "-", OutfitLogic.armorTier(armorLevel))
end

-- Qué piezas de armadura lleva en un grado: hombreras (y de qué), peto y si brilla
export type Armor = { Shoulders: string?, Chest: boolean, Trim: boolean }
function OutfitLogic.armor(tier: number): Armor
	return {
		Shoulders = if tier >= 1 then OutfitLogic.TierNames[math.min(tier, #OutfitLogic.TierNames)] else nil,
		Chest = tier >= 3,
		Trim = tier >= 4,
	}
end

return OutfitLogic
