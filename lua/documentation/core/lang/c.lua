---@module 'documentation.core.lang.c'
--- C, registered as a language backend. Real work lives in `cfamily.lua`,
--- shared with `cpp.lua` — see that file's header for the two decisions this
--- language forced: what a header's prototypes are, and what stands in for a
--- module system when there is none.
---
--- `.h` is claimed here rather than by `cpp.lua`. A header shared between
--- the two parses as C in either grammar for the shapes this backend reads,
--- and claiming it twice would give one file two module identities — which
--- is a wrong answer rather than a duplicate.

local M = require("documentation.core.lang.cfamily").backend(
  "c",
  "c",
  { "c", "h" },
  { "src", "lib", "source" }
)

require("documentation.core.lang_registry").register(M.name, M)

return M
