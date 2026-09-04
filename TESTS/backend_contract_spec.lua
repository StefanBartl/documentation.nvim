-- TESTS/backend_contract_spec.lua — every registered backend keeps its promises.
--
-- The trap this exists for is the one `core/markers.lua` opened by being
-- careful: a backend that declares no comment syntax is **skipped** rather
-- than guessed at, because `#` opens a comment in Python and a preprocessor
-- directive in C. That is the right default and it fails silently — a new
-- backend that forgets the field scans clean, reports no markers, and looks
-- exactly like a language whose authors write none.
--
-- Same shape as `artifact_contract_spec.lua`: the contract is a comment in
-- `@types/init.lua` and a set of tables maintained by hand, and a comment is
-- not a mechanism.

return function(H)
  local eq, ok = H.eq, H.ok
  local registry = require("documentation.core.lang_registry")

  -- `M.all` forces every backend in `KNOWN_BACKENDS` to register, which the
  -- registry otherwise defers until first use.
  --
  -- **`all(true)`, unfiltered.** This spec is about what the *build* can
  -- read, not about what some scan was configured to read, and
  -- `lang_registry.ENABLED` legitimately outlives the scan that set it (see
  -- `scan_scope_spec.lua`). Calling `all()` here made this spec pass or fail
  -- on which spec ran before it, which is exactly the coupling `M.reset`
  -- exists to prevent elsewhere.
  local all = registry.all(true)
  ok(#all >= 4, "expected the registered backends, found " .. #all)

  ---Fields without which a backend silently does less than it appears to.
  ---
  ---Each entry says what goes wrong when it is missing, because a required
  ---field with no reason attached is one somebody deletes.
  local REQUIRED = {
    {
      field = "is_source",
      why = "without it the walk cannot decide which files this backend claims",
    },
    {
      field = "extensions",
      why = "the page needs the list to pick a glossary; a predicate cannot be enumerated",
    },
    {
      field = "detect_source",
      why = "`config.detect_source` asks every backend in turn and a missing one is skipped",
    },
    {
      field = "parse_header",
      why = "the scan calls it for every module file",
    },
    {
      field = "scan_file",
      why = "the scan calls it for every source file",
    },
  }

  for _, backend in ipairs(all) do
    local name = backend.name
    for _, req in ipairs(REQUIRED) do
      ok(backend[req.field] ~= nil, ("%s declares no `%s` — %s"):format(name, req.field, req.why))
    end
  end

  -- ---------------------------------------------------------------------
  -- Comment syntax, the one whose absence is silent.
  --
  -- Every programming language has comments, so "declares none" is a
  -- mistake rather than a state. If a backend ever legitimately has none,
  -- this assertion is the right place to argue for the exception — which is
  -- the point of writing it down rather than trusting the next author to
  -- remember `core/markers.lua` exists.
  -- ---------------------------------------------------------------------
  for _, backend in ipairs(all) do
    local name = backend.name
    local line = backend.line_comments or {}
    local block = backend.block_comments or {}
    ok(
      #line > 0 or #block > 0,
      ("%s declares neither `line_comments` nor `block_comments`, so "):format(name)
        .. "`core/markers.lua` skips its files entirely and every `-- TODO:` "
        .. "in that language goes unreported — silently, which is the whole "
        .. "reason this assertion exists"
    )

    for _, pair in ipairs(block) do
      eq(#pair, 2, name .. ": a block comment is an opener and a closer")
      ok(pair[1] ~= "" and pair[2] ~= "", name .. ": neither half may be empty")
    end
  end

  -- ---------------------------------------------------------------------
  -- And the syntax has to actually work, not merely be present. A backend
  -- could declare `line_comments = { "//" }` for Lua and satisfy everything
  -- above while finding nothing.
  -- ---------------------------------------------------------------------
  do
    local markers = require("documentation.core.markers")
    for _, backend in ipairs(all) do
      local name = backend.name
      local token = (backend.line_comments or {})[1]
      if token then
        -- `code_prelude` is what a minimal file of this language has to
        -- begin with for its code to be code — empty for every backend but
        -- PHP, whose source outside `<?php` is text rather than code. That
        -- is the grammar being right, and it means a probe built without the
        -- tag asks the wrong question rather than finding a bug.
        local probe = (backend.code_prelude or "") .. token .. " TODO: proof"
        local found = markers.scan_source(probe, backend)
        eq(#found, 1, name .. ": its own first line-comment token must produce a marker")
      end
    end
  end

  -- ---------------------------------------------------------------------
  -- Every backend has a parity fixture.
  --
  -- `scripts/parity.lua` measures the capability matrix in
  -- `docs/languages.md` by running each backend over one real file of its
  -- own language. A backend with no fixture is reported as "no fixture" and
  -- **silently leaves a row out of the audit** -- the same failure mode as
  -- the missing comment token above, one level up: the table looks complete
  -- because the missing language is not in it.
  --
  -- Asserts the file exists, not what is in it. What is in it is the
  -- fixture's own job and the matrix is where it shows.
  -- ---------------------------------------------------------------------
  do
    local root = (vim.fn.getcwd():gsub("\\", "/"))
    local dir = root .. "/TESTS/fixtures/parity"
    ok(vim.fn.isdirectory(dir) == 1, "the parity fixture directory must exist")

    -- Keyed by backend name, matching `FIXTURES` in `scripts/parity.lua`.
    -- Two hand-maintained copies of one list is exactly what this repo
    -- avoids elsewhere -- but the script must run under a bare
    -- `nvim -l` with no harness, and a spec must run without the script,
    -- so the duplication buys each of them its own independence. This
    -- assertion is what stops them drifting.
    for _, backend in ipairs(all) do
      local matches = vim.fn.glob(dir .. "/**/" .. backend.name .. ".*", false, true)
      -- Java's fixture is `Java.java`: the language requires the file name
      -- to match the public type, so the one lower-case name would not
      -- compile. Matched case-insensitively rather than special-cased.
      if #matches == 0 then
        for _, path in ipairs(vim.fn.glob(dir .. "/**/*", false, true)) do
          local stem = path:match("([^/]+)%.[^.]+$")
          if stem and stem:lower() == backend.name:lower() then
            matches[#matches + 1] = path
          end
        end
      end
      ok(
        #matches > 0,
        backend.name
          .. ": needs a fixture in TESTS/fixtures/parity/, or it is left out of "
          .. "the capability matrix without saying so"
      )
    end
  end

  -- ---------------------------------------------------------------------
  -- `emits_calls` must agree with what the backend actually returns.
  --
  -- The field exists so a host can say *why* a Calls panel is empty, and a
  -- flag that says a backend produces call edges when it does not would
  -- make that sentence a lie in the one place a reader went looking for the
  -- truth. So it is measured, not trusted -- the same discipline the
  -- comment-token check above follows, and the same one `scripts/parity.lua`
  -- applies to the whole capability matrix.
  --
  -- Run over each backend's own parity fixture, and skipped per backend
  -- when its grammar is absent, which is the normal local state.
  -- ---------------------------------------------------------------------
  do
    local root = (vim.fn.getcwd():gsub("\\", "/"))
    local dir = root .. "/TESTS/fixtures/parity"
    local checked = 0

    for _, backend in ipairs(all) do
      local matches = vim.fn.glob(dir .. "/**/" .. backend.name .. ".*", false, true)
      if #matches == 0 then
        for _, path in ipairs(vim.fn.glob(dir .. "/**/*", false, true)) do
          local stem = path:match("([^/\\]+)%.[^.]+$")
          if stem and stem:lower() == backend.name:lower() then
            matches[#matches + 1] = path
          end
        end
      end

      -- The `.mli` sibling is a fixture for the same backend and not a
      -- second one; either file answers this question.
      local fixture = matches[1]
      -- `DOCMAP_<LANG>_PARSER` honoured exactly as every language spec
      -- honours it, and for the same reason: without it, only the four
      -- grammars Neovim ships are reachable -- which is lua, js, ts and tsx,
      -- the four backends that declare `emits_calls`. The check would then
      -- only ever confirm the *true* direction and never catch a backend
      -- claiming a capability it does not have, which is the direction that
      -- would put a wrong sentence in front of a reader.
      local ready = true
      if backend.grammar then
        local explicit = os.getenv("DOCMAP_" .. backend.name:upper() .. "_PARSER")
        local ok_add, added
        if explicit and explicit ~= "" then
          ok_add, added = pcall(vim.treesitter.language.add, backend.grammar, { path = explicit })
        else
          ok_add, added = pcall(vim.treesitter.language.add, backend.grammar)
        end
        ready = ok_add and added == true
      end

      if fixture and ready then
        checked = checked + 1
        local _, calls = backend.scan_file(fixture)
        local produced = calls ~= nil and #calls > 0
        if backend.emits_calls == true then
          ok(
            produced,
            backend.name .. ": declares emits_calls and returned none for its own fixture"
          )
        else
          eq(
            produced,
            false,
            backend.name
              .. ": returned call sites without declaring emits_calls, so a host "
              .. "would tell a reader the panel is empty because the language is "
              .. "unsupported"
          )
        end
      end
    end

    -- Without this the loop above passes triumphantly on a machine with no
    -- grammars at all, which is most machines.
    ok(checked >= 1, "at least one backend should have been measurable, checked " .. checked)
  end
end
