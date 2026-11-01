-- WoobleOS (wooble_os): the Gen 3 PC as a modern desktop.
--   src/ui_kit.lua   the drawing kit (layout on the window, cached gradients, pools, text, the W)
--   src/apps.lua     the app registry (mod.exports.apps) and the built-in apps
--   src/desktop.lua  the desktop: monitor, boot, menu bar, home grid, dock, sheets, input
--   src/shell.lua    the PC menu takeover, the UI stack layer, the render / pointer / wheel hooks

local function loadSibling(mod, name)
  local source = mod:read(name)
  if not source then
    mod.log:error("%s is missing -- reinstall the mod", name)
    return nil
  end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. name)
  if not chunk then
    mod.log:error("%s failed to compile (%s) -- reinstall the mod", name, tostring(err))
    return nil
  end
  local ok, result = pcall(chunk)
  if not ok then
    mod.log:error("%s errored while loading (%s) -- reinstall the mod", name, tostring(result))
    return nil
  end
  return result
end

return function(mod)
  -- (Gen 1 / 2: nothing to do; the loader skips the mod there unless forced on)
  if mod.generation ~= nil and mod.generation ~= 3 then return end
  local makeKit, makeApps = loadSibling(mod, "src/ui_kit.lua"), loadSibling(mod, "src/apps.lua")
  local makeDesktop, makeShell = loadSibling(mod, "src/desktop.lua"), loadSibling(mod, "src/shell.lua")
  if not (makeKit and makeApps and makeDesktop and makeShell) then return end

  local function option(key, default)
    local ok, v = pcall(function() return mod.options:get(key) end)
    if ok and v ~= nil then return v end
    return default
  end
  local version = "0.1.0"
  pcall(function()
    local m = mod.manifest
    if type(m) == "table" and m.version then version = tostring(m.version) end
  end)

  local Sh
  -- engine modules, kept: the mod's require checks every call, and the desktop asks each frame
  local engineMods = {}
  local function engine(name)
    local m = engineMods[name]
    if m ~= nil then return m or nil end
    local ok
    ok, m = pcall(require, name)
    m = ok and type(m) == "table" and m or false
    engineMods[name] = m
    return m or nil
  end
  local Kit = makeKit({
    safeArea = function()
      local SafeArea = engine("src.core.SafeArea")
      if SafeArea and SafeArea.windowRect then return SafeArea.windowRect() end
    end,
  })
  local Apps = makeApps()
  local glyphOpts = setmetatable({}, { __mode = "k" })
  local NONE = { 0, 0, 0, 0 }
  local CURRENCY_GLYPH, CURRENCY_EM, CURRENCY_DROP, CURRENCY_BOLD = 0xB7, 11, -0.04, 0.6
  local signAdvance, signAdvanceFor
  local Desktop = makeDesktop({
    kit = Kit,
    apps = Apps,
    version = version,
    se = function(name) if Sh then Sh.se(name) end end,
    now = function() return love and love.timer and love.timer.getTime() or 0 end,
    session = function()
      local Runtime = engine("src.core.game3.runtime")
      return Runtime and Runtime.getSession and Runtime.getSession() or nil
    end,
    gameId = function() return Sh and Sh.gameId() or "" end,
    options = function()
      return { boot = option("boot", true) ~= false, clock24 = option("clock24", false) == true }
    end,
    -- the device's time (the engine's reading; POKEPORT_RTC overrides it for tests)
    clock = function()
      local Rtc = engine("src.core.game3.rtc")
      if not (Rtc and Rtc.hostInfo) then return nil end
      local info = Rtc.hostInfo(nil)
      return info.hour, info.minute
    end,
    -- the game's Pokédollar sign: glyph 0xB7 of the cart's own font, as tall as a px font
    currency = function(G, x, y, px, rgba)
      local Font = engine("src.ui.game3.frlg_font")
      if not (Font and Font.drawGlyph) then return nil end
      local k = px / CURRENCY_EM
      G.push()
      G.translate(x, y + px * CURRENCY_DROP)
      G.scale(k, k)
      local opts = glyphOpts[rgba]
      if not opts then
        opts = { colors = { fg = rgba, shadow = NONE, bg = NONE } }
        glyphOpts[rgba] = opts
      end
      local adv = Font.drawGlyph(CURRENCY_GLYPH, 0, 0, opts)
      Font.drawGlyph(CURRENCY_GLYPH, CURRENCY_BOLD, 0, opts)
      G.pop()
      return ((tonumber(adv) or 7) + CURRENCY_BOLD) * k
    end,
    currencyWidth = function(px)
      local game = Sh and Sh.gameId() or ""
      if signAdvanceFor ~= game then
        local Font = engine("src.ui.game3.frlg_font")
        if not (Font and Font.advance) then return nil end
        local ok, adv = pcall(Font.advance, CURRENCY_GLYPH)
        signAdvance, signAdvanceFor = (ok and tonumber(adv) or 7) + CURRENCY_BOLD, game
      end
      return signAdvance * px / CURRENCY_EM
    end,
    log = function(fmt, ...) mod.log:warn(fmt, ...) end,
  })
  Sh = makeShell(mod, { require = require, log = mod.log, desktop = Desktop, apps = Apps })
  Sh.enabled = function() return option("desktop", true) ~= false end

  local okI, errI = pcall(Sh.install)
  if not okI then mod.log:warn("the desktop's hooks failed: %s", tostring(errI)) end
  mod.events:on("game.ready", function()
    local ok, err = pcall(Sh.ready)
    if not ok then mod.log:warn("the PC keeps its own menu: %s", tostring(err)) end
  end)
  -- (a new map or a loaded save: the next PC boots again)
  mod.events:on("map.entered", function() Sh.forget() end)
  mod.events:on("save.loaded", function() Sh.forget() end)

  -- other mods add apps: exports.apps.register{ id, label, glyph, color, order, dock, available, open }
  mod.exports.apps = { register = Apps.register, list = function() return Apps.apps end }
  mod.exports._test = { desktop = Desktop, shell = Sh, apps = Apps, kit = Kit }
end
