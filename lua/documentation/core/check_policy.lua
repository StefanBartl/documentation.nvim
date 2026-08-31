---@module 'documentation.core.check_policy'
--- `opts.checks` — switching a check off, or re-grading what it reports.
---
--- **The gap this closes was total, not partial.** `opts.extra_checks` could
--- *add* a check and nothing could remove or soften one, so every one of the
--- codes in `M.CODES` was all-or-nothing at the severity its call site
--- happened to raise it with. Two consequences, both measured on real trees
--- rather than imagined:
---
---   * `missing-module-tag` is an `error`, so a repository adopting this tool
---     gradually had a red `--check` from the first commit until the last
---     file was annotated — and a gate that is red for a month is a gate
---     people learn to ignore.
---   * `dead_code` reports the public API of any library, which its own
---     doc-comment says outright. The advice was "leave it off", because
---     there was no way to keep the check and quiet the six functions that
---     are published on purpose.
---
--- **A code, not a finding.** The unit is the check, not the individual
--- report: `checks = { ["undocumented-param"] = false }` is a policy someone
--- can read, while a list of suppressed sites is a file that rots silently as
--- the code moves under it. Per-site suppression is a real thing to want and
--- a different feature — it needs an anchor in the source that survives
--- editing, which a table in a config file cannot be.
---
--- **Applied after every check has run, not before.** Skipping the work would
--- be faster and would make `--check` non-deterministic in a subtle way: the
--- checks share the derived tables they build over `ir`, and several of them
--- feed counts that `core/quicks.lua` reads. Filtering the *output* keeps one
--- code path for every configuration, so a tree checked with a policy and the
--- same tree checked without one differ in exactly the findings the policy
--- names and in nothing else.
---
--- **Re-grading happens before the sort in `check.run`, deliberately.**
--- `Documentation.Finding[]` is serialized into `module_map.json` in severity
--- order and `--check` byte-compares it; a severity changed after sorting
--- would produce a list that no longer agrees with its own ordering, and two
--- runs could disagree on which of two equal-ranked findings came first.

local M = {}

---Every check code this repository raises, as a set.
---
---Transcribed from the `add(...)` call sites in `core/check.lua`, and used
---for one thing only: telling a reader that `checks = { ["dead-fn"] = false }`
---names nothing. That warning is the whole reason the list exists — a typo'd
---policy key silently doing nothing is precisely the failure mode this
---module was added to remove, and it would be embarrassing to reintroduce it
---one layer up.
---
---**A code missing from this table is not an error at runtime.** `opts.
---extra_checks` returns findings with codes this repository has never heard
---of, and a policy that could not name them would be a policy that works for
---built-in checks and quietly ignores the ones a project wrote itself. So
---this gates the *warning*, never the behaviour; see `M.validate`.
---@type table<string, true>
M.CODES = {
  ["binding-conflict"] = true,
  ["consumer-require-missing"] = true,
  ["dead-function"] = true,
  ["dead-readme-link"] = true,
  ["dead-see-target"] = true,
  ["doc-references-missing"] = true,
  ["example-does-not-parse"] = true,
  ["file-holds-many-modules"] = true,
  ["layer-violation"] = true,
  ["missing-module-tag"] = true,
  ["missing-readme"] = true,
  ["missing-summary"] = true,
  ["module-path-mismatch"] = true,
  ["orphaned-class-alias"] = true,
  ["param-name-mismatch"] = true,
  ["require-cycle"] = true,
  ["require-not-declared"] = true,
  ["sibling-reference-missing"] = true,
  ["tag-file-unavailable"] = true,
  ["tag-require-missing"] = true,
  ["test-references-missing"] = true,
  ["tools-spec-invalid"] = true,
  ["type-vs-class"] = true,
  ["undocumented-param"] = true,
  ["unreferenced-module"] = true,
  ["unused-require"] = true,
}

---@type table<string, true>
local SEVERITIES = { error = true, warn = true, info = true }

---Report policy entries that name no known check, or no known severity.
---
---Split from `M.apply` because the two have different audiences and
---different lifetimes: this runs once, when options are built, and needs a
---`notify`; `apply` runs on every check pass and must stay usable from the
---standalone build, which has no notification surface at all.
---
---Same posture as `config.build`'s unknown-key check and
---`bindings/keymaps.lua`'s unknown-action check, for the same stated reason:
---a silently dropped override is the worst outcome, because the user typed
---something, nothing happened, and nothing anywhere says why.
---@param policy table<string, boolean|Documentation.Severity>?
---@param notify table? A `lib.nvim.notify`-shaped instance (`.warn(msg)`).
function M.validate(policy, notify)
  if not notify or type(policy) ~= "table" then
    return
  end

  local unknown_code, bad_value = {}, {}
  for code, value in pairs(policy) do
    if type(code) ~= "string" or not M.CODES[code] then
      unknown_code[#unknown_code + 1] = tostring(code)
    end
    -- `true` is accepted and means "leave it alone". It is redundant, but it
    -- is what someone writes while toggling a line off and on, and warning
    -- about it would be warning about the act of using the option.
    if not (value == true or value == false or (type(value) == "string" and SEVERITIES[value])) then
      bad_value[#bad_value + 1] = ("%s = %s"):format(tostring(code), tostring(value))
    end
  end

  if #unknown_code > 0 then
    table.sort(unknown_code)
    -- Worded as "not a check this repository raises" rather than "unknown":
    -- `extra_checks` codes legitimately land here, and calling a project's
    -- own check unknown would be telling it that its own code is a typo.
    notify.warn(
      ("opts.checks: not a check documentation.nvim raises: %s  (an extra_checks code is fine here; a typo is not)"):format(
        table.concat(unknown_code, ", ")
      )
    )
  end
  if #bad_value > 0 then
    table.sort(bad_value)
    notify.warn(
      ("opts.checks: expected false, or one of error/warn/info: %s"):format(
        table.concat(bad_value, ", ")
      )
    )
  end
end

---Apply `policy` to `findings`, returning a fresh list.
---
---A new list rather than an in-place filter: `check.run` builds the input and
---owns it, but `extra_checks` contributed entries to it, and a project whose
---check function returns a cached table would find this module mutating
---something it still holds.
---
---The findings themselves are copied only when re-graded — a dropped finding
---needs no copy and an untouched one is passed through by reference, which
---keeps the common case (no policy at all) free of an allocation per finding.
---@param findings Documentation.Finding[]
---@param policy table<string, boolean|Documentation.Severity>?
---@return Documentation.Finding[]
function M.apply(findings, policy)
  if type(policy) ~= "table" or next(policy) == nil then
    return findings
  end

  local out = {}
  for _, f in ipairs(findings) do
    local rule = policy[f.check]
    if type(rule) == "string" and SEVERITIES[rule] then
      if rule == f.severity then
        out[#out + 1] = f
      else
        local copy = {}
        for k, v in pairs(f) do
          copy[k] = v
        end
        copy.severity = rule
        out[#out + 1] = copy
      end
    elseif rule ~= false then
      -- `true`, `nil`, and anything `validate` warned about: leave it alone.
      -- An invalid value must **not** be the same as `false` — silently
      -- deleting findings because a severity was misspelled is the one
      -- outcome worse than ignoring the line.
      out[#out + 1] = f
    end
    -- `rule == false` falls through appending nothing: dropped entirely,
    -- not downgraded to `info`. "Off" has to mean off — an `info` still
    -- shows in the page's Findings tab and still counts in the tally, so a
    -- reader who switched a check off and watched the number stay the same
    -- would reasonably conclude the option does not work.
  end
  return out
end

return M
