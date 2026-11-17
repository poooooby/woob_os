-- The modern menus on FireRed / LeafGreen / Ruby / Sapphire / Emerald: the game's own Summary, Party
-- menu and Bag taken over where WoobOS has its own, from the START menu's
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
--
-- The party menu: src.ui.game3.party_menu's show(party, overlay, opts) wrapped the same way. Ours for the
-- START menu's (mode "list"), a battle's switch and send-out (singles and doubles: the game's battle order,
-- its validate and onSelect with the real slots), an item used from the game's bag / TM Case / Berry Pouch
-- in the field (mode "use") and an item given (mode "give"). The game's for choosing Pokémon for something
-- (the Day Care, a contest, the Frontier: "choose" / "choose_multi"), the Move Tutor, the Pokédude and
-- Oak's first battle, a multi battle's, a link's, an item used from the bag in battle (until the Bag is
-- ours) and Ruby / Sapphire's mail given. Ours answers as the game's: PartyMenu.open / cursor / _party /
-- _order set while it's up, then opts.onClose(), then opts.onSelect(slot, mon) when one was chosen; a
-- field move runs after (ctx.menu.after). While ours is up the game's GIVE from its bag comes back through
-- show(mode "give"): handed to our window (src/apps/menus.lua W.giveFromBag), the bag closed.
--
-- The Bag: src.ui.game3.bag_menu's show(bag, opts) wrapped the same way, and Screens.handleInput / draw for
-- "bag" (a battle calls those, through Emerald's and Ruby / Sapphire's skins). Ours for the START menu's
-- (no location) and a battle's (with its onBattleUse); the game's for a shop's selling, the item PC, a
-- berry tree, the Berry Blender, the party menu's GIVE from the game's party, choosing (onChoose), the
-- Pokédude and Teachy TV, links. Ours answers as the game's: a battle's use is onBattleUse(id, slot,
-- moveSlot, usedInMenu) without onClose (BagMenu.battleUse); closed, onClose() then, in a battle,
-- onBattleUse(nil); leaving for the field (a bike, Repel, the VS Seeker) onClose() then its own work. While
-- ours is up: BagMenu.open, its showMessage (ItemUse's field words) in our bubble; ItemUse's on-field
-- callbacks wait (BagMenu.isOpen true) until ours has closed. Its party is the same screen's
-- (src/apps/menus.lua): the party menu isn't opened through the game for it.
--
--   Mn = menus(engine, deps)   deps: Sh ; on() -> the option ; feed(input) (the host's input, once a frame) ;
--                              log(fmt, ...) ; partyUi(session) -> the game's party skin (Ruby / Sapphire's)
--   Mn.wrap() (at game.ready) ; Mn.isOpen() ; Mn.openSummary(party, index, opts) -> true when ours opened ;
--   Mn.openParty(party, overlay, opts) -> the same ; Mn.openBag(bag, opts) -> the same ;
--   Mn.kind() -> "summary" | "party" | "bag" | nil

return function(engine, deps)
  local Mn = {}
  local cur = nil   -- (the open one: { kind, opts, menu })
  local function log(fmt, ...) if deps.log then pcall(deps.log, fmt, ...) end end

  function Mn.isOpen() return cur ~= nil end
  function Mn.kind() return cur and cur.kind or nil end

  -- (the game's own words under the names its bag and party menu use: each profile's text aliases --
  -- Emerald's "gText_Var1CantBeHeld" for "gText_ItemCantBeHeld" -- set while one of ours is open, as the
  -- game's screens set them around their input)
  local aliased = {}
  local function aliases(s, on)
    local R = engine("src.core.game3.rom_text")
    if not R then return end
    if not on then
      for k = #aliased, 1, -1 do
        R.overrides[aliased[k]] = nil
        aliased[k] = nil
      end
      return
    end
    local Pr = engine("src.core.game3.profile")
    local ok, row = pcall(Pr.forSession, s)
    local list = ok and type(row) == "table" and type(row.ui) == "table" and row.ui.textAliases or nil
    if type(list) ~= "table" then return end
    for from, to in pairs(list) do
      local okH, fine = pcall(function() return R.overrides[from] == nil and not R.has(from) and R.has(to) end)
      if okH and fine then
        R.overrides[from] = R.ir(to)
        aliased[#aliased + 1] = from
      end
    end
  end
  Mn.aliases = aliases
  -- (the option; Mn.on stands in for it in the tests)
  local function on()
    local v = Mn.on
    if v == nil then v = deps.on and deps.on() end
    return v
  end

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
    aliases(nil, false)
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
    if cur or not on() then return false end
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
    aliases(s, true)
    return true
  end

  -- a battle on: its summary can't reorder moves
  function Mn.inBattle()
    local B = engine("src.core.game3.battle")
    local ok, on = pcall(B and B.isActive or error)
    return ok and on == true
  end

  -- ------- the party menu

  local PARTY_MODES = { list = true, battle_switch = true, battle_faint = true, use = true, give = true, choose = true,
                        choose_multi = true, move_tutor = true }

  -- (a link room, the Union Room, a link battle: the game's own)
  local function linked()
    local Map, UR = engine("src.core.game3.map"), engine("src.core.game3.link.union_room")
    local okU, union = pcall(function() return UR.isUnionMap(Map.current) end)
    if okU and union then return true end
    local Link = package.loaded["src.core.game3.link"]
    if type(Link) == "table" and Link.link ~= nil then
      local okL, inRoom = pcall(Link.inLinkRoom)
      if okL and inRoom == true then return true end
    end
    local B = engine("src.core.game3.battle")
    return B ~= nil and type(B._st) == "table" and B._st.link ~= nil and B._st.link ~= false
  end

  -- which callers are ours
  local function partyOurs(opts)
    local mode = opts.mode or "list"
    if not PARTY_MODES[mode] then return false end
    if opts.onChoose or opts.nativePartyLayout or opts.minigameEligible or opts.fadeIn then return false end
    if mode == "list" and opts.onSelect then return false end
    -- (an item from the game's bag in battle: its bag drives the game's party menu itself)
    if mode == "use" and (opts.onSelect or opts.battle or opts.battleOrder) then return false end
    if type(opts.multi) == "table" and next(opts.multi) ~= nil then return false end
    local B = engine("src.core.game3.battle")
    local st = B and B._st
    local inBattle = Mn.inBattle()
    if inBattle and type(st) == "table" and (st.pokedude or st.multi) then return false end
    -- (FireRed / LeafGreen's first battle: Oak's words over the party menu)
    if opts.battle or mode == "battle_switch" or mode == "battle_faint" then
      local Oak, BUi = engine("src.core.game3.battle.oak_advice"), engine("src.core.game3.battle.ui")
      local okO, pending = pcall(function() return Oak.pending(BUi._st, Oak.FLAG_PARTY_MENU) end)
      if okO and pending then return false end
    end
    if linked() then return false end
    -- (Ruby / Sapphire's mail given: the game's own writing screen)
    if mode == "give" and opts.item then
      local Mail, I = engine("src.core.game3.mail"), engine("src.core.game3.items_data")
      local okM, mail = pcall(function() return Mail.isMailItem(I.toNumericId(opts.item) or opts.item) end)
      local p = deps.partyUi and deps.partyUi(opts.session)
      if okM and mail and p and p.beginGiveMail then return false end
    end
    -- (the Battle Pike's party rules)
    local s = opts.session
    local Pr = engine("src.core.game3.profile")
    local okF, fam = pcall(Pr.family, s)
    if okF and fam == "rse" then
      local Pike = engine("src.core.game3.rse.frontier.pike")
      local okP, inPike = pcall(Pike.inBattlePike, s)
      if okP and inPike then return false end
    end
    return true
  end

  -- ours closed (its answer in menu.result): the game's callbacks, in the game's order
  local function partyClosed(c)
    local PM = engine("src.ui.game3.party_menu")
    cur = nil
    aliases(nil, false)
    local m, opts = c.menu, c.opts
    local res = m.result or {}
    if PM then
      PM.open = false
      PM.mode = "list"
      PM.cursor = tonumber(m.cursor) or 1
      -- (what callers read after: the team chosen (PartyMenu.chosenOrder), the tutor's result)
      local order = {}
      for k, sl in ipairs(res.list or {}) do order[k] = sl end
      PM._chooseOrder = order
      PM._tutorResult = m.tutorResult == true
    end
    if opts.onClose then
      local ok, err = pcall(opts.onClose)
      if not ok then log("the party's onClose failed: %s", tostring(err)) end
    end
    local chosen = res.chosen
    if opts.onSelect and (res.list or res.cancelMulti) then
      local ok, err = pcall(opts.onSelect, res.list)
      if not ok then log("the party's onSelect failed: %s", tostring(err)) end
    elseif chosen and opts.onSelect then
      local ok, err = pcall(opts.onSelect, chosen, m.party[chosen])
      if not ok then log("the party's onSelect failed: %s", tostring(err)) end
    end
    if m.after then
      local ok, err = pcall(m.after)
      if not ok then log("after the party: %s", tostring(err)) end
    end
  end

  -- the party in a battle's order (the game's PartyMenu.battleOrder): the shown list, each one's real
  -- slot, the overlay in that order
  local function battleView(party, overlay, opts)
    local PM = engine("src.ui.game3.party_menu")
    local order = opts.battleOrder
    if order == nil then
      local B = engine("src.core.game3.battle")
      local st = B and B._st
      if not (st and st.playerParty and st.playerParty == party) then return party, overlay, nil end
      local ok, got = pcall(PM.battleOrder, st)
      order = ok and got or nil
    end
    if type(order) ~= "table" then return party, overlay, nil end
    local view, ov = {}, overlay
    for i, pi in ipairs(order) do view[i] = party[pi] end
    if type(overlay) == "table" then
      ov = {}
      for i, pi in ipairs(order) do ov[i] = overlay[pi] end
    end
    return view, ov, order
  end

  function Mn.openParty(sessionParty, overlay, opts)
    if type(overlay) == "table" and opts == nil and (overlay.mode or overlay.session or overlay.battle
        or overlay.onSelect or overlay.activeSlot) then
      opts, overlay = overlay, nil
    end
    opts = opts or {}
    if cur then
      -- (the game's bag giving while ours waits on GIVE: ours does it, the bag closed)
      if cur.kind == "party" and opts.mode == "give" and cur.menu.win and cur.menu.win.giveFromBag then
        local Screens = engine("src.ui.game3.screens")
        local okB, Bag = pcall(Screens.get, "bag", opts.session)
        if okB and Bag and Bag.isOpen and Bag.isOpen() then
          Bag._onClose = nil
          pcall(Bag.close)
        end
        cur.menu.win.giveFromBag(opts.item, opts.giveSource, opts.onClose)
        return true
      end
      return false
    end
    if not on() or not partyOurs(opts) then return false end
    local Sh = deps.Sh
    if not (Sh and Sh.openFull) then return false end
    local s = opts.session
    local party = sessionParty or (s and s.party)
    if type(party) ~= "table" or not party[1] then return false end
    overlay = overlay or (s and (s.move_overlay or s.moveOverlay))
    local mode = opts.mode or "list"
    local battle = opts.battle == true or mode == "battle_switch" or mode == "battle_faint"
    local view, ov, order = party, overlay, nil
    if mode == "battle_switch" or mode == "battle_faint" then view, ov, order = battleView(party, overlay, opts) end
    local onSelect, validate = opts.onSelect, opts.validate
    local o = opts
    if order then
      -- (the game's callbacks take real slots: ours speak in the shown order)
      o = {}
      for k, v in pairs(opts) do o[k] = v end
      if onSelect then o.onSelect = function(d, mon) return onSelect(d and order[d], mon) end end
      if validate then o.validate = function(d) return validate(d and order[d]) end end
    end
    local m = { kind = "party", party = view, order = order, overlay = ov, mode = mode, item = opts.item,
                bag = opts.bag or (s and (s.bag or s.inventory)), giveSource = opts.giveSource, battle = battle,
                double = opts.layout == "double", validate = o.validate, cursor = 1, count = opts.count,
                eligible = opts.eligible, validateChosen = opts.validateChosen, chooseFullMessage = opts.chooseFullMessage,
                immediateChooseCancel = opts.immediateChooseCancel, eggFails = opts.eggFails,
                chooseCancelStart = opts.chooseCancelStart, tutor = opts.tutor, autoSlot = opts.autoSlot }
    local c = { kind = "party", opts = o, menu = m }
    cur = c
    local PM = engine("src.ui.game3.party_menu")
    if PM then
      PM.open, PM.cursor, PM.mode = true, 1, mode
      PM._party, PM._overlay, PM._session, PM._bag, PM._item = view, ov, s, m.bag, opts.item
      PM._order, PM._battle, PM._flyReturn = order, battle, nil
    end
    local ok, opened = pcall(Sh.openFull, "menus", s, function() partyClosed(c) end, nil,
      { menu = m, chrome = false })
    if not (ok and opened) then
      cur = nil
      if PM then PM.open = false end
      if not ok then log("the party couldn't open: %s", tostring(opened)) end
      return false
    end
    aliases(s, true)
    return true
  end

  -- ------- the Bag

  local function teachyTv()
    local Tv = package.loaded["src.ui.game3.teachy_tv"]
    if type(Tv) ~= "table" or type(Tv.isOpen) ~= "function" then return false end
    local ok, open = pcall(Tv.isOpen)
    return ok and open == true
  end

  -- (the places the Bag opens for that are ours: START's and a battle's (no location), a berry tree's and the
  -- Berry Blender's (choosing a Berry), the item PC's deposit, a shop's selling)
  local BAG_PLACES = { berry_tree = true, blender = true, itempc = true, shop = true }
  local function bagOurs(opts)
    local loc = opts.location
    if loc ~= nil and not BAG_PLACES[loc] then return false end
    if opts.onChoose and loc ~= "berry_tree" and loc ~= "blender" then return false end
    if opts.pocketIdx then return false end
    if opts.battle and not opts.onBattleUse then return false end
    local B = engine("src.core.game3.battle")
    local st = B and B._st
    if opts.battle and type(st) == "table" and (st.pokedude or (st.link ~= nil and st.link ~= false)) then
      return false
    end
    if linked() or teachyTv() then return false end
    return true
  end

  local function bagClosed(c)
    local BM = engine("src.ui.game3.bag_menu")
    cur = nil
    aliases(nil, false)
    local m, opts = c.menu, c.opts
    if BM then BM.open = false end
    local res = m.result or {}
    local function try(f, ...)
      if not f then return end
      local ok, err = pcall(f, ...)
      if not ok then log("after the bag: %s", tostring(err)) end
    end
    if res.classic then
      -- (the game's own bag instead, where ours was: Ruby / Sapphire's mail is written there)
      local w = BM and BM.__woobOs
      if w then try(w.orig.show, c.bag, opts) end
      return
    end
    if res.battle then
      local b = res.battle
      return try(opts.onBattleUse, b.id, b.slot, b.moveSlot, b.used)
    end
    if res.chosen ~= nil and opts.onChoose then
      -- (a Berry chosen, or none: the game's choose_done, onClose then onChoose(id | 0))
      try(opts.onClose)
      return try(opts.onChoose, res.chosen)
    end
    try(opts.onClose)
    if opts.battle and opts.onBattleUse and not res.leave then try(opts.onBattleUse, nil) end
    if m.after then try(m.after) end
  end

  function Mn.openBag(sessionBag, opts)
    opts = opts or {}
    if cur then
      -- (the game asking for its bag again while ours is up -- Teachy TV's way back: ours is there)
      return cur.kind == "bag" and opts.location == nil and not opts.battle
    end
    if not on() or not bagOurs(opts) then return false end
    local Sh = deps.Sh
    if not (Sh and Sh.openFull) then return false end
    local s = opts.session
    local bag = opts.bag
    if type(sessionBag) == "table" then
      if sessionBag.pockets then
        bag = sessionBag
      elseif sessionBag.bag or sessionBag.party then
        s = s or sessionBag
        bag = sessionBag.bag or bag
      end
    end
    bag = bag or (s and (s.bag or s.inventory))
    if not (s and bag) then return false end
    local POCKET = { BERRIES = "BERRY_POUCH", TM_HM = "TM_CASE" }
    local m = { kind = "bag", bag = bag, battle = opts.battle == true, pocket = POCKET[opts.pocket] or opts.pocket,
                location = opts.location }
    local c = { kind = "bag", opts = opts, menu = m, bag = sessionBag }
    cur = c
    local BM = engine("src.ui.game3.bag_menu")
    if BM then
      BM.open, BM._bag, BM._session, BM._battle, BM._location = true, bag, s, m.battle, opts.location
    end
    local ok, opened = pcall(Sh.openFull, "menus", s, function() bagClosed(c) end, nil, { menu = m, chrome = false })
    if not (ok and opened) then
      cur = nil
      if BM then BM.open = false end
      if not ok then log("the bag couldn't open: %s", tostring(opened)) end
      return false
    end
    aliases(s, true)
    return true
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
    w.impl = { openSummary = Mn.openSummary, isOpen = function() return cur ~= nil and cur.kind == "summary" end,
               closeOurs = function() return Mn.closeOurs() end,
               feed = function(input) if deps.feed then deps.feed(input) end end, log = log }
    return true
  end

  local function wrapParty()
    local PM = engine("src.ui.game3.party_menu")
    if not PM then return false end
    local w = PM.__woobOs
    if not w then
      w = { orig = { show = PM.show, isOpen = PM.isOpen, close = PM.close, handleInput = PM.handleInput,
                     update = PM.update, draw = PM.draw, reloadSprites = PM.reloadSprites } }
      PM.__woobOs = w
      local o = w.orig
      PM.show = function(party, overlay, opts)
        local impl = w.impl
        if impl and impl.openParty then
          local ok, took = pcall(impl.openParty, party, overlay, opts)
          if ok and took then return end
          if not ok and impl.log then impl.log("the party's takeover failed: %s", tostring(took)) end
        end
        return o.show(party, overlay, opts)
      end
      PM.isOpen = function(...)
        local impl = w.impl
        if impl and impl.isOpen() then return true end
        return o.isOpen(...)
      end
      PM.close = function(...)
        local impl = w.impl
        if impl and impl.isOpen() then return impl.closeOurs() end
        return o.close(...)
      end
      PM.handleInput = function(input, ...)
        local impl = w.impl
        if impl and impl.isOpen() then return impl.feed(input) end
        return o.handleInput(input, ...)
      end
      PM.update = function(...)
        local impl = w.impl
        if impl and impl.isOpen() then return end
        if o.update then return o.update(...) end
      end
      PM.draw = function(...)
        local impl = w.impl
        if impl and impl.isOpen() then return end
        return o.draw(...)
      end
      PM.reloadSprites = function(...)
        local impl = w.impl
        if impl and impl.isOpen() then return end
        if o.reloadSprites then return o.reloadSprites(...) end
      end
      -- (a caller's words over the party -- the Frontier's "no more than ..." as it opens again -- in ours)
      o.showMessage, o.showYesNo = PM.showMessage, PM.showYesNo
      PM.showMessage = function(text, onDismiss, ...)
        local impl = w.impl
        if impl and impl.isOpen() and impl.say(text, onDismiss) then return end
        return o.showMessage(text, onDismiss, ...)
      end
      PM.showYesNo = function(text, cb, ...)
        local impl = w.impl
        if impl and impl.isOpen() and impl.ask(text, cb) then return end
        return o.showYesNo(text, cb, ...)
      end
    end
    w.impl = { openParty = Mn.openParty, isOpen = function() return cur ~= nil and cur.kind == "party" end,
               say = function(text, after)
                 local win = cur and cur.menu.win
                 return win and win.say and win.say(text, after) or false
               end,
               ask = function(text, after)
                 local win = cur and cur.menu.win
                 return win and win.ask and win.ask(text, after) or false
               end,
               closeOurs = function() return Mn.closeOurs() end,
               feed = function(input) if deps.feed then deps.feed(input) end end, log = log }
    return true
  end

  local function wrapBag()
    local BM = engine("src.ui.game3.bag_menu")
    if not BM then return false end
    local w = BM.__woobOs
    if not w then
      w = { orig = { show = BM.show, isOpen = BM.isOpen, close = BM.close, handleInput = BM.handleInput,
                     draw = BM.draw, showMessage = BM.showMessage } }
      BM.__woobOs = w
      local o = w.orig
      BM.show = function(bag, opts)
        local impl = w.impl
        if impl and impl.openBag then
          local ok, took = pcall(impl.openBag, bag, opts)
          if ok and took then return end
          if not ok and impl.log then impl.log("the bag's takeover failed: %s", tostring(took)) end
        end
        return o.show(bag, opts)
      end
      BM.isOpen = function(...)
        local impl = w.impl
        if impl and impl.isOpen() then return true end
        return o.isOpen(...)
      end
      BM.close = function(...)
        local impl = w.impl
        if impl and impl.isOpen() then return impl.closeOurs() end
        return o.close(...)
      end
      BM.handleInput = function(input, ...)
        local impl = w.impl
        if impl and impl.isOpen() then return impl.feed(input) end
        return o.handleInput(input, ...)
      end
      BM.draw = function(...)
        local impl = w.impl
        if impl and impl.isOpen() then return end
        return o.draw(...)
      end
      BM.showMessage = function(text, onDone, ...)
        local impl = w.impl
        if impl and impl.isOpen() and impl.say(text, onDone) then return end
        return o.showMessage(text, onDone, ...)
      end
    end
    w.impl = { openBag = Mn.openBag, isOpen = function() return cur ~= nil and cur.kind == "bag" end,
               closeOurs = function() return Mn.closeOurs() end,
               say = function(text, onDone)
                 local win = cur and cur.menu.win
                 return win and win.say and win.say(text, onDone) or false
               end,
               feed = function(input) if deps.feed then deps.feed(input) end end, log = log }
    -- (a battle hands the bag its input and draws it through Screens -- Emerald's and Ruby / Sapphire's
    -- skins: while ours is up, ours)
    local Screens = engine("src.ui.game3.screens")
    if Screens and not Screens.__woobOs then
      local so = { handleInput = Screens.handleInput, draw = Screens.draw }
      Screens.__woobOs = so
      Screens.handleInput = function(id, mod, input, ...)
        local ww = BM.__woobOs
        local impl = ww and ww.impl
        if id == "bag" and impl and impl.isOpen() then return impl.feed(input) end
        return so.handleInput(id, mod, input, ...)
      end
      Screens.draw = function(id, mod, ...)
        local ww = BM.__woobOs
        local impl = ww and ww.impl
        if id == "bag" and impl and impl.isOpen() then return end
        return so.draw(id, mod, ...)
      end
    end
    return true
  end

  -- ours closed from outside (a battle's end, the game's close): as B would, nothing chosen
  function Mn.closeOurs()
    local c = cur
    if not c then return end
    if c.kind == "party" then c.menu.result = c.menu.result or { chosen = nil }
    elseif c.kind == "bag" then c.menu.result = c.menu.result or {}
    else c.menu.result = c.menu.result or { picked = false, index = c.menu.index } end
    local Sh = deps.Sh
    local h = Sh and Sh.host and Sh.host()
    local Tm = h
    if Tm and Tm.isOpen and Tm.isOpen() and Tm.state then
      local r = Tm.state()
      if r and r.ctx and r.ctx.menu == c.menu and r.ctx.done then return r.ctx.done() end
    end
    if c.kind == "party" then partyClosed(c) elseif c.kind == "bag" then bagClosed(c) else summaryClosed(c) end
  end

  function Mn.wrap()
    local ok, err = pcall(wrapSummary)
    if not ok then log("the modern menus couldn't wrap the summary: %s", tostring(err)) end
    ok, err = pcall(wrapParty)
    if not ok then log("the modern menus couldn't wrap the party menu: %s", tostring(err)) end
    ok, err = pcall(wrapBag)
    if not ok then log("the modern menus couldn't wrap the bag: %s", tostring(err)) end
  end

  return Mn
end
