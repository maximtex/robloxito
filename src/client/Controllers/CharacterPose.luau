-- Movimientos del personaje al pelear, hechos a mano en cada cliente (solo se ven, no
-- cambian nada del juego): se giran un momento las articulaciones de los hombros y la
-- cintura (Motor6D.C0) y vuelven a su sitio. Sirve para R15 y R6.
-- - punch: un puñetazo (alterna derecha e izquierda) con un giro de cintura.
-- - aim: apunta con el brazo derecho (se mantiene mientras sigas disparando).
-- - cast: los dos brazos hacia delante y arriba (lanzar un hechizo).
-- - throw: brazo atrás y lanzamiento por encima del hombro (granada).
-- - slam: los dos brazos arriba y golpe abajo (terremoto).
-- - spread: los dos brazos abiertos a los lados (nova).
-- - charge: los dos brazos hacia delante, como al embestir.
-- Los usa CombatController (cada golpe del estilo) y StyleController (las habilidades), con
-- el personaje de quien ataca (también el de otros jugadores cercanos).

local TweenService = game:GetService("TweenService")

local CharacterPose = {}

type Joint = { Motor: Motor6D, Rig: string, Side: number }

local originals: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local tokens: { [Motor6D]: number } = setmetatable({}, { __mode = "k" }) :: any
local nextPunch: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

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
		local rightMotor = right and right:FindFirstChild("RightShoulder")
		local leftMotor = left and left:FindFirstChild("LeftShoulder")
		if rightMotor and rightMotor:IsA("Motor6D") then
			found.Right = { Motor = rightMotor, Rig = "R15", Side = 1 }
		end
		if leftMotor and leftMotor:IsA("Motor6D") then
			found.Left = { Motor = leftMotor, Rig = "R15", Side = -1 }
		end
		if waist and waist:IsA("Motor6D") then
			found.Waist = { Motor = waist, Rig = "R15", Side = 0 }
		end
		return found
	end
	local torso = character:FindFirstChild("Torso")
	if torso then
		local rightMotor = torso:FindFirstChild("Right Shoulder")
		local leftMotor = torso:FindFirstChild("Left Shoulder")
		if rightMotor and rightMotor:IsA("Motor6D") then
			found.Right = { Motor = rightMotor, Rig = "R6", Side = 1 }
		end
		if leftMotor and leftMotor:IsA("Motor6D") then
			found.Left = { Motor = leftMotor, Rig = "R6", Side = -1 }
		end
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

-- Lleva la articulación a `rotation` en `outSeconds`, la mantiene `hold` y vuelve en `back`.
local function swing(joint: Joint?, rotation: CFrame, outSeconds: number, hold: number, back: number)
	if not joint then
		return
	end
	local motor = joint.Motor
	local base = originals[motor]
	if not base then
		base = motor.C0
		originals[motor] = base
	end
	local token = (tokens[motor] or 0) + 1
	tokens[motor] = token
	TweenService:Create(motor, TweenInfo.new(outSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = base * rotation }):Play()
	task.delay(outSeconds + hold, function()
		if tokens[motor] == token and motor.Parent then
			TweenService:Create(motor, TweenInfo.new(back, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { C0 = base }):Play()
		end
	end)
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
