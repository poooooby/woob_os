-- The Radio app's model on Gold / Silver / Crystal: the Pokégear's radio, played by the game's own show
-- machine through an off-stack Pokégear (H.gear(): never pushed). Everything is the game's: which stations
-- the dial finds here and now (Johto's or Kanto's, the EXPN Card's, the Ruins of Alph's signal, the Rocket
-- takeover, the Ch. 20 signal, Buena at night), the shows' words line by line (Oak's talk, the Pokédex
-- Show, Lucky Number, Places & People ...), and the music they start, which stays the map's music after
-- the radio is left, as the Pokégear leaves it (March and Lullaby change the wild encounters; the Poké
-- Flute wakes Snorlax). The knob is the save's (radioTuningKnob), as the Pokégear's.
--
--   Rd = radio(H)
--   Rd.available(s) -> the Pokégear's Radio Card       Rd.KNOB_MAX (80: 20.5 MHz; the knob steps by 2)
--   Rd.open() -> true (tuned where the knob is)       Rd.openStation(station) (a wall radio's: one station)
--   Rd.close() (the music as leaving the radio leaves it)
--   Rd.step(clock) (the show, 60 steps a second of the clock)
--   Rd.knob() -> 0..80 ; Rd.setKnob(k) -> true when it moved (tuned)
--   Rd.stations() -> { { knob, frequency ("04.5"), station (id | nil: nothing here now), name } } (on open)
--   Rd.current() -> station id | nil, name | nil, frequency
--   Rd.lines() -> the show's two lines (top, bottom: "" when quiet) ; Rd.version (bumps when they change)
--   Rd.song() -> the song the station plays (a "Music_*" label) | nil
--   Rd.history(i) -> the transcript's i-th line, 1 the newest (the game's PkMn as the kit's K.PKMN) | nil;
--     Rd.historyCount() ; Rd.histVersion (bumps on a line, and when a new tune starts it again)
--   Rd.featured() -> the species key Oak's talk / the Pokédex Show is on about | nil
--   Rd.lucky() -> Lucky Number's number this week, on that station | nil

local KNOB_MAX = 80
local STEP = 1 / 60
local HIST = 12
-- (the shows that name a Pokémon: the one they're on about, for its picture)
local FEATURES = { OAKS_POKEMON_TALK = true, POKEDEX_SHOW = true }

return function(H)
  local engine = H.engine
  local Rd = { KNOB_MAX = KNOB_MAX, version = 0, histVersion = 0 }
  local gear, list, fixed = nil, nil, nil
  local acc, last = 0, nil
  local top, bottom, rawTop, rawBottom = "", "", "", ""
  -- the game's PkMn (its <PK><MN> tiles) as the kit's PkMn mark (K.PKMN, a private-use character the
  -- kit draws as the small staggered letters)
  local PKMN = "\238\128\128"
  local function marked(s) return (s:gsub("<PK><MN>", PKMN):gsub("<PKMN>", PKMN):gsub("<PK>", ""):gsub("<MN>", "")) end
  -- "OAK's <PK><MN> Talk" -> "Oak's PkMn Talk" (the game's capitals as a name)
  local named = {}
  local function nameOf(raw)
    if raw == nil then return nil end
    local got = named[raw]
    if got then return got end
    local s = marked(tostring(raw))
    s = s:gsub("POKéMON", "Pokémon"):gsub("POKé", "Poké"):gsub("(%u)([%u']+)", function(a, b) return a .. b:lower() end)
    named[raw] = s
    return s
  end

  -- (the station tuned: kept when the dial moves, so a draw asks nothing of the game)
  local cur = { station = nil, name = nil, frequency = "" }
  local function readCurrent()
    cur.station, cur.name, cur.frequency = nil, nil, ""
    if not gear then return end
    if fixed then
      local okN, name = pcall(gear.stationName, gear, fixed)
      cur.station, cur.name = fixed, okN and nameOf(name) or nil
      return
    end
    local ok, row = pcall(gear.currentStation, gear)
    if ok and type(row) == "table" then
      cur.station, cur.name, cur.frequency = row.station, row.station and nameOf(row.name) or nil,
        tostring(row.frequency or "")
    end
  end

  function Rd.available(s) return H.hasRadio and H.hasRadio(s) or false end

  local function refreshList()
    list = {}
    if not gear then return end
    local ok, rows = pcall(gear.stations, gear)
    for _, r in ipairs(ok and type(rows) == "table" and rows or {}) do
      list[#list + 1] = { knob = r.knob, frequency = tostring(r.frequency or ""), station = r.station,
                          name = nameOf(r.name) }
    end
  end
  -- the transcript: the show's lines as the game prints them (its log), the last HIST kept, newest first;
  -- a new tune (the game's log started again) starts it again
  local hist, histN, seenLog, seenN = {}, 0, nil, 0
  local function clearHist()
    for i = 1, histN do hist[i] = nil end
    histN, seenLog, seenN = 0, nil, 0
    Rd.histVersion = Rd.histVersion + 1
  end
  local function addLine(s)
    if s == "" then return end
    if s:find("<", 1, true) then s = marked(s) end
    for i = math.min(histN + 1, HIST), 2, -1 do hist[i] = hist[i - 1] end
    hist[1] = s
    histN = math.min(histN + 1, HIST)
    Rd.histVersion = Rd.histVersion + 1
  end
  local function heard()
    local r = gear and gear.radio
    local t, b = r and tostring(r.top or "") or "", r and tostring(r.bottom or "") or ""
    if t ~= rawTop or b ~= rawBottom then
      rawTop, rawBottom = t, b
      top = t:find("<", 1, true) and marked(t) or t
      bottom = b:find("<", 1, true) and marked(b) or b
      Rd.version = Rd.version + 1
    end
    local log = r and r.log
    if type(log) ~= "table" then return end
    if log ~= seenLog or #log < seenN then
      clearHist()
      seenLog = log
    end
    for i = seenN + 1, #log do addLine(tostring(log[i] or "")) end
    seenN = #log
  end

  function Rd.open()
    Rd.close()
    gear = H.gear and H.gear() or nil
    if not gear then return false end
    fixed, acc, last = nil, 0, nil
    refreshList()
    local ok, err = pcall(gear.tuneRadio, gear)
    if not ok and H.log then H.log("the radio couldn't tune: %s", tostring(err)) end
    readCurrent()
    heard()
    return ok
  end
  -- (a wall radio: the one station its script names, no dial)
  function Rd.openStation(station)
    Rd.close()
    gear = H.gear and H.gear() or nil
    local Pokegear = engine("src.ui.gen2.Pokegear")
    if not (gear and Pokegear and Pokegear.Radio and station) then return false end
    fixed, acc, last = station, 0, nil
    list = {}
    local ok, err = pcall(function()
      gear.radio = Pokegear.Radio.new({ data = gear:radioData(), rng = gear.radioRng })
      gear.radio:tune(station)
      gear.radioOn, gear.radioShow = true, station
      gear:playRadioMusic()
    end)
    if not ok and H.log then H.log("the wall radio couldn't play: %s", tostring(err)) end
    readCurrent()
    heard()
    return ok
  end
  function Rd.close()
    if gear then pcall(gear.stopRadio, gear) end
    gear, list, fixed = nil, nil, nil
    cur.station, cur.name, cur.frequency = nil, nil, ""
    top, bottom, rawTop, rawBottom = "", "", "", ""
    Rd.version = Rd.version + 1
    clearHist()
  end
  function Rd.isOpen() return gear ~= nil end
  function Rd.fixed() return fixed end

  -- (the show's frames, 60 a second of the clock, at most a second's worth at once)
  function Rd.step(clock)
    if not gear then return end
    if last == nil then last = clock end
    acc = math.min(1, acc + math.max(0, clock - last))
    last = clock
    while acc >= STEP do
      acc = acc - STEP
      if fixed then
        local r = gear.radio
        if r then
          r:step()
          pcall(gear.playRadioMusic, gear)
        end
      else
        pcall(gear.tickRadio, gear)
      end
    end
    heard()
  end

  function Rd.knob() return gear and tonumber(gear.tuningKnob) or 0 end
  function Rd.setKnob(k)
    if not gear or fixed then return false end
    k = math.max(0, math.min(KNOB_MAX, math.floor((tonumber(k) or 0) / 2 + 0.5) * 2))
    if k == gear.tuningKnob then return false end
    gear.tuningKnob = k
    local ok = pcall(gear.tuneRadio, gear)
    acc = 0
    readCurrent()
    heard()
    return ok
  end
  function Rd.stations() return list or {} end
  function Rd.current() return cur.station, cur.name, cur.frequency end
  function Rd.lines() return top, bottom end
  function Rd.history(i) return hist[i] end
  function Rd.historyCount() return histN end
  -- the Pokémon the show is on about (Oak's talk, the Pokédex Show: a species key) | nil
  function Rd.featured()
    local r = gear and gear.radio
    if not (r and cur.station and FEATURES[cur.station]) then return nil end
    -- (not while Team Rocket has the airwaves)
    if tostring(r.cur or ""):find("^ROCKET") or tostring(r.next or ""):find("^ROCKET") then return nil end
    return r.vars and r.vars.species or nil
  end
  -- Lucky Number's number this week (the save's) | nil off that station
  function Rd.lucky()
    local r = gear and gear.radio
    if not (r and cur.station == "LUCKY_CHANNEL" and r.data) then return nil end
    return tonumber(r.data.luckyNumber)
  end
  function Rd.song() return gear and gear.radioSong or nil end
  return Rd
end
