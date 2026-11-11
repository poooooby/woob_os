-- Challenges (the model is src/challenges.lua, env.challenges): this week's five goals, each with its
-- progress, its reward and Claim once it's done; the week's countdown and a ring of how many are
-- claimed; the bonus for claiming all five.
--   buttons  Up / Down a goal (the bonus last), A claim, B close
--   touch    Claim; drag (or the wheel) scrolls when they don't all fit
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, sin, pi = math.floor, math.max, math.min, math.sin, math.pi

local M = 3
local CLAIM, BONUS = 2100, 2200
local HINTS = { main = { { "^ v", "hint.choose" }, { "A", "challenges.claim" }, { "B", "hint.close" } } }
-- each kind's picture (src/icons.lua) and colour
local LOOK = {
  trainer = { "glove", { 255, 69, 58 } }, wild = { "flame", { 255, 149, 0 } }, catch = { "pokeball", { 226, 70, 72 } },
  type = { "pokeball", { 88, 86, 214 } }, new = { "database", { 0, 122, 255 } }, hatch = { "cube", { 255, 189, 46 } },
  evolve = { "send", { 175, 82, 222 } }, items = { "bag", { 52, 170, 220 } }, steps = { "shoes", { 52, 199, 89 } },
  places = { "internet", { 48, 176, 199 } }, levels = { "chart", { 255, 55, 95 } }, swarm = { "fish", { 0, 150, 136 } },
}
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env)
  local K, Ch, T = env.K, env.challenges, env.T or NO_T
  local UI = K.UI
  local W = { title = T("app.challenges") }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local st = { cursor = 1, keys = false, top = 0, toast = nil, texts = {}, flash = {} }
  W.state = st
  ctx.resume = nil

  local function commas(n)
    local s = tostring(floor(n))
    repeat
      local k
      s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return s
  end
  local countText = K.textCache(function(key) return floor(key / 100000) .. " / " .. key % 100000 end)
  local endsText = K.textCache(function(mins)
    if mins >= 1440 then return T.f("challenges.endsDays", floor(mins / 1440), floor(mins % 1440 / 60)) end
    return T.f("challenges.endsHours", floor(mins / 60), mins % 60)
  end)
  local timesText = K.textCache(function(n) return "x" .. n end)
  local doneText = K.textCache(function(n) return n .. "/5" end)

  -- the goals' words: made again for a new week or another language
  local function texts(list)
    local code = T.code and T.code() or ""
    if st.textsList ~= list or st.textsCode ~= code then
      st.textsList, st.textsCode = list, code
      for i, e in ipairs(list) do st.texts[i] = Ch.text(e) end
    end
    return st.texts
  end
  -- (the countdown, worked out once a second: the local time makes tables)
  local function endsMinutes()
    local sec = floor(now())
    if st.endsAt ~= sec then st.endsAt, st.endsMin = sec, floor(Ch.endsIn() / 60) end
    return st.endsMin
  end

  local function toast(text, bad) st.toast = { text = text, bad = bad, t = now() } end
  local function claim(i)
    local s = session()
    local ok, r
    if i > #Ch.list(s) then ok, r = Ch.claimBonus(s) else ok, r = Ch.claim(s, i) end
    if not ok then
      se("SE_FAILURE")
      return toast(T("reason.challenges." .. tostring(r)), true)
    end
    st.flash[i] = now()
    if r.money then
      se("SE_SHOP")
      toast(T.f("challenges.gotMoney", commas(r.money)), false)
    else
      se("SE_SUCCESS")
      local name = env.itemName and env.itemName(r.item) or tostring(r.item)
      toast(T.f("challenges.gotItem", name, r.n), false)
      if env.pad and env.pad.transfer then pcall(env.pad.transfer, r.item, "in") end
    end
  end

  local cur
  function W.input(input, nav)
    cur = input
    if input:wasPressed("b") then return false end
    local n = #Ch.list(session()) + 1
    if nav.up or nav.down then
      if not st.keys then
        st.keys = true
      else
        st.cursor = max(1, min(n, st.cursor + (nav.down and 1 or -1)))
      end
      se("SE_SELECT")
    elseif input:wasPressed("a") then
      st.keys = true
      claim(st.cursor)
    end
    return true
  end
  function W.tap(arg)
    st.keys = false
    if arg == BONUS then return claim(#Ch.list(session()) + 1) end
    if type(arg) == "number" and arg > CLAIM and arg < BONUS then claim(arg - CLAIM) end
  end
  function W.scroll(dy)
    st.top = max(0, min(st.maxTop or 0, st.top - dy))
  end
  function W.hints() return T.list(HINTS.main) end

  -- ------- drawing (no tables made here)

  local WHITE = { 255, 255, 255 }
  local GREEN, GOLD = { 52, 199, 89 }, { 255, 189, 46 }

  local function money(n, x, y, size, c, right)
    if not env.amount then return 0 end
    local ok, w = pcall(env.amount, n, 0, 0, size, c, true)
    w = ok and tonumber(w) or 0
    pcall(env.amount, n, right and x - w or x, y, size, c)
    return w
  end
  local function ring(cx, cy, r, k, c, width)
    local G = K.graphics()
    G.setLineWidth(max(1, width * K.sc))
    K.col(UI.fill)
    G.circle("line", K.X(cx), K.Y(cy), r * K.sc)
    if k > 0 then
      K.col(c)
      G.arc("line", "open", K.X(cx), K.Y(cy), r * K.sc, -pi / 2, -pi / 2 + 2 * pi * min(1, k), 32)
    end
  end
  -- a tick in a circle
  local function check(cx, cy, r, c)
    local G = K.graphics()
    K.col(c)
    G.circle("fill", K.X(cx), K.Y(cy), r * K.sc)
    G.setColor(1, 1, 1, 1)
    G.setLineWidth(max(1, r * 0.28 * K.sc))
    G.line(K.X(cx - r * 0.45), K.Y(cy), K.X(cx - r * 0.1), K.Y(cy + r * 0.35), K.X(cx + r * 0.5), K.Y(cy - r * 0.35))
  end
  -- a reward: money, or an item's picture and how many -> its width
  local function reward(r, x, y, right)
    if r.money then return money(r.money, x, y + 1, 4.2, UI.label, right) end
    local tw = K.width(timesText(r.n), 3.8)
    local w = 9 + tw
    local x0 = right and x - w or x
    if env.itemIcon then pcall(env.itemIcon, r.item, x0, y - 1.5, 8) end
    K.text(timesText(r.n), x0 + 9, y + 1.4, 3.8, UI.secondary)
    return w
  end

  local function drawRow(i, e, text, x, y, w, h, clock)
    local b = K.R(x, y, w, h)
    K.card(b, 4)
    local look = LOOK[e.kind] or LOOK.catch
    local p, done = Ch.progress(e), Ch.done(e)
    -- (the picture in a ring of progress)
    local rr = h * 0.32
    local cx, cy = x + 4 + rr, y + h / 2
    ring(cx, cy, rr, p / max(1, e.goal), done and GREEN or look[2], 1)
    K.col(look[2])
    K.graphics().circle("fill", K.X(cx), K.Y(cy), (rr - 1.6) * K.sc)
    if env.glyph then pcall(env.glyph, K.graphics(), look[1], K.X(cx), K.Y(cy), (rr - 1.6) * 2 * K.sc, 1, look[2]) end
    -- (the words, the bar, the count)
    local tx = cx + rr + 3.5
    local right = x + w - 4
    local rw = 24
    local tw = right - rw - tx - 2
    K.text(text, tx, y + h * 0.18, K.fit(text, 4.3, tw), e.claimed and UI.tertiary or UI.label)
    local by = y + h * 0.62
    K.col(UI.fill)
    K.box("fill", K.R(tx, by, tw - 16, 1.6), 0.8)
    K.col(done and GREEN or look[2])
    K.box("fill", K.R(tx, by, (tw - 16) * p / max(1, e.goal), 1.6), 0.8)
    K.text(countText(p * 100000 + e.goal), tx + tw - 15, by - 1.3, 3.4, UI.secondary, "right", 15)
    -- (the reward, Claim, or the tick)
    if e.claimed then
      check(right - 4, cy, 3.4, GREEN)
    elseif done then
      local cb = K.R(right - rw, cy - 4.5, rw, 9)
      local pulse = 0.5 + 0.5 * sin(clock * 4)
      K.col(UI.accent, 0.18 * pulse)
      K.box("fill", K.R(cb[1] - 1, cb[2] - 1, cb[3] + 2, cb[4] + 2), 5)
      K.button(cb, T("challenges.claim"), "accent", st.keys and st.cursor == i, 4.2)
      K.addHit(cb, "win", CLAIM + i)
    else
      reward(e.reward, right, cy - 2.6, true)
    end
    if st.keys and st.cursor == i and not (done and not e.claimed) then K.focusRing(b, 4) end
    local f = st.flash[i]
    if f and now() - f < 0.5 then
      K.col(GREEN, 0.25 * (1 - (now() - f) / 0.5))
      K.box("fill", b, 4)
    end
  end

  -- the week: the countdown, a ring of how many are claimed, the bonus
  local function drawWeek(x, y, w, h, list, clock)
    local b = K.R(x, y, w, h)
    K.card(b, 5)
    local s = session()
    K.bold(T("challenges.week"), x + 5, y + 4, 6, UI.label)
    K.text(endsText(endsMinutes()), x + 5, y + 12, 3.8, UI.secondary)
    local claimed = 0
    for _, e in ipairs(list) do if e.claimed then claimed = claimed + 1 end end
    local rr = min(w * 0.22, (h - 50) / 2)
    local cx, cy = x + w / 2, y + 22 + rr
    if rr > 4 then
      ring(cx, cy, rr, claimed / max(1, #list), GOLD, 2.2)
      K.bold(doneText(claimed), cx - rr, cy - 3.2, 6, UI.label, "center", rr * 2)
    end
    -- (the bonus)
    local bonus = Ch.bonus(s)
    local bb = K.R(x + 4, y + h - 22, w - 8, 18)
    K.col(GOLD, 0.16)
    K.box("fill", bb, 4)
    K.bold(T("challenges.bonus"), bb[1] + 3, bb[2] + 2.5, 4.2, UI.label)
    K.text(T("challenges.bonusNote"), bb[1] + 3, bb[2] + 8.5, 3.4, UI.secondary)
    local i = #list + 1
    if bonus.claimed then
      check(bb[1] + bb[3] - 6, bb[2] + 9, 3.4, GREEN)
    elseif Ch.bonusReady(s) then
      local cb = K.R(bb[1] + bb[3] - 23, bb[2] + 4.5, 21, 9)
      K.button(cb, T("challenges.claim"), "accent", st.keys and st.cursor == i, 4.2)
      K.addHit(cb, "win", BONUS)
    else
      reward(bonus, bb[1] + bb[3] - 3, bb[2] + 6.5, true)
    end
    if st.keys and st.cursor == i then K.focusRing(bb, 4) end
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    st.clip = body
    local s = session()
    local list = Ch.list(s)
    local words = texts(list)
    if not portrait and w >= 200 then
      local lw = floor((w - M * 3) * 0.36)
      drawWeek(x + M, y + M, lw, h - M * 2, list, clock)
      local rx, rw = x + M * 2 + lw, w - lw - M * 3
      local rh = min(22, (h - M * 2 - (#list - 1) * 2) / max(1, #list))
      st.maxTop, st.top = 0, 0
      for i, e in ipairs(list) do drawRow(i, e, words[i], rx, y + M + (i - 1) * (rh + 2), rw, rh, clock) end
    else
      -- (upright: the week's card, then the goals, scrolling)
      local hh = 34
      local hb = K.R(x + M, y + M, w - M * 2, hh)
      K.card(hb, 5)
      K.bold(T("challenges.week"), hb[1] + 4, hb[2] + 3, 5.4, UI.label)
      K.text(endsText(endsMinutes()), hb[1] + 4, hb[2] + 10, 3.6, UI.secondary)
      local claimed = 0
      for _, e in ipairs(list) do if e.claimed then claimed = claimed + 1 end end
      ring(hb[1] + hb[3] - 10, hb[2] + 9, 6, claimed / max(1, #list), GOLD, 1.6)
      K.text(doneText(claimed), hb[1] + hb[3] - 16, hb[2] + 7.4, 3.2, UI.label, "center", 12)
      local bonus = Ch.bonus(s)
      K.text(T("challenges.bonus"), hb[1] + 4, hb[2] + 19, 3.8, UI.label)
      local i = #list + 1
      if bonus.claimed then
        check(hb[1] + hb[3] - 8, hb[2] + 26, 3, GREEN)
      elseif Ch.bonusReady(s) then
        local cb = K.R(hb[1] + hb[3] - 23, hb[2] + 22, 20, 9)
        K.button(cb, T("challenges.claim"), "accent", st.keys and st.cursor == i, 4)
        K.addHit(cb, "win", BONUS)
      else
        reward(bonus, hb[1] + hb[3] - 4, hb[2] + 24, true)
      end
      local top = y + M + hh + 3
      local rh = 20
      local area = K.R(x, top, w, y + h - top)
      st.maxTop = max(0, #list * (rh + 2) - area[4])
      st.top = min(st.top, st.maxTop)
      if st.keys and st.cursor <= #list then
        local cy = (st.cursor - 1) * (rh + 2)
        if cy < st.top then st.top = cy end
        if cy + rh > st.top + area[4] then st.top = cy + rh - area[4] end
      end
      K.scissor(area)
      for j, e in ipairs(list) do drawRow(j, e, words[j], x + M, top + (j - 1) * (rh + 2) - st.top, w - M * 2, rh, clock) end
      K.scissor(body)
    end
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h), UI.red, UI.green, UI.hud) then st.toast = nil end
  end

  return W
end
