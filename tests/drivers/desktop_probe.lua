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
  stor.currentBox = 1
  U.tap(game, "down"); U.wait(4)
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
    -- the pad's Poké Ball: dropped on, its button glowing red once it's had time
    check(waitFor(function() return D.ballState() == "drop" or D.ballState() == "on" end, 600), "the Poké Ball drops onto the pad")
    if D.ballState() == "drop" then shot("d2_ball_drop") end
    check(waitFor(function() return D.ballState() == "on" end, 600), "it lands")
    local onAt = love.timer.getTime()
    waitFor(function() return love.timer.getTime() - onAt > D.BALL.glow + 0.2 end, 1200)
    shot("d2_ball_glow")
    Bx.forget(lent[1])
    bst.area, bst.bi = "box", 1
    U.wait(10)
    local pv = Bx.info(lent[1], X._test.env.T)
    check(pv and pv.dmax == 6 and pv.gmax == true, "the preview: Dynamax Level 6, the G-Max Factor")
    shot("d2_boxes")
    Bx.dynamax = dynamax0
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
    -- a party Pokémon into the box and back: a Poké Ball across the pad
    bst.area, bst.pi = "party", 3
    U.tap(game, "a"); U.wait(4)
    bst.area, bst.bi = "box", 30
    U.tap(game, "a"); U.wait(2)
    check(#s0.party == 2 and stor.boxes[1].mons[30] ~= nil, "deposit: party to box")
    check(waitFor(function()
      local n, _, _, _, kind = D.padState()
      return n > 0 and kind == "ball" and love.timer.getTime() - D.state().padQ[1].t0 >= 0.45
    end, 600), "a Poké Ball crosses the pad")
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
    local back = waitFor(function()
      if D.window() then return true end
      U.tap(game, "b")
      U.wait(20)
      return D.window() ~= nil
    end, 30)
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
  -- the window's draw garbage
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
    -- the window's draw garbage
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
      for _, id in ipairs({ "storage", "items", "mail" }) do
        for i, app in ipairs(st.dock) do if app.id == id then D.launch("dock", i) end end
        waitFor(function() return D.window() ~= nil end, 600)
        U.wait(10)
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
