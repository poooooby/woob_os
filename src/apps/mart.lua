-- The Mart app: a corner shop. The game's own Mart clerk behind the counter under a striped awning,
-- talking in a speech bubble: a greeting for the time of day (or the new stock a Badge brought), a
-- word on each purchase and sale, why not when something can't be had, a tip now and then. The goods
-- (more as the Gym Badges come in) are bought straight into the Bag, the item appearing on the
-- shelf's pad; the Bag's items sold for half their price, off the pad. Tabs along the list's top; the
-- chosen item on a lit stand beside it (its words, how many, the total); coins flying to and from the
-- till, the money counting.
--   buttons  Up / Down the item, L / R the tab (Buy: Balls, Medicine, Battle, Field; Sell: the
--            Bag's pockets), START Buy | Sell, A the item (then < > one, ^ v ten, SELECT as many
--            as there are / as money buys, A buy or sell, B back), B close
--   touch    tap an item, its - / + and Buy / Sell; the Buy | Sell switch; a tab; the clerk; the
--            bubble (the rest of the words); drag (or the wheel) scrolls the list
-- The model is src/mart.lua (env.mart); rows are made again only after a change. The clerk is the
-- game's overworld sprite (env.clerk), drawn at whole pixels; without it the bubble speaks alone.
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, sin, abs, pi = math.floor, math.max, math.min, math.sin, math.abs, math.pi

local ROW_H, TAB_H, M = 10, 9, 3
local AW, BAND = 7, 34                 -- the awning's depth, the shopfront's
-- hit args: rows 1.., the rest below
local SEG_BUY, SEG_SELL = 2001, 2002
local STEP_MINUS, STEP_PLUS, STEP_GO, CLERK, BUBBLE = 2010, 2011, 2012, 2013, 2014
local TAB_AT = 2100
local FLASH = 0.6
local CPS, SIZE, LINE = 44, 4, 5.1
local UTF8 = "[%z\1-\127\194-\244][\128-\191]*"
local IDLE = 16                        -- seconds quiet before a tip
local RICH, BROKE, BULK, RARE, BIG = 500000, 200, 10, 1000, 10000
local COINS = 9

-- (the words are keys of lang/*.lua, through env.T)
local HINTS = {
  buy = { { "A", "hint.choose" }, { "L R", "hint.tab" }, { "START", "hint.sell" } },
  sell = { { "A", "hint.choose" }, { "L R", "hint.pocket" }, { "START", "hint.buy" } },
  stepBuy = { { "< >", "hint.one" }, { "^ v", "hint.ten" }, { "A", "hint.buy" }, { "B", "hint.back" } },
  stepSell = { { "< >", "hint.one" }, { "^ v", "hint.ten" }, { "A", "hint.sell" }, { "B", "hint.back" } },
}
-- what the clerk says
local SAY = {
  morning = "mart.say.morning", day = "mart.say.day", evening = "mart.say.evening", night = "mart.say.night",
  rich = "mart.say.rich", broke = "mart.say.broke", newStock = "mart.say.newStock",
  buy = { "mart.say.buy1", "mart.say.buy2", "mart.say.buy3" },
  bulk = "mart.say.bulk", premier = "mart.say.premier",
  sell = { "mart.say.sell1", "mart.say.sell2" }, sellBig = "mart.say.sellBig", sellRare = "mart.say.sellRare",
  short = "mart.say.short", shortBank = "mart.say.shortBank", bag_full = "mart.say.bagFull",
  badges = "mart.say.badges", badgesOne = "mart.say.badgesOne", cant_sell = "mart.say.cantSell",
  gone = "mart.say.gone", toSell = "mart.say.toSell", toBuy = "mart.say.toBuy",
  tips = { "mart.say.tip1", "mart.say.tip2", "mart.say.tip3", "mart.say.tip4", "mart.say.tip5", "mart.say.tip6" },
  poke = { "mart.say.poke1", "mart.say.poke2", "mart.say.poke3" },
}
-- (a word on what was bought, by the tab it came from)
local TAB_SAY = { ["mart.balls"] = "mart.say.balls", ["mart.medicine"] = "mart.say.medicine",
                  ["mart.battle"] = "mart.say.battle", ["mart.field"] = "mart.say.field" }
-- (the Bag's pockets with nothing in them a Mart buys)
local NO_SELL = { KEY_ITEMS = true }
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

-- an item's name for a sentence: the game's capitals made into words ("POKé BALL" -> "Poké Ball")
local function nice(name)
  name = tostring(name or "")
  if name:find("%l") then return name end
  return (name:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

return function(ctx, env)
  local K, mart, T = env.K, env.mart, env.T or NO_T
  -- (pad: the shelf's item pad lights up while the window is open)
  local W = { title = "Mart", pad = true }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local st = {
    mode = "buy", focus = "list", tab = 1, tabs = {}, sellTab = 1, pockets = {}, pocketKeys = {},
    rows = {}, cursor = 1, top = 0, visible = 6, qty = 1, inBag = 0,
    badges = mart.badges(session()), flash = -10, tabKey = "",
    say = nil, lines = nil, full = false, mood = nil, moodT = -10, idleAt = now(),
    n = 0, tipN = os.time() % #SAY.tips, pokeN = 0, newFrom = 99, shakeAt = -10, lastTotal = 0,
  }
  W.state = st

  local qtyText = K.textCache(function(n) return "×" .. tostring(n) end)
  local inBagText = K.textCache(function(n) return T.f("mart.inBag", n) end)
  local needsText = K.textCache(function(n) return n == 1 and T("mart.needsOne") or T.f("mart.needs", n) end)
  local badgeText = K.textCache(function(n) return T.f("mart.badgesShort", n) end)

  local function row() return st.rows[st.cursor] end
  local function locked(r) return st.mode == "buy" and r and (r.badges or 0) > st.badges end
  local function isNew(r) return st.mode == "buy" and r and r.badges > st.newFrom and r.badges <= st.badges end
  -- (keeps the chosen row in view, unless the list was scrolled by hand since the last press: a drag
  -- or the wheel would otherwise be pulled straight back to it on the next frame)
  local function clampList(follow)
    if follow then st.free = false end
    st.cursor = max(1, min(st.cursor, #st.rows))
    local vis = st.visible
    if not st.free then
      if st.cursor > st.top + vis then st.top = st.cursor - vis end
      if st.cursor <= st.top then st.top = st.cursor - 1 end
    end
    st.top = max(0, min(st.top, max(0, #st.rows - vis)))
  end
  -- how many the stepper goes up to: as many as there are to sell; 99 to buy
  local function qtyMax()
    local r = row()
    if not r then return 1 end
    if st.mode == "sell" then return max(1, r.qty or 1) end
    return mart.MAX_QTY
  end
  local function readBag()
    local r = row()
    st.inBag = r and mart.inBag(session(), r.id) or 0
  end
  local function refresh()
    local s = session()
    if st.mode == "buy" then
      st.tabs = mart.tabs()
      st.tab = max(1, min(st.tab, #st.tabs))
      local t = st.tabs[st.tab]
      st.rows = t and t.rows or {}
      st.tabKey = t and t.key or "app.mart"
    else
      local pockets, keys = {}, {}
      for _, p in ipairs(env.inv and env.inv.pockets(s) or {}) do
        if not NO_SELL[p.id] then
          pockets[#pockets + 1] = p
          keys[#pockets] = "pocket." .. p.id
        end
      end
      st.pockets, st.pocketKeys = pockets, keys
      st.sellTab = max(1, min(st.sellTab, #pockets))
      local p = pockets[st.sellTab]
      st.rows = p and mart.sellRows(s, p.id) or {}
      st.tabKey = p and keys[st.sellTab] or "items.bag"
    end
    clampList(true)
    st.qty = max(1, min(st.qty, qtyMax()))
    readBag()
  end
  W.refresh = refresh

  -- ------- the clerk's words

  -- a line in the bubble (typed out); mood: "hop" | "shake" | "turn" | nil
  local function say(key, mood, bad, arg)
    local text = arg ~= nil and T.f(key, arg) or T(key)
    st.say = { key = key, text = text, bad = bad and true or false, t = now() }
    st.lines, st.full = nil, false
    if mood then st.mood, st.moodT = mood, now() end
    st.idleAt = now()
  end
  local function shown()
    local L, s = st.lines, st.say
    if not (L and s) then return 0 end
    if st.full then return L.n end
    return max(0, min(L.n, floor((now() - s.t - 0.12) * CPS)))
  end
  local function typing() return st.say ~= nil and (not st.lines or shown() < st.lines.n) end

  -- the greeting: the new stock a Badge brought, a full wallet or an empty one, else the time of day
  local function greet()
    local s = session()
    local money = mart.money(s)
    local seen = mart.seen and mart.seen()
    if mart.see then mart.see(st.badges) end
    if seen and st.badges > seen then
      st.newFrom = seen
      for _, t in ipairs(mart.tabs()) do
        for _, r in ipairs(t.rows) do
          if r.badges > seen and r.badges <= st.badges then return say(SAY.newStock, "hop", false, nice(r.name)) end
        end
      end
    end
    if money >= RICH then return say(SAY.rich, "hop") end
    if money < BROKE then return say(SAY.broke) end
    local h = tonumber(os.date("%H")) or 12
    if h >= 5 and h < 12 then say(SAY.morning)
    elseif h >= 12 and h < 18 then say(SAY.day)
    elseif h >= 18 and h < 22 then say(SAY.evening)
    else say(SAY.night) end
  end

  -- why not, in the clerk's words (the Bank named when it holds what's missing)
  local function refuse(why, r)
    se("SE_FAILURE")
    st.shakeAt = now()
    if why == "badges" then
      local n = r and r.badges or 1
      if n == 1 then return say(SAY.badgesOne, "shake", true) end
      return say(SAY.badges, "shake", true, n)
    end
    if why == "money" then
      local Bk, apps = env.bank, env.apps
      local need = (r and r.price or 0) * st.qty - mart.money(session())
      local has = Bk and Bk.balance and (not (apps and apps.isInstalled) or apps.isInstalled("bank"))
      if has and Bk.balance() >= need then return say(SAY.shortBank, "shake", true) end
      return say(SAY.short, "shake", true)
    end
    say(SAY[why] or SAY.gone, "shake", true)
  end

  -- a tip when it's been quiet a while (from W.input: the draw makes nothing)
  local function idle()
    if st.focus ~= "list" or typing() or now() - st.idleAt < IDLE then return end
    st.tipN = st.tipN % #SAY.tips + 1
    say(SAY.tips[st.tipN])
  end

  -- ------- choosing

  local function setCursor(c)
    c = max(1, min(#st.rows, c))
    if c ~= st.cursor and #st.rows > 0 then
      st.cursor, st.qty, st.focus = c, 1, "list"
      clampList(true)
      readBag()
      se("SE_SELECT")
    end
  end
  local function setTab(i)
    local n = st.mode == "buy" and #st.tabs or #st.pockets
    if n == 0 then return end
    i = (i - 1) % n + 1
    local cur = st.mode == "buy" and st.tab or st.sellTab
    if i == cur then return end
    if st.mode == "buy" then st.tab = i else st.sellTab = i end
    st.cursor, st.top, st.qty, st.focus = 1, 0, 1, "list"
    refresh()
    se("SE_SELECT")
  end
  local function setMode(mode)
    if st.mode == mode then return end
    st.mode, st.cursor, st.top, st.qty, st.focus = mode, 1, 0, 1, "list"
    refresh()
    se("SE_SELECT")
    say(mode == "sell" and SAY.toSell or SAY.toBuy, "turn")
  end
  local function stepBy(d)
    local q = max(1, min(qtyMax(), st.qty + d))
    if q ~= st.qty then
      st.qty = q
      se("SE_SELECT")
    end
  end
  -- SELECT in the stepper: all of them (selling), as many as the money buys (buying)
  local function stepAll()
    local r = row()
    if not r then return end
    if st.mode == "sell" then
      st.qty = qtyMax()
    else
      st.qty = max(1, min(mart.MAX_QTY, floor(mart.money(session()) / max(1, r.price))))
    end
    se("SE_SELECT")
  end

  -- buy or sell st.qty of the chosen item
  local function act()
    local r = row()
    if not r then return end
    local s = session()
    if locked(r) then return refuse("badges", r) end
    local qty = st.qty
    if st.mode == "buy" then
      local before = mart.money(s)
      local ok, got = mart.buy(s, r.id, qty, st.badges)
      if not ok then
        if got == "money" then st.flash = now() end
        return refuse(got, r)
      end
      -- (it appears on the pad, then goes up into the Bag)
      if env.pad and env.pad.transfer then pcall(env.pad.transfer, r.id, "in") end
      se("SE_SHOP")
      st.lastTotal = before - mart.money(s)
      st.coins = { t = now(), out = false }
      st.fly = { t = now(), id = r.id, sell = false, n = min(qty, 5) }
      st.n = st.n + 1
      if got then say(SAY.premier, "hop")
      elseif qty >= BULK then say(SAY.bulk, "hop", false, qty)
      elseif st.n % 2 == 1 and TAB_SAY[st.tabKey] then say(TAB_SAY[st.tabKey], "hop")
      else say(SAY.buy[floor(st.n / 2) % #SAY.buy + 1], "hop", false, nice(r.name)) end
    else
      local ok, got = mart.sell(s, r.id, qty)
      if not ok then return refuse(got, r) end
      if env.pad and env.pad.transfer then pcall(env.pad.transfer, r.id, "out") end
      se("SE_SHOP")
      st.lastTotal = got
      st.coins = { t = now(), out = true }
      st.fly = { t = now(), id = r.id, sell = true, n = min(qty, 5) }
      st.n = st.n + 1
      if (r.price or 0) >= RARE then say(SAY.sellRare, "hop", false, nice(r.name))
      elseif got >= BIG then say(SAY.sellBig, "hop")
      else say(SAY.sell[st.n % #SAY.sell + 1], "hop") end
    end
    st.qty, st.focus = 1, "list"
    refresh()
  end
  -- A on an item: how many (a locked or unsellable one: the clerk says why)
  local function begin()
    local r = row()
    if not r then return end
    if locked(r) then return refuse("badges", r) end
    if st.mode == "sell" and not r.price then return refuse("cant_sell", r) end
    st.focus = "step"
    se("SE_SELECT")
  end
  local function poke()
    st.pokeN = st.pokeN % #SAY.poke + 1
    se("SE_SELECT")
    say(SAY.poke[st.pokeN], "hop")
  end

  -- ------- buttons

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  function W.input(input, nav)
    cur = input
    if nav.up or nav.down or nav.left or nav.right then st.idleAt, st.keys = now(), true end
    idle()
    if st.focus == "step" then
      if nav.right then stepBy(1)
      elseif nav.left then stepBy(-1)
      elseif nav.up then stepBy(10)
      elseif nav.down then stepBy(-10)
      elseif pressed("select") then stepAll()
      elseif pressed("a") then act()
      elseif pressed("b") then
        st.focus = "list"
        se("SE_SELECT")
      end
      return true
    end
    if pressed("b") then return false end
    if nav.up then setCursor(st.cursor - 1)
    elseif nav.down then setCursor(st.cursor + 1)
    elseif pressed("l") then setTab((st.mode == "buy" and st.tab or st.sellTab) - 1)
    elseif pressed("r") then setTab((st.mode == "buy" and st.tab or st.sellTab) + 1)
    elseif pressed("start") then setMode(st.mode == "buy" and "sell" or "buy")
    elseif pressed("a") then
      st.keys = true
      begin()
    end
    return true
  end

  function W.tap(arg)
    if type(arg) ~= "number" then return end
    st.idleAt, st.keys = now(), false
    if arg == SEG_BUY then return setMode("buy") end
    if arg == SEG_SELL then return setMode("sell") end
    if arg == CLERK then return poke() end
    if arg == BUBBLE then
      if typing() then st.full = true end
      return
    end
    if arg > TAB_AT and arg <= TAB_AT + 20 then return setTab(arg - TAB_AT) end
    if arg == STEP_MINUS or arg == STEP_PLUS then
      local r = row()
      if not r or locked(r) or (st.mode == "sell" and not r.price) then return end
      st.focus = "step"
      return stepBy(arg == STEP_PLUS and 1 or -1)
    end
    if arg == STEP_GO then return act() end
    if st.rows[arg] then
      if st.cursor == arg then
        if st.focus == "list" then return begin() end
        return
      end
      setCursor(arg)
    end
  end

  function W.scroll(dy)
    st.free, st.idleAt = true, now()
    st.top = max(0, min(max(0, #st.rows - st.visible), st.top - dy / ROW_H))
  end

  function W.hints()
    if st.focus == "step" then return T.list(st.mode == "buy" and HINTS.stepBuy or HINTS.stepSell) end
    return T.list(st.mode == "buy" and HINTS.buy or HINTS.sell)
  end

  -- ------- drawing (no tables made here)

  -- a corner shop at dusk: Mart blue, a striped awning, shelves of goods behind the counter
  local BG_TOP, BG_FOOT = { 34, 98, 196 }, { 9, 24, 66 }
  local MART, MART_DEEP = { 56, 136, 250 }, { 22, 74, 196 }
  local AWN_WHITE = { 244, 248, 255 }
  local WHITE, SOFT, FAINT = { 255, 255, 255 }, { 204, 220, 248 }, { 128, 150, 198 }
  local INK, BUBBLE_C = { 22, 36, 76 }, { 250, 252, 255 }
  local GLASS, EDGE = { 255, 255, 255, 0.07 }, { 255, 255, 255, 0.13 }
  local GOLD, GOLD_FOOT = { 255, 222, 128 }, { 196, 146, 44 }
  local RED, RED_DEEP = { 255, 96, 108 }, { 176, 30, 52 }
  local GREEN, GREEN_DEEP = { 86, 230, 152 }, { 18, 150, 96 }
  local COUNTER_TOP, COUNTER_FOOT = { 250, 252, 255 }, { 190, 206, 236 }
  local TILL_TOP, TILL_FOOT, LCD, LCD_INK = { 70, 84, 120 }, { 34, 42, 70 }, { 20, 52, 40 }, { 120, 255, 170 }
  local SHADE = { 0, 0, 0 }
  local TAB_C = { { 255, 104, 104 }, { 96, 226, 170 }, { 255, 178, 74 }, { 124, 184, 255 } }
  local POCKET_C = { ITEMS = { 124, 184, 255 }, POKE_BALLS = { 255, 104, 104 }, TM_CASE = { 255, 178, 74 },
                     BERRY_POUCH = { 150, 222, 98 } }
  local GOODS = { { 255, 104, 104 }, { 96, 226, 170 }, { 255, 178, 74 }, { 124, 184, 255 }, { 255, 222, 128 },
                  { 200, 146, 255 } }

  local function ease(k) k = min(1, max(0, k)) return 1 - (1 - k) * (1 - k) * (1 - k) end
  local function money(n, x, y, size, c, right)
    if not env.amount then return 0 end
    local ok, w = pcall(env.amount, n, 0, 0, size, c, true)
    w = ok and tonumber(w) or 0
    pcall(env.amount, n, right and x - w or x, y, size, c)
    return w
  end
  local function glass(b, rad)
    K.col(GLASS)
    K.box("fill", b, rad)
    K.ring(b, rad, EDGE, 1, 0.4)
  end
  local function tabColor(i)
    if st.mode == "buy" then return TAB_C[(i - 1) % #TAB_C + 1] end
    local p = st.pockets[i]
    return p and POCKET_C[p.id] or TAB_C[4]
  end
  local function curColor() return tabColor(st.mode == "buy" and st.tab or st.sellTab) end
  -- a small padlock, `s` units tall, its top left at x, y
  local function padlock(x, y, s, c, a)
    local G = K.graphics()
    K.col(c, a)
    K.box("fill", K.R(x, y + s * 0.42, s * 0.8, s * 0.58), s * 0.12)
    G.setLineWidth(max(1, s * 0.13 * K.sc))
    G.arc("line", "open", K.X(x + s * 0.4), K.Y(y + s * 0.42), s * 0.26 * K.sc, pi, pi * 2)
  end
  local function newTag(x, y)
    local word = T("mart.new")
    local w = K.width(word, 2.8) + 3
    K.grad(K.R(x, y, w, 4.2), 2.1, GOLD, GOLD_FOOT)
    K.bold(word, x, y + 0.55, 2.8, INK, "center", w)
    return w
  end

  -- the shop behind everything: the room's light, the ceiling lamps, two shelves of goods
  local function drawShop(x, y, w, h, clock)
    K.grad(K.R(x, y, w, h), 0, BG_TOP, BG_FOOT)
    for i = 0, 2 do
      K.glow(x + w * (0.18 + i * 0.32), y + AW + 2, w * 0.16, BAND * 0.8, WHITE, 0.07 + 0.02 * sin(clock * 1.3 + i))
    end
    K.glow(x + w * 0.5, y + h, w * 0.6, h * 0.4, MART, 0.12)
    for s = 0, 1 do
      local sy = y + AW + 10 + s * 10
      local gx, i = x + 1.5 + s * 1.7, s * 7
      while gx < x + w - 3 do
        local gw = 2.2 + (i * 7 % 5) * 0.45
        local gh = 2.8 + (i * 5 % 4) * 1.05
        K.col(GOODS[i % #GOODS + 1], 0.3)
        K.box("fill", K.R(gx, sy - gh, gw, gh), 0.5)
        K.col(WHITE, 0.08 + 0.07 * sin(clock * 1.7 + i * 1.3))
        K.box("fill", K.R(gx + 0.4, sy - gh + 0.4, 0.45, gh - 0.8))
        gx = gx + gw + 0.9 + (i * 3 % 3) * 0.5
        i = i + 1
      end
      K.col(WHITE, 0.14)
      K.box("fill", K.R(x, sy, w, 0.7))
      K.col(SHADE, 0.2)
      K.box("fill", K.R(x, sy + 0.7, w, 0.8))
    end
  end

  -- the awning: Mart blue and white stripes, scalloped, a glint running along it now and then
  local function drawAwning(x, y, w, clock)
    local G = K.graphics()
    local sw, d = 9, AW - 3.5
    K.col(SHADE, 0.22)
    K.box("fill", K.R(x, y + d, w, 3.5))
    local n = floor(w / sw) + 1
    for i = 0, n - 1 do
      local sx = x + i * sw
      local c = i % 2 == 0 and MART or AWN_WHITE
      K.grad(K.R(sx, y, sw, d), 0, c, K.dark(c, 0.14))
      K.col(K.dark(c, 0.14))
      G.arc("fill", "pie", K.X(sx + sw / 2), K.Y(y + d), (sw / 2) * K.sc, 0, pi, 14)
    end
    local p = (clock * 0.22) % 1.8
    if p < 1 then
      local gx = x - 12 + p * (w + 24)
      K.col(WHITE, 0.3 * sin(p * pi))
      G.polygon("fill", K.X(gx), K.Y(y), K.X(gx + 5), K.Y(y), K.X(gx + 2), K.Y(y + d), K.X(gx - 3), K.Y(y + d))
    end
  end

  -- the clerk: the game's sprite at whole pixels; a hop for a sale, a shake of the head for a no, a
  -- turn round for Buy / Sell, a glance along the shelves now and then, a nod while talking
  local function drawClerk(cx, foot, hU, clock)
    local spr = env.clerk and env.clerk()
    local sw0, sh0 = spr and (spr.width or spr.w), spr and (spr.height or spr.h)
    if not (spr and spr.image and spr.quads and sw0 and sh0) then return end
    local G = K.graphics()
    local px = max(1, floor(hU * K.sc / sh0 + 0.5))
    local t = now() - st.moodT
    local frame, flip, lift = 0, false, 0
    if st.mood == "hop" and t < 0.7 then
      lift = abs(sin(t / 0.35 * pi)) * 2.4 * (1 - t / 1.4)
    elseif st.mood == "shake" and t < 0.6 then
      frame, flip = 2, floor(t / 0.12) % 2 == 1
    elseif st.mood == "turn" and t < 0.5 then
      local q = floor(t / 0.125)
      if q == 0 then frame = 2 elseif q == 1 then frame = 1 elseif q == 2 then frame, flip = 2, true end
    else
      local p = clock % 9
      if p > 6.4 and p < 7.3 then frame = 2 elseif p >= 7.3 and p < 8.2 then frame, flip = 2, true end
    end
    if frame >= (spr.frameCount or 1) or not spr.quads[frame] then frame, flip = 0, false end
    local sw, sh = sw0 * px, sh0 * px
    local nod = (typing() and floor(clock * 7) % 2 == 1) and px or 0
    local X = floor(K.X(cx) - sw / 2 + 0.5)
    local Y = floor(K.Y(foot - lift) - sh + 0.5) + nod
    G.setColor(1, 1, 1, 1)
    if flip then
      G.draw(spr.image, spr.quads[frame], X + sw, Y, 0, -px, px)
    else
      G.draw(spr.image, spr.quads[frame], X, Y, 0, px, px)
    end
    K.addHit(K.R(cx - sw / K.sc / 2, foot - sh / K.sc, sw / K.sc, sh / K.sc), "win", CLERK)
    st.headY = foot - sh / K.sc * 0.78
  end

  -- the counter, the clerk behind it (seen from the chest up), the till on it (its drawer out when
  -- coins land)
  local function drawCounter(x, y, w, clock)
    local G = K.graphics()
    local top = y + BAND - 8
    local cx = x + 12
    st.headY = top - 14
    K.glow(cx, top - 10, 14, 13, MART, 0.3)
    drawClerk(cx, top + 3, BAND - 8, clock)
    local cb = K.R(x, top, w, 8)
    K.shadow(cb, 2, 1, 0.35)
    K.grad(cb, 2, COUNTER_TOP, COUNTER_FOOT)
    K.col(MART)
    K.box("fill", K.R(x, top + 2.8, w, 3.2))
    K.col(WHITE, 0.7)
    K.box("fill", K.R(x + 1.5, top + 0.5, w - 3, 0.5), 0.25)
    if K.drawLogo then K.drawLogo(K.X(x + w / 2), K.Y(top + 4.4), 4.4 * K.sc, WHITE, 0.95) end
    -- (the till)
    local tw, th = 14, 9
    local tx, ty = x + w - tw - 2, top - th + 0.6
    local c = st.coins
    local age = c and now() - c.t or 9
    local open = (age > 0.35 and age < 1.3) and sin(min(1, (age - 0.35) / 0.95) * pi) or 0
    if open > 0 then
      K.grad(K.R(tx + 1, ty + th - 1 + open * 2.4, tw - 2, 2.6), 0.6, GOLD, GOLD_FOOT)
    end
    K.grad(K.R(tx, ty, tw, th), 1.4, TILL_TOP, TILL_FOOT)
    K.col(LCD)
    local lb = K.R(tx + 1.2, ty + 1.1, tw - 2.4, 3.6)
    K.box("fill", lb, 0.6)
    money(st.lastTotal, lb[1] + lb[3] - 0.6, lb[2] + 0.55, 2.4, LCD_INK, true)
    for k = 0, 5 do
      K.col(WHITE, 0.32)
      G.circle("fill", K.X(tx + 3 + (k % 3) * 2.6), K.Y(ty + 6 + floor(k / 3) * 1.6), 0.5 * K.sc)
    end
    K.col(c and age < 0.8 and GOLD or GREEN, 0.9)
    G.circle("fill", K.X(tx + tw - 2.4), K.Y(ty + 6.8), 0.7 * K.sc)
    st.tillX, st.tillY = tx + tw / 2, ty + 1
    st.counterX, st.counterY = cx + 6, top - 3
  end

  -- the words, as lines that fit with each line's typed-out beginnings (made when the words or the
  -- width change, never on other frames); a word wider than the line breaks between its letters
  local function linesOf(text, w, size)
    local lines, line = {}, ""
    for word in tostring(text or ""):gmatch("%S+") do
      if K.width(word, size) > w then
        local acc = line == "" and "" or (line .. " ")
        for ch in word:gmatch(UTF8) do
          local try = acc .. ch
          if acc ~= "" and K.width(try, size) > w then
            lines[#lines + 1] = acc
            acc = ch
          else
            acc = try
          end
        end
        line = acc
      else
        local try = line == "" and word or (line .. " " .. word)
        if line ~= "" and K.width(try, size) > w then
          lines[#lines + 1] = line
          line = word
        else
          line = try
        end
      end
    end
    if line ~= "" then lines[#lines + 1] = line end
    local out = { lines = lines, pre = {}, count = {}, n = 0, size = size, line = LINE * size / SIZE }
    for j, l in ipairs(lines) do
      local pre, k, acc = {}, 0, ""
      for ch in l:gmatch(UTF8) do
        k = k + 1
        acc = acc .. ch
        pre[k] = acc
      end
      out.pre[j], out.count[j], out.n = pre, k, out.n + k
    end
    return out
  end

  -- the speech bubble: it pops up with each line, its tail at the clerk, the words typed out
  local function drawBubble(x, y, w, h, clock)
    local s = st.say
    if not s or w < 20 then return end
    local G = K.graphics()
    local k = ease((now() - s.t) / 0.2)
    local by = y + (1 - k) * 2.5
    local b = K.R(x, by, w, h)
    K.shadow(b, 4, 1.2, 0.4 * k)
    K.col(BUBBLE_C, k)
    K.box("fill", b, 4)
    local ty = min(max(st.headY or (y + h / 2), by + 4), by + h - 4)
    G.polygon("fill", K.X(x + 0.6), K.Y(ty - 2.6), K.X(x - 4.2), K.Y(ty + 0.4), K.X(x + 0.6), K.Y(ty + 2.6))
    if s.bad then K.ring(b, 4, RED, 0.85 * k, 0.55) end
    local nm = T("mart.clerk")
    local nw = K.width(nm, 3) + 5
    K.grad(K.R(x + 4, by - 2.4, nw, 4.8), 2.4, s.bad and RED or MART, s.bad and RED_DEEP or MART_DEEP)
    K.bold(nm, x + 4, by - 1.7, 3, WHITE, "center", nw, k)
    -- (the words: made again when they or the width change; smaller when they'd overflow)
    local tw = w - 8
    local L = st.lines
    if not L or st.linesW ~= floor(tw) or st.linesText ~= s.text then
      L = linesOf(s.text, tw, SIZE)
      if #L.lines * L.line > h - 4 then L = linesOf(s.text, tw, SIZE * 0.84) end
      st.lines, st.linesW, st.linesText = L, floor(tw), s.text
    end
    local left = shown()
    local total = #L.lines * L.line
    local ly = by + max(2.8, (h - total) / 2 + 0.4)
    for j = 1, #L.lines do
      if ly + L.line > by + h + 0.5 then break end
      local cnt = L.count[j]
      if left >= cnt then
        K.text(L.lines[j], x + 4, ly, L.size, INK, nil, nil, k)
        left = left - cnt
      else
        local cw = 0
        if left > 0 then
          K.text(L.pre[j][left], x + 4, ly, L.size, INK, nil, nil, k)
          cw = K.width(L.pre[j][left], L.size)
        end
        K.col(s.bad and RED or MART, 0.5 + 0.5 * abs(sin(clock * 8)))
        K.box("fill", K.R(x + 4 + cw + 0.4, ly + 0.3, 0.6, L.size * 1.1))
        break
      end
      ly = ly + L.line
    end
    K.addHit(b, "win", BUBBLE)
  end

  -- Buy | Sell: a pill, its light sliding to the chosen side (blue to buy, green to sell)
  local function drawSwitch(x, y, w, h)
    local b = K.R(x, y, w, h)
    K.col(WHITE, 0.1)
    K.box("fill", b, h / 2)
    local want = st.mode == "buy" and 0 or 1
    local dt = st.swT and min(0.1, max(0, now() - st.swT)) or 0
    st.swT = now()
    st.swK = (st.swK or want) + (want - (st.swK or want)) * min(1, dt * 12)
    local half = (w - 1) / 2
    local hb = K.R(x + 0.5 + half * st.swK, y + 0.5, half, h - 1)
    if st.mode == "buy" then K.grad(hb, (h - 1) / 2, MART, MART_DEEP) else K.grad(hb, (h - 1) / 2, GREEN, GREEN_DEEP) end
    local l1, l2 = T("mart.buy"), T("mart.sell")
    local fs = 4.2
    K.bold(l1, x, y + (h - fs * 1.2) / 2, K.fit(l1, fs, half - 3), st.mode == "buy" and WHITE or SOFT, "center", half)
    K.bold(l2, x + half, y + (h - fs * 1.2) / 2, K.fit(l2, fs, half - 3), st.mode == "sell" and WHITE or SOFT, "center", half)
    K.addHit(K.R(x, y, half, h), "win", SEG_BUY)
    K.addHit(K.R(x + half, y, half, h), "win", SEG_SELL)
  end

  -- the money: a coin, the amount counting to what it is (red a moment when it falls short)
  local function drawMoney(x, y, w, h)
    local G = K.graphics()
    local b = K.R(x, y, w, h)
    glass(b, h / 2)
    local cx, cy = x + h / 2 + 0.5, y + h / 2
    K.col(GOLD_FOOT)
    G.circle("fill", K.X(cx), K.Y(cy), (h / 2 - 1.6) * K.sc)
    K.col(GOLD)
    G.circle("fill", K.X(cx), K.Y(cy), (h / 2 - 2.3) * K.sc)
    local target = mart.money(session())
    local dt = st.mT and min(0.1, max(0, now() - st.mT)) or 0
    st.mT = now()
    st.shownM = st.shownM and (st.shownM + (target - st.shownM) * min(1, dt * 5)) or target
    if abs(target - st.shownM) < 1 then st.shownM = target end
    local flash = now() - st.flash < FLASH
    local size = K.fit("0000000", 4.6, w - h - 3)
    money(floor(st.shownM + 0.5), x + w - h / 2, y + (h - size * 1.15) / 2, size, flash and RED or GOLD, true)
    st.moneyX, st.moneyY = cx, cy
  end

  -- the tabs: one chip each, the light sliding to the chosen one in its colour
  local function drawTabs(x, y, w, h)
    local n = st.mode == "buy" and #st.tabs or #st.pockets
    if n == 0 then return end
    local cw = w / n
    local want = (st.mode == "buy" and st.tab or st.sellTab) - 1
    local dt = st.tabT and min(0.1, max(0, now() - st.tabT)) or 0
    st.tabT = now()
    if st.tabMode ~= st.mode then st.tabK, st.tabMode = want, st.mode end
    st.tabK = (st.tabK or want) + (want - (st.tabK or want)) * min(1, dt * 14)
    local c = curColor()
    local hb = K.R(x + st.tabK * cw + 0.6, y + 0.6, cw - 1.2, h - 1.2)
    K.col(c, 0.28)
    K.box("fill", hb, (h - 1.2) / 2)
    K.ring(hb, (h - 1.2) / 2, c, 0.8, 0.45)
    for i = 1, n do
      local key = st.mode == "buy" and st.tabs[i].key or st.pocketKeys[i]
      local label = T(key)
      local on = i - 1 == want
      local fs = K.fit(label, 3.6, cw - 3)
      K.bold(label, x + (i - 1) * cw, y + (h - fs * 1.2) / 2, fs, on and WHITE or SOFT, "center", cw)
      K.addHit(K.R(x + (i - 1) * cw, y, cw, h), "win", TAB_AT + i)
    end
  end

  local function drawList(x, y, w, h, focused, clock)
    local G = K.graphics()
    local clip = K.R(x, y, w, h)
    K.scissor(clip)
    local top = st.top
    local first = floor(top) + 1
    local last = min(#st.rows, first + st.visible + 1)
    local sell = st.mode == "sell"
    local tc = curColor()
    for i = first, last do
      local r = st.rows[i]
      local ry = y + (i - 1 - top) * ROW_H
      local rb = K.R(x + 1.5, ry + 0.4, w - 3, ROW_H - 0.8)
      local on = i == st.cursor
      local off = locked(r) or (sell and not r.price)
      if on then
        K.col(tc, focused and (0.26 + 0.06 * sin(clock * 4)) or 0.14)
        K.box("fill", rb, 3)
        K.ring(rb, 3, tc, focused and 0.75 or 0.3, 0.45)
        K.col(tc)
        K.box("fill", K.R(rb[1] + 0.7, rb[2] + 2, 0.9, rb[4] - 4), 0.45)
      elseif i > first then
        K.col(WHITE, 0.06)
        K.box("fill", K.R(x + 14, ry, w - 17, 0.3))
      end
      K.col(tc, off and 0.07 or (on and 0.3 or 0.15))
      G.circle("fill", K.X(x + 8), K.Y(ry + ROW_H / 2), 4.1 * K.sc)
      if env.itemIcon then pcall(env.itemIcon, r.id, x + 4, ry + 1, 8, off and 0.45 or 1) end
      local rw = 0
      if locked(r) then
        local bt = badgeText(r.badges)
        rw = K.width(bt, 3.8) + 7
        local lb = K.R(x + w - 4 - rw, ry + 2.3, rw, 5.4)
        K.col(WHITE, 0.08)
        K.box("fill", lb, 2.7)
        padlock(lb[1] + 1.4, lb[2] + 0.8, 3.6, FAINT)
        K.text(bt, lb[1] + 5, lb[2] + 1, 3.8, FAINT)
      elseif r.price then
        rw = money(r.price, x + w - 4, ry + 2.7, 4.3, off and FAINT or GOLD, true)
      end
      if sell then
        local qt = qtyText(r.qty)
        local qw = K.width(qt, 3.8)
        K.text(qt, x + w - 7 - rw - qw, ry + 3, 3.8, SOFT)
        rw = rw + qw + 3
      end
      local nx = x + 14
      if isNew(r) then nx = nx + newTag(nx, ry + 2.9) + 1.5 end
      local ns = K.fit(r.name, 4.5, x + w - 6 - rw - nx)
      K.text(r.name, nx, ry + 2.7 + (4.5 - ns) * 0.5, ns, off and FAINT or WHITE)
      K.addHit(rb, "win", i, clip)
    end
    if #st.rows == 0 then
      K.text(T(sell and "items.emptyPocket" or "mart.soldOut"), x, y + h / 2 - 3, 4.4, FAINT, "center", w)
    end
    K.scrollbar(x + w, y, h, top, st.visible, #st.rows)
    K.scissor(st.clip)
  end

  -- the list's card: the tabs, the rows
  local function drawListPane(x, y, w, h, focused, clock)
    glass(K.R(x, y, w, h), 5)
    drawTabs(x + 1.5, y + 1.5, w - 3, TAB_H)
    local top = y + TAB_H + 3
    st.visible = max(1, floor((y + h - 1 - top) / ROW_H))
    clampList()
    drawList(x, top, w, y + h - 1 - top, focused, clock)
  end

  -- the stepper: - and + either side of how many (bumping as it changes), the total on the right
  local function drawStepper(x, y, w, stepping, short, total)
    local G = K.graphics()
    local sb = K.R(x, y, 32, 10)
    K.col(WHITE, 0.09)
    K.box("fill", sb, 5)
    for side = 0, 1 do
      local cx = side == 0 and sb[1] + 5 or sb[1] + sb[3] - 5
      K.col(WHITE, 0.16)
      G.circle("fill", K.X(cx), K.Y(sb[2] + 5), 3.7 * K.sc)
      K.col(WHITE)
      K.box("fill", K.R(cx - 1.6, sb[2] + 4.65, 3.2, 0.7), 0.35)
      if side == 1 then K.box("fill", K.R(cx - 0.35, sb[2] + 3.4, 0.7, 3.2), 0.35) end
    end
    K.addHit(K.R(sb[1], sb[2], 16, 10), "win", STEP_MINUS)
    K.addHit(K.R(sb[1] + 16, sb[2], 16, 10), "win", STEP_PLUS)
    if st.qty ~= st.lastQty then st.lastQty, st.bumpAt = st.qty, now() end
    local bump = max(0, 1 - (now() - (st.bumpAt or -10)) / 0.22)
    local qs = 4.6 * (1 + 0.18 * bump)
    K.bold(qtyText(st.qty), sb[1] + 9, sb[2] + (10 - qs * 1.2) / 2, qs, WHITE, "center", 14)
    if stepping and st.keys then K.focusRing(sb, 5) end
    local sh = now() - st.shakeAt
    local dx = sh < 0.4 and sin(sh * 55) * 1.3 * (1 - sh / 0.4) or 0
    money(total, x + w + dx, y + 2.4, 5.2, short and RED or GOLD, true)
  end

  -- the button: lit and breathing when it can be done
  local function drawGo(b, label, on, sell, stepping, clock)
    if on then
      K.col(sell and GREEN or MART, 0.2 + 0.12 * sin(clock * 3))
      K.box("fill", K.R(b[1] - 1, b[2] - 1, b[3] + 2, b[4] + 2), b[4] / 2 + 1)
      if sell then K.grad(b, b[4] / 2, GREEN, GREEN_DEEP) else K.grad(b, b[4] / 2, MART, MART_DEEP) end
    else
      K.col(WHITE, 0.08)
      K.box("fill", b, b[4] / 2)
    end
    if stepping and st.keys then K.focusRing(b, b[4] / 2) end
    K.bold(label, b[1], b[2] + (b[4] - 4.8 * 1.2) / 2, K.fit(label, 4.8, b[3] - 6), on and WHITE or FAINT, "center", b[3])
    K.addHit(b, "win", STEP_GO)
  end

  -- the chosen item on its lit stand: the picture bobbing, its name, how many are in the Bag, its
  -- words when there's room; how many, the total and Buy / Sell at the foot (or why it can't be had)
  local function drawDetail(x, y, w, h, clock)
    local G = K.graphics()
    glass(K.R(x, y, w, h), 5)
    local r = row()
    if not r then return end
    local tc = curColor()
    local big = h >= 60
    local is = big and 16 or 11
    local sx, sy = x + 4 + is / 2 + 1, y + 3 + is / 2 + 1
    K.glow(sx, sy, is * 0.95, is * 0.8, tc, 0.32)
    K.col(SHADE, 0.28)
    G.ellipse("fill", K.X(sx), K.Y(sy + is * 0.55), is * 0.42 * K.sc, is * 0.1 * K.sc)
    local bob = sin(clock * 2.2) * 0.7
    if env.itemIcon then pcall(env.itemIcon, r.id, sx - is / 2, sy - is / 2 + bob - 0.6, is) end
    st.standX, st.standY = sx, sy
    local tx = x + is + 9
    local nx = tx
    if isNew(r) then nx = nx + newTag(nx, y + 4.6) + 1.5 end
    local ns = K.fit(r.name, 5, x + w - 4 - nx)
    K.bold(r.name, nx, y + 4 + (5 - ns) * 0.5, ns, WHITE)
    -- (in the Bag: a little chip)
    local bt = inBagText(st.inBag)
    local bw = K.width(bt, 3.5) + 4
    K.col(tc, 0.18)
    K.box("fill", K.R(tx, y + 10.6, bw, 5), 2.5)
    K.text(bt, tx + 2, y + 11.3, 3.5, SOFT)
    if big and r.desc ~= "" then
      -- (the words, as many whole lines as fit above the stepper)
      local dy = y + is + 8
      local lh = K.font(3.8 * K.sc):getHeight() / K.sc
      local n = floor((h - (dy - y) - 28) / lh)
      if n >= 1 then
        K.scissor(K.R(x, dy, w, n * lh + 0.2))
        K.text(r.desc, x + 4, dy, 3.8, SOFT, "left", w - 8)
        K.scissor(st.clip)
      end
    end
    local go = K.R(x + 4, y + h - 13, w - 8, 10)
    local sell = st.mode == "sell"
    local stepping = st.focus == "step"
    if locked(r) then
      -- (the Badges it needs: a padlock, the words, a pip for each of the eight)
      padlock(x + 4, y + h - 27, 4.4, RED)
      K.text(needsText(r.badges), x + 10, y + h - 26.6, 3.8, RED, "left", w - 14)
      for i = 1, 8 do
        local on = i <= st.badges
        local need = i <= r.badges
        K.col(on and GOLD or (need and RED or WHITE), on and 1 or (need and 0.45 or 0.14))
        G.circle("fill", K.X(x + 6 + (i - 1) * 4), K.Y(y + h - 18.5), 1.3 * K.sc)
      end
      drawGo(go, T("mart.buy"), false, false, false, clock)
      return
    end
    if sell and not r.price then
      K.text(T("reason.mart.cant_sell"), x + 4, y + h - 25.5, 3.8, FAINT, "left", w - 8)
      drawGo(go, T("mart.sell"), false, true, false, clock)
      return
    end
    local total = (r.price or 0) * st.qty
    local short = not sell and total > mart.money(session())
    drawStepper(x + 4, y + h - 26, w - 8, stepping, short, total)
    drawGo(go, T(sell and "mart.sell" or "mart.buy"), not short, sell, stepping, clock)
  end

  -- the item flying (the clerk's hands to the stand when bought, the stand to the clerk when sold),
  -- coins flying (the money to the till, the till to the money); each from its number and the time
  local function drawFlying(clock)
    local f = st.fly
    if f then
      local age = now() - f.t
      if age > 1 then
        st.fly = nil
      elseif st.standX and st.counterX then
        local ax, ay, bx, by = st.counterX, st.counterY, st.standX, st.standY
        if f.sell then ax, ay, bx, by = st.standX, st.standY, st.counterX, st.counterY end
        for i = 1, f.n do
          local k = ease((age - (i - 1) * 0.08) / 0.55)
          if k > 0 and k < 1 then
            local px = ax + (bx - ax) * k
            local py = ay + (by - ay) * k - sin(k * pi) * 12
            local sz = 8 * (1 + 0.3 * sin(k * pi))
            if env.itemIcon then pcall(env.itemIcon, f.id, px - sz / 2, py - sz / 2, sz, 1 - 0.25 * k) end
          end
        end
      end
    end
    local c = st.coins
    if not c then return end
    local age = now() - c.t
    if age > 1.3 then st.coins = nil return end
    if not (st.moneyX and st.tillX) then return end
    local G = K.graphics()
    local fx, fy, tx, ty = st.moneyX, st.moneyY, st.tillX, st.tillY
    if c.out then fx, fy, tx, ty = st.tillX, st.tillY, st.moneyX, st.moneyY end
    for i = 1, COINS do
      local k = ease((age - i * 0.045) / 0.7)
      if k > 0 and k < 1 then
        local lift = sin(k * pi) * (10 + (i % 3) * 3)
        local spread = (i - COINS / 2) * 1.4 * sin(k * pi)
        local px, py = fx + (tx - fx) * k + spread, fy + (ty - fy) * k - lift
        local rr = 2 * (1 - 0.3 * k)
        local spin = abs(math.cos(clock * 8 + i))
        K.col(GOLD_FOOT, 1 - k * 0.3)
        G.ellipse("fill", K.X(px), K.Y(py), rr * max(0.2, spin) * K.sc, rr * K.sc)
        K.col(GOLD, 1 - k * 0.3)
        G.ellipse("fill", K.X(px), K.Y(py), (rr - 0.5) * max(0.15, spin) * K.sc, (rr - 0.5) * K.sc)
      end
    end
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    st.clip = body
    K.scissor(body)
    drawShop(x, y, w, h, clock)
    local cw = 40
    drawCounter(x + M, y, cw, clock)
    -- (the awning in front: the clerk stands under it)
    drawAwning(x, y, w, clock)
    local focused = st.focus == "list"
    local wide = not portrait and w >= 200
    local bx = x + M + cw + 6
    local by, bh = y + AW + 3.5, BAND - AW - 5
    local top
    if wide then
      local colW = 58
      local colX = x + w - M - colW
      drawBubble(bx, by, colX - 5 - bx, bh, clock)
      local cy = y + AW + (BAND - AW - 21) / 2
      drawSwitch(colX, cy, colW, 9)
      drawMoney(colX, cy + 11, colW, 10)
      top = y + BAND + 2
    else
      drawBubble(bx, by, x + w - M - bx, bh, clock)
      local sw = floor((w - M * 3) * 0.55)
      drawSwitch(x + M, y + BAND + 2, sw, 9)
      drawMoney(x + M * 2 + sw, y + BAND + 1.5, w - M * 3 - sw, 10)
      top = y + BAND + 14
    end
    if portrait then
      local dh = min(46, (y + h - M - top) * 0.45)
      local lh = y + h - M - top - dh - M
      drawListPane(x + M, top, w - M * 2, lh, focused, clock)
      drawDetail(x + M, top + lh + M, w - M * 2, dh, clock)
    else
      local lw = floor((w - M * 3) * 0.56)
      drawListPane(x + M, top, lw, y + h - M - top, focused, clock)
      drawDetail(x + M * 2 + lw, top, w - M * 3 - lw, y + h - M - top, clock)
    end
    drawFlying(clock)
    K.scissor(body)
  end

  refresh()
  greet()
  return W
end
