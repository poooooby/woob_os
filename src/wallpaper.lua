-- The desktop's wallpapers. "classic" is the game's own colours (drawn by the desktop as before);
-- five more are painted here in the spirit of a Mac's (silk ribbons, dusk hills, a coast at
-- sunset, bands of waves, a bloom of petals), each tinted by the game; and every PNG / JPG a
-- player puts in the mod's wallpapers/ folder: "fill" (cover the screen, cropped from the centre)
-- or "stretch" (the whole picture, stretched to the screen's shape).
--
-- A wallpaper is painted once into a canvas the size it's shown at (its rounded corners from a
-- stencil), and the desktop draws that canvas: one draw a frame, no garbage. It's painted again
-- only when the choice, the size or the game changes. Without canvases (the headless test) or for
-- a picture that won't load, draw() answers false and the desktop shows the classic colours.
--
--   Wall = wallpaper(deps)   deps: gameId() ; list(dir) ; image(path) -> a love Image ; log(fmt, ...)
--   Wall.choices() -> { { id, key | name } } (built-ins, then the folder's pictures; listed anew)
--   Wall.tint(game) -> top, foot (the game's colours) ; Wall.BUILTIN
--   Wall.draw(id, x, y, w, h, radius, fit) -> true when drawn (window pixels; fit for pictures)
--   Wall.place(iw, ih, w, h, fit) -> x, y, sx, sy (where a picture goes) ; Wall.isPicture(id)

local floor, max, min, sin, cos, pi = math.floor, math.max, math.min, math.sin, math.cos, math.pi

return function(deps)
  local Wall = {}
  Wall.BUILTIN = { "classic", "ribbon", "hills", "coast", "waves", "bloom" }
  local TINT = {
    firered = { { 255, 140, 96 }, { 168, 40, 76 } }, leafgreen = { { 150, 216, 112 }, { 34, 116, 92 } },
    ruby = { { 240, 100, 116 }, { 112, 26, 70 } }, sapphire = { { 96, 164, 244 }, { 34, 56, 150 } },
    emerald = { { 84, 214, 164 }, { 18, 96, 112 } }, other = { { 116, 144, 232 }, { 58, 48, 140 } },
  }
  function Wall.tint(game)
    local t = TINT[game] or TINT.other
    return t[1], t[2]
  end

  local WHITE, BLACK = { 255, 255, 255 }, { 0, 0, 0 }
  local function mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
  end

  -- ------- painting (window pixels; only when a canvas is made, so tables are fine here)

  local G
  local function col(c, a) G.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1) end
  local function vgrad(x, y, w, h, c1, c2, a1, a2)
    local m = G.newMesh({
      { x, y, 0, 0, c1[1] / 255, c1[2] / 255, c1[3] / 255, a1 or 1 },
      { x + w, y, 0, 0, c1[1] / 255, c1[2] / 255, c1[3] / 255, a1 or 1 },
      { x + w, y + h, 0, 0, c2[1] / 255, c2[2] / 255, c2[3] / 255, a2 or 1 },
      { x, y + h, 0, 0, c2[1] / 255, c2[2] / 255, c2[3] / 255, a2 or 1 },
    }, "fan", "static")
    G.setColor(1, 1, 1, 1)
    G.draw(m)
    m:release()
  end
  -- a band between two curves across the width, shaded from its top edge to its bottom edge
  local function band(w, top, bot, ctop, cbot, atop, abot)
    local verts, n = {}, 48
    for i = 0, n do
      local x = w * i / n
      verts[#verts + 1] = { x, top(x), 0, 0, ctop[1] / 255, ctop[2] / 255, ctop[3] / 255, atop or 1 }
      verts[#verts + 1] = { x, bot(x), 0, 0, cbot[1] / 255, cbot[2] / 255, cbot[3] / 255, abot or 1 }
    end
    local m = G.newMesh(verts, "strip", "static")
    G.setColor(1, 1, 1, 1)
    G.draw(m)
    m:release()
  end
  local function glow(cx, cy, r, c, a)
    for i = 1, 8 do
      col(c, a / 8)
      G.circle("fill", cx, cy, r * (1 - (i - 1) / 9))
    end
  end
  -- (a steady "random": the same mountains every time)
  local function rng(seed)
    local s = seed
    return function()
      s = (s * 1103515245 + 12345) % 2147483648
      return s / 2147483648
    end
  end

  local PAINT = {}

  -- silk ribbons glowing across a deep ground
  function PAINT.ribbon(w, h, t, f)
    vgrad(0, 0, w, h, mix(f, BLACK, 0.5), mix(f, BLACK, 0.82))
    glow(w * 0.78, h * 0.12, h * 0.9, mix(t, WHITE, 0.2), 0.35)
    G.setBlendMode("add")
    for i = 1, 5 do
      local ph, base = i * 0.9, h * (0.12 + i * 0.13)
      local amp, thick = h * 0.13, h * (0.05 + 0.035 * i / 5)
      local function top(x) return base + amp * sin(x / w * 2.6 + ph) - (x / w) * h * 0.28 end
      local function bot(x) return top(x) + thick * (0.6 + 0.4 * sin(x / w * 3.1 + ph * 1.7)) end
      band(w, top, bot, mix(t, WHITE, 0.4), t, 0.5, 0.02)
      band(w, function(x) return top(x) - thick * 0.25 end, top, t, mix(t, WHITE, 0.4), 0, 0.3)
    end
    G.setBlendMode("alpha")
  end

  -- rolling hills at dusk, the far ones paler
  function PAINT.hills(w, h, t, f)
    vgrad(0, 0, w, h * 0.7, mix(t, WHITE, 0.55), mix(t, WHITE, 0.15))
    glow(w * 0.72, h * 0.3, h * 0.28, mix(WHITE, t, 0.15), 0.9)
    col(mix(WHITE, t, 0.1))
    G.circle("fill", w * 0.72, h * 0.3, h * 0.075)
    for k = 1, 4 do
      local base, amp = h * (0.42 + k * 0.12), h * (0.075 - k * 0.008)
      local c = mix(mix(t, f, 0.2 + k * 0.2), BLACK, (k - 1) * 0.1)
      band(w, function(x)
        return base + amp * sin(x / w * (2.2 + k * 0.7) + k * 1.3) + amp * 0.4 * sin(x / w * (5 + k) + k)
      end, function() return h end, mix(c, WHITE, 0.08), mix(c, BLACK, 0.18))
    end
  end

  -- a sunset coast: the sun on the sea, the hills behind, a headland in front
  function PAINT.coast(w, h, t, f)
    local hz = h * 0.58
    vgrad(0, 0, w, hz, mix(f, BLACK, 0.35), mix(t, WHITE, 0.35))
    glow(w * 0.5, hz, h * 0.45, mix(t, WHITE, 0.5), 0.7)
    col(mix(t, WHITE, 0.7))
    G.circle("fill", w * 0.5, hz, h * 0.09)
    local rand = rng(7)
    local far = {}
    for i = 0, 12 do far[i] = hz - h * (0.06 + rand() * 0.13) end
    band(w, function(x)
      local u = x / w * 12
      local i = min(11, floor(u))
      return far[i] + (far[i + 1] - far[i]) * (u - i)
    end, function() return hz + 1 end, mix(mix(f, BLACK, 0.3), t, 0.3), mix(f, BLACK, 0.4))
    local sea = mix(mix(f, { 40, 70, 130 }, 0.45), BLACK, 0.15)
    vgrad(0, hz, w, h - hz, mix(sea, t, 0.25), mix(sea, BLACK, 0.55))
    for i = 1, 9 do
      local y = hz + h * 0.02 * i
      col(mix(t, WHITE, 0.6), 0.5 - i * 0.045)
      G.rectangle("fill", w * 0.5 - h * (0.12 - i * 0.008), y, h * (0.24 - i * 0.016), max(1, h * 0.004))
    end
    band(w, function(x)
      local u = x / w
      if u < 0.6 then return h + 2 end
      return hz + h * 0.42 * (1 - (u - 0.6) / 0.4) ^ 0.6 - h * 0.48 * ((u - 0.6) / 0.4) ^ 1.4 + h * 0.06
    end, function() return h + 2 end, mix(f, BLACK, 0.55), mix(f, BLACK, 0.8))
  end

  -- thick bands of colour waving up the screen, each casting a soft shadow
  function PAINT.waves(w, h, t, f)
    vgrad(0, 0, w, h, mix(t, WHITE, 0.5), t)
    -- (the highest band first: each one down the screen is drawn over the foot of the last)
    for i = 1, 6 do
      local function edge(x)
        return h * (0.1 + (i - 1) * 0.16) + h * 0.07 * sin(x / w * 2.4 + i * 0.8) + (x / w) * h * 0.12
      end
      local c = mix(mix(t, WHITE, 0.35), f, (i - 1) / 5)
      band(w, function(x) return edge(x) - h * 0.03 end, edge, BLACK, BLACK, 0, 0.22)
      band(w, edge, function() return h + 2 end, mix(c, WHITE, 0.12), mix(c, BLACK, 0.2))
    end
  end

  -- a bloom of petals rising from the foot of the screen, on dark
  function PAINT.bloom(w, h, t, f)
    vgrad(0, 0, w, h, mix(f, BLACK, 0.6), mix(f, BLACK, 0.9))
    glow(w * 0.5, h, h * 0.8, t, 0.5)
    local cx, cy = w * 0.5, h * 1.05
    for j = 1, 9 do
      local a = -1.25 + (j - 1) * (2.5 / 8)
      local len, wid = h * 0.82, h * 0.2
      local c = j % 2 == 0 and mix(t, WHITE, 0.25) or mix(t, f, 0.35)
      G.push()
      G.translate(cx + sin(a) * len * 0.55, cy - cos(a) * len * 0.55)
      G.rotate(a)
      for k = 0, 3 do
        col(mix(c, WHITE, k * 0.12), 0.32)
        G.ellipse("fill", 0, k * h * 0.02, wid * (1 - k * 0.18), len * 0.55 * (1 - k * 0.12))
      end
      G.pop()
    end
  end

  -- a picture from the folder: fill (one scale covering the screen, cropped from the centre) or
  -- stretch (each side to the screen's, nothing cropped)
  function Wall.place(iw, ih, w, h, fit)
    if fit == "stretch" then return 0, 0, w / iw, h / ih end
    local k = max(w / iw, h / ih)
    return (w - iw * k) / 2, (h - ih * k) / 2, k, k
  end
  function Wall.isPicture(id) return type(id) == "string" and id:find("^user:") ~= nil end
  local function paintImage(img, w, h, fit)
    local iw, ih = img:getDimensions()
    local x, y, sx, sy = Wall.place(iw, ih, w, h, fit)
    G.setColor(1, 1, 1, 1)
    G.draw(img, x, y, 0, sx, sy)
  end

  -- ------- the folder

  local userImages = {}
  local function userImage(file)
    local img = userImages[file]
    if img == nil then
      local ok, got = pcall(deps.image, "wallpapers/" .. file)
      img = ok and got or false
      if not ok and deps.log then deps.log("wallpapers/%s won't load: %s", file, tostring(got)) end
      userImages[file] = img
    end
    return img or nil
  end

  function Wall.choices()
    local out = {}
    for _, id in ipairs(Wall.BUILTIN) do out[#out + 1] = { id = id, key = "wall." .. id } end
    local ok, files = pcall(deps.list, "wallpapers")
    if ok and type(files) == "table" then
      for _, file in ipairs(files) do
        local low = type(file) == "string" and file:lower() or ""
        if low:match("%.png$") or low:match("%.jpe?g$") then
          out[#out + 1] = { id = "user:" .. file, name = file:gsub("%.[^.]+$", "") }
        end
      end
    end
    return out
  end

  -- ------- the canvases: by game, then id, then size (bounded)

  local canvases, count = {}, 0
  local function paint(id, w, h, radius, fit)
    G = love and love.graphics
    if not (G and G.newCanvas and G.newMesh and G.stencil) then return nil end
    local img
    if id:sub(1, 5) == "user:" then
      img = userImage(id:sub(6))
      if not img then return nil end
    elseif not PAINT[id] then
      return nil
    end
    local ok, canvas = pcall(G.newCanvas, w, h, { msaa = 4 })
    if not ok or not canvas then ok, canvas = pcall(G.newCanvas, w, h) end
    if not ok or not canvas then return nil end
    local top, foot = Wall.tint(deps.gameId and deps.gameId() or "")
    local painted, err = pcall(function()
      G.push("all")
      G.setCanvas({ canvas, stencil = true })
      G.origin()
      G.setScissor()
      G.setShader()
      G.clear(0, 0, 0, 0)
      G.stencil(function() G.rectangle("fill", 0, 0, w, h, radius, radius) end, "replace", 1)
      G.setStencilTest("greater", 0)
      if img then paintImage(img, w, h, fit) else PAINT[id](w, h, top, foot) end
      G.setStencilTest()
      G.setCanvas()
      G.pop()
    end)
    if not painted then
      pcall(G.setCanvas)
      pcall(G.pop)
      if deps.log then deps.log("the %s wallpaper couldn't be painted: %s", id, tostring(err)) end
      return nil
    end
    return canvas
  end

  local function canvasFor(id, w, h, radius, fit)
    local game = deps.gameId and deps.gameId() or ""
    local byId = canvases[game]
    if not byId then
      byId = {}
      canvases[game] = byId
    end
    local bySize = byId[id]
    if not bySize then
      bySize = {}
      byId[id] = bySize
    end
    -- (a picture's fit is part of its key: one canvas per way of showing it)
    local key = w * 100000000 + h * 10000 + floor(radius * 10) + (fit == "stretch" and 0.5 or 0)
    local c = bySize[key]
    if c == nil then
      if count >= 32 then
        for _, ids in pairs(canvases) do
          for _, sizes in pairs(ids) do
            for _, cv in pairs(sizes) do if cv then pcall(cv.release, cv) end end
          end
        end
        canvases, count = {}, 0
        return canvasFor(id, w, h, radius, fit)
      end
      c = paint(id, w, h, radius, fit) or false
      bySize[key], count = c, count + 1
    end
    return c or nil
  end

  function Wall.draw(id, x, y, w, h, radius, fit)
    if not id or id == "classic" then return false end
    local g = love and love.graphics
    if not g then return false end
    local c = canvasFor(id, floor(w + 0.5), floor(h + 0.5), radius or 0, Wall.isPicture(id) and fit or nil)
    if not c then return false end
    g.setColor(1, 1, 1, 1)
    g.draw(c, x, y)
    return true
  end

  return Wall
end
