-- WoobOS (woob_os): the Gen 3 PC as a modern desktop.
--   src/ui_kit.lua   the drawing kit (layout on the window, cached gradients, pools, text, the W)
--   src/apps.lua     the app registry (mod.exports.apps) and the built-in apps
--   src/desktop.lua  the desktop: monitor, boot, menu bar, home grid, dock, sheets, input
--   src/shell.lua    the PC menu takeover, the UI stack layer, the render / pointer / wheel hooks
--   src/inventory.lua, src/mailbox.lua   the item and mail models (the engine's Storage, Bag, Mail)
--   src/apps/items.lua, src/apps/mail.lua the Items (Bag | PC) and Mail (inbox) windows
--   src/apps/settings.lua               the Settings window (Language, Wallpaper)
--   src/mart.lua, src/apps/mart.lua     the shop model (badge-gated stock, buy, sell), the Mart window
--   src/auction.lua, src/apps/auction.lua   R-Bay: the auction market (worked out from a seed and the
--                                       clock; the player's bids in the save), its window
--   src/slots.lua, src/apps/slots.lua   Rocket Slots: the machine, its tickets and prize corner, its window
--   src/gts.lua, src/apps/gts.lua       the GTS: Wonder Trade and the Global Trade Station, its window
--   src/boxes.lua, src/apps/boxes.lua, src/apps/boxes_view.lua   the Pokémon model, the Boxes window
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
  local makeBx, boxesWindow = loadSibling(mod, "src/boxes.lua"), loadSibling(mod, "src/apps/boxes.lua")
  local boxesView = loadSibling(mod, "src/apps/boxes_view.lua")
  local Arrange = loadSibling(mod, "src/arrange.lua")
  local makeMart, martWindow = loadSibling(mod, "src/mart.lua"), loadSibling(mod, "src/apps/mart.lua")
  local makeAuction, auctionWindow = loadSibling(mod, "src/auction.lua"), loadSibling(mod, "src/apps/auction.lua")
  local makeSlots, slotsWindow = loadSibling(mod, "src/slots.lua"), loadSibling(mod, "src/apps/slots.lua")
  local makeGts, gtsWindow = loadSibling(mod, "src/gts.lua"), loadSibling(mod, "src/apps/gts.lua")
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
  -- an item the game has no picture for (another mod's: WoobDex's Exp. Candies, Dynamax Candy,
  -- Max Mushrooms ...): the Bag's own drawItemIcon, which such a mod wraps to draw its items,
  -- painted once into a 24 px canvas and kept (false: nobody drew it)
  local modIcons = {}
  local function modIcon(id, rse)
    local got = modIcons[id]
    if got ~= nil then return got end
    got = false
    local G = love and love.graphics
    local Chrome = engine(rse and "src.ui.game3.rse.bag_chrome" or "src.ui.game3.bag_chrome")
    local okC, canvas = pcall(G and G.newCanvas or error, 24, 24)
    if okC and canvas and Chrome and Chrome.drawItemIcon then
      G.push("all")
      local ok, drawn = pcall(function()
        G.setCanvas(canvas)
        G.origin()
        G.setScissor()
        G.clear(0, 0, 0, 0)
        if rse then
          Chrome.drawItemIcon(id, 0, 0)
          return true
        end
        return Chrome.drawItemIcon(id, 0, 0, 1)
      end)
      G.pop()
      local okD, data = false, nil
      if ok and drawn then okD, data = pcall(canvas.newImageData, canvas) end
      if okD and data then
        for py = 0, 23 do
          for px = 0, 23 do
            local _, _, _, alpha = data:getPixel(px, py)
            if alpha > 0 then got = canvas break end
          end
          if got then break end
        end
      end
      if got then pcall(canvas.setFilter, canvas, "nearest", "nearest") end
    end
    modIcons[id] = got
    return got
  end
  local function itemIcon(id, x, y, size, a)
    local G = Kit.graphics()
    local k = size * Kit.sc / 24
    if frlg() then
      local img = frlgIcons[id]
      if img == nil then
        local Chrome = engine("src.ui.game3.bag_chrome")
        local ok, got = pcall(Chrome and Chrome.iconImage or error, id)
        img = ok and got or false
        if not img then img = modIcon(id, false) end
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
    if n < 0 or n >= rseSheet.count then
      local img = modIcon(id, true)
      if img then
        G.setColor(1, 1, 1, a or 1)
        G.draw(img, Kit.X(x), Kit.Y(y), 0, k, k)
        return
      end
      n = rseSheet.count - 1
    end
    local q = rseQuads[n]
    if not q then
      q = love.graphics.newQuad(0, n * 24, 24, 24, rseSheet.w, rseSheet.h)
      rseQuads[n] = q
    end
    G.setColor(1, 1, 1, a or 1)
    G.draw(rseSheet.img, q, Kit.X(x), Kit.Y(y), 0, k, k)
  end
  -- a Pokémon's menu icon (its first frame), `size` units square (kept per species: the engine's
  -- lookup makes garbage every call; a species without one is remembered too)
  local iconFor = {}
  local function monIcon(species, x, y, size)
    local e = iconFor[species]
    if e == nil then
      local P = engine("src.core.game3.pokemon")
      local ok, got = pcall(P and P.icon or error, species)
      e = ok and type(got) == "table" and got.image and got.quads and got or false
      iconFor[species] = e
    end
    if not e then return end
    local G = Kit.graphics()
    G.setColor(1, 1, 1, 1)
    G.draw(e.image, e.quads[0], Kit.X(x), Kit.Y(y), 0, size * Kit.sc / e.w, size * Kit.sc / e.h)
  end
  -- a Pokémon's own menu icon (eggs, forms), `size` units square, frame 0 / 1, alpha a (kept per
  -- Pokémon: the engine's lookup builds names)
  local iconOf = setmetatable({}, { __mode = "k" })
  local function monIconOf(mon, x, y, size, frame, a)
    local e = iconOf[mon]
    if e == nil then
      local P = engine("src.core.game3.pokemon")
      local ok, got = pcall(P and P.monIcon or error, mon)
      e = ok and type(got) == "table" and got.image and got.quads and got or false
      iconOf[mon] = e
    end
    if not e then return end
    local q = e.quads[frame or 0] or e.quads[0]
    if not q then return end
    local G = Kit.graphics()
    G.setColor(1, 1, 1, a or 1)
    G.draw(e.image, q, Kit.X(x), Kit.Y(y), 0, size * Kit.sc / e.w, size * Kit.sc / (e.h or e.w))
  end
  -- a box's wallpaper, the game's own picture covering x, y, w, h (units) -> true when drawn. The
  -- picture (160 x 144) is the box-name banner over the framed panel the Pokémon sit on: inside
  -- the panel's frame only (our header has the name, our bezel is the frame), a quad kept per picture
  local PANEL = { 8 / 160, 32 / 144, 142 / 160, 104 / 144 }
  local panels = setmetatable({}, { __mode = "k" })
  local function boxWall(id, x, y, w, h)
    local Chrome = engine("src.ui.game3.pc_chrome")
    if not Chrome then return false end
    local ok = pcall(Chrome.ensure)
    local img = ok and Chrome._wallpapers and Chrome._wallpapers[tonumber(id) or 1]
    if not img then return false end
    local G = Kit.graphics()
    local q = panels[img]
    if not q then
      local iw, ih = img:getDimensions()
      q = { quad = love.graphics.newQuad(PANEL[1] * iw, PANEL[2] * ih, PANEL[3] * iw, PANEL[4] * ih, iw, ih),
            w = PANEL[3] * iw, h = PANEL[4] * ih }
      panels[img] = q
    end
    local px, py, pw, ph = Kit.X(x), Kit.Y(y), w * Kit.sc, h * Kit.sc
    local k = math.max(pw / q.w, ph / q.h)
    local sx, sy, sw, sh = G.getScissor()
    G.intersectScissor(math.floor(px), math.floor(py), math.ceil(pw), math.ceil(ph))
    G.setColor(1, 1, 1, 1)
    G.draw(img, q.quad, px + (pw - q.w * k) / 2, py + (ph - q.h * k) / 2, 0, k, k)
    if sx then G.setScissor(sx, sy, sw, sh) else G.setScissor() end
    return true
  end
  local function boxWallCount()
    local Chrome = engine("src.ui.game3.pc_chrome")
    local ok, names = pcall(function()
      Chrome.ensure()
      return Chrome.wallpaperNames()
    end)
    return ok and type(names) == "table" and #names > 0 and #names or 16
  end
  -- a species' front picture (64 px), `size` units square at x, y -> true when drawn (kept per species)
  local pics = {}
  local function monPic(species, x, y, size, a)
    local pic = pics[species]
    if pic == nil then
      local P = engine("src.core.game3.pokemon")
      local ok, got = pcall(P and P.monFrontPic or error, { species = species }, nil, "box")
      pic = ok and type(got) == "table" and got.image and got or false
      pics[species] = pic
    end
    if not pic then return false end
    local G = Kit.graphics()
    local k = size * Kit.sc / (pic.w or 64)
    G.setColor(1, 1, 1, a or 1)
    G.draw(pic.image, Kit.X(x), Kit.Y(y), 0, k, k)
    return true
  end
  local function itemName(id)
    local I = engine("src.core.game3.items_data")
    local ok, name = pcall(I and I.displayName or error, id)
    return ok and name and tostring(name) or tostring(id)
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
    inv = makeInv and makeInv(engine), mb = makeMb and makeMb(engine), bx = makeBx and makeBx(engine),
    mart = makeMart and makeMart(engine),
    monIconOf = monIconOf, monPic = monPic, boxWall = boxWall, boxWallCount = boxWallCount, itemName = itemName,
    T = T, wall = Wall, gameId = gameId, wallpaper = wallpaper,
    language = function() return T and T.code() or "en" end,
    setLanguage = function(code)
      if T and T.set(code) and Settings then Settings.set("language", code) end
    end,
    setWallpaper = function(id) if Settings then Settings.set("wallpaper", id) end end,
    wallpaperFit = wallpaperFit,
    setWallpaperFit = function(fit) if Settings then Settings.set("wallpaperFit", fit) end end,
  }
  -- R-Bay's market: this save's seed (its playthrough), the device's clock, WoobleDex's species
  if makeAuction then
    env.auction = makeAuction(engine, {
      save = mod.save,
      now = os.time,
      seed = function(s)
        local id = s and s.meta and s.meta.playthroughId
        if type(id) == "string" and id ~= "" then
          local h = 0
          for i = 1, #id do h = (h * 131 + id:byte(i)) % 2147483647 end
          return h
        end
        return (tonumber(s and s.trainerId) or 0) * 65536 + (tonumber(s and s.secretId) or 0) + 1
      end,
      dex = function() return mod.find("national_dex_gen3") end,
      badges = function(s) return env.mart and env.mart.badges(s) or 0 end,
    })
  end
  -- Rocket Slots: its tickets kept in the save; a Pokémon prize's level from the badges
  if makeSlots then
    env.slots = makeSlots(engine, {
      save = mod.save,
      badges = function(s) return env.mart and env.mart.badges(s) or 0 end,
    })
  end
  -- the GTS: strangers' Pokémon (R-Bay's species and tiers), the deposit kept in the save
  if makeGts and env.auction and env.bx then
    env.gts = makeGts(engine, {
      save = mod.save,
      now = os.time,
      seed = function(s) return env.auction and env.auction.seedOf and env.auction.seedOf(s) or 1 end,
      pools = env.auction.pools, tierOf = env.auction.tierOf, minLevel = env.auction.minLevel,
      frlg = frlg, bx = env.bx,
    })
  end
  -- (the Boxes preview's Dynamax row: WoobleDex's levels and factors, when it's on)
  if env.bx then
    env.bx.dynamax = function()
      local nd = mod.find("national_dex_gen3")
      return nd and nd.exports and nd.exports.dynamax or nil
    end
  end
  local Apps = makeApps({
    boxes = env.bx and boxesWindow and boxesView
      and function(ctx, e) return boxesWindow(ctx, e, boxesView) end or nil,
    items = env.inv and itemsWindow or nil,
    mail = env.mb and mailWindow or nil,
    mart = env.mart and martWindow or nil,
    auction = env.auction and auctionWindow or nil,
    slots = env.slots and slotsWindow or nil,
    gts = env.gts and gtsWindow or nil,
    gtsBadge = env.gts and function() return env.gts.waiting() end or nil,
    auctionBadge = env.auction and function() return env.auction.unread() end or nil,
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
  local Desktop
  Desktop = makeDesktop({
    kit = Kit,
    apps = Apps,
    version = version,
    se = env.se,
    now = env.now,
    session = session,
    gameId = gameId,
    env = env,
    T = T, wall = Wall, wallpaper = wallpaper, wallpaperFit = wallpaperFit,
    -- the player's arrangement of the dock and the home screen (src/arrange.lua), kept in Settings
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
    -- (once a second while the desktop is open: R-Bay's ended auctions settled, a win's Poké Ball
    -- onto the pad)
    tick = function(ctx)
      if not env.auction then return end
      local s = ctx and ctx.session or session()
      local won, _, sp = env.auction.settle(s)
      if won > 0 and sp then Desktop.padTransfer(sp, "in", "ball") end
      if env.gts then pcall(env.gts.settle, s) end
    end,
  })
  -- the shelf's item pad, for the apps: an item crossing it ("out" to the PC, "in" to the Bag)
  env.pad = { transfer = function(id, dir, kind) Desktop.padTransfer(id, dir, kind) end }
  -- (money in a window, with the game's sign: the Mart)
  env.amount = function(n, x, y, size, c, measure) return Desktop.amount(n, x, y, size, c, measure) end
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
  mod.events:on("save.loaded", function(ev)
    Sh.forget()
    -- (auctions that ended while the game was closed: settled with the save they belong to)
    if env.auction then pcall(env.auction.settle, ev and ev.save or session()) end
    if env.gts then pcall(env.gts.settle, ev and ev.save or session()) end
  end)

  -- other mods add apps: exports.apps.register{ id, label, glyph, color, order, dock, available,
  -- open | window }
  mod.exports.apps = { register = Apps.register, list = function() return Apps.apps end }
  mod.exports._test = { desktop = Desktop, shell = Sh, apps = Apps, kit = Kit, inv = env.inv, mb = env.mb, bx = env.bx,
                        mart = env.mart, auction = env.auction, slots = env.slots, gts = env.gts,
                        env = env, i18n = T, settings = Settings, wall = Wall, arrange = Arrange }
end
