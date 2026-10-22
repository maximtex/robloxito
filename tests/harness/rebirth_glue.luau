-- Entorno para el RebirthService REAL sobre la persistencia real (persist_stubs +
-- persist_glue): PetService simulado, remotes con FireAllClients, instancias mínimas
-- (leaderstats) y jugadores con señales de atributos. Devuelve el PetService simulado.

local PetServiceStub = { Pushed = 0 }
function PetServiceStub.pushInventory()
	PetServiceStub.Pushed += 1
end

-- Avisos a todos los clientes (RebirthEvent).
local broadcasts = {}
PetServiceStub.Broadcasts = broadcasts
local baseGet = RemoteService.get
RemoteService.get = function(name)
	local remote = baseGet(name)
	if not remote.FireAllClients then
		remote.FireAllClients = function(_, ...)
			table.insert(broadcasts, { Name = name, Args = { ... } })
		end
	end
	return remote
end

-- Instancias mínimas: nombre, padre e hijos (para leaderstats).
local function attach(object, parent)
	if parent and parent.Children then
		table.insert(parent.Children, object)
	end
end
local function findChild(self, name)
	for _, child in self.Children do
		if child.Name == name then
			return child
		end
	end
	return nil
end
Instance = {
	new = function(className)
		local object = { ClassName = className, Children = {}, FindFirstChild = findChild }
		return setmetatable(object, {
			__newindex = function(t, key, value)
				if key == "Parent" then
					rawset(t, "_parent", value)
					attach(t, value)
				else
					rawset(t, key, value)
				end
			end,
			__index = function(t, key)
				if key == "Parent" then
					return rawget(t, "_parent")
				end
				return nil
			end,
		})
	end,
}

-- Jugador con hijos, personaje y señales de cambio de atributo.
function PetServiceStub.newPlayer(name, userId)
	local player = newPlayer(name, userId)
	player.Children = {}
	player.FindFirstChild = findChild
	player.CharacterAdded = signal()
	player.DisplayName = name
	local signals = {}
	local baseSet = player.SetAttribute
	function player.GetAttributeChangedSignal(_, attribute)
		signals[attribute] = signals[attribute] or signal()
		return signals[attribute]
	end
	function player.SetAttribute(self, key, value)
		local old = self:GetAttribute(key)
		baseSet(self, key, value)
		if old ~= value and signals[key] then
			signals[key]:Fire()
		end
	end
	return player
end

return PetServiceStub
