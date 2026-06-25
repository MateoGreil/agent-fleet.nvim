local M = {}

local function live_by_cwd(cwd)
  local agent = require("agent-fleet.agent")
  local result = {}
  for _, entry in pairs(agent.agents) do
    if entry.session_id ~= nil and entry.cwd == cwd then
      result[entry.session_id] = entry
    end
  end
  return result
end

local function index_by_id(items)
  local result = {}
  for _, item in ipairs(items) do
    result[item.id] = item
  end
  return result
end

function M.rows(opts)
  opts = opts or {}
  local cwd = opts.cwd or vim.fn.getcwd()
  local sessions_dir = opts.sessions_dir or require("agent-fleet.config").get().sessions_dir
  local include_archived = opts.include_archived or false

  local live = live_by_cwd(cwd)
  local disk = index_by_id(require("agent-fleet.sessions").list(cwd, sessions_dir))
  local roster = index_by_id(
    require("agent-fleet.roster").list({ cwd = cwd, include_archived = true })
  )

  local ids = {}
  local seen = {}
  local function collect(id)
    if id ~= nil and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  for id in pairs(live) do
    collect(id)
  end
  for id in pairs(disk) do
    collect(id)
  end
  for id in pairs(roster) do
    collect(id)
  end

  local rows = {}
  for _, id in ipairs(ids) do
    local live_entry = live[id]
    local disk_entry = disk[id]
    local roster_entry = roster[id]

    local is_live = false
    local bufnr = nil
    if live_entry and live_entry.bufnr and vim.api.nvim_buf_is_valid(live_entry.bufnr) then
      is_live = true
      bufnr = live_entry.bufnr
    end

    local name
    if roster_entry then
      name = roster_entry.name
    elseif live_entry then
      name = live_entry.name
    else
      name = "pi:" .. id:sub(1, 8)
    end

    local done = roster_entry and roster_entry.done or false
    local archived = roster_entry and roster_entry.archived or false

    local created_at = 0
    if disk_entry then
      created_at = disk_entry.created_at
    elseif roster_entry then
      created_at = roster_entry.created_at or 0
    end

    if include_archived or not archived then
      rows[#rows + 1] = {
        id = id,
        name = name,
        cwd = cwd,
        live = is_live,
        bufnr = bufnr,
        done = done,
        archived = archived,
        file = disk_entry and disk_entry.file or nil,
        created_at = created_at,
      }
    end
  end

  table.sort(rows, function(a, b)
    if a.archived ~= b.archived then
      return not a.archived
    end
    if a.done ~= b.done then
      return not a.done
    end
    if a.live ~= b.live then
      return a.live
    end
    return a.created_at < b.created_at
  end)

  return rows
end

function M.done_candidates(cwd)
  local rows = M.rows({ cwd = cwd or vim.fn.getcwd() })
  local result = {}
  for _, row in ipairs(rows) do
    if not row.done then
      result[#result + 1] = row
    end
  end
  return result
end

function M.archive_candidates(cwd)
  return M.rows({ cwd = cwd or vim.fn.getcwd(), include_archived = true })
end

return M
