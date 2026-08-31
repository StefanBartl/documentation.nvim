-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/lang_erlang_spec.lua — documentation.core.lang.erlang
--
-- Skips when the erlang parser is not reachable; `DOCMAP_ERLANG_PARSER`
-- points at one without installing it into a runtimepath.
--
-- Erlang is the export list again, and this time it **carries arity**:
-- `-export([add/2]).` publishes `add` at two arguments and says nothing
-- about `add/3`, which is a different function. A set of bare names would
-- publish both whenever either was listed, which is why the set here is
-- keyed by `name/arity` and why a function's arity has to be counted from
-- its clause head to ask the question at all.

return function(H)
  local eq, ok = H.eq, H.ok

  local explicit = os.getenv("DOCMAP_ERLANG_PARSER")
  local ok_add, has_er
  if explicit and explicit ~= "" then
    ok_add, has_er = pcall(vim.treesitter.language.add, "erlang", { path = explicit })
  else
    ok_add, has_er = pcall(vim.treesitter.language.add, "erlang")
  end

  local er = require("documentation.core.lang_registry").get("erlang")
  ok(er ~= nil, "the erlang backend must be registered")

  eq(er.is_source("widget.erl"), true)
  eq(er.is_source("widget.hrl"), true, "a header is a source file")
  eq(er.is_source("rebar.config"), false)
  eq(er.module_tag, false, "`-module(x).` is a declaration, not a doc tag")
  eq(#er.block_comments, 0, "Erlang has no block comment at all")
  eq(er.param_docs, false, "`-spec` names types rather than parameters")

  if not (ok_add and has_er) then
    ok(true, "lang.erlang: erlang parser not installed — skipping the rest")
    return
  end

  local function write(body)
    local file = H.tmpfile(".erl")
    local fw = assert(io.open(file, "w"))
    fw:write(body)
    fw:close()
    return file
  end

  local file = write(table.concat({
    "%% Copyright (c) Somebody.",
    "",
    "%% @doc A widget module that does things.",
    "%%",
    "%% More detail here.",
    "-module(widget).",
    "",
    "-export([add/2, max_count/0]).",
    "",
    '-include("helpers.hrl").',
    '-include_lib("kernel/include/file.hrl").',
    "",
    "-define(MAX, 10).",
    "",
    "%% @doc How many.",
    "-spec max_count() -> integer().",
    "max_count() -> ?MAX.",
    "",
    "%% @doc Adds two numbers.",
    "-spec add(integer(), integer()) -> integer().",
    "add(X, Y) -> X + Y.",
    "",
    "%% @doc Same name, three arguments, not exported.",
    "add(X, Y, Z) -> X + Y + Z.",
    "",
    "%% @doc Not exported.",
    "helper(Z) -> Z.",
    "",
  }, "\n"))

  local header = er.parse_header(file)
  eq(header.module, "widget", "`-module(widget).` names it")
  eq(header.summary, "A widget module that does things.", "`%% @doc` above `-module`")
  ok(header.body:match("More detail"))
  ok(not header.summary:match("Copyright"), "a run with no @doc in it is a note")

  local fns, _, requires, symbols = er.scan_file(file)
  local by = {}
  for _, fn in ipairs(fns) do
    by[fn.signature] = fn
  end

  -- **Arity is part of the identity.** This is the assertion the whole file
  -- is worth having for: `add/2` is exported and `add/3` is not, and a set
  -- of bare names would have published both.
  eq(by["add/2"].internal, false, "`add/2` is in the export list")
  eq(
    by["add/3"].internal,
    true,
    "`add/3` is a different function and is not — no other backend here has "
      .. "arity in a declaration's identity"
  )
  eq(by["max_count/0"].internal, false)
  eq(by["helper/1"].internal, true)

  -- The EDoc sits above the `-spec`, and the definition is a separate node —
  -- Haskell's two-node shape again.
  eq(by["add/2"].summary, "Adds two numbers.")
  eq(by["helper/1"].summary, "Not exported.", "and above the function when there is no spec")

  local mods = {}
  for _, r in ipairs(requires) do
    mods[r.module] = true
  end
  eq(mods["./helpers.hrl"], true, "`-include` names a file beside this one")
  eq(
    mods["kernel/include/file.hrl"],
    true,
    "`-include_lib` names one in another application — external by construction"
  )

  local sym = {}
  for _, s in ipairs(symbols) do
    sym[s.name] = s
  end
  eq(sym["MAX"].kind, "constant", "`-define` is a module-scope constant")

  -- `-compile(export_all).` publishes everything — the third shape of that
  -- after Haskell's missing list and Python's missing `__all__`, and still
  -- widespread in older code.
  local all = write(table.concat({
    "-module(open).",
    "-compile(export_all).",
    "",
    "%% @doc Published by the compile directive.",
    "shown(X) -> X.",
    "",
  }, "\n"))
  eq(er.scan_file(all)[1].internal, false, "`-compile(export_all)` publishes everything")

  local markers = require("documentation.core.markers")
  eq(#markers.scan_source("% TODO: finish this", er), 1)
end
