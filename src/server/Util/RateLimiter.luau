-- Limitador de frecuencia por jugador para RemoteEvents.
-- check() devuelve:
--   "ok"       -> procesar
--   "cooldown" -> demasiado pronto desde la última aceptada (responder al cliente)
--   "flood"    -> demasiadas solicitudes en la ventana (ignorar en silencio)

local RateLimiter = {}
RateLimiter.__index = RateLimiter

type State = {
	LastAccepted: number,
	WindowStart: number,
	Count: number,
}

export type RateLimiter = typeof(setmetatable(
	{} :: { Cooldown: number, WindowSeconds: number, MaxPerWindow: number, States: { [Player]: State } },
	RateLimiter
))

function RateLimiter.new(cooldown: number, windowSeconds: number, maxPerWindow: number): RateLimiter
	return setmetatable({
		Cooldown = cooldown,
		WindowSeconds = windowSeconds,
		MaxPerWindow = maxPerWindow,
		States = {},
	}, RateLimiter)
end

function RateLimiter.check(self: RateLimiter, player: Player): string
	local now = os.clock()
	local state = self.States[player]
	if not state then
		state = { LastAccepted = -math.huge, WindowStart = now, Count = 0 }
		self.States[player] = state
	end

	if now - state.WindowStart > self.WindowSeconds then
		state.WindowStart = now
		state.Count = 0
	end

	state.Count += 1
	if state.Count > self.MaxPerWindow then
		return "flood"
	end
	if now - state.LastAccepted < self.Cooldown then
		return "cooldown"
	end

	state.LastAccepted = now
	return "ok"
end

function RateLimiter.remove(self: RateLimiter, player: Player)
	self.States[player] = nil
end

return RateLimiter
