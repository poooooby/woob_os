-- R-Bay: Team Rocket's auction house for Pokémon (the model is src/auction.lua, env.auction). Browse
-- the twelve running auctions (a list on the left, a strip on top in portrait; the chosen one on the
-- right: its picture, tier, level, IVs, the price, the time left, the last bids, your maximum), or
-- My Bids (the auctions you're in, then how the ended ones went).
--   buttons  Up / Down the auction, A bid (then < > one step, ^ v ten, SELECT all you can, A place
--            it, B back), L / R or START Browse | My Bids, B close
--   touch    tap an auction, its - / + and Place Bid; the Browse | My Bids switch; drag (or the
--            wheel) scrolls the list
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min = math.floor, math.max, math.min

local ROW_H, HEAD_H, M = 13, 10, 3
-- hit args: Browse rows 1.., My Bids rows MINE + i, the rest below
local MINE = 3000
local SEG_BROWSE, SEG_MINE = 2001, 2002
local STEP_MINUS, STEP_PLUS, STEP_GO = 2010, 2011, 2012

-- the Rocket look: a dark body, red accents; a colour per tier
local C = {
  bg = { 22, 22, 26 }, card = { 36, 36, 42 }, cardHi = { 62, 62, 72 }, line = { 255, 255, 255, 0.07 },
  text = { 238, 238, 242 }, soft = { 152, 152, 162 }, faint = { 104, 104, 114 },
  red = { 226, 36, 48 }, redSoft = { 226, 36, 48, 0.2 }, green = { 64, 204, 112 }, gold = { 244, 192, 40 },
  bar = { 255, 255, 255, 0.1 }, ivBar = { 226, 36, 48 }, white = { 255, 255, 255 },
}
local TIER_C = {
  common = { 128, 128, 140 }, uncommon = { 52, 178, 92 }, rare = { 44, 124, 232 }, prized = { 152, 84, 224 },
  legendary = { 232, 170, 28 }, mythical = { 232, 82, 164 },
}

-- (the words are keys of lang/*.lua, through env.T)
local HINTS = {
  list = { { "A", "hint.bid" }, { "L R", "hint.tab" }, { "B", "hint.close" } },
  step = { { "< >", "hint.step" }, { "^ v", "hint.ten" }, { "A", "hint.bid" }, { "B", "hint.back" } },
  mine = { { "A", "hint.open" }, { "L R", "hint.tab" }, { "B", "hint.close" } },
}
local TIER_KEY = {
  common = "auction.tier.common", uncommon = "auction.tier.uncommon", rare = "auction.tier.rare",
  prized = "auction.tier.prized", legendary = "auction.tier.legendary", mythical = "auction.tier.mythical",
}
local IV_LABEL = { "auction.ivHp", "auction.ivAtk", "auction.ivDef", "auction.ivSpa", "auction.ivSpd", "auction.ivSpe" }
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env)
  local K, Au, T = env.K, env.auction, env.T or NO_T
  local W = { title = "R-Bay" }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end
  local function clockNow() return Au.now() end

  local st = {
    tab = "browse", focus = "list", cursor = 1, top = 0, visible = 6, key = nil, amount = 0,
    mineCursor = 1, mineTop = 0, rows = {}, mineRows = {}, mineN = 0, mineBids = 0, mineAt = -1, toast = nil,
  }
  W.state = st

  local levelText = K.textCache(function(n) return T.f("boxes.level", n) end)
  local bidsText = K.textCache(function(n) return n == 1 and T("auction.bid1") or T.f("auction.bids", n) end)
  local ivTotal = K.textCache(function(n) return T.f("auction.ivTotal", n) end)
  local numText = K.textCache(function(n) return tostring(n) end)
  -- time left: by the minute over a minute, by the second under it
  local leftText = K.textCache(function(k)
    if k <= 0 then return T("auction.ended") end
    if k < 60 then return T.f("auction.s", k) end
    local mins = floor(k / 60)
    if mins >= 60 then return T.f("auction.hm", floor(mins / 60), mins % 60) end
    return T.f("auction.m", mins)
  end)
  local function leftKey(secs)
    if secs <= 0 then return 0 end
    if secs < 60 then return secs end
    return floor(secs / 60) * 60
  end

  -- ------- the model, read

  local function listings() return Au.listings(session(), clockNow()) end
  local function current()
    local rows = listings()
    st.rows = rows
    -- (the chosen auction kept by its key while the list turns over)
    if st.key then
      for i, L in ipairs(rows) do
        if L.key == st.key then st.cursor = i break end
      end
    end
    st.cursor = max(1, min(st.cursor, #rows))
    local L = rows[st.cursor]
    st.key = L and L.key
    return L
  end
  local function clampList()
    local n = st.tab == "browse" and #st.rows or st.mineN
    local c, top = st.tab == "browse" and st.cursor or st.mineCursor, st.tab == "browse" and st.top or st.mineTop
    c = max(1, min(c, n))
    local vis = st.visible
    if c > top + vis then top = c - vis end
    if c <= top then top = c - 1 end
    top = max(0, min(top, max(0, n - vis)))
    if st.tab == "browse" then st.cursor, st.top = c, top else st.mineCursor, st.mineTop = c, top end
  end
  -- My Bids: the running bids, then the results (rows made once a second, not per frame)
  local function rebuildMine(force)
    local t = clockNow()
    if not force and t == st.mineAt then return end
    st.mineAt = t
    local rows = st.mineRows
    local bids = Au.mine(session(), t)
    local n = 0
    for _, b in ipairs(bids) do
      n = n + 1
      rows[n] = b
    end
    st.mineBids = n
    for _, r in ipairs(Au.results()) do
      n = n + 1
      rows[n] = r
    end
    for i = n + 1, #rows do rows[i] = nil end
    st.mineN = n
  end
  local function listingOf(key)
    for _, L in ipairs(st.rows) do if L.key == key then return L end end
    return nil
  end

  local function toast(text, bad, sound)
    st.toast = { text = text, bad = bad, t = now() }
    se(sound or (bad and "SE_FAILURE" or "SE_SELECT"))
  end

  -- ------- bidding

  local function affordable(L)
    local s = session()
    local have = max(0, floor(tonumber(s and s.money) or 0))
    return have + (L.mine and L.mine.max or 0)
  end
  local function setTab(tab)
    if st.tab == tab then return end
    st.tab, st.focus = tab, "list"
    if tab == "mine" then
      rebuildMine(true)
      Au.seen()
    end
    se("SE_SELECT")
  end
  local function begin()
    local L = current()
    if not L then return end
    if clockNow() >= L.finish - 30 then return toast(T("reason.auction.ended"), true) end
    local least = Au.minBid(L)
    if least > affordable(L) then return toast(T("reason.auction.money"), true) end
    st.focus, st.amount = "step", least
    se("SE_SELECT")
  end
  local function stepBy(n)
    local L = current()
    if not L then return end
    local a = st.amount
    for _ = 1, math.abs(n) do
      if n > 0 then a = a + Au.step(a) else a = a - Au.step(max(0, a - 1)) end
    end
    a = max(Au.minBid(L), min(max(Au.minBid(L), affordable(L)), a))
    if a ~= st.amount then
      st.amount = a
      se("SE_SELECT")
    end
  end
  local function place()
    local L = current()
    if not L then return end
    local ok, why = Au.bid(session(), L, st.amount, clockNow())
    if not ok then return toast(T(why and ("reason.auction." .. why) or "failed"), true) end
    st.focus = "list"
    if L.leader == 0 then
      toast(T("auction.leading"), false, "SE_SHOP")
    else
      toast(T("auction.outbidNow"), true)
    end
  end

  -- ------- buttons

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  function W.input(input, nav)
    cur = input
    if st.focus == "step" then
      if nav.right then stepBy(1)
      elseif nav.left then stepBy(-1)
      elseif nav.up then stepBy(10)
      elseif nav.down then stepBy(-10)
      elseif pressed("select") then
        local L = current()
        if L then st.amount = max(Au.minBid(L), affordable(L)) end
        se("SE_SELECT")
      elseif pressed("a") then place()
      elseif pressed("b") then
        st.focus = "list"
        se("SE_SELECT")
      end
      return true
    end
    if pressed("b") then return false end
    if pressed("l") or pressed("r") or pressed("start") then
      setTab(st.tab == "browse" and "mine" or "browse")
      return true
    end
    if st.tab == "browse" then
      local d = nav.up and -1 or (nav.down and 1 or 0)
      if d ~= 0 and #st.rows > 0 then
        local c = max(1, min(#st.rows, st.cursor + d))
        if c ~= st.cursor then
          st.cursor = c
          st.key = st.rows[c].key
          clampList()
          se("SE_SELECT")
        end
      elseif pressed("a") then begin()
      end
    else
      local d = nav.up and -1 or (nav.down and 1 or 0)
      if d ~= 0 and st.mineN > 0 then
        local c = max(1, min(st.mineN, st.mineCursor + d))
        if c ~= st.mineCursor then
          st.mineCursor = c
          clampList()
          se("SE_SELECT")
        end
      elseif pressed("a") then
        -- (a running bid: to it in Browse, to raise it)
        local r = st.mineRows[st.mineCursor]
        if r and st.mineCursor <= st.mineBids and listingOf(r.key) then
          st.key, st.tab = r.key, "browse"
          current()
          clampList()
          se("SE_SELECT")
        end
      end
    end
    return true
  end

  function W.tap(arg)
    if type(arg) ~= "number" then return end
    if arg == SEG_BROWSE then return setTab("browse") end
    if arg == SEG_MINE then return setTab("mine") end
    if arg == STEP_MINUS or arg == STEP_PLUS then
      if st.focus ~= "step" then begin() end
      if st.focus == "step" then stepBy(arg == STEP_PLUS and 1 or -1) end
      return
    end
    if arg == STEP_GO then
      if st.focus ~= "step" then return begin() end
      return place()
    end
    if arg > MINE then
      local i = arg - MINE
      if st.mineRows[i] then
        if st.mineCursor == i and i <= st.mineBids and listingOf(st.mineRows[i].key) then
          st.key, st.tab = st.mineRows[i].key, "browse"
          current()
          clampList()
        else
          st.mineCursor = i
        end
        se("SE_SELECT")
      end
      return
    end
    if st.rows[arg] then
      st.focus = "list"
      if st.cursor == arg then return begin() end
      st.cursor, st.key = arg, st.rows[arg].key
      clampList()
      se("SE_SELECT")
    end
  end

  function W.scroll(dy)
    if st.tab == "browse" then
      st.top = max(0, min(max(0, #st.rows - st.visible), st.top - dy / ROW_H))
    else
      st.mineTop = max(0, min(max(0, st.mineN - st.visible), st.mineTop - dy / ROW_H))
    end
  end

  function W.hints()
    if st.focus == "step" then return T.list(HINTS.step) end
    return T.list(st.tab == "browse" and HINTS.list or HINTS.mine)
  end

  -- ------- drawing (no tables made here)

  local function money(n, x, y, size, c, right)
    if not env.amount then return 0 end
    local ok, w = pcall(env.amount, n, 0, 0, size, c, true)
    w = ok and tonumber(w) or 0
    pcall(env.amount, n, right and x - w or x, y, size, c)
    return w
  end
  local function pill(text, x, y, size, c)
    local w = K.width(text, size) + 3
    K.col(c)
    K.box("fill", K.R(x, y, w, size * 1.35), size * 0.6)
    K.text(text, x, y + size * 0.12, size, C.white, "center", w)
    return w
  end
  local function monIcon(sp, x, y, s)
    if env.monIcon then pcall(env.monIcon, sp, x, y, s) end
  end

  -- one auction's row: the icon, the name and its price; its tier, level, your standing, time left
  local function drawRow(L, i, x, ry, w, on, focused, t, clip)
    local rb = K.R(x + 1.5, ry + 0.4, w - 3, ROW_H - 0.8)
    if on then
      K.col(focused and C.redSoft or C.cardHi)
      K.box("fill", rb, 2.5)
    end
    monIcon(L.sp, x + 2.5, ry + 1.5, 10)
    local pw = money(L.price, x + w - 4, ry + 1.8, 4.6, C.text, true)
    local ns = K.fit(L.name, 4.6, w - 22 - pw)
    K.bold(L.name, x + 14, ry + 1.8 + (4.6 - ns) * 0.5, ns, C.text)
    local px = x + 14
    px = px + pill(T(TIER_KEY[L.tier]), px, ry + 7.3, 3.4, TIER_C[L.tier]) + 2
    K.text(levelText(L.level), px, ry + 7.4, 3.8, C.soft)
    px = px + K.width(levelText(L.level), 3.8) + 2
    if L.mine then
      local lead = L.leader == 0
      pill(T(lead and "auction.winning" or "auction.outbid"), px, ry + 7.3, 3.4, lead and C.green or C.red)
    end
    local left = L.finish - t
    K.text(leftText(leftKey(left)), x + w - 4 - 30, ry + 7.4, 3.8, left < 600 and C.red or C.soft, "right", 30)
    if not on then
      K.col(C.line)
      K.box("fill", K.R(x + 14, ry + ROW_H - 0.2, w - 16, 0.25))
    end
    K.addHit(rb, "win", i, clip)
  end

  local function drawBrowseList(x, y, w, h, focused, t)
    K.col(C.card)
    K.box("fill", K.R(x, y, w, h), 4)
    st.visible = max(1, floor((h - 2) / ROW_H))
    clampList()
    local clip = K.R(x, y + 1, w, h - 2)
    K.scissor(clip)
    local first = floor(st.top) + 1
    local last = min(#st.rows, first + st.visible + 1)
    for i = first, last do
      drawRow(st.rows[i], i, x, y + 1 + (i - 1 - st.top) * ROW_H, w, i == st.cursor, focused, t, clip)
    end
    K.scrollbar(x + w, y + 1, h - 2, st.top, st.visible, #st.rows)
    K.scissor(nil)
  end

  -- the IVs: two columns of three (the stat, its value, a bar; gold at 31), the total over them
  local function drawIvs(L, x, y, w)
    K.text(ivTotal(L.ivSum), x, y, 3.8, C.soft)
    local cw = (w - 3) / 2
    for i, key in ipairs(Au.IV_KEYS) do
      local col, row = (i - 1) % 2, floor((i - 1) / 2)
      local cx, cy = x + col * (cw + 3), y + 5 + row * 5
      local v = L.ivs[key] or 0
      local top = v == 31
      K.text(T(IV_LABEL[i]), cx, cy, 3.6, C.soft)
      K.text(numText(v), cx + 9, cy, 3.6, top and C.gold or C.text, "right", 6)
      local bx, bw = cx + 16.5, cw - 17
      K.col(C.bar)
      K.box("fill", K.R(bx, cy + 1.1, bw, 2.2), 1.1)
      K.col(top and C.gold or C.ivBar)
      K.box("fill", K.R(bx, cy + 1.1, max(1.2, bw * v / 31), 2.2), 1.1)
    end
  end

  -- the chosen auction: who, what it's worth so far, the last bids, your maximum
  local function drawDetail(L, x, y, w, h, t, compact)
    K.col(C.card)
    K.box("fill", K.R(x, y, w, h), 4)
    if not L then return end
    local ps = compact and 18 or 26
    K.col(C.bg)
    K.box("fill", K.R(x + 3, y + 3, ps, ps), 3)
    local drawn = env.monPic and env.monPic(L.sp, x + 3, y + 3, ps)
    if not drawn then monIcon(L.sp, x + 3 + ps * 0.1, y + 3 + ps * 0.1, ps * 0.8) end
    local tx = x + ps + 6
    local ns = K.fit(L.name, 5.4, w - (tx - x) - 3)
    K.bold(L.name, tx, y + 3.5 + (5.4 - ns) * 0.5, ns, C.text)
    local pw = pill(T(TIER_KEY[L.tier]), tx, y + 10.3, 3.6, TIER_C[L.tier])
    K.text(levelText(L.level), tx + pw + 2, y + 10.4, 4, C.soft)
    if not compact and L.types ~= "" then K.text(L.types, tx, y + 16, 3.8, C.faint, "left", w - (tx - x) - 3) end
    local yy = y + ps + 6
    if not compact then
      drawIvs(L, x + 4, yy, w - 8)
      yy = yy + 21
    end
    -- the price, the bids, the time left; your standing
    K.text(T(L.nbids > 0 and "auction.current" or "auction.starting"), x + 4, yy, 3.8, C.soft)
    local left = L.finish - t
    K.text(leftText(leftKey(left)), x + w - 4 - 34, yy, 3.8, left < 600 and C.red or C.soft, "right", 34)
    local mw = money(L.price, x + 4, yy + 4.4, 6, C.text)
    local bt = bidsText(L.nbids)
    K.text(bt, x + 6 + mw, yy + 5.6, 3.8, C.soft)
    -- (your standing beside it: winning or outbid)
    if L.mine then
      local lead = L.leader == 0
      pill(T(lead and "auction.winning" or "auction.outbid"), x + 8 + mw + K.width(bt, 3.8), yy + 5.3, 3.4,
        lead and C.green or C.red)
    end
    yy = yy + 12
    -- the last bids, newest first (while there's room above the bid controls)
    local room = floor((y + h - 27 - yy) / 4.6)
    local nh = min(L.histN, 5, max(0, room))
    for j = 0, nh - 1 do
      local i = (L.histN - 1 - j) % 5 + 1
      local who = L.histWho[i]
      local name = who == 0 and T("auction.you") or (L.bidders[who] and L.bidders[who].name or "?")
      K.text(name, x + 4, yy, 3.6, who == 0 and C.red or C.faint, "left", w - 30)
      money(L.histAmt[i], x + w - 4, yy, 3.6, C.faint, true)
      yy = yy + 4.6
    end
    -- your maximum: - / + and the amount, then Place Bid (Raise while you're in it)
    local stepping = st.focus == "step"
    -- (not stepping: your maximum while you're in it, else the least you could bid)
    local amount = stepping and st.amount or (L.mine and L.mine.max or Au.minBid(L))
    local sb = K.R(x + 4, y + h - 25, 22, 10)
    K.col(C.cardHi)
    K.box("fill", sb, 3.2)
    K.col(C.line)
    K.box("fill", K.R(sb[1] + 11, sb[2] + 2.2, 0.3, 5.6))
    K.text("-", sb[1], sb[2] + 1.4, 6, C.text, "center", 11)
    K.text("+", sb[1] + 11, sb[2] + 1.6, 6, C.text, "center", 11)
    K.addHit(K.R(sb[1], sb[2], 11, 10), "win", STEP_MINUS)
    K.addHit(K.R(sb[1] + 11, sb[2], 11, 10), "win", STEP_PLUS)
    if stepping then K.focusRing(sb, 3.2) end
    K.text(T("auction.max"), sb[1] + 25, sb[2] + 0.4, 3.4, C.soft)
    money(amount, sb[1] + 25, sb[2] + 4.2, 5, (stepping or L.mine) and C.text or C.faint)
    local go = K.R(x + 4, y + h - 13, w - 8, 10)
    local ended = left <= 30
    K.col(ended and C.cardHi or C.red)
    K.box("fill", go, 3.2)
    if stepping then K.focusRing(go, 3.2) end
    local label = T(L.mine and "auction.raise" or "auction.place")
    local fs = K.fit(label, 4.8, go[3] - 3)
    K.bold(label, go[1], go[2] + (go[4] - fs * 1.2) / 2, fs, ended and C.faint or C.white, "center", go[3])
    K.addHit(go, "win", STEP_GO)
  end

  -- My Bids: the running ones (your max, winning or outbid, the time left), then the results
  local function drawMine(x, y, w, h, t)
    K.col(C.card)
    K.box("fill", K.R(x, y, w, h), 4)
    st.visible = max(1, floor((h - 2) / ROW_H))
    clampList()
    local clip = K.R(x, y + 1, w, h - 2)
    K.scissor(clip)
    if st.mineN == 0 then
      K.text(T("auction.none"), x, y + h / 2 - 3, 4.6, C.faint, "center", w)
    end
    local first = floor(st.mineTop) + 1
    local last = min(st.mineN, first + st.visible + 1)
    for i = first, last do
      local r = st.mineRows[i]
      local ry = y + 1 + (i - 1 - st.mineTop) * ROW_H
      local rb = K.R(x + 1.5, ry + 0.4, w - 3, ROW_H - 0.8)
      if i == st.mineCursor then
        K.col(C.redSoft)
        K.box("fill", rb, 2.5)
      end
      monIcon(r.sp, x + 2.5, ry + 1.5, 10)
      local ns = K.fit(r.name or "?", 4.6, w - 60)
      K.bold(r.name or "?", x + 14, ry + 1.8 + (4.6 - ns) * 0.5, ns, C.text)
      local px = x + 14
      px = px + pill(T(TIER_KEY[r.tier] or TIER_KEY.common), px, ry + 7.3, 3.4, TIER_C[r.tier] or TIER_C.common) + 2
      K.text(levelText(r.level or 1), px, ry + 7.4, 3.8, C.soft)
      if i <= st.mineBids then
        local L = listingOf(r.key)
        local lead = L and L.leader == 0
        local tag = T(L and (lead and "auction.winning" or "auction.outbid") or "auction.ended")
        K.text(tag, x + w - 4 - 40, ry + 1.8, 4.2, L and (lead and C.green or C.red) or C.soft, "right", 40)
        K.text(leftText(leftKey((r.finish or 0) - t)), x + w - 4 - 30, ry + 7.4, 3.8, C.soft, "right", 30)
      else
        K.text(T(r.won and "auction.won" or "auction.lost"), x + w - 4 - 40, ry + 1.8, 4.2,
          r.won and C.green or C.soft, "right", 40)
        local note = r.won and T(r.where == "pc" and "auction.toPc" or "auction.toParty") or T("auction.refunded")
        local nw = K.width(note, 3.6)
        K.text(note, x + w - 4 - nw, ry + 7.5, 3.6, C.faint)
        if r.won then money(r.price or 0, x + w - 6 - nw, ry + 7.5, 3.6, C.soft, true) end
      end
      if i ~= st.mineCursor then
        K.col(C.line)
        K.box("fill", K.R(x + 14, ry + ROW_H - 0.2, w - 16, 0.25))
      end
      K.addHit(rb, "win", MINE + i, clip)
    end
    K.scrollbar(x + w, y + 1, h - 2, st.mineTop, st.visible, st.mineN)
    K.scissor(nil)
  end

  -- the head: the R, Browse | My Bids (a dot while results are unread), the money
  local function drawHead(x, y, w)
    K.col(C.red)
    K.box("fill", K.R(x, y + 1, 8, 8), 2)
    K.bold("R", x, y + 1.9, 5.4, C.white, "center", 8)
    local sx, sw = x + 11, min(70, w * 0.5)
    K.col(C.card)
    K.box("fill", K.R(sx, y + 1, sw, 8), 2.6)
    local half = sw / 2
    for i = 1, 2 do
      local on = (i == 1) == (st.tab == "browse")
      local b = K.R(sx + 0.5 + (i - 1) * half, y + 1.5, half - 1, 7)
      if on then
        K.col(C.cardHi)
        K.box("fill", b, 2.2)
      end
      local label = T(i == 1 and "auction.browse" or "auction.mine")
      local fs = K.fit(label, 4.2, half - 4)
      if on then K.bold(label, b[1], b[2] + 1.3, fs, C.text, "center", b[3])
      else K.text(label, b[1], b[2] + 1.3, fs, C.soft, "center", b[3]) end
      K.addHit(b, "win", i == 1 and SEG_BROWSE or SEG_MINE)
    end
    if Au.unread() > 0 then
      K.col(C.red)
      local G = K.graphics()
      G.circle("fill", K.X(sx + sw - 3), K.Y(y + 2.5), 1.3 * K.sc)
    end
    local s = session()
    money(max(0, floor(tonumber(s and s.money) or 0)), x + w - 1, y + 2.4, 5, C.text, true)
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    local t = clockNow()
    K.col(C.bg)
    K.box("fill", body)
    local L = current()
    if st.tab == "mine" then rebuildMine(false) end
    drawHead(x + M, y + 1, w - M * 2)
    local top = y + HEAD_H + 1.5
    local bodyH = y + h - M - top
    if st.tab == "mine" then
      drawMine(x + M, top, w - M * 2, bodyH, t)
    elseif portrait then
      local dh = min(64, bodyH * 0.5)
      local lh = bodyH - dh - M
      drawBrowseList(x + M, top, w - M * 2, lh, st.focus == "list", t)
      K.scissor(body)
      drawDetail(L, x + M, top + lh + M, w - M * 2, dh, t, true)
    else
      local lw = floor((w - M * 3) * 0.52)
      drawBrowseList(x + M, top, lw, bodyH, st.focus == "list", t)
      K.scissor(body)
      drawDetail(L, x + M * 2 + lw, top, w - M * 3 - lw, bodyH, t, bodyH < 80)
    end
    K.scissor(body)
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h), C.red, C.green, K.UI.hud) then
      st.toast = nil
    end
  end

  current()
  return W
end
