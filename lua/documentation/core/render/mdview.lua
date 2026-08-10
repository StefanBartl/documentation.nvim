---@module 'documentation.core.render.mdview'
--- Renders the docmap IR as Markdown shaped for mdview.nvim's live preview
--- (`opts.mdview`, see `editor/registry.lua#ensure_mdview`) — Tier A of the
--- roadmap's "mdview.nvim integration" item. A close relative of
--- `render/markdown.lua`'s `overview.md`, not a copy: this output is pushed
--- straight into a running mdview session (comrak render + ammonia sanitize,
--- native to that plugin), which imposes real constraints `overview.md`
--- never had to satisfy on GitHub.
---
--- Two constraints, checked against mdview's own source rather than assumed
--- (2026-08-10, `native/wasm-render/src/lib.rs`'s `sanitizer()` and the
--- vendored `ammonia` 4.1.3 crate source under `~/.cargo/registry/src`):
---
--- 1. **No Mermaid.** mdview's client (`src/client/`) has no Mermaid
---    dependency at all — a ```mermaid fenced block survives ammonia (`pre`/
---    `code` are default-allowed tags) but renders as inert text, not a
---    diagram. `render/markdown.lua`'s two Mermaid sections are dropped
---    entirely rather than shipped broken; a short note points at the
---    interactive HTML map instead (Tier B — a real box+connector diagram
---    inside mdview's own tab — needs a `kind` field on mdview's own WS
---    protocol that does not exist yet; out of scope here, see the roadmap
---    decision record).
--- 2. **No custom classes or `style` attributes.** ammonia 4.1.3's *default*
---    `Builder` allows `id`-free, `style`-free markup — `generic_attributes`
---    is only `{"lang", "title"}` — and mdview's own `sanitizer()` adds just
---    three things beyond that default: `<input>` (task-list checkboxes),
---    and a `class` attribute scoped to `<code>` only (for
---    `language-xxx` syntax-highlight hints). `<details>`/`<summary>` and
---    GFM tables need nothing extra — both are already in ammonia's default
---    tag set. So this renderer sticks to plain tables, headings, lists,
---    inline code and `<details>` — the same subset `render/markdown.lua`
---    already uses apart from Mermaid — and never emits a `class` or `id`
---    attribute of its own.

local M = {}

---Escape the characters that break a Markdown table cell.
---@param s string?
---@return string
local function cell(s)
  if not s or s == "" then
    return ""
  end
  return (s:gsub("|", "\\|"):gsub("\n", " "))
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
  put("# " .. ir.meta.title .. " — module map (live)\n")
  put(
    "> **Live preview** via mdview.nvim (`opts.mdview`) — this reflects the\n"
      .. "> in-memory IR of a running `install()` handle, not necessarily what\n"
      .. "> was last written to `overview.md` on disk.\n"
  )
  put(
    ("**%d modules** · %d namespaces · %d helper files\n"):format(
      c.module or 0,
      c.namespace or 0,
      c.file or 0
    )
  )
  put(
    "Diagrams (namespace/dependency graphs) are not shown here — mdview's\n"
      .. "preview has no Mermaid renderer. The [interactive map](index.html)\n"
      .. "has them, plus filtering, full descriptions and source links.\n"
  )

  put("\n## Modules\n")
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
      local fn_count = #(n.functions or {})
      put(
        ("| %s%s | %s | %s | %s |"):format(
          indent,
          name,
          cell(n.summary),
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
        put(("| %s | `%s` | %s |"):format(f.severity, f.check, cell(f.message)))
      end
    end
  end

  if t.info > 0 then
    put("\n<details>\n<summary>" .. t.info .. " informational findings</summary>\n")
    put("\n| Check | Message |")
    put("|---|---|")
    for _, f in ipairs(findings) do
      if f.severity == "info" then
        put(("| `%s` | %s |"):format(f.check, cell(f.message)))
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
