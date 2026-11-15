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
  -- the play-tied apps: Gen 3's models over the Game Boy games' port (src/gb/port.lua) and play (src/gb/play.lua)
  local makePort, makePlay = loadSibling(mod, "src/gb/port.lua"), loadSibling(mod, "src/gb/play.lua")
  local makeMart, martWindow = loadSibling(mod, "src/gb/mart.lua"), loadSibling(mod, "src/apps/mart.lua")
  local makeBank, bankWindow = loadSibling(mod, "src/bank.lua"), loadSibling(mod, "src/apps/bank.lua")
  local makeAuction, auctionWindow = loadSibling(mod, "src/auction.lua"), loadSibling(mod, "src/apps/auction.lua")
  local makeSlots, slotsWindow = loadSibling(mod, "src/slots.lua"), loadSibling(mod, "src/apps/slots.lua")
  local makeGts, gtsWindow = loadSibling(mod, "src/gts.lua"), loadSibling(mod, "src/apps/gts.lua")
  local makeJournal, makeSwarm = loadSibling(mod, "src/journal.lua"), loadSibling(mod, "src/swarm.lua")
  local makeChallenges, challengesWindow = loadSibling(mod, "src/challenges.lua"), loadSibling(mod, "src/apps/challenges.lua")
  local makeErrands, errandsWindow = loadSibling(mod, "src/errands.lua"), loadSibling(mod, "src/apps/errands.lua")
  local makeNews, newsWindow = loadSibling(mod, "src/news.lua"), loadSibling(mod, "src/apps/news.lua")
  local makeDex, dexWindow = loadSibling(mod, "src/gb/dex.lua"), loadSibling(mod, "src/apps/pokedex.lua")
  local dexView = loadSibling(mod, "src/apps/pokedex_view.lua")
  -- the 3D map: the Game Boy maps built to scale (src/gb/map3d.lua), drawn by Gen 3's renderer and window
  local makeGbMap, makeWorld = loadSibling(mod, "src/gb/map3d.lua"), loadSibling(mod, "src/map3d/world.lua")
  local makeMapRender, mapScene = loadSibling(mod, "src/map3d/render.lua"), loadSibling(mod, "src/map3d/scene.lua")
  local makeTowns = loadSibling(mod, "src/map3d/towns.lua")
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
  -- (the Pokédex in the START menu's place: the mod's option, then Settings > Gameplay)
  local function dexOn()
    return option("pokedex", true) ~= false and (not Settings or Settings.get("pokedexApp", true) ~= false)
  end
  local Host = makeHost(mod, { gen = gen, require = require, log = mod.log, dexOn = dexOn,
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
    env.money = Gd.money
    -- (an item or a type the shared models name by Gen 3's number: the port's translation)
    env.itemName = function(id) return Gd.itemName(type(id) == "number" and env.port and env.port.item(id) or id) end
    local TYPE_KEY = { [0] = "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST", "STEEL",
                       "CURSE_TYPE", "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC_TYPE", "ICE", "DRAGON", "DARK" }
    env.typeName = function(t)
      if type(t) == "number" then
        local key = "type." .. t
        if T and T.has and T.has(key) then return T(key) end
        return Gd.typeName(TYPE_KEY[t] or "NORMAL")
      end
      return Gd.typeName(t)
    end
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
  -- (each Ball its own colour: the Slots' reels show four)
  local BALL_TILE = { POKE_BALL = { 226, 70, 72 }, GREAT_BALL = { 64, 120, 220 }, ULTRA_BALL = { 214, 168, 32 },
                      MASTER_BALL = { 150, 70, 200 }, RARE_CANDY = { 120, 140, 240 } }
  local tileOf = {}
  local Desktop
  env.itemIcon = function(id, x, y, size, a)
    if not Gd then return end
    local t = tileOf[id]
    if not t then
      local key = id
      if type(id) == "number" and env.port then id = env.port.item(id) end
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
      colour = BALL_TILE[id] or colour
      t = { colour = colour, glyph = base[2] }
      tileOf[key] = t
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

  -- ------- the play-tied apps
  local Nt
  local NOTIFY_APP = { gts = "gts", bank = "bank", challenge = "challenges", errand = "errands", swarm = "news" }
  local Desktop0, Watch0 = nil, nil
  local function looking(id)
    local w = Desktop0 and Desktop0.isOpen() and Desktop0.state()
    if w and w.winApp and w.winApp.id == id then return true end
    local ws = Watch0 and Watch0.isOpen() and Watch0.state()
    return ws ~= nil and ws.winApp ~= nil and ws.winApp.id == id
  end
  local function notify(kind, data, quiet)
    if not Nt then return end
    local app = NOTIFY_APP[kind] or "auction"
    Nt.push(kind, data, quiet or looking(app))
  end
  local Port = Gd and makePort and makePort(Host, Gd, { bank = function() return env.bank end,
                                                         bx = function() return env.bx end }) or nil
  local Play = Gd and makePlay and makePlay(Host, Gd) or nil
  env.port = Port
  env.log = warn
  -- (the Map app: its region built in the background once the player's been in the field a while)
  if makeGbMap and makeWorld and makeMapRender and mapScene and Gd then
    local Wd = makeWorld(function() return nil end, {})
    local Towns = makeTowns and makeTowns() or nil
    local Model = makeGbMap(Host, Gd, { world = Wd, log = warn, place = Play and Play.place or nil })
    env.map3d = {
      model = Model, towns = Towns,
      render = makeMapRender({ log = warn, towns = Towns }),
      clock = function()
        local t = os.date("*t")
        return t.hour, t.min
      end,
      flyCheck = function() return nil, "none" end,
      fly = function() return false, "none" end,
      invert = function()
        return option("mapInvertX", false) == true, option("mapInvertY", false) == true
      end,
    }
  end
  -- (the shared models' Gen 3 engine: nothing here, the port answers instead)
  local function noEngine() return nil end
  -- (this save's seed: the player's ID and name)
  local function seed(s)
    local p = s and s.player or {}
    local id, name = tonumber(p.id) or 1, tostring(p.name or "")
    local h = id
    for i = 1, #name do h = (h * 131 + name:byte(i)) % 2147483647 end
    return h + 1
  end
  local wallet = Gd and { get = Gd.money, set = Gd.setMoney, cap = Gd.MAX_MONEY } or nil
  local function badges(s) return env.mart and env.mart.badges(s) or (Gd and math.min(8, Gd.badges(s)) or 0) end
  if Port then
    env.mart = makeMart and makeMart(Host, Gd, { save = mod.save, pay = Port.pay }) or nil
    env.bank = makeBank and makeBank(noEngine, { save = mod.save, now = os.time, notify = notify, wallet = wallet }) or nil
    env.auction = makeAuction and makeAuction(noEngine, {
      save = mod.save, now = os.time, seed = seed, badges = badges, notify = notify, port = Port,
      soon = function() return (tonumber(Settings and Settings.get("soonMinutes", 10)) or 10) * 60 end,
    }) or nil
    local function hasItem(id) return Gd.item(id) ~= nil end
    local function tmMove(id)
      local it = Gd.item(id)
      local mv = it and (it.teaches or (it.machine and it.machine.move))
      return mv and Gd.moveName(mv) or nil
    end
    local PRIZES = Host.gen == 1 and {
      { kind = "item", id = "NUGGET", cost = 10 }, { kind = "item", id = "RARE_CANDY", cost = 15 },
      { kind = "mon", dex = 63, cost = 40 }, { kind = "mon", dex = 35, cost = 40 },
      { kind = "item", id = "TM_ICE_BEAM", cost = 60 }, { kind = "item", id = "TM_THUNDERBOLT", cost = 60 },
      { kind = "item", id = "TM_FIRE_BLAST", cost = 60 }, { kind = "item", id = "TM_EARTHQUAKE", cost = 80 },
      { kind = "mon", dex = 123, cost = 90 }, { kind = "mon", dex = 127, cost = 90 },
      { kind = "item", id = "TM_HYPER_BEAM", cost = 100 }, { kind = "mon", dex = 147, cost = 150 },
      { kind = "mon", dex = 137, cost = 200 }, { kind = "item", id = "MASTER_BALL", cost = 600 },
    } or {
      { kind = "item", id = "NUGGET", cost = 10 }, { kind = "item", id = "RARE_CANDY", cost = 15 },
      { kind = "item", id = "PP_UP", cost = 25 }, { kind = "mon", dex = 63, cost = 40 }, { kind = "mon", dex = 35, cost = 40 },
      { kind = "item", id = "TM_THUNDER", cost = 60 }, { kind = "item", id = "TM_BLIZZARD", cost = 60 },
      { kind = "item", id = "TM_FIRE_BLAST", cost = 60 }, { kind = "item", id = "TM_EARTHQUAKE", cost = 80 },
      { kind = "mon", dex = 123, cost = 90 }, { kind = "mon", dex = 127, cost = 90 },
      { kind = "item", id = "TM_HYPER_BEAM", cost = 100 }, { kind = "mon", dex = 147, cost = 150 },
      { kind = "mon", dex = 137, cost = 200 }, { kind = "item", id = "MASTER_BALL", cost = 600 },
    }
    env.slots = makeSlots and makeSlots(noEngine, { save = mod.save, badges = badges, port = Port, prizes = PRIZES,
                                               hasItem = hasItem, tmMove = tmMove }) or nil
    if makeGts and env.auction and env.bx then
      env.gts = makeGts(noEngine, {
        save = mod.save, now = os.time, port = Port, hasItem = hasItem,
        seed = function(s) return env.auction.seedOf and env.auction.seedOf(s) or 1 end,
        pools = env.auction.pools, tierOf = env.auction.tierOf, minLevel = env.auction.minLevel,
        frlg = function() return false end, bx = env.bx, notify = notify,
      })
    end
    env.swarm = makeSwarm and Play and makeSwarm(noEngine, {
      now = os.time, session = session, seed = seed, routes = Play.routes,
      day = function(t) return env.journal and env.journal.day(t) or math.floor(t / 86400) end,
      badges = badges, on = function() return not Settings or Settings.get("swarms", true) ~= false end,
    }) or nil
    env.journal = makeJournal and makeJournal(noEngine, {
      save = mod.save, now = os.time, session = session, badges = badges, port = Port,
      swarm = function() return env.swarm and env.swarm.species() or nil end,
      leader = function(cls) return cls == 1 end,
      map = function() return Play and Play.mapNow(session()) or nil end,
    }) or nil
    if makeChallenges and env.journal then
      env.challenges = makeChallenges(noEngine, {
        save = mod.save, now = os.time, journal = env.journal, T = T, notify = notify, port = Port,
        seed = seed, badges = badges, frlg = function() return Host.gen == 1 end, canHatch = Host.gen == 2,
        itemName = env.itemName, typeName = env.typeName,
        swarmOn = function() return env.swarm ~= nil and env.swarm.on() end,
      })
    end
    if makeErrands and env.bx then
      env.errands = makeErrands(noEngine, { save = mod.save, now = os.time, bx = env.bx, T = T, notify = notify, port = Port,
                                       seed = seed, badges = badges })
    end
    if makeNews then
      env.news = makeNews(noEngine, {
        save = mod.save, now = os.time, T = T, notify = notify,
        journal = env.journal, swarm = env.swarm, auction = env.auction, gts = env.gts, errands = env.errands,
        challenges = env.challenges, place = Play and Play.place or function(m) return tostring(m) end,
        itemName = env.itemName,
        moveName = function(id) return id and Gd.moveName(id) or nil end,
        monName = function(sp) return Gd.speciesName(sp) end,
      })
    end
  end
  -- the Pokédex (src/gb/dex.lua): the window is Gen 3's; the picture a breathing still with a hop when chosen
  env.dexOption = function() return option("pokedex", true) ~= false end
  if Gd and makeDex then
    env.dex = makeDex(Host, Gd, { T = T, place = Play and Play.place or nil })
    env.cry = function(sp)
      local g, Sound = Host.game(), engine("src.core.Sound")
      if g and g.data and Sound and Sound.playCry then pcall(Sound.playCry, g.data, sp) end
    end
    env.dexSprite = {
      start = function() end, stop = function() end, pack = function() return false, nil end,
      draw = function(sp, cx, cy, size, clock, chosenAt, scale, alpha)
        local pic = Art and Art.pic(sp)
        if not pic then return end
        local G = Kit.graphics()
        local k0 = size * Kit.sc / pic.w
        local k = k0 * (scale or 1)
        local t = clock - (chosenAt or -10)
        local hop = (t >= 0 and t < 0.45) and math.sin(t / 0.45 * math.pi) * 2.5 * Kit.sc or 0
        local b = 1 + 0.022 * math.sin(clock * 2.3)
        G.setColor(1, 1, 1, alpha or 1)
        G.draw(pic.image, Kit.X(cx), Kit.Y(cy) + pic.h / 2 * k0 - hop, 0, k * (2 - b), k * b, pic.w / 2, pic.h)
      end,
    }
  end
  -- the Mart's clerk: the game's own overworld sprite (frames down, up, side: the window's order)
  local clerkSpr = nil
  env.clerk = function()
    if clerkSpr ~= nil then return clerkSpr or nil end
    clerkSpr = false
    local d = Gd and Gd.data()
    local set = d and (Host.gen == 2 and d.gen2Sprites or d.sprites)
    local spr = set and set.SPRITE_CLERK
    local Assets = engine("src.render.Assets")
    local ok, img = pcall(Assets and Assets.image or error, spr and spr.image)
    local G = love and love.graphics
    if ok and img and G and G.newQuad then
      local iw, ih = img:getDimensions()
      local n = math.max(1, math.floor(ih / 16))
      local quads = {}
      for i = 0, n - 1 do quads[i] = G.newQuad(0, i * 16, 16, 16, iw, ih) end
      clerkSpr = { image = img, quads = quads, width = 16, height = 16, frameCount = n }
    end
    return clerkSpr or nil
  end
  -- the News's anchor (the mod's own art, as on Gen 3)
  local ANCHOR = { talk = "assets/newscaster.png", cheer = "assets/newscaster-cheer.png",
                   shock = "assets/newscaster-shock.png" }
  local anchorArt = {}
  env.anchor = function(mood)
    local key = mood or "talk"
    local path = ANCHOR[key]
    if not path then return nil end
    if anchorArt[key] == nil then
      anchorArt[key] = false
      local LG = love and love.graphics
      local ok, img = pcall(mod.assets.image, mod.assets, path)
      if ok and img and LG and LG.newQuad then
        pcall(img.setFilter, img, "nearest", "nearest")
        local iw, ih = img:getDimensions()
        local n, quads = math.max(1, math.floor(iw / ih)), {}
        for i = 0, n - 1 do quads[i] = LG.newQuad(i * ih, 0, ih, ih, iw, ih) end
        anchorArt[key] = { image = img, quads = quads, n = n, size = ih, foot = 0 }
      end
    end
    return anchorArt[key] or nil
  end

  local Watch
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
    mart = env.mart and martWindow or nil,
    bank = env.bank and bankWindow or nil,
    auction = env.auction and auctionWindow or nil,
    auctionBadge = env.auction and function() return env.auction.unread() end or nil,
    slots = env.slots and slotsWindow or nil,
    gts = env.gts and gtsWindow or nil,
    gtsBadge = env.gts and function() return env.gts.waiting() end or nil,
    challenges = env.challenges and challengesWindow or nil,
    challengesBadge = env.challenges and function(ctx) return env.challenges.waiting(ctx and ctx.session or session()) end
      or nil,
    errands = env.errands and errandsWindow or nil,
    errandsBadge = env.errands and function() return env.errands.waiting() end or nil,
    news = env.news and newsWindow or nil,
    pokedex = env.dex and dexWindow and dexView and function(ctx, e) return dexWindow(ctx, e, dexView) end or nil,
    pokedexAvailable = env.dex and function(ctx)
      return env.dexOption() and env.dex.available(ctx.session or session())
    end or nil,
    map = env.map3d and function(ctx, e) return mapScene(ctx, e, { mode = "app" }) end or nil,
    settings = T and Settings and settingsWindow or nil,
  })
  -- Gen 2's own screens as apps: the bedroom's decorations (the room reloads after the PC when one
  -- moved) and the Pokégear's phone (the game's calls, their scripts and all)
  if gen == 2 then
    Apps.register({ id = "decorate", labelKey = "app.decorate", label = "Decorate", glyph = "home",
                    color = { 156, 112, 220 }, order = 50,
                    available = function(ctx) return ctx.mode == "bedroom" end,
                    open = function(ctx) ctx.over(function(back) Host.decorate(back) end) end })
    Apps.register({ id = "phone", labelKey = "app.phone", label = "Phone", glyph = "phone",
                    color = { 52, 199, 89 }, order = 31,
                    available = function(ctx) return Host.hasPhone(ctx.session or session()) end,
                    open = function(ctx) ctx.over(function(back) Host.pokegear(back) end) end })
  end
  Nt = makeNotify and makeNotify({
    K = Kit, T = T, now = env.now, epoch = os.time, se = env.se, apps = Apps, monIcon = env.monIcon,
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
  Desktop0, Watch0 = Desktop, Watch
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

  -- once a second: R-Bay's auctions and the GTS settle, challenges and errands, the News's day, a Badge
  local function tick()
    local open = Desktop.isOpen() and Desktop.state() or (Watch and Watch.isOpen() and Watch.state())
    local s = open and open.ctx and open.ctx.session or session()
    if not s then return end
    if env.auction then
      local okA, won, _, sp = pcall(env.auction.settle, s)
      if okA and won and won > 0 and sp and Desktop.isOpen() then Desktop.padTransfer(sp, "in", "ball") end
    end
    if env.gts then pcall(env.gts.settle, s) end
    if env.challenges then pcall(env.challenges.check, s) end
    if env.errands then pcall(env.errands.settle, s) end
    if env.news then pcall(env.news.tick, s) end
    if Play then pcall(Play.tick, s) end
  end

  -- the 3D map's region built in the background, a few milliseconds a frame, once the player's been in
  -- the field a few seconds (so the Map opens at once); which region, looked at once a second
  local mapPrep = { at = nil, game = nil, want = nil, nextLook = 0, built = {} }
  local function frame(game)
    local m3 = env.map3d
    if not m3 then return end
    local g = gameId()
    if mapPrep.game ~= g then mapPrep.game, mapPrep.at, mapPrep.want, mapPrep.built = g, nil, nil, {} end
    local now = love and love.timer and love.timer.getTime() or 0
    if not (Sh and Sh.free(game)) then return end
    if not mapPrep.want then
      if now < mapPrep.nextLook then return end
      mapPrep.nextLook = now + 1
      local okH, rid = pcall(m3.model.regionHere, session())
      if not (okH and rid) or mapPrep.built[rid] then return end
      mapPrep.want, mapPrep.at = rid, now + 4
    end
    if now < mapPrep.at then return end
    local rid = mapPrep.want
    m3.model.prepare(rid)
    if m3.model.step(0.004) then return end
    local region = m3.model.region(rid)
    if region and region.world and love and love.graphics and m3.render.prepare(love.graphics, region, 0.004) then
      return
    end
    mapPrep.built[rid], mapPrep.want = true, nil
  end

  Sh = makeShell(mod, { require = require, log = mod.log, desktop = Desktop, apps = Apps, watch = Watch,
                        notify = Nt, tick = tick, session = session, townmap = TownMap, host = Host, frame = frame,
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
  mod.events:on("save.loaded", function(ev)
    Sh.forget()
    if Play then Play.resetBadges() end
    local s = ev and ev.save or session()
    if env.auction then pcall(env.auction.settle, s) end
    if env.gts then pcall(env.gts.settle, s) end
    if env.errands then pcall(env.errands.settle, s) end
  end)
  -- the journal's events (the game's own, as the journal reads them) and the daily swarm's encounters
  if Play and env.journal then pcall(Play.attach, mod, env.journal) end
  if env.swarm then
    mod.hooks:wrap("encounter.species", function(nxt, enc, ctx, ...)
      local got = nxt(enc, ctx, ...)
      local ok, swapped = pcall(env.swarm.encounter, got, ctx)
      return ok and swapped or got
    end)
  end

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
                        bx = env.bx, inv = env.inv, mb = env.mb, hall = env.hall, oak = env.oak, port = Port, play = Play,
                        mart = env.mart, bank = env.bank, auction = env.auction, slots = env.slots, gts = env.gts,
                        journal = env.journal, swarm = env.swarm, challenges = env.challenges, errands = env.errands,
                        news = env.news, dex = env.dex,
                        settings = Settings, wall = Wall, arrange = Arrange, watch = Watch, pad = Watch,
                        notify = Nt, tick = tick, townmap = TownMap, host = Host }
end
