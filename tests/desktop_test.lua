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
T.eq(ids(Apps.list(ctxWith("select", rowsAll))), "storage items mail oak hall settings about logoff",
  "a cleared game's PC: every app")
T.eq(ids(Apps.list(ctxWith("select", { { id = "storage" }, { id = "player" }, { id = "quit" } }))),
  "storage items mail settings about logoff", "early on: no Oak's PC, no Hall of Fame")
T.eq(ids(Apps.list(ctxWith("bedroom"))), "items mail settings about logoff", "the bedroom PC: Items, Mail, Settings")
do
  local c = ctxWith("bedroom")
  c.family = "rse"
  T.eq(ids(Apps.list(c)), "items mail decorate settings about logoff", "Ruby / Sapphire / Emerald's bedroom: Decorate too")
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
T.eq(st.sheet, "logoff", "its second row: Log Off")
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
T.eq(#st.grid + #st.dock, rse and 6 or 5, "with Items, Mail, Settings, About and Log Off" .. (rse and ", Decorate" or ""))
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
T.eq(IW.state.step.qty, 4, "Down: one fewer")
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

-- ------- the Pokémon model (src/boxes.lua, on the engine's Storage)
local Bx = X._test.bx
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
-- carrying across boxes; B puts back
bst.bi = 4
press("a")
press("r")
T.eq(bst.box, 2, "R: the next box, while carrying")
press("b")
T.check(bst.held == nil and Bx.get(s, Bx.addr("box", 4, 1)) == moved, "B: back where it was")
press("l")
-- a party Pokémon into a box: a Poké Ball crosses the pad
bst.area, bst.pi = "party", 3
local pm = s.party[3]
press("a")
bst.area, bst.bi = "box", 30
press("a")
do
  local n, dir, _, _, kind = D.padState()
  T.check(Bx.get(s, Bx.addr("box", 30, 1)) == pm and n > 0 and dir == "out" and kind == "ball",
    "party to box: a Poké Ball goes out across the pad")
end
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
                 pocket = 1, reason = 1, mail = 1, settings = 1, wall = 1, failed = 1 }
for _, file in ipairs({ "main.lua", "src/desktop.lua", "src/apps.lua", "src/apps/items.lua", "src/apps/mail.lua",
                        "src/apps/settings.lua" }) do
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
