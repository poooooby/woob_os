-- Standalone: luajit mods/wooble_os/tests/desktop_test.lua [game] (from the gen1recomp root; needs
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

local run = T.sdk.loadMods({ "mods/wooble_os" }, { data = {}, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.events:emit("game.ready", {})
local X = run.loader.exports.wooble_os
local D, Sh, Apps = X._test.desktop, X._test.shell, X._test.apps
local PcMenu = require("src.ui.game3.pc_menu")
local Stack = require("src.ui.game3.stack")
T.check(rawget(PcMenu, "__woobleOs") ~= nil, "the PC menu is wrapped")

local VP = { width = 480, height = 320 }
local function draw(n, step)
  for _ = 1, n or 1 do
    clock = clock + (step or 1 / 60)
    D.draw(G, VP)
  end
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
T.eq(ids(Apps.list(ctxWith("select", rowsAll))), "storage items oak hall about logoff",
  "a cleared game's PC: every app")
T.eq(ids(Apps.list(ctxWith("select", { { id = "storage" }, { id = "player" }, { id = "quit" } }))),
  "storage items about logoff", "early on: no Oak's PC, no Hall of Fame")
T.eq(ids(Apps.list(ctxWith("bedroom"))), "items about logoff", "the bedroom PC: Items only")
T.check(not Apps.register({ id = "storage", open = noop }), "an id can't be taken twice")
T.check(not Apps.register({ id = "x" }), "an app needs open()")

-- ------- the Pokémon Center PC

openPc({ startMode = "select" })
T.check(D.isOpen() and Stack.has("wooble_os"), "the PC menu opens the desktop, on the UI stack")
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

-- Boxes: zooms up, then the script gets the storage row
st.focus, st.dockCursor = "dock", 1
press("a")
T.check(st.zoom ~= nil, "Boxes zooms up from its icon")
draw(30)
T.check(not D.isOpen() and not Stack.has("wooble_os"), "then the desktop closes")
T.eq(last(), st.ctx.row("storage"), "and the script gets the storage row (" .. tostring(last()) .. ")")

-- back to the PC menu (the script comes back after the storage system): no boot, Boxes zooms back
openPc({ startMode = "select" })
st = D.state()
T.check(D.isOpen() and not D.booting(), "the PC menu again: the desktop, without the boot")
T.check(st.zoom and st.zoom.back and st.zoom.id == "storage", "Boxes zooms back into its icon")
draw(30)
-- Items: the player row
st.focus, st.dockCursor = "dock", 2
D.input(input({}, {}))
press("a")
draw(30)
T.eq(last(), st.ctx.row("player"), "Items hands the script the player's PC row (" .. tostring(last()) .. ")")

-- log off: B asks, A logs off -> 127
openPc({ startMode = "select" })
st = D.state()
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
T.eq(#st.grid + #st.dock, 3, "with Items, About and Log Off")
D.skipBoot()
draw(40)
st.focus, st.dockCursor = "dock", 1
D.input(input({}, {}))
press("a")
draw(30)
T.check(not D.isOpen() and PcMenu.isOpen(), "Items opens the game's player's PC")
PcMenu.close()
T.check(D.isOpen() and Stack.has("wooble_os"), "and closing it comes back to the desktop")
T.check(not D.booting(), "without the boot")
st = D.state()
draw(30)
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

-- ------- garbage: the draw, warm
draw(120)
collectgarbage("collect")
collectgarbage("stop")
local kb0 = collectgarbage("count")
draw(300)
local per = (collectgarbage("count") - kb0) / 300
collectgarbage("restart")
T.check(per < 0.2, ("the draw makes next to no garbage (%.3f KB a frame)"):format(per))

st.ctx.logoff()
run.release()
T.finish("wooble_os desktop (" .. GAME .. ")")
