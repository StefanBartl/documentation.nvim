---@module 'documentation.core.render.sarif'
--- Drift findings as SARIF 2.1.0 — the format GitHub code scanning ingests.
---
--- The payoff is placement, not analysis: uploaded from CI, every finding
--- lands inline on the pull request that caused it, which is where a
--- `missing-summary` actually gets fixed. Nothing here computes anything;
--- `core/check.lua` already did.
---
--- ## The line number this cannot give
---
--- `docs/ROADMAP/IDEAS/IDEAS.md` §6.1 says "the findings already have file,
--- line, severity and message". Three of those four are true.
--- `Documentation.Finding` carries `severity`, `check`, `node` and
--- `message` — and **no line**. `docs/PIPELINE.md` already records the
--- consequence for diagnostics ("lands on the buffer's first line exactly
--- the way an existing quickfix jump already does") and names adding a
--- `line` field as its own separate step.
---
--- So every result here points at line 1 of the file the finding's node
--- belongs to. That is a real limitation and it is stated in the SARIF
--- itself, in the run's `invocation.properties`, rather than left for a
--- reviewer to infer from every annotation appearing at the top of a file.
--- Emitting a fabricated line would be worse: a reviewer would trust it.
---
--- ## Determinism
---
--- Written through `core/json.lua` for the same reason `module_map.json` is:
--- key order is fixed, so re-running an unchanged tree produces an
--- unchanged file. A SARIF that differs between identical runs makes every
--- upload look like new findings.

local M = {}

---SARIF's three levels, from this plugin's three severities. `info` becomes
---`note` rather than being dropped — the same decision `bindings/diagnostics`
---already made, and for the same reason: an `info` finding is the one a
---reader most often wants to see in review and least often wants to fail a
---build over.
---@type table<Documentation.Severity, string>
local LEVEL = { error = "error", warn = "warning", info = "note" }

---Where a finding points, as a repo-relative path.
---
---A node's `source` when it has one (the file that actually carries the
---defect), its `path` otherwise — a namespace has no source file, and
---pointing at the directory is more useful than pointing at nothing. `nil`
---for a finding with no node at all, which SARIF permits: a result may carry
---no location, and inventing one would put a finding on a file that has
---nothing to do with it.
---@param ir Documentation.IR
---@param finding Documentation.Finding
---@return string?
local function uri_for(ir, finding)
  if not finding.node then
    return nil
  end
  local node = ir.nodes[finding.node]
  if not node then
    -- A synthetic node id (`config.lua`'s aggregator check reports against
    -- one) is still a path-shaped string, and using it beats dropping the
    -- location.
    return finding.node
  end
  return node.source or node.path
end

---@param ir Documentation.IR
---@param findings Documentation.Finding[]
---@param opts Documentation.Opts
---@return string sarif JSON, newline-terminated.
function M.render(ir, findings, opts)
  local json = require("documentation.core.json")

  -- One rule per check id that actually occurs. Declaring every check this
  -- plugin *can* emit would list rules a reviewer never sees a result for;
  -- SARIF consumers show the rule list, so a full catalogue there reads as
  -- "these all fired".
  local rule_index, rule_ids = {}, {}
  for _, f in ipairs(findings) do
    if not rule_index[f.check] then
      rule_index[f.check] = true
      rule_ids[#rule_ids + 1] = f.check
    end
  end
  table.sort(rule_ids)

  local rules = {}
  for _, id in ipairs(rule_ids) do
    rules[#rules + 1] = {
      id = id,
      name = id,
      shortDescription = { text = id },
      helpUri = "https://github.com/StefanBartl/documentation.nvim/blob/main/docs/PIPELINE.md",
    }
  end

  local results = {}
  for _, f in ipairs(findings) do
    local result = {
      ruleId = f.check,
      level = LEVEL[f.severity] or "note",
      message = { text = f.message },
    }
    local uri = uri_for(ir, f)
    if uri then
      result.locations = {
        {
          physicalLocation = {
            artifactLocation = { uri = uri },
            -- Always 1. See this module's header: findings carry no line,
            -- and a fabricated one would be trusted.
            region = { startLine = 1 },
          },
        },
      }
    end
    results[#results + 1] = result
  end

  local run = {
    tool = {
      driver = {
        name = "documentation.nvim",
        informationUri = "https://github.com/StefanBartl/documentation.nvim",
        rules = rules,
      },
    },
    invocation = {
      executionSuccessful = true,
      properties = {
        -- Said in the artifact, not only in this file's header: a reviewer
        -- seeing every annotation at line 1 deserves to be told why rather
        -- than left to guess that the tool is broken.
        lineNumbers = "not available — findings attach to a file, not a line; "
          .. "every result points at line 1",
        -- Recorded because a finding's file path is only meaningful against
        -- the roots that were walked, and a multi-root scan has several.
        source = (function()
          local src = opts.source
          if type(src) == "table" then
            return table.concat(src, ", ")
          end
          return tostring(src)
        end)(),
      },
    },
    results = results,
  }

  return json.encode({
    ["$schema"] = "https://json.schemastore.org/sarif-2.1.0.json",
    version = "2.1.0",
    runs = { run },
  }) .. "\n"
end

return M
