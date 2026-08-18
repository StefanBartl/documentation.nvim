---@module 'documentation.core.lang.js'
--- JavaScript, registered as a language backend. Real work lives in
--- `ecma.lua`, shared with `ts.lua`/`tsx.lua` — see that file's header for
--- what is and is not recognized.

-- `.jsx` is JavaScript, so it is claimed here rather than by `tsx.lua`,
-- exactly as `tsx.lua`'s own header said it should be: a `.jsx` file is not
-- TypeScript, and conflating the two would be a wrong module identity rather
-- than a shortcut. Verified rather than assumed — the `javascript` grammar
-- parses a real JSX component with zero ERROR nodes, so no second grammar is
-- needed for it.
local M =
  require("documentation.core.lang.ecma").backend("js", "javascript", { "js", "jsx" }, "index.js")

require("documentation.core.lang_registry").register(M.name, M)

return M
