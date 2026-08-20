---@module 'documentation.core.tags'
--- The catalogue of annotation tags this plugin recognises — one table, three
--- consumers.
---
--- ## Why a table rather than the `if/elseif` chain it replaces
---
--- `functions.lua`'s doc-block parser dispatched on tag name through fourteen
--- branches, which was fine as a parser and useless as an answer to any
--- question *about* the tags: which ones exist, what each means, where a
--- reader can look one up. Three separate pieces of work wanted exactly that
--- answer and were each costed with their own copy of it —
--- `ROADMAP/IDEAS/ReferenceTab.md`'s tag panel and its lookup layer's third
--- kind, and `IDEAS_IMPLEMENTATION_PLAN.md` §2.1's annotation-adoption panel,
--- which that document rates as the highest-value panel idea in the backlog
--- and gates on this exact refactor. Building it once is cheaper than any of
--- the three estimates assumed in isolation; building it three times is the
--- duplication this repository warns about everywhere else.
---
--- **The parsing stays in `functions.lua`.** What moved here is the
--- catalogue: name, what the tag means, whether it repeats, and where to read
--- more. Handlers need the parser's own accumulators and its Lua-specific
--- `parse_param`/`parse_overload`, and dragging those into a data table would
--- have traded one coupling for a worse one. What the two halves share is the
--- *name list*, and `TESTS/tags_spec.lua` asserts they agree in both
--- directions — a tag catalogued with no handler is a promise the parser does
--- not keep, and a handler for an uncatalogued tag is a feature no reader can
--- discover.
---
--- ## `field` is what makes an adoption count possible without a second table
---
--- A consumer asking "how many functions in this tree carry `@todo`" needs to
--- know that `@todo` lands in `FunctionInfo.todo` and `@param` in `.params`.
--- That mapping is not derivable from the tag name — `param` fills `params`,
--- `return` fills `returns` — so it is either here or hardcoded in every
--- consumer. It is here, and `TESTS/tags_spec.lua` asserts every declared
--- field actually appears on a parsed function, against a fixture that uses
--- every tag. A field name that drifts is otherwise a panel silently
--- reporting zero adoption for a tag the tree uses everywhere.
---
--- ## `origin` is the field that decides the link
---
--- Half of these are LuaCATS/EmmyLua, understood by lua-language-server and
--- documented on its own site. The other half are **this project's own
--- conventions** — `@todo`, `@bug`, `@test`, `@internal` as this plugin reads
--- it — and sending a reader to luals.github.io for one of those would be a
--- link that loads, looks authoritative and does not contain the answer. That
--- is the same rule the stdlib glossary already applies to Neovim's API:
--- `origin` withholds the upstream link rather than pointing it somewhere
--- plausible.
---
--- Anchors were **read out of the published page**, not guessed:
--- `https://luals.github.io/wiki/annotations/` was fetched and its real `id="…"`
--- attributes extracted. Twenty-five exist; every `luals` entry below uses one
--- of them. That is the `dead-readme-link` lesson applied before shipping
--- rather than after — see `ReferenceTab.md` § *Links, and the staleness
--- objection*.

local M = {}

---Where a tag comes from, which is also what decides whether it gets a link.
---
---`"luals"` — LuaCATS/EmmyLua, understood by lua-language-server.
---`"docmap"` — this plugin's own convention; no upstream page describes it.
---@alias Documentation.Tags.Origin "luals"|"docmap"

---One recognised annotation tag.
---@class Documentation.Tags.Entry
---@field name string The tag without its `@`.
---@field origin Documentation.Tags.Origin
---@field repeats boolean Whether more than one occurrence is meaningful. A repeated non-repeating tag is a mistake the parser silently resolves by keeping one, and a reader should know which kind they are looking at.
---@field summary string One sentence, this project's own words, offline. The link is an enhancement — if every URL broke tomorrow this still answers the question.
---@field anchor string? Fragment on the origin's reference page, verified to exist. Absent for `docmap` tags, deliberately.
---@field scope "function"|"module"|"type" Where the tag is written, which is also which parser reads it.
---@field url string? Only on the copies `M.for_page` produces: the resolved reference URL, or absent when this tag's origin publishes none.
---@field field string? For a function-scope tag, the `Documentation.FunctionInfo` key it lands in — the join that lets a consumer ask "how many functions carry this" without a second table mapping tag names to fields. Absent for module- and type-scope tags, whose data does not live on a function.

---The base URL each origin's anchors hang off.
---
---One base per origin rather than one URL per tag, so the surface that can
---rot is a single string checkable by one gate instead of twenty-five
---independently rotting links. An anchor that moves then degrades to landing
---on the right page at the wrong position, which is a much softer failure
---than a 404.
---@type table<Documentation.Tags.Origin, string?>
M.REFERENCE = {
  luals = "https://luals.github.io/wiki/annotations/",
  -- Deliberately none. These are described in this repository's own
  -- `docs/ANNOTATION_TAGS.md`, which a generated page cannot link to
  -- usefully from an arbitrary checkout.
  docmap = nil,
}

---Every tag this plugin reads, in the order a reader meets them.
---
---**Recognised, not merely valid.** LuaCATS has more tags than this; what is
---here is what some part of this pipeline actually does something with, which
---is the only list that can be honest about what the map shows. `@raises`,
---`@stability` and the rest of `ANNOTATION_TAGS.md`'s "not implemented"
---section are absent for that reason and belong here the day they are read.
---@type Documentation.Tags.Entry[]
M.TAGS = {
  {
    name = "module",
    origin = "luals",
    repeats = false,
    scope = "module",
    anchor = "module",
    summary = "The file's dotted identity, and the one tag this plugin treats as not optional — a Lua module's canonical name cannot be recovered from its path in general.",
  },
  {
    name = "meta",
    origin = "luals",
    repeats = false,
    scope = "module",
    anchor = "meta",
    summary = "Marks a definition-only file: types and signatures with no runtime behind them.",
  },
  {
    name = "param",
    origin = "luals",
    repeats = true,
    scope = "function",
    field = "params",
    anchor = "param",
    summary = "One parameter, its type and its description — the only tag with a structural check behind it, since a name that does not match the signature is a documented lie.",
  },
  {
    name = "return",
    origin = "luals",
    repeats = true,
    scope = "function",
    field = "returns",
    anchor = "return",
    summary = "What the function hands back. Rendered, never checked: Lua's returns are positional and unnamed, so there is nothing to compare a claim against.",
  },
  {
    name = "generic",
    origin = "luals",
    repeats = true,
    scope = "function",
    field = "generic",
    anchor = "generic",
    summary = "Type parameters, collected and shown in the rendered signature.",
  },
  {
    name = "overload",
    origin = "luals",
    repeats = true,
    scope = "function",
    field = "overload",
    anchor = "overload",
    summary = "An alternative call shape. Parsed structurally, so a parameter documented only on an overload still counts as documented.",
  },
  {
    name = "deprecated",
    origin = "luals",
    repeats = false,
    scope = "function",
    field = "deprecated",
    anchor = "deprecated",
    summary = "This still works and should not be used. The text after it is the migration hint, which is the half that makes the badge actionable.",
  },
  {
    name = "async",
    origin = "luals",
    repeats = false,
    scope = "function",
    field = "async",
    anchor = "async",
    summary = "The function yields; a badge, not a check.",
  },
  {
    name = "nodiscard",
    origin = "luals",
    repeats = false,
    scope = "function",
    field = "nodiscard",
    anchor = "nodiscard",
    summary = "The return value is the point — discarding it is a bug at the call site.",
  },
  {
    name = "see",
    origin = "luals",
    repeats = true,
    scope = "function",
    field = "see",
    anchor = "see",
    summary = "A cross-reference, comma-separated, and one of the signals that keeps a function from reading as dead code.",
  },
  {
    name = "internal",
    origin = "docmap",
    repeats = false,
    scope = "function",
    field = "internal",
    summary = 'Implementation, not published surface. Sharpens every question of the form "is this used": the parameter check skips it, the diff counts it as a helper, and the API surface panel leaves it out.',
  },
  {
    name = "todo",
    origin = "docmap",
    repeats = true,
    scope = "function",
    field = "todo",
    summary = "Work the author left for later, attached to the function it concerns. Listed in the Notes tab; one entry per occurrence, because a function with two open todos has two.",
  },
  {
    name = "bug",
    origin = "docmap",
    repeats = true,
    scope = "function",
    field = "bug",
    summary = "A defect the author recorded against this function. Counted on the dashboard and gated nowhere — it is the author's claim, not a finding of this tool's.",
  },
  {
    name = "test",
    origin = "docmap",
    repeats = true,
    scope = "function",
    field = "test",
    summary = "Which spec covers this, written by hand. The measured answer comes from the test tree instead; this is the note beside it.",
  },
  {
    name = "since",
    origin = "docmap",
    repeats = false,
    scope = "function",
    field = "since",
    summary = "When this appeared, in the project's own versioning — history, not runtime behaviour.",
  },
  {
    name = "example",
    origin = "docmap",
    repeats = false,
    scope = "function",
    field = "example",
    summary = "The only multi-line tag: every following comment line belongs to it, and the block is parsed so an example that does not compile is a finding.",
  },
  {
    name = "class",
    origin = "luals",
    repeats = false,
    scope = "type",
    anchor = "class",
    summary = "Declares a type, with its fields below it. Read through lua-language-server rather than from the comment, so it needs a `--full` generation.",
  },
  {
    name = "field",
    origin = "luals",
    repeats = true,
    scope = "type",
    anchor = "field",
    summary = "One member of the class above it: name, type, and what it is for.",
  },
  {
    name = "alias",
    origin = "luals",
    repeats = false,
    scope = "type",
    anchor = "alias",
    summary = "A name for a type expression — most usefully for a union of string literals, which is how an enum is spelled in practice.",
  },
  {
    name = "enum",
    origin = "luals",
    repeats = false,
    scope = "type",
    anchor = "enum",
    summary = "Marks a real runtime table as the source of a set of values, so the values and the documentation cannot drift apart.",
  },
  {
    name = "type",
    origin = "luals",
    repeats = false,
    scope = "type",
    anchor = "type",
    summary = "The type of the value on the next line, for a variable rather than a function.",
  },
}

---`name` -> entry, built once.
---@type table<string, Documentation.Tags.Entry>
local by_name = {}
for _, t in ipairs(M.TAGS) do
  by_name[t.name] = t
end

---Look one tag up by name, with or without the leading `@`.
---@param name string
---@return Documentation.Tags.Entry?
function M.get(name)
  if type(name) ~= "string" then
    return nil
  end
  return by_name[(name:gsub("^@", ""))]
end

---Every catalogued tag name, sorted — the list both panels iterate.
---@return string[]
function M.names()
  local out = {}
  for _, t in ipairs(M.TAGS) do
    out[#out + 1] = t.name
  end
  table.sort(out)
  return out
end

---The reference URL for a tag, or `nil` when its origin publishes none.
---
---`nil` rather than a plausible guess: a link that loads and does not contain
---the answer is worse than no link, which is the whole reason `origin`
---exists.
---@param name string
---@return string?
function M.url(name)
  local entry = M.get(name)
  if not entry or not entry.anchor then
    return nil
  end
  local base = M.REFERENCE[entry.origin]
  if not base then
    return nil
  end
  return base .. "#" .. entry.anchor
end

---The catalogue as the page needs it: every entry with its link already
---resolved.
---
---Resolved here rather than in JavaScript because `M.url`'s rule — an
---`origin` with no published reference gets no link, ever — is the one part
---of this module that is a decision rather than data. A second
---implementation of it in the page would be a second place for that decision
---to be got wrong, and it would be got wrong in the direction of linking
---somewhere plausible.
---@return Documentation.Tags.Entry[]
function M.for_page()
  local out = {}
  for i, t in ipairs(M.TAGS) do
    local copy = vim.deepcopy(t)
    copy.url = M.url(t.name)
    out[i] = copy
  end
  return out
end

return M
