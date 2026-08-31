-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/lang_ocaml_spec.lua — documentation.core.lang.ocaml
--
-- Skips when the ocaml parsers are not reachable. Two are needed:
-- `DOCMAP_OCAML_PARSER` for `.ml` and `DOCMAP_OCAML_INTERFACE_PARSER` for
-- `.mli`, because they are different languages to the parser — an interface
-- holds `val` declarations with no bodies, which the implementation grammar
-- cannot read. This is the only backend of the twenty-three that selects
-- between two grammars by extension.
--
-- **The export list lives in another file**, which nothing else here does:
-- `widget.mli` says what `widget.ml` publishes, and the compiler enforces
-- it. So the fixture writes a real pair into a real directory — a test that
-- skipped the sibling would be testing a different function than the one
-- that runs.

return function(H)
  local eq, ok = H.eq, H.ok

  local function add_lang(name, var)
    local explicit = os.getenv(var)
    local ok_add, has
    if explicit and explicit ~= "" then
      ok_add, has = pcall(vim.treesitter.language.add, name, { path = explicit })
    else
      ok_add, has = pcall(vim.treesitter.language.add, name)
    end
    return ok_add and has
  end
  local has_ml = add_lang("ocaml", "DOCMAP_OCAML_PARSER")
  local has_mli = add_lang("ocaml_interface", "DOCMAP_OCAML_INTERFACE_PARSER")

  local ml = require("documentation.core.lang_registry").get("ocaml")
  ok(ml ~= nil, "the ocaml backend must be registered")

  eq(ml.is_source("widget.ml"), true)
  eq(ml.is_source("widget.mli"), true, "an interface is a source file and is mapped")
  eq(ml.is_source("dune-project"), false)
  eq(ml.module_tag, false, "a module's name is its file stem, by the compiler's rule")
  eq(ml.param_docs, true, "ocamldoc has `@param x`")
  eq(
    #ml.line_comments,
    0,
    "OCaml has no line comment at all — the first of the twenty-three with an "
      .. "empty `line_comments`, so markers are found through `(* … *)` alone"
  )

  if not (has_ml and has_mli) then
    ok(true, "lang.ocaml: parsers not installed — skipping the rest")
    return
  end

  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local function write(name, body)
    local path = dir .. "/" .. name
    local fw = assert(io.open(path, "w"))
    fw:write(body)
    fw:close()
    return path
  end

  local impl = write(
    "widget.ml",
    table.concat({
      "(* Copyright (c) Somebody. *)",
      "",
      "(** A widget module that does things.",
      "",
      "    More detail here. *)",
      "",
      "open Printf",
      "include Base",
      "",
      "(** How many. *)",
      "let max_count = 10",
      "",
      "(** A widget. *)",
      "type widget = { name : string }",
      "",
      "(** Adds two numbers.",
      "    @param x The first number.",
      "    @param y The second number.",
      "    @return Their sum. *)",
      "let add x y = x + y",
      "",
      "(** Not in the interface. *)",
      "let helper z = z",
      "",
    }, "\n")
  )

  write(
    "widget.mli",
    table.concat({
      "(** A widget module that does things. *)",
      "",
      "val max_count : int",
      "",
      "(** Adds two numbers. *)",
      "val add : int -> int -> int",
      "",
    }, "\n")
  )

  local header = ml.parse_header(impl)
  eq(header.module, "Widget", "the file stem, capitalised — the compiler's own rule")
  eq(header.summary, "A widget module that does things.")
  ok(header.body:match("More detail"))
  ok(
    not header.summary:match("Copyright"),
    "`(*` is a comment and `(**` is documentation — ocamldoc's rule, and one "
      .. "worth honouring strictly because OCaml projects follow it"
  )

  local fns, _, requires, symbols = ml.scan_file(impl)
  local by = {}
  for _, fn in ipairs(fns) do
    by[fn.name] = fn
  end

  -- ---------------------------------------------------------------------
  -- **The interface decides.** This is the assertion the whole file exists
  -- for: `add` is in `widget.mli` and `helper` is not, and the two look
  -- identical in `widget.ml`.
  -- ---------------------------------------------------------------------
  eq(by["add"].internal, false, "declared in the sibling .mli")
  eq(
    by["helper"].internal,
    true,
    "absent from it — and unreachable from outside the module, enforced by "
      .. "the compiler rather than by convention"
  )

  eq(#by["add"].params, 2, "ocamldoc's `@param` is a real tag")
  eq(by["add"].params[1].name, "x")
  eq(by["add"].returns[1].desc, "Their sum.")

  local mods = {}
  for _, r in ipairs(requires) do
    mods[r.module] = true
  end
  eq(mods["Printf"], true, "`open`")
  eq(mods["Base"], true, "and `include`")

  local sym = {}
  for _, s in ipairs(symbols) do
    sym[s.name] = s
  end
  eq(
    sym["max_count"].kind,
    "constant",
    "a `let` with no parameters is a value — OCaml does not distinguish them "
      .. "syntactically, so the parameters decide, as in Haskell"
  )
  eq(sym["widget"].detail, "type")
  eq(sym["widget"].summary, "A widget.")

  -- The `.mli` is mapped too, and is where a well-kept project documents.
  local ifns = ml.scan_file(dir .. "/widget.mli")
  local iby = {}
  for _, fn in ipairs(ifns) do
    iby[fn.name] = fn
  end
  eq(iby["add"] ~= nil, true, "a `val` declaration is an entity")
  eq(iby["add"].summary, "Adds two numbers.", "and carries the interface's own prose")
  eq(iby["add"].internal, false, "nothing in an interface is internal — it *is* the surface")

  -- ---------------------------------------------------------------------
  -- **No `.mli` means everything is public** — the third time this tool has
  -- met "absent means everything", after Haskell's missing export list and
  -- Python's missing `__all__`. Every time, the other reading would report
  -- a whole module as private.
  -- ---------------------------------------------------------------------
  local lone = write(
    "solo.ml",
    table.concat({
      "(** A module with no interface. *)",
      "",
      "let visible x = x",
      "",
    }, "\n")
  )
  eq(ml.scan_file(lone)[1].internal, false, "no interface publishes everything")

  -- ---------------------------------------------------------------------
  -- **OCaml documents *after* a declaration, and that is the dominant form
  -- in interfaces.** The first version of this backend called it a rare
  -- shape for record fields and skipped it; scanned against
  -- `mirage/alcotest` that found 0 documented `val`s in 50, because every
  -- one is written signature-first with the prose beneath. Reporting a
  -- thoroughly documented interface as undocumented is the Doxygen-only
  -- mistake about C, in a language where *position* rather than punctuation
  -- was what got read wrong.
  -- ---------------------------------------------------------------------
  write(
    "trailing.mli",
    table.concat({
      "val above : int -> int",
      "(** Documented from below, the way interfaces are written. *)",
      "",
      "(** Documented from above, which also works. *)",
      "val below : int -> int",
      "",
    }, "\n")
  )
  local tfns = ml.scan_file(dir .. "/trailing.mli")
  local tby = {}
  for _, fn in ipairs(tfns) do
    tby[fn.name] = fn
  end
  eq(
    tby["above"].summary,
    "Documented from below, the way interfaces are written.",
    "a block on the row right after the declaration documents it"
  )
  eq(
    tby["below"].summary,
    "Documented from above, which also works.",
    "and a block separated by a blank line belongs to what follows it, not to "
      .. "what came before"
  )

  local markers = require("documentation.core.markers")
  eq(#markers.scan_source("(* TODO: finish this *)", ml), 1)
end
