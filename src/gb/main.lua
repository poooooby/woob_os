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
  local boxesSummary = loadSibling(mod, "src/apps/boxes_summary.lua")
  local itemsWindow, mailWindow = loadSibling(mod, "src/apps/items.lua"), loadSibling(mod, "src/apps/mail.lua")
  local hallWindow, oakWindow = loadSibling(mod, "src/apps/hall.lua"), loadSibling(mod, "src/apps/oak.lua")
  -- the play-tied apps: Gen 3's models over the Game Boy games' port (src/gb/port.lua) and play (src/gb/play.lua)
  local makePort, makePlay = loadSibling(mod, "src/gb/port.lua"), loadSibling(mod, "src/gb/play.lua")
  local makeMart, martWindow = loadSibling(mod, "src/gb/mart.lua"), loadSibling(mod, "src/apps/mart.lua")
  local makeGen3Icons = loadSibling(mod, "src/gb/gen3_icons.lua")
  local makeBank, bankWindow = loadSibling(mod, "src/bank.lua"), loadSibling(mod, "src/apps/bank.lua")
  local makeAuction, auctionWindow = loadSibling(mod, "src/auction.lua"), loadSibling(mod, "src/apps/auction.lua")
  local makeSlots, slotsWindow = loadSibling(mod, "src/slots.lua"), loadSibling(mod, "src/apps/slots.lua")
  local makeGts, gtsWindow = loadSibling(mod, "src/gts.lua"), loadSibling(mod, "src/apps/gts.lua")
  local makeJournal, makeSwarm = loadSibling(mod, "src/journal.lua"), loadSibling(mod, "src/swarm.lua")
  local makeChallenges, challengesWindow = loadSibling(mod, "src/challenges.lua"), loadSibling(mod, "src/apps/challenges.lua")
  local makeErrands, errandsWindow = loadSibling(mod, "src/errands.lua"), loadSibling(mod, "src/apps/errands.lua")
  local makeNews, newsWindow = loadSibling(mod, "src/news.lua"), loadSibling(mod, "src/apps/news.lua")
  local makeDex, dexWindow = loadSibling(mod, "src/gb/dex.lua"), loadSibling(mod, "src/apps/pokedex.lua")
  local makeSpawnArea = loadSibling(mod, "src/spawn_area.lua")
  local dexView = loadSibling(mod, "src/apps/pokedex_view.lua")
  -- the 3D map: the Game Boy maps built to scale (src/gb/map3d.lua), drawn by Gen 3's renderer and window
  local makeGbMap, makeWorld = loadSibling(mod, "src/gb/map3d.lua"), loadSibling(mod, "src/map3d/world.lua")
  local makeMapRender, mapScene = loadSibling(mod, "src/map3d/render.lua"), loadSibling(mod, "src/map3d/scene.lua")
  -- Gold / Silver / Crystal's Pokégear: the Phone (its phone book, the game's calls) and the Radio
  local makePhone, phoneWindow = loadSibling(mod, "src/gb/phone.lua"), loadSibling(mod, "src/apps/phone.lua")
  local makeRadio, radioWindow = loadSibling(mod, "src/gb/radio.lua"), loadSibling(mod, "src/apps/radio.lua")
  -- the real shops: every shop counter opens the Mart full screen
  local makeGbShop, makeShop = loadSibling(mod, "src/gb/realshop.lua"), loadSibling(mod, "src/shop.lua")
  local ShopThemes = loadSibling(mod, "src/shop_themes.lua")
  local makeTowns = loadSibling(mod, "src/map3d/towns.lua")
  local makeMarks = loadSibling(mod, "src/marks.lua")
  -- Gold / Silver / Crystal's GPS: the walk graph over every map, the waypoint's route, the field's arrow
  local makeGpsGraph, makeGpsRoute = loadSibling(mod, "src/gps/graph.lua"), loadSibling(mod, "src/gps/route.lua")
  local makeGpsArrow, makeGpsReader = loadSibling(mod, "src/gps/arrow.lua"), loadSibling(mod, "src/gps/read2.lua")
  -- the Pokémon Center: the nurse's counter full screen
  local makePokecenter, pokecenterWindow = loadSibling(mod, "src/gb/pokecenter.lua"), loadSibling(mod, "src/apps/pokecenter.lua")
  local pokecenterView, makeNurseArt = loadSibling(mod, "src/apps/pokecenter_view.lua"), loadSibling(mod, "src/nurse_art.lua")
  local makeSizeArt = loadSibling(mod, "src/size_art.lua")
  local stallView = loadSibling(mod, "src/apps/stall_view.lua")
  local summaryCtl = loadSibling(mod, "src/apps/summary_ctl.lua")
  local typeArt = loadSibling(mod, "src/apps/type_art.lua")
  local makeLighting = loadSibling(mod, "src/lighting.lua")
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
  local env
  local Host = makeHost(mod, { gen = gen, require = require, log = mod.log, dexOn = dexOn,
                               gearOn = function() return option("pokegear", true) ~= false end,
                               padOn = function() return not env or env.padOption() end,
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
  -- (WoobleSpritePack, g9-battle-sprites-gen3, while it's active: its party icons)
  local function spritePack()
    local m = mod.find("g9-battle-sprites-gen3")
    local ex = m and m.exports
    local okA, on = pcall(ex and ex.isActive or error)
    return okA and on == true and ex or nil
  end
  local Art = Gd and makeArt and makeArt(Host, Gd, Kit, { pack = spritePack }) or nil

  local Wall = makeWall and makeWall({
    K = Kit, gameId = gameId,
    list = function(dir) return mod:list(dir) end,
    image = function(path) return mod.assets:image(path) end,
    log = warn,
  })
  local function wallpaper() return Settings and Settings.get("wallpaper", "classic") or "classic" end
  local function wallpaperFit() return Settings and Settings.get("wallpaperFit", "fill") or "fill" end
  env = {
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
    setSetting = function(key, v)
      if Settings then Settings.set(key, v) end
      if key == "textSize" then Kit.setTextScale((tonumber(v) or 100) / 100) end
      if key == "theme" then Kit.setTheme(v) end
    end,
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
    -- a TM's move where the game has no words for it (Red / Blue / Yellow): "Fighting · Power 75 · Acc. 100% · PP 15"
    Gd.moveLine = function(_, m)
      if type(m) ~= "table" or not T then return nil end
      local power = tonumber(m.power) or 0
      return string.format("%s · %s %s · %s %d%% · %s %d", env.typeName(m.type), T("dex.col.power"),
        power > 1 and tostring(power) or "—", T("dex.col.acc"), tonumber(m.accuracy) or 0, T("dex.col.pp"),
        tonumber(m.pp) or 0)
    end
    -- a species' icon (frame 0 / 1, tinted r, g, b, a), a Pokémon's own, a species' front picture
    env.monIcon = function(sp, x, y, size, frame, r, g, b, a) if Art then Art.drawIcon(sp, x, y, size, frame, r, g, b, a) end end
    env.monIconOf = function(mon, x, y, size, frame, a)
      if Art and type(mon) == "table" then Art.drawIcon(mon.species, x, y, size, frame, 1, 1, 1, a, mon) end
    end
    env.monPic = function(sp, x, y, size, a, mon) return Art ~= nil and Art.drawPic(sp, x, y, size, a, mon) end
  end
  -- an item's picture: the Game Boy games have none, so Gen 3's when a Gen 3 game is imported too
  -- (src/gb/gen3_icons.lua), else a tile in its pocket's colour with one of the desktop's pictures on it
  -- (a TM in its move's type's colour)
  local Gi = Gd and makeGen3Icons and makeGen3Icons(engine, Gd) or nil
  env.gen3Icons = Gi
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
      t = { colour = colour, glyph = base[2], gb = id }
      tileOf[key] = t
    end
    local G = Kit.graphics()
    -- (`a` is the whole alpha, the kit's fade already in it, as the Gen 3 icons take it; none: the fade)
    if Gi and t.gen3 ~= false then
      local drawn = Gi.draw(G, t.gb, Kit.X(x), Kit.Y(y), size * Kit.sc / 24, a or Kit.getFade())
      if drawn then return end
      t.gen3 = false
    end
    local b = Kit.R(x + size * 0.06, y + size * 0.06, size * 0.88, size * 0.88)
    -- (`a` is the whole alpha, the kit's fade already in it, as the Gen 3 icons take it; none: the fade)
    local al = a or Kit.getFade()
    local c = t.colour
    G.setColor(c[1] / 255, c[2] / 255, c[3] / 255, (c[4] or 1) * al)
    Kit.box("fill", b, size * 0.24)
    if Desktop and Desktop.glyph then
      pcall(Desktop.glyph, G, t.glyph, Kit.X(x + size / 2), Kit.Y(y + size / 2), size * Kit.sc * 0.62, al, t.colour)
    end
  end
  env.inv = Gd and makeInv and makeInv(Host, Gd) or nil
  env.bx = Gd and makeBx and makeBx(Host, Gd, Art, { save = mod.save }) or nil
  env.mb = Gd and Host.gen == 2 and makeMb and makeMb(Host, Gd) or nil
  if Gd and makeHall then env.hall, env.oak = makeHall(Host, Gd) end

  -- ------- the play-tied apps
  local Nt
  local NOTIFY_APP = { gts = "gts", bank = "bank", challenge = "challenges", errand = "errands", swarm = "news",
                       gps = "map" }
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
  -- (the map's markers: the save's own)
  if makeMarks then env.marks = makeMarks({ save = mod.save }) end
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
      -- (Gold / Silver / Crystal: Fly from the app, as the party menu's; Red / Blue / Yellow: none)
      flyCheck = function(ctx, s) return Model.flyCheck(s or (ctx and ctx.session) or session()) end,
      fly = function(ctx, region, place)
        local s = ctx.session or session()
        local mon, why = Model.flyCheck(s)
        if not mon then return false, why end
        if not (place and place.spawn) then return false, "none" end
        ctx.done()
        return Model.flyTo(place, mon), "none"
      end,
      invert = function()
        return option("mapInvertX", false) == true, option("mapInvertY", false) == true
      end,
    }
  end
  -- the GPS (Gold / Silver / Crystal): the walk graph built once in the background (kept on disk), the
  -- waypoint's route, the field's arrow (Settings: fieldGps, off unless turned on)
  local Gps
  if gen == 2 and env.map3d and makeGpsGraph and makeGpsRoute and makeGpsReader then
    local Version = engine("src.core.Version")
    local function gameData()
      local g = Host.game()
      return g and g.data or nil
    end
    local function world()
      local g = Host.game()
      local w = g and g.world
      return type(w) == "table" and w or nil
    end
    local graph = makeGpsGraph(engine, {
      reader = makeGpsReader,
      maps = function() local d = gameData(); return d and d.gen2Maps or nil end,
      tilesets = function() local d = gameData(); return d and d.gen2Tilesets or nil end,
      -- (the blocks Cut, Whirlpool and the scripts changed: their first values, as the World kept them)
      edits = function(id)
        local w = world()
        return w and type(w.blockEdits) == "table" and w.blockEdits[id] or nil
      end,
      cache = mod.cache, gameId = gameId, version = version, engine = Version and Version.engine, log = warn })
    local JOHTO = { "ZEPHYR", "HIVE", "PLAIN", "FOG", "STORM", "MINERAL", "GLACIER", "RISING" }
    local eventIds
    local function eventFlag(name)
      local d = gameData()
      if eventIds == nil then
        local FI = engine("src.core.gen2.FlagIds")
        local ok, ids = pcall(FI and FI.events or error, d and d.gen2Constants)
        eventIds = ok and type(ids) == "table" and ids or false
      end
      return eventIds and eventIds[name] or nil
    end
    local function hasItem(s, id)
      local inv = s and s.inventory
      return type(inv) == "table" and (tonumber(inv[id]) or 0) > 0
    end
    local route = makeGpsRoute(engine, {
      graph = graph, save = mod.save, session = session, log = warn,
      -- (where the player stands: the World's own map and square, and whether they're surfing)
      where = function()
        local w = world()
        local g = Host.game()
        if not (w and w.map and w.player) then return nil end
        local FM = engine("src.world.gen2.FieldMoves")
        local okS, surfing = pcall(FM and FM.isSurfing or error, w.playerState)
        return w.map.id, tonumber(w.player.cellX) or 0, tonumber(w.player.cellY) or 0, okS and surfing == true,
          g and g.save
      end,
      -- (a town's maps: those of its landmark, as the 3D map's places are made)
      inSection = function(mapId, sec)
        local d = gameData()
        local def = d and d.gen2Maps and d.gen2Maps[mapId]
        return def ~= nil and ("lm" .. tostring(def.landmark or mapId)) == sec
      end,
      -- (what the player can use or pass: an HM's badge and a Pokemon that knows it; a gate's flag, item, Badges)
      can = function(s, key, h)
        local FM = engine("src.world.gen2.FieldMoves")
        if not (FM and s) then return false end
        local w = world()
        local ev = w and w.events
        if key == "FLAG" then
          if not (ev and h and h.flag) then return false end
          return ev:objectVisible(h.flag) == false
        elseif key == "ITEM" then
          if not (h and hasItem(s, h.item)) then return false end
          if h.event then
            local id = eventFlag(h.event)
            return ev ~= nil and id ~= nil and ev:get(id) == true
          end
          return true
        elseif key == "BADGES" then
          local n = 0
          for _, b in ipairs(JOHTO) do
            local ok, yes = pcall(FM.hasBadge, s, b)
            if ok and yes then n = n + 1 end
          end
          return n >= ((h and h.count) or 8)
        end
        local badge = FM.BADGE and FM.BADGE[key]
        if badge then
          local okB, yes = pcall(FM.hasBadge, s, badge)
          if not (okB and yes) then return false end
        end
        local okU, mon = pcall(FM.partyMoveUser, s.party, key)
        return okU and mon ~= nil and mon ~= false
      end,
      notify = function(kind, data) if Nt then Nt.push(kind, data) end end,
    })
    -- (the arrow: the field's camera and where the World's picture went on the window this frame)
    local arrow = makeGpsArrow and makeGpsArrow({
      K = Kit, route = route,
      on = function() return Settings ~= nil and Settings.get("fieldGps", false) == true end,
      player = function(vp)
        local w = world()
        if not (w and w.map and w.player and w.camera and type(vp) == "table") then return nil end
        local Tilt, Pipes = engine("src.render.Tilt"), engine("src.render.Pipelines")
        local okT, tilted = pcall(Tilt and Tilt.active or error)
        if okT and tilted then return nil end
        local okP, pipe = pcall(Pipes and Pipes.worldPipeline or error)
        if okP and pipe then return nil end
        local Pf = engine("src.render.Playfield")
        if not Pf then return nil end
        local okR, x, y, pw, ph = pcall(Pf.rect, tonumber(vp.width) or 0, tonumber(vp.height) or 0)
        if not okR then return nil end
        local G2 = engine("src.core.Game2")
        local okF, bx, by = pcall(G2 and G2.faithfulBox or error, pw, ph)
        if okF and bx then x, y = x + bx, y + by end
        local okZ, sc = pcall(w.zoomScale, w)
        if not (okZ and tonumber(sc)) then return nil end
        local p = w.player
        return tonumber(p.px), tonumber(p.py), w.map.id, tonumber(w.camera.x), tonumber(w.camera.y), x, y, sc, sc
      end,
    }) or nil
    Gps = { graph = graph, route = route, arrow = arrow, at = nil }
    env.gps = {
      ready = graph.ready,
      work = function(budget)
        graph.prepare()
        graph.step(budget)
      end,
      set = route.set, clear = route.clear, dest = route.dest, line = route.line, spotAt = route.spotAt,
      needs = function() return route.needs end, hms = function() return route.HMS end,
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
                                               hasItem = hasItem, T = T, seed = seed,
                                               day = function(t) return env.journal and env.journal.day(t) or math.floor(t / 86400) end,
                                               untilNext = function(t)
                                                 local lt = env.journal and env.journal.localTime(t) or t
                                                 return 86400 - lt % 86400
                                               end }) or nil
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
      -- (a legendary or mythical Pokémon, by R-Bay's tiers: its battle is followed for the News)
      legend = function(sp)
        local tier = env.auction and env.auction.tierOf(sp)
        return tier == "legendary" or tier == "mythical"
      end,
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
  -- (the WoobPad option: off, no START row, and the game's own Pokégear from START)
  env.padOption = function() return option("woobpad", true) ~= false end
  if Gd and makeDex then
    -- (WoobleSpawns, modern_spawns: the wild Pokémon it places, for the Where tab)
    local spawnArea = makeSpawnArea and makeSpawnArea({
      gen = Host.gen,
      spawns = function()
        local m = mod.find("modern_spawns")
        return m and m.exports or nil
      end,
    })
    env.dex = makeDex(Host, Gd, { T = T, place = Play and Play.place or nil, spawnArea = spawnArea })
    env.cry = function(sp)
      local g, Sound = Host.game(), engine("src.core.Sound")
      if g and g.data and Sound and Sound.playCry then pcall(Sound.playCry, g.data, sp) end
    end
    local measured = {}
    env.dexSprite = {
      start = function() end, stop = function() end,
      -- (where the picture's drawn pixels sit in draw()'s size x size box round cx, cy, as fractions of
      -- size: { fx0, fy0, fx1, fy1 }; read once per species (the Size tab's chart); nil without one)
      measure = function(sp)
        local m = measured[sp]
        if m == nil then
          m = false
          local pic = Art and Art.pic(sp)
          local Sz = env.sizeArt
          if pic and Sz then
            local u0, v0, u1, v1 = Sz.bounds(pic.image)
            local box = pic.box or pic.w
            if u0 and box then
              m = { fx0 = (u0 - pic.w / 2) / box, fx1 = (u1 - pic.w / 2) / box,
                    fy0 = (v0 - pic.h + box / 2) / box, fy1 = (v1 - pic.h + box / 2) / box }
            end
          end
          measured[sp] = m
        end
        return m or nil
      end,
      -- (WoobleSpritePack drawing it: true, its picture now)
      pack = function(sp)
        local pic = Art and sp and Art.livePic(sp)
        return pic ~= nil, pic
      end,
      draw = function(sp, cx, cy, size, clock, chosenAt, scale, alpha, shiny, mon)
        -- (WoobleSpritePack's animation, else the game's picture breathing; `mon`: that Pokémon's own, a
        -- shiny in its colours)
        local packPic = Art and not shiny and Art.livePic(sp)
        local pic = packPic or (Art and Art.pic(sp, mon))
        if not pic then return end
        local G = Kit.graphics()
        local box = pic.box or pic.w
        local k0 = size * Kit.sc / box
        local k = k0 * (scale or 1)
        local t = clock - (chosenAt or -10)
        local hop = (t >= 0 and t < 0.45) and math.sin(t / 0.45 * math.pi) * 2.5 * Kit.sc or 0
        local b = packPic and 1 or 1 + 0.022 * math.sin(clock * 2.3)
        G.setColor(1, 1, 1, alpha or 1)
        -- (its feet on the box's bottom)
        G.draw(pic.image, Kit.X(cx), Kit.Y(cy) + box / 2 * k0 - hop, 0, k * (2 - b), k * b, pic.w / 2, pic.h)
      end,
    }
  end
  -- the Mart's clerk: the game's own overworld sprite (frames down, up, side: the window's order), made
  -- the way the field makes its people (SpriteRenderer.new), so a mod's sprite set (Facets) is his too;
  -- made again after any mod's option changes (a set chosen or turned off)
  local clerkSpr = nil
  -- (a mod's sheet for him, as the field would draw him: its image and frames as they are; nil = the game's)
  local function moddedClerk(spr)
    local SR = engine("src.render.SpriteRenderer")
    if not (SR and SR.new and type(spr) == "table") then return nil end
    local ok, r = pcall(SR.new, spr, "woob_os_clerk")
    if not (ok and type(r) == "table" and r.def ~= nil and r.def ~= spr and r.image and r.frames) then return nil end
    local fw, fh = tonumber(r.frameWidth), tonumber(r.frameHeight)
    if not (fw and fh and r.frames[0]) then return nil end
    return { image = r.image, quads = r.frames, width = fw, height = fh, frameCount = tonumber(r.frameCount) or 1,
             grey = type(r.def) == "table" and not r.def.trueColor and not r.def.gbaArt }
  end
  env.clerk = function()
    if clerkSpr ~= nil then return clerkSpr or nil end
    clerkSpr = false
    local d = Gd and Gd.data()
    local set = d and (Host.gen == 2 and d.gen2Sprites or d.sprites)
    local spr = set and set.SPRITE_CLERK
    local G = love and love.graphics
    local mine = moddedClerk(spr)
    if mine and not mine.grey then
      clerkSpr = mine
      return clerkSpr
    end
    local Assets = engine("src.render.Assets")
    local ok, img = true, mine and mine.image
    if not img then ok, img = pcall(Assets and Assets.image or error, spr and spr.image) end
    -- (the game's grey sheet painted in its colours: Gen 2 the clerk's own palette, Gen 1 a shopkeeper's)
    if ok and img and Art and Art.colourSheet then
      local cols
      if Host.gen == 2 then
        local Pal = engine("src.world.gen2.Palettes")
        local okP, c = pcall(Pal and Pal.spritePalette or error, d.gen2Palettes, "DAY", spr)
        cols = okP and c or nil
      else
        cols = { { 248, 248, 248 }, { 248, 200, 152 }, { 72, 120, 216 }, { 24, 24, 40 } }
      end
      local okC, painted = pcall(Art.colourSheet, img, cols)
      if okC and painted then img = painted end
    end
    if mine and ok and img then
      -- (a mod's grey sheet: painted as the game's would be, its own frames)
      mine.image, mine.grey = img, nil
      clerkSpr = mine
    elseif ok and img and G and G.newQuad then
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
  env.nurse = makeNurseArt and makeNurseArt(mod) or nil
  -- (the Pokédex's Size tab: the trainer it measures against, and a picture's drawn pixels)
  env.sizeArt = makeSizeArt and makeSizeArt(mod, Kit) or nil
  -- (the Size tab's heights: WoobleDex's measured ones (exports.artHeights, its data/art_heights.lua: each
  -- WoobleSprite picture's height standing, in metres), by species id (the sprite's, as the games' own: PIKACHU, NIDORAN_F), else by National Dex number; nil
  -- without WoobleDex or a row: the Pokédex's own height from the game)
  local artRows = nil
  env.artHeight = function(sp, nat)
    if artRows == nil then
      artRows = false
      local nd = mod.find("national_dex_gen3")
      local okA, all = pcall(nd and nd.exports and nd.exports.artHeights or error)
      if okA and type(all) == "table" then
        artRows = { byKey = {}, byDex = {} }
        for id, r in pairs(all) do
          if type(r) == "table" and tonumber(r.standing) then
            artRows.byKey[id] = r
            local d, sl = tonumber(r.dex), tonumber(r.slot) or math.huge
            local was = d and artRows.byDex[d]
            if d and (not was or (tonumber(was.slot) or math.huge) > sl) then artRows.byDex[d] = r end
          end
        end
      end
    end
    if not artRows then return nil end
    return artRows.byKey[sp] or (nat and artRows.byDex[tonumber(nat)]) or nil
  end

  env.stallView = stallView or nil
  env.summaryCtl = summaryCtl or nil
  env.typeArt = typeArt and env.K and typeArt(env.K) or nil
  env.lighting = makeLighting and makeLighting({ log = function(fmt, ...) mod.log:warn(fmt, ...) end }) or nil

  -- (Gold / Silver / Crystal: the Pokégear's phone book; a tap stands in for A in a call's boxes)
  if gen == 2 and makePhone then
    env.phone = makePhone(Host, { save = mod.save, now = os.time, place = Play and Play.place or nil,
                                  tap = function(btn)
                                    local g = Host.game()
                                    if g and mod.input and mod.input.tap then mod.input:tap(g, btn) end
                                  end })
  end
  local Watch
  local Apps = makeApps({
    icons = Icons,
    store = storeWindow,
    removed = Settings and function() return Settings.get("removedApps", "") end or nil,
    saveRemoved = Settings and function(text) Settings.set("removedApps", text) end or nil,
    boxes = env.bx and boxesWindow and boxesView
      and function(ctx, e) return boxesWindow(ctx, e, boxesView, boxesSummary) end or nil,
    items = env.inv and itemsWindow or nil,
    mail = env.mb and mailWindow or nil,
    phone = env.phone and phoneWindow or nil,
    phoneAvailable = env.phone and function(ctx) return env.phone.available(ctx.session or session()) end or nil,
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
  -- moved); the Radio, once the Pokégear has its card (the game's shows and music)
  if gen == 2 and makeRadio and radioWindow then
    env.radio = makeRadio(Host)
    Apps.register({ id = "radio", labelKey = "app.radio", label = "Radio", glyph = "radio",
                    color = { 255, 120, 60 }, order = 31.5,
                    available = function(ctx) return env.radio.available(ctx.session or session()) end,
                    window = radioWindow })
  end
  if gen == 2 then
    Apps.register({ id = "decorate", labelKey = "app.decorate", label = "Decorate", glyph = "home",
                    color = { 156, 112, 220 }, order = 50,
                    available = function(ctx) return ctx.mode == "bedroom" end,
                    open = function(ctx) ctx.over(function(back) Host.decorate(back) end) end })
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
    kit = Kit, T = T, env = env, se = env.se, scene = mapScene, log = function(fmt, ...) mod.log:warn(fmt, ...) end,
  }) or nil
  env.pad = { transfer = function(id, dir, kind)
    if Desktop.isOpen() then Desktop.padTransfer(id, dir, kind) end
  end }
  env.apps = Apps
  env.appIcon = function(app, x, y, size, a) Desktop.appIcon(app, x, y, size, nil, a) end
  env.glyph = Desktop.glyph
  env.amount = function(n, x, y, size, c, measure) return Desktop.amount(n, x, y, size, c, measure) end

  -- the text size (Settings > Display, the mod option), on the kit: at load, once a second, and at once
  -- when the Settings app changes it
  local function applyTextSize()
    local pct = Settings and Settings.textSize(option("textSize", 100)) or tonumber(option("textSize", 100)) or 100
    Kit.setTextScale(pct / 100)
    -- (the theme, the same way: Light, Dark or OLED)
    Kit.setTheme(Settings and Settings.theme(option("theme", "light")) or option("theme", "light"))
  end
  applyTextSize()
  -- once a second: R-Bay's auctions and the GTS settle, challenges and errands, the News's day, a Badge
  local function tick()
    applyTextSize()
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
    -- (the GPS's walk graph: once the map's region is ready, a few milliseconds a frame; read back from the
    -- disk after the first time)
    if Gps and not mapPrep.want and not Gps.graph.ready() then
      Gps.at = Gps.at or now + 6
      if now >= Gps.at then
        Gps.graph.prepare()
        Gps.graph.step(0.003)
      end
    end
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
                        fieldDraw = Gps and Gps.arrow and function(G, vp, free, t) Gps.arrow.draw(G, vp, free, t) end or nil,
                        map3d = env.map3d, padOn = function() return env.padOption() end,
                        watchRow = function() return not Settings or Settings.get("watchRow", true) ~= false end,
                        watchLabel = function() return T and T("watch.start") or "WATCH" end })
  Sh.enabled = function() return option("desktop", true) ~= false end

  Host.install()
  if makeGbShop and makeShop and ShopThemes and env.mart and Gd then
    env.realShop = makeGbShop(Host, Gd, {
      Sh = Sh, base = env.mart, T = T, makeShop = makeShop, themes = ShopThemes, clerk = env.clerk,
      place = Play and Play.place or nil, screens = mod.content and mod.content.screens,
      on = function() return option("realShops", true) ~= false end,
      log = function(fmt, ...) mod.log:warn(fmt, ...) end,
    })
    local okS, errS = pcall(env.realShop.install)
    if not okS then mod.log:warn("the shops keep their own screens: %s", tostring(errS)) end
  end
  -- the Pokémon Center: the nurse's counter (src/gb/pokecenter.lua; the window is an app that's never on
  -- the home screen: Sh.openFull opens it by id)
  if makePokecenter and pokecenterWindow and pokecenterView and Gd then
    Apps.register({ id = "pokecenter", labelKey = "nurse.title", label = "Pokémon Center", glyph = "pokeball",
                    color = { 236, 80, 110 }, order = 99, pad = false, available = function() return false end,
                    window = function(ctx, e) return pokecenterWindow(ctx, e, pokecenterView) end })
    env.pokecenter = makePokecenter(Host, Gd, {
      Sh = Sh, hooks = mod.hooks, on = function() return option("pokecenter", true) ~= false end,
      log = function(fmt, ...) mod.log:warn(fmt, ...) end,
    })
    -- (Gold / Silver / Crystal: the nurse's script, caught as it starts; Red / Blue / Yellow: at game.ready)
    if gen == 2 then pcall(env.pokecenter.install) end
  end
  local okI, errI = pcall(Sh.install)
  if not okI then mod.log:warn("the desktop's hooks failed: %s", tostring(errI)) end
  mod.events:on("game.ready", function(ev)
    if ev and ev.game then Host.bind(ev.game) end
    local ok, err = pcall(Sh.ready)
    if not ok then mod.log:warn("the PC keeps its own menu: %s", tostring(err)) end
    if env.pokecenter and gen == 1 then
      local okP, errP = pcall(env.pokecenter.install)
      if not okP then mod.log:warn("the nurse keeps her own counter: %s", tostring(errP)) end
    end
  end)
  mod.events:on("map.entered", function() Sh.forget() end)
  -- the GPS: each step and each map (there yet? the arrow's next warp); a loaded save's own waypoint; Fly
  -- (the game's or ours: both through World:flyTo, wrapped once per process) clears the waypoint
  if Gps then
    mod.events:on("world.stepped", function(ev)
      if type(ev) == "table" and Gps.route.dest() then
        pcall(Gps.route.step, ev.mapId, tonumber(ev.x) or 0, tonumber(ev.y) or 0)
      end
    end)
    mod.events:on("map.entered", function(ev)
      Gps.route.refresh()
      local g = Host.game()
      local p = g and g.world and g.world.player
      if type(ev) == "table" and Gps.route.dest() and p then
        pcall(Gps.route.step, ev.mapId, tonumber(p.cellX) or 0, tonumber(p.cellY) or 0)
      end
    end)
    local World = engine("src.world.gen2.World")
    if World and World.flyTo then
      local w = rawget(World, "__woobOsGps")
      if not w then
        w = { orig = World.flyTo }
        World.__woobOsGps = w
        World.flyTo = function(...)
          if w.impl then pcall(w.impl) end
          return w.orig(...)
        end
      end
      w.impl = function() Gps.route.clear() end
    end
  end
  -- (a sprite set chosen or turned off in another mod: the clerk made again)
  mod.events:on("mod.options_changed", function() clerkSpr = nil end)
  mod.events:on("checkpoint.restored", function() if env.marks then pcall(env.marks.load) end end)
  mod.events:on("save.loaded", function(ev)
    Sh.forget()
    if env.marks then pcall(env.marks.load) end
    if Gps then pcall(Gps.route.load) end
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
  mod.exports._test = { post = notify, desktop = Desktop, shell = Sh, apps = Apps, kit = Kit, env = env, i18n = T, gd = Gd, art = Art,
                        marks = env.marks, gps = Gps,
                        bx = env.bx, inv = env.inv, mb = env.mb, hall = env.hall, oak = env.oak, port = Port, play = Play,
                        mart = env.mart, bank = env.bank, auction = env.auction, slots = env.slots, gts = env.gts,
                        journal = env.journal, swarm = env.swarm, challenges = env.challenges, errands = env.errands,
                        news = env.news, dex = env.dex, pokecenter = env.pokecenter,
                        settings = Settings, wall = Wall, arrange = Arrange, watch = Watch, pad = Watch,
                        notify = Nt, tick = tick, townmap = TownMap, host = Host }
end
