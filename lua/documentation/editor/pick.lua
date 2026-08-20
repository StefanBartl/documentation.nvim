---@module 'documentation.editor.pick'
--- `:DocMap pick` — fuzzy-find any module or function in the map and land on
--- its source line.
---
--- **The interaction `:DocBrowse` does not have.** The browser's `/` is a
--- fuzzy jump *inside* the browser: it moves the cursor to a row and leaves
--- you in the browser, which is right when you are exploring. This is the
--- other one — *I know the name, get me there* — and it ends in the file,
--- with the browser never opening. `IDEAS.md` §4.2 names them as two
--- interactions rather than one, and they stay two.
---
--- Cheap for the reason that entry gives: the IR is already a flat, ordered
--- list with locations attached, so this adds no extraction. It reads the
--- live handle the command layer already keeps per root.
---
--- ## Which picker
---
--- **`pickers.nvim` first, `lib.nvim`'s kit second**, and the order is about
--- what the list needs rather than about preference. This ecosystem's
--- `pickers.nvim` resolves one of telescope, fzf-lua or snacks and exposes
--- `engines.pick_item{ items, prompt, on_select }`, where an item carrying a
--- `file` gets that engine's own **native file previewer** — so a list of
--- several hundred entries arrives fuzzy-matchable and previewable with
--- nothing to maintain here. Measured on this repository: **913 entries**,
--- 907 of them with a file and 784 with a line. That is a real picker's job,
--- not a numbered prompt's.
---
--- Without it, `kit.select` with `respect_override = true`, which is what
--- `browse/init.lua` already does for its trail list: defer to whatever the
--- reader wired into `vim.ui.select` (telescope-ui-select, fzf-lua,
--- dressing), and fall back to the kit's own chooser when they wired
--- nothing. A published plugin that ignores a configured picker is being
--- opinionated about someone else's editor.
---
--- Neither is a hard dependency. `pickers.nvim` is probed through
--- `soft_require`, the same way `pdfport.nvim` and `runtime-analysis.nvim`
--- are; `lib.nvim` is already required by `core/`.
---
--- ## Why the entry round-trips as a table
---
--- `on_select` hands back the original item, and all three engines were read
--- rather than assumed on this point: telescope stores it as `entry.value`,
--- fzf-lua — a separate process that can only return text — keeps a
--- `by_line` map and returns the table anyway. So the location travels on
--- the item, and there is no text-to-entry lookup to keep in step. The one
--- shape that cannot round-trip is an item with no `file`, which fzf passes
--- through as a plain string; a namespace node is exactly that, so those
--- carry their location on a lookup table as well and the handler accepts
--- either. That lookup is keyed by the label, which is safe because the
--- labels are unique — measured, not assumed: 913 entries, 0 collisions.

local M = {}

local soft_require = require("documentation.core.soft_require")

---Every module and function in the map, as picker items.
---
---Modules read as their dotted name and functions as `module#M.fn` — the
---same two shapes `:DocBrowse`'s own fuzzy jump builds, deliberately, so a
---name typed in one place is the name typed in the other.
---
---A node with no `source` (a namespace directory) still becomes an entry:
---it has no line to land on, but it is a real place in the tree and
---answering "where is `documentation.core`" with nothing would be worse
---than answering with its directory.
---@param ir Documentation.IR
---@param root string Absolute repository root, forward-slashed.
---@return { text: string, file: string?, line: integer? }[]
function M.entries(ir, root)
  local out = {}
  for _, id in ipairs(ir.order or {}) do
    local node = ir.nodes[id]
    if node then
      local label = node.module or node.name
      out[#out + 1] = {
        text = label,
        file = node.source and (root .. "/" .. node.source) or nil,
        line = nil,
      }
      for _, fn in ipairs(node.functions or {}) do
        out[#out + 1] = {
          text = ("%s#%s"):format(label, fn.name),
          file = node.source and (root .. "/" .. node.source) or nil,
          line = fn.line,
        }
      end
    end
  end
  return out
end

---Open `file` and put the cursor on `line`.
---@param entry { file: string?, line: integer?, text: string }
---@param notify table
local function jump(entry, notify)
  if not entry or not entry.file then
    notify.warn(("%s has no file to open"):format(entry and entry.text or "that"))
    return
  end
  vim.cmd.edit(vim.fn.fnameescape(entry.file))
  if entry.line then
    pcall(vim.api.nvim_win_set_cursor, 0, { entry.line, 0 })
    vim.cmd("normal! zz")
  end
end

---`:DocMap pick`.
---@param ctx Documentation.Bindings.Ctx
function M.run(ctx)
  -- `handle.ir` is a function, not a field — it never triggers a scan, it
  -- hands back what the registry already has.
  local ir = ctx.handle and ctx.handle.ir()
  if not ir or not ir.order or #ir.order == 0 then
    ctx.notify.warn(
      "nothing scanned here yet — run :" .. (ctx.command_name or "DocMap") .. " first"
    )
    return
  end

  local root = ctx.cfg.root:gsub("\\", "/"):gsub("/+$", "")
  local items = M.entries(ir, root)
  if #items == 0 then
    ctx.notify.info("the map is empty — nothing to pick")
    return
  end

  -- fzf-lua returns a bare string for an item with no `file`; every other
  -- path returns the table. One lookup covers both without a branch at the
  -- call site.
  local by_text = {}
  for _, item in ipairs(items) do
    by_text[item.text] = item
  end
  local function chosen(selected)
    local entry = type(selected) == "table" and selected or by_text[tostring(selected)]
    jump(entry, ctx.notify)
  end

  local prompt = ("%s › module or function"):format(ctx.cfg.title or "map")

  -- **Ask whether there is anything to resolve before asking it to
  -- resolve.** `engines.load()` ends with
  -- `notify.error("No picker engine found. Install telescope.nvim, ...")`
  -- when none of the three is installed — correct for `:Pickers`, wrong
  -- here, where the answer is simply "use the kit instead". Without this
  -- probe a reader with `pickers.nvim` and no engine would get an error
  -- telling them to install telescope, immediately followed by a working
  -- picker. `available()` exists on all three engine modules; checking it
  -- is not duplicating the resolution, it is declining to start one.
  local function any_engine()
    for _, name in ipairs({ "telescope", "fzf", "snacks" }) do
      local mod = soft_require.probe("pickers.engines." .. name)
      if mod and type(mod.available) == "function" then
        local ok_probe, yes = pcall(mod.available)
        if ok_probe and yes then
          return true
        end
      end
    end
    return false
  end

  local pickers = soft_require.probe("pickers.engines")
  if pickers and type(pickers.load) == "function" and any_engine() then
    -- `load()` and not the module found above: which engine wins is
    -- `pickers.nvim`'s configuration to decide, not this plugin's.
    local engine = pickers.load()
    if engine and type(engine.pick_item) == "function" then
      engine.pick_item({ items = items, prompt = prompt, on_select = chosen })
      return
    end
  end

  -- No pickers.nvim, or it resolved no engine (none of telescope/fzf-lua/
  -- snacks installed). `kit.select` takes plain strings, so the location
  -- comes back through `by_text` — which is why that table exists
  -- unconditionally rather than only on the fzf path.
  local labels = {}
  for i, item in ipairs(items) do
    labels[i] = item.text
  end
  require("lib.nvim.ui.kit").select({
    title = " " .. prompt .. " ",
    items = labels,
    respect_override = true,
    on_select = chosen,
  })
end

return M
