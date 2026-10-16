-- A colour wheel popup: drag on the wheel to pick the hue (around) and how vivid
-- it is (out from the white centre), and on the slider below for brightness. It's
-- built from Frames and gradients, so it needs no uploaded image.

local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local make = Ui.make

local SPOKES = 144 -- thin wedges of colour that make up the wheel
local TAU = 2 * math.pi

local ColorPicker = {}
ColorPicker.__index = ColorPicker

export type Picker = typeof(setmetatable(
	{} :: {
		panel: Frame,
		hue: number,
		saturation: number,
		value: number,
		onPick: (Color3) -> (),
		_refresh: () -> (),
	},
	ColorPicker
))

-- `props` positions the popup (Position, Size, Parent). `onPick` is called with
-- every colour picked, while dragging too.
function ColorPicker.new(props: { [string]: any }, onPick: (Color3) -> ()): Picker
	local panel = Ui.panel({
		Position = props.Position,
		Size = props.Size,
		Visible = false,
		ZIndex = 20,
		Parent = props.Parent,
	}, { Ui.border(2, Theme.border) })

	-- The wheel: spokes running from white at the centre to the full hue at the rim.
	local wheel = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.04),
		Size = UDim2.fromScale(0.86, 0.66),
		BackgroundColor3 = Theme.white,
		Parent = panel,
	}, { Ui.square(), Ui.round() })
	for i = 0, SPOKES - 1 do
		local angle = i / SPOKES * TAU
		-- GUI objects rotate about their centre, so each spoke is centred halfway out.
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + 0.25 * math.cos(angle), 0.5 + 0.25 * math.sin(angle)),
			Size = UDim2.fromScale(0.5, 0.03),
			Rotation = math.deg(angle),
			BorderSizePixel = 0,
			BackgroundColor3 = Theme.white,
			ZIndex = 1,
			Parent = wheel,
		}, {
			make("UIGradient", { Color = ColorSequence.new(Theme.white, Color3.fromHSV(i / SPOKES, 1, 1)) }),
		})
	end
	-- Darkens the whole wheel to preview the brightness.
	local shade = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = wheel,
	}, { Ui.round() })
	-- A rim that tidies the spoke ends into a clean circle.
	make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = wheel,
	}, { Ui.round(), Ui.border(3, Theme.white), })
	local marker = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = wheel,
	}, {
		Ui.round(),
		Ui.border(3, Theme.outline),
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -4, 1, -4),
			BackgroundTransparency = 1,
		}, { Ui.round(), Ui.border(2, Theme.white) }),
	})
	local wheelInput = make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 5,
		Parent = wheel,
	})

	-- Brightness slider: black on the left to the full colour on the right.
	local sliderGradient = make("UIGradient", {})
	local slider = make("Frame", {
		Position = UDim2.fromScale(0.07, 0.75),
		Size = UDim2.fromScale(0.86, 0.075),
		BackgroundColor3 = Theme.white,
		Parent = panel,
	}, { Ui.corner(6), Ui.border(1, Theme.border), sliderGradient })
	local knob = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, 10, 1.5, 0),
		BackgroundColor3 = Theme.white,
		ZIndex = 2,
		Parent = slider,
	}, { Ui.corner(4), Ui.border(2, Theme.outline) })
	local sliderInput = make("TextButton", {
		Size = UDim2.new(1, 0, 1, 12),
		Position = UDim2.fromOffset(0, -6),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 3,
		Parent = slider,
	})

	-- The picked colour and its hex code.
	local swatch = make("Frame", {
		Position = UDim2.fromScale(0.07, 0.87),
		Size = UDim2.fromScale(0.2, 0.09),
		Parent = panel,
	}, { Ui.corner(4), Ui.border(1, Theme.border) })
	local hex = Ui.label({
		Position = UDim2.fromScale(0.3, 0.87),
		Size = UDim2.fromScale(0.63, 0.09),
		FontFace = Theme.monoBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = panel,
	}, { Ui.maxText(20) })

	local self = setmetatable({
		panel = panel,
		hue = 0,
		saturation = 1,
		value = 1,
		onPick = onPick,
		_refresh = function() end,
	}, ColorPicker)

	local function refresh()
		local full = Color3.fromHSV(self.hue, self.saturation, 1)
		local color = Color3.fromHSV(self.hue, self.saturation, self.value)
		shade.BackgroundTransparency = self.value
		sliderGradient.Color = ColorSequence.new(Color3.new(0, 0, 0), full)
		local angle = self.hue * TAU
		marker.Position = UDim2.fromScale(
			0.5 + 0.5 * self.saturation * math.cos(angle),
			0.5 + 0.5 * self.saturation * math.sin(angle)
		)
		knob.Position = UDim2.fromScale(self.value, 0.5)
		swatch.BackgroundColor3 = color
		hex.Text = "#" .. string.upper(color:ToHex())
	end
	self._refresh = refresh

	local function pickWheel(point: Vector2)
		local centre = wheel.AbsolutePosition + wheel.AbsoluteSize / 2
		local offset = (point - centre) / (wheel.AbsoluteSize.X / 2)
		self.saturation = math.min(1, offset.Magnitude)
		self.hue = (math.atan2(offset.Y, offset.X) / TAU) % 1
		refresh()
		self.onPick(Color3.fromHSV(self.hue, self.saturation, self.value))
	end

	local function pickSlider(point: Vector2)
		self.value = math.clamp((point.X - slider.AbsolutePosition.X) / slider.AbsoluteSize.X, 0, 1)
		refresh()
		self.onPick(Color3.fromHSV(self.hue, self.saturation, self.value))
	end

	-- Drag on either control; keeps tracking even if the pointer slips off it.
	local dragging: ((Vector2) -> ())? = nil
	local dragInput: InputObject? = nil
	local function startDrag(pick: (Vector2) -> ())
		return function(input: InputObject)
			if Ui.isPress(input) then
				dragging, dragInput = pick, input
				pick(Ui.pointerPosition(input))
			end
		end
	end
	wheelInput.InputBegan:Connect(startDrag(pickWheel))
	sliderInput.InputBegan:Connect(startDrag(pickSlider))
	UserInputService.InputChanged:Connect(function(input)
		local pick = dragging
		if not pick then
			return
		end
		local isMouseDrag = input.UserInputType == Enum.UserInputType.MouseMovement
			and (dragInput :: InputObject).UserInputType == Enum.UserInputType.MouseButton1
		if isMouseDrag or input == dragInput then
			pick(Ui.pointerPosition(input))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input == dragInput) then
			dragging, dragInput = nil, nil
		end
	end)

	refresh()
	return self
end

function ColorPicker.isOpen(self: Picker): boolean
	return self.panel.Visible
end

-- Opens the picker showing `current`, so small tweaks start from the colour in use.
function ColorPicker.open(self: Picker, current: Color3)
	local hue, saturation, value = current:ToHSV()
	self.hue, self.saturation, self.value = hue, saturation, value
	self._refresh()
	self.panel.Visible = true
	Ui.pop(self.panel, 0.6, 0.25)
end

function ColorPicker.close(self: Picker)
	self.panel.Visible = false
end

function ColorPicker.contains(self: Picker, point: Vector2): boolean
	return self.panel.Visible and Ui.contains(self.panel, point)
end

return ColorPicker
