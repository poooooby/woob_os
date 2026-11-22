-- The modern menus' Pokémon screen (the party): its state and input, inside src/apps/menus.lua's window
-- (ctx.menu.kind "party"); drawn by src/apps/party_view.lua; the rules are src/party.lua's (env.party).
-- Six cards; A on one opens its menu (SUMMARY, its field moves, SWITCH, ITEM / MAIL, CANCEL; in a battle
-- SHIFT / SEND OUT, SUMMARY, CANCEL). The summary is the Boxes' (src/apps/summary_ctl.lua) inside the
-- same window. Picking for an item (use / give), a second Pokémon to switch with, Softboiled's target: the
-- same cards with a prompt on top. The game's words arrive as messages, yes / no questions, a list to
-- pick from, a level's stats; the HP bars fill before the words.
--
--   Pc = party(env, T, A, Ctl)        Ctl: summary_ctl's (A has its SUM_* args and the party's own)
--   P = Pc.open(m, ctx)               m: ctx.menu ({ kind = "party", party, order, mode, item, ... }) ->
--                                     the state the view draws (st.party)
--   Pc.input(P, input, nav) / Pc.tap(P, arg) -> "close" when the menu's done (m.result says how) ;
--   Pc.hints(P) ; Pc.tick(P, clock) (once a frame: an HP bar's fill, LearnMove's turn) ;
--   Pc.giveFromBag(P, item, source, after) (the game's bag gave one while ours waited)

local max, min, floor = math.max, math.min, math.floor

local HINTS = {
  list = { { "A", "hint.choose" }, { "B", "hint.close" } },
  battle = { { "A", "hint.choose" }, { "B", "hint.back" } },
  forced = { { "A", "hint.choose" } },
  pickFor = { { "A", "hint.choose" }, { "B", "hint.cancel" } },
  menu = { { "^ v", "hint.move" }, { "A", "hint.ok" }, { "B", "hint.back" } },
  msg = { { "A", "hint.ok" } },
  yesno = { { "< >", "hint.move" }, { "A", "hint.ok" }, { "B", "party.no" } },
  pick = { { "^ v", "hint.move" }, { "A", "hint.ok" }, { "B", "hint.cancel" } },
  multi = { { "A", "hint.choose" }, { "START", "party.confirm" }, { "B", "hint.cancel" } },
  confirm = { { "A", "party.confirm" }, { "^", "hint.back" }, { "B", "hint.cancel" } },
}

return function(env, T, A, Ctl)
  local Pt = env.party
  local Pc = {}
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  -- ------- the cards

  local function refresh(P)
    local c = P.c
    P.n = 0
    for i = 1, 6 do
      local mon = c.party[i]
      if mon then
        P.n = i
        if env.forgetMon then pcall(env.forgetMon, mon) end
        local ok, card = pcall(Pt.card, mon, T)
        card = ok and card or { mon = mon, name = "?", levelText = "", maxHp = 1, sp = 0 }
        if (c.mode == "use" or c.mode == "battleUse") and c.item then
          local okT, tag = pcall(Pt.tag, c, mon)
          card.tag = okT and tag and T(tag) or nil
          card.tagOk = okT and tag == "party.able"
        elseif c.mode == "move_tutor" then
          local okT, tag = pcall(Pt.tutorTag, c, mon)
          card.tag = okT and tag and T(tag) or nil
          card.tagOk = okT and tag == "party.able"
        elseif c.mode == "choose_multi" then
          -- (choosing a team: its place in the order, or that it can't go)
          local okE, yes = pcall(Pt.eligible, c, i)
          if not (okE and yes) then card.tag, card.tagOk = T("party.notAble"), false end
          card.orderN = nil
          for k, sl in ipairs(P.order or {}) do if sl == i then card.orderN = k end end
        end
        card.active = c.battle and (i == 1 or (c.double and i == 2)) or false
        -- (a partner's, in a battle fought beside one: the partner's name on it, the card faded)
        local okA, ally = pcall(Pt.ally, c, i)
        card.ally = okA and ally and (ally ~= "" and ally or T("party.partner")) or nil
        P.cards[i] = card
      else
        P.cards[i] = nil
      end
    end
    P.cur = max(1, min(P.cur, max(1, P.n)))
    P.at = now()
  end
  Pc.refresh = refresh

  function Pc.open(m, ctx)
    local c = { session = ctx.session or (env.session and env.session()), party = m.party or {}, order = m.order,
                bag = m.bag, item = m.item, giveSource = m.giveSource, battle = m.battle == true, mode = m.mode or "list",
                double = m.double == true, overlay = m.overlay, eligible = m.eligible, tutor = m.tutor,
                chooseFullMessage = m.chooseFullMessage }
    if not c.bag and c.session then c.bag = c.session.bag or c.session.inventory end
    local P = { m = m, c = c, cards = {}, cur = 1, n = 0, view = "pick", base = c.mode, menu = nil, prompt = nil,
                anim = nil, sum = nil, from = nil, at = now(), openAt = now(), lastRight = 2, hp = {},
                order = {}, max = max(1, tonumber(m.count) or 0), autoSlot = tonumber(m.autoSlot) }
    if c.mode == "choose_multi" and (tonumber(m.count) or 0) <= 0 then P.max = 3 end
    if m.pd then P.pd = { plan = m.pd, index = 1, frames = 0 } end
    refresh(P)
    P.cur = max(1, min(tonumber(m.cursor) or 1, max(1, P.n)))
    m.cursor = P.cur
    -- (what the top says: the item's name for using / giving)
    if c.item and (c.mode == "use" or c.mode == "battleUse" or c.mode == "give") and env.itemName then
      P.itemName = env.itemName(c.item)
      P.title = T.f(c.mode == "give" and "party.giveTo" or "party.useOn", P.itemName)
    elseif c.mode == "choose" then
      P.title = T("party.choose")
    elseif c.mode == "choose_multi" then
      P.title = T.f("party.chooseN", P.max)
    elseif c.mode == "move_tutor" then
      local okM, _, moveName = pcall(Pt.tutorMove, c)
      P.title = T.f("party.teach", okM and moveName or "")
    elseif c.mode == "battle_faint" then
      P.title = T("party.sendOutWhich")
    elseif c.battle then
      P.title = T("party.switchWhich")
    else
      P.title = T("party.title")
    end
    return P
  end

  local function setCur(P, i)
    if i == P.cur then return end
    P.cur = i
    P.m.cursor = i
    se("SE_SELECT")
  end

  -- ------- the flows' way in (src/party.lua's `ui`)

  local function back(P, mode, arg)
    P.prompt, P.anim, P.menu = nil, nil, nil
    if mode == "softboiled" then
      P.view = "softboiled"
      if arg then P.from = arg end
    else
      P.view, P.from = "pick", nil
    end
  end

  local function makeUi(P)
    local ui = {}
    function ui.say(text, after)
      local pages = Pt.pages(text)
      if #pages == 1 and pages[1] == "" then
        if after then after() end
        return
      end
      P.prompt = { kind = "msg", pages = pages, page = 1, after = after, at = now() }
    end
    function ui.ask(text, after)
      local pages = Pt.pages(text)
      P.prompt = { kind = "yesno", pages = { table.concat(pages, " ") }, page = 1, after = after, yes = true, at = now() }
    end
    function ui.pick(prompt, names, after)
      P.prompt = { kind = "pick", pages = { prompt }, page = 1, names = names, sel = 1, after = after, at = now() }
    end
    function ui.stats(mon, old, new, after)
      local ok, card = pcall(Pt.card, mon, T)
      local title = ok and card and (card.name .. "  " .. card.levelText) or ""
      P.prompt = { kind = "stats", page = 1, old = old, new = new, after = after, at = now(), pages = { title } }
    end
    function ui.hp(i, from, to, after)
      P.anim = { i = i, from = from, to = to, t0 = now(), dur = min(1.2, max(0.35, math.abs(to - from) / 60)), after = after }
    end
    function ui.forget(i, moveId, after)
      P.sumAfter = after
      P.sumForget = true
      P.sum = Ctl.open(P.c.party, i, { session = function() return P.c.session end, learn = moveId, back = "party.title" })
      P.view = "summary"
    end
    -- (soft: only when the flow left nothing open after it -- Ruby / Sapphire's mail, chained prompts)
    function ui.back(mode, arg, soft)
      if soft and (P.prompt or P.anim or P.view == "summary") then return end
      back(P, mode, arg)
    end
    function ui.battle(id, slot, moveSlot, used)
      P.prompt, P.anim = nil, nil
      P.m.result = { battle = { id = id, slot = slot, moveSlot = moveSlot, used = used } }
      P.done = true
    end
    function ui.close()
      P.prompt, P.anim = nil, nil
      P.done = true
    end
    function ui.leave(fn)
      P.prompt, P.anim = nil, nil
      P.m.after = fn
      P.done = true
    end
    function ui.refresh() refresh(P) end
    return ui
  end
  local uis = setmetatable({}, { __mode = "k" })
  local function uiOf(P)
    local u = uis[P]
    if not u then
      u = makeUi(P)
      uis[P] = u
    end
    return u
  end
  Pc.ui = uiOf

  local function run(P, f, ...)
    local ok, err = pcall(f, ...)
    if not ok then
      if env.log then pcall(env.log, "the party: %s", tostring(err)) end
      back(P, "list")
    end
  end

  -- ------- the summary inside

  local function openSummary(P, i)
    P.sumAfter, P.sumForget = nil, false
    local party = P.base == "list" and not P.c.battle
    P.sum = Ctl.open(P.c.party, i, { session = function() return P.c.session end, party = party, back = "party.title" })
    P.view = "summary"
    P.menu = nil
  end
  local function summaryClosed(P)
    local S = P.sum
    P.sum = nil
    Ctl.stop()
    local after = P.sumAfter
    P.sumAfter = nil
    if P.sumForget then
      P.sumForget = false
      P.view = "pick"
      refresh(P)
      if after then after(type(S.picked) == "number" and S.picked or nil) end
      return
    end
    -- (back on the one it ended on)
    P.view = "pick"
    if S and S.i and P.cards[S.i] then
      P.cur = S.i
      P.m.cursor = S.i
    end
    refresh(P)
  end

  -- ------- the menus

  local function openMenu(P, rows, kind)
    if not rows or #rows == 0 then return end
    P.menu = { rows = rows, sel = 1, kind = kind, at = now(), i = P.cur }
    P.view = "menu"
    se("SE_SELECT")
  end

  -- a battle's choice: the game's validate first (its words, back to picking), else the menu closes with it
  local function choose(P, i)
    local v = P.m.validate
    if v then
      local ok, why = pcall(v, i)
      if ok and why then
        se("SE_SELECT")
        P.menu, P.view = nil, "pick"
        return uiOf(P).say(why, function() back(P, "list") end)
      end
    end
    se("SE_SELECT")
    -- (a caller that answers itself -- the mailbox: ours stays open, its words and close come through
    -- PartyMenu.showMessage / close)
    local onChoose = P.m.onChoose
    if onChoose then
      P.menu, P.view = nil, "pick"
      local ok, err = pcall(onChoose, i, P.c.party[i])
      if not ok and env.log then pcall(env.log, "the party's onChoose: %s", tostring(err)) end
      return
    end
    P.m.result = { chosen = i }
    P.done = true
  end

  -- ------- choosing a team (choose_multi): in, out, done, or not after all

  local function enter(P, i)
    P.menu, P.view = nil, "pick"
    if #P.order >= P.max then
      se("SE_FAILURE")
      return uiOf(P).say(Pt.fullText(P.c, P.max), function() back(P, "list") end)
    end
    se("SE_SELECT")
    P.order[#P.order + 1] = i
    refresh(P)
    if #P.order == P.max then P.confirmFocus = true end
  end
  local function leave(P, i)
    P.menu, P.view = nil, "pick"
    se("SE_SELECT")
    for k, sl in ipairs(P.order) do if sl == i then table.remove(P.order, k) break end end
    P.confirmFocus = false
    refresh(P)
  end
  local function confirm(P)
    local v = P.m.validateChosen
    local list = {}
    for k, sl in ipairs(P.order) do list[k] = sl end
    if v then
      local ok, why = pcall(v, list)
      if ok and why then
        se("SE_FAILURE")
        return uiOf(P).say(why, function() back(P, "list") end)
      end
    end
    if #list == 0 then
      se("SE_FAILURE")
      return uiOf(P).say(Pt.noneText(), function() back(P, "list") end)
    end
    se("SE_SELECT")
    P.m.result = { list = list }
    P.done = true
  end
  local function cancelMulti(P)
    se("SE_SELECT")
    local function out()
      P.order = {}
      P.m.result = { cancelMulti = true }
      P.done = true
    end
    if P.m.immediateChooseCancel then return out() end
    uiOf(P).ask(Pt.cancelText(), function(yes) if yes then out() else back(P, "list") end end)
  end
  Pc.confirm = confirm

  local function runRow(P, r)
    local c, i = P.c, P.menu and P.menu.i or P.cur
    local act = r.act
    local ui = uiOf(P)
    if act == "SUMMARY" then
      se("SE_SELECT")
      return openSummary(P, i)
    elseif act == "SWITCH" then
      se("SE_SELECT")
      P.menu, P.view, P.from = nil, "switch", i
    elseif act == "ITEM" or act == "MAIL" then
      openMenu(P, Pt.itemActions(c, act), act)
    elseif act == "GIVE" then
      se("SE_SELECT")
      P.menu, P.view = nil, "pick"
      P.giving = i
      -- (the Bag over the party, choosing what to give; without ours, the game's)
      if env.bagCtl then
        P.wantBag = true
      elseif not Pt.openBag(c, function() P.giving = nil back(P, "list") refresh(P) end) then
        P.giving = nil
      end
    elseif act == "TAKE" then
      P.menu, P.view = nil, "pick"
      run(P, Pt.take, c, i, ui)
    elseif act == "TAKE_MAIL" then
      P.menu, P.view = nil, "pick"
      run(P, Pt.takeMail, c, i, ui)
    elseif act == "READ" then
      P.menu, P.view = nil, "pick"
      run(P, Pt.readMail, c, i, ui)
    elseif act == "SHIFT" or act == "SEND OUT" then
      choose(P, i)
    elseif act == "ENTER" then
      enter(P, i)
    elseif act == "NO ENTRY" then
      leave(P, i)
    elseif act == "HOOK" then
      se("SE_SELECT")
      P.menu, P.view = nil, "pick"
      run(P, Pt.hookRow, c, i, r)
    elseif r.fm then
      P.menu, P.view = nil, "pick"
      run(P, Pt.fieldMove, c, i, act, ui)
    else
      -- (CANCEL: an item menu goes back to the Pokémon's, the Pokémon's to the cards)
      se("SE_SELECT")
      if P.menu and (P.menu.kind == "ITEM" or P.menu.kind == "MAIL") then
        openMenu(P, P.mainRows, "main")
        return
      end
      P.menu, P.view = nil, "pick"
    end
  end

  -- A on a card, by what the menu is for
  local function act(P, i)
    local c = P.c
    local card = P.cards[i]
    if not card then return end
    if P.view == "switch" then
      se("SE_SELECT")
      if i ~= P.from then run(P, Pt.swap, c, P.from, i) end
      P.view, P.from = "pick", nil
      refresh(P)
      return
    end
    if P.view == "softboiled" then
      return run(P, Pt.softboiled, c, P.from, i, uiOf(P))
    end
    local base = P.base
    if base == "choose" then
      if card.egg and P.m.eggFails then return se("SE_FAILURE") end
      return choose(P, i)
    end
    if base == "move_tutor" then
      if card.egg then return se("SE_FAILURE") end
      se("SE_SELECT")
      return run(P, Pt.tutor, c, i, uiOf(P))
    end
    if base == "choose_multi" then
      P.mainRows = Pt.multiActions(c, i, P.order)
      return openMenu(P, P.mainRows, "main")
    end
    if base == "use" or base == "give" or base == "battleUse" then
      if card.egg then return se("SE_FAILURE") end
      if base == "use" then return run(P, Pt.use, c, i, uiOf(P)) end
      if base == "battleUse" then return run(P, env.bagRules.battleUse, c, c.party, c.order, i, c.item, uiOf(P)) end
      se("SE_SELECT")
      return run(P, Pt.give, c, i, c.item, c.giveSource, uiOf(P), function() uiOf(P).close() end)
    end
    if c.battle then
      P.mainRows = Pt.battleActions(c, i)
    else
      P.mainRows = Pt.actions(c, i)
    end
    openMenu(P, P.mainRows, "main")
  end

  -- what the window does next: "close" (done), "bag" (the Bag over the party, choosing what to give)
  function Pc.result(P)
    if P.done then
      P.m.tutorResult = P.c.tutorResult
      return "close"
    end
    if P.wantBag then return "bag" end
    return nil
  end

  -- B on the cards: away (a forced send-out can't)
  local function cancel(P)
    if P.view == "switch" or P.view == "softboiled" then
      se("SE_SELECT")
      P.view, P.from = "pick", nil
      return
    end
    if P.base == "battle_faint" then return se("SE_FAILURE") end
    if P.base == "choose_multi" then return cancelMulti(P) end
    se("SE_SELECT")
    P.m.result = { chosen = nil }
    P.done = true
  end

  -- the cards' moves: landscape the lead on the left, the rest down the right; a narrow screen one column
  local function nav(P, nv)
    local n = P.n
    if n < 1 then return end
    local i = P.cur
    if P.narrow then
      if nv.up then return setCur(P, (i - 2) % n + 1) end
      if nv.down then return setCur(P, i % n + 1) end
      return
    end
    if nv.left then
      if i > 1 then
        P.lastRight = i
        setCur(P, 1)
      end
    elseif nv.right then
      if i == 1 and n > 1 then setCur(P, min(n, max(2, P.lastRight or 2))) end
    elseif nv.up then
      setCur(P, (i - 2) % n + 1)
    elseif nv.down then
      setCur(P, i % n + 1)
    end
    if P.cur > 1 then P.lastRight = P.cur end
  end

  -- ------- input

  -- (the prompts' input, on any state with one in .prompt: the Bag's too)
  local function promptInput(P, input, nv)
    local p = P.prompt
    local function pressed(k) return input:wasPressed(k) end
    if p.kind == "yesno" then
      if nv.left or nv.right or nv.up or nv.down then
        p.yes = not p.yes
        se("SE_SELECT")
      elseif pressed("a") or pressed("b") then
        se("SE_SELECT")
        local yes = pressed("a") and p.yes
        P.prompt = nil
        if p.after then p.after(yes) end
      end
      return
    end
    if p.kind == "pick" then
      local n = #p.names
      if nv.up then p.sel = (p.sel - 2) % n + 1 se("SE_SELECT")
      elseif nv.down then p.sel = p.sel % n + 1 se("SE_SELECT")
      elseif pressed("a") then
        se("SE_SELECT")
        P.prompt = nil
        if p.after then p.after(p.sel - 1) end
      elseif pressed("b") then
        se("SE_SELECT")
        P.prompt = nil
        if p.after then p.after(nil) end
      end
      return
    end
    if pressed("a") or pressed("b") or pressed("start") then
      se("SE_SELECT")
      if p.kind == "stats" and p.page == 1 then
        p.page, p.at = 2, now()
        return
      end
      if p.kind == "msg" and p.page < #p.pages then
        p.page, p.at = p.page + 1, now()
        return
      end
      P.prompt = nil
      if p.after then p.after() end
    end
  end

  local function finishAnim(P)
    local a = P.anim
    P.anim = nil
    if a and a.after then a.after() end
  end

  function Pc.input(P, input, nv)
    if P.done then return "close" end
    local function pressed(k) return input:wasPressed(k) end
    -- (the Pokédude's: its own presses only; B stops it)
    if P.pd and not P.pdFeeding then
      if pressed("b") and not P.prompt then
        se("SE_SELECT")
        P.m.result = { pdCancel = true }
        P.done = true
      elseif P.prompt then
        promptInput(P, input, nv)
      end
      return Pc.result(P)
    end
    if P.anim then
      if pressed("a") or pressed("b") then finishAnim(P) end
      return Pc.result(P)
    end
    if P.prompt then
      promptInput(P, input, nv)
      return Pc.result(P)
    end
    if P.view == "summary" and P.sum then
      if Ctl.input(P.sum, input, nv) == "close" then summaryClosed(P) end
      return Pc.result(P)
    end
    if P.view == "menu" and P.menu then
      local mm = P.menu
      local n = #mm.rows
      if nv.up then mm.sel = (mm.sel - 2) % n + 1 se("SE_SELECT")
      elseif nv.down then mm.sel = mm.sel % n + 1 se("SE_SELECT")
      elseif pressed("a") then runRow(P, mm.rows[mm.sel])
      elseif pressed("b") then
        se("SE_SELECT")
        if mm.kind == "ITEM" or mm.kind == "MAIL" then openMenu(P, P.mainRows, "main")
        else P.menu, P.view = nil, "pick" end
      end
      return Pc.result(P)
    end
    -- (choosing a team: the Confirm button below the cards, START straight to it)
    if P.base == "choose_multi" and P.view == "pick" then
      if P.confirmFocus then
        if nv.up then P.confirmFocus = false se("SE_SELECT")
        elseif pressed("a") or pressed("start") then confirm(P)
        elseif pressed("b") then cancel(P) end
        return Pc.result(P)
      end
      if pressed("start") then
        P.confirmFocus = true
        se("SE_SELECT")
        return Pc.result(P)
      end
      if nv.down and P.cur == P.n then
        P.confirmFocus = true
        se("SE_SELECT")
        return Pc.result(P)
      end
    end
    nav(P, nv)
    local startCancels = P.view == "pick" and not P.c.battle and not (P.base == "choose" and P.m.chooseCancelStart == false)
    if pressed("a") then act(P, P.cur)
    elseif pressed("b") or (pressed("start") and startCancels) then cancel(P) end
    return Pc.result(P)
  end

  Pc.promptInput = promptInput
  local function promptTap(P, arg)
    local p = P.prompt
    if p.kind == "yesno" and (arg == A.YES or arg == A.NO) then
      se("SE_SELECT")
      P.prompt = nil
      if p.after then p.after(arg == A.YES) end
    elseif p.kind == "pick" and arg > A.PICK and arg <= A.PICK + #p.names then
      se("SE_SELECT")
      P.prompt = nil
      if p.after then p.after(arg - A.PICK - 1) end
    elseif p.kind == "pick" and arg == A.NO then
      se("SE_SELECT")
      P.prompt = nil
      if p.after then p.after(nil) end
    elseif arg == A.MSG and (p.kind == "msg" or p.kind == "stats") then
      se("SE_SELECT")
      if p.kind == "stats" and p.page == 1 then p.page, p.at = 2, now()
      elseif p.kind == "msg" and p.page < #p.pages then p.page, p.at = p.page + 1, now()
      else
        P.prompt = nil
        if p.after then p.after() end
      end
    end
  end
  Pc.promptTap = promptTap

  function Pc.tap(P, arg)
    if P.done then return "close" end
    if P.anim then
      finishAnim(P)
      return Pc.result(P)
    end
    local p = P.prompt
    if p then
      promptTap(P, arg)
      return Pc.result(P)
    end
    -- (a lesson plays itself: its Skip (the Close button) stops it, as B; nothing else)
    if P.pd and not P.pdFeeding then
      if arg == A.CANCEL then
        se("SE_SELECT")
        P.m.result = { pdCancel = true }
        P.done = true
      end
      return Pc.result(P)
    end
    if P.view == "summary" and P.sum then
      if Ctl.tap(P.sum, arg) == "close" then summaryClosed(P) end
      return Pc.result(P)
    end
    if P.view == "menu" and P.menu then
      local k = arg - A.MENU
      if k >= 1 and k <= #P.menu.rows then
        P.menu.sel = k
        runRow(P, P.menu.rows[k])
      elseif arg == A.SCRIM then
        se("SE_SELECT")
        P.menu, P.view = nil, "pick"
      end
      return Pc.result(P)
    end
    if arg == A.CANCEL then
      cancel(P)
    elseif arg == A.CONFIRM then
      confirm(P)
    elseif arg > A.CARD and arg <= A.CARD + 6 then
      local i = arg - A.CARD
      if P.cards[i] then
        if i ~= P.cur then
          P.cur = i
          P.m.cursor = i
        end
        act(P, i)
      end
    end
    return Pc.result(P)
  end

  -- once a frame: an HP bar's fill ending, the game's move learning taking its turn
  local function press(k)
    return { wasPressed = function(_, x) return x == k end, isDown = function() return false end }
  end
  local NV = {}
  -- (the Pokédude's next press, a frame at a time; "use": the item on the one chosen, the game's words, done)
  local function pdStep(P)
    local pd = P.pd
    pd.frames = pd.frames + 1
    local e = pd.plan[pd.index]
    if not e or pd.frames < (e.at or 0) then return end
    pd.index = pd.index + 1
    if e.use then
      local slot = P.c.order and P.c.order[P.cur] or P.cur
      local ok, text = pcall(P.m.pdUse or function() return nil end, slot)
      se("SE_USE_ITEM")
      refresh(P)
      return uiOf(P).say(ok and text or "", function()
        -- (the shown slot: the battle's order turns it into the real one, as for a switch)
        P.m.result = { pdSelect = P.cur }
        P.done = true
      end)
    end
    if e.key then
      NV.up, NV.down, NV.left, NV.right = e.key == "up", e.key == "down", e.key == "left", e.key == "right"
      P.pdFeeding = true
      local ok, err = pcall(Pc.input, P, press(e.key), NV)
      P.pdFeeding = false
      if not ok and env.log then pcall(env.log, "the Pokédude's party: %s", tostring(err)) end
    end
  end

  function Pc.tick(P, clock)
    local a = P.anim
    if a and clock - a.t0 >= a.dur then finishAnim(P) end
    if P.pd and not P.done and not P.prompt then pdStep(P) end
    -- (the tutor's script naming the one already: straight to it)
    if P.autoSlot and P.base == "move_tutor" and not P.prompt then
      local i = P.autoSlot
      P.autoSlot = nil
      if P.cards[i] then
        P.cur, P.m.cursor = i, i
        run(P, Pt.tutor, P.c, i, uiOf(P))
      end
    end
    if Pt.pump then pcall(Pt.pump) end
    return Pc.result(P)
  end

  -- the game's bag gave an item to the one waiting (ITEM -> GIVE)
  function Pc.giveFromBag(P, item, source, after)
    local i = P.giving or P.cur
    P.giving = nil
    P.view, P.menu = "pick", nil
    run(P, Pt.give, P.c, i, item, source, uiOf(P), function()
      back(P, "list")
      if after then after() end
    end)
  end

  local LESSON = { { "B", "hint.skip" } }
  function Pc.hints(P)
    local h
    if P.pd and not P.prompt then return T.list(LESSON) end
    if P.prompt then
      local k = P.prompt.kind
      h = k == "yesno" and HINTS.yesno or (k == "pick" and HINTS.pick or HINTS.msg)
    elseif P.view == "summary" and P.sum then
      return Ctl.hints(P.sum)
    elseif P.view == "menu" then
      h = HINTS.menu
    elseif P.view == "switch" or P.view == "softboiled" or P.base == "use" or P.base == "give"
        or P.base == "battleUse" then
      h = HINTS.pickFor
    elseif P.base == "choose_multi" then
      h = P.confirmFocus and HINTS.confirm or HINTS.multi
    elseif P.base == "choose" or P.base == "move_tutor" then
      h = HINTS.pickFor
    elseif P.base == "battle_faint" then
      h = HINTS.forced
    elseif P.c.battle then
      h = HINTS.battle
    else
      h = HINTS.list
    end
    return T.list(h)
  end

  return Pc
end
