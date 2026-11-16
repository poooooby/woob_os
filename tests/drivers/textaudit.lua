-- The text-size audit the drivers share (showcase.lua's SHOWCASE_TEXT, desktop_probe.lua's PROBE_TEXT): one
-- frame's texts drawn at 100% and at `pct` (Settings' text size, the kit's K.audit / K.auditIssues), and
-- what's new at `pct`: texts running over each other ("overlap") or out past their clip ("clipX" /
-- "clipY"). What's there at 100% too (a list's row cut at its end, a ticker) isn't counted.
--
--   local audit = dofile("mods/woob_os/tests/drivers/textaudit.lua")(U, X)
--   audit(pct) -> { "kind | text | other" (xN), ... }, texts drawn ; the text size is left at `pct`
--   audit.restore() puts Settings' text size back as it was

return function(U, X)
  local Kt, env, Settings = X._test.kit, X._test.env, X._test.settings
  local was = Settings and Settings.get("textSize", nil)
  local function at(pct)
    env.setSetting("textSize", pct)
    U.wait(3)
    Kt.audit = { n = 0 }
    U.wait(1)
    local A = Kt.audit
    Kt.audit = nil
    local got = {}
    for _, it in ipairs(Kt.auditIssues(A)) do
      local key = it[1] .. " | " .. it[2] .. (it[3] and (" | " .. it[3]) or "")
      got[key] = (got[key] or 0) + 1
    end
    return got, A.n
  end
  local audit = setmetatable({}, { __call = function(_, pct)
    local base = at(100)
    local big, n = at(pct)
    local out = {}
    for key, c in pairs(big) do
      local extra = c - (base[key] or 0)
      if extra > 0 then out[#out + 1] = key .. (extra > 1 and (" (x" .. extra .. ")") or "") end
    end
    table.sort(out)
    return out, n
  end })
  function audit.restore() env.setSetting("textSize", was or 100) end
  return audit
end
