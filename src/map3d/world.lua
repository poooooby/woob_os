-- The 3D map's world built to scale from the game's own maps: Hoenn; Kanto and the Sevii Islands'
-- three pictures (FireRed / LeafGreen), each a world of its own. Every outdoor map put where it joins
-- its neighbours, each of its tiles read for what it is, and the doors (where each leads), for the
-- buildings. A tile's class comes from its collision, its behaviour and the colours of its own art
-- (the cart's tile pictures, read once per tileset); nothing of the game's is kept beyond the
-- session, nothing here draws.
--
--   Tiles: the game's 16 px squares, x right, y down (z in the world), 0, 0 the top-left of the first
--   map placed (Littleroot, Pallet Town, an island's town). World units: MT tiles each.
--
--   Wd = World(engine, deps)   deps: maps() -> the game's map definitions ; art(pair) -> a tileset's
--                              colours, pixels(pair) -> its pixels (the tests' stand-ins for the
--                              cart's); FireRed / LeafGreen's Town Map: layouts() -> its pictures'
--                              grids, pictureOf(section) -> 0..3
--   Wd.MT, Wd.C (the classes), Wd.REGIONS (hoenn, kanto, sevii123, sevii45, sevii67)
--   Wd.build(opts) -> world    (synchronous; inside a coroutine it yields as it goes: opts.pace(),
--                              true when it should; opts.region the region's id, Hoenn by default)
--     world = { maps = { { id, def, x, y, w, h, sec, how } }, byId, x0, y0, cols, rows,
--               cls[], mid[], pix[] (the tile's tileset index), elev[], mapIx[],
--               doors = { { x, y, map, dest, kind, foot = { x0, y0, x1, y1 } | nil } },
--               pairs = { { name, art } }, art(k, q) -> r, g, b (a quarter of the tile, 0..3),
--               tile(pi, mid, out) -> true, out[1..768] the tile's 16 x 16 pixels (r, g, b) | false }
--   Wd.CLASS_COLOR[c] -> r, g, b (the debug picture's colours)

local floor, max, min, abs, sqrt = math.floor, math.max, math.min, math.abs, math.sqrt

local MT = 16

-- the classes (a number per tile)
local C = {
  VOID = 0, SEA = 1, POND = 2, SHALLOW = 3, FALL = 4, CURRENT = 5,
  GROUND = 10, TALL = 11, LONG = 12, SAND = 13, ASH = 14, SOIL = 15, ROCKY = 16, PUDDLE = 17, MOUNT = 18,
  LEDGE_E = 20, LEDGE_W = 21, LEDGE_N = 22, LEDGE_S = 23,
  DOOR = 30, TREE = 40, BUILDING = 41, ROCK = 42, SMALL = 43, STRUCT = 44,
  BRIDGE = 50, LOG = 51,
}
-- behaviours that name a tile's class outright
local BEH = {
  OCEAN_WATER = C.SEA, DEEP_WATER = C.SEA, SOOTOPOLIS_DEEP_WATER = C.SEA, INTERIOR_DEEP_WATER = C.SEA,
  NO_SURFACING = C.SEA, SEAWEED = C.SEA, POND_WATER = C.POND, HOT_SPRINGS = C.POND, SHALLOW_WATER = C.SHALLOW,
  -- (FireRed / LeafGreen's: the rough sea round the Sevii Islands, the water by the Cycling Road)
  FAST_WATER = C.SEA, CYCLING_ROAD_WATER = C.SEA, SEMI_DEEP_WATER = C.SEA,
  WATERFALL = C.FALL, EASTWARD_CURRENT = C.CURRENT, WESTWARD_CURRENT = C.CURRENT,
  NORTHWARD_CURRENT = C.CURRENT, SOUTHWARD_CURRENT = C.CURRENT,
  TALL_GRASS = C.TALL, LONG_GRASS = C.LONG, LONG_GRASS_SOUTH_EDGE = C.LONG,
  SAND = C.SAND, DEEP_SAND = C.SAND, FOOTPRINTS = C.SAND, ASHGRASS = C.ASH, BERRY_TREE_SOIL = C.SOIL,
  MOUNTAIN_TOP = C.MOUNT, MUDDY_SLOPE = C.ROCKY, BUMPY_SLOPE = C.ROCKY, PUDDLE = C.PUDDLE,
  BRIDGE_OVER_OCEAN = C.BRIDGE, BRIDGE_OVER_POND_LOW = C.BRIDGE, BRIDGE_OVER_POND_MED = C.BRIDGE,
  BRIDGE_OVER_POND_HIGH = C.BRIDGE, BRIDGE_OVER_POND_MED_EDGE_1 = C.BRIDGE, BRIDGE_OVER_POND_MED_EDGE_2 = C.BRIDGE,
  BRIDGE_OVER_POND_HIGH_EDGE_1 = C.BRIDGE, BRIDGE_OVER_POND_HIGH_EDGE_2 = C.BRIDGE, FORTREE_BRIDGE = C.BRIDGE,
  UNUSED_BRIDGE = C.BRIDGE, BIKE_BRIDGE_OVER_BARRIER = C.BRIDGE,
  PACIFIDLOG_VERTICAL_LOG_TOP = C.LOG, PACIFIDLOG_VERTICAL_LOG_BOTTOM = C.LOG,
  PACIFIDLOG_HORIZONTAL_LOG_LEFT = C.LOG, PACIFIDLOG_HORIZONTAL_LOG_RIGHT = C.LOG,
}
-- a bridge's kind (its deck's height): over the sea, over a pond low / higher / highest, Fortree's
-- over the trees, Pacifidlog's logs
local BRIDGE_KIND = {
  BRIDGE_OVER_OCEAN = "ocean", BRIDGE_OVER_POND_LOW = "low", BRIDGE_OVER_POND_MED = "med",
  BRIDGE_OVER_POND_MED_EDGE_1 = "med", BRIDGE_OVER_POND_MED_EDGE_2 = "med", BRIDGE_OVER_POND_HIGH = "high",
  BRIDGE_OVER_POND_HIGH_EDGE_1 = "high", BRIDGE_OVER_POND_HIGH_EDGE_2 = "high", FORTREE_BRIDGE = "tree",
  UNUSED_BRIDGE = "low", BIKE_BRIDGE_OVER_BARRIER = "low",
}
-- the debug picture's colours
local CLASS_COLOR = {
  [C.VOID] = { 20, 40, 90 }, [C.SEA] = { 40, 90, 200 }, [C.POND] = { 80, 160, 240 }, [C.SHALLOW] = { 120, 190, 240 },
  [C.FALL] = { 220, 240, 255 }, [C.CURRENT] = { 60, 120, 220 },
  [C.GROUND] = { 150, 200, 120 }, [C.TALL] = { 60, 150, 60 }, [C.LONG] = { 40, 120, 40 }, [C.SAND] = { 230, 210, 140 },
  [C.ASH] = { 160, 160, 150 }, [C.SOIL] = { 140, 90, 50 }, [C.ROCKY] = { 190, 150, 110 }, [C.PUDDLE] = { 140, 180, 200 },
  [C.MOUNT] = { 205, 170, 130 },
  [C.LEDGE_E] = { 255, 120, 0 }, [C.LEDGE_W] = { 255, 120, 0 }, [C.LEDGE_N] = { 255, 120, 0 }, [C.LEDGE_S] = { 255, 160, 0 },
  [C.DOOR] = { 255, 0, 255 }, [C.TREE] = { 10, 80, 20 }, [C.BUILDING] = { 230, 60, 60 }, [C.ROCK] = { 120, 80, 50 },
  [C.SMALL] = { 250, 250, 250 }, [C.STRUCT] = { 255, 255, 0 }, [C.BRIDGE] = { 160, 100, 40 }, [C.LOG] = { 120, 70, 30 },
}
-- maps left out: under the sea, unused, the tops of structures (the landmarks stand for those), and
-- the islands only an event's ticket reaches (Navel Rock, Birth Island)
local SKIP = { "UNDERWATER", "PROTOTYPE", "SKY_PILLAR_TOP", "MT_PYRE_SUMMIT", "NAVEL_ROCK", "BIRTH_ISLAND" }
-- the regions: Hoenn whole; Kanto and the Sevii Islands' three pictures (FireRed / LeafGreen) each
-- the maps whose sections are on that picture of the Town Map; each from a town of its own
local REGIONS = {
  hoenn = { root = "LITTLEROOT_TOWN$" },
  kanto = { root = "PALLET_TOWN$", picture = 0 },
  sevii123 = { root = "ONE_ISLAND$", picture = 1 },
  sevii45 = { root = "FIVE_ISLAND$", picture = 2 },
  sevii67 = { root = "SIX_ISLAND$", picture = 3 },
}
-- a door's kind, from the name of the map it leads into (the first that fits)
local KINDS = {
  { "INDIGO_PLATEAU_POKEMON_CENTER", "league" }, { "SILPH_CO", "silph" }, { "POKEMON_TOWER", "ptower" },
  { "TRAINER_TOWER", "ttower" }, { "SSANNE", "harbor" }, { "POKEMON_MANSION", "mansion" }, { "POWER_PLANT", "plant" },
  { "POKEMON_CENTER", "center" }, { "POKECENTER", "center" }, { "_MART", "mart" }, { "DEPARTMENT_STORE", "store" }, { "_GYM", "gym" },
  { "_LAB", "lab" }, { "HOUSE", "house" }, { "CONTEST_HALL", "contest" }, { "GAME_CORNER", "corner" },
  { "WEATHER_INSTITUTE", "institute" }, { "SPACE_CENTER", "space" }, { "TRICK_HOUSE", "trick" },
  { "POKEMON_LEAGUE", "league" }, { "BATTLE_TOWER", "tower" }, { "BIKE_SHOP", "shop" }, { "_SHOP", "shop" },
  { "MUSEUM", "museum" }, { "SCHOOL", "school" }, { "SHIPYARD", "shipyard" }, { "HARBOR", "harbor" },
  { "COVE_LILY", "house" }, { "SAFARI_ZONE", "gate" },
}

return function(engine, deps)
  deps = deps or {}
  local Wd = { MT = MT, C = C, CLASS_COLOR = CLASS_COLOR, REGIONS = REGIONS }

  local function maps() return deps.maps and deps.maps() or nil end
  local MB = engine("src.core.game3.mb")
  local Conn = engine("src.core.game3.connections")
  local Dataset = engine("src.core.game3.dataset")

  -- (inside a coroutine: a yield now and then, opts.pace saying when)
  local pace
  local function breathe()
    if pace and pace() and coroutine.running() then coroutine.yield() end
  end

  -- ------- which maps

  local function outdoor(id, def)
    if type(def) ~= "table" then return false end
    for _, s in ipairs(SKIP) do if id:find(s, 1, true) then return false end end
    local ok, out = pcall(Dataset.isOutdoorMapType, def.mapType)
    if not (ok and out) then return false end
    local L = def.midLayout
    return L ~= nil and (L.trueWidth or L.width or 0) > 0
  end
  local function sizeOf(def)
    local L = def.midLayout
    return L.trueWidth or L.width, L.trueHeight or L.height
  end

  -- ------- placing them: the connections, then doors, then the Town Map

  -- one group of maps joined by their connections, from `root`, at 0, 0 (its own frame)
  local function group(all, root, taken)
    local out = { { id = root, def = all[root], x = 0, y = 0 } }
    taken[root] = true
    local i = 1
    while out[i] do
      local cur = out[i]
      i = i + 1
      local cw, ch = sizeOf(cur.def)
      for _, c in ipairs(Conn.each(cur.def)) do
        local dest = all[c.map]
        if dest and not taken[c.map] and outdoor(c.map, dest) then
          local dw, dh = sizeOf(dest)
          local x, y
          if c.dir == "north" then x, y = c.offset, -dh
          elseif c.dir == "south" then x, y = c.offset, ch
          elseif c.dir == "west" then x, y = -dw, c.offset
          elseif c.dir == "east" then x, y = cw, c.offset end
          if x then
            taken[c.map] = true
            out[#out + 1] = { id = c.map, def = dest, x = cur.x + x, y = cur.y + y }
          end
        end
      end
    end
    return out
  end

  -- FireRed / LeafGreen's Town Map: its four pictures' grids (22 x 15 cells, a map layer and a dungeon
  -- layer, [y][x] = the section), and which picture a section is on
  local function frlgLayouts()
    if deps.layouts then return deps.layouts() end
    local RX = engine("src.import.gba.region_map_extract")
    if not RX then return nil end
    pcall(RX.ensureGenerated)
    return RX.LAYOUTS
  end
  local function pictureOf(sec)
    if deps.pictureOf then return deps.pictureOf(sec) end
    local Pos = engine("src.ui.game3.region_map_position")
    local ok, r = pcall(Pos and Pos.regionFor or error, tonumber(sec) or -1, frlgLayouts())
    return ok and tonumber(r) or nil
  end
  -- (the region being built: Hoenn's, or one of FireRed / LeafGreen's pictures)
  local cur = REGIONS.hoenn

  -- the Town Map section of a map: its rectangle on the Town Map (cells)
  local function sectionRect(sec)
    if cur.picture then
      local P = (frlgLayouts() or {})[cur.picture]
      if not P then return nil end
      local x0, y0, x1, y1
      for _, layer in ipairs({ "map", "dungeon" }) do
        local grid = P[layer]
        if grid and not x0 then
          for y = 0, 14 do
            local row = grid[y]
            for x = 0, 21 do
              if row and row[x] == sec then
                x0, y0 = min(x0 or x, x), min(y0 or y, y)
                x1, y1 = max(x1 or x, x), max(y1 or y, y)
              end
            end
          end
        end
      end
      if not x0 then return nil end
      return x0, y0, x1 - x0 + 1, y1 - y0 + 1
    end
    local Mapsec = engine("src.ui.game3.rse.mapsec")
    local ok, e = pcall(Mapsec and Mapsec.entry or error, sec)
    if ok and type(e) == "table" and tonumber(e.width) and e.width > 0 then
      return e.x, e.y, e.width, e.height
    end
    return nil
  end

  -- what is already there: an occupancy grid over a box around the mainland (0 nothing, 1 open
  -- ground or water, 2 a wall), made once (filled in order: a plain array) and marked as each group
  -- is placed
  local function occMark(occ, grp)
    local cols = occ.cols
    for _, m in ipairs(grp) do
      local L = m.def.midLayout
      for cy = 0, m.h - 1 do
        local gy = m.y + cy - occ.y0
        if gy >= 0 and gy < occ.rows then
          local row = gy * cols + (m.x - occ.x0) + 1
          for cx = 0, m.w - 1 do
            local gx = m.x + cx - occ.x0
            if gx >= 0 and gx < cols then
              local coll = L:collAt(cx, cy)
              if coll ~= 255 then occ[row + cx] = coll == 7 and 2 or 1 end
            end
          end
        end
      end
      breathe()
    end
  end
  local function occupancy(list)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, m in ipairs(list) do
      x0, y0 = min(x0, m.x), min(y0, m.y)
      x1, y1 = max(x1, m.x + m.w), max(y1, m.y + m.h)
    end
    local pad = 200
    x0, y0, x1, y1 = x0 - pad, y0 - pad, x1 + pad, y1 + pad
    local cols = x1 - x0
    local occ = { x0 = x0, y0 = y0, cols = cols, rows = y1 - y0 }
    for k = 1, cols * (y1 - y0) do
      occ[k] = 0
      if k % 50000 == 0 then breathe() end
    end
    occMark(occ, list)
    return occ
  end
  -- how badly a group placed at ox, oy lies over what's there (its tiles over open ground or water)
  local function clash(occ, grp, ox, oy)
    local bad = 0
    local cols = occ.cols
    for _, m in ipairs(grp) do
      local L = m.def.midLayout
      local w, h = sizeOf(m.def)
      for cy = 0, h - 1, 2 do
        local gy = oy + m.y + cy - occ.y0
        if gy >= 0 and gy < occ.rows then
          local row = gy * cols + (ox + m.x - occ.x0) + 1
          for cx = 0, w - 1, 2 do
            local here = occ[row + cx]
            if here == 1 and L:collAt(cx, cy) ~= 255 and ox + m.x + cx - occ.x0 >= 0 and ox + m.x + cx - occ.x0 < cols then
              bad = bad + 1
            end
          end
        end
      end
    end
    return bad
  end
  -- the nearest spot to (gx, gy) where the group clashes least (a spiral out, every `step` tiles)
  local function settle(occ, grp, gx, gy, reach, step)
    local best, bx, by = clash(occ, grp, gx, gy), gx, gy
    if best == 0 then return gx, gy, 0 end
    for r = step, reach, step do
      for dy = -r, r, step do
        for dx = -r, r, step do
          if max(abs(dx), abs(dy)) == r then
            breathe()
            local b = clash(occ, grp, gx + dx, gy + dy)
            -- (a little for the distance, so the nearest of the clean spots wins)
            local score = b * 4 + (abs(dx) + abs(dy)) / 8
            if score < best * 4 + (abs(bx - gx) + abs(by - gy)) / 8 then best, bx, by = b, gx + dx, gy + dy end
          end
        end
      end
      if best == 0 then break end
      breathe()
    end
    return bx, by, best
  end

  -- a door between a group's map and a placed map: where the group would have to be for the two
  -- doors to meet (the median of every pair); none, then through a gatehouse (this map's door into an
  -- indoor map whose other door leads to a placed map: the gate's own width between them). A warp's
  -- destWarp is 1-based here (the engine's), the index into the other map's warps
  local logf
  local function byDoors(grp, placedById, all, viaGate)
    local xs, ys = {}, {}
    local function add(x, y, why)
      xs[#xs + 1], ys[#ys + 1] = x, y
      if logf then logf("    door pair", grp[1].id, why, x, y) end
    end
    for _, m in ipairs(grp) do
      for _, w in ipairs(m.def.warps or {}) do
        local host = placedById[w.destMap]
        if host and not viaGate then
          local hw = (host.def.warps or {})[tonumber(w.destWarp) or 0]
          if hw then add(host.x + hw.x - (m.x + w.x), host.y + hw.y - (m.y + w.y), host.id) end
        end
        local gate = all[w.destMap]
        if viaGate and gate and not placedById[w.destMap] and not outdoor(w.destMap, gate) then
          local gin = (gate.warps or {})[tonumber(w.destWarp) or 0]
          for _, gw in ipairs(gate.warps or {}) do
            local host2 = placedById[gw.destMap]
            local hw = host2 and (host2.def.warps or {})[tonumber(gw.destWarp) or 0]
            if gin and hw then
              add(host2.x + hw.x - (gw.x - gin.x) - (m.x + w.x), host2.y + hw.y - (gw.y - gin.y) - (m.y + w.y),
                w.destMap .. ">" .. host2.id)
            end
          end
        end
      end
    end
    if #xs == 0 then return nil end
    table.sort(xs)
    table.sort(ys)
    return xs[floor((#xs + 1) / 2)], ys[floor((#ys + 1) / 2)], #xs
  end

  -- a city inside another map's island (Sootopolis in Route 126's crater): the host's biggest island
  -- that touches none of its edges, and the city's own outer rock left off (the host's rim stands for it)
  local INTO = { SOOTOPOLIS_CITY = "ROUTE126" }
  local function island(host)
    local L, w, h = host.def.midLayout, host.w, host.h
    local seen, best, bestN = {}, nil, 0
    for sy = 0, h - 1 do
      for sx = 0, w - 1 do
        local k0 = sy * w + sx
        local c0 = L:collAt(sx, sy)
        if not seen[k0] and c0 ~= 41 and c0 ~= 255 then
          local stack, n, tx, ty, edge = { k0 }, 0, 0, 0, false
          seen[k0] = true
          while #stack > 0 do
            local k = table.remove(stack)
            local x, y = k % w, floor(k / w)
            n, tx, ty = n + 1, tx + x, ty + y
            if x == 0 or y == 0 or x == w - 1 or y == h - 1 then edge = true end
            for d = 1, 4 do
              local nx, ny = x + (d == 1 and 1 or d == 2 and -1 or 0), y + (d == 3 and 1 or d == 4 and -1 or 0)
              if nx >= 0 and ny >= 0 and nx < w and ny < h then
                local nk = ny * w + nx
                local c = L:collAt(nx, ny)
                if not seen[nk] and c ~= 41 and c ~= 255 then
                  seen[nk] = true
                  stack[#stack + 1] = nk
                end
              end
            end
          end
          if not edge and n > bestN then best, bestN = { tx / n, ty / n }, n end
        end
      end
    end
    return best
  end
  local function outerRock(m)
    local L, w, h = m.def.midLayout, m.w, m.h
    local crop, stack = {}, {}
    local function push(x, y)
      local k = y * w + x
      if not crop[k] and L:collAt(x, y) == 7 then crop[k] = true stack[#stack + 1] = k end
    end
    for x = 0, w - 1 do push(x, 0) push(x, h - 1) end
    for y = 0, h - 1 do push(0, y) push(w - 1, y) end
    while #stack > 0 do
      local k = table.remove(stack)
      local x, y = k % w, floor(k / w)
      if x > 0 then push(x - 1, y) end
      if x < w - 1 then push(x + 1, y) end
      if y > 0 then push(x, y - 1) end
      if y < h - 1 then push(x, y + 1) end
    end
    return crop
  end

  -- Town Map cells -> tiles, fitted over the maps placed by their connections (one line per axis; with
  -- only a few maps -- an island's -- one scale for both)
  local function townMapFit(list)
    local sx, sxx, sxt, st, n = 0, 0, 0, 0, 0
    local sy, syy, syt, su = 0, 0, 0, 0
    for _, m in ipairs(list) do
      local ex, ey, ew, eh = sectionRect(m.sec)
      if ex then
        local cx, cy = ex + ew / 2, ey + eh / 2
        local tx, ty = m.x + m.w / 2, m.y + m.h / 2
        sx, sxx, sxt, st = sx + cx, sxx + cx * cx, sxt + cx * tx, st + tx
        sy, syy, syt, su = sy + cy, syy + cy * cy, syt + cy * ty, su + ty
        n = n + 1
      end
    end
    if n < 2 then return nil end
    local vx, vy = n * sxx - sx * sx, n * syy - sy * sy
    local ax = (n * sxt - sx * st) / max(1e-6, vx)
    local ay = (n * syt - sy * su) / max(1e-6, vy)
    if n < 6 or ax < 4 or ay < 4 then
      local a = ((n * sxt - sx * st) + (n * syt - sy * su)) / max(1e-6, vx + vy)
      if a < 4 then return nil end
      ax, ay = a, a
    end
    return { ax = ax, bx = (st - ax * sx) / n, ay = ay, by = (su - ay * sy) / n }
  end

  -- a map that stands in for another along its connections (Saffron City's, the middle of the city
  -- without its gatehouses): where in the real one it is, by their tiles
  local function standInOffset(m, real)
    local A, B = real.midLayout, m.def.midLayout
    local aw, ah = sizeOf(real)
    local bw, bh = m.w, m.h
    local best, bx, by = -1, 0, 0
    for oy = 0, max(0, ah - bh) do
      for ox = 0, max(0, aw - bw) do
        local n = 0
        for y = 0, bh - 1, 2 do
          for x = 0, bw - 1, 2 do
            if A:midAt(x + ox, y + oy) == B:midAt(x, y) then n = n + 1 end
          end
        end
        if n > best then best, bx, by = n, ox, oy end
      end
      breathe()
    end
    return bx, by
  end

  -- every outdoor map of the region placed: { list, byId, root, fit }
  function Wd.place(all, region)
    all = all or maps()
    if not all then return nil end
    cur = REGIONS[region or "hoenn"] or REGIONS.hoenn
    local ids = {}
    -- (a map's layout is read the first time it's asked for: a few at a time)
    local seen = 0
    for id, def in pairs(all) do
      if type(id) == "string" and outdoor(id, def)
          and (not cur.picture or pictureOf(def.regionMapSectionId) == cur.picture) then
        ids[#ids + 1] = id
      end
      seen = seen + 1
      if seen % 8 == 0 then breathe() end
    end
    table.sort(ids)
    -- (a map with a stand-in along the connections is that stand-in: not placed again)
    local standIn, kept = {}, {}
    for _, id in ipairs(ids) do
      local real = id:match("^(.+)_CONNECTION$")
      if real and all[real] then standIn[real] = id end
    end
    for _, id in ipairs(ids) do if not standIn[id] then kept[#kept + 1] = id end end
    ids = kept
    local root
    for _, id in ipairs(ids) do if id:match(cur.root) then root = id end end
    root = root or ids[1]
    if not root then return nil end
    local taken = {}
    local main = group(all, root, taken)
    local list, byId = {}, {}
    local function add(m, how)
      m.w, m.h = sizeOf(m.def)
      m.sec = m.def.regionMapSectionId
      m.how = how
      list[#list + 1] = m
      byId[m.id] = m
    end
    for _, m in ipairs(main) do add(m, "joined") end
    breathe()
    -- (the real map behind a stand-in: its doors moved onto the stand-in (those inside it: its
    -- gatehouses are the routes' own), and its own id finding the stand-in, offset (the player there))
    for real, sid in pairs(standIn) do
      local m = byId[sid]
      if m then
        local ox, oy = standInOffset(m, all[real])
        m.warps = {}
        for _, w in ipairs(all[real].warps or {}) do
          local x, y = w.x - ox, w.y - oy
          if x >= 0 and y >= 0 and x < m.w and y < m.h then
            m.warps[#m.warps + 1] = { x = x, y = y, destMap = w.destMap, destWarp = w.destWarp }
          end
        end
        local rw, rh = sizeOf(all[real])
        byId[real] = { id = real, def = all[real], x = m.x - ox, y = m.y - oy, w = rw, h = rh, sec = m.sec,
                       how = "stand-in", standIn = m }
      end
    end
    -- (the rest, a group at a time: maps joined to each other but not to the mainland)
    local groups = {}
    for _, id in ipairs(ids) do
      if not taken[id] then groups[#groups + 1] = group(all, id, taken) end
    end
    for _, grp in ipairs(groups) do
      for _, m in ipairs(grp) do m.w, m.h = sizeOf(m.def) end
    end
    local fit = townMapFit(list)
    local occ = occupancy(list)
    -- (a city into its host's island; doors next: those that meet a placed map, then those through a
    -- gatehouse; then the Town Map for the rest; each settled clear of what's there)
    local pending = {}
    for _, grp in ipairs(groups) do
      local into
      for _, m in ipairs(grp) do
        for name, hostName in pairs(INTO) do
          if m.id:sub(-#name) == name then
            for _, h in ipairs(list) do if h.id:sub(-#hostName) == hostName then into = { m = m, host = h } end end
          end
        end
      end
      local spot = into and island(into.host)
      if spot then
        local m = into.m
        local dx = floor(into.host.x + spot[1] - m.w / 2 + 0.5) - m.x
        local dy = floor(into.host.y + spot[2] - m.h / 2 + 0.5) - m.y
        for _, gm in ipairs(grp) do
          gm.x, gm.y = gm.x + dx, gm.y + dy
          gm.crop = outerRock(gm)
          add(gm, "into")
        end
        occMark(occ, grp)
      else
        pending[#pending + 1] = grp
      end
    end
    -- (a door straight into a placed map first, then through a gatehouse; neither, the biggest group
    -- left by the Town Map; and after each, the doors again: a map placed may be the one another's
    -- doors lead to (the Safari Zone's areas, an island's forest))
    local function byDoor(viaGate)
      for gi = #pending, 1, -1 do
        local grp = pending[gi]
        local dx, dy = byDoors(grp, byId, all, viaGate)
        if dx then
          local px, py = settle(occ, grp, dx, dy, viaGate and 24 or 8, 1)
          for _, m in ipairs(grp) do
            m.x, m.y = m.x + px, m.y + py
            add(m, viaGate and "gate" or "door")
          end
          table.remove(pending, gi)
          occMark(occ, grp)
          return true
        end
      end
      return false
    end
    local function byTownMap()
      local gi = 1
      for i, grp in ipairs(pending) do
        if #grp > #pending[gi] then gi = i end
      end
      local grp = table.remove(pending, gi)
      local anchor
      for _, m in ipairs(grp) do
        if sectionRect(m.def.regionMapSectionId) then anchor = m break end
      end
      local gx, gy = 0, 0
      if fit and anchor then
        local ex, ey, ew, eh = sectionRect(anchor.def.regionMapSectionId)
        gx = floor(fit.ax * (ex + ew / 2) + fit.bx - anchor.w / 2 - anchor.x + 0.5)
        gy = floor(fit.ay * (ey + eh / 2) + fit.by - anchor.h / 2 - anchor.y + 0.5)
      end
      local px, py = settle(occ, grp, gx, gy, 96, 4)
      px, py = settle(occ, grp, px, py, 4, 1)
      for _, m in ipairs(grp) do
        m.x, m.y = m.x + px, m.y + py
        add(m, "townmap")
      end
      occMark(occ, grp)
    end
    while #pending > 0 do
      if not byDoor(false) and not byDoor(true) then byTownMap() end
    end
    return { list = list, byId = byId, root = root, fit = fit }
  end

  -- ------- the tile art: per tileset, each metatile's colours (its four quarters as seen from above,
  -- the top layer over the bottom) and how green and leafy it is

  -- a tileset's own pixels: each metatile's 256 palette bytes (the bottom layer's, the top layer's; 0 is
  -- see-through) and the palette's colours -> { under, over, uOff, oOff, uSlot, oSlot, LR, LG, LB, ids } | nil
  -- (read for its colours, and again for the map's picture at full size; the tests may hand their own)
  local function readPixels(pair)
    if deps.pixels then return deps.pixels(pair) end
    local NP = engine("src.import.gba.native_pack")
    local Extract = engine("src.import.gba.extract_island1")
    if not (NP and Extract and Dataset and Dataset.cache) then return nil end
    local cache = Dataset.cache()
    local root = (Extract.NATIVE_ROOT or (Extract.CACHE_ROOT .. "/native")) .. "/" .. pair
    local okU, under = pcall(cache.read, cache, root .. "/mids.idx")
    local okP, palBlob = pcall(cache.read, cache, root .. "/palettes.bin")
    if not (okU and under and okP and palBlob) then return nil end
    local okO, over = pcall(cache.read, cache, root .. "/mids_over.idx")
    local ui = NP.decodeIdx(under)
    local pals = NP.decodePalettes(palBlob)
    if not (ui and pals) then return nil end
    local rgb = NP.palsToRgb8(pals)
    local LR, LG, LB = {}, {}, {}
    for byte = 0, 255 do
      local c = rgb[floor(byte / 16) % 16][byte % 16]
      LR[byte], LG[byte], LB[byte] = c[1], c[2], c[3]
    end
    local oi = okO and over and NP.decodeIdx(over) or nil
    local uSlot, oSlot = {}, {}
    for i, m in ipairs(ui.midIds) do uSlot[m] = i - 1 end
    if oi then for i, m in ipairs(oi.midIds) do oSlot[m] = i - 1 end end
    return { under = under, over = oi and over or nil, uOff = 13 + ui.midCount * 2, oOff = oi and (13 + oi.midCount * 2) or 0,
             uSlot = uSlot, oSlot = oSlot, LR = LR, LG = LG, LB = LB, ids = ui.midIds }
  end

  local artCache = {}
  local function readArt(pair)
    if artCache[pair] ~= nil then return artCache[pair] or nil end
    artCache[pair] = false
    -- (the tests hand it their own: { [mid] = { q, green, blue, rock, over, r, g, b } })
    if deps.art then
      artCache[pair] = deps.art(pair) or false
      return artCache[pair] or nil
    end
    local P = readPixels(pair)
    if not P then return nil end
    local under, over, LR, LG, LB = P.under, P.over, P.LR, P.LG, P.LB
    local overSlot, uOff, oOff = P.oSlot, P.uOff, P.oOff
    local ui = { midIds = P.ids }
    local byte = string.byte
    -- (each palette byte's kind: 1 leafy green, 2 water blue, 3 rock (browns, greys), 0 else)
    local KIND = {}
    for p = 0, 255 do
      local r, g, b = LR[p], LG[p], LB[p]
      local hi, lo = max(r, g, b), min(r, g, b)
      local sat = hi > 0 and (hi - lo) / hi or 0
      if g > r + 10 and g > b + 6 then KIND[p] = 1
      elseif b > r + 24 and b >= g - 8 then KIND[p] = 2
      elseif (r >= g - 4 and g >= b - 4 and sat < 0.55 and hi < 215) or (sat < 0.14 and hi < 190) then KIND[p] = 3
      else KIND[p] = 0 end
    end
    -- art[mid] = { q = { r, g, b } x 4 (TL TR BL BR), green / blue / rock (0..1: the share of its pixels),
    --              over (0..1), r, g, b (the mean) }
    local art = {}
    for i, mid in ipairs(ui.midIds) do
      if i % 64 == 0 then breathe() end
      local ub = uOff + (i - 1) * 256
      local os = overSlot[mid]
      local ob = os and (oOff + os * 256) or nil
      local q = {}
      local tr, tg, tb, n, cov = 0, 0, 0, 0, 0
      local kinds = { 0, 0, 0 }
      for qy = 0, 1 do
        for qx = 0, 1 do
          local r, g, b, k = 0, 0, 0, 0
          for py = qy * 8, qy * 8 + 7 do
            for px = qx * 8, qx * 8 + 7 do
              local off = py * 16 + px
              local p = ob and byte(over, ob + off) or 0
              if p ~= 0 then cov = cov + 1 else p = byte(under, ub + off) or 0 end
              if p ~= 0 then
                r, g, b, k = r + LR[p], g + LG[p], b + LB[p], k + 1
                local kd = KIND[p]
                if kd > 0 then kinds[kd] = kinds[kd] + 1 end
              end
            end
          end
          k = max(1, k)
          q[#q + 1] = r / k
          q[#q + 1] = g / k
          q[#q + 1] = b / k
          tr, tg, tb, n = tr + r, tg + g, tb + b, n + k
        end
      end
      n = max(1, n)
      art[mid] = { q = q, green = kinds[1] / 256, blue = kinds[2] / 256, rock = kinds[3] / 256, over = cov / 256,
                   r = tr / n, g = tg / n, b = tb / n }
    end
    artCache[pair] = art
    breathe()
    return art
  end

  -- a wall's look: a tree (green and leafy), rock (brown or grey, or a rock in the water) or something
  -- built
  local function wallClass(a)
    if not a then return C.STRUCT end
    if a.green >= 0.38 then return C.TREE end
    if a.blue >= 0.4 or a.rock >= 0.5 or (a.blue + a.rock >= 0.7) then return C.ROCK end
    return C.STRUCT
  end

  -- ------- the tiles

  local function doorKind(dest, all)
    local d = dest and all[dest]
    for _, k in ipairs(KINDS) do
      if dest and dest:find(k[1], 1, true) then return k[2] end
    end
    if d then
      local mt = tonumber(d.mapType)
      if mt == 4 or d.cave == 1 then return "cave" end
      local okO, out = pcall(Dataset.isOutdoorMapType, d.mapType)
      if okO and out then return "gate" end
    end
    return "special"
  end

  -- a building's footprint from its door: the solid block of building tiles above and beside it
  -- (lo, hi: how far along it may run, either side: halfway to the next building's door)
  local function footprint(world, dx, dy, lo, hi)
    lo, hi = lo or -math.huge, hi or math.huge
    local cls, cols = world.cls, world.cols
    local function at(x, y)
      local gx, gy = x - world.x0, y - world.y0
      if gx < 0 or gy < 0 or gx >= cols or gy >= world.rows then return nil end
      return gy * cols + gx + 1
    end
    local k0 = at(dx, dy - 1)
    if not k0 or world.filled[k0] then return nil end
    -- (a building's tiles: walls from the same half of the tilesets as the one over the door (a town's
    -- own houses are its second tileset; Centers and Marts the first), not leafy)
    local second = (world.mid[k0] or 0) >= 512
    local built
    -- (a gatehouse entered going south (FireRed / LeafGreen's into Saffron): the building under its door)
    local function under()
      local k1 = at(dx, dy + 1)
      if not k1 or world.filled[k1] then return nil end
      second = (world.mid[k1] or 0) >= 512
      if not built(k1) then return nil end
      local x0, x1 = dx, dx
      while dx - x0 < 6 and x0 - 1 >= lo and built(at(x0 - 1, dy + 1)) do x0 = x0 - 1 end
      while x1 - dx < 6 and x1 + 1 <= hi and built(at(x1 + 1, dy + 1)) do x1 = x1 + 1 end
      local y1 = dy + 1
      while y1 - dy < 8 do
        local n = 0
        for x = x0, x1 do if built(at(x, y1 + 1)) then n = n + 1 end end
        if n < (x1 - x0 + 1) * 0.7 then break end
        y1 = y1 + 1
      end
      for y = dy, y1 do
        for x = x0, x1 do
          local k = at(x, y)
          if k and cls[k] ~= C.DOOR and (y > dy or built(k)) then cls[k] = C.BUILDING end
        end
      end
      return { x0 = x0, y0 = dy, x1 = x1 + 1, y1 = y1 + 1 }
    end
    function built(k)
      if not k or world.filled[k] then return false end
      local c = cls[k]
      if c == C.BUILDING or c == C.DOOR then return true end
      if c ~= C.STRUCT and c ~= C.ROCK and c ~= C.TREE then return false end
      if ((world.mid[k] or 0) >= 512) ~= second then return false end
      if c == C.TREE then
        local p = world.pairs[world.pix[k] or 0]
        local a = p and p.art[world.mid[k]]
        if not a or a.green >= 0.6 then return false end
      end
      return true
    end
    -- (a doorway two tiles tall (Stern's Shipyard): the floor in it, the wall above that)
    local top = dy - 1
    if not built(k0) then
      local k2 = at(dx, dy - 2)
      if k2 and not world.filled[k2] then
        local was = second
        second = (world.mid[k2] or 0) >= 512
        if built(k2) then top, k0 = dy - 2, k2 else second = was end
      end
    end
    if not built(k0) then return cur.picture and under() or nil end
    -- (along the row above the door, then up while most of that run stays built)
    local x0, x1 = dx, dx
    while dx - x0 < 6 and x0 - 1 >= lo and built(at(x0 - 1, top)) do x0 = x0 - 1 end
    while x1 - dx < 6 and x1 + 1 <= hi and built(at(x1 + 1, top)) do x1 = x1 + 1 end
    local y0 = top
    while dy - y0 < 8 do
      local n = 0
      for x = x0, x1 do if built(at(x, y0 - 1)) then n = n + 1 end end
      if n < (x1 - x0 + 1) * 0.7 then break end
      y0 = y0 - 1
    end
    -- (the roof's top rows: drawn over the player's head (the tiles' top layer) and walked behind, so
    -- not walls; the building's all the same where most of the run's inner tiles (a dome's corners show
    -- the grass behind) are a good share top-layer art and not mostly green)
    local function roofTop(k)
      if not k or world.filled[k] then return false end
      local c = cls[k]
      if c == C.BUILDING or c == C.DOOR or c == C.ROCK or c == C.SEA or c == C.POND
          or c == C.SHALLOW or c == C.CURRENT then return false end
      local p = world.pairs[world.pix[k] or 0]
      local a = p and p.art[world.mid[k]]
      return a ~= nil and a.over >= 0.35 and a.green < 0.65
    end
    local ix0, ix1 = x0, x1
    if x1 - x0 >= 2 then ix0, ix1 = x0 + 1, x1 - 1 end
    for _ = 1, 2 do
      local n = 0
      for x = ix0, ix1 do if roofTop(at(x, y0 - 1)) then n = n + 1 end end
      if n < (ix1 - ix0 + 1) * 0.6 then break end
      y0 = y0 - 1
    end
    for y = y0, dy do
      for x = x0, x1 do
        local k = at(x, y)
        if k and cls[k] ~= C.DOOR and (y < dy or built(k)) then cls[k] = C.BUILDING end
      end
    end
    return { x0 = x0, y0 = y0, x1 = x1 + 1, y1 = dy + 1 }
  end

  -- smooth value noise, 0..1, at tile x, y, its cells s tiles across (the filled-in land's ragged edge)
  local function lattice(i, j)
    local v = math.sin(i * 127.1 + j * 311.7) * 43758.5453
    return v - floor(v)
  end
  local function vnoise(x, y, s)
    local fx, fy = x / s, y / s
    local ix, iy = floor(fx), floor(fy)
    local tx, ty = fx - ix, fy - iy
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    local a, b = lattice(ix, iy), lattice(ix + 1, iy)
    local c, d = lattice(ix, iy + 1), lattice(ix + 1, iy + 1)
    return (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * ty
  end
  Wd.noise = vnoise

  -- ------- heights (world units), read the way the game draws its land: from above and a little
  -- from the south, so a mountain shows as rows of its cliff faces, its summit toward its north edge.
  --   - Each column, going north from a mountain's foot, rises a row's worth with every row of rock
  --     (a waterfall's face too); its walkable ground (paths, the tops), the land it closes in and the
  --     lakes up there hold the level they're at; past its north edge it's back to the land's level.
  --     The far (north) side comes down twice as steeply as it went up.
  --   - Columns don't agree exactly: high ground is smoothed across (the median of five), and each
  --     closed-in field or lake made flat at its own median.
  --   - The sea's surface is 0, its bed well under it (shallows less); a lake's surface just under the
  --     ground round it. A bridge or a log over water keeps the water's bed and surface under its deck.
  local H = { SEA_BED = -0.26, SHALLOW_BED = -0.1, GROUND = 0.06, ROW = 0.04, LEVEL = 0.1, POND_DEPTH = 0.08,
              DECK = 0.07, LOG = 0.045, DECK_LEVEL = 0.045, TREE = 0.08, BRIDGE_LAND = 0.05 }
  H.SEA = H.SEA_BED
  Wd.H = H
  local WATER = { [C.SEA] = true, [C.POND] = true, [C.SHALLOW] = true, [C.CURRENT] = true }
  local HIGH = { [C.ROCK] = true, [C.ROCKY] = true, [C.FALL] = true }
  -- (where the player walks: the walkable areas, the levels; the most steps up there are)
  local STEP_WALK = { [C.GROUND] = true, [C.TALL] = true, [C.LONG] = true, [C.SAND] = true, [C.ASH] = true,
                      [C.SOIL] = true, [C.PUDDLE] = true, [C.MOUNT] = true, [C.DOOR] = true, [C.BRIDGE] = true,
                      [C.LOG] = true }
  local STEP_CAP = 24
  -- (where the player walks, for the walkable areas; a lake's water counts as one of its own)
  local WALK = { [C.GROUND] = true, [C.TALL] = true, [C.LONG] = true, [C.SAND] = true, [C.ASH] = true,
                 [C.SOIL] = true, [C.PUDDLE] = true, [C.MOUNT] = true, [C.DOOR] = true, [C.BRIDGE] = true,
                 [C.LOG] = true, [C.POND] = true, [C.SHALLOW] = true }
  Wd.WATER = WATER
  local function heights(world)
    local cls, cols, rows = world.cls, world.cols, world.rows
    local filled = world.filled
    local n = cols * rows
    local function wetC(c) return not c or WATER[c] end
    -- (1. what's closed in: fields (land) and lakes (water) that reach neither the sea nor the edge)
    local comp, info = {}, {}
    for k = 1, n do comp[k] = 0 end
    local nextId = 0
    local stack = {}
    for k0 = 1, n do
      if comp[k0] == 0 and not HIGH[cls[k0]] then
        nextId = nextId + 1
        local w0 = wetC(cls[k0])
        local inf = { water = w0, open = false }
        info[nextId] = inf
        comp[k0] = nextId
        stack[1] = k0
        local sp = 1
        while sp > 0 do
          local k = stack[sp]
          stack[sp] = nil
          sp = sp - 1
          local x = (k - 1) % cols
          local c = cls[k]
          if x == 0 or x == cols - 1 or k <= cols or k > n - cols then inf.open = true end
          if w0 and (not c or c == C.SEA or c == C.CURRENT) then inf.open = true end
          for d = 1, 4 do
            local nk = d == 1 and k - 1 or d == 2 and k + 1 or d == 3 and k - cols or k + cols
            local ok = nk >= 1 and nk <= n and (d > 2 or ((d == 1 and x > 0) or (d == 2 and x < cols - 1)))
            if ok then
              local nc = cls[nk]
              local nw = wetC(nc)
              -- (land by the sea or the shallows is low; by a lake it may be up a mountain)
              if not w0 and nw and nc ~= C.POND then inf.open = true end
              if comp[nk] == 0 and not HIGH[nc] and nw == w0 then
                comp[nk] = nextId
                sp = sp + 1
                stack[sp] = nk
              end
            end
          end
        end
      end
      if k0 % 20000 == 0 then breathe() end
    end
    -- (open water: the sea and what reaches it)
    local function sea(k)
      if not wetC(cls[k]) then return false end
      local inf = info[comp[k]]
      return not inf or inf.open
    end
    -- (2. the walkable areas, the levels: tiles joined the way the player walks (cut at ledges,
    -- cliffs, trees, walls and water), across two maps only where the game joins them; one by the sea
    -- or the edge is the ground's own level)
    local mapA, list = world.mapIx, world.maps
    local function joinedAcross(a, b)
      local ma, mb = mapA[a], mapA[b]
      if ma == mb then return true end
      local A, B = ma and list[ma], mb and list[mb]
      return A ~= nil and B ~= nil and A.how == "joined" and B.how == "joined"
    end
    local reg, rinfo = {}, {}
    for k = 1, n do reg[k] = 0 end
    local nr = 0
    for k0 = 1, n do
      if reg[k0] == 0 and STEP_WALK[cls[k0]] and not filled[k0] then
        nr = nr + 1
        local inf = { n = 0, ground = false, map = mapA[k0] }
        rinfo[nr] = inf
        reg[k0] = nr
        stack[1] = k0
        local sp = 1
        while sp > 0 do
          local k = stack[sp]
          stack[sp] = nil
          sp = sp - 1
          inf.n = inf.n + 1
          local x = (k - 1) % cols
          if x == 0 or x == cols - 1 or k <= cols or k > n - cols then inf.ground = true end
          for d = 1, 4 do
            local nk = d == 1 and k - 1 or d == 2 and k + 1 or d == 3 and k - cols or k + cols
            local ok = nk >= 1 and nk <= n and (d > 2 or ((d == 1 and x > 0) or (d == 2 and x < cols - 1)))
            if ok then
              if sea(nk) then inf.ground = true end
              if reg[nk] == 0 and STEP_WALK[cls[nk]] and not filled[nk] and joinedAcross(k, nk) then
                reg[nk] = nr
                sp = sp + 1
                stack[sp] = nk
              end
            end
          end
        end
      end
      if k0 % 20000 == 0 then breathe() end
    end
    -- (an area of only a few tiles -- a cave's door in a cliff, a tile between rocks, a corner between
    -- ledges -- isn't a level of its own: it takes the ground round it, as a forest does)
    local MIN_AREA = 16
    for k = 1, n do
      local r = reg[k]
      if r > 0 and rinfo[r].n < MIN_AREA then reg[k] = 0 end
    end
    -- (3. the steps between them, read off the art: going north across a band of cliff (its face, the
    -- way the game draws one) to another area, that one is higher, a step for every two rows of face
    -- (at most three); a ledge a step, down the way it's jumped)
    local votes = {}
    local function vote(lo, hi, d)
      if lo == hi or lo == 0 or hi == 0 then return end
      local key = lo * 65536 + hi
      local v = votes[key]
      if not v then v = { lo = lo, hi = hi, n = 0, d = 0 } votes[key] = v end
      v.n, v.d = v.n + 1, v.d + d
    end
    local BAND = 6
    -- (FireRed / LeafGreen's towns are flat: the stone walls round Saffron City aren't cliffs)
    local function cliff(k)
      if not cur.picture then return true end
      local m = list[mapA[k] or 0]
      local mt = m and tonumber(m.def.mapType)
      return not (mt == 1 or mt == 2)
    end
    for x = 0, cols - 1 do
      local below, band, rock, ledge = 0, 0, false, false
      for y = rows - 1, 0, -1 do
        local k = y * cols + x + 1
        local r = reg[k]
        local c = cls[k]
        if r > 0 then
          -- (FireRed / LeafGreen's ledges are a hop on flat land: only a cliff is a step there)
          if below > 0 and band > 0 and (rock or (ledge and not cur.picture)) then
            vote(below, r, ledge and not rock and 1 or min(3, floor((band + 1) / 2)))
          end
          below, band, rock, ledge = r, 0, false, false
        elseif below > 0 then
          band = band + 1
          if (c == C.ROCK or c == C.FALL or c == C.ROCKY) and cliff(k) then rock = true
          elseif c == C.LEDGE_S then ledge = true
          elseif sea(k) or c == C.TREE or band > BAND then below, band, rock, ledge = 0, 0, false, false end
        end
      end
      if x % 32 == 0 then breathe() end
    end
    for y = 0, rows - 1 do
      local base = y * cols
      for x = 1, cols - 2 do
        local c = cls[base + x + 1]
        if (c == C.LEDGE_E or c == C.LEDGE_W) and not cur.picture then
          local w, e = reg[base + x], reg[base + x + 2]
          -- (east: jumped going east, so the west side is the higher)
          if c == C.LEDGE_E then vote(e, w, 1) else vote(w, e, 1) end
        end
      end
    end
    -- (each pair the way most of its crossings say, by their mean step)
    local edges = {}
    for _, v in pairs(votes) do
      local back = votes[v.hi * 65536 + v.lo]
      if not back or v.n > back.n or (v.n == back.n and v.lo < v.hi) then
        edges[#edges + 1] = { v.lo, v.hi, max(1, floor(v.d / v.n + 0.5)) }
      end
    end
    -- (4. the levels: the fewest steps up from the ground's (an area by the sea, or the edge); a cliff
    -- read both ways can't lift anything twice, and the back of a plateau reached from below some other
    -- way stays low. Steps in buckets: they're whole and few)
    local out = {}
    for _, e in ipairs(edges) do
      local lo = e[1]
      local o = out[lo]
      if not o then o = {} out[lo] = o end
      o[#o + 1] = e
    end
    local level, done = {}, {}
    local bucket = {}
    for r = 1, nr do
      if rinfo[r].ground then
        level[r] = 0
        local b = bucket[0]
        if not b then b = {} bucket[0] = b end
        b[#b + 1] = r
      else
        level[r] = false
      end
    end
    for l = 0, STEP_CAP do
      local b = bucket[l]
      if b then
        local i = 1
        while b[i] do
          local r = b[i]
          i = i + 1
          if not done[r] and level[r] == l then
            done[r] = true
            for _, e in ipairs(out[r] or {}) do
              local hi, nl = e[2], l + e[3]
              if nl <= STEP_CAP and (not level[hi] or nl < level[hi]) then
                level[hi] = nl
                local nb = bucket[nl]
                if not nb then nb = {} bucket[nl] = nb end
                nb[#nb + 1] = hi
              end
            end
          end
        end
      end
    end
    for r = 1, nr do if not level[r] then level[r] = 0 end end
    breathe()
    -- (Mt. Chimney's summit: the highest ground there is)
    local top, chim, chimN = 0, nil, 0
    for r = 1, nr do
      if level[r] > top then top = level[r] end
      local m = list[rinfo[r].map or 0]
      if m and m.id:find("MT_CHIMNEY", 1, true) and not m.id:find("CABLE", 1, true) and rinfo[r].n > chimN then
        chim, chimN = r, rinfo[r].n
      end
    end
    if chim and level[chim] < top + 2 then level[chim] = top + 2 end
    -- (Mt. Pyre's: its own mountain's highest area, two thirds as high as Mt. Chimney)
    local pyre, pyreL = nil, -1
    for r = 1, nr do
      local m = list[rinfo[r].map or 0]
      if m and m.id:find("MT_PYRE_EXTERIOR", 1, true) and rinfo[r].n >= MIN_AREA and level[r] > pyreL then
        pyre, pyreL = r, level[r]
      end
    end
    if pyre and chim then
      local want = floor(level[chim] * 0.65)
      if level[pyre] < want then level[pyre] = want end
    end
    world.levels, world.region = level, reg
    -- (5. everything else, from the walkable ground round it:
    --   - forests, walls and the land filled in past the maps: the lowest level that reaches them
    --     without crossing rock (the trees outside a plateau's cliffs are down with the land, those
    --     closed in by them up on it)
    --   - rock: the top of the cliff it is (the highest area within two tiles); deeper in, the nearest
    --     ground's level smoothed over (a box thirteen across: the mountain climbs to its summit), back
    --     to whole levels; the same for what nothing walkable reaches)
    local lv, claimed = {}, {}
    for k = 1, n do lv[k], claimed[k] = 0, false end
    local buckets, topL = {}, 0
    for k = 1, n do
      local r = reg[k]
      if r > 0 then
        local l = level[r]
        lv[k], claimed[k] = l, true
        local b = buckets[l]
        if not b then b = {} buckets[l] = b end
        b[#b + 1] = k
        if l > topL then topL = l end
      end
    end
    for l = 0, topL do
      local queue = buckets[l]
      if queue then
        local qh = 1
        while queue[qh] do
          local k = queue[qh]
          qh = qh + 1
          local x = (k - 1) % cols
          for dd = 1, 4 do
            local nk = dd == 1 and k - 1 or dd == 2 and k + 1 or dd == 3 and k - cols or k + cols
            local ok = nk >= 1 and nk <= n and (dd > 2 or ((dd == 1 and x > 0) or (dd == 2 and x < cols - 1)))
            if ok and not claimed[nk] and not HIGH[cls[nk]] and not sea(nk) then
              claimed[nk], lv[nk] = true, l
              queue[#queue + 1] = nk
            end
          end
          if qh % 40000 == 0 then breathe() end
        end
      end
    end
    buckets = nil
    -- (the rest, rock first among it: the nearest claimed ground's level)
    local near, dist2 = {}, {}
    local queue = {}
    for k = 1, n do
      if claimed[k] then
        near[k], dist2[k] = lv[k], 0
        queue[#queue + 1] = k
      else
        near[k], dist2[k] = 0, false
      end
    end
    local qh = 1
    while queue[qh] do
      local k = queue[qh]
      qh = qh + 1
      local x = (k - 1) % cols
      for dd = 1, 4 do
        local nk = dd == 1 and k - 1 or dd == 2 and k + 1 or dd == 3 and k - cols or k + cols
        local ok = nk >= 1 and nk <= n and (dd > 2 or ((dd == 1 and x > 0) or (dd == 2 and x < cols - 1)))
        if ok and not dist2[nk] and not sea(nk) then
          dist2[nk], near[nk] = dist2[k] + 1, near[k]
          queue[#queue + 1] = nk
        end
      end
      if qh % 40000 == 0 then breathe() end
    end
    queue = nil
    -- (the highest walkable area each rock tile reaches through rock, and how far: the highest claim
    -- their rock first)
    local topLv, topD = {}, {}
    for k = 1, n do topLv[k], topD[k] = -1, false end
    local byLevel = {}
    for k = 1, n do
      local r = reg[k]
      if r > 0 then
        local l = level[r]
        local b = byLevel[l]
        if not b then b = {} byLevel[l] = b end
        b[#b + 1] = k
      end
    end
    for l = topL, 0, -1 do
      local q = byLevel[l]
      if q then
        for _, k in ipairs(q) do if not topD[k] then topD[k] = 0 end end
        local qh = 1
        while q[qh] do
          local k = q[qh]
          qh = qh + 1
          local x = (k - 1) % cols
          for dd = 1, 4 do
            local nk = dd == 1 and k - 1 or dd == 2 and k + 1 or dd == 3 and k - cols or k + cols
            local ok = nk >= 1 and nk <= n and (dd > 2 or ((dd == 1 and x > 0) or (dd == 2 and x < cols - 1)))
            if ok and not topD[nk] and HIGH[cls[nk]] and reg[nk] == 0 then
              topD[nk], topLv[nk] = (topD[k] or 0) + 1, l
              q[#q + 1] = nk
            end
          end
          if qh % 40000 == 0 then breathe() end
        end
      end
    end
    byLevel = nil
    local M = {}
    for k = 1, n do
      local v = lv[k]
      if not claimed[k] then
        v = near[k]
        if HIGH[cls[k]] then
          local x, y = (k - 1) % cols, floor((k - 1) / cols)
          local best = -1
          for dy = -2, 2 do
            local yy = y + dy
            if yy >= 0 and yy < rows then
              for dx = -2, 2 do
                local xx = x + dx
                if xx >= 0 and xx < cols then
                  local r = reg[yy * cols + xx + 1]
                  if r > 0 and level[r] > best then best = level[r] end
                end
              end
            end
          end
          if best >= 0 then
            -- (a cliff's top)
            v = best
          elseif topLv[k] > v and topD[k] then
            -- (deeper in: between the low ground nearest it and the high ground it climbs to)
            local dl, dt = dist2[k] or 1, topD[k]
            v = v + (topLv[k] - v) * dl / (dl + dt)
          end
        end
      end
      M[k] = v
      if k % 40000 == 0 then breathe() end
    end
    topLv, topD = nil, nil
    -- (rock deeper in than two tiles: smoothed a little (a box five across), whole levels)
    local R = 2
    local A = {}
    for k = 1, n do A[k] = M[k] end
    local function deep(k) return not claimed[k] and dist2[k] and dist2[k] > 2 end
    for y = 0, rows - 1 do
      local base = y * cols
      for x = 0, cols - 1 do
        local k = base + x + 1
        if deep(k) then
          local s, c2 = 0, 0
          for d = -R, R do
            local xx = x + d
            if xx >= 0 and xx < cols and not sea(base + xx + 1) then s, c2 = s + M[base + xx + 1], c2 + 1 end
          end
          A[k] = s / max(1, c2)
        end
      end
      if y % 32 == 0 then breathe() end
    end
    for x = 0, cols - 1 do
      for y = 0, rows - 1 do
        local k = y * cols + x + 1
        if deep(k) then
          local s, c2 = 0, 0
          for d = -R, R do
            local yy = y + d
            if yy >= 0 and yy < rows and not sea(yy * cols + x + 1) then s, c2 = s + A[yy * cols + x + 1], c2 + 1 end
          end
          M[k] = floor(s / max(1, c2) + 0.5)
        end
      end
      if x % 32 == 0 then breathe() end
    end
    A = nil
    -- (FireRed / LeafGreen: the mountains filled in between the maps (and grown past their edges) rise
    -- the deeper in they are, a level every four tiles from their foot, in terraces, up to six)
    if cur.picture then
      local dr, q = {}, {}
      for k = 1, n do
        if HIGH[cls[k]] then dr[k] = false else dr[k] = 0 q[#q + 1] = k end
      end
      local qh = 1
      while q[qh] do
        local k = q[qh]
        qh = qh + 1
        local d = dr[k] + 1
        local x = (k - 1) % cols
        for dd = 1, 4 do
          local nk = dd == 1 and k - 1 or dd == 2 and k + 1 or dd == 3 and k - cols or k + cols
          local ok = nk >= 1 and nk <= n and (dd > 2 or ((dd == 1 and x > 0) or (dd == 2 and x < cols - 1)))
          if ok and not dr[nk] then dr[nk] = d q[#q + 1] = nk end
        end
        if qh % 40000 == 0 then breathe() end
      end
      q = nil
      for k = 1, n do
        if filled[k] and HIGH[cls[k]] then
          local x, y = (k - 1) % cols + world.x0, floor((k - 1) / cols) + world.y0
          local rise = min(6, floor((dr[k] or 0) / (3.4 + 1.2 * vnoise(x, y, 20))))
          if rise > M[k] then M[k] = rise end
        end
      end
    end
    -- (5b. the great mountains (Mt. Chimney, Mt. Pyre, Mt. Ember): a broad round base (its edge
    -- wandering in smooth noise) climbing to the summit in whole levels. What nothing walks on there
    -- (rock, forest, the land filled in) rises to it; a walkable area in its reach rises too: a town
    -- whole and flat, to the lowest the mountain is under it, a path climbing with it a level under the
    -- rock round it; the summit stays on top)
    local function centreOf(summit)
      local sx, sy, sn = 0, 0, 0
      for k = 1, n do
        if reg[k] == summit then sx, sy, sn = sx + (k - 1) % cols, sy + floor((k - 1) / cols), sn + 1 end
      end
      if sn == 0 then return nil end
      return sx / sn, sy / sn, sqrt(sn / math.pi)
    end
    -- (low: the rock past the cone's foot stays down, a shelf round the mountain, not its old level)
    local function mountain(sumL, cx, cy, r0, base, summit, low)
      local function coneAt(k)
        local x, y = (k - 1) % cols, floor((k - 1) / cols)
        local d = sqrt((x - cx) ^ 2 + (y - cy) ^ 2) - r0
        if d <= 0 then return sumL end
        d = d / (0.8 + 0.4 * vnoise(x + world.x0, y + world.y0, 24))
        if d >= base then return 0 end
        return sumL * (1 - d / base) ^ 1.25
      end
      local x0r, x1r = max(0, floor(cx - r0 - base * 1.3)), min(cols - 1, floor(cx + r0 + base * 1.3))
      local y0r, y1r = max(0, floor(cy - r0 - base * 1.3)), min(rows - 1, floor(cy + r0 + base * 1.3))
      -- (a town: its map a town's or a city's)
      local function town(r)
        local m = list[rinfo[r].map or 0]
        local mt = m and tonumber(m.def.mapType)
        return mt == 1 or mt == 2
      end
      local townLow = {}
      for y = y0r, y1r do
        for x = x0r, x1r do
          local k = y * cols + x + 1
          local r = reg[k]
          if r > 0 and r ~= summit and town(r) then
            local c = coneAt(k)
            local m = townLow[r]
            if not m or c < m then townLow[r] = c end
          end
        end
      end
      for r, c in pairs(townLow) do
        local cl = floor(c)
        if cl > level[r] then level[r] = cl end
      end
      -- (inside the base the mountain is the height: rock on it, the ground a level under it (paths,
      -- routes, and the trees on them: they stand on the ground, not on pillars), a town flat at its
      -- own, the summit on top)
      for y = y0r, y1r do
        for x = x0r, x1r do
          local k = y * cols + x + 1
          if not sea(k) then
            local c = coneAt(k)
            if c > 0.5 then
              local r = reg[k]
              local cl = floor(c + 0.5)
              if r == summit then
                M[k] = level[r]
              elseif r > 0 and town(r) then
                M[k] = level[r]
              elseif r > 0 or not HIGH[cls[k]] then
                -- (a path, and the trees, walls and fences by it: on the ground, a level under the rock)
                M[k] = max(0, cl - 1)
              else
                M[k] = cl
              end
            elseif low and HIGH[cls[k]] and M[k] > 1 then
              M[k] = 1
            end
          end
        end
        if y % 32 == 0 then breathe() end
      end
    end
    if pyre then
      local cx, cy, r0 = centreOf(pyre)
      if cx then mountain(level[pyre], cx, cy, r0, 44, pyre) end
    end
    if chim then
      local cx, cy, r0 = centreOf(chim)
      if cx then mountain(level[chim], cx, cy, r0, 96, chim) end
    end
    -- (Mt. Ember's summit (the Sevii Islands) is up its door to the top: the highest ground there is)
    for _, d in ipairs(world.doors or {}) do
      if tostring(d.dest):find("MT_EMBER_SUMMIT$") then
        local ex, ey = d.x - world.x0, d.y - world.y0
        mountain(top + 3, ex + 0.5, ey + 1, 2.5, 52, nil, true)
        world.ember = { x = d.x, y = d.y }
        break
      end
    end
    -- (the land grown out past a map's edge into the sea (FireRed / LeafGreen): down to the shore in
    -- terraces, a level for every tile and a third from the water; a mountain's slope too)
    local grown = world.grown
    if grown and next(grown) then
      local sd, q = {}, {}
      for k = 1, n do
        if sea(k) then sd[k] = 0 q[#q + 1] = k else sd[k] = false end
      end
      local qh = 1
      while q[qh] do
        local k = q[qh]
        qh = qh + 1
        local d = sd[k] + 1
        if d <= 40 then
          local x = (k - 1) % cols
          for dd = 1, 4 do
            local nk = dd == 1 and k - 1 or dd == 2 and k + 1 or dd == 3 and k - cols or k + cols
            local ok = nk >= 1 and nk <= n and (dd > 2 or ((dd == 1 and x > 0) or (dd == 2 and x < cols - 1)))
            if ok and not sd[nk] then sd[nk] = d q[#q + 1] = nk end
          end
        end
        if qh % 40000 == 0 then breathe() end
      end
      for k = 1, n do
        if grown[k] and sd[k] then M[k] = min(M[k], floor((sd[k] - 1) * 0.75)) end
      end
    end
    -- (6. the heights, the water's surfaces: a lake up in the hills just under the land round it, the
    -- sea's 0)
    local h, ws = {}, {}
    for k = 1, n do
      local c = cls[k]
      local l = M[k]
      if wetC(c) then
        if not sea(k) and l > 0 then
          ws[k] = H.GROUND + l * H.LEVEL - 0.02
          h[k] = ws[k] - H.POND_DEPTH
        else
          ws[k] = 0
          h[k] = c == C.SHALLOW and H.SHALLOW_BED or H.SEA_BED
        end
      else
        ws[k] = false
        h[k] = H.GROUND + l * H.LEVEL
      end
      if k % 40000 == 0 then breathe() end
    end
    -- (7. bridges and logs: over water, the water's bed and surface under a deck; over land a deck
    -- over it (Fortree's over the trees))
    local deck = {}
    local bkind = world.bkind or {}
    for k = 1, n do
      local c = cls[k]
      if c == C.BRIDGE or c == C.LOG then
        local x = (k - 1) % cols
        local wk
        for d = 1, 4 do
          local nk = d == 1 and k - 1 or d == 2 and k + 1 or d == 3 and k - cols or k + cols
          local ok = nk >= 1 and nk <= n and (d > 2 or ((d == 1 and x > 0) or (d == 2 and x < cols - 1)))
          if ok and ws[nk] then wk = nk break end
        end
        local kind = bkind[k]
        if wk then
          ws[k], h[k] = ws[wk], h[wk]
          local lift = kind == "high" and 2 or (kind == "med" and 1 or 0)
          deck[k] = ws[k] + (c == C.LOG and H.LOG or H.DECK + lift * H.DECK_LEVEL)
        else
          deck[k] = h[k] + (kind == "tree" and H.TREE + 0.02 or H.BRIDGE_LAND)
        end
      end
    end
    world.h, world.ws, world.deck = h, ws, deck
  end

  -- the region's outline for the model and the scene: its box in world units and a coarse terrain
  -- (every 4 tiles: the highest ground in each block, its colour, sea or land) for heights at a point,
  -- the cursor and the flat fallback
  function Wd.terrain(world, p)
    pace = p
    local S = 4
    local cols, rows = math.ceil(world.cols / S), math.ceil(world.rows / S)
    local t = { cols = cols, rows = rows, h = {}, kind = {}, r = {}, g = {}, b = {}, peak = {}, town = {} }
    for j = 0, rows - 1 do
      for i = 0, cols - 1 do
        local top, land, r, g, b, n = H.SEA, 0, 0, 0, 0, 0
        for y = j * S, min(world.rows - 1, j * S + S - 1) do
          for x = i * S, min(world.cols - 1, i * S + S - 1) do
            local k = y * world.cols + x + 1
            local hk = world.h[k]
            if hk > top then top = hk end
            if hk > 0 then land = land + 1 end
            local cr, cg, cb = world.art(k, 0)
            if cr then r, g, b, n = r + cr, g + cg, b + cb, n + 1 end
          end
        end
        local q = j * cols + i + 1
        if q % 2000 == 0 then breathe() end
        t.h[q] = top
        t.kind[q] = land > 0 and "land" or "sea"
        t.peak[q] = 0
        if n > 0 then
          t.r[q], t.g[q], t.b[q] = r / n / 255, g / n / 255, b / n / 255
        else
          t.r[q], t.g[q], t.b[q] = 0.16, 0.3, 0.62
        end
      end
    end
    pace = nil
    return t, S / MT
  end

  -- what the regions are built from, as a short string: a hash of every outdoor map's name, size,
  -- section, tileset, connections, doors and tiles. A built map kept on disk is used again only while
  -- it's the same (another cart, a mod changing the maps: built afresh). p: the pacing, as Wd.build's
  function Wd.fingerprint(p)
    local all = maps()
    if type(all) ~= "table" then return nil end
    pace = p
    local ids, n = {}, 0
    for id, def in pairs(all) do
      if type(id) == "string" and outdoor(id, def) then ids[#ids + 1] = id end
      n = n + 1
      if n % 4 == 0 then breathe() end
    end
    table.sort(ids)
    breathe()
    local A, B = 0, 0
    local function add(v)
      A = (A * 31 + v) % 2147483629
      B = (B * 37 + v) % 2147483587
    end
    local sbyte = string.byte
    local function addS(s)
      s = tostring(s)
      for i = 1, #s do add(sbyte(s, i)) end
      add(0)
    end
    for _, id in ipairs(ids) do
      local def = all[id]
      local L = def.midLayout
      local w, h = sizeOf(def)
      addS(id)
      add(w)
      add(h)
      add(tonumber(def.regionMapSectionId) or 0)
      add(tonumber(def.mapType) or 0)
      addS(def.pair or L.pair or "")
      for _, c in ipairs(type(def.connections) == "table" and def.connections or {}) do
        addS(c.dir or c.direction or "")
        addS(c.map or "")
        add((tonumber(c.offset) or 0) + 65536)
      end
      for _, wp in ipairs(type(def.warps) == "table" and def.warps or {}) do
        add(tonumber(wp.x) or 0)
        add(tonumber(wp.y) or 0)
        addS(wp.destMap or "")
      end
      for cy = 0, h - 1 do
        for cx = 0, w - 1 do
          add((tonumber(L:midAt(cx, cy)) or 0) % 65536 * 4096 + (tonumber(L:collAt(cx, cy)) or 0) % 256 * 16
            + (tonumber(L:elevAt(cx, cy)) or 0) % 16)
        end
        if cy % 8 == 7 then breathe() end
      end
      breathe()
    end
    pace = nil
    return ("%d-%08x%08x"):format(#ids, A, B)
  end

  function Wd.build(opts)
    opts = opts or {}
    pace, logf = opts.pace, opts.log
    -- (how far along, 0..1, for the map's loading bar)
    local prog = opts.progress or function() end
    local all = maps()
    local layout = Wd.place(all, opts.region)
    if not layout then pace, logf = nil, nil return nil end
    prog(0.08)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, m in ipairs(layout.list) do
      x0, y0 = min(x0, m.x), min(y0, m.y)
      x1, y1 = max(x1, m.x + m.w), max(y1, m.y + m.h)
    end
    local PAD = 24
    x0, y0, x1, y1 = x0 - PAD, y0 - PAD, x1 + PAD, y1 + PAD
    local cols, rows = x1 - x0, y1 - y0
    local world = { maps = layout.list, byId = layout.byId, x0 = x0, y0 = y0, cols = cols, rows = rows,
                    cls = {}, mid = {}, pix = {}, elev = {}, mapIx = {}, doors = {}, pairs = {}, fit = layout.fit }
    local cls, midA, pixA, elevA, mapA = world.cls, world.mid, world.pix, world.elev, world.mapIx
    -- (each filled in order first: a plain array of numbers, not a hash table, light on the collector)
    for k = 1, cols * rows do
      cls[k], midA[k], pixA[k], elevA[k], mapA[k] = false, 0, 0, 0, false
      if k % 50000 == 0 then breathe() end
    end
    local pairIx = {}
    -- (behaviour ids -> classes, once)
    local behClass, bkindOf = {}, {}
    for name, c in pairs(BEH) do
      local id = MB.id(name)
      if id then behClass[id] = c end
    end
    for name, kd in pairs(BRIDGE_KIND) do
      local id = MB.id(name)
      if id then bkindOf[id] = kd end
    end
    world.bkind = {}
    local InteractionScripts = engine("src.core.game3.scripting.interaction_scripts")
    for mi, m in ipairs(layout.list) do
      local def, L = m.def, m.def.midLayout
      local pair = def.pair or L.pair
      local pi = pairIx[pair]
      if not pi then
        pi = #world.pairs + 1
        pairIx[pair] = pi
        world.pairs[pi] = { name = pair, art = readArt(pair) or {} }
      end
      prog(0.08 + 0.5 * mi / #layout.list)
      local art = world.pairs[pi].art
      local behaviors = InteractionScripts and InteractionScripts.behaviors and InteractionScripts.behaviors[pair] or {}
      local crop = m.crop
      for cy = 0, m.h - 1 do
        local row = (m.y + cy - y0) * cols + (m.x - x0) + 1
        for cx = 0, m.w - 1 do
          local coll = L:collAt(cx, cy)
          if coll ~= 255 and not (crop and crop[cy * m.w + cx]) then
            local k = row + cx
            local mid = L:midAt(cx, cy)
            local beh = behaviors[mid] or -1
            local c = behClass[beh]
            if c == C.BRIDGE then world.bkind[row + cx] = bkindOf[beh] end
            if not c then
              if coll == 41 then c = C.SEA
              elseif coll == 24 then c = C.TALL
              elseif coll == 113 then c = C.DOOR
              elseif coll == 160 then c = C.LEDGE_E
              elseif coll == 161 then c = C.LEDGE_W
              elseif coll == 162 then c = C.LEDGE_N
              elseif coll == 163 then c = C.LEDGE_S
              elseif coll == 7 or coll == 130 then c = wallClass(art[mid])
              else c = C.GROUND end
            end
            cls[k], midA[k], pixA[k], elevA[k], mapA[k] = c, mid, pi, L:elevAt(cx, cy), mi
          end
        end
      end
      breathe()
    end
    -- (FireRed / LeafGreen's bridges are plain ground over the water: a strip of ground at most three
    -- tiles across with water on both sides, not grassy, is a bridge, its deck over the water)
    if cur.picture then
      local nn = cols * rows
      local function wet(k) local c = cls[k] return c == C.SEA or c == C.POND or c == C.SHALLOW or c == C.CURRENT end
      local function walk(k) local c = cls[k] return c == C.GROUND or c == C.SAND end
      local function inside(k, step)
        local nk = k + step
        if nk < 1 or nk > nn then return false end
        if step == 1 or step == -1 then return floor((nk - 1) / cols) == floor((k - 1) / cols) end
        return true
      end
      local function strip(k, step)
        local a, b, w = k, k, 1
        while w <= 3 and inside(a, -step) and walk(a - step) do a, w = a - step, w + 1 end
        while w <= 3 and inside(b, step) and walk(b + step) do b, w = b + step, w + 1 end
        return w <= 3 and inside(a, -step) and inside(b, step) and wet(a - step) and wet(b + step)
      end
      local deckAt = {}
      for k = 1, nn do
        if walk(k) and (strip(k, cols) or strip(k, 1)) then
          local p = world.pairs[pixA[k]]
          local a = p and p.art[midA[k]]
          if not a or a.green < 0.3 then deckAt[#deckAt + 1] = k end
        end
        if k % 40000 == 0 then breathe() end
      end
      for _, k in ipairs(deckAt) do
        cls[k] = C.BRIDGE
        world.bkind[k] = "low"
      end
    end
    -- (the gaps between maps: what the game shows past a map's edge, its border, from the nearest map;
    -- all of a gap the maps close in, the open sea's side only so far out)
    -- (from the maps joined to the mainland and those its doors lead to; the islands the Town Map put
    -- out at sea are islands of their own; the distance in whole steps any way, diagonals too)
    local REACH = 20
    local n = cols * rows
    local dist, queue = {}, {}
    for k = 1, n do dist[k] = false end
    for k = 1, n do
      if cls[k] then
        local m = layout.list[mapA[k]]
        -- (the maps a door or a gatehouse put there fill round themselves too: Mt. Chimney ringed by
        -- its own mountain; the islands the Town Map put out at sea don't)
        local seeds = m.how ~= "townmap"
        dist[k] = seeds and 0 or -1
        if seeds then queue[#queue + 1] = k end
      end
    end
    local qh = 1
    while queue[qh] do
      local k = queue[qh]
      qh = qh + 1
      local x = (k - 1) % cols
      local d = dist[k] + 1
      local src = mapA[k]
      for dy = -1, 1 do
        local row = k + dy * cols
        if row >= 1 and row <= n then
          for dx = -1, 1 do
            local nk = row + dx
            if (dx ~= 0 or dy ~= 0) and x + dx >= 0 and x + dx < cols and not dist[nk] then
              dist[nk], mapA[nk] = d, src
              queue[#queue + 1] = nk
            end
          end
        end
      end
      if qh % 20000 == 0 then breathe() end
    end
    queue = nil
    local outer, stack = {}, {}
    for k = 1, n do outer[k] = false end
    local function seed(k) if not cls[k] and not outer[k] then outer[k] = true stack[#stack + 1] = k end end
    for x = 1, cols do seed(x) seed(n - cols + x) end
    for y = 0, rows - 1 do seed(y * cols + 1) seed(y * cols + cols) end
    local steps = 0
    while #stack > 0 do
      local k = table.remove(stack)
      local x = (k - 1) % cols
      if x > 0 then seed(k - 1) end
      if x < cols - 1 then seed(k + 1) end
      if k > cols then seed(k - cols) end
      if k + cols <= n then seed(k + cols) end
      steps = steps + 1
      if steps % 20000 == 0 then breathe() end
    end
    world.filled = {}
    for k = 1, n do world.filled[k] = false end
    -- (which map's border a filled tile takes: the nearest map's, looked up a little way off, the way
    -- wandering in smooth noise, so where two kinds of border meet it winds instead of running straight)
    local WARP = 12
    local srcW = {}
    for k = 1, n do
      local src = mapA[k]
      if not cls[k] and src then
        local gx, gy = (k - 1) % cols, floor((k - 1) / cols)
        local wx = floor(gx + (vnoise(gx + x0, gy + y0, 18) - 0.5) * 2 * WARP + 0.5)
        local wy = floor(gy + (vnoise(gx + x0 + 57, gy + y0 + 113, 18) - 0.5) * 2 * WARP + 0.5)
        if wx >= 0 and wy >= 0 and wx < cols and wy < rows then
          local wk = wy * cols + wx + 1
          if not cls[wk] and mapA[wk] then src = mapA[wk] end
        end
      end
      srcW[k] = src or false
      if k % 40000 == 0 then breathe() end
    end
    for k = 1, n do
      local reach = REACH
      if outer[k] then
        local gx, gy = (k - 1) % cols + x0, floor((k - 1) / cols) + y0
        reach = 3 + REACH * (0.62 * vnoise(gx, gy, 15) + 0.38 * vnoise(gx + 91, gy + 37, 6))
      end
      if not cls[k] and dist[k] and dist[k] > 0 and (not outer[k] or dist[k] <= reach) then
        local mi = srcW[k]
        mapA[k] = mi
        local m = layout.list[mi]
        local L = m.def.midLayout
        local gx, gy = (k - 1) % cols + x0, floor((k - 1) / cols) + y0
        local mid = L:midAt(gx - m.x, gy - m.y)
        local pair = m.def.pair or L.pair
        local pi = pairIx[pair]
        local a = world.pairs[pi].art[mid]
        local behaviors = InteractionScripts and InteractionScripts.behaviors and InteractionScripts.behaviors[pair] or {}
        local c = behClass[behaviors[mid] or -1]
        if not c then
          if a and a.blue >= 0.5 then c = C.SEA else c = wallClass(a) end
          if c == C.STRUCT then c = C.ROCK end
        end
        -- (mountain ground past a map's edge is the mountain itself: nobody walks it)
        if c == C.MOUNT or c == C.ROCKY then c = C.ROCK end
        cls[k], midA[k], pixA[k], elevA[k] = c, mid, pi, 0
        world.filled[k] = true
      elseif not cls[k] then
        mapA[k] = false
      end
      if k % 20000 == 0 then breathe() end
    end
    dist, outer = nil, nil
    breathe()
    prog(0.66)
    -- (FireRed / LeafGreen: land a map's edge cuts off -- an island's mountain or forest running on
    -- past where the game stops drawing -- goes on into the sea and is rounded off there: a run of land
    -- along an edge grows out a third as far as it is long (at most GROW) in a half ellipse, its outline
    -- wandering in noise; a forest's edge rows repeated out from it (its trees in step), rock the
    -- map's own commonest rock (its mountain's top, not its cliff faces). Only over the sea: never into
    -- another map, nor the forest or rock filled in between)
    world.grown = {}
    if cur.picture then
      local GROW = 14
      local grown, filled = world.grown, world.filled
      local nn = cols * rows
      local function growable(k)
        if k < 1 or k > nn then return false end
        local c = cls[k]
        return not c or (filled[k] and WATER[c] == true)
      end
      local function landClass(c)
        if not c or WATER[c] or c == C.FALL or c == C.BRIDGE or c == C.LOG then return nil end
        if c == C.TREE then return C.TREE end
        if HIGH[c] or c == C.MOUNT or c == C.STRUCT or c == C.SMALL or c == C.BUILDING or c == C.DOOR then return C.ROCK end
        if c >= C.LEDGE_E and c <= C.LEDGE_S then return C.GROUND end
        return c
      end
      for mi, m in ipairs(layout.list) do
        local mx, my = m.x - x0, m.y - y0
        -- (the map's commonest rock with rock all round it: the mountain's top, not a cliff's face)
        local rockK, seen, best = nil, {}, 0
        for cy = 1, m.h - 2 do
          local row = (my + cy) * cols + mx + 1
          for cx = 1, m.w - 2 do
            local k = row + cx
            if mapA[k] == mi and cls[k] == C.ROCK and cls[k - 1] == C.ROCK and cls[k + 1] == C.ROCK
                and cls[k - cols] == C.ROCK and cls[k + cols] == C.ROCK then
              local id = midA[k]
              local c = (seen[id] or 0) + 1
              seen[id] = c
              if c > best then best, rockK = c, k end
            end
          end
        end
        for side = 1, 4 do
          local along = side <= 2 and m.w or m.h
          local out = side == 1 and -cols or (side == 2 and cols or (side == 3 and -1 or 1))
          -- (the map's own tile at (cx, cy), world k)
          local function tileK(cx, cy) return (my + cy) * cols + mx + cx + 1 end
          local function edgeAt(i)
            if side == 1 then return i, 0 elseif side == 2 then return i, m.h - 1
            elseif side == 3 then return 0, i else return m.w - 1, i end
          end
          -- (the tile d out from the edge stands for: the edge's rows repeated, two by two)
          local function sourceAt(i, d)
            local o = d % 2
            if side == 1 then return i, o elseif side == 2 then return i, m.h - 1 - o
            elseif side == 3 then return o, i else return m.w - 1 - o, i end
          end
          local i = 0
          while i < along do
            local cx, cy = edgeAt(i)
            local k = tileK(cx, cy)
            local lc = mapA[k] == mi and not filled[k] and landClass(cls[k])
            if lc and growable(k + out) then
              local a = i
              while i + 1 < along do
                local nx, ny = edgeAt(i + 1)
                local nk = tileK(nx, ny)
                if mapA[nk] == mi and not filled[nk] and landClass(cls[nk]) and growable(nk + out) then i = i + 1 else break end
              end
              local b = i
              local L = b - a + 1
              local D = min(GROW, max(2, floor(L * 0.36 + 0.5)))
              for j = a, b do
                local ex, ey = edgeAt(j)
                local ek = tileK(ex, ey)
                local ec = landClass(cls[ek])
                local t = (j - a + 0.5) / L
                local prof = sqrt(max(0, 1 - (2 * t - 1) ^ 2))
                local gx, gy = m.x + ex, m.y + ey
                local depth = floor(D * prof * (0.7 + 0.6 * vnoise(gx, gy, 9)) + 0.5)
                for d = 1, depth do
                  local nk = ek + out * d
                  if side >= 3 and floor((nk - 1) / cols) ~= floor((ek - 1) / cols) then break end
                  if not growable(nk) then break end
                  local sx, sy = sourceAt(j, d)
                  local sk = tileK(sx, sy)
                  local from = (mapA[sk] == mi and landClass(cls[sk]) == ec) and sk or ek
                  if ec == C.ROCK and rockK then from = rockK end
                  cls[nk], midA[nk], pixA[nk], elevA[nk], mapA[nk] = ec, midA[from], pixA[from], 0, mi
                  filled[nk], grown[nk] = true, true
                end
              end
            end
            i = i + 1
          end
        end
        breathe()
      end
    end
    -- (FireRed / LeafGreen: the open sea all one water: the rough water a Sevii map rings itself with
    -- is drawn lighter than the sea past it, and would show each map's rectangle)
    if cur.picture then
      local count, bestN, bestK = {}, 0, nil
      for k = 1, cols * rows do
        if cls[k] == C.SEA then
          local key = pixA[k] * 65536 + midA[k]
          local c = (count[key] or 0) + 1
          count[key] = c
          if c > bestN then bestN, bestK = c, k end
        end
      end
      if bestK then
        local pm, mm = pixA[bestK], midA[bestK]
        for k = 1, cols * rows do
          if cls[k] == C.SEA then pixA[k], midA[k] = pm, mm end
        end
      end
      breathe()
    end
    prog(0.72)
    -- (the doors: each map's warps on its door tiles, and where they lead)
    for _, m in ipairs(layout.list) do
      for _, w in ipairs(m.warps or m.def.warps or {}) do
        local gx, gy = m.x + w.x, m.y + w.y
        local k = (gy - y0) * cols + (gx - x0) + 1
        local dest = w.destMap
        if not layout.byId[dest] then
          local dd = all[dest]
          world.doors[#world.doors + 1] = { x = gx, y = gy, map = m.id, dest = dest, kind = doorKind(dest, all),
                                            k = k, sec = dd and dd.regionMapSectionId }
        end
      end
    end
    -- (a building with two doors (a museum, the Department Store) is one building: the second door's
    -- footprint, over the first's, left off. Doors three or more tiles apart on a row are two buildings
    -- side by side (Mauville's house by its Mart): each footprint stops halfway to the other's door)
    local feet = {}
    for _, d in ipairs(world.doors) do
      if d.kind ~= "cave" and d.kind ~= "gate" then
        local lo, hi = -math.huge, math.huge
        for _, o in ipairs(world.doors) do
          if o ~= d and abs(o.y - d.y) <= 1 and abs(o.x - d.x) >= 3 and abs(o.x - d.x) <= 14 then
            local mid = floor((o.x + d.x) / 2)
            if o.x < d.x then lo = max(lo, mid + 1) else hi = min(hi, mid) end
          end
        end
        local f = footprint(world, d.x, d.y, lo, hi)
        for _, g in ipairs(feet) do
          if f then
            local ow = min(f.x1, g.x1) - max(f.x0, g.x0)
            local oh = min(f.y1, g.y1) - max(f.y0, g.y0)
            local a = min((f.x1 - f.x0) * (f.y1 - f.y0), (g.x1 - g.x0) * (g.y1 - g.y0))
            if ow > 0 and oh > 0 and ow * oh * 2 >= a then
              d.shares = g
              f = nil
            end
          end
        end
        d.foot = f
        if f then feet[#feet + 1] = f end
      end
    end
    -- (what's built and joined to no door: a fence, a sign, a lamp)
    for k = 1, cols * rows do
      if cls[k] == C.STRUCT then cls[k] = C.SMALL end
    end
    function world.art(k, q)
      local p = world.pairs[pixA[k] or 0]
      local a = p and p.art[midA[k]]
      if not a then return nil end
      local o = q * 3
      return a.q[o + 1], a.q[o + 2], a.q[o + 3]
    end
    -- a tile's own picture, 16 x 16, the top layer over the bottom: out[1..768] r, g, b (0..255) row by
    -- row (a pixel see-through in both layers the tile's mean colour) -> false without its art
    -- (pi: world.pairs' number, as world.pix holds)
    local pixOf = {}
    local sbyte = string.byte
    function world.tile(pi, mid, out)
      local P = pixOf[pi]
      if P == nil then
        local p = world.pairs[pi]
        P = p and readPixels(p.name) or false
        pixOf[pi] = P
      end
      local us = P and P.uSlot[mid]
      if not us then return false end
      local a = world.pairs[pi].art[mid]
      local mr, mg, mb = a and a.r or 0, a and a.g or 0, a and a.b or 0
      local under, over, LR, LG, LB = P.under, P.over, P.LR, P.LG, P.LB
      local ub = P.uOff + us * 256
      local os = over and P.oSlot[mid]
      local ob = os and (P.oOff + os * 256) or nil
      for off = 0, 255 do
        local p = ob and sbyte(over, ob + off) or 0
        if p == 0 then p = sbyte(under, ub + off) or 0 end
        local o = off * 3
        if p ~= 0 then
          out[o + 1], out[o + 2], out[o + 3] = LR[p], LG[p], LB[p]
        else
          out[o + 1], out[o + 2], out[o + 3] = mr, mg, mb
        end
      end
      return true
    end
    prog(0.78)
    heights(world)
    prog(0.97)
    breathe()
    -- (once its meshes are made: the per-tile arrays let go, the maps and doors kept)
    function world.release()
      world.cls, world.mid, world.pix, world.elev, world.mapIx, world.filled, world.h = nil, nil, nil, nil, nil, nil, nil
      world.ws, world.deck, world.bkind = nil, nil, nil
      world.pairs = {}
      pixOf = {}
      cls, midA, pixA, elevA, mapA = nil, nil, nil, nil, nil
      world.released = true
    end
    pace, logf = nil, nil
    return world
  end

  return Wd
end
