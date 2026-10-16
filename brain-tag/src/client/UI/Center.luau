-- Center screen: the big "Survivors Win!!!" / "Zombies Win!!!" text, plus
-- short toasts under the banner.

local TweenService = game:GetService("TweenService")

local ClientState = require(script.Parent.Parent.ClientState)
local UIKit = require(script.Parent.UIKit)

local Center = {}

function Center.buildWinText(parent: Instance): () -> ()
	local label = UIKit.label({
		Name = "WinText",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.9, 0.2),
		TextScaled = true,
		Font = UIKit.HEAVY,
		Visible = false,
		ZIndex = 10,
		Parent = parent,
	})
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 96, Parent = label })
	UIKit.textStroke(4).Parent = label
	local scale = UIKit.new("UIScale", { Scale = 1, Parent = label })

	local shown = ""
	return function()
		local winner = ClientState.attr("Winner")
		local text = if winner == "Survivors"
			then "Survivors Win!!!"
			elseif winner == "Zombies" then "Zombies Win!!!"
			else ""
		if text ~= shown then
			shown = text
			label.Visible = text ~= ""
			label.Text = text
			if text ~= "" then
				scale.Scale = 0.4
				TweenService:Create(
					scale,
					TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Scale = 1 }
				):Play()
			end
		end
	end
end

function Center.buildToasts(parent: Instance): (text: string, hex: string?) -> ()
	local stack = UIKit.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.fromOffset(420, 120),
		BackgroundTransparency = 1,
		Parent = parent,
	}, { UIKit.list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center) })

	local order = 0
	return function(text: string, hex: string?)
		order += 1
		local toast = UIKit.panel({
			Name = "Toast",
			LayoutOrder = order,
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			Parent = stack,
		}, { UIKit.padding(14, 0) })
		local label = UIKit.label({
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = 17,
			Text = text,
			TextColor3 = if hex then Color3.fromHex(hex) else UIKit.WHITE,
			Parent = toast,
		})
		local toasts = stack:GetChildren()
		local count = 0
		for _, child in toasts do
			if child:IsA("Frame") then
				count += 1
			end
		end
		if count > 3 then
			local oldest: Frame? = nil
			for _, child in toasts do
				if child:IsA("Frame") and (not oldest or child.LayoutOrder < oldest.LayoutOrder) then
					oldest = child
				end
			end
			if oldest then
				oldest:Destroy()
			end
		end
		task.delay(3, function()
			if toast.Parent then
				local info = TweenInfo.new(0.4)
				TweenService:Create(toast, info, { BackgroundTransparency = 1 }):Play()
				TweenService:Create(label, info, { TextTransparency = 1 }):Play()
				task.wait(0.45)
				toast:Destroy()
			end
		end)
	end
end

return Center
