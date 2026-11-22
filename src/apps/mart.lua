-- The Mart app: a corner shop. The game's own Mart clerk behind the counter under a striped awning,
-- talking in a speech bubble: a greeting for the time of day (or the new stock a Badge brought), a
-- word on each purchase and sale, why not when something can't be had, a tip now and then. The goods
-- (more as the Gym Badges come in) are bought straight into the Bag, the item appearing on the
-- shelf's pad; the Bag's items sold for half their price, off the pad. Tabs along the list's top; the
-- chosen item on a lit stand beside it (its words, how many, the total); coins flying to and from the
-- till, the money counting. In the Pokédex's glass: the shop's lights drifting behind (the second turning
-- to the tab's colour), the bubble, the list and the stand on frosted panes, Buy | Sell a glass switch.
--   buttons  Up / Down the item, L / R the tab (Buy: Balls, Medicine, Battle, Field; Sell: the
--            Bag's pockets), START Buy | Sell, A the item (then < > one, ^ v ten, SELECT as many
--            as there are / as money buys, A buy or sell, B back), B close
--   touch    tap an item, its - / + and Buy / Sell; the Buy | Sell switch; a tab; the clerk; the
--            bubble (the rest of the words); drag (or the wheel) scrolls the list
-- The model is src/mart.lua (env.mart); rows are made again only after a change. The clerk is the
-- game's overworld sprite (env.clerk), drawn at whole pixels; without it the bubble speaks alone.
-- Shop mode (ctx.shop, src/shop.lua: a real shop counter, full screen): that counter's goods and model,
-- its place for the title and a sign on the awning, its look (src/shop_themes.lua's colours for the
-- awning, the shelves and the lights), its own clerk, buy-only shops without Sell, decorations' pictures.
-- A stall out in the open (the shop's kind "stall": Slateport's market) is drawn by env.stallView
-- (src/apps/stall_view.lua): the sky, the sea and the beach, a market tent, the table, a cash box.
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, sin, abs, pi = math.floor, math.max, math.min, math.sin, math.abs, math.pi

local ROW_H, TAB_H, M = 10, 9, 3
local AW, BAND = 7, 34                 -- the awning's depth, the shopfront's
-- hit args: rows 1.., the rest below
local SEG_BUY, SEG_SELL = 2001, 2002
local STEP_MINUS, STEP_PLUS, STEP_GO, CLERK, BUBBLE, STEP_ALL = 2010, 2011, 2012, 2013, 2014, 2015
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
  buyOnly = { { "A", "hint.choose" }, { "L R", "hint.tab" }, { "B", "hint.close" } },
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
  short = "mart.say.short", shortBank = "mart.say.shortBank", bag_full = "mart.say.bagFull", decor_full = "mart.say.decorFull",
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
  local K, T = env.K, env.T or NO_T
  -- (a real shop counter's model, or the app's Mart)
  local shop = ctx.shop
  local mart = shop or env.mart
  -- (pad: the shelf's item pad lights up while the window is open; not for a real shop, full screen)
  local W = { title = shop and shop.title or "Mart", pad = not shop }
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
    if mode == "sell" and mart.buyOnly then return end
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

  -- (by touch: - / + held repeat it, tens after a moment; the number tapped is all of them, as SELECT)
  local hold = K.newHold()
  local function stepping(d)
    local r = row()
    if not r or locked(r) or (st.mode == "sell" and not r.price) then hold.d = nil return false end
    st.focus = "step"
    if d then stepBy(d) end
    return true
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
      if not shop and env.pad and env.pad.transfer then pcall(env.pad.transfer, r.id, "in") end
      se("SE_SHOP")
      st.lastTotal = before - mart.money(s)
      st.coins = { t = now(), out = false }
      st.fly = { t = now(), id = r.id, sell = false, n = min(qty, 5), decor = r.decor }
      st.n = st.n + 1
      if got then say(SAY.premier, "hop")
      elseif qty >= BULK then say(SAY.bulk, "hop", false, qty)
      elseif st.n % 2 == 1 and TAB_SAY[st.tabKey] then say(TAB_SAY[st.tabKey], "hop")
      else say(SAY.buy[floor(st.n / 2) % #SAY.buy + 1], "hop", false, nice(r.name)) end
    else
      local ok, got = mart.sell(s, r.id, qty)
      if not ok then return refuse(got, r) end
      if not shop and env.pad and env.pad.transfer then pcall(env.pad.transfer, r.id, "out") end
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
      stepping(arg == STEP_PLUS and 1 or -1)
      return
    end
    if arg == STEP_ALL then
      if stepping() then stepAll() end
      return
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

  function W.pointer(phase, x, y, id) return K.holdPointer(hold, phase, x, y, id, W.scroll) end
  function W.scroll(dy)
    st.free, st.idleAt = true, now()
    st.top = max(0, min(max(0, #st.rows - st.visible), st.top - dy / ROW_H))
  end

  function W.hints()
    if st.focus == "step" then return T.list(st.mode == "buy" and HINTS.stepBuy or HINTS.stepSell) end
    if mart.buyOnly then return T.list(HINTS.buyOnly) end
    return T.list(st.mode == "buy" and HINTS.buy or HINTS.sell)
  end

  -- ------- drawing (no tables made here)

  -- a corner shop in the Pokédex's glass: soft lights drifting behind in Mart blue (the second turning
  -- to the chosen tab's colour), shelves of goods, the striped awning and the counter in front of them;
  -- the bubble, the list, the item's stand, the stepper and the money on panes of frosted glass
  local MART, MART_DEEP = { 56, 136, 250 }, { 22, 74, 196 }
  local AWN_WHITE = { 250, 252, 255 }
  local WHITE, INK, SOFT, FAINT = { 255, 255, 255 }, { 28, 28, 30 }, { 112, 112, 120 }, { 160, 160, 170 }
  local GOLD, GOLD_FOOT, GOLD_INK = { 255, 222, 128 }, { 196, 146, 44 }, { 178, 122, 10 }
  local RED, RED_DEEP = { 255, 72, 84 }, { 196, 30, 52 }
  local GREEN, GREEN_DEEP = { 60, 206, 120 }, { 18, 150, 86 }
  local TILL_TOP, TILL_FOOT, LCD, LCD_INK = { 70, 84, 120 }, { 34, 42, 70 }, { 20, 52, 40 }, { 120, 255, 170 }
  local SHADE = { 0, 0, 0 }
  local TAB_C = { { 255, 104, 104 }, { 72, 206, 150 }, { 255, 168, 60 }, { 96, 164, 255 } }
  local POCKET_C = { ITEMS = { 96, 164, 255 }, POKE_BALLS = { 255, 104, 104 }, TM_CASE = { 255, 168, 60 },
                     BERRY_POUCH = { 130, 206, 80 } }
  local GOODS = { { 255, 104, 104 }, { 72, 206, 150 }, { 255, 168, 60 }, { 96, 164, 255 }, { 240, 196, 80 },
                  { 180, 126, 255 } }
  -- (a real shop: its own look -- the awning's stripes, the shelves' goods, the lights behind)
  local LIGHT = { 0.3, 0.56, 1 }
  local theme = shop and shop.theme
  if theme then
    for i = 1, 3 do
      MART[i], MART_DEEP[i], AWN_WHITE[i] = theme.stripe[i], theme.stripeDeep[i], theme.stripe2[i]
      LIGHT[i] = theme.light[i] / 255
    end
    if theme.goods then GOODS = theme.goods end
  end
  -- an item's picture (a decoration's, for a decoration shop), size units square at x, y
  local function goodsIcon(id, decor, x, y, size, a)
    if decor then
      local Dc = env.decorate
      local ok, img = pcall(Dc and Dc.picture or error, decor)
      K.rescissor()
      if not (ok and img) then return end
      local pw, ph = img:getDimensions()
      local k = size * K.sc / max(pw, ph)
      local G = K.graphics()
      G.setColor(1, 1, 1, a or 1)
      G.draw(img, K.X(x + size / 2) - pw * k / 2, K.Y(y + size / 2) - ph * k / 2, 0, k, k)
      return
    end
    if env.itemIcon then pcall(env.itemIcon, id, x, y, size, a) end
  end
  -- (a stall out in the open: its own look)
  local stall = shop and shop.kind == "stall" and env.stallView and env.stallView(K, env, shop, now) or nil
  -- the motion's numbers (the view's own: st is the window's)
  local mv = { lastT = nil, dt = 0, coloured = false, r2 = 0.4, g2 = 0.64, b2 = 1, sw = nil, tabK = nil,
               tabMode = nil, hl = nil, listKey = nil, listMode = nil, listAt = -10, itemId = nil, itemMode = nil,
               itemAt = -10 }

  local ease = K.outCubic
  local function money(n, x, y, size, c, right)
    if not env.amount then return 0 end
    local ok, w = pcall(env.amount, n, 0, 0, size, c, true)
    w = ok and tonumber(w) or 0
    pcall(env.amount, n, right and x - w or x, y, size, c)
    return w
  end
  local function tabColor(i)
    if st.mode == "buy" and shop then
      -- (a real shop's: a pocket's colour, else its awning's)
      local t = st.tabs[i]
      local p = t and t.key and t.key:match("^pocket%.(.+)$")
      return p and POCKET_C[p] or MART
    end
    if st.mode == "buy" then return TAB_C[(i - 1) % #TAB_C + 1] end
    local p = st.pockets[i]
    return p and POCKET_C[p.id] or TAB_C[4]
  end
  local function curColor() return tabColor(st.mode == "buy" and st.tab or st.sellTab) end
  -- (Buy's colour, Sell's)
  local function actColor(sell) return sell and GREEN_DEEP or MART end
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

  -- the shop behind everything: the lights drifting, the ceiling lamps, two glass shelves of goods
  local function drawShop(body, clock)
    local x, y, w = body[1], body[2], body[3]
    local c = curColor()
    if mv.coloured then
      mv.r2 = K.approach(mv.r2, c[1] / 255, mv.dt, 5)
      mv.g2 = K.approach(mv.g2, c[2] / 255, mv.dt, 5)
      mv.b2 = K.approach(mv.b2, c[3] / 255, mv.dt, 5)
    else
      mv.r2, mv.g2, mv.b2, mv.coloured = c[1] / 255, c[2] / 255, c[3] / 255, true
    end
    K.backdrop(body, clock, LIGHT[1], LIGHT[2], LIGHT[3], mv.r2, mv.g2, mv.b2)
    for i = 0, 2 do
      K.glow(x + w * (0.18 + i * 0.32), y + AW + 2, w * 0.16, BAND * 0.8, WHITE, 0.1 + 0.03 * sin(clock * 1.3 + i))
    end
    for s = 0, 1 do
      local sy = y + AW + 10 + s * 10
      local gx, i = x + 1.5 + s * 1.7, s * 7
      while gx < x + w - 3 do
        local gw = 2.2 + (i * 7 % 5) * 0.45
        local gh = 2.8 + (i * 5 % 4) * 1.05
        K.col(GOODS[i % #GOODS + 1], 0.42)
        K.box("fill", K.R(gx, sy - gh, gw, gh), 0.5)
        K.col(WHITE, 0.22 + 0.14 * sin(clock * 1.7 + i * 1.3))
        K.box("fill", K.R(gx + 0.4, sy - gh + 0.4, 0.45, gh - 0.8))
        gx = gx + gw + 0.9 + (i * 3 % 3) * 0.5
        i = i + 1
      end
      K.col(WHITE, 0.75)
      K.box("fill", K.R(x, sy, w, 0.7))
      K.col(SHADE, 0.06)
      K.box("fill", K.R(x, sy + 0.7, w, 0.8))
    end
  end

  -- the awning: Mart blue and white stripes, scalloped, a glint running along it now and then
  local function drawAwning(x, y, w, clock)
    local G = K.graphics()
    local sw, d = 9, AW - 3.5
    K.col(SHADE, 0.1)
    K.box("fill", K.R(x, y + d, w, 3.5))
    local n = floor(w / sw) + 1
    for i = 0, n - 1 do
      local sx = x + i * sw
      local c = i % 2 == 0 and MART or AWN_WHITE
      K.grad(K.R(sx, y, sw, d), 0, c, K.dark(c, 0.1))
      K.col(K.dark(c, 0.1))
      G.arc("fill", "pie", K.X(sx + sw / 2), K.Y(y + d), (sw / 2) * K.sc, 0, pi, 14)
    end
    K.col(WHITE, 0.6)
    K.box("fill", K.R(x, y, w, 0.5))
    if shop and shop.sub then
      local word = shop.sub
      local fs = K.fit(word, 3.6, w * 0.5)
      local pw = K.width(word, fs) + 8
      local pb = K.R(x + (w - pw) / 2, y + 0.6, pw, 5.8)
      K.shadow(pb, 2.9, 0.6, 0.18)
      K.glass(pb, 2.9, 0.92)
      K.bold(word, pb[1], pb[2] + (pb[4] - fs * 1.2) / 2 + 0.2, fs, MART_DEEP, "center", pw)
    end
    local p = (clock * 0.22) % 1.8
    if p < 1 then
      local gx = x - 12 + p * (w + 24)
      K.col(WHITE, 0.35 * sin(p * pi))
      G.polygon("fill", K.X(gx), K.Y(y), K.X(gx + 5), K.Y(y), K.X(gx + 2), K.Y(y + d), K.X(gx - 3), K.Y(y + d))
    end
  end

  -- the clerk: the game's sprite at whole pixels; a hop for a sale, a shake of the head for a no, a
  -- turn round for Buy / Sell, a glance along the shelves now and then, a nod while talking
  local function drawClerk(cx, foot, hU, clock)
    local spr = (shop and shop.clerk) or (env.clerk and env.clerk())
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

  -- the counter (a pane of glass with the Mart's blue band and the W), the clerk behind it (seen from
  -- the chest up), the till on it (its drawer out when coins land)
  local function drawCounter(x, y, w, clock)
    local G = K.graphics()
    local top = y + BAND - 8
    local cx = x + 12
    st.headY = top - 14
    K.glow(cx, top - 10, 14, 13, MART, 0.16)
    drawClerk(cx, top + 3, BAND - 8, clock)
    local cb = K.R(x, top, w, 8)
    K.glass(cb, 2, 0.8)
    K.col(MART, 0.92)
    K.box("fill", K.R(x, top + 2.8, w, 3.2))
    K.col(WHITE, 0.35)
    K.box("fill", K.R(x, top + 2.8, w, 0.4))
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
    K.shadow(K.R(tx, ty, tw, th), 1.4, 0.8, 0.18)
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
    -- (a line's step as tall as the words are drawn: the text size's)
    local out = { lines = lines, pre = {}, count = {}, n = 0, size = size, line = LINE * size / SIZE * K.textScale() }
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

  -- the speech bubble: a pane of glass popping up with each line, its tail at the clerk, the words typed out
  local function drawBubble(x, y, w, h, clock)
    local s = st.say
    if not s or w < 20 then return end
    local G = K.graphics()
    local k = ease((now() - s.t) / 0.2)
    local by = y + (1 - k) * 2.5
    local b = K.R(x, by, w, h)
    local f0 = K.getFade()
    K.setFade(f0 * k)
    K.glass(b, 4, 0.86)
    K.col(WHITE, 0.86)
    local ty = min(max(st.headY or (y + h / 2), by + 4), by + h - 4)
    G.polygon("fill", K.X(x + 0.6), K.Y(ty - 2.6), K.X(x - 4.2), K.Y(ty + 0.4), K.X(x + 0.6), K.Y(ty + 2.6))
    if s.bad then K.ring(b, 4, RED, 0.85, 0.55) end
    local nm = T("mart.clerk")
    local nw = K.width(nm, 3) + 5
    K.grad(K.R(x + 4, by - 2.4, nw, 4.8), 2.4, s.bad and RED or MART, s.bad and RED_DEEP or MART_DEEP)
    K.bold(nm, x + 4, by - 1.7, 3, WHITE, "center", nw)
    -- (the words: made again when they or the width change; smaller when they'd overflow)
    local tw = w - 8
    local L = st.lines
    local TS = K.textScale()
    if not L or st.linesW ~= floor(tw) or st.linesText ~= s.text or st.linesTS ~= TS then
      L = linesOf(s.text, tw, SIZE)
      if #L.lines * L.line > h - 4 then L = linesOf(s.text, tw, SIZE * 0.84) end
      -- (bigger text: smaller again until the lines fit, never under the words' size at 100%'s 0.84)
      local k = 0.84
      while TS > 1 and #L.lines * L.line > h - 4 and SIZE * (k - 0.06) * TS >= SIZE * 0.84 - 0.01 do
        k = k - 0.06
        L = linesOf(s.text, tw, SIZE * k)
      end
      st.lines, st.linesW, st.linesText, st.linesTS = L, floor(tw), s.text, TS
    end
    local left = shown()
    local total = #L.lines * L.line
    local ly = by + max(2.8, (h - total) / 2 + 0.4)
    for j = 1, #L.lines do
      if ly + L.line > by + h + 0.5 then break end
      local cnt = L.count[j]
      if left >= cnt then
        K.text(L.lines[j], x + 4, ly, L.size, INK)
        left = left - cnt
      else
        local cw = 0
        if left > 0 then
          K.text(L.pre[j][left], x + 4, ly, L.size, INK)
          cw = K.width(L.pre[j][left], L.size)
        end
        K.col(s.bad and RED or MART, 0.5 + 0.5 * abs(sin(clock * 8)))
        K.box("fill", K.R(x + 4 + cw + 0.4, ly + 0.3 - 0.6 * (TS - 1) * L.size, 0.6, L.size * TS * 1.1))
        break
      end
      ly = ly + L.line
    end
    K.setFade(f0)
    K.addHit(b, "win", BUBBLE)
  end

  -- Buy | Sell: the glass switch, its thumb sliding to the chosen side, a line of blue (to buy) or green
  -- (to sell) under it
  local function drawSwitch(x, y, w, h)
    if mart.buyOnly then
      -- (a shop that only sells: a plain glass label)
      local b = K.R(x, y, w, h)
      K.glass(b, h / 2, 0.75)
      local word = T("mart.buy")
      K.bold(word, x, y + (h - 4.2 * 1.2) / 2 + 0.2, K.fit(word, 4.2, w - 4), MART_DEEP, "center", w)
      return
    end
    local want = st.mode == "buy" and 1 or 2
    mv.sw = mv.sw and K.approach(mv.sw, want, mv.dt, 16) or want
    K.glassSwitch(x, y, w, h, mv.sw, "win", SEG_BUY, T("mart.buy"), SEG_SELL, T("mart.sell"), nil, nil, 4.2)
    local sw = (w - 1) / 2
    K.col(K.mix(MART, GREEN_DEEP, mv.sw - 1), 0.9)
    K.box("fill", K.R(x + 0.5 + (mv.sw - 1) * sw + sw * 0.3, y + h - 1.9, sw * 0.4, 0.7), 0.35)
  end

  -- the money: a coin, the amount counting to what it is (red a moment when it falls short)
  local function drawMoney(x, y, w, h)
    local G = K.graphics()
    local b = K.R(x, y, w, h)
    K.glass(b, h / 2, 0.6)
    local cx, cy = x + h / 2 + 0.5, y + h / 2
    K.col(GOLD_FOOT)
    G.circle("fill", K.X(cx), K.Y(cy), (h / 2 - 1.6) * K.sc)
    K.col(GOLD)
    G.circle("fill", K.X(cx), K.Y(cy), (h / 2 - 2.3) * K.sc)
    local target = mart.money(session())
    st.shownM = st.shownM and K.approach(st.shownM, target, mv.dt, 5) or target
    if abs(target - st.shownM) < 1 then st.shownM = target end
    local flash = now() - st.flash < FLASH
    local size = K.fit("0000000", 4.6, w - h - 3)
    money(floor(st.shownM + 0.5), x + w - h / 2, y + (h - size * 1.15) / 2, size, flash and RED or GOLD_INK, true)
    st.moneyX, st.moneyY = cx, cy
  end

  -- the tabs: one chip each, a pane of the chosen one's colour sliding to it
  local function drawTabs(x, y, w, h)
    local n = st.mode == "buy" and #st.tabs or #st.pockets
    if n == 0 then return end
    local cw = w / n
    local want = (st.mode == "buy" and st.tab or st.sellTab) - 1
    if mv.tabMode ~= st.mode or not mv.tabK then mv.tabK, mv.tabMode = want, st.mode end
    mv.tabK = K.approach(mv.tabK, want, mv.dt, 16)
    local c = curColor()
    local hb = K.R(x + mv.tabK * cw + 0.6, y + 0.6, cw - 1.2, h - 1.2)
    K.col(SHADE, 0.08)
    K.box("fill", K.R(hb[1], hb[2] + 0.4, hb[3], hb[4]), (h - 1.2) / 2)
    K.col(c, 0.92)
    K.box("fill", hb, (h - 1.2) / 2)
    K.ring(hb, (h - 1.2) / 2, WHITE, 0.6, 0.35)
    for i = 1, n do
      local key = st.mode == "buy" and st.tabs[i].key or st.pocketKeys[i]
      local label = T(key)
      local on = abs(mv.tabK - (i - 1)) < 0.5
      local fs = K.fit(label, 3.6, cw - 3)
      if on then
        K.bold(label, x + (i - 1) * cw, y + (h - fs * 1.2) / 2, fs, WHITE, "center", cw)
      else
        K.text(label, x + (i - 1) * cw, y + (h - fs * 1.2) / 2, fs, SOFT, "center", cw)
      end
      K.addHit(K.R(x + (i - 1) * cw, y, cw, h), "win", TAB_AT + i)
    end
  end

  -- the rows: the highlight gliding to the chosen one, a tab's rows rising in one after another
  local function drawList(x, y, w, h, focused, clock)
    local G = K.graphics()
    local clip = K.R(x, y, w, h)
    K.scissor(clip)
    local top = st.top
    local first = floor(top) + 1
    local last = min(#st.rows, first + st.visible + 1)
    local sell = st.mode == "sell"
    local tc = curColor()
    if st.tabKey ~= mv.listKey or st.mode ~= mv.listMode then
      mv.listKey, mv.listMode, mv.listAt, mv.hl = st.tabKey, st.mode, clock, nil
    end
    local since = clock - mv.listAt
    if #st.rows > 0 then
      mv.hl = mv.hl and K.approach(mv.hl, st.cursor, mv.dt, 22) or st.cursor
      local e = K.stagger(since, st.cursor - first, 0.035, 0.28)
      local f0 = K.getFade()
      K.setFade(f0 * max(0, e))
      local hb = K.R(x + 1.5, y + (mv.hl - 1 - top) * ROW_H + 0.4, w - 3, ROW_H - 0.8)
      K.col(tc, focused and (0.2 + 0.05 * sin(clock * 4)) or 0.1)
      K.box("fill", hb, 3)
      K.ring(hb, 3, tc, focused and 0.85 or 0.35, 0.45)
      K.col(tc)
      K.box("fill", K.R(hb[1] + 0.7, hb[2] + 2, 0.9, hb[4] - 4), 0.45)
      K.setFade(f0)
    end
    for i = first, last do
      local r = st.rows[i]
      local ry = y + (i - 1 - top) * ROW_H
      local rb = K.R(x + 1.5, ry + 0.4, w - 3, ROW_H - 0.8)
      local on = i == st.cursor
      local off = locked(r) or (sell and not r.price)
      -- (rising in: an offset and a fade, no transform -- a push makes garbage in some stand-ins)
      local e = K.stagger(since, i - first, 0.035, 0.28)
      local f0 = K.getFade()
      K.setFade(f0 * e)
      ry = ry + (1 - e) * 4
      if i > first and not on and i - 1 ~= st.cursor then K.hairline(x + 14, ry, w - 17) end
      K.col(tc, off and 0.1 or (on and 0.3 or 0.18))
      G.circle("fill", K.X(x + 8), K.Y(ry + ROW_H / 2), 4.1 * K.sc)
      goodsIcon(r.id, r.decor, x + 4, ry + 1, 8, (off and 0.45 or 1) * K.getFade())
      local rw = 0
      if locked(r) then
        local bt = badgeText(r.badges)
        rw = K.width(bt, 3.8) + 7
        local lb = K.R(x + w - 4 - rw, ry + 2.3, rw, 5.4)
        K.col(SHADE, 0.06)
        K.box("fill", lb, 2.7)
        padlock(lb[1] + 1.4, lb[2] + 0.8, 3.6, SOFT)
        K.text(bt, lb[1] + 5, lb[2] + 1, 3.8, SOFT)
      elseif r.price then
        rw = money(r.price, x + w - 4, ry + 2.7, 4.3, off and FAINT or GOLD_INK, true)
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
      if on and focused then
        K.bold(r.name, nx, ry + 2.7 + (4.5 - ns) * 0.5, ns, off and FAINT or INK)
      else
        K.text(r.name, nx, ry + 2.7 + (4.5 - ns) * 0.5, ns, off and FAINT or INK)
      end
      K.addHit(rb, "win", i, clip)
      K.setFade(f0)
    end
    if #st.rows == 0 then
      K.text(T(sell and "items.emptyPocket" or "mart.soldOut"), x, y + h / 2 - 3, 4.4, SOFT, "center", w)
    end
    K.scrollbar(x + w, y, h, top, st.visible, #st.rows)
    K.scissor(st.clip)
  end

  -- the list's pane: the tabs, the rows
  local function drawListPane(x, y, w, h, focused, clock)
    K.glass(K.R(x, y, w, h), 5, 0.5)
    drawTabs(x + 1.5, y + 1.5, w - 3, TAB_H)
    local top = y + TAB_H + 3
    st.visible = max(1, floor((y + h - 1 - top) / ROW_H))
    clampList()
    drawList(x, top, w, y + h - 1 - top, focused, clock)
  end

  -- the stepper: a glass pill, - and + either side of how many (bumping as it changes), the total on the right
  local function drawStepper(x, y, w, stepping, short, total)
    local G = K.graphics()
    local sb = K.R(x, y, 32, 10)
    K.glass(sb, 5, 0.62)
    local ac = actColor(st.mode == "sell")
    for side = 0, 1 do
      local cx = side == 0 and sb[1] + 5 or sb[1] + sb[3] - 5
      K.col(ac, 0.14)
      G.circle("fill", K.X(cx), K.Y(sb[2] + 5), 3.7 * K.sc)
      K.col(ac)
      K.box("fill", K.R(cx - 1.6, sb[2] + 4.65, 3.2, 0.7), 0.35)
      if side == 1 then K.box("fill", K.R(cx - 0.35, sb[2] + 3.4, 0.7, 3.2), 0.35) end
    end
    local mb, pb = K.R(sb[1], sb[2], 10.5, 10), K.R(sb[1] + 21.5, sb[2], 10.5, 10)
    K.addHit(mb, "win", STEP_MINUS)
    K.addHit(K.R(sb[1] + 10.5, sb[2], 11, 10), "win", STEP_ALL)
    K.addHit(pb, "win", STEP_PLUS)
    K.holdZone(hold, mb, -1)
    K.holdZone(hold, pb, 1)
    if st.qty ~= st.lastQty then st.lastQty, st.bumpAt = st.qty, now() end
    local bump = max(0, 1 - (now() - (st.bumpAt or -10)) / 0.22)
    local qs = 4.6 * (1 + 0.18 * bump)
    K.bold(qtyText(st.qty), sb[1] + 9, sb[2] + (10 - qs * 1.2) / 2, qs, INK, "center", 14)
    if stepping and st.keys then K.focusRing(sb, 5) end
    local sh = now() - st.shakeAt
    local dx = sh < 0.4 and sin(sh * 55) * 1.3 * (1 - sh / 0.4) or 0
    money(total, x + w + dx, y + 2.4, 5.2, short and RED or GOLD_INK, true)
  end

  -- the button: lit and breathing when it can be done, clear glass when it can't
  local function drawGo(b, label, on, sell, stepping, clock)
    if on then
      local ac = actColor(sell)
      K.col(ac, 0.14 + 0.1 * sin(clock * 3))
      K.box("fill", K.R(b[1] - 1, b[2] - 1, b[3] + 2, b[4] + 2), b[4] / 2 + 1)
      if sell then K.grad(b, b[4] / 2, GREEN, GREEN_DEEP) else K.grad(b, b[4] / 2, MART, MART_DEEP) end
      K.ring(b, b[4] / 2, WHITE, 0.45, 0.35)
    else
      K.glass(b, b[4] / 2, 0.4)
    end
    if stepping and st.keys then K.focusRing(b, b[4] / 2) end
    K.bold(label, b[1], b[2] + (b[4] - 4.8 * 1.2) / 2, K.fit(label, 4.8, b[3] - 6), on and WHITE or FAINT, "center", b[3])
    K.addHit(b, "win", STEP_GO)
  end

  -- the chosen item on its lit stand: the picture popping up on it as it's chosen, then bobbing, its name
  -- and how many are in the Bag sliding in after it, its words when there's room; how many, the total and
  -- Buy / Sell at the foot (or why it can't be had)
  local function drawDetail(x, y, w, h, clock)
    local G = K.graphics()
    K.glass(K.R(x, y, w, h), 5, 0.5)
    local r = row()
    if not r then return end
    if r.id ~= mv.itemId or st.mode ~= mv.itemMode then mv.itemId, mv.itemMode, mv.itemAt = r.id, st.mode, clock end
    local pt = clock - mv.itemAt
    local tc = curColor()
    local big = h >= 60
    local is = big and 16 or 11
    local sx, sy = x + 4 + is / 2 + 1, y + 3 + is / 2 + 1
    -- (the stand: a disc of the tab's colour, its lit top)
    K.col(tc, 0.16)
    G.circle("fill", K.X(sx), K.Y(sy), is * 0.64 * K.sc)
    K.col(tc, 0.32)
    G.ellipse("fill", K.X(sx), K.Y(sy + is * 0.55), is * 0.46 * K.sc, is * 0.12 * K.sc)
    K.col(WHITE, 0.7)
    G.ellipse("fill", K.X(sx), K.Y(sy + is * 0.52), is * 0.3 * K.sc, is * 0.06 * K.sc)
    local pop = 0.7 + 0.3 * K.outBack(pt / 0.38)
    local ps = is * pop
    local bob = sin(clock * 2.2) * 0.7
    goodsIcon(r.id, r.decor, sx - ps / 2, sy + is / 2 - ps + bob - 0.6, ps, K.getFade())
    st.standX, st.standY = sx, sy
    local e1 = ease((pt - 0.04) / 0.3)
    local f0 = K.getFade()
    K.setFade(f0 * e1)
    local tx = x + is + 9 + (1 - e1) * 5
    local ty = y + (1 - e1) * 1.5
    local nx = tx
    if isNew(r) then nx = nx + newTag(nx, ty + 4.6) + 1.5 end
    local ns = K.fit(r.name, 5, x + w - 4 - nx)
    K.bold(r.name, nx, ty + 4 + (5 - ns) * 0.5, ns, INK)
    -- (in the Bag: a little chip)
    local bt = inBagText(st.inBag)
    local bw = K.width(bt, 3.5) + 4
    K.col(tc, 0.2)
    K.box("fill", K.R(tx, ty + 10.6, bw, 5 + (K.textScale() - 1) * 1.5), 2.5)
    K.text(bt, tx + 2, ty + 11.3, 3.5, SOFT)
    K.setFade(f0)
    if big and r.desc ~= "" then
      -- (the words, as many whole lines as fit above the stepper)
      local e2 = ease((pt - 0.1) / 0.32)
      local dy = y + is + 8
      local lh = K.font(3.8 * K.textScale() * K.sc):getHeight() / K.sc
      local n = floor((h - (dy - y) - 28) / lh)
      if n >= 1 then
        K.scissor(K.R(x, dy, w, n * lh + 0.2))
        K.text(r.desc, x + 4, dy + (1 - e2) * 2, 3.8, SOFT, "left", w - 8, e2)
        K.scissor(st.clip)
      end
    end
    local go = K.R(x + 4, y + h - 13, w - 8, 10)
    local sell = st.mode == "sell"
    local stepping = st.focus == "step"
    if locked(r) then
      -- (the Badges it needs: a padlock, the words, a pip for each of the eight)
      padlock(x + 4, y + h - 27, 4.4, RED)
      K.text(needsText(r.badges), x + 10, y + h - 26.6, 3.8, RED_DEEP, "left", w - 14)
      for i = 1, 8 do
        local on = i <= st.badges
        local need = i <= r.badges
        K.col(on and GOLD_FOOT or (need and RED or SHADE), on and 1 or (need and 0.5 or 0.1))
        G.circle("fill", K.X(x + 6 + (i - 1) * 4), K.Y(y + h - 18.5), 1.3 * K.sc)
      end
      drawGo(go, T("mart.buy"), false, false, false, clock)
      return
    end
    if sell and not r.price then
      K.text(T("reason.mart.cant_sell"), x + 4, y + h - 25.5, 3.8, SOFT, "left", w - 8)
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
            goodsIcon(f.id, f.decor, px - sz / 2, py - sz / 2, sz, 1 - 0.25 * k)
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
    K.holdStep(hold, stepping)
    K.holdBegin(hold)
    mv.dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT = clock
    st.clip = body
    -- (a stall's wider: the goods set out on its table)
    local cw = stall and floor(min(56, max(40, w * 0.24))) or 40
    if stall then
      stall.backdrop(body, clock, BAND)
      K.scissor(body)
      stall.front(x + M, y, cw, BAND, clock, st, drawClerk, goodsIcon)
    else
      drawShop(body, clock)
      K.scissor(body)
      drawCounter(x + M, y, cw, clock)
      -- (the awning in front: the clerk stands under it)
      drawAwning(x, y, w, clock)
    end
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
  -- (a counter that fades up through black: the clerk's first words once the shop's in sight)
  local delay = tonumber(ctx.veilDelay)
  if delay and delay > 0 and st.say then
    st.say.t = st.say.t + delay
    if st.moodT then st.moodT = st.moodT + delay end
  end
  return W
end
