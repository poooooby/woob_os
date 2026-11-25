-- The trainer card, modern, on FireRed, LeafGreen, Ruby, Sapphire and Emerald (src/apps/trainercard.lua the window;
-- the Game Boy games' model is src/gb/trainercard.lua). START's TRAINER CARD -- the game's src.ui.game3.trainer_card
-- show -- opens ours full screen instead (Modern Menus' "Trainer Card" switch); a link partner's card (the Union
-- Room, the Cable Club) stays the game's.
-- What it says is the game's own: FireRed / LeafGreen / Emerald's card is worked out by the game's own show (its
-- stars, badges, the Hall of Fame debut, link battles, trades, Berry Crush, the Union Room, contests, Pokéblocks,
-- Battle Points) -- run with the game's screen stack stood in for, so it's never pushed -- and Ruby / Sapphire's by
-- its card policy; the Pokédex counts are our Pokédex's (env.dex), the journey's numbers the game's own stats.
-- Its pictures are the cart's: the card's badge sheet and the trainer's front picture, found through the engine
-- (the cache contract, the card's manifest), never a path of ours.
--
--   Tc = TrainerCard(engine, deps)   deps: Sh, on() -> the switch, T, kit (K), dex (env.dex), gameId(), log
--   Tc.wrap() (game.ready) ; Tc.read(s) -> the window's model (src/apps/trainercard.lua) | nil

local floor, max, min = math.floor, math.max, math.min

-- each region's badges: the name on the badge, its leader, a colour for its light
local SETS = {
  kanto = {
    { "Boulder", "Brock", { 176, 176, 188 } }, { "Cascade", "Misty", { 80, 156, 255 } },
    { "Thunder", "Lt. Surge", { 255, 196, 60 } }, { "Rainbow", "Erika", { 120, 220, 130 } },
    { "Soul", "Koga", { 244, 110, 170 } }, { "Marsh", "Sabrina", { 236, 196, 70 } },
    { "Volcano", "Blaine", { 255, 96, 60 } }, { "Earth", "Giovanni", { 96, 204, 112 } },
  },
  hoenn = {
    { "Stone", "Roxanne", { 180, 160, 140 } }, { "Knuckle", "Brawly", { 214, 170, 120 } },
    { "Dynamo", "Wattson", { 255, 206, 70 } }, { "Heat", "Flannery", { 255, 110, 60 } },
    { "Balance", "Norman", { 226, 132, 100 } }, { "Feather", "Winona", { 130, 196, 255 } },
    { "Mind", "Tate & Liza", { 244, 124, 204 } }, { "Rain", "Juan", { 90, 156, 255 } },
  },
}
-- the game's own stats worth showing (pokeemerald / pokefirered's GAME_STAT_*), in the order they're listed
local JOURNEY = {
  { 10, "tc.rec.hof", "medal", { 255, 184, 40 } },
  { 7, "tc.rec.battles", "glove", { 255, 69, 58 } },
  { 11, "tc.rec.caught", "pokeball", { 236, 64, 72 } },
  { 13, "tc.rec.eggs", "cube", { 52, 199, 89 } },
  { 14, "tc.rec.evolved", "check", { 175, 82, 222 } },
  { 5, "tc.rec.steps", "shoes", { 90, 200, 250 } },
  { 12, "tc.rec.fishing", "fish", { 0, 122, 255 } },
  { 15, "tc.rec.center", "building", { 255, 45, 85 } },
  { 38, "tc.rec.shopped", "bag", { 255, 149, 0 } },
}

return function(engine, deps)
  local Tc = {}
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
  local function gid() return deps.gameId and deps.gameId() or "firered" end
  local function rse() local g = gid() return g == "emerald" or g == "ruby" or g == "sapphire" end
  local function rs() local g = gid() return g == "ruby" or g == "sapphire" end
  local function num(v) return floor(tonumber(v) or 0) end
  local function grouped(n)
    local s = tostring(floor(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
  end

  -- ------- the game's own answers
  -- (FireRed / LeafGreen / Emerald: the game's show works the card out; its screen stack stood in for, so nothing
  -- is pushed, and its state put back after; its opening sound plays, as the game's)
  local function gameCard(s)
    local TC = engine("src.ui.game3.trainer_card")
    local Stack = engine("src.ui.game3.stack")
    if not (TC and Stack and Tc.orig) then return nil end
    local push = Stack.push
    Stack.push = function() end
    local ok, err = pcall(Tc.orig, { session = s })
    Stack.push = push
    local c = TC._card
    TC.open, TC._session, TC._card, TC._onClose, TC._flip, TC.side = false, nil, nil, nil, nil, "front"
    if not ok then
      log("the trainer card's data: %s", tostring(err))
      return nil
    end
    return type(c) == "table" and c or nil
  end
  local function rsCard(s)
    local P = engine("src.ui.game3.rs.trainer_card_policy")
    local c = P and call(P.generate, s)
    if type(c) ~= "table" then return nil end
    c.playerName = c.name
    c.female = c.gender == 1 or c.gender == "female" or c.gender == "F"
    c.hasHofResult = (c.hofDebutHours or 0) ~= 0 or (c.hofDebutMinutes or 0) ~= 0 or (c.hofDebutSeconds or 0) ~= 0
    c.hasLinkResults = (c.linkBattleWins or 0) ~= 0 or (c.linkBattleLosses or 0) ~= 0
    c.hasTrades = (c.pokemonTrades or 0) ~= 0
    return c
  end

  -- ------- the cart's pictures
  local art = { tried = false }
  local function findArt()
    if art.tried then return art end
    art.tried = true
    local Kit = engine("src.ui.game3.rse.scene_kit")
    if not (Kit and love and love.graphics) then return art end
    if rse() then
      local m = call(Kit.manifest, "rse/trainer_card")
      if type(m) ~= "table" then return art end
      if type(m.badges) == "table" and m.badges.png then art.badges = call(Kit.image, m.badges.png) end
      local root = m.badges and type(m.badges.png) == "string" and m.badges.png:match("^(.-)rse/trainer_card/")
      if type(m.pics) == "table" and root then
        -- (Emerald: the trainers' front pictures, by number)
        art.male = call(Kit.rgbaImage, root .. "trainers/front/" .. tostring(m.pics.male) .. ".rgba", 64, 64)
        art.female = call(Kit.rgbaImage, root .. "trainers/front/" .. tostring(m.pics.female) .. ".rgba", 64, 64)
      else
        -- (Ruby / Sapphire: the card's own two pictures)
        for _, f in ipairs(m.files or {}) do
          if type(f) == "string" and f:sub(-9) == "/male.png" then art.male = call(Kit.image, f) end
          if type(f) == "string" and f:sub(-11) == "/female.png" then art.female = call(Kit.image, f) end
        end
      end
    else
      -- (FireRed / LeafGreen: the card's folder from the contract, its manifest, its badge sheet)
      local Contract = engine("src.import.CacheContract")
      local files = Contract and call(Contract.requiredFiles, gid())
      local man
      for _, f in ipairs(type(files) == "table" and files or {}) do
        if type(f) == "string" and f:sub(-#"/trainer_card/manifest.lua") == "/trainer_card/manifest.lua"
            and not f:find("/rse/", 1, true) then
          man = f
        end
      end
      if man then
        local dir = man:sub(1, -#"manifest.lua" - 1)
        local root = dir:sub(1, -#"trainer_card/" - 1)
        local m = call(Kit.loadLua, man)
        art.badges = call(Kit.rgbaImage, dir .. "badges.rgba", 128, 16)
        if type(m) == "table" and type(m.pics) == "table" then
          art.male = call(Kit.rgbaImage, root .. "trainers/front/" .. tostring(m.pics.male) .. ".rgba", 64, 64)
          art.female = call(Kit.rgbaImage, root .. "trainers/front/" .. tostring(m.pics.female) .. ".rgba", 64, 64)
        end
      end
    end
    if art.badges then
      local iw, ih = art.badges:getDimensions()
      art.quads = {}
      for i = 0, 7 do art.quads[i + 1] = love.graphics.newQuad(i * 16, 0, 16, 16, iw, ih) end
    end
    return art
  end

  -- ------- the card
  function Tc.read(s)
    if type(s) ~= "table" then return nil end
    local c = rs() and rsCard(s) or gameCard(s)
    if not c then return nil end
    local card = {}
    card.name = tostring(c.playerName or c.name or s.name or "")
    card.female = c.female == true
    card.idText = string.format("%05d", num(c.trainerId) % 65536)
    card.money = num(c.money or s.money)
    card.hours, card.minutes = num(c.playTimeHours), num(c.playTimeMinutes) % 60
    card.stars, card.maxStars = max(0, min(4, num(c.stars))), 4
    card.tier = card.stars
    local region = rse() and "hoenn" or "kanto"
    card.region = T("tc.region." .. region)
    -- (the Pokédex: our Pokédex's counts, the list the game shows now -- the National Dex once it has it)
    if c.hasPokedex and deps.dex and deps.dex.open then
      local book = call(deps.dex.open, s)
      local mode = book and book.modes and book.modes[#book.modes]
      local cnt = mode and book.counts and book.counts[mode]
      if cnt then
        card.dex = { caught = num(cnt.caught), seen = num(cnt.seen), total = book.lists[mode] and #book.lists[mode] or 0 }
      else
        card.dex = { caught = num(c.caughtMonsCount), seen = num(c.caughtMonsCount), total = 0 }
      end
    end
    -- (the badges)
    local set = { title = T("tc.badges." .. region), badges = {} }
    for i, def in ipairs(SETS[region]) do
      local leader = def[2]
      if i == 8 and region == "hoenn" and rs() then leader = "Wallace" end
      set.badges[i] = { name = def[1], leader = leader, have = c.badges and c.badges[i] == true, color = def[3] }
    end
    card.sets = { set }
    -- (the records: the Hall of Fame, link play, the game's extras, the journey)
    local recs = {}
    local function add(icon, color, label, value, sub, bar)
      recs[#recs + 1] = { icon = icon, color = color, label = label, value = value, sub = sub, bar = bar }
    end
    if c.hasHofResult then
      local t = string.format("%d:%02d:%02d", num(c.hofDebutHours), num(c.hofDebutMinutes), num(c.hofDebutSeconds))
      add("medal", { 255, 184, 40 }, T("tc.rec.debut"), t)
      card.champion = T.f("tc.champion", t)
    end
    if c.hasLinkResults then
      local w, l = num(c.linkBattleWins), num(c.linkBattleLosses)
      add("controller", { 88, 86, 214 }, T("tc.rec.link"), T.f("tc.winLoss", tostring(w), tostring(l)), nil,
        (w + l) > 0 and w / (w + l) or nil)
    end
    if c.hasTrades then add("send", { 48, 176, 199 }, T("tc.rec.trades"), grouped(num(c.pokemonTrades))) end
    if num(c.unionRoomNum) > 0 then add("network", { 0, 199, 190 }, T("tc.rec.union"), grouped(num(c.unionRoomNum))) end
    if num(c.berryCrushPoints) > 0 then add("flower", { 255, 45, 85 }, T("tc.rec.crush"), grouped(num(c.berryCrushPoints))) end
    if num(c.contestsWithFriends) > 0 then add("mic", { 255, 149, 0 }, T("tc.rec.contests"), grouped(num(c.contestsWithFriends))) end
    if num(c.pokeblocksWithFriends) > 0 then add("cube", { 255, 214, 10 }, T("tc.rec.blocks"), grouped(num(c.pokeblocksWithFriends))) end
    if num(c.frontierBP) > 0 then add("pokedollar", { 52, 199, 89 }, T("tc.rec.bp"), grouped(num(c.frontierBP))) end
    if num(c.battleTowerWins) > 0 then
      add("building", { 90, 120, 255 }, T("tc.rec.tower"), grouped(num(c.battleTowerWins)),
        T.f("tc.streak", tostring(num(c.battleTowerLosses))))
    end
    local stats = type(s.gameStats) == "table" and s.gameStats or {}
    for _, j in ipairs(JOURNEY) do
      local v = num(stats[j[1]])
      if v > 0 and #recs < 8 then add(j[3], j[4], T(j[2]), grouped(v)) end
    end
    card.records = recs
    -- (the party, as it stands)
    card.party = {}
    for i, mon in ipairs(type(s.party) == "table" and s.party or {}) do
      if i > 6 then break end
      local sp = tonumber(mon.species or mon.sp)
      if sp and sp > 0 then card.party[#card.party + 1] = { sp = sp, level = tonumber(mon.level), mon = mon } end
    end
    -- (the pictures)
    local a = findArt()
    local G = love and love.graphics
    local K = deps.kit
    card.art = {}
    function card.art.portrait(cx, foot, w, h)
      local img = card.female and (a.female or a.male) or (a.male or a.female)
      if not (img and K and G) then return false end
      local iw, ih = img:getDimensions()
      local sc = min(w / iw, h / ih)
      -- (whole steps when it can: pixel art stays sharp)
      local px = sc * K.sc
      if px >= 1 then px = floor(px) end
      local dw, dh = iw * px, ih * px
      G.setColor(1, 1, 1, K.getFade())
      G.draw(img, K.X(cx) - dw / 2, K.Y(foot) - dh, 0, px, px)
      return true
    end
    function card.art.badge(_, i, cx, cy, size, _, have)
      if not (a.badges and a.quads and a.quads[i] and K and G) then return end
      local px = size / 16 * K.sc
      if have then G.setColor(1, 1, 1, K.getFade()) else G.setColor(0, 0, 0, 0.55 * K.getFade()) end
      G.draw(a.badges, a.quads[i], K.X(cx) - 8 * px, K.Y(cy) - 8 * px, 0, px, px)
    end
    local g = gid()
    card.sounds = g == "emerald" and { flip = "SE_RG_CARD_FLIP", close = "SE_RG_CARD_FLIPPING" }
      or (rs() and { flip = "SE_SELECT", close = "SE_SELECT" })
      or { flip = "SE_CARD_FLIP", close = "SE_CARD_FLIPPING" }
    return card
  end

  -- ------- the takeover
  function Tc.wrap()
    local TC = engine("src.ui.game3.trainer_card")
    if not (TC and TC.show) then return false end
    local slot = rawget(TC, "__woobOsCard")
    if not slot then
      slot = { orig = TC.show }
      TC.__woobOsCard = slot
      TC.show = function(opts)
        if slot.impl then return slot.impl(opts) end
        return slot.orig(opts)
      end
    end
    Tc.orig = slot.orig
    slot.impl = function(opts)
      opts = opts or {}
      local s = opts.session
      -- (ours: the switch on, the player's own card -- a link partner's stays the game's)
      if not (deps.on and deps.on()) or opts.linkCard or type(s) ~= "table" or s.dex == nil then
        return slot.orig(opts)
      end
      local card = Tc.read(s)
      if not card then return slot.orig(opts) end
      local ok, opened = pcall(deps.Sh.openFull, "trainercard", s, function()
        if opts.onClose then
          local okC, errC = pcall(opts.onClose)
          if not okC then log("after the trainer card: %s", tostring(errC)) end
        end
      end, nil, { menu = card, chrome = false, noHints = true })
      if not (ok and opened) then
        if not ok then log("the trainer card failed to open: %s", tostring(opened)) end
        return slot.orig(opts)
      end
    end
    return true
  end

  return Tc
end
