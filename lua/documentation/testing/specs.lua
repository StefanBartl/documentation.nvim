---@module 'documentation.testing.specs'
--- Finding a project's spec files and reading which modules each one needs.
---
--- A spec "covers" a module when it requires it, or requires something that
--- loads it (the graph carries the second half). This file only produces the
--- first half: the modules a spec file names, read as text. It errs towards
--- "needs more", never less:
---
---   * `require("a.b")`, `require "a.b"`, `pcall(require, "a.b")` name a module;
---   * `require("a.dialect." .. name)` names a PREFIX: every module below it;
---   * `require(name)` (a variable) is DYNAMIC: the spec may need anything, so
---     it can never be proven unaffected.
---
--- Comment lines are ignored, strings are not. Discovery follows the
--- conventional layout (`<tests_dir>/**/*_spec.lua`, `TESTS` by default) plus
--- an optional per-repository list, and treats every path as untrusted input:
--- roots must be repository-relative and may not climb out of it.

local M = {}

---Largest spec file read (a bigger file is reported unreadable, never cut).
M.MAX_FILE_BYTES = 2 * 1024 * 1024
---Most spec files one discovery returns.
M.MAX_SPECS = 5000

-- Directories that hold fixtures and dependencies, never specs.
local SKIP_DIRS = { fixtures = true, [".deps"] = true, node_modules = true, [".git"] = true }

---A repository-relative path that stays inside the repository.
---@param p any
---@return string|nil clean Forward slashes, no `.` segments; nil when refused.
function M.clean_rel(p)
  if type(p) ~= "string" or p == "" or #p > 500 or p:find("[%z\1-\31]") then
    return nil
  end
  p = p:gsub("\\", "/")
  if p:sub(1, 1) == "/" or p:match("^%a:") then
    return nil
  end
  local parts = {}
  for seg in p:gmatch("[^/]+") do
    if seg == ".." then
      -- Resolved against what came before; a climb above the start is a path
      -- out of the repository and refused.
      if #parts == 0 then
        return nil
      end
      table.remove(parts)
    elseif seg ~= "." then
      parts[#parts + 1] = seg
    end
  end
  if #parts == 0 then
    return nil
  end
  return table.concat(parts, "/")
end

---@param root string Absolute repository root (forward slashes).
---@param tests_dir string|nil Default "TESTS".
---@param spec_roots any Optional extra roots: directories or single `.lua` files, repo-relative.
---@return string[] specs Repo-relative, sorted, unique.
---@return Documentation.Testing.Gap[] problems Roots that were refused or unreadable.
function M.discover(root, tests_dir, spec_roots)
  local uv = vim.uv or vim.loop
  local problems = {}
  local roots = {}

  local conventional = M.clean_rel(tests_dir or "TESTS")
  if conventional then
    roots[#roots + 1] = { rel = conventional, implicit = true }
  end
  if spec_roots ~= nil and type(spec_roots) ~= "table" then
    problems[#problems + 1] = {
      kind = "invalid_spec_root",
      message = "spec_roots must be a list of repository-relative paths",
    }
  elseif type(spec_roots) == "table" then
    for _, r in ipairs(spec_roots) do
      local clean = M.clean_rel(r)
      if clean then
        roots[#roots + 1] = { rel = clean }
      else
        problems[#problems + 1] = {
          kind = "invalid_spec_root",
          message = ("spec root refused (not a path inside the repository): %s"):format(
            type(r) == "string" and vim.inspect(r:sub(1, 80)) or type(r)
          ),
        }
      end
    end
  end

  local seen, out = {}, {}
  ---@param rel string
  local function add(rel)
    local key = rel:lower()
    if not seen[key] and #out < M.MAX_SPECS then
      seen[key] = true
      out[#out + 1] = rel
    end
  end

  for _, r in ipairs(roots) do
    local abs = root .. "/" .. r.rel
    local st = uv.fs_stat(abs)
    if not st then
      -- The conventional directory missing is a normal state (a project
      -- without specs); an explicitly listed root that is missing is not.
      if not r.implicit then
        problems[#problems + 1] = {
          kind = "invalid_spec_root",
          path = r.rel,
          message = "spec root does not exist: " .. r.rel,
        }
      end
    elseif st.type == "file" then
      if r.rel:sub(-4) == ".lua" then
        add(r.rel)
      end
    elseif st.type == "directory" then
      local ok, files, errors = pcall(function()
        return require("lib.nvim.fs.collect_recursive").files(abs, {
          ignore = function(p, is_dir)
            if is_dir then
              return SKIP_DIRS[p:match("([^/]+)$") or ""] == true
            end
            return false
          end,
        })
      end)
      if ok and type(files) == "table" then
        for _, f in ipairs(files) do
          if f:sub(-9) == "_spec.lua" then
            add(r.rel .. "/" .. f:sub(#abs + 2))
          end
        end
        if type(errors) == "table" and #errors > 0 then
          problems[#problems + 1] = {
            kind = "invalid_spec_root",
            path = r.rel,
            message = "part of the spec root could not be read: " .. tostring(errors[1]),
          }
        end
      end
    end
  end

  table.sort(out)
  return out, problems
end

---Read one file whole, within the size cap.
---@param abs string
---@return string|nil text
---@return string|nil err
function M.read_capped(abs)
  local uv = vim.uv or vim.loop
  local st = uv.fs_stat(abs)
  if not st or st.type ~= "file" then
    return nil, "not a regular file"
  end
  if st.size > M.MAX_FILE_BYTES then
    return nil, ("larger than %d bytes"):format(M.MAX_FILE_BYTES)
  end
  local fd = io.open(abs, "rb")
  if not fd then
    return nil, "cannot be opened"
  end
  local text = fd:read("*a")
  fd:close()
  return text, nil
end

---The computed requires of a source: the literal heads of `require("a.b." .. k)`
---and whether a bare `require(variable)` / `pcall(require, variable)` occurs.
---Shared by the spec scan and the check for dynamic loaders in the graph.
---@param src string
---@return string[] prefixes Literal heads of computed names (end with a dot), sorted.
---@return boolean dynamic `require(<expression>)` with no literal head somewhere.
function M.scan_computed(src)
  local prefixes, pseen = {}, {}
  local dynamic = false
  for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    if not line:match("^%s*%-%-") then
      for p in line:gmatch("require%s*[%(,]?%s*['\"]([%w%._%-]+%.)['\"]%s*%.%.") do
        if not pseen[p] then
          pseen[p] = true
          prefixes[#prefixes + 1] = p
        end
      end
      -- A variable argument: `require(name)`, `pcall(require, name)`.
      if line:match("[^%w_]require%s*%(%s*[%a_]") or line:match("^%s*require%s*%(%s*[%a_]") then
        dynamic = true
      end
      if line:match("pcall%s*%(%s*require%s*,%s*[%a_]") then
        dynamic = true
      end
    end
  end
  table.sort(prefixes)
  return prefixes, dynamic
end

---What a spec's source says it needs.
---@param src string
---@return string[] modules Literal module names.
---@return string[] prefixes Literal heads of computed names (end with a dot).
---@return boolean dynamic `require(<expression>)` somewhere.
function M.scan_text(src)
  local deps = require("documentation.core.deps")
  local modules, seen = {}, {}
  for _, req in ipairs(deps.extract_source(src)) do
    if not seen[req.module] then
      seen[req.module] = true
      modules[#modules + 1] = req.module
    end
  end

  local prefixes, dynamic = M.scan_computed(src)
  table.sort(modules)
  return modules, prefixes, dynamic
end

---Read and scan one spec file.
---@param root string
---@param rel string
---@return Documentation.Testing.SpecInfo
function M.read(root, rel)
  local text, err = M.read_capped(root .. "/" .. rel)
  if not text then
    return { path = rel, modules = {}, prefixes = {}, dynamic = false, unreadable = err }
  end
  local modules, prefixes, dynamic = M.scan_text(text)
  return { path = rel, modules = modules, prefixes = prefixes, dynamic = dynamic }
end

return M
