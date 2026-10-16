-- Bottom-right: "Score" and "Speed Multiplier" (plus a 2x boost timer when
-- one is running).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(script.Parent.Parent.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local UIKit = require(script.Parent.UIKit)
local Util = require(ReplicatedStorage.Shared.Util)

local BottomRight = {}

function BottomRight.build(parent: Instance): () -> ()
	local box = UIKit.panel({
		Name = "ScoreBox",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
		Size = UDim2.fromOffset(210, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, { UIKit.padding(12, 8), UIKit.list(Enum.FillDirection.Vertical, 2) })
	local score = UIKit.label({
		Name = "Score",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = 22,
		Font = UIKit.HEAVY,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = box,
	})
	local speed = UIKit.label({
		Name = "Speed",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = box,
	})
	local boost = UIKit.label({
		Name = "Boost",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 16),
		TextSize = 14,
		TextColor3 = UIKit.GOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		Parent = box,
	})

	return function()
		local value = ClientState.my("Score") or 0
		score.Text = "Score: " .. Util.commas(value)
		speed.Text = string.format("Speed Multiplier: %.2f", Config.SPEED_MULTIPLIER(value))
		local endsAt = ClientState.my("BoostEndsAt")
		local left = if typeof(endsAt) == "number" then endsAt - workspace:GetServerTimeNow() else 0
		boost.Visible = left > 0
		if left > 0 then
			boost.Text = "2x score  " .. Util.clock(left)
		end
	end
end

return BottomRight
