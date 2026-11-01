-- The Settings app, after a phone's or a Mac's: a list of settings beside the open one.
--   Language   WoobleOS's words in another language (lang/*.lua; the game's own text stays)
--   Wallpaper  the classic colours, five drawn wallpapers, the pictures in wallpapers/ (a picture
--              shows Fill | Stretch by the title: SELECT or a tap switches)
-- A choice takes effect at once and is kept for the installation (src/settings.lua).
-- Landscape: the list | the setting; portrait: the list, A opens the setting over it.
--   buttons  Up / Down the setting (then the language, the wallpaper), A open / choose, Left or B
--            back (from the list, B closes)
--   touch    tap a setting, a language, a wallpaper; drag (or the wheel) scrolls the wallpapers
--
--   window(ctx, env) -> win (src/apps.lua); env: T, wall, language() / setLanguage(code),
--   wallpaper() / setWallpaper(id), wallpaperFit() / setWallpaperFit(fit), gameId()

local floor, max, min = math.floor, math.max, math.min

local C = {
  ink = { 30, 32, 44 }, soft = { 104, 108, 128 }, faint = { 150, 154, 170 }, accent = { 64, 132, 246 },
  pane = { 255, 255, 255 }, ground = { 242, 242, 247 }, line = { 0, 0, 0 }, wash = { 64, 132, 246, 0.12 },
  langTile = { 64, 132, 246 }, wallTile = { 172, 96, 220 }, chev = { 196, 198, 206 },
}
local SECTIONS = {
  { id = "language", key = "settings.language", tile = C.langTile },
  { id = "wallpaper", key = "settings.wallpaper", tile = C.wallTile },
}
local ROW_H, LANG_H = 13, 11
local SIDE, LANG, WALL, BACK, FIT = 1, 100, 200, 300, 400
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
    wallVisible = 2,
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
  local function count() return section() == "language" and #st.langs or #st.walls end
  local function cursor() return section() == "language" and st.langCursor or st.wallCursor end
  local function setCursor(i)
    if section() == "language" then st.langCursor = i else st.wallCursor = i end
  end
  -- (the wallpaper grid's row kept in view)
  local function showWall()
    local row = floor((st.wallCursor - 1) / st.cols)
    if row < st.wallTop then st.wallTop = row end
    if row >= st.wallTop + st.wallVisible then st.wallTop = row - st.wallVisible + 1 end
    st.wallTop = max(0, min(st.wallTop, max(0, st.wallRows - st.wallVisible)))
  end

  local function choose()
    if section() == "language" then
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
    else
      G.polygon("fill", cx - u * 0.32, cy + u * 0.22, cx - u * 0.08, cy - u * 0.12, cx + u * 0.12, cy + u * 0.22)
      G.polygon("fill", cx - u * 0.02, cy + u * 0.22, cx + u * 0.14, cy, cx + u * 0.32, cy + u * 0.22)
      G.circle("fill", cx + u * 0.18, cy - u * 0.18, u * 0.08)
    end
  end

  local function drawSide(x, y, w, h)
    K.col(C.ground)
    K.box("fill", K.R(x, y, w, h))
    for i, sec in ipairs(SECTIONS) do
      local rb = K.R(x + 3, y + 3 + (i - 1) * (ROW_H + 1), w - 6, ROW_H)
      local on = i == st.section
      if on and st.focus == "side" then
        K.col(C.accent)
        K.box("fill", rb, 3)
      elseif on then
        K.col(C.wash)
        K.box("fill", rb, 3)
      else
        K.col(C.pane)
        K.box("fill", rb, 3)
      end
      local tb = K.R(rb[1] + 2.5, rb[2] + 2, ROW_H - 4, ROW_H - 4)
      K.col(sec.tile)
      K.box("fill", tb, 2.2)
      tileGlyph(sec.id, tb[1], tb[2], tb[3])
      local label = T(sec.key)
      local ink = (on and st.focus == "side") and K.WHITE or C.ink
      local ls = K.fit(label, 4.8, rb[3] - ROW_H - 8)
      K.text(label, rb[1] + ROW_H + 1, rb[2] + 3.4 + (4.8 - ls) * 0.5, ls, ink)
      K.text(">", rb[1] + rb[3] - 6, rb[2] + 3, 5, (on and st.focus == "side") and K.WHITE or C.chev)
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
    K.col(C.pane)
    K.box("fill", gb, 4)
    local code = env.language and env.language() or "en"
    for i, l in ipairs(st.langs) do
      local rb = K.R(gb[1], gb[2] + (i - 1) * LANG_H, gb[3], LANG_H)
      if i == st.langCursor and st.focus == "detail" then
        K.col(C.wash)
        K.box("fill", rb, 4)
      end
      if i > 1 then
        K.col(C.line, 0.08)
        K.box("fill", K.R(rb[1] + 5, rb[2], rb[3] - 5, 0.4))
      end
      K.text(l.name, rb[1] + 5, rb[2] + 2.6, 5, C.ink)
      if l.code == code then check(rb[1] + rb[3] - 10, rb[2] + 3, 5, C.accent) end
      K.addHit(rb, "win", LANG + i)
    end
    K.text(T("settings.languageNote"), x + 6, gb[2] + gb[4] + 3, 4.2, C.soft, "left", w - 12)
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
          local ok, got = pcall(Wall.draw, wp.id, K.X(tb[1]), K.Y(tb[2]), tb[3] * K.sc, tb[4] * K.sc, 2 * K.sc,
            fit())
          drawn = ok and got
        end
        if not drawn and top then K.grad(tb, 2, top, foot) end
        if wp.id == current then
          K.ring(K.R(tb[1] - 1.2, tb[2] - 1.2, tb[3] + 2.4, tb[4] + 2.4), 3, C.accent, 1, 1)
        elseif i == st.wallCursor and st.focus == "detail" then
          K.ring(K.R(tb[1] - 1.2, tb[2] - 1.2, tb[3] + 2.4, tb[4] + 2.4), 3, C.accent, K.pulse() * 0.6, 0.8)
        end
        if i == st.wallCursor and st.focus == "detail" and wp.id == current then
          K.ring(K.R(tb[1] - 2.4, tb[2] - 2.4, tb[3] + 4.8, tb[4] + 4.8), 4, C.accent, K.pulse() * 0.5, 0.6)
        end
        local name = wp.key and T(wp.key) or wp.name
        local ns = K.fit(name, 4.2, tw)
        K.text(name, tb[1], tb[2] + th + 1.5, ns, wp.id == current and C.accent or C.ink, "center", tw)
        K.addHit(K.R(tb[1], tb[2], tw, cellH - 1), "win", WALL + i, clip)
      end
    end
    K.scissor(nil)
    K.text(T("settings.wallpaperNote"), x + 6, y + h - noteH + 1, 4, C.soft, "left", w - 12)
  end

  local function drawDetail(x, y, w, h)
    K.col(C.ground)
    K.box("fill", K.R(x, y, w, h))
    local sec = SECTIONS[st.section]
    K.text(T(sec.key), x + 6, y + 3, 6.5, C.ink)
    K.text(T(sec.key), x + 6.25, y + 3, 6.5, C.ink)
    -- a picture: Fill | Stretch, by the title
    if sec.id == "wallpaper" and picture() then
      local f = fit()
      local sw = min(64, w * 0.5)
      local half = sw / 2
      local bx = x + w - sw - 5
      K.col(C.chev, 0.5)
      K.box("fill", K.R(bx, y + 2.5, sw, 8), 4)
      for i, id in ipairs(FITS) do
        local sb = K.R(bx + (i - 1) * half + 0.6, y + 3.1, half - 1.2, 6.8)
        local on = id == f
        if on then
          K.col(C.pane)
          K.box("fill", sb, 3.4)
        end
        local label = T(id == "fill" and "settings.fill" or "settings.stretch")
        K.text(label, sb[1], sb[2] + 1.2, K.fit(label, 4.2, sb[3] - 2), on and C.accent or C.ink, "center", sb[3])
        K.addHit(sb, "win", FIT + i - 1)
      end
    end
    if sec.id == "language" then drawLanguage(x, y, w, h) else drawWallpaper(x, y, w, h) end
  end

  function W.draw(body, clock, portrait)
    st.portrait = portrait
    local x, y, w, h = body[1], body[2], body[3], body[4]
    if portrait then
      if st.reading then
        drawDetail(x, y + 10, w, h - 10)
        K.scissor(body)
        local label = T("nav.back")
        K.text(label, x + 4, y + 2, 4.6, C.accent)
        K.addHit(K.R(x + 2, y, K.width(label, 4.6) + 6, 10), "win", BACK)
      else
        drawSide(x, y, w, h)
      end
    else
      local sw = min(90, floor(w * 0.36))
      drawSide(x, y, sw, h)
      K.col(C.line, 0.1)
      K.box("fill", K.R(x + sw, y, 0.6, h))
      drawDetail(x + sw + 0.6, y, w - sw - 0.6, h)
    end
  end

  refresh()
  return W
end
