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

vim.api.nvim_create_user_command("AgentResume", function()
  local roster = require("agent-fleet.roster")
  local entries = roster.list({ cwd = vim.fn.getcwd() })
  if #entries == 0 then
    vim.notify("agent-fleet: no agents for this directory", vim.log.levels.INFO)
    return
  end
  vim.ui.select(entries, {
    prompt = "Resume agent",
    format_item = function(e)
      return e.name .. (e.done and "  ✓" or "")
    end,
  }, function(choice)
    if choice then
      require("agent-fleet").resume(choice.id)
    end
  end)
end, { desc = "agent-fleet: resume a past agent (current directory)" })

vim.api.nvim_create_user_command("Agents", function()
  local board = require("agent-fleet.board")
  local rows = board.rows({ cwd = vim.fn.getcwd() })
  if #rows == 0 then
    vim.notify("agent-fleet: no agents for this directory", vim.log.levels.INFO)
    return
  end
  vim.ui.select(rows, {
    prompt = "Agents",
    format_item = function(r)
      local icon = r.live and "\u{25cf}" or "\u{25cb}"
      return icon .. " " .. r.name .. (r.done and "  \u{2713}" or "")
    end,
  }, function(choice)
    if choice then
      require("agent-fleet.agent").resume_session({ id = choice.id, cwd = choice.cwd, type = "pi" })
    end
  end)
end, { desc = "agent-fleet: list & switch agents of the current directory" })
