---@module 'documentation.core.lang.asm'
--- Assembly, registered as a language backend — and the first one here that
--- deliberately parses **without** a tree-sitter grammar.
---
--- **Why no grammar, when every backend since `lua.lua` has had one.** The
--- request that produced this file said "assembly", and assembly is not one
--- language: GAS, NASM and the ARM/MASM families disagree about the comment
--- character, about whether a directive starts with `.` or `%`, and about
--- how a symbol is exported. That is a fork, not a set of dialects, and a
--- grammar is written against exactly one side of it — a `tree-sitter-asm`
--- parse of a NASM file is not a degraded parse, it is a confident wrong
--- one. What this backend actually needs — a label, an export directive, an
--- include — is line-directed in *every* one of those syntaxes, because
--- assembly is a line-oriented language by construction: one statement per
--- line, no nesting, no expression grammar to get lost in. So a line scanner
--- is not the cheap option here, it is the one that is right across the fork.
---
--- `lang_registry.report()` already keeps the two apart: `grammar = nil`
--- means "needs no parser", which is not the same answer as "wanted a
--- grammar and could not find one", and a host reading the handshake sees
--- this backend at full fidelity rather than as a broken one. It is also the
--- only backend here whose spec never skips.
---
--- **What the roadmap said assembly has none of, and what measuring found
--- instead.** `docs/ROADMAP/IDEAS/MULTILANG.md` recorded assembly as having
--- no visibility concept and no module system, and half of that was wrong:
---
--- * **Visibility is real and it is explicit.** `.globl` / `.global` (GAS,
---   ARM), `global` (NASM) and `PUBLIC` (MASM) name the symbols a file
---   publishes. That is a stronger signal than most languages here give —
---   stronger than Lua's leading underscore, and unlike C it needs no header
---   file to read it from. Everything not named in one of those is internal,
---   which is the assembler's own rule rather than this tool's guess.
--- * **The module system really is absent**, so the path is the identity,
---   exactly as Zig established and C confirmed. `module_tag = false`,
---   `module_file = nil`, a directory is a namespace.
--- * **A documentation convention really is absent — but two habits are
---   not.** There is no Doxygen here and never was, so the rules are the
---   plainest ones that could work: a run of comment lines above a label
---   documents it, and failing that the comment trailing the label itself
---   does, which is where a NASM codebase puts its calling convention.
---   Measuring decided the second one, not taste — see `doc_above`. The
---   cost is the cost C's plain-comment rule has, commented-out code
---   looking like prose, and `looks_like_prose` is the same single filter,
---   tuned to the tells assembly leaves (`%eax`, `[bx]`, a trailing `:`).
---
--- **Not every label is a function, and the file says which — twice.**
---
--- A label followed by a data directive (`.asciz`, `db`, `.space`, `resb`)
--- is storage, and reporting it as a function would put `msg` and `_start`
--- in one list. Those become `SymbolInfo` instead — as do `.equ`, `.set`
--- and NASM's `equ`, which are genuinely module-scope constants. So the map
--- of an assembly file separates code from data the way its author already
--- did.
---
--- And a label in the middle of a routine is a *branch target*, not a
--- routine. Telling the two apart is `is_routine`, and it is the one rule
--- here that a measurement rather than a reading produced — see its own
--- comment for the numbers, and for why layout turned out to be a better
--- signal than anything in the name.
---
--- **What this backend knowingly does not see**, stated rather than left to
--- be discovered: NASM's column-zero label without a colon (telling it from
--- an instruction needs a mnemonic table per architecture, which is a
--- transcription this file declines), MASM's `name PROC`, and anything a
--- macro generates. Each of those is a "found nothing" rather than a wrong
--- answer, which is the direction to fail in.

local M = {}

M.name = "asm"

---No tree-sitter grammar, by decision rather than by omission — see this
---file's header. Written as an explicit `nil` so a reader of the field list
---does not have to conclude it was forgotten.
---@type string?
M.grammar = nil

---Bare extensions this backend claims.
---
---`.s` and `.S` are one entry: the difference between them is that `.S` runs
---through the C preprocessor first, which changes what a comment looks like
---(`//` and `/* */` become legal, and `#include` appears) but not what a
---label looks like — and both are already handled below.
---
---**`inc` is claimed, with the conflict named.** It is NASM's conventional
---extension for an included macro file, and leaving it out would mean the
---`%include` edges of a real NASM project point at nodes that were never
---scanned. It is also Pascal's and PHP's include extension; no backend here
---claims either language, so the conflict is theoretical today, and
---`lang_registry`'s first-registered-wins order is where it would be
---resolved if that changed.
---@type string[]
M.extensions = { "s", "asm", "nasm", "inc" }

---The path is the identity; nothing tag-shaped can be missing.
M.module_tag = false

---What opens a comment, across the fork.
---
---All four are listed because one repository can contain all four: `;` is
---NASM/MASM and ARM's legacy syntax, `#` is GAS on x86 and RISC-V, `//` and
---`/* */` are GAS's C-style pair (and the only ones that survive a `.S`
---file's preprocessor pass), and `@` is ARM's GAS comment.
---
---`;` is first because `backend_contract_spec.lua` proves whichever token is
---first actually produces a marker, and it is the one no architecture in
---scope gives a second meaning. `#` is the one that does — an ARM immediate
---is `#1` — which costs nothing here: a marker needs `TODO:`-shaped text
---after the token, and `1` is not.
---@type string[]
M.line_comments = { ";", "#", "//", "@" }

---@type { [1]: string, [2]: string }[]
M.block_comments = { { "/*", "*/" } }

---No glossary. An assembly keyword glossary is an instruction-set
---transcription, and there are three instruction sets in scope here that
---disagree — `mov` alone means the opposite operand order in GAS and NASM.
---`Documentation.LangBackend.glossary` calls the absent case the honest
---degradation for exactly this shape of problem: no decoration at all,
---rather than one architecture's meaning shown over another's code.
M.glossary = nil

---@param filename string
---@return boolean
function M.is_source(filename)
  local lower = filename:lower()
  return lower:match("%.s$") ~= nil
    or lower:match("%.asm$") ~= nil
    or lower:match("%.nasm$") ~= nil
    or lower:match("%.inc$") ~= nil
end

---Where this backend's sources live under `root`, or `nil`.
---
---The candidate list is longer than the other backends' because assembly
---rarely lives in a directory named after itself: it lives in `boot/`,
---`arch/` or `kernel/` in the projects that are mostly assembly, and in
---`src/` in the ones that are not.
---@param root string
---@return string?
function M.detect_source(root)
  local uv = vim.uv or vim.loop
  local function holds_asm(dir)
    local fd = uv.fs_scandir(dir)
    if not fd then
      return false
    end
    while true do
      local name, kind = uv.fs_scandir_next(fd)
      if not name then
        return false
      end
      if kind ~= "directory" and M.is_source(name) then
        return true
      end
    end
  end

  for _, candidate in ipairs({ "src", "asm", "boot", "kernel", "arch", "lib", "source" }) do
    if holds_asm(root .. "/" .. candidate) then
      return candidate
    end
  end
  if holds_asm(root) then
    return "."
  end
  return nil
end

---@param path string
---@return string?
local function read(path)
  local fd = io.open(path, "rb")
  if not fd then
    return nil
  end
  local src = fd:read("*a")
  fd:close()
  return src
end

---Split one line into its code and its comment, carrying block state.
---
---**`#` only opens a comment when it is not `#include`.** A `.S` file is
---C-preprocessed, so `#include "macros.h"` is an ordinary line there;
---treating its `#` as a comment opener would make every include in every
---`.S` file invisible, which is the quiet failure this whole family of
---decisions exists to avoid.
---
---Quoting is not tracked. A `;` inside `.asciz "a;b"` truncates the code
---half of that line — which costs nothing, because a string literal is
---never a label and never an include, and the alternative is a quoting model
---per syntax for no gain.
---@param line string
---@param in_block boolean Whether a `/*` was left open by an earlier line.
---@return string code
---@return string? comment
---@return boolean in_block
local function split_line(line, in_block)
  if in_block then
    local close = line:find("%*/")
    if not close then
      return "", line, true
    end
    local head = line:sub(1, close - 1)
    local code, comment = split_line(line:sub(close + 2), false)
    return code, head .. (comment and ("\n" .. comment) or ""), false
  end

  local open = line:find("/%*")
  if open then
    local before = line:sub(1, open - 1)
    local after = line:sub(open + 2)
    local close = after:find("%*/")
    if close then
      local tail_code, tail_comment = split_line(after:sub(close + 2), false)
      local body = after:sub(1, close - 1)
      return before .. " " .. tail_code,
        body .. (tail_comment and ("\n" .. tail_comment) or ""),
        false
    end
    return before, after, true
  end

  local best = nil
  for _, token in ipairs({ ";", "//", "@" }) do
    local at = line:find(token, 1, true)
    if at and (not best or at < best) then
      best = at
    end
  end
  local hash = line:find("#", 1, true)
  if hash and not line:match("^%s*#%s*include") and (not best or hash < best) then
    best = hash
  end
  if not best then
    return line, nil, false
  end
  return line:sub(1, best - 1), (line:sub(best):gsub("^[;/@#]+%s?", "")), false
end

---Every line of `src`, split into code and comment.
---@param src string
---@return { code: string, comment: string?, blank: boolean }[]
local function read_lines(src)
  local out, in_block = {}, false
  for raw in (src .. "\n"):gmatch("([^\n]*)\n") do
    local code, comment
    code, comment, in_block = split_line(raw, in_block)
    out[#out + 1] = {
      code = code,
      comment = comment,
      blank = raw:match("^%s*$") ~= nil,
    }
  end
  return out
end

---Whether a comment block is prose rather than instructions somebody
---switched off.
---
---The job `cfamily.lua`'s filter of the same name does, against different
---tells. Assembly's commented-out code is not punctuated like C's — it ends
---in no semicolon — so the giveaways are the sigils no sentence contains
---(`%eax`, `$0x10`), a memory operand (`[bx+2]`), and a trailing colon,
---which is a label somebody commented out.
---@param lines string[]
---@return boolean
local function looks_like_prose(lines)
  for _, line in ipairs(lines) do
    local bare = line:gsub("^%s+", ""):gsub("%s+$", "")
    if bare ~= "" then
      if bare:match(":$") then
        return false
      end
      if bare:match("%%%a") or bare:match("%$%-?%w") then
        return false
      end
      if bare:match("%[%s*[%w_%+%-%*%s]+%s*%]") then
        return false
      end
    end
  end
  return true
end

---Drop separator lines — a row of `;;;;;;;;` or `********` is punctuation,
---not a sentence, and it is how half of all assembly banners are drawn.
---@param block string[]
---@return string[]
local function without_rules(block)
  local kept = {}
  for _, line in ipairs(block) do
    if not line:match("^[%-%*=_;#/%s]+$") then
      kept[#kept + 1] = line
    end
  end
  return kept
end

---What documents the label on line `idx`: the run of comment lines above
---it, or failing that the comment trailing the label itself.
---
---**The trailing comment is not a fallback for tidiness — it is the second
---convention, and measuring found it is the more common one.** Reading only
---the block above found 5 documented routines out of 63 in
---`nemasu/asmttpd`, a real 2334-line NASM server whose routines are almost
---all annotated: it writes
---`add_content_type_header: ;rdi - pointer to buffer, rsi - type` — the
---calling convention, on the label's own line, which is the closest thing
---assembly has to a parameter list. Reporting those as undocumented would
---repeat exactly the mistake the Doxygen-only rule made about C, in a
---language with far less excuse for insisting on a house style.
---
---The block above wins when both exist: it is the longer statement, and a
---trailing note beside it is a detail rather than the summary.
---@param lines { code: string, comment: string?, blank: boolean }[]
---@param idx integer 1-based index of the documented line.
---@return string
local function doc_above(lines, idx)
  local block = {}
  local i = idx - 1
  while i >= 1 and lines[i].comment and lines[i].code:match("^%s*$") do
    table.insert(block, 1, (lines[i].comment:gsub("^%s+", ""):gsub("%s+$", "")))
    i = i - 1
  end
  if #block > 0 and looks_like_prose(block) then
    local kept = without_rules(block)
    if #kept > 0 then
      return table.concat(kept, "\n")
    end
  end

  local trailing = lines[idx] and lines[idx].comment
  if trailing then
    local one = { (trailing:gsub("^%s+", ""):gsub("%s+$", "")) }
    if one[1] ~= "" and looks_like_prose(one) and #without_rules(one) > 0 then
      return one[1]
    end
  end
  return ""
end

---Names this file exports, from whichever directive its syntax uses.
---
---`.globl a, b` takes a list; NASM's `global a:function` carries a type
---suffix after a colon. Both are reduced to bare names here so the caller
---asks one question.
---@param lines { code: string, comment: string?, blank: boolean }[]
---@return table<string, boolean>
local function exported_names(lines)
  local out = {}
  for _, entry in ipairs(lines) do
    local list = entry.code:match("^%s*%.?globa?l%s+(.+)$")
      or entry.code:match("^%s*%.export%s+(.+)$")
      or entry.code:match("^%s*[Pp][Uu][Bb][Ll][Ii][Cc]%s+(.+)$")
    if list then
      for name in list:gmatch("[^,%s]+") do
        out[(name:gsub(":.*$", ""))] = true
      end
    end
  end
  return out
end

---Data directives, and whether what follows one is a literal.
---
---`true` means the directive writes a value out at the label (`.asciz "hi"`,
---`dd 1`), so the value itself is worth carrying as the symbol's detail.
---`false` means it reserves space (`.space 64`, `resb 8`), where the
---interesting fact is the size and there is no literal.
local DATA_DIRECTIVES = {
  [".byte"] = true,
  [".word"] = true,
  [".hword"] = true,
  [".short"] = true,
  [".long"] = true,
  [".int"] = true,
  [".quad"] = true,
  [".octa"] = true,
  [".float"] = true,
  [".double"] = true,
  [".ascii"] = true,
  [".asciz"] = true,
  [".string"] = true,
  ["db"] = true,
  ["dw"] = true,
  ["dd"] = true,
  ["dq"] = true,
  ["dt"] = true,
  [".space"] = false,
  [".skip"] = false,
  [".zero"] = false,
  [".fill"] = false,
  [".comm"] = false,
  [".lcomm"] = false,
  ["resb"] = false,
  ["resw"] = false,
  ["resd"] = false,
  ["resq"] = false,
}

---The data directive a label is followed by, if any.
---
---Looks on the label's own line first (`msg: .asciz "hi"`, which is how it
---is usually written) and then at the next line carrying code, skipping
---blanks and comments — because the two-line form is equally common and the
---difference is formatting, not meaning.
---@param lines { code: string, comment: string?, blank: boolean }[]
---@param idx integer
---@param rest string Whatever followed the colon on the label's own line.
---@return string? directive
---@return string operand
local function data_after(lines, idx, rest)
  local function classify(text)
    local word, operand = text:match("^%s*([%.%a][%w_%.]*)%s*(.*)$")
    if word and DATA_DIRECTIVES[word:lower()] ~= nil then
      return word:lower(), (operand:gsub("%s+$", ""))
    end
    return nil, ""
  end

  local word, operand = classify(rest)
  if word then
    return word, operand
  end
  local i = idx + 1
  while lines[i] and lines[i].code:match("^%s*$") do
    i = i + 1
  end
  if lines[i] then
    return classify(lines[i].code)
  end
  return nil, ""
end

---The include target on a line, already made relative-resolvable.
---
---**The `./` prefix is added here on purpose.** `deps.lua`'s
---`resolve_relative` only follows a specifier starting with `./` or `../` —
---a bare name is a package everywhere else in this tool. In assembly a bare
---`%include "macros.inc"` means "the file beside me", which is what
---`./macros.inc` says in the vocabulary the resolver already speaks. Without
---this, an assembly project's internal includes would all land in
---`requires_external` and its Deps view would be empty of exactly the edges
---it exists to draw.
---@param code string
---@return string?
local function include_target(code)
  local target = code:match('^%s*%%include%s+"([^"]+)"')
    or code:match('^%s*%.include%s+"([^"]+)"')
    or code:match('^%s*#%s*include%s+"([^"]+)"')
    or code:match("^%s*[Ii][Nn][Cc][Ll][Uu][Dd][Ee]%s+([%w_%./\\%-]+)%s*$")
  if not target then
    return nil
  end
  target = target:gsub("\\", "/")
  if target:sub(1, 1) == "/" or target:sub(1, 2) == "./" or target:sub(1, 3) == "../" then
    return target
  end
  return "./" .. target
end

---Whether a line of code is a label definition, what follows it, and
---whether it starts in column zero.
---
---The third answer is the one that turned out to matter — see
---`is_routine`.
---@param code string
---@return string? name
---@return string rest
---@return boolean flush Whether the label starts at column zero.
local function label_on(code)
  local name, rest = code:match("^%s*([%.%w_%$%?][%w_%.%$%?]*)%s*:%s*(.*)$")
  if not name then
    return nil, "", false
  end
  return name, rest, code:match("^[%.%w_%$%?]") ~= nil
end

---Whether a label names a routine, or is a branch target inside one.
---
---**This rule came out of a measurement, and the measurement changed the
---design.** A first version reported every label as an entity. Against
---`nemasu/asmttpd` — a real 2334-line NASM web server — that produced 129
---"functions" for a program with about sixty, because assembly's branch
---targets are labels too: `create_http206_response_ret`,
---`detect_content_type_ret`, `worker_thread_continue`. A map whose function
---list is two-thirds jump labels is wrong about the one thing it exists to
---show, the same way the Doxygen-only rule was wrong about C.
---
---The signal is layout, and it is the one every assembly file already uses:
---**a routine's label starts in column zero, a branch target is indented
---with the instructions it belongs to.** Measured: asmttpd is 61 flush and
---76 indented, and `musl`'s 304 assembly sources are 579 flush and *zero*
---indented — so the rule removes the noise where there is noise and costs
---nothing where there is none, which is the property that made it worth
---taking over a naming heuristic.
---
---Two guards, because a layout rule that is wrong is wrong silently:
---
--- * A file whose labels are *all* indented is one where indentation carries
---   no information, so `indented_only` switches the rule off for that file
---   rather than reporting a file full of routines as empty.
--- * A dotted label is dropped whatever its column. That is not a guess
---   about style: `.L` in GAS never reaches the symbol table, and a NASM
---   `.name` is scoped to the label above it — both are the assembler
---   saying outright that this is a jump target, not a name.
---@param label string
---@param flush boolean Whether it starts in column zero.
---@param indented_only boolean Whether this file has no flush label at all.
---@return boolean
local function is_routine(label, flush, indented_only)
  if label:sub(1, 1) == "." then
    return false
  end
  return flush or indented_only
end

---@param path string
---@return Documentation.Header
function M.parse_header(path)
  local empty = { module = nil, summary = "", body = "", tags = {} }
  local src = read(path)
  if not src then
    return empty
  end
  local lines = read_lines(src)

  -- The header is the first run of comment-only lines in the file, after any
  -- blank ones.
  local i = 1
  while lines[i] and lines[i].blank do
    i = i + 1
  end
  local block = {}
  while lines[i] and lines[i].comment and lines[i].code:match("^%s*$") do
    block[#block + 1] = (lines[i].comment:gsub("^%s+", ""):gsub("%s+$", ""))
    i = i + 1
  end
  if #block == 0 or not looks_like_prose(block) then
    return empty
  end

  -- **A block sitting directly on top of a label documents the label, not
  -- the file.** C tells the two apart by punctuation — a file header is
  -- Doxygen-style `/**`. Assembly has no such mark, so position is the only
  -- evidence there is: something separated from the code below it is about
  -- the file, something touching it is about the thing it touches. Claiming
  -- both would put one paragraph in two places on the page.
  if lines[i] and label_on(lines[i].code) then
    return empty
  end

  -- A license banner is a summary of nothing, and it is the single most
  -- common thing at the top of an assembly file. The judgement C's
  -- Doxygen-only file rule makes, reached by content because there is no
  -- punctuation here to reach it by.
  local probe = table.concat(block, "\n"):lower()
  if
    probe:match("copyright")
    or probe:match("spdx%-license")
    or probe:match("all rights reserved")
    or probe:match("permission is hereby")
    or probe:match("licensed under")
    or probe:match("gnu general public")
  then
    return empty
  end

  local kept = without_rules(block)
  if #kept == 0 then
    return empty
  end
  local prose = table.concat(kept, "\n")
  return {
    module = nil,
    summary = require("documentation.core.scan").split_summary(prose),
    body = prose,
    tags = {},
  }
end

---@param path string
---@return Documentation.FunctionInfo[], Documentation.RawCall[], Documentation.RawRequire[], Documentation.SymbolInfo[], table[], Documentation.EndpointSpec[], integer, Documentation.BindingSpec[]
function M.scan_file(path)
  local src = read(path)
  if not src then
    return {}, {}, {}, {}, {}, {}, 0, {}
  end
  local _, newlines = src:gsub("\n", "")
  local count = #src == 0 and 0 or (newlines + (src:sub(-1) == "\n" and 0 or 1))

  local split = require("documentation.core.scan").split_summary
  local lines = read_lines(src)
  local exported = exported_names(lines)

  -- Whether any label in this file starts in column zero. Needed before the
  -- walk rather than during it, since it decides how to read the very first
  -- label — see `is_routine`.
  local indented_only = true
  for _, entry in ipairs(lines) do
    local _, _, flush = label_on(entry.code)
    if flush then
      indented_only = false
      break
    end
  end

  -- `.type name, @object` is GAS saying outright what a label is. It wins
  -- over the directive sniffing below, being a statement rather than an
  -- inference.
  local declared = {}
  for _, entry in ipairs(lines) do
    local name, kind = entry.code:match("^%s*%.type%s+([%w_%.%$%?]+)%s*,%s*[@%%#]?(%a+)")
    if name then
      declared[name] = kind:lower()
    end
  end

  local fns, requires, symbols = {}, {}, {}

  for idx, entry in ipairs(lines) do
    local target = include_target(entry.code)
    if target then
      requires[#requires + 1] = { module = target, line = idx }
    end

    -- `.equ NAME, 4` and NASM's `NAME equ 4` are one statement in two word
    -- orders; `NAME = 4` is GAS's third spelling of it.
    local cname, cvalue = entry.code:match("^%s*%.equ%s+([%w_%.%$%?]+)%s*,%s*(.+)$")
    if not cname then
      cname, cvalue = entry.code:match("^%s*%.set%s+([%w_%.%$%?]+)%s*,%s*(.+)$")
    end
    if not cname then
      cname, cvalue = entry.code:match("^%s*([%w_%.%$%?]+)%s+[Ee][Qq][Uu]%s+(.+)$")
    end
    if not cname then
      cname, cvalue = entry.code:match("^%s*([%w_%.%$%?]+)%s*=%s*(.+)$")
    end

    if cname then
      symbols[#symbols + 1] = {
        name = cname,
        kind = "constant",
        detail = (cvalue:gsub("%s+$", "")),
        summary = split(doc_above(lines, idx)),
        line = idx,
      }
    else
      local label, rest, flush = label_on(entry.code)
      -- A purely numeric label (`1:`, jumped to as `1f`/`1b`) is a branch
      -- target with no identity beyond the next few instructions. Naming it
      -- in a map would fill the list with entries that mean nothing outside
      -- the twenty lines around them.
      if label and not label:match("^%d+$") then
        local prose = doc_above(lines, idx)
        local summary = split(prose)
        local directive, operand = data_after(lines, idx, rest)
        local kind = declared[label]
        if kind == "function" then
          directive = nil
        end
        if directive or kind == "object" then
          symbols[#symbols + 1] = {
            name = label,
            kind = (directive and DATA_DIRECTIVES[directive]) and "constant" or "binding",
            detail = directive and (operand ~= "" and (directive .. " " .. operand) or directive)
              or "object",
            summary = summary,
            line = idx,
          }
        elseif is_routine(label, flush, indented_only) then
          fns[#fns + 1] = {
            name = label,
            -- Written as it appears in the file. A label has no parameter
            -- list to put here, and inventing `()` would claim a calling
            -- convention this backend cannot see.
            signature = label .. ":",
            line = idx,
            summary = summary,
            body = prose,
            params = {},
            returns = {},
            internal = not exported[label],
            see = {},
            overload = {},
            todo = {},
            bug = {},
            test = {},
          }
        end
      end
    end
  end

  return fns, {}, requires, symbols, {}, {}, count, {}
end

require("documentation.core.lang_registry").register(M.name, M)

return M
