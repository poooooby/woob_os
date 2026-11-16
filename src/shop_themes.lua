-- The real shops' looks (src/shop.lua's theme): each counter dressed for where it is and what it sells.
-- A Poké Mart is the Mart's own blue and white; a department store's floor takes the colour of what's on
-- its shelves (balls and trainer goods sky blue, medicine mint, battle items orange, TMs violet, gifts and
-- stones pink, decorations pastel), so Celadon, Goldenrod and Lilycove come out right floor by floor
-- whatever each keeps where; a rooftop is sunny, an herb shop leaf green on wood, the pharmacy white and
-- teal, a souvenir shop rustic, the Underground's bargain stall dim neon, the Indigo Plateau navy and gold.
--
--   Th = require-free: Th.pick(where) -> theme, kindKey
--     where = { map (the map's id or label), kind ("mart" | "herb" | "pharmacy" | "bargain" | "decor" |
--               "rooftop"), names = { the goods' names } }
--     theme = { stripe, stripeDeep, stripe2 (the awning's two stripes), light (the lights behind),
--               goods = { the shelves' colours } }
--     kindKey: the word for the shop (lang/*.lua "shop.kind.<key>")
--   Th.floor(map) -> "4F" | "B1F" | "rooftop" | nil

local Th = {}

local function rgb(r, g, b) return { r, g, b } end
local THEMES = {
  mart = { stripe = rgb(56, 136, 250), stripeDeep = rgb(22, 74, 196), stripe2 = rgb(250, 252, 255),
           light = rgb(77, 143, 255), goods = { rgb(255, 104, 104), rgb(72, 206, 150), rgb(255, 168, 60),
                                                 rgb(96, 164, 255), rgb(240, 196, 80), rgb(180, 126, 255) } },
  balls = { stripe = rgb(40, 170, 240), stripeDeep = rgb(16, 110, 190), stripe2 = rgb(236, 248, 255),
            light = rgb(60, 190, 255), goods = { rgb(255, 90, 90), rgb(255, 255, 255), rgb(60, 140, 255),
                                                  rgb(255, 210, 60) } },
  medicine = { stripe = rgb(40, 196, 150), stripeDeep = rgb(16, 140, 104), stripe2 = rgb(240, 255, 250),
               light = rgb(90, 220, 170), goods = { rgb(150, 110, 230), rgb(255, 120, 160), rgb(80, 200, 255),
                                                    rgb(255, 220, 90) } },
  battle = { stripe = rgb(255, 128, 40), stripeDeep = rgb(210, 80, 16), stripe2 = rgb(255, 248, 236),
             light = rgb(255, 150, 70), goods = { rgb(255, 90, 60), rgb(255, 200, 60), rgb(120, 120, 255),
                                                  rgb(90, 200, 120) } },
  tm = { stripe = rgb(150, 96, 236), stripeDeep = rgb(100, 52, 190), stripe2 = rgb(246, 240, 255),
         light = rgb(160, 120, 255), goods = { rgb(255, 160, 60), rgb(90, 160, 255), rgb(255, 90, 140),
                                               rgb(120, 220, 140) } },
  gifts = { stripe = rgb(255, 104, 170), stripeDeep = rgb(214, 54, 124), stripe2 = rgb(255, 244, 250),
            light = rgb(255, 130, 190), goods = { rgb(255, 210, 90), rgb(130, 200, 255), rgb(170, 120, 255),
                                                  rgb(255, 150, 120) } },
  decor = { stripe = rgb(150, 190, 255), stripeDeep = rgb(110, 140, 220), stripe2 = rgb(255, 236, 246),
            light = rgb(200, 170, 255), goods = { rgb(255, 190, 210), rgb(190, 230, 200), rgb(200, 200, 255),
                                                  rgb(255, 226, 170) } },
  rooftop = { stripe = rgb(255, 196, 40), stripeDeep = rgb(230, 140, 20), stripe2 = rgb(255, 255, 255),
              light = rgb(110, 200, 255), goods = { rgb(255, 120, 120), rgb(120, 200, 255), rgb(255, 220, 100),
                                                    rgb(140, 230, 160) } },
  herb = { stripe = rgb(96, 170, 70), stripeDeep = rgb(60, 120, 40), stripe2 = rgb(214, 180, 130),
           light = rgb(140, 200, 100), goods = { rgb(120, 180, 80), rgb(190, 150, 90), rgb(230, 210, 140),
                                                 rgb(90, 140, 60) } },
  pharmacy = { stripe = rgb(30, 170, 170), stripeDeep = rgb(10, 120, 124), stripe2 = rgb(255, 255, 255),
               light = rgb(120, 220, 220), goods = { rgb(255, 255, 255), rgb(255, 110, 110), rgb(80, 200, 200),
                                                     rgb(200, 230, 240) } },
  souvenir = { stripe = rgb(176, 112, 60), stripeDeep = rgb(120, 70, 30), stripe2 = rgb(246, 226, 190),
               light = rgb(220, 160, 100), goods = { rgb(200, 140, 80), rgb(150, 190, 120), rgb(230, 200, 140),
                                                     rgb(180, 110, 90) } },
  neon = { stripe = rgb(236, 60, 200), stripeDeep = rgb(150, 20, 140), stripe2 = rgb(40, 34, 80),
           light = rgb(140, 70, 255), goods = { rgb(255, 80, 220), rgb(60, 230, 255), rgb(255, 230, 60),
                                                rgb(120, 255, 140) } },
  league = { stripe = rgb(30, 50, 120), stripeDeep = rgb(14, 26, 74), stripe2 = rgb(250, 214, 110),
             light = rgb(90, 110, 220), goods = { rgb(255, 210, 90), rgb(255, 255, 255), rgb(120, 150, 255),
                                                  rgb(220, 90, 90) } },
}
Th.THEMES = THEMES

-- the floor in a map's id or label: "..._4F", "...4F", "..._B1F", "..._ROOFTOP"
function Th.floor(map)
  map = tostring(map or ""):upper()
  if map:find("ROOF", 1, true) then return "rooftop" end
  local b = map:match("B(%d)F$")
  if b then return "B" .. b .. "F" end
  local f = map:match("(%d+)F$")
  if f then return f .. "F" end
  return nil
end

-- (what a shelf mostly holds, by the goods' names)
local CATS = {
  { "tm", { "^TM", "^HM", "TECHNICAL" } },
  { "medicine", { "POTION", "HEAL", "REVIVE", "ANTIDOTE", "ETHER", "ELIXIR", "AWAKENING", "PARLYZ", "PARALYZ",
                  "RESTORE", "BURN", "ICE HEAL", "FULL", "FRESH WATER", "SODA", "LEMONADE", "MOOMOO" } },
  { "battle", { "^X ", "^X_", "GUARD SPEC", "DIRE HIT", "PROTEIN", "IRON", "CALCIUM", "ZINC", "CARBOS", "HP UP",
                "PP UP" } },
  { "balls", { "BALL", "REPEL", "ESCAPE ROPE", "POKé DOLL" } },
  { "gifts", { "STONE", "DOLL", "MAIL", "CUSHION", "POSTER", "FLUTE", "CARD" } },
}
local function categoryOf(names)
  local count = {}
  for _, n in ipairs(names or {}) do
    local up = tostring(n):upper()
    for _, c in ipairs(CATS) do
      local hit = false
      for _, pat in ipairs(c[2]) do if up:find(pat) then hit = true break end end
      if hit then
        count[c[1]] = (count[c[1]] or 0) + 1
        break
      end
    end
  end
  local best, n = nil, 0
  for k, v in pairs(count) do if v > n or (v == n and k < (best or "~")) then best, n = k, v end end
  return best
end

function Th.pick(where)
  where = where or {}
  local map = tostring(where.map or ""):upper()
  local kind = where.kind or "mart"
  -- (the kind of counter first: the Underground has the herb shop and the bargain stall both)
  if kind == "decor" then return THEMES.decor, "decor" end
  if kind == "bargain" then return THEMES.neon, "bargain" end
  if kind == "herb" then return THEMES.herb, "herb" end
  if kind == "pharmacy" then return THEMES.pharmacy, "pharmacy" end
  if kind == "rooftop" then return THEMES.rooftop, "rooftop" end
  if map:find("HERB", 1, true) then return THEMES.herb, "herb" end
  if map:find("PHARMACY", 1, true) then return THEMES.pharmacy, "pharmacy" end
  if map:find("ROOF", 1, true) then return THEMES.rooftop, "rooftop" end
  if map:find("UNDERGROUND", 1, true) then return THEMES.neon, "bargain" end
  if map:find("SOUVENIR", 1, true) or map:find("GIFT_SHOP", 1, true) or map:find("MAHOGANY_MART", 1, true) or
     map:find("MT_MOON", 1, true) or map:find("MOUNT_MOON", 1, true) or map:find("MTMOON", 1, true) then
    return THEMES.souvenir, "souvenir"
  end
  if map:find("INDIGO", 1, true) or map:find("POKEMON_LEAGUE", 1, true) then return THEMES.league, "league" end
  local store = map:find("DEPT", 1, true) or map:find("DEPARTMENT", 1, true) or map:find("CELADONMART", 1, true)
    or map:find("CELADON_MART", 1, true)
  if store then
    local cat = categoryOf(where.names)
    return THEMES[cat or "balls"] or THEMES.balls, "dept"
  end
  return THEMES.mart, "mart"
end

return Th
