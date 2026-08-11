---@module 'documentation.editor.serve'
--- A minimal HTTP server for the generated map, so the History tab can load
--- commit data on demand instead of having it baked in.
---
--- ## Why this exists at all
---
--- docmap's whole self-image up to here was "produces files, has no runtime".
--- This breaks that deliberately, for a reason that is not a preference:
--- a page opened as `file://` gets an **opaque origin** in Chrome and Firefox,
--- and `fetch()` refuses the `file:` scheme for CORS requests outright
--- (Firefox additionally isolates file origins via `privacy.file_unique_origin`
--- since FF68). `:DocMap open` opens exactly that way. So "load it when the
--- user clicks" cannot mean "read a neighbouring file" — it has to mean a
--- server, where the origin is ordinary `http://127.0.0.1:PORT` and the other
--- end can call `git` directly.
---
--- What that buys is laziness. Analysing one historical commit costs ~0.3s
--- (two `git show` reads of the committed artifact plus the pure analysis);
--- precomputing all ~90 of this repo's commits would cost 25-50s and be stale
--- the moment anything is committed. On demand, it is 0.3s per commit the
--- reader actually opens, and never stale, because git is asked at request
--- time.
---
--- ## Security posture
---
--- Small surface, but a real one — a socket and a subprocess. Three rules,
--- all enforced below rather than documented and hoped for:
---
--- 1. **Bind `127.0.0.1`, never `0.0.0.0`.** This is a personal tool on a
---    personal machine; there is no case where the network needs it.
--- 2. **Validate every `<sha>` against `^[0-9a-f]{7,40}$` before it reaches
---    git.** Without that, a request path is argument injection into a
---    subprocess. The check is a whitelist, not an escape.
--- 3. **No path parameter can leave `out_dir`.** Static serving takes a bare
---    filename, and anything containing a separator or a dot-dot is rejected
---    before it becomes a path.
---
--- Plus a lifecycle rule: the server is torn down on `VimLeavePre`, so
--- quitting the editor cannot leave a listening socket behind.
---
--- ## Why the handlers run through `vim.schedule`
---
--- libuv read callbacks are a fast-event context: `vim.system():wait()` — and
--- anything else built on `vim.wait` — cannot run there. Every request is
--- therefore parsed in the callback but *handled* on the main loop, which is
--- also what makes it safe to touch the IR and call git at all.

local M = {}

local uv = vim.uv or vim.loop

---The single running server, if any. Module-level state, which this file is
---the only owner of — the alternative (a handle the caller stores) would put
---lifecycle management on every call site for a thing there is only ever one
---of per editor session.
---@type { server: userdata, port: integer, cfg: table, clients: table<userdata, boolean>, augroup: integer? }|nil
local current = nil

---Two paths name the same repository when they normalise the same.
---
---Separator and trailing-slash only. Not `fs.canonicalize`: comparing a
---running server's root against the one just resolved must not touch the
---filesystem — the old root may have been renamed or unmounted since, and a
---comparison that can fail is worse than one that is merely textual.
---@param p string?
---@return string
local function normalize_root(p)
  return (tostring(p or ""):gsub("\\", "/"):gsub("/+$", ""))
end

---@param code integer
---@return string
local function status_text(code)
  return ({
    [200] = "OK",
    [400] = "Bad Request",
    [404] = "Not Found",
    [405] = "Method Not Allowed",
    [500] = "Internal Server Error",
  })[code] or "OK"
end

---Write one response and close. `Connection: close` on purpose: keep-alive
---would need a state machine per socket to know where one request ends and
---the next begins, and this serves a handful of requests per session.
---@param client userdata
---@param code integer
---@param content_type string
---@param body string
local function respond(client, code, content_type, body)
  if not client or client:is_closing() then
    return
  end
  local head = table.concat({
    ("HTTP/1.1 %d %s"):format(code, status_text(code)),
    "Content-Type: " .. content_type,
    "Content-Length: " .. #body,
    -- The map is local and private; no proxy or browser should keep a copy of
    -- an answer that is only true for the current working tree.
    "Cache-Control: no-store",
    "Connection: close",
    "",
    "",
  }, "\r\n")
  client:write(head .. body, function()
    if not client:is_closing() then
      client:close()
    end
  end)
end

---@param client userdata
---@param code integer
---@param message string
local function respond_error(client, code, message)
  respond(client, code, "application/json", vim.json.encode({ error = message }))
end

---Run git in the repo and return stdout, or nil plus stderr.
---
---Only ever called from a `vim.schedule`d handler — `:wait()` is `vim.wait`
---underneath and would fail in the libuv callback the request arrives on.
---@param cfg table
---@param args string[]
---@return string|nil stdout
---@return string|nil err
local function git(cfg, args)
  local cmd = { "git" }
  vim.list_extend(cmd, args)
  local proc = vim.system(cmd, { cwd = cfg.root, text = true }):wait()
  if proc.code ~= 0 then
    return nil, vim.trim(proc.stderr or "git failed")
  end
  return proc.stdout or ""
end

-- Moved to `core/api.lua`, which now owns every git-backed route and needs
-- the same validation the standalone build's own `--api=commit/<sha>`
-- parsing does. Re-exported under its old name: `TESTS/docmap_spec.lua`
-- calls `serve.safe_sha` directly, and there is no reason to make that
-- test reach into a different module for a property this one still
-- enforces before any request reaches `core.api.answer`.
M.safe_sha = require("documentation.core.api").safe_sha

---Encode one `core.api` answer as this server's JSON response.
---
---Every data route is thin on purpose: their bodies moved to `core/api.lua`
---so the standalone build can answer the identical questions for
---`docmap-desktop`'s own host, and two hosts computing the same join
---separately is exactly how they would come to disagree. What stays here is
---what is genuinely this transport's: the socket, the status code, the
---encoding, and the one thing only Neovim can supply — `git` via
---`vim.system`.
---@param client userdata
---@param name string A `core.api` route name, or `commit/<sha>`.
---@param cfg table
---@param query string|nil Raw query string, `?`-prefixed.
local function respond_api(client, name, cfg, query)
  local api = require("documentation.core.api")
  -- `snapshot=` (telemetry/loaded) and `n=` (commits) never both apply to
  -- the same route, so trying both and taking whichever is present needs
  -- no per-route branch here — each route's own doc comment says which
  -- one it reads `param` as.
  local raw = query and (query:match("[?&]snapshot=([^&]+)") or query:match("[?&]n=([^&]+)"))
  local param = api.decode_param(raw)
  cfg.git = cfg.git or git
  local result, err = api.answer(name, cfg, param)
  if not result then
    return respond_error(client, 404, err or "no such endpoint")
  end
  return respond(client, 200, "application/json", vim.json.encode(result))
end

---Accept a request path only if it is a bare filename inside `out_dir`.
---
---An empty path means `index.html`; anything containing a separator or a `..`
---segment is refused, so this route cannot be walked out of the served
---directory. The caller has already applied its own contract — this is checked
---again here rather than trusted, because it is the whole security property of
---the route.
---
---Exported for the same reason `safe_sha` is: a security property that cannot
---be tested without opening a socket does not get tested.
---@param name string Path segment from the request line, without the leading "/".
---@return string|nil filename Safe bare filename, or nil if refused.
function M.safe_static_name(name)
  if type(name) ~= "string" then
    return nil
  end
  if name == "" then
    return "index.html"
  end
  if name:find("[/\\]") or name:find("%.%.") then
    return nil
  end
  return name
end

---Serve a file out of `out_dir`.
---@param cfg table
---@param client userdata
---@param name string
local function route_static(cfg, client, name)
  name = M.safe_static_name(name)
  if not name then
    return respond_error(client, 400, "bad path")
  end

  local path = ("%s/%s/%s"):format(cfg.root, cfg.out_dir or "docs/map", name)
  local fd = io.open(path, "rb")
  if not fd then
    return respond_error(client, 404, "not found: " .. name)
  end
  local body = fd:read("*a")
  fd:close()

  local ext = name:match("%.(%w+)$") or ""
  local ctype = ({
    html = "text/html; charset=utf-8",
    json = "application/json",
    svg = "image/svg+xml",
    md = "text/plain; charset=utf-8",
    css = "text/css",
    js = "text/javascript",
  })[ext] or "application/octet-stream"

  respond(client, 200, ctype, body)
end

---Dispatch one parsed request. Runs on the main loop (see the module header).
---@param cfg table
---@param client userdata
---@param method string
---@param target string
local function handle(cfg, client, method, target)
  if method ~= "GET" then
    return respond_error(client, 405, "only GET is served")
  end

  local path, query = target:match("^([^?]*)(.*)$")
  path = path or "/"
  query = query or ""

  -- "Is a docmap server behind this origin?" — the one question the page
  -- could not answer, and the reason a *published* copy of the map showed
  -- the wrong error. `historyAvailable()` in the page tests the protocol,
  -- so on GitHub Pages (`https:`) the four server-backed panels considered
  -- themselves live, fetched, got the host's 404 and reported "Is it still
  -- running? `:DocMap serve` starts it" — advice that is simply false there.
  --
  -- Deliberately trivial and unauthenticated, like every other route here:
  -- this server binds 127.0.0.1 only, so answering "yes, I am a docmap
  -- server" tells a caller nothing it could not already tell by fetching
  -- any other endpoint.
  if path == "/api/ping" then
    return respond(client, 200, "application/json", vim.json.encode({ docmap = true }))
  end

  -- Every route `core/api.lua` owns, dispatched by name rather than one
  -- `if` per route: the set is data on that module, so a route added there
  -- reaches this host and the standalone one without either being told.
  -- `commit/<sha>` is included even though it is not a fixed key in
  -- `core.api.routes` — `M.answer` itself recognises and validates that
  -- shape, so it is enough to let anything under `/api/` fall through to
  -- it (the `/api/ping` case above already returned) and let `core.api`
  -- say no rather than re-deciding the shape here.
  if path:match("^/api/") then
    return respond_api(client, path:sub(6), cfg, query)
  end

  return route_static(cfg, client, path:gsub("^/", ""))
end

---@param cfg table
---@param client userdata
local function on_connection(cfg, client)
  local buf = ""
  client:read_start(function(err, chunk)
    if err or not chunk then
      if not client:is_closing() then
        client:close()
      end
      return
    end

    buf = buf .. chunk
    -- Wait for the full header block. Only GET is served, so there is no body
    -- to read past it — the headers are the whole request.
    if not buf:find("\r\n\r\n", 1, true) then
      -- A client that never completes a request must not be able to grow this
      -- without bound.
      if #buf > 64 * 1024 then
        client:close()
      end
      return
    end

    local method, target = buf:match("^(%u+)%s+(%S+)%s+HTTP/")
    client:read_stop()

    vim.schedule(function()
      if not method then
        return respond_error(client, 400, "malformed request")
      end
      local ok, herr = pcall(handle, cfg, client, method, target)
      if not ok then
        respond_error(client, 500, tostring(herr))
      end
    end)
  end)
end

---@return boolean
function M.is_running()
  return current ~= nil
end

---@return { port: integer, url: string, root: string }|nil
function M.info()
  if not current then
    return nil
  end
  return {
    port = current.port,
    url = ("http://127.0.0.1:%d/"):format(current.port),
    -- Which tree it answers for. Callers need this to say so, and `start`
    -- needs it to notice that the answer has gone stale.
    root = current.cfg and current.cfg.root or "",
  }
end

---Start the server. Idempotent: an already-running server is returned as is
---rather than replaced, so a second `:DocMap serve` does not silently orphan
---the first socket.
---@param cfg table A resolved `Documentation.Opts`.
---@return string|nil url
---@return string|nil err
function M.start(cfg)
  -- A running server answers for the tree it was started with, and for no
  -- other. Returning its URL for a *different* repository is the same defect
  -- `bindings/usrcmds/init.lua`'s `buffer_root` documents for `:DocMap`
  -- itself: "which project am I looking at" answered once, then silently
  -- wrong from the second invocation on.
  --
  -- Here it was worse than silent, because it looked like a bug in the map.
  -- Start the server in repository A, run `:DocMap serve` again from
  -- repository B, and the notification says "already running at
  -- http://127.0.0.1:PORT" — an URL that serves A. If A has no `docs/map`
  -- yet, opening it answers `{"error":"not found: index.html"}`, which reads
  -- as "the map is broken" rather than "you are looking at the wrong tree".
  --
  -- So: same root, same server; different root, restart on the new one. The
  -- caller is told which of the two happened so the message can name the
  -- repository, the way every other report in this plugin does.
  if current then
    local same = normalize_root(current.cfg and current.cfg.root) == normalize_root(cfg.root)
    if same then
      return M.info().url
    end
    M.stop()
  end

  local server = uv.new_tcp()
  if not server then
    return nil, "could not create a TCP handle"
  end

  -- Port 0 lets the OS pick a free one, which avoids both a hardcoded port
  -- colliding with something else and a retry loop looking for a free one.
  local ok_bind, bind_err = pcall(function()
    -- 127.0.0.1 only. Never 0.0.0.0: this is a personal tool on a personal
    -- machine, and binding wider would expose the repo's source to the
    -- network for no gain whatsoever.
    assert(server:bind("127.0.0.1", 0))
  end)
  if not ok_bind then
    server:close()
    return nil, "bind failed: " .. tostring(bind_err)
  end

  local name = server:getsockname()
  local port = name and name.port
  if not port then
    server:close()
    return nil, "could not determine the bound port"
  end

  local ok_listen, listen_err = pcall(function()
    assert(server:listen(64, function(lerr)
      if lerr then
        return
      end
      local client = uv.new_tcp()
      if not client then
        return
      end
      server:accept(client)
      on_connection(cfg, client)
    end))
  end)
  if not ok_listen then
    server:close()
    return nil, "listen failed: " .. tostring(listen_err)
  end

  -- Quitting the editor must not leave a listening socket behind. This is the
  -- lifecycle obligation that comes with having a runtime at all, so it is
  -- wired at start rather than left to the user remembering `serve stop`.
  local augroup = vim.api.nvim_create_augroup("lib_docmap_serve", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = function()
      M.stop()
    end,
    desc = "documentation.editor.serve: close the map server on exit",
  })

  current = { server = server, port = port, cfg = cfg, augroup = augroup }
  return M.info().url
end

---Stop the server. Idempotent — stopping twice, or when none ever ran, is a
---no-op rather than an error, matching `uninstall()`'s tolerance elsewhere in
---this module.
---@return boolean stopped True when a server was actually running.
function M.stop()
  if not current then
    return false
  end
  local c = current
  current = nil

  if c.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, c.augroup)
  end
  if not c.server:is_closing() then
    c.server:close()
  end
  return true
end

return M
