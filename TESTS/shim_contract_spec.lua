-- TESTS/shim_contract_spec.lua — what `core/` calls vs. what the standalone
-- build implements
--
-- **This exists because three defects reached a release behind a gate that
-- said nothing.** `scripts/ci.lua`'s `standalone` gate needs PUC Lua on
-- `PATH` with `lfs` and `dkjson`; where it does not find one it prints
-- *skipped* and the run still reports five green gates. On 2026-08-20 a
-- release build failed twice in a row on `core/` calling Neovim APIs the
-- shim does not implement — `node:start()` and `vim.pesc`, both introduced
-- that day, both invisible locally. Local green meant "four gates and a
-- shrug".
--
-- Three answers were possible. This is the third and the only
-- one that catches the *next* one before CI does, because it needs neither
-- PUC Lua nor the `lua_tree_sitter` rock: it reads what `core/` calls out of
-- a real parse, and asks the shim itself what it provides.
--
-- **How each half is answered, and why they differ.**
--
--   * `vim.*` is answered **exactly**: `standalone/vim_shim.lua` is loaded
--     here and looked up. Two things make that possible — fake `lfs` and
--     `dkjson` through `package.preload`, and unsetting `_G.vim` for the
--     duration, because the shim opens with `if _G.vim then return _G.vim
--     end` and would otherwise hand back Neovim's own table. That mistake
--     was made while writing this: every lookup answered "yes", including
--     names the shim demonstrably lacks.
--   * Node and query **methods** are answered by **classification**, not by
--     loading, and that is a real limit rather than a shortcut:
--     `standalone/treesitter.lua` installs its methods onto the metatable of
--     a node produced by the `lua_tree_sitter` binding, so enumerating them
--     needs the rock this spec deliberately does not require. What it can do
--     is fail on a name nobody has classified — which is exactly the shape
--     `node:start()` had.
--
-- **The gate is the unclassified name.** Every `vim.*` path and every method
-- name `core/` uses must be accounted for below. Adding a call to something
-- new fails this spec until someone says what it is — which is the question
-- that went unasked twice.

return function(H)
  local eq, ok = H.eq, H.ok

  local root = (vim.fn.getcwd():gsub("\\", "/"))

  -- ---------------------------------------------------------------------
  -- What `core/` actually calls, read off a real parse.
  --
  -- Not grep: a first pass with `grep -oE 'vim\.[a-z.]+'` reported 44 paths
  -- and 43 method names against the parser's 27 and 30, because doc-comments
  -- in this tree talk about `vim.*` constantly and CSS-ish prose contains
  -- things like `:not(`. A contract built on those numbers would be
  -- classifying fiction.
  -- ---------------------------------------------------------------------
  local function lua_files(dir)
    local out = {}
    local function walk(d)
      for name, kind in vim.fs.dir(d) do
        local p = d .. "/" .. name
        if kind == "directory" then
          walk(p)
        elseif name:sub(-4) == ".lua" then
          out[#out + 1] = p
        end
      end
    end
    walk(dir)
    return out
  end

  local DOT = vim.treesitter.query.parse("lua", "(dot_index_expression) @d")
  local METH =
    vim.treesitter.query.parse("lua", "(method_index_expression method: (identifier) @m)")

  local used_vim, used_method = {}, {}
  local files = lua_files(root .. "/lua/documentation/core")
  ok(#files > 50, "shim contract: found the core tree to read (" .. #files .. " files)")

  for _, path in ipairs(files) do
    local fd = assert(io.open(path, "rb"))
    local src = fd:read("*a")
    fd:close()
    local parser = vim.treesitter.get_string_parser(src, "lua")
    local tree = parser:parse()[1]:root()

    for id, node in DOT:iter_captures(tree, src) do
      if DOT.captures[id] == "d" then
        local text = vim.treesitter.get_node_text(node, src)
        -- Longest chain only: `vim.json.encode` is the call, `vim.json` is
        -- the step on the way and is implied by it.
        if text:match("^vim%.[%w_.]+$") then
          used_vim[text] = used_vim[text] or path
        end
      end
    end
    for id, node in METH:iter_captures(tree, src) do
      if METH.captures[id] == "m" then
        local name = vim.treesitter.get_node_text(node, src)
        used_method[name] = used_method[name] or path
      end
    end
  end

  -- ---------------------------------------------------------------------
  -- What `vim_shim.lua` provides — asked of the file, not declared here.
  -- ---------------------------------------------------------------------
  local saved_vim = _G.vim
  local saved_preload = { lfs = package.preload.lfs, dkjson = package.preload.dkjson }
  package.preload.lfs = function()
    return {
      attributes = function()
        return nil
      end,
      dir = function()
        return function()
          return nil
        end
      end,
    }
  end
  package.preload.dkjson = function()
    return {
      encode = function()
        return ""
      end,
      decode = function()
        return nil
      end,
      null = {},
    }
  end

  local chunk, load_err = loadfile(root .. "/standalone/vim_shim.lua")
  ok(chunk ~= nil, "shim contract: vim_shim.lua loads as a chunk — " .. tostring(load_err))

  local shim
  if chunk then
    _G.vim = nil
    local ok_run, result = pcall(chunk)
    -- Restored before any assertion below can longjmp out of this function:
    -- leaving `_G.vim` nil would take down every later spec in the run, and
    -- the failure would look like anything but this file.
    _G.vim = saved_vim
    package.preload.lfs = saved_preload.lfs
    package.preload.dkjson = saved_preload.dkjson
    ok(ok_run, "shim contract: vim_shim.lua runs with lfs/dkjson faked — " .. tostring(result))
    if ok_run then
      shim = result
    end
  end

  ok(shim ~= nil and shim ~= saved_vim, "shim contract: got the shim's table, not Neovim's own")

  local function shim_has(path)
    local cur = shim
    for part in path:gmatch("[^.]+") do
      if part ~= "vim" then
        if type(cur) ~= "table" then
          return false
        end
        cur = cur[part]
        if cur == nil then
          return false
        end
      end
    end
    return true
  end

  -- ---------------------------------------------------------------------
  -- `vim.*` paths `core/` uses that the shim does **not** provide, each with
  -- the reason it is allowed to be absent.
  --
  -- All three are `core/luals.lua`, and the reason is one fact: `--full`
  -- shells out to `lua-language-server` and is Neovim-only, so the
  -- standalone binary never reaches that module. If a fourth ever appears
  -- here, the question to ask is whether the standalone path can reach it —
  -- not whether the list can grow.
  -- ---------------------------------------------------------------------
  local ALLOWED_ABSENT = {
    ["vim.fn.executable"] = "core/luals.lua — probes for lua-language-server; --full is Neovim-only",
    ["vim.fn.tempname"] = "core/luals.lua — scratch dir for the --doc run, same reason",
    ["vim.wait"] = "core/luals.lua — bounded wait around the spawn, same reason",
  }

  local unprovided = {}
  for path in pairs(used_vim) do
    if not shim_has(path) and not ALLOWED_ABSENT[path] then
      unprovided[#unprovided + 1] = path .. "  (" .. used_vim[path]:gsub(".*/core/", "core/") .. ")"
    end
  end
  table.sort(unprovided)
  eq(
    table.concat(unprovided, "\n    "),
    "",
    "shim contract: every vim.* path core/ uses is in the shim, or listed as "
      .. "unreachable with a reason"
  )

  -- The exception list must not rot in the other direction either: an entry
  -- for something the shim has since implemented is a stale claim.
  for path, why in pairs(ALLOWED_ABSENT) do
    ok(
      used_vim[path] ~= nil,
      "shim contract: " .. path .. " is still used by core/ (" .. why .. ")"
    )
    ok(
      not shim_has(path),
      "shim contract: "
        .. path
        .. " is still absent from the shim — implemented since, "
        .. "so drop it from ALLOWED_ABSENT"
    )
  end

  -- ---------------------------------------------------------------------
  -- Methods. Every name `core/` calls on any receiver, classified.
  --
  -- `ts_shim` is verified against the file rather than trusted: those five
  -- are installed by `standalone/treesitter.lua` as `function index:<name>`,
  -- one exact shape, and `start`/`end_` are two of them because a release
  -- build failed on them.
  --
  -- `ts_binding` is a declaration, and the honest label for it is *read off
  -- the real binding once*, not *checked here* — enumerating it needs the
  -- `lua_tree_sitter` rock, which this spec does not require on purpose.
  -- ---------------------------------------------------------------------
  local METHOD_KIND = {
    -- Lua's own string metatable.
    byte = "lua",
    find = "lua",
    format = "lua",
    gmatch = "lua",
    gsub = "lua",
    lower = "lua",
    match = "lua",
    rep = "lua",
    sub = "lua",
    upper = "lua",
    -- Lua file handles, from `io.open`.
    close = "lua",
    lines = "lua",
    read = "lua",
    write = "lua",
    -- Installed by standalone/treesitter.lua onto the node metatable.
    start = "ts_shim",
    end_ = "ts_shim",
    range = "ts_shim",
    field = "ts_shim",
    iter_children = "ts_shim",
    -- The lua_tree_sitter binding's own node/tree/parser surface.
    child = "ts_binding",
    child_count = "ts_binding",
    named_child = "ts_binding",
    named_child_count = "ts_binding",
    parent = "ts_binding",
    prev_sibling = "ts_binding",
    type = "ts_binding",
    parse = "ts_binding",
    root = "ts_binding",
    -- Wrapped by standalone/treesitter.lua's own Query object.
    iter_captures = "ts_shim_query",
    iter_matches = "ts_shim_query",
  }

  local unclassified = {}
  for name, path in pairs(used_method) do
    if not METHOD_KIND[name] then
      unclassified[#unclassified + 1] = name .. "  (" .. path:gsub(".*/core/", "core/") .. ")"
    end
  end
  table.sort(unclassified)
  eq(
    table.concat(unclassified, "\n    "),
    "",
    "shim contract: every method core/ calls is classified — an unclassified name is the "
      .. "question that went unasked when node:start() shipped"
  )

  -- The five the shim installs, checked against the file that installs them.
  local fd = assert(io.open(root .. "/standalone/treesitter.lua", "rb"))
  local ts_src = fd:read("*a")
  fd:close()
  for name, kind in pairs(METHOD_KIND) do
    if kind == "ts_shim" then
      ok(
        ts_src:find("function index:" .. name .. "(", 1, true) ~= nil,
        "shim contract: standalone/treesitter.lua installs node:" .. name .. "()"
      )
    elseif kind == "ts_shim_query" then
      ok(
        ts_src:find("function Query:" .. name .. "(", 1, true) ~= nil,
        "shim contract: standalone/treesitter.lua wraps Query:" .. name .. "()"
      )
    end
  end

  -- And the classification must not rot: a name classified here that core/
  -- no longer calls is a claim about code that is gone.
  local stale = {}
  for name in pairs(METHOD_KIND) do
    if not used_method[name] then
      stale[#stale + 1] = name
    end
  end
  table.sort(stale)
  eq(
    table.concat(stale, ", "),
    "",
    "shim contract: every classified method is still called by core/"
  )
end
