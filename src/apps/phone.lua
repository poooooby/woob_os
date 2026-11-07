-- The Phone app: the PokéNav's contacts as a phone (src/phone.lua). Three tabs: Favourites, Recents
-- (the calls made and the field's calls, newest first) and Contacts (a Rematch filter: who's ready
-- for a rematch). A contact's card: their picture, class and place, a "wants a rematch" or "nearby"
-- pill, Call and ★; the check page's lines (Emerald) or Trainer's Eyes' profile (Ruby / Sapphire,
-- no calls). A call: the calling screen, then the game's own words in a bubble, a page at a time.
--   buttons  L / R the tab, Up / Down the row, A open (a card: Left / Right Call or ★, A press),
--            SELECT the Rematch filter (Contacts), B back
--   touch    the tabs, a row, the card's buttons, End; drag (or the wheel) scrolls
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, abs, sin, pi = math.floor, math.max, math.min, math.abs, math.sin, math.pi

local ROW_H, M = 15, 3
local TAB_FAV, TAB_REC, TAB_CON, FILTER, CALL, FAV, END, NEXT = 2001, 2002, 2003, 2004, 2010, 2011, 2012, 2013
local DIAL = 0.9    -- seconds of "Calling ..."
local HINTS = {
  list = { { "L R", "phone.hint.tab" }, { "A", "hint.choose" }, { "B", "hint.back" } },
  contacts = { { "L R", "phone.hint.tab" }, { "A", "hint.choose" }, { "SELECT", "phone.rematch" }, { "B", "hint.back" } },
  card = { { "< >", "phone.hint.button" }, { "A", "hint.choose" }, { "B", "hint.back" } },
  call = { { "A", "phone.hint.next" }, { "B", "phone.end" } },
}
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env)
  local K, Ph, T = env.K, env.phone, env.T or NO_T
  local UI = K.UI
  local W = { title = T("app.phone") }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local st = {
    tab = 3, view = "list", cursor = 1, top = 0, visible = 6, rematchOnly = false, contacts = {}, rows = {},
    button = 1, call = nil, pages = nil, page = 1, pagesW = 0, toast = nil, agoAt = -10,
  }
  W.state = st

  local agoText = K.textCache(function(m)
    if m < 1 then return T("notify.now") end
    if m < 60 then return T.f("notify.minutes", m) end
    if m < 1440 then return T.f("notify.hours", floor(m / 60)) end
    return T.f("notify.days", floor(m / 1440))
  end)

  -- the rows of the tab showing (made after a change, never in a draw)
  local function refresh()
    local s = session()
    st.contacts = Ph.contacts(s)
    local byKey = {}
    for _, c in ipairs(st.contacts) do byKey[c.key] = c end
    st.byKey = byKey
    local rows = {}
    if st.tab == 1 then
      for _, c in ipairs(st.contacts) do if Ph.isFav(s, c.key) then rows[#rows + 1] = { contact = c } end end
    elseif st.tab == 2 then
      for _, r in ipairs(Ph.recents(s)) do
        rows[#rows + 1] = { recent = r, contact = r.key and byKey[r.key] or nil }
      end
    else
      for _, c in ipairs(st.contacts) do
        if not st.rematchOnly or c.rematch then rows[#rows + 1] = { contact = c } end
      end
    end
    st.rows = rows
    st.cursor = max(1, min(st.cursor, #rows))
    st.agoAt = -10
  end
  W.refresh = refresh

  local function clamp()
    st.cursor = max(1, min(st.cursor, #st.rows))
    if st.cursor > st.top + st.visible then st.top = st.cursor - st.visible end
    if st.cursor <= st.top then st.top = st.cursor - 1 end
    st.top = max(0, min(st.top, max(0, #st.rows - st.visible)))
  end
  local function row() return st.rows[st.cursor] end
  local function setTab(t)
    t = (t - 1) % 3 + 1
    if t == st.tab then return end
    st.tab, st.cursor, st.top, st.view = t, 1, 0, "list"
    refresh()
    se("SE_SELECT")
  end
  local function toast(key, bad)
    st.toast = { text = T(key), bad = bad ~= false, t = now() }
  end

  local function openRow()
    local r = row()
    if not r then return end
    st.button = 1
    if r.contact then
      st.view = "card"
    elseif r.recent then
      -- (a field call from someone no longer listed: its words again)
      st.call = { contact = nil, recent = r.recent, text = r.recent.text, t0 = now() - DIAL, name = r.recent.name,
                  pic = r.recent.pic }
      st.pages, st.page, st.view = nil, 1, "call"
    end
    se("SE_SELECT")
  end

  local function call()
    local r = row()
    local c = r and r.contact
    if not c then return end
    if not c.canCall then
      se("SE_FAILURE")
      return toast("phone.noCalls")
    end
    local text, ok = Ph.call(session(), c)
    if not ok then
      se("SE_FAILURE")
      return toast("phone.failed")
    end
    se("SE_POKENAV_CALL")
    st.call = { contact = c, text = text, t0 = now(), name = c.name, pic = c.pic }
    st.pages, st.page, st.view = nil, 1, "call"
    refresh()
  end
  local function fav()
    local r = row()
    local c = r and r.contact
    if not c then return end
    local on = Ph.toggleFav(session(), c.key)
    se("SE_SELECT")
    toast(on and "phone.favOn" or "phone.favOff", false)
    if st.tab == 1 then refresh() end
  end
  local function endCall()
    if not st.call then return end
    se("SE_POKENAV_HANG_UP")
    st.view = st.call.contact and "card" or "list"
    st.call, st.pages = nil, nil
  end
  local function nextPage()
    if not st.call then return end
    if now() - st.call.t0 < DIAL then return end
    if st.pages and st.page < #st.pages then
      st.page = st.page + 1
      se("SE_SELECT")
    else
      endCall()
    end
  end

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  function W.input(input, nav)
    cur = input
    if st.view == "call" then
      if pressed("a") then nextPage() elseif pressed("b") then endCall() end
      return true
    end
    if st.view == "card" then
      if pressed("b") then
        st.view = "list"
        se("SE_SELECT")
      elseif nav.left or nav.right then
        st.button = st.button == 1 and 2 or 1
        se("SE_SELECT")
      elseif pressed("a") then
        if st.button == 1 then call() else fav() end
      end
      return true
    end
    if pressed("b") then return false end
    if nav.up then st.cursor = st.cursor - 1; clamp(); se("SE_SELECT")
    elseif nav.down then st.cursor = st.cursor + 1; clamp(); se("SE_SELECT")
    elseif pressed("l") then setTab(st.tab - 1)
    elseif pressed("r") then setTab(st.tab + 1)
    elseif pressed("select") and st.tab == 3 then
      st.rematchOnly = not st.rematchOnly
      refresh()
      se("SE_SELECT")
    elseif pressed("a") then openRow()
    end
    return true
  end

  function W.tap(arg)
    if arg == TAB_FAV then return setTab(1) end
    if arg == TAB_REC then return setTab(2) end
    if arg == TAB_CON then return setTab(3) end
    if arg == FILTER then
      st.rematchOnly = not st.rematchOnly
      refresh()
      return se("SE_SELECT")
    end
    if arg == CALL then return call() end
    if arg == FAV then return fav() end
    if arg == END then return endCall() end
    if arg == NEXT then return nextPage() end
    if type(arg) == "number" and st.rows[arg] then
      if st.cursor == arg and st.view ~= "list" then return end
      st.cursor = arg
      clamp()
      openRow()
    end
  end

  function W.scroll(dy)
    if st.view ~= "list" and not st.wide then return end
    st.top = max(0, min(max(0, #st.rows - st.visible), st.top - dy / ROW_H))
  end

  function W.hints()
    if st.view == "call" then return T.list(HINTS.call) end
    if st.view == "card" then return T.list(HINTS.card) end
    return T.list(st.tab == 3 and HINTS.contacts or HINTS.list)
  end

  -- ------- drawing (no tables made here)

  local GREEN, AMBER, STAR = { 52, 199, 89 }, { 255, 159, 10 }, { 255, 204, 0 }
  local CALL_TOP, CALL_FOOT = { 34, 52, 64 }, { 12, 16, 22 }
  local WHITE, SOFT = { 255, 255, 255 }, { 255, 255, 255, 0.7 }
  local TILE = { 228, 230, 238 }

  -- the trainer's picture in a rounded tile (units); someone without one (Mom, the Professor): their
  -- initial on a tint of their own
  local initialOf = setmetatable({}, { __mode = "k" })
  local INITIAL = { { 120, 160, 230 }, { 230, 140, 110 }, { 120, 190, 140 }, { 190, 130, 210 }, { 220, 180, 90 } }
  local function picture(pic, x, y, size, ring, name)
    local G = K.graphics()
    local img = Ph.picture(pic)
    if not img and name then
      local key = name
      local c = INITIAL[(#key % #INITIAL) + 1]
      K.col(c)
      K.box("fill", K.R(x, y, size, size), size * 0.28)
      K.bold(key:sub(1, 1), x, y + size * 0.2, size * 0.55, WHITE, "center", size)
      if ring then K.ring(K.R(x, y, size, size), size * 0.28, ring, 0.9, 0.6) end
      return
    end
    K.col(TILE)
    K.box("fill", K.R(x, y, size, size), size * 0.28)
    if img then
      local iw, ih = img:getDimensions()
      local s = size * K.sc / max(iw, ih) * 1.05
      G.setColor(1, 1, 1, 1)
      K.scissor(K.R(x, y, size, size))
      G.draw(img, K.X(x + size / 2), K.Y(y + size / 2), 0, s, s, iw / 2, ih / 2)
      K.scissor(st.clip)
    end
    if ring then K.ring(K.R(x, y, size, size), size * 0.28, ring, 0.9, 0.6) end
  end

  -- a small star
  local function star(cx, cy, r, c)
    local G = K.graphics()
    K.col(c)
    local x, y, s = K.X(cx), K.Y(cy), r * K.sc
    G.polygon("fill", x, y - s, x + s * 0.3, y - s * 0.3, x + s, y - s * 0.25, x + s * 0.45, y + s * 0.2,
      x + s * 0.6, y + s, x, y + s * 0.5, x - s * 0.6, y + s, x - s * 0.45, y + s * 0.2, x - s, y - s * 0.25,
      x - s * 0.3, y - s * 0.3)
  end

  local function drawRows(x, y, w, h, focused)
    st.visible = max(1, floor(h / ROW_H))
    clamp()
    local s = session()
    local t = os.time()
    local refreshAgo = now() - st.agoAt >= 1
    if refreshAgo then st.agoAt = now() end
    if #st.rows == 0 then
      local key = st.tab == 1 and "phone.noFav" or (st.tab == 2 and "phone.noRecent" or "phone.noContacts")
      K.text(T(key), x, y + h / 2 - 4, 4.6, UI.secondary, "center", w)
      return
    end
    K.card(K.R(x, y, w, min(h, (#st.rows - st.top) * ROW_H)), 4)
    for i = st.top + 1, min(#st.rows, st.top + st.visible) do
      local r = st.rows[i]
      local ry = y + (i - st.top - 1) * ROW_H
      local rb = K.R(x, ry, w, ROW_H)
      local on = i == st.cursor
      if on then K.selection(K.R(x + 1, ry + 0.5, w - 2, ROW_H - 1), focused, 3) end
      local ink = (on and focused) and WHITE or UI.label
      local soft = (on and focused) and SOFT or UI.secondary
      local c = r.contact
      local name = c and c.name or (r.recent and r.recent.name) or "?"
      picture(c and c.pic or (r.recent and r.recent.pic), x + 2.5, ry + 2, 11, nil, name)
      local tx = x + 16
      local nw = w - 16 - 14
      K.bold(name, tx, ry + 2.2, K.fit(name, 5, nw), ink)
      local sub
      if r.recent then
        if refreshAgo or not r.ago then r.ago = agoText(max(0, floor((t - (r.recent.at or t)) / 60))) end
        sub = r.ago
        -- (in or out: a little arrow)
        local G = K.graphics()
        K.col(r.recent.incoming and GREEN or UI.accent)
        local ax, ay = K.X(tx + 1.5), K.Y(ry + 10.2)
        local u = 1.4 * K.sc
        if r.recent.incoming then G.polygon("fill", ax - u, ay - u, ax + u, ay + u, ax - u, ay + u)
        else G.polygon("fill", ax + u, ay + u, ax - u, ay - u, ax + u, ay - u) end
        K.text(sub, tx + 4, ry + 8.3, 4, soft)
      else
        sub = c.place ~= "" and c.place or c.desc
        K.text(sub, tx, ry + 8.3, K.fit(sub, 4, nw), soft)
      end
      if c and c.rematch then
        K.col(GREEN)
        K.box("fill", K.R(x + w - 8, ry + ROW_H / 2 - 1.6, 3.2, 3.2), 1.6)
      end
      if c and Ph.isFav(s, c.key) then star(x + w - 12.5, ry + ROW_H / 2, 1.8, STAR) end
      if i > st.top + 1 and not on and i - 1 ~= st.cursor then K.hairline(tx, ry, w - 16) end
      K.addHit(rb, "win", i)
    end
    K.scrollbar(x + w, y, h, st.top, st.visible, #st.rows)
  end

  -- a capsule with words
  local function pill(x, y, words, fill, ink, size)
    size = size or 4
    local w = K.width(words, size) + 5
    K.col(fill)
    K.box("fill", K.R(x, y, w, size + 3), (size + 3) / 2)
    K.text(words, x + 2.5, y + 1.4, size, ink)
    return x + w + 2
  end
  local GREEN_SOFT, AMBER_SOFT = { 52, 199, 89, 0.16 }, { 255, 159, 10, 0.16 }

  local function drawCard(x, y, w, h)
    local r = row()
    local c = r and r.contact
    if not c then return end
    local b = K.R(x, y, w, h)
    K.card(b, 5)
    local ps = min(36, w * 0.34, h * 0.4)
    picture(c.pic, x + 4, y + 4, ps, UI.separator, c.name)
    local tx = x + ps + 8
    local nw = w - ps - 12
    K.bold(c.name, tx, y + 5, K.fit(c.name, 7, nw), UI.label)
    K.text(c.desc, tx, y + 14, K.fit(c.desc, 4.4, nw), UI.secondary)
    if c.place ~= "" then K.text(c.place, tx, y + 20, K.fit(c.place, 4.4, nw), UI.tertiary) end
    local py = y + 27
    local px = tx
    if c.rematch then px = pill(px, py, T("phone.wantsRematch"), GREEN_SOFT, GREEN) end
    if c.nearby then pill(px, py, T("phone.nearby"), AMBER_SOFT, AMBER) end
    -- (Call and ★)
    local by = y + max(ps + 8, 36)
    local bw = (w - 12) / 2
    local cb, fb = K.R(x + 4, by, bw, 11), K.R(x + 8 + bw, by, bw, 11)
    if c.canCall then
      K.col(GREEN)
      K.box("fill", cb, 5.5)
      K.bold(T("phone.call"), cb[1], cb[2] + 2.8, 4.8, WHITE, "center", cb[3])
    else
      K.col(UI.fill)
      K.box("fill", cb, 5.5)
      K.text(T("phone.call"), cb[1], cb[2] + 2.8, 4.8, UI.tertiary, "center", cb[3])
    end
    if st.button == 1 then K.focusRing(cb, 5.5) end
    local on = Ph.isFav(session(), c.key)
    K.col(UI.fill)
    K.box("fill", fb, 5.5)
    star(fb[1] + 7, fb[2] + 5.5, 2.4, on and STAR or UI.tertiary)
    K.text(T(on and "phone.favourite" or "phone.addFav"), fb[1] + 11, fb[2] + 2.8, K.fit(T("phone.addFav"), 4.6, bw - 13),
      UI.label)
    if st.button == 2 then K.focusRing(fb, 5.5) end
    K.addHit(cb, "win", CALL)
    K.addHit(fb, "win", FAV)
    -- (the check page / the profile)
    local ly = by + 15
    for i, line in ipairs(c.check) do
      if ly + 5 > y + h - 2 then break end
      local head = c.headings and c.headings[i]
      K.text(line, x + 5, ly, K.fit(line, head and 4.2 or 4.4, w - 10), head and UI.accent or UI.label)
      ly = ly + (head and 5.6 or 6.4)
    end
  end

  -- the call's words in pages of whole lines (made when the width changes, not every frame)
  local function paginate(text, w, size, lines)
    local pages, page, n, line = {}, {}, 0, ""
    local function push()
      n = n + 1
      page[#page + 1] = line
      line = ""
      if n >= lines then
        pages[#pages + 1] = table.concat(page, "\n")
        page, n = {}, 0
      end
    end
    for para in (text .. "\n"):gmatch("([^\n]*)\n") do
      for word in para:gmatch("%S+") do
        local try = line == "" and word or (line .. " " .. word)
        if K.width(try, size) > w and line ~= "" then
          push()
          line = word
        else
          line = try
        end
      end
      if line ~= "" then push() end
    end
    if #page > 0 then pages[#pages + 1] = table.concat(page, "\n") end
    if #pages == 0 then pages[1] = "" end
    return pages
  end

  local function drawCall(x, y, w, h, clock)
    local cl = st.call
    if not cl then return end
    local G = K.graphics()
    K.grad(K.R(x, y, w, h), 0, CALL_TOP, CALL_FOOT)
    local ps = min(30, h * 0.26)
    local cx = x + w / 2
    -- (the picture in a ring, pulsing while it rings)
    local dialing = now() - cl.t0 < DIAL
    if dialing then
      local p = (clock * 1.6) % 1
      K.col(GREEN, 0.5 * (1 - p))
      G.circle("line", K.X(cx), K.Y(y + 6 + ps / 2), (ps / 2 + 2 + p * 6) * K.sc)
    end
    picture(cl.pic, cx - ps / 2, y + 6, ps, WHITE, cl.name)
    K.bold(cl.name, x, y + 9 + ps, 6, WHITE, "center", w)
    if dialing then
      local dots = floor((now() - cl.t0) * 4) % 4
      K.text(T("phone.calling"), x, y + 17 + ps, 4.4, SOFT, "center", w)
      for i = 1, dots do
        K.col(SOFT)
        G.circle("fill", K.X(cx + K.width(T("phone.calling"), 4.4) / 2 + i * 2), K.Y(y + 21 + ps), 0.5 * K.sc)
      end
    else
      -- (the words in a bubble, a page at a time)
      local by = y + 18 + ps
      local bh = y + h - 16 - by
      local bw = w - 12
      local size = 4.6
      local lines = max(1, floor((bh - 6) / (size * 1.3)))
      if not st.pages or st.pagesW ~= floor(bw) or st.pagesL ~= lines then
        st.pages, st.pagesW, st.pagesL = paginate(cl.text or "", bw - 8, size, lines), floor(bw), lines
        st.page = min(st.page, #st.pages)
      end
      local bb = K.R(x + 6, by, bw, bh)
      K.col(WHITE, 0.94)
      K.box("fill", bb, 5)
      G.polygon("fill", K.X(cx - 3), K.Y(by), K.X(cx + 3), K.Y(by), K.X(cx), K.Y(by - 2.5))
      K.text(st.pages[st.page], bb[1] + 4, bb[2] + 3, size, UI.label, "left", bw - 8)
      if st.page < #st.pages then
        K.chevron(bb[1] + bb[3] - 4, bb[2] + bb[4] - 4, 3, UI.accent, 2, K.pulse())
      end
      K.addHit(bb, "win", NEXT)
    end
    -- (End)
    local eb = K.R(cx - 12, y + h - 13, 24, 10)
    K.col(UI.red)
    K.box("fill", eb, 5)
    K.bold(T("phone.end"), eb[1], eb[2] + 2.4, 4.6, WHITE, "center", eb[3])
    K.addHit(eb, "win", END)
  end

  local function drawTabs(x, y, w)
    K.segmented(x, y, w, 9, st.tab, "win", TAB_FAV, T("phone.favourites"), TAB_REC, T("phone.recents"),
      TAB_CON, T("phone.contacts"))
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    st.clip = body
    st.wide = not portrait and w >= 200
    if st.view == "call" then
      drawCall(x, y, w, h, clock)
    elseif st.wide then
      local lw = floor((w - M * 3) * 0.48)
      drawTabs(x + M, y + 2, lw)
      local top = y + 13
      if st.tab == 3 then
        local fb = K.R(x + M, top, lw, 8)
        K.col(st.rematchOnly and GREEN_SOFT or UI.fill)
        K.box("fill", fb, 4)
        K.text(T("phone.rematchOnly"), fb[1] + 3, fb[2] + 1.6, 4.2, st.rematchOnly and GREEN or UI.secondary)
        K.addHit(fb, "win", FILTER)
        top = top + 10
      end
      drawRows(x + M, top, lw, y + h - M - top, st.view == "list")
      K.scissor(body)
      local cx = x + M * 2 + lw
      if row() and row().contact then
        drawCard(cx, y + 2, w - lw - M * 3, h - 2 - M)
      else
        K.text(T("phone.pick"), cx, y + h / 2 - 3, 4.6, UI.tertiary, "center", w - lw - M * 3)
      end
    elseif st.view == "card" then
      drawCard(x + M, y + 2, w - M * 2, h - 2 - M)
    else
      drawTabs(x + M, y + 2, w - M * 2)
      local top = y + 13
      if st.tab == 3 then
        local fb = K.R(x + M, top, w - M * 2, 8)
        K.col(st.rematchOnly and GREEN_SOFT or UI.fill)
        K.box("fill", fb, 4)
        K.text(T("phone.rematchOnly"), fb[1] + 3, fb[2] + 1.6, 4.2, st.rematchOnly and GREEN or UI.secondary)
        K.addHit(fb, "win", FILTER)
        top = top + 10
      end
      drawRows(x + M, top, w - M * 2, y + h - M - top, true)
    end
    K.scissor(body)
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h), UI.red, UI.green, UI.hud) then st.toast = nil end
  end

  -- (opened on a tab: a notification's call opens Recents)
  local resume = ctx.resume and ctx.resume.app == ctx.app and ctx.resume.state
  if type(resume) == "table" and resume.tab == "recents" then st.tab = 2 end
  refresh()
  return W
end
