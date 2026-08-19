---@module 'documentation.core.lang.cpp'
--- C++, registered as a language backend. Real work lives in `cfamily.lua`,
--- shared with `c.lua`.
---
--- What C++ adds over C, and what this backend therefore reads that the C
--- registration never meets: `Thing::go` as a written name (taken as
--- written, not reconstructed from the enclosing class), members declared
--- inside a class body, and an access specifier that is *positional* —
--- everything after `private:` is private until the next one, a `class`
--- starts private and a `struct` starts public. That last one is why
--- `internal` is tracked while walking rather than read off the member node:
--- there is nothing on the node to read.
---
--- `.h` belongs to `c.lua`; see its header. The C++-only header extensions
--- (`.hpp`, `.hh`, `.hxx`) are claimed here, where nothing else wants them.

local M = require("documentation.core.lang.cfamily").backend(
  "cpp",
  "cpp",
  { "cpp", "cc", "cxx", "c++", "hpp", "hh", "hxx" },
  { "src", "lib", "source", "include" }
)

require("documentation.core.lang_registry").register(M.name, M)

return M
