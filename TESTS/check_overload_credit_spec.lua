-- TESTS/check_overload_credit_spec.lua — `core/check.lua`'s
-- `check_undocumented_params` crediting `@overload`-only signatures
-- (docs/ROADMAP.md, now docs/ROADMAP/FEATURES.md once shipped).
--
-- Its own file, not a block in docmap_spec.lua: that file already sits
-- near Lua's 200-local-per-function ceiling — the same rationale
-- browse_loaded_spec.lua/browse_telemetry_spec.lua/browse_endpoints_spec.lua
-- already state for themselves.

return function(H)
  local ok = H.ok
  local check = require("documentation.core.check")

  local function make_ir(fns)
    return {
      meta = {
        title = "t",
        source = "lua",
        types_dir = "@types",
        branch = "main",
        schema = 1,
        counts = { module = 1, namespace = 0, file = 0 },
      },
      root = "a",
      order = { "a" },
      nodes = {
        a = {
          id = "a",
          kind = "module",
          name = "a",
          path = "a",
          source = "a/init.lua",
          module = "a",
          summary = "x",
          body = "",
          readme = "x.md",
          types = {},
          export = "table",
          parent = nil,
          depth = 0,
          children = {},
          functions = fns,
        },
      },
      edges = {},
    }
  end

  local opts = { root = "/fake", lua_root = "lua", extra_checks = {} }

  local function fires_undoc_param(fns)
    for _, f in ipairs(check.run(make_ir(fns), opts)) do
      if f.check == "undocumented-param" then
        return true
      end
    end
    return false
  end

  ---@param name string
  local function param(name)
    return { name = name, type = "any", optional = false, desc = "" }
  end

  ---@param signature string
  ---@param params table[]
  ---@param overload table[]
  local function fn(signature, params, overload)
    return {
      name = "M.foo",
      signature = signature,
      summary = "",
      line = 1,
      params = params,
      returns = {},
      generic = {},
      deprecated = nil,
      async = false,
      nodiscard = false,
      see = {},
      overload = overload,
      example = nil,
      since = nil,
    }
  end

  -- A function documented entirely through @overload -- zero @param
  -- lines, its real parameter list living inside the fun(...) literals
  -- instead -- must not be flagged: @overload is the alternative
  -- convention, not a gap.
  ok(not fires_undoc_param({
    fn("foo(a, b)", {}, {
      { raw = "fun(a: string, b: number)", params = { param("a"), param("b") }, returns = {} },
    }),
  }), "undocumented-param: silent when an @overload's own params cover the signature")

  -- The overload exists but does NOT cover the declared count -- a real
  -- gap, still a real finding. Proves the fix is scoped to "an overload
  -- actually covers it", not "any overload present at all".
  ok(
    fires_undoc_param({
      fn("foo(a, b, c)", {}, {
        { raw = "fun(a: string)", params = { param("a") }, returns = {} },
      }),
    }),
    "undocumented-param: still fires when no overload's params cover the full count"
  )

  -- Some @param lines (not zero) plus an overload that would otherwise
  -- cover it -- still a real finding. The credit only applies to the
  -- exact case the false positive was in: zero @param lines.
  ok(
    fires_undoc_param({
      fn("foo(a, b)", { param("a") }, {
        { raw = "fun(a: string, b: number)", params = { param("a"), param("b") }, returns = {} },
      }),
    }),
    "undocumented-param: still fires with partial @param lines, even with a covering overload"
  )

  -- No overload at all, zero @param lines -- unchanged behavior, still a
  -- real finding. Confirms the fix didn't accidentally widen to "no
  -- @param lines at all is fine".
  ok(
    fires_undoc_param({
      fn("foo(a, b)", {}, {}),
    }),
    "undocumented-param: still fires for zero @param lines with no overload to credit"
  )
end
