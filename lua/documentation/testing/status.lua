---@module 'documentation.testing.status'
--- The last run of a project's specs, read back from what testing.nvim wrote.
---
--- Two files are understood and nothing from them is ever executed:
---
---   * a Result-IR (`testing run --json <file>`, `schema_version = 1`): every
---     case carries its file and status, so each spec file gets the worst
---     status of its cases;
---   * the run history (`stdpath('state')/testing/<project>/runs.jsonl`, one
---     JSON object per line): it remembers only the case ids that FAILED, so a
---     spec file with a remembered failure is `fail` and every other file is
---     left unknown (silence there is "no failure recorded", not "passed").
---
--- Both are UNTRUSTED input (SEC-33): they sit in a state directory any other
--- process can write to. The file is size-capped before it is read, decoded
--- under `pcall`, every field is type- and length-checked, and a value is only
--- ever used as a lookup key against the spec files this plugin discovered
--- itself, never as a path, a pattern or markup. A file that is not usable at
--- all is reported in `notes` and the map simply shows no status.
---
--- The location of the history is the one testing.nvim documents
--- (`<state>/testing/<basename>-<12 hex of sha256(project key)>/runs.jsonl`).
--- It is derived here, not asked of testing.nvim: this plugin never requires
--- it. The shapes read are the documented, versioned ones; a different version
--- is ignored with a note.

local M = {}

M.MAX_BYTES = 4 * 1024 * 1024
M.MAX_CASES = 200000
M.MAX_PATH_BYTES = 500

-- Worst first. Ranks decide which status represents a file with mixed cases.
local RANK = {
  crash = 1,
  timeout = 2,
  error = 3,
  fail = 4,
  xpass = 5,
  skip = 6,
  xfail = 7,
  pass = 8,
}
M.STATUSES = RANK

---The better of two statuses is the later in `RANK`; the worse wins.
---@param a string|nil
---@param b string
---@return string
local function worse(a, b)
  if not a or RANK[b] < RANK[a] then
    return b
  end
  return a
end
M.worse = worse

---Directory of one project's history, as testing.nvim derives it.
---@param root string
---@param state_dir string|nil Defaults to `stdpath('state')`.
---@return string|nil
function M.history_dir(root, state_dir)
  local ok, key = pcall(require("lib.nvim.fs.project_key"), root)
  if not ok or type(key) ~= "string" then
    return nil
  end
  local base = state_dir or vim.fn.stdpath("state")
  local name = (key:match("([^/]+)[/]*$") or "project"):gsub("[^%w_.%-]", "_")
  return ("%s/testing/%s-%s"):format(base, name, vim.fn.sha256(key):sub(1, 12))
end

---@param s any
---@return string|nil
local function clean_file(s)
  if type(s) ~= "string" or s == "" or #s > M.MAX_PATH_BYTES or s:find("[%z\1-\31]") then
    return nil
  end
  s = s:gsub("\\", "/"):gsub("^%./", "")
  return s
end

---@param decoded table
---@param notes string[]
---@return table<string, string> by_spec
local function from_result_ir(decoded, notes)
  local by_spec = {}
  local n = 0
  for _, case in ipairs(decoded.cases or {}) do
    n = n + 1
    if n > M.MAX_CASES then
      notes[#notes + 1] = ("result file has more than %d cases: the rest is ignored"):format(
        M.MAX_CASES
      )
      break
    end
    if type(case) == "table" then
      local file = clean_file(case.file)
      local status = type(case.status) == "string" and RANK[case.status] and case.status or nil
      if file and status then
        by_spec[file] = worse(by_spec[file], status)
      end
    end
  end
  return by_spec
end

---@param text string
---@param notes string[]
---@return table<string, string>|nil by_spec
---@return integer|nil ts
local function from_history(text, notes)
  local last
  local dropped = 0
  for line in text:gmatch("[^\r\n]+") do
    local ok, rec = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
    if
      ok
      and type(rec) == "table"
      and rec.v == 1
      and type(rec.failed) == "table"
      and type(rec.ts) == "number"
    then
      last = rec
    else
      dropped = dropped + 1
    end
  end
  if dropped > 0 then
    notes[#notes + 1] = ("%d unusable line(s) in the run history ignored"):format(dropped)
  end
  if not last then
    return nil, nil
  end
  local by_spec = {}
  for i, id in ipairs(last.failed) do
    if i > M.MAX_CASES then
      break
    end
    if type(id) == "string" and #id <= 2000 then
      -- `<file>::<describe>::<case>`: the file is the part before the first `::`.
      local file = clean_file(id:match("^(.-)::") or id)
      if file then
        by_spec[file] = "fail"
      end
    end
  end
  return by_spec, last.ts
end

---@class Documentation.Testing.StatusRead
---@field by_spec table<string, string> Spec file (as the run wrote it) -> status.
---@field source string|nil Path read.
---@field kind "result-ir"|"history"|nil
---@field ts integer|nil Unix time of the run, history only.
---@field notes string[]

---Read the last known statuses.
---@param root string
---@param opts { status_file?: string, state_dir?: string }|nil
---@return Documentation.Testing.StatusRead
function M.read(root, opts)
  opts = opts or {}
  local uv = vim.uv or vim.loop
  local result = { by_spec = {}, notes = {} }

  local path = opts.status_file
  if path ~= nil and (type(path) ~= "string" or path == "") then
    result.notes[1] = "status_file must be a path string: ignored"
    return result
  end
  if not path then
    local dir = M.history_dir(root, opts.state_dir)
    path = dir and (dir .. "/runs.jsonl") or nil
    if not path or not uv.fs_stat(path) then
      return result -- no run recorded yet: the normal state, not a note
    end
  end

  local st = uv.fs_stat(path)
  if not st then
    result.notes[1] = "status file not found: " .. path
    return result
  end
  if st.type ~= "file" then
    result.notes[1] = "status file is not a regular file: ignored"
    return result
  end
  if st.size > M.MAX_BYTES then
    result.notes[1] = ("status file is larger than %d bytes: ignored"):format(M.MAX_BYTES)
    return result
  end
  local fd = io.open(path, "rb")
  if not fd then
    result.notes[1] = "status file cannot be read: " .. path
    return result
  end
  local text = fd:read("*a")
  fd:close()
  result.source = path

  -- A Result-IR is one JSON document; a history is one document per line. Try
  -- the whole text first: a history with a single line is also a valid whole.
  local ok, whole = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
  if ok and type(whole) == "table" and whole.schema_version ~= nil then
    if whole.schema_version ~= 1 or type(whole.cases) ~= "table" then
      result.notes[#result.notes + 1] = "unknown result schema version: ignored"
      return result
    end
    result.kind = "result-ir"
    result.by_spec = from_result_ir(whole, result.notes)
    return result
  end

  local by_spec, ts = from_history(text, result.notes)
  if by_spec then
    result.kind = "history"
    result.by_spec = by_spec
    result.ts = ts
  else
    result.notes[#result.notes + 1] = "status file holds neither a result nor a run history"
  end
  return result
end

return M
