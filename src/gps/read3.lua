-- The GPS's map reader on FireRed / LeafGreen / Ruby / Sapphire / Emerald (src/gps/graph.lua's reader): a
-- map's tiles from its layout (collision, behaviours, elevations; a layout the engine hasn't loaded read here
-- and not kept: the engine keeps every layout it loads, some 30 MB for all of them), its warps as
-- src/core/game3/collision.lua fires them, its connections, and Mt. Chimney's cable car. Cut trees, Rock
-- Smash rocks and Strength boulders are objects in these games, not tiles: the obstacles.
--
--   R = read3(engine, deps, Gw)   deps: maps() -> the game's map definitions ; game() -> the game (warps'
--                                 destinations)

local floor = math.floor

local KEEP = 6            -- layouts read here, kept at once
-- maps never walked through: under the sea, unused, the link rooms, secret bases
local SKIP = { "UNDERWATER", "PROTOTYPE", "SECRET_BASE", "UNION_ROOM", "TRADE_CENTER", "RECORD_CORNER",
               "BATTLE_COLOSSEUM", "INSIDE_OF_TRUCK" }
local CONN_DIR = { north = 1, south = 2, west = 3, east = 4 }
-- the rides a script makes, not a warp (both ways; the maps' names end so): Mt. Chimney's cable car
local LINKS = { { "ROUTE112_CABLE_CAR_STATION", "MT_CHIMNEY_CABLE_CAR_STATION", 12 } }
local function linked(id)
  for _, l in ipairs(LINKS) do
    if id:sub(-#l[1]) == l[1] or id:sub(-#l[2]) == l[2] then return true end
  end
  return false
end
-- a ledge's collision (0xA0-0xA7, its low three bits) -> the ways it's hopped (up 1, down 2, left 4, right 8)
local LEDGE_HOPS = { [0] = 8, 4, 1, 2, 2 + 8, 2 + 4, 1 + 8, 1 + 4 }
local HM_CUT, HM_SMASH, HM_STRENGTH = 1, 2, 4

return function(engine, deps, Gw)
  local WALL, LAND, WATER, LEDGE, WARP = Gw.WALL, Gw.LAND, Gw.WATER, Gw.LEDGE, Gw.WARP
  local breathe = Gw.breathe
  local R = {
    HMS = { { bit = HM_CUT, key = "CUT", word = "map.hm.cut" },
            { bit = HM_SMASH, key = "ROCK_SMASH", word = "map.hm.smash" },
            { bit = HM_STRENGTH, key = "STRENGTH", word = "map.hm.strength" } },
  }
  local Collision, Conn, P, IS
  function R.ready()
    Collision = Collision or engine("src.core.game3.collision")
    Conn = Conn or engine("src.core.game3.connections")
    -- (the collision bytes' meaning: the engine's own, the module every generation may read)
    P = P or engine("src.core.CollPermissions")
    IS = IS or engine("src.core.game3.scripting.interaction_scripts")
    return (Collision and Conn and P) and true or false
  end
  function R.maps() return deps.maps and deps.maps() or nil end

  -- ------- a map's layout: the engine's when it's loaded it; else read here, not kept

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
      while #privateOrder > KEEP do private[table.remove(privateOrder, 1)] = nil end
    end
    return got[1], got[2]
  end
  R.layoutOf = layoutOf
  function R.forget()
    for k in pairs(private) do private[k] = nil end
    for i = #privateOrder, 1, -1 do privateOrder[i] = nil end
  end

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
  R.fires = fires

  function R.build(id, def)
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

  -- ------- which maps, and how they join

  local function skipped(id)
    for _, s in ipairs(SKIP) do if id:find(s, 1, true) then return true end end
    return false
  end
  -- (a map worth walking through: joined to others by connections, or by warps to two places or more)
  function R.included(id, def)
    if skipped(id) then return false end
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

  function R.conns(def)
    local out = {}
    local okC, conns = pcall(Conn.each, def)
    if not (okC and type(conns) == "table") then return out end
    for _, c in ipairs(conns) do
      local d = CONN_DIR[c.dir]
      if d then out[#out + 1] = { dir = d, map = c.map, conn = c } end
    end
    return out
  end
  -- (where stepping off at x, y lands, and what that tile is)
  function R.landing(c, x, y)
    local all = R.maps()
    local destDef = all and all[c.map]
    if not destDef then return nil end
    local L, dest = layoutOf(c.map, destDef)
    if not L then return nil end
    local behs = IS and IS.behaviors and IS.behaviors[destDef.pair or L.pair]
    local okL, lx, ly = pcall(Collision.connectionLanding, dest, c.conn, Gw.DIR_NAME[c.dir], x, y)
    if not (okL and lx) then return nil end
    return lx, ly, (classify(dest, L, behs, lx, ly))
  end

  -- (where a warp leads: the map and the tile, or nil for one that goes back where the player came from)
  function R.destOf(wp)
    if tonumber(wp.mapNum) == 0x7F then return nil end
    local dm = wp.destMap or wp.map
    if type(dm) == "string" and dm:find("DYNAMIC", 1, true) then return nil end
    local ok, m, x, y = pcall(Collision.resolveWarpDestination, deps.game and deps.game() or nil, wp)
    if ok and type(m) == "string" then return m, tonumber(x) or 0, tonumber(y) or 0 end
    return nil
  end

  function R.links(ids)
    local out = {}
    for _, l in ipairs(LINKS) do
      local a, b
      for _, id in ipairs(ids) do
        if id:sub(-#l[1]) == l[1] then a = id elseif id:sub(-#l[2]) == l[2] then b = id end
      end
      if a and b then out[#out + 1] = { a = a, b = b, cost = l[3], gate = 0 } end
    end
    return out
  end

  function R.fingerprint(all)
    local n, warps, conns = 0, 0, 0
    for id, def in pairs(all) do
      if type(id) == "string" and type(def) == "table" then
        n = n + 1
        warps = warps + #(def.warps or {})
        conns = conns + #(def.connections or {})
      end
    end
    return ("g3|%d:%d:%d"):format(n, warps, conns)
  end

  return R
end
