-- Boca de la Cueva de los Espinillos (Bosque, en la colina oeste). El camino de la plaza a la
-- boca es un camino más del suelo (StudFloor Paths) y el hueco en la colina lo hace StudWorld
-- (layout.Cave.Opening); aquí va lo demás:
-- - El fondo del túnel cerrado con roca y, delante, una bruma que se oscurece hasta el negro
--   (capas cada vez más opacas) con chispas moradas: al cruzarla, CaveService te lleva dentro
--   de la cueva (CaveConfig, lejos del mapa; la construye CaveDungeon).
-- - Antorchas a los lados de la boca y el cartel encima.
-- buildMound: la boca de las otras mazmorras (Valle y Caldera, CaveConfig.Caves.*.Entrance.Mound):
-- un montículo de roca de bloques con el túnel en medio, la misma bruma, antorchas y cartel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local PartFactory = require(script.Parent.PartFactory)
local StudWorld = require(script.Parent.StudWorld)

local ForestCave = {}

local RGB = Color3.fromRGB
local B = 8 -- bloques de 8, alineados con el suelo del Bosque
local GROUND = GeneratorConfig.Position.Y

local ROCK = { RGB(104, 108, 140), RGB(86, 90, 120) }
local DARK = RGB(8, 6, 18)
local MIST = RGB(150, 90, 255)

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, solid: boolean?): Part
	return PartFactory.part(parent, name, {
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.Plastic,
		Solid = solid,
	})
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local point = Instance.new("PointLight")
	point.Color = color
	point.Range = range
	point.Brightness = brightness
	point.Shadows = false
	point.Parent = parent
end

-- Antorcha de pie (palo, llama de neón con fuego y luz). Sirve también para la cueva de dentro.
function ForestCave.torch(parent: Instance, position: Vector3): Part
	local stick = block(parent, "Palo", Vector3.new(0.6, 3.4, 0.6), CFrame.new(position), RGB(120, 76, 40), false)
	local flame = block(parent, "Llama", Vector3.new(1, 1.3, 1), CFrame.new(position + Vector3.new(0, 2.3, 0)), RGB(255, 160, 60), false)
	flame.Material = Enum.Material.Neon
	flame.CastShadow = false
	light(flame, RGB(255, 170, 90), 18, 1.6)
	local fire = Instance.new("Fire")
	fire.Size = 2.5
	fire.Heat = 4
	fire.Color = RGB(255, 150, 60)
	fire.SecondaryColor = RGB(255, 230, 120)
	fire.Parent = flame
	return stick
end

-- Cartel de madera con letras (cara `face`), para la boca y las salas de dentro.
function ForestCave.sign(parent: Instance, name: string, size: Vector3, cframe: CFrame, face: Enum.NormalId, text: string): Part
	local board = block(parent, name, size, cframe, RGB(150, 98, 54))
	local u = if face == Enum.NormalId.Left or face == Enum.NormalId.Right then size.Z else size.X
	StudWorld.studFace(board, face, u, size.Y)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Texto"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = RGB(255, 236, 170)
	label.TextStrokeColor3 = RGB(43, 29, 63)
	label.TextStrokeTransparency = 0
	label.Text = text
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.Parent = label
	return board
end

-- Chispas que flotan despacio (bruma de la boca y portales de dentro).
function ForestCave.motes(part: BasePart, color: Color3, face: Enum.NormalId, rate: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Chispas"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0.2)
	emitter.Lifetime = NumberRange.new(1.6, 2.8)
	emitter.Rate = rate
	emitter.Speed = NumberRange.new(0.6, 1.6)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.EmissionDirection = face
	emitter.Parent = part
	return emitter
end

function ForestCave.build(parent: Instance, layout)
	local cave = layout.Cave
	if not cave then
		return
	end
	local opening = cave.Opening
	local floorTop = StudWorld.FloorTop
	local doorRows = opening.Ceiling or 3
	local doorTop = GROUND + doorRows * B
	local doorZ0, doorZ1 = opening.MinZ, opening.MaxZ
	local midZ = (doorZ0 + doorZ1) / 2
	local width = doorZ1 - doorZ0
	local model = Instance.new("Model")
	model.Name = "ForestCave"

	-- 1. Fondo del túnel: roca (detrás ya no hay colina) un bloque más ancha y alta que el hueco
	local back = PartFactory.folder(model, "Fondo")
	for k = 0, math.round(width / B) + 1 do
		for r = 1, doorRows + 1 do
			local z = doorZ0 - B / 2 + k * B
			local part = block(back, ("fondo_%d_%d"):format(k, r), Vector3.new(B, B, B), CFrame.new(opening.MinX - B / 2, GROUND + (r - 0.5) * B, z), ROCK[(k + r) % 2 + 1], true)
			StudWorld.studFace(part, Enum.NormalId.Right, B, B)
		end
	end

	-- 2. Bruma: capas negras cada vez más opacas hacia el fondo (la boca "se traga" la luz) y
	-- chispas moradas. Sin colisión: al cruzarla te lleva dentro (CaveService).
	local mist = PartFactory.folder(model, "Bruma")
	local layers = { { 0.6, 0.86 }, { 2.8, 0.68 }, { 5, 0.42 }, { 7.4, 0.12 } }
	local deepest: Part? = nil
	for index, layer in layers do
		local x = opening.MinX + B - layer[1]
		local part = block(mist, "Bruma" .. index, Vector3.new(0.2, doorTop - floorTop, width), CFrame.new(x, (floorTop + doorTop) / 2, midZ), DARK, false)
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = layer[2]
		part.CastShadow = false
		deepest = part
	end
	if deepest then
		ForestCave.motes(deepest, MIST, Enum.NormalId.Right, 14)
		light(deepest, MIST, 14, 0.8)
	end

	-- 3. Antorchas a los lados de la boca, en la pradera
	local torchFolder = PartFactory.folder(model, "Torches")
	local outside = opening.MaxX + 1.2
	ForestCave.torch(torchFolder, Vector3.new(outside, floorTop + 1.7, doorZ0 - 2.5))
	ForestCave.torch(torchFolder, Vector3.new(outside, floorTop + 1.7, doorZ1 + 2.5))

	-- 4. Cartel encima de la boca, en la cara de la colina que mira a la pradera
	ForestCave.sign(model, "CartelCueva", Vector3.new(0.6, 5.2, 18), CFrame.new(opening.MaxX + 0.35, doorTop + 3.4, midZ), Enum.NormalId.Right, "⚠ " .. string.upper(cave.Name))

	model.Parent = parent
	return model
end

-- Boca de una mazmorra fuera del Bosque: montículo de Depth × Span (bloques de 8) y 3 filas de
-- alto (más una joroba encima), con un túnel de Width × Height desde el frente (Front, que
-- mira hacia Facing) hasta el bloque del fondo; dentro, la bruma que lleva a la cueva
-- (CaveService: Entrance.Trigger, en el fondo del túnel).
function ForestCave.buildMound(parent: Instance, cave)
	local spec = cave.Entrance.Mound
	local theme = cave.Theme or {}
	local rock = theme.Rock or ROCK
	local mistColor = theme.Mist or MIST
	local facing = Vector3.new(spec.Facing.X, 0, spec.Facing.Z).Unit
	local floorTop = StudWorld.FloorTop
	-- Marco: -Z local mira hacia fuera (Facing); X local a lo ancho; el montículo va hacia +Z
	local front = Vector3.new(spec.Front.X, GROUND, spec.Front.Z)
	local frame = CFrame.lookAt(front, front + facing)
	local model = Instance.new("Model")
	model.Name = "BocaCueva_" .. tostring(cave.Id)
	local cols = math.round(spec.Span / B)
	local deep = math.round(spec.Depth / B)
	local tunnelCols = math.round(spec.Width / B)
	local tunnelRows = math.round(spec.Height / B)
	local firstTunnel = math.floor((cols - tunnelCols) / 2) + 1
	local rocks = PartFactory.folder(model, "Roca")
	for d = 1, deep do
		for c = 1, cols do
			for row = 1, tunnelRows + 1 do
				local inTunnel = c >= firstTunnel and c < firstTunnel + tunnelCols and row <= tunnelRows and d < deep
				if not inTunnel then
					local offset = CFrame.new((c - (cols + 1) / 2) * B, (row - 0.5) * B, (d - 0.5) * B)
					local part = block(rocks, ("roca_%d_%d_%d"):format(d, c, row), Vector3.new(B, B, B), frame * offset, rock[(d + c + row) % 2 + 1], true)
					StudWorld.studFace(part, Enum.NormalId.Front, B, B)
					StudWorld.studFace(part, Enum.NormalId.Top, B, B)
				end
			end
		end
	end
	-- Joroba encima (más estrecha)
	for d = 1, deep - 1 do
		for c = 2, cols - 1 do
			local offset = CFrame.new((c - (cols + 1) / 2) * B, (tunnelRows + 1.5) * B, (d + 0.5) * B)
			local part = block(rocks, ("joroba_%d_%d"):format(d, c), Vector3.new(B, B, B), frame * offset, rock[(d + c) % 2 + 1], true)
			StudWorld.studFace(part, Enum.NormalId.Top, B, B)
		end
	end

	-- Bruma: capas oscuras cada vez más opacas hacia el fondo del túnel, con chispas
	local mist = PartFactory.folder(model, "Bruma")
	local back = (deep - 1) * B -- fondo del túnel (en Z local)
	local layers = { { 0.6, 0.86 }, { 2.8, 0.68 }, { 5, 0.42 }, { 7.4, 0.12 } }
	local deepest: Part? = nil
	local tunnelHeight = tunnelRows * B
	local lift = floorTop - GROUND
	for index, layer in layers do
		local z = back - B + layer[1]
		local part = block(mist, "Bruma" .. index, Vector3.new(spec.Width, tunnelHeight - lift, 0.2), frame * CFrame.new(0, (tunnelHeight + lift) / 2, z), DARK, false)
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = layer[2]
		part.CastShadow = false
		deepest = part
	end
	if deepest then
		ForestCave.motes(deepest, mistColor, Enum.NormalId.Front, 14)
		light(deepest, mistColor, 14, 0.8)
	end

	-- Antorchas a los lados de la boca y cartel encima
	local torches = PartFactory.folder(model, "Torches")
	for _, side in { -1, 1 } do
		local p = frame * CFrame.new(side * (spec.Width / 2 + 2.5), lift + 1.7, -1.2)
		ForestCave.torch(torches, p.Position)
	end
	local signCFrame = frame * CFrame.new(0, tunnelHeight + 3.4, -0.35)
	ForestCave.sign(model, "CartelCueva", Vector3.new(18, 5.2, 0.6), signCFrame, Enum.NormalId.Front, ("⚠ %s %s"):format(cave.Icon or "", string.upper(cave.Name)))

	model.Parent = parent
	return model
end

return ForestCave
