-- TESTS/binding_conflict_spec.lua — check.lua's `binding-conflict`
--
-- The check is meaningless for a plugin and valuable for a *config*, so its
-- fixtures are config-shaped. Every case below is one distinction between "a
-- binding was silently overridden" and "a binding was deliberately layered",
-- which is the whole difference between a check people keep on and one they
-- turn off in the first week.

return function(H)
  local fmsg = require("documentation.core.findings").format
  local eq = H.eq

  local root = (vim.fn.tempname():gsub("\\", "/"))
  local n = 0

  ---Build a config-shaped tree and return its `binding-conflict` messages,
  ---sorted so the assertions do not depend on finding order.
  ---@param files table<string, string> Repo-relative path to contents.
  ---@return string[]
  local function conflicts(files)
    n = n + 1
    local abs = ("%s/case%d"):format(root, n)
    for rel, body in pairs(files) do
      local path = abs .. "/" .. rel
      vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
      local fd = io.open(path, "w")
      if fd then
        fd:write(body)
        fd:close()
      end
    end
    local opts = require("documentation.config").build(abs)
    local ir = require("documentation.core.scan").scan(opts)
    local out = {}
    for _, f in ipairs(require("documentation.core.check").run(ir, opts)) do
      if f.check == "binding-conflict" then
        out[#out + 1] = fmsg(f)
      end
    end
    table.sort(out)
    return out
  end

  local HEAD = "---@module 'conf'\n--- Config.\n"

  -- The case the check exists for: the same key, twice, in two files, where
  -- one of them simply never fires and nothing says so.
  do
    local found = conflicts({
      ["lua/conf/init.lua"] = HEAD
        .. 'vim.keymap.set("n", "<leader>ff", function() end)\nreturn {}\n',
      ["lua/conf/later.lua"] = HEAD
        .. 'vim.keymap.set("n", "<leader>ff", function() end)\nreturn {}\n',
    })
    eq(#found, 1, "binding-conflict: the same lhs in the same mode, twice, is one finding")
    eq(
      found[1]:match("^[^ ]+ [^ ]+ in mode %a") ~= nil,
      true,
      "binding-conflict: ... naming the key and the mode"
    )
  end

  -- Different modes are different bindings. `n` and `v` do not collide, and
  -- a check that said they did would fire on nearly every config.
  do
    local found = conflicts({
      ["lua/conf/init.lua"] = HEAD
        .. 'vim.keymap.set("n", "<leader>x", function() end)\nreturn {}\n',
      ["lua/conf/other.lua"] = HEAD
        .. 'vim.keymap.set("v", "<leader>x", function() end)\nreturn {}\n',
    })
    eq(#found, 0, "binding-conflict: the same lhs in different modes is not a conflict")
  end

  -- One call, several modes, is one registration. Counting it per mode would
  -- make every multi-mode map in every config a finding.
  do
    local found = conflicts({
      ["lua/conf/init.lua"] = HEAD
        .. 'vim.keymap.set({ "n", "v" }, "<leader>y", function() end)\nreturn {}\n',
    })
    eq(#found, 0, "binding-conflict: one call declaring two modes is one registration")
  end

  -- Buffer-local shadowing is the mechanism, not a mistake. This case also
  -- caught a real bug in bindings.lua, which read `buffer` through a
  -- string-only accessor and so reported every `{ buffer = true }` keymap as
  -- global.
  do
    local found = conflicts({
      ["lua/conf/init.lua"] = HEAD
        .. 'vim.keymap.set("n", "<leader>b", function() end, { buffer = true })\nreturn {}\n',
      ["lua/conf/other.lua"] = HEAD
        .. 'vim.keymap.set("n", "<leader>b", function() end, { buffer = true })\nreturn {}\n',
    })
    eq(#found, 0, "binding-conflict: buffer-local registrations do not conflict")
  end

  -- `buffer = 0` means the current buffer and is just as local as `true`.
  do
    local found = conflicts({
      ["lua/conf/init.lua"] = HEAD
        .. 'vim.keymap.set("n", "<leader>b", function() end, { buffer = 0 })\nreturn {}\n',
      ["lua/conf/other.lua"] = HEAD
        .. 'vim.keymap.set("n", "<leader>b", function() end, { buffer = 0 })\nreturn {}\n',
    })
    eq(#found, 0, "binding-conflict: buffer = 0 is buffer-local too, not a number to ignore")
  end

  -- User commands share the check because they are the same statement about
  -- a different namespace.
  do
    local found = conflicts({
      ["lua/conf/init.lua"] = HEAD
        .. 'vim.api.nvim_create_user_command("Reload", function() end, {})\nreturn {}\n',
      ["lua/conf/other.lua"] = HEAD
        .. 'vim.api.nvim_create_user_command("Reload", function() end, {})\nreturn {}\n',
    })
    eq(#found, 1, "binding-conflict: a user command registered twice is reported")
    eq(found[1]:find("Reload", 1, true) ~= nil, true, "binding-conflict: ... naming the command")
  end

  -- Three registrations are one finding listing three sites, not three
  -- findings — otherwise the noisiest key in a config produces the most
  -- output while saying the least.
  do
    local found = conflicts({
      ["lua/conf/init.lua"] = HEAD
        .. 'vim.keymap.set("n", "<leader>q", function() end)\nreturn {}\n',
      ["lua/conf/b.lua"] = HEAD .. 'vim.keymap.set("n", "<leader>q", function() end)\nreturn {}\n',
      ["lua/conf/c.lua"] = HEAD .. 'vim.keymap.set("n", "<leader>q", function() end)\nreturn {}\n',
    })
    eq(#found, 1, "binding-conflict: three registrations are one finding")
    eq(
      found[1]:find("registered 3 times", 1, true) ~= nil,
      true,
      "binding-conflict: ... which says how many"
    )
  end

  vim.fn.delete(root, "rf")
end
