-- WaveService · Results: oleada superada, récords, cofre, victoria, resumen, fin y modo infinito.
-- Parte de WaveService (ver WaveService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WaveConfig = require(Shared.Config.WaveConfig)
local WaveLogic = require(Shared.WaveLogic)
local ItemLogic = require(Shared.ItemLogic)
local PlayerDataService = require(script.Parent.Parent.PlayerDataService)
local GameEvents = require(script.Parent.Parent.Parent.Util.GameEvents)
local ItemService = require(script.Parent.Parent.ItemService)
local Types = require(script.Parent.Types)
type Participant = Types.Participant
type Run = Types.Run

local ctx: any -- tabla de estado compartida (la crea WaveService/init.luau)
local RESTART_LOCK: any
local best: any
local lockedUntil: any
local runOf: any
local runs: any
local enterChoice: any -- (declarada aquí; antes, más arriba en el original)
local finish: any -- (declarada aquí; antes, más arriba en el original)
local recordCleared: any -- (declarada aquí; antes, más arriba en el original)

-- Funciones de las otras partes
local function broadcast(...) return ctx.broadcast(...) end
local function despawnAll(...) return ctx.despawnAll(...) end
local function enterBreak(...) return ctx.enterBreak(...) end
local function enterCards(...) return ctx.enterCards(...) end
local function hint(...) return ctx.hint(...) end
local function newParticipant(...) return ctx.newParticipant(...) end
local function pay(...) return ctx.pay(...) end
local function rootOf(...) return ctx.rootOf(...) end
local function serverTime(...) return ctx.serverTime(...) end
local function setPlayerRun(...) return ctx.setPlayerRun(...) end
local function updateSign(...) return ctx.updateSign(...) end

-- Oleada `wave` superada: récord del servidor y de cada jugador (WaveLogic.recordWave), que
-- se guarda. Aviso "Record" la primera vez que alguien supera su récord anterior.
function recordCleared(run: Run, wave: number)
	if run.Arena.Tutorial then
		return
	end
	local key = WaveLogic.recordKey(run.ArenaId, run.Difficulty)
	best[key] = math.max(best[key] or 0, wave)
	for player, participant in run.Participants do
		local profile = PlayerDataService.get(player)
		if not profile then
			continue
		end
		local records = profile.PetData.Waves
		if type(records) ~= "table" then
			records = WaveLogic.emptyRecords()
			profile.PetData.Waves = records
		end
		GameEvents.fire("WaveCleared", player, run.ArenaId, wave, run.Difficulty, run.Endless) -- requisito de renacer (RebirthService) y retos semanales
		if WaveLogic.recordWave(records, run.ArenaId, wave, run.Difficulty) then
			participant.NewBest = true
			if participant.StartBest > 0 and not participant.RecordShown and player.Parent then
				participant.RecordShown = true
				ctx.eventRemote:FireClient(player, "Record", { Wave = wave, Previous = participant.StartBest })
			end
		end
		PlayerDataService.markDirty(player)
		PlayerDataService.replicate(player)
	end
end

local function waveCleared(run: Run)
	local wave = run.Wave
	recordCleared(run, wave)
	for _, participant in run.Participants do
		local profile = PlayerDataService.get(participant.Player)
		if profile then
			-- Premio de la oleada (con la dificultad y el modificador de la partida)
			local diamonds, money = WaveLogic.clearReward(wave, run.ArenaId)
			local given, coins = pay(participant, diamonds * run.Effects.Reward, money * run.Effects.Reward)
			-- Respiro: recupera parte de la vida (solo quien sigue en pie; "Sin respiro", nada)
			local healed = false
			local heal = if run.Effects.ClearHeal ~= nil then run.Effects.ClearHeal else WaveConfig.ClearHeal
			local _, humanoid = rootOf(participant.Player)
			if humanoid and humanoid.Health > 0 and heal and heal > 0 then
				local before = humanoid.Health
				humanoid.Health = math.min(humanoid.MaxHealth, before + humanoid.MaxHealth * heal)
				healed = humanoid.Health > before
			end
			ctx.eventRemote:FireClient(participant.Player, "Cleared", { Wave = wave, Diamonds = given, Money = coins, Healed = healed })
		end
	end
	if not run.Endless and wave >= run.Waves then
		finish(run, true) -- modo sin jefe: ganada al limpiar la última
	elseif WaveLogic.isCardWave(run.ArenaId, wave, run.Effects.CardEvery) then
		enterCards(run)
	else
		enterBreak(run, WaveConfig.BreakSeconds)
	end
end

-- Cofre de las mazmorras para un jugador: 💰 y, a veces, una poción para el inventario. Se
-- cobra ya; el cliente lo dibuja delante del altar y lo abre ("Chest").
local function giveChest(run: Run, participant: Participant)
	local player = participant.Player
	local profile = PlayerDataService.get(player)
	local items = profile and ItemLogic.ofProfile(profile)
	local money, potion = WaveLogic.chestReward(run.ArenaId, math.random(), math.random(), ItemLogic.boostOrder())
	money = math.floor(money * run.Effects.Reward)
	if money <= 0 and not potion then
		return
	end
	local _, coins = pay(participant, 0, money)
	if potion and not (items and ItemLogic.addPotion(items, potion, 1) > 0) then
		potion = nil
	end
	if potion then
		PlayerDataService.markDirty(player)
		pcall(ItemService.push, player)
	end
	if player.Parent then
		ctx.eventRemote:FireClient(player, "Chest", {
			Position = run.Center + Vector3.new(0, 0, WaveConfig.Place.AreaRadius * 0.45),
			Facing = Vector3.new(0, 0, -1),
			Money = coins,
			Potion = potion,
			Arena = run.Arena.DisplayName,
		})
	end
end

-- Premio de victoria para todos los de la partida (una sola vez).
local function payVictory(run: Run)
	if run.VictoryPaid then
		return
	end
	run.VictoryPaid = true
	hint(run, "Victory")
	for player, participant in run.Participants do
		local profile = PlayerDataService.get(player)
		if profile then
			local diamonds, money = WaveLogic.victoryReward(run.ArenaId)
			local scale = run.Effects.Reward * run.Effects.VictoryBonus
			participant.VictoryDiamonds, participant.VictoryMoney = pay(participant, diamonds * scale, money * scale)
			local ok, err = pcall(giveChest, run, participant)
			if not ok then
				warn("[WaveService] Cofre: " .. tostring(err))
			end
		end
		GameEvents.fire("WaveWon", player, run.ArenaId, run.Difficulty, run.Mutator)
	end
end

-- Resumen para un jugador y vuelta al mundo normal.
local function sendResult(run: Run, player: Player, participant: Participant, victory: boolean)
	if player.Parent then
		local profile = PlayerDataService.get(player)
		ctx.eventRemote:FireClient(player, "Result", {
			Run = run.Id,
			Victory = victory,
			Tutorial = run.Arena.Tutorial == true,
			Endless = run.Endless == true,
			Arena = run.Arena.DisplayName,
			Tags = WaveLogic.runTags(run.Difficulty, run.Mutator),
			Wave = run.Wave,
			Waves = run.Waves,
			Kills = participant.Kills,
			Diamonds = participant.Diamonds,
			Money = participant.Money,
			Golden = participant.Golden,
			BestStreak = participant.BestStreak,
			VictoryDiamonds = participant.VictoryDiamonds,
			VictoryMoney = participant.VictoryMoney,
			Best = best[WaveLogic.recordKey(run.ArenaId, run.Difficulty)] or 0,
			PersonalBest = if profile then WaveLogic.bestWave(profile.PetData.Waves, WaveLogic.recordKey(run.ArenaId, run.Difficulty)) else 0,
			NewBest = participant.NewBest and participant.StartBest > 0,
		})
	end
	if runOf[player] == run then
		runOf[player] = nil
		setPlayerRun(player, nil)
	end
	lockedUntil[player] = os.clock() + RESTART_LOCK
end

-- Fin de la partida: premios, resumen y cada uno vuelve al mundo normal. En el modo infinito
-- la victoria ya se cobró al caer el jefe: el resumen la cuenta, pero no se paga otra vez.
function finish(run: Run, victory: boolean)
	if run.Phase == "Done" then
		return
	end
	-- Lo que quede se retira sin botín (los jefes derrotados ya se fueron solos).
	despawnAll(run)
	run.Phase = "Done"
	run.EndsAt = 0
	if victory then
		payVictory(run)
	end
	for player, participant in run.Participants do
		sendResult(run, player, participant, victory or run.VictoryPaid)
	end
	runs[run.Id] = nil
	updateSign()
end

-- Jefe derrotado en un modo con modo infinito: se cobra la victoria y cada jugador tiene
-- Endless.ChoiceSeconds para elegir si sigue ("Endless", true/false).
function enterChoice(run: Run)
	despawnAll(run) -- la escolta se retira (los jefes ya cayeron)
	payVictory(run)
	run.Phase = "Choice"
	run.EndsAt = os.clock() + WaveConfig.Endless.ChoiceSeconds
	for player, participant in run.Participants do
		participant.Continue = nil
		participant.Choices = nil
		if player.Parent then
			ctx.eventRemote:FireClient(player, "Choice", {
				EndsAt = serverTime(run.EndsAt),
				Wave = run.Wave,
				VictoryDiamonds = participant.VictoryDiamonds,
				VictoryMoney = participant.VictoryMoney,
			})
		end
	end
	broadcast(run)
	updateSign()
end

-- Fin de la elección: quien no sigue se lleva su resumen; con alguien que sigue, empieza el
-- modo infinito (tras una pausa corta).
local function resolveChoice(run: Run)
	for player, participant in run.Participants do
		if participant.Continue ~= true then
			run.Participants[player] = nil
			sendResult(run, player, participant, true)
		end
	end
	if next(run.Participants) == nil then
		run.Phase = "Done"
		runs[run.Id] = nil
		updateSign()
		return
	end
	run.Endless = true
	enterBreak(run, 2)
end

local function addParticipant(run: Run, player: Player)
	local participant = newParticipant(player)
	local profile = PlayerDataService.get(player)
	participant.StartBest = if profile then WaveLogic.bestWave(profile.PetData.Waves, WaveLogic.recordKey(run.ArenaId, run.Difficulty)) else 0
	run.Participants[player] = participant
	runOf[player] = run
	setPlayerRun(player, run)
	broadcast(run)
	updateSign()
	-- Qué tiene de especial esta partida (modificador y dificultad), en el cartel de abajo
	local lines = {}
	local mutator = run.Mutator and WaveConfig.Mutators[run.Mutator]
	if mutator then
		table.insert(lines, ("%s %s: %s"):format(mutator.Icon, mutator.Name, mutator.Text))
	end
	local difficulty = run.Difficulty ~= "Normal" and WaveConfig.Difficulties[run.Difficulty]
	if difficulty then
		table.insert(lines, ("%s %s: %s"):format(difficulty.Icon, difficulty.Name, difficulty.Text))
	end
	if #lines > 0 and player.Parent then
		ctx.eventRemote:FireClient(player, "Hint", { Text = table.concat(lines, "\n"), Seconds = 7 })
	end
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.addParticipant = addParticipant
	context.enterChoice = enterChoice
	context.finish = finish
	context.recordCleared = recordCleared
	context.resolveChoice = resolveChoice
	context.waveCleared = waveCleared
end

function Part.link(context: any)
	RESTART_LOCK = context.RESTART_LOCK
	best = context.best
	lockedUntil = context.lockedUntil
	runOf = context.runOf
	runs = context.runs
end

return Part
