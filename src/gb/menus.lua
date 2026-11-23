-- The modern menus on the Game Boy games (src/menus.lua's for Red / Blue / Yellow and Gold / Silver / Crystal): the
-- game's own party menu, summary and Bag taken over through the screen registry. Each is a carrier of ours pushed
-- in the game's screen's place; its first update opens the modern window (Sh.openFull("menus"),
-- src/apps/menus.lua) over it, and it answers the game as its screen would:
--   the party menu   Gen 1 "PartyMenu": START's list (B pops it, then onCancel()); a battle's SWITCH and send-out
--                    (onSwitch(mon, menu), the menu kept open: menu:refuse(text) in our words box, menu:close());
--                    choosing for an item, a trade, the Day Care (pickOnly: onSwitch, the picker's animateTo /
--                    setMessage / refuse / close). Gen 2 "Gen2PartyMenu": START's (B: onCancel(), which pops it), a
--                    battle's and every other chooser (onChoose(index, mon), the caller pops it -- our state on top
--                    answers for it: list:refuse, stack:top():showItemResult, a pop by the game closes ours and takes
--                    the carrier with it)
--   the summary      Gen 1 "SummaryMenu" (one Pokémon; pops itself), Gen 2 "Gen2SummaryMenu" (one, or the party at
--                    an index; its MOVE screen; onClose(), the caller pops; screen.index where it ended)
--   the Bag          Gen 1 "BagMenu" (START's, a battle's), Gen 2 "Gen2PackMenu" (START's, a battle's, the held
--                    item's GIVE; the mart's and the item PC's, which hold their pack, stay the game's). USE is the
--                    game's own bag, built off the stack on that item (Gen 1: its choose, and in the field its USE
--                    box's USE; Gen 2: useSelected), so every item does what it does there
-- While one of ours is up, the game's own pieces come into the same window: a party list it asks for (an item's
-- target) opens as a page over ours, a state of ours standing in for it on the stack (`woobOsAbove`); its text
-- boxes (src.render.TextBox, wrapped once per process) are our words box, a state of ours standing in until they're
-- read. With the option off, a link battle, or anything failing: the game's own screen.
--
--   Mn = GbMenus(H, Gd, deps)   deps: Sh, on(kind, battle) -> bool, party (src/gb/party.lua's), bag (src/gb/bag.lua's),
--                               screens, log
--   Mn.install() (load: the screens and the text boxes) ; Mn.isOpen() ; Mn.cur() (the tests')

return function(H, Gd, deps)
  local Mn = {}
  local gen, engine = H.gen, H.engine
  local Sh, Pt, Bg = deps.Sh, deps.party, deps.bag
  local function log(fmt, ...) if deps.log then pcall(deps.log, fmt, ...) end end
  local function on(kind, battle) return deps.on == nil or deps.on(kind, battle) == true end
  local cur = nil
  function Mn.isOpen() return cur ~= nil end
  function Mn.cur() return cur end
  local MAP_ID = Sh.MAP_ID

  local function popIfTop(game, st)
    local stk = game and game.stack
    if stk and stk:top() == st then pcall(stk.pop, stk) end
  end
  local function removeState(game, st)
    local list = game and game.stack and game.stack.states
    if type(list) ~= "table" then return end
    for i = #list, 1, -1 do
      if list[i] == st then
        table.remove(list, i)
        return
      end
    end
  end
  local function carrierDraw(self)
    local G = love and love.graphics
    if G and self.isOpaque then
      G.setColor(0, 0, 0, 1)
      G.rectangle("fill", 0, 0, 160, 144)
      G.setColor(1, 1, 1, 1)
    end
  end
  local function win()
    local w = cur and cur.m and cur.m.win
    return w
  end

  -- (a carrier: c.open() -> true when ours opened; c.fallback(): the game's own in its place)
  local function carrierUpdate(self)
    if self.opened then
      -- (back on top with ours gone without a word: answered as closed)
      if not self.done and not (Sh.hostOpen and Sh.hostOpen()) then self.lost() end
      return
    end
    self.opened = true
    local ok, got = pcall(self.open)
    if ok and got then return end
    if not ok then log("a modern menu failed to open: %s", tostring(got)) end
    self.done = true
    if cur == self then cur = nil end
    popIfTop(self.game, self)
    if self.fallback then
      local okF, errF = pcall(self.fallback)
      if not okF then log("the game's own menu: %s", tostring(errF)) end
    end
  end
  -- (ours never carries the game's screen id: the registry stamps it, and another mod that dresses the game's own
  -- menus by it -- OmniUI -- would draw its party or bag over ours)
  local NO_ID = { __newindex = function(t, k, v) if k ~= "screenId" then rawset(t, k, v) end end }
  local function newCarrier(game, opts)
    local c = setmetatable({ isMenu = true, isOpaque = true, update = carrierUpdate, draw = carrierDraw, game = game,
                             opts = opts, woobOsMenu = true }, NO_ID)
    function c.lost()
      c.done = true
      if cur == c then cur = nil end
    end
    return c
  end

  -- (closing ours from the game's side: the window shut, nothing answered back)
  local function shut(c)
    c.done = true
    if cur == c then cur = nil end
    local h = Sh.host and Sh.host()
    local st = h and h.state and h.state()
    if st and st.ctx and st.ctx.done then pcall(st.ctx.done) end
  end
  -- (the window: open over the carrier, our state answering for it)
  local function openWindow(c, m, onClosed)
    local game = c.game
    local function closed()
      if cur == c then cur = nil end
      if c.done then return end
      c.done = true
      onClosed(m)
    end
    if not Sh.openFull("menus", game.save, closed, nil, { menu = m, chrome = false }) then return false end
    cur = c
    c.m = m
    -- (the game popping "its" screen -- our state, on top: ours closes and the carrier goes with it)
    H.forward(MAP_ID, c, function()
      shut(c)
      removeState(game, c)
    end)
    return true
  end
  local function say(c, text, after)
    local w = c.m and c.m.win
    if w and w.say and w.say(text, after) then return end
    if after then after() end
  end
  -- (an HP bar's fill, then words: the window's party, as the game's showItemResult / animateTo)
  local function hpThen(c, i, from, to, text, after)
    local w = c.m and c.m.win
    local function words()
      if text and text ~= "" then say(c, text, after) elseif after then after() end
    end
    if w and w.hp and i and from and to and from ~= to and w.hp(i, from, to, words) then return end
    words()
  end
  local function partyIndex(m, mon)
    for i, x in ipairs(m.party or {}) do if x == mon then return i end end
    return nil
  end

  -- ------- a chooser of the game's while ours is up: its list a page of the same window, a state of ours standing in
  local function innerCarrier(game, opts, m, cancel)
    local w = win()
    if not (w and w.innerParty) then return nil end
    local c = setmetatable({ isMenu = true, isOpaque = false, woobOsAbove = true, woobOsMenu = true, inner = true,
                             game = game, opts = opts, m = cur.m }, NO_ID)
    c.update = function() if game.input then Sh.feedHost(game.input) end end
    c.draw = function() end
    -- (the game took its list away)
    c.exit = function(self)
      if self.done then return end
      self.done = true
      w.innerDone()
    end
    if not w.innerParty(m, function(res)
      if res.chosen ~= nil or c.done then return end
      cancel(c)
    end) then return nil end
    return c
  end

  -- ------- the party menu

  local function party1(game, opts)
    opts = opts or {}
    local battle = type(opts.battle) == "table" and opts.battle or nil
    if battle and battle.kind == "link" then return nil end
    if opts.rows or not on("party", battle ~= nil) then return nil end
    local mode = "list"
    if opts.forceSwitch then mode = battle and "battle_faint" or "choose"
    elseif battle and opts.onSwitch and not opts.pickOnly then mode = "battle_switch"
    elseif opts.pickOnly or opts.onSwitch then mode = "choose" end
    local party = opts.party or (game.save and game.save.party) or {}
    if not party[1] then return nil end
    local m = { kind = "party", party = party, mode = mode, battle = battle ~= nil, cursor = game.partyMenuSavedIndex or 1 }
    local c
    if mode ~= "list" then
      m.onChoose = function(i, mon)
        if c.keepOpen then
          local ok, err = pcall(opts.onSwitch, mon, c)
          if not ok then log("the game's choice: %s", tostring(err)) end
        else
          if c.inner then popIfTop(game, c) else shut(c) popIfTop(game, c) end
          if opts.onSwitch then pcall(opts.onSwitch, mon) end
        end
      end
    end
    -- (asked for while ours is up -- an item's target from the game's bag: a page of the same window)
    if cur and mode ~= "list" then
      c = innerCarrier(game, opts, m, function(c0)
        popIfTop(game, c0)
        if opts.onCancel then pcall(opts.onCancel) end
      end)
      if not c then return nil end
    else
      c = newCarrier(game, opts)
      function c.open()
        if Mn.isOpen() then return false end
        return openWindow(c, m, function()
          local res = m.result or {}
          game.partyMenuSavedIndex = m.cursor or game.partyMenuSavedIndex
          popIfTop(game, c)
          if m.after then
            local ok, err = pcall(m.after)
            if not ok then log("after the party menu: %s", tostring(err)) end
            return
          end
          if res.chosen == nil and opts.onCancel then
            local ok, err = pcall(opts.onCancel)
            if not ok then log("after the party menu: %s", tostring(err)) end
          end
        end)
      end
      c.fallback = function()
        local M = engine("src.ui.PartyMenu")
        game.stack:push(M.new(game, opts))
      end
    end
    c.keepOpen = opts.keepOpen == true
    -- (the menu the game holds while it's open)
    function c:refuse(text) say(self, text) end
    function c:setMessage(text) if text and text ~= "" then say(self, text) end end
    function c:eraseCursors() end
    function c:close()
      if self.inner then popIfTop(game, self) return end
      shut(self)
      popIfTop(game, self)
    end
    function c:animateTo(mon, fromHP, onDone)
      hpThen(self, partyIndex(m, mon), fromHP, mon and mon.hp, nil, onDone)
    end
    return c
  end

  local function party2(game, opts)
    opts = opts or {}
    local battle = opts.battle == true
    local B = Pt.battleOf and Pt.battleOf(game)
    if battle and B and B.link then return nil end
    if not on("party", battle) then return nil end
    local mode = "list"
    if battle then mode = opts.battleSubmenu and "battle_switch" or "battle_faint"
    elseif not opts.submenu then mode = "choose" end
    if mode == "list" and not opts.onCancel then return nil end
    local party = opts.party or (opts.save and opts.save.party) or (game.save and game.save.party) or {}
    if not party[1] then return nil end
    local m = { kind = "party", party = party, mode = mode, battle = battle, cursor = game.partyMenuCursor or 1 }
    if mode ~= "list" then
      m.onChoose = function(i, mon)
        -- (the caller pops "the list": a state of ours on top answers for it)
        local ok, err = pcall(opts.onChoose, i, mon)
        if not ok then log("the game's choice: %s", tostring(err)) end
      end
    end
    local c
    if cur and mode ~= "list" then
      c = innerCarrier(game, opts, m, function(c0)
        if opts.onCancel then pcall(opts.onCancel) end
        popIfTop(game, c0)
      end)
      if not c then return nil end
    else
      c = newCarrier(game, opts)
      function c.open()
        if Mn.isOpen() then return false end
        return openWindow(c, m, function()
          local res = m.result or {}
          game.partyMenuCursor = m.cursor or game.partyMenuCursor
          if m.after then
            popIfTop(game, c)
            local ok, err = pcall(m.after)
            if not ok then log("after the party menu: %s", tostring(err)) end
            return
          end
          if res.chosen == nil and opts.onCancel then
            local ok, err = pcall(opts.onCancel)
            if not ok then log("after the party menu: %s", tostring(err)) end
          end
          popIfTop(game, c)
        end)
      end
      c.fallback = function()
        local M = engine("src.ui.gen2.PartyMenu")
        game.stack:push(M.new(game, opts))
      end
    end
    function c:refuse(text) say(self, text) end
    function c:showItemResult(slot, o)
      o = o or {}
      if o.sfx then H.sfx(o.sfx) end
      hpThen(self, slot, o.fromHp, o.toHp, o.text, o.onDone)
    end
    function c:closeSubmenu() end
    return c
  end

  -- ------- the summary

  local function summary(game, list, index, opts, onClosed)
    if not on("summary", false) or type(list) ~= "table" or not list[index or 1] then return nil end
    local c = newCarrier(game, opts)
    function c.open()
      if Mn.isOpen() then return false end
      local s = game.save
      local m = { kind = "summary", list = list, index = index or 1, party = s ~= nil and list == s.party }
      return openWindow(c, m, function()
        local res = m.result or {}
        c.index = res.index or c.index
        onClosed(c)
      end)
    end
    c.index = index or 1
    return c
  end
  local function summary1(game, mon)
    if type(mon) ~= "table" or cur then return nil end
    local s = game.save
    local list, i = { mon }, 1
    for k, x in ipairs(s and s.party or {}) do if x == mon then list, i = s.party, k end end
    local c = summary(game, list, i, {}, function(c0) popIfTop(game, c0) end)
    if c then c.fallback = function() game.stack:push(engine("src.ui.SummaryMenu").new(game, mon)) end end
    return c
  end
  local function summary2(game, opts)
    opts = opts or {}
    if cur then return nil end
    local list, i = opts.party, opts.index
    if not list then list, i = { opts.mon }, 1 end
    local c = summary(game, list, i or 1, opts, function(c0)
      if opts.onClose then
        local ok, err = pcall(opts.onClose)
        if not ok then log("after the summary: %s", tostring(err)) end
      end
      popIfTop(game, c0)
    end)
    if c then c.fallback = function() game.stack:push(engine("src.ui.gen2.SummaryMenu").new(game, opts)) end end
    return c
  end

  -- ------- the Bag

  -- (USE: the game's own bag built off the stack, on that item)
  local function use1(game, opts, c, row)
    local BM = engine("src.ui.BagMenu")
    local okN, list = pcall(BM.new, game, opts)
    if not (okN and list) then return false end
    local idx
    for k, it in ipairs(list.items or {}) do
      if it.value == row.id and (row.slot == nil or it.slot == nil or it.slot == row.slot) then idx = k break end
    end
    if not idx then return false end
    list.index = idx
    -- (the game closing its bag -- a Ball thrown, a bike ridden: ours with it)
    list.close = function()
      if c.done then return end
      shut(c)
      popIfTop(game, c)
    end
    local before = #game.stack.states
    list.onChoose(list.items[idx], list)
    -- (the field's USE / TOSS box: USE, at once)
    local top = game.stack:top()
    if not opts.battle and #game.stack.states > before and type(top) == "table" and type(top.items) == "table"
        and top.items[1] and top.items[1].onSelect then
      game.stack:pop()
      top.items[1].onSelect()
    end
    return true
  end
  local function use2(game, opts, c, row)
    local PM = engine("src.ui.gen2.PackMenu")
    local okN, pack = pcall(PM.new, game, opts)
    if not (okN and pack) then return false end
    local want = ({ ITEMS = "ITEM", POKE_BALLS = "BALL", KEY_ITEMS = "KEY_ITEM", TM_CASE = "TM_HM" })[row.pocket or "ITEMS"] or "ITEM"
    for i = 1, 4 do
      pack.pocketIndex = i
      local p = pack:pocket()
      if p and p.id == want then break end
    end
    pack:rebuild()
    local idx
    for k, r in ipairs(pack.rows or {}) do if r.id == row.id then idx = k break end end
    if not idx then return false end
    pack.index = idx
    -- (its words in our box)
    pack.showMessage = function(_, lines)
      local text = type(lines) == "table" and table.concat(lines, "\n") or tostring(lines or "")
      say(c, text)
    end
    pack:useSelected()
    return true
  end

  local function bagCarrier(game, opts, m, useFn, onClosed, fallback)
    local c = newCarrier(game, opts)
    function c.open()
      if Mn.isOpen() then return false end
      Bg.useHandler = function(row, ui)
        local ok, took = pcall(useFn, game, opts, c, row)
        if not ok then log("the game's item use: %s", tostring(took)) end
        if not (ok and took) then ui.back() end
      end
      return openWindow(c, m, function()
        Bg.useHandler = nil
        onClosed(c, m.result or {})
      end)
    end
    c.fallback = fallback
    return c
  end
  local function bag1(game, opts)
    opts = opts or {}
    local battle = type(opts.battle) == "table" and opts.battle or nil
    if cur or (battle and battle.kind == "link") or not on("bag", battle ~= nil) then return nil end
    local m = { kind = "bag", battle = battle ~= nil }
    return bagCarrier(game, opts, m, use1, function(c, res)
      popIfTop(game, c)
      if res.chosen == nil and not res.leave and opts.onCancel then pcall(opts.onCancel) end
    end, function() game.stack:push(engine("src.ui.BagMenu").new(game, opts)) end)
  end
  local function bag2(game, opts)
    opts = opts or {}
    if cur or opts.tutorial then return nil end
    -- (START's, a battle's, a held item's GIVE; the mart's and the item PC's hold theirs: the game's)
    if not (opts.battle or opts.give or (opts.world == nil and opts.onClose)) then return nil end
    if not on("bag", opts.battle == true) then return nil end
    local m = { kind = "bag", battle = opts.battle == true, location = opts.give and "party" or nil }
    return bagCarrier(game, opts, m, use2, function(c, res)
      -- (the caller pops it, as it pops the game's)
      if res.chosen ~= nil and opts.onChoose then
        local ok, err = pcall(opts.onChoose, res.chosen, 1)
        if not ok then log("after the pack: %s", tostring(err)) end
      elseif not res.leave and opts.onClose then
        local ok, err = pcall(opts.onClose)
        if not ok then log("after the pack: %s", tostring(err)) end
      end
      popIfTop(game, c)
    end, function() game.stack:push(engine("src.ui.gen2.PackMenu").new(game, opts)) end)
  end

  -- ------- the game's text boxes while ours is up: our words box, a state of ours standing in until read
  local function ghostText(game, text, onDone, opts)
    if not (cur and type(text) == "string") or type(game) ~= "table" or not game.stack then return nil end
    if type(opts) == "table" and (opts.stay or opts.evoIntro) then return nil end
    local w = win()
    if not w then return nil end
    -- (only while ours, or a state of ours over it, is on top)
    local top = game.stack:top()
    if not (type(top) == "table" and (rawget(top, "woobOs") or rawget(top, "woobOsAbove"))) then return nil end
    local g = { isMenu = true, isOpaque = false, woobOsAbove = true, game = game }
    g.draw = function() end
    g.update = function() if game.input then Sh.feedHost(game.input) end end
    local function out()
      if g.gone then return end
      g.gone = true
      popIfTop(game, g)
      removeState(game, g)
    end
    local choice = type(opts) == "table" and opts.choice or nil
    local shown
    if choice then
      shown = w.ask and w.ask(text, function(yes)
        out()
        pcall(choice, yes == true)
        if onDone then pcall(onDone) end
      end)
    else
      shown = w.say(text, function()
        out()
        if onDone then pcall(onDone) end
      end)
    end
    if not shown then return nil end
    return g
  end

  function Mn.install()
    local reg = deps.screens
    if not (reg and reg.register) then return false end
    local function wrapScreen(id, path, make)
      reg:register(id, { new = function(game, ...)
        local okC, c = pcall(make, game, ...)
        if okC and c then return c end
        if not okC then log("a modern menu: %s", tostring(c)) end
        return engine(path).new(game, ...)
      end })
    end
    if gen == 2 then
      wrapScreen("Gen2PartyMenu", "src.ui.gen2.PartyMenu", party2)
      wrapScreen("Gen2SummaryMenu", "src.ui.gen2.SummaryMenu", summary2)
      if Bg then wrapScreen("Gen2PackMenu", "src.ui.gen2.PackMenu", bag2) end
    else
      wrapScreen("PartyMenu", "src.ui.PartyMenu", party1)
      wrapScreen("SummaryMenu", "src.ui.SummaryMenu", summary1)
      if Bg then wrapScreen("BagMenu", "src.ui.BagMenu", bag1) end
    end
    -- (the text boxes: once per process, this instance's code swapped in)
    local TB = engine("src.render.TextBox")
    if type(TB) == "table" and type(TB.new) == "function" then
      local w = rawget(TB, "__woobOsMenus")
      if not w then
        w = { orig = TB.new }
        TB.__woobOsMenus = w
        TB.new = function(...)
          local cw = rawget(TB, "__woobOsMenus")
          if cw.impl then
            local ok, got = pcall(cw.impl, ...)
            if ok and got then return got end
          end
          return cw.orig(...)
        end
      end
      w.impl = ghostText
    end
    return true
  end

  return Mn
end
