-- The GPS's map reader on Gold / Silver / Crystal (src/gps/graph.lua's reader): every map's 16 px squares
-- from its blocks and its tileset's collision (the map's own blocks before Cut, Whirlpool or a script changed
-- them: the World keeps those in blockEdits), read as src/world/gen2/World.lua moves a player: land, water,
-- ledges hopped from their own square two squares on, one-way walls (Permissions.stepPermitted), ice
-- sliding on, warps that fire (doors, stairs, caves, ladders, holes, the carpets inside a door).
-- The obstacles: Cut trees (tiles here: their block swapped for its cut one), Rock Smash rocks and Strength
-- boulders (objects), whirlpools, waterfalls (only climbing one: down, the water carries the player); and
-- the story's gates, each its own bit: Sudowoodo, the Snorlax by Diglett's Cave, the man holding Mahogany's
-- east road until Team Rocket's hideout is cleared, Victory Road Gate's guards and its Badge check, the
-- Cycling Road's gates (a Bicycle), the Magnet Train (the Pass, the power back on) and the S.S. Aqua (its
-- ticket: Olivine's and Vermilion's ports joined, the ship's own rooms left out).
--
--   R = read2(engine, deps, Gw)   deps: maps() -> gen2Maps ; tilesets() -> gen2Tilesets ; edits(mapId) ->
--                                 the World's blockEdits for it (the blocks' first values) | nil

local floor = math.floor

local SKIP = { "TRADE_CENTER", "COLOSSEUM", "TIME_CAPSULE", "MOBILE_", "FAST_SHIP", "ELEVATOR", "POKECENTER_2F",
               "BATTLE_TOWER_BATTLE_ROOM", "BATTLE_TOWER_ELEVATOR", "BATTLE_TOWER_HALLWAY" }
local CONN_DIR = { north = 1, south = 2, west = 3, east = 4 }
local HOP_BIT = { up = 1, down = 2, left = 4, right = 8 }
local MV_SMASH, MV_STRENGTH, MV_SUDOWOODO = 0x18, 0x19, 0x17
local HIDDEN = 0xFFFF       -- an object's flag that never hides it
local SHIP = { "OLIVINE_PORT", "VERMILION_PORT", 24 }
local TRAIN = { "GOLDENROD_MAGNET_TRAIN_STATION", "SAFFRON_MAGNET_TRAIN_STATION" }

return function(engine, deps, Gw)
  local WALL, LAND, WATER, WARP = Gw.WALL, Gw.LAND, Gw.WATER, Gw.WARP
  local LEAVE, DIR_NAME = Gw.LEAVE, Gw.DIR_NAME
  local breathe = Gw.breathe
  -- (the obstacles' bits: kept as they are, the graph on disk holds them)
  local G = {
    CUT = { bit = 1, key = "CUT", word = "map.hm.cut" },
    SMASH = { bit = 2, key = "ROCK_SMASH", word = "map.hm.smash" },
    STRENGTH = { bit = 4, key = "STRENGTH", word = "map.hm.strength" },
    WHIRL = { bit = 8, key = "WHIRLPOOL", word = "map.hm.whirlpool" },
    FALL = { bit = 16, key = "WATERFALL", word = "map.hm.waterfall" },
    SUDOWOODO = { bit = 32, key = "FLAG", word = "map.gate.sudowoodo" },
    SNORLAX = { bit = 64, key = "FLAG", word = "map.gate.snorlax" },
    ROCKETS = { bit = 128, key = "FLAG", word = "map.gate.rockets" },
    GUARD1 = { bit = 256, key = "FLAG", word = "map.gate.guard" },
    GUARD2 = { bit = 512, key = "FLAG", word = "map.gate.guard" },
    BADGES = { bit = 1024, key = "BADGES", word = "map.gate.badges", count = 8 },
    BIKE = { bit = 2048, key = "ITEM", word = "map.gate.bike", item = "BICYCLE" },
    TRAIN = { bit = 4096, key = "ITEM", word = "map.gate.train", item = "PASS", event = "EVENT_RESTORED_POWER_TO_KANTO" },
    SHIP = { bit = 8192, key = "ITEM", word = "map.gate.ship", item = "S_S_TICKET" },
  }
  local R = { HMS = { G.CUT, G.SMASH, G.STRENGTH, G.WHIRL, G.FALL, G.SUDOWOODO, G.SNORLAX, G.ROCKETS, G.GUARD1,
                      G.GUARD2, G.BADGES, G.BIKE, G.TRAIN, G.SHIP } }
  R.G = G

  local P, CP, FM, Map2
  function R.maps() return deps.maps and deps.maps() or nil end
  local function tilesets() return deps.tilesets and deps.tilesets() or nil end

  -- ------- the story's gates: where they stand, and the flag that hides each (the cart's own, found in its maps)

  local gates = nil       -- [mapId] = { { x, y, bit }, ... }
  local function gateAt(id, x, y, g)
    if not g then return end
    gates[id] = gates[id] or {}
    local list = gates[id]
    list[#list + 1] = { x, y, g.bit }
  end
  local function coordCells(def, g)
    for _, c in ipairs(def and def.coordEvents or {}) do
      local x, y = tonumber(c.x), tonumber(c.y)
      if x and y then gateAt(def.id, x, y, g) end
    end
  end
  local function scan(all)
    gates = {}
    for id, def in pairs(all) do
      if type(def) == "table" then
        for _, o in ipairs(def.objects or {}) do
          local x, y, f = tonumber(o.x), tonumber(o.y), tonumber(o.eventFlag)
          if x and y and f and f ~= HIDDEN then
            if tonumber(o.movement) == MV_SUDOWOODO and not G.SUDOWOODO.flag then
              G.SUDOWOODO.flag = f
              gateAt(id, x, y, G.SUDOWOODO)
            elseif o.sprite == "SPRITE_BIG_SNORLAX" and not G.SNORLAX.flag then
              -- (a big object: its square and the three it overhangs)
              G.SNORLAX.flag = f
              for dy = 0, 1 do for dx = 0, 1 do gateAt(id, x + dx, y + dy, G.SNORLAX) end end
            end
          end
        end
      end
    end
    -- (Mahogany's east road: the man on the square its scene stops a player at)
    local mh = all.MAHOGANY_TOWN
    for _, o in ipairs(mh and mh.objects or {}) do
      local x, y, f = tonumber(o.x), tonumber(o.y), tonumber(o.eventFlag)
      for _, c in ipairs(mh.coordEvents or {}) do
        if f and f ~= HIDDEN and tonumber(c.x) == x and tonumber(c.y) == y and not G.ROCKETS.flag then
          G.ROCKETS.flag = f
          gateAt("MAHOGANY_TOWN", x, y, G.ROCKETS)
        end
      end
    end
    if G.ROCKETS.flag then coordCells(mh, G.ROCKETS) end
    -- (Victory Road Gate: the Badge check's squares, and the two guards)
    local vg = all.VICTORY_ROAD_GATE
    if vg then
      coordCells(vg, G.BADGES)
      local n = 0
      for _, o in ipairs(vg.objects or {}) do
        local x, y, f = tonumber(o.x), tonumber(o.y), tonumber(o.eventFlag)
        if o.sprite == "SPRITE_BLACK_BELT" and x and y and f and f ~= HIDDEN and n < 2 then
          n = n + 1
          local g = n == 1 and G.GUARD1 or G.GUARD2
          g.flag = f
          gateAt("VICTORY_ROAD_GATE", x, y, g)
        end
      end
    end
    -- (the Cycling Road's gates: a Bicycle)
    coordCells(all.ROUTE_16_GATE, G.BIKE)
    coordCells(all.ROUTE_17_ROUTE_18_GATE, G.BIKE)
    -- (the Magnet Train: the warps between the two stations)
    for k = 1, 2 do
      local id, other = TRAIN[k], TRAIN[3 - k]
      local def = all[id]
      for _, wp in ipairs(def and def.warps or {}) do
        if wp.destMap == other then gateAt(id, tonumber(wp.x), tonumber(wp.y), G.TRAIN) end
      end
    end
  end

  function R.ready()
    P = P or engine("src.world.gen2.Permissions")
    CP = CP or engine("src.core.CollPermissions")
    FM = FM or engine("src.world.gen2.FieldMoves")
    Map2 = Map2 or engine("src.world.gen2.Map")
    if not (P and CP and Map2) then return false end
    if not gates then
      local all = R.maps()
      if type(all) ~= "table" then return false end
      scan(all)
    end
    return true
  end
  function R.forget() end

  -- ------- a map's squares

  -- (a map's block at bx, by: its first value where the World has changed it)
  local function blockOf(def, edits, bx, by)
    if bx < 0 or by < 0 or bx >= def.width or by >= def.height then return def.borderBlock or 0 end
    local i = by * def.width + bx + 1
    local o = edits and edits[i]
    if o ~= nil then return o end
    return def.blocks[i] or 0
  end
  local function collOf(ts, b, cx, cy)
    if b == 0 then return 0xff end
    local q = ts.collision[b + 1]
    return q and q[(cy % 2) * 2 + (cx % 2) + 1] or 0xff
  end
  local function editsOf(id)
    if not deps.edits then return nil end
    local ok, e = pcall(deps.edits, id)
    return ok and type(e) == "table" and e or nil
  end

  function R.build(id, def)
    local tsAll = tilesets()
    local ts = tsAll and tsAll[def.tileset]
    if not (ts and ts.collision and type(def.blocks) == "table" and tonumber(def.width)) then return nil end
    local W = def.width
    local w, h = W * 2, def.height * 2
    local edits = editsOf(id)
    local rec = { id = id, def = def, w = w, h = h, cls = {}, elev = {}, ledge = {}, wall = {}, warp = {}, obst = {},
                  block = {}, hop = {}, ice = {}, upOnly = {} }
    local cls, elev, obst = rec.cls, rec.elev, rec.obst
    local cutRows = FM and FM.CUT_BLOCKS and FM.CUT_BLOCKS[def.tileset]
    local function collAt(cx, cy) return collOf(ts, blockOf(def, edits, floor(cx / 2), floor(cy / 2)), cx, cy) end
    local side = false
    for cy = 0, h - 1 do
      for cx = 0, w - 1 do
        local i = cy * w + cx
        local coll = collAt(cx, cy)
        local perm = CP.of(coll)
        local c = WALL
        if perm == CP.LAND then
          c = LAND
          local f = P.ledgeFacings(coll)
          if f then
            local m = 0
            for d, on in pairs(f) do if on and HOP_BIT[d] then m = m + HOP_BIT[d] end end
            if m ~= 0 then rec.hop[i] = m end
          end
          if P.isIce(coll) then rec.ice[i] = true end
        elseif perm == CP.WATER then
          c = WATER
          if P.isWhirlpool(coll) then obst[i] = G.WHIRL.bit end
          if P.isWaterfall(coll) then obst[i], rec.upOnly[i] = G.FALL.bit, true end
        elseif P.isCutTree(coll) and cutRows then
          -- (a Cut tree: land once its block is swapped for the cut one)
          local row = cutRows[blockOf(def, edits, floor(cx / 2), floor(cy / 2))]
          if row and CP.isLand(collOf(ts, row[1], cx, cy)) then
            c = LAND
            obst[i] = G.CUT.bit
          end
        end
        if P.isSideWall(coll) then side = true end
        cls[i], elev[i] = c, 0
      end
      if cy % 4 == 3 then breathe() end
    end
    -- (one-way walls: the steps the game refuses from each square near one)
    if side then
      for cy = 0, h - 1 do
        for cx = 0, w - 1 do
          local near = P.isSideWall(collAt(cx, cy)) or P.isSideWall(collAt(cx, cy - 1))
            or P.isSideWall(collAt(cx, cy + 1)) or P.isSideWall(collAt(cx - 1, cy)) or P.isSideWall(collAt(cx + 1, cy))
          if near then
            local m = 0
            for d = 1, 4 do
              if not P.stepPermitted(collAt, cx, cy, DIR_NAME[d]) then m = m + LEAVE[d] end
            end
            if m ~= 0 then rec.block[cy * w + cx] = m end
          end
        end
        if cy % 4 == 3 then breathe() end
      end
    end
    -- (the field moves' objects: rocks and boulders)
    for _, o in ipairs(def.objects or {}) do
      local x, y, mv = tonumber(o.x), tonumber(o.y), tonumber(o.movement)
      if x and y and x >= 0 and y >= 0 and x < w and y < h then
        if mv == MV_SMASH then obst[y * w + x] = G.SMASH.bit
        elseif mv == MV_STRENGTH then obst[y * w + x] = G.STRENGTH.bit end
      end
    end
    -- (the warps that fire: a warp's square, its collision a warp's)
    for wi, wp in ipairs(def.warps or {}) do
      local x, y = tonumber(wp.x), tonumber(wp.y)
      if x and y and x >= 0 and y >= 0 and x < w and y < h and P.isWarpCollision(collAt(x, y)) then
        cls[y * w + x] = WARP
        rec.warp[y * w + x] = wi
      end
    end
    -- (the story's gates on it)
    for _, g in ipairs(gates and gates[id] or {}) do
      local x, y = g[1], g[2]
      if x >= 0 and y >= 0 and x < w and y < h then
        local i = y * w + x
        if cls[i] == LAND or cls[i] == WARP then obst[i] = g[3] end
      end
    end
    return rec
  end

  -- ------- which maps, and how they join

  local function skipped(id)
    for _, s in ipairs(SKIP) do if id:find(s, 1, true) then return true end end
    return false
  end
  function R.included(id, def)
    if skipped(id) then return false end
    if id == SHIP[1] or id == SHIP[2] then return true end
    if type(def.connections) == "table" and next(def.connections) ~= nil then return true end
    local first
    for _, w in ipairs(def.warps or {}) do
      local k = tostring(w.destMap) .. ":" .. tostring(w.destWarp)
      if first == nil then first = k elseif k ~= first then return true end
    end
    return false
  end

  function R.conns(def)
    local out = {}
    for name, c in pairs(type(def.connections) == "table" and def.connections or {}) do
      local d = CONN_DIR[name]
      local m = type(c) == "table" and (c.mapId or (type(c.map) == "string" and c.map)) or nil
      if d and m then out[#out + 1] = { dir = d, map = m, conn = c } end
    end
    table.sort(out, function(a, b) return a.dir < b.dir end)
    return out
  end
  -- (where stepping off at x, y lands, and what that square is; past the strip the two maps share, nowhere)
  function R.landing(c, x, y)
    local all = R.maps()
    local dest = all and all[c.map]
    if not dest then return nil end
    local lx, ly = Map2.connectionLanding(dest, c.conn, DIR_NAME[c.dir], x, y)
    if not lx then return nil end
    local off = (tonumber(c.conn.offset) or 0) * 2
    if (c.dir == 1 or c.dir == 2) and lx ~= x - off then return nil end
    if (c.dir == 3 or c.dir == 4) and ly ~= y - off then return nil end
    local ts = tilesets() and tilesets()[dest.tileset]
    if not ts then return nil end
    local coll = collOf(ts, blockOf(dest, editsOf(c.map), floor(lx / 2), floor(ly / 2)), lx, ly)
    local perm = CP.of(coll)
    local cl = perm == CP.LAND and LAND or (perm == CP.WATER and WATER or WALL)
    return lx, ly, cl
  end

  -- (where a warp leads: the map and the square of the warp it names; "the last map" (-1) nowhere)
  function R.destOf(wp)
    local dw = tonumber(wp.destWarp)
    if not dw or dw <= 0 or dw >= 255 then return nil end
    local all = R.maps()
    local dm = type(wp.destMap) == "string" and all and all[wp.destMap]
    local t = dm and dm.warps and dm.warps[dw]
    if not t then return nil end
    return wp.destMap, tonumber(t.x) or 0, tonumber(t.y) or 0
  end

  function R.links(ids)
    local a, b
    for _, id in ipairs(ids) do
      if id == SHIP[1] then a = id elseif id == SHIP[2] then b = id end
    end
    if a and b then return { { a = a, b = b, cost = SHIP[3], gate = G.SHIP.bit } } end
    return {}
  end

  function R.fingerprint(all)
    local n, warps, conns, objs = 0, 0, 0, 0
    for id, def in pairs(all) do
      if type(id) == "string" and type(def) == "table" then
        n = n + 1
        warps = warps + #(def.warps or {})
        objs = objs + #(def.objects or {})
        for _ in pairs(type(def.connections) == "table" and def.connections or {}) do conns = conns + 1 end
      end
    end
    return ("g2|%d:%d:%d:%d"):format(n, warps, conns, objs)
  end

  return R
end
