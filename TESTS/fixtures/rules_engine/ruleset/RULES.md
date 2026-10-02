# Fixture ruleset for the rules engine under the standalone shim

Every rule here is a question the engine must answer the same way in Neovim
and under the shim. `expected.txt` next to this directory is what each should
say; the two hosts are also compared with each other.

## Mechanical checks

#### `FIX-01` — a grep that finds something

```rule
id = "FIX-01",
severity = "recommended",
check = { type = "grep", pattern = "vim%.tbl_flatten%(", include = "%.lua$" },
agent = { question = "Is every flatten call guarded?", include = { "lua/**/*.lua" }, max_files = 3 },
```

Deprecated call; the grep reports candidates, not verdicts.

```bash
# a shell comment that must not be read as a heading
echo done
```

#### `FIX-02` — a grep that finds nothing

```rule
id = "FIX-02",
severity = "recommended",
check = { type = "grep", pattern = "does%.not%.occur%.anywhere" },
```

#### `FIX-03` — a required file that exists

```rule
id = "FIX-03",
severity = "critical",
check = { type = "file_exists", path = "README.md" },
```

#### `FIX-04` — a required file that is missing

```rule
id = "FIX-04",
severity = "critical",
check = { type = "file_exists", path = "LICENSE" },
```

#### `FIX-05` — a forbidden JSON key that is present

```rule
id = "FIX-05",
severity = "recommended",
check = { type = "json_key_absent", path = ".luarc.json", key = "workspace.library" },
```

## Judgement

#### `FIX-06` — no automated check

```rule
id = "FIX-06",
severity = "nice-to-have",
```

Read the code and decide; this stays a worklist entry.

## Predicates

These run Neovim API code, which is the surface the shim has to provide.

#### `PRD-01` — glob and filereadable

```rule
id = "PRD-01",
severity = "recommended",
check = {
  type = "lua_predicate",
  fn = function(root)
    local hits = vim.fn.glob(root .. "/lua/*/health.lua", false, true)
    if #hits > 0 and vim.fn.filereadable(root .. "/README.md") == 1 then
      return true
    end
    return false, "no health module"
  end,
},
```

#### `PRD-02` — readfile and json decode

```rule
id = "PRD-02",
severity = "recommended",
check = {
  type = "lua_predicate",
  fn = function(root)
    local lines = vim.fn.readfile(root .. "/.luarc.json")
    local ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
    if not ok then
      return false, "unreadable .luarc.json"
    end
    if decoded.workspace and decoded.workspace.library then
      return false, { { file = root .. "/.luarc.json", line = 1, text = "workspace.library is set" } }
    end
    return true
  end,
},
```

#### `PRD-03` — recursive glob

```rule
id = "PRD-03",
severity = "recommended",
check = {
  type = "lua_predicate",
  fn = function(root)
    local files = vim.fn.glob(root .. "/lua/**/*.lua", false, true)
    return #files >= 3, "expected at least three lua files, found " .. #files
  end,
},
```

#### `PRD-04` — a subprocess and its exit status

```rule
id = "PRD-04",
severity = "recommended",
check = {
  type = "lua_predicate",
  fn = function()
    local out = vim.fn.system({ "git", "--version" })
    if vim.v.shell_error ~= 0 then
      return false, "git failed"
    end
    return out:match("^git version") ~= nil, "unexpected git output"
  end,
},
```

#### `PRD-05` — string helpers and path helpers

```rule
id = "PRD-05",
severity = "nice-to-have",
check = {
  type = "lua_predicate",
  fn = function(root)
    local parts = vim.split(vim.trim("  a/b/c  "), "/", { plain = true })
    local name = vim.fs.basename(vim.fs.normalize(root .. "/lua/mod/"))
    return #parts == 3 and name == "mod", "path helpers disagree"
  end,
},
```

## Hostile blocks

A ruleset is code. Neither of these may run, and neither may stop the rest.

#### `HOS-01` — a block that calls into the host

```rule
id = os.getenv("HOME"),
severity = "critical",
```

#### `HOS-02` — a block that never returns

```rule
id = (function() while true do end end)(),
severity = "critical",
```

#### `HOS-03` — a bad agent hint

```rule
id = "HOS-03",
severity = "nice-to-have",
agent = { qustion = "typo in the key" },
```

The rule stays; only the hint is dropped, and reported.
