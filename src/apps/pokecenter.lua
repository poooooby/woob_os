-- The Pokémon Center: the nurse's counter, the latest games' way. A close-up of the nurse behind her
-- counter (assets/nurse.png at whole pixels, env.nurse), her words typed out in a box along the foot,
-- a choice beside her (heal | I'm all good). To heal, she walks off to the left (her sheet's steps, a
-- little bounce each) as the screen fades to the machine: a ball onto the tray for each Pokémon, the tray in, the glow with the game's own jingle, the
-- team's health filling on the plate under it, the tray back out; then she walks back in as the screen
-- fades up, turns to you, and anything else?
-- What the game's own nurse does besides talking (the heal, its flags, its sounds) is the model's:
-- ctx.nurse, made by src/pokecenter.lua (FireRed / LeafGreen / Ruby / Sapphire / Emerald) and
-- src/gb/pokecenter.lua (the Game Boy games), opened full screen by Sh.openFull.
--   buttons  A the words (the rest of them, then on), Up / Down the choice, A choose, B "I'm all good"
--   touch    tap the words (or anywhere) to go on, a choice to choose it
--
--   window(ctx, env, view) -> win (src/apps.lua); view = src/apps/pokecenter_view.lua's maker
--   ctx.nurse = { team = { { mon, name, hp, max, egg }, ... } (as it was at the counter), lead (the
--                 first Pokémon's name, not an Egg), time ("morning" | "day" | "night"), greet (nil |
--                 "gold" the Gold Card's first visit | "usual" | "pokecom"), heal() -> true when she has
--                 Pokérus to explain, ball(i), jingle(), jingleDone() -> bool, after() (back from the
--                 machine), pikachu (Yellow's, beside the machine) }

local floor, max, min = math.floor, math.max, math.min

local CPS = 44
local TURN, FADE = 0.35, 0.45
-- her walk to the machine and back: how far (units), how long, a step's length (her sheet's four steps)
local WALK, WALK_T = 44, 0.95
-- the machine's beats, seconds from when it's on screen: the first ball, one every `each`, the tray in
-- (`slide`), the glow up (`glow`), held at least `hold` (and until the jingle ends; `cap` at most)
local TIMING = { place0 = 0.5, each = 0.42, slide = 0.55, glow = 0.7, hold = 1.7, cap = 7, gap = 0.25 }
local UTF8 = "[%z\1-\127\194-\244][\128-\191]*"
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env, makeView)
  local K, T = env.K, env.T or NO_T
  local model = ctx.nurse or {}
  local team = model.team or {}
  local function now() return env.now and env.now() or (love and love.timer and love.timer.getTime() or 0) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, got = pcall(f, ...)
    return ok and got or nil
  end
  if env.prewarm then pcall(env.prewarm, { "SE_SELECT" }, 1) end

  local st = { t0 = now(), say = nil, full = false, after = nil, menu = false, menuT = 0, cursor = 1,
               queue = {}, face = "down", turnT = nil, bowT = nil, scene = "nurse", black = 0, fadeT = nil,
               fadeDir = 0, onBlack = nil, mc = nil, team = team, model = model, timing = TIMING,
               rows = { T("nurse.heal"), T("nurse.allGood") } }
  st.now = now

  -- ------- the words: one at a time, typed out
  local function count(text)
    local n = 0
    for _ in text:gmatch(UTF8) do n = n + 1 end
    return n
  end
  local function say(text, after)
    text = tostring(text or "")
    st.say = { text = text, t = now(), n = count(text) }
    st.full, st.after, st.menu = false, after, false
  end
  local function shown()
    local s = st.say
    if not s then return 0 end
    if st.full then return s.n end
    return floor((now() - s.t - 0.1) * CPS)
  end
  local function typing() return st.say ~= nil and not st.full and shown() < st.say.n end
  st.shown, st.typing = shown, typing

  local function queue(text, after) st.queue[#st.queue + 1] = { text, after } end
  local function nextLine()
    local q = table.remove(st.queue, 1)
    if q then say(q[1], q[2]) end
    return q ~= nil
  end

  -- (her greeting: the time of day's, the Gold Card's, the Pokécom Center's)
  local greet = model.greet
  if greet == "gold" then
    queue(T("nurse.goldCard"), "next")
    queue(T("nurse.usual"), "menu")
  elseif greet == "usual" then
    queue(T("nurse.usual"), "menu")
  elseif greet == "pokecom" then
    queue(T("nurse.pokecom"), "next")
    queue(T("nurse.service"), "menu")
  else
    queue(T("nurse.hello." .. tostring(model.time or "day")) .. " " .. T("nurse.service"), "menu")
  end
  nextLine()

  local function healedLines(pokerus)
    local lead = model.lead
    if lead and #team > 1 then
      queue(T.f("nurse.healed.team", lead), "next")
    elseif lead then
      queue(T.f("nurse.healed.one", lead), "next")
    else
      queue(T("nurse.healed.none"), "next")
    end
    if pokerus then
      queue(T("nurse.pokerus1"), "next")
      queue(T("nurse.pokerus2"), "next")
    end
    queue(T("nurse.more"), "menu")
    nextLine()
  end

  -- ------- the beats: the turn, the fades, the machine (stepped from input, every frame it's open)
  local function fadeOut(onBlack) st.fadeT, st.fadeDir, st.onBlack = now(), 1, onBlack end
  local function step()
    local t = now()
    if st.say and st.after == "menu" and not st.menu and not typing() then st.menu, st.menuT = true, t end
    if st.turnT and t - st.turnT >= TURN then
      st.turnT = nil
      fadeOut("machine")
    end
    if st.fadeT then
      local k = (t - st.fadeT) / FADE
      if st.fadeDir > 0 then
        st.black = min(1, k)
        if k >= 1 then
          local to = st.onBlack
          st.onBlack = nil
          if to == "machine" then
            st.scene, st.say, st.menu = "machine", nil, false
            st.mc = { t0 = t + FADE * 0.4, placed = 0, healed = false, outT = nil }
          elseif to == "back" then
            -- (she walks back in from the left as it fades up; her words once she's there)
            st.scene, st.mc, st.face = "nurse", nil, "down"
            st.walk = { t0 = t, from = -WALK, to = 0, dur = WALK_T, face = "right" }
            call(model.after)
            healedLines(st.pokerus)
            if st.say then st.say.t = t + WALK_T end
          end
          st.fadeT, st.fadeDir = t, -1
        end
      else
        st.black = max(0, 1 - k)
        if k >= 1 then st.fadeT, st.fadeDir = nil, 0 end
      end
    end
    local mc = st.mc
    if mc and st.scene == "machine" then
      local e = t - mc.t0
      local n = #team
      while mc.placed < n and e >= TIMING.place0 + mc.placed * TIMING.each do
        mc.placed = mc.placed + 1
        call(model.ball, mc.placed)
      end
      local glow0 = TIMING.place0 + n * TIMING.each + TIMING.gap + TIMING.slide
      if not mc.healed and e >= glow0 then
        mc.healed = true
        st.pokerus = call(model.heal) == true
        call(model.jingle)
      end
      if mc.healed and not mc.outT then
        local held = e - glow0
        local done = model.jingleDone == nil or call(model.jingleDone) == true
        if (held >= TIMING.hold and done) or held >= TIMING.cap then mc.outT = e end
      end
      if mc.outT and not st.fadeT and e >= mc.outT + 1.1 then fadeOut("back") end
    end
  end

  local function choose(i)
    if not st.menu then return end
    se("SE_SELECT")
    st.menu, st.cursor = false, i
    if i == 1 then
      say(T("nurse.take"), "machine")
    else
      say(T("nurse.bye"), "close")
      st.bowT = now()
    end
  end
  local function walking() return st.walk ~= nil and now() - st.walk.t0 < st.walk.dur end
  local function busy()
    return st.scene ~= "nurse" or st.fadeT ~= nil or st.turnT ~= nil or st.closed or walking()
  end
  local function advance()
    if busy() or not st.say then return end
    if typing() then
      st.full = true
      return
    end
    if st.menu then
      choose(st.cursor)
      return
    end
    local after = st.after
    if after == "next" then
      nextLine()
    elseif after == "machine" then
      -- (she walks off to the left, to the machine; the fade starts partway)
      local t = now()
      st.after, st.face, st.turnT = nil, "left", t
      st.walk = { t0 = t, from = 0, to = -WALK, dur = WALK_T, face = "left" }
    elseif after == "close" then
      st.after, st.closed = nil, true
      ctx.done()
    elseif after == "menu" then
      st.menu, st.menuT = true, now()
    end
  end

  local W = { title = T("nurse.title") }
  local view = makeView(K, env, st, T)

  function W.draw(body, clock, portrait) view.draw(body, clock, portrait) end

  function W.input(input, nav)
    step()
    if busy() then return true end
    if st.menu then
      if nav.up or nav.down then
        st.cursor = st.cursor == 1 and 2 or 1
        se("SE_SELECT")
      end
    end
    if input:wasPressed("a") then
      advance()
    elseif input:wasPressed("b") then
      if typing() then
        st.full = true
      elseif st.menu then
        choose(2)
      else
        advance()
      end
    end
    return true
  end

  function W.tap(arg)
    if busy() then return end
    if type(arg) == "number" and arg > view.ROW_AT and arg <= view.ROW_AT + #st.rows then
      if st.menu then choose(arg - view.ROW_AT) end
      return
    end
    -- (anywhere else: the words go on; a choice waits to be tapped)
    if st.menu and not typing() then return end
    advance()
  end

  function W.hints() return nil end
  -- (the lighting's canvases let go)
  function W.close() if view.release then pcall(view.release) end end

  -- (the tests')
  W.state, W.step = st, step
  return W
end
