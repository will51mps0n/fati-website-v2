-- Hiding in bushes, on your screen: the bush you stand in fades so you can
-- see yourself (and anyone hiding with you), and the name tags of players
-- hiding in other bushes disappear. On dark maps, name tags also show only
-- for people close enough to see (DarknessController), and on roofed maps
-- only for people in the same room as you (Roofs).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bushes = require(ReplicatedStorage.Shared.Bushes)
local Config = require(ReplicatedStorage.Shared.Config)
local DarknessController = require(script.Parent.DarknessController)
local Roofs = require(ReplicatedStorage.Shared.Roofs)

local BushController = {}

local player = Players.LocalPlayer
local INTERVAL = 0.1

local faded: Model? = nil

local function fade(bush: Model?, amount: number)
	if not bush then
		return
	end
	for _, part in bush:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = amount
		end
	end
end

local function characters(): { Instance }
	local list = workspace:GetChildren()
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		for _, bot in bots:GetChildren() do
			table.insert(list, bot)
		end
	end
	return list
end

local function rootOf(model: Instance): BasePart?
	return model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function step()
	local me = player.Character
	local myRoot = me and rootOf(me)
	local mine = if myRoot then Bushes.coverAt(myRoot.Position) else nil
	if mine ~= faded then
		fade(faded, 0)
		fade(mine, Config.BUSH_SEE_THROUGH)
		faded = mine
	end

	for _, model in characters() do
		if model:IsA("Model") and model:GetAttribute("ParticipantId") and model ~= me then
			local head = model:FindFirstChild("Head")
			local tag = head and head:FindFirstChild("NameTag")
			local root = rootOf(model)
			if tag and tag:IsA("BillboardGui") and root then
				local theirs = Bushes.coverAt(root.Position)
				local show = (theirs == nil or theirs == mine)
					and DarknessController.sees(root.Position)
					and (myRoot == nil or Roofs.canSee(myRoot.Position, root.Position))
				if tag.Enabled ~= show then
					tag.Enabled = show
				end
			end
		end
	end
end

function BushController.start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < INTERVAL then
			return
		end
		elapsed = 0
		local ok, err = pcall(function()
			step()
			return true
		end)
		if not ok then
			warn("[Bushes] " .. tostring(err))
		end
	end)
end

return BushController
