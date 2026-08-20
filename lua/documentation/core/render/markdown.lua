---@module 'documentation.core.render.markdown'
--- Renders the docmap IR as a Markdown overview: a Mermaid namespace graph,
--- a nested module index with README links, and the drift report.
---
--- This is the format that renders on the code host itself, so it is what a
--- reader who never opens the HTML page still sees.

local M = {}

local mermaid = require("documentation.core.render.mermaid")

---Escape the characters that break a Markdown table cell.
---@param s string?
---@return string
local function cell(s)
  if not s or s == "" then
    return ""
  end
  return (s:gsub("|", "\\|"):gsub("\n", " "))
end

---Rewrite a summary's relative markdown links so they still resolve from
---the artifact directory.
---
---**Every relative link in a summary was broken, not some of them.** A
---module header writes `[DEFAULTS.lua](DEFAULTS.lua)`, which is correct
---where it was written — beside the file it names. `overview.md` copies
---that sentence into `docs/map/`, where the same text points at
---`docs/map/DEFAULTS.lua`, which does not exist. Measured across three
---repositories before this was written: 4 of 4 such links here, 1 of 1 in
---runtime-analysis.nvim, 0 of 0 in lib.nvim — a 100% failure rate for the
---shape, not a stray.
---
---**`dead-readme-link` is right not to catch it**, which was worth
---establishing before touching either. `docs.corpus` excludes `out_dir`
---explicitly, so the check never reads generated output — and it should
---not: you fix a generator, you do not lint its output. The defect was
---found by the standalone gate reading the artifact as a plain file.
---
---Absolute URLs and bare anchors are left exactly as written: neither has
---a directory to be relative to.
---@param text string
---@param base_dir string Repo-relative directory of the file the text came from.
---@param out_dir string
---@param rel fun(out_dir: string, target: string): string
---@return string
local function rebase_links(text, base_dir, out_dir, rel)
  if not text or text == "" or not base_dir then
    return text
  end
  return (
    text:gsub("(%]%()([^)]+)(%))", function(open, target, close)
      if target:match("^%a[%w+.-]*://") or target:sub(1, 1) == "#" then
        return open .. target .. close
      end
      -- Split a trailing anchor off before resolving: `../x.md#section` is a
      -- path plus a fragment, and the fragment must survive untouched.
      local path, anchor = target:match("^([^#]*)(#.*)$")
      path = path or target
      anchor = anchor or ""
      if path == "" then
        return open .. target .. close
      end
      local resolved = require("documentation.core.docs").resolve_link(base_dir, path)
      return open .. rel(out_dir, resolved) .. anchor .. close
    end)
  )
end

---Path from the artifact back to a repo-relative target.
---@param out_dir string
---@param target string
---@return string
local function rel(out_dir, target)
  local depth = select(2, out_dir:gsub("[^/]+", "")) or 0
  return string.rep("../", depth) .. target
end

---@param ir Documentation.IR
---@param findings Documentation.Finding[]
---@param opts Documentation.Opts
---@return string
function M.render(ir, findings, opts)
  local out_dir = opts.out_dir or "docs/map"
  local o = {}
  local function put(s)
    o[#o + 1] = s
  end

  local c = ir.meta.counts
  put("# " .. ir.meta.title .. " — module map\n")
  put(
    "> **Generated** by `documentation`. Do not edit by hand — run `:DocMap`\n"
      .. "> (or `nvim --headless -l scripts/gen_map.lua`) to regenerate.\n"
  )
  put(
    ("**%d modules** · %d namespaces · %d helper files\n"):format(
      c.module or 0,
      c.namespace or 0,
      c.file or 0
    )
  )
  put(
    "The [interactive map](index.html) has filtering, full descriptions and\n"
      .. "source links; this page is the version the code host renders directly.\n"
  )

  put("\n## Namespaces\n")
  put(mermaid.render(ir, findings, { max_depth = 2 }))

  -- Empty when nothing in the tree requires anything else in it, which is a
  -- real state for a small plugin — better no section than an empty diagram.
  local deps_graph = mermaid.render_deps(ir, { depth = 2 })
  if deps_graph ~= "" then
    put("\n\n## Dependencies\n")
    put(
      "Which parts of the tree require which, rolled up to the second level.\n"
        .. "The [interactive map](index.html)'s **Deps** view has this per module,\n"
        .. "in both directions, with load-time and lazy requires told apart.\n"
    )
    put(deps_graph)
  end

  put("\n\n## Modules\n")
  put("| Module | Description | Fns | Docs |")
  put("|---|---|---|---|")

  for _, id in ipairs(ir.order) do
    local n = ir.nodes[id]
    if n.kind ~= "file" and id ~= ir.root then
      local indent = string.rep("&nbsp;&nbsp;", math.max(0, n.depth - 1))
      local name = n.module and ("`" .. n.module .. "`") or ("`" .. n.name .. "`")
      local links = {}
      if n.readme then
        links[#links + 1] = "[README](" .. rel(out_dir, n.readme) .. ")"
      end
      if n.source then
        links[#links + 1] = "[src](" .. rel(out_dir, n.source) .. ")"
      end
      -- Full per-function detail (signatures, params, examples) is reserved
      -- for the interactive HTML — a count here is enough to tell a reader
      -- "there's documented API surface" without ~250 rows turning into
      -- thousands once every function's signature is spelled out.
      local fn_count = #(n.functions or {})
      -- The directory the summary was *written* in: a file's own, or the
      -- namespace directory itself when there is no file. That is the base
      -- every relative link in it was written against.
      local base_dir = (n.source and n.source:match("^(.*)/[^/]+$")) or n.path
      put(
        ("| %s%s | %s | %s | %s |"):format(
          indent,
          name,
          cell(rebase_links(n.summary, base_dir, out_dir, rel)),
          fn_count > 0 and tostring(fn_count) or "",
          table.concat(links, " · ")
        )
      )
    end
  end

  local t = { error = 0, warn = 0, info = 0 }
  for _, f in ipairs(findings) do
    t[f.severity] = (t[f.severity] or 0) + 1
  end

  put("\n## Drift\n")
  put(("%d errors · %d warnings · %d info\n"):format(t.error, t.warn, t.info))

  if t.error + t.warn == 0 then
    put("No errors or warnings.\n")
  else
    put("| Severity | Check | Message |")
    put("|---|---|---|")
    for _, f in ipairs(findings) do
      if f.severity ~= "info" then
        put(
          ("| %s | `%s` | %s |"):format(
            f.severity,
            f.check,
            cell(require("documentation.core.findings").format(f))
          )
        )
      end
    end
  end

  if t.info > 0 then
    put("\n<details>\n<summary>" .. t.info .. " informational findings</summary>\n")
    put("\n| Check | Message |")
    put("|---|---|")
    for _, f in ipairs(findings) do
      if f.severity == "info" then
        put(
          ("| `%s` | %s |"):format(f.check, cell(require("documentation.core.findings").format(f)))
        )
      end
    end
    put("\n</details>")
  end

  return table.concat(o, "\n") .. "\n"
end

return setmetatable(M, {
  __call = function(_, ...)
    return M.render(...)
  end,
})
