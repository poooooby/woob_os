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
--   src/pcgames.lua, src/apps/pcgames.lua   the PC Games mod's screen in a window
--   src/ribbons.lua, src/apps/ribbons.lua   the Ribbons app
--   src/hall.lua, src/apps/hall.lua   the Hall of Fame app
--   src/oak.lua, src/apps/oak.lua   the Oak's PC app
--   src/gts.lua, src/apps/gts.lua       the GTS: Wonder Trade and the Global Trade Station, its window
--   src/boxes.lua, src/apps/boxes.lua, src/apps/boxes_view.lua   the Pokémon model, the Boxes window
--   src/i18n.lua, lang/*.lua            the words, by language ; src/settings.lua the kept choices
--   src/wallpaper.lua                   the drawn wallpapers and the wallpapers/ folder's pictures
--   WoobPad: src/desktop.lua again (deps.device "pad"), from the START menu
--   src/notify.lua                      the notifications (R-Bay, the GTS): a list and banners
--   src/map3d/model.lua, render.lua, scene.lua, towns.lua   the region in 3D (from the game's Town
--                                       Map), its drawing, its window (the Map app), its towns' buildings
--   src/townmap.lua                     the full-screen host: the 3D Town Map, the PokéNav's apps
--   src/phone.lua, src/apps/phone.lua   the Phone: the PokéNav's Match Call / Trainer's Eyes contacts
--   src/condition.lua, src/apps/condition.lua   Condition: the contest conditions, Pokéblocks
--   src/pokenav.lua                     the PokéNav's Match Call / Trainer's Eyes and Condition: ours

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
  local makePcGames, pcGamesWindow = loadSibling(mod, "src/pcgames.lua"), loadSibling(mod, "src/apps/pcgames.lua")
  local makeGts, gtsWindow = loadSibling(mod, "src/gts.lua"), loadSibling(mod, "src/apps/gts.lua")
  local makeNotify = loadSibling(mod, "src/notify.lua")
  local makeBank, bankWindow = loadSibling(mod, "src/bank.lua"), loadSibling(mod, "src/apps/bank.lua")
  local makeJournal = loadSibling(mod, "src/journal.lua")
  local makeErrands, errandsWindow = loadSibling(mod, "src/errands.lua"), loadSibling(mod, "src/apps/errands.lua")
  local makeSwarm = loadSibling(mod, "src/swarm.lua")
  local makeNews, newsWindow = loadSibling(mod, "src/news.lua"), loadSibling(mod, "src/apps/news.lua")
  local makeChallenges, challengesWindow = loadSibling(mod, "src/challenges.lua"), loadSibling(mod, "src/apps/challenges.lua")
  local makeNotes, makeFrost = loadSibling(mod, "src/notes.lua"), loadSibling(mod, "src/frost.lua")
  local Icons = loadSibling(mod, "src/icons.lua")
  local storeWindow = loadSibling(mod, "src/apps/appstore.lua")
  local makeGear, makeGearPanel = loadSibling(mod, "src/kanto_gear.lua"), loadSibling(mod, "src/gear_panel.lua")
  local makeMapModel, makeMapRender = loadSibling(mod, "src/map3d/model.lua"), loadSibling(mod, "src/map3d/render.lua")
  local mapScene, makeTownMap = loadSibling(mod, "src/map3d/scene.lua"), loadSibling(mod, "src/townmap.lua")
  local makeTowns = loadSibling(mod, "src/map3d/towns.lua")
  local makePhone, phoneWindow = loadSibling(mod, "src/phone.lua"), loadSibling(mod, "src/apps/phone.lua")
  local makeCondition, conditionWindow = loadSibling(mod, "src/condition.lua"), loadSibling(mod, "src/apps/condition.lua")
  local makeRibbons, ribbonsWindow = loadSibling(mod, "src/ribbons.lua"), loadSibling(mod, "src/apps/ribbons.lua")
  local makeHall, hallWindow = loadSibling(mod, "src/hall.lua"), loadSibling(mod, "src/apps/hall.lua")
  local makeOak, oakWindow = loadSibling(mod, "src/oak.lua"), loadSibling(mod, "src/apps/oak.lua")
  local makeDecorate, decorateWindow = loadSibling(mod, "src/decorate.lua"), loadSibling(mod, "src/apps/decorate.lua")
  local makePokenav = loadSibling(mod, "src/pokenav.lua")
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
    fallback = function(font, px, exact)
      if fallbackMissing or not font.setFallbacks then return end
      local size = math.max(6, math.floor(px + 0.5))
      -- (exact: for a canvas of one pixel a unit, see K.exactFonts)
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
  -- a species' front picture (64 px), `size` units square at x, y -> true when drawn (kept per
  -- species); with `mon`, that Pokémon's own (shiny when it is; kept per Pokémon)
  local pics = {}
  local picOf = setmetatable({}, { __mode = "k" })
  local function monPic(species, x, y, size, a, mon)
    local pic
    if type(mon) == "table" then
      pic = picOf[mon]
      if pic == nil then
        local P = engine("src.core.game3.pokemon")
        local ok, got = pcall(P and P.monFrontPic or error, mon, nil, "box")
        pic = ok and type(got) == "table" and got.image and got or false
        picOf[mon] = pic
      end
    else
      pic = pics[species]
    end
    if pic == nil then
      local P = engine("src.core.game3.pokemon")
      -- (a species, not a Pokémon: told it isn't shiny, else no personality and no OT ID read as
      -- the shiny one; the listing's Pokémon is made later with its own)
      local ok, got = pcall(P and P.monFrontPic or error, { species = species, isShiny = false }, nil, "box")
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
    mart = makeMart and makeMart(engine, { save = mod.save }),
    monIconOf = monIconOf, monPic = monPic, boxWall = boxWall, boxWallCount = boxWallCount, itemName = itemName,
    T = T, wall = Wall, gameId = gameId, wallpaper = wallpaper,
    language = function() return T and T.code() or "en" end,
    setLanguage = function(code)
      if T and T.set(code) and Settings then Settings.set("language", code) end
    end,
    setWallpaper = function(id) if Settings then Settings.set("wallpaper", id) end end,
    wallpaperFit = wallpaperFit,
    setWallpaperFit = function(fit) if Settings then Settings.set("wallpaperFit", fit) end end,
    -- (the Settings app's switches: WoobPad's START row, the notifications' banners)
    setting = function(key, default)
      if not Settings then return default end
      return Settings.get(key, default)
    end,
    setSetting = function(key, v) if Settings then Settings.set(key, v) end end,
  }
  -- the notifications: pushed by the models below, made once the apps are (Nt set further down);
  -- quiet (the list only) while the player is looking at that app already
  local Nt, Desktop, Watch
  local function looking(id)
    local w = Desktop and Desktop.isOpen() and Desktop.state()
    if w and w.winApp and w.winApp.id == id then return true end
    local ws = Watch and Watch.isOpen() and Watch.state()
    if ws and ws.winApp and ws.winApp.id == id then return true end
    return Sh ~= nil and Sh.showing(id)
  end
  -- (which app a kind of notification belongs to; R-Bay's are the rest)
  local NOTIFY_APP = { gts = "gts", call = "phone", bank = "bank", challenge = "challenges", errand = "errands",
                       swarm = "news" }
  local function notify(kind, data, quiet)
    if not Nt then return end
    local app = NOTIFY_APP[kind] or "auction"
    Nt.push(kind, data, quiet or looking(app))
  end
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
      notify = notify,
      -- (the ending-soon alert: Settings > WoobPad, 5 / 10 / 15 / 30 minutes before the end)
      soon = function() return (tonumber(Settings and Settings.get("soonMinutes", 10)) or 10) * 60 end,
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
      frlg = frlg, bx = env.bx, notify = notify, shinyPersonality = env.auction.shinyPersonality,
    })
  end
  -- the Bank: money kept beside the wallet; what the wallet can't hold goes there (the engine's
  -- Prize.apply, which every gain goes through, wrapped once per process: impl swapped per instance)
  if makeBank then
    env.bank = makeBank(engine, { save = mod.save, now = os.time, notify = notify })
    local Prize = engine("src.core.game3.battle.prize")
    if Prize and Prize.apply then
      local w = rawget(Prize, "__woobOs")
      if not w then
        w = { orig = Prize.apply }
        Prize.__woobOs = w
        Prize.apply = function(s, amount, ...)
          if w.impl then return w.impl(w.orig, s, amount, ...) end
          return w.orig(s, amount, ...)
        end
      end
      local bank = env.bank
      w.impl = function(orig, s, amount, ...)
        local gained, total = orig(s, amount, ...)
        local over = math.max(0, math.floor(tonumber(amount) or 0)) - (tonumber(gained) or 0)
        if s and over > 0 then
          local ok, banked = pcall(bank.overflow, s, over)
          -- (what the bank took counts as gained: the player has it)
          if ok and tonumber(banked) then gained = (tonumber(gained) or 0) + banked end
        end
        return gained, total
      end
    end
  end
  -- the daily swarm (a species all over one route; Settings: swarms) and the journal (what the player does,
  -- from the engine's events), the week's Challenges counted from it
  if makeSwarm then
    env.swarm = makeSwarm(engine, {
      now = os.time, session = session,
      seed = function(s) return env.auction and env.auction.seedOf and env.auction.seedOf(s) or 1 end,
      day = function(t) return env.journal and env.journal.day(t) or math.floor(t / 86400) end,
      badges = function(s) return env.mart and env.mart.badges(s) or 0 end,
      on = function() return not Settings or Settings.get("swarms", true) ~= false end,
    })
  end
  if makeJournal then
    -- (a Gym Leader: the game's own class, its number asked once per game)
    local leaderCls, leaderFor = nil, nil
    env.journal = makeJournal(engine, {
      save = mod.save, now = os.time, session = session,
      badges = function(s) return env.mart and env.mart.badges(s) or 0 end,
      swarm = function() return env.swarm and env.swarm.species() or nil end,
      leader = function(cls)
        local g = gameId()
        if leaderFor ~= g then
          leaderFor, leaderCls = g, false
          local Constants = engine("src.core.game3.constants")
          local okC, C = pcall(Constants and Constants.of or error, g)
          if okC and C then
            local okI, id = pcall(C.id, C, "trainer_classes", "TRAINER_CLASS_LEADER")
            if okI and tonumber(id) then leaderCls = tonumber(id) end
          end
        end
        return leaderCls ~= false and cls ~= nil and cls == leaderCls
      end,
    })
  end
  -- (a type's name in WoobOS's words, "type.<id>"; else the game's own, shortened as it keeps them)
  env.typeName = function(id)
    local key = "type." .. tostring(id)
    if T and T.has and T.has(key) then return T(key) end
    local Types = engine("src.core.game3.battle.types")
    local ok, name = pcall(Types and Types.name or error, id)
    if not (ok and type(name) == "string" and name ~= "") then return tostring(id) end
    return name:sub(1, 1) .. name:sub(2):lower()
  end
  if makeChallenges and env.journal then
    env.challenges = makeChallenges(engine, {
      save = mod.save, now = os.time, journal = env.journal, T = T, notify = notify,
      seed = function(s) return env.auction and env.auction.seedOf and env.auction.seedOf(s) or 1 end,
      badges = function(s) return env.mart and env.mart.badges(s) or 0 end,
      frlg = frlg, itemName = env.itemName, typeName = env.typeName,
      swarmOn = function() return env.swarm ~= nil and env.swarm.on() end,
    })
  end
  -- Errands: teams sent out on jobs in real time, held in the save while they're out
  if makeErrands and env.bx then
    env.errands = makeErrands(engine, {
      save = mod.save, now = os.time, bx = env.bx, T = T, notify = notify,
      seed = function(s) return env.auction and env.auction.seedOf and env.auction.seedOf(s) or 1 end,
      badges = function(s) return env.mart and env.mart.badges(s) or 0 end,
    })
  end
  -- the News: the day's stories, the WoobOS News anchor reading them
  local function titled(text)
    return (tostring(text):lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
  end
  -- (a map's name, the save menu's way: a session that's only that map)
  local function placeName(mapId)
    local SaveMenu = engine("src.ui.game3.save_menu")
    local s = session() or {}
    local probe = setmetatable({ map = mapId, mapName = "", regionMapSectionId = false, mapSec = false },
      { __index = s })
    local ok, n = pcall(SaveMenu and SaveMenu.locationName or error, probe)
    if ok and type(n) == "string" and n ~= "" and n ~= "PALLET TOWN" then return titled(n) end
    return titled((tostring(mapId or "?"):gsub("^%u%u_", ""):gsub("_", " ")))
  end
  -- the Mart's clerk: the game's own overworld sprite (FireRed / LeafGreen's clerk, Ruby / Sapphire /
  -- Emerald's Mart employee), asked for until it comes (once a second at most); kept per game
  local clerkSpr, clerkFor, clerkTry = nil, nil, -10
  env.clerk = function()
    local g = gameId()
    if clerkSpr and clerkFor == g then return clerkSpr end
    local t = env.now()
    if t - clerkTry < 1 then return nil end
    clerkTry, clerkSpr = t, nil
    local Constants, Ow = engine("src.core.game3.constants"), engine("src.core.game3.ow_sprites")
    if not (Constants and Ow and Ow.getDraw) then return nil end
    local okC, C = pcall(Constants.of, g)
    if not (okC and C) then return nil end
    local okI, id = pcall(C.id, C, "event_objects", "OBJ_EVENT_GFX_CLERK")
    if not (okI and id) then okI, id = pcall(C.id, C, "event_objects", "OBJ_EVENT_GFX_MART_EMPLOYEE") end
    if not (okI and id) then return nil end
    local okS, spr = pcall(Ow.getDraw, id)
    if okS and type(spr) == "table" and spr.image and spr.quads then clerkSpr, clerkFor = spr, g end
    return clerkSpr
  end
  -- the News's anchor: assets/newscaster.png, square frames side by side (0 at rest, the rest her
  -- talking), loaded once for whole-pixel scaling, its frames cut with it; `foot` = the empty rows
  -- under every frame (the bust is drawn that much lower, to meet the shot's edge)
  local ANCHOR = "assets/newscaster.png"
  local anchorArt
  env.anchor = function()
    if anchorArt == nil then
      anchorArt = false
      local LG, LI = love and love.graphics, love and love.image
      local ok, img = pcall(mod.assets.image, mod.assets, ANCHOR)
      if ok and img and LG and LG.newQuad then
        pcall(img.setFilter, img, "nearest", "nearest")
        local iw, ih = img:getDimensions()
        local n, quads = math.max(1, math.floor(iw / ih)), {}
        for i = 0, n - 1 do quads[i] = LG.newQuad(i * ih, 0, ih, ih, iw, ih) end
        local foot = 0
        local okP, full = pcall(mod.assets.path, mod.assets, ANCHOR)
        local okD, data = false, nil
        if okP and LI and LI.newImageData then okD, data = pcall(LI.newImageData, full) end
        if okD and data then
          for y = ih - 1, 0, -1 do
            local empty = true
            for x = 0, iw - 1 do
              local _, _, _, a = data:getPixel(x, y)
              if a > 0 then
                empty = false
                break
              end
            end
            if not empty then break end
            foot = foot + 1
          end
          pcall(data.release, data)
        end
        anchorArt = { image = img, quads = quads, n = n, size = ih, foot = foot }
      end
    end
    return anchorArt or nil
  end
  if makeNews then
    env.news = makeNews(engine, {
      save = mod.save, now = os.time, T = T, notify = notify,
      journal = env.journal, swarm = env.swarm, auction = env.auction, gts = env.gts, errands = env.errands,
      challenges = env.challenges, place = placeName, itemName = env.itemName,
      moveName = function(num)
        local Pk = engine("src.core.game3.pokemon")
        local ok, n = pcall(Pk and Pk.moveName or error, num)
        if not (ok and type(n) == "string" and n ~= "" and n ~= "-------") then return nil end
        return titled(n)
      end,
      monName = function(sp)
        local Pk = engine("src.core.game3.pokemon")
        local ok, n = pcall(Pk and Pk.name or error, sp)
        if not (ok and n) then return tostring(sp) end
        -- (the fonts have no gender signs: Nidoran F, Nidoran M)
        return titled((tostring(n):gsub("\226\153\128", " F"):gsub("\226\153\130", " M")))
      end,
      storm = function(s)
        if gameId() ~= "emerald" or not (env.map3d and env.map3d.model) then return nil end
        local M = env.map3d.model
        local okR, region = pcall(M.region, "hoenn")
        if not (okR and region) then return nil end
        local ok, st = pcall(M.storm, region, s)
        if ok and st and st.place then return { kind = st.kind, place = titled(st.place.name or "") } end
        return nil
      end,
    })
  end
  -- the 3D map: the region from the game's Town Map (its picture read back once through a canvas),
  -- its drawing, the device's clock for day and night, and Fly from the app (outdoors, the party's
  -- Fly and the badge: the game's own flight)
  local function pixels(img, x, y, w, h)
    local G = love and love.graphics
    if not (G and G.newCanvas and img) then return nil end
    local okC, c = pcall(G.newCanvas, w, h, { dpiscale = 1 })
    if not (okC and c) then return nil end
    G.push("all")
    local okD = pcall(function()
      G.origin()
      G.setScissor()
      G.setShader()
      G.setCanvas(c)
      G.clear(0, 0, 0, 0)
      G.setColor(1, 1, 1, 1)
      G.draw(img, -x, -y)
    end)
    G.setCanvas()
    G.pop()
    local okI, data = pcall(c.newImageData, c)
    if not (okD and okI and data) then return nil end
    return function(px, py)
      if px < 0 or py < 0 or px >= w or py >= h then return nil end
      local r, g, b, a = data:getPixel(px, py)
      if a < 0.5 then return nil end
      return r * 255, g * 255, b * 255
    end
  end
  if makeMapModel and makeMapRender and mapScene then
    -- (the maps' definitions, for the weather: the live game's)
    local function mapDefs()
      local g = mod.game
      return g and g.data and g.data.maps or nil
    end
    local Model = makeMapModel(engine, { pixels = pixels, gameId = gameId, maps = mapDefs })
    local Towns = makeTowns and makeTowns() or nil
    env.map3d = {
      model = Model,
      towns = Towns,
      render = makeMapRender({ log = warn, towns = Towns }),
      clock = function()
        local Rtc = engine("src.core.game3.rtc")
        if not (Rtc and Rtc.hostInfo) then return 12, 0 end
        local info = Rtc.hostInfo(nil)
        return info.hour, info.minute
      end,
      flyCheck = function(ctx, s)
        -- (over the PokéNav there's no flying off: it has to be closed first)
        if ctx and ctx.mode == "pokenav" then return nil, "none" end
        return Model.flyCheck(s)
      end,
      -- (the mod's options: the camera's turn and tilt inverted)
      invert = function()
        return option("mapInvertX", false) == true, option("mapInvertY", false) == true
      end,
      -- (the host closed, the START menu with it, then the game's own Fly: the take-off, the map, the landing)
      fly = function(ctx, region, place)
        local s = ctx.session or session()
        local mon, why = Model.flyCheck(s)
        if not mon then return false, why end
        local Field = engine("src.core.game3.field")
        if not (Field and Field.flyTo) then return false, "none" end
        local info
        if region.family == "rse" then
          local RseMap = engine("src.ui.game3.rse.region_map")
          local sec, pick = Model.pickArgs(region, place)
          info = pick
          info.dest = RseMap and RseMap.flyWarpDestination(s, sec, 0) or nil
          if not info.dest then return false, "none" end
        end
        ctx.done()
        local StartMenu = engine("src.ui.game3.start_menu")
        if StartMenu and StartMenu.isOpen and StartMenu.isOpen() then pcall(StartMenu.close, true) end
        Field.flyTo(region.family == "rse" and place.id or place.sym, mon, info)
        return true
      end,
    }
  end
  -- the PokéNav's apps: the Phone (its contacts, the game's calls, recents and favourites in the
  -- save) and Condition (the contest conditions, the Pokéblock case)
  if makePhone then
    env.phone = makePhone(engine, { save = mod.save, now = os.time, notify = notify,
                                    image = function(path) return mod.assets:image(path) end })
  end
  if makeCondition and env.bx then env.condition = makeCondition(engine, { bx = env.bx }) end
  if makeHall then env.hall = makeHall(engine) end
  if makeOak then env.oak = makeOak(engine) end
  if makeDecorate then env.decorate = makeDecorate(engine) end
  if makeRibbons and env.condition and env.phone then
    env.ribbons = makeRibbons(engine, { family = env.phone.family, available = env.condition.available })
  end
  -- (the Boxes preview's Dynamax row: WoobleDex's levels and factors, when it's on)
  if env.bx then
    env.bx.dynamax = function()
      local nd = mod.find("national_dex_gen3")
      return nd and nd.exports and nd.exports.dynamax or nil
    end
  end
  if makePcGames and pcGamesWindow then
    env.pcgames = makePcGames(engine, {
      find = function() return mod.find("pc_solitaire") end,
      game = function()
        local Runtime = engine("src.core.game3.runtime")
        return Runtime and Runtime._game
      end,
      log = function(...) mod.log:warn(...) end,
    })
  end
  local Apps = makeApps({
    icons = Icons,
    store = storeWindow,
    removed = Settings and function() return Settings.get("removedApps", "") end or nil,
    saveRemoved = Settings and function(text) Settings.set("removedApps", text) end or nil,
    boxes = env.bx and boxesWindow and boxesView
      and function(ctx, e) return boxesWindow(ctx, e, boxesView) end or nil,
    items = env.inv and itemsWindow or nil,
    mail = env.mb and mailWindow or nil,
    mart = env.mart and martWindow or nil,
    auction = env.auction and auctionWindow or nil,
    slots = env.slots and slotsWindow or nil,
    pcgames = env.pcgames and pcGamesWindow or nil,
    pcgamesAvailable = env.pcgames and env.pcgames.available or nil,
    gts = env.gts and gtsWindow or nil,
    bank = env.bank and bankWindow or nil,
    challenges = env.challenges and challengesWindow or nil,
    errands = env.errands and errandsWindow or nil,
    errandsBadge = env.errands and function() return env.errands.waiting() end or nil,
    news = env.news and newsWindow or nil,
    challengesBadge = env.challenges and function(ctx) return env.challenges.waiting(ctx and ctx.session or session()) end
      or nil,
    map = env.map3d and function(ctx, e) return mapScene(ctx, e, { mode = "app" }) end or nil,
    phone = env.phone and phoneWindow or nil,
    condition = env.condition and conditionWindow or nil,
    ribbons = env.ribbons and ribbonsWindow or nil,
    hall = env.hall and hallWindow or nil,
    oak = env.oak and oakWindow or nil,
    oakAvailable = env.oak and function(ctx) return env.oak.available(ctx.session or session()) end or nil,
    hallTeams = env.hall and function(ctx) return env.hall.count(ctx.session or session()) end or nil,
    ribbonsAvailable = env.ribbons and function(ctx) return env.ribbons.available(ctx.session or session()) end or nil,
    phoneAvailable = env.phone and function(ctx) return env.phone.available(ctx.session or session()) end or nil,
    conditionAvailable = env.condition and function(ctx) return env.condition.available(ctx.session or session()) end
      or nil,
    gtsBadge = env.gts and function() return env.gts.waiting() end or nil,
    auctionBadge = env.auction and function() return env.auction.unread() end or nil,
    settings = T and Settings and settingsWindow or nil,
    decorate = env.decorate and decorateWindow or nil,
  })
  local glyphOpts = setmetatable({}, { __mode = "k" })
  local NONE = { 0, 0, 0, 0 }
  local CURRENCY_GLYPH, CURRENCY_EM, CURRENCY_DROP, CURRENCY_BOLD = 0xB7, 11, -0.04, 0.6
  local signAdvance, signAdvanceFor
  Nt = makeNotify and makeNotify({
    K = Kit, T = T, now = env.now, epoch = os.time, se = env.se, monIcon = monIcon, apps = Apps,
    glyph = function(...) if Desktop then return Desktop.glyph(...) end end,
    enabled = function() return not Settings or Settings.get("notifications", true) ~= false end,
    setting = function(key, default)
      if not Settings then return default end
      return Settings.get(key, default)
    end,
  }) or nil
  -- (Settings > Notifications: which apps tell the player things, and each one's switch)
  env.notifications = Nt and { apps = Nt.APPS, setting = Nt.SETTING } or nil
  local deskDeps = ({
    kit = Kit,
    apps = Apps,
    icons = Icons,
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
    notify = Nt,
    -- (the notifications drawer and its frosted glass: each desktop makes its own)
    notes = makeNotes,
    frost = makeFrost,
  })
  Desktop = makeDesktop(deskDeps)
  -- WoobPad: the same desktop as a tablet, from the START menu anywhere (the same apps, arrangement
  -- and notifications; no boot, no shelf)
  Watch = makeDesktop(setmetatable({ device = "pad" }, { __index = deskDeps }))
  -- the 3D map in place of the game's Town Map and Fly map (Settings: map3d)
  local TownMap = makeTownMap and makeTownMap({
    kit = Kit, T = T, env = env, se = env.se,
    scene = mapScene, log = function(fmt, ...) mod.log:warn(fmt, ...) end,
  }) or nil
  -- the shelf's item pad, for the apps: an item crossing it ("out" to the PC, "in" to the Bag);
  -- WoobPad has no shelf
  env.pad = { transfer = function(id, dir, kind)
    if Desktop.isOpen() then Desktop.padTransfer(id, dir, kind) end
  end }
  -- (the App Store: the registry, and an app's icon in a window)
  env.apps = Apps
  env.appIcon = function(app, x, y, size) Desktop.appIcon(app, x, y, size) end
  -- (a desktop glyph in window pixels, white: the Phone's handset)
  env.glyph = Desktop.glyph
  -- (money in a window, with the game's sign: the Mart)
  env.amount = function(n, x, y, size, c, measure) return Desktop.amount(n, x, y, size, c, measure) end
  -- once a second, wherever the player is: R-Bay's auctions and the GTS settle (their
  -- notifications come from it); a win's Poké Ball onto the desktop's pad
  local function tick()
    -- (the open desktop's or pad's session first: the one the PC was opened with)
    local open = Desktop.isOpen() and Desktop.state() or (Watch and Watch.isOpen() and Watch.state())
    local s = open and open.ctx and open.ctx.session or session()
    if not s then return end
    if env.auction then
      local won, _, sp = env.auction.settle(s)
      if won > 0 and sp and Desktop.isOpen() then Desktop.padTransfer(sp, "in", "ball") end
    end
    if env.gts then pcall(env.gts.settle, s) end
    if env.challenges then pcall(env.challenges.check, s) end
    if env.errands then pcall(env.errands.settle, s) end
    if env.news then pcall(env.news.tick, s) end
  end
  -- the PokéNav's Match Call / Trainer's Eyes and Condition: our apps instead (Settings: pokenavApps)
  local Pokenav = makePokenav and makePokenav(engine, {
    open = function(appId, s, onClose, state) return Sh and Sh.openFull(appId, s, onClose, state) or false end,
    enabled = function()
      return option("desktop", true) ~= false and (not Settings or Settings.get("pokenavApps", true) ~= false)
    end,
    log = function(fmt, ...) mod.log:warn(fmt, ...) end,
  }) or nil
  -- (a call in the field: who, and their words, into the Phone's recents and a notification)
  local function onCall(s, trainerId, msg)
    if not env.phone then return end
    local MC, Trainers = engine("src.core.game3.rse.match_call"), engine("src.core.game3.scripting.trainers")
    local okN, name = pcall(function() return MC.trainerName(s, MC.matchCallId(trainerId)) end)
    local okT, info = pcall(Trainers and Trainers.get or error, trainerId)
    if not (okN and name) then name = okT and info and info.name or "?" end
    env.phone.incoming(s, name, env.phone.textOf(msg) or "", okT and info and info.pic or nil)
  end
  -- the Kanto Gear apps' own screen, apart from the PC's and WoobPad's
  local GearPanel = makeTownMap and makeGearPanel and makeGearPanel({
    host = makeTownMap({ kit = Kit, T = T, env = env, se = env.se, scene = mapScene, keepHits = true,
                         log = function(fmt, ...) mod.log:warn(fmt, ...) end }),
    kit = Kit,
    bridge = function() return engine("src.render.SecondScreen") end,
    log = function(fmt, ...) mod.log:warn(fmt, ...) end,
  }) or nil
  Sh = makeShell(mod, { require = require, log = mod.log, desktop = Desktop, apps = Apps, watch = Watch,
                        gearPanel = GearPanel,
                        notify = Nt, tick = tick, session = session,
                        townmap = TownMap, map3d = env.map3d, pokenav = Pokenav,
                        onCall = env.phone and onCall or nil,
                        map3dOn = function() return not Settings or Settings.get("map3d", true) ~= false end,
                        watchRow = function() return not Settings or Settings.get("watchRow", true) ~= false end,
                        watchLabel = function() return T and T("watch.start") or "WATCH" end })
  Sh.enabled = function() return option("desktop", true) ~= false end

  -- Slots, R-Bay and the GTS as Kanto Gear apps, when that mod's on (src/kanto_gear.lua)
  local Gear = makeGear and makeGear({
    find = mod.find,
    open = function(id) return Sh.openFromGear(id) end,
    shown = function(id) return Sh.gearOpen(id) end,
    color = function(id) local app = Apps.byId(id); return app and app.color end,
    glyph = Desktop.glyph,
    log = function(fmt, ...) mod.log:warn(fmt, ...) end,
  }) or nil

  local okI, errI = pcall(Sh.install)
  if not okI then mod.log:warn("the desktop's hooks failed: %s", tostring(errI)) end
  mod.events:on("game.ready", function()
    if env.pcgames then env.pcgames.reset() end
    if env.decorate then env.decorate.reset() end
    if env.map3d then env.map3d.lastStorm = nil end
    local ok, err = pcall(Sh.ready)
    if not ok then mod.log:warn("the PC keeps its own menu: %s", tostring(err)) end
    Sh.closeGear()
    if Gear then pcall(Gear.bind) end
  end)
  -- the journal's events (observed only), and an item used from the Bag or the field (the hook's
  -- answer passed on as it came)
  if env.journal then
    for _, name in ipairs({ "battle.started", "battle.damage_dealt", "battle.battler_switched", "battle.fainted",
                            "battle.ended", "pokemon.caught", "egg.hatched", "pokemon.evolved", "pokemon.level_up",
                            "map.entered", "world.stepped", "flag.changed" }) do
      mod.events:on(name, function(ev) env.journal.on(name, ev) end)
    end
    -- (the daily swarm: on its route, some of the encounters become it)
    if env.swarm then
      mod.hooks:wrap("encounter.species", function(nxt, enc, ctx, ...)
        local got = nxt(enc, ctx, ...)
        local ok, swapped = pcall(env.swarm.encounter, got, ctx)
        return ok and swapped or got
      end)
    end
    mod.hooks:wrap("item.use", function(nxt, ...)
      local ok, kind, text = nxt(...)
      if ok then pcall(env.journal.on, "item.used") end
      return ok, kind, text
    end)
  end
  -- (a new map or a loaded save: the next PC boots again)
  mod.events:on("map.entered", function() Sh.forget() end)
  mod.events:on("save.loaded", function(ev)
    Sh.forget()
    Sh.closeGear()
    -- (auctions that ended while the game was closed: settled with the save they belong to)
    if env.auction then pcall(env.auction.settle, ev and ev.save or session()) end
    if env.gts then pcall(env.gts.settle, ev and ev.save or session()) end
    if env.errands then pcall(env.errands.settle, ev and ev.save or session()) end
  end)

  -- other mods add apps (DEVELOPMENT.md "Adding an app"): exports.apps.register{ id, label, glyph,
  -- color, order, dock, available, open | window } ; exports.apps.icons() -> the pictures to choose from
  mod.exports.apps = {
    register = function(app)
      -- (another mod's app is always the player's to keep or remove)
      if type(app) == "table" then app.removable, app.fromMod = true, true end
      local ok, why = Apps.register(app)
      if not ok then mod.log:warn("an app wasn't added: %s", tostring(why)) end
      return ok, why
    end,
    list = function() return Apps.apps end,
    icons = Apps.icons,
  }
  mod.exports._test = { desktop = Desktop, shell = Sh, apps = Apps, kit = Kit, inv = env.inv, mb = env.mb, bx = env.bx,
                        mart = env.mart, auction = env.auction, slots = env.slots, pcgames = env.pcgames, gts = env.gts,
                        bank = env.bank, journal = env.journal, challenges = env.challenges, errands = env.errands,
                        swarm = env.swarm, news = env.news,
                        env = env, i18n = T, settings = Settings, wall = Wall, arrange = Arrange,
                        watch = Watch, pad = Watch, notify = Nt, tick = tick, map3d = env.map3d, townmap = TownMap,
                        phone = env.phone, condition = env.condition, ribbons = env.ribbons, hall = env.hall, oak = env.oak, decorate = env.decorate, pokenav = Pokenav, onCall = onCall, gear = Gear, gearPanel = GearPanel }
end
