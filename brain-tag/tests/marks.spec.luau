-- Maps built in Studio: copying a built-in map to marks and reading it back
-- gives the same map, the starter map loads cleanly, and mistakes are named.
local MapLayout = require(script.Parent.MapLayout)
local MapMarks = require(script.Parent.MapMarks)

-- Rounded, with -0 written as 0 (mirrored rects have some).
local function n(v: number): number
	return math.round(v * 100) / 100 + 0
end

local function key(r: MapLayout.Rect): string
	return string.format("%.2f,%.2f,%.2f,%.2f", n(r.x1), n(r.z1), n(r.x2), n(r.z2))
end

local function rectSet(list: { MapLayout.Rect }): { [string]: number }
	local set = {}
	for _, r in list do
		local k = key(r)
		set[k] = (set[k] or 0) + 1
	end
	return set
end

local function sameSet(a: { [string]: number }, b: { [string]: number }, label: string)
	for k, n in a do
		expectEq(b[k], n, label .. " " .. k)
	end
	for k, n in b do
		expectEq(a[k], n, label .. " " .. k)
	end
end

local function pointRects(list: { MapLayout.Point }): { MapLayout.Rect }
	local out = {}
	for _, p in list do
		table.insert(out, { x1 = p.x, z1 = p.z, x2 = p.x, z2 = p.z })
	end
	return out
end

for _, name in { "Neighborhood", "Mansion" } do
	test(name .. ": copied to Studio and back is the same map", function()
		local original = MapLayout.get(name)
		assert(original, name)
		local copy, errors, warnings = MapMarks.toLayout(name, original.title, MapMarks.fromLayout(original))
		expectEq(#errors, 0, "errors: " .. table.concat(errors, "; "))
		expectEq(#warnings, 0, "warnings: " .. table.concat(warnings, "; "))
		expectEq(key(copy.bounds), key(original.bounds), "bounds")

		local function pieces(layout: MapLayout.Layout, windows: boolean): { MapLayout.Rect }
			local out = {}
			for _, p in MapLayout.allWallPieces(layout) do
				if p.window == windows then
					table.insert(out, p.rect)
				end
			end
			return out
		end
		sameSet(rectSet(pieces(copy, false)), rectSet(pieces(original, false)), "wall piece")
		sameSet(rectSet(pieces(copy, true)), rectSet(pieces(original, true)), "window piece")

		local function doors(layout: MapLayout.Layout): { [string]: number }
			local set = {}
			for _, d in MapLayout.doors(layout) do
				local k = string.format(
					"%.2f,%.2f,%.2f,%s,%s",
					n(d.x),
					n(d.z),
					n(d.width),
					d.house,
					tostring(d.exterior)
				)
				set[k] = (set[k] or 0) + 1
			end
			return set
		end
		sameSet(doors(copy), doors(original), "door")

		local function rooms(layout: MapLayout.Layout): { [string]: number }
			local set = {}
			for _, r in layout.rooms do
				local k = key(r.rect) .. r.floor .. r.house .. r.name
				set[k] = (set[k] or 0) + 1
			end
			return set
		end
		sameSet(rooms(copy), rooms(original), "room")

		local function furniture(layout: MapLayout.Layout): { [string]: number }
			local set = {}
			for _, f in layout.furniture do
				local k = string.format("%s %.2f,%.2f %d %s", f.kind, n(f.x), n(f.z), f.rot, f.house)
				set[k] = (set[k] or 0) + 1
			end
			return set
		end
		sameSet(furniture(copy), furniture(original), "furniture")

		for _, field in { "humanSpawns", "zombieSpawns", "itemSpots", "wizardSpots" } do
			sameSet(
				rectSet(pointRects((copy :: any)[field])),
				rectSet(pointRects((original :: any)[field])),
				field
			)
		end
		expectEq(copy.start.x, original.start.x, "start x")
		expectEq(copy.start.z, original.start.z, "start z")

		for _, field in { "paths", "patios", "pools" } do
			sameSet(rectSet((copy :: any)[field]), rectSet((original :: any)[field]), field)
		end
		for _, field in { "asphalt", "sidewalks", "centerLines", "edgeLines" } do
			sameSet(rectSet((copy.road :: any)[field]), rectSet((original.road :: any)[field]), field)
		end
		expectEq(#copy.islands, #original.islands, "islands")
		expectEq(#copy.bushes, #original.bushes, "bushes")
		for i, b in original.bushes do
			local c = copy.bushes[i]
			expect(c.x == b.x and c.z == b.z and c.r == b.r and c.color == b.color, "bush " .. i)
		end
		expectEq(#copy.houses, #original.houses, "houses")
	end)
end

test("the starter map loads with no problems", function()
	local layout, errors, warnings = MapMarks.toLayout("Starter", "Starter", MapMarks.starter())
	expectEq(#errors, 0, "errors: " .. table.concat(errors, "; "))
	expectEq(#warnings, 0, "warnings: " .. table.concat(warnings, "; "))
	expect(#layout.walls == 9, "walls: " .. #layout.walls)
	expect(#MapLayout.doors(layout) == 4, "doors: " .. #MapLayout.doors(layout))
	local exterior = 0
	for _, d in MapLayout.doors(layout) do
		if d.exterior then
			exterior += 1
		end
	end
	expectEq(exterior, 3, "doors to the outside")
	expect(#layout.furniture >= 10, "furniture")
	expectEq(#layout.zombieSpawns, 1, "zombie spawn")
end)

test("mistakes are reported", function()
	local function mark(kind: string, x: number, z: number, w: number, d: number): MapMarks.Mark
		return { kind = kind, x = x, z = z, w = w, d = d, rot = 0 }
	end
	local _, errors, warnings = MapMarks.toLayout("Bad", "Bad", {
		mark("Wall", 0, 0, 40, 3),
		mark("Door", 0, 30, 6, 3), -- not on any wall
		mark("Teapot", 5, 5, 1, 1),
	})
	expectEq(#errors, 3, "no bounds, no human spawn, no zombie spawn: " .. table.concat(errors, "; "))
	local text = table.concat(warnings, "\n")
	expect(string.find(text, "isn't on a wall", 1, true) ~= nil, "door off the wall")
	expect(string.find(text, "Teapot", 1, true) ~= nil, "unknown kind")

	-- A square door part still cuts the wall it sits on.
	local layout = MapMarks.toLayout("Ok", "Ok", {
		mark("Bounds", 0, 0, 100, 100),
		mark("Wall", 0, 0, 43, 3),
		mark("Door", 5, 0, 6, 6),
		mark("HumanSpawn", 10, 10, 4, 4),
		mark("ZombieSpawn", -10, 10, 4, 4),
	})
	expectEq(#layout.walls[1].gaps, 1, "gap")
	expectEq(layout.walls[1].gaps[1][1], 2, "gap start")
	expectEq(layout.walls[1].gaps[1][2], 8, "gap end")
	expectEq(layout.walls[1].x1, -20, "wall centerline start")
end)
