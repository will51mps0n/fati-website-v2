-- Swinging doors (maps with swingDoors, like the haunted house). Anyone walks
-- straight through them; on your screen a door swings open away from whoever
-- is passing and falls shut behind them. Shut, it hides the room beyond: it
-- blocks your lantern's light, and bots can't see through it either.

local RunService = game:GetService("RunService")

local DoorController = {}

type Door = {
	part: BasePart,
	closed: CFrame,
	hinge: Vector3,
	horizontal: boolean,
	half: number, -- half the door's length
	angle: number, -- radians, 0 = shut
	attached: { { part: BasePart, offset: CFrame } }, -- the knob swings along
}

local OPEN = math.rad(85)
local SPEED = 7 -- radians per second
local REACH = 4.5 -- how far from the door line someone pushes it open

local doors: { [BasePart]: Door } = {}

local function track(part: Instance)
	if not part:IsA("BasePart") or part.Name ~= "SwingDoor" then
		return
	end
	local horizontal = part:GetAttribute("Horizontal") == true
	local half = (if horizontal then part.Size.X else part.Size.Z) / 2
	local along = if horizontal then Vector3.xAxis else Vector3.zAxis
	local attached = {}
	for _, child in part:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(attached, { part = child, offset = part.CFrame:ToObjectSpace(child.CFrame) })
		end
	end
	doors[part] = {
		part = part,
		closed = part.CFrame,
		hinge = part.Position - along * half,
		horizontal = horizontal,
		half = half,
		angle = 0,
		attached = attached,
	}
	part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(workspace) then
			doors[part] = nil
		end
	end)
end

local function roots(): { BasePart }
	local list = {}
	local function scan(folder: Instance)
		for _, model in folder:GetChildren() do
			if model:IsA("Model") and model:GetAttribute("ParticipantId") then
				local root = model:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					table.insert(list, root)
				end
			end
		end
	end
	scan(workspace)
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		scan(bots)
	end
	return list
end

local function step(dt: number)
	if next(doors) == nil then
		return
	end
	local people = roots()
	for _, door in doors do
		local center = door.closed.Position
		-- Which way should it be open? Away from the nearest person in the doorway.
		local target = 0
		local nearest = math.huge
		for _, root in people do
			local rel = root.Position - center
			local along = if door.horizontal then rel.X else rel.Z
			local across = if door.horizontal then rel.Z else rel.X
			if
				math.abs(along) < door.half + 1.5
				and math.abs(across) < REACH
				and math.abs(across) < nearest
			then
				nearest = math.abs(across)
				-- Turning the free end toward -across: a positive angle moves it
				-- toward -Z (horizontal doors) or +X (vertical doors).
				local away = if door.horizontal
					then (if across > 0 then 1 else -1)
					else (if across > 0 then -1 else 1)
				-- Already open one way while someone is still in it: stay that way.
				if door.angle ~= 0 then
					away = if door.angle > 0 then 1 else -1
				end
				target = away * OPEN
			end
		end
		if door.angle ~= target then
			local delta = target - door.angle
			local stepSize = SPEED * dt
			door.angle = if math.abs(delta) <= stepSize
				then target
				else door.angle + math.sign(delta) * stepSize
			local hinge = CFrame.new(door.hinge)
			local cframe = hinge * CFrame.Angles(0, door.angle, 0) * hinge:Inverse() * door.closed
			door.part.CFrame = cframe
			for _, extra in door.attached do
				extra.part.CFrame = cframe * extra.offset
			end
		end
	end
end

function DoorController.start()
	local map = workspace:WaitForChild("Map")
	local folder = map:WaitForChild("Doors")
	folder.ChildAdded:Connect(function(child)
		task.defer(track, child)
	end)
	for _, child in folder:GetChildren() do
		track(child)
	end
	RunService.RenderStepped:Connect(step)
end

return DoorController
