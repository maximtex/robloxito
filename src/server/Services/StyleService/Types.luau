-- StyleService · tipos que comparten sus partes (antes estaban en StyleService.luau).


-- Lo que comparten los golpes de una habilidad: quién, su estilo y su nivel, y el primer
-- combo que salta (para avisarlo una vez).
export type Cast = {
	Player: Player,
	Style: string,
	SkillId: string,
	Damage: number, -- daño base de cada golpe (DPS × DamageRatio × nivel)
	Buffed: boolean,
	Color: Color3?, -- el de sus efectos (las del Mundo 2 traen el suyo)
	Aim: Vector3?, -- punto al que apuntaba el jugador al usarla (ratón, toque o delante)
	Element: string?, -- Magia: deja su marca elemental y dispara combos (AbilityService)
	Combo: string?,
	ComboAt: Vector3?,
}

return {}
