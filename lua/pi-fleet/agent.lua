local config = require("pi-fleet.config")

local M = {}

-- id -> { id, name, bufnr, job, cwd }
M.agents = {}
M._seq = 0

--- Launch a pi agent in a native terminal in a new split.
--- @param opts table|nil { name?: string, cwd?: string }
--- @return table|nil agent
function M.launch(opts)
  opts = opts or {}
  local cfg = config.get()
  local cwd = opts.cwd or vim.fn.getcwd()

  M._seq = M._seq + 1
  local id = M._seq
  local name = opts.name or ("agent-" .. id)

  vim.cmd(cfg.window)
  local bufnr = vim.api.nvim_get_current_buf()

  local job = vim.fn.jobstart(cfg.pi_cmd, { term = true, cwd = cwd })
  if job <= 0 then
    vim.notify("pi-fleet: failed to launch '" .. cfg.pi_cmd .. "'", vim.log.levels.ERROR)
    return nil
  end

  local agent = { id = id, name = name, bufnr = bufnr, job = job, cwd = cwd }
  M.agents[id] = agent
  vim.b[bufnr].pi_fleet = { id = id, name = name }

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

  vim.notify(("pi-fleet: launched %s (cwd: %s)"):format(name, cwd), vim.log.levels.INFO)
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
