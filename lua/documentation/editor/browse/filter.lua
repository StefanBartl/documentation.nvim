---@module 'documentation.editor.browse.filter'
--- The local list filter: a typed query narrowing whatever list is currently
--- on screen, in place.
---
--- Deliberately **not** what `/` does. `/` is a fuzzy jump across every module
--- and function in the tree — it answers "take me to the thing I can name".
--- This answers "show me less of what I am already looking at", which is a
--- different question and wants a different matcher: plain case-insensitive
--- substrings, so a query means exactly what it says. Fuzzy matching is
--- forgiving, and forgiveness is wrong here — the whole point of typing
--- `-test` is that nothing containing "test" survives it.
---
--- ## Query language
---
---     fs bar        every row containing "fs" AND "bar"
---     "open url"    a phrase, spaces and all
---     -spec         no row containing "spec"
---     -"unit test"  a negated phrase
---
--- Terms are ANDed. `OR` is not supported and is not an oversight: the reason
--- to narrow a list is to make it shorter, and every `OR` makes it longer.
--- Someone who wants a union has `/`.
---
--- Lenient on purpose — this is typed live, and half a query is a normal
--- intermediate state rather than a mistake to reject. An unterminated quote
--- runs to the end of the input, and a lone `-` is dropped rather than
--- negating the next term the user has not typed yet.
---
--- ## Pure
---
--- No window, no buffer, no `vim` API — same split `trail.lua`, `diff.lua`
--- and `history.lua` follow, and the same payoff: the whole query language is
--- driven from a headless spec, and only the one key that reaches it needs
--- the UI.

local M = {}

-- `Documentation.Browse.Filter`/`.FilterTerm` are declared in
-- `browse/@types`.

---Parse a query string.
---
---Returns `nil` for anything that yields no terms — an empty string, only
---whitespace, a lone `-`. That is the same value the caller stores for "no
---filter", so clearing is submitting an empty line rather than a second key.
---@param query string?
---@return Documentation.Browse.Filter|nil
function M.parse(query)
  if type(query) ~= "string" then
    return nil
  end

  local terms = {}
  local i, n = 1, #query

  while i <= n do
    local c = query:sub(i, i)
    if c:match("%s") then
      i = i + 1
    else
      local negated = false
      if c == "-" then
        negated = true
        i = i + 1
        c = query:sub(i, i)
      end

      local text
      if c == '"' then
        i = i + 1
        local close = query:find('"', i, true)
        -- Unterminated: take the rest. The alternative is refusing to filter
        -- at all on the keystroke before the closing quote, which is the one
        -- moment the user is definitely still typing.
        text = query:sub(i, (close or n + 1) - 1)
        i = (close or n) + 1
      else
        local stop = query:find("%s", i) or (n + 1)
        text = query:sub(i, stop - 1)
        i = stop
      end

      -- A lone `-` negates nothing. Dropping it beats treating it as a
      -- literal, which would empty the list on a keystroke that reads as
      -- unfinished.
      if text ~= "" then
        terms[#terms + 1] = { text = text:lower(), negated = negated }
      end
    end
  end

  if #terms == 0 then
    return nil
  end
  return { raw = query, terms = terms }
end

---Does `text` satisfy every term?
---@param filter Documentation.Browse.Filter|nil
---@param text string?
---@return boolean
function M.matches(filter, text)
  if not filter then
    return true
  end
  local haystack = (text or ""):lower()
  for _, t in ipairs(filter.terms) do
    local hit = haystack:find(t.text, 1, true) ~= nil
    if hit == t.negated then
      return false
    end
  end
  return true
end

---Narrow a list of entries.
---
---Matched against the row's **label** — what is actually on screen — and
---nothing else. Filtering on data the row does not display would make rows
---vanish for reasons the reader cannot see, which is the failure mode this
---whole feature exists to avoid.
---
---Rows are narrowed flat: an indented Deps walk keeps each surviving row's
---original indent rather than re-laying-out the tree. That indent still
---reports the depth the row sat at, which is information; re-parenting
---survivors onto their nearest surviving ancestor would instead invent a
---relationship the graph does not have. Keeping ancestors of matches was the
---other candidate and loses on the plainer ground that it makes `-foo` fail
---to remove foo.
---@param filter Documentation.Browse.Filter|nil
---@param entries Documentation.Browse.Entry[]
---@return Documentation.Browse.Entry[] kept
---@return integer hidden
function M.apply(filter, entries)
  if not filter then
    return entries, 0
  end
  local kept, hidden = {}, 0
  for _, e in ipairs(entries) do
    if M.matches(filter, e.label) then
      kept[#kept + 1] = e
    else
      hidden = hidden + 1
    end
  end
  return kept, hidden
end

---A one-line rendering of the query, for the status line.
---
---The parsed terms rather than `raw`, so what is displayed is what is being
---applied. A status line echoing the typed string could keep showing a stray
---quote or a dropped `-` that the matcher ignored, which is exactly the sort
---of small lie that makes a filter feel unpredictable.
---@param filter Documentation.Browse.Filter|nil
---@return string|nil
function M.describe(filter)
  if not filter then
    return nil
  end
  local parts = {}
  for i, t in ipairs(filter.terms) do
    local text = t.text:find("%s") and ('"%s"'):format(t.text) or t.text
    parts[i] = (t.negated and "-" or "") .. text
  end
  return table.concat(parts, " ")
end

return M
