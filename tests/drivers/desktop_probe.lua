-- Driver: the desktop in the engine. A new game, a Pokémon Center: one A on the PC boots the desktop
-- with no text box on the way (shots through the boot); Boxes runs the game's own storage menu and the PC menu comes back as the
-- desktop without the boot; Items runs the game's player's PC and back; B then A logs off and the
-- player walks again. Then the mouse alone (a dock icon, the power button, Log Off), the bedroom
-- PC's desktop, window shapes, and the garbage its draw makes. Shots d*.png.
--   SHOT_DIR=<dir> POKEPORT_GAME=firered POKEPORT_VERSION=firered \
--   POKEPORT_DRIVER=mods/woob_os/tests/drivers/desktop_probe.lua love .

local CENTER = { frlg = "VIRIDIAN_CITY_POKEMON_CENTER_1F", rse = "OLDALE_TOWN_POKEMON_CENTER_1F" }

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/wos"
  -- (the limit in frames, and at least as long on the wall clock at 60 a second: the frames can
  -- run far faster than that, and the effects waited on keep the wall clock's time)
  local function waitFor(pred, limit)
    limit = limit or 600
    local untilT = love.timer.getTime() + limit / 60
    local n = 0
    while n < limit or love.timer.getTime() < untilT do
      if pred() then return true end
      U.wait(1)
      n = n + 1
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
  local X = game.mods.exports.woob_os
  local D = X and X._test and X._test.desktop
  if not D then log("FAIL woob_os has no _test.desktop"); return end
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
  local Message = require("src.ui.game3.message")
  -- one A: no "booted up the PC" / "Which PC should be accessed?" on the way (no box, no more A)
  local function pcOn()
    toPc()
    U.tap(game, "a")
    local boxed = false
    local open = waitFor(function()
      if Message.isOpen() then boxed = true end
      return D.isOpen()
    end, 240)
    check(not boxed, "no text box before the desktop")
    return open
  end
  check(pcOn(), "A on the PC: the desktop")
  -- (black to 0.25, the bar full by about 1.05, the reveal from 1.35)
  for i, at in ipairs({ 0.15, 0.6, 1.25, 1.55 }) do
    waitFor(function() return D.state() and (love.timer.getTime() - D.state().t0) >= at end, 240)
    shot("d0" .. i .. "_boot")
  end
  check(waitFor(function() return not D.booting() end, 240), "the boot runs out")
  U.wait(40)
  shot("d1_desktop")
  local st = D.state()
  check(Stack.has("woob_os") and Field.isLocked and Field.isLocked(), "on the UI stack, the field held")

  -- the draw's garbage, measured around each call (warmed up first: LuaJIT compiling the new
  -- paths' traces lands on the heap once)
  U.wait(180)
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

  -- Boxes (the dock's first): our own window, over a party and boxes lent for the run (the
  -- session's own put back after; nothing is saved)
  check(st.dock[1] and st.dock[1].id == "storage", "Boxes in the dock")
  local Storage, Bag = require("src.core.game3.storage"), require("src.core.game3.bag")
  local Party = require("src.core.game3.party")
  local Bx = X._test.bx
  local stor = Storage.ensure(s0)
  local party0, box0, cur0 = s0.party, {}, stor.currentBox
  for b = 1, 3 do
    box0[b] = stor.boxes[b].mons
    stor.boxes[b].mons = {}
  end
  -- (made in a session of their own: the player's Pokédex untouched)
  local function lend(list)
    local out = {}
    for _, sp in ipairs(list) do
      local tmp = { party = {} }
      local ok, _, m = Party.giveMon(tmp, sp, 18 + #out)
      if ok and m then out[#out + 1] = m end
    end
    return out
  end
  s0.party = lend({ 1, 4, 7 })
  local lent = lend({ 25, 133, 152, 155, 158, 175 })
  for i, slot in ipairs({ 1, 2, 7, 8, 14, 20 }) do stor.boxes[1].mons[slot] = lent[i] end
  -- (one shiny: the sparkle on its icon in the grid)
  if lent[4] then lent[4].isShiny = true end
  stor.currentBox = 1
  -- (Down past the home screen's rows)
  for _ = 1, 4 do
    if st.focus == "dock" then break end
    U.tap(game, "down"); U.wait(4)
  end
  check(st.focus == "dock", "Down: the dock")
  U.tap(game, "a")
  -- (the zoom runs on the clock; the driver's frames run faster than it)
  check(waitFor(function() return D.window() ~= nil end, 600), "A on Boxes: its window, in the desktop")
  local BW = D.window()
  local bst = BW and BW.state
  check(BW and BW.title == "Boxes", "the Boxes window")
  if bst then
    -- (the preview's Dynamax row: WoobleDex's, when it's on, else a stand-in; the lent Pikachu
    -- Dynamax Level 6 with the G-Max Factor)
    local realDx = Bx.dynamax and Bx.dynamax()
    local dynamax0 = Bx.dynamax
    if realDx and realDx.setLevel then
      realDx.setLevel(lent[1], 6); realDx.setFactor(lent[1], true)
    else
      local Dx = { canDynamax = function() return true end, level = function(m) return m == lent[1] and 6 or 0 end,
                   canGigantamax = function(m) return m == lent[1] end }
      Bx.dynamax = function() return Dx end
    end
    log("  Dynamax from " .. (realDx and "WoobleDex" or "a stand-in"))
    -- the pad's Poké Ball: dropped on, unlit until a Pokémon is carried
    check(waitFor(function() return D.ballState() == "drop" or D.ballState() == "on" end, 600), "the Poké Ball drops onto the pad")
    if D.ballState() == "drop" then shot("d2_ball_drop") end
    check(waitFor(function() return D.ballState() == "on" end, 600), "it lands")
    U.wait(20)
    check(select(2, D.ballState()) == nil, "the ball rests unlit")
    Bx.forget(lent[1])
    bst.area, bst.bi = "box", 1
    U.wait(10)
    local pv = Bx.info(lent[1], X._test.env.T)
    check(pv and pv.dmax == 6 and pv.gmax == true, "the preview: Dynamax Level 6, the G-Max Factor")
    shot("d2_boxes")
    Bx.dynamax = dynamax0
    -- (the shiny: its sparkle on the icon and in the preview)
    bst.area, bst.bi = "box", 8
    U.wait(4)
    check(Bx.shiny(Bx.boxMons(s0, 1)[8]) == true, "a shiny: the sparkle on its icon")
    shot("d2_boxes_shiny")
    bst.area, bst.bi = "box", 1
    U.wait(2)
    -- Swap: carry one two along
    U.tap(game, "select"); U.wait(4)
    check(bst.mode == BW.SWAP, "SELECT: Swap")
    bst.area, bst.bi = "box", 1
    U.tap(game, "a"); U.wait(4)
    check(bst.held ~= nil, "A picks it up")
    U.tap(game, "right"); U.wait(4)
    U.tap(game, "right"); U.wait(8)
    shot("d2b_boxes_carry")
    U.tap(game, "a"); U.wait(4)
    check(stor.boxes[1].mons[3] == lent[1], "A puts it down two along")
    -- Swap onto another: they trade places, and back
    do
      local k
      for i = 1, 30 do if i ~= 3 and stor.boxes[1].mons[i] then k = i; break end end
      local other = k and stor.boxes[1].mons[k]
      for round = 1, 2 do
        bst.area, bst.bi = "box", round == 1 and 3 or k
        U.tap(game, "a"); U.wait(4)
        bst.bi = round == 1 and k or 3
        U.tap(game, "a"); U.wait(4)
        if round == 1 then
          check(bst.held == nil and stor.boxes[1].mons[k] == lent[1] and stor.boxes[1].mons[3] == other,
            "Swap onto another: they trade places")
        end
      end
      check(stor.boxes[1].mons[3] == lent[1] and stor.boxes[1].mons[k] == other, "and back")
    end
    -- a party Pokémon into the box and back: a Poké Ball across the pad
    bst.area, bst.pi = "party", 3
    U.tap(game, "a"); U.wait(4)
    check(waitFor(function() return select(2, D.ballState()) == "moving" end, 120), "carrying: the ball glows red")
    U.wait(15)
    shot("d2_ball_glow")
    bst.area, bst.bi = "box", 30
    U.tap(game, "a"); U.wait(2)
    check(#s0.party == 2 and stor.boxes[1].mons[30] ~= nil, "deposit: party to box")
    check(waitFor(function() return select(2, D.ballState()) == "moved" end, 120) and D.padState() == 0,
      "put down: the ball flashes green, nothing crosses the pad")
    shot("d2c_pad_ball")
    U.tap(game, "a"); U.wait(4)
    bst.area, bst.pi = "party", 3
    U.tap(game, "a"); U.wait(4)
    check(#s0.party == 3 and stor.boxes[1].mons[30] == nil, "withdraw: back to the party")
    -- Drag: hold A over a rectangle, let go, carry the group to box 2
    U.tap(game, "select"); U.wait(4)
    check(bst.mode == BW.DRAG, "SELECT: Drag")
    bst.area, bst.bi = "box", 2
    table.insert(game.input.pressQueue, "a")
    game.input.state.a = true
    U.wait(3)
    U.tap(game, "right"); U.wait(3)
    U.tap(game, "down"); U.wait(6)
    check(bst.rect ~= nil, "held A: a rectangle")
    shot("d2d_boxes_rect")
    game.input.state.a = false
    U.wait(4)
    check(bst.held and bst.held.n == 3, "let go: three in the hand (" .. tostring(bst.held and bst.held.n) .. ")")
    U.tap(game, "r"); U.wait(4)
    check(bst.box == 2, "R: box 2, carrying them (the game's help stays shut)")
    bst.area, bst.bi = "box", 1
    U.wait(6)
    shot("d2e_boxes_group")
    U.tap(game, "a"); U.wait(4)
    check(bst.held == nil and Bx.count(s0, 2) == 3, "A: down in box 2, together")
    -- Select: a Pokémon's options, the box menu, the wallpapers
    U.tap(game, "select"); U.wait(4)
    check(bst.mode == BW.SELECT, "SELECT: round to Select")
    U.tap(game, "a"); U.wait(6)
    check(bst.sheet and bst.sheet.kind == "actions", "A: its options")
    shot("d2f_actions")
    U.tap(game, "b"); U.wait(4)
    U.tap(game, "start"); U.wait(6)
    check(bst.sheet and bst.sheet.kind == "box", "START: the box menu")
    shot("d2g_boxmenu")
    U.tap(game, "down"); U.wait(2)
    U.tap(game, "down"); U.wait(2)
    U.tap(game, "a"); U.wait(6)
    check(bst.sheet and bst.sheet.kind == "wall", "Wallpaper: the game's wallpapers")
    shot("d2h_wallpaper")
    U.tap(game, "b"); U.wait(4)
    -- WoobleDex's Bigger PC (on unless its option is off): every box, R round from 40 to 1
    do
      local Bx = X._test.bx
      local St = require("src.core.game3.storage")
      log(("  the PC's boxes: %d (the engine's TOTAL_BOXES_COUNT %s)"):format(Bx.BOXES, tostring(St.TOTAL_BOXES_COUNT)))
      check(Bx.BOXES == (tonumber(St.TOTAL_BOXES_COUNT) or 14), "Boxes has every box the PC has")
      if Bx.BOXES > 14 then
        local box0 = bst.box
        bst.box = Bx.BOXES - 1
        Bx.setCurrent(s0, bst.box)
        U.tap(game, "r"); U.wait(10)
        check(bst.box == Bx.BOXES, "R to the last box (" .. tostring(bst.box) .. ")")
        shot("d2h2_box_last")
        U.tap(game, "r"); U.wait(6)
        check(bst.box == 1, "then round to box 1")
        bst.box = box0
        Bx.setCurrent(s0, box0)
        U.wait(4)
      end
    end
    -- the window's draw garbage
    local drawB, kbB, nB = D.draw, 0, 0
    D.draw = function(...)
      local was = collectgarbage("isrunning")
      collectgarbage("stop")
      local kb0 = collectgarbage("count")
      drawB(...)
      kbB, nB = kbB + (collectgarbage("count") - kb0), nB + 1
      if was then collectgarbage("restart") end
    end
    U.wait(120)
    D.draw = drawB
    log(("  the Boxes window's draw: %.3f KB per frame over %d frames"):format(kbB / math.max(1, nB), nB))
    check(kbB / math.max(1, nB) < 0.5, "the Boxes window makes next to no garbage")
    -- Summary: the game's screen, then the window back as it was
    U.tap(game, "a"); U.wait(6)
    U.tap(game, "down"); U.wait(2)
    U.tap(game, "a")
    check(waitFor(function() return not D.isOpen() end, 120), "Summary: the game's own screen")
    U.wait(40)
    shot("d2i_summary")
    -- (B only while the game's Summary is up: a B on the desktop coming back opens its Log Off sheet)
    local back = waitFor(function()
      if D.window() then return true end
      if not D.isOpen() then
        U.tap(game, "b")
        U.wait(20)
      end
      return D.window() ~= nil
    end, 30)
    if D.isOpen() and D.state().sheet then
      U.tap(game, "b")
      U.wait(10)
    end
    local BW2 = D.window()
    check(back and BW2 and BW2.title == "Boxes" and BW2.state.box == 2 and BW2.state.mode == BW.SELECT,
      "B: back into Boxes, box 2, Select")
    U.wait(10)
    shot("d2j_boxes_back")
    check(D.ballState() == "on", "the Poké Ball still on the pad after the Summary")
    U.tap(game, "b")
    check(waitFor(function() return D.ballState() == "done" end, 600), "closed: the button flashes green")
    shot("d2k_ball_green")
    check(waitFor(function() return D.ballState() == "lift" end, 600), "then the ball lifts off")
    shot("d2l_ball_lift")
    check(waitFor(function() return D.ballState() == "off" end, 600), "and it's gone")
    waitFor(function() return D.window() == nil and D.state() and D.state().zoom == nil end, 600)
  end
  -- (the session's own party and boxes back)
  s0.party = party0
  for b = 1, 3 do stor.boxes[b].mons = box0[b] end
  stor.currentBox = cur0
  st = D.state()

  -- Items: our own window; the PC's Potion to the Bag and back
  local Storage, Bag = require("src.core.game3.storage"), require("src.core.game3.bag")
  local pcItems = Storage.ensure(s0).items
  local potion = pcItems[1] and pcItems[1].id
  local pcQty0, bagQty0 = pcItems[1] and pcItems[1].qty or 0, potion and Bag.get(s0.bag, potion) or 0
  st.focus, st.dockCursor = "dock", 2
  U.tap(game, "a")
  waitFor(function() return D.window() ~= nil end, 600)
  U.wait(10)
  local IW = D.window()
  check(IW and IW.title == "Items", "Items: its window, in the desktop")
  check(waitFor(function() return select(4, D.padState()) > 0.99 end, 600), "the shelf's pad lights up")
  shot("d4_items")
  -- the Bag's own sort menu (START with the Bag in focus), closed again
  if IW then
    local focus0 = IW.state.focus
    IW.state.focus = "bag"
    U.tap(game, "start"); U.wait(6)
    check(IW.state.menu and IW.state.menu.pane == "bag", "START on the Bag: its sort menu")
    shot("d4s_items_bag_sort")
    U.tap(game, "b"); U.wait(4)
    IW.state.focus = focus0
  end
  -- items other mods add (WoobDex's Exp. Candy, Dynamax Candy, Max Mushrooms): their own pictures,
  -- lent to the PC for a shot, then taken back
  do
    local items0 = {}
    for i, e in ipairs(pcItems) do items0[i] = e end
    for _, id in ipairs({ 950, 955, 956 }) do pcItems[#pcItems + 1] = { id = id, qty = 3 } end
    IW.refresh()
    IW.state.focus = "pc"
    U.wait(10)
    shot("d4m_mod_items")
    local Env0 = X._test.env
    local okMod = love.graphics.newCanvas ~= nil
    for _, id in ipairs({ 950, 955, 956 }) do
      local got = false
      local G = love.graphics
      G.push("all")
      local okC, canvas = pcall(G.newCanvas, 24, 24)
      if okC and canvas then
        G.setCanvas(canvas)
        G.origin()
        G.clear(0, 0, 0, 0)
        -- (drawn as the window draws it, in the kit's units: the canvas's 24 px at its corner)
        local K = Env0.K
        pcall(Env0.itemIcon, id, -K.ox / K.sc, -K.oy / K.sc, 24 / K.sc, 1)
        G.setCanvas()
        local data = canvas:newImageData()
        for py = 0, 23 do for px = 0, 23 do if select(4, data:getPixel(px, py)) > 0 then got = true end end end
      end
      G.pop()
      log(("  item %d: %s"):format(id, got and "a picture" or "none"))
      okMod = okMod and got
    end
    check(okMod, "WoobDex's items have their pictures (950, 955, 956)")
    for i = #pcItems, 1, -1 do pcItems[i] = nil end
    for i, e in ipairs(items0) do pcItems[i] = e end
    IW.refresh()
    U.wait(4)
  end
  -- the pad: the Poké Ball resting on it while there's a party (a party lent for the shot, then put back)
  do
    local party0 = s0.party
    s0.party = { { species = 1 }, { species = 4 }, { species = 7 } }
    check(waitFor(function() return D.state().balls == 3 end, 1200) and D.ballState() == "off",
      "Items holds no Pokémon: no Poké Ball on the pad")
    s0.party = party0
  end
  -- (the pad's effects run on the wall clock: wait for their moments)
  local function padAt(dir, at)
    return waitFor(function()
      local n, d = D.padState()
      return n > 0 and d == dir and love.timer.getTime() - D.state().padQ[1].t0 >= at
    end, 1200)
  end
  if IW and potion then
    U.tap(game, "a"); U.wait(4)
    if IW.state.step then U.tap(game, "a"); U.wait(4) end
    check(Bag.get(s0.bag, potion) == bagQty0 + pcQty0, "the PC's first item to the Bag")
    check(padAt("in", 0.3), "it digitizes in on the pad")
    shot("d4p1_pad_in")
    padAt("in", 0.65)
    shot("d4p2_pad_hold")
    shot("d4b_items_moved")
    U.tap(game, "left"); U.wait(4)
    for i, row in ipairs(IW.state.bag.rows) do if row.id == potion then IW.state.bag.cursor = i end end
    U.tap(game, "select"); U.wait(4)
    check(Bag.get(s0.bag, potion) == 0 and Storage.ensure(s0).items[1].qty == pcQty0 + bagQty0,
      "SELECT: the whole stack back to the PC")
    check(padAt("out", 0.15), "then it drops onto the pad")
    shot("d4p3_pad_drop")
    padAt("out", 0.5)
    shot("d4p4_pad_out")
    check(waitFor(function() return D.padState() == 0 end, 1200), "and digitizes away")
    -- an item crossing, its draw garbage (warm: it just played)
    D.padTransfer(potion, "out")
    local drawP, kbP, nP = D.draw, 0, 0
    D.draw = function(...)
      local was = collectgarbage("isrunning")
      collectgarbage("stop")
      local kb0 = collectgarbage("count")
      drawP(...)
      kbP, nP = kbP + (collectgarbage("count") - kb0), nP + 1
      if was then collectgarbage("restart") end
    end
    waitFor(function() return D.padState() == 0 end, 1200)
    D.draw = drawP
    log(("  an item crossing the pad: %.3f KB per frame over %d frames"):format(kbP / math.max(1, nP), nP))
    check(kbP / math.max(1, nP) < 0.5, "an item crossing the pad makes next to no garbage")
  end
  -- the window's draw garbage (warmed up first: LuaJIT compiling new paths lands on the heap once)
  U.wait(120)
  local drawW, kbW, nW = D.draw, 0, 0
  D.draw = function(...)
    local was = collectgarbage("isrunning")
    collectgarbage("stop")
    local kb0 = collectgarbage("count")
    drawW(...)
    kbW, nW = kbW + (collectgarbage("count") - kb0), nW + 1
    if was then collectgarbage("restart") end
  end
  U.wait(120)
  D.draw = drawW
  log(("  the Items window's draw: %.3f KB per frame over %d frames"):format(kbW / math.max(1, nW), nW))
  check(kbW / math.max(1, nW) < 0.5, "the Items window makes next to no garbage")
  U.tap(game, "b")
  waitFor(function() return D.window() == nil and D.state() and D.state().zoom == nil end, 600)
  check(D.window() == nil and D.isOpen(), "B: the desktop again")

  -- Mail: a letter in the PC's mailbox, read, then to the Bag
  local Mail = require("src.core.game3.mail")
  local rec = Mail.pool(s0)[7]
  Mail.clear(rec)
  rec.itemId, rec.playerName, rec.species = 121, "MOM", 25
  rec.words[1], rec.words[2], rec.words[4] = 0x200, 0x201, 0x400
  st.focus, st.dockCursor = "dock", 3
  U.tap(game, "a")
  waitFor(function() return D.window() ~= nil end, 600)
  U.wait(10)
  local MW = D.window()
  check(MW and MW.title == "Mail" and #MW.state.inbox == 1, "Mail: its inbox, the letter in it")
  U.tap(game, "a"); U.wait(10)
  shot("d4c_mail")
  local mailBag0 = Bag.get(s0.bag, 121)
  U.tap(game, "a"); U.wait(4)
  shot("d4d_mail_sheet")
  U.tap(game, "left"); U.wait(2)
  U.tap(game, "a"); U.wait(10)
  check(Bag.get(s0.bag, 121) == mailBag0 + 1 and Mail.isEmpty(rec), "Move to Bag: the stationery back, the message gone")
  U.tap(game, "b")
  waitFor(function() return D.window() == nil and D.state() and D.state().zoom == nil end, 600)
  check(D.window() == nil and D.isOpen(), "B: the desktop again")
  U.wait(10)
  shot("d4e_dock_focus")
  st = D.state()

  -- Mart: no badges yet (a Great Ball locked), then all eight lent; three Great Balls onto the pad,
  -- one sold back off it; the Bag and the money put back after
  for i, app in ipairs(st.grid) do if app.id == "mart" then st.focus, st.cursor = "grid", i end end
  U.tap(game, "a")
  waitFor(function() return D.window() ~= nil end, 600)
  U.wait(10)
  local TW = D.window()
  check(TW and TW.title == "Mart", "Mart: its window")
  if TW then
    local ts = TW.state
    local money0, great0 = s0.money, Bag.get(s0.bag, 3)
    local great = TW.state.rows[2] and TW.state.rows[2].price or 0
    check(ts.badges == 0 and great > 0, "a new game: no badges (" .. tostring(ts.badges) .. "), a Great Ball's price " .. great)
    shot("d11_mart")
    U.tap(game, "down"); U.wait(2)
    U.tap(game, "a"); U.wait(6)
    check(ts.focus == "list" and ts.toast and ts.toast.bad, "a Great Ball with no badges: locked")
    shot("d11b_mart_locked")
    ts.badges = 8
    U.tap(game, "a"); U.wait(2)
    U.tap(game, "right"); U.wait(2)
    U.tap(game, "right"); U.wait(2)
    check(ts.focus == "step" and ts.qty == 3, "how many: three (" .. tostring(ts.qty) .. ")")
    shot("d11c_mart_step")
    U.tap(game, "a"); U.wait(2)
    check(Bag.get(s0.bag, 3) == great0 + 3 and s0.money == money0 - 3 * great, "three Great Balls bought")
    check(padAt("in", 0.3), "they appear on the pad")
    shot("d11d_mart_pad")
    U.tap(game, "start"); U.wait(4)
    for i, p in ipairs(ts.pockets) do if p.id == "POKE_BALLS" then ts.sellTab = i end end
    TW.refresh()
    for i, r in ipairs(ts.rows) do if r.id == 3 then ts.cursor = i end end
    TW.refresh()
    U.wait(4)
    shot("d11e_mart_sell")
    U.tap(game, "a"); U.wait(2)
    U.tap(game, "a"); U.wait(2)
    check(Bag.get(s0.bag, 3) == great0 + 2 and s0.money == money0 - 3 * great + math.floor(great / 2),
      "one sold back for half its price")
    check(padAt("out", 0.15), "it leaves off the pad")
    shot("d11f_mart_out")
    waitFor(function() return D.padState() == 0 end, 1200)
    -- the window's draw garbage (warmed up first: LuaJIT compiling new paths lands on the heap once)
    U.wait(120)
    local drawM, kbM, nM = D.draw, 0, 0
    D.draw = function(...)
      local was = collectgarbage("isrunning")
      collectgarbage("stop")
      local kb0 = collectgarbage("count")
      drawM(...)
      kbM, nM = kbM + (collectgarbage("count") - kb0), nM + 1
      if was then collectgarbage("restart") end
    end
    U.wait(120)
    D.draw = drawM
    log(("  the Mart window's draw: %.3f KB per frame over %d frames"):format(kbM / math.max(1, nM), nM))
    check(kbM / math.max(1, nM) < 0.5, "the Mart window makes next to no garbage")
    local extra = Bag.get(s0.bag, 3) - great0
    if extra > 0 then Bag.remove(s0.bag, 3, extra) end
    s0.money = money0
    U.tap(game, "b")
    waitFor(function() return D.window() == nil and D.state() and D.state().zoom == nil end, 600)
    check(D.window() == nil and D.isOpen(), "B: the desktop again")
  end
  st = D.state()

  -- R-Bay: the market; a bid nobody beats (lent money), its end (the model's clock moved past it):
  -- the Pokémon arrives, a Poké Ball onto the pad; everything put back after
  local Au = X._test.auction
  for i, app in ipairs(st.grid) do if app.id == "auction" then st.focus, st.cursor = "grid", i end end
  U.tap(game, "a")
  waitFor(function() return D.window() ~= nil end, 600)
  U.wait(10)
  local RW = D.window()
  check(RW and RW.title == "R-Bay" and #RW.state.rows == 12, "R-Bay: its window, twelve auctions")
  if RW then
    local rs = RW.state
    shot("d12_rbay")
    for i, L in ipairs(rs.rows) do
      if L.tier == "legendary" or L.tier == "mythical" or L.tier == "prized" then rs.cursor, rs.key = i, L.key end
    end
    U.wait(4)
    shot("d12b_rbay_pick")
    local money0, party0 = s0.money, #(s0.party or {})
    s0.money = 999999
    U.tap(game, "a"); U.wait(2)
    U.tap(game, "right"); U.wait(2)
    shot("d12c_rbay_step")
    U.tap(game, "select"); U.wait(2)
    local L = rs.rows[rs.cursor]
    U.tap(game, "a"); U.wait(6)
    check(L.mine ~= nil and L.leader == 0, "a bid nobody beats: in the lead")
    shot("d12d_rbay_bid")
    U.tap(game, "r"); U.wait(6)
    check(rs.tab == "mine" and rs.mineN >= 1, "My Bids: the bid")
    shot("d12e_rbay_mine")
    -- the window's draw garbage, on My Bids, then Browse (each warmed up first: LuaJIT compiling
    -- the new paths' traces lands on the heap once)
    local drawA, kbA, nA, on = D.draw, 0, 0, false
    D.draw = function(...)
      if not on then return drawA(...) end
      local was = collectgarbage("isrunning")
      collectgarbage("stop")
      local kb0 = collectgarbage("count")
      drawA(...)
      kbA, nA = kbA + (collectgarbage("count") - kb0), nA + 1
      if was then collectgarbage("restart") end
    end
    U.wait(120)
    on = true
    U.wait(90)
    on = false
    local kbMine, nMine = kbA, nA
    U.tap(game, "l")
    U.wait(120)
    on = true
    U.wait(90)
    D.draw = drawA
    log(("  the R-Bay window's draw: %.3f KB per frame over %d frames (My Bids %.3f, Browse %.3f)"):format(
      kbA / math.max(1, nA), nA, kbMine / math.max(1, nMine), (kbA - kbMine) / math.max(1, nA - nMine)))
    check(kbA / math.max(1, nA) < 0.5, "the R-Bay window makes next to no garbage")
    -- its end
    local now0 = Au.now
    Au.now = function() return L.finish + 1 end
    check(waitFor(function() return #Au.results() > 0 end, 300), "it ends: settled on the desktop's tick")
    local res = Au.results()[1]
    check(res and res.won and res.sp == L.sp, "won: " .. tostring(res and res.name))
    check(#(s0.party or {}) == party0 + 1 and s0.party[#s0.party].ivs.hp == L.ivs.hp, "it joins the party, with its IVs")
    check(waitFor(function() local n, _, _, _, kind = D.padState(); return n > 0 and kind == "ball" end, 120),
      "a Poké Ball onto the pad")
    U.wait(20)
    shot("d12f_rbay_won")
    U.tap(game, "r"); U.wait(6)
    shot("d12g_rbay_result")
    -- put back: the party, the money, the save's R-Bay data, the clock
    if #s0.party == party0 + 1 then s0.party[#s0.party] = nil end
    s0.money = money0
    if Au.store then Au.store:set("auction", nil) end
    Au.now = now0
    U.tap(game, "b")
    waitFor(function() return D.window() == nil and D.state() and D.state().zoom == nil end, 600)
    check(D.window() == nil and D.isOpen(), "B: the desktop again")
  end
  st = D.state()

  -- Slots: a spin told to land on the jackpot (lent money), the pay table, a prize redeemed with lent
  -- tickets onto the pad; everything put back after
  local Sl = X._test.slots
  for i, app in ipairs(st.grid) do if app.id == "slots" then st.focus, st.cursor = "grid", i end end
  U.tap(game, "a")
  waitFor(function() return D.window() ~= nil end, 600)
  U.wait(10)
  local SW = D.window()
  check(SW and SW.title == "Slots", "Slots: its window")
  if SW then
    local ss = SW.state
    local money0, rng0 = s0.money, Sl.rng
    local tickets0 = Sl.tickets()
    s0.money = 20000
    shot("d13_slots")
    local queue = {}
    local function at(r, sym) for i, v in ipairs(Sl.REELS[r]) do if v == sym then return i end end end
    Sl.rng = function() return table.remove(queue, 1) or 1 end
    queue = { at(1, Sl.ROCKET), at(2, Sl.ROCKET), at(3, Sl.ROCKET) }
    U.tap(game, "a"); U.wait(2)
    check(ss.spinning and s0.money == 20000 - Sl.BETS[ss.bet], "A: spinning, the bet taken")
    U.wait(20)
    shot("d13b_slots_spin")
    check(waitFor(function() return ss.tease and ss.stopped[2] and not ss.stopped[3] end, 600), "two R's: the last reel held back")
    U.wait(30)
    shot("d13b2_slots_tease")
    check(waitFor(function() return not ss.spinning end, 900), "the reels stop")
    U.wait(40)
    check(ss.win and ss.win.jackpot and s0.money == 20000 - Sl.BETS[ss.bet] + Sl.BETS[ss.bet] * Sl.PAYS[Sl.ROCKET].x,
      "the jackpot, paid")
    shot("d13c_slots_jackpot")
    U.wait(60)
    shot("d13c2_slots_jackpot_coins")
    U.tap(game, "start"); U.wait(6)
    check(ss.table, "START: the pay table")
    shot("d13d_slots_table")
    U.tap(game, "b"); U.wait(4)
    -- five lines: three Meowth down the diagonal
    local nowS = function() return love.timer.getTime() end
    waitFor(function() return nowS() - ss.win.t > ss.win.tier.count + 2.2 end, 3000)
    U.tap(game, "up"); U.wait(3)
    U.tap(game, "up"); U.wait(20)
    check(Sl.LINE_SETS[ss.lines] == 5, "Up, Up: five lines")
    shot("d13d2_slots_five_lines")
    local n = #Sl.REELS[1]
    local i1, i2, i3 = at(1, 6), at(2, 6), at(3, 6)
    queue = { i1 % n + 1, i2, (i3 - 2) % n + 1 }
    local before = s0.money
    U.tap(game, "a"); U.wait(2)
    check(s0.money == before - 5 * Sl.BETS[ss.bet], "five lines: five bets")
    check(waitFor(function() return not ss.spinning end, 900), "the reels stop")
    U.wait(30)
    check(Sl.result.won[4] == Sl.PAYS[6].x and ss.win and ss.win.pays >= Sl.PAYS[6].x * Sl.BETS[ss.bet],
      "the diagonal pays")
    shot("d13d3_slots_diagonal")
    waitFor(function() return nowS() - ss.win.t > ss.win.tier.count + 2.3 end, 3000)
    shot("d13d4_slots_diagonal_line")
    U.wait(150)
    -- the draw's garbage: idle, then a spin (each warmed up)
    local drawS, kbS, nS, on = D.draw, 0, 0, false
    D.draw = function(...)
      if not on then return drawS(...) end
      local was = collectgarbage("isrunning")
      collectgarbage("stop")
      local kb0 = collectgarbage("count")
      drawS(...)
      kbS, nS = kbS + (collectgarbage("count") - kb0), nS + 1
      if was then collectgarbage("restart") end
    end
    U.wait(240)
    on = true
    U.wait(60)
    queue = { 1, 2, 3 }
    U.tap(game, "a")
    U.wait(90)
    D.draw = drawS
    log(("  the Slots window's draw: %.3f KB per frame over %d frames"):format(kbS / math.max(1, nS), nS))
    check(kbS / math.max(1, nS) < 0.5, "the Slots window makes next to no garbage")
    waitFor(function() return not ss.spinning end, 600)
    U.tap(game, "r"); U.wait(6)
    check(ss.tab == "prizes", "R: the prizes")
    Sl.setTickets(500)
    for i, p in ipairs(Sl.prizes()) do if p.kind == "mon" and p.cost == 200 then ss.cursor = i end end
    U.wait(6)
    shot("d13e_slots_prizes")
    local candy
    for i, p in ipairs(Sl.prizes()) do if p.kind == "item" and p.id == 68 then candy = i end end
    ss.cursor = candy or 1
    local candies0 = Bag.get(s0.bag, 68)
    U.tap(game, "a"); U.wait(4)
    check(Bag.get(s0.bag, 68) == candies0 + 1, "a Rare Candy redeemed into the Bag")
    U.wait(6)
    shot("d13f_slots_redeemed")
    check(padAt("in", 0.3), "it appears on the pad")
    -- put back
    if Bag.get(s0.bag, 68) > candies0 then Bag.remove(s0.bag, 68, Bag.get(s0.bag, 68) - candies0) end
    Sl.setTickets(tickets0)
    s0.money = money0
    Sl.rng = rng0
    U.tap(game, "b")
    waitFor(function() return D.window() == nil and D.state() and D.state().zoom == nil end, 600)
    check(D.window() == nil and D.isOpen(), "B: the desktop again")
  end
  st = D.state()

  -- GTS: a party lent; a Wonder Trade told to bring a legendary (search, found, reveal), one that
  -- brings a Kadabra (the game's evolution scene, then the window again); the listings; a deposit
  -- (asking a Pidgey) answered and collected; everything put back after
  do
    local Gx, Au = X._test.gts, X._test.auction
    local Party = require("src.core.game3.party")
    local P = require("src.core.game3.pokemon")
    local party0 = s0.party
    local scratch = { party = {}, name = s0.name, trainerId = s0.trainerId, secretId = s0.secretId,
                      dex = { seen = {}, owned = {}, caught = {} } }
    Party.giveMon(scratch, P.speciesFromNational(16), 12)
    Party.giveMon(scratch, P.speciesFromNational(19), 14)
    Party.giveMon(scratch, P.speciesFromNational(21), 15)
    s0.party = scratch.party
    local gtsData0 = Gx.store and Gx.store:get("gts")
    local rng0, now0 = Gx.rng, Gx.now
    local queue = {}
    local R = love.math.random
    Gx.rng = function(n)
      local v = table.remove(queue, 1)
      if v then return math.max(1, math.min(n, v)) end
      return R(1, n)
    end
    local function poolIndex(nat)
      local sp = P.speciesFromNational(nat)
      for tier, pool in pairs(Au.pools()) do
        for i, e in ipairs(pool) do if e.sp == sp then return tier, i end end
      end
    end
    for i, app in ipairs(st.grid) do if app.id == "gts" then st.focus, st.cursor = "grid", i end end
    U.tap(game, "a")
    waitFor(function() return D.window() ~= nil end, 600)
    U.wait(10)
    local GW = D.window()
    check(GW and GW.title == "GTS", "GTS: its window")
    if GW then
      local gw = GW.state
      shot("d14_gts_wonder")
      -- (a legendary: the tier roll, then the first of that pool)
      queue = { 990, 1 }
      gw.cursor = 2
      U.tap(game, "a"); U.wait(4)
      shot("d14b_gts_confirm")
      U.tap(game, "a"); U.wait(40)
      shot("d14c_gts_search")
      check(waitFor(function() return gw.search and gw.search.found end, 600), "the search finds a trainer")
      U.wait(30)
      shot("d14d_gts_found")
      check(waitFor(function() return gw.reveal ~= nil end, 600), "the newcomer revealed")
      U.wait(30)
      shot("d14e_gts_reveal")
      check(gw.reveal and Au.tierOf(tonumber(gw.reveal.mon.species)) == "legendary" and P.isTradedMon(gw.reveal.mon, s0),
        "a legendary, from a stranger")
      U.tap(game, "a"); U.wait(10)
      -- (a Kadabra: the game's evolution scene, then this window again)
      local tier, idx = poolIndex(64)
      local base = { common = 1, uncommon = 451, rare = 751, prized = 901, legendary = 981, mythical = 996 }
      queue = { base[tier] or 451, idx }
      gw.cursor = 1
      U.tap(game, "a"); U.wait(4)
      U.tap(game, "a"); U.wait(4)
      U.tap(game, "a")
      check(waitFor(function() return gw.reveal ~= nil end, 900), "a Kadabra revealed")
      check(gw.reveal and gw.reveal.evolve ~= nil, "it's going to evolve")
      U.wait(20)
      shot("d14f_gts_kadabra")
      U.tap(game, "a")
      local Scene = require("src.ui.game3.evolution_scene")
      check(waitFor(function() return Scene.isOpen() end, 300), "the game's evolution scene")
      U.wait(120)
      shot("d14g_gts_evolving")
      waitFor(function()
        if Scene.isOpen() then U.tap(game, "a") end
        return not Scene.isOpen() and D.window() ~= nil
      end, 3000)
      GW = D.window()
      gw = GW and GW.state
      local alakazam = false
      for _, m in ipairs(s0.party) do if tonumber(m.species) == P.speciesFromNational(65) then alakazam = true end end
      check(alakazam and GW and GW.title == "GTS", "Alakazam, and the GTS again")
      U.wait(20)
      -- the listings
      U.tap(game, "start"); U.wait(30)
      check(gw.tab == "browse" and #gw.listings > 0, "the GTS listings")
      shot("d14h_gts_browse")
      -- the window's draw garbage (warmed up)
      local drawG, kbG, nG, on = D.draw, 0, 0, false
      D.draw = function(...)
        if not on then return drawG(...) end
        local was = collectgarbage("isrunning")
        collectgarbage("stop")
        local kb0 = collectgarbage("count")
        drawG(...)
        kbG, nG = kbG + (collectgarbage("count") - kb0), nG + 1
        if was then collectgarbage("restart") end
      end
      U.wait(120)
      on = true
      U.wait(120)
      D.draw = drawG
      log(("  the GTS window's draw: %.3f KB per frame over %d frames"):format(kbG / math.max(1, nG), nG))
      check(kbG / math.max(1, nG) < 0.5, "the GTS window makes next to no garbage")
      -- a deposit: one of yours for a Pidgey, any level; answered; collected
      s0.dex = s0.dex or { seen = {}, owned = {}, caught = {} }
      s0.dex.seen = s0.dex.seen or {}
      local pidgeySeen0 = s0.dex.seen[P.speciesFromNational(16)]
      s0.dex.seen[P.speciesFromNational(16)] = true
      U.tap(game, "start"); U.wait(10)
      check(gw.tab == "deposit", "My Deposit")
      shot("d14i_gts_deposit_empty")
      U.tap(game, "a"); U.wait(6)
      gw.cursor = #gw.rows
      U.tap(game, "a"); U.wait(6)
      -- (a Pidgey, seen for the run: a fair ask, always answered, nothing to evolve)
      for i, sp in ipairs(gw.species) do if sp == P.speciesFromNational(16) then gw.scursor = i end end
      U.wait(4)
      shot("d14j_gts_species")
      U.tap(game, "a"); U.wait(6)
      shot("d14k_gts_levels")
      U.tap(game, "a"); U.wait(4)
      U.tap(game, "a"); U.wait(20)
      local dep = Gx.posted()
      check(dep and dep.matchAt, "posted, a match coming")
      shot("d14l_gts_waiting")
      if dep and dep.matchAt then
        local at = dep.matchAt
        Gx.now = function() return at + 1 end
        check(waitFor(function() return Gx.waiting() == 1 end, 300), "answered on the desktop's tick")
        U.wait(30)
        shot("d14m_gts_traded")
        U.tap(game, "a")
        check(waitFor(function() return gw.reveal ~= nil end, 600), "collected: revealed")
        U.wait(20)
        U.tap(game, "a"); U.wait(6)
      end
      -- put back
      s0.dex.seen[P.speciesFromNational(16)] = pidgeySeen0
      s0.party = party0
      if Gx.store then Gx.store:set("gts", gtsData0) end
      Gx.rng, Gx.now = rng0, now0
      U.tap(game, "b")
      waitFor(function() return D.window() == nil and D.state() and D.state().zoom == nil end, 600)
      check(D.window() == nil and D.isOpen(), "B: the desktop again")
    end
    s0.party = party0
    Gx.rng, Gx.now = rng0, now0
  end
  st = D.state()

  -- Settings: French, every wallpaper (a picture the run put in wallpapers/ too), then the
  -- installation's settings file back as it was
  local XT = X._test
  local I18n, Set, Wall, Env = XT.i18n, XT.settings, XT.wall, XT.env
  local savedSettings = Set.cache and Set.cache.read and Set.cache:read("settings.lua")
  for i, app in ipairs(st.grid) do if app.id == "settings" then st.focus, st.cursor = "grid", i end end
  U.tap(game, "a")
  waitFor(function() return D.window() ~= nil end, 600)
  U.wait(10)
  local SW = D.window()
  check(SW and SW.title == "Settings", "Settings: its window")
  shot("d5a_settings")
  U.tap(game, "a"); U.wait(4)
  for _ = 1, 3 do U.tap(game, "down"); U.wait(3) end
  U.tap(game, "a"); U.wait(6)
  check(I18n.code() == "fr", "A on Français: French")
  shot("d5b_settings_fr")
  U.tap(game, "b"); U.wait(3)
  U.tap(game, "down"); U.wait(3)
  U.tap(game, "a"); U.wait(20)
  shot("d5c_settings_wallpaper")
  U.tap(game, "b"); U.wait(3)
  U.tap(game, "b")
  waitFor(function() return D.window() == nil and D.state().zoom == nil end, 600)
  U.wait(10)
  shot("d5d_desktop_fr")
  -- Japanese (its kana from the engine's Plain Pixel face) and Brazilian Portuguese
  for _, code in ipairs({ "ja", "pt-br" }) do
    Env.setLanguage(code)
    check(I18n.code() == code, code .. ": chosen")
    U.wait(4)
    shot("d5d_desktop_" .. code)
    st = D.state()
    for i, app in ipairs(st.grid) do if app.id == "settings" then st.focus, st.cursor = "grid", i end end
    U.tap(game, "a")
    waitFor(function() return D.window() ~= nil end, 600)
    U.wait(6)
    U.tap(game, "a"); U.wait(6)
    shot("d5d_settings_" .. code)
    U.tap(game, "b"); U.wait(3)
    U.tap(game, "b")
    waitFor(function() return D.window() == nil and D.state().zoom == nil end, 600)
  end
  Env.setLanguage("en")
  local choices = Wall.choices()
  check(#choices >= 7, "the wallpapers: the built-ins and the run's picture (" .. #choices .. ")")
  for _, c in ipairs(choices) do
    Env.setWallpaper(c.id)
    U.wait(4)
    shot("d5e_wall_" .. c.id:gsub("[^%w]", "_"))
  end
  -- a picture: Fill and Stretch, and the switch on the Wallpaper page
  local pic
  for _, c in ipairs(choices) do if Wall.isPicture(c.id) then pic = c.id end end
  if pic then
    Env.setWallpaper(pic)
    Env.setWallpaperFit("stretch")
    U.wait(4)
    shot("d5f_picture_stretch")
    st = D.state()
    for i, app in ipairs(st.grid) do if app.id == "settings" then st.focus, st.cursor = "grid", i end end
    U.tap(game, "a")
    waitFor(function() return D.window() ~= nil end, 600)
    U.wait(6)
    U.tap(game, "down"); U.wait(3)
    U.tap(game, "a"); U.wait(20)
    shot("d5g_settings_fit")
    U.tap(game, "select"); U.wait(4)
    check(Env.wallpaperFit() == "fill", "SELECT on the Wallpaper page: back to Fill")
    U.tap(game, "b"); U.wait(3)
    U.tap(game, "b")
    waitFor(function() return D.window() == nil and D.state().zoom == nil end, 600)
    shot("d5h_picture_fill")
  end
  Env.setWallpaper("ribbon")
  U.wait(10)
  local drawR, kbR, nR = D.draw, 0, 0
  D.draw = function(...)
    local was = collectgarbage("isrunning")
    collectgarbage("stop")
    local kb0 = collectgarbage("count")
    drawR(...)
    kbR, nR = kbR + (collectgarbage("count") - kb0), nR + 1
    if was then collectgarbage("restart") end
  end
  U.wait(120)
  D.draw = drawR
  log(("  the desktop's draw on Ribbon: %.3f KB per frame over %d frames"):format(kbR / math.max(1, nR), nR))
  check(kbR / math.max(1, nR) < 0.5, "a drawn wallpaper makes next to no garbage")
  -- arranging: a long press on the first app, dragged into the dock and let go; Done
  do
    st = D.state()
    local grid0, dock0 = {}, {}
    for i, a in ipairs(st.grid) do grid0[i] = a end
    for i, a in ipairs(st.dock) do dock0[i] = a end
    local function hitOf(kind, arg)
      for _, h in ipairs(st.hit) do if h.kind == kind and h.arg == arg then return h end end
    end
    local g1, d1 = hitOf("grid", 1), hitOf("dock", 1)
    local app = st.grid[1]
    if g1 and d1 then
      local gx, gy = g1[1] + g1[3] / 2, g1[2] + g1[4] / 2
      D.pointer({ id = 7, phase = "pressed", x = gx, y = gy })
      check(waitFor(function() return D.arranging() and st.carry ~= nil end, 600), "a long press: arranging, the app in hand")
      U.wait(20)
      shot("d10_arrange_lift")
      local dx, dy = d1[1] + d1[3] / 2, d1[2] + d1[4] / 2
      for k = 1, 8 do
        D.pointer({ id = 7, phase = "moved", x = gx + (dx - gx) * k / 8, y = gy + (dy - gy) * k / 8 })
        U.wait(2)
      end
      check(st.carry and st.carry.list == "dock", "dragged into the dock")
      shot("d10b_arrange_dock")
      D.pointer({ id = 7, phase = "released", x = dx, y = dy })
      U.wait(10)
      local inDock = false
      for _, a in ipairs(st.dock) do if a == app then inDock = true end end
      check(st.carry == nil and inDock, "let go: it stays in the dock")
      shot("d10c_arranged")
      U.tap(game, "b"); U.wait(6)
      check(not D.arranging(), "B: done")
    end
    -- (the arrangement as it was)
    Set.set("dockApps", nil)
    Set.set("homeApps", nil)
    st.grid, st.dock = grid0, dock0
    st.cursor, st.dockCursor, st.focus = 1, 1, "grid"
  end
  Env.setWallpaper("classic")
  if Set.cache then
    if savedSettings then Set.cache:write("settings.lua", savedSettings) else Set.cache:delete("settings.lua") end
  end
  check(I18n.code() == "en", "(back to English and Classic)")
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
  check(st.sheet == "about", "About WoobOS")
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

  -- WoobPad: START, its row, the home screen, the apps (each one), the notifications, B: the
  -- START menu again
  local Wt, Nt = X._test.pad, X._test.notify
  local StartMenu = require("src.ui.game3.start_menu")

  check(waitFor(function() return Sh.free(game) end, 900), "the player free in the field")
  U.tap(game, "start")
  check(waitFor(function() return StartMenu.isOpen() end, 120), "START: the menu")
  local row
  for i, e in ipairs(StartMenu.ENTRIES or {}) do if e.id == "woob_watch" then row = i end end
  local nextId = row and StartMenu.ENTRIES[row + 1] and StartMenu.ENTRIES[row + 1].id
  check(nextId == "exit" or nextId == "mods", "the pad's row in it, above EXIT (or the engine's MODS)")
  U.wait(10)
  shot("w0_start_menu")
  if row then
    StartMenu.cursor = row
    U.tap(game, "a")
    check(waitFor(function() return Wt.isOpen() end, 120), "chosen: WoobPad")
    U.wait(40)
    shot("w1_pad_home")
    local ws = Wt.state()
    -- (the draw's garbage on the home screen, warmed up first)
    local wdraw, wKb, wN = Wt.draw, 0, 0
    U.wait(60)
    Wt.draw = function(...)
      local was = collectgarbage("isrunning")
      collectgarbage("stop")
      local kb0 = collectgarbage("count")
      wdraw(...)
      wKb, wN = wKb + (collectgarbage("count") - kb0), wN + 1
      if was then collectgarbage("restart") end
    end
    U.wait(120)
    Wt.draw = wdraw
    log(("  the pad's draw: %.3f KB per frame over %d frames"):format(wKb / math.max(1, wN), wN))
    check(wKb / math.max(1, wN) < 0.5, "the pad's draw makes next to no garbage")
    local list = {}
    for _, a in ipairs(ws.grid) do list[#list + 1] = a end
    for _, a in ipairs(ws.dock) do list[#list + 1] = a end
    for _, app in ipairs(list) do
      if app.window then
        Wt.openApp(app.id)
        waitFor(function() return Wt.window() ~= nil end, 600)
        U.wait(40)
        shot("w3_pad_" .. app.id)
        check(Wt.window() ~= nil and not ws.winFailed, app.id .. " on the pad")
        Wt.closeWindow()
        waitFor(function() return ws.zoom == nil end, 600)
      end
    end
    U.wait(10)
    Wt.sheet("notes")
    U.wait(20)
    shot("w4_pad_notes")
    U.tap(game, "b"); U.wait(6)
    check(ws.sheet == nil, "B: the notifications go")
    U.tap(game, "b"); U.wait(10)
    check(not Wt.isOpen() and StartMenu.isOpen(), "B on the home screen: put away, the START menu again")
    U.tap(game, "b")
    waitFor(function() return not StartMenu.isOpen() end, 120)
  end
  -- a notification over the field; a tap on it opens the pad on that app
  check(waitFor(function() return Sh.free(game) end, 600), "the field again")
  Nt.push("outbid", { name = "PIKACHU", sp = require("src.core.game3.pokemon").speciesFromNational(25) })
  check(waitFor(function() return Nt.fieldRect() ~= nil end, 120), "a notification: its banner over the field")
  U.wait(30)
  shot("w5_field_banner")
  local fr = Nt.fieldRect()
  if fr then
    Sh.pointer({ id = 1, phase = "pressed", x = fr[1] + fr[3] / 2, y = fr[2] + fr[4] / 2 })
    check(waitFor(function() return Wt.window() ~= nil end, 120) and Wt.state().winApp.id == "auction",
      "tapped: WoobPad, on R-Bay")
    U.wait(40)
    shot("w6_banner_rbay")
    Wt.state().ctx.done()
    check(waitFor(function() return Sh.free(game) end, 120), "closed: the field")
  end

  -- the Town Map and the Fly map: the 3D map in their place (drawn in 3D, next to no garbage), B
  -- back to the field, START the game's own map
  do
    local Tm, M3 = X._test.townmap, X._test.map3d
    local frlgMap = M3.model.family() == "frlg"
    local RM = require(frlgMap and "src.ui.game3.region_map" or "src.ui.game3.rse.region_map")
    check(waitFor(function() return Sh.free(game) end, 600), "the field, for the Town Map")
    RM.show({ session = s0 })
    check(waitFor(function() return Tm.isOpen() end, 60), "the Town Map: the 3D map")
    U.wait(40)
    local mst = Tm.isOpen() and Tm.state().win.state
    check(mst and mst.three == true, "drawn in 3D (a shader, meshes, a depth canvas)")
    shot("t1_townmap")
    local tdraw, tKb, tN = Tm.draw, 0, 0
    U.wait(30)
    Tm.draw = function(...)
      local was = collectgarbage("isrunning")
      collectgarbage("stop")
      local kb0 = collectgarbage("count")
      tdraw(...)
      tKb, tN = tKb + (collectgarbage("count") - kb0), tN + 1
      if was then collectgarbage("restart") end
    end
    U.wait(90)
    Tm.draw = tdraw
    log(("  the 3D map's draw: %.3f KB per frame over %d frames"):format(tKb / math.max(1, tN), tN))
    check(tKb / math.max(1, tN) < 0.5, "the 3D map's draw makes next to no garbage")
    U.tap(game, "l")
    game.input.state.l = true
    U.wait(30)
    game.input.state.l = false
    U.wait(20)
    shot("t2_townmap_turned")
    U.tap(game, "b")
    check(waitFor(function() return not Tm.isOpen() end, 60) and waitFor(function() return Sh.free(game) end, 120),
      "B: back to the field")
    local closedWith = "no"
    RM.show({ session = s0, mode = "fly", onPick = function() end, onClose = function(v) closedWith = v end })
    check(waitFor(function() return Tm.isOpen() end, 60), "the Fly map: the 3D map")
    U.wait(40)
    shot("t3_flymap")
    U.tap(game, "b")
    check(waitFor(function() return not Tm.isOpen() end, 60) and closedWith ~= "no", "B: closed as the game's own")
    -- (START: the game's own map, handed the same options; a stand-in here)
    local w = rawget(RM, "__woobOs")
    local realOrig, handed = w.orig, nil
    w.orig = function(o) handed = o end
    local opts = { session = s0 }
    waitFor(function() return Sh.free(game) end, 120)
    RM.show(opts)
    waitFor(function() return Tm.isOpen() end, 60)
    U.wait(20)
    U.tap(game, "start")
    check(waitFor(function() return handed == opts end, 60) and not Tm.isOpen(), "START: the game's own map")
    w.orig = realOrig
    waitFor(function() return Sh.free(game) end, 120)
  end

  -- the PokéNav (Ruby / Sapphire / Emerald): its Match Call / Trainer's Eyes and Condition open our
  -- Phone and Condition full screen; B is the PokéNav's menu again
  if X._test.phone and X._test.phone.family() then
    local Tm2, Ph2 = X._test.townmap, X._test.phone
    local Flags2, Space2 = require("src.core.game3.scripting.flags"), require("src.core.game3.scripting.space")
    local C2 = require("src.core.game3.constants").of(require("src.core.game3.profile").forSession(s0).id)
    local set = {}
    local function setF(name)
      local id = C2:flag(name)
      if id then
        set[#set + 1] = { id, Flags2.getFlag(Space2.store, nil, id) }
        pcall(Flags2.setFlag, Space2.store, nil, id, true)
      end
    end
    setF("FLAG_SYS_POKENAV_GET")
    local emeraldNav = Ph2.family() == "emerald"
    if emeraldNav then
      setF("FLAG_ADDED_MATCH_CALL_TO_POKENAV")
      setF("FLAG_ENABLE_ROXANNE_MATCH_CALL")
    else
      local man = require("src.ui.game3.rs.pokenav.gfx").manifest("pokenav_detail")
      local id = 0x500 + man.leaders[0].opponentId
      set[#set + 1] = { id, Flags2.getFlag(Space2.store, nil, id) }
      pcall(Flags2.setFlag, Space2.store, nil, id, true)
    end
    check(waitFor(function() return Sh.free(game) end, 600), "the field, for the PokéNav")
    require("src.ui.game3.screens").get("pokenav", s0).show({ session = s0, game = game })
    U.wait(120)
    U.tap(game, "down"); U.wait(8)
    U.tap(game, "down"); U.wait(8)
    U.tap(game, "a")
    check(waitFor(function() return Tm2.isOpen() end, 300) and Tm2.state().ctx.app == "phone",
      emeraldNav and "Match Call: our Phone" or "Trainer's Eyes: our Phone")
    U.wait(30)
    shot("n1_phone")
    local nKb = 0
    if Tm2.isOpen() then
      local tdraw, kb, n = Tm2.draw, 0, 0
      U.wait(20)
      Tm2.draw = function(...)
        local was = collectgarbage("isrunning")
        collectgarbage("stop")
        local kb0 = collectgarbage("count")
        tdraw(...)
        kb, n = kb + (collectgarbage("count") - kb0), n + 1
        if was then collectgarbage("restart") end
      end
      U.wait(90)
      Tm2.draw = tdraw
      nKb = kb / math.max(1, n)
    end
    log(("  the Phone's draw: %.3f KB per frame"):format(nKb))
    check(nKb < 0.5, "the Phone's draw makes next to no garbage")
    U.tap(game, "b")
    check(waitFor(function() return not Tm2.isOpen() end, 120), "B: the PokéNav again")
    U.wait(80)
    U.tap(game, "up"); U.wait(8)
    U.tap(game, "a"); U.wait(60)
    U.tap(game, "a")
    check(waitFor(function() return Tm2.isOpen() end, 300) and Tm2.state().ctx.app == "condition", "Condition: ours")
    U.wait(30)
    shot("n2_condition")
    U.tap(game, "b")
    check(waitFor(function() return not Tm2.isOpen() end, 120), "B: the PokéNav again")
    U.wait(60)
    shot("n3_pokenav_back")
    for _ = 1, 6 do U.tap(game, "b"); U.wait(20) end
    waitFor(function() return Sh.free(game) end, 600)
    for _, f in ipairs(set) do pcall(Flags2.setFlag, Space2.store, nil, f[1], f[2] == true) end
  end

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
    if shape[1] == "w16x9" or shape[1] == "portrait" then
      for _, id in ipairs({ "storage", "items", "mail", "auction", "mart", "slots", "gts", "map" }) do
        for i, app in ipairs(st.dock) do if app.id == id then D.launch("dock", i) end end
        for i, app in ipairs(st.grid) do if app.id == id then D.launch("grid", i) end end
        waitFor(function() return D.window() ~= nil end, 600)
        U.wait(40)
        shot("d9_" .. shape[1] .. "_" .. id)
        check(D.window() ~= nil and not st.winFailed, id .. " draws " .. shape[1])
        D.closeWindow()
        waitFor(function() return st.zoom == nil end, 600)
      end
    end
  end
  love.window.setMode(W0, H0, flags)
  if love.resize then pcall(love.resize, W0, H0) end
  U.wait(10)
  D.state().ctx.logoff()
  waitFor(function() return not D.isOpen() end, 60)

  -- the pad in a tall window
  love.window.setMode(430, 900, flags)
  if love.resize then pcall(love.resize, 430, 900) end
  U.wait(10)
  -- (a party lent for the face's icons, made in a throwaway session; last: a party in the field
  -- brings out another mod's follower, which stands in front of the PC after)
  local partyW0 = s0.party
  do
    local PokeW = require("src.core.game3.pokemon")
    local tmp = { party = {}, name = "WOS", trainerId = s0.trainerId, dex = { seen = {}, owned = {}, caught = {} } }
    for _, nat in ipairs({ 25, 6, 9, 130 }) do Party.giveMon(tmp, PokeW.speciesFromNational(nat), 30) end
    if tmp.party[2] then tmp.party[2].hp = math.floor((tmp.party[2].maxHp or 10) * 0.4) end
    s0.party = tmp.party
  end
  Sh.openWatch(s0)
  U.wait(40)
  shot("w7_pad_portrait")
  if Wt.isOpen() then Wt.state().ctx.done() end
  s0.party = partyW0
  love.window.setMode(W0, H0, flags)
  if love.resize then pcall(love.resize, W0, H0) end
  U.wait(10)
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
