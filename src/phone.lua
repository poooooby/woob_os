-- The Phone's model: the PokéNav's contacts as a phone book. Emerald: Match Call's (the game's
-- own list, names, classes, pictures, the check page's lines, rematches), and a call is the game's
-- own (its words, and what it does: a trainer asking for a rematch, a flag set), so calling from
-- the Phone counts as calling from the PokéNav. Ruby / Sapphire: Trainer's Eyes' (the trainers
-- and Gym Leaders fought, their profiles, who's ready for a rematch; those games have no calls).
-- The recent calls (30) and the favourites are kept in the save ("phone"): they rewind with it.
--
--   Ph = Phone(engine, deps)   deps: save (mod.save) ; now() -> the device's seconds ; notify(kind, data) ;
--                              image(path) -> one of the mod's own pictures
--   Ph.family(s) -> "emerald" | "rs" | nil        Ph.available(s) -> the game has given it
--   Ph.contacts(s) -> { contact }   contact = { key, name, desc, pic, place, rematch, nearby, canCall,
--                                                check = { lines } }
--   Ph.call(s, contact) -> text, ok (logged)      Ph.recents(s) ; Ph.isFav(s, key) ; Ph.toggleFav(s, key)
--   Ph.incoming(s, name, text, pic) (the field's calls: logged, and a notification)
--   Ph.picture(pic) -> a love Image or nil (kept): a number is the game's trainer picture; "mom",
--                      "scott", "stone" (the mod's assets/*.png, Wooble's) and "birch" (the Professor of
--                      the game's new-game speech) stand in for the Emerald contacts the game has none for

local KEEP = 30

return function(engine, deps)
  deps = deps or {}
  local Ph = { KEEP = KEEP, store = deps.save, now = deps.now or os.time }
  local loose = nil

  local function family()
    local Profile = engine("src.core.game3.profile")
    local ok, P = pcall(Profile and Profile.forSession or error, nil)
    if not (ok and type(P) == "table" and P.family == "rse") then return nil end
    local id = tostring(P.id or "")
    if id:find("emerald") then return "emerald" end
    return "rs"
  end
  function Ph.family() return family() end

  local function flagOn(s, name)
    local Flags, Space = engine("src.core.game3.scripting.flags"), engine("src.core.game3.scripting.space")
    local Constants, Profile = engine("src.core.game3.constants"), engine("src.core.game3.profile")
    local ok, id = pcall(function()
      return Constants.of(Profile.forSession(s).id):flag(name)
    end)
    if not (ok and id) then return false end
    if Flags and Space and Space.store then
      local okF, v = pcall(Flags.getFlag, Space.store, nil, id)
      if okF and v == true then return true end
    end
    local f = s and s.flags
    return f ~= nil and (f[id] == true or f[id] == 1 or f[name] == true)
  end

  function Ph.available(s)
    local fam = family()
    if not fam or not s then return false end
    if fam == "emerald" then return flagOn(s, "FLAG_ADDED_MATCH_CALL_TO_POKENAV") end
    return flagOn(s, "FLAG_SYS_POKENAV_GET")
  end

  -- ------- the save's part: recents and favourites

  local function data()
    local store = Ph.store
    local d = store and store:get("phone") or loose
    if type(d) ~= "table" then
      d = { recents = {}, fav = {} }
      if store then store:set("phone", d) else loose = d end
    end
    d.recents, d.fav = d.recents or {}, d.fav or {}
    return d
  end
  local function saved(d) if Ph.store then Ph.store:set("phone", d) end end

  local function log(name, key, text, pic, incoming)
    local d = data()
    table.insert(d.recents, 1, { name = tostring(name or "?"), key = key, text = tostring(text or ""),
                                 pic = tonumber(pic) or (type(pic) == "string" and pic or nil), at = Ph.now(),
                                 incoming = incoming == true })
    while #d.recents > KEEP do d.recents[#d.recents] = nil end
    saved(d)
  end
  function Ph.recents() return data().recents end
  function Ph.isFav(_, key) return data().fav[key] == true end
  function Ph.toggleFav(_, key)
    local d = data()
    d.fav[key] = not d.fav[key] or nil
    saved(d)
    return d.fav[key] == true
  end

  -- ------- pictures and words

  local pics = {}
  local OWN_ART = { mom = "assets/mom.png", scott = "assets/scott.png", stone = "assets/mrstone.png" }
  local function ownPicture(key)
    if key == "birch" then
      -- (the Professor as the game's new-game speech shows him)
      local Kit = engine("src.ui.game3.rse.scene_kit")
      local okM, man = pcall(Kit and Kit.manifest or error, "birch")
      local p = okM and type(man) == "table" and man.pics and man.pics.birch
      local okI, img = pcall(Kit and Kit.image or error, p and p.png)
      return okI and img or nil
    end
    if OWN_ART[key] and deps.image then
      local ok, img = pcall(deps.image, OWN_ART[key])
      if ok and img then
        pcall(img.setFilter, img, "nearest", "nearest")
        return img
      end
    end
    return nil
  end
  function Ph.picture(pic)
    if type(pic) == "string" and not tonumber(pic) then
      local got = pics[pic]
      if got == nil then
        got = ownPicture(pic) or false
        pics[pic] = got
      end
      return got or nil
    end
    pic = tonumber(pic)
    if not pic or pic < 0 then return nil end
    local got = pics[pic]
    if got ~= nil then return got or nil end
    local TrainerPic = engine("src.core.game3.trainer_pic")
    local ok, p = pcall(TrainerPic and TrainerPic.front or error, pic)
    got = ok and type(p) == "table" and p.image or false
    pics[pic] = got
    return got or nil
  end

  local function plain(key, ctx)
    local RomText = engine("src.core.game3.rom_text")
    if not (RomText and key) then return nil end
    local ok, s = pcall(RomText.plain, key, ctx)
    return ok and s or nil
  end
  -- "LITTLEROOT TOWN" -> "Littleroot Town" ; "{PKMN} PROF." -> "Pokémon Prof." (the game's codes out)
  local function titled(s)
    s = tostring(s or ""):gsub("{PKMN}", "POKéMON"):gsub("{PK}{MN}", "POKéMON"):gsub("{[^}]*}", "")
    return (s:gsub("(%a)([%w'é]*)", function(a, rest) return a:upper() .. rest:lower() end))
  end
  Ph.titled = titled

  -- ------- the contacts

  -- the special contacts the game has no picture for, by their name's text: ours
  local OWN_PIC = { gText_MomMatchCallName = "mom", gText_ProfBirchMatchCallName = "birch",
                    gText_ScottMatchCallName = "scott", gText_MrStoneMatchCallName = "stone" }
  local function emeraldContacts(s)
    local MC = engine("src.core.game3.rse.match_call")
    local ok, list = pcall(MC and MC.buildList or error, s)
    if not ok then return {} end
    local out = {}
    for _, e in ipairs(list) do
      local okN, desc, name = pcall(MC.entryNameAndDesc, e)
      local okP, pic = pcall(MC.entryTrainerPic, s, e)
      local okM, place = pcall(MC.mapName, e.mapSec)
      local okR, rematch = pcall(MC.showRematchIcon, s, e)
      local okB, nearby = pcall(MC.shouldDoNearbyMessage, s, e)
      local c = { key = (e.isSpecialTrainer and "h" or "t") .. tostring(e.headerId), entry = e,
                  name = okN and titled(name) or "?", desc = okN and titled(desc) or "",
                  pic = okP and tonumber(pic) or -1, place = okM and place and titled(place) or "",
                  rematch = okR and rematch == true, nearby = okB and nearby == true, canCall = true, check = {} }
      if e.isSpecialTrainer and c.pic < 0 then
        local okH, h = pcall(MC.header, e.headerId)
        c.pic = okH and type(h) == "table" and OWN_PIC[h.name] or c.pic
      end
      local okC, has = pcall(MC.headerHasCheckPage, e.headerId)
      if not e.isSpecialTrainer or (okC and has) then
        for i = 1, 4 do
          local okF, key = pcall(MC.entryFlavorText, s, e, i)
          local line = okF and key and plain(key) or nil
          if line and line ~= "" then c.check[#c.check + 1] = line end
        end
      end
      out[#out + 1] = c
    end
    return out
  end

  local function rsContacts(s)
    local Gfx, Data = engine("src.ui.game3.rs.pokenav.gfx"), engine("src.ui.game3.rs.pokenav.data")
    local Trainers = engine("src.core.game3.scripting.trainers")
    if not (Gfx and Data and Trainers) then return {} end
    local ok, man = pcall(Gfx.manifest, "pokenav_detail")
    local okR, region = pcall(Gfx.manifest, "region_map")
    if not ok then return {} end
    local okE, rows = pcall(Data.trainersEyes, s, nil, man)
    if not okE then return {} end
    local out = {}
    for _, row in ipairs(rows) do
      local okT, info = pcall(Trainers.get, row.opponentId)
      info = okT and info or {}
      local c = { key = "r" .. tostring(row.rematchTableIdx), row = row, name = titled(info.name or "?"),
                  desc = titled(info.className or ""), pic = tonumber(info.pic) or -1,
                  place = okR and titled(Data.sectionName(region, row.regionMapSectionId)) or "",
                  rematch = (tonumber(row.rematchNo) or 0) ~= 0, nearby = false, canCall = false, check = {} }
      local lines = man.descriptions and man.descriptions[row.descriptionId]
      local st = man.strings or {}
      if lines then
        c.check = { st.Strategy, lines[1], st.TrainersPokemon, lines[2], st.SelfIntroduction, lines[3], lines[4] }
        c.headings = { [1] = true, [3] = true, [5] = true }
      end
      out[#out + 1] = c
    end
    return out
  end

  function Ph.contacts(s)
    local fam = family()
    if fam == "emerald" then return emeraldContacts(s) end
    if fam == "rs" then return rsContacts(s) end
    return {}
  end

  -- the game's own call: its words (a trainer close by says so instead); logged
  function Ph.call(s, c)
    if not (c and c.canCall and c.entry) then return nil, false end
    local MC, Screen = engine("src.core.game3.rse.match_call"), engine("src.ui.game3.rse.pokenav.match_call")
    local TextIR = engine("src.core.game3.scripting.text_ir")
    local text
    if c.nearby then
      text = plain("gText_TrainerCloseBy")
    else
      local ok, msg = pcall(MC.entryMessage, s, c.entry)
      if ok and msg then
        local okI, ir = pcall(Screen.messageIr, msg)
        local okP, s2 = pcall(TextIR.toPlain, okI and ir or {}, msg.ctx or {})
        text = okP and s2 or nil
      end
    end
    if not text or text == "" then return nil, false end
    text = text:gsub("\r", "")
    log(c.name, c.key, text, c.pic, false)
    return text, true
  end

  -- a call the game made in the field (src/shell.lua wraps MatchCall.startCall)
  function Ph.incoming(s, name, text, pic)
    log(name, nil, text, pic, true)
    if deps.notify then deps.notify("call", { name = name, text = text, pic = pic }) end
  end

  -- the words of a call window's message (the field's calls)
  function Ph.textOf(msg)
    if type(msg) ~= "table" then return nil end
    local Screen, TextIR = engine("src.ui.game3.rse.pokenav.match_call"), engine("src.core.game3.scripting.text_ir")
    local okI, ir = pcall(Screen.messageIr, msg)
    if not okI then return nil end
    local okP, s = pcall(TextIR.toPlain, ir, msg.ctx or {})
    return okP and s or nil
  end

  return Ph
end
