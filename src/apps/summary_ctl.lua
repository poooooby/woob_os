-- The summary's state and input, shared by the windows that show one (src/apps/boxes.lua's, and the modern
-- menus' src/apps/menus.lua): one Pokémon of a list at a time, its page from env.bx's summary, drawn by
-- src/apps/boxes_summary.lua. Up / Down the list's next Pokémon (its cry), L / R or Left / Right the tab;
-- on Moves, A takes the moves (Up / Down along them); a party Pokémon's moves trade places (A on one,
-- then A on another), never in battle. Choosing a move to forget (S.learn: the move it would learn, a
-- fifth row): A forgets the chosen one (an HM refused unless S.forgetMove), on the new move or B keeps
-- them all; S.picked holds the answer (the slot 0..3, or false) once it's chosen. Choosing a move for something
-- (S.choose: the question's word key -- a PP item's move, the Move Deleter's): the same page without the fifth row,
-- A on any move, B none.
-- Words: only from actions (Bx.summary makes the page's), never while drawing.
--
--   Ctl = summaryCtl(env, T, A, TABS)   A: the window's hit args (SUM_BACK / PREV / NEXT / PIC / TAB / MOVE)
--   S = Ctl.open(list, index, opts)     opts: session() ; party (its moves may be reordered) ; learn (a move
--                                       id: choosing one to forget) ; forgetMove (an HM may go) ; choose (a word
--                                       key: choosing one of its moves) ; back (the top's word) -> the state the
--                                       view draws (st.sum)
--   Ctl.show(S, i, quiet) ; Ctl.input(S, input, nav) -> "close" when it's done ; Ctl.tap(S, arg) -> the same ;
--   Ctl.hints(S) -> the hint list ; Ctl.stop() (the picture's animation)

local HINTS = {
  sum = { { "^ v", "sum.hint.mon" }, { "L R", "hint.tab" }, { "A", "dex.hint.cry" }, { "B", "hint.back" } },
  sumMoves = { { "^ v", "sum.hint.mon" }, { "L R", "hint.tab" }, { "A", "sum.hint.moves" }, { "B", "hint.back" } },
  sumMove = { { "^ v", "sum.hint.move" }, { "B", "hint.back" } },
  sumMoveSwap = { { "^ v", "sum.hint.move" }, { "A", "sum.hint.swap" }, { "B", "hint.back" } },
  sumSwapping = { { "^ v", "sum.hint.move" }, { "A", "sum.hint.here" }, { "B", "hint.cancel" } },
  forget = { { "^ v", "sum.hint.move" }, { "A", "sum.hint.forget" }, { "B", "sum.hint.keep" } },
  forgetNew = { { "^ v", "sum.hint.move" }, { "A", "sum.hint.keep" }, { "B", "sum.hint.keep" } },
  choose = { { "^ v", "sum.hint.move" }, { "A", "sum.hint.choose" }, { "B", "hint.cancel" } },
}

return function(env, T, A, TABS)
  local Bx = env.bx
  local Ctl = {}
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local function cry(S)
    local rec = S.rec
    if not rec or rec.egg then return end
    if env.dexSprite then env.dexSprite.start(rec.sp, rec.shiny) end
    S.at = now()
    if env.cry then pcall(env.cry, rec.sp) end
  end
  Ctl.cry = cry

  -- the i-th of the list shown (its page made here, an action, never a draw), its cry
  function Ctl.show(S, i, quiet)
    local n = #S.list
    if n == 0 then return end
    i = (i - 1) % n + 1
    S.i, S.swap, S.top, S.hm = i, nil, 0, false
    S.move = (S.learn or S.choose) and 1 or nil
    S.rec = Bx.summary(S.session(), S.list[i], T)
    S.at = now()
    if not quiet then se("SE_SELECT") end
    cry(S)
  end

  function Ctl.open(list, index, opts)
    opts = opts or {}
    local S = { list = list, i = index or 1, rec = nil, tab = 1, move = nil, swap = nil, party = opts.party == true,
                top = 0, h = 0, vis = 0, at = now(), openAt = now(), lines = {}, shown = { 0, 0, 0, 0, 0, 0 },
                session = opts.session or function() return nil end, back = opts.back, hm = false, picked = nil,
                forgetMove = opts.forgetMove == true }
    -- (choosing one of its moves: the moves tab, the cursor on the first)
    if type(opts.choose) == "string" then
      S.choose, S.tab, S.party = opts.choose, #TABS, false
    end
    -- (choosing a move to forget: the moves tab, the cursor on the first, the move it would learn below)
    if opts.learn and Bx.moveRecord then
      local ok, rec = pcall(Bx.moveRecord, opts.learn, T)
      if ok and rec then
        S.learn, S.tab, S.party = rec, #TABS, false
      end
    end
    -- (a battle's or a script's party is read fresh: no page kept from before)
    for _, mon in ipairs(list) do pcall(Bx.forget, mon) end
    Ctl.show(S, S.i, true)
    return S
  end

  function Ctl.stop() if env.dexSprite then env.dexSprite.stop() end end

  local function tab(S, t)
    if S.learn or S.choose then return end
    t = (t - 1) % #TABS + 1
    if t == S.tab then return end
    S.tab, S.move, S.swap, S.top = t, nil, nil, 0
    se("SE_SELECT")
  end

  -- a move chosen to forget (k: the row; the one past the four is the new move: none forgotten)
  local function forget(S, k)
    local moves = S.rec and S.rec.moves or {}
    local m = moves[k]
    if not m then
      se("SE_SELECT")
      S.picked = false
      return "close"
    end
    if S.learn and Bx.isHm and Bx.isHm(m.id) and not S.forgetMove then
      se("SE_FAILURE")
      S.hm = true
      return nil
    end
    se("SE_SELECT")
    S.picked = m.slot - 1
    return "close"
  end

  -- a move chosen: the first time it's shown; again (a party Pokémon's), picked up to swap; another
  -- picked while one is held: the two trade places
  local function move(S, k)
    if S.learn or S.choose then
      if S.move == k then return forget(S, k) end
      S.move, S.hm = k, false
      se("SE_SELECT")
      return nil
    end
    local moves = S.rec and S.rec.moves or {}
    if not moves[k] then return nil end
    if S.swap then
      if S.swap ~= k then
        local mon = S.list[S.i]
        if Bx.swapMoves(mon, moves[S.swap].slot, moves[k].slot) then
          S.rec = Bx.summary(S.session(), mon, T)
        end
      end
      S.swap, S.move = nil, k
      se("SE_SELECT")
      return nil
    end
    if S.move == k and S.party and #moves > 1 then S.swap = k
    else S.move = k end
    se("SE_SELECT")
    return nil
  end

  function Ctl.input(S, input, nav)
    local function pressed(k) return input:wasPressed(k) end
    local moves = S.rec and S.rec.moves or {}
    if S.learn or S.choose then
      local last = #moves + (S.learn and 1 or 0)
      if nav.up then
        if S.move > 1 then S.move, S.hm = S.move - 1, false se("SE_SELECT") end
      elseif nav.down then
        if S.move < last then S.move, S.hm = S.move + 1, false se("SE_SELECT") end
      elseif pressed("a") then
        return forget(S, S.move)
      elseif pressed("b") then
        se("SE_SELECT")
        S.picked = false
        return "close"
      end
      return nil
    end
    if S.move then
      if nav.up then
        if S.move > 1 then S.move = S.move - 1 se("SE_SELECT") end
      elseif nav.down then
        if S.move < #moves then S.move = S.move + 1 se("SE_SELECT") end
      elseif pressed("a") then
        if S.party and #moves > 1 then
          if S.swap then move(S, S.move)
          else
            S.swap = S.move
            se("SE_SELECT")
          end
        end
      elseif pressed("b") then
        if S.swap then S.swap = nil else S.move = nil end
        se("SE_SELECT")
      end
      return nil
    end
    if pressed("b") then
      se("SE_SELECT")
      return "close"
    elseif pressed("l") or nav.left then tab(S, S.tab - 1)
    elseif pressed("r") or nav.right then tab(S, S.tab + 1)
    elseif nav.up then if #S.list > 1 then Ctl.show(S, S.i - 1) end
    elseif nav.down then if #S.list > 1 then Ctl.show(S, S.i + 1) end
    elseif pressed("a") then
      if S.tab == #TABS and #moves > 0 then
        S.move = 1
        se("SE_SELECT")
      else
        cry(S)
      end
    end
    return nil
  end

  function Ctl.tap(S, arg)
    if arg == A.SUM_BACK then
      se("SE_SELECT")
      if S.learn or S.choose then S.picked = false end
      return "close"
    end
    if S.learn or S.choose then
      if arg > A.SUM_MOVE and arg <= A.SUM_MOVE + 5 then return move(S, arg - A.SUM_MOVE) end
      if arg == A.SUM_PIC then cry(S) end
      return nil
    end
    if arg == A.SUM_PREV then return Ctl.show(S, S.i - 1) end
    if arg == A.SUM_NEXT then return Ctl.show(S, S.i + 1) end
    if arg == A.SUM_PIC then return cry(S) end
    if arg > A.SUM_TAB and arg <= A.SUM_TAB + #TABS then return tab(S, arg - A.SUM_TAB) end
    if arg > A.SUM_MOVE and arg <= A.SUM_MOVE + 4 then return move(S, arg - A.SUM_MOVE) end
    return nil
  end

  function Ctl.hints(S)
    local h
    if S.choose then
      h = HINTS.choose
    elseif S.learn then
      local moves = S.rec and S.rec.moves or {}
      h = S.move and S.move > #moves and HINTS.forgetNew or HINTS.forget
    elseif S.move then
      if S.swap then h = HINTS.sumSwapping
      elseif S.party and #(S.rec and S.rec.moves or {}) > 1 then h = HINTS.sumMoveSwap
      else h = HINTS.sumMove end
    else
      h = S.tab == #TABS and HINTS.sumMoves or HINTS.sum
    end
    return T.list(h)
  end

  return Ctl
end
