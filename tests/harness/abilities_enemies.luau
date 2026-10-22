-- (Va DESPUÉS de los módulos reales: usa EnemyLogic.)
-- EnemyService simulado con el EnemyLogic REAL (vida, muerte única, reparto y estados).
local enemyList = {}
local kills = {}
local payouts = {}
local marks = {}
local EnemyService = {}
local function newEnemy(id, x, z, health, kind)
	local enemy = {
		Id = id,
		Kind = kind or "Normal",
		Radius = 1.2,
		RootHeight = 1.6,
		Reward = 100,
		Generation = 0,
		Root = { Position = Vector3.new(x, 3, z) },
		Model = { Parent = true },
		Status = { State = "Idle", Health = health, MaxHealth = health, Contributions = {} },
		Control = EnemyLogic.newControl(),
	}
	table.insert(enemyList, enemy)
	return enemy
end
function EnemyService.isAlive(enemy)
	return enemy ~= nil and enemy.Model.Parent ~= nil and enemy.Status.State ~= "Dead"
end
function EnemyService.damage(enemy, player, amount)
	if enemy.Model.Parent == nil then
		return 0, false
	end
	amount = EnemyLogic.damageTaken(amount, enemy.Control, os.clock())
	local dealt, killed = EnemyLogic.applyDamage(enemy.Status, player.UserId, amount)
	if killed then
		enemy.Generation += 1
		kills[enemy.Id] = (kills[enemy.Id] or 0) + 1
		for userId, value in EnemyLogic.splitReward(enemy.Status.Contributions, enemy.Reward) do
			payouts[userId] = (payouts[userId] or 0) + value
		end
	end
	return dealt, killed
end
local function candidatesOf()
	local candidates, byId = {}, {}
	for _, enemy in enemyList do
		if EnemyService.isAlive(enemy) then
			byId[enemy.Id] = enemy
			table.insert(candidates, { Id = enemy.Id, X = enemy.Root.Position.X, Z = enemy.Root.Position.Z, Radius = enemy.Radius, Alive = true })
		end
	end
	return candidates, byId
end
function EnemyService.findInRadius(center, radius, maxTargets)
	local candidates, byId = candidatesOf()
	local result = {}
	for _, id in EnemyLogic.selectInRadius(center.X, center.Z, candidates, radius, maxTargets) do
		table.insert(result, byId[id])
	end
	return result
end
function EnemyService.findTargets(origin, look, range, arcDot, maxTargets)
	local candidates, byId = candidatesOf()
	local result = {}
	for _, id in EnemyLogic.selectTargets(origin.X, origin.Z, look.X, look.Z, candidates, range, arcDot, maxTargets) do
		table.insert(result, byId[id])
	end
	return result
end
function EnemyService.applyControl(enemy, kind, seconds, factor)
	if not EnemyService.isAlive(enemy) or enemy.Status.State == "Return" then
		return false
	end
	return EnemyLogic.applyControl(enemy.Control, kind, os.clock(), seconds, factor, 10)
end
function EnemyService.markStatus(enemy, name, seconds)
	marks[enemy.Id] = { Name = name, Seconds = seconds }
end
local knocks = {}
function EnemyService.auraOf(enemy)
	return EnemyLogic.auraOf(enemy.Control, os.clock())
end
function EnemyService.setAura(enemy, element, seconds)
	if not EnemyService.isAlive(enemy) or enemy.Status.State == "Return" then
		return
	end
	EnemyLogic.setAura(enemy.Control, element, os.clock(), seconds, 10)
end
function EnemyService.knockback(enemy, from, force)
	if enemy.Kind == "Boss" or not EnemyService.isAlive(enemy) then
		return
	end
	knocks[enemy.Id] = force
end
