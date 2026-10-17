local fails = 0
local counts = {}
for _, name in names do
	local group, side = poseGroup(name)
	counts[group] = (counts[group] or 0) + 1
	local base = name:match("^(%a+)")
	local expect = if base == "Root" then "Static" elseif ARM_PARTS[base] then "Arm" elseif LEG_PARTS[base] then "Leg" else "Body"
	local sideOk = (group ~= "Arm" and group ~= "Leg") or side == tonumber(name:match("(%-?1)$"))
	if group ~= expect or not sideOk then
		fails += 1
		print("FALLO", name, group, side)
	end
end
print(("piezas: %d  (Body %d, Arm %d, Leg %d, Static %d)"):format(#names, counts.Body or 0, counts.Arm or 0, counts.Leg or 0, counts.Static or 0))
print(if fails == 0 then "TODO OK" else fails .. " FALLOS")
