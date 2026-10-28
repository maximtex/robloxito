-- Ajustes del jugador (⚙️ Ajustes) que se guardan con su partida (campo Settings del guardado
-- v18). Lógica pura: la usan SaveService (sanear y guardar), SettingsService (validar lo que
-- pide el cliente) y el cliente (mostrar y aplicar).
--
-- Datos (profile.PetData.Settings):
--   HudScale: number   tamaño de la interfaz elegido (uno de HudScales; 1 = el normal).
--                      Multiplica la escala que HudLayout calcula para la pantalla: los
--                      amigos que lo probaron decían que el HUD tapaba demasiado.

local SettingsLogic = {}

export type Settings = {
	HudScale: number,
}

-- Tamaños que se pueden elegir (de menor a mayor). Solo para achicar: más grande que el
-- normal no cabe en pantallas pequeñas (lo comprueba la suite "hudlayout").
SettingsLogic.HudScales = { 0.6, 0.7, 0.8, 0.9, 1 }
SettingsLogic.DefaultHudScale = 1

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- El tamaño permitido más cercano a `value` (el normal si no es un número válido).
function SettingsLogic.sanitizeHudScale(value: any): number
	if not isFiniteNumber(value) then
		return SettingsLogic.DefaultHudScale
	end
	local best, bestDiff = SettingsLogic.DefaultHudScale, math.huge
	for _, scale in SettingsLogic.HudScales do
		local diff = math.abs(scale - value)
		if diff < bestDiff - 1e-9 then
			best, bestDiff = scale, diff
		end
	end
	return best
end

function SettingsLogic.empty(): Settings
	return { HudScale = SettingsLogic.DefaultHudScale }
end

-- Sin el campo (v17 o anteriores) o con valores raros: los ajustes por defecto.
function SettingsLogic.sanitize(raw: any): Settings
	local result = SettingsLogic.empty()
	if type(raw) == "table" then
		result.HudScale = SettingsLogic.sanitizeHudScale(raw.HudScale)
	end
	return result
end

function SettingsLogic.serialize(settings: Settings?): { HudScale: number }
	local clean = SettingsLogic.sanitize(settings)
	return { HudScale = clean.HudScale }
end

-- El tamaño `steps` posiciones más grande (o más pequeño si es negativo), sin salirse de la
-- lista.
function SettingsLogic.stepHudScale(current: any, steps: number): number
	local list = SettingsLogic.HudScales
	local value = SettingsLogic.sanitizeHudScale(current)
	local index = table.find(list, value) or 1
	return list[math.clamp(index + math.floor(steps), 1, #list)]
end

-- "90 %"
function SettingsLogic.hudScaleLabel(value: any): string
	return ("%d %%"):format(math.floor(SettingsLogic.sanitizeHudScale(value) * 100 + 0.5))
end

return SettingsLogic
