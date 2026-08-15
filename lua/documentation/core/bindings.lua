---@module 'documentation.core.bindings'
--- Keymaps, user commands and autocmds — the three shapes of a Neovim
--- *config* that `core/plugins.lua` did not already cover.
---
--- A Neovim config is, roughly, four things: plugin specs, keymaps,
--- autocmds and options. `plugins.lua` handles the first and says why
--- ("those files show up as empty leaves, which is backwards"). This module
--- handles the next three, on the same terms and for the same reason: a
--- `lua/bindings/mappings/*.lua` full of `map("n", "<C-a>", …)` contributes
--- no functions, no symbols, and therefore nothing to a map of the tree —
--- even though "what do I have bound, and where" is one of the questions a
--- config is most often opened to answer.
---
--- Options (`vim.opt.x = …`) are deliberately NOT here: they are
--- assignments, not calls, and a flat list of option names is a much weaker
--- answer than `:set` already gives interactively. Left out rather than
--- added because the shape happened to be adjacent.
---
--- ## Two tiers, and why the second one is opt-in
---
--- **Built-ins** (below) are recognized unconditionally. `vim.keymap.set`
--- means exactly one thing in every Neovim config that has ever existed;
--- there is nothing to guess and no way to be wrong.
---
--- **Wrappers are opt-in**, declared by the caller as
--- `opts.bindings.wrappers`. That is not timidity, it is the measurement:
--- in the real config this was built against, keymaps were 233×
--- `map("n", …)` versus 4× `vim.keymap.set`, and user commands 72×
--- `usercmd.create` versus 12× `vim.api.nvim_create_user_command`. A
--- built-ins-only extractor would have found 1.7% of the keymaps — so
--- wrapper support is the primary case here, not a refinement of it.
---
--- But a *bare* `map(...)` is genuinely ambiguous in a way `vim.keymap.set`
--- never is: `map` is also the most natural name for a list-mapping helper,
--- and guessing wrong means silently reporting a `vim.tbl_map` call as a
--- keymap binding. Since the caller always knows its own helper's name and
--- the map cannot know it, the caller declares it:
---
---   opts.bindings = {
---     wrappers = {
---       ["map"] = "keymap",              -- map(mode, lhs, rhs, opts)
---       ["usercmd.create"] = "usercmd",  -- create(name, cmd, opts)
---       ["autocmd.create"] = "autocmd",  -- create(event, opts)
---     },
---   }
---
--- The value names an ARGUMENT LAYOUT, not a free-form parser — a wrapper
--- is only declarable when its signature already matches one of the
--- built-in shapes. That is the common case by construction (a thin wrapper
--- around `vim.keymap.set` keeps its argument order; the config measured
--- above does exactly this via `vim.g.__map_helper`), and a wrapper that
--- reorders its arguments is honestly out of scope rather than quietly
--- mis-parsed.
---
--- **Not followed:** `local map = require(...)` / `vim.g.__map_helper` is
--- never traced back to what it points at. The callee text as written is
--- what gets matched — `usercmd.create` matches the key `"usercmd.create"`
--- whatever `usercmd` happens to be bound to. Same line `core/plugins.lua`
--- draws for `local M = {...}; return M`, and `core/deps.lua` for
--- `require(expr .. var)`: this scanner does not resolve identifiers.
---
--- ## What is read out of a call, and what is not
---
--- Position and `desc` only. A keymap's *right-hand side* is deliberately
--- not captured: it is as often a multi-line function literal as a string,
--- and a map of "what is bound where" does not become more useful by
--- inlining an anonymous function's body into a table cell. `desc` — which
--- every binding in a maintained config sets anyway — is the human answer
--- to the same question, and `line` points at the real thing.
---
--- ## Pure
---
--- Runs on the tree `functions.lua` already parsed, the same way
--- `symbols.lua` and `plugins.lua` do — no extra read, no extra parse.

local M = {}

---Argument layouts, keyed by the name a caller writes in
---`opts.bindings.wrappers`. `arg` indices are 1-based over the call's own
---argument list.
---
---`kind` is what the binding IS; the layout name is how its call is SHAPED.
---They differ only where a buffer-local variant shifts every index by one,
---which is exactly why both exist.
---@type table<string, { kind: string, mode?: integer, lhs?: integer, name?: integer, event?: integer, opts?: integer, buffer?: boolean }>
local LAYOUTS = {
  -- vim.keymap.set(mode, lhs, rhs, opts)
  keymap = { kind = "keymap", mode = 1, lhs = 2, opts = 4 },
  -- vim.api.nvim_buf_set_keymap(buf, mode, lhs, rhs, opts)
  keymap_buf = { kind = "keymap", mode = 2, lhs = 3, opts = 5, buffer = true },
  -- vim.api.nvim_create_user_command(name, cmd, opts)
  usercmd = { kind = "usercmd", name = 1, opts = 3 },
  -- vim.api.nvim_buf_create_user_command(buf, name, cmd, opts)
  usercmd_buf = { kind = "usercmd", name = 2, opts = 4, buffer = true },
  -- vim.api.nvim_create_autocmd(event, opts)
  autocmd = { kind = "autocmd", event = 1, opts = 2 },
}

---Callees recognized with no configuration at all. Every one of these is an
---official Neovim API whose meaning is fixed; none can be anything else.
---@type table<string, string>
local BUILTINS = {
  ["vim.keymap.set"] = "keymap",
  ["vim.api.nvim_set_keymap"] = "keymap",
  ["vim.api.nvim_buf_set_keymap"] = "keymap_buf",
  ["vim.api.nvim_create_user_command"] = "usercmd",
  ["vim.api.nvim_buf_create_user_command"] = "usercmd_buf",
  ["vim.api.nvim_create_autocmd"] = "autocmd",
}

---Caller-declared wrappers for this scan, `callee -> layout name`.
---
---Module-level rather than a `scan_file` parameter for the reason
---`core/scan.lua` already spells out for `snippet.MAX_LINES`: that
---signature is shared by five language backends, and threading one policy
---value through all of them buys nothing when it only has to be current
---before the walk starts. `core/scan.lua` resets this on every `M.scan`,
---so one repo's wrappers can never leak into a later scan of a different
---repo in the same process.
---@type table<string, string>
M.WRAPPERS = {}

---The empty default a scan with no `opts.bindings` resets to — a real
---value to reset *to*, so "no wrappers configured" is expressible and is
---not merely "whatever the last scan happened to set".
M.DEFAULT_WRAPPERS = {}

---@return table<string, string>
function M.recognized()
  local out = {}
  for callee, layout in pairs(BUILTINS) do
    out[callee] = layout
  end
  -- Caller-declared entries win: a config that wraps `vim.keymap.set` under
  -- its own name and ALSO declares that name gets one binding per call,
  -- and a deliberate re-declaration of a built-in is the caller's call to
  -- make, not something to silently ignore.
  for callee, layout in pairs(M.WRAPPERS or {}) do
    if LAYOUTS[layout] then
      out[callee] = layout
    end
  end
  return out
end

---Dotted source text of whatever is being called, exactly as written.
---Never resolved (see the module header) — `usercmd.create` is the string
---`"usercmd.create"`, whatever `usercmd` is bound to.
---@param call TSNode
---@param src string
---@return string?
local function callee_text(call, src)
  local fn = call:field("name")[1]
  if not fn then
    return nil
  end
  local ok, text = pcall(vim.treesitter.get_node_text, fn, src)
  if not ok or type(text) ~= "string" then
    return nil
  end
  -- A call split across lines (`vim.api\n  .nvim_create_autocmd`) is still
  -- one dotted path; normalizing whitespace out keeps it matchable rather
  -- than mysteriously invisible.
  return (text:gsub("%s+", ""))
end

---Positional arguments of a call, in order. Named/table arguments are
---included as nodes too — position is what the layouts index by.
---@param call TSNode
---@return TSNode[]
local function arg_nodes(call)
  local args = call:field("arguments")[1]
  if not args then
    return {}
  end
  local out = {}
  for child in args:iter_children() do
    local t = child:type()
    -- Skip the punctuation the grammar exposes as anonymous children.
    if t ~= "(" and t ~= ")" and t ~= "," then
      out[#out + 1] = child
    end
  end
  return out
end

---A string literal's own value, or nil for anything that is not one.
---Deliberately literal-only: a `lhs` built at runtime (`prefix .. "x"`) has
---no single answer at scan time, and inventing one would be a guess.
---@param node TSNode?
---@param src string
---@return string?
local function string_value(node, src)
  if not node or node:type() ~= "string" then
    return nil
  end
  local ok, text = pcall(vim.treesitter.get_node_text, node, src)
  if not ok or type(text) ~= "string" then
    return nil
  end
  -- Strip one layer of matching quotes; long-bracket strings are left as
  -- written, being vanishingly rare here and never wrong to show verbatim.
  local inner = text:match("^['\"](.*)['\"]$")
  return inner or text
end

---One string, or a `{ "n", "v" }` list of them, as a list either way —
---`vim.keymap.set` accepts both for `mode`, and `nvim_create_autocmd` for
---`event`, so both call sites need the same normalization.
---@param node TSNode?
---@param src string
---@return string[]
local function string_list(node, src)
  if not node then
    return {}
  end
  local single = string_value(node, src)
  if single then
    return { single }
  end
  if node:type() ~= "table_constructor" then
    return {}
  end
  local out = {}
  for child in node:iter_children() do
    if child:type() == "field" then
      -- A positional entry has no `name` field; a named one is not a mode.
      if not child:field("name")[1] then
        local v = string_value(child:field("value")[1] or child:child(0), src)
        if v then
          out[#out + 1] = v
        end
      end
    end
  end
  return out
end

---A named string field out of an options table (`{ desc = "…" }`).
---@param node TSNode?
---@param key string
---@param src string
---@return string?
local function table_string_field(node, key, src)
  if not node or node:type() ~= "table_constructor" then
    return nil
  end
  for child in node:iter_children() do
    if child:type() == "field" then
      local name = child:field("name")[1]
      if name then
        local ok, name_text = pcall(vim.treesitter.get_node_text, name, src)
        if ok and name_text == key then
          return string_value(child:field("value")[1], src)
        end
      end
    end
  end
  return nil
end

---Depth-first over every node, since a binding call can sit anywhere — a
---module's top level, inside a `setup()`, inside an autocmd callback.
---`plugins.lua` walks only the top-level `return`, which is right for a
---spec file and wrong here.
---@param node TSNode
---@param visit fun(n: TSNode)
local function walk(node, visit)
  visit(node)
  for child in node:iter_children() do
    walk(child, visit)
  end
end

---Extract every recognized binding call in this file.
---@param root TSNode Root of the parsed Lua tree for this source.
---@param src string
---@return Documentation.BindingSpec[]
function M.extract(root, src)
  local recognized = M.recognized()
  local out = {}

  walk(root, function(node)
    if node:type() ~= "function_call" then
      return
    end
    local callee = callee_text(node, src)
    if not callee then
      return
    end
    local layout = LAYOUTS[recognized[callee] or ""]
    if not layout then
      return
    end

    local args = arg_nodes(node)
    local opts_node = layout.opts and args[layout.opts] or nil

    ---@type Documentation.BindingSpec
    local spec = {
      kind = layout.kind,
      callee = callee,
      buffer = layout.buffer == true,
      modes = {},
      events = {},
      line = node:start() + 1,
    }

    if layout.mode then
      spec.modes = string_list(args[layout.mode], src)
    end
    if layout.lhs then
      spec.lhs = string_value(args[layout.lhs], src)
    end
    if layout.name then
      spec.name = string_value(args[layout.name], src)
    end
    if layout.event then
      spec.events = string_list(args[layout.event], src)
    end
    spec.desc = table_string_field(opts_node, "desc", src)
    if opts_node and table_string_field(opts_node, "buffer", src) ~= nil then
      spec.buffer = true
    end

    -- A call whose identifying argument is not a literal (`map(mode, key,
    -- …)` with both from variables) is recorded with what IS known rather
    -- than dropped: the call site is real, and `line` still points at it.
    -- Only a call that yielded nothing identifying at all is skipped, since
    -- a row with no lhs, no name and no event says nothing.
    if spec.lhs or spec.name or #spec.events > 0 then
      out[#out + 1] = spec
    end
  end)

  return out
end

return M
