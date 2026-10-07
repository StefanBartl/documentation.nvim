-- TESTS/setup_lazy_spec.lua -- `setup()` registers commands and scans nothing.
--
-- It used to install a handle eagerly, which ran a full scan (and, through
-- `core/scan.lua`, three git processes for `repo_url`/`branch`) before anybody
-- had asked a question: 123 ms on every editor start (testing.nvim K9/K10).
-- The handle `setup()` returns is lazy now: the first read scans.

return function(H)
  local eq, ok = H.eq, H.ok

  local root = vim.fn.tempname():gsub("\\", "/")
  vim.fn.mkdir(root .. "/lua/lazyfix", "p")
  vim.fn.writefile({ "local M = {}", "return M" }, root .. "/lua/lazyfix/init.lua")

  local scan_full = require("documentation").scan_full
  local scans = 0
  require("documentation").scan_full = function(...)
    scans = scans + 1
    return scan_full(...)
  end

  local handle = require("documentation.bindings.usrcmds").setup({
    root = root,
    command_name = "DocMapLazySpec",
    browse_command_name = "DocBrowseLazySpec",
    hover = false,
    telemetry = false,
  })

  eq(scans, 0, "setup(): no scan before the first read")
  eq(handle.scanned(), false, "setup(): the handle reports it is not scanned yet")

  local ir = handle.ir()
  eq(scans, 1, "the first ir() read scans")
  eq(handle.scanned(), true, "after the read the handle is scanned")
  ok(ir and ir.nodes, "ir() hands back a real IR")

  handle.ir()
  handle.findings()
  eq(scans, 1, "later reads reuse the scan")

  -- findings() on its own is also a first read.
  require("documentation.editor.registry").uninstall(root)
  local second = require("documentation.bindings.usrcmds").setup({
    root = root,
    command_name = "DocMapLazySpec",
    browse_command_name = "DocBrowseLazySpec",
    hover = false,
    telemetry = false,
  })
  local before = scans
  ok(type(second.findings()) == "table", "findings() on a fresh lazy handle scans and answers")
  eq(scans, before + 1, "findings() as first read costs one scan")

  require("documentation.editor.registry").uninstall(root)
  require("documentation").scan_full = scan_full
  vim.fn.delete(root, "rf")
end
