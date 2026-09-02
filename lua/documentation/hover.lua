---@module 'documentation.hover'
---@brief What the module under the cursor is, out of the generated map.
---@description
--- A dotted module name in a `require("…")` is a question every reader of
--- unfamiliar code has: what *is* that. The answer already exists — this
--- plugin writes `docs/map/module_map.json` with a summary, a function list
--- and a body for every module in a repository — and until now it was
--- reachable only by opening the map.
---
--- This registers a **position** preview with
--- [hover.nvim](https://github.com/StefanBartl/hover.nvim): the cursor rests
--- on `lib.nvim.bindings.usercmd.composer` and the float says what that
--- module does. No scan at runtime, no Treesitter, one file read of an
--- artifact that is already on disk.
---
--- **Why a position and not a source.** A source hands back a *target string*
--- for hover.nvim to classify, and the useful answer here is not a file — it
--- is a summary that exists only in the map. Handing back the module's source
--- path would preview its first twenty lines, which is the module header if
--- you are lucky and a license block if you are not. The summary is the
--- thing worth showing.
---
--- **A stale map is the hazard, and it is a quiet one.** The artifact is a
--- snapshot: nothing regenerates it when the code changes, and in at least
--- one repository here it is not even tracked. A preview from a stale map
--- does not look stale — it looks current, which is worse than looking
--- absent. So the float compares the artifact's mtime against the module's
--- own source file and says so when the source is newer. That is a cheap
--- check (one `fs_stat` on a file the map already names) and it turns a
--- silent wrong answer into a visible old one.
---
--- **A dotted name is not a path**, so this cannot collide with hover.nvim's
--- bare-path rules: those refuse a name with no separator and no resolvable
--- target, and a position preview is asked only after they have declined.
---
---@see documentation.generate

local M = {}

local api = vim.api
local uv = vim.uv or vim.loop

---@type boolean
local _registered = false

---@type table<string, { mtime: integer, nodes: table<string, table>, root: string }>
local _maps = {}

---@internal
--- The nearest `docs/map/module_map.json` above `start`, or nil.
---@param start string a directory
---@return string|nil artifact
---@return string|nil root the directory the artifact belongs to
local function find_map(start)
  local dir = start
  for _ = 1, 24 do
    if dir == "" then
      return nil
    end
    local candidate = dir .. "/docs/map/module_map.json"
    if uv.fs_stat(candidate) then
      return candidate, dir
    end
    local parent = vim.fs.dirname(dir)
    if not parent or parent == dir then
      return nil
    end
    dir = parent
  end
  return nil
end

---@internal
--- The map at `path`, keyed by module name. Cached by the artifact's mtime,
--- so a regenerated map is picked up without a restart and an unchanged one
--- is parsed once per session rather than once per hover.
---@param path string
---@param root string
---@return table<string, table>|nil nodes
---@return integer|nil mtime
local function load_map(path, root)
  local st = uv.fs_stat(path)
  if not st or not st.mtime then
    return nil
  end
  local mtime = st.mtime.sec

  local cached = _maps[path]
  if cached and cached.mtime == mtime then
    return cached.nodes, mtime
  end

  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local raw = fd:read("*a")
  fd:close()

  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= "table" or type(decoded.nodes) ~= "table" then
    return nil
  end

  local nodes = {}
  for _, node in ipairs(decoded.nodes) do
    if type(node) == "table" and type(node.module) == "string" and node.module ~= "" then
      nodes[node.module] = node
    end
  end

  _maps[path] = { mtime = mtime, nodes = nodes, root = root }
  return nodes, mtime
end

---@internal
--- The dotted name the cursor is inside, or nil.
---
--- Bounded by the characters a Lua module name is made of. Quotes and
--- parentheses are not among them, so `require("a.b.c")` yields `a.b.c`.
---@param line string
---@param col integer 0-based
---@return string|nil
local function dotted_at(line, col)
  if type(line) ~= "string" or line == "" then
    return nil
  end
  local allowed = "[%w_%.%-]"
  if not line:sub(col + 1, col + 1):match(allowed) then
    return nil
  end

  local first = col + 1
  while first > 1 and line:sub(first - 1, first - 1):match(allowed) do
    first = first - 1
  end
  local last = col + 1
  while last < #line and line:sub(last + 1, last + 1):match(allowed) do
    last = last + 1
  end

  local run = line:sub(first, last)
  -- At least one dot: a bare word is not a module name, and answering for one
  -- would mean looking every identifier up in the map.
  if not run:find(".", 1, true) then
    return nil
  end
  return run
end

---@internal
--- The float's content for `node`.
---@param node table
---@param artifact_mtime integer
---@param root string
---@return table
local function content_for(node, artifact_mtime, root)
  local lines = {}

  if type(node.summary) == "string" and node.summary ~= "" then
    for _, part in ipairs(vim.split(node.summary, "\n", { plain = true })) do
      lines[#lines + 1] = part
    end
  else
    lines[#lines + 1] = "(no summary in the map)"
  end

  local funcs = type(node.functions) == "table" and #node.functions or 0
  local requires = type(node.requires) == "table" and #node.requires or 0
  local required_by = type(node.required_by) == "table" and #node.required_by or 0
  lines[#lines + 1] = ""
  lines[#lines + 1] = ("%d function%s  ·  requires %d  ·  required by %d"):format(
    funcs,
    funcs == 1 and "" or "s",
    requires,
    required_by
  )

  -- The staleness check, and the shape of `node.path` is the whole subtlety:
  -- it can name a *file* (`lua/x/y.lua`) or the *directory* of a module with
  -- an `init.lua` in it. Statting the directory is the obvious mistake and a
  -- silent one -- a directory's mtime moves when entries are added or
  -- removed, not when a file inside it is edited, so an edited module would
  -- look current forever.
  if type(node.path) == "string" and node.path ~= "" then
    local base = root .. "/" .. node.path
    local newest = nil
    for _, candidate in ipairs({ base, base .. ".lua", base .. "/init.lua" }) do
      local st = uv.fs_stat(candidate)
      if st and st.type == "file" and st.mtime then
        newest = math.max(newest or 0, st.mtime.sec)
      end
    end
    if newest and newest > artifact_mtime then
      lines[#lines + 1] = ""
      lines[#lines + 1] = "! the source is newer than the map -- regenerate it"
    end
  end

  return { lines = lines, title = node.module }
end

--- Register the position preview with hover.nvim, if it is installed.
---@return boolean registered
function M.setup()
  if _registered then
    return true
  end

  local ok, registry = pcall(require, "hover.registry")
  if not ok or type(registry) ~= "table" or type(registry.register) ~= "function" then
    return false
  end
  if type(registry.position_at) ~= "function" then
    return false
  end

  registry.register("documentation.nvim", {
    positions = {
      ---@param bufnr integer
      ---@param row integer 1-based
      ---@param col integer 0-based
      ---@return table|nil
      function(bufnr, row, col)
        if not api.nvim_buf_is_valid(bufnr) then
          return nil
        end
        local line = api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
        local name = dotted_at(line, col)
        if not name then
          return nil
        end

        local buf_name = api.nvim_buf_get_name(bufnr)
        local start = buf_name ~= "" and vim.fs.dirname(buf_name) or (uv.cwd() or "")
        local artifact, root = find_map(start)
        if not artifact or not root then
          return nil
        end

        local nodes, mtime = load_map(artifact, root)
        if not nodes or not mtime then
          return nil
        end
        local node = nodes[name]
        if not node then
          return nil
        end

        return content_for(node, mtime, root)
      end,
    },
  })

  _registered = true
  return true
end

---@internal
--- The dotted-name test on its own, for the spec suite.
---@param line string
---@param col integer
---@return string|nil
function M.dotted_at(line, col)
  return dotted_at(line, col)
end

---@internal
--- Forget the registration and the parsed maps. Tests only.
---@return nil
function M._reset()
  _registered = false
  _maps = {}
end

return M
