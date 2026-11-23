-- The 3D map's objectives card (src/map3d/objectives.lua the lists): in the map's own frosted glass, beside the
-- place's card or above it, the place's entries under their headings -- Story, Gyms, Key items, People, Shops --
-- each with a box ticked once done (shops and most people have none), a story moment not reached yet as "???"
-- while spoilers are off. A wide card flows its entries into columns; too long for it, the entries without a box
-- (shops, most people) run on together a line at a time (V.fit); "+N more" when it still can't hold them.
-- Nothing made while drawing (the words are the list's, made when it is).
--
--   V = ObjectivesView(K, T)
--   V.height(list, w, maxH) -> the card's height for the list at that width ; V.draw(list, x, y, w, h, clock, glass)
--   V.fit(list, w, maxH) -> the list to draw in that room (made when the list or the room changes)
--   (glass(b, rad): the map's own glass)

local floor, max, min = math.floor, math.max, math.min

local HEAD = { story = "map.obj.h.story", gym = "map.obj.h.gym", key = "map.obj.h.key", people = "map.obj.h.people",
               shop = "map.obj.h.shop" }
local C = { white = { 255, 255, 255 }, text = { 238, 242, 250 }, faint = { 165, 174, 194 }, box = { 255, 255, 255, 0.6 },
            done = { 52, 199, 89 }, head = { 150, 196, 255 } }
local ROW, HEAD_H, PAD, TITLE = 4.9, 4.6, 3.2, 6
local COL_W = 70

return function(K, T)
  local V = {}
  local moreT = K.textCache(function(n) return T.f("map.obj.more", n) end)

  local function rowH() return ROW + (K.textScale() - 1) * 1.6 end
  local function headH() return HEAD_H + (K.textScale() - 1) * 1.4 end
  local function cols(w) return max(1, floor((w - PAD * 2) / COL_W)) end
  -- (the height of the lines: a heading each time the kind changes)
  local function linesH(list)
    local hh, last = 0, nil
    for _, e in ipairs(list) do
      if e.kind ~= last then hh, last = hh + headH(), e.kind end
      hh = hh + rowH()
    end
    return hh
  end
  local function wantH(list, w)
    local per = linesH(list) / cols(w)
    -- (columns break between entries: a row's worth of slack each)
    return PAD * 2 + TITLE + per + (cols(w) > 1 and rowH() + headH() or 0)
  end
  function V.height(list, w, maxH) return min(maxH, wantH(list, w)) end

  -- (too long for the card: a heading's entries without a box run on together, " · " between, a line as far as
  -- the column goes; the ones with a box stay a line each)
  local SEP = " · "
  function V.fit(list, w, maxH)
    if wantH(list, w) <= maxH then return list end
    local out = {}
    local room = (w - PAD * 2) / cols(w) - 2 - 4.4 - 1
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
          if line and K.width(try, 3.5) > room then
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
    return out
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

  function V.draw(list, x, y, w, h, clock, glass)
    local G = K.graphics()
    local row, hh = rowH(), headH()
    if glass then glass(K.R(x, y, w, h), 6) else K.glass(K.R(x, y, w, h), 6, 0.6) end
    local title = T("map.obj.title")
    K.bold(title, x + PAD + 1, y + PAD - 0.6, K.fit(title, 4.4, w - PAD * 2), C.white)
    local n = cols(w)
    local cw = (w - PAD * 2) / n
    local top, foot = y + PAD + TITLE, y + h - PAD
    local col, yy = 1, top
    local last = nil
    local total = #list
    for i, e in ipairs(list) do
      local need = row + ((e.kind ~= last or yy == top) and hh or 0)
      -- (full: the next column, its heading again; the last column keeps a line for "+N more")
      local spare = (col == n and i < total) and row or 0
      if yy + need + spare > foot and col < n then
        col, yy, last = col + 1, top, nil
        need = row + hh
        spare = (col == n and i < total) and row or 0
      end
      if yy + need + spare > foot then
        K.text(moreT(total - i + 1), x + PAD + 1 + (col - 1) * cw, yy + 0.4, 3.4, C.faint)
        return
      end
      local cx = x + PAD + 1 + (col - 1) * cw
      if e.kind ~= last or yy == top then
        last = e.kind
        K.text(T(HEAD[e.kind] or HEAD.shop), cx, yy + 0.2, 3.1, C.head)
        yy = yy + hh
      end
      local tx = cx
      if e.done ~= nil then
        box(tx, yy + 0.5, 3.6, e.done)
        tx = tx + 5.4
      else
        -- (a run-on line's next: no dot of its own)
        if not e.cont then
          K.col(C.faint)
          G.circle("fill", K.X(tx + 1.5), K.Y(yy + 2.4), max(1, 0.7 * K.sc))
        end
        tx = tx + 4.4
      end
      local label = e.hidden and "???" or e.label
      local ls = K.fit(label, 3.5, cx + cw - 2 - tx)
      K.text(label, tx, yy + (row - ls * 1.25) / 2 - 0.3, ls, (e.hidden or e.done) and C.faint or C.text)
      yy = yy + row
    end
  end

  return V
end
