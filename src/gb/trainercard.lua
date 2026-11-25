-- The trainer card, modern, on the Game Boy games (src/apps/trainercard.lua the window; Gen 3's model is
-- src/trainercard.lua): START's TRAINER card -- the screen registry's "TrainerCard" on Red / Blue / Yellow,
-- "Gen2TrainerCard" on Gold / Silver / Crystal -- becomes a carrier of ours that opens the window, answering as
-- the game's screen does once it closes (Gen 1's pops itself, then onCancel(); Gen 2's calls onClose, its caller
-- pops it).
-- What it says is the save's: the name, ID, money, play time, the Pokédex (our Pokédex's counts), the badges (Gen 1
-- the badge items, Gen 2 Johto's and Kanto's), the Hall of Fame, the coins, the party. The card's tier is worked
-- out the way the Gen 3 games give stars: all eight badges, the Champion, then Gen 1 a full Kanto Pokédex and Mew,
-- Gen 2 Kanto's eight badges and a full Pokédex.
-- Its pictures are the game's own, borrowed from its own card built off the stack (Gen 1: the badges, the leaders'
-- faces and the player's picture in the card's palette; Gen 2: the badges turning as the cart turns them, the
-- leaders' faces, the player's portrait); Kanto's badges come from an imported FireRed / LeafGreen when there is one
-- (in colour, the same eight), never a path of ours.
--
--   Gt = GbTrainerCard(H, deps)   deps: Sh, on() -> the switch, T, kit (K), dex (env.dex), screens, log
--   Gt.install() (load: the screens) ; Gt.read(game) -> the window's model (the tests')

local floor, max, min = math.floor, math.max, math.min

local KANTO = {
  { "Boulder", "Brock", { 176, 176, 188 } }, { "Cascade", "Misty", { 80, 156, 255 } },
  { "Thunder", "Lt. Surge", { 255, 196, 60 } }, { "Rainbow", "Erika", { 120, 220, 130 } },
  { "Soul", "Koga", { 244, 110, 170 } }, { "Marsh", "Sabrina", { 236, 196, 70 } },
  { "Volcano", "Blaine", { 255, 96, 60 } }, { "Earth", "Giovanni", { 96, 204, 112 } },
}
-- (Gold / Silver / Crystal's Kanto: Janine at Fuchsia, Blue at Viridian)
local KANTO2 = { [5] = "Janine", [8] = "Blue" }
local JOHTO = {
  { "Zephyr", "Falkner", { 200, 222, 255 } }, { "Hive", "Bugsy", { 255, 204, 60 } },
  { "Plain", "Whitney", { 255, 170, 204 } }, { "Fog", "Morty", { 170, 140, 224 } },
  { "Storm", "Chuck", { 130, 170, 236 } }, { "Mineral", "Jasmine", { 196, 204, 214 } },
  { "Glacier", "Pryce", { 150, 222, 255 } }, { "Rising", "Clair", { 255, 140, 60 } },
}
local JOHTO_KEYS = { "ZEPHYR", "HIVE", "PLAIN", "FOG", "STORM", "MINERAL", "GLACIER", "RISING" }
-- (the order of the cart's badge OAM table: Mineral listed before Storm)
local OAM_ORDER = { "ZEPHYR", "HIVE", "PLAIN", "FOG", "MINERAL", "STORM", "GLACIER", "RISING" }
local WARM = { { 255, 255, 255 }, { 248, 204, 164 }, { 206, 74, 62 }, { 30, 24, 40 } }
local KANTO_KEYS = { "BOULDER", "CASCADE", "THUNDER", "RAINBOW", "SOUL", "MARSH", "VOLCANO", "EARTH" }

return function(H, deps)
  local Gt = {}
  local gen = H.gen
  local engine = H.engine
  local T = deps.T
  local function log(fmt, ...) if deps.log then pcall(deps.log, fmt, ...) end end
  local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b = pcall(f, ...)
    if not ok then
      log("the trainer card: %s", tostring(a))
      return nil
    end
    return a, b
  end
  local function num(v) return floor(tonumber(v) or 0) end
  local function grouped(n)
    local s = tostring(floor(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
  end
  local function on() return deps.on == nil or deps.on() == true end
  local open = false
  function Gt.isOpen() return open end
  local PATH = gen == 2 and "src.ui.gen2.TrainerCard" or "src.ui.TrainerCard"

  -- ------- Kanto's badges in colour, from an imported FireRed / LeafGreen
  local frlg = nil
  local function frlgBadges()
    if frlg ~= nil then return frlg or nil end
    frlg = false
    local CacheFs, GV, Contract = engine("src.import.CacheFs"), engine("src.core.GameVersion"),
      engine("src.import.CacheContract")
    if not (CacheFs and CacheFs.readAt and GV and Contract and love and love.image) then return nil end
    for _, v in ipairs({ "firered", "leafgreen" }) do
      local okP, pre = pcall(GV.cachePrefix, v)
      local files = okP and call(Contract.requiredFiles, v)
      for _, f in ipairs(type(files) == "table" and files or {}) do
        if type(f) == "string" and f:sub(-#"/trainer_card/manifest.lua") == "/trainer_card/manifest.lua"
            and not f:find("/rse/", 1, true) then
          local ok, data = pcall(CacheFs.readAt, pre .. f:sub(1, -#"manifest.lua" - 1) .. "badges.rgba")
          if ok and type(data) == "string" and #data == 128 * 16 * 4 then
            local okI, id = pcall(love.image.newImageData, 128, 16, "rgba8", data)
            local okG, img = false, nil
            if okI then okG, img = pcall(love.graphics.newImage, id) end
            if okG and img then
              img:setFilter("nearest", "nearest")
              frlg = { img = img, quads = {} }
              for i = 0, 7 do frlg.quads[i + 1] = love.graphics.newQuad(i * 16, 0, 16, 16, 128, 16) end
              return frlg
            end
          end
        end
      end
    end
    return nil
  end

  -- ------- what the save says
  local function playTime(save)
    if gen == 2 then
      local t = type(save.playTime) == "table" and save.playTime or {}
      return num(t.hours), num(t.minutes)
    end
    local t = num(save.playTime)
    return floor(t / 3600), floor(t / 60) % 60
  end
  local function hofCount(save)
    local h = save.hallOfFame
    if type(h) ~= "table" then return 0 end
    if gen == 2 then return num(h.count) end
    return #h
  end
  local function has(list, key, i)
    if type(list) ~= "table" then return false end
    local v = list[key] or list[key:lower()] or list[i] or list[key .. "BADGE"]
    return v == true or (tonumber(v) or 0) > 0
  end

  function Gt.read(game)
    local save = type(game) == "table" and game.save
    if type(save) ~= "table" then return nil end
    local player = type(save.player) == "table" and save.player or {}
    local card = {}
    card.name = tostring(player.name or "")
    local Gen2Save = gen == 2 and engine("src.core.gen2.Save")
    if gen == 2 then
      local fem = Gen2Save and call(Gen2Save.isFemale, save)
      card.female = fem == true
    end
    card.idText = string.format("%05d", num(player.id) % 65536)
    card.money = num(gen == 2 and player.money or save.money)
    card.hours, card.minutes = playTime(save)
    card.region = T(gen == 2 and "tc.region.johto" or "tc.region.kanto")
    -- (the Pokédex: our Pokédex's counts)
    local caught = 0
    if deps.dex and deps.dex.open then
      local book = call(deps.dex.open, save)
      local mode = book and book.modes and book.modes[#book.modes]
      local cnt = mode and book.counts and book.counts[mode]
      if cnt then
        caught = num(cnt.caught)
        card.dex = { caught = caught, seen = num(cnt.seen), total = book.lists[mode] and #book.lists[mode] or 0 }
      end
    end
    -- (the badges)
    local sets = {}
    if gen == 2 then
      local j = { title = T("tc.badges.johto"), badges = {}, kind = "johto" }
      for i, def in ipairs(JOHTO) do
        j.badges[i] = { name = def[1], leader = def[2], have = has(player.badges, JOHTO_KEYS[i], i), color = def[3] }
      end
      sets[1] = j
      local k = { title = T("tc.badges.kanto"), badges = {}, kind = "kanto" }
      local anyK = false
      for i, def in ipairs(KANTO) do
        local got = has(player.kantoBadges, KANTO_KEYS[i], i)
        anyK = anyK or got
        k.badges[i] = { name = def[1], leader = KANTO2[i] or def[2], have = got, color = def[3] }
      end
      sets[2] = k
      card.kantoStarted = anyK
    else
      local Badges = engine("src.inventory.Badges")
      local list = Badges and call(Badges.list, game.data) or {}
      local inv = type(save.inventory) == "table" and save.inventory or {}
      local k = { title = T("tc.badges.kanto"), badges = {}, kind = "kanto" }
      for i, def in ipairs(KANTO) do
        local entry = list[i]
        local got = entry and Badges and inv[Badges.itemFor(entry)] and true or false
        k.badges[i] = { name = def[1], leader = def[2], have = got == true, color = def[3] }
      end
      sets[1] = k
    end
    card.sets = sets
    -- (the tier: as the Gen 3 games give stars)
    local function all(set)
      for _, b in ipairs(set.badges) do if not b.have then return false end end
      return true
    end
    local hof = hofCount(save)
    local stars = 0
    if all(sets[1]) then stars = stars + 1 end
    if hof > 0 then stars = stars + 1 end
    if gen == 2 then
      if all(sets[2]) then stars = stars + 1 end
      if caught >= 251 then stars = stars + 1 end
    else
      if caught >= 150 then stars = stars + 1 end
      if caught >= 151 then stars = stars + 1 end
    end
    card.stars, card.maxStars, card.tier = stars, 4, stars
    if hof > 0 then card.champion = T.f("tc.championTimes", tostring(hof)) end
    -- (the records)
    local recs = {}
    local function add(icon, color, label, value)
      recs[#recs + 1] = { icon = icon, color = color, label = label, value = value }
    end
    if hof > 0 then add("medal", { 255, 184, 40 }, T("tc.rec.hof"), grouped(hof)) end
    local have, total = 0, 0
    for _, set in ipairs(sets) do
      for _, b in ipairs(set.badges) do
        total = total + 1
        if b.have then have = have + 1 end
      end
    end
    add("check", { 255, 149, 0 }, T("tc.rec.badges"), string.format("%d / %d", have, total))
    if card.dex then
      add("pokeball", { 236, 64, 72 }, T("tc.rec.owned"), grouped(card.dex.caught))
      add("eye", { 90, 200, 250 }, T("tc.rec.seen"), grouped(card.dex.seen))
    end
    local coins = num(gen == 2 and player.coins or save.coins)
    if coins > 0 then add("pokedollar", { 52, 199, 89 }, T("tc.rec.coins"), grouped(coins)) end
    card.records = recs
    -- (the party)
    card.party = {}
    for i, mon in ipairs(type(save.party) == "table" and save.party or {}) do
      if i > 6 then break end
      if mon and mon.species then card.party[#card.party + 1] = { sp = mon.species, level = tonumber(mon.level), mon = mon } end
    end
    -- (the pictures: the game's own card, built off the stack)
    local M = engine(PATH)
    local inst
    if M and M.new then
      local okN, got = pcall(M.new, game, {})
      if okN then inst = got else log("the game's trainer card (for its pictures): %s", tostring(got)) end
    end
    card.art = Gt.art(game, inst, card)
    return card
  end

  -- ------- the pictures
  function Gt.art(game, inst, card)
    local K = deps.kit
    local G = love and love.graphics
    local art = {}
    local GbcPalette = engine("src.render.GbcPalette")
    local fr = frlgBadges()
    -- (a drawing in a palette: one body, its arguments set before each call -- nothing made while drawing)
    local P = { img = nil, quad = nil, x = 0, y = 0, s = 1 }
    local function body() G.draw(P.img, P.quad, P.x, P.y, 0, P.s, P.s) end
    local function bodyFlip() G.draw(P.img, P.quad, P.x, P.y, 0, -P.s, P.s) end
    -- (Gen 1's pictures in warm colours of their own -- white, skin, Red's red, near-black -- rather than the whole
    -- screen's palette, which tints them purple and orange alone)
    local cardPal = gen == 1 and WARM or nil
    -- (the player's colours for the portrait, once; the keyed palette leaves its white clear)
    local portraitColors = gen == 2 and inst and inst.colorsAt and call(inst.colorsAt, inst, 14, 1) or nil
    local function inKeyed(pal)
      if pal and GbcPalette and GbcPalette.keyedWith and GbcPalette.available and GbcPalette.available() then
        GbcPalette.keyedWith(pal, body)
      else
        body()
      end
    end
    local function inPalette(pal, fn)
      fn = fn or body
      if pal and GbcPalette and GbcPalette.available and GbcPalette.available() then
        GbcPalette.with(pal, fn)
      else
        fn()
      end
    end
    -- (an image's quad centred, scaled)
    local function quadAt(img, quad, cx, cy, size, srcW, srcH, pal, have)
      local px = size / max(srcW, srcH) * K.sc
      P.img, P.quad, P.s = img, quad, px
      P.x, P.y = K.X(cx) - srcW * px / 2, K.Y(cy) - srcH * px / 2
      if have == false then G.setColor(0, 0, 0, 0.55 * K.getFade()) else G.setColor(1, 1, 1, K.getFade()) end
      inPalette(pal)
    end

    function art.portrait(cx, foot, w, h)
      if not (inst and K and G) then return false end
      if gen == 1 then
        if not (inst.pic and inst.picQuad) then return false end
        local pw, ph = inst.picW or 32, inst.picH or 48
        local sc = min(w / pw, h / ph) * K.sc
        if sc >= 1 then sc = floor(sc) end
        P.img, P.quad, P.s = inst.pic, inst.picQuad, sc
        P.x, P.y = K.X(cx) - pw * sc / 2, K.Y(foot) - ph * sc
        G.setColor(1, 1, 1, K.getFade())
        inPalette(not inst.picTrueColor and cardPal or nil)
        return true
      end
      -- (Gen 2: the card's 5 x 7 portrait, tile by tile in the player's colours, its white left clear)
      local gfx = inst.gfx
      local sheet = inst.card
      if not (gfx and sheet and sheet.image and sheet:image()) then return false end
      local wide = gfx.portraitWide or 5
      local high = floor((gfx.portraitTiles or 35) / wide)
      local pw, ph = wide * 8, high * 8
      local sc = min(w / pw, h / ph) * K.sc
      if sc >= 1 then sc = floor(sc) end
      local x0, y0 = K.X(cx) - pw * sc / 2, K.Y(foot) - ph * sc
      G.setColor(1, 1, 1, K.getFade())
      local img = sheet:image()
      for row = 0, high - 1 do
        for col = 0, wide - 1 do
          local q = sheet:quad(row * wide + col - (sheet.firstTile or 0))
          if q then
            P.img, P.quad, P.s = img, q, sc
            P.x, P.y = x0 + col * 8 * sc, y0 + row * 8 * sc
            inKeyed(portraitColors)
          end
        end
      end
      return true
    end

    -- the badges: Kanto's from FireRed when it's there; else the game's own
    local frame2 = 0
    function art.badge(set, i, cx, cy, size, clock, have)
      if not (K and G) then return end
      local kind = card.sets[set] and card.sets[set].kind
      if kind == "kanto" and fr and fr.quads[i] then
        quadAt(fr.img, fr.quads[i], cx, cy, size, 16, 16, nil, have)
        return
      end
      if gen == 1 then
        if inst and inst.badges and inst.badges.quads[i - 1] then
          quadAt(inst.badges.img, inst.badges.quads[i - 1], cx, cy, size, 16, 16, cardPal, have)
        end
        return
      end
      if kind ~= "johto" then
        -- (Gen 2's Kanto with no FireRed: the badge's colour, its first letter)
        local b = card.sets[set].badges[i]
        local r = size * 0.38
        K.col(have and b.color or K.BLACK, have and 0.95 or 0.4)
        G.circle("fill", K.X(cx), K.Y(cy), r * K.sc, 24)
        K.bold(b.name:sub(1, 1), cx - r, cy - r * 0.62, r * 1.1, K.WHITE, "center", r * 2, have and 1 or 0.4)
        return
      end
      -- (Johto: the cart's badge, turning as it does -- eight frames, one every 8 / 60 s)
      local gfx = inst and inst.gfx
      local list = gfx and gfx.badgeOam
      if not (list and inst.badges and inst.badges.available and inst.badges:available()) then return end
      local key = JOHTO_KEYS[i]
      local obj
      for k2, name in ipairs(OAM_ORDER) do
        if name == key then obj = list[k2] end
      end
      if not obj then return end
      -- (face on, each turning over now and then as the cart turns them, one after another)
      local ph = ((clock or 0) + i * 0.55) % 6
      frame2 = ph < 64 / 60 and floor(ph * 60 / 8) % 8 or 0
      local tile = have and (obj.frames[frame2 + 1] or 0) or (obj.frames[1] or 0)
      local flip = tile >= 0x80
      local base = flip and (tile - 0x80) or tile
      local px = size / 16 * K.sc
      local ox, oy = K.X(cx) - 8 * px, K.Y(cy) - 8 * px
      if have then G.setColor(1, 1, 1, K.getFade()) else G.setColor(0, 0, 0, 0.55 * K.getFade()) end
      local img = inst.badges:image()
      for c = 0, 3 do
        local cxp, cyp = c % 2, floor(c / 2)
        local q = inst.badges:quad(base + c)
        if q then
          P.img, P.quad = img, q
          local dx = flip and (1 - cxp) or cxp
          if flip then
            P.x, P.y, P.s = ox + (dx * 8 + 8) * px, oy + cyp * 8 * px, px
            inPalette(gfx.badgePalette, bodyFlip)
          else
            P.x, P.y, P.s = ox + dx * 8 * px, oy + cyp * 8 * px, px
            inPalette(gfx.badgePalette)
          end
        end
      end
    end

    -- (a set with leaders' faces: Gen 1's, Gen 2's Johto -- the cart has none for Gen 2's Kanto)
    function art.hasFace(set)
      if gen == 1 then return inst ~= nil and inst.faces ~= nil end
      return card.sets[set] ~= nil and card.sets[set].kind == "johto" and inst ~= nil
    end
    -- the leaders' faces (the Game Boy cards': Gen 1's sheet, Gen 2's drawn by the game at its place)
    function art.face(set, i, cx, cy, size, have)
      if not (inst and K and G) then return end
      local kind = card.sets[set] and card.sets[set].kind
      if gen == 1 then
        if inst.faces and inst.faces.quads[i - 1] then
          quadAt(inst.faces.img, inst.faces.quads[i - 1], cx, cy, size, 16, 16, cardPal, true)
        end
        return
      end
      if kind ~= "johto" or not inst.drawLeaderFace or not inst.gfx then return end
      local first = (inst.gfx.leadersFirstTile or 0) + (i - 1) * 10
      local tx = 2 + ((i - 1) % 4) * 4
      local ty = i <= 4 and 10 or 13
      local sc = size / 32 * K.sc
      G.push()
      G.translate(K.X(cx) - 16 * sc, K.Y(cy) - 12 * sc)
      G.scale(sc, sc)
      G.translate(-tx * 8, -ty * 8)
      G.setColor(1, 1, 1, K.getFade())
      pcall(inst.drawLeaderFace, inst, first, tx, ty)
      G.pop()
      G.setColor(1, 1, 1, 1)
    end
    return art
  end

  -- ------- the takeover: a carrier in the game's screen's place
  local function carrierDraw(self)
    local G = love and love.graphics
    if G then
      G.setColor(0, 0, 0, 1)
      G.rectangle("fill", 0, 0, 160, 144)
      G.setColor(1, 1, 1, 1)
    end
  end
  local function carrierUpdate(self)
    if self.done then return end
    if self.opened then
      if not (deps.Sh.hostOpen and deps.Sh.hostOpen()) then self.finish() end
      return
    end
    self.opened = true
    local card = Gt.read(self.game)
    local ok, got = false, false
    if card then
      open = true
      ok, got = pcall(deps.Sh.openFull, "trainercard", self.game.save, function() self.finish() end, nil,
        { menu = card, chrome = false, noHints = true })
      if not ok then log("the trainer card failed to open: %s", tostring(got)) end
    end
    if not (ok and got) then
      open = false
      self.done = true
      local stk = self.game.stack
      if stk and stk:top() == self then pcall(stk.pop, stk) end
      local M = engine(PATH)
      if M then stk:push(M.new(self.game, self.opts)) end
    end
  end

  function Gt.install()
    local reg = deps.screens
    if not (reg and reg.register) then return false end
    local id = gen == 2 and "Gen2TrainerCard" or "TrainerCard"
    reg:register(id, { new = function(game, opts)
      opts = opts or {}
      local M = engine(PATH)
      if not (M and on() and type(game) == "table" and game.save) then return M.new(game, opts) end
      local c = H.noId({ update = carrierUpdate, draw = carrierDraw, isOpaque = true, game = game, opts = opts })
      c.finish = function()
        if c.done then return end
        c.done = true
        open = false
        local stk = game.stack
        if gen == 2 then
          -- (the caller pops it, as it pops the game's)
          if opts.onClose then
            local okD, errD = pcall(opts.onClose)
            if not okD then log("after the trainer card: %s", tostring(errD)) end
          end
          if stk and stk:top() == c then pcall(stk.pop, stk) end
        else
          if stk and stk:top() == c then pcall(stk.pop, stk) end
          if opts.onCancel then
            local okC, errC = pcall(opts.onCancel)
            if not okC then log("after the trainer card: %s", tostring(errC)) end
          end
        end
      end
      return c
    end })
    return true
  end

  return Gt
end
