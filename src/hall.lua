-- The Hall of Fame app's model: the teams the game recorded (session.hallOfFameTeams, oldest first, up
-- to 50), newest first, numbered as the game's own PC numbers them. Read only.
--
--   Hl = Hall(engine)
--   Hl.teams(s) -> { { number, members = { { species, level, nickname, name, sameName (no nickname),
--                      gender ("M" | "F" | nil), trainerId, egg, picMon } } } }
--   Hl.count(s) ; Hl.cry(member) ; Hl.stop()

local max = math.max
local STAT_ENTERED = 10    -- GAME_STAT_ENTERED_HOF
local SPECIES_EGG = 412

return function(engine)
  local Hl = {}
  local function Pokemon() return engine("src.core.game3.pokemon") end

  function Hl.count(s)
    local list = s and s.hallOfFameTeams
    return type(list) == "table" and #list or 0
  end

  local function member(rec)
    local P = Pokemon()
    local sp = tonumber(rec.species) or 0
    local p = tonumber(rec.personality) or 0
    local egg = sp == SPECIES_EGG
    local okN, name = pcall(P.name, sp)
    local nick = tostring(rec.nickname or "")
    local species = okN and tostring(name or "") or ""
    local gender
    if not egg then
      local okG, g = pcall(P.gender, sp, p)
      if okG and (g == "M" or g == "F") then gender = g end
    end
    return {
      species = sp, level = tonumber(rec.level) or 0, nickname = nick,
      name = species, gender = gender, egg = egg, sameName = egg or nick:upper() == species:upper(),
      trainerId = (tonumber(rec.trainerId) or 0) % 65536,
      -- (its picture: shiny by its own numbers, as it was when it got here)
      picMon = { species = sp, level = rec.level, personality = p, otId = tonumber(rec.trainerId) or 0,
                 otSecretId = tonumber(rec.otSecretId) or 0 },
    }
  end

  function Hl.teams(s)
    local list, out = s and s.hallOfFameTeams, {}
    if type(list) ~= "table" then return out end
    local newest = tonumber(s.gameStats and s.gameStats[STAT_ENTERED]) or #list
    for i = #list, 1, -1 do
      local members = {}
      for k = 1, 6 do
        local rec = list[i][k]
        if rec and (tonumber(rec.species) or 0) ~= 0 then members[#members + 1] = member(rec) end
      end
      if #members > 0 then out[#out + 1] = { number = max(0, newest - (#list - i)), members = members } end
    end
    return out
  end

  function Hl.stop()
    local Audio = engine("src.core.game3.audio")
    if Audio and Audio.stopCry then pcall(Audio.stopCry) end
  end
  function Hl.cry(m)
    if not m or m.egg then return end
    local Audio = engine("src.core.game3.audio")
    if not (Audio and Audio.playCry) then return end
    Hl.stop()
    pcall(Audio.playCry, m.species)
  end
  return Hl
end
