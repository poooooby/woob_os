-- The Settings app, after a phone's or a Mac's: a list of settings beside the open one.
--   Language   WoobOS's words in another language (lang/*.lua; the game's own text stays)
--   Wallpaper  the classic colours, five drawn wallpapers, the pictures in wallpapers/ (a picture
--              shows Fill | Stretch by the title: SELECT or a tap switches)
--   Watch      WoobWatch's row in the START menu, the notifications' banners (on / off switches)
-- A choice takes effect at once and is kept for the installation (src/settings.lua).
-- Landscape: the list | the setting; portrait: the list, A opens the setting over it.
--   buttons  Up / Down the setting (then the language, the wallpaper), A open / choose, Left or B
--            back (from the list, B closes)
--   touch    tap a setting, a language, a wallpaper; drag (or the wheel) scrolls the wallpapers
--
--   window(ctx, env) -> win (src/apps.lua); env: T, wall, language() / setLanguage(code),
--   wallpaper() / setWallpaper(id), wallpaperFit() / setWallpaperFit(fit), gameId(),
--   setting(key, default) / setSetting(key, value)

local floor, max, min = math.floor, math.max, math.min

-- the sections' tiles (the rest of the look is the kit's K.UI)
local C = { langTile = { 10, 132, 255 }, wallTile = { 175, 82, 222 }, watchTile = { 255, 69, 58 },
            switchOff = { 120, 120, 128, 0.28 } }
local SECTIONS = {
  { id = "language", key = "settings.language", tile = C.langTile },
  { id = "wallpaper", key = "settings.wallpaper", tile = C.wallTile },
  { id = "watch", key = "settings.watch", tile = C.watchTile },
}
-- the Watch section's rows: switches (the kept setting, its words, on by default) and a choice
-- (the values A / a tap / Left / Right step through)
local SOON_CHOICES = { 5, 10, 15, 30 }
local TOGGLES = {
  { key = "watchRow", label = "settings.watchRow" },
  { key = "notifications", label = "settings.notifications" },
  { key = "soonMinutes", label = "settings.soonAlert", choices = SOON_CHOICES, default = 10 },
}
local ROW_H, LANG_H, TOGGLE_H = 13, 11, 13
local SIDE, LANG, WALL, BACK, FIT, TOGGLE = 1, 100, 200, 300, 400, 500
local FITS = { "fill", "stretch" }
local HINTS = {
  side = { { "A", "hint.open" }, { "B", "hint.close" } },
  detail = { { "A", "hint.choose" }, { "B", "hint.back" } },
  picture = { { "A", "hint.choose" }, { "SELECT", "hint.fit" }, { "B", "hint.back" } },
}
local NO_T = setmetatable({ list = function(l) return l end, f = string.format, languages = function() return {} end },
  { __call = function(_, k) return k end })

return function(ctx, env)
  local K, T, Wall = env.K, env.T or NO_T, env.wall
  local W = { title = "Settings" }
  local function se(name) if env.se then pcall(env.se, name) end end

  local st = {
    section = 1, focus = "side", reading = false, portrait = false,
    langs = {}, langCursor = 1, walls = {}, wallCursor = 1, wallTop = 0, cols = 3, wallRows = 1,
    wallVisible = 2, toggleCursor = 1,
  }
  W.state = st

  local function refresh()
    st.langs = T.languages()
    local code = env.language and env.language() or "en"
    for i, l in ipairs(st.langs) do if l.code == code then st.langCursor = i end end
    st.walls = Wall and Wall.choices() or { { id = "classic", key = "wall.classic" } }
    local id = env.wallpaper and env.wallpaper() or "classic"
    st.wallCursor = 1
    for i, w in ipairs(st.walls) do if w.id == id then st.wallCursor = i end end
  end
  W.refresh = refresh

  local function section() return SECTIONS[st.section].id end
  -- (the wallpaper is one of the player's pictures: it can fill or stretch)
  local function picture() return Wall ~= nil and Wall.isPicture(env.wallpaper and env.wallpaper()) end
  local function fit() return env.wallpaperFit and env.wallpaperFit() or "fill" end
  local function setFit(f)
    if env.setWallpaperFit then env.setWallpaperFit(f) end
    se("SE_SELECT")
  end
  local function count()
    local s = section()
    if s == "watch" then return #TOGGLES end
    return s == "language" and #st.langs or #st.walls
  end
  local function cursor()
    local s = section()
    if s == "watch" then return st.toggleCursor end
    return s == "language" and st.langCursor or st.wallCursor
  end
  local function setCursor(i)
    local s = section()
    if s == "watch" then st.toggleCursor = i
    elseif s == "language" then st.langCursor = i else st.wallCursor = i end
  end
  local function toggled(i)
    local t = TOGGLES[i]
    return t ~= nil and (not env.setting or env.setting(t.key, true) ~= false)
  end
  -- a choice row's value and its place among the choices
  local function choiceOf(t)
    local v = env.setting and tonumber(env.setting(t.key, t.default)) or t.default
    for j, c in ipairs(t.choices) do if c == v then return v, j end end
    return t.default, 1
  end
  local function stepChoice(i, d)
    local t = TOGGLES[i]
    if not (t and t.choices and env.setSetting) then return false end
    local _, j = choiceOf(t)
    j = (j - 1 + d) % #t.choices + 1
    env.setSetting(t.key, t.choices[j])
    se("SE_SELECT")
    return true
  end
  -- (the wallpaper grid's row kept in view)
  local function showWall()
    local row = floor((st.wallCursor - 1) / st.cols)
    if row < st.wallTop then st.wallTop = row end
    if row >= st.wallTop + st.wallVisible then st.wallTop = row - st.wallVisible + 1 end
    st.wallTop = max(0, min(st.wallTop, max(0, st.wallRows - st.wallVisible)))
  end

  local function choose()
    if section() == "watch" then
      local t = TOGGLES[st.toggleCursor]
      if t and t.choices then return stepChoice(st.toggleCursor, 1) end
      if t and env.setSetting then env.setSetting(t.key, not toggled(st.toggleCursor)) end
    elseif section() == "language" then
      local l = st.langs[st.langCursor]
      if l and env.setLanguage then env.setLanguage(l.code) end
    else
      local w = st.walls[st.wallCursor]
      if w and env.setWallpaper then env.setWallpaper(w.id) end
    end
    se("SE_SELECT")
  end
  local function open()
    st.focus = "detail"
    if st.portrait then st.reading = true end
    se("SE_SELECT")
  end
  local function back()
    st.focus, st.reading = "side", false
    se("SE_SELECT")
  end

  -- ------- buttons

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  function W.input(input, nav)
    cur = input
    if st.focus == "side" then
      if pressed("b") then return false end
      if nav.up or nav.down then
        local s = max(1, min(#SECTIONS, st.section + (nav.down and 1 or -1)))
        if s ~= st.section then
          st.section = s
          se("SE_SELECT")
        end
      elseif pressed("a") or (nav.right and not st.portrait) then open()
      end
      return true
    end
    if pressed("b") then
      back()
      return true
    end
    if pressed("a") then
      choose()
      return true
    end
    if pressed("select") and section() == "wallpaper" and picture() then
      setFit(fit() == "fill" and "stretch" or "fill")
      return true
    end
    local n, c = count(), cursor()
    -- (on a choice row Left / Right step its value)
    local tc = section() == "watch" and TOGGLES[st.toggleCursor]
    if tc and tc.choices and (nav.left or nav.right) then
      stepChoice(st.toggleCursor, nav.right and 1 or -1)
      return true
    end
    local step = section() == "wallpaper" and st.cols or 1
    if nav.left and section() == "wallpaper" and (c - 1) % st.cols > 0 then
      setCursor(c - 1)
    elseif nav.left then
      if not st.portrait then back() end
      return true
    elseif nav.right and section() == "wallpaper" and c < n and c % st.cols > 0 then
      setCursor(c + 1)
    elseif nav.up and c - step >= 1 then
      setCursor(c - step)
    elseif nav.down and c + step <= n then
      setCursor(c + step)
    elseif nav.down and section() == "wallpaper" and floor((c - 1) / st.cols) < floor((n - 1) / st.cols) then
      setCursor(n)
    else
      return true
    end
    if section() == "wallpaper" then showWall() end
    se("SE_SELECT")
    return true
  end

  function W.tap(arg)
    if type(arg) ~= "number" then return end
    if arg == BACK then return back() end
    if arg >= FIT and arg < FIT + #FITS then return setFit(FITS[arg - FIT + 1]) end
    if arg >= SIDE and arg < SIDE + #SECTIONS then
      st.section = arg - SIDE + 1
      return open()
    end
    if arg >= WALL and arg < BACK then
      st.section, st.focus, st.wallCursor = 2, "detail", arg - WALL
      return choose()
    end
    if arg >= TOGGLE and arg < TOGGLE + #TOGGLES then
      st.section, st.focus, st.toggleCursor = 3, "detail", arg - TOGGLE + 1
      return choose()
    end
    if arg >= LANG and arg < WALL then
      st.section, st.focus, st.langCursor = 1, "detail", arg - LANG
      return choose()
    end
  end

  function W.scroll(dy)
    if section() ~= "wallpaper" then return end
    st.wallTop = max(0, min(max(0, st.wallRows - st.wallVisible), st.wallTop - dy / 30))
  end

  function W.hints()
    if st.focus == "side" then return T.list(HINTS.side) end
    return T.list((section() == "wallpaper" and picture()) and HINTS.picture or HINTS.detail)
  end

  -- ------- drawing (no tables made here)

  local function tileGlyph(id, x, y, s)
    local G = K.graphics()
    local cx, cy, u = K.X(x + s / 2), K.Y(y + s / 2), s * K.sc
    G.setColor(1, 1, 1, 1)
    G.setLineWidth(max(1, u * 0.08))
    if id == "language" then
      local r = u * 0.3
      G.circle("line", cx, cy, r)
      G.ellipse("line", cx, cy, r * 0.42, r)
      G.line(cx - r, cy, cx + r, cy)
    elseif id == "watch" then
      -- (a watch: its band, the case, two hands)
      G.rectangle("fill", cx - u * 0.12, cy - u * 0.38, u * 0.24, u * 0.76)
      G.rectangle("fill", cx - u * 0.22, cy - u * 0.24, u * 0.44, u * 0.48, u * 0.1, u * 0.1)
      K.col(C.watchTile)
      G.line(cx, cy, cx, cy - u * 0.13)
      G.line(cx, cy, cx + u * 0.1, cy + u * 0.04)
    else
      G.polygon("fill", cx - u * 0.32, cy + u * 0.22, cx - u * 0.08, cy - u * 0.12, cx + u * 0.12, cy + u * 0.22)
      G.polygon("fill", cx - u * 0.02, cy + u * 0.22, cx + u * 0.14, cy, cx + u * 0.32, cy + u * 0.22)
      G.circle("fill", cx + u * 0.18, cy - u * 0.18, u * 0.08)
    end
  end

  local UI = K.UI

  -- the sidebar (System Settings'): a tile and a name per section, the chosen one highlighted
  local function drawSide(x, y, w, h)
    K.col(UI.sidebar)
    K.box("fill", K.R(x, y, w, h))
    for i, sec in ipairs(SECTIONS) do
      local rb = K.R(x + 3, y + 3 + (i - 1) * (ROW_H + 1), w - 6, ROW_H)
      local on = i == st.section
      if on then K.selection(rb, st.focus == "side", 3) end
      local tb = K.R(rb[1] + 2.5, rb[2] + 2, ROW_H - 4, ROW_H - 4)
      K.col(sec.tile)
      K.box("fill", tb, 2.2)
      tileGlyph(sec.id, tb[1], tb[2], tb[3])
      local label = T(sec.key)
      local ink = (on and st.focus == "side") and K.WHITE or UI.label
      local ls = K.fit(label, 4.8, rb[3] - ROW_H - 4)
      K.text(label, rb[1] + ROW_H + 1, rb[2] + 3.4 + (4.8 - ls) * 0.5, ls, ink)
      K.addHit(rb, "win", SIDE + i - 1)
    end
  end

  local function check(x, y, s, c)
    local G = K.graphics()
    K.col(c)
    G.setLineWidth(max(1, s * 0.16 * K.sc))
    G.line(K.X(x), K.Y(y + s * 0.5), K.X(x + s * 0.38), K.Y(y + s * 0.85), K.X(x + s), K.Y(y + s * 0.1))
  end

  local function drawLanguage(x, y, w, h)
    local n = #st.langs
    local gb = K.R(x + 4, y + 13, w - 8, n * LANG_H)
    K.card(gb, 4)
    local code = env.language and env.language() or "en"
    for i, l in ipairs(st.langs) do
      local rb = K.R(gb[1], gb[2] + (i - 1) * LANG_H, gb[3], LANG_H)
      local focused = st.focus == "detail"
      local on = focused and i == st.langCursor
      if on then
        K.selection(K.R(rb[1] + 1, rb[2] + 0.5, rb[3] - 2, rb[4] - 1), true, 3)
      elseif i > 1 and not (focused and i - 1 == st.langCursor) then
        K.hairline(rb[1] + 5, rb[2], rb[3] - 5)
      end
      K.text(l.name, rb[1] + 5, rb[2] + 2.6, 5, on and K.WHITE or UI.label)
      if l.code == code then check(rb[1] + rb[3] - 10, rb[2] + 3, 5, on and K.WHITE or UI.accent) end
      K.addHit(rb, "win", LANG + i)
    end
    K.text(T("settings.languageNote"), x + 6, gb[2] + gb[4] + 3, 4.2, UI.secondary, "left", w - 12)
  end

  local function drawWallpaper(x, y, w, h)
    local gap, noteH = 4, 12
    local gridY, gridH = y + 13, h - 13 - noteH
    -- (thumbnails small enough for two whole rows above the note)
    local cols = max(2, floor((w - 8) / 44))
    local th = min((w - 8 - (cols - 1) * gap) / cols * 0.62, gridH / 2 - 9)
    cols = max(cols, floor((w - 8 + gap) / (th / 0.62 + gap)))
    st.cols = cols
    local tw = (w - 8 - (cols - 1) * gap) / cols
    th = min(tw * 0.62, gridH / 2 - 9)
    local cellH = th + 9
    st.wallRows = math.ceil(#st.walls / cols)
    st.wallVisible = max(1, floor(gridH / cellH))
    local clip = K.R(x, gridY, w, gridH)
    K.scissor(clip)
    local current = env.wallpaper and env.wallpaper() or "classic"
    local top, foot
    if Wall then top, foot = Wall.tint(env.gameId and env.gameId() or "") end
    for i, wp in ipairs(st.walls) do
      local row, c = floor((i - 1) / cols), (i - 1) % cols
      local ty = gridY + (row - st.wallTop) * cellH
      if ty + cellH > gridY - cellH and ty < gridY + gridH + cellH then
        local tb = K.R(x + 4 + c * (tw + gap), ty + 1.5, tw, th)
        local drawn = false
        if wp.id ~= "classic" and Wall then
          local ok, got = pcall(Wall.draw, wp.id, K.X(tb[1]), K.Y(tb[2]), tb[3] * K.sc, tb[4] * K.sc, 2.5 * K.sc,
            fit())
          drawn = ok and got
        end
        if not drawn and top then K.grad(tb, 2.5, top, foot) end
        if wp.id == current then
          K.ring(K.R(tb[1] - 1.2, tb[2] - 1.2, tb[3] + 2.4, tb[4] + 2.4), 3.5, UI.accent, 1, 1)
        end
        if i == st.wallCursor and st.focus == "detail" then
          K.focusRing(K.R(tb[1] - 1.4, tb[2] - 1.4, tb[3] + 2.8, tb[4] + 2.8), 3.6, K.pulse())
        end
        local name = wp.key and T(wp.key) or wp.name
        local ns = K.fit(name, 4.2, tw)
        local ink = wp.id == current and UI.accent or UI.label
        if wp.id == current then K.bold(name, tb[1], tb[2] + th + 1.5, ns, ink, "center", tw)
        else K.text(name, tb[1], tb[2] + th + 1.5, ns, ink, "center", tw) end
        K.addHit(K.R(tb[1], tb[2], tw, cellH - 1), "win", WALL + i, clip)
      end
    end
    K.scissor(nil)
    K.text(T("settings.wallpaperNote"), x + 6, y + h - noteH + 1, 4, UI.secondary, "left", w - 12)
  end

  local minutesText = K.textCache(function(m) return T.f("settings.minutes", m) end)
  -- an on / off switch (iOS's): green with the knob right when on
  local function switch(x, y, on)
    local G = K.graphics()
    local b = K.R(x, y, 14, 8)
    K.col(on and UI.green or C.switchOff)
    K.box("fill", b, 4)
    K.col(K.WHITE)
    G.circle("fill", K.X(x + (on and 10 or 4)), K.Y(y + 4), 3.3 * K.sc)
  end
  local function drawWatch(x, y, w, h)
    local gb = K.R(x + 4, y + 13, w - 8, #TOGGLES * TOGGLE_H)
    K.card(gb, 4)
    for i, t in ipairs(TOGGLES) do
      local rb = K.R(gb[1], gb[2] + (i - 1) * TOGGLE_H, gb[3], TOGGLE_H)
      local on = st.focus == "detail" and i == st.toggleCursor
      if on then K.selection(K.R(rb[1] + 1, rb[2] + 0.5, rb[3] - 2, rb[4] - 1), true, 3)
      elseif i > 1 and not (st.focus == "detail" and i - 1 == st.toggleCursor) then
        K.hairline(rb[1] + 5, rb[2], rb[3] - 5)
      end
      local label = T(t.label)
      local ls = K.fit(label, 5, rb[3] - (t.choices and 34 or 26))
      K.text(label, rb[1] + 5, rb[2] + 3.4 + (5 - ls) * 0.5, ls, on and K.WHITE or UI.label)
      if t.choices then
        -- (the value between < >, as a stepper)
        local v = choiceOf(t)
        local ink = on and K.WHITE or UI.accent
        local vx = rb[1] + rb[3] - 34
        K.chevron(vx + 2, rb[2] + TOGGLE_H / 2, 3.6, ink, -1)
        K.text(minutesText(v), vx + 4, rb[2] + 3.6, 4.6, ink, "center", 21)
        K.chevron(vx + 27, rb[2] + TOGGLE_H / 2, 3.6, ink, 1)
      else
        switch(rb[1] + rb[3] - 19, rb[2] + 2.5, toggled(i))
      end
      K.addHit(rb, "win", TOGGLE + i - 1)
    end
    K.text(T("settings.watchNote"), x + 6, gb[2] + gb[4] + 3, 4.2, UI.secondary, "left", w - 12)
  end

  local function drawDetail(x, y, w, h)
    local sec = SECTIONS[st.section]
    K.bold(T(sec.key), x + 6, y + 3, 6.5, UI.label)
    -- a picture: Fill | Stretch, by the title
    if sec.id == "wallpaper" and picture() then
      local sw = min(64, w * 0.5)
      K.segmented(x + w - sw - 5, y + 2.5, sw, 8, fit() == "fill" and 1 or 2, "win",
        FIT, T("settings.fill"), FIT + 1, T("settings.stretch"))
    end
    if sec.id == "language" then drawLanguage(x, y, w, h)
    elseif sec.id == "watch" then drawWatch(x, y, w, h)
    else drawWallpaper(x, y, w, h) end
  end

  function W.draw(body, clock, portrait)
    st.portrait = portrait
    local x, y, w, h = body[1], body[2], body[3], body[4]
    if portrait then
      if st.reading then
        drawDetail(x, y + 10, w, h - 10)
        K.scissor(body)
        local label = T("nav.back")
        K.chevron(x + 5, y + 5, 4, UI.accent, -1)
        K.text(label, x + 8.5, y + 2.4, 4.6, UI.accent)
        K.addHit(K.R(x + 2, y, K.width(label, 4.6) + 10, 10), "win", BACK)
      else
        drawSide(x, y, w, h)
      end
    else
      local sw = min(90, floor(w * 0.36))
      drawSide(x, y, sw, h)
      K.vline(x + sw, y, h)
      drawDetail(x + sw + 0.6, y, w - sw - 0.6, h)
    end
  end

  refresh()
  return W
end
