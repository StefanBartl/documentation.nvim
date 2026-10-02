local M = {}

function M.flat(t)
  return vim.tbl_flatten(t)
end

return M
