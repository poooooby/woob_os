-- The Mail app: the PC's mailbox as an inbox, in glass. Two folders: Inbox (the PC's mail: read it, move it
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

-- (the rest of the look is the kit's K.UI)
local C = {
  paper = { 252, 251, 247 }, ink = { 28, 28, 30 }, soft = { 112, 112, 120 }, faint = { 162, 162, 170 },
  white = { 255, 255, 255 }, slate = { 120, 132, 178 }, slate2 = { 190, 140, 90 },
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
  -- (keeps the chosen row in view, unless the list was scrolled by hand since the last press: a drag
  -- or the wheel would otherwise be pulled straight back to it on the next frame)
  local function clamp(follow)
    if follow then st.free = false end
    local n = #rows()
    st.cursor = max(1, min(st.cursor, n))
    if not st.free then
      if st.cursor > st.top + st.visible then st.top = st.cursor - st.visible end
      if st.cursor <= st.top then st.top = st.cursor - 1 end
    end
    st.top = max(0, min(st.top, max(0, n - st.visible)))
    if n == 0 then st.focus, st.reading = "list", false end
  end
  local function refresh()
    local s = session()
    st.inbox, st.held = mb.inbox(s), mb.held(s)
    st.segInbox = T("mail.inbox") .. "  " .. #st.inbox
    st.segHeld = T("mail.held") .. "  " .. #st.held
    clamp(true)
  end
  W.refresh = refresh

  local function toast(text, bad)
    st.toast = { text = text, bad = bad, t = now() }
    se(bad and "SE_FAILURE" or "SE_SELECT")
  end
  local function setFolder(f)
    if st.folder == f then return end
    st.folder, st.cursor, st.top, st.focus, st.reading, st.action = f, 1, 0, "list", false, 1
    clamp(true)
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
        clamp(true)
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
      clamp(true)
      if st.portrait then return open() end
      st.focus = "list"
      se("SE_SELECT")
    end
  end

  function W.scroll(dy)
    if st.reading then return end
    st.free = true
    st.top = max(0, min(max(0, #rows() - st.visible), st.top - dy / ROW_H))
  end

  function W.hints()
    if st.sheet then return T.list(HINTS.sheet) end
    if st.focus == "reader" then return T.list(HINTS.reader) end
    return T.list(HINTS.list)
  end

  -- ------- drawing (no tables made here)
  -- Glass, as the Pokédex's: the lights behind in the chosen letter's stationery colours; the folders a
  -- glass switch whose thumb slides; the list a pane whose highlight glides and whose rows rise in
  -- (sliding from the folder's side when it changes); the letter rising onto its tray as it's chosen,
  -- its lines after it, the Pokémon's icon popping up; the sheets rising in over a dim

  local UI = K.UI
  local approach, outCubic, outBack, stagger = K.approach, K.outCubic, K.outBack, K.stagger
  local G, bodyNow = nil, nil
  -- (the motion's numbers: `at` when the rows started rising in, `dir` the side they slide from, `glide`
  -- the highlight's row, `shown` the eased top; the letter, the sheet, the party's highlight)
  local mv = { lastT = nil, coloured = false, r = 0.6, g = 0.6, b = 0.6, r2 = 0.6, g2 = 0.6, b2 = 0.6,
               seg = nil, folder = nil, at = nil, dir = 0, glide = nil, shown = nil, letter = nil, letterAt = -10,
               sheet = nil, sheetAt = -10, monX = nil, monY = nil }
  W.motion = mv

  -- (everything drawn after it at `e` of itself, until unfade(); numbers only)
  local FADES, nFade = {}, 0
  local function fade(e)
    nFade = nFade + 1
    FADES[nFade] = K.getFade()
    K.setFade(FADES[nFade] * (e > 0 and e or 0))
  end
  local function unfade()
    K.setFade(FADES[nFade])
    nFade = nFade - 1
  end
  local function tintOf(row) return row and TINT[row.design] or C.slate end
  local function icon(sp, x, y, size)
    if env.monIcon and sp and sp ~= 0 and sp ~= "" then pcall(env.monIcon, sp, x, y, size, 0, 1, 1, 1, K.getFade()) end
  end

  -- (the backdrop's lights: the chosen letter's stationery, then its folder's; eased)
  local function tint(dt)
    local t1 = tintOf(rows()[st.cursor])
    local t2 = st.folder == "held" and C.slate2 or C.slate
    local rate = mv.coloured and 6 or 1000
    mv.coloured = true
    mv.r, mv.g, mv.b = approach(mv.r, t1[1] / 255, dt, rate), approach(mv.g, t1[2] / 255, dt, rate),
      approach(mv.b, t1[3] / 255, dt, rate)
    mv.r2, mv.g2, mv.b2 = approach(mv.r2, t2[1] / 255, dt, rate), approach(mv.g2, t2[2] / 255, dt, rate),
      approach(mv.b2, t2[3] / 255, dt, rate)
  end

  local function drawSegs(x, y, w, dt)
    local target = st.folder == "inbox" and 1 or 2
    mv.seg = mv.seg and approach(mv.seg, target, dt, 18) or target
    K.glassSwitch(x + 3, y + 1.5, w - 6, SEG_H - 2.5, mv.seg, "win", SEG_INBOX, st.segInbox, SEG_HELD, st.segHeld,
      nil, nil, 4.2)
  end

  -- the letters, in a glass pane: the stationery's dot, who from, its design, the first line
  local function drawList(x, y, w, h, clock, dt)
    local list = rows()
    local focused = st.focus == "list"
    K.glass(K.R(x, y, w, h), 4, focused and 0.62 or 0.45)
    y, h = y + 1, h - 2
    st.visible = max(1, floor(h / ROW_H))
    clamp()
    local clip = K.R(x, y, w, h)
    K.scissor(clip)
    if mv.at == nil then mv.at, mv.glide, mv.shown = clock, nil, nil end
    if mv.shown == nil or st.free then mv.shown = st.top else mv.shown = approach(mv.shown, st.top, dt, 20) end
    local top = mv.shown
    local n = #list
    if n > 0 then
      if mv.glide == nil then mv.glide = st.cursor end
      mv.glide = approach(mv.glide, st.cursor, dt, 24)
      local hb = K.R(x + 1.5, y + (mv.glide - 1 - top) * ROW_H + 0.4, w - 3, ROW_H - 0.8)
      K.col(C.white, focused and 0.88 or 0.45)
      K.box("fill", hb, 2.5)
      if focused then K.ring(hb, 2.5, K.dark(tintOf(list[st.cursor]), 0.1), 0.55 + 0.35 * K.pulse(), 0.6) end
    end
    local first = floor(top) + 1
    local since = clock - mv.at
    for i = first, min(n, first + st.visible + 1) do
      local row = list[i]
      local ry = y + (i - 1 - top) * ROW_H
      local e = stagger(since, i - first, 0.025, 0.26)
      local oy, ox = (1 - e) * 4, (1 - e) * mv.dir * 10
      fade(e)
      local on = i == st.cursor
      if i < n and not on and i + 1 ~= st.cursor then K.hairline(x + 9 + ox, ry + ROW_H - 0.1 + oy, w - 11) end
      local tc = tintOf(row)
      if on then K.glow(x + 5 + ox, ry + 5 + oy, 3.2, 3.2, tc, 0.35) end
      K.col(tc)
      G.circle("fill", K.X(x + 5 + ox), K.Y(ry + 5 + oy), (on and 1.9 or 1.6) * K.sc)
      local fs = K.fit(row.from, 4.8, w * 0.5)
      K.bold(row.from, x + 9 + ox, ry + 2.2 + (4.8 - fs) * 0.5 + oy, fs, C.ink)
      local ts = K.fit(row.title, 4, w * 0.42)
      K.text(row.title, x + w * 0.5 + ox, ry + 2.6 + oy, ts, C.soft, "right", w * 0.5 - 4)
      local line = st.folder == "held" and row.monName or row.preview
      local ps = K.fit(line, 4.2, w - 14)
      K.text(line, x + 9 + ox, ry + 8.2 + oy, ps, C.soft)
      unfade()
      K.addHit(K.R(x + 1.5, ry + 0.4, w - 3, ROW_H - 0.8), "win", i, clip)
    end
    if n == 0 then
      local words = T(st.folder == "inbox" and "mail.empty" or "mail.emptyHeld")
      local e = stagger(since, 0, 0, 0.3)
      K.text(words, x + 4, y + h / 2 - 4 + (1 - e) * 4, K.fit(words, 4.8, w - 8), C.soft, "center", w - 8, e)
    end
    K.scrollbar(x + w, y, h, top, st.visible, n)
    K.scissor(bodyNow)
  end

  -- the open mail: a glass tray, the letter on it in its stationery's tint, then its actions
  local function drawReader(x, y, w, h, clock)
    local tray = K.R(x + 1.5, y + 1.5, w - 3, h - 3)
    K.glass(tray, 5, st.focus == "reader" and 0.6 or 0.42)
    local row = rows()[st.cursor]
    if not row then
      mv.letter = nil
      K.text(T("mail.pick"), x, y + h / 2 - 4, 4.8, C.soft, "center", w)
      return
    end
    if row ~= mv.letter then mv.letter, mv.letterAt = row, clock end
    local t = clock - mv.letterAt
    local e = outCubic(t / 0.3)
    local tc = tintOf(row)
    local cardH = h - ACT_H - 10
    local cb = K.R(x + 4.5, y + 4.5 + (1 - e) * 6, w - 9, cardH)
    fade(e)
    K.shadow(cb, 5, 1.2, 0.2)
    K.col(C.paper)
    K.box("fill", cb, 5)
    K.grad(K.R(cb[1], cb[2], cb[3], 12), 5, K.light(tc, 0.1), K.dark(tc, 0.1))
    -- (square under the band's rounded foot)
    K.col(K.dark(tc, 0.06))
    K.box("fill", K.R(cb[1], cb[2] + 7, cb[3], 5))
    local tts = K.fit(row.title, 5, cb[3] - 22)
    K.label(row.title, cb[1] + 4, cb[2] + 3.2 + (5 - tts) * 0.5, tts, C.white)
    -- (a species: Gen 3's number, the Game Boy games' id; popping up)
    local is = 16 * (0.55 + 0.45 * outBack((t - 0.08) / 0.34))
    icon(row.species, cb[1] + cb[3] - 9 - is / 2, cb[2] + 7 - is / 2, is)
    -- the words, centred down the card, one after another
    local lines = row.lines
    local ly = cb[2] + 16
    local room = cardH - 16 - 10
    local step = min(8, room / max(1, #lines))
    for i = 1, #lines do
      local le = stagger(t - 0.1, i - 1, 0.05, 0.3)
      local ls = K.fit(lines[i], 5.2, cb[3] - 10)
      K.text(lines[i], cb[1] + 5, ly + (i - 1) * step + (1 - le) * 3, ls, C.ink, "center", cb[3] - 10, le)
    end
    local fe = outCubic((t - 0.2) / 0.3)
    K.bold(row.from, cb[1] + 5, cb[2] + cardH - 8, 4.6, C.ink, "right", cb[3] - 10, fe)
    K.text(T("mail.from"), cb[1] + 5, cb[2] + cardH - 8, 4.2, C.soft, nil, nil, fe)
    unfade()
    -- the actions: the first filled, the rest grey; the focus ring on the one chosen
    local acts = ACTIONS[st.folder]
    local n = #acts
    local bw = (w - 9 - (n - 1) * 3) / n
    for i = 1, n do
      local bb = K.R(x + 4.5 + (i - 1) * (bw + 3), y + h - ACT_H - 4, bw, ACT_H)
      K.button(bb, T(acts[i]), i == 1 and "accent" or "gray", st.focus == "reader" and st.action == i)
      K.addHit(bb, "win", ACTION + i - 1)
    end
  end

  local function drawSheet(body, clock, dt)
    if st.sheet ~= mv.sheet then mv.sheet, mv.sheetAt, mv.monX, mv.monY = st.sheet, clock, nil, nil end
    if not st.sheet then return end
    local e = outCubic((clock - mv.sheetAt) / 0.22)
    K.dim(body, 0.24 * e)
    K.addHit(body, "win", DIM)
    fade(e)
    if st.sheet == "bag" then
      -- an alert: the question, Cancel | Move
      local aw = min(124, body[3] - 16)
      local ab = K.R(body[1] + (body[3] - aw) / 2, body[2] + (body[4] - 46) / 2 + (1 - e) * 8, aw, 46)
      K.shadow(ab, 6, 1.6, 0.28)
      K.glass(ab, 6, 0.92)
      local title, words = T("mail.confirmTitle"), T("mail.confirmBody")
      K.bold(title, ab[1], ab[2] + 6, K.fit(title, 5.4, ab[3] - 8), C.ink, "center", ab[3])
      K.text(words, ab[1], ab[2] + 15, K.fit(words, 4.4, ab[3] - 8), C.soft, "center", ab[3])
      local bw = (aw - 14) / 2
      for i = 1, 2 do
        local yes = i == 2
        local bb = K.R(ab[1] + 5 + (i - 1) * (bw + 4), ab[2] + ab[4] - 15, bw, 10)
        K.button(bb, T(yes and "mail.confirmMove" or "button.cancel"), yes and "danger" or "gray", yes == st.yes)
        K.addHit(bb, "win", yes and YES or NO)
      end
      unfade()
      return
    end
    -- give: the party, two columns of three, the highlight gliding between them
    local aw = min(170, body[3] - 10)
    local ab = K.R(body[1] + (body[3] - aw) / 2, body[2] + 4 + (1 - e) * 8, aw, body[4] - 8)
    K.shadow(ab, 6, 1.6, 0.28)
    K.glass(ab, 6, 0.92)
    local gt = T("mail.giveTitle")
    K.bold(gt, ab[1], ab[2] + 3.5, K.fit(gt, 5, ab[3] - 6), C.ink, "center", ab[3])
    local cw, chh = (aw - 12) / 2, min(18, (ab[4] - 14) / 3)
    local c = st.partyCursor - 1
    local tx, ty = ab[1] + 4 + (c % 2) * (cw + 4), ab[2] + 12 + floor(c / 2) * chh
    mv.monX = mv.monX and approach(mv.monX, tx, dt, 24) or tx
    mv.monY = mv.monY and approach(mv.monY, ty, dt, 24) or ty
    for i = 1, #st.party do
      local cl, rw = (i - 1) % 2, floor((i - 1) / 2)
      local pb = K.R(ab[1] + 4 + cl * (cw + 4), ab[2] + 12 + rw * chh, cw, chh - 2)
      K.col(C.white, 0.38)
      K.box("fill", pb, 3.5)
      K.addHit(pb, "win", MON + i - 1)
    end
    local cp = st.party[st.partyCursor]
    if cp then
      local hb = K.R(mv.monX, mv.monY, cw, chh - 2)
      K.col(C.white, 0.92)
      K.box("fill", hb, 3.5)
      K.ring(hb, 3.5, cp.held and C.faint or UI.accent, 0.55 + 0.35 * K.pulse(), 0.6)
    end
    for i = 1, #st.party do
      local p = st.party[i]
      local cl, rw = (i - 1) % 2, floor((i - 1) / 2)
      local px, py = ab[1] + 4 + cl * (cw + 4), ab[2] + 12 + rw * chh
      local ce = stagger(clock - mv.sheetAt, i - 1, 0.03, 0.26)
      local d = (1 - ce) * 3
      fade(ce * (p.held and 0.55 or 1))
      icon(p.species, px + 0.5, py + (chh - 2 - 14) / 2 - 1 + d, 14)
      local ns = K.fit(p.name, 4.8, cw - 18)
      K.bold(p.name, px + 16, py + 2 + d, ns, C.ink)
      local sub = p.item or T("mail.noItem")
      K.text(sub, px + 16, py + chh - 8.5 + d, K.fit(sub, 4, cw - 18), C.soft)
      unfade()
    end
    unfade()
  end

  local M = 3
  function W.draw(body, clock, portrait)
    G = K.graphics()
    bodyNow = body
    st.portrait = portrait
    local dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT = clock
    local x, y, w, h = body[1], body[2], body[3], body[4]
    tint(dt)
    K.backdrop(body, clock, mv.r, mv.g, mv.b, mv.r2, mv.g2, mv.b2)
    K.scissor(body)
    -- (another folder: its rows rise in again, from its side)
    if mv.folder ~= st.folder then
      if mv.folder ~= nil then mv.at, mv.dir = nil, st.folder == "held" and 1 or -1 end
      mv.folder = st.folder
    end
    if portrait then
      if st.reading then
        local bb = K.R(x + 2, y + 1, 30, SEG_H - 2)
        K.chevron(bb[1] + 3, bb[2] + bb[4] / 2 + 0.2, 4, UI.accent, -1)
        K.text(T("nav.back"), bb[1] + 6.5, bb[2] + 1.6, 4.6, UI.accent)
        K.addHit(bb, "win", BACK)
        drawReader(x + M - 1.5, y + SEG_H, w - M * 2 + 3, h - SEG_H - 1, clock)
      else
        drawSegs(x, y, w, dt)
        drawList(x + M, y + SEG_H + 1, w - M * 2, h - SEG_H - 4, clock, dt)
      end
    else
      local lw = min(110, floor(w * 0.44))
      drawSegs(x, y, lw, dt)
      drawList(x + M, y + SEG_H + 1, lw - M * 2, h - SEG_H - 4, clock, dt)
      drawReader(x + lw - 1.5, y + 1, w - lw + 1.5 - M + 1.5, h - 2.5, clock)
    end
    K.scissor(body)
    drawSheet(body, clock, dt)
    if st.toast and not K.toast(st.toast, clock, body, UI.red, UI.green, UI.hud) then st.toast = nil end
  end

  refresh()
  return W
end
