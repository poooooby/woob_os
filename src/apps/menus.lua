-- The modern menus' window (src/menus.lua opens it full screen in place of the game's own: Sh.openFull
-- "menus", ctx.menu): a party Pokémon's summary, in the Pokédex's glass, as Boxes shows one (its state
-- and input src/apps/summary_ctl.lua's, drawn by src/apps/boxes_summary.lua). From the party menu: Up /
-- Down its Pokémon, L / R the tabs, its moves reordered outside battle. Choosing a move to forget (a TM, a
-- level up, an evolution): the moves with the new one below, A the one to forget, B none. Its answer goes
-- back in ctx.menu.result ({ picked = the slot 0..3 | false, index }) as it closes.
--
--   window(ctx, env, makeSummary) -> win (src/apps.lua)   ctx.menu = { kind = "summary", list, index, party,
--                                                                    learn, forgetMove, back }

local max, min = math.max, math.min

-- hit args (the summary view's)
local A = { SUM_BACK = 600, SUM_PREV = 601, SUM_NEXT = 602, SUM_PIC = 603, SUM_TAB = 610, SUM_MOVE = 620 }
local SUM_TABS = { "sum.tab.info", "sum.tab.stats", "sum.tab.moves" }
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env, makeSummary)
  local K, T = env.K, env.T or NO_T
  local m = ctx.menu or {}
  local W = { title = "" }
  local st = { closed = false }
  W.state = st
  local function session() return ctx.session or (env.session and env.session()) end
  local Ctl = env.summaryCtl(env, T, A, SUM_TABS)
  st.sum = Ctl.open(m.list or {}, m.index or 1, { session = session, party = m.party, learn = m.learn,
                                                 forgetMove = m.forgetMove, back = m.back })
  local view = makeSummary and makeSummary(K, env, T, st, A, SUM_TABS) or nil

  -- (done: the answer for the game, then the host closes and src/menus.lua answers it)
  local function done()
    if st.closed then return end
    st.closed = true
    Ctl.stop()
    m.result = { picked = st.sum.picked, index = st.sum.i }
    if ctx.done then ctx.done() end
  end

  function W.input(input, nav)
    if st.closed then return true end
    if Ctl.input(st.sum, input, nav) == "close" then done() end
    return true
  end
  function W.tap(arg)
    if st.closed or type(arg) ~= "number" then return end
    if Ctl.tap(st.sum, arg) == "close" then done() end
  end
  function W.scroll(dy)
    local S = st.sum
    S.top = max(0, min(max(0, S.h - S.vis), S.top - dy))
  end
  function W.draw(body, clock, portrait)
    if view then view.draw(body, clock, portrait, st.sum) end
  end
  function W.hints() return Ctl.hints(st.sum) end
  function W.close()
    Ctl.stop()
    if not st.closed then
      st.closed = true
      m.result = m.result or { picked = false, index = st.sum.i }
    end
  end
  return W
end
