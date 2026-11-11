-- Standalone: luajit mods/woob_os/tests/map3d_test.lua [game] (from the gen1recomp root; needs that
-- cart imported, FireRed by default).
--
-- The 3D map (src/map3d/*.lua, src/townmap.lua): every region built from the game's Town Map, its
-- towns, Centers, Marts and Gyms (with their badges), the towns' buildings (sizes, styles), where the player is, the D-pad reaching every
-- town, the game's Town Map and Fly map taken over (Fly handed back exactly as the game's map hands
-- it, B as it closes, START the classic map, the setting off), Fly from the app refused without the
-- badge or a Pokémon that knows it, its words, and next to no garbage.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GAME = arg[1] or "firered"
local RSE = not (GAME == "firered" or GAME == "leafgreen")

local clock = 100
local function noop() end
local fontOf = {}
local function newFont(px)
  local f = fontOf[px]
  if not f then
    f = { getWidth = function(_, s) return #tostring(s) * px * 0.55 end, getHeight = function() return px * 1.2 end,
          getWrap = function(_, s) return 0, { s } end }
    fontOf[px] = f
  end
  return f
end
local G = setmetatable({ newFont = newFont, getFont = function() return newFont(12) end,
                         newMesh = function() error("no meshes headless") end },
                       { __index = function() return noop end })
love = { timer = { getTime = function() return clock end }, graphics = G }

require("src.core.GameVersion").set(GAME)
-- (Ruby / Sapphire / Emerald's map reads its manifest through love.filesystem: the cart's folder)
love.filesystem = {
  getInfo = function(p)
    local f = io.open(GAME .. "/" .. p, "rb")
    if f then f:close() return {} end
  end,
  load = function(p) return loadfile(GAME .. "/" .. p) end,
}
do
  local CacheBlob = require("src.import.CacheBlob")
  require("src.core.game3.dataset").cache = function()
    return {
      read = function(_, rel)
        local f = io.open(GAME .. "/" .. rel, "rb")
        if not f then return nil end
        local bytes = f:read("*a")
        f:close()
        return CacheBlob.decode(rel, bytes)
      end,
      exists = function(_, rel)
        local f = io.open(GAME .. "/" .. rel, "rb")
        if f then f:close() end
        return f ~= nil
      end,
    }
  end
end

local run = T.sdk.loadMods({ "mods/woob_os" }, { data = {}, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.events:emit("game.ready", {})
local X = run.loader.exports.woob_os
local Sh, Apps, Wt, Tm = X._test.shell, X._test.apps, X._test.watch, X._test.townmap
local M3 = X._test.map3d
local Settings = X._test.settings
local Stack = require("src.ui.game3.stack")
T.check(M3 ~= nil and Tm ~= nil, "the 3D map and its Town Map host are made")
local Mdl = M3.model
local kept = {}
Settings.cache = { read = function() return nil end, write = function(_, k, v) kept[k] = v end }

local function input(press, down)
  local p, d = {}, {}
  for _, k in ipairs(press or {}) do p[k] = true end
  for _, k in ipairs(down or {}) do d[k] = true end
  return { wasPressed = function(_, k) return p[k] == true end, isDown = function(_, k) return d[k] == true end }
end
local NONE = {}
local function garbageOf(n, fn)
  local best = math.huge
  for _ = 1, 2 do
    collectgarbage("collect")
    collectgarbage("stop")
    local kb = collectgarbage("count")
    for _ = 1, n do
      clock = clock + 1 / 60
      fn()
    end
    best = math.min(best, (collectgarbage("count") - kb) / n)
    collectgarbage("restart")
  end
  return best
end

local Bag, Storage = require("src.core.game3.bag"), require("src.core.game3.storage")
local ItemsData = require("src.core.game3.items_data")
local s = { name = "WOS", playerName = "WOS", bag = Bag.new(), storage = Storage.new(), party = {}, money = 3000,
            flags = {}, vars = {} }
ItemsData.ensureModel(s)
s.trainerId, s.secretId = 4321, 8765
s.meta = { playthroughId = "map-run" }
require("src.core.game3.runtime").getSession = function() return s end

-- ------- the model: every region, its towns and their facts

T.eq(Mdl.family(), RSE and "rse" or "frlg", "the game's family")
local regions = Mdl.regions()
T.eq(#regions, RSE and 1 or 4, RSE and "Hoenn" or "Kanto and the Sevii Islands' three pictures")
local home
for _, d in ipairs(regions) do
  local ok, r = pcall(Mdl.region, d.id)
  T.check(ok and r and r.terrain, d.id .. " builds (" .. tostring(not ok and r or "") .. ")")
  if ok and r then
    local t = r.terrain
    local kinds, bad = {}, 0
    for k = 1, t.cols * t.rows do
      if not t.kind[k] or type(t.h[k]) ~= "number" then bad = bad + 1 else kinds[t.kind[k]] = true end
    end
    T.eq(bad, 0, d.id .. ": every sample has a kind and a height")
    T.check(kinds.sea and kinds.land, d.id .. ": land and sea")
    local towns, named = 0, true
    for _, p in ipairs(r.places) do
      if p.kind == "town" then towns = towns + 1 end
      named = named and type(p.name) == "string" and p.name ~= "" and #p.cells > 0
    end
    T.check(named, d.id .. ": every place has a name and cells")
    T.check(towns > 0, d.id .. ": towns (" .. towns .. ")")
    T.check(Mdl.region(d.id) == r, d.id .. ": built once, kept")
    if d.id == "kanto" or d.id == "hoenn" then home = r end
  end
end
-- (the Gyms: eight, each with its own badge; a Center in every town that has one)
do
  local badges, gyms, centers, marts = {}, 0, 0, 0
  for _, p in ipairs(home.places) do
    if p.hasGym then
      gyms = gyms + 1
      if p.badge then badges[p.badge] = p.name end
    end
    if p.center then centers = centers + 1 end
    if p.mart then marts = marts + 1 end
  end
  local all = true
  for i = 1, 8 do all = all and badges[i] ~= nil end
  T.eq(gyms, 8, "eight Gyms")
  T.check(all, "badges 1-8, one per Gym")
  T.check(centers >= 10 and marts >= 9, "Centers (" .. centers .. ") and Marts (" .. marts .. ") from the map catalog")
  local first = RSE and "Rustboro City" or "Pewter City"
  T.eq(badges[1], first, "the first badge's Gym: " .. first)
  local start = RSE and "Littleroot Town" or "Pallet Town"
  local found
  for _, p in ipairs(home.places) do if p.name == start then found = p end end
  T.check(found and found.kind == "town" and not found.center and not found.hasGym, start .. ": a town, no Center, no Gym")
end
-- (a landmark in a town's own cells is part of its card)
if not RSE then
  local fuchsia
  for _, p in ipairs(home.places) do if p.sym == "MAPSEC_FUCHSIA_CITY" then fuchsia = p end end
  T.check(fuchsia and fuchsia.extras and fuchsia.extras[1] and fuchsia.extras[1].sym == "MAPSEC_KANTO_SAFARI_ZONE",
    "the Safari Zone is part of Fuchsia City's card")
end
T.eq(Mdl.titled("POKéMON TOWER"), "Pokémon Tower", "names in title case")
T.eq(Mdl.camel("MAPSEC_ROUTE_4_POKECENTER"), "Route4", "a section's map name")

-- the towns: each its size, its roofs, its own structures (src/map3d/towns.lua)
do
  local Tw = M3.towns
  T.check(Tw ~= nil, "the towns' builder is made")
  local whole = true
  for _, d in ipairs(regions) do
    local okB, verts = pcall(Tw.build, Mdl.region(d.id))
    whole = whole and okB and #verts > 0 and #verts % 3 == 0 and #verts[1] == 11
    if not okB then print(verts) end
  end
  T.check(whole, "every region's towns build, in whole triangles")
  local function named(n)
    for _, p in ipairs(home.places) do if p.name == n then return p end end
  end
  if RSE then
    T.eq(named("Littleroot Town").tier, 1, "Littleroot: a town")
    T.eq(named("Rustboro City").tier, 3, "Rustboro: a city")
    T.eq(Tw.styleOf(named("Mossdeep City")), "rocket", "Mossdeep: its rocket")
    T.eq(Tw.styleOf(named("Rustboro City")), "skyscraper", "Rustboro: Devon's tower")
    if home.fromPicture then T.check(named("Pacifidlog Town").water == true, "Pacifidlog: on the water") end
  else
    T.eq(named("Pallet Town").tier, 1, "Pallet: a town")
    T.eq(named("Celadon City").tier, 3, "Celadon: a city")
    T.eq(Tw.styleOf(named("Pallet Town")), "lab", "Pallet: Oak's lab")
    T.eq(Tw.styleOf(named("Pokémon Tower")), "tower", "the Pokémon Tower")
    local r, g, b = Tw.ground(named("Celadon City"))
    local r2 = Tw.ground(named("Pallet Town"))
    T.check(r ~= r2, "a city's ground is not a town's")
  end
end

-- visited, from the game's own flags
-- (the first two Gyms' towns: Pewter and Cerulean, Rustboro and Dewford)
local firstTown, otherTown
for _, p in ipairs(home.places) do
  if p.badge == 1 then firstTown = p elseif p.badge == 2 then otherTown = p end
end
local function visit(p)
  if RSE then
    local C = require("src.core.game3.constants").of(require("src.core.game3.profile").forSession(s).id)
    local RM = require("src.ui.game3.rse.region_map")
    s.flags[C:flag("FLAG_VISITED_LITTLEROOT_TOWN") + (p.id - RM.manifest().mapsecs.LITTLEROOT_TOWN)] = true
  else
    local name = "FLAG_WORLD_MAP_" .. p.sym:sub(8)
    s.flags[name] = true
    local Flags = require("src.core.game3.scripting.flags")
    if Flags.IDS[name] then s.flags[Flags.IDS[name]] = true end
  end
end
Mdl.live(home, s)
T.check(not firstTown.visited, firstTown.name .. ": not visited yet")
visit(firstTown)
Mdl.live(home, s)
T.check(firstTown.visited and firstTown.canFly, firstTown.name .. ": visited, Fly can reach it")

-- where the player is (the game's own position code, from a map in that town)
do
  local okP, rid, px, pz
  if RSE then
    local Map = require("src.core.game3.map")
    local prev = Map.currentDef
    Map.currentDef = function() return { regionMapSectionId = firstTown.id, mapType = 1, width = 20, height = 20 } end
    okP, rid, px, pz = pcall(Mdl.player, s)
    Map.currentDef = prev
  else
    local Runtime = require("src.core.game3.runtime")
    local MapCatalog = require("src.import.gba.map_catalog")
    local prevGame, prevSlot = Runtime._game, MapCatalog.slotKeyFor
    Runtime._game = { data = { maps = { TEST_TOWN = { regionMapSectionId = firstTown.id, mapType = 1, width = 24, height = 20 } } } }
    MapCatalog.slotKeyFor = function(id) if id == "TEST_TOWN" then return "3_99" end return prevSlot(id) end
    s.map, s.x, s.y = "TEST_TOWN", 5, 5
    okP, rid, px, pz = pcall(Mdl.player, s)
    Runtime._game, MapCatalog.slotKeyFor = prevGame, prevSlot
  end
  local inside = false
  if okP and px then
    for _, c in ipairs(firstTown.cells) do
      inside = inside or (px >= c[1] and px < c[1] + 1 and pz >= c[2] and pz < c[2] + 1)
    end
  end
  T.check(okP and rid == home.id and inside, "the player is found in " .. firstTown.name .. " (" .. tostring(rid) .. " "
    .. tostring(px) .. ", " .. tostring(pz) .. ")")
end

-- ------- the Map app: every town in reach of the D-pad, the card, Fly refused

local mapApp = Apps.byId("map")
T.check(mapApp ~= nil and mapApp.window ~= nil, "the Map app is registered with a window")
local ctx = { session = s, mode = "watch", app = "map", rows = {} }
function ctx.done() ctx.closed = true end
local K = X._test.kit
local VP = { width = 480, height = 320 }
local W = mapApp.window(ctx, X._test.env)
T.check(W and W.draw and W.state.region == home, "it opens on the player's region")
local body = { 0, 0, 200, 140 }
local function draw(n)
  for _ = 1, n or 1 do
    clock = clock + 1 / 60
    K.frame(G, VP, { height = 160, minWidth = 200, maxWidth = 300, portraitWidth = 160, portraitHeight = 260,
                     portraitAspect = 0.9 }, clock)
    W.draw(body, clock)
  end
end
draw(3)
local st = W.state
T.check(#st.nav > 0 and st.here ~= nil, "the cursor starts on a place")
-- (the cursor: free, the way the camera faces; let go near a town, it glides onto it)
do
  local function hold(keys, frames)
    for _ = 1, frames do
      W.input(input({}, keys), NONE)
      draw(1)
    end
    W.input(input(), NONE)
  end
  for _, c in ipairs({ st.cam, st.goal }) do c.yaw = 0 end
  local town = st.nav[1]
  W.focus(town)
  local x0, z0 = st.cx, st.cz
  hold({ "right" }, 6)
  T.check(st.cx > x0 + 0.05 and math.abs(st.cz - z0) < 0.01, "Right (the camera facing north): the cursor east")
  hold({ "up" }, 6)
  T.check(st.cz < z0 - 0.05, "Up: north")
  -- (left a little off a town: it glides back onto it)
  local snapped, reachedAll = true, true
  for _, p in ipairs(st.nav) do
    if p.kind == "town" then
      st.cx, st.cz, st.snapTo, st.moving = p.x + 0.45, p.z - 0.3, nil, true
      W.input(input(), NONE)
      draw(90)
      snapped = snapped and math.abs(st.cx - p.x) < 0.01 and math.abs(st.cz - p.z) < 0.01
      reachedAll = reachedAll and (st.here == p or (st.here and st.here.within == p))
    end
  end
  T.check(snapped, "let go near any town: the cursor settles on it")
  T.check(reachedAll, "and the card is that town's")
  -- (on a route: the route, not a town)
  local route
  for _, p in ipairs(st.region.places) do if p.kind == "route" and not route then route = p end end
  if route then
    local c = route.cells[1]
    local far = true
    for _, q in ipairs(st.nav) do
      if (q.x - c[1] - 0.5) ^ 2 + (q.z - c[2] - 0.5) ^ 2 < 1.3 ^ 2 then far = false end
    end
    st.cx, st.cz, st.snapTo, st.moving = c[1] + 0.5, c[2] + 0.5, nil, true
    W.input(input(), NONE)
    draw(30)
    T.check(not far or st.here == route, "between towns: the route under the cursor (" .. tostring(st.here and st.here.name) .. ")")
  end
  W.focus(town)
end
-- (the right stick turns and tilts; SELECT: the flat map, north up, and back)
do
  local yaw, pitch = st.goal.yaw, st.goal.pitch
  local stick = input()
  stick.rightStickAxis = { x = 1, y = -0.8 }
  for _ = 1, 10 do W.input(stick, NONE); draw(1) end
  W.input(input(), NONE)
  T.check(st.goal.yaw > yaw and st.goal.pitch > pitch, "the right stick: turned and tilted")
  W.input(input({ "select" }), NONE)
  T.check(st.flat, "SELECT: the flat map")
  draw(3)
  local hasFlat = false
  for _, h in ipairs(W.hints()) do if h[1] == "SELECT" then hasFlat = true end end
  T.check(hasFlat and not st.three, "drawn flat (its hints say SELECT: 3D)")
  local tapFlat
  for _, h in ipairs(K.hits) do if h.kind == "win" and h.arg == 1005 then tapFlat = h end end
  T.check(tapFlat ~= nil, "its 2D / 3D chip")
  local x0 = st.cx
  for _ = 1, 6 do W.input(input({}, { "right" }), NONE); draw(1) end
  W.input(input(), NONE)
  T.check(st.cx > x0, "the cursor: right is east, north up")
  W.tap(1005)
  T.check(not st.flat, "the chip: 3D again")
  draw(30)
end
-- (A zooms; the card's Fly refused without the badge)
local z0 = st.zoom
W.input(input({ "a" }), NONE)
T.check(st.zoom == z0 % 4 + 1, "A zooms")
-- (four set zooms: the region, nearer, near, then a close-up of the place, at a fixed distance and a
-- lower angle; A again, the region)
do
  for _ = 1, 4 do
    if st.zoom ~= 3 then W.input(input({ "a" }), NONE) end
  end
  T.eq(st.zoom, 3, "A steps through to near")
  local near = st.goal.dist
  W.input(input({ "a" }), NONE)
  T.check(st.zoom == 4 and math.abs(st.goal.dist - 2.4) < 1e-6 and st.goal.dist < near and st.goal.pitch < 0.78,
    ("A again: the close-up (%.2f units, near was %.2f; pitch %.2f)"):format(st.goal.dist, near, st.goal.pitch))
  W.scroll(-40)
  T.check(st.goal.dist > 2.4, "the wheel out from the close-up")
  W.scroll(400)
  T.check(st.goal.dist >= 2 - 1e-6 and st.goal.dist < 2.4, "the wheel in: to just past the close-up (" .. st.goal.dist .. ")")
  W.input(input({ "a" }), NONE)
  T.eq(st.zoom, 1, "A after the close-up: the whole region again")
end
W.focus(firstTown)
draw(70)
T.eq(st.flyWhy, "badge", "no badge that allows Fly: refused for that")
W.input(input({ "start" }), NONE)
T.check(st.toast ~= nil and not ctx.closed, "START (Fly) says why, and stays")
do
  local FM = require("src.core.game3.field_moves")
  local flag = FM.badgeFlag("FLY")
  s.flags[flag] = true
  st.liveAt = -10
  draw(1)
  T.eq(st.flyWhy, "mon", "the badge but no Pokémon that knows Fly: refused for that")
  s.flags[flag] = nil
end
-- (an unvisited town can't be flown to)
W.focus(otherTown)
st.flyMon = {}
st.toast = nil
W.tap(1003)
T.check(st.toast and st.toast.text == X._test.i18n("map.notVisited") and not ctx.closed, "Fly to an unvisited town: no")
st.flyMon = nil
-- (a tap on a pin chooses that place)
draw(1)
local pinHit
for _, h in ipairs(K.hits) do
  if h.kind == "win" and h.arg > 2000 and h.arg - 2000 ~= st.sel then pinHit = h end
end
T.check(pinHit ~= nil, "the places have pins to tap")
if pinHit then
  -- (the hit's record is the kit's, used again next frame: its arg kept)
  local arg = pinHit.arg
  W.tap(arg)
  draw(90)
  T.eq(st.sel, arg - 2000, "a tap on a pin: the cursor glides there")
end
-- (drags turn and tilt, two fingers zoom, the wheel too)
do
  local yaw, pitch, dist = st.goal.yaw, st.goal.pitch, st.goal.dist
  W.pointer("pressed", 50, 50, 1)
  W.pointer("moved", 70, 60, 1)
  W.pointer("moved", 90, 70, 1)
  T.check(W.pointer("released", 90, 70, 1) == true and st.goal.yaw ~= yaw and st.goal.pitch ~= pitch, "a drag turns and tilts")
  W.pointer("pressed", 40, 50, 1)
  W.pointer("pressed", 60, 50, 2)
  W.pointer("moved", 30, 50, 1)
  W.pointer("moved", 70, 50, 2)
  W.pointer("released", 30, 50, 1)
  W.pointer("released", 70, 50, 2)
  T.check(st.goal.dist < dist, "two fingers spread: closer")
  local d2 = st.goal.dist
  W.scroll(-30)
  T.check(st.goal.dist > d2, "the wheel: further")
end
-- (B is the host's: back)
T.check(W.input(input({ "b" }), NONE) == false, "B goes back")
-- (no garbage to speak of, the card and the pins drawn)
draw(2)
local kb = garbageOf(120, function() draw(1) end)
T.check(kb < 0.5, string.format("the map's draw makes next to no garbage (%.3f KB/frame)", kb))

-- ------- Kyogre's and Groudon's storms (Emerald): the game's variables, one rumour at a time
if RSE then
  local Rs = require("src.core.game3.rse.init")
  local var0, flag0 = Rs.var, Rs.flag
  local vars, flags = {}, {}
  Rs.var = function(n) return vars[n] or 0 end
  Rs.flag = function(n) return flags[n] == true end
  local LOC, ENDING = "VAR_ABNORMAL_WEATHER_LOCATION", "VAR_SHOULD_END_ABNORMAL_WEATHER"
  local hoenn = Mdl.region("hoenn")
  if GAME == "emerald" then
    T.eq(Mdl.storm(hoenn, s), nil, "no rumour yet: no storm")
    local ROUTES = { 114, 114, 115, 115, 116, 116, 118, 118, 105, 105, 125, 125, 127, 127, 129, 129 }
    for at, route in ipairs(ROUTES) do
      vars[LOC] = at
      local got = Mdl.storm(hoenn, s)
      T.check(got ~= nil and got.place.name == "Route " .. route and got.kind == (at >= 9 and "rain" or "sand"),
        "location " .. at .. ": " .. (got and got.kind .. " over " .. got.place.name or "nothing"))
    end
    vars[LOC] = 3
    flags.FLAG_DEFEATED_KYOGRE = true
    T.eq(Mdl.storm(hoenn, s).kind, "sand", "Kyogre caught: Groudon's still shows")
    flags.FLAG_DEFEATED_GROUDON = true
    T.eq(Mdl.storm(hoenn, s), nil, "and it clears once Groudon's caught")
    flags = {}
    vars[ENDING] = 1
    T.eq(Mdl.storm(hoenn, s), nil, "the game ending the weather clears it")
    vars[ENDING] = nil
    -- the window: it appears, drifts to a new report, clears
    local ms = W.state
    vars[LOC] = 11
    ms.liveAt = -10
    draw(1)
    T.check(ms.storm.on and ms.storm.kind == "rain" and ms.storm.place.name == "Route 125", "the map reads it")
    draw(120)
    T.eq(ms.storm.grow, 1, "and it grows in")
    local fromX = ms.storm.x
    vars[LOC] = 9      -- (Route 105: the far side of the map)
    ms.liveAt = -10
    draw(2)
    T.check(ms.storm.tx ~= fromX and ms.storm.x ~= ms.storm.tx, "a new report: it drifts there")
    local stormKb = garbageOf(120, function() draw(1) end)
    T.check(stormKb < 0.5, string.format("the storm makes next to no garbage (%.3f KB/frame)", stormKb))
    vars[LOC] = 3
    ms.liveAt = -10
    draw(1)
    T.check(ms.storm.kind == "sand" and ms.storm.grow < 1, "the other one: it starts afresh, where it is")
    flags.FLAG_DEFEATED_GROUDON = true
    ms.liveAt = -10
    draw(120)
    T.check(not ms.storm.on and ms.storm.grow == 0, "caught: it clears")
  else
    vars[LOC] = 11
    T.eq(Mdl.storm(hoenn, s), nil, "Ruby / Sapphire have no abnormal weather")
  end
  Rs.var, Rs.flag = var0, flag0
end

-- ------- the everyday weather (Ruby / Sapphire / Emerald): where the game's maps put it, quiet
if RSE then
  local hoenn = Mdl.region("hoenn")
  local function placeNamed(n)
    for _, p in ipairs(hoenn.places) do if p.name == n then return p end end
  end
  local r111, r113, r119, chimney = placeNamed("Route 111"), placeNamed("Route 113"), placeNamed("Route 119"),
    placeNamed("Mt. Chimney")
  T.check(r111 and r113 and r119 and chimney, "the places the weather goes on")
  -- (the game's shapes: a map's own weather, weather tiles, a script's setweather; an indoor map's never shows)
  local maps = {
    R111 = { regionMapSectionId = r111.id, mapType = 3, width = 40, height = 140, weather = 2 },
    R113 = { regionMapSectionId = r113.id, mapType = 3, width = 100, height = 20, weather = 2 },
    R119 = { regionMapSectionId = r119.id, mapType = 3, width = 40, height = 140, weather = 2 },
    CHIMNEY = { regionMapSectionId = chimney.id, mapType = 3, width = 40, height = 40, weather = 7 },
    HOUSE = { regionMapSectionId = r113.id, mapType = 8, width = 10, height = 9, weather = 8 },
  }
  local events = {
    R111 = { coordEvents = { { x = 10, y = 38, var = 0, scriptPtr = 1, scriptKey = "sand" },
                             { x = 17, y = 62, var = 0, scriptPtr = 1, scriptKey = "sand" },
                             { x = 7, y = 31, var = 0, scriptPtr = 1, scriptKey = "sun" } } },
    R113 = { coordEvents = { { x = 19, y = 6, var = 8, scriptPtr = 0 }, { x = 87, y = 14, var = 8, scriptPtr = 0 },
                             { x = 14, y = 8, var = 2, scriptPtr = 0 } } },
    R119 = { coordEvents = { { x = 15, y = 13, var = 20, scriptPtr = 0 }, { x = 34, y = 133, var = 20, scriptPtr = 0 } } },
    HOUSE = { coordEvents = { { x = 1, y = 1, var = 9, scriptPtr = 0 } } },
  }
  local scripts = { sand = { { op = "setweather", 8 }, { op = "doweather" } }, sun = { { op = "setweather", 2 } } }
  local data0 = Mdl.weatherData
  Mdl.weatherData = function() return maps, events, scripts end
  hoenn.wxSpots = nil
  local function byPlace(list)
    local by = {}
    for _, w in ipairs(list) do by[w.place.name] = by[w.place.name] or w end
    return by
  end
  local stage0 = s.weatherCycleStage
  s.weatherCycleStage = 0
  local by = byPlace(Mdl.weather(hoenn, s))
  T.check(by["Route 111"] and by["Route 111"].kind == "sand", "Route 111: the desert's sandstorm (a script's setweather)")
  T.check(by["Route 113"] and by["Route 113"].kind == "ash", "Route 113: falling ash (its weather tiles; not the house's)")
  T.check(by["Mt. Chimney"] and by["Mt. Chimney"].kind == "ash", "Mt. Chimney: ash (the map's own weather)")
  local sand = by["Route 111"]
  if sand and r111.z1 - r111.z0 > 1 then
    T.check(sand.rz < (r111.z1 - r111.z0) / 2 and sand.z < (r111.z0 + r111.z1) / 2,
      "the sandstorm only over the desert's part of Route 111 (its north)")
  end
  local okCycles = pcall(require("src.core.game3.weather").cycles)
  if okCycles then
    T.eq(by["Route 119"], nil, "Route 119: sunny on its cycle's first day")
    s.weatherCycleStage = 2
    local w119 = byPlace(Mdl.weather(hoenn, s))["Route 119"]
    T.check(w119 and w119.kind == "thunder", "and a thunderstorm on its third")
  end
  T.eq(#Mdl.weather({ id = "kanto", places = r111 and { r111 } or {} }, s), 0, "FireRed and LeafGreen's regions: none")
  T.check(sand and sand.y and sand.y0 and sand.y >= sand.y0, "each knows the ground under it (its clouds go over it)")
  -- (a section the Town Map shows inside another -- Mt. Pyre on Route 122 -- brings its weather there)
  local okM, man = pcall(require("src.ui.game3.rse.region_map").manifest)
  local byId, from, onto = {}, nil, nil
  for _, p in ipairs(hoenn.places) do byId[p.id] = p end
  for _, sp in ipairs(okM and man.specialPlaces or {}) do
    local p = byId[sp[2]]
    if not from and p and not byId[sp[1]] and p.kind == "route" and not by[p.name] then from, onto = sp[1], p end
  end
  if from then
    maps.INSIDE = { regionMapSectionId = from, mapType = 3, width = 30, height = 30, weather = 6 }
    hoenn.wxSpots = nil
    local w = byPlace(Mdl.weather(hoenn, s))[onto.name]
    T.check(w and w.kind == "fog", "a section inside " .. onto.name .. ": its fog there")
    maps.INSIDE = nil
    hoenn.wxSpots = nil
  end
  -- the window: it eases in, the card knows, next to no garbage
  local ms = W.state
  ms.liveAt = -10
  draw(1)
  T.check(#ms.wx >= 3 and ms.wxBy[r111] == "sand" and ms.wxBy[r113] == "ash", "the map reads it (" .. #ms.wx .. ")")
  draw(120)
  local grown = true
  for _, a in ipairs(ms.wx) do grown = grown and a.grow == 1 end
  T.check(grown, "and it eases in")
  local wxKb = garbageOf(120, function() draw(1) end)
  T.check(wxKb < 0.5, string.format("the weather makes next to no garbage (%.3f KB/frame)", wxKb))
  maps.R113 = nil
  hoenn.wxSpots = nil
  ms.liveAt = -10
  draw(120)
  T.eq(ms.wxBy[r113], nil, "a weather that's gone eases out")
  s.weatherCycleStage = stage0
  Mdl.weatherData = data0
  hoenn.wxSpots = nil
end

-- ------- the game's Town Map and Fly map: ours instead

local RMname = RSE and "src.ui.game3.rse.region_map" or "src.ui.game3.region_map"
local RM = require(RMname)
T.check(rawget(RM, "__woobOs") ~= nil, "the region map's show is wrapped")
local origCalls = 0
local realOrig = RM.__woobOs.orig
RM.__woobOs.orig = function(o) origCalls = origCalls + 1 end
local function press(k)
  Tm.input(input({ k }, { k }))
  Tm.input(input({}, {}))
end
local picked, closed
local function showFly()
  picked, closed = nil, "no"
  RM.show({ session = s, mode = "fly",
            onPick = function(a, b) picked = { a, b } end,
            onClose = function(v) closed = v end })
end
showFly()
T.check(Tm.isOpen() and Stack.has(Sh.MAP_ID) and origCalls == 0, "Fly opens the 3D map, not the game's")
Tm.input(input({}, {}))   -- (the A that chose Fly let go)
Tm.draw(G, VP)
local tw = Tm.state().win
T.eq(tw.state.zoom, 1, "Fly mode starts on the whole region")
tw.focus(firstTown)
press("a")
T.check(not Tm.isOpen() and not Stack.has(Sh.MAP_ID), "A on a visited town: the map closes")
if RSE then
  T.check(picked and picked[1] == firstTown.id and type(picked[2]) == "table" and picked[2].posWithinMapSec == 0
    and closed == true, "Fly handed back as the game's map hands it: the section, its place in it, then onClose(true)")
else
  T.check(picked and picked[1] == firstTown.sym and picked[2] == firstTown.id and closed == "no",
    "Fly handed back as the game's map hands it: the section's symbol and number")
end
-- (B: closed as the game's map closes)
showFly()
Tm.input(input({}, {}))
press("b")
local wantClosed = nil
if RSE then wantClosed = false end
T.check(not Tm.isOpen() and picked == nil and closed == wantClosed, "B closes it, nothing picked")
-- (the Town Map item: START opens the game's own map with the same options)
local opened
RM.__woobOs.orig = function(o) origCalls, opened = origCalls + 1, o end
local itemOpts = { session = s }
RM.show(itemOpts)
T.check(Tm.isOpen() and Tm.state().win.state and #Tm.state().win.state.nav > 0, "the Town Map item opens the 3D map")
Tm.input(input({}, {}))
press("start")
T.check(not Tm.isOpen() and origCalls == 1 and opened == itemOpts, "START: the game's own map, as it would have opened")
-- (a tap on the screen's hints doesn't break it; the setting off: the game's own map at once)
Settings.set("map3d", false)
RM.show(itemOpts)
T.check(not Tm.isOpen() and origCalls == 2, "Settings' 3D Town Map off: the game's map")
Settings.set("map3d", true)
-- (the other family's module is left alone)
do
  local other = require(RSE and "src.ui.game3.region_map" or "src.ui.game3.rse.region_map")
  local w = rawget(other, "__woobOs")
  local calls = 0
  if w then
    local o = w.orig
    w.orig = function() calls = calls + 1 end
    other.show({ session = s })
    w.orig = o
  end
  T.check(not Tm.isOpen() and (not w or calls == 1), "the other games' map module is passed through")
end
-- (the Town Map's draw: next to no garbage either)
RM.show(itemOpts)
Tm.input(input({}, {}))
for _ = 1, 3 do Tm.draw(G, VP) end
local kb2 = garbageOf(120, function() Tm.draw(G, VP) end)
T.check(kb2 < 0.5, string.format("the Town Map's draw makes next to no garbage (%.3f KB/frame)", kb2))
press("b")
RM.__woobOs.orig = realOrig

-- ------- the words

do
  local function readFile(p)
    local f = io.open("mods/woob_os/" .. p, "rb")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
  end
  local en = assert(load(readFile("lang/en.lua"), "en", "t", {}))().strings
  local missing = {}
  local PREFIX = { map = 1, app = 1, hint = 1, settings = 1 }
  for _, file in ipairs({ "src/map3d/model.lua", "src/map3d/scene.lua", "src/townmap.lua", "src/apps/settings.lua" }) do
    for key in (readFile(file) or ""):gmatch('"([%a][%w_]*%.[%w_%.]+)"') do
      if PREFIX[key:match("^(%a+)")] and not key:match("%.$") and not key:match("%.lua$") and not en[key] then
        missing[#missing + 1] = key
      end
    end
  end
  for _, code in ipairs({ "none", "badge", "mon", "indoors" }) do
    if not en["map.why." .. code] then missing[#missing + 1] = "map.why." .. code end
  end
  T.eq(table.concat(missing, " "), "", "every word the map names is in English")
  for _, l in ipairs({ "fr", "de", "es", "it", "ja", "pt-br" }) do
    local t = assert(load(readFile("lang/" .. l .. ".lua"), l, "t", {}))().strings
    local gaps = {}
    for k, v in pairs(en) do
      if (k:match("^map%.") or k == "app.map" or k:match("^settings%.map")) then
        if not t[k] then gaps[#gaps + 1] = k
        elseif select(2, v:gsub("%%s", "")) ~= select(2, t[k]:gsub("%%s", "")) then gaps[#gaps + 1] = k .. " (%s)" end
      end
    end
    T.eq(table.concat(gaps, " "), "", l .. ": every map word, the same %s")
  end
end

T.finish("woob_os map3d (" .. GAME .. ")")
run.release()
