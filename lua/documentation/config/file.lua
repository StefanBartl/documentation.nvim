---@module 'documentation.config.file'
--- `.docmap.json` — the options a **repository** states about itself.
---
--- ## Why a file, and why here
---
--- The plugin's option surface has always been reachable from exactly one
--- place: a Lua table written by whoever *hosts* the engine. That is right for
--- a Neovim spec and wrong for everything else, and the gap was not
--- theoretical — it was three separate holes with one shape:
---
---   * `docmap-desktop` shells out to the standalone binary, which accepts
---     seven flags. Every other option was unreachable from the app, so its
---     "Project settings" dialog could offer exactly the two the CLI happened
---     to take, and its own comment says so: *"anything further belongs in the
---     engine first"*.
---   * `action.yml` exposes five inputs, and `IDEAS.md` §6.2 records why it
---     stops there: `layers` and `extra_checks` *"fit no input without
---     inventing a configuration language"*. Correct — for YAML inputs. The
---     answer to "this does not fit on a command line" is a file, not more
---     command line.
---   * `standalone/docmap.lua` hardcodes **this** repository's three layer
---     rules into every run over every tree, because a generic CLI had no
---     other way to be given any.
---
--- One file read by `config.build` closes all three at once, and closes them
--- for options that do not exist yet: a host that can already pass a table
--- gains nothing, and every host that cannot gains the whole surface.
---
--- ## Why JSON and not Lua
---
--- A Lua config file would be more expressive — `extra_checks` is a list of
--- *functions* and no data format holds one. It is also the wrong answer
--- here, and not by a small margin: this file is read out of a repository
--- that CI just cloned, or that a person added to a desktop app by pointing
--- at a directory. Executing it would make "look at this project's map" a
--- code-execution primitive on any tree, which is a far worse trade than
--- losing one option. `extra_checks` stays a host-side option, where the
--- person writing the callback is the person running it.
---
--- JSON over TOML/YAML for a duller reason: `vim.json.decode` is already in
--- `standalone/vim_shim.lua`, so the standalone binary reads this file with
--- no new dependency. A format needing a parser would have to ship one into a
--- build whose whole point is that it needs nothing.
---
--- ## What a repository may and may not say
---
--- `REPO_KEYS` below is an allowlist, not a denylist, and the split is the
--- design rather than a safety measure. A repository can state facts about
--- *itself* — where its sources are, what its layers are, which checks its
--- team decided are noise. It cannot state facts about *your session*: a
--- checkout you cloned must not be able to rename your commands, rebind your
--- keys, turn on a file watcher, or switch your telemetry on. Those are the
--- host's, and a file that could set them would make opening an unfamiliar
--- repository a decision rather than an action.
---
--- ## Precedence
---
--- `DEFAULTS` < derived (`source`, `title`) < **this file** < the host's
--- explicit `opts` < CLI flags. The file loses to an explicit table because
--- a host that passed one is answering a question the file also answers, and
--- the more specific voice should win — the same order `--exclude=` already
--- has over `opts.exclude` in `core/cli.lua`.
---
--- Read on every `build()` rather than cached: a `:DocMap` after editing
--- `.docmap.json` should use what the file now says, and one `io.open` of a
--- file measured in hundreds of bytes is not the cost worth trading that for.

local M = {}

---The file a repository states its options in.
---
---One name, at the root, dotfile-spelled. Not a candidate list like
---`features_dir`'s: those exist because a *convention* had two spellings in
---the wild before the option did, and this convention has none yet. A second
---accepted name would only make "why is my config ignored" a two-place
---question forever after.
M.NAME = ".docmap.json"

---Keys a repository is allowed to set about itself.
---
---Every entry is a fact about the tree. Deliberately **absent**, and the
---reason for each group:
---
---  `root`, `root_markers`   circular: this file is found *by* resolving the
---                           root, so a root written inside it could only
---                           ever agree or be wrong.
---  `extra_checks`           Lua functions; see the header on why this file
---                           is not executed.
---  `keys`, `which_key`,     yours, not the repository's. A checkout must not
---  `browse`, `command_name`,rebind your keys or rename your commands.
---  `browse_command_name`,
---  `progress_style`
---  `watch`, `watch_ms`,     side effects in your session: background scans,
---  `callhierarchy`,         extra LSP clients, published diagnostics, a push
---  `diagnostics`, `mdview`  to another plugin. A repository does not get to
---                           start those by being opened.
---  `telemetry`,             whether *you* collect data about your own
---  `serve_port`, `debug`    editing, which port on *your* machine is bound,
---                           how loud your session is.
---  `generate_all`           a list of other repositories on your disk.
---
---`telemetry_namespace` **is** here while `telemetry` is not, and that is the
---split working rather than an inconsistency: the namespace is the name this
---project's data is filed under, which is the project's own fact; whether any
---is collected is yours.
---@type table<string, true>
M.REPO_KEYS = {
  source = true,
  exclude = true,
  languages = true,
  lua_root = true,
  types_dir = true,
  out_dir = true,
  tests_dir = true,
  features_dir = true,
  checklist_dir = true,
  install_dir = true,
  title = true,
  repo_url = true,
  branch = true,
  layers = true,
  checks = true,
  quicks = true,
  dead_code = true,
  calls_heuristic = true,
  docs_heuristic = true,
  luals = true,
  luals_timeout_ms = true,
  snippet_max_lines = true,
  badge = true,
  godbolt = true,
  pdf = true,
  theme = true,
  diagram = true,
  consumers = true,
  tag_files = true,
  external_repos = true,
  plugins = true,
  bindings = true,
  telemetry_namespace = true,
}

---Read `path` whole, or `nil`.
---
---`io.open` rather than `lib.nvim.fs.read`: this module is bundled into the
---standalone binary and runs there under PUC Lua with only
---`standalone/vim_shim.lua`'s subset of `vim.*`, which has no `fs` surface at
---all. The same reason `core/features.lua` opens files by hand.
---@param path string
---@return string?
local function read(path)
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local text = fd:read("*a")
  fd:close()
  return text
end

---Load `<root>/.docmap.json`, if there is one.
---
---A malformed file is reported and then ignored, never fatal. This is read
---on the way into every scan, including the ones a CI job and a desktop app
---run unattended; a JSON typo that stopped the map from being generated at
---all would be a worse outcome than a map generated with the defaults and a
---warning saying why.
---
---The same goes for keys the allowlist rejects: they are named in the
---warning and dropped. Silence there is the failure this whole option
---surface exists to remove — somebody wrote a line, nothing happened, and
---nothing said why.
---@param root string Absolute repository root, forward slashes, no trailing slash.
---@param notify table? A `lib.nvim.notify`-shaped instance (`.warn(msg)`).
---@return table<string, any>? overrides `nil` when the repository ships no such file.
function M.load(root, notify)
  if type(root) ~= "string" or root == "" then
    return nil
  end

  local path = (root:gsub("\\", "/"):gsub("/+$", "")) .. "/" .. M.NAME
  local text = read(path)
  if not text or text:match("^%s*$") then
    return nil
  end

  local ok, decoded = pcall(vim.json.decode, text)
  if not ok or type(decoded) ~= "table" then
    if notify then
      notify.warn(
        ("%s: not readable as a JSON object%s"):format(
          M.NAME,
          ok and "" or (" — " .. tostring(decoded):gsub("^.*:%s*", ""))
        )
      )
    end
    return nil
  end

  -- Required here rather than at the top of the file: `documentation.config`
  -- requires *this* module, and a load-time require in the other direction
  -- would be a cycle. By the time anything calls `load`, both are loaded.
  local known = require("documentation.config").KNOWN_OPTS_KEYS

  local out, host_only, unknown = {}, {}, {}
  for key, value in pairs(decoded) do
    if M.REPO_KEYS[key] then
      out[key] = value
    -- `$schema` is skipped rather than reported: it is what an editor needs
    -- to offer completion in this file, it is inert to every reader here,
    -- and warning about the line that makes the file pleasant to write
    -- would be warning about doing the right thing.
    elseif key ~= "$schema" then
      -- Two lists, because they are two different mistakes and the fix for
      -- one is not the fix for the other. A real option that a repository
      -- may not set is a misunderstanding about *whose* setting it is —
      -- move it to your own spec. A key that is not an option at all is a
      -- typo. One message covering both would send half its readers looking
      -- in the wrong place.
      local list = known[key] and host_only or unknown
      list[#list + 1] = tostring(key)
    end
  end

  if notify then
    if #host_only > 0 then
      table.sort(host_only)
      notify.warn(
        ("%s: ignored — these belong to whoever opens the repository, not to it: %s"):format(
          M.NAME,
          table.concat(host_only, ", ")
        )
      )
    end
    if #unknown > 0 then
      table.sort(unknown)
      notify.warn(("%s: unrecognized key(s): %s"):format(M.NAME, table.concat(unknown, ", ")))
    end
  end

  return next(out) ~= nil and out or nil
end

return M
