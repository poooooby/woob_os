-- The Phone app: the PokéNav's contacts as a phone (src/phone.lua). Three tabs: Favourites, Recents
-- (the calls made and the field's calls, newest first) and Contacts (a Rematch filter: who's ready
-- for a rematch). A contact's card: their picture, class and place, a "wants a rematch" or "nearby"
-- pill, Call and ★; the check page's lines (Emerald) or Trainer's Eyes' profile (Ruby / Sapphire,
-- no calls). A call: it rings (the picture large, pulsing), then a header (the picture, the name, a
-- running timer, a waveform while they talk) over the game's own words as chat bubbles: a "..."
-- bubble, then the words typed out; A shows the rest at once, then the next bubble; the older ones
-- glide up and fade under the header. End: the round red button (B).
--   buttons  L / R the tab, Up / Down the row, A open (a card: Left / Right Call or ★, A press),
--            SELECT the Rematch filter (Contacts), B back
--   touch    the tabs, a row, the card's buttons, End; drag (or the wheel) scrolls
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, abs, sin, pi = math.floor, math.max, math.min, math.abs, math.sin, math.pi

local ROW_H, M = 15, 3
local TAB_FAV, TAB_REC, TAB_CON, FILTER, CALL, FAV, END, NEXT = 2001, 2002, 2003, 2004, 2010, 2011, 2012, 2013
local DIAL = 0.9    -- seconds of "Calling ..."
local TYPING = 0.45 -- seconds of the "..." bubble before each one
local CPS = 46      -- letters a second, typed out
local SHRINK = 0.35 -- seconds of the picture moving up into the header
local HINTS = {
  list = { { "L R", "phone.hint.tab" }, { "A", "hint.choose" }, { "B", "hint.back" } },
  contacts = { { "L R", "phone.hint.tab" }, { "A", "hint.choose" }, { "SELECT", "phone.rematch" }, { "B", "hint.back" } },
  card = { { "< >", "phone.hint.button" }, { "A", "hint.choose" }, { "B", "hint.back" } },
  call = { { "A", "phone.hint.next" }, { "B", "phone.end" } },
  typing = { { "A", "hint.skip" }, { "B", "phone.end" } },
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
    button = 1, call = nil, bubbles = nil, bubW = 0, bubL = 0, toast = nil, agoAt = -10,
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

  -- (keeps the chosen row in view, unless the list was scrolled by hand since the last press: a drag
  -- or the wheel would otherwise be pulled straight back to it on the next frame)
  local function clamp(follow)
    if follow then st.free = false end
    st.cursor = max(1, min(st.cursor, #st.rows))
    if not st.free then
      if st.cursor > st.top + st.visible then st.top = st.cursor - st.visible end
      if st.cursor <= st.top then st.top = st.cursor - 1 end
    end
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

  -- a call under way: cl.idx the bubble showing, cl.at when it began ("..." first), cl.full once A
  -- has shown all of it; cl.lift / stackH / last the bubbles' glide
  -- (the game's words open with the caller's name, which the header already shows)
  local function withoutName(text, name)
    if not (text and name and name ~= "") then return text end
    if text:sub(1, #name + 1):upper() == (name .. ":"):upper() then
      return (text:sub(#name + 2):gsub("^%s+", ""))
    end
    return text
  end
  local function startCall(cl)
    cl.text = withoutName(cl.text, cl.name)
    cl.idx, cl.at, cl.full, cl.lift, cl.stackH, cl.last = 1, max(cl.t0 + DIAL, now()), false, 0, nil, nil
    st.call, st.bubbles, st.view = cl, nil, "call"
  end
  local function typingNow(cl, t) return not cl.full and t - cl.at < TYPING end
  local function shownOf(cl, b, t)
    if cl.full then return b.n end
    return max(0, min(b.n, floor((t - cl.at - TYPING) * CPS)))
  end

  local function openRow()
    local r = row()
    if not r then return end
    st.button = 1
    if r.contact then
      st.view = "card"
    elseif r.recent then
      -- (a field call from someone no longer listed: its words again, answered already)
      startCall({ contact = nil, recent = r.recent, text = r.recent.text, t0 = now() - DIAL - SHRINK, name = r.recent.name,
                  pic = r.recent.pic })
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
    startCall({ contact = c, text = text, t0 = now(), name = c.name, pic = c.pic })
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
    st.call, st.bubbles = nil, nil
  end
  -- A / a tap: the rest of the bubble at once, then the next one, then the call ends
  local function nextPage()
    local cl = st.call
    if not cl or not st.bubbles then return end
    local t = now()
    if t - cl.t0 < DIAL then return end
    local b = st.bubbles[cl.idx]
    if b and shownOf(cl, b, t) < b.n then
      cl.full = true
      return
    end
    if cl.idx < #st.bubbles then
      cl.idx, cl.at, cl.full = cl.idx + 1, t, false
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
    if nav.up then st.cursor = st.cursor - 1; clamp(true); se("SE_SELECT")
    elseif nav.down then st.cursor = st.cursor + 1; clamp(true); se("SE_SELECT")
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
      clamp(true)
      openRow()
    end
  end

  function W.scroll(dy)
    if st.view ~= "list" and not st.wide then return end
    st.free = true
    st.top = max(0, min(max(0, #st.rows - st.visible), st.top - dy / ROW_H))
  end

  function W.hints()
    if st.view == "call" then
      local cl, b = st.call, st.bubbles and st.call and st.bubbles[st.call.idx]
      if b and now() - cl.t0 >= DIAL and shownOf(cl, b, now()) < b.n then return T.list(HINTS.typing) end
      return T.list(HINTS.call)
    end
    if st.view == "card" then return T.list(HINTS.card) end
    return T.list(st.tab == 3 and HINTS.contacts or HINTS.list)
  end

  -- ------- drawing (no tables made here)

  local GREEN, AMBER, STAR = { 52, 199, 89 }, { 255, 159, 10 }, { 255, 204, 0 }
  local CALL_TOP, CALL_FOOT = { 34, 52, 64 }, { 12, 16, 22 }
  local WHITE, SOFT = { 255, 255, 255 }, { 255, 255, 255, 0.7 }
  local TILE = { 228, 230, 238 }

  -- the trainer's picture in a rounded tile (units); someone without one: their initial on a tint of
  -- their own
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

  -- a five-pointed star: ten triangles from its middle (a filled polygon must be convex)
  local STAR_X, STAR_Y = {}, {}
  for i = 0, 10 do
    local a = -math.pi / 2 + i * math.pi / 5
    local k = i % 2 == 0 and 1 or 0.42
    STAR_X[i], STAR_Y[i] = math.cos(a) * k, math.sin(a) * k
  end
  local function star(cx, cy, r, c)
    local G = K.graphics()
    K.col(c)
    local x, y, s = K.X(cx), K.Y(cy), r * K.sc
    for i = 0, 9 do
      G.polygon("fill", x, y, x + STAR_X[i] * s, y + STAR_Y[i] * s, x + STAR_X[i + 1] * s, y + STAR_Y[i + 1] * s)
    end
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
    -- (scrolled by hand, the top falls between rows: from the row it's in, clipped to the list; the
    -- pictures put the clip back to st.clip)
    local area = K.R(x, y, w, h)
    local clip = st.clip
    st.clip = area
    K.scissor(area)
    local first = floor(st.top) + 1
    for i = first, min(#st.rows, first + st.visible) do
      local r = st.rows[i]
      local ry = y + (i - 1 - st.top) * ROW_H
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
      if i > first and not on and i - 1 ~= st.cursor then K.hairline(tx, ry, w - 16) end
      K.addHit(rb, "win", i, area)
    end
    st.clip = clip
    K.scissor(clip)
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
    -- (the buttons' focus only once the card is open: A on a contact)
    local carded = st.view == "card"
    if carded and st.button == 1 then K.focusRing(cb, 5.5) end
    local on = Ph.isFav(session(), c.key)
    K.col(UI.fill)
    K.box("fill", fb, 5.5)
    star(fb[1] + 7, fb[2] + 5.5, 2.4, on and STAR or UI.tertiary)
    K.text(T(on and "phone.favourite" or "phone.addFav"), fb[1] + 11, fb[2] + 2.8, K.fit(T("phone.addFav"), 4.6, bw - 13),
      UI.label)
    if carded and st.button == 2 then K.focusRing(fb, 5.5) end
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

  -- ------- the call

  local BG_TOP, BG_FOOT, BUBBLE = { 24, 32, 48 }, { 6, 8, 14 }, { 50, 58, 76 }
  local GREEN_TEXT = { 120, 230, 150 }
  local SIZE, LINE, PADX, PADY = 4.6, 6.1, 3.6, 2.4
  local UTF8 = "[%z\1-\127\194-\244][\128-\191]*"

  -- a bubble: its lines, each line's typed-out beginnings (made here, so the draw makes no strings)
  local function bubbleOf(lines)
    local b = { lines = lines, pre = {}, count = {}, n = 0, tw = 0 }
    for j, line in ipairs(lines) do
      local pre, k, acc = {}, 0, ""
      for ch in line:gmatch(UTF8) do
        k = k + 1
        acc = acc .. ch
        pre[k] = acc
      end
      b.pre[j], b.count[j], b.n = pre, k, b.n + k
      b.tw = max(b.tw, K.width(line, SIZE))
    end
    b.h = #lines * LINE + PADY * 2 - 0.6
    return b
  end
  -- the game's pages (a blank line apart) as bubbles of at most `most` lines, `w` units wide (made
  -- when the size changes, not every frame)
  local function buildBubbles(text, w, most)
    local out = {}
    text = (text or ""):gsub("\r", "")
    for page in (text .. "\n\n"):gmatch("(.-)\n\n") do
      local lines, line = {}, ""
      for word in page:gmatch("%S+") do
        local try = line == "" and word or (line .. " " .. word)
        if line ~= "" and K.width(try, SIZE) > w then
          lines[#lines + 1] = line
          line = word
          if #lines >= most then
            out[#out + 1] = bubbleOf(lines)
            lines = {}
          end
        else
          line = try
        end
      end
      if line ~= "" then lines[#lines + 1] = line end
      if #lines > 0 then out[#out + 1] = bubbleOf(lines) end
    end
    if #out == 0 then out[1] = bubbleOf({ "..." }) end
    return out
  end
  -- a bubble's height: the newest grows a line at a time as it's typed ("..." before it)
  local function heightOf(cl, b, i, t)
    if i ~= cl.idx or cl.full then return b.h end
    if typingNow(cl, t) then return 9.2 end
    local left, n = shownOf(cl, b, t), 0
    for j = 1, #b.lines do
      if left <= 0 then break end
      n, left = j, left - b.count[j]
    end
    return max(1, n) * LINE + PADY * 2 - 0.6
  end
  local timeText = K.textCache(function(s) return string.format("%d:%02d", floor(s / 60), s % 60) end)

  -- the "..." bubble's dots, rising one after another
  local function typingDots(bx, by, a, clock)
    local G = K.graphics()
    for d = 0, 2 do
      local s = abs(sin(clock * 6 - d * 0.7))
      K.col(WHITE, (0.4 + 0.6 * s) * a)
      G.circle("fill", K.X(bx + 4.6 + d * 3.9), K.Y(by + 4.6 - s * 1.2), 1.05 * K.sc)
    end
  end

  -- a hang-up button: red, round, a handset lying across it
  local function endButton(cx, cy, r, glow, clock)
    local G = K.graphics()
    if glow then
      local p = (clock * 0.9) % 1
      K.col(UI.red, 0.55 * (1 - p))
      G.setLineWidth(max(1, 0.6 * K.sc))
      G.circle("line", K.X(cx), K.Y(cy), (r + p * 4) * K.sc)
    end
    K.col(UI.red)
    G.circle("fill", K.X(cx), K.Y(cy), r * K.sc)
    if env.glyph then
      G.push()
      G.translate(K.X(cx), K.Y(cy))
      G.rotate(pi * 0.75)
      pcall(env.glyph, G, "phone", 0, 0, r * 1.45 * K.sc, 1)
      G.pop()
    end
    K.addHit(K.R(cx - r - 1, cy - r - 1, r * 2 + 2, r * 2 + 2), "win", END)
  end

  -- the bubbles, newest at the foot, between ay0 and ay1
  local function drawBubbles(cl, x, ay0, ay1, w, a, t, clock)
    local G = K.graphics()
    local tw = floor(min(w - 28, 170) - PADX * 2)
    local most = max(2, min(4, floor((ay1 - ay0 - PADY * 2) / LINE)))
    if not st.bubbles or st.bubW ~= tw or st.bubL ~= most then
      st.bubbles, st.bubW, st.bubL = buildBubbles(cl.text, tw, most), tw, most
      cl.idx = min(cl.idx, #st.bubbles)
    end
    local bubbles = st.bubbles
    local typing = typingNow(cl, t)
    -- (the stack's height: when it grows, everything is lifted back down and glides up)
    local H = 0
    for i = 1, cl.idx do H = H + heightOf(cl, bubbles[i], i, t) + 2.2 end
    local dt = cl.last and min(0.1, max(0, t - cl.last)) or 0
    cl.last = t
    if cl.stackH and H > cl.stackH then cl.lift = cl.lift + (H - cl.stackH) end
    cl.stackH = H
    cl.lift = cl.lift * math.exp(-dt * 11)
    if cl.lift < 0.05 then cl.lift = 0 end
    local area = K.R(x, ay0, w, ay1 - ay0)
    K.scissor(area)
    local clip = st.clip
    st.clip = area
    local bub = K.mix(BUBBLE, INITIAL[(#(cl.name or "") % #INITIAL) + 1], 0.2)
    local bx = x + 14
    local by = ay1 + cl.lift
    for i = cl.idx, 1, -1 do
      local b = bubbles[i]
      local now_ = i == cl.idx
      local dots = now_ and typing
      local bh, bw = heightOf(cl, b, i, t), dots and 17 or (b.tw + PADX * 2)
      by = by - bh
      if by + bh < ay0 then break end
      -- (fading in as it comes; the older ones fading out as they reach the header)
      local ba = a * min(1, max(0, (by - ay0 + 3) / 9))
      if now_ and not cl.full then
        ba = ba * min(1, dots and (t - cl.at) / 0.15 or (0.35 + (t - cl.at - TYPING) / 0.12))
      end
      K.col(bub, ba)
      K.box("fill", K.R(bx, by, bw, bh), 4.4)
      if now_ then
        -- (the newest: a tail toward the picture beside it)
        G.polygon("fill", K.X(bx + 0.6), K.Y(by + bh - 4.4), K.X(bx + 4.2), K.Y(by + bh), K.X(bx - 1.8), K.Y(by + bh + 0.5))
        picture(cl.pic, x + 4.5, by + bh - 7.6, 7.6, nil, cl.name)
      end
      if dots then
        typingDots(bx, by, ba, clock)
      else
        local left = now_ and shownOf(cl, b, t) or b.n
        local ly = by + PADY
        for j, line in ipairs(b.lines) do
          local n = b.count[j]
          if left >= n then
            K.text(line, bx + PADX, ly, SIZE, WHITE, nil, nil, ba)
            left = left - n
          else
            if left > 0 then K.text(b.pre[j][left], bx + PADX, ly, SIZE, WHITE, nil, nil, ba) end
            break
          end
          ly = ly + LINE
        end
        if now_ and cl.idx < #bubbles and shownOf(cl, b, t) >= b.n then
          K.chevron(bx + bw + 3.2, by + bh - 3, 1.8, WHITE, 2, K.pulse() * ba)
        end
      end
      by = by - 2.2
    end
    st.clip = clip
    K.scissor(clip)
    K.addHit(area, "win", NEXT)
  end

  local function drawCall(x, y, w, h, clock)
    local cl = st.call
    if not cl then return end
    local G = K.graphics()
    local t = now()
    local since = t - cl.t0
    local tint = INITIAL[(#(cl.name or "") % #INITIAL) + 1]
    K.grad(K.R(x, y, w, h), 0, BG_TOP, BG_FOOT)
    K.glow(x + w * (0.25 + 0.06 * sin(clock * 0.4)), y + h * 0.16, w * 0.55, h * 0.45, tint, 0.2)
    K.glow(x + w * 0.85, y + h * (0.9 + 0.05 * sin(clock * 0.33)), w * 0.5, h * 0.4, GREEN, 0.08)
    -- (e: 0 while it rings, 1 once the picture is up in the header)
    local e = min(1, max(0, (since - DIAL) / SHRINK))
    e = e * e * (3 - 2 * e)
    local cx = x + w / 2
    local big = min(30, h * 0.26)
    local px0, py0 = cx - big / 2, y + max(6, h * 0.3 - big / 2)
    local ps = big + (12 - big) * e
    local px, py = px0 + (x + 5 - px0) * e, py0 + (y + 4 - py0) * e
    if since < DIAL then
      -- (two rings spreading out of the picture while it rings)
      for k = 0, 1 do
        local p = (clock * 1.2 + k * 0.5) % 1
        K.col(GREEN, 0.55 * (1 - p))
        G.setLineWidth(max(1, 0.5 * K.sc))
        G.circle("line", K.X(cx), K.Y(py0 + big / 2), (big / 2 + 1.5 + p * 9) * K.sc)
      end
    end
    picture(cl.pic, px, py, ps, WHITE, cl.name)
    if e < 1 then
      local a = 1 - e
      K.bold(cl.name, x, py0 + big + 4, 6, WHITE, "center", w, a)
      local word = T("phone.calling")
      local ww = K.width(word, 4.4)
      K.text(word, x, py0 + big + 12, 4.4, SOFT, "center", w, a)
      local dots = floor(since * 4) % 4
      for i = 1, dots do
        K.col(SOFT, a)
        G.circle("fill", K.X(cx + ww / 2 + i * 2), K.Y(py0 + big + 16), 0.5 * K.sc)
      end
    end
    if since >= DIAL then
      -- (the header: the name, a green dot and the time on the call, a waveform while they talk)
      local nx = x + 20
      K.bold(cl.name, nx, y + 4.2, K.fit(cl.name, 5.2, w - 26), WHITE, nil, nil, e)
      K.col(GREEN, e)
      G.circle("fill", K.X(nx + 1), K.Y(y + 12.9), 0.95 * K.sc)
      local clockText = timeText(floor(max(0, since - DIAL)))
      K.text(clockText, nx + 3, y + 10.8, 3.8, GREEN_TEXT, nil, nil, e)
      local b = st.bubbles and st.bubbles[cl.idx]
      local talking = b and not typingNow(cl, t) and shownOf(cl, b, t) < b.n
      local wx = nx + 3 + K.width(clockText, 3.8) + 3
      for i = 0, 4 do
        local amp = talking and (0.35 + 0.65 * abs(sin(clock * 9 + i * 1.7))) or 0.12
        local bh = 0.7 + 2.8 * amp
        K.col(WHITE, 0.75 * e)
        K.box("fill", K.R(wx + i * 1.5, y + 12.9 - bh / 2, 0.8, bh), 0.4)
      end
      K.hairline(x, y + 18, w, WHITE, 0.08 * e)
      drawBubbles(cl, x, y + 19, y + h - 18, w, e, t, clock)
    end
    -- (End)
    local last = st.bubbles and cl.idx >= #st.bubbles and e >= 1
    local done = last and st.bubbles[cl.idx] and shownOf(cl, st.bubbles[cl.idx], t) >= st.bubbles[cl.idx].n
    endButton(cx, y + h - 9, 6, done, clock)
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
