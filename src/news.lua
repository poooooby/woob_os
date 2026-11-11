-- The News's model: the broadcast, built when it's opened. World stories first (today's swarm, Ruby /
-- Sapphire / Emerald's own TV outbreak, Emerald's storms, R-Bay's hottest auction), then the
-- player's (the week so far, and what the journal saw since they last watched: catches, a shiny,
-- hatches, evolutions, trainers beaten, a badge; a GTS trade; a team out on an errand or back; the
-- week's challenges). Nothing made up beyond the swarm, which is real (src/swarm.lua). The last
-- time they watched is kept in the save (mod.save "news"), and the swarm's notification once a day.
--
--   Nw = News(engine, deps)  deps: save ; now() ; journal ; swarm ; auction ; gts ; errands ;
--       challenges ; storm(s) -> { kind, place } | nil ; place(mapId) -> its name ; monName(sp) ; T ;
--       notify(kind, data)
--   Nw.build(s) -> { stories = { { tag = "world" | "you", head, body, sp, glyph, color, key } }, ticker }
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

  function Nw.build(s)
    local list = {}
    local function add(tag, key, head, body, extra)
      local st = { tag = tag, key = key, head = head, body = body }
      if extra then for k, v in pairs(extra) do st[k] = v end end
      list[#list + 1] = st
    end
    local now = Nw.now()
    local me = playerOf(s)
    -- (the world)
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
        { glyph = "cloud", color = k == "sand" and { 214, 150, 60 } or { 70, 110, 200 } })
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
    -- (the player: the week so far)
    local Jr = deps.journal
    if Jr then
      local tr, ca, steps = Jr.count("trainer"), Jr.count("caught"), Jr.count("steps")
      if tr + ca + steps > 0 then
        add("you", "week", T("news.week.head"), T.f("news.week.body", tr, ca, steps), { glyph = "chart", color = { 255, 55, 95 } })
      end
      -- (the moments since they last watched; the newest, a few)
      local d = data()
      local since = tonumber(d.watched) or 0
      local told = 0
      for _, m in ipairs(Jr.log()) do
        if told >= MOMENTS or (m.at or 0) <= since then break end
        local ok = true
        if m.k == "catch" and m.shiny then
          add("you", "shiny", T.f("news.shiny.head", name(m.sp)), T.f("news.shiny.body", me, name(m.sp)), { sp = m.sp })
        elseif m.k == "catch" and m.new then
          add("you", "catch", T.f("news.catch.head", name(m.sp)), T.f("news.catch.body", me, name(m.sp)), { sp = m.sp })
        elseif m.k == "hatch" then
          add("you", "hatch", T.f("news.hatch.head", name(m.sp)), T.f("news.hatch.body", me, name(m.sp)), { sp = m.sp })
        elseif m.k == "evolve" then
          add("you", "evolve", T.f("news.evolve.head", name(m.from), name(m.sp)),
            T.f("news.evolve.body", me, name(m.from), name(m.sp)), { sp = m.sp })
        elseif m.k == "trainer" and m.name then
          local who = titled(tostring(m.cls or "") ~= "" and (tostring(m.cls) .. " " .. tostring(m.name)) or tostring(m.name))
          add("you", "trainer", T.f("news.trainer.head", me, who), T.f("news.trainer.body", me, who),
            { glyph = "glove", color = { 255, 69, 58 } })
        elseif m.k == "badge" then
          add("you", "badge", T.f("news.badge.head", me), T.f("news.badge.body", me, tonumber(m.n) or 0),
            { glyph = "medal", color = { 255, 189, 46 } })
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
          { glyph = "medal", color = { 255, 159, 10 } })
      end
    end
    if #list == 0 then add("you", "quiet", T("news.quiet.head"), T("news.quiet.body"), { glyph = "mic", color = { 88, 86, 214 } }) end
    -- (the ticker: every headline, one after another)
    local heads = {}
    for i, st in ipairs(list) do heads[i] = st.head end
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
