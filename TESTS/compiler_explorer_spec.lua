-- TESTS/compiler_explorer_spec.lua — two functions in one clientstate, and
-- a Compiler Explorer that can be your own
--
-- The Duplicates panel raises a question it cannot answer: two functions have
-- the same structure, so do they compile to the same thing? Marking both and
-- opening them in one `clientstate` answers it — Compiler Explorer's own
-- format is an array of sessions, so this is that format used as documented.
--
-- **Same limit as `prose_render_spec.lua` and `hierarchy_gestures_spec.lua`,
-- for the same reason.** All of this runs in the browser: the generated HTML
-- contains the functions, not their results, so no Lua spec can press the
-- button. It was verified by driving the real page — a pair of the tree's own
-- structural duplicates (`checklist.read_file` and `features.read_file`)
-- produced a 726-character URL decoding to two Lua sessions, both on
-- `luac 5.4.7`, carrying those two functions; a bare `localhost:10240` was
-- refused and nothing was stored; `http://localhost:10240/` was accepted with
-- its trailing slash trimmed, retargeted both the bar and the per-function
-- triggers, and rewrote the warning; and the reset put godbolt.org back.
--
-- What a spec *can* hold is the two properties that make those true, and the
-- second one is the reason this file exists at all.
--
-- **The measurements that shaped it**, over this corpus's 232 duplicate
-- groups in 27 repositories:
--
--   * **144 of 232 groups have exactly two members** — so a pair is not a
--     special case, it is the common one.
--   * A pair of this repository's own duplicates comes to **3 104 characters
--     at the longest**, well inside godbolt.org's 8 KB request line. **Two of
--     its 17 whole groups exceed it.** Which is why marks drive this rather
--     than a "compile this group" button: the reader picks what to compare,
--     and the common pick fits.

return function(H)
  local eq, ok = H.eq, H.ok

  local path = (vim.fn.getcwd():gsub("\\", "/")) .. "/lua/documentation/core/render/html.lua"
  local fd = assert(io.open(path, "rb"), "compiler explorer spec: html.lua must be readable")
  local src = fd:read("*a")
  fd:close()

  -- ---------------------------------------------------------------------
  -- One clientstate, many sessions.
  -- ---------------------------------------------------------------------
  ok(
    src:find('if(typeof sources === "string") sources = [sources];', 1, true) ~= nil,
    "clientstate: the URL builder takes a list — one source is the list of one, "
      .. "so the single-function trigger and the compare bar cannot drift apart"
  )
  ok(
    src:find("sessions: sources.map(function(src, i){", 1, true) ~= nil,
    "clientstate: one session per source, which is Compiler Explorer's own shape"
  )
  ok(
    src:find("return { id: i + 1", 1, true) ~= nil,
    "clientstate: session ids are 1-based and distinct — two sessions sharing an "
      .. "id is one editor, not two"
  )

  -- Modules are deliberately not offered here. A module's "source" is its
  -- functions concatenated, which is already an approximation; putting one
  -- beside two functions would answer a different question in the third
  -- editor without saying so.
  ok(
    src:find('return e.kind === "fn" && e.fn && e.fn.snippet;', 1, true) ~= nil,
    "compare bar: functions with a snippet, and nothing else"
  )

  -- ---------------------------------------------------------------------
  -- **The committed page must never carry one machine's address.**
  --
  -- This is the property the whole local-instance feature has to preserve.
  -- A generated `docs/map/index.html` is committed and shared; a baked
  -- `localhost:10240` would be a link that works for its author and fails
  -- for everyone the repository is shared with, silently, in a new tab.
  --
  -- So: the default is the only host that appears in the source, and the
  -- override lives in `localStorage` — a fact about the machine the page is
  -- read on, not about the tree it describes.
  -- ---------------------------------------------------------------------
  eq(
    src:match('var CE_DEFAULT = "([^"]+)"'),
    "https://godbolt.org",
    "host: the only address baked into the page is the public one"
  )
  ok(
    src:find('var CE_LS_KEY = "docmap:compiler-explorer";', 1, true) ~= nil,
    "host: the override is a browser-local preference"
  )

  -- And it must be a real origin. A stored `javascript:` would otherwise
  -- become a click target the page built itself, which is the one thing a
  -- configurable base URL must not be able to turn into.
  local guards = 0
  for _ in src:gmatch("%^https%?:\\/\\/") do
    guards = guards + 1
  end
  ok(
    guards >= 2,
    "host: checked on the way in and on the way out — a stored value that is "
      .. "not an http(s) origin is refused when set and ignored when read ("
      .. guards
      .. " guards)"
  )

  -- ---------------------------------------------------------------------
  -- The 8 KB ceiling belongs to godbolt.org's front end, not to Compiler
  -- Explorer. Applying it to a locally-run instance would be this page
  -- inventing a restriction its target does not have, and refusing a link
  -- that would have worked.
  -- ---------------------------------------------------------------------
  ok(
    src:find("function ceTooLong(url){ return !ceIsLocal() && url.length > 8000; }", 1, true) ~= nil,
    "size limit: godbolt.org's, and only godbolt.org's"
  )
  eq(
    src:find("if(url.length > 8000)", 1, true),
    nil,
    "size limit: no call site still tests the length directly — a second copy of "
      .. "the rule is how the local instance would quietly inherit the limit again"
  )

  -- ---------------------------------------------------------------------
  -- The warning is rewritten, not relabelled.
  --
  -- "Leaves your machine" is the entire point of the notice, and it is
  -- simply untrue of an address on that machine. A warning that cries wolf
  -- is one people learn to click past — including on the pages where it is
  -- true.
  -- ---------------------------------------------------------------------
  ok(src:find("var tip = ceIsLocal()", 1, true) ~= nil, "warning: two texts, chosen by host")
  ok(
    src:find("Nothing leaves your machine, because that ", 1, true) ~= nil,
    "warning: ...and the local one says the opposite of the remote one"
  )
end
