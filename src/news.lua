-- The News's model: the broadcast, built when it's opened. It follows the player as a rookie the
-- region can't stop talking about, the way sports news follows a breakout star: first their latest
-- Gym (the score, then the play-by-play: the leads, each knockout and the turn it came, the
-- finishing blow), their last two trainers beaten (the score, where, both teams, the finisher), their
-- latest catch (a signing: where, the level, the Ball), newest first, and their week. Then the world
-- (today's swarm, Ruby / Sapphire / Emerald's own TV outbreak, Emerald's storms, R-Bay's hottest
-- auction), then what else the journal saw since they last watched (a shiny, a first for the
-- Pokédex, hatches, evolutions), a GTS trade, a team out on an errand or back, the week's challenges.
-- Nothing made up: the battles are the journal's box scores (src/journal.lua), the swarm is real
-- (src/swarm.lua). The last time they watched is kept in the save (mod.save "news"), and the swarm's
-- notification once a day. Each story has the anchor's mood for it: "cheer" for the rookie's big
-- moments (a Gym, a clean sweep, a first for the Pokédex, a hatch, an evolution, the week's challenges
-- all done), "shock" for breaking news and anything shiny or legendary, none (her everyday read) for
-- the rest.
--
--   Nw = News(engine, deps)  deps: save ; now() ; journal ; swarm ; auction ; gts ; errands ;
--       challenges ; storm(s) -> { kind, place } | nil ; place(mapId) -> its name ; monName(sp) ;
--       moveName(num) ; itemName(id) ; T ; notify(kind, data)
--   Nw.build(s) -> { stories = { { tag = "world" | "you", head, body, beats = { { mark, text } } | nil,
--       sp, glyph, color, key, mood = "cheer" | "shock" | nil } }, ticker }
--     keys: gym, match1, match2, signing, week, swarm, outbreak, storm, rbay, shiny, catch, hatch,
--       evolve, gts, errand, errandBack, challenges, quiet
--   Nw.tick(s) (once a second: a new day's swarm -> a "swarm" notification, once a day)

local floor, max, min = math.floor, math.max, math.min

local TIER_RANK = { common = 1, uncommon = 2, rare = 3, prized = 4, legendary = 5, mythical = 6 }
local MOMENTS = 4      -- the journal's moments told at most

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
        add("you", "week", T("news.week.head"), T.f("news.week.body", tr, ca, steps), { glyph = "chart", color = { 255, 55, 95 } })
      end
    end
    -- (the world)
    local sw = deps.swarm and deps.swarm.today(s)
    if sw then
      local where, who = place(sw.mapId), name(sw.species)
      add("world", "swarm", T.f("news.swarm.head", who, where), T.f("news.swarm.body", who, where, sw.min, sw.max),
        { sp = sw.species, mood = "shock" })
    end
    local ob = s and s.outbreak
    if type(ob) == "table" and tonumber(ob.species) and (not sw or tonumber(ob.species) ~= sw.species) then
      local who, where = name(tonumber(ob.species)), place(ob.map)
      add("world", "outbreak", T.f("news.outbreak.head", who, where), T.f("news.outbreak.body", who, where),
        { sp = tonumber(ob.species), mood = "shock" })
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
          { sp = best.sp, glyph = "rocket", color = { 196, 30, 44 },
            mood = (best.shiny or (TIER_RANK[best.tier] or 0) >= TIER_RANK.legendary) and "shock" or nil })
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
        add("you", "gts", T.f("news.gts.head", name(t.sp), region), T.f("news.gts.body", region, name(t.sp)),
          { sp = t.sp, glyph = "globe", color = { 30, 120, 220 } })
      end
    end
    -- (a team out, or back)
    if deps.errands then
      for _, e in ipairs(deps.errands.out()) do
        local job = T("errands.job." .. e.job)
        if e.back then
          add("you", "errandBack", T("news.errandBack.head"), T.f("news.errandBack.body", job), { glyph = "shoes", color = { 0, 150, 136 } })
        else
          add("you", "errand", T("news.errand.head"), T.f("news.errand.body", job), { glyph = "shoes", color = { 0, 150, 136 } })
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
        add("you", "challenges", T.f("news.challenges.head", done, #l), T.f("news.challenges.body", done, #l),
          { glyph = "medal", color = { 255, 159, 10 }, mood = done >= #l and "cheer" or nil })
      end
    end
    if #list == 0 then add("you", "quiet", T("news.quiet.head"), T("news.quiet.body"), { glyph = "mic", color = { 88, 86, 214 } }) end
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
