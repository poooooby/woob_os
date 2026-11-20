-- The GPS's walk graph (FireRed / LeafGreen / Ruby / Sapphire / Emerald; Gold / Silver / Crystal): every map
-- a player can walk through, read from the game's own maps by a reader of each generation's (src/gps/
-- read3.lua, read2.lua: the tiles' collision, the warps and connections), made into points ("nodes") joined
-- by how many steps lie between them.
--   arrival  where a player stands after coming in: on a warp's tile, or at a connection's landing
--   exit     where a player leaves: a warp's tile that fires (a door, a ladder, a hole, stairs) or the
--            middle of a run of tiles along a connected edge (a run at most RUN tiles long)
-- Each arrival is joined to each exit of its map it can walk to (on foot, and with Surf; each without the
-- obstacles and through them, with the obstacles that path took), each exit to the arrival it leads to (one
-- step). Houses with one way in and out are left out (no one walks through them). Ledges are one way; one-way
-- walls and elevations (bridges) are kept as the game moves a player. An obstacle is a bit of a mask: an HM's
-- (a Cut tree, a Rock Smash rock, a Strength boulder; Gen 2's whirlpools and waterfalls too) or, on Gen 2, a
-- gate of the story's (Sudowoodo, the Snorlax, a guard, a ticket): a wall unless the walk may pass it.
--
--   Gw = graph(engine, deps)  deps: reader(engine, deps, Gw) -> the generation's reader ; cache (mod.cache) ;
--                             gameId() ; version ; engine (its version) ; log(fmt, ...) ; and the reader's own
--   Gw.prepare() ; Gw.step(budget) -> true while there's more ; Gw.ready() ; Gw.progress() -> 0..1
--   Gw.tiles(mapId) -> rec { id, def, w, h, cls, elev, ledge, wall, warp, obst [, block, hop, ice, upOnly] }
--   Gw.walk(rec, x, y, surfing, allowSurf, reach(i, d, hm) -> stop?, maxD, parents, hms) -> the tiles' steps
--       (hms: the obstacles it may pass, a mask of Gw.HMS's bits; hm: those its way there took)
--   Gw.pathTo(i) -> the tile indices from the walk's start to i (after a walk with parents)
--   Gw.HMS -> { { bit, key, word [, flag, item] }, ... } (the reader's) ; Gw.HM_ALL ; Gw.covers(have, need)
--   Gw.mi[mapId] ; Gw.ids[mi] ; nodes NM / NX / NY / NK (1 warp exit, 2 edge exit, 3 arrival) ;
--   edges EA -> EB, EL (on foot, -1 none) / ES (with Surf), EHL / EHS (through obstacles) and EML / EMS (the
--   obstacles that took) ; Gw.into[node] = { edge, ... } ;
--   Gw.exits[mi] = { node, ... } ; Gw.arrivals[mi] = { node, ... } ; Gw.node(mi, x, y, k) -> node | nil
--   Gw.arrivalAt(mapId, x, y) -> node | nil
--
-- The reader (R = reader(engine, deps, Gw)):
--   R.HMS ; R.ready() -> its engine modules are there ; R.maps() -> the map definitions by id ;
--   R.included(id, def) ; R.build(id, def) -> rec | nil ; R.conns(def) -> { { dir (1 up 2 down 3 left 4 right),
--   map, ... }, ... } ; R.landing(conn, x, y) -> lx, ly, cls | nil ; R.destOf(warp) -> mapId, x, y | nil ;
--   R.links(ids) -> { { a = mapId, b = mapId, cost, gate (a bit, 0: none) }, ... } ; R.fingerprint(all) ;
--   R.forget() (anything it keeps)

local floor = math.floor

local FORMAT = 3
local RUN = 12            -- a connected edge's run of tiles: one exit each this many
local OBSTACLE = 2        -- the steps an obstacle costs once it can be passed (a little: round it if as near)
local KEEP_TILES = 6      -- maps' tiles kept at once
-- the four ways: up, down, left, right
local DX, DY = { 0, 0, -1, 1 }, { -1, 1, 0, 0 }
local DIR_NAME = { "up", "down", "left", "right" }
-- one-way walls: a tile's behaviour blocks leaving it, or coming into it (north 1, south 2, west 4, east 8)
local LEAVE, ENTER = { 1, 2, 4, 8 }, { 2, 1, 8, 4 }
local HOP = { 1, 2, 4, 8 }   -- a ledge's facings (up, down, left, right)
-- tiles' classes
local WALL, LAND, WATER, LEDGE, WARP = 0, 1, 2, 3, 4
local SURF = 16              -- a walk's state: tile * 17 + the elevation it's at (0..15), or 16 surfing

-- (masks: LuaJIT's bit library, the sandbox's own copy; a plain fallback where there's none)
local bitlib = rawget(_G, "bit")
local bor, band
if bitlib and bitlib.bor then
  bor, band = bitlib.bor, bitlib.band
else
  local function op(a, b, both)
    local r, p = 0, 1
    while a > 0 or b > 0 do
      local x, y = a % 2, b % 2
      if (both and x == 1 and y == 1) or (not both and (x == 1 or y == 1)) then r = r + p end
      a, b, p = (a - x) / 2, (b - y) / 2, p * 2
    end
    return r
  end
  bor = function(a, b) return op(a, b, false) end
  band = function(a, b) return op(a, b, true) end
end

local function has(m, b) return m ~= nil and m ~= 0 and floor(m / b) % 2 == 1 end

return function(engine, deps)
  deps = deps or {}
  local Gw = { RUN = RUN, WALL = WALL, LAND = LAND, WATER = WATER, LEDGE = LEDGE, WARP = WARP, DX = DX, DY = DY,
               DIR_NAME = DIR_NAME, LEAVE = LEAVE, ENTER = ENTER, bor = bor, band = band }
  local function log(...) if deps.log then deps.log(...) end end

  -- (the build: a slice of the frame at a time; only ever inside its own coroutine)
  local state = { ready = false, job = nil, progress = 0, failed = false }
  local slice = { start = 0, budget = 0.004 }
  local function clock() return love and love.timer and love.timer.getTime() or os.clock() end
  local function breathe()
    local co = state.job
    if co and coroutine.running() == co and clock() - slice.start > slice.budget then coroutine.yield() end
  end
  Gw.breathe = breathe

  local R = deps.reader and deps.reader(engine, deps, Gw) or nil
  Gw.reader = R
  Gw.HMS = R and R.HMS or {}
  local all = 0
  for _, h in ipairs(Gw.HMS) do all = bor(all, h.bit) end
  Gw.HM_ALL = all
  -- (the HMs Gen 3 names: kept for the tests and the scene's words)
  for _, h in ipairs(Gw.HMS) do
    if h.key == "CUT" then Gw.HM_CUT = h.bit elseif h.key == "ROCK_SMASH" then Gw.HM_SMASH = h.bit
    elseif h.key == "STRENGTH" then Gw.HM_STRENGTH = h.bit end
  end
  function Gw.covers(have, need) return bor(have or 0, need or 0) == (have or 0) end
  local function maps() return R and R.maps() or nil end

  -- ------- a map's tiles (the reader's; the last few kept)

  local kept, keptOrder = {}, {}
  function Gw.tiles(id)
    local r = kept[id]
    if r then return r end
    if not (R and R.ready()) then return nil end
    local defs = maps()
    local def = defs and defs[id]
    if not def then return nil end
    local ok, made = pcall(R.build, id, def)
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
    if R and R.forget then R.forget() end
  end
  Gw.destOf = function(wp) return R and R.ready() and R.destOf(wp) or nil end

  -- ------- a walk over one map: breadth first, from a tile, as the player moves

  -- (Gen 2's ice: on from a tile the way it was entered until something stops it; the tile it stops on)
  local function slide(rec, j, dir)
    local w, h, cls, ice, block = rec.w, rec.h, rec.cls, rec.ice, rec.block
    local extra = 0
    while ice[j] and extra < 64 do
      if block and has(block[j], LEAVE[dir]) then break end
      local x = j % w
      local y = (j - x) / w
      local nx, ny = x + DX[dir], y + DY[dir]
      if nx < 0 or ny < 0 or nx >= w or ny >= h then break end
      local k = ny * w + nx
      local c = cls[k]
      if c ~= LAND and c ~= WARP then break end
      if rec.obst[k] then break end
      j, extra = k, extra + 1
      if c == WARP then break end
    end
    return j, extra
  end

  -- (one step: the tile it lands on, the elevation after, its cost -- or nil)
  local function move(rec, i, e, dir, allowSurf)
    local w = rec.w
    local x = i % w
    local y = (i - x) / w
    local nx, ny = x + DX[dir], y + DY[dir]
    local surf = e == SURF
    local hop = rec.hop
    local block = rec.block
    local j
    local ok = nx >= 0 and ny >= 0 and nx < w and ny < rec.h
    if ok and has(rec.wall[i], LEAVE[dir]) then ok = false end
    if ok and block and has(block[i], LEAVE[dir]) then ok = false end
    if ok then
      j = ny * w + nx
      if has(rec.wall[j], ENTER[dir]) then ok = false end
    end
    if ok then
      local c = rec.cls[j]
      if c == WARP then return j, e, 1 end
      if c == WATER then
        if surf or allowSurf then return j, SURF, 1 end
        ok = false
      end
      local elev = rec.elev
      if ok and c == LAND then
        local te = elev[j] or 0
        if surf then
          -- (getting off: onto land at its own height, or the game's usual 3)
          if te ~= 0 and te ~= 15 and te ~= 3 and te ~= 1 then return nil end
          local k, extra = j, 0
          if rec.ice and rec.ice[j] then k, extra = slide(rec, j, dir) end
          return k, (te == 0 or te == 15) and 3 or te, 1 + extra
        end
        if e ~= 0 and te ~= 0 and te ~= 15 and te ~= e then return nil end
        local k, extra = j, 0
        if rec.ice and rec.ice[j] then k, extra = slide(rec, j, dir) end
        if te == 15 or (elev[i] or 0) == 15 then return k, e, 1 + extra end
        return k, te, 1 + extra
      end
      if ok and c == LEDGE and not surf and has(rec.ledge[j], HOP[dir]) then
        local lx, ly = nx + DX[dir], ny + DY[dir]
        if lx < 0 or ly < 0 or lx >= w or ly >= rec.h then return nil end
        local k = ly * w + lx
        local ck = rec.cls[k]
        if ck == LAND then
          local te = elev[k] or 0
          return k, te == 15 and e or te, 2
        end
        if ck == WARP then return k, e, 2 end
      end
    end
    -- (Gen 2's ledges: a step refused off a ledge's own tile, the way it hops, is a jump two tiles on)
    if hop and not surf and has(hop[i], HOP[dir]) then
      local lx, ly = x + DX[dir] * 2, y + DY[dir] * 2
      if lx < 0 or ly < 0 or lx >= w or ly >= rec.h then return nil end
      local k = ly * w + lx
      local ck = rec.cls[k]
      if ck == LAND or ck == WARP then return k, e, 2 end
    end
    return nil
  end
  Gw.move = move

  -- (the walk's tables, used again each time; a queue of buckets, one per number of steps: the steps
  -- aren't all one -- a ledge's hop is two, an obstacle more)
  -- (a state's steps, parent and obstacles are this walk's while its stamp is this walk's number: nothing
  -- cleared, no table grown again walk after walk)
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
  -- (an obstacle on tile j stepped onto going `dir`: its bit, or nil -- a waterfall only stops a climb)
  local function obstacle(rec, j, dir)
    local need = rec.obst[j]
    if need and dir ~= 1 and rec.upOnly and rec.upOnly[j] then return nil end
    return need
  end
  Gw.obstacle = obstacle
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
    local cls = rec.cls
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
                local need = j and obstacle(rec, j, dir)
                -- (an obstacle: a wall unless the walk may pass it)
                if need and bor(hms, need) ~= hms then j = nil end
                if j then
                  local mk = MK[s]
                  if need then
                    cost = cost + OBSTACLE
                    mk = bor(mk, need)
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

  -- the stamp: what the graph was made from (kept on disk while it's the same)
  local function fingerprint(defs)
    return ("%d|%s|%s|%s|%s"):format(FORMAT, tostring(deps.version or "?"), tostring(deps.engine or "?"),
      tostring(deps.gameId and deps.gameId() or "?"), R.fingerprint(defs))
  end
  local function path()
    local g = tostring(deps.gameId and deps.gameId() or "game"):gsub("[^%w_%-]", "_")
    return "gps/" .. g .. ".txt"
  end

  -- ------- kept on disk: a line per map, node and edge

  -- (Gw.cache: the tests' own disk in place of mod.cache)
  local function write(stamp)
    local cache = Gw.cache or deps.cache
    if not (cache and cache.write) then return end
    local out = { "GPS " .. stamp }
    for _, id in ipairs(Gw.ids) do out[#out + 1] = "M " .. id end
    for n = 1, nNodes do out[#out + 1] = ("N %d %d %d %d"):format(NM[n], NX[n], NY[n], NK[n]) end
    for e = 1, nEdges do
      out[#out + 1] = ("E %d %d %d %d %d %d %d %d"):format(EA[e], EB[e], EL[e], ES[e], EHL[e], EHS[e], EML[e], EMS[e])
    end
    local ok, err = pcall(cache.write, cache, path(), table.concat(out, "\n"))
    if not ok then log("the GPS couldn't keep its graph: %s", tostring(err)) end
  end
  local function read(stamp)
    local cache = Gw.cache or deps.cache
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
  local function edgeRuns(mi, rec, conn)
    local dir = conn.dir
    local dmi = Gw.mi[conn.map]
    if not (dir and dmi) then return end
    local w, h = rec.w, rec.h
    local along = (dir == 1 or dir == 2) and w or h
    local function at(t)
      if dir == 1 then return t, 0 elseif dir == 2 then return t, h - 1
      elseif dir == 3 then return 0, t else return w - 1, t end
    end
    local block = rec.block
    local function open(i) return not has(rec.wall[i], LEAVE[dir]) and not (block and has(block[i], LEAVE[dir])) end
    local t = 0
    while t < along do
      local x, y = at(t)
      local i = y * w + x
      local c = rec.cls[i]
      local run = (c == LAND or c == WATER) and open(i) and c or nil
      if run then
        local t1 = t
        while t1 + 1 < along and t1 - t + 1 < RUN do
          local x2, y2 = at(t1 + 1)
          local j = y2 * w + x2
          if rec.cls[j] ~= run or not open(j) then break end
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
              local okL, lx, ly, lc = pcall(R.landing, conn, mx, my)
              if okL and lx and (lc == run or (run == LAND and lc == WARP)) then
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
    if not (R and R.ready()) then
      log("the GPS can't read the maps: the engine's modules aren't there")
      return false
    end
    local defs = maps()
    if type(defs) ~= "table" then
      log("the GPS can't read the maps: no maps")
      return false
    end
    local stamp = fingerprint(defs)
    if read(stamp) then
      finish()
      state.progress = 1
      return true
    end
    clear()
    local ids = {}
    local seen = 0
    for id, def in pairs(defs) do
      if type(id) == "string" and type(def) == "table" and R.included(id, def) then ids[#ids + 1] = id end
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
        local okC, conns = pcall(R.conns, rec.def)
        if okC and type(conns) == "table" then
          for _, c in ipairs(conns) do edgeRuns(mi, rec, c) end
        end
      end
      state.progress = 0.3 * mi / n
      breathe()
    end
    -- (a warp's exit to where it leads)
    for _, p in ipairs(pending) do
      local m, x, y = R.destOf(p[2])
      local dmi = m and Gw.mi[m]
      if dmi then addEdge(p[1], newNode(dmi, x, y, 3), 1, 1) end
    end
    -- (the rides a script makes, not a warp: each arrival at one end to each at the other; a gated one only
    -- through its gate)
    local okL, links = pcall(R.links, ids)
    for _, l in ipairs(okL and type(links) == "table" and links or {}) do
      local a, b = Gw.mi[l.a], Gw.mi[l.b]
      if a and b then
        local g = l.gate or 0
        for _, x in ipairs(Gw.arrivals[a] or {}) do
          for _, y in ipairs(Gw.arrivals[b] or {}) do
            if g == 0 then
              addEdge(x, y, l.cost, l.cost)
              addEdge(y, x, l.cost, l.cost)
            else
              addEdge(x, y, -1, -1, l.cost, l.cost, g, g)
              addEdge(y, x, -1, -1, l.cost, l.cost, g, g)
            end
          end
        end
      end
    end
    -- (each arrival to each exit of its map it can walk to: on foot, and with Surf)
    local all = Gw.HM_ALL
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
          -- (on foot, with Surf; each without the obstacles, then through them)
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
            end, nil, nil, pass > 2 and all or 0)
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
