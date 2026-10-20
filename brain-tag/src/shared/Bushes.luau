-- Bushes hide whoever stands in them. Shared so the server (hidden flags for
-- bots) and your client (see-through canopy, hidden name tags) agree on who
-- is covered. A bush is a model of upright leaf discs in workspace.Map.Bushes.

local Bushes = {}

Bushes.ATTRIBUTE = "InBush" -- set on characters by the server
Bushes.CLOAK_ATTRIBUTE = "CloakedUntil" -- server time the Magic Cloak wears off

local cachedFolder: Instance? = nil
local cached: { BasePart } = {}
local dirty = true

-- Every leaf disc on the current map. Re-collected when the map is rebuilt.
function Bushes.leaves(): { BasePart }
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Bushes")
	if folder ~= cachedFolder then
		cachedFolder = folder
		dirty = true
		if folder then
			folder.DescendantAdded:Connect(function()
				dirty = true
			end)
		end
	end
	if dirty then
		dirty = false
		cached = {}
		if folder then
			for _, part in folder:GetDescendants() do
				if part.Name == "Leaves" and part:IsA("BasePart") then
					table.insert(cached, part)
				end
			end
		end
	end
	return cached
end

-- The bush model covering a position, if any. Leaf discs are upright
-- cylinders, so their diameter is Size.Y.
function Bushes.coverAt(position: Vector3): Model?
	for _, part in Bushes.leaves() do
		local center = part.Position
		local radius = part.Size.Y / 2 - 0.4
		local dx, dz = position.X - center.X, position.Z - center.Z
		if dx * dx + dz * dz <= radius * radius then
			local model = part.Parent
			return if model and model:IsA("Model") then model else nil
		end
	end
	return nil
end

return Bushes
