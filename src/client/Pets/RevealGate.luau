-- Compuerta de revelación: mientras se incuba un huevo, la interfaz retiene los cambios
-- que delatarían la mascota antes de la presentación (mascota que te sigue, inventario
-- y multiplicador del HUD). El servidor ya ha decidido el resultado; esto es solo
-- presentación. Al soltar la compuerta, cada sistema se actualiza con el estado real.

local RevealGate = {}

local held = false
local released = Instance.new("BindableEvent")

RevealGate.Released = released.Event

function RevealGate.hold()
	held = true
end

function RevealGate.release()
	if held then
		held = false
		released:Fire()
	end
end

function RevealGate.isHeld(): boolean
	return held
end

return RevealGate
