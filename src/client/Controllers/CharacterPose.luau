-- Movimientos del personaje al pelear, hechos a mano en cada cliente (solo se ven, no
-- cambian nada del juego): se giran un momento las articulaciones de los hombros y la
-- cintura y vuelven a su sitio. Sirve para R15 y R6, con las articulaciones de siempre
-- (Motor6D) y con las nuevas de Roblox (AnimationConstraint, la mejora de articulaciones
-- del avatar). En las dos se escribe su Transform en cada fotograma, justo después de las
-- animaciones (RunService.PreSimulation): el giro se mezcla con la animación (Weight) y,
-- mientras lleva el arma, la espada o el bastón, la sustituye en ese brazo. No se toca el C0
-- (en las articulaciones nuevas no se puede, y la animación lo compensaría).
-- - punch: un puñetazo (alterna derecha e izquierda) con un giro de cintura.
-- - aim: apunta con el brazo derecho (se mantiene mientras sigas disparando).
-- - cast: los dos brazos hacia delante y arriba (lanzar un hechizo).
-- - throw: brazo atrás y lanzamiento por encima del hombro (granada).
-- - slam: los dos brazos arriba y golpe abajo (terremoto).
-- - spread: los dos brazos abiertos a los lados (nova).
-- - charge: los dos brazos hacia delante, como al embestir.
-- - slash: los tres tajos del Guerrero (de derecha a izquierda, de vuelta y el giro).
-- - recoil: el arma salta un poco al disparar.
-- - setRest: postura de reposo de cada estilo (el arma medio levantada, la espada en guardia,
--   el bastón; con el clic derecho, el arma al frente o la espada cruzada para bloquear): los
--   golpes vuelven a ella en vez de a los brazos de la animación.
-- - gearPoint: un punto de lo que lleva en la mano (la boca del arma, la punta de la espada,
--   la esfera del bastón: GearModels) para sacar de ahí los efectos.
-- Los usa CombatController (cada golpe del estilo), GearPose (los reposos de todos) y
-- StyleController (las habilidades), con el personaje de quien ataca (también el de otros
-- jugadores cercanos).

local RunService = game:GetService("RunService")

local CharacterPose = {}

-- Target: la articulación (Motor6D o AnimationConstraint, las dos tienen Transform)
type Joint = { Target: Instance, Rig: string, Side: number }

-- Un tramo del movimiento de una articulación: hacia `To` (y la mezcla `Weight`) en
-- `Duration` segundos; `ToRest`: hacia el reposo que tenga al empezar el tramo.
type Step = { To: CFrame?, Weight: number?, ToRest: boolean?, Duration: number, Ease: string }
type State = {
	Offset: CFrame, -- giro que se aplica ahora
	Weight: number, -- 0 = solo la animación, 1 = solo el giro
	Rest: CFrame?, -- postura de reposo (nil = la animación)
	Steps: { Step },
	From: CFrame,
	FromWeight: number,
	Goal: CFrame,
	GoalWeight: number,
	Elapsed: number,
}

-- Sin claves débiles: el objeto Luau de una articulación se puede recoger aunque siga en el
-- personaje y se perdería su postura. Se quita cuando la articulación ya no está (update).
local states: { [Instance]: State } = {}
local nextSlash: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local nextPunch: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

local function jointOf(instance: Instance?, rig: string, side: number): Joint?
	if instance and (instance:IsA("Motor6D") or instance:IsA("AnimationConstraint")) then
		return { Target = instance, Rig = rig, Side = side }
	end
	return nil
end

-- Articulaciones del personaje: hombros (Side 1 derecha, -1 izquierda) y cintura.
local function joints(character: Model?): ({ [string]: Joint })
	local found = {}
	if not character then
		return found
	end
	local upperTorso = character:FindFirstChild("UpperTorso")
	if upperTorso then
		local right = character:FindFirstChild("RightUpperArm")
		local left = character:FindFirstChild("LeftUpperArm")
		local waist = upperTorso:FindFirstChild("Waist")
		found.Right = jointOf(right and right:FindFirstChild("RightShoulder"), "R15", 1)
		found.Left = jointOf(left and left:FindFirstChild("LeftShoulder"), "R15", -1)
		found.Waist = jointOf(waist, "R15", 0)
		return found
	end
	local torso = character:FindFirstChild("Torso")
	if torso then
		found.Right = jointOf(torso:FindFirstChild("Right Shoulder"), "R6", 1)
		found.Left = jointOf(torso:FindFirstChild("Left Shoulder"), "R6", -1)
	end
	return found
end

-- Giro de un brazo: `forward` grados hacia delante (90 = horizontal, 180 = arriba) y `out`
-- grados hacia fuera (abrirlo a un lado).
local function armRotation(joint: Joint, forward: number, out: number): CFrame
	if joint.Rig == "R15" then
		return CFrame.Angles(math.rad(forward), 0, math.rad(out * joint.Side))
	end
	-- R6: el hombro está girado 90° (el eje de "hacia delante" es Z local)
	return CFrame.Angles(math.rad(-out), 0, math.rad(forward * joint.Side))
end

local function ease(kind: string, t: number): number
	if kind == "Out" then
		return 1 - (1 - t) * (1 - t)
	elseif kind == "InOut" then
		return if t < 0.5 then 2 * t * t else 1 - (-2 * t + 2) ^ 2 / 2
	end
	return t
end

-- Empieza el siguiente tramo desde donde está ahora
local function nextStep(state: State)
	local step = state.Steps[1]
	if not step then
		return
	end
	state.From = state.Offset
	state.FromWeight = state.Weight
	state.Elapsed = 0
	if step.ToRest then
		state.Goal = state.Rest or CFrame.identity
		state.GoalWeight = if state.Rest then 1 else 0
	else
		state.Goal = step.To or state.Offset
		state.GoalWeight = step.Weight or 1
	end
end

local stepping = false
local function update(dt: number)
	for target, state in states do
		if not target.Parent then
			states[target] = nil
			continue
		end
		local step = state.Steps[1]
		if step then
			state.Elapsed += dt
			local t = if step.Duration > 0 then math.clamp(state.Elapsed / step.Duration, 0, 1) else 1
			local alpha = ease(step.Ease, t)
			state.Offset = state.From:Lerp(state.Goal, alpha)
			state.Weight = state.FromWeight + (state.GoalWeight - state.FromWeight) * alpha
			if t >= 1 then
				table.remove(state.Steps, 1)
				nextStep(state)
			end
		end
		if state.Weight > 0.001 then
			local joint = target :: any
			-- La animación ya ha escrito su Transform en este fotograma: se mezcla con el giro
			joint.Transform = if state.Weight >= 0.999 then state.Offset else (joint.Transform :: CFrame):Lerp(state.Offset, state.Weight)
		elseif not state.Steps[1] and not state.Rest then
			states[target] = nil -- ya solo manda la animación
		end
	end
end

local function stateOf(joint: Joint): State
	local state = states[joint.Target]
	if not state then
		state = {
			Offset = CFrame.identity,
			Weight = 0,
			Rest = nil,
			Steps = {},
			From = CFrame.identity,
			FromWeight = 0,
			Goal = CFrame.identity,
			GoalWeight = 0,
			Elapsed = 0,
		}
		states[joint.Target] = state
	end
	if not stepping then
		stepping = true
		RunService.PreSimulation:Connect(update)
	end
	return state :: State
end

-- Cambia los tramos de una articulación (lo que estaba haciendo se corta desde donde está)
local function play(joint: Joint, steps: { Step })
	local state = stateOf(joint)
	state.Steps = steps
	nextStep(state)
end

-- Lleva la articulación a `rotation` en `outSeconds`, la mantiene `hold` y vuelve a su reposo
-- (setRest; la animación si no hay) en `back`.
local function swing(joint: Joint?, rotation: CFrame, outSeconds: number, hold: number, back: number)
	if not joint then
		return
	end
	play(joint, {
		{ To = rotation, Weight = 1, Duration = outSeconds, Ease = "Out" },
		{ To = rotation, Weight = 1, Duration = hold, Ease = "Linear" },
		{ ToRest = true, Duration = back, Ease = "InOut" },
	})
end

local function waistTurn(found, degrees: number, outSeconds: number, hold: number, back: number)
	local waist = found.Waist
	if waist then
		swing(waist, CFrame.Angles(0, math.rad(degrees), 0), outSeconds, hold, back)
	end
end

-- Puñetazo: alterna brazo; el otro se queda en guardia un momento
function CharacterPose.punch(character: Model?)
	if not character then
		return
	end
	local found = joints(character)
	local side = nextPunch[character] or 1
	nextPunch[character] = -side
	local hitter = if side > 0 then found.Right else found.Left
	local guard = if side > 0 then found.Left else found.Right
	if hitter then
		swing(hitter, armRotation(hitter, 95, -8), 0.06, 0.06, 0.14)
	end
	if guard then
		swing(guard, armRotation(guard, 55, 0), 0.08, 0.12, 0.2)
	end
	waistTurn(found, 18 * side, 0.06, 0.06, 0.16)
end

-- Apuntar con el arma (brazo derecho al frente mientras dispares)
function CharacterPose.aim(character: Model?)
	local found = joints(character)
	if found.Right then
		swing(found.Right, armRotation(found.Right, 88, 0), 0.08, 0.45, 0.25)
	end
end

-- Lanzar un hechizo: brazos hacia delante y un poco arriba
function CharacterPose.cast(character: Model?, charge: number?)
	local found = joints(character)
	local hold = charge or 0.1
	for _, joint in { found.Right, found.Left } do
		swing(joint, armRotation(joint, 115, -12), 0.12, hold, 0.28)
	end
end

-- Granada: brazo atrás y por encima del hombro hacia delante
function CharacterPose.throw(character: Model?)
	local found = joints(character)
	local right = found.Right
	if not right then
		return
	end
	swing(right, armRotation(right, -50, 10), 0.12, 0, 0.1)
	task.delay(0.12, function()
		swing(right, armRotation(right, 160, 0), 0.08, 0.1, 0.3)
	end)
	waistTurn(found, -20, 0.12, 0.05, 0.3)
end

-- Terremoto: brazos arriba y golpe al suelo
function CharacterPose.slam(character: Model?)
	local found = joints(character)
	for _, joint in { found.Right, found.Left } do
		swing(joint, armRotation(joint, 170, 10), 0.12, 0.05, 0.05)
	end
	task.delay(0.17, function()
		for _, joint in { found.Right, found.Left } do
			swing(joint, armRotation(joint, 40, 25), 0.06, 0.25, 0.3)
		end
	end)
end

-- Nova: brazos abiertos a los lados
function CharacterPose.spread(character: Model?)
	local found = joints(character)
	for _, joint in { found.Right, found.Left } do
		swing(joint, armRotation(joint, 20, 80), 0.1, 0.35, 0.3)
	end
end

-- Embestida: los dos puños por delante
function CharacterPose.charge(character: Model?)
	local found = joints(character)
	for _, joint in { found.Right, found.Left } do
		swing(joint, armRotation(joint, 90, -15), 0.05, 0.3, 0.25)
	end
end

-- Postura de reposo: "Gun" (el arma medio levantada), "Aim" (el arma al frente: apuntando),
-- "Sword" (la espada en guardia), "Block" (la espada cruzada delante), "Staff" (el bastón) o
-- nil (los brazos caídos). Solo se ve (cada cliente, cada personaje).
local REST_POSES = {
	Gun = { Right = { 40, 4 } },
	Aim = { Right = { 88, 0 }, Left = { 70, -35 } },
	Sword = { Right = { 25, 8 } },
	Block = { Right = { 75, -55 }, Left = { 55, -20 } },
	Staff = { Right = { 12, 6 } },
}
function CharacterPose.setRest(character: Model?, pose: string?)
	local found = joints(character)
	local spec = pose and REST_POSES[pose] or {}
	for _, side in { "Right", "Left" } do
		local joint = found[side]
		if joint then
			local angles = spec[side]
			local rest = if angles then armRotation(joint, angles[1], angles[2]) else nil
			local existing = states[joint.Target]
			if rest or existing then
				local state = stateOf(joint)
				if state.Rest ~= rest then
					state.Rest = rest
					-- Un golpe en marcha vuelve solo al reposo nuevo; si no (o si ya estaba
					-- volviendo al de antes), se va ya
					local current = state.Steps[1]
					if not current or current.ToRest then
						play(joint, { { ToRest = true, Duration = 0.18, Ease = "Out" } })
					end
				end
			end
		end
	end
end

-- Disparo: el arma sube al frente (la otra mano la sujeta), salta un poco con el retroceso
-- y se queda apuntando mientras sigas disparando; luego vuelve a su reposo
function CharacterPose.recoil(character: Model?, strength: number?)
	local found = joints(character)
	local right = found.Right
	if right then
		local kick = 14 * (strength or 1)
		local aimed = armRotation(right, 88, 0)
		play(right, {
			{ To = armRotation(right, 88 + kick, 0), Weight = 1, Duration = 0.04, Ease = "Out" },
			{ To = aimed, Weight = 1, Duration = 0.08, Ease = "Out" },
			{ To = aimed, Weight = 1, Duration = 0.45, Ease = "Linear" },
			{ ToRest = true, Duration = 0.25, Ease = "InOut" },
		})
	end
	local left = found.Left
	if left then
		swing(left, armRotation(left, 70, -35), 0.08, 0.55, 0.25)
	end
end

-- Tajo del Guerrero: 1 de derecha a izquierda, 2 de vuelta, 3 el giro (brazos abiertos)
function CharacterPose.slash(character: Model?, step: number?)
	if not character then
		return
	end
	local found = joints(character)
	local right = found.Right
	if not right then
		return
	end
	local which = step or nextSlash[character] or 1
	nextSlash[character] = (which % 3) + 1
	if which == 1 then
		swing(right, armRotation(right, 100, 70), 0.05, 0, 0.02)
		task.delay(0.06, function()
			swing(right, armRotation(right, 85, -45), 0.08, 0.08, 0.2)
		end)
		waistTurn(found, -22, 0.08, 0.06, 0.2)
	elseif which == 2 then
		swing(right, armRotation(right, 95, -40), 0.05, 0, 0.02)
		task.delay(0.06, function()
			swing(right, armRotation(right, 80, 75), 0.08, 0.08, 0.2)
		end)
		waistTurn(found, 22, 0.08, 0.06, 0.2)
	else
		for _, joint in { found.Right, found.Left } do
			swing(joint, armRotation(joint, 85, 80), 0.06, 0.22, 0.25)
		end
		waistTurn(found, 45, 0.1, 0.08, 0.25)
	end
end

-- Punto de lo que lleva en la mano: "Muzzle" (boca del arma), "Tip" (punta de la espada) u
-- "Orb" (esfera del bastón). nil si no lleva o no tiene ese punto.
function CharacterPose.gearPoint(character: Model?, name: string): Vector3?
	local gear = character and character:FindFirstChild("HeldGear")
	local handle = gear and (gear :: Model).PrimaryPart or (gear and gear:FindFirstChild("Handle"))
	local attachment = handle and handle:FindFirstChild(name)
	if attachment and attachment:IsA("Attachment") then
		return attachment.WorldPosition
	end
	return nil
end

-- Posición de la mano derecha (o del centro del personaje) para sacar efectos de ella.
function CharacterPose.handPosition(character: Model?): Vector3?
	if not character then
		return nil
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if hand and hand:IsA("BasePart") then
		return if hand.Name == "Right Arm" then (hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, 0)).Position else hand.Position
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position + Vector3.new(0, 1.2, 0) else nil
end

return CharacterPose
