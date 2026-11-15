-- The Hall of Fame and Oak's PC apps' models on the Game Boy games, the same interfaces as src/hall.lua and
-- src/oak.lua. The Hall: the teams the game recorded (Gen 1: save.hallOfFame, a list oldest first; Gen 2:
-- src/core/gen2/HallOfFame.lua, newest first, up to 30). Oak's PC: the Pokédex's counts (Gen 1 of 151, Gen 2
-- of 251) and Professor Oak's rating in the game's own words. Read only.
--
--   Hl, Ok = hall(host, Gd)

return function(H, Gd)
  local engine = H.engine
  local gen = H.gen
  local Hl, Ok = {}, { TOTAL = gen == 1 and 151 or 251 }

  -- ------- the Hall of Fame

  local function teamsRaw(s)
    if not s then return {} end
    if gen == 2 then
      local HoF = engine("src.core.gen2.HallOfFame")
      local out = {}
      local okN, n = pcall(HoF and HoF.teamCount or error, s)
      for i = 1, (okN and tonumber(n) or 0) do
        local ok, t = pcall(HoF.team, s, i)
        if ok and type(t) == "table" then out[#out + 1] = { number = tonumber(t.winCount) or (n - i + 1), mons = t.mons } end
      end
      return out
    end
    local list = s.hallOfFame
    local out = {}
    if type(list) ~= "table" then return out end
    for i = #list, 1, -1 do out[#out + 1] = { number = i, mons = list[i] } end
    return out
  end

  function Hl.count(s) return #teamsRaw(s) end

  local function member(rec)
    local sp = rec.species
    local nick = tostring(rec.nickname or "")
    local species = Gd.speciesName(sp)
    local def = Gd.def(sp)
    local g = rec.gender == "male" and "M" or (rec.gender == "female" and "F" or nil)
    return {
      species = sp, level = tonumber(rec.level) or 0,
      nickname = nick ~= "" and nick or species, name = species, gender = g, egg = false,
      sameName = nick == "" or (def ~= nil and nick:upper() == tostring(def.name):upper()),
      trainerId = (tonumber(rec.otId) or 0) % 65536,
      picMon = { species = sp, shiny = rec.shiny == true, dvs = rec.dvs },
    }
  end

  function Hl.teams(s)
    local out = {}
    for _, t in ipairs(teamsRaw(s)) do
      local members = {}
      for _, rec in ipairs(t.mons or {}) do
        if type(rec) == "table" and rec.species then members[#members + 1] = member(rec) end
      end
      if #members > 0 then out[#out + 1] = { number = t.number, members = members } end
    end
    return out
  end

  function Hl.stop() end
  function Hl.cry(m)
    if not m or m.egg then return end
    local g = H.game()
    local Sound = engine("src.core.Sound")
    if g and g.data and Sound and Sound.playCry then pcall(Sound.playCry, g.data, m.species) end
  end

  -- ------- Oak's PC

  function Ok.available(s)
    if not s then return false end
    if gen == 2 then
      return type(s.engineFlags) == "table" and s.engineFlags[11] == true
    end
    local f = s.flags or {}
    return f.EVENT_GOT_POKEDEX ~= nil and f.EVENT_GOT_POKEDEX ~= false
  end

  -- (the game's words on one line: its control codes and #MON as the game prints it)
  local function plain(text)
    text = tostring(text or "")
    text = text:gsub("#", "POKé"):gsub("{[^}]*}", ""):gsub("[\n\f\v\r]", " "):gsub("%s+", " ")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
  end

  local function counts(s)
    local dex = s and s.pokedex or {}
    local caughtSet = gen == 2 and (dex.caught or {}) or (dex.owned or {})
    local seen, caught = 0, 0
    for _, v in pairs(dex.seen or {}) do if v then seen = seen + 1 end end
    for _, v in pairs(caughtSet) do if v then caught = caught + 1 end end
    return seen, caught, dex.seen or {}, caughtSet
  end

  local function wordsFor(caught)
    local d = Gd.data()
    if gen == 1 then
      local key
      if caught >= 150 then
        key = "_DexRatingText_Own150To151"
      else
        local lo = math.floor(caught / 10) * 10
        key = ("_DexRatingText_Own%dTo%d"):format(lo, lo + 9)
      end
      return plain(d and d.text and d.text[key] or ""), key
    end
    local Sp, Strings = engine("src.script.gen2.Specials"), engine("src.core.Strings")
    local ok, row = pcall(Sp and Sp.findOakRating or error, caught)
    if not (ok and type(row) == "table") then return "", nil end
    local text = row.text
    if Strings then
      local okS, t = pcall(Strings, row.text)
      if okS and t then text = t end
    end
    return plain(text), row
  end

  function Ok.rating(s)
    local out = { seen = 0, caught = 0, words = "", complete = false, map = {}, toNext = nil, toward = 0 }
    for i = 1, Ok.TOTAL do out.map[i] = 0 end
    local seen, caught, seenSet, caughtSet = counts(s)
    out.seen, out.caught = seen, caught
    local words, mark = wordsFor(caught)
    out.words = words
    for _, sp in ipairs(Gd.species()) do
      local n = Gd.dex(sp)
      if n >= 1 and n <= Ok.TOTAL then
        out.map[n] = caughtSet[sp] and 2 or (seenSet[sp] and 1 or 0)
      end
    end
    -- (how many more to his next words, and how far along to them)
    if caught >= Ok.TOTAL - (gen == 1 and 1 or 0) then
      out.complete = true
    else
      local from = caught
      while from > 0 and select(2, wordsFor(from - 1)) == mark do from = from - 1 end
      local to = caught + 1
      while to <= Ok.TOTAL and select(2, wordsFor(to)) == mark do to = to + 1 end
      if to <= Ok.TOTAL then
        out.toNext = to - caught
        out.toward = (caught - from) / math.max(1, to - from)
      end
    end
    return out
  end

  local pic = nil
  function Ok.picture()
    if pic then return pic end
    -- (the game's own record of it: Gen 1's Prof. Oak trainer, Gen 2's new-game speech)
    local Assets = engine("src.render.Assets")
    local g = H.game()
    local path
    if gen == 1 then
      local tr = g and g.data and g.data.trainers and g.data.trainers.OPP_PROF_OAK
      path = tr and tr.pic
    else
      path = g and g.oakSpeechData and g.oakSpeechData.oakPic
    end
    if not path then return nil end
    local ok, img = pcall(Assets and Assets.image or error, path)
    if ok and img then pic = img end
    return pic or nil
  end

  return Hl, Ok
end
