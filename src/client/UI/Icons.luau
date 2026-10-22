-- Iconos dibujados del HUD (estilo simulador). Cargados directamente desde las texturas
-- locales instaladas en rbxasset://textures/hud/<name>.png (o AssetId numérico si se sube).

local Icons = {}

Icons.Ids = {
	pets = "rbxasset://textures/hud/pets.png",
	quests = "rbxasset://textures/hud/quests.png",
	cores = "rbxasset://textures/hud/cores.png",
	amulets = "rbxasset://textures/hud/amulets.png",
	rebirth = "rbxasset://textures/hud/rebirth.png",
	rewards = "rbxasset://textures/hud/rewards.png",
	shop = "rbxasset://textures/hud/shop.png",
	energy = "rbxasset://textures/hud/energy.png",
	tokens = "rbxasset://textures/hud/tokens.png",
}

Icons.Emoji = {
	pets = "🐾",
	quests = "📜",
	cores = "✨",
	amulets = "🧿",
	rebirth = "🔄",
	rewards = "🎁",
	shop = "💎",
	energy = "⚡",
	tokens = "🪙",
	money = "💰", -- sin textura: siempre el emoji
	armory = "⚔️",
}

export type Props = {
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Rotation: number?,
	ZIndex: number?,
	Name: string?,
}

function Icons.has(name: string): boolean
	local id = Icons.Ids[name]
	if typeof(id) == "string" and id ~= "" then
		return true
	end
	return typeof(id) == "number" and id > 0
end

function Icons.image(name: string): string?
	local id = Icons.Ids[name]
	if typeof(id) == "string" and id ~= "" then
		return id
	elseif typeof(id) == "number" and id > 0 then
		return "rbxassetid://" .. tostring(id)
	end
	return nil
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
		end
	end

	holder.Parent = parent
	return holder
end

return Icons
