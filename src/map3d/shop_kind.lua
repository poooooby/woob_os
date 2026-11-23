-- What a shop sells, in a word: a stock's item names -> a category's word key (the map's objectives name a
-- department store's floor, a market stall by it). Every game's names alike: Gen 3's constants (ITEM_X_ATTACK) and
-- the Game Boy games' names (X ATTACK, POKé BALL) both come down to their letters and digits (XATTACK, POKBALL).
--
--   Sk = ShopKind()
--   Sk.norm(name) -> its letters and digits, upper case, ITEM_ gone
--   Sk.of(names) -> "map.obj.cat.<kind>" or nil (no names): tm | vitamins | battle | stones | medicine | balls | mail |
--                   trainer
--   Sk.DECO -> the decorations' key (Gen 3's decoration marts)

local BATTLE = {}
for _, n in ipairs({ "XATTACK", "XDEFEND", "XDEFENSE", "XSPEED", "XSPECIAL", "XSPATK", "XSPDEF", "XACCURACY",
                     "GUARDSPEC", "DIREHIT", "HPUP", "PROTEIN", "IRON", "CARBOS", "CALCIUM", "ZINC", "PPUP", "PPMAX" }) do
  BATTLE[n] = true
end
-- (the vitamins: a stock of them alone -- and candies -- is Vitamins, not Battle Items)
local VITAMIN = { HPUP = true, PROTEIN = true, IRON = true, CARBOS = true, CALCIUM = true, ZINC = true }
local MEDICINE = {}
for _, n in ipairs({ "POTION", "SUPERPOTION", "HYPERPOTION", "MAXPOTION", "FULLRESTORE", "REVIVE", "MAXREVIVE",
                     "ANTIDOTE", "PARALYZEHEAL", "PARLYZHEAL", "AWAKENING", "BURNHEAL", "ICEHEAL", "FULLHEAL", "ETHER",
                     "MAXETHER", "ELIXIR", "ELIXER", "MAXELIXIR", "MAXELIXER", "FRESHWATER", "SODAPOP", "LEMONADE",
                     "MOOMOOMILK", "ENERGYPOWDER", "ENERGYROOT", "HEALPOWDER", "REVIVALHERB", "LAVACOOKIE",
                     "BERRYJUICE", "RAGECANDYBAR", "OLDGATEAU" }) do
  MEDICINE[n] = true
end

return function()
  local Sk = { DECO = "map.obj.cat.deco" }

  function Sk.norm(name)
    local s = tostring(name or ""):upper():gsub("^ITEM_", "")
    -- (é and the other marks: dropped with everything that isn't a letter or a digit)
    return (s:gsub("[^%w]", ""))
  end

  -- (a TM by its number, Gen 3's TM01_FOCUS_PUNCH, or by its move, the Game Boy games' TM_SUNNY_DAY)
  local function kindOf(raw)
    local up = tostring(raw or ""):upper():gsub("^ITEM_", "")
    if up:find("^[TH]M[%d_ ]") then return "tm" end
    local n = Sk.norm(raw)
    -- (and what raises a level, Rare Candies and Exp. Candies, sold beside them)
    if VITAMIN[n] or n == "RARECANDY" or n:find("^EXPCANDY") then return "vitamins" end
    if BATTLE[n] then return "battle" end
    if n:find("STONE$") then return "stones" end
    if MEDICINE[n] then return "medicine" end
    if n:find("BALL$") then return "balls" end
    if n:find("MAIL$") then return "mail" end
    return "other"
  end

  function Sk.of(names)
    local count, total = {}, 0
    for _, name in ipairs(names or {}) do
      local k = kindOf(name)
      count[k] = (count[k] or 0) + 1
      total = total + 1
    end
    if total == 0 then return nil end
    local function share(k) return (count[k] or 0) / total end
    local kind
    if share("tm") == 1 then kind = "tm"
    elseif share("vitamins") == 1 then kind = "vitamins"
    elseif share("battle") + share("vitamins") >= 0.5 then kind = "battle"
    elseif share("stones") >= 0.5 then kind = "stones"
    elseif share("medicine") == 1 then kind = "medicine"
    elseif share("balls") == 1 then kind = "balls"
    elseif share("mail") == 1 then kind = "mail"
    else kind = "trainer" end
    return "map.obj.cat." .. kind
  end

  return Sk
end
