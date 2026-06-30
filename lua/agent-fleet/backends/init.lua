local M = {}

local registry = {
  pi = require("agent-fleet.backends.pi"),
  generic = require("agent-fleet.backends.generic"),
}

M.generic = registry.generic

function M.resolve(type)
  local cfg = require("agent-fleet.config").get()
  local name = type
  if cfg.agents[type] and cfg.agents[type].backend then
    name = cfg.agents[type].backend
  end
  return registry[name] or registry.generic
end

return M
