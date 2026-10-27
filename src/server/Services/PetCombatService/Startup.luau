-- PetCombatService · Startup: arranque (start): remotes, peticiones del cliente y bucle.
-- Parte de PetCombatService (ver PetCombatService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local MonetizationLogic = require(Shared.MonetizationLogic)
local StyleConfig = require(Shared.Config.StyleConfig)
local MagicLogic = require(Shared.MagicLogic)
local WarriorLogic = require(Shared.WarriorLogic)
local PlayerDataService = require(script.Parent.Parent.PlayerDataService)
local RemoteService = require(script.Parent.Parent.RemoteService)
local EnemyService = require(script.Parent.Parent.EnemyService)
local CombatService = require(script.Parent.Parent.CombatService)

local ctx: any -- tabla de estado compartida (la crea PetCombatService/init.luau)
local PetCombatService: any -- la tabla pública del servicio
local Api = {} -- funciones públicas de esta parte (init.luau las copia a PetCombatService)
local HOLD_SECONDS: any
local STEP_SECONDS: any
local autoLimiter: any
local burstDamage: any
local burstScale: any
local burstUntil: any
local hitCombos: any
local states: any

-- Funciones de las otras partes
local function ammoUpkeep(...) return ctx.ammoUpkeep(...) end
local function attackStats(...) return ctx.attackStats(...) end
local function broadcast(...) return ctx.broadcast(...) end
local function heal(...) return ctx.heal(...) end
local function maxHealthOf(...) return ctx.maxHealthOf(...) end
local function oneWayLatency(...) return ctx.oneWayLatency(...) end
local function reset(...) return ctx.reset(...) end
local function rootOf(...) return ctx.rootOf(...) end
local function setTarget(...) return ctx.setTarget(...) end
local function startReload(...) return ctx.startReload(...) end
local function stateOf(...) return ctx.stateOf(...) end

function Api.start()
	ctx.abilityRemote = RemoteService.get(Constants.Remotes.PetAbility)

	-- Golpe de una habilidad (CombatService.reportHit): pasa a ser el objetivo
	CombatService.onPlayerHit(function(player: Player, enemy: any)
		if EnemyService.isAlive(enemy) and EnemyService.canInteract(player, enemy) then
			setTarget(stateOf(player), enemy)
		end
	end)
	-- Hacia dónde apunta (punto ya validado por CombatService) y qué pide: "Shot" un golpe,
	-- "Hold" sigue mientras llegue, "Release" ha soltado (y suelta el orbe que cargaba), "Aim"
	-- solo apunta (para el automático), "Charge" empieza a cargar un orbe (Magia), "Reload"
	-- recarga (Armas), "AdsOn"/"AdsOff" apunta con el clic derecho (Armas) y
	-- "BlockOn"/"BlockOff" bloquea (Guerrero).
	CombatService.onShotRequest(function(player: Player, aim: Vector3, mode: string)
		local state = stateOf(player)
		local now = os.clock()
		local style = state.Style
		if mode == "Release" then
			state.HeldUntil = -math.huge
			if state.ChargeStart then
				state.PendingCharge = now - state.ChargeStart
				state.ChargeStart = nil
				state.AimPoint = aim
				state.AimAt = now
			end
			return
		elseif mode == "Reload" then
			local profile = PlayerDataService.get(player)
			if profile and style == "Weapons" then
				local stats = attackStats(player, profile, state, style, now)
				ammoUpkeep(player, state, stats, now)
				startReload(player, state, stats, now)
			end
			return
		elseif mode == "AdsOn" or mode == "AdsOff" then
			state.Ads = mode == "AdsOn" and style == "Weapons"
			return
		elseif mode == "BlockOn" then
			if style == "Warrior" then
				-- Cuenta desde que lo pulsó (sin el viaje del aviso): la parada es justa con lag
				WarriorLogic.startBlock(state.Block, now - oneWayLatency(player))
				state.HeldUntil = -math.huge
				player:SetAttribute(Constants.Attributes.Blocking, true)
			end
			return
		elseif mode == "BlockOff" then
			WarriorLogic.stopBlock(state.Block)
			player:SetAttribute(Constants.Attributes.Blocking, false)
			return
		end
		state.AimPoint = aim
		state.AimAt = now
		if mode == "Charge" then
			if style == "Magic" and not state.ChargeStart then
				local spec = StyleConfig.Styles.Magic.Charge
				state.ChargeStart = now - spec.MinHold
				state.HeldUntil = -math.huge
				local root = rootOf(player)
				if root then
					broadcast(player, root.Position, { Kind = "Charging", Element = MagicLogic.element(player:GetAttribute(Constants.Attributes.EquippedWeapon)) })
				end
			end
		elseif mode == "Hold" then
			state.HeldUntil = now + HOLD_SECONDS
		elseif mode ~= "Aim" then
			state.ShotRequestedAt = now
		end
	end)
	-- Clic en el cuerpo de un enemigo (ClickDetector): sus mascotas lo atacan
	EnemyService.onClicked(function(player: Player, enemy: any)
		if not EnemyService.canInteract(player, enemy) then
			return
		end
		setTarget(stateOf(player), enemy)
	end)
	-- Guerrero · Sed de batalla: cada bicho que derrota le cura
	if EnemyService.onDefeated then
		EnemyService.onDefeated(function(player: Player)
			local state = states[player]
			local passive = StyleConfig.Styles.Warrior.Passive
			if state and state.Style == "Warrior" and passive.KillHeal then
				local maxHealth = maxHealthOf(player)
				if maxHealth then
					heal(player, maxHealth * passive.KillHeal)
				end
			end
		end)
	end
	-- Insignia AUTO (o V): enciende o apaga el disparo automático, solo con el pase
	RemoteService.get(Constants.Remotes.SetAutoFire).OnServerEvent:Connect(function(player: Player, enabled: any)
		if typeof(enabled) ~= "boolean" or autoLimiter:check(player) ~= "ok" then
			return
		end
		local profile = PlayerDataService.get(player)
		if not (profile and MonetizationLogic.autoFire(profile.Passes)) then
			return
		end
		local state = stateOf(player)
		state.AutoFire = enabled
		player:SetAttribute(Constants.Attributes.AutoFire, enabled)
	end)

	local function watch(player: Player)
		stateOf(player)
		player.CharacterRemoving:Connect(function()
			reset(player)
		end)
		player:GetAttributeChangedSignal(Constants.Attributes.CurrentZone):Connect(function()
			reset(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		reset(player)
		states[player] = nil
		burstUntil[player] = nil
		burstScale[player] = nil
		burstDamage[player] = nil
		hitCombos[player] = nil
		autoLimiter:remove(player)
	end)

	task.spawn(function()
		while true do
			task.wait(STEP_SECONDS)
			local ok, err = pcall(PetCombatService.step, os.clock())
			if not ok then
				warn("[PetCombatService] " .. tostring(err))
			end
		end
	end)
end

local Part = { Api = Api }

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	PetCombatService = context.Service
	HOLD_SECONDS = context.HOLD_SECONDS
	STEP_SECONDS = context.STEP_SECONDS
	autoLimiter = context.autoLimiter
	burstDamage = context.burstDamage
	burstScale = context.burstScale
	burstUntil = context.burstUntil
	hitCombos = context.hitCombos
	states = context.states
end

return Part
