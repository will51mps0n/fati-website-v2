--[[
	DrawingRenderer  (ModuleScript)
	Put in: ReplicatedStorage   — name it exactly "DrawingRenderer"

	Draws lines on a GUI "canvas" Frame. Each line segment is a thin, rotated,
	rounded Frame. Coordinates are 0..1000 on both axes so drawings look the
	same on every screen size.

	A stroke is { c = colorIndex, s = sizeIndex, p = buffer } where the buffer
	holds pairs of uint16 (x, y), 4 bytes per point.
]]

local Config = require(script.Parent:WaitForChild("Config"))

local Renderer = {}

local ASPECT = Config.CANVAS_ASPECT
local zCounter = 0

-- A container for one stroke, so a stroke can be removed in one go (undo).
function Renderer.newGroup(canvas)
	zCounter += 1
	local group = Instance.new("Frame")
	group.Name = "Stroke"
	group.BackgroundTransparency = 1
	group.Size = UDim2.fromScale(1, 1)
	group.ZIndex = zCounter -- later strokes always draw on top
	group.Parent = canvas
	return group
end

-- One line from (x1, y1) to (x2, y2). thickness is in thousandths of canvas width.
function Renderer.segment(parent, x1, y1, x2, y2, color, thickness)
	-- Work in "canvas widths" so rotation is correct even though the canvas isn't square.
	local dx = (x2 - x1) / 1000
	local dy = (y2 - y1) / 1000 / ASPECT
	local length = math.sqrt(dx * dx + dy * dy)
	local t = thickness / 1000

	local line = Instance.new("Frame")
	line.BorderSizePixel = 0
	line.BackgroundColor3 = color
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromScale((x1 + x2) / 2000, (y1 + y2) / 2000)
	-- Width is relative to canvas width; height is relative to canvas height, hence * ASPECT.
	line.Size = UDim2.fromScale(length + t, t * ASPECT)
	line.Rotation = math.deg(math.atan2(dy, dx))

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0) -- pill shape = round brush tips
	corner.Parent = line

	line.Parent = parent
	return line
end

function Renderer.drawStroke(canvas, stroke)
	local group = Renderer.newGroup(canvas)
	local color = Config.COLORS[stroke.c] or Config.COLORS[1]
	local size = Config.BRUSH_SIZES[stroke.s] or Config.BRUSH_SIZES[1]
	local points = stroke.p
	local count = buffer.len(points) // 4
	if count == 0 then
		return group
	end

	local px, py = buffer.readu16(points, 0), buffer.readu16(points, 2)
	if count == 1 then
		Renderer.segment(group, px, py, px, py, color, size) -- a single dot
	end
	for i = 1, count - 1 do
		local x, y = buffer.readu16(points, i * 4), buffer.readu16(points, i * 4 + 2)
		Renderer.segment(group, px, py, x, y, color, size)
		px, py = x, y
	end
	return group
end

function Renderer.clear(canvas)
	for _, child in canvas:GetChildren() do
		if child.Name == "Stroke" then
			child:Destroy()
		end
	end
end

function Renderer.render(canvas, strokes)
	Renderer.clear(canvas)
	for _, stroke in strokes or {} do
		Renderer.drawStroke(canvas, stroke)
	end
end

return Renderer
