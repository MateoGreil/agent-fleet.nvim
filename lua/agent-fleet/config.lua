local M = {}

M.presets = {
  pi = {
    cmd = "pi",
    backend = "pi",
    sessions_dir = vim.fn.expand("~/.pi/agent/sessions"),
    session = { id_flag = "--session-id", name_flag = "--name", resume_flag = "--session" },
  },
  claude = {
    cmd = "claude",
    backend = "claude",
    sessions_dir = vim.fn.expand("~/.claude/projects"),
    session = { id_flag = "--session-id", name_flag = "--name", resume_flag = "--resume" },
  },
}

M.defaults = {
  agents = {},
  window = "enew",
  start_insert = true,
  follow_output = true,
  board = {
    refresh_ms = 2000,
  },
  auto_name = {
    enabled = false,
    thinking = "off",
    namer_timeout_ms = 30000,
    max_chars = 2000,
  },
}

M.options = {}

function M.setup(opts)
  opts = opts or {}
  local merged = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)

  for key, decl in pairs(merged.agents) do
    local backend_key = decl.backend or (M.presets[key] and key)
    local base = backend_key and vim.deepcopy(M.presets[backend_key] or {}) or {}
    merged.agents[key] = vim.tbl_deep_extend("force", base, decl)
    if not merged.agents[key].backend then
      merged.agents[key].backend = "generic"
    end
    if merged.agents[key].sessions_dir then
      merged.agents[key].sessions_dir = vim.fn.expand(merged.agents[key].sessions_dir)
    end
  end

  if opts.default_agent ~= nil then
    merged.default_agent = opts.default_agent
    if not merged.agents[merged.default_agent] then
      vim.notify(
        "agent-fleet: default_agent '" .. tostring(merged.default_agent) .. "' is not declared in agents",
        vim.log.levels.ERROR
      )
    end
  else
    local count = 0
    local only_key
    for k in pairs(merged.agents) do
      count = count + 1
      only_key = k
    end
    if count == 0 then
      vim.notify(
        "agent-fleet: no agents declared; declare at least one agent in `agents = {...}`",
        vim.log.levels.ERROR
      )
    elseif count == 1 then
      merged.default_agent = only_key
    else
      vim.notify(
        "agent-fleet: multiple agents declared but no default_agent set",
        vim.log.levels.ERROR
      )
    end
  end

  M.options = merged
end

function M.get()
  if vim.tbl_isempty(M.options) then
    M.setup({})
  end
  return M.options
end

return M
