"""Generates the hand-planned maps into MapLayout.luau: Christmas Town and
the Halloween maps (Haunted House, Pumpkin Farm, Spooky Village, Witch Woods).

Walls, doors, windows, secret walls, rooms and outdoor things are written
by hand below; furniture is fitted into each room automatically (against
the walls for big pieces, never in a doorway, an item spot or a cobweb),
so a room's contents are just a list of names. Rerun after editing:

    python3 tools/map_plans.py

then run the tests (tools/run_tests.py): they check every room is
reachable, doorways are clear and nothing overlaps.
"""

from __future__ import annotations

import math
import random
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAYOUT = ROOT / "src" / "shared" / "MapLayout.luau"
BEGIN = "-- BEGIN GENERATED MAPS (tools/map_plans.py) --"
END = "-- END GENERATED MAPS --"

T = 3.0
SCALE = 1.15
KEEP = {"Beanbag", "Bed", "Bookshelf", "Car", "Dresser", "Lamp", "Rug", "Sink", "Stove", "TVStand"}
SPECS = {
    "Couch": (10, 3.6), "Armchair": (3.8, 3.8), "Fridge": (4, 4), "Stove": (4, 3.6), "Sink": (4, 3),
    "Toilet": (2.6, 3.4), "Bathtub": (9, 4.6), "Bed": (7, 10), "Table": (8, 5), "CoffeeTable": (4, 3),
    "Chair": (2.4, 2.4), "Bookshelf": (9, 2), "Box": (2.6, 2.6), "Plant": (2.2, 2.2), "Picture": (4, 3),
    "Rug": (12, 8), "Wardrobe": (6, 2.6), "Piano": (8, 4.5), "PoolTable": (10, 6), "Dresser": (5, 2.4),
    "Washer": (3, 3), "Desk": (6, 3), "Crate": (3.4, 3.4), "Barrel": (2.4, 2.4), "Bench": (6, 2),
    "Lamp": (1.8, 1.8), "Beanbag": (3.4, 3.4), "TrashCan": (2.2, 2.2), "Aquarium": (6, 2.6),
    "Tombstone": (3.2, 1.4), "Coffin": (3, 7), "Candelabra": (1.6, 1.6), "Cauldron": (3.6, 3.6),
    "Pumpkin": (2.4, 2.4), "JackOLantern": (2.6, 2.6), "HayBale": (5, 2.6),
    "ChristmasTree": (5, 5), "Present": (2, 2), "Snowman": (3.4, 3.4), "Scarecrow": (3.4, 1.6),
}
AGAINST_WALL = {"Bookshelf", "Wardrobe", "Dresser", "Bed", "Piano", "Fridge", "Stove", "Sink", "Bathtub",
                "Toilet", "Washer", "Aquarium", "Couch", "Bench", "Desk", "Picture"}
ROOM_GAP = 2.4  # walking room left between pieces indoors
YARD_GAP = 3.0
LANE = 3.8  # half-width of the clear lanes kept for the biggest players (MAX_SCALE)


def size(kind, rot=0):
    w, d = SPECS[kind]
    if kind not in KEEP:
        w, d = w * SCALE, d * SCALE
    return (d, w) if rot % 180 == 90 else (w, d)


def rect(x1, z1, x2, z2):
    return (min(x1, x2), min(z1, z2), max(x1, x2), max(z1, z2))


def overlap(a, b, m=0.0):
    return a[0] < b[2] + m and b[0] < a[2] + m and a[1] < b[3] + m and b[1] < a[3] + m


def around(x, z, r):
    return (x - r, z - r, x + r, z + r)


class Plan:
    def __init__(self, name, w, d):
        self.name, self.w, self.d = name, w, d
        self.walls = []  # (x1, z1, x2, z2, gaps, windows, secrets)
        self.rooms = []  # (name, floor, rect, contents)
        self.fixed = []  # (kind, x, z, rot)
        self.cobwebs = []  # (x, z, r)
        self.rugs = []  # (x, z)
        self.items = []

    def wall(self, x1, z1, x2, z2, gaps=(), windows=(), secrets=()):
        self.walls.append((x1, z1, x2, z2, list(gaps), list(windows), list(secrets)))

    def room(self, name, floor, x1, z1, x2, z2, contents=()):
        self.rooms.append((name, floor, rect(x1, z1, x2, z2), list(contents)))

    def obstacles(self):
        walls, zones = [], []
        for x1, z1, x2, z2, gaps, _windows, secrets in self.walls:
            h = T / 2
            horizontal = z1 == z2
            walls.append(rect(x1 - h, z1 - h, x2 + h, z2 + h))
            for a, b in gaps + secrets:
                reach = h + 3 + 0.8
                zones.append(
                    rect(a - 0.6, z1 - reach, b + 0.6, z1 + reach)
                    if horizontal
                    else rect(x1 - reach, a - 0.6, x1 + reach, b + 0.6)
                )
        for x, z, r in self.cobwebs:
            zones.append(around(x, z, r + 1.5))
        return walls, zones

    def furnish(self, rng):
        walls, zones = self.obstacles()
        placed = [self._rect(*f) for f in self.fixed]
        furniture = list(self.fixed)
        for x, z in self.rugs:
            furniture.append(("Rug", x, z, 0))
        for name, _floor, r, contents in self.rooms:
            area = (r[0] + T / 2 + 0.15, r[1] + T / 2 + 0.15, r[2] - T / 2 - 0.15, r[3] - T / 2 - 0.15)
            reserved = []
            if "hall" in name.lower():
                # A clear lane down the middle of every hallway.
                cx, cz = (r[0] + r[2]) / 2, (r[1] + r[3]) / 2
                if r[2] - r[0] >= r[3] - r[1]:
                    reserved.append((r[0], cz - LANE, r[2], cz + LANE))
                else:
                    reserved.append((cx - LANE, r[1], cx + LANE, r[3]))
            target = None
            roomy = min(area[2] - area[0], area[3] - area[1]) >= 14
            if contents and roomy:
                target = self._item_spot(area, zones, placed)
                if target:
                    self.items.append(target)
                    reserved.append(around(*target, 3.4))
            target = target or ((r[0] + r[2]) / 2, (r[1] + r[3]) / 2)
            # A wide lane from each doorway of the room to its middle.
            for door, normal in self.doors_of(r):
                reserved += lane(door, normal, target)
            furniture += fit(rng, area, contents, placed, walls, zones + reserved, ROOM_GAP, against=True)
        return furniture

    def doors_of(self, r):
        """Doorways (and secret walls) on the room's edges: (point on the wall, inward normal)."""
        out = []
        for x1, z1, x2, z2, gaps, _windows, secrets in self.walls:
            for a, b in gaps + secrets:
                mid = (a + b) / 2
                if z1 == z2 and r[0] < mid < r[2] and z1 in (r[1], r[3]):
                    out.append(((mid, z1), (0, 1) if z1 == r[1] else (0, -1)))
                elif x1 == x2 and r[1] < mid < r[3] and x1 in (r[0], r[2]):
                    out.append(((x1, mid), (1, 0) if x1 == r[0] else (-1, 0)))
        return out

    def _item_spot(self, area, zones, placed):
        cx, cz = (area[0] + area[2]) / 2, (area[1] + area[3]) / 2
        for dx, dz in [(0, 0), (3, 3), (-3, -3), (3, -3), (-3, 3), (0, 6), (0, -6), (6, 0), (-6, 0)]:
            x, z = cx + dx, cz + dz
            box = around(x, z, 3.4)
            if box[0] < area[0] or box[2] > area[2] or box[1] < area[1] or box[3] > area[3]:
                continue
            if any(overlap(box, o) for o in zones + placed):
                continue
            return (round(x, 2), round(z, 2))
        return None

    @staticmethod
    def _rect(kind, x, z, rot):
        w, d = size(kind, rot)
        return (x - w / 2, z - d / 2, x + w / 2, z + d / 2)


def lane(door, normal, target):
    """Two strips (in through the door, then across) from a doorway to `target`."""
    (dx, dz), (nx, nz) = door, normal
    tx, tz = target
    if nx:  # door in a vertical wall: go along X first
        bend = (tx, dz)
    else:
        bend = (dx, tz)
    first = rect(dx - LANE, dz - LANE, bend[0] + LANE, bend[1] + LANE)
    first = rect(min(dx, bend[0]) - LANE, min(dz, bend[1]) - LANE, max(dx, bend[0]) + LANE, max(dz, bend[1]) + LANE)
    second = rect(min(bend[0], tx) - LANE, min(bend[1], tz) - LANE, max(bend[0], tx) + LANE, max(bend[1], tz) + LANE)
    return [first, second]


def fit(rng, area, kinds, placed, walls, zones, gap, against):
    out = []
    ix1, iz1, ix2, iz2 = area
    for kind in kinds:
        options = []
        for rot in (0, 90, 180, 270):
            wall_piece = against and kind in AGAINST_WALL
            if not wall_piece and rot in (180, 270):
                continue
            w, d = size(kind, rot)
            if w > ix2 - ix1 or d > iz2 - iz1:
                continue
            nx, nz = int((ix2 - ix1 - w) / 0.5) + 1, int((iz2 - iz1 - d) / 0.5) + 1
            for i in range(nx):
                x = ix1 + w / 2 + i * 0.5
                for j in range(nz):
                    z = iz1 + d / 2 + j * 0.5
                    r = (x - w / 2, z - d / 2, x + w / 2, z + d / 2)
                    if wall_piece:
                        touching = {
                            0: abs(r[1] - iz1) < 0.26,
                            180: abs(r[3] - iz2) < 0.26,
                            90: abs(r[0] - ix1) < 0.26,
                            270: abs(r[2] - ix2) < 0.26,
                        }
                        if not touching[rot]:
                            continue
                    if any(overlap(r, o, gap) for o in placed):
                        continue
                    if any(overlap(r, o) for o in zones) or any(overlap(r, o) for o in walls):
                        continue
                    options.append((rng.random(), x, z, rot, r))
        if not options:
            continue  # no room left for it: leave it out
        options.sort()
        _, x, z, rot, r = options[0]
        placed.append(r)
        out.append((kind, round(x, 2), round(z, 2), rot))
    return out


# --- Shared small buildings ----------------------------------------------------------------

def outhouse():
    p = Plan("OUTHOUSE", 12, 12)
    p.wall(0, 0, 12, 0)
    p.wall(0, 12, 12, 12, gaps=[(2.5, 9.5)])
    p.wall(0, 0, 0, 12)
    p.wall(12, 0, 12, 12)
    p.room("Outhouse", "Wood", 0, 0, 12, 12)
    p.fixed.append(("Toilet", 6, 3.5, 0))
    return p


def crypt():
    p = Plan("CRYPT", 30, 24)
    p.wall(0, 0, 30, 0)
    p.wall(0, 24, 30, 24, gaps=[(11.5, 18.5)])
    p.wall(0, 0, 0, 24)
    p.wall(30, 0, 30, 24)
    p.room("Crypt", "Concrete", 0, 0, 30, 24)
    p.fixed += [("Coffin", 8, 11, 0), ("Coffin", 15, 11, 0), ("Coffin", 22, 11, 0),
                ("Candelabra", 3.5, 3.5, 0), ("Candelabra", 26.5, 3.5, 0)]
    p.items.append((15, 19))
    p.cobwebs.append((26, 20, 2))
    return p


def garden_shed():
    p = Plan("GARDEN_SHED", 28, 20)
    p.wall(0, 0, 28, 0, gaps=[(10.5, 17.5)])
    p.wall(0, 20, 28, 20, windows=[(8, 20)])
    p.wall(0, 0, 0, 20)
    p.wall(28, 0, 28, 20)
    p.room("Shed", "Wood", 0, 0, 28, 20)
    p.fixed += [("Crate", 4, 16, 0), ("Barrel", 9, 16.8, 0), ("Box", 23.5, 16.5, 0), ("Box", 23.5, 13, 0),
                ("TrashCan", 4, 4, 0), ("Cauldron", 22, 5, 0)]
    p.items.append((14, 10))
    return p


# --- Haunted manor --------------------------------------------------------------------------

def manor():
    p = Plan("MANOR", 240, 150)
    # Outside walls
    p.wall(0, 0, 240, 0, gaps=[(116.5, 123.5)],
           windows=[(8, 28), (54, 82), (92, 108), (132, 160), (170, 206), (227, 237)])
    p.wall(0, 150, 240, 150, gaps=[(116, 124)],
           windows=[(6, 30), (54, 82), (92, 108), (132, 164), (186, 234)])
    p.wall(0, 0, 0, 150, gaps=[(64.5, 71.5)], windows=[(10, 50), (86, 140)])
    p.wall(240, 0, 240, 150, gaps=[(64.5, 71.5)], windows=[(10, 50), (86, 140)])
    # The main hallway (east-west) and the cross hallway (north-south)
    p.wall(0, 60, 112, 60, gaps=[(14, 21), (38.5, 45.5), (62, 69), (96, 103)])
    p.wall(128, 60, 240, 60, gaps=[(142, 149), (182, 189), (214.5, 221.5), (228.5, 235.5)])
    p.wall(0, 76, 112, 76, gaps=[(12, 19), (38.5, 45.5), (64, 71), (96, 103)])
    p.wall(128, 76, 240, 76, gaps=[(142, 149), (170.5, 177.5), (200, 207), (220, 227)])
    p.wall(112, 0, 112, 60, gaps=[(11, 18)])
    p.wall(128, 0, 128, 60, gaps=[(14, 21)])
    p.wall(112, 76, 112, 150, gaps=[(90, 97)])
    p.wall(128, 76, 128, 150, gaps=[(125, 132)])
    # North-west: library, a hidden nook and a closet, bedroom, bathroom, closet
    p.wall(36, 0, 36, 60, secrets=[(12, 19)])
    p.wall(48, 0, 48, 60)
    p.wall(36, 40, 48, 40, secrets=[(39, 45)])
    p.wall(88, 0, 88, 60, secrets=[(40, 47)])
    p.wall(88, 30, 112, 30)
    # North-east: study, nursery, gallery, a hidden nook and a closet, washroom
    p.wall(164, 0, 164, 60, gaps=[(20, 27)])
    p.wall(128, 36, 164, 36, gaps=[(140, 147)])
    p.wall(212, 0, 212, 60, secrets=[(14, 21)])
    p.wall(224, 0, 224, 60, secrets=[(24, 31)])
    p.wall(212, 40, 224, 40, secrets=[(215, 221)])
    # South-west: kitchen, pantry, cellar (secret), dining room, servants' rooms
    p.wall(36, 76, 36, 150, gaps=[(90, 97)], secrets=[(124, 131)])
    p.wall(48, 76, 48, 150, secrets=[(124, 131)])
    p.wall(36, 112, 48, 112, secrets=[(39, 45)])
    p.wall(88, 76, 88, 150, secrets=[(128, 135)])
    p.wall(88, 112, 112, 112, gaps=[(96, 103)])
    # South-east: foyer, closets, ballroom
    p.wall(168, 76, 168, 150, gaps=[(125, 132)])
    p.wall(180, 76, 180, 150, gaps=[(135, 142)])
    p.wall(168, 112, 180, 112, secrets=[(171, 177)])

    c = "Candelabra"
    p.room("Library", "Wood", 0, 0, 36, 60,
           ["Bookshelf", "Bookshelf", "Bookshelf", "Desk", "Chair", "Armchair", "Armchair", c, c, "JackOLantern", "Box"])
    p.room("Hidden nook", "Wood", 36, 0, 48, 40, ["Coffin", c])
    p.room("Linen closet", "Wood", 36, 40, 48, 60, ["Box", "Box"])
    p.room("Bedroom", "Wood", 48, 0, 88, 60,
           ["Bed", "Bed", "Wardrobe", "Wardrobe", "Dresser", "Chair", c, "Pumpkin", "Plant", "Box"])
    p.room("Bathroom", "Tile", 88, 0, 112, 30, ["Bathtub", "Toilet", "Sink", "Washer", "Cauldron"])
    p.room("Junk closet", "Wood", 88, 30, 112, 60, ["Box", "Box", "Crate", "Barrel"])
    p.room("North hall", "Tile", 112, 0, 128, 60, [c, c, "Bench", "JackOLantern"])
    p.room("Study", "Wood", 128, 0, 164, 36, ["Desk", "Chair", "Bookshelf", "Bookshelf", "PoolTable", c])
    p.room("Nursery", "Wood", 128, 36, 164, 60, ["Bed", "Beanbag", "Armchair", "Box", "Pumpkin", c])
    p.room("Gallery", "Brick", 164, 0, 212, 60,
           ["Piano", "Bench", "Bench", "Picture", "Picture", "Armchair", "Armchair", c, c, "Plant", "Plant", "JackOLantern"])
    p.room("Dusty nook", "Wood", 212, 0, 224, 40, ["Barrel", "Barrel", "Box"])
    p.room("Storage closet", "Wood", 212, 40, 224, 60, ["Box", "Box"])
    p.room("Washroom", "Tile", 224, 0, 240, 60, ["Bathtub", "Toilet", "Sink", "Cauldron"])
    p.room("Main hall", "Tile", 0, 60, 240, 76,
           ["Bench", "Bench", "Bench", c, c, c, c, c, "JackOLantern", "JackOLantern", "JackOLantern",
            "Armchair", "Armchair", "Crate", "Crate", "Pumpkin", "Pumpkin", "Pumpkin"])
    p.room("Kitchen", "Tile", 0, 76, 36, 150,
           ["Fridge", "Stove", "Stove", "Sink", "Sink", "Table", "Chair", "Chair", "Chair", "Cauldron",
            "Barrel", "Barrel", "TrashCan", "Pumpkin", "Pumpkin", "Pumpkin", "Crate"])
    p.room("Pantry", "Wood", 36, 76, 48, 112, ["Crate", "Crate", "Barrel", "Barrel", "Pumpkin", "Pumpkin"])
    p.room("Cellar", "Concrete", 36, 112, 48, 150, ["Coffin", "Barrel", c])
    p.room("Dining room", "Wood", 48, 76, 88, 150,
           ["Table", "Table", "Chair", "Chair", "Chair", "Chair", "Chair", "Chair", "Chair", "Chair",
            c, c, "Dresser", "JackOLantern", "JackOLantern", "Plant"])
    p.room("Servants' hall", "Wood", 88, 76, 112, 112, ["Table", "Chair", "Chair", "Bench", "Barrel"])
    p.room("Servant's room", "Wood", 88, 112, 112, 150, ["Bed", "Dresser", "Box", c])
    p.room("South hall", "Tile", 112, 76, 128, 150, [c, c, "JackOLantern", "JackOLantern", "Bench"])
    p.room("Foyer", "Brick", 128, 76, 168, 150,
           ["Couch", "Armchair", "Armchair", "Coffin", c, c, "Plant", "Plant", "JackOLantern", "JackOLantern", "Bench"])
    p.room("Broom closet", "Wood", 168, 76, 180, 112, ["Box", "Box", "TrashCan", "Barrel"])
    p.room("Coat closet", "Wood", 168, 112, 180, 150, ["Box", "Box", "Dresser"])
    p.room("Ballroom", "Wood", 180, 76, 240, 150,
           ["PoolTable", "Piano", "Couch", "Couch", "Armchair", "Armchair", "Armchair", "CoffeeTable", c, c, c, c,
            "Bench", "Bench", "JackOLantern", "JackOLantern", "JackOLantern", "Pumpkin", "Pumpkin", "Crate", "Crate",
            "Aquarium", "Wardrobe"])
    p.rugs += [(18, 34), (68, 34), (188, 30), (68, 113), (148, 113), (210, 113)]
    p.cobwebs += [(42, 4.5, 2.5), (218, 4.5, 2.5), (42, 145.5, 2.5), (174, 107.5, 2.5), (174, 145.5, 2.5),
                  (4.5, 4.5, 3), (235.5, 145.5, 3), (106, 145.5, 3), (92.5, 34.5, 2.5)]
    return p


# --- Christmas Town -------------------------------------------------------------------------

def cottage():
    p = Plan("COTTAGE", 44, 32)
    p.wall(0, 0, 44, 0, gaps=[(30, 37)], windows=[(4, 20)])
    p.wall(0, 32, 44, 32, gaps=[(8, 15)], windows=[(28, 40)])
    p.wall(0, 0, 0, 32, windows=[(8, 24)])
    p.wall(44, 0, 44, 32, windows=[(3, 13), (19, 29)])
    p.wall(24, 0, 24, 32, gaps=[(4, 11), (20, 27)])
    p.wall(24, 16, 44, 16, gaps=[(30, 37)])
    p.room("Living room", "Wood", 0, 0, 24, 32,
           ["Couch", "Armchair", "CoffeeTable", "Lamp", "ChristmasTree", "Present", "Present", "Present"])
    p.room("Bedroom", "Wood", 24, 0, 44, 16, ["Wardrobe", "Bed", "Box"])
    p.room("Kitchen", "Tile", 24, 16, 44, 32, ["Fridge", "Stove", "Sink", "Chair"])
    return p


def workshop():
    p = Plan("WORKSHOP", 120, 60)
    p.wall(0, 0, 120, 0, windows=[(10, 60), (76, 94), (104, 116)])
    p.wall(0, 60, 120, 60, gaps=[(31, 39), (81, 88)], windows=[(8, 24), (46, 62), (104, 116)])
    p.wall(0, 0, 0, 60, gaps=[(26.5, 33.5)], windows=[(6, 20), (40, 54)])
    p.wall(120, 0, 120, 60, windows=[(8, 22), (38, 52)])
    p.wall(70, 0, 70, 60, gaps=[(11, 18), (41, 48)])
    p.wall(70, 30, 100, 30, gaps=[(82, 89)])
    p.wall(100, 0, 100, 60, gaps=[(11, 18), (41, 48)])
    p.room("Toy workshop", "Wood", 0, 0, 70, 60,
           ["Table", "Table", "Table", "Chair", "Chair", "Chair", "Chair", "Chair", "Chair", "Present", "Present",
            "Present", "Present", "Present", "Present", "Crate", "Crate", "Crate", "Box", "Box", "Box", "Box",
            "ChristmasTree", "Bench", "Bench", "Desk", "Bookshelf"])
    p.room("Wrapping room", "Wood", 70, 0, 100, 30,
           ["Table", "Present", "Present", "Present", "Present", "Present", "Present", "Box", "Box"])
    p.room("Santa's office", "Wood", 70, 30, 100, 60,
           ["Desk", "Chair", "Bookshelf", "Armchair", "Plant", "Present", "Piano"])
    p.room("Storeroom", "Concrete", 100, 0, 120, 60,
           ["Crate", "Crate", "Crate", "Crate", "Barrel", "Barrel", "Box", "Box", "Box", "Box", "Present", "Present", "Present"])
    p.rugs.append((35, 30))
    return p


def gingerbread():
    p = Plan("GINGERBREAD", 30, 24)
    p.wall(0, 0, 30, 0, windows=[(6, 24)])
    p.wall(0, 24, 30, 24, gaps=[(11.5, 18.5)])
    p.wall(0, 0, 0, 24, windows=[(6, 18)])
    p.wall(30, 0, 30, 24, windows=[(6, 18)])
    p.room("Gingerbread house", "Wood", 0, 0, 30, 24,
           ["ChristmasTree", "Present", "Present", "Present", "Present", "Table", "Chair", "Chair"])
    return p


# --- Maps -------------------------------------------------------------------------------------

class Map:
    def __init__(self, fn, name, title, theme, roofs, bounds):
        self.fn, self.name, self.title, self.theme, self.roofs, self.bounds = fn, name, title, theme, roofs, bounds
        self.houses = []  # (id, plan, ox, oz, rotated, outline, size[, wall color])
        self.yard_rooms = []  # (name, floor, rect, contents, fixed)
        self.yard_pieces = []  # fixed outdoor pieces (kind, x, z, rot)
        self.yard_scatter = []  # kinds placed anywhere outdoors
        self.paths, self.patios, self.pools = [], [], []
        self.road = {"sidewalks": [], "asphalt": [], "centerLines": [], "edgeLines": []}
        self.bushes = []
        self.human, self.zombie, self.wizard = [], [], []
        self.start = (0, 0)
        self.items = []

    def house_rect(self, h):
        _id, plan, ox, oz = h[0], h[1], h[2], h[3]
        return (ox, oz, ox + plan.w, oz + plan.d)

    def to_world(self, h, x, z):
        _id, plan, ox, oz, rotated = h[0], h[1], h[2], h[3], h[4]
        return (ox + (plan.w - x if rotated else x), oz + (plan.d - z if rotated else z))


def haunted():
    m = Map("buildHaunted", "Haunted", "The Haunted House", "Haunted", True, (-180, -170, 180, 170))
    m.houses.append(("Manor", manor(), -120, -120, False, "Blue", "Huge"))
    m.houses.append(("Crypt", crypt(), 130, -160, False, "Orange", "Small"))
    m.houses.append(("Shed", garden_shed(), -170, 60, False, "Orange", "Small"))
    spots = [(-170, -100, False), (-170, -20, False), (-90, -160, True), (-30, -160, True), (30, -160, True),
             (160, -60, False), (160, 30, False), (-60, 140, True)]
    for i, (ox, oz, rotated) in enumerate(spots, 1):
        m.houses.append(("Outhouse%d" % i, outhouse(), ox, oz, rotated, "Orange", "Small"))
    tombstones = [("Tombstone", x, z, 0) for z in (75, 92, 109, 126, 143) for x in (56, 74, 92, 110, 128, 146)]
    m.yard_rooms.append(("Graveyard", "Dirt", (40, 60, 170, 150),
                         ["Pumpkin"] * 4 + ["JackOLantern"] * 3 + ["Coffin", "Bench"], tombstones))
    m.yard_rooms.append(("Pumpkin patch", "Dirt", (-170, 95, -66, 160),
                         ["Pumpkin"] * 26 + ["JackOLantern"] * 8 + ["HayBale"] * 5, []))
    m.yard_pieces += [("JackOLantern", -10, 34, 0), ("JackOLantern", 10, 34, 0)]
    m.paths = [rect(-4, 30, 4, 170), rect(4, 100, 40, 106), rect(141, -136, 149, -60), rect(-160, 30, -152, 60)]
    m.patios = [rect(-16, 30, 16, 38)]
    m.pools = [rect(-45, 95, -12, 125)]
    m.bushes = [(-172, -160, 5, "Green"), (-120, -165, 4, "Orange"), (60, -165, 4, "Green"), (172, -120, 5, "Orange"),
                (172, 0, 4, "Green"), (-172, 50, 4, "Orange"), (-30, 160, 5, "Green"), (110, 160, 4, "Orange"),
                (-100, 40, 4, "Green"), (60, 45, 4, "Orange")]
    m.human = [(-150, -130), (-110, -145), (0, -150), (80, -150), (165, -90), (165, 10), (-150, 30), (-120, 70),
               (20, 60), (-30, 150), (100, 160), (174, 100)]
    m.zombie = [(165, -160), (-170, 0)]
    m.start = (0, 65)
    m.wizard = [(-140, -165), (140, -40), (-100, 165), (150, 165)]
    return m


def christmas():
    m = Map("buildChristmasTown", "ChristmasTown", "Christmas Town", "Winter", False, (-170, -170, 170, 170))
    m.houses.append(("Workshop", workshop(), -60, -150, False, "Orange", "Huge"))
    m.houses.append(("CottageA", cottage(), -160, -60, False, "Blue", "Small"))
    m.houses.append(("CottageB", cottage(), 116, -60, False, "Orange", "Small"))
    m.houses.append(("CottageC", cottage(), -160, 20, True, "Orange", "Small"))
    m.houses.append(("CottageD", cottage(), 116, 20, True, "Blue", "Small"))
    m.houses.append(("Gingerbread", gingerbread(), -15, 40, False, "Orange", "Small"))
    m.patios = [rect(-45, -60, 45, 10)]
    m.paths = [rect(-29, -90, -21, -60), rect(21, -90, 28, -60), rect(-90, -124, -60, -116)]
    m.pools = [rect(45, 40, 90, 70)]  # a frozen pond
    m.road = {
        "sidewalks": [rect(-170, 92, 170, 100), rect(-170, 128, 170, 136)],
        "asphalt": [rect(-170, 100, 170, 128)],
        "centerLines": [rect(-170, 113.6, 170, 114.4)],
        "edgeLines": [rect(-170, 101, 170, 101.4), rect(-170, 126.6, 170, 127)],
    }
    m.yard_pieces += [("ChristmasTree", 0, -48, 0), ("Present", -5, -42, 0), ("Present", 5, -42, 0),
                      ("Present", 0, -40, 0), ("Present", -6, -52, 0), ("Present", 6, -52, 0),
                      ("Snowman", -35, -50, 0), ("Snowman", 35, -50, 0), ("Snowman", -35, 0, 0), ("Snowman", 35, 0, 0)]
    m.yard_scatter = ["Snowman"] * 6 + ["ChristmasTree"] * 8 + ["Present"] * 14
    m.bushes = [(-160, -160, 5, "Green"), (-100, -165, 4, "Orange"), (100, -165, 4, "Green"), (160, -160, 5, "Orange"),
                (-165, 0, 4, "Green"), (165, 0, 4, "Orange"), (-80, 80, 4, "Green"), (80, 85, 3, "Orange"),
                (-160, 160, 5, "Green"), (160, 160, 5, "Orange"), (-30, 75, 3, "Green")]
    m.human = [(-130, 75), (0, 80), (130, 75), (-120, -100), (120, -100), (-90, -10), (90, -10), (-100, -150),
               (100, -150), (0, -160)]
    m.zombie = [(-160, 114), (160, 114)]
    m.start = (0, -10)
    m.wizard = [(-150, -150), (150, -150), (-150, 150), (150, 150)]
    return m


# --- More Halloween maps ---------------------------------------------------------------------

def farmhouse():
    p = Plan("FARMHOUSE", 64, 44)
    p.wall(0, 0, 64, 0, windows=[(5, 23), (33, 59)])
    p.wall(0, 44, 64, 44, gaps=[(32, 39)], windows=[(4, 24), (48, 60)])
    p.wall(0, 0, 0, 44, gaps=[(8, 15)], windows=[(26, 40)])
    p.wall(64, 0, 64, 44, windows=[(4, 18), (27, 40)])
    p.wall(28, 0, 28, 44, gaps=[(8, 15), (30, 37)])
    p.wall(0, 22, 64, 22, gaps=[(10, 17), (32, 39), (50, 57)])
    p.wall(44, 22, 44, 44, gaps=[(30, 37)])
    c = "Candelabra"
    p.room("Kitchen", "Tile", 0, 0, 28, 22, ["Fridge", "Stove", "Sink", "Table", "Chair", "Chair", "Pumpkin", "Barrel"])
    p.room("Parlor", "Wood", 28, 0, 64, 22, ["Piano", "Couch", "Armchair", "CoffeeTable", c, "JackOLantern"])
    p.room("Bedroom", "Wood", 0, 22, 28, 44, ["Bed", "Wardrobe", "Dresser", c])
    p.room("Mudroom", "Wood", 28, 22, 44, 44, ["Bench", "Box", "Pumpkin"])
    p.room("Back bedroom", "Wood", 44, 22, 64, 44, ["Bed", "Wardrobe", "Box"])
    return p


def barn():
    p = Plan("BARN", 90, 60)
    p.wall(0, 0, 90, 0, windows=[(4, 14), (22, 32), (40, 50), (58, 68), (76, 86)])
    p.wall(0, 60, 90, 60, gaps=[(20, 28), (62, 70)])
    p.wall(0, 0, 0, 60, gaps=[(34, 41)])
    p.wall(90, 0, 90, 60, gaps=[(34, 41)])
    p.wall(0, 18, 90, 18, gaps=[(5.5, 12.5), (23.5, 30.5), (41.5, 48.5), (59.5, 66.5), (77.5, 84.5)])
    for x in (18, 36, 54, 72):
        p.wall(x, 0, x, 18)
    for i in range(4):
        p.room("Stall %d" % (i + 1), "Wood", i * 18, 0, i * 18 + 18, 18, ["HayBale", "Barrel"])
    p.room("Tack room", "Wood", 72, 0, 90, 18, ["Wardrobe", "Crate", "Box"])
    p.room("Barn floor", "Wood", 0, 18, 90, 60,
           ["HayBale"] * 10 + ["Crate", "Crate", "Crate", "Barrel", "Barrel", "Scarecrow", "Pumpkin", "Pumpkin",
                               "Pumpkin", "JackOLantern", "JackOLantern"])
    p.cobwebs += [(3.5, 3.5, 2), (86.5, 3.5, 2)]
    return p


def corn_maze(rng, cols=8, rows=6, cell=12):
    """A random maze of tall corn walls with a few walk-through (secret) shortcuts."""
    p = Plan("CORN_MAZE", cols * cell, rows * cell)
    open_edges = set()
    seen = {(0, 0)}
    stack = [(0, 0)]
    while stack:
        cx, cz = stack[-1]
        nbrs = [(cx + dx, cz + dz) for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1))
                if 0 <= cx + dx < cols and 0 <= cz + dz < rows and (cx + dx, cz + dz) not in seen]
        if nbrs:
            n = rng.choice(nbrs)
            open_edges.add(frozenset(((cx, cz), n)))
            seen.add(n)
            stack.append(n)
        else:
            stack.pop()
    # A few extra openings so there are loops to run around.
    inner = []
    for i in range(cols):
        for j in range(rows):
            for n in ((i + 1, j), (i, j + 1)):
                if n[0] < cols and n[1] < rows and frozenset(((i, j), n)) not in open_edges:
                    inner.append(((i, j), n))
    rng.shuffle(inner)
    for a, b in inner[:6]:
        open_edges.add(frozenset((a, b)))
    walls_left = [e for e in inner[6:]]
    secrets = set(frozenset(e) for e in walls_left[:4])
    top, bottom = rng.randrange(cols), rng.randrange(cols)
    p.wall(0, 0, cols * cell, 0, gaps=[(top * cell + 2, top * cell + 10)])
    p.wall(0, rows * cell, cols * cell, rows * cell, gaps=[(bottom * cell + 2, bottom * cell + 10)])
    p.wall(0, 0, 0, rows * cell)
    p.wall(cols * cell, 0, cols * cell, rows * cell)
    for i in range(cols):
        for j in range(rows):
            for n in ((i + 1, j), (i, j + 1)):
                if n[0] >= cols or n[1] >= rows or frozenset(((i, j), n)) in open_edges:
                    continue
                secret = frozenset(((i, j), n)) in secrets
                if n[0] == i + 1:  # wall to the east of (i, j)
                    x = (i + 1) * cell
                    p.wall(x, j * cell, x, (j + 1) * cell, secrets=[(j * cell + 3, j * cell + 9)] if secret else [])
                else:  # wall to the south
                    z = (j + 1) * cell
                    p.wall(i * cell, z, (i + 1) * cell, z, secrets=[(i * cell + 3, i * cell + 9)] if secret else [])
    # Dead ends get something spooky; the middle-most open cell keeps an item.
    def exits(c):
        count = sum(1 for e in open_edges if c in e)
        return count + (1 if c in ((top, 0), (bottom, rows - 1)) else 0)
    props = ["JackOLantern", "Scarecrow", "Pumpkin", "HayBale", "JackOLantern", "Pumpkin", "Scarecrow"]
    dead = [(i, j) for i in range(cols) for j in range(rows) if exits((i, j)) == 1]
    for k, (i, j) in enumerate(dead):
        p.fixed.append((props[k % len(props)], i * cell + cell / 2, j * cell + cell / 2, 0))
    middle = min(((i, j) for i in range(cols) for j in range(rows) if (i, j) not in dead),
                 key=lambda c: (c[0] - cols / 2) ** 2 + (c[1] - rows / 2) ** 2)
    p.items.append((middle[0] * cell + cell / 2, middle[1] * cell + cell / 2))
    return p


def village_house():
    p = Plan("VILLAGE_HOUSE", 30, 24)
    p.wall(0, 0, 30, 0, windows=[(3, 13)])
    p.wall(0, 24, 30, 24, gaps=[(4, 11)], windows=[(19, 28)])
    p.wall(0, 0, 0, 24, windows=[(6, 18)])
    p.wall(30, 0, 30, 24, windows=[(6, 18)])
    p.wall(16, 0, 16, 24, gaps=[(9, 16)])
    p.room("Front room", "Wood", 0, 0, 16, 24, ["Armchair", "Table", "Chair", "Candelabra", "Pumpkin"])
    p.room("Back room", "Wood", 16, 0, 30, 24, ["Bed", "Box"])
    p.cobwebs.append((27.5, 2.5, 1.8))
    return p


def cottage_house():
    p = Plan("COTTAGE_HOUSE", 36, 28)
    p.wall(0, 0, 36, 0, windows=[(3, 15), (21, 33)])
    p.wall(0, 28, 36, 28, gaps=[(23, 30)], windows=[(3, 15)])
    p.wall(0, 0, 0, 28, gaps=[(4, 11)], windows=[(17, 25)])
    p.wall(36, 0, 36, 28, windows=[(6, 22)])
    p.wall(18, 0, 18, 28, gaps=[(4, 11), (18, 25)])
    p.wall(0, 14, 18, 14, gaps=[(5.5, 12.5)])
    p.room("Kitchen", "Tile", 0, 0, 18, 14, ["Stove", "Sink", "Barrel"])
    p.room("Bedroom", "Wood", 0, 14, 18, 28, ["Wardrobe", "Bed"])
    p.room("Living room", "Wood", 18, 0, 36, 28, ["Couch", "Armchair", "Candelabra", "JackOLantern", "Box"])
    return p


def village_shop():
    p = Plan("VILLAGE_SHOP", 28, 20)
    p.wall(0, 0, 28, 0, windows=[(3, 15)])
    p.wall(0, 20, 28, 20, gaps=[(5, 12)], windows=[(20, 26)])
    p.wall(0, 0, 0, 20, windows=[(5, 15)])
    p.wall(28, 0, 28, 20, gaps=[(6.5, 13.5)])
    p.wall(18, 0, 18, 20, gaps=[(6.5, 13.5)])
    p.room("Shop", "Wood", 0, 0, 18, 20, ["Table", "Pumpkin", "Pumpkin", "JackOLantern", "Crate"])
    p.room("Storeroom", "Wood", 18, 0, 28, 20, ["Crate", "Barrel", "Box"])
    return p


def inn():
    p = Plan("INN", 50, 40)
    p.wall(0, 0, 50, 0, windows=[(4, 26), (34, 46)])
    p.wall(0, 40, 50, 40, gaps=[(11, 18)], windows=[(34, 46)])
    p.wall(0, 0, 0, 40, windows=[(6, 34)])
    p.wall(50, 0, 50, 40, gaps=[(4, 11)], windows=[(19, 25), (31, 37)])
    p.wall(30, 0, 30, 40, gaps=[(4, 11), (19, 25), (31, 37)])
    p.wall(30, 16, 50, 16)
    p.wall(30, 28, 50, 28)
    c = "Candelabra"
    p.room("Common room", "Wood", 0, 0, 30, 40,
           ["Table", "Table", "Chair", "Chair", "Chair", "Chair", "Bench", c, c, "Barrel", "JackOLantern"])
    p.room("Kitchen", "Tile", 30, 0, 50, 16, ["Stove", "Sink", "Cauldron"])
    p.room("Guest room", "Wood", 30, 16, 50, 28, ["Bed", "Box"])
    p.room("Spare room", "Wood", 30, 28, 50, 40, ["Bed", "Dresser"])
    p.cobwebs.append((47, 37, 1.8))
    return p


def church():
    p = Plan("CHURCH", 40, 70)
    p.wall(0, 0, 40, 0, gaps=[(28, 35)], windows=[(4, 20)])
    p.wall(0, 70, 40, 70, gaps=[(16, 24)], windows=[(3, 13), (27, 37)])
    p.wall(0, 0, 0, 70, windows=[(26, 44), (50, 66)])
    p.wall(40, 0, 40, 70, windows=[(26, 44), (50, 66)])
    p.wall(0, 20, 40, 20, gaps=[(8.5, 15.5), (28.5, 35.5)])
    p.wall(24, 0, 24, 20, secrets=[(6, 13)])
    c = "Candelabra"
    p.room("Nave", "Concrete", 0, 20, 40, 70, ["Bench"] * 8 + [c, c, c, c])
    p.room("Altar", "Brick", 0, 0, 24, 20, ["Coffin", c, c])
    p.room("Bell tower", "Concrete", 24, 0, 40, 20, ["Barrel", "Crate"])
    p.cobwebs += [(37, 3, 1.8), (3, 67, 2)]
    return p


def witch_hut():
    p = Plan("WITCH_HUT", 40, 32)
    p.wall(0, 0, 40, 0, windows=[(4, 22)])
    p.wall(0, 32, 40, 32, gaps=[(16, 23)], windows=[(28, 38)])
    p.wall(0, 0, 0, 32, windows=[(6, 26)])
    p.wall(40, 0, 40, 32, gaps=[(18, 25)])
    p.wall(26, 0, 26, 32, gaps=[(4, 11), (20, 27)])
    p.wall(26, 14, 40, 14)
    c = "Candelabra"
    p.room("Brewing room", "Wood", 0, 0, 26, 32,
           ["Piano", "Wardrobe", "Cauldron", "Cauldron", "Cauldron", "Bookshelf", "Bookshelf", c, c, "JackOLantern", "Pumpkin"])
    p.room("Pantry", "Wood", 26, 0, 40, 14, ["Barrel", "Barrel", "Crate"])
    p.room("Bedroom", "Wood", 26, 14, 40, 32, ["Wardrobe", "Bed"])
    p.cobwebs += [(3, 3, 2), (37, 3, 1.6)]
    return p


def cabin():
    p = Plan("CABIN", 30, 22)
    p.wall(0, 0, 30, 0, windows=[(4, 16)])
    p.wall(0, 22, 30, 22, gaps=[(6, 13)], windows=[(22, 28)])
    p.wall(0, 0, 0, 22, windows=[(5, 17)])
    p.wall(30, 0, 30, 22, windows=[(5, 17)])
    p.wall(20, 0, 20, 22, gaps=[(7.5, 14.5)])
    p.room("Cabin", "Wood", 0, 0, 20, 22, ["Wardrobe", "Table", "Chair", "Chair", "Barrel", "Candelabra"])
    p.room("Bunk room", "Wood", 20, 0, 30, 22, ["Wardrobe", "Box"])
    return p


def mill():
    p = Plan("MILL", 36, 36)
    p.wall(0, 0, 36, 0, windows=[(3, 15), (21, 33)])
    p.wall(0, 36, 36, 36, gaps=[(5.5, 12.5)], windows=[(21, 33)])
    p.wall(0, 0, 0, 36, windows=[(3, 15), (21, 33)])
    p.wall(36, 0, 36, 36, gaps=[(23.5, 30.5)], windows=[(3, 15)])
    p.wall(18, 0, 18, 36, gaps=[(5.5, 12.5), (23.5, 30.5)])
    p.wall(0, 18, 36, 18, gaps=[(5.5, 12.5), (23.5, 30.5)])
    p.room("Millstone room", "Concrete", 0, 0, 18, 18, ["Crate", "Barrel", "HayBale"])
    p.room("Grain room", "Wood", 18, 0, 36, 18, ["HayBale", "Barrel", "Barrel", "Box"])
    p.room("Office", "Wood", 0, 18, 18, 36, ["Desk", "Chair", "Wardrobe"])
    p.room("Storage", "Wood", 18, 18, 36, 36, ["Wardrobe", "Crate", "Box", "Box", "Cauldron", "Pumpkin"])
    p.cobwebs.append((33, 3, 1.6))
    return p


def scatter_trees(m, rng, count, rmin, rmax):
    """Forest: trees (bushes you can hide in) spread out, never in the way."""
    b = m.bounds
    avoid = [(h[0] - 9, h[1] - 9, h[2] + 9, h[3] + 9) for h in (m.house_rect(h) for h in m.houses)]
    avoid += [(r[0] - 5, r[1] - 5, r[2] + 5, r[3] + 5) for _, _, r, _, _ in m.yard_rooms]
    avoid += [(r[0] - 5, r[1] - 5, r[2] + 5, r[3] + 5) for r in m.pools + m.paths + m.patios]
    avoid += [around(x, z, 7) for x, z in m.human + m.zombie + m.wizard]
    avoid += [around(m.start[0], m.start[1], 18)]
    trees = []
    for _ in range(count * 60):
        if len(trees) >= count:
            break
        r = rng.uniform(rmin, rmax)
        x = rng.uniform(b[0] + r + 4, b[2] - r - 4)
        z = rng.uniform(b[1] + r + 4, b[3] - r - 4)
        box = around(x, z, r)
        if any(overlap(box, a) for a in avoid):
            continue
        if any((x - tx) ** 2 + (z - tz) ** 2 < (r + tr + 8) ** 2 for tx, tz, tr, _ in trees + m.bushes):
            continue
        trees.append((round(x, 1), round(z, 1), round(r, 1), "Green" if rng.random() < 0.8 else "Orange"))
    m.bushes += trees


def pumpkin_farm(rng):
    m = Map("buildPumpkinFarm", "PumpkinFarm", "The Pumpkin Farm", "Haunted", True, (-180, -170, 180, 170))
    m.houses.append(("Farmhouse", farmhouse(), -150, -150, False, "Orange", "Large"))
    m.houses.append(("Barn", barn(), -40, -150, False, "Orange", "Huge"))
    m.houses.append(("CornMaze", corn_maze(rng), 66, -40, False, "Orange", "Huge", "B8963A"))
    m.houses.append(("Shed", garden_shed(), 110, -150, False, "Orange", "Small"))
    m.houses.append(("Outhouse1", outhouse(), -172, -60, False, "Orange", "Small"))
    m.houses.append(("Outhouse2", outhouse(), 150, 120, True, "Orange", "Small"))
    m.yard_rooms.append(("Corn maze", "Dirt", (66, -40, 162, 32), [], []))
    m.yard_rooms.append(("Pumpkin patch", "Dirt", (-165, 40, -45, 150),
                         ["Pumpkin"] * 30 + ["JackOLantern"] * 10 + ["Scarecrow"] * 3, []))
    m.yard_rooms.append(("Hay field", "Dirt", (-20, 70, 60, 150),
                         ["HayBale"] * 14 + ["Scarecrow"] * 2 + ["Pumpkin"] * 6, []))
    m.paths = [rect(-170, -64, 170, -54), rect(-118, -106, -111, -64), rect(-20, -90, -12, -64), rect(22, -90, 30, -64)]
    m.pools = [rect(80, 80, 130, 115)]
    m.bushes = [(-172, -160, 4, "Green"), (174, -125, 5, "Orange"), (-30, 160, 4, "Green"), (172, 60, 4, "Orange"),
                (-172, 10, 5, "Green"), (100, 158, 4, "Green")]
    m.human = [(-160, -40), (-100, -40), (-40, -40), (40, -40), (-150, 20), (-30, 40), (40, 50), (175, -100),
               (150, 60), (0, 160), (-100, 162), (175, 150)]
    m.zombie = [(165, -162), (-170, 160)]
    m.start = (10, 10)
    m.wizard = [(-170, -100), (60, -165), (-170, 130), (110, 150)]
    return m


def spooky_village():
    m = Map("buildSpookyVillage", "SpookyVillage", "The Spooky Village", "BloodMoon", True, (-180, -180, 180, 180))
    north = [("HouseN1", cottage_house(), -170, -165), ("HouseN2", village_house(), -122, -165),
             ("ShopN3", village_shop(), -80, -165), ("Inn", inn(), -40, -165), ("HouseN5", village_house(), 22, -165),
             ("HouseN6", cottage_house(), 64, -165), ("ShopN7", village_shop(), 112, -165)]
    for i, (hid, plan, ox, oz) in enumerate(north):
        m.houses.append((hid, plan, ox, oz, False, "Blue" if i % 2 else "Orange", "Small"))
    south = [("HouseS1", village_house(), -170, 135), ("HouseS2", cottage_house(), -128, 131),
             ("ShopS3", village_shop(), -80, 139), ("HouseS4", village_house(), -40, 135),
             ("HouseS5", cottage_house(), 2, 131), ("ShopS6", village_shop(), 50, 139)]
    for i, (hid, plan, ox, oz) in enumerate(south):
        m.houses.append((hid, plan, ox, oz, True, "Orange" if i % 2 else "Blue", "Small"))
    m.houses.append(("HouseW1", village_house(), -170, -60, False, "Blue", "Small"))
    m.houses.append(("HouseW2", cottage_house(), -170, 10, False, "Orange", "Small"))
    m.houses.append(("HouseW3", village_house(), -100, -100, False, "Orange", "Small"))
    m.houses.append(("HouseE1", village_house(), 60, -95, False, "Blue", "Small"))
    m.houses.append(("Church", church(), 110, 40, False, "Orange", "Large"))
    tomb = [("Tombstone", x, z, 0) for z in (-25, -8, 9) for x in (122, 140, 158)]
    m.yard_rooms.append(("Graveyard", "Dirt", (110, -40, 176, 26), ["Pumpkin", "JackOLantern", "Coffin"], tomb))
    m.patios = [rect(-45, -45, 45, 45)]
    # Market stalls round the square: a table, pumpkins in front.
    m.yard_pieces += [("Table", -30, -30, 0), ("Pumpkin", -33, -23.5, 0), ("JackOLantern", -27, -23.5, 0),
                      ("Table", 30, -30, 0), ("Pumpkin", 27, -23.5, 0), ("Pumpkin", 33, -23.5, 0),
                      ("Table", -30, 32, 0), ("JackOLantern", -33, 37.5, 0), ("Pumpkin", -27, 37.5, 0),
                      ("Table", 30, 32, 0), ("HayBale", 30, 38.5, 0), ("Cauldron", 0, -20, 0)]
    m.yard_scatter = ["Pumpkin"] * 10 + ["JackOLantern"] * 6 + ["HayBale"] * 4 + ["Barrel"] * 4 + ["Crate"] * 3
    m.bushes = [(-60, -70, 3, "Orange"), (95, -40, 3, "Green"), (-90, 95, 3, "Green"), (95, 100, 3, "Orange"),
                (-176, 100, 3, "Green"), (176, -100, 3, "Orange")]
    m.human = [(-60, -60), (60, -60), (-60, 60), (60, 60), (-120, -30), (-120, 60), (100, -120), (-150, -100),
               (0, 100), (0, -100), (160, 130), (-100, 110)]
    m.zombie = [(-176, 110), (170, 160)]
    m.start = (0, 10)
    m.wizard = [(-60, 0), (150, -60), (-110, 170), (100, 170)]
    return m


def witch_woods(rng):
    m = Map("buildWitchWoods", "WitchWoods", "Witch Woods", "Swamp", True, (-190, -190, 190, 190))
    m.houses.append(("WitchHut", witch_hut(), -20, -20, False, "Orange", "Large"))
    m.houses.append(("Mill", mill(), 70, 40, False, "Blue", "Large"))
    m.houses.append(("CabinA", cabin(), -160, -160, False, "Orange", "Small"))
    m.houses.append(("CabinB", cabin(), 120, -160, False, "Blue", "Small"))
    m.houses.append(("CabinC", cabin(), -160, 130, True, "Blue", "Small"))
    m.houses.append(("CabinD", cabin(), 130, 140, True, "Orange", "Small"))
    m.houses.append(("Outhouse1", outhouse(), -90, -178, False, "Orange", "Small"))
    m.houses.append(("Outhouse2", outhouse(), 165, 0, False, "Orange", "Small"))
    m.houses.append(("Outhouse3", outhouse(), -178, 30, False, "Orange", "Small"))
    stones = []
    for k in range(10):
        a = k / 10 * math.tau
        stones.append(("Tombstone", round(-100 + math.cos(a) * 20, 1), round(-30 + math.sin(a) * 20, 1), 0))
    m.yard_rooms.append(("Stone circle", "Dirt", (-130, -60, -70, 0), ["Cauldron", "JackOLantern"], stones))
    m.yard_rooms.append(("Pumpkin clearing", "Dirt", (20, 105, 100, 170),
                         ["Pumpkin"] * 18 + ["JackOLantern"] * 6 + ["Scarecrow"] * 2 + ["HayBale"] * 3, []))
    m.pools = [rect(-70, 60, -20, 92), rect(-95, 92, -50, 120), rect(120, -70, 170, -30)]
    m.paths = [rect(-3, 12, 4, 60), rect(-150, -138, -143, -100), rect(127, -138, 134, -100)]
    m.human = [(-120, -110), (-40, -120), (40, -120), (120, -100), (-170, -60), (170, 60), (-100, 40), (0, 80),
               (60, -40), (-30, 160), (160, 100), (-140, 170)]
    m.zombie = [(-180, 180), (180, -180)]
    m.start = (0, 45)
    m.wizard = [(-60, -60), (100, -110), (-120, 80), (140, 30)]
    scatter_trees(m, rng, 55, 4, 7)
    return m


def place_yards(m, rng):
    houses = [m.house_rect(h) for h in m.houses]
    reserved = [around(x, z, 4) for x, z in m.human + m.zombie + m.wizard + [m.start]]
    reserved += [around(m.start[0], m.start[1], 12)]
    reserved += [around(x, z, r + 2) for x, z, r, _ in m.bushes]
    blocked = [(h[0] - 6, h[1] - 6, h[2] + 6, h[3] + 6) for h in houses]
    blocked += m.pools + m.road["asphalt"] + m.road["sidewalks"]
    placed = [Plan._rect(*p) for p in m.yard_pieces]
    out_rooms = []
    for name, floor, r, contents, fixed in m.yard_rooms:
        placed += [Plan._rect(*p) for p in fixed]
        if not contents and not fixed:
            out_rooms.append((name, floor, r, []))  # just a floor (a corn maze's dirt)
            continue
        area = (r[0] + 3, r[1] + 3, r[2] - 3, r[3] - 3)
        cx, cz = (area[0] + area[2]) / 2, (area[1] + area[3]) / 2
        # Near the middle, well clear of fixed pieces (tombstones).
        spot = min(
            ((cx + dx, cz + dz) for dx in range(-12, 13) for dz in range(-12, 13)
             if not any(overlap(around(cx + dx, cz + dz, LANE + 1), p) for p in placed)),
            key=lambda s: (s[0] - cx) ** 2 + (s[1] - cz) ** 2,
        )
        m.items.append(spot)
        # Clear lanes across the yard through its middle, for the biggest players.
        cross = [(r[0], spot[1] - LANE, r[2], spot[1] + LANE), (spot[0] - LANE, r[1], spot[0] + LANE, r[3])]
        zones = reserved + [around(*spot, 3)] + m.paths + cross
        pieces = list(fixed) + fit(rng, area, contents, placed, [], zones, YARD_GAP, against=False)
        out_rooms.append((name, floor, r, pieces))
    scattered = []
    if m.yard_scatter:
        b = m.bounds
        area = (b[0] + 6, b[1] + 6, b[2] - 6, b[3] - 6)
        rooms = [r for _, _, r, _, _ in m.yard_rooms]
        for kind in m.yard_scatter:
            for _ in range(400):
                w, d = size(kind)
                x = rng.uniform(area[0] + w / 2, area[2] - w / 2)
                z = rng.uniform(area[1] + d / 2, area[3] - d / 2)
                pr = (x - w / 2, z - d / 2, x + w / 2, z + d / 2)
                if any(overlap(pr, o) for o in blocked + reserved + rooms + m.paths + m.patios):
                    continue
                if any(overlap(pr, o, YARD_GAP) for o in placed):
                    continue
                placed.append(pr)
                scattered.append((kind, round(x, 1), round(z, 1), 0))
                break
    return out_rooms, scattered


# --- Luau output ---------------------------------------------------------------------------

def fmt(v):
    return ("%g" % round(v, 2))


def ranges(rs):
    return "{ " + ", ".join("{ %s, %s }" % (fmt(a), fmt(b)) for a, b in rs) + " }"


def emit_plan(lines, plan, furniture):
    lines.append("local %s: Plan = {" % plan.name)
    lines.append("\tw = %s," % fmt(plan.w))
    lines.append("\td = %s," % fmt(plan.d))
    lines.append("\twalls = {")
    for x1, z1, x2, z2, gaps, windows, secrets in plan.walls:
        args = [fmt(x1), fmt(z1), fmt(x2), fmt(z2)]
        tail = [ranges(gaps) if gaps else "nil", ranges(windows) if windows else "nil", ranges(secrets) if secrets else "nil"]
        while tail and tail[-1] == "nil":
            tail.pop()
        lines.append("\t\twall(%s)," % ", ".join(args + tail))
    lines.append("\t},")
    lines.append("\trooms = {")
    for name, floor, r, _ in plan.rooms:
        lines.append('\t\troom("%s", "%s", %s, %s, %s, %s),' % (name, floor, fmt(r[0]), fmt(r[1]), fmt(r[2]), fmt(r[3])))
    lines.append("\t},")
    lines.append("\tfurniture = {")
    for kind, x, z, rot in furniture:
        lines.append('\t\tpiece("%s", %s, %s%s),' % (kind, fmt(x), fmt(z), ", %d" % rot if rot else ""))
    lines.append("\t},")
    lines.append("\titems = { %s }," % ", ".join("pt(%s, %s)" % (fmt(x), fmt(z)) for x, z in plan.items))
    lines.append("}")
    lines.append("")


def emit_map(lines, m, rng, emitted):
    for h in m.houses:
        plan = h[1]
        if plan.name not in emitted:
            emitted[plan.name] = plan.furnish(rng)
            emit_plan(lines, plan, emitted[plan.name])
    yard_rooms, scattered = place_yards(m, rng)
    b = m.bounds
    lines.append("local function %s(): Layout" % m.fn)
    lines.append('\tlocal layout = newLayout("%s", "%s")' % (m.name, m.title))
    lines.append('\tlayout.theme = "%s"' % m.theme)
    if m.roofs:
        lines.append("\tlayout.roofs = true")
    lines.append("\tlayout.bounds = rect(%s, %s, %s, %s)" % tuple(fmt(v) for v in b))
    for h in m.houses:
        hid, plan, ox, oz, rotated, outline, sz = h[:7]
        wall = ', "%s"' % h[7] if len(h) > 7 else ""
        lines.append('\taddHouse(layout, "%s", %s, %s, %s, %s, "%s", "%s"%s)' % (hid, plan.name, fmt(ox), fmt(oz), "true" if rotated else "false", outline, sz, wall))
    # Cobwebs inside houses (plan coords -> world).
    webs = []
    for h in m.houses:
        for x, z, r in h[1].cobwebs:
            wx, wz = m.to_world(h, x, z)
            webs.append((wx, wz, r))
    lines.append("\t-- Yards: wall-less rooms (graveyard, pumpkin patch) and outdoor pieces.")
    lines.append("\tlocal function yardRoom(name: string, floor: string, x1: number, z1: number, x2: number, z2: number)")
    lines.append('\t\ttable.insert(layout.rooms, { name = name, floor = floor, rect = rect(x1, z1, x2, z2), house = "" })')
    lines.append("\tend")
    lines.append("\tlocal function outdoor(kind: string, x: number, z: number, rot: number?)")
    lines.append('\t\ttable.insert(layout.furniture, { kind = kind, x = x, z = z, rot = rot or 0, house = "" })')
    lines.append("\tend")
    for name, floor, r, pieces in yard_rooms:
        lines.append('\tyardRoom("%s", "%s", %s, %s, %s, %s)' % (name, floor, fmt(r[0]), fmt(r[1]), fmt(r[2]), fmt(r[3])))
        for kind, x, z, rot in pieces:
            lines.append('\toutdoor("%s", %s, %s%s)' % (kind, fmt(x), fmt(z), ", %d" % rot if rot else ""))
    for kind, x, z, rot in m.yard_pieces + scattered:
        lines.append('\toutdoor("%s", %s, %s%s)' % (kind, fmt(x), fmt(z), ", %d" % rot if rot else ""))
    for key in ("paths", "patios", "pools"):
        if getattr(m, key):
            lines.append("\tlayout.%s = { %s }" % (key, ", ".join("rect(%s, %s, %s, %s)" % tuple(fmt(v) for v in r) for r in getattr(m, key))))
    if any(m.road.values()):
        lines.append("\tlayout.road = {")
        for key in ("sidewalks", "asphalt", "centerLines", "edgeLines"):
            lines.append("\t\t%s = { %s }," % (key, ", ".join("rect(%s, %s, %s, %s)" % tuple(fmt(v) for v in r) for r in m.road[key])))
        lines.append("\t}")
    lines.append("\tlayout.bushes = {")
    for x, z, r, color in m.bushes:
        lines.append('\t\tbush(%s, %s, %s, "%s"),' % (fmt(x), fmt(z), fmt(r), color))
    for x, z, r in webs:
        lines.append('\t\tbush(%s, %s, %s, "Cobweb"),' % (fmt(x), fmt(z), fmt(r)))
    lines.append("\t}")
    lines.append("\tlayout.humanSpawns = { %s }" % ", ".join("pt(%s, %s)" % (fmt(x), fmt(z)) for x, z in m.human))
    lines.append("\tlayout.zombieSpawns = { %s }" % ", ".join("pt(%s, %s)" % (fmt(x), fmt(z)) for x, z in m.zombie))
    lines.append("\tlayout.start = pt(%s, %s)" % (fmt(m.start[0]), fmt(m.start[1])))
    lines.append("\tlayout.wizardSpots = { %s }" % ", ".join("pt(%s, %s)" % (fmt(x), fmt(z)) for x, z in m.wizard))
    if m.items:
        lines.append("\tfor _, p in { %s } do" % ", ".join("pt(%s, %s)" % (fmt(x), fmt(z)) for x, z in m.items))
        lines.append("\t\ttable.insert(layout.itemSpots, p)")
        lines.append("\tend")
    lines.append("\treturn layout")
    lines.append("end")
    lines.append("")
    exterior = {}
    for hid, plan, *_ in m.houses:
        count = 0
        for x1, z1, x2, z2, gaps, _w, _s in plan.walls:
            on_edge = (z1 == z2 and z1 in (0, plan.d)) or (x1 == x2 and x1 in (0, plan.w))
            if on_edge:
                count += len(gaps)
        exterior[hid] = count
    print("%s exterior doors: %s" % (m.name, ", ".join("%s = %d" % kv for kv in exterior.items())))


def main():
    rng = random.Random(1031)
    lines = [BEGIN, "-- Made by tools/map_plans.py: edit that file and rerun it, don't edit here.", ""]
    emitted = {}
    maps = [christmas(), haunted()]
    maps += [pumpkin_farm(random.Random(77)), spooky_village(), witch_woods(random.Random(5))]
    for m in maps:
        lines.append("-- %s %s" % (m.title, "-" * max(4, 88 - len(m.title))))
        lines.append("")
        emit_map(lines, m, rng, emitted)
    lines.append(END)
    block = "\n".join(lines)
    text = LAYOUT.read_text()
    if BEGIN in text:
        text = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END), lambda _: block, text, flags=re.S)
    else:
        start = text.index("-- Christmas Town ---")
        stop = text.index("MapLayout.maps = {")
        text = text[:start] + block + "\n\n" + text[stop:]
    LAYOUT.write_text(text)
    for name, furniture in emitted.items():
        print("%s: %d pieces" % (name, len(furniture)))


if __name__ == "__main__":
    main()
