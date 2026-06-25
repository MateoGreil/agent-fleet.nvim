if vim.g.loaded_agent_fleet then
  return
end
vim.g.loaded_agent_fleet = true

vim.api.nvim_create_user_command("Agent", function(opts)
  local name = vim.trim(opts.args)
  require("agent-fleet").launch({ name = name ~= "" and name or nil })
end, {
  nargs = "*",
  desc = "agent-fleet: launch the default coding agent in a terminal, optionally named",
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

vim.api.nvim_create_user_command("AgentDone", function()
  local cands = require("agent-fleet.board").done_candidates(vim.fn.getcwd())
  if #cands == 0 then
    vim.notify("agent-fleet: no agent to mark done", vim.log.levels.INFO)
    return
  end
  vim.ui.select(cands, {
    prompt = "Mark done",
    format_item = function(row)
      return (row.live and "\u{25cf} " or "\u{25cb} ") .. row.name
    end,
  }, function(row)
    if row then
      local roster = require("agent-fleet.roster")
      roster.ensure({ id = row.id, type = "pi", name = row.name, cwd = row.cwd })
      roster.mark_done(row.id)
      vim.notify("agent-fleet: marked done \u{2014} " .. row.name, vim.log.levels.INFO)
    end
  end)
end, { desc = "agent-fleet: mark a past agent done (current directory)" })

vim.api.nvim_create_user_command("AgentArchive", function()
  local cands = require("agent-fleet.board").archive_candidates(vim.fn.getcwd())
  if #cands == 0 then
    vim.notify("agent-fleet: no agent to archive", vim.log.levels.INFO)
    return
  end
  vim.ui.select(cands, {
    prompt = "Archive / unarchive",
    format_item = function(row)
      return (row.archived and "[archived] " or "") .. row.name
    end,
  }, function(row)
    if row then
      local roster = require("agent-fleet.roster")
      roster.ensure({ id = row.id, type = "pi", name = row.name, cwd = row.cwd })
      local now = not row.archived
      roster.set_archived(row.id, now)
      vim.notify(
        ("agent-fleet: %s \u{2014} %s"):format(now and "archived" or "unarchived", row.name),
        vim.log.levels.INFO
      )
    end
  end)
end, { desc = "agent-fleet: archive / unarchive a past agent (current directory)" })
