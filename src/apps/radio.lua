-- The Radio app (Gold / Silver / Crystal): the Pokégear's radio, its shows the game's own (the model is
-- src/gb/radio.lua, env.radio). A real radio app:
--   now playing  the station's artwork (its own picture in its colour, broadcast rings; the Pokémon Oak's
--                talk / the Pokédex Show is on about popping onto it; Lucky Number's ticket), its name, the
--                frequency, the song and an equaliser dancing to it
--   transcript   the show's lines as the game prints them, newest at the foot typing in, the older ones
--                sliding up and fading; who's speaking ("MARY:") in the station's colour; ON AIR
--   presets      a button for every station heard here and now
--   tuner        the frequency read out big, the band from 0.5 to 20.5 with each station's mark and a
--                needle gliding to the knob, its arrows
-- Nothing on the dial: static. A wall radio's (ctx.resume.state.station) is one station: no presets or tuner.
-- In the Pokédex's glass: the lights behind take the station's colour. Portrait: stacked.
--   buttons  Left / Right tune (held: on through the band), L / R the next station either way, B close
--   touch    the tuner (a tap or a drag tunes), its arrows, the presets, the marks; the wheel tunes
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, abs, sin = math.floor, math.max, math.min, math.abs, math.sin

local M, GAP = 3, 3
local LEFT, RIGHT, DIAL, MARK = 2001, 2002, 2003, 2100
local HINTS = {
  dial = { { "< >", "radio.hint.tune" }, { "L R", "radio.hint.station" }, { "B", "hint.close" } },
  fixed = { { "B", "hint.close" } },
}
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

-- each station's colour (the lights behind, its artwork, its mark and preset) and its picture
local TINT = {
  OAKS_POKEMON_TALK = { 70, 170, 90 }, POKEDEX_SHOW = { 226, 70, 72 }, POKEMON_MUSIC = { 150, 100, 220 },
  LUCKY_CHANNEL = { 232, 168, 32 }, BUENAS_PASSWORD = { 236, 96, 160 }, UNOWN_RADIO = { 110, 110, 130 },
  PLACES_AND_PEOPLE = { 60, 130, 220 }, LETS_ALL_SING = { 255, 140, 40 }, POKE_FLUTE_RADIO = { 0, 170, 170 },
  EVOLUTION_RADIO = { 170, 40, 60 }, ROCKET_RADIO = { 60, 40, 50 },
}
local EMBLEM = {
  OAKS_POKEMON_TALK = "speech", POKEDEX_SHOW = "dex", POKEMON_MUSIC = "headphones", LUCKY_CHANNEL = "medal",
  BUENAS_PASSWORD = "letters", UNOWN_RADIO = "eye", PLACES_AND_PEOPLE = "map", LETS_ALL_SING = "mic",
  POKE_FLUTE_RADIO = "speaker", EVOLUTION_RADIO = "wifi", ROCKET_RADIO = "rocket",
}
local C = { ink = { 28, 28, 30 }, soft = { 112, 112, 120 }, faint = { 162, 162, 170 }, white = { 255, 255, 255 },
            black = { 0, 0, 0 }, red = { 255, 59, 48 }, slate = { 120, 132, 178 }, static = { 150, 150, 160 } }

-- sizes (units, at 100% text)
local NAME, SUB, LINE, HEAD, PRESET, PFREQ, READ = 6.4, 4.2, 5, 3.8, 4, 3.2, 8

return function(ctx, env)
  local K, Rd, T = env.K, env.radio, env.T or NO_T
  local W = { title = T("app.radio") }
  local function se(name) if env.se then pcall(env.se, name) end end
  local fixedStation = ctx.resume and ctx.resume.state and ctx.resume.state.station or nil
  ctx.resume = nil

  local st = { knob = 0, dragging = false }
  W.state = st
  if fixedStation then Rd.openStation(fixedStation) else Rd.open() end
  st.knob = Rd.knob()

  function W.close() Rd.close() end

  -- ------- tuning
  local function tuneTo(k)
    if Rd.fixed() then return end
    if Rd.setKnob(k) then
      st.knob = Rd.knob()
      se("SE_SELECT")
    end
  end
  -- (L / R: the next knob with a station on it, that way)
  local function nextStation(d)
    local best = nil
    for _, row in ipairs(Rd.stations()) do
      if row.station and ((d > 0 and row.knob > st.knob) or (d < 0 and row.knob < st.knob)) then
        if not best or (d > 0 and row.knob < best) or (d < 0 and row.knob > best) then best = row.knob end
      end
    end
    if best then tuneTo(best) else se("SE_FAILURE") end
  end

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  function W.input(input, nav)
    cur = input
    if pressed("b") then return false end
    if Rd.fixed() then
      if pressed("a") then return false end
      return true
    end
    if nav.left then tuneTo(st.knob - 2)
    elseif nav.right then tuneTo(st.knob + 2)
    elseif pressed("l") then nextStation(-1)
    elseif pressed("r") then nextStation(1)
    end
    return true
  end

  -- (the tuner's band, units: set each draw for the pointer)
  local band = { x = 0, w = 1, y = 0, h = 0 }
  local function knobAt(x) return (x - band.x) / max(1, band.w) * Rd.KNOB_MAX end
  function W.tap(arg)
    if arg == LEFT then return tuneTo(st.knob - 2) end
    if arg == RIGHT then return tuneTo(st.knob + 2) end
    if type(arg) == "number" and arg >= MARK and arg <= MARK + Rd.KNOB_MAX then return tuneTo(arg - MARK) end
  end
  function W.pointer(phase, x, y)
    if Rd.fixed() then return false end
    local inBand = x >= band.x - 3 and x <= band.x + band.w + 3 and y >= band.y - 4 and y <= band.y + band.h + 4
    if phase == "pressed" then
      st.dragging = inBand
      if inBand then tuneTo(knobAt(x)) end
      return inBand
    elseif phase == "moved" and st.dragging then
      tuneTo(knobAt(x))
      return true
    elseif phase == "released" then
      local was = st.dragging
      st.dragging = false
      return was
    end
    return false
  end
  function W.scroll(dy)
    if dy > 0 then tuneTo(st.knob + 2) elseif dy < 0 then tuneTo(st.knob - 2) end
  end
  function W.hints() return T.list(Rd.fixed() and HINTS.fixed or HINTS.dial) end

  -- ------- drawing (no tables, closures or strings made here but the cached ones)
  local G = nil
  local approach, outCubic, outBack = K.approach, K.outCubic, K.outBack
  local mv = { lastT = nil, needle = nil, openAt = nil, station = false, stationAt = -10, histVer = -1, histAt = -10,
               feat = false, featAt = -10, r = 0.5, g = 0.5, b = 0.5, coloured = false, body = nil }
  W.motion = mv

  -- "Music_PokemonMarch" -> "Pokémon March" (kept)
  local songName = K.textCache(function(label)
    local s = tostring(label):gsub("^Music_", ""):gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2")
    return (s:gsub("Pokemon", "Pokémon"))
  end)
  local freqText = K.textCache(function(k) return string.format("%.1f", (k + 2) / 4) end)
  local luckyText = K.textCache(function(n) return string.format("No. %05d", n % 100000) end)
  -- "MARY: PROF.OAK'S" -> the speaker "MARY:" and the rest (kept; "" when nobody's named)
  local function splitOf(s)
    local who, rest = s:match("^([%u%.' ]+:)%s*(.*)$")
    if who and #who <= 14 then return who, rest end
    return "", s
  end
  local speakerOf = K.textCache(function(s) return (splitOf(s)) end)
  local restOf = K.textCache(function(s) local _, rest = splitOf(s) return rest end)
  local function tintOf(station) return station and TINT[station] or (station and C.slate or C.static) end
  local function glyph(kind, cx, cy, size, a, tile)
    if env.glyph then pcall(env.glyph, G, kind, K.X(cx), K.Y(cy), size * K.sc, (a or 1) * K.getFade(), tile) end
  end

  -- the artwork: a tile in the station's colour, rings going out, its picture; the Pokémon a show is on
  -- about popping on in its place (the picture to the corner); Lucky Number's ticket
  local function drawArt(x, y, s, clock, station, tint)
    local b = K.R(x, y, s, s)
    local rad = s * 0.16
    K.shadow(b, rad, 1.6, 0.16)
    if station then
      K.grad(b, rad, K.light(tint, 0.2), K.dark(tint, 0.25))
    else
      K.grad(b, rad, C.static, K.dark(C.static, 0.35))
    end
    local cx, cy = x + s / 2, y + s / 2
    K.scissor(b)
    G.setLineWidth(max(1, 0.55 * K.sc))
    for i = 0, 2 do
      local p = (clock * (station and 0.35 or 0.12) + i / 3) % 1
      K.col(C.white, (1 - p) * (station and 0.34 or 0.12))
      G.circle("line", K.X(cx), K.Y(cy), (s * 0.18 + p * s * 0.55) * K.sc)
    end
    -- (a soft sheen over the top)
    K.grad(K.R(x, y, s, s * 0.45), rad, K.fade(C.white, 0.22), K.fade(C.white, 0))
    K.scissor(mv.body)
    local sp = station and Rd.featured() or nil
    if (sp or false) ~= mv.feat then mv.feat, mv.featAt = sp or false, clock end
    local lucky = station and Rd.lucky() or nil
    local emblem = station and EMBLEM[station] or "wifi"
    if sp and env.monPic then
      local pe = outBack(min(1, (clock - mv.featAt) / 0.45))
      local pa = min(1, (clock - mv.featAt) / 0.2)
      K.glow(cx, cy + s * 0.04, s * 0.4, s * 0.36, C.white, 0.55 * pa)
      local ps = s * 0.74 * (0.7 + 0.3 * pe)
      pcall(env.monPic, sp, cx - ps / 2, cy - ps / 2 + s * 0.02, ps, pa * K.getFade())
      K.rescissor()
      glyph(emblem, x + s * 0.15, y + s * 0.15, s * 0.17, 0.9, tint)
    else
      local ea = station and 1 or 0.55
      glyph(emblem, cx, cy - (lucky and s * 0.09 or 0), s * 0.44, ea, tint)
    end
    if lucky then
      local lb = K.R(x + s * 0.14, y + s * 0.7, s * 0.72, s * 0.17)
      K.col(C.white, 0.94)
      K.box("fill", lb, lb[4] / 2)
      local txt = luckyText(lucky)
      local fs = K.fit(txt, s * 0.09, lb[3] - 4)
      K.bold(txt, lb[1], lb[2] + lb[4] / 2 - fs * 0.62 * K.textScale(), fs, K.dark(tint, 0.3), "center", lb[3])
    end
  end

  -- the equaliser: bars dancing while a song plays (flat and grey when nothing does)
  local function drawEq(x, y, w, h, clock, tint, on)
    local n = min(24, floor(w / 2.6))
    if n < 3 then return end
    local bw = w / n
    for i = 0, n - 1 do
      local v = 0.1
      if on then v = 0.18 + 0.82 * abs(sin(clock * (2.6 + (i % 4) * 0.7) + i * 1.7) * sin(clock * 1.3 + i * 0.9)) end
      local bh = max(0.8, h * v)
      K.col(on and tint or C.faint, on and 0.85 or 0.5)
      K.box("fill", K.R(x + i * bw + bw * 0.2, y + h - bh, bw * 0.6, bh), min(0.6, bw * 0.3))
    end
  end

  -- now playing: the artwork, the station's name, the frequency and the song, the equaliser; across
  -- (portrait: the artwork beside the words) or down
  local TS = 1
  local function infoH() return K.lineH(NAME) * 1.3 + K.lineH(SUB) * 1.35 + 7 end
  local function drawNowPlaying(x, y, w, h, clock, station, name, tint, across)
    K.glass(K.R(x, y, w, h), 7, 0.62)
    local e = outCubic((clock - mv.stationAt) / 0.3)
    local title = name or T(station and "radio.station" or "radio.noSignal")
    local freq = Rd.fixed() and T("radio.onAir") or freqText(st.knob)
    local song = station and Rd.song() or nil
    local label = song and songName(song) or nil
    local ax, ay, as, tx, ty, tw
    if across then
      as = h - 8
      ax, ay = x + 4, y + 4
      tx, tw = ax + as + 5, x + w - (ax + as + 5) - 4
      ty = y + (h - infoH()) / 2
    else
      as = min(w - 10, h - infoH() - 9)
      ax, ay = x + (w - as) / 2, y + 5
      tx, tw = x + 5, w - 10
      ty = ay + as + 4
    end
    drawArt(ax, ay, as, clock, station, tint)
    local align = (not across) and "center" or nil
    local ox = (1 - e) * 5
    local fs = K.fit(title, NAME, tw)
    K.bold(title, tx + ox, ty, fs, C.ink, align, tw, e)
    ty = ty + K.lineH(NAME) * 1.3
    -- (the frequency, then a note and the song)
    local fw = K.width(freq, SUB)
    local room = tw - fw - 6
    local lw = label and min(room - 4, K.width(label, SUB)) or 0
    local lx = tx + ox
    if align == "center" then lx = tx + (tw - (fw + (label and room > 12 and lw + 6 or 0))) / 2 end
    K.text(freq, lx, ty, SUB, C.soft, nil, nil, e)
    if label and room > 12 then
      local nx = lx + fw + 3
      local bob = sin(clock * 5) * 0.5
      local my = ty + SUB * 0.62 * TS
      K.col(tint, e)
      G.circle("fill", K.X(nx + 1), K.Y(my + 1.6 + bob), 1 * K.sc)
      K.box("fill", K.R(nx + 1.7, my - 2.2 + bob, 0.45, 3.8))
      K.text(label, nx + 3.5, ty, K.fit(label, SUB, room - 4), tint, nil, nil, e)
    end
    ty = ty + K.lineH(SUB) * 1.35
    local eqW = min(tw, 60)
    drawEq(align == "center" and tx + (tw - eqW) / 2 or tx, ty, eqW, 5, clock, tint, song ~= nil)
  end

  -- the transcript: ON AIR and the frequency up top; the lines, newest at the foot typing in
  local function drawTranscript(x, y, w, h, clock, station, tint)
    K.glass(K.R(x, y, w, h), 6, 0.6)
    local hy = y + 3
    local hh = K.lineH(HEAD) * 1.25
    if station then
      local p = 0.5 + 0.5 * sin(clock * 4)
      K.col(C.red, 0.55 + 0.45 * p)
      G.circle("fill", K.X(x + 7), K.Y(hy + HEAD * 0.62 * TS), 1.2 * K.sc)
      K.glow(x + 7, hy + HEAD * 0.62 * TS, 3, 3, C.red, 0.3 * p)
      K.bold(T("radio.live"), x + 10, hy, HEAD, C.red)
    else
      K.bold(T("radio.noSignal"), x + 6, hy, HEAD, C.soft)
    end
    K.hairline(x + 5, hy + hh + 1, w - 10, nil, 0.6)
    local top, foot = hy + hh + 2.5, y + h - 3
    local area = K.R(x + 1, top, w - 2, foot - top)
    local ax, ay, aw, ah = area[1], area[2], area[3], area[4]
    if not station then
      -- (static: a word, and bars flickering under it)
      local word = T("radio.static")
      K.text(word, x, ay + ah / 2 - 6, K.fit(word, 4.6, w - 8), C.soft, "center", w)
      for i = 0, 23 do
        local bh = 1 + 4 * abs(sin(clock * 23 + i * 2.7) * sin(clock * 7 + i))
        K.col(C.faint, 0.6)
        K.box("fill", K.R(x + w / 2 - 30 + i * 2.6, ay + ah / 2 + 4 - bh / 2, 1.4, bh), 0.6)
      end
      return
    end
    local n = Rd.historyCount()
    if n == 0 then
      local word = T("radio.tuningIn")
      local a = 0.55 + 0.45 * sin(clock * 3)
      K.text(word, x, ay + ah / 2 - 3, K.fit(word, LINE, w - 8), C.soft, "center", w, a)
      return
    end
    if Rd.histVersion ~= mv.histVer then
      if mv.histVer >= 0 then mv.histAt = clock end
      mv.histVer = Rd.histVersion
    end
    local lh = K.lineH(LINE) * 1.38
    local e = outCubic((clock - mv.histAt) / 0.3)
    local typed = min(1, (clock - mv.histAt) / 0.55)
    local slide = (1 - e) * lh
    local tx, tw = x + 6, w - 12
    for i = 1, n do
      local ly = foot - 1 - i * lh + slide
      if ly + lh < ay then break end
      local s = Rd.history(i)
      local a = i == 1 and 1 or max(0.2, 1 - (i - 1) * 0.16)
      -- (the lines nearest the top fade out under it)
      local edge = (ly - ay) / lh
      if edge < 1 then a = a * max(0, edge) end
      local ink = i == 1 and C.ink or C.soft
      local who, rest = speakerOf(s), restOf(s)
      local clipTop = max(ay, ly - 1)
      if i == 1 and typed < 1 then
        K.scissor(K.R(tx - 1, clipTop, (K.width(s, LINE) + 4) * typed + 1, ly + lh - clipTop))
      else
        K.scissor(area)
      end
      if who ~= "" then
        K.bold(who, tx, ly, LINE, tint, nil, nil, a)
        local sw = K.width(who, LINE) + 1.6
        K.text(rest, tx + sw, ly, K.fit(rest, LINE, tw - sw), ink, nil, nil, a)
      else
        K.text(s, tx, ly, K.fit(s, LINE, tw), ink, nil, nil, a)
      end
    end
    -- (the typing caret after the newest line)
    if typed < 1 then
      local s = Rd.history(1)
      local cx = tx + min(tw, K.width(s, LINE)) * typed + 0.6
      K.scissor(area)
      K.col(tint, 0.8)
      K.box("fill", K.R(cx, foot - 1 - lh + slide + LINE * 0.25 * TS, 0.6, LINE * 0.85 * TS))
    end
    K.scissor(mv.body)
  end

  -- the presets: a button for each station heard here and now, its picture and frequency; the tuned one
  -- filled in its colour and opened out (eased) to show its name too, as room allows
  local function presetH() return K.lineH(PRESET) * 1.1 + K.lineH(PFREQ) * 1.05 + 5 end
  local pw = {}
  local function drawPresets(x, y, w, h, dt)
    local n, tuned = 0, false
    for _, row in ipairs(Rd.stations()) do
      if row.station then
        n = n + 1
        if row.knob == st.knob then tuned = true end
      end
    end
    if n == 0 then return end
    local d = min(h - 4, 9)
    local compact = 3 + d + 3 + K.width("20.5", PFREQ * 1.2) + 4
    local wide = min(92, w - (n - 1) * (compact + GAP))
    if wide < compact * 1.4 then
      compact = (w - GAP * (n - 1)) / n
      wide = compact
    end
    if not tuned then compact = min(wide, (w - GAP * (n - 1)) / n) end
    local total = 0
    for _, row in ipairs(Rd.stations()) do
      if row.station then
        local target = row.knob == st.knob and wide or compact
        pw[row.knob] = approach(pw[row.knob] or target, target, dt, 14)
        total = total + pw[row.knob]
      end
    end
    local cx = x + (w - total - GAP * (n - 1)) / 2
    for _, row in ipairs(Rd.stations()) do
      if row.station then
        local cw = pw[row.knob]
        local b = K.R(cx, y, cw, h)
        local on = row.knob == st.knob
        local tint = tintOf(row.station)
        if on then
          K.shadow(b, h / 2, 1.2, 0.14)
          K.grad(b, h / 2, K.light(tint, 0.1), K.dark(tint, 0.12))
        else
          K.glass(b, h / 2, 0.55)
        end
        -- (its picture in a disc of its colour)
        local ccx, ccy = cx + 2.5 + d / 2, y + h / 2
        K.col(on and C.white or tint, on and 0.28 or 1)
        G.circle("fill", K.X(ccx), K.Y(ccy), d / 2 * K.sc)
        glyph(EMBLEM[row.station] or "wifi", ccx, ccy, d * 0.62, 1, tint)
        local tx = cx + 2.5 + d + 2.5
        local nw = cx + cw - 3 - tx
        local name = row.name or ""
        local fq = freqText(row.knob)
        K.scissor(b)
        if on and K.width(name, 3.6) <= nw then
          local ty = y + (h - (K.lineH(PRESET) * 1.1 + K.lineH(PFREQ) * 1.05)) / 2
          K.bold(name, tx, ty, K.fit(name, PRESET, nw), C.white)
          K.text(fq, tx, ty + K.lineH(PRESET) * 1.1, PFREQ, C.white, nil, nil, 0.85)
        else
          local fs = PFREQ * 1.2
          K.bold(fq, tx, y + h / 2 - fs * 0.62 * TS, K.fit(fq, fs, nw), on and C.white or C.ink)
        end
        K.scissor(mv.body)
        K.addHit(b, "win", MARK + row.knob)
        cx = cx + cw + GAP
      end
    end
  end

  -- the tuner: the arrows, the frequency read out big, the band's ticks (a long one each MHz), the
  -- stations' marks, the needle
  local function drawTuner(x, y, w, h, clock, dt)
    K.glass(K.R(x, y, w, h), 6, 0.55)
    local ab = 9
    local lb, rb = K.R(x + 2, y + h / 2 - ab / 2, ab, ab), K.R(x + w - 2 - ab, y + h / 2 - ab / 2, ab, ab)
    K.chevron(lb[1] + 5, lb[2] + ab / 2, 3.8, K.UI.accent, -1)
    K.chevron(rb[1] + 4, rb[2] + ab / 2, 3.8, K.UI.accent, 1)
    K.addHit(lb, "win", LEFT)
    K.addHit(rb, "win", RIGHT)
    -- (the read-out: the needle's frequency)
    if mv.needle == nil then mv.needle = st.knob end
    mv.needle = approach(mv.needle, st.knob, dt, 16)
    local rw = K.width("20.5", READ) + 5
    local rx = x + 2 + ab + 2
    local rbx = K.R(rx, y + 3, rw, h - 6)
    K.col(C.black, 0.06)
    K.box("fill", rbx, 4)
    local ftxt = freqText(st.knob)
    K.bold(ftxt, rx, y + h / 2 - READ * 0.62 * TS, K.fit(ftxt, READ, rw - 2), C.ink, "center", rw)
    band.x = rx + rw + 6
    band.w = x + w - 2 - ab - 4 - band.x
    band.y, band.h = y + 5, h - 13
    local KM = Rd.KNOB_MAX
    for k = 0, KM, 2 do
      local tx = band.x + band.w * k / KM
      local major = (k + 2) % 4 == 0
      K.col(C.ink, major and 0.45 or 0.2)
      K.box("fill", K.R(tx - 0.2, band.y + band.h - (major and 5 or 2.5), 0.4, major and 5 or 2.5))
      -- (the MHz under every fifth long tick: 5, 10, 15, 20)
      if major and ((k + 2) / 4) % 5 == 0 then
        K.text(freqText(k), tx - 6, band.y + band.h + 0.4, 3, C.soft, "center", 12)
      end
    end
    for _, row in ipairs(Rd.stations()) do
      if row.station then
        local tx = band.x + band.w * row.knob / KM
        local on = row.knob == st.knob
        local c = tintOf(row.station)
        if on then K.glow(tx, band.y + 3, 3.5, 3.5, c, 0.45) end
        K.col(c, on and 1 or 0.75)
        G.circle("fill", K.X(tx), K.Y(band.y + 3), (on and 1.9 or 1.4) * K.sc)
        K.addHit(K.R(tx - 3, band.y - 1, 6, 8), "win", MARK + row.knob)
      end
    end
    -- (the needle gliding to the knob)
    local nx = band.x + band.w * mv.needle / KM
    K.glow(nx, band.y + band.h / 2, 2.5, band.h * 0.7, C.red, 0.18)
    K.col(C.red)
    K.box("fill", K.R(nx - 0.4, band.y - 1, 0.8, band.h + 1), 0.4)
    G.circle("fill", K.X(nx), K.Y(band.y - 1), 1.2 * K.sc)
    K.addHit(K.R(band.x, band.y - 2, band.w, band.h + 4), "win", DIAL)
  end

  function W.draw(body, clock, portrait)
    G = K.graphics()
    TS = K.textScale()
    mv.body = body
    local dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT = clock
    if mv.openAt == nil then mv.openAt = clock end
    Rd.step(clock)
    st.knob = Rd.knob()
    local station, name = Rd.current()
    if station ~= mv.station then mv.station, mv.stationAt = station, clock end
    local tint = tintOf(station)
    local rate = mv.coloured and 5 or 1000
    mv.coloured = true
    mv.r, mv.g, mv.b = approach(mv.r, tint[1] / 255, dt, rate), approach(mv.g, tint[2] / 255, dt, rate),
      approach(mv.b, tint[3] / 255, dt, rate)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    K.backdrop(body, clock, mv.r, mv.g, mv.b, 0.55, 0.6, 0.9)
    K.scissor(body)
    local e = outCubic((clock - mv.openAt) / 0.35)
    K.rise(e, 6)
    local fixed = Rd.fixed() ~= nil
    local tunerH = fixed and 0 or min(30, max(22, h * 0.22)) + (TS - 1) * 8
    local pH = fixed and 0 or presetH()
    local x0, y0, w0 = x + M, y + M, w - M * 2
    local foot = y + h - M - (fixed and 0 or tunerH + GAP)
    if portrait or w < h * 1.15 then
      -- (stacked: now playing across the top, the transcript, the presets, the tuner)
      local npH = min(58, max(40, h * 0.3)) + (TS - 1) * 10
      drawNowPlaying(x0, y0, w0, npH, clock, station, name, tint, true)
      local ty = y0 + npH + GAP
      local trH = foot - ty - (fixed and 0 or pH + GAP)
      drawTranscript(x0, ty, w0, trH, clock, station, tint)
      if not fixed then drawPresets(x0, ty + trH + GAP, w0, pH, dt) end
    else
      -- (side by side: now playing on the left, the transcript and the presets on the right)
      local topH = foot - y0
      local lw = max(78, min(116, w0 * 0.4))
      drawNowPlaying(x0, y0, lw, topH, clock, station, name, tint, false)
      local rx, rw = x0 + lw + GAP, w0 - lw - GAP
      local trH = topH - (fixed and 0 or pH + GAP)
      drawTranscript(rx, y0, rw, trH, clock, station, tint)
      if not fixed then drawPresets(rx, y0 + trH + GAP, rw, pH, dt) end
    end
    if not fixed then drawTuner(x0, y + h - M - tunerH, w0, tunerH, clock, dt) end
    K.settle(e)
    K.scissor(body)
  end

  return W
end
