-- The modern menus' Pokémon screen, drawn (its state src/apps/party.lua's, P): six glass cards over the
-- backdrop lit by the chosen Pokémon's types. Wide, the lead's big card on the left with its picture and
-- the other five down the right; narrow, six rows. Each: its icon (hopping while chosen), name, sex, level,
-- HP bar filling and emptying, its status, the item it holds; while an item's used, whether it can (a TM's
-- able / learned). Over them: the chosen one's menu by its card, the game's words in a bubble along the
-- foot (yes / no beside them), a list to pick from, a level's stats. The summary is the Boxes' view.
-- Nothing made while drawing but a wrapped text's lines when the text or the width changes.
--
--   View(K, env, T, A, sumView) -> { draw(body, clock, portrait, P) }

local floor, max, min, sin, abs = math.floor, math.max, math.min, math.sin, math.abs

local M, GAP, TOP_H = 3, 2, 12
local NARROW = 190
local C = {
  ink = { 28, 28, 30 }, soft = { 112, 112, 120 }, white = { 255, 255, 255 }, black = { 0, 0, 0 },
  accent = { 10, 132, 255 }, green = { 52, 199, 89 }, red = { 255, 59, 48 }, hpGood = { 52, 199, 89 },
  hpMid = { 255, 204, 0 }, hpLow = { 255, 59, 48 }, track = { 118, 118, 128, 0.2 }, statusC = { 150, 150, 160 },
  gold = { 232, 170, 28 }, faint = { 230, 70, 70 }, slate = { 120, 132, 178 }, slate2 = { 150, 120, 190 },
  able = { 52, 168, 83 }, notAble = { 150, 150, 160 },
}
local STATUS_C = { [1] = { 160, 64, 160 }, [2] = { 216, 176, 32 }, [3] = { 140, 140, 150 }, [4] = { 96, 176, 216 },
                   [5] = { 232, 104, 56 }, [7] = { 220, 64, 64 } }
local SHEEN_TOP, SHEEN_FOOT = { 255, 255, 255, 0.45 }, { 255, 255, 255, 0 }
local TYPE = {
  [0] = { 168, 168, 120 }, [1] = { 192, 48, 40 }, [2] = { 168, 144, 240 }, [3] = { 160, 64, 160 },
  [4] = { 224, 192, 104 }, [5] = { 184, 160, 56 }, [6] = { 168, 184, 32 }, [7] = { 112, 88, 152 },
  [8] = { 184, 184, 208 }, [9] = { 104, 160, 144 }, [10] = { 240, 128, 48 }, [11] = { 104, 144, 240 },
  [12] = { 120, 200, 80 }, [13] = { 248, 208, 48 }, [14] = { 248, 88, 136 }, [15] = { 152, 216, 216 },
  [16] = { 112, 56, 248 }, [17] = { 112, 88, 72 }, [18] = { 238, 153, 172 },
}
local STAT_KEYS = { "dex.stat.hp", "dex.stat.atk", "dex.stat.def", "dex.stat.spa", "dex.stat.spd", "dex.stat.spe" }
local STAT_FIELDS = { "maxHp", "atk", "def", "spa", "spd", "spe" }

return function(K, env, T, A, sumView)
  local V = {}
  local G = nil
  local outCubic, outBack, approach = K.outCubic, K.outBack, K.approach
  local hpText = K.textCache(function(k) return tostring(floor(k / 1000)) .. " / " .. tostring(k % 1000) end)
  local plus = K.textCache(function(n) return (n >= 0 and "+" or "") .. tostring(n) end)
  local numT = K.textCache(function(n) return tostring(n) end)
  local countT = K.textCache(function(k) return tostring(floor(k / 100)) .. "/" .. tostring(k % 100) end)
  -- (a team's place, 1 2 3, on its card's corner)
  local function orderBadge(card, x, y)
    if not card.orderN then return end
    local r = 3.4
    K.col(C.accent)
    G.circle("fill", K.X(x + r), K.Y(y + r), r * K.sc)
    K.ring(K.R(x, y, r * 2, r * 2), r, C.white, 0.9, 0.5)
    K.bold(numT(card.orderN), x, y + r - 2.6, 4.2, C.white, "center", r * 2)
  end
  -- the motion's numbers
  local mv = { r = 0.6, g = 0.6, b = 0.6, r2 = 0.6, g2 = 0.6, b2 = 0.6, coloured = false, lastT = nil,
               selX = nil, selY = nil, menuAt = 0, menu = nil, prompt = nil, promptAt = 0 }
  V.motion = mv
  -- each slot's place (units), filled by the layout
  local GX, GY, GW, GH = { 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0 }
  local shownHp = { -1, -1, -1, -1, -1, -1 }
  local shownMon = {}
  local bodyNow = nil

  -- ------- words wrapped to a width (kept per slot until the text, size or width change)
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

  -- a bar filling to k (0..1) of w
  local function bar(x, y, w, h, k, c, a)
    K.col(C.track, a)
    K.box("fill", K.R(x, y, w, h), h / 2)
    k = k < 0 and 0 or (k > 1 and 1 or k)
    if k > 0 then
      K.col(c, a)
      K.box("fill", K.R(x, y, max(h, w * k), h), h / 2)
    end
  end
  local function hpColour(k) return k > 0.5 and C.hpGood or (k > 0.2 and C.hpMid or C.hpLow) end
  -- a small capsule with words in it -> its width
  local function pill(s, x, y, h, size, c, a)
    local pw = K.width(s, size) + 4
    K.col(c, a)
    K.box("fill", K.R(x, y, pw, h), h / 2)
    K.text(s, x, y + (h - size * 1.2) / 2, size, C.white, "center", pw, a)
    return pw
  end
  -- what it holds: the item's picture, or (Ruby / Sapphire have none) a small mark, mail's blue
  local HELD_C, MAIL_C = { 245, 170, 60 }, { 90, 150, 240 }
  local function heldMark(card, x, y, s)
    if env.itemIcon and env.itemIcon(card.item, x, y, s, 0.95) then return end
    K.col(card.mail and MAIL_C or HELD_C)
    G.circle("fill", K.X(x + s / 2), K.Y(y + s / 2), s * 0.3 * K.sc)
    K.ring(K.R(x + s * 0.2, y + s * 0.2, s * 0.6, s * 0.6), s * 0.3, C.white, 0.9, 0.5)
  end
  -- a four-pointed star (a shiny's): two thin diamonds crossed
  local function star(cx, cy, r, c, a)
    K.col(c, a)
    local x, y, rr, q = K.X(cx), K.Y(cy), r * K.sc, r * K.sc * 0.3
    G.polygon("fill", x, y - rr, x + q, y, x, y + rr, x - q, y)
    G.polygon("fill", x - rr, y, x, y - q, x + rr, y, x, y + q)
  end

  -- the HP a card shows: eased towards the Pokémon's own, or along an HP bar's fill
  local function hpOf(P, i, card, clock, dt)
    local mon = card.mon
    local hp = tonumber(mon.hp) or 0
    local a = P.anim
    if a and a.i == i then
      local k = outCubic((clock - a.t0) / max(0.01, a.dur))
      hp = a.from + (a.to - a.from) * k
      shownHp[i] = hp
      return hp
    end
    if shownMon[i] ~= mon or shownHp[i] < 0 then
      shownMon[i], shownHp[i] = mon, hp
    else
      shownHp[i] = approach(shownHp[i], hp, dt, 10)
      if abs(shownHp[i] - hp) < 0.3 then shownHp[i] = hp end
    end
    return shownHp[i]
  end

  -- ------- the layout: each slot's place
  local function layout(P, x, y, w, h)
    local narrow = w < NARROW
    P.narrow = narrow
    if narrow then
      local rh = (h - GAP * 5) / 6
      for i = 1, 6 do
        GX[i], GY[i], GW[i], GH[i] = x, y + (i - 1) * (rh + GAP), w, rh
      end
      return
    end
    local lw = max(78, min(floor(w * 0.36), 132))
    GX[1], GY[1], GW[1], GH[1] = x, y, lw, h
    local rx, rw = x + lw + GAP + 1, w - lw - GAP - 1
    local rh = (h - GAP * 4) / 5
    for i = 2, 6 do
      GX[i], GY[i], GW[i], GH[i] = rx, y + (i - 2) * (rh + GAP), rw, rh
    end
  end

  -- a card's pane: the glass, its type's colour when it's the one chosen, a fainted one's red
  local function pane(b, rad, card, sel, mark)
    local t = card and not card.egg and card.t1 and TYPE[card.t1] or nil
    K.shadow(b, rad, sel and 1.8 or 1.1, sel and 0.12 or 0.07)
    if sel then
      if t then K.col(t, 0.72) else K.col(C.slate, 0.7) end
    else
      K.col(C.white, 0.5)
    end
    K.box("fill", b, rad)
    K.grad(K.R(b[1], b[2], b[3], min(b[4], 16)), rad, SHEEN_TOP, SHEEN_FOOT)
    if card and card.statusId == 7 then
      K.col(C.faint, 0.16)
      K.box("fill", b, rad)
    end
    K.ring(b, rad, C.white, 0.8, 0.35)
    if mark then K.ring(b, rad, mark, 0.95, 0.9) end
  end

  -- the words a card shows under its name: an item's tag while one's used, else its HP
  local function vitals(P, i, card, x, y, w, size, clock, dt, onDark)
    local ink = onDark and C.white or C.ink
    if card.egg then return end
    if card.tag then
      pill(card.tag, x, y - 0.4, size * 1.35, size * 0.9, card.tagOk and C.able or C.notAble)
      return
    end
    local hp = hpOf(P, i, card, clock, dt)
    local k = hp / card.maxHp
    local bx = x
    if card.status then
      bx = bx + pill(card.status, x, y - 0.6, size * 1.3, size * 0.82, STATUS_C[card.statusId] or C.statusC) + 1.5
    end
    local nw = K.width(hpText(card.maxHp * 1000 + card.maxHp), size * 0.9) + 1
    bar(bx, y + size * 0.3, max(6, x + w - bx - nw - 2), size * 0.5, k, hpColour(k))
    K.text(hpText(floor(hp + 0.5) * 1000 + card.maxHp), x + w - nw, y - 0.2, size * 0.9, ink, "right", nw, 0.9)
  end

  -- the lead's big card: the picture, the name, the level, HP
  local function bigCard(P, i, card, x, y, w, h, clock, dt, sel, mark)
    local b = K.R(x, y, w, h)
    pane(b, 6, card, sel, mark)
    local onDark = sel
    local ink = onDark and C.white or C.ink
    local soft = onDark and C.white or C.soft
    local ps = max(20, min(w - 16, h * 0.46))
    local bob = sel and sin(clock * 5) * 0.8 or 0
    local pcx, pcy = x + w / 2, y + 4 + ps / 2 + (card.active and 3 or 0)
    K.glow(pcx, pcy, ps * 0.6, ps * 0.5, C.white, sel and 0.32 or 0.2)
    K.col(C.black, 0.16)
    G.ellipse("fill", K.X(pcx), K.Y(pcy + ps * 0.44), ps * 0.26 * K.sc, ps * 0.055 * K.sc)
    if env.monPic then env.monPic(card.sp, pcx - ps / 2, pcy - ps / 2 + bob, ps, 1, card.mon) end
    K.rescissor()
    if card.active then pill(T("party.inBattle"), x + 3, y + 3, 5.4, 3.3, C.accent) end
    if card.item then heldMark(card, x + w - 11, y + 3, 8) end
    local ty = pcy + ps / 2 + 2 + (K.textScale() - 1) * 2
    local fs = K.fit(card.name, 6, w - 14)
    local nw = K.width(card.name, fs)
    local nx = x + (w - nw) / 2 - (card.gender and 2.5 or 0)
    K.bold(card.name, nx, ty, fs, ink)
    if card.gender and not K.hasSign(card.name) then K.sexMark(card.gender, nx + nw + 1.2, ty + 0.8, 4.6, 1, onDark and C.white or nil) end
    if card.shiny then star(nx - 3.5, ty + 3.2, 2.3 + 0.4 * sin(clock * 5), C.gold) end
    ty = ty + lineH(fs)
    K.text(card.levelText, x, ty, 4.2, soft, "center", w, 0.9)
    ty = ty + lineH(4.2) + 1.5
    vitals(P, i, card, x + 5, ty, w - 10, 4.2, clock, dt, onDark)
    orderBadge(card, x + 2, y + 2)
    K.addHit(b, "win", A.CARD + i)
  end

  -- one of the five (or a row on a narrow screen)
  local function rowCard(P, i, card, x, y, w, h, clock, dt, sel, mark)
    local b = K.R(x, y, w, h)
    pane(b, 5, card, sel, mark)
    local onDark = sel
    local ink = onDark and C.white or C.ink
    local soft = onDark and C.white or C.soft
    local is = min(h + 2, 24)
    local hop = sel and abs(sin(clock * 6)) * 1.6 or 0
    local frame = floor(clock * (sel and 6 or 2.5)) % 2
    if env.monIconOf then env.monIconOf(card.mon, x + 1, y + (h - is) / 2 - hop, is, frame, 1) end
    K.rescissor()
    if card.item then heldMark(card, x + is - 6, y + h - 7.5, 6.5) end
    local tx = x + is + 2
    local right = max(40, min(w * 0.42, 70))
    local nameW = w - (tx - x) - right - 4
    local ns = K.fit(card.name, 5, nameW - 4)
    local ny = y + h / 2 - lineH(ns) * 0.95
    K.bold(card.name, tx, ny, ns, ink)
    local nx = tx + K.width(card.name, ns) + 1
    if card.gender and not K.hasSign(card.name) then K.sexMark(card.gender, nx, ny + 0.7, 4, 1, onDark and C.white or nil) nx = nx + 4.5 end
    if card.shiny then star(nx + 1.8, ny + 2.6, 1.9, C.gold) end
    K.text(card.levelText, tx, ny + lineH(ns), 3.8, soft, nil, nil, 0.9)
    if card.active then pill(T("party.inBattle"), tx + K.width(card.levelText, 3.8) + 2, ny + lineH(ns), 4.8, 3, C.accent) end
    vitals(P, i, card, x + w - right - 3, y + h / 2 - 2.2, right, 3.8, clock, dt, onDark)
    orderBadge(card, x + 2, y + 2)
    K.addHit(b, "win", A.CARD + i)
  end

  -- an empty place: faint glass
  local function emptyCard(i)
    local b = K.R(GX[i], GY[i], GW[i], GH[i])
    K.col(C.white, 0.16)
    K.box("fill", b, i == 1 and 6 or 5)
    K.ring(b, i == 1 and 6 or 5, C.white, 0.35, 0.3)
  end

  -- ------- the top: what the screen's for, and the way out
  local function drawTop(P, x, y, w)
    local title = P.title or ""
    if P.view == "switch" then title = T("party.moveTo")
    elseif P.view == "softboiled" then title = T("party.useOnWhich") end
    local forced = P.base == "battle_faint"
    local bw = 0
    local base = P.base
    local picking = P.view == "switch" or P.view == "softboiled" or base == "use" or base == "give"
      or base == "battleUse" or base == "choose" or base == "choose_multi" or base == "move_tutor"
    if not forced then
      local label = T(picking and "hint.cancel" or (P.c.battle and "hint.back" or "hint.close"))
      bw = K.width(label, 4.2) + 8
      local bb = K.R(x + w - bw, y + 1.5, bw, 8)
      K.col(C.white, 0.55)
      K.box("fill", bb, 4)
      K.ring(bb, 4, C.white, 0.8, 0.3)
      K.text(label, bb[1], bb[2] + (8 - 4.2 * 1.2) / 2, 4.2, C.accent, "center", bw)
      K.addHit(bb, "win", A.CANCEL)
    end
    -- (choosing a team: Confirm, with how many of how many)
    if base == "choose_multi" then
      local label = T("party.confirm")
      local cnt = countT(#P.order * 100 + P.max)
      local cw = K.width(label, 4.2) + K.width(cnt, 3.8) + 12
      local cb = K.R(x + w - bw - cw - 3, y + 1.5, cw, 8)
      local any = #P.order > 0
      K.col(any and C.accent or C.white, any and 0.95 or 0.55)
      K.box("fill", cb, 4)
      if P.confirmFocus then K.ring(cb, 4, C.accent, 0.9, 1) K.focusRing(cb, 4) end
      K.text(label, cb[1] + 4, cb[2] + (8 - 4.2 * 1.2) / 2, 4.2, any and C.white or C.accent)
      K.text(cnt, cb[1], cb[2] + (8 - 3.8 * 1.2) / 2, 3.8, any and C.white or C.soft, "right", cw - 4)
      K.addHit(cb, "win", A.CONFIRM)
      bw = bw + cw + 3
    end
    local fs = K.fit(title, 6, w - bw - 6)
    K.bold(title, x + 1, y + (TOP_H - fs * 1.2) / 2, fs, C.ink)
  end

  -- ------- the chosen one's menu, by its card
  local function drawMenu(P, clock, body)
    local mm = P.menu
    if mm ~= mv.menu then
      mv.menu, mv.menuAt = mm, clock
    end
    local i = mm.i or P.cur
    K.dim(body, 0.14)
    K.addHit(body, "win", A.SCRIM)
    local rows = mm.rows
    local rh, size = 8 + (K.textScale() - 1) * 3, 4.6
    local mw = 40
    for k = 1, #rows do mw = max(mw, K.width(rows[k].text, size) + 12) end
    mw = min(mw, body[3] - 2 * M)
    local mh = #rows * rh + 3
    local mx, my
    if P.narrow then
      mx = body[1] + (body[3] - mw) / 2
      my = GY[i] + GH[i] + 1
      if my + mh > body[2] + body[4] - M then my = GY[i] - mh - 1 end
    elseif i == 1 then
      mx = GX[1] + GW[1] - mw * 0.35
      my = GY[1] + GH[1] * 0.42
    else
      mx = GX[i] - mw - 2
      my = GY[i] + GH[i] / 2 - mh / 2
    end
    my = max(body[2] + TOP_H, min(my, body[2] + body[4] - mh - M))
    mx = max(body[1] + M, min(mx, body[1] + body[3] - mw - M))
    local e = outBack((clock - mv.menuAt) / 0.22)
    local fa = outCubic((clock - mv.menuAt) / 0.12)
    G.push()
    local cx, cy = K.X(mx + mw / 2), K.Y(my + mh / 2)
    G.translate(cx, cy)
    G.scale(0.9 + 0.1 * e, 0.9 + 0.1 * e)
    G.translate(-cx, -cy)
    local fade0 = K.getFade()
    K.setFade(fade0 * fa)
    local b = K.R(mx, my, mw, mh)
    K.glass(b, 5, 0.9)
    for k = 1, #rows do
      local rb = K.R(mx + 1.5, my + 1.5 + (k - 1) * rh, mw - 3, rh)
      local on = k == mm.sel
      if on then K.selection(rb, true, 3) end
      local r = rows[k]
      K.text(r.text, rb[1] + 4, rb[2] + (rh - size * 1.2) / 2, K.fit(r.text, size, mw - 10),
        on and C.white or (r.fm and C.accent or C.ink))
      K.addHit(rb, "win", A.MENU + k)
    end
    K.setFade(fade0)
    G.pop()
  end

  -- ------- the game's words: a bubble along the foot; yes / no beside; a list to pick from; a level's stats
  local function drawPrompt(P, clock, body)
    local p = P.prompt
    if p ~= mv.prompt then
      mv.prompt, mv.promptAt = p, clock
    end
    local e = outCubic((clock - mv.promptAt) / 0.18)
    local x, w = body[1] + M, body[3] - M * 2
    if p.kind == "pick" or p.kind == "stats" then
      K.dim(body, 0.18 * e)
      local size = 4.6
      local rh = 8 + (K.textScale() - 1) * 3
      local n = p.kind == "pick" and #p.names + 1 or 6
      local sw = min(w, 110)
      local title = p.pages[1] or ""
      local tl = title ~= "" and wrap("pickTitle", title, sw - 10, 4.4) or nil
      local th = tl and #tl * lineH(4.4) + 3 or 3
      local sh = th + n * rh + 4
      local sx, sy = body[1] + (body[3] - sw) / 2, body[2] + (body[4] - sh) / 2 + (1 - e) * 6
      local b = K.R(sx, sy, sw, sh)
      K.glass(b, 6, 0.92)
      K.addHit(b, "win", A.MSG)
      if tl then
        for k = 1, #tl do K.bold(tl[k], sx + 5, sy + 3 + (k - 1) * lineH(4.4), 4.4, C.ink) end
      end
      for k = 1, n do
        local rb = K.R(sx + 2, sy + th + 1 + (k - 1) * rh, sw - 4, rh)
        if p.kind == "pick" then
          local last = k == n
          local on = (last and p.sel == n) or k == p.sel
          if on and not last then K.selection(rb, true, 3) end
          local s = last and T("hint.cancel") or p.names[k]
          K.text(s, rb[1] + 4, rb[2] + (rh - size * 1.2) / 2, size, on and not last and C.white or (last and C.accent or C.ink))
          K.addHit(rb, "win", last and A.NO or (A.PICK + k))
        else
          local f = STAT_FIELDS[k]
          K.text(T(STAT_KEYS[k]), rb[1] + 4, rb[2] + (rh - size * 1.2) / 2, size, C.ink)
          local s
          if p.page == 1 then s = plus((p.new[f] or 0) - (p.old[f] or 0)) else s = numT(p.new[f] or 0) end
          K.bold(s, rb[1], rb[2] + (rh - size * 1.2) / 2, size, p.page == 1 and C.green or C.ink, "right", rb[3] - 4)
          if k < n then K.hairline(rb[1] + 3, rb[2] + rh, rb[3] - 6) end
        end
      end
      return
    end
    local size = 5
    local yes = p.kind == "yesno"
    local bwid = yes and 26 or 0
    local text = p.pages[p.page] or ""
    local lines = wrap("msg", text, w - 10 - bwid, size)
    local bh = max(16, #lines * lineH(size) + 7)
    local by = body[2] + body[4] - bh - M + (1 - e) * 6
    local b = K.R(x, by, w, bh)
    K.glass(b, 6, 0.93)
    K.addHit(b, "win", A.MSG)
    -- (typed out as the game's are, quickly: each line uncovered left to right)
    local left = (clock - (p.at or mv.promptAt)) * 90
    for k = 1, #lines do
      local s = lines[k]
      if left <= 0 then break end
      local ly = by + 3.5 + (k - 1) * lineH(size)
      if left < #s then
        local lw = K.width(s, size) * left / #s
        G.intersectScissor(K.X(x + 4), K.Y(ly - 1), (lw + 1) * K.sc, lineH(size) * 1.4 * K.sc)
        K.text(s, x + 5, ly, size, C.ink)
        K.scissor(bodyNow)
      else
        K.text(s, x + 5, ly, size, C.ink)
      end
      left = left - #s
    end
    if yes then
      local yb = K.R(x + w - bwid - 2, by + 2.5, bwid - 1, (bh - 7) / 2)
      local nb = K.R(x + w - bwid - 2, by + 4.5 + (bh - 7) / 2, bwid - 1, (bh - 7) / 2)
      K.button(yb, T("party.yes"), p.yes and "accent" or "gray", false, 4.2)
      K.button(nb, T("party.no"), p.yes and "gray" or "accent", false, 4.2)
      K.addHit(yb, "win", A.YES)
      K.addHit(nb, "win", A.NO)
    else
      local k = 0.5 + 0.5 * sin(clock * 5)
      K.chevron(x + w - 6, by + bh - 4 + k * 0.8, 2.6, C.accent, 2)
    end
  end

  -- (the Bag's prompts are the same bubble: any state with .prompt)
  function V.drawPrompt(S, clock, body)
    G = K.graphics()
    bodyNow = body
    drawPrompt(S, clock, body)
  end

  function V.draw(body, clock, portrait, P)
    G = K.graphics()
    bodyNow = body
    local dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT = clock
    if P.view == "summary" and P.sum and sumView then
      sumView.draw(body, clock, portrait, P.sum)
      if P.prompt then drawPrompt(P, clock, body) end
      return
    end
    local x, y, w, h = body[1], body[2], body[3], body[4]
    -- (the backdrop's lights: the chosen one's types, eased; slate for an egg)
    local card = P.cards[P.cur]
    local t1 = card and not card.egg and card.t1 and TYPE[card.t1] or nil
    local t2 = t1 and (card.t2 and card.t2 ~= card.t1 and TYPE[card.t2] or t1) or C.slate2
    t1 = t1 or C.slate
    local rate = mv.coloured and 6 or 1000
    mv.coloured = true
    mv.r, mv.g, mv.b = approach(mv.r, t1[1] / 255, dt, rate), approach(mv.g, t1[2] / 255, dt, rate),
      approach(mv.b, t1[3] / 255, dt, rate)
    local k2 = t2 == t1 and 0.35 or 0
    mv.r2 = approach(mv.r2, (t2[1] + (255 - t2[1]) * k2) / 255, dt, rate)
    mv.g2 = approach(mv.g2, (t2[2] + (255 - t2[2]) * k2) / 255, dt, rate)
    mv.b2 = approach(mv.b2, (t2[3] + (255 - t2[3]) * k2) / 255, dt, rate)
    K.backdrop(body, clock, mv.r, mv.g, mv.b, mv.r2, mv.g2, mv.b2)
    K.scissor(body)
    drawTop(P, x + M, y + 1, w - M * 2)
    local top = y + TOP_H + 2
    layout(P, x + M, top, w - M * 2, y + h - M - top)
    local picking = P.view == "switch" or P.view == "softboiled"
    for i = 1, 6 do
      local c = P.cards[i]
      -- (the cards settling in one after another as it opens)
      local e = outCubic((clock - P.openAt - (i - 1) * 0.04) / 0.32)
      K.rise(e, 6)
      if c then
        local sel = i == P.cur
        local mark = (picking and i == P.from) and C.green or nil
        if P.narrow or i > 1 then rowCard(P, i, c, GX[i], GY[i], GW[i], GH[i], clock, dt, sel, mark)
        else bigCard(P, i, c, GX[i], GY[i], GW[i], GH[i], clock, dt, sel, mark) end
      else
        emptyCard(i)
      end
      K.settle(e)
    end
    if P.view == "menu" and P.menu then drawMenu(P, clock, body) else mv.menu = nil end
    if P.prompt then drawPrompt(P, clock, body) else mv.prompt = nil end
    K.scissor(bodyNow)
  end

  return V
end
