-- The notifications drawer, for the desktop and WoobPad (src/desktop.lua hosts it): frosted glass
-- (the screen blurred under it, src/frost.lua) pulled down from the top of the screen, following the
-- finger, or sliding down from the W menu. The time at its top, "Notifications" and Clear, then a
-- card each, newest first. A card swiped left or right goes (a red Clear shows behind it as it
-- moves); Clear sends them all off one after another; a tap on a card opens its app. Pushed back
-- up by its handle (or anywhere, while the list fits), B, or a tap on the empty glass.
--   buttons  Up / Down a card, A open, Left / Right clear it, SELECT clear all, B / START close
--
--   Nd = Notes(deps)   deps: K ; T ; se(name) ; notify (src/notify.lua) ; frost (src/frost.lua) or nil ;
--                      clock(t) -> the time's text or nil ; glyph(G, kind, cx, cy, size, a)
--   Nd.open() / Nd.close() / Nd.reset() ; Nd.visible() -> drawn at all ; Nd.k() -> how far down (0..1)
--   Nd.pullBegin(screenH) / Nd.pullTo(dy) / Nd.pullEnd(dy) -> true: it opened (a pull from the top, units)
--   Nd.input(input, up, down, left, right) -> nil | "close" | "open", rec
--   Nd.pointer(phase, x, y) (units) -> nil | "close" | "open", rec
--   Nd.wheel(dy) ; Nd.draw(sb, rad, dt, clock) (after the screen's drawing, Fr.finish'ed)

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local CARD_H, GAP, HEAD, FOOT = 24, 3, 40, 12
local OPEN_AT = 20       -- units pulled: it opens (less: back up)
local FLING = 520        -- units a second, a card going
local STAGGER = 0.035    -- Clear: each card this long after the one above it

return function(deps)
  local K, T, Nt = deps.K, deps.T, deps.notify
  local Nd = {}
  local k, want, dragging = 0, 0, false
  local scroll, cursor = 0, 1
  local clearing = nil
  local press = nil
  local keys = false       -- the buttons in use: the chosen card ringed
  local geo = { x = 0, y = 0, w = 1, h = 1, cx = 0, cw = 1, top = 0, bottom = 0, clear = { 0, 0, 0, 0 },
                fits = true, oy = 0, shownTop = 0, shownFoot = 0 }
  local TINT, WHITE, RED = { 14, 16, 24 }, { 255, 255, 255 }, { 255, 69, 58 }
  local SOFT = { 255, 255, 255, 0.62 }

  local function se(name) if deps.se then deps.se(name) end end
  local function list() return Nt and Nt.list() or {} end

  function Nd.visible() return k > 0.001 or want > 0 or dragging end
  function Nd.k() return k end
  function Nd.reset()
    k, want, dragging, press, clearing = 0, 0, false, nil, nil
  end
  local function fresh()
    scroll, cursor, clearing, keys = 0, 1, nil, false
    for _, rec in ipairs(list()) do rec.uiX, rec.uiY, rec.uiFling, rec.uiAt, rec.uiAll = 0, nil, nil, nil, nil end
    if Nt then Nt.seen() end
  end
  function Nd.open()
    if want == 0 and k < 0.05 then fresh() end
    want, dragging = 1, false
  end
  function Nd.close()
    want, dragging, press = 0, false, nil
  end

  -- a pull from the top of the screen: the drawer follows it
  function Nd.pullBegin(screenH)
    if screenH then geo.h = screenH end
    if k < 0.05 then fresh() end
    dragging = true
  end
  function Nd.pullTo(dy) k = max(0, min(1, dy / geo.h)) end
  function Nd.pullEnd(dy)
    dragging = false
    want = (dy >= OPEN_AT or k > 0.35) and 1 or 0
    return want == 1
  end

  -- a card sent off to one side (dir -1 / 1), after `delay` seconds
  local function fling(rec, dir, delay, all)
    if not rec or rec.uiFling then return end
    rec.uiFling, rec.uiAt, rec.uiAll = dir, delay or 0, all
  end
  local function clearAll()
    local l = list()
    if #l == 0 or clearing then return end
    for i, rec in ipairs(l) do fling(rec, 1, (i - 1) * STAGGER, true) end
    clearing = true
    se("SE_SELECT")
  end

  local function keepInView()
    local cy = (cursor - 1) * (CARD_H + GAP)
    local view = geo.bottom - geo.top
    if cy < scroll then scroll = cy end
    if cy + CARD_H > scroll + view then scroll = cy + CARD_H - view end
  end
  local function clampScroll()
    local l = list()
    local content = #l * (CARD_H + GAP) - GAP
    scroll = max(0, min(scroll, max(0, content - (geo.bottom - geo.top))))
  end

  function Nd.input(input, up, down, left, right)
    local l = list()
    local n = #l
    -- (the first press of the D-pad only shows which card is chosen)
    if not keys and (up or down or left or right) then
      keys = true
      se("SE_SELECT")
      return nil
    end
    if up and cursor > 1 then
      cursor = cursor - 1
      keepInView()
      se("SE_SELECT")
    elseif down and cursor < n then
      cursor = cursor + 1
      keepInView()
      se("SE_SELECT")
    elseif (left or right) and l[cursor] then
      fling(l[cursor], left and -1 or 1)
      se("SE_SELECT")
    elseif input:wasPressed("select") then
      clearAll()
    elseif input:wasPressed("a") then
      if l[cursor] then return "open", l[cursor] end
    elseif input:wasPressed("b") or input:wasPressed("start") then
      return "close"
    end
    return nil
  end

  function Nd.wheel(dy)
    scroll = scroll - dy * 10
    clampScroll()
  end

  -- the card under a point (units) -> rec, its index
  local function cardAt(x, y)
    if x < geo.cx or x > geo.cx + geo.cw or y < geo.shownTop or y > geo.shownFoot then return nil end
    for i, rec in ipairs(list()) do
      local cy = geo.top + (rec.uiY or 0) - scroll + geo.oy
      if y >= cy and y < cy + CARD_H and not rec.uiFling then return rec, i end
    end
    return nil
  end

  function Nd.pointer(phase, x, y)
    if phase == "pressed" then
      keys = false
      local rec = cardAt(x, y)
      press = { x = x, y = y, ly = y, rec = rec, axis = nil, handle = y > geo.y + geo.h - FOOT }
      return nil
    end
    local p = press
    if not p then return nil end
    if phase == "moved" then
      local dx, dy = x - p.x, y - p.y
      if not p.axis and (abs(dx) > 3 or abs(dy) > 3) then
        if p.rec and abs(dx) > abs(dy) then
          p.axis = "card"
        elseif not p.handle and not geo.fits and p.y >= geo.top then
          p.axis = "scroll"
        else
          p.axis = "drawer"
          dragging = true
        end
      end
      if p.axis == "card" then
        p.rec.uiX = dx
      elseif p.axis == "scroll" then
        scroll = scroll - (y - p.ly)
        clampScroll()
      elseif p.axis == "drawer" then
        k = max(0, min(1, 1 + min(0, dy) / geo.h))
      end
      p.ly = y
      return nil
    end
    press = nil
    if phase == "cancelled" then
      if p.axis == "drawer" then dragging = false end
      return nil
    end
    -- released
    if p.axis == "card" then
      if abs(x - p.x) > geo.cw * 0.3 then
        fling(p.rec, x > p.x and 1 or -1)
        se("SE_SELECT")
      end
      return nil
    elseif p.axis == "drawer" then
      dragging = false
      if p.y - y > OPEN_AT or k < 0.7 then return "close" end
      want = 1
      return nil
    elseif p.axis == "scroll" then
      return nil
    end
    -- a tap: a card opens, Clear clears, the empty glass closes
    if K.inside(geo.clear, x, y) and #list() > 0 then
      clearAll()
      return nil
    end
    local rec = cardAt(x, y)
    if rec then return "open", rec end
    return "close"
  end

  -- each frame: the drawer toward open or shut, the cards toward their places, the flung ones off
  local function step(dt, clock)
    if not dragging then
      k = k + (want - k) * min(1, dt * 13)
      if abs(want - k) < 0.002 then k = want end
    end
    local l = list()
    local w = geo.cw
    for i = #l, 1, -1 do
      local rec = l[i]
      if rec.uiFling then
        rec.uiAt = (rec.uiAt or 0) - dt
        if rec.uiAt <= 0 then rec.uiX = (rec.uiX or 0) + rec.uiFling * FLING * dt end
        if abs(rec.uiX or 0) > w + 16 then
          Nt.remove(rec)
          if cursor > i then cursor = cursor - 1 end
        end
      elseif not (press and press.rec == rec and press.axis == "card") then
        rec.uiX = (rec.uiX or 0) * max(0, 1 - dt * 16)
      end
    end
    l = list()
    if clearing and #l == 0 then clearing = nil end
    cursor = max(1, min(cursor, #l))
    for i, rec in ipairs(l) do
      local ty = (i - 1) * (CARD_H + GAP)
      rec.uiY = rec.uiY and (rec.uiY + (ty - rec.uiY) * min(1, dt * 14)) or ty
    end
    clampScroll()
  end

  function Nd.draw(sb, rad, dt, clock)
    local G = K.graphics()
    local x, w, h = sb[1], sb[3], sb[4]
    geo.x, geo.y, geo.w, geo.h = x, sb[2], w, h
    step(dt or 0, clock or 0)
    if k <= 0.001 then return end
    local e = k
    local bottom = sb[2] + h * e
    local oy = h * (e - 1)
    geo.oy = oy
    -- the glass: the screen frosted under it, darkened a little, a fine edge at its foot
    local frosted = deps.frost and deps.frost.draw(G, K.X(x), K.Y(sb[2]), w * K.sc, h * e * K.sc, rad * K.sc)
    K.col(TINT, frosted and 0.42 or 0.9)
    K.box("fill", K.R(x, sb[2], w, h * e), rad)
    K.col(WHITE, 0.14)
    K.box("fill", K.R(x, bottom - 0.3, w, 0.3))
    local a = min(1, e * 1.4)
    local sx, sy, sw, sh
    if G.getScissor then sx, sy, sw, sh = G.getScissor() end
    K.scissor(K.R(x, sb[2], w, h * e))
    if sx and G.intersectScissor then G.intersectScissor(sx, sy, sw, sh) end
    -- (the time)
    local ct = deps.clock and deps.clock(clock)
    if ct then K.bold(ct, x, sb[2] + 6 + oy, 15, WHITE, "center", w, a) end
    -- (the heading and Clear)
    local cw = min(w - 16, 170)
    local cx = x + (w - cw) / 2
    geo.cx, geo.cw = cx, cw
    local hy = sb[2] + 27 + oy
    K.bold(T("notes.title"), cx + 1, hy, 6, WHITE, nil, nil, a)
    local l = list()
    local word = T("notes.clear")
    local bw = K.width(word, 4.4) + 8
    local cb = geo.clear
    cb[1], cb[2], cb[3], cb[4] = cx + cw - bw, hy - 0.4, bw, 8
    if #l > 0 then
      K.col(WHITE, 0.18 * a)
      K.box("fill", cb, 4)
      K.text(word, cb[1], cb[2] + 1.6, 4.4, WHITE, "center", cb[3], a)
      K.addHit(cb, "noteClear")
    end
    -- (the cards)
    local top, foot = sb[2] + HEAD + oy, bottom - FOOT
    geo.top, geo.bottom = sb[2] + HEAD, sb[2] + h - FOOT
    geo.shownTop, geo.shownFoot = top, foot
    geo.fits = #l * (CARD_H + GAP) - GAP <= geo.bottom - geo.top
    if #l == 0 then
      if deps.glyph then
        K.col(WHITE, 0.4 * a)
        pcall(deps.glyph, G, "bell", K.X(x + w / 2), K.Y((top + foot) / 2 - 6), 12 * K.sc, 0.45 * a)
      end
      K.text(T("notes.none"), x, (top + foot) / 2 + 2, 5, SOFT, "center", w, a)
    elseif foot > top then
      local ltop = max(top, sb[2])
      K.scissor(K.R(x, ltop, w, foot - ltop))
      if sx and G.intersectScissor then G.intersectScissor(sx, sy, sw, sh) end
      for i, rec in ipairs(l) do
        local cy = top + (rec.uiY or 0) - scroll
        if cy > foot then break end
        if cy + CARD_H >= top then
          local dx = rec.uiX or 0
          local b = K.R(cx + dx, cy, cw, CARD_H)
          -- (swiped: a red Clear in the gap it leaves)
          if abs(dx) > 1 and not rec.uiAll then
            local ra = min(1, abs(dx) / 30) * a
            local gap = min(abs(dx) - 1.5, cw)
            if gap > 0.5 then
              local gx = dx > 0 and cx or cx + cw - gap
              K.col(RED, ra)
              K.box("fill", K.R(gx, cy, gap, CARD_H), min(6, gap / 2))
              if gap > K.width(word, 4.4) + 6 then
                K.bold(word, gx, cy + CARD_H / 2 - 2.6, 4.4, WHITE, "center", gap, ra)
              end
            end
          end
          local ca = a * (rec.uiFling and max(0, 1 - abs(dx) / (cw + 16)) or 1)
          Nt.drawCard(rec, b, ca, Nt.ago(rec), true)
          if keys and i == cursor and not rec.uiFling then K.focusRing(b, 6, 0.8 * a) end
          K.addHit(b, "noteRow", i)
        end
      end
      K.scissor(K.R(x, sb[2], w, h * e))
      if sx and G.intersectScissor then G.intersectScissor(sx, sy, sw, sh) end
    end
    -- (the handle: push it back up)
    K.col(WHITE, 0.5 * a)
    K.box("fill", K.R(x + w / 2 - 11, bottom - 5, 22, 1.6), 0.8)
    if sx then G.setScissor(sx, sy, sw, sh) else G.setScissor() end
  end

  return Nd
end
