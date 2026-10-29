-- InventoryController · tipos que comparten sus partes (antes estaban en InventoryController.luau).

export type State = {
	Ready: boolean,
	Potions: { [string]: number },
	Eggs: { [string]: number },
	Boosts: { [string]: number },
	Titles: { [string]: boolean },
	Title: string,
	Progress: { [string]: { number } },
}

return {}
