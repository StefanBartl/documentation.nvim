---@module 'documentation.core.endpoint_coverage'
--- The static x runtime join for routes — `runtime-analysis.nvim`'s own
--- `docs/ROADMAP.md` §6.2. This tree's own static analysis
--- (`core/endpoints.lua`) knows every route the source declares;
--- `runtime-analysis.history` knows which ones were actually sent, per
--- project. "Three of your eleven routes have never been exercised" is a
--- real answer neither side can give alone.
---
--- **Soft dependency, same discipline as `telemetry_join.lua`.**
--- `core.soft_require.probe("runtime-analysis.history")` — absent entirely, or
--- nothing was ever sent for this project, is "no data", never treated as
--- "every route is uncovered". Request history (see that module's own
--- doc-comment) is method + url + status + timestamp only — no headers, no
--- body — so this join can only ever say a route *was reached*, never with
--- what.
---
--- **Path matching, "record it, don't guess it".** A declared route path
--- (`/users/:id` — Express/Fastify/Koa/Connect/Restify — or `/users/{id}`
--- — Hapi) is converted to a Lua pattern matching one path segment per
--- param; a recorded URL's own path is extracted the same way regardless
--- of whether it is a real absolute URL, a bare path, or an unresolved
--- `{{var}}`-templated one (`runtime-analysis.env`'s own trap: history
--- records the template, never the resolved value, so `{{baseUrl}}` is a
--- real, expected prefix here — treated the same way a real scheme+host
--- would be, stripped rather than matched against). Optional params
--- (`:id?`), wildcards (`*`) and regex routes are outside what this
--- pattern can express — a route using one of those is simply never
--- matched, not matched wrong.

local M = {}

---Read `root`'s own request history, no live instance or plugin session
---required — the same "works from a fresh `:DocMap check`" shape
---`telemetry_join.load` already has.
---@param root string
---@return RA.History.Entry[]? entries `nil` when `runtime-analysis.nvim`
---is not installed, or nothing was ever sent for this project.
function M.load(root)
  local history = require("documentation.core.soft_require").probe("runtime-analysis.history")
  if not history then
    return nil
  end
  local ok_list, entries = pcall(history.list, { root = root })
  if not ok_list or not entries then
    return nil
  end
  return entries
end

---A URL's own path component — scheme+host, or an unresolved `{{var}}`
---prefix standing in for one, and any query/fragment stripped.
---@param url string
---@return string
function M.path_of(url)
  local rest = url:match("^%b{}(.*)$")
  if not rest then
    rest = url:match("^%a[%w+.%-]*://[^/]*(.*)$")
  end
  rest = rest or url
  rest = rest:match("^([^?#]*)") or rest
  if rest == "" then
    rest = "/"
  end
  return rest
end

---@param route_path string
---@return string lua_pattern
function M.route_pattern(route_path)
  local escaped = route_path:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
  local pattern = escaped:gsub(":[%w_]+", "[^/]+")
  -- `{` and `}` are not Lua pattern metacharacters, so the escape above
  -- above already left them literal — this substitution runs on the
  -- already-escaped string, matching `{name}` verbatim.
  pattern = pattern:gsub("{[%w_]+}", "[^/]+")
  return "^" .. pattern .. "/?$"
end

---Every history entry whose method and path match `spec` — `entries`'
---own newest-first order is preserved.
---@param spec Documentation.EndpointSpec
---@param entries RA.History.Entry[]
---@return RA.History.Entry[]
function M.matches(spec, entries)
  local pattern = M.route_pattern(spec.path)
  local method = spec.method:lower()
  local out = {}
  for _, e in ipairs(entries) do
    if method == "all" or e.method:lower() == method then
      if M.path_of(e.url):match(pattern) then
        out[#out + 1] = e
      end
    end
  end
  return out
end

return M
