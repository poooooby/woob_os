-- GTS: the Global Trade Station and Wonder Trade (the model is src/gts.lua, env.gts). Three tabs:
--   Wonder Trade  your Pokémon (the party, then a box) on the left, the chosen one on the right:
--                 Send, and a trainer somewhere in the world sends one back (the globe searching,
--                 the pad swapping the Poké Balls, the newcomer revealed)
--   GTS           the strangers' listings: what they offer, what they want; the ones you can answer
--                 glow; pick which of yours to give
--   My Deposit    post one of yours asking for a species (one you've seen) and a level; it's traded
--                 when someone answers; collect it, or withdraw yours
-- A trade evolution (Kadabra, Machoke ...) plays the game's own evolution scene, then the window comes
-- back.
--   buttons  Up / Down choose, L / R the box (or the letter, choosing a species), A, B back / close,
--            START the next tab
--   touch    the tabs, a row, the buttons; drag (or the wheel) scrolls
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, sin, cos, abs, pi, sqrt = math.floor, math.max, math.min, math.sin, math.cos, math.abs, math.pi, math.sqrt

local ROW_H, LROW_H, HEAD_H, M = 12, 17, 10, 3
local PARTICLES = 60
-- hit args
local TAB = 2000          -- + 1..3
local BOX_PREV, BOX_NEXT, GO, YES, NO, SHEET_ROW = 2010, 2011, 2012, 2013, 2014, 3000
local ROW = 4000          -- + i (the picker's or the listings' rows)
local LEVEL = 5000        -- + i

local C = {
  bg = { 10, 18, 34 }, card = { 20, 34, 60 }, cardTop = { 30, 52, 88 }, cardHi = { 44, 72, 116 },
  line = { 255, 255, 255, 0.07 }, text = { 236, 242, 250 }, soft = { 150, 172, 204 }, faint = { 92, 110, 140 },
  teal = { 40, 214, 204 }, blue = { 54, 144, 255 }, blueDeep = { 18, 64, 150 }, blueTop = { 80, 170, 255 },
  sea = { 24, 96, 190 }, land = { 60, 190, 120 }, green = { 64, 204, 112 }, red = { 236, 64, 70 },
  gold = { 250, 200, 60 }, goldTop = { 255, 232, 130 }, goldDark = { 176, 120, 16 }, shinyInk = { 74, 48, 0 }, white = { 255, 255, 255 }, black = { 0, 0, 0 },
  shade = { 0, 0, 0, 0.55 }, pink = { 255, 110, 170 }, boy = { 70, 150, 255 }, girl = { 255, 100, 150 },
  btnTop = { 60, 160, 255 }, btnFoot = { 20, 90, 200 }, okTop = { 80, 220, 140 }, okFoot = { 30, 150, 90 },
}
local TIER_C = {
  common = { 128, 128, 140 }, uncommon = { 52, 178, 92 }, rare = { 44, 124, 232 }, prized = { 152, 84, 224 },
  legendary = { 232, 170, 28 }, mythical = { 232, 82, 164 },
}
local TIER_KEY = {
  common = "auction.tier.common", uncommon = "auction.tier.uncommon", rare = "auction.tier.rare",
  prized = "auction.tier.prized", legendary = "auction.tier.legendary", mythical = "auction.tier.mythical",
}
local RANK = { common = 1, uncommon = 2, rare = 3, prized = 4, legendary = 5, mythical = 6 }
local CONFETTI = { C.gold, C.teal, C.blue, C.pink, C.green, C.white, C.red }
local TABS = { "wonder", "browse", "deposit" }
local TAB_KEY = { "gts.wonder", "gts.browse", "gts.deposit" }

local HINTS = {
  pick = { { "A", "hint.choose" }, { "L R", "hint.box" }, { "START", "hint.tab" }, { "B", "hint.close" } },
  pickBack = { { "A", "hint.choose" }, { "L R", "hint.box" }, { "B", "hint.back" } },
  browse = { { "A", "hint.trade" }, { "START", "hint.tab" }, { "B", "hint.close" } },
  deposit = { { "A", "hint.choose" }, { "START", "hint.tab" }, { "B", "hint.close" } },
  species = { { "A", "hint.choose" }, { "L R", "hint.letter" }, { "B", "hint.back" } },
  levels = { { "< >", "hint.level" }, { "A", "hint.ok" }, { "B", "hint.back" } },
  confirm = { { "< >", "hint.choose" }, { "A", "hint.ok" }, { "B", "hint.back" } },
  reveal = { { "A", "hint.ok" } },
  search = { { "A", "hint.skip" } },
}
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env)
  local K, Gx, Bx, T = env.K, env.gts, env.bx, env.T or NO_T
  local W = { title = "GTS", pad = true }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local st = {
    tab = "wonder", box = 1, rows = {}, cursor = 1, top = 0, visible = 6, picking = nil,
    lcursor = 1, ltop = 0, listings = {}, listingsAt = nil,
    sheet = nil, species = {}, scursor = 1, stop = 0, levels = 1, confirm = nil, yes = true,
    search = nil, reveal = nil, toast = nil, request = nil, depKey = nil, dep = {},
  }
  W.state = st
  if Bx and Bx.current then st.box = Bx.current(session()) or 1 end
  -- (back from the game's evolution scene: the tab it was on)
  local resume = ctx.resume
  if resume and resume.app == ctx.app and type(resume.state) == "table" then
    st.tab = resume.state.tab or st.tab
    st.box = resume.state.box or st.box
  end
  ctx.resume = nil

  local levelText = K.textCache(function(n) return T.f("boxes.level", n) end)
  local ivTotal = K.textCache(function(n) return T.f("auction.ivTotal", n) end)
  local rangeText = K.textCache(function(i)
    local r = Gx.LEVELS[i]
    if i == 1 or not r then return T("gts.anyLevel") end
    return T.f("gts.levelRange", r[1], r[2])
  end)
  local agoText = K.textCache(function(mins)
    if mins >= 60 then return T.f("gts.agoH", floor(mins / 60)) end
    return T.f("gts.agoM", mins)
  end)
  local function regionName(r) return T("gts.region." .. (Gx.REGIONS[r] or "kanto")) end

  local function toast(text, bad, sound)
    st.toast = { text = text, bad = bad, t = now() }
    se(sound or (bad and "SE_FAILURE" or "SE_SELECT"))
  end
  local function why(reason) return T(reason and ("reason.gts." .. reason) or "failed") end

  -- ------- confetti (a fixed pool)

  local P = {}
  for i = 1, PARTICLES do P[i] = { live = false, x = 0, y = 0, vx = 0, vy = 0, t0 = 0, life = 0, spin = 0, c = nil } end
  local nextP = 1
  local burstAt = { x = 0, y = 0 }
  local function confetti(n)
    for i = 1, n do
      local p = P[nextP]
      nextP = nextP % PARTICLES + 1
      local a = (i / n) * pi * 2 + sin(i * 3.3) * 0.3
      local v = 30 + (i * 29 % 45)
      p.live, p.x, p.y, p.vx, p.vy, p.t0, p.life = true, burstAt.x, burstAt.y, cos(a) * v, sin(a) * v - 25, now(), 1.8
      p.spin, p.c = (i * 0.37) % 1, CONFETTI[i % #CONFETTI + 1]
    end
  end
  W.state.particles = P

  -- ------- the rows (made on a change, not per frame)

  -- the picker: the party, then the box (or, answering a listing, every Pokémon that fits)
  local function rebuildRows()
    local s = session()
    local rows = st.rows
    local list
    if st.picking and st.picking.purpose == "accept" then
      list = Gx.matching(s, st.picking.listing)
    else
      list = Gx.candidates(s, st.box)
    end
    local n = 0
    for _, addr in ipairs(list) do
      local mon = Bx.get(s, addr)
      if mon then
        n = n + 1
        local r = rows[n] or {}
        rows[n] = r
        local ok, reason = Gx.canSend(s, addr)
        local info = Bx.info(mon, T)
        r.addr, r.mon, r.ok, r.why = addr, mon, ok, (not ok) and why(reason) or nil
        r.name, r.level, r.party = info and info.name or "?", tonumber(mon.level) or 1, addr.loc == "party"
        r.sp = tonumber(mon.species or mon.speciesId)
      end
    end
    for i = n + 1, #rows do rows[i] = nil end
    st.cursor = max(1, min(st.cursor, n))
    st.top = max(0, min(st.top, max(0, n - st.visible)))
  end
  -- the strangers' listings (their words made once per listing)
  local function rebuildListings()
    local s = session()
    local list = Gx.offers(s, Gx.now())
    do
      st.listingsAt = list
      -- (the ones you can answer first, then the rest, the traded last)
      local out = st.listings
      local n = 0
      for pass = 1, 3 do
        for _, L in ipairs(list) do
          local which = L.done and 3 or (L.canDo and 1 or 2)
          if which == pass then
            n = n + 1
            out[n] = L
            if not L.words then
              L.words = true
              L.offerName, L.askName = Gx.name(L.sp), Gx.name(L.ask)
              L.whoText = L.who[1] .. " · " .. regionName(L.who[2])
            end
          end
        end
      end
      for i = n + 1, #out do out[i] = nil end
      st.lcursor = max(1, min(st.lcursor, n))
    end
  end
  -- the deposit's words, again when it changes
  local function depositWords()
    local dep = Gx.posted()
    local key = dep and ((dep.received and "r" or "w") .. tostring(dep.at)) or "none"
    if st.depKey == key then return dep end
    st.depKey = key
    local d = st.dep
    if dep then
      local info = Bx.info(dep.mon, T)
      d.name = info and info.name or "?"
      d.seek = T.f("gts.seeking", Gx.name(dep.species), rangeText(dep.levels))
      d.sp = tonumber(dep.mon.species or dep.mon.speciesId)
      d.level = tonumber(dep.mon.level) or 1
      if dep.received then
        d.traded = T.f("gts.traded", d.name)
        d.from = T.f("gts.found", dep.stranger[1], regionName(dep.stranger[2]))
      end
    end
    return dep
  end

  -- ------- the trades: the search, the swap on the pad, the reveal

  local function tierOf(mon)
    local A = env.auction
    return A and A.tierOf and A.tierOf(tonumber(mon.species or mon.speciesId)) or "common"
  end
  -- the trade's show: `dur` seconds of searching (the globe), then found (the Poké Balls cross the
  -- pad), then the newcomer revealed
  local function show(recv, who, sent, dur)
    st.search = {
      t0 = now(), dur = dur, recv = recv, who = who, sent = sent, found = false, tier = tierOf(recv),
      text = T.f("gts.found", who[1], regionName(who[2])), initial = who[1]:sub(1, 1), girl = who[3] == 1,
    }
    st.picking, st.sheet, st.confirm = nil, nil, nil
    se(dur > 1 and "SE_POKENAV_ON" or "SE_BALL_TRADE")
  end
  local function reveal()
    local sh = st.search
    st.search = nil
    if not sh then return end
    local s = session()
    local mon = sh.recv
    local info = Bx.info(mon, T)
    local item = info and info.item and info.itemName
    st.reveal = {
      mon = mon, t0 = now(), tier = sh.tier, name = info and info.name or "?", level = tonumber(mon.level) or 1,
      ot = T.f("gts.ot", sh.who[1], regionName(sh.who[2])), item = item and T.f("gts.holding", item) or nil,
      ivs = (mon.ivs and ((mon.ivs.hp or 0) + (mon.ivs.atk or 0) + (mon.ivs.def or 0) + (mon.ivs.spa or 0)
        + (mon.ivs.spd or 0) + (mon.ivs.spe or 0))) or 0,
      evolve = Gx.evolveTarget(s, mon), shiny = info and info.shiny == true,
    }
    local rank = RANK[sh.tier] or 1
    -- (a shiny: the confetti and its own chime, whatever its tier)
    if rank >= 4 or st.reveal.shiny then confetti(50) end
    se(rank >= 5 and "SE_APPLAUSE" or ((rank >= 3 or st.reveal.shiny) and "SE_SHINY" or "SE_SUCCESS"))
    rebuildRows()
  end
  local function advance(t)
    local sh = st.search
    if not sh then return end
    if not sh.found and t >= sh.t0 + sh.dur then
      sh.found = true
      -- (the Poké Balls cross the pad: yours out, theirs in)
      if env.pad and env.pad.transfer then
        if sh.sent then pcall(env.pad.transfer, tonumber(sh.sent.species or sh.sent.speciesId), "out", "ball") end
        pcall(env.pad.transfer, tonumber(sh.recv.species or sh.recv.speciesId), "in", "ball")
      end
      se("SE_BALL_TRADE")
    elseif not sh.found and t >= (sh.tick or 0) then
      sh.tick = t + 0.45
      se("SE_DEX_SEARCH")
    end
    if sh.found and t >= sh.t0 + sh.dur + 1.8 then reveal() end
  end
  local function finishReveal()
    local rv = st.reveal
    st.reveal = nil
    if not rv then return end
    -- (a trade evolution: the game's own scene, then this window again)
    if rv.evolve and ctx.over then
      local s = session()
      ctx.over(function(onClose) Gx.openEvolution(s, rv.mon, rv.evolve, onClose) end, { tab = st.tab, box = st.box })
    end
  end

  local function doWonder(addr)
    local ok, recv, who, _, sent = Gx.wonder(session(), addr)
    if not ok then return toast(why(recv), true) end
    show(recv, who, sent, 2.5 + (floor(now() * 1000) % 1500) / 1000)
  end
  local function doAccept(addr)
    local L = st.picking and st.picking.listing
    if not L then return end
    local ok, recv, who, sent = Gx.accept(session(), L, addr)
    if not ok then return toast(why(recv), true) end
    show(recv, who, sent, 0.6)
    rebuildListings()
  end
  local function doDeposit()
    local r = st.request
    if not r then return end
    local ok, reason = Gx.deposit(session(), r.addr, r.species, st.levels, Gx.now())
    st.sheet, st.confirm, st.picking, st.request = nil, nil, nil, nil
    if not ok then return toast(why(reason), true) end
    if env.pad and env.pad.transfer then pcall(env.pad.transfer, r.sp, "out", "ball") end
    toast(T("gts.posted"), false, "SE_BALL_TRADE")
    rebuildRows()
  end
  local function doWithdraw()
    st.confirm = nil
    local ok, mon = Gx.withdraw(session())
    if not ok then return toast(why(mon), true) end
    if env.pad and env.pad.transfer then pcall(env.pad.transfer, tonumber(mon.species or mon.speciesId), "in", "ball") end
    local info = Bx.info(mon, T)
    toast(T.f("gts.withdrawn", info and info.name or "?"), false, "SE_BALL_TRADE")
    rebuildRows()
  end
  local function doCollect()
    local dep = Gx.posted()
    local mine = dep and dep.mon
    local ok, recv, who = Gx.collect(session())
    if not ok then return toast(why(recv), true) end
    show(recv, who, mine, 0.4)
  end

  local function ask(kind, text)
    st.confirm, st.yes = { kind = kind, text = text }, true
    se("SE_SELECT")
  end
  local function answer(yes)
    local c = st.confirm
    st.confirm = nil
    if not (c and yes) then return se("SE_SELECT") end
    if c.kind == "wonder" then doWonder(c.addr)
    elseif c.kind == "accept" then doAccept(c.addr)
    elseif c.kind == "deposit" then doDeposit()
    elseif c.kind == "withdraw" then doWithdraw() end
  end

  -- A on a row of the picker
  local function choose(i)
    local r = st.rows[i]
    if not r then return end
    if not r.ok then return toast(r.why or why("invalid"), true) end
    local purpose = st.picking and st.picking.purpose or "wonder"
    if purpose == "wonder" then
      ask("wonder", T.f("gts.confirmWonder", r.name))
      st.confirm.addr = r.addr
    elseif purpose == "accept" then
      local L = st.picking.listing
      ask("accept", T.f("gts.confirmAccept", r.name, L.offerName))
      st.confirm.addr = r.addr
    else
      -- (a deposit: which species you want for it, then the level)
      st.request = { addr = r.addr, sp = r.sp, name = r.name }
      local list = Gx.seenSpecies(session())
      st.species, st.scursor, st.stop = list, 1, 0
      st.sheet = "species"
      se("SE_SELECT")
    end
  end
  local function setTab(tab)
    if st.tab == tab then return end
    st.tab, st.picking, st.sheet, st.confirm = tab, nil, nil, nil
    st.cursor, st.top = 1, 0
    if tab == "wonder" then rebuildRows() elseif tab == "browse" then rebuildListings() end
    se("SE_SELECT")
  end
  local function nextTab(d)
    for i, t in ipairs(TABS) do
      if t == st.tab then return setTab(TABS[(i - 1 + d) % #TABS + 1]) end
    end
  end
  local function setBox(d)
    st.box = (st.box - 1 + d) % (Bx.BOXES or 14) + 1
    st.cursor, st.top = 1, 0
    rebuildRows()
    se("SE_SELECT")
  end
  local function pickFor(purpose, listing)
    st.picking = { purpose = purpose, listing = listing }
    st.cursor, st.top = 1, 0
    rebuildRows()
    if #st.rows == 0 and purpose == "accept" then
      st.picking = nil
      return toast(T("gts.noMatch"), true)
    end
    se("SE_SELECT")
  end
  -- A on a listing / the deposit card
  local function listingA(i)
    local L = st.listings[i]
    if not L then return end
    if L.done then return toast(why("gone"), true) end
    if not L.canDo then return toast(T("gts.noMatch"), true) end
    pickFor("accept", L)
  end
  local function depositA()
    local dep = depositWords()
    if not dep then return pickFor("deposit") end
    if dep.received then return doCollect() end
    ask("withdraw", T.f("gts.confirmWithdraw", st.dep.name))
  end
  -- species: L / R to the next letter
  local function letterJump(d)
    local list = st.species
    if #list == 0 then return end
    local here = Gx.name(list[st.scursor]):sub(1, 1)
    local i = st.scursor
    for _ = 1, #list do
      i = (i - 1 + d) % #list + 1
      if Gx.name(list[i]):sub(1, 1) ~= here then
        -- (to the first of that letter)
        if d < 0 then
          local first = Gx.name(list[i]):sub(1, 1)
          while i > 1 and Gx.name(list[i - 1]):sub(1, 1) == first do i = i - 1 end
        end
        st.scursor = i
        se("SE_SELECT")
        return
      end
    end
  end

  -- ------- buttons

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  local function moveIn(n, c, d)
    if n == 0 then return c end
    local nc = max(1, min(n, c + d))
    if nc ~= c then se("SE_SELECT") end
    return nc
  end
  function W.input(input, nav)
    cur = input
    local d = nav.up and -1 or (nav.down and 1 or 0)
    if st.reveal then
      if pressed("a") or pressed("b") then finishReveal() end
      return true
    end
    if st.search then
      -- (A skips the search; the trade has happened already)
      if pressed("a") and not st.search.found then st.search.dur = now() - st.search.t0 end
      return true
    end
    if st.confirm then
      if nav.left or nav.right then
        st.yes = not st.yes
        se("SE_SELECT")
      elseif pressed("a") then answer(st.yes)
      elseif pressed("b") then answer(false) end
      return true
    end
    if st.sheet == "species" then
      if d ~= 0 then st.scursor = moveIn(#st.species, st.scursor, d)
      elseif pressed("l") then letterJump(-1)
      elseif pressed("r") then letterJump(1)
      elseif pressed("a") and st.species[st.scursor] then
        st.request.species = st.species[st.scursor]
        st.sheet, st.levels = "levels", 1
        se("SE_SELECT")
      elseif pressed("b") then
        st.sheet, st.request = nil, nil
        se("SE_SELECT")
      end
      return true
    end
    if st.sheet == "levels" then
      if nav.left then st.levels = moveIn(#Gx.LEVELS, st.levels, -1)
      elseif nav.right then st.levels = moveIn(#Gx.LEVELS, st.levels, 1)
      elseif pressed("a") then
        st.sheet = nil
        ask("deposit", T.f("gts.confirmDeposit", st.request.name, Gx.name(st.request.species), rangeText(st.levels)))
      elseif pressed("b") then
        st.sheet = "species"
        se("SE_SELECT")
      end
      return true
    end
    if pressed("start") then
      nextTab(1)
      return true
    end
    if st.tab == "wonder" or st.picking then
      if pressed("b") then
        if st.picking then
          st.picking = nil
          if st.tab ~= "wonder" then st.cursor = 1 end
          se("SE_SELECT")
          return true
        end
        return false
      end
      if d ~= 0 then
        st.cursor = moveIn(#st.rows, st.cursor, d)
      elseif (pressed("l") or pressed("r")) and not (st.picking and st.picking.purpose == "accept") then
        setBox(pressed("l") and -1 or 1)
      elseif pressed("a") then choose(st.cursor) end
      return true
    end
    if pressed("b") then return false end
    if st.tab == "browse" then
      if d ~= 0 then st.lcursor = moveIn(#st.listings, st.lcursor, d)
      elseif pressed("a") then listingA(st.lcursor) end
    elseif pressed("a") then
      depositA()
    end
    return true
  end

  function W.tap(arg)
    if type(arg) ~= "number" then return end
    if st.reveal then return finishReveal() end
    if st.search then return end
    if st.confirm then
      if arg == YES then return answer(true) end
      if arg == NO then return answer(false) end
      return
    end
    if st.sheet == "species" then
      if arg > SHEET_ROW and st.species[arg - SHEET_ROW] then
        local i = arg - SHEET_ROW
        if st.scursor == i then
          st.request.species = st.species[i]
          st.sheet, st.levels = "levels", 1
        else
          st.scursor = i
        end
        se("SE_SELECT")
      elseif arg == NO then
        st.sheet, st.request = nil, nil
      end
      return
    end
    if st.sheet == "levels" then
      if arg > LEVEL and arg <= LEVEL + #Gx.LEVELS then
        st.levels = arg - LEVEL
        se("SE_SELECT")
      elseif arg == GO then
        st.sheet = nil
        ask("deposit", T.f("gts.confirmDeposit", st.request.name, Gx.name(st.request.species), rangeText(st.levels)))
      elseif arg == NO then
        st.sheet = "species"
      end
      return
    end
    if arg > TAB and arg <= TAB + #TABS then return setTab(TABS[arg - TAB]) end
    if arg == BOX_PREV then return setBox(-1) end
    if arg == BOX_NEXT then return setBox(1) end
    if arg == GO then
      if st.tab == "wonder" or st.picking then return choose(st.cursor) end
      if st.tab == "deposit" then return depositA() end
      return listingA(st.lcursor)
    end
    if arg > ROW then
      local i = arg - ROW
      if st.tab == "wonder" or st.picking then
        if st.cursor == i then return choose(i) end
        st.cursor = i
      else
        if st.lcursor == i then return listingA(i) end
        st.lcursor = i
      end
      se("SE_SELECT")
    end
  end

  function W.scroll(dy)
    if st.sheet == "species" then
      st.stop = max(0, min(max(0, #st.species - 8), st.stop - dy / ROW_H))
    elseif st.tab == "wonder" or st.picking then
      st.top = max(0, min(max(0, #st.rows - st.visible), st.top - dy / ROW_H))
    elseif st.tab == "browse" then
      st.ltop = max(0, min(max(0, #st.listings - st.visible), st.ltop - dy / LROW_H))
    end
  end

  function W.hints()
    if st.reveal then return T.list(HINTS.reveal) end
    if st.search then return T.list(HINTS.search) end
    if st.confirm then return T.list(HINTS.confirm) end
    if st.sheet == "species" then return T.list(HINTS.species) end
    if st.sheet == "levels" then return T.list(HINTS.levels) end
    if st.picking then return T.list(HINTS.pickBack) end
    if st.tab == "wonder" then return T.list(HINTS.pick) end
    if st.tab == "browse" then return T.list(HINTS.browse) end
    return T.list(HINTS.deposit)
  end

  -- ------- drawing (no tables made here)

  local function G() return K.graphics() end
  local function scaleAbout(cx, cy, k)
    local g = G()
    g.push()
    g.translate(K.X(cx), K.Y(cy))
    g.scale(k, k)
    g.translate(-K.X(cx), -K.Y(cy))
  end
  local function sparkle(cx, cy, s, c, a)
    local g = G()
    K.col(c, a)
    local x, y, r, q = K.X(cx), K.Y(cy), s * K.sc, s * K.sc * 0.22
    g.polygon("fill", x, y - r, x + q, y - q, x + r, y, x + q, y + q, x, y + r, x - q, y + q, x - r, y, x - q, y - q)
  end
  local function rays(cx, cy, r, clock, c, a)
    local g = G()
    g.push()
    g.translate(K.X(cx), K.Y(cy))
    g.rotate(clock * 0.5)
    K.col(c, a)
    local rr = r * K.sc
    for i = 0, 11 do
      local a0 = i * pi / 6
      g.polygon("fill", 0, 0, cos(a0) * rr, sin(a0) * rr, cos(a0 + 0.24) * rr, sin(a0 + 0.24) * rr)
    end
    g.pop()
  end
  local function pill(text, x, y, size, c, a)
    local w = K.width(text, size) + 3
    K.col(c, a)
    K.box("fill", K.R(x, y, w, size * 1.35), size * 0.6)
    K.text(text, x, y + size * 0.12, size, C.white, "center", w, a)
    return w
  end
  -- the Shiny badge: gold, a star at its left -> its width
  local function shinyBadge(x, y, size, clock, a)
    local word = T("auction.shiny")
    local w = K.width(word, size) + size * 1.6 + 3
    local b = K.R(x, y, w, size * 1.35)
    K.grad(b, size * 0.6, C.goldTop, C.goldDark, a)
    sparkle(x + size * 0.85, y + size * 0.68, size * 0.55 * (0.85 + 0.15 * sin((clock or 0) * 5)), C.white, a or 1)
    K.bold(word, x + size * 1.6, y + size * 0.12, size, C.shinyInk, "center", w - size * 1.6 - 1, a)
    return w
  end
  local function button(b, label, focused, kind, clock)
    local top, foot = C.btnTop, C.btnFoot
    if kind == "ok" then top, foot = C.okTop, C.okFoot elseif kind == "off" then top, foot = C.cardHi, C.card end
    if kind ~= "off" then
      local p = 0.5 + 0.5 * sin(clock * 4)
      K.col(top, 0.22 * p)
      K.box("fill", K.R(b[1] - 1.4, b[2] - 1.4, b[3] + 2.8, b[4] + 2.8), 4.4)
    end
    K.grad(b, 3.2, top, foot)
    if focused then K.focusRing(b, 3.2) end
    local fs = K.fit(label, 4.8, b[3] - 3)
    K.bold(label, b[1], b[2] + (b[4] - fs * 1.2) / 2, fs, kind == "off" and C.faint or C.white, "center", b[3])
  end

  -- the globe: a sea, meridians turning, parallels, a ring round it; pings while it searches
  local function globe(cx, cy, r, clock, searching)
    local g = G()
    local X, Y, sc = K.X(cx), K.Y(cy), K.sc
    for k = 3, 1, -1 do
      K.col(C.teal, 0.06 * k)
      g.circle("fill", X, Y, r * (1 + 0.15 * (4 - k)) * sc)
    end
    K.col(C.sea)
    g.circle("fill", X, Y, r * sc)
    K.col(C.blueTop, 0.35)
    g.circle("fill", X - r * 0.3 * sc, Y - r * 0.3 * sc, r * 0.55 * sc)
    -- (continents: blobs sliding across with the turn)
    for i = 0, 4 do
      local ph = ((clock * (searching and 0.35 or 0.12) + i * 0.21) % 1) * 2 - 1
      local px = cx + ph * r * 0.9
      local py = cy + sin(i * 2.3) * r * 0.45
      local w = (1 - ph * ph) * r * 0.32
      if w > 0.3 then
        K.col(C.land, 0.85)
        g.ellipse("fill", K.X(px), K.Y(py), w * sc, r * 0.18 * sc)
      end
    end
    g.setLineWidth(max(1, 0.35 * sc))
    for k = 0, 3 do
      local ph = (clock * (searching and 0.35 or 0.12) + k / 4) % 1
      local rx = r * abs(cos(ph * pi))
      K.col(C.teal, 0.45)
      g.ellipse("line", X, Y, max(0.5, rx * sc), r * sc)
    end
    K.col(C.teal, 0.35)
    for k = -1, 1 do
      local yy = k * r * 0.5
      local hw = r * sqrt(1 - (k * 0.5) ^ 2)
      g.line(X - hw * sc, Y + yy * sc, X + hw * sc, Y + yy * sc)
    end
    K.col(C.teal, 0.9)
    g.circle("line", X, Y, r * sc)
    -- (the ring)
    g.push()
    g.translate(X, Y)
    g.rotate(-0.35)
    K.col(C.gold, 0.55)
    g.ellipse("line", 0, 0, r * 1.42 * sc, r * 0.36 * sc)
    local ra = clock * (searching and 3 or 1)
    K.col(C.goldTop)
    g.circle("fill", cos(ra) * r * 1.42 * sc, sin(ra) * r * 0.36 * sc, max(1, r * 0.08 * sc))
    g.pop()
    if searching then
      for i = 0, 4 do
        local cyc = clock * 1.6 + i * 0.37
        local k = cyc % 1
        local seed = floor(cyc) * 5 + i
        local px = cx + sin(seed * 2.17) * r * 0.65
        local py = cy + cos(seed * 1.31) * r * 0.55
        K.col(C.goldTop, 1 - k)
        g.circle("line", K.X(px), K.Y(py), (0.6 + k * 3.5) * sc)
        g.circle("fill", K.X(px), K.Y(py), 0.6 * sc)
      end
    end
  end
  -- a stranger's badge: their initial on a disc (blue or pink), a gold rim
  local function badge(cx, cy, r, initial, girl)
    local g = G()
    K.col(C.gold)
    g.circle("fill", K.X(cx), K.Y(cy), (r + 0.6) * K.sc)
    K.col(girl and C.girl or C.boy)
    g.circle("fill", K.X(cx), K.Y(cy), r * K.sc)
    K.bold(initial, cx - r, cy - r * 0.62, r * 1.25, C.white, "center", r * 2)
  end

  local function drawParticles(clock, body)
    local g = G()
    K.scissor(body)
    for i = 1, PARTICLES do
      local p = P[i]
      if p.live then
        local age = clock - p.t0
        if age > p.life then
          p.live = false
        elseif age >= 0 then
          local px, py = p.x + p.vx * age, p.y + p.vy * age + 55 * age * age
          local a = min(1, (p.life - age) / 0.4)
          g.push()
          g.translate(K.X(px), K.Y(py))
          g.rotate(clock * 8 + p.spin * 6)
          K.col(p.c, a)
          local f = abs(cos(clock * 6 + p.spin * 4))
          g.rectangle("fill", -1.2 * K.sc, -0.6 * K.sc * f - 0.2 * K.sc, 2.4 * K.sc, 1.2 * K.sc * f + 0.4 * K.sc)
          g.pop()
        end
      end
    end
    K.scissor(nil)
  end

  -- the picker's list: the box's name with its arrows on top (not when answering a listing)
  local function drawPicker(x, y, w, h, clock)
    K.grad(K.R(x, y, w, h), 4, C.cardTop, C.card)
    local accept = st.picking and st.picking.purpose == "accept"
    local top = y + 1
    if not accept then
      K.chevron(x + 5, y + 5.3, 4, C.teal, -1)
      K.addHit(K.R(x, y, 12, 10), "win", BOX_PREV)
      K.chevron(x + w - 5, y + 5.3, 4, C.teal, 1)
      K.addHit(K.R(x + w - 12, y, 12, 10), "win", BOX_NEXT)
      local name = Bx.boxName(session(), st.box) or ""
      local ns = K.fit(name, 4.6, w - 26)
      K.bold(name, x + 12, y + 2.7 + (4.6 - ns) * 0.5, ns, C.text, "center", w - 24)
      K.col(C.line)
      K.box("fill", K.R(x, y + 10, w, 0.25))
      top = y + 10.5
    end
    local lh = y + h - 1 - top
    st.visible = max(1, floor(lh / ROW_H))
    if st.cursor > st.top + st.visible then st.top = st.cursor - st.visible end
    if st.cursor <= st.top then st.top = st.cursor - 1 end
    st.top = max(0, min(st.top, max(0, #st.rows - st.visible)))
    local clip = K.R(x, top, w, lh)
    K.scissor(clip)
    local first = floor(st.top) + 1
    for i = first, min(#st.rows, first + st.visible + 1) do
      local r = st.rows[i]
      local ry = top + (i - 1 - st.top) * ROW_H
      local rb = K.R(x + 1.5, ry + 0.4, w - 3, ROW_H - 0.8)
      if i == st.cursor then
        K.col(C.teal, 0.2)
        K.box("fill", rb, 2.5)
        K.ring(rb, 2.5, C.teal, 0.7, 0.5)
      end
      if env.monIconOf then pcall(env.monIconOf, r.mon, x + 3, ry + 0.5, 11, floor(clock * 3) % 2, r.ok and 1 or 0.4) end
      local ns = K.fit(r.name, 4.6, w - 40)
      K.text(r.name, x + 15, ry + (r.why and 1.2 or 3.4), ns, r.ok and C.text or C.faint)
      K.text(levelText(r.level), x + w - 4 - 20, ry + 3.4, 4, C.soft, "right", 20)
      if r.why then K.text(r.why, x + 15, ry + 6.6, 3.2, C.red, "left", w - 40) end
      if r.party then
        K.col(C.gold, 0.9)
        G().circle("fill", K.X(x + w - 4 - 22 - 1.5), K.Y(ry + ROW_H / 2), 1 * K.sc)
      end
      K.addHit(rb, "win", ROW + i, clip)
    end
    if #st.rows == 0 then K.text(T("gts.emptyBox"), x, top + lh / 2 - 3, 4.4, C.faint, "center", w) end
    K.scrollbar(x + w, top, lh, st.top, st.visible, #st.rows)
    K.scissor(nil)
  end

  -- the picker's right card: what's being done, the chosen Pokémon, the button
  local function drawPickCard(x, y, w, h, clock)
    K.grad(K.R(x, y, w, h), 4, C.cardTop, C.card)
    local purpose = st.picking and st.picking.purpose or "wonder"
    local r = st.rows[st.cursor]
    local gy = y + 15
    if h < 74 then
      -- (a short card, a small window's: the title alone above the Pokémon and its button)
      local title = purpose == "wonder" and T("gts.wonder")
        or (purpose == "accept" and st.picking.listing.offerName or T("gts.depositTitle"))
      local fs = K.fit(title, 5.2, w - 8)
      K.bold(title, x, y + 3 + (5.2 - fs) * 0.5, fs, C.text, "center", w)
      if purpose == "accept" then K.text(T("gts.pickGive"), x + 4, y + 10, 3.6, C.teal, "center", w - 8) end
    elseif purpose == "wonder" then
      globe(x + w / 2, gy, 10, clock, false)
      K.bold(T("gts.wonder"), x, y + 28, 5.4, C.text, "center", w)
      K.text(T("gts.wonderBlurb"), x + 4, y + 35, 3.6, C.soft, "center", w - 8)
    elseif purpose == "accept" then
      local L = st.picking.listing
      if env.monIcon then pcall(env.monIcon, L.sp, x + w / 2 - 8, y + 3, 16) end
      K.bold(L.offerName, x, y + 20, 5, C.text, "center", w)
      K.text(L.whoText, x, y + 26.5, 3.8, C.soft, "center", w)
      K.text(T("gts.pickGive"), x + 4, y + 33, 3.8, C.teal, "center", w - 8)
    else
      K.bold(T("gts.depositTitle"), x, y + 4, 5, C.text, "center", w)
      K.text(T("gts.depositBlurb"), x + 4, y + 11, 3.6, C.soft, "center", w - 8)
    end
    if r then
      local cy = y + h - 30
      K.col(C.bg, 0.5)
      K.box("fill", K.R(x + 3, cy - 2, w - 6, 15), 3)
      local drawn = env.monPic and r.sp and env.monPic(r.sp, x + 4, cy - 1.5, 13, 1, r.mon)
      if not drawn and env.monIconOf then pcall(env.monIconOf, r.mon, x + 4, cy - 1.5, 13, 0, 1) end
      local ns = K.fit(r.name, 4.8, w - 24)
      K.bold(r.name, x + 19, cy + 0.8, ns, C.text)
      K.text(levelText(r.level), x + 19, cy + 6.6, 3.8, C.soft)
      local label = T(purpose == "wonder" and "gts.send" or (purpose == "accept" and "gts.trade" or "gts.next"))
      button(K.R(x + 4, y + h - 13, w - 8, 10), label, false, r.ok and "go" or "off", clock)
      K.addHit(K.R(x + 4, y + h - 13, w - 8, 10), "win", GO)
    end
  end

  -- the strangers' listings: offer → want, the stranger; the ones you can answer glowing
  local function drawListings(x, y, w, h, clock)
    K.grad(K.R(x, y, w, h), 4, C.cardTop, C.card)
    local lh = h - 2
    st.visible = max(1, floor(lh / LROW_H))
    if st.lcursor > st.ltop + st.visible then st.ltop = st.lcursor - st.visible end
    if st.lcursor <= st.ltop then st.ltop = st.lcursor - 1 end
    st.ltop = max(0, min(st.ltop, max(0, #st.listings - st.visible)))
    local clip = K.R(x, y + 1, w, lh)
    K.scissor(clip)
    local first = floor(st.ltop) + 1
    local half = (w - 10) / 2
    for i = first, min(#st.listings, first + st.visible + 1) do
      local L = st.listings[i]
      local ry = y + 1 + (i - 1 - st.ltop) * LROW_H
      local rb = K.R(x + 1.5, ry + 0.4, w - 3, LROW_H - 0.8)
      if L.canDo then
        K.col(C.green, 0.1 + 0.06 * sin(clock * 3 + i))
        K.box("fill", rb, 2.5)
      end
      if i == st.lcursor then
        K.col(C.teal, 0.18)
        K.box("fill", rb, 2.5)
        K.ring(rb, 2.5, C.teal, 0.8, 0.5)
      end
      local a = L.done and 0.4 or 1
      local tc = TIER_C[L.tier] or TIER_C.common
      K.col(tc, a)
      K.box("fill", K.R(rb[1] + 0.6, rb[2] + 1.6, 1.1, rb[4] - 3.2), 0.5)
      -- (what they offer)
      if env.monIcon then pcall(env.monIcon, L.sp, x + 3.5, ry + 0.8, 11) end
      local ns = K.fit(L.offerName, 4.6, half - 16)
      K.bold(L.offerName, x + 15, ry + 1.6, ns, C.text, nil, nil, a)
      local pw = pill(T(TIER_KEY[L.tier] or TIER_KEY.common), x + 15, ry + 7.2, 3.2, tc, a)
      K.text(levelText(L.level), x + 17 + pw, ry + 7.2, 3.6, C.soft, nil, nil, a)
      if L.shiny then shinyBadge(x + 15 + pw + 3 + K.width(levelText(L.level), 3.6), ry + 7.2, 3.2, clock, a) end
      K.text(L.whoText, x + 15, ry + 11.6, 3.2, C.faint, nil, nil, a)
      -- (the swap arrows, then what they want)
      local mx = x + 5 + half
      K.chevron(mx - 0.5, ry + 5, 3.4, C.teal, 1, a)
      K.chevron(mx + 1.5, ry + 9, 3.4, C.teal, -1, a)
      local ax = mx + 5
      K.text(T("gts.wants"), ax, ry + 0.8, 3.2, C.faint, nil, nil, a)
      if env.monIcon then pcall(env.monIcon, L.ask, ax, ry + 4.5, 9) end
      local ans = K.fit(L.askName, 4.2, x + w - ax - 14)
      K.text(L.askName, ax + 11, ry + 5, ans, C.text, nil, nil, a)
      K.text(rangeText(L.levels), ax + 11, ry + 10.2, 3.4, C.soft, nil, nil, a)
      if L.done then
        pill(T("gts.done"), x + w - 4 - 16, ry + 1.4, 3.2, C.faint)
      elseif L.canDo then
        local t = T("gts.haveIt")
        local tw = K.width(t, 3.2) + 3
        pill(t, x + w - 4 - tw, ry + 1.4, 3.2, C.green, 0.7 + 0.3 * abs(sin(clock * 4)))
      end
      if i ~= st.lcursor then
        K.col(C.line)
        K.box("fill", K.R(x + 15, ry + LROW_H - 0.2, w - 17, 0.25))
      end
      K.addHit(rb, "win", ROW + i, clip)
    end
    if #st.listings == 0 then K.text(T("gts.none"), x, y + h / 2 - 3, 4.4, C.faint, "center", w) end
    K.scrollbar(x + w, y + 1, lh, st.ltop, st.visible, #st.listings)
    K.scissor(nil)
  end

  -- My Deposit: nothing posted (post one), waiting (yours on a pulsing ring), traded (collect)
  local function drawDeposit(x, y, w, h, clock)
    local dep = depositWords()
    local b = K.R(x, y, w, h)
    K.grad(b, 4, C.cardTop, C.card)
    local cx = x + w / 2
    if not dep then
      globe(cx, y + h * 0.36, min(16, h * 0.2), clock, false)
      K.bold(T("gts.depositTitle"), x, y + h * 0.62, 5.4, C.text, "center", w)
      K.text(T("gts.depositBlurb"), x + 8, y + h * 0.62 + 7, 3.8, C.soft, "center", w - 16)
      local go = K.R(cx - 30, y + h - 14, 60, 10)
      button(go, T("gts.depositBtn"), false, "go", clock)
      K.addHit(go, "win", GO)
      return
    end
    local d = st.dep
    local py = y + h * 0.34
    local r = min(17, h * 0.22)
    local g = G()
    if dep.received then
      rays(cx, py, r * 2.2, clock, C.gold, 0.16)
      K.col(C.gold, 0.5 + 0.3 * sin(clock * 5))
      g.circle("line", K.X(cx), K.Y(py), r * 1.05 * K.sc)
    else
      -- (waiting: rings going out from it)
      for k = 0, 2 do
        local f = (clock * 0.5 + k / 3) % 1
        K.col(C.teal, 0.5 * (1 - f))
        g.circle("line", K.X(cx), K.Y(py), r * (0.9 + f * 0.8) * K.sc)
      end
    end
    K.col(C.bg, 0.6)
    g.circle("fill", K.X(cx), K.Y(py), r * 0.95 * K.sc)
    local depMon = Gx.posted() and Gx.posted().mon
    if not (env.monPic and d.sp and env.monPic(d.sp, cx - r * 0.8, py - r * 0.8 + sin(clock * 2) * 0.6, r * 1.6, 1, depMon)) then
      if env.monIcon and d.sp then pcall(env.monIcon, d.sp, cx - r * 0.6, py - r * 0.6, r * 1.2) end
    end
    local ty = py + r + 3
    if dep.received then
      K.bold(d.traded, x, ty, 5, C.gold, "center", w)
      K.text(d.from, x, ty + 7, 3.8, C.soft, "center", w)
      sparkle(cx - r - 3, py - r * 0.5, 1.4 + 0.8 * abs(sin(clock * 3)), C.white, 0.9)
      sparkle(cx + r + 3, py + r * 0.4, 1.2 + 0.8 * abs(sin(clock * 4)), C.goldTop, 0.9)
      local go = K.R(cx - 30, y + h - 14, 60, 10)
      button(go, T("gts.collect"), false, "ok", clock)
      K.addHit(go, "win", GO)
    else
      K.bold(d.name, x, ty, 5, C.text, "center", w)
      K.text(d.seek, x, ty + 6.5, 3.8, C.teal, "center", w)
      local mins = floor(max(0, Gx.now() - (dep.at or 0)) / 60)
      local dots = floor(clock * 2) % 4
      K.text(T("gts.waiting"), x, ty + 12, 3.6, C.soft, "center", w)
      for k = 1, dots do
        g.circle("fill", K.X(cx + K.width(T("gts.waiting"), 3.6) / 2 + k * 1.6), K.Y(ty + 15.6), 0.4 * K.sc)
      end
      K.text(agoText(mins), x, ty + 17, 3.4, C.faint, "center", w)
      local go = K.R(cx - 30, y + h - 14, 60, 10)
      button(go, T("gts.withdraw"), false, "off", clock)
      K.addHit(go, "win", GO)
    end
  end

  -- the search: the globe spinning over the window, pings; then found: the stranger's badge
  local function drawSearch(x, y, w, h, clock)
    local sh = st.search
    local t = now()
    K.col(C.bg, 0.92)
    K.box("fill", K.R(x, y, w, h))
    local cx, cy = x + w / 2, y + h * 0.42
    local r = min(w, h) * 0.22
    if not sh.found then
      globe(cx, cy, r, clock, true)
      local label = T("gts.searching")
      K.bold(label, x, cy + r + 6, 5.2, C.text, "center", w)
      local dots = floor(clock * 3) % 4
      local lw = K.width(label, 5.2)
      for k = 1, dots do
        G().circle("fill", K.X(cx + lw / 2 + 1 + k * 2), K.Y(cy + r + 10.3), 0.6 * K.sc)
      end
    else
      local k = min(1, (t - sh.t0 - sh.dur) / 0.35)
      local s = k < 1 and k * 1.15 or 1
      globe(cx, cy, r * 0.8, clock, false)
      scaleAbout(cx, cy, s)
      badge(cx, cy - r * 0.15, r * 0.45, sh.initial, sh.girl)
      G().pop()
      K.bold(sh.text, x, cy + r + 6, 5, C.gold, "center", w)
    end
  end

  -- the reveal: the newcomer on a glow in its tier's colour (rays for the rare), springing in; its
  -- name, level, tier, OT and home, what it holds, its IVs
  local function drawReveal(x, y, w, h, clock)
    local rv = st.reveal
    local t = now()
    K.col(C.bg, 0.92)
    K.box("fill", K.R(x, y, w, h))
    local tc = TIER_C[rv.tier] or TIER_C.common
    local cx, cy = x + w / 2, y + h * 0.36
    local r = min(w, h) * 0.2
    burstAt.x, burstAt.y = cx, cy
    if (RANK[rv.tier] or 1) >= 3 then rays(cx, cy, r * 2.6, clock, tc, 0.2) end
    local g = G()
    for k = 3, 1, -1 do
      K.col(tc, 0.12 * k)
      g.circle("fill", K.X(cx), K.Y(cy), r * (0.55 + 0.25 * (3 - k)) * K.sc)
    end
    local age = t - rv.t0
    local s = age < 0.3 and (age / 0.3) * 1.2 or (age < 0.5 and 1.2 - (age - 0.3) or 1 + 0.03 * sin(clock * 3))
    scaleAbout(cx, cy, s)
    local sp = tonumber(rv.mon.species or rv.mon.speciesId)
    -- (the Pokémon itself: shiny when it really is)
    if not (env.monPic and env.monPic(sp, cx - r, cy - r, r * 2, 1, rv.mon)) and env.monIconOf then
      pcall(env.monIconOf, rv.mon, cx - r * 0.8, cy - r * 0.8, r * 1.6, 0, 1)
    end
    g.pop()
    sparkle(cx - r * 1.1, cy - r * 0.6, 1.5 + abs(sin(clock * 3)), C.white, 0.9)
    sparkle(cx + r * 1.15, cy + r * 0.5, 1.3 + abs(sin(clock * 4 + 1)), tc, 0.9)
    local ty = cy + r + 3
    local ns = K.fit(rv.name, 6, w - 20)
    K.bold(rv.name, x, ty, ns, C.text, "center", w)
    local tier = T(TIER_KEY[rv.tier] or TIER_KEY.common)
    local pw = K.width(tier, 3.6) + 3
    local lv = levelText(rv.level)
    local lw = K.width(lv, 4)
    local shw = rv.shiny and (K.width(T("auction.shiny"), 3.6) + 3.6 * 1.6 + 3 + 2) or 0
    local sx = cx - (pw + 2 + lw + shw) / 2
    pill(tier, sx, ty + 7.4, 3.6, tc)
    K.text(lv, sx + pw + 2, ty + 7.4, 4, C.soft)
    if rv.shiny then shinyBadge(sx + pw + 4 + lw, ty + 7.4, 3.6, clock) end
    K.text(rv.ot, x, ty + 13, 3.8, C.teal, "center", w)
    local yy = ty + 18.5
    if rv.item then
      K.text(rv.item, x, yy, 3.6, C.gold, "center", w)
      yy = yy + 5
    end
    K.text(ivTotal(rv.ivs), x, yy, 3.6, C.soft, "center", w)
    if rv.evolve then K.text(T("gts.evolving"), x, yy + 5, 3.8, C.goldTop, "center", w, 0.6 + 0.4 * abs(sin(clock * 4))) end
  end

  -- a sheet over the window: the species list (with its letters) or the level ranges
  local function drawSheet(x, y, w, h, clock)
    K.col(C.shade)
    K.box("fill", K.R(x, y, w, h))
    local sw, sh = min(w - 16, 130), min(h - 12, 92)
    local sx, sy = x + (w - sw) / 2, y + (h - sh) / 2
    K.grad(K.R(sx, sy, sw, sh), 5, C.cardTop, C.card)
    K.ring(K.R(sx, sy, sw, sh), 5, C.teal, 0.6, 0.6)
    if st.sheet == "species" then
      K.bold(T("gts.pickSpecies"), sx, sy + 3, 4.8, C.text, "center", sw)
      local top = sy + 10
      local vis = floor((sh - 12) / ROW_H)
      if st.scursor > st.stop + vis then st.stop = st.scursor - vis end
      if st.scursor <= st.stop then st.stop = st.scursor - 1 end
      st.stop = max(0, min(st.stop, max(0, #st.species - vis)))
      local clip = K.R(sx, top, sw, sh - 12)
      K.scissor(clip)
      local first = floor(st.stop) + 1
      for i = first, min(#st.species, first + vis + 1) do
        local sp = st.species[i]
        local ry = top + (i - 1 - st.stop) * ROW_H
        local rb = K.R(sx + 2, ry + 0.4, sw - 4, ROW_H - 0.8)
        if i == st.scursor then
          K.col(C.teal, 0.22)
          K.box("fill", rb, 2.5)
        end
        if env.monIcon then pcall(env.monIcon, sp, sx + 4, ry + 0.5, 11) end
        K.text(Gx.name(sp), sx + 17, ry + 3.2, 4.6, C.text)
        K.addHit(rb, "win", SHEET_ROW + i, clip)
      end
      if #st.species == 0 then K.text(T("gts.noneSeen"), sx, top + 20, 4, C.faint, "center", sw) end
      K.scrollbar(sx + sw, top, sh - 12, st.stop, vis, #st.species)
      K.scissor(nil)
    else
      K.bold(T("gts.pickLevels"), sx, sy + 3, 4.8, C.text, "center", sw)
      if env.monIcon then pcall(env.monIcon, st.request.species, sx + sw / 2 - 8, sy + 10, 16) end
      K.text(Gx.name(st.request.species), sx, sy + 27, 4.4, C.teal, "center", sw)
      -- (the ranges as chips, two rows)
      local n = #Gx.LEVELS
      local per = 6
      local cw = (sw - 8) / per
      for i = 1, n do
        local col, row = (i - 1) % per, floor((i - 1) / per)
        local cb = K.R(sx + 4 + col * cw + 0.5, sy + 36 + row * 10, cw - 1, 8.4)
        local on = i == st.levels
        if on then K.grad(cb, 2.5, C.btnTop, C.btnFoot) else K.col(C.cardHi) K.box("fill", cb, 2.5) end
        local label = rangeText(i)
        local fs = K.fit(label, 3.4, cb[3] - 1.5)
        K.text(label, cb[1], cb[2] + 2.3, fs, on and C.white or C.soft, "center", cb[3])
        K.addHit(cb, "win", LEVEL + i)
      end
      local go = K.R(sx + 6, sy + sh - 13, sw - 12, 10)
      button(go, T("gts.next"), false, "go", clock)
      K.addHit(go, "win", GO)
    end
  end
  local function drawConfirm(x, y, w, h, clock)
    local c = st.confirm
    K.col(C.shade)
    K.box("fill", K.R(x, y, w, h))
    local sw, sh = min(w - 20, 120), 34
    local sx, sy = x + (w - sw) / 2, y + (h - sh) / 2
    K.grad(K.R(sx, sy, sw, sh), 5, C.cardTop, C.card)
    K.ring(K.R(sx, sy, sw, sh), 5, C.teal, 0.6, 0.6)
    K.text(c.text, sx + 4, sy + 4, 4.4, C.text, "center", sw - 8)
    local bw = (sw - 12) / 2
    local yb, nb = K.R(sx + 4, sy + sh - 13, bw, 10), K.R(sx + 8 + bw, sy + sh - 13, bw, 10)
    button(nb, T("button.cancel"), not st.yes, "off", clock)
    button(yb, T(c.kind == "withdraw" and "gts.withdraw" or "button.ok"), st.yes, c.kind == "withdraw" and "off" or "go", clock)
    K.addHit(yb, "win", YES)
    K.addHit(nb, "win", NO)
  end

  -- the head: the globe, the three tabs (a count on My Deposit when a trade waits), the money
  local function drawHead(x, y, w, clock)
    globe(x + 4, y + 5, 3.4, clock, false)
    local sx, sw = x + 11, min(120, w * 0.72)
    K.col(C.card)
    K.box("fill", K.R(sx, y + 1, sw, 8), 2.6)
    local third = sw / 3
    for i = 1, 3 do
      local on = TABS[i] == st.tab
      local b = K.R(sx + 0.5 + (i - 1) * third, y + 1.5, third - 1, 7)
      if on then K.grad(b, 2.2, C.cardHi, C.card) end
      local label = T(TAB_KEY[i])
      local fs = K.fit(label, 4.2, third - 4)
      if on then K.bold(label, b[1], b[2] + 1.3, fs, C.text, "center", b[3])
      else K.text(label, b[1], b[2] + 1.3, fs, C.soft, "center", b[3]) end
      K.addHit(b, "win", TAB + i)
    end
    if Gx.waiting() > 0 then
      local g = G()
      local k = 1 + 0.15 * abs(sin(clock * 3))
      K.col(C.red)
      g.circle("fill", K.X(sx + sw - 1.5), K.Y(y + 1.5), 2.4 * k * K.sc)
      K.text("1", sx + sw - 4.5, y - 0.1, 3.2, C.white, "center", 6)
    end
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    advance(now())
    K.col(C.bg)
    K.box("fill", body)
    drawHead(x + M, y + 1, w - M * 2, clock)
    local top = y + HEAD_H + 1.5
    local bodyH = y + h - M - top
    if st.tab == "wonder" or st.picking then
      if portrait then
        local ch = min(78, bodyH * 0.5)
        drawPicker(x + M, top, w - M * 2, bodyH - ch - M, clock)
        K.scissor(body)
        drawPickCard(x + M, top + bodyH - ch, w - M * 2, ch, clock)
      else
        local lw = floor((w - M * 3) * 0.52)
        drawPicker(x + M, top, lw, bodyH, clock)
        K.scissor(body)
        drawPickCard(x + M * 2 + lw, top, w - M * 3 - lw, bodyH, clock)
      end
    elseif st.tab == "browse" then
      drawListings(x + M, top, w - M * 2, bodyH, clock)
    else
      drawDeposit(x + M, top, w - M * 2, bodyH, clock)
    end
    K.scissor(body)
    if st.sheet then drawSheet(x, y, w, h, clock) end
    if st.confirm then drawConfirm(x, y, w, h, clock) end
    if st.search then drawSearch(x, y, w, h, clock) end
    if st.reveal then drawReveal(x, y, w, h, clock) end
    drawParticles(clock, body)
    K.scissor(body)
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h), C.red, C.green, K.UI.hud) then
      st.toast = nil
    end
  end

  rebuildRows()
  if st.tab == "browse" then rebuildListings() end
  return W
end
