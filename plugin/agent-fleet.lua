if vim.g.loaded_agent_fleet then
  return
end
vim.g.loaded_agent_fleet = true

vim.api.nvim_create_user_command("Agent", function(opts)
  local prompt = vim.trim(opts.args)
  if prompt ~= "" then
    require("agent-fleet").launch({ prompt = prompt })
    return
  end
  vim.ui.input({ prompt = "New agent prompt: " }, function(input)
    input = input and vim.trim(input)
    if input and input ~= "" then
      require("agent-fleet").launch({ prompt = input })
    end
  end)
end, {
  nargs = "*",
  desc = "agent-fleet: launch the default coding agent, prompting for an initial message (like the board's i key)",
})

vim.api.nvim_create_user_command("AgentsBoard", function()
  require("agent-fleet.ui").open()
end, { desc = "agent-fleet: open the board" })

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
  local now = os.time() * 1000
  vim.ui.select(rows, {
    prompt = "Agents",
    format_item = function(r)
      return require("agent-fleet.board").format_row(r, now)
    end,
  }, function(choice)
    if choice then
      require("agent-fleet.agent").resume_session({ id = choice.id, cwd = choice.cwd, type = choice.type })
    end
  end)
end, { desc = "agent-fleet: list & switch agents of the current directory" })

vim.api.nvim_create_user_command("AgentDone", function()
  local actions = require("agent-fleet.actions")
  local row = actions.current_row()
  if row then
    actions.done(row)
    vim.notify("agent-fleet: marked done \u{2014} " .. row.name, vim.log.levels.INFO)
    return
  end
  local cands = require("agent-fleet.board").done_candidates(vim.fn.getcwd())
  if #cands == 0 then
    vim.notify("agent-fleet: no agent to mark done", vim.log.levels.INFO)
    return
  end
  local now = os.time() * 1000
  vim.ui.select(cands, {
    prompt = "Mark done",
    format_item = function(row)
      return require("agent-fleet.board").format_row(row, now)
    end,
  }, function(chosen)
    if chosen then
      actions.done(chosen)
      vim.notify("agent-fleet: marked done \u{2014} " .. chosen.name, vim.log.levels.INFO)
    end
  end)
end, { desc = "agent-fleet: mark a past agent done (current directory)" })

vim.api.nvim_create_user_command("AgentArchive", function()
  local actions = require("agent-fleet.actions")
  local row = actions.current_row()
  if row then
    local now = actions.archive(row)
    vim.notify(
      ("agent-fleet: %s \u{2014} %s"):format(now and "archived" or "unarchived", row.name),
      vim.log.levels.INFO
    )
    return
  end
  local cands = require("agent-fleet.board").archive_candidates(vim.fn.getcwd())
  if #cands == 0 then
    vim.notify("agent-fleet: no agent to archive", vim.log.levels.INFO)
    return
  end
  local now = os.time() * 1000
  vim.ui.select(cands, {
    prompt = "Archive / unarchive",
    format_item = function(row)
      return require("agent-fleet.board").format_row(row, now)
    end,
  }, function(chosen)
    if chosen then
      local now = actions.archive(chosen)
      vim.notify(
        ("agent-fleet: %s \u{2014} %s"):format(now and "archived" or "unarchived", chosen.name),
        vim.log.levels.INFO
      )
    end
  end)
end, { desc = "agent-fleet: archive / unarchive a past agent (current directory)" })

vim.api.nvim_create_user_command("AgentRename", function(opts)
  local actions = require("agent-fleet.actions")

  local function apply(target, name)
    actions.rename(target, name)
    vim.notify(("agent-fleet: renamed \u{2014} %s"):format(name), vim.log.levels.INFO)
  end

  local function prompt(target)
    vim.ui.input({ prompt = "Rename agent: ", default = target.name }, function(input)
      input = input and vim.trim(input)
      if input and input ~= "" then
        apply(target, input)
      elseif input == "" then
        vim.notify("agent-fleet: rename cancelled (empty name)", vim.log.levels.INFO)
      end
    end)
  end

  local row = actions.current_row()
  if row then
    local name = vim.trim(opts.args)
    if name ~= "" then
      apply(row, name)
    else
      prompt(row)
    end
    return
  end

  local cands = require("agent-fleet.board").archive_candidates(vim.fn.getcwd())
  if #cands == 0 then
    vim.notify("agent-fleet: no agent to rename", vim.log.levels.INFO)
    return
  end
  local now = os.time() * 1000
  vim.ui.select(cands, {
    prompt = "Rename",
    format_item = function(r)
      return require("agent-fleet.board").format_row(r, now)
    end,
  }, function(chosen)
    if chosen then
      prompt(chosen)
    end
  end)
end, {
  nargs = "*",
  desc = "agent-fleet: rename an agent (current buffer or picker)",
})
