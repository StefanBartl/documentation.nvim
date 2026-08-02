---@module 'documentation.core.plugins'
--- Plugin-manager spec entries — the one shape of file this map was blind to
--- until now.
---
--- A Neovim *config* (as opposed to a Neovim *plugin*) is mostly
--- `lua/plugins/*.lua` files whose entire content is
--- `return { { "author/repo", event = "…" }, … }` — no functions, no named
--- symbols, nothing `functions.lua` or `symbols.lua` has anything to say
--- about. Scanned today, those files show up as empty leaves, which is
--- backwards: they are usually the files someone most wants an overview of
--- ("what do I have installed, and what loads it").
---
--- Scoped to **lazy.nvim's spec shape** specifically, named as such rather
--- than pretending generality. packer.nvim and vim-plug specs look
--- different (`use {...}` calls, `Plug '...'` commands) and would need their
--- own extractor, not a bent version of this one — a real follow-up, not
--- attempted here.
---
--- ## What is recognized
---
--- The module's own top-level `return { … }` — a direct child of `chunk`,
--- matching real usage rather than a general "any array of tables"
--- heuristic that would also fire on ordinary config data. Each element is
--- either a bare string (`"author/repo"`, lazy.nvim's shorthand for "no
--- options") or a table whose positional `[1]` string is the repo.
---
--- **Not followed:** `local M = {...}; return M`. The indirection would need
--- tracing an identifier back to its assignment, which is exactly the kind
--- of guess this plugin's scanner declines to make elsewhere (see
--- `deps.lua`'s comment on `require(expr .. var)`). Verified against a real
--- Neovim config that every sampled `lua/plugins/*.lua` file uses the direct
--- form; a file using the indirect one simply contributes no plugins,
--- exactly as it contributes no functions to `functions.lua` today.
---
--- ## Two shapes that look identical and are not, found by running this
--- against a real config rather than only synthetic fixtures
---
--- `return { {...}, {...} }` (many plugins) and `return { "repo",
--- event = "…" }` (one plugin — a config split one file per plugin, a real
--- and common style) parse to the same node type. Read naively, the second
--- shape's `event`'s *value* looks like just another positional array
--- element, and a first pass here genuinely produced a spec whose `repo`
--- was the string `"VeryLazy"`. The distinguishing signal: an array of
--- specs never has a *named* field at the outer level; a single spec's own
--- trigger/metadata keys always do. `M.extract` checks for one before
--- deciding which shape it is looking at.
---
--- A bare-string array is not unique to plugin specs either — a plain list
--- of command names (`return { "NeotestRunNearest", … }`, found genuinely
--- documenting `:command` names in the same real config) is the identical
--- shape. `looks_like_repo` requires a `/` with no embedded whitespace,
--- which every sampled real spec has and no command name does — GitHub
--- shorthand is the one thing lazy.nvim's own contract requires of a bare
--- positional string, so this is not a guess about style, it is the format.
---
--- ## Pure
---
--- Runs on the tree `functions.lua` already parsed, the same way
--- `symbols.lua` does — no extra read, no extra parse.

local M = {}

---Whether a string is shaped like lazy.nvim's GitHub shorthand
---(`"owner/repo"`), the only form it accepts as a bare positional value.
---
---Exists because a bare-string array (`return { "a", "b", "c" }`) is not
---unique to plugin specs — a plain list of command names is the identical
---shape. Verified against a real config: `return {
---"NeotestRunNearest", "NeotestDebugNearest", … }` is a *usercommand* list,
---not plugins, and every one of those strings has no `/` while every real
---spec sampled from the same config (`"kdheepak/lazygit.nvim"`, …) does.
---No embedded whitespace either — a sentence fragment that happens to
---contain a slash (a file path in a description string) is not a repo.
---@param s string
---@return boolean
local function looks_like_repo(s)
  return s:find("/", 1, true) ~= nil and not s:find("%s")
end

---String content of a `(string (string_content))` node, or nil for anything
---else. Recognized value shapes are deliberately narrow: a computed string
---(`"a" .. "b"`) or an interpolated one is not something this can read
---without evaluating Lua, and guessing would be worse than skipping it.
---@param node TSNode?
---@param src string
---@return string?
local function string_value(node, src)
  if not node or node:type() ~= "string" then
    return nil
  end
  local content = node:named_child(0)
  if not content then
    return ""
  end
  return vim.treesitter.get_node_text(content, src)
end

---True/false for a literal `true`/`false` node, nil for anything else
---(including a function — `enabled = function() … end` is a real, common
---pattern this deliberately does not evaluate).
---@param node TSNode?
---@return boolean?
local function bool_value(node)
  if not node then
    return nil
  end
  local t = node:type()
  if t == "true" then
    return true
  end
  if t == "false" then
    return false
  end
  return nil
end

---A literal `number` node as a Lua number, or nil.
---@param node TSNode?
---@param src string
---@return integer?
local function number_value(node, src)
  if not node or node:type() ~= "number" then
    return nil
  end
  return tonumber(vim.treesitter.get_node_text(node, src))
end

---One field's string values, whichever of the two shapes lazy.nvim accepts:
---a single string (`cmd = "Foo"`) or an array of strings
---(`cmd = { "Foo", "Bar" }`). Always returns an array, even for the single
---form, since every caller wants "the trigger values" and not "which shape
---was written" — the two are not a meaningful distinction to a reader.
---@param node TSNode?
---@param src string
---@return string[]
local function string_or_array(node, src)
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
      local value = child:field("value")[1]
      local s = string_value(value, src)
      if s then
        out[#out + 1] = s
      end
    end
  end
  return out
end

---Dependency repo strings from a `dependencies = { … }` field. Each element
---is either a bare string or a nested spec table whose own `[1]` is the
---repo — the same two shapes a top-level entry can take, one level down.
---@param node TSNode?
---@param src string
---@return string[]
local function dependency_repos(node, src)
  if not node or node:type() ~= "table_constructor" then
    return {}
  end
  local out = {}
  for child in node:iter_children() do
    if child:type() == "field" then
      local value = child:field("value")[1]
      if value then
        local direct = string_value(value, src)
        if direct then
          out[#out + 1] = direct
        elseif value:type() == "table_constructor" then
          -- Only the first positional field of the nested table is the
          -- repo; named fields (its own `opts`, `event`, …) are not a
          -- dependency's business to report here.
          for nc in value:iter_children() do
            if nc:type() == "field" and not nc:field("name")[1] then
              local repo = string_value(nc:field("value")[1], src)
              if repo then
                out[#out + 1] = repo
                break
              end
            end
          end
        end
      end
    end
  end
  return out
end

---Recognized trigger/metadata keys on one spec table, keyed by the
---identifier text lazy.nvim reads. `name` maps to nothing here on purpose —
---it is read directly by `parse_entry`, since it doubles as the fallback
---repo when no positional string is given.
local FIELD_KIND = {
  event = "strings",
  cmd = "strings",
  ft = "strings",
  keys = "keys",
  dependencies = "deps",
  lazy = "bool",
  enabled = "bool",
  priority = "number",
  branch = "string",
  version = "string",
  dir = "string",
  url = "string",
  opts = "presence",
  config = "presence",
}

---`keys` is triggers *and* a mapping table — lazy.nvim accepts
---`keys = "<leader>x"`, `keys = { "<leader>x", "<leader>y" }`, or
---`keys = { { "<leader>x", "<cmd>...<cr>" }, … }`. Only the lhs is a
---trigger; the rhs is what the key does, not when the plugin loads, so it
---is not collected here.
---@param node TSNode?
---@param src string
---@return string[]
local function key_triggers(node, src)
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
      local value = child:field("value")[1]
      if value then
        local direct = string_value(value, src)
        if direct then
          out[#out + 1] = direct
        elseif value:type() == "table_constructor" then
          -- `{ "<leader>x", "<cmd>...<cr>" }`: the lhs is this table's own
          -- first positional field.
          for nc in value:iter_children() do
            if nc:type() == "field" and not nc:field("name")[1] then
              local lhs = string_value(nc:field("value")[1], src)
              if lhs then
                out[#out + 1] = lhs
              end
              break
            end
          end
        end
      end
    end
  end
  return out
end

---Parse one spec table (or bare string) into a `Documentation.PluginSpec`.
---`nil` for anything that is neither — a spec list can legitimately hold an
---expression this cannot read (a function call building a spec dynamically,
---for instance), and skipping it is correct: reporting a guess would be a
---false plugin.
---@param node TSNode
---@param src string
---@return Documentation.PluginSpec?
local function parse_entry(node, src)
  local srow = node:range()
  local bare = string_value(node, src)
  if bare and not looks_like_repo(bare) then
    return nil
  end
  if bare then
    return {
      repo = bare,
      line = srow + 1,
      event = {},
      cmd = {},
      ft = {},
      keys = {},
      dependencies = {},
      has_opts = false,
      has_config = false,
    }
  end
  if node:type() ~= "table_constructor" then
    return nil
  end

  local spec = {
    repo = nil,
    line = srow + 1,
    event = {},
    cmd = {},
    ft = {},
    keys = {},
    dependencies = {},
    has_opts = false,
    has_config = false,
  }
  local explicit_name

  for child in node:iter_children() do
    if child:type() == "field" then
      local name_node = child:field("name")[1]
      local value = child:field("value")[1]
      if not name_node then
        -- Positional: the repo shorthand, first one wins (lazy.nvim itself
        -- only reads the first positional string too). Not accepted unless
        -- it is actually shaped like one — see `looks_like_repo`.
        if not spec.repo then
          local candidate = string_value(value, src)
          if candidate and looks_like_repo(candidate) then
            spec.repo = candidate
          end
        end
      else
        local key = vim.treesitter.get_node_text(name_node, src)
        local kind = FIELD_KIND[key]
        if key == "name" then
          explicit_name = string_value(value, src)
        elseif kind == "strings" then
          spec[key] = string_or_array(value, src)
        elseif kind == "keys" then
          spec.keys = key_triggers(value, src)
        elseif kind == "deps" then
          spec.dependencies = dependency_repos(value, src)
        elseif kind == "bool" then
          spec[key] = bool_value(value)
        elseif kind == "number" then
          spec[key] = number_value(value, src)
        elseif kind == "string" then
          spec[key] = string_value(value, src)
        elseif kind == "presence" then
          spec["has_" .. key] = true
        end
      end
    end
  end

  -- `name`/`dir`/`url` are the recognized fallbacks, in that order, for a
  -- spec with no positional repo string — `dir`-only (a local checkout) and
  -- `url`-only (a non-GitHub remote) specs are real and have no shorthand.
  spec.repo = spec.repo or explicit_name or spec.dir or spec.url

  return spec
end

---Extract every recognized spec from this file's own top-level `return`.
---@param root TSNode Root of the parsed Lua tree for this source.
---@param src string
---@return Documentation.PluginSpec[]
function M.extract(root, src)
  local out = {}
  for node in root:iter_children() do
    if node:type() == "return_statement" then
      -- `expression_list` sits at a fixed position (`return`, then it), not
      -- behind a named field — verified against a real parse, where
      -- `:field("expression_list")` comes back empty.
      local exprs = node:child(1)
      local outer
      if exprs then
        for c in exprs:iter_children() do
          if c:type() == "table_constructor" then
            outer = c
            break
          end
        end
      end
      if outer then
        -- lazy.nvim's own return shape is genuinely ambiguous without this
        -- check: `return { {...}, {...} }` (many plugins) and
        -- `return { "repo", event = "…" }` (one plugin, config split one
        -- file per plugin — the shape this config's own `plugins/nvchad.lua`
        -- uses) parse to the same node type, `table_constructor`. The real
        -- distinguishing signal is whether the table has any NAMED field —
        -- an array never does, a single spec's own trigger/metadata keys
        -- always do. Verified against both real shapes: treating a
        -- single-spec table's `event = "VeryLazy"` as a positional array
        -- element produced a spec whose repo was the string "VeryLazy".
        local one_spec = false
        for child in outer:iter_children() do
          if child:type() == "field" and child:field("name")[1] then
            one_spec = true
            break
          end
        end

        if one_spec then
          local entry = parse_entry(outer, src)
          if entry and entry.repo then
            out[#out + 1] = entry
          end
        else
          for child in outer:iter_children() do
            if child:type() == "field" then
              local value = child:field("value")[1]
              if value then
                local entry = parse_entry(value, src)
                if entry and entry.repo then
                  out[#out + 1] = entry
                end
              end
            end
          end
        end
      end
    end
  end
  return out
end

return M
