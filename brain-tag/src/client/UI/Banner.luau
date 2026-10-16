-- Top-center countdown banner: "Outbreak happening in N seconds", the
-- survival timer, or "Waiting for players".

local ClientState = require(script.Parent.Parent.ClientState)
local UIKit = require(script.Parent.UIKit)
local Util = require(game:GetService("ReplicatedStorage").Shared.Util)

local Banner = {}

function Banner.build(parent: Instance): () -> ()
	local frame = UIKit.panel({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(0, 42),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = parent,
	}, { UIKit.padding(18, 0) })
	local label = UIKit.label({
		Name = "Text",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 22,
		Font = UIKit.HEAVY,
		Parent = frame,
	})

	return function()
		local phase = ClientState.phase()
		local left = ClientState.secondsLeft()
		local text
		if phase == "Waiting" then
			local count = #ClientState.participants:GetChildren()
			local needed = ClientState.attr("Needed") or 2
			text = string.format("Waiting for players (%d/%d)", count, needed)
		elseif phase == "Prep" then
			text = string.format("Outbreak happening in %d seconds", math.ceil(left))
		elseif phase == "Infection" then
			if ClientState.isZombie() then
				text = "Infect them all!  " .. Util.clock(left)
			else
				text = "Survive!  " .. Util.clock(left) .. " left"
			end
		else
			text = "Next round starting..."
		end
		label.Text = text
		label.TextColor3 = if phase == "Infection" and left <= 10 then UIKit.RED else UIKit.WHITE
	end
end

return Banner
