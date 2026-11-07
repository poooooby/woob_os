-- The shell: puts the desktop (src/desktop.lua) where the game's PC menu was. No engine edits:
--   - the game's PC scripts open their menu through src.ui.game3.pc_menu's show(opts) at the time
--     they run (scripting/adapters.lua openPc), so wrapping that one function catches a Pokémon
--     Center PC's menu (startMode "select") and the player's bedroom PC (opts.bedroom). Every other
--     way in (the storage menu, the player's PC menu the scripts open after a choice) goes to the
--     game's own menu as before. The PC's turn-on flicker and sounds stay the game's.
--   - script.command skips the game's "booted up the PC" and "Which PC should be accessed?" lines
--     in front of those two menus (the boot does their job); with the Desktop option off they stay
--   - the wrapper is installed once per process on the module (PcMenu.__woobOs) and calls the
--     current mod instance's `impl`, so loading the mod again (another game) never wraps it twice
--   - the desktop is a Gen 3 UI stack layer (it takes the buttons, holds the script) drawn over the
--     whole window from render.hud; taps and clicks from input.pointer, the wheel from input.wheel;
--     the on-screen touch pad (and FireRed / LeafGreen's L / R help) is put away while it is up and
--     put back as it was
--   - an app hands the game's script the menu row the game's own list has for it (pc_menu's
--     _rootEntries: FireRed / LeafGreen storage, player, Oak, Hall of Fame, log off; Ruby /
--     Sapphire / Emerald storage, player, Hall of Fame, log off), so the script runs on exactly as
--     if the row was chosen, and comes back to the PC menu - the desktop again, without the boot
--
--   - WoobWatch (src/watch.lua) is the same apps on the player's wrist: its own layer
--     ("woob_watch"), pushed from the START menu's row (over the menu: closing it is the menu again)
--     or from a tap on a notification's banner over the field (closing it is the field again).
--     One of the two is open at a time; the hooks below go to whichever is
--   - once a second, whatever is on screen (deps.tick: R-Bay and the GTS settle, notifications
--     come from them), and the notifications' banner over the field while the player is free to
--     move (src/notify.lua)
--
--   Sh = shell(mod, deps)   deps: require ; log ; desktop (made) ; watch (made) ; apps (made) ;
--                           notify (src/notify.lua) ; tick() ; session() ; watchRow() -> the START
--                           row shown ; watchLabel() -> its words
--   Sh.install() (load: the hooks) ; Sh.ready() (game.ready: the PC menu wrap) ; Sh.layer ;
--   Sh.openWatch(session, opts) (opts: { app, state } to open an app at once) ; Sh.free(game)

return function(mod, deps)
  local req = deps.require or require
  local log = deps.log
  local D, A, Wt, Nt = deps.desktop, deps.apps, deps.watch, deps.notify
  local Sh = { LAYER_ID = "woob_os", WATCH_ID = "woob_watch" }

  local engineMods = {}
  local function engine(name)
    local m = engineMods[name]
    if m then return m end
    local ok
    ok, m = pcall(req, name)
    m = ok and type(m) == "table" and m or nil
    engineMods[name] = m
    return m
  end
  Sh.engine = engine

  local function se(name)
    local Ids, Audio = engine("src.core.game3.se_ids"), engine("src.core.game3.audio")
    local id = Ids and Ids[name]
    if id and Audio and Audio.playSe then pcall(Audio.playSe, id) end
  end
  Sh.se = se

  -- FireRed / LeafGreen's help (L or R in the field opens it, and the game's update stops under
  -- it): off while the desktop is up (L / R are the desktop's pages and the boxes), back after
  local helpPrev, helpOff = nil, false
  local function help(hide)
    local Help = engine("src.ui.game3.help_system")
    if not Help then return end
    if hide then
      if not helpOff then helpPrev, helpOff = Help.enabled, true end
      Help.enabled = false
    elseif helpOff then
      helpOff = false
      Help.enabled = helpPrev
    end
  end

  -- the on-screen touch pad: put away while the desktop is up, back as it was after (and the help
  -- with it)
  local padPrev, padHidden = nil, false
  local function pad(hide)
    help(hide)
    local TC = engine("src.core.TouchControls")
    if not TC then return end
    if hide then
      if not padHidden then
        padPrev, padHidden = TC.enabled, true
      end
      if TC.enabled ~= false then
        TC.enabled = false
        if TC.reset then pcall(TC.reset, TC) end
      end
    elseif padHidden then
      padHidden = false
      TC.enabled = padPrev
      if TC.enabled ~= false and TC.reset then pcall(TC.reset, TC) end
    end
  end

  local Layer = { isMenu = true }
  Sh.layer = Layer
  function Layer.handleInput(input) D.input(input) end
  function Layer.update() end
  function Layer.draw()
    local G = love and love.graphics
    if G then
      G.setColor(0, 0, 0, 1)
      G.rectangle("fill", 0, 0, 240, 160)
      G.setColor(1, 1, 1, 1)
    end
  end

  -- (the watch's: the field stays drawn under it, the watch dims it itself)
  local WatchLayer = { isMenu = true }
  Sh.watchLayer = WatchLayer
  function WatchLayer.handleInput(input) if Wt then Wt.input(input) end end
  function WatchLayer.update() end
  function WatchLayer.draw() end

  -- (the desktop is full screen: the field isn't drawn under it; the watch's field stays, dimmed)
  local FULL, OVER = { hideBelow = true, fullscreen = true }, { hideBelow = true, fullscreen = false }
  local function push(id, layer)
    id, layer = id or Sh.LAYER_ID, layer or Layer
    local Stack = engine("src.ui.game3.stack")
    if not Stack then return false end
    local ok, err = pcall(Stack.push, id, layer, layer == WatchLayer and OVER or FULL)
    if not ok then
      if log then log:warn("the desktop could not open: %s", tostring(err)) end
      return false
    end
    pad(true)
    return true
  end
  local function pop(id)
    id = id or Sh.LAYER_ID
    local Stack = engine("src.ui.game3.stack")
    if Stack and Stack.has and Stack.has(id) then pcall(Stack.pop, id) end
    pad(false)
  end
  -- the one open (the desktop or the watch), and its layer's id
  local function host()
    if D.isOpen() then return D, Sh.LAYER_ID end
    if Wt and Wt.isOpen() then return Wt, Sh.WATCH_ID end
    return nil
  end
  Sh.host = host

  local function familyOf(game)
    game = tostring(game or "")
    if game:find("firered", 1, true) or game:find("leafgreen", 1, true) then return "frlg" end
    return "rse"
  end
  local GAMES = { "firered", "leafgreen", "ruby", "sapphire", "emerald" }
  local function gameId()
    local GV = engine("src.core.GameVersion")
    local g = GV and GV.current and tostring(GV.current) or ""
    for _, id in ipairs(GAMES) do
      if g:find(id, 1, true) then return id end
    end
    return g
  end
  Sh.gameId = gameId

  -- (back from an app the script ran: the next PC menu skips the boot and zooms back into it)
  local warm = nil
  function Sh.forget() warm = nil end

  -- the desktop in place of the game's menu; false: let the game's menu open
  local function openDesktop(opts, mode, original)
    local PcMenu = engine("src.ui.game3.pc_menu")
    local rows = {}
    if mode == "select" and PcMenu and PcMenu._rootEntries then
      PcMenu._session = opts.session
      local ok, got = pcall(PcMenu._rootEntries)
      if ok and type(got) == "table" then rows = got end
      if #rows == 0 then return false end
    end
    local ctx = { session = opts.session, mode = mode, family = familyOf(gameId()), rows = rows }
    function ctx.row(id)
      for i, row in ipairs(rows) do
        if row.id == id then return i - 1 end
      end
      return nil
    end
    local closed = false
    local function close()
      closed = true
      D.close()
      pop()
    end
    -- a row to the game's script (127: logged off)
    function ctx.finish(result)
      if closed then return end
      close()
      warm = (result ~= 127 and ctx.app ~= "hall") and { back = ctx.app } or nil
      if opts.onClose then opts.onClose(result) end
    end
    function ctx.done()
      if closed then return end
      close()
      warm = nil
      if opts.onClose then opts.onClose(mode == "select" and 127 or nil) end
    end
    -- (the game's script plays the PC turning off)
    function ctx.logoff()
      if mode == "select" then ctx.finish(127) else ctx.done() end
    end
    -- one of the game's own screens over the desktop: open(onClose) opens it; the desktop comes
    -- back (no boot, the app's icon zooming back) when it closes. With `resume` (an app window's
    -- state), the window itself comes back, handed ctx.resume = { app, state }
    function ctx.over(open, resume)
      D.close()
      pop()
      local back = ctx.app
      local function reopen()
        if closed then return end
        ctx.warm, ctx.back = true, back
        ctx.resume = resume ~= nil and { app = back, state = resume } or nil
        D.open(ctx)
        push()
      end
      local ok, err = pcall(open, reopen)
      if not ok then
        if log then log:warn("the game's screen failed to open: %s", tostring(err)) end
        reopen()
      end
    end
    -- the game's own PC menu over the desktop
    function ctx.original(o)
      ctx.over(function(onClose)
        original({ session = opts.session, startMode = o.startMode, bedroom = o.bedroom, closeOnExit = true,
                   silentClose = true, onClose = onClose })
      end)
    end
    function ctx.sheet(kind) D.sheet(kind) end
    if warm then
      ctx.warm, ctx.back = true, warm.back
      warm = nil
    end
    D.open(ctx)
    if not push() then
      D.close()
      return false
    end
    return true
  end

  -- the watch: the apps (no PC rows: Oak, the Hall, Decorate and log off stay at the PC); closing
  -- it goes back to what was under it (the START menu, or the field)
  function Sh.openWatch(s, opts)
    if not Wt or Wt.isOpen() or D.isOpen() then return false end
    if Sh.enabled and not Sh.enabled() then return false end
    s = s or (deps.session and deps.session())
    local ctx = { session = s, mode = "watch", host = "watch", family = familyOf(gameId()), rows = {} }
    function ctx.row() return nil end
    local closed = false
    local function close()
      if closed then return end
      closed = true
      Wt.close()
      pop(Sh.WATCH_ID)
    end
    ctx.finish, ctx.done, ctx.logoff = close, close, close
    -- one of the game's screens over the watch (Boxes' Summary, an evolution), the watch back on
    -- the app after
    function ctx.over(open, resume)
      Wt.close()
      pop(Sh.WATCH_ID)
      local back = ctx.app
      local function reopen()
        if closed then return end
        ctx.resume = { app = back, state = resume }
        Wt.open(ctx)
        push(Sh.WATCH_ID, WatchLayer)
      end
      local ok, err = pcall(open, reopen)
      if not ok then
        if log then log:warn("the game's screen failed to open: %s", tostring(err)) end
        reopen()
      end
    end
    function ctx.original() end
    function ctx.sheet() end
    if opts and opts.app then ctx.resume = { app = opts.app, state = opts.state } end
    Wt.open(ctx)
    if not push(Sh.WATCH_ID, WatchLayer) then
      Wt.close()
      return false
    end
    return true
  end

  -- the player free to move in the field (the engine's own test for its quicksave): no script,
  -- no menu, no message, no battle
  function Sh.free(game)
    if not (type(game) == "table" and game.phase == "field") then return false end
    local Hud = engine("src.ui.game3.hud")
    if not (Hud and Hud.busy and Hud.startButtonAllowed) then return false end
    local ok, busy = pcall(Hud.busy)
    if not ok or busy then return false end
    local ok2, allowed = pcall(Hud.startButtonAllowed)
    return ok2 and allowed == true
  end

  -- the wrap of pc_menu.show: once per process, calling this instance
  function Sh.ready()
    local PcMenu = engine("src.ui.game3.pc_menu")
    if not (PcMenu and type(PcMenu.show) == "function") then
      if log then log:warn("the game's PC menu wasn't found: the PC keeps its own menu") end
      return false
    end
    local w = rawget(PcMenu, "__woobOs")
    if not w then
      w = { orig = PcMenu.show }
      PcMenu.__woobOs = w
      PcMenu.show = function(opts)
        local impl = w.impl
        if impl then
          local ok, opened = pcall(impl, opts or {}, w.orig)
          if ok and opened then return end
          if not ok and w.log then w.log:warn("the desktop failed to open: %s", tostring(opened)) end
        end
        return w.orig(opts)
      end
    end
    w.log = log
    w.impl = function(opts, original)
      if Sh.enabled and not Sh.enabled() then return false end
      local mode = (opts.startMode == "select" and "select") or (opts.bedroom == true and "bedroom") or nil
      if not mode then return false end
      return openDesktop(opts, mode, original)
    end
    return true
  end

  -- the game's two lines before its PC menu ("X booted up the PC." and "Which PC should be
  -- accessed?"): the boot does their job, so they're skipped. In the scripts (msgbox = loadword +
  -- callstd 4): a Center PC is msgbox, goto <menu>; the menu is message, waitmessage, special
  -- CreatePCMenu / ScriptMenu_CreatePCMultichoice; the bedroom PC is msgbox, special BedroomPC.
  local PC_SPECIALS = { CreatePCMenu = true, ScriptMenu_CreatePCMultichoice = true, BedroomPC = true }
  local function pcMenuAt(list, i)
    local row = list and list[i]
    if not (row and row.op == "special") then return false end
    local N = engine("src.core.game3.scripting.natives")
    local ok, name = pcall(N and N.specialName or error, row.id or row[1])
    return ok and PC_SPECIALS[name] == true
  end
  local function promptAt(list, i)
    local row = list and list[i]
    if not row then return false end
    if row.op == "message" then
      return list[i + 1] ~= nil and list[i + 1].op == "waitmessage" and pcMenuAt(list, i + 2)
    end
    if row.op == "waitmessage" then return pcMenuAt(list, i + 1) end
    return pcMenuAt(list, i)
  end
  -- (vm.ctx.pc.index is the row after this one by the time the hook runs)
  function Sh.skips(vm, op, row)
    if op ~= "message" and op ~= "waitmessage" and op ~= "callstd" then return false end
    local pc = vm and vm.ctx and vm.ctx.pc
    local list = pc and vm.scripts and vm.scripts[pc.listKey]
    if not list then return false end
    local i = pc.index
    if op == "message" or op == "waitmessage" then return promptAt(list, i - 1) end
    if tonumber(row and (row.std or row[1])) ~= 4 then return false end
    if pcMenuAt(list, i) then return true end
    local nxt = list[i]
    return nxt ~= nil and nxt.op == "goto" and promptAt(vm.scripts[nxt.target], 1)
  end

  -- each frame (render.hud): the once-a-second tick; the desktop or the watch drawn over the
  -- whole window, else a notification's banner over the field once the player is free
  local tickAt = -1
  function Sh.frame(game, viewport)
    local G = love and love.graphics
    local t = love and love.timer and love.timer.getTime() or 0
    if deps.tick and (t - tickAt >= 1 or t < tickAt) then
      tickAt = t
      local ok, err = pcall(deps.tick)
      if not ok and log then log:warn("the tick failed: %s", tostring(err)) end
    end
    -- (the layer taken away under it, a reset: the desktop or the watch goes too)
    local Stack = engine("src.ui.game3.stack")
    local h, id = host()
    if h and Stack and Stack.has and not Stack.has(id) then
      h.close()
      pad(false)
      h = nil
    end
    if not (G and type(viewport) == "table" and (h or Nt)) then return end
    G.push("all")
    G.origin()
    G.setScissor()
    G.setShader()
    G.setBlendMode("alpha")
    local ok, err
    if h then
      pad(true)
      ok, err = pcall(h.draw, G, viewport)
    else
      ok, err = pcall(Nt.drawField, G, viewport, Sh.free(game), t)
    end
    G.pop()
    if not ok and log then log:warn("the desktop's draw failed: %s", tostring(err)) end
  end
  -- a press, a move, a release: the one open takes it; a tap on the field's banner opens the
  -- watch on that notification's app; nil: not ours
  function Sh.pointer(ev)
    local h = host()
    if h then return h.pointer(ev) end
    if Nt and type(ev) == "table" and ev.phase == "pressed" then
      local rec = Nt.hitField(tonumber(ev.x) or 0, tonumber(ev.y) or 0)
      if rec then
        Sh.openWatch(nil, { app = rec.app, state = rec.state })
        return true
      end
    end
    return nil
  end
  -- the START menu's rows with the watch's above EXIT (the Desktop option and the Settings choice on)
  function Sh.startRows(list)
    if not (Wt and type(list) == "table" and #list > 0) then return list end
    if Sh.enabled and not Sh.enabled() then return list end
    if deps.watchRow and not deps.watchRow() then return list end
    -- (the game's own START menu only: one with SAVE in it, not a link room's or the Safari Zone's)
    local at, normal = #list, false
    for i, e in ipairs(list) do
      if e.id == "save" then normal = true end
      if (e.id == "exit" or e.id == "mods") and at == #list then at = i end
    end
    if not normal then return list end
    local label = deps.watchLabel and deps.watchLabel() or "WATCH"
    table.insert(list, at, { id = "woob_watch", label = label, onSelect = function(_, s) Sh.openWatch(s) end })
    return list
  end

  -- the hooks (at load)
  function Sh.install()
    mod.hooks:wrap("script.command", function(nxt, ctx, op, row, ...)
      if (op == "message" or op == "waitmessage" or op == "callstd") and not (Sh.enabled and not Sh.enabled()) then
        local ok, skip = pcall(Sh.skips, type(ctx) == "table" and (ctx.runner or ctx.vm), op, row)
        if ok and skip then return false end
      end
      return nxt(ctx, op, row, ...)
    end)
    mod.hooks:wrap("render.hud", function(nxt, game, viewport)
      local res = nxt(game, viewport)
      Sh.frame(game, viewport)
      return res
    end)
    mod.hooks:wrap("input.pointer", function(nxt, game, ev)
      local used = Sh.pointer(ev)
      if used ~= nil then return used end
      return nxt(game, ev)
    end)
    mod.hooks:wrap("input.wheel", function(nxt, game, dy)
      local h = host()
      if h then return h.wheel(dy) end
      return nxt(game, dy)
    end)
    -- the watch's row in the START menu, above EXIT
    mod.hooks:wrap("ui.start_menu.items", function(nxt, game, items)
      return Sh.startRows(nxt(game, items))
    end)
    return true
  end

  return Sh
end
