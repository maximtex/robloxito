-- Ciclo de día y noche en este cliente (DayNight + WorldConfig.DayNight). La hora sale de
-- la del servidor, así que todos los jugadores ven el mismo momento del día. En las zonas
-- con luz fija (la Caldera: atardecer permanente) manda PortalController; al volver, la luz
-- del ciclo se recupera poco a poco (sin saltos).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local WorldConfig = require(Shared.Config.WorldConfig)
local DayNight = require(Shared.DayNight)

local DayNightController = {}

local BLEND_SECONDS = 2.5

local player = Players.LocalPlayer
local night = 0

-- Cuánto es de noche ahora (0..1). La usan las luciérnagas y los sonidos del bosque.
function DayNightController.night(): number
	return night
end

local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Interpola horas por el camino corto (23 h -> 1 h pasa por medianoche).
local function lerpClock(a: number, b: number, t: number): number
	local delta = ((b - a + 12) % 24) - 12
	return (a + delta * t) % 24
end

function DayNightController.start()
	if not DayNight.enabled() then
		return
	end
	local day = {
		OutdoorAmbient = WorldConfig.Lighting.OutdoorAmbient,
		Ambient = WorldConfig.Lighting.Ambient,
	}
	local fixed = false
	local blendFrom: any = nil
	local blendStart = 0
	local accumulator = 0

	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		accumulator = 0
		local zoneId = player:GetAttribute(Constants.Attributes.CurrentZone)
		if DayNight.isFixedZone(zoneId) then
			if not fixed then
				Lighting.ExposureCompensation = 0
			end
			fixed = true
			night = 0
			return
		end
		if fixed then
			-- Se sale de una zona de luz fija: se mezcla desde la luz que haya ahora.
			fixed = false
			blendFrom = { ClockTime = Lighting.ClockTime, OutdoorAmbient = Lighting.OutdoorAmbient, Ambient = Lighting.Ambient }
			blendStart = os.clock()
		end
		local target = DayNight.lighting(Workspace:GetServerTimeNow(), day)
		-- Para pruebas en Studio: el atributo ClockOverride de Workspace fija la hora.
		local override = Workspace:GetAttribute("ClockOverride")
		if typeof(override) == "number" then
			local fixedNight = DayNight.nightFactor(override)
			target = {
				ClockTime = override % 24,
				Night = fixedNight,
				OutdoorAmbient = day.OutdoorAmbient:Lerp(WorldConfig.DayNight.NightOutdoorAmbient, fixedNight),
				Ambient = day.Ambient:Lerp(WorldConfig.DayNight.NightAmbient, fixedNight),
			}
		end
		night = target.Night
		local clock, outdoor, ambient = target.ClockTime, target.OutdoorAmbient, target.Ambient
		if blendFrom then
			local t = math.clamp((os.clock() - blendStart) / BLEND_SECONDS, 0, 1)
			clock = lerpClock(blendFrom.ClockTime, clock, t)
			outdoor = blendFrom.OutdoorAmbient:Lerp(outdoor, t)
			ambient = blendFrom.Ambient:Lerp(ambient, t)
			if t >= 1 then
				blendFrom = nil
			end
		end
		Lighting.ClockTime = clock
		Lighting.OutdoorAmbient = outdoor
		Lighting.Ambient = ambient
		Lighting.ExposureCompensation = lerpNumber(0, WorldConfig.DayNight.NightExposure or 0, night)
	end)
end

return DayNightController
