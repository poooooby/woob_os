-- An update notice (src/notice.lua opens it, full screen over the field: Sh.openFull("notice", ..., { fade,
-- notice })): the glass of the other windows (K.backdrop's lights in the page's colours, faded in over the field,
-- its pictures scattered over it) and a glass card with a coloured head. The question (the Modern Menus: use them? No | Yes),
-- then a last note (where to change it: the mod's options) and OK. The answer is given the moment it's
-- chosen (env.notice.answer: the option set, the notice seen), so the note is only words.
--   buttons  Left / Right the choice, A choose, B No; the note: A or B
--   touch    a button
--
--   window(ctx, env) -> win (src/apps.lua); ctx.notice = a src/notice.lua notice

local floor, max, min = math.floor, math.max, math.min
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })
local WHITE = { 255, 255, 255 }
local A_NO, A_YES, A_OK = 1, 2, 3
local TITLE, BODY, BTN_H, PAD = 6.4, 4.6, 11, 9
-- (each page's two colours: the question's blue to indigo, "on" green to teal, "classic" greys)
local HEAD_ASK = { { 10, 132, 255 }, { 94, 92, 230 } }
local HEAD_ON = { { 52, 199, 89 }, { 48, 176, 199 } }
local HEAD_OFF = { { 142, 142, 147 }, { 99, 99, 110 } }

return function(ctx, env)
  local K, T = env.K, env.T or NO_T
  local n = ctx.notice or {}
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local st = { page = "ask", focus = A_YES, t0 = nil, pageAt = nil, yes = nil, lines = {}, wrapKey = nil, nLines = 0 }
  local W = { title = "" }

  -- (the words in lines of width w, worked out again only when the words, size or width change)
  local function wrap(s, size, w)
    local key = s .. "|" .. floor(size * 100) .. "|" .. floor(w * 10) .. "|" .. floor(K.textScale() * 100)
    if key == st.wrapKey then return st.lines, st.nLines end
    local lines, nl, line = st.lines, 0, ""
    for word in s:gmatch("%S+") do
      local try = line == "" and word or (line .. " " .. word)
      if line ~= "" and K.width(try, size) > w then
        nl = nl + 1
        lines[nl] = line
        line = word
      else
        line = try
      end
    end
    if line ~= "" then nl = nl + 1 lines[nl] = line end
    for k = nl + 1, #lines do lines[k] = nil end
    st.wrapKey, st.nLines = key, nl
    return lines, nl
  end

  local function texts()
    if st.page == "ask" then return T(n.titleKey or ""), T(n.bodyKey or "") end
    return T(st.yes and n.onKey or n.offKey or ""), T(n.afterKey or "")
  end

  local function choose(yes)
    if st.page ~= "ask" then return end
    se("SE_SELECT")
    st.yes = yes
    if env.notice then pcall(env.notice.answer, n, yes) end
    st.page, st.pageAt, st.focus = "after", now(), A_OK
  end
  local function finish()
    if st.page ~= "after" then return end
    se("SE_SELECT")
    if ctx.done then ctx.done() end
  end

  function W.input(input, nav)
    if st.page == "ask" then
      if nav.left or nav.right then
        st.focus = st.focus == A_YES and A_NO or A_YES
        se("SE_SELECT")
      end
      if input:wasPressed("a") then choose(st.focus == A_YES)
      elseif input:wasPressed("b") then choose(false) end
    elseif input:wasPressed("a") or input:wasPressed("b") then
      finish()
    end
    return true
  end

  function W.tap(arg)
    if arg == A_YES then choose(true)
    elseif arg == A_NO then choose(false)
    elseif arg == A_OK then finish() end
  end

  -- the page's colours: the head's two (0..255) and the backdrop's lights (0..1, the same)
  local function colours()
    if st.page == "ask" then return HEAD_ASK end
    return st.yes and HEAD_ON or HEAD_OFF
  end

  function W.draw(body, clock)
    if not st.t0 then
      st.t0, st.pageAt = clock, clock
      -- (the field through, once the host's layer is up: asked before it, it's lost)
      if ctx.seeField then pcall(ctx.seeField, true) end
    end
    local G = K.graphics()
    local e = K.outCubic(min(1, (clock - st.t0) / 0.4))
    local hc = colours()
    -- (the glass's backdrop over the field: drifting lights in the page's colours, its pictures scattered
    -- over them; it fades in from the field, a hint of which stays under it)
    local f0 = K.getFade()
    K.setFade(f0 * e * 0.94)
    local c1, c2 = hc[1], hc[2]
    K.backdrop(body, clock, c1[1] / 255, c1[2] / 255, c1[3] / 255, c2[1] / 255, c2[2] / 255, c2[3] / 255)
    local Art = env.typeArt
    if Art and Art.scatter then
      Art.scatter("pocket", st.page == "ask" and "POKE_BALLS" or "KEY_ITEMS", body, clock, WHITE, 0.3)
    end
    K.setFade(f0)
    K.scissor(body)
    -- (the card: glass, its head in the page's colours with its picture peeking up from the head's foot; it pops
    -- in, and again for the note)
    local title, words = texts()
    local ts = K.textScale() - 1
    local cw = min(body[3] - 20, 196 + ts * 20)
    local inner = cw - PAD * 2
    local lines, nl = wrap(words, BODY, inner)
    local lh = K.lineH(BODY) * 1.25
    local hh = 26 + ts * 6
    local ch = hh + 7 + nl * lh + 7 + BTN_H + PAD
    ch = min(ch, body[4] - 8)
    local pe = K.outBack(min(1, (clock - st.pageAt) / 0.3))
    local cx, cy = body[1] + (body[3] - cw) / 2, body[2] + (body[4] - ch) / 2 + (1 - pe) * 8
    K.rise(e, 10)
    local card = K.R(cx, cy, cw, ch)
    K.glass(card, 8, 0.9)
    K.grad(K.R(cx, cy, cw, hh), 8, c1, c2)
    if Art and Art.pocket then
      G.intersectScissor(K.X(cx), K.Y(cy), cw * K.sc, hh * K.sc)
      Art.pocket(st.page == "ask" and "POKE_BALLS" or "KEY_ITEMS", cx + cw - hh * 0.7, cy + hh * 0.95, hh * 1.4,
        -0.5 + 0.12 * math.sin(clock * 0.4), WHITE, 0.25)
      K.scissor(body)
    end
    K.rescissor()
    K.bold(title, cx + PAD, cy + (hh - K.lineH(TITLE)) / 2, K.fit(title, TITLE, inner - hh * 0.6), WHITE, nil, nil)
    -- (the words, settling in with the page)
    local we = K.outCubic(min(1, (clock - st.pageAt) / 0.25))
    K.rise(we, 4)
    local y = cy + hh + 7
    for k = 1, nl do
      K.text(lines[k], cx + PAD, y, BODY, K.UI.label, "center", inner)
      y = y + lh
    end
    K.settle(we)
    -- (the buttons along the foot)
    local by = cy + ch - PAD - BTN_H
    if st.page == "ask" then
      local bw = (inner - 6) / 2
      local nb = K.R(cx + PAD, by, bw, BTN_H)
      K.button(nb, T("notice.no"), "gray", st.focus == A_NO, 5)
      K.addHit(nb, "win", A_NO)
      local yb = K.R(cx + PAD + bw + 6, by, bw, BTN_H)
      K.button(yb, T("notice.yes"), "accent", st.focus == A_YES, 5)
      K.addHit(yb, "win", A_YES)
    else
      local ob = K.R(cx + PAD + inner * 0.2, by, inner * 0.6, BTN_H)
      K.button(ob, T("notice.ok"), "accent", true, 5)
      K.addHit(ob, "win", A_OK)
    end
    K.settle(e)
  end

  function W.hints() return nil end
  -- (the field shows through, dimmed, the whole time)
  function W.see() return true end

  W.state = st
  return W
end
