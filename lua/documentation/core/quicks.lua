---@module 'documentation.core.quicks'
--- Quicks: the tree's own state, stated in sentences instead of tables.
---
--- Every other Analysis panel answers a question the reader already had.
--- This one answers the question they have *before* they have a question —
--- "how is this repository doing?" — which is the one thing nine tables of
--- rows are collectively bad at. Nothing here is new extraction: every number
--- below is read off fields the scan already produced, which is exactly why
--- this is a hundred lines and not a second pipeline.
---
--- ## Why each verdict carries its own `basis`
---
--- Quicks are, by construction, confident-sounding prose. That is a genuine
--- hazard in this plugin specifically, which everywhere else refuses to state
--- more than it knows: `calls_heuristic`, `docs_heuristic` and `dead_code` are
--- all default-off with paragraphs explaining that a wrong confident answer is
--- worse than an incomplete one. "Only 12% test coverage" written in that same
--- artifact would quietly break the rule those three flags exist to keep.
---
--- So `basis` is a required field, not a courtesy. It says what the number
--- actually measured — `tested` means "this function's bare name appears
--- somewhere under `tests_dir`", not "this function is covered by a test — and
--- `goto` points at the panel holding the rows the number came from. A reader
--- who distrusts a sentence is two clicks from the evidence, which is the only
--- thing that makes stating it in sentences defensible at all.
---
--- ## What is deliberately not here
---
--- **Purity** ("N% of your functions are pure"). Not derivable: nothing in the
--- IR records side effects, and the honest approximations — "returns a value
--- and calls no `vim.*`/`io.*`/`os.*`" — are exactly the kind of confident
--- guess the paragraph above rules out. It is buildable as a real scan-time
--- metric next to `complexity` and `shape`, where the parse tree exists; until
--- someone does that, it is absent rather than estimated.
---
--- **Orphan modules** ("N modules nothing requires"). A library consists of
--- functions and modules with no internal caller *by design* — the same
--- argument `opts.dead_code` makes for staying off by default. On a library
--- tree this would headline a number that is not a problem.
---
--- ## Determinism
---
--- The result is serialised into a committed artifact, and `--check`
--- byte-compares. So selection and ordering are total: sort by weight, then by
--- how far the value sits past its own threshold, then by `id`. No `pairs`
--- order reaches the output, and two runs over an unchanged tree produce
--- identical bytes.

local M = {}

---How many verdicts of each polarity `compute` returns.
M.DEFAULT_LIMIT = 5

---Bound on `quick.evidence`. The list exists so a reader can act on a verdict
---(the page's compare marks take exactly these keys); it is not a second copy
---of the panel, and an unbounded one on a large tree would be.
M.MAX_EVIDENCE = 20

---Cut points, all inclusive on the "good" side.
---
---Chosen to be unremarkable rather than aspirational: a threshold that
---nobody's real tree clears makes every verdict negative, and a page that is
---always scolding gets closed. Override wholesale or per key through
---`opts.quicks.thresholds`.
M.DEFAULT_THRESHOLDS = {
  doc_coverage = { good = 80, bad = 50 },
  test_coverage = { good = 70, bad = 30 },
  module_summary = { good = 90, bad = 60 },
  complexity = { good = 90, bad = 70 },
  examples = { good = 25, bad = 5 },
  docs_mentions = { good = 50, bad = 10 },
  -- Absolute counts, not percentages: "bad at or above".
  avg_fn_lines = { good = 25, bad = 45 },
  duplicates = { good = 0, bad = 1 },
  drift_errors = { good = 0, bad = 1 },
  drift_warnings = { good = 0, bad = 10 },
  deprecated = { good = 0, bad = 1 },
  todos = { good = 0, bad = 15 },
}

---A function is "simple" at or below this cyclomatic complexity. McCabe's own
---original paper proposed 10 as the point to look harder at a routine, which
---is old but is also the number every tool since has anchored on.
M.SIMPLE_COMPLEXITY = 10

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

---@param n integer
---@param total integer
---@return number percent Rounded to one decimal so the artifact is stable.
local function pct(n, total)
  if total <= 0 then
    return 0
  end
  return math.floor((1000 * n / total) + 0.5) / 10
end

---`1` -> "", `2` -> "s".
---@param n number
---@return string
local function s(n)
  return n == 1 and "" or "s"
end

---Walk every function in the tree.
---@param ir Documentation.IR
---@param fn fun(fninfo: Documentation.FunctionInfo, node: Documentation.Node)
local function each_function(ir, fn)
  for _, id in ipairs(ir.order or {}) do
    local node = ir.nodes[id]
    for _, f in ipairs((node and node.functions) or {}) do
      fn(f, node)
    end
  end
end

---The key scheme the rest of this plugin already uses for a function:
---`"<node id>#<name>"`. Shared with the HTML page's `fnKey`, which is what
---lets a verdict's `evidence` be handed straight to the compare marks.
---@param node_id string
---@param fn_name string
---@return string
local function fn_key(node_id, fn_name)
  return node_id .. "#" .. fn_name
end

-- ---------------------------------------------------------------------------
-- Probes
-- ---------------------------------------------------------------------------

---One measurement, before it is judged.
---@class Documentation.Quicks.Probe
---@field id string
---@field weight integer Higher sorts first within a polarity.
---@field value number
---@field unit "percent"|"count"
---@field good_when "high"|"low"
---@field n integer? Numerator, for the headline.
---@field total integer? Denominator, for the headline.
---@field headline_good string
---@field headline_bad string
---@field basis string
---@field tab string Page tab a reader should land on to see the rows.
---@field atool string? Analysis panel within that tab.
---@field evidence string[]? Bounded list of node/function keys behind the number.

---@param list string[]
---@return string[]
local function bounded(list)
  table.sort(list)
  if #list <= M.MAX_EVIDENCE then
    return list
  end
  local out = {}
  for i = 1, M.MAX_EVIDENCE do
    out[i] = list[i]
  end
  return out
end

---Every probe, unjudged. Split from `compute` so the judging rule exists once
---and reads as a rule rather than as twelve near-copies of an `if`.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
---@return Documentation.Quicks.Probe[]
local function probes(ir, findings)
  local out = {}

  -- R4, already aggregated by the module that owns the definition of
  -- "documented" — recomputing the rule here is how two answers to one
  -- question start drifting apart.
  local documented, publishable = require("documentation.core.doccoverage").summary(ir)

  local tested, testable, untested = 0, 0, {}
  local simple, complex_fns, complex_list = 0, 0, {}
  local with_example = 0
  local deprecated = {}
  local todos = 0
  local fn_lines, fn_count = 0, 0
  local long_fns = {}

  each_function(ir, function(f, node)
    fn_count = fn_count + 1

    -- `line_end` is absent on an artifact written before spans existed; a
    -- missing span contributes nothing rather than a bogus zero-line function.
    if f.line_end and f.line and f.line_end >= f.line then
      local len = f.line_end - f.line + 1
      fn_lines = fn_lines + len
      if len > 60 then
        long_fns[#long_fns + 1] = fn_key(node.id, f.name)
      end
    end

    local c = f.complexity or 1
    if c <= M.SIMPLE_COMPLEXITY then
      simple = simple + 1
    else
      complex_fns = complex_fns + 1
      complex_list[#complex_list + 1] = fn_key(node.id, f.name)
    end

    if f.deprecated ~= nil then
      deprecated[#deprecated + 1] = fn_key(node.id, f.name)
    end
    todos = todos + #(f.todo or {}) + #(f.bug or {})

    -- Published surface only, matching `doccoverage`'s own scope: an
    -- `@internal` helper's test and example bar is the author's business, and
    -- folding it in answers a question nobody asked.
    if not f.internal then
      testable = testable + 1
      if f.tested then
        tested = tested + 1
      else
        untested[#untested + 1] = fn_key(node.id, f.name)
      end
      if f.example and f.example ~= "" then
        with_example = with_example + 1
      end
    end
  end)

  if publishable > 0 then
    out[#out + 1] = {
      id = "doc-coverage",
      weight = 90,
      value = pct(documented, publishable),
      unit = "percent",
      good_when = "high",
      n = documented,
      total = publishable,
      headline_good = "Your published API is well documented",
      headline_bad = "Most of your published API is undocumented",
      basis = "A function counts as documented when it has a summary and every "
        .. "parameter is annotated correctly. `@internal` functions are excluded.",
      tab = "analysis",
      atool = "doc",
    }

    out[#out + 1] = {
      id = "test-coverage",
      weight = 85,
      value = pct(tested, testable),
      unit = "percent",
      good_when = "high",
      n = tested,
      total = testable,
      headline_good = "Most of your published API is named in a spec",
      headline_bad = "Most of your published API is never named in a spec",
      basis = "Auto-derived and coarse: a function counts as tested when its bare "
        .. "name appears somewhere under `tests_dir`. That means 'not found by name', "
        .. "not 'definitely untested' — and a name matched there was not necessarily "
        .. "executed.",
      tab = "analysis",
      atool = "test",
      evidence = bounded(untested),
    }

    out[#out + 1] = {
      id = "examples",
      weight = 40,
      value = pct(with_example, testable),
      unit = "percent",
      good_when = "high",
      n = with_example,
      total = testable,
      headline_good = "A good share of your published API carries a usage example",
      headline_bad = "Almost nothing in your published API shows how to call it",
      basis = "Counts `@example` blocks on non-`@internal` functions.",
      tab = "index",
    }
  end

  if fn_count > 0 then
    out[#out + 1] = {
      id = "complexity",
      weight = 70,
      value = pct(simple, fn_count),
      unit = "percent",
      good_when = "high",
      n = simple,
      total = fn_count,
      headline_good = ("Nearly every function stays under complexity %d"):format(
        M.SIMPLE_COMPLEXITY
      ),
      headline_bad = ("A lot of functions sit above complexity %d"):format(M.SIMPLE_COMPLEXITY),
      basis = (
        "Cyclomatic complexity (McCabe), counted over each function's own "
        .. "subtree including nested closures. %d function%s above the line."
      ):format(complex_fns, s(complex_fns)),
      tab = "analysis",
      atool = "complexity",
      evidence = bounded(complex_list),
    }

    out[#out + 1] = {
      id = "avg-fn-lines",
      weight = 35,
      value = math.floor((10 * fn_lines / fn_count) + 0.5) / 10,
      unit = "count",
      good_when = "low",
      headline_good = "Your functions are short on average",
      headline_bad = "Your functions run long on average",
      basis = (
        "Mean source span (`line` to `line_end`) across %d function%s. "
        .. "A long mean is a smell, not a defect — a table-driven dispatcher is "
        .. "legitimately long."
      ):format(fn_count, s(fn_count)),
      tab = "index",
      evidence = bounded(long_fns),
    }
  end

  -- Module-level annotation: the "are my files described at all" question,
  -- which is separate from whether their *functions* are. Namespaces (a
  -- directory with no `init.lua`) are excluded — there is no file there to
  -- have written a header in.
  local described, describable = 0, 0
  for _, id in ipairs(ir.order or {}) do
    local node = ir.nodes[id]
    if node and node.kind ~= "namespace" then
      describable = describable + 1
      if node.summary and node.summary ~= "" then
        described = described + 1
      end
    end
  end
  if describable > 0 then
    out[#out + 1] = {
      id = "module-summary",
      weight = 80,
      value = pct(described, describable),
      unit = "percent",
      good_when = "high",
      n = described,
      total = describable,
      headline_good = "Nearly every file opens with a description",
      headline_bad = "Many files have no description at the top",
      basis = "Counts a non-empty summary in the file's leading doc-comment block. "
        .. "Namespace directories are excluded — they have no file to hold one.",
      tab = "tree",
    }
  end

  -- Prose corpus, only when there is one. On a tree with no `.md` files this
  -- is not a bad score, it is a question that does not apply.
  local docs = ir.docs
  if docs and docs.files and #docs.files > 0 and describable > 0 then
    local mentioned = 0
    local refs = docs.refs or {}
    for _, id in ipairs(ir.order or {}) do
      local node = ir.nodes[id]
      if node and node.kind ~= "namespace" and refs[id] and #refs[id] > 0 then
        mentioned = mentioned + 1
      end
    end
    out[#out + 1] = {
      id = "docs-mentions",
      weight = 30,
      value = pct(mentioned, describable),
      unit = "percent",
      good_when = "high",
      n = mentioned,
      total = describable,
      headline_good = "Your prose docs actually reach most of the tree",
      headline_bad = "Your prose docs mention only a fraction of the tree",
      basis = (
        "Counts modules referenced from a code span in one of the %d "
        .. "scanned `.md` file%s."
      ):format(#docs.files, s(#docs.files)),
      tab = "analysis",
      atool = "docs",
    }
  end

  local dups = ir.duplicates
  if dups and dups.groups then
    out[#out + 1] = {
      id = "duplicates",
      weight = 60,
      value = #dups.groups,
      unit = "count",
      good_when = "low",
      headline_good = "No two functions share a structure",
      headline_bad = "Several functions are structural copies of each other",
      basis = (
        "Groups functions by a hash of their parse-tree node types, so a "
        .. "renamed copy still matches. %d function%s across those groups. Sharing "
        .. "a shape is not automatically wrong — two folds over the same shape are "
        .. "legitimate."
      ):format(dups.functions or 0, s(dups.functions or 0)),
      tab = "analysis",
      atool = "duplicates",
    }
  end

  local errors, warnings = 0, 0
  for _, f in ipairs(findings or {}) do
    if f.severity == "error" then
      errors = errors + 1
    elseif f.severity == "warn" then
      warnings = warnings + 1
    end
  end
  out[#out + 1] = {
    id = "drift-errors",
    weight = 100,
    value = errors,
    unit = "count",
    good_when = "low",
    headline_good = "The map is in sync with the tree",
    headline_bad = "The map has drifted from the tree",
    basis = "Error-severity findings from the drift checks — the same set "
      .. "`:DocMap check` fails a pre-commit hook on.",
    tab = "notes",
  }
  out[#out + 1] = {
    id = "drift-warnings",
    weight = 50,
    value = warnings,
    unit = "count",
    good_when = "low",
    headline_good = "Nothing in the tree raised a warning",
    headline_bad = "The drift checks raised a pile of warnings",
    basis = "Warn-severity findings. These never fail `:DocMap check`.",
    tab = "notes",
  }

  if #deprecated > 0 then
    out[#out + 1] = {
      id = "deprecated",
      weight = 45,
      value = #deprecated,
      unit = "count",
      good_when = "low",
      headline_good = "Nothing is left marked deprecated",
      headline_bad = "Deprecated functions are still in the tree",
      basis = "Counts functions carrying `@deprecated`. Whether that is overdue "
        .. "depends on a deprecation window this map knows nothing about.",
      tab = "index",
      evidence = bounded(deprecated),
    }
  end

  if todos > 0 then
    out[#out + 1] = {
      id = "todos",
      weight = 25,
      value = todos,
      unit = "count",
      good_when = "low",
      headline_good = "No open `@todo` or `@bug` annotations",
      headline_bad = "There is a backlog of `@todo`/`@bug` annotations",
      basis = "Counts `@todo` and `@bug` entries on functions. Written-down work "
        .. "is better than undocumented work — a high number here is a reading, "
        .. "not an accusation.",
      tab = "notes",
    }
  end

  return out
end

-- ---------------------------------------------------------------------------
-- Judging
-- ---------------------------------------------------------------------------

---Turn one probe into a verdict, or `nil` when it lands between the two cut
---points — the "unremarkable" band, which is most of a healthy tree and has
---nothing worth a sentence.
---@param p Documentation.Quicks.Probe
---@param th table
---@return Documentation.Quick?
local function judge(p, th)
  local t = th[(p.id:gsub("%-", "_"))]
  if not t then
    return nil
  end

  local polarity, distance
  if p.good_when == "high" then
    if p.value >= t.good then
      polarity, distance = "good", p.value - t.good
    elseif p.value < t.bad then
      polarity, distance = "bad", t.bad - p.value
    end
  else
    if p.value <= t.good then
      polarity, distance = "good", t.good - p.value
    elseif p.value >= t.bad then
      polarity, distance = "bad", p.value - t.bad
    end
  end

  if not polarity then
    return nil
  end

  -- `%s`/`tostring` on a number is host-Lua-specific: LuaJIT renders an
  -- integral float as `100`, PUC Lua 5.3+ as `100.0`. That leaked into the
  -- byte-compared artifact as `"detail":"100.0% — 85 of 85"`, which is the
  -- same defect `core/json.lua` fixes for *values* — this is the second
  -- place it surfaces, because these details are pre-formatted strings
  -- rather than numbers the encoder ever sees. `%.14g` renders an integral
  -- value without a fractional part and a real one with it, matching what
  -- LuaJIT's `tostring` produced here.
  ---@param n number
  ---@return string
  local function numstr(n)
    return (("%.14g"):format(n))
  end

  local detail
  if p.unit == "percent" and p.total then
    detail = ("%s%% — %d of %d"):format(numstr(p.value), p.n, p.total)
  elseif p.unit == "percent" then
    detail = ("%s%%"):format(numstr(p.value))
  else
    detail = numstr(p.value)
  end

  ---@type Documentation.Quick
  return {
    id = p.id,
    polarity = polarity,
    value = p.value,
    unit = p.unit,
    detail = detail,
    headline = polarity == "good" and p.headline_good or p.headline_bad,
    basis = p.basis,
    weight = p.weight,
    distance = distance,
    tab = p.tab,
    atool = p.atool,
    evidence = (polarity == "bad" and p.evidence and #p.evidence > 0) and p.evidence or nil,
  }
end

---@param a Documentation.Quick
---@param b Documentation.Quick
---@return boolean
local function rank(a, b)
  if a.weight ~= b.weight then
    return a.weight > b.weight
  end
  if a.distance ~= b.distance then
    return a.distance > b.distance
  end
  return a.id < b.id
end

---Verdicts over `ir`, split by polarity and capped.
---
---Pure: an IR and a finding list in, a table out. No filesystem, no git, no
---editor — the same contract `coverage`, `doccoverage` and `duplicates` keep,
---and the reason this can be called from the renderer, the CLI and a spec
---alike.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]?
---@param opts Documentation.Opts?
---@return Documentation.Quicks.Result
function M.compute(ir, findings, opts)
  local qopts = (opts and opts.quicks) or {}
  local th = vim.tbl_deep_extend("force", {}, M.DEFAULT_THRESHOLDS, qopts.thresholds or {})
  local limit_good = qopts.limit_good or M.DEFAULT_LIMIT
  local limit_bad = qopts.limit_bad or M.DEFAULT_LIMIT

  local good, bad = {}, {}
  for _, p in ipairs(probes(ir, findings or {})) do
    local q = judge(p, th)
    if q then
      local bucket = q.polarity == "good" and good or bad
      bucket[#bucket + 1] = q
    end
  end

  table.sort(good, rank)
  table.sort(bad, rank)

  ---@param list Documentation.Quick[]
  ---@param n integer
  ---@return Documentation.Quick[]
  local function take(list, n)
    local out = {}
    for i = 1, math.min(n, #list) do
      out[i] = list[i]
    end
    return out
  end

  return {
    good = take(good, limit_good),
    bad = take(bad, limit_bad),
    -- Counts *before* the cap, so the page can say "3 of 7 shown" rather than
    -- implying the capped list is everything there was.
    total_good = #good,
    total_bad = #bad,
  }
end

return M
