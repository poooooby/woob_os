-- WoobOS (woob_os): the PC as a modern desktop (Gen 3 here; the Game Boy games: src/gb/main.lua).
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
--   src/dex.lua, src/apps/pokedex.lua, src/apps/pokedex_view.lua   the Pokédex (the game's own taken over)
--   src/gts.lua, src/apps/gts.lua       the GTS: Wonder Trade and the Global Trade Station, its window
--   src/boxes.lua, src/apps/boxes.lua, src/apps/boxes_view.lua, src/apps/boxes_summary.lua   the Pokémon
--     model, the Boxes window and its summary
--   src/i18n.lua, lang/*.lua            the words, by language ; src/settings.lua the kept choices
--   src/wallpaper.lua                   the drawn wallpapers and the wallpapers/ folder's pictures
--   WoobPad: src/desktop.lua again (deps.device "pad"), from the START menu
--   src/notify.lua                      the notifications (R-Bay, the GTS): a list and banners
--   src/map3d/model.lua, render.lua, scene.lua, towns.lua   the region in 3D (from the game's Town
--                                       Map), its drawing, its window (the Map app), its towns' buildings
--   src/map3d/world.lua, cache.lua      the region built to scale from the game's maps; kept on disk
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
  -- (every game: a WOOBOS row in the OPTIONS menu, straight to this mod's options)
  local optionsRow = loadSibling(mod, "src/options_row.lua")
  if optionsRow then
    local ok, err = pcall(optionsRow, mod, require)
    if not ok then mod.log:warn("the options' WOOBOS row couldn't be added: %s", tostring(err)) end
    -- (kept: its api, which the modern OPTIONS screen tells to open our page in itself)
    optionsRow = ok and type(err) == "table" and err or nil
  end
  -- (Red / Blue / Yellow, Gold / Silver / Crystal: the Game Boy games' own wiring, src/gb/main.lua -- the
  -- same kit, desktop and windows over their own models and host)
  if mod.generation == 1 or mod.generation == 2 then
    local gb = loadSibling(mod, "src/gb/main.lua")
    if gb then return gb(mod, loadSibling, optionsRow) end
    return
  end
  if mod.generation ~= nil and mod.generation ~= 3 then return end
  local makeKit, makeApps = loadSibling(mod, "src/ui_kit.lua"), loadSibling(mod, "src/apps.lua")
  local makeDesktop, makeShell = loadSibling(mod, "src/desktop.lua"), loadSibling(mod, "src/shell.lua")
  local makeInv, makeMb = loadSibling(mod, "src/inventory.lua"), loadSibling(mod, "src/mailbox.lua")
  local itemsWindow, mailWindow = loadSibling(mod, "src/apps/items.lua"), loadSibling(mod, "src/apps/mail.lua")
  local makeI18n, makeSettings = loadSibling(mod, "src/i18n.lua"), loadSibling(mod, "src/settings.lua")
  local makeWall, settingsWindow = loadSibling(mod, "src/wallpaper.lua"), loadSibling(mod, "src/apps/settings.lua")
  local makeBx, boxesWindow = loadSibling(mod, "src/boxes.lua"), loadSibling(mod, "src/apps/boxes.lua")
  local boxesView = loadSibling(mod, "src/apps/boxes_view.lua")
  local boxesSummary = loadSibling(mod, "src/apps/boxes_summary.lua")
  local summaryCtl = loadSibling(mod, "src/apps/summary_ctl.lua")
  local typeArt = loadSibling(mod, "src/apps/type_art.lua")
  local makeMenus, menusWindow = loadSibling(mod, "src/menus.lua"), loadSibling(mod, "src/apps/menus.lua")
  -- (an update's notice, once: src/notice.lua the list and when, src/apps/notice.lua the card)
  local makeNotice, noticeWindow = loadSibling(mod, "src/notice.lua"), loadSibling(mod, "src/apps/notice.lua")
  local makeParty, partyCtl = loadSibling(mod, "src/party.lua"), loadSibling(mod, "src/apps/party.lua")
  local partyView = loadSibling(mod, "src/apps/party_view.lua")
  local makeBagRules, bagCtl = loadSibling(mod, "src/bag_rules.lua"), loadSibling(mod, "src/apps/bag.lua")
  local bagView = loadSibling(mod, "src/apps/bag_view.lua")
  -- (the moments we stage: an evolution, a catch's page and its nickname -- src/scenes.lua the wraps)
  -- (kept in one table: this function is near Lua's 200 locals)
  local SC = { make = loadSibling(mod, "src/scenes.lua"), evolve = loadSibling(mod, "src/evolve.lua"),
               caught = loadSibling(mod, "src/caught.lua"), keyboard = loadSibling(mod, "src/keyboard.lua"),
               evolutionWindow = loadSibling(mod, "src/apps/evolution.lua"),
               caughtWindow = loadSibling(mod, "src/apps/caught.lua"), fx = loadSibling(mod, "src/apps/scene_fx.lua"),
               optScreen = loadSibling(mod, "src/options_screen.lua"), optWindow = loadSibling(mod, "src/apps/options.lua"),
               modsScreen = loadSibling(mod, "src/mods_screen.lua"),
               objectives = loadSibling(mod, "src/map3d/objectives.lua"),
               objectivesView = loadSibling(mod, "src/map3d/objectives_view.lua"),
               shopKind = loadSibling(mod, "src/map3d/shop_kind.lua"),
               trainerCard = loadSibling(mod, "src/trainercard.lua"),
               trainerCardWindow = loadSibling(mod, "src/apps/trainercard.lua") }
  local Arrange = loadSibling(mod, "src/arrange.lua")
  local makeMart, martWindow = loadSibling(mod, "src/mart.lua"), loadSibling(mod, "src/apps/mart.lua")
  -- the real shops: every shop counter opens the Mart full screen (src/realshop.lua; src/shop.lua the
  -- counter's model, src/shop_themes.lua its look)
  local makeRealShop, makeShop = loadSibling(mod, "src/realshop.lua"), loadSibling(mod, "src/shop.lua")
  local ShopThemes = loadSibling(mod, "src/shop_themes.lua")
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
  local makeStory = loadSibling(mod, "src/story.lua")
  local makeChallenges, challengesWindow = loadSibling(mod, "src/challenges.lua"), loadSibling(mod, "src/apps/challenges.lua")
  local makeNotes, makeFrost = loadSibling(mod, "src/notes.lua"), loadSibling(mod, "src/frost.lua")
  local Icons = loadSibling(mod, "src/icons.lua")
  local storeWindow = loadSibling(mod, "src/apps/appstore.lua")
  local makeGear, makeGearPanel = loadSibling(mod, "src/kanto_gear.lua"), loadSibling(mod, "src/gear_panel.lua")
  local makeMapModel, makeMapRender = loadSibling(mod, "src/map3d/model.lua"), loadSibling(mod, "src/map3d/render.lua")
  local mapScene, makeTownMap = loadSibling(mod, "src/map3d/scene.lua"), loadSibling(mod, "src/townmap.lua")
  local makeTowns, makeWorld = loadSibling(mod, "src/map3d/towns.lua"), loadSibling(mod, "src/map3d/world.lua")
  local makeMapCache = loadSibling(mod, "src/map3d/cache.lua")
  -- the map's GPS (a waypoint's walk, the field's arrow) and its markers
  local makeGpsGraph, makeGpsRoute = loadSibling(mod, "src/gps/graph.lua"), loadSibling(mod, "src/gps/route.lua")
  local makeGpsArrow, makeMarks = loadSibling(mod, "src/gps/arrow.lua"), loadSibling(mod, "src/marks.lua")
  local makeGpsReader = loadSibling(mod, "src/gps/read3.lua")
  local makePhone, phoneWindow = loadSibling(mod, "src/phone.lua"), loadSibling(mod, "src/apps/phone.lua")
  local makeCondition, conditionWindow = loadSibling(mod, "src/condition.lua"), loadSibling(mod, "src/apps/condition.lua")
  local makeRibbons, ribbonsWindow = loadSibling(mod, "src/ribbons.lua"), loadSibling(mod, "src/apps/ribbons.lua")
  local makeHall, hallWindow = loadSibling(mod, "src/hall.lua"), loadSibling(mod, "src/apps/hall.lua")
  local makeOak, oakWindow = loadSibling(mod, "src/oak.lua"), loadSibling(mod, "src/apps/oak.lua")
  local makeDex, dexWindow = loadSibling(mod, "src/dex.lua"), loadSibling(mod, "src/apps/pokedex.lua")
  local dexView = loadSibling(mod, "src/apps/pokedex_view.lua")
  local makeSpawnArea = loadSibling(mod, "src/spawn_area.lua")
  local makeDecorate, decorateWindow = loadSibling(mod, "src/decorate.lua"), loadSibling(mod, "src/apps/decorate.lua")
  local makePokenav = loadSibling(mod, "src/pokenav.lua")
  -- the Pokémon Center: the nurse's counter full screen (src/pokecenter.lua the takeover and the game's
  -- side effects; the window and its look; the nurse's sprite)
  local makePokecenter, pokecenterWindow = loadSibling(mod, "src/pokecenter.lua"), loadSibling(mod, "src/apps/pokecenter.lua")
  local pokecenterView, makeNurseArt = loadSibling(mod, "src/apps/pokecenter_view.lua"), loadSibling(mod, "src/nurse_art.lua")
  local makeSizeArt = loadSibling(mod, "src/size_art.lua")
  local stallView = loadSibling(mod, "src/apps/stall_view.lua")
  local makeLighting = loadSibling(mod, "src/lighting.lua")
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
  -- (each modern menu's own option, under Modern Menus)
  local MENU_OPTION = { bag = "menuBag", party = "menuParty", summary = "menuSummary", evolution = "menuEvolution",
                        catch = "menuCatch" }
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
      Kit.rescissor()
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
        return true
      end
      return false
    end
    -- (Ruby / Sapphire / Emerald: one sheet of 24 px icons, by item id; its quads kept here)
    if rseSheet == nil then
      local Chrome, SceneKit = engine("src.ui.game3.rse.bag_chrome"), engine("src.ui.game3.rse.scene_kit")
      local ok, m = pcall(Chrome and Chrome.manifest or error)
      local icons = ok and m and m.icons
      local img = icons and SceneKit and SceneKit.rgbaImage(icons.rgba, icons.w, icons.h)
      rseSheet = img and { img = img, count = icons.count, w = icons.w, h = icons.h } or false
    end
    if not rseSheet then return false end
    local n = tonumber(id) or 0
    if n < 0 or n >= rseSheet.count then
      local img = modIcon(id, true)
      if img then
        G.setColor(1, 1, 1, a or 1)
        G.draw(img, Kit.X(x), Kit.Y(y), 0, k, k)
        return true
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
    return true
  end
  -- a Pokémon's menu icon, `size` units square: frame 0 / 1, tinted r, g, b, a (white by default; the
  -- Pokédex's unseen are dark) (kept per species: the engine's lookup makes garbage every call; a species
  -- without one is remembered too)
  local iconFor = {}
  local function monIcon(species, x, y, size, frame, r, g, b, a)
    local e = iconFor[species]
    if e == nil then
      local P = engine("src.core.game3.pokemon")
      local ok, got = pcall(P and P.icon or error, species)
      Kit.rescissor()
      e = ok and type(got) == "table" and got.image and got.quads and got or false
      iconFor[species] = e
    end
    if not e then return end
    local q = e.quads[frame or 0] or e.quads[0]
    local G = Kit.graphics()
    G.setColor(r or 1, g or 1, b or 1, a or 1)
    G.draw(e.image, q, Kit.X(x), Kit.Y(y), 0, size * Kit.sc / e.w, size * Kit.sc / e.h)
  end
  -- a Pokémon's own menu icon (eggs, forms), `size` units square, frame 0 / 1, alpha a (kept per
  -- Pokémon: the engine's lookup builds names)
  local iconOf = setmetatable({}, { __mode = "k" })
  local function monIconOf(mon, x, y, size, frame, a)
    local e = iconOf[mon]
    if e == nil then
      local P = engine("src.core.game3.pokemon")
      local ok, got = pcall(P and P.monIcon or error, mon)
      Kit.rescissor()
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
        Kit.rescissor()
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
      Kit.rescissor()
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
  -- (a Pokémon changed -- it evolved, an egg hatched: its icon and picture made again)
  local function forgetMon(mon)
    if type(mon) ~= "table" then return end
    iconOf[mon], picOf[mon] = nil, nil
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
    prewarm = function(names, priority) if Sh then Sh.prewarm(names, priority) end end,
    inv = makeInv and makeInv(engine), mb = makeMb and makeMb(engine), bx = makeBx and makeBx(engine),
    mart = makeMart and makeMart(engine, { save = mod.save }),
    monIconOf = monIconOf, monPic = monPic, forgetMon = forgetMon, log = warn, boxWall = boxWall, boxWallCount = boxWallCount, itemName = itemName,
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
    setSetting = function(key, v)
      if Settings then Settings.set(key, v) end
      if key == "textSize" then Kit.setTextScale((tonumber(v) or 100) / 100) end
      if key == "theme" then Kit.setTheme(v) end
    end,
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
                       swarm = "news", story = "news", gps = "map" }
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
      save = mod.save, T = T, gameId = gameId,
      badges = function(s) return env.mart and env.mart.badges(s) or 0 end,
      -- (the limited prizes: the playthrough's seed, the local day, the game's own ids and flags)
      seed = function(s) return env.auction and env.auction.seedOf and env.auction.seedOf(s) or 1 end,
      day = function(t) return env.journal and env.journal.day(t) or math.floor(t / 86400) end,
      untilNext = function(t)
        local lt = env.journal and env.journal.localTime(t) or t
        return 86400 - lt % 86400
      end,
      const = function(kind, name)
        local Constants = engine("src.core.game3.constants")
        local C = Constants and Constants.of(gameId())
        return C and C:id(kind, name)
      end,
      flag = function(name)
        local R = engine("src.core.game3.rse.init")
        return R and R.flag(name, session()) or false
      end,
      setFlag = function(name, on)
        local R = engine("src.core.game3.rse.init")
        if R then R.setFlag(name, on, session()) end
      end,
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
      -- (a legendary or mythical Pokemon, by R-Bay's tiers: its battle is followed for the News)
      legend = function(sp)
        local tier = env.auction and env.auction.tierOf(sp)
        return tier == "legendary" or tier == "mythical"
      end,
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
  -- Emerald's Mart employee). His graphics id is kept per game; the sprite is asked of OwSprites.getDraw
  -- each time, as the field does (a table lookup once loaded), so a mod's sprite set (Facets) is his too,
  -- and a set chosen later shows at once; until it loads, asked once a second at most
  local clerkId, clerkFor, clerkTry, clerkMiss = nil, nil, -10, nil
  env.clerk = function()
    local g = gameId()
    local Ow = engine("src.core.game3.ow_sprites")
    if not (Ow and Ow.getDraw) then return nil end
    if clerkFor ~= g then
      local t = env.now()
      if t - clerkTry < 1 then return nil end
      clerkTry = t
      local Constants = engine("src.core.game3.constants")
      if not Constants then return nil end
      local okC, C = pcall(Constants.of, g)
      if not (okC and C) then return nil end
      local okI, id = pcall(C.id, C, "event_objects", "OBJ_EVENT_GFX_CLERK")
      if not (okI and id) then okI, id = pcall(C.id, C, "event_objects", "OBJ_EVENT_GFX_MART_EMPLOYEE") end
      if not (okI and id) then return nil end
      clerkId, clerkFor = id, g
    end
    local t = env.now()
    if clerkMiss and t - clerkMiss < 1 then return nil end
    local okS, spr = pcall(Ow.getDraw, clerkId)
    if okS and type(spr) == "table" and spr.image and spr.quads then
      clerkMiss = nil
      return spr
    end
    clerkMiss = t
    return nil
  end
  -- the News's anchor: a sheet per mood (assets/newscaster.png her everyday read, newscaster-cheer.png,
  -- newscaster-shock.png), square frames side by side (0 at rest), each loaded the first time it's
  -- asked for, for whole-pixel scaling, its frames cut with it; `foot` = the empty rows under every
  -- frame (the bust is drawn that much lower, to meet the shot's edge). env.anchor(mood): nil for a
  -- mood with no sheet (the window falls back on the everyday one)
  local ANCHOR = { talk = "assets/newscaster.png", cheer = "assets/newscaster-cheer.png",
                   shock = "assets/newscaster-shock.png" }
  local anchorArt = {}
  env.anchor = function(mood)
    local key = mood or "talk"
    local path = ANCHOR[key]
    if not path then return nil end
    if anchorArt[key] == nil then
      anchorArt[key] = false
      local LG, LI = love and love.graphics, love and love.image
      local ok, img = pcall(mod.assets.image, mod.assets, path)
      if ok and img and LG and LG.newQuad then
        pcall(img.setFilter, img, "nearest", "nearest")
        local iw, ih = img:getDimensions()
        local n, quads = math.max(1, math.floor(iw / ih)), {}
        for i = 0, n - 1 do quads[i] = LG.newQuad(i * ih, 0, ih, ih, iw, ih) end
        local foot = 0
        local okP, full = pcall(mod.assets.path, mod.assets, path)
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
        anchorArt[key] = { image = img, quads = quads, n = n, size = ih, foot = foot }
      end
    end
    return anchorArt[key] or nil
  end
  env.nurse = makeNurseArt and makeNurseArt(mod) or nil
  -- the G-Max Factor's mark (assets/gmax.png, from Lucidious89's Dynamax plugin), loaded the first time it's
  -- drawn: centred on cx, its foot at `foot`, `h` units tall -> its width in units (0 with no picture)
  local gmaxArt = nil
  env.gmaxMark = function(cx, foot, h)
    if gmaxArt == nil then
      gmaxArt = false
      local ok, img = pcall(mod.assets.image, mod.assets, "assets/gmax.png")
      if ok and img then
        pcall(img.setFilter, img, "linear", "nearest")
        gmaxArt = img
      end
    end
    if not gmaxArt then return 0 end
    local iw, ih = gmaxArt:getDimensions()
    local k = h * Kit.sc / ih
    local G = Kit.graphics()
    G.setColor(1, 1, 1, Kit.getFade())
    G.draw(gmaxArt, math.floor(Kit.X(cx) - iw * k / 2 + 0.5), math.floor(Kit.Y(foot) - ih * k + 0.5), 0, k, k)
    return iw * h / ih
  end
  -- (the Pokédex's Size tab: the trainer it measures against, and a picture's drawn pixels)
  env.sizeArt = makeSizeArt and makeSizeArt(mod, Kit) or nil
  -- (the Size tab's heights: WoobleDex's measured ones (exports.artHeights, its data/art_heights.lua: each
  -- WoobleSprite picture's height standing, in metres), by species slot (the engine's), else by National Dex number; nil
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
            artRows.byKey[tonumber(r.slot) or id] = r
            local d, sl = tonumber(r.dex), tonumber(r.slot) or math.huge
            local was = d and artRows.byDex[d]
            if d and (not was or (tonumber(was.slot) or math.huge) > sl) then artRows.byDex[d] = r end
          end
        end
      end
    end
    if not artRows then return nil end
    return artRows.byKey[tonumber(sp) or sp] or (nat and artRows.byDex[tonumber(nat)]) or nil
  end

  env.summaryCtl = summaryCtl or nil
  env.typeArt = typeArt and env.K and typeArt(env.K) or nil
  -- (the staged scenes' shared pieces, and the nickname keyboard)
  env.sceneFx = SC.fx and env.K and SC.fx(env.K, T) or nil
  env.keyboard = SC.keyboard and env.K and SC.keyboard(env.K, T) or nil
  env.stallView = stallView or nil
  env.lighting = makeLighting and makeLighting({ log = function(fmt, ...) mod.log:warn(fmt, ...) end }) or nil
  -- (a species by the game's own name for it, "KYOGRE")
  local function speciesNamed(id)
    local Constants = engine("src.core.game3.constants")
    local ok, C = pcall(Constants and Constants.of or error, gameId())
    local byName = ok and C and C.species and C.species.byName
    return byName and tonumber(byName["SPECIES_" .. tostring(id)]) or nil
  end
  -- Ruby / Sapphire / Emerald's story for the News, from the game's own flags and variables
  if makeStory then
    env.story = makeStory(engine, {
      save = mod.save, now = os.time, gameId = gameId, species = speciesNamed, notify = notify,
      flag = function(name)
        local R = engine("src.core.game3.rse.init")
        return R and R.flag(name, session()) or false
      end,
      var = function(name)
        local R = engine("src.core.game3.rse.init")
        return R and R.var(name, session()) or 0
      end,
      head = function(s, rec) return env.news and env.news.storyHead(s, rec) or tostring(rec.id) end,
    })
  end
  if makeNews then
    env.news = makeNews(engine, {
      save = mod.save, now = os.time, T = T, notify = notify, story = env.story, species = speciesNamed,
      gameId = gameId,
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
        -- (Nidoran's sign kept: the kit draws it)
        return titled(tostring(n))
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
    -- (Ruby / Sapphire / Emerald: Hoenn built to scale from those maps)
    local World = makeWorld and makeWorld(engine, { maps = mapDefs }) or nil
    -- (a region built to scale kept on disk: the next start reads it back instead of building it)
    local Version = engine("src.core.Version")
    local MapCache = makeMapCache and mod.cache and makeMapCache({
      cache = mod.cache, loadData = T and T.loadData, version = version, engine = Version and Version.engine,
      data = love and love.data, log = warn }) or nil
    local Model = makeMapModel(engine, { pixels = pixels, gameId = gameId, maps = mapDefs, world = World, log = warn,
                                         mapCache = MapCache })
    -- (the places' objectives, the mod option Map Objectives: the story's beats, gyms, key items, people, shops)
    if SC.objectives and SC.objectivesView then
      local Ob = SC.objectives(engine, {
        maps = mapDefs, gameId = gameId, T = T, log = warn,
        shopKind = SC.shopKind and SC.shopKind() or nil,
        family = function()
          local g = gameId()
          return (g == "firered" or g == "leafgreen") and "frlg" or "rse"
        end,
        flag = function(name, s)
          local R = engine("src.core.game3.rse.init")
          local ok, on = pcall(R and R.flag or error, name, s or session())
          return ok and on == true
        end,
        hasItem = function(s, id)
          local Bag = engine("src.core.game3.bag")
          local bag = (s or session() or {}).bag
          local ok, has = pcall(Bag and Bag.has or error, bag, id, 1)
          return ok and has == true
        end,
        reached = function(s)
          local set = {}
          local ok, list = pcall(env.story and env.story.reached or error, s or session())
          for _, r in ipairs(ok and type(list) == "table" and list or {}) do set[r.id] = true end
          return set
        end,
      })
      env.objectives = {
        at = Ob.at, reset = Ob.reset, view = SC.objectivesView(Kit, T),
        mode = function()
          local m = option("mapObjectives", "on")
          return (m == "spoilers" or m == "off") and m or "on"
        end,
      }
    end
    local Towns = makeTowns and makeTowns() or nil
    env.map3d = {
      model = Model,
      towns = Towns,
      render = makeMapRender({ log = warn, towns = Towns, mapCache = MapCache }),
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
  -- the map's markers (every game) and its GPS: the walk graph built once in the background (kept on disk),
  -- the waypoint's route, the field's arrow (Settings: fieldGps, off unless turned on)
  if makeMarks then env.marks = makeMarks({ save = mod.save }) end
  local Gps
  if env.map3d and makeGpsGraph and makeGpsRoute and makeGpsReader then
    local Version = engine("src.core.Version")
    local function mapDefs()
      local g = mod.game
      return g and g.data and g.data.maps or nil
    end
    local graph = makeGpsGraph(engine, {
      reader = makeGpsReader, maps = mapDefs, game = function() return mod.game end, cache = mod.cache, gameId = gameId, version = version,
      engine = Version and Version.engine, log = warn })
    local Player = engine("src.core.game3.player")
    local route = makeGpsRoute(engine, {
      graph = graph, save = mod.save, session = session, log = warn,
      surfing = function() return Player ~= nil and Player.surfing == true end,
      -- (a field move the player can use: its badge, and a Pokémon in the party that knows it; an item's way --
      -- the desert's Go-Goggles -- while it's in the Bag)
      can = function(s, key, h)
        if type(h) == "table" and h.item then
          local Bag = engine("src.core.game3.bag")
          local okH, has = pcall(Bag.has, s and s.bag, h.item, 1)
          return okH and has == true
        end
        local FM, Space = engine("src.core.game3.field_moves"), engine("src.core.game3.scripting.space")
        if not (FM and s) then return false end
        local okB, badge = pcall(FM.hasBadge, { store = Space and Space.store, session = s }, key)
        if not (okB and badge) then return false end
        local okU, mon = pcall(FM.partyMoveUser, s.party, key)
        return okU and mon ~= nil and mon ~= false
      end,
      mapDef = function(id) local all = mapDefs(); return all and all[id] end,
      notify = function(kind, data) if Nt then Nt.push(kind, data) end end,
    })
    local arrow = makeGpsArrow and makeGpsArrow({
      K = Kit, route = route,
      on = function() return Settings ~= nil and Settings.get("fieldGps", false) == true end,
      -- (the player, the field's camera, and where the engine put its world canvas this frame)
      player = function()
        local Map = engine("src.core.game3.map")
        if not (Player and Map) then return nil end
        local FV, R = engine("src.core.game3.field_view"), engine("src.render.Renderer")
        local camX, camY = FV and tonumber(FV._lastCamX), FV and tonumber(FV._lastCamY)
        local ox, oy, sx, sy
        if R and camX then ox, oy, sx, sy = tonumber(R.wipeWox), tonumber(R.wipeWoy), tonumber(R.wipeSx), tonumber(R.wipeSy) end
        return tonumber(Player.px), tonumber(Player.py), Map.current, camX, camY, ox, oy, sx, sy
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
  -- the PokéNav's apps: the Phone (its contacts, the game's calls, recents and favourites in the
  -- save) and Condition (the contest conditions, the Pokéblock case)
  if makePhone then
    env.phone = makePhone(engine, { save = mod.save, now = os.time, notify = notify,
                                    image = function(path) return mod.assets:image(path) end })
  end
  if makeCondition and env.bx then env.condition = makeCondition(engine, { bx = env.bx }) end
  if makeHall then env.hall = makeHall(engine) end
  if makeOak then env.oak = makeOak(engine) end
  -- the Pokédex: the model (WoobleDex's Pokémon, forms and Gigantamax when it's on), the picture
  -- (Emerald's own front animation, else a breathing still) and the cry
  local function wooble()
    local nd = mod.find("national_dex_gen3")
    return nd and nd.exports or nil
  end
  -- (WoobleDex's Register Owned: its own step, run before our Pokédex opens as before its own)
  local function registerOwned(s)
    local wd = wooble()
    if wd and wd.registerOwned then pcall(wd.registerOwned, s) end
  end
  -- (the mod's option: off, the game's own Pokédex everywhere and no app; read when asked, never per frame)
  -- (the Pokédex: one of Modern Menus' categories, so off with it)
  env.dexOption = function() return option("modernMenus", true) ~= false and option("pokedex", true) ~= false end
  -- (the WoobPad option: off, no START row, and the game's own PokéNav)
  env.padOption = function() return option("woobpad", true) ~= false end
  -- (WoobleSpawns, modern_spawns: the wild Pokémon it places, for the Where tab; its species by id, a
  -- slot's id from the content registry, read once; a map's group and number from its encounter record)
  local function registry(name)
    local reg = mod.content and mod.content[name]
    return type(reg) == "table" and reg or nil
  end
  local idOfSlot
  local function speciesId(sp)
    if not idOfSlot then
      idOfSlot = {}
      local reg = registry("pokemon")
      local okE, it = pcall(function() return reg:each() end)
      local ids = {}
      if okE and type(it) == "function" then
        for id in it do ids[#ids + 1] = id end
      elseif okE and type(it) == "table" then
        ids = it
      end
      for _, id in ipairs(ids) do
        local okG, rec = pcall(reg.get, reg, id)
        local index = okG and type(rec) == "table" and tonumber(rec.index)
        if index and idOfSlot[index] == nil then idOfSlot[index] = id end
      end
    end
    return idOfSlot[tonumber(sp)]
  end
  local function mapGroupNum(mapId)
    local reg = registry("encounters")
    local ok, rec = pcall(reg and reg.get or error, reg, mapId)
    if ok and type(rec) == "table" and rec.mapGroup then return tonumber(rec.mapGroup), tonumber(rec.mapNum) end
    reg = registry("maps")
    ok, rec = pcall(reg and reg.get or error, reg, mapId)
    if ok and type(rec) == "table" and rec.mapGroup then return tonumber(rec.mapGroup), tonumber(rec.mapNum) end
    return nil
  end
  local spawnArea = makeSpawnArea and makeSpawnArea({
    gen = 3,
    spawns = function()
      local m = mod.find("modern_spawns")
      return m and m.exports or nil
    end,
  })
  if makeDex then
    env.dex = makeDex(engine, { T = T, typeName = env.typeName, placeName = placeName, itemName = env.itemName,
                                wooble = wooble, gameId = gameId, spawnArea = spawnArea, speciesId = speciesId,
                                mapGroupNum = mapGroupNum })
    local P = engine("src.core.game3.pokemon")
    if P and P.onReload then pcall(P.onReload, function() env.dex.reset() end, "woob_os_dex") end
    env.cry = function(sp)
      local Audio = engine("src.core.game3.audio")
      if Audio and Audio.playCry then pcall(Audio.playCry, sp) end
    end
    local anim = { sp = nil, sprite = nil, acc = 0, last = nil, pack = false, packAt = -1, packPic = nil, shiny = false }
    -- (the pictures kept per species, a shiny's apart: the Boxes' summary shows a shiny in its colours)
    local stills, frames, stillsS, framesS, measured = {}, {}, {}, {}, {}
    -- (WoobleSpritePack, g9-battle-sprites-gen3: its art comes through the engine's frontPic, one frame
    -- of its animated sheet per call by a shared clock (8 a second); a species it draws is asked again
    -- while it's shown, 16 times a second, instead of kept)
    local PACK_EVERY = 1 / 16
    local function spritePack()
      local m = mod.find("g9-battle-sprites-gen3")
      local ex = m and m.exports
      local okA, on = pcall(ex and ex.isActive or error)
      return okA and on == true and ex or nil
    end
    local function still(sp, shiny)
      local kept = shiny and stillsS or stills
      local e = kept[sp]
      if e == nil then
        local Pk = engine("src.core.game3.pokemon")
        local ok, got = pcall(Pk and Pk.frontPic or error, sp, 0, shiny == true, 0, "dex")
        Kit.rescissor()
        e = ok and type(got) == "table" and got.image and got or false
        kept[sp] = e
      end
      return e or nil
    end
    local function framePic(sp, frame, shiny)
      local kept = shiny and framesS or frames
      local f = kept[sp]
      if not f then
        f = {}
        kept[sp] = f
      end
      local e = f[frame]
      if e == nil then
        local MA = engine("src.core.game3.mon_anim")
        local ok, got = pcall(MA and MA.framePic or error, sp, frame, shiny == true)
        Kit.rescissor()
        e = ok and type(got) == "table" and got.image and got or false
        f[frame] = e
      end
      return e or nil
    end
    env.dexSprite = {
      -- (chosen: the game's animation from the start, where the game has one)
      start = function(sp, shiny)
        anim.sp, anim.sprite, anim.acc, anim.last, anim.shiny = sp, nil, 0, nil, shiny == true
        anim.pack, anim.packAt, anim.packPic = false, -1, nil
        local ex = spritePack()
        if ex and ex.hasSprite then
          local Pk = engine("src.core.game3.pokemon")
          local okN, nat = pcall(Pk and Pk.national or error, sp)
          local okH, has = pcall(ex.hasSprite, okN and nat or sp, "front")
          anim.pack = okH and has == true
        end
        local MA = engine("src.core.game3.mon_anim")
        local okE, on = pcall(MA and MA.enabled or error)
        if not (okE and on) then return end
        local ok, sprite = pcall(MA.newSprite, sp, { affineMode = "off", hFlip = false })
        if not (ok and type(sprite) == "table") then return end
        sprite.data[0] = sp
        sprite.callback = function(spr)
          spr.data[1] = 1
          MA.summary(spr, sp, false)
        end
        anim.sprite = sprite
      end,
      stop = function() anim.sp, anim.sprite, anim.pack, anim.packPic = nil, nil, false, nil end,
      -- (where the still picture's drawn pixels sit in draw()'s size x size box round cx, cy, as fractions
      -- of size: { fx0, fy0, fx1, fy1 }; read once per species (the Size tab's chart); nil without a picture
      -- or a canvas to read it through)
      measure = function(sp)
        local m = measured[sp]
        if m == nil then
          m = false
          local base = still(sp, false)
          local Sz = env.sizeArt
          if base and Sz then
            local u0, v0, u1, v1 = Sz.bounds(base.image)
            local bw = base.w or 64
            if u0 then m = { fx0 = (u0 - 32) / bw, fy0 = (v0 - 32) / bw, fx1 = (u1 - 32) / bw, fy1 = (v1 - 32) / bw } end
          end
          measured[sp] = m
        end
        return m or nil
      end,
      -- (tests: whether the chosen one is the pack's, and the picture last drawn from it)
      pack = function() return anim.pack, anim.packPic end,
      -- (centred on cx, cy, size units: the animation stepped at the game's 60 a second, its frames'
      -- pictures kept here and drawn without the engine's per-draw tables; done, or none, the still
      -- picture breathing from its feet, with a hop just after it's chosen; `scale` and `alpha` the
      -- Pokédex's pop as it's chosen; `shiny` its shiny colours, as started)
      draw = function(sp, cx, cy, size, clock, chosenAt, scale, alpha, shiny)
        local base
        shiny = shiny == true
        if anim.pack and anim.sp == sp and anim.shiny == shiny then
          if not anim.packPic or clock - anim.packAt >= PACK_EVERY or clock < anim.packAt then
            local Pk = engine("src.core.game3.pokemon")
            local ok, got = pcall(Pk and Pk.frontPic or error, sp, 0, shiny, 0, "dex")
            -- (the pack makes a frame's canvas the first time it's shown: the scissor set again after it)
            Kit.rescissor()
            if ok and type(got) == "table" and got.image then anim.packPic = got end
            anim.packAt = clock
          end
          base = anim.packPic or still(sp, shiny)
        else
          base = still(sp, shiny)
        end
        if not base then return end
        local G = Kit.graphics()
        local k0 = size * Kit.sc / (base.w or 64)
        local k = k0 * (scale or 1)
        alpha = alpha or 1
        local px, py = Kit.X(cx), Kit.Y(cy)
        local sprite = anim.sp == sp and anim.shiny == shiny and anim.sprite or nil
        if sprite then
          local MA = engine("src.core.game3.mon_anim")
          local dt = anim.last and math.max(0, math.min(0.1, clock - anim.last)) or 0
          anim.last = clock
          anim.acc = anim.acc + dt
          local n = 0
          while anim.acc >= 1 / 60 and n < 4 do
            anim.acc, n = anim.acc - 1 / 60, n + 1
            if not pcall(MA.step, sprite, true) then
              anim.sprite = nil
              break
            end
          end
          if anim.sprite and MA.done(sprite) then anim.sprite = nil end
          if anim.sprite then
            if sprite.invisible then return end
            local pic = (tonumber(sprite.frame) or 0) ~= 0 and framePic(sp, sprite.frame, shiny) or base
            local sx, sy, rot = 1, 1, 0
            local m = sprite.matrix
            if sprite.affineMode ~= "off" and m then
              local xs = (m.xScale or 0) ~= 0 and m.xScale or 256
              local ys = (m.yScale or 0) ~= 0 and m.yScale or 256
              sx, sy, rot = 256 / xs, 256 / ys, -(math.floor((m.rotation or 0) / 256) * 2 * math.pi / 256)
            end
            G.setColor(1, 1, 1, alpha)
            G.draw(pic.image, px + (sprite.x2 or 0) * k, py + (sprite.y2 or 0) * k, rot, sx * k, sy * k, 32, 32)
            return
          end
        end
        local t = clock - (chosenAt or -10)
        local hop = (t >= 0 and t < 0.45) and math.sin(t / 0.45 * math.pi) * 2.5 * Kit.sc or 0
        local b = 1 + 0.022 * math.sin(clock * 2.3)
        G.setColor(1, 1, 1, alpha)
        G.draw(base.image, px, py + 32 * k0 - hop, 0, k * (2 - b), k * b, 32, 64)
      end,
    }
  end
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
    -- (the summary's Dynamax row: while Galar Rising, the raids that hand the levels out, is on)
    env.bx.galar = function() return mod.find("max_raids") ~= nil end
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
      and function(ctx, e) return boxesWindow(ctx, e, boxesView, boxesSummary) end or nil,
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
    pokedex = env.dex and dexWindow and dexView and function(ctx, e)
      registerOwned(ctx.session or session())
      return dexWindow(ctx, e, dexView)
    end or nil,
    pokedexAvailable = env.dex and function(ctx)
      return env.dexOption() and env.dex.available(ctx.session or session())
    end or nil,
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
  -- the scene host: an evolution, a catch's page and its nickname (src/scenes.lua), full screen over the rest
  SC.host = makeTownMap and makeTownMap({
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
  env.appIcon = function(app, x, y, size, a) Desktop.appIcon(app, x, y, size, nil, a) end
  -- (a desktop glyph in window pixels, white: the Phone's handset)
  env.glyph = Desktop.glyph
  -- (money in a window, with the game's sign: the Mart)
  env.amount = function(n, x, y, size, c, measure) return Desktop.amount(n, x, y, size, c, measure) end
  -- (one of the desktop's pictures, white, centred on cx, cy in units; tile: the colour its holes show)
  env.icon = function(name, cx, cy, s, a, tile)
    if Icons then pcall(Icons.draw, Kit.graphics(), name, Kit.X(cx), Kit.Y(cy), s * Kit.sc, a, tile) end
  end
  -- the text size (Settings > Display, the mod option), on the kit: at load, once a second, and at once
  -- when the Settings app changes it
  local function applyTextSize()
    local pct = Settings and Settings.textSize(option("textSize", 100)) or tonumber(option("textSize", 100)) or 100
    Kit.setTextScale(pct / 100)
    -- (the theme, the same way: Light, Dark or OLED)
    Kit.setTheme(Settings and Settings.theme(option("theme", "light")) or option("theme", "light"))
    -- (the Overworld GPS switch: the mod option or Settings > Map, whichever changed last; the arrow reads
    -- the setting each frame)
    if Settings then Settings.fieldGps(option("fieldGps", false)) end
  end
  applyTextSize()
  -- once a second, wherever the player is: R-Bay's auctions and the GTS settle (their
  -- notifications come from it); a win's Poké Ball onto the desktop's pad
  local function tick()
    applyTextSize()
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
  -- each frame: the region the player is in (Hoenn; Kanto or one of the Sevii Islands' pictures) built
  -- to scale in the background, a few milliseconds a frame once they've been out in the field a few
  -- seconds (so the map opens at once; opened sooner, it finishes the build itself). Which region,
  -- looked at once a second; each built once
  local mapPrep = { at = nil, game = nil, want = nil, nextLook = 0, built = {} }
  local function frame(game)
    if env.notice then env.notice.step(game) end
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
      if Settings and Settings.get("map3d", true) == false then return end
      local okH, rid = pcall(m3.model.regionHere, session())
      if not (okH and rid) or mapPrep.built[rid] then return end
      mapPrep.want, mapPrep.at = rid, now + 4
    end
    if now < mapPrep.at then return end
    local rid = mapPrep.want
    m3.model.prepare(rid)
    if m3.model.step(0.004) then return end
    local region = m3.model.region(rid)
    if region and region.world and m3.render.prepare(love.graphics, region, 0.004) then return end
    mapPrep.built[rid], mapPrep.want = true, nil
  end
  -- the PokéNav's Match Call / Trainer's Eyes and Condition: our apps instead (Settings: pokenavApps)
  local Pokenav = makePokenav and makePokenav(engine, {
    open = function(appId, s, onClose, state) return Sh and Sh.openFull(appId, s, onClose, state) or false end,
    enabled = function()
      return option("desktop", true) ~= false and env.padOption()
        and (not Settings or Settings.get("pokenavApps", true) ~= false)
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
                        notify = Nt, tick = tick, frame = frame, session = session,
                        townmap = TownMap, scenes = SC.host, map3d = env.map3d, pokenav = Pokenav,
                        onCall = env.phone and onCall or nil,
                        map3dOn = function() return not Settings or Settings.get("map3d", true) ~= false end,
                        dexOn = env.dex and function()
                          return env.dexOption() and (not Settings or Settings.get("pokedexApp", true) ~= false)
                        end or nil,
                        registerOwned = registerOwned,
                        padOn = function() return env.padOption() end,
                        fieldDraw = Gps and Gps.arrow and function(G, vp, free, t) Gps.arrow.draw(G, vp, free, t) end or nil,
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
  local RealShop = makeRealShop and makeShop and ShopThemes and env.mart and makeRealShop(engine, {
    Sh = Sh, base = env.mart, T = T, makeShop = makeShop, themes = ShopThemes, clerk = env.clerk, place = placeName,
    on = function() return option("realShops", true) ~= false end,
    log = function(fmt, ...) mod.log:warn(fmt, ...) end,
  }) or nil
  env.realShop = RealShop
  -- (the clerk's greeting and goodbye skipped: the counter opens straight away)
  if RealShop then
    mod.hooks:wrap("script.command", function(nxt, ctx, op, row, ...)
      return RealShop.command(nxt, ctx, op, row, ...)
    end)
  end
  -- the Pokémon Center: the nurse's counter full screen (src/pokecenter.lua; the window is an app that's
  -- never on the home screen: Sh.openFull opens it by id)
  if makePokecenter and pokecenterWindow and pokecenterView then
    Apps.register({ id = "pokecenter", labelKey = "nurse.title", label = "Pokémon Center", glyph = "pokeball",
                    color = { 236, 80, 110 }, order = 99, pad = false, available = function() return false end,
                    window = function(ctx, e) return pokecenterWindow(ctx, e, pokecenterView) end })
    env.pokecenter = makePokecenter(engine, {
      Sh = Sh, on = function() return option("pokecenter", true) ~= false end,
      log = function(fmt, ...) mod.log:warn(fmt, ...) end,
    })
    mod.hooks:wrap("script.command", function(nxt, ctx, op, row, ...)
      return env.pokecenter.command(nxt, ctx, op, row, ...)
    end)
  end
  -- the modern menus (src/menus.lua): the game's Summary, party menu and Bag, in our glass (the option
  -- "modernMenus"; src/party.lua the party's rules, src/apps/party.lua + party_view.lua its screen;
  -- src/bag_rules.lua the Bag's, src/apps/bag.lua + bag_view.lua)
  local Menus = nil
  if makeMenus and menusWindow and boxesSummary and summaryCtl then
    if makeParty and partyCtl then
      env.party = makeParty(engine, { T = T, log = function(fmt, ...) mod.log:warn(fmt, ...) end,
        -- (the G-Max Factor, as the summary shows it: WoobleDex's, while Galar Rising is on)
        gmax = function(mon)
          local Dx = env.bx and env.bx.galar and env.bx.galar() and env.bx.dynamax and env.bx.dynamax()
          return type(Dx) == "table" and type(Dx.canGigantamax) == "function" and Dx.canGigantamax(mon) == true
        end })
      env.partyCtl = partyCtl
      if makeBagRules and bagCtl and env.inv then
        env.bagRules = makeBagRules(engine, { T = T, inv = env.inv, moveRecord = env.bx and env.bx.moveRecord,
                                              log = function(fmt, ...) mod.log:warn(fmt, ...) end })
        env.bagCtl = bagCtl
      end
    end
    Apps.register({ id = "menus", labelKey = "menus.title", label = "Menus", glyph = "pokeball",
                    color = { 10, 132, 255 }, order = 99, pad = false, available = function() return false end,
                    window = function(ctx, e) return menusWindow(ctx, e, boxesSummary, partyView, bagView) end })
    Menus = makeMenus(engine, {
      -- (Modern Menus, then the category's own -- Bag / Pokémon Menu / Summary -- and Battle Menus for one in a
      -- battle: each shown in the options only while Modern Menus is on)
      Sh = Sh, on = function(kind, battle)
        if option("modernMenus", true) == false then return false end
        local key = MENU_OPTION[kind]
        if key and option(key, true) == false then return false end
        if battle and option("menuBattle", true) == false then return false end
        return true
      end,
      feed = function(input) Sh.feedHost(input) end,
      -- (a battle's menus on the Kanto Gear's screen: the option, with Kanto Gear there to stand down)
      gear = function() return option("gearMenus", true) == true and Gear ~= nil and Gear.bound() end,
      partyUi = function(s) return env.party and env.party.partyUi(s) or nil end,
      log = function(fmt, ...) mod.log:warn(fmt, ...) end,
    })
    env.menus = Menus
  end
  -- an update's notice (src/notice.lua): the first time free in the field, the newest one not yet seen
  if makeNotice and noticeWindow then
    Apps.register({ id = "notice", labelKey = "notice.title", label = "Notice", glyph = "pokeball",
                    color = { 10, 132, 255 }, order = 99, pad = false, available = function() return false end,
                    window = function(ctx, e) return noticeWindow(ctx, e) end })
    env.notice = makeNotice(engine, { Sh = Sh, Settings = Settings, modId = mod.id or "woob_os",
                                      log = function(fmt, ...) mod.log:warn(fmt, ...) end })
  end
  -- the moments we stage (src/scenes.lua): an evolution, a catch's page and a Pokémon's nickname, full screen
  -- on the scene host; each a switch under Modern Menus
  if SC.make and SC.evolve and SC.caught and SC.evolutionWindow and SC.caughtWindow and env.sceneFx then
    Apps.register({ id = "evolution", labelKey = "evo.title", label = "Evolution", glyph = "pokeball",
                    color = { 120, 90, 220 }, order = 99, pad = false, available = function() return false end,
                    window = function(ctx, e) return SC.evolutionWindow(ctx, e) end })
    Apps.register({ id = "caught", labelKey = "caught.title", label = "Caught", glyph = "pokeball",
                    color = { 236, 80, 110 }, order = 99, pad = false, available = function() return false end,
                    window = function(ctx, e) return SC.caughtWindow(ctx, e) end })
    local function dexInfo(sp)
      if not (env.dex and env.dex.open and env.dex.page) then return nil end
      local book = env.dex.open(session())
      for _, mode in ipairs(book and book.modes or {}) do
        for _, en in ipairs(book.lists[mode] or {}) do
          if en.sp == sp then
            local pg = env.dex.page(en)
            if type(pg) == "table" then
              return { numText = en.numText, category = pg.category, heightText = pg.heightText,
                       weightText = pg.weightText, description = pg.description }
            end
            return { numText = en.numText }
          end
        end
      end
      return nil
    end
    local warn = function(fmt, ...) mod.log:warn(fmt, ...) end
    local Scenes = SC.make(engine, {
      Sh = Sh, log = warn,
      on = function(kind)
        if option("modernMenus", true) == false then return false end
        return option(MENU_OPTION[kind] or "", true) ~= false
      end,
      evolve = SC.evolve(engine, { kit = Kit, log = warn }),
      caught = SC.caught(engine, { kit = Kit, T = T, log = warn, dexInfo = dexInfo }),
      family = function()
        local g = Sh.gameId and Sh.gameId() or ""
        return (g == "firered" or g == "leafgreen") and "frlg" or "rse"
      end,
    })
    env.scenes, SC.scenes = Scenes, Scenes
    -- (a nickname given on the catch's page: the battle's question answered, not asked again)
    mod.hooks:wrap("catch.nickname", function(nxt, mon, cctx)
      local ok, ans = pcall(Scenes.nickFor, mon)
      if ok and ans ~= nil then return ans end
      return nxt(mon, cctx)
    end)
  end
  -- the OPTIONS screen, modern (src/options_screen.lua): the game's OPTIONS and each mod's own options page
  if SC.optScreen and SC.optWindow then
    Apps.register({ id = "options", labelKey = "opt.title", label = "Options", glyph = "pokeball",
                    color = { 142, 142, 147 }, order = 99, pad = false, available = function() return false end,
                    window = function(ctx, e) return SC.optWindow(ctx, e) end })
    SC.options = SC.optScreen(engine, { Sh = Sh, log = function(fmt, ...) mod.log:warn(fmt, ...) end,
      family = function()
        local g = Sh.gameId and Sh.gameId() or ""
        if g == "ruby" or g == "sapphire" then return "rs" end
        return (g == "firered" or g == "leafgreen") and "frlg" or "rse"
      end,
      on = function()
        return option("modernMenus", true) ~= false and option("menuOptions", true) ~= false
      end })
    env.optionsScreen = SC.options
    if type(optionsRow) == "table" then
      optionsRow.inWindow = function(id)
        local f = SC.options.inWindow
        return SC.options.isOpen() and type(f) == "function" and f(id) == true
      end
    end
    -- MODS, modern (src/mods_screen.lua), in the same window
    if SC.modsScreen then
      env.modsScreen = SC.modsScreen(engine, { Sh = Sh, Os = SC.options, T = T, gen = 3,
        log = function(fmt, ...) mod.log:warn(fmt, ...) end,
        on = function() return option("modernMenus", true) ~= false and option("menuMods", true) ~= false end })
    end
  end
  -- the trainer card, modern (src/trainercard.lua; the window an app that's never on the grid): Modern Menus'
  -- "Trainer Card" switch
  if SC.trainerCard and SC.trainerCardWindow and env.sceneFx then
    Apps.register({ id = "trainercard", labelKey = "tc.title", label = "Trainer Card", glyph = "pokeball",
                    color = { 255, 184, 40 }, order = 99, pad = false, available = function() return false end,
                    window = function(ctx, e) return SC.trainerCardWindow(ctx, e) end })
    SC.tc = SC.trainerCard(engine, {
      Sh = Sh, T = T, kit = Kit, dex = env.dex, gameId = function() return Sh.gameId and Sh.gameId() or "firered" end,
      on = function() return option("modernMenus", true) ~= false and option("menuTrainerCard", true) ~= false end,
      log = function(fmt, ...) mod.log:warn(fmt, ...) end,
    })
    env.trainerCard = SC.tc
  end
  mod.events:on("game.ready", function()
    if SC.tc then
      local okT, errT = pcall(SC.tc.wrap)
      if not okT then mod.log:warn("the game keeps its own trainer card: %s", tostring(errT)) end
    end
    if SC.options then
      local okO, errO = pcall(SC.options.wrap)
      if not okO then mod.log:warn("the game keeps its own OPTIONS: %s", tostring(errO)) end
    end
    if env.modsScreen then
      local okM, errM = pcall(env.modsScreen.wrap)
      if not okM then mod.log:warn("the game keeps its own MODS: %s", tostring(errM)) end
    end
    if SC.scenes then
      local okS, errS = pcall(SC.scenes.wrap)
      if not okS then mod.log:warn("the game keeps its own evolution and catch screens: %s", tostring(errS)) end
    end
    if Menus then pcall(Menus.wrap) end
    if RealShop then
      local okR, errR = pcall(RealShop.wrap)
      if not okR then mod.log:warn("the shops keep their own menus: %s", tostring(errR)) end
    end
    if env.pcgames then env.pcgames.reset() end
    if env.decorate then env.decorate.reset() end
    if env.map3d then env.map3d.lastStorm = nil end
    local ok, err = pcall(Sh.ready)
    if not ok then mod.log:warn("the PC keeps its own menu: %s", tostring(err)) end
    Sh.closeGear()
    if Gear then pcall(Gear.bind) end
  end)
  -- (a flag's change: the engine names it from FireRed's table whatever the game, so Ruby / Sapphire /
  -- Emerald's own name is looked up from its id -- a Badge's flag, a story flag)
  local function flagEvent(ev)
    local id = type(ev) == "table" and tonumber(ev.id)
    if not id then return ev end
    local F = engine("src.core.game3.scripting.flags")
    local ok, t = pcall(F and F.active or error, session())
    local nm = ok and type(t) == "table" and t.NAMES and t.NAMES[id]
    if type(nm) ~= "string" or nm == ev.name then return ev end
    return { name = nm, id = id, value = ev.value }
  end
  -- the journal's events (observed only), and an item used from the Bag or the field (the hook's
  -- answer passed on as it came)
  if env.journal then
    for _, name in ipairs({ "battle.started", "battle.damage_dealt", "battle.battler_switched", "battle.fainted",
                            "battle.ended", "pokemon.caught", "egg.hatched", "pokemon.evolved", "pokemon.level_up",
                            "map.entered", "world.stepped", "flag.changed" }) do
      if name == "flag.changed" then
        mod.events:on(name, function(ev) env.journal.on(name, flagEvent(ev)) end)
      else
        mod.events:on(name, function(ev) env.journal.on(name, ev) end)
      end
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
  -- the story's beats: a story flag changed, a new map (variables send no event), a save loaded (its own
  -- beats, kept without a notification the first time)
  if env.story then
    for _, name in ipairs({ "flag.changed", "map.entered" }) do
      mod.events:on(name, function(ev)
        pcall(env.story.on, name, name == "flag.changed" and flagEvent(ev) or ev, session())
      end)
    end
  end
  -- the GPS: each step and each map (there yet? the arrow's next warp); a loaded save's own waypoint and
  -- markers; Fly (the game's or ours: both through Field.flyTo, wrapped once per process) clears the waypoint
  if Gps then
    local Player = engine("src.core.game3.player")
    mod.events:on("world.stepped", function(ev)
      if type(ev) == "table" and Gps.route.dest() then
        pcall(Gps.route.step, ev.mapId, tonumber(ev.x) or 0, tonumber(ev.y) or 0)
      end
    end)
    mod.events:on("map.entered", function(ev)
      Gps.route.refresh()
      if type(ev) == "table" and Gps.route.dest() and Player then
        pcall(Gps.route.step, ev.mapId, tonumber(Player.cellX) or 0, tonumber(Player.cellY) or 0)
      end
    end)
    local Field = engine("src.core.game3.field")
    if Field and Field.flyTo then
      local w = rawget(Field, "__woobOsGps")
      if not w then
        w = { orig = Field.flyTo }
        Field.__woobOsGps = w
        Field.flyTo = function(...)
          if w.impl then pcall(w.impl) end
          return w.orig(...)
        end
      end
      w.impl = function() Gps.route.clear() end
    end
  end
  local function reloadSaved()
    if Gps then pcall(Gps.route.load) end
    if env.marks then pcall(env.marks.load) end
  end
  mod.events:on("checkpoint.restored", reloadSaved)
  -- (a new map or a loaded save: the next PC boots again)
  mod.events:on("map.entered", function() Sh.forget() end)
  mod.events:on("save.loaded", function(ev)
    Sh.forget()
    Sh.closeGear()
    reloadSaved()
    -- (auctions that ended while the game was closed: settled with the save they belong to)
    if env.auction then pcall(env.auction.settle, ev and ev.save or session()) end
    if env.gts then pcall(env.gts.settle, ev and ev.save or session()) end
    if env.errands then pcall(env.errands.settle, ev and ev.save or session()) end
    if env.story then pcall(env.story.check, ev and ev.save or session()) end
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
  mod.exports._test = { post = notify, desktop = Desktop, shell = Sh, apps = Apps, kit = Kit, inv = env.inv, mb = env.mb, bx = env.bx,
                        mart = env.mart, auction = env.auction, slots = env.slots, pcgames = env.pcgames, gts = env.gts,
                        bank = env.bank, journal = env.journal, challenges = env.challenges, errands = env.errands,
                        swarm = env.swarm, news = env.news, story = env.story, pokecenter = env.pokecenter, menus = env.menus, scenes = SC.scenes, sceneHost = SC.host, optionsScreen = SC.options, modsScreen = env.modsScreen, objectives = env.objectives,
                        env = env, i18n = T, settings = Settings, wall = Wall, arrange = Arrange,
                        watch = Watch, pad = Watch, notify = Nt, tick = tick, map3d = env.map3d, townmap = TownMap,
                        phone = env.phone, condition = env.condition, ribbons = env.ribbons, hall = env.hall, oak = env.oak, decorate = env.decorate, pokenav = Pokenav, onCall = onCall, gear = Gear, gearPanel = GearPanel,
                        gps = Gps, marks = env.marks }
end
