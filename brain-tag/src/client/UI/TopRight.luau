-- Top-right: ping/fps, "N Survivors" (white) over "N Zombies" (red), and a
-- collapsible top-10 leaderboard with your own name in lime green.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ClientState = require(script.Parent.Parent.ClientState)
local UIKit = require(script.Parent.UIKit)
local Util = require(game:GetService("ReplicatedStorage").Shared.Util)

local TopRight = {}

local ROWS = 10
local HUMAN_DOT = Color3.fromHex("F2C79A")
local ZOMBIE_DOT = Color3.fromHex("7BC043")

local showStats = true

function TopRight.setStatsVisible(on: boolean)
	showStats = on
end

function TopRight.statsVisible(): boolean
	return showStats
end

function TopRight.build(parent: Instance): () -> ()
	local column = UIKit.new("Frame", {
		Name = "TopRight",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 6),
		Size = UDim2.fromOffset(240, 400),
		BackgroundTransparency = 1,
		Parent = parent,
	}, { UIKit.list(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Right) })

	local stats = UIKit.label({
		Name = "Stats",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(240, 16),
		TextSize = 13,
		Font = UIKit.FONT,
		TextColor3 = UIKit.MUTED,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = column,
	})
	local survivors = UIKit.label({
		Name = "Survivors",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(240, 32),
		TextSize = 30,
		Font = UIKit.HEAVY,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = column,
	})
	UIKit.textStroke(1.5).Parent = survivors
	local zombies = UIKit.label({
		Name = "Zombies",
		LayoutOrder = 3,
		Size = UDim2.fromOffset(240, 32),
		TextSize = 30,
		Font = UIKit.HEAVY,
		TextColor3 = UIKit.RED,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = column,
	})
	UIKit.textStroke(1.5).Parent = zombies

	local expanded = true
	local toggle = UIKit.button({
		Name = "LeaderboardToggle",
		LayoutOrder = 4,
		Size = UDim2.fromOffset(150, 26),
		Text = "^  Leaderboard",
		TextSize = 16,
		BackgroundColor3 = UIKit.PANEL,
		BackgroundTransparency = UIKit.PANEL_TRANSPARENCY,
		Parent = column,
	})
	local board = UIKit.panel({
		Name = "Leaderboard",
		LayoutOrder = 5,
		Size = UDim2.fromOffset(220, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = column,
	}, { UIKit.padding(8, 6), UIKit.list(Enum.FillDirection.Vertical, 2) })

	toggle.Activated:Connect(function()
		expanded = not expanded
		board.Visible = expanded
		toggle.Text = (if expanded then "^" else "v") .. "  Leaderboard"
	end)

	local rows = {}
	for i = 1, ROWS do
		local row = UIKit.new("Frame", {
			Name = "Row" .. i,
			LayoutOrder = i,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 20),
			Visible = false,
			Parent = board,
		})
		local dot = UIKit.new("Frame", {
			Name = "Dot",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(8, 8),
			BorderSizePixel = 0,
			Parent = row,
		}, { UIKit.corner(4) })
		local name = UIKit.label({
			Name = "Name",
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -84, 1, 0),
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})
		local score = UIKit.label({
			Name = "Score",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 70, 1, 0),
			TextSize = 15,
			Font = UIKit.FONT,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})
		rows[i] = { frame = row, dot = dot, name = name, score = score }
	end

	local frames, fps = 0, 60
	local windowStart = os.clock()
	RunService.RenderStepped:Connect(function()
		frames += 1
		local now = os.clock()
		if now - windowStart >= 1 then
			fps = frames / (now - windowStart)
			frames, windowStart = 0, now
		end
	end)

	return function()
		stats.Visible = showStats
		if showStats then
			local ping = math.floor(Players.LocalPlayer:GetNetworkPing() * 1000)
			stats.Text = string.format("ping %d ms  |  %d fps", ping, math.floor(fps + 0.5))
		end
		local s = ClientState.attr("Survivors") or 0
		local z = ClientState.attr("Zombies") or 0
		survivors.Text = string.format("%d %s", s, if s == 1 then "Survivor" else "Survivors")
		zombies.Text = string.format("%d %s", z, if z == 1 then "Zombie" else "Zombies")

		local list = ClientState.rows()
		for i, row in rows do
			local entry = list[i]
			row.frame.Visible = entry ~= nil
			if entry then
				row.name.Text = entry.name
				row.name.TextColor3 = if entry.isMe
					then UIKit.LIME
					elseif entry.vip then UIKit.GOLD
					else UIKit.WHITE
				row.score.Text = Util.commas(entry.score)
				row.score.TextColor3 = if entry.isMe then UIKit.LIME else UIKit.WHITE
				row.dot.BackgroundColor3 = if entry.team == "Zombie" then ZOMBIE_DOT else HUMAN_DOT
			end
		end
	end
end

return TopRight
