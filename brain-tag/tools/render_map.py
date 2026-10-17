"""Draw MapLayout.luau as a top-down PNG, roughly how the game camera sees it.

Usage: python3 tools/render_map.py [path/to/luau] [out.png] [MapName]
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from luau_bundle import ROOT, bundle  # noqa: E402

DUMP = """
local MapLayout = require(script.Parent.MapLayout)
local FurnitureSpecs = require(script.Parent.FurnitureSpecs)
local layout = MapLayout.get("__MAP__")

local function encode(value)
	local t = typeof(value)
	if t == "number" then
		return tostring(value)
	elseif t == "string" then
		return string.format("%q", value)
	elseif t == "boolean" then
		return tostring(value)
	elseif t == "table" then
		if #value > 0 or next(value) == nil then
			local out = {}
			for _, v in value do
				table.insert(out, encode(v))
			end
			return "[" .. table.concat(out, ",") .. "]"
		end
		local out = {}
		for k, v in value do
			if typeof(v) ~= "function" then
				table.insert(out, string.format("%q", tostring(k)) .. ":" .. encode(v))
			end
		end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null"
end

local furniture = {}
for _, spot in layout.furniture do
	local w, d = FurnitureSpecs.footprint(spot.kind, spot.rot)
	local spec = FurnitureSpecs.get(spot.kind)
	table.insert(furniture, { kind = spot.kind, rect = MapLayout.footprint(spot, w, d), weight = spec.weight, rot = spot.rot, x = spot.x, z = spot.z })
end

print(encode({
	bounds = layout.bounds,
	colors = MapLayout.COLORS,
	road = layout.road,
	islands = layout.islands,
	paths = layout.paths,
	patios = layout.patios,
	pools = layout.pools,
	bushes = layout.bushes,
	houses = layout.houses,
	rooms = layout.rooms,
	pieces = MapLayout.allWallPieces(layout),
	furniture = furniture,
	humanSpawns = layout.humanSpawns,
	zombieSpawns = layout.zombieSpawns,
	itemSpots = layout.itemSpots,
	wizardSpots = layout.wizardSpots,
}))
"""

FURNITURE_COLORS = {
    "Couch": "3C8DBC",
    "Armchair": "5BAA4A",
    "Fridge": "F0F2F5",
    "Stove": "E8E8E8",
    "Sink": "C9D1D9",
    "Toilet": "FAFAFA",
    "Bathtub": "F4F7FA",
    "Bed": "8E5A32",
    "Table": "B07A45",
    "CoffeeTable": "9A6838",
    "Chair": "C08A55",
    "Bookshelf": "6B4226",
    "Box": "C9A06A",
    "Plant": "B5653A",
    "Picture": "D4A93A",
    "Rug": "3FAE5C",
    "Wardrobe": "7A4A2A",
    "Piano": "222222",
    "PoolTable": "2E8B57",
    "Car": "D9443B",
    "Dresser": "8E5A32",
    "Washer": "E8ECEF",
    "Desk": "A0703F",
    "TVStand": "5A3A22",
    "Crate": "C8955A",
    "Barrel": "8B5A2B",
    "Bench": "A0703F",
    "Lamp": "F2E2A0",
    "Beanbag": "E74C3C",
    "TrashCan": "7F8C8D",
    "Aquarium": "7FC8F8",
    "Arcade": "6C3483",
    "VendingMachine": "C0392B",
    "Treadmill": "2C3E50",
}


def hex_color(value: str) -> tuple[int, int, int]:
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def main() -> int:
    luau = sys.argv[1] if len(sys.argv) > 1 else shutil.which("luau")
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "tools" / "out" / "map.png"
    map_name = sys.argv[3] if len(sys.argv) > 3 else "Neighborhood"
    if not luau:
        print("luau not found")
        return 2
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False) as handle:
        handle.write(bundle(DUMP.replace("__MAP__", map_name)))
        script = handle.name
    result = subprocess.run([luau, script], capture_output=True, text=True, check=True)
    data = json.loads(result.stdout)

    scale = 3
    b = data["bounds"]
    width = int((b["x2"] - b["x1"]) * scale)
    height = int((b["z2"] - b["z1"]) * scale)
    image = Image.new("RGB", (width, height), hex_color(data["colors"]["Grass"]))
    draw = ImageDraw.Draw(image)
    c = data["colors"]

    def box(r: dict, fill: str, outline: str | None = None, inset: float = 0.0) -> None:
        x1 = (r["x1"] - b["x1"] + inset) * scale
        z1 = (r["z1"] - b["z1"] + inset) * scale
        x2 = (r["x2"] - b["x1"] - inset) * scale
        z2 = (r["z2"] - b["z1"] - inset) * scale
        draw.rectangle([x1, z1, x2, z2], fill=hex_color(fill), outline=hex_color(outline) if outline else None)

    def point(p: dict, radius: float, fill: str) -> None:
        x = (p["x"] - b["x1"]) * scale
        z = (p["z"] - b["z1"]) * scale
        draw.ellipse([x - radius * scale, z - radius * scale, x + radius * scale, z + radius * scale], fill=hex_color(fill))

    for r in data["paths"]:
        box(r, c["Dirt"])
    for r in data["patios"]:
        box(r, c["Concrete"])
    for r in data["road"]["sidewalks"]:
        box(r, c["Sidewalk"])
    for r in data["road"]["asphalt"]:
        box(r, c["Asphalt"])
    for r in data["road"]["centerLines"]:
        box(r, c["CenterLine"])
    for r in data["road"]["edgeLines"]:
        box(r, c["EdgeLine"])
    for island in data["islands"]:
        box(island["walk"], c["Sidewalk"])
        box(island["grass"], c["Grass"])
    for r in data["pools"]:
        box({"x1": r["x1"] - 1.5, "z1": r["z1"] - 1.5, "x2": r["x2"] + 1.5, "z2": r["z2"] + 1.5}, c["PoolRim"])
        box(r, c["PoolWater"])

    floor_colors = {"Brick": c["Brick"], "Tile": c["Tile"], "Wood": c["Wood"], "Concrete": c["Concrete"]}
    for room in data["rooms"]:
        box(room["rect"], floor_colors[room["floor"]])

    for item in data["furniture"]:
        if item["kind"] == "Rug":
            box(item["rect"], FURNITURE_COLORS["Rug"])
    for item in data["furniture"]:
        if item["kind"] != "Rug":
            box(item["rect"], FURNITURE_COLORS.get(item["kind"], "FF00FF"), outline="333333")

    outline_for = {h["id"]: c["OutlineBlue"] if h["outline"] == "Blue" else c["OutlineOrange"] for h in data["houses"]}
    for piece in data["pieces"]:
        r = piece["rect"]
        grown = {"x1": r["x1"] - 0.5, "z1": r["z1"] - 0.5, "x2": r["x2"] + 0.5, "z2": r["z2"] + 0.5}
        box(grown, outline_for[piece["house"]])
    for piece in data["pieces"]:
        box(piece["rect"], c["Wall"])
        if piece["window"]:
            r = piece["rect"]
            if piece["horizontal"]:
                mid = (r["z1"] + r["z2"]) / 2
                box({"x1": r["x1"], "z1": mid - 0.5, "x2": r["x2"], "z2": mid + 0.5}, c["Window"])
            else:
                mid = (r["x1"] + r["x2"]) / 2
                box({"x1": mid - 0.5, "z1": r["z1"], "x2": mid + 0.5, "z2": r["z2"]}, c["Window"])

    for bush in data["bushes"]:
        color = c["BushGreen"] if bush["color"] == "Green" else c["BushOrange"]
        point(bush, bush["r"], color)
    for p in data["humanSpawns"]:
        point(p, 1.6, "FFFFFF")
    for p in data["zombieSpawns"]:
        point(p, 5, c["ZombiePit"])
    for p in data["itemSpots"]:
        point(p, 1, "FFD54A")
    for p in data["wizardSpots"]:
        point(p, 1.8, "8E44AD")

    out.parent.mkdir(parents=True, exist_ok=True)
    image.save(out)
    print(f"wrote {out} ({width}x{height})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
