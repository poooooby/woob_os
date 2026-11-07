-- WoobWatch: the PC's apps on the player's wrist, opened from the game's START menu (or a tap on a
-- notification) anywhere the START menu opens. A smartwatch over the field (dimmed behind it): a
-- dark case, a digital crown and a side button, the band off the window's edges. Its screens:
--   face   the time, the date, the player's money and name, the apps' complications (R-Bay's bids,
--          the GTS deposit, Slots' tickets), a red dot while notifications are unread
--          A or a tap: the apps ; Down or a swipe down: the notifications (a swipe up back) ; B closes the watch
--   grid   the apps as round icons in a honeycomb (the focused one's name in the status bar)
--          the D-pad moves, L / R or the wheel turn the crown, A opens, B the face
--   app    an app's own window (src/apps.lua's contract, the desktop's) under the status bar
--          (its name, the time); the app takes the buttons first, a B it leaves alone (or a tap on
--          the name) goes back to the apps
--   notes  the notifications, newest first; A (or a tap) opens one's app at it, B the face
-- A notification arriving while the watch is open slides down over its screen (a tap opens it).
--
--   Wt = watch(deps)   deps: kit ; apps ; T ; se(name) ; now() ; session() ; env (handed to the
--                      windows) ; clock() -> hour, minute, day, weekday (1 = Sunday) ; options() ->
--                      { clock24 } ; glyph(G, kind, cx, cy, size, a) ; amount(n, x, y, size, c) ;
--                      labelOf(app) ; notify (src/notify.lua) ; log(fmt, ...)
--   Wt.open(ctx) (ctx: src/shell.lua's, ctx.resume = { app, state } opens that app at once) ;
--   Wt.close() ; Wt.isOpen() ; Wt.input(input) ; Wt.pointer(ev) -> true ; Wt.wheel(dy) ;
--   Wt.draw(G, vp) ; Wt.state() ; Wt.window() ; Wt.launch(i) ; Wt.openApp(id, state) ; Wt.pulse()

local floor, max, min, abs, sqrt = math.floor, math.max, math.min, math.abs, math.sqrt

local W = {}
W.PAGE = { height = 300, minWidth = 216, maxWidth = 216, portraitWidth = 216, portraitHeight = 300, portraitAspect = 99 }
-- the case, its screen (inset), the screen's corners, the status bar (units)
W.CASE = { w = 196, h = 244, top = 22, inset = 10, radius = 34 }
W.SCREEN_RADIUS = 24
W.STATUS = 14
-- the honeycomb: an icon's size, the room between rows, between icons in a row
W.HONEY = { icon = 40, pitch = 37, gap = 50 }
W.ZOOM = 0.22
-- the apps' windows drawn this much bigger than on the PC (a watch's few large rows, not a
-- phone's many): the window lays out in a body this many times smaller (units)
W.APP_ZOOM = 1.5
W.REPEAT_START, W.REPEAT_EVERY = 20, 4

local C = {
  dim = { 0, 0, 0 }, caseTop = { 74, 78, 92 }, caseFoot = { 26, 27, 34 }, caseEdge = { 132, 138, 156 },
  bandTop = { 40, 42, 52 }, bandFoot = { 22, 23, 30 }, bandHole = { 10, 10, 14 },
  crownTop = { 190, 194, 206 }, crownFoot = { 92, 96, 110 }, crownRing = { 255, 70, 60 },
  screen = { 0, 0, 0 }, screenFoot = { 12, 13, 20 }, ink = { 255, 255, 255 }, soft = { 150, 152, 166 },
  faint = { 90, 92, 104 }, accent = { 255, 69, 58 }, good = { 52, 199, 89 }, gold = { 255, 196, 60 },
  tile = { 28, 29, 36 }, tileHi = { 44, 46, 56 }, dot = { 255, 59, 48 }, glass = { 255, 255, 255, 0.07 },
  clear = { 255, 255, 255, 0 }, keyFill = { 70, 72, 84 },
  -- (over the face's wallpaper: darker toward the foot, so the time and the tiles read)
  shadeTop = { 0, 0, 0, 0.5 }, shadeFoot = { 0, 0, 0, 0.62 },
  classicTop = { 116, 144, 232 }, classicFoot = { 58, 48, 140 },
}
W.C = C

local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

local HINTS = {
  face = { { "A", "hint.open" }, { "v", "watch.hintNotes" }, { "B", "hint.close" } },
  grid = { { "A", "hint.open" }, { "L R", "watch.hintCrown" }, { "B", "watch.hintFace" } },
  notes = { { "A", "hint.open" }, { "B", "watch.hintFace" } },
  window = { { "B", "hint.close" } },
}
local ANY_KEY = { "a", "b", "start", "select", "l", "r", "up", "down", "left", "right" }
local COMPS = { "auction", "gts", "slots", "mart" }

return function(deps)
  local K = deps.kit
  local T = deps.T or NO_T
  local Wt = { PAGE = W.PAGE, CASE = W.CASE, HONEY = W.HONEY, ZOOM = W.ZOOM, C = C }
  local WHITE, BLACK = K.WHITE, K.BLACK
  local repeated = K.repeater(W.REPEAT_START, W.REPEAT_EVERY)
  local Nt = deps.notify

  local function now() return deps.now and deps.now() or 0 end
  local function se(name) if deps.se then pcall(deps.se, name) end end
  local function labelOf(app) return deps.labelOf and deps.labelOf(app) or app.label end
  local function log(fmt, ...) if deps.log then deps.log(fmt, ...) end end

  local r = nil   -- the open watch

  -- ------- open / close

  -- the honeycomb's places: rows of three, then two between them (units from the grid's top middle)
  local function placeIcons(apps)
    local H = W.HONEY
    local pos, rows = {}, {}
    local row, inRow, y = 1, 0, 0
    for i = 1, #apps do
      local size = row % 2 == 1 and 3 or 2
      if inRow >= size then
        row, inRow, y = row + 1, 0, y + H.pitch
        size = row % 2 == 1 and 3 or 2
      end
      inRow = inRow + 1
      pos[i] = { x = 0, y = y, row = row }
      rows[row] = rows[row] or { first = i, n = 0, size = size }
      rows[row].n = rows[row].n + 1
    end
    for _, rw in pairs(rows) do
      for j = 1, rw.n do
        local i = rw.first + j - 1
        pos[i].x = (j - (rw.n + 1) / 2) * H.gap
      end
    end
    return pos, rows, row
  end

  local function appIndex(id)
    for i, app in ipairs(r.apps) do if app.id == id then return i end end
    return nil
  end

  function Wt.open(ctx)
    ctx = ctx or {}
    local apps = {}
    for _, app in ipairs(deps.apps.list(ctx)) do
      if app.watch ~= false and app.window then apps[#apps + 1] = app end
    end
    local pos, rows, nRows = placeIcons(apps)
    r = { ctx = ctx, apps = apps, pos = pos, rows = rows, nRows = nRows, screen = "face", cursor = 1,
          scroll = 0, noteCursor = 1, noteTop = 0, t0 = now(), held = {}, hit = K.hits, waitRelease = true,
          comp = { lead = 0, out = 0, bids = 0, gts = "none", tickets = 0, money = 0, at = -1 },
          clock = { key = nil, at = -1, text = "", date = "" } }
    local resume = ctx.resume
    if resume and resume.app then
      local i = appIndex(resume.app)
      if i then
        r.cursor = i
        r.resumeApp = apps[i]
      end
    end
    return true
  end
  function Wt.close()
    if not r then return end
    local w = r.win
    r = nil
    if w and w.close then pcall(w.close) end
  end
  function Wt.isOpen() return r ~= nil end
  function Wt.state() return r end
  function Wt.window() return r and r.win end
  -- a Pokémon crossing (the desktop's pad): the crown's ring glows a moment instead
  function Wt.pulse() if r then r.pulseT = now() end end
  function Wt.padTransfer() Wt.pulse() end

  -- ------- the actions

  local function openWindow(app)
    r.ctx.app = app.id
    local ok, w = pcall(app.window, r.ctx, deps.env)
    if not (ok and type(w) == "table" and w.draw) then
      log("the app %s failed to open: %s", app.id, tostring(w))
      r.screen = "grid"
      return
    end
    r.win, r.winApp, r.winFailed, r.screen = w, app, false, "app"
  end
  local function closeWindow(silent)
    local w, app = r.win, r.winApp
    if not w then return end
    r.win, r.winApp = nil, nil
    if w.close then pcall(w.close) end
    r.screen = "grid"
    r.zoom = { app = app, i = appIndex(app.id) or r.cursor, t = now(), back = true }
    if not silent then se("SE_SELECT") end
  end
  Wt.closeWindow = function() if r then closeWindow() end end

  function Wt.launch(i)
    if not r or (r.zoom and not r.zoom.back) then return end
    local app = r.apps[i]
    if not app then return end
    r.cursor = i
    se("SE_SELECT")
    r.zoom = { app = app, i = i, t = now() }
  end
  -- an app at once (a notification's), with its state handed over as ctx.resume
  function Wt.openApp(id, state)
    if not r then return false end
    local i = appIndex(id)
    if not i then return false end
    if r.win then closeWindow(true) end
    r.zoom = nil
    r.cursor = i
    r.ctx.resume = state ~= nil and { app = id, state = state } or nil
    openWindow(r.apps[i])
    se("SE_SELECT")
    return true
  end
  local function openNote(i)
    local rec = Nt and Nt.list()[i]
    if not rec then return end
    Wt.openApp(rec.app, rec.state)
  end
  local function toScreen(s)
    if r.screen == s then return end
    r.screen = s
    if s == "notes" then
      r.noteCursor, r.noteTop = 1, 0
      if Nt then Nt.seen() end
    end
    se("SE_SELECT")
  end
  local function done()
    local ctx = r.ctx
    se("SE_SELECT")
    if ctx.done then ctx.done() else Wt.close() end
  end

  -- the honeycomb's cursor: along the list, or to the nearest icon in the row above / below
  local function moveTo(i)
    i = max(1, min(#r.apps, i))
    if i ~= r.cursor then
      r.cursor = i
      se("SE_SELECT")
    end
  end
  local function moveRow(d)
    local p = r.pos[r.cursor]
    if not p then return end
    local rw = r.rows[p.row + d]
    if not rw then return end
    local best, bestD = nil, math.huge
    for j = 1, rw.n do
      local i = rw.first + j - 1
      local dd = abs(r.pos[i].x - p.x)
      if dd < bestD then best, bestD = i, dd end
    end
    if best then moveTo(best) end
  end

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  local NAV = {}
  function Wt.input(input)
    if not (r and input) then return end
    cur = input
    if r.waitRelease then
      local okD, down = pcall(input.isDown, input, "a")
      if input:wasPressed("a") or (okD and down) then return end
      r.waitRelease = false
    end
    if r.zoom and not r.zoom.back then return end
    local held = r.held
    local up, down, left, right = repeated(input, "up", held), repeated(input, "down", held),
      repeated(input, "left", held), repeated(input, "right", held)
    if r.win then
      NAV.up, NAV.down, NAV.left, NAV.right = up, down, left, right
      local ok, used = pcall(r.win.input, input, NAV)
      if not ok then log("the window's input failed: %s", tostring(used)) end
      if ok and used then return end
      if pressed("b") then return closeWindow() end
      return
    end
    if r.screen == "face" then
      if pressed("a") then return toScreen("grid") end
      if pressed("b") then return done() end
      if down or pressed("select") then return toScreen("notes") end
      if left or right then return toScreen("grid") end
      return
    end
    if r.screen == "notes" then
      local n = Nt and #Nt.list() or 0
      if pressed("b") or (up and r.noteCursor <= 1) then return toScreen("face") end
      if pressed("a") then return openNote(r.noteCursor) end
      if up and r.noteCursor > 1 then
        r.noteCursor = r.noteCursor - 1
        se("SE_SELECT")
      elseif down and r.noteCursor < n then
        r.noteCursor = r.noteCursor + 1
        se("SE_SELECT")
      end
      return
    end
    -- the apps
    if pressed("b") then return toScreen("face") end
    if pressed("a") then return Wt.launch(r.cursor) end
    if pressed("l") then return moveTo(r.cursor - 1) end
    if pressed("r") then return moveTo(r.cursor + 1) end
    if left then moveTo(r.cursor - 1)
    elseif right then moveTo(r.cursor + 1)
    elseif up then moveRow(-1)
    elseif down then moveRow(1)
    end
  end

  function Wt.wheel(dy)
    if not r then return false end
    if r.win then
      if r.win.scroll then pcall(r.win.scroll, dy * 10, r.mouseX, r.mouseY) end
    elseif r.screen == "grid" then
      moveTo(r.cursor + (dy > 0 and -1 or 1))
    elseif r.screen == "notes" then
      local n = Nt and #Nt.list() or 0
      r.noteCursor = max(1, min(n, r.noteCursor + (dy > 0 and -1 or 1)))
    elseif dy < 0 then
      toScreen("notes")
    end
    return true
  end

  -- ------- touch and mouse

  local function hitAt(x, y)
    local hits = r.hit
    for i = #hits, 1, -1 do
      local h = hits[i]
      if K.inside(h, x, y) then return h end
    end
    return nil
  end
  local function tap(x, y)
    local h = hitAt(x, y)
    if not h then return false end
    local kind, arg = h.kind, h.arg
    if kind == "wface" then toScreen("grid")
    elseif kind == "wcomp" then
      local i = appIndex(COMPS[arg])
      if i then Wt.launch(i) end
    elseif kind == "wgrid" then
      if arg == r.cursor then Wt.launch(arg) else moveTo(arg) end
    elseif kind == "wbell" then toScreen("notes")
    elseif kind == "wnote" then
      r.noteCursor = arg
      openNote(arg)
    elseif kind == "wback" then
      if r.win then closeWindow() elseif r.screen == "grid" or r.screen == "notes" then toScreen("face") end
    elseif kind == "wbanner" then
      local rec = Nt and Nt.showing()
      if Nt then Nt.dismiss() end
      if rec then Wt.openApp(rec.app, rec.state) end
    elseif kind == "win" then
      if r.win and r.win.tap then
        local ok, err = pcall(r.win.tap, arg, x, y)
        if not ok then log("the window's tap failed: %s", tostring(err)) end
      end
    end
    return true
  end
  Wt.tap = function(x, y) return r ~= nil and tap(x, y) end

  -- (window pixels to the window's own units: its zoomed transform, as last drawn)
  local function winUnits(x, y)
    local t = r.winT
    if not t then return (x - K.ox) / K.sc, (y - K.oy) / K.sc end
    return (x - t[2]) / t[1], (y - t[3]) / t[1]
  end
  local function winScale() return r.winT and r.winT[1] or K.sc end
  local function winPointer(phase, x, y, id)
    local w = r.win
    if not (w and w.pointer) then return false end
    local ux, uy = winUnits(x, y)
    local ok, used = pcall(w.pointer, phase, ux, uy, id)
    if not ok then log("the window's pointer failed: %s", tostring(used)) end
    return ok and used == true
  end

  function Wt.pointer(ev)
    if not (r and type(ev) == "table") then return false end
    local x, y = tonumber(ev.x) or 0, tonumber(ev.y) or 0
    local press = r.press
    -- (a second finger while a window has the first: the window's too, by its id -- the map's pinch)
    if press and press.own and ev.id ~= press.id and r.win and r.win.pointer then
      if ev.phase == "pressed" or ev.phase == "moved" or ev.phase == "released" or ev.phase == "cancelled" then
        press.drag = true
        winPointer(ev.phase, x, y, ev.id)
      end
      return true
    end
    if ev.phase == "pressed" then
      local wa = r.winArea
      r.press = { id = ev.id, x = x, y = y, ly = y, drag = false,
                  win = r.win ~= nil and wa ~= nil and K.inside(wa, x, y) }
      if r.press.win and r.win.pointer and not (Nt and Nt.showing() and hitAt(x, y) and hitAt(x, y).kind == "wbanner") then
        r.press.own = true
        winPointer("pressed", x, y, ev.id)
      end
    elseif ev.phase == "moved" then
      r.mouseX, r.mouseY = x, y
      if press and press.id == ev.id then
        local far = abs(y - press.y) > 4 * K.sc or abs(x - press.x) > 4 * K.sc
        if press.own then
          if far then press.drag = true end
          winPointer("moved", x, y, ev.id)
        elseif press.win and (press.drag or far) then
          press.drag = true
          if r.win and r.win.scroll then pcall(r.win.scroll, (y - press.ly) / winScale(), press.x, press.y) end
          press.ly = y
        elseif far then
          press.drag = true
          local dy = (y - press.ly) / K.sc
          if r.screen == "grid" then
            r.scroll = r.scroll - dy
          elseif r.screen == "notes" then
            r.noteTop = max(0, r.noteTop - dy / 32)
          end
          press.ly = y
        end
      elseif not press and r.win and r.win.pointer and r.winArea and K.inside(r.winArea, x, y) then
        winPointer("hover", x, y, ev.id)
      end
    elseif ev.phase == "released" then
      if press and press.id == ev.id then
        r.press = nil
        if press.own then
          if not winPointer("released", x, y, ev.id) and not press.drag then tap(x, y) end
        elseif press.drag then
          -- (the face pulled down: the notifications, as a watch's; pushed back up: the face)
          local dy = (y - press.y) / K.sc
          if r.screen == "face" and dy > 24 then toScreen("notes")
          elseif r.screen == "notes" and dy < -40 and r.noteEnd then toScreen("face") end
          if r.screen == "grid" then
            -- (the cursor follows to the icon nearest the middle)
            local mid = r.scroll
            local best, bestD = r.cursor, math.huge
            for i, p in ipairs(r.pos) do
              local dd = abs(p.y - mid) + abs(p.x) * 0.2
              if dd < bestD then best, bestD = i, dd end
            end
            r.cursor = best
          end
        else
          tap(x, y)
        end
      end
    elseif ev.phase == "cancelled" then
      if press and press.id == ev.id then
        if press.own then winPointer("cancelled", x, y, ev.id) end
        r.press = nil
      end
    end
    return true
  end

  -- ------- drawing

  local clockText = K.textCache(function(key)
    local h, m = floor(key / 100) % 100, key % 100
    if key >= 10000 then return string.format("%d:%02d", h, m) end
    local h12 = h % 12
    if h12 == 0 then h12 = 12 end
    return string.format("%d:%02d", h12, m)
  end)
  local dateText = K.textCache(function(key)
    local wd, day = floor(key / 100), key % 100
    return T.f("watch.date", T("watch.wd" .. wd), day)
  end)
  local numText = K.textCache(function(n) return tostring(n) end)
  local ticketsText = K.textCache(function(n) return T.f("watch.tickets", n) end)
  local bidsText = K.textCache(function(key)
    local lead, out = floor(key / 100), key % 100
    if lead + out == 0 then return T("watch.noBids") end
    if out == 0 then return T.f("watch.leading", lead) end
    if lead == 0 then return T.f("watch.outbid", out) end
    return T.f("watch.leadOut", lead, out)
  end)

  -- the time and the date, read once a second (the engine's reading makes a table)
  local function readClock(clock)
    local c = r.clock
    if clock - c.at < 1 and c.key then return c end
    c.at = clock
    local ok, h, m, day, wd = pcall(deps.clock or function() return nil end)
    if ok and tonumber(h) and tonumber(m) then
      local o = deps.options and deps.options() or {}
      c.key = floor(h) * 100 + floor(m) + (o.clock24 and 10000 or 0)
      c.text = clockText(c.key)
      c.date = (tonumber(day) and tonumber(wd)) and dateText(floor(wd) * 100 + floor(day)) or ""
      c.pm = not o.clock24 and floor(h) >= 12
    else
      c.key, c.text, c.date = false, "", ""
    end
    return c
  end
  -- the complications, once a second: R-Bay's bids (leading / outbid), the GTS deposit, the tickets
  local function readComps(clock)
    local c = r.comp
    if clock - c.at < 1 and c.at >= 0 then return c end
    c.at = clock
    local env = deps.env or {}
    local s = deps.session and deps.session()
    c.money = s and max(0, floor(tonumber(s.money) or 0)) or 0
    c.lead, c.out = 0, 0
    if env.auction and s then
      local ok, rows = pcall(env.auction.listings, s)
      if ok and type(rows) == "table" then
        for _, L in ipairs(rows) do
          if L.mine then
            if L.leader == 0 then c.lead = c.lead + 1 else c.out = c.out + 1 end
          end
        end
      end
    end
    c.gts = "none"
    if env.gts then
      local dep = env.gts.posted()
      c.gts = dep and (dep.received and "traded" or "waiting") or "none"
    end
    c.tickets = env.slots and tonumber(env.slots.tickets()) or 0
    return c
  end

  -- the band (behind the case, off the page's top and foot), the case, the crown and the button
  local function drawBody(L, clock)
    local G = K.graphics()
    local cb = L.case
    local bw = 128
    local bx = cb[1] + (cb[3] - bw) / 2
    K.grad(K.R(bx, -20, bw, cb[2] + 40), 10, C.bandFoot, C.bandTop)
    K.grad(K.R(bx, cb[2] + cb[4] - 20, bw, L.ph - cb[2] - cb[4] + 40), 10, C.bandTop, C.bandFoot)
    for i = 0, 3 do
      K.col(C.bandHole)
      local hy = cb[2] + cb[4] + 26 + i * 16
      if hy < L.ph - 4 then G.circle("fill", K.X(bx + bw / 2), K.Y(hy), 2.4 * K.sc) end
    end
    -- (the crown: ridged, its red ring glowing a moment when a Pokémon crosses)
    local cr = L.crown
    K.grad(cr, 2, C.crownTop, C.crownFoot)
    for i = 1, 6 do
      K.col(BLACK, 0.25)
      K.box("fill", K.R(cr[1] + 1, cr[2] + i * cr[4] / 7, cr[3] - 1.5, 0.5))
    end
    local pk = r.pulseT and max(0, 1 - (now() - r.pulseT) / 0.6) or 0
    K.col(C.crownRing, 0.75 + 0.25 * pk)
    K.box("fill", K.R(cr[1] - 1.2, cr[2] + cr[4] / 2 - 1.2, 1.4, 2.4))
    if pk > 0 then
      K.col(C.crownRing, 0.4 * pk)
      G.circle("fill", K.X(cr[1]), K.Y(cr[2] + cr[4] / 2), (3 + 5 * (1 - pk)) * K.sc)
    end
    K.grad(L.button, 1.6, C.crownTop, C.crownFoot)
    K.shadow(cb, W.CASE.radius, 3, 0.55)
    K.grad(cb, W.CASE.radius, C.caseTop, C.caseFoot)
    K.ring(cb, W.CASE.radius, C.caseEdge, 0.55, 0.6)
    K.grad(K.R(cb[1] + 3, cb[2] + 2, cb[3] - 6, cb[4] * 0.4), W.CASE.radius - 3, C.glass, C.clear)
    local sb = L.screen
    K.col(C.screen)
    K.box("fill", sb, W.SCREEN_RADIUS)
  end

  -- the status bar: the title (or the app's name, a chevron back) and the time
  local function drawStatus(L, clock, title, back, tint)
    local sb, st = L.screen, L.status
    local c = readClock(clock)
    local x = sb[1] + W.SCREEN_RADIUS * 0.55
    if back then
      K.chevron(x + 1.2, st[2] + st[4] / 2 + 0.5, 4.4, tint or C.accent, -1)
      K.addHit(K.R(sb[1], st[2] - 2, sb[3] * 0.6, st[4] + 2), "wback")
      x = x + 4.5
    end
    if title then
      local fs = K.fit(title, 5.4, sb[3] * 0.62 - (x - sb[1]))
      K.bold(title, x, st[2] + 4.2 + (5.4 - fs) * 0.5, fs, tint or C.ink)
    end
    K.bold(c.text, sb[1], st[2] + 4.2, 5.4, C.ink, "right", sb[3] - W.SCREEN_RADIUS * 0.55)
  end

  -- a complication: a tile with the app's round glyph and its line, tappable (opens the app)
  local function drawComp(i, b, appId, line, tint)
    local G = K.graphics()
    local app = deps.apps.byId(appId)
    K.col(C.tile)
    K.box("fill", b, 6)
    local s = b[4] - 7
    local cx, cy = b[1] + 3.5 + s / 2, b[2] + b[4] / 2
    if app then
      K.col(app.color)
      G.circle("fill", K.X(cx), K.Y(cy), s / 2 * K.sc)
      if deps.glyph then pcall(deps.glyph, G, app.glyph, K.X(cx), K.Y(cy), s * K.sc, 1) end
      K.text(labelOf(app), b[1] + s + 7, b[2] + 2.6, 3.6, C.soft, "left", b[3] - s - 9)
    end
    local fs = K.fit(line, 4.6, b[3] - s - 9)
    K.bold(line, b[1] + s + 7, b[2] + b[4] - fs * 1.2 - 2.4, fs, tint or C.ink)
    if app then K.addHit(b, "wcomp", i) end
  end
  -- the face's ground: the wallpaper chosen in Settings (as the desktop's: a picture or a drawn
  -- one; classic, the game's colours), shaded so the words read
  local function drawFaceWall(sb)
    local id = deps.wallpaper and deps.wallpaper() or "classic"
    local drawn = false
    if id ~= "classic" and deps.wall then
      local fit = deps.wallpaperFit and deps.wallpaperFit() or "fill"
      local ok, got = pcall(deps.wall.draw, id, K.X(sb[1]), K.Y(sb[2]), sb[3] * K.sc, sb[4] * K.sc,
        W.SCREEN_RADIUS * K.sc, fit)
      drawn = ok and got
    end
    if not drawn then
      if not r.wall then
        local top, foot
        if deps.wall then top, foot = deps.wall.tint(deps.gameId and deps.gameId() or "") end
        r.wall = { top or C.classicTop, foot or C.classicFoot }
      end
      K.grad(sb, W.SCREEN_RADIUS, r.wall[1], r.wall[2])
    end
    K.grad(sb, W.SCREEN_RADIUS, C.shadeTop, C.shadeFoot)
  end
  local function drawFace(L, clock)
    local sb = L.screen
    local x, y, w = sb[1] + 12, sb[2] + 12, sb[3] - 24
    local c = readClock(clock)
    local comp = readComps(clock)
    drawFaceWall(sb)
    K.addHit(K.R(sb[1], sb[2], sb[3], sb[4] * 0.55), "wface")
    -- (the date in red, the unread dot, the time big)
    K.bold(c.date, x, y + 2, 6, C.accent)
    if Nt and Nt.unread() > 0 then
      local G = K.graphics()
      K.col(C.dot, 0.75 + 0.25 * math.sin(clock * 4))
      G.circle("fill", K.X(sb[1] + sb[3] / 2), K.Y(sb[2] + 5), 2.4 * K.sc)
      K.addHit(K.R(sb[1] + sb[3] / 2 - 10, sb[2], 20, 12), "wbell")
    end
    local ts = 38
    K.bold(c.text, x, y + 12, ts, C.ink)
    if c.pm ~= nil and c.key and c.key < 10000 then
      K.bold(c.pm and "PM" or "AM", x + K.width(c.text, ts) + 3, y + 12 + ts * 0.62, 6, C.soft)
    end
    -- (who and their money)
    local s = deps.session and deps.session()
    local name = s and (s.playerName or s.name) or ""
    if type(name) ~= "string" then name = "" end
    local my = y + 12 + ts * 1.25
    if name ~= "" then K.bold(name, x, my, 6, C.soft) end
    if deps.amount then deps.amount(comp.money, x, my + 8.5, 7.5, C.gold) end
    -- (the party: each one's icon, its HP under it)
    local party = s and s.party
    local env = deps.env
    if type(party) == "table" and env and env.monIconOf then
      local G = K.graphics()
      local frame = floor(clock * 3) % 2
      local py, ps = my + 22, 20
      for i = 1, 6 do
        local mon = party[i]
        if type(mon) == "table" then
          local ix = x + (i - 1) * (ps + 6)
          env.monIconOf(mon, ix, py, ps, frame)
          local hp, mhp = tonumber(mon.hp) or 0, tonumber(mon.maxHp) or 0
          if mhp > 0 then
            local k = max(0, min(1, hp / mhp))
            K.col(C.tile)
            K.box("fill", K.R(ix + 2, py + ps + 1, ps - 4, 1.6), 0.8)
            K.col(k > 0.5 and C.good or (k > 0.2 and C.gold or C.accent))
            K.box("fill", K.R(ix + 2, py + ps + 1, (ps - 4) * k, 1.6), 0.8)
          end
          G.setColor(1, 1, 1, 1)
        end
      end
    end
    -- (the complications: two by two)
    local cw, ch = (w - 4) / 2, 24
    local cy = sb[2] + sb[4] - 14 - ch * 2 - 4
    drawComp(1, K.R(x, cy, cw, ch), COMPS[1], bidsText(min(99, comp.lead) * 100 + min(99, comp.out)),
      comp.out > 0 and C.accent or (comp.lead > 0 and C.good or nil))
    local g = comp.gts
    drawComp(2, K.R(x + cw + 4, cy, cw, ch), COMPS[2], T(g == "traded" and "watch.gtsTraded" or (g == "waiting" and "watch.gtsWaiting" or "watch.gtsNone")),
      g == "traded" and C.good or nil)
    drawComp(3, K.R(x, cy + ch + 4, cw, ch), COMPS[3], ticketsText(comp.tickets))
    drawComp(4, K.R(x + cw + 4, cy + ch + 4, cw, ch), COMPS[4], T("watch.shop"))
  end

  -- the honeycomb: the icons smaller toward the screen's top and foot (a fisheye), the focused one
  -- ringed; scrolled so the focused row sits mid-screen
  local function drawGrid(L, clock)
    local G = K.graphics()
    local sb, body = L.screen, L.body
    local H = W.HONEY
    local p = r.pos[r.cursor]
    if p and not (r.press and r.press.drag) then
      -- (all of them in view: centred; more: the focused row mid-screen)
      local span = (r.nRows - 1) * H.pitch
      local want = span + H.icon + 8 <= body[4] and span / 2 or max(0, min(span, p.y))
      r.scroll = r.scroll + (want - r.scroll) * min(1, (r.dt or 0.016) * 12)
    end
    local cx, cy = sb[1] + sb[3] / 2, body[2] + body[4] / 2 - 4
    K.scissor(body)
    local half = body[4] / 2
    for i, app in ipairs(r.apps) do
      local q = r.pos[i]
      local x, y = cx + q.x, cy + q.y - r.scroll
      local d = min(1, abs(y - cy) / (half + 10))
      local k = 1 - 0.45 * d * d
      if i == r.cursor then k = k * 1.08 end
      local s = H.icon * k
      if y + s / 2 > body[2] - 4 and y - s / 2 < body[2] + body[4] + 4 then
        K.col(app.color, 1 - 0.3 * d)
        G.circle("fill", K.X(x), K.Y(y), s / 2 * K.sc)
        K.col(WHITE, 0.16)
        G.arc("fill", K.X(x), K.Y(y), s / 2 * K.sc * 0.94, math.pi * 1.05, math.pi * 1.95)
        if deps.glyph then pcall(deps.glyph, G, app.glyph, K.X(x), K.Y(y), s * K.sc, 1 - 0.3 * d) end
        if i == r.cursor then
          K.col(WHITE, K.pulse())
          G.setLineWidth(max(1, 0.8 * K.sc))
          G.circle("line", K.X(x), K.Y(y), (s / 2 + 2.2) * K.sc)
        end
        local n = app.badgeN
        if n and n > 0 then
          local br = s * 0.15
          K.col(C.dot)
          G.circle("fill", K.X(x + s * 0.34), K.Y(y - s * 0.34), br * K.sc)
          K.text(numText(min(n, 99)), x + s * 0.34 - br, y - s * 0.34 - br * 0.62, br * 1.2, WHITE, "center", br * 2)
        end
        r.icon[i] = r.icon[i] or {}
        local ic = r.icon[i]
        ic[1], ic[2], ic[3] = x, y, s
        K.addHit(K.R(x - s / 2, y - s / 2, s, s), "wgrid", i, body)
      end
    end
    K.scissor(nil)
  end

  local function drawNotes(L, clock)
    local sb, body = L.screen, L.body
    local list = Nt and Nt.list() or {}
    local n = #list
    local x, w = sb[1] + 8, sb[3] - 16
    local rowH = 30
    if n == 0 then
      r.noteEnd = true
      K.text(T("watch.noNotes"), body[1], body[2] + body[4] / 2 - 4, 5, C.soft, "center", body[3])
      return
    end
    local vis = max(1, floor((body[4] - 4) / rowH))
    if r.noteCursor > r.noteTop + vis then r.noteTop = r.noteCursor - vis end
    if r.noteCursor <= r.noteTop then r.noteTop = r.noteCursor - 1 end
    r.noteTop = max(0, min(r.noteTop, max(0, n - vis)))
    -- (the list's foot in view: a push up goes back to the face)
    r.noteEnd = r.noteTop >= n - vis
    K.scissor(body)
    local first = floor(r.noteTop) + 1
    for i = first, min(n, first + vis) do
      local y = body[2] + 2 + (i - 1 - r.noteTop) * rowH
      local b = K.R(x, y, w, rowH - 3)
      Nt.drawCard(list[i], b, 1, Nt.ago(list[i]))
      if i == r.noteCursor then K.ring(b, 6, WHITE, K.pulse(), 0.7) end
      K.addHit(b, "wnote", i, body)
    end
    K.scissor(nil)
  end

  local zbody = { 0, 0, 0, 0 }
  local function drawWindow(L, clock)
    local body = L.body
    local wa = r.winArea or {}
    r.winArea = wa
    wa[1], wa[2], wa[3], wa[4] = K.X(body[1]), K.Y(body[2]), body[3] * K.sc, body[4] * K.sc
    -- (the windows' own grey ground, as the desktop's window has: their light cards read on it)
    K.col(K.UI.grouped)
    K.box("fill", body, 6)
    -- (zoomed: the body's top left the units' origin, each unit W.APP_ZOOM times bigger)
    local z = W.APP_ZOOM
    local t = r.winT or {}
    r.winT = t
    t[1], t[2], t[3] = K.sc * z, wa[1], wa[2]
    zbody[3], zbody[4] = body[3] / z, body[4] / z
    local psc, pox, poy = K.transform(t[1], t[2], t[3])
    K.scissor(zbody)
    local ok, err = pcall(r.win.draw, zbody, clock, true)
    K.scissor(nil)
    K.transform(psc, pox, poy)
    K.graphics().setColor(1, 1, 1, 1)
    if not ok and not r.winFailed then
      r.winFailed = true
      log("the window's draw failed: %s", tostring(err))
    end
  end

  -- an app growing out of its icon (k 0 the icon, 1 the screen), or back into it
  local function drawZoom(L, app, i, k)
    local G = K.graphics()
    local ic = r.icon[i]
    local sb = L.screen
    local fx, fy, fs = sb[1] + sb[3] / 2, sb[2] + sb[4] / 2, W.HONEY.icon
    if ic then fx, fy, fs = ic[1], ic[2], ic[3] end
    local e = k * k * (3 - 2 * k)
    local w = fs + (sb[3] - fs) * e
    local h = fs + (sb[4] - fs) * e
    local x = fx - fs / 2 + (sb[1] - (fx - fs / 2)) * e
    local y = fy - fs / 2 + (sb[2] - (fy - fs / 2)) * e
    local rad = fs / 2 + (W.SCREEN_RADIUS - fs / 2) * e
    K.col(app.color)
    K.box("fill", K.R(x, y, w, h), rad)
    if deps.glyph then pcall(deps.glyph, G, app.glyph, K.X(x + w / 2), K.Y(y + h / 2), fs * K.sc * (1 + e), 1 - e * 0.5) end
  end

  -- the screen's corners kept round over whatever's on it (the case's colour round them)
  local function drawCorners(L)
    local G = K.graphics()
    local sb = L.screen
    local rad = W.SCREEN_RADIUS
    -- (a ring from the corner's curve out to the square corner: only what lies past the curve)
    G.setLineWidth(rad * 0.46 * K.sc)
    K.col(C.caseFoot)
    local rr = rad * 1.21
    local x1, y1, x2, y2 = K.X(sb[1] + rad), K.Y(sb[2] + rad), K.X(sb[1] + sb[3] - rad), K.Y(sb[2] + sb[4] - rad)
    G.arc("line", "open", x1, y1, rr * K.sc, math.pi, math.pi * 1.5)
    G.arc("line", "open", x2, y1, rr * K.sc, math.pi * 1.5, math.pi * 2)
    G.arc("line", "open", x2, y2, rr * K.sc, 0, math.pi * 0.5)
    G.arc("line", "open", x1, y2, rr * K.sc, math.pi * 0.5, math.pi)
  end

  local function layout(pw, ph)
    local CS = W.CASE
    local L = { pw = pw, ph = ph }
    local cx = pw / 2
    local top = (ph - W.PAGE.portraitHeight) / 2 + CS.top
    L.case = { cx - CS.w / 2, top, CS.w, CS.h }
    local sb = { L.case[1] + CS.inset, top + CS.inset, CS.w - CS.inset * 2, CS.h - CS.inset * 2 }
    L.screen = sb
    L.status = { sb[1], sb[2] + 2, sb[3], W.STATUS }
    L.body = { sb[1] + 2, sb[2] + W.STATUS + 3, sb[3] - 4, sb[4] - W.STATUS - 8 }
    L.crown = { L.case[1] + CS.w - 1, top + 46, 7, 22 }
    L.button = { L.case[1] + CS.w - 1, top + 88, 4, 30 }
    L.hints = { cx - 96, top + CS.h + 4, 192, 10 }
    return L
  end
  Wt.layout = layout

  local layoutKey = {}
  function Wt.draw(g, vp)
    if not (r and g and vp) then return end
    local clock = now()
    local pw, ph = K.frame(g, vp, W.PAGE, clock - r.t0)
    -- (the field dimmed behind the watch: the whole window, as the kit measured it)
    g.setColor(0, 0, 0, 0.6)
    g.rectangle("fill", 0, 0, K.ww or 0, K.wh or 0)
    local L = layoutKey.L
    if not (L and layoutKey.pw == pw and layoutKey.ph == ph) then
      L = layout(pw, ph)
      layoutKey.L, layoutKey.pw, layoutKey.ph = L, pw, ph
    end
    r.layout, r.hit = L, K.hits
    r.icon = r.icon or {}
    r.dt = max(0, min(0.1, clock - (r.lastDraw or clock)))
    r.lastDraw = clock
    if r.resumeApp then
      local app = r.resumeApp
      r.resumeApp = nil
      openWindow(app)
    end
    -- (the icons' counts, once a second)
    if not r.badgeAt or clock - r.badgeAt >= 1 or clock < r.badgeAt then
      r.badgeAt = clock
      for _, app in ipairs(r.apps) do
        if app.badge then
          local ok, n = pcall(app.badge, r.ctx)
          app.badgeN = ok and tonumber(n) or 0
        end
      end
    end
    drawBody(L, clock)
    local screen = r.screen
    local z = r.zoom
    if r.win then
      drawStatus(L, clock, labelOf(r.winApp), true, r.winApp.color and K.light(r.winApp.color, 0.35))
      drawWindow(L, clock)
    elseif screen == "face" then
      drawFace(L, clock)
    elseif screen == "notes" then
      drawStatus(L, clock, T("watch.notes"), true)
      drawNotes(L, clock)
    else
      local app = r.apps[r.cursor]
      drawStatus(L, clock, app and labelOf(app) or "", false)
      drawGrid(L, clock)
    end
    local launch
    if z then
      local k = (now() - z.t) / W.ZOOM
      if k >= 1 then
        r.zoom = nil
        if not z.back then launch = z.app end
      else
        drawZoom(L, z.app, z.i, z.back and (1 - k) or k)
      end
    end
    -- (a notification arriving: down over the top of the screen)
    if Nt then
      local rec, k = Nt.step(clock, true)
      if rec then
        local sb = L.screen
        local b = K.R(sb[1] + 6, sb[2] + 4 - (1 - k) * 34, sb[3] - 12, 26)
        Nt.drawCard(rec, b, min(1, k * 1.5))
        K.addHit(b, "wbanner")
      end
    end
    drawCorners(L)
    local hints
    if r.win then
      local ok, got = true, nil
      if r.win.hints then ok, got = pcall(r.win.hints) end
      hints = ok and type(got) == "table" and got or T.list(HINTS.window)
    else
      hints = T.list(HINTS[screen] or HINTS.grid)
    end
    K.hints(hints, L.hints, C.ink, true, C.soft, C.keyFill)
    g.setColor(1, 1, 1, 1)
    if launch then openWindow(launch) end
  end

  return Wt
end
