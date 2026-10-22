-- Entorno simulado para ejecutar el AbilityService REAL fuera de Roblox (con EnemyLogic,
-- CoreLogic, CombatMath y AbilityLogic reales; EnemyService y los servicios de datos
-- simulados con lo mínimo).
local V3 = {}
V3.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2)
	elseif key == "Unit" then
		local m = math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2)
		return Vector3.new(self.X / m, self.Y / m, self.Z / m)
	end
	return nil
end
V3.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return Vector3.new(b.X * a, b.Y * a, b.Z * a)
	end
	return Vector3.new(a.X * b, a.Y * b, a.Z * b)
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
local clock = 100
local delayed = {}
local realOs = os
os = { clock = function() return clock end, time = function() return 1700000000 end }
task = {
	spawn = function(fn, ...)
		-- El único task.spawn sin argumentos del servicio es su bucle infinito: no se ejecuta;
		-- la prueba llama a AbilityService.step directamente.
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

-- Jugadores falsos (mirando hacia -Z, como en Roblox por defecto)
local playersList = {}
local PlayersService
local function newPlayer(name, userId, position)
	local character = {}
	local humanoid = { Health = 100, MaxHealth = 100, WalkSpeed = 16, Parent = character }
	function humanoid.GetAttribute(_, _name) return nil end
	local root = {
		Position = position,
		CFrame = { LookVector = Vector3.new(0, 0, -1) },
		IsA = function(_, className) return className == "BasePart" end,
	}
	character.FindFirstChild = function(_, childName) return if childName == "HumanoidRootPart" then root else nil end
	character.FindFirstChildOfClass = function() return humanoid end
	local attributeSignals = {}
	local player = {
		Name = name,
		UserId = userId,
		Character = character,
		Root = root,
		Humanoid = humanoid,
		CharacterRemoving = signal(),
		GetAttributeChangedSignal = function(self, attribute)
			attributeSignals[attribute] = attributeSignals[attribute] or signal()
			return attributeSignals[attribute]
		end,
		AttributeSignals = attributeSignals,
	}
	table.insert(playersList, player)
	player.Parent = PlayersService
	return player
end
local playerAdded, playerRemoving = signal(), signal()
PlayersService = {
	GetPlayers = function() return playersList end,
	PlayerAdded = playerAdded,
	PlayerRemoving = playerRemoving,
}
local WorkspaceService = { GetServerTimeNow = function() return clock + 5000 end } -- reloj del servidor desplazado
local ReplicatedStorageService = { WaitForChild = function() return {} end }
local StarterPlayerService = { CharacterWalkSpeed = 16 }
game = {
	GetService = function(_, name)
		if name == "Players" then return PlayersService end
		if name == "Workspace" then return WorkspaceService end
		if name == "ReplicatedStorage" then return ReplicatedStorageService end
		if name == "StarterPlayer" then return StarterPlayerService end
		return {}
	end,
}
script = { Parent = { Parent = {} } }
warn = function(...) print("WARN", ...) end

-- PlayerDataService simulado: perfil con nivel, multiplicador y núcleos
local profiles = {}
local PlayerDataService = {
	get = function(player) return profiles[player] end,
	isPetDataReady = function(profile) return profile.Ready ~= false end,
}
local fired = {}
local remotes = {}
local RemoteService = {
	get = function(name)
		if not remotes[name] then
			remotes[name] = {
				OnServerEvent = signal(),
				FireClient = function(_, player, ...)
					table.insert(fired, { Remote = name, Player = player, Args = { ... }, Event = (select(1, ...)) })
				end,
			}
		end
		return remotes[name]
	end,
}
local engaged = {}
local CombatService = {
	reportHit = function(player, enemy) table.insert(engaged, { Player = player, Enemy = enemy }) end,
}

