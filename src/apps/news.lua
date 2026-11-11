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

  local BG_TOP, BG_FOOT = { 18, 34, 78 }, { 6, 10, 26 }
  local DESK_TOP, DESK_FOOT = { 210, 222, 240 }, { 120, 136, 168 }
  local RED, WHITE, SOFT = { 230, 40, 50 }, { 255, 255, 255 }, { 255, 255, 255, 0.7 }
  local TAG_WORLD, TAG_YOU = { 10, 132, 255 }, { 255, 149, 0 }
  local TICKER = { 160, 20, 30 }

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
    K.col(RED)
    K.box("fill", K.R(x, y, w, 6), 3)
    K.col(WHITE, 0.55 + 0.45 * abs(sin(clock * 3)))
    K.graphics().circle("fill", K.X(x + 2.6), K.Y(y + 3), 0.9 * K.sc)
    K.bold(T("news.live"), x + 4.4, y + 0.9, 3.6, WHITE)
    return w
  end
  local function studio(x, y, w, h, clock)
    local G = K.graphics()
    K.grad(K.R(x, y, w, h), 0, BG_TOP, BG_FOOT)
    -- (slow light beams across the back)
    for i = 0, 2 do
      local p = (clock * 0.05 + i * 0.33) % 1
      local bx = x + w * (p * 1.4 - 0.2)
      K.col(WHITE, 0.035)
      G.polygon("fill", K.X(bx), K.Y(y), K.X(bx + w * 0.12), K.Y(y), K.X(bx + w * 0.02), K.Y(y + h), K.X(bx - w * 0.1), K.Y(y + h))
    end
    K.glow(x + w * 0.22, y + h * 0.5, w * 0.35, h * 0.5, TAG_WORLD, 0.12)
  end
  -- the anchor: the reporter behind the desk, the mark on its front
  local function anchor(x, y, w, h, clock)
    local ps = min(h * 0.72, w * 0.9)
    reporter(x + (w - ps) / 2, y + h - ps - 8, ps)
    local db = K.R(x + 2, y + h - 12, w - 4, 12)
    K.grad(db, 2.5, DESK_TOP, DESK_FOOT)
    K.col(WHITE, 0.6)
    K.box("fill", K.R(db[1] + 2, db[2] + 0.6, db[3] - 4, 0.5))
    K.bold(T("news.title"), db[1], db[2] + 3.6, K.fit(T("news.title"), 4.4, db[3] - 6), BG_TOP, "center", db[3])
  end

  local function drawCard(x, y, w, h, clock)
    local story = cast.stories[st.i]
    if not story then return end
    local b = K.R(x, y, w, h)
    K.shadow(b, 5, 1.4, 0.35)
    K.col(UI.card)
    K.box("fill", b, 5)
    K.addHit(b, "win", CARD)
    -- (the tag, the count)
    local tag = T(story.tag == "world" and "news.world" or "news.you")
    local tw = K.width(tag, 3.4) + 5
    K.col(story.tag == "world" and TAG_WORLD or TAG_YOU)
    K.box("fill", K.R(x + 4, y + 4, tw, 5.6), 2.8)
    K.bold(tag, x + 4, y + 4.9, 3.4, WHITE, "center", tw)
    K.text(countText(st.i * 100 + #cast.stories), x + w - 24, y + 4.6, 3.4, UI.tertiary, "right", 20)
    -- (the picture: a Pokémon, or an app's)
    local ps = min(26, h * 0.32)
    local px, py = x + w - ps - 4, y + 11
    if story.sp and env.monPic then
      K.col(UI.fill)
      K.box("fill", K.R(px, py, ps, ps), 4)
      pcall(env.monPic, story.sp, px, py, ps, 1)
    elseif story.glyph then
      K.col(story.color or TAG_YOU)
      K.box("fill", K.R(px, py, ps, ps), ps * 0.26)
      if env.glyph then pcall(env.glyph, K.graphics(), story.glyph, K.X(px + ps / 2), K.Y(py + ps / 2), ps * K.sc, 1, story.color) end
    end
    -- (the headline, two lines at most)
    local hw = w - 8 - ps - 4
    K.bold(story.head, x + 4, y + 12, K.fit(story.head, 5.4, hw * 2) , UI.label, "left", hw)
    -- (the words, typed out)
    local tw2 = w - 8
    if not st.lines or st.linesW ~= floor(tw2) or st.linesI ~= st.i then
      st.lines, st.linesW, st.linesI = linesOf(story.body, tw2), floor(tw2), st.i
    end
    local L = st.lines
    local left = shown()
    local ly = y + 12 + ps + 3
    for j, line in ipairs(L.lines) do
      if ly + LINE > y + h - 3 then break end
      local n = L.count[j]
      if left >= n then
        K.text(line, x + 4, ly, SIZE, UI.secondary)
        left = left - n
      else
        if left > 0 then K.text(L.pre[j][left], x + 4, ly, SIZE, UI.secondary) end
        break
      end
      ly = ly + LINE
    end
    if shown() >= L.n then K.chevron(x + w - 6, y + h - 5, 2, UI.accent, 1, K.pulse()) end
  end

  local function ticker(x, y, w, h, clock)
    K.col(TICKER)
    K.box("fill", K.R(x, y, w, h))
    local label = T("news.headlines")
    local lw = K.width(label, 3.8) + 6
    K.col(WHITE)
    K.box("fill", K.R(x, y, lw, h))
    K.bold(label, x, y + (h - 3.8 * 1.2) / 2, 3.8, TICKER, "center", lw)
    local text = cast.ticker
    local tw = K.width(text, 3.8) + 30
    local off = (clock * 14) % tw
    local G = K.graphics()
    local sx, sy, sw, sh
    if G.getScissor then sx, sy, sw, sh = G.getScissor() end
    K.scissor(K.R(x + lw, y, w - lw, h))
    if sx and G.intersectScissor then G.intersectScissor(sx, sy, sw, sh) end
    K.text(text, x + lw + 4 - off, y + (h - 3.8 * 1.2) / 2, 3.8, WHITE)
    K.text(text, x + lw + 4 - off + tw, y + (h - 3.8 * 1.2) / 2, 3.8, WHITE)
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
