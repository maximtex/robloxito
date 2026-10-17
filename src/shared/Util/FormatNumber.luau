-- Formatea números grandes: 1234 -> "1.23K", 5600000 -> "5.6M".
-- Con `decimals`, los valores menores de 1000 conservan hasta esos decimales
-- (1.1 -> "1.1"); sin él se redondean hacia abajo como antes.

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

local function trimZeros(text: string): string
	return (text:gsub("%.?0+$", ""))
end

local function formatNumber(value: number, decimals: number?): string
	if math.abs(value) < 1000 then
		if decimals and decimals > 0 then
			return trimZeros(string.format("%." .. decimals .. "f", value))
		end
		return tostring(math.floor(value))
	end

	value = math.floor(value)
	local index = 1
	local scaled = value
	while math.abs(scaled) >= 1000 and index < #SUFFIXES do
		scaled /= 1000
		index += 1
	end

	return trimZeros(string.format("%.2f", scaled)) .. SUFFIXES[index]
end

return formatNumber
