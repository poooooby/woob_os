-- Driver: a showcase of WoobOS, one scene per feature, stepped by hand. A new game (nothing is saved
-- unless you save it) with a party, boxes, items, money and the rest made up for the show.
--   Page Down  the next scene     Page Up  the one before     Home  everything made up again, from the top
-- Between those it's the real thing: play with each scene on the keyboard, a controller or the mouse.
-- Scenes this game hasn't got are left out (Oak's PC is FireRed / LeafGreen's, the storms Emerald's, PC
-- Games needs that mod switched on).
--
--   POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_DRIVER_PACED=1 \
--   POKEPORT_DRIVER=mods/woob_os/tests/drivers/showcase.lua "/c/Program Files/LOVE/lovec.exe" .
--
-- SHOWCASE_AUTO=<dir> walks every scene by itself through the same keys, a screenshot of each in <dir>
-- and a log (driver.log), then quits.

local CENTER = { frlg = "VIRIDIAN_CITY_POKEMON_CENTER_1F", rse = "OLDALE_TOWN_POKEMON_CENTER_1F" }
local HOUSE = "LITTLEROOT_TOWN_BRENDANS_HOUSE_2F"
local NOOP = function() end

local function body(game, log, auto)
  local U = require("tests.drivers.util")
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
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "WOS", gender = 0 })
  U.wait(90)

  local Runtime, Map, Warp = require("src.core.game3.runtime"), require("src.core.game3.map"), require("src.core.game3.warp")
  local Stack, Profile = require("src.ui.game3.stack"), require("src.core.game3.profile")
  local PcMenu, Message = require("src.ui.game3.pc_menu"), require("src.ui.game3.message")
  local StartMenu = require("src.ui.game3.start_menu")
  local Storage, Bag, Party = require("src.core.game3.storage"), require("src.core.game3.bag"), require("src.core.game3.party")
  local Poke, Mail = require("src.core.game3.pokemon"), require("src.core.game3.mail")
  local Flags, Space = require("src.core.game3.scripting.flags"), require("src.core.game3.scripting.space")
  local s0 = Runtime.getSession()
  local X = game.mods.exports.woob_os
  local T = X and X._test
  if not (T and T.desktop) then log("FAIL woob_os has no _test.desktop"); return end
  local D, Sh, Wt, Tm, Nt, M3 = T.desktop, T.shell, T.pad, T.townmap, T.notify, T.map3d
  local gid = Sh.gameId()
  local frlg = gid == "firered" or gid == "leafgreen"
  local rse, emerald = not frlg, gid == "emerald"
  local prefix = Profile.forSession(s0).map.enginePrefix
  local center, house = prefix .. CENTER[frlg and "frlg" or "rse"], prefix .. HOUSE
  local RM = require(frlg and "src.ui.game3.region_map" or "src.ui.game3.rse.region_map")
  local Rse = rse and require("src.core.game3.rse.init") or nil
  local LOC = "VAR_ABNORMAL_WEATHER_LOCATION"

  -- ------- what the show runs on (again on Home)

  local function nat(n) return Poke.speciesFromNational(n) end
  local function make(list, level)
    local out = {}
    for _, n in ipairs(list) do
      local tmp = { party = {} }
      local ok, _, m = Party.giveMon(tmp, nat(n), level + #out)
      if ok and m then out[#out + 1] = m end
    end
    return out
  end
  local function setFlag(name)
    local id = require("src.core.game3.constants").of(Profile.forSession(s0).id):flag(name)
    if id then pcall(Flags.setFlag, Space.store, nil, id, true) end
  end
  local function seed()
    s0.money = 999999
    s0.party = make({ 25, 6, 9, 3, 94, 143 }, 42)
    if s0.party[2] then s0.party[2].hp = math.floor((s0.party[2].maxHp or 10) * 0.4) end
    local stor = Storage.ensure(s0)
    for b = 1, 3 do stor.boxes[b].mons = {} end
    local boxed = make({ 1, 4, 7, 133, 150, 151, 152, 155, 158, 175, 249, 250, 280, 380, 381 }, 20)
    for i, m in ipairs(boxed) do stor.boxes[1].mons[i * 2 - 1] = m end
    if boxed[4] then boxed[4].isShiny = true end
    if boxed[6] then boxed[6].isShiny = true end
    stor.currentBox = 1
    stor.items = { { id = 13, qty = 5 }, { id = 2, qty = 12 }, { id = 68, qty = 3 } }
    s0.bag = Bag.new()
    if require("src.core.game3.items_data").ensureModel then require("src.core.game3.items_data").ensureModel(s0) end
    for _, it in ipairs({ { 1, 3 }, { 2, 20 }, { 4, 40 }, { 13, 12 }, { 21, 6 }, { 68, 9 }, { 121, 2 } }) do
      pcall(Bag.add, s0.bag, it[1], it[2])
    end
    local rec = Mail.pool(s0)[7]
    Mail.clear(rec)
    rec.itemId, rec.playerName, rec.species = 121, "MOM", nat(25)
    rec.words[1], rec.words[2], rec.words[4] = 0x200, 0x201, 0x400
    local function fame(n, lv)
      return { species = nat(n), level = lv, nickname = n == 25 and "SPARKY" or Poke.name(nat(n)), trainerId = 4242, personality = n * 7 }
    end
    s0.hallOfFameTeams = { { fame(1, 40), fame(4, 41), fame(7, 42) },
                           { fame(25, 70), fame(6, 71), fame(9, 72), fame(130, 73), fame(150, 74), fame(143, 75) } }
    s0.gameStats = s0.gameStats or {}
    s0.gameStats[10] = 2
    if rse then
      local RC = require("src.core.game3.rse.ribbons")
      for _, k in ipairs({ "cool", "beauty", "cute", "smart", "tough" }) do RC.set(s0.party[1], k, 4) end
      for _, k in ipairs({ "champion", "winning", "victory", "artist", "effort" }) do RC.set(s0.party[1], k, 1) end
      RC.set(s0.party[2], "cool", 2)
      RC.set(s0.party[3], "champion", 1)
      s0.party[1].contest = { cool = 180, beauty = 90, cute = 240, smart = 60, tough = 120, sheen = 70 }
      s0.party[2].contest = { cool = 250, beauty = 40, cute = 10, smart = 110, tough = 200, sheen = 20 }
      s0.party[3].contest = { cool = 70, beauty = 230, cute = 90, smart = 180, tough = 30, sheen = 120 }
      local Pk = require("src.core.game3.rse.pokeblock")
      local case = Pk.clearAll(s0)
      for i, c in ipairs({ { 1, 30 }, { 2, 24 }, { 3, 18 }, { 4, 36 }, { 5, 22 }, { 14, 40 } }) do
        local b = case[i]
        b.color, b.spicy, b.dry, b.sweet, b.bitter, b.sour, b.feel = c[1], 20 + i, 10, 30 - i, 5, 12, c[2]
      end
      s0.decorationInventory, s0.playerRoomDecorations, s0.playerRoomDecorationPositions = nil, nil, nil
      local Inv, Core = require("src.core.game3.rse.decoration_inventory"), require("src.core.game3.rse.decoration")
      for cat = 0, 7 do
        local n = 0
        for d = 1, Core.NUM_DECORATIONS do
          if n < (cat == 6 and 14 or 6) and Inv.categoryOf(d) == cat then Inv.add(d, s0); n = n + 1 end
        end
      end
      setFlag("FLAG_SYS_POKENAV_GET")
      if T.phone and T.phone.family() == "emerald" then
        setFlag("FLAG_ADDED_MATCH_CALL_TO_POKENAV")
        setFlag("FLAG_ENABLE_ROXANNE_MATCH_CALL")
      elseif T.phone and T.phone.family() then
        local man = require("src.ui.game3.rs.pokenav.gfx").manifest("pokenav_detail")
        pcall(Flags.setFlag, Space.store, nil, 0x500 + man.leaders[0].opponentId, true)
      end
    end
  end

  -- ------- getting to a clean start for a scene

  local function goTo(mapId, x, y)
    if Map.current == mapId and not Warp.isBusy() then return end
    Warp.request(nil, game, mapId, x, y, "up", {})
    if not waitFor(function() return Map.current == mapId and not Warp.isBusy() end, 900) then
      error("couldn't reach " .. mapId)
    end
    U.wait(20)
  end

  -- everything open, shut, whatever the player was in the middle of
  local function clearAll()
    if Tm.isOpen() then pcall(Tm.close) end
    if Wt.isOpen() then pcall(function() Wt.state().ctx.done() end) end
    if D.isOpen() then pcall(function() D.state().ctx.logoff() end) end
    if rse then pcall(require("src.ui.game3.rse.decoration").reset) end
    if StartMenu.isOpen() then pcall(StartMenu.close, true) end
    if Message.isOpen and Message.isOpen() and Message.close then pcall(Message.close) end
    Stack.clear()
    pcall(require("src.ui.game3.fade").clear)
    if not waitFor(function() return Sh.free(game) end, 300) then log("  (the field isn't free yet)") end
  end

  local function openDesktop(mode, skip)
    Sh.forget()
    if mode == "bedroom" then
      PcMenu.show({ session = s0, startMode = "player_pc", bedroom = true, closeOnExit = true, onClose = NOOP })
    else
      PcMenu.show({ session = s0, startMode = "select", closeOnExit = true, onClose = NOOP })
    end
    if not D.isOpen() then error("the desktop didn't open") end
    if skip then D.skipBoot() end
  end

  -- the desktop in that mode, nothing over it; kept open from one scene to the next
  local function desk(mode)
    if not (D.isOpen() and D.state().ctx.mode == mode) then
      clearAll()
      if mode == "bedroom" then goTo(house, 3, 5) else goTo(center, 7, 8) end
      openDesktop(mode, true)
      U.wait(10)
    end
    if D.booting() then D.skipBoot() end
    local r = D.state()
    r.sheet, r.menuOpen, r.edit, r.carry = nil, false, nil, nil
    return r
  end
  local function deskBare(mode)
    local r = desk(mode)
    if D.window() then
      D.closeWindow()
      waitFor(function() return D.window() == nil and r.zoom == nil end, 120)
    end
    return r
  end
  local function field()
    clearAll()
    goTo(center, 7, 8)
  end

  -- ------- the scenes

  local function app(id, title, words, mode, after)
    return { title = title, words = words, enter = function()
      desk(mode or "select")
      if not D.openApp(id) then error("no app " .. id) end
      if not waitFor(function() return D.window() ~= nil end, 240) then error(id .. " didn't open") end
      if after then after(D.window()) end
    end }
  end
  local function storm(at, title, words)
    return { title = title, words = words, enter = function()
      desk("select")
      Rse.setVar(LOC, at, s0)
      D.openApp("map")
      waitFor(function() return D.window() ~= nil end, 240)
      local W = D.window()
      if not waitFor(function() return W.state.storm.on end, 180) then error("no storm") end
      W.focus(W.state.storm.place)
    end, leave = function()
      Rse.setVar(LOC, 0, s0)
      M3.lastStorm = nil
    end }
  end

  local all = {
    { title = "The W boot", words = "The PC switching on. Page Up and Page Down again to replay it.", enter = function()
      clearAll()
      goTo(center, 7, 8)
      openDesktop("select", false)
    end },
    { title = "The desktop", words = "An iMac-like monitor: a home grid, a dock, a menu bar. Arrow keys and A.", enter = function()
      deskBare("select")
    end },
    { title = "The W menu", words = "The menu bar's W: About, Notifications, Log Off.", enter = function()
      local r = deskBare("select")
      r.menuOpen, r.menuCursor = true, 1
    end },
    { title = "About WoobOS", words = "The system's About sheet.", enter = function()
      deskBare("select")
      D.sheet("about")
    end },
    { title = "Arranging apps", words = "SELECT or a long press: drag apps round the grid and into the dock.", enter = function()
      deskBare("select")
      U.tap(game, "select")
      U.wait(4)
    end },
    { title = "Log Off", words = "The power button's sheet.", enter = function()
      deskBare("select")
      D.sheet("logoff")
    end },

    app("storage", "Boxes", "Party and every box, with Select, Swap and Drag. The Poke Ball on the shelf holds what you carry. Two shinies sparkle in the grid."),
    app("items", "Items", "Your Bag and the PC's items side by side. The pad under the monitor shows them going across."),
    app("mail", "Mail", "An inbox for the PC's mailbox: read a letter, take it to the Bag, give it to a Pokemon."),
    app("mart", "Mart", "Buy and sell from the PC. More stock with each Gym Badge (all eight lent here).", nil, function(W)
      W.state.badges = 8
    end),
    app("gts", "GTS", "The Global Trade Station: Wonder Trade, listings, and your own deposits."),
    app("auction", "R-Bay", "Team Rocket's auctions for Pokemon, with rival bidders and a Hot Auction."),
    app("slots", "Rocket Slots", "A five-reel video slot: wilds, free spins, Auto, and a prize corner."),
    app("phone", "Phone", "Match Call's contacts, recents and favourites (Trainer's Eyes on Ruby and Sapphire)."),
    app("condition", "Condition", "The contest conditions on a radar. Compare two Pokemon and feed them Pokeblocks."),
    app("ribbons", "Ribbons", "A display case of every Pokemon with Ribbons, and what each one is for."),
    app("hall", "Hall of Fame", "Your champion teams as a trophy case. L and R change team."),
    app("oak", "Oak's PC", "The Kanto Pokedex as a dashboard, with Professor Oak's rating.", nil, function(W)
      local map = W.state.rating.map
      for i = 1, 151 do map[i] = (i % 3 == 0 and 2) or (i % 3 == 1 and 1) or 0 end
    end),
    app("pcgames", "PC Games", "The PC Games mod's games, crisp, across the monitor."),
    app("store", "App Store", "Take R-Bay, Slots, the GTS, the Mart or another mod's app off the home screen, or get it back."),
    app("settings", "Settings", "Language, wallpapers, and more. Careful: changes here are your real settings."),
    { title = "Decorate", words = "A catalogue of your decorations, in the real bedroom. Place in Room hands you the game's cursor.", enter = function()
      if not (D.isOpen() and D.state().ctx.mode == "bedroom") then
        clearAll()
        goTo(house, 3, 5)
      end
      local Core, SBm, Inv = require("src.core.game3.rse.decoration"), require("src.core.game3.rse.secret_base"),
        require("src.core.game3.rse.decoration_inventory")
      local Coll, grid = require("src.core.game3.collision"), SBm.fieldGrid()
      local w, h = grid.size()
      local room = Core.context(s0, true)
      for i = 1, room.size do room.items[i], room.pos[i] = 0, 0 end
      local put = 0
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          local b = Coll.behavior(x, y)
          if put < 2 and (Core.isBeh(b, "HOLDS_SMALL_DECORATION") or Core.isBeh(b, "HOLDS_LARGE_DECORATION")) then
            put = put + 1
            room.items[put], room.pos[put] = Inv.inventories(s0)[6][put + 2], Core.encodePos(x, y)
          end
        end
      end
      SBm.hideDecorationSprites(s0)
      SBm.initDecorationSprites(0, s0)
      desk("bedroom")
      D.openApp("decorate")
      waitFor(function() return D.window() ~= nil end, 240)
    end },

    app("map", "The 3D map", "The region as a little model you can turn, tilt and zoom. It follows your device's clock."),
    { title = "The flat map", words = "SELECT: the game's own Town Map picture, north up.", enter = function()
      desk("select")
      D.openApp("map")
      waitFor(function() return D.window() ~= nil end, 240)
      U.wait(4)
      U.tap(game, "select")
    end },
    storm(11, "Kyogre's rainstorm", "Over the route the Weather Institute names. Shown here on Route 125."),
    storm(3, "Groudon's sandstorm", "The same for Groudon. It moves with each report and clears when caught. Route 115 here."),
    { title = "The Town Map", words = "The game's own Town Map opens as the 3D map. START for the classic one.", enter = function()
      field()
      RM.show({ session = s0 })
      waitFor(function() return Tm.isOpen() end, 60)
    end },
    { title = "The Fly map", words = "Fly picks a town on the 3D map. (Nothing flies in the showcase.)", enter = function()
      field()
      RM.show({ session = s0, mode = "fly", onPick = NOOP, onClose = NOOP })
      waitFor(function() return Tm.isOpen() end, 60)
    end },

    { title = "WoobPad in the START menu", words = "Its own row in the START menu, under BAG.", enter = function()
      field()
      U.tap(game, "start")
      if not waitFor(function() return StartMenu.isOpen() end, 120) then error("no START menu") end
      for i, e in ipairs(StartMenu.ENTRIES or {}) do if e.id == "woob_watch" then StartMenu.cursor = i end end
    end },
    { title = "WoobPad", words = "The apps anywhere in the world, over the field.", enter = function()
      field()
      Sh.openWatch(s0)
      waitFor(function() return Wt.isOpen() end, 120)
    end },
    { title = "Notifications", words = "The list on WoobPad: outbids, trades, calls.", enter = function()
      field()
      Nt.push("outbid", { name = "PIKACHU", sp = nat(25) }, true)
      Nt.push("gts", { name = "EEVEE", sp = nat(133), who = "KAI" }, true)
      Sh.openWatch(s0)
      waitFor(function() return Wt.isOpen() end, 120)
      U.wait(10)
      Wt.sheet("notes")
    end },
    { title = "A banner over the field", words = "Notifications drop in while you walk. Tap one to open that app on WoobPad.", enter = function()
      field()
      Nt.push("outbid", { name = "PIKACHU", sp = nat(25) })
    end, every = 6, tick = function()
      if Sh.free(game) then Nt.push("outbid", { name = "PIKACHU", sp = nat(25) }) end
    end },
  }

  local WHEN = {
    ["Oak's PC"] = function() return frlg end,
    ["PC Games"] = function() return T.pcgames ~= nil and T.pcgames.available() end,
    ["Phone"] = function() return rse end, ["Condition"] = function() return rse end, ["Ribbons"] = function() return rse end,
    ["Decorate"] = function() return rse end,
    ["Kyogre's rainstorm"] = function() return emerald end, ["Groudon's sandstorm"] = function() return emerald end,
  }
  local scenes = {}
  for _, sc in ipairs(all) do
    local w = WHEN[sc.title]
    local ok, yes = true, true
    if w then ok, yes = pcall(w) end
    if ok and yes then scenes[#scenes + 1] = sc else log("  left out here: " .. sc.title) end
  end

  -- ------- the keys, and the caption over everything

  local NAV = { pageup = -1, pagedown = 1, home = 0 }
  local delta, restart = 0, false
  local keyWas = love.keypressed
  love.keypressed = function(key, scancode, isrepeat)
    local d = NAV[key]
    if d == nil then return keyWas(key, scancode, isrepeat) end
    if isrepeat then return end
    if d == 0 then restart = true else delta = delta + d end
  end

  local CAPTION_FOR, CAPTION_FADE = 5, 0.6   -- seconds shown, then gone (a scene's trouble stays)
  local cur, trouble, shownAt = 0, nil, 0
  local titleFont, wordFont
  local drawWas = love.draw
  love.draw = function(...)
    drawWas(...)
    local sc = scenes[cur]
    if not sc then return end
    local fade = trouble and 1 or math.max(0, 1 - math.max(0, love.timer.getTime() - shownAt - CAPTION_FOR) / CAPTION_FADE)
    if fade <= 0 then return end
    local G = love.graphics
    titleFont = titleFont or G.newFont(17)
    wordFont = wordFont or G.newFont(13)
    local w, h = G.getDimensions()
    local bw = math.min(w - 16, 860)
    local bx, by, bh = (w - bw) / 2, h - 58, 50
    G.push("all")
    G.origin()
    G.setScissor()
    G.setColor(0.05, 0.06, 0.1, 0.82 * fade)
    G.rectangle("fill", bx, by, bw, bh, 10, 10)
    G.setColor(1, 1, 1, fade)
    G.setFont(titleFont)
    G.print(sc.title, bx + 14, by + 5)
    local nav = cur .. " / " .. #scenes .. "   PgUp  PgDn   Home: restart"
    G.setFont(wordFont)
    G.setColor(0.72, 0.76, 0.86, fade)
    G.print(nav, bx + bw - 14 - wordFont:getWidth(nav), by + 9)
    if trouble then G.setColor(1, 0.5, 0.45, 1) else G.setColor(0.86, 0.89, 0.95, fade) end
    G.print(trouble or sc.words, bx + 14, by + 28)
    G.pop()
  end

  local function show(i)
    local prev = scenes[cur]
    if prev and prev.leave then pcall(prev.leave) end
    cur, trouble, shownAt = i, nil, love.timer.getTime()
    local sc = scenes[i]
    log(("scene %d/%d: %s"):format(i, #scenes, sc.title))
    local ok, err = xpcall(sc.enter, debug.traceback)
    if not ok then
      log("FAIL " .. sc.title .. ": " .. tostring(err))
      trouble = "This scene couldn't open: " .. tostring(err):match("^[^\n]*")
    end
  end

  -- what the keys asked for since last time (several Page Downs while a scene opened add up)
  local function pump()
    if restart then
      restart, delta = false, 0
      clearAll()
      seed()
      cur = 0
      show(1)
    elseif delta ~= 0 then
      local to = (cur - 1 + delta) % #scenes + 1
      delta = 0
      show(to)
    end
  end

  seed()
  show(1)

  if auto then
    local fails = 0
    local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
    local function settle(t)
      local untilT = love.timer.getTime() + t
      waitFor(function() return love.timer.getTime() > untilT end, 600)
    end
    local function shoot()
      local name = string.format("%02d_%s.png", cur, scenes[cur].title:gsub("[^%w]+", "_"))
      U.shot(game, auto .. "/" .. name)
    end
    settle(3.2)
    shoot()
    for i = 2, #scenes do
      love.keypressed("pagedown", "pagedown", false)
      pump()
      check(cur == i and trouble == nil, "Page Down: " .. scenes[i].title)
      check(not (D.isOpen() and D.state().winFailed), "  it draws")
      settle(1.5)
      shoot()
    end
    love.keypressed("pagedown", "pagedown", false)
    pump()
    check(cur == 1, "Page Down from the last: the first again")
    settle(1)
    love.keypressed("pageup", "pageup", false)
    pump()
    check(cur == #scenes, "Page Up from the first: the last")
    settle(1)
    love.keypressed("pagedown", "pagedown", false)
    love.keypressed("pagedown", "pagedown", true)
    love.keypressed("pagedown", "pagedown", false)
    pump()
    check(cur == 2, "two presses add up, a held key's repeats don't")
    -- (the player's own keys still reach the scene)
    deskBare("select")
    local r2 = D.state()
    r2.focus, r2.cursor = "grid", 1
    U.wait(30)
    love.keypressed("right", "right", false)
    U.wait(3)
    love.keyreleased("right")
    U.wait(3)
    check(r2.cursor == 2, "a real key press moves the desktop's cursor (" .. tostring(r2.cursor) .. ")")
    s0.money = 1
    love.keypressed("home", "home", false)
    pump()
    check(cur == 1 and s0.money == 999999, "Home: from the top, everything made up again")
    settle(0.5)
    log(("%d failures"):format(fails))
    love.keypressed, love.draw = keyWas, drawWas
    return
  end

  local lastTick = love.timer.getTime()
  while true do
    U.wait(1)
    pump()
    local sc = scenes[cur]
    if sc.tick and love.timer.getTime() - lastTick >= sc.every then
      lastTick = love.timer.getTime()
      pcall(sc.tick)
    end
  end
end

return function(game)
  local auto = os.getenv("SHOWCASE_AUTO")
  local logFile = auto and io.open(auto .. "/driver.log", "w")
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    print("[showcase]", line)
    if logFile then logFile:write(line, "\n"); logFile:flush() end
  end
  local ok, err = xpcall(function() body(game, log, auto) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  log("DONE")
  if logFile then logFile:close() end
  love.event.quit()
end
