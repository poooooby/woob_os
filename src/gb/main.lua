-- WoobOS on the Game Boy games: Red / Blue / Yellow (Gen 1) and Gold / Silver / Crystal (Gen 2). The same
-- kit, desktop, WoobPad, notifications and app windows as Gen 3 (main.lua), over these games' own models
-- (src/gb/*.lua: their save tables, data, sounds and pictures) and host (src/gb/host.lua: their screen stack
-- and PC takeover), handed to the shell (src/shell.lua) as deps.host.
--
--   gb(mod, loadSibling)   called from main.lua when mod.generation is 1 or 2

return function(mod, loadSibling)
  local gen = mod.generation == 1 and 1 or 2
  local makeKit, makeApps = loadSibling(mod, "src/ui_kit.lua"), loadSibling(mod, "src/apps.lua")
  local makeDesktop, makeShell = loadSibling(mod, "src/desktop.lua"), loadSibling(mod, "src/shell.lua")
  local makeHost = loadSibling(mod, "src/gb/host.lua")
  local makeI18n, makeSettings = loadSibling(mod, "src/i18n.lua"), loadSibling(mod, "src/settings.lua")
  local makeWall, settingsWindow = loadSibling(mod, "src/wallpaper.lua"), loadSibling(mod, "src/apps/settings.lua")
  local Arrange = loadSibling(mod, "src/arrange.lua")
  local makeNotify = loadSibling(mod, "src/notify.lua")
  local makeNotes, makeFrost = loadSibling(mod, "src/notes.lua"), loadSibling(mod, "src/frost.lua")
  local Icons = loadSibling(mod, "src/icons.lua")
  local storeWindow = loadSibling(mod, "src/apps/appstore.lua")
  local makeTownMap = loadSibling(mod, "src/townmap.lua")
  if not (makeKit and makeApps and makeDesktop and makeShell and makeHost) then return end

  local function warn(fmt, ...) mod.log:warn(fmt, ...) end
  local T = makeI18n and makeI18n({
    read = function(path) return mod:read(path) end,
    list = function(dir) return mod:list(dir) end,
    log = warn,
  })
  local Settings = T and makeSettings and makeSettings({ cache = mod.cache, loadData = T.loadData, log = warn })
  if T and Settings then T.set(Settings.get("language", "en")) end

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
  local Host = makeHost(mod, { gen = gen, require = require, log = mod.log,
                               enabled = function() return option("desktop", true) ~= false end })
  local engine = Host.engine
  local FALLBACK_FONT = "assets/fonts/plainpixel/PlainPixel-Regular.ttf"
  local fallbackFonts, fallbackMissing = {}, false
  local Kit = makeKit({
    safeArea = function()
      local SafeArea = engine("src.core.SafeArea")
      if SafeArea and SafeArea.windowRect then return SafeArea.windowRect() end
    end,
    fallback = function(font, px, exact)
      if fallbackMissing or not font.setFallbacks then return end
      local size = math.max(6, math.floor(px + 0.5))
      local key = exact and -size or size
      local f = fallbackFonts[key]
      if not f then
        local ok, made
        if exact then
          ok, made = pcall(love.graphics.newFont, FALLBACK_FONT, size, "normal", 1)
        else
          ok, made = pcall(love.graphics.newFont, FALLBACK_FONT, size)
        end
        if not (ok and made) then
          fallbackMissing = true
          return
        end
        f = made
        fallbackFonts[key] = f
      end
      pcall(font.setFallbacks, font, f)
    end,
  })
  local gameId = Host.gameId
  local session = Host.session

  local Wall = makeWall and makeWall({
    K = Kit, gameId = gameId,
    list = function(dir) return mod:list(dir) end,
    image = function(path) return mod.assets:image(path) end,
    log = warn,
  })
  local function wallpaper() return Settings and Settings.get("wallpaper", "classic") or "classic" end
  local function wallpaperFit() return Settings and Settings.get("wallpaperFit", "fill") or "fill" end
  local env = {
    K = Kit, session = session, now = function() return love and love.timer and love.timer.getTime() or 0 end,
    se = function(name) Host.se(name) end, gen = gen, host = Host,
    prewarm = function() end,
    T = T, wall = Wall, gameId = gameId, wallpaper = wallpaper,
    language = function() return T and T.code() or "en" end,
    setLanguage = function(code)
      if T and T.set(code) and Settings then Settings.set("language", code) end
    end,
    setWallpaper = function(id) if Settings then Settings.set("wallpaper", id) end end,
    wallpaperFit = wallpaperFit,
    setWallpaperFit = function(fit) if Settings then Settings.set("wallpaperFit", fit) end end,
    setting = function(key, default)
      if not Settings then return default end
      return Settings.get(key, default)
    end,
    setSetting = function(key, v) if Settings then Settings.set(key, v) end end,
  }

  local Nt, Desktop, Watch
  local Apps = makeApps({
    icons = Icons,
    store = storeWindow,
    settings = T and Settings and settingsWindow or nil,
  })
  Nt = makeNotify and makeNotify({
    K = Kit, T = T, now = env.now, epoch = os.time, se = env.se, apps = Apps,
    glyph = function(...) if Desktop then return Desktop.glyph(...) end end,
    enabled = function() return not Settings or Settings.get("notifications", true) ~= false end,
    setting = function(key, default)
      if not Settings then return default end
      return Settings.get(key, default)
    end,
  }) or nil
  env.notifications = Nt and { apps = Nt.APPS, setting = Nt.SETTING } or nil
  local deskDeps = ({
    kit = Kit, apps = Apps, icons = Icons, version = version, se = env.se, now = env.now,
    session = session, gameId = gameId, env = env,
    T = T, wall = Wall, wallpaper = wallpaper, wallpaperFit = wallpaperFit,
    arrange = Arrange,
    layout = function()
      if not Settings then return nil, nil end
      return Settings.get("dockApps", nil), Settings.get("homeApps", nil)
    end,
    saveLayout = function(dockText, gridText)
      if not Settings then return end
      Settings.set("dockApps", dockText)
      Settings.set("homeApps", gridText)
    end,
    options = function()
      return { boot = option("boot", true) ~= false, clock24 = option("clock24", false) == true }
    end,
    -- the device's time, once a second
    clock = function()
      local t = os.date("*t")
      return t.hour, t.min
    end,
    log = function(fmt, ...) mod.log:warn(fmt, ...) end,
    notify = Nt,
    notes = makeNotes,
    frost = makeFrost,
  })
  Desktop = makeDesktop(deskDeps)
  Watch = makeDesktop(setmetatable({ device = "pad" }, { __index = deskDeps }))
  local TownMap = makeTownMap and makeTownMap({
    kit = Kit, T = T, env = env, se = env.se, log = function(fmt, ...) mod.log:warn(fmt, ...) end,
  }) or nil
  env.pad = { transfer = function(id, dir, kind)
    if Desktop.isOpen() then Desktop.padTransfer(id, dir, kind) end
  end }
  env.apps = Apps
  env.appIcon = function(app, x, y, size) Desktop.appIcon(app, x, y, size) end
  env.glyph = Desktop.glyph
  env.amount = function(n, x, y, size, c, measure) return Desktop.amount(n, x, y, size, c, measure) end

  local function tick() end

  Sh = makeShell(mod, { require = require, log = mod.log, desktop = Desktop, apps = Apps, watch = Watch,
                        notify = Nt, tick = tick, session = session, townmap = TownMap, host = Host,
                        watchRow = function() return not Settings or Settings.get("watchRow", true) ~= false end,
                        watchLabel = function() return T and T("watch.start") or "WATCH" end })
  Sh.enabled = function() return option("desktop", true) ~= false end

  Host.install()
  local okI, errI = pcall(Sh.install)
  if not okI then mod.log:warn("the desktop's hooks failed: %s", tostring(errI)) end
  mod.events:on("game.ready", function(ev)
    if ev and ev.game then Host.bind(ev.game) end
    local ok, err = pcall(Sh.ready)
    if not ok then mod.log:warn("the PC keeps its own menu: %s", tostring(err)) end
  end)
  mod.events:on("map.entered", function() Sh.forget() end)
  mod.events:on("save.loaded", function() Sh.forget() end)

  mod.exports.apps = {
    register = function(app)
      if type(app) == "table" then app.removable, app.fromMod = true, true end
      local ok, why = Apps.register(app)
      if not ok then mod.log:warn("an app wasn't added: %s", tostring(why)) end
      return ok, why
    end,
    list = function() return Apps.apps end,
    icons = Apps.icons,
  }
  mod.exports._test = { desktop = Desktop, shell = Sh, apps = Apps, kit = Kit, env = env, i18n = T,
                        settings = Settings, wall = Wall, arrange = Arrange, watch = Watch, pad = Watch,
                        notify = Nt, tick = tick, townmap = TownMap, host = Host }
end
