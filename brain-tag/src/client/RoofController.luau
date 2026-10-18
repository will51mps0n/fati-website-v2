-- Roofed maps (the haunted house): every room is covered by a pitch black
-- roof, so from outside you can't see who or what is in there. The roof of
-- the room you stand in disappears on your screen, so you see that room
-- only. Doorways are open: walk straight in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Roofs = require(ReplicatedStorage.Shared.Roofs)

local RoofController = {}

local player = Players.LocalPlayer
local open: BasePart? = nil

local function step()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local mine = if root then Roofs.over(root.Position) else nil
	if mine == open then
		return
	end
	if open and open.Parent then
		open.LocalTransparencyModifier = 0
	end
	if mine then
		mine.LocalTransparencyModifier = 1
	end
	open = mine
end

function RoofController.start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.05 then
			elapsed = 0
			step()
		end
	end)
end

return RoofController
