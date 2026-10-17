--!strict
-- Every map as plain data, in studs. X grows to the right and Z grows DOWN
-- the screen (the camera looks straight down with -Z as "up"). MapBuilder
-- turns a layout into Parts; tests/ checks every layout and tools/ draws them.
--
-- Neighborhood: a road across the middle bulging around a small island
-- house, with a large house above and the same plan turned 180 degrees below.
-- Mansion: one big house modeled on the original's (orange brick rooms,
-- a concrete garage), a pool and an orange shed out back, the road in front.

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
export type Island = { walk: Rect, grass: Rect }

export type Layout = {
	name: string,
	title: string,
	bounds: Rect,
	houses: { House },
	walls: { Wall },
	rooms: { Room },
	furniture: { FurnitureSpot },
	itemSpots: { Point },
	road: { sidewalks: { Rect }, asphalt: { Rect }, centerLines: { Rect }, edgeLines: { Rect } },
	islands: { Island },
	paths: { Rect },
	patios: { Rect },
	pools: { Rect },
	bushes: { Bush },
	humanSpawns: { Point },
	zombieSpawns: { Point },
	wizardSpots: { Point },
}

local MapLayout = {}

MapLayout.WALL_THICKNESS = 3
MapLayout.WALL_HEIGHT = 12
MapLayout.MAX_WALL_PIECE = 8 -- breakable segment length

-- Surface heights (top Y) so overlapping flat layers never z-fight.
MapLayout.HEIGHTS = {
	Grass = 0,
	Dirt = 0.05,
	Sidewalk = 0.1,
	Patio = 0.12,
	Asphalt = 0.15,
	RoadLine = 0.18,
	IslandWalk = 0.2,
	IslandGrass = 0.25,
	Floor = 0.3,
	FloorDetail = 0.33,
	Rug = 0.36,
	PoolRim = 0.45,
}

-- Picked from screenshots of the original.
MapLayout.COLORS = {
	Grass = "4FB35F",
	GrassTuft = "3E9A4E",
	Flower = "F48FB1",
	FlowerCenter = "FFE066",
	Pebble = "9EA7AD",
	Twig = "8B6A43",
	Dirt = "C27B45",
	DirtSpeck = "A86434",
	Sidewalk = "A9BEC4",
	SidewalkSpeck = "93A9B0",
	Asphalt = "474749",
	CenterLine = "F2C230",
	EdgeLine = "F4F4F4",
	Wall = "4A4A4A",
	OutlineBlue = "A3CCDB",
	OutlineOrange = "E8762C",
	Window = "BFE6F5",
	Brick = "D88B53",
	BrickMortar = "EDBB8E",
	Tile = "9EB1BE",
	TileAlt = "B9C8D2",
	Wood = "B07A45",
	WoodLine = "8E5F31",
	Concrete = "BCC3C8",
	ConcreteSpeck = "A5ADB3",
	PoolWater = "4FB3E8",
	PoolRim = "E6EEF2",
	BushGreen = "43A85A",
	BushOrange = "E8913A",
	ZombiePit = "6B2D2D",
}

local T = MapLayout.WALL_THICKNESS

-- Plans ------------------------------------------------------------------------------
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

local function rect(x1: number, z1: number, x2: number, z2: number): Rect
	return { x1 = math.min(x1, x2), z1 = math.min(z1, z2), x2 = math.max(x1, x2), z2 = math.max(z1, z2) }
end

local function pt(x: number, z: number): Point
	return { x = x, z = z }
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
		piece("Wardrobe", 16, 3.3),
		piece("Bookshelf", 30, 3),
		piece("Dresser", 45.2, 14, 270),
		piece("Desk", 36, 18),
		piece("Lamp", 12, 14.5),
		piece("Armchair", 40, 28),
		piece("Box", 16, 29),
		piece("Box", 16, 26),
		piece("Plant", 44, 4),
		piece("Picture", 8, 30),
		piece("Beanbag", 28, 28),
		-- Bathroom
		piece("Bathtub", 65, 4.5),
		piece("Toilet", 52, 14, 90),
		piece("Toilet", 52, 20, 90),
		piece("Sink", 78.5, 14, 270),
		piece("Washer", 78.5, 22),
		piece("Box", 76, 30),
		-- Kitchen
		piece("Fridge", 87, 4),
		piece("Stove", 93, 3.5),
		piece("Sink", 99, 3.2),
		piece("Crate", 106, 4),
		piece("Barrel", 137, 4),
		piece("TrashCan", 131, 4),
		piece("Table", 116, 20),
		piece("Chair", 110, 20, 90),
		piece("Chair", 122, 20, 270),
		piece("Chair", 116, 15, 0),
		piece("Chair", 116, 25, 180),
		piece("Box", 134, 30),
		piece("Box", 134, 26.6),
		-- Hallway
		piece("Plant", 4, 40),
		piece("Lamp", 80, 43),
		piece("Box", 128, 44),
		-- Living room
		piece("Couch", 38, 64),
		piece("Armchair", 24, 70, 90),
		piece("Rug", 38, 72),
		piece("CoffeeTable", 38, 71),
		piece("Bookshelf", 67, 70, 270),
		piece("Piano", 52, 79.5),
		piece("TVStand", 52, 50.6),
		piece("Lamp", 28, 60),
		piece("Aquarium", 8, 81),
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
		piece("PoolTable", 122, 60),
		piece("Couch", 122, 78, 180),
		piece("Armchair", 78, 56),
		piece("Crate", 88, 56),
		piece("Arcade", 136, 66),
		piece("Box", 136, 52),
		piece("Box", 132.6, 52),
		piece("Plant", 75, 80),
		piece("Picture", 90, 80),
	},
	items = {
		pt(24, 18),
		pt(70, 22),
		pt(100, 25),
		pt(40, 42),
		pt(90, 42),
		pt(40, 76),
		pt(88, 66),
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
		piece("Barrel", 17, 24),
		piece("Couch", 31, 23.5, 180),
		piece("Armchair", 36, 10, 270),
		piece("Box", 26, 4),
	},
	items = { pt(10, 16), pt(30, 12) },
}

-- 200 x 130, modeled on the original's big house: bedroom, bathroom, study
-- and kitchen at the back, a long hallway, then living room, laundry, entry
-- hall, game room and a concrete garage at the front.
local MANSION: Plan = {
	w = 200,
	d = 130,
	walls = {
		wall(
			0,
			0,
			200,
			0,
			{ { 168, 176 } },
			{ { 8, 24 }, { 34, 50 }, { 62, 86 }, { 100, 132 }, { 146, 162 }, { 180, 194 } }
		),
		wall(
			0,
			130,
			200,
			130,
			{ { 96, 104 }, { 170, 178 } },
			{ { 10, 28 }, { 40, 62 }, { 112, 140 }, { 154, 164 }, { 184, 194 } }
		),
		wall(0, 0, 0, 130, { { 59, 67 } }, { { 10, 46 }, { 80, 120 } }),
		wall(200, 0, 200, 130, nil, { { 10, 46 }, { 80, 120 } }),
		wall(0, 56, 200, 56, { { 24, 31 }, { 70, 77 }, { 112, 119 }, { 160, 167 } }),
		wall(0, 70, 200, 70, { { 30, 37 }, { 77, 84 }, { 96.5, 103.5 }, { 125, 132 }, { 160, 167 } }),
		wall(56, 0, 56, 56, { { 40, 47 } }),
		wall(92, 0, 92, 56),
		wall(140, 0, 140, 56),
		wall(70, 70, 70, 130),
		wall(92, 70, 92, 130),
		wall(108, 70, 108, 130),
		wall(150, 70, 150, 130),
	},
	rooms = {
		room("Master Bedroom", "Brick", 0, 0, 56, 56),
		room("Bathroom", "Tile", 56, 0, 92, 56),
		room("Study", "Wood", 92, 0, 140, 56),
		room("Kitchen", "Tile", 140, 0, 200, 56),
		room("Hallway", "Brick", 0, 56, 200, 70),
		room("Living Room", "Wood", 0, 70, 70, 130),
		room("Laundry", "Tile", 70, 70, 92, 130),
		room("Entry", "Brick", 92, 70, 108, 130),
		room("Game Room", "Wood", 108, 70, 150, 130),
		room("Garage", "Concrete", 150, 70, 200, 130),
	},
	furniture = {
		-- Master bedroom
		piece("Bed", 10, 8),
		piece("Bed", 20, 8),
		piece("Rug", 16, 22),
		piece("Wardrobe", 40, 3.3),
		piece("Dresser", 53.3, 22, 270),
		piece("Armchair", 44, 34),
		piece("Lamp", 5, 20),
		piece("Box", 6, 50),
		piece("Box", 9, 50),
		piece("Plant", 51, 4),
		piece("Desk", 44, 48),
		-- Bathroom
		piece("Bathtub", 74, 4.5),
		piece("Toilet", 61, 20, 90),
		piece("Toilet", 61, 27, 90),
		piece("Sink", 88.5, 20, 270),
		piece("Sink", 88.5, 28, 270),
		piece("Washer", 88, 46),
		piece("Box", 80, 50),
		-- Study
		piece("Bookshelf", 104, 3),
		piece("Bookshelf", 116, 3),
		piece("Bookshelf", 128, 3),
		piece("Rug", 116, 40),
		piece("Desk", 106, 24),
		piece("Chair", 106, 28, 180),
		piece("Piano", 128, 30),
		piece("Armchair", 98, 46),
		piece("Plant", 136, 52),
		piece("Box", 96, 30),
		piece("Aquarium", 98, 36, 90),
		-- Kitchen
		piece("Fridge", 148, 4),
		piece("Fridge", 153, 4),
		piece("Stove", 159, 3.5),
		piece("Sink", 186, 3.2),
		piece("Table", 170, 28),
		piece("Chair", 164, 28, 90),
		piece("Chair", 176, 28, 270),
		piece("Chair", 170, 23, 0),
		piece("Chair", 170, 33, 180),
		piece("Crate", 194, 50),
		piece("Barrel", 145, 50),
		piece("TrashCan", 186, 50),
		piece("Box", 196, 16),
		piece("Box", 196, 19.2),
		-- Hallway
		piece("Plant", 196, 60),
		piece("Bench", 145, 67),
		piece("Lamp", 50, 59),
		-- Living room
		piece("Couch", 30, 100),
		piece("Couch", 14, 110, 90),
		piece("Armchair", 48, 110, 270),
		piece("Rug", 30, 109),
		piece("CoffeeTable", 30, 108),
		piece("TVStand", 30, 127),
		piece("Piano", 55, 80),
		piece("Bookshelf", 2.6, 86, 90),
		piece("Plant", 66, 126),
		piece("Box", 64, 74),
		piece("Lamp", 6, 126),
		piece("Beanbag", 50, 122),
		-- Laundry
		piece("Washer", 74, 90),
		piece("Washer", 74, 94),
		piece("Crate", 75, 120),
		piece("Box", 88, 126),
		piece("Box", 88, 122.9),
		-- Entry
		piece("Plant", 95.5, 77),
		piece("Lamp", 105, 110),
		-- Game room
		piece("PoolTable", 129, 100),
		piece("Couch", 129, 125, 180),
		piece("Armchair", 114, 80),
		piece("TVStand", 147, 100, 90),
		piece("Barrel", 113, 124),
		piece("Bookshelf", 140, 73.5),
		piece("Lamp", 146, 124),
		piece("Arcade", 144.5, 116),
		-- Garage
		piece("Car", 174, 98),
		piece("Crate", 155, 75),
		piece("Crate", 155, 79),
		piece("Barrel", 196, 74),
		piece("Barrel", 196, 77.2),
		piece("Box", 155, 126),
		piece("Box", 158, 126),
		piece("Desk", 195, 110, 270),
		piece("Crate", 196, 126),
		piece("VendingMachine", 196.5, 90, 270),
		piece("Treadmill", 158, 105),
	},
	items = {
		pt(30, 40),
		pt(75, 38),
		pt(115, 16),
		pt(185, 42),
		pt(100, 63),
		pt(45, 90),
		pt(120, 112),
		pt(160, 112),
		pt(100, 96),
	},
}

-- 36 x 26 garden shed with an orange outline.
local SHED: Plan = {
	w = 36,
	d = 26,
	walls = {
		wall(0, 0, 36, 0, nil, { { 6, 30 } }),
		wall(0, 26, 36, 26, { { 14, 22 } }),
		wall(0, 0, 0, 26, { { 9, 17 } }),
		wall(36, 0, 36, 26, nil, { { 6, 20 } }),
	},
	rooms = { room("Shed", "Wood", 0, 0, 36, 26) },
	furniture = {
		piece("Crate", 5, 5),
		piece("Crate", 9, 5),
		piece("Barrel", 31, 4.5),
		piece("Bench", 18, 3),
		piece("Desk", 26, 21),
		piece("Box", 31, 22),
	},
	items = { pt(18, 14) },
}

-- Assembly -------------------------------------------------------------------------------

local function newLayout(name: string, title: string): Layout
	return {
		name = name,
		title = title,
		bounds = rect(-210, -200, 210, 200),
		houses = {},
		walls = {},
		rooms = {},
		furniture = {},
		itemSpots = {},
		road = { sidewalks = {}, asphalt = {}, centerLines = {}, edgeLines = {} },
		islands = {},
		paths = {},
		patios = {},
		pools = {},
		bushes = {},
		humanSpawns = {},
		zombieSpawns = {},
		wizardSpots = {},
	}
end

local function addHouse(
	layout: Layout,
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
		layout.houses,
		{ id = id, rect = rect(px(0), pz(0), px(plan.w), pz(plan.d)), outline = outline, size = size }
	)

	for _, w in plan.walls do
		local horizontal = w.z1 == w.z2
		local f = if horizontal then px else pz
		table.insert(layout.walls, {
			x1 = math.min(px(w.x1), px(w.x2)),
			z1 = math.min(pz(w.z1), pz(w.z2)),
			x2 = math.max(px(w.x1), px(w.x2)),
			z2 = math.max(pz(w.z1), pz(w.z2)),
			horizontal = horizontal,
			gaps = mapRanges(w.gaps, f),
			windows = mapRanges(w.windows, f),
			house = id,
		})
	end

	for _, r in plan.rooms do
		table.insert(layout.rooms, {
			name = r.name,
			floor = r.floor,
			rect = rect(px(r.x1), pz(r.z1), px(r.x2), pz(r.z2)),
			house = id,
		})
	end

	for _, p in plan.furniture do
		local rot = if rotated then (p.rot + 180) % 360 else p.rot
		table.insert(layout.furniture, { kind = p.kind, x = px(p.x), z = pz(p.z), rot = rot, house = id })
	end

	for _, spot in plan.items do
		table.insert(layout.itemSpots, pt(px(spot.x), pz(spot.z)))
	end
end

-- Point reflection through the map center, used to mirror yards.
local function mirrorRects(list: { Rect }): { Rect }
	local out = table.clone(list)
	for _, r in list do
		table.insert(out, rect(-r.x2, -r.z2, -r.x1, -r.z1))
	end
	return out
end

local function mirrorPoints(list: { Point }): { Point }
	local out = table.clone(list)
	for _, p in list do
		table.insert(out, pt(-p.x, -p.z))
	end
	return out
end

local function bush(x: number, z: number, r: number, color: string): Bush
	return { x = x, z = z, r = r, color = color }
end

-- Neighborhood ------------------------------------------------------------------------------

local function buildNeighborhood(): Layout
	local layout = newLayout("Neighborhood", "The Neighborhood")
	local B = layout.bounds
	addHouse(layout, "North", LARGE, -110, -150, false, "Blue", "Large")
	addHouse(layout, "South", LARGE, -30, 66, true, "Orange", "Large")
	addHouse(layout, "Island", SMALL, -20, -14, false, "Blue", "Small")

	layout.road = {
		sidewalks = { rect(B.x1, -20, B.x2, 20), rect(-52, -46, 52, 46) },
		asphalt = { rect(B.x1, -14, B.x2, 14), rect(-46, -40, 46, 40) },
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
	}
	layout.islands = { { walk = rect(-30, -24, 30, 24), grass = rect(-27, -21, 27, 21) } }

	layout.paths = mirrorRects({
		rect(-95, -66, -87, -20), -- north front door
		rect(30, -112, 64, -104), -- north side door, east...
		rect(56, -112, 64, -20), -- ...then down to the road
		rect(10, -180, 18, -150), -- north kitchen door
		rect(0, -192, 28, -180), -- garden patch
	})

	local north = {
		bush(-130, -130, 4, "Green"),
		bush(-150, -80, 5, "Green"),
		bush(-125, -165, 4, "Orange"),
		bush(-180, -182, 6, "Green"),
		bush(-60, -176, 5, "Green"),
		bush(45, -170, 4, "Orange"),
		bush(95, -150, 6, "Green"),
		bush(140, -120, 5, "Orange"),
		bush(110, -62, 4, "Green"),
		bush(170, -170, 5, "Green"),
		bush(185, -80, 4, "Orange"),
		bush(-186, -112, 4, "Orange"),
		bush(-70, -40, 3, "Green"),
		bush(20, -56, 3, "Orange"),
	}
	for _, b in north do
		table.insert(layout.bushes, b)
		table.insert(layout.bushes, bush(-b.x, -b.z, b.r, if b.color == "Green" then "Orange" else "Green"))
	end

	layout.humanSpawns = mirrorPoints({
		pt(-160, -140),
		pt(-72, -190),
		pt(75, -186),
		pt(130, -160),
		pt(165, -45),
		pt(-165, -45),
		pt(-35, -56),
		pt(95, -95),
	})
	layout.zombieSpawns = { pt(-195, 0), pt(195, 0) }
	layout.wizardSpots = mirrorPoints({ pt(-120, -186), pt(160, -100), pt(-178, -150) })
	return layout
end

-- Mansion ----------------------------------------------------------------------------------

local function buildMansion(): Layout
	local layout = newLayout("Mansion", "The Mansion")
	local B = layout.bounds
	addHouse(layout, "Mansion", MANSION, -100, -40, false, "Blue", "Huge")
	addHouse(layout, "Shed", SHED, 110, -120, false, "Orange", "Small")

	layout.road = {
		sidewalks = { rect(B.x1, 142, B.x2, 182) },
		asphalt = { rect(B.x1, 148, B.x2, 176) },
		centerLines = { rect(B.x1, 161.4, B.x2, 161.8), rect(B.x1, 162.2, B.x2, 162.6) },
		edgeLines = { rect(B.x1, 149, B.x2, 149.4), rect(B.x1, 174.6, B.x2, 175) },
	}

	layout.paths = {
		rect(-4, 90, 4, 142), -- front door to the sidewalk
		rect(-150, 19, -100, 27), -- side door, west...
		rect(-150, 19, -142, 142), -- ...then down to the road
		rect(100, -111, 110, -103), -- patio to the shed door
		rect(124, -94, 132, -60), -- shed front door, north...
		rect(124, -60, 160, -52), -- ...and around to the yard
	}
	layout.patios = {
		rect(66, 90, 82, 142), -- driveway from the garage
		rect(-60, -110, 100, -50), -- pool deck behind the kitchen
		rect(68, -50, 76, -40), -- kitchen back door step
	}
	layout.pools = { rect(-40, -95, 40, -65) }

	layout.bushes = {
		bush(-150, -150, 6, "Green"),
		bush(-110, -175, 4, "Orange"),
		bush(-180, -90, 5, "Green"),
		bush(-185, -20, 4, "Orange"),
		bush(-180, 60, 5, "Green"),
		bush(-60, 125, 4, "Green"),
		bush(-30, 110, 3, "Orange"),
		bush(40, 112, 4, "Green"),
		bush(120, 120, 5, "Orange"),
		bush(160, 100, 4, "Green"),
		bush(185, 40, 5, "Green"),
		bush(185, -40, 4, "Orange"),
		bush(180, -150, 6, "Green"),
		bush(60, -170, 5, "Orange"),
		bush(-20, -170, 4, "Green"),
		bush(150, -175, 4, "Orange"),
	}

	layout.humanSpawns = {
		pt(-60, 116),
		pt(30, 128),
		pt(150, 125),
		pt(-170, 100),
		pt(-180, 25),
		pt(180, 70),
		pt(175, 5),
		pt(-170, -60),
		pt(170, -100),
		pt(-120, -160),
		pt(0, -150),
		pt(100, -170),
		pt(-80, 100),
		pt(110, 105),
	}
	layout.zombieSpawns = { pt(-195, 162), pt(195, 162) }
	layout.wizardSpots = { pt(-130, -130), pt(160, -20), pt(-160, 128), pt(40, -180) }
	return layout
end

MapLayout.maps = {
	Neighborhood = buildNeighborhood(),
	Mansion = buildMansion(),
} :: { [string]: Layout }
MapLayout.names = { "Neighborhood", "Mansion" }

local current: Layout = MapLayout.maps.Neighborhood

function MapLayout.current(): Layout
	return current
end

function MapLayout.get(name: string): Layout?
	return MapLayout.maps[name]
end

function MapLayout.use(name: string): Layout
	current = MapLayout.maps[name] or MapLayout.maps.Neighborhood
	return current
end

-- Derived geometry ------------------------------------------------------------------------

-- Splits a wall into solid pieces no longer than MAX_WALL_PIECE, skipping the
-- doorway gaps and splitting at window edges so each piece is fully a window
-- or fully plain wall.
function MapLayout.wallPieces(w: Wall): { WallPiece }
	local h = T / 2
	local a = (if w.horizontal then w.x1 else w.z1) - h
	local b = (if w.horizontal then w.x2 else w.z2) + h
	local across = if w.horizontal then w.z1 else w.x1

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

function MapLayout.allWallPieces(layout: Layout): { WallPiece }
	local out = {}
	for _, w in layout.walls do
		for _, p in MapLayout.wallPieces(w) do
			table.insert(out, p)
		end
	end
	return out
end

-- Every doorway, at the center of its gap.
function MapLayout.doors(layout: Layout): { Door }
	local out = {}
	for _, w in layout.walls do
		local house: House? = nil
		for _, hs in layout.houses do
			if hs.id == w.house then
				house = hs
			end
		end
		for _, gap in w.gaps do
			local mid = (gap[1] + gap[2]) / 2
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

function MapLayout.footprint(spot: FurnitureSpot, width: number, depth: number): Rect
	return rect(spot.x - width / 2, spot.z - depth / 2, spot.x + width / 2, spot.z + depth / 2)
end

-- The walkable inside of a room (wall centerlines pulled in by half a wall).
function MapLayout.roomInterior(r: Room): Rect
	local h = T / 2
	return rect(r.rect.x1 + h, r.rect.z1 + h, r.rect.x2 - h, r.rect.z2 - h)
end

-- Areas where grass decorations must not go.
function MapLayout.noDecorRects(layout: Layout): { Rect }
	local out: { Rect } = {}
	for _, hs in layout.houses do
		local r = hs.rect
		table.insert(out, rect(r.x1 - 3, r.z1 - 3, r.x2 + 3, r.z2 + 3))
	end
	for _, list in { layout.road.sidewalks, layout.paths, layout.patios, layout.pools } do
		for _, r in list do
			table.insert(out, r)
		end
	end
	for _, b in layout.bushes do
		table.insert(out, rect(b.x - b.r - 1, b.z - b.r - 1, b.x + b.r + 1, b.z + b.r + 1))
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
