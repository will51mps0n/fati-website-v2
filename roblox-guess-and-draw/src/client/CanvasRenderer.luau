-- Draws the shared canvas. Points are normalised: x and y both run 0..1 across it.
--
-- Strokes are rotated, rounded Frames. Alongside them a low-resolution grid
-- records which colour covers each spot, so the bucket can flood-fill. Every
-- client builds the same grid from the same history, so a fill comes out the
-- same on every screen. Fills are drawn underneath the strokes, slightly
-- oversized, so they tuck neatly under the lines around them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("GuessAndDraw"):WaitForChild("Config"))

-- Canvas height measured in canvas widths, so lengths are the same in both axes.
local HEIGHT_IN_WIDTHS = 1 / Config.CANVAS_ASPECT

local GRID_W = Config.FILL_GRID_WIDTH
local GRID_H = math.floor(GRID_W * HEIGHT_IN_WIDTHS + 0.5) -- square cells
local CELLS = GRID_W * GRID_H
local MIN_STAMP_RADIUS = 0.75 -- cells; keeps the thinnest lines solid walls for the fill
local FILL_OVERLAP = 0.6 -- cells each fill rectangle reaches under its neighbours

local CanvasRenderer = {}
CanvasRenderer.__index = CanvasRenderer

-- Colours travel as 0xRRGGBB numbers.
function CanvasRenderer.toInt(color: Color3): number
	return math.floor(color.R * 255 + 0.5) * 65536 + math.floor(color.G * 255 + 0.5) * 256 + math.floor(color.B * 255 + 0.5)
end

function CanvasRenderer.toColor(value: number): Color3
	return Color3.fromRGB(value // 65536 % 256, value // 256 % 256, value % 256)
end

local BACKGROUND = CanvasRenderer.toInt(Config.BACKGROUND_COLOR)

type Segment = { frame: Frame, cell: number, colorInt: number }

type Item = {
	kind: string, -- "stroke" or "fill"
	id: number,
	colorInt: number,
	container: Frame?,
	-- strokes
	thickness: number?,
	points: { number }?,
	segments: { Segment }?,
	lastX: number?,
	lastY: number?,
	-- fills
	x: number?,
	y: number?,
	recolored: { { segment: Segment, previous: number } }?,
}

export type Renderer = typeof(setmetatable(
	{} :: {
		canvas: GuiObject,
		fillLayer: Frame,
		items: { Item },
		byId: { [number]: Item },
		layer: number,
		fillLayerZ: number,
		grid: buffer,
	},
	CanvasRenderer
))

local function resetGrid(grid: buffer)
	for i = 0, CELLS - 1 do
		buffer.writeu32(grid, i * 4, BACKGROUND)
	end
end

local function cellAt(x: number, y: number): number
	local cx = math.clamp(math.floor(x * GRID_W), 0, GRID_W - 1)
	local cy = math.clamp(math.floor(y * GRID_H), 0, GRID_H - 1)
	return cy * GRID_W + cx
end

-- Paints a round-ended line of the given diameter (in canvas widths) into the grid.
local function stamp(grid: buffer, x1: number, y1: number, x2: number, y2: number, thickness: number, colorInt: number)
	local ax, ay = x1 * GRID_W, y1 * GRID_H
	local bx, by = x2 * GRID_W, y2 * GRID_H
	local radius = math.max(thickness * GRID_W / 2, MIN_STAMP_RADIUS)
	local radiusSq = radius * radius
	local dx, dy = bx - ax, by - ay
	local lengthSq = dx * dx + dy * dy

	local minX = math.max(0, math.floor(math.min(ax, bx) - radius))
	local maxX = math.min(GRID_W - 1, math.ceil(math.max(ax, bx) + radius))
	local minY = math.max(0, math.floor(math.min(ay, by) - radius))
	local maxY = math.min(GRID_H - 1, math.ceil(math.max(ay, by) + radius))
	for cy = minY, maxY do
		local py = cy + 0.5
		for cx = minX, maxX do
			local px = cx + 0.5
			local t = 0
			if lengthSq > 0 then
				t = math.clamp(((px - ax) * dx + (py - ay) * dy) / lengthSq, 0, 1)
			end
			local qx, qy = ax + t * dx - px, ay + t * dy - py
			if qx * qx + qy * qy <= radiusSq then
				buffer.writeu32(grid, (cy * GRID_W + cx) * 4, colorInt)
			end
		end
	end
end

-- Floods the area of matching colour around (x, y) with `colorInt`. Returns the
-- colour that was replaced and a mask of the flooded cells, or nil if the spot
-- already had that colour.
local function flood(grid: buffer, x: number, y: number, colorInt: number): (number, buffer?)
	local start = cellAt(x, y)
	local old = buffer.readu32(grid, start * 4)
	if old == colorInt then
		return old, nil
	end
	local mask = buffer.create(CELLS)
	local stack = table.create(1024)
	local top = 1
	stack[1] = start
	buffer.writeu32(grid, start * 4, colorInt)
	buffer.writeu8(mask, start, 1)
	while top > 0 do
		local i = stack[top]
		top -= 1
		local column = i % GRID_W
		-- Left, right, up, down.
		for _, n in { if column > 0 then i - 1 else -1, if column < GRID_W - 1 then i + 1 else -1, i - GRID_W, i + GRID_W } do
			if n >= 0 and n < CELLS and buffer.readu32(grid, n * 4) == old then
				buffer.writeu32(grid, n * 4, colorInt)
				buffer.writeu8(mask, n, 1)
				top += 1
				stack[top] = n
			end
		end
	end
	return old, mask
end

-- Draws the flooded cells as rectangles: runs along each row, with identical runs
-- in consecutive rows merged into one taller rectangle.
local function drawMask(container: Frame, mask: buffer, color: Color3)
	local function emit(x0: number, x1: number, y0: number, y1: number)
		local frame = Instance.new("Frame")
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = color
		frame.Position = UDim2.fromScale((x0 - FILL_OVERLAP) / GRID_W, (y0 - FILL_OVERLAP) / GRID_H)
		frame.Size = UDim2.fromScale((x1 - x0 + 1 + 2 * FILL_OVERLAP) / GRID_W, (y1 - y0 + 1 + 2 * FILL_OVERLAP) / GRID_H)
		frame.Parent = container
	end

	local open: { [number]: number } = {} -- run key (x0 * GRID_W + x1) -> first row
	for y = 0, GRID_H - 1 do
		local row: { [number]: boolean } = {}
		local x = 0
		while x < GRID_W do
			if buffer.readu8(mask, y * GRID_W + x) == 1 then
				local x0 = x
				while x < GRID_W and buffer.readu8(mask, y * GRID_W + x) == 1 do
					x += 1
				end
				row[x0 * GRID_W + x - 1] = true
			else
				x += 1
			end
		end
		for key, firstRow in open do
			if not row[key] then
				emit(key // GRID_W, key % GRID_W, firstRow, y - 1)
				open[key] = nil
			end
		end
		for key in row do
			if not open[key] then
				open[key] = y
			end
		end
	end
	for key, firstRow in open do
		emit(key // GRID_W, key % GRID_W, firstRow, GRID_H - 1)
	end
end

function CanvasRenderer.new(canvas: GuiObject): Renderer
	-- All fills live in one layer under every stroke.
	local fillLayer = Instance.new("Frame")
	fillLayer.Name = "Fills"
	fillLayer.BackgroundTransparency = 1
	fillLayer.Size = UDim2.fromScale(1, 1)
	fillLayer.ZIndex = 0
	fillLayer.Parent = canvas

	local grid = buffer.create(CELLS * 4)
	resetGrid(grid)
	return setmetatable({
		canvas = canvas,
		fillLayer = fillLayer,
		items = {},
		byId = {},
		layer = 0,
		fillLayerZ = 0,
		grid = grid,
	}, CanvasRenderer)
end

local function drawSegment(stroke: Item, grid: buffer, x1: number, y1: number, x2: number, y2: number)
	local thickness = stroke.thickness :: number
	local dx = x2 - x1
	local dy = (y2 - y1) * HEIGHT_IN_WIDTHS
	local length = math.sqrt(dx * dx + dy * dy)

	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = CanvasRenderer.toColor(stroke.colorInt)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2)
	-- Width covers the segment plus a round cap at each end; height is the brush diameter.
	frame.Size = UDim2.fromScale(length + thickness, thickness / HEIGHT_IN_WIDTHS)
	frame.Rotation = math.deg(math.atan2(dy, dx))

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame

	frame.Parent = stroke.container
	table.insert(stroke.segments :: { Segment }, {
		frame = frame,
		cell = cellAt((x1 + x2) / 2, (y1 + y2) / 2),
		colorInt = stroke.colorInt,
	})
	stamp(grid, x1, y1, x2, y2, thickness, stroke.colorInt)
end

-- Adds points to a stroke, creating it if needed. `points` is a flat {x1, y1, x2, y2, ...}.
function CanvasRenderer.addPoints(self: Renderer, id: number, colorInt: number, sizeIndex: number, points: { number })
	local stroke = self.byId[id]
	if stroke and stroke.kind ~= "stroke" then
		return
	end
	if not stroke then
		self.layer += 1
		local container = Instance.new("Frame")
		container.Name = tostring(id)
		container.BackgroundTransparency = 1
		container.Size = UDim2.fromScale(1, 1)
		container.ZIndex = self.layer -- later strokes paint over earlier ones
		container.Parent = self.canvas
		stroke = {
			kind = "stroke",
			id = id,
			colorInt = colorInt,
			container = container,
			thickness = Config.BRUSH_SIZES[sizeIndex] or Config.BRUSH_SIZES[1],
			points = {},
			segments = {},
		}
		self.byId[id] = stroke
		table.insert(self.items, stroke)
	end

	local item = stroke :: Item
	for i = 1, #points - 1, 2 do
		local x, y = points[i], points[i + 1]
		table.insert(item.points :: { number }, x)
		table.insert(item.points :: { number }, y)
		if item.lastX then
			if x ~= item.lastX or y ~= item.lastY then
				drawSegment(item, self.grid, item.lastX :: number, item.lastY :: number, x, y)
			end
		else
			drawSegment(item, self.grid, x, y, x, y) -- a dot
		end
		item.lastX, item.lastY = x, y
	end
end

-- Bucket fill at (x, y).
function CanvasRenderer.fill(self: Renderer, id: number, colorInt: number, x: number, y: number)
	if self.byId[id] then
		return
	end
	local item: Item = { kind = "fill", id = id, colorInt = colorInt, x = x, y = y, recolored = {} }
	self.byId[id] = item
	table.insert(self.items, item)

	local old, mask = flood(self.grid, x, y, colorInt)
	if not mask then
		return
	end
	local color = CanvasRenderer.toColor(colorInt)
	self.fillLayerZ += 1
	local container = Instance.new("Frame")
	container.Name = `Fill{id}`
	container.BackgroundTransparency = 1
	container.Size = UDim2.fromScale(1, 1)
	container.ZIndex = self.fillLayerZ
	container.Parent = self.fillLayer
	item.container = container
	drawMask(container, mask, color)

	-- Strokes sit above fills, so any stroke pieces that were part of the flooded
	-- colour (e.g. eraser marks on a white background) take the new colour too.
	local recolored = item.recolored :: { any }
	for _, other in self.items do
		if other.kind == "stroke" then
			for _, segment in other.segments :: { Segment } do
				if segment.colorInt == old and buffer.readu8(mask, segment.cell) == 1 then
					table.insert(recolored, { segment = segment, previous = segment.colorInt })
					segment.colorInt = colorInt
					segment.frame.BackgroundColor3 = color
				end
			end
		end
	end
end

-- Rebuilds the grid from the remaining history (after an undo).
function CanvasRenderer._rebuildGrid(self: Renderer)
	resetGrid(self.grid)
	for _, item in self.items do
		if item.kind == "stroke" then
			local points = item.points :: { number }
			local thickness = item.thickness :: number
			for i = 1, #points - 1, 2 do
				local px, py = points[i - 2], points[i - 1]
				if px then
					stamp(self.grid, px, py, points[i], points[i + 1], thickness, item.colorInt)
				else
					stamp(self.grid, points[i], points[i + 1], points[i], points[i + 1], thickness, item.colorInt)
				end
			end
		else
			flood(self.grid, item.x :: number, item.y :: number, item.colorInt)
		end
	end
end

-- Undo: removes a stroke or fill (normally the last one).
function CanvasRenderer.remove(self: Renderer, id: number)
	local item = self.byId[id]
	if not item then
		return
	end
	self.byId[id] = nil
	local index = table.find(self.items, item)
	if index then
		table.remove(self.items, index)
	end
	if item.container then
		item.container:Destroy()
	end
	if item.recolored then
		for i = #item.recolored, 1, -1 do
			local change = item.recolored[i]
			change.segment.colorInt = change.previous
			change.segment.frame.BackgroundColor3 = CanvasRenderer.toColor(change.previous)
		end
	end
	self:_rebuildGrid()
end

function CanvasRenderer.clear(self: Renderer)
	for _, item in self.items do
		if item.container then
			item.container:Destroy()
		end
	end
	table.clear(self.items)
	table.clear(self.byId)
	self.layer = 0
	self.fillLayerZ = 0
	resetGrid(self.grid)
end

return CanvasRenderer
