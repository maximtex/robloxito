-- Partículas ambientales del mapa (polvo mágico, luciérnagas, polvo que cae del árbol
-- ancestral, destellos de cristal y bruma). Solo decorativo: cada campo es una pieza
-- invisible, anclada y sin colisión con un ParticleEmitter que emite en todo su volumen.
-- Sin recursos externos: solo texturas internas de Roblox (rbxasset://).

local PartFactory = require(script.Parent.PartFactory)

local Ambience = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function fade(size: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, size),
		NumberSequenceKeypoint.new(0.7, size),
		NumberSequenceKeypoint.new(1, 0),
	})
end

-- Estilos de partícula. Cada uno recibe el color (o dos) del lugar.
local PRESETS: { [string]: (Color3, Color3?) -> { [string]: any } } = {
	-- Motas de luz que flotan despacio por el claro.
	Motes = function(color, second)
		return {
			Texture = SPARKLE,
			Lifetime = NumberRange.new(6, 10),
			Speed = NumberRange.new(0.1, 0.4),
			SpreadAngle = Vector2.new(180, 180),
			Size = fade(0.18),
			Color = ColorSequence.new(color, second or color),
			LightEmission = 0.8,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-30, 30),
		}
	end,
	-- Luciérnagas: puntos brillantes que suben y se apagan.
	Fireflies = function(color)
		return {
			Texture = SPARKLE,
			Lifetime = NumberRange.new(3, 5),
			Speed = NumberRange.new(0.2, 0.6),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, 0.12, 0),
			Size = fade(0.24),
			Color = ColorSequence.new(color),
			LightEmission = 1,
		}
	end,
	-- Polvo mágico que cae girando (copa del árbol ancestral).
	Falling = function(color, second)
		return {
			Texture = SPARKLE,
			Lifetime = NumberRange.new(7, 9),
			Speed = NumberRange.new(0.2, 0.4),
			EmissionDirection = Enum.NormalId.Bottom,
			SpreadAngle = Vector2.new(40, 40),
			Acceleration = Vector3.new(0, -0.4, 0),
			Size = fade(0.3),
			Color = ColorSequence.new(color, second or color),
			LightEmission = 0.9,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-60, 60),
		}
	end,
	-- Ascuas que suben despacio y se apagan (Caldera de Brasas).
	Embers = function(color, second)
		return {
			Texture = SPARKLE,
			Lifetime = NumberRange.new(4, 7),
			Speed = NumberRange.new(0.6, 1.6),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(35, 35),
			Acceleration = Vector3.new(0, 0.5, 0),
			Size = fade(0.2),
			Color = ColorSequence.new(color, second or color),
			LightEmission = 1,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-90, 90),
		}
	end,
	-- Humo denso que sube (cráter del volcán y fumarolas).
	Smoke = function(color)
		return {
			Texture = SMOKE,
			Lifetime = NumberRange.new(6, 9),
			Speed = NumberRange.new(2, 4),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(18, 18),
			Acceleration = Vector3.new(0.4, 0.6, 0),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 14) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.7, 0.75), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(color),
			LightEmission = 0,
			RotSpeed = NumberRange.new(-12, 12),
		}
	end,
	-- Hilillo de humo pequeño y suave (chimeneas del pueblo).
	Wisp = function(color)
		return {
			Texture = SMOKE,
			Lifetime = NumberRange.new(3, 4.5),
			Speed = NumberRange.new(1, 1.8),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(10, 10),
			Acceleration = Vector3.new(0.3, 0.15, 0),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 3) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.6, 0.8), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(color),
			LightEmission = 0,
			RotSpeed = NumberRange.new(-15, 15),
		}
	end,
	-- Penacho de humo enorme y lento (cráter del volcán: se ve desde lejos).
	Plume = function(color)
		return {
			Texture = SMOKE,
			Lifetime = NumberRange.new(12, 16),
			Speed = NumberRange.new(5, 8),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(12, 12),
			Acceleration = Vector3.new(1.2, 0.4, 0),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 14), NumberSequenceKeypoint.new(1, 46) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(0.7, 0.7), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(color),
			LightEmission = 0,
			RotSpeed = NumberRange.new(-8, 8),
		}
	end,
	-- Bruma suave (pie de la cascada).
	Mist = function(color)
		return {
			Texture = SMOKE,
			Lifetime = NumberRange.new(3, 5),
			Speed = NumberRange.new(0.5, 1),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(25, 25),
			Size = NumberSequence.new(3, 6),
			Transparency = NumberSequence.new(0.82, 1),
			Color = ColorSequence.new(color),
			LightEmission = 0.1,
			RotSpeed = NumberRange.new(-10, 10),
		}
	end,
}

-- Crea un campo de partículas. `style` es una clave de PRESETS.
function Ambience.field(parent: Instance, name: string, style: string, center: Vector3, size: Vector3, rate: number, color: Color3, second: Color3?): Part
	local part = PartFactory.part(parent, name, {
		Size = size,
		CFrame = CFrame.new(center),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
		CastShadow = false,
	})
	part.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Particles"
	emitter.LightInfluence = 0
	for key, value in PRESETS[style](color, second) do
		(emitter :: any)[key] = value
	end
	emitter.Rate = rate
	emitter.Parent = part
	return part
end

return Ambience
