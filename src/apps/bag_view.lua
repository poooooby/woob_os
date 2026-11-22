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
  BERRY_POUCH = { { 110, 200, 110 }, { 200, 230, 120 } }, PYRAMID = { { 230, 190, 110 }, { 240, 220, 160 } },
}
local TYPE = {
  [0] = { 168, 168, 120 }, [1] = { 192, 48, 40 }, [2] = { 168, 144, 240 }, [3] = { 160, 64, 160 },
  [4] = { 224, 192, 104 }, [5] = { 184, 160, 56 }, [6] = { 168, 184, 32 }, [7] = { 112, 88, 152 },
  [8] = { 184, 184, 208 }, [9] = { 104, 160, 144 }, [10] = { 240, 128, 48 }, [11] = { 104, 144, 240 },
  [12] = { 120, 200, 80 }, [13] = { 248, 208, 48 }, [14] = { 248, 88, 136 }, [15] = { 152, 216, 216 },
  [16] = { 112, 56, 248 }, [17] = { 112, 88, 72 }, [18] = { 238, 153, 172 },
}
local POCKET_KEY = { ITEMS = "pocket.ITEMS", KEY_ITEMS = "pocket.KEY_ITEMS", POKE_BALLS = "pocket.POKE_BALLS",
                     TM_CASE = "pocket.TM_CASE", BERRY_POUCH = "pocket.BERRY_POUCH", PYRAMID = "bag.pyramid" }

return function(K, env, T, A, partyView)
  local V = {}
  local G = nil
  local outCubic, outBack, approach = K.outCubic, K.outBack, K.approach
  local numT = K.textCache(function(n) return tostring(n) end)
  local timesT = K.textCache(function(n) return "×" .. tostring(n) end)
  local drawSell
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

  -- an item's picture, or (Ruby / Sapphire have none) one of ours: a Ball, a TM's disc in its move's
  -- type, a Berry, else a tile with its initial
  local INITIAL = K.textCache(function(name) return tostring(name):match("[%w]") or "?" end)
  local BERRY_C, LEAF_C, TILE_C, BALL_C = { 120, 90, 200 }, { 80, 170, 80 }, { 140, 150, 170 }, { 230, 60, 60 }
  local function itemArt(r, pocket, x, y, s, a)
    if env.itemIcon and env.itemIcon(r.id, x, y, s, a) then return end
    local cx, cy, rr = K.X(x + s / 2), K.Y(y + s / 2), s * 0.38 * K.sc
    a = a or 1
    if pocket == "POKE_BALLS" then
      K.col(C.white, a)
      G.circle("fill", cx, cy, rr)
      K.col(BALL_C, a)
      G.arc("fill", cx, cy, rr, math.pi, 2 * math.pi)
      K.col(C.black, 0.8 * a)
      G.setLineWidth(math.max(1, rr * 0.16))
      G.line(cx - rr, cy, cx + rr, cy)
      G.circle("line", cx, cy, rr)
      K.col(C.white, a)
      G.circle("fill", cx, cy, rr * 0.28)
      K.col(C.black, 0.8 * a)
      G.circle("line", cx, cy, rr * 0.28)
    elseif r.tm then
      K.col(TYPE[r.tm.typeId] or TILE_C, a)
      G.circle("fill", cx, cy, rr)
      K.col(C.white, 0.55 * a)
      G.circle("fill", cx - rr * 0.3, cy - rr * 0.3, rr * 0.35)
      K.col(C.white, a)
      G.circle("fill", cx, cy, rr * 0.22)
    elseif pocket == "BERRY_POUCH" then
      K.col(BERRY_C, a)
      G.circle("fill", cx, cy + rr * 0.1, rr * 0.9)
      K.col(LEAF_C, a)
      G.ellipse("fill", cx + rr * 0.3, cy - rr * 0.8, rr * 0.45, rr * 0.22)
    else
      local b = K.R(x + s * 0.12, y + s * 0.12, s * 0.76, s * 0.76)
      K.col(TILE_C, a)
      K.box("fill", b, s * 0.18)
      K.bold(INITIAL(r.name), b[1], b[2] + (b[4] - s * 0.5 * 1.2) / 2, s * 0.5, C.white, "center", b[3], a)
    end
  end

  -- a Ball's chance to catch (a wild battle): a capsule, red for a long shot, amber, then green
  local CHANCE_LOW, CHANCE_MID, CHANCE_HIGH = { 255, 69, 58 }, { 255, 149, 0 }, { 52, 199, 89 }
  local function chanceColour(p) return p < 25 and CHANCE_LOW or (p < 60 and CHANCE_MID or CHANCE_HIGH) end
  -- (right-aligned at rx; its width back)
  local function chanceChip(r, rx, cy, size, a)
    local s = r.chanceText
    local th = K.lineH(size) * 1.2
    local cw = K.width(s, size) + K.lineH(size) * 1.2
    local ch = th + K.lineH(size) * 0.3
    local b = K.R(rx - cw, cy - ch / 2, cw, ch)
    K.col(chanceColour(r.chance), 0.92 * (a or 1))
    K.box("fill", b, ch / 2)
    -- (placed by its 1x size: the kit's text lifts a bigger one round the same middle)
    K.bold(s, b[1], b[2] + (ch - size * 1.2) / 2, size, C.white, "center", cw, a)
    return cw
  end
  V.chanceChip = chanceChip

  -- the pockets' tabs: a capsule, a white thumb sliding to the one shown
  -- (on the Kanto Gear's small screen, B.compact: each pocket's picture in place of its name, taller)
  local TAB_PIC = 13
  local function tabs(B, x, y, w, dt)
    local n = #B.pockets
    if n < 1 then return end
    local th = B.compact and TAB_PIC or TAB_H
    mv.tab = mv.tab and approach(mv.tab, B.pi, dt, 16) or B.pi
    local tb = K.R(x, y, w, th)
    local rad = th / 2
    K.col(C.white, 0.32)
    K.box("fill", tb, rad)
    K.ring(tb, rad, C.white, 0.7, 0.3)
    local sw = (w - 1) / n
    local tx = x + 0.5 + (mv.tab - 1) * sw
    K.col(C.black, 0.1)
    K.box("fill", K.R(tx, y + 0.9, sw, th - 1), rad - 0.5)
    K.col(C.white)
    K.box("fill", K.R(tx, y + 0.5, sw, th - 1), rad - 0.5)
    for i = 1, n do
      local p = B.pockets[i]
      local sb = K.R(x + 0.5 + (i - 1) * sw, y + 0.5, sw, th - 1)
      local on = abs(mv.tab - i) < 0.5
      if B.compact and env.typeArt then
        local pc = POCKET_C[p] or POCKET_C.ITEMS
        env.typeArt.pocket(p, sb[1] + sb[3] / 2, sb[2] + sb[4] / 2, sb[4] * 0.78, 0, on and pc[1] or K.UI.secondary, on and 1 or 0.7)
      else
        local label = T(POCKET_KEY[p] or "pocket.ITEMS")
        local fs = K.fit(label, 4.2, sw - 2)
        local ty = sb[2] + (sb[4] - fs * 1.2) / 2
        if on then K.bold(label, sb[1], ty, fs, K.UI.label, "center", sb[3])
        else K.text(label, sb[1], ty, fs, K.UI.secondary, "center", sb[3]) end
      end
      K.addHit(sb, "win", A.POCKET + i)
    end
    return th
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
    -- (the pocket's own picture as a garnish: large in the card's bottom corner, peeking in from past its
    -- edges, turning slowly, in the pocket's colour -- as the summary's and the Pokédex's cards do)
    local Art = env.typeArt
    if Art then
      local pc = POCKET_C[B.pockets[B.pi]] or POCKET_C.ITEMS
      local ms = narrow and h * 1.5 or min(w, h) * 0.95
      G.intersectScissor(K.X(x), K.Y(y), w * K.sc, h * K.sc)
      Art.pocket(B.pockets[B.pi], x + w - ms * 0.22, y + h - ms * 0.2, ms, -0.5 + 0.12 * math.sin(clock * 0.4), pc[1], 0.3)
      K.scissor(V.body)
    end
    K.glow(ix + is / 2, iy + is / 2, is * 0.7, is * 0.6, C.white, 0.35)
    local s2 = is * pop
    itemArt(row, B.pockets[B.pi], ix + (is - s2) / 2, iy + (is - s2) / 2, s2, 1)
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
    if row.chanceText then
      -- (a Ball in a wild battle: its chance to catch)
      local s = T("bag.catch")
      local sw = K.width(s, 3.8)
      local chipW = K.width(row.chanceText, 4.4) + K.lineH(4.4) * 1.2
      local chH = K.lineH(4.4) * 1.5
      local px = narrow and tx or (tx + (tw - sw - 2 - chipW) / 2)
      K.text(s, px, ty + (chH - 3.8 * 1.2) / 2, 3.8, C.soft)
      chanceChip(row, px + sw + 2 + chipW, ty + chH / 2, 4.4)
      ty = ty + chH + 1.5
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

  -- (the Kanto Gear's strip: as tall as the chosen item's card needs -- its name, the catch chance, a TM's
  -- move, every line of its words -- as detail() lays them out narrow)
  local function stripNeed(B, row, w)
    if not row then return 24 end
    local is = 20
    local tw = w - is - 12
    local need = 3 + lineH(5.6)
    if row.registered then need = need + 6.5 end
    if row.chanceText then need = need + K.lineH(4.4) * 1.5 + 1.5 end
    local m = row.tm
    if m then need = need + 7 + lineH(3.2) + lineH(4.4) + 1 end
    local desc = m and m.desc ~= "" and m.desc or row.desc
    need = need + #wrap("descN", desc, tw, 4) * lineH(4) + 4.5
    return max(is + 6, need)
  end

  -- the pocket's list
  local RH = 9
  local function list(B, rows, x, y, w, h, clock, dt)
    local b = K.R(x, y, w, h)
    K.glass(b, 6, 0.5)
    local rh = B.compact and 15 or (RH + (K.textScale() - 1) * 3)
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
      -- (the chosen row as the summary's move to forget: a pale fill, an accent edge)
      local hb = K.R(x + 2 + slide, mv.selY, w - 4, rh)
      K.col(C.accent, 0.14)
      K.box("fill", hb, 3)
      K.ring(hb, 3, C.accent, 0.9, 0.6)
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
        local ink = moved and C.white or C.ink
        local isz = min(rh - 1.6, 11)
        itemArt(r, B.pockets[B.pi], rx + 1.5 + (rh - 1.6 - isz) / 2, ry + (rh - isz) / 2, isz, 1)
        local qw = r.qtyText and K.width(r.qtyText, 4.2) + 2 or 0
        -- (a Ball's catch chance, left of how many)
        local cwid = 0
        if r.chanceText then
          cwid = chanceChip(r, x + w - 5 - qw - 1.5, ry + rh / 2, 3.6, e) + 2.5
        end
        local nx = rx + rh + 2
        local fs = K.fit(r.name, 4.6, w - (nx - x) - qw - cwid - 6)
        K.text(r.name, nx, ry + (rh - fs * 1.2) / 2, fs, ink, nil, nil, e)
        if r.qtyText then K.text(r.qtyText, rx, ry + (rh - 4.2 * 1.2) / 2, 4.2, ink, "right", w - 7, e) end
        if r.registered then
          K.col(moved and C.white or C.reg, 0.9)
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
    local rh, size = B.compact and 14 or (8 + (K.textScale() - 1) * 3), 4.6
    local mw = 38
    for k = 1, #rows do mw = max(mw, K.width(rows[k].text, size) + 12) end
    local mh = #rows * rh + 3
    local mx = max(body[1] + M, lx - mw - 2)
    local my = max(body[2] + TOP_H, min(rowY - mh / 2 + 4, body[2] + body[4] - mh - M))
    if mm.sort then
      -- (START's: from the Sort button, else the top's right)
      mx = max(body[1] + M, (mv.sortR or (body[1] + body[3] - M)) - mw)
      my = (mv.sortB or (body[2] + TOP_H)) + 1.5
    end
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

  -- selling: a card of its own -- the item, the shop's words, the price each, how many, the total, the money
  -- before and after, Cancel / Sell
  local SELL_BAND = { 52, 199, 89 }
  local function money(n, x, y, size, c, align, w)
    if not env.amount then return end
    local aw = env.amount(n, 0, 0, size, c, true)
    local ax = align == "right" and (x + w - aw) or (align == "center" and (x + (w - aw) / 2) or x)
    env.amount(n, ax, y, size, c)
    return aw
  end
  function drawSell(B, clock, body)
    local p = B.prompt
    local d = p.sell
    if p ~= mv.sellP then mv.sellP, mv.sellAt = p, clock end
    local e = outBack((clock - mv.sellAt) / 0.28)
    K.dim(body, 0.28 * math.min(1, e))
    local ts = K.textScale() - 1
    local sw = min(body[3] - 2 * M, 150 + ts * 30)
    local hh = 24 + ts * 5
    local lines = wrap("sellWords", p.pages[1] or "", sw - 10, 3.8)
    local nl = min(2, #lines)
    local bh, gap = 9 + ts * 2, 3
    -- (as tall as what's on it)
    local sh = hh + 3 + nl * lineH(3.8) + 2 + lineH(4.2) * 2 + 3 + lineH(6) + 1 + lineH(3.8) + 5 + bh + 4
    local sx, sy = body[1] + (body[3] - sw) / 2, body[2] + (body[4] - sh) / 2 + (1 - e) * 8
    local b = K.R(sx, sy, sw, sh)
    K.glass(b, 7, 0.96)
    -- (its head: the pocket's colour, the item's picture and name, how many)
    local pocket = B.pockets[B.pi]
    local pc = POCKET_C[pocket] or POCKET_C.ITEMS
    K.grad(K.R(sx, sy, sw, hh), 7, pc[1], pc[2])
    if env.typeArt then
      -- (inside the head only, peeking up from its foot, clear of its rounded corner)
      G.intersectScissor(K.X(sx), K.Y(sy), sw * K.sc, hh * K.sc)
      env.typeArt.pocket(pocket, sx + sw - hh * 0.75, sy + hh * 0.95, hh * 1.3, -0.5 + 0.12 * math.sin(clock * 0.4), C.white, 0.25)
      K.scissor(V.body)
    end
    itemArt(d.row, pocket, sx + 4, sy + 3, hh - 6, 1)
    K.rescissor()
    local nx = sx + hh + 2
    local ns = K.fit(d.row.name, 5.6, sw - (nx - sx) - 30)
    K.bold(d.row.name, nx, sy + 3, ns, C.white)
    K.text(timesT(d.qty), nx, sy + 3 + lineH(ns), 4.4, C.white, nil, nil, 0.9)
    -- (the shop's words)
    local yy = sy + hh + 3
    for k = 1, nl do
      K.text(lines[k], sx + 5, yy + (k - 1) * lineH(3.8), 3.8, C.soft)
    end
    yy = yy + nl * lineH(3.8) + 2
    -- (the sums)
    local lx, rw = sx + 6, sw - 12
    local rs = 4.2
    K.text(T("bag.sell.each"), lx, yy, rs, C.ink)
    money(d.unit, lx, yy, rs, C.ink, "right", rw)
    yy = yy + lineH(rs) + 0.5
    K.text(T("bag.sell.qty"), lx, yy, rs, C.ink)
    K.text(timesT(d.qty), lx, yy, rs, C.ink, "right", rw)
    yy = yy + lineH(rs) + 1
    K.hairline(lx, yy, rw)
    yy = yy + 1.5
    K.bold(T("bag.sell.total"), lx, yy + 0.6, 4.6, C.ink)
    money(d.earn, lx, yy, 6, SELL_BAND, "right", rw)
    yy = yy + lineH(6) + 1
    -- (the money now, and after)
    K.text(T("bag.sell.money"), lx, yy, 3.8, C.soft)
    local aw = env.amount and env.amount(d.money + d.earn, 0, 0, 3.8, C.ink, true) or 0
    money(d.money + d.earn, lx, yy, 3.8, C.ink, "right", rw)
    local arx = lx + rw - aw - 5
    K.chevron(arx + 2, yy + 2.3, 2.2, C.soft, 1)
    money(d.money, lx, yy, 3.8, C.soft, "right", rw - aw - 7)
    -- (Cancel / Sell)
    local bw = (sw - 10 - gap) / 2
    local by = sy + sh - bh - 4
    local nb = K.R(sx + 5, by, bw, bh)
    local yb = K.R(sx + 5 + bw + gap, by, bw, bh)
    K.button(nb, T("hint.cancel"), "gray", not p.yes, 4.6)
    K.button(yb, T("bag.sell.confirm"), "accent", p.yes, 4.6)
    K.addHit(nb, "win", A.NO)
    K.addHit(yb, "win", A.YES)
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
    -- (the pocket's pictures drifting behind the glass)
    if env.typeArt then
      env.typeArt.scatter("pocket", pocket, body, clock, C.white, 0.3)
      K.scissor(body)
    end
    K.scissor(body)
    -- (the top: what it's for, and away)
    local loc = B.c.location
    local bw = 0
    -- (the Berry Blender waits for a Berry: no way out; a lesson's: Skip, as its B -- none for the Old Man's)
    local lesson = B.pd ~= nil or B.m.demo or B.m.tmDemo
    if loc ~= "blender" and not (B.pd and B.pd.plan.noInterrupt) then
      local label = T(lesson and "hint.skip" or (loc == "party" and "hint.back"
        or ((loc == "berry_tree") and "hint.cancel" or "hint.close")))
      bw = K.width(label, 4.2) + 8
      local bb = K.R(x + w - M - bw, y + 2.5, bw, 8)
      K.col(C.white, 0.55)
      K.box("fill", bb, 4)
      K.ring(bb, 4, C.white, 0.8, 0.3)
      K.text(label, bb[1], bb[2] + (8 - 4.2 * 1.2) / 2, 4.2, C.accent, "center", bw)
      K.addHit(bb, "win", A.CANCEL)
    end
    -- (Sort, beside it: a pocket START sorts; never on the Kanto Gear's screen, a battle's; kept while its
    -- menu drops from it)
    mv.sortR = nil
    local sortRows = B.rows[pocket]
    local sorting = B.view == "menu" and B.menu and B.menu.sort
    if not B.compact and not B.prompt and sortRows and sortRows.sortable and (B.view == "list" or sorting) then
      local label = T("items.sort")
      local sw2 = K.width(label, 4.2) + 8
      local sb = K.R(x + w - M - bw - 2 - sw2, y + 2.5, sw2, 8)
      K.col(C.white, sorting and 0.85 or 0.55)
      K.box("fill", sb, 4)
      K.ring(sb, 4, C.white, 0.8, 0.3)
      K.text(label, sb[1], sb[2] + (8 - 4.2 * 1.2) / 2, 4.2, C.accent, "center", sw2)
      K.addHit(sb, "win", A.SORT)
      mv.sortR, mv.sortB = sb[1] + sb[3], sb[2] + sb[4]
      bw = bw + sw2 + 2
    end
    -- (the Kanto Gear's screen: the pocket's name as the title, its tabs pictures)
    local title = B.compact and T(POCKET_KEY[pocket] or "pocket.ITEMS") or (B.title or "")
    local fs = K.fit(title, 6, w - bw - 2 * M - 6)
    K.bold(title, x + M + 1, y + 1 + (TOP_H - fs * 1.2) / 2, fs, C.ink)
    local top = y + TOP_H + 2
    local th = tabs(B, x + M, top, w - 2 * M, dt) or TAB_H
    top = top + th + GAP + 1
    local ah = y + h - M - top
    local rows = B.rows[pocket] or {}
    local row = rows[B.cur]
    local e = outCubic((clock - B.openAt) / 0.35)
    K.rise(e, 6)
    local listX, rh
    if w < NARROW then
      -- (the Gear's: grown to fit the item's card, two rows of the list kept below it)
      local dh = B.compact and min(stripNeed(B, row, w - 2 * M), ah - 2 * 15 - GAP - 3) or min(40, ah * 0.36)
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
    if B.prompt and B.prompt.sell then drawSell(B, clock, body)
    elseif B.prompt and partyView then partyView.drawPrompt(B, clock, body) end
    -- (what a sort did: a capsule at the foot, a moment)
    local tt = B.toast
    if tt then
      local age = clock - tt.at
      if age > 1.8 or age < 0 then
        B.toast = nil
      else
        local a = min(1, age / 0.15, (1.8 - age) / 0.3)
        local ts = 4.4
        local tw = K.width(tt.text, ts) + 12
        local th = K.lineH(ts) * 1.2 + 4
        local tb = K.R(x + (w - tw) / 2, y + h - M - th - 2 + (1 - outCubic(min(1, age / 0.25))) * 4, tw, th)
        local f0 = K.getFade()
        K.setFade(f0 * a)
        K.glass(tb, th / 2, 0.92)
        K.text(tt.text, tb[1], tb[2] + (th - ts * 1.2) / 2, ts, C.ink, "center", tw)
        K.setFade(f0)
      end
    end
    K.scissor(body)
  end

  return V
end
