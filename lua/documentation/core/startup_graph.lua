---@module 'documentation.core.startup_graph'
--- The startup flamegraph `runtime-analysis.nvim` writes, baked into the
--- generated page.
---
--- **Why this one is embedded when Telemetry and Loaded are fetched.** Those
--- two answer questions whose answers keep changing — call counts grow, a
--- newer snapshot supersedes an older one — so baking either into a committed
--- artifact would ship a number that is wrong by the time anyone reads it.
--- They need `:DocMap serve`, and that is correct for them. Startup
--- attribution is the opposite: it exists once per session, is over before
--- the UI is up, and does not accumulate. Baking it in is not a compromise
--- here, it is the only form in which it reaches the person who opens the
--- page from `gh-pages` — and *that* person is the one who asks why the thing
--- starts slowly.
---
--- **The file, never the live module.** `runtime-analysis.telemetry.startup`
--- holds its data in process state, so reading it here would embed whatever
--- the `:DocMap`-running session happened to record — usually nothing, since
--- that session is rarely the one that measured. Worse, it would make the
--- artifact differ between two runs over identical source, and between the
--- Neovim build and the Neovim-free one. A file that somebody deliberately
--- wrote (`:RATelemetry flamegraph`) is evidence in the same sense a
--- `loaded` snapshot is, and `core/loaded_diff.lua` chose it for the same
--- reason.
---
--- **And it is checked, not trusted.** The path is configurable, so "we
--- wrote it ourselves" stops being true the moment someone points
--- `opts.startup_flamegraph` at a downloaded CI artifact. The content is
--- interpolated into the emitted document, which is exactly the situation
--- `render/html.lua` already validates `opts.theme` for. `M.is_safe` is a
--- narrow structural check rather than a sanitizer: it does not try to clean
--- a hostile file, it refuses one.

local M = {}

--- The flamegraph's path: the configured one, else the one
--- `runtime-analysis.nvim` writes by default.
---@param opts Documentation.Opts
---@return string|nil path  nil when nothing can name a path at all
function M.path(opts)
  local configured = opts and opts.startup_flamegraph
  if type(configured) == "string" and configured ~= "" then
    return configured
  end

  local report_file =
    require("documentation.core.soft_require").probe("runtime-analysis.telemetry.report_file")
  if not report_file or type(report_file.flamegraph_path) ~= "function" then
    return nil
  end

  local ok, path = pcall(report_file.flamegraph_path)
  if not ok or type(path) ~= "string" then
    return nil
  end
  return path
end

--- Whether `svg` is the shape this page is willing to inline.
---
--- Refusal, not sanitisation. Cleaning a hostile SVG means keeping a list of
--- everything that can execute in one, which is a list that grows without
--- anyone here noticing; refusing anything that carries a script, an event
--- handler or a `javascript:` target costs four patterns and fails safe. A
--- flamegraph written by `renderers/flamegraph.lua` has none of them, so a
--- file that does is either not that file or has been altered, and in both
--- cases "not shown" is the right outcome.
---
--- Deliberately not a parser: an SVG is XML, this is a substring check, and a
--- sufficiently determined encoding could slip past it. That is acceptable
--- for what this guards — a local file the reader's own tooling wrote — and
--- it would not be if this ever accepted a remote source, which is why it
--- does not.
---@param svg string
---@return boolean ok
---@return string|nil reason
function M.is_safe(svg)
  if type(svg) ~= "string" or svg == "" then
    return false, "empty"
  end
  if not svg:find("<svg", 1, true) then
    return false, "not an SVG"
  end

  local lowered = svg:lower()
  if lowered:find("<script", 1, true) then
    return false, "contains a script element"
  end
  if lowered:find("javascript:", 1, true) then
    return false, "contains a javascript: target"
  end
  if lowered:find("<foreignobject", 1, true) then
    -- `foreignObject` embeds arbitrary HTML inside the SVG, which puts every
    -- question this check just answered back on the table one level down.
    return false, "contains a foreignObject"
  end
  -- Any `on…=` attribute. Matched on the attribute shape rather than a list
  -- of known event names, because the list is the part that goes stale.
  if lowered:find("%son%a+%s*=") then
    return false, "contains an event-handler attribute"
  end
  return true, nil
end

---@class Documentation.StartupGraph
---@field svg string          The document to inline.
---@field path string         Where it was read from, for the panel's own footnote.
---@field mtime integer|nil   Unix seconds, so the page can say how old the measurement is.

--- Read the flamegraph, if there is one worth embedding.
---
--- Every absence returns `nil` plus a reason, and the reasons are different
--- on purpose: "runtime-analysis is not installed" and "it is installed but
--- nobody has run `:RATelemetry flamegraph`" are two different things to tell
--- a reader, and only the second is worth acting on.
---@param opts Documentation.Opts
---@return Documentation.StartupGraph|nil graph
---@return string|nil reason  why there is none
function M.load(opts)
  local path = M.path(opts)
  if not path then
    return nil, "runtime-analysis.nvim is not installed"
  end

  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil, "no flamegraph written yet — run `:RATelemetry flamegraph`"
  end

  local svg = require("lib.nvim.fs.read")(path)
  if not svg then
    return nil, "flamegraph could not be read: " .. path
  end

  local ok, reason = M.is_safe(svg)
  if not ok then
    return nil, ("flamegraph refused (%s): %s"):format(reason or "unknown", path)
  end

  return {
    svg = svg,
    path = path,
    mtime = stat.mtime and stat.mtime.sec or nil,
  },
    nil
end

--- The rendered page with the baked-in graph taken back out.
---
--- Exists for exactly one caller: `--check`, which regenerates the map in
--- memory and compares it byte for byte against what is committed. A
--- flamegraph is machine-local and changes every time somebody measures, so
--- without this a repository that once baked one in would report itself stale
--- forever — the same failure `action.yml` already documents for the
--- parser-less standalone build, arriving from the other direction.
---
--- **And that is not a special case grudgingly carved out, it is what
--- `--check` means.** The gate asks whether the map still describes the
--- current source. A startup measurement describes a *session*: it can go out
--- of date without a single line changing, and it can stay correct across a
--- refactor that changes every line. It was never one of the things this
--- comparison is about.
---@param html string
---@return string
function M.strip(html)
  if type(html) ~= "string" then
    return html
  end
  -- `</template>` cannot occur inside the SVG — an SVG has no such element,
  -- and `M.is_safe` has already refused a file carrying `foreignObject`,
  -- which is the only way arbitrary HTML could have got in there.
  local stripped = html:gsub('<template id="startup%-graph".-</template>', "")
  return stripped
end

return M
