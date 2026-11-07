-- Standalone: luajit mods/woob_os/tests/watch_test.lua [game] (from the gen1recomp root; needs that
-- cart imported, FireRed by default).
--
-- WoobWatch (src/watch.lua) and the notifications (src/notify.lua): the START menu's row, the
-- watch's face, apps and notifications list, every app opening on it, ctx.over back to the app,
-- the models' notifications (outbid, ending soon, won, lost, a GTS trade), the field's banner and
-- a tap on it opening the watch, the setting that turns the banners off, and next to no garbage.
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
local Wt, Nt, Sh, Apps, D = X._test.watch, X._test.notify, X._test.shell, X._test.apps, X._test.desktop
local Settings = X._test.settings
local Stack = require("src.ui.game3.stack")
local Runtime = require("src.mods.Runtime")
T.check(Wt ~= nil and Nt ~= nil, "the watch and the notifications are made")
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
do
  local got = Runtime.call("ui.start_menu.items", vanilla, {}, startList(true))
  T.check(got[#got - 1] and got[#got - 1].id == "woob_watch" and got[#got].id == "exit",
    "the watch's row, just above EXIT (" .. ids(got) .. ")")
  T.check(type(got[#got - 1].label) == "string" and got[#got - 1].label ~= "" and type(got[#got - 1].onSelect) == "function",
    "with its words and onSelect")
  local link = Runtime.call("ui.start_menu.items", vanilla, {}, startList(false))
  T.check(not ids(link):find("woob_watch", 1, true), "not in a link room's or the Safari Zone's menu")
  Settings.set("watchRow", false)
  local off = Runtime.call("ui.start_menu.items", vanilla, {}, startList(true))
  T.check(not ids(off):find("woob_watch", 1, true), "Settings: the row off")
  Settings.set("watchRow", true)
  -- choosing it: the watch over the START menu
  got[#got - 1].onSelect({}, s)
end
T.check(Wt.isOpen() and Stack.has("woob_watch"), "chosen: the watch opens on its layer")
local st = Wt.state()
T.eq(st.screen, "face", "on its face")
T.eq(ids(st.apps), "storage items mail gts mart auction slots settings",
  "every app with a window (no Oak, Hall, Decorate, About, Log Off)")
T.check(not Sh.openWatch(s), "one watch at a time")
draw(5)
T.check(hitOf("wface") ~= nil and hitOf("wcomp", 1) ~= nil, "the face: tappable, its complications")
press("a")
T.check(st.screen ~= "face" or st.waitRelease == false, "the A that chose the row doesn't count (still held)")
Wt.input(input({}, {}))
press("a")
T.eq(st.screen, "grid", "A: the apps")
draw(3)
T.check(hitOf("wgrid", 1) ~= nil, "the honeycomb's icons, tappable")
press("right")
T.eq(st.cursor, 2, "Right: the next app")
press("down")
T.check(st.pos[st.cursor].row == 2, "Down: the row under it")
press("l")
local c0 = st.cursor
press("r")
T.eq(st.cursor, c0 + 1, "R turns the crown on")

-- every app: opens on the watch and draws, at the window's shapes
for i, app in ipairs(st.apps) do
  st.cursor = i
  press("a")
  T.check(st.zoom ~= nil, app.id .. ": zooms up from its icon")
  draw(30)
  T.check(Wt.window() ~= nil and st.screen == "app", app.id .. ": open on the watch")
  for _, shape in ipairs({ { 480, 320 }, { 320, 480 }, { 900, 320 } }) do
    VP.width, VP.height = shape[1], shape[2]
    draw(2)
  end
  VP.width, VP.height = 480, 320
  T.check(not st.winFailed, app.id .. ": draws on the watch at every shape")
  -- (B: back to the apps, unless the window used it; tap the back chevron then)
  press("b")
  if Wt.window() then
    draw(1)
    local back = hitOf("wback")
    if back then tapHit(back) end
  end
  T.check(Wt.window() == nil and st.screen == "grid", app.id .. ": back to the apps")
  draw(20)
end

-- ctx.over: the game's own screen over the watch, the app again after
do
  local i
  for j, app in ipairs(st.apps) do if app.id == "storage" then i = j end end
  st.cursor = i
  press("a")
  draw(30)
  local ctx = st.ctx
  local reopen
  ctx.over(function(onClose) reopen = onClose end, { mode = 1 })
  T.check(not Wt.isOpen() and not Stack.has("woob_watch"), "over: the watch steps aside for the game's screen")
  reopen()
  st = Wt.state()
  draw(2)
  T.check(Wt.isOpen() and Stack.has("woob_watch") and Wt.window() and st.winApp.id == "storage",
    "and comes back on the app it was in")
  press("b")
  if Wt.window() then
    draw(1)
    local back = hitOf("wback")
    if back then tapHit(back) end
  end
  draw(20)
end

-- the face, the notifications list, closing
press("b")
T.eq(st.screen, "face", "B on the apps: the face")
press("down")
T.eq(st.screen, "notes", "Down: the notifications")
draw(2)
press("b")
T.eq(st.screen, "face", "B: the face again")
press("b")
T.check(not Wt.isOpen() and not Stack.has("woob_watch"), "B on the face: closed, the START menu again")

-- the face: the wallpaper chosen in Settings; a swipe down for the notifications, up for the face
do
  local Wall = X._test.wall
  local realDraw = Wall.draw
  local drew
  Wall.draw = function(id) drew = id return true end
  Settings.set("wallpaper", "hills")
  Sh.openWatch(s)
  st = Wt.state()
  draw(2)
  T.eq(drew, "hills", "the face shows the chosen wallpaper")
  Settings.set("wallpaper", "classic")
  Wall.draw = realDraw
  local f = hitOf("wface")
  local x, y = f[1] + f[3] / 2, f[2] + 10
  Wt.pointer({ id = 3, phase = "pressed", x = x, y = y })
  Wt.pointer({ id = 3, phase = "moved", x = x, y = y + 60 })
  Wt.pointer({ id = 3, phase = "released", x = x, y = y + 60 })
  T.eq(st.screen, "notes", "a swipe down: the notifications")
  draw(2)
  Wt.pointer({ id = 4, phase = "pressed", x = x, y = y + 60 })
  Wt.pointer({ id = 4, phase = "moved", x = x, y = y - 40 })
  Wt.pointer({ id = 4, phase = "released", x = x, y = y - 40 })
  T.eq(st.screen, "face", "a swipe up: the face again")
  -- Settings > Watch: the ending-soon alert, 5 / 10 / 15 / 30 minutes
  Wt.openApp("settings")
  draw(2)
  local ss = Wt.window().state
  ss.section, ss.focus, ss.toggleCursor = 3, "detail", 3
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
  T.check(not st.winFailed, "the Watch section draws")
  Settings.set("soonMinutes", 10)
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
T.check(Wt.isOpen() and Wt.window() and Wt.state().winApp.id == "auction", "and opens the watch on R-Bay")
T.eq(Wt.window().state.tab, "browse", "on the auction it was about")
st = Wt.state()
draw(3)
st.ctx.done()
T.check(not Wt.isOpen() and not Stack.has("woob_watch"), "closed: the field again")
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
-- a banner while the watch is open: over its screen, a tap opens that app
Sh.openWatch(s)
st = Wt.state()
Wt.input(input({}, {}))
draw(2)
Nt.push("gts", { name = "PIDGEY", sp = spOf(16), who = "Yuki" })
draw(10)
local bh = hitOf("wbanner")
T.check(bh ~= nil, "on the watch: the banner over its screen")
if bh then tapHit(bh) end
T.check(Wt.window() and st.winApp.id == "gts", "tapped: the GTS opens")
draw(3)

-- ------- garbage

local fieldKb = garbageOf(60, function() Nt.reset(); Nt.push("outbid", { name = "PIKACHU", sp = spOf(25) }) end,
  function() Nt.drawField(G, FVP, true, clock) end)
T.check(fieldKb < 0.5, ("the field's banner: next to no garbage (%.3f KB a frame)"):format(fieldKb))
if Wt.window() then Wt.closeWindow() end
draw(30)
st.screen = "face"
-- (the money's Pokédollar sign: a stand-in while measuring, the engine's glyph draw makes
-- garbage headless; the probe measures the real one)
local FrlgFont = require("src.ui.game3.frlg_font")
local realGlyph = FrlgFont.drawGlyph
FrlgFont.drawGlyph = function() return 7 end
local faceKb = garbageOf(60, nil, function() Wt.draw(G, VP) end)
FrlgFont.drawGlyph = realGlyph
T.check(faceKb < 0.5, ("the face: next to no garbage (%.3f KB a frame)"):format(faceKb))
st.screen = "grid"
local gridKb = garbageOf(60, nil, function() Wt.draw(G, VP) end)
T.check(gridKb < 0.5, ("the apps: next to no garbage (%.3f KB a frame)"):format(gridKb))
st.ctx.done()

run.release()
T.finish("woob_os watch (" .. GAME .. ")")
