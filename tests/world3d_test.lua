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

-- a layout: w x h, cell(x, y) -> coll, mid
local function layout(w, h, cell)
  local L = { width = w, height = h, trueWidth = w, trueHeight = h, pair = "test" }
  function L:collAt(x, y)
    if x < 0 or y < 0 or x >= w or y >= h then return 255 end
    return (cell(x, y))
  end
  function L:midAt(x, y)
    if x < 0 or y < 0 or x >= w or y >= h then return TREE end
    local _, m = cell(x, y)
    return m
  end
  function L:elevAt() return 3 end
  return L
end

-- Littleroot: ground; a house (rows 4-7, cols 4-8; its door at 6, 8); the sea along its foot
local town = layout(20, 20, function(x, y)
  if y >= 17 then return 41, SEA end
  if x == 6 and y == 8 then return 113, GROUND end
  if x >= 4 and x <= 8 and y >= 4 and y <= 8 then return 7, WALL end
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
    warps = { { x = 6, y = 8, destMap = "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F", destWarp = 1 } } },
  EM_ROUTE101 = { mapType = 3, midLayout = route, pair = "test", regionMapSectionId = 16,
    connections = { { dir = "south", map = "EM_LITTLEROOT_TOWN", offset = 0 } },
    warps = { { x = 19, y = 30, destMap = "EM_ROUTE102_GATE", destWarp = 1 } } },
  EM_ROUTE102 = { mapType = 3, midLayout = away, pair = "test", regionMapSectionId = 17, connections = {},
    warps = { { x = 0, y = 8, destMap = "EM_ROUTE102_GATE", destWarp = 2 } } },
  -- (the gatehouse: in from Route 101 at 0, 4; out to Route 102 at 9, 4)
  EM_ROUTE102_GATE = { mapType = 8, warps = { { x = 0, y = 4, destMap = "EM_ROUTE101", destWarp = 1 },
                                              { x = 9, y = 4, destMap = "EM_ROUTE102", destWarp = 1 } } },
  EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F = { mapType = 8, warps = { { x = 3, y = 7, destMap = "EM_LITTLEROOT_TOWN", destWarp = 1 } } },
}

local function engine(name)
  if name == "src.core.game3.scripting.interaction_scripts" then return { behaviors = { test = BEH } } end
  if name == "src.ui.game3.rse.mapsec" then return nil end
  local ok, m = pcall(require, name)
  return ok and m or nil
end
local Wd = assert(loadfile(MOD .. "/src/map3d/world.lua"))()(engine, {
  maps = function() return maps end, art = function() return ART end })
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
local door
for _, d in ipairs(world.doors) do if d.map == "EM_LITTLEROOT_TOWN" then door = d end end
T.check(door and door.kind == "house" and door.x == 6 and door.y == 8, "the house's door, a house's kind")
local f = door and door.foot
T.check(f and f.x0 == 4 and f.y0 == 4 and f.x1 == 9 and f.y1 == 9,
  "its footprint: the block above and beside the door (" .. (f and (f.x0 .. "," .. f.y0 .. "-" .. f.x1 .. "," .. f.y1) or "-") .. ")")
T.eq(world.cls[k(5, 5)], C.BUILDING, "the house's tiles a building")
-- (the gap east of Route 101, closed in by Route 102 and the town: filled from a border)
local filled = 0
for kk = 1, world.cols * world.rows do if world.filled[kk] then filled = filled + 1 end end
T.check(filled > 0, "the gaps filled from the maps' borders (" .. filled .. " tiles)")

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

T.finish("woob_os world3d (" .. GAME .. ")")
