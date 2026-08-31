-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/lang_haskell_spec.lua — documentation.core.lang.haskell
--
-- Skips when the haskell parser is not reachable; `DOCMAP_HASKELL_PARSER`
-- points at one without installing it into a runtimepath.
--
-- Haskell is the first of twenty backends whose **visibility lives in the
-- module header** rather than on the declaration: `module Foo (a, b) where`
-- states the published surface once, at the top, and a definition looks
-- identical whether or not it is exported.
--
-- The two fixtures below exist for the pair of readings that would invert a
-- module: no export list publishes *everything*, and an empty one publishes
-- nothing.

return function(H)
  local eq, ok = H.eq, H.ok

  local explicit = os.getenv("DOCMAP_HASKELL_PARSER")
  local ok_add, has_hs
  if explicit and explicit ~= "" then
    ok_add, has_hs = pcall(vim.treesitter.language.add, "haskell", { path = explicit })
  else
    ok_add, has_hs = pcall(vim.treesitter.language.add, "haskell")
  end

  local hs = require("documentation.core.lang_registry").get("haskell")
  ok(hs ~= nil, "the haskell backend must be registered")

  eq(hs.is_source("Widget.hs"), true)
  eq(hs.is_source("stack.yaml"), false, "a build file is not a source file")
  eq(hs.module_tag, false, "a module header is a declaration, not a doc tag")
  eq(
    hs.param_docs,
    false,
    "a Haskell type signature has no parameter names in it — there is nothing "
      .. "for a per-parameter convention to match against"
  )
  eq(hs.line_comments[1], "--")

  if not (ok_add and has_hs) then
    ok(true, "lang.haskell: haskell parser not installed — skipping the rest")
    return
  end

  local function write(body)
    local file = H.tmpfile(".hs")
    local fw = assert(io.open(file, "w"))
    fw:write(body)
    fw:close()
    return file
  end

  local file = write(table.concat({
    "-- Copyright (c) Somebody.",
    "",
    "-- | A widget module that does things.",
    "--",
    "-- More detail here.",
    "module Acme.Widget",
    "  ( Widget(..)",
    "  , add",
    "  , maxCount",
    "  ) where",
    "",
    "import Data.List (sort)",
    "import qualified Data.Map as M",
    "",
    "-- | How many.",
    "maxCount :: Int",
    "maxCount = 10",
    "",
    "-- | A widget.",
    "data Widget = Widget",
    "  { name :: String",
    "  }",
    "",
    "-- | Adds two numbers.",
    "add :: Int -> Int -> Int",
    "add x y = x + y",
    "",
    "-- | Not exported.",
    "helper :: Int -> Int",
    "helper z = z",
    "",
  }, "\n"))

  -- ---------------------------------------------------------------------
  -- The module names itself, and its Haddock documents the module rather
  -- than standing in for a first declaration — the closest thing to a real
  -- file-level doc comment in any of the twenty.
  -- ---------------------------------------------------------------------
  local header = hs.parse_header(file)
  eq(
    header.module,
    "Acme.Widget",
    "the keyword and the name are both `module` nodes here, and the keyword "
      .. "comes first — taking the first match named every file `module`"
  )
  eq(header.summary, "A widget module that does things.")
  ok(header.body:match("More detail"))
  ok(not header.summary:match("Copyright"), "`--` is a comment, `-- |` is a haddock")

  local fns, _, requires, symbols = hs.scan_file(file)
  local by = {}
  for _, fn in ipairs(fns) do
    by[fn.name] = fn
  end

  -- ---------------------------------------------------------------------
  -- Visibility from the export list.
  -- ---------------------------------------------------------------------
  eq(by["add"].internal, false, "named in the export list")
  eq(
    by["helper"].internal,
    true,
    "absent from it — and the definition looks identical either way, which is "
      .. "what makes this shape different from every other backend's"
  )

  -- The doc block sits above the *signature*, and the definition is a
  -- separate node — the only backend where the documented thing and the
  -- defined thing are two nodes.
  eq(
    by["add"].summary,
    "Adds two numbers.",
    "the haddock above `add :: …` documents `add x y = …`"
  )
  eq(by["add"].signature, "add(x, y)")

  local mods = {}
  for _, r in ipairs(requires) do
    mods[r.module] = true
  end
  eq(mods["Data.List"], true)
  eq(mods["Data.Map"], true, "a qualified import names the same module")

  local sym = {}
  for _, s in ipairs(symbols) do
    sym[s.name] = s
  end
  eq(sym["maxCount"].kind, "constant", "a bind with no patterns is a value, not a function")
  eq(sym["maxCount"].summary, "How many.")
  eq(sym["Widget"].summary, "A widget.")

  -- ---------------------------------------------------------------------
  -- **The two readings that would invert a module.** No export list
  -- publishes everything; an empty one publishes nothing. Getting the first
  -- backwards would report a whole module as private — the same class of
  -- inversion C#'s interface default was.
  -- ---------------------------------------------------------------------
  local everything = write(table.concat({
    "module Acme.Open where",
    "",
    "-- | Exported because there is no list.",
    "visible :: Int",
    "visible = 1",
    "",
  }, "\n"))
  local efns, _, _, esym = hs.scan_file(everything)
  local _ = efns
  eq(esym[1].name, "visible")
  eq(
    hs.parse_header(everything).module,
    "Acme.Open",
    "a module with no export list still names itself"
  )

  local nothing = write(table.concat({
    "module Acme.Closed () where",
    "",
    "-- | Exported by nothing.",
    "hidden :: Int -> Int",
    "hidden z = z",
    "",
  }, "\n"))
  local nfns = hs.scan_file(nothing)
  eq(nfns[1].internal, true, "an empty export list publishes nothing")

  local open = write(table.concat({
    "module Acme.Open2 where",
    "",
    "-- | Exported because there is no list.",
    "shown :: Int -> Int",
    "shown z = z",
    "",
  }, "\n"))
  eq(
    hs.scan_file(open)[1].internal,
    false,
    "**no list is the opposite of an empty list** — it publishes every " .. "top-level name"
  )

  local markers = require("documentation.core.markers")
  eq(#markers.scan_source("-- TODO: finish this", hs), 1)
end
