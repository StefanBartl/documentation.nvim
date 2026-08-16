-- TESTS/usrcmds_actions_spec.lua — `bindings/usrcmds/init.lua`'s ACTIONS
-- table is the one real dispatch/completion source of truth; this guards
-- the two places that used to be independent, hand-typed copies of it
-- (`bindings/autocmds.lua`'s `:DocMap` args string, and this module's own
-- `usercmd.create` help text) against drifting out of sync again the way
-- the args string already had (missing `checklist`/`bindings`).

return function(H)
  local eq, ok = H.eq, H.ok

  local usrcmds = require("documentation.bindings.usrcmds")
  local names = usrcmds.action_names()

  ok(#names > 0, "action_names(): returns a non-empty list")

  -- ------------------------------------------------- autocmds.lua's args string
  do
    local autocmds = require("documentation.bindings.autocmds")
    local docmap = nil
    for _, entry in ipairs(autocmds.usrcmds) do
      if entry.name == "DocMap" then
        docmap = entry
      end
    end
    assert(docmap, "bindings/autocmds.lua: a DocMap entry exists")

    for _, name in ipairs(names) do
      ok(
        docmap.args:find(name, 1, true) ~= nil,
        ("bindings/autocmds.lua DocMap args is missing action %q"):format(name)
      )
    end
  end

  -- --------------------------------------------- usrcmds/init.lua's usage hints
  --
  -- Token-boundary check, not a plain substring search: "check" is itself a
  -- substring of "checklist", so a naive find() would report "check" as
  -- present even if it had been silently removed.
  do
    local hints = usrcmds.action_usage_hints
    ok(type(hints) == "string" and #hints > 0, "action_usage_hints: is a non-empty string")

    local bracketed = hints:match("^%[(.*)%]$")
    assert(bracketed, "action_usage_hints: is bracketed like [a|b|c]")

    local hinted = {}
    for token in (bracketed .. "|"):gmatch("(.-)|") do
      local head = token:match("^%S+")
      if head then
        hinted[head] = true
      end
    end

    for _, name in ipairs(names) do
      ok(
        hinted[name] == true,
        ("usrcmds/init.lua action_usage_hints is missing action %q"):format(name)
      )
    end
  end

  -- Regression: the real bug that motivated this spec.
  eq(vim.tbl_contains(names, "checklist"), true, "checklist is a real action")
  eq(vim.tbl_contains(names, "bindings"), true, "bindings is a real action")
end
