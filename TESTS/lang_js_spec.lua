-- TESTS/lang_js_spec.lua — documentation.core.lang.js/ts/tsx (ecma.lua)
--
-- Skips rather than failing when the javascript/typescript/tsx treesitter
-- parsers are not on the runtimepath — the same precedent
-- docmap_browse_spec.lua sets for a missing prerequisite (there, this
-- repository's own committed map; here, a parser CI does not install yet).
-- The extraction itself was verified against real parses of real JS/TS/TSX
-- files during development (see docs/ROADMAP/MULTILANG.md and the commit
-- this file landed in) with grammars built from source for that purpose;
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

  local fns, _, requires, _, _, lines = js_backend.scan_file(fixture)

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

  eq(#requires, 3, "lang.js: ESM default + named imports, and CommonJS require, all three found")
  local mods = {}
  for _, r in ipairs(requires) do
    mods[r.module] = true
  end
  ok(mods["fs"] and mods["fs/promises"] and mods["os"], "lang.js: with the right module strings")

  ok(lines > 0, "lang.js: line count computed the same way as the Lua backend")

  -- Module identity is deliberately never set — see ecma.lua's own header.
  local hdr = require("documentation.core.lang_registry").get("js").parse_header(fixture)
  eq(hdr.module, nil, "lang.js: module identity is never a tag — it is the file path, elsewhere")
  eq(hdr.summary, "Module-level summary line.", "lang.js: file-level JSDoc still gives a summary")

  os.remove(fixture)

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
