-- PetController · tipos que comparten sus partes (antes estaban en PetController.luau).

export type Snapshot = {
	Ready: boolean,
	Saving: boolean?,
	Pets: { { Uid: string, PetId: string } },
	Equipped: { string },
	MaxEquipped: number,
	MaxInventory: number,
}

return {}
