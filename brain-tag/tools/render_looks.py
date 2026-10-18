"""Draw skins and furniture top-down as a PNG, to check looks without Studio.

Runs the real CharacterLook.apply / FurnitureBuilder.build under a tiny fake
of Roblox's Instance, Vector3, CFrame and Color3, then paints every part
from straight above, lowest first (like the game camera sees them).

Usage: python3 tools/render_looks.py path/to/luau [out.png] [Skin:Team | Furniture:Kind | Item:Id ...]
"""

from __future__ import annotations

import json
import math
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from luau_bundle import PRELUDE, module_source  # noqa: E402

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover
    raise SystemExit("needs Pillow: pip install pillow")

MODULES = ["Config", "Items", "Skins", "RoundRules", "Parts", "CharacterLook", "FurnitureSpecs", "MapLayout", "ItemModels"]
SERVER_MODULES = ["FurnitureBuilder"]

FAKES = r"""
local Vector3 = {}
local V = {}
V.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
	return nil
end
local function vec(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, V) end
V.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__unm = function(a) return vec(-a.X, -a.Y, -a.Z) end
V.__mul = function(a, b)
	if type(a) == "number" then return vec(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return vec(a.X * b, a.Y * b, a.Z * b) end
	return vec(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V.__div = function(a, b) return vec(a.X / b, a.Y / b, a.Z / b) end
Vector3.new = function(x, y, z) return vec(x or 0, y or 0, z or 0) end
Vector3.one = vec(1, 1, 1)
Vector3.zero = vec(0, 0, 0)
Vector3.xAxis, Vector3.yAxis, Vector3.zAxis = vec(1, 0, 0), vec(0, 1, 0), vec(0, 0, 1)

local CFrame = {}
local CF = {}
local CFMethods = {}
CF.__index = function(c, k)
	if k == "Position" then return vec(c.p[1], c.p[2], c.p[3]) end
	return CFMethods[k]
end
local function cf(r, p) return setmetatable({ r = r, p = p }, CF) end
local function matmul(a, b)
	local m = {}
	for i = 1, 3 do
		m[i] = {}
		for j = 1, 3 do
			m[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
		end
	end
	return m
end
local I = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
CF.__mul = function(a, b)
	local r = matmul(a.r, b.r)
	local p = {}
	for i = 1, 3 do
		p[i] = a.p[i] + a.r[i][1] * b.p[1] + a.r[i][2] * b.p[2] + a.r[i][3] * b.p[3]
	end
	return cf(r, p)
end
CFrame.new = function(x, y, z) return cf(I, { x or 0, y or 0, z or 0 }) end
function CFMethods.Inverse(c)
	local t = { { c.r[1][1], c.r[2][1], c.r[3][1] }, { c.r[1][2], c.r[2][2], c.r[3][2] }, { c.r[1][3], c.r[2][3], c.r[3][3] } }
	local p = {}
	for i = 1, 3 do
		p[i] = -(t[i][1] * c.p[1] + t[i][2] * c.p[2] + t[i][3] * c.p[3])
	end
	return cf(t, p)
end
function CFMethods.ToObjectSpace(c, other) return c:Inverse() * other end
CFrame.identity = cf(I, { 0, 0, 0 })
CFrame.fromMatrix = function(pos, rx, ry, rz)
	rz = rz or vec(rx.Y * ry.Z - rx.Z * ry.Y, rx.Z * ry.X - rx.X * ry.Z, rx.X * ry.Y - rx.Y * ry.X)
	return cf({ { rx.X, ry.X, rz.X }, { rx.Y, ry.Y, rz.Y }, { rx.Z, ry.Z, rz.Z } }, { pos.X, pos.Y, pos.Z })
end
CFrame.Angles = function(rx, ry, rz)
	local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	local X = { { 1, 0, 0 }, { 0, cx, -sx }, { 0, sx, cx } }
	local Y = { { cy, 0, sy }, { 0, 1, 0 }, { -sy, 0, cy } }
	local Z = { { cz, -sz, 0 }, { sz, cz, 0 }, { 0, 0, 1 } }
	return cf(matmul(matmul(X, Y), Z), { 0, 0, 0 })
end

local Color3 = {}
local function col(r, g, b) return { R = r, G = g, B = b, __color = true } end
Color3.new = col
Color3.fromRGB = function(r, g, b) return col(r / 255, g / 255, b / 255) end
Color3.fromHex = function(h)
	h = string.gsub(h, "#", "")
	return col(tonumber(string.sub(h, 1, 2), 16) / 255, tonumber(string.sub(h, 3, 4), 16) / 255, tonumber(string.sub(h, 5, 6), 16) / 255)
end

local Enum = setmetatable({}, { __index = function(_, e)
	return setmetatable({}, { __index = function(_, v) return e .. "." .. v end })
end })

local all = {}
local Inst = {}
Inst.__index = Inst
function Inst:SetAttribute(k, v) self.attrs[k] = v end
function Inst:GetAttribute(k) return self.attrs[k] end
function Inst:FindFirstChild(name) for _, c in self.kids do if c.Name == name then return c end end return nil end
function Inst:GetChildren() return table.clone(self.kids) end
function Inst:Destroy() self:_parent(nil); self.dead = true end
function Inst:IsA(c) return self.ClassName == c or (c == "BasePart" and self.ClassName == "Part") end
function Inst:_parent(p)
	local old = rawget(self, "_p")
	if old then
		local i = table.find(old.kids, self)
		if i then table.remove(old.kids, i) end
	end
	rawset(self, "_p", p)
	if p then table.insert(p.kids, self) end
end
local InstMeta = {
	__index = function(t, k)
		if k == "Parent" then return rawget(t, "_p") end
		return Inst[k]
	end,
	__newindex = function(t, k, v)
		if k == "Parent" then t:_parent(v) else rawset(t, k, v) end
	end,
}
local Instance = { new = function(c)
	local o = setmetatable({ ClassName = c, Name = c, kids = {}, attrs = {}, Transparency = 0 }, InstMeta)
	table.insert(all, o)
	return o
end }
local function typeof(v)
	if type(v) == "table" then
		if getmetatable(v) == V then return "Vector3" end
		if getmetatable(v) == CF then return "CFrame" end
		if v.__color then return "Color3" end
		return "table"
	end
	return type(v)
end
local ReplicatedStorage = { Shared = setmetatable({}, { __index = function(_, name) return { __module = name } end }) }
local game = { GetService = function(_, name) if name == "ReplicatedStorage" then return ReplicatedStorage end return {} end }
local PhysicalProperties = { new = function() return {} end }
function Inst:GetDescendants()
	local out = {}
	local function walk(o) for _, c in o.kids do table.insert(out, c); walk(c) end end
	walk(self)
	return out
end
local workspace = {}
"""

MAIN = r"""
local CharacterLook = require(script.Parent.CharacterLook)
local FurnitureBuilder = require(script.Parent.FurnitureBuilder)
local ItemModels = require(script.Parent.ItemModels)
local out = {}
for _, entry in ARGS do
	local model, root
	if entry[1] == "Furniture" then
		local folder = Instance.new("Folder")
		model = FurnitureBuilder.build({ kind = entry[2], x = 0, z = 0, rot = 0, house = "" }, folder).model
		entry = { entry[2], "Furniture" }
	elseif entry[1] == "Item" then
		model = ItemModels.build(entry[2])
		entry = { entry[2], "Item" }
	else
		model = Instance.new("Model")
		root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = CFrame.new(0, 0, 0)
		root.Size = Vector3.new(2.2, 2, 2.2)
		root.Parent = model
		CharacterLook.apply(model, root, entry[1], entry[2], 1)
	end
	local parts = {}
	for _, p in model:GetDescendants() do
		if p.ClassName == "Part" and p ~= root and (p.Transparency or 0) < 1 and p.Name ~= "Shadow" then
			table.insert(parts, {
				name = p.Name, shape = tostring(p.Shape or "Enum.PartType.Block"),
				size = { p.Size.X, p.Size.Y, p.Size.Z },
				r = p.CFrame.r, pos = p.CFrame.p,
				color = { p.Color.R, p.Color.G, p.Color.B },
				alpha = 1 - (p.Transparency or 0),
			})
		end
	end
	table.insert(out, { skin = entry[1], team = entry[2], parts = parts })
end
local function enc(v)
	if type(v) == "table" then
		if #v > 0 or next(v) == nil then
			local items = {}
			for _, x in v do table.insert(items, enc(x)) end
			return "[" .. table.concat(items, ",") .. "]"
		end
		local items = {}
		for k, x in v do table.insert(items, string.format("%q", k) .. ":" .. enc(x)) end
		return "{" .. table.concat(items, ",") .. "}"
	elseif type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end
print(enc(out))
"""


def main() -> None:
    luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
    out = sys.argv[2] if len(sys.argv) > 2 else "tools/out/looks.png"
    wanted = sys.argv[3:] or ["Classic:Human", "ClassicZombie:Zombie", "Alpha:Zombie", "Donkey:Human", "Dog:Human"]
    args = "local ARGS = {" + ",".join('{"%s","%s"}' % tuple(w.split(":")) for w in wanted) + "}\n"
    pieces = [FAKES, PRELUDE]
    for name in MODULES:
        pieces.append(f'__sources["{name}"] = function(script)\n{module_source(name)}\nend\n')
    for name in SERVER_MODULES:
        text = (Path(__file__).resolve().parent.parent / "src" / "server" / f"{name}.luau").read_text()
        text = re.sub(r"^export type ", "type ", text, flags=re.MULTILINE)
        pieces.append(f'__sources["{name}"] = function(script)\n{text}\nend\n')
    pieces.append(args + MAIN)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False) as handle:
        handle.write("\n".join(pieces))
    result = subprocess.run([luau, handle.name], capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(result.stderr or result.stdout)
    data = json.loads(result.stdout.strip().splitlines()[-1])

    furniture = any(look["team"] == "Furniture" for look in data)
    items = any(look["team"] == "Item" for look in data)
    cell, scale = (520, 26) if furniture else (520, 52) if items else (260, 40)  # px per cell, px per stud
    image = Image.new("RGBA", (cell * len(data), cell + 30), (205, 140, 85, 255))
    draw = ImageDraw.Draw(image)
    for index, look in enumerate(data):
        ox, oz = index * cell + cell / 2, cell / 2 + 10
        if look["team"] == "Item":
            oz = cell - 70  # items point up the picture from the hand
        shapes = []
        for p in look["parts"]:
            r, pos, size = p["r"], p["pos"], p["size"]
            shape = p["shape"]
            # Vertical half-extent decides draw order (top-most last).
            half = [size[0] / 2, size[1] / 2, size[2] / 2]
            if "Ball" in shape:
                top = pos[1] + half[0]
            else:
                top = pos[1] + sum(abs(r[1][j]) * half[j] for j in range(3))
            shapes.append((top, p))
        shapes.sort(key=lambda t: t[0])
        for _, p in shapes:
            r, pos, size = p["r"], p["pos"], p["size"]
            color = tuple(int(max(0, min(1, c)) * 255) for c in p["color"]) + (int(p.get("alpha", 1) * 255),)
            layer = Image.new("RGBA", image.size, (0, 0, 0, 0)) if color[3] < 255 else None
            pen = ImageDraw.Draw(layer) if layer else draw
            cx, cz = ox + pos[0] * scale, oz + pos[2] * scale
            shape = p["shape"]
            if "Ball" in shape or ("Cylinder" in shape and abs(r[1][0]) > 0.9):
                radius = (size[0] if "Ball" in shape else size[1]) / 2 * scale
                pen.ellipse([cx - radius, cz - radius, cx + radius, cz + radius], fill=color)
            else:
                # Footprint of a block (or a lying cylinder) seen from above.
                corners = []
                for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                    local = [sx * size[0] / 2, 0, sz * size[2] / 2]
                    if "Cylinder" in shape:
                        local = [sx * size[0] / 2, 0, sz * size[1] / 2]
                    wx = sum(r[0][j] * local[j] for j in range(3))
                    wz = sum(r[2][j] * local[j] for j in range(3))
                    corners.append((cx + wx * scale, cz + wz * scale))
                pen.polygon(corners, fill=color)
            if layer:
                image.alpha_composite(layer)
        draw.text((index * cell + 8, cell + 10), f"{look['skin']}", fill=(20, 20, 20))
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    image.save(out)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
