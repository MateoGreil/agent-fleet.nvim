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

  vim.cmd(cfg.window)
  local bufnr = vim.api.nvim_get_current_buf()

  local job = vim.fn.jobstart(M.build_argv(def.cmd, extra), { term = true, cwd = cwd })
  if job <= 0 then
    vim.notify("agent-fleet: failed to launch '" .. def.cmd .. "'", vim.log.levels.ERROR)
    return nil
  end

  if session_id then
    require("agent-fleet.roster").add({ id = session_id, type = kind, name = name, cwd = cwd })
  end

  local agent = { id = id, name = name, agent = kind, cmd = def.cmd, bufnr = bufnr, job = job, cwd = cwd, session_id = session_id }
  M.agents[id] = agent
  vim.b[bufnr].agent_fleet = { id = id, name = name, agent = kind }
  pcall(vim.api.nvim_buf_set_name, bufnr, "agent:" .. name)

  vim.api.nvim_create_autocmd({ "BufWipeout", "TermClose" }, {
    buffer = bufnr,
    once = true,
    callback = function()
      M.agents[id] = nil
    end,
  })

  if cfg.start_insert then
    vim.cmd("startinsert")
  end

  vim.notify(("agent-fleet: launched %s (%s, cwd: %s)"):format(name, kind, cwd), vim.log.levels.INFO)
  return agent
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
