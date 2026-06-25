if vim.g.loaded_agent_fleet then
  return
end
vim.g.loaded_agent_fleet = true

vim.api.nvim_create_user_command("Agent", function(opts)
  require("agent-fleet").launch({ agent = opts.args ~= "" and opts.args or nil })
end, {
  nargs = "?",
  complete = function(arg_lead)
    local agents = require("agent-fleet.config").get().agents
    local keys = {}
    for key in pairs(agents) do
      if key:find(arg_lead, 1, true) == 1 then
        table.insert(keys, key)
      end
    end
    table.sort(keys)
    return keys
  end,
  desc = "agent-fleet: launch a coding agent in a terminal",
})
