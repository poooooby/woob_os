-- Driver: the desktop in the engine. A new game, a Pokémon Center: A on the PC boots the desktop
-- (shots through the boot); Boxes runs the game's own storage menu and the PC menu comes back as the
-- desktop without the boot; Items runs the game's player's PC and back; B then A logs off and the
-- player walks again. Then the mouse alone (a dock icon, the power button, Log Off), the bedroom
-- PC's desktop, window shapes, and the garbage its draw makes. Shots d*.png.
--   SHOT_DIR=<dir> POKEPORT_GAME=firered POKEPORT_VERSION=firered \
--   POKEPORT_DRIVER=mods/wooble_os/tests/drivers/desktop_probe.lua love .

local CENTER = { frlg = "VIRIDIAN_CITY_POKEMON_CENTER_1F", rse = "OLDALE_TOWN_POKEMON_CENTER_1F" }

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/wos"
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "WOS", gender = 0 })
  U.wait(90)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Field = require("src.core.game3.field")
  local Stack = require("src.ui.game3.stack")
  local Profile = require("src.core.game3.profile")
  local Collision = require("src.core.game3.collision")
  local I = require("src.core.game3.scripting.interaction_scripts")
  local PcMenu = require("src.ui.game3.pc_menu")
  local s0 = Runtime.getSession()
  s0.money = 12345
  local X = game.mods.exports.wooble_os
  local D = X and X._test and X._test.desktop
  if not D then log("FAIL wooble_os has no _test.desktop"); return end
  local Sh = X._test.shell
  local gid = Sh.gameId()
  local family = (gid == "firered" or gid == "leafgreen") and "frlg" or "rse"

  -- the Pokémon Center, in front of its PC
  local prefix = Profile.forSession(s0).map.enginePrefix
  local center = prefix .. CENTER[family]
  Warp.request(nil, game, center, 7, 8, "up", {})
  check(waitFor(function() return Map.current == center and not Warp.isBusy() end, 1200), "warped to " .. center)
  U.wait(30)
  local pcKey = I.scriptFor(0x83, "up", true)
  local px, py
  for y = 0, 20 do
    for x = 0, 30 do
      if not px and I.scriptFor(Collision.behavior(x, y), "up", true) == pcKey and pcKey then px, py = x, y end
    end
  end
  check(px ~= nil, "the PC's tile (" .. tostring(px) .. "," .. tostring(py) .. ")")
  if not px then return end
  local function toPc()
    Warp.request(nil, game, center, px, py + 1, "up", {})
    waitFor(function() return Map.current == center and not Warp.isBusy() end, 600)
    U.wait(20)
  end
  local function pcOn()
    toPc()
    U.tap(game, "a")
    -- (the game's turn-on message, then its PC menu: the desktop)
    for _ = 1, 8 do
      if D.isOpen() then break end
      U.wait(30)
      if not D.isOpen() then U.tap(game, "a") end
    end
    return waitFor(function() return D.isOpen() end, 240)
  end
  check(pcOn(), "A on the PC: the desktop")
  for i, at in ipairs({ 0.2, 0.7, 1.3, 1.85 }) do
    waitFor(function() return D.state() and (love.timer.getTime() - D.state().t0) >= at end, 240)
    shot("d0" .. i .. "_boot")
  end
  check(waitFor(function() return not D.booting() end, 240), "the boot runs out")
  U.wait(40)
  shot("d1_desktop")
  local st = D.state()
  check(Stack.has("wooble_os") and Field.isLocked and Field.isLocked(), "on the UI stack, the field held")

  -- the draw's garbage, measured around each call
  local draw, drawKb, draws = D.draw, 0, 0
  D.draw = function(...)
    local was = collectgarbage("isrunning")
    collectgarbage("stop")
    local kb0 = collectgarbage("count")
    draw(...)
    drawKb, draws = drawKb + (collectgarbage("count") - kb0), draws + 1
    if was then collectgarbage("restart") end
  end
  U.wait(120)
  D.draw = draw
  local perFrame = drawKb / math.max(1, draws)
  log(("  the desktop's draw: %.3f KB per frame over %d frames"):format(perFrame, draws))
  check(perFrame < 0.5, "the draw makes next to no garbage")

  -- Boxes (the dock's first): the game's storage menu, then the PC menu = the desktop, warm
  check(st.dock[1] and st.dock[1].id == "storage", "Boxes in the dock")
  U.tap(game, "down"); U.wait(4)
  check(st.focus == "dock", "Down: the dock")
  U.tap(game, "a"); U.wait(30)
  check(not D.isOpen(), "A on Boxes: the desktop gives way")
  local storageMenu = waitFor(function()
    if PcMenu.isOpen() and PcMenu.mode == "storage_menu" then return true end
    if not D.isOpen() then U.tap(game, "a") end
    U.wait(10)
    return false
  end, 60)
  check(storageMenu, "the game's storage menu (" .. tostring(PcMenu.mode) .. ")")
  shot("d2_storage")
  -- B / SEE YA out: the script goes back to its PC menu - the desktop, no boot
  local back = waitFor(function()
    if D.isOpen() then return true end
    U.tap(game, "b")
    U.wait(15)
    return D.isOpen()
  end, 40)
  check(back, "out of the storage menu: the desktop again")
  check(not D.booting(), "without the boot")
  U.wait(6)
  shot("d3_zoom_back")
  U.wait(30)
  st = D.state()

  -- Items: the game's player's PC, then back
  st.focus, st.dockCursor = "dock", 2
  U.tap(game, "a"); U.wait(30)
  local playerMenu = waitFor(function()
    if PcMenu.isOpen() and (PcMenu.mode == "player_pc" or PcMenu.mode == "item_storage") then return true end
    if not D.isOpen() then U.tap(game, "a") end
    U.wait(10)
    return false
  end, 60)
  check(playerMenu, "Items: the game's player's PC (" .. tostring(PcMenu.mode) .. ")")
  shot("d4_items")
  back = waitFor(function()
    if D.isOpen() then return true end
    U.tap(game, "b")
    U.wait(15)
    return D.isOpen()
  end, 40)
  check(back, "out of it: the desktop again")
  U.wait(30)
  st = D.state()

  -- B, then A: logged off, the player walks again
  U.tap(game, "b"); U.wait(10)
  shot("d5_logoff_sheet")
  U.tap(game, "a")
  check(waitFor(function() return not D.isOpen() end, 60), "logged off")
  check(waitFor(function() return not (Field.isLocked and Field.isLocked()) end, 300), "the field free again")
  local y0 = Player.cellY
  U.hold(game, "down", 16); U.wait(20)
  check(Player.cellY == y0 + 1, "the player walks again (" .. tostring(y0) .. " -> " .. tostring(Player.cellY) .. ")")

  -- the mouse alone: a dock icon (Items) and back, the power button, Log Off
  check(pcOn(), "the PC again: the desktop")
  D.skipBoot()
  U.wait(40)
  st = D.state()
  local function click(kind, arg)
    for _, h in ipairs(st.hit) do
      if h.kind == kind and (arg == nil or h.arg == arg) then
        local x, y = h[1] + h[3] / 2, h[2] + h[4] / 2
        game:mousepressed(x, y, 1, false)
        U.wait(2)
        game:mousereleased(x, y, 1, false)
        U.wait(6)
        return true
      end
    end
    log("  no " .. kind .. " to click")
    return false
  end
  click("wmenu")
  check(st.menuOpen, "a click on the W: its menu")
  shot("d6_wmenu")
  click("menuRow", 1)
  check(st.sheet == "about", "About WoobleOS")
  shot("d7_about")
  click("ok")
  click("power")
  check(st.sheet == "logoff", "the power button asks")
  click("yes")
  check(waitFor(function() return not D.isOpen() end, 60), "Log Off clicked: logged off")
  waitFor(function() return not (Field.isLocked and Field.isLocked()) end, 300)

  -- the bedroom PC (its script opens the game's menu as player_pc + bedroom)
  local closed = false
  PcMenu.show({ session = s0, startMode = "player_pc", bedroom = true, closeOnExit = true,
                onClose = function() closed = true end })
  check(D.isOpen() and D.state().ctx.mode == "bedroom", "the bedroom PC: the desktop")
  D.skipBoot()
  U.wait(40)
  shot("d8_bedroom")
  D.state().ctx.logoff()
  check(closed and not D.isOpen(), "the bedroom PC logs off")

  -- window shapes
  check(pcOn(), "the PC again")
  D.skipBoot()
  U.wait(30)
  local W0, H0, flags = love.window.getMode()
  for _, shape in ipairs({ { "w16x9", 1280, 720 }, { "portrait", 430, 900 }, { "w21x9", 1680, 720 },
                          { "w4x3", 1024, 768 }, { "small", 640, 480 } }) do
    love.window.setMode(shape[2], shape[3], flags)
    if love.resize then pcall(love.resize, shape[2], shape[3]) end
    U.wait(20)
    st = D.state()
    local L = st.layout or {}
    log(("  %s: %s, page %.0f x %.0f, grid %d x %d"):format(shape[1], L.portrait and "portrait" or "landscape",
      L.pw or 0, L.ph or 0, L.cols or 0, L.rows or 0))
    shot("d9_" .. shape[1])
  end
  love.window.setMode(W0, H0, flags)
  if love.resize then pcall(love.resize, W0, H0) end
  U.wait(10)
  D.state().ctx.logoff()
  waitFor(function() return not D.isOpen() end, 60)
  log(("%d failures"):format(fails))
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/wos"
  local logFile = io.open(dir .. "/driver.log", "w")
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    print("[driver]", line)
    if logFile then logFile:write(line, "\n"); logFile:flush() end
  end
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  log("DONE")
  if logFile then logFile:close() end
  love.event.quit()
end
