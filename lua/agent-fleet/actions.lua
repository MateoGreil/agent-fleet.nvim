local M = {}

function M.current_row()
  local meta = vim.b.agent_fleet
  if not meta then
    return nil
  end
  local agent = require("agent-fleet.agent")
  local a = agent.agents[meta.id]
  if not a or not a.bufnr or not vim.api.nvim_buf_is_valid(a.bufnr) then
    return nil
  end
  if type(a.session_id) ~= "string" then
    return nil
  end
  return { id = a.session_id, name = a.name, cwd = a.cwd, live = true, bufnr = a.bufnr }
end

function M.close_live(row)
  if not row.live or not row.bufnr or not vim.api.nvim_buf_is_valid(row.bufnr) then
    return false
  end
  pcall(vim.cmd, "bdelete! " .. row.bufnr)
  return true
end

function M.done(row)
  local roster = require("agent-fleet.roster")
  roster.ensure({ id = row.id, type = row.type or "pi", name = row.name, cwd = row.cwd })
  roster.mark_done(row.id)
  M.close_live(row)
end

function M.archive(row)
  local roster = require("agent-fleet.roster")
  local now = not row.archived
  roster.ensure({ id = row.id, type = row.type or "pi", name = row.name, cwd = row.cwd })
  roster.set_archived(row.id, now)
  if now then
    M.close_live(row)
  end
  return now
end

return M
