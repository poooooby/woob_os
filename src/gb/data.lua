-- The Game Boy games' facts for the models (src/gb/*.lua), the same answers on Gen 1 (Red / Blue / Yellow)
-- and Gen 2 (Gold / Silver / Crystal): the game's data (string ids: species "PIKACHU", items "POTION", moves
-- "THUNDERSHOCK"), a Pokémon's name, level, HP, types, gender, shininess, the money, the Badges.
--
--   Gd = data(host)           host: src/gb/host.lua (H.gen, H.game(), H.engine)
--   Gd.gen ; Gd.data() ; Gd.def(sp) ; Gd.dex(sp) ; Gd.speciesName(sp) (title case) ; Gd.monName(mon)
--   Gd.level(mon) ; Gd.hp(mon) / Gd.maxHp(mon) ; Gd.isEgg(mon) ; Gd.shiny(mon) ; Gd.gender(mon) -> "M" | "F" | nil
--   Gd.typesOf(sp) -> { { id (the Gen 3 number the windows colour by), name }, ... }
--   Gd.typeId(gbType) ; Gd.typeName(gbType) ; Gd.moveName(id) ; Gd.itemName(id) ; Gd.item(id)
--   Gd.money(s) / Gd.setMoney(s, n) (0 .. 999999) ; Gd.addMoney(s, n) -> what went in ; Gd.badges(s) -> count
--   Gd.species() -> the species ids in National Dex order (kept) ; Gd.title(text)

return function(H)
  local Gd = { gen = H.gen, MAX_MONEY = 999999 }
  local engine = H.engine
  local floor, max, min = math.floor, math.max, math.min

  function Gd.data()
    local g = H.game()
    return g and g.data or nil
  end
  function Gd.def(sp)
    local d = Gd.data()
    local p = d and d.pokemon
    local def = p and sp and p[sp]
    return type(def) == "table" and def.baseStats and def or nil
  end
  function Gd.dex(sp)
    local def = Gd.def(sp)
    return def and tonumber(def.dex) or 0
  end

  -- "MR.MIME" -> "Mr.Mime", "NIDORAN_M" handled by the game's own name
  local titled = {}
  function Gd.title(text)
    text = tostring(text or "")
    local got = titled[text]
    if got then return got end
    got = text:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end)
    got = got:gsub("é", "é")
    titled[text] = got
    return got
  end
  function Gd.speciesName(sp)
    local def = Gd.def(sp)
    local name = def and def.name or tostring(sp or "?")
    return Gd.title(name)
  end
  function Gd.monName(mon)
    if type(mon) ~= "table" then return "?" end
    if Gd.isEgg(mon) then return "Egg" end
    local nick = mon.nickname
    if type(nick) == "string" and nick ~= "" then
      local def = Gd.def(mon.species)
      -- (a nickname that's only the species' own name, as the game stores it: titled like it)
      if def and nick == def.name then return Gd.speciesName(mon.species) end
      return nick
    end
    return Gd.speciesName(mon.species)
  end
  function Gd.level(mon) return tonumber(mon and mon.level) or 1 end
  function Gd.hp(mon) return tonumber(mon and mon.hp) or 0 end
  function Gd.maxHp(mon)
    if type(mon) ~= "table" then return 0 end
    local m = tonumber(mon.maxHp)
    if m then return m end
    return tonumber(mon.stats and mon.stats.hp) or 0
  end
  function Gd.isEgg(mon) return type(mon) == "table" and (mon.isEgg == true or mon.egg == true) end
  function Gd.shiny(mon)
    if Gd.gen == 1 or type(mon) ~= "table" or Gd.isEgg(mon) then return false end
    if mon.isShiny ~= nil then return mon.isShiny == true end
    if mon.shiny ~= nil then return mon.shiny == true end
    local Mon = engine("src.battle.gen2.Mon")
    if Mon and Mon.vanillaShiny and type(mon.dvs) == "table" then
      local ok, yes = pcall(Mon.vanillaShiny, mon.dvs)
      return ok and yes == true
    end
    return false
  end
  function Gd.gender(mon)
    if Gd.gen == 1 or type(mon) ~= "table" or Gd.isEgg(mon) then return nil end
    if mon.gender == "male" then return "M" end
    if mon.gender == "female" then return "F" end
    return nil
  end

  -- ------- types: the Game Boy names, as the Gen 3 numbers the windows colour their pills by
  local TYPE_ID = {
    NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4, ROCK = 5, BUG = 6, GHOST = 7, STEEL = 8,
    FIRE = 10, WATER = 11, GRASS = 12, ELECTRIC = 13, PSYCHIC = 14, PSYCHIC_TYPE = 14, ICE = 15, DRAGON = 16,
    DARK = 17, BIRD = 2, CURSE_TYPE = 9, CURSE = 9,
  }
  function Gd.typeId(t)
    t = tostring(t or "")
    return TYPE_ID[t] or TYPE_ID[t:gsub("_TYPE$", "")] or 0
  end
  local typeNames = {}
  function Gd.typeName(t)
    t = tostring(t or "")
    local got = typeNames[t]
    if got then return got end
    local d = Gd.data()
    local raw
    if Gd.gen == 2 then
      raw = d and d.type_chart and d.type_chart.names and d.type_chart.names[t]
    else
      local TC = engine("src.battle.TypeChart")
      local ok, n = pcall(TC and TC.displayName or error, t, d)
      raw = ok and n or nil
    end
    got = Gd.title(raw or t:gsub("_TYPE$", ""))
    typeNames[t] = got
    return got
  end
  local typesOf = {}
  function Gd.typesOf(sp)
    local got = typesOf[sp]
    if got then return got end
    got = {}
    local def = Gd.def(sp)
    local ts = def and def.types or {}
    for i = 1, 2 do
      local t = ts[i]
      if t and (i == 1 or t ~= ts[1]) then got[#got + 1] = { id = Gd.typeId(t), name = Gd.typeName(t), gb = t } end
    end
    typesOf[sp] = got
    return got
  end

  function Gd.moveName(id)
    local d = Gd.data()
    local m = d and d.moves and d.moves[id]
    return Gd.title(m and m.name or tostring(id or "?"):gsub("_", " "))
  end
  function Gd.item(id)
    local d = Gd.data()
    return d and d.items and d.items[id] or nil
  end
  -- an item's words on one line (the game's breaks, and the hyphens it broke words with, taken out)
  function Gd.itemDesc(id)
    local it = Gd.item(id)
    local d = tostring(it and it.description or "")
    d = d:gsub("%-%s*<NEXT>%s*", ""):gsub("%-\n", ""):gsub("<NEXT>", " "):gsub("[\n\f]", " "):gsub("%s+", " ")
    return (d:gsub("^%s+", ""):gsub("%s+$", ""))
  end
  function Gd.itemName(id)
    local it = Gd.item(id)
    local name = it and it.name or tostring(id or "?"):gsub("_", " ")
    -- (TMs and HMs keep their numbers as the game writes them)
    if name:match("^[TH]M%d") then return name end
    return Gd.title(name)
  end

  -- ------- money and Badges
  local function wallet(s)
    if not s then return nil end
    if Gd.gen == 2 then return s.player end
    return s
  end
  function Gd.money(s)
    local w = wallet(s)
    return w and tonumber(w.money) or 0
  end
  function Gd.setMoney(s, n)
    local w = wallet(s)
    if w then w.money = max(0, min(Gd.MAX_MONEY, floor(tonumber(n) or 0))) end
  end
  function Gd.addMoney(s, n)
    local before = Gd.money(s)
    Gd.setMoney(s, before + n)
    return Gd.money(s) - before
  end
  function Gd.badges(s)
    if not s then return 0 end
    local n = 0
    if Gd.gen == 2 then
      local p = s.player or {}
      for _, set in ipairs({ p.badges or {}, p.kantoBadges or {} }) do
        for _, v in pairs(set) do if v then n = n + 1 end end
      end
      return n
    end
    for id, v in pairs(s.inventory or {}) do
      if type(id) == "string" and id:find("BADGE", 1, true) and (tonumber(v) or 0) > 0 then n = n + 1 end
    end
    return n
  end

  -- every species, National Dex order (made once per data)
  local list, listFor = nil, nil
  function Gd.species()
    local d = Gd.data()
    if list and listFor == d then return list end
    list, listFor = {}, d
    for id, def in pairs(d and d.pokemon or {}) do
      if type(def) == "table" and def.baseStats and tonumber(def.dex) then list[#list + 1] = id end
    end
    table.sort(list, function(a, b) return Gd.dex(a) < Gd.dex(b) end)
    return list
  end

  return Gd
end
