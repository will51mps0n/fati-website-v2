-- Read-only view of the replicated game state for client code: the round
-- phase and timer, and every participant's public info.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = {}

local player = Players.LocalPlayer
local folder = ReplicatedStorage:WaitForChild("BrainTagState") :: Folder
local participants = folder:WaitForChild("Participants") :: Folder

ClientState.folder = folder
ClientState.participants = participants

function ClientState.phase(): string
	return (folder:GetAttribute("Phase") :: string?) or "Waiting"
end

function ClientState.secondsLeft(): number
	local endsAt = folder:GetAttribute("PhaseEndsAt")
	if typeof(endsAt) ~= "number" then
		return 0
	end
	return math.max(0, endsAt - workspace:GetServerTimeNow())
end

function ClientState.attr(name: string): any
	return folder:GetAttribute(name)
end

function ClientState.myId(): string
	return "P" .. player.UserId
end

-- This player's replicated entry (nil until the server finished loading them).
function ClientState.me(): Configuration?
	return participants:FindFirstChild(ClientState.myId()) :: Configuration?
end

function ClientState.my(name: string): any
	local me = ClientState.me()
	return me and me:GetAttribute(name)
end

function ClientState.isZombie(): boolean
	return ClientState.my("Team") == "Zombie"
end

function ClientState.myCharacter(): (Model?, BasePart?, Humanoid?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return character, root, humanoid
end

function ClientState.owns(listAttr: string, key: string): boolean
	local raw = ClientState.my(listAttr)
	if typeof(raw) ~= "string" then
		return false
	end
	for entry in string.gmatch(raw, "[^,]+") do
		if entry == key then
			return true
		end
	end
	return false
end

export type Row = {
	id: string,
	name: string,
	score: number,
	team: string,
	isMe: boolean,
	isBot: boolean,
	vip: boolean,
}

function ClientState.rows(): { Row }
	local rows = {}
	local myId = ClientState.myId()
	for _, entry in participants:GetChildren() do
		table.insert(rows, {
			id = entry.Name,
			name = (entry:GetAttribute("DisplayName") :: string?) or entry.Name,
			score = (entry:GetAttribute("Score") :: number?) or 0,
			team = (entry:GetAttribute("Team") :: string?) or "Human",
			isMe = entry.Name == myId,
			isBot = entry:GetAttribute("IsBot") == true,
			vip = entry:GetAttribute("VIP") == true,
		})
	end
	table.sort(rows, function(a, b)
		if a.score == b.score then
			return a.name < b.name
		end
		return a.score > b.score
	end)
	return rows
end

return ClientState
