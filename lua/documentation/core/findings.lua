---@module 'documentation.core.findings'
--- The English message catalog, and the one place a finding becomes a
--- sentence.
---
--- **Why this exists.** Until now every check in `core/check.lua` built its
--- own English sentence with `string.format` and handed it out already
--- rendered. That is fine for exactly one locale and impossible for a
--- second: the sentence is produced deep inside the check, five layers
--- before anything knows who is reading it. `I18N.md`'s task 0 — the one it
--- calls "blocks everything, useful alone" — is to move the rendering to the
--- *edge*, so a finding travels as data and becomes text once, at the
--- quickfix list, the page, the CLI report, the markdown, the SARIF file or
--- the MCP response.
---
--- **Named placeholders, not positional ones**, and this is the whole point
--- rather than a style preference. `%s requires %s, but %s must not reach
--- into %s` cannot be translated: German, Japanese and Arabic each put those
--- four pieces in a different order, and a translator handed four anonymous
--- slots has no way to reorder them. `{from} requires {to}` can be written
--- `{to} wird von {from} …` without touching a line of Lua.
---
--- **Untranslated is visible, never invisible** (`I18N.md` rule 2.3). A key
--- with no template renders as `<check-name>` plus its parameters rather
--- than an empty string, so a check added without a catalog entry looks
--- obviously unfinished instead of silently producing a blank row. The spec
--- fails on it too — that is the gate — but the runtime behaviour still has
--- to be honest, because a catalog is exactly the kind of table that gains
--- an entry later than the code it describes.
---
--- **`message` still wins when present**, and that is not a transition
--- shim. `opts.extra_checks` is a documented extension point: another
--- repository plugs in its own checks and returns findings with prose it
--- wrote itself, and nothing here has a catalog entry for those. Such a
--- finding passes through untouched.
---
--- Findings are **not** part of `module_map.json` — `init.lua` serialises an
--- explicit whitelist and has never included them — so this change needs no
--- schema bump. The English sentences that *are* in the artifact live in
--- `quicks`, which is its own task.

local M = {}

---Message templates, keyed by finding id.
---
---The id is the finding's `check` name, except where one check has to say
---materially different things: `dead-function` reports three genuinely
---different facts and `param-name-mismatch` one, so those carry a
---`params.variant` and the key becomes `<check>.<variant>`. A variant is
---not a formatting detail — it is a different sentence, which is precisely
---what a translator needs to see as a separate entry.
---
---Every template is byte-identical to the sentence the check produced
---before this table existed. That is the acceptance criterion `I18N.md`
---sets for this task, and it is checked two ways: `findings_spec.lua`
---renders one finding per key, and the whole existing suite asserts on
---these strings in twenty-one places.
---@type table<string, string>
M.CATALOG = {
  ["missing-module-tag"] = "{file} has no ---@module annotation",
  ["missing-summary"] = "{file} has no description line",
  ["module-path-mismatch"] = "{file} declares @module '{declared}' but lives at '{expected}'",
  ["missing-readme"] = "{path} has no README.md",
  ["dead-readme-link"] = "{file} links to '{target}' which does not exist",
  ["doc-references-missing"] = "{doc}:{line} references '{text}', but {module} has no '{missing}'",
  ["sibling-reference-missing"] = "{file} references '{target}', which does not exist in the {repo} checkout",
  ["tools-spec-invalid"] = "{source}: entry #{index} is invalid — {reason}",
  ["tag-require-missing"] = "{module} is required by {who} but {prefix}'s own map does not declare it — either that require is broken, or that map predates a rename",
  ["tag-file-unavailable"] = "tag_files['{prefix}'] points at {dir}, which has no readable module_map.json — requires under '{prefix}' were not checked",
  ["unreferenced-module"] = "{module} is required by no other file in the tree",
  ["orphaned-class-alias"] = "{kind} {name} is declared in {file} and referenced by nothing in the tree",
  ["test-references-missing"] = "{file}:{line} references '{alias}.{field}', but {module} has no '{field}'",
  ["binding-conflict"] = "{what} is registered {count} times; the last one wins: {where}",
  ["unused-require"] = "{file}:{line} binds require('{module}') to '{alias}' and never uses it",
  ["example-does-not-parse"] = "{fn}'s @example is not valid Lua: {error}",
  ["consumer-require-missing"] = "{module} is required by {who} but no module here declares it — either they are broken, or their map predates a rename",
  ["require-cycle"] = "require cycle across {count} modules: {members}",
  -- The quotes are the template's, not a value's: the check used `%q` here
  -- and the acceptance criterion is byte-identity. A module name has
  -- nothing `%q` would escape beyond wrapping it.
  ["require-not-declared"] = 'requires "{module}" (line {line}), which no file in this tree declares',
  ["layer-violation"] = "{from} requires {to}, but {from_layer} must not reach into {to_layer}{why}",
  ["dead-see-target"] = "{fn}: @see target '{target}' does not resolve to a known module or function",
  ["type-vs-class"] = '{module}: local "{name}" annotated ---@type {type}, but {count} field(s) are assigned to it after its literal — LuaLS reports missing-fields/"fields cannot be injected" for this shape; use ---@class instead (---@class {module} : {type}, plus @see the type definition, if {type} should still be checked against it)',
  ["undocumented-param"] = "{fn} has {declared} parameter(s) but only {documented} @param line(s)",
  ["param-name-mismatch"] = "{fn}: @param #{index} is documented as '{documented}' but the signature declares '{actual}' at that position",
  ["dead-function.file-local"] = "{fn} is file-local and nothing in its own file mentions it",
  ["dead-function.internal"] = "{fn} is marked @internal and nothing in the tree calls it",
  ["dead-function.no-caller"] = "{fn} has no caller anywhere in the tree",
}

---Catalog key for a finding: its check name, or `<check>.<variant>` when it
---carries one.
---@param finding Documentation.Finding
---@return string
function M.key(finding)
  local variant = finding.params and finding.params.variant
  if variant then
    return finding.check .. "." .. tostring(variant)
  end
  return finding.check
end

---Substitute `{name}` placeholders from `params`.
---
---A placeholder with no matching parameter is left standing rather than
---replaced with the empty string: a template and its call site drifting
---apart is a defect, and `{who}` sitting visibly in the output says so
---where a silent gap would not. Same reasoning as rule 2.3 one level down.
---
---Values are substituted literally, and a **function** replacement is what
---makes that true: `gsub` interprets `%1`/`%%` only in a replacement
---*string*, never in what a replacement function returns. An earlier
---version escaped the value defensively and so turned a `%s` inside an
---`@example` parse error into `%%s`. Found by this module's own spec, not
---by the three-repository byte comparison — no real finding happened to
---carry a percent sign.
---@param template string
---@param params table<string, any>?
---@return string
local function interpolate(template, params)
  if not params then
    return template
  end
  return (
    template:gsub("{([%w_]+)}", function(name)
      local value = params[name]
      if value == nil then
        return "{" .. name .. "}"
      end
      return tostring(value)
    end)
  )
end

---Render one finding as a sentence.
---
---The single entry point every surface calls. Three cases, in order:
---a finding that already carries prose (an `opts.extra_checks` finding)
---keeps it; a known key is interpolated; an unknown key renders visibly
---rather than blank.
---@param finding Documentation.Finding
---@return string
function M.format(finding)
  if finding.message then
    return finding.message
  end
  local key = M.key(finding)
  local template = M.CATALOG[key]
  if not template then
    -- Deliberately not an error: a missing catalog entry must not take down
    -- a scan, and it must not be invisible either. `findings_spec.lua` is
    -- what makes it fail loudly at development time.
    local parts = {}
    for name, value in pairs(finding.params or {}) do
      if name ~= "variant" then
        parts[#parts + 1] = ("%s=%s"):format(name, tostring(value))
      end
    end
    table.sort(parts)
    return ("<%s>%s"):format(key, #parts > 0 and (" " .. table.concat(parts, " ")) or "")
  end
  return interpolate(template, finding.params)
end

return M
