---@module 'documentation.bindings.usrcmds.impact'
--- `:DocMap impact [ref]` — where the changed *lines* radiate to.
---
--- `diff` answers what changed about the tree's shape; this answers which
--- functions the changed lines touch and who calls those.
--- `documentation.core.history` does all of it purely; this module is the git
--- and quickfix half.
---
--- Semantics are deliberately the same as `diff`: everything between `ref` and
--- the working tree, `HEAD` by default. So bare `:DocMap impact` is "what does
--- my uncommitted work affect" — the pre-commit question — and on a clean tree
--- `impact HEAD~1` is exactly "what did the last commit affect". One rule, and
--- it puts the *live* IR on the `+` side, which matters: the live IR always
--- carries `line_end`, so the new side is always attributed exactly and only
--- the historical side can degrade.
---
--- The out_dir exclusion is not optional. Measured on one commit here, the full
--- diff is 4.8 MB of which all but 27 KB is the regenerated map — without it
--- this analyses mostly its own output.

local M = {}

---@param ctx Documentation.Bindings.Ctx
---@param arg string Everything after "impact" — a revision, or "" for HEAD.
function M.run(ctx, arg)
  local ref = vim.trim(arg or "")
  if ref == "" then
    ref = "HEAD"
  end
  local out_dir = ctx.cfg.out_dir or "docs/map"

  local dproc = vim
    .system({
      "git",
      "diff",
      "--unified=0",
      ref,
      "--",
      ".",
      (":(exclude)%s"):format(out_dir),
    }, { cwd = ctx.cfg.root, text = true })
    :wait()
  if dproc.code ~= 0 then
    ctx.notify.warn(("Cannot diff against %s: %s"):format(ref, vim.trim(dproc.stderr or "")))
    return
  end
  if vim.trim(dproc.stdout or "") == "" then
    ctx.notify.info(("Nothing changed since %s (outside %s)."):format(ref, out_dir))
    return
  end

  -- The parent artifact is a convenience, not a requirement: without it the
  -- `-` side simply contributes nothing, which is the honest result for a
  -- revision that predates the map. So a failure here is a notice, not an
  -- abort.
  local before
  local rel = out_dir .. "/module_map.json"
  local sproc = vim
    .system({ "git", "show", ("%s:%s"):format(ref, rel) }, { cwd = ctx.cfg.root, text = true })
    :wait()
  if sproc.code == 0 then
    local ok_decode, doc = pcall(vim.json.decode, sproc.stdout, {
      luanil = { object = true, array = true },
    })
    if ok_decode and type(doc) == "table" and type(doc.nodes) == "table" then
      before = require("documentation.editor.browse.source").rehydrate(doc)
    end
  end

  local ir = ctx.handle.ir()
  local history = require("documentation.core.history")
  local result = history.analyze(dproc.stdout, ir, before)

  vim.fn.setqflist({}, " ", {
    title = ("docmap impact: %s → working tree"):format(ref),
    items = history.quickfix_items(result, ir, ctx.cfg.root),
  })

  if #result.touched == 0 then
    ctx.notify.info(
      ("%d file(s) changed since %s, but no scanned function was touched."):format(
        #result.files,
        ref
      )
    )
  else
    ctx.notify.info(
      ("%d function(s) touched · %d caller module(s) · %d impacted transitively%s"):format(
        #result.touched,
        #result.calling_modules,
        #result.impacted_modules,
        -- Said out loud rather than implied: an approximated span means the
        -- attribution over-reaches into the gaps between functions, and a
        -- reader deserves to know which kind of answer this is.
        result.approximate and "  (spans approximated — pre-line_end artifact)" or ""
      )
    )
  end
  vim.cmd("copen")
end

return M
