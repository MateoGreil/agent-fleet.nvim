local config = require("agent-fleet.config")

local M = {}

-- id -> { id, name, agent, cmd, bufnr, job, cwd, session_id, auto_named }
M.agents = {}
M._seq = 0

--- Build an argv list from a command string and an extra-args list.
--- @param cmd string
--- @param extra string[]|nil
--- @return string[]
function M.build_argv(cmd, extra)
  local argv = vim.split(cmd, " ", { trimempty = true })
  for _, arg in ipairs(extra or {}) do
    argv[#argv + 1] = arg
  end
  return argv
end

--- Open a terminal for argv, register it, and wire cleanup.
--- @param argv string[]
--- @param cwd string
--- @param meta table { id, name, kind, cmd, session_id, auto_named }
--- @return table|nil agent
local function spawn(argv, cwd, meta)
  local cfg = config.get()

  vim.cmd(cfg.window)
  local bufnr = vim.api.nvim_get_current_buf()

  local job = vim.fn.jobstart(argv, { term = true, cwd = cwd })
  if job <= 0 then
    vim.notify("agent-fleet: failed to launch '" .. meta.cmd .. "'", vim.log.levels.ERROR)
    return nil
  end

  local agent = {
    id = meta.id,
    name = meta.name,
    agent = meta.kind,
    cmd = meta.cmd,
    bufnr = bufnr,
    job = job,
    cwd = cwd,
    session_id = meta.session_id,
    auto_named = meta.auto_named,
  }
  M.agents[meta.id] = agent
  vim.b[bufnr].agent_fleet = { id = meta.id, name = meta.name, agent = meta.kind }
  pcall(vim.api.nvim_buf_set_name, bufnr, "agent:" .. meta.name)

  vim.api.nvim_create_autocmd({ "BufWipeout", "TermClose" }, {
    buffer = bufnr,
    once = true,
    callback = function()
      M.agents[meta.id] = nil
    end,
  })

  if cfg.start_insert then
    vim.cmd("startinsert")
  end

  vim.notify(("agent-fleet: launched %s (%s, cwd: %s)"):format(meta.name, meta.kind, cwd), vim.log.levels.INFO)
  return agent
end

--- Launch a coding agent in a native terminal in the current window.
--- @param opts table|nil { agent?: string, name?: string, cwd?: string, prompt?: string }
--- @return table|nil agent
function M.launch(opts)
  opts = opts or {}
  local cfg = config.get()

  local kind = opts.agent or cfg.default_agent
  local def = cfg.agents[kind]
  if not def or not def.cmd then
    vim.notify("agent-fleet: unknown agent '" .. tostring(kind) .. "'", vim.log.levels.ERROR)
    return nil
  end

  local cwd = opts.cwd or vim.fn.getcwd()

  M._seq = M._seq + 1
  local id = M._seq
  local auto_named = opts.name == nil
  local name = opts.name
    or require("agent-fleet.autoname").default_name(opts.prompt)
    or (kind .. "-" .. id)

  local session_id = nil
  local extra = {}
  if def.session then
    session_id = require("agent-fleet.util").uuid()
    extra = { def.session.id_flag, session_id, def.session.name_flag, name }
    if type(opts.prompt) == "string" and vim.trim(opts.prompt) ~= "" then
      extra[#extra + 1] = opts.prompt
    end
  end

  local agent = spawn(
    M.build_argv(def.cmd, extra),
    cwd,
    { id = id, name = name, kind = kind, cmd = def.cmd, session_id = session_id, auto_named = auto_named }
  )
  if not agent then
    return nil
  end

  if session_id then
    require("agent-fleet.roster").add({ id = session_id, type = kind, name = name, cwd = cwd, auto_named = auto_named })
    require("agent-fleet.autoname").name_from_prompt(agent, opts.prompt)
  end

  return agent
end

--- Resume a session by spec: focus its live buffer if still running, else
--- relaunch its session in the given cwd. Works for sessions not in the
--- roster (external/disk-only).
--- @param spec table { id = string, cwd = string, type = string|nil }
--- @return table|nil agent
function M.resume_session(spec)
  local cfg = config.get()
  local kind = spec.type or "pi"

  for _, agent in pairs(M.agents) do
    if agent.session_id == spec.id and vim.api.nvim_buf_is_valid(agent.bufnr) then
      local focused = false
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_buf(win) == agent.bufnr then
          vim.api.nvim_set_current_win(win)
          focused = true
          break
        end
      end
      if not focused then
        vim.cmd("buffer " .. agent.bufnr)
      end
      return agent
    end
  end

  local def = cfg.agents[kind]
  if not def or not def.session then
    vim.notify("agent-fleet: cannot resume agent type '" .. tostring(kind) .. "'", vim.log.levels.ERROR)
    return nil
  end

  local backends = require("agent-fleet.backends")
  local backend = backends.resolve(kind)
  if backend.has_disk then
    local session_file = backend.session_file(spec.cwd, cfg.agents[kind].sessions_dir, spec.id)
    if not session_file then
      vim.notify("agent-fleet: session file not found for " .. spec.id, vim.log.levels.WARN)
      return nil
    end
  end

  local entry = require("agent-fleet.roster").get(spec.id)
  local name = entry and entry.name or (kind .. ":" .. spec.id:sub(1, 8))

  M._seq = M._seq + 1
  local argv = M.build_argv(def.cmd, { def.session.resume_flag, spec.id })
  return spawn(
    argv,
    spec.cwd,
    { id = M._seq, name = name, kind = kind, cmd = def.cmd, session_id = spec.id }
  )
end

--- Resume a past agent by its session id, using the roster for cwd/type.
--- @param id string
--- @return table|nil agent
function M.resume(id)
  local entry = require("agent-fleet.roster").get(id)
  if not entry then
    vim.notify("agent-fleet: unknown agent " .. tostring(id), vim.log.levels.ERROR)
    return nil
  end
  return M.resume_session({ id = entry.id, cwd = entry.cwd, type = entry.type })
end

--- @return table list of agents sorted by id
function M.list()
  local out = {}
  for _, agent in pairs(M.agents) do
    table.insert(out, agent)
  end
  table.sort(out, function(a, b)
    return a.id < b.id
  end)
  return out
end

return M
