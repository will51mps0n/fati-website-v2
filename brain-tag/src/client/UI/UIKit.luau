-- Tiny UI toolkit: every HUD element is built in code with these helpers.
-- Style: BuilderSans, white text, dark translucent rounded panels.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Sounds = require(script.Parent.Parent.Sounds)

local UIKit = {}

UIKit.FONT = Enum.Font.BuilderSans
UIKit.BOLD = Enum.Font.BuilderSansBold
UIKit.HEAVY = Enum.Font.BuilderSansExtraBold
UIKit.PANEL = Color3.fromHex(Config.COLORS.Panel)
UIKit.PANEL_TRANSPARENCY = 0.25
UIKit.WHITE = Color3.new(1, 1, 1)
UIKit.MUTED = Color3.fromRGB(190, 194, 200)
UIKit.LIME = Color3.fromHex(Config.COLORS.SelfName)
UIKit.RED = Color3.fromHex(Config.COLORS.ZombieText)
UIKit.GOLD = Color3.fromHex(Config.COLORS.VipName)
UIKit.ACCENT = Color3.fromHex(Config.COLORS.Accent)
UIKit.GOOD = Color3.fromHex(Config.COLORS.Good)

type Props = { [string]: any }

-- Creates an instance, applies properties (Parent last) and adds children.
function UIKit.new(className: string, props: Props?, children: { any }?): any
	local instance = Instance.new(className) :: any
	local parent = nil
	local given: Props = props or {}
	local kids: { any } = children or {}
	for key, value in given do
		if key == "Parent" then
			parent = value
		else
			instance[key] = value
		end
	end
	for _, child in kids do
		child.Parent = instance
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UIKit.corner(radius: number?): Instance
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0, radius or 8) })
end

function UIKit.stroke(color: Color3?, thickness: number?, transparency: number?): Instance
	return UIKit.new("UIStroke", {
		Color = color or UIKit.WHITE,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UIKit.textStroke(thickness: number?): Instance
	return UIKit.new("UIStroke", {
		Color = Color3.fromRGB(15, 15, 18),
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})
end

function UIKit.padding(px: number, vertical: number?): Instance
	local v = vertical or px
	return UIKit.new("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, v),
		PaddingBottom = UDim.new(0, v),
	})
end

function UIKit.list(
	direction: Enum.FillDirection?,
	padding: number?,
	hAlign: Enum.HorizontalAlignment?,
	vAlign: Enum.VerticalAlignment?
): Instance
	return UIKit.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 6),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function UIKit.panel(props: Props, children: { any }?): Frame
	local merged: Props = {
		BackgroundColor3 = UIKit.PANEL,
		BackgroundTransparency = UIKit.PANEL_TRANSPARENCY,
		BorderSizePixel = 0,
	}
	for key, value in props do
		merged[key] = value
	end
	local frame = UIKit.new("Frame", merged, children)
	UIKit.corner(8).Parent = frame
	return frame
end

function UIKit.label(props: Props): TextLabel
	local merged: Props = {
		BackgroundTransparency = 1,
		Font = UIKit.BOLD,
		TextColor3 = UIKit.WHITE,
		TextSize = 18,
		Text = "",
		BorderSizePixel = 0,
	}
	for key, value in props do
		merged[key] = value
	end
	return UIKit.new("TextLabel", merged)
end

function UIKit.button(props: Props, onClick: (() -> ())?): TextButton
	local merged: Props = {
		BackgroundColor3 = UIKit.ACCENT,
		BorderSizePixel = 0,
		Font = UIKit.HEAVY,
		TextColor3 = UIKit.WHITE,
		TextSize = 18,
		AutoButtonColor = true,
	}
	for key, value in props do
		merged[key] = value
	end
	local button = UIKit.new("TextButton", merged)
	UIKit.corner(8).Parent = button
	button.Activated:Connect(function()
		Sounds.play("UiClick")
	end)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

-- A centered modal window with a title bar and a close button. Returns the
-- window and its content frame.
function UIKit.modal(
	parent: Instance,
	title: string,
	width: number,
	height: number,
	onClose: () -> ()
): (Frame, Frame, TextLabel)
	local window = UIKit.panel({
		Name = title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 0.86, 0),
		BackgroundTransparency = 0.08,
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	})
	UIKit.new("UISizeConstraint", { MaxSize = Vector2.new(width, height), Parent = window })
	local heading = UIKit.label({
		Name = "Title",
		Text = title,
		TextSize = 26,
		Font = UIKit.HEAVY,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -80, 0, 36),
		ZIndex = 21,
		Parent = window,
	})
	UIKit.button({
		Name = "Close",
		Text = "X",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = Color3.fromRGB(70, 72, 78),
		ZIndex = 22,
		Parent = window,
	}, onClose)
	local content = UIKit.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 52),
		Size = UDim2.new(1, -24, 1, -64),
		ZIndex = 21,
		Parent = window,
	})
	return window, content, heading
end

-- Renders a 3D model inside a ViewportFrame, framed from above at an angle.
function UIKit.viewport(parent: Instance, model: Model, props: Props?): ViewportFrame
	local merged: Props = {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(205, 205, 205),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-0.3, -1, -0.4),
	}
	local given: Props = props or {}
	for key, value in given do
		merged[key] = value
	end
	local frame = UIKit.new("ViewportFrame", merged)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = frame
	frame.CurrentCamera = camera
	model.Parent = frame
	local cf, size = model:GetBoundingBox()
	local radius = math.max(size.Magnitude / 2, 0.5)
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.08
	local from = cf.Position + Vector3.new(0.45, 1, 0.75).Unit * distance
	camera.CFrame = CFrame.lookAt(from, cf.Position)
	frame.Parent = parent
	return frame
end

return UIKit
