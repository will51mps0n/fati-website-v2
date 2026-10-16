--!strict
-- The whole neighborhood as plain data, in studs. X grows to the right and Z
-- grows DOWN the screen (the camera looks straight down with -Z as "up").
-- MapBuilder turns this into Parts; tests/ checks it and tools/ draws it.
--
-- Layout: a road runs across the middle and bulges around a small house on an
-- island at the center. One large house sits above the road, a second one
-- below it (the same plan turned 180 degrees, so the map is point-symmetric).

export type Rect = { x1: number, z1: number, x2: number, z2: number }
export type Range = { number }
export type Point = { x: number, z: number }

export type Wall = {
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	horizontal: boolean,
	gaps: { Range }, -- doorway openings along the wall axis
	windows: { Range },
	house: string,
}

export type WallPiece = {
	rect: Rect, -- full footprint including thickness
	window: boolean,
	house: string,
	horizontal: boolean,
}

export type Room = { name: string, floor: string, rect: Rect, house: string }
export type FurnitureSpot = { kind: string, x: number, z: number, rot: number, house: string }
export type House = { id: string, rect: Rect, outline: string, size: string }
export type Bush = { x: number, z: number, r: number, color: string }
export type Door = {
	x: number,
	z: number,
	horizontal: boolean,
	width: number,
	house: string,
	exterior: boolean,
}

local MapLayout = {}

MapLayout.WALL_THICKNESS = 3
MapLayout.WALL_HEIGHT = 12
MapLayout.MAX_WALL_PIECE = 8 -- breakable segment length
MapLayout.BOUNDS = { x1 = -210, z1 = -200, x2 = 210, z2 = 200 } :: Rect

-- Surface heights (top Y) so overlapping flat layers never z-fight.
MapLayout.HEIGHTS = {
	Grass = 0,
	Dirt = 0.05,
	Sidewalk = 0.1,
	Asphalt = 0.15,
	RoadLine = 0.18,
	IslandWalk = 0.2,
	IslandGrass = 0.25,
	Floor = 0.3,
	FloorDetail = 0.33,
	Rug = 0.36,
}

MapLayout.COLORS = {
	Grass = "6DBE4B",
	GrassTuft = "4E9E36",
	Flower = "F48FB1",
	FlowerCenter = "FFE066",
	Pebble = "A0A4A8",
	Twig = "8B6A43",
	Dirt = "9C7148",
	DirtSpeck = "7A5534",
	Sidewalk = "C9CCD1",
	Asphalt = "4D4F55",
	CenterLine = "F2C230",
	EdgeLine = "F4F4F4",
	Wall = "4A4A4A",
	OutlineBlue = "8FD3FF",
	OutlineOrange = "F2A65A",
	Window = "9FD8F5",
	Brick = "D9B88A",
	BrickMortar = "BF9A6A",
	Tile = "9AA9BA",
	TileAlt = "B8C4D1",
	Wood = "A8743F",
	WoodLine = "8E5F31",
	BushGreen = "3FA34D",
	BushOrange = "E8913A",
	ZombiePit = "6B2D2D",
}

local T = MapLayout.WALL_THICKNESS

-- Plans ------------------------------------------------------------------------
-- Plans are in house-local coordinates with (0, 0) at the top-left corner of
-- the wall centerlines.

type PlanWall = { x1: number, z1: number, x2: number, z2: number, gaps: { Range }, windows: { Range } }
type PlanRoom = { name: string, floor: string, x1: number, z1: number, x2: number, z2: number }
type PlanPiece = { kind: string, x: number, z: number, rot: number }
type Plan = {
	w: number,
	d: number,
	walls: { PlanWall },
	rooms: { PlanRoom },
	furniture: { PlanPiece },
	items: { Point },
}

local function wall(
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	gaps: { Range }?,
	windows: { Range }?
): PlanWall
	return { x1 = x1, z1 = z1, x2 = x2, z2 = z2, gaps = gaps or {}, windows = windows or {} }
end

local function room(name: string, floor: string, x1: number, z1: number, x2: number, z2: number): PlanRoom
	return { name = name, floor = floor, x1 = x1, z1 = z1, x2 = x2, z2 = z2 }
end

local function piece(kind: string, x: number, z: number, rot: number?): PlanPiece
	return { kind = kind, x = x, z = z, rot = rot or 0 }
end

-- 140 x 84: bedroom, bathroom and kitchen on top, a hallway across the middle,
-- living and dining rooms at the front (bottom, facing the road).
local LARGE: Plan = {
	w = 140,
	d = 84,
	walls = {
		wall(0, 0, 140, 0, { { 120, 128 } }, { { 8, 20 }, { 30, 42 }, { 56, 72 } }), -- back, kitchen door
		wall(0, 84, 140, 84, { { 15, 23 } }, { { 36, 60 }, { 82, 112 } }), -- front door
		wall(0, 0, 0, 84, nil, { { 8, 28 }, { 56, 76 } }),
		wall(140, 0, 140, 84, { { 38, 46 } }, { { 8, 28 }, { 58, 78 } }), -- hallway side door
		wall(0, 36, 140, 36, { { 20, 27 }, { 61, 68 }, { 105, 112 } }),
		wall(0, 48, 140, 48, { { 30, 37 }, { 100, 107 } }),
		wall(48, 0, 48, 36),
		wall(82, 0, 82, 36),
		wall(70, 48, 70, 84),
	},
	rooms = {
		room("Bedroom", "Wood", 0, 0, 48, 36),
		room("Bathroom", "Tile", 48, 0, 82, 36),
		room("Kitchen", "Tile", 82, 0, 140, 36),
		room("Hallway", "Brick", 0, 36, 140, 48),
		room("Living Room", "Wood", 0, 48, 70, 84),
		room("Dining Room", "Brick", 70, 48, 140, 84),
	},
	furniture = {
		-- Bedroom
		piece("Bed", 7, 8),
		piece("Bookshelf", 30, 3),
		piece("Armchair", 40, 28),
		piece("Box", 16, 29),
		piece("Box", 16, 26),
		piece("Plant", 44, 4),
		piece("Picture", 8, 30),
		-- Bathroom
		piece("Bathtub", 65, 4.5),
		piece("Toilet", 52, 14, 90),
		piece("Toilet", 52, 20, 90),
		piece("Sink", 78.5, 14, 270),
		piece("Box", 76, 30),
		-- Kitchen
		piece("Fridge", 87, 4),
		piece("Stove", 93, 3.5),
		piece("Sink", 99, 3.2),
		piece("Table", 116, 20),
		piece("Chair", 110, 20, 90),
		piece("Chair", 122, 20, 270),
		piece("Chair", 116, 15, 0),
		piece("Chair", 116, 25, 180),
		piece("Box", 134, 30),
		piece("Box", 134, 26.6),
		-- Hallway
		piece("Plant", 4, 40),
		piece("Box", 128, 44),
		-- Living room
		piece("Couch", 38, 64),
		piece("Armchair", 24, 70, 90),
		piece("Rug", 38, 72),
		piece("CoffeeTable", 38, 71),
		piece("Bookshelf", 67, 70, 270),
		piece("Box", 5, 52),
		piece("Box", 8, 52),
		piece("Box", 5, 55),
		piece("Plant", 66, 52),
		-- Dining room
		piece("Table", 104, 66),
		piece("Chair", 98, 66, 90),
		piece("Chair", 110, 66, 270),
		piece("Chair", 104, 61, 0),
		piece("Chair", 104, 71, 180),
		piece("Couch", 122, 78, 180),
		piece("Armchair", 78, 56),
		piece("Box", 136, 52),
		piece("Box", 132.6, 52),
		piece("Plant", 75, 80),
		piece("Picture", 90, 80),
	},
	items = {
		{ x = 24, z = 18 },
		{ x = 70, z = 22 },
		{ x = 100, z = 25 },
		{ x = 40, z = 42 },
		{ x = 90, z = 42 },
		{ x = 52, z = 75 },
		{ x = 88, z = 60 },
	},
}

-- 40 x 28 on the road island: a washroom and a den.
local SMALL: Plan = {
	w = 40,
	d = 28,
	walls = {
		wall(0, 0, 40, 0, { { 28, 35 } }, { { 5, 15 } }),
		wall(0, 28, 40, 28, { { 6, 13 } }, { { 25, 36 } }),
		wall(0, 0, 0, 28, nil, { { 8, 20 } }),
		wall(40, 0, 40, 28, nil, { { 8, 20 } }),
		wall(22, 0, 22, 28, { { 10, 17 } }),
	},
	rooms = {
		room("Washroom", "Tile", 0, 0, 22, 28),
		room("Den", "Wood", 22, 0, 40, 28),
	},
	furniture = {
		piece("Toilet", 4, 4),
		piece("Sink", 17, 3.2),
		piece("Box", 4, 23),
		piece("Couch", 31, 23.5, 180),
		piece("Armchair", 36, 10, 270),
		piece("Box", 26, 4),
	},
	items = {
		{ x = 10, z = 16 },
		{ x = 30, z = 12 },
	},
}

-- Assembly -----------------------------------------------------------------------

local houses: { House } = {}
local walls: { Wall } = {}
local rooms: { Room } = {}
local furniture: { FurnitureSpot } = {}
local itemSpots: { Point } = {}

local function rect(x1: number, z1: number, x2: number, z2: number): Rect
	return { x1 = math.min(x1, x2), z1 = math.min(z1, z2), x2 = math.max(x1, x2), z2 = math.max(z1, z2) }
end

local function addHouse(
	id: string,
	plan: Plan,
	ox: number,
	oz: number,
	rotated: boolean,
	outline: string,
	size: string
)
	local function px(x: number): number
		return ox + (if rotated then plan.w - x else x)
	end
	local function pz(z: number): number
		return oz + (if rotated then plan.d - z else z)
	end
	local function mapRanges(ranges: { Range }, f: (number) -> number): { Range }
		local out = {}
		for _, r in ranges do
			local a, b = f(r[1]), f(r[2])
			table.insert(out, { math.min(a, b), math.max(a, b) })
		end
		table.sort(out, function(a, b)
			return a[1] < b[1]
		end)
		return out
	end

	table.insert(
		houses,
		{ id = id, rect = rect(px(0), pz(0), px(plan.w), pz(plan.d)), outline = outline, size = size }
	)

	for _, w in plan.walls do
		local horizontal = w.z1 == w.z2
		local f = if horizontal then px else pz
		local x1, x2 = math.min(px(w.x1), px(w.x2)), math.max(px(w.x1), px(w.x2))
		local z1, z2 = math.min(pz(w.z1), pz(w.z2)), math.max(pz(w.z1), pz(w.z2))
		table.insert(walls, {
			x1 = x1,
			z1 = z1,
			x2 = x2,
			z2 = z2,
			horizontal = horizontal,
			gaps = mapRanges(w.gaps, f),
			windows = mapRanges(w.windows, f),
			house = id,
		})
	end

	for _, r in plan.rooms do
		table.insert(rooms, {
			name = r.name,
			floor = r.floor,
			rect = rect(px(r.x1), pz(r.z1), px(r.x2), pz(r.z2)),
			house = id,
		})
	end

	for _, p in plan.furniture do
		local rot = if rotated then (p.rot + 180) % 360 else p.rot
		table.insert(furniture, { kind = p.kind, x = px(p.x), z = pz(p.z), rot = rot, house = id })
	end

	for _, spot in plan.items do
		table.insert(itemSpots, { x = px(spot.x), z = pz(spot.z) })
	end
end

addHouse("North", LARGE, -110, -150, false, "Blue", "Large")
addHouse("South", LARGE, -30, 66, true, "Orange", "Large")
addHouse("Island", SMALL, -20, -14, false, "Blue", "Small")

-- Point reflection through the map center, used to mirror the yards.
local function mirrorRect(r: Rect): Rect
	return rect(-r.x2, -r.z2, -r.x1, -r.z1)
end

local function withMirror(list: { Rect }): { Rect }
	local out = table.clone(list)
	for _, r in list do
		table.insert(out, mirrorRect(r))
	end
	return out
end

local function withMirrorPoints(list: { Point }): { Point }
	local out = table.clone(list)
	for _, p in list do
		table.insert(out, { x = -p.x, z = -p.z })
	end
	return out
end

-- Road ---------------------------------------------------------------------------------

local B = MapLayout.BOUNDS

MapLayout.road = {
	-- Drawn in this order; later layers sit higher (see HEIGHTS).
	sidewalks = {
		rect(B.x1, -20, B.x2, 20),
		rect(-52, -46, 52, 46),
	},
	asphalt = {
		rect(B.x1, -14, B.x2, 14),
		rect(-46, -40, 46, 40),
	},
	centerLines = {
		rect(B.x1, -0.8, -46, -0.4),
		rect(B.x1, 0.4, -46, 0.8),
		rect(46, -0.8, B.x2, -0.4),
		rect(46, 0.4, B.x2, 0.8),
	},
	edgeLines = {
		rect(B.x1, -13.2, -46, -12.8),
		rect(46, -13.2, B.x2, -12.8),
		rect(B.x1, 12.8, -46, 13.2),
		rect(46, 12.8, B.x2, 13.2),
		rect(-45, -39.2, 45, -38.8),
		rect(-45, 38.8, 45, 39.2),
		rect(-45.2, -39, -44.8, -13),
		rect(44.8, -39, 45.2, -13),
		rect(-45.2, 13, -44.8, 39),
		rect(44.8, 13, 45.2, 39),
	},
	islandWalk = rect(-30, -24, 30, 24),
	islandGrass = rect(-27, -21, 27, 21),
}

-- Dirt paths from the doors out to the sidewalks, plus a back garden.
MapLayout.paths = withMirror({
	rect(-95, -66, -87, -20), -- north front door
	rect(30, -112, 64, -104), -- north side door, east...
	rect(56, -112, 64, -20), -- ...then down to the road
	rect(10, -180, 18, -150), -- north kitchen door
	rect(0, -192, 28, -180), -- garden patch
})

-- Bushes block movement. The south yard mirrors the north one, colors swapped.
do
	local north: { Bush } = {
		{ x = -130, z = -130, r = 4, color = "Green" },
		{ x = -150, z = -80, r = 5, color = "Green" },
		{ x = -125, z = -165, r = 4, color = "Orange" },
		{ x = -180, z = -182, r = 6, color = "Green" },
		{ x = -60, z = -176, r = 5, color = "Green" },
		{ x = 45, z = -170, r = 4, color = "Orange" },
		{ x = 95, z = -150, r = 6, color = "Green" },
		{ x = 140, z = -120, r = 5, color = "Orange" },
		{ x = 110, z = -62, r = 4, color = "Green" },
		{ x = 170, z = -170, r = 5, color = "Green" },
		{ x = 185, z = -80, r = 4, color = "Orange" },
		{ x = -186, z = -112, r = 4, color = "Orange" },
		{ x = -70, z = -40, r = 3, color = "Green" },
		{ x = 20, z = -56, r = 3, color = "Orange" },
	}
	local all = table.clone(north)
	for _, bush in north do
		table.insert(all, {
			x = -bush.x,
			z = -bush.z,
			r = bush.r,
			color = if bush.color == "Green" then "Orange" else "Green",
		})
	end
	MapLayout.bushes = all
end

MapLayout.humanSpawns = withMirrorPoints({
	{ x = -160, z = -140 },
	{ x = -72, z = -190 },
	{ x = 75, z = -186 },
	{ x = 130, z = -160 },
	{ x = 165, z = -45 },
	{ x = -165, z = -45 },
	{ x = -35, z = -56 },
	{ x = 95, z = -95 },
})

MapLayout.zombieSpawns = {
	{ x = -195, z = 0 },
	{ x = 195, z = 0 },
}

MapLayout.wizardSpots = withMirrorPoints({
	{ x = -120, z = -186 },
	{ x = 160, z = -100 },
	{ x = -178, z = -150 },
})

MapLayout.houses = houses
MapLayout.walls = walls
MapLayout.rooms = rooms
MapLayout.furniture = furniture
MapLayout.itemSpots = itemSpots

-- Derived geometry -------------------------------------------------------------------------

-- Splits a wall into solid pieces no longer than MAX_WALL_PIECE, skipping the
-- doorway gaps and splitting at window edges so each piece is fully a window
-- or fully plain wall.
function MapLayout.wallPieces(w: Wall): { WallPiece }
	local h = T / 2
	local a = (if w.horizontal then w.x1 else w.z1) - h
	local b = (if w.horizontal then w.x2 else w.z2) + h
	local across = if w.horizontal then w.z1 else w.x1

	-- Solid spans = [a, b] minus gaps.
	local spans: { Range } = {}
	local cursor = a
	for _, gap in w.gaps do
		if gap[1] > cursor then
			table.insert(spans, { cursor, gap[1] })
		end
		cursor = math.max(cursor, gap[2])
	end
	if cursor < b then
		table.insert(spans, { cursor, b })
	end

	-- Cut points at window edges.
	local cuts: { number } = {}
	for _, win in w.windows do
		table.insert(cuts, win[1])
		table.insert(cuts, win[2])
	end

	local pieces: { WallPiece } = {}
	for _, span in spans do
		local stops = { span[1] }
		for _, c in cuts do
			if c > span[1] + 0.01 and c < span[2] - 0.01 then
				table.insert(stops, c)
			end
		end
		table.insert(stops, span[2])
		table.sort(stops)
		for i = 1, #stops - 1 do
			local s, e = stops[i], stops[i + 1]
			local mid = (s + e) / 2
			local isWindow = false
			for _, win in w.windows do
				if mid > win[1] and mid < win[2] then
					isWindow = true
				end
			end
			local count = math.max(1, math.ceil((e - s) / MapLayout.MAX_WALL_PIECE - 0.001))
			local step = (e - s) / count
			for k = 0, count - 1 do
				local p1, p2 = s + step * k, s + step * (k + 1)
				local r = if w.horizontal
					then rect(p1, across - h, p2, across + h)
					else rect(across - h, p1, across + h, p2)
				table.insert(
					pieces,
					{ rect = r, window = isWindow, house = w.house, horizontal = w.horizontal }
				)
			end
		end
	end
	return pieces
end

function MapLayout.allWallPieces(): { WallPiece }
	local out = {}
	for _, w in walls do
		for _, p in MapLayout.wallPieces(w) do
			table.insert(out, p)
		end
	end
	return out
end

-- Every doorway, at the center of its gap.
function MapLayout.doors(): { Door }
	local out = {}
	for _, w in walls do
		for _, gap in w.gaps do
			local mid = (gap[1] + gap[2]) / 2
			local house: House? = nil
			for _, hs in houses do
				if hs.id == w.house then
					house = hs
				end
			end
			local exterior = false
			if house then
				local r = house.rect
				exterior = if w.horizontal
					then (w.z1 == r.z1 or w.z1 == r.z2)
					else (w.x1 == r.x1 or w.x1 == r.x2)
			end
			table.insert(out, {
				x = if w.horizontal then mid else w.x1,
				z = if w.horizontal then w.z1 else mid,
				horizontal = w.horizontal,
				width = gap[2] - gap[1],
				house = w.house,
				exterior = exterior,
			})
		end
	end
	return out
end

-- Footprint of a furniture spot given its size.
function MapLayout.footprint(spot: FurnitureSpot, width: number, depth: number): Rect
	return rect(spot.x - width / 2, spot.z - depth / 2, spot.x + width / 2, spot.z + depth / 2)
end

-- The walkable inside of a room (wall centerlines pulled in by half a wall).
function MapLayout.roomInterior(r: Room): Rect
	local h = T / 2
	return rect(r.rect.x1 + h, r.rect.z1 + h, r.rect.x2 - h, r.rect.z2 - h)
end

-- Areas where grass decorations must not go.
function MapLayout.noDecorRects(): { Rect }
	local out: { Rect } = {}
	for _, hs in houses do
		local r = hs.rect
		table.insert(out, rect(r.x1 - 3, r.z1 - 3, r.x2 + 3, r.z2 + 3))
	end
	for _, r in MapLayout.road.sidewalks do
		table.insert(out, r)
	end
	for _, r in MapLayout.paths do
		table.insert(out, r)
	end
	for _, bush in MapLayout.bushes do
		table.insert(
			out,
			rect(bush.x - bush.r - 1, bush.z - bush.r - 1, bush.x + bush.r + 1, bush.z + bush.r + 1)
		)
	end
	return out
end

function MapLayout.inRect(r: Rect, x: number, z: number, margin: number?): boolean
	local m = margin or 0
	return x >= r.x1 - m and x <= r.x2 + m and z >= r.z1 - m and z <= r.z2 + m
end

function MapLayout.rectsOverlap(a: Rect, b: Rect, margin: number?): boolean
	local m = margin or 0
	return a.x1 < b.x2 + m and b.x1 < a.x2 + m and a.z1 < b.z2 + m and b.z1 < a.z2 + m
end

return MapLayout
