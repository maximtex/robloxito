-- Animaciones propias de cada mascota (alas, colas, hojas y parpadeo), en local.
-- Lee lo que deja PetModelBuilder en el modelo:
-- - Welds llamados "PetAnim" con atributos Hinge (Vector3, punto de giro en el espacio
--   de la raíz), Axis (Vector3), Offset, Amp, Speed y Phase (números). Cada frame:
--   ángulo = Offset + Amp · sin(t · Speed + Phase), girando alrededor de Hinge.
-- - Piezas con el atributo PetBlink = "Open" (ojos abiertos) o "Closed" (párpados).
-- Un modelo de arte externo puede usar los mismos atributos para animarse igual.

local PetAnimator = {}

type Joint = {
	Weld: Weld,
	Base: CFrame,
	Hinge: Vector3,
	Axis: Vector3,
	Offset: number,
	Amp: number,
	Speed: number,
	Phase: number,
}

export type Rig = {
	Joints: { Joint },
	Open: { BasePart },
	Closed: { BasePart },
	Random: Random,
	NextBlink: number,
	BlinkUntil: number,
	Blinking: boolean,
}

local BLINK_SECONDS = 0.12
local BLINK_MIN_GAP = 2.5
local BLINK_MAX_GAP = 5.5

local function numberAttribute(instance: Instance, name: string, default: number): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else default
end

-- Devuelve nil si el modelo no tiene nada que animar.
function PetAnimator.collect(model: Model): Rig?
	local rig: Rig = {
		Joints = {},
		Open = {},
		Closed = {},
		Random = Random.new(),
		NextBlink = 0,
		BlinkUntil = 0,
		Blinking = false,
	}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Weld") and descendant.Name == "PetAnim" then
			local hinge = descendant:GetAttribute("Hinge")
			local axis = descendant:GetAttribute("Axis")
			if typeof(hinge) == "Vector3" and typeof(axis) == "Vector3" and axis.Magnitude > 0 then
				table.insert(rig.Joints, {
					Weld = descendant,
					Base = descendant.C0,
					Hinge = hinge,
					Axis = axis.Unit,
					Offset = numberAttribute(descendant, "Offset", 0),
					Amp = numberAttribute(descendant, "Amp", 0),
					Speed = numberAttribute(descendant, "Speed", 1),
					Phase = numberAttribute(descendant, "Phase", 0),
				})
			end
		elseif descendant:IsA("BasePart") then
			local blink = descendant:GetAttribute("PetBlink")
			if blink == "Open" then
				table.insert(rig.Open, descendant)
			elseif blink == "Closed" then
				table.insert(rig.Closed, descendant)
			end
		end
	end
	if #rig.Joints == 0 and (#rig.Open == 0 or #rig.Closed == 0) then
		return nil
	end
	rig.NextBlink = rig.Random:NextNumber(0.5, BLINK_MAX_GAP)
	return rig
end

local function setBlink(rig: Rig, closed: boolean)
	rig.Blinking = closed
	for _, part in rig.Open do
		part.Transparency = if closed then 1 else 0
	end
	for _, part in rig.Closed do
		part.Transparency = if closed then 0 else 1
	end
end

-- t: tiempo en segundos (con la fase propia de la mascota ya sumada).
function PetAnimator.step(rig: Rig, t: number)
	for _, joint in rig.Joints do
		local angle = joint.Offset + joint.Amp * math.sin(t * joint.Speed + joint.Phase)
		joint.Weld.C0 = CFrame.new(joint.Hinge) * CFrame.fromAxisAngle(joint.Axis, angle) * CFrame.new(-joint.Hinge) * joint.Base
	end

	if #rig.Open > 0 and #rig.Closed > 0 then
		if rig.Blinking then
			if t >= rig.BlinkUntil then
				setBlink(rig, false)
				rig.NextBlink = t + rig.Random:NextNumber(BLINK_MIN_GAP, BLINK_MAX_GAP)
			end
		elseif t >= rig.NextBlink then
			setBlink(rig, true)
			rig.BlinkUntil = t + BLINK_SECONDS
		elseif rig.NextBlink - t > BLINK_MAX_GAP * 2 then
			-- El reloj retrocedió (otra fase): reprogramar.
			rig.NextBlink = t + rig.Random:NextNumber(BLINK_MIN_GAP, BLINK_MAX_GAP)
		end
	end
end

return PetAnimator
