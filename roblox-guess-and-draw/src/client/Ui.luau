-- Building blocks for the UI (flat skribbl.io-style panels, text, buttons, avatars)
-- and the small tween animations used everywhere.

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local Ui = {}

function Ui.make(className: string, props: { [string]: any }, children: { Instance }?): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

local make = Ui.make

local function merge(defaults: { [string]: any }, props: { [string]: any })
	for key, value in props do
		defaults[key] = value
	end
	return defaults
end

function Ui.corner(radius: number?): UICorner
	return make("UICorner", { CornerRadius = UDim.new(0, radius or 4) })
end

-- Fully rounded ends: circles and pills.
function Ui.round(): UICorner
	return make("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

function Ui.pad(pixels: number, vertical: number?): UIPadding
	local h, v = UDim.new(0, pixels), UDim.new(0, vertical or pixels)
	return make("UIPadding", { PaddingLeft = h, PaddingRight = h, PaddingTop = v, PaddingBottom = v })
end

function Ui.maxText(size: number): UITextSizeConstraint
	return make("UITextSizeConstraint", { MaxTextSize = size })
end

function Ui.square(): UIAspectRatioConstraint
	return make("UIAspectRatioConstraint", { AspectRatio = 1 })
end

-- Outline around a frame or button.
function Ui.border(thickness: number?, color: Color3?, transparency: number?): UIStroke
	return make("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Thickness = thickness or 2,
		Color = color or Theme.border,
		Transparency = transparency or 0,
	})
end

-- Outline around the letters of a text label.
function Ui.textOutline(thickness: number?, color: Color3?): UIStroke
	return make("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Thickness = thickness or 2,
		Color = color or Theme.outline,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

function Ui.label(props: { [string]: any }, children: { Instance }?): TextLabel
	return make(
		"TextLabel",
		merge({ BackgroundTransparency = 1, TextColor3 = Theme.text, FontFace = Theme.bold, TextScaled = true }, props),
		children
	)
end

-- Big white heading text, as on the dark canvas overlay.
function Ui.title(props: { [string]: any }, children: { Instance }?): TextLabel
	return Ui.label(merge({ FontFace = Theme.heavy, TextColor3 = Theme.white }, props), children)
end

-- A flat white panel with slightly rounded corners.
function Ui.panel(props: { [string]: any }, children: { Instance }?): Frame
	local list = children or {}
	table.insert(list, Ui.corner(4))
	return make("Frame", merge({ BackgroundColor3 = Theme.panel, BorderSizePixel = 0 }, props), list)
end

-- Pointer position in full-window pixels, the space our ScreenGui is laid out in
-- (it ignores the topbar inset), so it compares directly with AbsolutePosition.
function Ui.pointerPosition(input: InputObject?): Vector2
	if input and input.UserInputType == Enum.UserInputType.Touch then
		-- Touch positions are measured from below the topbar; shift them into window space.
		return Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
	end
	return UserInputService:GetMouseLocation()
end

function Ui.isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

function Ui.contains(gui: GuiObject, point: Vector2): boolean
	local relative = point - gui.AbsolutePosition
	return relative.X >= 0 and relative.Y >= 0 and relative.X <= gui.AbsoluteSize.X and relative.Y <= gui.AbsoluteSize.Y
end

-- Animation --------------------------------------------------------------------------

function Ui.tween(
	instance: Instance,
	seconds: number,
	goal: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goal
	)
	tween:Play()
	return tween
end

function Ui.scaleOf(gui: GuiObject): UIScale
	local scale = gui:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = make("UIScale", { Parent = gui })
	end
	return scale :: UIScale
end

-- Springs the element in from small (or large) to full size.
function Ui.pop(gui: GuiObject, from: number?, seconds: number?)
	local scale = Ui.scaleOf(gui)
	scale.Scale = from or 0.5
	Ui.tween(scale, seconds or 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- A quick bump in size and back.
function Ui.pulse(gui: GuiObject, amount: number?)
	local scale = Ui.scaleOf(gui)
	scale.Scale = amount or 1.2
	Ui.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

function Ui.shake(gui: GuiObject, degrees: number?)
	local angle = degrees or 8
	task.spawn(function()
		for _, rotation in { angle, -angle, angle * 0.6, -angle * 0.6, 0 } do
			Ui.tween(gui, 0.05, { Rotation = rotation }, Enum.EasingStyle.Sine).Completed:Wait()
		end
	end)
end

-- Loops forever between the current and the given property values.
function Ui.loop(instance: Instance, seconds: number, goal: { [string]: any })
	TweenService:Create(
		instance,
		TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		goal
	):Play()
end

-- Grows a little on hover and shrinks while pressed.
function Ui.hoverable(target: GuiButton, scaleTarget: GuiObject?)
	local scale = Ui.scaleOf(scaleTarget or target)
	local hovering = false
	target.MouseEnter:Connect(function()
		hovering = true
		Ui.tween(scale, 0.12, { Scale = 1.06 })
	end)
	target.MouseLeave:Connect(function()
		hovering = false
		Ui.tween(scale, 0.12, { Scale = 1 })
	end)
	target.MouseButton1Down:Connect(function()
		Ui.tween(scale, 0.08, { Scale = 0.92 })
	end)
	target.MouseButton1Up:Connect(function()
		Ui.tween(scale, 0.2, { Scale = if hovering then 1.06 else 1 }, Enum.EasingStyle.Back)
	end)
end

-- Buttons ------------------------------------------------------------------------------

-- The outlined white button used on the dark canvas overlay (word choices). It
-- fills white on hover. Takes Text plus any layout props.
function Ui.overlayButton(props: { [string]: any }): TextButton
	local text = props.Text or ""
	props.Text = ""
	local button = make(
		"TextButton",
		merge({ BackgroundColor3 = Theme.white, BackgroundTransparency = 1, AutoButtonColor = false }, props),
		{ Ui.corner(8), Ui.border(3, Theme.white) }
	)
	local caption = Ui.title({ Size = UDim2.fromScale(1, 1), Text = text, Parent = button }, { Ui.maxText(30), Ui.pad(10, 6) })
	Ui.hoverable(button)
	button.MouseEnter:Connect(function()
		Ui.tween(button, 0.12, { BackgroundTransparency = 0 })
		Ui.tween(caption, 0.12, { TextColor3 = Theme.overlay })
	end)
	button.MouseLeave:Connect(function()
		Ui.tween(button, 0.12, { BackgroundTransparency = 1 })
		Ui.tween(caption, 0.12, { TextColor3 = Theme.white })
	end)
	button.Activated:Connect(function()
		Sounds.play("click")
	end)
	return button
end

-- A white square tool button (toolbar), holding an icon or a custom child.
function Ui.toolButton(props: { [string]: any }): TextButton
	local button = make(
		"TextButton",
		merge({ Text = "", BackgroundColor3 = Theme.white, AutoButtonColor = false, Size = UDim2.fromScale(1, 1) }, props),
		{ Ui.corner(6), Ui.square() }
	)
	Ui.hoverable(button)
	button.Activated:Connect(function()
		Sounds.play("click", 0.5)
	end)
	return button
end

-- Avatars ------------------------------------------------------------------------------

-- The player's avatar headshot. Shows their initial in a circle when there is no
-- picture (Studio test players have no avatar).
function Ui.avatar(userId: number?, name: string?, props: { [string]: any }): Frame
	local frame = make("Frame", merge({ BackgroundTransparency = 1 }, props))
	if userId and userId > 0 then
		make("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150`,
			Parent = frame,
		})
	else
		make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.border, Parent = frame }, {
			Ui.round(),
			Ui.label({
				Size = UDim2.fromScale(1, 1),
				Text = string.upper(string.sub(name or "?", 1, 1)),
				TextColor3 = Theme.white,
				FontFace = Theme.heavy,
			}, { Ui.pad(6) }),
		})
	end
	return frame
end

return Ui
