-- The App Store: the apps that are the player's to keep or not (src/apps.lua's catalog: WoobOS's extras
-- and every app another mod registers), with a featured card, GET / OPEN and a page for each. What's
-- removed leaves the home screen and WoobPad; what it saved stays. The game's PC and PokéNav apps
-- aren't here: they can't be removed.
--   buttons  the D-pad the list, A an app's page, B close ; on a page: left / right, A, B back
--   touch    a row, its GET / OPEN, the featured card
-- The look is the Pokédex's glass: the groups are panes over a backdrop lit by the chosen app's colour,
-- the featured card and an app's page a pane of the app's own. Its motion (numbers in `mv`, nothing made
-- while it draws): the featured card settling in and its icon popping as the store opens, its words
-- sliding in after it, the groups settling in and their rows rising one after another, the highlight
-- gliding from the card to a row and between rows, the list scrolling smoothly, the backdrop turning to
-- the chosen app's colour, an app's page sliding in over the list (its icon popping, its words and its
-- buttons sliding in, its description's card after them), the ring and the bar filling as an app is got,
-- GET / OPEN popping as an app is got or removed, the question popping up over a dim.
--
--   window(ctx, env) -> win (src/apps.lua)   env.apps, env.appIcon(app, x, y, size)

local floor, max, min, pi, sin = math.floor, math.max, math.min, math.pi, math.sin

local M, GAP, ROW_H, HERO_H, HEAD_H, PILL_W, PILL_H = 3, 2, 18, 32, 8, 20, 8
local TOP_H, HEAD_PANE = 10, 38           -- a page's back row; its pane of the app's colour
local INSTALL = 0.9                       -- how long the ring fills (seconds)
local ROW, PILL, ACT, HERO, HERO_PILL, BACK, YES, NO, DIM = 1000, 2000, 3000, 4001, 4002, 4003, 4004, 4005, 4006
local WHITE, BLACK = { 255, 255, 255 }, { 0, 0, 0 }
local SHEEN_TOP, SHEEN_FOOT = { 255, 255, 255, 0.34 }, { 255, 255, 255, 0 }
local GROUP = { "store.woobApps", "store.modApps" }
local ACTS_ON, ACTS_OFF = { "open", "remove" }, { "get" }
local WORD = { open = "store.open", remove = "store.remove", get = "store.get" }
local HINTS = { { "+", "hint.choose" }, { "A", "store.hint.details" }, { "B", "hint.close" } }
local HINTS_PAGE = { { "+", "hint.choose" }, { "A", "hint.ok" }, { "B", "hint.back" } }
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env)
  local K, Apps, T = env.K, env.apps, env.T or NO_T
  local UI = K.UI
  local W = { title = T("app.store") }
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  -- pick: 0 the featured card, 1.. the rows ; page: the row whose page is open
  local st = { pick = 0, top = 0, follow = true, act = 1, rows = {}, byId = {}, cards = {}, contentH = 0, viewH = 0 }
  W.state = st

  local function nameOf(app) return app.labelKey and T(app.labelKey) or app.label end

  -- the rows, and where each sits in the scrolling list (made on change, read by the draw)
  local function build()
    local catalog = Apps.catalog(ctx)
    local rows, byId, cards = {}, {}, {}
    local y = M
    local hasHero = #catalog > 0
    if hasHero then y = y + HERO_H + GAP end
    for pass = 1, 2 do
      local card
      for _, app in ipairs(catalog) do
        if (pass == 2) == (app.fromMod == true) then
          if not card then
            card = { key = GROUP[pass], head = y, top = y + HEAD_H, h = 0 }
            cards[#cards + 1] = card
            y = card.top
          end
          local row = { app = app, id = app.id, name = nameOf(app), y = y, installed = Apps.isInstalled(app.id),
                        tag = app.taglineKey and T(app.taglineKey) or app.tagline or T("store.modTag"),
                        desc = app.descKey and T(app.descKey) or app.description or app.tagline or T("store.modDesc"),
                        by = app.by or T(pass == 1 and "store.byWoob" or "store.modApps") }
          rows[#rows + 1] = row
          byId[app.id] = row
          y = y + ROW_H
          card.h = card.h + ROW_H
        end
      end
      if card then y = y + GAP + 1 end
    end
    st.rows, st.byId, st.cards, st.contentH = rows, byId, cards, y + M
    -- (the featured app is chosen once, so it doesn't jump away as it's got)
    if not st.heroId and rows[1] then
      local first = rows[1]
      for _, row in ipairs(rows) do
        if not row.installed then first = row; break end
      end
      st.heroId = first.id
    end
    st.hero = st.heroId and byId[st.heroId] or rows[1]
    if st.page then st.page = byId[st.page.id] end
    st.pick = max(st.hero and 0 or 1, min(#rows, st.pick))
  end

  local function toast(text) st.toast = { text = text, t = now() } end
  local function changed()
    if ctx.refreshApps then ctx.refreshApps() end
    build()
  end
  -- (an app got or removed: its GET / OPEN pops)
  local function flipped(id) st.flipId, st.flipAt = id, now() end

  local function get(row)
    if st.job or row.installed then return end
    Apps.setInstalled(row.id, true)
    st.job = { id = row.id, name = row.name, t = now() }
    se("SE_SELECT")
    changed()
    st.act = 1
  end
  local function open(row)
    if st.job then return end
    if ctx.launchApp then ctx.launchApp(row.id) end
  end
  local function primary(row)
    if row.installed then open(row) else get(row) end
  end

  local function acts() return st.page.installed and ACTS_ON or ACTS_OFF end

  local function perform(id)
    local row = st.page
    if not (row and id) or st.job then return end
    if id == "get" then get(row)
    elseif id == "open" then open(row)
    elseif id == "remove" then
      se("SE_SELECT")
      st.confirm = { row = row, cursor = 2, title = T.f("store.removeTitle", row.name) }
    end
  end

  local function answer(yes)
    local c = st.confirm
    st.confirm = nil
    se("SE_SELECT")
    if not (c and yes) then return end
    Apps.setInstalled(c.row.id, false)
    changed()
    st.act = 1
    flipped(c.row.id)
    toast(T.f("store.removed", c.row.name))
  end

  local function showPage(row)
    if not row then return end
    st.page, st.act = row, 1
    se("SE_SELECT")
  end
  local function move(to)
    if to < (st.hero and 0 or 1) or to > #st.rows then return end
    st.pick, st.follow = to, true
    se("SE_SELECT")
  end

  function W.input(input, nav)
    local function pressed(k) return input:wasPressed(k) end
    if st.confirm then
      local c = st.confirm
      if pressed("b") then answer(false)
      elseif pressed("a") then answer(c.cursor == 1)
      elseif (nav.left and c.cursor == 2) or (nav.right and c.cursor == 1) then
        c.cursor = 3 - c.cursor
        se("SE_SELECT")
      end
      return true
    end
    if st.page then
      local list = acts()
      if pressed("b") then st.page = nil; se("SE_SELECT")
      elseif pressed("a") then perform(list[st.act])
      elseif nav.left and st.act > 1 then st.act = st.act - 1; se("SE_SELECT")
      elseif nav.right and st.act < #list then st.act = st.act + 1; se("SE_SELECT")
      end
      return true
    end
    if pressed("b") then return false end
    if pressed("a") then showPage(st.pick == 0 and st.hero or st.rows[st.pick])
    elseif nav.up then move(st.pick - 1)
    elseif nav.down then move(st.pick + 1)
    end
    return true
  end

  function W.tap(arg)
    if type(arg) ~= "number" then return end
    if st.confirm then
      if arg == YES then answer(true) elseif arg == NO or arg == DIM then answer(false) end
      return
    end
    if arg == BACK then st.page = nil; se("SE_SELECT")
    elseif arg == HERO then st.pick = 0; showPage(st.hero)
    elseif arg == HERO_PILL then if st.hero then primary(st.hero) end
    elseif arg > ACT then
      if not st.page then return end
      st.act = arg - ACT
      perform(acts()[arg - ACT])
    elseif arg > PILL then
      st.pick = arg - PILL
      if st.rows[st.pick] then primary(st.rows[st.pick]) end
    elseif arg > ROW then
      st.pick = arg - ROW
      showPage(st.rows[st.pick])
    end
  end

  function W.scroll(dy)
    if st.page or st.confirm then return end
    st.top = st.top - dy
    st.follow = false
  end

  function W.hints()
    return T.list((st.page or st.confirm) and HINTS_PAGE or HINTS)
  end

  -- ------- drawing (no tables, closures or strings made here)

  local G = nil
  local outCubic, outBack, approach, rise, settle, stagger = K.outCubic, K.outBack, K.approach, K.rise, K.settle,
    K.stagger
  -- the motion's numbers: when the store opened, the page opened (and whose), the question popped up;
  -- the highlight's place and height (list units), the eased scroll, the page's slide, the backdrop's colours
  local mv = { lastT = nil, openAt = nil, pageAt = -10, pageId = nil, pageRow = nil, push = 0, confirm = nil,
               confirmAt = -10, hy = nil, hh = HERO_H, top = 0, coloured = false,
               r = 0.5, g = 0.5, b = 0.5, r2 = 0.5, g2 = 0.5, b2 = 0.5 }
  W.motion = mv

  local function jobOf(row) return st.job and st.job.id == row.id and st.job or nil end
  -- (drawn `s` times its size round cx, cy (units) until G.pop: something popping in)
  local function pop(s, cx, cy)
    if s == 1 then return false end
    local px, py = K.X(cx), K.Y(cy)
    G.push()
    G.translate(px, py)
    G.scale(max(0.001, s))
    G.translate(-px, -py)
    return true
  end
  -- (how far the app's GET / OPEN is into its pop, or nil)
  local function flipOf(row, clock)
    if st.flipId ~= row.id or not st.flipAt then return nil end
    local t = (clock - st.flipAt) / 0.42
    if t < 0 or t >= 1 then return nil end
    return t
  end

  -- a pane of the app's colour (the featured card, a page's top): its shade, a sheen, a light drifting
  local function colourPane(app, b, rad, clock)
    K.shadow(b, rad, 1.4, 0.14)
    K.grad(b, rad, K.light(app.color, 0.14), K.dark(app.color, 0.2))
    K.grad(K.R(b[1], b[2], b[3], min(b[4], 16)), rad, SHEEN_TOP, SHEEN_FOOT)
    local rx = min(b[3] * 0.22, 34)
    K.glow(b[1] + b[3] - rx - 3 + sin(clock * 0.6) * 3, b[2] + b[4] * 0.45, rx, b[4] * 0.42, WHITE, 0.16)
    K.ring(b, rad, WHITE, 0.55, 0.4)
  end

  -- GET / OPEN, or the ring while it installs. onCard: on a colour (the pill white)
  local function pill(row, x, y, onCard, arg, clip, clock, live)
    local b = K.R(x, y, PILL_W, PILL_H)
    local job = jobOf(row)
    if job then
      local cx, cy, rad = K.X(x + PILL_W / 2), K.Y(y + PILL_H / 2), 3 * K.sc
      G.setLineWidth(max(1, 0.8 * K.sc))
      K.col(onCard and WHITE or UI.fillOn, onCard and 0.45 or 1)
      G.circle("line", cx, cy, rad)
      K.col(onCard and WHITE or UI.accent)
      G.arc("line", "open", cx, cy, rad, -pi / 2, -pi / 2 + 2 * pi * min(1, (clock - job.t) / INSTALL))
      return
    end
    local ft = flipOf(row, clock)
    local popped = ft and pop(0.55 + 0.45 * outBack(ft), x + PILL_W / 2, y + PILL_H / 2)
    if onCard then
      K.col(WHITE)
      K.box("fill", b, PILL_H / 2)
    else
      K.col(WHITE, 0.82)
      K.box("fill", b, PILL_H / 2)
      K.ring(b, PILL_H / 2, UI.accent, 0.22, 0.35)
    end
    local word = T(row.installed and "store.open" or "store.get")
    local fs = K.fit(word, 4, PILL_W - 3)
    K.bold(word, x, y + (PILL_H - fs * 1.2) / 2, fs, UI.accent, "center", PILL_W)
    if popped then G.pop() end
    if live then K.addHit(b, "win", arg, clip) end
  end

  -- the featured app: a pane of its colour, its icon popping up, its words sliding in after it
  local function drawHero(row, x, y, w, body, clock, live)
    local b = K.R(x, y, w, HERO_H)
    colourPane(row.app, b, 5, clock)
    if live then K.addHit(b, "win", HERO, body) end
    local t = clock - mv.openAt
    local popped = t < 0.5 and pop(0.6 + 0.4 * outBack(t / 0.5), x + 16, y + 16)
    env.appIcon(row.app, x + 5, y + 5, 22)
    if popped then G.pop() end
    local tx = x + 32
    local tw = w - 32 - PILL_W - 8
    local e1, e2, e3 = outCubic((t - 0.08) / 0.34), outCubic((t - 0.13) / 0.34), outCubic((t - 0.18) / 0.34)
    local fa = K.getFade()
    local eyebrow = T("store.featured")
    K.label(eyebrow, tx + (1 - e1) * 8, y + 4.5, K.fit(eyebrow, 3.6, tw), WHITE, nil, nil, 0.8 * e1 * fa)
    K.label(row.name, tx + (1 - e2) * 8, y + 10, K.fit(row.name, 7, tw), WHITE, nil, nil, e2 * fa)
    K.label(row.tag, tx + (1 - e3) * 8, y + 20, K.fit(row.tag, 4.2, tw), WHITE, nil, nil, 0.9 * e3 * fa)
    pill(row, x + w - PILL_W - 4, y + (HERO_H - PILL_H) / 2, true, HERO_PILL, body, clock, live)
  end

  local function drawRow(i, row, x, y, w, last, e, body, clock, live)
    local b = K.R(x, y, w, ROW_H)
    if live then K.addHit(b, "win", ROW + i, body) end
    local popped = e < 1 and pop(max(0, outBack(e)), x + 9.5, y + 9)
    env.appIcon(row.app, x + 2.5, y + 2, 14)
    if popped then G.pop() end
    local tx, tw = x + 20, w - 20 - PILL_W - 6
    local on = st.pick == i
    K.bold(row.name, tx, y + 3.2, K.fit(row.name, 5, tw), on and UI.accent or UI.label)
    K.text(row.tag, tx, y + 10.2, K.fit(row.tag, 3.8, tw), UI.secondary)
    pill(row, x + w - PILL_W - 3, y + (ROW_H - PILL_H) / 2, false, PILL + i, body, clock, live)
    if not last and not on and st.pick ~= i + 1 then K.hairline(tx, y + ROW_H - 0.2, w - 20) end
  end

  local function drawList(body, clock, dt, live)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    st.viewH = h
    local rows = st.rows
    if #rows == 0 then
      local words = T("store.empty")
      K.text(words, x, y + h / 2 - 3, K.fit(words, 4.8, w - 6), UI.secondary, "center", w)
      return
    end
    local most = max(0, st.contentH - h)
    if st.follow then
      st.follow = false
      if st.pick == 0 then
        st.top = 0
      else
        local ry = rows[st.pick].y
        if ry - HEAD_H < st.top then st.top = ry - HEAD_H
        elseif ry + ROW_H + M > st.top + h then st.top = ry + ROW_H + M - h end
      end
    end
    st.top = max(0, min(most, st.top))
    -- (the scroll and the highlight eased; snapped the first time)
    local pr = st.pick > 0 and rows[st.pick] or nil
    local ty, th = pr and pr.y or M, pr and ROW_H or HERO_H
    if mv.hy == nil then
      mv.hy, mv.hh, mv.top = ty, th, st.top
    else
      mv.hy, mv.hh = approach(mv.hy, ty, dt, 22), approach(mv.hh, th, dt, 22)
      mv.top = approach(mv.top, st.top, dt, 18)
    end
    local top = mv.top
    local cx, cw = x + M, w - M * 2 - (most > 0 and 2 or 0)
    local since = clock - mv.openAt
    if st.hero then
      local e = outCubic(since / 0.4)
      rise(e, 6)
      drawHero(st.hero, cx, y + M - top, cw, body, clock, live)
      settle(e)
    end
    for i = 1, #st.cards do
      local c = st.cards[i]
      local e = outCubic((since - 0.05 - i * 0.06) / 0.4)
      rise(e, 6)
      local words = T(c.key)
      K.bold(words, cx + 1, y + c.head + 1.6 - top, K.fit(words, 4.2, cw), UI.secondary)
      K.glass(K.R(cx, y + c.top - top, cw, c.h), 4)
      settle(e)
    end
    -- (the highlight: a ring round the featured card, an accent pane under a row, gliding between them)
    local k = (mv.hh - ROW_H) / (HERO_H - ROW_H)
    k = k < 0 and 0 or (k > 1 and 1 or k)
    local hb = K.R(cx - 0.6, y + mv.hy - top - 0.6, cw + 1.2, mv.hh + 1.2)
    local rad = 3 + 2 * k
    if k < 1 then
      K.col(UI.accent, 0.12 * (1 - k))
      K.box("fill", hb, rad)
      K.ring(hb, rad, UI.accent, 0.9 * (1 - k), 0.6)
    end
    if k > 0 then K.ring(hb, rad, WHITE, k * K.pulse(), 1) end
    for i = 1, #rows do
      local row = rows[i]
      local ry = y + row.y - top
      if ry + ROW_H > y and ry < y + h then
        local nextRow = rows[i + 1]
        local e = stagger(since - 0.1, i, 0.03, 0.3)
        rise(e, 4)
        drawRow(i, row, cx, ry, cw, not nextRow or nextRow.y ~= row.y + ROW_H, e, body, clock, live)
        settle(e)
      end
    end
    K.scrollbar(x + w - 2.2, y + 2, h - 4, top, h, st.contentH)
  end

  -- a page's button on the app's colour: GET / OPEN white with the accent's words, Remove glass
  local function pageButton(b, id, focused)
    local rad = b[4] / 2
    if id == "remove" then
      K.col(WHITE, 0.26)
      K.box("fill", b, rad)
      K.ring(b, rad, WHITE, 0.7, 0.35)
    else
      K.col(BLACK, 0.12)
      K.box("fill", K.R(b[1], b[2] + 0.5, b[3], b[4]), rad)
      K.col(WHITE)
      K.box("fill", b, rad)
    end
    if focused then K.ring(K.R(b[1] - 1.2, b[2] - 1.2, b[3] + 2.4, b[4] + 2.4), rad + 1.2, WHITE, K.pulse(), 0.9) end
    local label = T(WORD[id])
    local fs = K.fit(label, 4.6, b[3] - 3)
    if id == "remove" then K.label(label, b[1], b[2] + (b[4] - fs * 1.2) / 2, fs, WHITE, "center", b[3])
    else K.bold(label, b[1], b[2] + (b[4] - fs * 1.2) / 2, fs, UI.accent, "center", b[3]) end
  end

  -- (how many lines its description takes at w units: worked out once per width, kept on its row)
  local function descLines(row, w)
    local px = floor(w * K.sc + 0.5)
    if row.wrapPx ~= px then
      local ok, _, lines = pcall(K.font(4.4 * K.sc).getWrap, K.font(4.4 * K.sc), row.desc, w * K.sc)
      row.wrapPx, row.wrapN = px, ok and type(lines) == "table" and #lines or 3
    end
    return row.wrapN
  end

  -- an app's page: back, a pane of its colour (its icon popping, its name, who made it, its buttons or
  -- the bar while it's got), then what it does on glass
  local function drawPage(body, row, clock, live)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    local since = clock - mv.pageAt
    local back = T("store.back")
    local bw = K.width(back, 4.4) + 10
    local bb = K.R(x + M, y + 1.5, bw, 9)
    K.col(WHITE, 0.5)
    K.box("fill", bb, 4.5)
    K.ring(bb, 4.5, WHITE, 0.8, 0.3)
    K.chevron(bb[1] + 3.6, bb[2] + 4.5, 3.8, UI.accent, -1)
    K.text(back, bb[1] + 6.6, bb[2] + 2.1, 4.4, UI.accent)
    if live then K.addHit(K.R(x + M - 1, y, bw + 2, 12), "win", BACK) end
    local hy = y + TOP_H + 2
    local e1 = outCubic(since / 0.36)
    rise(e1, 6)
    local pb = K.R(x + M, hy, w - M * 2, HEAD_PANE)
    colourPane(row.app, pb, 5, clock)
    local px, py = x + M + 5, hy + 5
    local popped = since < 0.5 and pop(0.55 + 0.45 * outBack(since / 0.5), px + 14, py + 14)
    env.appIcon(row.app, px, py, 28)
    if popped then G.pop() end
    local tx, tw = px + 33, w - M * 2 - 5 - 33 - 5
    local fa = K.getFade()
    local e2, e3 = outCubic((since - 0.06) / 0.32), outCubic((since - 0.12) / 0.32)
    K.label(row.name, tx + (1 - e2) * 8, py, K.fit(row.name, 8, tw), WHITE, nil, nil, e2 * fa)
    K.label(row.by, tx + (1 - e2) * 8, py + 10, K.fit(row.by, 4.2, tw), WHITE, nil, nil, 0.85 * e2 * fa)
    local by = py + 18
    local job = jobOf(row)
    if job then
      local bw2 = min(tw, 60)
      local k = min(1, (clock - job.t) / INSTALL)
      K.col(WHITE, 0.3)
      K.box("fill", K.R(tx, by + 3, bw2, 4), 2)
      K.col(WHITE)
      K.box("fill", K.R(tx, by + 3, max(4, bw2 * outCubic(k)), 4), 2)
    else
      local list = row.installed and ACTS_ON or ACTS_OFF
      local ft = flipOf(row, clock)
      rise(e3, 0, 6)
      for i = 1, #list do
        local b = K.R(tx + (i - 1) * 42, by, 40, 10)
        local id = list[i]
        local bp = ft and pop(0.6 + 0.4 * outBack(ft - (i - 1) * 0.12), b[1] + 20, b[2] + 5)
        pageButton(b, id, live and st.act == i and not st.confirm)
        if bp then G.pop() end
        if live then K.addHit(b, "win", ACT + i) end
      end
      settle(e3)
    end
    settle(e1)
    -- (what it does, on glass, settling in after the pane)
    local e4 = outCubic((since - 0.1) / 0.4)
    rise(e4, 7)
    local cy = hy + HEAD_PANE + GAP + 1
    local cw = w - M * 2
    local cb = K.R(x + M, cy, cw, max(10, min(y + h - M - cy, 8 + descLines(row, cw - 10) * 4.4 * 1.2)))
    K.glass(cb, 5)
    K.text(row.desc, cb[1] + 5, cb[2] + 4, 4.4, UI.label, "left", cb[3] - 10)
    settle(e4)
  end

  -- the question: the dim, then the card popping up over it
  local function drawConfirm(body, clock)
    local c = st.confirm
    local x, y, w, h = body[1], body[2], body[3], body[4]
    local e = outCubic((clock - mv.confirmAt) / 0.22)
    K.dim(body, 0.3 * e)
    K.addHit(body, "win", DIM)
    local mw, mh = min(w - 16, 130), 40
    local mx, my = x + (w - mw) / 2, y + (h - mh) / 2
    local cb = K.R(mx, my, mw, mh)
    rise(e, 6)
    local popped = e < 1 and pop(0.92 + 0.08 * outBack((clock - mv.confirmAt) / 0.26), mx + mw / 2, my + mh / 2)
    K.shadow(cb, 6, 1.8, 0.28)
    K.glass(cb, 6, 0.9)
    K.addHit(cb, "win", -1)
    K.bold(c.title, mx + 4, my + 5, K.fit(c.title, 5.4, mw - 8), UI.label, "center", mw - 8)
    K.text(T("store.removeNote"), mx + 5, my + 13, 3.9, UI.secondary, "center", mw - 10)
    local bw, by = (mw - 8 - GAP) / 2, my + mh - 14
    for i = 1, 2 do
      local bb = K.R(mx + 4 + (i - 1) * (bw + GAP), by, bw, 10.5)
      K.button(bb, T(i == 1 and "store.remove" or "button.cancel"), i == 1 and "danger" or "gray", c.cursor == i, 4.6)
      K.addHit(bb, "win", i == 1 and YES or NO)
    end
    if popped then G.pop() end
    settle(e)
  end

  function W.draw(body, clock)
    G = K.graphics()
    local w = body[3]
    local dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT = clock
    if not mv.openAt then mv.openAt, mv.push = clock, st.page and 1 or 0 end
    local job = st.job
    if job and clock - job.t >= INSTALL then
      st.job = nil
      se("SE_SUCCESS")
      flipped(job.id)
      toast(T.f("store.added", job.name))
    end
    -- (a page opened: its motion starts; the one sliding away kept to draw)
    if st.page then
      if st.page.id ~= mv.pageId then mv.pageId, mv.pageAt = st.page.id, clock end
      mv.pageRow = st.page
    else
      mv.pageId = nil
    end
    if st.confirm ~= mv.confirm then
      if st.confirm then mv.confirmAt = clock end
      mv.confirm = st.confirm
    end
    -- (the backdrop's lights: the chosen app's colour and a paler one, eased; snapped the first time)
    local shown = st.page or mv.pageRow
    if not (st.page or mv.push > 0.001) then shown = st.pick > 0 and st.rows[st.pick] or st.hero end
    if shown then
      local c = shown.app.color
      local rate = mv.coloured and 7 or 1000
      mv.coloured = true
      mv.r, mv.g, mv.b = approach(mv.r, c[1] / 255, dt, rate), approach(mv.g, c[2] / 255, dt, rate),
        approach(mv.b, c[3] / 255, dt, rate)
      mv.r2 = approach(mv.r2, (c[1] + (255 - c[1]) * 0.45) / 255, dt, rate)
      mv.g2 = approach(mv.g2, (c[2] + (255 - c[2]) * 0.45) / 255, dt, rate)
      mv.b2 = approach(mv.b2, (c[3] + (255 - c[3]) * 0.45) / 255, dt, rate)
    end
    K.backdrop(body, clock, mv.r, mv.g, mv.b, mv.r2, mv.g2, mv.b2)
    -- (a page slides in over the list, the list easing back under it)
    mv.push = approach(mv.push, st.page and 1 or 0, dt, 14)
    local p = outCubic(mv.push)
    if p < 0.999 then
      local sh = p > 0.001
      if sh then
        G.push()
        G.translate(-w * 0.3 * p * K.sc, 0)
      end
      drawList(body, clock, dt, st.page == nil)
      if sh then
        G.pop()
        K.col(BLACK, 0.12 * p)
        K.box("fill", body)
      end
    end
    if p > 0.001 and mv.pageRow then
      local sh = p < 0.999
      if sh then
        G.push()
        G.translate(w * (1 - p) * K.sc, 0)
        K.shadow(body, 0, 0, 0.2)
      end
      K.backdrop(body, clock, mv.r, mv.g, mv.b, mv.r2, mv.g2, mv.b2)
      drawPage(body, mv.pageRow, clock, st.page ~= nil)
      if sh then G.pop() end
    end
    K.scissor(body)
    if st.confirm then drawConfirm(body, clock) end
    if st.toast and not K.toast(st.toast, clock, body, UI.red, UI.green, UI.hud) then st.toast = nil end
  end

  build()
  return W
end
