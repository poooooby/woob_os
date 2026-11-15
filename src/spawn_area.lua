-- WoobleSpawns (modern_spawns): where its tables put a species, for the Pokédex's Where tab. While it's on,
-- the wild Pokémon walking in grass, surfing and (where it makes them) biting a Good or Super Rod are its
-- own, not the cart's, so those rows come from here; the rest (the Old Rod, Rock Smash) stay the cart's.
-- Read only, through its public exports (api 2): locate (every map and kind a species can be met on),
-- tableFor (each slot's species and levels), poolFor (COMPLETE: what each slot can turn into, each equally
-- likely), settings (TIME OF DAY SPAWNS).
--
--   Sa = SpawnArea({ spawns = fn -> exports | nil, gen = 1 | 2 | 3 })
--   Sa.active() -> the exports while it's on, else nil (read when a page is made, never per frame)
--   Sa.rows(id) -> { { mapId, method, lo, hi, chance (0..100), rare?, when? ("day" | "night") } } | nil
--                  (nil: it's off; `id` its species id, "PIKACHU"; `rare`: a legendary's home, met
--                  1 in 1024 or so; `when`: only then, with TIME OF DAY SPAWNS on)
--   Sa.replaces(method) -> true for a method whose cart rows its own stand in for

local floor, max, min = math.floor, math.max, math.min

-- (each slot's share of its table, percent, as each game rolls them)
local G3_LAND = { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }
local G3_WATER = { 60, 30, 5, 4, 1 }
local G3_GOOD = { 60, 20, 20 }
local G3_SUPER = { 40, 40, 15, 4, 1 }
local G1_LAND = { 20, 20, 15, 10, 10, 10, 5, 5, 4, 1 }
local G2_LAND = { 30, 30, 20, 10, 5, 4, 1 }
local G2_WATER = { 60, 30, 10 }
local G2_TIMES = { "MORN", "DAY", "NITE" }

-- (its table kinds -> the Where tab's methods; a legendary's home is "grass" / "water" on every game)
local METHOD = {
  [1] = { grass = "grass", water = "surf", superRod = "super" },
  [2] = { grass = "grass", water = "surf", ["fish.good"] = "good", ["fish.super"] = "super" },
  [3] = { land = "grass", grass = "grass", water = "surf", ["fish.good"] = "good", ["fish.super"] = "super" },
}
local WEIGHTS = {
  [1] = { grass = G1_LAND, water = G1_LAND },
  [3] = { land = G3_LAND, grass = G3_LAND, water = G3_WATER, ["fish.good"] = G3_GOOD, ["fish.super"] = G3_SUPER },
}
-- (the cart's rows its own replace: what it generates; Gen 1 and 2 show no other fishing)
local REPLACES = {
  [1] = { grass = true, surf = true, super = true },
  [2] = { grass = true, surf = true, good = true, super = true },
  [3] = { grass = true, surf = true, good = true, super = true },
}

return function(deps)
  local gen = deps.gen or 3
  -- (Sa.spawns: its exports, looked up; the tests swap it)
  local Sa = { spawns = deps.spawns }

  function Sa.active()
    local ex = Sa.spawns and Sa.spawns()
    if type(ex) ~= "table" or type(ex.locate) ~= "function" or type(ex.tableFor) ~= "function" then return nil end
    local ok, on = pcall(ex.isActive or error)
    return ok and on == true and ex or nil
  end

  function Sa.replaces(method) return REPLACES[gen][method] == true end

  local function has(list, id)
    for _, v in ipairs(list) do
      if v == id then return true end
    end
    return false
  end
  local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, got = pcall(fn, ...)
    return ok and got or nil
  end

  -- the share of one table (and its pools) that is `id`, percent, and its levels; nil when no slot is
  local function matchSlots(slots, weights, pools, id, poolBase)
    local chance, lo, hi = 0, nil, nil
    local allLo, allHi
    for i, s in ipairs(slots) do
      local l = tonumber(s.minLevel or s.level) or 0
      local h = tonumber(s.maxLevel or s.level or s.minLevel) or l
      allLo, allHi = min(allLo or l, l), max(allHi or h, h)
      local w = weights and weights[i] or 0
      local pool = pools and pools[(poolBase or 0) + i]
      local share = 0
      if type(pool) == "table" and #pool > 0 then
        if has(pool, id) then share = w / #pool end
      elseif s.species == id then
        share = w
      end
      if share > 0 then
        chance = chance + share
        lo, hi = min(lo or l, l), max(hi or h, h)
      end
    end
    return chance, lo, hi, allLo, allHi
  end

  -- one map's kind at one period -> chance, lo, hi (chance 0: it isn't in the table: a legendary's home),
  -- the table's own level range for that case
  local function oneKind(ex, mapId, kind, period, id)
    local t = call(ex.tableFor, mapId, kind, period)
    if type(t) ~= "table" then return nil end
    local pools = call(ex.poolFor, mapId, kind, period)
    if gen == 2 and kind == "grass" then
      -- (seven slots for each of the morning, the day and the night, the pools 1-7, 8-14, 15-21: the best
      -- of the three)
      local best, lo, hi, aLo, aHi = 0, nil, nil, nil, nil
      for k, time in ipairs(G2_TIMES) do
        local slots = type(t.slots) == "table" and t.slots[time]
        if type(slots) == "table" then
          local c, l, h, al, ah = matchSlots(slots, G2_LAND, pools, id, (k - 1) * 7)
          if c > best then best, lo, hi = c, l, h end
          aLo, aHi = min(aLo or al or 0, al or 0), max(aHi or ah or 0, ah or 0)
        end
      end
      return best, lo or aLo, hi or aHi
    end
    if gen == 2 and (kind == "fish.good" or kind == "fish.super") then
      -- (rows of a cumulative chance out of 255)
      local chance, lo, hi, prev = 0, nil, nil, 0
      local aLo, aHi
      for _, r in ipairs(t) do
        local c = tonumber(r.chance) or prev
        local l = tonumber(r.level) or 0
        aLo, aHi = min(aLo or l, l), max(aHi or l, l)
        if r.species == id then
          chance = chance + max(0, c - prev) * 100 / 256
          lo, hi = min(lo or l, l), max(hi or l, l)
        end
        prev = c
      end
      return chance, lo or aLo, hi or aHi
    end
    if gen == 1 and kind == "superRod" then
      -- (a bare list, each as likely)
      local list = t.slots or t
      local n, hit, lo, hi, aLo, aHi = #list, 0, nil, nil, nil, nil
      for _, r in ipairs(list) do
        local l = tonumber(r.level) or 0
        aLo, aHi = min(aLo or l, l), max(aHi or l, l)
        if r.species == id then
          hit = hit + 1
          lo, hi = min(lo or l, l), max(hi or l, l)
        end
      end
      return n > 0 and hit * 100 / n or 0, lo or aLo, hi or aHi
    end
    local slots = type(t.slots) == "table" and t.slots or nil
    if not slots then return nil end
    local weights = WEIGHTS[gen] and WEIGHTS[gen][kind] or G2_WATER
    local c, l, h, al, ah = matchSlots(slots, weights, pools, id, 0)
    return c, l or al, h or ah
  end

  function Sa.rows(id)
    local ex = Sa.active()
    if not ex or id == nil then return nil end
    local maps = call(ex.locate, id)
    if type(maps) ~= "table" then return nil end
    -- (TIME OF DAY SPAWNS: a roster each for the day and the night; off, the one)
    local settings = call(ex.settings)
    local tod = type(settings) == "table" and settings.timeOfDay
    local periods = (tod and tod ~= "off" and tod ~= false) and { "day", "night" } or { false }
    local out, byKey = {}, {}
    for mapId, kinds in pairs(maps) do
      for kind in pairs(type(kinds) == "table" and kinds or {}) do
        local method = METHOD[gen][kind]
        if method then
          local key = tostring(mapId) .. "|" .. method
          for _, period in ipairs(periods) do
            local chance, lo, hi = oneKind(ex, mapId, kind, period or nil, id)
            if chance then
              local r = byKey[key]
              if not r then
                r = { mapId = mapId, method = method, lo = lo or 0, hi = hi or lo or 0, chance = 0, seenIn = {} }
                byKey[key] = r
                out[#out + 1] = r
              end
              if chance > 0 then
                r.chance = max(r.chance, chance)
                if lo then r.lo, r.hi = min(r.lo, lo), max(r.hi, hi or lo) end
                if period then r.seenIn[period] = true end
              end
            end
          end
        end
      end
    end
    for _, r in ipairs(out) do
      if r.chance <= 0 then r.rare = true end
      if periods[1] and not r.rare then
        if r.seenIn.day and not r.seenIn.night then r.when = "day"
        elseif r.seenIn.night and not r.seenIn.day then r.when = "night" end
      end
      r.seenIn = nil
    end
    return out
  end

  -- (a chance as the tab shows it: whole percent, "<1%" under one)
  function Sa.chanceText(chance)
    if chance > 0 and chance < 1 then return "<1%" end
    return ("%d%%"):format(min(100, floor(chance + 0.5)))
  end

  return Sa
end
