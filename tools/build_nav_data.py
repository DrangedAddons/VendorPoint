"""Build VendorPoint's travel data (Data/Terrain.lua, Data/Roads.lua) from AzerothGPS's data
(used with its author's permission), without AzerothGPS having to be installed.

Usage:
  python -I tools/build_nav_data.py                 latest AzerothGPS release from CurseForge
  python -I tools/build_nav_data.py --from <dir>    an AzerothGPS folder on disk instead
  add --force to rebuild when the source version hasn't changed

Prints "unchanged" and writes nothing when Data/ was already built from that version.

Output (all in VendorPoint's private namespace, world yards, x north, y west):
  VP.Terrain[cont] = { tx0, ty0, cell, w, h, rows = { run-length rows } }   (copied as is)
  VP.Roads[cont]   = { n = { x1, y1, ... }, e = { a1, b1, len1, ... } }     (junctions and road lengths,
                       plus "links": straight walks between nearby junctions the terrain allows,
                       so separate road pieces join up the way AzerothGPS's off-road router joins them)
  VP.Walls[cont]   = { { x1, y1, x2, y2, ... }, ... }                       (drawn walls)
  VP.Opens[cont]   = { row * 65536 + col, ... }                              (cells wall erasers open)
"""
import io
import json
import math
import os
import re
import sys
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CURSEFORGE_PROJECT = 1712208  # AzerothGPS
CF_FILES = "https://www.curseforge.com/api/v1/mods/%d/files?pageIndex=0&pageSize=20&sort=dateCreated&sortDescending=true"
CF_DOWNLOAD = "https://www.curseforge.com/api/v1/mods/%d/files/%d/download"
FOREVER_VERSION = "1.60."   # game versions starting with this are WoW Forever's
NEEDED = ("AzerothGPS.toc", "Data/Terrain.lua", "Data/Roads.lua")

TILE = 1600 / 3
OPEN_YD = 6          # a wall eraser stroke opens blocked ground this close to it (AzerothGPS's value)
END_SLACK = 40       # same as Nav.lua: blocked cells this close to either end are ignored
SWIM = 1.5
LINK_YD = 400        # junctions this close get a straight-walk link when the terrain allows
LINK_TRIES = 8       # ... trying the nearest this many


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "VendorPoint-data-builder"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def from_curseforge():
    files = json.loads(get(CF_FILES % CURSEFORGE_PROJECT))["data"]
    files = [f for f in files if f.get("releaseType") == 1
             and any(v.startswith(FOREVER_VERSION) for v in f.get("gameVersions", []))]
    if not files:
        sys.exit("no Forever release of AzerothGPS found on CurseForge")
    f = files[0]
    print("CurseForge:", f["displayName"], f["fileName"], f["dateCreated"])
    data = get(CF_DOWNLOAD % (CURSEFORGE_PROJECT, f["id"]))
    texts = {}
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for name in NEEDED:
            texts[name] = z.read("AzerothGPS/" + name).decode("utf-8")
    return texts


def from_dir(path):
    texts = {}
    for name in NEEDED:
        with open(os.path.join(path, name), encoding="utf-8") as f:
            texts[name] = f.read()
    return texts


def block(text, start):
    """The balanced { ... } that opens at text[start] (no braces inside strings in these files)."""
    depth = 0
    for i in range(start, len(text)):
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
    raise ValueError("unbalanced")


def table_after(text, marker):
    return block(text, text.index(marker) + len(marker))


def top_entries(table_text):
    """[cont] = { ... } entries of a table literal, as (cont, body)."""
    out, i = [], 1
    pat = re.compile(r"\[(\d+)\]\s*=\s*\{")
    while True:
        m = pat.search(table_text, i)
        if not m:
            return out
        body = block(table_text, m.end() - 1)
        out.append((int(m.group(1)), body))
        i = m.end() - 1 + len(body)


def numbers(text):
    return [float(x) for x in re.findall(r"-?\d+(?:\.\d+)?(?:e-?\d+)?", text)]


def fmt(v):
    s = ("%.1f" % v).rstrip("0").rstrip(".")
    return s if s not in ("-0", "") else "0"


# --- terrain, the same reading as Nav.lua -------------------------------------------------------
ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"
INDEX = {c: i for i, c in enumerate(ALPHABET)}
SHORT = 21


def decode_row(text):
    runs, pos, i = [], 0, 0
    while i < len(text):
        if text[i] == "_":
            v = ord(text[i + 1]) - 48
            n = INDEX[text[i + 2]] * 4096 + INDEX[text[i + 3]] * 64 + INDEX[text[i + 4]]
            i += 5
        else:
            k = INDEX[text[i]]
            v, n = k // SHORT, k % SHORT + 1
            i += 1
        pos += n
        runs.append((pos, v))
    return runs


class Grid:
    def __init__(self, body, opens, walls):
        head = body[: body.index("rows")]
        g = {k: float(v) for k, v in re.findall(r"(\w+)\s*=\s*(-?[\d.]+)", head)}
        self.tx0, self.ty0, self.cell = g["tx0"], g["ty0"], g["cell"]
        self.w, self.h = int(g["w"]), int(g["h"])
        self.rows = re.findall(r'"([^"]*)"', body[body.index("rows"):])
        self.decoded = {}
        self.opens = opens
        self.walls = walls

    def to_cell(self, x, y):
        k = TILE / self.cell
        return math.floor(((32 - x / TILE) - self.ty0) * k) + 1, math.floor(((32 - y / TILE) - self.tx0) * k) + 1

    def centre(self, row, col):
        k = TILE / self.cell
        return (32 - self.ty0 - (row - 0.5) / k) * TILE, (32 - self.tx0 - (col - 0.5) / k) * TILE

    def at(self, row, col):
        if row < 1 or row > self.h or col < 1 or col > self.w:
            return 2
        if row * 65536 + col in self.opens:
            return 0
        runs = self.decoded.get(row)
        if runs is None:
            runs = self.decoded[row] = decode_row(self.rows[row - 1])
        lo, hi = 0, len(runs) - 1
        while lo < hi:
            mid = (lo + hi) // 2
            if runs[mid][0] < col:
                lo = mid + 1
            else:
                hi = mid
        return runs[lo][1]

    def crosses_wall(self, x1, y1, x2, y2):
        def orient(ax, ay, bx, by, cx, cy):
            return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
        for pts in self.walls:
            for i in range(0, len(pts) - 3, 2):
                ax, ay, bx, by = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
                if ((orient(x1, y1, x2, y2, ax, ay) > 0) != (orient(x1, y1, x2, y2, bx, by) > 0) and
                        (orient(ax, ay, bx, by, x1, y1) > 0) != (orient(ax, ay, bx, by, x2, y2) > 0)):
                    return True
        return False

    def segment(self, x1, y1, x2, y2):
        dx, dy = x2 - x1, y2 - y1
        length = math.hypot(dx, dy)
        if self.crosses_wall(x1, y1, x2, y2):
            return None
        n = max(1, math.ceil(length / (self.cell / 3)))
        slack = END_SLACK / length if length > 0 else 1
        water, last = 0, None
        for i in range(n + 1):
            t = i / n
            rc = self.to_cell(x1 + dx * t, y1 + dy * t)
            if rc != last:
                v, last = self.at(*rc), rc
            if v == 2 and slack < t < 1 - slack:
                return None
            if v == 1:
                water += 1
        return length + length * (water / (n + 1)) * (SWIM - 1)


def inside(poly, x, y):
    c, j = False, len(poly) - 1
    for i in range(len(poly)):
        (xi, yi), (xj, yj) = poly[i], poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            c = not c
        j = i
    return c


def near(line, x, y, r):
    for (ax, ay), (bx, by) in zip(line, line[1:]):
        dx, dy = bx - ax, by - ay
        length2 = dx * dx + dy * dy
        t = 0 if length2 == 0 else max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / length2))
        if (ax + dx * t - x) ** 2 + (ay + dy * t - y) ** 2 <= r * r:
            return True
    return False


def build(texts):
    m = re.search(r"^## Version:\s*(\S+)", texts["AzerothGPS.toc"], re.M)
    ver = m.group(1) if m else "?"
    stamp = "-- GENERATED by tools/build_nav_data.py from AzerothGPS %s (with its author's permission).\n" % ver
    roads_path = os.path.join(ROOT, "Data", "Roads.lua")
    if "--force" not in sys.argv and os.path.exists(roads_path):
        with open(roads_path, encoding="utf-8") as f:
            if f.readline() == stamp:
                print("unchanged: Data/ is already built from AzerothGPS", ver)
                return
    header = stamp + ("-- AzerothGPS data (c) 2026 AzerothGPS, all rights reserved. Do not edit by hand.\n"
                      "local _, VP = ...\n")

    terrain_text, roads_text = texts["Data/Terrain.lua"], texts["Data/Roads.lua"]
    t_table = table_after(terrain_text, "ns.Terrain = ")
    r_table = table_after(roads_text, "ns.Roads = ")
    w_table = table_after(roads_text, "ns.Walls = ")
    o_table = table_after(roads_text, "ns.WallOpens = ")

    # walls
    walls = {}
    for cont, body in top_entries(w_table):
        walls[cont] = []
        for wm in re.finditer(r"\{([^{}]*)\}", body[1:-1]):
            pts = numbers(re.sub(r"\b[a-z]+\s*=\s*-?[\d.]+", "", wm.group(1)))  # drop z = ... fields
            if len(pts) >= 4:
                walls[cont].append(pts[: len(pts) // 2 * 2])

    # grids, with the wall erasers' cells opened
    grids = {}
    for cont, body in top_entries(t_table):
        grids[cont] = Grid(body, set(), walls.get(cont, []))
    opens = {}
    for cont, body in top_entries(o_table):
        g = grids.get(cont)
        if not g:
            continue
        cells = set()
        for om in re.finditer(r"\{\s*area\s*=\s*(true|false)\s*,\s*pts\s*=\s*\{([^{}]*)\}\s*\}", body):
            v = numbers(om.group(2))
            pts = list(zip(v[0::2], v[1::2]))
            area = om.group(1) == "true"
            pad = 0 if area else OPEN_YD
            xs, ys = [p[0] for p in pts], [p[1] for p in pts]
            r1, c1 = g.to_cell(max(xs) + pad, max(ys) + pad)
            r2, c2 = g.to_cell(min(xs) - pad, min(ys) - pad)
            for row in range(min(r1, r2), max(r1, r2) + 1):
                for col in range(min(c1, c2), max(c1, c2) + 1):
                    x, y = g.centre(row, col)
                    if (area and inside(pts, x, y)) or near(pts, x, y, OPEN_YD):
                        cells.add(row * 65536 + col)
        opens[cont] = cells
        g.opens = cells
        print("opens", cont, len(cells), "cells")

    # roads, linked
    out = [header, "VP.Roads = {\n"]
    for cont, body in top_entries(r_table):
        nodes = numbers(block(body, body.index("n = {") + 4))
        xs, ys = nodes[0::2], nodes[1::2]
        edges, adjacent = [], set()
        for em in re.finditer(r"\{([^{}]*)\}", block(body, body.index("e = {") + 4)[1:-1]):
            v = numbers(em.group(1))
            a, b = int(v[0]), int(v[1])
            edges.append((a, b, v[2]))
            adjacent.add((min(a, b), max(a, b)))
        links = 0
        g = grids.get(cont)
        if g:
            buckets = {}
            for i in range(len(xs)):
                buckets.setdefault((int(xs[i] // LINK_YD), int(ys[i] // LINK_YD)), []).append(i)
            for i in range(len(xs)):
                bx, by = int(xs[i] // LINK_YD), int(ys[i] // LINK_YD)
                cands = []
                for ox in (-1, 0, 1):
                    for oy in (-1, 0, 1):
                        for j in buckets.get((bx + ox, by + oy), ()):
                            if j != i:
                                d = math.hypot(xs[j] - xs[i], ys[j] - ys[i])
                                if d <= LINK_YD:
                                    cands.append((d, j))
                cands.sort()
                for d, j in cands[:LINK_TRIES]:
                    key = (min(i, j) + 1, max(i, j) + 1)
                    if key in adjacent:
                        continue
                    cost = g.segment(xs[i], ys[i], xs[j], ys[j])
                    if cost is not None:
                        adjacent.add(key)
                        edges.append((key[0], key[1], cost))
                        links += 1
        out.append("  [%d] = {\n    n = {%s},\n    e = {%s},\n  },\n" % (
            cont, ",".join(fmt(x) for x in nodes),
            ",".join("%d,%d,%s" % (a, b, fmt(c)) for a, b, c in edges)))
        print("roads", cont, len(xs), "junctions,", len(edges) - links, "roads,", links, "links")
    out.append("}\n\n-- Walls (what can't be walked through, like a mountain's edge the grid has open): point lists.\n")
    out.append("VP.Walls = {\n")
    for cont, lst in walls.items():
        out.append("  [%d] = {%s},\n" % (cont, ",".join("{" + ",".join(fmt(x) for x in p) + "}" for p in lst)))
    out.append("}\n\n-- Ground the wall erasers open (AzerothGPS's own fixes to the grid): cells, row * 65536 + col.\n")
    out.append("VP.Opens = {\n")
    for cont, cells in opens.items():
        out.append("  [%d] = {%s},\n" % (cont, ",".join(str(c) for c in sorted(cells))))
    out.append("}\n")

    os.makedirs(os.path.join(ROOT, "Data"), exist_ok=True)
    with open(os.path.join(ROOT, "Data", "Terrain.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(header)
        f.write("-- Passability per continent: cells of `cell` yards, row = south, col = east, from terrain\n"
                "-- tile (tx0, ty0). 0 open, 1 water, 2 blocked (too steep). Rows are run-length encoded.\n")
        f.write("VP.Terrain = " + t_table + "\n")
    with open(roads_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("".join(out))
    print("built Data/Terrain.lua and Data/Roads.lua from AzerothGPS", ver)


if __name__ == "__main__":
    if "--from" in sys.argv:
        build(from_dir(sys.argv[sys.argv.index("--from") + 1]))
    else:
        build(from_curseforge())
