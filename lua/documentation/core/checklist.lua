---@module 'documentation.core.checklist'
--- Reads a repo's own `docs/CHECKLIST/` folder into
--- `Documentation.Checklist.Result` — a **ledger of hand-verified facts**,
--- not a set of automated checks.
---
--- The distinction is the whole point, and it came out of reading a real
--- corpus rather than from designing one. `docs/ROADMAP/RULES/` in this
--- author's nvim-config is 33 per-plugin reports plus 9 thematic syntheses,
--- each guideline cited to a real `file:line`. Its `keybindings-count.md`
--- asks "does `<leader>xy` support `2<leader>xy`" *per keymap* — and that is
--- not something a scanner can decide, because it needs to know whether
--- count-semantics make sense for this particular action. A person answered
--- it once, reading the code.
---
--- So nothing here re-derives a verdict. What it does instead is watch the
--- **citation**: an item pinned to a file that has been committed to since
--- the item was last verified is flagged "re-read this", rather than
--- continuing to display a verdict that may quietly have stopped being true.
--- The output is not pass/fail, it is *what needs attention*.
---
--- ## Why the staleness is not in here
---
--- This module is pure `path -> Result` and never runs git — the same split
--- `core/churn.lua` draws, and for the same hard reason it states: git data
--- cannot enter the committed artifact, because `--check` byte-compares
--- generated output against committed output, so a map carrying history has
--- no fixed point. The *ledger* is static and bakes into `module_map.json`
--- happily; the *staleness verdict* is computed live, by
--- `M.status` below, off a `path -> commit dates` table somebody else
--- produced.
---
--- Splitting it that way is also what lets the parser be driven from a
--- headless spec with no repository at all.
---
--- ## The format
---
--- Ordinary Markdown, because the corpus that motivated this is ordinary
--- Markdown and hand-edited throughout:
---
---     ## Keybindings
---
---     - [x] `<leader>xy` supports count where it should
---           <!-- @ref lua/plugins/dap/keymaps.lua:32 -->
---           <!-- @verified 2026-08-08 -->
---     - [ ] Picker inputs support autocompletion
---           <!-- @ref lua/plugins/foo/usrcmds.lua:14 -->
---
--- `- [x]`/`- [ ]` is the syntax every roadmap file in this ecosystem
--- already uses. The metadata rides in HTML comments so it is invisible in a
--- rendered preview but trivially parseable line-by-line — the same "cheap
--- reliable reading beats a general one" discipline `core/features.lua` and
--- `core/deps.lua` already follow, no CommonMark parser involved.
---
--- **`@verified` is a date, not a commit hash.** A hash is exact and nobody
--- hand-writes one; requiring it would force a command to check an item off,
--- which reopens a decision this feature deliberately settled the other way
--- (hand-editing, as the `RULES/` corpus was actually produced). The cost is
--- a real but small imprecision — several commits on the verification day
--- itself can be ordered wrong — which does not matter for facts re-read
--- every few months.
---
--- ## What is deliberately not validated
---
--- An `@ref` that names no file, an item with no `@ref` at all, a section
--- with no items: all valid, none an error. Same posture as
--- `core/features.lua`. An item with no citation simply cannot go stale —
--- that is a real state (a fact about the project rather than about a line
--- of code), not a defect to reject. Resolution against the IR happens in
--- `resolve`, separately and after the fact, so a checklist can be written
--- before the code it cites exists.

local M = {}

local uv = vim.uv or vim.loop

---@param path string
---@return boolean
local function is_dir(path)
  local st = uv.fs_stat(path)
  return st ~= nil and st.type == "directory"
end

---@param path string
---@return string|nil
local function read_file(path)
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local text = fd:read("*a")
  fd:close()
  return text
end

--- Candidate folder names, in resolution order — uppercase preferred, the
--- same shape and reasoning as `core/features.lua`'s own `CANDIDATE_FOLDERS`.
--- The `.md` entries are the degenerate single-file case: a project with six
--- checklist items should not have to make a directory for them.
local CANDIDATES = { "docs/CHECKLIST", "docs/checklist", "docs/CHECKLIST.md", "docs/checklist.md" }

---Split into lines, `\n`-terminated tail included so the last real line is
---never dropped — same idiom `core/features.lua` and `core/deps.lua` use.
---@param text string
---@return string[]
local function to_lines(text)
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    out[#out + 1] = (line:gsub("%s+$", ""))
  end
  return out
end

---@param s string
---@return string
local function trim(s)
  return (s:match("^%s*(.-)%s*$"))
end

---One `- [ ]` / `- [x]` line.
---
---Accepts `*` as the bullet marker alongside `-`, and both cases of `x`,
---because a corpus written by hand across dozens of files will contain both
---and rejecting one of them would only produce a checklist that silently
---misses items.
---@param line string
---@return boolean? done
---@return string? text
local function match_item(line)
  local mark, text = line:match("^%s*[-*]%s*%[([ xX])%]%s*(.*)$")
  if not mark then
    return nil, nil
  end
  return mark ~= " ", trim(text)
end

---One `<!-- @tag value -->` metadata comment.
---@param line string
---@return string? tag
---@return string? value
local function match_meta(line)
  local tag, value = line:match("^%s*<!%-%-%s*@(%w+)%s+(.-)%s*%-%->%s*$")
  if not tag then
    return nil, nil
  end
  return tag, trim(value)
end

---Split an `@ref` value into a repo-relative path and an optional 1-based
---line.
---
---The line is kept even though staleness is decided per *file*: it is what
---makes a flagged item actionable — "this file changed, and the thing you
---verified was at line 32" is a place to jump to, where the path alone is a
---file to re-read from the top. Same reasoning as `core/churn.lua` shipping
---its commit count beside its score: the number that explains the verdict
---travels with it.
---@param value string
---@return string path
---@return integer? line
local function split_ref(value)
  local path, line = value:match("^(.-):(%d+)$")
  if path then
    return path, tonumber(line)
  end
  return value, nil
end

---Parse one checklist file's text.
---@param text string
---@param path string Repo-relative, for `item.file`.
---@return Documentation.Checklist.Section[]
function M.parse(text, path)
  local lines = to_lines(text)
  local sections = {}
  ---@type Documentation.Checklist.Section?
  local current
  ---@type Documentation.Checklist.Item?
  local last_item
  -- Partial `<!-- ... ` comment, awaiting its closing `-->` on a later line.
  ---@type string?
  local pending

  for i, line in ipairs(lines) do
    local heading = line:match("^##%s+(.+)$")
    if heading then
      current = { name = trim(heading), line = i, items = {} }
      sections[#sections + 1] = current
      last_item = nil
      pending = nil
    else
      local done, text_ = match_item(line)
      if done ~= nil then
        -- An item before any `## ` heading still belongs somewhere. A
        -- synthetic section keeps the shape uniform for every consumer
        -- rather than making each one handle a nil parent — and its `line =
        -- 0` says plainly that no heading exists in the file, instead of
        -- pointing at a line that says something else.
        if not current then
          current = { name = "", line = 0, items = {} }
          sections[#sections + 1] = current
        end
        last_item = {
          done = done,
          text = text_ or "",
          line = i,
          file = path,
          meta = {},
        }
        current.items[#current.items + 1] = last_item
      elseif last_item then
        ---@type Documentation.Checklist.Item
        local item = last_item

        -- A metadata comment may wrap across lines, and a long `@note`
        -- routinely does — found running this against a real ledger, where
        -- the opening line of a three-line comment failed to match and was
        -- then swallowed into the item's own text, comment markers and all.
        -- Buffered into one logical line before matching, so the matcher
        -- itself stays a single-line pattern.
        --
        -- `logical` is nil while a comment is still open, which is what the
        -- rest of this branch tests. Written as a value rather than as a
        -- `goto continue`: the label would have to sit past the `local tag`
        -- below, and jumping forward into a local's scope is not legal Lua.
        ---@type string?
        local logical = line
        if pending then
          pending = pending .. " " .. trim(line)
          if line:find("%-%->") then
            logical, pending = pending, nil
          else
            logical = nil
          end
        elseif line:find("<!%-%-") and not line:find("%-%->") then
          pending = trim(line)
          logical = nil
        end

        local tag, value
        if logical then
          tag, value = match_meta(logical)
        end

        if not logical then
          -- Mid-comment: nothing to decide until the closing `-->` arrives.
        elseif tag == "ref" and value then
          local ref_path, ref_line = split_ref(value)
          item.ref = ref_path
          item.ref_line = ref_line
        elseif tag == "verified" and value then
          item.verified = value
        elseif tag and value then
          -- Unknown tags are kept rather than dropped, for the same reason
          -- `core/features.lua` accepts one-off metadata keys: a corpus
          -- written by hand will grow a vocabulary this parser did not
          -- anticipate, and silently discarding it is worse than carrying
          -- it through to whatever displays it.
          item.meta[#item.meta + 1] = { key = tag, value = value }
        elseif trim(line) == "" then
          -- A blank line does not end the block: the `RULES/`-shaped corpus
          -- this format is modelled on separates an item's text from its
          -- metadata comments with one, and treating that as a terminator
          -- would drop every citation in it.
        elseif line:match("^%s") then
          -- An indented continuation line. Hand-written checklist items wrap
          -- — found the first time this parser was run against a real
          -- ledger, where every multi-line item silently lost everything
          -- after its first line and the quickfix text ended mid-sentence.
          -- Joined with a single space, since the line break is Markdown
          -- formatting rather than content.
          item.text = item.text == "" and trim(line) or (item.text .. " " .. trim(line))
        else
          -- A non-indented, non-blank, non-comment line ends the item's
          -- metadata block. Without this, prose after a list would attach
          -- its comments to the last item several paragraphs above.
          last_item = nil
        end
      end
    end
  end

  return sections
end

---Read the checklist corpus under `root`.
---@param root string Absolute repository root, forward slashes, no trailing slash.
---@return Documentation.Checklist.Result? `nil` when the repo has no checklist at all.
function M.resolve(root)
  if type(root) ~= "string" or root == "" then
    return nil
  end

  local source, files = nil, {}

  for _, candidate in ipairs(CANDIDATES) do
    local abs = root .. "/" .. candidate
    if candidate:match("%.md$") then
      local text = read_file(abs)
      if text then
        source = candidate
        files[1] = {
          path = candidate,
          name = candidate:match("([^/]+)%.md$"),
          sections = M.parse(text, candidate),
        }
        break
      end
    elseif is_dir(abs) then
      source = candidate
      local names = {}
      for name, kind in vim.fs.dir(abs) do
        if kind == "file" and name:match("%.md$") then
          names[#names + 1] = name
        end
      end
      -- Sorted, so two runs over an unchanged tree produce identical bytes.
      -- `vim.fs.dir` gives no ordering guarantee, and the artifact is
      -- byte-compared by `--check`.
      table.sort(names)
      for _, name in ipairs(names) do
        local rel = candidate .. "/" .. name
        local text = read_file(root .. "/" .. rel)
        if text then
          files[#files + 1] =
            { path = rel, name = name:gsub("%.md$", ""), sections = M.parse(text, rel) }
        end
      end
      break
    end
  end

  if not source then
    return nil
  end

  local total, done, cited = 0, 0, 0
  for _, file in ipairs(files) do
    for _, section in ipairs(file.sections) do
      for _, item in ipairs(section.items) do
        total = total + 1
        if item.done then
          done = done + 1
        end
        if item.ref then
          cited = cited + 1
        end
      end
    end
  end

  return { source = source, files = files, total = total, done = done, cited = cited }
end

---Turn `git log --format=%x1e%cs --name-only` output into the `path -> dates`
---table `status` wants.
---
---Pure string work over a buffer somebody else obtained, which is the point:
---two callers need this table (`:DocMap checklist` and the serve tier's
---`/api/checklist`), they invoke git differently, and the part worth sharing
---— and worth testing — is the parsing, not the subprocess.
---
---`%cs` is git's own short committer date, already `YYYY-MM-DD`, so nothing
---here parses a date. Records are separated by `\30` (git's `%x1e`); within a
---record the first line is the date and the rest are the paths that commit
---touched.
---@param stdout string
---@return table<string, string[]> dates Repo-relative path -> ISO dates, newest-first as git emitted them.
function M.parse_history(stdout)
  local dates = {}
  for record in (stdout or ""):gmatch("[^\30]+") do
    local date
    for line in record:gmatch("[^\r\n]+") do
      local text = line:match("^%s*(.-)%s*$")
      if text ~= "" then
        if not date then
          date = text
        else
          local list = dates[text]
          if not list then
            list = {}
            dates[text] = list
          end
          list[#list + 1] = date
        end
      end
    end
  end
  return dates
end

---Pair every item with a staleness verdict.
---
---Pure: takes a `path -> commit dates` table somebody else produced and
---returns a ranking, the identical split `core/churn.lua` uses so the scoring
---can be driven from a headless spec with no repository at all. Counting
---commits is git's job and belongs in the command layer.
---
---Dates are compared as strings, which is correct rather than lazy: ISO-8601
---`YYYY-MM-DD` sorts lexicographically in date order, and `git log --format=%cs`
---emits exactly that. No date parsing, no timezone question, no dependency.
---
---**The comparison is `>`, not `>=`.** A commit made on the verification day
---itself does not mark the item stale. That is the deliberate cost of pinning
---to a date rather than a commit hash: same-day ordering is unknowable from a
---date alone, and of the two possible errors, "misses a same-day edit" is far
---less damaging than "flags every item the moment it is verified", which would
---make the whole ledger cry wolf and get ignored.
---@param result Documentation.Checklist.Result
---@param dates table<string, string[]> Repo-relative path -> ISO commit dates touching it, any order.
---@return Documentation.Checklist.Status[] Sorted: stale first (most commits first), then unverified, then uncited, then current.
function M.status(result, dates)
  local out = {}

  for _, file in ipairs(result.files) do
    for _, section in ipairs(file.sections) do
      for _, item in ipairs(section.items) do
        local entry = { item = item, commits = 0 }
        local history = item.ref and dates[item.ref] or nil

        if not item.ref then
          entry.state = "uncited"
        elseif not item.verified then
          entry.state = "unverified"
        else
          local newer, last = 0, nil
          for _, date in ipairs(history or {}) do
            if date > item.verified then
              newer = newer + 1
            end
            if not last or date > last then
              last = date
            end
          end
          entry.last_commit = last
          entry.commits = newer
          entry.state = newer > 0 and "stale" or "current"
        end

        -- An uncited or unverified item still deserves the cited file's last
        -- commit date when one exists, so the display can say *when* rather
        -- than only *that* something is unknown.
        if entry.last_commit == nil and history then
          for _, date in ipairs(history) do
            if not entry.last_commit or date > entry.last_commit then
              entry.last_commit = date
            end
          end
        end

        out[#out + 1] = entry
      end
    end
  end

  local rank = { stale = 1, unverified = 2, uncited = 3, current = 4 }
  table.sort(out, function(a, b)
    if rank[a.state] ~= rank[b.state] then
      return rank[a.state] < rank[b.state]
    end
    if a.commits ~= b.commits then
      return a.commits > b.commits
    end
    -- Stable tail so two runs over unchanged input produce the same order:
    -- file, then line. Without it `table.sort` is free to permute equal
    -- elements and a quickfix list reshuffles between invocations.
    if a.item.file ~= b.item.file then
      return a.item.file < b.item.file
    end
    return a.item.line < b.item.line
  end)

  return out
end

---Which cited paths exist in the scanned tree, and which do not.
---
---Kept out of `resolve` on purpose: a checklist is legitimately written
---before the code it cites, and a `@ref` may point at a file this map does
---not scan (a `scripts/` path, a config file) without that being a mistake.
---What this reports is therefore two neutral lists, not a finding — the
---caller decides whether an unresolved reference means anything.
---
---Resolution is by **file path**, not by node id: `node.id` is the
---directory's path for a module node, so the two are not interchangeable
---here — the same trap `editor/callhierarchy.lua` documents.
---@param result Documentation.Checklist.Result
---@param ir Documentation.IR
---@return string[] resolved Cited paths that back a scanned node, sorted, deduplicated.
---@return string[] unresolved Cited paths that do not, same shape.
function M.resolve_refs(result, ir)
  local sources = {}
  for _, node in pairs(ir.nodes or {}) do
    if node.source then
      sources[node.source] = true
    end
  end

  local seen, resolved, unresolved = {}, {}, {}
  for _, file in ipairs(result.files) do
    for _, section in ipairs(file.sections) do
      for _, item in ipairs(section.items) do
        if item.ref and not seen[item.ref] then
          seen[item.ref] = true
          local into = sources[item.ref] and resolved or unresolved
          into[#into + 1] = item.ref
        end
      end
    end
  end

  table.sort(resolved)
  table.sort(unresolved)
  return resolved, unresolved
end

return M
