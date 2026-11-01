-- The Mail app: the PC's mailbox as an inbox. Two folders: Inbox (the PC's mail: read it, move it
-- to the Bag (the message is lost, as in the game), give it to a Pokémon) and Held (mail the
-- party is holding: take it into the Inbox). Landscape: the list | the open mail; portrait: the
-- list, A opens the mail over it.
--   buttons  Up / Down the mail, L / R the folder, A open / act, Left / Right the actions, B back
--            (from the list: close)
--   touch    tap a folder, a mail, an action, a Pokémon; drag (or the wheel) scrolls the list
-- The model is src/mailbox.lua (env.mb); rows are made again only after a change.
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min = math.floor, math.max, math.min

local C = {
  ink = { 30, 32, 44 }, soft = { 104, 108, 128 }, faint = { 150, 154, 170 }, accent = { 64, 132, 246 },
  pane = { 255, 255, 255 }, head = { 238, 240, 245 }, chip = { 214, 220, 232 }, bad = { 220, 62, 74 },
  good = { 120, 230, 160 }, wash = { 64, 132, 246, 0.12 }, dim = { 0, 0, 0 }, paper = { 252, 251, 247 },
}
-- the stationery's tints, by design (item - ORANGE MAIL): Orange, Harbor, Glitter, Mech, Wood, Wave,
-- Bead, Shadow, Tropic, Dream, Fab, Retro
local TINT = {
  [0] = { 244, 140, 60 }, { 70, 130, 200 }, { 222, 178, 40 }, { 120, 130, 146 }, { 160, 112, 70 },
  { 48, 170, 186 }, { 232, 110, 160 }, { 96, 76, 140 }, { 70, 170, 90 }, { 168, 140, 222 },
  { 214, 80, 190 }, { 214, 84, 64 },
}
local ROW_H, SEG_H, ACT_H = 15, 10, 11
local SEG_INBOX, SEG_HELD, ACTION, YES, NO, MON, BACK, DIM = 2001, 2002, 2010, 2020, 2021, 2030, 2040, 2050

-- (the words are keys of lang/*.lua, through env.T)
local ACTIONS = { inbox = { "mail.toBag", "mail.give" }, held = { "mail.take" } }
local HINTS = {
  list = { { "A", "hint.open" }, { "L R", "hint.folder" }, { "B", "hint.close" } },
  reader = { { "< >", "hint.choose" }, { "A", "hint.ok" }, { "B", "hint.back" } },
  sheet = { { "A", "hint.ok" }, { "B", "hint.cancel" } },
}
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env)
  local K, mb, T = env.K, env.mb, env.T or NO_T
  local W = { title = "Mail" }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local st = {
    folder = "inbox", inbox = {}, held = {}, cursor = 1, top = 0, focus = "list", action = 1,
    reading = false, sheet = nil, yes = true, party = {}, partyCursor = 1, toast = nil, visible = 5,
    portrait = false, segInbox = "Inbox", segHeld = "Held",
  }
  W.state = st

  local function rows() return st[st.folder] end
  local function clamp()
    local n = #rows()
    st.cursor = max(1, min(st.cursor, n))
    if st.cursor > st.top + st.visible then st.top = st.cursor - st.visible end
    if st.cursor <= st.top then st.top = st.cursor - 1 end
    st.top = max(0, min(st.top, max(0, n - st.visible)))
    if n == 0 then st.focus, st.reading = "list", false end
  end
  local function refresh()
    local s = session()
    st.inbox, st.held = mb.inbox(s), mb.held(s)
    st.segInbox = T("mail.inbox") .. "  " .. #st.inbox
    st.segHeld = T("mail.held") .. "  " .. #st.held
    clamp()
  end
  W.refresh = refresh

  local function toast(text, bad)
    st.toast = { text = text, bad = bad, t = now() }
    se(bad and "SE_FAILURE" or "SE_SELECT")
  end
  local function setFolder(f)
    if st.folder == f then return end
    st.folder, st.cursor, st.top, st.focus, st.reading, st.action = f, 1, 0, "list", false, 1
    clamp()
    se("SE_SELECT")
  end
  local function open()
    if not rows()[st.cursor] then return end
    st.focus, st.action = "reader", 1
    if st.portrait then st.reading = true end
    se("SE_SELECT")
  end
  local function back()
    st.focus, st.reading = "list", false
    se("SE_SELECT")
  end

  local function doAction(i)
    local row = rows()[st.cursor]
    if not row then return end
    local s = session()
    if st.folder == "held" then
      local ok, why = mb.take(s, row)
      refresh()
      if ok then toast(T("mail.filed")) else toast(T(why and ("reason.mail." .. why) or "failed"), true) end
      return
    end
    if i == 1 then
      st.sheet, st.yes = "bag", false
      se("SE_SELECT")
    else
      st.party = mb.party(s)
      if #st.party == 0 then return toast(T("mail.noParty"), true) end
      st.partyCursor = 1
      for k, p in ipairs(st.party) do
        if not p.held then
          st.partyCursor = k
          break
        end
      end
      st.sheet = "give"
      se("SE_SELECT")
    end
  end
  local function answer(yes)
    local row = rows()[st.cursor]
    local s = session()
    if st.sheet == "bag" then
      st.sheet = nil
      if not yes then return se("SE_SELECT") end
      local ok, why = mb.toBag(s, row)
      refresh()
      back()
      if ok then
        toast(T.f("mail.movedToBag", row.title))
      else
        toast(T(why and ("reason.mail." .. why) or "failed"), true)
      end
    elseif st.sheet == "give" then
      if not yes then
        st.sheet = nil
        return se("SE_SELECT")
      end
      local p = st.party[st.partyCursor]
      if not p then return end
      if p.held then return toast(T("reason.mail.holding"), true) end
      st.sheet = nil
      local ok, why = mb.give(s, row, p.mon)
      refresh()
      back()
      if ok then
        toast(T.f("mail.given", p.name))
      else
        toast(T(why and ("reason.mail." .. why) or "failed"), true)
      end
    end
  end

  -- ------- buttons

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  function W.input(input, nav)
    cur = input
    if st.sheet == "bag" then
      if nav.left or nav.right then
        st.yes = not st.yes
        se("SE_SELECT")
      elseif pressed("a") then answer(st.yes)
      elseif pressed("b") then answer(false)
      end
      return true
    end
    if st.sheet == "give" then
      local n = #st.party
      local d = (nav.left and -1) or (nav.right and 1) or (nav.up and -2) or (nav.down and 2) or 0
      if d ~= 0 then
        local c = st.partyCursor + d
        if c >= 1 and c <= n then
          st.partyCursor = c
          se("SE_SELECT")
        end
      elseif pressed("a") then answer(true)
      elseif pressed("b") then answer(false)
      end
      return true
    end
    if pressed("l") then
      setFolder("inbox")
      return true
    end
    if pressed("r") then
      setFolder("held")
      return true
    end
    if st.focus == "reader" then
      local acts = ACTIONS[st.folder]
      if nav.left or nav.right then
        local a = max(1, min(#acts, st.action + (nav.right and 1 or -1)))
        if a ~= st.action then
          st.action = a
          se("SE_SELECT")
        end
      elseif pressed("a") then doAction(st.action)
      elseif pressed("b") or (nav.up and not st.portrait) then back()
      end
      return true
    end
    if pressed("b") then return false end
    if nav.up or nav.down then
      local n = #rows()
      local c = max(1, min(n, st.cursor + (nav.down and 1 or -1)))
      if c ~= st.cursor and n > 0 then
        st.cursor = c
        clamp()
        se("SE_SELECT")
      end
    elseif pressed("a") or (nav.right and not st.portrait) then open()
    end
    return true
  end

  function W.tap(arg)
    if type(arg) ~= "number" then return end
    if st.sheet then
      if arg == YES then return answer(true) end
      if arg == NO or arg == DIM then return answer(false) end
      if arg >= MON and arg < MON + 6 then
        st.partyCursor = arg - MON + 1
        return answer(true)
      end
      return
    end
    if arg == SEG_INBOX then return setFolder("inbox") end
    if arg == SEG_HELD then return setFolder("held") end
    if arg == BACK then return back() end
    if arg >= ACTION and arg < ACTION + 4 then
      st.focus, st.action = "reader", arg - ACTION + 1
      return doAction(st.action)
    end
    if arg >= 1 and rows()[arg] then
      if st.cursor == arg and st.focus == "list" then return open() end
      st.cursor = arg
      clamp()
      if st.portrait then return open() end
      st.focus = "list"
      se("SE_SELECT")
    end
  end

  function W.scroll(dy)
    if st.reading then return end
    st.top = max(0, min(max(0, #rows() - st.visible), st.top - dy / ROW_H))
  end

  function W.hints()
    if st.sheet then return T.list(HINTS.sheet) end
    if st.focus == "reader" then return T.list(HINTS.reader) end
    return T.list(HINTS.list)
  end

  -- ------- drawing (no tables made here)

  local function drawSegs(x, y, w)
    local half = (w - 6) / 2
    for k = 1, 2 do
      local f = k == 1 and "inbox" or "held"
      local sb = K.R(x + 3 + (k - 1) * half, y + 1.5, half, SEG_H - 3)
      local on = st.folder == f
      K.col(on and C.accent or C.chip)
      K.box("fill", sb, 3.5)
      local label = k == 1 and st.segInbox or st.segHeld
      K.text(label, sb[1], sb[2] + 1.6, 4.4, on and K.WHITE or C.ink, "center", sb[3])
      K.addHit(sb, "win", k == 1 and SEG_INBOX or SEG_HELD)
    end
  end

  local function drawList(x, y, w, h)
    local list = rows()
    st.visible = max(1, floor(h / ROW_H))
    clamp()
    local clip = K.R(x, y, w, h)
    K.scissor(clip)
    local first = floor(st.top) + 1
    for i = first, min(#list, first + st.visible + 1) do
      local row = list[i]
      local ry = y + (i - 1 - st.top) * ROW_H
      local rb = K.R(x + 1, ry + 0.5, w - 2, ROW_H - 1)
      local on = i == st.cursor
      local strong = on and st.focus == "list"
      if strong then
        K.col(C.accent)
        K.box("fill", rb, 2.5)
      elseif on then
        K.col(C.wash)
        K.box("fill", rb, 2.5)
      end
      local tint = TINT[row.design] or TINT[0]
      K.col(strong and K.WHITE or tint)
      K.graphics().circle("fill", K.X(x + 5), K.Y(ry + 5), 1.6 * K.sc)
      local ink, sub = strong and K.WHITE or C.ink, strong and K.WHITE or C.soft
      local fs = K.fit(row.from, 4.8, w * 0.5)
      K.text(row.from, x + 9, ry + 2.2 + (4.8 - fs) * 0.5, fs, ink)
      local ts = K.fit(row.title, 4, w * 0.42)
      K.text(row.title, x + w * 0.5, ry + 2.6, ts, sub, "right", w * 0.5 - 4)
      local line = st.folder == "held" and row.monName or row.preview
      local ps = K.fit(line, 4.2, w - 14)
      K.text(line, x + 9, ry + 8.2, ps, sub)
      K.addHit(rb, "win", i, clip)
    end
    if #list == 0 then
      K.text(T(st.folder == "inbox" and "mail.empty" or "mail.emptyHeld"), x + 4, y + h / 2 - 4, 4.8,
        C.faint, "center", w - 8)
    end
    if #list > st.visible then
      local bh = max(6, h * st.visible / #list)
      local by = y + (h - bh) * (st.top / max(1, #list - st.visible))
      K.col(K.BLACK, 0.18)
      K.box("fill", K.R(x + w - 1.6, by, 1.2, bh), 0.6)
    end
    K.scissor(nil)
  end

  -- the open mail: a card in its stationery's tint, then its actions
  local function drawReader(x, y, w, h, body)
    local row = rows()[st.cursor]
    if not row then
      K.text(T("mail.pick"), x, y + h / 2 - 4, 4.8, C.faint, "center", w)
      return
    end
    local tint = TINT[row.design] or TINT[0]
    local cardH = h - ACT_H - 6
    local cb = K.R(x + 4, y + 3, w - 8, cardH)
    K.shadow(cb, 4, 1, 0.22)
    K.col(C.paper)
    K.box("fill", cb, 4)
    local band = K.R(cb[1], cb[2], cb[3], 12)
    K.grad(band, 4, K.light(tint, 0.1), K.dark(tint, 0.1))
    -- (square under the band's rounded foot)
    K.col(K.dark(tint, 0.06))
    K.box("fill", K.R(cb[1], cb[2] + 8, cb[3], 4))
    local tts = K.fit(row.title, 5, cb[3] - 22)
    K.label(row.title, cb[1] + 4, cb[2] + 3.2 + (5 - tts) * 0.5, tts, K.WHITE)
    if env.monIcon and row.species > 0 then pcall(env.monIcon, row.species, cb[1] + cb[3] - 17, cb[2] - 1, 16) end
    -- the words, centred down the card
    local lines = row.lines
    local ly = cb[2] + 16
    local room = cardH - 16 - 10
    local step = min(8, room / max(1, #lines))
    for i = 1, #lines do
      local ls = K.fit(lines[i], 5.2, cb[3] - 10)
      K.text(lines[i], cb[1] + 5, ly + (i - 1) * step, ls, C.ink, "center", cb[3] - 10)
    end
    K.text(row.from, cb[1] + 5, cb[2] + cardH - 8, 4.6, C.soft, "right", cb[3] - 10)
    K.text(T("mail.from"), cb[1] + 5, cb[2] + cardH - 8, 4.2, C.faint)
    -- the actions
    local acts = ACTIONS[st.folder]
    local n = #acts
    local bw = (w - 8 - (n - 1) * 3) / n
    for i = 1, n do
      local bb = K.R(x + 4 + (i - 1) * (bw + 3), y + h - ACT_H - 1, bw, ACT_H - 1)
      local on = st.focus == "reader" and st.action == i
      local warn = st.folder == "inbox" and i == 1
      if on then
        K.col(warn and C.bad or C.accent)
        K.box("fill", bb, 5)
      else
        K.col(C.chip)
        K.box("fill", bb, 5)
      end
      local label = T(acts[i])
      local fs = K.fit(label, 4.6, bw - 4)
      K.text(label, bb[1], bb[2] + 2.6 + (4.6 - fs) * 0.5, fs, on and K.WHITE or C.ink, "center", bb[3])
      K.addHit(bb, "win", ACTION + i - 1)
    end
  end

  local function drawSheet(body)
    if not st.sheet then return end
    K.col(C.dim, 0.3)
    K.box("fill", body)
    K.addHit(body, "win", DIM)
    if st.sheet == "bag" then
      local aw = min(130, body[3] - 16)
      local ab = K.R(body[1] + (body[3] - aw) / 2, body[2] + (body[4] - 50) / 2, aw, 50)
      K.shadow(ab, 6, 1.5, 0.3)
      K.col(C.pane)
      K.box("fill", ab, 6)
      local title, body = T("mail.confirmTitle"), T("mail.confirmBody")
      K.text(title, ab[1], ab[2] + 7, K.fit(title, 6, ab[3] - 6), C.ink, "center", ab[3])
      K.text(body, ab[1], ab[2] + 17, K.fit(body, 4.8, ab[3] - 6), C.soft, "center", ab[3])
      local bw = (aw - 20) / 2
      for i = 1, 2 do
        local yes = i == 2
        local bb = K.R(ab[1] + 8 + (i - 1) * (bw + 4), ab[2] + ab[4] - 17, bw, 12)
        local on = yes == st.yes
        K.col(on and (yes and C.bad or C.soft) or C.chip)
        K.box("fill", bb, 6)
        local bl = T(yes and "mail.confirmMove" or "button.cancel")
        K.text(bl, bb[1], bb[2] + 3, K.fit(bl, 5, bb[3] - 2), on and K.WHITE or C.ink, "center", bb[3])
        K.addHit(bb, "win", yes and YES or NO)
      end
      return
    end
    -- give: the party, two columns of three
    local aw = min(170, body[3] - 10)
    local ab = K.R(body[1] + (body[3] - aw) / 2, body[2] + 4, aw, body[4] - 8)
    K.shadow(ab, 6, 1.5, 0.3)
    K.col(C.pane)
    K.box("fill", ab, 6)
    local gt = T("mail.giveTitle")
    K.text(gt, ab[1], ab[2] + 3, K.fit(gt, 5, ab[3] - 6), C.ink, "center", ab[3])
    local cw, chh = (aw - 12) / 2, min(18, (ab[4] - 14) / 3)
    for i, p in ipairs(st.party) do
      local col, rw = (i - 1) % 2, floor((i - 1) / 2)
      local pb = K.R(ab[1] + 4 + col * (cw + 4), ab[2] + 11 + rw * chh, cw, chh - 2)
      local on = i == st.partyCursor
      K.col(on and (p.held and C.soft or C.accent) or C.head)
      K.box("fill", pb, 3)
      if env.monIcon then pcall(env.monIcon, p.species, pb[1] + 0.5, pb[2] + (pb[4] - 14) / 2 - 1, 14) end
      local ink = on and K.WHITE or (p.held and C.faint or C.ink)
      local ns = K.fit(p.name, 4.8, cw - 18)
      K.text(p.name, pb[1] + 16, pb[2] + 2, ns, ink)
      local sub = p.item or T("mail.noItem")
      local ss = K.fit(sub, 4, cw - 18)
      K.text(sub, pb[1] + 16, pb[2] + pb[4] - 6.5, ss, on and K.WHITE or C.faint)
      K.addHit(pb, "win", MON + i - 1)
    end
  end

  function W.draw(body, clock, portrait)
    st.portrait = portrait
    local x, y, w, h = body[1], body[2], body[3], body[4]
    if portrait then
      if st.reading then
        local bb = K.R(x + 2, y + 1, 26, SEG_H - 2)
        K.text(T("nav.back"), bb[1] + 2, bb[2] + 1.6, 4.6, C.accent)
        K.addHit(bb, "win", BACK)
        drawReader(x, y + SEG_H, w, h - SEG_H, body)
      else
        drawSegs(x, y, w)
        drawList(x, y + SEG_H, w, h - SEG_H)
        K.scissor(body)
      end
    else
      local lw = min(110, floor(w * 0.44))
      drawSegs(x, y, lw)
      drawList(x, y + SEG_H, lw, h - SEG_H)
      K.scissor(body)
      K.col(K.BLACK, 0.1)
      K.box("fill", K.R(x + lw, y, 1, h))
      drawReader(x + lw + 1, y, w - lw - 1, h, body)
    end
    drawSheet(body)
    if st.toast and not K.toast(st.toast, clock, body, C.bad, C.good, C.ink) then st.toast = nil end
  end

  refresh()
  return W
end
