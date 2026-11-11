-- The Bank's model: money kept apart from the wallet, in the save (mod.save "bank": it rewinds with
-- the save, as the money does). The wallet holds what the game allows (999,999); whatever would go
-- over it lands here instead (main.lua wraps the engine's Prize.apply, which every gain goes
-- through: prize money, the game's scripts, the Mart, R-Bay, Slots), up to MAX. Deposit from the
-- wallet, withdraw into it (as much as fits). Interest: a tenth of a percent a day on what's kept,
-- for each whole day since the last payment (a week at most), never more than DAILY a day.
--
--   Bk = Bank(engine, deps)  deps: save (mod.save) ; now() -> epoch seconds ; notify(kind, data)
--   Bk.MAX ; Bk.wallet() -> the wallet's cap (the engine's) ; Bk.balance() ; Bk.log() -> newest first
--       { kind = "in" | "out" | "over" | "interest", amount, at }
--   Bk.deposit(s, n) / Bk.withdraw(s, n) -> true, moved | false, reason
--   Bk.room(s) -> how much the wallet can still take ; Bk.overflow(s, n) -> banked
--   Bk.settle(s, now) -> interest paid (0 when none is due)
--   reasons: "none" (nothing to move) | "wallet" (the wallet's full) | "full" (the bank's full)

local floor, max, min = math.floor, math.max, math.min

local MAX = 999999999
local function commas(n)
  local s = tostring(floor(n))
  repeat
    local k
    s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
  until k == 0
  return s
end
local KEEP = 30
local RATE, DAILY, DAYS = 0.001, 5000, 7

return function(engine, deps)
  deps = deps or {}
  local Bk = { MAX = MAX, store = deps.save, now = deps.now or os.time }

  local loose
  local function data()
    local store = Bk.store
    local d = store and store:get("bank") or loose
    if type(d) ~= "table" then
      d = { balance = 0, log = {} }
      if store then store:set("bank", d) else loose = d end
    end
    d.balance, d.log = tonumber(d.balance) or 0, d.log or {}
    return d
  end
  local function save(d) if Bk.store then Bk.store:set("bank", d) end end
  local function note(d, kind, amount)
    -- (overflow from one place in a row: one line, added up)
    local top = d.log[1]
    if kind == "over" and top and top.kind == "over" and Bk.now() - (top.at or 0) < 60 then
      top.amount, top.at = top.amount + amount, Bk.now()
    else
      table.insert(d.log, 1, { kind = kind, amount = amount, at = Bk.now() })
      while #d.log > KEEP do d.log[#d.log] = nil end
    end
  end

  function Bk.balance() return data().balance end
  function Bk.log() return data().log end
  function Bk.wallet()
    local Prize = engine("src.core.game3.battle.prize")
    return tonumber(Prize and Prize.MAX_MONEY) or 999999
  end
  local function money(s) return max(0, floor(tonumber(s and s.money) or 0)) end
  function Bk.room(s) return max(0, Bk.wallet() - money(s)) end

  function Bk.deposit(s, n)
    n = floor(tonumber(n) or 0)
    if not s or n <= 0 then return false, "none" end
    local d = data()
    n = min(n, money(s), MAX - d.balance)
    if n <= 0 then return false, money(s) <= 0 and "none" or "full" end
    s.money = money(s) - n
    d.balance = d.balance + n
    note(d, "in", n)
    save(d)
    return true, n
  end
  function Bk.withdraw(s, n)
    n = floor(tonumber(n) or 0)
    if not s or n <= 0 then return false, "none" end
    local d = data()
    if d.balance <= 0 then return false, "none" end
    n = min(n, d.balance, Bk.room(s))
    if n <= 0 then return false, "wallet" end
    d.balance = d.balance - n
    s.money = money(s) + n
    note(d, "out", n)
    save(d)
    return true, n
  end

  -- what didn't fit in the wallet -> how much the bank took (the rest is lost, as over the cap)
  function Bk.overflow(s, n)
    n = floor(tonumber(n) or 0)
    if not s or n <= 0 then return 0 end
    local d = data()
    n = min(n, MAX - d.balance)
    if n <= 0 then return 0 end
    d.balance = d.balance + n
    note(d, "over", n)
    save(d)
    if deps.notify then pcall(deps.notify, "bank", { name = commas(n), amount = n }) end
    return n
  end

  -- interest for the whole days since the last payment (the first visit only starts the count)
  function Bk.settle(s, now)
    now = now or Bk.now()
    local d = data()
    local day = floor(now / 86400)
    if not d.day then
      d.day = day
      save(d)
      return 0
    end
    local days = min(DAYS, day - d.day)
    if days <= 0 then
      if day < d.day then d.day = day end
      return 0
    end
    d.day = day
    local paid = 0
    for _ = 1, days do
      local i = min(DAILY, floor(d.balance * RATE))
      i = min(i, MAX - d.balance)
      d.balance, paid = d.balance + i, paid + i
    end
    if paid > 0 then note(d, "interest", paid) end
    save(d)
    return paid
  end

  return Bk
end
