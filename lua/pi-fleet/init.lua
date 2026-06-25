local M = {}

function M.setup(opts)
  require("pi-fleet.config").setup(opts)
end

function M.launch(opts)
  return require("pi-fleet.agent").launch(opts)
end

function M.list()
  return require("pi-fleet.agent").list()
end

return M
