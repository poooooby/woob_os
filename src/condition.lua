-- The Condition app's model: the five contest conditions (Cool, Beauty, Cute, Smart, Tough) and
-- the sheen of the party's Pokémon, or of every Pokémon in the party and the boxes ranked by one
-- condition (the PokéNav's search); the Pokéblock case, and feeding a block with the game's own
-- rules (its flavours by the Pokémon's nature, the sheen that ends it at 255).
--
--   Cd = Condition(engine, deps)   deps: bx (src/boxes.lua)
--   Cd.KEYS = { "cool", "beauty", "cute", "smart", "tough" }
--   Cd.available(s) ; Cd.party(s) / Cd.search(s, cat 1..5) -> rows { mon, where, conds, sheen, sparkles }
--   Cd.blocks(s) -> { slot, block, name, flavors, feel } ; Cd.feed(s, slot, mon) -> true, result | false, why ;
--   Cd.ribbons(mon) -> its count
--   ("full": its sheen is full; "none": no such block)

local floor, max, min = math.floor, math.max, math.min

local KEYS = { "cool", "beauty", "cute", "smart", "tough" }
local MAX_SHEEN = 255

return function(engine, deps)
  deps = deps or {}
  local Cd = { KEYS = KEYS, MAX_SHEEN = MAX_SHEEN }
  local Bx = deps.bx

  local function num(v) return floor(tonumber(v) or 0) end
  local function isEgg(mon) return mon and (mon.isEgg or mon.egg) and true or false end

  function Cd.available(s)
    local Profile = engine("src.core.game3.profile")
    local ok, P = pcall(Profile and Profile.forSession or error, nil)
    if not (ok and type(P) == "table" and P.family == "rse") then return false end
    local Flags, Space, Constants = engine("src.core.game3.scripting.flags"), engine("src.core.game3.scripting.space"),
      engine("src.core.game3.constants")
    local okI, id = pcall(function() return Constants.of(P.id):flag("FLAG_SYS_POKENAV_GET") end)
    if not (okI and id) then return false end
    if Flags and Space and Space.store then
      local okF, v = pcall(Flags.getFlag, Space.store, nil, id)
      if okF and v == true then return true end
    end
    local f = s and s.flags
    return f ~= nil and (f[id] == true or f[id] == 1)
  end

  -- a Pokémon's conditions, read (never written: the game's own reader makes the table)
  local function row(mon, where)
    local c = type(mon.contest) == "table" and mon.contest or {}
    local r = { mon = mon, where = where, conds = {}, sheen = num(c.sheen) % 256 }
    for i, k in ipairs(KEYS) do r.conds[i] = num(c[k]) % 256 end
    local Pb = engine("src.core.game3.rse.pokeblock")
    local ok, sp = pcall(Pb and Pb.sparkles or error, r.sheen)
    r.sparkles = ok and tonumber(sp) or floor(r.sheen / 29)
    return r
  end
  Cd.row = row

  function Cd.party(s)
    local out = {}
    local party = Bx and Bx.party(s) or (s and s.party) or {}
    for i = 1, #party do
      local m = party[i]
      if m and not isEgg(m) then out[#out + 1] = row(m, 0) end
    end
    return out
  end

  -- every Pokémon, the party's and the boxes', best first in that condition
  function Cd.search(s, cat)
    cat = max(1, min(5, tonumber(cat) or 1))
    local out = Cd.party(s)
    if Bx then
      for b = 1, Bx.boxCount() do
        local mons = Bx.boxMons(s, b) or {}
        for slot = 1, Bx.SLOTS or 30 do
          local m = mons[slot]
          if m and not isEgg(m) then out[#out + 1] = row(m, b) end
        end
      end
    end
    for i, r in ipairs(out) do r.order = i end
    table.sort(out, function(a, b)
      if a.conds[cat] ~= b.conds[cat] then return a.conds[cat] > b.conds[cat] end
      return a.order < b.order
    end)
    return out
  end

  -- how many ribbons it wears
  function Cd.ribbons(mon)
    local Ribbons = engine("src.core.game3.rse.ribbons")
    local ok, n = pcall(Ribbons and Ribbons.count or error, mon)
    return ok and tonumber(n) or 0
  end

  -- the case's blocks
  function Cd.blocks(s)
    local Pb = engine("src.core.game3.rse.pokeblock")
    if not (Pb and s) then return {} end
    local ok, list = pcall(Pb.slots, s)
    if not ok or type(list) ~= "table" then return {} end
    local out = {}
    for i = 1, #list do
      local b = list[i]
      if b and num(b.color) ~= 0 then
        local okN, name = pcall(Pb.name, b)
        local nm = okN and tostring(name) or "?"
        nm = nm:gsub("(%a)([%w'é]*)", function(a, rest) return a:upper() .. rest:lower() end)
        out[#out + 1] = { slot = i - 1, block = b, name = nm,
                          flavors = { num(b.spicy), num(b.dry), num(b.sweet), num(b.bitter), num(b.sour) },
                          feel = num(b.feel), color = num(b.color) }
      end
    end
    return out
  end

  -- a block fed as the Pokéblock case feeds it: refused at full sheen; the block used up
  function Cd.feed(s, slot, mon)
    local Pb = engine("src.core.game3.rse.pokeblock")
    if not (Pb and s and mon) then return false, "none" end
    local block = Pb.get(s, slot)
    if not block or num(block.color) == 0 then return false, "none" end
    if num(type(mon.contest) == "table" and mon.contest.sheen) >= MAX_SHEEN then return false, "full" end
    local ok, res = pcall(Pb.feed, block, mon)
    if not ok then return false, "none" end
    pcall(Pb.tryClear, s, slot)
    return true, res
  end

  return Cd
end
