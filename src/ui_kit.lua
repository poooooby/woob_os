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
--   K = Kit(deps)        deps: safeArea() -> x, y, w, h (window pixels) or nil
--   K.frame(G, vp, page, now) -> pw, ph, portrait   starts a frame: the window from the render.hud
--         viewport (vp.width / height), the page in units, K.sc / K.ox / K.oy set, pools emptied
--         page = { height, minWidth, maxWidth, portraitWidth, portraitHeight, portraitAspect }
--   K.R(x, y, w, h) ; K.X(u) ; K.Y(u) ; K.col(c, a) ; K.box(mode, b, rad) ; K.grad(b, rad, top, foot, a)
--   K.gradient(G, x, y, w, h, rad, top, foot, a) (window pixels) ; K.shadow(b, rad, lift, a)
--   K.ring(b, rad, c, a, w) ; K.addHit(b, kind, arg, clip) ; K.hits (this frame's, last on top)
--   K.font(px) ; K.width(s, size) ; K.text(s, x, y, size, c, align, w, a) ; K.label(...) (shadowed)
--   K.fit(s, size, w) ; K.scissor(b | nil) ; K.pulse() ; K.textCache(make) ; K.inside(rect, x, y)
--   K.mix / light / dark / fade ; K.WHITE / BLACK ; K.drawPlate(title, x, y, maxW, accent, body, outline)
--   K.drawLogo(cx, cy, size, accent, a, soft) (window pixels: the W)
--   K.hints(list, box, keyInk, center, wordColor, keyFill) (wordColor nil: white, shadowed)
--   K.toast(state, clock, area, badColor, goodColor) ; K.repeater(start, every) -> fn(input, key, held)

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
  local function font(px)
    px = max(6, floor(px + 0.5))
    local f = fonts[px]
    if not f then
      local ok, made = pcall(G.newFont, px)
      f = ok and made or G.getFont()
      fonts[px] = f
    end
    return f
  end
  K.font = font

  local function X(v) return ox + v * sc end
  local function Y(v) return oy + v * sc end
  K.X, K.Y = X, Y
  local function col(c, a)
    c = c or WHITE
    G.setColor(c[1] / 255, c[2] / 255, c[3] / 255, (a or 1) * (c[4] or 1))
  end
  K.col = col
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
      g.setColor(1, 1, 1, alpha or 1)
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
  -- a soft shadow under b, `lift` units down
  function K.shadow(b, rad, lift, a)
    for i = 1, 3 do
      local s = i * 0.7
      col(BLACK, (a or 0.18) / 3)
      box("fill", R(b[1] - s * 0.6, b[2] - s * 0.4 + lift, b[3] + s * 1.2, b[4] + s * 1.2), (rad or 0) + s)
    end
  end
  local function ring(b, rad, c, a, w)
    col(c, a)
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

  local function width(s, size) return font(size * sc):getWidth(s) / sc end
  K.width = width
  local function text(s, x, y, size, c, align, w, a)
    local f = font(size * sc)
    G.setFont(f)
    col(c, a)
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
    text(s, x, y + 0.5, size, BLACK, align, w, 0.22 * (a or 1))
    return text(s, x, y, size, c, align, w, a)
  end
  -- a font size that fits s in w units (smaller only, never under 3.5)
  function K.fit(s, size, w)
    local tw = width(s, size)
    if w and tw > w and tw > 0 then return max(3.5, size * w / tw * 0.97) end
    return size
  end
  function K.scissor(b)
    if b then G.setScissor(X(b[1]), Y(b[2]), max(0, b[3] * sc), max(0, b[4] * sc)) else G.setScissor() end
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
    nRect, nHitRec = 0, 0
    for i = #hits, 1, -1 do hits[i] = nil end
    local ww = tonumber(vp.width) or (tonumber(vp.gameX) or 0) * 2 + (tonumber(vp.gameWidth) or 240)
    local wh = tonumber(vp.height) or (tonumber(vp.gameY) or 0) * 2 + (tonumber(vp.gameHeight) or 160)
    local ax, ay, aw, ah = 0, 0, ww, wh
    if deps.safeArea then
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

  return K
end
