-- The 3D map's region model on the Game Boy games: Kanto (Red / Blue / Yellow), Johto and Kanto (Gold /
-- Silver / Crystal), each built to scale from the game's own outdoor maps, as src/map3d/world.lua builds
-- Gen 3's: every town and route put where its connections join it to its neighbours, each 16 px square
-- read for what it is (the collision, the tiles; Gen 2's colours from the map's own palettes), the doors
-- (where each leads) for the buildings. The same interface as src/map3d/model.lua, so src/map3d/scene.lua
-- and render.lua draw it unchanged. No Fly from it, no weather.
--
--   Mdl = map3d(host, Gd, deps)   deps.world: a src/map3d/world.lua made with no engine (its classes,
--                                 heights, unit and terrain); deps.place(mapId) -> its name (src/gb/play.lua)
--   (the interface: src/map3d/model.lua's; Mdl._build(id) -> the world, for the tests)

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

-- the regions, each from a town of its own (Gen 2's Kanto is its own world: no road joins the two)
local REGIONS = {
  [1] = { { id = "kanto", key = "map.region.kanto", root = "PALLET_TOWN" } },
  [2] = { { id = "johto", key = "map.region.johto", root = "NEW_BARK_TOWN" },
          { id = "kanto", key = "map.region.kanto", root = "PALLET_TOWN" } },
}
-- a door's kind, from the name of the map it leads into (the first that fits)
local KINDS = {
  { "INDIGO_PLATEAU_POKECENTER", "league" }, { "POKECENTER", "center" }, { "POKEMON_CENTER", "center" },
  { "SILPH_CO", "silph" }, { "POKEMON_TOWER", "ptower" }, { "POKEMON_MANSION", "mansion" }, { "POWER_PLANT", "plant" },
  { "DEPT_STORE", "store" }, { "_MART", "mart" }, { "_GYM", "gym" }, { "_LAB", "lab" }, { "LAB", "lab" },
  { "HOUSE", "house" }, { "GAME_CORNER", "corner" }, { "MUSEUM", "museum" }, { "SCHOOL", "school" },
  { "BIKE_SHOP", "shop" }, { "_SHOP", "shop" }, { "RADIO_TOWER", "silph" }, { "LIGHTHOUSE", "ptower" },
  { "TIN_TOWER", "ptower" }, { "BELL_TOWER", "ptower" }, { "SPROUT_TOWER", "ptower" }, { "BURNED_TOWER", "house" },
  { "HARBOR", "harbor" }, { "PORT", "harbor" }, { "DANCE_THEATRE", "contest" }, { "DANCE_THEATER", "contest" },
  { "_GATE", "gate" }, { "GATE", "gate" },
}
-- what a door into these is: a cave's mouth (no building round it)
local CAVES = { "CAVE", "TUNNEL", "MT_MOON", "MOUNT_MOON", "MT_MORTAR", "MOUNT_MORTAR", "ICE_PATH", "DARK_CAVE",
                "UNION_CAVE", "SLOWPOKE_WELL", "VICTORY_ROAD", "SEAFOAM", "DIGLETTS", "FOREST", "RUINS",
                "WHIRL_ISLAND", "DRAGONS_DEN", "TOHJO_FALLS", "SILVER_CAVE", "ROCK_TUNNEL", "UNDERGROUND", "CAVE" }
-- the towns' Gym Badges (by the Badge's name; Gen 1's an item "<NAME>BADGE")
local GYM_BADGE = {
  PEWTER_CITY = "BOULDER", CERULEAN_CITY = "CASCADE", VERMILION_CITY = "THUNDER", CELADON_CITY = "RAINBOW",
  FUCHSIA_CITY = "SOUL", SAFFRON_CITY = "MARSH", CINNABAR_ISLAND = "VOLCANO", VIRIDIAN_CITY = "EARTH",
  VIOLET_CITY = "ZEPHYR", AZALEA_TOWN = "HIVE", GOLDENROD_CITY = "PLAIN", ECRUTEAK_CITY = "FOG",
  OLIVINE_CITY = "MINERAL", CIANWOOD_CITY = "STORM", MAHOGANY_TOWN = "GLACIER", BLACKTHORN_CITY = "RISING",
}
local KANTO_BADGE = { BOULDER = true, CASCADE = true, THUNDER = true, RAINBOW = true, SOUL = true, MARSH = true,
                      VOLCANO = true, EARTH = true }
-- Gen 1's water tiles (the overworld tileset's sea and its shores' water)
local GEN1_WATER = { [0x14] = true, [0x32] = true, [0x3a] = true, [0x48] = true }

return function(H, Gd, deps)
  deps = deps or {}
  local engine = H.engine
  local gen = H.gen
  local Wd = deps.world
  local C, Hh, MT = Wd.C, Wd.H, Wd.MT
  local M = {}

  local function data() return Gd.data() end
  local function mapDefs()
    local d = data()
    return d and (gen == 2 and d.gen2Maps or d.maps) or nil
  end
  local function tilesetOf(def)
    local d = data()
    if not (d and def) then return nil end
    if gen == 2 then return d.gen2Tilesets and d.gen2Tilesets[def.tileset] or nil end
    return d.tilesets and d.tilesets[def.tileset] or nil
  end
  local function outdoor(def)
    if type(def) ~= "table" or type(def.blocks) ~= "table" or not tonumber(def.width) then return false end
    if gen == 2 then return def.environment == "TOWN" or def.environment == "ROUTE" end
    return def.tileset == "OVERWORLD" or def.tileset == "PLATEAU"
  end
  local function connOf(c)
    if type(c) ~= "table" then return nil end
    local id = c.mapId or c.map
    return type(id) == "string" and id or nil
  end

  -- ------- placing the maps: their connections, from the region's town (cells, its top-left at 0, 0)

  local groups = {}
  local function groupOf(rid)
    local all = mapDefs()
    if not all then return nil end
    local g = groups[rid]
    if g and g.all == all then return g end
    local desc
    for _, d in ipairs(REGIONS[gen]) do if d.id == rid then desc = d end end
    if not (desc and outdoor(all[desc.root])) then return nil end
    -- (a map another region already holds stays there)
    local taken = {}
    for _, d in ipairs(REGIONS[gen]) do
      if d.id == rid then break end
      local other = groupOf(d.id)
      if other then
        for id in pairs(other.byId) do taken[id] = true end
      end
    end
    if taken[desc.root] then return nil end
    local list, byId = {}, {}
    local function add(id, x, y)
      local def = all[id]
      local m = { id = id, def = def, x = x, y = y, w = def.width * 2, h = def.height * 2 }
      list[#list + 1], byId[id] = m, m
      return m
    end
    add(desc.root, 0, 0)
    local i = 1
    while list[i] do
      local cur = list[i]
      i = i + 1
      for dir, c in pairs(cur.def.connections or {}) do
        local id = connOf(c)
        local def = id and all[id]
        if def and not byId[id] and not taken[id] and outdoor(def) then
          local off = (tonumber(c.offset) or 0) * 2
          local w, h = def.width * 2, def.height * 2
          local x, y
          if dir == "north" then x, y = cur.x + off, cur.y - h
          elseif dir == "south" then x, y = cur.x + off, cur.y + cur.h
          elseif dir == "west" then x, y = cur.x - w, cur.y + off
          elseif dir == "east" then x, y = cur.x + cur.w, cur.y + off end
          if x then add(id, x, y) end
        end
      end
    end
    g = { all = all, list = list, byId = byId, desc = desc }
    groups[rid] = g
    return g
  end
  M._group = groupOf

  -- ------- each square: what it is

  local Perm = gen == 2 and engine("src.world.gen2.Permissions") or nil
  local Attrs = gen == 2 and engine("src.world.gen2.TileAttrs") or nil
  local Pal = gen == 2 and engine("src.world.gen2.Palettes") or nil
  local Gbc = engine("src.render.GbcPalette")
  local function blockAt(def, bx, by)
    if bx < 0 or by < 0 or bx >= def.width or by >= def.height then return def.borderBlock or 0 end
    return def.blocks[by * def.width + bx + 1] or 0
  end
  -- a square's four 8 px tiles (top-left, top-right, bottom-left, bottom-right)
  local function tilesOf(def, ts, cx, cy, out)
    local block = ts and ts.blocks and ts.blocks[blockAt(def, floor(cx / 2), floor(cy / 2)) + 1]
    local lx, ly = (cx % 2) * 2, (cy % 2) * 2
    for q = 0, 3 do
      local tx, ty = lx + q % 2, ly + floor(q / 2)
      out[q + 1] = block and block[ty * 4 + tx + 1] or 0
    end
    return out
  end
  local SLOT_GRAY, SLOT_RED, SLOT_GREEN, SLOT_WATER, SLOT_YELLOW, SLOT_BROWN, SLOT_ROOF = 1, 2, 3, 4, 5, 6, 7
  local function slotOf(ts, tile)
    if not (Attrs and ts) then return 1 end
    local ok, s = pcall(Attrs.paletteSlot, ts, tile)
    return ok and tonumber(s) or 1
  end
  local function inList(list, v)
    if type(list) ~= "table" then return false end
    for _, x in ipairs(list) do if x == v then return true end end
    return false
  end
  -- (Gen 2: a block with a roof's tiles in it is a building's, all of its walls)
  local roofed = setmetatable({}, { __mode = "k" })
  local function hasRoof(ts, id)
    local byTs = roofed[ts]
    if not byTs then byTs = {} roofed[ts] = byTs end
    local got = byTs[id]
    if got == nil then
      got = false
      local block = ts.blocks and ts.blocks[id + 1]
      for i = 1, block and 16 or 0 do
        local sl = slotOf(ts, block[i])
        if sl == SLOT_ROOF or sl == SLOT_RED then got = true break end
      end
      byTs[id] = got
    end
    return got
  end
  -- (Johto's big tree is drawn in the brown palette, as the cliffs are: told apart by its tiles, the
  -- crown's top, middle and foot down its middle)
  local bigTree = setmetatable({}, { __mode = "k" })
  local function isBigTree(ts, id)
    local byTs = bigTree[ts]
    if not byTs then byTs = {} bigTree[ts] = byTs end
    local got = byTs[id]
    if got == nil then
      local block = ts.blocks and ts.blocks[id + 1]
      got = block ~= nil and block[2] == 0x2c and block[6] == 0x3c and block[14] == 0x4c
      byTs[id] = got
    end
    return got
  end
  local tiles = {}
  local function classOf(def, ts, cx, cy)
    tilesOf(def, ts, cx, cy, tiles)
    if gen == 2 then
      local quad = ts and ts.collision and ts.collision[blockAt(def, floor(cx / 2), floor(cy / 2)) + 1]
      local coll = quad and quad[(cy % 2) * 2 + (cx % 2) + 1] or 0xff
      if Perm then
        if Perm.isWaterfall(coll) then return C.FALL end
        if Perm.isWater(coll) then return C.SEA end
        if Perm.isWarpCollision(coll) then return C.DOOR end
        if Perm.isCutTree(coll) or Perm.isHeadbuttTree(coll) then return C.TREE end
        if Perm.isGrass(coll) then return C.TALL end
        if Perm.isWalkable(coll) or Perm.isLand(coll) then
          return slotOf(ts, tiles[3]) == SLOT_YELLOW and C.SAND or C.GROUND
        end
      end
      -- (a wall: a building's where its block has a roof; a tree where its tiles are green -- its trunk
      -- may be brown --, rock where they're all brown, water where they're water; anything else low: a
      -- fence, a sign)
      if ts and hasRoof(ts, blockAt(def, floor(cx / 2), floor(cy / 2))) then return C.STRUCT end
      if ts and isBigTree(ts, blockAt(def, floor(cx / 2), floor(cy / 2))) then return C.TREE end
      local green, brown, water, gray = 0, 0, 0, 0
      for q = 1, 4 do
        local s = slotOf(ts, tiles[q])
        if s == SLOT_GREEN then green = green + 1 elseif s == SLOT_BROWN then brown = brown + 1
        elseif s == SLOT_WATER then water = water + 1 elseif s == SLOT_GRAY then gray = gray + 1 end
      end
      if green >= 2 then return C.TREE end
      if water >= 3 then return C.SEA end
      if brown >= 3 or gray >= 3 then return C.ROCK end
      return C.SMALL
    end
    -- (Gen 1: the square's lower-left tile decides, as the game's collision does)
    local t = tiles[3]
    if GEN1_WATER[t] then return C.SEA end
    if ts and inList(ts.doorTiles, t) then return C.DOOR end
    if ts and t == ts.grassTile then return C.TALL end
    if ts and inList(ts.walkable, t) then return C.GROUND end
    return C.TREE
  end

  -- the colours: Gen 2 the map's own palettes (by day), each tile its palette's; Gen 1 our own by what
  -- it is (its art has none)
  local CLASS_RGB = {
    [C.SEA] = { 64, 128, 212 }, [C.FALL] = { 200, 230, 255 }, [C.GROUND] = { 196, 214, 140 }, [C.SAND] = { 226, 206, 150 },
    [C.TALL] = { 96, 168, 84 }, [C.TREE] = { 52, 116, 64 }, [C.ROCK] = { 164, 128, 96 }, [C.STRUCT] = { 200, 196, 186 },
    [C.DOOR] = { 140, 110, 90 }, [C.BUILDING] = { 210, 104, 92 }, [C.SMALL] = { 214, 208, 196 },
  }
  local function setOf(def)
    if not (Pal and Gbc) then return nil end
    local d = data()
    local ok, set = pcall(Pal.bgSet, d and d.gen2Palettes, def, "DAY")
    return ok and type(set) == "table" and set or nil
  end
  local function rgbOf(set, slot)
    local colors = set and set[slot]
    if not colors then return nil end
    local ok, c1 = pcall(Gbc.color, colors, 1)
    local ok2, c2 = pcall(Gbc.color, colors, 2)
    if not (ok and ok2 and c1 and c2) then
      c1, c2 = colors[1], colors[2]
      if not (c1 and c2) then return nil end
    end
    local function ch(i) return (c1[i] * 0.45 + c2[i] * 0.55) end
    local r, g, b = ch(1), ch(2), ch(3)
    -- (colours given 0..1 or 0..31 come out 0..255)
    local top = max(r, g, b)
    if top <= 1.001 then r, g, b = r * 255, g * 255, b * 255
    elseif top <= 31.001 then r, g, b = r * 255 / 31, g * 255 / 31, b * 255 / 31 end
    return r, g, b
  end

  -- ------- the world

  local function kindOf(dest)
    dest = tostring(dest or "")
    for _, c in ipairs(CAVES) do if dest:find(c, 1, true) then return "cave" end end
    for _, k in ipairs(KINDS) do if dest:find(k[1], 1, true) then return k[2] end end
    return "house"
  end

  local function build(rid, pace)
    local g = groupOf(rid)
    if not g then return nil end
    local function rest() if pace and pace() and coroutine.running() then coroutine.yield() end end
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, m in ipairs(g.list) do
      x0, y0 = min(x0, m.x), min(y0, m.y)
      x1, y1 = max(x1, m.x + m.w), max(y1, m.y + m.h)
    end
    -- (a margin of sea round it)
    local PAD = 6
    x0, y0, x1, y1 = x0 - PAD, y0 - PAD, x1 + PAD, y1 + PAD
    local cols, rows = x1 - x0, y1 - y0
    local n = cols * rows
    local cls, mapIx, rgb = {}, {}, {}
    for k = 1, n do cls[k], mapIx[k] = C.SEA, 0 end
    local maps = {}
    for mi, m in ipairs(g.list) do
      local ts = tilesetOf(m.def)
      local set = setOf(m.def)
      local slotRgb = {}
      for cy = 0, m.h - 1 do
        local row = (m.y - y0 + cy) * cols + (m.x - x0) + 1
        for cx = 0, m.w - 1 do
          local k = row + cx
          if mapIx[k] == 0 then
            cls[k], mapIx[k] = classOf(m.def, ts, cx, cy), mi
            if set then
              -- (each of the square's four tiles its palette's colour)
              local base = (k - 1) * 12
              for q = 1, 4 do
                local s = slotOf(ts, tiles[q])
                local c = slotRgb[s]
                if c == nil then
                  local r, gg, b = rgbOf(set, s)
                  c = r and { r, gg, b } or false
                  slotRgb[s] = c
                end
                if c then rgb[base + q * 3 - 2], rgb[base + q * 3 - 1], rgb[base + q * 3] = c[1], c[2], c[3] end
              end
            end
          end
        end
        if cy % 8 == 0 then rest() end
      end
      maps[#maps + 1] = { id = m.id, def = m.def, x = m.x, y = m.y, w = m.w, h = m.h }
    end
    local byId = {}
    for i, m in ipairs(maps) do byId[m.id] = m; m.ix = i end
    -- (the doors: a warp into a map that isn't one of these; a building's walls round it)
    local doors, inFoot = {}, {}
    local function at(gx, gy)
      local i, j = gx - x0, gy - y0
      if i < 0 or j < 0 or i >= cols or j >= rows then return nil end
      return j * cols + i + 1
    end
    local function wall(k)
      local c = k and cls[k]
      return c == C.STRUCT or c == C.TREE or c == C.ROCK or c == C.SMALL or c == C.DOOR
    end
    for _, m in ipairs(g.list) do
      for _, w in ipairs(m.def.warps or {}) do
        local dest = w.destMap or w.dest or w.map
        local wx, wy = tonumber(w.x), tonumber(w.y)
        if type(dest) == "string" and wx and wy and not g.byId[dest] then
          local gx, gy = m.x + wx, m.y + wy
          local k = at(gx, gy)
          if k then
            local kind = kindOf(dest)
            local d = { x = gx, y = gy, k = k, map = m.id, dest = dest, kind = kind }
            if kind ~= "cave" and not inFoot[k] then
              -- (its front: along the door's row both ways, then up while those squares are walls)
              local a, b = gx, gx
              for _ = 1, 6 do
                local kk = at(a - 1, gy)
                if wall(kk) and cls[kk] ~= C.TREE or (gen == 1 and wall(kk)) then a = a - 1 else break end
              end
              for _ = 1, 6 do
                local kk = at(b + 1, gy)
                if wall(kk) and cls[kk] ~= C.TREE or (gen == 1 and wall(kk)) then b = b + 1 else break end
              end
              local top = gy
              for _ = 1, 6 do
                local whole = true
                for x = a, b do
                  local kk = at(x, top - 1)
                  if not wall(kk) or (gen == 2 and cls[kk] == C.TREE) then whole = false break end
                end
                if not whole then break end
                top = top - 1
              end
              if b - a >= 1 and gy - top >= 1 then
                d.foot = { x0 = a, y0 = top, x1 = b + 1, y1 = gy + 1 }
                for y = top, gy do
                  for x = a, b do
                    local kk = at(x, y)
                    if kk then
                      inFoot[kk] = true
                      if cls[kk] ~= C.DOOR then cls[kk] = C.BUILDING end
                    end
                  end
                end
              end
            end
            doors[#doors + 1] = d
          end
        end
      end
      rest()
    end
    -- (the heights: the land flat, rock a step up, a building no door of ours stands for a block of its
    -- own, the sea's bed under its surface)
    local h, ws, deck = {}, {}, {}
    for k = 1, n do
      local c = cls[k]
      if c == C.SEA or c == C.FALL then
        ws[k], h[k] = 0, Hh.SEA_BED
      else
        ws[k] = false
        h[k] = Hh.GROUND + (c == C.ROCK and Hh.LEVEL * 2 or (c == C.STRUCT and Hh.LEVEL * 1.4 or 0))
      end
    end
    rest()
    local function art(k, q)
      local base = (k - 1) * 12 + (q or 0) * 3
      local r = rgb[base + 1]
      if r then
        local c = cls[k]
        if c == C.SEA then return r * 0.8, rgb[base + 2] * 0.9, rgb[base + 3] end
        return r, rgb[base + 2], rgb[base + 3]
      end
      local c = CLASS_RGB[cls[k]] or CLASS_RGB[C.GROUND]
      -- (a little each way, square by square, so a field isn't one flat colour)
      local v = ((k * 7 + (q or 0) * 13) % 11 - 5) * 1.6
      return max(0, min(255, c[1] + v)), max(0, min(255, c[2] + v)), max(0, min(255, c[3] + v))
    end
    return { maps = maps, byId = byId, x0 = x0, y0 = y0, cols = cols, rows = rows, cls = cls, mapIx = mapIx,
             doors = doors, h = h, ws = ws, deck = deck, art = art }
  end
  M._build = function(id) return build(id) end

  -- ------- the places: the towns, routes and landmarks, each its maps

  local function titled(s) return Gd.title(tostring(s or ""):gsub("\n", " ")) end
  local function placeKey(m)
    if gen == 2 then return "lm" .. tostring(m.def.landmark or m.id) end
    return m.id
  end
  local function placeKind(m, name)
    local id = m.id
    if gen == 2 then
      if m.def.environment == "TOWN" then return "town" end
    elseif id:find("_TOWN$") or id:find("_CITY$") or id:find("PLATEAU$") or id:find("_ISLAND$") then
      return "town"
    end
    if id:find("^ROUTE_") or tostring(name):upper():find("^ROUTE") then return "route" end
    return "landmark"
  end
  local function tierOf(id)
    if id:find("CITY") or id:find("PLATEAU") then return 3 end
    if id:find("ISLAND") then return 2 end
    return 1
  end

  local function placesOf(world)
    local byKey, list = {}, {}
    for _, m in ipairs(world.maps) do
      local key = placeKey(m)
      local p = byKey[key]
      if not p then
        local name = deps.place and deps.place(m.id) or titled(m.id:gsub("_", " "))
        p = { id = key, sym = m.id, name = name, kind = placeKind(m, name), cells = {}, maps = {} }
        byKey[key] = p
        list[#list + 1] = p
      end
      p.maps[m.id] = true
      p.cells[#p.cells + 1] = { m.x / MT, m.y / MT, m.w / MT, m.h / MT }
    end
    for _, d in ipairs(world.doors) do
      local m = world.byId[d.map]
      local p = m and byKey[placeKey(m)]
      if p then
        if d.kind == "center" then p.center = true end
        if d.kind == "mart" or d.kind == "store" then p.mart = true end
        if d.kind == "gym" then p.hasGym = true end
      end
    end
    for _, p in ipairs(list) do
      local sx, sz, sw = 0, 0, 0
      local c1 = p.cells[1]
      p.x0, p.z0, p.x1, p.z1 = c1[1], c1[2], c1[1] + c1[3], c1[2] + c1[4]
      for _, c in ipairs(p.cells) do
        local a = c[3] * c[4]
        sx, sz, sw = sx + (c[1] + c[3] / 2) * a, sz + (c[2] + c[4] / 2) * a, sw + a
        p.x0, p.z0 = min(p.x0, c[1]), min(p.z0, c[2])
        p.x1, p.z1 = max(p.x1, c[1] + c[3]), max(p.z1, c[2] + c[4])
      end
      p.x, p.z = sx / sw, sz / sw
      p.tier = p.kind == "town" and tierOf(p.sym) or nil
      local badge = GYM_BADGE[p.sym]
      if p.hasGym and badge then
        p.badge = badge
        p.badgeName = Gd.title(badge) .. " Badge"
      end
    end
    table.sort(list, function(a, b)
      if a.kind ~= b.kind then return a.kind == "town" end
      if a.z ~= b.z then return a.z < b.z end
      return a.x < b.x
    end)
    return list
  end

  -- ------- the interface (src/map3d/model.lua's)

  local built, jobs, progress = {}, {}, {}
  local slice = { start = 0, budget = 0.004, sync = false }
  local function clock() return love and love.timer and love.timer.getTime() or os.clock() end
  local function pace() return not slice.sync and clock() - slice.start > slice.budget end
  local function key(id) return tostring(H.gameId()) .. ":" .. tostring(id) end

  function M.regions() return REGIONS[gen] end
  function M.toScale() return mapDefs() ~= nil end
  function M.storm() return nil end
  function M.weather() return nil end
  function M.weatherData() return nil end
  function M.flyCheck() return nil, "none" end
  function M.pickArgs() return nil end

  local function regionOf(id, background)
    local p = progress[key(id)] or { m = 0 }
    progress[key(id)] = p
    local world = build(id, background and pace or nil)
    if not world then return nil end
    p.m = 0.8
    local t, step = Wd.terrain(world, background and pace or nil)
    local places = placesOf(world)
    local desc
    for _, d in ipairs(REGIONS[gen]) do if d.id == id then desc = d end end
    local region = { id = id, key = desc and desc.key, family = H.family, terrain = t, places = places,
                     x0 = world.x0 / MT, z0 = world.y0 / MT, w = world.cols / MT, h = world.rows / MT, step = step,
                     fromPicture = true, world = world, classes = C, heights = Hh, unit = MT }
    for _, pl in ipairs(places) do pl.y = M.heightAt(region, pl.x, pl.z) end
    return region
  end

  function M.region(id, background)
    local k = key(id)
    if built[k] then return built[k] end
    local job = jobs[k]
    if job and not background then
      slice.sync = true
      while coroutine.status(job) ~= "dead" do
        local ok, err = coroutine.resume(job)
        if not ok then
          if deps.log then deps.log("the map's build failed: %s", tostring(err)) end
          break
        end
      end
      slice.sync = false
      jobs[k] = nil
      if built[k] then return built[k] end
    end
    local ok, region = pcall(regionOf, id, background)
    progress[k] = nil
    if not ok then
      if deps.log then deps.log("the map's build failed: %s", tostring(region)) end
      return nil
    end
    built[k] = region
    return region
  end
  function M.prepare(id)
    local k = key(id)
    if built[k] or jobs[k] then return end
    jobs[k] = coroutine.create(function() return M.region(id, true) end)
  end
  function M.step(budget)
    local more = false
    for k, co in pairs(jobs) do
      slice.start, slice.budget, slice.sync = clock(), budget or 0.004, false
      local ok, err = coroutine.resume(co)
      if not ok and deps.log then deps.log("the map's build failed: %s", tostring(err)) end
      if coroutine.status(co) == "dead" then jobs[k] = nil else more = true end
    end
    return more
  end
  function M.building(id) return jobs[key(id)] ~= nil end
  function M.ready(id) return built[key(id)] ~= nil end
  function M.progress(id)
    local r = built[key(id)]
    if r then return 1, nil end
    local p = progress[key(id)]
    return p and p.m or 0, true
  end
  function M.forget(id) built[key(id)] = nil end

  function M.heightAt(region, x, z)
    local t = region.terrain
    local i = floor((x - region.x0) / region.step + 0.5)
    local j = floor((z - region.z0) / region.step + 0.5)
    i, j = max(0, min(t.cols - 1, i)), max(0, min(t.rows - 1, j))
    return max(0, t.h[j * t.cols + i + 1])
  end

  -- ------- what the save says

  local function badgeOwned(s, name)
    if not (s and name) then return false end
    if gen == 1 then return (tonumber(s.inventory and s.inventory[name .. "BADGE"]) or 0) > 0 end
    local p = s.player or {}
    local set = KANTO_BADGE[name] and p.kantoBadges or p.badges
    return type(set) == "table" and set[name] == true
  end
  -- (Gen 2: a town visited, by its fly point; Gen 1: the save's own towns)
  local function visitedMaps(s)
    local out = {}
    if not s then return out end
    if gen == 1 then
      for id, v in pairs(s.visited or {}) do if v then out[id] = true end end
      return out
    end
    local d = data()
    local FM = engine("src.world.gen2.FieldMoves")
    local spawns = d and d.gen2Landmarks and d.gen2Landmarks.spawns
    for name, sp in pairs(type(spawns) == "table" and spawns or {}) do
      if type(sp) == "table" and sp.map then
        local ok, yes = pcall(FM and FM.hasVisitedSpawn or error, s, name)
        if ok and yes then out[sp.map] = true end
      end
    end
    return out
  end
  function M.live(region, s)
    if not region then return end
    local seen = visitedMaps(s)
    for _, p in ipairs(region.places) do
      p.shown = true
      p.visited = false
      for id in pairs(p.maps or {}) do if seen[id] then p.visited = true end end
      p.canFly = false
      p.badgeOwned = badgeOwned(s, p.badge)
    end
  end
  function M.available(s, id)
    if id ~= "kanto" or gen == 1 then return true end
    -- (Gen 2's Kanto: once the player's been there)
    local g = groupOf("kanto")
    if not g then return false end
    local seen = visitedMaps(s)
    for mid in pairs(g.byId) do if seen[mid] then return true end end
    local here = M.regionHere(s)
    return here == "kanto"
  end

  -- where the player stands: the live map and square, or (indoors) the last outdoor square
  local function where(s)
    local game = H.game()
    if gen == 2 then
      local w = game and game.world
      if w and w.map and w.player then
        local id, x, y = w.map.id, w.player.cellX, w.player.cellY
        local lo = w.lastOutdoor
        return id, x, y, lo
      end
      local p = s and s.position
      return p and (p.map or p.mapId), p and p.x, p and p.y, s and s.lastOutdoor
    end
    local ow = game and game.overworld
    if ow and ow.map and ow.player then
      return ow.map.id, ow.player.cellX, ow.player.cellY, ow.lastOutdoor or (s and s.lastOutdoor)
    end
    local p = s and s.player
    return p and p.map, p and p.x, p and p.y, s and s.lastOutdoor
  end
  function M.regionHere(s)
    local id, _, _, lo = where(s)
    for _, d in ipairs(REGIONS[gen]) do
      local g = groupOf(d.id)
      if g and (g.byId[id] or (type(lo) == "table" and g.byId[lo.id or lo.map])) then return d.id end
    end
    return REGIONS[gen][1].id
  end
  function M.player(s)
    local id, x, y, lo = where(s)
    if not id then return nil end
    for _, d in ipairs(REGIONS[gen]) do
      local g = groupOf(d.id)
      local m = g and g.byId[id]
      if m and tonumber(x) then return d.id, (m.x + x + 0.5) / MT, (m.y + y + 0.5) / MT end
      local lm = g and type(lo) == "table" and g.byId[lo.id or lo.map]
      if lm then return d.id, (lm.x + (tonumber(lo.x) or 0) + 0.5) / MT, (lm.y + (tonumber(lo.y) or 0) + 0.5) / MT end
    end
    return nil
  end

  return M
end
