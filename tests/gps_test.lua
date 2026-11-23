-- Standalone: luajit mods/woob_os/tests/gps_test.lua [emerald|firered|...] (from the gen1recomp root; needs
-- that cart imported, Emerald by default).
--
-- The map's GPS (src/gps/*.lua) on the game's own maps: the walk graph built (and read back from the
-- disk), routes through forests, caves and tunnels, Mt. Chimney's cable car, a route that needs Surf
-- ("surf" without it, "ok" with it), one that needs Fly ("none"), the arrow's next warp or edge, arriving
-- clears it, the map's line, the field's arrow drawn with next to no garbage; and the markers' model.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GAME = arg[1] or "emerald"
local RSE = not (GAME == "firered" or GAME == "leafgreen")
local P = RSE and "EM_" or "FR_"
if GAME == "ruby" then P = "RU_" elseif GAME == "sapphire" then P = "SA_" end

local clock = 0
love = { timer = { getTime = function() return clock end } }
require("src.core.GameVersion").set(GAME)
require("src.import.gba.versions").select(GAME)
love.filesystem = {
  getInfo = function(p)
    local f = io.open(GAME .. "/" .. p, "rb")
    if f then f:close() return {} end
  end,
  load = function(p) return loadfile(GAME .. "/" .. p) end,
}
local Dataset = require("src.core.game3.dataset")
Dataset.cacheRootOverride = GAME .. "/data/generated/gba"
local okM, maps = pcall(Dataset.buildMaps)
if not (okM and type(maps) == "table" and next(maps)) then
  print("gps_test: skipped (no " .. GAME .. " cart imported: " .. tostring(maps) .. ")")
  os.exit(0)
end
Dataset.attachMidLayouts(maps, Dataset.cache())
-- (the maps' objects -- cut trees, rocks, boulders -- from the cart's scripts, read as the paths say)
do
  local Space, CacheBlob = require("src.core.game3.scripting.space"), require("src.import.CacheBlob")
  local function open(rel) return io.open(rel, "rb") or io.open(GAME .. "/" .. rel, "rb") end
  pcall(Space.ensureBundle, { cache = {
    read = function(_, rel)
      local f = open(rel)
      if not f then return nil end
      local b = f:read("*a")
      f:close()
      return CacheBlob.decode(rel, b)
    end,
    exists = function(_, rel)
      local f = open(rel)
      if f then f:close() end
      return f ~= nil
    end } })
  pcall(Space.attachEventsToMaps, maps, Space.bundle)
end
local game = { data = { maps = maps } }
local function engine(n)
  local ok, m = pcall(require, n)
  return ok and type(m) == "table" and m or nil
end
local MOD = "mods/woob_os/src/"
local makeGraph, makeRoute = dofile(MOD .. "gps/graph.lua"), dofile(MOD .. "gps/route.lua")
local makeArrow, makeMarks = dofile(MOD .. "gps/arrow.lua"), dofile(MOD .. "marks.lua")
local makeReader = dofile(MOD .. "gps/read3.lua")

-- (the disk: kept in memory)
local disk = {}
local cache = { read = function(_, k) return disk[k] end, write = function(_, k, v) disk[k] = v; return true end }
local function graph()
  return makeGraph(engine, { reader = makeReader, maps = function() return maps end, game = function() return game end, cache = cache,
                             gameId = function() return GAME end, version = "test", log = print })
end

-- ------- the graph

local Gw = graph()
local t0 = os.clock()
T.check(Gw.buildNow(), "the walk graph builds")
local nn, ne = Gw.count()
T.check(nn > 1000 and ne > nn, ("its points and ways (%d, %d; %.2f s)"):format(nn, ne, os.clock() - t0))
T.check(disk["gps/" .. GAME .. ".txt"] ~= nil, "kept on disk")
do
  local again = graph()
  again.buildNow()
  local n2, e2 = again.count()
  T.check(n2 == nn and e2 == ne, "read back from the disk the same")
end
-- (the background build: a few milliseconds a step)
do
  local bg = makeGraph(engine, { reader = makeReader, maps = function() return maps end, game = function() return game end,
                                 gameId = function() return GAME end, version = "test" })
  bg.prepare()
  local steps = 0
  love.timer.getTime = os.clock
  while bg.step(0.002) and steps < 100000 do steps = steps + 1 end
  love.timer.getTime = function() return clock end
  T.check(bg.ready() and steps > 1, "built in the background a slice at a time (" .. steps .. " slices)")
end

-- ------- routes

local s = { map = P .. "LITTLEROOT_TOWN", x = 10, y = 10, party = {} }
local SURF, HMS = false, {}
local notified = {}
local store = { d = {} }
function store:get(k) return self.d[k] end
function store:set(k, v) self.d[k] = v end
local Rt = makeRoute(engine, { graph = Gw, save = store, session = function() return s end,
  can = function(_, k) if k == "SURF" then return SURF end return HMS[k] == true end,
  surfing = function() return false end,
  mapDef = function(id) return maps[id] end, log = print,
  notify = function(kind, data) notified[#notified + 1] = { kind, data } end })

local function go(from, fx, fy, to, tx, ty, surf, sec, hms)
  SURF, HMS = surf == true, hms or {}
  s.map, s.x, s.y = from, fx, fy
  Rt.clear()
  return Rt.set({ map = to, x = tx, y = ty, name = to, sec = sec })
end
local function through(id)
  for _, m in ipairs(Rt.chain() or {}) do if m == id then return true end end
  return false
end

if RSE and P == "EM_" then
  T.eq(go("EM_LITTLEROOT_TOWN", 10, 10, "EM_OLDALE_TOWN", 10, 10), "ok", "Littleroot to Oldale: a route")
  T.check(through("EM_ROUTE101"), "by Route 101")
  T.check(Rt.target.on and Rt.target.dy == -1 and Rt.target.y == 0, "the arrow: north, over the edge")
  T.eq(go("EM_LITTLEROOT_TOWN", 10, 10, "EM_RUSTBORO_CITY", 15, 20), "ok", "Littleroot to Rustboro")
  T.check(through("EM_PETALBURG_WOODS"), "through Petalburg Woods")
  T.eq(go("EM_RUSTBORO_CITY", 15, 20, "EM_VERDANTURF_TOWN", 10, 10), "ok", "Rustboro to Verdanturf")
  T.check(through("EM_RUSTURF_TUNNEL"), "through Rusturf Tunnel")
  T.eq(go("EM_LITTLEROOT_TOWN", 10, 10, "EM_DEWFORD_TOWN", 10, 10), "surf", "Dewford without Surf: needs Surf")
  T.eq(Rt.dest(), nil, "and no waypoint kept")
  T.eq(go("EM_LITTLEROOT_TOWN", 10, 10, "EM_DEWFORD_TOWN", 10, 10, true), "ok", "with Surf: a route")
  T.eq(go("EM_ROUTE112", 20, 50, "EM_LAVARIDGE_TOWN", 10, 10), "ok", "Lavaridge, on foot")
  T.check(through("EM_MT_CHIMNEY_CABLE_CAR_STATION") and through("EM_JAGGED_PASS"), "by the cable car and Jagged Pass")
  T.eq(go("EM_LITTLEROOT_TOWN", 10, 10, "EM_SOOTOPOLIS_CITY", 30, 30, true), "none", "Sootopolis: no route on foot")
  -- (Rusturf Tunnel's rocks: the only way, so drawn through them, Rock Smash marked; with it, nothing to mark)
  T.eq(go("EM_RUSTBORO_CITY", 15, 20, "EM_VERDANTURF_TOWN", 10, 10), "ok", "Verdanturf without Rock Smash: a route")
  T.eq(Rt.needs, 2, "and it says Rock Smash is needed on the way")
  local byId, list = {}, {}
  for _, id in ipairs({ "EM_RUSTBORO_CITY", "EM_ROUTE116", "EM_VERDANTURF_TOWN" }) do
    byId[id] = { id = id, x = #list * 128, y = 0, w = 128, h = 128 }
    list[#list + 1] = byId[id]
  end
  local L = Rt.line({ id = "t", unit = 16, world = { byId = byId, maps = list } })
  T.check(L and L.hn >= 1 and L.hk[1] == 2, "the line marks the Rock Smash spot (" .. tostring(L and L.hn) .. ")")
  T.eq(go("EM_RUSTBORO_CITY", 15, 20, "EM_VERDANTURF_TOWN", 10, 10, false, nil, { ROCK_SMASH = true }), "ok",
    "with Rock Smash")
  T.eq(Rt.needs, 0, "nothing needed")
  L = Rt.line({ id = "t2", unit = 16, world = { byId = byId, maps = list } })
  T.check(L and L.hn == 0, "and no mark")
  -- (Route 111's desert: its edges turn the player back without the Go-Goggles)
  local rec = Gw.tiles("EM_ROUTE111")
  local edges = 0
  for _, o in pairs(rec and rec.obst or {}) do if o == 8 then edges = edges + 1 end end
  T.eq(edges, 10, "the desert's edges: ten cells needing the Go-Goggles")
  local r1 = go("EM_ROUTE111", 20, 100, "EM_FALLARBOR_TOWN", 10, 10)
  T.eq(r1, "ok", "Route 111 to Fallarbor, without the Go-Goggles: a route")
  T.check(Rt.needs % 16 < 8 and through("EM_FIERY_PATH"), "around the desert, by Fiery Path (needs "
    .. tostring(Rt.needs) .. ", by " .. table.concat(Rt.chain() or {}, ", ") .. ")")
  T.eq(go("EM_ROUTE111", 20, 100, "EM_FALLARBOR_TOWN", 10, 10, false, nil, { GO_GOGGLES = true }), "ok", "with them")
  T.check(not through("EM_FIERY_PATH") and Rt.needs % 16 < 8, "straight across the desert (by "
    .. table.concat(Rt.chain() or {}, ", ") .. ")")
  -- (Mirage Tower, in the desert: no other way in, so drawn through the edge and marked)
  T.eq(go("EM_ROUTE111", 20, 100, "EM_MIRAGE_TOWER_1F", 5, 5), "ok", "Mirage Tower without them: a route")
  T.check(Rt.needs % 16 >= 8, "that says the Go-Goggles are needed (" .. tostring(Rt.needs) .. ")")
elseif not RSE then
  T.eq(go("FR_PALLET_TOWN", 10, 10, "FR_VIRIDIAN_CITY", 20, 20), "ok", "Pallet to Viridian")
  T.check(through("FR_ROUTE_1"), "by Route 1")
  -- (the story's way: Mt. Moon; with Cut, the shortcut it opens)
  T.eq(go("FR_PEWTER_CITY", 20, 20, "FR_CERULEAN_CITY", 20, 20), "ok", "Pewter to Cerulean")
  T.check(through("FR_MT_MOON_1F") and Rt.needs == 0, "through Mt. Moon, without Cut")
  T.eq(go("FR_PEWTER_CITY", 20, 20, "FR_CERULEAN_CITY", 20, 20, false, nil, { CUT = true }), "ok", "with Cut")
  T.check(through("FR_DIGLETTS_CAVE_B1F") and Rt.needs == 0, "the shortcut through Diglett's Cave it opens")
  T.eq(go("FR_MT_MOON_1F", 14, 20, "FR_CERULEAN_CITY", 20, 20), "ok", "Mt. Moon to Cerulean")
  T.check(through("FR_MT_MOON_B2F") and through("FR_ROUTE_4"), "down its ladders and out by Route 4")
  T.eq(go("FR_PALLET_TOWN", 10, 10, "FR_CINNABAR_ISLAND", 10, 10), "surf", "Cinnabar without Surf: needs Surf")
  T.eq(go("FR_PALLET_TOWN", 10, 10, "FR_CINNABAR_ISLAND", 10, 10, true), "ok", "with Surf: by Route 21")
  T.eq(go("FR_PALLET_TOWN", 10, 10, "FR_ONE_ISLAND", 10, 10, true), "none", "the Sevii Islands: no route (the boat)")
end
-- (Ruby / Sapphire / Emerald: Route 111's desert edges found from their scripts, the same ten on each)
if RSE then
  local rec = Gw.tiles(P .. "ROUTE111")
  local edges = 0
  for _, o in pairs(rec and rec.obst or {}) do if o == 8 then edges = edges + 1 end end
  T.eq(edges, 10, "Route 111's desert: ten edge cells needing the Go-Goggles")
end

-- (already there; a waypoint on a roof: the nearest tile to stand on)
do
  local town = P .. (RSE and "LITTLEROOT_TOWN" or "PALLET_TOWN")
  T.eq(go(town, 10, 10, town, 10, 11), "here", "a waypoint where the player stands: already here")
  local other = P .. (RSE and "OLDALE_TOWN" or "VIRIDIAN_CITY")
  T.eq(go(town, 10, 10, other, 0, 0), "ok", "a waypoint off the paths: the nearest tile")
end

-- (each step: the arrow; arriving clears it, and says so)
do
  local from = P .. (RSE and "LITTLEROOT_TOWN" or "PALLET_TOWN")
  local to = P .. (RSE and "OLDALE_TOWN" or "VIRIDIAN_CITY")
  T.eq(go(from, 10, 10, to, 10, 10), "ok", "a waypoint to walk to")
  T.check(store.d.gps and store.d.gps.dest and store.d.gps.dest.map == to, "kept in the save")
  Rt.step(from, 10, 10)
  T.check(Rt.target.on and Rt.target.map == from, "the arrow on this map")
  local d = Rt.dest()
  Rt.step(to, d.x + 1, d.y)
  T.check(Rt.dest() == nil and not Rt.target.on and notified[#notified] and notified[#notified][1] == "gps",
    "two steps from it: arrived, cleared, a notification")
  -- (a town: anywhere in it)
  T.eq(go(from, 10, 10, to, 10, 10, false, maps[to].regionMapSectionId), "ok", "a town's waypoint")
  Rt.step(to, 0, 0)
  T.eq(Rt.dest(), nil, "a town: arrived on coming into it")
  -- (the save's own: read back on loading)
  go(from, 10, 10, to, 10, 10)
  local kept = store.d.gps
  Rt.clear()
  store.d.gps = kept
  Rt.load()
  T.check(Rt.dest() and Rt.dest().map == to, "a loaded save's waypoint")
end

-- (the map's line: the walk's corners in world units; a stretch off the map dashed)
do
  local from = P .. (RSE and "LITTLEROOT_TOWN" or "PALLET_TOWN")
  local to = P .. (RSE and "RUSTBORO_CITY" or "PEWTER_CITY")
  go(from, 10, 10, to, 15, 20)
  local byId, list = {}, {}
  for _, id in ipairs(Rt.chain() or {}) do
    local def = maps[id]
    -- (the forest, the woods and the buildings left off this map: between, the line dashed)
    if def and def.mapType ~= nil and require("src.core.game3.dataset").isOutdoorMapType(def.mapType)
        and not id:find("WOODS") and not id:find("FOREST") then
      byId[id] = { id = id, x = #list * 64, y = 0, w = 64, h = 64 }
      list[#list + 1] = byId[id]
    end
  end
  local region = { id = "test", unit = 16, world = { byId = byId, maps = list } }
  local L = Rt.line(region)
  T.check(L and L.n > 4, "the line has its corners (" .. tostring(L and L.n) .. ")")
  local gaps = 0
  for k = 1, L and L.n or 0 do if L.gap[k] then gaps = gaps + 1 end end
  T.check(gaps >= 1, "a forest or a gatehouse between: dashed")
  T.check(Rt.line(region) == L, "kept while nothing moved")
  local id, x, y = Rt.spotAt(region, (list[1].x + 5.5) / 16, 3.5 / 16)
  T.check(id == list[1].id and x == 5 and y == 3, "a point on the map: its map and tile")
end

-- ------- the arrow over the field: next to no garbage

do
  local noop = function() end
  local G = { circle = noop, polygon = noop, setLineWidth = noop }
  local K = { sc = 3, X = function(u) return u * 3 end, Y = function(v) return v * 3 end, col = noop, place = noop }
  local Rt2 = { target = { on = true, map = "M", x = 12, y = 3, dx = 0, dy = 0, dest = false } }
  local A = makeArrow({ K = K, route = Rt2, on = function() return true end,
                        player = function() return 160, 128, "M", 160 + 8 - 120, 128 + 8 - 80, 0, 0, 3, 3 end })
  local vp = { gameX = 0, gameY = 0, gameWidth = 720, gameHeight = 480, scale = 3 }
  for _ = 1, 60 do clock = clock + 1 / 60; A.draw(G, vp, true, clock) end
  T.check(A.a > 0.9 and A.angle ~= nil, "it fades in and points")
  local want = math.atan2(3 * 16 - 128, 12 * 16 - 160)
  T.check(math.abs(A.angle - want) < 0.05, "at the warp's tile")
  local best = math.huge
  for _ = 1, 2 do
    collectgarbage("collect")
    collectgarbage("stop")
    local kb = collectgarbage("count")
    for _ = 1, 300 do clock = clock + 1 / 60; A.draw(G, vp, true, clock) end
    best = math.min(best, (collectgarbage("count") - kb) / 300)
    collectgarbage("restart")
  end
  T.check(best < 0.05, ("the arrow makes next to no garbage (%.4f KB/frame)"):format(best))
  for _ = 1, 60 do clock = clock + 1 / 60; A.draw(G, vp, false, clock) end
  T.check(A.a < 0.05, "not free to move: it fades away")
end

-- ------- the markers

do
  local st2 = { d = {} }
  function st2:get(k) return self.d[k] end
  function st2:set(k, v) self.d[k] = v end
  local Mk = makeMarks({ save = st2 })
  T.check(Mk.add("hoenn", 1, 2, "flag", nil) ~= nil, "a marker anywhere")
  local a = Mk.add("hoenn", 3, 4, "star", 7)
  local b = Mk.add("hoenn", 3, 4, "berry", 7)
  T.check(a == b and #Mk.list() == 2 and a.kind == "berry", "a place holds one: its kind changed")
  T.eq(Mk.onPlace("hoenn", 7), a, "found by its place")
  for i = 3, Mk.MAX do Mk.add("hoenn", i, i, "ball") end
  local none, why = Mk.add("hoenn", 0, 0, "flag")
  T.check(none == nil and why == "full" and #Mk.list() == 20, "twenty at most")
  Mk.remove(a)
  T.eq(#Mk.list(), 19, "one removed")
  local Mk2 = makeMarks({ save = st2 })
  T.eq(#Mk2.list(), 19, "kept in the save, read back")
end

-- ------- the map's objectives (src/map3d/objectives.lua), from the same maps and scripts
do
  local Words = setmetatable({ f = function(k, ...) return k .. ":" .. table.concat({ ... }, ",") end },
                             { __call = function(_, k) return k end })
  local flags, items, beats = {}, {}, {}
  -- (the shops' stocks, as the game loads them)
  local Marts = require("src.core.game3.marts")
  local nMarts = 0
  do
    local f = io.open(GAME .. "/data/generated/gba/scripts/marts.lua", "rb")
    local src = f and f:read("*a")
    if f then f:close() end
    local chunk = src and load(src, "@marts.lua", "t", {})
    local okP, pack = pcall(chunk or error)
    if okP then nMarts = Marts.install(pack) end
  end
  T.check((tonumber(nMarts) or 0) > 0, "the cart's shops' stocks (" .. tostring(nMarts) .. ")")
  local Ob = dofile(MOD .. "map3d/objectives.lua")(engine, {
    shopKind = dofile(MOD .. "map3d/shop_kind.lua")(),
    maps = function() return maps end, gameId = function() return GAME end, T = Words, log = print,
    family = function() return RSE and "rse" or "frlg" end,
    flag = function(name) return flags[name] == true end,
    hasItem = function(_, id) return items[id] == true end,
    reached = function() return beats end,
  })
  local secOf = {}
  for id, def in pairs(maps) do secOf[id] = tonumber(def.regionMapSectionId) end
  local function list(mapId, spoilers) return Ob.at(secOf[mapId], {}, spoilers) or {} end
  local function find(l, kind, pat)
    for _, e in ipairs(l) do if e.kind == kind and tostring(e.label):find(pat, 1, true) then return e end end
  end
  local function count(l, kind, pat)
    local n = 0
    for _, e in ipairs(l) do if e.kind == kind and tostring(e.label):find(pat, 1, true) then n = n + 1 end end
    return n
  end
  if RSE then
    local mv = list(P .. "MAUVILLE_CITY")
    T.check(find(mv, "gym", "Wattson") and find(mv, "key", "Mach Bike") and find(mv, "key", "Acro Bike")
            and find(mv, "key", "Basement Key"), "Mauville: Wattson's Gym, both bikes, the Basement Key")
    T.check(find(mv, "shop", "map.obj.shop.mart") ~= nil, "and its Poké Mart")
    T.check(not find(list(P .. "OLDALE_TOWN"), "key", "Ticket"), "the event tickets left out (every Center's)")
    local ly = list(P .. "LILYCOVE_CITY")
    T.check(count(ly, "shop", "map.obj.shop.floor") >= 4 and find(ly, "people", "deleter"),
            "Lilycove: the department store's floors, the Move Deleter")
    local order = {}
    for _, e in ipairs(ly) do if e.kind == "shop" then order[#order + 1] = tostring(e.label) end end
    local seq = table.concat(order, " | ")
    T.check(seq:find("2F.-3F.-4F.-5F.-roof") ~= nil, "its floors from the bottom up, the rooftop last: " .. seq)
    -- (each floor by what it sells)
    T.check(seq:find("floorKind:map.obj.cat.trainer,2F", 1, true) and seq:find("floorKind:map.obj.cat.battle,3F", 1, true)
            and seq:find("floorKind:map.obj.cat.tm,4F", 1, true) and seq:find("floorKind:map.obj.cat.deco,5F", 1, true),
            "each floor by what it sells: Trainer Items, Battle Items, TMs, Decorations")
    -- (a market's stalls by what each sells; Mt. Chimney's Lava Cookies, sold by a script of their own)
    local sl = {}
    for _, e in ipairs(list(P .. "SLATEPORT_CITY")) do if e.kind == "shop" then sl[#sl + 1] = tostring(e.label) end end
    print("  Slateport's shops: " .. table.concat(sl, " | "))
    T.check(table.concat(sl, " | "):find("stallKind:", 1, true) ~= nil, "Slateport's stalls by what they sell")
    local mc = {}
    for _, e in ipairs(list(P .. "MT_CHIMNEY")) do if e.kind == "shop" then mc[#mc + 1] = tostring(e.label) end end
    T.check(table.concat(mc, " | "):find("vendor:Lava Cookie", 1, true) ~= nil,
            "Mt. Chimney: the Lava Cookie vendor (" .. table.concat(mc, " | ") .. ")")
    local eg = list(P .. "EVER_GRANDE_CITY")
    T.eq(count(eg, "gym", "map.obj.elite"), 4, "Ever Grande: the Elite Four, once each")
    T.check(find(list(P .. "ROUTE117"), "people", "daycare") ~= nil, "Route 117: the Day Care")
    T.check(find(list(P .. "SLATEPORT_CITY"), "people", "nameRater") ~= nil, "Slateport: the Name Rater")
    T.check(find(eg, "shop", "map.obj.shop.mart") ~= nil and not find(eg, "shop", "League"),
            "Ever Grande: the League's Poké Mart, by that name")
    -- (the boxes: a Badge's flag, an item in the Bag)
    local g = find(mv, "gym", "Wattson")
    T.check(g and g.done == false, "Wattson's box empty")
    flags.FLAG_BADGE03_GET = true
    T.check(find(list(P .. "MAUVILLE_CITY"), "gym", "Wattson").done == true, "ticked with the Badge")
    local b = find(mv, "key", "Mach Bike")
    T.check(b and b.done == false, "the Mach Bike unticked")
    -- (a story moment ahead: ??? until reached, named with spoilers)
    local cv = find(list(P .. "MT_CHIMNEY"), "story", "map.obj.story.chimney")
    T.check(cv and cv.hidden == true and cv.done == false, "Mt. Chimney's story moment ahead: hidden")
    T.check(find(list(P .. "MT_CHIMNEY", true), "story", "chimney").hidden == false, "with spoilers: named")
    beats.chimney = true
    local cd = find(list(P .. "MT_CHIMNEY"), "story", "chimney")
    T.check(cd.done == true and cd.hidden == false, "reached: ticked and named")
  else
    local ce = list("FR_CERULEAN_CITY")
    T.check(find(ce, "gym", "Misty") and find(ce, "key", "Bicycle") and find(ce, "story", "burglar"),
            "Cerulean: Misty's Gym, the Bicycle, the burglar")
    local la = list("FR_LAVENDER_TOWN")
    T.check(find(la, "key", "Flute") and find(la, "people", "nameRater"), "Lavender: the Poké Flute, the Name Rater")
    T.check(not find(list("FR_CELADON_CITY"), "people", "nameRater"), "Celadon's Eevee isn't a Name Rater")
    local cs = {}
    for _, e in ipairs(list("FR_CELADON_CITY")) do if e.kind == "shop" then cs[#cs + 1] = tostring(e.label) end end
    print("  Celadon's shops: " .. table.concat(cs, " | "))
    T.check(table.concat(cs, " | "):find("floorKind:map.obj.cat.tm", 1, true) ~= nil, "Celadon's TMs by their floor")
    T.eq(count(list("FR_POKEMON_LEAGUE_LORELEIS_ROOM"), "gym", "map.obj.elite"), 4, "the Elite Four, once each")
    T.check(find(list("FR_SSANNE_CAPTAINS_OFFICE"), "key", "HM01") ~= nil, "the S.S. Anne: HM01")
  end
end

T.finish("woob_os gps (" .. GAME .. ")")
