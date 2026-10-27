-- EnemyService · tipos que comparten sus partes (antes estaban en EnemyService.luau).

local EnemyLogic = require(script.Parent.Parent.Parent.Util.EnemyLogic)

export type SafeZone = { Center: Vector3, Radius: number }
export type SafeArea = { Min: Vector2, Max: Vector2 } -- rectángulo en X/Z del mundo

export type Enemy = {
	Id: number,
	TypeId: string,
	Def: any,
	Kind: string,
	ZoneId: string,
	Model: Model,
	Root: BasePart,
	Humanoid: Humanoid,
	Eyes: { BasePart },
	EyeColor: Color3,
	Aura: ParticleEmitter?, -- aura de furia (solo jefes), apagada salvo en furia
	Glow: PointLight?, -- luz de furia (solo jefes), apagada salvo en furia
	Bar: Frame,
	Billboard: BillboardGui,
	RootHeight: number, -- altura del centro de la raíz sobre el suelo
	Radius: number, -- radio horizontal para recibir golpes
	DeathSeconds: number?, -- cuánto queda el cuerpo tras morir (modelos con animación Death)
	Home: Vector3,
	LeashCenter: Vector3,
	LeashRadius: number,
	DetectRange: number,
	SafeZones: { SafeZone },
	SafeAreas: { SafeArea },
	RewardMultiplier: number,
	Status: EnemyLogic.EnemyState,
	Control: EnemyLogic.Control, -- estados de las habilidades (os.clock)
	Target: Player?,
	NextAttack: number,
	WindupUntil: number?, -- preparando un golpe hasta entonces (os.clock): quieto, comprometido
	NextSlam: number,
	NextWander: number,
	Enraged: boolean,
	Generation: number, -- cambia en cada muerte/reaparición: invalida tareas pendientes
	StuckSince: number?,
	LastHomeDistance: number,
	Brain: any?, -- solo jefes con Def.Brain: su máquina de estados (updateBoss)
	-- Oleadas (WaveService)
	Pooled: boolean, -- de la reserva: no reaparece solo, vuelve a la reserva al morir
	InPool: boolean, -- en la reserva, esperando a que una oleada lo saque
	WaveControlled: boolean, -- jefe que solo sale en la última oleada (no reaparece solo)
	OnWaveDeath: ((any, Player?, Vector3) -> ())?, -- aviso al morir (enemigo, quién lo mató, dónde)
	LastHitBy: Player?, -- quién dio el último golpe (solo para OnWaveDeath)
	Run: number?, -- partida de oleadas a la que pertenece (nil = el mundo normal)
	MoneyMultiplier: number, -- dinero que suelta (golpes y derrota); la ⚡ no cambia
	DamageMultiplier: number?, -- daño que hace (oleadas; nil = 1)
	Territory: number?, -- territorio del jefe (si no, Def.Brain.Territory)
	Variant: string?, -- "Elite" o "MiniBoss" (mazmorras: más grande, brilla, más vida y botín)
	-- Jefe que se parte (oleadas: el Coloso del Equilibrio): al bajar a SplitAt de su vida
	-- máxima no baja más y se avisa a OnSplit (WaveService lo cambia por sus dos mitades)
	SplitAt: number?,
	OnSplit: ((any) -> ())?,
}

export type Rig = { Model: Model, Root: BasePart, Humanoid: Humanoid, Eyes: { BasePart }, RootHeight: number }

export type Brain = {
	State: string,
	Until: number,
	LockedUntil: number,
	Path: { Vector3 }?,
	PathIndex: number,
	PathGoal: Vector3?,
	PathAt: number,
	Computing: boolean,
	NextSpecial: { [string]: number },
	LastPosition: Vector3,
	StillSince: number,
	Dash: { Hit: { [Player]: boolean }, Until: number, Damage: number, Width: number }?,
}

export type WaveSpawnOptions = {
	LeashCenter: Vector3?, -- persigue a quien esté dentro de este círculo
	LeashRadius: number?,
	DetectRange: number?, -- distancia a la que ve a los jugadores
	HealthMultiplier: number?,
	RewardMultiplier: number?,
	PoolLimit: number?, -- como mucho estos de su tipo en la reserva
	OnDeath: ((any, Player?, Vector3) -> ())?,
	Run: number?, -- partida (oleadas privadas): solo la ven y lo golpean sus jugadores
	MoneyMultiplier: number?, -- dinero que suelta (la ⚡ no cambia)
	DamageMultiplier: number?, -- daño que hace a los jugadores
	CollisionSlot: number?, -- hueco de la partida (1..MaxRuns): chocan los del mismo hueco
	Elite: boolean?, -- élite (EnemyConfig.Elite): de su propia reserva, más grande y más fuerte
	-- Jefes: su arena (para la barra del jefe del cliente) y su territorio
	Arena: { Center: Vector3, Radius: number, Name: string }?,
	Territory: number?,
	-- Jefe que se parte: al bajar a SplitAt (parte de la vida máxima) se llama a OnSplit una vez
	SplitAt: number?,
	OnSplit: ((any) -> ())?,
}

return {}
