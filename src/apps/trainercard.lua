-- The trainer card, full screen (Modern Menus' "Trainer Card" switch; every game): a glass card floating over a
-- night lit in its tier's colours -- the game's own card colour by its stars (Gen 3) or by what's been done (the
-- Game Boy games) -- with a foil edge, engraved lines, a holographic sweep and a holo sticker. Its pages turn over
-- like a card, in perspective (the page drawn once into a canvas, laid on a strip of quads that turns about its
-- middle, the far side darker): the front (the trainer's portrait under a spotlight, name, ID, the Hall of Fame,
-- money, the Pokédex, play time with its colon blinking, stars, the badge strip), a page for each set of badges (the
-- game's own badge art in glass medallions, the leaders' names, their faces on the Game Boy games; earned ones lit
-- and glinting, the rest dark) and the records (the Hall of Fame, link battles, trades, what the game counted, the
-- party), the back's dark stripe with the ID as a barcode. Held upright, a tall card laid out for it.
--   buttons  A / Right / R the next page, Left / L the one before, B closes
--   touch    tap the card for the next page, the arrows beside it, the dots, the close button
-- The model (ctx.menu) is src/trainercard.lua's (Gen 3) or src/gb/trainercard.lua's (the Game Boy games):
--   card = { name, female, idText, money, hours, minutes, dex = { caught, seen, total } | nil, stars, maxStars,
--            tier (0..4), champion (words) | nil, region (words), sets = { { title, badges = { { name, leader,
--            have, color } } } }, records = { { icon, color, label, value, sub, bar } }, party = { { sp, level,
--            mon } }, art = { portrait(cx, foot, w, h), badge(set, i, cx, cy, size, clock, have),
--            face(set, i, cx, cy, size, have) | nil }, sounds = { open, flip, close } | nil, release() | nil }
-- Nothing made while drawing: the words are the model's (made when it's opened), the particles a fixed pool, the
-- flip's canvas and mesh made once (again only when the window's size changes).

local floor, max, min, sin, cos, abs, pi = math.floor, math.max, math.min, math.sin, math.cos, math.abs, math.pi

local A = { CARD = 3001, CLOSE = 3002, PREV = 3003, NEXT = 3004, DOT = 3010 }
local FLIP, IN, OUT = 0.5, 0.7, 0.28
local RATIO = 1.586
local STRIPS = 28
-- (the tiers: the card's metal, its foil edge, the light round it, the words on it)
local TIERS = {
  [0] = { top = { 96, 138, 236 }, foot = { 24, 38, 116 }, edge = { 190, 216, 255 }, glow = { 84, 132, 255 },
          glow2 = { 124, 92, 236 }, ink = { 255, 255, 255 }, soft = { 204, 216, 255 }, dark = true },
  [1] = { top = { 226, 160, 108 }, foot = { 108, 54, 28 }, edge = { 255, 218, 182 }, glow = { 255, 146, 80 },
          glow2 = { 214, 84, 56 }, ink = { 255, 255, 255 }, soft = { 255, 226, 202 }, dark = true },
  [2] = { top = { 236, 241, 250 }, foot = { 118, 130, 156 }, edge = { 255, 255, 255 }, glow = { 182, 208, 255 },
          glow2 = { 140, 162, 210 }, ink = { 30, 34, 48 }, soft = { 70, 80, 104 }, dark = false },
  [3] = { top = { 255, 226, 126 }, foot = { 156, 100, 16 }, edge = { 255, 248, 214 }, glow = { 255, 194, 64 },
          glow2 = { 255, 136, 36 }, ink = { 50, 32, 4 }, soft = { 102, 70, 16 }, dark = false },
  [4] = { top = { 72, 68, 96 }, foot = { 8, 8, 14 }, edge = { 226, 204, 255 }, glow = { 168, 108, 255 },
          glow2 = { 56, 200, 255 }, ink = { 255, 255, 255 }, soft = { 204, 194, 234 }, dark = true },
}
local C = { white = { 255, 255, 255 }, black = { 0, 0, 0 }, night = { 8, 10, 24 }, nightFoot = { 2, 2, 8 },
            gold = { 255, 214, 90 }, goldDeep = { 196, 132, 16 }, goldInk = { 72, 46, 4 }, socket = { 0, 0, 0 },
            stripe = { 14, 14, 20 }, green = { 52, 199, 89 }, red = { 255, 69, 58 }, blue = { 10, 132, 255 },
            ice = { 214, 236, 255 }, back = { 210, 214, 230 } }
-- (the holographic sweep's colours, in turn)
local HOLO = { { 255, 120, 200 }, { 120, 200, 255 }, { 140, 255, 190 }, { 255, 236, 120 }, { 190, 140, 255 } }
-- (the lights drifting in the night, the twinkles)
local NL, NT = 18, 36

return function(ctx, env)
  local K, T = env.K, env.T
  local Fx = env.sceneFx
  local card = ctx.menu
  local function now() return env.now and env.now() or (love and love.timer and love.timer.getTime() or 0) end
  local function se(name) if name and env.se then pcall(env.se, name) end end
  local rnd = love and love.math and love.math.random or math.random
  local word = T or function(k) return k end

  local W = { title = "" }
  if not (card and Fx) then
    function W.draw() if ctx.done then ctx.done() end end
    function W.input() return true end
    return W
  end
  local tierN = max(0, min(4, floor(tonumber(card.tier) or 0)))
  local tier = TIERS[tierN]
  local sets = card.sets or {}

  -- the pages: the front, each set of badges, the records
  local PAGES = { { kind = "front" } }
  for i = 1, #sets do PAGES[#PAGES + 1] = { kind = "badges", set = i } end
  PAGES[#PAGES + 1] = { kind = "records" }
  local NP = #PAGES

  local t0 = now()
  local st = { page = 1, from = nil, flipAt = -10, dir = 1, outAt = nil, glintAt = t0 }
  W.state = st

  -- (the night's lights and twinkles: a fixed pool, placed once)
  local LT = { x = {}, y = {}, s = {}, v = {}, hue = {} }
  for i = 1, NL do
    LT.x[i], LT.y[i], LT.s[i], LT.v[i], LT.hue[i] = rnd(), rnd(), 10 + rnd() * 26, 0.006 + rnd() * 0.02, rnd()
  end
  local TW = { x = {}, y = {}, s = {}, ph = {}, sp = {} }
  for i = 1, NT do
    TW.x[i], TW.y[i], TW.s[i], TW.ph[i], TW.sp[i] = rnd(), rnd(), 0.5 + rnd() * 1.3, rnd() * 6.28, 0.6 + rnd() * 1.6
  end

  -- the words this card shows, once
  local wd = {
    title = word("tc.title"), badges = word("tc.badges"), records = word("tc.records"), idNo = word("tc.id"),
    money = word("tc.money"), dex = word("tc.dex"), time = word("tc.time"), party = word("tc.party"),
    seen = word("tc.seen"), none = word("tc.none"), tierName = word("tc.tier." .. tostring(tierN)),
  }
  wd.hours = tostring(floor(tonumber(card.hours) or 0))
  wd.minutes = string.format("%02d", floor(tonumber(card.minutes) or 0))
  if card.dex then
    wd.dexCaught = tostring(card.dex.caught or 0)
    wd.dexOf = card.dex.total and card.dex.total > 0 and ("/ " .. tostring(card.dex.total)) or ""
  end
  local setWords = {}
  for i, set in ipairs(sets) do
    local have = 0
    for _, b in ipairs(set.badges or {}) do if b.have then have = have + 1 end end
    set.haveN = have
    setWords[i] = string.format("%d / %d", have, #(set.badges or {}))
  end
  for _, p in ipairs(card.party or {}) do p.levelText = p.level and ("Lv. " .. tostring(p.level)) or "" end
  -- (the ID as a barcode on the back's stripe: bars from its digits, made once)
  local BAR = {}
  do
    local id = tostring(card.idText or "00000")
    for i = 1, #id do
      local d = tonumber(id:sub(i, i)) or 0
      BAR[#BAR + 1] = 1 + d % 3
      BAR[#BAR + 1] = 1 + floor(d / 3) % 3
      BAR[#BAR + 1] = 1 + (d + i) % 2
    end
  end

  if card.sounds then se(card.sounds.open) end

  -- ------- moving between pages
  local function turn(d)
    if st.outAt or now() - st.flipAt < FLIP * 0.55 then return end
    local to = (st.page - 1 + d) % NP + 1
    if to == st.page then return end
    st.from, st.page, st.flipAt, st.dir = st.page, to, now(), d
    se(card.sounds and card.sounds.flip or "SE_SELECT")
  end
  local function goTo(i)
    if i == st.page or st.outAt then return end
    st.from, st.page, st.flipAt, st.dir = st.page, i, now(), i > st.page and 1 or -1
    se(card.sounds and card.sounds.flip or "SE_SELECT")
  end
  local function leave()
    if st.outAt then return end
    st.outAt = now()
    se(card.sounds and card.sounds.close or "SE_SELECT")
  end

  function W.input(input, nav)
    if st.outAt then return true end
    local function p(k) return input:wasPressed(k) end
    if p("b") or p("start") then leave()
    elseif p("a") or p("r") or (nav and nav.right) then turn(1)
    elseif p("l") or (nav and nav.left) then turn(-1) end
    return true
  end
  function W.tap(arg)
    if st.outAt or type(arg) ~= "number" then return end
    if arg == A.CLOSE then leave()
    elseif arg == A.CARD or arg == A.NEXT then turn(1)
    elseif arg == A.PREV then turn(-1)
    elseif arg > A.DOT and arg <= A.DOT + NP then goTo(arg - A.DOT) end
  end
  function W.hints() return nil end

  -- ------- drawing
  local G
  local function ease(t) return K.outCubic(max(0, min(1, t))) end
  local tall = false

  -- the holographic sweep: a soft slanted band of turning colour crossing the card every 5 s
  local function sweep(x, y, w, h, clock, strength)
    local cyc = (clock * 0.2) % 1
    local u = -0.4 + cyc * 1.8
    local slant = h * 0.5
    local lo, hi = x + 2, x + w - 2
    local hc = HOLO[floor(clock * 0.2) % #HOLO + 1]
    G.setBlendMode("add")
    for band = 1, 3 do
      local bw = w * (0.05 + band * 0.045)
      local x1 = x + w * u - bw / 2
      local x2 = x1 + bw
      local ax, bx = max(lo, min(hi, x1)), max(lo, min(hi, x2))
      local cx2, dx2 = max(lo, min(hi, x1 - slant)), max(lo, min(hi, x2 - slant))
      if bx - ax > 0.2 or dx2 - cx2 > 0.2 then
        K.col(hc, (0.09 - band * 0.022) * strength)
        G.polygon("fill", K.X(ax), K.Y(y + 1.5), K.X(bx), K.Y(y + 1.5), K.X(dx2), K.Y(y + h - 1.5),
          K.X(cx2), K.Y(y + h - 1.5))
      end
    end
    G.setBlendMode("alpha")
  end

  -- the card's metal, the lines engraved in it, the Poké Ball pressed into the front, the back's stripe, the
  -- sweep, the foil edge
  local function cardBase(x, y, w, h, clock, back)
    local rad = min(w, h) * 0.075
    local b = K.R(x, y, w, h)
    K.shadow(b, rad, 3.2, 0.45)
    K.grad(b, rad, tier.top, tier.foot)
    -- (the guilloche: fine arcs round a point past the right edge, kept inside the card)
    G.setLineWidth(max(1, 0.25 * K.sc))
    K.col(tier.dark and C.white or C.black, 0.07)
    local span = max(w, h)
    local ox, oy = x + w * 1.05, y + h * 0.5
    for i = 1, 11 do
      local r = span * (0.12 + i * 0.075)
      local px, py
      for s = 0, 32 do
        local a = pi * 0.5 + (s / 32) * pi
        local qx, qy = ox + cos(a) * r, oy + sin(a) * r * 0.82
        local ok = qx > x + rad and qx < x + w - 1 and qy > y + 1 and qy < y + h - 1
        if px and ok then G.line(K.X(px), K.Y(py), K.X(qx), K.Y(qy)) end
        if ok then px, py = qx, qy else px = nil end
      end
    end
    if not back then
      local er = min(w, h) * 0.36
      local ex, ey = x + w - er * 0.62, y + h * 0.6
      K.col(tier.dark and C.white or C.black, 0.06)
      G.setLineWidth(max(1, er * 0.1 * K.sc))
      G.arc("line", "open", K.X(ex), K.Y(ey), er * K.sc, pi * 0.5, pi * 1.5, 24)
      G.line(K.X(ex - er), K.Y(ey), K.X(ex - er * 0.28), K.Y(ey))
      G.circle("line", K.X(ex), K.Y(ey), er * 0.26 * K.sc, 20)
    else
      -- (the back: a dark stripe along the top, as a card's)
      local sh = min(h * 0.13, 15)
      K.col(C.stripe, 0.88)
      K.box("fill", K.R(x, y + sh * 0.75, w, sh))
      K.grad(K.R(x, y + sh * 0.75, w, sh * 0.3), 0, C.white, C.black, 0.08)
    end
    K.grad(K.R(x, y, w, h * 0.45), rad, C.white, tier.top, tier.dark and 0.14 or 0.3)
    sweep(x, y, w, h, clock, tier.dark and 1 or 0.75)
    K.ring(b, rad, tier.edge, 0.95, 0.7)
    K.ring(K.R(x + 1.1, y + 1.1, w - 2.2, h - 2.2), max(0.5, rad - 1), C.white, tier.dark and 0.18 or 0.4, 0.3)
  end
  local function stripeY(y, h) local sh = min(h * 0.13, 15) return y + sh * 0.75, sh end

  -- a sparkle star: lit (gold, glowing) or a dim slot
  local function star(cx, cy, r, lit, clock, i)
    if lit then
      K.glow(cx, cy, r * 2.4, r * 2.4, C.gold, 0.35 + 0.15 * sin(clock * 3 + i))
      Fx.star(cx, cy, r * 1.25, C.gold, 1, 0)
      Fx.star(cx, cy, r * 0.7, C.white, 0.9, 0)
    else
      Fx.star(cx, cy, r * 1.05, tier.dark and C.white or C.black, 0.3, 0)
    end
  end

  -- a glass socket with a badge in it (have: lit and ringed in its colour; else dark)
  local function medallion(set, i, cx, cy, r, clock, have, color, glint)
    local b = K.R(cx - r, cy - r, r * 2, r * 2)
    if have then K.glow(cx, cy, r * 1.9, r * 1.9, color or C.gold, 0.32) end
    K.col(C.socket, have and 0.28 or 0.4)
    K.box("fill", b, r)
    K.grad(K.R(cx - r, cy - r, r * 2, r), r, C.white, C.black, have and 0.16 or 0.06)
    K.ring(b, r, have and (color or C.gold) or C.white, have and 0.95 or 0.22, have and 0.55 or 0.3)
    card.art.badge(set, i, cx, cy, r * 1.45, clock, have)
    if have and glint > 0 then
      Fx.star(cx + r * 0.45, cy - r * 0.45, r * 0.7 * glint, C.white, glint, clock * 2)
    end
  end
  local function glintOf(clock, i, n, have, every)
    if not have then return 0 end
    local k = (clock - st.glintAt) / every
    if floor(k) % (n + 5) + 1 ~= i then return 0 end
    return sin((k % 1) * pi)
  end

  -- the holo sticker: a disc of turning colours with the ball on it
  local function sticker(hx, hy, hr, clock)
    local hc1 = HOLO[floor(clock * 1.2) % #HOLO + 1]
    local hc2 = HOLO[(floor(clock * 1.2) + 2) % #HOLO + 1]
    K.glow(hx, hy, hr * 1.8, hr * 1.8, hc1, 0.3)
    K.col(hc2, 0.9)
    G.circle("fill", K.X(hx), K.Y(hy), hr * K.sc, 28)
    K.col(hc1, 0.75)
    G.circle("fill", K.X(hx + sin(clock * 1.7) * hr * 0.2), K.Y(hy - hr * 0.2), hr * 0.7 * K.sc, 24)
    K.col(C.white, 0.95)
    G.setLineWidth(max(1, hr * 0.1 * K.sc))
    G.circle("line", K.X(hx), K.Y(hy), hr * 0.56 * K.sc, 20)
    G.line(K.X(hx - hr * 0.56), K.Y(hy), K.X(hx + hr * 0.56), K.Y(hy))
    G.circle("fill", K.X(hx), K.Y(hy), hr * 0.17 * K.sc, 12)
    K.ring(K.R(hx - hr, hy - hr, hr * 2, hr * 2), hr, C.white, 0.7, 0.35)
  end

  -- the trainer in a glass frame under a spotlight, the stars under it
  local function portrait(px, py, pw, ph, clock)
    local pb = K.R(px, py, pw, ph)
    K.glow(px + pw / 2, py + ph * 0.55, pw * 0.75, ph * 0.65, tier.glow, 0.42)
    K.glass(pb, 4, tier.dark and 0.16 or 0.3, C.white, 0.6, 0.7)
    K.grad(K.R(px, py + ph * 0.55, pw, ph * 0.45), 4, tier.foot, tier.foot, 0.25)
    K.glow(px + pw / 2, py + ph - 3.2, pw * 0.34, 2.2, C.black, 0.45)
    K.glow(px + pw / 2, py + ph * 0.4, pw * 0.3, ph * 0.45, C.white, 0.1 + 0.04 * sin(clock * 1.5))
    card.art.portrait(px + pw / 2, py + ph - 2, pw - 2, ph - 4)
    sticker(px + pw - 1.5, py + ph - 1.5, min(5, pw * 0.11), clock)
  end
  local function stars(cx, cy, w, clock)
    local ms = max(card.maxStars or 4, 1)
    local sr = min(2.5, w / (ms * 2.8))
    local sx0 = cx - (ms - 1) * sr * 1.4
    for i = 1, ms do star(sx0 + (i - 1) * sr * 2.8, cy, sr, i <= (card.stars or 0), clock, i) end
  end

  -- the name, large, with its sign; the Hall of Fame on a gold pill under it -> the y under them
  local function nameBlock(rx, ry, rw, align, clock)
    local ink = tier.ink
    local ns = K.fit(card.name or "", 9, rw - 6)
    local nw = K.width(card.name or "", ns)
    local nx = align == "center" and rx + (rw - nw) / 2 or rx
    if tier.dark then K.bold(card.name or "", nx + 0.4, ry + 0.4, ns, C.black, nil, nil, 0.35) end
    K.bold(card.name or "", nx, ry, ns, ink)
    if card.female ~= nil and not K.hasSign(card.name or "") then
      K.sexMark(card.female and "f" or "m", nx + nw + 2.6, ry + ns * 0.62, ns * 0.55, 1)
    end
    local y2 = ry + ns * 1.25 + 0.8
    if card.champion then
      local cs = 2.9
      local tw = K.width(card.champion, cs)
      local pw = min(rw, tw + 9)
      local px = align == "center" and rx + (rw - pw) / 2 or rx
      local pb = K.R(px, y2, pw, 5.2)
      K.grad(pb, 2.6, C.gold, C.goldDeep)
      K.ring(pb, 2.6, C.white, 0.6, 0.3)
      Fx.star(px + 3, y2 + 2.6, 1.6, C.white, 0.95, clock)
      K.bold(card.champion, px + 5.5, y2 + 0.9, K.fit(card.champion, cs, pw - 7), C.goldInk)
      y2 = y2 + 7
    end
    return y2
  end

  -- money, the Pokédex (its bar: seen, caught), play time (the colon blinking) in rows from y to foot
  local function facts(rx, y, rw, foot, clock)
    local ink, soft = tier.ink, tier.soft
    local rowH = (foot - y) / 3
    local function label(s, yy) K.text(s, rx, yy, 3.1, soft, "left", rw * 0.5) end
    local vy = 0.9
    label(wd.money, y + vy)
    if env.amount then
      local mw = env.amount(card.money or 0, 0, 0, 4.6, ink, true)
      env.amount(card.money or 0, rx + rw - mw, y, 4.6, ink)
    end
    K.hairline(rx, y + rowH - 1.6, rw, ink, 0.12)
    local dy = y + rowH
    label(wd.dex, dy + vy)
    if card.dex then
      local cw2 = K.width(wd.dexCaught, 4.6)
      local ow = K.width(wd.dexOf, 3.2)
      K.bold(wd.dexCaught, rx + rw - ow - 1 - cw2, dy, 4.6, ink)
      K.text(wd.dexOf, rx + rw - ow, dy + 1.2, 3.2, soft)
      local bx, by, bw = rx, dy + 6, rw
      local tot = max(1, card.dex.total or card.dex.seen or 1)
      K.col(tier.dark and C.white or C.black, 0.14)
      K.box("fill", K.R(bx, by, bw, 1.3), 0.65)
      K.col(tier.dark and C.ice or tier.soft, 0.45)
      K.box("fill", K.R(bx, by, bw * min(1, (card.dex.seen or 0) / tot), 1.3), 0.65)
      K.col(C.green, 0.95)
      K.box("fill", K.R(bx, by, bw * min(1, (card.dex.caught or 0) / tot), 1.3), 0.65)
    else
      K.text(wd.none, rx, dy + vy, 3.4, soft, "right", rw)
    end
    K.hairline(rx, dy + rowH - 1.6, rw, ink, 0.12)
    local ty = dy + rowH
    label(wd.time, ty + vy)
    local mw2 = K.width(wd.minutes, 4.6)
    local cwid = K.width(":", 4.6)
    local hw = K.width(wd.hours, 4.6)
    local tx = rx + rw - mw2 - cwid - hw
    K.bold(wd.hours, tx, ty, 4.6, ink)
    K.bold(":", tx + hw, ty, 4.6, ink, nil, nil, (floor(clock * 1.1) % 2 == 0) and 1 or 0.25)
    K.bold(wd.minutes, tx + hw + cwid, ty, 4.6, ink)
  end

  -- the badges along the front's foot (or in two rows of four on a tall card)
  local function badgeStrip(x, y, w, h, clock, rows)
    local set = sets[1]
    if not set then return end
    local n = #set.badges
    local per = math.ceil(n / rows)
    local r = min(h / (rows * 2.6), w / (per * 2.5))
    local gap = (w - r * 2) / max(1, per - 1)
    for i, bd in ipairs(set.badges) do
      local col, row = (i - 1) % per, floor((i - 1) / per)
      local cx = x + r + col * gap
      local cy = y + r + row * (h / rows)
      medallion(1, i, cx, cy, r, clock, bd.have, bd.color, glintOf(clock, i, n, bd.have, 0.35))
    end
  end

  -- ------- the front
  local function front(x, y, w, h, clock)
    local ink, soft = tier.ink, tier.soft
    local pad = min(w, h) * 0.07
    -- (the header: the card's name, the region, the ID)
    local hy = y + pad * 0.85
    K.bold(wd.title, x + pad, hy, 3.5, ink, "left", w * 0.5, 0.9)
    if card.region then K.text(card.region, x + pad, hy + 4.4, 2.9, soft, "left", w * 0.5, 0.85) end
    local idw = K.width(card.idText or "", 4.2)
    K.bold(card.idText or "", x + w - pad - idw, hy, 4.2, ink)
    K.text(wd.idNo, x + w - pad - idw - 31.5, hy + 0.6, 3, soft, "right", 30)
    local hl = hy + 9.5
    K.hairline(x + pad, hl, w - pad * 2, ink, 0.22)
    if tall then
      -- (upright: the portrait on top, the name and facts under it, the badges in two rows)
      local pw, ph = w * 0.56, h * 0.27
      local px, py = x + (w - pw) / 2, hl + 4
      portrait(px, py, pw, ph, clock)
      stars(x + w / 2, py + ph + 4.5, pw, clock)
      local ny = nameBlock(x + pad, py + ph + 9, w - pad * 2, "center", clock)
      local foot = y + h * 0.79
      facts(x + pad, ny + 1.5, w - pad * 2, foot, clock)
      badgeStrip(x + pad, foot + 1.5, w - pad * 2, y + h - pad * 0.7 - foot - 1.5, clock, 2)
      return
    end
    -- (wide: the portrait at the left, the name and facts at its right, the badges along the foot)
    local stripH = h * 0.2
    local foot = y + h - pad * 0.55 - stripH
    local pw = w * 0.29
    local ph = foot - 6.5 - (hl + 3)
    local px, py = x + pad, hl + 3
    portrait(px, py, pw, ph, clock)
    stars(px + pw / 2, py + ph + 3.6, pw, clock)
    local rx = px + pw + pad
    local rw = x + w - pad - rx
    local ny = nameBlock(rx, hl + 3, rw, "left", clock)
    facts(rx, ny + 0.5, rw, foot - 1, clock)
    badgeStrip(x + pad, foot + 1, w - pad * 2, stripH, clock, 1)
  end

  -- the back's stripe: the page's title, and at its right the count or the ID's barcode
  local function stripe(x, y, w, h, title, right, bars)
    local sy, sh = stripeY(y, h)
    local pad = min(w, h) * 0.07
    K.bold(title, x + pad, sy + (sh - 4.4 * 1.2) / 2, K.fit(title, 4.4, w * 0.6), C.white)
    if right then
      local rw = K.width(right, 4.2)
      K.bold(right, x + w - pad - rw, sy + (sh - 4.2 * 1.2) / 2, 4.2, C.white)
    elseif bars then
      local bx = x + w - pad
      local bh = sh * 0.56
      local by = sy + (sh - bh) / 2
      K.col(C.white, 0.85)
      for i = #BAR, 1, -1 do
        local bw = BAR[i] * 0.32
        bx = bx - bw
        if i % 2 == 1 then K.box("fill", K.R(bx, by, bw, bh)) end
        bx = bx - 0.3
      end
    end
    return sy + sh
  end

  -- ------- a set of badges
  local function badgesPage(x, y, w, h, clock, si)
    local set = sets[si]
    local ink, soft = C.white, C.back
    local pad = min(w, h) * 0.07
    local top = stripe(x, y, w, h, set.title or wd.badges, setWords[si]) + pad * 0.6
    if set.haveN == #set.badges and #set.badges > 0 then
      Fx.star(x + w - pad - K.width(setWords[si], 4.2) - 3, select(1, stripeY(y, h)) + 7, 1.8, C.gold, 1, clock)
    end
    -- (four across and two down -- two across upright: each its medallion, its name, its leader, and on the Game
    -- Boy games the leader's face beside it)
    local n = #set.badges
    local cols = tall and 2 or 4
    local rows = math.ceil(n / cols)
    local cwid, chei = (w - pad * 2) / cols, (y + h - pad * 0.6 - top) / rows
    local faces = card.art.face ~= nil and (card.art.hasFace == nil or card.art.hasFace(si) == true)
    local r = min(cwid * (faces and 0.17 or 0.2), chei * 0.27)
    for i, bd in ipairs(set.badges) do
      local col, row = (i - 1) % cols, floor((i - 1) / cols)
      local cx = x + pad + col * cwid + cwid / 2
      local cy = top + row * chei + r + 0.5
      local g = glintOf(clock, i, n, bd.have, 0.3)
      if faces then
        local fs = r * 1.7
        local fb = K.R(cx - r * 0.3 - fs - 1, cy - fs * 0.5, fs, fs)
        K.col(C.black, 0.22)
        K.box("fill", fb, 1.4)
        K.ring(fb, 1.4, C.white, 0.18, 0.25)
        card.art.face(si, i, fb[1] + fs / 2, cy, fs * 0.92, bd.have)
        medallion(si, i, cx + r * 0.9, cy, r, clock, bd.have, bd.color, g)
      else
        medallion(si, i, cx, cy, r, clock, bd.have, bd.color, g)
      end
      local ty = cy + r + 1.2
      local nm = bd.name or ""
      K.bold(nm, cx - cwid / 2 + 1, ty, K.fit(nm, 3.1, cwid - 2), bd.have and ink or soft, "center", cwid - 2,
        bd.have and 1 or 0.55)
      local ld = bd.leader or ""
      K.text(ld, cx - cwid / 2 + 1, ty + 3.6, K.fit(ld, 2.7, cwid - 2), soft, "center", cwid - 2, bd.have and 0.9 or 0.45)
    end
  end

  -- ------- the records
  local function recordsPage(x, y, w, h, clock)
    local ink, soft = C.white, C.back
    local pad = min(w, h) * 0.07
    local top = stripe(x, y, w, h, wd.records, nil, true) + pad * 0.5
    local recs = card.records or {}
    local party = card.party or {}
    local partyH = #party > 0 and min(22, h * 0.21) or 0
    local area = y + h - pad * 0.7 - partyH - top
    local cols = 2
    local n = min(#recs, 8)
    local rows = max(1, math.ceil(n / cols))
    local tw = (w - pad * 2 - 2) / cols
    local th = min(16, area / rows - 1.3)
    if n == 0 then K.text(wd.none, x, top + area / 2 - 2, 3.6, soft, "center", w) end
    for i = 1, n do
      local rc = recs[i]
      local col, row = (i - 1) % cols, floor((i - 1) / cols)
      local bx, by = x + pad + col * (tw + 2), top + row * (th + 1.3)
      local b = K.R(bx, by, tw, th)
      K.col(C.white, 0.08)
      K.box("fill", b, 2.4)
      K.ring(b, 2.4, C.white, 0.14, 0.25)
      local isz = min(th * 0.62, 10)
      local ix, iy = bx + 1.8 + isz / 2, by + th / 2
      K.col(rc.color or C.blue, 0.95)
      K.box("fill", K.R(ix - isz / 2, iy - isz / 2, isz, isz), isz * 0.26)
      K.grad(K.R(ix - isz / 2, iy - isz / 2, isz, isz / 2), isz * 0.26, C.white, rc.color or C.blue, 0.25)
      if env.icon and rc.icon then env.icon(rc.icon, ix, iy, isz, 1, rc.color or C.blue) end
      local lx = ix + isz / 2 + 1.8
      local lw = bx + tw - 1.5 - lx
      K.text(rc.label or "", lx, by + th * 0.12, K.fit(rc.label or "", 2.7, lw), soft, "left", lw)
      local vs = K.fit(rc.value or "", 4.4, lw)
      K.bold(rc.value or "", lx, by + th * 0.12 + 3.4, vs, ink, "left", lw)
      if rc.bar then
        local bb = by + th - 2.2
        K.col(C.red, 0.7)
        K.box("fill", K.R(lx, bb, lw, 1), 0.5)
        K.col(C.green, 0.95)
        K.box("fill", K.R(lx, bb, lw * max(0, min(1, rc.bar)), 1), 0.5)
      elseif rc.sub then
        K.text(rc.sub, lx + K.width(rc.value or "", vs) + 1.5, by + th * 0.12 + 4.4, 2.6, soft, "left", lw)
      end
    end
    -- (the party along the foot: their icons bobbing, their levels under them)
    if #party > 0 then
      local py = y + h - pad * 0.7 - partyH
      K.hairline(x + pad, py - 0.4, w - pad * 2, C.white, 0.18)
      K.text(wd.party, x + pad, py + 0.5, 2.6, soft, "left", 30)
      local slot = (w - pad * 2) / 6
      local isz = min(partyH * 0.72, slot * 0.82)
      for i, pm in ipairs(party) do
        local cx = x + pad + slot * (i - 0.5)
        local bob = sin(clock * 4 + i * 0.9) * 0.35
        if env.monIcon then
          pcall(env.monIcon, pm.sp, cx - isz / 2, py + partyH - isz - 3.6 + bob, isz, floor(clock * 4 + i) % 2)
        end
        K.text(pm.levelText, cx - slot / 2, py + partyH - 3.2, 2.5, soft, "center", slot)
      end
    end
  end

  local function drawPage(pg, x, y, w, h, clock)
    if pg.kind == "front" then
      cardBase(x, y, w, h, clock, false)
      front(x, y, w, h, clock)
    elseif pg.kind == "badges" then
      cardBase(x, y, w, h, clock, true)
      badgesPage(x, y, w, h, clock, pg.set)
    else
      cardBase(x, y, w, h, clock, true)
      recordsPage(x, y, w, h, clock)
    end
  end

  -- the night behind: the tier's lights drifting, twinkles, a slow ring of rays
  local function night(b, clock)
    local x, y, w, h = b[1], b[2], b[3], b[4]
    K.grad(b, 0, K.mix(C.night, tier.foot, 0.25), C.nightFoot)
    K.glow(x + w * 0.5, y + h * 0.48, w * 0.62, h * 0.66, tier.glow, 0.24)
    K.glow(x + w * (0.2 + 0.05 * sin(clock * 0.3)), y + h * 0.85, w * 0.4, h * 0.5, tier.glow2, 0.16)
    K.glow(x + w * (0.82 + 0.04 * cos(clock * 0.23)), y + h * 0.15, w * 0.32, h * 0.4, tier.glow2, 0.1)
    for i = 1, NL do
      local yy = (LT.y[i] - clock * LT.v[i]) % 1.2 - 0.1
      local c = LT.hue[i] < 0.5 and tier.glow or tier.glow2
      K.glow(x + w * LT.x[i], y + h * yy, LT.s[i], LT.s[i], c, 0.05 * sin(max(0, min(1, yy)) * pi))
    end
    G.setBlendMode("add")
    Fx.rays(x + w / 2, y + h * 0.47, max(w, h) * 0.8, 14, clock * 0.04, tier.glow, 0.035, 0.05)
    G.setBlendMode("alpha")
    for i = 1, NT do
      local a = 0.25 + 0.6 * (0.5 + 0.5 * sin(clock * TW.sp[i] + TW.ph[i]))
      Fx.star(x + w * TW.x[i], y + h * TW.y[i], TW.s[i] * 0.7, C.white, a * 0.6, 0)
    end
  end

  -- ------- the flip in perspective: the page drawn into a canvas, laid on a strip that turns
  local flip = { canvas = nil, w = 0, h = 0, mesh = nil, failed = false }
  local function flipReady()
    if flip.failed or not (G.newCanvas and G.newMesh) then return false end
    local ww, wh = G.getDimensions()
    if not flip.canvas or flip.w ~= ww or flip.h ~= wh then
      if flip.canvas and flip.canvas.release then flip.canvas:release() end
      local ok, c = pcall(G.newCanvas, ww, wh)
      if not ok then flip.failed = true return false end
      flip.canvas, flip.w, flip.h = c, ww, wh
      if flip.mesh then flip.mesh:setTexture(c) end
    end
    if not flip.mesh then
      local ok, m = pcall(G.newMesh, (STRIPS + 1) * 2, "strip", "stream")
      if not ok then flip.failed = true return false end
      flip.mesh = m
      m:setTexture(flip.canvas)
    end
    return true
  end
  -- (theta: the turn, -pi/2 .. pi/2 (0 face on); the card's rect in units)
  local function drawTurned(pg, bx, by, cw, ch, clock, theta, fade)
    local prev = G.getCanvas()
    G.setCanvas(flip.canvas)
    G.clear(0, 0, 0, 0)
    K.setFade(1)
    drawPage(pg, bx, by, cw, ch, clock)
    G.setCanvas(prev)
    K.rescissor()
    local x0, y0, pw, ph = K.X(bx), K.Y(by), cw * K.sc, ch * K.sc
    local cx, cy = x0 + pw / 2, y0 + ph / 2
    local f = pw * 2.4
    local ct, s1 = cos(theta), sin(theta) * st.dir
    for i = 0, STRIPS do
      local u = i / STRIPS
      local off = (u - 0.5) * pw
      local z = off * s1
      local k = f / (f + z)
      local sx = cx + off * ct * k
      local hh = ph / 2 * k
      local lit = (1 - 0.55 * abs(sin(theta)) * (0.5 + 0.5 * max(-1, min(1, z / (pw * 0.5))))) * fade
      local tu, tv0, tv1 = (x0 + u * pw) / flip.w, y0 / flip.h, (y0 + ph) / flip.h
      flip.mesh:setVertex(i * 2 + 1, sx, cy - hh, tu, tv0, lit, lit, lit, fade)
      flip.mesh:setVertex(i * 2 + 2, sx, cy + hh, tu, tv1, lit, lit, lit, fade)
    end
    G.setColor(1, 1, 1, 1)
    G.setBlendMode("alpha", "premultiplied")
    G.draw(flip.mesh)
    G.setBlendMode("alpha")
  end

  function W.draw(body, clock, portraitScreen)
    G = K.graphics()
    K.themeHold(true)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    night(body, clock)
    -- (the card's size: as wide as fits a card's shape; upright, a tall card)
    local topBar, footBar = 15, 12
    tall = portraitScreen == true or h > w
    local cw, ch
    if tall then
      ch = min(h - topBar - footBar, (w - 12) * RATIO)
      cw = ch / RATIO
    else
      cw = min(w - 30, (h - topBar - footBar) * RATIO)
      ch = cw / RATIO
    end
    local cx, cy = x + w / 2, y + topBar + (h - topBar - footBar) / 2
    -- (coming in from below, settling; leaving the same way)
    local tin = ease((clock - t0) / IN)
    local tout = st.outAt and ease((clock - st.outAt) / OUT) or 0
    if st.outAt and clock - st.outAt >= OUT then
      K.themeHold(false)
      if ctx.done then ctx.done() end
      return
    end
    local float = sin(clock * 1.3) * 0.9
    local lift = (1 - K.outBack(max(0, min(1, (clock - t0) / IN)))) * h * 0.6 + tout * h * 0.5 + float
    local fade = tin * (1 - tout)
    local bx, by = cx - cw / 2, cy - ch / 2 + lift
    -- (turning: the page leaving, then the one coming, in perspective; a plain squeeze without a canvas)
    local fp = (clock - st.flipAt) / FLIP
    local pg = PAGES[st.page]
    if fp < 1 and st.from then
      local e = K.inOut(max(0, min(1, fp)))
      local theta = e < 0.5 and (e * pi) or ((e - 1) * pi)
      if e < 0.5 then pg = PAGES[st.from] end
      if flipReady() then
        drawTurned(pg, bx, by, cw, ch, clock, theta, fade)
      else
        K.setFade(fade)
        G.push()
        G.translate(K.X(cx), K.Y(cy + lift))
        G.scale(max(0.02, abs(cos(theta))), 1)
        G.translate(-K.X(cx), -K.Y(cy + lift))
        drawPage(pg, bx, by, cw, ch, clock)
        G.pop()
        K.rescissor()
      end
    else
      K.setFade(fade)
      drawPage(pg, bx, by, cw, ch, clock)
    end
    K.setFade(fade)
    K.addHit(K.R(bx, by, cw, ch), "win", A.CARD)
    -- (the arrows beside it)
    local ar = 5
    local function arrow(ax, dir, arg)
      local b = K.R(ax - ar, cy - ar, ar * 2, ar * 2)
      K.glass(b, ar, 0.16, C.white, 0.5, 0.5)
      K.chevron(ax + (dir > 0 and 0.4 or -0.4), cy, 2.4, C.white, dir, 0.9)
      K.addHit(b, "win", arg)
    end
    if not tall and w - cw > 26 then
      arrow(bx - 9, -1, A.PREV)
      arrow(bx + cw + 9, 1, A.NEXT)
    end
    -- (the close button)
    local cb = K.R(x + 4, y + 3.5, 9, 9)
    K.glass(cb, 4.5, 0.18, C.white, 0.5, 0.6)
    G.setLineWidth(max(1, 0.55 * K.sc))
    K.col(C.white, 0.95)
    G.line(K.X(x + 6.6), K.Y(y + 6.1), K.X(x + 10.4), K.Y(y + 9.9))
    G.line(K.X(x + 10.4), K.Y(y + 6.1), K.X(x + 6.6), K.Y(y + 9.9))
    K.addHit(cb, "win", A.CLOSE)
    -- (the dots under the card, the tier's name at the foot)
    local dw = 4.2
    local dx0 = x + w / 2 - (NP - 1) * dw / 2
    local dy = by + ch + 6
    for i = 1, NP do
      local on = i == st.page
      K.col(C.white, on and 0.95 or 0.32)
      K.box("fill", K.R(dx0 + (i - 1) * dw - (on and 1.6 or 0.9), dy - 0.9, on and 3.2 or 1.8, 1.8), 0.9)
      K.addHit(K.R(dx0 + (i - 1) * dw - 2, dy - 3, 4, 6), "win", A.DOT + i)
    end
    K.text(wd.tierName, x, y + h - 6, 2.8, tier.edge, "right", w - 4, 0.7)
    K.setFade(1)
    K.themeHold(false)
  end

  function W.close()
    if flip.canvas and flip.canvas.release then pcall(flip.canvas.release, flip.canvas) end
    if flip.mesh and flip.mesh.release then pcall(flip.mesh.release, flip.mesh) end
    flip.canvas, flip.mesh = nil, nil
    if card.release then pcall(card.release) end
  end

  return W
end
