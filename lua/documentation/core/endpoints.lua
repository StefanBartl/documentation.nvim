---@module 'documentation.core.endpoints'
--- Call-based route registrations — Express/Fastify/Koa-shaped
--- `app.get(path, handler)` calls — recognized in an already-parsed JS/TS/TSX
--- tree. The "call-based routing" half of `docs/ECOSYSTEM.md` §3.1's split;
--- file-based routing (Next.js/SvelteKit/Nuxt/Remix) is explicitly the other
--- half and belongs in a Hierarchy view instead, not attempted here — a
--- route's parent directory carries real structure there, and flattening it
--- into a list would lose the fact worth showing.
---
--- ## What is recognized, stated narrowly
---
--- `IDENTIFIER.METHOD("/path", ...handler)` where METHOD is a lowercase HTTP
--- verb (`get`/`post`/`put`/`delete`/`patch`/`options`/`head`) or `all`, and
--- the first argument is a string literal starting with `/`. Nothing checks
--- what IDENTIFIER is bound to — the same reasoning `core/plugins.lua`'s
--- `looks_like_repo` gives for a bare-string heuristic: a call shaped exactly
--- like a route registration, with a path-shaped first argument, is already
--- a narrow and specific signal, and requiring a verified `express()`/
--- `Router()` binding first would trade a real, cheap recognizer for a
--- variable-flow analysis this repository does not otherwise do anywhere.
--- The accepted risk, stated rather than hidden: an unrelated object whose
--- own `.get(path, handler)`-shaped method happens to match (a cache, a
--- router-like abstraction) would false-positive — not verified against a
--- real Express application; `docs/ECOSYSTEM.md`'s own stated limit ("every
--- framework-syntax claim above is unverified") still applies here.
---
--- `app.use(...)` is not recognized: `use` is not in the method set, since it
--- mounts middleware — optionally with no path at all — rather than
--- registering one route.
---
--- With more than two arguments (middleware chained before the final
--- handler, `app.post(path, authMiddleware, createUser)`), the *last*
--- argument is taken as the handler — the one that actually produces the
--- response, which is the one worth a reader's attention; the middleware
--- before it is real but not this recognizer's concern.
---
--- ## What "framework" means here
---
--- Not guessed from the call shape — Express, Fastify and Koa (via
--- `koa-router`) all accept the identical `app.get(path, handler)` shape, so
--- nothing about the call itself says which one it is. Read instead from
--- this file's own already-extracted `requires`: if the file required
--- `express`/`fastify`/`koa`/`koa-router`/`connect`/`restify`/`hapi`/
--- `@hapi/hapi`, every route in it is labelled with that package;
--- otherwise `framework` is `nil` — the call shape matched, but nothing
--- here claims to know whose convention it is.
---
--- ## What "documented" means
---
--- True only when the handler is a *named* reference (`getUser`, not an
--- inline `function(req, res) {...}` or arrow expression) that resolves to
--- one of this same file's own scanned functions with a non-empty summary.
--- An inline handler has no separate declaration to check, so it is
--- `false` — not "unknown" pretending to be "undocumented."

local M = {}

local HTTP_METHODS = {
  get = true,
  post = true,
  put = true,
  delete = true,
  patch = true,
  options = true,
  head = true,
  all = true,
}

local FRAMEWORK_BY_IMPORT = {
  express = "express",
  fastify = "fastify",
  koa = "koa",
  ["koa-router"] = "koa",
  connect = "connect",
  restify = "restify",
  hapi = "hapi",
  ["@hapi/hapi"] = "hapi",
}

---Parsed queries are per-grammar, same reason `core/lang/ecma.lua` caches
---its own call/identifier queries this way (there, via `lib.lua.memo`).
---@param lang string
local route_query = require("lib.lua.memo").fn(function(lang)
  return vim.treesitter.query.parse(
    lang,
    [[
    (call_expression
      function: (member_expression
        property: (property_identifier) @method)
      arguments: (arguments) @args) @call
    ]]
  )
end, { size = 8 })

---@param requires Documentation.RawRequire[]
---@return string?
local function detect_framework(requires)
  for _, r in ipairs(requires or {}) do
    local known = FRAMEWORK_BY_IMPORT[r.module]
    if known then
      return known
    end
  end
  return nil
end

---@param fns Documentation.FunctionInfo[]
---@return table<string, Documentation.FunctionInfo>
local function index_by_name(fns)
  local by_name = {}
  for _, fn in ipairs(fns) do
    by_name[fn.name] = fn
  end
  return by_name
end

---Every call-based route registration in an already-parsed JS/TS/TSX tree.
---@param root TSNode
---@param src string
---@param lang string
---@param fns Documentation.FunctionInfo[] This file's own already-scanned functions, for the `documented` cross-reference.
---@param requires Documentation.RawRequire[] This file's own already-extracted imports, for `framework`.
---@return Documentation.EndpointSpec[]
function M.extract(root, src, lang, fns, requires)
  local framework = detect_framework(requires)
  local by_name = index_by_name(fns)
  local out = {}

  local query = route_query(lang)
  local id_by_name = {}
  for id, name in ipairs(query.captures) do
    id_by_name[name] = id
  end

  for _, match in query:iter_matches(root, src) do
    local method_nodes = match[id_by_name.method]
    local args_nodes = match[id_by_name.args]
    local call_nodes = match[id_by_name.call]
    local method_node = method_nodes and method_nodes[1]
    local args_node = args_nodes and args_nodes[1]
    local call_node = call_nodes and call_nodes[1]

    if method_node and args_node and call_node then
      local method = vim.treesitter.get_node_text(method_node, src)
      if HTTP_METHODS[method] then
        local path_node = args_node:named_child(0)
        if path_node and path_node:type() == "string" then
          local content = path_node:named_child(0)
          local path = content and vim.treesitter.get_node_text(content, src)
          if path and path:sub(1, 1) == "/" then
            local n = args_node:named_child_count()
            local handler_node = n >= 2 and args_node:named_child(n - 1) or nil
            local handler = handler_node
                and handler_node:type() == "identifier"
                and vim.treesitter.get_node_text(handler_node, src)
              or nil

            local srow = call_node:range()
            out[#out + 1] = {
              method = method,
              path = path,
              handler = handler,
              line = srow + 1,
              framework = framework,
              documented = (
                handler ~= nil
                and by_name[handler] ~= nil
                and by_name[handler].summary ~= ""
              ),
            }
          end
        end
      end
    end
  end

  table.sort(out, function(a, b)
    return a.line < b.line
  end)
  return out
end

return M
