-- The App Store: the apps that are the player's to keep or not (src/apps.lua's catalog: WoobOS's extras
-- and every app another mod registers), with a featured card, GET / OPEN and a page for each. What's
-- removed leaves the home screen and WoobPad; what it saved stays. The game's PC and PokéNav apps
-- aren't here: they can't be removed.
--   buttons  the D-pad the list, A an app's page, B close ; on a page: left / right, A, B back
--   touch    a row, its GET / OPEN, the featured card
--
--   window(ctx, env) -> win (src/apps.lua)   env.apps, env.appIcon(app, x, y, size)

local floor, max, min, pi = math.floor, math.max, math.min, math.pi

local M, GAP, ROW_H, HERO_H, HEAD_H, PILL_W, PILL_H = 3, 2, 18, 32, 8, 20, 8
local INSTALL = 0.9                       -- how long the ring fills (seconds)
local ROW, PILL, ACT, HERO, HERO_PILL, BACK, YES, NO, DIM = 1000, 2000, 3000, 4001, 4002, 4003, 4004, 4005, 4006
local WHITE = { 255, 255, 255 }
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

  -- ------- drawing (no tables made here)

  local function jobOf(row) return st.job and st.job.id == row.id and st.job or nil end

  -- GET / OPEN, or the ring while it installs. onCard: on a colour (the pill white)
  local function pill(row, x, y, onCard, arg, clip, clock)
    local b = K.R(x, y, PILL_W, PILL_H)
    local job = jobOf(row)
    if job then
      local g, cx, cy, rad = K.graphics(), K.X(x + PILL_W / 2), K.Y(y + PILL_H / 2), 3 * K.sc
      g.setLineWidth(max(1, 0.8 * K.sc))
      K.col(onCard and WHITE or UI.fillOn, onCard and 0.45 or 1)
      g.circle("line", cx, cy, rad)
      K.col(onCard and WHITE or UI.accent)
      g.arc("line", "open", cx, cy, rad, -pi / 2, -pi / 2 + 2 * pi * min(1, (clock - job.t) / INSTALL))
      return
    end
    K.col(onCard and WHITE or UI.fillOn)
    K.box("fill", b, PILL_H / 2)
    local word = T(row.installed and "store.open" or "store.get")
    local fs = K.fit(word, 4, PILL_W - 3)
    K.bold(word, x, y + (PILL_H - fs * 1.2) / 2, fs, UI.accent, "center", PILL_W)
    K.addHit(b, "win", arg, clip)
  end

  local function drawHero(row, x, y, w, on, body, clock)
    local b = K.R(x, y, w, HERO_H)
    K.grad(b, 5, K.light(row.app.color, 0.14), K.dark(row.app.color, 0.2))
    K.addHit(b, "win", HERO, body)
    if on then K.ring(b, 5, WHITE, K.pulse(), 1) end
    env.appIcon(row.app, x + 5, y + 5, 22)
    local tx = x + 32
    local tw = w - 32 - PILL_W - 8
    local eyebrow = T("store.featured")
    K.text(eyebrow, tx, y + 4.5, K.fit(eyebrow, 3.6, tw), WHITE, nil, nil, 0.8)
    K.bold(row.name, tx, y + 10, K.fit(row.name, 7, tw), WHITE)
    K.text(row.tag, tx, y + 20, K.fit(row.tag, 4.2, tw), WHITE, nil, nil, 0.9)
    pill(row, x + w - PILL_W - 4, y + (HERO_H - PILL_H) / 2, true, HERO_PILL, body, clock)
  end

  local function drawRow(i, row, x, y, w, on, last, body, clock)
    local b = K.R(x, y, w, ROW_H)
    if on then K.selection(b, true, 3) end
    K.addHit(b, "win", ROW + i, body)
    env.appIcon(row.app, x + 2.5, y + 2, 14)
    local tx, tw = x + 20, w - 20 - PILL_W - 6
    K.bold(row.name, tx, y + 3.2, K.fit(row.name, 5, tw), on and WHITE or UI.label)
    K.text(row.tag, tx, y + 10.2, K.fit(row.tag, 3.8, tw), on and WHITE or UI.secondary)
    pill(row, x + w - PILL_W - 3, y + (ROW_H - PILL_H) / 2, on, PILL + i, body, clock)
    if not last and not on then K.hairline(tx, y + ROW_H - 0.2, w - 20) end
  end

  local function drawList(body, clock)
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
    local cx, cw = x + M, w - M * 2 - (most > 0 and 2 or 0)
    if st.hero then drawHero(st.hero, cx, y + M - st.top, cw, st.pick == 0, body, clock) end
    for i = 1, #st.cards do
      local c = st.cards[i]
      local words = T(c.key)
      K.bold(words, cx + 1, y + c.head + 1.6 - st.top, K.fit(words, 4.2, cw), UI.secondary)
      K.card(K.R(cx, y + c.top - st.top, cw, c.h), 4)
    end
    for i = 1, #rows do
      local row = rows[i]
      local ry = y + row.y - st.top
      if ry + ROW_H > y and ry < y + h then
        local nextRow = rows[i + 1]
        drawRow(i, row, cx, ry, cw, st.pick == i, not nextRow or nextRow.y ~= row.y + ROW_H, body, clock)
      end
    end
    K.scrollbar(x + w - 2.2, y + 2, h - 4, st.top, h, st.contentH)
  end

  -- an app's page: its icon, name, buttons and what it does
  local function drawPage(body, clock)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    local row = st.page
    local back = T("store.back")
    K.chevron(x + M + 2, y + 6.2, 5, UI.accent, -1)
    K.text(back, x + M + 5.5, y + 3.6, 4.8, UI.accent)
    K.addHit(K.R(x + M - 1, y + 1, K.width(back, 4.8) + 10, 10), "win", BACK)
    local cardY = y + 12
    K.card(K.R(x + M, cardY, w - M * 2, y + h - M - cardY), 5)
    local px, py = x + M + 5, cardY + 5
    env.appIcon(row.app, px, py, 28)
    local tx, tw = px + 33, w - M * 2 - 5 - 33 - 5
    K.bold(row.name, tx, py, K.fit(row.name, 8, tw), UI.label)
    K.text(row.by, tx, py + 10, K.fit(row.by, 4.2, tw), UI.secondary)
    local by = py + 18
    local job = jobOf(row)
    if job then
      local bw = min(tw, 60)
      K.col(UI.fill)
      K.box("fill", K.R(tx, by + 3, bw, 4), 2)
      K.col(UI.accent)
      K.box("fill", K.R(tx, by + 3, max(4, bw * min(1, (clock - job.t) / INSTALL)), 4), 2)
    else
      local list = acts()
      for i = 1, #list do
        local b = K.R(tx + (i - 1) * 42, by, 40, 10)
        local id = list[i]
        K.button(b, T(WORD[id]), id == "remove" and "gray" or "accent", st.act == i and not st.confirm, 4.6)
        K.addHit(b, "win", ACT + i)
      end
    end
    K.hairline(px, py + 32, w - M * 2 - 10)
    K.text(row.desc, px, py + 36, 4.4, UI.secondary, "left", w - M * 2 - 10)
  end

  local function drawConfirm(body, clock)
    local c = st.confirm
    local x, y, w, h = body[1], body[2], body[3], body[4]
    K.dim(body, 0.35)
    K.addHit(body, "win", DIM)
    local mw, mh = min(w - 16, 130), 40
    local mx, my = x + (w - mw) / 2, y + (h - mh) / 2
    K.sheet(K.R(mx, my, mw, mh), 6)
    K.bold(c.title, mx + 4, my + 5, K.fit(c.title, 5.4, mw - 8), UI.label, "center", mw - 8)
    K.text(T("store.removeNote"), mx + 5, my + 13, 3.9, UI.secondary, "center", mw - 10)
    local bw, by = (mw - 8 - GAP) / 2, my + mh - 14
    for i = 1, 2 do
      local bb = K.R(mx + 4 + (i - 1) * (bw + GAP), by, bw, 10.5)
      K.button(bb, T(i == 1 and "store.remove" or "button.cancel"), i == 1 and "danger" or "gray", c.cursor == i, 4.6)
      K.addHit(bb, "win", i == 1 and YES or NO)
    end
  end

  function W.draw(body, clock)
    local job = st.job
    if job and clock - job.t >= INSTALL then
      st.job = nil
      se("SE_SUCCESS")
      toast(T.f("store.added", job.name))
    end
    if st.page then drawPage(body, clock) else drawList(body, clock) end
    if st.confirm then drawConfirm(body, clock) end
    if st.toast and not K.toast(st.toast, clock, body, UI.red, UI.green, UI.hud) then st.toast = nil end
  end

  build()
  return W
end
