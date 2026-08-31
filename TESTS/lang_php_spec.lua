-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/lang_php_spec.lua — documentation.core.lang.php
--
-- Skips when the php parser is not reachable; `DOCMAP_PHP_PARSER` points at
-- one without installing it into a runtimepath.
--
-- Two of the assertions below are here because PHP contradicts a language
-- this tool already learned from. Its default visibility is **public** where
-- C#'s is private, so the rule has to be written as "not private and not
-- protected" rather than as "has `public`" — and writing it the other way
-- round would report every unmarked method in every legacy PHP file as
-- internal, which is C#'s interface bug with the sign flipped.
--
-- The fixture is written under a `src/` directory because the module name is
-- namespace plus file stem, and PSR-4 is what makes that resolvable.

return function(H)
  local eq, ok = H.eq, H.ok

  local explicit = os.getenv("DOCMAP_PHP_PARSER")
  local ok_add, has_php
  if explicit and explicit ~= "" then
    ok_add, has_php = pcall(vim.treesitter.language.add, "php", { path = explicit })
  else
    ok_add, has_php = pcall(vim.treesitter.language.add, "php")
  end

  local php = require("documentation.core.lang_registry").get("php")
  ok(php ~= nil, "the php backend must be registered")

  -- ---------------------------------------------------------------------
  -- Contract answers, which hold with or without a grammar installed.
  -- ---------------------------------------------------------------------
  eq(php.is_source("Widget.php"), true)
  eq(php.is_source("composer.json"), false, "a manifest is not a source file")
  eq(php.module_tag, false, "a namespace is a language construct, not a doc tag")
  eq(php.param_docs, true, "PHPDoc's @param names each one")
  eq(php.line_comments[1], "//")

  if not (ok_add and has_php) then
    ok(true, "lang.php: php parser not installed — skipping the rest")
    return
  end

  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. "/src", "p")
  local function write(rel, body)
    local path = root .. "/" .. rel
    local fw = assert(io.open(path, "w"))
    fw:write(body)
    fw:close()
    return path
  end

  local file = write(
    "src/Widget.php",
    table.concat({
      "<?php",
      "// Copyright (c) Somebody. Licensed under MIT.",
      "",
      "declare(strict_types=1);",
      "",
      "namespace Acme\\Widgets;",
      "",
      "use Acme\\Other\\Thing;",
      "use Acme\\Aliased\\Deep as Alias;",
      "",
      "require_once __DIR__ . '/helpers.php';",
      "",
      "/**",
      " * A widget that does things.",
      " *",
      " * More detail here.",
      " */",
      "class Widget implements Doer",
      "{",
      "    /** How many. */",
      "    public const MAX = 10;",
      "",
      "    private int $count = 0;",
      "",
      "    /**",
      "     * Adds two numbers.",
      "     *",
      "     * @param int $x The first number.",
      "     * @param int $y The second number,",
      "     *   continued on a new line.",
      "     * @return int Their sum.",
      "     */",
      "    public function add(int $x, int $y): int",
      "    {",
      "        return $x + $y;",
      "    }",
      "",
      "    /** Not published. */",
      "    private function helper(): void {}",
      "",
      "    function implicitPublic(): void {}",
      "",
      "    protected function guarded(): void {}",
      "",
      "    /** @internal Not for you. */",
      "    public function taggedInternal(): void {}",
      "}",
      "",
      "/** An interface. */",
      "interface Doer",
      "{",
      "    /** Do it. */",
      "    public function go(int $n): void;",
      "}",
      "",
      "/** A free function. */",
      "function freeStanding(string $s): string",
      "{",
      "    return $s;",
      "}",
      "",
    }, "\n")
  )

  -- ---------------------------------------------------------------------
  -- The header: namespace plus stem, and no license banner.
  -- ---------------------------------------------------------------------
  local header = php.parse_header(file)
  eq(
    header.module,
    "Acme\\Widgets\\Widget",
    "namespace plus file stem — PSR-4 requires the two to agree, which is what "
      .. "makes a `use` elsewhere resolve to this file"
  )
  eq(header.summary, "A widget that does things.", "the first type's doc block is the file's")
  ok(header.body:match("More detail"), "and the rest of the block is the body")
  ok(
    not header.summary:match("Copyright"),
    "a license banner is a `//` comment and only `/**` is documentation"
  )

  local fns, _, requires, symbols = php.scan_file(file)
  local by = {}
  for _, fn in ipairs(fns) do
    by[fn.name] = fn
  end

  -- ---------------------------------------------------------------------
  -- Visibility, and the default that runs opposite to C#'s.
  -- ---------------------------------------------------------------------
  eq(by["Widget::add"].internal, false, "explicitly public")
  eq(by["Widget::helper"].internal, true, "explicitly private")
  eq(by["Widget::guarded"].internal, true, "protected is not published")
  eq(
    by["Widget::implicitPublic"].internal,
    false,
    "**a PHP method with no modifier is public** — the opposite of C#, where "
      .. "the same absence means private"
  )
  eq(
    by["Widget::taggedInternal"].internal,
    true,
    "PHPDoc's @internal keeps a `public` method out of the published surface — "
      .. "PHP is the only backend here where a keyword and an authoring "
      .. "convention are both available and both read"
  )
  eq(
    by["Doer::go"].internal,
    false,
    "an interface member is public and cannot be declared otherwise — writing "
      .. "`private` there is a fatal error. The fourth language to need this, "
      .. "after C#, Go and Rust"
  )
  eq(by["freeStanding"].internal, false, "a free function has no visibility to declare")

  -- ---------------------------------------------------------------------
  -- PHPDoc: the sigil comes off, or nothing would ever match.
  -- ---------------------------------------------------------------------
  eq(#by["Widget::add"].params, 2)
  eq(by["Widget::add"].params[1].name, "x", "`@param int $x` documents the parameter named `x`")
  eq(by["Widget::add"].params[1].type, "int", "the type comes before the name in PHPDoc")
  eq(by["Widget::add"].params[1].desc, "The first number.")
  eq(
    by["Widget::add"].params[2].desc,
    "The second number, continued on a new line.",
    "a description continued on the next line is joined"
  )
  eq(#by["Widget::add"].returns, 1)
  eq(by["Widget::add"].returns[1].type, "int")
  eq(by["Widget::add"].signature, "Widget::add(x, y)", "and the signature agrees with them")

  -- ---------------------------------------------------------------------
  -- Both kinds of require edge, which is what PHP has and C, Java and C#
  -- each have only half of.
  -- ---------------------------------------------------------------------
  local mods = {}
  for _, r in ipairs(requires) do
    mods[r.module] = true
  end
  eq(mods["Acme\\Other\\Thing"], true, "a `use` names a class, which under PSR-4 is a file")
  eq(mods["Acme\\Aliased\\Deep"], true, "an alias names the same class")
  eq(
    mods["./helpers.php"],
    true,
    "`__DIR__ . '/helpers.php'` is relative and its slash is a separator — read "
      .. "literally it would be `/helpers.php`, a real file somewhere else"
  )

  local sym = {}
  for _, s in ipairs(symbols) do
    sym[s.name] = s
  end
  eq(sym["Widget"].detail, "class")
  eq(sym["Doer"].detail, "interface")
  eq(sym["Widget::MAX"].kind, "constant")
  eq(sym["Widget::MAX"].summary, "How many.")
  eq(sym["Widget::count"].kind, "binding", "and a property's `$` is not part of its name")

  -- ---------------------------------------------------------------------
  -- **PHP source outside `<?php` is text, not code**, which makes it the
  -- only backend here whose files are not code from the first byte — and the
  -- reason the contract carries `code_prelude`.
  --
  -- Found by `backend_contract_spec.lua`, whose job is to prove a declared
  -- comment token *works* rather than that it is present. It probed with a
  -- bare `// TODO: proof` and got nothing — not because the token is wrong,
  -- but because that string is not PHP. The grammar was right; the question
  -- was.
  -- ---------------------------------------------------------------------
  local markers = require("documentation.core.markers")
  eq(php.code_prelude, "<?php\n")
  eq(#markers.scan_source(php.code_prelude .. "// TODO: finish this", php), 1)
  eq(
    #markers.scan_source("// TODO: finish this", php),
    0,
    "and without the tag there is no comment to find, which is correct rather than a miss"
  )
end
