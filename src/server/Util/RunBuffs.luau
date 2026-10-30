-- Mejoras de la partida de oleadas que tocan el daño que recibe el jugador y su daño a los
-- jefes (cartas Piel dura, Cañón de cristal, Cazajefes y Puño demoledor). WaveService le dice
-- de dónde sacar las mejoras de cada jugador (setProvider) y StyleService las aplica a sus
-- multiplicadores de siempre. Así ninguno de los dos depende del otro.

local RunBuffs = {}

local provider: ((Player) -> any)? = nil

local function finite(value: any, default: number, low: number, high: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return default
	end
	return math.clamp(value, low, high)
end

-- WaveService: mejoras (WaveLogic.Mods) del jugador en su partida, o nil si no juega.
function RunBuffs.setProvider(fn: (Player) -> any)
	provider = fn
end

local function modsOf(player: Player): any
	if not provider then
		return nil
	end
	local ok, mods = pcall(provider, player)
	return if ok and type(mods) == "table" then mods else nil
end

-- Multiplicador del daño que recibe (1 fuera de una partida).
function RunBuffs.incoming(player: Player): number
	local mods = modsOf(player)
	return if mods then finite(mods.Armor, 1, 0.2, 3) else 1
end

-- Multiplicador de su daño a los jefes (1 fuera de una partida).
function RunBuffs.bossDamage(player: Player): number
	local mods = modsOf(player)
	return if mods then finite(mods.BossDamage, 1, 1, 5) else 1
end

return RunBuffs
