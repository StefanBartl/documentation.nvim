-- TESTS/fence_render_spec.lua — fenced blocks reach the page as highlighted code
--
-- The sibling `prose_render_spec.lua` opens by stating what it cannot do:
-- `prose()` runs in the browser, so "no Lua spec can see a `<code>` element",
-- and it settles for asserting the *routing* instead. That was the honest
-- answer for what it could reach. This file goes the other way, because it
-- can: the artifact's JavaScript is plain text in `html.lua`, `node` is a
-- normal thing to have, and the fence renderer is a pure string-to-string
-- function with no DOM in it.
--
-- So the pure helpers are lifted out of the embedded `JS` string and run in
-- `node` against real inputs. Without `node` the file skips rather than
-- fails — the same stance the rest of this ecosystem takes towards an
-- optional external tool.
--
-- **Why lifting is safe here and would not be in general.** `extract` counts
-- braces without tracking strings or regex literals, which is wrong for
-- JavaScript at large. It is right for exactly these seven definitions, none
-- of which contains a brace inside a string or a pattern — and if that ever
-- stops being true, `node` reports a syntax error rather than a wrong result.
-- A test helper is allowed to be narrow as long as it fails loudly.

---@param H table harness from TESTS/run.lua
return function(H)
  local eq, ok = H.eq, H.ok

  local root = (vim.fn.getcwd():gsub("\\", "/"))
  local path = root .. "/lua/documentation/core/render/html.lua"
  local fd = assert(io.open(path, "rb"), "fence spec: html.lua must be readable")
  local src = fd:read("*a")
  fd:close()

  -- ── The routing guarantee, which holds with or without node ──────────────
  --
  -- One fence renderer on the page. The Features tab split fences before this
  -- existed and wrote its own `<pre><code>`; a second renderer beside
  -- `fenceHTML` would give the same Lua two looks on one page, which is the
  -- failure `prose()`'s own comment warns about.
  local pre_code = 0
  for _ in src:gmatch('"<pre><code>"') do
    pre_code = pre_code + 1
  end
  eq(
    pre_code,
    0,
    "fence: nothing writes its own <pre><code> — every fence goes through fenceHTML"
  )

  ok(
    src:find("function fenceHTML(src, lang){", 1, true) ~= nil,
    "fence: the page defines one fence renderer"
  )
  ok(
    src:find('el.closest("[data-path]")', 1, true) ~= nil,
    "fence: the keyword card looks the language up by data-path, not by a container class — "
      .. "otherwise a keyword inside a fence finds nothing"
  )

  -- ── The behaviour, which needs node ──────────────────────────────────────
  if vim.fn.executable("node") == 0 then
    return
  end

  --- Lift one `function name(...){...}` or `var NAME = {...};` out of `src`.
  ---@param decl string exact opening text, e.g. "function prose(s){"
  ---@return string
  local function extract(decl)
    local start = src:find(decl, 1, true)
    assert(start, "fence spec: cannot find " .. decl)
    local open = src:find("{", start + #decl - 1, true)
    assert(open, "fence spec: no brace after " .. decl)
    local depth, i = 0, open
    while i <= #src do
      local ch = src:sub(i, i)
      if ch == "{" then
        depth = depth + 1
      elseif ch == "}" then
        depth = depth - 1
        if depth == 0 then
          break
        end
      end
      i = i + 1
    end
    assert(depth == 0, "fence spec: unbalanced braces in " .. decl)
    return src:sub(start, i)
  end

  local lifted = table.concat({
    extract("function esc(s){"),
    extract("function prose(s){"),
    extract("var FENCE_EXT = {") .. ";",
    extract("function fenceHTML(src, lang){"),
    extract("function richText(s){"),
    extract("function exampleHTML(s){"),
    extract("function glossaryForPath(path){"),
    extract("function snipBodyHTML(src, path){"),
  }, "\n\n")

  -- A glossary in the shape `lang_registry.glossaries()` produces: keyed by
  -- file extension, `syntax` carrying the delimiters `snipBodyHTML` needs to
  -- skip strings and comments.
  -- `[==[` rather than `[[`: the glossary literal below contains `]]`
  -- (a nested JavaScript array), which would close a plain long bracket.
  local harness = [==[
const IR = { glossaries: { lua: {
  keywords: { ["local"]: { summary: "a local" }, ["function"]: { summary: "a function" } },
  stdlib:   { ["table.concat"]: { summary: "joins a list" } },
  syntax:   { line_comment: "--", strings: [['"', '"'], ["'", "'"]], escape: "\\" }
} } };

]==] .. lifted .. [==[


const results = [];
function check(name, actual, want){ results.push({ name, actual, want, ok: actual === want }); }
function has(name, actual, needle){ results.push({ name, actual, want: "contains " + needle, ok: actual.indexOf(needle) >= 0 }); }
function hasNot(name, actual, needle){ results.push({ name, actual, want: "without " + needle, ok: actual.indexOf(needle) < 0 }); }

// Prose with no fence is handed straight to prose(), unchanged behaviour.
check("plain prose is untouched", richText("plain `code` here"), prose("plain `code` here"));
has("inline code still renders", richText("a `b` c"), "<code>b</code>");

// A fence becomes a block, and the text around it stays prose.
const mixed = richText("before\n```lua\nlocal x = 1\n```\nafter `y`");
has("prose before the fence survives", mixed, "before");
has("the fence becomes a pre", mixed, '<pre class="fence"');
has("prose after the fence survives", mixed, "<code>y</code>");
hasNot("the fence markers are gone", mixed, "```");

// The language reaches the tokenizer: `local` is a Lua keyword and gets the
// same decoration a source snippet would give it.
has("a lua fence is highlighted", mixed, 'data-kw="local"');
has("the container carries the path the keyword card looks up", mixed, 'data-path="fence.lua"');
has("and the info string, for inspection", mixed, 'data-lang="lua"');

// An alias that is not a declared extension still finds its glossary shape.
has("aliases map to the extension", fenceHTML("x", "python"), 'data-path="fence.py"');
has("the raw info string is kept as written", fenceHTML("x", "python"), 'data-lang="python"');

// A language nothing knows degrades to plain escaped text, no decoration.
const unknown = fenceHTML("<b>x</b> local", "brainfuck");
has("an unknown language still renders as a block", unknown, '<pre class="fence"');
has("...escaped", unknown, "&lt;b&gt;");
hasNot("...and undecorated", unknown, "data-kw");

// A fence with no info string at all: a block, no glossary, no path.
const bare = richText("```\nlocal x\n```");
has("a bare fence is still a block", bare, '<pre class="fence"');
hasNot("...with no path to look anything up in", bare, "data-path");
hasNot("...and no language", bare, "data-lang");

// Content is escaped inside a fence -- the whole safety argument.
has("markup inside a fence cannot escape", fenceHTML("<script>", "lua"), "&lt;script&gt;");

// An unclosed fence goes back as written, opening line included: half a block
// is a typo, and swallowing it would hide it.
const unclosed = richText("intro\n```lua\nlocal x = 1");
hasNot("an unclosed fence renders no block", unclosed, "<pre");
has("...and the opening line is still visible", unclosed, "```lua");

// @example: code, not prose. Without a fence it is escaped and nothing more,
// so a backtick in a shell example stays a backtick.
check("an unfenced example is escaped only", exampleHTML("run `x` now"), esc("run `x` now"));
hasNot("...no markup is invented in it", exampleHTML("run `x` now"), "<code>");
has("a fenced example is rendered", exampleHTML("```lua\nlocal x\n```"), '<pre class="fence"');

// Strings and comments inside a fence are not decorated -- inherited from
// snipBodyHTML, asserted here because the fence is a new caller of it.
const commented = fenceHTML('-- local\nlocal s = "local"', "lua");
check("a keyword is decorated exactly once, outside string and comment",
  (commented.match(/data-kw="local"/g) || []).length, 1);

let failed = 0;
for(const r of results){
  if(!r.ok){ failed++; console.log("FAIL  " + r.name + "\n  want: " + r.want + "\n  got:  " + r.actual); }
}
console.log(failed === 0 ? "FENCE_OK " + results.length : "FENCE_FAILED " + failed);
]==]

  local tmp = vim.fn.tempname() .. ".js"
  local out = assert(io.open(tmp, "wb"))
  out:write(harness)
  out:close()

  local result = vim.system({ "node", tmp }, { text = true }):wait()
  local stdout = result.stdout or ""
  ok(
    stdout:find("FENCE_OK", 1, true) ~= nil,
    "fence: the renderer behaves — "
      .. vim.trim(stdout ~= "" and stdout or (result.stderr or "no output"))
  )
  pcall(os.remove, tmp)
end
