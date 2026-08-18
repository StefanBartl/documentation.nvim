-- TESTS/lang_js_gaps_spec.lua — the three shapes ecma.lua used to miss
--
-- MULTILANG.md's Phase 1 shipped with three gaps stated plainly rather than
-- papered over: class methods, `.jsx`, and `module.exports = { … }`. This
-- covers all three.
--
-- Skips rather than fails without the javascript parser, the same precedent
-- `lang_js_spec.lua` sets and for the same reason — CI does not install one
-- yet, and a spec that fails on its absence would be reporting the
-- environment rather than the code.

return function(H)
  local eq, ok = H.eq, H.ok

  -- `pcall` alone is not enough: `language.add` returns falsy rather than
  -- erroring when the parser is missing, so the pcall reports success.
  local ok_js, has_js = pcall(vim.treesitter.language.add, "javascript")
  if not (ok_js and has_js) then
    ok(true, "lang.js gaps: javascript parser not installed — skipping (see this file's header)")
    return
  end

  local backend = require("documentation.core.lang_registry").get("js")

  ---@param body string
  ---@return table<string, string> name -> signature
  local function functions_of(body, suffix)
    local path = H.tmpfile(suffix or ".js")
    local fd = assert(io.open(path, "w"))
    fd:write(body)
    fd:close()
    local fns = backend.scan_file(path)
    local out = {}
    for _, fn in ipairs(fns) do
      out[fn.name] = fn.signature
    end
    os.remove(path)
    return out
  end

  -- Class methods, named `Class.method` — the same flat shape Lua already
  -- uses for `function M.foo()`, which is why this needed no new IR field.
  do
    local fns = functions_of(table.concat({
      "/** A greeter. */",
      "export class Greeter {",
      "  /** Say hello. */",
      "  hello(name) { return name; }",
      "  /** Build one. */",
      "  static make() { return new Greeter(); }",
      "  /** Not callable. */",
      "  get size() { return 1; }",
      "}",
      "/** Free function. */",
      "export function standalone() { return 1; }",
    }, "\n"))

    eq(fns["Greeter.hello"], "Greeter.hello(name)", "class: a method is qualified by its class")
    eq(fns["Greeter.make"], "Greeter.make()", "class: a static method too")
    -- A getter recorded as `Greeter.size()` would read as callable and is
    -- not one. Left out rather than shipped with a signature that lies.
    eq(fns["Greeter.size"], nil, "class: an accessor is skipped, not given a fake call signature")
    eq(fns["hello"], nil, "class: a method is never recorded under its bare name")
    eq(fns["standalone"], "standalone()", "class: a free function beside a class is unaffected")
  end

  -- `module.exports = { … }`. Before this, a CommonJS module written this way
  -- contributed no functions at all — an empty module rather than a wrong
  -- one, which is the failure mode that looks like success.
  do
    local fns = functions_of(table.concat({
      "module.exports = {",
      "  /** Read. */",
      "  read(p) { return p; },",
      "  /** Write. */",
      "  write: function (p) { return p; },",
      "  /** Arrow. */",
      "  arrow: (p) => p,",
      "  notAFunction: 42,",
      "};",
    }, "\n"))

    eq(fns["read"], "read(p)", "module.exports: the shorthand method form")
    eq(fns["write"], "write(p)", "module.exports: a function expression value")
    eq(fns["arrow"], "arrow(p)", "module.exports: an arrow value")
    eq(fns["notAFunction"], nil, "module.exports: a non-function property is not a function")
  end

  -- Only the direct form. Following an identifier back to its assignment is
  -- the kind of guess `deps.lua` already refuses to make about computed
  -- requires, and a guessed map is worse than an honest gap.
  do
    local fns = functions_of(table.concat({
      "const api = { read(p) { return p; } };",
      "module.exports = api;",
    }, "\n"))
    eq(fns["read"], nil, "module.exports: an indirect assignment is not followed")
  end

  -- `.jsx` is JavaScript, so `js.lua` claims it — verified rather than
  -- assumed, the javascript grammar parses a real component with no ERROR
  -- nodes.
  do
    ok(backend.is_source("app.jsx"), "jsx: the js backend claims .jsx")
    ok(backend.is_source("app.js"), "jsx: ... and still claims .js")

    local fns = functions_of(
      table.concat({
        "/** Render items. */",
        "export function App({ items }) {",
        "  return <div className='w'>{items.map((i) => <span key={i}>{i}</span>)}</div>;",
        "}",
      }, "\n"),
      ".jsx"
    )
    eq(
      fns["App"],
      "App({ items })",
      "jsx: a component's function is extracted through the JSX body"
    )
  end
end
