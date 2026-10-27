-- Lógica pura de las oleadas, la racha, el orbe dorado y la energía de cada enemigo (sin
-- APIs de Roblox, para probarla fuera de Studio: batería "waves"). La usan WaveService y
-- EnemyService para decidir y WaveController para mostrar. Números en WaveConfig.
-- El azar llega como una función rng() que devuelve un número en [0, 1) (math.random en
-- el juego, una secuencia fija en las pruebas).

local WaveConfig = require(script.Parent.Config.WaveConfig)
local EnemyConfig = require(script.Parent.Config.EnemyConfig)

local WaveLogic = {}

export type Levels = { [string]: number } -- mejoras de la partida: cardId -> nivel
export type Mods = {
	Damage: number, -- multiplicador del daño del arma
	Cooldown: number, -- multiplicador del tiempo entre disparos
	Chain: number, -- saltos extra a otros enemigos
	Splash: { Radius: number, Fraction: number }?,
	Twin: number, -- probabilidad de disparo extra
	Explode: { Radius: number, ShotMultiplier: number }?,
	Loot: number, -- multiplicador del botín (💎 y 💰)
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

-- Modo de la práctica del tutorial (el que tiene Tutorial = true), o nil.
function WaveLogic.tutorialArena(): string?
	for arenaId, arena in WaveConfig.Arenas do
		if arena.Tutorial then
			return arenaId
		end
	end
	return nil
end

-- Número total de oleadas de un modo (las de hordas + la del jefe, si tiene).
function WaveLogic.waveCount(arenaId: string): number
	local arena = WaveConfig.Arenas[arenaId]
	if not arena then
		return 0
	end
	return #arena.Waves + (if arena.Boss then 1 else 0)
end

function WaveLogic.isBossWave(arenaId: string, wave: number): boolean
	local arena = WaveConfig.Arenas[arenaId]
	return arena ~= nil and arena.Boss ~= nil and wave == WaveLogic.waveCount(arenaId)
end

-- ¿Tiene modo infinito? (los modos con jefe, salvo Endless = false; la práctica no)
function WaveLogic.hasEndless(arenaId: string): boolean
	local arena = WaveConfig.Arenas[arenaId]
	return arena ~= nil and arena.Boss ~= nil and not arena.Tutorial and arena.Endless ~= false and WaveConfig.Endless ~= nil
end

-- Oleadas del modo infinito: después del jefe (oleada waveCount + k, k >= 1) salen los de
-- la última oleada de hordas, CountGrowth más por cada k; cada StrongEvery, el doble de
-- fuertes. nil si no es una oleada infinita.
function WaveLogic.endlessCounts(arenaId: string, wave: number): { [string]: number }?
	local arena = WaveConfig.Arenas[arenaId]
	local k = math.floor(positive(wave)) - WaveLogic.waveCount(arenaId)
	if not (WaveLogic.hasEndless(arenaId) and k >= 1 and #arena.Waves > 0) then
		return nil
	end
	local settings = WaveConfig.Endless
	local base = arena.Waves[#arena.Waves]
	local scale = 1 + positive(settings.CountGrowth) * k
	local strongWave = (settings.StrongEvery or 0) > 0 and k % settings.StrongEvery == 0
	local counts = {}
	for typeId, count in base do
		local n = math.max(1, math.floor(positive(count) * scale + 0.5))
		local def = EnemyConfig.Types[typeId]
		if strongWave and def and def.Kind == "Strong" then
			n *= 2
		end
		counts[typeId] = n
	end
	return counts
end

-- Enemigos de una oleada de hordas, en orden de aparición: los tipos se reparten a lo
-- largo de la oleada (no salen todos los fuertes juntos) y el azar solo baraja un poco
-- dentro de cada tramo. Lista vacía si la oleada no existe o es la del jefe. Las que vienen
-- después del jefe son las del modo infinito (endlessCounts).
function WaveLogic.spawnList(arenaId: string, wave: number, rng: () -> number): { string }
	local arena = WaveConfig.Arenas[arenaId]
	local counts = arena and (arena.Waves[wave] or WaveLogic.endlessCounts(arenaId, wave))
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

-- Enemigos vivos a la vez como mucho en la oleada `wave` (las primeras, menos).
function WaveLogic.maxAlive(wave: number): number
	local w = math.max(1, math.floor(positive(wave)))
	local start = WaveConfig.AliveStart or WaveConfig.MaxAlive
	local growth = WaveConfig.AliveGrowth or 0
	return math.max(1, math.min(WaveConfig.MaxAlive, math.floor(start + growth * (w - 1))))
end

-- Daño de los enemigos de la oleada `wave` frente al de su configuración.
function WaveLogic.damageMultiplier(wave: number): number
	local w = math.max(1, math.floor(positive(wave)))
	local start = WaveConfig.DamageStart or 1
	local growth = WaveConfig.DamageGrowth or 0
	local cap = WaveConfig.DamageMax or start
	return math.min(cap, start + growth * (w - 1))
end

function WaveLogic.bossHealthMultiplier(players: number): number
	local n = math.max(1, math.floor(positive(players)))
	return 1 + WaveConfig.BossPlayerHealth * (n - 1)
end

function WaveLogic.rewardMultiplier(wave: number): number
	local w = math.max(1, math.floor(positive(wave)))
	return 1 + WaveConfig.RewardGrowth * (w - 1)
end

-- Multiplicador de los premios de un modo (RewardScale: zonas más altas, más premio).
local function rewardScale(arenaId: string?): number
	local arena = arenaId and WaveConfig.Arenas[arenaId]
	return if arena and arena.RewardScale ~= nil then positive(arena.RewardScale) else 1
end

-- Premio por limpiar la oleada `wave` (💎, 💰) en el modo `arenaId` (opcional). Los 💎 los
-- multiplica después WaveService con PlayerDataService.diamondMultiplier.
function WaveLogic.clearReward(wave: number, arenaId: string?): (number, number)
	local w = math.max(1, math.floor(positive(wave)))
	local scale = rewardScale(arenaId)
	return math.floor(WaveConfig.ClearDiamonds * w * scale), math.floor(WaveConfig.ClearMoney * w * scale)
end

-- Premio de victoria (💎, 💰); cada modo puede escalarlo (RewardScale y VictoryScale: la
-- práctica del tutorial da menos).
function WaveLogic.victoryReward(arenaId: string?): (number, number)
	local arena = arenaId and WaveConfig.Arenas[arenaId]
	local scale = (if arena and arena.VictoryScale ~= nil then positive(arena.VictoryScale) else 1) * rewardScale(arenaId)
	return math.floor(WaveConfig.VictoryDiamonds * scale), math.floor(WaveConfig.VictoryMoney * scale)
end

-- Cofre de victoria de las mazmorras (Arenas.*.Chest): (💰, poción o nil). `rollPotion` y
-- `rollWhich` en [0, 1); `potions`: las que pueden salir (ItemLogic.potionOrder()). Sin
-- cofre en ese modo: (0, nil).
function WaveLogic.chestReward(arenaId: string?, rollPotion: number, rollWhich: number, potions: { string }?): (number, string?)
	local arena = arenaId and WaveConfig.Arenas[arenaId]
	local chest = arena and arena.Chest
	if not chest then
		return 0, nil
	end
	local money = math.floor(positive(chest.Money))
	local potion = nil
	local list = potions or {}
	if #list > 0 and positive(chest.PotionChance) > 0 and rollPotion < chest.PotionChance then
		potion = list[math.clamp(math.floor(rollWhich * #list) + 1, 1, #list)]
	end
	return money, potion
end

-- ¿Sale élite este bicho de una oleada? (Arenas.*.EliteChance; `roll` en [0, 1)). Los jefes y
-- la escolta, nunca (quien llama no lo pregunta).
function WaveLogic.isElite(arenaId: string?, roll: number): boolean
	local arena = arenaId and WaveConfig.Arenas[arenaId]
	local chance = if arena then positive(arena.EliteChance) else 0
	return chance > 0 and roll < chance
end

-- ¿Toca elegir mejora al terminar la oleada `wave`? (nunca tras la última; en el modo
-- infinito siguen saliendo cada CardEvery)
function WaveLogic.isCardWave(arenaId: string, wave: number): boolean
	local arena = WaveConfig.Arenas[arenaId]
	local every = if arena and arena.CardEvery then arena.CardEvery else WaveConfig.CardEvery
	local count = WaveLogic.waveCount(arenaId)
	return every > 0 and wave >= 1 and wave % every == 0 and (wave < count or (wave > count and WaveLogic.hasEndless(arenaId)))
end

-- Consejo de un modo para un momento de la partida ("Countdown", "Cards", "Victory" o el
-- número de la oleada que empieza). nil si no tiene.
function WaveLogic.hint(arenaId: string, key: any): string?
	local arena = WaveConfig.Arenas[arenaId]
	local hints = arena and arena.Hints
	local text = hints and hints[key]
	return if type(text) == "string" then text else nil
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

-- 💎 de un enemigo para quien recibe `share` de su recompensa (la parte del dinero que le
-- toca, antes de multiplicadores).
function WaveLogic.killDiamonds(share: number, killShare: number): number
	return positive(share) * positive(killShare)
end

-- Un número de 💎 con decimales -> entero: lo que falta para el siguiente es su probabilidad
-- (`roll` en [0, 1)). 1.3 da 1 o 2 (un 30 % de las veces 2).
function WaveLogic.roundDiamonds(amount: number, roll: number): number
	local value = positive(amount)
	local whole = math.floor(value)
	return whole + (if positive(roll) < value - whole then 1 else 0)
end

-- Récords del jugador (campo Waves del guardado, v10) --------------------------------------
-- Cleared: oleadas superadas en total (clasificación "Oleadas superadas"); Best: la oleada
-- más alta superada en cada modo (las del modo infinito cuentan: 11, 12...). La práctica
-- del tutorial no cuenta.

export type Records = { Cleared: number, Best: { [string]: number } }

local MAX_RECORD_MODES = 20

function WaveLogic.emptyRecords(): Records
	return { Cleared = 0, Best = {} }
end

-- Datos guardados (o cualquier cosa) -> récords válidos; siempre una tabla nueva.
function WaveLogic.sanitizeRecords(raw: any): Records
	local result = WaveLogic.emptyRecords()
	if type(raw) ~= "table" then
		return result
	end
	if isFiniteNumber(raw.Cleared) and raw.Cleared > 0 then
		result.Cleared = math.min(math.floor(raw.Cleared), 1e9)
	end
	if type(raw.Best) == "table" then
		local count = 0
		for arenaId, wave in raw.Best do
			if type(arenaId) == "string" and #arenaId <= 64 and isFiniteNumber(wave) and wave >= 1 and count < MAX_RECORD_MODES then
				result.Best[arenaId] = math.min(math.floor(wave), 1e6)
				count += 1
			end
		end
	end
	return result
end

-- Copia para guardar.
function WaveLogic.serializeRecords(records: any): Records
	return WaveLogic.sanitizeRecords(records)
end

-- Mejor oleada superada en un modo (0 si ninguna).
function WaveLogic.bestWave(records: any, arenaId: string): number
	local best = type(records) == "table" and type(records.Best) == "table" and records.Best[arenaId]
	return if isFiniteNumber(best) and best > 0 then math.floor(best) else 0
end

-- Oleada `wave` superada en el modo `arenaId`: suma una a las superadas y sube el récord
-- de ese modo. true si es un récord nuevo. La práctica y los modos que no existen no cuentan.
function WaveLogic.recordWave(records: Records, arenaId: string, wave: number): boolean
	local arena = WaveConfig.Arenas[arenaId]
	local w = math.floor(positive(wave))
	if not arena or arena.Tutorial or w < 1 or type(records) ~= "table" or type(records.Best) ~= "table" then
		return false
	end
	records.Cleared = math.min(math.floor(positive(records.Cleared)) + 1, 1e9)
	if w > WaveLogic.bestWave(records, arenaId) then
		records.Best[arenaId] = math.min(w, 1e6)
		return true
	end
	return false
end

return WaveLogic
