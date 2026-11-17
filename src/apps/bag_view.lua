-- The modern menus' Bag, drawn (its state src/apps/bag.lua's, B): the pockets as tabs along the top, a
-- thumb sliding to the one shown; the chosen item's card (its picture, name, how many, words; a TM's move:
-- its type, power, accuracy, PP) beside the pocket's list, over a backdrop in the pocket's colours. The
-- list slides in from the side the pocket turned to; the chosen row glides. Over them: an item's menu by
-- its row, how many to toss, the game's words (the party view's bubble). Narrow: the card above the list.
-- Nothing made while drawing but a wrapped text's lines when the text or the width changes.
--
--   View(K, env, T, A, partyView) -> { draw(body, clock, portrait, B) }

local floor, max, min, sin, abs = math.floor, math.max, math.min, math.sin, math.abs

local M, GAP, TOP_H, TAB_H = 3, 2, 12, 9
local NARROW = 200
local C = {
  ink = { 28, 28, 30 }, soft = { 112, 112, 120 }, white = { 255, 255, 255 }, black = { 0, 0, 0 },
  accent = { 10, 132, 255 }, green = { 52, 199, 89 }, move = { 255, 149, 0 }, reg = { 88, 86, 214 },
}
-- (each pocket's lights)
local POCKET_C = {
  ITEMS = { { 255, 170, 90 }, { 255, 214, 120 } }, KEY_ITEMS = { { 150, 120, 230 }, { 120, 170, 255 } },
  POKE_BALLS = { { 240, 90, 90 }, { 255, 160, 140 } }, TM_CASE = { { 90, 150, 240 }, { 120, 210, 230 } },
  BERRY_POUCH = { { 110, 200, 110 }, { 200, 230, 120 } },
}
local TYPE = {
  [0] = { 168, 168, 120 }, [1] = { 192, 48, 40 }, [2] = { 168, 144, 240 }, [3] = { 160, 64, 160 },
  [4] = { 224, 192, 104 }, [5] = { 184, 160, 56 }, [6] = { 168, 184, 32 }, [7] = { 112, 88, 152 },
  [8] = { 184, 184, 208 }, [9] = { 104, 160, 144 }, [10] = { 240, 128, 48 }, [11] = { 104, 144, 240 },
  [12] = { 120, 200, 80 }, [13] = { 248, 208, 48 }, [14] = { 248, 88, 136 }, [15] = { 152, 216, 216 },
  [16] = { 112, 56, 248 }, [17] = { 112, 88, 72 }, [18] = { 238, 153, 172 },
}
local POCKET_KEY = { ITEMS = "pocket.ITEMS", KEY_ITEMS = "pocket.KEY_ITEMS", POKE_BALLS = "pocket.POKE_BALLS",
                     TM_CASE = "pocket.TM_CASE", BERRY_POUCH = "pocket.BERRY_POUCH" }

return function(K, env, T, A, partyView)
  local V = {}
  local G = nil
  local outCubic, outBack, approach = K.outCubic, K.outBack, K.approach
  local numT = K.textCache(function(n) return tostring(n) end)
  local timesT = K.textCache(function(n) return "×" .. tostring(n) end)
  local mv = { tab = nil, r = 0.9, g = 0.6, b = 0.4, r2 = 0.9, g2 = 0.8, b2 = 0.5, coloured = false, lastT = nil,
               selY = nil, top = 0, menu = nil, menuAt = 0, qtyAt = 0 }
  V.motion = mv

  local wraps = {}
  local function wrap(slot, text, w, size)
    local c = wraps[slot]
    if c and c.text == text and c.w == w and c.size == size then return c.lines end
    local lines, line = {}, ""
    for wd in tostring(text or ""):gmatch("%S+") do
      local try = line == "" and wd or (line .. " " .. wd)
      if line ~= "" and K.width(try, size) > w then
        lines[#lines + 1] = line
        line = wd
      else
        line = try
      end
    end
    if line ~= "" then lines[#lines + 1] = line end
    wraps[slot] = { text = text, w = w, size = size, lines = lines }
    return lines
  end
  local function lineH(size) return K.lineH(size) * 1.25 end

  -- the pockets' tabs: a capsule, a white thumb sliding to the one shown
  local function tabs(B, x, y, w, dt)
    local n = #B.pockets
    if n < 1 then return end
    mv.tab = mv.tab and approach(mv.tab, B.pi, dt, 16) or B.pi
    local tb = K.R(x, y, w, TAB_H)
    local rad = TAB_H / 2
    K.col(C.white, 0.32)
    K.box("fill", tb, rad)
    K.ring(tb, rad, C.white, 0.7, 0.3)
    local sw = (w - 1) / n
    local tx = x + 0.5 + (mv.tab - 1) * sw
    K.col(C.black, 0.1)
    K.box("fill", K.R(tx, y + 0.9, sw, TAB_H - 1), rad - 0.5)
    K.col(C.white)
    K.box("fill", K.R(tx, y + 0.5, sw, TAB_H - 1), rad - 0.5)
    for i = 1, n do
      local p = B.pockets[i]
      local label = T(POCKET_KEY[p] or "pocket.ITEMS")
      local sb = K.R(x + 0.5 + (i - 1) * sw, y + 0.5, sw, TAB_H - 1)
      local fs = K.fit(label, 4.2, sw - 2)
      local ty = sb[2] + (sb[4] - fs * 1.2) / 2
      if abs(mv.tab - i) < 0.5 then K.bold(label, sb[1], ty, fs, K.UI.label, "center", sb[3])
      else K.text(label, sb[1], ty, fs, K.UI.secondary, "center", sb[3]) end
      K.addHit(sb, "win", A.POCKET + i)
    end
  end

  -- the chosen item's card
  local function detail(B, row, x, y, w, h, clock, narrow)
    local b = K.R(x, y, w, h)
    K.glass(b, 6, 0.55)
    if not row then
      local s = T("bag.empty")
      K.text(s, x, y + h / 2 - 3, 4.6, C.soft, "center", w)
      return
    end
    local is = narrow and min(h - 6, 20) or min(w * 0.42, 34)
    local ix, iy = narrow and (x + 4) or (x + (w - is) / 2), y + (narrow and (h - is) / 2 or 6)
    local pop = 0.85 + 0.15 * outBack((clock - (B.moveAt or B.pageAt or 0)) / 0.3)
    K.glow(ix + is / 2, iy + is / 2, is * 0.7, is * 0.6, C.white, 0.35)
    if env.itemIcon then
      local s2 = is * pop
      env.itemIcon(row.id, ix + (is - s2) / 2, iy + (is - s2) / 2, s2, 1)
    end
    K.rescissor()
    local tx, tw, ty
    if narrow then
      tx, tw, ty = ix + is + 4, x + w - ix - is - 8, y + 3
    else
      tx, tw, ty = x + 5, w - 10, iy + is + 3
    end
    local fs = K.fit(row.name, 5.6, tw - (row.qtyText and K.width(row.qtyText, 4.4) + 3 or 0))
    if narrow then K.bold(row.name, tx, ty, fs, C.ink)
    else K.bold(row.name, tx, ty, fs, C.ink, "center", tw) end
    if row.qtyText and narrow then
      K.text(row.qtyText, tx, ty + 0.6, 4.4, C.soft, "right", tw)
    end
    ty = ty + lineH(fs)
    if row.qtyText and not narrow then
      K.text(row.qtyText, tx, ty - 0.5, 4.2, C.soft, "center", tw)
      ty = ty + lineH(4.2)
    end
    if row.registered then
      local s = T("bag.registered")
      local pw = K.width(s, 3.4) + 5
      local px = narrow and tx or (tx + (tw - pw) / 2)
      K.col(C.reg)
      K.box("fill", K.R(px, ty, pw, 5), 2.5)
      K.text(s, px, ty + 0.4, 3.4, C.white, "center", pw)
      ty = ty + 6.5
    end
    local m = row.tm
    if m then
      -- (a TM's move: its type, then power / accuracy / PP)
      local tn = m.typeName or ""
      local pw = K.width(tn, 3.6) + 5
      local px = narrow and tx or (tx + (tw - pw) / 2)
      K.col(TYPE[m.typeId] or C.soft)
      K.box("fill", K.R(px, ty, pw, 5.4), 2.7)
      K.text(tn, px, ty + 0.5, 3.6, C.white, "center", pw)
      ty = ty + 7
      local cw = tw / 3
      for k = 1, 3 do
        local label = k == 1 and T("bag.power") or (k == 2 and T("bag.accuracy") or T("sum.pp"))
        local v = k == 1 and m.powerText or (k == 2 and m.accText or numT(m.maxPp or 0))
        K.text(label, tx + (k - 1) * cw, ty, 3.2, C.soft, "center", cw)
        K.bold(v, tx + (k - 1) * cw, ty + lineH(3.2), 4.4, C.ink, "center", cw)
      end
      ty = ty + lineH(3.2) + lineH(4.4) + 1
    end
    local desc = m and m.desc ~= "" and m.desc or row.desc
    local lines = wrap(narrow and "descN" or "desc", desc, tw, 4)
    local room = y + h - 3 - ty
    local lh = lineH(4)
    for k = 1, #lines do
      if k * lh > room then break end
      K.text(lines[k], tx, ty + (k - 1) * lh, 4, C.ink, narrow and nil or "center", narrow and nil or tw, 0.85)
    end
  end

  -- the pocket's list
  local RH = 9
  local function list(B, rows, x, y, w, h, clock, dt)
    local b = K.R(x, y, w, h)
    K.glass(b, 6, 0.5)
    local rh = RH + (K.textScale() - 1) * 3
    local n = #rows
    local inner = K.R(x + 1, y + 1.5, w - 2, h - 3)
    B.vis, B.h = h - 3, n * rh
    -- (the chosen row kept in sight, unless the list was scrolled by hand)
    if not B.scrolled then
      local want = (B.cur - 1) * rh
      local top = B.top or 0
      if want < top then top = want end
      if want + rh > top + B.vis then top = want + rh - B.vis end
      B.top = max(0, min(top, max(0, B.h - B.vis)))
    end
    mv.top = approach(mv.top, B.top or 0, dt, 18)
    K.scissor(inner)
    local e = outCubic((clock - B.pageAt) / 0.28)
    local slide = (1 - e) * 14 * (B.dir or 0)
    local yy = y + 1.5 - mv.top
    local selY = yy + (B.cur - 1) * rh
    mv.selY = mv.selY and approach(mv.selY, selY, dt, 22) or selY
    if n > 0 and not B.moving then
      K.selection(K.R(x + 2 + slide, mv.selY, w - 4, rh), true, 3)
    end
    for k = 1, n do
      local ry = yy + (k - 1) * rh
      if ry + rh >= y and ry <= y + h then
        local r = rows[k]
        local on = k == B.cur
        local moved = B.moving and on
        local rx = x + 2 + slide + (moved and 2 or 0)
        if moved then
          K.col(C.move, 0.9)
          K.box("fill", K.R(rx, ry, w - 4, rh), 3)
        end
        local ink = (on or moved) and C.white or C.ink
        if env.itemIcon then env.itemIcon(r.id, rx + 1.5, ry + 0.8, rh - 1.6, 1) end
        local qw = r.qtyText and K.width(r.qtyText, 4.2) + 2 or 0
        local nx = rx + rh + 2
        local fs = K.fit(r.name, 4.6, w - (nx - x) - qw - 6)
        K.text(r.name, nx, ry + (rh - fs * 1.2) / 2, fs, ink, nil, nil, e)
        if r.qtyText then K.text(r.qtyText, rx, ry + (rh - 4.2 * 1.2) / 2, 4.2, ink, "right", w - 7, e) end
        if r.registered then
          K.col(on and C.white or C.reg, 0.9)
          G.circle("fill", K.X(nx - 1.2), K.Y(ry + rh / 2), 0.9 * K.sc)
        end
        K.addHit(K.R(x + 1, ry, w - 2, rh), "win", A.ROW + k, inner)
      end
    end
    if n == 0 then K.text(T("bag.empty"), x, y + h / 2 - 3, 4.4, C.soft, "center", w) end
    K.scissor(V.body)
    K.scrollbar(x + w - 1.5, y + 2, h - 4, mv.top, B.vis, max(B.vis, B.h))
    return rh
  end

  -- an item's menu by its row
  local function drawMenu(B, clock, body, rowY, lx)
    local mm = B.menu
    if mm ~= mv.menu then mv.menu, mv.menuAt = mm, clock end
    K.dim(body, 0.14)
    K.addHit(body, "win", A.SCRIM)
    local rows = mm.rows
    local rh, size = 8 + (K.textScale() - 1) * 3, 4.6
    local mw = 38
    for k = 1, #rows do mw = max(mw, K.width(rows[k].text, size) + 12) end
    local mh = #rows * rh + 3
    local mx = max(body[1] + M, lx - mw - 2)
    local my = max(body[2] + TOP_H, min(rowY - mh / 2 + 4, body[2] + body[4] - mh - M))
    local e = outBack((clock - mv.menuAt) / 0.22)
    local fa = outCubic((clock - mv.menuAt) / 0.12)
    G.push()
    local cx, cy = K.X(mx + mw / 2), K.Y(my + mh / 2)
    G.translate(cx, cy)
    G.scale(0.9 + 0.1 * e, 0.9 + 0.1 * e)
    G.translate(-cx, -cy)
    local f0 = K.getFade()
    K.setFade(f0 * fa)
    K.glass(K.R(mx, my, mw, mh), 5, 0.9)
    for k = 1, #rows do
      local rb = K.R(mx + 1.5, my + 1.5 + (k - 1) * rh, mw - 3, rh)
      local on = k == mm.sel
      if on then K.selection(rb, true, 3) end
      K.text(rows[k].text, rb[1] + 4, rb[2] + (rh - size * 1.2) / 2, K.fit(rows[k].text, size, mw - 10), on and C.white or C.ink)
      K.addHit(rb, "win", A.MENU + k)
    end
    K.setFade(f0)
    G.pop()
  end

  -- how many to toss
  local function drawQty(B, clock, body, row)
    local q = B.qty
    K.dim(body, 0.18)
    K.addHit(body, "win", A.SCRIM)
    local sw, sh = min(body[3] - 2 * M, 96), (q.kind == "sell" and 46 or 40) + (K.textScale() - 1) * 6
    local sx, sy = body[1] + (body[3] - sw) / 2, body[2] + (body[4] - sh) / 2
    K.glass(K.R(sx, sy, sw, sh), 6, 0.93)
    local title = T(q.kind == "deposit" and "bag.depositHow" or (q.kind == "sell" and "bag.sellHow" or "bag.tossHow"))
    K.bold(title, sx, sy + 3, K.fit(title, 4.6, sw - 8), C.ink, "center", sw)
    if row then K.text(row.name, sx, sy + 3 + lineH(4.6), K.fit(row.name, 4, sw - 8), C.soft, "center", sw) end
    local cy = sy + sh - (q.kind == "sell" and 24 or 17)
    local bw = 12
    local db = K.R(sx + 6, cy, bw, 9)
    local ub = K.R(sx + sw - 6 - bw, cy, bw, 9)
    K.button(db, "-", "gray", false, 5)
    K.button(ub, "+", "gray", false, 5)
    K.addHit(db, "win", A.QTY_DOWN)
    K.addHit(ub, "win", A.QTY_UP)
    K.bold(timesT(q.n), sx, cy + 1, 6, C.ink, "center", sw)
    -- (selling: what it comes to)
    if q.kind == "sell" and env.amount and B.sellUnit then
      local total = B.sellUnit * q.n
      local aw = env.amount(total, 0, 0, 4, C.ink, true)
      env.amount(total, sx + (sw - aw) / 2, cy + 9.5, 4, C.ink)
    end
    local ob = K.R(sx + sw / 2 - 14, sy + sh - 7, 28, 6)
    K.addHit(ob, "win", A.QTY_OK)
    K.text(T("hint.ok"), ob[1], ob[2] + 0.3, 4, C.accent, "center", ob[3])
  end

  function V.draw(body, clock, portrait, B)
    G = K.graphics()
    V.body = body
    local dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT = clock
    local x, y, w, h = body[1], body[2], body[3], body[4]
    local pocket = B.pockets[B.pi]
    local pc = POCKET_C[pocket] or POCKET_C.ITEMS
    local rate = mv.coloured and 6 or 1000
    mv.coloured = true
    mv.r, mv.g, mv.b = approach(mv.r, pc[1][1] / 255, dt, rate), approach(mv.g, pc[1][2] / 255, dt, rate),
      approach(mv.b, pc[1][3] / 255, dt, rate)
    mv.r2, mv.g2, mv.b2 = approach(mv.r2, pc[2][1] / 255, dt, rate), approach(mv.g2, pc[2][2] / 255, dt, rate),
      approach(mv.b2, pc[2][3] / 255, dt, rate)
    K.backdrop(body, clock, mv.r, mv.g, mv.b, mv.r2, mv.g2, mv.b2)
    K.scissor(body)
    -- (the top: what it's for, and away)
    local loc = B.c.location
    local bw = 0
    -- (the Berry Blender waits for a Berry: no way out)
    if loc ~= "blender" then
      local label = T(loc == "party" and "hint.back" or ((loc == "berry_tree") and "hint.cancel" or "hint.close"))
      bw = K.width(label, 4.2) + 8
      local bb = K.R(x + w - M - bw, y + 2.5, bw, 8)
      K.col(C.white, 0.55)
      K.box("fill", bb, 4)
      K.ring(bb, 4, C.white, 0.8, 0.3)
      K.text(label, bb[1], bb[2] + (8 - 4.2 * 1.2) / 2, 4.2, C.accent, "center", bw)
      K.addHit(bb, "win", A.CANCEL)
    end
    local title = B.title or ""
    local fs = K.fit(title, 6, w - bw - 2 * M - 6)
    K.bold(title, x + M + 1, y + 1 + (TOP_H - fs * 1.2) / 2, fs, C.ink)
    local top = y + TOP_H + 2
    tabs(B, x + M, top, w - 2 * M, dt)
    top = top + TAB_H + GAP + 1
    local ah = y + h - M - top
    local rows = B.rows[pocket] or {}
    local row = rows[B.cur]
    local e = outCubic((clock - B.openAt) / 0.35)
    K.rise(e, 6)
    local listX, rh
    if w < NARROW then
      local dh = min(40, ah * 0.36)
      detail(B, row, x + M, top, w - 2 * M, dh, clock, true)
      listX = x + M
      rh = list(B, rows, x + M, top + dh + GAP, w - 2 * M, ah - dh - GAP, clock, dt)
    else
      local dw = max(70, min(floor(w * 0.38), 120))
      detail(B, row, x + M, top, dw, ah, clock, false)
      listX = x + M + dw + GAP
      rh = list(B, rows, listX, top, w - 2 * M - dw - GAP, ah, clock, dt)
    end
    K.settle(e)
    if B.view == "menu" and B.menu then
      drawMenu(B, clock, body, (mv.selY or top) , listX + 6)
    else
      mv.menu = nil
    end
    if B.view == "qty" and B.qty then drawQty(B, clock, body, row) end
    if B.prompt and partyView then partyView.drawPrompt(B, clock, body) end
    K.scissor(body)
  end

  return V
end
