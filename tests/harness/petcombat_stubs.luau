-- Entorno simulado para ejecutar el PetCombatService REAL fuera de Roblox.
local V3 = {}
V3.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2)
	end
	return nil
end
V3.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
Vector3 = {
	new = function(x, y, z)
		return setmetatable({ X = x, Y = y, Z = z }, V3)
	end,
}
Vector2 = {
	new = function(x, y)
		return { X = x, Y = y, Magnitude = math.sqrt(x * x + y * y) }
	end,
}
Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end }

-- Reloj y tareas diferidas controlados por la prueba
local clock = 0
local delayed = {}
local realOs = os
os = { clock = function() return clock end, time = realOs.time }
task = {
	spawn = function(fn, ...)
		-- El único task.spawn sin argumentos del servicio es su bucle infinito: no se
		-- ejecuta; la prueba llama a PetCombatService.step directamente.
		if select("#", ...) == 0 then
			return
		end
		fn(...)
	end,
	delay = function(seconds, fn)
		table.insert(delayed, { At = clock + seconds, Fn = fn })
	end,
	wait = function() end,
}
local function advance(to)
	clock = to
	local index = 1
	while index <= #delayed do
		local item = delayed[index]
		if item.At <= clock then
			table.remove(delayed, index)
			item.Fn()
		else
			index += 1
		end
	end
end

local function signal()
	local listeners = {}
	return {
		Connect = function(_, fn)
			table.insert(listeners, fn)
			return { Disconnect = function() end }
		end,
		Fire = function(_, ...)
			for _, fn in listeners do
				fn(...)
			end
		end,
	}
end

-- Jugadores falsos
local playersList = {}
local function newPlayer(name, userId, position)
	local humanoid = { Health = 100 }
	local root = { Position = position, IsA = function(_, className) return className == "BasePart" end }
	local character = {
		FindFirstChild = function(_, childName) return if childName == "HumanoidRootPart" then root else nil end,
		FindFirstChildOfClass = function() return humanoid end,
	}
	local attributeSignals = {}
	local attributes = {}
	local player = {
		Name = name,
		UserId = userId,
		Character = character,
		Root = root,
		Humanoid = humanoid,
		CharacterRemoving = signal(),
		SetAttribute = function(_, key, value) attributes[key] = value end,
		GetAttribute = function(_, key) return attributes[key] end,
		GetAttributeChangedSignal = function(self, attribute)
			attributeSignals[attribute] = attributeSignals[attribute] or signal()
			return attributeSignals[attribute]
		end,
		AttributeSignals = attributeSignals,
	}
	table.insert(playersList, player)
	return player
end
local playerAdded, playerRemoving = signal(), signal()
local PlayersService = {
	GetPlayers = function() return playersList end,
	PlayerAdded = playerAdded,
	PlayerRemoving = playerRemoving,
}
local fired = {}
local WorkspaceService = { GetServerTimeNow = function() return clock end }
game = {
	GetService = function(_, name)
		if name == "Players" then return PlayersService end
		if name == "Workspace" then return WorkspaceService end
		-- ReplicatedStorage: los módulos reales ya van incrustados; solo hace falta WaitForChild
		return { WaitForChild = function() return {} end }
	end,
}
warn = function(...) print("WARN", ...) end

-- PlayerDataService simulado: perfil con nivel, multiplicador y mascotas EQUIPADAS
local profiles = {}
local PlayerDataService = {
	get = function(player) return profiles[player] end,
	getEquippedPetIds = function(profile) return profile.Equipped end,
}
local remotes = {}
local RemoteService = {
	get = function(name)
		remotes[name] = remotes[name] or {
			OnServerEvent = signal(),
			FireClient = function(_, player, event) table.insert(fired, { Remote = name, Player = player, Event = event }) end,
		}
		return remotes[name]
	end,
}
local hitListener, shotListener
local CombatService = {
	onPlayerHit = function(fn) hitListener = fn end,
	onShotRequest = function(fn) shotListener = fn end,
}
