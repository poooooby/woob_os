-- Standalone: luajit mods/woob_os/tests/pokedex_test.lua [game] (from the gen1recomp root; needs that
-- cart imported, Emerald by default).
--
-- The Pokédex (src/dex.lua, src/apps/pokedex.lua, its view, the takeover in src/shell.lua): the
-- regional dex (Kanto's 151, Hoenn's 202) and the National one only once it's unlocked; seen and
-- caught by the game's own flags; a page's facts read from the cart (Poliwag's category, types,
-- height and weight; Bulbasaur's stats, ability, moves; the gender ratios; where Magikarp bites; an
-- evolution's how); the game's rules (unseen nothing, seen the card and Where, caught everything);
-- the window wide and upright, scrolled, its tabs, next to no garbage; the START menu's Pokédex
-- opening ours full screen, START the game's own, the setting off the game's own; the app only once
-- the game has given the Pokédex.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GAME = arg[1] or "emerald"
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
local Sh, Tm, Apps = X._test.shell, X._test.townmap, X._test.apps
local Settings, K, env = X._test.settings, X._test.kit, X._test.env
local Stack = require("src.ui.game3.stack")
local Dx = env and env.dex
T.check(Dx ~= nil and Tm ~= nil, "the Pokédex's model and the full-screen host are made")
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
local ItemsData, P = require("src.core.game3.items_data"), require("src.core.game3.pokemon")
local s = { name = "WOS", playerName = "WOS", bag = Bag.new(), storage = Storage.new(), party = {}, money = 3000,
            flags = {}, vars = {}, gender = 0 }
ItemsData.ensureModel(s)
s.dex = { seen = {}, owned = {}, caught = {} }
require("src.core.game3.runtime").getSession = function() return s end
local function sp(nat) return P.speciesFromNational(nat) end
-- (seen: Bulbasaur, Poliwag, Nidoran♀, Magnemite, Magikarp, Treecko; caught: Bulbasaur, Poliwag, Magikarp)
for _, n in ipairs({ 1, 60, 29, 81, 129, 252 }) do s.dex.seen[sp(n)] = true end
for _, n in ipairs({ 1, 60, 129 }) do s.dex.caught[sp(n)] = true; s.dex.owned[sp(n)] = true end

-- ------- the list

local book = Dx.open(s)
local rmode = RSE and "hoenn" or "kanto"
T.eq(book.modes[1], rmode, "the regional dex first")
T.eq(#book.lists[rmode], RSE and 202 or 151, RSE and "Hoenn's 202" or "Kanto's 151")
T.check(book.lists.national == nil, "the National dex only once the game unlocks it")
local function entryOf(list, nat)
  for _, e in ipairs(list or {}) do if e.nat == nat then return e end end
end
local reg = book.lists[rmode]
if RSE then
  T.check(reg[1].nat == 252 and reg[1].numText == "001" and reg[1].seen and not reg[1].caught,
    "Hoenn's No. 001 is Treecko, seen, not caught")
else
  T.check(reg[1].nat == 1 and reg[1].name == "Bulbasaur" and reg[1].seen and reg[1].caught, "No. 001 Bulbasaur, caught")
  T.check(not reg[4].seen, "Charmander unseen")
end
local counts = book.counts[rmode]
T.check(counts and counts.seen >= 3 and counts.caught >= 1, ("its counts (%d seen, %d caught)"):format(counts.seen, counts.caught))

-- ------- a page: the cart's own facts

local function page(nat) return Dx.page({ sp = sp(nat), nat = nat }) end
local poli = page(60)
T.eq(poli.category, "Tadpole Pokémon", "Poliwag: the Tadpole Pokémon")
T.check(#poli.types == 1 and poli.types[1].id == 11, "Water, one type")
T.check(poli.heightText:find("0.6 m", 1, true) and poli.weightText:find("12.4 kg", 1, true),
  "0.6 m, 12.4 kg (" .. poli.heightText .. ", " .. poli.weightText .. ")")
T.check(#poli.description > 30 and not poli.description:find("POKéMON", 1, true),
  "its description, in a sentence's case")
local bulba = page(1)
T.eq(bulba.total, 318, "Bulbasaur's base stats: 318 in all")
T.check(bulba.stats[1] == 45 and bulba.stats[4] == 65, "HP 45, Sp. Atk 65 (the radar's order: HP Atk Def SpA SpD Spe)")
T.check(bulba.abilities[1] and bulba.abilities[1].name == "Overgrow" and #bulba.abilities[1].desc > 5, "Overgrow, with its words")
T.check(bulba.moves.level[1] and bulba.moves.level[1].name == "Tackle", "its first move: Tackle")
local toxic = false
for _, r in ipairs(bulba.moves.tm) do if r.tag == "TM06" and r.name == "Toxic" then toxic = true end end
T.check(toxic, "TM06 Toxic")
T.check(#bulba.moves.egg > 0, "egg moves")
T.check(bulba.evolutions[1] and bulba.evolutions[1].toName == "Ivysaur" and bulba.evolutions[1].how:find("16"),
  "evolves into Ivysaur at 16")
T.check(bulba.female and math.abs(bulba.female - 0.125) < 0.001 and bulba.maleText == "87.5%", "87.5% male")
local nido = page(29)
T.check(nido.female == 1, "Nidoran♀: all female")
local mag = page(81)
T.check(mag.female == nil, "Magnemite: genderless")
local karp = page(129)
local rod = false
for _, r in ipairs(karp.where) do if r.method == "old" then rod = true end end
T.check(#karp.where > 0 and rod, "Magikarp: where it bites an Old Rod")
local evInfo
for _, r in ipairs(bulba.info) do if r.value:find("1 ", 1, true) and r.label == env.T("dex.info.ev") then evInfo = r.value end end
T.check(evInfo ~= nil, "its EV yield in Info (" .. tostring(evInfo) .. ")")

-- ------- the window

local VP = { width = 480, height = 320 }
local PAGE = { height = 160, minWidth = 200, maxWidth = 300, portraitWidth = 160, portraitHeight = 260, portraitAspect = 0.9 }
local function drawWin(W, portrait)
  K.frame(G, VP, PAGE, clock)
  W.draw(portrait and { 0, 0, 115, 138 } or { 0, 0, 260, 130 }, clock, portrait)
end
local app = Apps.byId("pokedex")
T.check(app ~= nil and app.window ~= nil, "the Pokédex app is made")
T.check(not app.available({ session = s, mode = "pad" }), "not on the PC or WoobPad before the game gives the Pokédex")
local ctx = { session = s, mode = "pad", app = "pokedex", rows = {} }
local okO, W = pcall(app.window, ctx, env)
T.check(okO and W and W.draw, "its window opens (" .. tostring(not okO and W or "") .. ")")
if okO and W then
  local st = W.state
  local okD, err = pcall(function()
    for _ = 1, 3 do drawWin(W, false) drawWin(W, true) end
  end)
  T.check(okD, "draws wide and upright (" .. tostring(err) .. ")")
  drawWin(W, false)
  T.check(not st.narrow and st.cols >= 3, "wide: the grid beside the page (" .. tostring(st.cols) .. " across)")
  -- (the D-pad through the grid; a caught one's page and its tabs)
  local target = RSE and 1 or 1
  W.input(input({}), { right = true })
  T.eq(st.sel, 2, "Right: the next one")
  W.input(input({}), { left = true })
  T.eq(st.sel, 1, "Left: back")
  W.input(input({}), { down = true })
  T.eq(st.sel, 1 + st.cols, "Down: a row on")
  W.input(input({}), { up = true })
  -- (a caught Pokémon: Bulbasaur on FireRed / LeafGreen; on Hoenn's list Magikarp)
  local caughtAt
  for i, e in ipairs(st.list) do if e.caught then caughtAt = i break end end
  W.tap(W.A.CELL + caughtAt)
  T.check(st.entry and st.entry.caught and st.page and st.page.moves, "tapped: a caught one's page")
  W.input(input({ "a" }), NONE)
  T.eq(st.focus, "detail", "A: the page")
  local okT = pcall(function()
    for tab = 1, 3 do
      W.tap(W.A.TAB + tab)
      for k = 1, 4 do
        W.tap(W.A.KIND + k)
        drawWin(W, false)
      end
    end
  end)
  T.check(okT and st.tab == 3, "every tab and every list of moves draws")
  W.scroll(-40, 200)
  drawWin(W, false)
  T.check(st.detailTop > 0, "the page scrolls under the wheel")
  W.input(input({ "b" }), NONE)
  T.eq(st.focus, "grid", "B: back to the grid")
  -- (unseen: nothing but ???; seen only: no stats or moves)
  local unseenAt, seenAt
  for i, e in ipairs(st.list) do
    if not e.seen and not unseenAt then unseenAt = i end
    if e.seen and not e.caught and not seenAt then seenAt = i end
  end
  W.tap(W.A.CELL + unseenAt)
  T.check(st.page == nil, "unseen: no page")
  drawWin(W, false)
  if seenAt then
    W.tap(W.A.CELL + seenAt)
    drawWin(W, false)
    T.check(st.page ~= nil and not st.entry.caught, "seen only: the card and Where")
  end
  -- (upright: the grid, then the page in its place, B back)
  drawWin(W, true)
  T.check(st.narrow, "upright: narrow")
  W.tap(W.A.CELL + caughtAt)
  drawWin(W, true)
  T.check(st.detail, "a tap: the page in the grid's place")
  W.input(input({ "b" }), NONE)
  drawWin(W, true)
  T.check(not st.detail, "B: the grid again")
  -- (scrolled by hand between rows: still drawn)
  W.scroll(-30, 10)
  drawWin(W, false)
  T.check(st.gridTop > 0, "the grid scrolls by hand")
  local kb = garbageOf(120, function() drawWin(W, false) end)
  T.check(kb < 0.5, string.format("next to no garbage (%.3f KB/frame)", kb))
  W.tap(W.A.CELL + caughtAt)
  W.input(input({ "a" }), NONE)
  local kb2 = garbageOf(120, function() drawWin(W, false) end)
  T.check(kb2 < 0.5, string.format("a page: next to no garbage (%.3f KB/frame)", kb2))
  -- (WoobleDex's forms: a Forms tab, each form's name, a Poké Ball under those caught; a stand-in whose
  -- forms are other species the save has: one caught, one unseen)
  local caughtSp, unseenSp
  for _, e in ipairs(st.list) do
    if e.caught and e ~= st.list[caughtAt] and not caughtSp then caughtSp = e.sp end
    if not e.seen and not unseenSp then unseenSp = e.sp end
  end
  local baseNat = st.list[caughtAt].nat
  local prevWooble = Dx.wooble
  Dx.wooble = function()
    return {
      formsOf = function(nat)
        if nat ~= baseNat then return {} end
        return { { id = "A_FORM", slot = caughtSp or unseenSp, form = "ALOLA" },
                 { id = "B_FORM", slot = unseenSp, form = "GALAR" } }
      end,
      formLabel = function(slot) return slot == unseenSp and "GALARIAN" or nil end,
    }
  end
  W.input(input({ "b" }), NONE)
  W.tap(W.A.CELL + (caughtAt == 1 and 2 or 1))
  W.tap(W.A.CELL + caughtAt)
  T.check(#st.forms == 3 and st.forms[1].base and st.forms[1].caught, "its forms, the base one first")
  T.check(st.tabs[4] == "forms", "a Forms tab after Info")
  T.check(st.forms[3].name == "Galarian" and not st.forms[3].seen and st.forms[2].name == (caughtSp and "Alola" or "Galarian"),
          "each form's name (WoobleDex's, else its own)")
  T.check(caughtSp == nil or st.forms[2].caught, "a caught form: its Poké Ball")
  W.input(input({ "a" }), NONE)
  W.tap(W.A.TAB + 4)
  local okF, errF = pcall(drawWin, W, false)
  T.check(okF and st.tabId == "forms", "the Forms tab draws (" .. tostring(errF) .. ")")
  pcall(drawWin, W, true)
  local kb3 = garbageOf(120, function() drawWin(W, false) end)
  T.check(kb3 < 0.5, string.format("the Forms tab: next to no garbage (%.3f KB/frame)", kb3))
  W.input(input({ "r" }), NONE)
  T.eq(st.tabId, "moves", "R from Forms: round to Moves")
  -- (a Pokémon without forms: three tabs)
  W.input(input({ "b" }), NONE)
  W.tap(W.A.CELL + (caughtAt == 1 and 2 or 1))
  T.check(#st.forms == 0 and st.tabs[4] == nil, "no forms: no Forms tab")
  Dx.wooble = prevWooble
end

-- ------- the START menu's Pokédex: ours, START the game's own, the setting off the game's

local Screens = require("src.ui.game3.screens")
local Dm = Screens.get("pokedex", s)
local function press(k)
  Tm.input(input({ k }, { k }))
  Tm.input(input({}, {}))
end
Dm.show(s.dex, { session = s })
T.check(Tm.isOpen() and Stack.has(Sh.MAP_ID) and Tm.state().ctx.app == "pokedex", "START's Pokédex: ours, full screen")
Tm.input(input({}, {}))
for _ = 1, 2 do pcall(Tm.draw, G, VP) end
press("b")
T.check(not Tm.isOpen() and not Stack.has(Sh.MAP_ID), "B: closed")
-- (START: the game's own Pokédex instead)
local classicOpened = false
local w = rawget(Dm, "__woobOs")
local realOrig = w and w.orig
if w then w.orig = function() classicOpened = true end end
Dm.show(s.dex, { session = s })
Tm.input(input({}, {}))
press("start")
T.check(not Tm.isOpen() and classicOpened, "START: the game's own Pokédex")
-- (the setting off: the game's own, straight away)
classicOpened = false
Settings.set("pokedexApp", false)
Dm.show(s.dex, { session = s })
T.check(not Tm.isOpen() and classicOpened, "the setting off: the game's own")
Settings.set("pokedexApp", true)
-- (the mod's option off: the game's own, no app, no row in Settings)
local realOption = env.dexOption
env.dexOption = function() return false end
classicOpened = false
Dm.show(s.dex, { session = s })
T.check(not Tm.isOpen() and classicOpened, "the mod's option off: the game's own")
T.check(not app.available({ session = s, mode = "pad" }), "the mod's option off: no app")
local SetWin = Apps.byId("settings")
local okS, SW = pcall(SetWin.window, { session = s, mode = "pad", app = "settings", rows = {} }, env)
local hasRow = false
if okS and SW and SW.SECTIONS then
  for _, sec in ipairs(SW.SECTIONS) do
    for _, t in ipairs(sec.toggles or {}) do if t.key == "pokedexApp" then hasRow = true end end
  end
end
T.check(okS and not hasRow, "the mod's option off: no Pokédex row in Settings")
env.dexOption = realOption
local okS2, SW2 = pcall(SetWin.window, { session = s, mode = "pad", app = "settings", rows = {} }, env)
local hasRow2 = false
if okS2 and SW2 and SW2.SECTIONS then
  for _, sec in ipairs(SW2.SECTIONS) do
    for _, t in ipairs(sec.toggles or {}) do if t.key == "pokedexApp" then hasRow2 = true end end
  end
end
T.check(hasRow2, "the option on: the Pokédex's row in Settings again")
if w then w.orig = realOrig end

T.finish("woob_os pokedex (" .. GAME .. ")")
