-- WaveService · tipos que comparten sus partes (antes estaban en WaveService.luau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WaveLogic = require(Shared.WaveLogic)

export type Participant = {
	Player: Player,
	Levels: WaveLogic.Levels,
	Mods: WaveLogic.Mods,
	Choices: { string }?, -- mejoras para elegir ahora (nil si no toca)
	Kills: number,
	Diamonds: number,
	Money: number,
	Golden: number,
	BestStreak: number,
	StartBest: number, -- su récord en este modo al empezar (WaveLogic.Records)
	NewBest: boolean, -- ha superado su récord en esta partida
	RecordShown: boolean, -- ya se le avisó del récord nuevo
	Continue: boolean?, -- modo infinito: true sigue, false se va, nil aún no ha elegido
	VictoryDiamonds: number, -- premio de victoria ya cobrado
	VictoryMoney: number,
}

export type Run = {
	Id: number,
	ArenaId: string, -- modo (WaveConfig.Arenas)
	Arena: any,
	PlaceId: string, -- círculo (WaveConfig.Places)
	Slot: number, -- hueco 1..MaxRuns (grupo de colisión de sus enemigos)
	ZoneId: string,
	Center: Vector3,
	Phase: string, -- "Countdown" | "Wave" | "Break" | "Cards" | "Boss" | "Choice" | "Done"
	Endless: boolean, -- en el modo infinito (tras ganarle al jefe)
	VictoryPaid: boolean, -- el premio de victoria ya se cobró (al caer el jefe)
	Wave: number,
	Waves: number,
	EndsAt: number, -- os.clock() en que acaba la fase (cuenta atrás, pausa, mejoras)
	Queue: { string }, -- enemigos que faltan por salir en esta oleada
	Alive: { [any]: boolean },
	AliveCount: number,
	Total: number,
	Killed: number,
	Players: number, -- jugadores dentro al empezar la oleada (vida de los enemigos)
	Participants: { [Player]: Participant },
	EmptySince: number?,
	NextSpawnAt: number,
	NextEscortAt: number,
	-- Jefes vivos de la partida: uno, o los dos en que se parte el Coloso del Equilibrio
	-- (EnemyConfig.Types.*.Split). Se gana cuando cae el último.
	Bosses: { any },
	LastBroadcast: number,
}

export type Place = {
	Id: string,
	ArenaId: string, -- modo que se juega aquí
	Practice: boolean, -- solo la práctica del tutorial (WaveConfig.Places.*.Practice)
	ZoneId: string,
	Center: Vector3,
	SpawnPoints: { Vector2 }?, -- por dónde salen los bichos (si no, el anillo del altar)
	SpawnJitter: number,
	LeashRadius: number?,
	InsideRadius: number?, -- hasta dónde se cuenta como dentro (si no, el círculo)
	StatusLabel: TextLabel?,
	InfoLabel: TextLabel?,
}

return {}
