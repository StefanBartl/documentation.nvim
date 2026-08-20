---@module 'documentation.editor.browse.highlight'
--- Code inside the browser's detail pane, highlighted rather than left as
--- literal backticks — the editor half of what `core/render/html.lua`'s
--- `prose()` does for the generated page.
---
--- **Two surfaces, and the measurement decides which one matters.** Before
--- writing this, the tree was counted rather than guessed at: **2 132 inline
--- `` `code` `` spans** are reachable in this pane (module summaries, node
--- bodies, function summaries and bodies), against **four** node bodies out
--- of a hundred and twenty-three carrying a ```` ``` ```` fence, and **zero**
--- `@example` blocks. So inline code is the feature and fenced blocks are the
--- rare extra — which is the opposite emphasis from the one the plan entry
--- was written with, and it is why the plugin below is the addition and not
--- the mechanism.
---
--- **Inline code needs no dependency at all.** It is a pattern match and an
--- extmark, so it works in a bare Neovim and is what a reader sees whether or
--- not anything optional is installed.
---
--- **`color_my_ascii.nvim` is a soft dependency for the fenced case**, the
--- same posture `pdfport.nvim` and `runtime-analysis.nvim` already have here:
--- probed through `core/soft_require`, and its absence changes nothing except
--- that four blocks in this repository stay plain. It fits *this* surface and
--- not the generated page for one concrete reason — its fence API is
--- buffer-based (`fences.list_blocks(bufnr, …)`), and this pane genuinely is
--- a Neovim buffer, where the page is a standalone artifact opened in a
--- browser and written by an engine that runs without Neovim at all.
---
--- Everything here is `pcall`-guarded and namespace-scoped: a highlighting
--- failure must never take down a pane whose job is to show text.

local M = {}

---One namespace for this module, cleared on every apply.
---
---Its own rather than shared: the detail pane is re-rendered on every `j`/`k`
---and clearing by namespace is what makes that cheap and total. A namespace
---shared with something else would either clear that thing's marks or leave
---this one's behind.
local NS = vim.api.nvim_create_namespace("documentation.browse.detail")

---What an inline span is drawn as.
---
---`@markup.raw` is the Treesitter-era name for exactly this — inline code in
---prose — so it inherits whatever the reader's colourscheme already decided
---for it, in every colourscheme, without this file picking a colour. The
---pane's own filetype has no parser, which is irrelevant: the group is a
---highlight name, not a capture, and linking is the colourscheme's job.
local SPAN_HL = "@markup.raw"

---And the backticks themselves, one step quieter.
---
---Kept visible rather than concealed. `conceallevel` would shift every column
---after the span, and this pane aligns several columns by hand (`kind    %s`,
---the symbol table); text that moves under a cursor is a worse trade than two
---dim characters.
local TICK_HL = "@punctuation.special"

---Every inline `` `code` `` span in one line, as 0-based byte ranges.
---
---**Deliberately not a Markdown parser.** The rule is the smallest one that
---is right for what this pane holds: a backtick, at least one character that
---is not a backtick or a newline, a backtick. That is what a doc comment
---writes. Nested or doubled fences (`` `` `x` `` ``) are not attempted — they
---do not appear in a summary line, and a half-right parser that sometimes
---swallows the wrong span is worse here than one that skips a shape nobody
---uses.
---
---Byte offsets, not character ones: `nvim_buf_set_extmark` counts bytes, and
---these lines contain `·` and `—` routinely.
---@param line string
---@return { s: integer, e: integer }[] 0-based, end-exclusive, over the whole span including both backticks.
function M.spans(line)
  local out = {}
  local from = 1
  while true do
    local s, e = line:find("`[^`\n]+`", from)
    if not s then
      break
    end
    out[#out + 1] = { s = s - 1, e = e }
    from = e + 1
  end
  return out
end

---Hand the buffer to `color_my_ascii.nvim`, if it is installed.
---
---**Only when there is something for it to do.** `list_blocks` is asked
---first, and the plugin is only invoked when it reports a block — which in
---this repository is four bodies out of a hundred and twenty-three. Calling
---`highlight_buffer` unconditionally would run a full-buffer pass on every
---`j`/`k` for the ninety-seven per cent of nodes that have no fence at all.
---
---Failure is silence: an optional plugin's surface is not
---stability-guaranteed, which is the same reason `mdview` and `pdfport` are
---reached this way.
---@param bufnr integer
---@return integer blocks How many fenced blocks it was given, `0` when it is absent or found none.
local function apply_fences(bufnr)
  local cma = require("documentation.core.soft_require").probe("color_my_ascii")
  if not cma or type(cma.fences) ~= "table" or type(cma.fences.list_blocks) ~= "function" then
    return 0
  end

  local ok, blocks = pcall(cma.fences.list_blocks, bufnr)
  if not ok or type(blocks) ~= "table" or #blocks == 0 then
    return 0
  end

  if type(cma.highlight_buffer) == "function" then
    pcall(cma.highlight_buffer, bufnr)
  end
  return #blocks
end

---Highlight the detail pane's current contents.
---
---Takes the lines it was just given rather than reading the buffer back:
---the caller has them in hand, and re-reading would be a second source of
---truth for the same strings.
---@param bufnr integer
---@param lines string[]
---@return integer spans How many inline spans were marked — returned for a spec to assert on rather than for a caller to use.
function M.apply(bufnr, lines)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return 0
  end
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)

  local marked = 0
  for row, line in ipairs(lines) do
    for _, span in ipairs(M.spans(line)) do
      -- Three marks per span rather than one: the ticks are dimmed and the
      -- text between them is the code. One mark over the whole span would
      -- colour the punctuation like the content, which is exactly the
      -- distinction the generated page draws with a `<code>` element.
      local ok = pcall(function()
        vim.api.nvim_buf_set_extmark(bufnr, NS, row - 1, span.s, {
          end_col = span.s + 1,
          hl_group = TICK_HL,
        })
        vim.api.nvim_buf_set_extmark(bufnr, NS, row - 1, span.s + 1, {
          end_col = span.e - 1,
          hl_group = SPAN_HL,
        })
        vim.api.nvim_buf_set_extmark(bufnr, NS, row - 1, span.e - 1, {
          end_col = span.e,
          hl_group = TICK_HL,
        })
      end)
      if ok then
        marked = marked + 1
      end
    end
  end

  apply_fences(bufnr)
  return marked
end

return M
