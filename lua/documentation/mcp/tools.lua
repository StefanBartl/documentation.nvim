---@module 'documentation.mcp.tools'
--- The tool catalogue an MCP client sees, and the only place that knows what a
--- `Documentation.Handle` can answer.
---
--- Deliberately thin. Every tool below is a projection of a method that
--- already exists on the handle (`ir`, `node`, `requires`, `required_by`,
--- `callers`, `callees`, `findings`, `rescan`) — none of them extracts
--- anything new, and none reaches past the handle into the pipeline. That is
--- the whole reason this phase was cheap: the interface was already there and
--- already tested, so the risk here is protocol drift, not analysis.
---
--- Two rules the projections follow, both about the agent's context budget
--- rather than about correctness:
---
--- 1. **Never return a raw IR node.** A node carries parser-internal and
---    render-only fields (`symbols`, `stats`, `types_detail`, `body`) that an
---    agent pays for in tokens on every call and can almost never use. Each
---    tool returns a named projection instead, so growing the IR does not
---    silently grow every tool result.
--- 2. **Everything list-shaped takes `limit`.** A `docmap_modules` over a
---    large tree is thousands of entries; an agent that wanted three of them
---    should not have to receive all of them to find out.
---
--- A third rule, load-bearing rather than a convenience, governs
--- `docmap_checklist` specifically: **there is no tool that writes
--- `@verified`.** `PROTOCOLS_AND_AGENTS.md` states the reason directly — an
--- agent that can edit a checklist's `@verified` timestamps is an agent that
--- can mark its own work as verified, and the verifying actor and the
--- verified actor must not be the same one without a human in between. The
--- catalogue below is read-only end to end; the write path is a person
--- editing Markdown, same as `core/checklist.lua`'s own header already
--- documents for every other caller of this ledger. Do not add a
--- `docmap_checklist_verify` tool without re-reading that constraint first.
---
--- Payloads are encoded by `documentation.core.json`, not `vim.json.encode`:
--- key order is then stable across runs, which makes a tool result diffable
--- and an agent's cache of one meaningful. (The JSON-RPC envelope around it is
--- plain `vim.json` — see `protocol.lua` for why the two differ.)

require("documentation.mcp.@types")

local json = require("documentation.core.json")

local M = {}

---Clamp a caller-supplied limit into something sane.
---
---`nil` means "the default", not "unlimited": an MCP client that omits the
---argument is the common case, and the common case should not be the one that
---dumps an entire tree into a context window.
---@param n any
---@param default integer
---@return integer
local function clamp_limit(n, default)
  if type(n) ~= "number" then
    return default
  end
  n = math.floor(n)
  if n < 1 then
    return 1
  end
  if n > 1000 then
    return 1000
  end
  return n
end

---One node, projected down to what an agent can act on.
---@param node Documentation.Node
---@return table
local function node_summary(node)
  return {
    id = node.id,
    kind = node.kind,
    name = node.name,
    module = node.module,
    path = node.path,
    source = node.source,
    summary = node.summary,
    parent = node.parent,
    children = node.children,
  }
end

---@param edge Documentation.Edge
---@return table
local function edge_summary(edge)
  return {
    kind = edge.kind,
    from = edge.from,
    to = edge.to,
    from_fn = edge.from_fn,
    to_fn = edge.to_fn,
    to_module = edge.to_module,
    line = edge.line,
    deferred = edge.deferred,
    confidence = edge.confidence,
  }
end

---Wrap a Lua value as an MCP tool result.
---
---MCP's `tools/call` result is a content-block list, the same shape a message
---uses — a tool cannot return raw JSON, only text (or an image, or a resource
---link) that happens to contain it. So every payload here is serialised into
---one `text` block rather than returned as structured data.
---@param value any
---@return table
local function result(value)
  return {
    content = { { type = "text", text = json.encode(value) } },
  }
end

---@type table<string, { description: string, input_schema: table, run: fun(handle: Documentation.Handle, args: table, ctx?: Documentation.Mcp.ToolCtx): table }>
local catalogue = {}

catalogue.docmap_modules = {
  description = "List modules in the scanned tree, newest scan. Returns id, kind, name, "
    .. "declared @module path and one-line summary for each. Use `prefix` to scope to a "
    .. "subtree by node id (the repo-relative path).",
  input_schema = {
    type = "object",
    properties = {
      prefix = {
        type = "string",
        description = "Only return nodes whose id starts with this repo-relative path.",
      },
      limit = {
        type = "integer",
        description = "Maximum entries to return (default 200, max 1000).",
      },
    },
  },
  run = function(handle, args)
    local ir = handle.ir()
    local limit = clamp_limit(args.limit, 200)
    local prefix = type(args.prefix) == "string" and args.prefix or nil

    -- Sorted by id rather than by iteration order: `ir.nodes` is a hash, so
    -- an unsorted walk returns a different list every run for the same tree,
    -- which makes two identical calls look like a change.
    local ids = {}
    for id in pairs(ir.nodes) do
      if not prefix or id:sub(1, #prefix) == prefix then
        ids[#ids + 1] = id
      end
    end
    table.sort(ids)

    local out = {}
    for i = 1, math.min(#ids, limit) do
      out[i] = node_summary(ir.nodes[ids[i]])
    end
    return result({ total = #ids, returned = #out, modules = out })
  end,
}

catalogue.docmap_node = {
  description = "Look up one module by node id (its repo-relative path). Returns the "
    .. "module's summary, its documented functions, and the ids it requires / is required by.",
  input_schema = {
    type = "object",
    properties = {
      id = { type = "string", description = "Node id — the repo-relative path." },
    },
    required = { "id" },
  },
  run = function(handle, args)
    local node = handle.node(args.id)
    if not node then
      error(("no such node: %s"):format(tostring(args.id)), 0)
    end

    local fns = {}
    for _, fn in ipairs(node.functions or {}) do
      fns[#fns + 1] = {
        name = fn.name,
        line = fn.line,
        documented = fn.documented,
        tested = fn.tested,
      }
    end

    local out = node_summary(node)
    out.body = node.body
    out.export = node.export
    out.functions = fns
    out.requires = node.requires
    out.required_by = node.required_by
    out.requires_external = node.requires_external
    return result(out)
  end,
}

catalogue.docmap_requires = {
  description = "Require edges out of a module — what it depends on.",
  input_schema = {
    type = "object",
    properties = { id = { type = "string", description = "Node id." } },
    required = { "id" },
  },
  run = function(handle, args)
    local out = {}
    for i, e in ipairs(handle.requires(args.id)) do
      out[i] = edge_summary(e)
    end
    return result({ id = args.id, edges = out })
  end,
}

catalogue.docmap_required_by = {
  description = "Require edges into a module — what depends on it. The question to ask "
    .. "before changing a module's exports.",
  input_schema = {
    type = "object",
    properties = { id = { type = "string", description = "Node id." } },
    required = { "id" },
  },
  run = function(handle, args)
    local out = {}
    for i, e in ipairs(handle.required_by(args.id)) do
      out[i] = edge_summary(e)
    end
    return result({ id = args.id, edges = out })
  end,
}

catalogue.docmap_callees = {
  description = "Call edges out of one function. `fn_key` is `<node id>#<declared name>`, "
    .. "e.g. `lua/documentation/init.lua#M.generate`.",
  input_schema = {
    type = "object",
    properties = {
      fn_key = { type = "string", description = "`<node id>#<declared name>`." },
    },
    required = { "fn_key" },
  },
  run = function(handle, args)
    local out = {}
    for i, e in ipairs(handle.callees(args.fn_key)) do
      out[i] = edge_summary(e)
    end
    return result({ fn_key = args.fn_key, edges = out })
  end,
}

catalogue.docmap_callers = {
  description = "Call edges into one function, same `<node id>#<declared name>` key scheme "
    .. "as docmap_callees. The question to ask before changing a signature.",
  input_schema = {
    type = "object",
    properties = {
      fn_key = { type = "string", description = "`<node id>#<declared name>`." },
    },
    required = { "fn_key" },
  },
  run = function(handle, args)
    local out = {}
    for i, e in ipairs(handle.callers(args.fn_key)) do
      out[i] = edge_summary(e)
    end
    return result({ fn_key = args.fn_key, edges = out })
  end,
}

catalogue.docmap_findings = {
  description = "Documentation drift findings from the last scan — missing summaries, "
    .. "stale references, undocumented exports. Filter by severity, check id or node.",
  input_schema = {
    type = "object",
    properties = {
      severity = {
        type = "string",
        description = "One of error, warn, info.",
        enum = { "error", "warn", "info" },
      },
      check = { type = "string", description = "Stable check id, e.g. missing-summary." },
      node = { type = "string", description = "Only findings attached to this node id." },
      limit = { type = "integer", description = "Maximum findings (default 100, max 1000)." },
    },
  },
  run = function(handle, args)
    local limit = clamp_limit(args.limit, 100)
    local matched = {}
    for _, f in ipairs(handle.findings()) do
      local keep = true
      if args.severity and f.severity ~= args.severity then
        keep = false
      end
      if args.check and f.check ~= args.check then
        keep = false
      end
      if args.node and f.node ~= args.node then
        keep = false
      end
      if keep then
        matched[#matched + 1] = {
          severity = f.severity,
          check = f.check,
          node = f.node,
          message = f.message,
        }
      end
    end

    local out = {}
    for i = 1, math.min(#matched, limit) do
      out[i] = matched[i]
    end
    return result({ total = #matched, returned = #out, findings = out })
  end,
}

catalogue.docmap_rescan = {
  description = "Re-scan the tree from disk now and return the new counts. Call this after "
    .. "editing files; every other tool answers from the scan already in memory.",
  input_schema = {
    type = "object",
    properties = {
      luals = {
        type = "boolean",
        description = "Also run lua-language-server enrichment (slower, adds type detail).",
      },
    },
  },
  run = function(handle, args)
    local ir, findings = handle.rescan({ luals = args.luals == true })
    local nodes = 0
    for _ in pairs(ir.nodes) do
      nodes = nodes + 1
    end
    local tally = require("documentation").tally(findings)
    return result({
      nodes = nodes,
      edges = #(ir.edges or {}),
      findings = { error = tally.error, warn = tally.warn, info = tally.info },
    })
  end,
}

catalogue.docmap_checklist = {
  description = "The hand-verified ledger — facts a person decided by reading the code, each "
    .. "pinned to a file (`@ref`) and dated (`@verified`). Read-only: there is no tool that "
    .. "writes `@verified` — an agent that could mark an item verified could mark its own work "
    .. "verified, so that path does not exist here; a human edits the Markdown by hand. Default "
    .. "view is stale + unverified, the same as `:DocMap checklist` with no argument. See "
    .. "docs/CHECKLIST_FORMAT.md.",
  input_schema = {
    type = "object",
    properties = {
      state = {
        type = "string",
        description = 'Only items in this state. Omit for stale + unverified. "all" for every item.',
        enum = { "stale", "unverified", "uncited", "current", "all" },
      },
      limit = {
        type = "integer",
        description = "Maximum items returned (default 100, max 1000). `counts` below always covers every item, not only the returned page.",
      },
    },
  },
  run = function(handle, args, ctx)
    local checklist = require("documentation.core.checklist")
    local ledger = handle.ir().checklist
    if not ledger then
      return result({
        available = false,
        reason = "this repository has no checklist — see docs/CHECKLIST_FORMAT.md",
      })
    end

    -- Same subprocess `bindings/usrcmds/checklist.lua` and `editor/serve.lua`
    -- run, and the same reason it is one whole-tree `git log` rather than one
    -- per cited path: a ledger with fifty items would otherwise spawn fifty
    -- processes. `handle.root` is the only path this module has to a
    -- repository at all — the MCP tool catalogue never sees `Documentation.Opts`.
    local out_dir = (ctx and ctx.out_dir) or "docs/map"
    local proc
    vim.system({
      "git",
      "log",
      "--no-merges",
      "--format=%x1e%cs",
      "--name-only",
      "--",
      ".",
      (":(exclude)%s"):format(out_dir),
    }, { cwd = handle.root, text = true }, function(res)
      proc = res
    end)
    -- Bounded the same way the usrcmd bounds it: a `git log` over a
    -- repository's full history is the slow part of this tool, and an agent
    -- waiting on a tool call needs a ceiling more than it needs patience.
    local settled = vim.wait(120000, function()
      return proc ~= nil
    end, 20)
    if not settled or not proc or proc.code ~= 0 then
      return result({
        available = false,
        reason = (
          settled and proc and vim.trim(proc.stderr or "") or "git log did not finish within 120s"
        ),
      })
    end

    local statuses = checklist.status(ledger, checklist.parse_history(proc.stdout or ""))
    local limit = clamp_limit(args.limit, 100)
    local counts = { stale = 0, unverified = 0, uncited = 0, current = 0 }

    local items = {}
    for _, status in ipairs(statuses) do
      counts[status.state] = (counts[status.state] or 0) + 1

      local keep
      if args.state == "all" then
        keep = true
      elseif args.state then
        keep = status.state == args.state
      else
        keep = status.state == "stale" or status.state == "unverified"
      end

      if keep and #items < limit then
        local item = status.item
        items[#items + 1] = {
          text = item.text,
          file = item.file,
          line = item.line,
          ref = item.ref,
          ref_line = item.ref_line,
          verified = item.verified,
          state = status.state,
          commits = status.commits,
          last_commit = status.last_commit,
        }
      end
    end

    return result({
      available = true,
      total = ledger.total,
      counts = counts,
      returned = #items,
      items = items,
    })
  end,
}

---The catalogue as MCP's `tools/list` wants it: an array, sorted by name.
---
---Sorted for the same reason `docmap_modules` sorts — a hash walk would give
---a client a different tool order on every connection, and some clients hash
---the list to decide whether their cached schema is still valid.
---@return table[]
function M.list()
  local names = {}
  for name in pairs(catalogue) do
    names[#names + 1] = name
  end
  table.sort(names)

  local out = {}
  for i, name in ipairs(names) do
    out[i] = {
      name = name,
      description = catalogue[name].description,
      inputSchema = catalogue[name].input_schema,
    }
  end
  return out
end

---Run one tool by name.
---
---Raises on an unknown name or a failing tool; `protocol.lua` turns that into
---an `isError` tool result rather than a JSON-RPC error, which is what MCP
---asks for — a tool that failed is a result the model should see and can
---react to, not a transport fault.
---@param handle Documentation.Handle
---@param name string
---@param args table?
---@param ctx Documentation.Mcp.ToolCtx? Server-level context no single handle carries — today, `out_dir`.
---@return table
---@raises string When `name` is not a known tool, or the tool itself fails.
function M.call(handle, name, args, ctx)
  local tool = catalogue[name]
  if not tool then
    error(("unknown tool: %s"):format(tostring(name)), 0)
  end
  return tool.run(handle, args or {}, ctx)
end

return M
