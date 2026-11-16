-- The News (the model is src/news.lua, env.news): a studio. The anchor in a TV close-up (the WoobOS
-- News mark behind her, a LIVE light, the title on a lower third; she talks while the words type, a
-- camera cut between stories; a story with a mood (src/news.lua: "cheer", "shock") has her react
-- from its own sheet); one story at a time on a card beside her (World or Your Story, the
-- headline, a picture, the words typed out; a play-by-play's beats each on its own, its turn marked
-- before it); every headline crawling along a ticker at the foot. Words taller than the card follow
-- the line being typed, then scroll. The broadcast is made when it opens (a notification's swarm opens
-- on that story).
--   buttons  A the rest of the words, then the next story; Left the one before; Up / Down scroll; B close
--   touch    the card: the same as A; a drag or the wheel scrolls
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, sin, abs, pi = math.floor, math.max, math.min, math.sin, math.abs, math.pi

local M = 3
local CARD = 2001
local CPS = 52
local SIZE, LINE = 4.1, 5.4
local MARK_W, MARK_SIZE = 9, 3.1     -- a beat's turn, in a pill before its first line
local UTF8 = "[%z\1-\127\194-\244][\128-\191]*"
local HINTS = { main = { { "A", "news.next" }, { "<", "hint.back" }, { "B", "hint.close" } } }
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })
local TALK_FPS = 9
-- a mood's sheet: 0 at rest, 1 and 2 the reaction coming on (at the cut, before the words), 3 on the
-- mood held while she talks, round and round; `hold` a frame of it with her mouth shut, for once the
-- words are all there, HOLD seconds, before 2 and 1 take her back to rest
local MOODS = { cheer = { hold = 15 }, shock = { hold = 3 } }
local LEAD = 2 / TALK_FPS
local HOLD = 1.6

return function(ctx, env)
  local K, Nw, T = env.K, env.news, env.T or NO_T
  local UI = K.UI
  local W = { title = T("app.news") }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local cast = Nw.build(session())
  local st = { i = 1, at = now(), full = false, lines = nil, linesW = 0, linesI = 0, cast = cast, top = 0, cap = 1,
               doneAt = nil, mood = nil, frame = 0 }
  -- (her sheets loaded now, not at the cut to a story)
  if env.anchor then
    pcall(env.anchor)
    for _, story in ipairs(cast.stories) do if story.mood then pcall(env.anchor, story.mood) end end
  end
  W.state = st
  local resume = ctx.resume
  if resume and resume.app == ctx.app and type(resume.state) == "table" and resume.state.story then
    for i, story in ipairs(cast.stories) do if story.key == resume.state.story then st.i = i end end
  end
  ctx.resume = nil

  local countText = K.textCache(function(k) return floor(k / 100) .. " / " .. k % 100 end)

  -- the story's words as lines that fit, each with its typed-out beginnings (made when the story or
  -- the width changes, never in a draw): the body, then each beat of a play-by-play on lines of its
  -- own, its mark (the turn) by the first; a word wider than the line (Japanese has no spaces) broken
  -- between letters
  local function linesOf(story, w)
    local lines, mark, indent = {}, {}, {}
    local function wrap(text, mk)
      local lw = mk and (w - MARK_W) or w
      local line, first = "", true
      local function push(l)
        local j = #lines + 1
        lines[j], mark[j], indent[j] = l, first and mk or false, mk and MARK_W or 0
        first = false
      end
      for word in tostring(text or ""):gmatch("%S+") do
        local try = line == "" and word or (line .. " " .. word)
        if K.width(try, SIZE) <= lw then
          line = try
        elseif line ~= "" and K.width(word, SIZE) <= lw then
          push(line)
          line = word
        else
          -- (too wide even alone: letter by letter)
          local acc = line == "" and "" or (line .. " ")
          for ch in word:gmatch(UTF8) do
            if acc ~= "" and K.width(acc .. ch, SIZE) > lw then
              push(acc)
              acc = ch
            else
              acc = acc .. ch
            end
          end
          line = acc
        end
      end
      if line ~= "" then push(line) end
    end
    wrap(story.body)
    for _, beat in ipairs(story.beats or {}) do wrap(beat.text, beat.mark or "") end
    local out = { lines = lines, mark = mark, indent = indent, pre = {}, count = {}, n = 0 }
    for j, l in ipairs(lines) do
      local pre, k, acc = {}, 0, ""
      for ch in l:gmatch(UTF8) do
        k = k + 1
        acc = acc .. ch
        pre[k] = acc
      end
      out.pre[j], out.count[j], out.n = pre, k, out.n + k
    end
    return out
  end
  local function shown()
    local L = st.lines
    if not L then return 0 end
    if st.full then return L.n end
    return max(0, min(L.n, floor((now() - st.at - 0.25) * CPS)))
  end
  local function go(d)
    local n = #cast.stories
    st.i = (st.i - 1 + d) % n + 1
    st.at, st.full, st.lines, st.top, st.settled, st.doneAt = now(), false, nil, 0, false, nil
    se("SE_SELECT")
  end
  -- (words taller than the card: scrolled once they're all there)
  local function scrollBy(d)
    local L = st.lines
    if not L or shown() < L.n then return end
    st.top = max(0, min(#L.lines - st.cap, st.top + d))
  end
  local function advance()
    if st.lines and shown() < st.lines.n then
      st.full = true
      return
    end
    go(1)
  end

  function W.input(input, nav)
    if input:wasPressed("b") then return false end
    if input:wasPressed("a") or nav.right then advance()
    elseif nav.left then go(-1)
    elseif nav.up then scrollBy(-1)
    elseif nav.down then scrollBy(1) end
    return true
  end
  function W.tap(arg) if arg == CARD then advance() end end
  function W.scroll(dy) scrollBy(-dy / LINE) end
  function W.hints() return T.list(HINTS.main) end

  -- ------- drawing (no tables made here)

  -- the studio in the Pokédex's glass: its lights drifting behind (the first turning to the story's
  -- colour: World blue, Your Story orange, breaking red), the camera's shot framed in glass, the story on a
  -- frosted card, the ticker a strip of glass
  local RED, RED_DEEP, WHITE = { 236, 44, 56 }, { 150, 16, 28 }, { 255, 255, 255 }
  local INK, BODY, SOFT = { 28, 28, 30 }, { 58, 58, 68 }, { 112, 112, 120 }
  local SHADE = { 0, 0, 0 }
  local TAG_WORLD, TAG_YOU = { 40, 150, 255 }, { 255, 156, 40 }
  local SCREEN_TOP, SCREEN_FOOT = { 30, 80, 170 }, { 10, 26, 70 }
  local BREAKING = { swarm = true, outbreak = true, storm = true }
  -- the motion's numbers (the view's own: st is the window's)
  local mv = { lastT = nil, dt = 0, coloured = false, r = 0.16, g = 0.59, b = 1 }

  local ease = K.outCubic
  local function live(x, y, clock)
    local w = K.width(T("news.live"), 3.6) + 7
    K.col(RED, 0.3 + 0.25 * abs(sin(clock * 3)))
    K.box("fill", K.R(x - 0.8, y - 0.8, w + 1.6, 7.6), 3.8)
    K.grad(K.R(x, y, w, 6), 3, RED, RED_DEEP)
    K.col(WHITE, 0.55 + 0.45 * abs(sin(clock * 3)))
    K.graphics().circle("fill", K.X(x + 2.6), K.Y(y + 3), 0.9 * K.sc)
    K.bold(T("news.live"), x + 4.4, y + 0.9, 3.6, WHITE)
    return w
  end
  local function tagColor(story)
    if not story then return TAG_WORLD end
    if BREAKING[story.key] then return RED end
    return story.tag == "world" and TAG_WORLD or TAG_YOU
  end
  -- the studio: its lights over a pale wash, beams of light sweeping, the floor's lights
  local function studio(body, clock)
    local G = K.graphics()
    local x, y, w, h = body[1], body[2], body[3], body[4]
    local c = tagColor(cast.stories[st.i])
    if mv.coloured then
      mv.r = K.approach(mv.r, c[1] / 255, mv.dt, 4)
      mv.g = K.approach(mv.g, c[2] / 255, mv.dt, 4)
      mv.b = K.approach(mv.b, c[3] / 255, mv.dt, 4)
    else
      mv.r, mv.g, mv.b, mv.coloured = c[1] / 255, c[2] / 255, c[3] / 255, true
    end
    K.backdrop(body, clock, mv.r, mv.g, mv.b, 0.2, 0.34, 0.9)
    for i = 0, 2 do
      local p = (clock * 0.05 + i * 0.33) % 1
      local bx = x + w * (p * 1.4 - 0.2)
      K.col(WHITE, 0.22)
      G.polygon("fill", K.X(bx), K.Y(y), K.X(bx + w * 0.12), K.Y(y), K.X(bx + w * 0.02), K.Y(y + h), K.X(bx - w * 0.1), K.Y(y + h))
    end
    -- (the floor's lights)
    for i = 0, 7 do
      K.col(c, 0.3 + 0.15 * sin(clock * 2 + i))
      G.circle("fill", K.X(x + w * (i + 0.5) / 8), K.Y(y + h - 10), 0.6 * K.sc)
    end
  end
  -- which of her frames: everyday, the sheet's frames in turn while the words type (0 at rest); in a
  -- mood, the reaction coming on, the mood while she talks, held once the words are there, then back
  local function frameOf(art, mood)
    local t = now() - st.at
    local L = st.lines
    local typed = L and shown() or 0
    local done = L ~= nil and typed >= L.n
    if done and not st.doneAt then st.doneAt = now() end
    if not mood then
      if L and not done and typed > 0 then return floor(t * TALK_FPS) % art.n end
      return 0
    end
    if t < LEAD then return 1 + floor(t * TALK_FPS) end
    if not done then return 3 + floor((t - LEAD) * TALK_FPS) % (art.n - 3) end
    local d = now() - max(st.doneAt, st.at + LEAD)
    if d < HOLD then return min(MOODS[mood].hold, art.n - 1) end
    if d < HOLD + LEAD then return 2 - floor((d - HOLD) * TALK_FPS) end
    return 0
  end

  -- the anchor's close-up, framed in a pane of glass: a camera shot of the studio (the mark large behind
  -- her, lights out of focus drifting, scan lines), her bust at whole pixels as tall as the shot
  -- (frameOf), a flash for the cut to a new story, the title on a lower third, the LIVE light
  local function closeUp(x, y, w, h, clock)
    local G = K.graphics()
    K.glass(K.R(x - 1.3, y - 1.3, w + 2.6, h + 2.6), 5.2, 0.55)
    local b = K.R(x, y, w, h)
    K.grad(b, 4, SCREEN_TOP, SCREEN_FOOT)
    K.scissor(b)
    if K.drawLogo then
      K.drawLogo(K.X(x + w / 2), K.Y(y + h * 0.4), min(w, h * 1.3) * 0.85 * K.sc, TAG_WORLD, 0.2 + 0.05 * sin(clock * 1.2))
    end
    for i = 0, 5 do
      local px = x + w * ((i * 0.37 + clock * 0.012 * (1 + i % 3)) % 1)
      local py = y + h * (0.12 + (i * 0.23) % 0.55)
      local r = 4 + (i % 3) * 2.5
      K.glow(px, py, r, r, i % 2 == 0 and TAG_WORLD or TAG_YOU, 0.16 + 0.06 * sin(clock * 0.9 + i))
    end
    local story = cast.stories[st.i]
    local mood = story and MOODS[story.mood or ""] and story.mood or nil
    local art = mood and env.anchor and env.anchor(mood)
    if not (art and art.n > 3) then mood, art = nil, env.anchor and env.anchor() end
    if art then
      local foot = art.foot or 0
      local px = max(1, floor(h * 0.94 * K.sc / (art.size - foot)))
      local frame = frameOf(art, mood)
      st.mood, st.frame = mood, frame
      local size = art.size * px
      G.setColor(1, 1, 1, K.getFade())
      G.draw(art.image, art.quads[frame] or art.quads[0], floor(K.X(x + w / 2) - size / 2 + 0.5),
        floor(K.Y(y + h) - size + 0.5) + foot * px, 0, px, px)
    end
    for i = 0, 7 do
      K.col(WHITE, 0.035)
      G.rectangle("fill", K.X(x), K.Y(y + ((clock * 5 + i * h / 8) % h)), w * K.sc, 0.35 * K.sc)
    end
    local cut = now() - st.at
    if cut < 0.2 then
      K.col(WHITE, 0.55 * (1 - cut / 0.2))
      K.box("fill", b)
    end
    -- (the screen's glass: a sheen down from its top)
    K.grad(K.R(x, y, w, min(h, 16)), 4, K.fade(WHITE, 0.16), K.fade(WHITE, 0))
    -- (the lower third: the title on red, a light sweeping it now and then)
    local title = T("news.title")
    local fs = K.fit(title, 4.2, w - 12)
    local tw = min(w - 4, K.width(title, fs) + 9)
    local lb = K.R(x + 2, y + h - 10, tw, 6.6)
    K.shadow(lb, 1, 0.8, 0.45)
    K.grad(lb, 1, RED, RED_DEEP)
    K.col(WHITE)
    K.box("fill", K.R(lb[1], lb[2] + lb[4], tw * 0.6, 0.5))
    local p = (clock * 0.3) % 2
    if p < 1 then
      local sx = lb[1] - 6 + p * (tw + 12)
      K.col(WHITE, 0.3 * sin(p * pi))
      G.polygon("fill", K.X(sx), K.Y(lb[2]), K.X(sx + 3), K.Y(lb[2]), K.X(sx + 1), K.Y(lb[2] + lb[4]), K.X(sx - 2), K.Y(lb[2] + lb[4]))
    end
    K.bold(title, lb[1] + 4, lb[2] + (lb[4] - fs * 1.2) / 2, fs, WHITE)
    K.scissor(st.clip)
    K.ring(b, 4, WHITE, 0.7, 0.45)
    live(x + 3, y + 3, clock)
  end

  -- the story's card: a pane of frosted glass sliding in with each story (a light wiping across it), its
  -- headline and picture settling in after it, the words typed out
  local function drawCard(x, y, w, h, clock)
    local G = K.graphics()
    local story = cast.stories[st.i]
    if not story then return end
    local t = now() - st.at
    local k = ease(t / 0.35)
    local slide = (1 - k) * 14
    local b = K.R(x + slide, y, w, h)
    K.addHit(K.R(x, y, w, h), "win", CARD)
    local f0 = K.getFade()
    K.setFade(f0 * k)
    K.glass(b, 5, 0.62)
    local tagC = story.tag == "world" and TAG_WORLD or TAG_YOU
    K.scissor(b)
    K.grad(K.R(b[1] + 4, b[2] + 1, w - 8, 1.8), 0.9, tagC, K.dark(tagC, 0.25))
    if k < 1 then
      local wx = b[1] + w * k * 1.2 - 10
      K.col(WHITE, 0.5 * (1 - k))
      G.polygon("fill", K.X(wx), K.Y(b[2]), K.X(wx + 8), K.Y(b[2]), K.X(wx - 4), K.Y(b[2] + h), K.X(wx - 12), K.Y(b[2] + h))
    end
    local cx = b[1]
    local top = b[2] + 5
    -- (breaking news: a red banner, its stripes running)
    if BREAKING[story.key] then
      local bb = K.R(cx, top, w, 7)
      K.grad(bb, 0, RED, RED_DEEP)
      for s2 = 0, 12 do
        local sx = cx + ((s2 * 9 + clock * 14) % (w + 9)) - 9
        K.col(WHITE, 0.08)
        G.polygon("fill", K.X(sx), K.Y(top), K.X(sx + 4), K.Y(top), K.X(sx + 1), K.Y(top + 7), K.X(sx - 3), K.Y(top + 7))
      end
      local word = T("news.breaking")
      K.bold(word, cx + 4, top + 1.2, 4, WHITE, nil, nil, 0.7 + 0.3 * abs(sin(clock * 4)))
      top = top + 9
    end
    -- (the tag, the dots for where it is in the broadcast)
    local tag = T(story.tag == "world" and "news.world" or "news.you")
    local tw = K.width(tag, 3.3) + 5
    K.col(tagC)
    K.box("fill", K.R(cx + 4, top, tw, 5.4), 2.7)
    K.bold(tag, cx + 4, top + 0.8, 3.3, WHITE, "center", tw)
    local n = #cast.stories
    local dx = cx + w - 4
    for d = n, 1, -1 do
      local on = d == st.i
      local dw = on and 4 or 1.4
      dx = dx - dw
      if on then K.col(tagC) else K.col(SHADE, 0.2) end
      K.box("fill", K.R(dx, top + 2, dw, 1.4), 0.7)
      dx = dx - 1
    end
    -- (the picture in a spotlight, popping up after the card)
    local ps = min(26, h * 0.32)
    local px, py = cx + w - ps - 4, top + 7
    local pk = K.outBack((t - 0.12) / 0.4)
    local pa = ease((t - 0.12) / 0.2)
    K.col(tagC, 0.16 * pa)
    G.circle("fill", K.X(px + ps / 2), K.Y(py + ps / 2), ps * 0.62 * K.sc)
    local pz = ps * (0.75 + 0.25 * pk)
    local pzx, pzy = px + (ps - pz) / 2, py + (ps - pz) / 2
    if story.sp and env.monPic then
      local bob = sin(clock * 1.6) * 0.6
      pcall(env.monPic, story.sp, pzx, pzy + bob, pz, pa * K.getFade())
    elseif story.glyph then
      local gc = story.color or TAG_YOU
      K.setFade(f0 * k * pa)
      K.grad(K.R(pzx, pzy, pz, pz), pz * 0.26, K.light(gc, 0.1), K.dark(gc, 0.35))
      K.setFade(f0 * k)
      if env.glyph then pcall(env.glyph, G, story.glyph, K.X(pzx + pz / 2), K.Y(pzy + pz / 2), pz * K.sc, pa * K.getFade(), gc) end
    end
    -- (the headline, two lines at most, rising in)
    local hw = w - 8 - ps - 4
    local he = ease((t - 0.06) / 0.32)
    K.bold(story.head, cx + 4, top + 7 + (1 - he) * 3, K.fit(story.head, 5.4, hw * 2), INK, "left", hw, he)
    -- (the words, typed out)
    local tw2 = w - 8
    if not st.lines or st.linesW ~= floor(tw2) or st.linesI ~= st.i then
      st.lines, st.linesW, st.linesI = linesOf(story, tw2), floor(tw2), st.i
    end
    local L = st.lines
    local total = shown()
    local left = total
    local y0 = top + 7 + ps + 3
    local nl = #L.lines
    st.cap = max(1, floor((b[2] + h - 3 - y0) / LINE))
    -- (while typing, the line being typed kept in view; all there (A shows the rest), the last lines,
    -- then where they scroll it)
    if total < L.n then
      local cur, k2 = 1, total
      for j = 1, nl do
        cur = j
        if k2 < L.count[j] then break end
        k2 = k2 - L.count[j]
      end
      st.top, st.settled = max(0, cur - st.cap), false
    elseif not st.settled then
      st.top, st.settled = max(0, nl - st.cap), true
    end
    st.top = max(0, min(st.top, nl - st.cap))
    local first = floor(st.top) + 1
    local ly = y0
    for j = 1, nl do
      local cnt = L.count[j]
      if j < first then
        left = left - min(left, cnt)
      else
        if j >= first + st.cap or left <= 0 then break end
        local lx = cx + 4 + L.indent[j]
        local mk = L.mark[j]
        if mk then
          -- (the beat's turn: a pill; a beat with none, a dot)
          if mk == "" then
            K.col(tagC, 0.9)
            G.circle("fill", K.X(cx + 4 + MARK_W * 0.4), K.Y(ly + SIZE * 0.62), 0.9 * K.sc)
          else
            K.col(tagC, 0.9)
            K.box("fill", K.R(cx + 4, ly + 0.3, MARK_W - 1.6, SIZE * 1.15), 1.6)
            K.bold(mk, cx + 4, ly + 0.3 + (SIZE * 1.15 - MARK_SIZE * 1.2) / 2, MARK_SIZE, WHITE, "center", MARK_W - 1.6)
          end
        end
        if left >= cnt then
          K.text(L.lines[j], lx, ly, SIZE, BODY)
          left = left - cnt
        else
          K.text(L.pre[j][left], lx, ly, SIZE, BODY)
          -- (the caret where the words are being typed)
          local cw = K.width(L.pre[j][left], SIZE)
          K.col(tagC, 0.5 + 0.5 * abs(sin(clock * 8)))
          K.box("fill", K.R(lx + cw + 0.4, ly + 0.4, 0.6, SIZE * 1.1))
          break
        end
        ly = ly + LINE
      end
    end
    if nl > st.cap then
      local sh = st.cap * LINE
      local bh = max(4, sh * st.cap / nl)
      K.col(SHADE, 0.22)
      K.box("fill", K.R(b[1] + w - 2.2, y0 + (sh - bh) * (st.top / max(1, nl - st.cap)), 1, bh), 0.5)
    end
    if total >= L.n then K.chevron(cx + w - 6, b[2] + h - 5, 2, tagC, 1, K.pulse()) end
    K.setFade(f0)
    K.scissor(st.clip)
  end

  -- the ticker: a strip of glass, HEADLINES on red at its left, every headline crawling along it
  local function ticker(x, y, w, h, clock)
    local G = K.graphics()
    local strip = K.R(x, y, w, h)
    K.col(WHITE, 0.72)
    K.box("fill", strip)
    K.grad(K.R(x, y, w, h), 0, K.fade(WHITE, 0.5), K.fade(WHITE, 0))
    K.col(WHITE)
    K.box("fill", K.R(x, y, w, 0.35))
    local label = T("news.headlines")
    local lw = K.width(label, 3.8) + 6
    K.grad(K.R(x, y, lw, h), 0, RED, RED_DEEP)
    K.col(RED_DEEP)
    G.polygon("fill", K.X(x + lw), K.Y(y), K.X(x + lw + 3), K.Y(y + h / 2), K.X(x + lw), K.Y(y + h))
    K.bold(label, x, y + (h - 3.8 * 1.2) / 2, 3.8, WHITE, "center", lw)
    local text = cast.ticker
    local tw = K.width(text, 3.8) + 30
    local off = (clock * 14) % tw
    local sx, sy, sw, sh
    if G.getScissor then sx, sy, sw, sh = G.getScissor() end
    K.scissor(K.R(x + lw + 3, y, w - lw - 3, h))
    if sx and G.intersectScissor then G.intersectScissor(sx, sy, sw, sh) end
    K.text(text, x + lw + 6 - off, y + (h - 3.8 * 1.2) / 2, 3.8, INK)
    K.text(text, x + lw + 6 - off + tw, y + (h - 3.8 * 1.2) / 2, 3.8, INK)
    if sx then G.setScissor(sx, sy, sw, sh) else G.setScissor() end
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    mv.dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT = clock
    st.clip = body
    studio(body, clock)
    K.scissor(body)
    local th = 8
    local ah = h - th
    if not portrait and w >= 200 then
      local lw = floor(w * 0.36)
      closeUp(x + M, y + M + 2, lw, ah - M * 2 - 2, clock)
      drawCard(x + lw + M * 2, y + M + 2, w - lw - M * 3, ah - M * 2 - 2, clock)
    else
      local chH = min(56, floor(ah * 0.4))
      closeUp(x + M, y + M, w - M * 2, chH, clock)
      drawCard(x + M, y + M * 2 + chH, w - M * 2, ah - M * 3 - chH, clock)
    end
    K.rescissor()
    ticker(x, y + h - th, w, th, clock)
    K.scissor(body)
  end

  return W
end
