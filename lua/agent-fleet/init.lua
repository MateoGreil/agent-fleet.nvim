local M = {}

function M.setup(opts)
  require("agent-fleet.config").setup(opts)
end

function M.launch(opts)
  return require("agent-fleet.agent").launch(opts)
end

function M.list()
  return require("agent-fleet.agent").list()
end

return M
