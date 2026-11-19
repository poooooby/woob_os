-- A market stall's look for the Mart window in shop mode (src/apps/mart.lua, a shop whose kind is "stall":
-- src/shop_themes.lua's, a shop on a town's or city's own outdoor map, as Slateport's market by the sea):
-- open air in place of the Mart's shopfront. Behind it all the sky for the time of day (the sun or the
-- moon, clouds drifting, stars at night), the sea along the horizon (its swell, a glitter under the sun),
-- gulls gliding over it, the beach in front (its foam line coming and going); over the vendor a market
-- tent of pale blue and white as the game's (its roof's stripes, its scalloped valance, its poles, the
-- shade under it), the vendor behind a wooden table with a cloth, the stall's own goods set out on it
-- and a cash box at its end (its lid up when coins land).
-- Numbers only on each frame (src/ui_kit.lua's rules): the colours made once, as the shop opens.
--
--   S = stallView(K, env, shop, now)   shop: the window's model (ctx.shop) ; now() the window's clock
--   S.backdrop(body, clock, band)      the sky, the sea, the beach (band: the shopfront's depth)
--   S.front(x, y, w, band, clock, st, clerk, icon)
--                                      the tent, the vendor (clerk(cx, foot, hU, clock): the window's), the
--                                      table, its goods (icon(id, decor, x, y, size)), the cash box; sets
--                                      st.tillX / tillY (the coins fly there), st.counterX / counterY, st.headY

local floor, max, min, sin, cos, pi = math.floor, math.max, math.min, math.sin, math.cos, math.pi

local function rgb(r, g, b) return { r, g, b } end
-- the time of day's colours: the sky (top, foot), the sea (far, near), the sand (far, near), the light
local DAY = {
  morning = { sky = rgb(255, 196, 168), skyFoot = rgb(196, 222, 255), sea = rgb(96, 168, 226), seaNear = rgb(40, 120, 200),
              sand = rgb(246, 222, 178), sandNear = rgb(232, 200, 150), sun = rgb(255, 214, 150) },
  day = { sky = rgb(86, 160, 250), skyFoot = rgb(186, 226, 255), sea = rgb(56, 156, 230), seaNear = rgb(22, 104, 196),
          sand = rgb(250, 232, 190), sandNear = rgb(236, 206, 156), sun = rgb(255, 246, 200) },
  evening = { sky = rgb(250, 128, 112), skyFoot = rgb(255, 200, 140), sea = rgb(170, 110, 160), seaNear = rgb(80, 70, 150),
              sand = rgb(236, 190, 150), sandNear = rgb(210, 160, 124), sun = rgb(255, 170, 90) },
  night = { sky = rgb(14, 22, 58), skyFoot = rgb(46, 64, 120), sea = rgb(30, 50, 100), seaNear = rgb(14, 26, 66),
            sand = rgb(120, 116, 136), sandNear = rgb(92, 88, 112), sun = rgb(230, 236, 255) },
}
local WHITE, SHADE, INK = rgb(255, 255, 255), rgb(0, 0, 0), rgb(28, 28, 30)
local TENT, TENT_DEEP, TENT_WHITE, POLE = rgb(150, 190, 240), rgb(96, 140, 210), rgb(250, 252, 255), rgb(206, 210, 222)
local WOOD, WOOD_DEEP, WOOD_TOP, PLANK = rgb(196, 140, 88), rgb(136, 88, 50), rgb(226, 182, 128), rgb(110, 70, 40)
local CLOTH, CLOTH_DEEP = rgb(240, 244, 252), rgb(200, 210, 230)
local BOX, BOX_DEEP, COIN, COIN_DEEP = rgb(226, 72, 72), rgb(150, 30, 40), rgb(255, 222, 128), rgb(196, 146, 44)
local BIRD = rgb(250, 252, 255)
local AO_DARK, AO_CLEAR = { 0, 0, 0, 0.18 }, { 0, 0, 0, 0 }
-- (what the scene's dimmed toward in the dark themes)
local DIM_DARK, DIM_OLED = { 14, 18, 36 }, { 0, 0, 4 }

return function(K, env, shop, now)
  local S = {}
  local h = tonumber(os.date("%H")) or 12
  local part = (h >= 5 and h < 10) and "morning" or ((h >= 10 and h < 17) and "day" or ((h >= 17 and h < 20) and "evening" or "night"))
  local C = DAY[part]
  local night = part == "night"
  local seaMid = K.mix and K.mix(C.sea, C.seaNear, 0.5) or C.sea
  -- (the goods set out on the table: the first few of the stall's own)
  local wares = {}
  local tabs = shop and shop.tabs and shop.tabs()
  for _, t in ipairs(tabs or {}) do
    for _, r in ipairs(t.rows or {}) do
      if #wares < 3 then wares[#wares + 1] = r end
    end
  end

  -- ------- behind it all: the sky, the sea, the beach
  function S.backdrop(body, clock, band)
    local G = K.graphics()
    local x, y, w, bh = body[1], body[2], body[3], body[4]
    local horizon = y + band * 0.46
    -- (the shore in the gap between the shopfront and the panels: under their glass it showed as a line)
    local shore = y + band + 0.2
    K.grad(K.R(x, y, w, horizon - y), 0, C.sky, C.skyFoot)
    -- (the sun or the moon, high on the right; stars at night; clouds drifting by day)
    local sx, sy = x + w * 0.66, y + band * 0.2
    K.glow(sx, sy, 16, 12, C.sun, night and 0.25 or 0.45)
    K.col(C.sun)
    G.circle("fill", K.X(sx), K.Y(sy), 3.2 * K.sc, 28)
    if night then
      K.col(C.sky)
      G.circle("fill", K.X(sx + 1.4), K.Y(sy - 0.9), 2.8 * K.sc, 28)
      for i = 0, 13 do
        local px = x + w * ((i * 0.137 + 0.05) % 1)
        local py = y + (horizon - y) * ((i * 0.29 + 0.07) % 0.85)
        K.col(WHITE, 0.35 + 0.35 * sin(clock * 1.6 + i * 1.9))
        G.circle("fill", K.X(px), K.Y(py), 0.32 * K.sc, 6)
      end
    else
      for i = 0, 2 do
        local cx = x + ((i * 0.37 * w + clock * (1.2 + i * 0.5)) % (w + 40)) - 20
        local cy = y + 3.5 + i * 3.2
        K.col(WHITE, 0.55 - i * 0.1)
        G.ellipse("fill", K.X(cx), K.Y(cy), (7 + i * 2) * K.sc, 1.6 * K.sc, 18)
        G.ellipse("fill", K.X(cx + 3), K.Y(cy - 1), 4 * K.sc, 1.5 * K.sc, 14)
      end
    end
    -- (the sea: its swell in rows of light dashes drifting, a glitter under the sun)
    K.grad(K.R(x, horizon, w, shore - horizon), 0, C.sea, C.seaNear)
    K.col(WHITE, 0.55)
    K.box("fill", K.R(x, horizon, w, 0.35))
    for row = 0, 4 do
      local ry = horizon + 1.6 + row * (shore - horizon - 2) / 5
      local len = 2.2 + row * 0.9
      local gap = 9 + row * 3
      local off = (clock * (1.5 + row * 0.7) + row * 13) % gap
      local px = x - gap + off
      while px < x + w do
        K.col(WHITE, 0.16 + row * 0.04)
        K.box("fill", K.R(px, ry, len, 0.35 + row * 0.08))
        px = px + gap
      end
    end
    for i = 0, 5 do
      local gy = horizon + 1 + i * 1.7
      local gx = sx + sin(clock * 2.3 + i * 1.7) * (1.5 + i * 0.8)
      K.col(C.sun, (night and 0.25 or 0.5) * (0.6 + 0.4 * sin(clock * 5 + i * 2.1)))
      K.box("fill", K.R(gx - 1.2 - i * 0.3, gy, 2.4 + i * 0.6, 0.35))
    end
    -- (gulls gliding over the water, wings beating now and then)
    if not night then
      for i = 0, 1 do
        local gx = x + ((clock * (6 + i * 2.5) + i * w * 0.55) % (w + 30)) - 15
        local gy = y + band * (0.24 + i * 0.1) + sin(clock * 0.9 + i * 2) * 1.6
        local flap = 0.6 + 0.4 * sin(clock * (i == 0 and 7 or 6) + i)
        G.setLineWidth(max(1, 0.45 * K.sc))
        K.col(BIRD, 0.9)
        G.line(K.X(gx - 2.2), K.Y(gy - flap), K.X(gx), K.Y(gy), K.X(gx + 2.2), K.Y(gy - flap))
      end
    end
    -- (the beach: the foam's line coming and going, the sand to the foot)
    local swash = sin(clock * 0.8) * 0.4
    K.grad(K.R(x, shore + swash, w, y + bh - shore - swash), 0, C.sand, C.sandNear)
    K.col(seaMid, 0.35)
    K.box("fill", K.R(x, shore + swash, w, 1))
    K.col(WHITE, 0.75)
    local fx = x
    local k = 0
    while fx < x + w do
      local fw = 6 + (k * 7 % 5)
      G.ellipse("fill", K.X(fx + fw / 2), K.Y(shore + swash + 0.2), fw / 2 * K.sc, 0.55 * K.sc, 12)
      fx = fx + fw + 1.5
      k = k + 1
    end
  end

  -- ------- over the vendor: the tent; in front of them, the table
  -- (a stripe of the roof: a slice of the trapezoid between its top and bottom edges)
  local function roofStripe(x0, x1, top, foot, inset, i, n, c)
    local a, b = i / n, (i + 1) / n
    local ta, tb = x0 + inset + (x1 - x0 - inset * 2) * a, x0 + inset + (x1 - x0 - inset * 2) * b
    local fa, fb = x0 + (x1 - x0) * a, x0 + (x1 - x0) * b
    K.col(c)
    K.graphics().polygon("fill", K.X(ta), K.Y(top), K.X(tb), K.Y(top), K.X(fb), K.Y(foot), K.X(fa), K.Y(foot))
  end

  function S.front(x, y, w, band, clock, st, clerk, icon)
    local G = K.graphics()
    local x0, x1 = x - 1.5, x + w + 1.5
    local roofTop, roofFoot = y + 1, y + 9
    local valance = roofFoot + 3.2
    local top = y + band - 8                -- the table's top
    -- (the shade under the tent, the poles)
    K.col(SHADE, 0.16)
    K.box("fill", K.R(x0 + 1, roofFoot, x1 - x0 - 2, top - roofFoot))
    K.grad(K.R(x0 + 1, roofFoot, x1 - x0 - 2, 5), 0, AO_DARK, AO_CLEAR)
    for side = 0, 1 do
      local px = side == 0 and x0 + 1.2 or x1 - 2.2
      K.col(POLE)
      K.box("fill", K.R(px, roofFoot, 1, top - roofFoot + 1), 0.4)
      K.col(WHITE, 0.6)
      K.box("fill", K.R(px + 0.15, roofFoot, 0.3, top - roofFoot))
    end
    -- (the vendor, behind the table)
    local cx = x + 12
    K.glow(cx, top - 10, 14, 12, C.sun, 0.12)
    clerk(cx, top + 3, band - 8, clock)
    -- (the roof: pale blue and white stripes narrowing to the ridge, its edge lit; the valance scalloped)
    local n = 6
    for i = 0, n - 1 do
      roofStripe(x0, x1, roofTop, roofFoot, 5, i, n, i % 2 == 0 and TENT or TENT_WHITE)
    end
    K.col(TENT_DEEP, 0.35)
    G.polygon("fill", K.X(x0 + 5), K.Y(roofTop), K.X(x1 - 5), K.Y(roofTop), K.X(x1 - 4.4), K.Y(roofTop + 1.2),
      K.X(x0 + 4.4), K.Y(roofTop + 1.2))
    K.col(WHITE, 0.75)
    K.box("fill", K.R(x0 + 5, roofTop - 0.3, x1 - x0 - 10, 0.6), 0.3)
    local sw = (x1 - x0) / n
    for i = 0, n - 1 do
      local c = i % 2 == 0 and TENT or TENT_WHITE
      local vx = x0 + i * sw
      K.grad(K.R(vx, roofFoot, sw, valance - roofFoot - 1.4), 0, c, K.dark(c, 0.08))
      K.col(K.dark(c, 0.08))
      G.arc("fill", "pie", K.X(vx + sw / 2), K.Y(valance - 1.4), (sw / 2) * K.sc, 0, pi, 14)
    end
    K.col(TENT_DEEP, 0.5)
    K.box("fill", K.R(x0, roofFoot, x1 - x0, 0.4))
    -- (the stall's sign on the roof: the kind of shop)
    if shop and shop.sub then
      local word = shop.sub
      local fs = K.fit(word, 3.2, x1 - x0 - 14)
      local pw = K.width(word, fs) + 6
      local pb = K.R((x0 + x1 - pw) / 2, roofTop + 2, pw, 5)
      K.shadow(pb, 2.5, 0.5, 0.18)
      K.glass(pb, 2.5, 0.94)
      K.bold(word, pb[1], pb[2] + (pb[4] - fs * 1.2) / 2 + 0.2, fs, TENT_DEEP, "center", pw)
    end
    -- (the table: its top, a cloth over it, its front's planks)
    local tx0, tx1 = x0 + 0.5, x1 - 0.5
    K.shadow(K.R(tx0, top, tx1 - tx0, band - (top - y)), 0.8, 0.8, 0.2)
    K.grad(K.R(tx0, top - 0.6, tx1 - tx0, 2.4), 0.6, WOOD_TOP, WOOD)
    K.grad(K.R(tx0, top + 1.8, tx1 - tx0, y + band - top - 1.8), 0, WOOD, WOOD_DEEP)
    for k = 1, 3 do
      K.col(PLANK, 0.5)
      K.box("fill", K.R(tx0, top + 1.8 + k * (y + band - top - 1.8) / 4, tx1 - tx0, 0.35))
    end
    local cw = (tx1 - tx0) * 0.62
    local clx = tx0 + (tx1 - tx0 - cw) / 2
    K.grad(K.R(clx, top + 1.2, cw, 4.2), 0, CLOTH, CLOTH_DEEP)
    for i = 0, 5 do
      K.col(TENT, 0.85)
      G.arc("fill", "pie", K.X(clx + cw * (i + 0.5) / 6), K.Y(top + 5.4), (cw / 12) * K.sc, 0, pi, 10)
    end
    K.col(TENT, 0.85)
    K.box("fill", K.R(clx, top + 4.4, cw, 1))
    -- (the cash box at the table's end; the goods set out between it and the vendor)
    local bw, bh = 9, 5.4
    local bx, by = tx1 - bw - 1.2, top - bh + 0.8
    for i, r in ipairs(wares) do
      local gx = x + 21 + (i - 1) * 6.6
      if gx + 5.6 < bx - 0.8 then
        K.col(SHADE, 0.18)
        G.ellipse("fill", K.X(gx + 2.8), K.Y(top + 0.9), 2.8 * K.sc, 0.6 * K.sc, 12)
        icon(r.id, r.decor, gx, top - 5.4, 5.6)
      end
    end
    -- (the cash box: its lid up while coins land)
    local c = st.coins
    local age = c and now() - c.t or 9
    local open = (age > 0.35 and age < 1.3) and sin(min(1, (age - 0.35) / 0.95) * pi) or 0
    K.col(SHADE, 0.2)
    G.ellipse("fill", K.X(bx + bw / 2), K.Y(by + bh), bw * 0.6 * K.sc, 0.7 * K.sc, 14)
    K.grad(K.R(bx, by, bw, bh), 0.8, BOX, BOX_DEEP)
    K.col(COIN_DEEP)
    K.box("fill", K.R(bx + bw / 2 - 1.2, by + bh * 0.45, 2.4, 1.2), 0.3)
    local lid = 1.4 + open * 2.2
    K.grad(K.R(bx - 0.3, by - lid, bw + 0.6, 1.6), 0.6, K.light(BOX, 0.15), BOX)
    if open > 0 then
      K.col(COIN)
      K.box("fill", K.R(bx + 1, by - lid + 1.6, bw - 2, lid - 1.4))
    end
    K.col(WHITE, 0.4)
    K.box("fill", K.R(bx + 0.8, by + 0.6, 0.5, bh - 1.4), 0.25)
    st.tillX, st.tillY = bx + bw / 2, by - 1
    st.counterX, st.counterY = cx + 6, top - 3
  end

  -- (the open air -- sky, sea, tent, vendor, goods -- keeps its own colours for the time of day, whatever the
  -- theme; in the dark themes only the beach under the window's panels goes under one layer of night blue
  -- (Dark) or black (OLED), so the dark panels sit on dark)
  if K.themeHold then
    local back, front = S.backdrop, S.front
    function S.backdrop(body, clock, band, ...)
      local th = K.theme()
      K.themeHold(true)
      back(body, clock, band, ...)
      if th ~= "light" then
        local G = K.graphics()
        local d = th == "oled" and DIM_OLED or DIM_DARK
        local top = body[2] + (tonumber(band) or 0)
        G.setColor(d[1] / 255, d[2] / 255, d[3] / 255, (th == "oled" and 0.86 or 0.62) * K.getFade())
        G.rectangle("fill", K.X(body[1]), K.Y(top), body[3] * K.sc, (body[2] + body[4] - top) * K.sc)
      end
      K.themeHold(false)
    end
    function S.front(...)
      K.themeHold(true)
      front(...)
      K.themeHold(false)
    end
  end

  return S
end
