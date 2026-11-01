-- The shell: puts the desktop (src/desktop.lua) where the game's PC menu was. No engine edits:
--   - the game's PC scripts open their menu through src.ui.game3.pc_menu's show(opts) at the time
--     they run (scripting/adapters.lua openPc), so wrapping that one function catches a Pokémon
--     Center PC's menu (startMode "select") and the player's bedroom PC (opts.bedroom). Every other
--     way in (the storage menu, the player's PC menu the scripts open after a choice) goes to the
--     game's own menu as before. The PC's turn-on flicker and sounds stay the game's.
--   - script.command skips the game's "booted up the PC" and "Which PC should be accessed?" lines
--     in front of those two menus (the boot does their job); with the Desktop option off they stay
--   - the wrapper is installed once per process on the module (PcMenu.__woobleOs) and calls the
--     current mod instance's `impl`, so loading the mod again (another game) never wraps it twice
--   - the desktop is a Gen 3 UI stack layer (it takes the buttons, holds the script) drawn over the
--     whole window from render.hud; taps and clicks from input.pointer, the wheel from input.wheel;
--     the on-screen touch pad is put away while it is up and put back as it was
--   - an app hands the game's script the menu row the game's own list has for it (pc_menu's
--     _rootEntries: FireRed / LeafGreen storage, player, Oak, Hall of Fame, log off; Ruby /
--     Sapphire / Emerald storage, player, Hall of Fame, log off), so the script runs on exactly as
--     if the row was chosen, and comes back to the PC menu - the desktop again, without the boot
--
--   Sh = shell(mod, deps)   deps: require ; log ; desktop (made) ; apps (made) ; kitDeps
--   Sh.install() (load: the hooks) ; Sh.ready() (game.ready: the PC menu wrap) ; Sh.layer

return function(mod, deps)
  local req = deps.require or require
  local log = deps.log
  local D, A = deps.desktop, deps.apps
  local Sh = { LAYER_ID = "wooble_os" }

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

  -- the on-screen touch pad: put away while the desktop is up, back as it was after
  local padPrev, padHidden = nil, false
  local function pad(hide)
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

  local function push()
    local Stack = engine("src.ui.game3.stack")
    if not Stack then return false end
    local ok, err = pcall(Stack.push, Sh.LAYER_ID, Layer, { hideBelow = true, fullscreen = true })
    if not ok then
      if log then log:warn("the desktop could not open: %s", tostring(err)) end
      return false
    end
    pad(true)
    return true
  end
  local function pop()
    local Stack = engine("src.ui.game3.stack")
    if Stack and Stack.has and Stack.has(Sh.LAYER_ID) then pcall(Stack.pop, Sh.LAYER_ID) end
    pad(false)
  end

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
    -- back (no boot, the app's icon zooming back) when it closes
    function ctx.over(open)
      D.close()
      pop()
      local back = ctx.app
      local function reopen()
        if closed then return end
        ctx.warm, ctx.back = true, back
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

  -- the wrap of pc_menu.show: once per process, calling this instance
  function Sh.ready()
    local PcMenu = engine("src.ui.game3.pc_menu")
    if not (PcMenu and type(PcMenu.show) == "function") then
      if log then log:warn("the game's PC menu wasn't found: the PC keeps its own menu") end
      return false
    end
    local w = rawget(PcMenu, "__woobleOs")
    if not w then
      w = { orig = PcMenu.show }
      PcMenu.__woobleOs = w
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
      -- (the layer taken away under it, a reset: the desktop goes too)
      local Stack = engine("src.ui.game3.stack")
      if D.isOpen() and Stack and Stack.has and not Stack.has(Sh.LAYER_ID) then
        D.close()
        pad(false)
      end
      if D.isOpen() then
        local G = love and love.graphics
        if G and type(viewport) == "table" then
          pad(true)
          G.push("all")
          G.origin()
          G.setScissor()
          G.setShader()
          G.setBlendMode("alpha")
          local ok, err = pcall(D.draw, G, viewport)
          G.pop()
          if not ok and log then log:warn("the desktop's draw failed: %s", tostring(err)) end
        end
      end
      return res
    end)
    mod.hooks:wrap("input.pointer", function(nxt, game, ev)
      if D.isOpen() then return D.pointer(ev) end
      return nxt(game, ev)
    end)
    mod.hooks:wrap("input.wheel", function(nxt, game, dy)
      if D.isOpen() then return D.wheel(dy) end
      return nxt(game, dy)
    end)
    return true
  end

  return Sh
end
