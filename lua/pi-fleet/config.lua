local M = {}

M.defaults = {
  -- Command used to launch a pi agent. Runs in a native nvim terminal, so
  -- pi's inline rendering stays in the buffer and nvim scrollback/yank work.
  pi_cmd = "pi",
  -- Ex command that opens the agent window before it becomes a terminal.
  -- "botright vnew" = vertical split on the right; "botright new" = horizontal.
  window = "botright vnew",
  -- Drop straight into terminal insert mode after launching.
  start_insert = true,
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

function M.get()
  if vim.tbl_isempty(M.options) then
    M.setup({})
  end
  return M.options
end

return M
