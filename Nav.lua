-- Travel cost on foot between two points on a continent: the terrain grid (open, water,
-- too steep), drawn walls and the road network, from AzerothGPS's data (Data/*.lua, built by
-- tools/build_nav_data.py with its author's permission). Not a route planner: it only says
-- how far a walk is, so the nearest vendor can be picked by the walk instead of the bird.
-- World coordinates are yards, x north, y west (UnitPosition's order).
local _, VP = ...
local Nav = {}
VP.Nav = Nav

local TILE = 1600 / 3
local SWIM = 1.5          -- swimming is about 2/3 of run speed
local END_SLACK = 40      -- blocked ground this close to either end is ignored: vendors stand in
                          -- buildings and on ledges, and the player is evidently standing there
local SNAP_RANGE = 600    -- road junctions this close (as the bird flies) are tried to get on or off
local SNAP_TRIES = 6      -- ... the nearest this many of them

---------------------------------------------------------------------------
-- Terrain grid (run-length rows, decoded the first time a row is read)
---------------------------------------------------------------------------
local ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"
local INDEX = {}
for i = 1, #ALPHABET do INDEX[ALPHABET:byte(i)] = i - 1 end
local SHORT = 21

local function DecodeRow(text)
  local runs, pos, i, n = {}, 0, 1, #text
  while i <= n do
    local b = text:byte(i)
    local v, len
    if b == 95 then -- "_": a long run, value then three length digits
      v = text:byte(i + 1) - 48
      len = INDEX[text:byte(i + 2)] * 4096 + INDEX[text:byte(i + 3)] * 64 + INDEX[text:byte(i + 4)]
      i = i + 5
    else
      local k = INDEX[b]
      v = math.floor(k / SHORT)
      len = k % SHORT + 1
      i = i + 1
    end
    pos = pos + len
    runs[#runs + 1] = pos
    runs[#runs + 1] = v
  end
  return runs
end

local rowCache = {}  -- [grid][row] = runs
local openCache = {} -- [cont] = { [row * 65536 + col] = true }

local function Opens(cont)
  local set = openCache[cont]
  if not set then
    set = {}
    for _, key in ipairs(VP.Opens and VP.Opens[cont] or {}) do set[key] = true end
    openCache[cont] = set
  end
  return set
end

-- 0 open, 1 water, 2 blocked (and off the grid).
local function Cell(g, opens, row, col)
  if row < 1 or row > g.h or col < 1 or col > g.w then return 2 end
  if opens[row * 65536 + col] then return 0 end
  local rc = rowCache[g]
  if not rc then rc = {}; rowCache[g] = rc end
  local runs = rc[row]
  if not runs then
    runs = DecodeRow(g.rows[row])
    rc[row] = runs
  end
  local lo, hi = 1, #runs / 2
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if runs[mid * 2 - 1] < col then lo = mid + 1 else hi = mid end
  end
  return runs[lo * 2]
end

---------------------------------------------------------------------------
-- Walls (point lists): a leg crossing one is blocked
---------------------------------------------------------------------------
local wallBoxes = {} -- [cont] = { { pts, minX, minY, maxX, maxY }, ... }

local function Walls(cont)
  local list = wallBoxes[cont]
  if list then return list end
  list = {}
  for _, pts in ipairs(VP.Walls and VP.Walls[cont] or {}) do
    local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
    for i = 1, #pts - 1, 2 do
      x1, x2 = math.min(x1, pts[i]), math.max(x2, pts[i])
      y1, y2 = math.min(y1, pts[i + 1]), math.max(y2, pts[i + 1])
    end
    list[#list + 1] = { pts, x1, y1, x2, y2 }
  end
  wallBoxes[cont] = list
  return list
end

local function Orient(ax, ay, bx, by, cx, cy)
  return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
end

local function CrossesWall(cont, x1, y1, x2, y2)
  local lx1, lx2 = math.min(x1, x2), math.max(x1, x2)
  local ly1, ly2 = math.min(y1, y2), math.max(y1, y2)
  for _, w in ipairs(Walls(cont)) do
    if w[4] >= lx1 and w[2] <= lx2 and w[5] >= ly1 and w[3] <= ly2 then
      local pts = w[1]
      for i = 1, #pts - 3, 2 do
        local ax, ay, bx, by = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
        local d1, d2 = Orient(x1, y1, x2, y2, ax, ay), Orient(x1, y1, x2, y2, bx, by)
        local d3, d4 = Orient(ax, ay, bx, by, x1, y1), Orient(ax, ay, bx, by, x2, y2)
        if ((d1 > 0) ~= (d2 > 0)) and ((d3 > 0) ~= (d4 > 0)) then return true end
      end
    end
  end
  return false
end

---------------------------------------------------------------------------
-- A straight walk
---------------------------------------------------------------------------
-- Yards of walking straight from (x1, y1) to (x2, y2), water counted slower, or nil when the
-- line crosses steep ground or a wall. Without terrain data for the continent: the distance.
function Nav.Segment(cont, x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  local g = VP.Terrain and VP.Terrain[cont]
  if not g then return len end
  if CrossesWall(cont, x1, y1, x2, y2) then return nil end
  local k = TILE / g.cell
  local n = math.max(1, math.ceil(len / (g.cell / 3)))
  local slack = len > 0 and END_SLACK / len or 1
  local opens = Opens(cont)
  local water, lastRow, lastCol, lastV = 0, nil, nil, nil
  for i = 0, n do
    local t = i / n
    local x, y = x1 + dx * t, y1 + dy * t
    local col = math.floor(((32 - y / TILE) - g.tx0) * k) + 1
    local row = math.floor(((32 - x / TILE) - g.ty0) * k) + 1
    local v
    if row == lastRow and col == lastCol then
      v = lastV
    else
      v = Cell(g, opens, row, col)
      lastRow, lastCol, lastV = row, col, v
    end
    if v == 2 and t > slack and t < 1 - slack then return nil end
    if v == 1 then water = water + 1 end
  end
  return len + len * (water / (n + 1)) * (SWIM - 1)
end

---------------------------------------------------------------------------
-- Roads
---------------------------------------------------------------------------
local graphs = {} -- [cont] = { xs, ys, adj = { [i] = { j, len, j, len, ... } } }

local function Graph(cont)
  local g = graphs[cont]
  if g ~= nil then return g or nil end
  local r = VP.Roads and VP.Roads[cont]
  if not r then graphs[cont] = false; return nil end
  local xs, ys, adj = {}, {}, {}
  for i = 1, #r.n - 1, 2 do
    xs[#xs + 1], ys[#ys + 1] = r.n[i], r.n[i + 1]
    adj[#xs] = {}
  end
  local e = r.e
  for i = 1, #e - 2, 3 do
    local a, b, len = e[i], e[i + 1], e[i + 2]
    if adj[a] and adj[b] and a ~= b then
      local la, lb = adj[a], adj[b]
      la[#la + 1], la[#la + 2] = b, len
      lb[#lb + 1], lb[#lb + 2] = a, len
    end
  end
  g = { xs = xs, ys = ys, adj = adj }
  graphs[cont] = g
  return g
end

-- Junctions you can walk to straight from (x, y): { node, yards }, nearest first.
local function Snap(g, cont, x, y)
  local near = {}
  for i = 1, #g.xs do
    local d = math.sqrt((g.xs[i] - x) ^ 2 + (g.ys[i] - y) ^ 2)
    if d <= SNAP_RANGE then near[#near + 1] = { i, d } end
  end
  table.sort(near, function(a, b) return a[2] < b[2] end)
  local out = {}
  for i = 1, math.min(SNAP_TRIES, #near) do
    local node = near[i][1]
    local walk = Nav.Segment(cont, x, y, g.xs[node], g.ys[node])
    if walk then out[#out + 1] = { node, walk } end
  end
  return out
end

-- Yards along the roads from (x, y) to every junction (Dijkstra; a few hundred to 1,500 of them).
local function RoadDistances(g, cont, x, y)
  local dist, done = {}, {}
  local heap = {}
  local function push(node, d)
    heap[#heap + 1] = { node, d }
    local i = #heap
    while i > 1 do
      local p = math.floor(i / 2)
      if heap[p][2] <= heap[i][2] then break end
      heap[p], heap[i] = heap[i], heap[p]
      i = p
    end
  end
  local function pop()
    local top = heap[1]
    local last = table.remove(heap)
    if #heap > 0 then
      heap[1] = last
      local i = 1
      while true do
        local l, r, s = i * 2, i * 2 + 1, i
        if heap[l] and heap[l][2] < heap[s][2] then s = l end
        if heap[r] and heap[r][2] < heap[s][2] then s = r end
        if s == i then break end
        heap[s], heap[i] = heap[i], heap[s]
        i = s
      end
    end
    return top
  end
  for _, s in ipairs(Snap(g, cont, x, y)) do
    if not dist[s[1]] or s[2] < dist[s[1]] then
      dist[s[1]] = s[2]
      push(s[1], s[2])
    end
  end
  while #heap > 0 do
    local top = pop()
    local node, d = top[1], top[2]
    if not done[node] then
      done[node] = true
      local a = g.adj[node]
      for i = 1, #a - 1, 2 do
        local nb, nd = a[i], d + a[i + 1]
        if not dist[nb] or nd < dist[nb] then
          dist[nb] = nd
          push(nb, nd)
        end
      end
    end
  end
  return dist
end

---------------------------------------------------------------------------
-- From the player to many places
---------------------------------------------------------------------------
-- A context for costing several walks from one start: Walk(x, y) gives yards and "direct" or
-- "road", or nil when neither a straight walk nor the roads reach it.
function Nav.From(cont, sx, sy)
  local g = Graph(cont)
  local roadDist -- computed the first time a direct walk fails or a road might be shorter
  local ctx = {}
  function ctx.Walk(x, y)
    local direct = Nav.Segment(cont, sx, sy, x, y)
    if not g then return direct, direct and "direct" or nil end
    local bird = math.sqrt((x - sx) ^ 2 + (y - sy) ^ 2)
    -- A clear straight line is the shortest there is: no road beats it.
    if direct and direct <= bird * 1.05 then return direct, "direct" end
    roadDist = roadDist or RoadDistances(g, cont, sx, sy)
    local best, how = direct, direct and "direct" or nil
    for _, s in ipairs(Snap(g, cont, x, y)) do
      local d = roadDist[s[1]]
      if d and (not best or d + s[2] < best) then best, how = d + s[2], "road" end
    end
    return best, how
  end
  return ctx
end

-- Has terrain data for this continent (else every walk is the bird's distance).
function Nav.Knows(cont)
  return VP.Terrain and VP.Terrain[cont] ~= nil
end
