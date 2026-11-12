-- Standalone: luajit mods/woob_os/tests/world3d_test.lua [game] (from the gen1recomp root).
--
-- The 3D map's world built to scale (src/map3d/world.lua), on a little Hoenn of its own: a town with
-- a house and the sea at its foot; a route joined to its north by a connection, a band of rock across
-- it with a field and a lake up on top; a route no connection reaches, put where its gatehouse's door
-- leads; a gap between the maps for the borders to fill. The engine's own modules where they work
-- headless (connections, behaviours), stand-ins for the tile art and the behaviours of our tiles.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GAME = arg[1] or "emerald"
local noop = function() end
love = { timer = { getTime = os.clock }, graphics = setmetatable({}, { __index = function() return noop end }) }
require("src.core.GameVersion").set(GAME)

local MB = require("src.core.game3.mb")
local MOD = "mods/woob_os"

-- ------- the tiles: their metatiles (mid), their behaviours and their art
local GROUND, SEA, ROCK, POND, TREE, WALL, ROCKY = 1, 2, 6, 9, 7, 8, 4
local BEH = { [SEA] = MB.id("OCEAN_WATER"), [POND] = MB.id("POND_WATER"), [ROCKY] = MB.id("MOUNTAIN_TOP") }
local function art(green, blue, rock, r, g, b)
  return { q = { r, g, b, r, g, b, r, g, b, r, g, b }, green = green, blue = blue, rock = rock, over = 0, r = r, g = g, b = b }
end
local ART = {
  [GROUND] = art(0.3, 0, 0, 120, 190, 110), [SEA] = art(0, 0.9, 0, 40, 90, 200), [ROCK] = art(0, 0, 0.9, 150, 110, 80),
  [POND] = art(0, 0.9, 0, 60, 120, 220), [TREE] = art(0.7, 0, 0, 30, 110, 40), [WALL] = art(0, 0, 0.1, 230, 220, 200),
  [ROCKY] = art(0, 0, 0.6, 190, 150, 110),
}

-- a layout: w x h, cell(x, y) -> coll, mid; past its edges its border (trees unless said)
local function layout(w, h, cell, border)
  local L = { width = w, height = h, trueWidth = w, trueHeight = h, pair = "test" }
  function L:collAt(x, y)
    if x < 0 or y < 0 or x >= w or y >= h then return 255 end
    return (cell(x, y))
  end
  function L:midAt(x, y)
    if x < 0 or y < 0 or x >= w or y >= h then return border or TREE end
    local _, m = cell(x, y)
    return m
  end
  function L:elevAt() return 3 end
  return L
end

-- Littleroot: ground; a house (rows 4-7, cols 4-8; its door at 6, 8) and another built against it
-- (cols 9-13, its door at 11, 8); the sea along its foot
local town = layout(20, 20, function(x, y)
  if y >= 17 then return 41, SEA end
  if (x == 6 or x == 11) and y == 8 then return 113, GROUND end
  if x >= 4 and x <= 13 and y >= 4 and y <= 8 then return 7, WALL end
  return 0, GROUND
end)
-- Route 101: a field up top (rows 0-9, a lake in it), a band of rock (rows 10-15), the lowland below;
-- a door on its east edge to the gatehouse
local route = layout(20, 40, function(x, y)
  if y >= 10 and y <= 15 then return 7, ROCK end
  if y >= 2 and y <= 5 and x >= 8 and x <= 11 then return 41, POND end
  if x == 19 and y == 30 then return 113, GROUND end
  return 0, GROUND
end)
-- Route 102: off on its own, its door to the gatehouse on its west edge
local away = layout(16, 16, function(x, y)
  if x == 0 and y == 8 then return 113, GROUND end
  return 0, GROUND
end)

local maps = {
  EM_LITTLEROOT_TOWN = { mapType = 1, midLayout = town, pair = "test", regionMapSectionId = 0,
    connections = { { dir = "north", map = "EM_ROUTE101", offset = 0 } },
    warps = { { x = 6, y = 8, destMap = "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F", destWarp = 1 },
              { x = 11, y = 8, destMap = "EM_LITTLEROOT_TOWN_MAYS_HOUSE_1F", destWarp = 1 } } },
  EM_ROUTE101 = { mapType = 3, midLayout = route, pair = "test", regionMapSectionId = 16,
    connections = { { dir = "south", map = "EM_LITTLEROOT_TOWN", offset = 0 } },
    warps = { { x = 19, y = 30, destMap = "EM_ROUTE102_GATE", destWarp = 1 } } },
  EM_ROUTE102 = { mapType = 3, midLayout = away, pair = "test", regionMapSectionId = 17, connections = {},
    warps = { { x = 0, y = 8, destMap = "EM_ROUTE102_GATE", destWarp = 2 } } },
  -- (the gatehouse: in from Route 101 at 0, 4; out to Route 102 at 9, 4)
  EM_ROUTE102_GATE = { mapType = 8, warps = { { x = 0, y = 4, destMap = "EM_ROUTE101", destWarp = 1 },
                                              { x = 9, y = 4, destMap = "EM_ROUTE102", destWarp = 1 } } },
  EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F = { mapType = 8, warps = { { x = 3, y = 7, destMap = "EM_LITTLEROOT_TOWN", destWarp = 1 } } },
  EM_LITTLEROOT_TOWN_MAYS_HOUSE_1F = { mapType = 8, warps = { { x = 3, y = 7, destMap = "EM_LITTLEROOT_TOWN", destWarp = 2 } } },
}

local function engine(name)
  if name == "src.core.game3.scripting.interaction_scripts" then return { behaviors = { test = BEH } } end
  if name == "src.ui.game3.rse.mapsec" then return nil end
  local ok, m = pcall(require, name)
  return ok and m or nil
end
-- (the tileset's own pixels, for the map's art at full size: the ground's bottom layer all colour 1, its
-- top layer colour 2 in its first pixel; the wall see-through in both)
local PIX = { under = string.rep("\1", 256) .. string.rep("\0", 256), uOff = 1, uSlot = { [GROUND] = 0, [WALL] = 1 },
              over = "\2" .. string.rep("\0", 255), oOff = 1, oSlot = { [GROUND] = 0 },
              LR = { [1] = 10, [2] = 200 }, LG = { [1] = 20, [2] = 100 }, LB = { [1] = 30, [2] = 50 } }
local Wd = assert(loadfile(MOD .. "/src/map3d/world.lua"))()(engine, {
  maps = function() return maps end, art = function() return ART end, pixels = function() return PIX end })
local C, H = Wd.C, Wd.H

-- ------- placing the maps

local world = Wd.build()
T.check(world ~= nil, "the world builds")
local A, B, Cm = world.byId.EM_LITTLEROOT_TOWN, world.byId.EM_ROUTE101, world.byId.EM_ROUTE102
T.check(A and A.x == 0 and A.y == 0 and A.how == "joined", "Littleroot first, at 0, 0")
T.check(B and B.x == 0 and B.y == -40 and B.how == "joined", "Route 101 due north, by its connection")
T.check(Cm and Cm.how == "gate", "Route 102 placed through its gatehouse (" .. tostring(Cm and Cm.how) .. ")")
-- (Route 102's door where Route 101's door is, the gatehouse's width on: 9 tiles east)
T.check(Cm and Cm.x + 0 == B.x + 19 + 9 and Cm.y + 8 == B.y + 30,
  "its door the gatehouse's width from Route 101's (" .. tostring(Cm and Cm.x) .. ", " .. tostring(Cm and Cm.y) .. ")")
T.check(world.cols > 20 and world.rows > 60, "the world's box: all of them and a margin")

local function k(gx, gy) return (gy - world.y0) * world.cols + (gx - world.x0) + 1 end

-- ------- each tile

T.eq(world.cls[k(10, 18)], C.SEA, "the sea")
T.eq(world.cls[k(10, 12)], C.GROUND, "the town's ground")
T.eq(world.cls[k(5, -28)], C.ROCK, "Route 101's band of rock")
T.eq(world.cls[k(9, -37)], C.POND, "the lake up on the field")
local door, door2
for _, d in ipairs(world.doors) do
  if d.map == "EM_LITTLEROOT_TOWN" and d.x == 6 then door = d end
  if d.map == "EM_LITTLEROOT_TOWN" and d.x == 11 then door2 = d end
end
T.check(door and door.kind == "house" and door.x == 6 and door.y == 8, "the house's door, a house's kind")
local f = door and door.foot
T.check(f and f.x0 == 4 and f.y0 == 4 and f.x1 == 9 and f.y1 == 9,
  "its footprint: the block above and beside the door (" .. (f and (f.x0 .. "," .. f.y0 .. "-" .. f.x1 .. "," .. f.y1) or "-") .. ")")
T.eq(world.cls[k(5, 5)], C.BUILDING, "the house's tiles a building")
local f2 = door2 and door2.foot
T.check(f2 and not door2.shares and f2.x0 == 9 and f2.x1 == 14,
  "the house built against it a building of its own, from halfway between their doors (" ..
  (f2 and (f2.x0 .. "-" .. f2.x1) or (door2 and door2.shares and "shares" or "-")) .. ")")
-- (the gap east of Route 101, closed in by Route 102 and the town: filled from a border)
local filled = 0
for kk = 1, world.cols * world.rows do if world.filled[kk] then filled = filled + 1 end end
T.check(filled > 0, "the gaps filled from the maps' borders (" .. filled .. " tiles)")

-- ------- the tiles' own art, full size (the map's near view)
do
  local px, pi = {}, world.pix[k(10, 12)]
  local ok = world.tile(pi, GROUND, px)
  T.check(ok and #px == 768, "a tile's art: 16 x 16, three numbers a pixel (" .. #px .. ")")
  T.check(px[1] == 200 and px[2] == 100 and px[3] == 50 and px[4] == 10 and px[5] == 20 and px[6] == 30
    and px[766] == 10, "the top layer over the bottom, the bottom where the top is see-through")
  T.check(world.tile(pi, WALL, px) and px[1] == 230 and px[2] == 220 and px[3] == 200,
    "see-through in both layers: the tile's mean colour")
  T.check(world.tile(pi, ROCK, px) == false and world.tile(99, GROUND, px) == false,
    "no art for a metatile or a tileset it doesn't have")
end

-- ------- heights

local hTown, hField, hLow = world.h[k(10, 12)], world.h[k(3, -38)], world.h[k(3, -10)]
T.check(math.abs(hTown - H.GROUND) < 1e-6, "the town at the land's level (" .. hTown .. ")")
T.check(world.ws[k(10, 18)] == 0 and world.h[k(10, 18)] < 0, "the sea: its surface at 0, its bed under it")
T.check(world.ws[k(10, 12)] == false, "no water over the town")
T.check(hField > hLow + 0.1, ("the field up past the rock is higher than the lowland below it (%.3f, %.3f)"):format(hField, hLow))
local rockSouth, rockNorth = world.h[k(5, -25)], world.h[k(5, -30)]
T.check(rockNorth >= rockSouth, "the rock rises going north")
local lake = world.ws[k(9, -37)]
T.check(lake and lake > 0 and lake < hField, ("the lake held up on the field, just under it (%s, %.3f)"):format(tostring(lake), hField))
local same = true
for x = 0, 6 do if world.h[k(x, -38)] ~= hField then same = false end end
T.check(same, "the field is flat")

-- ------- the region's outline

local t, step = Wd.terrain(world)
T.check(t.cols * 4 >= world.cols and t.rows * 4 >= world.rows and step == 4 / Wd.MT, "the coarse terrain: every 4 tiles")
local seen = false
for q = 1, t.cols * t.rows do if t.h[q] > hLow + 0.05 then seen = true end end
T.check(seen, "the coarse terrain keeps the high ground")
world.release()
T.check(world.cls == nil and world.released and #world.doors > 0 and world.byId.EM_ROUTE101,
  "released: the tiles let go, the maps and doors kept")

-- ------- the noise for the filled land's edge: smooth, 0..1
local lo, hi, jump = 1, 0, 0
local prev = Wd.noise(0, 7, 15)
for x = 1, 200 do
  local v = Wd.noise(x, 7, 15)
  lo, hi, jump = math.min(lo, v), math.max(hi, v), math.max(jump, math.abs(v - prev))
  prev = v
end
T.check(lo >= 0 and hi <= 1 and hi - lo > 0.3 and jump < 0.2, "the noise: 0..1, varied, smooth")

-- ------- FireRed / LeafGreen: Kanto and a Sevii island, each a world of its own
--   Pallet Town: a stone wall across it (rows 6-7), the sea at its foot. Route 1 to its north: a ledge
--   across it (row 20); a strait (rows 8-12) a plank bridge crosses (x 10). Saffron City's stand-in
--   (10 x 10) east of Route 1, the real city 14 x 14 round it (offset 2, 2) with the Mart's door and a
--   gatehouse's out past the stand-in. One Island (Sevii 1-3): its mountain cut off by its north edge,
--   the sea round it.
local PLANK = 10
ART[PLANK] = art(0, 0, 0.2, 170, 120, 70)
local pallet = layout(20, 20, function(x, y)
  if y >= 17 then return 41, SEA end
  if y == 6 or y == 7 then return 7, ROCK end
  return 0, GROUND
end)
local route1 = layout(20, 30, function(x, y)
  if y >= 8 and y <= 12 then
    if x == 10 then return 0, PLANK end
    return 41, SEA
  end
  if y == 20 then return 163, GROUND end
  return 0, GROUND
end)
local function saffronCell(x, y)
  if x >= 3 and x <= 6 and y >= 2 and y <= 4 then return 7, WALL end
  if x == 5 and y == 5 then return 113, GROUND end
  return 0, GROUND
end
local saffronStandIn = layout(10, 10, saffronCell)
local saffronReal = layout(14, 14, function(x, y)
  if x >= 2 and y >= 2 and x < 12 and y < 12 then return saffronCell(x - 2, y - 2) end
  if x == 0 and y == 7 then return 113, GROUND end
  return 7, TREE
end)
local island = layout(16, 16, function(x, y)
  if y <= 3 then return 7, ROCK end
  if x >= 2 and x <= 13 and y <= 11 then return 0, GROUND end
  return 41, SEA
end, SEA)
local frMaps = {
  FR_PALLET_TOWN = { mapType = 1, midLayout = pallet, pair = "test", regionMapSectionId = 88,
    connections = { { dir = "north", map = "FR_ROUTE_1", offset = 0 } }, warps = {} },
  FR_ROUTE_1 = { mapType = 3, midLayout = route1, pair = "test", regionMapSectionId = 89,
    connections = { { dir = "south", map = "FR_PALLET_TOWN", offset = 0 },
                    { dir = "east", map = "FR_SAFFRON_CITY_CONNECTION", offset = 0 } }, warps = {} },
  FR_SAFFRON_CITY_CONNECTION = { mapType = 1, midLayout = saffronStandIn, pair = "test", regionMapSectionId = 90,
    connections = { { dir = "west", map = "FR_ROUTE_1", offset = 0 } }, warps = {} },
  FR_SAFFRON_CITY = { mapType = 1, midLayout = saffronReal, pair = "test", regionMapSectionId = 90, connections = {},
    warps = { { x = 7, y = 7, destMap = "FR_SAFFRON_CITY_MART", destWarp = 1 },
              { x = 0, y = 7, destMap = "FR_ROUTE_7_EAST_ENTRANCE", destWarp = 1 } } },
  FR_SAFFRON_CITY_MART = { mapType = 8, warps = {} },
  FR_ROUTE_7_EAST_ENTRANCE = { mapType = 8, warps = {} },
  SEVII_ONE_ISLAND = { mapType = 1, midLayout = island, pair = "test", regionMapSectionId = 101, connections = {}, warps = {} },
}
local Fr = assert(loadfile(MOD .. "/src/map3d/world.lua"))()(engine, {
  maps = function() return frMaps end, art = function() return ART end, layouts = function() return {} end,
  pictureOf = function(sec) return sec == 101 and 1 or 0 end })
local kanto = Fr.build({ region = "kanto" })
T.check(kanto and kanto.byId.FR_PALLET_TOWN and kanto.byId.FR_PALLET_TOWN.x == 0, "Kanto builds, from Pallet Town")
T.check(kanto and kanto.byId.SEVII_ONE_ISLAND == nil, "Kanto has none of the Sevii Islands' maps")
local function kk(w, gx, gy) return (gy - w.y0) * w.cols + (gx - w.x0) + 1 end
-- (Saffron: the stand-in placed by its connection, the real city's doors on it, its own id finding it)
local sc = kanto.byId.FR_SAFFRON_CITY_CONNECTION
local real = kanto.byId.FR_SAFFRON_CITY
T.check(sc and sc.how == "joined" and sc.x == 20 and sc.y == -30, "Saffron's stand-in east of Route 1, by its connection")
T.check(real and real.standIn == sc and real.x == sc.x - 2 and real.y == sc.y - 2,
  "the real Saffron City where its tiles match the stand-in's (" .. tostring(real and real.x) .. ", " .. tostring(real and real.y) .. ")")
local mart, gate
for _, d in ipairs(kanto.doors) do
  if d.dest == "FR_SAFFRON_CITY_MART" then mart = d end
  if d.dest == "FR_ROUTE_7_EAST_ENTRANCE" then gate = d end
end
T.check(mart and mart.map == "FR_SAFFRON_CITY_CONNECTION" and mart.x == sc.x + 5 and mart.y == sc.y + 5 and mart.kind == "mart",
  "the Mart's door moved onto the stand-in")
T.check(gate == nil, "the gatehouse's door past the stand-in left off (the route's own)")
-- (a town's wall isn't a cliff; a ledge is a hop, not a step; a plank strip over the water a bridge)
T.check(math.abs(kanto.h[kk(kanto, 10, 2)] - kanto.h[kk(kanto, 10, 12)]) < 1e-6, "Pallet flat on both sides of its wall")
T.check(math.abs(kanto.h[kk(kanto, 10, -15)] - kanto.h[kk(kanto, 10, -5)]) < 1e-6, "Route 1 level on both sides of its ledge")
local bk = kk(kanto, 10, -20)
T.eq(kanto.cls[bk], Fr.C.BRIDGE, "the plank strip over the strait a bridge")
T.check(kanto.deck[bk] and kanto.ws[bk] and kanto.deck[bk] > kanto.ws[bk], "its deck over the water")
local sevii = Fr.build({ region = "sevii123" })
T.check(sevii and sevii.byId.SEVII_ONE_ISLAND and sevii.byId.FR_PALLET_TOWN == nil, "Sevii 1-3 builds: One Island, none of Kanto")
-- (the mountain the map's north edge cuts off goes on into the sea, rounded off; the sea beyond)
local g1 = sevii and sevii.grown[kk(sevii, 8, -2)]
T.check(g1 and sevii.cls[kk(sevii, 8, -2)] == Fr.C.ROCK, "One Island's mountain grown on past the map's edge")
T.check(sevii and not sevii.grown[kk(sevii, 8, -18)] and Fr.WATER[sevii.cls[kk(sevii, 8, -18)] or Fr.C.SEA],
  "only so far: the sea past it")
T.check(sevii and not sevii.grown[kk(sevii, 0, -6)] or false, "rounded off: its corners not grown as far")

-- ------- kept on disk (src/map3d/cache.lua): the maps' fingerprint, the outline and terrain read back
do
  local fp1, fp2 = Wd.fingerprint(), Wd.fingerprint()
  T.check(type(fp1) == "string" and fp1 == fp2, "the maps' fingerprint: the same maps, the same (" .. tostring(fp1) .. ")")
  local was = town.midAt
  function town:midAt(x, y)
    if x == 3 and y == 3 then return ROCK end
    return was(self, x, y)
  end
  local fp3 = Wd.fingerprint()
  town.midAt = was
  T.check(fp3 ~= fp1, "one tile changed: another fingerprint")
  T.check(Wd.fingerprint() == fp1, "and back")

  -- (an in-memory mod.cache; love.data stood in for: compressing is a copy)
  local files = {}
  local fakeCache = {
    write = function(_, rel, bytes) files[rel] = bytes return true end,
    read = function(_, rel) return files[rel] end,
    delete = function(_, rel) files[rel] = nil return true end,
  }
  local function loadData(src)
    local chunk = loadstring(src)
    return chunk and chunk() or nil
  end
  local fakeData = { compress = function(_, _, b) return b end }
  local Mc = assert(loadfile(MOD .. "/src/map3d/cache.lua"))()({ cache = fakeCache, loadData = loadData,
    version = "9.9.9", engine = "1.0", data = fakeData })
  local stamp = Mc.stamp(fp1)
  T.check(stamp and stamp:find(fp1, 1, true) and stamp:find("9.9.9", 1, true), "the stamp: the version and the maps")
  local world = Wd.build()
  local t, step = Wd.terrain(world)
  local dir = Mc.dir("emerald", "hoenn")
  local ok, err = Mc.write(dir, stamp, { world = world, terrain = t, step = step, meshes = {}, images = {} })
  T.check(ok, "written (" .. tostring(err) .. ")")
  T.check(files[dir .. "/world.lua"] and files[dir .. "/terrain.bin"], "its index and its terrain")
  local got = Mc.readWorld(dir, stamp)
  T.check(got and got.world.cols == world.cols and got.world.rows == world.rows and got.world.x0 == world.x0
    and #got.world.maps == #world.maps and #got.world.doors == #world.doors, "read back: the world's box, maps and doors")
  local m0 = world.maps[1]
  local m1 = got and got.world.byId[m0.id]
  T.check(m1 and m1.x == m0.x and m1.y == m0.y and m1.w == m0.w and m1.sec == m0.sec, "a map's place, by its name")
  local same = got and got.terrain.cols == t.cols and got.terrain.rows == t.rows and got.step == step
  for q = 1, t.cols * t.rows do
    if not same then break end
    local a, b = got.terrain, t
    if math.abs(a.h[q] - b.h[q]) > 1e-4 or a.kind[q] ~= b.kind[q] or math.abs(a.r[q] - b.r[q]) > 0.003 then same = false end
  end
  T.check(same, "the terrain: every sample's height, colour and kind")
  T.check(Mc.readWorld(dir, Mc.stamp(fp3)) == nil, "another stamp (the maps changed): not read")
  Mc.forget(dir)
  T.check(Mc.readWorld(dir, stamp) == nil, "forgotten: not read")
end

T.finish("woob_os world3d (" .. GAME .. ")")
