-- TESTS/pdf_artifact_spec.lua — documentation.write_pdf_artifact
--
-- overview.pdf via pdfport.nvim (optional dependency, soft-required). All
-- three cases stub package.loaded["pdfport"] rather than depending on a real
-- pdfport.nvim + pandoc install being present on the machine running the
-- suite -- same pattern as markdown.nvim's tests/handler_pdf_spec.lua.

return function(H)
  local eq, ok = H.eq, H.ok

  local function reset_pdfport()
    package.loaded["pdfport"] = nil
  end

  -- A tiny but real scanned tree, so the happy-path case exercises the
  -- actual M.render.markdown() output rather than a hand-built fixture.
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp .. "/lua/demo", "p")
  local fd = assert(io.open(tmp .. "/lua/demo/init.lua", "w"))
  fd:write("---@module 'demo'\nlocal M = {}\nfunction M.run() end\nreturn M\n")
  fd:close()

  local docmap = require("documentation")
  local opts = { root = tmp, source = "lua", out_dir = "docs/map" }
  local ir, findings = docmap.scan_full(opts)

  -- ---------------------------------------------------- pdfport not installed
  do
    reset_pdfport()
    local got
    docmap.write_pdf_artifact(ir, findings, opts, function(is_ok, path_or_err)
      got = { ok = is_ok, msg = path_or_err }
    end)
    eq(got.ok, false, "no pdfport.nvim -> reports failure")
    ok(got.msg:find("not installed"), "no pdfport.nvim -> error names it")
  end

  -- ------------------------------------------------- no markdown producer
  do
    reset_pdfport()
    package.loaded["pdfport"] = {
      create = function() end,
      can_create = function()
        return false
      end,
    }
    local got
    docmap.write_pdf_artifact(ir, findings, opts, function(is_ok, path_or_err)
      got = { ok = is_ok, msg = path_or_err }
    end)
    eq(got.ok, false, "no available markdown producer -> reports failure")
    ok(got.msg:find("markdown producer"), "no available markdown producer -> error names it")
  end

  -- ------------------------------------------------------------- happy path
  do
    reset_pdfport()
    local create_opts
    package.loaded["pdfport"] = {
      can_create = function(kind)
        return kind == "markdown"
      end,
      create = function(create_call_opts)
        create_opts = create_call_opts
        create_call_opts.__callback({ status = "ok", path = create_call_opts.output })
      end,
    }

    local got
    docmap.write_pdf_artifact(ir, findings, opts, function(is_ok, path_or_err)
      got = { ok = is_ok, msg = path_or_err }
    end)

    ok(got.ok, "pdfport available -> reports success: " .. tostring(got.msg))
    eq(got.msg, "docs/map/overview.pdf", "reports the repo-relative overview.pdf path")
    eq(create_opts.from, "markdown", 'pdfport.create() gets from = "markdown"')
    eq(
      create_opts.output,
      (tmp:gsub("\\", "/")) .. "/docs/map/overview.pdf",
      "pdfport.create() gets the absolute output path"
    )
    ok(create_opts.text:find("module map"), "pdfport.create() gets the rendered overview as text")
  end

  reset_pdfport()
end
