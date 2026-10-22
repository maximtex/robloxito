--!strict
-- Geometría de pedestales-huevos.glb (diseño de Claude Design) generada a partir del archivo:
-- el altar central y los cuatro pedestales (Común, No común, Raro y Arcoíris). Escala: 1 m
-- del diseño = 4 studs. Cada pieza va en el marco de su pedestal (suelo en Y = 0, frente
-- hacia -Z) y la construye EggStandService con GlbParts.
-- { Nombre, Forma, Material, Color, Reflectance, Tamaño, CFrame, Extra? }
local EggGardenData = {}

-- Altura de la cara de arriba de cada pieza (donde se apoya el huevo o la mascota)
EggGardenData.Top = {
	Altar = 1.960,
	Comun = 1.758,
	NoComun = 1.758,
	Raro = 1.758,
	Arcoiris = 1.758,
}

EggGardenData.Altar = {
	{ "tier1", "Octagon", Enum.Material.SmoothPlastic, Color3.fromRGB(39, 48, 94), 0, Vector3.new(11.589, 0.784, 11.589), CFrame.new(0.000, 0.392, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "tier1_gold", "Octagon", Enum.Material.SmoothPlastic, Color3.fromRGB(242, 185, 40), 0.06, Vector3.new(11.838, 0.134, 11.838), CFrame.new(0.000, 0.851, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "tier2", "Octagon", Enum.Material.SmoothPlastic, Color3.fromRGB(64, 51, 138), 0, Vector3.new(9.313, 0.616, 9.313), CFrame.new(0.000, 1.226, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "tier2_glow", "Octagon", Enum.Material.Neon, Color3.fromRGB(63, 240, 224), 0, Vector3.new(9.478, 0.134, 9.478), CFrame.new(0.000, 1.187, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "tier2_gold", "Octagon", Enum.Material.SmoothPlastic, Color3.fromRGB(242, 185, 40), 0.06, Vector3.new(9.623, 0.134, 9.623), CFrame.new(0.000, 1.602, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "rune_pad", "Cylinder", Enum.Material.Neon, Color3.fromRGB(122, 58, 224), 0, Vector3.new(8.064, 0.179, 8.064), CFrame.new(0.000, 1.758, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "rune_ring_outer", "Ring", Enum.Material.SmoothPlastic, Color3.fromRGB(242, 185, 40), 0.06, Vector3.new(6.922, 0.202, 6.922), CFrame.new(0.000, 1.859, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000), { Inner = 6.518 } },
	{ "rune_ring_inner", "Ring", Enum.Material.SmoothPlastic, Color3.fromRGB(242, 185, 40), 0.06, Vector3.new(3.965, 0.157, 3.965), CFrame.new(0.000, 1.859, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000), { Inner = 3.651 } },
	{ "front_step", "Block", Enum.Material.SmoothPlastic, Color3.fromRGB(64, 51, 138), 0, Vector3.new(3.584, 0.392, 1.120), CFrame.new(0.000, 0.196, -6.272, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "front_step_gold", "Block", Enum.Material.SmoothPlastic, Color3.fromRGB(242, 185, 40), 0.06, Vector3.new(3.696, 0.090, 1.187), CFrame.new(0.000, 0.437, -6.272, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
}

EggGardenData.Comun = {
	{ "plinth", "Octagon", Enum.Material.SmoothPlastic, Color3.fromRGB(29, 58, 114), 0, Vector3.new(6.002, 0.560, 6.002), CFrame.new(0.000, 0.280, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "glow_band", "Octagon", Enum.Material.Neon, Color3.fromRGB(70, 214, 255), 0, Vector3.new(5.753, 0.157, 5.753), CFrame.new(0.000, 0.638, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "body", "Octagon", Enum.Material.SmoothPlastic, Color3.fromRGB(47, 95, 176), 0, Vector3.new(5.277, 0.672, 5.277), CFrame.new(0.000, 1.053, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "gold_lip", "Octagon", Enum.Material.SmoothPlastic, Color3.fromRGB(242, 185, 40), 0.06, Vector3.new(5.546, 0.134, 5.546), CFrame.new(0.000, 1.456, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "top_pad", "Cylinder", Enum.Material.SmoothPlastic, Color3.fromRGB(47, 95, 176), 0, Vector3.new(4.928, 0.112, 4.928), CFrame.new(0.000, 1.579, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "glow_pad", "Cylinder", Enum.Material.Neon, Color3.fromRGB(70, 214, 255), 0, Vector3.new(3.920, 0.067, 3.920), CFrame.new(0.000, 1.669, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "glow_pad_rim", "Ring", Enum.Material.SmoothPlastic, Color3.fromRGB(242, 185, 40), 0.06, Vector3.new(4.189, 0.157, 4.189), CFrame.new(0.000, 1.680, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000), { Inner = 3.875 } },
}

EggGardenData.NoComun = {
	{ "plinth", "Octagon", Enum.Material.SmoothPlastic, Color3.fromRGB(26, 94, 56), 0, Vector3.new(6.002, 0.560, 6.002), CFrame.new(0.000, 0.280, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "glow_band", "Octagon", Enum.Material.Neon, Color3.fromRGB(108, 255, 142), 0, Vector3.new(5.753, 0.157, 5.753), CFrame.new(0.000, 0.638, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "body", "Octagon", Enum.Material.SmoothPlastic, Color3.fromRGB(44, 154, 90), 0, Vector3.new(5.277, 0.672, 5.277), CFrame.new(0.000, 1.053, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "gold_lip", "Octagon", Enum.Material.SmoothPlastic, Color3.fromRGB(242, 185, 40), 0.06, Vector3.new(5.546, 0.134, 5.546), CFrame.new(0.000, 1.456, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "top_pad", "Cylinder", Enum.Material.SmoothPlastic, Color3.fromRGB(44, 154, 90), 0, Vector3.new(4.928, 0.112, 4.928), CFrame.new(0.000, 1.579, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "glow_pad", "Cylinder", Enum.Material.Neon, Color3.fromRGB(108, 255, 142), 0, Vector3.new(3.920, 0.067, 3.920), CFrame.new(0.000, 1.669, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "glow_pad_rim", "Ring", Enum.Material.SmoothPlastic, Color3.fromRGB(242, 185, 40), 0.06, Vector3.new(4.189, 0.157, 4.189), CFrame.new(0.000, 1.680, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000), { Inner = 3.875 } },
}

EggGardenData.Raro = {
	{ "plinth", "Octagon", Enum.Material.SmoothPlastic, Color3.fromRGB(19, 80, 106), 0, Vector3.new(6.002, 0.560, 6.002), CFrame.new(0.000, 0.280, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "glow_band", "Octagon", Enum.Material.Neon, Color3.fromRGB(95, 244, 255), 0, Vector3.new(5.753, 0.157, 5.753), CFrame.new(0.000, 0.638, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "body", "Octagon", Enum.Material.SmoothPlastic, Color3.fromRGB(31, 134, 168), 0, Vector3.new(5.277, 0.672, 5.277), CFrame.new(0.000, 1.053, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "gold_lip", "Octagon", Enum.Material.SmoothPlastic, Color3.fromRGB(242, 185, 40), 0.06, Vector3.new(5.546, 0.134, 5.546), CFrame.new(0.000, 1.456, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "top_pad", "Cylinder", Enum.Material.SmoothPlastic, Color3.fromRGB(31, 134, 168), 0, Vector3.new(4.928, 0.112, 4.928), CFrame.new(0.000, 1.579, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "glow_pad", "Cylinder", Enum.Material.Neon, Color3.fromRGB(95, 244, 255), 0, Vector3.new(3.920, 0.067, 3.920), CFrame.new(0.000, 1.669, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "glow_pad_rim", "Ring", Enum.Material.SmoothPlastic, Color3.fromRGB(242, 185, 40), 0.06, Vector3.new(4.189, 0.157, 4.189), CFrame.new(0.000, 1.680, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000), { Inner = 3.875 } },
}

EggGardenData.Arcoiris = {
	{ "plinth", "Octagon", Enum.Material.SmoothPlastic, Color3.fromRGB(156, 36, 96), 0, Vector3.new(6.002, 0.560, 6.002), CFrame.new(0.000, 0.280, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "glow_band", "Octagon", Enum.Material.Neon, Color3.fromRGB(255, 138, 216), 0, Vector3.new(5.753, 0.157, 5.753), CFrame.new(0.000, 0.638, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "body", "Octagon", Enum.Material.SmoothPlastic, Color3.fromRGB(232, 64, 138), 0, Vector3.new(5.277, 0.672, 5.277), CFrame.new(0.000, 1.053, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "gold_lip", "Octagon", Enum.Material.SmoothPlastic, Color3.fromRGB(242, 185, 40), 0.06, Vector3.new(5.546, 0.134, 5.546), CFrame.new(0.000, 1.456, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "top_pad", "Cylinder", Enum.Material.SmoothPlastic, Color3.fromRGB(232, 64, 138), 0, Vector3.new(4.928, 0.112, 4.928), CFrame.new(0.000, 1.579, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "glow_pad", "Cylinder", Enum.Material.Neon, Color3.fromRGB(255, 138, 216), 0, Vector3.new(3.920, 0.067, 3.920), CFrame.new(0.000, 1.669, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000) },
	{ "glow_pad_rim", "Ring", Enum.Material.SmoothPlastic, Color3.fromRGB(242, 185, 40), 0.06, Vector3.new(4.189, 0.157, 4.189), CFrame.new(0.000, 1.680, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000), { Inner = 3.875 } },
}

return EggGardenData
