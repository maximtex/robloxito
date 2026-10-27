-- StyleService · Actions: usar una habilidad, recargas, cambiar de estilo, comprar y subir habilidades y clases, dash y teletransporte.
-- Parte de StyleService (ver StyleService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local StyleLogic = require(Shared.StyleLogic)
local SkillLogic = require(Shared.SkillLogic)
local ClassLogic = require(Shared.ClassLogic)
local MagicLogic = require(Shared.MagicLogic)
local PlayerDataService = require(script.Parent.Parent.PlayerDataService)
local PetCombatService = require(script.Parent.Parent.PetCombatService)
local Types = require(script.Parent.Types)
type Cast = Types.Cast

local ctx: any -- tabla de estado compartida (la crea StyleService/init.luau)
local Api = {} -- funciones públicas de esta parte (init.luau las copia a StyleService)
local Codes: any
local HANDLERS: any
local SLOT_ATTRIBUTES: any
local buffUntil: any
local dashReadyAt: any
local lastSwitch: any
local readyAt: any

-- Funciones de las otras partes
local function broadcast(...) return ctx.broadcast(...) end
local function classModsOf(...) return ctx.classModsOf(...) end
local function classesOf(...) return ctx.classesOf(...) end
local function dashReach(...) return ctx.dashReach(...) end
local function moveDirection(...) return ctx.moveDirection(...) end
local function result(...) return ctx.result(...) end
local function rootOf(...) return ctx.rootOf(...) end
local function serverNow(...) return ctx.serverNow(...) end
local function skillsOf(...) return ctx.skillsOf(...) end
local function styleDps(...) return ctx.styleDps(...) end
local function styleOf(...) return ctx.styleOf(...) end

local function useAbility(player: Player, slot: number, aim: Vector3?)
	local style, profile = styleOf(player)
	local root = rootOf(player)
	if not (style and profile and root) then
		return
	end
	local skills = skillsOf(profile)
	local ability, skillId = StyleLogic.ability(style, slot, skills)
	-- Las del Mundo 2 usan el efecto de una del Mundo 1 (Base), que a su vez puede usar el de
	-- otra (las del Guerrero: Giro de acero → Torbellino, Grito de guerra → Furia…)
	local baseId = if ability and ability.Base then ability.Base else skillId
	local baseDef = baseId and SkillLogic.definition(baseId)
	if baseId and not HANDLERS[baseId] and baseDef and baseDef.Base then
		baseId = baseDef.Base
	end
	local handler = baseId and HANDLERS[baseId]
	if not (ability and skillId and handler) then
		return
	end
	local level = math.max(1, SkillLogic.level(skills, skillId))
	local class = ClassLogic.mods(profile.PetData.Classes, style)
	local now = os.clock()
	local own = readyAt[player] or {}
	readyAt[player] = own
	if (own[skillId] or 0) > now then
		result(player, { Success = false, Code = "NotReady", Style = style, Slot = slot, ReadyAt = serverNow() + (own[skillId] - now) })
		return
	end
	-- Magia: las habilidades gastan maná
	local manaCost = MagicLogic.skillCost(ability)
	if manaCost > 0 and PetCombatService.mana(player) < manaCost then
		result(player, { Success = false, Code = "NoMana", Style = style, Slot = slot, Cost = manaCost })
		return
	end
	local cast: Cast = {
		Player = player,
		Style = style,
		SkillId = skillId,
		Damage = styleDps(profile, style) * (ability.DamageRatio or 0) * SkillLogic.power(level) * class.SkillDamage,
		-- La Ráfaga y la Furia (y las que las usan) no se potencian a sí mismas
		Buffed = (buffUntil[player] or 0) > now and baseId ~= "Burst" and baseId ~= "Rage",
		Color = ability.Color,
		Aim = aim,
		Element = ability.Element,
	}
	if not handler(cast, ability, root, level) then
		result(player, { Success = false, Code = "NoTarget", Style = style, Slot = slot })
		return
	end
	if manaCost > 0 then
		PetCombatService.spendMana(player, manaCost)
	end
	local cooldown = SkillLogic.cooldown(ability, level) * class.SkillCooldown
	own[skillId] = now + cooldown
	local ready = serverNow() + cooldown
	player:SetAttribute(SLOT_ATTRIBUTES[slot], ready)
	result(player, { Success = true, Code = "Success", Style = style, Slot = slot, ReadyAt = ready, Cooldown = cooldown })
end

-- Recargas de las dos habilidades puestas del estilo `style` en los atributos del jugador.
local function publishCooldowns(player: Player, style: string)
	local profile = PlayerDataService.get(player)
	local own = readyAt[player]
	local now = os.clock()
	for slot, attribute in SLOT_ATTRIBUTES do
		local skillId = profile and SkillLogic.equipped(skillsOf(profile), style, slot)
		local at = own and skillId and own[skillId]
		player:SetAttribute(attribute, serverNow() + (if at then math.max(0, at - now) else 0))
	end
end

local function setStyle(player: Player, styleId: any, pick: boolean?)
	local profile = PlayerDataService.get(player)
	if not (profile and type(styleId) == "string" and StyleLogic.definition(styleId)) then
		return
	end
	local skills = skillsOf(profile)
	if pick then
		if skills.Picked then
			return -- ya eligió: se cambia con "Set"
		end
		skills.Picked = true
		PlayerDataService.markDirty(player)
	end
	local now = os.clock()
	if profile.PetData.Style == styleId then
		if pick then
			PlayerDataService.replicate(player)
			result(player, { Success = true, Code = "Success", Action = "Pick", Style = styleId })
		end
		return
	end
	if not pick and not StyleLogic.canSwitch(lastSwitch[player], now) then
		result(player, { Success = false, Code = "TooFast", Style = profile.PetData.Style })
		return
	end
	lastSwitch[player] = now
	profile.PetData.Style = styleId
	PlayerDataService.markDirty(player)
	PlayerDataService.replicate(player) -- también la velocidad al caminar y la vida del estilo
	publishCooldowns(player, styleId)
	result(player, { Success = true, Code = "Success", Action = if pick then "Pick" else "Set", Style = styleId })
end

-- Comprar, subir y poner habilidades (con 💎) -------------------------------------------------

-- Devuelve el código y los 💎 cobrados.
function Api.skillAction(player: Player, action: string, skillId: any, slot: any): (string, number)
	local profile = PlayerDataService.get(player)
	if not profile or profile.DataState == "Loading" then
		return Codes.NotReady, 0
	end
	if type(skillId) ~= "string" or #skillId > 40 then
		return Codes.InvalidRequest, 0
	end
	local skills = skillsOf(profile)
	local code, cost = "InvalidRequest", 0
	if action == "BuySkill" then
		code, cost = SkillLogic.buy(skills, skillId, profile.Diamonds, profile.PetData.UnlockedZones)
	elseif action == "UpgradeSkill" then
		code, cost = SkillLogic.upgrade(skills, skillId, profile.Diamonds)
	elseif action == "EquipSkill" then
		code = SkillLogic.equip(skills, skillId, slot)
	end
	if code == "Success" then
		profile.Diamonds -= cost
		PlayerDataService.markDirty(player)
		PlayerDataService.replicate(player)
		local style = StyleLogic.sanitize(profile.PetData.Style)
		publishCooldowns(player, style)
		if action ~= "EquipSkill" then
			PlayerDataService.saveNow(player) -- lo comprado con 💎 no se pierde con una caída
		end
	end
	return Codes[code] or code, cost
end

-- Comprar, subir y elegir clases (con 💎) ---------------------------------------------------

local CLASS_ACTIONS = { BuyClass = true, UpgradeClass = true, SelectClass = true }

-- Devuelve el código y los 💎 cobrados.
function Api.classAction(player: Player, action: string, classId: any): (string, number)
	local profile = PlayerDataService.get(player)
	if not profile or profile.DataState == "Loading" then
		return Codes.NotReady, 0
	end
	if type(classId) ~= "string" or #classId > 40 then
		return Codes.InvalidRequest, 0
	end
	local classes = classesOf(profile)
	local code, cost = "InvalidRequest", 0
	if action == "BuyClass" then
		code, cost = ClassLogic.buy(classes, classId, profile.Diamonds)
	elseif action == "UpgradeClass" then
		code, cost = ClassLogic.upgrade(classes, classId, profile.Diamonds)
	elseif action == "SelectClass" then
		code = ClassLogic.select(classes, classId)
	end
	if code == "Success" then
		profile.Diamonds -= cost
		PlayerDataService.markDirty(player)
		PlayerDataService.replicate(player) -- también la vida y la velocidad de la clase
		if action ~= "SelectClass" then
			PlayerDataService.saveNow(player) -- lo comprado con 💎 no se pierde con una caída
		end
	end
	return Codes[code] or code, cost
end

-- Dash de Puños ---------------------------------------------------------------------------

local function dash(player: Player)
	local style = styleOf(player)
	local root = rootOf(player)
	local def = StyleLogic.definition(style)
	local spec = def and def.Dash
	if not (root and spec) then
		return
	end
	local now = os.clock()
	if (dashReadyAt[player] or 0) > now then
		return
	end
	local direction = moveDirection(player, root)
	local origin = root.Position
	local reach = dashReach(player, origin, direction, spec.Distance)
	local cooldown = spec.Cooldown * classModsOf(player).DashCooldown -- clase (Monje)
	dashReadyAt[player] = now + cooldown
	player:SetAttribute(Constants.Attributes.DashReadyAt, serverNow() + cooldown)
	local finish = origin + direction * reach
	if reach > 0 then
		local character = player.Character :: Model
		character:PivotTo(CFrame.lookAt(finish, finish + direction))
		root.AssemblyLinearVelocity = Vector3.new(direction.X * 20, 0, direction.Z * 20)
	end
	broadcast(player, origin, { Kind = "QuickDash", From = origin, To = finish })
end

-- Teletransporte de Magia (clic derecho corto, Shift o su botón) ---------------------------

local function blink(player: Player, aim: Vector3?)
	local style = styleOf(player)
	local root = rootOf(player)
	local def = StyleLogic.definition(style)
	local spec = def and def.Blink
	if not (root and spec) then
		return
	end
	local now = os.clock()
	if (dashReadyAt[player] or 0) > now then
		return
	end
	if not PetCombatService.spendMana(player, spec.Cost or 0) then
		result(player, { Success = false, Code = "NoMana", Action = "Blink", Cost = spec.Cost })
		return
	end
	local origin = root.Position
	local direction = moveDirection(player, root)
	if aim then
		local flat = Vector3.new(aim.X - origin.X, 0, aim.Z - origin.Z)
		if flat.Magnitude > 1 then
			direction = flat.Unit
		end
	end
	local reach = dashReach(player, origin, direction, spec.Distance)
	dashReadyAt[player] = now + spec.Cooldown
	player:SetAttribute(Constants.Attributes.DashReadyAt, serverNow() + spec.Cooldown)
	local finish = origin + direction * reach
	if reach > 0 then
		local character = player.Character :: Model
		character:PivotTo(CFrame.lookAt(finish, finish + direction))
		root.AssemblyLinearVelocity = Vector3.zero
	end
	broadcast(player, origin, { Kind = "Blink", From = origin, To = finish })
end

local Part = { Api = Api }

function Part.install(context: any)
	ctx = context
	context.CLASS_ACTIONS = CLASS_ACTIONS
	context.blink = blink
	context.dash = dash
	context.setStyle = setStyle
	context.useAbility = useAbility
end

function Part.link(context: any)
	Codes = context.Codes
	HANDLERS = context.HANDLERS
	SLOT_ATTRIBUTES = context.SLOT_ATTRIBUTES
	buffUntil = context.buffUntil
	dashReadyAt = context.dashReadyAt
	lastSwitch = context.lastSwitch
	readyAt = context.readyAt
end

return Part
