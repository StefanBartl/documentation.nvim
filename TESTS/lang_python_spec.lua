-- TESTS/lang_python_spec.lua — documentation.core.lang.python
--
-- Skips when the python parser is not reachable, the precedent
-- `lang_js_spec.lua` set and for the same reason: CI does not install a
-- grammar this repository does not vendor. `DOCMAP_PYTHON_PARSER` points at
-- one without installing it into a runtimepath, which is how the assertions
-- below were run during development.
--
-- Three of them are here because Python is the first language in this tool
-- to have each property: documentation that is a *string* rather than a
-- comment, a documentation convention that forks three ways inside one
-- repository, and an export list (`__all__`) that overrides the naming
-- convention in both directions.

return function(H)
  local eq, ok = H.eq, H.ok

  -- `pcall` alone is not enough: `language.add` returns a falsy value rather
  -- than erroring when it cannot find the parser.
  local explicit = os.getenv("DOCMAP_PYTHON_PARSER")
  local ok_add, has_python
  if explicit and explicit ~= "" then
    ok_add, has_python = pcall(vim.treesitter.language.add, "python", { path = explicit })
  else
    ok_add, has_python = pcall(vim.treesitter.language.add, "python")
  end

  local registry = require("documentation.core.lang_registry")
  local py = registry.get("python")
  ok(py ~= nil, "the python backend must be registered")

  -- ---------------------------------------------------------------------
  -- Contract answers, which hold with or without a grammar installed.
  -- ---------------------------------------------------------------------
  eq(py.is_source("thing.py"), true)
  eq(py.is_source("thing.pyi"), true, "a stub file is a source file")
  eq(py.is_source("thing.pyc"), false, "compiled bytecode is not")
  eq(py.is_source("thing.lua"), false)
  eq(py.module_tag, false, "the import path is the file path")
  eq(py.module_file, "__init__.py", "a package is a directory, the init.lua shape")
  eq(py.param_docs, true, "all three docstring styles name parameters")
  eq(#py.block_comments, 0, "Python has no block comment — a triple-quoted string is a string")
  eq(py.line_comments[1], "#")

  if not (ok_add and has_python) then
    ok(
      true,
      "lang.python: python parser not installed — skipping the rest (see this file's header)"
    )
    return
  end

  local function scan(body)
    local file = H.tmpfile(".py")
    local fw = assert(io.open(file, "w"))
    fw:write(body)
    fw:close()
    return file
  end

  -- ---------------------------------------------------------------------
  -- Docstrings, visibility, imports, symbols.
  -- ---------------------------------------------------------------------
  local file = scan(table.concat({
    '"""A module of two things.',
    "",
    "Second line of the module doc.",
    '"""',
    "",
    "import os",
    "from . import sibling",
    "from ..pkg import deep",
    "",
    '__all__ = ["add", "_kept"]',
    "",
    "CONST = 42",
    "",
    "def add(x, y):",
    '    """Add two numbers.',
    "",
    "    Args:",
    "        x: The first number.",
    "        y: The second number.",
    "",
    "    Returns:",
    "        int: Their sum.",
    '    """',
    "    return x + y",
    "",
    "def _kept(z):",
    '    """Underscored but exported."""',
    "    return z",
    "",
    "def dropped(z):",
    '    """Public-looking but not in __all__."""',
    "    return z",
    "",
    "class Thing:",
    '    """A class."""',
    "",
    "    def __init__(self):",
    '        """Build one."""',
    "        pass",
    "",
    "    def go(self, n):",
    '        """Do the thing.',
    "",
    "        :param n: how many times",
    "        :returns: nothing",
    '        """',
    "        pass",
    "",
    "    def _helper(self):",
    '        """Not published."""',
    "        pass",
    "",
  }, "\n"))

  local header = py.parse_header(file)
  eq(header.summary, "A module of two things.", "a module docstring is the file's own doc")
  ok(header.body:match("Second line"), "and the rest of it is the body")
  eq(header.module, nil, "Python has no module tag to read")

  local fns, _, requires, symbols = py.scan_file(file)
  local by = {}
  for _, fn in ipairs(fns) do
    by[fn.name] = fn
  end

  -- **`__all__` beats the underscore, in both directions.** This is the
  -- assertion the whole visibility design rests on: without it a module's
  -- own statement of what it publishes would lose to a naming habit.
  eq(by["add"].internal, false, "named in __all__")
  eq(by["_kept"].internal, false, "underscored, but __all__ says it is published")
  eq(by["dropped"].internal, true, "public-looking, but __all__ does not list it")

  -- A method is judged by its own name, never against `__all__` — which
  -- lists module-level names and never methods. The first version of this
  -- backend got that wrong through `owner and nil or exported`, where
  -- `x and nil` is falsy and the `or` branch runs: every method came back
  -- internal, `Thing.go` included.
  eq(by["Thing.go"].internal, false, "a method is judged by its own name")
  eq(by["Thing._helper"].internal, true)
  eq(by["Thing.__init__"].internal, false, "a dunder is the most public thing in a class")

  -- The receiver is not in the call signature, and dropping it is what keeps
  -- `undocumented-param` correct: no docstring convention documents `self`.
  eq(by["Thing.go"].signature, "Thing.go(n)", "self is bound by the attribute access")
  eq(by["Thing.__init__"].signature, "Thing.__init__()")
  eq(#by["Thing.go"].params, 1, "and the documented parameters match what is declared")

  -- **The owner as a field, not as a prefix of the name.** The whole of
  -- engine item M7 rests on this being separable: `Thing.go` written at
  -- module scope and `go` written inside `class Thing` produce the identical
  -- `name`, so a string-prefix match cannot tell a method from a function
  -- that happens to be dotted.
  eq(by["Thing.go"].owner, "Thing", "a method knows what owns it")
  eq(by["Thing.go"].owner_kind, "class", "Python's only owning construct")
  eq(by["add"].owner, nil, "a module-level function has no owner")
  eq(by["add"].owner_kind, nil, "and no kind either — the two are set together")

  local scopes = require("documentation.core.scopes")
  local free, groups = scopes.split(fns)
  eq(#groups, 1, "one class in this file, one scope")
  eq(groups[1].name, "Thing")
  eq(groups[1].kind, "class")
  eq(#groups[1].functions, 3, "__init__, go and _helper")
  eq(#free, 3, "add, _kept and dropped belong to the module")

  eq(by["add"].signature, "add(x, y)")
  eq(#by["add"].params, 2)
  eq(by["add"].params[1].name, "x")
  eq(by["add"].params[1].desc, "The first number.")
  eq(#by["add"].returns, 1)

  -- Relative imports resolve; absolute ones are recorded as written, because
  -- `import a.b` is looked up along `sys.path` and resolving it against this
  -- tree would be a guess dressed as an edge.
  local mods = {}
  for _, r in ipairs(requires) do
    mods[r.module] = true
  end
  eq(mods["os"], true, "an absolute import, as written")
  eq(mods["./sibling"], true, "`from . import x` is the file beside this one")
  eq(mods["../pkg"], true, "and a second dot is one package up")

  local sym = {}
  for _, s in ipairs(symbols) do
    sym[s.name] = s
  end
  eq(sym["CONST"].kind, "constant")
  eq(sym["CONST"].detail, "42")
  eq(sym["Thing"].kind, "table", "a class is a module-scope binding, and its methods are functions")
  eq(sym["__all__"], nil, "the export list is read, not reported as a constant the module defines")

  -- ---------------------------------------------------------------------
  -- The three docstring styles, detected per docstring rather than per
  -- project — because one repository routinely mixes them.
  -- ---------------------------------------------------------------------
  local styles = scan(table.concat({
    "def google(a, b):",
    '    """Google style.',
    "",
    "    Args:",
    "        a (int): The first one.",
    "        b (str): The second one,",
    "            continued on a new line.",
    "",
    "    Returns:",
    "        bool: Whether it worked.",
    "",
    "    Raises:",
    "        ValueError: never.",
    '    """',
    "",
    "def numpy(a, b):",
    '    """NumPy style.',
    "",
    "    Parameters",
    "    ----------",
    "    a : int",
    "        The first one.",
    "    b : str",
    "        The second one.",
    "",
    "    Returns",
    "    -------",
    "    bool",
    "        Whether it worked.",
    '    """',
    "",
    "def plain(a):",
    '    """Just a sentence, no sections at all."""',
    "",
  }, "\n"))

  local sfns = py.scan_file(styles)
  local sby = {}
  for _, fn in ipairs(sfns) do
    sby[fn.name] = fn
  end

  eq(#sby["google"].params, 2, "Google's Args: block")
  eq(sby["google"].params[1].type, "int", "with the parenthesised type")
  eq(
    sby["google"].params[2].desc,
    "The second one, continued on a new line.",
    "and a description continued on the next line is joined, not truncated"
  )
  eq(#sby["google"].returns, 1)
  ok(not sby["google"].body:match("ValueError"), "a Raises: section is not folded into the prose")

  eq(#sby["numpy"].params, 2, "NumPy's underlined section")
  eq(sby["numpy"].params[1].type, "int")
  eq(sby["numpy"].params[1].desc, "The first one.")
  eq(#sby["numpy"].returns, 1)

  -- **No style is a real answer.** A docstring that is one prose sentence
  -- has no parameter documentation, and inventing some from its prose would
  -- be the confident guess this tool refuses everywhere else.
  eq(#sby["plain"].params, 0, "one prose sentence declares no parameters")
  eq(sby["plain"].summary, "Just a sentence, no sections at all.")

  -- ---------------------------------------------------------------------
  -- What is *not* a docstring. Python's own rule: `__doc__` is set only when
  -- the first statement is a string literal, so anything else in that slot
  -- means undocumented — and reading it any other way would credit prose the
  -- language itself does not.
  -- ---------------------------------------------------------------------
  local notdoc = scan(table.concat({
    "def later(a):",
    "    x = 1",
    '    """This is not a docstring — it is the second statement."""',
    "    return x",
    "",
  }, "\n"))
  local nfns = py.scan_file(notdoc)
  eq(nfns[1].summary, "", "a string that is not the first statement documents nothing")

  -- A `# type: ignore` above the docstring is common and must not un-document
  -- the function: a comment is skipped rather than treated as a wall.
  local commented = scan(table.concat({
    "def fine(a):",
    "    # type: ignore",
    '    """Still documented."""',
    "    return a",
    "",
  }, "\n"))
  eq(py.scan_file(commented)[1].summary, "Still documented.")

  -- ---------------------------------------------------------------------
  -- Three things a real project taught this backend that the fixtures above
  -- did not. All three were found by scanning `psf/requests` and all three
  -- were silent — a wrong answer rather than a missing one.
  -- ---------------------------------------------------------------------
  local real = scan(table.concat({
    '"""mypkg.api',
    "~~~~~~~~~~~~",
    "",
    "What this module does.",
    '"""',
    "",
    "def send(method, url=None, **kwargs):",
    '    """Send it.',
    "",
    "    :param method: the verb",
    "    :param url: where to",
    -- Escaped twice on purpose: reST writes `\*\*kwargs`, and this is a Lua
    -- string, so each backslash needs one of its own.
    "    :param \\*\\*kwargs: the rest",
    '    """',
    "",
    "def typed(a, *args: int, **kwargs: object):",
    '    """Typed splats."""',
    "",
  }, "\n"))

  -- 1. A reST section underline is punctuation. Joined to the title above it
  --    this gave `mypkg.api ~~~~~~~~~~~~` as the module summary.
  eq(py.parse_header(real).summary, "mypkg.api", "a reST underline is not part of the sentence")
  ok(py.parse_header(real).body:match("What this module does"), "and the prose survives it")

  local rfns = py.scan_file(real)
  local rby = {}
  for _, fn in ipairs(rfns) do
    rby[fn.name] = fn
  end

  -- 2. reST escapes the asterisks. Taken verbatim, the documented name can
  --    never match the declared one — a `param-name-mismatch` on every
  --    `**kwargs` in every reST-documented project.
  eq(rby["send"].params[3].name, "**kwargs", "the escape belongs to the markup, not to the name")

  -- 3. A typed splat nests one level deeper, and missing it dropped the
  --    parameter from the signature entirely.
  eq(rby["send"].signature, "send(method, url, **kwargs)")
  eq(rby["typed"].signature, "typed(a, *args, **kwargs)", "`*args: int` is a typed splat")

  -- ---------------------------------------------------------------------
  -- Markers come from `#` comments and only those. A "TODO" inside a
  -- docstring is prose the author published on purpose.
  -- ---------------------------------------------------------------------
  local markers = require("documentation.core.markers")
  eq(#markers.scan_source("# TODO: finish this", py), 1)
end
