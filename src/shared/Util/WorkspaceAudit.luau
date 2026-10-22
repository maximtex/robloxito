-- Diagnóstico de solo lectura (SOLO en Roblox Studio): busca en Workspace objetos que el
-- código del juego no crea y que suelen explicar "un modelo enorme" o "una textura rara":
-- piezas gigantes, mallas o texturas con recursos externos y scripts sueltos (modelos de
-- la caja de herramientas). Solo los lista en la Salida con su ruta completa: NO borra ni
-- modifica nada, para que se pueda decidir a mano si son contenido legítimo.
-- Se ejecuta una vez en el servidor y otra en el cliente (lo creado en local solo se ve ahí).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local StudFloor = require(script.Parent.StudFloor)

local WorkspaceAudit = {}

local HUGE_SIZE = 120 -- ninguna pieza del juego mide tanto
-- Creado por el propio proyecto (default.project.json); se informa aparte, no como hallazgo.
local PROJECT_BASEPLATE = "Baseplate"

local function report(where: string, findings: { string })
	if #findings == 0 then
		print(("[WorkspaceAudit:%s] Sin objetos sospechosos en Workspace."):format(where))
		return
	end
	warn(("[WorkspaceAudit:%s] %d objeto(s) que el código del juego no crea (revísalos a mano, no se ha borrado nada):"):format(where, #findings))
	for index = 1, math.min(#findings, 40) do
		warn("  - " .. findings[index])
	end
	if #findings > 40 then
		warn(("  ... y %d más"):format(#findings - 40))
	end
end

function WorkspaceAudit.run(where: string)
	if not RunService:IsStudio() then
		return
	end
	-- Los personajes llevan su avatar (mallas, caras, scripts Animate): no se revisan.
	local characters = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(characters, player.Character)
		end
	end
	local function inCharacter(item: Instance): boolean
		for _, character in characters do
			if item == character or item:IsDescendantOf(character) then
				return true
			end
		end
		return false
	end

	-- Modelos del mapa colocados por MapAssets (Creator Store, guardados en el place):
	-- llevan el atributo "MapAsset" y son contenido legítimo.
	local function fromMapAssets(item: Instance): boolean
		local model = item:FindFirstAncestorWhichIsA("Model")
		return model ~= nil and model:GetAttribute("MapAsset") ~= nil
	end

	local findings = {}
	local skippedAssets = 0
	for _, item in Workspace:GetDescendants() do
		if item:IsA("Terrain") or item:IsA("Camera") or inCharacter(item) then
			continue
		end
		if (item:IsA("MeshPart") or item:IsA("SurfaceAppearance") or item:IsA("SpecialMesh")) and fromMapAssets(item) then
			skippedAssets += 1
			continue
		end
		if item:IsA("BasePart") then
			local size = item.Size
			local largest = math.max(size.X, size.Y, size.Z)
			-- Los caminos del suelo de bloques (StudWorld) se juntan en tramos largos a propósito
			local floorPiece = item.Parent ~= nil and item.Parent.Name == StudFloor.FolderName
			if largest > HUGE_SIZE and not (item.Name == PROJECT_BASEPLATE and item.Parent == Workspace) and not floorPiece then
				table.insert(findings, ("Pieza enorme %s (%s) tamaño %s en %s"):format(item:GetFullName(), item.ClassName, tostring(size), tostring(item.Position)))
			end
			if item:IsA("MeshPart") and item.MeshId ~= "" then
				table.insert(findings, ("MeshPart con malla externa %s (%s)"):format(item:GetFullName(), item.MeshId))
			end
		elseif item:IsA("SpecialMesh") and (item.MeshId ~= "" or item.TextureId ~= "") then
			table.insert(findings, ("Malla externa %s (malla %s, textura %s, escala %s)"):format(item:GetFullName(), item.MeshId, item.TextureId, tostring(item.Scale)))
		elseif
			(item:IsA("Decal") or item:IsA("Texture"))
			and not (item.Parent and item.Parent:IsA("SpawnLocation"))
			-- Las texturas del suelo de bloques (StudWorld) las pone el juego en cada bloque
			and not (item.Parent and item.Parent.Parent and item.Parent.Parent.Name == StudFloor.FolderName)
		then
			table.insert(findings, ("%s %s (%s)"):format(item.ClassName, item:GetFullName(), item.Texture))
		elseif item:IsA("SurfaceAppearance") then
			table.insert(findings, ("SurfaceAppearance %s"):format(item:GetFullName()))
		elseif item:IsA("Script") or item:IsA("LocalScript") then
			table.insert(findings, ("Script suelto %s"):format(item:GetFullName()))
		end
	end
	if skippedAssets > 0 then
		print(("[WorkspaceAudit:%s] %d pieza(s) de los modelos del mapa (MapAssets) no se revisan."):format(where, skippedAssets))
	end
	report(where, findings)
end

return WorkspaceAudit
