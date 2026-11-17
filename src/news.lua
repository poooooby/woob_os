-- The News's model: the broadcast, built when it's opened. It follows the player as a rookie the
-- region can't stop talking about, the way sports news follows a breakout star: first their latest
-- Gym (the score, then the play-by-play: the leads, each knockout and the turn it came, the
-- finishing blow), their last two trainers beaten (the score, where, both teams, the finisher), their
-- latest catch (a signing: where, the level, the Ball), their latest battle with a legend (its
-- play-by-play and how it ended), newest first, and their week. Then the world
-- (Ruby / Sapphire / Emerald's story as it happens -- src/story.lua -- the weather while a legend is loose
-- and where Latias / Latios roam, today's swarm, the game's own TV outbreak, Emerald's storms, R-Bay's
-- hottest auction), then what else the journal saw since they last watched (a shiny, a first for the
-- Pokédex, hatches, evolutions), a GTS trade, a team out on an errand or back, the week's challenges.
-- The rookie's stories are told as the desk's reports, the player by name ("Our field teams report ..."),
-- never to them ("you").
-- Nothing made up: the battles are the journal's box scores (src/journal.lua), the swarm is real
-- (src/swarm.lua). The last time they watched is kept in the save (mod.save "news"), and the swarm's
-- notification once a day. Each story has the anchor's mood for it: "cheer" for the rookie's big
-- moments (a Gym, a clean sweep, a first for the Pokédex, a hatch, an evolution, the week's challenges
-- all done, a big week), "shock" for breaking news and anything shiny or legendary in the rookie's
-- own story, none (her everyday read) for the rest -- the day's swarm, the TV's outbreak and R-Bay too.
--
--   Nw = News(engine, deps)  deps: save ; now() ; journal ; swarm ; auction ; gts ; errands ;
--       challenges ; story (src/story.lua) ; storm(s) -> { kind, place } | nil ; place(mapId) -> its name ;
--       monName(sp) ; species(name) -> sp ;
--       moveName(num) ; itemName(id) ; T ; notify(kind, data)
--   Nw.build(s) -> { stories = { { tag = "world" | "you", head, body, beats = { { mark, text } } | nil,
--       sp, glyph, color, key, mood = "cheer" | "shock" | nil } }, ticker }
--     keys: gym, match1, match2, signing, legend, week, story.<id> (src/story.lua's ids), crisis, roamer,
--       swarm, outbreak, storm, rbay, shiny, catch, hatch, evolve, gts, errand, errandBack, challenges, quiet
--   Nw.tick(s) (once a second: a new day's swarm -> a "swarm" notification, once a day)
--   Nw.storyHead(s, { id, team, legend }) -> a story beat's headline (its notification's words)

local floor, max, min = math.floor, math.max, math.min

local TIER_RANK = { common = 1, uncommon = 2, rare = 3, prized = 4, legendary = 5, mythical = 6 }
local MOMENTS = 4      -- the journal's moments told at most
local BEATS_NEW = 3    -- the story's beats told at most, when several came since they last watched
-- the week's word on it, by the trainers beaten and the Pokémon caught since Monday: none, a quiet start;
-- under WEEK_BUSY a steady week; under WEEK_HUGE a busy one; past it, the whole region's talking
local WEEK_BUSY, WEEK_HUGE = 6, 15

-- the story's beats: what the headline and the words are given, in order (me = the player, team, legend;
-- groudon / kyogre the two by name), whose story it is, the anchor's mood, a picture when it has no
-- Pokemon. Ruby and Sapphire tell a few their own way, FireRed and LeafGreen the Champion (KEY_RS, KEY_FR:
-- the words' key)
local STORY = {
  -- (FireRed / LeafGreen)
  pokedex = { head = { "me" }, body = { "me" }, tag = "you", mood = "cheer", glyph = "pokeball" },
  mtMoon = { head = {}, body = { "me" }, tag = "you", mood = "cheer", glyph = "cube" },
  burglar = { head = {}, body = { "me" }, tag = "you", glyph = "glove" },
  bill = { head = { "me" }, body = { "me" }, tag = "you", glyph = "speech" },
  ssAnne = { head = { "me" }, body = { "me" }, tag = "you", glyph = "fish" },
  hideout = { head = {}, body = { "me" }, tag = "you", mood = "shock", glyph = "building" },
  fuji = { head = {}, body = { "me" }, tag = "you", mood = "cheer", glyph = "bell" },
  snorlax = { head = { "legend" }, body = { "legend", "me" } },
  silph = { head = {}, body = { "me" }, tag = "you", mood = "cheer", glyph = "building" },
  giovanni = { head = {}, body = { "me" }, mood = "shock", glyph = "glove" },
  championFr = { head = { "me" }, body = { "me" }, tag = "you", mood = "cheer", glyph = "medal" },
  ruby = { head = { "me" }, body = { "me" }, tag = "you", mood = "cheer", glyph = "flame" },
  warehouse = { head = {}, body = { "me" }, tag = "you", mood = "cheer", glyph = "building" },
  sapphire = { head = {}, body = { "me" }, tag = "you", mood = "cheer", glyph = "eye" },
  network = { head = {}, body = {}, mood = "cheer", glyph = "network" },
  beast = { head = { "legend" }, body = { "legend" }, mood = "shock" },
  -- (Ruby / Sapphire / Emerald)
  chimney = { head = { "me", "team" }, body = { "me", "team" }, tag = "you", mood = "cheer", glyph = "flame" },
  institute = { head = { "me", "team" }, body = { "me", "team" }, tag = "you", mood = "cheer", glyph = "cloud" },
  orb = { head = { "team" }, body = { "team" }, mood = "shock", glyph = "eye" },
  orbs = { head = {}, body = {}, mood = "shock", glyph = "eye" },
  groudon = { head = { "legend" }, body = { "team", "legend" }, mood = "shock" },
  submarine = { head = { "team" }, body = { "team" }, mood = "shock", glyph = "fish" },
  spaceCenter = { head = { "me" }, body = { "team", "me" }, tag = "you", mood = "cheer", glyph = "building" },
  awakened = { head = { "legend" }, body = { "team", "legend" }, mood = "shock" },
  clash = { head = { "groudon", "kyogre" }, body = {}, mood = "shock" },
  cave = { head = { "me" }, body = { "me" }, tag = "you", glyph = "eye" },
  caveRs = { head = { "legend" }, body = { "legend", "me" } },
  rayquaza = { head = { "legend" }, body = { "me", "legend" }, mood = "shock" },
  calm = { head = { "legend" }, body = { "legend" }, mood = "cheer" },
  calmRs = { head = { "me", "legend" }, body = { "me", "legend" }, tag = "you", mood = "cheer" },
  champion = { head = { "me" }, body = { "me" }, tag = "you", mood = "cheer", glyph = "medal" },
  lati = { head = { "legend" }, body = { "legend" }, mood = "shock" },
  frontier = { head = { "me" }, body = { "me" }, tag = "you", mood = "cheer", glyph = "building" },
  tower = { head = { "me" }, body = { "me" }, tag = "you", mood = "cheer", glyph = "building" },
}
local KEY_RS = { cave = "caveRs", calm = "calmRs" }
local KEY_FR = { champion = "championFr" }
local TEAM_COLOR = { magma = { 214, 48, 49 }, aqua = { 9, 132, 227 }, rocket = { 196, 30, 44 } }

return function(engine, deps)
  deps = deps or {}
  local Nw = { store = deps.save, now = deps.now or os.time }
  local T = deps.T

  local loose
  local function data()
    local store = Nw.store
    local d = store and store:get("news") or loose
    if type(d) ~= "table" then
      d = {}
      if store then store:set("news", d) else loose = d end
    end
    return d
  end
  local function save(d) if Nw.store then Nw.store:set("news", d) end end

  local function name(sp)
    if not sp then return "?" end
    if deps.monName then
      local ok, n = pcall(deps.monName, sp)
      if ok and n then return n end
    end
    return tostring(sp)
  end
  local function place(mapId)
    if deps.place then
      local ok, n = pcall(deps.place, mapId)
      if ok and n and n ~= "" then return n end
    end
    return tostring(mapId or "?")
  end
  local function commas(n)
    local s = tostring(floor(n))
    repeat
      local k
      s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return s
  end
  local function playerOf(s) return tostring(s and (s.name or s.playerName) or "?") end
  -- (the game's capitals, as the species are written: "Youngster Joey")
  local function titled(text)
    return (tostring(text):lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
  end
  local function moveName(num)
    if not (num and deps.moveName) then return nil end
    local ok, n = pcall(deps.moveName, num)
    return ok and n or nil
  end
  local function itemName(id)
    if not (id and deps.itemName) then return nil end
    local ok, n = pcall(deps.itemName, id)
    if ok and type(n) == "string" and n ~= "" then return titled(n) end
    return nil
  end
  -- (a team: "Pidgey, Rattata and Spearow")
  local function listOf(sps)
    local n = type(sps) == "table" and #sps or 0
    if n == 0 then return "?" end
    local out = name(sps[1])
    for i = 2, n do out = out .. T(i == n and "news.list.last" or "news.list.sep") .. name(sps[i]) end
    return out
  end
  local function whoOf(rec)
    local cls, nm = tostring(rec.cls or ""), tostring(rec.name or "?")
    return titled(cls ~= "" and (cls .. " " .. nm) or nm)
  end
  local function turns(n)
    n = tonumber(n) or 0
    return n == 1 and T("news.turn1") or T.f("news.turns", n)
  end
  local function num(v) return tonumber(v) or 0 end
  -- (how a blow landed: a critical hit, super effective)
  local function flair(b)
    if b.crit then return T("news.flair.crit") .. " " end
    if b.sup then return T("news.flair.super") .. " " end
    return ""
  end
  -- one knockout, told: who fell, to whom and what (when the journal saw it), the last of theirs the
  -- end of the match
  local function beatText(b, final)
    local mv = b.by and moveName(b.mv)
    if b.k == "ko" then
      if final then
        return mv and (flair(b) .. T.f("news.pbp.final", name(b.by), mv, name(b.v))) or T.f("news.pbp.finalNone", name(b.v))
      end
      return mv and (flair(b) .. T.f("news.pbp.ko", name(b.by), mv, name(b.v))) or T.f("news.pbp.koNone", name(b.v))
    end
    return mv and T.f("news.pbp.down", name(b.by), mv, name(b.v)) or T.f("news.pbp.downNone", name(b.v))
  end

  -- the rookie's coverage: the latest Gym, the last two trainers beaten, the latest catch
  local function rookie(Jr, me)
    local out = {}
    local g = Jr.gym and Jr.gym()
    if type(g) == "table" then
      local who = whoOf(g)
      local head = (g.badge and num(g.n) > 0) and T.f("news.gym.head", me, who, num(g.n)) or T.f("news.gym.headWin", me, who)
      local body = T.f("news.gym.lede", place(g.map), me, who, num(g.me), num(g.them), turns(g.turns))
      local beats = {}
      if g.lead and g.foeLead then
        beats[1] = { mark = "", text = T.f("news.pbp.lead", titled(tostring(g.name or "?")), name(g.foeLead), me, name(g.lead)) }
      end
      local last
      for i, b in ipairs(g.beats or {}) do if b.k == "ko" then last = i end end
      for i, b in ipairs(g.beats or {}) do
        beats[#beats + 1] = { mark = T.f("news.pbp.turn", num(b.t)), text = beatText(b, i == last) }
      end
      local f = g.fin
      out[#out + 1] = { tag = "you", key = "gym", head = head, body = body, beats = beats, at = num(g.at),
                        sp = f and f.by or g.lead, glyph = "medal", color = { 255, 189, 46 }, mood = "cheer" }
    end
    for i, w in ipairs(Jr.wins and Jr.wins() or {}) do
      if i > 2 then break end
      local who = whoOf(w)
      local body = T.f("news.match.body", place(w.map), me, listOf(w.mine), who, listOf(w.theirs), turns(w.turns))
      local f = w.fin
      local mv = f and f.by and moveName(f.mv)
      if mv then body = body .. " " .. flair(f) .. T.f("news.match.final", name(f.by), mv, name(f.v)) end
      if num(w.them) == 0 then body = body .. " " .. T("news.match.clean") end
      out[#out + 1] = { tag = "you", key = "match" .. i, head = T.f("news.match.head", me, num(w.me), who, num(w.them)),
                        body = body, at = num(w.at), sp = f and f.by or (w.mine and w.mine[1]),
                        glyph = "glove", color = { 255, 69, 58 }, mood = num(w.them) == 0 and "cheer" or nil }
    end
    local L = Jr.legend and Jr.legend()
    if type(L) == "table" and L.sp and L.result then
      local who = name(L.sp)
      local body = T.f("news.legend.lede", place(L.map), me, who, tostring(L.lv or "?"), turns(L.turns))
      local beats = {}
      if L.lead then beats[1] = { mark = "", text = T.f("news.legend.lead", me, name(L.lead), who) } end
      local last
      for i, b in ipairs(L.beats or {}) do if b.k == "ko" then last = i end end
      for i, b in ipairs(L.beats or {}) do
        beats[#beats + 1] = { mark = T.f("news.pbp.turn", num(b.t)), text = beatText(b, i == last) }
      end
      local balls = num(L.balls)
      if L.result == "caught" then
        local ball = itemName(L.ball)
        body = body .. " " .. (ball and T.f("news.legend.caught", ball) or T("news.legend.caughtNone"))
        if balls == 1 then body = body .. " " .. T("news.legend.first")
        elseif balls > 1 then body = body .. " " .. T.f("news.legend.balls", balls) end
        beats[#beats + 1] = { mark = T.f("news.pbp.turn", num(L.turns)),
                              text = ball and T.f("news.legend.caughtBeat", ball) or T("news.legend.caughtNone") }
      elseif L.result == "down" then
        body = body .. " " .. T("news.legend.down")
      elseif L.result == "lost" then
        body = body .. " " .. T.f("news.legend.lost", me)
      elseif L.result == "ran" then
        body = body .. " " .. T.f("news.legend.ran", me)
      else
        body = body .. " " .. T("news.legend.fled")
      end
      if L.shiny then body = body .. " " .. T("news.legend.shiny") end
      local mood = nil
      if L.shiny then mood = "shock" elseif L.result == "caught" then mood = "cheer" end
      out[#out + 1] = { tag = "you", key = "legend", head = T.f("news.legend.head." .. L.result, me, who), body = body,
                        beats = beats, at = num(L.at), sp = L.sp, mood = mood }
    end
    local c = Jr.catch and Jr.catch()
    if type(c) == "table" and c.sp then
      local body = T.f("news.sign.body", place(c.map), tostring(c.lv or "?"), name(c.sp))
      local ball = itemName(c.ball)
      if ball then body = body .. " " .. T.f("news.sign.ball", ball) end
      if c.shiny then body = body .. " " .. T("news.sign.shiny") elseif c.new then body = body .. " " .. T("news.sign.new") end
      out[#out + 1] = { tag = "you", key = "signing", head = T.f("news.sign.head", me, name(c.sp)), body = body,
                        at = num(c.at), sp = c.sp, mood = c.shiny and "shock" or (c.new and "cheer" or nil) }
    end
    -- (newest first, the way the day's sports lead)
    table.sort(out, function(a, b)
      if a.at ~= b.at then return a.at > b.at end
      return a.key < b.key
    end)
    return out
  end

  -- a story beat's words: its key (Ruby / Sapphire's own for a few), the names it's given in order
  local function legendName(sp) return sp and name(sp) or "?" end
  local spByName = {}
  local function speciesNamed(id)
    local hit = spByName[id]
    if hit == nil then
      local ok, sp = pcall(deps.species or error, id)
      hit = ok and sp or false
      spByName[id] = hit
    end
    return hit or nil
  end
  local function storyArgs(spec, me, rec)
    local out = {}
    for i, a in ipairs(spec) do
      if a == "me" then out[i] = me
      elseif a == "team" then out[i] = T("news.team." .. tostring(rec.team or "magma"))
      elseif a == "legend" then out[i] = legendName(rec.legend)
      else out[i] = legendName(speciesNamed(a:upper())) end
    end
    return out
  end
  local unpack = unpack or table.unpack
  local function storyKey(id)
    local g = deps.gameId and deps.gameId() or ""
    if g == "ruby" or g == "sapphire" then return KEY_RS[id] or id end
    if g == "firered" or g == "leafgreen" then return KEY_FR[id] or id end
    return id
  end
  function Nw.storyHead(s, rec)
    local key = storyKey(rec.id)
    local spec = STORY[key]
    if not spec then return tostring(rec.id) end
    return T.f("news.story." .. key .. ".head", unpack(storyArgs(spec.head, playerOf(s), rec)))
  end

  -- the story's beats: the ones reached since they last watched (the newest few), else the latest
  local function storyBeats(s, me, since, add)
    local Sy = deps.story
    if not Sy then return end
    local okR, all = pcall(Sy.reached, s)
    if not (okR and type(all) == "table" and #all > 0) then return end
    local told = {}
    for i = #all, 1, -1 do
      if #told >= BEATS_NEW then break end
      if all[i].at > since then told[#told + 1] = all[i] end
    end
    if #told == 0 then told[1] = all[#all] end
    for _, rec in ipairs(told) do
      local key = storyKey(rec.id)
      local spec = STORY[key]
      if spec then
        add(spec.tag or "world", "story." .. rec.id,
          T.f("news.story." .. key .. ".head", unpack(storyArgs(spec.head, me, rec))),
          T.f("news.story." .. key .. ".body", unpack(storyArgs(spec.body, me, rec))),
          { sp = rec.legend, glyph = not rec.legend and spec.glyph or nil,
            color = TEAM_COLOR[rec.team or ""] or { 88, 86, 214 }, mood = spec.mood })
      end
    end
  end

  function Nw.build(s)
    local list = {}
    local function add(tag, key, head, body, extra)
      local st = { tag = tag, key = key, head = head, body = body }
      if extra then for k, v in pairs(extra) do st[k] = v end end
      list[#list + 1] = st
    end
    local now = Nw.now()
    local me = playerOf(s)
    local Jr = deps.journal
    -- (the rookie: the latest Gym, the last two wins, the latest catch, newest first; then their week)
    if Jr then
      for _, st in ipairs(rookie(Jr, me)) do list[#list + 1] = st end
      local tr, ca, steps = Jr.count("trainer"), Jr.count("caught"), Jr.count("steps")
      if tr + ca + steps > 0 then
        -- (the tally as it is -- none, one or how many of each -- and a word on the week that fits it: the
        -- region talks only about a big one)
        local trW = tr == 0 and T("news.week.tr0") or (tr == 1 and T("news.week.tr1") or T.f("news.week.trN", tr))
        local caW = ca == 0 and T("news.week.ca0") or (ca == 1 and T("news.week.ca1") or T.f("news.week.caN", ca))
        local stW = steps == 0 and T("news.week.st0") or (steps == 1 and T("news.week.st1") or T.f("news.week.stN", steps))
        local done = tr + ca
        local close = done == 0 and T("news.week.quiet") or (done < WEEK_BUSY and T("news.week.steady")
          or (done < WEEK_HUGE and T("news.week.busy") or T("news.week.huge")))
        add("you", "week", T.f("news.week.head", me), T.f("news.week.lede", me, trW, caW, stW) .. " " .. close,
          { glyph = "chart", color = { 255, 55, 95 }, mood = done >= WEEK_HUGE and "cheer" or nil })
      end
    end
    -- (the world: the story first -- the weather while a legend is loose, its beats, where Latias / Latios
    -- roam -- then the day's)
    local Sy = deps.story
    if Sy and s then
      local okC, crisis = pcall(Sy.crisis, s)
      if okC and crisis then
        local legend = crisis == "drought" and speciesNamed("GROUDON") or speciesNamed("KYOGRE")
        add("world", "crisis", T("news.crisis." .. crisis .. ".head"), T.f("news.crisis." .. crisis .. ".body", legendName(legend)),
          { glyph = "cloud", color = crisis == "drought" and { 214, 150, 60 } or { 70, 110, 200 }, mood = "shock" })
      end
      storyBeats(s, me, tonumber(data().watched) or 0, add)
      local okL, r = pcall(Sy.roamer, s)
      if okL and type(r) == "table" then
        local who, where = name(r.sp), place(r.map)
        add("world", "roamer", T.f("news.roamer.head", who, where), T.f("news.roamer.body", who, where),
          { sp = r.sp, mood = "shock" })
      end
    end
    local sw = deps.swarm and deps.swarm.today(s)
    if sw then
      local where, who = place(sw.mapId), name(sw.species)
      add("world", "swarm", T.f("news.swarm.head", who, where), T.f("news.swarm.body", who, where, sw.min, sw.max),
        { sp = sw.species })
    end
    local ob = s and s.outbreak
    if type(ob) == "table" and tonumber(ob.species) and (not sw or tonumber(ob.species) ~= sw.species) then
      local who, where = name(tonumber(ob.species)), place(ob.map)
      add("world", "outbreak", T.f("news.outbreak.head", who, where), T.f("news.outbreak.body", who, where),
        { sp = tonumber(ob.species) })
    end
    local storm = deps.storm and deps.storm(s)
    if type(storm) == "table" and storm.place then
      local k = storm.kind == "sand" and "sand" or "rain"
      add("world", "storm", T.f("news.storm." .. k .. ".head", storm.place), T.f("news.storm." .. k .. ".body", storm.place),
        { glyph = "cloud", color = k == "sand" and { 214, 150, 60 } or { 70, 110, 200 }, mood = "shock" })
    end
    if deps.auction and s then
      local ok, ls = pcall(deps.auction.listings, s, now)
      local best, bestScore
      if ok and type(ls) == "table" then
        for _, L in ipairs(ls) do
          if (L.finish or 0) - now > 60 then
            local sc = (TIER_RANK[L.tier] or 0) * 1e7 + (L.shiny and 4.5e7 or 0) + (tonumber(L.price) or 0)
            if not bestScore or sc > bestScore then best, bestScore = L, sc end
          end
        end
      end
      if best then
        local tierWord = T("auction.tier." .. tostring(best.tier or "common"))
        add("world", "rbay", T.f("news.rbay.head", name(best.sp)),
          T.f("news.rbay.body", tierWord, name(best.sp), commas(tonumber(best.price) or 0)),
          { sp = best.sp, glyph = "rocket", color = { 196, 30, 44 } })
      end
    end
    -- (the rest since they last watched, the newest few: the latest catch is the signing already;
    -- trainers and Badges are the box scores)
    if Jr then
      local d = data()
      local since = tonumber(d.watched) or 0
      local told = 0
      local signed = Jr.catch and Jr.catch()
      for _, m in ipairs(Jr.log()) do
        if told >= MOMENTS or (m.at or 0) <= since then break end
        local ok = true
        if m.k == "catch" and type(signed) == "table" and signed.at == m.at and signed.sp == m.sp then
          ok = false
        elseif m.k == "catch" and m.shiny then
          add("you", "shiny", T.f("news.shiny.head", name(m.sp)), T.f("news.shiny.body", me, name(m.sp)),
            { sp = m.sp, mood = "shock" })
        elseif m.k == "catch" and m.new then
          add("you", "catch", T.f("news.catch.head", name(m.sp)), T.f("news.catch.body", me, name(m.sp)),
            { sp = m.sp, mood = "cheer" })
        elseif m.k == "hatch" then
          add("you", "hatch", T.f("news.hatch.head", name(m.sp)), T.f("news.hatch.body", me, name(m.sp)),
            { sp = m.sp, mood = "cheer" })
        elseif m.k == "evolve" then
          add("you", "evolve", T.f("news.evolve.head", name(m.from), name(m.sp)),
            T.f("news.evolve.body", me, name(m.from), name(m.sp)), { sp = m.sp, mood = "cheer" })
        else
          ok = false
        end
        if ok then told = told + 1 end
      end
    end
    -- (the GTS's last trade)
    if deps.gts then
      local okL, log = pcall(deps.gts.log)
      local t = okL and type(log) == "table" and log[1]
      if t and t.sp then
        local region = T("gts.region." .. tostring((deps.gts.REGIONS or {})[t.region or 1] or "kanto"))
        add("you", "gts", T.f("news.gts.head", name(t.sp), region), T.f("news.gts.body", me, region, name(t.sp)),
          { sp = t.sp, glyph = "globe", color = { 30, 120, 220 } })
      end
    end
    -- (a team out, or back)
    if deps.errands then
      for _, e in ipairs(deps.errands.out()) do
        local job = T("errands.job." .. e.job)
        if e.back then
          add("you", "errandBack", T.f("news.errandBack.head", me), T.f("news.errandBack.body", me, job), { glyph = "shoes", color = { 0, 150, 136 } })
        else
          add("you", "errand", T.f("news.errand.head", me), T.f("news.errand.body", me, job), { glyph = "shoes", color = { 0, 150, 136 } })
        end
        break
      end
    end
    -- (the week's challenges)
    if deps.challenges and s then
      local okC, l = pcall(deps.challenges.list, s)
      if okC and type(l) == "table" and #l > 0 then
        local done = 0
        for _, e in ipairs(l) do if deps.challenges.done(e) then done = done + 1 end end
        add("you", "challenges", T.f("news.challenges.head", me, done, #l), T.f("news.challenges.body", me, done, #l),
          { glyph = "medal", color = { 255, 159, 10 }, mood = done >= #l and "cheer" or nil })
      end
    end
    if #list == 0 then add("you", "quiet", T("news.quiet.head"), T.f("news.quiet.body", me), { glyph = "mic", color = { 88, 86, 214 } }) end
    -- (the ticker: every headline, one after another)
    local heads = {}
    for i, st in ipairs(list) do
      heads[i] = st.head
      st.at = nil
    end
    local d = data()
    d.watched = now
    save(d)
    return { stories = list, ticker = table.concat(heads, "   •   ") }
  end

  -- once a second: a new day's swarm, told once (when the field can show it)
  function Nw.tick(s)
    if not (s and deps.swarm) then return end
    local sw = deps.swarm.today(s)
    if not sw then return end
    local d = data()
    if d.swarmDay == sw.day then return end
    d.swarmDay = sw.day
    save(d)
    if deps.notify then
      pcall(deps.notify, "swarm", { name = name(sw.species), who = place(sw.mapId), state = { story = "swarm" } })
    end
  end

  return Nw
end
