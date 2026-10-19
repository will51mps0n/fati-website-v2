-- On-screen buttons for phones and tablets: USE (hold), GRAB (hold), PICK
-- UP, DROP, SHOP, and RETURN for zombies. Placed bottom-right.

local ClientState = require(script.Parent.Parent.ClientState)
local InputController = require(script.Parent.Parent.InputController)
local UIKit = require(script.Parent.UIKit)

local MobileButtons = {}

local function round(parent: Instance, text: string, size: number, position: UDim2, color: Color3): TextButton
	local button = UIKit.button({
		Text = text,
		TextSize = if size > 70 then 22 else 14,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.15,
		Parent = parent,
	})
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0.5, 0) -- full circle
	end
	return button
end

function MobileButtons.build(parent: Instance): () -> ()
	local cluster = UIKit.new("Frame", {
		Name = "MobileButtons",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -100),
		Size = UDim2.fromOffset(200, 200),
		BackgroundTransparency = 1,
		Parent = parent,
	})

	local use = round(cluster, "USE", 86, UDim2.fromOffset(140, 140), UIKit.ACCENT)
	use.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			InputController.useStart()
		end
	end)
	use.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			InputController.useStop()
		end
	end)

	local grab = round(cluster, "GRAB", 58, UDim2.fromOffset(28, 66), UIKit.GOOD)
	grab.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			InputController.grabStart()
		end
	end)
	grab.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			InputController.grabStop()
		end
	end)

	local pick = round(cluster, "PICK\nUP", 56, UDim2.fromOffset(52, 150), UIKit.PANEL)
	pick.Activated:Connect(InputController.pickUp)
	local drop = round(cluster, "DROP", 50, UDim2.fromOffset(78, 92), UIKit.PANEL)
	drop.Activated:Connect(InputController.drop)
	local shop = round(cluster, "SHOP", 50, UDim2.fromOffset(140, 66), UIKit.PANEL)
	shop.Activated:Connect(InputController.shop)
	local back = round(cluster, "RETURN", 70, UDim2.fromOffset(140, 140), UIKit.RED)
	back.Activated:Connect(InputController.zombieReturn)

	return function()
		local zombie = ClientState.isZombie()
		use.Visible = not zombie
		grab.Visible = not zombie
		pick.Visible = not zombie
		drop.Visible = not zombie
		shop.Visible = not zombie
		back.Visible = zombie and ClientState.phase() == "Infection"
	end
end

return MobileButtons
