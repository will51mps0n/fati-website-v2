-- Full-screen effects drawn on their own layer: confetti and floating "+points" text.

local Debris = game:GetService("Debris")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local Effects = {}

local layer: Frame? = nil

-- `effectsLayer` must cover the whole screen and sit above everything else.
function Effects.init(effectsLayer: Frame)
	layer = effectsLayer
end

function Effects.confetti(count: number?)
	if not layer then
		return
	end
	for _ = 1, count or 90 do
		local width = math.random(8, 15)
		local startX = math.random()
		local piece = Ui.make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(startX, -0.05 - math.random() * 0.35),
			Size = UDim2.fromOffset(width, math.floor(width * 0.6)),
			Rotation = math.random(0, 360),
			BackgroundColor3 = Theme.rainbow[math.random(#Theme.rainbow)],
			BorderSizePixel = 0,
			Parent = layer,
		}, { Ui.corner(2) })
		local seconds = 2.4 + math.random() * 1.8
		Ui.tween(piece, seconds, {
			Position = UDim2.fromScale(startX + (math.random() - 0.5) * 0.3, 1.1),
			Rotation = piece.Rotation + math.random(-720, 720),
		}, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
		Debris:AddItem(piece, seconds + 0.1)
	end
end

-- Pops up text at a screen position, then drifts it upward and fades it out.
function Effects.floatText(text: string, color: Color3, position: Vector2, textSize: number?)
	if not layer then
		return
	end
	local outline = Ui.textOutline(3)
	local label = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(position.X, position.Y),
		Size = UDim2.fromOffset(400, (textSize or 30) + 10),
		Text = text,
		TextScaled = false,
		TextSize = textSize or 30,
		TextColor3 = color,
		FontFace = Theme.heavy,
		Parent = layer,
	}, { outline })
	Ui.pop(label, 0.3, 0.35)
	task.delay(0.45, function()
		Ui.tween(label, 0.9, { Position = UDim2.fromOffset(position.X, position.Y - 60), TextTransparency = 1 })
		Ui.tween(outline, 0.9, { Transparency = 1 })
	end)
	Debris:AddItem(label, 1.5)
end

-- Centre of a GUI object on screen, handy as a floatText position.
function Effects.centreOf(gui: GuiObject): Vector2
	return gui.AbsolutePosition + gui.AbsoluteSize / 2
end

return Effects
