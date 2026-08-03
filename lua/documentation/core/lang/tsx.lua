---@module 'documentation.core.lang.tsx'
--- TSX, registered as a language backend — React function components and
--- hooks live here. Real work lives in `ecma.lua`, shared with `js.lua`/
--- `ts.lua`; see that file's header for what is and is not recognized.
---
--- `.jsx` is deliberately **not** claimed by this backend, even though the
--- `tsx` grammar can parse plain JSX too: a `.jsx` file is JavaScript, not
--- TypeScript, and `js.lua` already exists for it. Extending `js.lua` to
--- also parse JSX syntax (a separate JS grammar concern, not a TSX-only
--- one) is the honest fix, left for when a real `.jsx` tree actually needs
--- it rather than guessed at now.

local M = require("documentation.core.lang.ecma").backend("tsx", "tsx", { "tsx" }, "index.tsx")

require("documentation.core.lang_registry").register(M.name, M)

return M
