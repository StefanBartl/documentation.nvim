-- TESTS/consumer_require_spec.lua — check.lua's `consumer-require-missing`
--
-- The check half of IDEAS.md §1.7, and the only half that can honestly be a
-- check: "nobody requires this module" is a floor, not a fact, so it stays a
-- report. "A consumer requires something I do not have" is a positive claim
-- about data that exists in writing.
--
-- Written against real checkouts on disk rather than mocked, because the
-- thing being tested is a join across committed artifacts and a mocked
-- filesystem would assert that the mock agrees with itself.

return function(H)
  local fmsg = require("documentation.core.findings").format
  local eq = H.eq

  local root = (vim.fn.tempname():gsub("\\", "/"))
  local function write(rel, body)
    local path = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local fd = io.open(path, "w")
    if fd then
      fd:write(body)
      fd:close()
    end
  end

  ---A committed consumer map: only the fields the join reads.
  ---@param name string Project directory name.
  ---@param externals string[]
  local function consumer(name, externals)
    local nodes = { { id = "lua/c", requires_external = externals } }
    write(name .. "/docs/map/module_map.json", vim.json.encode({ nodes = nodes }))
  end

  -- The library. `lib.here` exists; nothing declares `lib.gone`.
  write("thelib/lua/lib/init.lua", "---@module 'lib'\n--- Root.\nlocal M = {}\nreturn M\n")
  write("thelib/lua/lib/here.lua", "---@module 'lib.here'\n--- Present.\nreturn {}\n")

  consumer("alpha.nvim", { "lib.here", "lib.gone", "plenary.async" })
  consumer("beta.nvim", { "lib.gone" })
  consumer("gamma.nvim", { "lib.here" })

  local function findings(opts_extra)
    local opts = require("documentation.config").build(root .. "/thelib", opts_extra)
    local ir = require("documentation.core.scan").scan(opts)
    local out = {}
    for _, f in ipairs(require("documentation.core.check").run(ir, opts)) do
      if f.check == "consumer-require-missing" then
        out[#out + 1] = fmsg(f)
      end
    end
    table.sort(out)
    return out
  end

  -- Inert by default. Most projects are not libraries with a knowable
  -- consumer set, and a check that read whatever sat beside a checkout would
  -- be guessing at its most important input.
  eq(#findings({}), 0, "consumer-require-missing: silent unless opts.consumers names a directory")

  local found = findings({ consumers = root })
  eq(#found, 1, "consumer-require-missing: one finding per missing module, not per consumer")
  eq(
    found[1]:find("lib.gone", 1, true) ~= nil,
    true,
    "consumer-require-missing: names the module nothing declares"
  )
  eq(
    found[1]:find("alpha.nvim, beta.nvim", 1, true) ~= nil,
    true,
    "consumer-require-missing: ... and every consumer still pointing at it, sorted"
  )

  -- A consumer requiring a foreign library is not this library's business,
  -- and reporting every foreign require would bury the one that matters.
  eq(
    found[1]:find("plenary", 1, true),
    nil,
    "consumer-require-missing: externals outside this library's namespace are ignored"
  )

  -- The message has to carry the second explanation. A library reading only
  -- "they are broken" would go looking in the wrong repository.
  eq(
    found[1]:find("map predates a rename", 1, true) ~= nil,
    true,
    "consumer-require-missing: says a stale consumer map is the other explanation"
  )

  vim.fn.delete(root, "rf")
end
