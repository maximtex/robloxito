-- PetCombatService · tipos que comparten sus partes (antes estaban en PetCombatService.luau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WarriorLogic = require(Shared.WarriorLogic)

export type State = {
	Target: any?,
	AutoFire: boolean, -- interruptor (solo cuenta con el pase)
	AimPoint: Vector3?, -- último punto al que apuntó
	AimAt: number, -- cuándo llegó
	ShotRequestedAt: number, -- última petición de un disparo sin usar
	HeldUntil: number, -- mantiene pulsado hasta
	LastHitAt: number,
	NextShotAt: number,
	PetNextHit: { [number]: number },
	Generation: number,
	Style: string?, -- estilo del último paso (al cambiar se reinicia lo de cada estilo)
	-- Armas
	Ammo: number,
	AmmoWeapon: string?, -- arma a la que corresponden las balas
	ReloadUntil: number, -- os.clock() del fin de la recarga (0 = no recarga)
	ReloadEnd: number, -- lo mismo en hora del servidor (para el cliente)
	Ads: boolean, -- apuntando (clic derecho)
	-- Magia
	Mana: number,
	ManaAt: number,
	ManaSpentAt: number,
	ChargeStart: number?, -- cargando un orbe desde
	PendingCharge: number?, -- segundos cargados de un orbe soltado (se lanza en el paso)
	-- Guerrero
	Combo: WarriorLogic.ComboState,
	Block: WarriorLogic.BlockState,
	CounterUntil: number, -- hasta cuándo el siguiente tajo es un contraataque
}

return {}
