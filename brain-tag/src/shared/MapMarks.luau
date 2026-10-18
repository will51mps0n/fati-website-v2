--!strict
-- Maps you build in Roblox Studio, as plain data. Every part in a map folder
-- is a "mark": its name says what it is (Wall, Door, Floor, HumanSpawn,
-- Couch...) and its footprint seen from above says where. toLayout turns
-- marks into a Layout (what the built-in maps are made of), fromLayout does
-- the reverse so a built-in map can be copied into Studio and edited.
-- Reading and making the actual parts is the server's MapStudio; README
-- "Making your own maps" explains it all for map makers.

local FurnitureSpecs = require(script.Parent.FurnitureSpecs)
local MapLayout = require(script.Parent.MapLayout)

type Layout = MapLayout.Layout
type Rect = MapLayout.Rect
type Range = MapLayout.Range
type Point = MapLayout.Point

local MapMarks = {}

export type Mark = {
	kind: string,
	x: number, -- center of the footprint
	z: number,
	w: number, -- footprint size along X
	d: number, -- footprint size along Z
	rot: number, -- furniture: degrees turned about the vertical
	id: string?, -- House: its name; Floor: the room's name
	floor: string?, -- Floor: Brick, Tile, Wood, Concrete or Dirt
	outline: string?, -- House: Blue or Orange wall trim
	color: string?, -- Bush: Green, Orange or Cobweb
}

-- Every kind of mark besides furniture (any furniture name is a mark too).
MapMarks.KINDS = {
	{ kind = "Bounds", about = "The play area. A brick wall goes around it. One per map." },
	{
		kind = "House",
		about = "A house's outline: walls inside get its trim color (Outline: Blue or Orange).",
	},
	{ kind = "Wall", about = "A wall. Long and thin; it is always rebuilt 3 studs thick." },
	{ kind = "Door", about = "Put it on a wall to cut a doorway as wide as the part." },
	{ kind = "Window", about = "Put it on a wall: that stretch becomes a (breakable) window." },
	{
		kind = "SecretWall",
		about = "Put it on a wall: that stretch looks solid but anyone walks through (bots don't know).",
	},
	{ kind = "Floor", about = "A room's floor (Floor attribute: Brick, Tile, Wood, Concrete or Dirt)." },
	{ kind = "HumanSpawn", about = "Where humans appear after the first spawn." },
	{ kind = "ZombieSpawn", about = "Where zombies appear (a red pit)." },
	{ kind = "Start", about = "Where everyone starts the round, together." },
	{ kind = "ItemSpot", about = "Where an item can lie on the ground." },
	{ kind = "WizardSpot", about = "Where the wizard can show up." },
	{ kind = "Bush", about = "A bush to hide in (Color attribute: Green, Orange or Cobweb for indoors)." },
	{ kind = "Road", about = "Asphalt." },
	{ kind = "Sidewalk", about = "Pale pavement." },
	{ kind = "CenterLine", about = "Yellow road line." },
	{ kind = "EdgeLine", about = "White road line." },
	{ kind = "Path", about = "A dirt path." },
	{ kind = "Patio", about = "Stone paving." },
	{ kind = "Pool", about = "A swimming pool." },
	{ kind = "IslandWalk", about = "A raised pavement island." },
	{ kind = "IslandGrass", about = "Grass on top of an island." },
}

local KNOWN: { [string]: boolean } = {}
for _, entry in MapMarks.KINDS do
	KNOWN[entry.kind] = true
end

MapMarks.FLOORS = { "Brick", "Tile", "Wood", "Concrete", "Dirt" }

local T = MapLayout.WALL_THICKNESS

-- True for any name the game turns into map data (marks and furniture).
function MapMarks.isKind(name: string): boolean
	return KNOWN[name] == true or MapMarks.isFurniture(name)
end

function MapMarks.isFurniture(name: string): boolean
	return FurnitureSpecs.specs[name] ~= nil
end

local function rectOf(m: Mark): Rect
	return { x1 = m.x - m.w / 2, z1 = m.z - m.d / 2, x2 = m.x + m.w / 2, z2 = m.z + m.d / 2 }
end

local function pointOf(m: Mark): Point
	return { x = m.x, z = m.z }
end

local function merged(ranges: { Range }): { Range }
	table.sort(ranges, function(a, b)
		return a[1] < b[1]
	end)
	local out: { Range } = {}
	for _, r in ranges do
		local last = out[#out]
		if last and r[1] <= last[2] then
			last[2] = math.max(last[2], r[2])
		else
			table.insert(out, { r[1], r[2] })
		end
	end
	return out
end

-- Marks -> a layout. Errors make the map unplayable (it is skipped);
-- warnings are worth fixing but the map still loads.
function MapMarks.toLayout(name: string, title: string, marks: { Mark }): (Layout, { string }, { string })
	local errors: { string } = {}
	local warnings: { string } = {}
	local layout = MapLayout.blank(name, title)
	local function where(m: Mark): string
		return string.format("%s at (%.0f, %.0f)", m.kind, m.x, m.z)
	end

	local byKind: { [string]: { Mark } } = {}
	for _, m in marks do
		if not MapMarks.isKind(m.kind) then
			table.insert(warnings, "Unknown kind " .. m.kind .. " (left out)")
			continue
		end
		local list = byKind[m.kind] or {}
		byKind[m.kind] = list
		table.insert(list, m)
	end
	local function all(kind: string): { Mark }
		return byKind[kind] or {}
	end

	local bounds = all("Bounds")
	if #bounds == 0 then
		table.insert(errors, "No Bounds part: add one under the whole play area")
	else
		layout.bounds = rectOf(bounds[1])
		if #bounds > 1 then
			table.insert(warnings, "More than one Bounds part: using the first")
		end
	end

	-- Houses: walls, rooms and furniture inside one belong to it.
	for i, m in all("House") do
		table.insert(layout.houses, {
			id = m.id or ("House" .. i),
			rect = rectOf(m),
			outline = if m.outline == "Orange" then "Orange" else "Blue",
			size = "Large",
		})
	end
	local function houseAt(x: number, z: number, margin: number): string
		local best, bestArea = "", math.huge
		for _, house in layout.houses do
			if MapLayout.inRect(house.rect, x, z, margin) then
				local area = (house.rect.x2 - house.rect.x1) * (house.rect.z2 - house.rect.z1)
				if area < bestArea then
					best, bestArea = house.id, area
				end
			end
		end
		return best
	end

	-- Walls, by their centerline (the part's thickness doesn't matter).
	for _, m in all("Wall") do
		local horizontal = m.w >= m.d
		local length = math.max(0, (if horizontal then m.w else m.d) - T)
		local a = (if horizontal then m.x else m.z) - length / 2
		table.insert(layout.walls, {
			x1 = if horizontal then a else m.x,
			z1 = if horizontal then m.z else a,
			x2 = if horizontal then a + length else m.x,
			z2 = if horizontal then m.z else a + length,
			horizontal = horizontal,
			gaps = {},
			windows = {},
			secrets = {},
			house = houseAt(m.x, m.z, T),
		})
	end

	-- Doors, windows and secret walls cut into the wall they sit on.
	local function cut(m: Mark, into: string)
		local best: MapLayout.Wall? = nil
		local bestScore = math.huge
		local long = m.w >= m.d
		for _, w in layout.walls do
			local along = if w.horizontal then m.x else m.z
			local off = math.abs(if w.horizontal then m.z - w.z1 else m.x - w.x1)
			local a = (if w.horizontal then w.x1 else w.z1) - T / 2
			local b = (if w.horizontal then w.x2 else w.z2) + T / 2
			if off <= T and along >= a - 0.01 and along <= b + 0.01 then
				-- Prefer the wall the part lies along (a doorway near a corner).
				local score = off + (if long ~= w.horizontal and math.abs(m.w - m.d) > 0.5 then 2 else 0)
				if score < bestScore then
					best, bestScore = w, score
				end
			end
		end
		if not best then
			table.insert(warnings, where(m) .. " isn't on a wall (left out)")
			return
		end
		local half = (if best.horizontal then m.w else m.d) / 2
		local along = if best.horizontal then m.x else m.z
		local list = if into == "Door"
			then best.gaps
			elseif into == "Window" then best.windows
			else best.secrets
		table.insert(list, { along - half, along + half })
	end
	for _, kind in { "Door", "Window", "SecretWall" } do
		for _, m in all(kind) do
			cut(m, kind)
		end
	end
	for _, w in layout.walls do
		w.gaps = merged(w.gaps)
		w.windows = merged(w.windows)
		w.secrets = merged(w.secrets)
	end

	for i, m in all("Floor") do
		local floor = if m.floor and table.find(MapMarks.FLOORS, m.floor) then m.floor else "Wood"
		table.insert(layout.rooms, {
			name = m.id or ("Room" .. i),
			floor = floor :: string,
			rect = rectOf(m),
			house = houseAt(m.x, m.z, 0),
		})
	end

	for _, m in marks do
		if MapMarks.isFurniture(m.kind) then
			table.insert(layout.furniture, {
				kind = m.kind,
				x = m.x,
				z = m.z,
				rot = math.round(m.rot) % 360,
				house = houseAt(m.x, m.z, 0),
			})
		end
	end

	for _, m in all("HumanSpawn") do
		table.insert(layout.humanSpawns, pointOf(m))
	end
	for _, m in all("ZombieSpawn") do
		table.insert(layout.zombieSpawns, pointOf(m))
	end
	for _, m in all("ItemSpot") do
		table.insert(layout.itemSpots, pointOf(m))
	end
	for _, m in all("WizardSpot") do
		table.insert(layout.wizardSpots, pointOf(m))
	end
	if #layout.humanSpawns == 0 then
		table.insert(errors, "No HumanSpawn: add at least one")
	end
	if #layout.zombieSpawns == 0 then
		table.insert(errors, "No ZombieSpawn: add at least one")
	end
	if #layout.itemSpots == 0 then
		layout.itemSpots = table.clone(layout.humanSpawns)
		table.insert(warnings, "No ItemSpot: items will lie at the human spawns")
	end
	if #layout.wizardSpots == 0 then
		layout.wizardSpots = table.clone(layout.humanSpawns)
		table.insert(warnings, "No WizardSpot: the wizard will show up at the human spawns")
	end
	local start = all("Start")[1]
	layout.start = if start then pointOf(start) else (layout.humanSpawns[1] or { x = 0, z = 0 })

	for _, m in all("Bush") do
		table.insert(layout.bushes, {
			x = m.x,
			z = m.z,
			r = math.max(m.w, m.d) / 2,
			color = if m.color == "Orange" or m.color == "Cobweb" then m.color :: string else "Green",
		})
	end

	local road = layout.road
	for kind, list in
		{
			Road = road.asphalt,
			Sidewalk = road.sidewalks,
			CenterLine = road.centerLines,
			EdgeLine = road.edgeLines,
			Path = layout.paths,
			Patio = layout.patios,
			Pool = layout.pools,
		} :: { [string]: { Rect } }
	do
		for _, m in all(kind) do
			table.insert(list, rectOf(m))
		end
	end

	-- Islands: each walk with the grass on it (or a grass edge of its own).
	local grasses = all("IslandGrass")
	local used: { [Mark]: boolean } = {}
	for _, m in all("IslandWalk") do
		local walk = rectOf(m)
		local grass: Rect? = nil
		for _, g in grasses do
			if not used[g] and MapLayout.inRect(walk, g.x, g.z) then
				used[g] = true
				grass = rectOf(g)
				break
			end
		end
		table.insert(layout.islands, {
			walk = walk,
			grass = grass or { x1 = walk.x1 + 3, z1 = walk.z1 + 3, x2 = walk.x2 - 3, z2 = walk.z2 - 3 },
		})
	end
	for _, g in grasses do
		if not used[g] then
			table.insert(layout.islands, { walk = rectOf(g), grass = rectOf(g) })
		end
	end

	-- Things that would never be reached.
	local b = layout.bounds
	for _, kind in { "HumanSpawn", "ZombieSpawn", "Start", "ItemSpot", "WizardSpot" } do
		for _, m in all(kind) do
			if #bounds > 0 and not MapLayout.inRect(b, m.x, m.z) then
				table.insert(warnings, where(m) .. " is outside the Bounds")
			end
		end
	end
	return layout, errors, warnings
end

-- A layout -> marks (to copy a built-in map into Studio).
function MapMarks.fromLayout(layout: Layout): { Mark }
	local marks: { Mark } = {}
	local function add(kind: string, r: Rect): Mark
		local m: Mark = {
			kind = kind,
			x = (r.x1 + r.x2) / 2,
			z = (r.z1 + r.z2) / 2,
			w = r.x2 - r.x1,
			d = r.z2 - r.z1,
			rot = 0,
		}
		table.insert(marks, m)
		return m
	end
	local function addPoint(kind: string, p: Point)
		add(kind, { x1 = p.x - 2, z1 = p.z - 2, x2 = p.x + 2, z2 = p.z + 2 })
	end

	add("Bounds", layout.bounds)
	for _, house in layout.houses do
		local m = add("House", house.rect)
		m.id, m.outline = house.id, house.outline
	end
	for _, room in layout.rooms do
		local m = add("Floor", room.rect)
		m.id, m.floor = room.name, room.floor
	end
	local h = T / 2
	for _, w in layout.walls do
		local function span(a: number, b: number): Rect
			return if w.horizontal
				then { x1 = a, z1 = w.z1 - h, x2 = b, z2 = w.z1 + h }
				else { x1 = w.x1 - h, z1 = a, x2 = w.x1 + h, z2 = b }
		end
		add(
			"Wall",
			span((if w.horizontal then w.x1 else w.z1) - h, (if w.horizontal then w.x2 else w.z2) + h)
		)
		for _, gap in w.gaps do
			add("Door", span(gap[1], gap[2]))
		end
		for _, window in w.windows do
			add("Window", span(window[1], window[2]))
		end
		for _, secret in w.secrets do
			add("SecretWall", span(secret[1], secret[2]))
		end
	end
	for _, spot in layout.furniture do
		local spec = FurnitureSpecs.get(spot.kind)
		local m = add(spot.kind, {
			x1 = spot.x - spec.w / 2,
			z1 = spot.z - spec.d / 2,
			x2 = spot.x + spec.w / 2,
			z2 = spot.z + spec.d / 2,
		})
		m.rot = spot.rot
	end
	for kind, list in
		{
			HumanSpawn = layout.humanSpawns,
			ZombieSpawn = layout.zombieSpawns,
			ItemSpot = layout.itemSpots,
			WizardSpot = layout.wizardSpots,
		} :: { [string]: { Point } }
	do
		for _, p in list do
			addPoint(kind, p)
		end
	end
	addPoint("Start", layout.start)
	for _, bush in layout.bushes do
		local m = add(
			"Bush",
			{ x1 = bush.x - bush.r, z1 = bush.z - bush.r, x2 = bush.x + bush.r, z2 = bush.z + bush.r }
		)
		m.color = bush.color
	end
	local road = layout.road
	for kind, list in
		{
			Road = road.asphalt,
			Sidewalk = road.sidewalks,
			CenterLine = road.centerLines,
			EdgeLine = road.edgeLines,
			Path = layout.paths,
			Patio = layout.patios,
			Pool = layout.pools,
		} :: { [string]: { Rect } }
	do
		for _, r in list do
			add(kind, r)
		end
	end
	for _, island in layout.islands do
		add("IslandWalk", island.walk)
		add("IslandGrass", island.grass)
	end
	return marks
end

-- A map to start from (320 x 300, about the size of the built-in maps): a
-- road, a house with two rooms, a cabin, a shed, spawns, items, bushes.
function MapMarks.starter(): { Mark }
	local marks: { Mark } = {}
	local function add(kind: string, x1: number, z1: number, x2: number, z2: number): Mark
		local m: Mark = {
			kind = kind,
			x = (x1 + x2) / 2,
			z = (z1 + z2) / 2,
			w = math.abs(x2 - x1),
			d = math.abs(z2 - z1),
			rot = 0,
		}
		table.insert(marks, m)
		return m
	end
	local function point(kind: string, x: number, z: number)
		add(kind, x - 2, z - 2, x + 2, z + 2)
	end
	local function piece(kind: string, x: number, z: number, rot: number?)
		local spec = FurnitureSpecs.get(kind)
		add(kind, x - spec.w / 2, z - spec.d / 2, x + spec.w / 2, z + spec.d / 2).rot = rot or 0
	end
	local function wallH(z: number, x1: number, x2: number)
		add("Wall", x1 - 1.5, z - 1.5, x2 + 1.5, z + 1.5)
	end
	local function wallV(x: number, z1: number, z2: number)
		add("Wall", x - 1.5, z1 - 1.5, x + 1.5, z2 + 1.5)
	end

	add("Bounds", -160, -150, 160, 150)
	add("Sidewalk", -160, 102, 160, 112)
	add("Road", -160, 112, 160, 140)
	add("CenterLine", -160, 125.5, 160, 126.5)
	add("Sidewalk", -160, 140, 160, 150)

	-- The house: living room (left) and kitchen (right), front door on the
	-- road side, a back door, windows.
	local house = add("House", -60, -40, 20, 20)
	house.id, house.outline = "House", "Blue"
	local living = add("Floor", -60, -40, -10, 20)
	living.id, living.floor = "Living room", "Wood"
	local kitchen = add("Floor", -10, -40, 20, 20)
	kitchen.id, kitchen.floor = "Kitchen", "Tile"
	wallH(-40, -60, 20)
	wallH(20, -60, 20)
	wallV(-60, -40, 20)
	wallV(20, -40, 20)
	wallV(-10, -40, 20)
	add("Door", -40, 18.5, -32, 21.5) -- front door
	add("Door", -11.5, -15, -8.5, -7) -- between the rooms
	add("Door", 18.5, -30, 21.5, -22) -- back door
	add("Window", -56, -41.5, -44, -38.5)
	add("Window", -2, 18.5, 12, 21.5)
	piece("Couch", -48, 8)
	piece("CoffeeTable", -48, -2)
	piece("Bookshelf", -40, -36)
	piece("Plant", -56, -36)
	piece("Fridge", 15, -36)
	piece("Stove", 6, -36)
	piece("Sink", -3, -36)
	piece("Table", 4, 0)
	piece("Chair", -2, 0, 90)
	piece("Chair", 10, 0, 270)

	-- A shed in the yard.
	local shed = add("House", 50, -60, 90, -30)
	shed.id, shed.outline = "Shed", "Orange"
	local shedFloor = add("Floor", 50, -60, 90, -30)
	shedFloor.id, shedFloor.floor = "Shed", "Concrete"
	wallH(-60, 50, 90)
	wallH(-30, 50, 90)
	wallV(50, -60, -30)
	wallV(90, -60, -30)
	add("Door", 64, -31.5, 72, -28.5)
	piece("Box", 58, -52)
	piece("Box", 82, -52, 90)

	-- A one-room cabin with a front and a back door.
	local cabin = add("House", 70, 10, 120, 50)
	cabin.id, cabin.outline = "Cabin", "Orange"
	local cabinFloor = add("Floor", 70, 10, 120, 50)
	cabinFloor.id, cabinFloor.floor = "Cabin", "Wood"
	wallH(10, 70, 120)
	wallH(50, 70, 120)
	wallV(70, 10, 50)
	wallV(120, 10, 50)
	add("Door", 90, 48.5, 98, 51.5) -- front door
	add("Door", 68.5, 20, 71.5, 27) -- back door
	add("Window", 80, 8.5, 92, 11.5)
	add("Window", 118.5, 22, 121.5, 38)
	piece("Bed", 112, 18)
	piece("Dresser", 100, 13.2)
	piece("Armchair", 78, 42)
	piece("Lamp", 74, 14)
	piece("Bookshelf", 117.3, 40, 270)
	piece("Box", 84, 14)

	for _, p in
		{
			{ -130, 60 },
			{ -60, 60 },
			{ 0, 75 },
			{ 50, 80 },
			{ 135, 75 },
			{ 135, -80 },
			{ -130, -100 },
			{ 0, -110 },
			{ -110, -40 },
		}
	do
		point("HumanSpawn", p[1], p[2])
	end
	point("ZombieSpawn", 140, 126)
	point("Start", -20, 55)
	for _, p in { { -45, -20 }, { 5, -25 }, { 70, -45 }, { 95, 30 } } do
		point("ItemSpot", p[1], p[2])
	end
	point("WizardSpot", -140, -130)
	point("WizardSpot", 100, 90)
	local function bush(x: number, z: number, r: number, color: string)
		add("Bush", x - r, z - r, x + r, z + r).color = color
	end
	bush(-140, -20, 5, "Green")
	bush(145, -130, 4, "Green")
	bush(-20, -120, 5, "Orange")
	bush(145, 0, 4, "Orange")
	bush(-140, 90, 4, "Green")
	return marks
end

return MapMarks
