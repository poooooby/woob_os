-- The OPTIONS screen, modern (src/options_screen.lua the model: ctx.menu for the game's OPTIONS, full screen; ctx.scene
-- for a mod's own page opened where the mod manager would, on the scene host). Glass rows over soft lights: each
-- option's whole name, its control at the right -- a switch for on / off, the value between arrows for a choice,
-- a chevron for a page -- a row another mod put at the top tagged with that mod's name, a mod's options as a tree
-- (an option shown while another has a value, indented under it with a line to it), and the chosen option's
-- description in a card along the foot.
--   buttons  Up / Down an option, Left / Right its value, A to change it or open it, B / START back (out at the top)
--   touch    tap an option (a switch flips, a page opens), its arrows for the value, < back; drag or wheel to scroll
-- MODS (src/mods_screen.lua the model, kind "mods") in the same window: its rows under a divider for each section
-- (row.section), a mod's badge and the word on where it stands under its name (row.badge, row.sub), A on a mod its
-- page (row.open) while its switch flips; the manager's questions on a sheet (OK, or Cancel / OK).

local floor, max, min, abs, sin = math.floor, math.max, math.min, math.abs, math.sin

local A = { ROW = 3000, DEC = 3200, INC = 3400, BACK = 3600, KEY = 3700, SCRIM = 3690, SHEET = 3680 }
local M, TOP_H = 4, 15
local C = {
  ink = { 28, 28, 30 }, soft = { 112, 112, 120 }, faint = { 160, 160, 170 }, white = { 255, 255, 255 },
  accent = { 10, 132, 255 }, green = { 52, 199, 89 }, track = { 120, 120, 128, 0.32 }, line = { 120, 124, 140, 0.45 },
  red = { 255, 59, 48 }, black = { 0, 0, 0 },
}
-- (each mod's tag its own colour: from its name)
local TAGS = { { 175, 82, 222 }, { 255, 149, 0 }, { 48, 176, 199 }, { 255, 45, 85 }, { 88, 86, 214 }, { 52, 199, 89 } }
local SOUNDS = { "SE_SELECT" }

return function(ctx, env)
  local K, T = env.K, env.T
  local Os = env.optionsScreen
  local Mm = env.modsScreen
  local model = ctx.menu or ctx.scene
  local function now() return env.now and env.now() or (love and love.timer and love.timer.getTime() or 0) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local W = { title = "" }
  if not (model and Os) then
    function W.draw() if ctx.done then ctx.done() end end
    function W.input() return true end
    return W
  end
  if env.prewarm then pcall(env.prewarm, SOUNDS, 1) end
  local ectx = model.ctx or {}
  local Kb = env.keyboard

  local st = { pages = {}, kb = nil, toast = nil, toastAt = -10, t0 = now(), valuesAt = -1 }
  W.state = st
  local function page() return st.pages[#st.pages] end

  -- (a row's words, kept: the engine's own value() builds a new string each time it's asked -- asked when the
  -- page shows, after a change, and twice a second)
  local function refresh(p)
    p = p or page()
    if not p then return end
    for _, r in ipairs(p.rows) do
      if r.reset then r.valueText = nil
      elseif r.value then
        local ok, v = pcall(r.value, ectx)
        r.valueText = ok and v ~= nil and Os.sentence(tostring(v)) or nil
        if r.on then
          local okO, yes = pcall(r.on)
          r.isOn = okO and yes == true
        elseif r.kind == "toggle" then
          r.isOn = r.valueText ~= nil and r.valueText:upper() == "ON"
        end
      end
    end
    st.valuesAt = now()
  end
  local function push(p)
    p.cur = p.cur or 1
    p.top = p.top or 0
    p.shown = p.shown or 0
    p.at = now()
    st.pages[#st.pages + 1] = p
    refresh(p)
  end
  local function openPage(title, rows)
    push({ title = Os.sentence(title), rows = Os.pageRows(ectx, rows) })
    se("SE_SELECT")
  end
  -- (a page made again -- MODS' after a change -- the cursor kept on the same row)
  local function rebuild(p)
    if not (p and p.rebuild) then return end
    local id = p.rows[p.cur] and p.rows[p.cur].id
    pcall(p.rebuild)
    for i, x in ipairs(p.rows) do if x.id == id then p.cur = i end end
    p.cur = max(1, min(p.cur, #p.rows))
  end
  -- (what a model's rows reach in the window: MODS' pages, questions, notes)
  local finish
  local ui = {}
  function ui.push(p)
    push(p)
    se("SE_SELECT")
  end
  function ui.ok(text) st.sheet = { text = tostring(text or ""), at = now(), sel = 1 } end
  function ui.confirm(text, yes) st.sheet = { text = tostring(text or ""), yes = yes, at = now(), sel = 2 } end
  function ui.toast(text) st.toast, st.toastAt = tostring(text or ""), now() end
  function ui.close() if finish then finish() end end
  W.ui = ui
  function ui.refresh()
    for _, p in ipairs(st.pages) do rebuild(p) end
    refresh()
  end
  -- (WoobOS's own row at the top: its page here, not through the mod manager)
  function W.openMod(modId)
    local p = Os.modPage(modId, model.game or ectx.game)
    if not p then return false end
    push(p)
    se("SE_SELECT")
    return true
  end
  -- (MODS asked for from OPTIONS: its pages here)
  function W.openMods(mm)
    if not (mm and mm.top) then return false end
    local ok, p = pcall(mm.top, ui)
    if not (ok and p) then return false end
    st.mods = mm
    push(p)
    se("SE_SELECT")
    return true
  end
  if model.kind == "options" then
    local top = model.build(openPage)
    top.title = T("opt.title")
    push(top)
    Os.inWindow = W.openMod
    if Mm then Mm.inWindow = W.openMods end
  elseif model.kind == "mods" then
    st.mods = model
    push(model.top(ui))
  else
    push(model.page)
  end

  finish = function()
    if Os.inWindow == W.openMod then Os.inWindow = nil end
    if Mm and Mm.inWindow == W.openMods then Mm.inWindow = nil end
    if ctx.done then ctx.done() end
  end
  local function back()
    se("SE_SELECT")
    if #st.pages > 1 then
      st.pages[#st.pages] = nil
      rebuild(page())
      refresh()
      return
    end
    finish()
  end

  -- (a value changed: saved, a mod's tree made again with the cursor on the same option)
  local function changed(p, r, persisted)
    if persisted and model.persist then model.persist() end
    if p.rebuild then
      local id = r and r.id
      p.rebuild()
      for i, x in ipairs(p.rows) do if x.id == id then p.cur = i end end
      p.cur = max(1, min(p.cur, #p.rows))
    end
    refresh(p)
  end
  local function step(p, r, dir)
    if not (r and r.step) then return false end
    local ok, res = pcall(r.step, ectx, dir)
    if not ok then return false end
    se("SE_SELECT")
    changed(p, r, res == true)
    return true
  end
  local function activate(p, r)
    if not r then return end
    if r.reset then
      pcall(r.activate)
      changed(p, r, false)
      st.toast, st.toastAt = T("opt.restored"), now()
      se("SE_SELECT")
      return
    end
    if r.kind == "text" and Kb then
      st.kb = Kb.new(r.valueText or "", r.maxLen or 7)
      st.kbRow, st.kbAt = r, now()
      se("SE_SELECT")
      return
    end
    -- (a mod: its own page)
    if r.open then
      local ok, np = pcall(r.open)
      if ok and np then ui.push(np) end
      return
    end
    if r.activate then
      se("SE_SELECT")
      local ok, err = pcall(r.activate, ectx)
      if not ok and env.log then pcall(env.log, "an OPTIONS row: %s", tostring(err)) end
      Os.lendShaderLayer()
      if p.rebuild and page() == p then rebuild(p) end
      refresh()
      return
    end
    step(p, r, 1)
  end

  -- (the sheet: OK, or Cancel / OK)
  local function sheetAnswer(yes)
    local sh = st.sheet
    st.sheet = nil
    se("SE_SELECT")
    if yes and sh and sh.yes then
      local ok, err = pcall(sh.yes)
      if not ok and env.log then pcall(env.log, "a MODS answer: %s", tostring(err)) end
    end
    ui.refresh()
  end

  -- ------- input

  local function keyboardInput(input, nav)
    local kb = st.kb
    if nav then
      if nav.left then Kb.nav(kb, -1, 0) elseif nav.right then Kb.nav(kb, 1, 0)
      elseif nav.up then Kb.nav(kb, 0, -1) elseif nav.down then Kb.nav(kb, 0, 1) end
    end
    local function done(text)
      local p, r = page(), st.kbRow
      st.kb, st.kbRow = nil, nil
      if text and r and r.setText then
        pcall(r.setText, text)
        changed(p, r, false)
      end
    end
    if input:wasPressed("a") then
      local res = Kb.type(kb, kb.cur, now())
      if res == "ok" then se("SE_SELECT") return done(kb.text) end
      se(res == "full" and "SE_FAILURE" or "SE_SELECT")
    elseif input:wasPressed("b") then
      if Kb.back(kb, now()) == "empty" then st.kb, st.kbRow = nil, nil end
      se("SE_SELECT")
    elseif input:wasPressed("start") then Kb.toOk(kb)
    elseif input:wasPressed("select") then Kb.toggle(kb) end
  end

  function W.input(input, nav)
    if st.kb then
      keyboardInput(input, nav)
      return true
    end
    if st.sheet then
      local sh = st.sheet
      if nav and (nav.left or nav.right) and sh.yes then
        sh.sel = nav.left and 1 or 2
        se("SE_SELECT")
      elseif input:wasPressed("a") then
        sheetAnswer(sh.yes == nil or sh.sel == 2)
      elseif input:wasPressed("b") then
        sheetAnswer(false)
      end
      return true
    end
    local p = page()
    if not p then return true end
    local n = #p.rows
    if nav and nav.up and n > 0 then
      p.cur = p.cur > 1 and p.cur - 1 or n
      se("SE_SELECT")
    elseif nav and nav.down and n > 0 then
      p.cur = p.cur < n and p.cur + 1 or 1
      se("SE_SELECT")
    elseif nav and (nav.left or nav.right) then
      step(p, p.rows[p.cur], nav.left and -1 or 1)
    elseif input:wasPressed("a") then
      activate(p, p.rows[p.cur])
    elseif input:wasPressed("b") or input:wasPressed("start") then
      back()
    end
    return true
  end

  function W.tap(arg)
    if type(arg) ~= "number" then return end
    if st.kb then
      if arg == A.SCRIM then st.kb, st.kbRow = nil, nil return end
      if arg > A.KEY and arg <= A.KEY + Kb.keys(st.kb) then
        local res = Kb.type(st.kb, arg - A.KEY, now())
        if res == "ok" then
          local p, r, text = page(), st.kbRow, st.kb.text
          st.kb, st.kbRow = nil, nil
          if r and r.setText then pcall(r.setText, text) changed(p, r, false) end
        end
        se("SE_SELECT")
      end
      return
    end
    if st.sheet then
      if arg == A.SHEET + 2 then return sheetAnswer(true) end
      if arg == A.SHEET + 1 or arg == A.SCRIM then return sheetAnswer(st.sheet.yes == nil) end
      return
    end
    local p = page()
    if arg == A.BACK then return back() end
    if arg > A.INC and arg <= A.INC + #p.rows then
      p.cur = arg - A.INC
      return step(p, p.rows[p.cur], 1)
    end
    if arg > A.DEC and arg <= A.DEC + #p.rows then
      p.cur = arg - A.DEC
      return step(p, p.rows[p.cur], -1)
    end
    if arg > A.ROW and arg <= A.ROW + #p.rows then
      p.cur = arg - A.ROW
      return activate(p, p.rows[p.cur])
    end
  end

  function W.scroll(dy)
    local p = page()
    if p then p.top = max(0, min((p.contentH or 0) - (p.viewH or 0), p.top - dy)) p.dragged = true end
  end
  function W.hints() return nil end
  function W.close()
    if Os.inWindow == W.openMod then Os.inWindow = nil end
    if Mm and Mm.inWindow == W.openMods then Mm.inWindow = nil end
  end

  -- ------- drawing

  local function tagColour(name)
    local h = 0
    for i = 1, #name do h = (h * 31 + name:byte(i)) % 997 end
    return TAGS[h % #TAGS + 1]
  end
  local G
  -- (a switch: green with its knob right when on)
  local function switch(x, y, on, k)
    local w, h = 13, 7.4
    K.col(on and C.green or C.track)
    K.box("fill", K.R(x, y, w, h), h / 2)
    local kx = x + h / 2 + (w - h) * k
    K.col(C.black, 0.12)
    G.circle("fill", K.X(kx), K.Y(y + h / 2 + 0.3), (h / 2 - 0.6) * K.sc)
    K.col(C.white)
    G.circle("fill", K.X(kx), K.Y(y + h / 2), (h / 2 - 0.7) * K.sc)
  end

  -- (a sheet's button: the chosen one ringed)
  local function sheetButton(sh, i, bx, by, bw, bh, word, strong)
    local b = K.R(bx, by, bw, bh)
    K.col(strong and C.accent or C.track, strong and 1 or 0.5)
    K.box("fill", b, bh / 2)
    if sh.sel == i then K.ring(b, bh / 2, C.accent, 0.9, 0.7) end
    K.bold(word, bx, by + (bh - 4.4 * 1.2) / 2, 4.4, strong and C.white or C.ink, "center", bw)
    K.addHit(b, "win", A.SHEET + i)
  end

  local ROW_H = 13
  local function rowH() return ROW_H + (K.textScale() - 1) * 4 end

  local function drawRow(p, i, r, x, y, w, h, sel, clock)
    local depth = r.depth or 0
    local ind = depth * 8
    -- (the tree: a line down from the parent's row and across to this one)
    if depth > 0 then
      local lx = x + ind - 3.5
      K.col(C.line)
      G.setLineWidth(max(1, 0.45 * K.sc))
      G.line(K.X(lx), K.Y(y - 1.5), K.X(lx), K.Y(y + h / 2), K.X(lx + 2.6), K.Y(y + h / 2))
    end
    local b = K.R(x + ind, y, w - ind, h)
    K.glass(b, 4, sel and 0.95 or 0.72, sel and C.white or nil)
    if sel then K.ring(b, 4, C.accent, 0.9, 0.7) end
    K.addHit(b, "win", A.ROW + i)
    local lx = b[1] + 5
    local ly = y + (h - 4.8 * 1.2) / 2
    -- (a mod's badge: its first letter on its kind's colour)
    local bd = r.badge
    if bd then
      local s = h - 4.4
      K.col(bd.colour)
      K.box("fill", K.R(lx - 1.5, y + 2.2, s, s), s * 0.28)
      K.bold(bd.letter, lx - 1.5, y + 2.2 + (s - 4.4 * 1.2) / 2, 4.4, C.white, "center", s)
      lx = lx + s + 1.5
    end
    if r.reset then
      local word = T("opt.reset")
      K.bold(word, b[1], ly, 4.6, C.red, "center", b[3])
      return
    end
    -- (the control's room at the right, then the label in what's left)
    local right = b[1] + b[3] - 5
    local cw = 0
    local kind = r.kind
    local vt = r.valueText
    if kind == "toggle" then
      cw = 13
      r.knob = K.approach(r.knob or (r.isOn and 1 or 0), r.isOn and 1 or 0, 1 / 60, 14)
      switch(right - 13, y + (h - 7.4) / 2, r.isOn, r.knob)
      K.addHit(K.R(right - 15, y, 17, h), "win", A.INC + i)
    elseif kind == "group" or kind == "action" then
      K.chevron(right - 1.5, y + h / 2, 2.6, C.soft, 1)
      cw = 4
      if vt and vt ~= "" then
        local vs = K.fit(vt, 4, b[3] * 0.4)
        K.text(vt, right - 6 - b[3] * 0.4, ly + 0.4, vs, C.soft, "right", b[3] * 0.4)
        cw = cw + min(b[3] * 0.4, K.width(vt, vs)) + 3
      end
    elseif vt and (r.step or kind == "text") then
      -- (the value between arrows; a text option's value alone)
      local vw = min(b[3] * 0.45, K.width(vt, 4.6) + 2)
      local arrows = kind ~= "text" and r.step ~= nil
      local aw = arrows and 6 or 0
      local vx = right - aw - vw
      local vs = K.fit(vt, 4.6, vw)
      K.bold(vt, vx, ly, vs, sel and C.accent or C.ink, "center", vw)
      if arrows then
        K.chevron(right - 1.5, y + h / 2, 2.4, sel and C.accent or C.faint, 1)
        K.chevron(vx - 4.5, y + h / 2, 2.4, sel and C.accent or C.faint, -1)
        K.addHit(K.R(right - aw - 1, y, aw + 2, h), "win", A.INC + i)
        K.addHit(K.R(vx - aw - 1, y, aw + 2, h), "win", A.DEC + i)
        cw = vw + aw * 2 + 1
      else
        cw = vw
      end
    elseif vt then
      local vs = K.fit(vt, 4.4, b[3] * 0.4)
      K.text(vt, right - b[3] * 0.4, ly + 0.3, vs, C.soft, "right", b[3] * 0.4)
      cw = min(b[3] * 0.4, K.width(vt, vs))
    end
    -- (another mod's row: its name on a tag after the label)
    local labelW = right - cw - 4 - lx
    local tagW = 0
    if r.modName then
      tagW = K.width(r.modName, 3.2) + 5
      labelW = labelW - tagW - 2
    end
    local ls = K.fit(r.label, depth > 0 and 4.6 or 4.9, max(10, labelW))
    local ink = (r.tone == "accent" and C.accent) or (r.tone == "red" and C.red) or C.ink
    if r.sub then
      -- (a word under it: where a mod stands)
      local ss = K.fit(r.sub, 3.3, max(10, labelW))
      local th = ls * 1.2 + ss * 1.2 + 0.4
      local ty = y + (h - th) / 2
      K.bold(r.label, lx, ty, ls, ink)
      local sc = (r.subTone == "accent" and C.accent) or (r.subTone == "red" and C.red)
        or (r.subTone == "green" and C.green) or C.soft
      K.text(r.sub, lx, ty + ls * 1.2 + 0.4, ss, sc)
    else
      K.bold(r.label, lx, y + (h - ls * 1.2) / 2, ls, ink)
    end
    if r.modName then
      local tx = lx + min(labelW, K.width(r.label, ls)) + 2.5
      local tb = K.R(tx, y + h / 2 - 2.7, tagW, 5.4)
      K.col(tagColour(r.modName), 0.9)
      K.box("fill", tb, 2.7)
      K.text(r.modName, tx, y + h / 2 - 1.95, 3.2, C.white, "center", tagW)
    end
  end

  function W.draw(body, clock, portrait)
    G = K.graphics()
    clock = now()
    local p = page()
    if not p then return end
    if clock - st.valuesAt > 0.5 then refresh(p) end
    local x, y, w, h = body[1], body[2], body[3], body[4]
    if K.backdrop then K.backdrop(body, clock, 0.35, 0.55, 0.95, 0.65, 0.45, 0.9) end
    -- (the top: back, the page's title, its place under the others)
    local tb = K.R(x, y, w, TOP_H)
    K.chevron(x + 6, y + TOP_H / 2, 3.4, C.accent, -1)
    local backWord = #st.pages > 1 and st.pages[#st.pages - 1].title or T("opt.done")
    K.text(backWord, x + 9.5, y + TOP_H / 2 - 2.9, K.fit(backWord, 4.8, w * 0.3), C.accent)
    K.addHit(K.R(x, y, 12 + K.width(backWord, 4.8), TOP_H), "win", A.BACK)
    local title = p.title or ""
    K.bold(title, x, y + TOP_H / 2 - 3.4, K.fit(title, 5.8, w * 0.5), C.ink, "center", w)
    -- (the chosen option's description, in a card along the foot, when it has one)
    local r0 = p.rows[p.cur]
    local desc = r0 and r0.desc or p.desc
    local dh = 0
    if desc and desc ~= "" then
      -- (as tall as its lines: measured when the option or the text size changes)
      if st.descOf ~= desc or st.descTS ~= K.textScale() or st.descW ~= w then
        local lines = math.ceil(K.width(desc, 3.9) * 1.1 / max(20, w - M * 2 - 10))
        st.descOf, st.descTS, st.descW = desc, K.textScale(), w
        st.descH = 6 + lines * K.lineH(3.9) * 1.06
      end
      dh = st.descH
    end
    local top = y + TOP_H + 1
    local listH = y + h - M - (dh > 0 and dh + 3 or 0) - top
    local rh, gap = rowH(), 2.2
    local n = #p.rows
    -- (a line with words over a row that starts a part: the rows other mods added, apart from the game's; each of
    -- MODS' sections. Worked out when the page's rows change)
    if p.divsOf ~= p.rows then
      p.divsOf, p.divs, p.divN = p.rows, {}, {}
      local fm, prev, count = false, nil, 0
      for i, r in ipairs(p.rows) do
        local word
        if r.section then
          if r.section ~= prev then word = r.section end
          prev = r.section
        elseif r.modName and not fm then
          fm, word = true, T("opt.mods")
        end
        if word then
          p.divs[i] = word
          count = count + 1
        end
        p.divN[i] = count
      end
    end
    local DIV = 11 + (K.textScale() - 1) * 4
    local divN = p.divN
    local function rowY(i) return (i - 1) * (rh + gap) + (divN[i] or 0) * DIV end
    local contentH = n * (rh + gap) + (divN[n] or 0) * DIV
    p.contentH, p.viewH = contentH, listH
    -- (the chosen one kept in view, the list easing to it)
    if p.followed ~= p.cur then
      p.followed = p.cur
      local a = rowY(p.cur)
      if a < p.top then p.top = a elseif a + rh > p.top + listH then p.top = a + rh - listH end
    end
    p.top = max(0, min(p.top, max(0, contentH - listH)))
    p.shown = K.approach(p.shown, p.top, 1 / 60, 16)
    local area = K.R(x, top, w, listH)
    K.scissor(area)
    local e = K.outCubic((clock - (p.at or 0)) / 0.25)
    local lx, lw = x + M + (1 - e) * 10, w - M * 2 - 2
    for i = 1, n do
      local ry = top + rowY(i) - p.shown
      local word = p.divs[i]
      if word and ry > top - DIV - 2 and ry - DIV < top + listH + 2 then
        local dy = ry - DIV / 2 - 1.5
        local ww = K.width(word, 3.6) + 6
        K.col(C.line)
        G.setLineWidth(max(1, 0.4 * K.sc))
        G.line(K.X(lx + 2), K.Y(dy), K.X(lx + lw / 2 - ww / 2), K.Y(dy))
        G.line(K.X(lx + lw / 2 + ww / 2), K.Y(dy), K.X(lx + lw - 2), K.Y(dy))
        K.text(word, lx, dy - 2.3, 3.6, C.soft, "center", lw)
      end
      if ry + rh > top - 2 and ry < top + listH + 2 then drawRow(p, i, p.rows[i], lx, ry, lw, rh, i == p.cur, clock) end
    end
    K.scissor(body)
    K.scrollbar(x + w - M + 0.6, top, listH, p.shown, listH, max(listH, contentH))
    if dh > 0 then
      local db = K.R(x + M, y + h - M - dh, w - M * 2, dh)
      K.glass(db, 5, 0.9)
      K.text(desc, db[1] + 5, db[2] + 3, 3.9, C.ink, "left", db[3] - 10)
    end
    -- (a note: defaults back)
    if st.toast and clock - st.toastAt < 1.8 then
      local tw = K.width(st.toast, 4.2) + 12
      local a = min(1, (1.8 - (clock - st.toastAt)) * 3)
      local f0 = K.getFade()
      K.setFade(f0 * a)
      K.glass(K.R(x + (w - tw) / 2, y + h - 22, tw, 10), 5, 0.92)
      K.text(st.toast, x, y + h - 19.6, 4.2, C.ink, "center", w)
      K.setFade(f0)
    end
    -- (a question: a sheet over a dim, OK -- or Cancel / OK)
    local sh = st.sheet
    if sh then
      K.col(C.black, 0.25)
      K.box("fill", body)
      K.addHit(body, "win", A.SCRIM)
      local sw = min(w - 16, 170)
      if sh.forW ~= sw or sh.forTS ~= K.textScale() then
        local lines = math.ceil(K.width(sh.text, 4.2) * 1.12 / max(20, sw - 14)) + select(2, sh.text:gsub("\n", ""))
        sh.forW, sh.forTS, sh.textH = sw, K.textScale(), lines * K.lineH(4.2) * 1.06
      end
      local bh = 11 + (K.textScale() - 1) * 3
      local shH = 8 + sh.textH + 5 + bh + 6
      local k = K.outBack(min(1, (clock - sh.at) / 0.22))
      local sb = K.R(x + (w - sw) / 2, y + (h - shH) / 2 + (1 - k) * 8, sw, shH)
      K.glass(sb, 7, 0.97, C.white)
      K.text(sh.text, sb[1] + 7, sb[2] + 7, 4.2, C.ink, "center", sw - 14)
      local by = sb[2] + shH - 6 - bh
      if sh.yes then
        local bw = (sw - 14 - 4) / 2
        sheetButton(sh, 1, sb[1] + 7, by, bw, bh, T("opt.cancel"), false)
        sheetButton(sh, 2, sb[1] + 7 + bw + 4, by, bw, bh, T("opt.ok"), true)
      else
        sheetButton(sh, 1, sb[1] + 7, by, sw - 14, bh, T("opt.ok"), true)
      end
    end
    -- (a text option: the keyboard over a dim)
    if st.kb then
      K.col(C.black, 0.25)
      K.box("fill", body)
      K.addHit(body, "win", A.SCRIM)
      local kw = min(w - 8, 236)
      local kh = Kb.height(kw)
      local k = K.outCubic((clock - st.kbAt) / 0.25)
      Kb.draw(st.kb, x + (w - kw) / 2, y + h - 3 - kh * k, kw, clock, A.KEY, T("kb.ok"), nil)
    end
  end

  return W
end
