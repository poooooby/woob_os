-- Standalone: luajit mods/woob_os/tests/desktop_test.lua [game] (from the gen1recomp root; needs
-- that cart imported, FireRed by default).
--
-- The desktop in place of the game's PC menu (src/shell.lua, src/desktop.lua, src/apps.lua): the
-- Pokémon Center PC's menu and the bedroom PC open it, every other way in opens the game's own
-- menu; each app hands the game's script the row the game's own list has for it; logging off
-- (B, then Log Off) hands back 127; the next PC menu after an app skips the boot; the bedroom's
-- Items opens the game's player's PC and comes back; buttons, taps and the wheel drive it; it
-- lays out inside every window shape; and its draw makes next to no garbage.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GAME = arg[1] or "firered"

-- a clock the test moves, and a LÖVE graphics stand-in (no meshes: the flat fallback)
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
local D, Sh, Apps = X._test.desktop, X._test.shell, X._test.apps
local PcMenu = require("src.ui.game3.pc_menu")
local Stack = require("src.ui.game3.stack")
T.check(rawget(PcMenu, "__woobOs") ~= nil, "the PC menu is wrapped")

local VP = { width = 480, height = 320 }
local function draw(n, step)
  for _ = 1, n or 1 do
    clock = clock + (step or 1 / 60)
    D.draw(G, VP)
  end
end
-- KB a frame the draw makes over n frames: measured twice, the lower kept (a trace LuaJIT compiles
-- in the middle of one lands on the heap once; garbage the draw makes shows in both)
local function garbageOf(n, setup)
  local best = math.huge
  for _ = 1, 2 do
    if setup then setup() end
    collectgarbage("collect")
    collectgarbage("stop")
    local kb = collectgarbage("count")
    draw(n)
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
  D.input(input({ k }, { k }))
  D.input(input({}, {}))
end
local results = {}
local function openPc(opts)
  opts = opts or {}
  opts.onClose = function(res) results[#results + 1] = res == nil and "nil" or res end
  PcMenu.show(opts)
end
local function last() return results[#results] end
local function ids(list)
  local out = {}
  for _, app in ipairs(list) do out[#out + 1] = app.id end
  return table.concat(out, " ")
end

-- ------- the apps

local rowsAll = { { id = "storage" }, { id = "player" }, { id = "oak" }, { id = "hall" }, { id = "quit" } }
local function ctxWith(mode, rows)
  local ctx = { mode = mode, rows = rows or {} }
  ctx.row = function(id) for i, row in ipairs(ctx.rows) do if row.id == id then return i - 1 end end end
  return ctx
end
T.eq(ids(Apps.list(ctxWith("select", rowsAll))), "storage items map mail gts mart auction slots oak hall settings about logoff",
  "a cleared game's PC: every app")
T.eq(ids(Apps.list(ctxWith("select", { { id = "storage" }, { id = "player" }, { id = "quit" } }))),
  "storage items map mail gts mart auction slots settings about logoff", "early on: no Oak's PC, no Hall of Fame")
T.eq(ids(Apps.list(ctxWith("bedroom"))), "items map mail gts mart auction slots settings about logoff", "the bedroom PC: Items, Map, Mail, GTS, Mart, R-Bay, Slots, Settings")
do
  local c = ctxWith("bedroom")
  c.family = "rse"
  T.eq(ids(Apps.list(c)), "items map mail gts mart auction slots decorate settings about logoff", "Ruby / Sapphire / Emerald's bedroom: Decorate too")
end
T.check(not Apps.register({ id = "storage", open = noop }), "an id can't be taken twice")
T.check(not Apps.register({ id = "x" }), "an app needs open()")

-- ------- the Pokémon Center PC

openPc({ startMode = "select" })
T.check(D.isOpen() and Stack.has("woob_os"), "the PC menu opens the desktop, on the UI stack")
local st = D.state()
T.check(D.booting(), "it boots first")
press("a")
T.check(D.booting(), "the A that turned it on doesn't skip (still held)")
D.input(input({}, {}))
press("b")
T.check(not D.booting(), "a button skips the boot")
draw(40)
local rows = st.ctx.rows
T.check(#rows >= 3, "the game's own rows (" .. #rows .. ")")
T.eq(st.dock[1] and st.dock[1].id, "storage", "Boxes first in the dock")

-- Boxes: zooms up into its own window (no row to the script)
local before0 = #results
st.focus, st.dockCursor = "dock", 1
press("a")
T.check(st.zoom ~= nil, "Boxes zooms up from its icon")
draw(30)
T.check(D.isOpen() and D.window() ~= nil and D.window().title == "Boxes", "into its window, in the desktop")
T.eq(#results, before0, "and hands the script nothing")
press("b")
T.check(D.window() == nil and st.zoom and st.zoom.back and st.zoom.id == "storage", "B: back into its icon")
draw(30)

-- an app handing the script a row (as Oak's PC does): the PC menu again is the desktop, no boot,
-- the app's icon zooming back
st.ctx.app = "storage"
st.ctx.finish(st.ctx.row("storage"))
T.check(not D.isOpen() and not Stack.has("woob_os"), "a row to the script: the desktop closes")
T.eq(last(), st.ctx.row("storage"), "and the script gets the row (" .. tostring(last()) .. ")")
openPc({ startMode = "select" })
st = D.state()
T.check(D.isOpen() and not D.booting(), "the PC menu again: the desktop, without the boot")
T.check(st.zoom and st.zoom.back and st.zoom.id == "storage", "the app zooms back into its icon")
draw(30)
-- Items: our own window, in the desktop (no row to the script)
local before = #results
st.focus, st.dockCursor = "dock", 2
D.input(input({}, {}))
press("a")
draw(30)
T.check(D.isOpen() and D.window() ~= nil and D.window().title == "Items", "Items opens its window in the desktop")
T.eq(#results, before, "and hands the script nothing")
press("b")
T.check(D.window() == nil and D.isOpen(), "B closes it: the desktop")
T.check(st.zoom and st.zoom.back and st.zoom.id == "items", "and it zooms back into its icon")
draw(30)
st.ctx.logoff()

-- log off: B asks, A logs off -> 127
openPc({ startMode = "select" })
st = D.state()
D.skipBoot()
draw(30)
D.input(input({}, {}))
press("b")
T.eq(st.sheet, "logoff", "B asks to log off")
press("b")
T.eq(st.sheet, nil, "B again: not")
press("b")
press("a")
T.check(not D.isOpen(), "A logs off")
T.eq(last(), 127, "the script gets 127")

-- after logging off, the next PC boots again
openPc({ startMode = "select" })
T.check(D.booting(), "the next PC boots")
st = D.state()
D.skipBoot()
draw(40)

-- the D-pad: the grid, the menu bar, the W menu, About
st.focus, st.cursor = "grid", 1
D.input(input({}, {}))
press("up")
T.eq(st.focus, "menubar", "Up from the grid's top row: the menu bar")
press("a")
T.check(st.menuOpen, "A opens the W menu")
press("a")
T.eq(st.sheet, "about", "its first row: About")
press("a")
T.eq(st.sheet, nil, "A closes it")
press("start")
T.check(st.menuOpen, "START opens the W menu")
press("down")
press("a")
T.eq(st.sheet, "notes", "its second row: Notifications")
press("b")
T.eq(st.sheet, nil, "B closes them")
press("start")
press("down")
press("down")
press("a")
T.eq(st.sheet, "logoff", "its third row: Log Off")
press("b")

-- taps: the hit list of the last draw
draw(2)
local function hitOf(kind, arg)
  for _, h in ipairs(st.hit) do
    if h.kind == kind and (arg == nil or h.arg == arg) then return h end
  end
end
local wm = hitOf("wmenu")
T.check(wm ~= nil, "the W can be tapped")
D.tap(wm[1] + 1, wm[2] + 1)
T.check(st.menuOpen, "a tap on the W opens its menu")
draw(1)
local dim = hitOf("dim")
D.tap(dim[1] + 1, dim[2] + 1)
T.check(not st.menuOpen, "a tap beside it closes it")
draw(1)
local pw = hitOf("power")
T.check(pw ~= nil, "the power button can be tapped")
D.tap(pw[1] + 1, pw[2] + 1)
T.eq(st.sheet, "logoff", "the power button asks to log off")
draw(1)
local no = hitOf("no")
D.tap(no[1] + 1, no[2] + 1)
T.eq(st.sheet, nil, "Cancel")
draw(1)
local hall = hitOf("grid")
if hall then
  D.pointer({ id = 1, phase = "pressed", x = hall[1] + 2, y = hall[2] + 2 })
  D.pointer({ id = 1, phase = "released", x = hall[1] + 2, y = hall[2] + 2 })
  local app = st.grid[hall.arg]
  T.check(st.zoom ~= nil or st.sheet == app.id, "a tap on a home-screen icon opens its app (" .. app.id .. ")")
  draw(30)
end
if D.isOpen() then
  st.ctx.logoff()
end

-- ------- the bedroom PC

openPc({ startMode = "player_pc", bedroom = true })
st = D.state()
T.check(D.isOpen() and st.ctx.mode == "bedroom", "the bedroom PC opens the desktop")
local rse = st.ctx.family == "rse"
T.eq(#st.grid + #st.dock, rse and 11 or 10, "with Items, Map, Mail, GTS, Mart, R-Bay, Slots, Settings, About and Log Off" .. (rse and ", Decorate" or ""))
D.skipBoot()
draw(40)
if rse then
  -- Decorate: the game's own menu over the desktop, the desktop back after it
  local Rse = require("src.core.game3.rse.init")
  local was = Rse._systems.decorationMenu
  local opened
  Rse._systems.decorationMenu = { open = function(o) opened = o end }
  for i, app in ipairs(st.grid) do if app.id == "decorate" then st.focus, st.cursor = "grid", i end end
  D.input(input({}, {}))
  press("a")
  draw(30)
  T.check(opened ~= nil and not D.isOpen(), "Decorate opens the game's Decoration menu")
  if opened then opened.onClose() end
  T.check(D.isOpen() and Stack.has("woob_os") and not D.booting(), "and closing it comes back to the desktop")
  Rse._systems.decorationMenu = was
  st = D.state()
  draw(30)
end
st.ctx.logoff()
T.check(not D.isOpen(), "Log Off closes it")

-- ------- every other way in: the game's own menu
openPc({ startMode = "storage" })
T.check(not D.isOpen() and PcMenu.isOpen(), "the storage menu stays the game's")
PcMenu.close()
Sh.enabled = function() return false end
openPc({ startMode = "select" })
T.check(not D.isOpen() and PcMenu.isOpen(), "with the Desktop option off: the game's PC menu")
PcMenu.close()
Sh.enabled = function() return true end

-- ------- the game's lines before its PC menu: skipped (the boot does their job)
do
  local CacheBlob = require("src.import.CacheBlob")
  local rel = "data/generated/gba/scripts/scripts.lua"
  local f = io.open(GAME .. "/" .. rel, "rb")
  local S = f and CacheBlob.decode(rel, f:read("*a"))
  if f then f:close() end
  if type(S) == "string" then S = assert(loadstring(S))() end
  T.check(type(S) == "table", "the game's scripts")
  local vm = { scripts = S or {}, ctx = { pc = {} } }
  local function walk()
    local skipped, menus = {}, 0
    for key, list in pairs(vm.scripts) do
      for i, row in ipairs(list) do
        vm.ctx.pc.listKey, vm.ctx.pc.index = key, i + 1
        if Sh.skips(vm, row.op, row) then skipped[#skipped + 1] = { key = key, i = i, op = row.op } end
        if row.op == "special" then
          local name = require("src.core.game3.scripting.natives").specialName(row.id)
          if name == "CreatePCMenu" or name == "ScriptMenu_CreatePCMultichoice" or name == "BedroomPC" then
            menus = menus + 1
          end
        end
      end
    end
    return skipped, menus
  end
  local skipped, menus = walk()
  local by = { message = 0, waitmessage = 0, callstd = 0 }
  for _, s in ipairs(skipped) do by[s.op] = (by[s.op] or 0) + 1 end
  T.check(menus >= 2, "the PC menus in the scripts (" .. menus .. ")")
  T.check(by.callstd >= 2, "the boot lines skipped (" .. by.callstd .. ": Center and bedroom)")
  T.check(by.message >= 1 and by.message == by.waitmessage, "the menu's prompt skipped (" .. by.message .. ")")
  T.eq(#skipped, by.message + by.waitmessage + by.callstd, "and nothing else")
  -- through the hook: skipped (no vanilla call); with the Desktop option off, the game's
  local Runtime = require("src.mods.Runtime")
  local s1 = skipped[1]
  local row = vm.scripts[s1.key][s1.i]
  vm.ctx.pc.listKey, vm.ctx.pc.index = s1.key, s1.i + 1
  local ran = false
  local function vanilla() ran = true; return false end
  Runtime.call("script.command", vanilla, { runner = vm }, row.op, row)
  T.check(not ran, "the hook skips it")
  Sh.enabled = function() return false end
  Runtime.call("script.command", vanilla, { runner = vm }, row.op, row)
  T.check(ran, "with the Desktop option off: the game's line")
  Sh.enabled = function() return true end
end

-- ------- the boot bar: full before the reveal
T.check(D.bootFill(0.4) > 0.5, ("quick at first (%.2f at 0.4 s)"):format(D.bootFill(0.4)))
T.eq(D.bootFill(D.BOOT.LOGO - 0.2), 1, "full before the reveal")
T.eq(D.bootFill(D.BOOT.LOGO), 1, "and through it")

-- ------- window shapes
openPc({ startMode = "select" })
st = D.state()
D.skipBoot()
local shapes = { { "3:2", 480, 320 }, { "16:9", 1280, 720 }, { "21:9", 1680, 720 }, { "4:3", 1024, 768 },
                 { "phone upright", 390, 844 }, { "tablet upright", 768, 1024 }, { "tiny", 240, 160 } }
for _, shape in ipairs(shapes) do
  VP.width, VP.height = shape[2], shape[3]
  draw(30)
  local L = st.layout
  T.check(L.cols >= 2 and L.rows >= 1, shape[1] .. ": a grid of " .. L.cols .. " x " .. L.rows)
  local inside = true
  for _, h in ipairs(st.hit) do
    if h[1] < -0.5 or h[2] < -0.5 or h[1] + h[3] > shape[2] + 0.5 or h[2] + h[4] > shape[3] + 0.5 then
      inside = false
    end
  end
  T.check(inside, shape[1] .. ": everything to tap is inside the window")
  T.eq(L.portrait, shape[3] > shape[2] * 1.15 or (shape[2] / shape[3] < 1.15), shape[1] .. ": "
    .. (L.portrait and "portrait" or "landscape"))
  -- the shelf under the monitor: inside the page, the pad in its middle, the monitor on it
  local sh, lip, pb = L.shelf, L.lip, L.pad
  T.check(sh and lip and pb and lip[2] + lip[4] <= L.ph + 0.01 and pb[1] >= 0 and pb[1] + pb[3] <= L.pw
    and math.abs(pb[1] + pb[3] / 2 - L.pw / 2) < 0.01 and L.body[2] + L.body[4] <= L.ph - D.SHELF.h + 2
    and L.body[2] + L.body[4] > sh[2], shape[1] .. ": the shelf under the monitor, the pad in its middle")
  local foot = L.body[2] + L.body[4]
  T.check(pb[2] > foot and pb[2] + pb[4] < lip[2]
    and math.abs((pb[2] - foot) - (lip[2] - pb[2] - pb[4])) < 0.01,
    shape[1] .. ": the pad clear of the monitor and the shelf's front edge, centred between them")
  if not L.portrait then
    T.check(math.abs(L.screen[4] - 124) < 1e-6, shape[1] .. ": the screen as tall as ever (units)")
  end
end
VP.width, VP.height = 480, 320

-- pages: more apps than fit
for i = 1, 14 do
  Apps.register({ id = "test" .. i, label = "Test " .. i, glyph = "gear", order = 60, open = noop })
end
st.ctx.logoff()
openPc({ startMode = "select" })
st = D.state()
D.skipBoot()
draw(30)
T.check(#st.grid > st.perPage, "more apps than one page (" .. #st.grid .. " for " .. st.perPage .. ")")
D.input(input({}, {}))
press("r")
T.eq(st.page, 2, "R: the next page")
D.wheel(1)
T.eq(st.page, 1, "the wheel: back")
local grid1 = hitOf("grid")
D.pointer({ id = 2, phase = "pressed", x = grid1[1] + 5, y = grid1[2] + 5 })
D.pointer({ id = 2, phase = "moved", x = grid1[1] - 80, y = grid1[2] + 5 })
D.pointer({ id = 2, phase = "released", x = grid1[1] - 80, y = grid1[2] + 5 })
T.eq(st.page, 2, "a swipe: the next page")
T.check(st.zoom == nil, "and opens nothing")

-- ------- the item model (the engine's own Storage / Bag)
st.ctx.logoff()
local Inv, Mb = X._test.inv, X._test.mb
local Storage, Bag = require("src.core.game3.storage"), require("src.core.game3.bag")
local ItemsData, Mail = require("src.core.game3.items_data"), require("src.core.game3.mail")
local POTION = 13
local function newSession()
  local s = { name = "WOS", bag = Bag.new(), storage = Storage.new(), party = {} }
  s.storage.items = { { id = POTION, qty = 5 } }
  ItemsData.ensureModel(s)
  return s
end
local s = newSession()
local plain, keyItem = {}, nil
for id = 1, 400 do
  local info = ItemsData.info(id)
  if info and info.name and info.name ~= "" and not Mail.isMailItem(id) then
    if info.pocket == "ITEMS" and (tonumber(info.importance) or 0) == 0 and id ~= POTION then plain[#plain + 1] = id end
    if not keyItem and info.pocket == "KEY_ITEMS" and (tonumber(info.importance) or 0) ~= 0 then keyItem = id end
  end
end
T.check(#plain > 50 and keyItem ~= nil, "plain items and a key item to test with (" .. #plain .. ", " .. tostring(keyItem) .. ")")
T.eq(Inv.pockets(s)[1].id, "ITEMS", "the Bag's pockets, Items first")
T.eq(Inv.pcRows(s)[1].qty, 5, "the PC's rows")
T.check(Inv.withdraw(s, 1, 2), "withdraw 2")
T.eq(Storage.ensure(s).items[1].qty, 3, "the PC keeps 3")
T.eq(Bag.get(s.bag, POTION), 2, "the Bag has 2")
T.check(Inv.withdraw(s, 1, 3), "withdraw the rest")
T.eq(#Storage.ensure(s).items, 0, "the PC's row is gone")
T.check(Inv.deposit(s, "ITEMS", 1, 5), "deposit all 5 back")
T.eq(Storage.ensure(s).items[1] and Storage.ensure(s).items[1].qty, 5, "the PC has 5 again")
T.eq(Bag.get(s.bag, POTION), 0, "the Bag none")
-- a full PC refuses, and nothing moves
local _, cap = Inv.pcCount(s)
for i = 1, cap - 1 do Storage.ensure(s).items[#Storage.ensure(s).items + 1] = { id = plain[i], qty = 1 } end
Bag.add(s.bag, plain[cap], 2)
local ok, why = Inv.deposit(s, "ITEMS", 1, 2)
T.check(not ok and why == "pc_full", "a full PC refuses (" .. tostring(why) .. ")")
T.eq(Bag.get(s.bag, plain[cap]), 2, "and the Bag keeps them")
-- an important item stays in the Bag, and can't be tossed
s = newSession()
Bag.add(s.bag, keyItem, 1)
local pocketRows = Inv.bagRows(s, "KEY_ITEMS")
ok, why = Inv.deposit(s, "KEY_ITEMS", 1, 1)
T.check(#pocketRows == 1 and not ok and why == "important", "an important item stays in the Bag (" .. tostring(why) .. ")")
Storage.ensure(s).items[2] = { id = keyItem, qty = 1 }
ok, why = Inv.toss(s, 2, 1)
T.check(not ok and why == "important", "and can't be tossed from the PC")
T.check(Inv.toss(s, 1, 2) and Storage.ensure(s).items[1].qty == 3, "a Potion can (5 -> 3)")
-- a full Bag refuses a withdrawal
s = newSession()
local n = 0
for _, id in ipairs(plain) do
  if not Bag.canAdd(s.bag, id, 1) then break end
  Bag.add(s.bag, id, 1)
  n = n + 1
end
T.check(not Bag.canAdd(s.bag, POTION, 1), "the Bag's Items pocket filled (" .. n .. ")")
ok, why = Inv.withdraw(s, 1, 1)
T.check(not ok and why == "bag_full", "a full Bag refuses (" .. tostring(why) .. ")")
T.eq(Storage.ensure(s).items[1].qty, 5, "and the PC keeps them")
-- sort
s = newSession()
Storage.ensure(s).items = { { id = plain[3], qty = 1 }, { id = POTION, qty = 1 }, { id = plain[1], qty = 1 } }
Inv.sort(s, "name")
local names = {}
for i, e in ipairs(Storage.ensure(s).items) do names[i] = ItemsData.displayName(e.id):lower() end
T.check(names[1] <= names[2] and names[2] <= names[3], "sorted by name (" .. table.concat(names, ", ") .. ")")
-- sort a Bag pocket: by name, by type (the items' numbers); the pockets the game keeps in order stay
do
  s = newSession()
  for _, id in ipairs({ plain[3], POTION, plain[1], plain[2] }) do Bag.add(s.bag, id, 1) end
  local function order(key)
    local out = {}
    for i, r in ipairs(Inv.bagRows(s, "ITEMS")) do out[i] = key == "name" and r.name:lower() or ItemsData.toNumericId(r.id) end
    return out
  end
  T.check(Inv.sortPocket(s, "ITEMS", "name"), "the Items pocket: sorted")
  local byName = order("name")
  T.check(byName[1] <= byName[2] and byName[2] <= byName[3] and byName[3] <= byName[4],
    "the Bag by name (" .. table.concat(byName, ", ") .. ")")
  T.check(Inv.sortPocket(s, "ITEMS", "type"), "and by type")
  local byNum = order("type")
  T.check(byNum[1] < byNum[2] and byNum[2] < byNum[3] and byNum[3] < byNum[4],
    "the Bag by type: the items' numbers (" .. table.concat(byNum, ", ") .. ")")
  T.eq(Bag.get(s.bag, POTION), 1, "(nothing lost)")
  local okT, whyT = Inv.sortPocket(s, "TM_CASE", "name")
  T.check(not okT and whyT == "fixed", "the TM Case keeps the game's order (" .. tostring(whyT) .. ")")
end

-- ------- the mail model (the engine's own pool)
s = newSession()
local pool = Mail.pool(s)
local function letter(slot, item, from)
  local rec = pool[slot]
  Mail.clear(rec)
  rec.itemId, rec.playerName, rec.species = item, from, 25
  return rec
end
letter(9, 121, "MOM")
letter(12, 122, "DAD")
local pika = { species = 25, item = 0 }
local busy = { species = 1, item = POTION }
s.party = { pika, busy }
local inbox = Mb.inbox(s)
T.eq(#inbox, 2, "the inbox: the PC's two mails")
T.check(inbox[1].slot == 7 and inbox[2].slot == 8, "packed to the front")
T.eq(inbox[1].from, "MOM", "first to last")
ok = Mb.toBag(s, inbox[1])
T.check(ok and Bag.get(s.bag, 121) == 1, "to the Bag: the stationery as an item")
T.eq(#Mb.inbox(s), 1, "and the mail gone from the inbox")
inbox = Mb.inbox(s)
ok, why = Mb.give(s, inbox[1], busy)
T.check(not ok and why == "holding", "a Pokémon holding an item can't take it")
T.check(Mb.give(s, inbox[1], pika), "give it to Pikachu")
T.check(pika.item == 122 and Mail.monHasMail(pika), "Pikachu holds it")
T.eq(#Mb.inbox(s), 0, "the inbox is empty")
local held = Mb.held(s)
T.eq(#held, 1, "the Held folder has it")
T.eq(held[1].from, "DAD", "with its message")
T.check(Mb.take(s, held[1]) and (pika.item or 0) == 0, "Take: back into the inbox")
T.eq(#Mb.inbox(s), 1, "the inbox has it again")
for i = 8, 16 do letter(i, 121, "X") end
T.check(Mail.giveMailToMon2(s, pika, Mail.copy(pool[7])) ~= Mail.MAIL_NONE, "(Pikachu holds another)")
ok, why = Mb.take(s, Mb.held(s)[1])
T.check(not ok and why == "box_full", "a full mailbox refuses (" .. tostring(why) .. ")")

-- ------- the windows over a session: buttons move items, the mail reads
s = newSession()
openPc({ startMode = "select", session = s })
st = D.state()
D.skipBoot()
draw(30)
st.focus, st.dockCursor = "dock", 2
T.eq(select(4, D.padState()), 0, "the shelf's pad: dark on the home screen")
D.input(input({}, {}))
press("a")
draw(30)
local IW = D.window()
T.check(IW and IW.title == "Items", "Items over a session")
draw(20)
T.check(select(4, D.padState()) > 0.99, "the pad lights up with Items open")
do
  local party0 = s.party
  s.party = { { species = 25 }, { speciesId = 1 }, { species = 0 } }
  draw(70)
  T.eq(st.balls, 2, "the party read for the pad's Poké Ball (" .. tostring(st.balls) .. " Pokémon)")
  T.eq(D.ballState(), "off", "Items holds no Pokémon: no ball on the pad")
  s.party = party0
end
press("a")
T.check(IW.state.step and IW.state.step.qty == 5, "A on 5 Potions: how many (all to start)")
press("down")
T.eq(IW.state.step.qty, 1, "Down: ten fewer (no fewer than one)")
press("up")
T.eq(IW.state.step.qty, 5, "Up: ten more (no more than there are)")
press("left")
T.eq(IW.state.step.qty, 4, "Left: one fewer")
press("a")
T.eq(Bag.get(s.bag, POTION), 4, "A: 4 to the Bag")
T.eq(Storage.ensure(s).items[1].qty, 1, "1 left in the PC")
do
  local n, dir, id = D.padState()
  T.check(n == 1 and dir == "in" and id == POTION, "the Potion digitizes in on the pad (" .. tostring(dir) .. ")")
end
press("left")
T.eq(IW.state.focus, "bag", "Left: the Bag")
press("select")
T.eq(Bag.get(s.bag, POTION), 0, "SELECT: the whole stack to the PC")
T.eq(Storage.ensure(s).items[1].qty, 5, "5 in the PC again")
do
  local n, dir = D.padState()
  T.check(n == 2 and dir == "in", "going to the PC waits for the one coming in")
  draw(80)
  local n2, dir2, id2 = D.padState()
  T.check(n2 == 1 and dir2 == "out" and id2 == POTION, "then the Potion digitizes away (" .. tostring(dir2) .. ")")
  -- (a second move the same way while one waits: the last one chosen is shown)
  D.padTransfer(POTION, "in")
  D.padTransfer(13, "in")
  local n3 = D.padState()
  T.eq(n3, 2, "one waiting, the last one chosen")
  T.eq(st.padQ[2].id, 13, "(its item)")
  st.padN = 1
end
press("start")
T.check(IW.state.menu ~= nil, "START: the menu")
press("b")
T.check(IW.state.menu == nil and D.window() == IW, "B: the menu closes, the window stays")
-- the Bag's own sort: START on the Bag, Sort by Name, then the Bag's Sort button
do
  for _, id in ipairs({ plain[3], plain[1], plain[2] }) do Bag.add(s.bag, id, 1) end
  IW.refresh()
  press("left")
  T.eq(IW.state.focus, "bag", "(the Bag in focus)")
  press("start")
  T.check(IW.state.menu and IW.state.menu.pane == "bag" and #IW.state.menu.list == 2, "START on the Bag: the Bag's sort menu")
  draw(2)
  press("a")
  local rows = IW.state.bag.rows
  local sorted = #rows >= 3
  for i = 2, #rows do sorted = sorted and rows[i - 1].name:lower() <= rows[i].name:lower() end
  T.check(IW.state.menu == nil and sorted, "Sort by Name: the pocket in order (" .. #rows .. ")")
  IW.tap(2031)
  T.check(IW.state.menu and IW.state.menu.pane == "bag", "the Bag's Sort button: its menu")
  IW.tap(2021)
  rows = IW.state.bag.rows
  sorted = #rows >= 3
  for i = 2, #rows do sorted = sorted and ItemsData.toNumericId(rows[i - 1].id) <= ItemsData.toNumericId(rows[i].id) end
  T.check(sorted, "Sort by Type: by the items' numbers")
  IW.tap(2030)
  T.check(IW.state.menu and IW.state.menu.pane == "pc" and IW.state.focus == "pc", "the PC's Sort: the PC's menu")
  press("b")
end
draw(30)
local perW = garbageOf(120)
T.check(perW < 0.3, ("the Items window draws next to no garbage (%.3f KB a frame)"):format(perW))
T.eq(D.padState(), 0, "the pad's effects play out")
-- an effect on its own, warm, measured as it plays (each pass a new one)
local perP = garbageOf(60, function()
  draw(120)
  D.padTransfer(POTION, "out")
  draw(2)
end)
T.check(perP < 0.3, ("an item crossing the pad makes next to no garbage (%.3f KB a frame)"):format(perP))
for _, shape in ipairs({ { 480, 320 }, { 320, 480 }, { 900, 320 } }) do
  VP.width, VP.height = shape[1], shape[2]
  draw(2)
  T.check(not D.state().winFailed, "the Items window draws " .. shape[1] .. "x" .. shape[2])
end
VP.width, VP.height = 480, 320
press("b")
T.check(D.window() == nil, "B closes Items")
draw(30)
pool = Mail.pool(s)
letter(7, 121, "MOM")
st.focus, st.dockCursor = "dock", 3
D.input(input({}, {}))
press("a")
draw(30)
local MW = D.window()
T.check(MW and MW.title == "Mail", "Mail over a session")
T.eq(#MW.state.inbox, 1, "its inbox")
press("a")
T.eq(MW.state.focus, "reader", "A opens the mail")
draw(10)
press("a")
T.eq(MW.state.sheet, "bag", "Move to Bag asks first")
press("left")
press("a")
T.eq(Bag.get(s.bag, 121), 1, "yes: the stationery to the Bag")
T.eq(#MW.state.inbox, 0, "and the inbox is empty")
for _, shape in ipairs({ { 480, 320 }, { 320, 480 } }) do
  VP.width, VP.height = shape[1], shape[2]
  draw(2)
  T.check(not D.state().winFailed, "the Mail window draws " .. shape[1] .. "x" .. shape[2])
end
VP.width, VP.height = 480, 320
press("b")
T.check(D.window() == nil, "B closes Mail")
draw(30)

-- ------- the Mart: the stock by badges, buying, selling (src/mart.lua), then its window
local Mt = X._test.mart
do
  local tabs = Mt.tabs()
  T.eq(#tabs, 4, "the Mart's four tabs")
  T.check(tabs[1].rows[1].id == 4 and tabs[1].rows[1].price == 200, "Poké Balls first, at the game's price")
  local priced = true
  for _, t in ipairs(tabs) do for _, r in ipairs(t.rows) do priced = priced and r.price > 0 end end
  T.check(priced, "everything on sale has a price")
end
local ms = newSession()
ms.money = 5000
ok, why = Mt.buy(ms, 3, 1, 0)
T.check(not ok and why == "badges" and ms.money == 5000, "no badges: no Great Balls (" .. tostring(why) .. ")")
local great = Mt.price(3)
T.check(Mt.buy(ms, 3, 3, 1) and Bag.get(ms.bag, 3) == 3 and ms.money == 5000 - 3 * great,
  "one badge: three Great Balls into the Bag, paid for")
ms.money = 100
ok, why = Mt.buy(ms, POTION, 1, 0)
T.check(not ok and why == "money" and Bag.get(ms.bag, POTION) == 0 and ms.money == 100,
  "too little money: nothing bought (" .. tostring(why) .. ")")
ms.money = 5000
do
  local okB, bonus = Mt.buy(ms, 4, 10, 0)
  T.check(okB and bonus and Bag.get(ms.bag, 4) == 10 and Bag.get(ms.bag, Mt.PREMIER) == 1 and ms.money == 3000,
    "ten Poké Balls: a Premier Ball thrown in")
end
do
  local fs = newSession()
  fs.money = 5000
  for _, id in ipairs(plain) do
    if not Bag.canAdd(fs.bag, id, 1) then break end
    Bag.add(fs.bag, id, 1)
  end
  ok, why = Mt.buy(fs, POTION, 1, 0)
  T.check(not ok and why == "bag_full" and fs.money == 5000, "a full Bag: nothing bought (" .. tostring(why) .. ")")
end
ms.money = 0
Bag.add(ms.bag, POTION, 3)
do
  local okS, earned = Mt.sell(ms, POTION, 2)
  local half = math.floor(Mt.price(POTION) / 2)
  T.check(okS and earned == 2 * half and Bag.get(ms.bag, POTION) == 1 and ms.money == 2 * half,
    "two Potions sold for half their price (" .. tostring(earned) .. ")")
end
Bag.add(ms.bag, keyItem, 1)
ok, why = Mt.sell(ms, keyItem, 1)
T.check(not ok and why == "cant_sell" and Bag.get(ms.bag, keyItem) == 1, "a key item can't be sold")
ok, why = Mt.sell(ms, POTION, 5)
T.check(not ok and why == "gone", "nor more than there are")
ms.money = 999990
T.check(Mt.sell(ms, POTION, 1) and ms.money == 999999, "the money stops at 999,999")
T.eq(Mt.sellRows(ms, "POKE_BALLS")[1].price, Mt.sellPrice(Mt.sellRows(ms, "POKE_BALLS")[1].id), "the Bag's rows, priced to sell")

-- the window: a locked item, a purchase onto the pad, a sale off it
s.money = 10000
do
  local at
  for i, app in ipairs(st.grid) do if app.id == "mart" then at = i end end
  T.check(at ~= nil, "Mart on the home screen")
  D.launch("grid", at)
end
draw(30)
local MartW = D.window()
T.check(MartW and MartW.title == "Mart", "the Mart opens")
local ms2 = MartW.state
ms2.badges = 0
T.eq(ms2.rows[1].id, 4, "Poké Balls first")
press("down")
press("a")
T.check(ms2.focus == "list" and ms2.toast and ms2.toast.bad, "a Great Ball with no badges: why not, not how many")
ms2.badges = 8
press("a")
T.eq(ms2.focus, "step", "with the badges: how many")
press("right")
press("right")
press("up")
press("down")
T.eq(ms2.qty, 3, "Right twice: three (Up ten, Down ten)")
local before = Bag.get(s.bag, 3)
press("a")
T.check(Bag.get(s.bag, 3) == before + 3 and s.money == 10000 - 3 * great, "A: three Great Balls bought")
do
  local n, dir, id = D.padState()
  T.check(n >= 1 and dir == "in" and id == 3, "they appear on the pad (" .. tostring(dir) .. ")")
end
T.eq(ms2.focus, "list", "back in the list")
press("start")
T.eq(ms2.mode, "sell", "START: Sell")
for i, p in ipairs(ms2.pockets) do if p.id == "POKE_BALLS" then ms2.sellTab = i end end
MartW.refresh()
for i, r in ipairs(ms2.rows) do if r.id == 3 then ms2.cursor = i end end
MartW.refresh()
press("a")
press("a")
T.eq(Bag.get(s.bag, 3), before + 2, "a Great Ball sold")
T.eq(s.money, 10000 - 3 * great + math.floor(great / 2), "for half its price")
draw(90)
do
  local n, dir = D.padState()
  T.check(n >= 1 and dir == "out", "it leaves off the pad (" .. tostring(dir) .. ")")
end
press("start")
draw(30)
-- (headless the cart's font isn't there, and the engine's glyph draw tries loading it again on
-- every call: a stand-in for the Pokédollar sign while measuring; the probe measures the real one)
local FrlgFont = require("src.ui.game3.frlg_font")
local realGlyph = FrlgFont.drawGlyph
FrlgFont.drawGlyph = function() return 7 end
local perM = garbageOf(120)
FrlgFont.drawGlyph = realGlyph
T.check(perM < 0.3, ("the Mart draws next to no garbage (%.3f KB a frame)"):format(perM))
for _, shape in ipairs({ { 480, 320 }, { 320, 480 }, { 900, 320 } }) do
  VP.width, VP.height = shape[1], shape[2]
  draw(2)
  T.check(not D.state().winFailed, "the Mart draws " .. shape[1] .. "x" .. shape[2])
end
VP.width, VP.height = 480, 320
press("b")
T.check(D.window() == nil, "B closes the Mart")
draw(30)

-- ------- R-Bay: the market from a seed and the clock, bids, settling (src/auction.lua), its window
local Au = X._test.auction
local Party = require("src.core.game3.party")
local PokemonM = require("src.core.game3.pokemon")
local fakeSave = { data = {} }
function fakeSave.get(self, k) return self.data[k] end
function fakeSave.set(self, k, v) self.data[k] = v end
local store0, now0 = Au.store, Au.now
Au.store = fakeSave
local T0 = 1800000000
local tnow = T0
Au.now = function() return tnow end
local as = newSession()
as.meta = { playthroughId = "test-run" }
as.money = 0
do
  local list = Au.listings(as, T0)
  T.eq(#list, 12, "twelve auctions at once")
  local ok3h, spaced = true, true
  for i, L in ipairs(list) do
    ok3h = ok3h and L.finish - L.start == 3 * 3600 and L.start <= T0 and T0 < L.finish
    if i > 1 then spaced = spaced and L.finish - list[i - 1].finish == 900 end
  end
  T.check(ok3h, "each runs three hours, all running now")
  T.check(spaced, "one ends every fifteen minutes")
  local a, b = Au.generate(as, 3, 9000, 0), Au.generate(as, 3, 9000, 0)
  T.check(a.sp == b.sp and a.ivSum == b.ivSum and a.value == b.value and #a.bidders == #b.bidders,
    "the same seed, the same auction")
  local other = { meta = { playthroughId = "another-run" } }
  local c = Au.generate(other, 3, 9000, 0)
  T.check(c.sp ~= a.sp or c.ivSum ~= a.ivSum or c.value ~= a.value, "another save, another auction")
  local keys = {}
  for _, L in ipairs(list) do keys[L.key] = true end
  local changed = 0
  for _, L in ipairs(Au.listings(as, T0 + 900)) do if not keys[L.key] then changed = changed + 1 end end
  T.eq(changed, 1, "fifteen minutes on: one new auction")
end
do
  local pools = Au.pools()
  local legend = {}
  for _, e in ipairs(pools.legendary) do legend[e.sp] = true end
  T.check(legend[PokemonM.speciesFromNational(150)] and legend[PokemonM.speciesFromNational(384)],
    "Mewtwo and Rayquaza are legendary")
  local myth = {}
  for _, e in ipairs(pools.mythical) do myth[e.sp] = true end
  T.check(myth[PokemonM.speciesFromNational(151)] and not legend[PokemonM.speciesFromNational(151)], "Mew is mythical")
  local seen, capped, mono = {}, true, true
  local hiQ, loQ, hiN, loN = 0, 0, 0, 0
  for n = 9000, 9030 do
    for k = 0, 11 do
      local L = Au.generate(as, k, n, 0)
      seen[L.tier] = true
      if L.tier == "legendary" and not legend[L.sp] then mono = false end
      for _, bd in ipairs(L.bidders) do capped = capped and bd.max <= L.value * Au.CAP + 10 end
      if L.tier == "rare" then
        if L.ivSum >= 93 then hiQ, hiN = hiQ + L.value, hiN + 1 else loQ, loN = loQ + L.value, loN + 1 end
      end
      -- (the price only goes up)
      local last = 0
      for t = L.start, L.finish, 600 do
        local p = Au.sim(L, t, nil)
        if p < last then mono = false end
        last = p
      end
    end
  end
  T.check(seen.common and seen.uncommon and seen.rare and seen.prized and seen.legendary and seen.mythical,
    "every tier turns up over a few days")
  T.check(capped, "no fake bidder goes past 1.35 times the value")
  T.check(mono, "prices only go up; legendaries only as legendary")
  T.check(hiN > 0 and loN > 0 and hiQ / hiN > loQ / loN, ("better IVs, a higher value (%d vs %d)"):format(
    math.floor(hiQ / math.max(1, hiN)), math.floor(loQ / math.max(1, loN))))
end
-- a bid: too low, too dear, then a winning maximum; a raise takes only the difference
local Lw
for _, L in ipairs(Au.listings(as, T0)) do
  if not Lw and #L.bidders > 0 and L.tier ~= "legendary" and L.tier ~= "mythical" then Lw = L end
end
T.check(Lw ~= nil, "an auction to bid on")
tnow = Lw.start + 10
Au.listings(as, tnow)
as.money = 10
ok, why = Au.bid(as, Lw, Au.minBid(Lw) - 1, tnow)
T.check(not ok and why == "too_low", "under the least bid: refused (" .. tostring(why) .. ")")
ok, why = Au.bid(as, Lw, Au.minBid(Lw) + 100000, tnow)
T.check(not ok and why == "money" and as.money == 10, "more than the money: refused (" .. tostring(why) .. ")")
local top = 0
for _, bd in ipairs(Lw.bidders) do top = math.max(top, bd.max) end
local myMax = top + 5000
as.money = 900000
T.check(Au.bid(as, Lw, myMax, tnow) and as.money == 900000 - myMax, "a maximum over them all: held from the money")
T.check(Au.bid(as, Lw, myMax + 2000, tnow + 5) and as.money == 900000 - myMax - 2000, "a raise takes only the difference")
myMax = myMax + 2000
ok, why = Au.bid(as, Lw, myMax - 1, tnow + 6)
T.check(not ok and why == "too_low", "a maximum can't come down")
local price = Au.sim(Lw, Lw.finish, fakeSave.data.auction.bids[Lw.key])
T.check(price <= top + Au.step(top) and price >= Lw.startPrice, "the price: one step over the best of the rest (" .. price .. ")")
-- the end: the Pokémon to the party with the listed IVs, the change back
as.party = {}
local before = as.money
local won, lost = Au.settle(as, Lw.finish - 1)
T.check(won == 0 and lost == 0, "not before it ends")
won, lost = Au.settle(as, Lw.finish)
T.check(won == 1 and lost == 0, "it ends: won")
local got = as.party[1]
T.check(got and tonumber(got.species) == Lw.sp and got.level == Lw.level, "the Pokémon joins the party")
local same = got ~= nil
for _, key in ipairs(Au.IV_KEYS) do same = same and got.ivs[key] == Lw.ivs[key] end
T.check(same and got.hp == got.maxHp and (got.maxHp or 0) > 0, "with the listed IVs, its stats again, full HP")
T.eq(as.money, before + myMax - price, "the change comes back")
T.eq(Au.results()[1].won, true, "a result: won")
T.check(Au.unread() >= 1, "unread")
won, lost = Au.settle(as, Lw.finish + 60)
T.check(won == 0 and lost == 0 and #as.party == 1, "settled once only")
-- a loss: the whole maximum back
local Ll
for _, L in ipairs(Au.listings(as, Lw.finish)) do
  local hi = 0
  for _, bd in ipairs(L.bidders) do hi = math.max(hi, bd.max) end
  if not Ll and hi > L.startPrice + Au.step(L.startPrice) * 2 then Ll = L end
end
T.check(Ll ~= nil, "an auction to lose")
tnow = math.max(Lw.finish, Ll.start + 5)
Au.listings(as, tnow)
as.money = 500000
local lowMax = Au.minBid(Ll)
local outbidLater = false
for _, bd in ipairs(Ll.bidders) do outbidLater = outbidLater or bd.max > lowMax end
T.check(outbidLater and Au.bid(as, Ll, lowMax, tnow) and as.money == (Ll.leader == 0 and 500000 - lowMax or 500000),
  "a low maximum: held while it leads, back at once if outbid")
won, lost = Au.settle(as, Ll.finish)
T.check(won == 0 and lost == 1 and as.money == 500000, "outbid at the end: all of it back")
T.eq(Au.results()[1].won, false, "a result: lost")
-- outbid the moment you bid: the money back at once, the leader's answer the new top bid
do
  local Lo, tt
  for _, at in ipairs({ 0.5, 0.7, 0.9 }) do
    for _, L in ipairs(Au.listings(as, Ll.finish)) do
      local t1 = math.floor(L.start + (L.finish - L.start) * at)
      local _, leader, lmax = Au.sim(L, t1, nil)
      if not Lo and leader and lmax > Au.minBid(L) + Au.step(Au.minBid(L)) and t1 >= Ll.finish then Lo, tt = L, t1 end
    end
    if Lo then break end
  end
  T.check(Lo ~= nil, "an auction led by a high maximum")
  if Lo then
    Au.listings(as, tt)
    as.money = 500000
    local least = Au.minBid(Lo)
    T.check(Au.bid(as, Lo, least, tt) and Lo.leader ~= 0, "a bid under the leader's maximum: outbid at once")
    T.eq(as.money, 500000, "outbid: the money comes back at once")
    local top = (Lo.histN - 1) % 5 + 1
    T.check(Lo.histWho[top] == Lo.leader and Lo.histAmt[top] == Lo.price and Lo.price > least,
      "the top bid is the leader's answer (" .. tostring(Lo.price) .. " over " .. least .. ")")
    Au.listings(as, tt + 2)
    T.eq(as.money, 500000, "nothing taken twice on the next refresh")
    local again = Au.minBid(Lo)
    T.check(Au.bid(as, Lo, again, tt + 3) and as.money == (Lo.leader == 0 and 500000 - again or 500000),
      "bid again: the whole new maximum held (if it leads)")
    Au.settle(as, Lo.finish)
  end
end
-- a win with no room: it waits, then arrives
do
  local Lp = Au.listings(as, Ll.finish)[12]
  tnow = Ll.finish
  as.money = 999999
  T.check(Au.bid(as, Lp, 999000, tnow), "(a bid nobody beats)")
  local give = Party.giveMonToPlayer
  Party.giveMonToPlayer = function() return 2 end
  won = Au.settle(as, Lp.finish)
  local waiting = fakeSave.data.auction.bids[Lp.key]
  T.check(won == 0 and waiting and waiting.won == true, "no room anywhere: the win waits")
  Party.giveMonToPlayer = give
  as.party = {}
  won = Au.settle(as, Lp.finish + 10)
  T.check(won == 1 and as.party[1] and fakeSave.data.auction.bids[Lp.key] == nil, "then it arrives")
end
-- WoobleDex's species join the pools (a stand-in for its exports)
do
  local makeAu = dofile("mods/woob_os/src/auction.lua")
  local Au2 = makeAu(function(n) return require(n) end, { dex = function()
    return { exports = { apiVersion = 2,
      listSpecies = function() return { { dex = 480, slot = 999, name = "UXIE", legendary = true },
                                         { dex = 387, slot = 998, name = "TURTWIG" } } end,
      evolutionsOf = function(d) if d == 387 then return { evolvesInto = { { id = "grotle" } } } end end } }
  end })
  local p = Au2.pools()
  local inL, inP = false, false
  for _, e in ipairs(p.legendary) do inL = inL or e.sp == 999 end
  for _, e in ipairs(p.prized) do inP = inP or e.sp == 998 end
  T.check(inL and inP, "WoobleDex's legendaries and starters join the market")
end

-- the window: browse, bid with the buttons, My Bids, the count on the icon
s.money = 900000
tnow = T0
fakeSave.data = {}
do
  local at
  for i, app in ipairs(st.grid) do if app.id == "auction" then at = i end end
  T.check(at ~= nil, "R-Bay on the home screen")
  D.launch("grid", at)
end
draw(30)
local RW = D.window()
T.check(RW and RW.title == "R-Bay", "R-Bay opens")
local rs = RW.state
T.eq(#rs.rows, 12, "twelve auctions listed")
local chosen = rs.rows[1]
press("a")
T.eq(rs.focus, "step", "A: your maximum")
T.eq(rs.amount, Au.minBid(chosen), "starting at the least bid")
press("right")
T.check(rs.amount == Au.minBid(chosen) + Au.step(Au.minBid(chosen)), "Right: one step more")
local money0 = s.money
local bidAmount = rs.amount
press("a")
T.check(fakeSave.data.auction and fakeSave.data.auction.bids[chosen.key]
  and s.money == (chosen.leader == 0 and money0 - bidAmount or money0),
  "A: the bid placed, the maximum held (or back at once, outbid)")
T.eq(rs.focus, "list", "back in the list")
if chosen.leader == 0 then
  local live = 0
  for _, p in ipairs(rs.particles) do if p.live then live = live + 1 end end
  T.check(live > 0, "in the lead: confetti")
end
draw(2)
T.check(rs.hotKey ~= nil, "a Hot Auction picked")
press("select")
T.check(rs.key == rs.hotKey and rs.rows[rs.cursor].key == rs.hotKey, "SELECT: to the Hot Auction")
draw(2)
press("r")
T.eq(rs.tab, "mine", "R: My Bids")
draw(2)
T.check(rs.mineN >= 1 and rs.mineRows[1].key == chosen.key, "the bid in My Bids")
local FrlgFont2 = require("src.ui.game3.frlg_font")
local realGlyph2 = FrlgFont2.drawGlyph
FrlgFont2.drawGlyph = function() return 7 end
draw(60)
local perMine = garbageOf(120)
press("l")
draw(60)
local perBrowse = garbageOf(120)
FrlgFont2.drawGlyph = realGlyph2
T.check(perBrowse < 0.3 and perMine < 0.3, ("R-Bay draws next to no garbage (%.3f browsing, %.3f My Bids KB a frame)"):format(
  perBrowse, perMine))
for _, shape in ipairs({ { 480, 320 }, { 320, 480 }, { 900, 320 } }) do
  VP.width, VP.height = shape[1], shape[2]
  draw(2)
  T.check(not D.state().winFailed, "R-Bay draws " .. shape[1] .. "x" .. shape[2])
end
VP.width, VP.height = 480, 320
press("b")
T.check(D.window() == nil, "B closes R-Bay")
-- it ends while the desktop is open: settled on the shell's tick, a count on the icon
tnow = chosen.finish + 1
X._test.tick()
draw(90)
local auApp = Apps.byId("auction")
T.check(#Au.results() >= 1 and (auApp.badgeN or 0) >= 1, "it ends: settled, a count on R-Bay's icon (" ..
  tostring(auApp.badgeN) .. ")")
Au.seen()
draw(70)
T.eq(auApp.badgeN, 0, "seen: no count")
Au.store, Au.now = store0, now0

-- ------- Rocket Slots: the machine's return, spins, the prize corner (src/slots.lua), its window
local Sl = X._test.slots
local slotsSave = { data = {} }
function slotsSave.get(self, k) return self.data[k] end
function slotsSave.set(self, k, v) self.data[k] = v end
local slotsStore0, slotsRng0 = Sl.store, Sl.rng
Sl.store = slotsSave
do
  -- every way the reels can stop: what comes back of a bet, how rare the jackpot is
  local R1, R2, R3 = Sl.REELS[1], Sl.REELS[2], Sl.REELS[3]
  local back, n, jack, rarest = 0, 0, 0, true
  local count = {}
  for _, a in ipairs(R1) do
    for _, b in ipairs(R2) do
      for _, c in ipairs(R3) do
        n = n + 1
        local x, _, j = Sl.payout(a, b, c)
        back = back + x
        if j then jack = jack + 1 end
        if a == b and b == c then count[a] = (count[a] or 0) + 1 end
      end
    end
  end
  local rtp = back / n
  T.check(#R1 == 20 and #R2 == 20 and #R3 == 20, "three reels of twenty")
  T.check(rtp > 0.85 and rtp < 0.97, ("the machine pays back %.1f%% of what's bet"):format(rtp * 100))
  for sym, k in pairs(count) do if sym ~= Sl.ROCKET and k < (count[Sl.ROCKET] or 0) then rarest = false end end
  T.check(jack > 0 and rarest, "the jackpot can come up, rarest of all (1 in " .. math.floor(n / math.max(1, jack)) .. ")")
  -- every line pays back the same: more lines, the same return, only bigger swings
  local same = true
  for l = 2, #Sl.LINES do
    local row, backL = Sl.LINES[l], 0
    for s1 = 1, 20 do
      for s2 = 1, 20 do
        for s3 = 1, 20 do
          backL = backL + Sl.payout(Sl.at(1, s1, row[1]), Sl.at(2, s2, row[2]), Sl.at(3, s3, row[3]))
        end
      end
    end
    if backL ~= back then same = false end
  end
  T.check(#Sl.LINES == 5 and same, "five lines, each paying back the same")
end
-- spins, with the reels told where to stop
local queue = {}
Sl.rng = function(nn) return table.remove(queue, 1) or 1 end
local function stopsFor(a, b, c)
  local function at(r, sym) for i, v in ipairs(Sl.REELS[r]) do if v == sym then return i end end end
  queue = { at(1, a), at(2, b), at(3, c) }
end
local ss = newSession()
ss.money = 40
ok, why = Sl.spin(ss, 1)
T.check(not ok and why == "money" and ss.money == 40, "less than the bet: no spin")
ss.money = 10000
stopsFor(1, 2, 3)
ok = Sl.spin(ss, 2)
T.check(ok and Sl.collect(ss) == 0 and ss.money == 9900, "a losing spin: only the bet goes")
stopsFor(Sl.PIKACHU, Sl.PIKACHU, Sl.PIKACHU)
ok = Sl.spin(ss, 2)
T.eq(ss.money, 9800, "the win held back while the reels turn")
local pays, tickets = Sl.collect(ss)
T.check(pays == 7500 and ss.money == 17300, "three Pikachu: 75 times the bet (" .. tostring(pays) .. ")")
T.check(tickets == 6 and Sl.tickets() == 6, "and Rocket Tickets: 3 a ₽50, ×2 (" .. tostring(tickets) .. ")")
T.check(Sl.collect(ss) == 0, "paid once")
stopsFor(Sl.ROCKET, Sl.ROCKET, Sl.ROCKET)
ss.money = 999000
local okJ, res = Sl.spin(ss, 4)
Sl.collect(ss)
T.check(okJ and res.jackpot and ss.money == 999999, "the jackpot, the money stops at 999,999")
T.eq(Sl.stats().jackpots, 1, "counted")
-- more lines: the bet on each; three Great Balls on the top row pay only when it's played
do
  local function above(r, sym) for i, v in ipairs(Sl.REELS[r]) do if v == sym then return i % 20 + 1 end end end
  local function expect(lines, bet)
    local total = 0
    for l = 1, lines do
      local row = Sl.LINES[l]
      total = total + Sl.payout(Sl.at(1, queue[1], row[1]), Sl.at(2, queue[2], row[2]), Sl.at(3, queue[3], row[3])) * bet
    end
    return total
  end
  queue = { above(1, 2), above(2, 2), above(3, 2) }
  local want1 = expect(1, 100)
  ss.money = 10000
  ok = Sl.spin(ss, 2, 1)
  T.check(ok and ss.money == 9900 and Sl.result.won[2] == 0, "one line: the top row isn't played")
  T.eq(Sl.collect(ss), want1, "one line: only the middle pays")
  queue = { above(1, 2), above(2, 2), above(3, 2) }
  local want3 = expect(3, 100)
  ss.money = 10000
  ok = Sl.spin(ss, 2, 3)
  T.check(ok and ss.money == 9700, "three lines: three bets taken")
  T.check(Sl.result.won[2] == 20 and Sl.result.symbol ~= nil, "the top line: three Great Balls, 20 times its bet")
  local p3 = Sl.collect(ss)
  T.check(p3 == want3 and p3 >= 2000, "paid line by line (" .. tostring(p3) .. ")")
  ss.money = 400
  ok, why = Sl.spin(ss, 2, 5)
  T.check(not ok and why == "money" and ss.money == 400, "five lines of ₽100 with ₽400: no spin")
end
-- the prize corner
local list = Sl.prizes()
local candy, mon
for i, p in ipairs(list) do
  if p.kind == "item" and p.id == 68 then candy = i end
  if p.kind == "mon" and not mon then mon = i end
end
T.check(#list >= 12 and candy and mon, "prizes: items, TMs, Pokémon (" .. #list .. ")")
T.check(list[6].name:find(" ") ~= nil, "a TM named with its move (" .. tostring(list[6].name) .. ")")
Sl.setTickets(5)
ok, why = Sl.redeem(ss, candy)
T.check(not ok and why == "tickets", "too few tickets: refused")
Sl.setTickets(100)
local candies = Bag.get(ss.bag, 68)
ok, why = Sl.redeem(ss, candy)
T.check(ok and why == "bag" and Bag.get(ss.bag, 68) == candies + 1 and Sl.tickets() == 100 - list[candy].cost,
  "a Rare Candy into the Bag, its tickets taken")
ss.party = {}
ok, why = Sl.redeem(ss, mon)
T.check(ok and why == "party" and ss.party[1] and ss.party[1].level == Sl.level(ss), "a Pokémon to the party, at its level")
do
  local give = Party.giveMonToPlayer
  Party.giveMonToPlayer = function() return 2 end
  local before = Sl.tickets()
  ok, why = Sl.redeem(ss, mon)
  Party.giveMonToPlayer = give
  T.check(not ok and why == "no_room" and Sl.tickets() == before, "no room for it: refused, the tickets kept")
end

-- the window: a spin by buttons, the reels stopping in order, the win paid once; the bet; a prize
s.money = 50000
slotsSave.data = {}
do
  local at
  for i, app in ipairs(st.grid) do if app.id == "slots" then at = i end end
  T.check(at ~= nil, "Slots on the home screen")
  D.launch("grid", at)
end
draw(30)
local SW = D.window()
T.check(SW and SW.title == "Slots", "Slots opens")
local sws = SW.state
press("left")
T.eq(sws.bet, 1, "Left: a smaller bet")
press("right")
press("right")
T.eq(sws.bet, 3, "Right: a bigger one (₽500)")
stopsFor(Sl.PIKACHU, Sl.PIKACHU, Sl.PIKACHU)
press("a")
T.check(sws.spinning and s.money == 49500, "A: spinning, the bet taken")
draw(40)
T.check(sws.stopped[1] == false or sws.stopped[1] == true, "(the reels turning)")
press("a")
draw(1)
T.check(sws.stopped[1] and not sws.stopped[3], "A again: the first reel stops")
T.check(sws.tease and sws.stopAt[3] - sws.stopAt[2] > 1.5, "two Pikachu on the line: the last reel held back")
for _ = 1, 600 do
  if not sws.spinning then break end
  draw(1)
end
T.check(not sws.spinning and sws.win and sws.win.pays == 37500 and s.money == 87000, "the reels stop: 75 times ₽500 paid")
T.check(sws.win.tier and sws.win.tier.key == "slots.mega", "a MEGA WIN (" .. tostring(sws.win.tier and sws.win.tier.key) .. ")")
draw(5)
T.eq(Sl.tickets(), 30, "and 30 tickets")
local mid = true
for r = 1, 3 do mid = mid and Sl.REELS[r][((math.floor(sws.pos[r] + 0.5) - 1) % 20) + 1] == Sl.PIKACHU end
T.check(mid, "the reels show three Pikachu on the line")
press("start")
T.check(sws.table, "START: the pay table")
draw(2)
press("b")
T.check(not sws.table and D.window() == SW, "B: back to the machine")
-- the lines: Up / Down, the LINES button going round
press("up")
press("up")
T.eq(Sl.LINE_SETS[sws.lines], 5, "Up: five lines")
press("up")
T.eq(Sl.LINE_SETS[sws.lines], 5, "(no more than five)")
press("down")
T.eq(Sl.LINE_SETS[sws.lines], 3, "Down: three")
SW.tap(2008)
T.eq(Sl.LINE_SETS[sws.lines], 5, "LINES: five")
SW.tap(2008)
T.eq(Sl.LINE_SETS[sws.lines], 1, "LINES again: round to one")
press("up")
do
  local m0 = s.money
  stopsFor(1, 2, 3)
  press("a")
  T.check(sws.spinning and s.money == m0 - 3 * Sl.BETS[sws.bet], "three lines: the bet three times")
  for _ = 1, 600 do
    if not sws.spinning then break end
    draw(1)
  end
  T.check(not sws.spinning, "(stopped)")
end
-- the garbage: idle, then spinning (warmed up)
local FrlgFont3 = require("src.ui.game3.frlg_font")
local realGlyph3 = FrlgFont3.drawGlyph
FrlgFont3.drawGlyph = function() return 7 end
draw(60)
local perIdle = garbageOf(120)
local perSpin = garbageOf(60, function()
  draw(150)
  stopsFor(1, 2, 3)
  SW.input(input({ "a" }, { "a" }), {})
  draw(30)
end)
draw(150)
T.check(not sws.spinning, "(the last spin done)")
press("r")
T.eq(sws.tab, "prizes", "R: the prizes")
draw(60)
local perPrizes = garbageOf(120)
FrlgFont3.drawGlyph = realGlyph3
T.check(perIdle < 0.3 and perSpin < 0.3 and perPrizes < 0.3, ("Slots draws next to no garbage (%.3f idle, %.3f spinning, %.3f prizes KB a frame)"):format(
  perIdle, perSpin, perPrizes))
for i, p in ipairs(Sl.prizes()) do if p.id == 68 and p.kind == "item" then sws.cursor = i end end
local candies2 = Bag.get(s.bag, 68)
press("a")
T.check(Bag.get(s.bag, 68) == candies2 + 1, "A: a Rare Candy redeemed")
do
  local n, dir, id = D.padState()
  T.check(n >= 1 and dir == "in" and id == 68, "it appears on the pad")
end
for _, shape in ipairs({ { 480, 320 }, { 320, 480 }, { 900, 320 } }) do
  VP.width, VP.height = shape[1], shape[2]
  draw(2)
  press("l")
  draw(2)
  T.check(not D.state().winFailed, "Slots draws " .. shape[1] .. "x" .. shape[2])
  press("r")
end
VP.width, VP.height = 480, 320
press("b")
T.check(D.window() == nil, "B closes Slots")
draw(30)
Sl.store, Sl.rng = slotsStore0, slotsRng0

-- ------- the GTS: strangers' Pokémon, the rules, Wonder Trade, deposits, listings (src/gts.lua), its window
do
local Gx = X._test.gts
local BxG = X._test.bx
local gtsSave = { data = {} }
function gtsSave.get(self, k) return self.data[k] end
function gtsSave.set(self, k, v) self.data[k] = v end
local gtsStore0, gtsRng0, gtsNow0 = Gx.store, Gx.rng, Gx.now
Gx.store = gtsSave
local lcg = 12345
Gx.rng = function(n)
  lcg = (lcg * 1103515245 + 12345) % 2147483648
  return lcg % n + 1
end
local gnow = 1800000000
Gx.now = function() return gnow end
local PokeG = require("src.core.game3.pokemon")
local function spOf(nat) return PokeG.speciesFromNational(nat) end
local frlgGame = GAME == "firered" or GAME == "leafgreen"
local gs = newSession()
gs.trainerId, gs.secretId, gs.name = 4321, 8765, "WOS"
gs.dex = { seen = {}, owned = {}, caught = {} }
Party.giveMon(gs, spOf(16), 10)
-- a stranger's Pokémon: theirs, met in a trade
do
  local recv = Gx.make(gs, spOf(63), 20, Gx.STRANGERS[1], 0x0ABC1234)
  T.check(recv and recv.otName == "Yuki" and recv.metLocation == 0xFE and (recv.maxHp or 0) > 0, "a stranger's Abra: their OT, met in a trade")
  T.check(PokeG.isTradedMon(recv, gs), "the game counts it as traded (more EXP; obedience by badges)")
end
-- what may go
ok, why = Gx.canSend(gs, BxG.addr("party", 1))
T.check(not ok and why == "last", "the last Pokémon stays (" .. tostring(why) .. ")")
Party.giveMon(gs, spOf(19), 10)
T.check(Gx.canSend(gs, BxG.addr("party", 2)), "with two, one may go")
do
  local egg = { species = spOf(19), isEgg = true, level = 1, hp = 10 }
  gs.party[3] = egg
  ok, why = Gx.canSend(gs, BxG.addr("party", 3))
  T.check(not ok and why == "egg", "an Egg stays (" .. tostring(why) .. ")")
  gs.party[3] = nil
  local box = Storage.ensure(gs).boxes[1]
  box.mons[1] = { species = spOf(152), level = 5, hp = 10 }
  ok, why = Gx.canSend(gs, BxG.addr("box", 1, 1))
  if frlgGame then
    T.check(not ok and why == "national", "FireRed: Chikorita needs the National Pokédex (" .. tostring(why) .. ")")
  else
    T.check(ok, "Emerald: Chikorita may go")
  end
  box.mons[1] = nil
end
-- Wonder Trade: a party slot, a box cell; again and again, the mix by tier
ok, why = Gx.wonder(gs, BxG.addr("party", 2))
local got = gs.party[2]
T.check(ok and got and PokeG.isTradedMon(got, gs), "Wonder Trade: a stranger's Pokémon in the slot (" .. tostring(why and why.otName) .. ")")
T.check(got.level >= 2 and got.level <= 100 and gs.dex.seen[tonumber(got.species)], "at a level near yours, in the Pokédex")
do
  local box = Storage.ensure(gs).boxes[1]
  local r = Party.giveMon({ party = {}, name = "WOS", trainerId = 4321 }, spOf(16), 12)
  local _, _, mon = Party.giveMon({ party = {}, name = "WOS", trainerId = 4321, dex = { seen = {}, owned = {}, caught = {} } }, spOf(16), 12)
  box.mons[2] = mon
  local okB, recvB = Gx.wonder(gs, BxG.addr("box", 2, 1))
  T.check(okB and box.mons[2] == recvB and recvB ~= mon, "Wonder Trade from a box: the cell holds theirs")
  local _ = r
end
do
  local counts, kanto = {}, true
  for _ = 1, 400 do
    local okW, recv = Gx.wonder(gs, BxG.addr("party", 2))
    if okW then
      local tier = Au.tierOf(tonumber(recv.species)) or "?"
      counts[tier] = (counts[tier] or 0) + 1
      if frlgGame and (PokeG.national(tonumber(recv.species)) or 0) > 151 then kanto = false end
    end
  end
  local legends = (counts.legendary or 0) + (counts.mythical or 0)
  T.check((counts.common or 0) > 100 and legends < 30, ("the mix: %d common, %d legendary or mythical of 400"):format(counts.common or 0, legends))
  T.check(kanto, "without the National Pokédex, FireRed gets only Kanto's 151")
end
-- the GTS: deposit, a fair ask answered, collected; an absurd one never, withdrawn
local pidgey = spOf(16)
local before = #gs.party
ok, why = Gx.deposit(gs, BxG.addr("party", 2), pidgey, 1, gnow)
T.check(ok and #gs.party == before - 1 and Gx.posted() and Gx.posted().matchAt, "deposited, asking for a Pidgey: off the party, a match coming")
ok, why = Gx.deposit(gs, BxG.addr("party", 1), pidgey, 1, gnow)
T.check(not ok and why == "busy", "one at a time")
T.check(not Gx.settle(gs, gnow + 1) and Gx.waiting() == 0, "not yet")
T.check(Gx.settle(gs, Gx.posted().matchAt) and Gx.waiting() == 1, "answered: it waits to be collected")
ok, why = Gx.withdraw(gs)
T.check(not ok and why == "traded", "it can't be withdrawn now")
local okC, recvC = Gx.collect(gs)
T.check(okC and tonumber(recvC.species) == pidgey and PokeG.isTradedMon(recvC, gs) and Gx.waiting() == 0 and not Gx.posted(),
  "collected: a stranger's Pidgey")
local mewtwo = spOf(150)
before = #gs.party
ok = Gx.deposit(gs, BxG.addr("party", #gs.party), mewtwo, 1, gnow)
T.check(ok and Gx.posted().matchAt == false, "asking a Mewtwo for that: nobody answers")
T.check(not Gx.settle(gs, gnow + 10 * 86400), "not even in ten days")
ok = Gx.withdraw(gs)
T.check(ok and #gs.party == before and not Gx.posted(), "withdrawn: it's back")
-- the strangers' listings: the same for the same half hour; answering one
do
  local a = Gx.offers(gs, gnow)
  local keys = {}
  for i, L in ipairs(a) do keys[i] = L.key .. ":" .. tostring(L.sp) .. ":" .. tostring(L.ask) end
  local b = Gx.offers(gs, gnow + 60)
  local same = #a == #b
  for i, L in ipairs(b) do same = same and keys[i] == L.key .. ":" .. tostring(L.sp) .. ":" .. tostring(L.ask) end
  T.check(#a >= 6 and same, "ten listings each half hour, the same within it (" .. #a .. ")")
  -- (one asking for something other than the first in the party: that one is the wrong Pokémon)
  local first = tonumber(gs.party[1].species)
  local L = a[1]
  for _, M in ipairs(a) do if M.ask ~= first then L = M break end end
  local range = Gx.LEVELS[L.levels]
  Party.giveMon(gs, L.ask, math.max(2, range[1]))
  local mineAddr = BxG.addr("party", #gs.party)
  ok, why = Gx.accept(gs, L, BxG.addr("party", 1))
  if first ~= L.ask then T.check(not ok and why == "wrong", "the wrong Pokémon: refused") end
  local list = Gx.offers(gs, gnow + 120)
  local canDo = false
  for _, M in ipairs(list) do if M.key == L.key then canDo = M.canDo end end
  T.check(canDo, "having what it asks: it can be answered")
  ok = Gx.accept(gs, L, mineAddr)
  T.check(ok and tonumber(gs.party[#gs.party].species) == L.sp, "answered: their Pokémon in its place")
  list = Gx.offers(gs, gnow + 180)
  local done = false
  for _, M in ipairs(list) do if M.key == L.key then done = M.done end end
  T.check(done, "and that listing is done")
end
-- a trade evolution: Kadabra
do
  local kad = Gx.make(gs, spOf(64), 30, Gx.STRANGERS[2], 0x0BCD2345)
  T.eq(Gx.evolveTarget(gs, kad), spOf(65), "a Kadabra received evolves (Alakazam)")
end

-- the window: Wonder Trade by buttons, the search, the pad, the reveal; the tabs
Gx.store = gtsSave
gtsSave.data = {}
s.party = {}
Party.giveMon(s, spOf(16), 10)
Party.giveMon(s, spOf(19), 12)
local evolve0 = Gx.evolveTarget
Gx.evolveTarget = function() return nil end
do
  local at
  for i, app in ipairs(st.grid) do if app.id == "gts" then at = i end end
  T.check(at ~= nil, "GTS on the home screen")
  D.launch("grid", at)
end
draw(30)
local GW = D.window()
T.check(GW and GW.title == "GTS", "GTS opens")
local gw = GW.state
T.check(#gw.rows >= 2 and gw.tab == "wonder", "Wonder Trade: your Pokémon to choose from")
press("down")
press("a")
T.check(gw.confirm and gw.confirm.kind == "wonder", "A: send it?")
press("a")
T.check(gw.search and not gw.search.found, "yes: searching the world")
draw(20)
press("a")
draw(2)
T.check(gw.search and gw.search.found, "A skips the search: found")
do
  local n, dir, _, _, kind = D.padState()
  T.check(n >= 1 and kind == "ball", "the Poké Balls cross the pad (" .. tostring(dir) .. ")")
end
for _ = 1, 300 do
  if gw.reveal then break end
  draw(1)
end
T.check(gw.reveal and gw.reveal.mon == s.party[2], "the newcomer revealed, in your party")
press("a")
T.check(not gw.reveal, "A: done")
local FrlgFont4 = require("src.ui.game3.frlg_font")
local realGlyph4 = FrlgFont4.drawGlyph
FrlgFont4.drawGlyph = function() return 7 end
draw(60)
local perWonder = garbageOf(120)
press("start")
T.eq(gw.tab, "browse", "START: the GTS listings")
draw(60)
local perBrowseG = garbageOf(120)
press("start")
T.eq(gw.tab, "deposit", "START: My Deposit")
draw(60)
local perDeposit = garbageOf(120)
FrlgFont4.drawGlyph = realGlyph4
T.check(perWonder < 0.3 and perBrowseG < 0.3 and perDeposit < 0.3,
  ("GTS draws next to no garbage (%.3f, %.3f, %.3f KB a frame)"):format(perWonder, perBrowseG, perDeposit))
for _, shape in ipairs({ { 480, 320 }, { 320, 480 }, { 900, 320 } }) do
  VP.width, VP.height = shape[1], shape[2]
  for _ = 1, 3 do
    draw(2)
    press("start")
  end
  T.check(not D.state().winFailed, "GTS draws " .. shape[1] .. "x" .. shape[2])
end
VP.width, VP.height = 480, 320
press("b")
T.check(D.window() == nil, "B closes the GTS")
draw(30)
Gx.evolveTarget = evolve0
Gx.store, Gx.rng, Gx.now = gtsStore0, gtsRng0, gtsNow0
end

-- ------- the Pokémon model (src/boxes.lua, on the engine's Storage)
local Bx = X._test.bx
-- (the PC's box count: the engine's, raised to 40 by WoobleDex's Bigger PC)
do
  local St = require("src.core.game3.storage")
  local n0 = St.TOTAL_BOXES_COUNT
  T.eq(Bx.BOXES, tonumber(n0) or 14, "the PC's own number of boxes")
  St.TOTAL_BOXES_COUNT = 40
  local bs = { party = {}, storage = St.new() }
  St.ensure(bs)
  T.eq(Bx.BOXES, 40, "WoobleDex's Bigger PC: 40 boxes")
  Bx.setCurrent(bs, 30)
  T.eq(Bx.current(bs), 30, "box 30 can be the current one")
  Bx.setCurrent(bs, 41)
  T.eq(Bx.current(bs), 1, "and past 40 it comes round to 1")
  local addr = Bx.addr("box", 30, 40)
  T.check(addr and addr.boxId == 40 and addr.slot == 30 and Bx.addr("box", 30, 40) == addr, "box 40's places, made once")
  St.TOTAL_BOXES_COUNT = n0
  T.eq(Bx.BOXES, tonumber(n0) or 14, "back to the PC's own")
end
local function newMon(species, hp, extra)
  local m = { species = species, level = 10, hp = hp, maxHp = 30, moves = { 33, 45 }, personality = 1234, otId = 1 }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end
local p1, p2, p3 = newMon(1, 30), newMon(4, 0), newMon(7, 12)
s.party = { p1, p2, p3 }
do
  local b1 = Bx.boxMons(s, 1)
  for i = 1, Bx.SLOTS do b1[i] = nil end
  b1[1], b1[2], b1[7] = newMon(16, 5), newMon(19, 30), newMon(25, 30)
end
local held, why2
held = Bx.take(s, { Bx.addr("party", 3) })
T.check(held and held.n == 1 and #s.party == 2, "take a party Pokémon: the party packs up")
T.check(Bx.place(s, held, Bx.addr("box", 3, 1)), "deposit: into box 1, slot 3")
T.check(Bx.get(s, Bx.addr("box", 3, 1)) == p3 and p3.hp == 30, "there, and healed")
held, why2 = Bx.take(s, { Bx.addr("party", 1) })
T.check(not held and why2 == "last_usable", "the last Pokémon that can battle stays (" .. tostring(why2) .. ")")
held = Bx.take(s, { Bx.addr("box", 2, 1) })
T.check(Bx.place(s, held, Bx.addr("party", 6)) and #s.party == 3, "withdraw: onto the party's end")
do
  local h = Bx.take(s, { Bx.addr("box", 1, 1) })
  local ok, back = Bx.place(s, h, Bx.addr("party", 2))
  T.check(ok and back and back.mons[1] == p2 and s.party[2].species == 16, "a swap: the one there comes to the hand")
  T.check(Bx.place(s, back, Bx.addr("box", 1, 1)) and Bx.get(s, Bx.addr("box", 1, 1)) == p2,
    "and goes down where the first was")
end
do
  s.party[3].heldItem = 121
  local h = Bx.take(s, { Bx.addr("party", 3) })
  local ok, w = Bx.place(s, h, Bx.addr("box", 10, 1))
  T.check(not ok and w == "mail", "a Pokémon holding mail stays out of the boxes")
  Bx.putBack(s, h)
  T.check(#s.party == 3 and s.party[3].heldItem == 121, "put back where it was")
  s.party[3].heldItem = nil
end
-- a group of four keeps its shape
do
  local b2 = Bx.boxMons(s, 2)
  b2[1], b2[2], b2[7], b2[8] = newMon(41, 30), newMon(42, 30), newMon(43, 30), newMon(44, 30)
  local h = Bx.take(s, { Bx.addr("box", 1, 2), Bx.addr("box", 2, 2), Bx.addr("box", 7, 2), Bx.addr("box", 8, 2) })
  T.check(h and h.n == 4 and Bx.count(s, 2) == 0, "a group of four taken")
  local ok, w = Bx.fits(s, h, Bx.addr("box", 6, 3))
  T.check(not ok and w == "no_room", "past the box's edge: no room")
  T.check(Bx.place(s, h, Bx.addr("box", 5, 3)), "into box 3 at the fifth slot")
  local b3 = Bx.boxMons(s, 3)
  T.check(b3[5] and b3[6] and b3[11] and b3[12] and b3[5].species == 41 and b3[12].species == 44,
    "in the same 2 x 2 shape")
end
do
  for i = #s.party + 1, 5 do s.party[i] = newMon(50 + i, 30) end
  local h = Bx.take(s, { Bx.addr("box", 5, 3), Bx.addr("box", 6, 3) })
  local ok, w = Bx.place(s, h, Bx.addr("party", 6))
  T.check(not ok and w == "no_room", "two into a party with one place left: no room")
  Bx.putBack(s, h)
  T.check(Bx.get(s, Bx.addr("box", 5, 3)) ~= nil and Bx.get(s, Bx.addr("box", 6, 3)) ~= nil, "put back in their box")
  for i = 5, 4, -1 do s.party[i] = nil end
end
do
  local b4 = Bx.boxMons(s, 4)
  b4[1], b4[2] = newMon(60, 30, { isEgg = true }), newMon(61, 30)
  local ok, w = Bx.release(s, Bx.addr("box", 1, 4))
  T.check(not ok and w == "egg", "an Egg can't be released")
  T.check(Bx.release(s, Bx.addr("box", 2, 4)) and Bx.count(s, 4) == 1, "Release")
end
do
  Bag.add(s.bag, POTION, 2)
  local m = Bx.get(s, Bx.addr("box", 5, 3))
  T.check(Bx.giveItem(s, m, POTION) and m.heldItem == POTION and Bag.get(s.bag, POTION) == 1, "give a Potion to hold")
  local ok, w = Bx.giveItem(s, m, POTION)
  T.check(not ok and w == "holding", "one item at a time")
  T.check(Bx.takeItem(s, m) and not m.heldItem and Bag.get(s.bag, POTION) == 2, "take it back to the Bag")
  local ok2, w2 = Bx.giveItem(s, m, keyItem)
  T.check(not ok2 and w2 == "cant_hold", "a key item can't be held")
  local info = Bx.info(m, X._test.env.T)
  T.check(info and info.name ~= "" and info.levelText ~= "", "the preview's words (" .. tostring(info and info.name) .. ")")
  T.check(info.dmax == nil and not info.gmax, "no Dynamax row without WoobleDex")
  -- (WoobleDex's exports.dynamax, stood in: kept for the window's draws below, the row and the badge)
  local Dx = { canDynamax = function() return true end, level = function() return 7 end,
               canGigantamax = function(mon) return mon == m end }
  Bx.dynamax = function() return Dx end
  Bx.forget(m)
  info = Bx.info(m, X._test.env.T)
  T.check(info.dmax == 7 and info.gmax == true, "the Dynamax Level and the G-Max Factor in the preview")
  Dx.canDynamax = function(mon) return mon ~= m end
  Bx.forget(m)
  T.check(Bx.info(m, X._test.env.T).dmax == nil, "no row for a Pokémon that can't Dynamax")
  Dx.canDynamax = function() return true end
  Bx.forget(m)
end
Bx.rename(s, 3, "TEAM")
Bx.setWallpaper(s, 3, 5)
T.check(Bx.boxName(s, 3) == "TEAM" and Bx.wallpaper(s, 3) == 5, "rename a box, its wallpaper")
T.check(pcall(Bx.sendBox, s), "the box caught Pokémon go to")

-- ------- the Boxes window: modes, carrying, a group, the pointer, the pad, coming back
Bx.setCurrent(s, 1)
st.focus, st.dockCursor = "dock", 1
D.input(input({}, {}))
press("a")
draw(30)
local BW = D.window()
T.check(BW and BW.title == "Boxes", "Boxes over a session")
-- the pad's Poké Ball: it drops on, its button glows red
do
  local seen = {}
  for _ = 1, 150 do
    draw(1)
    seen[D.ballState()] = true
    if D.ballState() == "on" then break end
  end
  T.check(seen.drop and D.ballState() == "on", "Boxes: the Poké Ball drops onto the pad and stays")
end
local bst = BW.state
T.eq(bst.mode, BW.SELECT, "Select first")
press("select")
T.eq(bst.mode, BW.SWAP, "SELECT: Swap")
press("select")
T.eq(bst.mode, BW.DRAG, "SELECT again: Drag")
press("select")
T.eq(bst.mode, BW.SELECT, "and round to Select")
bst.area, bst.bi = "box", 1
press("a")
T.check(bst.sheet and bst.sheet.kind == "actions", "Select: A on a Pokémon, its options")
draw(2)
press("b")
T.check(bst.sheet == nil and D.window() == BW, "B: closed, the window stays")
-- Swap: pick up, move, put down
press("select")
local moved = Bx.get(s, Bx.addr("box", 1, 1))
press("a")
T.check(bst.held and bst.held.mons[1] == moved, "Swap: A picks it up")
press("right")
press("right")
press("right")
press("a")
T.check(bst.held == nil and Bx.get(s, Bx.addr("box", 4, 1)) == moved, "A puts it down three along")
-- Swap onto another: the two trade places (twice: back as they were)
do
  local k
  for i = 1, Bx.SLOTS do if i ~= 4 and Bx.get(s, Bx.addr("box", i, 1)) then k = i; break end end
  local other = Bx.get(s, Bx.addr("box", k, 1))
  for round = 1, 2 do
    local a, b = round == 1 and 4 or k, round == 1 and k or 4
    bst.area, bst.bi = "box", a
    press("a")
    bst.bi = b
    press("a")
  end
  T.check(bst.held == nil and Bx.get(s, Bx.addr("box", 4, 1)) == moved and Bx.get(s, Bx.addr("box", k, 1)) == other,
    "Swap onto another: they trade places, nothing left in the hand")
  -- a party Pokémon onto a box one: the box one takes its place in the party
  local p2 = s.party[2]
  bst.area, bst.pi = "party", 2
  press("a")
  bst.area, bst.bi = "box", k
  press("a")
  T.check(bst.held == nil and s.party[2] == other and Bx.get(s, Bx.addr("box", k, 1)) == p2,
    "party onto box: the two trade places, the same party slot")
  bst.area, bst.pi = "party", 2
  press("a")
  bst.area, bst.bi = "box", k
  press("a")
  T.check(s.party[2] == p2 and Bx.get(s, Bx.addr("box", k, 1)) == other, "and back")
end
-- carrying across boxes; B puts back
bst.bi = 4
press("a")
press("r")
T.eq(bst.box, 2, "R: the next box, while carrying")
press("b")
T.check(bst.held == nil and Bx.get(s, Bx.addr("box", 4, 1)) == moved, "B: back where it was")
press("l")
-- a party Pokémon into a box: the pad's Poké Ball glows red while it's carried, green once it's down
bst.area, bst.pi = "party", 3
local pm = s.party[3]
draw(1)
T.eq(select(2, D.ballState()), nil, "the pad's Poké Ball: unlit at rest")
press("a")
draw(1)
T.eq(select(2, D.ballState()), "moving", "carrying: the ball glows red")
bst.area, bst.bi = "box", 30
press("a")
draw(1)
T.check(Bx.get(s, Bx.addr("box", 30, 1)) == pm and select(2, D.ballState()) == "moved" and D.padState() == 0,
  "put down: green, and nothing crosses the pad")
-- Drag: hold A over a rectangle, let go, carry the group to another box
press("select")
T.eq(bst.mode, BW.DRAG, "Drag")
do
  local b3 = Bx.boxMons(s, 3)
  local want = Bx.count(s, 3)
  bst.box = 3
  Bx.setCurrent(s, 3)
  bst.area, bst.bi = "box", 5
  D.input(input({ "a" }, { "a" }))
  D.input(input({ "right" }, { "a", "right" }))
  D.input(input({}, { "a" }))
  D.input(input({ "down" }, { "a", "down" }))
  D.input(input({}, { "a" }))
  T.check(bst.rect and bst.rect.b == 12, "held A: a rectangle (" .. tostring(bst.rect and bst.rect.b) .. ")")
  D.input(input({}, {}))
  T.check(bst.held and bst.held.n == 4 and Bx.count(s, 3) == want - 4, "let go: the four in the hand")
  press("l")
  T.eq(bst.box, 2, "L: box 2")
  bst.area, bst.bi = "box", 15
  press("a")
  local b2 = Bx.boxMons(s, 2)
  T.check(bst.held == nil and b2[15] and b2[16] and b2[21] and b2[22], "A: down together, the same shape")
  T.check(b3[5] == nil, "and gone from box 3")
end
-- the pointer: Swap, drag one Pokémon onto an empty cell
press("select")
press("select")
T.eq(bst.mode, BW.SWAP, "Swap again")
draw(1)
do
  local function cellHit(i)
    for _, h in ipairs(st.hit) do if h.kind == "win" and h.arg == BW.A.BOX + i then return h end end
  end
  local from, to = cellHit(15), cellHit(1)
  local m = Bx.get(s, Bx.addr("box", 15, 2))
  local fx, fy, tx, ty = from[1] + from[3] / 2, from[2] + from[4] / 2, to[1] + to[3] / 2, to[2] + to[4] / 2
  D.pointer({ id = 9, phase = "pressed", x = fx, y = fy })
  D.pointer({ id = 9, phase = "moved", x = (fx + tx) / 2, y = (fy + ty) / 2 })
  T.check(bst.held and bst.held.mons[1] == m, "a drag lifts it")
  D.pointer({ id = 9, phase = "moved", x = tx, y = ty })
  draw(1)
  D.pointer({ id = 9, phase = "released", x = tx, y = ty })
  T.check(bst.held == nil and Bx.get(s, Bx.addr("box", 1, 2)) == m, "and drops it where it's let go")
  local chip
  for _, h in ipairs(st.hit) do if h.kind == "win" and h.arg == BW.A.MODE + BW.DRAG then chip = h end end
  D.tap(chip[1] + 1, chip[2] + 1)
  T.eq(bst.mode, BW.DRAG, "a tap on Drag's icon: Drag")
  draw(1)
  for _, h in ipairs(st.hit) do if h.kind == "win" and h.arg == BW.A.MODE + BW.SELECT then chip = h end end
  D.tap(chip[1] + 1, chip[2] + 1)
  T.eq(bst.mode, BW.SELECT, "a tap on the pill: on to the next mode (Select)")
end
-- the window's draw makes next to no garbage, warm, with the preview showing
bst.area, bst.bi = "box", 1
for _, shape in ipairs({ { 480, 320 }, { 320, 480 }, { 900, 320 } }) do
  VP.width, VP.height = shape[1], shape[2]
  draw(2)
  T.check(not D.state().winFailed, "the Boxes window draws " .. shape[1] .. "x" .. shape[2])
end
VP.width, VP.height = 480, 320
draw(120)
local perB = garbageOf(120)
T.check(perB < 0.3, ("the Boxes window draws next to no garbage (%.3f KB a frame)"):format(perB))
-- WoobleDex's Bigger PC: R goes on past box 14 to 15 ... 40, then round to 1
do
  local St = require("src.core.game3.storage")
  local n0 = St.TOTAL_BOXES_COUNT
  St.TOTAL_BOXES_COUNT = 40
  St.ensure(s)
  local b0 = bst.box
  bst.box = 14
  Bx.setCurrent(s, 14)
  press("r")
  T.eq(bst.box, 15, "Bigger PC: R from box 14 to box 15")
  draw(2)
  T.check(not D.state().winFailed, "and box 15 draws")
  for _ = 1, 25 do press("r") end
  T.eq(bst.box, 40, "on to box 40")
  press("r")
  T.eq(bst.box, 1, "then box 1 again")
  St.TOTAL_BOXES_COUNT = n0
  bst.box = b0
  Bx.setCurrent(s, b0)
  draw(2)
end
-- one of the game's screens over it (the summary, naming): the window back as it was
bst.mode, bst.box = BW.SWAP, 2
st.ctx.over(function(done) done() end, { mode = BW.SWAP, area = "box", pi = 1, bi = 1, box = 2 })
st = D.state()
draw(1)
local BW2 = D.window()
T.check(BW2 and BW2.title == "Boxes" and BW2 ~= BW, "back from the game's screen: the Boxes window again")
T.check(BW2.state.mode == BW.SWAP and BW2.state.box == 2 and BW2.state.bi == 1, "as it was (mode, box, cursor)")
draw(70)
T.eq(D.ballState(), "on", "and the Poké Ball already on the pad (no second drop)")
-- closing never leaves a Pokémon in the hand
D.input(input({}, {}))
press("a")
T.check(BW2.state.held ~= nil, "(one picked up)")
local heldMon = BW2.state.held.mons[1]
press("b")
press("b")
T.check(D.window() == nil, "B, B: closed")
local found = false
for b = 1, Bx.BOXES do for i = 1, Bx.SLOTS do if Bx.get(s, Bx.addr("box", i, b)) == heldMon then found = true end end end
T.check(found, "and the Pokémon it held is back in a box")
do
  local seen = {}
  for _ = 1, 150 do
    draw(1)
    seen[D.ballState()] = true
    if D.ballState() == "off" then break end
  end
  T.check(seen.done and seen.lift and D.ballState() == "off", "closed: the button flashes green, the ball lifts off")
end
draw(30)
st.ctx.logoff()
openPc({ startMode = "select" })
st = D.state()
D.skipBoot()
draw(30)

-- ------- the words (lang/*.lua through src/i18n.lua)
local I18n, Set, Wall = X._test.i18n, X._test.settings, X._test.wall
local MOD = "mods/woob_os/"
local function readFile(path)
  local f = io.open(MOD .. path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
local en = I18n.raw("en")
T.check(en and en["app.items"] == "Items", "English loads (lang/en.lua)")
-- every key the code names is in English
local missing, named = {}, 0
local NOT_WORDS = { ["game.ready"] = true }   -- (an engine event's name)
local PREFIX = { hint = 1, menu = 1, logoff = 1, button = 1, about = 1, nav = 1, game = 1, app = 1, items = 1,
                 pocket = 1, reason = 1, mail = 1, settings = 1, wall = 1, failed = 1, mart = 1, auction = 1, slots = 1, gts = 1 }
for _, file in ipairs({ "main.lua", "src/desktop.lua", "src/apps.lua", "src/apps/items.lua", "src/apps/mail.lua",
                        "src/apps/settings.lua", "src/apps/mart.lua", "src/mart.lua",
                        "src/apps/auction.lua", "src/auction.lua",
                        "src/apps/slots.lua", "src/slots.lua",
                        "src/apps/gts.lua", "src/gts.lua" }) do
  local src = readFile(file) or ""
  for key in src:gmatch('"([%a][%w_]*%.[%w_%.]+)"') do
    if PREFIX[key:match("^(%a+)")] and not key:match("%.$") and not key:match("%.lua$") and not NOT_WORDS[key] then
      named = named + 1
      if not en[key] then missing[#missing + 1] = key end
    end
  end
end
-- (and the keys made from codes)
for _, k in ipairs({ "bag_full", "pc_full", "stack_full", "important", "gone" }) do
  if not en["reason.item." .. k] then missing[#missing + 1] = "reason.item." .. k end
end
for _, k in ipairs({ "bag_full", "holding", "box_full", "gone" }) do
  if not en["reason.mail." .. k] then missing[#missing + 1] = "reason.mail." .. k end
end
for _, k in ipairs({ "last", "egg", "national", "mail", "invalid", "gone", "busy", "traded", "no_room", "wrong" }) do
  if not en["reason.gts." .. k] then missing[#missing + 1] = "reason.gts." .. k end
end
for _, k in ipairs({ "kanto", "johto", "hoenn", "sinnoh", "unova", "kalos", "alola", "galar", "paldea" }) do
  if not en["gts.region." .. k] then missing[#missing + 1] = "gts.region." .. k end
end
for _, k in ipairs({ "money", "tickets", "bag_full", "no_room" }) do
  if not en["reason.slots." .. k] then missing[#missing + 1] = "reason.slots." .. k end
end
for _, k in ipairs({ "too_low", "money", "ended" }) do
  if not en["reason.auction." .. k] then missing[#missing + 1] = "reason.auction." .. k end
end
for _, k in ipairs({ "common", "uncommon", "rare", "prized", "legendary", "mythical" }) do
  if not en["auction.tier." .. k] then missing[#missing + 1] = "auction.tier." .. k end
end
for _, k in ipairs({ "badges", "money", "bag_full", "cant_sell", "gone" }) do
  if not en["reason.mart." .. k] then missing[#missing + 1] = "reason.mart." .. k end
end
for _, k in ipairs({ "ITEMS", "KEY_ITEMS", "POKE_BALLS", "TM_CASE", "BERRY_POUCH" }) do
  if not en["pocket." .. k] then missing[#missing + 1] = "pocket." .. k end
end
for _, k in ipairs({ "firered", "leafgreen", "ruby", "sapphire", "emerald" }) do
  if not en["game." .. k] then missing[#missing + 1] = "game." .. k end
end
for _, k in ipairs(Wall.BUILTIN) do
  if not en["wall." .. k] then missing[#missing + 1] = "wall." .. k end
end
T.check(named > 60 and #missing == 0, "every key the code names is in English (" .. named .. " named; missing: "
  .. table.concat(missing, ", ") .. ")")
-- the shipped languages: each loads, has a name, every key, and the same %s as English
local langs = I18n.languages()
T.eq(#langs, 7, "seven languages (" .. #langs .. ")")
T.eq(langs[1].code, "en", "English first")
for _, l in ipairs(langs) do
  local words = I18n.raw(l.code)
  local gaps, bad = 0, {}
  for k, v in pairs(en) do
    local w = words[k]
    if not w then gaps = gaps + 1
    else
      local _, a = v:gsub("%%s", "")
      local _, b = w:gsub("%%s", "")
      if a ~= b then bad[#bad + 1] = k end
    end
  end
  T.check(l.name ~= l.code and gaps == 0 and #bad == 0, l.code .. ": " .. l.name .. ", every word, the same %s ("
    .. gaps .. " missing" .. (#bad > 0 and ("; %s off: " .. table.concat(bad, ", ")) or "") .. ")")
end
-- a missing word: English; an unknown key: itself; a file with code in it can't reach anything
do
  local makeI18n = dofile(MOD .. "src/i18n.lua")
  local files = {
    ["lang/en.lua"] = 'return { name = "English", strings = { ["hint.open"] = "Open", ["hint.back"] = "Back" } }',
    ["lang/xx.lua"] = 'return { name = "Test", strings = { ["hint.open"] = "Ouvre" } }',
    ["lang/yy.lua"] = 'return { name = tostring(os.time()), strings = {} }',
  }
  local logged = 0
  local t2 = makeI18n({ read = function(p) return files[p] end,
                        list = function() return { "en.lua", "xx.lua", "yy.lua" } end,
                        log = function() logged = logged + 1 end })
  T.check(t2.set("xx") and t2("hint.open") == "Ouvre" and t2("hint.back") == "Back", "a missing word falls back to English")
  T.eq(t2("no.such.key"), "no.such.key", "an unknown key shows itself")
  T.check(not t2.set("yy") and logged == 1, "a language file that reaches for anything is skipped")
end
-- switching: labels and hints follow, then back
local storageApp = Apps.byId("storage")
T.check(I18n.set("fr") and D.labelOf(storageApp) == "Boîtes", "French: Boxes is Boîtes")
T.eq(I18n.list(D.TEXT.hints.grid)[1][2], "Ouvrir", "and the hints follow")
I18n.set("en")
T.eq(D.labelOf(storageApp), "Boxes", "English again")

-- ------- the kept settings (a stand-in for mod.cache)
local function fakeCache()
  local store = {}
  return { store = store, read = function(_, k) return store[k] end,
           write = function(_, k, v) store[k] = v return true end }
end
local cacheA = fakeCache()
Set.cache = cacheA
Set.set("wallpaper", "hills")
T.eq(Set.get("wallpaper"), "hills", "a setting kept")
T.check(type(cacheA.store["settings.lua"]) == "string", "and written")
local Set2 = dofile(MOD .. "src/settings.lua")({ cache = cacheA, loadData = I18n.loadData })
T.eq(Set2.get("wallpaper"), "hills", "and read back")
Set.set("wallpaper", "classic")
T.eq(Wall.choices()[1].id, "classic", "the wallpapers: Classic first")
T.eq(#Wall.choices(), 6, "then the five drawn ones (no pictures in wallpapers/)")
T.check(not Wall.draw("ribbon", 0, 0, 100, 60, 3), "headless (no canvases): the classic colours instead")

-- ------- arranging the desktop (kept in the stand-in cache)
do
  local Ar = X._test.arrange
  local A1 = { { id = "a", dock = true }, { id = "b" }, { id = "c", dock = true }, { id = "d" } }
  local g, d = Ar.place(A1, nil, nil)
  T.eq(ids(d) .. " | " .. ids(g), "a c | b d", "no arrangement: each app where it says")
  g, d = Ar.place(A1, "b,zz", "c,a")
  T.eq(ids(d) .. " | " .. ids(g), "b | c a d", "an arrangement: the named apps in order, the rest after")
  local dt, gt = Ar.encode(d, g, "b,zz", "c,a,yy")
  T.eq(dt .. " | " .. gt, "b,zz | c,a,d,yy", "kept: apps this PC doesn't show keep their place")
  local full = {}
  for i = 1, 8 do full[i] = { id = "x" .. i, dock = true } end
  g, d = Ar.place(full, nil, nil)
  T.eq(#d .. " " .. #g, Ar.DOCK_MAX .. " " .. (8 - Ar.DOCK_MAX), "a full dock: the rest on the home screen")
end
local function reopen()
  st.ctx.logoff()
  openPc({ startMode = "select" })
  st = D.state()
  D.skipBoot()
  draw(30)
  D.input(input({}, {}))
end
reopen()
T.check(D.isOpen() and not D.window() and #st.grid > 0, "(the home screen)")
-- the buttons: SELECT, A picks the first app up, Down into the dock, A puts it there
local firstApp = st.grid[1]
st.focus, st.cursor = "grid", 1
D.setPage(1)
press("select")
T.check(D.arranging(), "SELECT: arranging")
press("a")
T.check(st.carry and st.carry.app == firstApp and not st.carry.ptr, "A picks the app up")
for _ = 1, 5 do if st.carry.list ~= "dock" then press("down") end end
T.eq(st.carry.list, "dock", "Down off the grid's foot: into the dock")
T.eq(st.dock[#st.dock], firstApp, "at its end")
press("left")
T.eq(st.dock[#st.dock - 1], firstApp, "Left: along the dock")
press("a")
T.check(st.carry == nil and D.arranging(), "A puts it down, still arranging")
T.check((Set.get("dockApps") or ""):find(firstApp.id, 1, true) ~= nil, "the dock's arrangement kept")
press("b")
T.check(not D.arranging(), "B: done")
reopen()
T.eq(st.dock[#st.dock - 1], firstApp, "the next PC keeps it")
-- the pointer: a long press on it in the dock, dragged to the home screen's first place
local function hitOf(kind, arg)
  for _, h in ipairs(st.hit) do if h.kind == kind and h.arg == arg then return h end end
end
draw(2)
local dh = hitOf("dock", #st.dock - 1)
local hx, hy = dh[1] + dh[3] / 2, dh[2] + dh[4] / 2
D.pointer({ id = 3, phase = "pressed", x = hx, y = hy })
draw(10)
T.check(not D.arranging(), "a short hold: nothing yet")
draw(30)
T.check(D.arranging() and st.carry and st.carry.app == firstApp and st.carry.ptr, "a long press: arranging, the app in hand")
local g1 = hitOf("grid", 1)
local gx, gy = g1[1] + g1[3] / 2, g1[2] + g1[4] / 2
D.pointer({ id = 3, phase = "moved", x = (hx + gx) / 2, y = (hy + gy) / 2 })
D.pointer({ id = 3, phase = "moved", x = gx, y = gy })
draw(1)
T.eq(st.grid[1], firstApp, "dragged onto the home screen's first place")
D.pointer({ id = 3, phase = "released", x = gx, y = gy })
T.check(st.carry == nil and D.arranging(), "let go: put down, still arranging")
T.eq((Set.get("homeApps") or ""):match("^[^,]+"), firstApp.id, "the home screen's arrangement kept")
-- the draw while arranging makes next to no garbage
draw(60)
local perA = garbageOf(120)
T.check(perA < 0.3, ("arranging draws next to no garbage (%.3f KB a frame)"):format(perA))
D.tap(2, 2)
T.check(not D.arranging(), "a tap on nothing: done")
-- (the defaults again)
Set.set("dockApps", nil)
Set.set("homeApps", nil)
reopen()
T.eq(st.dock[1] and st.dock[1].id, "storage", "no arrangement kept: Boxes first in the dock again")

-- ------- the Settings window: choose French, a wallpaper, back
for i, app in ipairs(st.grid) do if app.id == "settings" then st.focus, st.cursor = "grid", i end end
D.input(input({}, {}))
press("a")
draw(30)
local SW = D.window()
T.check(SW and SW.title == "Settings", "Settings opens its window")
press("a")
T.eq(SW.state.focus, "detail", "A: Language")
for _ = 1, 3 do press("down") end
T.eq(SW.state.langs[SW.state.langCursor].code, "fr", "Down to Français")
press("a")
T.check(I18n.code() == "fr" and Set.get("language") == "fr", "A: French, kept")
T.eq(D.labelOf(storageApp), "Boîtes", "the desktop's words follow")
press("b")
press("down")
press("a")
T.eq(SW.state.section, 2, "Wallpaper")
press("right")
press("a")
T.eq(Set.get("wallpaper"), "ribbon", "A on Ribbon: chosen")
-- a picture: Fill (cover, cropped from the centre) or Stretch (all of it, to the screen's shape)
do
  local px, py, sx, sy = Wall.place(200, 100, 100, 100, "fill")
  T.check(px == -50 and py == 0 and sx == 1 and sy == 1, "Fill: one scale, cropped from the centre")
  px, py, sx, sy = Wall.place(200, 100, 100, 100, "stretch")
  T.check(px == 0 and py == 0 and sx == 0.5 and sy == 1, "Stretch: each side to the screen's")
end
X._test.env.setWallpaper("user:picture.png")
T.eq(SW.hints()[2][1], "SELECT", "a picture: SELECT in the hints")
press("select")
T.eq(Set.get("wallpaperFit"), "stretch", "SELECT: Stretch")
draw(2)
T.check(not D.state().winFailed, "the Fill | Stretch switch draws")
press("select")
T.eq(Set.get("wallpaperFit"), "fill", "SELECT again: Fill")
X._test.env.setWallpaper("ribbon")
press("select")
T.eq(Set.get("wallpaperFit"), "fill", "a drawn wallpaper: SELECT does nothing")
for _, shape in ipairs({ { 480, 320 }, { 320, 480 } }) do
  VP.width, VP.height = shape[1], shape[2]
  draw(2)
  T.check(not D.state().winFailed, "the Settings window draws " .. shape[1] .. "x" .. shape[2])
end
VP.width, VP.height = 480, 320
-- (warm: the shapes above made new font sizes and wallpaper keys)
draw(120)
local perS = garbageOf(120)
T.check(perS < 0.3, ("the Settings window draws next to no garbage (%.3f KB a frame)"):format(perS))
press("b")
press("b")
T.check(D.window() == nil, "B, B: closed")
X._test.env.setLanguage("en")
X._test.env.setWallpaper("classic")
T.check(I18n.code() == "en" and Set.get("wallpaper") == "classic", "(back to English and Classic)")
draw(30)

-- ------- garbage: the draw, warm
draw(120)
local per = garbageOf(300)
T.check(per < 0.2, ("the draw makes next to no garbage (%.3f KB a frame)"):format(per))

st.ctx.logoff()
run.release()
T.finish("woob_os desktop (" .. GAME .. ")")
