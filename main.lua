-- WoobleOS (wooble_os): the Gen 3 PC as a modern desktop.
--   src/ui_kit.lua   the drawing kit (layout on the window, cached gradients, pools, text, the W)
--   src/apps.lua     the app registry (mod.exports.apps) and the built-in apps
--   src/desktop.lua  the desktop: monitor, boot, menu bar, home grid, dock, sheets, input
--   src/shell.lua    the PC menu takeover, the UI stack layer, the render / pointer / wheel hooks
--   src/inventory.lua, src/mailbox.lua   the item and mail models (the engine's Storage, Bag, Mail)
--   src/apps/items.lua, src/apps/mail.lua the Items (Bag | PC) and Mail (inbox) windows
--   src/apps/settings.lua               the Settings window (Language, Wallpaper)
--   src/i18n.lua, lang/*.lua            the words, by language ; src/settings.lua the kept choices
--   src/wallpaper.lua                   the drawn wallpapers and the wallpapers/ folder's pictures

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
  local makeInv, makeMb = loadSibling(mod, "src/inventory.lua"), loadSibling(mod, "src/mailbox.lua")
  local itemsWindow, mailWindow = loadSibling(mod, "src/apps/items.lua"), loadSibling(mod, "src/apps/mail.lua")
  local makeI18n, makeSettings = loadSibling(mod, "src/i18n.lua"), loadSibling(mod, "src/settings.lua")
  local makeWall, settingsWindow = loadSibling(mod, "src/wallpaper.lua"), loadSibling(mod, "src/apps/settings.lua")
  if not (makeKit and makeApps and makeDesktop and makeShell) then return end

  local function warn(fmt, ...) mod.log:warn(fmt, ...) end
  -- the words (lang/*.lua) and the Settings app's kept choices (mod.cache: the installation's)
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
  local FALLBACK_FONT = "assets/fonts/plainpixel/PlainPixel-Regular.ttf"
  local fallbackFonts, fallbackMissing = {}, false
  local Kit = makeKit({
    safeArea = function()
      local SafeArea = engine("src.core.SafeArea")
      if SafeArea and SafeArea.windowRect then return SafeArea.windowRect() end
    end,
    -- (what the default face can't draw, kana and CJK for Japanese among it, comes from the
    -- engine's own Plain Pixel face, as its launcher does it; Latin keeps its look. At the font's
    -- own size, not snapped to Plain Pixel's 15 px grid as the launcher does: snapped, kana came
    -- out half the size of the words around them at some sizes)
    fallback = function(font, px)
      if fallbackMissing or not font.setFallbacks then return end
      local size = math.max(6, math.floor(px + 0.5))
      local f = fallbackFonts[size]
      if not f then
        local ok, made = pcall(love.graphics.newFont, FALLBACK_FONT, size)
        if not (ok and made) then
          fallbackMissing = true
          return
        end
        f = made
        fallbackFonts[size] = f
      end
      pcall(font.setFallbacks, font, f)
    end,
  })
  local function gameId() return Sh and Sh.gameId() or "" end
  local function frlg()
    local g = gameId()
    return g == "firered" or g == "leafgreen"
  end
  local function session()
    local Runtime = engine("src.core.game3.runtime")
    return Runtime and Runtime.getSession and Runtime.getSession() or nil
  end
  -- the game's own item icon (24 px art), `size` units square at x, y (units), alpha `a`; FireRed / LeafGreen's
  -- images kept here (the engine's lookup makes garbage every call)
  local frlgIcons, rseSheet, rseQuads = {}, nil, {}
  local function itemIcon(id, x, y, size, a)
    local G = Kit.graphics()
    local k = size * Kit.sc / 24
    if frlg() then
      local img = frlgIcons[id]
      if img == nil then
        local Chrome = engine("src.ui.game3.bag_chrome")
        local ok, got = pcall(Chrome and Chrome.iconImage or error, id)
        img = ok and got or false
        frlgIcons[id] = img
      end
      if img then
        G.setColor(1, 1, 1, a or 1)
        G.draw(img, Kit.X(x), Kit.Y(y), 0, k, k)
      end
      return
    end
    -- (Ruby / Sapphire / Emerald: one sheet of 24 px icons, by item id; its quads kept here)
    if rseSheet == nil then
      local Chrome, SceneKit = engine("src.ui.game3.rse.bag_chrome"), engine("src.ui.game3.rse.scene_kit")
      local ok, m = pcall(Chrome and Chrome.manifest or error)
      local icons = ok and m and m.icons
      local img = icons and SceneKit and SceneKit.rgbaImage(icons.rgba, icons.w, icons.h)
      rseSheet = img and { img = img, count = icons.count, w = icons.w, h = icons.h } or false
    end
    if not rseSheet then return end
    local n = tonumber(id) or 0
    if n < 0 or n >= rseSheet.count then n = rseSheet.count - 1 end
    local q = rseQuads[n]
    if not q then
      q = love.graphics.newQuad(0, n * 24, 24, 24, rseSheet.w, rseSheet.h)
      rseQuads[n] = q
    end
    G.setColor(1, 1, 1, a or 1)
    G.draw(rseSheet.img, q, Kit.X(x), Kit.Y(y), 0, k, k)
  end
  -- a Pokémon's menu icon (its first frame), `size` units square (the engine keeps the images;
  -- a species without one is remembered, not looked for every frame)
  local noIcon = {}
  local function monIcon(species, x, y, size)
    if noIcon[species] then return end
    local P = engine("src.core.game3.pokemon")
    local e = P and P.icon and P.icon(species)
    if not (e and e.image and e.quads) then
      noIcon[species] = true
      return
    end
    local G = Kit.graphics()
    G.setColor(1, 1, 1, 1)
    G.draw(e.image, e.quads[0], Kit.X(x), Kit.Y(y), 0, size * Kit.sc / e.w, size * Kit.sc / e.h)
  end
  local Wall = makeWall and makeWall({
    gameId = gameId,
    list = function(dir) return mod:list(dir) end,
    image = function(path) return mod.assets:image(path) end,
    log = warn,
  })
  local function wallpaper() return Settings and Settings.get("wallpaper", "classic") or "classic" end
  -- (a picture of the player's: "fill" covers the screen, cropped; "stretch" shows all of it)
  local function wallpaperFit() return Settings and Settings.get("wallpaperFit", "fill") or "fill" end
  local env = {
    K = Kit, session = session, now = function() return love and love.timer and love.timer.getTime() or 0 end,
    se = function(name) if Sh then Sh.se(name) end end, itemIcon = itemIcon, monIcon = monIcon,
    inv = makeInv and makeInv(engine), mb = makeMb and makeMb(engine),
    T = T, wall = Wall, gameId = gameId, wallpaper = wallpaper,
    language = function() return T and T.code() or "en" end,
    setLanguage = function(code)
      if T and T.set(code) and Settings then Settings.set("language", code) end
    end,
    setWallpaper = function(id) if Settings then Settings.set("wallpaper", id) end end,
    wallpaperFit = wallpaperFit,
    setWallpaperFit = function(fit) if Settings then Settings.set("wallpaperFit", fit) end end,
  }
  local Apps = makeApps({
    items = env.inv and itemsWindow or nil,
    mail = env.mb and mailWindow or nil,
    settings = T and Settings and settingsWindow or nil,
    -- (Ruby / Sapphire / Emerald: the bedroom PC's Decoration, the game's own menu)
    decorate = function(ctx)
      ctx.over(function(onClose)
        local Rse = engine("src.core.game3.rse.init")
        local impl = Rse and Rse.system and Rse.system("decorationMenu", "DoPlayerRoomDecorationMenu")
        if not (impl and impl.open) then error("the game has no Decoration menu") end
        impl.open({ session = ctx.session or session(), onClose = onClose })
      end)
    end,
  })
  local glyphOpts = setmetatable({}, { __mode = "k" })
  local NONE = { 0, 0, 0, 0 }
  local CURRENCY_GLYPH, CURRENCY_EM, CURRENCY_DROP, CURRENCY_BOLD = 0xB7, 11, -0.04, 0.6
  local signAdvance, signAdvanceFor
  local Desktop = makeDesktop({
    kit = Kit,
    apps = Apps,
    version = version,
    se = env.se,
    now = env.now,
    session = session,
    gameId = gameId,
    env = env,
    T = T, wall = Wall, wallpaper = wallpaper, wallpaperFit = wallpaperFit,
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
  -- the shelf's item pad, for the apps: an item crossing it ("out" to the PC, "in" to the Bag)
  env.pad = { transfer = function(id, dir) Desktop.padTransfer(id, dir) end }
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

  -- other mods add apps: exports.apps.register{ id, label, glyph, color, order, dock, available,
  -- open | window }
  mod.exports.apps = { register = Apps.register, list = function() return Apps.apps end }
  mod.exports._test = { desktop = Desktop, shell = Sh, apps = Apps, kit = Kit, inv = env.inv, mb = env.mb,
                        env = env, i18n = T, settings = Settings, wall = Wall }
end
