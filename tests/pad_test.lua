-- Standalone: luajit mods/woob_os/tests/pad_test.lua [game] (from the gen1recomp root; needs that
-- cart imported, FireRed by default).
--
-- WoobPad (src/desktop.lua as a tablet) and the notifications (src/notify.lua): the START menu's
-- row, the pad's home screen and dock, every app opening on it, ctx.over back to the app, B putting
-- it away, the notifications list (the W menu, a pull down from the top), the models'
-- notifications (outbid, ending soon, won, lost, a GTS trade), the field's banner and a tap on it
-- opening the pad, the setting that turns the banners off, and next to no garbage.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GAME = arg[1] or "firered"

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
local Wt, Nt, Sh, Apps, D = X._test.pad, X._test.notify, X._test.shell, X._test.apps, X._test.desktop
local Settings = X._test.settings
local Stack = require("src.ui.game3.stack")
local Runtime = require("src.mods.Runtime")
T.check(Wt ~= nil and Nt ~= nil and Wt.device == "pad", "the pad and the notifications are made")
-- (the settings kept in memory: never the real installation's file)
local kept = {}
Settings.cache = { read = function() return nil end, write = function(_, k, v) kept[k] = v end }

local VP = { width = 480, height = 320 }
local function draw(n, step)
  for _ = 1, n or 1 do
    clock = clock + (step or 1 / 60)
    Wt.draw(G, VP)
  end
end
local function garbageOf(n, setup, fn)
  local best = math.huge
  for _ = 1, 2 do
    if setup then setup() end
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
local function input(press, down)
  local p, d = {}, {}
  for _, k in ipairs(press or {}) do p[k] = true end
  for _, k in ipairs(down or {}) do d[k] = true end
  return { wasPressed = function(_, k) return p[k] == true end, isDown = function(_, k) return d[k] == true end }
end
local function press(k)
  Wt.input(input({ k }, { k }))
  Wt.input(input({}, {}))
end
local function ids(list)
  local out = {}
  for _, app in ipairs(list) do out[#out + 1] = app.id end
  return table.concat(out, " ")
end
local function hitOf(kind, arg)
  local st = Wt.state()
  for _, h in ipairs(st.hit) do
    if h.kind == kind and (arg == nil or h.arg == arg) then return h end
  end
end
local function tapHit(h)
  local x, y = h[1] + h[3] / 2, h[2] + h[4] / 2
  Wt.pointer({ id = 1, phase = "pressed", x = x, y = y })
  Wt.pointer({ id = 1, phase = "released", x = x, y = y })
end

local Storage, Bag = require("src.core.game3.storage"), require("src.core.game3.bag")
local ItemsData = require("src.core.game3.items_data")
local Party = require("src.core.game3.party")
local PokeG = require("src.core.game3.pokemon")
local function spOf(nat) return PokeG.speciesFromNational(nat) end
local function newSession()
  local s = { name = "WOS", playerName = "WOS", bag = Bag.new(), storage = Storage.new(), party = {}, money = 12345 }
  ItemsData.ensureModel(s)
  s.trainerId, s.secretId = 4321, 8765
  s.dex = { seen = {}, owned = {}, caught = {} }
  s.meta = { playthroughId = "watch-run" }
  return s
end
local s = newSession()
-- (the engine's session: the one a tap on the field's banner opens the watch with)
require("src.core.game3.runtime").getSession = function() return s end
Party.giveMon(s, spOf(16), 10)
Party.giveMon(s, spOf(19), 12)

-- ------- the pictures: a species' is never the shiny one (R-Bay's listings, Wonder Trade's picker)
do
  local env = X._test.env
  T.check(PokeG.isShiny({ species = spOf(385) }) == true,
    "(the engine: a bare species, no personality or OT ID, reads as shiny)")
  local real, seen = PokeG.monFrontPic, nil
  PokeG.monFrontPic = function(m, ...) seen = m return real(m, ...) end
  env.monPic(spOf(385), 0, 0, 16)
  PokeG.monFrontPic = real
  T.check(seen ~= nil and PokeG.isShiny(seen) == false, "a species' picture asks for the normal one")
  local shinyMon = { species = spOf(385), isShiny = true }
  seen = nil
  PokeG.monFrontPic = function(m, ...) seen = m return real(m, ...) end
  env.monPic(spOf(385), 0, 0, 16, 1, shinyMon)
  PokeG.monFrontPic = real
  T.check(seen == shinyMon, "a Pokémon's own picture is its own (shiny when it is)")
end

-- ------- the START menu's row

local function startList(save)
  local l = { { id = "pokedex", label = "POKéDEX" }, { id = "pokemon", label = "POKéMON" }, { id = "bag", label = "BAG" } }
  if save then l[#l + 1] = { id = "save", label = "SAVE" } end
  l[#l + 1] = { id = "option", label = "OPTION" }
  l[#l + 1] = { id = "exit", label = "EXIT" }
  return l
end
local function vanilla(_, items) return items end
local PAD_ID = Sh.PAD_ID
local K = X._test.kit
do
  local got = Runtime.call("ui.start_menu.items", vanilla, {}, startList(true))
  T.check(got[3].id == "bag" and got[4] and got[4].id == "woob_watch",
    "no PokéNav yet: the pad's row under BAG, where it would be (" .. ids(got) .. ")")
  T.eq(got[4].label, X._test.i18n("watch.start"), "its words: WOOBPAD")
  T.check(type(got[4].onSelect) == "function", "and its onSelect")
  local noBag = {}
  for _, e in ipairs(startList(true)) do if e.id ~= "bag" then noBag[#noBag + 1] = e end end
  local odd = Runtime.call("ui.start_menu.items", vanilla, {}, noBag)
  T.check(odd[#odd - 1].id == "woob_watch" and odd[#odd].id == "exit", "a menu without BAG: above EXIT (" .. ids(odd) .. ")")
  local link = Runtime.call("ui.start_menu.items", vanilla, {}, startList(false))
  T.check(not ids(link):find("woob_watch", 1, true), "not in a link room's or the Safari Zone's menu")
  Settings.set("watchRow", false)
  local off = Runtime.call("ui.start_menu.items", vanilla, {}, startList(true))
  T.check(not ids(off):find("woob_watch", 1, true), "Settings: the row off")
  Settings.set("watchRow", true)
  -- (Ruby / Sapphire / Emerald: in the PokéNav's place, the PokéNav's row gone)
  local withNav = startList(true)
  table.insert(withNav, 3, { id = "pokenav", label = "POKéNAV" })
  local nav = Runtime.call("ui.start_menu.items", vanilla, {}, withNav)
  T.check(nav[3].id == "woob_watch" and not ids(nav):find("pokenav", 1, true) and #nav == #withNav,
    "in the PokéNav's place (" .. ids(nav) .. ")")
  got[4].onSelect({}, s)
end
T.check(Wt.isOpen() and Stack.has(PAD_ID), "chosen: the pad opens on its layer")
local st = Wt.state()
local function all(state)
  local out = {}
  for _, a in ipairs(state.grid) do out[#out + 1] = a end
  for _, a in ipairs(state.dock) do out[#out + 1] = a end
  table.sort(out, function(a, b) return a.order < b.order or (a.order == b.order and a.id < b.id) end)
  return out
end
T.eq(ids(all(st)), "storage items map mail gts mart bank auction slots errands challenges news store settings",
  "every app, no PC rows (no Oak, Hall, Decorate, Log Off)")
T.check(st.booted, "no boot: the home screen at once")
T.check(not Sh.openWatch(s), "one pad at a time")
draw(5)
T.check(hitOf("grid", 1) ~= nil and hitOf("dock", 1) ~= nil, "its home screen and dock, tappable")
press("a")
T.check(Wt.window() == nil and st.zoom == nil, "the A that chose the row doesn't count (still held)")
Wt.input(input({}, {}))
press("right")
T.eq(st.cursor, 2, "Right: the next app")
do
  local L = st.layout
  T.check(L.pad and L.screen[4] > 120, "a big screen (" .. math.floor(L.screen[4]) .. " units tall)")
end

-- every app: opens on the pad and draws, at the window's shapes
local function launch(id)
  for i, a in ipairs(st.grid) do if a.id == id then st.focus, st.cursor = "grid", i end end
  for i, a in ipairs(st.dock) do if a.id == id then st.focus, st.dockCursor = "dock", i end end
  press("a")
end
for _, app in ipairs(all(st)) do
  if app.window then
    launch(app.id)
    T.check(st.zoom ~= nil, app.id .. ": zooms up from its icon")
    draw(30)
    T.check(Wt.window() ~= nil, app.id .. ": open on the pad")
    for _, shape in ipairs({ { 480, 320 }, { 320, 480 }, { 900, 320 } }) do
      VP.width, VP.height = shape[1], shape[2]
      draw(2)
    end
    VP.width, VP.height = 480, 320
    T.check(not st.winFailed, app.id .. ": draws on the pad at every shape")
    for _ = 1, 4 do
      if Wt.window() then press("b") end
    end
    if Wt.window() then Wt.closeWindow() end
    T.check(Wt.window() == nil, app.id .. ": closed, the home screen again")
    draw(20)
  end
end

-- ctx.over: the game's own screen over the pad, the app again after
do
  launch("storage")
  draw(30)
  local ctx = st.ctx
  local reopen
  ctx.over(function(onClose) reopen = onClose end, { mode = 1 })
  T.check(not Wt.isOpen() and not Stack.has(PAD_ID), "over: the pad steps aside for the game's screen")
  reopen()
  st = Wt.state()
  draw(2)
  T.check(Wt.isOpen() and Stack.has(PAD_ID) and Wt.window() and st.winApp.id == "storage",
    "and comes back on the app it was in")
  Wt.closeWindow()
  draw(20)
end

-- the notifications: from the W menu, and pulled down from the top
Nt.reset()
Nt.push("gts", { name = "PIDGEY", sp = spOf(16), who = "Yuki" }, true)
press("start")
T.check(st.menuOpen, "START: the W menu")
press("down")
press("a")
T.eq(st.sheet, "notes", "its second row: Notifications")
draw(2)
T.check(hitOf("noteRow", 1) ~= nil, "the list, a card each")
press("b")
T.eq(st.sheet, nil, "B: gone")
do
  local L = st.layout
  local x, y = K.X(L.screen[1] + L.screen[3] / 2), K.Y(L.screen[2] + 3)
  Wt.pointer({ id = 3, phase = "pressed", x = x, y = y })
  Wt.pointer({ id = 3, phase = "moved", x = x, y = y + 80 })
  Wt.pointer({ id = 3, phase = "released", x = x, y = y + 80 })
  T.eq(st.sheet, "notes", "pulled down from the top: the notifications")
  draw(2)
  tapHit(hitOf("noteRow", 1))
  T.check(Wt.window() and st.winApp.id == "gts", "a tap on one: its app")
  Wt.closeWindow()
  draw(20)
end

-- the drawer: it follows the finger down, springs back from a short pull; a card swiped off goes,
-- a short swipe springs back; Clear sends them all; the buttons do the same; pushed back up it shuts
do
  local Nd = Wt.drawer
  local L = st.layout
  local u = K.sc
  local x, y = K.X(L.screen[1] + L.screen[3] / 2), K.Y(L.screen[2] + 3)
  draw(30)
  Wt.pointer({ id = 4, phase = "pressed", x = x, y = y })
  Wt.pointer({ id = 4, phase = "moved", x = x, y = y + 40 * u })
  draw(1)
  T.check(st.sheet == "notes" and Nd.k() > 0.2 and Nd.k() < 0.6, ("it follows the finger (%.2f of the way)"):format(Nd.k()))
  Wt.pointer({ id = 4, phase = "moved", x = x, y = y + 10 * u })
  Wt.pointer({ id = 4, phase = "released", x = x, y = y + 10 * u })
  draw(40)
  T.check(st.sheet == nil and not Nd.visible(), "let go after a short pull: back up")
  Nt.reset()
  for i = 1, 4 do Nt.push("gts", { name = "PIDGEY", sp = spOf(16), who = "Yuki" .. i }, true) end
  Wt.sheet("notes")
  draw(40)
  T.check(Nd.k() > 0.99, "from the W menu: it slides all the way down")
  local first, second = Nt.list()[1], Nt.list()[2]
  local h = hitOf("noteRow", 1)
  local cx, cy = h[1] + h[3] / 2, h[2] + h[4] / 2
  Wt.pointer({ id = 5, phase = "pressed", x = cx, y = cy })
  Wt.pointer({ id = 5, phase = "moved", x = cx + 12 * u, y = cy })
  draw(1)
  T.check((first.uiX or 0) > 10, "a card follows a sideways drag")
  Wt.pointer({ id = 5, phase = "released", x = cx + 12 * u, y = cy })
  draw(40)
  T.check(Nt.list()[1] == first and math.abs(first.uiX or 0) < 0.5, "a short swipe: it springs back")
  Wt.pointer({ id = 6, phase = "pressed", x = cx, y = cy })
  Wt.pointer({ id = 6, phase = "moved", x = cx - 90 * u, y = cy })
  Wt.pointer({ id = 6, phase = "released", x = cx - 90 * u, y = cy })
  draw(40)
  T.check(#Nt.list() == 3 and Nt.list()[1] == second, "swiped off: that one's gone, the rest move up")
  T.eq(st.sheet, "notes", "and the drawer stays")
  Wt.input(input({}, {}))
  press("right")
  draw(5)
  T.eq(#Nt.list(), 3, "the first press of the D-pad only rings the chosen card")
  press("right")
  draw(40)
  T.eq(#Nt.list(), 2, "Right: the chosen card goes")
  tapHit(hitOf("noteClear"))
  draw(60)
  T.eq(#Nt.list(), 0, "Clear: all of them")
  T.check(hitOf("noteClear") == nil, "and Clear goes with them")
  Nt.push("gts", { name = "PIDGEY", sp = spOf(16), who = "Yuki" }, true)
  draw(5)
  press("select")
  draw(60)
  T.eq(#Nt.list(), 0, "SELECT: all of them")
  -- (pushed up by the handle: shut)
  local hx, hy = K.X(L.screen[1] + L.screen[3] / 2), K.Y(L.screen[2] + L.screen[4] - 4)
  Wt.pointer({ id = 7, phase = "pressed", x = hx, y = hy })
  Wt.pointer({ id = 7, phase = "moved", x = hx, y = hy - 30 * u })
  draw(1)
  T.check(Nd.k() < 0.85, "the handle pushes it up")
  Wt.pointer({ id = 7, phase = "released", x = hx, y = hy - 30 * u })
  draw(40)
  T.check(st.sheet == nil and not Nd.visible(), "let go: shut")
end

-- B on the home screen: put away, the START menu again
press("b")
T.check(not Wt.isOpen() and not Stack.has(PAD_ID), "B on the home screen: put away")

-- the home screen: the wallpaper chosen in Settings; Settings > WoobPad's alert choice
do
  local Wall = X._test.wall
  local realDraw = Wall.draw
  local drew
  Wall.draw = function(id) drew = id return true end
  Settings.set("wallpaper", "hills")
  Sh.openWatch(s)
  st = Wt.state()
  draw(2)
  T.eq(drew, "hills", "the chosen wallpaper")
  Settings.set("wallpaper", "classic")
  Wall.draw = realDraw
  Wt.openApp("settings")
  draw(2)
  local SW = Wt.window()
  local ss = SW.state
  local si, ti
  for i, sec in ipairs(SW.SECTIONS) do if sec.id == "notify" then si = i end end
  for i, t in ipairs(si and SW.SECTIONS[si].toggles or {}) do if t.key == "soonMinutes" then ti = i end end
  T.check(si ~= nil and ti ~= nil, "Settings > Notifications, R-Bay's ending-soon alert in it")
  ss.section, ss.focus, ss.toggleCursor = si, "detail", ti
  Wt.input(input({}, {}))
  press("a")
  T.eq(Settings.get("soonMinutes", 10), 15, "A on the alert: 15 minutes")
  press("right")
  T.eq(Settings.get("soonMinutes", 10), 30, "Right: 30")
  press("right")
  T.eq(Settings.get("soonMinutes", 10), 5, "and round to 5")
  press("left")
  T.eq(Settings.get("soonMinutes", 10), 30, "Left: back to 30")
  draw(2)
  T.check(not st.winFailed, "the Notifications section draws")
  Settings.set("soonMinutes", 10)
  -- each app that tells the player things: its own switch (the Phone only where calls come)
  local rows, keys, at = SW.SECTIONS[si].toggles, {}, {}
  for i, t in ipairs(rows) do keys[#keys + 1] = t.key; at[t.key] = i end
  T.eq(rows[1].key, "notifications", "the banners first")
  T.check(at.notifyAuction and at.notifyGts and at.notifyBank and at.notifyErrands and at.notifyChallenges
    and at.notifyNews and rows[at.notifyAuction].app ~= nil, "an app's switch each, with its icon (" .. table.concat(keys, " ") .. ")")
  T.eq(at.notifyPhone ~= nil, Sh.gameId() == "emerald", "the Phone's only where calls come")
  -- R-Bay off: A on its row; nothing from it, the GTS's still come
  ss.toggleCursor = at.notifyAuction
  press("a")
  T.eq(Settings.get("notifyAuction", true), false, "A: R-Bay's notifications off")
  local before = #Nt.list()
  T.eq(Nt.push("outbid", { name = "MEW" }), nil, "R-Bay off: nothing from it")
  T.eq(#Nt.list(), before, "not even in the list")
  T.check(Nt.push("gts", { name = "PIDGEY", who = "Yuki" }) ~= nil and #Nt.list() == before + 1, "the GTS's still come")
  press("a")
  T.eq(Settings.get("notifyAuction", true), true, "A again: back on")
  -- (more rows than fit: the cursor's row kept in view, the wheel scrolls)
  draw(2)
  if #rows > ss.toggleVisible then
    ss.toggleCursor = 1
    for _ = 1, #rows do press("down") end
    draw(2)
    T.check(ss.toggleCursor == #rows and ss.toggleTop > 0 and ss.toggleCursor <= ss.toggleTop + ss.toggleVisible,
      "Down to the last row: the list scrolls with it")
    SW.scroll(400)
    T.eq(ss.toggleTop, 0, "the wheel scrolls back up")
  end
  T.check(not st.winFailed, "and it draws")
  st.ctx.done()
end

-- ------- the notifications from the models

local Au = X._test.auction
local fakeSave = { data = {} }
function fakeSave.get(self, k) return self.data[k] end
function fakeSave.set(self, k, v) self.data[k] = v end
local store0, now0 = Au.store, Au.now
Au.store = fakeSave
local tnow = 1800000000
Au.now = function() return tnow end
Nt.reset()
s.money = 500000
local function kinds()
  local out = {}
  for i = #Nt.list(), 1, -1 do out[#out + 1] = Nt.list()[i].kind end
  return table.concat(out, " ")
end
-- outbid at once by a leader's maximum: the list has it, no banner (the window said so)
do
  local Lo, tt
  for _, at in ipairs({ 0.3, 0.5, 0.7 }) do
    for _, L in ipairs(Au.listings(s, tnow)) do
      local t1 = math.floor(L.start + (L.finish - L.start) * at)
      local _, leader, lmax = Au.sim(L, t1, nil)
      if not Lo and leader and lmax > Au.minBid(L) + Au.step(Au.minBid(L)) and t1 >= tnow and L.finish - t1 > 1200 then
        Lo, tt = L, t1
      end
    end
    if Lo then break end
  end
  T.check(Lo ~= nil, "an auction led by a high maximum")
  if Lo then
    tnow = tt
    Au.listings(s, tnow)
    T.check(Au.bid(s, Lo, Au.minBid(Lo), tnow) and Lo.leader ~= 0, "a bid under it: outbid at once")
    T.eq(kinds(), "outbid", "a notification: outbid")
    T.eq(Nt.waiting(), 0, "quiet: the bid's own window says so")
    -- the alert set to 30 minutes: not at 31 minutes left, told at 25 (once)
    Settings.set("soonMinutes", 30)
    tnow = Lo.finish - 31 * 60
    Au.settle(s, tnow)
    T.eq(kinds(), "outbid", "Settings 30 minutes: not yet at 31 left")
    tnow = Lo.finish - 25 * 60
    Au.settle(s, tnow)
    T.eq(kinds(), "outbid soon", "25 minutes left: ending soon")
    T.check(Nt.list()[1].text:find("30", 1, true) ~= nil, "its words say 30 minutes (" .. Nt.list()[1].text .. ")")
    Settings.set("soonMinutes", 10)
    T.eq(Nt.waiting(), 1, "a banner waiting")
    Au.settle(s, tnow + 5)
    T.eq(kinds(), "outbid soon", "only once")
    tnow = Lo.finish + 1
    Au.settle(s, tnow)
    T.eq(kinds(), "outbid soon lost", "it ends: lost")
    T.eq(Nt.list()[1].app, "auction", "R-Bay's")
  end
end
-- a win: a bid nobody beats
do
  s.money = 999999
  local Lp = Au.listings(s, tnow)[12]
  T.check(Au.bid(s, Lp, 999000, tnow), "(a bid nobody beats)")
  local won = Au.settle(s, Lp.finish + 1)
  T.check(won == 1 and Nt.list()[1].kind == "won", "won: a notification")
  T.check(Nt.list()[1].state and Nt.list()[1].state.tab == "mine", "it opens R-Bay's My Bids")
end
Au.store, Au.now = store0, now0

-- a GTS deposit answered
do
  local Gx = X._test.gts
  local BxG = X._test.bx
  local gtsSave = { data = {} }
  function gtsSave.get(self, k) return self.data[k] end
  function gtsSave.set(self, k, v) self.data[k] = v end
  local gStore0, gRng0, gNow0 = Gx.store, Gx.rng, Gx.now
  Gx.store = gtsSave
  local lcg = 777
  Gx.rng = function(n)
    lcg = (lcg * 1103515245 + 12345) % 2147483648
    return lcg % n + 1
  end
  local gnow = 1800000000
  Gx.now = function() return gnow end
  local ok = Gx.deposit(s, BxG.addr("party", 2), spOf(16), 1, gnow)
  T.check(ok and Gx.settle(s, Gx.posted().matchAt), "a GTS deposit answered")
  local rec = Nt.list()[1]
  T.check(rec.kind == "gts" and rec.app == "gts" and rec.state.tab == "deposit" and rec.sp ~= nil,
    "a notification: the GTS, its deposit tab, the Pokémon")
  Gx.store, Gx.rng, Gx.now = gStore0, gRng0, gNow0
end

-- ------- shiny Pokémon: one in ten on R-Bay and the GTS, the badge's, and what you get is shiny
do
  local Au, Gx = X._test.auction, X._test.gts
  local fake = { data = {} }
  function fake.get(self, k) return self.data[k] end
  function fake.set(self, k, v) self.data[k] = v end
  local store0, now0 = Au.store, Au.now
  Au.store = fake
  local shinies, total, pics = 0, 0, true
  for n = 9000, 9199 do
    for k = 0, 11 do
      local L = Au.generate(s, k, n, 0)
      total = total + 1
      if L.shiny then
        shinies = shinies + 1
        pics = pics and L.picMon ~= nil and L.picMon.isShiny == true
      end
    end
  end
  T.check(shinies > total * 0.07 and shinies < total * 0.13,
    ("R-Bay: about one listing in ten is shiny (%d of %d)"):format(shinies, total))
  T.check(pics, "a shiny listing's picture is the shiny one")
  -- the Hot Auction: a shiny one when there is (a mythical may still win it)
  local tt, found
  for step = 0, 200 do
    tt = 1800000000 + step * 900
    for _, L in ipairs(Au.listings(s, tt)) do
      if L.shiny and L.finish - tt > 3600 then found = L end
    end
    if found then break end
  end
  T.check(found ~= nil, "a shiny auction running")
  if found then
    Au.now = function() return tt end
    -- (a bid nobody beats, then it ends: the winner's Pokémon is shiny, its OT the player)
    s.money = 999999
    s.party = { s.party[1] }
    T.check(Au.bid(s, found, 999000, tt), "a bid on the shiny one")
    local won = Au.settle(s, found.finish + 1)
    local got = s.party[#s.party]
    T.check(won == 1 and got and tonumber(got.species) == found.sp and PokeG.isShiny(got),
      "won: the Pokémon is shiny, as listed")
    T.check(Au.results()[1].shiny == true, "and its result says so")
  end
  Au.store, Au.now = store0, now0
  -- the GTS: a stranger's shiny is shiny for its own OT; one in ten listings
  local Gx0 = Gx.rng
  local lcg = 4242
  Gx.rng = function(n)
    lcg = (lcg * 1103515245 + 12345) % 2147483648
    return lcg % n + 1
  end
  local recv = Gx.make(s, spOf(129), 20, Gx.STRANGERS[2], 0x12345678, true)
  T.check(recv and PokeG.isShiny(recv) and recv.otName == "Pierre", "the GTS: a stranger's shiny Magikarp, theirs")
  local plain = 0
  for _ = 1, 200 do
    local m = Gx.make(s, spOf(129), 20, Gx.STRANGERS[2], 0x12345678, false)
    if m and PokeG.isShiny(m) then plain = plain + 1 end
  end
  T.check(plain <= 2, "not asked for: shiny only at the game's own odds (" .. plain .. " of 200)")
  Gx.rng = Gx0
  local gs, gt = 0, 0
  for w = 1, 60 do
    for _, L in ipairs(Gx.offers(s, 1800000000 + w * 1800)) do
      gt = gt + 1
      if L.shiny then gs = gs + 1 end
    end
  end
  T.check(gt > 0 and gs > gt * 0.04 and gs < gt * 0.18, ("the GTS: about one listing in ten shiny (%d of %d)"):format(gs, gt))
end

-- ------- the banner over the field

Nt.reset()
Nt.push("outbid", { name = "PIKACHU", sp = spOf(25), key = "1:2" })
T.eq(Nt.waiting(), 1, "a banner waits")
clock = clock + 1
T.check(not Nt.drawField(G, { width = 480, height = 320, gameX = 0, gameY = 0, gameWidth = 480, gameHeight = 320, scale = 2 }, false, clock),
  "not while the player isn't free (a script, a menu, a battle)")
T.eq(Nt.waiting(), 1, "it keeps waiting")
local FVP = { width = 480, height = 320, gameX = 0, gameY = 0, gameWidth = 480, gameHeight = 320, scale = 2 }
T.check(Nt.drawField(G, FVP, true, clock), "free: it slides in")
clock = clock + 0.5
Nt.drawField(G, FVP, true, clock)
T.check(Nt.showing() ~= nil, "held a while")
do
  local F = Nt.FIELD
  local x, y = (F.x + F.w / 2) * 2, (F.y + F.h / 2) * 2
  T.check(Sh.pointer({ id = 1, phase = "pressed", x = x, y = y }) == true, "a tap on it is ours")
end
draw(1)
T.check(Wt.isOpen() and Wt.window() and Wt.state().winApp.id == "auction", "and opens the pad on R-Bay")
T.eq(Wt.window().state.tab, "browse", "on the auction it was about")
st = Wt.state()
draw(3)
st.ctx.done()
T.check(not Wt.isOpen() and not Stack.has(PAD_ID), "put away: the field again")
-- one not tapped goes after its time
Nt.push("soon", { name = "EEVEE", sp = spOf(133) })
Nt.drawField(G, FVP, true, clock)
clock = clock + Nt.IN + Nt.HOLD + Nt.OUT + 0.1
T.check(not Nt.drawField(G, FVP, true, clock) and Nt.showing() == nil, "untapped: it slides away")
T.check(Sh.pointer({ id = 1, phase = "pressed", x = 100, y = 20 }) == nil, "and a tap there is the game's again")
-- the setting off: the list only
Settings.set("notifications", false)
Nt.push("outbid", { name = "MEW" })
T.eq(Nt.waiting(), 0, "Settings: notifications off, no banner")
T.eq(Nt.list()[1].text ~= nil and Nt.list()[1].kind, "outbid", "it's still in the list")
Settings.set("notifications", true)
-- a banner while the pad is open: over its screen, a tap opens that app
Sh.openWatch(s)
st = Wt.state()
Wt.input(input({}, {}))
draw(2)
Nt.push("gts", { name = "PIDGEY", sp = spOf(16), who = "Yuki" })
draw(10)
local bh = hitOf("notify")
T.check(bh ~= nil, "on the pad: the banner over its screen")
if bh then tapHit(bh) end
T.check(Wt.window() and st.winApp.id == "gts", "tapped: the GTS opens")
draw(3)

-- ------- garbage

local fieldKb = garbageOf(60, function() Nt.reset(); Nt.push("outbid", { name = "PIKACHU", sp = spOf(25) }) end,
  function() Nt.drawField(G, FVP, true, clock) end)
T.check(fieldKb < 0.5, ("the field's banner: next to no garbage (%.3f KB a frame)"):format(fieldKb))
if Wt.window() then Wt.closeWindow() end
draw(30)
-- (the money's Pokédollar sign: a stand-in while measuring, the engine's glyph draw makes
-- garbage headless; the probe measures the real one)
local FrlgFont = require("src.ui.game3.frlg_font")
local realGlyph = FrlgFont.drawGlyph
FrlgFont.drawGlyph = function() return 7 end
local homeKb = garbageOf(60, nil, function() Wt.draw(G, VP) end)
T.check(homeKb < 0.5, ("the home screen: next to no garbage (%.3f KB a frame)"):format(homeKb))
Wt.sheet("notes")
draw(40)   -- (slid all the way down first)
local notesKb = garbageOf(60, nil, function() Wt.draw(G, VP) end)
T.check(notesKb < 0.5, ("the notifications: next to no garbage (%.3f KB a frame)"):format(notesKb))
FrlgFont.drawGlyph = realGlyph
st.ctx.done()

-- ------- the Kanto Gear apps: through its public hook, stood in
;(function()
  local Gear, Tm = X._test.gear, X._test.townmap
  local registered = {}
  local hook = { api = 1, register = function(spec) registered[#registered + 1] = spec; return true end }
  local find0 = Gear.find
  T.eq(#Gear.specs, 0, "no Kanto Gear: nothing registered")
  Gear.find = function() return { exports = { modules = { api = 2, register = hook.register } } } end
  Gear.bind()
  T.eq(#registered, 0, "an api it doesn't know: nothing either")
  Gear.find = function(id) return id == "kanto_gear" and { exports = { modules = hook } } or nil end
  Gear.bind()
  Gear.bind()
  T.eq(#registered, 3, "three tiles, once however often the game's ready")
  local ACCENT = { blue = true, amber = true, red = true, green = true, slate = true }
  local byApp = {}
  for _, spec in ipairs(registered) do
    byApp[spec.id] = spec
    T.check(spec.id:match("^[a-z0-9_]+$") ~= nil, spec.id .. ": a valid id")
    T.check(#spec.label <= 20 and #spec.description >= 1 and #spec.description <= 3 and ACCENT[spec.accent] ~= nil,
      spec.id .. ": within the hook's limits")
    T.check(spec.available({ generation = 3 }) and not spec.available({ generation = 1 }), spec.id .. ": Gen 3 only")
    for code, words in pairs(spec.translations) do
      T.check(words[spec.description[1]] ~= nil and words[spec.description[2]] ~= nil, spec.id .. ": " .. code)
    end
    T.check(pcall(spec.icon, 0, 0, false) and pcall(spec.icon, 0, 0, true), spec.id .. ": its icon draws, and greyed")
  end
  T.check(byApp.woob_slots and byApp.woob_rbay and byApp.woob_gts, "Slots, R-Bay and the GTS")

  local free0 = Sh.free
  local gts, slots = byApp.woob_gts, byApp.woob_slots
  local Gp, K = X._test.gearPanel, X._test.kit
  local bridge0 = Gp.bridge
  Gp.bridge = nil
  local function full(c) return { x = 0, y = 0, width = c.width, height = c.height } end
  local function frame(nxt)
    local rect = Gp.viewport(nxt or full, { width = 480, height = 320 })
    Gp.frame()
    return rect
  end
  local function tap(x, y, id)
    local a = Gp.pointer({ id = id or 1, phase = "pressed", x = x, y = y })
    local b = Gp.pointer({ id = id or 1, phase = "released", x = x, y = y })
    return a and b
  end
  -- (a hit over the whole of the app's body, last on top)
  local tapped
  local function spy()
    local st = Gp.hostState()
    local d = st.win.draw
    st.win.draw = function(b, c, p) d(b, c, p); K.addHit(b, "win", 99) end
    st.win.tap = function(arg) tapped = arg end
    tapped = nil
  end

  Sh.free = function() return false end
  T.check(not gts.open() and not gts.shown() and not Gp.isOpen(), "not free in the field: refused, nothing opened")
  Sh.free = function() return true end
  T.check(gts.open(), "free: it opens")
  T.check(gts.shown() and not slots.shown(), "the Gear stands down for that one")
  T.check(Gp.isOpen() and not Tm.isOpen() and not Stack.has(Sh.MAP_ID) and not Wt.isOpen(),
    "on its own screen: nothing on the game's stack, the PC's and pad's hosts untouched")
  T.check(not slots.open(), "and no second one over it")

  -- no second display: under the game
  local rect = frame()
  T.eq(Gp.mode(), "stacked", "no second display: in the window")
  T.check(rect.y == 0 and rect.width == 480 and rect.height == 160, "the game above it")
  spy()
  frame()
  T.check(Gp.pointer({ id = 2, phase = "pressed", x = 240, y = 50 }) == false, "a press on the game's half is the game's")
  T.check(tap(240, 240) and tapped == 99, "a tap on the panel is the app's")
  K.frame(G, FVP, Tm.PAGE, 0)
  tapped = nil
  T.check(tap(240, 240) and tapped == 99, "and survives another host drawing in the same frame")
  Gp.pointer({ id = 3, phase = "pressed", x = 240, y = 240 })
  T.check(Gp.pointer({ id = 3, phase = "released", x = 240, y = 50 }) == true, "a press that began on the panel ends there")

  -- the game busy above it
  Sh.free = function() return false end
  frame()
  tapped = nil
  tap(240, 240)
  T.eq(tapped, nil, "the game busy: locked")
  T.check(gts.shown(), "but still up")
  Sh.free = function() return true end
  frame()
  tap(240, 240)
  T.eq(tapped, 99, "free again: it works")

  -- a traded Pokémon's evolution: on the game's screen, this one locked, then made again
  local finished
  Gp.hostState().ctx.over(function(onClose) finished = onClose end, { tab = "deposit" })
  T.check(gts.shown() and Gp.isOpen() and not Stack.has(Sh.MAP_ID), "over: the game's screen, this one stays")
  frame()
  tapped = nil
  tap(240, 240)
  T.eq(tapped, nil, "and is locked meanwhile")
  local oldWin = Gp.hostState().win
  finished()
  T.check(Gp.isOpen() and Gp.hostState().win ~= oldWin and gts.shown(), "the app again after")
  frame()

  -- the toolbar's way back
  T.check(tap(50, 166) and not gts.shown() and not Gp.isOpen(), "< Gear closes it, the Gear comes back")

  -- where the Gear's combined layout was
  local function tall(c) return { x = 0, y = 0, width = c.width, height = 200 } end
  T.eq(frame(tall).height, 200, "(the Gear's own layout, seen while it's up)")
  T.check(gts.open(), "open again")
  T.eq(frame().height, 200, "the game stays where the Gear had it")
  T.check(Gp.pointer({ id = 4, phase = "pressed", x = 240, y = 190 }) == false, "and the panel starts under it")
  Sh.closeGear()
  T.check(not gts.shown(), "closed by a reset")

  -- a separate display: the game keeps the window, frames and taps go through the bridge
  frame()
  local pushes, last, queue, freed = 0, nil, {}, 0
  Gp.bridge = function()
    return { available = function() return true end,
             push = function(d, w, h, b, p) pushes = pushes + 1; last = { w = w, h = h, p = p } end,
             pollTouch = function() return table.remove(queue, 1) end }
  end
  local newCanvas0, getCanvas0 = love.graphics.newCanvas, love.graphics.getCanvas
  local getTime0, tick = love.timer.getTime, 100
  love.timer.getTime = function() return tick end
  local canvasFake = { newImageData = function() return { release = function() freed = freed + 1 end } end, release = function() end }
  love.graphics.newCanvas = function() return canvasFake end
  T.check(gts.open(), "with a second display")
  rect = frame()
  T.eq(Gp.mode(), "external", "it goes there")
  T.check(rect.width == 480 and rect.height == 320, "the game keeps the whole window")
  T.check(pushes == 1 and last.w == 744 and last.h == 648 and last.p == "secondary" and freed == 1, "a frame sent, its memory let go")
  frame()
  T.eq(pushes, 1, "(at most thirty a second)")
  T.check(Gp.pointer({ id = 5, phase = "pressed", x = 240, y = 240 }) == false, "the window's own touches are the game's")
  spy()
  tick = tick + 1
  frame()
  queue[1], queue[2] = "down,360,240", "up,360,240"
  tick = tick + 1
  frame()
  T.eq(tapped, 99, "its taps are the app's")
  local scrolled
  Gp.hostState().win.scroll = function(dy) scrolled = dy end
  tapped = nil
  queue[1], queue[2] = "down,360,200", "up,360,320"
  tick = tick + 1
  frame()
  T.check(scrolled ~= nil and math.abs(scrolled - 120 / 3.375) < 0.01 and tapped == nil, "a release elsewhere is a drag (" .. tostring(scrolled) .. ")")
  queue[1], queue[2] = "down,20,20", "up,20,20"
  tick = tick + 1
  frame()
  T.check(not gts.shown(), "< Gear from the second display")
  -- a high-DPI device (Android always is): a canvas of exactly the picture's pixels, fonts to match
  local madeW, madeH, madeOpts
  local newFont0, fontScale = love.graphics.newFont, nil
  love.graphics.newFont = function(px, hinting, dpi) fontScale = dpi; return newFont0(px, hinting, dpi) end
  love.graphics.newCanvas = function(w, h, o)
    madeW, madeH, madeOpts = w, h, o
    return { newImageData = function()
      return { getDimensions = function() return w, h end, release = function() end }
    end, release = function() end }
  end
  T.check(gts.open(), "on a high-DPI device")
  tick = tick + 1
  frame()
  tick = tick + 1
  frame()
  T.check(madeW == 744 and madeH == 648 and madeOpts and madeOpts.dpiscale == 1, "the canvas is one pixel a unit")
  T.check(last.w == 744 and last.h == 648, "and the picture says those pixels")
  K.frame(G, FVP, Tm.PAGE, 0)
  K.exactFonts(true)
  K.width("a size no other test uses", 41.7)
  K.exactFonts(false)
  T.eq(fontScale, 1, "its fonts are made one pixel a unit too")
  K.width("and the window's own", 43.1)
  T.eq(fontScale, nil, "and the window's stay as they were")
  love.graphics.newFont = newFont0
  queue[1], queue[2] = "down,20,20", "up,20,20"
  tick = tick + 1
  frame()
  T.check(not gts.shown(), "< Gear in the picture's own pixels")
  love.graphics.newCanvas, love.graphics.getCanvas, love.timer.getTime = newCanvas0, getCanvas0, getTime0

  Gp.bridge = nil
  frame()
  for _, id in ipairs({ "woob_slots", "woob_rbay" }) do
    T.check(byApp[id].open() and byApp[id].shown(), id .. " opens")
    FrlgFont.drawGlyph = function() return 7 end
    frame()
    local kb = garbageOf(60, nil, function() Gp.frame() end)
    FrlgFont.drawGlyph = realGlyph
    T.check(kb < 0.5, id .. (": next to no garbage (%.3f KB a frame)"):format(kb))
    Gp.hostState().ctx.done()
    T.check(not byApp[id].shown() and not Gp.isOpen(), id .. " closes")
  end
  Sh.free, Gear.find, Gp.bridge = free0, find0, bridge0
end)()

run.release()
T.finish("woob_os pad (" .. GAME .. ")")
