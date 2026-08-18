---@module 'documentation.core.lang.glossary.lua'
--- Lua's keyword glossary — what the page shows when the reader hovers a
--- keyword in a rendered source snippet.
---
--- Data, not code. It exists as its own module rather than as a table inside
--- `core/lang/lua.lua` because it is several times that file's size and has
--- nothing to do with scanning; the backend requires it and passes it on,
--- which keeps the backend readable as the seam it is.
---
--- ## Which Lua
---
--- **5.1 plus the 5.2 extensions LuaJIT provides**, and that is a decision
--- rather than a default: Neovim runs LuaJIT, so linking or describing 5.4
--- would actively mislead — `goto` is available, integer division and the
--- `<close>`/`<const>` attributes are not. Entries for the things that do
--- *not* exist here are still worth carrying (a reader meets them in other
--- people's code), but they say so in `note` rather than being quietly
--- omitted, which would leave the reader with no answer at all.
---
--- ## Why there are no per-keyword anchors
---
--- `reference.url` is one base URL, and `docs/ROADMAP/IDEAS/ReferenceTab.md`
--- explains the rule at length: one link per language that can rot, rather
--- than several hundred that can rot independently. The per-entry anchors
--- that rule permits are deliberately **not** filled in here — the Lua 5.1
--- manual's section anchors were not verified when this was written, and a
--- reference panel full of links that land in the wrong place is the failure
--- this repository already has a `dead-readme-link` check because of. Add
--- them per entry once checked; the renderer already handles their absence.
---
--- The explanation never depends on the link. Every `summary` below stands
--- on its own, offline, inside the artifact.

local M = {}

---Where "read more" points, when the reader wants more than a sentence.
---@type Documentation.Glossary.Reference
M.reference = {
  label = "Lua 5.1 reference manual",
  url = "https://www.lua.org/manual/5.1/manual.html",
}

---How to tell code from not-code, for the page's tokenizer.
---
---A keyword decorated inside a string literal or a comment is a false
---positive: the definition shown would be correct and the context wrong,
---which is worse than not decorating it at all. So the tokenizer skips
---these spans, and the shape is data here rather than a lexer in the page.
---
---**Bounded on purpose.** Long brackets are handled at level zero only
---(`[[ ]]`, not `[==[ ]==]`). A level-N long string therefore ends up
---scanned as ordinary code, which can only ever produce a spurious
---decoration on a keyword inside it — the rarest case of an already rare
---one, and not worth a full Lua lexer in a page that is already 1.5 MB.
---@type Documentation.Glossary.Syntax
M.syntax = {
  line_comment = "--",
  block_comment = { "--[[", "]]" },
  strings = { { '"', '"' }, { "'", "'" }, { "[[", "]]" } },
  escape = "\\",
}

---@type table<string, Documentation.Glossary.Entry>
M.keywords = {
  -- Control flow
  ["if"] = { summary = "Starts a conditional. Needs `then`, closes with `end`." },
  ["then"] = { summary = "Opens the body of an `if` or `elseif`." },
  ["elseif"] = {
    summary = "A further condition, tested only when the ones above it failed.",
    note = "One word, not `else if` — the two-word form would need a second `end`.",
  },
  ["else"] = { summary = "The branch taken when every condition above failed." },
  ["end"] = { summary = "Closes a block: `if`, `for`, `while`, `function`, `do`." },
  ["for"] = {
    summary = "A loop, in one of two forms: numeric (`for i = 1, n`) or generic (`for k, v in pairs(t)`).",
  },
  ["in"] = {
    summary = "Separates the loop variables of a generic `for` from the iterator that feeds them.",
  },
  ["while"] = { summary = "Loops while the condition holds, tested before each pass." },
  ["repeat"] = {
    summary = "Loops until the condition holds, tested *after* each pass — so the body always runs at least once.",
  },
  ["until"] = {
    summary = "Ends a `repeat` block and states its exit condition.",
    note = "The condition can see locals declared inside the body, unlike every other scope in the language.",
  },
  ["do"] = {
    summary = "Opens a block. On its own it makes a scope; after `for`/`while` it opens the loop body.",
  },
  ["break"] = { summary = "Leaves the innermost enclosing loop." },
  ["goto"] = {
    summary = "Jumps to a `::label::` in the same function.",
    note = "Lua 5.2. Available in LuaJIT, so usable in Neovim — unlike most 5.2+ additions.",
  },
  ["return"] = {
    summary = "Returns zero or more values from a function.",
    note = "Must be the last statement in its block; `do return end` is the idiom for an early exit.",
  },

  -- Functions and scope
  ["function"] = { summary = "Defines a function, as a statement or as a value." },
  ["local"] = {
    summary = "Declares a variable in the current scope. Without it, an assignment creates a global.",
  },

  -- Values
  ["nil"] = {
    summary = "The absence of a value. Also the only value besides `false` that is falsy.",
    note = "Storing `nil` in a table removes the key rather than holding it — which is why `#t` and `ipairs` stop at a hole.",
  },
  ["true"] = { summary = "The boolean true." },
  ["false"] = {
    summary = "The boolean false.",
    note = 'With `nil`, one of only two falsy values — `0` and `""` are both true in Lua.',
  },

  -- Operators that are words
  ["and"] = {
    summary = "Logical and, short-circuiting.",
    note = "Returns one of its *operands*, not a boolean: `a and b` is `a` when `a` is falsy, otherwise `b`.",
  },
  ["or"] = {
    summary = "Logical or, short-circuiting.",
    note = "Also returns an operand, which is what makes `x = x or default` the idiomatic default.",
  },
  ["not"] = { summary = "Logical negation. Always yields a boolean, unlike `and`/`or`." },

  -- Not keywords, but the things a reader most often stops at
  ["self"] = {
    summary = "The implicit first parameter a method receives, created by defining it with `:` instead of `.`.",
    note = "Not a keyword — an ordinary parameter name the `:` sugar inserts for you.",
  },
}

return M
