-- Modelos del mapa sacados de la Creator Store y guardados EN EL PLACE (no en el repo):
-- ServerStorage.MapAssets con carpetas Trees, TallTrees, Bushes, Rocks y Landmarks.
-- - Árboles y arbustos: "Yasu's Stylized Tree Pack" (mvyasu). Cada uno son dos MeshPart
--   (tronco y copa) con SurfaceAppearance; la copa se tiñe con SurfaceAppearance.Color.
-- - Rocas: "Stylized Rocks - Free Pack" (PolyOne Studio, subido por Astrojox).
-- Sin scripts (se revisaron al insertarlos). Si la carpeta no está (place nuevo o sin
-- guardar), has() devuelve false y quien llama usa sus piezas básicas de siempre.
--
-- place() clona una variante, la escala a la altura pedida, la apoya en el suelo y la gira;
-- solo el tronco (o la roca entera) es sólido: las copas no chocan ni bloquean rayos.

local ServerStorage = game:GetService("ServerStorage")

local MapAssets = {}

local FOLDER_NAME = "MapAssets"
local SINK = 0.35 -- se hunde un poco para no flotar en pendientes suaves

type Variant = { Template: Model, Height: number, Bottom: CFrame }

local cache: { [string]: { Variant } } = {}

local function variantsOf(kind: string): { Variant }
	local cached = cache[kind]
	if cached then
		return cached
	end
	local list: { Variant } = {}
	local root = ServerStorage:FindFirstChild(FOLDER_NAME)
	local folder = root and root:FindFirstChild(kind)
	if folder then
		local models = folder:GetChildren()
		table.sort(models, function(a, b)
			return a.Name < b.Name
		end)
		for _, model in models do
			if model:IsA("Model") then
				local boxCFrame, size = model:GetBoundingBox()
				if size.Y > 0 then
					-- Punto de apoyo: centro de la base de la caja, sin giro.
					local bottom = CFrame.new(boxCFrame.Position - Vector3.new(0, size.Y / 2, 0))
					table.insert(list, { Template = model, Height = size.Y, Bottom = bottom })
				end
			end
		end
	end
	cache[kind] = list
	return list
end

function MapAssets.has(kind: string): boolean
	return #variantsOf(kind) > 0
end

function MapAssets.count(kind: string): number
	return #variantsOf(kind)
end

export type Options = {
	Height: number, -- altura final (studs)
	Yaw: number?, -- giro (radianes)
	Pick: number?, -- [0, 1): qué variante (determinista con la semilla del paisaje)
	Variant: number?, -- índice exacto (tiene prioridad sobre Pick)
	Tint: Color3?, -- color de la copa (SurfaceAppearance.Color de las piezas "Canopy")
	TintAll: boolean?, -- el tinte se aplica a todas las piezas (rocas oscuras de la Caldera);
	-- en las mallas con textura propia (que taparía el color) se quita la textura y se usa
	-- el material Material (basalto) con ese color.
	Material: Enum.Material?,
	Solid: string?, -- "Trunk" (por defecto), "All" o "None"
	Name: string?,
}

-- Coloca una copia apoyada en `ground` (punto del suelo). Devuelve el modelo o nil.
function MapAssets.place(kind: string, parent: Instance, ground: Vector3, options: Options): Model?
	local list = variantsOf(kind)
	if #list == 0 then
		return nil
	end
	local index = options.Variant or (math.floor((options.Pick or 0) * #list) + 1)
	local variant = list[math.clamp(index, 1, #list)]
	local model = variant.Template:Clone()
	local scale = options.Height / variant.Height
	-- Escalar respecto a la base: la relación base -> pivote se escala igual.
	local pivot = model:GetPivot()
	local offset = variant.Bottom:ToObjectSpace(pivot)
	model:ScaleTo(model:GetScale() * scale)
	local scaledOffset = CFrame.new(offset.Position * scale) * offset.Rotation
	local base = CFrame.new(ground - Vector3.new(0, SINK, 0)) * CFrame.Angles(0, options.Yaw or 0, 0)
	model:PivotTo(base * scaledOffset)

	local solid = options.Solid or "Trunk"
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanTouch = false
			local isCanopy = part.Name:find("Canopy") ~= nil or part.Name:find("Leaves") ~= nil
			local collide = solid == "All" or (solid == "Trunk" and not isCanopy)
			part.CanCollide = collide
			part.CanQuery = collide
			if options.TintAll and options.Tint and part:IsA("MeshPart") and part.TextureID ~= "" then
				part.TextureID = ""
				if options.Material then
					part.Material = options.Material
				end
			end
			if (isCanopy or options.TintAll) and options.Tint then
				local appearance = part:FindFirstChildOfClass("SurfaceAppearance")
				if appearance then
					appearance.Color = options.Tint
				else
					part.Color = options.Tint
				end
			end
		end
	end
	model.Name = options.Name or kind
	model:SetAttribute("MapAsset", kind) -- WorkspaceAudit no lo lista como objeto suelto
	model.Parent = parent
	return model
end

return MapAssets
