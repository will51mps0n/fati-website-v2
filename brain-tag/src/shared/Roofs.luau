-- Roofs over the rooms of roofed maps (the haunted house). Shared so bots
-- (server) and your screen (client) agree on who can see whom: from outside
-- a room you can't see in, and from inside a room you see only that room.

local Roofs = {}

local cachedFolder: Instance? = nil
local cached: { BasePart } = {}
local dirty = true

-- Every roof on the current map (none on most maps).
function Roofs.all(): { BasePart }
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Roofs")
	if folder ~= cachedFolder then
		cachedFolder = folder
		dirty = true
		if folder then
			folder.ChildAdded:Connect(function()
				dirty = true
			end)
		end
	end
	if dirty then
		dirty = false
		cached = {}
		if folder then
			for _, part in folder:GetChildren() do
				if part:IsA("BasePart") and part.Name == "Roof" then -- not the door panels
					table.insert(cached, part)
				end
			end
		end
	end
	return cached
end

-- The roof over a point, if it's inside a room.
function Roofs.over(position: Vector3): BasePart?
	for _, roof in Roofs.all() do
		local offset = position - roof.Position
		if math.abs(offset.X) <= roof.Size.X / 2 and math.abs(offset.Z) <= roof.Size.Z / 2 then
			return roof
		end
	end
	return nil
end

-- Can someone at `from` see someone at `to`? Yes when both stand under the
-- same roof (or both outdoors), or they're right next to each other.
function Roofs.canSee(from: Vector3, to: Vector3): boolean
	if #Roofs.all() == 0 then
		return true
	end
	local offset = to - from
	if Vector3.new(offset.X, 0, offset.Z).Magnitude <= 5 then
		return true
	end
	return Roofs.over(from) == Roofs.over(to)
end

return Roofs
