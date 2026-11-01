-- The desktop: a monitor (an aluminium body, a black glass border, a chin with the W) whose screen
-- shows a home screen. A menu bar along the top (the W menu, the money, the clock), a grid of app
-- icons in pages, a dock along the foot. Buttons, touch and the mouse all drive it:
--   grid     D-pad moves (Up from the top row: the menu bar; Down from the bottom: the dock),
--            A opens, L / R change page, B asks to log off, START opens the W menu
--   dock     Left / Right, Up back to the grid, A opens
--   menubar  A opens the W menu, Down back to the grid
--   menu     Up / Down, A chooses, B / START close it
--   sheet    Left / Right choose, A answers, B cancels
--   touch    tap an icon, the W, a menu row, a sheet's button, the power button on the chin;
--            swipe the grid (or the mouse wheel) for the next page; the mouse highlights what it's over
-- It boots first (black, the W with a progress bar, the desktop fading up); any button or tap
-- skips to the desktop. Drawn over the whole window from render.hud (src/shell.lua), laid out for
-- its shape: landscape (a page 160 units tall) or portrait (180 units wide).
--
--   D = desktop(deps)
--   deps: kit (src/ui_kit.lua) ; apps (src/apps.lua) ; se(name) ; now() -> seconds ; session() ;
--         currency(G, x, y, px, rgba) / currencyWidth(px) (the game's Pokédollar sign) ;
--         clock() -> hour, minute ; options() -> { boot = bool, clock24 = bool } ; version ;
--         gameId() -> "firered" | "leafgreen" | "ruby" | "sapphire" | "emerald"
--   D.open(ctx) (ctx: src/apps.lua, plus warm = skip the boot, back = the app id to zoom back from)
--   D.close() ; D.isOpen() ; D.input(input) ; D.pointer(ev) -> true ; D.wheel(dy) ; D.draw(G, vp)
--   D.state() (tests) ; D.booting() ; D.skipBoot() ; D.launch(i) ; D.tap(x, y)

return function(deps)
  local K = deps.kit
  local floor, max, min, abs = math.floor, math.max, math.min, math.abs
  local D = {}
  local WHITE, BLACK = K.WHITE, K.BLACK
  local mix, light, dark, fade = K.mix, K.light, K.dark, K.fade

  -- the boot (seconds): the screen black, the W with its progress bar, the desktop fading up
  D.BOOT = { BLACK = 0.35, LOGO = 1.3, REVEAL = 0.45 }
  local function bootLength() return D.BOOT.BLACK + D.BOOT.LOGO + D.BOOT.REVEAL end
  D.PAGE = { height = 160, minWidth = 220, maxWidth = 300, portraitWidth = 180, portraitHeight = 300,
             portraitAspect = 1.15 }
  -- a home-screen cell (an icon and its label), the icon's size, the dock's icons
  D.CELL = { w = 34, h = 33, icon = 20, dockIcon = 18 }
  -- an app opening / coming back: the zoom (seconds)
  D.ZOOM = 0.24
  D.REPEAT_START, D.REPEAT_EVERY = 20, 4
  local repeated = K.repeater(D.REPEAT_START, D.REPEAT_EVERY)

  -- colours
  local C = {
    shellTop = { 232, 234, 240 }, shellFoot = { 178, 182, 192 }, shellEdge = { 110, 114, 128 },
    glass = { 14, 15, 20 }, glassFoot = { 26, 28, 36 }, chinTop = { 214, 217, 225 }, chinFoot = { 186, 190, 200 },
    ink = { 30, 32, 44 }, soft = { 104, 108, 128 }, bar = { 250, 250, 252 }, bad = { 220, 62, 74 },
    off = { 0, 0, 0 }, logo = { 236, 238, 244 }, logoSoft = { 168, 174, 192 }, room = { 40, 42, 52 },
    roomFoot = { 18, 19, 26 }, sheet = { 248, 248, 251 }, sheetFoot = { 232, 234, 240 }, dim = { 0, 0, 0 },
    accent = { 64, 132, 246 }, clear = { 255, 255, 255, 0 }, gloss = { 255, 255, 255, 0.34 },
    good = { 120, 230, 160 }, coinTop = { 255, 222, 110 }, coinFoot = { 222, 160, 40 }, coinMark = { 120, 80, 10 },
  }
  -- the wallpaper, by game (its top, its foot)
  local WALL = {
    firered = { { 255, 140, 96 }, { 168, 40, 76 } }, leafgreen = { { 150, 216, 112 }, { 34, 116, 92 } },
    ruby = { { 240, 100, 116 }, { 112, 26, 70 } }, sapphire = { { 96, 164, 244 }, { 34, 56, 150 } },
    emerald = { { 84, 214, 164 }, { 18, 96, 112 } }, other = { { 116, 144, 232 }, { 58, 48, 140 } },
  }

  local TEXT = {
    hints = {
      grid = { { "A", "Open" }, { "B", "Log Off" }, { "START", "Menu" } },
      gridPages = { { "A", "Open" }, { "B", "Log Off" }, { "L R", "Page" }, { "START", "Menu" } },
      menu = { { "A", "Choose" }, { "B", "Back" } },
      sheet = { { "< >", "Choose" }, { "A", "OK" }, { "B", "Cancel" } },
      about = { { "A", "OK" } },
      boot = { { "A", "Skip" } },
    },
    menu = { "About WoobleOS", "Log Off…" },
    logoffTitle = "Log off?",
    logoffBody = "The PC turns off and you go back to the game.",
    cancel = "Cancel", logoff = "Log Off", ok = "OK",
    aboutName = "WoobleOS",
    games = { firered = "FireRed", leafgreen = "LeafGreen", ruby = "Ruby", sapphire = "Sapphire",
              emerald = "Emerald" },
  }
  D.TEXT = TEXT
  -- (a landscape chin has the W in its middle: the first two hints go left of it, the rest right)
  local HALVES = {}
  for key, list in pairs(TEXT.hints) do
    local left, right = {}, {}
    for i, h in ipairs(list) do
      if i <= 2 then left[#left + 1] = h else right[#right + 1] = h end
    end
    HALVES[list] = { left, right }
  end
  local ANY_KEY = { "a", "b", "start", "select", "l", "r", "up", "down", "left", "right" }
  local DIRS = { "up", "down", "left", "right" }

  local function now() return deps.now and deps.now() or 0 end
  local function se(name) if deps.se then pcall(deps.se, name) end end
  local function options()
    local ok, o = pcall(deps.options or function() return nil end)
    return ok and type(o) == "table" and o or {}
  end

  local r = nil   -- the open desktop

  -- ------- open / close

  function D.open(ctx)
    ctx = ctx or {}
    local apps = deps.apps.list(ctx)
    local grid, dock = {}, {}
    for _, app in ipairs(apps) do
      if app.dock then dock[#dock + 1] = app else grid[#grid + 1] = app end
    end
    local game = deps.gameId and deps.gameId() or ""
    r = { ctx = ctx, grid = grid, dock = dock, focus = grid[1] and "grid" or "dock", cursor = 1, dockCursor = 1,
          menuCursor = 1, page = 1, pageShown = 1, cols = 3, rows = 2, perPage = 6, t0 = now(), held = {},
          wall = WALL[game] or WALL.other, gameName = TEXT.games[game] or "", hit = K.hits, icon = {},
          waitRelease = true, booted = ctx.warm or options().boot == false }
    if r.booted then r.t0 = now() - bootLength() end
    -- (back from an app: its icon zooms back into place)
    if ctx.back then
      for i, app in ipairs(grid) do if app.id == ctx.back then r.cursor = i end end
      for i, app in ipairs(dock) do
        if app.id == ctx.back then r.dockCursor, r.focus = i, "dock" end
      end
      r.zoom = { id = ctx.back, t = now(), back = true }
    end
    return true
  end
  function D.close()
    if not r then return end
    r = nil
  end
  function D.isOpen() return r ~= nil end
  function D.state() return r end

  -- ------- the boot

  local function bootAge()
    if not r or r.booted then return nil end
    local age = now() - r.t0
    if age >= bootLength() then
      r.booted = true
      return nil
    end
    return age
  end
  local function booting()
    local age = bootAge()
    return age ~= nil and age < bootLength() - D.BOOT.REVEAL
  end
  function D.booting() return r ~= nil and booting() end
  function D.skipBoot()
    if booting() then r.t0 = now() - (bootLength() - D.BOOT.REVEAL) end
  end

  -- ------- the actions (buttons and taps both end here)

  local function pages() return max(1, math.ceil(#r.grid / r.perPage)) end
  local function setPage(p, sound)
    p = max(1, min(pages(), p))
    if p ~= r.page then
      r.page = p
      if sound ~= false then se("SE_SELECT") end
    end
    -- (the cursor follows onto the page)
    local first = (p - 1) * r.perPage + 1
    if r.cursor < first or r.cursor > min(#r.grid, first + r.perPage - 1) then r.cursor = first end
  end
  D.setPage = function(p) if r then setPage(p) end end

  local function appAt(focus, i)
    if focus == "dock" then return r.dock[i] end
    return r.grid[i]
  end

  -- open an app: it zooms up from its icon, then runs (a sheet opens at once)
  function D.launch(which, i)
    if not r or r.zoom and not r.zoom.back then return end
    local app = appAt(which, i)
    if not app then return end
    se("SE_SELECT")
    if app.id == "about" or app.id == "logoff" then
      r.zoom = nil
      return app.open(r.ctx)
    end
    r.zoom = { id = app.id, app = app, t = now() }
  end

  local function openMenu()
    r.menuOpen, r.menuCursor = true, 1
    se("SE_SELECT")
  end
  local function closeMenu()
    r.menuOpen = false
    se("SE_SELECT")
  end
  function D.sheet(kind)
    if not r then return end
    r.menuOpen = false
    r.sheet, r.sheetYes = kind, true
  end
  local function closeSheet()
    r.sheet = nil
    se("SE_SELECT")
  end
  local function logoff()
    r.sheet = nil
    se("SE_SELECT")
    if r.ctx.logoff then r.ctx.logoff() end
  end
  local function menuChoose(i)
    r.menuOpen = false
    if i == 1 then D.sheet("about") else D.sheet("logoff") end
    se("SE_SELECT")
  end

  -- the grid's cursor moved by dx, dy cells (pages follow at the edges)
  local function moveGrid(dx, dy)
    local per, cols = r.perPage, r.cols
    local p = floor((r.cursor - 1) / per)
    local k = (r.cursor - 1) % per
    local row, c = floor(k / cols), k % cols
    local onPage = min(per, #r.grid - p * per)
    local rowsHere = math.ceil(onPage / cols)
    if dx ~= 0 then
      c = c + dx
      if c < 0 then
        if p > 0 then p, c = p - 1, cols - 1 else c = 0 end
      elseif c >= cols or p * per + row * cols + c + 1 > #r.grid then
        if (p + 1) * per < #r.grid then p, c = p + 1, 0 else return end
      end
    end
    if dy ~= 0 then
      row = row + dy
      if row < 0 then
        r.focus = "menubar"
        se("SE_SELECT")
        return
      elseif row >= rowsHere then
        if #r.dock > 0 then
          r.focus = "dock"
          se("SE_SELECT")
        end
        return
      end
    end
    local onNew = min(per, #r.grid - p * per)
    local rowsNew = math.ceil(onNew / cols)
    row = min(row, rowsNew - 1)
    local idx = p * per + row * cols + c + 1
    idx = min(idx, p * per + onNew)
    if idx ~= r.cursor then
      r.cursor = idx
      se("SE_SELECT")
    end
    if p + 1 ~= r.page then r.page = p + 1 end
  end

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  function D.input(input)
    if not (r and input) then return end
    cur = input
    if r.waitRelease then
      local okD, down = pcall(input.isDown, input, "a")
      if input:wasPressed("a") or (okD and down) then return end
      r.waitRelease = false
    end
    if booting() then
      for _, k in ipairs(ANY_KEY) do
        if input:wasPressed(k) then return D.skipBoot() end
      end
      return
    end
    if r.zoom and not r.zoom.back then return end
    local held = r.held
    local up, down, left, right = repeated(input, "up", held), repeated(input, "down", held),
      repeated(input, "left", held), repeated(input, "right", held)
    if r.sheet then
      if r.sheet == "logoff" then
        if left or right or up or down then
          r.sheetYes = not r.sheetYes
          se("SE_SELECT")
        elseif pressed("a") then
          if r.sheetYes then logoff() else closeSheet() end
        elseif pressed("b") then closeSheet()
        end
      elseif pressed("a") or pressed("b") then closeSheet()
      end
      return
    end
    if r.menuOpen then
      if up or down then
        r.menuCursor = r.menuCursor == 1 and 2 or 1
        se("SE_SELECT")
      elseif pressed("a") then menuChoose(r.menuCursor)
      elseif pressed("b") or pressed("start") then closeMenu()
      end
      return
    end
    if pressed("start") then return openMenu() end
    if pressed("b") then
      se("SE_SELECT")
      return D.sheet("logoff")
    end
    if pressed("l") then return setPage(r.page - 1) end
    if pressed("r") then return setPage(r.page + 1) end
    if r.focus == "menubar" then
      if pressed("a") then openMenu()
      elseif down and #r.grid > 0 then
        r.focus = "grid"
        se("SE_SELECT")
      elseif down then
        r.focus = "dock"
        se("SE_SELECT")
      end
      return
    end
    if r.focus == "dock" then
      if pressed("a") then return D.launch("dock", r.dockCursor) end
      if left and r.dockCursor > 1 then
        r.dockCursor = r.dockCursor - 1
        se("SE_SELECT")
      elseif right and r.dockCursor < #r.dock then
        r.dockCursor = r.dockCursor + 1
        se("SE_SELECT")
      elseif up then
        r.focus = #r.grid > 0 and "grid" or "menubar"
        se("SE_SELECT")
      end
      return
    end
    if #r.grid == 0 then
      r.focus = "dock"
      return
    end
    if pressed("a") then return D.launch("grid", r.cursor) end
    if left then moveGrid(-1, 0)
    elseif right then moveGrid(1, 0)
    elseif up then moveGrid(0, -1)
    elseif down then moveGrid(0, 1)
    end
  end

  function D.wheel(dy)
    if not r then return false end
    if booting() or r.sheet or r.menuOpen then return true end
    if dy > 0 then setPage(r.page - 1) elseif dy < 0 then setPage(r.page + 1) end
    return true
  end

  -- ------- touch and mouse (window pixels, against the last draw's rectangles)

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
    if kind == "skip" then D.skipBoot()
    elseif kind == "grid" then
      r.focus, r.cursor = "grid", arg
      D.launch("grid", arg)
    elseif kind == "dock" then
      r.focus, r.dockCursor = "dock", arg
      D.launch("dock", arg)
    elseif kind == "wmenu" then
      if r.menuOpen then closeMenu() else openMenu() end
    elseif kind == "menuRow" then menuChoose(arg)
    elseif kind == "dim" then
      if r.sheet then closeSheet() else closeMenu() end
    elseif kind == "yes" then logoff()
    elseif kind == "no" or kind == "ok" then closeSheet()
    elseif kind == "power" then D.sheet("logoff"); se("SE_SELECT")
    elseif kind == "dot" then setPage(arg)
    end
    return true
  end
  D.tap = function(x, y) return r ~= nil and tap(x, y) end

  function D.pointer(ev)
    if not (r and type(ev) == "table") then return false end
    local x, y = tonumber(ev.x) or 0, tonumber(ev.y) or 0
    local press = r.press
    if ev.phase == "pressed" then
      local area = r.gridArea
      r.press = { id = ev.id, x = x, y = y, drag = false,
                  grid = area ~= nil and not r.sheet and not r.menuOpen and K.inside(area, x, y) }
    elseif ev.phase == "moved" then
      if press and press.id == ev.id then
        local dx = x - press.x
        if press.grid and (press.drag or abs(dx) > 4 * K.sc) then
          press.drag = true
          r.dragX = dx / K.sc
        end
      else
        local h = hitAt(x, y)
        r.hover = h and (h.kind == "grid" or h.kind == "dock") and h.kind or nil
        r.hoverArg = h and h.arg or nil
      end
    elseif ev.phase == "released" then
      if press and press.id == ev.id then
        r.press = nil
        if press.drag then
          local dx = r.dragX or 0
          r.dragX = nil
          if dx < -24 then setPage(r.page + 1) elseif dx > 24 then setPage(r.page - 1) end
        else
          tap(x, y)
        end
      end
    elseif ev.phase == "cancelled" then
      if press and press.id == ev.id then
        r.press, r.dragX = nil, nil
      end
    end
    return true
  end

  -- ------- drawing

  local amountText = K.textCache(function(n)
    local s = tostring(floor(n))
    repeat
      local k
      s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return s
  end)
  local clockText = K.textCache(function(key)
    local h, m, h24 = floor(key / 100), key % 100, key >= 10000
    h = h % 100
    if h24 then return string.format("%d:%02d", h, m) end
    local suffix = h < 12 and " AM" or " PM"
    local h12 = h % 12
    if h12 == 0 then h12 = 12 end
    return string.format("%d:%02d%s", h12, m, suffix)
  end)
  -- (the clock read once a second: the engine's reading makes a table)
  local clockAt, clockKey = -1, nil
  local function clockNow(clock)
    if clock - clockAt >= 1 or not clockKey then
      clockAt = clock
      local ok, h, m = pcall(deps.clock or function() return nil end)
      if ok and tonumber(h) and tonumber(m) then
        clockKey = floor(h) * 100 + floor(m) + (options().clock24 and 10000 or 0)
      else
        clockKey = false
      end
    end
    return clockKey and clockText(clockKey) or nil
  end

  -- the game's Pokédollar sign (its width in units) at x, y for a `size` font
  local rgbaOf = setmetatable({}, { __mode = "k" })
  local function rgba(c, a)
    local byA = rgbaOf[c]
    if not byA then
      byA = {}
      rgbaOf[c] = byA
    end
    local k = floor(a * 64 + 0.5)
    local v = byA[k]
    if not v then
      v = { c[1] / 255, c[2] / 255, c[3] / 255, k / 64 }
      byA[k] = v
    end
    return v
  end
  local function sign(x, y, size, c, measure)
    local sc = K.sc
    local px = size * sc
    if deps.currency then
      local ok, got
      if measure then
        ok, got = pcall(deps.currencyWidth, px)
      else
        ok, got = pcall(deps.currency, K.graphics(), K.X(x), K.Y(y), px, rgba(c, 1))
      end
      if ok and tonumber(got) then return tonumber(got) / sc end
    end
    if not measure then K.text("$", x, y, size, c) end
    return K.width("$", size)
  end

  -- an app's picture, white, centred on cx, cy (window pixels), `s` the tile's size (pixels)
  local function glyph(G, kind, cx, cy, s, a)
    G.setColor(1, 1, 1, a)
    local lw = max(1, s * 0.075)
    G.setLineWidth(lw)
    if type(kind) == "function" then
      pcall(kind, K, cx, cy, s, a)
    elseif kind == "ball" then
      local rad = s * 0.31
      G.circle("line", cx, cy, rad)
      G.line(cx - rad, cy, cx - rad * 0.38, cy)
      G.line(cx + rad * 0.38, cy, cx + rad, cy)
      G.circle("line", cx, cy, rad * 0.36)
      G.setColor(1, 1, 1, 0.35 * a)
      G.arc("fill", cx, cy, rad - lw / 2, math.pi, math.pi * 2)
    elseif kind == "bag" then
      local w, h = s * 0.56, s * 0.38
      G.rectangle("line", cx - w / 2, cy - h * 0.35, w, h, s * 0.08, s * 0.08)
      G.arc("line", "open", cx, cy - h * 0.35, s * 0.13, math.pi, math.pi * 2)
      G.rectangle("fill", cx - s * 0.06, cy - h * 0.12, s * 0.12, s * 0.1)
    elseif kind == "trophy" then
      local tw = s * 0.21
      G.polygon("fill", cx - tw, cy - s * 0.27, cx + tw, cy - s * 0.27, cx + tw * 0.62, cy + s * 0.04,
        cx - tw * 0.62, cy + s * 0.04)
      G.arc("line", "open", cx - tw, cy - s * 0.17, s * 0.09, math.pi * 0.5, math.pi * 1.5)
      G.arc("line", "open", cx + tw, cy - s * 0.17, s * 0.09, -math.pi * 0.5, math.pi * 0.5)
      G.rectangle("fill", cx - s * 0.04, cy + s * 0.03, s * 0.08, s * 0.12)
      G.rectangle("fill", cx - s * 0.16, cy + s * 0.15, s * 0.32, s * 0.08, s * 0.02, s * 0.02)
    elseif kind == "dex" then
      local w, h = s * 0.44, s * 0.56
      G.rectangle("line", cx - w / 2, cy - h / 2, w, h, s * 0.06, s * 0.06)
      G.circle("fill", cx - w * 0.2, cy - h * 0.3, s * 0.06)
      G.rectangle("fill", cx - w * 0.3, cy - h * 0.08, w * 0.6, h * 0.36, s * 0.02, s * 0.02)
    elseif kind == "power" then
      local rad = s * 0.26
      G.arc("line", "open", cx, cy + s * 0.02, rad, -math.pi * 0.5 + 0.7, math.pi * 1.5 - 0.7)
      G.line(cx, cy - s * 0.3, cx, cy - s * 0.02)
    elseif kind == "logo" then
      K.drawLogo(cx, cy + s * 0.02, s * 0.62, C.logo, a, C.logoSoft)
    elseif kind == "gear" then
      local rad = s * 0.2
      G.circle("line", cx, cy, rad)
      for i = 0, 7 do
        local an = i * math.pi / 4
        G.line(cx + math.cos(an) * rad, cy + math.sin(an) * rad, cx + math.cos(an) * rad * 1.45,
          cy + math.sin(an) * rad * 1.45)
      end
    end
  end

  -- an app's icon: a rounded tile in its colour with a gloss, the picture (units)
  local function appIcon(app, x, y, s, lift, a)
    local G = K.graphics()
    if lift and lift > 0 then
      x, y, s = x - s * lift / 2, y - s * lift / 2 - lift * 2, s * (1 + lift)
    end
    local b = K.R(x, y, s, s)
    local rad = s * 0.24
    K.shadow(b, rad, 0.8, 0.28 * (a or 1))
    K.grad(b, rad, light(app.color, 0.2), dark(app.color, 0.12), a)
    K.grad(K.R(x + 0.8, y + 0.6, s - 1.6, s * 0.48), rad * 0.85, C.gloss, C.clear, a)
    K.ring(b, rad, WHITE, 0.22 * (a or 1), 0.5)
    glyph(G, app.glyph, K.X(x + s / 2), K.Y(y + s / 2), s * K.sc, a or 1)
  end

  -- the monitor around the screen, the room behind it -> the screen's rectangle (units)
  local function drawMonitor(L)
    local G = K.graphics()
    K.col(C.roomFoot)
    G.rectangle("fill", 0, 0, K.ww, K.wh)
    K.gradient(G, 0, 0, K.ww, K.wh, 0, C.room, C.roomFoot)
    local body = L.body
    K.shadow(body, 9, 2, 0.5)
    K.grad(body, 9, C.shellTop, C.shellFoot)
    K.col(WHITE, 0.55)
    K.box("fill", K.R(body[1] + 8, body[2] + 0.8, body[3] - 16, 0.8), 0.4)
    K.ring(body, 9, C.shellEdge, 0.9, 0.8)
    -- the black glass, edge to edge above the chin
    K.grad(L.glassB, 6, C.glass, C.glassFoot)
    K.ring(L.glassB, 6, BLACK, 0.6, 0.6)
    -- the chin, brushed, with the W in its middle
    local chin = L.chin
    K.grad(chin, 0, C.chinTop, C.chinFoot)
    K.col(BLACK, 0.12)
    K.box("fill", K.R(chin[1], chin[2], chin[3], 0.6))
    K.drawLogo(K.X(L.chinLogo[1]), K.Y(L.chinLogo[2]), L.chinLogo[3] * K.sc, C.shellEdge, 0.9, C.logoSoft)
    -- the power button
    local pb = L.power
    K.gradient(G, K.X(pb[1]), K.Y(pb[2]), pb[3] * K.sc, pb[4] * K.sc, pb[3] / 2 * K.sc, C.shellTop, C.shellFoot)
    K.ring(pb, pb[3] / 2, C.shellEdge, 0.7, 0.6)
    G.setColor(C.shellEdge[1] / 255, C.shellEdge[2] / 255, C.shellEdge[3] / 255, 0.85)
    local rad = pb[3] * 0.27 * K.sc
    local pcx, pcy = K.X(pb[1] + pb[3] / 2), K.Y(pb[2] + pb[4] / 2)
    G.setLineWidth(max(1, pb[3] * 0.08 * K.sc))
    G.arc("line", "open", pcx, pcy + pb[3] * 0.02 * K.sc, rad, -math.pi * 0.5 + 0.7, math.pi * 1.5 - 0.7)
    G.line(pcx, pcy - pb[3] * 0.3 * K.sc, pcx, pcy - pb[3] * 0.02 * K.sc)
    K.addHit(pb, "power")
  end

  local function drawWallpaper(sb)
    local G = K.graphics()
    K.grad(sb, 3, r.wall[1], r.wall[2])
    -- two soft light bands across it
    K.col(WHITE, 0.07)
    local x0, y0, w, h = sb[1], sb[2], sb[3], sb[4]
    G.polygon("fill", K.X(x0 + w * 0.15), K.Y(y0), K.X(x0 + w * 0.45), K.Y(y0), K.X(x0 + w * 0.2), K.Y(y0 + h),
      K.X(x0 - w * 0.1), K.Y(y0 + h))
    K.col(WHITE, 0.05)
    G.polygon("fill", K.X(x0 + w * 0.55), K.Y(y0), K.X(x0 + w * 0.68), K.Y(y0), K.X(x0 + w * 0.43), K.Y(y0 + h),
      K.X(x0 + w * 0.3), K.Y(y0 + h))
  end

  local function drawMenuBar(L, clock)
    local mb = L.menubar
    K.col(C.bar, 0.62)
    K.box("fill", mb)
    K.col(BLACK, 0.08)
    K.box("fill", K.R(mb[1], mb[2] + mb[4] - 0.4, mb[3], 0.4))
    -- the W menu
    local wb = L.wbutton
    if r.menuOpen or r.focus == "menubar" then
      K.col(C.accent, r.menuOpen and 0.9 or 0.55 + 0.3 * K.pulse())
      K.box("fill", wb, 2)
    end
    K.drawLogo(K.X(wb[1] + wb[3] / 2), K.Y(wb[2] + wb[4] / 2 + 0.2), 6.5 * K.sc,
      (r.menuOpen or r.focus == "menubar") and C.bar or C.ink, 1, (r.menuOpen or r.focus == "menubar") and C.bar or C.soft)
    K.addHit(wb, "wmenu")
    -- the clock, the money (right to left, while they fit); the player's name by the W, as the
    -- signed-in user
    local x = mb[1] + mb[3] - 4
    local ct = clockNow(clock)
    if ct then
      local w = K.width(ct, 5)
      K.text(ct, x - w, mb[2] + 1.6, 5, C.ink)
      x = x - w - 6
    end
    local s = deps.session and deps.session()
    local money = s and tonumber(s.money)
    if money then
      local digits = amountText(max(0, floor(money)))
      local dw = K.width(digits, 5)
      local sw2 = sign(0, 0, 5, C.ink, true)
      if x - dw - sw2 > mb[1] + 40 then
        K.text(digits, x - dw, mb[2] + 1.6, 5, C.ink)
        sign(x - dw - sw2, mb[2] + 1.6, 5, C.ink)
        x = x - dw - sw2 - 6
      end
    end
    local name = s and (s.name or s.playerName)
    if type(name) == "string" and name ~= "" then
      local nx = wb[1] + wb[3] + 3
      local ns = K.fit(name, 5, x - nx)
      K.text(name, nx, mb[2] + 1.6 + (5 - ns) * 0.5, ns, C.ink)
    end
  end

  -- the zoom between an icon and the whole screen (k 0 = the icon, 1 = the screen)
  local function drawZoom(sb, app, from, k)
    local e = k * k * (3 - 2 * k)
    local x = from[1] + (sb[1] - from[1]) * e
    local y = from[2] + (sb[2] - from[2]) * e
    local w = from[3] + (sb[3] - from[3]) * e
    local h = from[3] + (sb[4] - from[3]) * e
    local b = K.R(x, y, w, h)
    local rad = from[3] * 0.24 * (1 - e) + 3 * e
    K.grad(b, rad, light(app.color, 0.2), dark(app.color, 0.12))
    glyph(K.graphics(), app.glyph, K.X(x + w / 2), K.Y(y + h / 2), from[3] * K.sc * (1 + e * 1.4), 1 - e * 0.4)
  end

  local function drawGrid(L, clock)
    local cell = D.CELL
    local area = L.grid
    r.gridArea = r.gridArea or {}
    local ga = r.gridArea
    ga[1], ga[2], ga[3], ga[4] = K.X(area[1]), K.Y(area[2]), area[3] * K.sc, area[4] * K.sc
    local per = r.perPage
    -- (the pages glide; a drag pulls them along)
    local target = r.page
    r.pageShown = r.pageShown + (target - r.pageShown) * min(1, (r.dt or 0) * 14)
    if abs(r.pageShown - target) < 0.002 then r.pageShown = target end
    local slide = (r.pageShown - 1) * area[3] - (r.dragX or 0)
    K.scissor(L.screen)
    for i, app in ipairs(r.grid) do
      local p = floor((i - 1) / per)
      local k = (i - 1) % per
      local row, c = floor(k / r.cols), k % r.cols
      local cx = area[1] + L.gridPad + p * area[3] + c * cell.w - slide
      local cy = area[2] + row * cell.h
      if cx + cell.w > area[1] - cell.w and cx < area[1] + area[3] + cell.w then
        local ix, iy = cx + (cell.w - cell.icon) / 2, cy + 1
        local rec = r.icon[app.id]
        if not rec then
          rec = {}
          r.icon[app.id] = rec
        end
        rec[1], rec[2], rec[3] = ix, iy, cell.icon
        local on = r.focus == "grid" and i == r.cursor and not r.sheet and not r.menuOpen
        local hover = r.hover == "grid" and r.hoverArg == i
        local zooming = r.zoom and r.zoom.id == app.id
        if not zooming then
          appIcon(app, ix, iy, cell.icon, (on or hover) and 0.08 or 0)
          if on then
            K.ring(K.R(ix - 2.2, iy - 3.2, cell.icon + 4.4, cell.icon + 4.4), 6, WHITE, K.pulse(), 1)
          end
        end
        local ls = K.fit(app.label, 4.6, cell.w - 1)
        K.label(app.label, cx, iy + cell.icon + 2.2 + (4.6 - ls) * 0.5, ls, WHITE, "center", cell.w)
        K.addHit(K.R(cx, cy, cell.w, cell.h), "grid", i, area)
      end
    end
    K.scissor(nil)
    -- the page dots
    local n = pages()
    if n > 1 then
      local dy = L.dots
      local x0 = dy[1] + (dy[3] - (n * 6 - 2)) / 2
      for p = 1, n do
        K.col(WHITE, p == r.page and 0.95 or 0.4)
        K.graphics().circle("fill", K.X(x0 + (p - 1) * 6 + 2), K.Y(dy[2] + 2), 1.4 * K.sc)
        K.addHit(K.R(x0 + (p - 1) * 6 - 1, dy[2] - 1, 6, 6), "dot", p)
      end
    end
  end

  local function drawDock(L)
    if #r.dock == 0 then return end
    local db = L.dockB
    K.shadow(db, 7, 1, 0.18)
    K.col(WHITE, 0.26)
    K.box("fill", db, 7)
    K.ring(db, 7, WHITE, 0.4, 0.5)
    local s = D.CELL.dockIcon
    for i, app in ipairs(r.dock) do
      local ix = db[1] + 5 + (i - 1) * (s + 5)
      local iy = db[2] + (db[4] - s) / 2
      local rec = r.icon[app.id]
      if not rec then
        rec = {}
        r.icon[app.id] = rec
      end
      rec[1], rec[2], rec[3] = ix, iy, s
      local on = r.focus == "dock" and i == r.dockCursor and not r.sheet and not r.menuOpen
      local hover = r.hover == "dock" and r.hoverArg == i
      if not (r.zoom and r.zoom.id == app.id) then
        appIcon(app, ix, iy, s, (on or hover) and 0.1 or 0)
        if on then K.ring(K.R(ix - 2, iy - 3, s + 4, s + 4), 5.5, WHITE, K.pulse(), 1) end
      end
      K.addHit(K.R(ix - 2, db[2], s + 4, db[4]), "dock", i)
    end
  end

  local function drawMenu(L)
    if not r.menuOpen then return end
    local sb = L.screen
    K.addHit(sb, "dim")
    local mb = L.menuB
    K.shadow(mb, 4, 1.2, 0.3)
    K.grad(mb, 4, C.sheet, C.sheetFoot)
    K.ring(mb, 4, BLACK, 0.12, 0.5)
    for i, label in ipairs(TEXT.menu) do
      local row = K.R(mb[1] + 2, mb[2] + 2 + (i - 1) * 10, mb[3] - 4, 10)
      if i == r.menuCursor then
        K.col(C.accent)
        K.box("fill", row, 2.5)
      end
      K.text(label, row[1] + 4, row[2] + 2.4, 5, i == r.menuCursor and WHITE or C.ink)
      K.addHit(row, "menuRow", i)
    end
  end

  local function drawSheet(L)
    if not r.sheet then return end
    local sb = L.screen
    K.keepHits("power")
    K.col(C.dim, 0.38)
    K.box("fill", sb, 3)
    K.addHit(sb, "dim")
    local ab = L.sheetB
    K.shadow(ab, 8, 2, 0.35)
    K.grad(ab, 8, C.sheet, C.sheetFoot)
    if r.sheet == "about" then
      K.drawLogo(K.X(ab[1] + ab[3] / 2), K.Y(ab[2] + 15), 22 * K.sc, C.accent, 1)
      K.text(TEXT.aboutName, ab[1], ab[2] + 26, 8, C.ink, "center", ab[3])
      r.aboutLine = r.aboutLine or ("Version " .. tostring(deps.version or "?")
        .. (r.gameName ~= "" and ("  ·  " .. r.gameName) or ""))
      K.text(r.aboutLine, ab[1], ab[2] + 37, 5, C.soft, "center", ab[3])
      local b = K.R(ab[1] + (ab[3] - 44) / 2, ab[2] + ab[4] - 18, 44, 13)
      K.grad(b, 6.5, light(C.accent, 0.15), dark(C.accent, 0.08))
      K.label(TEXT.ok, b[1], b[2] + 3, 6, WHITE, "center", b[3])
      K.ring(K.R(b[1] - 1.2, b[2] - 1.2, b[3] + 2.4, b[4] + 2.4), 7.5, C.accent, K.pulse(), 1)
      K.addHit(b, "ok")
      return
    end
    K.drawLogo(K.X(ab[1] + ab[3] / 2), K.Y(ab[2] + 12), 14 * K.sc, C.bad, 1)
    K.text(TEXT.logoffTitle, ab[1], ab[2] + 20, 7, C.ink, "center", ab[3])
    local bs = K.fit(TEXT.logoffBody, 4.8, ab[3] - 10)
    K.text(TEXT.logoffBody, ab[1] + 4, ab[2] + 30, bs, C.soft, "center", ab[3] - 8)
    local bw = (ab[3] - 20) / 2
    for i = 1, 2 do
      local yes = i == 2
      local b = K.R(ab[1] + 8 + (i - 1) * (bw + 4), ab[2] + ab[4] - 19, bw, 13)
      local on = yes == r.sheetYes
      local tint = yes and C.bad or C.soft
      if on then
        K.grad(b, 6.5, light(tint, 0.15), dark(tint, 0.08))
        K.label(yes and TEXT.logoff or TEXT.cancel, b[1], b[2] + 3, 6, WHITE, "center", b[3])
        K.ring(K.R(b[1] - 1.2, b[2] - 1.2, b[3] + 2.4, b[4] + 2.4), 7.5, tint, K.pulse(), 1)
      else
        K.col(BLACK, 0.07)
        K.box("fill", b, 6.5)
        K.text(yes and TEXT.logoff or TEXT.cancel, b[1], b[2] + 3, 6, C.ink, "center", b[3])
      end
      K.addHit(b, yes and "yes" or "no")
    end
  end

  local function drawBoot(L, bt)
    local sb = L.screen
    local B = D.BOOT
    local G = K.graphics()
    local revealAt = B.BLACK + B.LOGO
    if bt < revealAt then
      K.keepHits("power")
      K.addHit(sb, "skip")
    end
    local out = max(0, bt - revealAt) / B.REVEAL
    K.col(C.off, 1 - out * out)
    -- (past the screen's rounded corners, onto the black glass)
    K.box("fill", K.R(sb[1] - 1, sb[2] - 1, sb[3] + 2, sb[4] + 2))
    if bt < B.BLACK then return end
    local into = bt - B.BLACK
    if not r.chimed then
      r.chimed = true
      se("SE_PC_LOGIN")
    end
    local la = min(1, into / 0.3) * (1 - out)
    local size = min(sb[4] * 0.34, sb[3] * 0.24)
    local cx, cy = sb[1] + sb[3] / 2, sb[2] + sb[4] / 2 - 6
    K.drawLogo(K.X(cx), K.Y(cy), size * K.sc, C.logo, la, C.logoSoft)
    if out == 0 then
      local fill = min(1, max(0, (into - 0.2) / (B.LOGO - 0.35)))
      local bw = min(56, sb[3] * 0.36)
      local bar = K.R(cx - bw / 2, cy + size * 0.31 + 10, bw, 2)
      K.col(WHITE, 0.18 * la)
      K.box("fill", bar, 1)
      if fill > 0 then
        K.col(WHITE, la)
        K.box("fill", K.R(bar[1], bar[2], max(bar[4], bar[3] * fill), bar[4]), 1)
      end
    end
    G.setColor(1, 1, 1, 1)
  end

  -- the page's rectangles (units) for a pw x ph page
  function D.layout(pw, ph, portrait)
    local L = { pw = pw, ph = ph, portrait = portrait }
    local chinH = portrait and 34 or 22
    L.body = { 2.5, 2.5, pw - 5, ph - 5 }
    L.glassB = { 6, 6, pw - 12, ph - 6 - chinH }
    L.screen = { 10, 10, pw - 20, L.glassB[4] - 8 }
    L.chin = { 6, ph - chinH, pw - 12, chinH - 4 }
    local chinMid = L.chin[2] + L.chin[4] / 2
    if portrait then
      L.chinLogo = { pw / 2, L.chin[2] + 8, 10 }
      L.hints = { 10, L.chin[2] + 15, pw - 20, 9 }
      L.power = { pw - 19, L.chin[2] + 3.5, 9, 9 }
    else
      L.chinLogo = { pw / 2, chinMid, 10 }
      L.hints = { 12, chinMid - 4, pw / 2 - 21, 9 }
      L.power = { pw - 21, chinMid - 4.5, 9, 9 }
      L.hints2 = { pw / 2 + 10, chinMid - 4, L.power[1] - 4 - (pw / 2 + 10), 9 }
    end
    local sb = L.screen
    L.menubar = { sb[1], sb[2], sb[3], 9 }
    L.wbutton = { sb[1] + 2, sb[2] + 0.5, 11, 8 }
    L.menuB = { sb[1] + 2, sb[2] + 9.5, 72, 24 }
    local aw = min(140, sb[3] - 20)
    L.sheetB = { sb[1] + (sb[3] - aw) / 2, sb[2] + (sb[4] - 74) / 2, aw, 74 }
    -- the dock along the foot of the screen, the grid above it
    L.dockY = sb[2] + sb[4] - 27
    local top = sb[2] + 9 + 6
    local gridH = L.dockY - 8 - top
    local cell = D.CELL
    L.cols = max(2, floor((sb[3] - 12) / cell.w))
    L.rows = max(1, floor(gridH / cell.h))
    local gw = sb[3] - 12
    L.grid = { sb[1] + 6, top, gw, L.rows * cell.h }
    L.gridPad = (gw - L.cols * cell.w) / 2
    L.dots = { sb[1], L.dockY - 7, sb[3], 4 }
    return L
  end

  local layoutKey = {}
  function D.draw(g, vp)
    if not (r and g and vp) then return end
    local clock = now()
    local pw, ph, portrait = K.frame(g, vp, D.PAGE, clock - r.t0)
    local L = layoutKey.L
    if not (L and layoutKey.pw == pw and layoutKey.ph == ph and layoutKey.portrait == portrait) then
      L = D.layout(pw, ph, portrait)
      layoutKey.L, layoutKey.pw, layoutKey.ph, layoutKey.portrait = L, pw, ph, portrait
    end
    r.layout, r.hit = L, K.hits
    r.dt = max(0, min(0.1, clock - (r.lastDraw or clock)))
    r.lastDraw = clock
    if r.cols ~= L.cols or r.rows ~= L.rows then
      r.cols, r.rows, r.perPage = L.cols, L.rows, L.cols * L.rows
      setPage(floor((r.cursor - 1) / r.perPage) + 1, false)
      r.pageShown = r.page
    end
    -- the dock's width follows its apps
    local db = L.dockB or {}
    L.dockB = db
    local s = D.CELL.dockIcon
    local dw = #r.dock * (s + 5) + 5
    db[1], db[2], db[3], db[4] = L.screen[1] + (L.screen[3] - dw) / 2, L.dockY, dw, 24

    drawMonitor(L)
    local sb = L.screen
    drawWallpaper(sb)
    drawMenuBar(L, clock)
    drawGrid(L, clock)
    drawDock(L)
    -- an app zooming up from its icon (then it runs), or back down into it
    local z = r.zoom
    local launch
    if z then
      local k = (clock - z.t) / D.ZOOM
      local app = z.app or deps.apps.byId(z.id)
      local from = r.icon[z.id]
      if k >= 1 or not (app and from) then
        r.zoom = nil
        -- (run once the frame is drawn: an app may close the desktop)
        if not z.back and app then launch = app end
      else
        drawZoom(sb, app, from, z.back and (1 - k) or k)
      end
    end
    drawMenu(L)
    drawSheet(L)
    local bt = bootAge()
    if bt then drawBoot(L, bt) end
    -- the hints on the chin
    local hints
    if bt and bt < bootLength() - D.BOOT.REVEAL then hints = TEXT.hints.boot
    elseif r.sheet == "about" then hints = TEXT.hints.about
    elseif r.sheet then hints = TEXT.hints.sheet
    elseif r.menuOpen then hints = TEXT.hints.menu
    else hints = pages() > 1 and TEXT.hints.gridPages or TEXT.hints.grid
    end
    if portrait then
      K.hints(hints, L.hints, C.bar, true, C.ink, C.ink)
    else
      local halves = HALVES[hints]
      K.hints(halves[1], L.hints, C.bar, false, C.ink, C.ink)
      K.hints(halves[2], L.hints2, C.bar, false, C.ink, C.ink)
    end
    g.setColor(1, 1, 1, 1)
    if launch then
      r.ctx.app = launch.id
      local ok, err = pcall(launch.open, r.ctx)
      if not ok and deps.log then deps.log("the app %s failed to open: %s", launch.id, tostring(err)) end
    end
  end

  return D
end
