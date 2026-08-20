---@module 'documentation.editor.browse.lookup'
--- `K` in the browser's detail pane: the glossary card for the word under the
--- cursor, from the same tables the generated page's keyword hover reads.
---
--- **The measurement moved this feature before it was written, twice.**
---
--- *Where it fires.* Counted over this repository's own browser text, a
--- glossary term appears **213 times inside an inline `` `code` `` span** and
--- **2 558 times in plain English prose** — "and", "for", "in", "not",
--- "end", "type". A `K` that answered anywhere would therefore be wrong about
--- twelve times out of thirteen, and wrong in the worst way available: a
--- correct definition attached to a word that is not code. So this asks
--- `highlight.spans` — the same span data the pane is already coloured from —
--- and answers **only inside a span**. Outside one it says why, which is a
--- key that does nothing exactly once per reader.
---
--- *Which pane.* The spans live in the detail pane, and until this landed the
--- detail pane could not be focused: the browser's keys are bound to the list
--- buffer, and `<C-w>w` from the list lands in the editor *behind* the
--- floats. That is also why two of sixteen root-level entries were
--- unreadable — 46 lines of detail in a 14-row pane, with no way to scroll.
--- `w` fixes both, and `K` is the reason it was noticed.
---
--- The key is `w` and not the `<Tab>` this was first written with: a terminal
--- sends the same byte for `<Tab>` and `<C-i>`, so that binding quietly took
--- `<C-i>` away from the browser's history. `docmap_browse_spec.lua` caught
--- it — a stepped-forward view came back as `[structure]`.

local M = {}

---Which glossary a path's language uses, or `nil` for a language with none.
---
---By extension, exactly as the page's `glossaryForPath` does — the same
---registry, so the two surfaces cannot come to different conclusions about
---what a word means.
---@param path string?
---@return Documentation.Glossary?
function M.glossary_for(path)
  if type(path) ~= "string" then
    return nil
  end
  local ext = path:match("%.([%w]+)$")
  if not ext then
    return nil
  end
  local ok, registry = pcall(require, "documentation.core.lang_registry")
  if not ok then
    return nil
  end
  return (registry.glossaries() or {})[ext:lower()]
end

---The identifier the cursor sits on, and the code span it sits in.
---
---`col` is 0-based, as `nvim_win_get_cursor` reports it. Both returns are
---`nil` when the cursor is not inside a span, which is the common case and
---not an error.
---@param line string
---@param col integer 0-based byte column.
---@return string? word The whole dotted or colon-qualified run under the cursor.
---@return { s: integer, e: integer }? span The span it was found in.
function M.word_at(line, col)
  local spans = require("documentation.editor.browse.highlight").spans(line)
  for _, span in ipairs(spans) do
    -- The backticks themselves count as inside: a cursor resting on the
    -- opening tick of `` `vim.uv` `` is pointing at that word by any reading
    -- a person would give it.
    if col >= span.s and col < span.e then
      local body = line:sub(span.s + 2, span.e - 1)
      local base = span.s + 1 -- 0-based column of the first body byte
      -- Clamped into the body, which is what makes the sentence above true:
      -- resting on a backtick is *inside* the span but outside every run, so
      -- without this the tick returned a span and no word — the opposite of
      -- what the comment promises, and what the spec caught.
      local at = math.max(base, math.min(col, base + #body - 1))
      -- Every run of identifier bytes in the span, then the one containing
      -- the cursor. Dots and colons are part of a run: `vim.fs.dirname` and
      -- `s:gsub` are single names, and stopping at the dot would look up
      -- `vim`, which means nothing on its own.
      local from = 1
      while true do
        local s, e = body:find("[%w_%.:]+", from)
        if not s then
          break
        end
        if at >= base + s - 1 and at < base + e then
          return body:sub(s, e), span
        end
        from = e + 1
      end
      -- Inside a span but on punctuation: still a span, no word.
      return nil, span
    end
  end
  return nil, nil
end

---Resolve a word against one glossary.
---
---Three shapes, in the order the page's tokenizer resolves them: the longest
---dotted prefix in `stdlib`, a whole-run keyword, and a colon call read
---through `syntax.method_namespace` (`s:gsub` → `string.gsub`). Trailing
---punctuation a doc comment writes — `vim.uv.` at the end of a sentence, or a
---call's `(` — is trimmed first.
---@param word string
---@param gl Documentation.Glossary?
---@return string? key The glossary key that matched, which is not always the word.
---@return Documentation.Glossary.Entry?
---@return string? kind `"stdlib"` or `"keyword"`.
function M.resolve(word, gl)
  if not gl or type(word) ~= "string" or word == "" then
    return nil
  end
  word = word:gsub("[%.:]+$", "")

  local ns = gl.syntax and gl.syntax.method_namespace
  local receiver, method = word:match("^([%w_%.]*):([%w_]+)$")
  if method then
    if ns then
      local key = ns .. "." .. method
      local entry = (gl.stdlib or {})[key]
      if entry then
        return key, entry, "stdlib"
      end
    end
    -- A colon call whose method the namespace does not have is not a
    -- keyword either; the receiver is a name this glossary knows nothing
    -- about, so there is nothing honest left to say.
    local _ = receiver
    return nil
  end

  local parts = vim.split(word, ".", { plain = true })
  for take = #parts, 1, -1 do
    local key = table.concat(parts, ".", 1, take)
    local entry = (gl.stdlib or {})[key]
    if entry then
      return key, entry, "stdlib"
    end
  end

  -- A keyword is a bare word by definition — `end` in `foo.end` is not Lua.
  if #parts == 1 then
    local entry = (gl.keywords or {})[word]
    if entry then
      return word, entry, "keyword"
    end
  end
  return nil
end

---The card's lines, for one resolved entry.
---
---Built as text rather than as a rendered popup so a spec can read it. The
---reference link is withheld from an entry with an `origin`, for the reason
---the glossary's own type says: sending a reader to the Lua manual for
---`vim.split` is a link that looks right and answers nothing.
---@param key string
---@param entry Documentation.Glossary.Entry
---@param kind string
---@param gl Documentation.Glossary
---@return string[]
function M.card(key, entry, kind, gl)
  local lines = { key, ("%s%s"):format(kind, entry.origin and (" · " .. entry.origin) or ""), "" }
  for _, part in ipairs({ entry.summary, entry.note }) do
    if type(part) == "string" and part ~= "" then
      for _, l in ipairs(vim.split(part, "\n", { plain = true })) do
        lines[#lines + 1] = l
      end
      lines[#lines + 1] = ""
    end
  end
  if not entry.origin and gl.reference and gl.reference.url then
    lines[#lines + 1] = ("%s: %s%s"):format(
      gl.reference.label or "reference",
      gl.reference.url,
      entry.anchor or ""
    )
  end
  return lines
end

return M
