-- Banana peels: dropped by humans, slippery for zombies. A zombie that steps
-- on one slips: a shove in the way they were walking and a long daze.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Announcer = require(script.Parent.Announcer)
local Combat = require(script.Parent.Combat)
local Items = require(ReplicatedStorage.Shared.Items)
local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local Parts = require(ReplicatedStorage.Shared.Parts)
local Participants = require(script.Parent.Participants)
local Util = require(ReplicatedStorage.Shared.Util)

local Traps = {}

type Trap = { model: Model, position: Vector3, item: Items.Item }

local traps: { Trap } = {}
local folder: Folder
local MAX_TRAPS = 30

local function buildPeel(at: Vector3, spin: number): Model
	local model = Instance.new("Model")
	model.Name = "BananaPeel"
	local y = MapLayout.HEIGHTS.Floor + 0.12
	local center = CFrame.new(at.X, y, at.Z) * CFrame.Angles(0, spin, 0)
	for i = 0, 2 do
		local arm = center * CFrame.Angles(0, i * math.pi * 2 / 3, 0) * CFrame.new(0, 0, -0.6)
		Parts.make({
			name = "Peel",
			size = Vector3.new(0.55, 0.12, 1.3),
			cframe = arm,
			color = "F7DC6F",
			canCollide = false,
			canQuery = false,
			parent = model,
		})
		Parts.make({
			name = "PeelInside",
			size = Vector3.new(0.35, 0.13, 1.0),
			cframe = arm * CFrame.new(0, 0.005, 0.05),
			color = "FFF6C7",
			canCollide = false,
			canQuery = false,
			parent = model,
		})
	end
	Parts.disc("Stem", center.Position + Vector3.new(0, 0.05, 0), 0.5, 0.2, "8B5A2B", model).CanCollide =
		false
	return model
end

function Traps.place(position: Vector3, item: Items.Item)
	if #traps >= MAX_TRAPS then
		local oldest = table.remove(traps, 1)
		if oldest then
			oldest.model:Destroy()
		end
	end
	local model = buildPeel(position, math.random() * math.pi * 2)
	model.Parent = folder
	table.insert(traps, { model = model, position = Vector3.new(position.X, 0, position.Z), item = item })
end

function Traps.clear()
	for _, trap in traps do
		trap.model:Destroy()
	end
	table.clear(traps)
end

local function step()
	if #traps == 0 then
		return
	end
	for _, zombie in Participants.onTeam("Zombie") do
		local root, humanoid = Participants.body(zombie)
		if root and humanoid then
			for i = #traps, 1, -1 do
				local trap = traps[i]
				if Util.flatDistance(root.Position, trap.position) <= 1.4 + root.Size.X / 2 then
					local move = Util.flatUnit(humanoid.MoveDirection)
						or Util.flatUnit(root.CFrame.LookVector)
						or Vector3.xAxis
					Combat.knockback(zombie, move * (trap.item.knockback or 45), trap.item.stun or 1.2)
					Announcer.fx("Slip", { position = trap.position, character = zombie.character })
					trap.model:Destroy()
					table.remove(traps, i)
				end
			end
		end
	end
end

function Traps.init()
	folder = workspace:WaitForChild("Traps") :: Folder
	RunService.Heartbeat:Connect(step)
end

return Traps
