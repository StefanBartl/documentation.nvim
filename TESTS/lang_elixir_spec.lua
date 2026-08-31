-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/lang_elixir_spec.lua — documentation.core.lang.elixir
--
-- Skips when the elixir parser is not reachable; `DOCMAP_ELIXIR_PARSER`
-- points at one without installing it into a runtimepath.
--
-- Elixir is the first language here whose documentation the *compiler* takes
-- responsibility for: `@doc` is a module attribute, evaluated and stored in
-- the BEAM chunk. Which makes `@doc false` a real third state — public and
-- deliberately undocumented — distinct both from prose and from absence.

return function(H)
  local eq, ok = H.eq, H.ok

  local explicit = os.getenv("DOCMAP_ELIXIR_PARSER")
  local ok_add, has_ex
  if explicit and explicit ~= "" then
    ok_add, has_ex = pcall(vim.treesitter.language.add, "elixir", { path = explicit })
  else
    ok_add, has_ex = pcall(vim.treesitter.language.add, "elixir")
  end

  local ex = require("documentation.core.lang_registry").get("elixir")
  ok(ex ~= nil, "the elixir backend must be registered")

  eq(ex.is_source("widget.ex"), true)
  eq(ex.is_source("mix.exs"), true, "a script is a source file")
  eq(ex.is_source("mix.lock"), false)
  eq(ex.module_tag, false, "`defmodule` is a declaration, not a doc tag")
  eq(#ex.block_comments, 0, "Elixir has no block comment — a heredoc is a string")
  eq(ex.param_docs, false, "ExDoc describes arguments in prose; `@spec` names types")

  if not (ok_add and has_ex) then
    ok(true, "lang.elixir: elixir parser not installed — skipping the rest")
    return
  end

  local function write(body)
    local file = H.tmpfile(".ex")
    local fw = assert(io.open(file, "w"))
    fw:write(body)
    fw:close()
    return file
  end

  local file = write(table.concat({
    "defmodule Acme.Widget do",
    '  @moduledoc """',
    "  A widget that does things.",
    "",
    "  More detail here.",
    '  """',
    "",
    "  alias Acme.Other.Thing",
    "  import Enum",
    "  require Logger",
    "  use GenServer",
    "",
    "  @max_count 10",
    "",
    '  @doc """',
    "  Adds two numbers.",
    '  """',
    "  def add(x, y), do: x + y",
    "",
    "  @doc false",
    "  def hidden_from_docs, do: 1",
    "",
    '  @doc "Guarded."',
    "  def guarded(x) when is_integer(x), do: x",
    "",
    "  defp helper(z), do: z",
    "",
    "  defmodule Inner do",
    "    def nested, do: 2",
    "  end",
    "end",
    "",
  }, "\n"))

  local header = ex.parse_header(file)
  eq(header.module, "Acme.Widget", "`defmodule` names the module, from the language itself")
  eq(header.summary, "A widget that does things.")
  ok(header.body:match("More detail"), "the heredoc is dedented, so the body keeps its shape")

  local fns, _, requires, symbols = ex.scan_file(file)
  local by = {}
  for _, fn in ipairs(fns) do
    by[fn.name] = fn
  end

  -- ---------------------------------------------------------------------
  -- Visibility: a keyword, and an author's statement.
  -- ---------------------------------------------------------------------
  eq(by["Acme.Widget.add"].internal, false, "`def` is public")
  eq(by["Acme.Widget.helper"].internal, true, "`defp` is private to the module")
  eq(
    by["Acme.Widget.hidden_from_docs"].internal,
    true,
    "**`@doc false` is a third state** — public and deliberately undocumented. "
      .. "Reading it as prose would put the word `false` in a summary; reading "
      .. "it as absent would lose what the author said"
  )
  eq(
    by["Acme.Widget.hidden_from_docs"].summary,
    "",
    "and it carries no summary, because there is none to carry"
  )

  -- ---------------------------------------------------------------------
  -- `@doc` documents the *next* definition, so it is carried forward — the
  -- only backend here that reads its documentation before the thing it
  -- documents rather than above it.
  -- ---------------------------------------------------------------------
  eq(by["Acme.Widget.add"].summary, "Adds two numbers.")
  eq(by["Acme.Widget.add"].signature, "Acme.Widget.add(x, y)")
  eq(
    by["Acme.Widget.guarded"].summary,
    "Guarded.",
    "a plain string `@doc` works as well as a heredoc"
  )
  eq(
    by["Acme.Widget.guarded"].signature,
    "Acme.Widget.guarded(x)",
    "and a `when` guard wraps the head without hiding its parameters"
  )
  eq(by["Acme.Widget.Inner.nested"] ~= nil, true, "a nested module's functions are qualified")

  -- ---------------------------------------------------------------------
  -- Four import forms, one edge.
  -- ---------------------------------------------------------------------
  local mods = {}
  for _, r in ipairs(requires) do
    mods[r.module] = true
  end
  eq(mods["Acme.Other.Thing"], true, "alias")
  eq(mods["Enum"], true, "import")
  eq(mods["Logger"], true, "require")
  eq(
    mods["GenServer"],
    true,
    "and `use`, which invokes another module's `__using__` — a distinction the "
      .. "compiler needs and a dependency graph does not"
  )

  local sym = {}
  for _, s in ipairs(symbols) do
    sym[s.name] = s
  end
  eq(sym["Acme.Widget.max_count"].kind, "constant", "a module attribute is a module-scope constant")
  eq(
    sym["Acme.Widget.moduledoc"],
    nil,
    "and `@moduledoc` is read as the module's documentation, not reported as one of its constants"
  )

  local markers = require("documentation.core.markers")
  eq(#markers.scan_source("# TODO: finish this", ex), 1)
end
