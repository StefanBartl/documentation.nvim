---@module 'documentation.core.tools'
--- Reads a repo's own `lib.nvim.deps` manifest (`docs/install.json`, falling
--- back to `docs/INSTALL.md`) into `Documentation.Tools.Result` for the
--- `:DocMap tools` panel.
---
--- `lib.nvim` is an optional dependency here, the same posture
--- `bindings/progress.lua` takes toward `lib.nvim.progress`: even though this
--- plugin hard-requires lib.nvim elsewhere, a pinned or older install may not
--- ship the `deps` submodule yet, and this feature should degrade to "not
--- available" rather than error the whole scan.
---
--- Deliberately **not** `spec.find`/`spec.plugins` — those search
--- `runtimepath` and lazy.nvim's registry for *other* plugins' manifests,
--- which is the wrong shape here: this repo's own `docs/` is exactly one of
--- two known paths away, no search needed.
---
--- Declaration-only. Whether a declared tool is actually present on this
--- host is never resolved here and never lands on the result — that answer
--- differs by machine, and baking it into the IR would make `--check`'s
--- byte-compare depend on who last ran it, the same reason `ir.timing` stays
--- out of the artifact. `bin`/`required`/`why`/`pkg` as declared in the file
--- are deterministic, and that is exactly what this module returns.

local M = {}

local spec = require("documentation.core.soft_require").probe("lib.nvim.deps.spec")

--- Resolution order matches `lib.nvim.deps.spec`'s own `SPEC_FILES`: JSON
--- preferred when a repo ships both, since it has no line-oriented parsing
--- limits.
local SPEC_FILES = { "install.json", "INSTALL.md" }

---@param root string Repo root (`ctx.cfg.root` / `opts.root`).
---@param dir string? `opts.install_dir` — the directory holding the manifest. Default "docs".
---@return Documentation.Tools.Result|nil result `nil` when lib.nvim.deps is unavailable, or this repo ships neither spec file.
function M.resolve(root, dir)
  if not spec then
    return nil
  end

  -- One directory rather than a candidate list, unlike `features`/
  -- `checklist`: the *filenames* are already two, and `lib.nvim.deps.spec`
  -- owns that pair. Adding a second axis here would let a repository
  -- configure four combinations, three of which nobody has.
  --
  -- Normalised the same way `root` is, so `install_dir = "docs/"` and
  -- `"docs"` are one answer and `result.source` is one spelling — it is
  -- serialized into `module_map.json`, which `--check` byte-compares.
  local folder = (
    tostring(dir or "docs"):gsub("\\", "/"):gsub("^%./", ""):gsub("^/+", ""):gsub("/+$", "")
  )
  if folder == "." then
    folder = ""
  end

  local normalized = (root:gsub("\\", "/"):gsub("/+$", ""))
  for _, file in ipairs(SPEC_FILES) do
    -- A manifest at the repository root is `install.json`, not
    -- `./install.json`: `result.source` is serialized into
    -- `module_map.json` and rendered as a path in the page's Tools panel,
    -- and a dot segment there is a spelling nobody writes by hand.
    local rel = folder ~= "" and (folder .. "/" .. file) or file
    local result = spec.load(normalized .. "/" .. rel)
    if result then
      return {
        source = rel,
        tools = result.tools,
        errors = result.errors,
      }
    end
  end
  return nil
end

return M
