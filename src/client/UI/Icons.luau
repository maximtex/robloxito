-- Iconos dibujados del HUD (estilo simulador), subidos a Roblox (rbxassetid) para que los
-- vean todos los jugadores. Mientras una imagen carga se ve su emoji.

local ContentProvider = game:GetService("ContentProvider")

local Icons = {}

Icons.Ids = {
	pets = "rbxassetid://73764141862663",
	quests = "rbxassetid://103317099987621",
	cores = "rbxassetid://104226818630026",
	amulets = "rbxassetid://81377610137510",
	rebirth = "rbxassetid://78262713671639",
	rewards = "rbxassetid://104895230690253",
	shop = "rbxassetid://99317821262735",
	-- diamond: sin dibujo propio aún: se ve el emoji 💎 (los diamantes)
	tokens = "rbxassetid://111158193070510",
	money = "rbxassetid://120673758892369", -- fajo de billetes 3D (icono_dinero_3d.png)
	-- Iconos 3D de la barra del menú (diseño "HUD Botones"). Si alguno queda sin ID se usa
	-- el de Fallback.
	pets3d = "rbxassetid://123825778285787", -- icono_mascotas_3d.png (osito)
	rewards3d = "rbxassetid://84826349262356", -- icono_premios_3d.png (regalo azul)
	rebirth3d = "rbxassetid://78946373971553", -- icono_renacer_3d.png (flechas rosa y azul)
	armory3d = "rbxassetid://132273423772998", -- icono_armas_3d.png (espadas cruzadas)
	amulets3d = "rbxassetid://79337029056061", -- icono_amuletos_3d.png (amuleto morado)
	inventory3d = "rbxassetid://124730753609862", -- icono_inventario_3d.png (mochila)
}

-- Icono que se usa mientras uno nuevo no tiene ID.
Icons.Fallback = {
	pets3d = "pets",
	rewards3d = "rewards",
	rebirth3d = "rebirth",
	amulets3d = "amulets",
}

Icons.Emoji = {
	pets = "🐾",
	quests = "📜",
	cores = "✨",
	amulets = "🧿",
	rebirth = "🔄",
	rewards = "🎁",
	shop = "💎",
	diamond = "💎",
	tokens = "🪙",
	money = "💵",
	armory = "⚔️",
	pets3d = "🐻",
	rewards3d = "🎁",
	rebirth3d = "🔄",
	armory3d = "⚔️",
	amulets3d = "🧿",
	inventory3d = "🎒",
}

export type Props = {
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Rotation: number?,
	ZIndex: number?,
	Name: string?,
}

function Icons.image(name: string): string?
	local id = Icons.Ids[name]
	if typeof(id) == "string" and id ~= "" then
		return id
	elseif typeof(id) == "number" and id > 0 then
		return "rbxassetid://" .. tostring(id)
	end
	local fallback = Icons.Fallback[name]
	if fallback then
		return Icons.image(fallback)
	end
	return nil
end

function Icons.has(name: string): boolean
	return Icons.image(name) ~= nil
end

function Icons.make(parent: Instance, name: string, props: Props): Frame
	local zIndex = props.ZIndex or 1
	local holder = Instance.new("Frame")
	holder.Name = props.Name or ("Icon_" .. name)
	holder.BackgroundTransparency = 1
	holder.Size = props.Size
	holder.Position = props.Position or UDim2.new()
	holder.AnchorPoint = props.AnchorPoint or Vector2.zero
	holder.Rotation = props.Rotation or 0
	holder.ZIndex = zIndex

	local image = Icons.image(name)
	local isLocalAsset = typeof(image) == "string" and string.sub(image, 1, 11) == "rbxasset://"

	local emoji = Instance.new("TextLabel")
	emoji.Name = "Emoji"
	emoji.BackgroundTransparency = 1
	emoji.AnchorPoint = Vector2.new(0.5, 0.5)
	emoji.Position = UDim2.fromScale(0.5, 0.5)
	emoji.Size = UDim2.fromScale(0.8, 0.8)
	emoji.Font = Enum.Font.FredokaOne
	emoji.TextScaled = true
	emoji.TextColor3 = Color3.new(1, 1, 1)
	emoji.Text = Icons.Emoji[name] or "?"
	emoji.Visible = not isLocalAsset
	emoji.ZIndex = zIndex
	emoji.Parent = holder

	if image then
		local label = Instance.new("ImageLabel")
		label.Name = "Image"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.ScaleType = Enum.ScaleType.Fit
		label.Image = image
		label.ZIndex = zIndex + 1
		label.Parent = holder
		if not isLocalAsset then
			local function sync()
				emoji.Visible = not label.IsLoaded
			end
			label:GetPropertyChangedSignal("IsLoaded"):Connect(sync)
			sync()
			-- IsLoaded no siempre avisa cuando cambia (y en un panel cerrado la imagen no se
			-- dibuja): si el emoji no se esconde, se ve detrás del dibujo (el 🧿 azul detrás del
			-- amuleto). Por eso se esconde en cuanto la imagen termina de descargarse.
			task.spawn(function()
				pcall(function()
					ContentProvider:PreloadAsync({ label }, function(_, status)
						if status == Enum.AssetFetchStatus.Success then
							emoji.Visible = false
						end
					end)
				end)
			end)
		end
	end

	holder.Parent = parent
	return holder
end

return Icons
