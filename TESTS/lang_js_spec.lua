-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/lang_js_spec.lua — documentation.core.lang.js/ts/tsx (ecma.lua)
--
-- Skips rather than failing when the javascript/typescript/tsx treesitter
-- parsers are not on the runtimepath — the same precedent
-- docmap_browse_spec.lua sets for a missing prerequisite (there, this
-- repository's own committed map; here, a parser CI does not install yet).
-- The extraction itself was verified against real parses of real JS/TS/TSX
-- files during development (see the commit this file landed in) with
-- grammars built from source for that purpose;
-- this spec runs the same assertions whenever the parser happens to be
-- available, and says plainly why it is empty when it is not.

return function(H)
  local eq, ok = H.eq, H.ok

  -- `pcall` alone is not enough: `vim.treesitter.language.add` returns a
  -- falsy value rather than erroring when it cannot find the parser, so the
  -- pcall itself reports `ok = true` even when nothing was actually added.
  -- The real signal is the function's own return value.
  local ok_js, has_js = pcall(vim.treesitter.language.add, "javascript")
  if not (ok_js and has_js) then
    ok(true, "lang.js: javascript parser not installed — skipping (see this file's header)")
    return
  end

  local js_backend = require("documentation.core.lang_registry").get("js")

  local fixture = H.tmpfile(".js")
  local fw = assert(io.open(fixture, "w"))
  fw:write(table.concat({
    "/**",
    " * Module-level summary line.",
    " */",
    "",
    "/**",
    " * Adds two numbers.",
    " * @param {number} a the first number",
    " * @param {number} b the second number",
    " * @returns {number} the sum",
    " */",
    "function add(a, b) {",
    "  if (a > 0) {",
    "    return a + b;",
    "  }",
    "  return b;",
    "}",
    "",
    "export const triple = (x) => x * 3;",
    "",
    "export default async function quadruple(x) {",
    "  return x * 4;",
    "}",
    "",
    'import fs from "fs";',
    'import { readFile } from "fs/promises";',
    'const os = require("os");',
    'var path = require("path");',
    "",
    "/**",
    " * A custom hook, by name alone.",
    " */",
    "function useCounter(initial) {",
    "  return initial;",
    "}",
    "",
    "/**",
    " * @internal",
    " */",
    "function helper() {",
    "  return 1;",
    "}",
  }, "\n"))
  fw:close()

  local fns, _, requires, _, _, _, lines = js_backend.scan_file(fixture)

  eq(#fns, 5, "lang.js: finds all four recognized function shapes plus the hook")
  eq(fns[1].name, "add", "lang.js: function_declaration recognized, in line order")
  eq(fns[1].summary, "Adds two numbers.", "lang.js: JSDoc summary read")
  eq(#fns[1].params, 2, "lang.js: @param lines parsed")
  eq(fns[1].params[1].name, "a", "lang.js: ... with the right name")
  eq(fns[1].params[1].type, "number", "lang.js: ... and the {type} annotation")
  eq(#fns[1].returns, 1, "lang.js: @returns parsed")
  eq(fns[1].complexity, 2, "lang.js: complexity counts the if statement")

  eq(fns[2].name, "triple", "lang.js: const-arrow-function form recognized")
  eq(fns[2].signature, "triple(x)", "lang.js: signature is name + real params, not JSDoc's")

  eq(fns[3].name, "quadruple", "lang.js: export default function recognized like a plain export")
  ok(fns[3].async, "lang.js: async detected from the real keyword, not a tag")

  eq(fns[4].name, "useCounter", "lang.js: hook found like any other function_declaration")
  ok(
    fns[4].is_hook,
    "lang.js: ... and flagged as a hook by name alone (docs/FRAMEWORK_CONVENTIONS.md)"
  )

  ok(fns[5].internal, "lang.js: @internal recognized the same as Lua's convention")
  ok(not fns[1].internal, "lang.js: ... and not set on a function without the tag")

  eq(
    #requires,
    4,
    "lang.js: ESM default + named imports, and CommonJS require (const and var), all four found"
  )
  local mods = {}
  for _, r in ipairs(requires) do
    mods[r.module] = true
  end
  ok(
    mods["fs"] and mods["fs/promises"] and mods["os"] and mods["path"],
    "lang.js: with the right module strings, including the var-declared require"
  )

  ok(lines > 0, "lang.js: line count computed the same way as the Lua backend")

  -- Module identity is deliberately never set — see ecma.lua's own header.
  local hdr = require("documentation.core.lang_registry").get("js").parse_header(fixture)
  eq(hdr.module, nil, "lang.js: module identity is never a tag — it is the file path, elsewhere")
  eq(hdr.summary, "Module-level summary line.", "lang.js: file-level JSDoc still gives a summary")

  os.remove(fixture)

  -- Calls/local_refs: `ecma.lua`'s own extraction, plus `calls.lua`'s
  -- language-agnostic resolver consuming it unmodified — the same two-step
  -- split Lua's own `functions.lua`/`calls.lua` pair uses.
  do
    local calls_fixture = H.tmpfile(".js")
    local cf = assert(io.open(calls_fixture, "w"))
    cf:write(table.concat({
      "function caller(a, b) {",
      "  const x = callee(a);",
      "  return obj.method(x, b);",
      "}",
      "",
      "function callee(y) {",
      "  return y * 2;",
      "}",
    }, "\n"))
    cf:close()

    local cfns, ccalls = js_backend.scan_file(calls_fixture)
    eq(#ccalls, 2, "lang.js: both a bare and a member-expression call site captured")

    local by_callee = {}
    for _, c in ipairs(ccalls) do
      by_callee[c.callee] = c
    end
    eq(
      by_callee["callee"].from_fn,
      "caller",
      "lang.js: bare call attributed to its enclosing function"
    )
    eq(
      by_callee["obj.method"].from_fn,
      "caller",
      "lang.js: a member-expression call site is captured too, raw text and all"
    )

    for _, fn in ipairs(cfns) do
      if fn.name == "callee" then
        eq(fn.local_refs, 1, "lang.js: local_refs counts the one call site, minus the declaration")
      elseif fn.name == "caller" then
        eq(fn.local_refs, 0, "lang.js: ... and zero when nothing else mentions the name")
      end
    end

    -- End to end: `calls.lua`'s resolver is completely unmodified for JS —
    -- feeding it this file's own scan output through a minimal one-node IR
    -- confirms the bare call actually becomes a real edge, and the
    -- member-expression one — `obj` is neither a require alias nor a
    -- same-file `M.`-style prefix, a shape JS has no equivalent of — is
    -- silently dropped rather than mis-resolved.
    local ir = {
      order = { "n1" },
      nodes = {
        n1 = {
          id = "n1",
          module = "sample",
          functions = cfns,
          requires_raw = {},
          calls_raw = ccalls,
        },
      },
      edges = {},
    }
    local edges = require("documentation.core.calls").build(ir)
    eq(#edges, 1, "lang.js: exactly the bare call resolves to a real edge")
    eq(edges[1].from_fn, "caller", "lang.js: ... from the right caller")
    eq(edges[1].to_fn, "callee", "lang.js: ... to the right callee")
    eq(edges[1].confidence, "exact", "lang.js: ... at full confidence, a same-file bare name")

    os.remove(calls_fixture)
  end

  -- Symbols: module-scope non-function, non-require bindings, mirroring
  -- `documentation.core.symbols`'s own Lua scope and classification.
  do
    local symbols_fixture = H.tmpfile(".js")
    local sf = assert(io.open(symbols_fixture, "w"))
    sf:write(table.concat({
      "/**",
      " * The cache config.",
      " */",
      "const CONFIG = {",
      "  a: 1,",
      "  b: 2,",
      "};",
      "",
      "const MAX_RETRIES = 3;",
      "",
      'let greeting = "hello";',
      "",
      "export const EXPORTED = { x: 1 };",
      "",
      "function realFunction() {",
      "  return 1;",
      "}",
      "",
      "const arrowFn = (x) => x * 2;",
      "",
      'const fromRequire = require("something");',
      "",
      "const computed = 1 + 2;",
    }, "\n"))
    sf:close()

    local sfns, _, sreqs, syms = js_backend.scan_file(symbols_fixture)
    eq(#sfns, 2, "lang.js: symbols fixture's two real functions still recognized as functions")
    eq(#sreqs, 1, "lang.js: the require() binding is a dependency, not a symbol")

    eq(#syms, 5, "lang.js: five module-scope bindings, functions and require excluded")
    local by_name = {}
    for _, s in ipairs(syms) do
      by_name[s.name] = s
    end

    eq(by_name.CONFIG.kind, "table", "lang.js: an object literal classified as a table")
    eq(by_name.CONFIG.detail, "2 fields", "lang.js: ... with a field count")
    eq(by_name.CONFIG.summary, "The cache config.", "lang.js: ... and its leading JSDoc summary")

    eq(by_name.MAX_RETRIES.kind, "constant", "lang.js: a number literal classified as a constant")
    eq(by_name.MAX_RETRIES.detail, "3", "lang.js: ... with the literal as its detail")

    eq(by_name.greeting.kind, "constant", "lang.js: a string literal classified as a constant too")

    eq(by_name.EXPORTED.kind, "table", "lang.js: export-wrapped const still recognized")
    eq(by_name.EXPORTED.detail, "1 field", "lang.js: ... unwrapped correctly, one field")

    eq(by_name.computed.kind, "binding", "lang.js: a computed expression falls to binding")

    ok(by_name.arrowFn == nil, "lang.js: a function-shaped declarator is not also a symbol")
    ok(by_name.fromRequire == nil, "lang.js: a require() binding is not also a symbol")

    os.remove(symbols_fixture)
  end

  -- Endpoints: call-based route registrations, `core/endpoints.lua`'s own
  -- recognizer, threaded through the seventh `scan_file` return value.
  do
    local ep_fixture = H.tmpfile(".js")
    local ef = assert(io.open(ep_fixture, "w"))
    ef:write(table.concat({
      'const express = require("express");',
      "const app = express();",
      "",
      "/**",
      " * Fetch one user by id.",
      " */",
      "function getUser(req, res) {",
      "  res.send(req.params.id);",
      "}",
      "",
      "function createUser(req, res) {",
      '  res.send("created");',
      "}",
      "",
      'app.get("/users/:id", getUser);',
      'app.post("/users", createUser);',
      'app.delete("/users/:id", function(req, res) { res.send("deleted"); });',
      "",
      'app.use("/static", staticMiddleware);', -- must not be recognized
      'cache.get("key");', -- must not be recognized: not path-shaped
    }, "\n"))
    ef:close()

    local _, _, _, _, _, endpoints = js_backend.scan_file(ep_fixture)
    eq(#endpoints, 3, "lang.js: three real routes found; use() and a non-path .get() excluded")

    local by_path = {}
    for _, e in ipairs(endpoints) do
      by_path[e.method .. " " .. e.path] = e
    end

    local get = by_path["get /users/:id"]
    ok(get, 'lang.js: app.get("/users/:id", ...) recognized')
    eq(get.handler, "getUser", "lang.js: ... with the named handler")
    eq(
      get.framework,
      "express",
      'lang.js: ... framework read from this file\'s own require("express")'
    )
    ok(get.documented, "lang.js: ... and documented, since getUser carries a JSDoc summary")

    local post = by_path["post /users"]
    ok(post, 'lang.js: app.post("/users", ...) recognized')
    ok(not post.documented, "lang.js: ... but not documented — createUser has no doc block")

    local del = by_path["delete /users/:id"]
    ok(del, "lang.js: app.delete(...) with an inline handler recognized")
    eq(
      del.handler,
      nil,
      "lang.js: ... but no handler name — nothing to name for an inline function"
    )
    ok(not del.documented, "lang.js: ... so not documented either")

    os.remove(ep_fixture)
  end

  -- TypeScript and TSX share the same extraction; a light touch confirms
  -- the registration wiring, not a second full pass over ecma.lua's logic.
  local ok_ts, has_ts = pcall(vim.treesitter.language.add, "typescript")
  if ok_ts and has_ts then
    local ts_fixture = H.tmpfile(".ts")
    local twf = assert(io.open(ts_fixture, "w"))
    twf:write("export function add(a, b) {\n  return a + b;\n}\n")
    twf:close()
    local ts_fns = require("documentation.core.lang_registry").get("ts").scan_file(ts_fixture)
    eq(#ts_fns, 1, "lang.ts: shares ecma.lua's recognizer, registered under its own extension")
    os.remove(ts_fixture)
  end
end
