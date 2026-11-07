-- The desktop: a monitor (an aluminium body, a black glass border, a chin with the W) whose screen
-- shows a home screen. A menu bar along the top (the W menu, the money, the clock), a grid of app
-- icons in pages, a dock along the foot. Buttons, touch and the mouse all drive it:
--   grid     D-pad moves (Up from the top row: the menu bar; Down from the bottom: the dock),
--            A opens, L / R change page, B asks to log off, START opens the W menu, SELECT arranges
--   arrange  (a long press on an icon, or SELECT) the icons wiggle; A picks one up, the D-pad
--            carries it (off the grid's foot into the dock, up out of it), A puts it down; with
--            the pointer it follows the drag and lands where it's let go (held at the grid's edge:
--            the next page); B / START / SELECT, Done or a tap on nothing ends it. Kept through
--            deps.saveLayout (src/arrange.lua)
--   dock     Left / Right, Up back to the grid, A opens
--   menubar  A opens the W menu, Down back to the grid
--   menu     Up / Down, A chooses, B / START close it
--   sheet    Left / Right choose, A answers, B cancels
--   touch    tap an icon, the W, a menu row, a sheet's button, the power button on the chin;
--            swipe the grid (or the mouse wheel) for the next page; the mouse highlights what it's over
--   window   an app with `window` (src/apps.lua) opens in the screen under the menu bar: its title
--            strip (the close button), its body drawn by the app; the app takes the buttons first
--            (B it leaves alone closes the window, START it leaves alone opens the W menu), taps
--            on its hits, drags and the wheel as scroll(dy)
-- It boots first (black, the W with a progress bar, the desktop fading up); any button or tap
-- skips to the desktop. Drawn over the whole window from render.hud (src/shell.lua), laid out for
-- its shape: landscape (a page 160 units tall) or portrait (180 units wide).
--
--   D = desktop(deps)
--   deps: kit (src/ui_kit.lua) ; apps (src/apps.lua) ; se(name) ; now() -> seconds ; session() ;
--         currency(G, x, y, px, rgba) / currencyWidth(px) (the game's Pokédollar sign) ;
--         clock() -> hour, minute ; options() -> { boot = bool, clock24 = bool } ; version ;
--         gameId() -> "firered" | "leafgreen" | "ruby" | "sapphire" | "emerald" ;
--         env (handed to an app's window(ctx, env): the kit, item and Pokémon icons, ...) ;
--         T (src/i18n.lua: the words) ; wall (src/wallpaper.lua) ; wallpaper() -> the chosen id ;
--         wallpaperFit() -> "fill" | "stretch" (a picture's) ; arrange (src/arrange.lua) ;
--         layout() -> dockText, gridText ; saveLayout(dockText, gridText)
--         tick(ctx) (once a second while open: R-Bay settles its auctions)
--   D.open(ctx) (ctx: src/apps.lua, plus warm = skip the boot, back = the app id to zoom back from)
--   D.close() ; D.isOpen() ; D.input(input) ; D.pointer(ev) -> true ; D.wheel(dy) ; D.draw(G, vp)
--   D.state() (tests) ; D.booting() ; D.skipBoot() ; D.launch(i) ; D.tap(x, y) ; D.arranging()
--   D.padTransfer(itemId, "out" | "in") (an item across the shelf's pad; lit while a window has
--   pad = true) ; D.padState() -> effects, way, item, light ; D.ballState() -> the pad's ball (win.ball)
--
-- WoobPad (deps.device = "pad"): the same desktop as a tablet, from the START menu anywhere: no
-- monitor, chin or shelf, a thin bezel round a bigger screen over the dimmed game, the hints under
-- it; no boot; B on the home screen (or the top button) puts it away. Its W menu: About,
-- Notifications (a swipe down from the top too), Put Away

return function(deps)
  local K = deps.kit
  local floor, max, min, abs = math.floor, math.max, math.min, math.abs
  local D = {}
  local PAD = deps.device == "pad"
  D.device = PAD and "pad" or "pc"
  local WHITE, BLACK = K.WHITE, K.BLACK
  local mix, light, dark, fade = K.mix, K.light, K.dark, K.fade
  local Ar = deps.arrange

  -- the boot (seconds): the screen black, the W with its progress bar (full FILL in, held full to
  -- the end of LOGO), the desktop fading up
  D.BOOT = { BLACK = 0.25, LOGO = 1.1, FILL = 0.75, REVEAL = 0.45 }
  local function revealAt() return D.BOOT.BLACK + D.BOOT.LOGO end
  local function bootLength() return revealAt() + D.BOOT.REVEAL end
  -- the bar (0..1) at `into` seconds past the black: quick at first, full from the reveal on
  function D.bootFill(into)
    if into >= D.BOOT.LOGO then return 1 end
    local k = min(1, max(0, (into - 0.05) / D.BOOT.FILL))
    return 1 - (1 - k) * (1 - k)
  end
  -- the shelf under the monitor (units): the page is the monitor (160 tall) and the shelf
  -- (the item on the pad and the ball in its cradle: `item` units across)
  D.SHELF = { h = 28, item = 18 }
  D.PAGE = { height = 160 + D.SHELF.h, minWidth = 220, maxWidth = 300, portraitWidth = 180,
             portraitHeight = 300 + D.SHELF.h, portraitAspect = 1.15 }
  -- (the pad: its body and the hints under it; the screen 130-odd units tall, edge to edge)
  D.PAD_PAGE = { height = 160, minWidth = 230, maxWidth = 300, portraitWidth = 180, portraitHeight = 290,
                 portraitAspect = 1.0 }
  D.BEZEL = 6
  if PAD then D.PAGE = D.PAD_PAGE end
  -- the item pad (seconds): its light coming on / off; an item going out (dropping onto it,
  -- digitizing away, a flash) and coming in (digitizing in, a moment, fading into the Bag)
  -- (ball: the Poké Ball sinking into the pad / rising back)
  -- the Poké Ball on the pad (a window with `ball`: Boxes): its drop and bounce, its button's glow
  -- coming up red, the green flash on closing, the lift off (seconds); the drop's height (units)
  D.BALL = { drop = 0.5, flash = 0.5, lift = 0.45, height = 16, moved = 0.7 }
  D.PAD = { ball = 0.3, light = 0.25, drop = 0.25, out = 0.55, flash = 0.2, inn = 0.55, hold = 0.25, fade = 0.35, gap = 0.1 }
  local function padLength(dir)
    local P = D.PAD
    if dir == "out" then return P.drop + P.out + P.flash + P.gap end
    return P.inn + P.hold + P.fade + P.gap
  end
  -- a home-screen cell (an icon and its label), the icon's size, the dock's icons
  D.CELL = { w = 34, h = 33, icon = 20, dockIcon = 18 }
  -- an app opening / coming back: the zoom (seconds)
  D.ZOOM = 0.24
  -- the screen's corners (units)
  D.SCREEN_RADIUS = PAD and 7 or 4
  D.REPEAT_START, D.REPEAT_EVERY = 20, 4
  local repeated = K.repeater(D.REPEAT_START, D.REPEAT_EVERY)

  -- colours
  local C = {
    shellTop = { 232, 234, 240 }, shellFoot = { 178, 182, 192 }, shellEdge = { 110, 114, 128 },
    glass = { 14, 15, 20 }, glassFoot = { 26, 28, 36 },
    ink = { 30, 32, 44 }, soft = { 104, 108, 128 }, bar = { 250, 250, 252 }, bad = { 220, 62, 74 },
    off = { 0, 0, 0 }, logo = { 236, 238, 244 }, logoSoft = { 168, 174, 192 }, room = { 40, 42, 52 },
    roomFoot = { 18, 19, 26 }, sheet = { 248, 248, 251 }, sheetFoot = { 232, 234, 240 }, dim = { 0, 0, 0 },
    accent = { 64, 132, 246 }, clear = { 255, 255, 255, 0 }, gloss = { 255, 255, 255, 0.34 },
    good = { 120, 230, 160 }, coinTop = { 255, 222, 110 }, coinFoot = { 222, 160, 40 }, coinMark = { 120, 80, 10 },
    -- the shelf: its top, its front lip; a Poké Ball; the pad's light and beam
    shelfBack = { 150, 154, 166 }, shelfTop = { 214, 217, 225 }, lipTop = { 196, 200, 210 }, lipFoot = { 132, 136, 150 },
    ballRed = { 228, 64, 58 }, ballRedDark = { 176, 36, 40 }, ballRedLight = { 246, 122, 108 },
    ballWhite = { 248, 248, 250 }, ballShade = { 184, 186, 196 }, ballInk = { 40, 40, 48 },
    ballEdge = { 70, 72, 80 }, ballGlowRed = { 255, 46, 46 }, ballGlowGreen = { 60, 236, 110 },
    badge = { 255, 59, 48 },
    padGlow = { 90, 214, 255 }, padLight = { 150, 236, 255 },
    beamTop = { 90, 214, 255, 0 }, beamFoot = { 90, 214, 255, 0.7 },
    -- the pad: its aluminium edge, the black glass, the camera
    padTop = { 196, 200, 210 }, padFoot = { 132, 136, 148 }, padEdge = { 84, 88, 100 }, camera = { 30, 34, 52 },
    cameraLens = { 60, 80, 140 },
  }
  -- the words: keys into lang/*.lua (src/i18n.lua), looked up as they're drawn; the hint lists
  -- through T.list (one translated copy per language, made once)
  local T = deps.T or setmetatable({ list = function(l) return l end }, { __call = function(_, k) return k end })
  D.T = T
  local CLASSIC = { { 116, 144, 232 }, { 58, 48, 140 } }
  local TEXT = {
    hints = {
      grid = { { "A", "hint.open" }, { "B", "hint.logoff" }, { "SELECT", "hint.arrange" }, { "START", "hint.menu" } },
      gridPages = { { "A", "hint.open" }, { "L R", "hint.page" }, { "SELECT", "hint.arrange" }, { "START", "hint.menu" } },
      arrange = { { "A", "hint.pick" }, { "B", "hint.done" }, { "L R", "hint.page" } },
      carry = { { "+", "hint.move" }, { "A", "hint.drop" } },
      menu = { { "A", "hint.choose" }, { "B", "hint.back" } },
      sheet = { { "< >", "hint.choose" }, { "A", "hint.ok" }, { "B", "hint.cancel" } },
      about = { { "A", "hint.ok" } },
      boot = { { "A", "hint.skip" } },
      window = { { "B", "hint.close" }, { "START", "hint.menu" } },
      padGrid = { { "A", "hint.open" }, { "B", "hint.putAway" }, { "SELECT", "hint.arrange" }, { "START", "hint.menu" } },
      padGridPages = { { "A", "hint.open" }, { "L R", "hint.page" }, { "B", "hint.putAway" }, { "START", "hint.menu" } },
      notes = { { "^ v", "hint.scroll" }, { "A", "hint.open" }, { "B", "hint.back" } },
    },
    menu = PAD and { "menu.about", "menu.notifications", "menu.putAway" } or { "menu.about", "menu.notifications",
      "menu.logoff" },
    aboutName = "WoobOS",
  }
  D.TEXT = TEXT
  -- an app's name, in the language (another mod's app: its own label)
  local function labelOf(app) return app.labelKey and T(app.labelKey) or app.label end
  D.labelOf = labelOf
  -- (a landscape chin has the W in its middle: the first two hints go left of it, the rest right)
  -- (made once per list: an app's lists too, the first time they're shown)
  local HALVES = setmetatable({}, { __mode = "k" })
  local function halvesOf(list)
    local h = HALVES[list]
    if not h then
      local left, right = {}, {}
      for i, e in ipairs(list) do
        if i <= 2 then left[#left + 1] = e else right[#right + 1] = e end
      end
      h = { left, right }
      HALVES[list] = h
    end
    return h
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
    if Ar then
      local dockText, gridText
      if deps.layout then
        local ok, d, g = pcall(deps.layout)
        if ok then dockText, gridText = d, g end
      end
      grid, dock = Ar.place(apps, dockText, gridText)
    else
      for _, app in ipairs(apps) do
        if app.dock then dock[#dock + 1] = app else grid[#grid + 1] = app end
      end
    end
    local game = deps.gameId and deps.gameId() or ""
    r = { ctx = ctx, grid = grid, dock = dock, focus = grid[1] and "grid" or "dock", cursor = 1, dockCursor = 1,
          menuCursor = 1, page = 1, pageShown = 1, cols = 3, rows = 2, perPage = 6, t0 = now(), held = {},
          game = game, hit = K.hits, icon = {},
          -- the pad: its light (0..1), its effects (the first playing, the rest waiting)
          padGlow = 0, padN = 0, padQ = { {}, {}, {} },
          waitRelease = true, booted = PAD or ctx.warm or options().boot == false }
    if r.booted then r.t0 = now() - bootLength() end
    -- (back from one of the game's screens an app's window opened: the window again, as it was)
    local resume = ctx.resume
    if resume then
      for i, app in ipairs(dock) do
        if app.id == resume.app then r.dockCursor, r.focus = i, "dock" end
      end
      for i, app in ipairs(grid) do if app.id == resume.app then r.cursor = i end end
      local app = deps.apps.byId(resume.app)
      if app and app.window then r.resumeApp, r.ballSkip = app, true end
    elseif ctx.back then
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
    local w = r.win
    r = nil
    if w and w.close then pcall(w.close) end
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
    return age ~= nil and age < revealAt()
  end
  function D.booting() return r ~= nil and booting() end
  function D.skipBoot()
    -- (a hair past the reveal: now() - (now() - x) can round under x)
    if booting() then r.t0 = now() - revealAt() - 0.001 end
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
    if r and r.edit then return end
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

  -- an app's window: made when its zoom ends, closed back into its icon
  local function openWindow(app)
    r.ctx.app = app.id
    local ok, w = pcall(app.window, r.ctx, deps.env)
    if not (ok and type(w) == "table" and w.draw) then
      if deps.log then deps.log("the app %s failed to open: %s", app.id, tostring(w)) end
      return
    end
    r.win, r.winApp, r.winFailed = w, app, false
  end
  local function closeWindow()
    local w, app = r.win, r.winApp
    if not w then return end
    r.win, r.winApp = nil, nil
    if w.close then pcall(w.close) end
    r.zoom = { id = app.id, t = now(), back = true }
    se("SE_SELECT")
  end
  D.closeWindow = function() if r then closeWindow() end end
  -- an app's window at once (a notification's), its state handed over as ctx.resume
  function D.openApp(id, state)
    if not r then return false end
    local app = deps.apps.byId(id)
    if not (app and app.window) then return false end
    if r.win then
      local w = r.win
      r.win, r.winApp = nil, nil
      if w.close then pcall(w.close) end
    end
    r.zoom = nil
    r.ctx.resume = { app = id, state = state }
    openWindow(app)
    r.ctx.resume = nil
    se("SE_SELECT")
    return true
  end
  D.window = function() return r and r.win end

  -- an item crossing the pad: "out" (Bag -> PC) or "in" (PC -> Bag). One plays at a time; a
  -- waiting one of the same way is replaced, so the last item chosen is the one shown
  function D.padTransfer(id, dir, kind)
    if not r or PAD or (dir ~= "out" and dir ~= "in") then return end
    -- (a Pokémon moved while the pad's Poké Ball sits there: no crossing, the ball's glow tells it)
    if kind == "ball" and r.win and r.win.ball and (r.ballPhase == "drop" or r.ballPhase == "on") then
      return
    end
    local Q, n = r.padQ, r.padN
    local slot
    if n == 0 then slot = 1
    elseif n > 1 and Q[n].dir == dir then slot = n
    elseif n < #Q then slot = n + 1
    else slot = n
    end
    r.padN = max(n, slot)
    local e = Q[slot]
    e.id, e.dir, e.t0, e.sounded, e.kind = id, dir, now(), false, kind
  end
  local function padNext(clock)
    local Q = r.padQ
    for i = 1, r.padN - 1 do
      Q[i].id, Q[i].dir, Q[i].kind = Q[i + 1].id, Q[i + 1].dir, Q[i + 1].kind
    end
    r.padN = r.padN - 1
    if r.padN > 0 then Q[1].t0, Q[1].sounded = clock, false end
  end
  -- -> waiting + playing, the playing one's way and item, the light, its kind (nil: an item; "ball")
  -- the pad's Poké Ball: "off" | "drop" | "on" | "done" (the green flash) | "lift"; while on, its
  -- glow: "moving" (red: the window carries a Pokémon, win.moving()), "moved" (green: put down), nil
  function D.ballState()
    if not r then return "off" end
    local glow
    if r.ballPhase == "on" then
      if r.ballBusy then glow = "moving"
      elseif r.ballMoveT and now() - r.ballMoveT < D.BALL.moved then glow = "moved" end
    end
    return r.ballPhase or "off", glow
  end
  function D.padState()
    if not r then return 0 end
    local e = r.padQ[1]
    if r.padN == 0 then return 0, nil, nil, r.padGlow end
    return r.padN, e.dir, e.id, r.padGlow, e.kind
  end

  -- ------- arranging: a long press on an icon (or SELECT) and the icons wiggle; one picked up
  -- moves with the pointer or the D-pad, between the home screen and the dock (Ar.DOCK_MAX at
  -- most); Done (B, START, SELECT, a tap on nothing or on Done) ends it. Each drop is kept.
  D.LONG_PRESS = 0.5
  local function saveLayout()
    if not (Ar and deps.saveLayout) then return end
    local dockText, gridText
    if deps.layout then
      local ok, d, g = pcall(deps.layout)
      if ok then dockText, gridText = d, g end
    end
    local d, g = Ar.encode(r.dock, r.grid, dockText, gridText)
    pcall(deps.saveLayout, d, g)
  end
  local function enterEdit()
    if not Ar or r.edit then return end
    r.edit = true
    se("SE_SELECT")
  end
  local function pickUp(list, i, ptr, x, y)
    local app = (list == "dock" and r.dock or r.grid)[i]
    if not app then return end
    r.carry = { app = app, list = list, i = i, ptr = ptr, x = x, y = y }
    r.focus = list
    if list == "dock" then r.dockCursor = i else r.cursor = i end
    se("SE_SELECT")
  end
  local function drop()
    if not r.carry then return end
    r.carry = nil
    saveLayout()
    se("SE_SELECT")
  end
  local function exitEdit()
    if r.carry then
      r.carry = nil
      saveLayout()
    end
    r.edit = nil
    r.cursor = max(1, min(r.cursor, #r.grid))
    r.dockCursor = max(1, min(r.dockCursor, #r.dock))
    if r.focus == "grid" and #r.grid == 0 then r.focus = #r.dock > 0 and "dock" or "menubar" end
    if r.focus == "dock" and #r.dock == 0 then r.focus = #r.grid > 0 and "grid" or "menubar" end
    setPage(r.page, false)
    se("SE_SELECT")
  end
  D.arranging = function() return r ~= nil and r.edit == true end
  -- the carried app to `list` at j -> true when it moved (the grid's page follows when `follow`)
  local LISTS = {}
  local function carryTo(list, j, follow)
    local c = r.carry
    local into = list == "dock" and r.dock or r.grid
    if list == "dock" and c.list ~= "dock" and #r.dock >= Ar.DOCK_MAX then return false end
    j = max(1, min(#into + (c.list == list and 0 or 1), j))
    if list == c.list and j == c.i then return false end
    LISTS.grid, LISTS.dock = r.grid, r.dock
    j = Ar.move(LISTS, c.list, c.i, list, j)
    c.list, c.i = list, j
    r.focus = list
    if list == "dock" then
      r.dockCursor = j
    else
      r.cursor = j
      if follow then r.page = floor((j - 1) / r.perPage) + 1 end
    end
    return true
  end
  -- the D-pad carrying it: along its row, a row up or down, off the grid's foot into the dock and
  -- up out of the dock onto the page shown
  local function moveCarried(dir)
    local c = r.carry
    local moved = false
    if c.list == "grid" then
      local i, cols = c.i, r.cols
      local row = floor(((i - 1) % r.perPage) / cols)
      if dir == "left" then moved = i > 1 and carryTo("grid", i - 1, true)
      elseif dir == "right" then moved = i < #r.grid and carryTo("grid", i + 1, true)
      elseif dir == "up" then moved = row > 0 and carryTo("grid", i - cols, true)
      elseif row >= r.rows - 1 or i + cols > #r.grid then moved = carryTo("dock", #r.dock + 1)
      else moved = carryTo("grid", i + cols, true) end
    else
      local j = c.i
      if dir == "left" then moved = j > 1 and carryTo("dock", j - 1)
      elseif dir == "right" then moved = j < #r.dock and carryTo("dock", j + 1)
      elseif dir == "up" then moved = carryTo("grid", min(#r.grid + 1, r.page * r.perPage), true) end
    end
    if moved then se("SE_SELECT") end
  end
  -- the pointer carrying it (units): over the dock's band the dock, else the cell under it on
  -- the page shown
  local function carryToPointer(ux, uy)
    local L = r.layout
    local c = r.carry
    if not (L and c) then return end
    if uy >= L.dockY - 3 then
      -- (against the dock as wide as it will be with the app in it: it re-centres as it grows)
      local s, sb = D.CELL.dockIcon, L.screen
      local n = #r.dock + (c.list == "dock" and 0 or 1)
      local left = sb[1] + (sb[3] - (n * (s + 5) + 5)) / 2
      carryTo("dock", floor((ux - left - 2.5) / (s + 5)) + 1)
      return
    end
    local area, cell = L.grid, D.CELL
    if uy < area[2] - 4 or uy > area[2] + area[4] then return end
    local col = max(0, min(r.cols - 1, floor((ux - area[1] - L.gridPad) / cell.w)))
    local row = max(0, min(r.rows - 1, floor((uy - area[2]) / cell.h)))
    carryTo("grid", (r.page - 1) * r.perPage + row * r.cols + col + 1)
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
    -- (the notifications: read now; the list from the top)
    if kind == "notes" then
      r.notesTop = 0
      if deps.notify then deps.notify.seen() end
    end
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
    se("SE_SELECT")
    if i == 1 then D.sheet("about")
    elseif i == 2 then D.sheet("notes")
    elseif PAD then logoff()
    else D.sheet("logoff") end
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
  local NAV = {}
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
      if r.sheet == "notes" then
        local n = deps.notify and #deps.notify.list() or 0
        if up then r.notesTop = max(0, (r.notesTop or 0) - 1); se("SE_SELECT")
        elseif down then r.notesTop = min(max(0, n - 1), (r.notesTop or 0) + 1); se("SE_SELECT")
        elseif pressed("a") then
          local rec = deps.notify and deps.notify.list()[(r.notesTop or 0) + 1]
          closeSheet()
          if rec then D.openApp(rec.app, rec.state) end
        elseif pressed("b") or pressed("start") then closeSheet() end
        return
      end
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
        local n = #TEXT.menu
        r.menuCursor = (r.menuCursor - 1 + (down and 1 or -1)) % n + 1
        se("SE_SELECT")
      elseif pressed("a") then menuChoose(r.menuCursor)
      elseif pressed("b") or pressed("start") then closeMenu()
      end
      return
    end
    -- a window takes the buttons first
    if r.win then
      NAV.up, NAV.down, NAV.left, NAV.right = up, down, left, right
      local ok, used = pcall(r.win.input, input, NAV)
      if not ok and deps.log then deps.log("the window's input failed: %s", tostring(used)) end
      if ok and used then return end
      if pressed("b") then return closeWindow() end
      if pressed("start") then return openMenu() end
      return
    end
    -- arranging: A picks up and puts down, the D-pad carries; B, START or SELECT is Done
    if r.edit then
      if r.carry then
        if pressed("a") or pressed("b") then return drop() end
        if left then moveCarried("left")
        elseif right then moveCarried("right")
        elseif up then moveCarried("up")
        elseif down then moveCarried("down")
        end
        return
      end
      if pressed("b") or pressed("start") or pressed("select") then return exitEdit() end
      if pressed("a") then
        if r.focus == "grid" then pickUp("grid", r.cursor, false)
        elseif r.focus == "dock" then pickUp("dock", r.dockCursor, false) end
        return
      end
    elseif pressed("select") and Ar then
      return enterEdit()
    end
    if pressed("start") then return openMenu() end
    if pressed("b") then
      se("SE_SELECT")
      -- (the pad: put away at once)
      if PAD then return logoff() end
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
    if r.win then
      if r.win.scroll then pcall(r.win.scroll, dy * 10, r.mouseX, r.mouseY) end
      return true
    end
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
    -- (arranging: Done, a page's dot; a tap on nothing is Done too)
    if r.edit then
      if not h or h.kind == "editdone" then exitEdit()
      elseif h.kind == "dot" then setPage(h.arg) end
      return true
    end
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
    elseif kind == "noteRow" then
      local rec = deps.notify and deps.notify.list()[arg]
      closeSheet()
      if rec then D.openApp(rec.app, rec.state) end
    elseif kind == "yes" then logoff()
    elseif kind == "no" or kind == "ok" then closeSheet()
    elseif kind == "power" then
      se("SE_SELECT")
      if PAD then logoff() else D.sheet("logoff") end
    elseif kind == "dot" then setPage(arg)
    elseif kind == "winclose" then closeWindow()
    elseif kind == "notify" then
      local Nt = deps.notify
      local rec = Nt and Nt.showing()
      if Nt then Nt.dismiss() end
      if rec then D.openApp(rec.app, rec.state) end
    elseif kind == "win" then
      if r.win and r.win.tap then
        local ok, err = pcall(r.win.tap, arg, x, y)
        if not ok and deps.log then deps.log("the window's tap failed: %s", tostring(err)) end
      end
    end
    return true
  end
  D.tap = function(x, y) return r ~= nil and tap(x, y) end

  -- a window that takes the pointer itself (win.pointer(phase, x, y) in units: "pressed", "moved",
  -- "hover", "released" -> true when it used the release, "cancelled")
  local function winPointer(phase, x, y, id)
    local w = r.win
    if not (w and w.pointer) then return false end
    local ok, used = pcall(w.pointer, phase, (x - K.ox) / K.sc, (y - K.oy) / K.sc, id)
    if not ok and deps.log then deps.log("the window's pointer failed: %s", tostring(used)) end
    return ok and used == true
  end

  function D.pointer(ev)
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
      local area, wa = r.gridArea, r.winArea
      local free = not r.sheet and not r.menuOpen
      -- (the pad: a press at the top of the screen may pull the notifications down)
      local L0 = r.layout
      local fromTop = PAD and L0 and not r.sheet and (y - K.oy) / K.sc < L0.screen[2] + 12 or false
      r.press = { id = ev.id, x = x, y = y, ly = y, drag = false, t0 = now(), mx = x, my = y, top = fromTop,
                  grid = not r.win and area ~= nil and free and K.inside(area, x, y),
                  win = r.win ~= nil and wa ~= nil and free and K.inside(wa, x, y) }
      if r.press.win and r.win.pointer then
        r.press.own = true
        winPointer("pressed", x, y, ev.id)
      end
      -- (on an icon: held still, it's picked up to arrange; already arranging, at once)
      local h = not r.win and free and not booting() and hitAt(x, y)
      if h and (h.kind == "grid" or h.kind == "dock") then
        r.press.icon, r.press.arg = h.kind, h.arg
        if r.edit and not r.carry then
          pickUp(h.kind, h.arg, true, (x - K.ox) / K.sc, (y - K.oy) / K.sc)
          r.press.carry = true
        end
      end
    elseif ev.phase == "moved" then
      r.mouseX, r.mouseY = x, y
      if press and press.id == ev.id then
        press.mx, press.my = x, y
        if abs(x - press.x) > 4 * K.sc or abs(y - press.y) > 4 * K.sc then press.moved = true end
      end
      if press and press.id == ev.id and press.carry then
        local c = r.carry
        if c then
          c.x, c.y = (x - K.ox) / K.sc, (y - K.oy) / K.sc
          carryToPointer(c.x, c.y)
        end
      elseif press and press.id == ev.id and press.own then
        if abs(x - press.x) > 4 * K.sc or abs(y - press.y) > 4 * K.sc then press.drag = true end
        winPointer("moved", x, y, ev.id)
      elseif not press and r.win and r.win.pointer and r.winArea and K.inside(r.winArea, x, y) then
        winPointer("hover", x, y, ev.id)
      elseif press and press.id == ev.id then
        local dx = x - press.x
        if press.grid and (press.drag or abs(dx) > 4 * K.sc) then
          press.drag = true
          r.dragX = dx / K.sc
        elseif press.win and (press.drag or abs(y - press.y) > 4 * K.sc) then
          -- (a drag in a window scrolls it)
          press.drag = true
          if r.win and r.win.scroll then pcall(r.win.scroll, (y - press.ly) / K.sc, press.x, press.y) end
          press.ly = y
        end
      else
        local h = hitAt(x, y)
        r.hover = h and (h.kind == "grid" or h.kind == "dock") and h.kind or nil
        r.hoverArg = h and h.arg or nil
      end
    elseif ev.phase == "released" then
      if press and press.id == ev.id and press.top and y - press.y > 20 * K.sc then
        -- (pulled down from the top: the notifications)
        r.press = nil
        se("SE_SELECT")
        D.sheet("notes")
        return true
      end
      if press and press.id == ev.id and press.carry then
        r.press = nil
        drop()
      elseif press and press.id == ev.id and press.own then
        r.press = nil
        -- (a release the window didn't use is a tap)
        if not winPointer("released", x, y, ev.id) and not press.drag then tap(x, y) end
      elseif press and press.id == ev.id then
        r.press = nil
        if press.drag and press.win then
          -- (the window kept up with it)
        elseif press.drag then
          local dx = r.dragX or 0
          r.dragX = nil
          if dx < -24 then setPage(r.page + 1) elseif dx > 24 then setPage(r.page - 1) end
        else
          tap(x, y)
        end
      end
    elseif ev.phase == "cancelled" then
      if press and press.id == ev.id then
        if press.own then winPointer("cancelled", x, y, ev.id) end
        if press.carry then drop() end
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
  local badgeText = K.textCache(function(n) return tostring(n) end)
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
  -- an amount of money for the windows: the sign then the digits (units), its left at x -> its
  -- width (measure: only the width)
  function D.amount(n, x, y, size, c, measure)
    local digits = amountText(max(0, floor(tonumber(n) or 0)))
    local sw = sign(0, 0, size, c, true)
    if not measure then
      sign(x, y, size, c)
      K.text(digits, x + sw, y, size, c)
    end
    return sw + K.width(digits, size)
  end

  -- (the radar glyph's corners, once)
  local RADAR_X, RADAR_Y, RADAR_K = {}, {}, { 0.9, 0.55, 0.75, 0.5, 0.8 }
  for i = 1, 5 do
    local an = -math.pi / 2 + (i - 1) * 2 * math.pi / 5
    RADAR_X[i], RADAR_Y[i] = math.cos(an), math.sin(an)
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
    elseif kind == "mail" then
      local w, h = s * 0.56, s * 0.4
      local x0, y0 = cx - w / 2, cy - h / 2
      G.rectangle("line", x0, y0, w, h, s * 0.05, s * 0.05)
      G.line(x0 + lw * 0.3, y0 + lw * 0.3, cx, cy + h * 0.08, x0 + w - lw * 0.3, y0 + lw * 0.3)
    elseif kind == "rocket" then
      -- (Team Rocket's R: the stem, the bowl, the leg)
      G.setLineWidth(lw * 1.7)
      local x0, top, bot, mid = cx - s * 0.13, cy - s * 0.25, cy + s * 0.25, cy + s * 0.02
      G.line(x0, top, x0, bot)
      G.line(x0, top, cx + s * 0.03, top)
      G.arc("line", "open", cx + s * 0.03, (top + mid) / 2, (mid - top) / 2, -math.pi / 2, math.pi / 2)
      G.line(cx + s * 0.03, mid, x0, mid)
      G.line(cx - s * 0.01, mid, cx + s * 0.16, bot)
    elseif kind == "globe" then
      -- (a globe: its meridians and parallels, a ring round it with a gold Poké Ball on it)
      local rad = s * 0.27
      G.circle("line", cx, cy, rad)
      G.ellipse("line", cx, cy, rad * 0.45, rad)
      G.line(cx, cy - rad, cx, cy + rad)
      G.line(cx - rad, cy, cx + rad, cy)
      G.line(cx - rad * 0.87, cy - rad * 0.5, cx + rad * 0.87, cy - rad * 0.5)
      G.line(cx - rad * 0.87, cy + rad * 0.5, cx + rad * 0.87, cy + rad * 0.5)
      G.push()
      G.translate(cx, cy)
      G.rotate(-0.4)
      G.setColor(1, 0.86, 0.35, a)
      G.ellipse("line", 0, 0, rad * 1.45, rad * 0.38)
      local ra = (K.t or 0) * 1.2
      local bx, by = math.cos(ra) * rad * 1.45, math.sin(ra) * rad * 0.38
      G.setColor(0.95, 0.2, 0.22, a)
      G.arc("fill", bx, by, s * 0.05, math.pi, math.pi * 2)
      G.setColor(1, 1, 1, a)
      G.arc("fill", bx, by, s * 0.05, 0, math.pi)
      G.pop()
    elseif kind == "slots" then
      -- (a slot machine in colour: a white cabinet with a red crown, three reels each showing a
      -- Poké Ball, the lever's red knob, a sparkle twinkling at its corner)
      local w, h = s * 0.5, s * 0.46
      local x0, y0 = cx - w / 2 - s * 0.05, cy - h / 2 + s * 0.04
      G.setColor(1, 1, 1, a)
      G.rectangle("fill", x0, y0, w, h, s * 0.06, s * 0.06)
      G.setColor(0.86, 0.13, 0.19, a)
      G.rectangle("fill", x0, y0, w, h * 0.24, s * 0.06, s * 0.06)
      G.rectangle("fill", x0, y0 + h * 0.12, w, h * 0.12)
      local cw = (w - s * 0.1) / 3
      local ry = y0 + h * 0.34
      for i = 0, 2 do
        local rx = x0 + s * 0.035 + i * (cw + s * 0.015)
        G.setColor(0.16, 0.13, 0.16, a)
        G.rectangle("fill", rx, ry, cw, h * 0.52, s * 0.02, s * 0.02)
        local bx, by, br = rx + cw / 2, ry + h * 0.26, cw * 0.36
        G.setColor(0.95, 0.2, 0.22, a)
        G.arc("fill", bx, by, br, math.pi, math.pi * 2)
        G.setColor(1, 1, 1, a)
        G.arc("fill", bx, by, br, 0, math.pi)
        G.setColor(0.16, 0.13, 0.16, a)
        G.rectangle("fill", bx - br, by - br * 0.12, br * 2, br * 0.24)
        G.setColor(1, 1, 1, a)
        G.circle("fill", bx, by, br * 0.3)
      end
      G.setColor(1, 1, 1, a)
      G.setLineWidth(lw * 1.2)
      G.line(x0 + w, cy + h * 0.15, x0 + w + s * 0.08, cy + h * 0.15, x0 + w + s * 0.08, cy - h * 0.42)
      G.setColor(0.95, 0.2, 0.22, a)
      G.circle("fill", x0 + w + s * 0.08, cy - h * 0.48, s * 0.05)
      -- (the sparkle)
      local tw = 0.55 + 0.45 * math.abs(math.sin((K.t or 0) * 2.6))
      local sx, sy, r = x0 - s * 0.02, y0 - s * 0.06, s * 0.1 * tw
      local q = r * 0.25
      G.setColor(1, 1, 1, a * tw)
      G.polygon("fill", sx, sy - r, sx + q, sy - q, sx + r, sy, sx + q, sy + q, sx, sy + r, sx - q, sy + q, sx - r, sy, sx - q, sy - q)
    elseif kind == "cart" then
      -- (a shopping cart: the handle, the basket, two wheels)
      G.line(cx - s * 0.32, cy - s * 0.2, cx - s * 0.24, cy - s * 0.2, cx - s * 0.13, cy + s * 0.1,
        cx + s * 0.2, cy + s * 0.1)
      G.polygon("line", cx - s * 0.21, cy - s * 0.12, cx + s * 0.3, cy - s * 0.12, cx + s * 0.2, cy + s * 0.1,
        cx - s * 0.13, cy + s * 0.1)
      G.circle("fill", cx - s * 0.08, cy + s * 0.2, s * 0.05)
      G.circle("fill", cx + s * 0.16, cy + s * 0.2, s * 0.05)
    elseif kind == "home" then
      local w, h = s * 0.46, s * 0.3
      local x0, y0 = cx - w / 2, cy - h * 0.2
      G.rectangle("line", x0, y0, w, h + h * 0.3)
      G.polygon("fill", cx - w * 0.68, y0 + lw * 0.2, cx, cy - s * 0.3, cx + w * 0.68, y0 + lw * 0.2)
      G.rectangle("fill", cx - s * 0.05, y0 + h * 0.55, s * 0.1, h * 0.75)
    elseif kind == "map" then
      -- (a folded map in three panels, a red pin standing on it)
      local w, h = s * 0.54, s * 0.38
      local x0, y0, pw = cx - w / 2, cy - h / 2 + s * 0.06, w / 3
      local dip = s * 0.05
      G.setColor(1, 1, 1, a)
      G.polygon("fill", x0, y0, x0 + pw, y0 + dip, x0 + pw, y0 + h + dip, x0, y0 + h)
      G.polygon("fill", x0 + pw * 2, y0, x0 + w, y0 + dip, x0 + w, y0 + h + dip, x0 + pw * 2, y0 + h)
      G.setColor(1, 1, 1, a * 0.7)
      G.polygon("fill", x0 + pw, y0 + dip, x0 + pw * 2, y0, x0 + pw * 2, y0 + h, x0 + pw, y0 + h + dip)
      G.setColor(0.95, 0.24, 0.2, a)
      local px, py = cx + s * 0.06, cy - s * 0.12
      G.circle("fill", px, py, s * 0.09)
      G.polygon("fill", px - s * 0.075, py + s * 0.04, px + s * 0.075, py + s * 0.04, px, py + s * 0.2)
      G.setColor(1, 1, 1, a)
      G.circle("fill", px, py, s * 0.035)
    elseif kind == "phone" then
      -- (a handset: a gently curved grip, the earpiece and the mouthpiece reaching the same way,
      -- tilted as a phone app's; drawn about its own middle)
      G.push()
      G.translate(cx, cy)
      G.rotate(-math.pi / 4)
      local u = s
      local ax, rad = u * 0.18, u * 0.34
      G.setLineWidth(u * 0.14)
      G.arc("line", "open", ax, 0, rad, math.pi * 0.72, math.pi * 1.28, 16)
      for k = -1, 1, 2 do
        -- (each end: a rounded pad, tipped a little toward the other)
        local ex, ey = ax + rad * math.cos(math.pi * 0.72), k * rad * math.sin(math.pi * 0.72)
        G.push()
        G.translate(ex, ey)
        G.rotate(-k * 0.3)
        G.rectangle("fill", -u * 0.04, -u * 0.08, u * 0.23, u * 0.16, u * 0.07, u * 0.07)
        G.pop()
      end
      G.pop()
    elseif kind == "radar" then
      -- (a pentagon chart: its outline and a filled shape inside)
      local rad = s * 0.3
      local px, py, k = RADAR_X, RADAR_Y, RADAR_K
      G.polygon("line", cx + px[1] * rad, cy + py[1] * rad, cx + px[2] * rad, cy + py[2] * rad, cx + px[3] * rad,
        cy + py[3] * rad, cx + px[4] * rad, cy + py[4] * rad, cx + px[5] * rad, cy + py[5] * rad)
      G.setColor(1, 1, 1, 0.75 * a)
      G.polygon("fill", cx + px[1] * rad * k[1], cy + py[1] * rad * k[1], cx + px[2] * rad * k[2], cy + py[2] * rad * k[2],
        cx + px[3] * rad * k[3], cy + py[3] * rad * k[3], cx + px[4] * rad * k[4], cy + py[4] * rad * k[4],
        cx + px[5] * rad * k[5], cy + py[5] * rad * k[5])
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

  D.glyph = glyph

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
    -- (a count on the corner, as a phone shows one: R-Bay's ended auctions)
    local n = app.badgeN
    if n and n > 0 then
      local br = s * 0.17
      local bx, by = x + s - br * 0.6, y + br * 0.6
      K.col(C.badge, a)
      G.circle("fill", K.X(bx), K.Y(by), br * K.sc)
      K.text(badgeText(min(n, 99)), bx - br, by - br * 0.62, br * 1.2, WHITE, "center", br * 2, a)
    end
  end

  -- the focus ring, centred on the icon as appIcon lifts it (`pad` units clear of it all round)
  local function focusRing(x, y, s, lift, pad, rad)
    local lx, ly, ls = x - s * lift / 2, y - s * lift / 2 - lift * 2, s * (1 + lift)
    K.ring(K.R(lx - pad, ly - pad, ls + pad * 2, ls + pad * 2), rad, WHITE, K.pulse(), 1)
  end

  -- ------- the shelf: the pad in its middle (the Poké Ball resting on it, items crossing it)

  -- the ledge the monitor stands on: its top running back under the monitor, a front lip
  local function drawLedge(L)
    local top, lip = L.shelf, L.lip
    K.shadow(K.R(lip[1] + 2, lip[2], lip[3] - 4, lip[4]), 2, 1.5, 0.45)
    K.grad(top, 2, C.shelfBack, C.shelfTop)
    K.grad(lip, 1.5, C.lipTop, C.lipFoot)
    K.col(WHITE, 0.6)
    K.box("fill", K.R(lip[1] + 2, lip[2], lip[3] - 4, 0.6), 0.3)
    K.ring(K.R(top[1], top[2], top[3], top[4] + lip[4]), 2, C.shellEdge, 0.7, 0.6)
  end

  -- the scissor put back to (sx, sy, sw, sh) (none: nil), then narrowed to x, y, w, h (pixels)
  local function clipTo(G, sx, sy, sw, sh, x, y, w, h)
    if sx then G.setScissor(sx, sy, sw, sh) else G.setScissor() end
    if x then G.intersectScissor(floor(x), floor(y), math.ceil(w), math.ceil(h)) end
  end

  -- a Poké Ball facing us, `rad` units round, at cx, cy: a glossy red top lit from the top left,
  -- a white foot shading to grey, the band and the button (each half shaded inside a scissor)
  local function drawBall(G, cx, cy, rad, a, lit, litK)
    local x, y, R = K.X(cx), K.Y(cy), rad * K.sc
    local sx, sy, sw, sh = G.getScissor()
    local band, b = R * 0.09, R * 0.93
    K.col(C.ballEdge, a)
    G.circle("fill", x, y, R)
    clipTo(G, sx, sy, sw, sh, x - R, y - R, 2 * R, R - band)
    K.col(C.ballRedDark, a)
    G.circle("fill", x, y, b)
    K.col(C.ballRed, a)
    G.circle("fill", x - R * 0.1, y - R * 0.12, b * 0.84)
    K.col(C.ballRedLight, a)
    G.circle("fill", x - R * 0.28, y - R * 0.36, b * 0.4)
    clipTo(G, sx, sy, sw, sh, x - R, y + band, 2 * R, R)
    K.col(C.ballShade, a)
    G.circle("fill", x, y, b)
    K.col(C.ballWhite, a)
    G.circle("fill", x - R * 0.12, y - R * 0.22, b * 0.86)
    clipTo(G, sx, sy, sw, sh)
    K.col(C.ballInk, a)
    G.rectangle("fill", x - b, y - band, 2 * b, 2 * band)
    G.circle("fill", x, y, R * 0.34)
    K.col(C.ballShade, a)
    G.circle("fill", x, y, R * 0.26)
    K.col(C.ballWhite, a)
    G.circle("fill", x - R * 0.02, y - R * 0.02, R * 0.2)
    K.col(C.ballShade, 0.9 * (a or 1))
    G.setLineWidth(max(1, R * 0.04))
    G.circle("line", x, y, R * 0.13)
    K.col(WHITE, 0.75 * (a or 1))
    G.ellipse("fill", x - R * 0.42, y - R * 0.56, R * 0.15, R * 0.1)
    -- (the button lit: its colour, a brighter heart, a soft halo round it)
    if lit and litK and litK > 0 then
      local k = litK * (a or 1)
      G.setBlendMode("add")
      K.col(lit, 0.22 * k)
      G.circle("fill", x, y, R * 0.62)
      K.col(lit, 0.3 * k)
      G.circle("fill", x, y, R * 0.4)
      G.setBlendMode("alpha")
      K.col(dark(lit, 0.15), k)
      G.circle("fill", x, y, R * 0.21)
      K.col(lit, k)
      G.circle("fill", x, y, R * 0.17)
      K.col(light(lit, 0.45), 0.9 * k)
      G.circle("fill", x - R * 0.04, y - R * 0.05, R * 0.07)
    end
  end
  -- a Poké Ball as the pad's effects draw an item: s units square at x, y (its top left)
  local function ballIcon(_, x, y, s, a)
    drawBall(K.graphics(), x + s / 2, y + s / 2, s / 2, a)
  end

  -- the Poké Ball on the pad, for a window that holds the party (`win.ball`: Boxes) when there is
  -- one (read once a second): it drops onto the pad as the window opens and bounces, its button
  -- slowly glows red while the window is open; when it closes the button flashes green and the
  -- ball lifts off. Coming back from the game's Summary it is already there. It sinks into the
  -- pad while a Pokémon crosses it; the home screen's pad stays empty
  local function drawPadBall(L, clock)
    local G = K.graphics()
    if not r.ballsAt or clock - r.ballsAt >= 1 or clock < r.ballsAt then
      r.ballsAt = clock
      local s = r.ctx.session or (deps.session and deps.session())
      local party = type(s) == "table" and s.party
      local n = 0
      if type(party) == "table" then
        for i = 1, 6 do
          local m = party[i]
          if type(m) == "table" and (tonumber(m.species or m.speciesId) or 0) ~= 0 then n = n + 1 end
        end
      end
      r.balls = n
    end
    local B = D.BALL
    local want = r.win and r.win.ball and r.balls > 0
    local phase, t = r.ballPhase or "off", clock - (r.ballT0 or clock)
    if want then
      if phase == "off" and r.ballSkip then phase, t = "on", 0
      elseif phase == "off" or phase == "lift" then phase, t = "drop", 0
      elseif phase == "done" then phase, t = "on", 0 end
    elseif phase == "drop" or phase == "on" then
      phase, t = "done", 0
    end
    if phase == "drop" and t >= B.drop then
      phase, t = "on", t - B.drop
    elseif phase == "done" and t >= B.flash then
      phase, t = "lift", t - B.flash
    elseif phase == "lift" and t >= B.lift then
      phase, t = "off", 0
    end
    if phase ~= r.ballPhase then
      if phase == "on" and r.ballPhase == "drop" then se("SE_BALL_BOUNCE_1") end
      if phase == "done" then se("SE_BALL_CLICK") end
      r.ballPhase, r.ballT0, r.ballSkip = phase, clock - t, nil
      if phase ~= "on" then r.ballBusy, r.ballMoveT = false, nil end
    end
    -- (sunk while a Pokémon crosses the pad)
    local sinkWant = r.padN == 0 and 1 or 0
    if not r.ballK then r.ballK = sinkWant end
    local step = r.dt / D.PAD.ball
    r.ballK = sinkWant > r.ballK and min(sinkWant, r.ballK + step) or max(sinkWant, r.ballK - step)
    if phase == "off" or r.ballK <= 0 then return end
    local p = L.padC
    local rad = D.SHELF.item / 2
    local rest = p[2] + 1 - rad
    local off, a, lit, litK = 0, 1, C.ballGlowRed, 0
    if phase == "drop" then
      -- falling under gravity to the pad, then one small bounce
      local k = t / B.drop
      if k < 0.72 then
        local e = k / 0.72
        off = -B.height * (1 - e * e)
      else
        off = -2.4 * math.sin(math.pi * (k - 0.72) / 0.28)
      end
      a = min(1, k / 0.3)
    elseif phase == "on" then
      -- unlit at rest; red (pulsing) while a Pokémon is carried, a green flash once it's put down
      local busy = r.win and r.win.moving and r.win.moving() or false
      if busy and not r.ballBusy then r.ballBusyT = clock end
      if r.ballBusy and not busy then r.ballMoveT = clock end
      r.ballBusy = busy
      local m = r.ballMoveT and clock - r.ballMoveT
      if busy then
        litK = min(1, (clock - r.ballBusyT) / 0.12) * (0.78 + 0.22 * math.sin(clock * 6))
      elseif m and m < B.moved then
        lit = C.ballGlowGreen
        local k = m / B.moved
        litK = k < 0.55 and 1 or 1 - (k - 0.55) / 0.45
      end
    elseif phase == "done" then
      -- the green flash: bright at once, a second blink, held to the end
      lit = C.ballGlowGreen
      local k = t / B.flash
      litK = k < 0.25 and 1 or (k < 0.45 and 0.35 or 1)
    else
      local k = t / B.lift
      off = -B.height * 0.8 * k * k
      a = 1 - k
      lit, litK = C.ballGlowGreen, 1 - k
    end
    -- (its shadow on the pad: smaller and fainter the higher it is)
    local hk = max(0, 1 + off / B.height)
    K.col(BLACK, 0.22 * hk * a * r.ballK)
    G.ellipse("fill", K.X(p[1]), K.Y(p[2] + 0.6), rad * (0.55 + 0.45 * hk) * K.sc, rad * 0.3 * (0.55 + 0.45 * hk) * K.sc)
    local k = 1 - (1 - r.ballK) * (1 - r.ballK)
    if r.ballK < 1 then G.setScissor(0, 0, K.ww, floor(K.Y(p[2] + 1))) end
    drawBall(G, p[1], rest + off + (1 - k) * (rad * 2 + 1), rad, a, lit, litK)
    if r.ballK < 1 then G.setScissor() end
  end

  -- the pad: a silver disc, its glass lit while a window uses it, six lights round it
  local function drawPad(L, clock)
    local G = K.graphics()
    local p = L.padC
    local sc = K.sc
    local cx, cy, rx, ry = K.X(p[1]), K.Y(p[2]), p[3] * sc, p[4] * sc
    K.col(BLACK, 0.3)
    G.ellipse("fill", cx, cy + 2.4 * sc, rx * 1.02, ry)
    K.col(C.shellEdge)
    G.ellipse("fill", cx, cy + 1.5 * sc, rx, ry)
    K.col(C.shellFoot)
    G.ellipse("fill", cx, cy + 0.8 * sc, rx, ry)
    K.col(C.shellTop)
    G.ellipse("fill", cx, cy, rx, ry)
    K.col(C.glass)
    G.ellipse("fill", cx, cy, rx * 0.74, ry * 0.68)
    local glow = r.padGlow
    local busy = r.padN > 0
    if glow > 0 then
      G.setBlendMode("add")
      K.col(C.padGlow, glow * (0.45 + 0.15 * math.sin(clock * 2.5)))
      G.ellipse("fill", cx, cy, rx * 0.74, ry * 0.68)
      K.col(C.padLight, glow * 0.5)
      G.setLineWidth(max(1, 0.5 * sc))
      G.ellipse("line", cx, cy, rx * 0.5, ry * 0.44)
      G.setBlendMode("alpha")
    end
    for i = 0, 5 do
      local a = math.pi * 2 * i / 6 + 0.26
      local lx, ly = cx + math.cos(a) * rx * 0.87, cy + math.sin(a) * ry * 0.84
      K.col(C.shellEdge, 0.8)
      G.circle("fill", lx, ly, 0.85 * sc)
      if glow > 0 or busy then
        -- (a light running round while an item crosses)
        local on = busy and (0.35 + 0.65 * max(0, math.cos(a - clock * 9))) or glow
        K.col(C.padLight, on)
        G.circle("fill", lx, ly, 0.85 * sc)
      end
    end
  end

  -- the item at x, y (units, s square), cut into bands that come apart upward as k goes 0 -> 1
  -- (the top band first); `a` its alpha
  local PAD_BANDS = 6
  local function drawSlices(icon, id, x, y, s, k, a, clock)
    if k <= 0 then
      pcall(icon, id, x, y, s, a)
      return
    end
    local G = K.graphics()
    local bh = s / PAD_BANDS
    for i = 1, PAD_BANDS do
      local start = (i - 1) / PAD_BANDS * 0.5
      local q = min(1, max(0, (k - start) / 0.5))
      if q < 1 then
        local rise = q * 12
        local jitter = math.sin(i * 7.3 + clock * 40) * q * 1.4
        local by = y + (i - 1) * bh - rise
        G.setScissor(floor(K.X(x - 2)), floor(K.Y(by)), math.ceil((s + 4) * K.sc), math.ceil(bh * K.sc) + 1)
        pcall(icon, id, x + jitter, y - rise, s, a * (1 - q))
        if q > 0 then
          G.setBlendMode("add")
          K.col(C.padLight, q * 0.45 * a)
          K.box("fill", K.R(x + jitter, by, s, bh))
          G.setBlendMode("alpha")
        end
      end
    end
    G.setScissor()
  end

  -- the beam over the pad (0..1)
  local function drawBeam(L, k)
    if k <= 0 then return end
    local p = L.padC
    local G = K.graphics()
    G.setBlendMode("add")
    K.grad(K.R(p[1] - p[3] * 0.5, p[2] - 26, p[3], 26), 3, C.beamTop, C.beamFoot, k * 0.8)
    G.setBlendMode("alpha")
  end

  -- the item crossing the pad, over the monitor's chin
  local function drawPadFx(L, clock)
    if r.padN == 0 then return end
    local fx, P = r.padQ[1], D.PAD
    local icon = fx.kind == "ball" and ballIcon or deps.env and deps.env.itemIcon
    if not icon then return end
    local t = clock - fx.t0
    local p = L.padC
    local s = D.SHELF.item
    local x, y = p[1] - s / 2, p[2] - s + 1
    if fx.dir == "out" then
      if t < P.drop then
        local k = t / P.drop
        drawSlices(icon, fx.id, x, y - 10 * (1 - k * k), s, 0, min(1, k * 3), clock)
      elseif t < P.drop + P.out then
        if not fx.sounded then
          fx.sounded = true
          se("SE_WARP_OUT")
        end
        local k = (t - P.drop) / P.out
        drawBeam(L, k < 0.3 and k / 0.3 or 1 - (k - 0.3) / 0.7)
        drawSlices(icon, fx.id, x, y, s, k, 1, clock)
      elseif t < P.drop + P.out + P.flash then
        local k = (t - P.drop - P.out) / P.flash
        local G = K.graphics()
        G.setBlendMode("add")
        K.col(C.padLight, 1 - k)
        G.setLineWidth(max(1, 0.7 * K.sc))
        G.ellipse("line", K.X(p[1]), K.Y(p[2]), p[3] * (0.3 + 0.8 * k) * K.sc, p[4] * (0.3 + 0.8 * k) * K.sc)
        G.setBlendMode("alpha")
      end
    else
      if t < P.inn then
        if not fx.sounded then
          fx.sounded = true
          se("SE_WARP_IN")
        end
        local k = t / P.inn
        drawBeam(L, k < 0.6 and 1 or 1 - (k - 0.6) / 0.4)
        drawSlices(icon, fx.id, x, y, s, 1 - k, 1, clock)
      elseif t < P.inn + P.hold then
        drawSlices(icon, fx.id, x, y, s, 0, 1, clock)
      elseif t < P.inn + P.hold + P.fade then
        local k = (t - P.inn - P.hold) / P.fade
        drawSlices(icon, fx.id, x, y - 5 * k, s, 0, 1 - k, clock)
      end
    end
  end

  -- the monitor around the screen, the room behind it -> the screen's rectangle (units)
  local function drawMonitor(L, clock)
    local G = K.graphics()
    K.col(C.roomFoot)
    G.rectangle("fill", 0, 0, K.ww, K.wh)
    K.gradient(G, 0, 0, K.ww, K.wh, 0, C.room, C.roomFoot)
    drawLedge(L)
    local body = L.body
    K.shadow(body, 9, 2, 0.5)
    K.grad(body, 9, C.shellTop, C.shellFoot)
    K.col(WHITE, 0.55)
    K.box("fill", K.R(body[1] + 8, body[2] + 0.8, body[3] - 16, 0.8), 0.4)
    K.ring(body, 9, C.shellEdge, 0.9, 0.8)
    -- the black glass, edge to edge above the chin
    K.grad(L.glassB, 6, C.glass, C.glassFoot)
    K.ring(L.glassB, 6, BLACK, 0.6, 0.6)
    -- the chin: the body's own aluminium under the glass (a light edge), the W in its middle
    local gb = L.glassB
    K.col(WHITE, 0.35)
    K.box("fill", K.R(gb[1] + 6, gb[2] + gb[4] + 0.4, gb[3] - 12, 0.6), 0.3)
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
    -- on the shelf, in front of it
    drawPad(L, clock)
    drawPadBall(L, clock)
    drawPadFx(L, clock)
  end

  -- the pad: the game dimmed round it, an aluminium edge, the black glass, the camera, its top button
  local function drawPadDevice(L)
    local G = K.graphics()
    K.col(BLACK, 0.55)
    G.rectangle("fill", 0, 0, K.ww, K.wh)
    local body = L.body
    K.shadow(body, 12, 2.5, 0.55)
    K.grad(body, 12, C.padTop, C.padFoot)
    K.ring(body, 12, C.padEdge, 0.9, 0.6)
    K.col(WHITE, 0.45)
    K.box("fill", K.R(body[1] + 12, body[2] + 0.5, body[3] - 24, 0.5), 0.25)
    K.grad(L.glassB, 11, C.glass, C.glassFoot)
    -- (the camera in the bezel's middle)
    local cx, cy = L.camera[1], L.camera[2]
    K.col(C.camera)
    G.circle("fill", K.X(cx), K.Y(cy), 1.3 * K.sc)
    K.col(C.cameraLens, 0.8)
    G.circle("fill", K.X(cx - 0.3), K.Y(cy - 0.3), 0.5 * K.sc)
    -- (the top button: puts it away)
    local pb = L.power
    K.grad(pb, 0.8, C.padTop, C.padFoot)
    K.addHit(K.R(pb[1] - 2, pb[2] - 3, pb[3] + 4, pb[4] + 5), "power")
  end

  -- the chosen wallpaper (src/wallpaper.lua's canvas), else the game's classic colours
  local function drawWallpaper(sb)
    local G = K.graphics()
    local id = deps.wallpaper and deps.wallpaper() or "classic"
    if id ~= "classic" and deps.wall then
      local fit = deps.wallpaperFit and deps.wallpaperFit() or "fill"
      local ok, drawn = pcall(deps.wall.draw, id, K.X(sb[1]), K.Y(sb[2]), sb[3] * K.sc, sb[4] * K.sc, D.SCREEN_RADIUS * K.sc, fit)
      if ok and drawn then return end
    end
    if not r.wall then
      local top, foot
      if deps.wall then top, foot = deps.wall.tint(r.game) end
      r.wall = { top or CLASSIC[1], foot or CLASSIC[2] }
    end
    K.grad(sb, D.SCREEN_RADIUS, r.wall[1], r.wall[2])
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
    -- (an app open: its name there, as a Mac does)
    local name = r.winApp and labelOf(r.winApp) or s and (s.name or s.playerName)
    if type(name) == "string" and name ~= "" then
      local nx = wb[1] + wb[3] + 3
      local ns = K.fit(name, 5, x - nx)
      K.text(name, nx, mb[2] + 1.6 + (5 - ns) * 0.5, ns, C.ink)
      if r.winApp then K.text(name, nx + 0.25, mb[2] + 1.6 + (5 - ns) * 0.5, ns, C.ink) end
    end
  end

  -- the screen's corners rounded over whatever is on it (the menu bar, a window, a sheet): each
  -- corner covered in the glass's own colour by a thick arc whose inner edge is the rounding
  -- (each corner: which side in x and y, its arc's start and end in half turns)
  local CORNER_ARCS = { { -1, -1, 1, 1.5 }, { 1, -1, 1.5, 2 }, { 1, 1, 0, 0.5 }, { -1, 1, 0.5, 1 } }
  local function drawScreenCorners(L)
    local G = K.graphics()
    local sb, rad = L.screen, D.SCREEN_RADIUS
    local R = rad * K.sc
    G.setLineWidth(R * 0.7)
    for i = 1, 4 do
      local a = CORNER_ARCS[i]
      local x = a[1] < 0 and sb[1] + rad or sb[1] + sb[3] - rad
      local y = a[2] < 0 and sb[2] + rad or sb[2] + sb[4] - rad
      K.col(a[2] < 0 and L.glassAtTop or L.glassAtFoot)
      G.arc("line", "open", K.X(x), K.Y(y), R * 1.35, a[3] * math.pi - 0.08, a[4] * math.pi + 0.08)
    end
  end

  -- an app's window over the screen: a macOS toolbar (the close, minimise and zoom lights, the
  -- title), then the app on the grouped grey
  local function drawWindow(L, clock, portrait)
    local G = K.graphics()
    local UI = K.UI
    local wb, tb = L.win, L.winTitle
    -- (the whole screen, its rounded corners; the menu bar is drawn over its top)
    K.col(UI.grouped)
    K.box("fill", K.R(wb[1], wb[2] - 9, wb[3], wb[4] + 9), D.SCREEN_RADIUS)
    K.grad(tb, 0, UI.toolbar, UI.toolbarFoot)
    K.hairline(tb[1], tb[2] + tb[4] - 0.25, tb[3])
    -- (only the red one does anything: the window is the whole screen)
    local cb = L.winClose
    local cx, cy = cb[1] + cb[3] / 2, cb[2] + cb[4] / 2
    for i = 1, 3 do
      local c = i == 1 and UI.red or (i == 2 and UI.yellow or UI.green)
      local lx = cx + (i - 1) * 6.2
      K.col(c)
      G.circle("fill", K.X(lx), K.Y(cy), 2.2 * K.sc)
      K.col(dark(c, 0.25), 0.55)
      G.setLineWidth(max(1, 0.3 * K.sc))
      G.circle("line", K.X(lx), K.Y(cy), 2.2 * K.sc)
    end
    K.col(dark(UI.red, 0.55), 0.75)
    G.setLineWidth(max(1, 0.45 * K.sc))
    local px, py, d = K.X(cx), K.Y(cy), 0.95 * K.sc
    G.line(px - d, py - d, px + d, py + d)
    G.line(px - d, py + d, px + d, py - d)
    K.addHit(K.R(cb[1] - 2, cb[2] - 1, cb[3] + 4, cb[4] + 2), "winclose")
    local title = labelOf(r.winApp) or r.win.title
    K.bold(title, tb[1], tb[2] + 2.5, 4.8, UI.label, "center", tb[3])
    local body = L.winBody
    local wa = r.winArea or {}
    r.winArea = wa
    wa[1], wa[2], wa[3], wa[4] = K.X(body[1]), K.Y(body[2]), body[3] * K.sc, body[4] * K.sc
    K.scissor(body)
    local ok, err = pcall(r.win.draw, body, clock, portrait)
    K.scissor(nil)
    G.setColor(1, 1, 1, 1)
    if not ok and not r.winFailed then
      r.winFailed = true
      if deps.log then deps.log("the window's draw failed: %s", tostring(err)) end
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

  -- an icon on the home screen or in the dock: lifted under the cursor or the mouse; arranging,
  -- it wiggles, the one carried by the pointer leaves its place empty (it follows the pointer)
  -- and the one carried by the D-pad stands still, lifted higher
  local function arrangedIcon(app, ix, iy, s, on, hover, lift, pad, rad, clock, seed)
    local c = r.carry
    if c and c.app == app then
      if c.ptr then
        K.col(WHITE, 0.22)
        K.box("fill", K.R(ix, iy, s, s), s * 0.24)
        return
      end
      appIcon(app, ix, iy, s, lift * 2)
      focusRing(ix, iy, s, lift * 2, pad, rad)
      return
    end
    if r.edit then
      local G = K.graphics()
      local cx, cy = K.X(ix + s / 2), K.Y(iy + s / 2)
      G.push()
      G.translate(cx, cy)
      G.rotate(math.sin(clock * 17 + seed * 1.9) * 0.045)
      G.translate(-cx, -cy)
      appIcon(app, ix, iy, s, (on or hover) and lift or 0)
      G.pop()
    else
      appIcon(app, ix, iy, s, (on or hover) and lift or 0)
    end
    if on then focusRing(ix, iy, s, lift, pad, rad) end
  end

  -- arranging: the app the pointer carries, over everything, and Done at the screen's top right
  local function drawArranging(L)
    local c = r.carry
    if c and c.ptr then
      local s = D.CELL.icon
      appIcon(c.app, c.x - s / 2, c.y - s / 2, s, 0.18)
    end
    local sb = L.screen
    local label = T("desk.done")
    local w = K.width(label, 4.4) + 8
    local b = K.R(sb[1] + sb[3] - w - 3, sb[2] + 11, w, 8)
    K.button(b, label, "accent", false, 4.4)
    K.addHit(b, "editdone")
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
        if not zooming then arrangedIcon(app, ix, iy, cell.icon, on, hover, 0.08, 1.4, 6, clock, i) end
        local label = labelOf(app)
        local ls = K.fit(label, 4.6, cell.w - 1)
        if not (r.carry and r.carry.ptr and r.carry.app == app) then
          K.label(label, cx, iy + cell.icon + 2.2 + (4.6 - ls) * 0.5, ls, WHITE, "center", cell.w)
        end
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

  local function drawDock(L, clock)
    if #r.dock == 0 and not r.edit then return end
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
      if not (r.zoom and r.zoom.id == app.id) then arrangedIcon(app, ix, iy, s, on, hover, 0.1, 1.1, 5.5, clock, i + 7) end
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
    for i, label in ipairs(T.list(TEXT.menu)) do
      local row = K.R(mb[1] + 2, mb[2] + 2 + (i - 1) * 10, mb[3] - 4, 10)
      if i == r.menuCursor then
        K.col(C.accent)
        K.box("fill", row, 2.5)
      end
      K.text(label, row[1] + 4, row[2] + 2.4, 5, i == r.menuCursor and WHITE or C.ink)
      K.addHit(row, "menuRow", i)
    end
  end

  -- the notifications: the list, newest first, a card each (a tap opens its app)
  local function drawNotes(L)
    local sb = L.screen
    K.col(C.dim, 0.3)
    K.box("fill", sb, D.SCREEN_RADIUS)
    K.addHit(sb, "dim")
    local nb = L.notesB
    K.shadow(nb, 6, 2, 0.35)
    K.grad(nb, 6, C.sheet, C.sheetFoot)
    K.bold(T("notes.title"), nb[1] + 6, nb[2] + 4, 6.5, C.ink)
    local Nt = deps.notify
    local list = Nt and Nt.list() or {}
    if #list == 0 then
      K.text(T("notes.none"), nb[1], nb[2] + nb[4] / 2 - 3, 5, C.soft, "center", nb[3])
      return
    end
    local top = min(r.notesTop or 0, max(0, #list - 1))
    local y = nb[2] + 14
    for i = top + 1, #list do
      if y + 24 > nb[2] + nb[4] - 3 then break end
      local b = K.R(nb[1] + 4, y, nb[3] - 8, 24)
      Nt.drawCard(list[i], b, 1, Nt.ago(list[i]))
      K.addHit(b, "noteRow", i)
      y = y + 26
    end
  end

  local function drawSheet(L)
    if r.sheet == "notes" then return drawNotes(L) end
    if not r.sheet then return end
    local sb = L.screen
    K.keepHits("power")
    K.col(C.dim, 0.38)
    K.box("fill", sb, D.SCREEN_RADIUS)
    K.addHit(sb, "dim")
    local ab = L.sheetB
    K.shadow(ab, 8, 2, 0.35)
    K.grad(ab, 8, C.sheet, C.sheetFoot)
    if r.sheet == "about" then
      K.drawLogo(K.X(ab[1] + ab[3] / 2), K.Y(ab[2] + 15), 22 * K.sc, C.accent, 1)
      K.text(TEXT.aboutName, ab[1], ab[2] + 26, 8, C.ink, "center", ab[3])
      -- (made again only when the language changes)
      if r.aboutCode ~= T.code() then
        local gameName = r.game ~= "" and T("game." .. r.game) or ""
        r.aboutLine = T.f("about.version", tostring(deps.version or "?"))
          .. ((gameName ~= "" and gameName ~= "game." .. r.game) and ("  ·  " .. gameName) or "")
        r.aboutCode = T.code()
      end
      K.text(r.aboutLine, ab[1], ab[2] + 37, 5, C.soft, "center", ab[3])
      local b = K.R(ab[1] + (ab[3] - 44) / 2, ab[2] + ab[4] - 18, 44, 13)
      K.grad(b, 6.5, light(C.accent, 0.15), dark(C.accent, 0.08))
      K.label(T("button.ok"), b[1], b[2] + 3, 6, WHITE, "center", b[3])
      K.ring(K.R(b[1] - 1.2, b[2] - 1.2, b[3] + 2.4, b[4] + 2.4), 7.5, C.accent, K.pulse(), 1)
      K.addHit(b, "ok")
      return
    end
    K.drawLogo(K.X(ab[1] + ab[3] / 2), K.Y(ab[2] + 12), 14 * K.sc, C.bad, 1)
    K.text(T("logoff.title"), ab[1], ab[2] + 20, 7, C.ink, "center", ab[3])
    local body = T("logoff.body")
    local bs = K.fit(body, 4.8, ab[3] - 10)
    K.text(body, ab[1] + 4, ab[2] + 30, bs, C.soft, "center", ab[3] - 8)
    local bw = (ab[3] - 20) / 2
    for i = 1, 2 do
      local yes = i == 2
      local b = K.R(ab[1] + 8 + (i - 1) * (bw + 4), ab[2] + ab[4] - 19, bw, 13)
      local on = yes == r.sheetYes
      local tint = yes and C.bad or C.soft
      if on then
        K.grad(b, 6.5, light(tint, 0.15), dark(tint, 0.08))
        K.label(T(yes and "button.logoff" or "button.cancel"), b[1], b[2] + 3, 6, WHITE, "center", b[3])
        K.ring(K.R(b[1] - 1.2, b[2] - 1.2, b[3] + 2.4, b[4] + 2.4), 7.5, tint, K.pulse(), 1)
      else
        K.col(BLACK, 0.07)
        K.box("fill", b, 6.5)
        K.text(T(yes and "button.logoff" or "button.cancel"), b[1], b[2] + 3, 6, C.ink, "center", b[3])
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
    -- (through the reveal too, full and fading with the W: a skip never leaves it cut short)
    local fill = D.bootFill(into)
    local bw = min(56, sb[3] * 0.36)
    local bar = K.R(cx - bw / 2, cy + size * 0.31 + 10, bw, 2)
    K.col(WHITE, 0.18 * la)
    K.box("fill", bar, 1)
    if fill > 0 then
      K.col(WHITE, la)
      K.box("fill", K.R(bar[1], bar[2], max(bar[4], bar[3] * fill), bar[4]), 1)
    end
    G.setColor(1, 1, 1, 1)
  end

  -- the page's rectangles (units) for a pw x ph page
  function D.layout(pw, ph, portrait)
    if PAD then return D.padLayout(pw, ph, portrait) end
    local L = { pw = pw, ph = ph, portrait = portrait }
    local chinH = portrait and 34 or 22
    -- the monitor above the shelf
    local mh = ph - D.SHELF.h
    L.mh = mh
    L.body = { 2.5, 2.5, pw - 5, mh - 5 }
    L.glassB = { 6, 6, pw - 12, mh - 6 - chinH }
    L.screen = { 10, 10, pw - 20, L.glassB[4] - 8 }
    -- (the glass's colour by the screen's top and foot corners: what covers them)
    local gb, sbx = L.glassB, L.screen
    L.glassAtTop = mix(C.glass, C.glassFoot, (sbx[2] + 2 - gb[2]) / gb[4])
    L.glassAtFoot = mix(C.glass, C.glassFoot, (sbx[2] + sbx[4] - 2 - gb[2]) / gb[4])
    L.chin = { 6, mh - chinH, pw - 12, chinH - 4 }
    -- the shelf: its top running back under the monitor's foot, its lip; the pad in the middle of
    -- its top, clear of the monitor and the front edge (padC: its middle and radii; the disc's
    -- edge hangs 1.6 under it)
    L.shelf = { 1, mh - 4, pw - 2, 22 }
    L.lip = { 1, mh + 18, pw - 2, 6 }
    local top, front = L.body[2] + L.body[4], L.lip[2]
    L.padC = { pw / 2, (top + front) / 2 - 0.8, 26, 5 }
    L.pad = { L.padC[1] - 26, L.padC[2] - 5, 52, 11.6 }
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
    return D.screenLayout(L)
  end
  -- the pad: its body above the hints, a thin bezel round the screen
  function D.padLayout(pw, ph, portrait)
    local L = { pw = pw, ph = ph, portrait = portrait, pad = true }
    local bz = D.BEZEL
    L.body = { 3, 3, pw - 6, ph - 16 }
    L.glassB = { L.body[1] + 1.1, L.body[2] + 1.1, L.body[3] - 2.2, L.body[4] - 2.2 }
    L.screen = { L.body[1] + bz, L.body[2] + bz, L.body[3] - bz * 2, L.body[4] - bz * 2 }
    L.glassAtTop, L.glassAtFoot = C.glass, C.glassFoot
    L.camera = { pw / 2, L.body[2] + bz / 2 }
    L.power = { L.body[1] + L.body[3] - 30, L.body[2] - 0.9, 14, 1.2 }
    L.hints = { 8, ph - 11.5, pw - 16, 9 }
    return D.screenLayout(L)
  end
  -- (the screen's own pieces, the same on both)
  function D.screenLayout(L)
    local sb = L.screen
    L.menubar = { sb[1], sb[2], sb[3], 9 }
    L.wbutton = { sb[1] + 2, sb[2] + 0.5, 11, 8 }
    L.menuB = { sb[1] + 2, sb[2] + 9.5, 72, 34 }
    -- (the notifications: a sheet down from the top)
    local nw = min(150, sb[3] - 16)
    L.notesB = { sb[1] + (sb[3] - nw) / 2, sb[2] + 11, nw, sb[4] - 22 }
    -- an app's window: the screen under the menu bar, a title strip, its body
    L.win = { sb[1], sb[2] + 9, sb[3], sb[4] - 9 }
    L.winTitle = { sb[1], sb[2] + 9, sb[3], 10 }
    L.winClose = { sb[1] + 2, sb[2] + 9.5, 9, 9 }
    L.winBody = { sb[1], sb[2] + 19, sb[3], sb[4] - 19 }
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
    -- (back from one of the game's screens: the window that opened it, at once)
    if r.resumeApp then
      local app = r.resumeApp
      r.resumeApp = nil
      openWindow(app)
    end
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
    local dw = max(r.edit and 1 or 0, #r.dock) * (s + 5) + 5
    db[1], db[2], db[3], db[4] = L.screen[1] + (L.screen[3] - dw) / 2, L.dockY, dw, 24
    -- the pad: lit while the window uses it; its effects one after another
    local want = r.win and r.win.pad and 1 or 0
    local step = r.dt / D.PAD.light
    r.padGlow = want > r.padGlow and min(want, r.padGlow + step) or max(want, r.padGlow - step)
    if r.padN > 0 and clock - r.padQ[1].t0 >= padLength(r.padQ[1].dir) then padNext(clock) end
    -- (once a second: the icons' counts; the apps' models tick in the shell, open or not)
    if not r.tickAt or clock - r.tickAt >= 1 or clock < r.tickAt then
      r.tickAt = clock
      if deps.tick then pcall(deps.tick, r.ctx) end
      local ng = #r.grid
      for i = 1, ng + #r.dock do
        local app = i <= ng and r.grid[i] or r.dock[i - ng]
        if app.badge then
          local ok, n = pcall(app.badge, r.ctx)
          app.badgeN = ok and tonumber(n) or 0
        end
      end
    end

    -- a long press on an icon: arranging, that icon in hand
    local pr = r.press
    if pr and pr.icon and not pr.moved and not pr.carry and not r.carry and not r.win
       and now() - pr.t0 >= D.LONG_PRESS then
      enterEdit()
      pickUp(pr.icon, pr.arg, true, (pr.mx - K.ox) / K.sc, (pr.my - K.oy) / K.sc)
      pr.carry = r.carry ~= nil
    end
    -- (carried to the grid's edge and held there: the next page)
    local c = r.carry
    if c and c.ptr and c.y < L.dockY - 3 then
      local area = L.grid
      local edge = c.x < area[1] + 5 and -1 or (c.x > area[1] + area[3] - 5 and 1 or 0)
      if edge == 0 or edge ~= c.edge then
        c.edge, c.edgeT = edge, clock
      elseif clock - c.edgeT >= 0.6 then
        c.edgeT = clock
        local p = r.page + edge
        if p >= 1 and p <= pages() then
          r.page = p
          se("SE_SELECT")
          carryToPointer(c.x, c.y)
        end
      end
    end

    if PAD then drawPadDevice(L) else drawMonitor(L, clock) end
    local sb = L.screen
    drawWallpaper(sb)
    if r.win then
      drawWindow(L, clock, portrait)
    else
      drawGrid(L, clock)
      drawDock(L, clock)
      if r.edit then drawArranging(L) end
    end
    drawMenuBar(L, clock)
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
    -- (a notification arriving: a banner at the top right, under the menu bar; a tap opens it)
    local Nt = deps.notify
    if Nt then
      local rec, k = Nt.step(clock, not booting())
      if rec then
        local sb, mb = L.screen, L.menubar
        local bw = min(124, sb[3] - 10)
        local b = K.R(sb[1] + sb[3] - bw - 4 + (1 - k) * (bw + 8), mb[2] + mb[4] + 3, bw, 24)
        Nt.drawCard(rec, b, min(1, k * 1.5))
        K.addHit(b, "notify")
      end
    end
    drawScreenCorners(L)
    local bt = bootAge()
    if bt then drawBoot(L, bt) end
    -- the hints on the chin
    local hints
    if bt and bt < revealAt() then hints = T.list(TEXT.hints.boot)
    elseif r.sheet == "about" then hints = T.list(TEXT.hints.about)
    elseif r.sheet == "notes" then hints = T.list(TEXT.hints.notes)
    elseif r.sheet then hints = T.list(TEXT.hints.sheet)
    elseif r.menuOpen then hints = T.list(TEXT.hints.menu)
    elseif r.win then
      local ok, got = true, nil
      if r.win.hints then ok, got = pcall(r.win.hints) end
      hints = ok and type(got) == "table" and got or T.list(TEXT.hints.window)
    elseif r.carry then hints = T.list(TEXT.hints.carry)
    elseif r.edit then hints = T.list(TEXT.hints.arrange)
    elseif PAD then hints = T.list(pages() > 1 and TEXT.hints.padGridPages or TEXT.hints.padGrid)
    else hints = T.list(pages() > 1 and TEXT.hints.gridPages or TEXT.hints.grid)
    end
    if PAD then
      K.hints(hints, L.hints, C.ink, true, WHITE, WHITE)
    elseif portrait then
      K.hints(hints, L.hints, C.bar, true, C.ink, C.ink)
    else
      local halves = halvesOf(hints)
      K.hints(halves[1], L.hints, C.bar, false, C.ink, C.ink)
      K.hints(halves[2], L.hints2, C.bar, false, C.ink, C.ink)
    end
    g.setColor(1, 1, 1, 1)
    if launch and launch.window then
      openWindow(launch)
    elseif launch then
      r.ctx.app = launch.id
      local ok, err = pcall(launch.open, r.ctx)
      if not ok and deps.log then deps.log("the app %s failed to open: %s", launch.id, tostring(err)) end
    end
  end

  return D
end
