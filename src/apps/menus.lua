-- The modern menus' window (src/menus.lua opens it full screen in place of the game's own: Sh.openFull
-- "menus", ctx.menu), one of:
--   - kind "summary": a party Pokémon's summary, in the Pokédex's glass, as Boxes shows one (its state
--     and input src/apps/summary_ctl.lua's, drawn by src/apps/boxes_summary.lua). From the party menu: Up /
--     Down its Pokémon, L / R the tabs, its moves reordered outside battle. Choosing a move to forget (a TM,
--     a level up, an evolution): the moves with the new one below, A the one to forget, B none. Its answer
--     goes back in ctx.menu.result ({ picked = the slot 0..3 | false, index }) as it closes.
--   - kind "party": the party menu (src/apps/party.lua's state and input, src/apps/party_view.lua's
--     drawing, src/party.lua's rules); its answer in ctx.menu.result ({ chosen = the shown slot | nil }),
--     what runs after it closes (a field move) in ctx.menu.after. ctx.menu.win: this window, so
--     src/menus.lua can hand it what the game's bag gave.
--
--   window(ctx, env, makeSummary, makeParty) -> win (src/apps.lua)

local max, min = math.max, math.min

-- hit args (the summary view's, then the party's)
local A = { SUM_BACK = 600, SUM_PREV = 601, SUM_NEXT = 602, SUM_PIC = 603, SUM_TAB = 610, SUM_MOVE = 620,
            CARD = 700, MENU = 720, SCRIM = 740, CANCEL = 741, MSG = 742, YES = 743, NO = 744, PICK = 750 }
local SUM_TABS = { "sum.tab.info", "sum.tab.stats", "sum.tab.moves" }
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env, makeSummary, makeParty)
  local K, T = env.K, env.T or NO_T
  local m = ctx.menu or {}
  local W = { title = "" }
  local st = { closed = false }
  W.state = st
  local function session() return ctx.session or (env.session and env.session()) end
  local Ctl = env.summaryCtl(env, T, A, SUM_TABS)
  local sumView = makeSummary and makeSummary(K, env, T, st, A, SUM_TABS) or nil
  local Pc, partyView = nil, nil
  if m.kind == "party" then
    Pc = env.partyCtl(env, T, A, Ctl)
    st.party = Pc.open(m, ctx)
    partyView = makeParty and makeParty(K, env, T, A, sumView) or nil
    m.win = W
  else
    st.sum = Ctl.open(m.list or {}, m.index or 1, { session = session, party = m.party, learn = m.learn,
                                                   forgetMove = m.forgetMove, back = m.back })
  end

  -- (done: the answer for the game, then the host closes and src/menus.lua answers it)
  local function done()
    if st.closed then return end
    st.closed = true
    Ctl.stop()
    if Pc then
      m.result = m.result or { chosen = nil }
    else
      m.result = { picked = st.sum.picked, index = st.sum.i }
    end
    if ctx.done then ctx.done() end
  end

  function W.input(input, nav)
    if st.closed then return true end
    if Pc then
      if Pc.input(st.party, input, nav) == "close" then done() end
      return true
    end
    if Ctl.input(st.sum, input, nav) == "close" then done() end
    return true
  end
  function W.tap(arg)
    if st.closed or type(arg) ~= "number" then return end
    if Pc then
      if Pc.tap(st.party, arg) == "close" then done() end
      return
    end
    if Ctl.tap(st.sum, arg) == "close" then done() end
  end
  function W.scroll(dy)
    local S = Pc and st.party.sum or st.sum
    if not S then return end
    S.top = max(0, min(max(0, S.h - S.vis), S.top - dy))
  end
  function W.draw(body, clock, portrait)
    if Pc then
      if not st.closed and Pc.tick(st.party, clock) == "close" then return done() end
      if partyView then partyView.draw(body, clock, portrait, st.party) end
      return
    end
    if sumView then sumView.draw(body, clock, portrait, st.sum) end
  end
  function W.hints()
    if Pc then return Pc.hints(st.party) end
    return Ctl.hints(st.sum)
  end
  -- (the game's bag gave an item while ours waited on GIVE)
  function W.giveFromBag(item, source, after)
    if Pc and not st.closed then Pc.giveFromBag(st.party, item, source, after) end
  end
  -- (a summary asked for from inside: a move to forget while the party's open -- the evolution's)
  function W.forget(index, moveId, after)
    if not Pc or st.closed then return false end
    Pc.ui(st.party).forget(index, moveId, after)
    return true
  end
  function W.close()
    Ctl.stop()
    if not st.closed then
      st.closed = true
      if Pc then m.result = m.result or { chosen = nil }
      else m.result = m.result or { picked = false, index = st.sum.i } end
    end
  end
  return W
end
