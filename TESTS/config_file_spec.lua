-- TESTS/config_file_spec.lua — `.docmap.json`, and the precedence around it.
--
-- Its own file because the thing under test is a *merge order*, not a parser.
-- Three voices now answer the same questions — the defaults, the repository's
-- own file, the host's explicit table — and every bug this feature can have
-- is one of them winning where another should. A spec that only asserted
-- "the JSON was read" would pass while `source` from a spec was silently
-- losing to a file, which is the one outcome that would make a host's options
-- unreliable.
--
-- Real files under the temp dir rather than a mocked reader: `config.file`
-- exists precisely to read something off disk in a repository nobody
-- configured, and a mocked `io.open` would be asserting the mock agrees with
-- itself. Same reasoning `detect_source_spec.lua` states for its own trees.

return function(H)
  local eq, ok = H.eq, H.ok
  local cfg = require("documentation.config")
  local file = require("documentation.config.file")

  local root_dir = (vim.fn.tempname():gsub("\\", "/"))

  ---A repository with `lua/thing/init.lua` and, optionally, a `.docmap.json`.
  ---@param name string
  ---@param json string? Written verbatim, so a malformed case can be written.
  ---@return string abs
  local function repo(name, json)
    local abs = root_dir .. "/" .. name
    vim.fn.mkdir(abs .. "/lua/thing", "p")
    local fd = assert(io.open(abs .. "/lua/thing/init.lua", "w"))
    fd:write("---@module 'thing'\nlocal M = {}\nreturn M\n")
    fd:close()
    if json then
      local cf = assert(io.open(abs .. "/" .. file.NAME, "w"))
      cf:write(json)
      cf:close()
    end
    return abs
  end

  ---Collect warnings instead of showing them, so a spec asserting on a
  ---warning does not also print it into the run's output.
  ---@return table notify, string[] messages
  local function recorder()
    local messages = {}
    return {
      warn = function(msg)
        messages[#messages + 1] = msg
      end,
    },
      messages
  end

  -- ---------------------------------------------------------------------
  -- No file at all: the shape every existing repository has.
  -- ---------------------------------------------------------------------

  local bare = repo("bare")
  eq(file.load(bare), nil, "config.file: no .docmap.json is nil, not an empty table")
  eq(cfg.build(bare).branch, "main", "build: defaults survive an absent file")
  eq(cfg.build(bare).layers, nil, "build: an absent file adds no keys")

  -- ---------------------------------------------------------------------
  -- The file is read, and reaches a real option.
  -- ---------------------------------------------------------------------

  local configured = repo(
    "configured",
    [[{
      "title": "from-file",
      "branch": "develop",
      "tests_dir": "spec",
      "layers": [{ "from": "a", "to": "b", "why": "because" }]
    }]]
  )

  local opts = cfg.build(configured)
  eq(opts.title, "from-file", "build: the file overrides a derived value (title)")
  eq(opts.branch, "develop", "build: the file overrides a DEFAULTS value (branch)")
  eq(opts.tests_dir, "spec", "build: the file overrides tests_dir")
  eq(#opts.layers, 1, "build: layers arrive from the file as data")
  eq(opts.layers[1].why, "because", "build: a layer rule keeps its reason")

  -- ---------------------------------------------------------------------
  -- Precedence. The half most likely to regress, so it is asserted in both
  -- directions rather than once: a host's table beats the file, and the
  -- file beats a default — and neither statement implies the other.
  -- ---------------------------------------------------------------------

  local host = cfg.build(configured, { title = "from-host" })
  eq(host.title, "from-host", "build: an explicit opts table beats the file")
  eq(host.branch, "develop", "build: keys the host did not mention still come from the file")

  -- ---------------------------------------------------------------------
  -- `languages` has to reach source detection, which runs *before* the
  -- merge. This is the one ordering the implementation could get wrong
  -- while every assertion above still passed.
  -- ---------------------------------------------------------------------

  local polyglot = root_dir .. "/polyglot"
  vim.fn.mkdir(polyglot .. "/lua/thing", "p")
  vim.fn.mkdir(polyglot .. "/src", "p")
  for path, body in pairs({
    ["/lua/thing/init.lua"] = "local M = {}\nreturn M\n",
    ["/src/app.js"] = "export function a(){}\n",
  }) do
    local fd = assert(io.open(polyglot .. path, "w"))
    fd:write(body)
    fd:close()
  end
  local cf = assert(io.open(polyglot .. "/" .. file.NAME, "w"))
  cf:write([[{ "languages": ["lua"] }]])
  cf:close()

  local narrowed = cfg.sources(cfg.build(polyglot))
  eq(#narrowed, 1, "build: a file's `languages` narrows detection to one root")
  eq(narrowed[1], "lua/thing", "build: the disabled backend does not get to name the walk's root")

  -- ---------------------------------------------------------------------
  -- The allowlist. A repository may state facts about itself and not about
  -- the session reading it — the whole reason `REPO_KEYS` is an allowlist.
  -- ---------------------------------------------------------------------

  local pushy = repo(
    "pushy",
    [[{
      "title": "fine",
      "command_name": "Pwned",
      "watch": true,
      "telemetry": true,
      "nonsense": 1
    }]]
  )

  local note, messages = recorder()
  local loaded = file.load(pushy, note)
  eq(loaded.title, "fine", "config.file: a repository-owned key is kept")
  eq(loaded.command_name, nil, "config.file: a checkout cannot rename your commands")
  eq(loaded.watch, nil, "config.file: a checkout cannot start a watcher in your session")
  eq(loaded.telemetry, nil, "config.file: a checkout cannot switch your telemetry on")
  eq(loaded.nonsense, nil, "config.file: an unknown key is dropped")

  eq(#messages, 2, "config.file: host-only keys and typos are two warnings, not one")
  local joined = table.concat(messages, "\n")
  ok(
    joined:match("command_name") and joined:match("watch") and joined:match("telemetry"),
    "config.file: every rejected host-only key is named"
  )
  ok(joined:match("nonsense"), "config.file: an unrecognized key is named")

  -- `$schema` is what makes the file pleasant to write, so it must not be
  -- reported as one of those mistakes.
  local schema_only = repo("schema", [[{ "$schema": "./docs/docmap.schema.json", "branch": "x" }]])
  local quiet, quiet_msgs = recorder()
  eq(file.load(schema_only, quiet).branch, "x", "config.file: $schema does not stop the rest")
  eq(#quiet_msgs, 0, "config.file: $schema is not reported as an unknown key")

  -- ---------------------------------------------------------------------
  -- A malformed file warns and is ignored. Never fatal: this is read by CI
  -- jobs and by a desktop app scanning a tree nobody configured, and a JSON
  -- typo must not be able to stop a map from being generated at all.
  -- ---------------------------------------------------------------------

  local broken = repo("broken", "{ this is not json")
  local shout, shout_msgs = recorder()
  eq(file.load(broken, shout), nil, "config.file: malformed JSON yields no overrides")
  eq(#shout_msgs, 1, "config.file: malformed JSON warns exactly once")
  ok(shout_msgs[1]:match("%.docmap%.json"), "config.file: the warning names the file")

  local built = cfg.build(broken)
  eq(built.branch, "main", "build: a malformed file falls back to the defaults rather than failing")

  -- A JSON array is valid JSON and not a valid config: `decode` succeeds and
  -- the result is still unusable, which is a different path from a parse
  -- error and reached the same warning only by accident before it was
  -- asserted here.
  local listy = repo("listy", "[1, 2, 3]")
  local arr_note, arr_msgs = recorder()
  eq(file.load(listy, arr_note), nil, "config.file: a top-level array is not a config")
  eq(#arr_msgs, 1, "config.file: a top-level array warns")

  -- An empty object is not an error and not overrides either.
  eq(file.load(repo("empty", "{}")), nil, "config.file: an empty object yields nil, not {}")

  -- ---------------------------------------------------------------------
  -- This repository's own file, since it is now the only statement of the
  -- three layer rules that `scripts/gen_map.lua` and `standalone/docmap.lua`
  -- both used to carry a copy of. If it stops being read, the architecture
  -- check silently stops running — and a check that silently stops is worse
  -- than one that was never added.
  -- ---------------------------------------------------------------------

  local own = cfg.build((vim.fn.getcwd():gsub("\\", "/"):gsub("/+$", "")))
  eq(#(own.layers or {}), 3, "this repo's own .docmap.json still supplies its three layer rules")
  eq(
    own.repo_url,
    "https://github.com/StefanBartl/documentation.nvim",
    "this repo's own .docmap.json still supplies repo_url"
  )
end
