local M = {}

M.defaults = {
  -- Which configured agent to launch when none is specified.
  default_agent = "pi",
  -- Registry of agents: key -> { cmd = "<shell command>" }. Each runs in a
  -- native nvim terminal, so an inline-rendering CLI keeps its whole
  -- transcript in the buffer and nvim scrollback/yank work.
  agents = {
    pi = {
      cmd = "pi",
      session = { id_flag = "--session-id", name_flag = "--name", resume_flag = "--session" },
    },
    claude = { cmd = "claude" },
  },
  -- Ex command that opens the agent window before it becomes a terminal.
  -- "enew" = current window; "botright vnew" = vertical split on the right.
  window = "enew",
  -- Drop straight into terminal insert mode after launching.
  start_insert = true,
}

M.options = {}

function M.setup(opts)
  opts = opts or {}
  local merged = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
  -- Backward compat: pi_cmd seeds the "pi" agent's command.
  if opts.pi_cmd then
    merged.agents.pi = merged.agents.pi or {}
    merged.agents.pi.cmd = opts.pi_cmd
    merged.pi_cmd = nil
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
