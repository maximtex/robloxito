-- Lógica pura de las oleadas, la racha, el orbe dorado y la energía de cada enemigo (sin
-- APIs de Roblox, para probarla fuera de Studio: batería "waves"). La usan WaveService y
-- EnemyService para decidir y WaveController para mostrar. Números en WaveConfig.
-- El azar llega como una función rng() que devuelve un número en [0, 1) (math.random en
-- el juego, una secuencia fija en las pruebas).

local WaveConfig = require(script.Parent.Config.WaveConfig)

local WaveLogic = {}

export type Levels = { [string]: number } -- mejoras de la partida: cardId -> nivel
export type Mods = {
	Damage: number, -- multiplicador del daño del arma
	Cooldown: number, -- multiplicador del tiempo entre disparos
	Chain: number, -- saltos extra a otros enemigos
	Splash: { Radius: number, Fraction: number }?,
	Twin: number, -- probabilidad de disparo extra
	Explode: { Radius: number, ShotMultiplier: number }?,
	Loot: number, -- multiplicador del botín (⚡ y 💰)
	Heal: number, -- vida por enemigo derrotado
	StreakSeconds: number, -- segundos extra de la ventana de la racha
}
export type Streak = { Count: number, Until: number, Best: number }

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function positive(value: any): number
	return if isFiniteNumber(value) and value > 0 then value else 0
end

-- Oleadas --------------------------------------------------------------------------

function WaveLogic.arena(arenaId: string): any?
	return WaveConfig.Arenas[arenaId]
end

-- Número total de oleadas de una arena (las de hordas + la del jefe).
function WaveLogic.waveCount(arenaId: string): number
	local arena = WaveConfig.Arenas[arenaId]
	return if arena then #arena.Waves + 1 else 0
end

function WaveLogic.isBossWave(arenaId: string, wave: number): boolean
	return wave == WaveLogic.waveCount(arenaId)
end

-- Enemigos de una oleada de hordas, en orden de aparición: los tipos se reparten a lo
-- largo de la oleada (no salen todos los fuertes juntos) y el azar solo baraja un poco
-- dentro de cada tramo. Lista vacía si la oleada no existe o es la del jefe.
function WaveLogic.spawnList(arenaId: string, wave: number, rng: () -> number): { string }
	local arena = WaveConfig.Arenas[arenaId]
	local counts = arena and arena.Waves[wave]
	if not counts then
		return {}
	end
	-- Cada enemigo con su "momento" ideal (k + 0.5) / n dentro de la oleada, más un poco de
	-- azar; se ordena por ese momento (con desempate estable por tipo y número).
	local entries = {}
	local types = {}
	for typeId in counts do
		table.insert(types, typeId)
	end
	table.sort(types)
	for _, typeId in types do
		local n = math.floor(positive(counts[typeId]))
		for k = 0, n - 1 do
			local jitter = (rng() - 0.5) * 0.5 / math.max(n, 1)
			table.insert(entries, { Type = typeId, At = (k + 0.5) / n + jitter, Key = typeId .. k })
		end
	end
	table.sort(entries, function(a, b)
		if a.At ~= b.At then
			return a.At < b.At
		end
		return a.Key < b.Key
	end)
	local list = {}
	for _, entry in entries do
		table.insert(list, entry.Type)
	end
	return list
end

function WaveLogic.healthMultiplier(wave: number, players: number): number
	local w = math.max(1, math.floor(positive(wave)))
	local n = math.max(1, math.floor(positive(players)))
	return (1 + WaveConfig.HealthGrowth * (w - 1)) * (1 + WaveConfig.PlayerHealth * (n - 1))
end

function WaveLogic.bossHealthMultiplier(players: number): number
	local n = math.max(1, math.floor(positive(players)))
	return 1 + WaveConfig.BossPlayerHealth * (n - 1)
end

function WaveLogic.rewardMultiplier(wave: number): number
	local w = math.max(1, math.floor(positive(wave)))
	return 1 + WaveConfig.RewardGrowth * (w - 1)
end

-- Premio por limpiar la oleada `wave` (⚡, 💰) con un poder de energía `power`.
function WaveLogic.clearReward(wave: number, power: number): (number, number)
	local w = math.max(1, math.floor(positive(wave)))
	local p = math.max(1, positive(power))
	return math.floor(WaveConfig.ClearEnergy * w * p), math.floor(WaveConfig.ClearMoney * w)
end

function WaveLogic.victoryReward(power: number): (number, number)
	local p = math.max(1, positive(power))
	return math.floor(WaveConfig.VictoryEnergy * p), math.floor(WaveConfig.VictoryMoney)
end

-- ¿Toca elegir mejora al terminar la oleada `wave`? (nunca tras la del jefe)
function WaveLogic.isCardWave(arenaId: string, wave: number): boolean
	local every = WaveConfig.CardEvery
	return every > 0 and wave >= 1 and wave % every == 0 and wave < WaveLogic.waveCount(arenaId)
end

-- Mejoras ------------------------------------------------------------------------------

local function orderedCards(): { string }
	local ids = {}
	for cardId in WaveConfig.Cards do
		table.insert(ids, cardId)
	end
	table.sort(ids, function(a, b)
		return WaveConfig.Cards[a].Order < WaveConfig.Cards[b].Order
	end)
	return ids
end

function WaveLogic.levelOf(levels: Levels?, cardId: string): number
	local value = levels and levels[cardId]
	return if isFiniteNumber(value) and value > 0 then math.floor(value) else 0
end

-- Hasta `count` mejoras distintas que aún se pueden subir, al azar.
function WaveLogic.rollCards(levels: Levels?, rng: () -> number, count: number?): { string }
	local available = {}
	for _, cardId in orderedCards() do
		if WaveLogic.levelOf(levels, cardId) < WaveConfig.Cards[cardId].MaxLevel then
			table.insert(available, cardId)
		end
	end
	local wanted = math.min(count or WaveConfig.CardChoices, #available)
	local choices = {}
	for _ = 1, wanted do
		local index = math.clamp(math.floor(rng() * #available) + 1, 1, #available)
		table.insert(choices, table.remove(available, index))
	end
	return choices
end

-- Sube una mejora si se puede (existe y no está al máximo). true si se ha subido.
function WaveLogic.pick(levels: Levels, cardId: any): boolean
	local card = type(cardId) == "string" and WaveConfig.Cards[cardId]
	if not card then
		return false
	end
	local level = WaveLogic.levelOf(levels, cardId)
	if level >= card.MaxLevel then
		return false
	end
	levels[cardId] = level + 1
	return true
end

-- Efecto total de las mejoras de un jugador.
function WaveLogic.modifiers(levels: Levels?): Mods
	local mods: Mods = { Damage = 1, Cooldown = 1, Chain = 0, Splash = nil, Twin = 0, Explode = nil, Loot = 1, Heal = 0, StreakSeconds = 0 }
	for cardId, card in WaveConfig.Cards do
		local level = math.min(WaveLogic.levelOf(levels, cardId), card.MaxLevel)
		if level > 0 then
			if card.Damage then
				mods.Damage += card.Damage * level
			end
			if card.Cooldown then
				mods.Cooldown *= card.Cooldown ^ level
			end
			if card.Chain then
				mods.Chain += card.Chain * level
			end
			if card.Splash then
				mods.Splash = { Radius = card.Splash.Radius + card.Splash.RadiusPerLevel * (level - 1), Fraction = card.Splash.Fraction }
			end
			if card.Twin then
				mods.Twin = math.min(1, mods.Twin + card.Twin * level)
			end
			if card.Explode then
				mods.Explode = { Radius = card.Explode.Radius, ShotMultiplier = card.Explode.ShotMultiplier * level }
			end
			if card.Loot then
				mods.Loot += card.Loot * level
			end
			if card.Heal then
				mods.Heal += card.Heal * level
			end
			if card.StreakSeconds then
				mods.StreakSeconds += card.StreakSeconds * level
			end
		end
	end
	return mods
end

-- Racha ---------------------------------------------------------------------------------

function WaveLogic.newStreak(): Streak
	return { Count = 0, Until = -math.huge, Best = 0 }
end

-- Suma un enemigo derrotado en el instante `now` (segundos). Devuelve la racha nueva.
function WaveLogic.streakKill(streak: Streak, now: number, extraSeconds: number?): number
	if now > streak.Until then
		streak.Count = 0
	end
	streak.Count += 1
	streak.Until = now + WaveConfig.Streak.Window + positive(extraSeconds)
	if streak.Count > streak.Best then
		streak.Best = streak.Count
	end
	return streak.Count
end

-- Racha vigente (0 si ya caducó).
function WaveLogic.streakCount(streak: Streak?, now: number): number
	if not streak or now > streak.Until then
		return 0
	end
	return streak.Count
end

function WaveLogic.streakMultiplier(count: number): number
	local settings = WaveConfig.Streak
	local steps = math.floor(positive(count) / settings.Step)
	return 1 + math.min(steps * settings.StepBonus, settings.MaxBonus)
end

-- Botín de cada enemigo -----------------------------------------------------------------

-- ¿Orbe dorado? Nunca en los jefes.
function WaveLogic.rollGolden(rng: () -> number, isBoss: boolean): boolean
	if isBoss then
		return false
	end
	return rng() < WaveConfig.GoldenOrb.Chance
end

function WaveLogic.goldenMultiplier(golden: boolean): number
	return if golden then WaveConfig.GoldenOrb.Multiplier else 1
end

-- Energía de un enemigo para quien recibe `share` de su recompensa (la parte del dinero
-- que le toca, antes de multiplicadores), con su poder de energía.
function WaveLogic.killEnergy(share: number, killShare: number, power: number): number
	return positive(share) * positive(killShare) * math.max(1, positive(power))
end

return WaveLogic
