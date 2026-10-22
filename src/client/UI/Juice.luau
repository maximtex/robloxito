-- Efectos de satisfacción de la interfaz (solo cliente, solo presentación):
-- - Juice.sound: sonido 2D (sin posición) con volumen y tono.
-- - Juice.burst: estallido de estrellas que salen de un elemento de la interfaz, giran y se
--   apagan (mejora comprada, mascota nueva...).
-- - Juice.pop: "rebote" breve de escala en un elemento.
-- Sin recursos externos raros: sonidos ya usados en el juego y texto "★" (se ve en todas
-- las fuentes del juego).

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Juice = {}

-- Sonidos de la interfaz (los mismos que ya usan las aventuras y el combate).
Juice.Sounds = {
	Upgrade = { Id = "rbxassetid://9116394876", Volume = 0.45, Pitch = 1.25 },
	Crack = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.5, Pitch = 1.7 },
	Hatch = { Id = "rbxassetid://9116394876", Volume = 0.7, Pitch = 0.95 },
	HatchRare = { Id = "rbxassetid://9114518386", Volume = 0.6, Pitch = 1.1 },
	HatchEpic = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.45, Pitch = 1.35 },
}

function Juice.sound(spec: any, pitchScale: number?)
	if not spec then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = spec.Id
	sound.Volume = spec.Volume or 0.5
	sound.PlaybackSpeed = (spec.Pitch or 1) * (pitchScale or 1)
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(5, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

-- Estallido de `count` estrellas desde el centro de `origin` (en su mismo ScreenGui).
function Juice.burst(origin: GuiObject, color: Color3, count: number?, distance: number?)
	local gui = origin:FindFirstAncestorWhichIsA("LayerCollector")
	if not gui then
		return
	end
	local center = origin.AbsolutePosition + origin.AbsoluteSize / 2
	local total = count or 10
	local reach = distance or 110
	for index = 1, total do
		local angle = (index / total) * math.pi * 2 + math.random() * 0.5
		local size = math.random(16, 28)
		local star = Instance.new("TextLabel")
		star.Name = "JuiceStar"
		star.BackgroundTransparency = 1
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Size = UDim2.fromOffset(size, size)
		star.Position = UDim2.fromOffset(center.X, center.Y)
		star.Font = Enum.Font.FredokaOne
		star.TextScaled = true
		star.Text = "★"
		star.TextColor3 = if index % 3 == 0 then Color3.new(1, 1, 1) else color
		star.TextStrokeColor3 = Color3.fromRGB(40, 30, 10)
		star.TextStrokeTransparency = 0.5
		star.Rotation = math.random(0, 360)
		star.ZIndex = 50
		star.Active = false
		star.Parent = gui
		local travel = reach * (0.6 + math.random() * 0.6)
		local target = center + Vector2.new(math.cos(angle), math.sin(angle)) * travel
		local info = TweenInfo.new(0.55 + math.random() * 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(star, info, {
			Position = UDim2.fromOffset(target.X, target.Y),
			Rotation = star.Rotation + math.random(-200, 200),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
			Size = UDim2.fromOffset(size * 0.4, size * 0.4),
		})
		tween.Completed:Once(function()
			star:Destroy()
		end)
		tween:Play()
	end
end

-- Rebote de escala (usa o crea un UIScale llamado "JuicePop").
function Juice.pop(target: GuiObject, amount: number?)
	local scale = target:FindFirstChild("JuicePop")
	if not (scale and scale:IsA("UIScale")) then
		scale = Instance.new("UIScale")
		scale.Name = "JuicePop"
		scale.Parent = target
	end
	local uiScale = scale :: UIScale
	uiScale.Scale = 1 + (amount or 0.12)
	TweenService:Create(uiScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

return Juice
