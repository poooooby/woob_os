-- The modern menus on FireRed / LeafGreen / Ruby / Sapphire / Emerald: the game's own Summary (and, in
-- later phases, its Party menu and Bag) taken over where WoobOS has its own, from the START menu's
-- Pokémon and in battle alike. With the mod option off, or any caller that isn't ours, or anything failing:
-- the game's own screen.
--
-- The Summary: src.ui.game3.summary_menu's openMenu(party, index, opts) wrapped once per process
-- (SummaryMenu.__woobOs = { orig = { the module's own functions }, impl }). Ours for the party menu's
-- SUMMARY (in the field and in battle) and for choosing a move to forget (mode "select_move": a TM, a Rare
-- Candy, a level up in battle, an evolution, the Move Tutor, the Move Relearner, the Move Deleter);
-- the game's for the PC's boxes (WoobOS's Boxes have their own), trades, the Battle Factory and Ruby /
-- Sapphire's Day Care (`context`, `mode`, `enemyParty`, `owner`, `maxMonIndex`, `nativeMode`). Ours opens
-- full screen (Sh.openFull("menus", ...), the window src/apps/menus.lua with ctx.menu) and answers as the
-- game's would: SummaryMenu._cursor, then opts.onClose(cursor), then opts.onSelectMove(the slot 0..3 to
-- forget, or nil).
-- A battle doesn't send input through the UI stack: it asks SummaryMenu.isOpen(), then calls its
-- update / handleInput / draw itself (battle/init.lua party_menu_input, the level up's learning). While
-- ours is open those are ours: isOpen true, the input to our host (deps.feed: once a frame), update and draw
-- nothing (ours draws over the whole window), close closing ours (a battle's end).
--
--   Mn = menus(engine, deps)   deps: Sh ; on() -> the option ; feed(input) (the host's input, once a frame) ;
--                              log(fmt, ...)
--   Mn.wrap() (at game.ready) ; Mn.isOpen() ; Mn.openSummary(party, index, opts) -> true when ours opened

return function(engine, deps)
  local Mn = {}
  local cur = nil   -- (the open one: { kind, opts, menu })
  local function log(fmt, ...) if deps.log then pcall(deps.log, fmt, ...) end end

  function Mn.isOpen() return cur ~= nil end

  -- (a move to learn, as the game's summary reads it: an id, or a move's name)
  local function moveId(v)
    local n = tonumber(v)
    if n then return n end
    if type(v) ~= "string" then return nil end
    local Constants, GV = engine("src.core.game3.constants"), engine("src.core.GameVersion")
    local okC, id = pcall(function() return Constants.of(GV.get()):id("moves", v) end)
    if okC and tonumber(id) then return tonumber(id) end
    local P = engine("src.core.game3.pokemon")
    local okP, b = pcall(P and P.battleMoveId or error, v)
    return okP and tonumber(b) or nil
  end

  -- ------- the Summary

  -- which callers are ours: the party's summary and choosing a move to forget
  local function summaryOurs(opts)
    local c = opts.context
    if c ~= nil and c ~= "inBattle" then return false end
    local m = opts.mode
    if m ~= nil and m ~= "select_move" and m ~= "party" then return false end
    if opts.enemyParty or opts.owner or opts.maxMonIndex or opts.nativeMode or opts.linkBusy then return false end
    return true
  end

  -- ours closed (its answer in menu.result): the game's callbacks, in the game's order
  local function summaryClosed(c)
    local SM = engine("src.ui.game3.summary_menu")
    cur = nil
    local opts = c.opts
    local res = c.menu.result or {}
    local index = tonumber(res.index) or c.menu.index or 1
    if SM then
      SM.open = false
      SM._cursor = index
    end
    if opts.onClose then
      local ok, err = pcall(opts.onClose, index)
      if not ok then log("the summary's onClose failed: %s", tostring(err)) end
    end
    if opts.onSelectMove then
      local slot = (opts.mode == "select_move" and type(res.picked) == "number") and res.picked or nil
      local ok, err = pcall(opts.onSelectMove, slot)
      if not ok then log("the summary's onSelectMove failed: %s", tostring(err)) end
    end
  end

  function Mn.openSummary(party, index, opts)
    opts = opts or {}
    -- (the option; Mn.on stands in for it in the tests)
    local on = Mn.on
    if on == nil then on = deps.on and deps.on() end
    if cur or not on then return false end
    if not summaryOurs(opts) then return false end
    local Sh = deps.Sh
    if not (Sh and Sh.openFull) then return false end
    local list = {}
    for i, mon in ipairs(party or {}) do list[i] = mon end
    if #list == 0 then return false end
    index = math.max(1, math.min(#list, tonumber(index) or 1))
    local learn = opts.mode == "select_move" and moveId(opts.moveToLearn or opts.moveId) or nil
    local menu = { kind = "summary", list = list, index = index, learn = learn, forgetMove = opts.forgetMove == true,
                   -- (its moves reordered only from the party's own summary, never in battle)
                   party = opts.mode == nil and opts.context == nil and not Mn.inBattle(),
                   back = "menus.back" }
    local c = { kind = "summary", opts = opts, menu = menu }
    local s = opts.session or opts.playerState
    cur = c
    local ok, opened = pcall(Sh.openFull, "menus", s, function() summaryClosed(c) end, nil,
      { menu = menu, chrome = false })
    if not (ok and opened) then
      cur = nil
      if not ok then log("the summary couldn't open: %s", tostring(opened)) end
      return false
    end
    local SM = engine("src.ui.game3.summary_menu")
    if SM then
      SM.open, SM._cursor = true, index
    end
    return true
  end

  -- a battle on: its summary can't reorder moves
  function Mn.inBattle()
    local B = engine("src.core.game3.battle")
    local ok, on = pcall(B and B.isActive or error)
    return ok and on == true
  end

  -- ------- the wraps (once per process; this instance's impl swapped in)

  local function wrapSummary()
    local SM = engine("src.ui.game3.summary_menu")
    if not SM then return false end
    local w = SM.__woobOs
    if not w then
      w = { orig = { openMenu = SM.openMenu, isOpen = SM.isOpen, close = SM.close, handleInput = SM.handleInput,
                     update = SM.update, draw = SM.draw } }
      SM.__woobOs = w
      local o = w.orig
      SM.openMenu = function(party, index, opts)
        local impl = w.impl
        if impl and impl.openSummary then
          local ok, took = pcall(impl.openSummary, party, index, opts)
          if ok and took then return end
          if not ok and impl.log then impl.log("the summary's takeover failed: %s", tostring(took)) end
        end
        return o.openMenu(party, index, opts)
      end
      SM.isOpen = function(...)
        local impl = w.impl
        if impl and impl.isOpen() then return true end
        return o.isOpen(...)
      end
      SM.close = function(...)
        local impl = w.impl
        if impl and impl.isOpen() then return impl.closeOurs() end
        return o.close(...)
      end
      SM.handleInput = function(input, ...)
        local impl = w.impl
        if impl and impl.isOpen() then return impl.feed(input) end
        return o.handleInput(input, ...)
      end
      SM.update = function(...)
        local impl = w.impl
        if impl and impl.isOpen() then return end
        if o.update then return o.update(...) end
      end
      SM.draw = function(...)
        local impl = w.impl
        if impl and impl.isOpen() then return end
        return o.draw(...)
      end
    end
    w.impl = { openSummary = Mn.openSummary, isOpen = Mn.isOpen, closeOurs = function() return Mn.closeOurs() end,
               feed = function(input) if deps.feed then deps.feed(input) end end, log = log }
    return true
  end

  -- ours closed from outside (a battle's end, the game's close): as B would, nothing chosen
  function Mn.closeOurs()
    local c = cur
    if not c then return end
    c.menu.result = c.menu.result or { picked = false, index = c.menu.index }
    local Sh = deps.Sh
    local h = Sh and Sh.host and Sh.host()
    local Tm = h
    if Tm and Tm.isOpen and Tm.isOpen() and Tm.state then
      local r = Tm.state()
      if r and r.ctx and r.ctx.menu == c.menu and r.ctx.done then return r.ctx.done() end
    end
    summaryClosed(c)
  end

  function Mn.wrap()
    local ok, err = pcall(wrapSummary)
    if not ok then log("the modern menus couldn't wrap the summary: %s", tostring(err)) end
  end

  return Mn
end
