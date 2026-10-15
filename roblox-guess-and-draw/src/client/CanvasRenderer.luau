-- Draws strokes onto a canvas GuiObject using rotated, rounded Frames.
-- Points are normalised: x and y both run 0..1 across the canvas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

-- Canvas height measured in canvas widths, so lengths are the same in both axes.
local HEIGHT_IN_WIDTHS = 1 / Config.CANVAS_ASPECT

local CanvasRenderer = {}
CanvasRenderer.__index = CanvasRenderer

export type Renderer = typeof(setmetatable(
	{} :: { canvas: GuiObject, strokes: { [number]: any }, layer: number },
	CanvasRenderer
))

function CanvasRenderer.new(canvas: GuiObject): Renderer
	return setmetatable({ canvas = canvas, strokes = {}, layer = 0 }, CanvasRenderer)
end

local function colorFor(index: number): Color3
	local entry = Config.COLORS[index]
	return if entry then entry.color else Config.BACKGROUND_COLOR
end

local function drawSegment(stroke, x1: number, y1: number, x2: number, y2: number)
	local dx = x2 - x1
	local dy = (y2 - y1) * HEIGHT_IN_WIDTHS
	local length = math.sqrt(dx * dx + dy * dy)
	local thickness = stroke.thickness

	local segment = Instance.new("Frame")
	segment.BorderSizePixel = 0
	segment.BackgroundColor3 = stroke.color
	segment.AnchorPoint = Vector2.new(0.5, 0.5)
	segment.Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2)
	-- Width covers the segment plus a round cap at each end; height is the brush diameter.
	segment.Size = UDim2.fromScale(length + thickness, thickness / HEIGHT_IN_WIDTHS)
	segment.Rotation = math.deg(math.atan2(dy, dx))

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = segment

	segment.Parent = stroke.container
end

-- Adds points to a stroke, creating it if needed. `points` is a flat {x1, y1, x2, y2, ...}.
function CanvasRenderer.addPoints(self: Renderer, id: number, colorIndex: number, sizeIndex: number, points: { number })
	local stroke = self.strokes[id]
	if not stroke then
		self.layer += 1
		local container = Instance.new("Frame")
		container.Name = tostring(id)
		container.BackgroundTransparency = 1
		container.Size = UDim2.fromScale(1, 1)
		container.ZIndex = self.layer -- later strokes paint over earlier ones
		container.Parent = self.canvas
		stroke = {
			container = container,
			color = colorFor(colorIndex),
			thickness = Config.BRUSH_SIZES[sizeIndex] or Config.BRUSH_SIZES[1],
			lastX = nil :: number?,
			lastY = nil :: number?,
		}
		self.strokes[id] = stroke
	end

	for i = 1, #points - 1, 2 do
		local x, y = points[i], points[i + 1]
		if stroke.lastX then
			if x ~= stroke.lastX or y ~= stroke.lastY then
				drawSegment(stroke, stroke.lastX, stroke.lastY, x, y)
			end
		else
			drawSegment(stroke, x, y, x, y) -- a dot
		end
		stroke.lastX, stroke.lastY = x, y
	end
end

function CanvasRenderer.removeStroke(self: Renderer, id: number)
	local stroke = self.strokes[id]
	if stroke then
		stroke.container:Destroy()
		self.strokes[id] = nil
	end
end

function CanvasRenderer.clear(self: Renderer)
	for _, stroke in self.strokes do
		stroke.container:Destroy()
	end
	table.clear(self.strokes)
	self.layer = 0
end

return CanvasRenderer
