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
--- ## The per-entry anchors, and how they were checked
---
--- `reference.url` is one base URL, and `docs/ROADMAP/IDEAS/ReferenceTab.md`
--- explains the rule: one link per language that can rot, rather than
--- several hundred that can rot independently. The per-entry anchors that
--- rule permits were left empty until 2026-08-20, for a stated reason — the
--- 5.1 manual's anchors had not been verified, and a reference panel full of
--- links landing in the wrong place is the failure this repository already
--- has a `dead-readme-link` check because of.
---
--- **They are filled now, and every one was read out of the manual rather
--- than guessed.** The published 5.1 manual was fetched, its 397 `<a name>`
--- anchors extracted, and each entry matched against that set:
---
---   * **35 library functions** take `#pdf-<name>`, which is the manual's own
---     convention and was confirmed present for each.
---   * **22 keywords** take a section anchor, and the section was located by
---     searching the manual text for the sentence that documents the word —
---     not by reading the table of contents and inferring. That is how `do`
---     and `end` ended up at 2.4.2 (Blocks) rather than beside `if` at 2.4.4,
---     and how `self` ended up at 2.5.9 with function definitions.
---   * **`goto` gets none, deliberately.** It is not in 5.1 at all — which is
---     what its own `note` already says, and a link would have contradicted
---     the entry beside it.
---   * **The 18 `vim.*` entries get none**, for the reason the renderer
---     already encodes: a Neovim name is not in the Lua manual, and the page
---     does not offer the link for an entry that carries `origin`.
---
--- Re-checking is a fetch and a set comparison, not a re-reading; the recipe
--- above is the whole method.
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
  -- `s:gsub(...)` is `string.gsub(s, ...)`, and it is how Lua is actually
  -- written: measured over this repository's own rendered snippets,
  -- **1004 colon calls against 6 dotted ones** for the same eleven
  -- functions. Keyed by receiver so the knowledge stays in the language
  -- file — the page's tokenizer only follows what a glossary declares, and
  -- a language whose methods are not one namespace declares nothing here.
  method_namespace = "string",
}

---@type table<string, Documentation.Glossary.Entry>
M.keywords = {
  -- Control flow
  ["if"] = { anchor = "#2.4.4", summary = "Starts a conditional. Needs `then`, closes with `end`." },
  ["then"] = { anchor = "#2.4.4", summary = "Opens the body of an `if` or `elseif`." },
  ["elseif"] = {
    anchor = "#2.4.4",
    summary = "A further condition, tested only when the ones above it failed.",
    note = "One word, not `else if` — the two-word form would need a second `end`.",
  },
  ["else"] = { anchor = "#2.4.4", summary = "The branch taken when every condition above failed." },
  ["end"] = {
    anchor = "#2.4.2",
    summary = "Closes a block: `if`, `for`, `while`, `function`, `do`.",
  },
  ["for"] = {
    anchor = "#2.4.5",
    summary = "A loop, in one of two forms: numeric (`for i = 1, n`) or generic (`for k, v in pairs(t)`).",
  },
  ["in"] = {
    anchor = "#2.4.5",
    summary = "Separates the loop variables of a generic `for` from the iterator that feeds them.",
  },
  ["while"] = {
    anchor = "#2.4.4",
    summary = "Loops while the condition holds, tested before each pass.",
  },
  ["repeat"] = {
    anchor = "#2.4.4",
    summary = "Loops until the condition holds, tested *after* each pass — so the body always runs at least once.",
  },
  ["until"] = {
    anchor = "#2.4.4",
    summary = "Ends a `repeat` block and states its exit condition.",
    note = "The condition can see locals declared inside the body, unlike every other scope in the language.",
  },
  ["do"] = {
    anchor = "#2.4.2",
    summary = "Opens a block. On its own it makes a scope; after `for`/`while` it opens the loop body.",
  },
  ["break"] = { anchor = "#2.4.4", summary = "Leaves the innermost enclosing loop." },
  ["goto"] = {
    summary = "Jumps to a `::label::` in the same function.",
    note = "Lua 5.2. Available in LuaJIT, so usable in Neovim — unlike most 5.2+ additions.",
  },
  ["return"] = {
    anchor = "#2.4.4",
    summary = "Returns zero or more values from a function.",
    note = "Must be the last statement in its block; `do return end` is the idiom for an early exit.",
  },

  -- Functions and scope
  ["function"] = {
    anchor = "#2.5.9",
    summary = "Defines a function, as a statement or as a value.",
  },
  ["local"] = {
    anchor = "#2.4.7",
    summary = "Declares a variable in the current scope. Without it, an assignment creates a global.",
  },

  -- Values
  ["nil"] = {
    anchor = "#2.2",
    summary = "The absence of a value. Also the only value besides `false` that is falsy.",
    note = "Storing `nil` in a table removes the key rather than holding it — which is why `#t` and `ipairs` stop at a hole.",
  },
  ["true"] = { anchor = "#2.2", summary = "The boolean true." },
  ["false"] = {
    anchor = "#2.2",
    summary = "The boolean false.",
    note = 'With `nil`, one of only two falsy values — `0` and `""` are both true in Lua.',
  },

  -- Operators that are words
  ["and"] = {
    anchor = "#2.5.3",
    summary = "Logical and, short-circuiting.",
    note = "Returns one of its *operands*, not a boolean: `a and b` is `a` when `a` is falsy, otherwise `b`.",
  },
  ["or"] = {
    anchor = "#2.5.3",
    summary = "Logical or, short-circuiting.",
    note = "Also returns an operand, which is what makes `x = x or default` the idiomatic default.",
  },
  ["not"] = {
    anchor = "#2.5.3",
    summary = "Logical negation. Always yields a boolean, unlike `and`/`or`.",
  },

  -- Not keywords, but the things a reader most often stops at
  ["self"] = {
    anchor = "#2.5.9",
    summary = "The implicit first parameter a method receives, created by defining it with `:` instead of `.`.",
    note = "Not a keyword — an ordinary parameter name the `:` sugar inserts for you.",
  },
}

---Standard-library names, and the Neovim ones that sit beside them.
---
---**Chosen by measurement, not by completeness.** Counted across this
---repository before it was written: `ipairs` 405, `require` 328, `type` 133,
---`table.sort` 79, `table.concat` 76, `pcall` 68, `pairs` 64, `tostring` 55,
---`vim.trim` 40, `vim.treesitter.get_node_text` 28. A transcription of the
---whole 5.1 manual would be mostly entries nobody hovers, and every one of
---them a line to keep true.
---
---`docs/ROADMAP/IDEAS/IDEAS.md`'s note that "`calls_external` already knows
---which ones a tree actually uses" turned out not to hold: that field tracks
---*required modules*, and `table.concat` is a global, not a require. The
---counts above came from reading the source instead.
---
---## Why `vim.*` is here, and marked
---
---It is not Lua, and this file is Lua's glossary. It is also 40 % of what a
---reader of this ecosystem's code actually points at, and a glossary that
---refused to explain `vim.trim` on layering grounds would be correct and
---useless.
---
---The resolution is `origin`: those entries say **Neovim** on the card, and
---the renderer withholds the Lua manual link from them — sending a reader to
---`lua.org` for `vim.split` would be a link that looks right and answers
---nothing. The layering stays visible instead of being either conflated or
---obeyed into uselessness. A host-API glossary of its own is the real
---answer if a second host ever appears; one table with an honest label is
---the right size for one host.
---@type table<string, Documentation.Glossary.Entry>
M.stdlib = {
  -- Base — the most-used names in the language, by a wide margin.
  ["ipairs"] = {
    anchor = "#pdf-ipairs",
    summary = "Iterates a sequence 1, 2, 3… and stops at the first missing index.",
    note = "Stops at a hole, which is why `nil` in the middle of an array-like table silently truncates every loop over it.",
  },
  ["pairs"] = {
    anchor = "#pdf-pairs",
    summary = "Iterates every key of a table, in an unspecified order.",
    note = "The order can differ between runs of the same program — anything that has to be deterministic sorts the keys first.",
  },
  ["require"] = {
    anchor = "#pdf-require",
    summary = "Loads a module once and returns what it returned, from cache on every later call.",
    note = "Cached by module name: a second `require` does not re-run the file, which is why editing a loaded module needs a restart or an explicit cache eviction.",
  },
  ["pcall"] = {
    anchor = "#pdf-pcall",
    summary = "Calls a function and catches its error, returning `ok, result-or-error` instead of propagating.",
  },
  ["xpcall"] = {
    anchor = "#pdf-xpcall",
    summary = "`pcall` with a handler that runs before the stack unwinds, so it can capture a traceback.",
  },
  ["type"] = {
    anchor = "#pdf-type",
    summary = 'The type of a value as a string: "nil", "boolean", "number", "string", "table", "function", "thread", "userdata".',
  },
  ["tostring"] = {
    anchor = "#pdf-tostring",
    summary = "A value as a string, honouring a `__tostring` metamethod.",
  },
  ["tonumber"] = {
    anchor = "#pdf-tonumber",
    summary = "A string as a number, or `nil` when it is not one. Takes an optional base.",
  },
  ["select"] = {
    anchor = "#pdf-select",
    summary = "`select('#', ...)` counts varargs; `select(n, ...)` returns them from the nth on.",
    note = "The counting form is the only reliable way to see trailing `nil`s in `...`, which `#` and `ipairs` both hide.",
  },
  ["setmetatable"] = {
    anchor = "#pdf-setmetatable",
    summary = "Attaches a metatable, giving a table behaviour for indexing, calling, comparison and more.",
  },
  ["getmetatable"] = {
    anchor = "#pdf-getmetatable",
    summary = "The value's metatable, or what its `__metatable` field chose to expose instead.",
  },
  ["rawget"] = {
    anchor = "#pdf-rawget",
    summary = "Reads a table field without consulting `__index`.",
  },
  ["rawset"] = {
    anchor = "#pdf-rawset",
    summary = "Writes a table field without consulting `__newindex`.",
  },
  ["next"] = {
    anchor = "#pdf-next",
    summary = "One step of `pairs`. `next(t) == nil` is the idiomatic test for an empty table.",
  },
  ["error"] = {
    anchor = "#pdf-error",
    summary = "Raises an error. A level of 0 omits position information, 1 blames the caller, 2 the caller's caller.",
  },
  ["assert"] = {
    anchor = "#pdf-assert",
    summary = "Returns its arguments when the first is truthy, raises the second as an error otherwise.",
  },
  ["unpack"] = {
    anchor = "#pdf-unpack",
    summary = "A table's array part as multiple return values.",
    note = "`unpack` in 5.1/LuaJIT, `table.unpack` from 5.2 — this is the most common source of a 5.1-vs-5.4 portability break.",
  },
  ["print"] = {
    anchor = "#pdf-print",
    summary = "Writes its arguments to stdout, tab-separated. Rarely what you want in a plugin — see `vim.notify`.",
  },

  -- table
  ["table.concat"] = {
    anchor = "#pdf-table.concat",
    summary = "Joins a table's array part into a string with an optional separator.",
    note = "The idiomatic way to build a long string: repeated `..` allocates a new string every time, this allocates once.",
  },
  ["table.sort"] = {
    anchor = "#pdf-table.sort",
    summary = "Sorts a table's array part in place, with an optional comparator.",
    note = 'The comparator must be a strict ordering — returning true for equal elements raises "invalid order function" rather than sorting oddly.',
  },
  ["table.insert"] = {
    anchor = "#pdf-table.insert",
    summary = "Appends a value, or inserts it at a position and shifts the rest up.",
  },
  ["table.remove"] = {
    anchor = "#pdf-table.remove",
    summary = "Removes and returns the last element, or the one at a position, shifting the rest down.",
  },

  -- string
  ["string.format"] = {
    anchor = "#pdf-string.format",
    summary = "C-style formatting: `%s`, `%d`, `%q` (a Lua-readable quoted string), `%.2f`.",
  },
  ["string.gsub"] = {
    anchor = "#pdf-string.gsub",
    summary = "Replaces every match of a pattern, returning the new string and the number of replacements.",
    note = "Returns *two* values, which is why `x = (s:gsub(...))` needs its parentheses in a multiple-assignment or argument position.",
  },
  ["string.gmatch"] = {
    anchor = "#pdf-string.gmatch",
    summary = "Iterates every match of a pattern — the loop form of `string.match`.",
  },
  ["string.match"] = {
    anchor = "#pdf-string.match",
    summary = "The first match of a pattern, or its captures when it has any.",
  },
  ["string.find"] = {
    anchor = "#pdf-string.find",
    summary = "Where a pattern matches: start and end indices, plus captures. `true` as the fourth argument makes it a plain-text search.",
  },
  ["string.sub"] = {
    anchor = "#pdf-string.sub",
    summary = "A substring by index. Negative indices count from the end.",
  },
  ["string.rep"] = {
    anchor = "#pdf-string.rep",
    summary = "A string repeated n times, with an optional separator.",
  },

  -- math, os, io — the handful this tree actually reaches for
  ["math.min"] = { anchor = "#pdf-math.min", summary = "The smallest of its arguments." },
  ["math.max"] = { anchor = "#pdf-math.max", summary = "The largest of its arguments." },
  ["math.floor"] = {
    anchor = "#pdf-math.floor",
    summary = "Rounds toward negative infinity. The usual way to get an integer out of a division in 5.1.",
  },
  ["os.time"] = {
    anchor = "#pdf-os.time",
    summary = "Seconds since the epoch, or the time a table of date fields describes.",
  },
  ["os.date"] = {
    anchor = "#pdf-os.date",
    summary = "A formatted date string. A leading `!` in the format means UTC.",
  },
  ["io.open"] = {
    anchor = "#pdf-io.open",
    summary = "Opens a file, returning a handle or `nil` plus a message.",
    note = "Never raises — the `nil, err` return is the whole error path, so an unchecked call fails later and elsewhere.",
  },

  -- Neovim. Not Lua, marked as such, and here because it is what a reader of
  -- this ecosystem's code actually points at.
  ["vim.trim"] = { summary = "A string without leading or trailing whitespace.", origin = "Neovim" },
  ["vim.split"] = {
    summary = "Splits a string. `{ plain = true }` treats the separator literally rather than as a pattern.",
    note = "Without `plain`, a separator like `.` is a Lua pattern and matches every character.",
    origin = "Neovim",
  },
  ["vim.cmd"] = { summary = "Runs an Ex command.", origin = "Neovim" },
  ["vim.notify"] = {
    summary = "Reports a message at a log level, through whatever handler the user configured.",
    origin = "Neovim",
  },
  ["vim.schedule"] = {
    summary = "Defers a function to the main loop, where the full API is callable.",
    note = "The way out of a fast-event context, where most of `vim.api` raises.",
    origin = "Neovim",
  },
  ["vim.system"] = {
    summary = "Runs a process. Asynchronous with a callback, synchronous with `:wait()`.",
    origin = "Neovim",
  },
  ["vim.list_extend"] = {
    summary = "Appends one list's items onto another, in place.",
    origin = "Neovim",
  },
  ["vim.tbl_map"] = {
    summary = "A new table with a function applied to every value.",
    origin = "Neovim",
  },
  ["vim.tbl_contains"] = { summary = "Whether a list holds a value.", origin = "Neovim" },
  ["vim.tbl_deep_extend"] = {
    summary = "Merges tables recursively. The first argument decides collisions: 'force', 'keep' or 'error'.",
    origin = "Neovim",
  },
  ["vim.json.encode"] = {
    summary = "A Lua value as JSON.",
    note = "Key order is unspecified — anything that must be byte-stable needs its own encoder, which is why `core/json.lua` exists.",
    origin = "Neovim",
  },
  ["vim.json.decode"] = {
    summary = "JSON as a Lua value.",
    note = "`{ luanil = { object = true, array = true } }` drops nulls instead of yielding `vim.NIL`, which is truthy and therefore very easy to mishandle.",
    origin = "Neovim",
  },
  ["vim.fs.dir"] = { summary = "Iterates a directory, yielding name and type.", origin = "Neovim" },
  ["vim.fs.basename"] = { summary = "The last component of a path.", origin = "Neovim" },
  ["vim.fs.dirname"] = { summary = "A path without its last component.", origin = "Neovim" },
  ["vim.treesitter.get_node_text"] = {
    summary = "The source text a syntax node spans.",
    origin = "Neovim",
  },
  ["vim.treesitter.query.parse"] = {
    summary = "Compiles a query against a grammar, for iterating captures over a tree.",
    origin = "Neovim",
  },
  ["vim.uv"] = {
    summary = "The libuv bindings: filesystem, timers, processes. `vim.loop` before 0.10.",
    origin = "Neovim",
  },
}

return M
