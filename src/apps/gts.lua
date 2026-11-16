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
-- The look is the Pokédex's glass: the backdrop's lights turning to the shown Pokémon's types (your
-- chosen one, a listing's, your deposit's, the newcomer's; the globe's teal and blue while it searches),
-- glass panes, the chosen one popping up on a pane of its colour, type pills. Its motion, numbers only in
-- `mv`: the tabs' thumb sliding, rows rising in one after another (from the side the box turned to), the
-- highlight gliding and the lists scrolling smoothly, sheets popping up over a dim, the search fading in
-- over the window, the newcomer springing up on a disc of its type with its card settling in under it.
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
  ink = { 28, 28, 30 }, soft = { 112, 112, 120 }, faint = { 160, 160, 170 }, accent = { 10, 132, 255 },
  white = { 255, 255, 255 }, black = { 0, 0, 0 }, fill = { 118, 118, 128, 0.16 }, track = { 118, 118, 128, 0.16 },
  teal = { 0, 160, 166 }, tealLit = { 40, 214, 204 }, sea = { 34, 118, 212 }, seaTop = { 120, 196, 255 },
  land = { 70, 196, 120 }, green = { 52, 199, 89 }, red = { 255, 59, 48 }, gold = { 232, 170, 28 },
  goldTop = { 255, 226, 120 }, goldDark = { 176, 120, 16 }, shinyInk = { 74, 48, 0 }, pink = { 255, 110, 170 },
  boy = { 70, 150, 255 }, girl = { 255, 100, 150 }, slate = { 120, 132, 178 },
  -- (the GTS's own lights: the globe's teal and blue, when no Pokémon is shown)
  globeA = { 40, 196, 206 }, globeB = { 74, 134, 255 },
}
local SHADE_TOP, SHADE_FOOT = { 255, 255, 255, 0.28 }, { 0, 0, 0, 0.16 }
-- the types' colours (the game's ids; 18 WoobleDex's Fairy)
local TYPE = {
  [0] = { 168, 168, 120 }, [1] = { 192, 48, 40 }, [2] = { 168, 144, 240 }, [3] = { 160, 64, 160 },
  [4] = { 224, 192, 104 }, [5] = { 184, 160, 56 }, [6] = { 168, 184, 32 }, [7] = { 112, 88, 152 },
  [8] = { 184, 184, 208 }, [9] = { 104, 160, 144 }, [10] = { 240, 128, 48 }, [11] = { 104, 144, 240 },
  [12] = { 120, 200, 80 }, [13] = { 248, 208, 48 }, [14] = { 248, 88, 136 }, [15] = { 152, 216, 216 },
  [16] = { 112, 56, 248 }, [17] = { 112, 88, 72 }, [18] = { 238, 153, 172 },
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
local CONFETTI = { C.gold, C.tealLit, C.accent, C.pink, C.green, C.sea, C.red }
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
  -- (a type's word, kept per type: made when a row is made, read while drawing)
  local typeWords = {}
  local function typeWord(id, fallback)
    if id == nil then return nil end
    local w = typeWords[id]
    if w == nil then
      w = env.typeName and env.typeName(id) or fallback or ""
      typeWords[id] = w
    end
    return w
  end
  -- (o.t1 / o.t2 the types' ids, o.n1 / o.n2 their words: from a Pokémon's preview, or a species')
  local function setTypes(o, info, sp)
    local t1, t2
    local ts = info and not info.egg and info.types
    if ts and ts[1] then
      t1, t2 = ts[1].id, ts[2] and ts[2].id or nil
    elseif not info and sp ~= nil and Gx.types then
      t1, t2 = Gx.types(sp)
    end
    o.t1, o.t2 = t1, t2
    o.n1 = typeWord(t1, ts and ts[1] and ts[1].name)
    o.n2 = typeWord(t2, ts and ts[2] and ts[2].name)
  end

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
        r.sp = (tonumber(mon.species or mon.speciesId) or mon.species)
        r.shiny = info and info.shiny == true
        setTypes(r, info or false)
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
            if not L.typed then
              L.typed = true
              setTypes(L, nil, L.sp)
              L.a1 = Gx.types and (Gx.types(L.ask)) or nil
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
      d.sp = (tonumber(dep.mon.species or dep.mon.speciesId) or dep.mon.species)
      d.level = tonumber(dep.mon.level) or 1
      d.shiny = info and info.shiny == true
      setTypes(d, info or false)
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
    return A and A.tierOf and A.tierOf((tonumber(mon.species or mon.speciesId) or mon.species)) or "common"
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
      sp = (tonumber(mon.species or mon.speciesId) or mon.species),
    }
    setTypes(st.reveal, info or false)
    -- (the newcomer animated as the Pokédex's, where the game has an animation)
    if env.dexSprite then pcall(env.dexSprite.start, st.reveal.sp, st.reveal.shiny) end
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
        if sh.sent then pcall(env.pad.transfer, (tonumber(sh.sent.species or sh.sent.speciesId) or sh.sent.species), "out", "ball") end
        pcall(env.pad.transfer, (tonumber(sh.recv.species or sh.recv.speciesId) or sh.recv.species), "in", "ball")
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
    if env.pad and env.pad.transfer then pcall(env.pad.transfer, (tonumber(mon.species or mon.speciesId) or mon.species), "in", "ball") end
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

  function W.close() if env.dexSprite then pcall(env.dexSprite.stop) end end

  -- ------- drawing (no tables made here)

  local G = nil               -- (the host's graphics, taken each frame)
  local bodyNow = nil
  -- the motion's numbers
  local mv = {
    lastT = nil, coloured = false, r = 0.16, g = 0.77, b = 0.81, r2 = 0.29, g2 = 0.53, b2 = 1,
    tab = nil, tabX = 1, listAt = -10, listDir = 0, box = nil, picking = false, listings = nil,
    curY = 1, curPrev = nil, top = 0, lcurY = 1, lcurPrev = nil, ltop = 0, scurY = 1, scurPrev = nil, stop = 0,
    pickMon = nil, pickAt = -10, sheetKey = nil, sheetAt = -10, depKey = nil, depAt = -10,
  }
  W.motion = mv
  local function rowIn(since, i) return K.stagger(since, i, 0.03, 0.26) end

  local function scaleAbout(cx, cy, k)
    G.push()
    G.translate(K.X(cx), K.Y(cy))
    G.scale(k, k)
    G.translate(-K.X(cx), -K.Y(cy))
  end
  local function sparkle(cx, cy, s, c, a)
    K.col(c, a)
    -- (two thin diamonds crossed: love's filled polygons have to be convex)
    local x, y, r, q = K.X(cx), K.Y(cy), s * K.sc, s * K.sc * 0.3
    G.polygon("fill", x, y - r, x + q, y, x, y + r, x - q, y)
    G.polygon("fill", x - r, y, x, y - q, x + r, y, x, y + q)
  end
  local function rays(cx, cy, r, clock, c, a)
    G.push()
    G.translate(K.X(cx), K.Y(cy))
    G.rotate(clock * 0.5)
    K.col(c, a)
    local rr = r * K.sc
    for i = 0, 11 do
      local a0 = i * pi / 6
      G.polygon("fill", 0, 0, cos(a0) * rr, sin(a0) * rr, cos(a0 + 0.24) * rr, sin(a0 + 0.24) * rr)
    end
    G.pop()
  end
  -- a coloured chip with white words (a tier, "Traded", "You have it!") -> its width
  local function chip(text, x, y, size, c, a)
    local w = K.width(text, size) + 3
    K.col(c, a)
    K.box("fill", K.R(x, y, w, size * 1.35), size * 0.6)
    K.text(text, x, y + size * 0.12, size, C.white, "center", w, a)
    return w
  end
  local function chipW(text, size) return K.width(text, size) + 3 end
  -- a type's pill -> its width
  local function typePill(id, name, x, y, h, size, a, ring)
    local pw = K.width(name, size) + 5
    local b = K.R(x, y, pw, h)
    K.col(TYPE[id] or C.faint, a)
    K.box("fill", b, h / 2)
    if ring then K.ring(b, h / 2, C.white, 0.55 * (a or 1), 0.4) end
    K.text(name, x, y + (h - size * 1.2) / 2, size, C.white, "center", pw, a)
    return pw
  end
  local function pillsW(o, size)
    if not o.t1 then return 0 end
    local w = K.width(o.n1 or "", size) + 5
    if o.t2 then w = w + 1.5 + K.width(o.n2 or "", size) + 5 end
    return w
  end
  local function pills(o, x, y, h, size, a, ring)
    if not o.t1 then return 0 end
    local w = typePill(o.t1, o.n1 or "", x, y, h, size, a, ring)
    if o.t2 then w = w + 1.5 + typePill(o.t2, o.n2 or "", x + w + 1.5, y, h, size, a, ring) end
    return w
  end
  -- the Shiny badge: gold, a star at its left -> its width
  local function shinyW(size) return K.width(T("auction.shiny"), size) + size * 1.6 + 3 end
  local function shinyBadge(x, y, size, clock, a)
    local word = T("auction.shiny")
    local w = K.width(word, size) + size * 1.6 + 3
    local b = K.R(x, y, w, size * 1.35)
    K.grad(b, size * 0.6, C.goldTop, C.goldDark, a)
    sparkle(x + size * 0.85, y + size * 0.68, size * 0.55 * (0.85 + 0.15 * sin((clock or 0) * 5)), C.white, a or 1)
    K.bold(word, x + size * 1.6, y + size * 0.12, size, C.shinyInk, "center", w - size * 1.6 - 1, a)
    return w
  end
  -- a capsule button: "go" (the accent, breathing), "ok" (green, breathing), "gray" (a grey fill, dark
  -- words), "off" (can't: grey, faint words)
  local function button(b, label, focused, kind, clock)
    local fill = kind == "ok" and C.green or ((kind == "off" or kind == "gray") and C.fill or C.accent)
    local rad = min(b[4] / 2, 3.2)
    if kind == "go" or kind == "ok" then
      local p = 0.5 + 0.5 * sin(clock * 4)
      K.col(fill, 0.2 * p)
      K.box("fill", K.R(b[1] - 1.3, b[2] - 1.3, b[3] + 2.6, b[4] + 2.6), rad + 1.3)
    end
    K.col(fill)
    K.box("fill", b, rad)
    if focused then K.focusRing(b, rad) end
    local fs = K.fit(label, 4.6, b[3] - 3)
    local ink = kind == "off" and C.faint or (kind == "gray" and C.ink or C.white)
    K.bold(label, b[1], b[2] + (b[4] - fs * 1.2) / 2, fs, ink, "center", b[3])
  end
  -- a big Poké Ball's outline turning slowly (a pane's watermark)
  local function ballMark(cx, cy, r, turn, a)
    local pr = r * K.sc
    G.push()
    G.translate(K.X(cx), K.Y(cy))
    G.rotate(turn)
    K.col(C.white, a)
    G.setLineWidth(max(1, r * 0.11 * K.sc))
    G.circle("line", 0, 0, pr)
    G.line(-pr, 0, -pr * 0.36, 0)
    G.line(pr * 0.36, 0, pr, 0)
    G.circle("line", 0, 0, pr * 0.3)
    G.circle("fill", 0, 0, pr * 0.14)
    G.pop()
  end
  -- a soft disc in a type's colour (the Boxes preview's): its halo, a light in it, a bright rim
  local function disc(cx, cy, r, tid, a)
    local c = TYPE[tid] or C.slate
    local X, Y = K.X(cx), K.Y(cy)
    K.col(c, 0.14 * a)
    G.circle("fill", X, Y, r * 1.22 * K.sc)
    K.col(c, 0.3 * a)
    G.circle("fill", X, Y, r * K.sc)
    K.glow(cx, cy, r * 0.95, r * 0.85, C.white, 0.32 * a)
    K.col(C.white, 0.55 * a)
    G.setLineWidth(max(1, 0.3 * K.sc))
    G.circle("line", X, Y, r * K.sc)
  end
  -- a Pokémon's picture centred on cx, cy, `size` units, at `pop` of itself: the Pokédex's (the chosen
  -- one animated, the rest breathing), else the still; its shadow under it
  local function picture(sp, mon, cx, cy, size, clock, at, pop, a, shiny)
    if sp == nil then return end
    K.col(C.black, 0.16 * a)
    G.ellipse("fill", K.X(cx), K.Y(cy + size * 0.44), size * 0.26 * pop * K.sc, size * 0.05 * K.sc)
    if env.dexSprite then
      env.dexSprite.draw(sp, cx, cy, size, clock, at, pop, a * K.getFade(), shiny, mon)
    elseif env.monPic then
      env.monPic(sp, cx - size / 2 * pop, cy - size / 2 * pop, size * pop, a * K.getFade(), mon)
    end
    K.rescissor()
  end
  -- a pane in the shown Pokémon's colour (the summary's hero): a light from the top, a Poké Ball turning
  local function hero(b, clock)
    K.shadow(b, 4, 1.2, 0.1)
    G.setColor(mv.r, mv.g, mv.b, 0.74 * K.getFade())
    K.box("fill", b, 4)
    K.grad(b, 4, SHADE_TOP, SHADE_FOOT)
    K.ring(b, 4, C.white, 0.6, 0.4)
    G.intersectScissor(K.X(b[1]), K.Y(b[2]), b[3] * K.sc, b[4] * K.sc)
    ballMark(b[1] + b[3] - b[4] * 0.32, b[2] + b[4] * 0.6, b[4] * 0.62, clock * 0.18, 0.14)
    K.scissor(bodyNow)
  end

  -- the globe: a sea, meridians turning, parallels, a ring round it; pings while it searches
  local function globe(cx, cy, r, clock, searching)
    local X, Y, sc = K.X(cx), K.Y(cy), K.sc
    for k = 3, 1, -1 do
      K.col(C.tealLit, 0.07 * k)
      G.circle("fill", X, Y, r * (1 + 0.15 * (4 - k)) * sc)
    end
    K.col(C.sea)
    G.circle("fill", X, Y, r * sc)
    K.col(C.seaTop, 0.35)
    G.circle("fill", X - r * 0.3 * sc, Y - r * 0.3 * sc, r * 0.55 * sc)
    -- (continents: blobs sliding across with the turn)
    local speed = searching and 0.35 or 0.12
    for i = 0, 4 do
      local ph = ((clock * speed + i * 0.21) % 1) * 2 - 1
      local px = cx + ph * r * 0.9
      local py = cy + sin(i * 2.3) * r * 0.45
      local w = (1 - ph * ph) * r * 0.32
      if w > 0.3 then
        K.col(C.land, 0.9)
        G.ellipse("fill", K.X(px), K.Y(py), w * sc, r * 0.18 * sc)
      end
    end
    G.setLineWidth(max(1, 0.35 * sc))
    for k = 0, 3 do
      local ph = (clock * speed + k / 4) % 1
      local rx = r * abs(cos(ph * pi))
      K.col(C.white, 0.4)
      G.ellipse("line", X, Y, max(0.5, rx * sc), r * sc)
    end
    K.col(C.white, 0.3)
    for k = -1, 1 do
      local yy = k * r * 0.5
      local hw = r * sqrt(1 - (k * 0.5) ^ 2)
      G.line(X - hw * sc, Y + yy * sc, X + hw * sc, Y + yy * sc)
    end
    K.col(C.white, 0.9)
    G.circle("line", X, Y, r * sc)
    -- (the ring)
    G.push()
    G.translate(X, Y)
    G.rotate(-0.35)
    K.col(C.gold, 0.6)
    G.ellipse("line", 0, 0, r * 1.42 * sc, r * 0.36 * sc)
    local ra = clock * (searching and 3 or 1)
    K.col(C.goldTop)
    G.circle("fill", cos(ra) * r * 1.42 * sc, sin(ra) * r * 0.36 * sc, max(1, r * 0.08 * sc))
    G.pop()
    if searching then
      for i = 0, 4 do
        local cyc = clock * 1.6 + i * 0.37
        local k = cyc % 1
        local seed = floor(cyc) * 5 + i
        local px = cx + sin(seed * 2.17) * r * 0.65
        local py = cy + cos(seed * 1.31) * r * 0.55
        K.col(C.goldTop, 1 - k)
        G.circle("line", K.X(px), K.Y(py), (0.6 + k * 3.5) * sc)
        G.circle("fill", K.X(px), K.Y(py), 0.6 * sc)
      end
    end
  end
  -- a stranger's badge: their initial on a disc (blue or pink), a gold rim
  local function badge(cx, cy, r, initial, girl)
    K.col(C.gold)
    G.circle("fill", K.X(cx), K.Y(cy), (r + 0.6) * K.sc)
    K.col(girl and C.girl or C.boy)
    G.circle("fill", K.X(cx), K.Y(cy), r * K.sc)
    K.bold(initial, cx - r, cy - r * 0.62, r * 1.25, C.white, "center", r * 2)
  end

  local function drawParticles(clock, body)
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
          G.push()
          G.translate(K.X(px), K.Y(py))
          G.rotate(clock * 8 + p.spin * 6)
          K.col(p.c, a)
          local f = abs(cos(clock * 6 + p.spin * 4))
          G.rectangle("fill", -1.2 * K.sc, -0.6 * K.sc * f - 0.2 * K.sc, 2.4 * K.sc, 1.2 * K.sc * f + 0.4 * K.sc)
          G.pop()
        end
      end
    end
    K.scissor(nil)
  end

  -- a list's highlight gliding to row `at` (rows `rh` tall from `top`, scrolled `scroll`)
  local function highlight(x, top, w, rh, y, rad)
    local hb = K.R(x, top + (y - 1) * rh + 0.4, w, rh - 0.8)
    K.col(C.accent, 0.13)
    K.box("fill", hb, rad)
    K.ring(hb, rad, C.accent, 0.85, 0.5)
  end

  -- the picker's list: the box's name with its arrows on top (not when answering a listing)
  local function drawPicker(x, y, w, h, clock, dt)
    K.glass(K.R(x, y, w, h), 4)
    local accept = st.picking and st.picking.purpose == "accept"
    local top = y + 1
    local since = clock - mv.listAt
    if not accept then
      K.chevron(x + 5, y + 5.3, 4, C.accent, -1)
      K.addHit(K.R(x, y, 12, 10), "win", BOX_PREV)
      K.chevron(x + w - 5, y + 5.3, 4, C.accent, 1)
      K.addHit(K.R(x + w - 12, y, 12, 10), "win", BOX_NEXT)
      local name = Bx.boxName(session(), st.box) or ""
      local ns = K.fit(name, 4.6, w - 26)
      -- (the box's name sliding in from the side it turned to)
      local e = mv.listDir ~= 0 and K.outCubic(since / 0.28) or 1
      K.bold(name, x + 12 + (1 - e) * mv.listDir * 8, y + 2.7 + (4.6 - ns) * 0.5, ns, C.ink, "center", w - 24, e)
      K.hairline(x + 2, y + 10, w - 4)
      top = y + 10.5
    end
    local lh = y + h - 1 - top
    st.visible = max(1, floor(lh / ROW_H))
    if st.cursor > st.top + st.visible then st.top = st.cursor - st.visible end
    if st.cursor <= st.top then st.top = st.cursor - 1 end
    st.top = max(0, min(st.top, max(0, #st.rows - st.visible)))
    mv.top = K.approach(mv.top, st.top, dt, 18)
    local clip = K.R(x, top, w, lh)
    K.scissor(clip)
    if #st.rows > 0 then
      if mv.curPrev == nil then mv.curY = st.cursor end
      mv.curY, mv.curPrev = K.approach(mv.curY, st.cursor, dt, 22), st.cursor
      highlight(x + 1.5, top, w - 3, ROW_H, mv.curY - mv.top, 2.5)
    end
    local first = floor(mv.top) + 1
    local frame = floor(clock * 3) % 2
    for i = first, min(#st.rows, first + st.visible + 1) do
      local r = st.rows[i]
      local ry0 = top + (i - 1 - mv.top) * ROW_H
      local e = rowIn(since, i - first)
      local ry, dx = ry0 + (1 - e) * (mv.listDir == 0 and 3 or 0), (1 - e) * mv.listDir * 10
      local f0 = K.getFade()
      K.setFade(f0 * e)
      local a = r.ok and 1 or 0.45
      -- (its icon on a soft disc of its type's colour)
      K.col(TYPE[r.t1] or C.slate, 0.24 * a)
      G.circle("fill", K.X(x + 8.5 + dx), K.Y(ry + 6), 4.8 * K.sc)
      if env.monIconOf then pcall(env.monIconOf, r.mon, x + 3 + dx, ry + 0.5, 11, i == st.cursor and frame or 0, a * f0 * e) end
      local ns = K.fit(r.name, 4.6, w - 40)
      K.text(r.name, x + 15 + dx, ry + (r.why and 1.2 or 3.4), ns, r.ok and C.ink or C.faint)
      K.text(levelText(r.level), x + w - 4 - 20 + dx, ry + 3.4, 4, C.soft, "right", 20)
      if r.why then K.text(r.why, x + 15 + dx, ry + 6.6, 3.2, C.red, "left", w - 40) end
      if r.party then
        K.col(C.gold, 0.95)
        G.circle("fill", K.X(x + w - 4 - 22 - 1.5 + dx), K.Y(ry + ROW_H / 2), 1 * K.sc)
      end
      if r.shiny then sparkle(x + 13.5 + dx, ry + 2.2, 1.4, C.gold, 0.9) end
      K.setFade(f0)
      K.addHit(K.R(x + 1.5, ry0 + 0.4, w - 3, ROW_H - 0.8), "win", ROW + i, clip)
    end
    if #st.rows == 0 then K.text(T("gts.emptyBox"), x, top + lh / 2 - 3, 4.4, C.faint, "center", w) end
    K.scrollbar(x + w, top, lh, mv.top, st.visible, #st.rows)
    K.scissor(nil)
  end

  -- the chosen one on a pane of its colour: its picture popping up, its name, level and types sliding in
  local function drawChosen(r, x, y, w, h, clock)
    local b = K.R(x, y, w, h)
    hero(b, clock)
    local t = clock - mv.pickAt
    local pop = 0.82 + 0.18 * K.outBack(t / 0.38)
    local fa = K.outCubic(t / 0.16)
    local ps = min(h - 2, 30)
    local pcx, pcy = x + 2 + ps / 2, y + h / 2
    K.glow(pcx, pcy, ps * 0.6, ps * 0.55, C.white, 0.3 * fa)
    picture(r.sp, r.mon, pcx, pcy, ps, clock, mv.pickAt, pop, fa * (r.ok and 1 or 0.55), r.shiny)
    local tx = x + ps + 5
    local tw = x + w - tx - 2
    local e = K.outCubic((t - 0.05) / 0.3)
    local ox = (1 - e) * 6
    local ty = y + max(1.5, (h - (h >= 18 and 17 or 11)) / 2)
    local ns = K.fit(r.name, 4.8, tw - 4)
    K.label(r.name, tx + ox, ty, ns, C.white, nil, nil, e)
    if r.shiny then sparkle(tx + ox + K.width(r.name, ns) + 2.5, ty + 2.6, 1.8 + 0.4 * sin(clock * 5), C.goldTop, e) end
    K.label(levelText(r.level), tx + ox, ty + 6, 3.6, C.white, nil, nil, 0.9 * e)
    if h >= 18 and r.t1 and pillsW(r, 3.2) <= tw then pills(r, tx + ox, ty + 11.5, 5, 3.2, e, true) end
  end

  -- the picker's right card: what's being done, the chosen Pokémon, the button
  local function drawPickCard(x, y, w, h, clock)
    K.glass(K.R(x, y, w, h), 4)
    local purpose = st.picking and st.picking.purpose or "wonder"
    local r = st.rows[st.cursor]
    local headH
    if h < 74 then
      -- (a short card, a small window's: the title alone above the Pokémon and its button)
      local title = purpose == "wonder" and T("gts.wonder")
        or (purpose == "accept" and st.picking.listing.offerName or T("gts.depositTitle"))
      local fs = K.fit(title, 5.2, w - 8)
      K.bold(title, x, y + 3 + (5.2 - fs) * 0.5, fs, C.ink, "center", w)
      headH = 10
      if purpose == "accept" then
        K.text(T("gts.pickGive"), x + 4, y + 10, 3.6, C.teal, "center", w - 8)
        headH = 15
      end
    elseif purpose == "wonder" then
      globe(x + w / 2, y + 13 + sin(clock * 1.6) * 0.6, 9, clock, false)
      K.bold(T("gts.wonder"), x, y + 25, 5.2, C.ink, "center", w)
      K.text(T("gts.wonderBlurb"), x + 4, y + 31.5, 3.4, C.soft, "center", w - 8)
      headH = 46
    elseif purpose == "accept" then
      local L = st.picking.listing
      disc(x + w / 2, y + 11, 8, L.t1, 1)
      if env.monIcon then pcall(env.monIcon, L.sp, x + w / 2 - 8, y + 3, 16, floor(clock * 3) % 2) end
      K.bold(L.offerName, x, y + 21, 5, C.ink, "center", w)
      K.text(L.whoText, x, y + 27.5, 3.8, C.soft, "center", w)
      K.text(T("gts.pickGive"), x + 4, y + 34, 3.8, C.teal, "center", w - 8)
      headH = 41
    else
      K.bold(T("gts.depositTitle"), x, y + 4, 5, C.ink, "center", w)
      K.text(T("gts.depositBlurb"), x + 4, y + 11, 3.6, C.soft, "center", w - 8)
      headH = 30
    end
    if r then
      local mh = y + h - 15 - (y + headH)
      if mh >= 10 then drawChosen(r, x + 3, y + headH, w - 6, mh, clock) end
      local label = T(purpose == "wonder" and "gts.send" or (purpose == "accept" and "gts.trade" or "gts.next"))
      local bb = K.R(x + 4, y + h - 13, w - 8, 10)
      button(bb, label, false, r.ok and "go" or "off", clock)
      K.addHit(bb, "win", GO)
    end
  end

  -- the strangers' listings: offer → want, the stranger; the ones you can answer glowing
  local function drawListings(x, y, w, h, clock, dt)
    K.glass(K.R(x, y, w, h), 4)
    local lh = h - 2
    st.visible = max(1, floor(lh / LROW_H))
    if st.lcursor > st.ltop + st.visible then st.ltop = st.lcursor - st.visible end
    if st.lcursor <= st.ltop then st.ltop = st.lcursor - 1 end
    st.ltop = max(0, min(st.ltop, max(0, #st.listings - st.visible)))
    mv.ltop = K.approach(mv.ltop, st.ltop, dt, 18)
    local top = y + 1
    local clip = K.R(x, top, w, lh)
    K.scissor(clip)
    if #st.listings > 0 then
      if mv.lcurPrev == nil then mv.lcurY = st.lcursor end
      mv.lcurY, mv.lcurPrev = K.approach(mv.lcurY, st.lcursor, dt, 22), st.lcursor
      highlight(x + 1.5, top, w - 3, LROW_H, mv.lcurY - mv.ltop, 2.5)
    end
    local first = floor(mv.ltop) + 1
    local half = (w - 10) / 2
    local since = clock - mv.listAt
    local frame = floor(clock * 3) % 2
    for i = first, min(#st.listings, first + st.visible + 1) do
      local L = st.listings[i]
      local ry0 = top + (i - 1 - mv.ltop) * LROW_H
      local e = rowIn(since, i - first)
      local ry = ry0 + (1 - e) * 4
      local f0 = K.getFade()
      K.setFade(f0 * e)
      local rb = K.R(x + 1.5, ry + 0.4, w - 3, LROW_H - 0.8)
      if L.canDo then
        K.col(C.green, 0.1 + 0.06 * sin(clock * 3 + i))
        K.box("fill", rb, 2.5)
      end
      local a = L.done and 0.4 or 1
      local ia = a * f0 * e
      local tc = TIER_C[L.tier] or TIER_C.common
      K.col(tc, a)
      K.box("fill", K.R(rb[1] + 0.6, rb[2] + 1.6, 1.1, rb[4] - 3.2), 0.5)
      -- (what they offer, on a disc of its type)
      K.col(TYPE[L.t1] or C.slate, 0.26 * a)
      G.circle("fill", K.X(x + 9), K.Y(ry + 6.3), 5.4 * K.sc)
      if env.monIcon then pcall(env.monIcon, L.sp, x + 3.5, ry + 0.8, 11, i == st.lcursor and frame or 0, 1, 1, 1, ia) end
      local ns = K.fit(L.offerName, 4.6, half - 16)
      K.bold(L.offerName, x + 15, ry + 1.6, ns, C.ink, nil, nil, a)
      local pw = chip(T(TIER_KEY[L.tier] or TIER_KEY.common), x + 15, ry + 7.2, 3.2, tc, a)
      K.text(levelText(L.level), x + 17 + pw, ry + 7.2, 3.6, C.soft, nil, nil, a)
      if L.shiny then shinyBadge(x + 15 + pw + 3 + K.width(levelText(L.level), 3.6), ry + 7.2, 3.2, clock, a) end
      K.text(L.whoText, x + 15, ry + 11.6, 3.2, C.faint, nil, nil, a)
      -- (the swap arrows, then what they want)
      local mx = x + 5 + half
      K.chevron(mx - 0.5, ry + 5, 3.4, C.accent, 1, a)
      K.chevron(mx + 1.5, ry + 9, 3.4, C.accent, -1, a)
      local ax = mx + 5
      K.text(T("gts.wants"), ax, ry + 0.8, 3.2, C.faint, nil, nil, a)
      K.col(TYPE[L.a1] or C.slate, 0.24 * a)
      G.circle("fill", K.X(ax + 4.5), K.Y(ry + 9), 4.4 * K.sc)
      if env.monIcon then pcall(env.monIcon, L.ask, ax, ry + 4.5, 9, 0, 1, 1, 1, ia) end
      local ans = K.fit(L.askName, 4.2, x + w - ax - 14)
      K.text(L.askName, ax + 11, ry + 5, ans, C.ink, nil, nil, a)
      K.text(rangeText(L.levels), ax + 11, ry + 10.2, 3.4, C.soft, nil, nil, a)
      if L.done then
        local t = T("gts.done")
        chip(t, x + w - 4 - chipW(t, 3.2), ry + 1.4, 3.2, C.faint)
      elseif L.canDo then
        local t = T("gts.haveIt")
        chip(t, x + w - 4 - chipW(t, 3.2), ry + 1.4, 3.2, C.green, 0.7 + 0.3 * abs(sin(clock * 4)))
      end
      if i ~= st.lcursor and i + 1 ~= st.lcursor and i < #st.listings then
        K.hairline(x + 15, ry + LROW_H - 0.2, w - 17)
      end
      K.setFade(f0)
      K.addHit(K.R(x + 1.5, ry0 + 0.4, w - 3, LROW_H - 0.8), "win", ROW + i, clip)
    end
    if #st.listings == 0 then K.text(T("gts.none"), x, y + h / 2 - 3, 4.4, C.faint, "center", w) end
    K.scrollbar(x + w, top, lh, mv.ltop, st.visible, #st.listings)
    K.scissor(nil)
  end

  -- My Deposit: nothing posted (post one), waiting (yours on a pulsing ring), traded (collect)
  local function drawDeposit(x, y, w, h, clock)
    local dep = depositWords()
    if mv.depKey ~= st.depKey then mv.depKey, mv.depAt = st.depKey, clock end
    K.glass(K.R(x, y, w, h), 4)
    local t = clock - mv.depAt
    local pop = 0.82 + 0.18 * K.outBack(t / 0.42)
    local fa = K.outCubic(t / 0.2)
    local e1, e2 = K.outCubic((t - 0.08) / 0.32), K.outCubic((t - 0.16) / 0.32)
    local cx = x + w / 2
    if not dep then
      globe(cx, y + h * 0.34 + sin(clock * 1.6) * 0.8, min(16, h * 0.2) * pop, clock, false)
      K.rise(e1, 4)
      K.bold(T("gts.depositTitle"), x, y + h * 0.62, 5.4, C.ink, "center", w)
      K.text(T("gts.depositBlurb"), x + 8, y + h * 0.62 + 7, 3.8, C.soft, "center", w - 16)
      K.settle(e1)
      local go = K.R(cx - 30, y + h - 14, 60, 10)
      button(go, T("gts.depositBtn"), false, "go", clock)
      K.addHit(go, "win", GO)
      return
    end
    local d = st.dep
    local py = y + h * 0.34
    local r = min(17, h * 0.22)
    if dep.received then
      rays(cx, py, r * 2.2, clock, C.gold, 0.18 * fa)
      K.col(C.gold, (0.5 + 0.3 * sin(clock * 5)) * fa)
      G.setLineWidth(max(1, 0.4 * K.sc))
      G.circle("line", K.X(cx), K.Y(py), r * 1.08 * K.sc)
    else
      -- (waiting: rings going out from it)
      G.setLineWidth(max(1, 0.35 * K.sc))
      for k = 0, 2 do
        local f = (clock * 0.5 + k / 3) % 1
        K.col(TYPE[d.t1] or C.teal, 0.55 * (1 - f) * fa)
        G.circle("line", K.X(cx), K.Y(py), r * (0.95 + f * 0.8) * K.sc)
      end
    end
    disc(cx, py, r * 0.95, d.t1, fa)
    local posted = Gx.posted()
    picture(d.sp, posted and posted.mon, cx, py + sin(clock * 2) * 0.4, r * 1.6, clock, mv.depAt, pop, fa, d.shiny)
    local ty = py + r + 3
    K.rise(e1, 4)
    if dep.received then
      K.bold(d.traded, x, ty, 5, C.goldDark, "center", w)
      K.text(d.from, x, ty + 7, 3.8, C.soft, "center", w)
      sparkle(cx - r - 3, py - r * 0.5, 1.4 + 0.8 * abs(sin(clock * 3)), C.gold, 0.9)
      sparkle(cx + r + 3, py + r * 0.4, 1.2 + 0.8 * abs(sin(clock * 4)), C.goldTop, 0.9)
    else
      local nw = K.width(d.name, 5)
      local pw = pillsW(d, 3.2)
      if pw > 0 and nw + pw + 2 > w - 8 then pw = 0 end
      local nx = cx - (nw + (pw > 0 and pw + 2 or 0)) / 2
      K.bold(d.name, nx, ty, 5, C.ink)
      if pw > 0 then pills(d, nx + nw + 2, ty + 0.4, 5, 3.2) end
      K.text(d.seek, x, ty + 6.5, 3.8, C.teal, "center", w)
    end
    K.settle(e1)
    if not dep.received then
      K.rise(e2, 4)
      local mins = floor(max(0, Gx.now() - (dep.at or 0)) / 60)
      local dots = floor(clock * 2) % 4
      local wt = T("gts.waiting")
      K.text(wt, x, ty + 12, 3.6, C.soft, "center", w)
      K.col(C.soft)
      for k = 1, dots do
        G.circle("fill", K.X(cx + K.width(wt, 3.6) / 2 + k * 1.6), K.Y(ty + 15.6), 0.4 * K.sc)
      end
      K.text(agoText(mins), x, ty + 17, 3.4, C.faint, "center", w)
      K.settle(e2)
    end
    local go = K.R(cx - 30, y + h - 14, 60, 10)
    if dep.received then button(go, T("gts.collect"), false, "ok", clock)
    else button(go, T("gts.withdraw"), false, "gray", clock) end
    K.addHit(go, "win", GO)
  end

  -- the search: the window fading to the globe's lights, the globe spinning, pings; then found: the
  -- stranger's badge popping up
  local function drawSearch(x, y, w, h, clock)
    local sh = st.search
    local t = now()
    local e = K.outCubic((t - sh.t0) / 0.3)
    local f0 = K.getFade()
    K.setFade(f0 * e)
    K.backdrop(bodyNow, clock, mv.r, mv.g, mv.b, mv.r2, mv.g2, mv.b2)
    K.scissor(bodyNow)
    local cx, cy = x + w / 2, y + h * 0.42
    local r = min(w, h) * 0.22
    local lb = K.R(x + w / 2 - min(w - 12, 110) / 2, cy + r + 4, min(w - 12, 110), 10)
    if not sh.found then
      globe(cx, cy, r * (0.85 + 0.15 * K.outBack((t - sh.t0) / 0.5)), clock, true)
      K.glass(lb, 5, 0.55)
      local label = T("gts.searching")
      local fs = K.fit(label, 5, lb[3] - 14)
      local lw = K.width(label, fs)
      K.bold(label, lb[1], lb[2] + (10 - fs * 1.2) / 2, fs, C.ink, "center", lb[3])
      local dots = floor(clock * 3) % 4
      K.col(C.ink)
      for k = 1, dots do
        G.circle("fill", K.X(cx + lw / 2 + 0.5 + k * 1.6), K.Y(lb[2] + 5 + fs * 0.4), 0.45 * K.sc)
      end
    else
      local k = (t - sh.t0 - sh.dur) / 0.45
      globe(cx, cy, r * (1 - 0.2 * K.outCubic(k)), clock, false)
      scaleAbout(cx, cy - r * 0.15, K.outBack(k))
      badge(cx, cy - r * 0.15, r * 0.45, sh.initial, sh.girl)
      G.pop()
      local ek = K.outCubic(k)
      K.rise(ek, 4)
      K.glass(lb, 5, 0.6)
      local fs = K.fit(sh.text, 4.6, lb[3] - 6)
      K.bold(sh.text, lb[1], lb[2] + (10 - fs * 1.2) / 2, fs, C.goldDark, "center", lb[3])
      K.settle(ek)
    end
    K.setFade(f0)
  end

  -- the reveal: the newcomer springing up on a disc of its type (rays in its tier's colour for the rare),
  -- the backdrop turning to its colours; its card settling in under it: name, types, tier, level, OT and
  -- home, what it holds, its IVs
  local function drawReveal(x, y, w, h, clock)
    local rv = st.reveal
    local t = now()
    local age = t - rv.t0
    K.backdrop(bodyNow, clock, mv.r, mv.g, mv.b, mv.r2, mv.g2, mv.b2)
    K.scissor(bodyNow)
    local tc = TIER_C[rv.tier] or TIER_C.common
    local cx, cy = x + w / 2, y + h * 0.32
    local r = min(w, h) * 0.2
    burstAt.x, burstAt.y = cx, cy
    local fa = K.outCubic(age / 0.25)
    if (RANK[rv.tier] or 1) >= 3 then rays(cx, cy, r * 2.6 * (0.6 + 0.4 * fa), clock, tc, 0.22 * fa) end
    disc(cx, cy, r * 1.02 * (0.7 + 0.3 * K.outBack(age / 0.4)), rv.t1, fa)
    K.glow(cx, cy, r * 1.3, r * 1.2, C.white, 0.35 * fa)
    -- (the Pokémon itself: shiny when it really is; springing up past its size and settling, then breathing)
    local pop = age < 0.6 and (0.3 + 0.7 * K.outBack(age / 0.5)) or 1
    picture(rv.sp, rv.mon, cx, cy, r * 2, clock, rv.t0, pop, fa, rv.shiny)
    sparkle(cx - r * 1.1, cy - r * 0.6, (1.5 + abs(sin(clock * 3))) * fa, C.white, 0.9)
    sparkle(cx + r * 1.15, cy + r * 0.5, (1.3 + abs(sin(clock * 4 + 1))) * fa, tc, 0.9)
    -- (its card)
    local cw = min(w - 12, 150)
    local ty = cy + r + 3
    local ch = min(y + h - 3 - ty, 22 + (rv.item and 5 or 0) + (rv.evolve and 5 or 0) + 6)
    local e = K.outCubic((age - 0.18) / 0.4)
    K.rise(e, 6)
    K.glass(K.R(cx - cw / 2, ty, cw, ch), 5, 0.6)
    local yy = ty + 2.5
    local ns = K.fit(rv.name, 6, cw - 8)
    K.bold(rv.name, cx - cw / 2, yy, ns, C.ink, "center", cw)
    yy = yy + 7.6
    -- (its types, its tier, its level, Shiny: one line, centred; the types left out when it's too narrow)
    local tier = T(TIER_KEY[rv.tier] or TIER_KEY.common)
    local lv = levelText(rv.level)
    local tw = chipW(tier, 3.6)
    local lw = K.width(lv, 4)
    local shw = rv.shiny and (shinyW(3.6) + 2) or 0
    local pw = pillsW(rv, 3.4)
    local total = tw + 2 + lw + shw
    if pw > 0 and total + pw + 2 <= cw - 6 then total = total + pw + 2 else pw = 0 end
    local sx = cx - total / 2
    if pw > 0 then sx = sx + pills(rv, sx, yy - 0.2, 5.2, 3.4) + 2 end
    chip(tier, sx, yy, 3.6, tc)
    K.text(lv, sx + tw + 2, yy, 4, C.soft)
    if rv.shiny then shinyBadge(sx + tw + 4 + lw, yy, 3.6, clock) end
    yy = yy + 6.4
    K.text(rv.ot, cx - cw / 2, yy, 3.8, C.teal, "center", cw)
    yy = yy + 5.4
    if rv.item then
      K.text(rv.item, cx - cw / 2, yy, 3.6, C.goldDark, "center", cw)
      yy = yy + 5
    end
    K.text(ivTotal(rv.ivs), cx - cw / 2, yy, 3.6, C.soft, "center", cw)
    if rv.evolve then
      K.bold(T("gts.evolving"), cx - cw / 2, yy + 5, 3.8, C.goldDark, "center", cw, 0.6 + 0.4 * abs(sin(clock * 4)))
    end
    K.settle(e)
  end

  -- a sheet over the window: the species list (with its letters) or the level ranges
  local function drawSheetCard(x, y, w, h, clock, dt)
    local sw, sh = min(w - 16, 130), min(h - 12, 92)
    local sx, sy = x + (w - sw) / 2, y + (h - sh) / 2
    K.sheet(K.R(sx, sy, sw, sh), 6)
    if st.sheet == "species" then
      K.bold(T("gts.pickSpecies"), sx, sy + 3, 4.8, C.ink, "center", sw)
      local top = sy + 10
      local vis = floor((sh - 12) / ROW_H)
      if st.scursor > st.stop + vis then st.stop = st.scursor - vis end
      if st.scursor <= st.stop then st.stop = st.scursor - 1 end
      st.stop = max(0, min(st.stop, max(0, #st.species - vis)))
      mv.stop = K.approach(mv.stop, st.stop, dt, 18)
      K.hairline(sx, top - 0.6, sw)
      local clip = K.R(sx, top, sw, sh - 12)
      K.scissor(clip)
      if #st.species > 0 then
        if mv.scurPrev == nil then mv.scurY = st.scursor end
        mv.scurY, mv.scurPrev = K.approach(mv.scurY, st.scursor, dt, 22), st.scursor
        highlight(sx + 2, top, sw - 4, ROW_H, mv.scurY - mv.stop, 2.5)
      end
      local first = floor(mv.stop) + 1
      for i = first, min(#st.species, first + vis + 1) do
        local sp = st.species[i]
        local ry = top + (i - 1 - mv.stop) * ROW_H
        local rb = K.R(sx + 2, ry + 0.4, sw - 4, ROW_H - 0.8)
        if env.monIcon then pcall(env.monIcon, sp, sx + 4, ry + 0.5, 11, 0, 1, 1, 1, K.getFade()) end
        K.text(Gx.name(sp), sx + 17, ry + 3.2, 4.6, i == st.scursor and C.accent or C.ink)
        K.addHit(rb, "win", SHEET_ROW + i, clip)
      end
      if #st.species == 0 then K.text(T("gts.noneSeen"), sx, top + 20, 4, C.faint, "center", sw) end
      K.scrollbar(sx + sw, top, sh - 12, mv.stop, vis, #st.species)
      K.scissor(bodyNow)
    else
      K.bold(T("gts.pickLevels"), sx, sy + 3, 4.8, C.ink, "center", sw)
      local a1 = Gx.types and (Gx.types(st.request.species)) or nil
      disc(sx + sw / 2, sy + 18, 8, a1, 1)
      if env.monIcon then pcall(env.monIcon, st.request.species, sx + sw / 2 - 8, sy + 10, 16, floor(clock * 3) % 2, 1, 1, 1, K.getFade()) end
      K.text(Gx.name(st.request.species), sx, sy + 28, 4.4, C.teal, "center", sw)
      -- (the ranges as chips, two rows)
      local n = #Gx.LEVELS
      local per = 6
      local cw = (sw - 8) / per
      for i = 1, n do
        local col, row = (i - 1) % per, floor((i - 1) / per)
        local cb = K.R(sx + 4 + col * cw + 0.5, sy + 36 + row * 10, cw - 1, 8.4)
        local on = i == st.levels
        K.col(on and C.accent or C.fill)
        K.box("fill", cb, 2.5)
        local label = rangeText(i)
        local fs = K.fit(label, 3.4, cb[3] - 1.5)
        K.text(label, cb[1], cb[2] + 2.3, fs, on and C.white or C.ink, "center", cb[3])
        K.addHit(cb, "win", LEVEL + i)
      end
      local go = K.R(sx + 6, sy + sh - 13, sw - 12, 10)
      button(go, T("gts.next"), false, "go", clock)
      K.addHit(go, "win", GO)
    end
  end
  local function drawConfirmCard(x, y, w, h, clock)
    local c = st.confirm
    local sw, sh = min(w - 20, 120), 34
    local sx, sy = x + (w - sw) / 2, y + (h - sh) / 2
    K.sheet(K.R(sx, sy, sw, sh), 6)
    K.text(c.text, sx + 4, sy + 4, 4.4, C.ink, "center", sw - 8)
    local bw = (sw - 12) / 2
    local yb, nb = K.R(sx + 4, sy + sh - 13, bw, 10), K.R(sx + 8 + bw, sy + sh - 13, bw, 10)
    button(nb, T("button.cancel"), not st.yes, "gray", clock)
    button(yb, T(c.kind == "withdraw" and "gts.withdraw" or "button.ok"), st.yes, "go", clock)
    K.addHit(yb, "win", YES)
    K.addHit(nb, "win", NO)
  end
  -- (the dim, then the card popping up over it)
  local function drawSheets(x, y, w, h, clock, dt)
    if not (st.sheet or st.confirm) then return end
    local e = K.outCubic((clock - mv.sheetAt) / 0.22)
    K.dim(bodyNow, 0.24 * e)
    local f0 = K.getFade()
    K.rise(e, 6)
    if st.sheet then drawSheetCard(x, y, w, h, clock, dt) end
    if st.confirm then
      if st.sheet then K.dim(bodyNow, 0.12) end
      drawConfirmCard(x, y, w, h, clock)
    end
    K.settle(e)
    K.setFade(f0)
  end

  -- the head: the globe, the three tabs (a count on My Deposit when a trade waits)
  local function drawHead(x, y, w, clock, dt)
    globe(x + 4, y + 5, 3.4, clock, false)
    local sx, sw = x + 11, min(150, w - 13)
    local idx = st.tab == "wonder" and 1 or (st.tab == "browse" and 2 or 3)
    mv.tabX = K.approach(mv.tabX, idx, dt, 18)
    K.glassSwitch(sx, y + 1, sw, 8, mv.tabX, "win", TAB + 1, T(TAB_KEY[1]), TAB + 2, T(TAB_KEY[2]),
      TAB + 3, T(TAB_KEY[3]), 4.2)
    if Gx.waiting() > 0 then
      local k = 1 + 0.15 * abs(sin(clock * 3))
      K.col(C.red)
      G.circle("fill", K.X(sx + sw - 1.5), K.Y(y + 1.5), 2.4 * k * K.sc)
      K.text("1", sx + sw - 4.5, y - 0.1, 3.2, C.white, "center", 6)
    end
  end

  -- what changed since the last frame starts its motion; the lights turn to what's shown
  local function notice(clock, dt)
    if st.tab ~= mv.tab then
      mv.listAt, mv.listDir = clock, 0
      mv.tab, mv.curPrev, mv.lcurPrev = st.tab, nil, nil
    end
    if st.box ~= mv.box then
      if mv.box ~= nil then
        local d = st.box - mv.box
        if abs(d) > (Bx.BOXES or 14) / 2 then d = -d end
        mv.listAt, mv.listDir = clock, d > 0 and 1 or -1
      end
      mv.box = st.box
    end
    if (st.picking or false) ~= mv.picking then
      mv.picking, mv.listAt, mv.listDir, mv.curPrev = st.picking or false, clock, 0, nil
    end
    if st.listingsAt ~= mv.listings then
      if mv.listings ~= nil and st.tab == "browse" then mv.listAt, mv.listDir = clock, 0 end
      mv.listings = st.listingsAt
    end
    local sk = st.confirm and "confirm" or st.sheet
    if sk ~= mv.sheetKey then
      if sk then mv.sheetAt = clock end
      mv.sheetKey, mv.scurPrev = sk, nil
    end
    -- (the picker's chosen one: its picture pops up, animated as the Pokédex's)
    local rv, r = st.reveal, nil
    if not (rv or st.search) then
      r = (st.tab == "wonder" or st.picking) and st.rows[st.cursor] or nil
      local m = r and r.mon or nil
      if m ~= mv.pickMon then
        mv.pickMon, mv.pickAt = m, clock
        if m and env.dexSprite then pcall(env.dexSprite.start, r.sp, r.shiny) end
      end
    end
    -- (the lights: the newcomer's, the search's (the globe's), the chosen one's, a listing's, the deposit's)
    local t1, t2
    if rv then t1, t2 = rv.t1, rv.t2
    elseif not st.search then
      if st.tab == "wonder" or st.picking then
        if r then t1, t2 = r.t1, r.t2
        elseif st.picking and st.picking.listing then t1, t2 = st.picking.listing.t1, st.picking.listing.t2 end
      elseif st.tab == "browse" then
        local L = st.listings[st.lcursor]
        if L then t1, t2 = L.t1, L.t2 end
      elseif st.depKey ~= nil and st.depKey ~= "none" then
        t1, t2 = st.dep.t1, st.dep.t2
      end
    end
    local c1 = t1 and TYPE[t1] or nil
    local c2
    if c1 then c2 = t2 and TYPE[t2] or c1 else c1, c2 = C.globeA, C.globeB end
    local rate = mv.coloured and 6 or 1000
    mv.coloured = true
    mv.r = K.approach(mv.r, c1[1] / 255, dt, rate)
    mv.g = K.approach(mv.g, c1[2] / 255, dt, rate)
    mv.b = K.approach(mv.b, c1[3] / 255, dt, rate)
    local k2 = c2 == c1 and 0.35 or 0
    mv.r2 = K.approach(mv.r2, (c2[1] + (255 - c2[1]) * k2) / 255, dt, rate)
    mv.g2 = K.approach(mv.g2, (c2[2] + (255 - c2[2]) * k2) / 255, dt, rate)
    mv.b2 = K.approach(mv.b2, (c2[3] + (255 - c2[3]) * k2) / 255, dt, rate)
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    G = K.graphics()
    bodyNow = body
    local dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT = clock
    advance(now())
    notice(clock, dt)
    K.backdrop(body, clock, mv.r, mv.g, mv.b, mv.r2, mv.g2, mv.b2)
    K.scissor(body)
    -- (under the search once it's faded in, and under the reveal, nothing else is drawn)
    local covered = st.reveal or (st.search and now() - st.search.t0 >= 0.3)
    if not covered then
      drawHead(x + M, y + 1, w - M * 2, clock, dt)
      local top = y + HEAD_H + 1.5
      local bodyH = y + h - M - top
      if st.tab == "wonder" or st.picking then
        if portrait then
          local ch = min(92, bodyH * 0.5)
          drawPicker(x + M, top, w - M * 2, bodyH - ch - M, clock, dt)
          K.scissor(body)
          drawPickCard(x + M, top + bodyH - ch, w - M * 2, ch, clock)
        else
          local lw = floor((w - M * 3) * 0.52)
          drawPicker(x + M, top, lw, bodyH, clock, dt)
          K.scissor(body)
          drawPickCard(x + M * 2 + lw, top, w - M * 3 - lw, bodyH, clock)
        end
      elseif st.tab == "browse" then
        drawListings(x + M, top, w - M * 2, bodyH, clock, dt)
      else
        drawDeposit(x + M, top, w - M * 2, bodyH, clock)
      end
      K.scissor(body)
      drawSheets(x, y, w, h, clock, dt)
    end
    K.scissor(body)
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
