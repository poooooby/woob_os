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
  local makeData, makeArt = loadSibling(mod, "src/gb/data.lua"), loadSibling(mod, "src/gb/art.lua")
  local makeBx, makeInv = loadSibling(mod, "src/gb/boxes.lua"), loadSibling(mod, "src/gb/items.lua")
  local makeMb, makeHall = loadSibling(mod, "src/gb/mail.lua"), loadSibling(mod, "src/gb/hall.lua")
  local boxesWindow, boxesView = loadSibling(mod, "src/apps/boxes.lua"), loadSibling(mod, "src/apps/boxes_view.lua")
  local itemsWindow, mailWindow = loadSibling(mod, "src/apps/items.lua"), loadSibling(mod, "src/apps/mail.lua")
  local hallWindow, oakWindow = loadSibling(mod, "src/apps/hall.lua"), loadSibling(mod, "src/apps/oak.lua")
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
  -- the game's facts and its Pokémon's pictures (src/gb/data.lua, src/gb/art.lua)
  local Gd = makeData and makeData(Host) or nil
  local Art = Gd and makeArt and makeArt(Host, Gd, Kit) or nil

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
  if Gd then
    env.gd = Gd
    env.itemName = Gd.itemName
    env.typeName = function(t) return Gd.typeName(t) end
    -- a species' icon (frame 0 / 1, tinted r, g, b, a), a Pokémon's own, a species' front picture
    env.monIcon = function(sp, x, y, size, frame, r, g, b, a) if Art then Art.drawIcon(sp, x, y, size, frame, r, g, b, a) end end
    env.monIconOf = function(mon, x, y, size, frame, a)
      if Art and type(mon) == "table" then Art.drawIcon(mon.species, x, y, size, frame, 1, 1, 1, a, mon) end
    end
    env.monPic = function(sp, x, y, size, a, mon) return Art ~= nil and Art.drawPic(sp, x, y, size, a, mon) end
  end
  -- an item's picture: the Game Boy games have none, so a tile in its pocket's colour with one of the
  -- desktop's pictures on it (a TM in its move's type's colour)
  local POCKET_TILE = { ITEM = { { 88, 140, 220 }, "bag" }, BALL = { { 226, 70, 72 }, "pokeball" },
                        KEY_ITEM = { { 232, 168, 32 }, "medal" }, TM_HM = { { 140, 120, 200 }, "cube" },
                        MAIL = { { 64, 178, 236 }, "send" } }
  local TYPE_TILE = {
    [0] = { 168, 168, 120 }, [1] = { 192, 48, 40 }, [2] = { 168, 144, 240 }, [3] = { 160, 64, 160 },
    [4] = { 224, 192, 104 }, [5] = { 184, 160, 56 }, [6] = { 168, 184, 32 }, [7] = { 112, 88, 152 },
    [8] = { 184, 184, 208 }, [10] = { 240, 128, 48 }, [11] = { 104, 144, 240 }, [12] = { 120, 200, 80 },
    [13] = { 248, 208, 48 }, [14] = { 248, 88, 136 }, [15] = { 152, 216, 216 }, [16] = { 112, 56, 248 },
    [17] = { 112, 88, 72 },
  }
  local tileOf = {}
  local Desktop
  env.itemIcon = function(id, x, y, size, a)
    if not Gd then return end
    local t = tileOf[id]
    if not t then
      local it = Gd.item(id)
      local pocket = it and it.pocket or (Gd.gen == 1 and ((it and it.keyItem) and "KEY_ITEM" or
        (tostring(id):match("^[TH]M_") and "TM_HM") or (tostring(id):match("BALL$") and "BALL") or "ITEM")) or "ITEM"
      if tostring(id):find("MAIL", 1, true) then pocket = "MAIL" end
      local base = POCKET_TILE[pocket] or POCKET_TILE.ITEM
      local colour = base[1]
      if pocket == "TM_HM" then
        local move = it and (it.teaches or (it.machine and it.machine.move))
        local d = Gd.data()
        local mv = move and d and d.moves and d.moves[move]
        colour = mv and TYPE_TILE[Gd.typeId(mv.type)] or colour
      end
      t = { colour = colour, glyph = base[2] }
      tileOf[id] = t
    end
    local G = Kit.graphics()
    local b = Kit.R(x + size * 0.06, y + size * 0.06, size * 0.88, size * 0.88)
    Kit.col(t.colour, a)
    Kit.box("fill", b, size * 0.24)
    if Desktop and Desktop.glyph then
      pcall(Desktop.glyph, G, t.glyph, Kit.X(x + size / 2), Kit.Y(y + size / 2), size * Kit.sc * 0.62, a or 1, t.colour)
    end
  end
  env.inv = Gd and makeInv and makeInv(Host, Gd) or nil
  env.bx = Gd and makeBx and makeBx(Host, Gd, Art, { save = mod.save }) or nil
  env.mb = Gd and Host.gen == 2 and makeMb and makeMb(Host, Gd) or nil
  if Gd and makeHall then env.hall, env.oak = makeHall(Host, Gd) end

  local Nt, Watch
  local Apps = makeApps({
    icons = Icons,
    store = storeWindow,
    removed = Settings and function() return Settings.get("removedApps", "") end or nil,
    saveRemoved = Settings and function(text) Settings.set("removedApps", text) end or nil,
    boxes = env.bx and boxesWindow and boxesView
      and function(ctx, e) return boxesWindow(ctx, e, boxesView) end or nil,
    items = env.inv and itemsWindow or nil,
    mail = env.mb and mailWindow or nil,
    hall = env.hall and hallWindow or nil,
    oak = env.oak and oakWindow or nil,
    oakAvailable = env.oak and function(ctx) return env.oak.available(ctx.session or session()) end or nil,
    hallTeams = env.hall and function(ctx) return env.hall.count(ctx.session or session()) end or nil,
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
  mod.exports._test = { desktop = Desktop, shell = Sh, apps = Apps, kit = Kit, env = env, i18n = T, gd = Gd, art = Art,
                        bx = env.bx, inv = env.inv, mb = env.mb, hall = env.hall, oak = env.oak,
                        settings = Settings, wall = Wall, arrange = Arrange, watch = Watch, pad = Watch,
                        notify = Nt, tick = tick, townmap = TownMap, host = Host }
end
