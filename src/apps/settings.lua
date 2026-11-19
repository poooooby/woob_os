-- The Settings app, after a phone's or a Mac's: a list of settings beside the open one.
--   Language   WoobOS's words in another language (lang/*.lua; the game's own text stays)
--   Wallpaper  the classic colours, five drawn wallpapers, the pictures in wallpapers/ (a picture
--              shows Fill | Stretch by the title: SELECT or a tap switches)
--   Notifications  the banners over the field and in the screens, then each app that tells the player
--              things, on or off (with its icon; only the apps installed; the Phone only where calls
--              come: Emerald), R-Bay's ending-soon alert under R-Bay
--   Display    the text size: Normal, Large, Larger (the kit's K.setTextScale, through main.lua)
--   WoobPad    its row in the START menu
--   (a list of switches taller than the window scrolls: buttons follow the cursor, a drag or the wheel)
-- A choice takes effect at once and is kept for the installation (src/settings.lua).
-- Landscape: the list | the setting; portrait: the list, A opens the setting over it.
--   buttons  Up / Down the setting (then the language, the wallpaper), A open / choose, Left or B
--            back (from the list, B closes)
--   touch    tap a setting, a language, a wallpaper; drag (or the wheel) scrolls the wallpapers
-- The look is the Pokédex's glass: panes over a backdrop lit by the open section's colour. Its motion
-- (numbers in `mv`, nothing made while it draws): the sidebar's rows sliding in as it opens and its
-- highlight gliding from section to section, the chosen section's tile popping, the setting's title and
-- card sliding in and its rows rising one after another when the section changes, the chosen row's
-- highlight gliding, the switches' knobs sliding (stretching as they go) and their colour easing, a
-- choice's value sliding in from the side it stepped to, the check popping onto a new language, the
-- wallpapers popping in, the cursor's ring gliding over them, a badge popping onto the one chosen, the
-- lists scrolling smoothly; in portrait the setting slides in over the list.
--
--   window(ctx, env) -> win (src/apps.lua); env: T, wall, language() / setLanguage(code),
--   wallpaper() / setWallpaper(id), wallpaperFit() / setWallpaperFit(fit), gameId(),
--   setting(key, default) / setSetting(key, value), notifications = { apps, setting } (src/notify.lua's
--   Nt.APPS / Nt.SETTING), apps (src/apps.lua: byId, isInstalled), appIcon(app, x, y, size)

local floor, max, min, abs, sin, pi = math.floor, math.max, math.min, math.abs, math.sin, math.pi

-- the sections' tiles (the rest of the look is the kit's K.UI)
local C = { langTile = { 10, 132, 255 }, wallTile = { 175, 82, 222 }, watchTile = { 255, 69, 58 },
            mapTile = { 46, 170, 120 }, navTile = { 255, 92, 160 }, gameTile = { 255, 149, 0 },
            notifyTile = { 255, 59, 48 }, displayTile = { 88, 86, 214 },
            white = { 255, 255, 255 }, black = { 0, 0, 0 } }
-- (a switch's track: off, a grey glass; on, green; eased between)
local OFF_R, OFF_G, OFF_B, OFF_A = 120 / 255, 120 / 255, 128 / 255, 0.3
local ON_R, ON_G, ON_B = 52 / 255, 199 / 255, 89 / 255
-- the WoobPad, Map and PokéNav sections' rows: switches (the kept setting, its words, on by default) and a
-- choice (the values A / a tap / Left / Right step through)
local SOON_CHOICES = { 5, 10, 15, 30 }
-- (Display: the text size, percent; each one's words)
local TEXT_CHOICES = { 100, 115, 130 }
local TEXT_WORDS = { [100] = "settings.textNormal", [115] = "settings.textLarge", [130] = "settings.textLarger" }
local DISPLAY_TOGGLES = {
  { key = "textSize", label = "settings.textSize", choices = TEXT_CHOICES, default = 100, words = TEXT_WORDS },
}
local WATCH_TOGGLES = {
  { key = "watchRow", label = "settings.watchRow" },
}
-- (the Notifications section's rows: made when the window opens, from the apps there are)
local NOTIFY_TOGGLES = {}
local MAP_TOGGLES = {
  { key = "map3d", label = "settings.map3d" },
}
local NAV_TOGGLES = {
  { key = "pokenavApps", label = "settings.pokenavApps" },
}
-- (Gameplay: the Pokédex's row only while the mod's Pokédex option is on; made when the window opens)
local DEX_TOGGLE, SWARM_TOGGLE = { key = "pokedexApp", label = "settings.pokedexApp" },
  { key = "swarms", label = "settings.swarms" }
local GAME_TOGGLES = { DEX_TOGGLE, SWARM_TOGGLE }
local ALL_SECTIONS = {
  { id = "language", key = "settings.language", tile = C.langTile },
  { id = "wallpaper", key = "settings.wallpaper", tile = C.wallTile },
  { id = "display", key = "settings.display", tile = C.displayTile, toggles = DISPLAY_TOGGLES,
    note = "settings.displayNote" },
  { id = "notify", key = "settings.notifications", tile = C.notifyTile, toggles = NOTIFY_TOGGLES,
    note = "settings.notifyNote" },
  { id = "watch", key = "settings.watch", tile = C.watchTile, toggles = WATCH_TOGGLES, note = "settings.watchNote",
    pad = true },
  { id = "map", key = "settings.map", tile = C.mapTile, toggles = MAP_TOGGLES, note = "settings.mapNote" },
  { id = "pokenav", key = "settings.pokenav", tile = C.navTile, toggles = NAV_TOGGLES, note = "settings.pokenavNote",
    family = "rse", pad = true },
  { id = "game", key = "settings.game", tile = C.gameTile, toggles = GAME_TOGGLES, note = "settings.gameNote" },
}
-- (a switch's hit: TOGGLE + its section's place * 20 + its row)
local TOGGLE_SPAN = 20
local M, GAP = 3, 2
local ROW_H, LANG_H, TOGGLE_H, TITLE_H = 13, 11, 13, 12
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
  -- (the sections this game has: the PokéNav's only on Ruby / Sapphire / Emerald; WoobPad's and the
  -- PokéNav's only while the mod's WoobPad option is on)
  local SECTIONS = {}
  local padOff = env.padOption and not env.padOption()
  for _, sec in ipairs(ALL_SECTIONS) do
    if not (sec.family and ctx and ctx.family and ctx.family ~= sec.family) and not (sec.pad and padOff) then
      SECTIONS[#SECTIONS + 1] = sec
    end
  end
  local function se(name) if env.se then pcall(env.se, name) end end

  local st = {
    section = 1, focus = "side", reading = false, portrait = false,
    langs = {}, langCursor = 1, walls = {}, wallCursor = 1, wallTop = 0, cols = 3, wallRows = 1,
    wallVisible = 2, toggleCursor = 1, toggleTop = 0, toggleVisible = 6,
  }
  W.state = st
  W.SECTIONS = SECTIONS

  -- the Notifications rows: the banners, then each app that tells the player things (installed; the
  -- Phone only where calls come), R-Bay's ending-soon alert under R-Bay
  local function notifyRows()
    for i = #NOTIFY_TOGGLES, 1, -1 do NOTIFY_TOGGLES[i] = nil end
    NOTIFY_TOGGLES[1] = { key = "notifications", label = "settings.banners" }
    local N, A = env.notifications, env.apps
    for _, id in ipairs(N and N.apps or {}) do
      local app = A and A.byId and A.byId(id)
      local shown = app ~= nil and (not A.isInstalled or A.isInstalled(id))
      if id == "phone" and env.gameId and env.gameId() ~= "emerald" then shown = false end
      if shown and N.setting[id] then
        NOTIFY_TOGGLES[#NOTIFY_TOGGLES + 1] = { key = N.setting[id], label = app.labelKey or ("app." .. id), app = app }
        if id == "auction" then
          NOTIFY_TOGGLES[#NOTIFY_TOGGLES + 1] = { key = "soonMinutes", label = "settings.soonAlert",
                                                  choices = SOON_CHOICES, default = 10, under = true }
        end
      end
    end
  end

  local function gameRows()
    for i = #GAME_TOGGLES, 1, -1 do GAME_TOGGLES[i] = nil end
    if not env.dexOption or env.dexOption() then GAME_TOGGLES[#GAME_TOGGLES + 1] = DEX_TOGGLE end
    GAME_TOGGLES[#GAME_TOGGLES + 1] = SWARM_TOGGLE
  end

  local function refresh()
    notifyRows()
    gameRows()
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
  -- the section's switches (WoobPad, Map, PokéNav), nil for the others
  local function toggles()
    local list = SECTIONS[st.section].toggles
    if list and st.toggleCursor > #list then st.toggleCursor = #list end
    return list
  end
  -- (the wallpaper is one of the player's pictures: it can fill or stretch)
  local function picture() return Wall ~= nil and Wall.isPicture(env.wallpaper and env.wallpaper()) end
  local function fit() return env.wallpaperFit and env.wallpaperFit() or "fill" end
  local function setFit(f)
    if env.setWallpaperFit then env.setWallpaperFit(f) end
    se("SE_SELECT")
  end
  local function count()
    local s = section()
    if toggles() then return #toggles() end
    return s == "language" and #st.langs or #st.walls
  end
  local function cursor()
    local s = section()
    if toggles() then return st.toggleCursor end
    return s == "language" and st.langCursor or st.wallCursor
  end
  -- (a long list of switches: the cursor's row kept in view)
  local function showToggle()
    local c = st.toggleCursor
    if c <= st.toggleTop then st.toggleTop = c - 1 end
    if c > st.toggleTop + st.toggleVisible then st.toggleTop = c - st.toggleVisible end
  end
  local function setCursor(i)
    local s = section()
    if toggles() then
      st.toggleCursor = i
      showToggle()
    elseif s == "language" then st.langCursor = i else st.wallCursor = i end
  end
  local function toggled(i)
    local t = toggles() and toggles()[i]
    return t ~= nil and (not env.setting or env.setting(t.key, true) ~= false)
  end
  -- a choice row's value and its place among the choices
  local function choiceOf(t)
    local v = env.setting and tonumber(env.setting(t.key, t.default)) or t.default
    for j, c in ipairs(t.choices) do if c == v then return v, j end end
    return t.default, 1
  end
  local function stepChoice(i, d)
    local t = toggles() and toggles()[i]
    if not (t and t.choices and env.setSetting) then return false end
    local _, j = choiceOf(t)
    j = (j - 1 + d) % #t.choices + 1
    env.setSetting(t.key, t.choices[j])
    t.dir = d > 0 and 1 or -1
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
    if toggles() then
      local t = toggles()[st.toggleCursor]
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
          st.section, st.toggleCursor, st.toggleTop = s, 1, 0
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
    local tc = toggles() and toggles()[st.toggleCursor]
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
      if st.section ~= arg - SIDE + 1 then st.toggleCursor, st.toggleTop = 1, 0 end
      st.section = arg - SIDE + 1
      return open()
    end
    if arg >= WALL and arg < BACK then
      st.section, st.focus, st.wallCursor = 2, "detail", arg - WALL
      return choose()
    end
    if arg >= TOGGLE and arg < TOGGLE + TOGGLE_SPAN * (#SECTIONS + 1) then
      local si, i = floor((arg - TOGGLE) / TOGGLE_SPAN), (arg - TOGGLE) % TOGGLE_SPAN + 1
      if SECTIONS[si] and SECTIONS[si].toggles and SECTIONS[si].toggles[i] then
        if st.section ~= si then st.toggleCursor, st.toggleTop = 1, 0 end
        st.section, st.focus, st.toggleCursor = si, "detail", i
        return choose()
      end
      return
    end
    if arg >= LANG and arg < WALL then
      st.section, st.focus, st.langCursor = 1, "detail", arg - LANG
      return choose()
    end
  end

  function W.scroll(dy)
    local list = toggles()
    if list then
      st.toggleTop = max(0, min(max(0, #list - st.toggleVisible), st.toggleTop - dy / TOGGLE_H))
      return
    end
    if section() ~= "wallpaper" then return end
    st.wallTop = max(0, min(max(0, st.wallRows - st.wallVisible), st.wallTop - dy / 30))
  end

  function W.hints()
    if st.focus == "side" then return T.list(HINTS.side) end
    return T.list((section() == "wallpaper" and picture()) and HINTS.picture or HINTS.detail)
  end

  -- ------- drawing (no tables, closures or strings made here)

  local UI = K.UI
  local G = nil
  local outCubic, outBack, approach, rise, settle, stagger = K.outCubic, K.outBack, K.approach, K.rise, K.settle,
    K.stagger
  -- the motion's numbers: when the window opened, when the section last changed (its rows rise again),
  -- the sidebar's highlight, the chosen row's, the cursor's ring over the wallpapers, the eased scrolls,
  -- the Fill | Stretch thumb, the portrait page's slide, the backdrop's colours
  local mv = { lastT = nil, openAt = nil, sec = nil, secAt = -10, reading = false, sideY = 1, rowY = 1, rowSec = nil,
               focusK = 0, push = 0, ttop = 0, wtop = 0, wx = 0, wy = 0, wallSec = nil, fitX = 1, lang = nil,
               langAt = -10, wall = nil, wallAt = -10, coloured = false,
               r = 0.5, g = 0.5, b = 0.5, r2 = 0.5, g2 = 0.5, b2 = 0.5 }
  W.motion = mv
  -- (the portrait page's slide, units: the clips follow it; the body, the scissor put back)
  local offX, bodyNow = 0, nil
  local function clip(x, y, w, h) return K.R(x + offX, y, w, h) end

  -- a note under a card at a bigger text size: as big as lets its lines (wrapped at w) fit down to the
  -- body's foot, never smaller than at 100%; when no bigger size fits, as it is at 100% (100%: as it was).
  -- Worked out when the words, the width, the room or the size change, kept per note
  local noteFits = {}
  local function noteFits1(s, try, size, w, room, ts)
    local big = try * ts
    local f = K.font(big * K.sc)
    local lh = f:getHeight() / K.sc
    local n = 1
    if K.width(s, try / ts) <= w + 0.01 then
      -- (one that fits its width at `try` the kit keeps on one line, shrunk into it: only when that isn't
      -- smaller than at 100%)
      if K.width(s, size / ts) > w + 0.01 then return false end
    else
      local ok, _, lines = pcall(f.getWrap, f, s, w * K.sc)
      n = ok and type(lines) == "table" and #lines or 99
    end
    return n * lh - (big - try) * 0.6 <= room
  end
  local function drawNote(s, x, y, size, w)
    local ts = K.textScale()
    if ts == 1 or not bodyNow then return K.text(s, x, y, size, UI.secondary, "left", w) end
    local room = bodyNow[2] + bodyNow[4] - 0.5 - y
    local m = noteFits[s]
    if not m then
      m = {}
      noteFits[s] = m
    end
    if not (m.w == w and m.room == room and m.ts == ts and m.sc == K.sc and m.size == size) then
      local lo = size / ts
      local out, try = false, size
      for _ = 1, 16 do
        if try < lo then break end
        if noteFits1(s, try, size, w, room, ts) then
          out = try
          break
        end
        try = try > lo and max(lo, try * 0.96) or lo * 0.5
      end
      m.w, m.room, m.ts, m.sc, m.size, m.out = w, room, ts, K.sc, size, out
    end
    if m.out then return K.text(s, x, y, m.out, UI.secondary, "left", w) end
    K.setTextScale(1)
    K.text(s, x, y, size, UI.secondary, "left", w)
    K.setTextScale(ts)
  end

  local function tileGlyph(id, x, y, s)
    local cx, cy, u = K.X(x + s / 2), K.Y(y + s / 2), s * K.sc
    K.col(C.white)
    G.setLineWidth(max(1, u * 0.08))
    if id == "display" then
      -- (Aa: a big A and a small one, stroked)
      G.setLineWidth(max(1, u * 0.09))
      G.line(cx - u * 0.36, cy + u * 0.26, cx - u * 0.15, cy - u * 0.28, cx + u * 0.06, cy + u * 0.26)
      G.line(cx - u * 0.27, cy + u * 0.06, cx - u * 0.03, cy + u * 0.06)
      G.setLineWidth(max(1, u * 0.07))
      G.line(cx + u * 0.1, cy + u * 0.26, cx + u * 0.23, cy - u * 0.04, cx + u * 0.36, cy + u * 0.26)
      G.line(cx + u * 0.15, cy + u * 0.15, cx + u * 0.31, cy + u * 0.15)
    elseif id == "language" then
      local r = u * 0.3
      G.circle("line", cx, cy, r)
      G.ellipse("line", cx, cy, r * 0.42, r)
      G.line(cx - r, cy, cx + r, cy)
    elseif id == "watch" then
      -- (WoobPad: a tablet, its screen)
      G.rectangle("fill", cx - u * 0.32, cy - u * 0.24, u * 0.64, u * 0.48, u * 0.08, u * 0.08)
      K.col(C.watchTile)
      G.rectangle("fill", cx - u * 0.25, cy - u * 0.17, u * 0.5, u * 0.34, u * 0.04, u * 0.04)
    elseif id == "pokenav" then
      -- (a PokéNav: a rounded body, its screen)
      G.rectangle("fill", cx - u * 0.26, cy - u * 0.3, u * 0.52, u * 0.6, u * 0.12, u * 0.12)
      K.col(C.navTile)
      G.rectangle("fill", cx - u * 0.17, cy - u * 0.2, u * 0.34, u * 0.24, u * 0.04, u * 0.04)
    elseif id == "game" then
      -- (a flag on a pole: the day's events)
      G.rectangle("fill", cx - u * 0.22, cy - u * 0.3, u * 0.06, u * 0.6)
      G.polygon("fill", cx - u * 0.16, cy - u * 0.3, cx + u * 0.3, cy - u * 0.17, cx - u * 0.16, cy - u * 0.04)
    elseif id == "notify" then
      -- (a bell: its dome, its rim, the clapper)
      G.arc("fill", "pie", cx, cy + u * 0.02, u * 0.22, pi, pi * 2, 16)
      G.rectangle("fill", cx - u * 0.22, cy + u * 0.02, u * 0.44, u * 0.12)
      G.rectangle("fill", cx - u * 0.3, cy + u * 0.13, u * 0.6, u * 0.06, u * 0.03, u * 0.03)
      G.circle("fill", cx, cy + u * 0.26, u * 0.06)
      G.circle("fill", cx, cy - u * 0.22, u * 0.04)
    elseif id == "map" then
      -- (a folded map, a pin on it)
      G.polygon("fill", cx - u * 0.3, cy - u * 0.16, cx - u * 0.1, cy - u * 0.1, cx - u * 0.1, cy + u * 0.24, cx - u * 0.3, cy + u * 0.18)
      G.polygon("fill", cx + u * 0.1, cy - u * 0.16, cx + u * 0.3, cy - u * 0.1, cx + u * 0.3, cy + u * 0.24, cx + u * 0.1, cy + u * 0.18)
      K.col(C.white, 0.65)
      G.polygon("fill", cx - u * 0.1, cy - u * 0.1, cx + u * 0.1, cy - u * 0.16, cx + u * 0.1, cy + u * 0.18, cx - u * 0.1, cy + u * 0.24)
    else
      G.polygon("fill", cx - u * 0.32, cy + u * 0.22, cx - u * 0.08, cy - u * 0.12, cx + u * 0.12, cy + u * 0.22)
      G.polygon("fill", cx - u * 0.02, cy + u * 0.22, cx + u * 0.14, cy, cx + u * 0.32, cy + u * 0.22)
      G.circle("fill", cx + u * 0.18, cy - u * 0.18, u * 0.08)
    end
  end

  -- (drawn `s` times its size round cx, cy (units) until unpop: something popping in)
  local function pop(s, cx, cy)
    if s == 1 then return false end
    local px, py = K.X(cx), K.Y(cy)
    G.push()
    G.translate(px, py)
    G.scale(max(0.001, s))
    G.translate(-px, -py)
    return true
  end

  -- a check mark s units square at x, y
  local function check(x, y, s, c, a)
    K.col(c, a)
    G.setLineWidth(max(1, s * 0.16 * K.sc))
    G.line(K.X(x), K.Y(y + s * 0.5), K.X(x + s * 0.38), K.Y(y + s * 0.85), K.X(x + s), K.Y(y + s * 0.1))
  end

  -- the chosen row's highlight, gliding (row `at`, 1-based, of rows `rh` tall from y) while the setting
  -- has the focus
  local function rowHighlight(x, y, w, rh, at)
    if mv.focusK < 0.01 then return end
    local hb = K.R(x + 1, y + (at - 1) * rh + 0.5, w - 2, rh - 1)
    K.col(UI.accent, 0.13 * mv.focusK)
    K.box("fill", hb, 3)
    K.ring(hb, 3, UI.accent, 0.9 * mv.focusK, 0.6)
  end
  -- (the gliding row follows `target`; on another section it starts there)
  local function glide(target, dt)
    if mv.rowSec ~= st.section then
      mv.rowSec, mv.rowY = st.section, target
    else
      mv.rowY = approach(mv.rowY, target, dt, 24)
    end
  end

  -- what a section is set to, for the portrait list (the language's name, the wallpaper's)
  local function valueOf(id)
    if id == "language" then
      local code = env.language and env.language() or "en"
      for i = 1, #st.langs do if st.langs[i].code == code then return st.langs[i].name end end
    elseif id == "wallpaper" then
      local current = env.wallpaper and env.wallpaper() or "classic"
      for i = 1, #st.walls do
        local wp = st.walls[i]
        if wp.id == current then return wp.key and T(wp.key) or wp.name end
      end
    elseif id == "display" then
      local t = DISPLAY_TOGGLES[1]
      local v = env.setting and tonumber(env.setting(t.key, t.default)) or t.default
      return T(TEXT_WORDS[v] or TEXT_WORDS[100])
    end
    return nil
  end

  -- the sidebar (System Settings'): a pane of glass, a tile and a name per section, the chosen one's
  -- highlight gliding to it (the accent while the list has the focus); in portrait the whole list, with
  -- what each is set to and a chevron
  local function drawSide(x, y, w, h, clock, dt, live, full)
    -- (beside the setting, every section in the pane: rows a little shorter when there are more than fit;
    -- in portrait the pane as tall as its rows)
    local rh = full and ROW_H or min(ROW_H, (h - 5) / #SECTIONS - 1)
    local step = rh + 1
    local dy = (rh - ROW_H) / 2
    if full then h = min(h, 5 + #SECTIONS * step) end
    K.glass(K.R(x, y, w, h), 5, 0.42)
    local y0 = y + 3
    mv.sideY = approach(mv.sideY, st.section, dt, 22)
    local sideFocus = st.focus == "side"
    local hb = K.R(x + 2.5, y0 + (mv.sideY - 1) * step, w - 5, rh)
    if sideFocus then
      K.col(UI.accent, 0.92)
      K.box("fill", hb, 3.5)
    else
      K.col(C.white, 0.72)
      K.box("fill", hb, 3.5)
      K.ring(hb, 3.5, C.white, 0.9, 0.35)
    end
    local since = clock - mv.openAt
    local ts = rh - 4
    for i, sec in ipairs(SECTIONS) do
      local e = stagger(since, i, 0.035, 0.3)
      rise(e, 0, -6)
      local rb = K.R(x + 2.5, y0 + (i - 1) * step, w - 5, rh)
      local lit = sideFocus and abs(mv.sideY - i) < 0.5
      -- (its tile: the chosen one pops as it's chosen)
      local tb = K.R(rb[1] + 2, rb[2] + 2, ts, ts)
      local t = clock - mv.secAt
      local popped = i == st.section and t < 0.34 and pop(0.78 + 0.22 * outBack(t / 0.34), tb[1] + ts / 2,
        tb[2] + ts / 2)
      K.grad(tb, 2.6, K.light(sec.tile, 0.16), K.dark(sec.tile, 0.08))
      K.ring(tb, 2.6, C.white, 0.3, 0.3)
      tileGlyph(sec.id, tb[1], tb[2], ts)
      if popped then G.pop() end
      local label = T(sec.key)
      local lx = rb[1] + ts + 5
      local right = full and 8 or 2
      local value = full and valueOf(sec.id) or nil
      local vw = value and min(K.width(value, 4.2), rb[3] * 0.4) or 0
      local ls = K.fit(label, 4.8, rb[1] + rb[3] - lx - right - vw - (value and 3 or 0))
      local ink = lit and C.white or UI.label
      if i == st.section then K.bold(label, lx, rb[2] + 3.4 + dy + (4.8 - ls) * 0.5, ls, ink)
      else K.text(label, lx, rb[2] + 3.4 + dy + (4.8 - ls) * 0.5, ls, ink) end
      if value then
        K.text(value, rb[1] + rb[3] - right - vw, rb[2] + 3.9 + dy, K.fit(value, 4.2, vw), lit and C.white or UI.secondary,
          "right", vw, lit and 0.85 or 1)
      end
      if full then K.chevron(rb[1] + rb[3] - 4, rb[2] + rh / 2, 3.4, lit and C.white or UI.tertiary, 1) end
      settle(e)
      if live then K.addHit(rb, "win", SIDE + i - 1) end
    end
  end

  local function drawLanguage(x, y, w, h, clock, dt, live)
    local n = #st.langs
    local ce = outCubic((clock - mv.secAt - 0.03) / 0.32)
    rise(ce, 6)
    local gb = K.R(x, y + TITLE_H, w, n * LANG_H)
    K.glass(gb, 4)
    glide(st.langCursor, dt)
    rowHighlight(gb[1], gb[2], gb[3], LANG_H, mv.rowY)
    local code = env.language and env.language() or "en"
    if code ~= mv.lang then
      if mv.lang ~= nil then mv.langAt = clock end
      mv.lang = code
    end
    local since = clock - mv.secAt
    local focused = st.focus == "detail"
    for i, l in ipairs(st.langs) do
      local e = stagger(since, i, 0.03, 0.26)
      rise(e, 3)
      local rb = K.R(gb[1], gb[2] + (i - 1) * LANG_H, gb[3], LANG_H)
      local on = focused and i == st.langCursor
      if i > 1 and not (focused and (i == st.langCursor or i - 1 == st.langCursor)) then
        K.hairline(rb[1] + 5, rb[2], rb[3] - 5)
      end
      if l.code == code then K.bold(l.name, rb[1] + 5, rb[2] + 2.6, 5, on and UI.accent or UI.label)
      else K.text(l.name, rb[1] + 5, rb[2] + 2.6, 5, on and UI.accent or UI.label) end
      if l.code == code then
        -- (the check pops onto the language just chosen)
        local t = clock - mv.langAt
        local s = t < 0.36 and outBack(t / 0.36) or 1
        local cs = 5 * s
        check(rb[1] + rb[3] - 7.5 - cs / 2, rb[2] + 5.5 - cs / 2, cs, UI.accent)
      end
      settle(e)
      if live then K.addHit(rb, "win", LANG + i) end
    end
    local note, ny = T("settings.languageNote"), gb[2] + gb[4] + 3
    drawNote(note, x + 2, ny, 4.2, w - 4)
    settle(ce)
  end

  local function drawWallpaper(x, y, w, h, clock, dt, live)
    local gap, noteH = 4, 12
    local gridY, gridH = y + TITLE_H, h - TITLE_H - noteH
    -- (thumbnails small enough for two whole rows above the note)
    local cols = max(2, floor(w / 44))
    local th = min((w - (cols - 1) * gap) / cols * 0.62, gridH / 2 - 9)
    cols = max(cols, floor((w + gap) / (th / 0.62 + gap)))
    st.cols = cols
    local tw = (w - (cols - 1) * gap) / cols
    th = min(tw * 0.62, gridH / 2 - 9)
    local cellH = th + 9
    st.wallRows = math.ceil(#st.walls / cols)
    st.wallVisible = max(1, floor(gridH / cellH))
    st.wallTop = max(0, min(st.wallTop, max(0, st.wallRows - st.wallVisible)))
    -- (the scroll and the cursor's ring eased; snapped as the section opens)
    local cr, cc = floor((st.wallCursor - 1) / cols), (st.wallCursor - 1) % cols
    if mv.wallSec ~= st.section or mv.wallCols ~= cols then
      mv.wallSec, mv.wallCols, mv.wtop, mv.wx, mv.wy = st.section, cols, st.wallTop, cc, cr
    else
      mv.wtop = approach(mv.wtop, st.wallTop, dt, 18)
      mv.wx, mv.wy = approach(mv.wx, cc, dt, 24), approach(mv.wy, cr, dt, 24)
    end
    local current = env.wallpaper and env.wallpaper() or "classic"
    if current ~= mv.wall then
      if mv.wall ~= nil then mv.wallAt = clock end
      mv.wall = current
    end
    local area = clip(x - 3, gridY, w + 6, gridH)
    K.scissor(area)
    local top, foot
    if Wall then top, foot = Wall.tint(env.gameId and env.gameId() or "") end
    local since = clock - mv.secAt
    for i, wp in ipairs(st.walls) do
      local row, c = floor((i - 1) / cols), (i - 1) % cols
      local ty = gridY + (row - mv.wtop) * cellH
      if ty + cellH > gridY - cellH and ty < gridY + gridH + cellH then
        local tb = K.R(x + c * (tw + gap), ty + 1.5, tw, th)
        -- (popping in one after another as the section opens; its name rising under it)
        local pt = since < 2 and (since - i * 0.035) / 0.38 or 1
        local e = outCubic(pt)
        rise(e, 3)
        local popped = pt < 1 and pop(max(0, outBack(pt)), tb[1] + tw / 2, tb[2] + th / 2)
        K.shadow(tb, 2.5, 0.8, 0.16)
        local drawn = false
        if wp.id ~= "classic" and Wall then
          local ok, got = pcall(Wall.draw, wp.id, K.X(tb[1]), K.Y(tb[2]), tb[3] * K.sc, tb[4] * K.sc, 2.5 * K.sc,
            fit(), K.getFade())
          drawn = ok and got
          -- (a wallpaper painted just now drew into a canvas: the scissor set again)
          K.rescissor()
        end
        if not drawn and top then K.grad(tb, 2.5, top, foot) end
        K.ring(tb, 2.5, C.white, 0.85, 0.4)
        if wp.id == current then
          K.ring(K.R(tb[1] - 1.2, tb[2] - 1.2, tb[3] + 2.4, tb[4] + 2.4), 3.5, UI.accent, 1, 1)
          -- (a badge popping onto the one just chosen)
          local bt = clock - mv.wallAt
          local s = bt < 0.4 and outBack(bt / 0.4) or 1
          local bx, by, br = tb[1] + tw - 3.2, tb[2] + 3.2, 2.6 * s
          K.col(UI.accent)
          G.circle("fill", K.X(bx), K.Y(by), br * K.sc)
          K.col(C.white, 0.9)
          G.setLineWidth(max(1, 0.3 * K.sc))
          G.circle("line", K.X(bx), K.Y(by), br * K.sc)
          check(bx - br * 0.5, by - br * 0.42, br, C.white)
        end
        if popped then G.pop() end
        local name = wp.key and T(wp.key) or wp.name
        local ns = K.fit(name, 4.2, tw)
        -- (at a bigger text size it grows down, clear of the rings round the picture, as far as its cell
        -- has room under it)
        local g = (K.textScale() - 1) * ns * 0.6
        local ny = tb[2] + th + 1.5 + max(0, min(g, 5.8 + g - 1.16 * K.textScale() * ns))
        if wp.id == current then K.bold(name, tb[1], ny, ns, UI.accent, "center", tw)
        else K.text(name, tb[1], ny, ns, UI.label, "center", tw) end
        settle(e)
        if live then K.addHit(K.R(tb[1], tb[2], tw, cellH - 1), "win", WALL + i, area) end
      end
    end
    -- (the cursor's ring, gliding from picture to picture)
    if mv.focusK > 0.01 then
      local rb = K.R(x + mv.wx * (tw + gap) - 2, gridY + (mv.wy - mv.wtop) * cellH - 0.5, tw + 4, th + 4)
      K.ring(rb, 4, UI.accent, (0.45 + 0.4 * K.pulse()) * mv.focusK, 0.9)
    end
    K.scissor(bodyNow)
    if st.wallRows > st.wallVisible then
      K.scrollbar(x + w + 2.5, gridY, gridH, mv.wtop, st.wallVisible, st.wallRows)
    end
    local note, ny = T("settings.wallpaperNote"), y + h - noteH + 1
    drawNote(note, x + 2, ny, 4, w - 4)
  end

  local minutesText = K.textCache(function(m) return T.f("settings.minutes", m) end)
  -- an on / off switch (iOS's) in glass: its knob sliding (stretching as it goes) and the track easing
  -- from grey glass to green; t keeps where its knob is
  local function switch(x, y, on, t, dt)
    local target = on and 1 or 0
    local k = t.knob
    if k == nil then k = target else k = approach(k, target, dt, 16) end
    t.knob = k
    local b = K.R(x, y, 14, 8)
    G.setColor(OFF_R + (ON_R - OFF_R) * k, OFF_G + (ON_G - OFF_G) * k, OFF_B + (ON_B - OFF_B) * k,
      (OFF_A + (1 - OFF_A) * k) * K.getFade())
    K.box("fill", b, 4)
    K.ring(b, 4, C.white, 0.75 - 0.45 * k, 0.3)
    local kw = 6.6 + 1.8 * sin(pi * k)
    local kx = x + 0.7 + (14 - 1.4 - kw) * k
    K.col(C.black, 0.14)
    K.box("fill", K.R(kx, y + 1.1, kw, 6.6), 3.3)
    K.col(C.white)
    K.box("fill", K.R(kx, y + 0.7, kw, 6.6), 3.3)
  end
  -- one row of switches: its words (an app's after its icon, popping in; a row under another set in
  -- line with its words), then its switch or its value between < > in a capsule
  local function drawToggleRow(i, t, rb, area, e, clock, dt, live)
    rise(e, 3)
    local on = st.focus == "detail" and i == st.toggleCursor
    if i > 1 and not (st.focus == "detail" and (i == st.toggleCursor or i - 1 == st.toggleCursor)) then
      K.hairline(rb[1] + 5, rb[2], rb[3] - 5)
    end
    local lx = rb[1] + 5
    if t.app and env.appIcon then
      local is = TOGGLE_H - 4
      local popped = e < 1 and pop(outBack(e), rb[1] + 4 + is / 2, rb[2] + 2 + is / 2)
      pcall(env.appIcon, t.app, rb[1] + 4, rb[2] + 2, is)
      if popped then G.pop() end
      lx = rb[1] + TOGGLE_H + 3
    elseif t.under then
      lx = rb[1] + TOGGLE_H + 3
    end
    local label = T(t.label)
    local ls = K.fit(label, 5, rb[1] + rb[3] - lx - (t.choices and 37 or 21))
    K.text(label, lx, rb[2] + 3.4 + (5 - ls) * 0.5, ls, on and UI.accent or (t.under and UI.secondary or UI.label))
    if t.choices then
      local v = choiceOf(t)
      if t.shown == nil then t.shown, t.at = v, -10
      elseif t.shown ~= v then t.shown, t.at = v, clock end
      local vb = K.R(rb[1] + rb[3] - 36, rb[2] + 2.5, 32, 8)
      K.col(C.white, on and 0.85 or 0.55)
      K.box("fill", vb, 4)
      K.ring(vb, 4, on and UI.accent or C.white, on and 0.8 or 0.8, 0.35)
      K.chevron(vb[1] + 3.5, vb[2] + 4, 3.4, UI.accent, -1)
      K.chevron(vb[1] + vb[3] - 3.5, vb[2] + 4, 3.4, UI.accent, 1)
      -- (the new value sliding in from the side it stepped to)
      local ve = outCubic((clock - t.at) / 0.24)
      rise(ve, 0, 3 * (t.dir or 1))
      local vt = t.words and T(t.words[t.shown] or "") or minutesText(t.shown)
      -- (at a bigger text size kept clear of the < >)
      local vp = K.textScale() > 1 and 2 or 0
      K.bold(vt, vb[1] + 5 + vp, vb[2] + 1.4, K.fit(vt, 4.4, vb[3] - 10 - vp * 2), UI.accent, "center", vb[3] - 10 - vp * 2)
      settle(ve)
    else
      switch(rb[1] + rb[3] - 19, rb[2] + 2.5, toggled(i), t, dt)
    end
    settle(e)
    if live then K.addHit(rb, "win", TOGGLE + st.section * TOGGLE_SPAN + i - 1, area) end
  end
  local function drawToggles(x, y, w, h, clock, dt, live)
    local sec = SECTIONS[st.section]
    local list = sec.toggles
    -- (as many rows as fit above the note; more scroll)
    local noteH = sec.note and 15 or 0
    st.toggleVisible = max(1, floor((h - TITLE_H - 2 - noteH) / TOGGLE_H))
    st.toggleTop = max(0, min(st.toggleTop, max(0, #list - st.toggleVisible)))
    if mv.rowSec ~= st.section then mv.ttop = st.toggleTop else mv.ttop = approach(mv.ttop, st.toggleTop, dt, 18) end
    glide(st.toggleCursor, dt)
    local ce = outCubic((clock - mv.secAt - 0.03) / 0.32)
    rise(ce, 6)
    local gb = K.R(x, y + TITLE_H, w, min(#list, st.toggleVisible) * TOGGLE_H)
    K.glass(gb, 4)
    local area = clip(gb[1], gb[2], gb[3], gb[4])
    K.scissor(area)
    rowHighlight(gb[1], gb[2] - mv.ttop * TOGGLE_H, gb[3], TOGGLE_H, mv.rowY)
    local since = clock - mv.secAt
    for i, t in ipairs(list) do
      local ry = gb[2] + (i - 1 - mv.ttop) * TOGGLE_H
      if ry + TOGGLE_H > gb[2] and ry < gb[2] + gb[4] then
        drawToggleRow(i, t, K.R(gb[1], ry, gb[3], TOGGLE_H), area, stagger(since, i - st.toggleTop, 0.035, 0.28),
          clock, dt, live)
      end
    end
    K.scissor(bodyNow)
    if #list > st.toggleVisible then K.scrollbar(gb[1] + gb[3] + 2, gb[2], gb[4], mv.ttop, st.toggleVisible, #list) end
    if sec.note then
      local note, ny = T(sec.note), gb[2] + gb[4] + 3
      drawNote(note, x + 2, ny, 4.2, w - 4)
    end
    settle(ce)
  end

  -- the open setting: its title sliding in, Fill | Stretch by it for a picture, then its card
  local function drawDetail(x, y, w, h, clock, dt, live)
    local sec = SECTIONS[st.section]
    local te = outCubic((clock - mv.secAt) / 0.3)
    rise(te, 0, 8)
    local title = T(sec.key)
    local sw = min(64, w * 0.5)
    local withFit = sec.id == "wallpaper" and picture()
    -- (at a bigger text size kept clear of Fill | Stretch, and inside the setting)
    local ts = K.textScale() > 1 and K.fit(title, 6.5, w - 3 - (withFit and sw + 3 or 0)) or 6.5
    K.bold(title, x + 1.5, y + 1.5 + (6.5 - ts) * 0.5, ts, UI.label)
    settle(te)
    -- a picture: Fill | Stretch, by the title
    if withFit then
      mv.fitX = approach(mv.fitX, fit() == "fill" and 1 or 2, dt, 18)
      K.glassSwitch(x + w - sw, y + 1, sw, 8, mv.fitX, "win", FIT, T("settings.fill"), FIT + 1, T("settings.stretch"),
        nil, nil, 4.2)
    else
      mv.fitX = fit() == "fill" and 1 or 2
    end
    if sec.id == "language" then drawLanguage(x, y, w, h, clock, dt, live)
    elseif sec.toggles then drawToggles(x, y, w, h, clock, dt, live)
    else drawWallpaper(x, y, w, h, clock, dt, live) end
  end

  -- (portrait: back to the list, a capsule of glass)
  local function drawBack(x, y, live)
    local label = T("app.settings")
    local bw = K.width(label, 4.4) + 10
    local bb = K.R(x, y, bw, 9)
    K.col(C.white, 0.5)
    K.box("fill", bb, 4.5)
    K.ring(bb, 4.5, C.white, 0.8, 0.3)
    K.chevron(x + 3.6, y + 4.5, 3.8, UI.accent, -1)
    K.text(label, x + 6.6, y + 2.1, 4.4, UI.accent)
    if live then K.addHit(bb, "win", BACK) end
  end

  local function backdrop(body, clock) K.backdrop(body, clock, mv.r, mv.g, mv.b, mv.r2, mv.g2, mv.b2) end

  function W.draw(body, clock, portrait)
    st.portrait = portrait
    G = K.graphics()
    bodyNow = body
    local x, y, w, h = body[1], body[2], body[3], body[4]
    local dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT = clock
    if not mv.openAt then mv.openAt, mv.push = clock, st.reading and 1 or 0 end
    -- (another section, or the setting opened over the list in portrait: its rows rise again)
    if st.section ~= mv.sec or (portrait and st.reading and not mv.reading) then mv.sec, mv.secAt = st.section, clock end
    mv.reading = st.reading
    mv.focusK = approach(mv.focusK, st.focus == "detail" and 1 or 0, dt, 16)
    -- (the backdrop's lights: the section's colour and a paler one, eased; snapped the first time)
    local tile = SECTIONS[st.section].tile
    local rate = mv.coloured and 7 or 1000
    mv.coloured = true
    mv.r, mv.g, mv.b = approach(mv.r, tile[1] / 255, dt, rate), approach(mv.g, tile[2] / 255, dt, rate),
      approach(mv.b, tile[3] / 255, dt, rate)
    mv.r2 = approach(mv.r2, (tile[1] + (255 - tile[1]) * 0.45) / 255, dt, rate)
    mv.g2 = approach(mv.g2, (tile[2] + (255 - tile[2]) * 0.45) / 255, dt, rate)
    mv.b2 = approach(mv.b2, (tile[3] + (255 - tile[3]) * 0.45) / 255, dt, rate)
    backdrop(body, clock)
    offX = 0
    if portrait then
      -- (the setting slides in over the list, the list easing back under it)
      mv.push = approach(mv.push, st.reading and 1 or 0, dt, 14)
      local p = outCubic(mv.push)
      if p < 0.999 then
        local sh = p > 0.001
        if sh then
          G.push()
          G.translate(-w * 0.3 * p * K.sc, 0)
        end
        drawSide(x + M, y + M, w - M * 2, h - M * 2, clock, dt, not st.reading, true)
        if sh then
          G.pop()
          K.col(C.black, 0.12 * p)
          K.box("fill", body)
        end
      end
      if p > 0.001 then
        local sh = p < 0.999
        if sh then
          offX = w * (1 - p)
          G.push()
          G.translate(offX * K.sc, 0)
          K.shadow(body, 0, 0, 0.2)
        end
        backdrop(body, clock)
        K.scissor(body)
        drawBack(x + M, y + M, st.reading)
        drawDetail(x + M + 1, y + M + 11, w - M * 2 - 4, h - M * 2 - 11, clock, dt, st.reading)
        if sh then G.pop() end
        offX = 0
      end
      return
    end
    mv.push = st.reading and 1 or 0
    local sw = min(90, floor(w * 0.36))
    drawSide(x + M, y + M, sw - M, h - M * 2, clock, dt, true, false)
    local dx = x + sw + GAP + 1
    drawDetail(dx, y + M, x + w - M - 3 - dx, h - M * 2, clock, dt, true)
  end

  refresh()
  return W
end
