-- The GPS's walk graph (Ruby / Sapphire / Emerald, FireRed / LeafGreen): every map a player can walk
-- through, read from the game's own maps (their tiles' collision, behaviours and elevations, their
-- warps and connections), made into points ("nodes") joined by how many steps lie between them.
--   arrival  where a player stands after coming in: on a warp's tile, or at a connection's landing
--   exit     where a player leaves: a warp's tile that fires (a door, a ladder, a hole, stairs) or the
--            middle of a run of tiles along a connected edge (a run at most RUN tiles long)
-- Each arrival is joined to each exit of its map it can walk to (on foot, and with Surf; each without the
-- field moves' obstacles and through them, with the HMs that path needed), each exit to the arrival it
-- leads to (one step). Houses with one way in and out are left out (no one walks through them). Ledges
-- are one way; one-way walls and elevations (bridges) are kept as the game moves a player
-- (src/core/game3/collision.lua). Cut trees, Rock Smash rocks and Strength boulders (objects in these
-- games, not tiles) are walls unless the walk may use that HM. Boats and Emerald's cracked floors are
-- scripts, not warps: not in it.
--
--   Gw = graph(engine, deps)  deps: maps() -> the game's map definitions ; game() -> the game (warps'
--                             destinations) ; cache (mod.cache) ; gameId() ; version ; engine (its
--                             version) ; log(fmt, ...)
--   Gw.prepare() ; Gw.step(budget) -> true while there's more ; Gw.ready() ; Gw.progress() -> 0..1
--   Gw.tiles(mapId) -> rec { id, def, w, h, cls, elev, ledge, wall, warp } (kept for the last few)
--   Gw.walk(rec, x, y, surfing, allowSurf, reach(i, d, hm) -> stop?, maxD, parents, hms) -> the tiles' steps
--       (hms: the HMs it may use, Gw.HM_CUT 1 + Gw.HM_SMASH 2 + Gw.HM_STRENGTH 4; hm: those its way there used)
--   Gw.pathTo(rec, i) -> the tile indices from the walk's start to i (after a walk with parents)
--   Gw.mi[mapId] ; Gw.ids[mi] ; nodes NM / NX / NY / NK (1 warp exit, 2 edge exit, 3 arrival) ;
--   edges EA -> EB, EL (on foot, -1 none) / ES (with Surf), EHL / EHS (through obstacles) and EML / EMS (the
--   HMs that took) ; Gw.into[node] = { edge, ... } ;
--   Gw.exits[mi] = { node, ... } ; Gw.arrivals[mi] = { node, ... } ; Gw.node(mi, x, y, k) -> node | nil
--   Gw.arrivalAt(mapId, x, y) -> node | nil

local floor, max, min = math.floor, math.max, math.min

local FORMAT = 2
local RUN = 12            -- a connected edge's run of tiles: one exit each this many
local OBSTACLE = 2        -- the steps a cut tree, a boulder or a rock costs with its HM (a little: round it if as near)
local HM_CUT, HM_SMASH, HM_STRENGTH = 1, 2, 4
local HM_ALL = 7
-- (two HM masks together: a | b, for 0..7)
local OR = {}
for a = 0, 7 do
  for b = 0, 7 do
    local r = 0
    for _, bit in ipairs({ 1, 2, 4 }) do
      if math.floor(a / bit) % 2 == 1 or math.floor(b / bit) % 2 == 1 then r = r + bit end
    end
    OR[a * 8 + b] = r
  end
end
local KEEP_TILES = 6      -- maps' tiles kept at once
-- maps never walked through: under the sea, unused, the link rooms, secret bases
local SKIP = { "UNDERWATER", "PROTOTYPE", "SECRET_BASE", "UNION_ROOM", "TRADE_CENTER", "RECORD_CORNER",
               "BATTLE_COLOSSEUM", "INSIDE_OF_TRUCK" }
-- the four ways: up, down, left, right
local DX, DY = { 0, 0, -1, 1 }, { -1, 1, 0, 0 }
local DIR_NAME = { "up", "down", "left", "right" }
local CONN_DIR = { north = 1, south = 2, west = 3, east = 4 }
-- one-way walls: a tile's behaviour blocks leaving it, or coming into it (north 1, south 2, west 4, east 8)
local LEAVE, ENTER = { 1, 2, 4, 8 }, { 2, 1, 8, 4 }
local HOP = { 1, 2, 4, 8 }   -- a ledge's facings (up, down, left, right)
-- the rides a script makes, not a warp (both ways; the maps' names end so): Mt. Chimney's cable car
local LINKS = { { "ROUTE112_CABLE_CAR_STATION", "MT_CHIMNEY_CABLE_CAR_STATION", 12 } }
local function linked(id)
  for _, l in ipairs(LINKS) do
    if id:sub(-#l[1]) == l[1] or id:sub(-#l[2]) == l[2] then return true end
  end
  return false
end
-- tiles' classes
local WALL, LAND, WATER, LEDGE, WARP = 0, 1, 2, 3, 4
local SURF = 16              -- a walk's state: tile * 17 + the elevation it's at (0..15), or 16 surfing

-- a ledge's collision (0xA0-0xA7, its low three bits) -> the ways it's hopped (up 1, down 2, left 4, right 8)
local LEDGE_HOPS = { [0] = 8, 4, 1, 2, 2 + 8, 2 + 4, 1 + 8, 1 + 4 }

local function has(m, b) return m ~= nil and m ~= 0 and floor(m / b) % 2 == 1 end

return function(engine, deps)
  deps = deps or {}
  local Gw = { RUN = RUN, WALL = WALL, LAND = LAND, WATER = WATER, LEDGE = LEDGE, WARP = WARP, DX = DX, DY = DY,
               HM_CUT = HM_CUT, HM_SMASH = HM_SMASH, HM_STRENGTH = HM_STRENGTH, HM_ALL = HM_ALL }
  function Gw.covers(have, need) return OR[(have or 0) * 8 + (need or 0)] == (have or 0) end
  local function log(...) if deps.log then deps.log(...) end end
  local function maps() return deps.maps and deps.maps() or nil end

  local Collision, Conn, P, IS, Catalog
  local function mods()
    Collision = Collision or engine("src.core.game3.collision")
    Conn = Conn or engine("src.core.game3.connections")
    -- (the collision bytes' meaning: the engine's own, the module every generation may read)
    P = P or engine("src.core.CollPermissions")
    IS = IS or engine("src.core.game3.scripting.interaction_scripts")
    Catalog = Catalog or engine("src.import.gba.map_catalog")
    return Collision and Conn and P
  end

  -- (the build: a slice of the frame at a time; only ever inside its own coroutine)
  local state = { ready = false, job = nil, progress = 0, failed = false }
  local slice = { start = 0, budget = 0.004 }
  local function clock() return love and love.timer and love.timer.getTime() or os.clock() end
  local function breathe()
    local co = state.job
    if co and coroutine.running() == co and clock() - slice.start > slice.budget then coroutine.yield() end
  end

  -- ------- a map's layout: the engine's when it's loaded it; else read here, not kept (the engine keeps
  -- every layout it loads: the build would have kept them all, some 30 MB)

  local manifest
  local private, privateOrder = {}, {}
  local function readLayout(id, def)
    local Ds, Ex = engine("src.core.game3.dataset"), engine("src.import.gba.extract_island1")
    local NP, LN = engine("src.import.gba.native_pack"), engine("src.core.game3.layout_native")
    if not (Ds and Ex and NP and LN and Ds.cache) then return nil end
    local cache = Ds.cache()
    local root = Ex.NATIVE_ROOT or ((Ex.CACHE_ROOT or "") .. "/native")
    if manifest == nil then
      manifest = false
      local okR, src = pcall(cache.read, cache, root .. "/manifest.lua")
      local chunk = okR and type(src) == "string" and load(src, "@manifest", "t", {})
      local okC, got = false, nil
      if chunk then okC, got = pcall(chunk) end
      if okC and type(got) == "table" then manifest = got.layouts or {} end
    end
    local info = manifest and manifest[id]
    local okB, blob = pcall(cache.read, cache, root .. "/" .. ((info and info.file) or ("layouts/" .. id .. ".mid")))
    if not (okB and type(blob) == "string" and #blob >= 16 and blob:sub(1, 4) == NP.MAGIC_MID) then return nil end
    local okD, decoded = pcall(NP.decodeMidLayout, blob)
    if not (okD and decoded) then return nil end
    local okL, L = pcall(LN.fromDecoded, decoded, id, (info and info.pair) or def.pair, blob)
    return okL and L or nil
  end
  -- -> the layout, and the map as collision.lua's functions read it (a stand-in round a layout of our own)
  local function layoutOf(id, def)
    local L = rawget(def, "midLayout")
    if L then return L, def end
    if rawget(def, "modLayout") then
      L = def.midLayout
      return L, def
    end
    local got = private[id]
    if not got then
      local own = readLayout(id, def)
      if not own then
        L = def.midLayout
        return L, def
      end
      got = { own, { midLayout = own, pair = def.pair or own.pair, width = def.width, height = def.height } }
      private[id] = got
      privateOrder[#privateOrder + 1] = id
      while #privateOrder > KEEP_TILES do private[table.remove(privateOrder, 1)] = nil end
    end
    return got[1], got[2]
  end
  Gw.layoutOf = layoutOf

  -- ------- a map's tiles

  local function classify(def, L, behs, x, y)
    local coll = L:collAt(x, y)
    local b = behs and behs[L:midAt(x, y)]
    local c, ledge = WALL, 0
    if P.isLedge(coll) then
      c = LEDGE
      ledge = LEDGE_HOPS[coll % 8] or 0
    elseif P.isWalkable(coll) then
      c = LAND
    elseif Collision.isWaterOn(def, x, y, coll) and not Collision.isWaterfall(b) then
      c = WATER
    end
    local wall = 0
    if b then
      wall = (Collision.isNorthBlocked(b) and 1 or 0) + (Collision.isSouthBlocked(b) and 2 or 0)
        + (Collision.isWestBlocked(b) and 4 or 0) + (Collision.isEastBlocked(b) and 8 or 0)
    end
    return c, L:elevAt(x, y) or 0, ledge, wall, coll, b
  end
  -- (a warp's tile fires when the game would make it: collision.lua's installWarps)
  local function fires(coll, b)
    if coll and coll >= 0x60 and coll <= 0x7F then return true end
    if b == nil then return coll == nil or coll == 7 or coll == 0xff end
    return Collision.isWarpMetatileBehavior(b) == true
  end
  Gw.fires = function(coll, b) mods(); return fires(coll, b) end

  local kept, keptOrder = {}, {}
  local function build(id, def)
    if not def then return nil end
    local L, view = layoutOf(id, def)
    if not (L and L.width and L.height) then return nil end
    local w, h = L.width, L.height
    local behs = IS and IS.behaviors and IS.behaviors[def.pair or L.pair]
    local rec = { id = id, def = def, w = w, h = h, cls = {}, elev = {}, ledge = {}, wall = {}, warp = {}, obst = {} }
    local cls, elev, ledge, wall = rec.cls, rec.elev, rec.ledge, rec.wall
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local i = y * w + x
        local c, e, lg, wl = classify(view, L, behs, x, y)
        cls[i], elev[i] = c, e
        if lg ~= 0 then ledge[i] = lg end
        if wl ~= 0 then wall[i] = wl end
      end
      if y % 4 == 3 then breathe() end
    end
    -- (the field moves' obstacles: objects, not tiles)
    local FM = engine("src.core.game3.field_moves")
    local gfx = FM and FM.GFX_IDS
    local okG, cut, rock, boulder = pcall(function() return gfx.CUT_TREE, gfx.ROCK_SMASH_ROCK, gfx.PUSHABLE_BOULDER end)
    if okG then
      for _, o in ipairs(def.objects or {}) do
        local g = o.gfx or o.graphicsId
        local x, y = tonumber(o.x), tonumber(o.y)
        if g ~= nil and (g == cut or g == rock or g == boulder) and x and y and x >= 0 and y >= 0 and x < w and y < h then
          rec.obst[y * w + x] = g == cut and HM_CUT or (g == rock and HM_SMASH or HM_STRENGTH)
        end
      end
    end
    for wi, wp in ipairs(def.warps or {}) do
      local x, y = tonumber(wp.x), tonumber(wp.y)
      if x and y and x >= 0 and y >= 0 and x < w and y < h then
        local coll = L:collAt(x, y)
        local b = behs and behs[L:midAt(x, y)]
        if fires(coll, b) then
          cls[y * w + x] = WARP
          rec.warp[y * w + x] = wi
        end
      end
    end
    return rec
  end
  function Gw.tiles(id)
    local r = kept[id]
    if r then return r end
    if not mods() then return nil end
    local all = maps()
    local def = all and all[id]
    if not def then return nil end
    local ok, made = pcall(build, id, def)
    if not (ok and made) then
      if not ok then log("the GPS couldn't read %s: %s", tostring(id), tostring(made)) end
      return nil
    end
    kept[id] = made
    keptOrder[#keptOrder + 1] = id
    while #keptOrder > KEEP_TILES do
      kept[table.remove(keptOrder, 1)] = nil
    end
    return made
  end
  function Gw.forgetTiles()
    for k in pairs(kept) do kept[k] = nil end
    for i = #keptOrder, 1, -1 do keptOrder[i] = nil end
    for k in pairs(private) do private[k] = nil end
    for i = #privateOrder, 1, -1 do privateOrder[i] = nil end
  end

  -- ------- a walk over one map: breadth first, from a tile, as the player moves

  -- (one step: the tile it lands on, the elevation after, its cost -- or nil)
  local function move(rec, i, e, dir, allowSurf)
    local w = rec.w
    local x = i % w
    local y = (i - x) / w
    local nx, ny = x + DX[dir], y + DY[dir]
    if nx < 0 or ny < 0 or nx >= w or ny >= rec.h then return nil end
    local wall = rec.wall
    if has(wall[i], LEAVE[dir]) then return nil end
    local j = ny * w + nx
    if has(wall[j], ENTER[dir]) then return nil end
    local c = rec.cls[j]
    local surf = e == SURF
    if c == WARP then return j, e, 1 end
    if c == WATER then
      if surf or allowSurf then return j, SURF, 1 end
      return nil
    end
    local elev = rec.elev
    if c == LAND then
      local te = elev[j]
      if surf then
        -- (getting off: onto land at its own height, or the game's usual 3)
        if te ~= 0 and te ~= 15 and te ~= 3 and te ~= 1 then return nil end
        return j, (te == 0 or te == 15) and 3 or te, 1
      end
      if e ~= 0 and te ~= 0 and te ~= 15 and te ~= e then return nil end
      if te == 15 or elev[i] == 15 then return j, e, 1 end
      return j, te, 1
    end
    if c == LEDGE and not surf and has(rec.ledge[j], HOP[dir]) then
      local lx, ly = nx + DX[dir], ny + DY[dir]
      if lx < 0 or ly < 0 or lx >= w or ly >= rec.h then return nil end
      local k = ly * w + lx
      local ck = rec.cls[k]
      if ck == LAND then
        local te = elev[k]
        return k, te == 15 and e or te, 2
      end
      if ck == WARP then return k, e, 2 end
    end
    return nil
  end
  Gw.move = move

  -- (the walk's tables, used again each time; a queue of buckets, one per number of steps: the steps
  -- aren't all one -- a ledge's hop is two, an obstacle more)
  -- (a state's steps, parent and HMs are this walk's while its stamp is this walk's number: nothing cleared,
  -- no table grown again walk after walk)
  local B, D, PAR, MK, DG, TG = {}, {}, {}, {}, {}, {}
  local gen = 0
  local function reset() gen = gen + 1 end
  local lastParents = false
  -- (the state a player starts in on a tile)
  function Gw.startState(rec, i, surfing)
    if surfing or rec.cls[i] == WATER then return SURF end
    local e = rec.elev[i] or 0
    return e == 15 and 0 or e
  end
  -- reach(i, d) for each tile the first time it's reached, nearest first (true: stop); the start at 0
  function Gw.walk(rec, x, y, surfing, allowSurf, reach, maxD, parents, hms)
    reset()
    hms = hms or 0
    lastParents = parents and true or false
    if x < 0 or y < 0 or x >= rec.w or y >= rec.h then return end
    local i0 = y * rec.w + x
    local s0 = i0 * 17 + Gw.startState(rec, i0, surfing)
    if s0 % 17 == SURF and not (surfing or allowSurf) then return end
    local g = gen
    D[s0], MK[s0], PAR[s0], DG[s0] = 0, 0, false, g
    local pending = 1
    B[0] = B[0] or {}
    B[0][1] = s0
    local cls, obst = rec.cls, rec.obst
    local d, top = 0, 0
    local stop = false
    while pending > 0 and not stop do
      if maxD and d >= maxD then break end
      local b = B[d]
      if b then
        local k = 1
        while b[k] do
          local s = b[k]
          b[k] = nil
          k = k + 1
          pending = pending - 1
          -- (the build's long walks: a breath now and then; only ever inside the build's own coroutine)
          if pending % 256 == 0 then breathe() end
          if not stop and D[s] == d then
            local e = s % 17
            local i = (s - e) / 17
            if TG[i] ~= g then
              TG[i] = g
              if reach and reach(i, d, MK[s]) then stop = true end
            end
            -- (a warp that fires: the walk ends on it, unless it started there)
            if not stop and not (cls[i] == WARP and d > 0) then
              for dir = 1, 4 do
                local j, ne, cost = move(rec, i, e, dir, allowSurf)
                local need = j and obst[j]
                -- (a field move's obstacle: a wall without its HM)
                if need and OR[hms * 8 + need] ~= hms then j = nil end
                if j then
                  local mk = MK[s]
                  if need then
                    cost = cost + OBSTACLE
                    mk = OR[mk * 8 + need]
                  end
                  local ns, nd = j * 17 + ne, d + cost
                  local seen = DG[ns] == g
                  if not seen or nd < D[ns] then
                    D[ns], DG[ns] = nd, g
                    MK[ns] = mk
                    PAR[ns] = parents and s or false
                    local nb = B[nd]
                    if not nb then
                      nb = {}
                      B[nd] = nb
                    end
                    nb[#nb + 1] = ns
                    pending = pending + 1
                    if nd > top then top = nd end
                  end
                end
              end
            end
          end
        end
      end
      d = d + 1
    end
    -- (what's left queued: cleared for the next walk)
    for dd = d, top do
      local b = B[dd]
      if b then for k = #b, 1, -1 do b[k] = nil end end
    end
  end
  -- the tiles from the last walk's start to tile i (that walk kept its parents), as a list of indices
  function Gw.pathTo(i, out)
    out = out or {}
    for k = #out, 1, -1 do out[k] = nil end
    if not lastParents then return out end
    -- (the state that reached it first: the smallest steps)
    local best, bd
    for e = 0, 16 do
      local s = i * 17 + e
      if DG[s] == gen and (not bd or D[s] < bd) then best, bd = s, D[s] end
    end
    local n = 0
    local s = best
    while s and n < 100000 do
      n = n + 1
      out[n] = (s - s % 17) / 17
      s = PAR[s]
    end
    -- (reversed: from the start)
    for a = 1, floor(n / 2) do out[a], out[n - a + 1] = out[n - a + 1], out[a] end
    return out
  end

  -- ------- the graph

  local NM, NX, NY, NK = {}, {}, {}, {}
  local EA, EB, EL, ES, EHL, EHS, EML, EMS = {}, {}, {}, {}, {}, {}, {}, {}
  Gw.NM, Gw.NX, Gw.NY, Gw.NK = NM, NX, NY, NK
  Gw.EA, Gw.EB, Gw.EL, Gw.ES = EA, EB, EL, ES
  Gw.EHL, Gw.EHS, Gw.EML, Gw.EMS = EHL, EHS, EML, EMS
  Gw.mi, Gw.ids, Gw.into, Gw.exits, Gw.arrivals = {}, {}, {}, {}, {}
  local nodeIx = {}
  local nNodes, nEdges = 0, 0
  local function key(mi, x, y, k) return ((mi * 1024 + y) * 1024 + x) * 4 + k end
  local function newNode(mi, x, y, k)
    local kk = key(mi, x, y, k)
    local n = nodeIx[kk]
    if n then return n end
    nNodes = nNodes + 1
    n = nNodes
    NM[n], NX[n], NY[n], NK[n] = mi, x, y, k
    nodeIx[kk] = n
    local list = k == 3 and Gw.arrivals or Gw.exits
    list[mi] = list[mi] or {}
    list[mi][#list[mi] + 1] = n
    return n
  end
  function Gw.node(mi, x, y, k) return nodeIx[key(mi, x, y, k)] end
  function Gw.arrivalAt(id, x, y)
    local mi = Gw.mi[id]
    return mi and nodeIx[key(mi, x, y, 3)] or nil
  end
  local function addEdge(a, b, dl, ds, hl, hs, ml, ms)
    nEdges = nEdges + 1
    EA[nEdges], EB[nEdges], EL[nEdges], ES[nEdges] = a, b, dl, ds
    EHL[nEdges], EHS[nEdges], EML[nEdges], EMS[nEdges] = hl or dl, hs or ds, ml or 0, ms or 0
  end
  Gw.count = function() return nNodes, nEdges end

  local function clear()
    for _, t in ipairs({ NM, NX, NY, NK, EA, EB, EL, ES, EHL, EHS, EML, EMS }) do
      for k = #t, 1, -1 do t[k] = nil end
    end
    for _, t in ipairs({ Gw.mi, Gw.ids, Gw.into, Gw.exits, Gw.arrivals, nodeIx }) do
      for k in pairs(t) do t[k] = nil end
    end
    nNodes, nEdges = 0, 0
  end

  local function skipped(id)
    for _, s in ipairs(SKIP) do if id:find(s, 1, true) then return true end end
    return false
  end
  -- (a map worth walking through: joined to others by connections, or by warps to two places or more)
  local function included(id, def)
    if type(id) ~= "string" or type(def) ~= "table" or skipped(id) then return false end
    if linked(id) then return true end
    local okC, conns = pcall(Conn.each, def)
    if okC and type(conns) == "table" and #conns > 0 then return true end
    local first
    for _, w in ipairs(def.warps or {}) do
      local k = tostring(w.destMap) .. ":" .. tostring(w.destWarp) .. ":" .. tostring(w.mapNum)
      if first == nil then first = k elseif k ~= first then return true end
    end
    return false
  end

  -- (where a warp leads: the map and the tile, or nil for one that goes back where the player came from)
  local function destOf(wp)
    if tonumber(wp.mapNum) == 0x7F then return nil end
    local dm = wp.destMap or wp.map
    if type(dm) == "string" and dm:find("DYNAMIC", 1, true) then return nil end
    local ok, m, x, y = pcall(Collision.resolveWarpDestination, deps.game and deps.game() or nil, wp)
    if ok and type(m) == "string" then return m, tonumber(x) or 0, tonumber(y) or 0 end
    return nil
  end
  Gw.destOf = function(wp) mods(); return destOf(wp) end

  -- the stamp: what the graph was made from (kept on disk while it's the same)
  local function fingerprint(all)
    local n, warps, conns = 0, 0, 0
    for id, def in pairs(all) do
      if type(id) == "string" and type(def) == "table" then
        n = n + 1
        warps = warps + #(def.warps or {})
        conns = conns + #(def.connections or {})
      end
    end
    return ("%d|%s|%s|%s|%d:%d:%d"):format(FORMAT, tostring(deps.version or "?"), tostring(deps.engine or "?"),
      tostring(deps.gameId and deps.gameId() or "?"), n, warps, conns)
  end
  local function path()
    local g = tostring(deps.gameId and deps.gameId() or "game"):gsub("[^%w_%-]", "_")
    return "gps/" .. g .. ".txt"
  end

  -- ------- kept on disk: a line per map, node and edge

  local function write(stamp)
    local cache = deps.cache
    if not (cache and cache.write) then return end
    local out = { "GPS " .. stamp }
    for mi, id in ipairs(Gw.ids) do out[#out + 1] = "M " .. id end
    for n = 1, nNodes do out[#out + 1] = ("N %d %d %d %d"):format(NM[n], NX[n], NY[n], NK[n]) end
    for e = 1, nEdges do
      out[#out + 1] = ("E %d %d %d %d %d %d %d %d"):format(EA[e], EB[e], EL[e], ES[e], EHL[e], EHS[e], EML[e], EMS[e])
    end
    local ok, err = pcall(cache.write, cache, path(), table.concat(out, "\n"))
    if not ok then log("the GPS couldn't keep its graph: %s", tostring(err)) end
  end
  local function read(stamp, breathe)
    local cache = deps.cache
    if not (cache and cache.read) then return false end
    local ok, text = pcall(cache.read, cache, path())
    if not (ok and type(text) == "string") then return false end
    local head = text:match("^GPS ([^\n]*)")
    if head ~= stamp then return false end
    clear()
    local lines = 0
    for kind, rest in text:gmatch("\n(%u) ([^\n]*)") do
      if kind == "M" then
        local mi = #Gw.ids + 1
        Gw.ids[mi], Gw.mi[rest] = rest, mi
      elseif kind == "N" then
        local a, b, c, d = rest:match("^(%d+) (%d+) (%d+) (%d+)$")
        newNode(tonumber(a), tonumber(b), tonumber(c), tonumber(d))
      elseif kind == "E" then
        local a, b, c, d, e, f, g, h = rest:match("^(%d+) (%d+) (%-?%d+) (%-?%d+) (%-?%d+) (%-?%d+) (%d+) (%d+)$")
        if a then
          addEdge(tonumber(a), tonumber(b), tonumber(c), tonumber(d), tonumber(e), tonumber(f), tonumber(g),
            tonumber(h))
        end
      end
      lines = lines + 1
      if lines % 2000 == 0 then breathe() end
    end
    return nNodes > 0
  end

  local function finish()
    for k in pairs(Gw.into) do Gw.into[k] = nil end
    for e = 1, nEdges do
      local b = EB[e]
      local l = Gw.into[b]
      if not l then
        l = {}
        Gw.into[b] = l
      end
      l[#l + 1] = e
    end
  end

  -- ------- building it (in a coroutine: a few milliseconds a frame)


  -- a connected edge's tiles in runs (land and water apart), each run's middle an exit
  local function edgeRuns(mi, rec, conn, all)
    local dir = CONN_DIR[conn.dir]
    if not dir then return end
    local destDef = all[conn.map]
    local dmi = Gw.mi[conn.map]
    if not (destDef and dmi) then return end
    local L, dest = layoutOf(conn.map, destDef)
    if not L then return end
    local behs = IS and IS.behaviors and IS.behaviors[destDef.pair or L.pair]
    local w, h = rec.w, rec.h
    local along = (dir == 1 or dir == 2) and w or h
    local function at(t)
      if dir == 1 then return t, 0 elseif dir == 2 then return t, h - 1
      elseif dir == 3 then return 0, t else return w - 1, t end
    end
    local function landing(x, y)
      local okL, lx, ly = pcall(Collision.connectionLanding, dest, conn, DIR_NAME[dir], x, y)
      if not (okL and lx) then return nil end
      local c = classify(dest, L, behs, lx, ly)
      return lx, ly, c
    end
    local t = 0
    while t < along do
      local x, y = at(t)
      local i = y * w + x
      local c = rec.cls[i]
      local run = (c == LAND or c == WATER) and not has(rec.wall[i], LEAVE[dir]) and c or nil
      if run then
        local t1 = t
        while t1 + 1 < along and t1 - t + 1 < RUN do
          local x2, y2 = at(t1 + 1)
          local j = y2 * w + x2
          if rec.cls[j] ~= run or has(rec.wall[j], LEAVE[dir]) then break end
          t1 = t1 + 1
        end
        -- (the run's middle, or the nearest tile of it that lands somewhere it can stand)
        local mid = floor((t + t1) / 2)
        local found = false
        for k = 0, t1 - t do
          for sgn = -1, 1, 2 do
            local tt = mid + sgn * k
            if not found and tt >= t and tt <= t1 then
              local mx, my = at(tt)
              local lx, ly, lc = landing(mx, my)
              if lx and (lc == run or (run == LAND and lc == WARP)) then
                addEdge(newNode(mi, mx, my, 2), newNode(dmi, lx, ly, 3), 1, 1)
                found = true
              end
            end
          end
          if found then break end
        end
        t = t1 + 1
      else
        t = t + 1
      end
    end
  end

  local function buildAll()
    state.progress = 0
    if not mods() then
      log("the GPS can't read the maps: the engine's collision modules aren't there")
      return false
    end
    local all = maps()
    if type(all) ~= "table" then
      log("the GPS can't read the maps: no maps")
      return false
    end
    local stamp = fingerprint(all)
    if read(stamp, breathe) then
      finish()
      state.progress = 1
      return true
    end
    clear()
    local ids = {}
    local seen = 0
    for id, def in pairs(all) do
      if included(id, def) then ids[#ids + 1] = id end
      seen = seen + 1
      if seen % 32 == 0 then breathe() end
    end
    table.sort(ids)
    for mi, id in ipairs(ids) do Gw.ids[mi], Gw.mi[id] = id, mi end
    local n = #ids
    -- (the points: each map's warps and connected edges)
    local pending = {}
    for mi, id in ipairs(ids) do
      local rec = Gw.tiles(id)
      if rec then
        for wi, wp in ipairs(rec.def.warps or {}) do
          local x, y = tonumber(wp.x), tonumber(wp.y)
          if x and y and x >= 0 and y >= 0 and x < rec.w and y < rec.h then
            newNode(mi, x, y, 3)
            if rec.warp[y * rec.w + x] == wi then
              local ex = newNode(mi, x, y, 1)
              pending[#pending + 1] = { ex, wp }
            end
          end
        end
        local okC, conns = pcall(Conn.each, rec.def)
        if okC and type(conns) == "table" then
          for _, c in ipairs(conns) do edgeRuns(mi, rec, c, all) end
        end
      end
      state.progress = 0.3 * mi / n
      breathe()
    end
    -- (a warp's exit to where it leads)
    for _, p in ipairs(pending) do
      local m, x, y = destOf(p[2])
      local dmi = m and Gw.mi[m]
      if dmi then addEdge(p[1], newNode(dmi, x, y, 3), 1, 1) end
    end
    -- (the scripted rides: each arrival at one end to each at the other)
    for _, l in ipairs(LINKS) do
      local a, b
      for mi, id in ipairs(ids) do
        if id:sub(-#l[1]) == l[1] then a = mi elseif id:sub(-#l[2]) == l[2] then b = mi end
      end
      if a and b then
        for _, x in ipairs(Gw.arrivals[a] or {}) do
          for _, y in ipairs(Gw.arrivals[b] or {}) do
            addEdge(x, y, l[3], l[3])
            addEdge(y, x, l[3], l[3])
          end
        end
      end
    end
    -- (each arrival to each exit of its map it can walk to: on foot, and with Surf)
    local len, hm = { {}, {}, {}, {} }, { {}, {}, {}, {} }
    for mi, id in ipairs(ids) do
      local rec = Gw.tiles(id)
      local arr, exits = Gw.arrivals[mi], Gw.exits[mi]
      if rec and arr and exits then
        local exitAt = {}
        for _, x in ipairs(exits) do
          local i = NY[x] * rec.w + NX[x]
          exitAt[i] = exitAt[i] or {}
          exitAt[i][#exitAt[i] + 1] = x
        end
        for _, a in ipairs(arr) do
          for p = 1, 4 do
            for k in pairs(len[p]) do len[p][k] = nil end
            for k in pairs(hm[p]) do hm[p][k] = nil end
          end
          local i0 = NY[a] * rec.w + NX[a]
          -- (on foot, with Surf; each without the HMs' obstacles, then through them)
          for pass = 1, 4 do
            local into, used = len[pass], hm[pass]
            Gw.walk(rec, NX[a], NY[a], false, pass % 2 == 0, function(i, d, mk)
              local at = exitAt[i]
              if at then
                for _, x in ipairs(at) do
                  -- (a warp out of the very tile come in on: off it and back on)
                  local dd = (i == i0 and NK[x] == 1) and 2 or d
                  if into[x] == nil or dd < into[x] then into[x], used[x] = dd, mk end
                end
              end
            end, nil, nil, pass > 2 and HM_ALL or 0)
          end
          for x, hs in pairs(len[4]) do
            addEdge(a, x, len[1][x] or -1, len[2][x] or -1, len[3][x] or -1, hs, hm[3][x] or 0, hm[4][x] or 0)
          end
          breathe()
        end
      end
      state.progress = 0.3 + 0.7 * mi / n
      breathe()
    end
    Gw.forgetTiles()
    finish()
    write(stamp)
    state.progress = 1
    return true
  end

  function Gw.prepare()
    if state.ready or state.job or state.failed then return end
    state.job = coroutine.create(buildAll)
  end
  function Gw.step(budget)
    local co = state.job
    if not co then return false end
    slice.start, slice.budget = clock(), budget or 0.004
    local ok, done = coroutine.resume(co)
    if not ok then
      log("the GPS's map failed: %s", tostring(done))
      state.job, state.failed = nil, true
      return false
    end
    if coroutine.status(co) == "dead" then
      state.job = nil
      state.ready = done == true
      if not state.ready then state.failed = true end
      return false
    end
    return true
  end
  -- (tests: built at once)
  function Gw.buildNow()
    Gw.prepare()
    slice.budget = math.huge
    while Gw.step(math.huge) do end
    return state.ready
  end
  function Gw.ready() return state.ready end
  function Gw.building() return state.job ~= nil end
  function Gw.progress() return state.ready and 1 or state.progress end
  function Gw.reset()
    clear()
    Gw.forgetTiles()
    state.ready, state.job, state.failed, state.progress = false, nil, false, 0
  end

  return Gw
end
