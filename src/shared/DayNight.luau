-- Ciclo de día y noche (puro, sin APIs de Roblox salvo Color3), para probarlo fuera de
-- Studio. La hora del juego sale de la hora del servidor (workspace:GetServerTimeNow() en
-- el cliente), así que todos los jugadores ven el mismo momento del día.
-- Configuración: WorldConfig.DayNight.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.WorldConfig)

local DayNight = {}

local Settings = WorldConfig.DayNight

local function cycleSeconds(): number
	return Settings.CycleMinutes * 60
end

-- Fracción (0..1) del ciclo en una hora del servidor.
function DayNight.phase(serverTime: number): number
	local length = cycleSeconds()
	return (serverTime % length) / length
end

-- Hora de Roblox (Lighting.ClockTime, 0..24) en una fracción del ciclo.
function DayNight.clockAtPhase(phase: number): number
	local keys = Settings.Keys
	local p = math.clamp(phase, 0, 1)
	for index = 1, #keys - 1 do
		local a, b = keys[index], keys[index + 1]
		if p <= b[1] then
			local t = if b[1] > a[1] then (p - a[1]) / (b[1] - a[1]) else 0
			return (a[2] + (b[2] - a[2]) * t) % 24
		end
	end
	return keys[#keys][2] % 24
end

function DayNight.clockAt(serverTime: number): number
	return DayNight.clockAtPhase(DayNight.phase(serverTime))
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Cuánto es de noche (0 = pleno día, 1 = noche cerrada) a una hora de Roblox: sube al
-- atardecer (17 h -> 19 h) y baja al amanecer (5 h -> 7 h).
function DayNight.nightFactor(clockTime: number): number
	local c = clockTime % 24
	if c >= 7 and c <= 17 then
		return 0
	elseif c > 17 and c < 19 then
		return smooth((c - 17) / 2)
	elseif c > 5 and c < 7 then
		return smooth((7 - c) / 2)
	end
	return 1
end

-- Luz que toca: { ClockTime, OutdoorAmbient, Ambient, Night }. `day` = la luz de día del
-- juego ({ OutdoorAmbient, Ambient }).
function DayNight.lighting(serverTime: number, day: { OutdoorAmbient: Color3, Ambient: Color3 }): any
	local clock = DayNight.clockAt(serverTime)
	local night = DayNight.nightFactor(clock)
	return {
		ClockTime = clock,
		Night = night,
		OutdoorAmbient = day.OutdoorAmbient:Lerp(Settings.NightOutdoorAmbient, night),
		Ambient = day.Ambient:Lerp(Settings.NightAmbient, night),
	}
end

function DayNight.isFixedZone(zoneId: any): boolean
	return typeof(zoneId) == "string" and Settings.FixedZones[zoneId] == true
end

function DayNight.enabled(): boolean
	return Settings.Enabled == true
end

return DayNight
