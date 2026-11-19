-- The drawing kit: what a full-window touch screen needs, drawn in "units" on a page laid out for
-- the window (landscape: a page `height` units tall; portrait: `portraitWidth` wide), scaled to
-- its safe area. Lifted from WoobleDex's vending machine screen.
--
-- GARBAGE: the screens draw every frame, so nothing here makes a table or a closure per call once
-- warm: rectangles come from a pool (K.R, valid until the next frame), hit records too, derived
-- colours are memoised (K.mix / light / dark / fade return the same table for the same inputs) and
-- gradient meshes are kept by those colour tables' identity and their size. Callers keep to the
-- same rules: colour constants made once, no table literals in a draw.
--
--   K = Kit(deps)        deps: safeArea() -> x, y, w, h (window pixels) or nil ; fallback(font, px)
--                        (more glyphs under a font: the engine's kana / CJK face) or nil
--   K.frame(G, vp, page, now) -> pw, ph, portrait   starts a frame: the window from the render.hud
--         viewport (vp.width / height), the page in units, K.sc / K.ox / K.oy set, pools emptied
--         page = { height, minWidth, maxWidth, portraitWidth, portraitHeight, portraitAspect }
--   K.R(x, y, w, h) ; K.X(u) ; K.Y(u) ; K.col(c, a) ; K.box(mode, b, rad) ; K.grad(b, rad, top, foot, a)
--   K.gradient(G, x, y, w, h, rad, top, foot, a) (window pixels) ; K.shadow(b, rad, lift, a)
--   K.glow(cx, cy, rx, ry, c, a) ; K.ring(b, rad, c, a, w) ; K.addHit(b, kind, arg, clip) ; K.hits (this frame's, last on top)
--   K.font(px) ; K.width(s, size) ; K.text(s, x, y, size, c, align, w, a) ; K.label(...) (shadowed)
--   K.fit(s, size, w) ; K.scissor(b | nil) ; K.pulse() ; K.textCache(make) ; K.inside(rect, x, y)
--   K.mix / light / dark / fade ; K.WHITE / BLACK ; K.drawPlate(title, x, y, maxW, accent, body, outline)
--   K.drawLogo(cx, cy, size, accent, a, soft) (window pixels: the W)
--   K.hints(list, box, keyInk, center, wordColor, keyFill) (wordColor nil: white, shadowed)
--   K.toast(state, clock, area, badColor, goodColor) ; K.repeater(start, every) -> fn(input, key, held)
--   the windows' look (macOS / iOS): K.UI (the system colours: label, secondary, tertiary, separator,
--   grouped, card, sidebar, fill, accent, red, green, ...) ; K.bold(text args) ; K.hairline(x, y, w) /
--   K.vline(x, y, h) ; K.chevron(cx, cy, s, c, dir) ; K.card(b, rad) ; K.selection(b, focused, rad, c) ;
--   K.focusRing(b, rad, a) ; K.button(b, label, "accent" | "danger" | "gray" | "tinted", focused, size) ;
--   K.segmented(x, y, w, h, sel, kind, arg1, words1, arg2, words2 [, arg3, words3]) ; K.dim(b) ;
--   K.sheet(b, rad) ; K.scrollbar(x, y, h, top, visible, total)

return function(deps)
  deps = deps or {}
  local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
  local K = {}

  local WHITE, BLACK = { 255, 255, 255 }, { 0, 0, 0 }
  K.WHITE, K.BLACK = WHITE, BLACK

  -- ------- colours: { r, g, b [, a] }, r g b 0..255, a 0..1

  -- derived colours are made once and kept (by their parents and the amount, in 64ths): the same
  -- table every frame, so the meshes can be kept by them. Bounded: past 4000 the store starts over.
  local mixed, mixedCount = {}, 0
  local function memo(a, b, t)
    t = floor(t * 64 + 0.5)
    local byB = mixed[a]
    if not byB then
      byB = {}
      mixed[a] = byB
    end
    local byT = byB[b]
    if not byT then
      byT = {}
      byB[b] = byT
    end
    return byT, t
  end
  local function mix(a, b, t)
    local cache, k = memo(a, b, t)
    local c = cache[k]
    if not c then
      if mixedCount > 4000 then
        mixed, mixedCount = {}, 0
        cache, k = memo(a, b, t)
      end
      t = k / 64
      c = { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t,
            (a[4] or 1) + ((b[4] or 1) - (a[4] or 1)) * t }
      cache[k] = c
      mixedCount = mixedCount + 1
    end
    return c
  end
  local function light(c, t) return mix(c, WHITE, t) end
  local function dark(c, t) return mix(c, BLACK, t) end
  local FADE = {}
  local function fade(c, a)
    local cache, k = memo(c, FADE, a)
    local f = cache[k]
    if not f then
      f = { c[1], c[2], c[3], k / 64 }
      cache[k] = f
      mixedCount = mixedCount + 1
    end
    return f
  end
  K.mix, K.light, K.dark, K.fade = mix, light, dark, fade

  -- ------- the theme: Light (the colours as given), Dark or OLED. Every colour through the kit is seen to
  -- here, each table once per theme (kept, by the table: the same table every frame, so the meshes keep):
  --   a fill (K.col, K.box's colour, gradients): a light grey or white, or a pale tint, goes dark
  --     (white, the cards, to an elevated grey; the window's grounds, near white, to the darkest; OLED
  --     those black), its hue kept; a strong colour, a dark one (shadows, dims) and a faint white (a
  --     highlight, alpha 0.35 and under) stay
  --   ink (texts, rings, rules, chevrons): a dark one goes light (the words to near white, the greys to
  --     mid greys); a strong but deep one (the Mart's gold prices) a lighter shade of itself; a light one,
  --     or a bright strong colour, stays
  -- K.themeHold(true / false): the colours as given while held (a scene with a look of its own: the
  -- Pokémon Center, the market stalls, a dark window); the count starts over each frame
  local themeN, themeName, hold = 0, "light", 0
  -- (per theme: the light end's elevated grey, the grounds' grey, the mid greys' end)
  local TONE = { [1] = { e = 0.17, b = 0.105, m = 0.40 }, [2] = { e = 0.105, b = 0.0, m = 0.36 } }
  local toneFill, toneInk = { {}, {} }, { {}, {} }
  for i = 1, 2 do
    setmetatable(toneFill[i], { __mode = "k" })
    setmetatable(toneInk[i], { __mode = "k" })
  end
  local function hsl(r, g, b)
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local l = (mx + mn) / 2
    if mx == mn then return 0, 0, l end
    local d = mx - mn
    local s = l > 0.5 and d / (2 - mx - mn) or d / (mx + mn)
    local h
    if mx == r then h = (g - b) / d + (g < b and 6 or 0) elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
    return h / 6, s, l
  end
  local function hue(p, q, t)
    if t < 0 then t = t + 1 elseif t > 1 then t = t - 1 end
    if t < 1 / 6 then return p + (q - p) * 6 * t end
    if t < 1 / 2 then return q end
    if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
    return p
  end
  local function fromHsl(h, s, l, a)
    if s == 0 then return { l * 255, l * 255, l * 255, a } end
    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q
    return { hue(p, q, h + 1 / 3) * 255, hue(p, q, h) * 255, hue(p, q, h - 1 / 3) * 255, a }
  end
  local function fillOf(c)
    local kept = toneFill[themeN][c]
    if kept then return kept end
    local a = c[4] or 1
    local h, s, l = hsl(c[1] / 255, c[2] / 255, c[3] / 255)
    local out = c
    if l >= 0.55 and not (a <= 0.35 and l > 0.85) and not (s > 0.5 and l < 0.8) then
      local T = TONE[themeN]
      local nl
      if l >= 0.985 then nl = T.e
      elseif l >= 0.95 then nl = T.b + (l - 0.95) / 0.035 * (T.e - T.b)
      else nl = T.b + (0.95 - l) / 0.4 * (T.m - T.b) end
      out = fromHsl(h, s * 0.8, nl, c[4])
    end
    toneFill[themeN][c] = out
    return out
  end
  local function inkOf(c)
    local kept = toneInk[themeN][c]
    if kept then return kept end
    local h, s, l = hsl(c[1] / 255, c[2] / 255, c[3] / 255)
    local out = c
    if l <= 0.5 and not (s > 0.5 and l > 0.3) then out = fromHsl(h, s, 1 - l * 0.85, c[4])
    elseif s > 0.5 and l > 0.3 and l < 0.48 then
      -- (a strong colour too deep to read on the dark: the Mart's gold prices, a deep green: a lighter shade)
      out = fromHsl(h, s, 0.66, c[4])
    end
    toneInk[themeN][c] = out
    return out
  end
  -- (a colour as the theme has it: a fill's, or ink's)
  local function tf(c) if themeN == 0 or hold > 0 then return c end return fillOf(c) end
  local function ti(c) if themeN == 0 or hold > 0 then return c end return inkOf(c) end
  K.toneFill, K.toneInk = tf, ti
  function K.setTheme(name)
    name = (name == "dark" or name == "oled") and name or "light"
    themeName = name
    themeN = name == "dark" and 1 or (name == "oled" and 2 or 0)
  end
  -- (the theme the colours are drawn in now: "light" while held)
  function K.theme() return hold > 0 and "light" or themeName end
  function K.themeHold(on)
    if on then hold = hold + 1 elseif hold > 0 then hold = hold - 1 end
  end

  -- ------- the frame

  local G
  local ox, oy, sc, t0 = 0, 0, 1, 0
  local hits, hitPool, nHitRec = {}, {}, 0
  local rects, nRect = {}, 0
  K.hits = hits
  K.sc = 1

  -- a rectangle from the pool (valid until the next frame)
  local function R(x, y, w, h)
    nRect = nRect + 1
    local q = rects[nRect]
    if not q then
      q = {}
      rects[nRect] = q
    end
    q[1], q[2], q[3], q[4] = x, y, w, h
    return q
  end
  K.R = R

  local fonts = {}
  -- (a canvas of one pixel a unit, on a high-DPI device, wants fonts of its own: K.exactFonts)
  local exactFonts, exact = {}, false
  function K.exactFonts(on) exact = on end
  local function font(px)
    px = max(6, floor(px + 0.5))
    local cache = exact and exactFonts or fonts
    local f = cache[px]
    if not f then
      local ok, made
      if exact then ok, made = pcall(G.newFont, px, "normal", 1) else ok, made = pcall(G.newFont, px) end
      f = ok and made or G.getFont()
      if ok and made and deps.fallback then pcall(deps.fallback, made, px, exact) end
      cache[px] = f
    end
    return f
  end
  K.font = font

  local function X(v) return ox + v * sc end
  local function Y(v) return oy + v * sc end
  K.X, K.Y = X, Y
  -- (`fade`: everything drawn through col / grad / glow at that much of itself; K.setFade, reset each
  -- frame: something fading in over a backdrop that isn't one colour)
  local fade = 1
  local function col(c, a)
    c = tf(c or WHITE)
    G.setColor(c[1] / 255, c[2] / 255, c[3] / 255, (a or 1) * (c[4] or 1) * fade)
  end
  K.col = col
  -- (ink: a text's, a ring's, a rule's)
  local function ink(c, a)
    c = ti(c or WHITE)
    G.setColor(c[1] / 255, c[2] / 255, c[3] / 255, (a or 1) * (c[4] or 1) * fade)
  end
  K.ink = ink
  function K.setFade(v) fade = v end
  function K.getFade() return fade end
  -- motion (the glass windows'; numbers only, nothing made): eases of t in 0..1, a value followed
  -- smoothly whatever the frame rate, something settling in (K.rise(e, dy, dx): `(1 - e) * dy` lower,
  -- `dx` across, at `e` of itself, until K.settle(e)), the i-th of a group rising in `since` seconds after
  -- it started (`each` apart, `dur` long)
  local function clamp01(t) return t < 0 and 0 or (t > 1 and 1 or t) end
  function K.outCubic(t)
    t = clamp01(t)
    local u = 1 - t
    return 1 - u * u * u
  end
  function K.outBack(t)
    t = clamp01(t)
    local u = t - 1
    return 1 + 2.70158 * u * u * u + 1.70158 * u * u
  end
  function K.inOut(t)
    t = clamp01(t)
    return t < 0.5 and 4 * t * t * t or 1 - (-2 * t + 2) ^ 3 / 2
  end
  function K.approach(cur, target, dt, rate)
    local v = cur + (target - cur) * (1 - math.exp(-dt * rate))
    if math.abs(target - v) < 0.002 then return target end
    return v
  end
  local FADES, riseDepth = {}, 0
  function K.rise(e, dy, dx)
    if e >= 1 then return end
    riseDepth = riseDepth + 1
    FADES[riseDepth] = fade
    fade = fade * (e > 0 and e or 0)
    G.push()
    G.translate((1 - e) * (dx or 0) * sc, (1 - e) * (dy or 0) * sc)
  end
  function K.settle(e)
    if e >= 1 then return end
    fade = FADES[riseDepth]
    riseDepth = riseDepth - 1
    G.pop()
  end
  -- (no cutoff on `since`: a branch flipping mid-measure made LuaJIT compile a trace inside a garbage check)
  function K.stagger(since, i, each, dur) return K.outCubic((since - i * each) / dur) end
  local function box(mode, b, rad)
    G.rectangle(mode, X(b[1]), Y(b[2]), b[3] * sc, b[4] * sc, (rad or 0) * sc, (rad or 0) * sc)
  end
  K.box = box

  -- a rounded rectangle's outline, as points (rad 0: its corners); only when a mesh is made
  local CORNERS = { {}, {}, {}, {} }
  local function roundPoints(w, h, rad)
    rad = max(0, min(rad, w / 2, h / 2))
    local seg = rad > 0 and max(2, min(10, ceil(rad / 1.5))) or 0
    local pts, hp = {}, math.pi / 2
    CORNERS[1][1], CORNERS[1][2] = w - rad, rad
    CORNERS[2][1], CORNERS[2][2] = w - rad, h - rad
    CORNERS[3][1], CORNERS[3][2] = rad, h - rad
    CORNERS[4][1], CORNERS[4][2] = rad, rad
    for k, c in ipairs(CORNERS) do
      local a0 = -hp + (k - 1) * hp
      for i = 0, seg do
        local a = a0 + (seg == 0 and 0 or hp * i / seg)
        pts[#pts + 1] = { c[1] + math.cos(a) * rad, c[2] + math.sin(a) * rad }
      end
    end
    return pts
  end

  -- a rounded rectangle shaded from `top` to `foot` (window pixels): a fan mesh, kept by its
  -- colours (the same tables every frame: constants or mix()'s) and size; flat without meshes
  local meshes, meshCount = {}, 0
  local function gradient(g, x, y, w, h, rad, top, foot, alpha)
    if w <= 0 or h <= 0 then return end
    top, foot = tf(top), tf(foot)
    local byFoot = meshes[top]
    if not byFoot then
      byFoot = {}
      meshes[top] = byFoot
    end
    local bySize = byFoot[foot]
    if not bySize then
      bySize = {}
      byFoot[foot] = bySize
    end
    local key = floor(w * 2) + floor(h * 2) * 16384 + floor(rad * 2) * 268435456
    local m = bySize[key]
    if m == nil then
      local function vertex(px, py)
        local c = mix(top, foot, py / h)
        return { px, py, 0, 0, c[1] / 255, c[2] / 255, c[3] / 255, c[4] }
      end
      local verts = { vertex(w / 2, h / 2) }
      for _, p in ipairs(roundPoints(w, h, rad)) do verts[#verts + 1] = vertex(p[1], p[2]) end
      verts[#verts + 1] = verts[2]
      local ok, made = pcall(g.newMesh, verts, "fan", "static")
      m = ok and made or false
      if meshCount > 400 then
        meshes, meshCount = {}, 0
        bySize = {}
        meshes[top] = { [foot] = bySize }
      end
      bySize[key], meshCount = m, meshCount + 1
    end
    if m then
      g.setColor(1, 1, 1, (alpha or 1) * fade)
      g.draw(m, x, y)
    else
      local c = mix(top, foot, 0.5)
      g.setColor(c[1] / 255, c[2] / 255, c[3] / 255, (c[4] or 1) * (alpha or 1))
      g.rectangle("fill", x, y, w, h, rad, rad)
    end
  end
  K.gradient = gradient
  local function grad(b, rad, top, foot, alpha)
    gradient(G, X(b[1]), Y(b[2]), b[3] * sc, b[4] * sc, (rad or 0) * sc, top, foot, alpha)
  end
  K.grad = grad
  -- a soft light (additive), rx x ry units round cx, cy; nothing without meshes
  local glowMesh
  function K.glow(cx, cy, rx, ry, c, a)
    if glowMesh == nil then
      local v = { { 0, 0, 0, 0, 1, 1, 1, 1 } }
      for i = 0, 28 do
        local t = i / 28 * 2 * math.pi
        v[#v + 1] = { math.cos(t), math.sin(t), 0, 0, 1, 1, 1, 0 }
      end
      local ok, m = pcall(G.newMesh, v, "fan", "static")
      glowMesh = ok and m or false
    end
    if not glowMesh then return end
    G.setBlendMode("add")
    c = c or WHITE
    G.setColor(c[1] / 255, c[2] / 255, c[3] / 255, (a or 1) * (c[4] or 1) * fade)
    G.draw(glowMesh, X(cx), Y(cy), 0, rx * sc, ry * sc)
    G.setBlendMode("alpha")
  end
  -- a soft shadow under b, `lift` units down
  function K.shadow(b, rad, lift, a)
    for i = 1, 3 do
      local s = i * 0.7
      col(BLACK, (a or 0.18) / 3)
      box("fill", R(b[1] - s * 0.6, b[2] - s * 0.4 + lift, b[3] + s * 1.2, b[4] + s * 1.2), (rad or 0) + s)
    end
  end
  local function ring(b, rad, c, a, w)
    ink(c, a)
    G.setLineWidth(max(1, (w or 1) * sc))
    box("line", b, rad)
  end
  K.ring = ring

  -- a tappable rectangle (units), clipped to `clip`; records kept and filled again each frame
  function K.addHit(b, kind, arg, clip)
    local x, y, w, h = X(b[1]), Y(b[2]), b[3] * sc, b[4] * sc
    if clip then
      local cx, cy, cw, ch = X(clip[1]), Y(clip[2]), clip[3] * sc, clip[4] * sc
      local x2, y2 = min(x + w, cx + cw), min(y + h, cy + ch)
      x, y = max(x, cx), max(y, cy)
      w, h = x2 - x, y2 - y
      if w <= 0 or h <= 0 then return end
    end
    nHitRec = nHitRec + 1
    local rec = hitPool[nHitRec]
    if not rec then
      rec = {}
      hitPool[nHitRec] = rec
    end
    rec[1], rec[2], rec[3], rec[4], rec.kind, rec.arg = x, y, w, h, kind, arg
    hits[#hits + 1] = rec
  end
  -- keep only the hits of `kind` (a sheet over everything)
  function K.keepHits(kind)
    local n = 0
    for i = 1, #hits do
      if hits[i].kind == kind then
        n = n + 1
        hits[n] = hits[i]
      end
    end
    for i = #hits, n + 1, -1 do hits[i] = nil end
  end
  function K.inside(q, x, y) return x >= q[1] and y >= q[2] and x < q[1] + q[3] and y < q[2] + q[4] end

  -- ♀ / ♂: the fonts have neither (NIDORAN♀ drew a box), so a text with one is split once into runs and
  -- signs (kept, bounded; false: no sign after all) and each sign drawn as a mark in the text's colour.
  -- So is the Game Boy games' PkMn (their <PK><MN> tiles): K.PKMN in a text (a private-use character)
  -- draws as the small staggered P K M N
  local SIGN = "\226\153"
  local PKMN = "\238\128\128"
  K.PKMN = PKMN
  local SIGN_F, SIGN_M = { 255, 85, 140 }, { 60, 135, 255 }
  local signCache, signCount = {}, 0
  local function signsOf(s)
    local p = signCache[s]
    if p ~= nil then return p end
    if signCount > 300 then signCache, signCount = {}, 0 end
    local runs, sex, plain, i, from, nG, nP = {}, {}, {}, 1, 1, 0, 0
    while true do
      local at, atP = s:find(SIGN, i, true), s:find(PKMN, i, true)
      if atP and (not at or atP < at) then
        runs[#runs + 1] = s:sub(from, atP - 1)
        plain[#plain + 1] = runs[#runs]
        plain[#plain + 1] = "PkMn"
        sex[#runs], nP = "P", nP + 1
        from, i = atP + 3, atP + 3
      elseif at then
        local b = s:byte(at + 2)
        if b == 128 or b == 130 then
          runs[#runs + 1] = s:sub(from, at - 1)
          plain[#plain + 1] = runs[#runs]
          sex[#runs], nG = b == 128 and "F" or "M", nG + 1
          from = at + 3
        end
        i = at + 3
      else
        break
      end
    end
    if #runs == 0 then
      p = false
    else
      runs[#runs + 1] = s:sub(from)
      plain[#plain + 1] = runs[#runs]
      p = { runs = runs, sex = sex, plain = table.concat(plain), nG = nG, nP = nP }
    end
    signCache[s], signCount = p, signCount + 1
    return p
  end
  local function signed(s)
    if type(s) ~= "string" or not (s:find(SIGN, 1, true) or s:find(PKMN, 1, true)) then return nil end
    return signsOf(s) or nil
  end
  -- (a sign's width in a text of `size` units, its gap before included)
  local function signW(size) return size * 0.7 end
  -- (PkMn's: its four small letters, each tucked in under the one before)
  local PK_K, PK_ADV = 0.62, 0.86
  local function pkW(size) return font(size * PK_K * sc):getWidth("PKMN") / sc * PK_ADV + size * 0.1 end
  local function marksW(p, size) return p.nG * signW(size) + (p.nP > 0 and p.nP * pkW(size) or 0) end
  -- (PkMn drawn at x in a text of `size` at y, in the colour set; the text's font f set back after)
  local PK_CH = { "P", "K", "M", "N" }
  local function pkLetters(x, y, size, f)
    local sf = font(size * PK_K * sc)
    G.setFont(sf)
    local cx = x + size * 0.05
    for k = 1, 4 do
      local ch = PK_CH[k]
      -- (P and M high, K and N low, as the tiles have them)
      G.print(ch, X(cx), Y(y + (k % 2 == 1 and size * 0.06 or size * 0.38)))
      cx = cx + sf:getWidth(ch) / sc * PK_ADV
    end
    G.setFont(f)
  end
  -- a ♀ ("F") or ♂ ("M") s units tall, its top left at x, y, in the colour set
  local function sexLines(sex, x, y, s)
    G.setLineWidth(max(1, s * 0.15 * sc))
    local r = s * 0.27
    local cx = x + r + s * 0.06
    if sex == "F" then
      local cy = y + s * 0.34
      G.circle("line", X(cx), Y(cy), r * sc)
      G.line(X(cx), Y(cy + r), X(cx), Y(cy + r + s * 0.36))
      G.line(X(cx - s * 0.15), Y(cy + r + s * 0.18), X(cx + s * 0.15), Y(cy + r + s * 0.18))
    else
      local cy = y + s * 0.62
      local d = r * 0.72
      local tx, ty = cx + d + s * 0.26, cy - d - s * 0.26
      G.circle("line", X(cx), Y(cy), r * sc)
      G.line(X(cx + d), Y(cy - d), X(tx), Y(ty))
      G.line(X(tx), Y(ty), X(tx - s * 0.2), Y(ty))
      G.line(X(tx), Y(ty), X(tx), Y(ty + s * 0.2))
    end
  end
  -- a ♀ / ♂ mark ("F" | "M", either case) s units tall at x, y, in c (default the sign's own pink / blue)
  function K.sexMark(sex, x, y, s, a, c)
    local f = sex == "F" or sex == "f"
    col(c or (f and SIGN_F or SIGN_M), a)
    local lw = G.getLineWidth and G.getLineWidth() or 1
    sexLines(f and "F" or "M", x, y, s)
    G.setLineWidth(lw)
  end
  -- does s carry a ♀ / ♂ (a name that shows its own sign: no separate mark beside it, as the games do)
  function K.hasSign(s)
    local p = signed(s)
    return p ~= nil and p.nG > 0
  end

  -- the player's text size (Settings > Display or the mod option, set by main.lua): every text drawn this
  -- much bigger and measured at it (K.width, K.fit), so what's laid out after a text moves with it and
  -- a fitted text still fits; it grows round its line's middle, so a centred line stays centred, and a
  -- line given a width it fitted at 1x shrinks back into it rather than wrap or run over
  local TS = 1
  function K.setTextScale(v) TS = max(1, min(1.6, tonumber(v) or 1)) end
  function K.textScale() return TS end
  -- (a line's height at a size: a stacked line's step, as big as its text is drawn)
  function K.lineH(size) return size * TS end

  -- (a text's width at exactly `size`)
  local function measure(s, size)
    local p = signed(s)
    if p then
      local f, n = font(size * sc), 0
      for i = 1, #p.runs do n = n + f:getWidth(p.runs[i]) end
      return n / sc + marksW(p, size)
    end
    return font(size * sc):getWidth(s) / sc
  end
  local function width(s, size) return measure(s, size * TS) end
  K.width = width
  -- (a text with signs: on one line, runs and marks in turn; a wrapped one without its signs)
  local function signedText(p, f, x, y, size, align, w)
    local tw = 0
    for i = 1, #p.runs do tw = tw + f:getWidth(p.runs[i]) / sc end
    tw = tw + marksW(p, size)
    if align and w and tw > w + 0.01 then
      G.printf(p.plain, X(x), Y(y), w * sc, align)
      return
    end
    local cx = x
    if align == "center" then cx = x + (w - tw) / 2 elseif align == "right" then cx = x + w - tw end
    local lw = G.getLineWidth and G.getLineWidth() or 1
    local ms = size * 0.78
    for i = 1, #p.runs do
      local run = p.runs[i]
      if run ~= "" then
        G.print(run, X(cx), Y(y))
        cx = cx + f:getWidth(run) / sc
      end
      local sx = p.sex[i]
      if sx == "P" then
        pkLetters(cx, y, size, f)
        cx = cx + pkW(size)
      elseif sx then
        sexLines(sx, cx + size * 0.14, y + size * 0.16, ms)
        cx = cx + signW(size)
      end
    end
    G.setLineWidth(lw)
  end
  -- the text audit (the tests' text-size check; K.audit = { n = 0 } turns it on, nil off): each text's
  -- ink this frame (units) and the clip it was drawn in, read by K.auditIssues
  K.audit = nil
  -- (an overlay starts: a dim, a sheet, a toast, a window's own banner; texts under it and over it aren't
  -- compared)
  function K.auditLayer()
    local A = K.audit
    if A then A.layer = (A.layer or 0) + 1 end
  end
  local function auditText(s, x, y, size, align, w, f, a)
    local A = K.audit
    if (a or 1) * fade < 0.05 or s == "" then return end
    local tw, lines = measure(s, size), 1
    if align and w and tw > w + 0.01 then
      local ok, _, ls = pcall(f.getWrap, f, tostring(s), w * sc)
      lines = ok and type(ls) == "table" and math.max(1, #ls) or math.ceil(tw / math.max(1, w))
      tw = w
    end
    local x1 = x
    if align == "center" and w then x1 = x + (w - tw) / 2 elseif align == "right" and w then x1 = x + w - tw end
    local lh = size * 1.2
    local okH, fh = pcall(f.getHeight, f)
    if okH and tonumber(fh) then lh = fh / sc end
    local cx, cy, cw, ch
    if G.getScissor then cx, cy, cw, ch = G.getScissor() end
    A.n = A.n + 1
    A[A.n] = { s = tostring(s), x1 = x1, y1 = y + size * 0.22, x2 = x1 + tw, y2 = y + (lines - 1) * lh + size * 1.02,
               lines = lines, size = size, layer = A.layer or 0,
               cx1 = cx and (cx - ox) / sc, cy1 = cy and (cy - oy) / sc,
               cx2 = cx and (cx + cw - ox) / sc, cy2 = cy and (cy + ch - oy) / sc }
  end
  -- what the audit saw, as { kind, text, other } records: "overlap" (two texts' ink crossing; a text and
  -- its shadow or bold twin aren't counted), "clipX" / "clipY" (a text out past the clip it was drawn
  -- in), "wrap" (a text in more lines than `prev` had it, when given)
  function K.auditIssues(A)
    local out = {}
    for i = 1, A.n do
      local t = A[i]
      if t.cx1 then
        if t.x1 < t.cx1 - 0.4 or t.x2 > t.cx2 + 0.4 then
          -- (all of it out of the clip: not drawn at all, a list's row off its end)
          if t.x2 > t.cx1 and t.x1 < t.cx2 and t.y2 > t.cy1 and t.y1 < t.cy2 then out[#out + 1] = { "clipX", t.s } end
        end
        if (t.y1 < t.cy1 - 0.4 or t.y2 > t.cy2 + 0.4) and t.y2 > t.cy1 and t.y1 < t.cy2 then out[#out + 1] = { "clipY", t.s } end
      end
      for j = i + 1, A.n do
        local u = A[j]
        local twin = t.s == u.s and math.abs(t.x1 - u.x1) < 1.2 and math.abs(t.y1 - u.y1) < 1.2
        if not twin and t.layer == u.layer then
          local ix = math.min(t.x2, u.x2) - math.max(t.x1, u.x1)
          local iy = math.min(t.y2, u.y2) - math.max(t.y1, u.y1)
          if ix > 0.5 and iy > 0.5 then
            -- (both shown in the same clip; a text drawn where another is clipped away isn't an overlap)
            local vis = function(r, px, py)
              return not r.cx1 or (px >= r.cx1 and px <= r.cx2 and py >= r.cy1 and py <= r.cy2)
            end
            local mx, my = (math.max(t.x1, u.x1) + math.min(t.x2, u.x2)) / 2, (math.max(t.y1, u.y1) + math.min(t.y2, u.y2)) / 2
            if vis(t, mx, my) and vis(u, mx, my) then out[#out + 1] = { "overlap", t.s, u.s } end
          end
        end
      end
    end
    return out
  end

  local function text(s, x, y, size, c, align, w, a)
    if TS ~= 1 then
      local big = size * TS
      -- (a line that fitted its width at 1x stays on one line, in it)
      if align and w then
        local w1 = measure(s, size)
        if w1 <= w + 0.01 then
          -- (fonts come in whole pixels: stepped down until it truly fits, never under its 1x size)
          local wb = measure(s, big)
          local k = 0
          while wb > w and big > size and k < 4 do
            big = max(size, big * w / wb * 0.985)
            wb, k = measure(s, big), k + 1
          end
        end
      end
      y = y - (big - size) * 0.6
      size = big
    end
    local f = font(size * sc)
    G.setFont(f)
    ink(c, a)
    if K.audit then auditText(s, x, y, size, align, w, f, a) end
    local p = signed(s)
    if p then
      signedText(p, f, x, y, size, align, w)
      return f
    end
    if align then
      G.printf(s, X(x), Y(y), w * sc, align)
    else
      G.print(s, X(x), Y(y))
    end
    return f
  end
  K.text = text
  -- text that sits on colour: a faint shadow under it
  function K.label(s, x, y, size, c, align, w, a)
    hold = hold + 1
    text(s, x, y + 0.5, size, BLACK, align, w, 0.22 * (a or 1))
    hold = hold - 1
    return text(s, x, y, size, c, align, w, a)
  end
  -- a font size that fits s in w units at the text size (smaller only; never under 3.5 units drawn)
  function K.fit(s, size, w)
    local tw = width(s, size)
    if w and tw > w and tw > 0 then
      local floorS = 3.5 / TS
      local fs = max(floorS, size * w / tw * 0.97)
      -- (fonts come in whole pixels: a step or two more where the rounding still left it too wide)
      local k = 0
      while k < 3 and fs > floorS and width(s, fs) > w do
        fs, k = max(floorS, fs * 0.95), k + 1
      end
      return fs
    end
    return size
  end
  function K.scissor(b)
    if b then G.setScissor(X(b[1]), Y(b[2]), max(0, b[3] * sc), max(0, b[4] * sc)) else G.setScissor() end
  end
  -- the scissor there is, set again: after anything that drew into a canvas in the middle of a draw
  -- (WoobleSpritePack making a frame, the engine a picture, ours painting an icon). LÖVE's pop puts
  -- the scissor back while that canvas is still bound, so the GL scissor is worked out for the canvas
  -- and clips everything after it (the Pokédex's page flashed empty 8 times a second) until the
  -- next setScissor, though getScissor reads right
  function K.rescissor()
    if not (G and G.getScissor) then return end
    local x, y, w, h = G.getScissor()
    if x then G.setScissor(x, y, w, h) else G.setScissor() end
  end
  function K.pulse() return 0.7 + 0.3 * math.sin(K.t * 6) end

  -- values as text, kept (bounded)
  function K.textCache(make)
    local cache, count = {}, 0
    return function(n)
      local v = cache[n]
      if not v then
        if count > 500 then cache, count = {}, 0 end
        v = make(n)
        cache[n], count = v, count + 1
      end
      return v
    end
  end

  -- held D-pad: true on the press, then after `start` steps every `every` (the game's menus)
  function K.repeater(start, every)
    return function(input, key, held)
      if input:wasPressed(key) then
        held[key] = 0
        return true
      end
      local okD, down = pcall(input.isDown, input, key)
      if not (okD and down) then
        held[key] = nil
        return false
      end
      held[key] = (held[key] or 0) + 1
      local n = held[key] - start
      return n >= 0 and n % every == 0
    end
  end

  -- start a frame: the page laid out on the window's safe area -> pw, ph (units), portrait
  function K.frame(g, vp, page, clock)
    G = g
    nRect, nHitRec, fade, riseDepth, hold = 0, 0, 1, 0, 0
    for i = #hits, 1, -1 do hits[i] = nil end
    local ww = tonumber(vp.width) or (tonumber(vp.gameX) or 0) * 2 + (tonumber(vp.gameWidth) or 240)
    local wh = tonumber(vp.height) or (tonumber(vp.gameY) or 0) * 2 + (tonumber(vp.gameHeight) or 160)
    local ax, ay, aw, ah = 0, 0, ww, wh
    if deps.safeArea and not vp.noSafeArea then
      local ok, sx, sy, sw, sh = pcall(deps.safeArea)
      if ok and tonumber(sx) and tonumber(sy) and tonumber(sw) and tonumber(sh) then
        -- (inside the window the hud was handed)
        local x2, y2 = min(ww, sx + sw), min(wh, sy + sh)
        sx, sy = max(0, sx), max(0, sy)
        if x2 - sx > ww * 0.5 and y2 - sy > wh * 0.5 then ax, ay, aw, ah = sx, sy, x2 - sx, y2 - sy end
      end
    end
    local portrait = aw / ah < page.portraitAspect
    local pw, ph
    if portrait then
      sc = min(aw / page.portraitWidth, ah / page.portraitHeight)
      pw, ph = aw / sc, ah / sc
    else
      sc = min(ah / page.height, aw / page.minWidth)
      pw, ph = min(page.maxWidth, aw / sc), ah / sc
    end
    ox, oy = ax + (aw - pw * sc) / 2, ay
    K.sc, K.ox, K.oy, K.ww, K.wh = sc, ox, oy, ww, wh
    K.t = clock or 0
    return pw, ph, portrait
  end
  -- start a frame at a scale of our own: units from x, y (window pixels), `scale` pixels each (the
  -- field's banner, in the game's own pixels)
  function K.place(g, x, y, scale, clock)
    G = g
    nRect, nHitRec, fade = 0, 0, 1
    for i = #hits, 1, -1 do hits[i] = nil end
    sc, ox, oy = scale, x, y
    K.sc, K.ox, K.oy = sc, ox, oy
    K.t = clock or 0
  end
  -- the transform alone, the frame's pools and hits kept (a host drawing a window zoomed:
  -- set, draw, set back) -> the one it replaced
  function K.transform(nsc, nox, noy)
    local psc, pox, poy = sc, ox, oy
    sc, ox, oy = nsc, nox, noy
    K.sc, K.ox, K.oy = sc, ox, oy
    return psc, pox, poy
  end
  function K.graphics() return G end

  -- ------- pieces

  -- the name on a metal plate: brushed silver, a bevel, a screw at each end; the letters italic
  -- and outlined, the first word in `accent`, the rest in `body`; x, y its top left, maxW its room
  local PLATE = { top = { 242, 244, 248 }, foot = { 146, 152, 166 }, clear = { 255, 255, 255, 0 },
                  shine = { 255, 255, 255, 0.4 }, screwTop = { 250, 250, 252 }, screwFoot = { 120, 124, 136 } }
  local OUTLINE_AT = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }
  local titleChars = {}
  local function charsOf(title)
    local cs = titleChars[title]
    if not cs then
      cs = {}
      for ch in title:gmatch(".") do cs[#cs + 1] = ch end
      cs.split = #(title:match("^(%S+)") or title)
      titleChars[title] = cs
    end
    return cs
  end
  local function plateLetters(chars, split, size, spacing, x, y, c, c2, alpha)
    G.push()
    G.translate(X(x), Y(y))
    G.shear(-0.2, 0)
    local cx = 0
    for i, ch in ipairs(chars) do
      col(c2 and i > split and c2 or c, alpha)
      G.print(ch, cx * sc, 0)
      cx = cx + width(ch, size) + spacing
    end
    G.pop()
  end
  function K.drawPlate(title, x, y, maxW, accent, body, outline, height)
    local chars = charsOf(title)
    local split = chars.split
    local SPACING, PAD, SCREW = 0.55, 8.5, 3.6
    local ph2 = height or 15
    local size = 7.5 * ph2 / 15
    local tw
    for pass = 1, 2 do
      tw = -SPACING
      for _, ch in ipairs(chars) do tw = tw + width(ch, size) + SPACING end
      if pass == 2 or tw + PAD * 2 <= maxW then break end
      size = max(4, size * (maxW - PAD * 2) / tw)
    end
    local plate = R(x, y, min(maxW, tw + PAD * 2), ph2)
    local px, py, pw2 = plate[1], plate[2], plate[3]
    K.shadow(plate, 3.5, 0.9, 0.35)
    grad(plate, 3.5, PLATE.top, PLATE.foot)
    grad(R(px + 2.5, py + ph2 * 0.52, pw2 - 5, ph2 * 0.4), 0, PLATE.clear, PLATE.shine)
    for i = 1, 4 do
      col(WHITE, 0.12)
      box("fill", R(px + 3, py + 2 + i * 2.4 * ph2 / 15, pw2 - 6, 0.35))
    end
    col(WHITE, 0.85)
    box("fill", R(px + 2.5, py + 0.7, pw2 - 5, 0.6), 0.3)
    ring(R(px + 0.6, py + 0.6, pw2 - 1.2, ph2 - 1.2), 3, WHITE, 0.45, 0.6)
    ring(plate, 3.5, dark(outline, 0.3), 1, 0.8)
    for k = 0, 1 do
      local sx, sy = px + SCREW + k * (pw2 - SCREW * 2), py + ph2 / 2
      gradient(G, X(sx - 1.5), Y(sy - 1.5), 3 * sc, 3 * sc, 1.5 * sc, PLATE.screwTop, PLATE.screwFoot)
      col(dark(outline, 0.2), 0.8)
      G.setLineWidth(max(1, 0.45 * sc))
      G.line(X(sx - 1), Y(sy + 0.7), X(sx + 1), Y(sy - 0.7))
    end
    local f = font(size * sc)
    G.setFont(f)
    local lineH = f:getHeight() / sc
    local tx = px + (pw2 - tw) / 2 + 0.6
    local ty = py + (ph2 - lineH) / 2 - 0.2
    local firstColor, restColor, edge = dark(accent, 0.12), dark(body, 0.15), dark(outline, 0.45)
    for _, d in ipairs(OUTLINE_AT) do
      plateLetters(chars, split, size, SPACING, tx + d[1] * 0.5, ty + d[2] * 0.5 + 0.2, edge, nil, 1)
    end
    plateLetters(chars, split, size, SPACING, tx, ty, firstColor, restColor, 1)
    plateLetters(chars, split, size, SPACING, tx + 0.3, ty, firstColor, restColor, 1)
    G.setScissor(X(px), Y(py), pw2 * sc, (ty - py + lineH * 0.48) * sc)
    plateLetters(chars, split, size, SPACING, tx + 0.15, ty, WHITE, nil, 0.3)
    G.setScissor()
    return plate
  end

  -- the W: four slanted strokes folded like a ribbon (the outer two in `accent`, the inner two
  -- lighter, under them), over a soft glow; centred on cx, cy (window pixels), `size` wide
  local STROKES = { { 0, 0.25, 0, 1 }, { 0.25, 0.5, 1, 0.3 }, { 0.5, 0.75, 0.3, 1 }, { 0.75, 1, 1, 0 } }
  local STROKE_ORDER, OUTER = { 2, 3, 1, 4 }, { 1, 4 }
  local logoQuad = { 0, 0, 0, 0, 0, 0, 0, 0 }
  local lw, lh, lx0, ly0, lth, lslant
  local function quad(sx)
    local span = lw - lth - lslant
    local ax, ay = lx0 + sx[1] * span + (1 - sx[3]) * lslant, ly0 + sx[3] * lh
    local bx, by = lx0 + sx[2] * span + (1 - sx[4]) * lslant, ly0 + sx[4] * lh
    local q = logoQuad
    q[1], q[2], q[3], q[4], q[5], q[6], q[7], q[8] = ax, ay, ax + lth, ay, bx + lth, by, bx, by
    return q
  end
  function K.drawLogo(cx, cy, size, accent, a, soft)
    if a <= 0 then return end
    lw, lh = size, size * 0.62
    lx0, ly0 = cx - lw / 2, cy - lh / 2
    lth, lslant = lw * 0.17, lw * 0.07
    soft = soft or light(accent, 0.45)
    for i = 3, 1, -1 do
      G.setColor(accent[1] / 255, accent[2] / 255, accent[3] / 255, 0.07 * a)
      G.push()
      G.translate(cx, cy)
      G.scale(1 + i * 0.07, 1 + i * 0.1)
      G.translate(-cx, -cy)
      for _, sx in ipairs(STROKES) do G.polygon("fill", quad(sx)) end
      G.pop()
    end
    G.setColor(0, 0, 0, 0.3 * a)
    G.push()
    G.translate(size * 0.02, size * 0.03)
    for _, sx in ipairs(STROKES) do G.polygon("fill", quad(sx)) end
    G.pop()
    for _, i in ipairs(STROKE_ORDER) do
      local c = (i == 1 or i == 4) and accent or soft
      G.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a)
      G.polygon("fill", quad(STROKES[i]))
    end
    G.setColor(1, 1, 1, 0.35 * a)
    G.setLineWidth(max(1, size * 0.012))
    for _, i in ipairs(OUTER) do
      local q = quad(STROKES[i])
      G.line(q[1], q[2], q[7], q[8])
    end
  end

  -- the button hints: { { key, words }, ... } in `hb` (units), wrapping onto more lines; centred
  -- when `center`; keyInk the key caps' letters
  function K.hints(list, hb, keyInk, center, wordColor, keyFill)
    local hx, hy = hb[1], hb[2]
    if center then
      local total = 0
      for _, h in ipairs(list) do total = total + max(8, width(h[1], 4.5) + 4) + 2 + width(h[2], 5) + 6 end
      hx = hb[1] + max(0, (hb[3] - total + 6) / 2)
    end
    for _, h in ipairs(list) do
      local kw = max(8, width(h[1], 4.5) + 4)
      local tw = width(h[2], 5)
      if hx > hb[1] and hx + kw + 2 + tw > hb[1] + hb[3] then hx, hy = hb[1], hy + 10 end
      if hy + 8 <= hb[2] + hb[4] + 0.5 then
        col(keyFill or WHITE, 0.9)
        box("fill", R(hx, hy, kw, 8), 4)
        text(h[1], hx, hy + 1.4, 4.5, keyInk, "center", kw)
        if wordColor then
          text(h[2], hx + kw + 2, hy + 1.2, 5, wordColor)
        else
          K.label(h[2], hx + kw + 2, hy + 1.2, 5, WHITE)
        end
      end
      hx = hx + kw + 2 + tw + 6
    end
  end

  -- a toast pill near the foot of `area` (units): state = { text, bad, t }; -> false once gone
  function K.toast(state, clock, area, badColor, goodColor, ink)
    K.auditLayer()
    local age = clock - state.t
    local a = age < 2.2 and min(1, age / 0.15 + 0.01) or max(0, 1 - (age - 2.2) / 0.4)
    if a <= 0 then return false end
    local tw2 = min(area[3] - 10, width(state.text, 5.5) + 20)
    local tb = R(area[1] + (area[3] - tw2) / 2, area[2] + area[4] - 17 + (1 - min(1, age / 0.15)) * 4, tw2, 12)
    K.shadow(tb, 6, 1, 0.25 * a)
    col(state.bad and badColor or ink, 0.94 * a)
    box("fill", tb, 6)
    col(state.bad and WHITE or goodColor, a)
    G.circle("fill", X(tb[1] + 6.5), Y(tb[2] + 6), 1.8 * sc)
    local fs = K.fit(state.text, 5.5, tb[3] - 14)
    text(state.text, tb[1] + 6, tb[2] + 2.6 + (5.5 - fs) * 0.5, fs, WHITE, "center", tb[3] - 8, a)
    return true
  end

  -- ------- the windows' look (macOS / iOS): one palette and the controls every window shares

  local UI = {
    label = { 28, 28, 30 }, secondary = { 112, 112, 120 }, tertiary = { 162, 162, 170 },
    separator = { 60, 60, 67, 0.16 }, grouped = { 242, 242, 247 }, card = { 255, 255, 255 },
    sidebar = { 232, 232, 237 }, fill = { 118, 118, 128, 0.13 }, fillOn = { 118, 118, 128, 0.22 },
    accent = { 10, 132, 255 }, red = { 255, 59, 48 }, green = { 52, 199, 89 }, orange = { 255, 149, 0 },
    yellow = { 255, 189, 46 }, toolbar = { 252, 252, 253 }, toolbarFoot = { 240, 240, 244 },
    accentSoft = { 10, 132, 255, 0.13 }, hud = { 36, 36, 40 },
  }
  K.UI = UI

  -- text a touch heavier (drawn twice, under a pixel apart): titles, the chosen segment
  function K.bold(s, x, y, size, c, align, w, a)
    text(s, x, y, size, c, align, w, a)
    return text(s, x + 0.55 / sc, y, size, c, align, w, a)
  end
  -- a one-pixel rule (a list's separator), across or down
  function K.hairline(x, y, w, c, a)
    ink(c or UI.separator, a)
    G.rectangle("fill", X(x), floor(Y(y)), w * sc, max(1, 0.25 * sc))
  end
  function K.vline(x, y, h, c, a)
    ink(c or UI.separator, a)
    G.rectangle("fill", floor(X(x)), Y(y), max(1, 0.25 * sc), h * sc)
  end
  -- a chevron `s` units tall centred on cx, cy: dir 1 right, -1 left, 2 down
  function K.chevron(cx, cy, s, c, dir, a)
    ink(c, a)
    G.setLineWidth(max(1, s * 0.17 * sc))
    local h, d = s * 0.5, s * 0.28
    local x, y = X(cx), Y(cy)
    if dir == 2 then
      G.line(x - h * sc, y - d * sc, x, y + d * sc, x + h * sc, y - d * sc)
    else
      G.line(x - dir * d * sc, y - h * sc, x + dir * d * sc, y, x - dir * d * sc, y + h * sc)
    end
  end
  -- a white rounded card on the grouped ground
  function K.card(b, rad)
    col(UI.card)
    box("fill", b, rad or 4)
  end
  -- a list row's highlight: the accent while its list has the focus, grey when it doesn't
  function K.selection(b, focused, rad, c)
    col(focused and (c or UI.accent) or UI.fillOn)
    box("fill", b, rad or 2.5)
  end
  -- the keyboard-focus ring macOS draws round a control
  function K.focusRing(b, rad, a)
    ring(R(b[1] - 1, b[2] - 1, b[3] + 2, b[4] + 2), (rad or 0) + 1, UI.accent, (a or 1) * 0.6, 0.9)
  end
  -- a capsule button: style "accent" | "danger" (filled) | "gray" (a grey fill, dark words) |
  -- "tinted" (a pale accent fill, accent words); `focused` rings it
  function K.button(b, label, style, focused, size)
    local rad = min(b[4] / 2, 3.2)
    if style == "accent" or style == "danger" then
      col(style == "danger" and UI.red or UI.accent)
    elseif style == "tinted" then
      col(UI.accentSoft)
    else
      col(UI.fill)
    end
    box("fill", b, rad)
    if focused then K.focusRing(b, rad) end
    size = size or 4.6
    local fs = K.fit(label, size, b[3] - 3)
    local ink = (style == "accent" or style == "danger") and WHITE or (style == "tinted" and UI.accent or UI.label)
    K.bold(label, b[1], b[2] + (b[4] - fs * 1.2) / 2, fs, ink, "center", b[3])
  end
  -- the segmented control: up to three segments (each its hit arg and words), `sel` raised
  function K.segmented(x, y, w, h, sel, kind, a1, l1, a2, l2, a3, l3)
    local n = a3 and 3 or 2
    local tb = R(x, y, w, h)
    local rad = min(h / 2, 2.6)
    col(UI.fill)
    box("fill", tb, rad)
    local sw = (w - 1) / n
    for i = 1, n do
      local sb = R(x + 0.5 + (i - 1) * sw, y + 0.5, sw, h - 1)
      local label = i == 1 and l1 or (i == 2 and l2 or l3)
      local fs = K.fit(label, 4.3, sw - 2)
      local ty = sb[2] + (sb[4] - fs * 1.2) / 2
      if i == sel then
        col(BLACK, 0.1)
        box("fill", R(sb[1], sb[2] + 0.3, sb[3], sb[4]), rad - 0.5)
        col(WHITE)
        box("fill", sb, rad - 0.5)
        K.bold(label, sb[1], ty, fs, UI.label, "center", sb[3])
      else
        if i > 1 and i - 1 ~= sel then K.vline(sb[1], sb[2] + 1.5, sb[4] - 3) end
        text(label, sb[1], ty, fs, UI.label, "center", sb[3])
      end
      K.addHit(sb, kind, i == 1 and a1 or (i == 2 and a2 or a3))
    end
  end
  -- frosted glass (the Pokédex, Condition): a pane of `tint` (white) at `a` (0.5), a sheen down from its
  -- top edge at `sheen` (1) of itself, a bright edge at `edge` (0.8); nothing behind it is blurred, so it
  -- sits over soft things (K.backdrop)
  local SHEEN_TOP, SHEEN_FOOT = { 255, 255, 255, 0.55 }, { 255, 255, 255, 0 }
  function K.glass(b, rad, a, tint, sheen, edge)
    K.shadow(b, rad, 1.2, 0.07)
    col(tint or WHITE, a or 0.5)
    box("fill", b, rad)
    -- (dark: the sheen a faint light from the top, the edge dimmer; as given, not darkened)
    local dk = themeN ~= 0 and hold == 0
    hold = hold + 1
    grad(R(b[1], b[2], b[3], min(b[4], 16)), rad, SHEEN_TOP, SHEEN_FOOT, (sheen or 1) * (dk and 0.16 or 1))
    ring(b, rad, WHITE, (edge or 0.8) * (dk and 0.28 or 1), 0.35)
    hold = hold - 1
  end
  -- the backdrop glass sits on: a pale wash of the first colour with four soft lights drifting slowly
  -- over b (the first colour, the second, a violet, a pink); colours 0..1, numbers only
  local blobMesh
  local function blob(cx, cy, rx, ry, r, g, bl, a)
    if themeN ~= 0 and hold == 0 then a = a * (themeN == 2 and 0.3 or 0.42) end
    G.setColor(r, g, bl, a * fade)
    G.draw(blobMesh, X(cx), Y(cy), 0, rx * sc, ry * sc)
  end
  function K.backdrop(b, clock, r, g, bl, r2, g2, b2)
    local x, y, w, h = b[1], b[2], b[3], b[4]
    K.scissor(b)
    -- (dark: a deep wash of the colour, OLED black; the lights dimmer over it)
    local dk = themeN ~= 0 and hold == 0
    if themeN == 2 and dk then
      G.setColor(0, 0, 0, fade)
    elseif dk then
      G.setColor(0.07 + r * 0.1, 0.07 + g * 0.1, 0.08 + bl * 0.1, fade)
    else
      G.setColor(0.93 + (r - 0.93) * 0.3, 0.93 + (g - 0.93) * 0.3, 0.95 + (bl - 0.95) * 0.3, fade)
    end
    box("fill", b)
    if blobMesh == nil then
      local v = { { 0, 0, 0, 0, 1, 1, 1, 1 } }
      for i = 0, 32 do
        local t = i / 32 * 2 * math.pi
        v[#v + 1] = { math.cos(t), math.sin(t), 0, 0, 1, 1, 1, 0 }
      end
      local ok, m = pcall(G.newMesh, v, "fan", "static")
      blobMesh = ok and m or false
    end
    if not blobMesh then return end
    local sin, cos = math.sin, math.cos
    blob(x + w * (0.74 + 0.07 * sin(clock * 0.11)), y + h * (0.22 + 0.08 * cos(clock * 0.09)), w * 0.5, h * 0.62,
      r, g, bl, 0.9)
    blob(x + w * (0.24 + 0.08 * cos(clock * 0.07)), y + h * (0.82 + 0.06 * sin(clock * 0.1)), w * 0.46, h * 0.6,
      r2, g2, b2, 0.75)
    blob(x + w * (0.48 + 0.1 * sin(clock * 0.05 + 1)), y + h * (0.5 + 0.1 * cos(clock * 0.06)), w * 0.3, h * 0.45,
      0.55, 0.5, 1, 0.38)
    blob(x + w * (0.08 + 0.05 * cos(clock * 0.08)), y + h * (0.1 + 0.06 * sin(clock * 0.12)), w * 0.28, h * 0.4,
      1, 0.62, 0.7, 0.36)
  end
  -- a glass switch of two, three or four: its white thumb slides to `shown` (1 .. n, eased by the caller);
  -- each segment a hit of `kind`, args a1 .. a4 (the fourth after `size`)
  function K.glassSwitch(x, y, w, h, shown, kind, a1, l1, a2, l2, a3, l3, size, a4, l4, a5, l5)
    local n = a5 and 5 or (a4 and 4 or (a3 and 3 or 2))
    local rad = h / 2
    local tb = R(x, y, w, h)
    -- (dark: a dark track and a lighter thumb, as given)
    local dk = themeN ~= 0 and hold == 0
    hold = hold + 1
    col(dk and BLACK or WHITE, dk and 0.45 or 0.32)
    box("fill", tb, rad)
    ring(tb, rad, WHITE, dk and 0.16 or 0.7, 0.3)
    local sw = (w - 1) / n
    local tx = x + 0.5 + (shown - 1) * sw
    col(BLACK, dk and 0.25 or 0.1)
    box("fill", R(tx, y + 0.9, sw, h - 1), rad - 0.5)
    col(WHITE, dk and 0.24 or 1)
    box("fill", R(tx, y + 0.5, sw, h - 1), rad - 0.5)
    hold = hold - 1
    for i = 1, n do
      local label = i == 1 and l1 or (i == 2 and l2 or (i == 3 and l3 or (i == 4 and l4 or l5)))
      local sb = R(x + 0.5 + (i - 1) * sw, y + 0.5, sw, h - 1)
      local fs = K.fit(label, size or 4.3, sw - 2)
      local ty = sb[2] + (sb[4] - fs * 1.2) / 2
      if math.abs(shown - i) < 0.5 then
        K.bold(label, sb[1], ty, fs, UI.label, "center", sb[3])
      else
        text(label, sb[1], ty, fs, UI.secondary, "center", sb[3])
      end
      K.addHit(sb, kind, i == 1 and a1 or (i == 2 and a2 or (i == 3 and a3 or (i == 4 and a4 or a5))))
    end
  end
  -- a sheet or popover over a dimmed window: the dim, then the card with its shadow
  function K.dim(b, a)
    K.auditLayer()
    col(BLACK, a or 0.22)
    box("fill", b)
  end
  function K.sheet(b, rad)
    K.auditLayer()
    rad = rad or 6
    K.shadow(b, rad, 1.6, 0.3)
    col(UI.card)
    box("fill", b, rad)
    ring(b, rad, BLACK, 0.06, 0.4)
  end
  -- a thin scroll indicator at the right of a list
  function K.scrollbar(x, y, h, top, visible, total)
    if total <= visible then return end
    local bh = max(6, h * visible / total)
    local by = y + (h - bh) * (top / max(1, total - visible))
    col(BLACK, 0.22)
    box("fill", R(x - 1.6, by + 0.5, 1.1, bh - 1), 0.55)
  end

  return K
end
