-- Flags characters standing in a bush, or wearing the Magic Cloak (character
-- attribute "InBush"), so bots can't see them. Clients work out the visual side (name tags, see-through
-- canopy) themselves from the same shared geometry.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bushes = require(ReplicatedStorage.Shared.Bushes)
local Config = require(ReplicatedStorage.Shared.Config)
local Participants = require(script.Parent.Participants)
local Util = require(ReplicatedStorage.Shared.Util)

type Participant = Participants.Participant

local BushService = {}

local INTERVAL = 0.1

function BushService.hidden(p: Participant): boolean
	local character = p.character
	return character ~= nil and character:GetAttribute(Bushes.ATTRIBUTE) == true
end

-- Whether someone at `from` can spot `p`: always, unless `p` is in a bush
-- and the looker is farther than the reveal distance.
function BushService.visibleFrom(p: Participant, from: Vector3): boolean
	if not BushService.hidden(p) then
		return true
	end
	local root = Participants.body(p)
	return root ~= nil and Util.flatDistance(root.Position, from) <= Config.BUSH_REVEAL_DISTANCE
end

function BushService.init()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < INTERVAL then
			return
		end
		elapsed = 0
		for _, p in Participants.all() do
			local character = p.character
			if character then
				local root = Participants.body(p)
				local cloak = character:GetAttribute(Bushes.CLOAK_ATTRIBUTE)
				local cloaked = typeof(cloak) == "number" and cloak > workspace:GetServerTimeNow()
				local hidden = root ~= nil and (cloaked or Bushes.coverAt(root.Position) ~= nil)
				if character:GetAttribute(Bushes.ATTRIBUTE) ~= hidden then
					character:SetAttribute(Bushes.ATTRIBUTE, hidden)
				end
			end
		end
	end)
end

return BushService
