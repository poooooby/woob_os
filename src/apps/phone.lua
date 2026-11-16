-- The Phone app: the PokéNav's contacts as a phone (src/phone.lua). Three tabs: Favourites, Recents
-- (the calls made and the field's calls, newest first) and Contacts (a Rematch filter: who's ready
-- for a rematch). A contact's card: their picture, class and place, a "wants a rematch" or "nearby"
-- pill, Call and ★; the check page's lines (Emerald) or Trainer's Eyes' profile (Ruby / Sapphire,
-- no calls). A call: it rings (the picture large, pulsing), then a header (the picture, the name, a
-- running timer, a waveform while they talk) over the game's own words as chat bubbles: a "..."
-- bubble, then the words typed out; A shows the rest at once, then the next bubble; the older ones
-- glide up and fade under the header. End: the round red button (B).
-- The look is the Pokédex's glass: panes over a backdrop lit by the chosen contact's colour. Its motion
-- (numbers only, in `mv`): the backdrop turning to the contact's colour, the tabs' thumb sliding, the
-- rows rising in one after another when the tab or the filter changes, the chosen row's highlight
-- gliding and the list scrolling smoothly, the card's picture popping up on its disc and its words
-- sliding in, the check page's lines rising, the ★ popping as it's set, the card sliding over the list
-- when the window is narrow; a call fading in, its picture popping up while it rings and moving into the
-- header, each bubble popping up from its tail and widening as the words come.
--   buttons  L / R the tab, Up / Down the row, A open (a card: Left / Right Call or ★, A press),
--            SELECT the Rematch filter (Contacts), B back
--   touch    the tabs, a row, the card's buttons (narrow: its back), End; drag (or the wheel) scrolls
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, abs, sin, pi = math.floor, math.max, math.min, math.abs, math.sin, math.pi

local ROW_H, M, GAP = 15, 3, 2
local TAB_FAV, TAB_REC, TAB_CON, FILTER, CALL, FAV, END, NEXT, BACK = 2001, 2002, 2003, 2004, 2010, 2011, 2012, 2013,
  2014
local CHOICE = 2020 -- (a live call's YES / NO: CHOICE + 1, CHOICE + 2)
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

local C = {
  ink = { 28, 28, 30 }, soft = { 112, 112, 120 }, faint = { 160, 160, 170 }, accent = { 10, 132, 255 },
  white = { 255, 255, 255 }, black = { 0, 0, 0 }, green = { 52, 199, 89 }, greenInk = { 30, 150, 64 },
  amber = { 230, 140, 0 }, star = { 255, 196, 0 }, red = { 255, 59, 48 }, track = { 118, 118, 128, 0.16 },
  slate = { 120, 132, 178 }, bubble = { 255, 255, 255, 0.8 },
}
local SHADE_TOP, SHADE_FOOT = { 255, 255, 255, 0.28 }, { 0, 0, 0, 0.16 }
-- each contact's colour, by their name (iOS's: blue, orange, green, purple, pink, teal, indigo, amber)
local TINTS = { { 10, 132, 255 }, { 255, 149, 0 }, { 52, 199, 89 }, { 175, 82, 222 }, { 255, 55, 95 },
                { 48, 176, 199 }, { 88, 86, 214 }, { 230, 170, 30 } }

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
    local text, ok, live = Ph.call(session(), c)
    if not ok then
      se("SE_FAILURE")
      return toast("phone.failed")
    end
    -- (Gold / Silver / Crystal: the game rang already; a live call is the game's own script, its words
    -- followed as they come)
    if not live then se("SE_POKENAV_CALL") end
    startCall({ contact = c, text = text, t0 = now(), name = c.name, pic = c.pic, live = live })
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
    -- (a live call ends when the game's script does)
    if st.call.live and not st.call.live.done then return end
    se("SE_POKENAV_HANG_UP")
    st.view = st.call.contact and "card" or "list"
    st.call, st.bubbles = nil, nil
  end
  -- A / a tap: the rest of the bubble at once, then the next one, then the call ends
  local function nextPage()
    local cl = st.call
    if cl and cl.live and not cl.live.done then
      -- (a tap: the game's A, to its box)
      return cl.live.press("a")
    end
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
    if (arg == CHOICE + 1 or arg == CHOICE + 2) and st.call and st.call.live and st.call.live.choice then
      -- (the YES / NO box's own cursor, then its A)
      local box = st.call.live.choice
      box.index = arg - CHOICE
      return st.call.live.press("a")
    end
    if arg == BACK then
      if st.view == "card" then
        st.view = "list"
        se("SE_SELECT")
      end
      return
    end
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

  -- ------- drawing (no tables, closures or strings made here, but a contact's colour and initial the
  -- first time their name is drawn)

  local G = nil
  local outCubic, outBack, approach = K.outCubic, K.outBack, K.approach
  -- the motion's numbers: when the window opened, when the rows last rose (another tab, the filter),
  -- the tabs' thumb, the gliding highlight, the eased scroll, the contact shown and since when, the ★'s
  -- pop, the filter's switch, the narrow card's slide, the call's fade, the backdrop's colours
  local mv = { lastT = nil, openAt = nil, rowsAt = -10, tab = nil, filter = nil, tabX = 3, selY = nil, top = 0,
               shown = nil, shownAt = -10, view = nil, favKey = nil, favOn = nil, favAt = -10, filterK = 0, push = 0,
               call = nil, callAt = -10, coloured = false, r = 0.5, g = 0.5, b = 0.5, r2 = 0.5, g2 = 0.5, b2 = 0.5 }
  W.motion = mv

  local tints, initials = {}, {}
  local function tintOf(name)
    name = name or "?"
    local c = tints[name]
    if not c then
      local h = 0
      for i = 1, #name do h = (h * 31 + name:byte(i)) % 65521 end
      c = TINTS[h % #TINTS + 1]
      tints[name] = c
    end
    return c
  end
  local function initialOf(name)
    name = name or "?"
    local s = initials[name]
    if not s then
      s = name:match("[%z\1-\127\194-\244][\128-\191]*") or "?"
      s = s:upper()
      initials[name] = s
    end
    return s
  end

  -- (the scissor there was, put back: the pictures clip themselves to their square)
  local function clipTo(x, y, w, h)
    local sx, sy, sw, sh
    if G.getScissor then sx, sy, sw, sh = G.getScissor() end
    G.intersectScissor(K.X(x), K.Y(y), max(0, w * K.sc), max(0, h * K.sc))
    return sx, sy, sw, sh
  end
  local function unclip(sx, sy, sw, sh)
    if sx then G.setScissor(sx, sy, sw, sh) else G.setScissor() end
  end

  -- someone's picture on a round disc (units), clipped to its square; someone without one: their initial on
  -- a disc of their colour. `a` its alpha
  local function avatar(pic, name, x, y, size, a)
    local img = Ph.picture(pic)
    K.rescissor()
    local tint = tintOf(name)
    local cx, cy, r = K.X(x + size / 2), K.Y(y + size / 2), size / 2 * K.sc
    if not img then
      K.col(tint, a)
      G.circle("fill", cx, cy, r)
      K.bold(initialOf(name), x, y + size * 0.2, size * 0.55, C.white, "center", size, a)
      return
    end
    K.col(K.light(tint, 0.62), a)
    G.circle("fill", cx, cy, r)
    local iw, ih = img:getDimensions()
    local s = size * K.sc / max(iw, ih) * 1.08
    local sx, sy, sw, sh = clipTo(x, y, size, size)
    G.setColor(1, 1, 1, a * K.getFade())
    G.draw(img, cx, cy + size * 0.04 * K.sc, 0, s, s, iw / 2, ih / 2)
    unclip(sx, sy, sw, sh)
  end

  -- a five-pointed star: ten triangles from its middle (a filled polygon must be convex)
  local STAR_X, STAR_Y = {}, {}
  for i = 0, 10 do
    local a = -math.pi / 2 + i * math.pi / 5
    local k = i % 2 == 0 and 1 or 0.42
    STAR_X[i], STAR_Y[i] = math.cos(a) * k, math.sin(a) * k
  end
  local function star(cx, cy, r, c, a)
    K.col(c, a)
    local x, y, s = K.X(cx), K.Y(cy), r * K.sc
    for i = 0, 9 do
      G.polygon("fill", x, y, x + STAR_X[i] * s, y + STAR_Y[i] * s, x + STAR_X[i + 1] * s, y + STAR_Y[i + 1] * s)
    end
  end
  -- a handset, white, `s` units, centred on cx, cy, turned by `turn`
  local function handset(cx, cy, s, a, turn)
    if not env.glyph then return end
    if turn and turn ~= 0 then
      G.push()
      G.translate(K.X(cx), K.Y(cy))
      G.rotate(turn)
      pcall(env.glyph, G, "phone", 0, 0, s * K.sc, a * K.getFade())
      G.pop()
    else
      pcall(env.glyph, G, "phone", K.X(cx), K.Y(cy), s * K.sc, a * K.getFade())
    end
  end
  -- a capsule with words -> where the next one goes (grown with the text size, its words fitted to end by
  -- `right`)
  local function pill(x, y, words, fill, fillA, ink, size, a, right)
    if right and K.textScale() > 1 then size = K.fit(words, size, right - x - 5) end
    local w = K.width(words, size) + 5
    -- (as tall as its words are drawn)
    local g = (K.textScale() - 1) * size
    K.col(fill, fillA * a)
    K.box("fill", K.R(x, y, w, size + 2.6 + g), (size + 2.6 + g) / 2)
    K.bold(words, x, y + 1.2 + g / 2, size, ink, "center", w, a)
    return x + w + 1.5
  end

  -- ------- the list: the tabs' glass switch, the filter, the rows on a pane of glass

  local function drawEmpty(x, y, w, h)
    local key = st.tab == 1 and "phone.noFav" or (st.tab == 2 and "phone.noRecent" or "phone.noContacts")
    local d = min(16, h * 0.4)
    local cy = y + h / 2 - 4
    if d >= 8 then
      K.col(C.green, 0.85)
      G.circle("fill", K.X(x + w / 2), K.Y(cy - d * 0.3), d / 2 * K.sc)
      handset(x + w / 2, cy - d * 0.3, d * 0.8, 1)
      cy = cy + d * 0.3
    end
    K.text(T(key), x + 4, cy + 1, 4.2, C.soft, "center", w - 8)
  end

  local function drawRows(x, y, w, h, focused, clock, dt, live)
    st.visible = max(1, floor((h - 2) / ROW_H))
    clamp()
    if h < 4 then return end
    K.glass(K.R(x, y, w, h), 4, 0.55)
    if #st.rows == 0 then return drawEmpty(x, y, w, h) end
    local s = session()
    local t = os.time()
    local refreshAgo = now() - st.agoAt >= 1
    if refreshAgo then st.agoAt = now() end
    -- (smooth to where the D-pad sent it; scrolled by hand, right where the hand left it)
    if st.free then mv.top = st.top else mv.top = approach(mv.top, st.top, dt, 20) end
    local top = mv.top
    local area = K.R(x, y + 1, w, h - 2)
    local sx, sy, sw, sh = clipTo(x, y + 1, w, h - 2)
    -- (the chosen row's highlight, gliding from row to row)
    if mv.selY == nil then mv.selY = st.cursor else mv.selY = approach(mv.selY, st.cursor, dt, 24) end
    local hb = K.R(x + 1.2, y + 1 + (mv.selY - 1 - top) * ROW_H + 0.4, w - 2.4, ROW_H - 0.8)
    if focused then
      K.col(C.accent)
      K.box("fill", hb, 3.5)
    else
      K.col(C.white, 0.75)
      K.box("fill", hb, 3.5)
      K.ring(hb, 3.5, C.white, 0.9, 0.3)
    end
    local since = clock - mv.rowsAt
    local first = floor(top) + 1
    local f0 = K.getFade()
    -- (the name and the line under it apart as the text grows: nothing at 100%)
    local gl = (K.textScale() - 1) * 1.5
    for i = first, min(#st.rows, first + st.visible) do
      local r = st.rows[i]
      local e = K.stagger(since, i - first, 0.035, 0.28)
      local ry = y + 1 + (i - 1 - top) * ROW_H
      local oy = (1 - e) * 4
      K.setFade(f0 * e)
      local on = i == st.cursor
      local lit = on and focused and abs(mv.selY - i) < 0.5
      local ink = lit and C.white or C.ink
      local soft = lit and C.white or C.soft
      local c = r.contact
      local name = c and c.name or (r.recent and r.recent.name) or "?"
      avatar(c and c.pic or (r.recent and r.recent.pic), name, x + 2.5, ry + oy + 2, 11, 1)
      local tx = x + 16
      local nw = w - 16 - 14
      K.bold(name, tx, ry + oy + 2.2 - gl, K.fit(name, 4.8, nw), ink)
      if r.recent then
        if refreshAgo or not r.ago then r.ago = agoText(max(0, floor((t - (r.recent.at or t)) / 60))) end
        -- (in or out: a little arrow)
        K.col(lit and C.white or (r.recent.incoming and C.green or C.accent))
        local ax, ay = K.X(tx + 1.5), K.Y(ry + oy + 10.2 + gl)
        local u = 1.4 * K.sc
        if r.recent.incoming then G.polygon("fill", ax - u, ay - u, ax + u, ay + u, ax - u, ay + u)
        else G.polygon("fill", ax + u, ay + u, ax - u, ay - u, ax + u, ay - u) end
        K.text(r.ago, tx + 4, ry + oy + 8.3 + gl, 3.8, soft, nil, nil, lit and 0.85 or 1)
      else
        local sub = c.place ~= "" and c.place or c.desc
        K.text(sub, tx, ry + oy + 8.3 + gl, K.fit(sub, 3.8, nw), soft, nil, nil, lit and 0.85 or 1)
      end
      if c and c.rematch then
        K.col(lit and C.white or C.green)
        G.circle("fill", K.X(x + w - 6.4), K.Y(ry + oy + ROW_H / 2), 1.6 * K.sc)
      end
      if c and Ph.isFav(s, c.key) then star(x + w - 11.5, ry + oy + ROW_H / 2, 1.9, lit and C.white or C.star) end
      if i > first and not on and i - 1 ~= st.cursor then K.hairline(tx, ry, w - 18) end
      if live then K.addHit(K.R(x, ry, w, ROW_H), "win", i, area) end
    end
    K.setFade(f0)
    unclip(sx, sy, sw, sh)
    K.scrollbar(x + w, y + 1, h - 2, top, st.visible, #st.rows)
  end

  -- the tabs, the filter (Contacts), the rows
  local function drawList(x, y, w, h, focused, clock, dt, live)
    K.glassSwitch(x, y, w, 8, mv.tabX, "win", TAB_FAV, T("phone.favourites"), TAB_REC, T("phone.recents"),
      TAB_CON, T("phone.contacts"), 4.2)
    local top = y + 10
    if st.tab == 3 then
      -- (a capsule that turns green while it's on, a dot sliding across its switch)
      local fb = K.R(x, top, w, 7.5)
      local k = mv.filterK
      K.col(C.white, 0.4 * (1 - k))
      K.box("fill", fb, 3.75)
      K.col(C.green, 0.9 * k)
      K.box("fill", fb, 3.75)
      K.ring(fb, 3.75, C.white, 0.75, 0.3)
      local sw2 = 9
      local swb = K.R(x + w - sw2 - 1.5, top + 1.25, sw2, 5)
      K.col(C.white, 0.35 + 0.4 * k)
      K.box("fill", swb, 2.5)
      K.col(k > 0.5 and C.white or C.faint)
      G.circle("fill", K.X(swb[1] + 2.5 + (sw2 - 5) * k), K.Y(swb[2] + 2.5), 1.9 * K.sc)
      local label = T("phone.rematchOnly")
      local fs = K.fit(label, 4, w - sw2 - 8)
      K.text(label, x + 3, top + (7.5 - fs * 1.2) / 2, fs, C.soft, nil, nil, 1 - k)
      K.text(label, x + 3, top + (7.5 - fs * 1.2) / 2, fs, C.white, nil, nil, k)
      if live then K.addHit(fb, "win", FILTER) end
      top = top + 9
    end
    drawRows(x, top, w, y + h - top, focused, clock, dt, live)
  end

  -- ------- a contact's card: their pane (the picture popping up on its disc), Call and ★, the check page

  local function hero(c, x, y, w, h, t)
    local b = K.R(x, y, w, h)
    local f0 = K.getFade()
    K.shadow(b, 5, 1.4, 0.1)
    G.setColor(mv.r, mv.g, mv.b, 0.78 * f0)
    K.box("fill", b, 5)
    K.grad(b, 5, SHADE_TOP, SHADE_FOOT)
    K.ring(b, 5, C.white, 0.6, 0.4)
    local sx, sy, sw, sh = clipTo(x, y, w, h)
    -- (a call's rings spreading faintly from the corner)
    for k = 0, 1 do
      local p = (t * 0.25 + k * 0.5) % 1
      K.col(C.white, 0.16 * (1 - p))
      G.setLineWidth(max(1, 0.5 * K.sc))
      G.circle("line", K.X(x + w - 8), K.Y(y + 8), (6 + p * h * 0.9) * K.sc)
    end
    -- (the picture popping up on its disc, a light behind it)
    local pop = 0.75 + 0.25 * outBack(t / 0.42)
    local fa = outCubic(t / 0.18) * f0
    local ps = max(8, min(h - 8, 30))
    local pcx, pcy = x + 4 + ps / 2, y + h / 2
    K.glow(pcx, pcy, ps * 0.8, ps * 0.7, C.white, 0.3 * fa)
    K.col(C.white, 0.3 * fa)
    G.circle("fill", K.X(pcx), K.Y(pcy), ps / 2 * pop * K.sc)
    G.setLineWidth(max(1, 0.4 * K.sc))
    K.col(C.white, 0.75 * fa)
    G.circle("line", K.X(pcx), K.Y(pcy), ps / 2 * pop * K.sc)
    local img = Ph.picture(c.pic)
    K.rescissor()
    if img then
      local iw, ih = img:getDimensions()
      local s = ps * pop * K.sc / max(iw, ih) * 1.12
      G.setColor(1, 1, 1, fa)
      G.draw(img, K.X(pcx), K.Y(pcy - ps * 0.06), 0, s, s, iw / 2, ih / 2)
    else
      -- (their initial in their colour on a white disc)
      local ds = (ps - 5) * pop
      K.col(C.white, 0.92 * fa / max(0.001, f0))
      G.circle("fill", K.X(pcx), K.Y(pcy), ds / 2 * K.sc)
      K.bold(initialOf(c.name), pcx - ds / 2, pcy - ds * 0.3, ds * 0.5, tintOf(c.name), "center", ds,
        fa / max(0.001, f0))
    end
    unclip(sx, sy, sw, sh)
    -- (the words sliding in after it)
    local tx = x + ps + 9
    local room = x + w - tx - 3
    local e1, e2, e3 = outCubic((t - 0.05) / 0.32), outCubic((t - 0.1) / 0.32), outCubic((t - 0.16) / 0.32)
    -- (the lines apart as the text grows, the pills taller: nothing at 100%)
    local gs = K.textScale() - 1
    local ty = y + max(2, (h - 30 - gs * 9) / 2)
    K.label(c.name, tx + (1 - e1) * 8, ty, K.fit(c.name, 6.4, room), C.white, nil, nil, e1 * f0)
    K.label(c.desc, tx + (1 - e2) * 8, ty + 8.5 + gs * 4, K.fit(c.desc, 4, room), C.white, nil, nil, 0.9 * e2 * f0)
    if c.place ~= "" then
      K.label(c.place, tx + (1 - e2) * 8, ty + 14 + gs * 6, K.fit(c.place, 3.6, room), C.white, nil, nil,
        0.75 * e2 * f0)
    end
    local px = tx + (1 - e3) * 8
    local py = ty + 20.5 + gs * 8
    if c.rematch then px = pill(px, py, T("phone.wantsRematch"), C.white, 0.92, C.greenInk, 3.4, e3 * f0, x + w - 3) end
    if c.nearby then pill(px, py, T("phone.nearby"), C.white, 0.92, C.amber, 3.4, e3 * f0, x + w - 3) end
  end

  -- Call (green, a handset) and ★ (glass, the star popping as it's set)
  local function buttons(c, x, y, w, clock, carded)
    local bw = (w - 3) / 2
    local cb, fb = K.R(x, y, bw, 11), K.R(x + bw + 3, y, bw, 11)
    local f0 = K.getFade()
    local label = T("phone.call")
    local fs = K.fit(label, 4.8, bw - 14)
    local lw = K.width(label, fs)
    local gx = cb[1] + (bw - lw - 7) / 2
    if c.canCall then
      K.shadow(cb, 5.5, 1, 0.12)
      K.col(C.green)
      K.box("fill", cb, 5.5)
      K.col(C.white, 0.18)
      K.box("fill", K.R(cb[1] + 1, cb[2] + 0.6, cb[3] - 2, 4.6), 2.3)
      handset(gx + 2.5, cb[2] + 5.5, 8, 1)
      K.bold(label, gx + 7, cb[2] + (11 - fs * 1.2) / 2, fs, C.white)
    else
      K.col(C.white, 0.35)
      K.box("fill", cb, 5.5)
      K.ring(cb, 5.5, C.white, 0.7, 0.3)
      K.text(label, cb[1], cb[2] + (11 - fs * 1.2) / 2, fs, C.faint, "center", bw)
    end
    if carded and st.button == 1 then K.focusRing(cb, 5.5) end
    local on = Ph.isFav(session(), c.key)
    if mv.favKey ~= c.key then
      mv.favKey, mv.favOn = c.key, on
    elseif mv.favOn ~= on then
      mv.favOn, mv.favAt = on, clock
    end
    K.col(C.white, 0.6)
    K.box("fill", fb, 5.5)
    K.ring(fb, 5.5, C.white, 0.9, 0.35)
    local pt = clock - mv.favAt
    local k = 1
    if pt >= 0 and pt < 0.4 then
      k = 1 + 0.55 * sin(pt / 0.4 * pi)
      if on then
        -- (a ring bursting from it as it's set)
        local p = pt / 0.4
        K.col(C.star, 0.7 * (1 - p))
        G.setLineWidth(max(1, 0.5 * K.sc))
        G.circle("line", K.X(fb[1] + 7), K.Y(fb[2] + 5.5), (2.4 + p * 5) * K.sc)
      end
    end
    star(fb[1] + 7, fb[2] + 5.5, 2.6 * k, on and C.star or C.faint)
    local word = T(on and "phone.favourite" or "phone.addFav")
    local ws = K.fit(T("phone.addFav"), 4.4, bw - 14)
    K.text(word, fb[1] + 11, fb[2] + (11 - ws * 1.2) / 2, ws, C.ink)
    if carded and st.button == 2 then K.focusRing(fb, 5.5) end
    K.setFade(f0)
    K.addHit(cb, "win", CALL)
    K.addHit(fb, "win", FAV)
  end

  -- the check page's lines (the profile's headings in the accent) on glass, rising one after another
  local function checkPage(c, x, y, w, h, t)
    if h < 10 or #c.check == 0 then return end
    -- (as tall as its lines, the room allowing)
    -- (each line's step grows with the text size: nothing at 100%)
    local gs = K.textScale() - 1
    local need = 4.5
    for i = 1, #c.check do need = need + (c.headings and c.headings[i] and 5.4 + gs * 4.8 or 6.2 + gs * 5.2) end
    h = min(h, need)
    K.glass(K.R(x, y, w, h), 4, 0.55)
    local f0 = K.getFade()
    local ly = y + 3
    for i, line in ipairs(c.check) do
      local head = c.headings and c.headings[i]
      if ly + 5 + gs * 5 > y + h - 1.5 then break end
      local e = K.stagger(t - 0.12, i, 0.04, 0.28)
      K.setFade(f0 * e)
      K.text(line, x + 3.5, ly + (1 - e) * 3 + gs * 2, K.fit(line, head and 4 or 4.3, w - 7), head and C.accent or C.ink)
      ly = ly + (head and 5.4 + gs * 4.8 or 6.2 + gs * 5.2)
    end
    K.setFade(f0)
  end

  local function drawCard(x, y, w, h, clock, carded)
    local r = row()
    local c = r and r.contact
    if not c then
      -- (nobody chosen: a hint on glass)
      if h < 12 then return end
      local f0 = K.getFade()
      K.glass(K.R(x, y, w, h), 5, 0.35)
      local d = min(18, h * 0.3)
      local cx, cy = x + w / 2, y + h / 2 - 4
      K.col(C.white, 0.6)
      G.circle("fill", K.X(cx), K.Y(cy), d / 2 * K.sc)
      K.col(C.green)
      G.circle("fill", K.X(cx), K.Y(cy), d * 0.38 * K.sc)
      handset(cx, cy, d * 0.7, 1)
      K.text(T("phone.pick"), x + 4, cy + d / 2 + 2, 4.4, C.soft, "center", w - 8)
      K.setFade(f0)
      return
    end
    local t = clock - mv.shownAt
    local f0 = K.getFade()
    local heroH = min(36, h)
    local e0 = outCubic(t / 0.35)
    K.setFade(f0 * e0)
    hero(c, x, y + (1 - e0) * 5, w, heroH, t)
    K.setFade(f0)
    local by = y + heroH + GAP + 1
    if by + 11 > y + h then return end
    local e1 = outCubic((t - 0.06) / 0.35)
    K.setFade(f0 * e1)
    buttons(c, x, by + (1 - e1) * 5, w, clock, carded)
    K.setFade(f0)
    local ly = by + 14
    checkPage(c, x, ly, w, y + h - ly, t)
  end

  -- ------- the call

  local LINE_TOP = { 255, 255, 255, 0.55 }
  local SIZE, LINE, PADX, PADY = 4.6, 6.1, 3.6, 2.4
  -- (a line's step as the text grows, and how far its words are drawn higher by the kit: nothing at 100%)
  local function lineStep() return LINE + (K.textScale() - 1) * SIZE * 1.2 end
  local function lineLift() return (K.textScale() - 1) * SIZE * 0.6 end
  local UTF8 = "[%z\1-\127\194-\244][\128-\191]*"

  -- a bubble: its lines, each line's typed-out beginnings (made here, so the draw makes no strings)
  local function bubbleOf(lines)
    local b = { lines = lines, pre = {}, count = {}, lw = {}, n = 0, tw = 0 }
    for j, line in ipairs(lines) do
      local pre, k, acc = {}, 0, ""
      for ch in line:gmatch(UTF8) do
        k = k + 1
        acc = acc .. ch
        pre[k] = acc
      end
      b.pre[j], b.count[j], b.n = pre, k, b.n + k
      b.lw[j] = K.width(line, SIZE)
      b.tw = max(b.tw, b.lw[j])
    end
    b.h = #lines * lineStep() + PADY * 2 - 0.6
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
    return max(1, n) * lineStep() + PADY * 2 - 0.6
  end
  -- the widest line typed so far of a bubble, `left` letters into it
  local function typedWidth(b, left)
    local tw = 0
    for j = 1, #b.lines do
      if left <= 0 then break end
      local n = b.count[j]
      if left >= n then tw = max(tw, b.lw[j]) else tw = max(tw, K.width(b.pre[j][left], SIZE)) end
      left = left - n
    end
    return tw
  end
  local timeText = K.textCache(function(s) return string.format("%d:%02d", floor(s / 60), s % 60) end)

  -- the "..." bubble's dots, rising one after another
  local function typingDots(bx, by, k, a, clock)
    for d = 0, 2 do
      local s = abs(sin(clock * 6 - d * 0.7))
      K.col(C.soft, (0.45 + 0.55 * s) * a)
      G.circle("fill", K.X(bx + (4.6 + d * 3.9) * k), K.Y(by + (4.6 - s * 1.2) * k), 1.05 * k * K.sc)
    end
  end

  -- a live call's YES / NO (the game's box under ours): two glass pills, the one its cursor is on lit
  local function choiceRow(box, x, y, w, clock)
    local labels = box.labels or {}
    local pw = min(44, (w - 20) / 2)
    local x0 = x + (w - pw * 2 - 4) / 2
    for i = 1, 2 do
      local b = K.R(x0 + (i - 1) * (pw + 4), y, pw, 9)
      local on = box.index == i
      K.glass(b, 4.5, on and 0.95 or 0.55)
      if on then K.ring(b, 4.5, C.green, 0.6 + 0.3 * K.pulse(), 0.6) end
      local word = tostring(labels[i] or (i == 1 and "YES" or "NO"))
      K.bold(word, b[1], b[2] + 2.2, K.fit(word, 4.4, pw - 6), on and C.ink or C.soft, "center", pw)
      K.addHit(b, "win", CHOICE + i)
    end
  end

  -- a hang-up button: red, round, a handset lying across it; a ring calling for it once all is said
  local function endButton(cx, cy, r, glow, clock)
    if glow then
      local p = (clock * 0.9) % 1
      K.col(C.red, 0.55 * (1 - p))
      G.setLineWidth(max(1, 0.6 * K.sc))
      G.circle("line", K.X(cx), K.Y(cy), (r + p * 4) * K.sc)
    end
    K.col(C.black, 0.14)
    G.circle("fill", K.X(cx), K.Y(cy + 0.8), (r + 0.4) * K.sc)
    K.col(C.red)
    G.circle("fill", K.X(cx), K.Y(cy), r * K.sc)
    K.col(C.white, 0.2)
    G.circle("fill", K.X(cx), K.Y(cy - r * 0.45), r * 0.55 * K.sc)
    handset(cx, cy, r * 1.45, 1, pi * 0.75)
    K.addHit(K.R(cx - r - 1, cy - r - 1, r * 2 + 2, r * 2 + 2), "win", END)
  end

  -- the bubbles, newest at the foot, between ay0 and ay1: glass, the newest popping up from its tail and
  -- widening as the words come
  local function drawBubbles(cl, x, ay0, ay1, w, a, t, clock)
    local tw = floor(min(w - 28, 170) - PADX * 2)
    local step = lineStep()
    local most = max(2, min(4, floor((ay1 - ay0 - PADY * 2) / step)))
    if not st.bubbles or st.bubW ~= tw or st.bubL ~= most or st.bubS ~= K.textScale() then
      st.bubbles, st.bubW, st.bubL, st.bubS = buildBubbles(cl.text, tw, most), tw, most, K.textScale()
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
    local sx, sy, sw, sh = clipTo(x, ay0, w, ay1 - ay0)
    local bx = x + 14
    local by = ay1 + cl.lift
    for i = cl.idx, 1, -1 do
      local b = bubbles[i]
      local now_ = i == cl.idx
      local dots = now_ and typing
      local bh = heightOf(cl, b, i, t)
      local bw = b.tw + PADX * 2
      local k = 1
      if now_ and not cl.full then
        local since = t - cl.at
        -- (popping up from its tail, then widening from the dots' size as the words come)
        k = 0.55 + 0.45 * outBack(since / 0.3)
        if dots then bw = 17 else bw = max(17, typedWidth(b, shownOf(cl, b, t)) + PADX * 2) end
      end
      by = by - bh
      if by + bh < ay0 then break end
      -- (fading in as it comes; the older ones fading out as they reach the header)
      local ba = a * min(1, max(0, (by - ay0 + 3) / 9))
      if now_ and not cl.full then ba = ba * min(1, (t - cl.at) / 0.15) end
      local foot = by + bh
      local kb = K.R(bx, foot - bh * k, bw * k, bh * k)
      K.col(C.black, 0.06 * ba)
      K.box("fill", K.R(kb[1], kb[2] + 0.7, kb[3], kb[4]), 4.4 * k)
      K.col(C.bubble, ba)
      K.box("fill", kb, 4.4 * k)
      if now_ then
        -- (the newest: a tail toward the picture beside it)
        G.polygon("fill", K.X(bx + 0.6), K.Y(foot - 4.4 * k), K.X(bx + 4.2 * k), K.Y(foot), K.X(bx - 1.8 * k),
          K.Y(foot + 0.5))
      end
      K.col(LINE_TOP, ba)
      K.box("fill", K.R(kb[1] + 2, kb[2] + 0.5, max(0, kb[3] - 4), 0.6 * k), 0.3)
      K.ring(kb, 4.4 * k, C.white, 0.95 * ba, 0.3)
      if now_ then avatar(cl.pic, cl.name, x + 4.5, foot - 7.6, 7.6, ba) end
      if dots then
        typingDots(bx, foot - 9.2 * k, k, ba, clock)
      else
        local left = now_ and shownOf(cl, b, t) or b.n
        local ly = by + PADY + lineLift()
        for j, line in ipairs(b.lines) do
          local n = b.count[j]
          if left >= n then
            K.text(line, bx + PADX, ly, SIZE, C.ink, nil, nil, ba)
            left = left - n
          else
            if left > 0 then K.text(b.pre[j][left], bx + PADX, ly, SIZE, C.ink, nil, nil, ba) end
            break
          end
          ly = ly + step
        end
        if now_ and cl.idx < #bubbles and shownOf(cl, b, t) >= b.n then
          K.chevron(bx + bw + 3.2, by + bh - 3, 1.8, C.soft, 2, K.pulse() * ba)
        end
      end
      by = by - 2.2
    end
    unclip(sx, sy, sw, sh)
    K.addHit(area, "win", NEXT)
  end

  local function drawCall(x, y, w, h, clock)
    local cl = st.call
    if not cl then return end
    local t = now()
    local since = t - cl.t0
    local f0 = K.getFade()
    K.setFade(f0 * outCubic((clock - mv.callAt) / 0.25))
    -- (e: 0 while it rings, 1 once the picture is up in the header)
    local e = min(1, max(0, (since - DIAL) / SHRINK))
    e = e * e * (3 - 2 * e)
    local cx = x + w / 2
    local big = min(30, h * 0.26)
    local px0, py0 = cx - big / 2, y + max(6, h * 0.3 - big / 2)
    local hs = 11
    local ps = big + (hs - big) * e
    local px, py = px0 + (x + M + 2.5 - px0) * e, py0 + (y + M + 2.5 - py0) * e
    if e > 0 then
      -- (the header's pane, coming as the picture moves up into it)
      local fe = K.getFade()
      K.setFade(fe * e)
      K.glass(K.R(x + M, y + M, w - M * 2, 16), 5, 0.55)
      K.setFade(fe)
    end
    if since < DIAL then
      -- (a light behind it, two rings spreading out of the picture while it rings)
      K.glow(cx, py0 + big / 2, big * 0.95, big * 0.85, C.white, 0.35)
      for k = 0, 1 do
        local p = (clock * 1.2 + k * 0.5) % 1
        K.col(C.green, 0.6 * (1 - p))
        G.setLineWidth(max(1, 0.5 * K.sc))
        G.circle("line", K.X(cx), K.Y(py0 + big / 2), (big / 2 + 1.5 + p * 9) * K.sc)
      end
    end
    -- (the picture popping up as it starts to ring, on its disc)
    local pop = 0.6 + 0.4 * outBack(since / 0.45)
    local s = ps * pop
    local pcx, pcy = px + ps / 2, py + ps / 2
    K.col(C.white, 0.5 * (1 - e))
    G.circle("fill", K.X(pcx), K.Y(pcy), (s / 2 + 1.6) * K.sc)
    avatar(cl.pic, cl.name, pcx - s / 2, pcy - s / 2, s, 1)
    G.setLineWidth(max(1, 0.45 * K.sc))
    K.col(C.white, 0.9)
    G.circle("line", K.X(pcx), K.Y(pcy), s / 2 * K.sc)
    if e < 1 then
      local a = 1 - e
      local name = cl.name or "?"
      K.bold(name, x + 4, py0 + big + 4, K.fit(name, 6.4, w - 8), C.ink, "center", w - 8, a)
      local word = T("phone.calling")
      local ww = K.width(word, 4.4)
      K.text(word, x, py0 + big + 12.5, 4.4, C.soft, "center", w, a)
      local dots = floor(since * 4) % 4
      for i = 1, dots do
        K.col(C.soft, a)
        G.circle("fill", K.X(cx + ww / 2 + i * 2), K.Y(py0 + big + 16.5), 0.5 * K.sc)
      end
    end
    if since >= DIAL then
      -- (the header: the name, a green dot and the time on the call, a waveform while they talk)
      local nx = x + M + 17
      local name = cl.name or "?"
      local tint = tintOf(name)
      -- (the name and the time apart as the text grows: nothing at 100%)
      local gh = (K.textScale() - 1) * 1.5
      K.bold(name, nx, y + M + 2.4 - gh, K.fit(name, 5, w - M * 2 - 34), C.ink, nil, nil, e)
      K.col(C.green, e)
      G.circle("fill", K.X(nx + 1), K.Y(y + M + 10.9 + gh), 0.95 * K.sc)
      local clockText = timeText(floor(max(0, since - DIAL)))
      K.text(clockText, nx + 3, y + M + 8.8 + gh, 3.8, C.greenInk, nil, nil, e)
      local b = st.bubbles and st.bubbles[cl.idx]
      local talking = b and not typingNow(cl, t) and shownOf(cl, b, t) < b.n
      local wx = x + w - M - 13
      for i = 0, 4 do
        local amp = talking and (0.35 + 0.65 * abs(sin(clock * 9 + i * 1.7))) or 0.12
        local bh = 0.8 + 6 * amp
        K.col(tint, 0.85 * e)
        K.box("fill", K.R(wx + i * 1.9, y + M + 8 - bh / 2, 1, bh), 0.5)
      end
      if cl.live then
        -- (the game's box on top, its words so far: every bubble shown whole, the newest last)
        if cl.live.step() then
          cl.text = withoutName(cl.live.text, cl.name)
          st.bubbles, cl.full, cl.idx = nil, true, 1000
        end
        if cl.live.choice then choiceRow(cl.live.choice, x, y + h - 30, w, clock) end
      end
      drawBubbles(cl, x, y + M + 17.5, y + h - (cl.live and cl.live.choice and 32 or 20), w, e, t, clock)
    end
    -- (End)
    local last = st.bubbles and cl.idx >= #st.bubbles and e >= 1 and not (cl.live and not cl.live.done)
    local done = last and st.bubbles[cl.idx] and shownOf(cl, st.bubbles[cl.idx], t) >= st.bubbles[cl.idx].n
    endButton(cx, y + h - 10, 6, done, clock)
    K.setFade(f0)
  end

  -- ------- the whole window

  local function backdrop(body, clock) K.backdrop(body, clock, mv.r, mv.g, mv.b, mv.r2, mv.g2, mv.b2) end

  -- (what changed since the last frame starts its motion; the backdrop turns to who's chosen)
  local function follow(clock, dt)
    if st.tab ~= mv.tab or st.rematchOnly ~= mv.filter then
      if mv.tab ~= nil then mv.rowsAt = clock end
      if mv.tab ~= st.tab then mv.selY, mv.top = nil, st.top end
      mv.tab, mv.filter = st.tab, st.rematchOnly
    end
    mv.tabX = approach(mv.tabX, st.tab, dt, 18)
    mv.filterK = approach(mv.filterK, st.rematchOnly and 1 or 0, dt, 18)
    local r = row()
    local shown = r and (r.contact and r.contact.key or r.recent) or nil
    if shown ~= mv.shown then mv.shown, mv.shownAt = shown, clock end
    -- (back from a call: the card settles in again)
    if mv.view == "call" and st.view ~= "call" then mv.shownAt = clock end
    mv.view = st.view
    if st.call ~= mv.call then mv.call, mv.callAt = st.call, clock end
    local name = st.call and st.call.name or (r and (r.contact and r.contact.name or (r.recent and r.recent.name)))
    local c1 = name and tintOf(name) or C.slate
    local rate = mv.coloured and 7 or 1000
    mv.coloured = true
    mv.r, mv.g, mv.b = approach(mv.r, c1[1] / 255, dt, rate), approach(mv.g, c1[2] / 255, dt, rate),
      approach(mv.b, c1[3] / 255, dt, rate)
    mv.r2 = approach(mv.r2, (c1[1] + (255 - c1[1]) * 0.45) / 255, dt, rate)
    mv.g2 = approach(mv.g2, (c1[2] + (255 - c1[2]) * 0.45) / 255, dt, rate)
    mv.b2 = approach(mv.b2, (c1[3] + (255 - c1[3]) * 0.45) / 255, dt, rate)
  end

  -- narrow: the list, and the card sliding in over it (a back button at its top)
  local function drawNarrow(body, clock, dt)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    mv.push = approach(mv.push, st.view == "card" and 1 or 0, dt, 14)
    local p = outCubic(mv.push)
    if p < 0.999 then
      drawList(x + M - w * 0.3 * p, y + M, w - M * 2, h - M * 2, true, clock, dt, st.view == "list")
      if p > 0.001 then
        K.col(C.black, 0.12 * p)
        K.box("fill", body)
      end
    end
    if p > 0.001 then
      local ox = w * (1 - p)
      if p < 0.999 then
        K.shadow(K.R(x + ox, y, w, h), 0, 0, 0.2)
        backdrop(K.R(x + ox, y, w, h), clock)
        K.scissor(body)
      end
      local bx = x + M + ox
      local label = T("app.phone")
      K.chevron(bx + 2, y + M + 4, 4.2, C.accent, -1)
      K.text(label, bx + 4.8, y + M + 1.5, 4.2, C.accent)
      if st.view == "card" then K.addHit(K.R(bx - 1, y + M - 1, K.width(label, 4.2) + 8, 10), "win", BACK) end
      drawCard(bx, y + M + 10, w - M * 2, h - M * 2 - 10, clock, st.view == "card")
    end
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    G = K.graphics()
    st.clip = body
    st.wide = not portrait and w >= 200
    local dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT = clock
    if not mv.openAt then mv.openAt, mv.rowsAt = clock, clock end
    follow(clock, dt)
    backdrop(body, clock)
    if st.view == "call" then
      drawCall(x, y, w, h, clock)
    elseif st.wide then
      local lw = floor((w - M * 3) * 0.46)
      drawList(x + M, y + M, lw, h - M * 2, st.view == "list", clock, dt, true)
      K.scissor(body)
      drawCard(x + M * 2 + lw, y + M, w - lw - M * 3, h - M * 2, clock, st.view == "card")
    else
      drawNarrow(body, clock, dt)
    end
    K.scissor(body)
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h), UI.red, UI.green, UI.hud) then st.toast = nil end
  end

  -- (opened on a tab: a notification's call opens Recents)
  local resume = ctx.resume and ctx.resume.app == ctx.app and ctx.resume.state
  if type(resume) == "table" and resume.tab == "recents" then st.tab = 2 end
  mv.tabX = st.tab
  refresh()
  return W
end
