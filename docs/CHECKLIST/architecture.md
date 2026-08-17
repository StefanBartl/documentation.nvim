# Architecture — hand-verified facts

Facts about this tree that a scanner cannot decide, each cited to the file it
was read off and dated when a person last checked it. Not automated checks —
see [`docs/CHECKLIST_FORMAT.md`](../CHECKLIST_FORMAT.md) for why the two are
different things, and `:DocMap checklist` for what has drifted since.

## Layering

- [x] The core pipeline runs with no editor around it — nothing under
      `documentation.core` requires `documentation.editor` or
      `documentation.bindings`
      <!-- @ref scripts/gen_map.lua:96 -->
      <!-- @verified 2026-08-11 -->
      <!-- @note enforced by the layer-violation check, not only by hand -->

- [x] Git-derived data never enters the committed artifact, because `--check`
      byte-compares and a map carrying history has no fixed point
      <!-- @ref lua/documentation/core/churn.lua:36 -->
      <!-- @verified 2026-08-11 -->

- [x] The checklist ledger itself obeys that rule: `core/checklist.lua` is pure
      and never runs git; only `status()` is fed dates the command layer read
      <!-- @ref lua/documentation/core/checklist.lua:23 -->
      <!-- @verified 2026-08-11 -->

## Coexistence with other tooling

- [x] The call-hierarchy client answers alongside a real LuaLS rather than
      replacing it — both attach, LuaLS does not answer `prepareCallHierarchy`
      at all, and Neovim merges both hovers
      <!-- @ref lua/documentation/editor/callhierarchy.lua:16 -->
      <!-- @verified 2026-08-11 -->

- [x] Every soft dependency degrades to a stated result rather than an error
      when absent — runtime-analysis.nvim, pdfport.nvim, mdview.nvim
      <!-- @ref lua/documentation/core/telemetry_self.lua:1 -->
      <!-- @verified 2026-08-11 -->

## Protocol surfaces

- [x] The MCP server writes nothing but JSON-RPC to stdout; every diagnostic,
      `vim.notify` included, is pinned to stderr
      <!-- @ref scripts/mcp_server.lua:47 -->
      <!-- @verified 2026-08-11 -->

- [x] A failing MCP tool returns an `isError` result the model can read, never
      a JSON-RPC error the client's plumbing swallows
      <!-- @ref lua/documentation/mcp/protocol.lua:172 -->
      <!-- @verified 2026-08-11 -->

- [ ] The MCP tool catalogue still matches the current spec revision
      <!-- @ref lua/documentation/mcp/protocol.lua:37 -->
      <!-- @note deliberately open: MCP's spec is still moving, and this is the
           one item that is expected to need re-checking rather than to stay
           settled -->
