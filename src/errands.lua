-- Errands' model: send Pokémon on jobs in real time. A board of three jobs, new every six hours (from
-- the save's seed): a delivery round, a dig in the mine, Berry picking, a ferry escort, the power
-- plant, a bakery, the library, a night patrol, each favouring some types and with a level in mind,
-- an hour, four or eight long. A team of one to three goes: they leave the party or their boxes (kept
-- in the save while they're out, as a GTS deposit is) and come back when it's done with money, an item
-- and EXP each. How well the team suits the job (its types, its levels, how many) is settled when it
-- leaves and decides how much it brings back: Great, Good or OK. At most three teams out at once;
-- one can be called back early (no reward). Kept in the save (mod.save "errands": it rewinds with it).
--
--   Er = Errands(engine, deps)  deps: save ; now() ; seed(s) ; bx (src/boxes.lua) ; badges(s) ;
--       notify(kind, data) ; T (words: a notification's job name)
--   Er.JOBS ; Er.HOURS ; Er.MAX
--   Er.board(s, now) -> the three jobs posted { key, job, hours, taken }
--   Er.canSend(s, addr) -> true | false, reason ; Er.candidates(s, box) -> { addr } (the party, then box)
--   Er.send(s, key, addrs, now) -> true, errand | false, reason
--   Er.out() -> the teams out { key, job, hours, at, ends, team = { mon }, grade, reward, back }
--   Er.settle(s, now) (a team back: an "errand" notification) ; Er.waiting() -> teams back
--   Er.collect(s, i) -> true, errand, gained (levels each) | false, reason ; Er.recall(s, i)
--   reasons: "egg" | "mail" | "last" | "gone" | "busy" (three out) | "taken" | "team" (none, or more
--       than three) | "not_back" | "no_room" | "bag_full"

local floor, max, min = math.floor, math.max, math.min
local M31 = 2147483647

-- the jobs: the types they favour, the level in mind, the money (for an hour), the items, a picture
-- (src/icons.lua) and colour
local JOBS = {
  { id = "deliver", types = { 0, 2 }, level = 8, money = { 500, 900 }, items = { { 13, 2 }, { 4, 3 } },
    glyph = "send", color = { 0, 122, 255 } },
  { id = "mine", types = { 5, 4, 8, 1 }, level = 18, money = { 800, 1400 }, items = { { 106, 1 }, { 103, 2 }, { 24, 1 } },
    glyph = "cube", color = { 142, 110, 82 } },
  { id = "berry", types = { 12, 6 }, level = 6, money = { 400, 800 }, items = { { 139, 3 }, { 133, 2 }, { 142, 1 } },
    glyph = "flower", color = { 52, 199, 89 } },
  { id = "ferry", types = { 11, 15 }, level = 15, money = { 700, 1200 }, items = { { 26, 2 }, { 107, 1 } },
    glyph = "fish", color = { 48, 176, 199 } },
  { id = "power", types = { 13, 8 }, level = 20, money = { 900, 1500 }, items = { { 17, 2 }, { 18, 2 }, { 22, 2 } },
    glyph = "network", color = { 255, 189, 46 } },
  { id = "bakery", types = { 10 }, level = 12, money = { 600, 1000 }, items = { { 28, 2 }, { 27, 2 } },
    glyph = "flame", color = { 255, 120, 60 } },
  { id = "library", types = { 14, 7 }, level = 22, money = { 900, 1600 }, items = { { 34, 1 }, { 36, 1 } },
    glyph = "letters", color = { 175, 82, 222 } },
  { id = "patrol", types = { 17, 7, 3 }, level = 25, money = { 1000, 1800 }, items = { { 83, 2 }, { 84, 1 }, { 85, 1 } },
    glyph = "eye", color = { 88, 86, 214 } },
}
local HOURS = { 1, 4, 8 }
local FACTOR = { [1] = 1, [4] = 3, [8] = 5 }       -- what a job pays for its length (an hour = 1)
local GRADE = { great = 1.5, good = 1.2, ok = 1 }
local MAX, WINDOW, KEEP = 3, 6 * 3600, 20

local function nextRand(st)
  st.x = (st.x * 48271) % M31
  return st.x
end

return function(engine, deps)
  deps = deps or {}
  local Er = { store = deps.save, now = deps.now or os.time, rng = deps.rng, JOBS = JOBS, HOURS = HOURS, MAX = MAX,
               GRADE = GRADE }
  local Bx = deps.bx
  local BY_ID = {}
  for _, j in ipairs(JOBS) do BY_ID[j.id] = j end
  Er.job = function(id) return BY_ID[id] end

  local function P() return engine("src.core.game3.pokemon") end
  local function Storage() return engine("src.core.game3.storage") end
  local function roll(n)
    if Er.rng then return Er.rng(n) end
    local R = love and love.math and love.math.random
    return R and R(1, n) or math.random(1, n)
  end

  local loose
  local function data()
    local store = Er.store
    local d = store and store:get("errands") or loose
    if type(d) ~= "table" then
      d = { out = {}, taken = {}, log = {} }
      if store then store:set("errands", d) else loose = d end
    end
    d.out, d.taken, d.log = d.out or {}, d.taken or {}, d.log or {}
    return d
  end
  local function save(d) if Er.store then Er.store:set("errands", d) end end
  function Er.out() return data().out end
  function Er.log() return data().log end
  function Er.waiting()
    local n = 0
    for _, e in ipairs(data().out) do if e.back then n = n + 1 end end
    return n
  end

  -- ------- the board: three jobs every six hours

  local cache = { wnd = nil, seed = nil, list = nil }
  function Er.board(s, now)
    now = now or Er.now()
    local wnd = floor(now / WINDOW)
    local seed = tonumber(deps.seed and deps.seed(s)) or 1
    if cache.wnd ~= wnd or cache.seed ~= seed then
      local dice = { x = (seed * 6151 + wnd * 92821 + 5) % M31 }
      if dice.x == 0 then dice.x = 1 end
      for _ = 1, 3 do nextRand(dice) end
      local pool = {}
      for i = 1, #JOBS do pool[i] = JOBS[i] end
      local list = {}
      for i = 1, 3 do
        local j = table.remove(pool, nextRand(dice) % #pool + 1)
        list[i] = { key = wnd .. ":" .. i, job = j.id, hours = HOURS[nextRand(dice) % #HOURS + 1] }
      end
      cache.wnd, cache.seed, cache.list = wnd, seed, list
    end
    local taken = data().taken
    for _, b in ipairs(cache.list) do b.taken = taken[b.key] == true end
    return cache.list
  end

  -- ------- who may go

  local function isEgg(mon)
    local Pk = P()
    local ok, egg = pcall(Pk and Pk.isEgg or error, mon)
    return ok and egg == true or (mon and (mon.isEgg or mon.egg)) and true or false
  end
  local function hasMail(mon)
    local Mail = engine("src.core.game3.mail")
    local ok, has = pcall(Mail and Mail.monHasMail or error, mon)
    return ok and has == true
  end
  local function usable(mon) return mon and not isEgg(mon) and (tonumber(mon.hp) or 1) > 0 end
  function Er.canSend(s, addr)
    local mon = Bx.get(s, addr)
    if not mon then return false, "gone" end
    if isEgg(mon) then return false, "egg" end
    if hasMail(mon) then return false, "mail" end
    if addr.loc == "party" then
      local other = false
      for i, m in ipairs(Bx.party(s)) do
        if i ~= addr.slot and usable(m) then other = true end
      end
      if not other then return false, "last" end
    end
    return true
  end
  function Er.candidates(s, b)
    local out = {}
    for i = 1, 6 do
      local addr = Bx.addr("party", i)
      if Bx.get(s, addr) then out[#out + 1] = addr end
    end
    if b then
      for i = 1, Bx.SLOTS do
        local addr = Bx.addr("box", i, b)
        if Bx.get(s, addr) then out[#out + 1] = addr end
      end
    end
    return out
  end

  -- how well a team suits a job: its types, its levels, how many -> "great" | "good" | "ok"
  local function typesOf(mon)
    local Pk = P()
    local ok, types = pcall(Pk and Pk.types or error, tonumber(mon.species or mon.speciesId))
    return ok and type(types) == "table" and types or {}
  end
  function Er.fit(job, mon)
    for _, t in ipairs(typesOf(mon)) do
      for _, want in ipairs(job.types) do if tonumber(t) == want then return true end end
    end
    return false
  end
  local function grade(job, team)
    local score = #team - 1
    for _, mon in ipairs(team) do
      if Er.fit(job, mon) then score = score + 2 end
      if (tonumber(mon.level) or 1) >= job.level then score = score + 1 end
    end
    return score >= 6 and "great" or (score >= 3 and "good" or "ok")
  end

  -- what the team brings back (settled as it leaves): money, an item, EXP for each
  local function rewardOf(s, job, hours, g, team)
    local b = max(0, tonumber(deps.badges and deps.badges(s)) or 0)
    local k = (FACTOR[hours] or 1) * GRADE[g] * (1 + b * 0.25)
    local lo, hi = job.money[1], job.money[2]
    local money = floor((lo + roll(hi - lo + 1) - 1) * k / 10 + 0.5) * 10
    local it = job.items[roll(#job.items)]
    local n = it[2] * (hours >= 8 and 2 or 1) * (g == "great" and 2 or 1)
    local exp = {}
    for i, mon in ipairs(team) do
      local lvl = tonumber(mon.level) or 5
      exp[i] = floor((40 + lvl * 8) * (FACTOR[hours] or 1) * GRADE[g])
    end
    return { money = money, item = it[1], n = n, exp = exp }
  end

  function Er.send(s, key, addrs, now)
    now = now or Er.now()
    local d = data()
    if #d.out >= MAX then return false, "busy" end
    if type(addrs) ~= "table" or #addrs < 1 or #addrs > 3 then return false, "team" end
    local post
    for _, b in ipairs(Er.board(s, now)) do if b.key == key then post = b end end
    if not post then return false, "gone" end
    if d.taken[key] then return false, "taken" end
    local job = BY_ID[post.job]
    -- (each may go, and someone who can battle stays in the party)
    local leaving = {}
    for _, addr in ipairs(addrs) do
      local ok, why = Er.canSend(s, addr)
      if not ok then return false, why end
      if addr.loc == "party" then leaving[addr.slot] = true end
    end
    local stays = false
    for i, m in ipairs(Bx.party(s)) do if not leaving[i] and usable(m) then stays = true end end
    if not stays then return false, "last" end
    -- (out of their places: the boxes first, then the party from the back, so no slot moves under us)
    local order = {}
    for i, a in ipairs(addrs) do order[i] = a end
    table.sort(order, function(a, b)
      if a.loc ~= b.loc then return a.loc ~= "party" end
      return (a.slot or 0) > (b.slot or 0)
    end)
    local St = Storage()
    local team = {}
    for _, addr in ipairs(order) do
      local okT, mon = pcall(St.pickUpMon, s, addr.loc, addr.slot, addr.boxId)
      if okT and type(mon) == "table" then team[#team + 1] = mon end
    end
    if #team == 0 then return false, "gone" end
    local g = grade(job, team)
    local e = { key = key, job = job.id, hours = post.hours, at = now, ends = now + post.hours * 3600, team = team,
                grade = g, reward = rewardOf(s, job, post.hours, g, team), back = false }
    table.insert(d.out, e)
    d.taken[key] = true
    -- (the board's old windows forgotten)
    local wnd = floor(now / WINDOW)
    for k in pairs(d.taken) do
      local w = tonumber(tostring(k):match("^(%d+):"))
      if w and w < wnd - 1 then d.taken[k] = nil end
    end
    save(d)
    return true, e
  end

  function Er.settle(s, now)
    now = now or Er.now()
    local d = data()
    local changed = false
    for _, e in ipairs(d.out) do
      if not e.back and now >= e.ends then
        e.back, changed = true, true
        if deps.notify then
          local name = deps.T and deps.T("errands.job." .. e.job) or e.job
          pcall(deps.notify, "errand", { name = name, state = { tab = "out" } })
        end
      end
    end
    if changed then save(d) end
    return changed
  end

  -- a Pokémon to the player: the party, else the PC -> "party" | "pc" | nil
  local function place(s, mon)
    local party = Bx.party(s)
    if #party < 6 then
      party[#party + 1] = mon
      return "party"
    end
    local St = Storage()
    local ok, sent = pcall(St.sendMonToPC, s, mon)
    return ok and sent and "pc" or nil
  end
  -- room for n Pokémon (the party's spaces, then the boxes')
  local function room(s, n)
    local free = 6 - #Bx.party(s)
    if free >= n then return true end
    for b = 1, Bx.BOXES do
      for i = 1, Bx.SLOTS do
        if not Bx.get(s, Bx.addr("box", i, b)) then
          free = free + 1
          if free >= n then return true end
        end
      end
    end
    return false
  end
  local function giveExp(mon, n)
    local Daycare = engine("src.core.game3.daycare")
    local before = tonumber(mon.level) or 1
    local ok = pcall(Daycare and Daycare.applyExperience or error, mon, n)
    if not ok then
      local Exp = engine("src.core.game3.battle.experience")
      pcall(Exp and Exp.apply or error, mon, n)
    end
    if Bx.forget then Bx.forget(mon) end
    return max(0, (tonumber(mon.level) or before) - before)
  end

  function Er.collect(s, i)
    local d = data()
    local e = d.out[i]
    if not e then return false, "gone" end
    if not e.back then return false, "not_back" end
    if not room(s, #e.team) then return false, "no_room" end
    local Bag = engine("src.core.game3.bag")
    s.bag = s.bag or (Bag and Bag.new())
    local okC, can = pcall(Bag.canAdd, s.bag, e.reward.item, e.reward.n)
    if not (okC and can) then return false, "bag_full" end
    local gained = {}
    for k, mon in ipairs(e.team) do
      gained[k] = giveExp(mon, e.reward.exp[k] or 0)
      place(s, mon)
    end
    pcall(Bag.add, s.bag, e.reward.item, e.reward.n)
    local Prize = engine("src.core.game3.battle.prize")
    if Prize and Prize.apply then Prize.apply(s, e.reward.money) else s.money = (tonumber(s.money) or 0) + e.reward.money end
    table.remove(d.out, i)
    table.insert(d.log, 1, { job = e.job, grade = e.grade, money = e.reward.money, item = e.reward.item, n = e.reward.n,
                             sp = tonumber(e.team[1] and (e.team[1].species or e.team[1].speciesId)), at = Er.now() })
    while #d.log > KEEP do d.log[#d.log] = nil end
    save(d)
    return true, e, gained
  end

  -- called back early: home with nothing
  function Er.recall(s, i)
    local d = data()
    local e = d.out[i]
    if not e then return false, "gone" end
    if e.back then return Er.collect(s, i) end
    if not room(s, #e.team) then return false, "no_room" end
    for _, mon in ipairs(e.team) do place(s, mon) end
    table.remove(d.out, i)
    save(d)
    return true, e
  end

  return Er
end
