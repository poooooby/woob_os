-- The Oak's PC app's model (FireRed / LeafGreen): the Kanto Pokédex's counts and Professor Oak's rating
-- of them, in the game's own words (the same choice the PC's script makes). Read only.
--
--   Ok = Oak(engine)   Ok.available(s) -> the Pokédex is got ; Ok.TOTAL
--   Ok.rating(s) -> { seen, caught, words, complete, map (1..151: 2 caught, 1 seen, 0 neither),
--                     toNext (how many to his next rating) | nil, toward (0..1 of the way there) }
--   Ok.picture() -> Professor Oak's picture | nil

local TRAINER_PIC_OAK = 132      -- FireRed / LeafGreen's TRAINER_PIC_PROFESSOR_OAK
local STEP = 10                  -- his ratings change every ten caught, up to 150

return function(engine)
  local Ok = { TOTAL = 151 }

  local function dexOf(s) return s and (s.dex or s.pokedex) or nil end

  function Ok.available(s)
    local Profile, Constants = engine("src.core.game3.profile"), engine("src.core.game3.constants")
    local Flags, Space = engine("src.core.game3.scripting.flags"), engine("src.core.game3.scripting.space")
    local okP, P = pcall(Profile and Profile.forSession or error, nil)
    if not (okP and type(P) == "table" and P.family == "frlg") then return false end
    local okI, id = pcall(function() return Constants.of(P.id):flag("FLAG_SYS_POKEDEX_GET") end)
    if not (okI and id) then return false end
    if Flags and Space and Space.store then
      local okF, v = pcall(Flags.getFlag, Space.store, nil, id)
      if okF and v == true then return true end
    end
    local f = s and s.flags
    return f ~= nil and (f[id] == true or f[id] == 1)
  end

  function Ok.rating(s)
    local Dex, Rating, RomText = engine("src.core.game3.dex"), engine("src.core.game3.pokedex_rating"),
      engine("src.core.game3.rom_text")
    local dex = dexOf(s)
    local out = { seen = 0, caught = 0, words = "", complete = false, map = {}, toNext = nil, toward = 0 }
    for i = 1, Ok.TOTAL do out.map[i] = 0 end
    if not (Dex and dex) then return out end
    local okS, seen = pcall(Dex.countSeen, dex, "kanto")
    local okC, caught = pcall(Dex.countCaught, dex, "kanto")
    out.seen, out.caught = okS and tonumber(seen) or 0, okC and tonumber(caught) or 0
    local okR, key, complete = pcall(Rating.getRatingMessage, out.caught, dex)
    if okR and key then
      out.complete = complete == true
      local okT, text = pcall(RomText.plain, key)
      if okT and text then out.words = (tostring(text):gsub("[\r\n]+", " "):gsub("%s+", " ")) end
    end
    for i = 1, Ok.TOTAL do
      local okC2, c = pcall(Dex.isCaught, dex, i)
      local okS2, v = pcall(Dex.isSeen, dex, i)
      out.map[i] = (okC2 and c) and 2 or ((okS2 and v) and 1 or 0)
    end
    if not out.complete and out.caught < 150 then
      local inStep = out.caught % STEP
      out.toNext, out.toward = STEP - inStep, inStep / STEP
    end
    return out
  end

  function Ok.picture()
    local TrainerPic = engine("src.core.game3.trainer_pic")
    local ok, p = pcall(TrainerPic and TrainerPic.front or error, TRAINER_PIC_OAK)
    return ok and type(p) == "table" and p.image or nil
  end

  return Ok
end
