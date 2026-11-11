-- Standalone: luajit mods/woob_os/tests/pokenav_test.lua [game] (from the gen1recomp root; needs that
-- cart imported, Emerald by default).
--
-- The PokéNav's apps (src/phone.lua, src/condition.lua, their windows, src/pokenav.lua): the Phone's
-- contacts from the game's Match Call flags, a call with the game's words logged to Recents, the
-- favourites and the log kept in the save, the field's calls; the conditions read, the search
-- ranked, a Pokéblock fed by the game's own rules (and refused at full sheen); the PokéNav's
-- Match Call / Condition (Ruby / Sapphire: Condition) opening ours and handing back to the PokéNav
-- as the game's screens do, the tutorial's forced call, the search's graph and the setting off
-- passed through; next to no garbage; the words. FireRed / LeafGreen: none of it shows.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GAME = arg[1] or "emerald"
local RSE = not (GAME == "firered" or GAME == "leafgreen")
local EMERALD = GAME == "emerald"

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
local Ph, Cd, Sh, Tm, Apps, Nt = X._test.phone, X._test.condition, X._test.shell, X._test.townmap, X._test.apps,
  X._test.notify
local Settings, K, I18n = X._test.settings, X._test.kit, X._test.i18n
local Stack = require("src.ui.game3.stack")
T.check(Ph ~= nil and Cd ~= nil and Tm ~= nil, "the Phone, Condition and the full-screen host are made")
local kept = {}
Settings.cache = { read = function() return nil end, write = function(_, k, v) kept[k] = v end }
-- (the save, in memory)
local saveData = {}
Ph.store = { get = function(_, k) return saveData[k] end, set = function(_, k, v) saveData[k] = v end }

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
local ItemsData, Party, PokeG = require("src.core.game3.items_data"), require("src.core.game3.party"),
  require("src.core.game3.pokemon")
local s = { name = "WOS", playerName = "WOS", bag = Bag.new(), storage = Storage.new(), party = {}, money = 3000,
            flags = {}, vars = {}, gender = 0 }
ItemsData.ensureModel(s)
s.trainerId, s.secretId = 4321, 8765
s.dex = { seen = {}, owned = {}, caught = {} }
s.meta = { playthroughId = "nav-run" }
require("src.core.game3.runtime").getSession = function() return s end
local function sp(nat) return PokeG.speciesFromNational(nat) end
Party.giveMon(s, sp(25), 20)
Party.giveMon(s, sp(133), 22)

local function ids(list)
  local out = {}
  for _, app in ipairs(list) do out[#out + 1] = app.id end
  return " " .. table.concat(out, " ") .. " "
end
local ctxW = { session = s, mode = "pad", family = RSE and "rse" or "frlg", rows = {} }
function ctxW.row() return nil end

if not RSE then
  T.eq(Ph.family(), nil, "FireRed / LeafGreen: no PokéNav")
  T.check(not ids(Apps.list(ctxW)):find(" phone ") and not ids(Apps.list(ctxW)):find(" condition "),
    "no Phone, no Condition")
  T.finish("woob_os pokenav (" .. GAME .. ")")
  run.release()
  return
end

local C = require("src.core.game3.constants").of(require("src.core.game3.profile").forSession(s).id)
local function setFlag(name, on)
  local id = C:flag(name)
  if id then s.flags[id] = on ~= false or nil end
  return id
end

-- ------- the apps show once the game gives them

T.eq(Ph.family(), EMERALD and "emerald" or "rs", "the game's PokéNav")
T.check(not ids(Apps.list(ctxW)):find(" phone ") and not ids(Apps.list(ctxW)):find(" condition "),
  "no PokéNav yet: no Phone, no Condition")
setFlag("FLAG_SYS_POKENAV_GET")
if EMERALD then setFlag("FLAG_ADDED_MATCH_CALL_TO_POKENAV") end
T.check(ids(Apps.list(ctxW)):find(" phone ") and ids(Apps.list(ctxW)):find(" condition "),
  "the PokéNav (and its Match Call): the Phone and Condition")
T.check(not ids(Apps.list(ctxW)):find(" pokenav "), "no PokéNav icon: WoobOS's own apps instead")
T.check(ids(Apps.list(ctxW)):find(" ribbons ") and ids(Apps.list(ctxW)):find(" map "), "Ribbons and the Map among them")

-- ------- the Phone

if EMERALD then
  local before = #Ph.contacts(s)
  setFlag("FLAG_ENABLE_ROXANNE_MATCH_CALL")
  setFlag("FLAG_ENABLE_MOM_MATCH_CALL")
  local list = Ph.contacts(s)
  T.check(#list >= before + 2, "a contact's flag adds it (" .. before .. " -> " .. #list .. ")")
  local rox
  for _, c in ipairs(list) do if c.name:upper():find("ROXANNE") then rox = c end end
  T.check(rox and rox.desc ~= "" and rox.pic >= 0 and rox.canCall, "Roxanne: her class, her picture, a call")
  -- (Mom, the Professor, Scott and Mr. Stone: the game has no picture for them, so ours)
  setFlag("FLAG_ENABLE_PROF_BIRCH_MATCH_CALL")
  setFlag("FLAG_ENABLE_SCOTT_MATCH_CALL")
  local own, none = {}, {}
  for _, c in ipairs(Ph.contacts(s)) do
    own[c.pic] = c.name
    if c.pic == -1 then none[#none + 1] = c.name end
  end
  T.check(own.mom and own.birch and own.scott and own.stone and #none == 0,
    "Mom, Prof. Birch, Scott and Mr. Stone get pictures of their own (none left without: "
    .. table.concat(none, ", ") .. ")")
  T.check(Ph.picture(-1) == nil and Ph.picture("nobody") == nil, "no picture for nobody")
  if rox then
    local text, ok = Ph.call(s, rox)
    T.check(ok and type(text) == "string" and #text > 4, "a call: the game's words (" .. tostring(text):sub(1, 40) .. ")")
    T.check(Ph.recents(s)[1] and Ph.recents(s)[1].key == rox.key and Ph.recents(s)[1].text == text, "logged in Recents")
    T.check(Ph.toggleFav(s, rox.key) and Ph.isFav(s, rox.key), "★: a favourite")
    T.check(saveData.phone and saveData.phone.fav[rox.key] and #saveData.phone.recents == 1, "both kept in the save")
    -- (an older save: its own log)
    local mine = saveData.phone
    saveData.phone = nil
    T.check(#Ph.recents(s) == 0 and not Ph.isFav(s, rox.key), "another save: its own (none)")
    saveData.phone = mine
  end
  -- (the field's calls: logged, and a notification)
  T.check(rawget(require("src.core.game3.rse.match_call"), "__woobOs") ~= nil, "the field's calls are caught")
  Nt.reset()
  X._test.onCall(s, rox and rox.entry and require("src.core.game3.rse.rematch").trainerIds(
    require("src.core.game3.rse.match_call").entryRematchIdx(rox.entry))[1] or 265, { key = "gText_CallCantBeMadeHere",
    ctx = {} })
  T.check(Ph.recents(s)[1].incoming and Nt.list()[1] and Nt.list()[1].kind == "call" and Nt.list()[1].app == "phone",
    "a field call: in Recents, and a notification that opens the Phone")
else
  T.check(true, "Ruby / Sapphire: Trainer's Eyes' contacts (no calls)")
  local text, ok = Ph.call(s, { canCall = false })
  T.check(not ok, "no calls on Ruby / Sapphire")
end

-- ------- Condition

local m1, m2 = s.party[1], s.party[2]
m1.contest = { cool = 50, beauty = 10, cute = 200, smart = 0, tough = 30, sheen = 40 }
m2.contest = { cool = 120, beauty = 90, cute = 5, smart = 60, tough = 0, sheen = 0 }
local rows = Cd.party(s)
T.check(#rows == 2 and rows[1].conds[1] == 50 and rows[1].conds[3] == 200 and rows[1].sheen == 40,
  "the party's conditions, as stored")
local boxed = select(3, Party.giveMon({ party = {} }, sp(4), 10))
if boxed then
  boxed.contest = { cool = 250, beauty = 0, cute = 0, smart = 0, tough = 0, sheen = 0 }
  require("src.core.game3.storage").ensure(s).boxes[1].mons[3] = boxed
end
local found = Cd.search(s, 1)
T.check(found[1] and found[1].mon == boxed and found[2].mon == m2 and found[3].mon == m1,
  "the search: every Pokémon, best Cool first, the boxes' too")
-- (a Pokéblock: as the game feeds it, used up; none at full sheen)
local Pb = require("src.core.game3.rse.pokeblock")
Pb.clearAll(s)
local block = { color = 1, spicy = 20, dry = 0, sweet = 10, bitter = 0, sour = 0, feel = 12 }
Pb.add(s, block)
local twin = { contest = {}, personality = m1.personality }
for k, v in pairs(m1.contest) do twin.contest[k] = v end
local okW, want = pcall(Pb.feed, Pb.new(block), twin)
local ok, res = Cd.feed(s, 0, m1)
T.check(okW and ok and m1.contest.cool == twin.contest.cool and m1.contest.sheen == twin.contest.sheen,
  "fed: the game's own gains (Cool " .. tostring(m1.contest.cool) .. ", sheen " .. tostring(m1.contest.sheen) .. ")")
T.eq(#Cd.blocks(s), 0, "the block is used up")
Pb.add(s, block)
m2.contest.sheen = 255
local ok2, why = Cd.feed(s, 0, m2)
T.check(not ok2 and why == "full" and #Cd.blocks(s) == 1, "full sheen: it won't eat any more (the block kept)")

-- ------- Ribbons

local Rb, RC = X._test.ribbons, require("src.core.game3.rse.ribbons")
T.eq(#Rb.list(s), 0, "nobody has a Ribbon: an empty list")
RC.set(m1, "cool", 2)
RC.set(m1, "champion", 1)
RC.set(m2, "marine", 1)
if boxed then RC.set(boxed, "tough", 4) end
do
  local list = Rb.list(s)
  T.check(list[1] and list[1].mon == boxed and list[1].count == 4 and list[1].box == 1, "most Ribbons first, the boxes' too")
  T.check(list[2].mon == m1 and list[2].count == 3 and list[2].box == nil, "then the party's")
  T.eq(#list, 3, "only Pokémon with Ribbons")
  local normal, gift = Rb.ids(m1)
  T.check(#normal == 3 and #gift == 0, "its Ribbons (" .. #normal .. ")")
  local words = Rb.desc(s, normal[1])
  T.check(type(words) == "string" and #words > 8, "in the game's own words (" .. tostring(words) .. ")")
  local n2, g2 = Rb.ids(m2)
  T.check(#n2 == 0 and #g2 == 1, "a gift Ribbon apart")
  T.eq(Rb.desc(s, g2[1]), nil, "(no words for it until the save names one)")
  local ranks = Rb.contest(m1)
  T.check(ranks[1] == 2 and ranks[5] == 0, "its contest ranks")
end

-- ------- the windows: draw, no garbage

local VP = { width = 480, height = 320 }
local PAGE = { height = 160, minWidth = 200, maxWidth = 300, portraitWidth = 160, portraitHeight = 260, portraitAspect = 0.9 }
local function drawWin(W, portrait)
  K.frame(G, VP, PAGE, clock)
  W.draw(portrait and { 0, 0, 115, 138 } or { 0, 0, 260, 130 }, clock, portrait)
end
for _, id in ipairs({ "phone", "condition", "ribbons" }) do
  local app = Apps.byId(id)
  local ctx = { session = s, mode = "watch", app = id, rows = {} }
  local okO, W = pcall(app.window, ctx, X._test.env)
  T.check(okO and W and W.draw, id .. ": its window opens (" .. tostring(not okO and W or "") .. ")")
  if okO and W then
    local okD, err = pcall(function()
      for _ = 1, 3 do drawWin(W, false) drawWin(W, true) end
      W.input(input({ "a" }), NONE)
      for _ = 1, 3 do drawWin(W, false) drawWin(W, true) end
    end)
    T.check(okD, id .. ": draws wide and on the watch (" .. tostring(err) .. ")")
    W.input(input({ "b" }), NONE)
    local kb = garbageOf(120, function() drawWin(W, false) end)
    T.check(kb < 0.5, string.format("%s: next to no garbage (%.3f KB/frame)", id, kb))
  end
end

-- a call: it rings, then the words as chat bubbles, each typed out after a "..." bubble
if EMERALD then
  local tnow = 1000
  local envT = setmetatable({ now = function() return tnow end }, { __index = X._test.env })
  local W = Apps.byId("phone").window({ session = s, mode = "pad", app = "phone", rows = {} }, envT)
  local st = W.state
  for i, r in ipairs(st.rows) do
    if r.contact and r.contact.name:upper():find("ROXANNE") then st.cursor = i end
  end
  drawWin(W, false)
  W.input(input({ "a" }), NONE)
  W.input(input({ "a" }), NONE)
  T.eq(st.view, "call", "A on Call: the call")
  drawWin(W, false)
  W.input(input({ "a" }), NONE)
  T.check(st.view == "call" and st.bubbles == nil, "while it rings: no words yet, A waits")
  W.input(input({ "b" }), NONE)
  T.check(st.view == "card" and st.call == nil, "B: hung up, the card again")
  -- (a long call, from Recents: a field call logged with the game's words, two pages of them)
  Ph.incoming(s, "WALLY'S DAD", "WALLY'S DAD: Hi there! It's me. I've been training my POKéMON every day at the GYM, "
    .. "and I think we're ready for a real battle now.\n\nCome and see us in PETALBURG whenever you like!", -1)
  Nt.reset()
  W.tap(2002)
  st.cursor = 1
  W.input(input({ "a" }), NONE)
  T.check(st.view == "call", "a recent call: its words again")
  drawWin(W, false)
  local cl = st.call
  T.check(st.bubbles and #st.bubbles >= 2 and cl.idx == 1, "the words in bubbles, a page or more each (" ..
    tostring(st.bubbles and #st.bubbles) .. ")")
  T.check(st.bubbles and st.bubbles[1].lines[1]:sub(1, 3) == "Hi ", "without the caller's name before the words (" ..
    tostring(st.bubbles and st.bubbles[1].lines[1]) .. ")")
  local whole = true
  for _, b in ipairs(st.bubbles or {}) do
    for j, line in ipairs(b.lines) do
      if b.pre[j][b.count[j]] ~= line then whole = false end
    end
  end
  T.check(whole, "each line typed out ends as the line itself (letters, not bytes)")
  T.eq(W.hints()[1][2], envT.T("hint.skip"), "first a \"...\" bubble: A skips")
  tnow = tnow + 0.5
  drawWin(W, false)
  -- (once through first: LuaJIT's traces for each new stretch of typing land on the heap)
  local from = tnow
  local function typeOn()
    tnow = tnow + 0.002
    drawWin(W, false)
  end
  garbageOf(60, typeOn)
  tnow = from
  local kb = garbageOf(60, typeOn)
  T.check(kb < 0.5, string.format("typing out: next to no garbage (%.3f KB/frame)", kb))
  T.check(not cl.full, "the words being typed")
  W.input(input({ "a" }), NONE)
  T.check(cl.full and cl.idx == 1 and st.view == "call", "A: the rest of the bubble at once")
  T.eq(W.hints()[1][2], envT.T("phone.hint.next"), "then A is Next")
  local n = #st.bubbles
  do
    W.input(input({ "a" }), NONE)
    T.check(cl.idx == 2 and not cl.full, "A again: the next bubble")
    drawWin(W, false)
    T.check(cl.lift > 0, "the older ones lifted, gliding up")
  end
  for _ = 1, n * 2 + 2 do
    if st.view ~= "call" then break end
    W.input(input({ "a" }), NONE)
    tnow = tnow + 0.05
    drawWin(W, false)
  end
  T.check(st.view ~= "call" and st.call == nil, "after the last bubble, A ends the call")
  T.check(pcall(drawWin, W, true), "the card again, upright")
end

do
  local W = Apps.byId("ribbons").window({ session = s, mode = "pad", app = "ribbons", rows = {} }, X._test.env)
  local st = W.state
  local NAVR = setmetatable({ right = true }, { __index = NONE })
  local NAVD = setmetatable({ down = true }, { __index = NONE })
  drawWin(W, false)
  W.input(input({ "a" }), NONE)
  T.eq(st.focus, "grid", "A: its Ribbons")
  W.input(input({}), NAVR)
  T.eq(st.pick, 2, "Right: the next Ribbon")
  W.input(input({ "b" }), NONE)
  T.eq(st.focus, "list", "B: back to the list")
  W.input(input({}), NAVD)
  T.eq(st.cursor, 2, "Down: the next Pokémon")
  T.eq(st.pick, 1, "from its first Ribbon")
  T.check(W.input(input({ "b" }), NONE) == false, "B on the list: closed")
  local Empty = Apps.byId("ribbons").window({ session = { party = {}, storage = Storage.new() }, mode = "pad", app = "ribbons", rows = {} }, X._test.env)
  T.check(pcall(drawWin, Empty, false), "nobody with a Ribbon: it says so")
end

-- ------- the PokéNav: ours instead of its Match Call / Trainer's Eyes and Condition

local function stubShell()
  local sh = { session = s, mode = 0, monList = { items = {}, listCount = 0 } }
  function sh:fade() end
  function sh:fadeActive() return false end
  function sh:slideHeader() return nil end
  function sh:busy() return false end
  function sh:hideLeftHeaders() self.hidden = true end
  function sh:setKeyRepeat() end
  return sh
end
local function press(k)
  Tm.input(input({ k }, { k }))
  Tm.input(input({}, {}))
end
if EMERALD then
  local MCs, Cs = require("src.ui.game3.rse.pokenav.match_call"), require("src.ui.game3.rse.pokenav.condition")
  local sh = stubShell()
  local scr = MCs.new(sh, "match_call")
  T.check(scr.app == "phone", "Match Call: our Phone")
  scr:open()
  T.check(Tm.isOpen() and Stack.has(Sh.MAP_ID) and Tm.state().ctx.app == "phone", "opened full screen over the PokéNav")
  Tm.input(input({}, {}))
  for _ = 1, 2 do Tm.draw(G, VP) end
  press("b")
  T.check(not Tm.isOpen() and not Stack.has(Sh.MAP_ID), "B: closed")
  local r = scr:callback({})
  T.eq(r, scr.EXIT_TASK or 99, "then the game's way out")
  local co = coroutine.create(function() scr:loopTask(r) end)
  for _ = 1, 10 do if coroutine.status(co) ~= "dead" then coroutine.resume(co) end end
  T.eq(scr:callback({}), "main_menu_cursor_on_match_call", "back to the PokéNav's menu, on Match Call")
  T.check(sh.hidden, "its left headers put away, as the game's screen does")
  -- (the tutorial's forced call: the game's)
  local tut = stubShell()
  tut.mode = 1
  T.check(MCs.new(tut, "match_call").app == nil, "the tutorial's forced call: the game's Match Call")
  -- (the rest of its screens: ours, each back to the game's menu)
  do
    local MapS, RibS, SrchS = require("src.ui.game3.rse.pokenav.region_map"), require("src.ui.game3.rse.pokenav.ribbons"),
      require("src.ui.game3.rse.pokenav.condition_search")
    local a = MapS.new(stubShell())
    T.check(a.app == "map" and a.back == "main_menu_cursor_on_map", "its Hoenn Map: ours")
    local b = RibS.new(stubShell(), "ribbons_mon_list")
    T.check(b.app == "ribbons" and b.back == "main_menu_cursor_on_ribbons", "its Ribbons: ours")
    local sh2 = stubShell()
    sh2.conditionSearchId = 2
    local c = SrchS.new(sh2, "condition_search_results")
    T.check(c.app == "condition" and c.back == "condition_search_menu" and c.state.mode == "search" and c.state.cat == 3,
      "the condition search: ours, on that condition")
  end
  -- (Condition: the party's graph ours, the search's the game's)
  local cs = Cs.new(stubShell(), "condition_graph_party")
  T.check(cs.app == "condition", "Condition (the party): ours")
  local okS, gs = pcall(Cs.new, stubShell(), "condition_graph_search")
  T.check(okS and gs and gs.app == nil, "the search's graph: the game's")
  cs:open()
  T.check(Tm.isOpen() and Tm.state().ctx.app == "condition", "Condition full screen")
  Tm.input(input({}, {}))
  press("b")
  local rc = cs:callback({})
  local co2 = coroutine.create(function() cs:loopTask(rc) end)
  for _ = 1, 10 do if coroutine.status(co2) ~= "dead" then coroutine.resume(co2) end end
  T.eq(cs:callback({}), "condition_menu", "back to the Condition menu")
  -- (Settings off: the game's)
  Settings.set("pokenavApps", false)
  T.check(MCs.new(stubShell(), "match_call").app == nil, "Settings off: the game's Match Call")
  Settings.set("pokenavApps", true)
else
  do
    local RsM, RsS = require("src.ui.game3.rs.pokenav.map"), require("src.ui.game3.rs.pokenav.condition_search")
    T.eq(RsM.new(s, nil, {}).app, "map", "its Hoenn Map: ours")
    T.eq(RsS.new(s, 0, nil, nil, true).app, "ribbons", "its Ribbons: ours")
    local srch = RsS.new(s, 1)
    T.check(srch.app == "condition" and srch.state.cat == 2, "the condition search: ours, on that condition")
  end
  local RsC = require("src.ui.game3.rs.pokenav.condition")
  local f = RsC.new(s, nil, 1, nil)
  T.check(f.app == "condition", "Condition (the party): ours")
  T.eq(f:frame(input()), nil, "opened")
  T.check(Tm.isOpen() and Tm.state().ctx.app == "condition", "full screen over the PokéNav")
  Tm.input(input({}, {}))
  press("b")
  T.eq(f:frame(input()), "exit", "B: back to the PokéNav")
  T.check(rawget(require("src.ui.game3.rs.pokenav.eyes"), "__woobOs") ~= nil, "Trainer's Eyes is wrapped")
  Settings.set("pokenavApps", false)
  local okG, g = pcall(RsC.new, s, nil, 1, nil)
  T.check(not (okG and g and g.app), "Settings off: the game's")
  Settings.set("pokenavApps", true)
end

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
  local PREFIX = { phone = 1, cond = 1, app = 1, hint = 1, settings = 1, pokenav = 1, notify = 1, ribbons = 1 }
  for _, file in ipairs({ "src/phone.lua", "src/condition.lua", "src/apps/phone.lua", "src/apps/condition.lua",
                          "src/ribbons.lua", "src/apps/ribbons.lua",
                          "src/pokenav.lua", "src/townmap.lua", "src/notify.lua", "src/apps/settings.lua" }) do
    for key in (readFile(file) or ""):gmatch('"([%a][%w_]*%.[%w_%.]+)"') do
      if PREFIX[key:match("^(%a+)")] and not key:match("%.$") and not key:match("%.lua$") and not en[key]
          and not key:match("^cond%.why%.$") then
        missing[#missing + 1] = key
      end
    end
  end
  for _, code in ipairs({ "full", "none" }) do
    if not en["cond.why." .. code] then missing[#missing + 1] = "cond.why." .. code end
  end
  T.eq(table.concat(missing, " "), "", "every word the PokéNav's apps name is in English")
  for _, l in ipairs({ "fr", "de", "es", "it", "ja", "pt-br" }) do
    local t = assert(load(readFile("lang/" .. l .. ".lua"), l, "t", {}))().strings
    local gaps = {}
    for k, v in pairs(en) do
      if k:match("^phone%.") or k:match("^cond%.") or k:match("^pokenav%.") or k:match("^ribbons%.") or k == "app.phone"
          or k == "app.condition" or k == "app.ribbons"
          or k:match("^settings%.pokenav") or k == "notify.call" then
        if not t[k] then gaps[#gaps + 1] = k
        else
          for _, pat in ipairs({ "%%s", "%%d" }) do
            if select(2, v:gsub(pat, "")) ~= select(2, t[k]:gsub(pat, "")) then gaps[#gaps + 1] = k .. " (" .. pat .. ")" end
          end
        end
      end
    end
    T.eq(table.concat(gaps, " "), "", l .. ": every word, the same %s / %d")
  end
end

T.finish("woob_os pokenav (" .. GAME .. ")")
run.release()
