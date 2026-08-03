---@module 'documentation.core.lang.js'
--- JavaScript, registered as a language backend. Real work lives in
--- `ecma.lua`, shared with `ts.lua`/`tsx.lua` — see that file's header for
--- what is and is not recognized.

local M = require("documentation.core.lang.ecma").backend("js", "javascript", { "js" }, "index.js")

require("documentation.core.lang_registry").register(M.name, M)

return M
