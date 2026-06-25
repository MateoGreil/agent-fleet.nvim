local config = require("agent-fleet.config")

local M = {}

-- id -> { id, name, agent, cmd, bufnr, job, cwd, session_id }
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
--- @param meta table { id, name, kind, cmd, session_id }
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
--- @param opts table|nil { agent?: string, name?: string, cwd?: string }
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
  local name = opts.name or (kind .. "-" .. id)

  local session_id = nil
  local extra = {}
  if def.session then
    session_id = require("agent-fleet.util").uuid()
    extra = { def.session.id_flag, session_id, def.session.name_flag, name }
  end

  local agent = spawn(
    M.build_argv(def.cmd, extra),
    cwd,
    { id = id, name = name, kind = kind, cmd = def.cmd, session_id = session_id }
  )
  if not agent then
    return nil
  end

  if session_id then
    require("agent-fleet.roster").add({ id = session_id, type = kind, name = name, cwd = cwd })
  end

  return agent
end

--- Resume a past agent by its session id: focus its live buffer if still
--- running, else relaunch its pi session in its original cwd.
--- @param id string
--- @return table|nil agent
function M.resume(id)
  local cfg = config.get()

  local entry = require("agent-fleet.roster").get(id)
  if not entry then
    vim.notify("agent-fleet: unknown agent " .. tostring(id), vim.log.levels.ERROR)
    return nil
  end

  for _, agent in pairs(M.agents) do
    if agent.session_id == id and vim.api.nvim_buf_is_valid(agent.bufnr) then
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

  local matches = vim.fn.glob(cfg.sessions_dir .. "/**/*_" .. id .. ".jsonl", true, true)
  if #matches == 0 then
    vim.notify("agent-fleet: session file not found for " .. id, vim.log.levels.WARN)
    return nil
  end

  local def = cfg.agents[entry.type]
  if not def or not def.session then
    vim.notify("agent-fleet: cannot resume agent type '" .. tostring(entry.type) .. "'", vim.log.levels.ERROR)
    return nil
  end

  M._seq = M._seq + 1
  local argv = M.build_argv(def.cmd, { def.session.resume_flag, id })
  return spawn(
    argv,
    entry.cwd,
    { id = M._seq, name = entry.name, kind = entry.type, cmd = def.cmd, session_id = id }
  )
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
