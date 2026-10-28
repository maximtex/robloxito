-- StyleService · Startup: arranque (start): remotes, pasivas de las clases y limpieza al salir.
-- Parte de StyleService (ver StyleService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local StyleLogic = require(Shared.StyleLogic)
local RemoteService = require(script.Parent.Parent.RemoteService)
local EnemyService = require(script.Parent.Parent.EnemyService)
local PetCombatService = require(script.Parent.Parent.PetCombatService)

local ctx: any -- tabla de estado compartida (la crea StyleService/init.luau)
local StyleService: any -- la tabla pública del servicio
local Api = {} -- funciones públicas de esta parte (init.luau las copia a StyleService)
local CLASS_ACTIONS: any
local Codes: any
local buffUntil: any
local dashReadyAt: any
local generation: any
local lastSwitch: any
local limiter: any
local rageTaken: any
local rageUntil: any
local readyAt: any
local shopLimiter: any

-- Funciones de las otras partes
local function blink(...) return ctx.blink(...) end
local function classModsOf(...) return ctx.classModsOf(...) end
local function dash(...) return ctx.dash(...) end
local function result(...) return ctx.result(...) end
local function setStyle(...) return ctx.setStyle(...) end
local function styleOf(...) return ctx.styleOf(...) end
local function useAbility(...) return ctx.useAbility(...) end
local function validAim(...) return ctx.validAim(...) end

function Api.start()
	ctx.eventRemote = RemoteService.get(Constants.Remotes.StyleEvent)

	RemoteService.get(Constants.Remotes.StyleAction).OnServerEvent:Connect(function(player: Player, action: any, value: any, extra: any)
		if type(action) ~= "string" then
			return
		end
		if action == "BuySkill" or action == "UpgradeSkill" or action == "EquipSkill" then
			local rate = shopLimiter:check(player)
			if rate == "flood" then
				return
			elseif rate == "cooldown" then
				result(player, { Success = false, Code = Codes.TooFast, Action = action, Skill = value })
				return
			end
			local code, cost = StyleService.skillAction(player, action, value, extra)
			result(player, { Success = code == Codes.Success, Code = code, Action = action, Skill = value, Slot = extra, Cost = cost })
			return
		end
		if CLASS_ACTIONS[action] then
			local rate = shopLimiter:check(player)
			if rate == "flood" then
				return
			elseif rate == "cooldown" then
				result(player, { Success = false, Code = Codes.TooFast, Action = action, Class = value })
				return
			end
			local code, cost = StyleService.classAction(player, action, value)
			result(player, { Success = code == Codes.Success, Code = code, Action = action, Class = value, Cost = cost })
			return
		end
		if limiter:check(player) ~= "ok" then
			return
		end
		if action == "Set" then
			setStyle(player, value)
		elseif action == "Pick" then
			setStyle(player, value, true)
		elseif action == "Ability" then
			useAbility(player, if value == 2 then 2 else 1, validAim(player, extra))
		elseif action == "Dash" then
			dash(player)
		elseif action == "Blink" then
			blink(player, validAim(player, value))
		end
	end)

	-- Daño que recibe el jugador según su estilo (Puños menos, Armas más; con Furia, menos) y
	-- su clase (Tanque, Criomante)
	EnemyService.setIncomingDamageModifier(function(player: Player, amount: number, enemy: any?): number
		local style = styleOf(player)
		local taken = if style then StyleLogic.damageTaken(style, amount) else amount
		if (rageUntil[player] or 0) > os.clock() and (style == "Fists" or style == "Warrior") then
			taken *= math.clamp(rageTaken[player] or 0.5, 0, 1)
		end
		-- Guerrero: bloqueo (y parada perfecta: nada de daño)
		if style == "Warrior" then
			taken *= PetCombatService.blockIncoming(player, enemy)
		end
		return taken * classModsOf(player).DamageTaken
	end)
	-- Daño a los jefes según el estilo (Puños más, Guerrero menos: StyleConfig BossDamage) y
	-- la clase (Comando Élite)
	EnemyService.setOutgoingDamageModifier(function(player: Player, enemy: any, amount: number): number
		if enemy and enemy.Kind == "Boss" then
			return amount * StyleLogic.bossDamage(styleOf(player)) * classModsOf(player).BossDamage
		end
		return amount
	end)

	local function watch(player: Player)
		player.CharacterRemoving:Connect(function()
			generation[player] = (generation[player] or 0) + 1
			PetCombatService.setBurst(player, 0)
			buffUntil[player] = nil
			rageUntil[player] = nil
			player:SetAttribute(Constants.Attributes.StyleBurstUntil, nil)
			player:SetAttribute(Constants.Attributes.StyleRageUntil, nil)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSwitch[player] = nil
		readyAt[player] = nil
		generation[player] = nil
		buffUntil[player] = nil
		rageUntil[player] = nil
		rageTaken[player] = nil
		dashReadyAt[player] = nil
		limiter:remove(player)
		shopLimiter:remove(player)
	end)
end

local Part = { Api = Api }

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	StyleService = context.Service
	CLASS_ACTIONS = context.CLASS_ACTIONS
	Codes = context.Codes
	buffUntil = context.buffUntil
	dashReadyAt = context.dashReadyAt
	generation = context.generation
	lastSwitch = context.lastSwitch
	limiter = context.limiter
	rageTaken = context.rageTaken
	rageUntil = context.rageUntil
	readyAt = context.readyAt
	shopLimiter = context.shopLimiter
end

return Part
