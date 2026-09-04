---@module 'documentation.core.features'
--- Reads a repo's own `docs/FEATURES/` folder into
--- `Documentation.Features.Result` for the Features tab.
---
--- See `docs/features_format.md` for the full field guide this parser
--- implements — a `##`-per-feature, `- **Key:** value`-metadata convention
--- deliberately closest to `markdown.nvim`'s own real `docs/FEATURES/`, the
--- one of three independently-invented shapes found across this user's
--- plugins that is both ordinary prose and mechanically recognizable
--- line-by-line, no CommonMark parser needed — same "cheap reliable reading
--- beats a general one" discipline `core/deps.lua`'s require-extraction and
--- `lib.nvim.deps.spec`'s fenced-block parsing already use.
---
--- No validation, unlike `core/tools.lua`: that format feeds an installer,
--- so a missing `why` is a real defect. This one feeds a reader, and
--- `markdown.nvim`'s own real `docs/FEATURES/headings.md` already mixes
--- `Module`/`Keymaps`/`Config` with one-off keys in the same file — a
--- whitelist would reject working documentation that predates this parser.
--- A theme file with zero `##` sections, or a feature with zero metadata
--- bullets, is not an error; both are real, valid states.

local M = {}

local uv = vim.uv

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

--- Candidate folder names, in resolution order — uppercase preferred,
--- matching `docs/BINDINGS.md`'s own convention, same "first match wins"
--- shape `lib.nvim.deps.spec`'s `SPEC_FILES` uses for install.json/
--- INSTALL.md.
---
--- The *default* list, since `opts.features_dir` — a repository whose prose
--- lives under `documentation/` rather than `docs/` — replaces it. Still a
--- list either way: "first match wins" is what lets a project keep both
--- spellings on a case-sensitive filesystem while it renames one.
local CANDIDATE_FOLDERS = { "docs/FEATURES", "docs/features" }

--- Files that come first inside a features folder, in this order, before the
--- rest sorts alphabetically.
---
--- `core` first because it is the answer to "why would I install this" — the
--- handful of features the plugin exists for, ahead of the ones it grew. Then
--- `FEATURES`, which is where a repo that has outgrown a single file keeps the
--- overview of everything that is *not* singled out. Everything else follows
--- in name order, as before.
---
--- Matched case-insensitively against the theme name (the file name without
--- `.md`), so `CORE.md`, `core.md` and `Core.md` all land in the same slot.
local LEADING_THEMES = { "core", "features" }

---Sort key for a theme file: leading themes by their position in
---`LEADING_THEMES`, everything else after them.
---@param theme string File name without `.md`.
---@return integer
local function theme_rank(theme)
  local lowered = theme:lower()
  for i, leading in ipairs(LEADING_THEMES) do
    if lowered == leading then
      return i
    end
  end
  return #LEADING_THEMES + 1
end

---One `- **Key:** value` bullet.
---@param line string Already right-trimmed.
---@return string|nil key
---@return string value Empty string when there is no key, and when the bullet has a key with nothing after the colon. Never nil, so a caller that checked `key` does not have to check this one too.
local function match_bullet(line)
  -- The colon sits *inside* the bold markers (`**Key:**`), not after them
  -- (`**Key**:`) — confirmed against markdown.nvim's own real
  -- `docs/FEATURES/headings.md`, which is what this format is modelled on.
  local key, value = line:match("^%-%s*%*%*([^*:]+):%*%*%s*(.*)$")
  if not key then
    return nil, ""
  end
  return (key:match("^%s*(.-)%s*$")), (value:match("^%s*(.-)%s*$"))
end

---Split into lines, `\n`-terminated tail included so the last real line is
---never dropped — same idiom `core/deps.lua`'s `extract_source` uses.
---@param text string
---@return string[]
local function to_lines(text)
  local out = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    out[#out + 1] = line
  end
  -- The trailing empty string from a file that already ends in "\n" is not
  -- a real line and would otherwise read as a spurious paragraph break.
  if out[#out] == "" then
    out[#out] = nil
  end
  return out
end

---Everything from `start_idx` to `end_idx` (inclusive) that belongs to one
---feature: a summary (the leading run of non-bullet prose lines) and a
---metadata block (the contiguous run of bullets immediately after it).
---
---A bullet's own value routinely wraps onto an **indented** continuation
---line — confirmed against markdown.nvim's real `docs/FEATURES/headings.md`,
---where `- **Module:** ...(` regularly continues on the next line with a
---2-space-indented function list. Such a line is folded into the value of
---the bullet it continues, not treated as ending the run. A **blank** line,
---or a non-bullet line with **no** leading indent (a new flush-left
---paragraph — prose written after the metadata, with no blank separator),
---ends the run for good: neither case is a continuation of anything.
---@param lines string[]
---@param start_idx integer
---@param end_idx integer
---@return string|nil summary
---@return Documentation.Features.Meta[] meta
---@return integer|nil body_start_idx The line right after the metadata run ended — where a `Tab: true` feature's rich body begins. `nil` when the run never started (no bullets at all; see `parse_file`'s promoted-feature handling for what that means for `body`).
local function parse_body(lines, start_idx, end_idx)
  local summary_parts = {}
  ---@type Documentation.Features.Meta[]
  local meta = {}
  -- "before" the first bullet, "in" a contiguous bullet run, or "after" one
  -- that has ended — once "after", every remaining line is inert.
  local state = "before"
  local body_start_idx = nil

  for i = start_idx, end_idx do
    local raw = lines[i]
    local trimmed = raw:match("^%s*(.-)%s*$")
    local key, value = match_bullet(trimmed)

    if state == "before" then
      if key then
        meta[#meta + 1] = { key = key, value = value }
        state = "in"
      elseif trimmed ~= "" then
        summary_parts[#summary_parts + 1] = trimmed
      end
    elseif state == "in" then
      if key then
        meta[#meta + 1] = { key = key, value = value }
      elseif trimmed == "" then
        state = "after"
        body_start_idx = i + 1
      elseif raw:match("^%s") then
        local last = meta[#meta]
        last.value = last.value .. " " .. trimmed
      else
        state = "after"
        body_start_idx = i
      end
    end
  end

  return (#summary_parts > 0 and table.concat(summary_parts, " ") or nil), meta, body_start_idx
end

---One theme file: `# Title` + intro prose (optional) before the first `##`,
---then one `Documentation.Features.Entry` per `## <name>` section.
---@param path string Absolute path.
---@param rel string Repo-relative path, for `Documentation.Features.File.path`.
---@param theme string Filename without extension, as the author wrote it.
---@return Documentation.Features.File|nil `nil` when the file could not be read.
local function parse_file(path, rel, theme)
  local text = read_file(path)
  if not text then
    return nil
  end
  local lines = to_lines(text)

  -- Section boundaries first: every `## ` line, plus a sentinel one past
  -- the end so the last section's body has a real stop index.
  ---@type { name: string, line: integer, start_idx: integer }[]
  local headings = {}
  for i, line in ipairs(lines) do
    local name = line:match("^##%s+(.-)%s*$")
    if name then
      headings[#headings + 1] = { name = name, line = i, start_idx = i + 1 }
    end
  end

  -- Everything before the first `##` (skipping a leading `# Title` line, if
  -- any) is the file's own intro — optional, same as a feature's own
  -- summary is optional.
  local first_section_line = headings[1] and headings[1].line or (#lines + 1)
  local intro_start = 1
  if lines[1] and lines[1]:match("^#%s") then
    intro_start = 2
  end
  local intro = parse_body(lines, intro_start, first_section_line - 1)

  ---@type Documentation.Features.Entry[]
  local entries = {}
  for i, h in ipairs(headings) do
    local end_idx = (headings[i + 1] and headings[i + 1].line - 1) or #lines
    local summary, meta, body_start_idx = parse_body(lines, h.start_idx, end_idx)

    -- `Tab: true` is a control directive, not something a reader wants to
    -- see rendered as an ordinary "Tab: true" metadata row — pulled out of
    -- `meta` here rather than filtered client-side, so the IR never carries
    -- a bullet the page is going to hide again.
    local tab = false
    ---@type Documentation.Features.Meta[]
    local visible_meta = {}
    for _, m in ipairs(meta) do
      if m.key:lower() == "tab" and m.value:lower() == "true" then
        tab = true
      else
        visible_meta[#visible_meta + 1] = m
      end
    end

    -- The rich body only exists for a promoted feature — a card never
    -- renders it, so there is no reason to carry it for every other feature
    -- in the tree. `body_start_idx` is only ever nil here because `tab`
    -- itself is a bullet (see the loop above): a promoted feature always
    -- has at least one, so `parse_body` never falls back to folding the
    -- whole section into `summary` the way a truly bullet-less feature
    -- would. `body` stays nil when nothing actually follows the metadata
    -- block — a promoted feature can be title+summary+metadata only, same
    -- as an ordinary card; that's a real state, not a parse failure.
    local body = nil
    if tab and body_start_idx and body_start_idx <= end_idx then
      local body_lines = {}
      for li = body_start_idx, end_idx do
        body_lines[#body_lines + 1] = lines[li]
      end
      local joined = table.concat(body_lines, "\n"):match("^%s*(.-)%s*$")
      if joined ~= "" then
        body = joined
      end
    end

    entries[#entries + 1] = {
      name = h.name,
      line = h.line,
      summary = summary,
      meta = visible_meta,
      tab = tab,
      body = body,
    }
  end

  return { path = rel, theme = theme, intro = intro, entries = entries }
end

---Single-file fallback: `docs/FEATURES.md` instead of `docs/FEATURES/`.
---
---A small plugin has no reason to spread a dozen features over a folder, and
---nine of the sibling repos had picked the single file — where `resolve` used
---to return nil, so the Features tab said "no features" for a perfectly good
---catalogue. The parse is identical: `parse_file` does not care whether its
---file has siblings.
---
---The folder wins when a repo has both, so a repo splitting a grown
---`FEATURES.md` into themes can leave the old file in place until it is done.
---@param normalized string Repo root, forward slashes, no trailing separator.
---@param candidates string[] The folder candidates; each gets `.md` appended.
---@return Documentation.Features.Result|nil
local function resolve_single_file(normalized, candidates)
  for _, candidate in ipairs(candidates) do
    local rel = candidate .. ".md"
    local abs = normalized .. "/" .. rel
    if uv.fs_stat(abs) then
      local theme = candidate:match("([^/]+)$") or candidate
      local file = parse_file(abs, rel, theme)
      if file then
        return { folder = rel, intro = nil, files = { file } }
      end
      return nil
    end
  end
  return nil
end

---@param root string Repo root (`ctx.cfg.root` / `opts.root`).
---@param dirs string|string[]|nil `opts.features_dir`. Absent means `CANDIDATE_FOLDERS`.
---@return Documentation.Features.Result|nil result `nil` when this repo ships neither a features folder nor a single features file.
function M.resolve(root, dirs)
  local normalized = (root:gsub("\\", "/"):gsub("/+$", ""))

  local candidates = require("documentation.config").dir_list(dirs, CANDIDATE_FOLDERS)

  local folder
  for _, candidate in ipairs(candidates) do
    if is_dir(normalized .. "/" .. candidate) then
      folder = candidate
      break
    end
  end
  if not folder then
    return resolve_single_file(normalized, candidates)
  end
  local abs_folder = normalized .. "/" .. folder

  -- README.md (or readme.md) is the folder's own intro, read separately —
  -- never itself a theme file, the same way a plugin's top-level README is
  -- never scanned as a module.
  local intro
  for _, name in ipairs({ "README.md", "readme.md" }) do
    local text = read_file(abs_folder .. "/" .. name)
    if text then
      local trimmed = text:match("^%s*(.-)%s*$")
      intro = trimmed ~= "" and trimmed or nil
      break
    end
  end

  ---@type Documentation.Features.File[]
  local files = {}
  local iter = vim.fs.dir(abs_folder)
  if iter then
    ---@type string[]
    local names = {}
    for name, type_ in iter do
      if type_ == "file" and name:match("%.md$") and name:lower() ~= "readme.md" then
        names[#names + 1] = name
      end
    end
    -- `core` first, then `FEATURES`, then the rest by name — see
    -- `LEADING_THEMES`. Name order alone put ARCHITECTURE above CORE, which
    -- is the opposite of the order somebody reads them in.
    table.sort(names, function(a, b)
      local ra, rb = theme_rank(a:gsub("%.md$", "")), theme_rank(b:gsub("%.md$", ""))
      if ra ~= rb then
        return ra < rb
      end
      return a < b
    end)
    for _, name in ipairs(names) do
      local theme = name:gsub("%.md$", "")
      local file = parse_file(abs_folder .. "/" .. name, folder .. "/" .. name, theme)
      if file then
        files[#files + 1] = file
      end
    end
  end

  return { folder = folder, intro = intro, files = files }
end

return M
