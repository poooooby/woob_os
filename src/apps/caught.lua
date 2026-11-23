-- A catch's page and a Pokémon's nickname, full screen (the scene host, src/shell.lua's Sh.openScene; the model
-- ctx.scene is src/caught.lua's job). In glass over lights in the Pokémon's types' colours:
--   "dex"   after a first catch: the Pokémon popping out of its Ball's light among sparkles (its cry), a
--           "Registered" stamp, its Pokédex page (number, name, category, types, height, weight, entry),
--           the game's question -- a nickname? -- and on Yes the keyboard rising (src/keyboard.lua)
--   "name"  a nickname for a catch, an Egg, a gift: the Pokémon and the keyboard at once; a catch that went to
--           the PC says so after
--   buttons  A the words / a key, B No / Delete, Up / Down the question's Yes / No, the D-pad over the keys,
--            START to OK, SELECT the letters' page
--   touch    tap the words, Yes / No, the keys

local floor, max, min, sin, cos, abs, pi = math.floor, math.max, math.min, math.sin, math.cos, math.abs, math.pi

local A = { WORDS = 2101, YES = 2102, NO = 2103, KEY = 2200 }
local OUT = 0.35
local NSP = 18
local TYPE = {
  [0] = { 168, 168, 120 }, [1] = { 192, 48, 40 }, [2] = { 168, 144, 240 }, [3] = { 160, 64, 160 },
  [4] = { 224, 192, 104 }, [5] = { 184, 160, 56 }, [6] = { 168, 184, 32 }, [7] = { 112, 88, 152 },
  [8] = { 184, 184, 208 }, [9] = { 104, 160, 144 }, [10] = { 240, 128, 48 }, [11] = { 104, 144, 240 },
  [12] = { 120, 200, 80 }, [13] = { 248, 208, 48 }, [14] = { 248, 88, 136 }, [15] = { 152, 216, 216 },
  [16] = { 112, 56, 248 }, [17] = { 112, 88, 72 }, [18] = { 238, 153, 172 },
}
local C = { ink = { 28, 28, 30 }, soft = { 112, 112, 120 }, faint = { 160, 160, 170 }, white = { 255, 255, 255 },
            black = { 0, 0, 0 }, accent = { 10, 132, 255 }, red = { 230, 52, 64 }, gold = { 232, 170, 28 },
            stamp = { 214, 40, 56 } }
local SOUNDS = { "SE_SELECT", "SE_FAILURE" }

return function(ctx, env)
  local K, T = env.K, env.T
  local Fx, Kb = env.sceneFx, env.keyboard
  local job = ctx.scene
  local function now() return env.now and env.now() or (love and love.timer and love.timer.getTime() or 0) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local rnd = love and love.math and love.math.random or math.random

  local W = { title = "" }
  if not (job and Fx and Kb) then
    function W.draw() if ctx.done then ctx.done() end end
    function W.input() return true end
    return W
  end
  if env.prewarm then pcall(env.prewarm, SOUNDS, 1) end

  local t0 = now()
  local st = { words = Fx.words(), kb = nil, kbAt = nil, outAt = nil, answer = nil, finished = false,
               cried = false, stampAt = nil, typedSeen = -1 }
  W.state = st
  local t1, t2 = job.types()
  local TOP, FOOT
  local c1, c2 = TYPE[t1] or TYPE[0], TYPE[t2 or t1] or TYPE[t1] or TYPE[0]
  local SP = { a = {}, d = {}, s = {}, at = {} }
  for i = 1, NSP do SP.a[i], SP.d[i], SP.s[i], SP.at[i] = rnd() * 2 * pi, 0.6 + rnd() * 0.6, 1 + rnd() * 1.8, rnd() * 0.5 end

  local function out(answer)
    if st.outAt then return end
    st.answer, st.outAt = answer, now()
  end
  local function openKeyboard()
    st.kb, st.kbAt = Kb.new(job.initial or "", job.max), now()
    Fx.clear(st.words)
  end

  -- (the flow: the page's words, the question; or the keyboard at once)
  if job.kind == "dex" then
    st.stampAt = t0 + 0.75
  else
    openKeyboard()
  end
  local function begin(clock)
    if job.kind ~= "dex" or st.begun then return end
    st.begun = true
    Fx.say(st.words, { job.registered() }, function()
      Fx.say(st.words, job.ask(), function(yes)
        if yes then openKeyboard() else out(false) end
      end, now(), true)
    end, clock, false)
  end

  -- (OK: the name typed; a catch sent to the PC says where it went)
  local function trimmed(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
  local function confirm()
    local name = trimmed(st.kb and st.kb.text)
    se("SE_SELECT")
    if job.kind == "dex" then
      st.kb = nil
      return out(name ~= "" and name or false)
    end
    local nick = name ~= "" and name or job.seed
    local pc = job.pcPages(nick)
    st.kb = nil
    if pc then
      Fx.say(st.words, pc, function() out(nick) end, now(), false)
    else
      out(nick)
    end
  end
  local function key(k)
    local res = Kb.type(st.kb, k, now())
    if res == "ok" then return confirm() end
    if res == "full" or res == "empty" then se("SE_FAILURE") else se("SE_SELECT") end
  end

  local function step(clock)
    if not st.finished and not job.alive() then
      -- (the game let its screen go: ours too, quietly)
      st.finished = true
      job.abandon()
      if ctx.done then ctx.done() end
      return
    end
    if job.kind == "dex" and not st.cried and clock - t0 >= 0.45 then
      st.cried = true
      job.cry()
    end
    if clock - t0 >= 1.1 then begin(clock) end
    if st.outAt and not st.finished and clock - st.outAt >= OUT then
      st.finished = true
      if ctx.done then ctx.done() end
      job.finish(st.answer)
    end
  end

  -- ------- input

  function W.input(input, nav)
    local clock = now()
    step(clock)
    if st.outAt or st.finished then return true end
    local kb = st.kb
    if kb then
      if nav then
        if nav.left then Kb.nav(kb, -1, 0) elseif nav.right then Kb.nav(kb, 1, 0)
        elseif nav.up then Kb.nav(kb, 0, -1) elseif nav.down then Kb.nav(kb, 0, 1) end
      end
      if input:wasPressed("a") then key(kb.cur)
      elseif input:wasPressed("b") then
        if Kb.back(kb, clock) == "empty" then se("SE_FAILURE") else se("SE_SELECT") end
      elseif input:wasPressed("start") then Kb.toOk(kb) se("SE_SELECT")
      elseif input:wasPressed("select") then Kb.toggle(kb) se("SE_SELECT") end
      return true
    end
    local w = st.words
    if w.pages and w.ask and Fx.waiting(w, clock) then
      if nav and (nav.up or nav.down) then
        w.sel = w.sel == 1 and 2 or 1
        se("SE_SELECT")
      end
      if input:wasPressed("a") then se("SE_SELECT") Fx.choice(w, w.sel == 1)
      elseif input:wasPressed("b") then se("SE_SELECT") Fx.choice(w, false) end
      return true
    end
    if input:wasPressed("a") or input:wasPressed("b") then
      if not w.pages and job.kind == "dex" then begin(clock) Fx.press(w, clock) else Fx.press(w, clock) end
    end
    return true
  end

  function W.tap(arg)
    local clock = now()
    if st.outAt or st.finished then return end
    if st.kb then
      if type(arg) == "number" and arg > A.KEY and arg <= A.KEY + Kb.keys(st.kb) then key(arg - A.KEY) end
      return
    end
    if arg == A.YES then se("SE_SELECT") return Fx.choice(st.words, true) end
    if arg == A.NO then se("SE_SELECT") return Fx.choice(st.words, false) end
    if arg == A.WORDS then
      if not st.begun then begin(clock) end
      Fx.press(st.words, clock)
    end
  end

  function W.hints() return nil end
  -- (the keyboard up: no touch pad over it -- its own keys are the way to type)
  function W.noPad() return st.kb ~= nil end
  function W.close()
    if not st.finished then
      st.finished = true
      job.abandon()
    end
  end

  -- ------- drawing

  -- (the types' names: looked up once)
  local function typeName(id)
    if not id then return "" end
    local k = "type." .. tostring(id)
    return T.has and T.has(k) and T(k) or ""
  end
  local names = { [t1 or 0] = typeName(t1) }
  if t2 then names[t2] = typeName(t2) end
  local function typeChip(id, x, y, h)
    local name = names[id] or ""
    local tw = K.width(name, h * 0.62) + h * 1.2
    local c = TYPE[id] or TYPE[0]
    local r = K.R(x, y, tw, h)
    K.col(c, 0.92)
    K.box("fill", r, h / 2)
    if env.typeArt then pcall(env.typeArt.type, id, x + h * 0.55, y + h / 2, h * 0.66, 0, C.white, 0.95) end
    K.bold(name, x + h * 0.95, y + h * 0.17, h * 0.62, C.white)
    return tw
  end

  -- (the backdrop's colours: made once)
  TOP, FOOT = K.light(c1, 0.18), K.dark(K.mix(c1, c2, 0.6), 0.3)
  local MID = K.light(c2, 0.5)

  -- the stage behind it: its type's pictures drifting over the colours, slow rays and a light from behind it,
  -- a Poké Ball's outline turning there, a glass floor under its feet
  local function stage(b, cx, cy, size, clock)
    local G = K.graphics()
    local fa = min(1, max(0, (clock - t0) / 0.5))
    if env.typeArt then
      pcall(env.typeArt.scatter, "type", t1, b, clock, C.white, 0.16 * fa)
      K.rescissor()
    end
    K.glow(cx, cy, b[3] * 0.55, b[4] * 0.7, MID, 0.35 * fa)
    G.setBlendMode("add")
    Fx.rays(cx, cy, max(b[3], b[4]) * 1.2, 18, clock * 0.06, C.white, 0.06 * fa, 0.1)
    G.setBlendMode("alpha")
    K.glow(cx, cy, size * 0.9, size * 0.9, C.white, 0.2 * fa)
    -- (the Ball: its ring, its band either side of the button, the button's ring)
    local R = size * 0.78
    local turn = clock * 0.12
    local X0, Y0 = K.X(cx), K.Y(cy)
    local ca, sa = math.cos(turn), math.sin(turn)
    K.col(C.white, 0.22 * fa)
    G.setLineWidth(max(1, 1.6 * K.sc))
    G.circle("line", X0, Y0, R * K.sc)
    local r = R * 0.26
    G.circle("line", X0, Y0, r * K.sc)
    G.circle("line", X0, Y0, r * 0.55 * K.sc)
    G.line(X0 - ca * R * K.sc, Y0 - sa * R * K.sc, X0 - ca * r * K.sc, Y0 - sa * r * K.sc)
    G.line(X0 + ca * r * K.sc, Y0 + sa * r * K.sc, X0 + ca * R * K.sc, Y0 + sa * R * K.sc)
    -- (the floor: a disc of glass, lit along its far edge)
    local fy = cy + size * 0.43
    K.col(C.white, 0.22 * fa)
    G.ellipse("fill", X0, K.Y(fy), size * 0.5 * K.sc, size * 0.12 * K.sc)
    K.col(C.white, 0.45 * fa)
    G.setLineWidth(max(1, 0.5 * K.sc))
    G.ellipse("line", X0, K.Y(fy), size * 0.5 * K.sc, size * 0.12 * K.sc)
  end

  -- the Pokémon: on a light in its colours, out of its Ball with a pop, sparkles round it
  local function hero(cx, cy, size, clock)
    local G = K.graphics()
    local t = clock - t0
    local pop = job.kind == "dex" and K.outBack(min(1, max(0, (t - 0.25) / 0.45))) or K.outBack(min(1, t / 0.35))
    local fa = min(1, max(0, t / 0.3))
    K.glow(cx, cy, size * 0.95, size * 0.85, c1, 0.55 * fa)
    K.glow(cx, cy + size * 0.1, size * 0.7, size * 0.6, C.white, 0.35 * fa)
    -- (the Ball's flash: a ring opening as it comes out)
    if job.kind == "dex" and t < 0.9 then
      local rt = max(0, (t - 0.2) / 0.7)
      if rt > 0 and rt < 1 then
        G.setBlendMode("add")
        K.col(C.white, (1 - rt) * 0.9)
        G.setLineWidth(max(1, 3 * (1 - rt) * K.sc))
        G.circle("line", K.X(cx), K.Y(cy), size * (0.2 + 0.7 * K.outCubic(rt)) * K.sc)
        G.setBlendMode("alpha")
      end
    end
    K.col(C.black, 0.14 * fa)
    G.ellipse("fill", K.X(cx), K.Y(cy + size * 0.42), size * 0.28 * K.sc, size * 0.06 * K.sc)
    local breathe = 1 + sin(clock * 2.2) * 0.012
    Fx.pic(job.pic(), cx, cy, size, max(0.01, pop) * breathe, 1, 1, 1, fa, false)
    local wa = job.kind == "dex" and max(0, 1 - (t - 0.25) / 0.5) or 0
    if wa > 0 then Fx.pic(job.pic(), cx, cy, size, max(0.01, pop), 1, 1, 1, min(1, wa), true) end
    -- (sparkles: a burst as it comes out, then a few winking; gold for a shiny)
    for i = 1, NSP do
      local tt = t - 0.3 - SP.at[i]
      if tt > 0 then
        local a, d
        if tt < 0.8 then
          a, d = 1 - tt / 0.8, SP.d[i] * (0.4 + 0.6 * K.outCubic(tt / 0.8))
        else
          a, d = max(0, sin((tt * 0.9 + SP.at[i] * 3) * pi)) * (job.shiny and 0.9 or 0.45), SP.d[i]
        end
        if a > 0.02 then
          local x, y = cx + cos(SP.a[i]) * size * 0.62 * d, cy + sin(SP.a[i]) * size * 0.5 * d
          K.glow(x, y, SP.s[i] * 2, SP.s[i] * 2, job.shiny and C.gold or c2, a * 0.4)
          Fx.star(x, y, SP.s[i] * (0.6 + 0.4 * a), job.shiny and C.gold or C.white, a, tt * 2)
        end
      end
    end
    -- (its Ball, at its foot)
    if job.ball and env.itemIcon and fa > 0.5 then
      pcall(env.itemIcon, job.ball, cx + size * 0.32, cy + size * 0.28, 7, K.getFade())
      K.rescissor()
    end
  end

  -- (the page's height for its words at this width: the card no taller than they are)
  local function pageNeed(w)
    local info = job.info
    local g = (K.textScale() - 1) * 2
    local pw = w - 10
    local need = 4 + K.fit(job.name, 6.4, pw) * 1.25 + g + 6.4 + 3 + g + 4
    if info and info.numText then need = need + 4.6 + g end
    if info and info.category and info.category ~= "" then need = need + 5.4 + g end
    if info and (info.heightText or info.weightText) then need = need + 10.4 + g * 2 end
    if info and info.description and info.description ~= "" then
      local lines = math.ceil(K.width(info.description, 3.7) * 1.1 / pw)
      need = need + 2.2 + lines * K.lineH(3.7) * 1.05
    end
    return need
  end
  -- the page: number and name, category, types, height and weight, the entry
  local function page(x, y, w, h, clock)
    local info = job.info
    local e = K.outCubic((clock - t0 - 0.55) / 0.4)
    if e <= 0 then return end
    local f0 = K.getFade()
    K.setFade(f0 * e)
    local b = K.R(x + (1 - e) * 8, y, w, h)
    K.glass(b, 6, 0.86)
    K.scissor(b)
    local px, py, pw = b[1] + 5, b[2] + 4, w - 10
    local g = (K.textScale() - 1) * 2
    if info and info.numText then
      K.text(info.numText, px, py, 3.8, C.soft)
      py = py + 4.6 + g
    end
    local ns = K.fit(job.name, 6.4, pw)
    K.bold(job.name, px, py, ns, C.ink)
    py = py + ns * 1.25 + g
    if info and info.category and info.category ~= "" then
      K.text(info.category, px, py, 4, C.soft)
      py = py + 5.4 + g
    end
    local tx = px
    local ch = 6.4
    tx = tx + typeChip(t1, tx, py, ch) + 2
    if t2 then typeChip(t2, tx, py, ch) end
    py = py + ch + 3 + g
    if info and (info.heightText or info.weightText) then
      local half = pw / 2
      K.text(T("caught.height"), px, py, 3.4, C.soft)
      K.text(T("caught.weight"), px + half, py, 3.4, C.soft)
      py = py + 4.2 + g
      K.bold(info.heightText or "?", px, py, 4.4, C.ink)
      K.bold(info.weightText or "?", px + half, py, 4.4, C.ink)
      py = py + 6.2 + g
    end
    if info and info.description and info.description ~= "" then
      K.col(C.ink, 0.1)
      K.graphics().rectangle("fill", K.X(px), K.Y(py), pw * K.sc, max(1, 0.25 * K.sc))
      py = py + 2.2
      K.text(info.description, px, py, 3.7, C.ink, "left", pw)
    end
    K.scissor()
    K.setFade(f0)
  end

  -- ("Registered": a stamp landing on the page's corner)
  local function stamp(x, y, clock)
    if not st.stampAt or clock < st.stampAt then return end
    local k = min(1, (clock - st.stampAt) / 0.28)
    local s = 1.6 - 0.6 * K.outBack(k)
    local label = T("caught.stamp")
    local fs = 4.4 * s
    local sw = K.width(label, fs) + 8 * s
    local sh = 8.5 * s
    local G = K.graphics()
    G.push()
    G.translate(K.X(x), K.Y(y))
    G.rotate(-0.16)
    G.translate(-K.X(x), -K.Y(y))
    local r = K.R(x - sw / 2, y - sh / 2, sw, sh)
    K.col(C.stamp, 0.92 * min(1, k * 2))
    K.box("fill", r, 2)
    K.ring(K.R(r[1] + 0.9, r[2] + 0.9, r[3] - 1.8, r[4] - 1.8), 1.5, C.white, 0.8, 0.35)
    K.bold(label, r[1], r[2] + (sh - fs * 1.2) / 2, fs, C.white, "center", sw)
    G.pop()
  end

  function W.draw(body, clock, portrait)
    clock = now()
    step(clock)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    local b = K.R(x, y, w, h)
    -- (the Pokémon's own colours: its first type's light at the top, its second's, deeper, at the foot)
    K.grad(b, 0, TOP, FOOT)
    local bh = Fx.bubbleH()
    local kbW = min(w - 8, 236)
    local kbH = Kb.height(kbW)
    local kbK = 0
    if st.kb then kbK = K.outCubic((clock - st.kbAt) / 0.3) end
    local foot = y + h - 4 - (st.kb and kbH * kbK + 2 or bh + 3)
    local narrow = portrait or w < 200
    local showPage = job.kind == "dex" and not st.kb
    -- (the Pokémon: beside its page when there's room, alone in the middle when the keyboard's up)
    local cx, cy, size
    if showPage and not narrow then
      size = min(foot - y - 8, w * 0.38, 86)
      cx, cy = x + w * 0.27, y + (foot - y) / 2 + 2
    elseif showPage then
      size = min((foot - y) * 0.42, w * 0.6, 70)
      cx, cy = x + w / 2, y + 4 + size / 2
    else
      size = min(foot - y - 16, w * 0.5, 80)
      cx, cy = x + w / 2, y + 12 + (foot - y - 12) / 2
    end
    stage(b, cx, cy, size, clock)
    -- (a nickname: whose, over the Pokémon, white on a dark pill: it reads on any colour)
    if not showPage then
      local title = job.title or job.name
      local ts = K.fit(title, 5, w - 24)
      local tw = K.width(title, ts) + 10
      local tb = K.R(x + (w - tw) / 2, y + 3, tw, ts * 1.2 + 3.4)
      K.col(C.black, 0.32)
      K.box("fill", tb, tb[4] / 2)
      K.bold(title, tb[1], tb[2] + 1.7, ts, C.white, "center", tw)
    end
    hero(cx, cy, size, clock)
    if showPage then
      if narrow then
        local py = cy + size / 2 + 3
        page(x + 6, py, w - 12, min(foot - py, pageNeed(w - 12)), clock)
        stamp(x + w - 22, py + 3, clock)
      else
        local px = x + w * 0.52
        local pw = x + w - 6 - px
        local ph = min(foot - y - 8, pageNeed(pw))
        local py = max(y + 6, min(foot - 2 - ph, cy - ph / 2))
        page(px, py, pw, ph, clock)
        stamp(x + w - 24, py + 4, clock)
      end
    end
    -- the words, or the keyboard rising
    if st.kb then
      local ky = y + h - 3 - kbH * kbK
      Kb.draw(st.kb, x + (w - kbW) / 2, ky, kbW, clock, A.KEY, T("kb.ok"), job.seed ~= "" and job.seed or nil)
    else
      if st.words.pages and not st.words.ask then K.addHit(K.R(x, y, w, foot - y), "win", A.WORDS) end
      Fx.bubble(st.words, K.R(x + 6, y + h - bh - 3, w - 12, bh), clock, A.WORDS, A.YES, A.NO)
    end
    -- (in from white -- the Ball's flash -- or black; out to black)
    local fade = 1 - min(1, (clock - t0) / 0.3)
    if fade > 0 then
      K.col(job.kind == "dex" and C.white or C.black, fade)
      K.box("fill", b)
    end
    if st.outAt then
      K.col(C.black, min(1, (clock - st.outAt) / OUT))
      K.box("fill", b)
    end
  end

  return W
end
