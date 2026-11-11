-- Challenges' model: five goals a week (Monday to Sunday, local time), the same for a save all week
-- (seeded from its playthrough and the week), counted from the journal (src/journal.lua): battles,
-- catches (of a type, new ones, today's swarm), hatches, evolutions, levels, items used, steps,
-- places. Goals grow with the badges. Each pays money (into the wallet; what it can't hold goes to
-- the Bank) or items into the Bag; all five claimed, the week's bonus. Kept in the save (mod.save
-- "challenges": it rewinds with the save).
--
--   Ch = Challenges(engine, deps)  deps: save ; now() ; journal (Jr) ; seed(s) ; badges(s) ;
--       notify(kind, data) ; T (words) ; typeName(id) ; itemName(id) ; swarmOn() ; frlg()
--   Ch.list(s) -> the week's five { kind, param, goal, reward = { money } | { item, n }, claimed, told }
--   Ch.progress(e) -> counted so far (at most the goal) ; Ch.done(e) ; Ch.text(e) -> its words
--   Ch.bonus(s) -> { item, n, claimed } ; Ch.bonusReady(s)
--   Ch.claim(s, i) / Ch.claimBonus(s) -> true, reward | false, reason ("not_done" | "claimed" | "bag_full")
--   Ch.check(s) (once a second: a goal reached -> a "challenge" notification, once)
--   Ch.waiting(s) -> rewards waiting to be claimed ; Ch.endsIn(now) -> seconds to the next Monday

local floor, max, min = math.floor, math.max, math.min
local M31 = 2147483647

-- the kinds: the journal's count, the goal for b badges, how much the reward is worth (x), when it
-- can be offered (b badges, FireRed / LeafGreen?)
local KINDS = {
  { id = "trainer", key = "trainer", goal = function(b) return 3 + b end, x = 3 },
  { id = "wild", key = "wild", goal = function(b) return 8 + 2 * b end, x = 2 },
  { id = "catch", key = "caught", goal = function(b) return 3 + floor(b / 2) end, x = 3 },
  { id = "type", goal = function(b) return 2 + floor(b / 3) end, x = 3 },
  { id = "new", key = "new", goal = function(b) return 2 + floor(b / 2) end, x = 3 },
  { id = "hatch", key = "hatched", goal = function() return 1 end, x = 3,
    when = function(b, frlg) return frlg and b >= 8 or (not frlg and b >= 3) end },
  { id = "evolve", key = "evolved", goal = function(b) return 1 + floor(b / 4) end, x = 3,
    when = function(b) return b >= 1 end },
  { id = "items", key = "items", goal = function(b) return 4 + b end, x = 1 },
  { id = "steps", key = "steps", goal = function(b) return 1500 + 250 * b end, x = 1 },
  { id = "places", key = "places", goal = function(b) return 6 + b end, x = 1 },
  { id = "levels", key = "levels", goal = function(b) return 5 + 2 * b end, x = 2 },
  { id = "swarm", key = "swarm", goal = function() return 1 end, x = 3, swarm = true },
}
local BY_ID = {}
for _, k in ipairs(KINDS) do BY_ID[k.id] = k end
-- the types a "type" goal may ask for (ones found in the wild early and late)
local TYPES = { 0, 11, 12, 6, 2, 3, 5, 4, 13, 10, 14 }
-- the items a goal may pay, by how far along (0-2, 3-5, 6+ badges): { id, how many }
local ITEMS = {
  { { 4, 5 }, { 13, 4 }, { 22, 2 }, { 3, 3 }, { 24, 1 }, { 17, 3 } },
  { { 3, 5 }, { 22, 4 }, { 21, 2 }, { 24, 2 }, { 2, 2 }, { 23, 3 } },
  { { 2, 5 }, { 21, 4 }, { 25, 1 }, { 19, 1 }, { 63, 1 }, { 64, 1 }, { 65, 1 }, { 66, 1 }, { 67, 1 } },
}
-- the week's bonus, all five claimed
local BONUS = { { 68, 1 }, { 68, 2 }, { 68, 3 } }
local COUNT = 5

local function nextRand(st)
  st.x = (st.x * 48271) % M31
  return st.x
end

return function(engine, deps)
  deps = deps or {}
  local Ch = { store = deps.save, now = deps.now or os.time, KINDS = KINDS, COUNT = COUNT }
  local Jr = deps.journal
  local T = deps.T

  local loose
  local function data()
    local store = Ch.store
    local d = store and store:get("challenges") or loose
    if type(d) ~= "table" then
      d = {}
      if store then store:set("challenges", d) else loose = d end
    end
    return d
  end
  local function save(d) if Ch.store then Ch.store:set("challenges", d) end end
  local function badges(s) return max(0, floor(tonumber(deps.badges and deps.badges(s)) or 0)) end
  local function tier(b) return b >= 6 and 3 or (b >= 3 and 2 or 1) end

  -- the week's set, made the first time it's asked for that week
  local function build(s, week)
    local b = badges(s)
    local frlg = deps.frlg and deps.frlg() or false
    local swarmOn = deps.swarmOn and deps.swarmOn() or false
    local seed = tonumber(deps.seed and deps.seed(s)) or 1
    local dice = { x = (seed * 7919 + week * 104729 + 17) % M31 }
    if dice.x == 0 then dice.x = 1 end
    for _ = 1, 3 do nextRand(dice) end
    local function roll(n) return nextRand(dice) % n + 1 end
    local pool = {}
    for _, k in ipairs(KINDS) do
      if (not k.when or k.when(b, frlg)) and (not k.swarm or swarmOn) then pool[#pool + 1] = k end
    end
    local list = {}
    for i = 1, min(COUNT, #pool) do
      local k = table.remove(pool, roll(#pool))
      local e = { kind = k.id, goal = k.goal(b), claimed = false, told = false }
      if k.id == "type" then e.param = TYPES[roll(#TYPES)] end
      -- (half pay money, half items)
      if roll(2) == 1 then
        e.reward = { money = floor((800 + 400 * b) * k.x / 100 + 0.5) * 100 }
      else
        local it = ITEMS[tier(b)]
        local pick = it[roll(#it)]
        e.reward = { item = pick[1], n = pick[2] }
      end
      list[i] = e
    end
    local bonus = BONUS[tier(b)]
    return { week = week, list = list, bonus = { item = bonus[1], n = bonus[2], claimed = false } }
  end
  local function current(s)
    local d = data()
    local week = Jr and Jr.week() or 0
    if d.week ~= week or type(d.list) ~= "table" then
      local made = build(s, week)
      d.week, d.list, d.bonus = made.week, made.list, made.bonus
      save(d)
    end
    return d
  end

  function Ch.list(s) return current(s).list end
  function Ch.bonus(s) return current(s).bonus end
  local function keyOf(e) return e.kind == "type" and ("t" .. tostring(e.param)) or (BY_ID[e.kind] and BY_ID[e.kind].key) end
  function Ch.progress(e)
    local key = keyOf(e)
    return min(e.goal, key and Jr and Jr.count(key) or 0)
  end
  function Ch.done(e) return Ch.progress(e) >= e.goal end
  function Ch.text(e)
    if not T then return e.kind end
    if e.kind == "type" then
      local name = deps.typeName and deps.typeName(e.param) or tostring(e.param)
      return T.f("challenges.kind.type", e.goal, name)
    end
    return T.f("challenges.kind." .. e.kind, e.goal)
  end
  function Ch.bonusReady(s)
    local d = current(s)
    if d.bonus.claimed then return false end
    for _, e in ipairs(d.list) do if not e.claimed then return false end end
    return true
  end
  function Ch.waiting(s)
    if not s then return 0 end
    local d = current(s)
    local n = 0
    for _, e in ipairs(d.list) do if not e.claimed and Ch.done(e) then n = n + 1 end end
    if Ch.bonusReady(s) then n = n + 1 end
    return n
  end

  -- a reward to the player: money (the wallet, then the Bank, through Prize.apply), items to the Bag
  local function pay(s, r)
    if r.money then
      local Prize = engine("src.core.game3.battle.prize")
      if Prize and Prize.apply then Prize.apply(s, r.money) else s.money = (tonumber(s.money) or 0) + r.money end
      return true
    end
    local Bag = engine("src.core.game3.bag")
    s.bag = s.bag or (Bag and Bag.new())
    local okC, can = pcall(Bag.canAdd, s.bag, r.item, r.n)
    if not (okC and can) then return false end
    local okA = pcall(Bag.add, s.bag, r.item, r.n)
    return okA
  end
  function Ch.claim(s, i)
    local d = current(s)
    local e = d.list[i]
    if not e then return false, "not_done" end
    if e.claimed then return false, "claimed" end
    if not Ch.done(e) then return false, "not_done" end
    if not pay(s, e.reward) then return false, "bag_full" end
    e.claimed, e.told = true, true
    save(d)
    return true, e.reward
  end
  function Ch.claimBonus(s)
    local d = current(s)
    if d.bonus.claimed then return false, "claimed" end
    if not Ch.bonusReady(s) then return false, "not_done" end
    if not pay(s, d.bonus) then return false, "bag_full" end
    d.bonus.claimed = true
    save(d)
    return true, d.bonus
  end

  -- once a second: each goal reached tells the player once
  function Ch.check(s)
    if not s then return end
    local d = current(s)
    local changed = false
    for _, e in ipairs(d.list) do
      if not e.told and Ch.done(e) then
        e.told, changed = true, true
        if deps.notify then pcall(deps.notify, "challenge", { name = Ch.text(e) }) end
      end
    end
    if changed then save(d) end
  end

  -- seconds until the next Monday midnight (local)
  function Ch.endsIn(now)
    now = now or Ch.now()
    if not Jr then return 0 end
    local lt = Jr.localTime(now)
    local nextMonday = (floor((floor(lt / 86400) + 3) / 7) + 1) * 7 - 3
    return max(0, nextMonday * 86400 - lt)
  end

  return Ch
end
