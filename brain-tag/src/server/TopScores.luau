-- All-time top 10 (across servers) for the trophy panel, refreshed every
-- couple of minutes from the OrderedDataStore that DataService updates.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)

local TopScores = {}

local names: { [number]: string } = {}

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and name then
		names[userId] = name
		return name
	end
	return "Player " .. userId
end

local function refresh()
	local rows = {}
	for _, entry in DataService.topScores(10) do
		table.insert(rows, { name = nameOf(entry.userId), score = entry.score })
	end
	local state = ReplicatedStorage:FindFirstChild("BrainTagState")
	if state then
		state:SetAttribute("TopScores", HttpService:JSONEncode(rows))
	end
end

function TopScores.start()
	task.spawn(function()
		while true do
			if DataService.isAvailable() then
				refresh()
			end
			task.wait(Config.TOP_SCORES_REFRESH_SECONDS)
		end
	end)
end

return TopScores
