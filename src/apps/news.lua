-- The News (the model is src/news.lua, env.news): a studio. The game's own reporter at a desk with
-- the WoobOS News mark and a LIVE light; one story at a time on a card beside them (World or Your
-- Story, the headline, a picture, the words typed out); every headline crawling along a ticker at
-- the foot. The broadcast is made when it opens (a notification's swarm opens on that story).
--   buttons  A the rest of the words, then the next story; Left the one before; B close
--   touch    the card: the same as A
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, sin, abs = math.floor, math.max, math.min, math.sin, math.abs

local M = 3
local CARD = 2001
local CPS = 52
local SIZE, LINE = 4.1, 5.4
local UTF8 = "[%z\1-\127\194-\244][\128-\191]*"
local HINTS = { main = { { "A", "news.next" }, { "<", "hint.back" }, { "B", "hint.close" } } }
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env)
  local K, Nw, T = env.K, env.news, env.T or NO_T
  local UI = K.UI
  local W = { title = T("app.news") }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local cast = Nw.build(session())
  local st = { i = 1, at = now(), full = false, lines = nil, linesW = 0, linesI = 0, cast = cast }
  W.state = st
  local resume = ctx.resume
  if resume and resume.app == ctx.app and type(resume.state) == "table" and resume.state.story then
    for i, story in ipairs(cast.stories) do if story.key == resume.state.story then st.i = i end end
  end
  ctx.resume = nil

  local countText = K.textCache(function(k) return floor(k / 100) .. " / " .. k % 100 end)

  -- the story's words as lines that fit, each with its typed-out beginnings (made when the story or
  -- the width changes, never in a draw)
  local function linesOf(text, w)
    local lines, line = {}, ""
    for word in tostring(text or ""):gmatch("%S+") do
      local try = line == "" and word or (line .. " " .. word)
      if line ~= "" and K.width(try, SIZE) > w then
        lines[#lines + 1] = line
        line = word
      else
        line = try
      end
    end
    if line ~= "" then lines[#lines + 1] = line end
    local out = { lines = lines, pre = {}, count = {}, n = 0 }
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
    st.at, st.full, st.lines = now(), false, nil
    se("SE_SELECT")
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
    elseif nav.left then go(-1) end
    return true
  end
  function W.tap(arg) if arg == CARD then advance() end end
  function W.hints() return T.list(HINTS.main) end

  -- ------- drawing (no tables made here)

  local BG_TOP, BG_FOOT = { 20, 38, 88 }, { 5, 8, 24 }
  local DESK_TOP, DESK_FOOT = { 214, 226, 244 }, { 110, 128, 164 }
  local RED, RED_DEEP, WHITE = { 236, 44, 56 }, { 150, 16, 28 }, { 255, 255, 255 }
  local SOFT, FAINT = { 196, 210, 236 }, { 120, 138, 176 }
  local PANEL, PANEL_EDGE = { 12, 20, 46, 0.88 }, { 255, 255, 255, 0.14 }
  local TAG_WORLD, TAG_YOU = { 40, 150, 255 }, { 255, 156, 40 }
  local SCREEN_TOP, SCREEN_FOOT = { 30, 80, 170 }, { 10, 26, 70 }
  local TICKER = { 168, 20, 32 }
  local BREAKING = { swarm = true, outbreak = true, storm = true }

  local function ease(k) k = min(1, max(0, k)) return 1 - (1 - k) * (1 - k) * (1 - k) end
  local function reporter(x, y, size)
    local img = env.reporter and env.reporter()
    if not img then return end
    local G = K.graphics()
    local iw, ih = img:getDimensions()
    local s = size * K.sc / max(iw, ih)
    G.setColor(1, 1, 1, 1)
    G.draw(img, K.X(x), K.Y(y), 0, s, s)
  end
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
  -- the studio: night blue, beams sweeping, a big screen behind the anchor with the mark turning
  local function studio(x, y, w, h, clock)
    local G = K.graphics()
    K.grad(K.R(x, y, w, h), 0, BG_TOP, BG_FOOT)
    for i = 0, 2 do
      local p = (clock * 0.05 + i * 0.33) % 1
      local bx = x + w * (p * 1.4 - 0.2)
      K.col(WHITE, 0.035)
      G.polygon("fill", K.X(bx), K.Y(y), K.X(bx + w * 0.12), K.Y(y), K.X(bx + w * 0.02), K.Y(y + h), K.X(bx - w * 0.1), K.Y(y + h))
    end
    K.glow(x + w * 0.22, y + h * 0.5, w * 0.35, h * 0.5, TAG_WORLD, 0.14)
    -- (the floor's lights)
    for i = 0, 7 do
      K.col(TAG_WORLD, 0.12 + 0.08 * sin(clock * 2 + i))
      G.circle("fill", K.X(x + w * (i + 0.5) / 8), K.Y(y + h - 10), 0.6 * K.sc)
    end
  end
  local function screen(x, y, w, h, clock)
    local b = K.R(x, y, w, h)
    K.grad(b, 3, SCREEN_TOP, SCREEN_FOOT)
    K.ring(b, 3, PANEL_EDGE, 1, 0.5)
    -- (the W mark, a light going round it)
    if K.drawLogo then
      K.drawLogo(K.X(x + w / 2), K.Y(y + h / 2), min(w, h) * 0.55 * K.sc, TAG_WORLD, 0.35 + 0.15 * sin(clock * 1.5))
    end
    local G = K.graphics()
    for i = 0, 5 do
      local yy = y + ((clock * 6 + i * h / 6) % h)
      K.col(WHITE, 0.04)
      G.rectangle("fill", K.X(x + 1), K.Y(yy), (w - 2) * K.sc, 0.4 * K.sc)
    end
  end
  -- the anchor: the reporter in front of the screen, behind the desk
  local function anchor(x, y, w, h, clock)
    screen(x + w * 0.12, y + 4, w * 0.76, h * 0.42, clock)
    local ps = min(h * 0.72, w * 0.9)
    reporter(x + (w - ps) / 2, y + h - ps - 8, ps)
    local db = K.R(x + 2, y + h - 12, w - 4, 12)
    K.shadow(db, 2.5, 1.2, 0.4)
    K.grad(db, 2.5, DESK_TOP, DESK_FOOT)
    K.col(WHITE, 0.6)
    K.box("fill", K.R(db[1] + 2, db[2] + 0.6, db[3] - 4, 0.5))
    K.col(RED)
    K.box("fill", K.R(db[1], db[2] + db[4] - 2, db[3], 1.2))
    K.bold(T("news.title"), db[1], db[2] + 3.4, K.fit(T("news.title"), 4.4, db[3] - 6), BG_TOP, "center", db[3])
  end

  local function drawCard(x, y, w, h, clock)
    local G = K.graphics()
    local story = cast.stories[st.i]
    if not story then return end
    -- (a new story: it slides in, a light wiping across)
    local k = ease((now() - st.at) / 0.35)
    local slide = (1 - k) * 14
    local b = K.R(x + slide, y, w, h)
    K.shadow(b, 5, 2, 0.5)
    K.col(PANEL, k)
    K.box("fill", b, 5)
    K.ring(b, 5, PANEL_EDGE, k, 0.45)
    K.addHit(K.R(x, y, w, h), "win", CARD)
    local tagC = story.tag == "world" and TAG_WORLD or TAG_YOU
    K.scissor(b)
    K.grad(K.R(b[1], b[2], w, 3), 0, tagC, K.dark(tagC, 0.35))
    if k < 1 then
      local wx = b[1] + w * k * 1.2 - 10
      K.col(WHITE, 0.25 * (1 - k))
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
    K.col(tagC, k)
    K.box("fill", K.R(cx + 4, top, tw, 5.4), 2.7)
    K.bold(tag, cx + 4, top + 0.8, 3.3, WHITE, "center", tw, k)
    local n = #cast.stories
    local dx = cx + w - 4
    for d = n, 1, -1 do
      local on = d == st.i
      local dw = on and 4 or 1.4
      dx = dx - dw
      K.col(WHITE, on and 0.95 or 0.3)
      K.box("fill", K.R(dx, top + 2, dw, 1.4), 0.7)
      dx = dx - 1
    end
    -- (the picture in a spotlight)
    local ps = min(26, h * 0.32)
    local px, py = cx + w - ps - 4, top + 7
    K.glow(px + ps / 2, py + ps / 2, ps * 0.85, ps * 0.85, tagC, 0.3 * k)
    if story.sp and env.monPic then
      local bob = sin(clock * 1.6) * 0.6
      pcall(env.monPic, story.sp, px, py + bob, ps, k)
    elseif story.glyph then
      K.grad(K.R(px, py, ps, ps), ps * 0.26, K.light(story.color or TAG_YOU, 0.1), K.dark(story.color or TAG_YOU, 0.35))
      if env.glyph then pcall(env.glyph, G, story.glyph, K.X(px + ps / 2), K.Y(py + ps / 2), ps * K.sc, k, story.color) end
    end
    -- (the headline, two lines at most)
    local hw = w - 8 - ps - 4
    K.bold(story.head, cx + 4, top + 7, K.fit(story.head, 5.4, hw * 2), WHITE, "left", hw, k)
    -- (the words, typed out)
    local tw2 = w - 8
    if not st.lines or st.linesW ~= floor(tw2) or st.linesI ~= st.i then
      st.lines, st.linesW, st.linesI = linesOf(story.body, tw2), floor(tw2), st.i
    end
    local L = st.lines
    local left = shown()
    local ly = top + 7 + ps + 3
    for j, line in ipairs(L.lines) do
      if ly + LINE > b[2] + h - 3 then break end
      local cnt = L.count[j]
      if left >= cnt then
        K.text(line, cx + 4, ly, SIZE, SOFT)
        left = left - cnt
      else
        if left > 0 then
          K.text(L.pre[j][left], cx + 4, ly, SIZE, SOFT)
          -- (the caret where the words are being typed)
          local cw = K.width(L.pre[j][left], SIZE)
          K.col(tagC, 0.5 + 0.5 * abs(sin(clock * 8)))
          K.box("fill", K.R(cx + 4 + cw + 0.4, ly + 0.4, 0.6, SIZE * 1.1))
        end
        break
      end
      ly = ly + LINE
    end
    if shown() >= L.n then K.chevron(cx + w - 6, b[2] + h - 5, 2, tagC, 1, K.pulse()) end
    K.scissor(st.clip)
  end

  local function ticker(x, y, w, h, clock)
    local G = K.graphics()
    K.grad(K.R(x, y, w, h), 0, TICKER, RED_DEEP)
    local label = T("news.headlines")
    local lw = K.width(label, 3.8) + 6
    K.col(WHITE)
    K.box("fill", K.R(x, y, lw, h))
    K.col(WHITE)
    G.polygon("fill", K.X(x + lw), K.Y(y), K.X(x + lw + 3), K.Y(y + h / 2), K.X(x + lw), K.Y(y + h))
    K.bold(label, x, y + (h - 3.8 * 1.2) / 2, 3.8, TICKER, "center", lw)
    local text = cast.ticker
    local tw = K.width(text, 3.8) + 30
    local off = (clock * 14) % tw
    local sx, sy, sw, sh
    if G.getScissor then sx, sy, sw, sh = G.getScissor() end
    K.scissor(K.R(x + lw + 3, y, w - lw - 3, h))
    if sx and G.intersectScissor then G.intersectScissor(sx, sy, sw, sh) end
    K.text(text, x + lw + 6 - off, y + (h - 3.8 * 1.2) / 2, 3.8, WHITE)
    K.text(text, x + lw + 6 - off + tw, y + (h - 3.8 * 1.2) / 2, 3.8, WHITE)
    if sx then G.setScissor(sx, sy, sw, sh) else G.setScissor() end
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    st.clip = body
    studio(x, y, w, h, clock)
    local th = 8
    local ah = h - th
    if not portrait and w >= 200 then
      local lw = floor(w * 0.36)
      anchor(x + M, y + 10, lw, ah - 12, clock)
      live(x + M + 1, y + 3, clock)
      drawCard(x + lw + M * 2, y + M + 2, w - lw - M * 3, ah - M * 2 - 2, clock)
    else
      local aw = min(w * 0.5, 46)
      anchor(x + M, y + 8, aw, 40, clock)
      live(x + M + 1, y + 2, clock)
      drawCard(x + M, y + 50, w - M * 2, ah - 52, clock)
    end
    ticker(x, y + h - th, w, th, clock)
    K.scissor(body)
  end

  return W
end
