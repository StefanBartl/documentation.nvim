---@module 'documentation.core.lang.glossary.ecma'
--- Keyword glossary for JavaScript, TypeScript and TSX — one table for all
--- three, the same relationship `core/lang/ecma.lua` has to `js.lua`/
--- `ts.lua`/`tsx.lua`.
---
--- **One table, not three, and the TypeScript-only entries are marked rather
--- than split out.** A reader hovering `satisfies` in a `.ts` file and a
--- reader hovering it in a `.js` file are asking the same question; the
--- second one's answer is "this is TypeScript, it does not exist here",
--- which is information, not an error. Maintaining three tables to withhold
--- that would cost more and say less.
---
--- Reference is MDN, one base URL and no per-entry anchors — see
--- `glossary/lua.lua`'s header for the rule and why the anchors this rule
--- permits are deliberately left unfilled until someone checks them.

local M = {}

---@type Documentation.Glossary.Reference
M.reference = {
  label = "MDN JavaScript reference",
  url = "https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference",
}

---How to tell code from not-code, for the page's tokenizer. See
---`glossary/lua.lua`'s own `syntax` for why this is data rather than a lexer.
---
---**Two known limits, both erring toward not decorating.** A template
---literal is treated as one opaque string, so a keyword inside `${...}`
---interpolation is skipped rather than explained; and a regex literal whose
---body contains `//` or `/*` can start a phantom comment span. Both cost a
---missing decoration, never a wrong one, which is the direction to fail in.
---@type Documentation.Glossary.Syntax
M.syntax = {
  line_comment = "//",
  block_comment = { "/*", "*/" },
  strings = { { '"', '"' }, { "'", "'" }, { "`", "`" } },
  escape = "\\",
}

---@type table<string, Documentation.Glossary.Entry>
M.keywords = {
  -- Asynchrony — the entries most worth having, because the semantics are
  -- not guessable from the shape.
  ["async"] = {
    summary = "Marks a function as asynchronous: it now always returns a promise, whatever it appears to return.",
  },
  ["await"] = {
    summary = "Suspends the enclosing async function until a promise settles, then continues with its value.",
    note = "Suspends this function only — it does not block the thread, and other work continues meanwhile.",
  },
  ["yield"] = {
    summary = "Hands a value out of a generator and suspends it until the caller asks for the next one.",
  },

  -- Bindings
  ["const"] = {
    summary = "A block-scoped binding that cannot be reassigned.",
    note = "The *binding* is fixed, not the value: a `const` object's properties can still be changed.",
  },
  ["let"] = { summary = "A block-scoped binding that can be reassigned." },
  ["var"] = {
    summary = "A function-scoped binding.",
    note = "Hoisted to the top of its function and visible before its own line — the reason `let` exists.",
  },

  -- Functions, classes, objects
  ["function"] = { summary = "Defines a function." },
  ["return"] = { summary = "Returns a value from a function." },
  ["class"] = {
    summary = "Defines a class — syntax over the prototype chain, not a separate object model.",
  },
  ["extends"] = { summary = "Names the class this one inherits from." },
  ["super"] = {
    summary = "The parent class: `super(...)` calls its constructor, `super.x` reaches its members.",
  },
  ["this"] = {
    summary = "The receiver of the current call.",
    note = "Determined by how a function is *called*, not where it is defined — except in arrow functions, which take it from the enclosing scope.",
  },
  ["new"] = {
    summary = "Constructs an instance: makes an object, runs the constructor against it, returns it.",
  },
  ["static"] = { summary = "A member on the class itself rather than on its instances." },
  ["get"] = { summary = "Defines a property that runs a function when read." },
  ["set"] = { summary = "Defines a property that runs a function when assigned to." },

  -- Operators that are words
  ["typeof"] = {
    summary = "The type of a value, as a string.",
    note = '`typeof null` is `"object"` — a bug preserved for compatibility since 1995.',
  },
  ["instanceof"] = {
    summary = "Whether a constructor's prototype appears in an object's prototype chain.",
  },
  ["delete"] = { summary = "Removes a property from an object." },
  ["void"] = { summary = "Evaluates its operand and yields `undefined`." },
  ["in"] = {
    summary = "Whether a property exists on an object or its prototype chain — and the separator in `for...in`.",
  },
  ["of"] = { summary = "Iterates values in `for...of`, where `for...in` iterates keys." },

  -- Control flow
  ["if"] = { summary = "A conditional." },
  ["else"] = { summary = "The branch taken when the condition failed." },
  ["for"] = {
    summary = "A loop: the C-style form, or `for...of` over values, or `for...in` over keys.",
  },
  ["while"] = { summary = "Loops while the condition holds, tested before each pass." },
  ["do"] = {
    summary = "With `while`, a loop whose condition is tested after the body — so it always runs once.",
  },
  ["switch"] = { summary = "Dispatches on a value, comparing with strict equality." },
  ["case"] = {
    summary = "One branch of a `switch`.",
    note = "Falls through to the next case without a `break`, which is a feature about as often as it is a bug.",
  },
  ["default"] = {
    summary = "The `switch` branch taken when nothing matched — or, in a module, the unnamed export.",
  },
  ["break"] = { summary = "Leaves the innermost loop or `switch`." },
  ["continue"] = { summary = "Skips to the next pass of the innermost loop." },
  ["try"] = { summary = "Runs a block whose exceptions are handled rather than propagated." },
  ["catch"] = { summary = "Handles an exception thrown inside the matching `try`." },
  ["finally"] = {
    summary = "Runs after `try`/`catch` whatever happened, including on an early `return`.",
  },
  ["throw"] = {
    summary = "Raises an exception. Any value can be thrown, though an `Error` is what tooling expects.",
  },

  -- Modules
  ["import"] = { summary = "Brings bindings in from another module." },
  ["export"] = { summary = "Makes a binding available to other modules." },
  ["from"] = { summary = "Names the module an `import`/`export` refers to." },
  ["as"] = {
    summary = "Renames an imported or exported binding — and, in TypeScript, asserts a type.",
    note = "TypeScript's `x as T` is an assertion, not a conversion: nothing is checked and nothing is converted at runtime.",
  },

  -- Values
  ["null"] = { summary = "An intentionally absent value." },
  ["undefined"] = {
    summary = "The value of something never assigned.",
    note = "Not a keyword but a global binding — which is why `void 0` was once the safer way to write it.",
  },
  ["true"] = { summary = "The boolean true." },
  ["false"] = { summary = "The boolean false." },

  -- TypeScript. Marked rather than hidden from .js readers -- "this does not
  -- exist here" is a real answer to the question they asked.
  ["interface"] = {
    summary = "TypeScript: a structural type. Erased at compile time — nothing of it exists at runtime.",
    note = "TypeScript only.",
  },
  ["type"] = {
    summary = "TypeScript: names a type, including ones an interface cannot express (unions, conditionals).",
    note = "TypeScript only.",
  },
  ["enum"] = {
    summary = "TypeScript: a named set of constants.",
    note = "TypeScript only — and unlike the rest, a plain `enum` emits real runtime code rather than being erased.",
  },
  ["implements"] = {
    summary = "TypeScript: declares that a class satisfies an interface. Checked, then erased.",
    note = "TypeScript only.",
  },
  ["readonly"] = {
    summary = "TypeScript: a property that may not be assigned after construction. Compile-time only.",
    note = "TypeScript only.",
  },
  ["keyof"] = {
    summary = "TypeScript: the union of a type's property names.",
    note = "TypeScript only.",
  },
  ["infer"] = {
    summary = "TypeScript: captures a type inside a conditional type so the branch can name it.",
    note = "TypeScript only.",
  },
  ["declare"] = {
    summary = "TypeScript: asserts that something exists elsewhere, emitting nothing.",
    note = "TypeScript only.",
  },
  ["namespace"] = {
    summary = "TypeScript: an older module system, predating ES modules and largely superseded by them.",
    note = "TypeScript only.",
  },
  ["abstract"] = {
    summary = "TypeScript: a class that cannot be instantiated, or a member subclasses must implement.",
    note = "TypeScript only.",
  },
  ["satisfies"] = {
    summary = "TypeScript: checks a value against a type without widening it to that type.",
    note = "TypeScript only. The difference from `as`: `satisfies` verifies and keeps the narrow inferred type, `as` overrides it and checks nothing.",
  },
  ["public"] = {
    summary = "TypeScript: the default visibility, stated explicitly. Compile-time only.",
    note = "TypeScript only.",
  },
  ["private"] = {
    summary = "TypeScript: a member its class alone may use — enforced by the compiler, not at runtime.",
    note = "TypeScript only. JavaScript's own `#name` fields are the runtime-enforced version.",
  },
  ["protected"] = {
    summary = "TypeScript: a member its class and subclasses may use. Compile-time only.",
    note = "TypeScript only.",
  },
}

---Built-in names worth a sentence, chosen the same way `glossary/lua.lua`'s
---are: by what a reader stops at, not by transcribing a specification. The
---bar is "the behaviour is not guessable from the name" — `Array.isArray`
---does not need an entry, `Array.prototype.flat`'s depth argument does.
---
---No `origin` on any of these: unlike Lua's glossary, which carries the host
---API beside the language, every name here *is* JavaScript, and MDN
---documents all of them.
---@type table<string, Documentation.Glossary.Entry>
M.stdlib = {
  ["Object.keys"] = {
    summary = "An array of an object's own enumerable string keys.",
    note = "Own keys only — inherited ones are excluded, which is what separates it from `for...in`.",
  },
  ["Object.values"] = { summary = "An array of an object's own enumerable values." },
  ["Object.entries"] = { summary = "An array of `[key, value]` pairs, own and enumerable." },
  ["Object.assign"] = {
    summary = "Copies own enumerable properties onto a target, and returns it.",
    note = "A shallow copy: nested objects are shared with the source, not cloned.",
  },
  ["Object.freeze"] = {
    summary = "Makes an object's own properties non-writable.",
    note = "Shallow as well — a frozen object's nested objects are still mutable.",
  },
  ["Array.isArray"] = {
    summary = "Whether a value is an array, across realms, where `instanceof Array` is not.",
  },
  ["Array.from"] = {
    summary = "An array from anything iterable or array-like, with an optional map function.",
  },
  ["JSON.stringify"] = {
    summary = "A value as JSON.",
    note = "Drops `undefined`, functions and symbols in objects, and turns them into `null` inside arrays — the same value serialises differently depending on where it sits.",
  },
  ["JSON.parse"] = {
    summary = "JSON text as a value. Throws on malformed input rather than returning null.",
  },
  ["Promise.all"] = {
    summary = "Resolves when every promise does, rejects as soon as any one rejects.",
    note = "The first rejection wins immediately; the others keep running, unobserved.",
  },
  ["Promise.allSettled"] = {
    summary = "Waits for every promise and reports each outcome, never rejecting.",
  },
  ["Promise.race"] = {
    summary = "Settles as the first promise to settle does, whether it resolved or rejected.",
  },
  ["Promise.resolve"] = {
    summary = "A promise already resolved with a value — the usual way to enter a promise chain.",
  },
  ["Array.prototype.reduce"] = {
    summary = "Folds an array to one value.",
    note = "Without an initial value it starts from element 0 and throws on an empty array.",
  },
  ["Array.prototype.flat"] = {
    summary = "Flattens nested arrays, one level by default; `Infinity` for all of them.",
  },
  ["Array.prototype.at"] = {
    summary = "Element by index, where a negative index counts from the end.",
  },
  ["Object.fromEntries"] = {
    summary = "An object from `[key, value]` pairs — the inverse of `Object.entries`.",
  },
  ["structuredClone"] = {
    summary = "A deep clone, including Maps, Sets, Dates and cycles.",
    note = "Cannot clone functions or DOM nodes, and throws rather than skipping them.",
  },
  ["console.log"] = {
    summary = "Writes to the console. Objects are logged by reference in some consoles, so a later mutation can appear retroactively.",
  },
  ["Number.isInteger"] = {
    summary = "Whether a value is a number with no fractional part, without the coercion `parseInt` does.",
  },
  ["Number.parseFloat"] = {
    summary = "Leading numeric text as a float, ignoring trailing junk rather than failing on it.",
  },
  ["Math.max"] = {
    summary = "The largest of its arguments. `Math.max()` with none is `-Infinity`.",
  },
  ["Math.min"] = {
    summary = "The smallest of its arguments. `Math.min()` with none is `Infinity`.",
  },
}

return M
