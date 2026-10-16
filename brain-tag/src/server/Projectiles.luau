-- Potato gun shots, simulated on the server with sphere casts so hits are
-- decided in one place. Potatoes pass through humans and stop at the first
-- zombie, wall, bush or piece of furniture.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Announcer = require(script.Parent.Announcer)
local Combat = require(script.Parent.Combat)
local FurnitureService = require(script.Parent.FurnitureService)
local Items = require(ReplicatedStorage.Shared.Items)
local Parts = require(ReplicatedStorage.Shared.Parts)
local Participants = require(script.Parent.Participants)

type Participant = Participants.Participant

local Projectiles = {}

type Shot = {
	part: Part,
	position: Vector3,
	direction: Vector3,
	traveled: number,
	item: Items.Item,
	params: RaycastParams,
	ignored: { Instance },
}

local shots: { Shot } = {}
local folder: Folder

local function finish(shot: Shot, at: Vector3?)
	shot.part:Destroy()
	local index = table.find(shots, shot)
	if index then
		table.remove(shots, index)
	end
	if at then
		Announcer.fx("Splat", { position = at })
	end
end

local function step(dt: number)
	for i = #shots, 1, -1 do
		local shot = shots[i]
		local item = shot.item
		local distance = (item.projectileSpeed or 90) * dt
		local radius = item.projectileRadius or 0.6
		local done = false
		for _ = 1, 4 do
			local result = workspace:Spherecast(shot.position, radius, shot.direction * distance, shot.params)
			if not result then
				break
			end
			local target = Participants.fromPart(result.Instance)
			if target and target.team == "Human" and target.character then
				-- Fly through teammates.
				table.insert(shot.ignored, target.character)
				shot.params.FilterDescendantsInstances = shot.ignored
				continue
			end
			if target and target.team == "Zombie" then
				Combat.knockback(target, shot.direction * (item.knockback or 50), item.stun or 0.3)
			elseif
				result.Instance:IsA("BasePart") and FurnitureService.weightOf(result.Instance) == "Light"
			then
				FurnitureService.addPush(result.Instance, shot.direction * 10, result.Position)
			end
			finish(shot, result.Position)
			done = true
			break
		end
		if not done then
			shot.position += shot.direction * distance
			shot.traveled += distance
			if shot.traveled >= (item.projectileRange or 100) then
				finish(shot, nil)
			else
				shot.part.CFrame = CFrame.new(shot.position)
			end
		end
	end
end

function Projectiles.fire(shooter: Participant, item: Items.Item, aim: Vector3)
	local root = Participants.body(shooter)
	if not root or not shooter.character then
		return
	end
	local radius = item.projectileRadius or 0.6
	local origin = root.Position + aim * (root.Size.X / 2 + radius + 0.4)
	local part = Parts.make({
		name = "Potato",
		shape = Enum.PartType.Ball,
		size = Vector3.one * radius * 2,
		cframe = CFrame.new(origin),
		color = if item.isRare then "B98A4E" else "C9A66B",
		canCollide = false,
		canQuery = false,
		parent = folder,
	})
	local ignored: { Instance } = {
		shooter.character,
		folder,
		workspace:WaitForChild("GroundItems"),
		workspace:WaitForChild("Effects"),
	}
	local map = workspace:WaitForChild("Map")
	for _, name in { "Ground", "Road", "Floors", "Boundary" } do
		local child = map:FindFirstChild(name)
		if child then
			table.insert(ignored, child)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignored
	table.insert(shots, {
		part = part,
		position = origin,
		direction = aim,
		traveled = 0,
		item = item,
		params = params,
		ignored = ignored,
	})
end

function Projectiles.clear()
	for i = #shots, 1, -1 do
		finish(shots[i], nil)
	end
end

function Projectiles.init()
	folder = workspace:WaitForChild("Projectiles") :: Folder
	RunService.Heartbeat:Connect(step)
end

return Projectiles
