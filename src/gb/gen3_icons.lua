-- Gen 3's item pictures on Red / Blue / Yellow / Gold / Silver / Crystal, when the player has a Gen 3 game
-- imported too: Emerald's sheet of 24 px icons, else FireRed's / LeafGreen's (the same art, one file per
-- item), read from that game's own imported cache -- nothing of it ships with the mod. The files are found
-- through the engine's cache contract (the files each version's import has) and the version's cache
-- prefix: the engine keeps its Gen 3 modules from a mod on a Game Boy game (they read and write Gen 3's
-- save shapes), so only those generation-free ones are asked. These games' items are matched to Gen 3's
-- item numbers by name (GEN3, below; a few renamed: Parlyz Heal, the Gen 2 Berries), a TM / HM by its
-- move's type (Gen 3's discs are coloured by type). An item with no match, or no Gen 3 game imported: no
-- picture, and src/gb/main.lua draws its tile as before.
--
--   Gi = Gen3Icons(engine, Gd)
--   Gi.number(id) -> the Gen 3 item number for one of these games' item ids, or nil
--   Gi.source() -> "emerald" | "firered" | "leafgreen" | nil (looked for once)
--   Gi.draw(G, id, X, Y, k, alpha) -> true when drawn (G the kit's graphics): at pixels X, Y, scaled k
--                                      (24 px -> 24 * k)

-- these games' items by Gen 3's numbers (the same in all five Gen 3 games); Gen 2's Berries as the Gen 3
-- Berry that does the same (Berry: Oran, PRZCureBerry: Cheri, MiracleBerry: Lum ...)
local GEN3 = {
  AMULET_COIN = 189, ANTIDOTE = 14, AWAKENING = 17, BASEMENT_KEY = 271, BERRY = 139, BERRY_JUICE = 44,
  BICYCLE = 360, BIG_MUSHROOM = 104, BIG_PEARL = 107, BIKE_VOUCHER = 352, BITTER_BERRY = 140, BLACKBELT_I = 207,
  BLACKGLASSES = 206, BRIGHTPOWDER = 179, BURNT_BERRY = 137, BURN_HEAL = 15, CALCIUM = 67, CARBOS = 66,
  CARD_KEY = 355, CHARCOAL = 215, CLEANSE_TAG = 190, COIN_CASE = 260, DIRE_HIT = 74, DOME_FOSSIL = 358,
  DRAGON_FANG = 216, DRAGON_SCALE = 201, ELIXER = 36, ENERGYPOWDER = 30, ENERGY_ROOT = 31, ESCAPE_ROPE = 85,
  ETHER = 34, EVERSTONE = 195, EXP_ALL = 182, EXP_SHARE = 182, FIRE_STONE = 95, FOCUS_BAND = 196, FRESH_WATER = 26,
  FULL_HEAL = 23, FULL_RESTORE = 19, GOLD_BERRY = 142, GOLD_TEETH = 353, GOOD_ROD = 263, GREAT_BALL = 3,
  GUARD_SPEC = 73, HARD_STONE = 204, HEAL_POWDER = 32, HELIX_FOSSIL = 357, HP_UP = 63, HYPER_POTION = 21,
  ICE_BERRY = 136, ICE_HEAL = 16, IRON = 65, ITEMFINDER = 261, KINGS_ROCK = 187, LEAF_STONE = 98, LEFTOVERS = 200,
  LEMONADE = 28, LIFT_KEY = 356, LIGHT_BALL = 202, LUCKY_EGG = 197, LUCKY_PUNCH = 222, MAGNET = 208,
  MASTER_BALL = 1, MAX_ELIXER = 37, MAX_ETHER = 35, MAX_POTION = 20, MAX_REPEL = 84, MAX_REVIVE = 25,
  METAL_COAT = 199, METAL_POWDER = 223, MINT_BERRY = 134, MIRACLEBERRY = 141, MIRACLE_SEED = 205, MOOMOO_MILK = 29,
  MOON_STONE = 94, MYSTERYBERRY = 138, MYSTIC_WATER = 209, NEVERMELTICE = 212, NUGGET = 110, OAKS_PARCEL = 349,
  OLD_AMBER = 354, OLD_ROD = 262, PARLYZ_HEAL = 18, PEARL = 106, POISON_BARB = 211, POKE_BALL = 4, POKE_DOLL = 80,
  POKE_FLUTE = 350, POTION = 13, PP_UP = 69, PROTEIN = 64, PRZCUREBERRY = 133, PSNCUREBERRY = 135,
  QUICK_CLAW = 183, RARE_CANDY = 68, REPEL = 86, REVIVAL_HERB = 33, REVIVE = 24, SACRED_ASH = 45, SAFARI_BALL = 5,
  SCOPE_LENS = 198, SECRET_KEY = 351, SHARP_BEAK = 210, SILPH_SCOPE = 359, SILVERPOWDER = 188, SMOKE_BALL = 194,
  SODA_POP = 27, SOFT_SAND = 203, SPELL_TAG = 213, STARDUST = 108, STAR_PIECE = 109, STICK = 225, SUN_STONE = 93,
  SUPER_POTION = 22, SUPER_REPEL = 83, SUPER_ROD = 264, S_S_TICKET = 265, THICK_CLUB = 224, THUNDERSTONE = 96,
  THUNDER_STONE = 96, TINYMUSHROOM = 103, TOWN_MAP = 361, TWISTEDSPOON = 214, ULTRA_BALL = 2, UP_GRADE = 218,
  WATER_STONE = 97, X_ACCURACY = 78, X_ATTACK = 75, X_DEFEND = 76, X_SPECIAL = 79, X_SPEED = 77
}
-- a disc of each type (Gen 3's TM / HM item numbers; TM01 is 289, HM01 339): Gen 3 has no Bug one
local TM_OF_TYPE = {
  [0] = 293, [1] = 289, [2] = 328, [3] = 294, [4] = 314, [5] = 325, [7] = 318, [8] = 311, [10] = 299,
  [11] = 291, [12] = 297, [13] = 312, [14] = 292, [15] = 295, [16] = 290, [17] = 300,
}
local HM_OF_TYPE = { [0] = 339, [1] = 344, [2] = 340, [11] = 341 }
local ICON_BYTES = 24 * 24 * 4

return function(engine, Gd)
  local Gi = {}

  -- ------- the names
  local numberOf = {}
  function Gi.number(id)
    if type(id) ~= "string" then return nil end
    local got = numberOf[id]
    if got ~= nil then return got or nil end
    got = false
    if id:match("^TM_") or id:match("^HM_") then
      local move = Gd.tmMove(id)
      local d = Gd.data()
      local mv = move and d and d.moves and d.moves[move]
      local t = mv and Gd.typeId(mv.type)
      if t then got = (id:match("^HM_") and HM_OF_TYPE[t]) or TM_OF_TYPE[t] or false end
    else
      got = GEN3[id] or false
    end
    numberOf[id] = got
    return got or nil
  end

  -- ------- the pictures, from whichever Gen 3 game is imported
  local art = nil
  local function find()
    if art ~= nil then return art end
    art = false
    local CacheFs, GV = engine("src.import.CacheFs"), engine("src.core.GameVersion")
    local Contract = engine("src.import.CacheContract")
    if not (CacheFs and CacheFs.readAt and GV and Contract and Contract.requiredFiles and love and love.image) then
      return art
    end
    -- (a version's file whose path ends so, from the contract: nil when it has none)
    local function fileOf(version, tail)
      local ok, files = pcall(Contract.requiredFiles, version)
      if not (ok and type(files) == "table") then return nil end
      for _, f in ipairs(files) do
        if type(f) == "string" and f:sub(-#tail) == tail then return f end
      end
      return nil
    end
    -- (Emerald: one sheet, an icon every 24 rows, by item number)
    local okP, pre = pcall(GV.cachePrefix, "emerald")
    local sheet = fileOf("emerald", "/bag/icons.rgba")
    if okP and type(pre) == "string" and sheet then
      local ok, data = pcall(CacheFs.readAt, pre .. sheet)
      if ok and type(data) == "string" and #data >= ICON_BYTES and #data % ICON_BYTES == 0 then
        local h = #data / (24 * 4)
        local okI, imgData = pcall(love.image.newImageData, 24, h, "rgba8", data)
        local okG, img = false, nil
        if okI and imgData then okG, img = pcall(love.graphics.newImage, imgData) end
        if okG and img then
          img:setFilter("nearest", "nearest")
          art = { game = "emerald", sheet = img, count = h / 24, h = h, quads = {} }
          return art
        end
      end
    end
    -- (FireRed / LeafGreen: a file per item number)
    local Ex = engine("src.import.gba.bag_chrome_extract")
    if Ex and type(Ex.CACHE_SUB) == "string" then
      for _, v in ipairs({ "firered", "leafgreen" }) do
        local okV, p = pcall(GV.cachePrefix, v)
        local manifest = fileOf(v, "/" .. Ex.CACHE_SUB .. "/manifest.lua")
        if okV and type(p) == "string" and manifest then
          local dir = p .. manifest:sub(1, -#"manifest.lua" - 1) .. "icons/"
          -- (the Poké Ball's: there when the game's cache is)
          local ok, data = pcall(CacheFs.readAt, dir .. "4.rgba")
          if ok and type(data) == "string" and #data == ICON_BYTES then
            art = { game = v, dir = dir, imgs = {}, read = CacheFs.readAt }
            return art
          end
        end
      end
    end
    return art
  end
  function Gi.source()
    local a = find()
    return a and a.game or nil
  end

  -- one FireRed / LeafGreen icon, read once (false: none)
  local function fileIcon(a, n)
    local img = a.imgs[n]
    if img ~= nil then return img end
    img = false
    local ok, data = pcall(a.read, a.dir .. n .. ".rgba")
    if ok and type(data) == "string" and #data == ICON_BYTES then
      local okI, imgData = pcall(love.image.newImageData, 24, 24, "rgba8", data)
      local okG, made = false, nil
      if okI and imgData then okG, made = pcall(love.graphics.newImage, imgData) end
      if okG and made then
        made:setFilter("nearest", "nearest")
        img = made
      end
    end
    a.imgs[n] = img
    return img
  end

  function Gi.draw(G, id, X, Y, k, alpha)
    local n = Gi.number(id)
    if not n then return false end
    local a = find()
    if not a then return false end
    if a.sheet then
      if n < 0 or n >= a.count then return false end
      local q = a.quads[n]
      if not q then
        q = love.graphics.newQuad(0, n * 24, 24, 24, 24, a.h)
        a.quads[n] = q
      end
      G.setColor(1, 1, 1, alpha)
      G.draw(a.sheet, q, X, Y, 0, k, k)
      return true
    end
    local img = fileIcon(a, n)
    if not img then return false end
    G.setColor(1, 1, 1, alpha)
    G.draw(img, X, Y, 0, k, k)
    return true
  end

  return Gi
end
