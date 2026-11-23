-- The modern menus' window (src/menus.lua opens it full screen in place of the game's own: Sh.openFull
-- "menus", ctx.menu), one of:
--   - kind "summary": a party Pokémon's summary, in the Pokédex's glass, as Boxes shows one (its state
--     and input src/apps/summary_ctl.lua's, drawn by src/apps/boxes_summary.lua). From the party menu: Up /
--     Down its Pokémon, L / R the tabs, its moves reordered outside battle. Choosing a move to forget (a TM,
--     a level up, an evolution): the moves with the new one below, A the one to forget, B none. Its answer
--     goes back in ctx.menu.result ({ picked = the slot 0..3 | false, index }) as it closes.
--   - kind "party": the party menu (src/apps/party.lua's state and input, src/apps/party_view.lua's
--     drawing, src/party.lua's rules); its answer in ctx.menu.result ({ chosen = the shown slot | nil }),
--     what runs after it closes (a field move) in ctx.menu.after.
--   - kind "bag": the Bag (src/apps/bag.lua, src/apps/bag_view.lua, src/bag_rules.lua); its answer in
--     ctx.menu.result ({ battle = { id, slot, moveSlot, used } } | { leave = true } (ctx.menu.after runs) |
--     { classic = true } (the game's own bag instead) | {} (closed)).
-- One screen, pages over pages: the Bag opens the party over it (an item used on a Pokémon, given, used in
-- battle) and comes back to it; the party's GIVE opens the Bag over it, choosing what to give. ctx.menu.win:
-- this window, so src/menus.lua can hand it what the game's bag gave and the game's words.
--
--   window(ctx, env, makeSummary, makeParty, makeBag) -> win (src/apps.lua)

local max, min = math.max, math.min

-- hit args (the summary view's, the party's, the Bag's)
local A = { SUM_BACK = 600, SUM_PREV = 601, SUM_NEXT = 602, SUM_PIC = 603, SUM_TAB = 610, SUM_MOVE = 620,
            CARD = 700, MENU = 720, SCRIM = 740, CANCEL = 741, MSG = 742, YES = 743, NO = 744, CONFIRM = 745, PICK = 750,
            POCKET = 800, QTY_DOWN = 811, QTY_UP = 812, QTY_OK = 813, SORT = 820, ROW = 1000 }
local SUM_TABS = { "sum.tab.info", "sum.tab.stats", "sum.tab.moves" }
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env, makeSummary, makeParty, makeBag)
  local K, T = env.K, env.T or NO_T
  local m = ctx.menu or {}
  local W = { title = "" }
  local st = { closed = false, page = "summary" }
  W.state = st
  local function session() return ctx.session or (env.session and env.session()) end
  local Ctl = env.summaryCtl(env, T, A, SUM_TABS)
  local sumView = makeSummary and makeSummary(K, env, T, st, A, SUM_TABS) or nil
  local Pc = (m.kind == "party" or m.kind == "bag") and env.partyCtl and env.partyCtl(env, T, A, Ctl) or nil
  local Bc = Pc and env.bagCtl and env.bagCtl(env, T, A, Pc) or nil
  local partyView = Pc and makeParty and makeParty(K, env, T, A, sumView) or nil
  local bagView = Bc and makeBag and makeBag(K, env, T, A, partyView) or nil
  if m.kind == "party" then
    st.party, st.page = Pc.open(m, ctx), "party"
  elseif m.kind == "bag" then
    st.bag, st.page = Bc.open(m, ctx), "bag"
  else
    st.sum = Ctl.open(m.list or {}, m.index or 1, { session = session, party = m.party, learn = m.learn,
                                                   forgetMove = m.forgetMove, back = m.back })
  end
  m.win = W

  -- (done: the answer for the game, then the host closes and src/menus.lua answers it)
  local function done()
    if st.closed then return end
    st.closed = true
    Ctl.stop()
    if m.kind == "party" then m.result = m.result or { chosen = nil }
    elseif m.kind == "bag" then m.result = m.result or {}
    else m.result = { picked = st.sum.picked, index = st.sum.i } end
    if ctx.done then ctx.done() end
  end

  -- ------- pages over pages

  -- the Bag opened the party over it
  local function partyOverBag(want)
    local B = st.bag
    local s = B.c.session or session()
    local pm
    if want.mode == "battleUse" then
      local party, order, double = env.bagRules.battleParty(B.c)
      pm = { kind = "party", party = party, order = order, mode = "battleUse", item = want.item, bag = B.c.bag,
             battle = true, double = double == true, cursor = 1 }
    else
      pm = { kind = "party", party = s and s.party or {}, mode = want.mode, item = want.item, bag = want.bag or B.c.bag,
             cursor = 1 }
    end
    st.inner, st.innerAfter = pm, want.after
    st.party = Pc.open(pm, ctx)
    st.page = "party"
  end
  local function partyOverBagDone()
    local pm = st.inner
    local res = pm.result or {}
    local after = st.innerAfter
    st.inner, st.party, st.innerAfter = nil, nil, nil
    Ctl.stop()
    -- (what the party used of an item it was lent goes back where it came from: the Pyramid's bag)
    if after then pcall(after) end
    if res.battle then
      m.result = { battle = res.battle }
      return done()
    end
    if pm.after then
      m.after, m.result = pm.after, { leave = true }
      return done()
    end
    st.page = "bag"
    st.bag.prompt, st.bag.menu, st.bag.view = nil, nil, "list"
    Bc.refresh(st.bag)
  end
  -- the party's GIVE opened the Bag over it
  local function bagOverParty()
    local P = st.party
    P.wantBag = nil
    local bm = { kind = "bag", location = "party", bag = P.c.bag }
    st.innerBag = bm
    st.bag = Bc.open(bm, ctx)
    st.page = "bag"
  end
  local function bagOverPartyDone()
    local bm = st.innerBag
    local res = bm.result or {}
    st.innerBag, st.bag = nil, nil
    st.page = "party"
    local P = st.party
    if res.chosen then
      Pc.giveFromBag(P, res.chosen, env.bagRules.giveSource(P.c.bag))
    else
      P.giving = nil
    end
  end

  -- ------- a chooser of the game's own, asked for while ours is up (the Game Boy games' item use: the game's bag
  -- code opening its party list): the party over the page that was up, answering the game through pm.onChoose;
  -- the game taking its list away (W.innerDone), or B (onDone(result)), back to that page
  local function innerDone()
    local gi = st.gameInner
    if not gi then return nil end
    st.gameInner = nil
    Ctl.stop()
    st.party, st.page = gi.party, gi.page
    if st.page == "bag" and st.bag then
      st.bag.prompt, st.bag.menu, st.bag.view = nil, nil, "list"
      Bc.refresh(st.bag)
    elseif st.page == "party" and st.party then
      Pc.refresh(st.party)
    end
    return gi
  end
  function W.innerParty(pm, onDone)
    if st.closed or st.gameInner or not Pc then return false end
    st.gameInner = { pm = pm, onDone = onDone, page = st.page, party = st.party }
    st.party = Pc.open(pm, ctx)
    st.page = "party"
    return true
  end
  function W.innerDone() innerDone() end

  -- what a page's input / tap / tick said
  local function step(r)
    if st.closed or not r then return end
    if st.page == "party" then
      if r == "close" and st.gameInner then
        local gi = innerDone()
        if gi and gi.onDone then pcall(gi.onDone, gi.pm.result or {}) end
        return
      end
      if r == "close" then
        if st.inner then partyOverBagDone() else done() end
      elseif r == "bag" and Bc then
        bagOverParty()
      end
    elseif st.page == "bag" then
      if r == "close" then
        if st.innerBag then bagOverPartyDone() else done() end
      elseif r == "party" then
        local want = st.bag.wantParty
        st.bag.wantParty = nil
        if want then partyOverBag(want) end
      end
    end
  end

  function W.input(input, nav)
    if st.closed then return true end
    if st.page == "party" then step(Pc.input(st.party, input, nav))
    elseif st.page == "bag" then step(Bc.input(st.bag, input, nav))
    elseif Ctl.input(st.sum, input, nav) == "close" then done() end
    return true
  end
  function W.tap(arg)
    if st.closed or type(arg) ~= "number" then return end
    if st.page == "party" then step(Pc.tap(st.party, arg))
    elseif st.page == "bag" then step(Bc.tap(st.bag, arg))
    elseif Ctl.tap(st.sum, arg) == "close" then done() end
  end
  function W.scroll(dy)
    if st.page == "bag" then return Bc.scroll(st.bag, dy) end
    local S = st.page == "party" and st.party.sum or st.sum
    if not S then return end
    S.top = max(0, min(max(0, S.h - S.vis), S.top - dy))
  end
  function W.draw(body, clock, portrait)
    -- (on the Kanto Gear's screen, a battle's: the Bag's compact look, the party's smaller title and names)
    if st.bag then st.bag.compact = ctx.gear == true end
    if st.party then st.party.compact = ctx.gear == true end
    if st.page == "party" then
      if not st.closed then step(Pc.tick(st.party, clock)) end
      if st.page == "party" and partyView and st.party then partyView.draw(body, clock, portrait, st.party) return end
    end
    if st.page == "bag" then
      if not st.closed then step(Bc.tick(st.bag, clock)) end
      if st.page == "bag" and bagView and st.bag then bagView.draw(body, clock, portrait, st.bag) return end
      if st.page == "party" and partyView and st.party then partyView.draw(body, clock, portrait, st.party) end
      return
    end
    if st.page == "summary" and sumView then sumView.draw(body, clock, portrait, st.sum) end
  end
  function W.hints()
    if st.page == "party" and st.party then return Pc.hints(st.party) end
    if st.page == "bag" and st.bag then return Bc.hints(st.bag) end
    if st.sum then return Ctl.hints(st.sum) end
    return nil
  end
  -- (the game's bag gave an item while ours waited on GIVE)
  function W.giveFromBag(item, source, after)
    if st.party and not st.closed then Pc.giveFromBag(st.party, item, source, after) end
  end
  function W.bagState() return st.bag end
  -- (the game's words for the Bag while it's up: ItemUse's field message)
  function W.say(text, after)
    if st.closed then return false end
    if st.page == "bag" and st.bag then Bc.ui(st.bag).say(text, after) return true end
    if st.page == "party" and st.party then Pc.ui(st.party).say(text, after) return true end
    return false
  end
  function W.ask(text, after)
    if st.closed then return false end
    if st.page == "bag" and st.bag then Bc.ui(st.bag).ask(text, after) return true end
    if st.page == "party" and st.party then Pc.ui(st.party).ask(text, after) return true end
    return false
  end
  -- (an HP bar filling on the party, for the game: the Game Boy games' item results)
  function W.hp(i, from, to, after)
    if st.closed or not (st.page == "party" and st.party) then return false end
    Pc.ui(st.party).hp(i, from, to, after)
    return true
  end
  -- (a summary asked for from inside: a move to forget while the party's open)
  function W.forget(index, moveId, after)
    if not st.party or st.closed then return false end
    Pc.ui(st.party).forget(index, moveId, after)
    return true
  end
  function W.close()
    Ctl.stop()
    if not st.closed then
      st.closed = true
      if m.kind == "party" then m.result = m.result or { chosen = nil }
      elseif m.kind == "bag" then m.result = m.result or {}
      else m.result = m.result or { picked = false, index = st.sum.i } end
    end
  end
  return W
end
