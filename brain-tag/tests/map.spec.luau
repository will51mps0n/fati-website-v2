-- Map geometry: furniture fits its rooms, doorways stay clear, wall pieces are
-- small enough to shotgun, and every room can be reached on foot.
local MapLayout = require(script.Parent.MapLayout)
local FurnitureSpecs = require(script.Parent.FurnitureSpecs)
local Config = require(script.Parent.Config)

local pieces = MapLayout.allWallPieces()
local doors = MapLayout.doors()

local function furnitureRect(spot)
	local w, d = FurnitureSpecs.footprint(spot.kind, spot.rot)
	return MapLayout.footprint(spot, w, d)
end

local function describe(spot)
	return string.format("%s %s at (%.1f, %.1f)", spot.house, spot.kind, spot.x, spot.z)
end

test("furniture kinds exist and rotations are quarter turns", function()
	for _, spot in MapLayout.furniture do
		expect(FurnitureSpecs.specs[spot.kind] ~= nil, "known kind " .. spot.kind)
		expectEq(spot.rot % 90, 0, describe(spot) .. " rotation")
	end
	expect(#MapLayout.furniture >= 80, "plenty of furniture: " .. #MapLayout.furniture)
end)

test("every piece sits inside exactly one room", function()
	for _, spot in MapLayout.furniture do
		local r = furnitureRect(spot)
		local inside = 0
		for _, room in MapLayout.rooms do
			local interior = MapLayout.roomInterior(room)
			if
				r.x1 >= interior.x1
				and r.x2 <= interior.x2
				and r.z1 >= interior.z1
				and r.z2 <= interior.z2
			then
				inside += 1
			end
		end
		expectEq(inside, 1, describe(spot) .. " rooms containing it")
	end
end)

test("furniture never overlaps walls or other furniture", function()
	for i, spot in MapLayout.furniture do
		local r = furnitureRect(spot)
		for _, piece in pieces do
			expect(not MapLayout.rectsOverlap(r, piece.rect), describe(spot) .. " overlaps a wall")
		end
		if not FurnitureSpecs.get(spot.kind).decor then
			for j, other in MapLayout.furniture do
				if j > i and not FurnitureSpecs.get(other.kind).decor then
					expect(
						not MapLayout.rectsOverlap(r, furnitureRect(other)),
						describe(spot) .. " overlaps " .. describe(other)
					)
				end
			end
		end
	end
end)

test("doorways start clear", function()
	local T = MapLayout.WALL_THICKNESS
	for _, door in doors do
		local half = door.width / 2
		local zone = if door.horizontal
			then { x1 = door.x - half, z1 = door.z - T / 2 - 3, x2 = door.x + half, z2 = door.z + T / 2 + 3 }
			else {
				x1 = door.x - T / 2 - 3,
				z1 = door.z - half,
				x2 = door.x + T / 2 + 3,
				z2 = door.z + half,
			}
		for _, spot in MapLayout.furniture do
			if not FurnitureSpecs.get(spot.kind).decor then
				expect(
					not MapLayout.rectsOverlap(zone, furnitureRect(spot)),
					describe(spot) .. " blocks a door at " .. door.x .. "," .. door.z
				)
			end
		end
	end
end)

test("door sizes and counts", function()
	local exterior: { [string]: number } = {}
	for _, door in doors do
		if door.exterior then
			exterior[door.house] = (exterior[door.house] or 0) + 1
			expect(door.width >= 7 and door.width <= 8, "exterior door width " .. door.width)
		else
			expect(door.width >= 6 and door.width <= 8, "interior door width " .. door.width)
		end
	end
	expectEq(exterior.North, 3, "north house exterior doors")
	expectEq(exterior.South, 3, "south house exterior doors")
	expectEq(exterior.Island, 2, "island house exterior doors")
end)

test("every door can be barricaded with one long piece", function()
	local longest = 0
	for _, kind in { "Couch", "Bed", "Bookshelf", "Bathtub" } do
		local spec = FurnitureSpecs.get(kind)
		longest = math.max(longest, spec.w, spec.d)
	end
	for _, door in doors do
		expect(longest >= door.width + 2, "a piece overlaps both sides of a " .. door.width .. " stud door")
	end
end)

test("wall pieces are short and windows sit in solid wall", function()
	local T = MapLayout.WALL_THICKNESS
	for _, piece in pieces do
		local r = piece.rect
		local length = math.max(r.x2 - r.x1, r.z2 - r.z1)
		local thickness = math.min(r.x2 - r.x1, r.z2 - r.z1)
		expect(length <= MapLayout.MAX_WALL_PIECE + 1e-6, "piece length " .. length)
		expect(math.abs(thickness - T) < 1e-6 or length < T + 1e-6, "piece thickness " .. thickness)
	end
	for _, w in MapLayout.walls do
		for _, win in w.windows do
			for _, gap in w.gaps do
				expect(win[2] <= gap[1] or win[1] >= gap[2], "window overlaps a door")
			end
			-- No perpendicular wall may meet the wall inside a window.
			for _, other in MapLayout.walls do
				if other.horizontal ~= w.horizontal and other.house == w.house then
					local at = if w.horizontal then other.x1 else other.z1
					local touches = if w.horizontal
						then other.z1 <= w.z1 and other.z2 >= w.z1
						else other.x1 <= w.x1 and other.x2 >= w.x1
					if touches then
						expect(at + T / 2 <= win[1] or at - T / 2 >= win[2], "window crosses a wall junction")
					end
				end
			end
		end
	end
	expect(#pieces > 100, "plenty of breakable pieces: " .. #pieces)
end)

-- Flood fill on a 1-stud grid from the zombie spawn, treating walls,
-- furniture and bushes as solid and inflating them by a body radius.
local function reachableGrid(radius: number)
	local B = MapLayout.BOUNDS
	local width = B.x2 - B.x1
	local height = B.z2 - B.z1
	local blocked = {}
	local function cellIndex(cx: number, cz: number): number
		return cz * width + cx
	end
	local function block(x1: number, z1: number, x2: number, z2: number)
		local cx1 = math.max(0, math.floor(x1 - radius - B.x1))
		local cx2 = math.min(width - 1, math.ceil(x2 + radius - B.x1))
		local cz1 = math.max(0, math.floor(z1 - radius - B.z1))
		local cz2 = math.min(height - 1, math.ceil(z2 + radius - B.z1))
		for cz = cz1, cz2 do
			for cx = cx1, cx2 do
				-- Only block a cell whose center is within the inflated rect.
				local x = B.x1 + cx + 0.5
				local z = B.z1 + cz + 0.5
				if x > x1 - radius and x < x2 + radius and z > z1 - radius and z < z2 + radius then
					blocked[cellIndex(cx, cz)] = true
				end
			end
		end
	end
	for _, piece in pieces do
		local r = piece.rect
		block(r.x1, r.z1, r.x2, r.z2)
	end
	for _, spot in MapLayout.furniture do
		if not FurnitureSpecs.get(spot.kind).decor then
			local r = furnitureRect(spot)
			block(r.x1, r.z1, r.x2, r.z2)
		end
	end
	for _, bush in MapLayout.bushes do
		block(bush.x - bush.r, bush.z - bush.r, bush.x + bush.r, bush.z + bush.r)
	end

	local seen = {}
	local start = MapLayout.zombieSpawns[1]
	local sx, sz = math.floor(start.x - B.x1), math.floor(start.z - B.z1)
	local queue = { cellIndex(sx, sz) }
	seen[queue[1]] = true
	local head = 1
	while head <= #queue do
		local idx = queue[head]
		head += 1
		local cx, cz = idx % width, idx // width
		for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local nx, nz = cx + d[1], cz + d[2]
			if nx >= 0 and nx < width and nz >= 0 and nz < height then
				local n = cellIndex(nx, nz)
				if not seen[n] and not blocked[n] then
					seen[n] = true
					table.insert(queue, n)
				end
			end
		end
	end
	return function(x: number, z: number): boolean
		return seen[cellIndex(math.floor(x - B.x1), math.floor(z - B.z1))] == true
	end
end

test("every room, spawn and item spot is reachable at normal size", function()
	local reachable = reachableGrid(Config.CHARACTER.RootWidth / 2)
	for _, room in MapLayout.rooms do
		local found = false
		local interior = MapLayout.roomInterior(room)
		for x = interior.x1 + 1, interior.x2 - 1, 2 do
			for z = interior.z1 + 1, interior.z2 - 1, 2 do
				if reachable(x, z) then
					found = true
				end
			end
		end
		expect(found, room.house .. " " .. room.name .. " reachable")
	end
	for _, list in
		{ MapLayout.humanSpawns, MapLayout.itemSpots, MapLayout.wizardSpots, MapLayout.zombieSpawns }
	do
		for _, p in list do
			expect(reachable(p.x, p.z), string.format("point (%d, %d) reachable", p.x, p.z))
		end
	end
end)

test("the biggest players still fit through every door", function()
	local reachable = reachableGrid(Config.CHARACTER.RootWidth / 2 * Config.MAX_SCALE)
	for _, p in MapLayout.itemSpots do
		expect(reachable(p.x, p.z), string.format("item spot (%d, %d) reachable at max size", p.x, p.z))
	end
end)

test("spawns and item spots are in sensible places", function()
	local function insideHouse(x: number, z: number): boolean
		for _, house in MapLayout.houses do
			if MapLayout.inRect(house.rect, x, z, 2) then
				return true
			end
		end
		return false
	end
	for _, p in MapLayout.humanSpawns do
		expect(not insideHouse(p.x, p.z), "human spawn in a yard")
		expect(MapLayout.inRect(MapLayout.BOUNDS, p.x, p.z, -5), "human spawn inside bounds")
	end
	for _, p in MapLayout.wizardSpots do
		expect(not insideHouse(p.x, p.z), "wizard spot in a yard")
	end
	for _, p in MapLayout.itemSpots do
		expect(insideHouse(p.x, p.z), "item spot inside a house")
		for _, spot in MapLayout.furniture do
			if not FurnitureSpecs.get(spot.kind).decor then
				expect(
					not MapLayout.inRect(furnitureRect(spot), p.x, p.z, 1.5),
					"item spot clear of " .. describe(spot)
				)
			end
		end
	end
	for _, bush in MapLayout.bushes do
		local r = { x1 = bush.x - bush.r, z1 = bush.z - bush.r, x2 = bush.x + bush.r, z2 = bush.z + bush.r }
		for _, path in MapLayout.paths do
			expect(not MapLayout.rectsOverlap(r, path, 1), "bush on a path")
		end
		for _, walk in MapLayout.road.sidewalks do
			expect(not MapLayout.rectsOverlap(r, walk, 1), "bush on the sidewalk")
		end
		for _, house in MapLayout.houses do
			expect(not MapLayout.rectsOverlap(r, house.rect, 3), "bush against a house")
		end
		for _, list in { MapLayout.humanSpawns, MapLayout.wizardSpots } do
			for _, p in list do
				expect(not MapLayout.inRect(r, p.x, p.z, 3), "bush on a spawn")
			end
		end
	end
end)
