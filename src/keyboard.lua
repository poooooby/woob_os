-- The nickname keyboard: the Pokédex search's look (white keys on glass, grey Delete and Shift, the accent's
-- OK, the D-pad's key ringed, the one just typed flashing) with the game's own letters -- capitals, small
-- letters and the marks its naming screen has (0-9 ! ? ♂ ♀ / - … “ ” ‘ ’ , .), nothing it can't keep.
-- It starts on capitals and drops to small letters after the first one, as a phone's does; Shift
-- (or SELECT) changes it back, 123 / ABC the marks. Ten letters at most (the game's).
--
--   Kb = Keyboard(K, T)
--   kb = Kb.new(text, max)            -> { text, max, page = "upper" | "lower" | "marks", cur, typedK, typedAt }
--   Kb.type(kb, k, clock)             -> "ok" | "typed" | "deleted" | "page" | "full" | "empty" (k: a key's index)
--   Kb.back(kb, clock) -> "deleted" | "empty" ; Kb.toggle(kb) (SELECT: the next page) ; Kb.toOk(kb) (START)
--   Kb.nav(kb, dx, dy)                (the D-pad over the keys)
--   Kb.len(kb) -> letters typed ; Kb.keys(kb) -> the page's key count
--   Kb.height(w) -> the sheet's height ; Kb.draw(kb, x, y, w, clock, hit, okWord) (hit + k: a key's tap)

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local UTF8 = "[%z\1-\127\194-\244][\128-\191]*"
local LAST = "[%z\1-\127\194-\244][\128-\191]*$"

-- (a page's rows: letters on a ten-key grid; Shift, Delete, the page key, space and OK wider)
local ROWS = {
  upper = {
    { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
    { "A", "S", "D", "F", "G", "H", "J", "K", "L" },
    { "SHIFT", "Z", "X", "C", "V", "B", "N", "M", "DEL" },
    { "MARKS", "SPACE", "OK" },
  },
  lower = {
    { "q", "w", "e", "r", "t", "y", "u", "i", "o", "p" },
    { "a", "s", "d", "f", "g", "h", "j", "k", "l" },
    { "SHIFT", "z", "x", "c", "v", "b", "n", "m", "DEL" },
    { "MARKS", "SPACE", "OK" },
  },
  marks = {
    { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
    { "!", "?", "\226\153\130", "\226\153\128", "/", "-", "\226\128\166", ",", "." },
    { "\226\128\156", "\226\128\157", "\226\128\152", "\226\128\153", "DEL" },
    { "ABC", "SPACE", "OK" },
  },
}
local SPECIAL = { SHIFT = true, DEL = true, MARKS = true, ABC = true, SPACE = true, OK = true }

-- (each page's keys laid out once: x0 / w in key widths of a ten-key row, its row)
local LAYOUT = {}
for name, rows in pairs(ROWS) do
  local L = { keys = {}, row = {}, x0 = {}, w = {}, first = {}, count = {} }
  for r, keys in ipairs(rows) do
    L.first[r], L.count[r] = #L.keys + 1, #keys
    for c, key in ipairs(keys) do
      local k = #L.keys + 1
      L.keys[k], L.row[k] = key, r
      if r == 1 then L.x0[k], L.w[k] = c - 1, 1
      elseif r == 2 then L.x0[k], L.w[k] = c - 0.5, 1
      elseif r == 3 then
        if key == "SHIFT" then L.x0[k], L.w[k] = 0, 1.5
        elseif key == "DEL" then L.x0[k], L.w[k] = 8.5, 1.5
        elseif name == "marks" then L.x0[k], L.w[k] = 1.25 + (c - 1) * 1.75, 1.75
        else L.x0[k], L.w[k] = 1.5 + (c - 2), 1 end
      else
        if c == 1 then L.x0[k], L.w[k] = 0, 2
        elseif key == "SPACE" then L.x0[k], L.w[k] = 2, 5.5
        else L.x0[k], L.w[k] = 7.5, 2.5 end
      end
    end
  end
  LAYOUT[name] = L
end

local C = {
  ink = { 28, 28, 30 }, soft = { 112, 112, 120 }, faint = { 160, 160, 170 }, white = { 255, 255, 255 },
  accent = { 10, 132, 255 }, grey = { 206, 210, 220 }, shade = { 0, 0, 0, 0.13 }, full = { 255, 59, 48 },
}

return function(K, T)
  local Kb = {}
  local word = T or function(k) return k end
  local countT = K.textCache(function(k) return tostring(floor(k / 100)) .. " / " .. tostring(k % 100) end)

  function Kb.len(kb)
    local _, n = kb.text:gsub(UTF8, "")
    return n
  end
  function Kb.new(text, maxLen)
    local kb = { text = tostring(text or ""), max = tonumber(maxLen) or 10, page = "upper", cur = 1,
                 typedK = nil, typedAt = -1 }
    if kb.text ~= "" then kb.page = "lower" end
    kb.cur = LAYOUT[kb.page].first[2]
    return kb
  end
  function Kb.layout(kb) return LAYOUT[kb.page] end
  function Kb.keys(kb) return #LAYOUT[kb.page].keys end

  -- (the cursor kept on the same row and place when the page changes under it)
  local function setPage(kb, page)
    local from = LAYOUT[kb.page]
    local r, mid = from.row[kb.cur] or 2, (from.x0[kb.cur] or 0) + (from.w[kb.cur] or 1) / 2
    kb.page = page
    local L = LAYOUT[page]
    r = min(r, #ROWS[page])
    local best, bestD = L.first[r], nil
    for j = L.first[r], L.first[r] + L.count[r] - 1 do
      local d = abs(L.x0[j] + L.w[j] / 2 - mid)
      if not bestD or d < bestD then best, bestD = j, d end
    end
    kb.cur = best
  end

  function Kb.back(kb, clock)
    if kb.text == "" then return "empty" end
    kb.text = kb.text:gsub(LAST, "")
    kb.typedAt = clock or 0
    local L = LAYOUT[kb.page]
    for k = 1, #L.keys do if L.keys[k] == "DEL" then kb.typedK = k end end
    if kb.text == "" and kb.page == "lower" then setPage(kb, "upper") end
    return "deleted"
  end
  function Kb.toggle(kb)
    setPage(kb, kb.page == "upper" and "lower" or (kb.page == "lower" and "marks" or "upper"))
  end
  function Kb.toOk(kb)
    local L = LAYOUT[kb.page]
    kb.cur = L.first[#ROWS[kb.page]] + L.count[#ROWS[kb.page]] - 1
  end

  function Kb.type(kb, k, clock)
    local L = LAYOUT[kb.page]
    local key = L.keys[k]
    if not key then return nil end
    kb.cur, kb.typedK, kb.typedAt = k, k, clock or 0
    if key == "OK" then return "ok" end
    if key == "DEL" then return Kb.back(kb, clock) end
    if key == "SHIFT" then
      setPage(kb, kb.page == "upper" and "lower" or "upper")
      return "page"
    end
    if key == "MARKS" then setPage(kb, "marks") return "page" end
    if key == "ABC" then setPage(kb, kb.text == "" and "upper" or "lower") return "page" end
    if Kb.len(kb) >= kb.max then return "full" end
    if key == "SPACE" then
      if kb.text == "" or kb.text:sub(-1) == " " then return "full" end
      kb.text = kb.text .. " "
      return "typed"
    end
    kb.text = kb.text .. key
    -- (the first capital typed: small letters after it)
    if kb.page == "upper" and Kb.len(kb) == 1 then setPage(kb, "lower") end
    return "typed"
  end

  function Kb.nav(kb, dx, dy)
    local L = LAYOUT[kb.page]
    local k = kb.cur
    local r = L.row[k]
    if dx ~= 0 then
      local f, n = L.first[r], L.count[r]
      kb.cur = f + (k - f + dx) % n
      return
    end
    local rows = #ROWS[kb.page]
    local r2 = (r - 1 + dy) % rows + 1
    local mid = L.x0[k] + L.w[k] / 2
    local best, bestD = L.first[r2], nil
    for j = L.first[r2], L.first[r2] + L.count[r2] - 1 do
      local d = abs(L.x0[j] + L.w[j] / 2 - mid)
      if not bestD or d < bestD then best, bestD = j, d end
    end
    kb.cur = best
  end

  -- (the sheet: the field over four rows of keys)
  local function sizes()
    local g = K.textScale() - 1
    return 9 + g * 3, 1.8, 12 + g * 3
  end
  function Kb.height(w)
    local kh, gap, fh = sizes()
    return 3 + fh + 3 + 4 * kh + 3 * gap + 3
  end

  -- (Delete: an arrow to the left with a cross in it; Shift: an arrow up, filled on capitals)
  local function backspace(cx, cy, s, c)
    local G = K.graphics()
    K.col(c)
    G.setLineWidth(max(1, 0.45 * K.sc))
    local x1, x2, y1, y2 = K.X(cx - s * 1.2), K.X(cx + s * 1.2), K.Y(cy - s), K.Y(cy + s)
    local xm = K.X(cx - s * 0.45)
    G.line(x1, K.Y(cy), xm, y1, x2, y1, x2, y2, xm, y2, x1, K.Y(cy))
    local q = s * 0.4
    G.line(K.X(cx - q + s * 0.25), K.Y(cy - q), K.X(cx + q + s * 0.25), K.Y(cy + q))
    G.line(K.X(cx + q + s * 0.25), K.Y(cy - q), K.X(cx - q + s * 0.25), K.Y(cy + q))
  end
  local function shiftArrow(cx, cy, s, c, filled)
    local G = K.graphics()
    K.col(c)
    G.setLineWidth(max(1, 0.45 * K.sc))
    local mode = filled and "fill" or "line"
    G.polygon(mode, K.X(cx), K.Y(cy - s), K.X(cx + s), K.Y(cy), K.X(cx + s * 0.45), K.Y(cy),
      K.X(cx + s * 0.45), K.Y(cy + s), K.X(cx - s * 0.45), K.Y(cy + s), K.X(cx - s * 0.45), K.Y(cy),
      K.X(cx - s), K.Y(cy))
  end

  -- the sheet at x, y, w wide (the field, then the keys) -> its height
  function Kb.draw(kb, x, y, w, clock, hit, okWord, place)
    local G = K.graphics()
    local kh, gap, fh = sizes()
    local h = Kb.height(w)
    local sb = K.R(x, y, w, h)
    K.glass(sb, 6, 0.95)
    K.addHit(sb, "win", 0)
    -- (the field: the name and a blinking caret, the count at its right, red when full)
    local fb = K.R(x + 3, y + 3, w - 6, fh)
    K.col(C.white, 0.92)
    K.box("fill", fb, fh / 2)
    K.ring(fb, fh / 2, C.accent, 0.9, 0.6)
    local ts = 5.2
    local tx, ty = fb[1] + 6, fb[2] + (fh - ts * 1.2) / 2
    local tw = 0
    if kb.text == "" then
      if place then K.text(place, tx, ty, K.fit(place, ts, fb[3] - 30), C.faint) end
    else
      K.bold(kb.text, tx, ty, ts, C.ink)
      tw = K.width(kb.text, ts) + 0.4
    end
    if floor(clock * 2.2) % 2 == 0 then
      K.col(C.accent)
      G.rectangle("fill", K.X(tx + tw + 0.3), K.Y(ty), max(1, 0.5 * K.sc), ts * 1.2 * K.sc)
    end
    local n = Kb.len(kb)
    K.text(countT(n * 100 + kb.max), fb[1], fb[2] + (fh - 4 * 1.2) / 2, 4, n >= kb.max and C.full or C.soft,
      "right", fb[3] - 5)
    -- (the keys)
    local L = LAYOUT[kb.page]
    local ky0 = y + 3 + fh + 3
    local unit = (w - 6) / 10
    for k = 1, #L.keys do
      local key = L.keys[k]
      local kx = x + 3 + L.x0[k] * unit + 0.8
      local kw = L.w[k] * unit - 1.6
      local kyy = ky0 + (L.row[k] - 1) * (kh + gap)
      local kbx = K.R(kx, kyy, kw, kh)
      local ok = key == "OK"
      K.col(C.shade)
      K.box("fill", K.R(kx, kyy + 0.5, kw, kh), 2)
      if ok then K.col(C.accent)
      elseif SPECIAL[key] and not (key == "SHIFT" and kb.page == "upper") then K.col(C.grey)
      else K.col(C.white) end
      K.box("fill", kbx, 2)
      if kb.typedK == k and clock - kb.typedAt < 0.14 then
        K.col(C.accent, 0.35)
        K.box("fill", kbx, 2)
      end
      if k == kb.cur then K.ring(kbx, 2, C.accent, 1, 0.8) end
      local cx, cy = kx + kw / 2, kyy + kh / 2
      if key == "DEL" then
        backspace(cx, cy, kh * 0.28, C.ink)
      elseif key == "SHIFT" then
        shiftArrow(cx, cy, kh * 0.26, C.ink, kb.page == "upper")
      else
        local label, ls = key, 4.8
        if key == "SPACE" then label, ls = word("kb.space"), 4
        elseif ok then label, ls = okWord or word("kb.ok"), 4.4
        elseif key == "MARKS" then label, ls = "123", 4
        elseif key == "ABC" then label, ls = "ABC", 4 end
        local fs = K.fit(label, ls, kw - 2)
        K.text(label, kx, kyy + (kh - fs * 1.2) / 2, fs, ok and C.white or C.ink, "center", kw)
      end
      if hit then K.addHit(kbx, "win", hit + k) end
    end
    return h
  end

  return Kb
end
