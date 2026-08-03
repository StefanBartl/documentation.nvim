---@module 'documentation.core.lang.ts'
--- TypeScript, registered as a language backend. Real work lives in
--- `ecma.lua`, shared with `js.lua`/`tsx.lua` — see that file's header for
--- what is and is not recognized. Type annotations themselves (parameter
--- types, return types, interfaces, generics) are not read — `ecma.lua`'s
--- function recognizer works on the same untyped shapes `js.lua` does, so a
--- `.ts` file's own type annotations contribute nothing beyond what a
--- JSDoc `@param`/`@returns` tag would already say.

local M = require("documentation.core.lang.ecma").backend("ts", "typescript", { "ts" }, "index.ts")

require("documentation.core.lang_registry").register(M.name, M)

return M
