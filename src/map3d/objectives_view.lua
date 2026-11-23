-- The 3D map's objectives card (src/map3d/objectives.lua the lists): in the map's own frosted glass, beside the
-- place's card or above it, the place's entries under their headings -- Story, Gyms, Key items, People, Shops --
-- each with a box ticked once done (shops and most people have none), a story moment not reached yet as "???"
-- while spoilers are off. A wide card flows its entries into columns. Every word stays inside the card: an entry
-- too long for its column goes on over the next lines (V.lines); too many for the card, the entries without a box
-- (shops, most people) run on together a line at a time (V.fit); and when it still can't hold them, "+N more" on a
-- button that opens the card wider and taller (the scene's).
-- Nothing made while drawing (the words are the list's, made when it is or when the room changes).
--
--   V = ObjectivesView(K, T)
--   V.lines(list, w) -> the list with every entry inside a column that wide (kept)
--   V.fit(list, w, maxH) -> the list to draw in that room ; V.height(list, w, maxH) -> the card's height for it
--   V.draw(list, x, y, w, h, clock, glass, hitArg) -> how many didn't fit ("+N more" drawn; the card's hit hitArg)
--   (glass(b, rad): the map's own glass)

local floor, max, min = math.floor, math.max, math.min

local HEAD = { story = "map.obj.h.story", gym = "map.obj.h.gym", key = "map.obj.h.key", people = "map.obj.h.people",
               shop = "map.obj.h.shop" }
local C = { white = { 255, 255, 255 }, text = { 238, 242, 250 }, faint = { 165, 174, 194 }, box = { 255, 255, 255, 0.6 },
            done = { 52, 199, 89 }, head = { 150, 196, 255 }, pill = { 255, 255, 255, 0.16 } }
local ROW, HEAD_H, PAD, TITLE = 4.9, 4.6, 3.2, 6
local COL_W = 70
local FS = 3.5
local BOX_IN, DOT_IN = 5.4, 4.4
-- (a card that holds them exactly: the draw (at the screen's place) and the measure (from the card's top) round apart)
local EPS = 0.05

return function(K, T)
  local V = {}
  local moreT = K.textCache(function(n) return T.f("map.obj.more", n) end)

  local function rowH() return ROW + (K.textScale() - 1) * 1.6 end
  local function headH() return HEAD_H + (K.textScale() - 1) * 1.4 end
  local function cols(w) return max(1, floor((w - PAD * 2) / COL_W)) end
  local function colW(w) return (w - PAD * 2) / cols(w) end
  -- (a column's room for an entry's words: after its box or its dot, short of the column's end)
  local function textRoom(w, boxed) return colW(w) - 2 - (boxed and BOX_IN or DOT_IN) - 1 end

  -- (the lines laid into columns as the draw does: a heading where the kind changes and atop each column) -> how
  -- many fit a card h tall (the last column keeping a line for "+N more" when some don't)
  local function packed(list, w, h)
    local row, hh = rowH(), headH()
    local n = cols(w)
    local top = PAD + TITLE
    local foot = h - PAD
    local col, yy, last = 1, top, nil
    local total = #list
    for i, e in ipairs(list) do
      local need = row + ((e.kind ~= last or yy == top) and hh or 0)
      local spare = (col == n and i < total) and row or 0
      if yy + need + spare > foot + EPS and col < n then
        col, yy, last = col + 1, top, nil
        need = row + hh
        spare = (col == n and i < total) and row or 0
      end
      if yy + need + spare > foot + EPS then return i - 1 end
      if e.kind ~= last or yy == top then last, yy = e.kind, yy + hh end
      yy = yy + row
    end
    return total
  end
  -- (the height that holds them all: from an even share of the columns up, a row at a time)
  local function wantH(list, w)
    local row, hh = rowH(), headH()
    local lines, last = 0, nil
    for _, e in ipairs(list) do
      if e.kind ~= last then lines, last = lines + hh, e.kind end
      lines = lines + row
    end
    local h = PAD * 2 + TITLE + lines / cols(w)
    for _ = 1, #list + 2 do
      if packed(list, w, h) >= #list then return h end
      h = h + row
    end
    return h
  end
  function V.height(list, w, maxH) return min(maxH, wantH(list, w)) end

  -- (a label's pieces: words with the space before them, and a word too long alone -- a line with no spaces too,
  -- Japanese -- character by character, joined with nothing)
  local function pieces(s, room, out, glue)
    local n = 0
    for word in s:gmatch("%S+") do
      local sp = n > 0 and " " or ""
      if K.width(word, FS) <= room then
        n = n + 1
        out[n], glue[n] = word, sp
      else
        local cur = ""
        for ch in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
          if cur ~= "" and K.width(cur .. ch, FS) > room then
            n = n + 1
            out[n], glue[n] = cur, sp
            cur, sp = ch, ""
          else
            cur = cur .. ch
          end
        end
        if cur ~= "" then
          n = n + 1
          out[n], glue[n] = cur, sp
        end
      end
    end
    return n
  end
  -- (every entry inside its column: one too long for it goes on over the next lines, under its words)
  local function wrap(list, w)
    local out
    local ps, gl = {}, {}
    for i, e in ipairs(list) do
      local label = e.hidden and "???" or tostring(e.label)
      local boxed = e.done ~= nil or e.boxed == true
      local room = textRoom(w, boxed)
      if K.width(label, FS) > room then
        if not out then
          out = {}
          for j = 1, i - 1 do out[j] = list[j] end
        end
        local n = pieces(label, room, ps, gl)
        local line, first = nil, true
        local faded = e.done == true or e.hidden or e.faded
        local function put()
          if first then
            out[#out + 1] = { kind = e.kind, label = line, done = e.done, cont = e.cont, boxed = e.boxed, faded = faded }
          else
            out[#out + 1] = { kind = e.kind, label = line, cont = true, boxed = boxed, faded = faded }
          end
          first = false
        end
        for j = 1, n do
          local try = line and (line .. gl[j] .. ps[j]) or ps[j]
          if line and K.width(try, FS) > room then
            put()
            line = ps[j]
          else
            line = try
          end
        end
        if line then put() end
      elseif out then
        out[#out + 1] = e
      end
    end
    return out or list
  end
  -- (kept: made again when the list, the width or the text size changes)
  local wrapOf, wrapW, wrapS, wrapped
  function V.lines(list, w)
    if wrapOf ~= list or wrapW ~= w or wrapS ~= K.textScale() then
      wrapOf, wrapW, wrapS = list, w, K.textScale()
      wrapped = wrap(list, w)
    end
    return wrapped
  end

  -- (too long for the card: a heading's entries without a box run on together, " · " between, a line as far as
  -- the column goes; the ones with a box stay a line each)
  local SEP = " · "
  function V.fit(list, w, maxH)
    local whole = V.lines(list, w)
    if wantH(whole, w) <= maxH then return whole end
    local out = {}
    local room = textRoom(w, false)
    local i, n = 1, #list
    while i <= n do
      local e = list[i]
      if e.done ~= nil or e.hidden then
        out[#out + 1] = e
        i = i + 1
      else
        local kind, line, cont = e.kind, nil, false
        while i <= n and list[i].kind == kind and list[i].done == nil and not list[i].hidden do
          local lab = tostring(list[i].label)
          local try = line and (line .. SEP .. lab) or lab
          if line and K.width(try, FS) > room then
            out[#out + 1] = { kind = kind, label = line, cont = cont }
            line, cont = lab, true
          else
            line = try
          end
          i = i + 1
        end
        if line then out[#out + 1] = { kind = kind, label = line, cont = cont } end
      end
    end
    return wrap(out, w)
  end

  -- (a box: ticked green once done, empty glass before)
  local function box(x, y, s, done)
    local G = K.graphics()
    if done then
      K.col(C.done)
      K.box("fill", K.R(x, y, s, s), s * 0.25)
      K.col(C.white)
      G.setLineWidth(max(1, s * 0.16 * K.sc))
      G.line(K.X(x + s * 0.22), K.Y(y + s * 0.52), K.X(x + s * 0.42), K.Y(y + s * 0.72), K.X(x + s * 0.78), K.Y(y + s * 0.28))
    else
      K.ring(K.R(x, y, s, s), s * 0.25, C.box, 1, max(0.3, s * 0.1))
    end
  end

  function V.draw(list, x, y, w, h, clock, glass, hitArg)
    local G = K.graphics()
    local row, hh = rowH(), headH()
    local card = K.R(x, y, w, h)
    if glass then glass(card, 6) else K.glass(card, 6, 0.6) end
    if hitArg then K.addHit(card, "win", hitArg) end
    local title = T("map.obj.title")
    K.bold(title, x + PAD + 1, y + PAD - 0.6, K.fit(title, 4.4, w - PAD * 2 - 2), C.white)
    local n = cols(w)
    local cw = colW(w)
    local top, foot = y + PAD + TITLE, y + h - PAD
    local col, yy = 1, top
    local last = nil
    local total = #list
    for i, e in ipairs(list) do
      local need = row + ((e.kind ~= last or yy == top) and hh or 0)
      -- (full: the next column, its heading again; the last column keeps a line for "+N more")
      local spare = (col == n and i < total) and row or 0
      if yy + need + spare > foot + EPS and col < n then
        col, yy, last = col + 1, top, nil
        need = row + hh
        spare = (col == n and i < total) and row or 0
      end
      if yy + need + spare > foot + EPS then
        -- (the rest on a button: the card opens wider and taller)
        local cx = x + PAD + 1 + (col - 1) * cw
        local words = moreT(total - i + 1)
        local fs = K.fit(words, 3.4, cw - 8)
        local pb = K.R(cx - 1, yy + 0.2, min(cw - 2, K.width(words, fs) + 7), row - 0.4)
        K.col(C.pill)
        K.box("fill", pb, pb[4] / 2)
        K.text(words, pb[1] + 2, pb[2] + (pb[4] - fs * 1.2) / 2, fs, C.text)
        K.chevron(pb[1] + pb[3] - 2.6, pb[2] + pb[4] / 2, 1.4, C.text, 1)
        return total - i + 1
      end
      local cx = x + PAD + 1 + (col - 1) * cw
      if e.kind ~= last or yy == top then
        last = e.kind
        local head = T(HEAD[e.kind] or HEAD.shop)
        K.text(head, cx, yy + 0.2, K.fit(head, 3.1, cw - 2), C.head)
        yy = yy + hh
      end
      local tx = cx
      if e.done ~= nil then
        box(tx, yy + 0.5, 3.6, e.done)
        tx = tx + BOX_IN
      elseif e.cont then
        -- (a line going on: under its words, no box or dot of its own)
        tx = tx + (e.boxed and BOX_IN or DOT_IN)
      else
        K.col(C.faint)
        G.circle("fill", K.X(tx + 1.5), K.Y(yy + 2.4), max(1, 0.7 * K.sc))
        tx = tx + DOT_IN
      end
      local label = e.hidden and "???" or e.label
      local ls = K.fit(label, FS, cx + cw - 2 - tx)
      local faded = e.hidden or e.done or e.faded
      K.text(label, tx, yy + (row - ls * 1.25) / 2 - 0.3, ls, faded and C.faint or C.text)
      yy = yy + row
    end
    return 0
  end

  return V
end
